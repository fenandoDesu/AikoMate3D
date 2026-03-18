import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:convert';
import 'ar_screen.dart';

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
    const vrmUrl = 'http://localhost:8080/assets/web/models/UltimateLoverH1.vrm';
    final message = jsonEncode({'command': 'loadVRM', 'url': vrmUrl});
    _controller?.evaluateJavascript(
      source: "window.onFlutterMessage('$message')",
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_serverReady) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri('http://localhost:$_serverPort/assets/web/index.html?mode=normal'),
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
              debugPrint('WebView error: ${error.description} url: ${request.url}');
            },
            onPermissionRequest: (controller, request) async {
              return PermissionResponse(
                resources: request.resources,
                action: PermissionResponseAction.GRANT,
              );
            },
          ),

          // AR button top right
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'ar_btn',
              backgroundColor: Colors.white.withOpacity(0.9),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ArScreen()),
                );
              },
              child: const Icon(Icons.view_in_ar, color: Colors.deepPurple),
            ),
          ),
        ],
      ),
    );
  }
}