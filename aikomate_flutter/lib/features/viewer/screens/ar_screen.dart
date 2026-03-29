import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:aikomate_flutter/features/ai_companion/ai_companion_service.dart';
import 'package:aikomate_flutter/reusable_widgets/glass.dart';

const String _speechHelperHtml = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Speech Helper</title>
</head>
<body>
  <script>
    (function () {
      const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
      let recognition = null;
      let listening = false;

      function notify(event, payload = {}) {
        if (!window.flutter_inappwebview || !window.flutter_inappwebview.callHandler) {
          return;
        }
        window.flutter_inappwebview.callHandler('FlutterBridge', JSON.stringify({
          event,
          ...payload
        }));
      }

      if (SpeechRecognition) {
        recognition = new SpeechRecognition();
        recognition.continuous = false;
        recognition.interimResults = false;
        recognition.maxAlternatives = 1;
        recognition.lang = navigator.language || 'en-US';

        recognition.onstart = () => {
          listening = true;
          notify('speechStarted');
        };

        recognition.onend = () => {
          listening = false;
          notify('speechEnded');
        };

        recognition.onerror = (event) => {
          listening = false;
          notify('speechError', { message: event.error || 'unknown' });
        };

        recognition.onresult = (event) => {
          const result = event.results[event.resultIndex];
          if (result && result[0]) {
            notify('speechTranscript', {
              transcript: result[0].transcript.trim(),
              language: result[0].language || recognition.lang || 'en-US'
            });
          }
        };
      }

      window.startSpeechRecognition = () => {
        if (!recognition || listening) return false;
        recognition.start();
        return true;
      };

      window.isSpeechRecognitionSupported = () => !!recognition;
      window.stopSpeechRecognition = () => {
        recognition?.stop();
        listening = false;
      };
    })();
  </script>
