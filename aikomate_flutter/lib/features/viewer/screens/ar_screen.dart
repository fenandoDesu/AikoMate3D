import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:ar_flutter_plugin_flutterflow/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_flutterflow/datatypes/config_planedetection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

class ArScreen extends StatefulWidget {
  const ArScreen({super.key});

  @override
  State<ArScreen> createState() => _ArScreenState();
}

class _ArScreenState extends State<ArScreen> {
  // WebView
  InAppWebViewController? _webController;
  InAppLocalhostServer? _localhostServer;
  final int _serverPort = 8081;
  bool _serverReady = false;
  bool _vrmLoaded = false;

  // AR
  ARSessionManager? _arSessionManager;
  ARObjectManager? _arObjectManager;
  bool _arReady = false;
  bool _planeDetected = false;

  // World position to pass to Three.js
  double _placeX = 0, _placeY = 0, _placeZ = -0.8;

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.android) {
      InAppWebViewController.setWebContentsDebuggingEnabled(true);
    }
    _requestPermissionsAndStart();
  }

  Future<void> _requestPermissionsAndStart() async {
    await Permission.camera.request();
    _localhostServer = InAppLocalhostServer(port: _serverPort);
    await _localhostServer!.start();
    setState(() => _serverReady = true);
  }

  @override
  void dispose() {
    _arSessionManager?.dispose();
    _localhostServer?.close();
    super.dispose();
  }

  // ── AR callbacks ────────────────────────────────────────────────────────────

  void _onARViewCreated(
    ARSessionManager sessionManager,
    ARObjectManager objectManager,
    ARAnchorManager anchorManager,
    ARLocationManager locationManager,
  ) {
    _arSessionManager = sessionManager;
    _arObjectManager = objectManager;

    _arSessionManager!.onInitialize(
      showAnimatedGuide: false,
      showFeaturePoints: false,
      showPlanes: true,          // show detected planes visually
      handlePans: false,
      handleRotation: false,
    );
    _arObjectManager!.onInitialize();

    // Listen for plane taps → place VRM there
    _arSessionManager!.onPlaneOrPointTap = (hits) {
      if (hits.isEmpty) return;
      final hit = hits.first;
      final t = hit.worldTransform;
      // Extract translation from the 4x4 column-major matrix
      _placeX = t[12];
      _placeY = t[13];
      _placeZ = t[14];
      _tryPlaceVRM();
    };

    setState(() => _arReady = true);
    debugPrint('ARView created');
  }

  void _tryPlaceVRM() {
    if (!_vrmLoaded || _webController == null) return;
    final msg = jsonEncode({
      'command': 'placeAR',
      'x': _placeX,
      'y': _placeY,
      'z': _placeZ,
    });
    _webController!.evaluateJavascript(
      source: "window.onFlutterMessage('${msg.replaceAll("'", "\\'")}')",
    );
    setState(() => _planeDetected = true);
  }

  // ── WebView ─────────────────────────────────────────────────────────────────

  void _loadVRM() {
    final url = 'http://localhost:$_serverPort/assets/web/models/UltimateLoverH1.vrm';
    final msg = jsonEncode({'command': 'loadVRM', 'url': url});
    _webController?.evaluateJavascript(
      source: "window.onFlutterMessage('$msg')",
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_serverReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Layer 1: ARCore camera + plane detection ──
          ARView(
            onARViewCreated: _onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
          ),

          // ── Layer 2: Three.js VRM renderer (transparent bg) ──
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(
                'http://localhost:$_serverPort/assets/web/index.html?mode=ar-overlay',
              ),
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              useHybridComposition: true,
              transparentBackground: true,
            ),
            onWebViewCreated: (controller) {
              _webController = controller;
              controller.addJavaScriptHandler(
                handlerName: 'FlutterBridge',
                callback: (args) {
                  final data = jsonDecode(args[0] as String);
                  final event = data['event'] as String?;
                  debugPrint('JS → Flutter: $event');
                  if (event == 'ready') _loadVRM();
                  if (event == 'vrmLoaded') {
                    _vrmLoaded = true;
                    // If user already tapped a plane, place immediately
                    if (_planeDetected) _tryPlaceVRM();
                  }
                },
              );
            },
            onConsoleMessage: (controller, msg) =>
                debugPrint('JS: ${msg.message}'),
            onPermissionRequest: (controller, request) async =>
                PermissionResponse(
                  resources: request.resources,
                  // Deny camera to WebView — ARView owns it
                  action: PermissionResponseAction.DENY,
                ),
          ),

          // ── Layer 3: HUD ──
          if (_arReady && !_planeDetected)
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Point at a surface, then tap to place',
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ),
            ),

          // ── Back button ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'back_btn',
              backgroundColor: Colors.white.withOpacity(0.9),
              onPressed: () => Navigator.pop(context),
              child: const Icon(Icons.close, color: Colors.deepPurple),
            ),
          ),
        ],
      ),
    );
  }
}