import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key});

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  InAppWebViewController? _controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: InAppWebView(
        initialFile: 'assets/web/index.html',
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          allowFileAccessFromFileURLs: true,
          allowUniversalAccessFromFileURLs: true,
          allowContentAccess: true,
        ),
        onWebViewCreated: (controller) {
          _controller = controller;
          controller.addJavaScriptHandler(
            handlerName: 'FlutterBridge',
            callback: (args) {
              final data = jsonDecode(args[0]);
              debugPrint('JS → Flutter: ${data['event']}');
              if (data['event'] == 'ready') {
                _loadVRM();
              }
            },
          );
        },
        onConsoleMessage: (controller, message) {
          debugPrint('JS console: ${message.message}');
        },
        onLoadStop: (controller, url) {
          debugPrint('Page loaded: $url');
        },
        onReceivedError: (controller, request, error) {
          debugPrint('WebView error: ${error.description} url: ${request.url}');
        },
        onReceivedHttpError: (controller, request, response) {
          debugPrint('HTTP error: ${response.statusCode} url: ${request.url}');
        },
      ),
    );
  }

  Future<void> _loadVRM() async {
    final assetData = await rootBundle.load('assets/web/models/UltimateLoverH1.vrm');
    final base64Data = base64Encode(assetData.buffer.asUint8List());
    final message = jsonEncode({
      'command': 'loadVRM',
      'fileName': 'models/UltimateLoverH1.vrm',
      'data': base64Data,
    });
    _controller?.evaluateJavascript(
      source: "window.onFlutterMessage('$message')",
    );
  }
}
