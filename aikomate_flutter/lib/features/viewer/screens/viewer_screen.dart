import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:convert';
import 'ar_screen.dart';
import 'dart:ui';
import '../../../reusable_widgets/glass.dart';

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key});

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

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
              size: 50,
              radius: 15,
              style: GlassPresets.button,
              icon: Icons.menu,
              onPressed: () {
                setState(() {
                  _showOptions = true;
                });
              },
            ),
          ),
          // AR button top right
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: GlassIconButton(
              size: 50,
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
                    color: Colors.black.withOpacity(0.3),
                    child: Center(
                      child: GestureDetector(
                        onTap: () {},
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GlassContainer(
                              style: GlassPresets.button,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                              child: const Text(
                                "Settings",
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            const SizedBox(height: 16),
                            GlassContainer(
                              style: GlassPresets.button,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                              child: const Text(
                                "Profile",
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            const SizedBox(height: 16),
                            GlassContainer(
                              style: GlassPresets.button,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                              child: const Text(
                                "Logout",
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
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