</body>
</html>
''';

class ArScreen extends StatefulWidget {
  const ArScreen({super.key});

  @override
  State<ArScreen> createState() => _ArScreenState();
}

class _ArScreenState extends State<ArScreen> {
  static const _channel = MethodChannel('com.aikomate/ar');

  late final AiCompanionService _aiService;
  StreamSubscription<String>? _logSubscription;
  InAppWebViewController? _speechController;
  bool _speechSupported = false;
  bool _isSpeechRecognitionActive = false;
  String _speechLanguage = 'en-US';
  String _statusLabel = '';

  @override
  void initState() {
    super.initState();
    _aiService = AiCompanionService();
    _logSubscription = _aiService.logStream.listen((message) {
      if (!mounted) return;
      setState(() {
        _statusLabel = message;
      });
    });
    _aiService.ensureConnected().catchError((error) {
      if (!mounted) return;
      setState(() {
        _statusLabel = 'Companion unavailable';
      });
    });
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    unawaited(_aiService.dispose());
    super.dispose();
  }

  Future<void> _openAR() async {
    await _channel.invokeMethod('openAR');
    if (mounted) Navigator.pop(context);
  }

  Future<void> _checkSpeechSupport() async {
    final controller = _speechController;
    if (controller == null) return;
    try {
      final result = await controller.evaluateJavascript(
        source: '(window.isSpeechRecognitionSupported || (() => false))();',
      );
      if (!mounted) return;
      setState(() {
        _speechSupported = _truthy(result);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _speechSupported = false;
      });
    }
  }

  void _handleSpeechBridge(Map<String, dynamic> data) {
    final event = data['event'];
    switch (event) {
      case 'speechTranscript':
        _handleSpeechTranscript(data);
        break;
      case 'speechStarted':
        if (!mounted) return;
        setState(() {
          _isSpeechRecognitionActive = true;
          _statusLabel = 'Listening...';
        });
        break;
      case 'speechEnded':
        if (!mounted) return;
        setState(() {
          _isSpeechRecognitionActive = false;
        });
        break;
      case 'speechError':
        if (!mounted) return;
        setState(() {
          _isSpeechRecognitionActive = false;
          _statusLabel = data['message'] ?? 'Speech recognition failed';
        });
        break;
    }
  }

  void _handleSpeechTranscript(Map<String, dynamic> data) {
    final transcript = (data['transcript'] as String?)?.trim();
    if (transcript == null || transcript.isEmpty) return;
    final language = data['language'] as String? ?? _speechLanguage;
    if (!mounted) return;
    setState(() {
      _speechLanguage = language;
    });
    _sendSpeechTranscript(transcript, language);
  }

  bool _truthy(dynamic value) => value == true || value == 'true';

  void _sendSpeechTranscript(String text, String language) {
    if (text.isEmpty) return;
    if (mounted) {
      setState(() {
        _statusLabel = 'Sending...';
      });
    }
    unawaited(
      _aiService
          .sendMessage(text: text, language: language)
          .then((_) {
            if (!mounted) return;
            setState(() {
              _statusLabel = 'Awaiting response...';
            });
          })
          .catchError((error) {
            if (!mounted) return;
            setState(() {
              _statusLabel = 'Companion unavailable';
            });
          }),
    );
  }

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  Future<void> _startSpeechRecognition() async {
    final micOk = await _ensureMicPermission();
    if (!micOk) {
      if (!mounted) return;
      setState(() {
        _statusLabel = 'Microphone permission required';
      });
      return;
    }

    if (!_speechSupported) {
      if (!mounted) return;
      setState(() {
        _statusLabel = 'Speech recognition unavailable';
      });
      return;
    }

    if (_isSpeechRecognitionActive) return;

    try {
      final result = await _speechController?.evaluateJavascript(
        source:
            'typeof window.startSpeechRecognition === "function" && window.startSpeechRecognition();',
      );
      if (!mounted) return;
      if (!_truthy(result)) {
        setState(() {
          _statusLabel = 'Speech recognition failed to start';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusLabel = 'Speech recognition error';
      });
    }
  }

  String _buildStatusHint(AiCompanionConnectionState state) {
    final label = _connectionLabel(state);
    final pieces = <String>[];
    if (label.isNotEmpty) pieces.add(label);
    if (_statusLabel.isNotEmpty) pieces.add(_statusLabel);
    return pieces.join(' · ');
  }

  String _connectionLabel(AiCompanionConnectionState state) {
    switch (state) {
      case AiCompanionConnectionState.connecting:
        return 'Connecting to companion';
      case AiCompanionConnectionState.ready:
        return 'Companion ready';
      case AiCompanionConnectionState.error:
        return 'Companion error';
      case AiCompanionConnectionState.idle:
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF050B20),
                  Color(0xFF0F2038),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: GlassIconButton(
                adaptiveIconSize: true,
                padding: const EdgeInsets.all(8),
                size: 55,
                radius: 15,
                style: GlassPresets.button,
                icon: Icons.view_in_ar,
                onPressed: _openAR,
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<AiCompanionConnectionState>(
                  valueListenable: _aiService.connectionState,
                  builder: (context, state, _) {
                    final hint = _buildStatusHint(state);
                    return Text(
                      hint.isNotEmpty ? hint : 'Tap the mic and speak to begin',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  _statusLabel.isNotEmpty
                      ? _statusLabel
                      : 'Only voice input is available here',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: GlassIconButton(
                  adaptiveIconSize: true,
                  padding: const EdgeInsets.all(16),
                  size: 90,
                  radius: 45,
                  style: GlassPresets.button,
                  icon: Icons.mic,
                  onPressed: _startSpeechRecognition,
                ),
              ),
            ),
          ),
          Offstage(
            offstage: true,
            child: SizedBox(
              height: 0,
              width: 0,
              child: InAppWebView(
                initialData: InAppWebViewInitialData(data: _speechHelperHtml),
                onWebViewCreated: (controller) {
                  _speechController = controller;
                  controller.addJavaScriptHandler(
                    handlerName: 'FlutterBridge',
                    callback: (args) {
                      if (args.isEmpty) return;
                      try {
                        final data = jsonDecode(args[0]);
                        _handleSpeechBridge(data);
                      } catch (_) {
                        // ignore malformed events
                      }
                    },
                  );
                },
                onLoadStop: (controller, _) {
                  _speechController = controller;
                  unawaited(_checkSpeechSupport());
                },
                onPermissionRequest: (controller, request) async {
                  return PermissionResponse(
                    resources: request.resources,
                    action: PermissionResponseAction.GRANT,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
