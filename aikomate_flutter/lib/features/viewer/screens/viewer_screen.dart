import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:convert';
import 'ar_screen.dart';
import '../../../reusable_widgets/glass.dart';
import '../../../menu_sections_pages/login.dart';
import '../../../menu_sections_pages/signup.dart';

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key});

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

enum OverlayView { menu, login, signup }

OverlayView _overlayView = OverlayView.menu;

class _ViewerScreenState extends State<ViewerScreen> {
  InAppWebViewController? _controller;
  InAppLocalhostServer? _localhostServer;
  final int _serverPort = 8080;
  bool _serverReady = false;
  bool _showOptions = false;

  @override
  void initState() {
    super.initState();
    _startServer();
  }

  Future<void> _startServer() async {
    _localhostServer = InAppLocalhostServer(port: _serverPort);
    await _localhostServer!.start();
    setState(() => _serverReady = true);
  }

  @override
  void dispose() {
    _localhostServer?.close();
    super.dispose();
  }

  void _loadVRM() {
    const vrmUrl =
        'http://localhost:8080/assets/web/models/UltimateLoverH1.vrm';
    final message = jsonEncode({'command': 'loadVRM', 'url': vrmUrl});
    _controller?.evaluateJavascript(
      source: "window.onFlutterMessage('$message')",
    );
  }

  Widget _buildOption(IconData icon, {VoidCallback? onTap}) {
    return GlassIconButton(
      adaptiveIconSize: true,
      size: 50,
      radius: 15,
      padding: EdgeInsets.all(12),
      style: GlassPresets.button,
      icon: icon,
      onPressed: onTap ?? () {},
    );
  }

  Widget _buildOverlayContent() {
    switch (_overlayView) {
      case OverlayView.menu:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: GridView.count(
            key: const ValueKey("menu"),
            shrinkWrap: true,
            crossAxisCount: 4,
            mainAxisSpacing: 20,
            crossAxisSpacing: 20,
            children: [
              _buildOption(
                Icons.account_circle_outlined,
                onTap: () {
                  setState(() => _overlayView = OverlayView.login);
                },
              ),
              _buildOption(Icons.shopping_bag_outlined),
              _buildOption(Icons.wallpaper_outlined),
              _buildOption(Icons.question_answer_outlined),
              _buildOption(Icons.diversity_1_outlined),
              _buildOption(Icons.record_voice_over_outlined),
              _buildOption(Icons.translate_outlined),
              _buildOption(Icons.settings_outlined),
            ],
          ),
        );

      case OverlayView.login:
        return LoginView(
          key: const ValueKey("login"),
          onBack: () {
            setState(() => _overlayView = OverlayView.menu);
          },
          onSignup: () {
            setState(() => _overlayView = OverlayView.signup);
          },
        );

      case OverlayView.signup:
        return SignupView(
          key: const ValueKey("signup"),
          onBack: () {
            setState(() => _overlayView = OverlayView.login);
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_serverReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(
                'http://localhost:$_serverPort/assets/web/index.html?mode=normal',
              ),
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
            ),
            onWebViewCreated: (controller) {
              _controller = controller;
              controller.addJavaScriptHandler(
                handlerName: 'FlutterBridge',
                callback: (args) {
                  final data = jsonDecode(args[0]);
                  debugPrint('JS → Flutter: ${data['event']}');
                  if (data['event'] == 'ready') _loadVRM();
                },
              );
            },
            onConsoleMessage: (controller, message) {
              debugPrint('JS console: ${message.message}');
            },
            onReceivedError: (controller, request, error) {
              debugPrint(
                'WebView error: ${error.description} url: ${request.url}',
              );
            },
            onPermissionRequest: (controller, request) async {
              return PermissionResponse(
                resources: request.resources,
                action: PermissionResponseAction.GRANT,
              );
            },
          ),

          // options button top left
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            child: GlassIconButton(
              adaptiveIconSize: true,
              padding: EdgeInsets.all(8),
              size: 55,
              radius: 15,
              style: GlassPresets.button,
              icon: Icons.menu,
              onPressed: () {
                setState(() {
                  _showOptions = true; 
                  _overlayView = OverlayView.menu; // reset to menu
                });
              },
            ),
          ),
          // AR button top right
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: GlassIconButton(
              adaptiveIconSize: true,
              padding: EdgeInsets.all(8),
              size: 55,
              radius: 15,
              style: GlassPresets.button,
              icon: Icons.view_in_ar,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ArScreen()),
                );
              },
            ),
          ),
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: GlassContainer(
                  style: GlassPresets.chatBar,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: "Type a message...",
                            hintStyle: TextStyle(color: Colors.white70),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        color: Colors.white.withOpacity(0.9),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(Icons.mic),
                        color: Colors.white.withOpacity(0.9),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_showOptions)
            Positioned.fill(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _showOptions ? 1 : 0,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _showOptions = false;
                    });
                  },
                  child: Container(
                    color: Colors.black.withOpacity(0.6),
                    child: Center(
                      child: GestureDetector(
                        onTap: () {},
                        child: SizedBox(
                          width: double.infinity,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: _buildOverlayContent(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
