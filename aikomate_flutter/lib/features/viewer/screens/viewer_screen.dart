import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:aikomate_flutter/features/ai_companion/ai_companion_service.dart';
import 'package:aikomate_flutter/core/config/env.dart';
import 'package:aikomate_flutter/core/auth/google_sign_in_service.dart';
import 'package:aikomate_flutter/core/storage/secure_storage.dart';
import 'package:aikomate_flutter/reusable_widgets/glass.dart';
import 'package:aikomate_flutter/menu_sections_pages/login.dart';
import 'package:aikomate_flutter/menu_sections_pages/signup.dart';
import 'package:aikomate_flutter/menu_sections_pages/profile.dart';
import 'package:aikomate_flutter/menu_sections_pages/history.dart';
import 'package:aikomate_flutter/menu_sections_pages/background.dart';
import 'package:aikomate_flutter/core/api/auth_api.dart';
import 'package:aikomate_flutter/core/storage/settings_storage.dart';
import 'package:aikomate_flutter/features/viewer/user_background_loopback.dart';
import 'package:aikomate_flutter/features/viewer/viewer_launch_args.dart';
import 'package:aikomate_flutter/features/viewer/vrm_remote_loopback_cache.dart';
import 'package:aikomate_flutter/features/viewer/widgets/intimacy_thermometer.dart';

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key, this.launchArgs});

  /// When set (e.g. from Discover), loads this template’s VRM URL and persona.
  final ViewerLaunchArgs? launchArgs;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

enum OverlayView { menu, login, signup, profile, history, background }

OverlayView _overlayView = OverlayView.menu;

class _ViewerScreenState extends State<ViewerScreen> {
  static const _arChannel = MethodChannel('com.aikomate/ar');
  InAppWebViewController? _controller;
  InAppLocalhostServer? _localhostServer;
  final int _serverPort = 8080;
  bool _serverReady = false;
  bool _showOptions = false;
  late final AiCompanionService _aiService;
  final TextEditingController _messageController = TextEditingController();
  StreamSubscription<String>? _logSubscription;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  bool _speechSupported = false;
  bool _isSpeechRecognitionActive = false;
  String _speechLanguage = 'en-US';
  String _statusLabel = '';
  final List<Map<String, dynamic>> _pendingWebEvents = [];
  int? _petPointerId;

  final UserBackgroundLoopback _userBackgroundLoopback =
      UserBackgroundLoopback();

  final VrmRemoteLoopbackCache _vrmRemoteCache = VrmRemoteLoopbackCache();

  /// True while Dart is downloading a remote `.vrm` to bypass browser CORS.
  bool _vrmDownloading = false;
  double? _vrmDownloadFraction;
  String _vrmOverlayCaption = '';

  @override
  void initState() {
    super.initState();
    final a = widget.launchArgs;
    _aiService = AiCompanionService(
      avatarName:
          (a?.displayName.trim().isNotEmpty ?? false)
              ? a!.displayName.trim()
              : 'Haruna',
      userName:
          (a?.userName?.trim().isNotEmpty ?? false)
              ? a!.userName!.trim()
              : 'Fernando',
      personalityPrompt: a?.personalityPrompt,
    );
    _logSubscription = _aiService.logStream.listen((message) {
      if (!mounted) return;
      setState(() {
        _statusLabel = message;
      });
    });
    _eventSubscription = _aiService.eventStream.listen((event) {
      _queueWebEvent(event);
    });
    _aiService.ensureConnected().catchError((error) {
      if (!mounted) return;
      setState(() {
        _statusLabel = "AI companion unavailable";
      });
    });

    _startServer();
  }

  Future<void> _startServer() async {
    _localhostServer = InAppLocalhostServer(port: _serverPort);
    await _localhostServer!.start();
    setState(() => _serverReady = true);
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _eventSubscription?.cancel();
    unawaited(_aiService.dispose());
    _messageController.dispose();
    _localhostServer?.close();
    _userBackgroundLoopback.dispose();
    _vrmRemoteCache.dispose();
    super.dispose();
  }

  String _bundledVrmHttpUrl() =>
      'http://localhost:$_serverPort/assets/web/models/UltimateLoverH1.vrm';

  bool _isLoopbackHost(Uri uri) {
    final h = uri.host.toLowerCase();
    return h == 'localhost' || h == '127.0.0.1';
  }

  /// Remote CDN URLs fail CORS from `http://localhost:8080`; download in Dart
  /// and serve from a second loopback server with CORS headers.
  Future<void> _prepareAndLoadVrm() async {
    final remote = widget.launchArgs?.vrmUrl.trim();
    final fallback = _bundledVrmHttpUrl();
    String urlToLoad;

    if (remote == null || remote.isEmpty) {
      urlToLoad = fallback;
    } else {
      final parsed = Uri.tryParse(remote);
      if (parsed != null && _isLoopbackHost(parsed)) {
        urlToLoad = remote;
      } else {
        if (!mounted) return;
        setState(() {
          _vrmDownloading = true;
          _vrmDownloadFraction = null;
          _vrmOverlayCaption = 'Preparing avatar…';
          _statusLabel = 'Preparing avatar…';
        });
        try {
          urlToLoad = await _vrmRemoteCache.cacheFromRemoteUrl(
            remote,
            templateId: widget.launchArgs?.templateId,
            onSource: ({required bool fromSealedStore}) {
              if (!mounted) return;
              setState(() {
                _vrmOverlayCaption =
                    fromSealedStore
                        ? 'Loading saved avatar…'
                        : 'Downloading avatar…';
                _statusLabel = _vrmOverlayCaption;
              });
            },
            onProgress: (f) {
              if (!mounted) return;
              setState(() => _vrmDownloadFraction = f);
            },
          );
        } catch (e, st) {
          debugPrint('VRM proxy download failed: $e\n$st');
          if (mounted) {
            setState(() {
              _statusLabel = 'Avatar download failed; using default model';
            });
          }
          urlToLoad = fallback;
        } finally {
          if (mounted) {
            setState(() {
              _vrmDownloading = false;
              _vrmDownloadFraction = null;
              _vrmOverlayCaption = '';
            });
          }
        }
      }
    }

    if (!mounted) return;
    _queueWebEvent({'command': 'loadVRM', 'url': urlToLoad});
    if (urlToLoad != fallback) {
      setState(() => _statusLabel = 'Loading avatar in 3D…');
    }
  }

  Future<void> _loadSavedBackground() async {
    final settings = await SettingsStorage.readAll();
    final bg = settings["background"];
    if (bg is Map) {
      final config = BackgroundConfig.fromJson(
        bg.map((k, v) => MapEntry(k.toString(), v)),
      );
      await _applyBackground(config);
    }
  }

  void _sendWebEvent(
    InAppWebViewController controller,
    Map<String, dynamic> event,
  ) {
    final payload = jsonEncode(event);
    final jsStringArg = jsonEncode(payload);
    controller.evaluateJavascript(
      source: 'window.onFlutterMessage($jsStringArg)',
    );
  }

  void _queueWebEvent(Map<String, dynamic> event) {
    final controller = _controller;
    if (controller == null) {
      _pendingWebEvents.add(event);
      return;
    }
    _sendWebEvent(controller, event);
  }

  bool get _petInputEnabled => !_showOptions;

  void _onPetPointerDown(PointerDownEvent event) {
    if (!_petInputEnabled || _petPointerId != null) return;
    _petPointerId = event.pointer;
    _queueWebEvent({
      "command": "petInputStart",
      "x": event.localPosition.dx,
      "y": event.localPosition.dy,
    });
  }

  void _onPetPointerMove(PointerMoveEvent event) {
    if (!_petInputEnabled || _petPointerId != event.pointer) return;
    _queueWebEvent({
      "command": "petInputMove",
      "x": event.localPosition.dx,
      "y": event.localPosition.dy,
    });
  }

  void _onPetPointerEnd(int pointer) {
    if (_petPointerId != pointer) return;
    _petPointerId = null;
    _queueWebEvent({"command": "petInputEnd"});
  }

  void _flushPendingWebEvents() {
    final controller = _controller;
    if (controller == null || _pendingWebEvents.isEmpty) return;
    final pending = List<Map<String, dynamic>>.from(_pendingWebEvents);
    _pendingWebEvents.clear();
    for (final event in pending) {
      _sendWebEvent(controller, event);
    }
  }

  Future<String> _resolveBackgroundWebUrl(BackgroundConfig config) async {
    final trimmed = config.url.trim();
    if (trimmed.isEmpty) return "";
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final deviceHttp = await _userBackgroundLoopback.toHttpUrlIfDeviceFile(
      trimmed,
    );
    if (deviceHttp != null) {
      return deviceHttp;
    }
    if (trimmed.startsWith('assets/web/')) {
      return 'http://localhost:$_serverPort/$trimmed';
    }
    if (!trimmed.startsWith('/') && !trimmed.contains('://')) {
      return 'http://localhost:$_serverPort/assets/web/$trimmed';
    }
    return trimmed;
  }

  Future<void> _applyBackground(BackgroundConfig config) async {
    final url = await _resolveBackgroundWebUrl(config);
    _queueWebEvent({
      "command": "setBackground",
      "type": config.type,
      "url": url,
      "focusX": config.imageFocusX,
      "focusY": config.imageFocusY,
      "zoom": config.imageZoom,
    });
  }

  Future<void> _checkSpeechSupport() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final result = await controller.evaluateJavascript(
        source: '(window.isSpeechRecognitionSupported || (() => false))();',
      );
      if (!mounted) return;
      setState(() {
        _speechSupported = _truthy(result);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _speechSupported = false;
      });
    }
  }

  void _handleFlutterMessage(Map<String, dynamic> data) {
    final event = data['event'];
    switch (event) {
      case 'ready':
        unawaited(_prepareAndLoadVrm());
        unawaited(_checkSpeechSupport());
        _flushPendingWebEvents();
        _queueWebEvent({
          "command": "setIntimacy",
          "value": _aiService.intimacy.value,
        });
        unawaited(_loadSavedBackground());
        break;
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
        setState(() => _isSpeechRecognitionActive = false);
        break;
      case 'speechError':
        if (!mounted) return;
        setState(() {
          _isSpeechRecognitionActive = false;
          _statusLabel = data['message'] ?? 'Speech recognition failed';
        });
        break;
      case 'petRub':
        unawaited(_triggerPetRubHaptic());
        break;
      case 'intimacy_update':
        final raw = data['intimacy'];
        if (raw is num) {
          _aiService.intimacy.value = raw.round().clamp(0, 5);
        }
        break;
      case 'vrmLoaded':
        if (!mounted) return;
        setState(() => _statusLabel = 'Avatar ready');
        break;
      case 'vrmError':
        if (!mounted) return;
        setState(() {
          _statusLabel =
              'Avatar load failed: ${data['error'] ?? 'unknown error'}';
        });
        break;
    }
  }

  Future<void> _triggerPetRubHaptic() async {
    try {
      await HapticFeedback.vibrate();
      await HapticFeedback.lightImpact();
    } catch (_) {
      // Ignore unsupported haptics on this device/runtime.
    }
  }

  void _handleSpeechTranscript(Map<String, dynamic> data) {
    final transcript = (data['transcript'] as String?)?.trim();
    if (transcript == null || transcript.isEmpty) return;
    final language = data['language'] as String? ?? _speechLanguage;
    if (!mounted) return;
    setState(() {
      _speechLanguage = language;
      _messageController.text = transcript;
      _messageController.selection = TextSelection.collapsed(
        offset: transcript.length,
      );
    });
    _sendMessageFromText(triggeredBySpeech: true);
  }

  bool _truthy(dynamic value) => value == true || value == 'true';

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  void _sendMessageFromText({bool triggeredBySpeech = false}) {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    if (mounted) {
      setState(() {
        _statusLabel = 'Sending...';
      });
    }

    unawaited(
      _aiService
          .sendMessage(text: text, language: _speechLanguage)
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

    _messageController.clear();
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
      final result = await _controller?.evaluateJavascript(
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

  Future<void> _openAR() async {
    try {
      final token = await SecureStorage.getToken();
      if (token == null) {
        if (!mounted) return;
        setState(() {
          _statusLabel = 'Missing auth token';
        });
        return;
      }
      await _arChannel.invokeMethod('openAR', {
        'token': token,
        'wsUrl': Env.chatWsUrl,
        'avatarName': _aiService.avatarName,
        'userName': _aiService.userName,
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusLabel = 'Failed to open AR';
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
        return '';
    }
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
                onTap: () async {
                  final result = await auth();

                  if (!mounted) return;

                  if (result.success) {
                    setState(() {
                      _overlayView = OverlayView.profile;
                    });
                  } else {
                    setState(() {
                      _overlayView = OverlayView.login;
                    });
                  }
                },
              ),
              _buildOption(Icons.shopping_bag_outlined),
              _buildOption(
                Icons.wallpaper_outlined,
                onTap: () async {
                  setState(() {
                    _overlayView = OverlayView.background;
                  });
                },
              ),
              _buildOption(
                Icons.question_answer_outlined,
                onTap: () async {
                  final result = await auth();

                  if (result.success) {
                    setState(() {
                      _overlayView = OverlayView.history;
                    });
                  } else {
                    setState(() {
                      _overlayView = OverlayView.login;
                    });
                  }
                },
              ),
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
          onLoginSuccess: () {
            setState(() {
              _overlayView = OverlayView.profile;
              _showOptions = true; // optional but nice UX
            });
          },
        );
      case OverlayView.signup:
        return SignupView(
          key: const ValueKey("signup"),
          onBack: () {
            setState(() => _overlayView = OverlayView.login);
          },
          onLogin: () {
            setState(() => _overlayView = OverlayView.login);
          },
          onSignupSuccess: () {
            setState(() {
              _overlayView = OverlayView.profile;
              _showOptions = true;
            });
          },
        );
      case OverlayView.profile:
        return ProfileView(
          key: const ValueKey("profile"),
          onBack: () {
            setState(() => _overlayView = OverlayView.menu);
          },
          onLogout: () async {
            await SecureStorage.deleteToken();
            await GoogleSignInService.instance.signOut();
            if (!mounted) return;
            setState(() {
              _overlayView = OverlayView.menu;
              _showOptions = false;
            });
          },
        );
      case OverlayView.history:
        return HistoryView(
          key: const ValueKey("history"),
          onBack: () {
            setState(() => _overlayView = OverlayView.menu);
          },
        );
      case OverlayView.background:
        return BackgroundView(
          key: const ValueKey("background"),
          onBack: () {
            setState(() => _overlayView = OverlayView.menu);
          },
          onApply: (config) {
            unawaited(_applyBackground(config));
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
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(
                  'http://localhost:$_serverPort/assets/web/index.html?mode=normal',
                ),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                disableVerticalScroll: true,
                disableHorizontalScroll: true,
                disallowOverScroll: true,
                alwaysBounceVertical: false,
                alwaysBounceHorizontal: false,
                supportZoom: false,
                builtInZoomControls: false,
                displayZoomControls: false,
                overScrollMode: OverScrollMode.NEVER,
                verticalScrollBarEnabled: false,
                horizontalScrollBarEnabled: false,
              ),
              onWebViewCreated: (controller) {
                _controller = controller;
                if (_pendingWebEvents.isNotEmpty) {
                  final pending = List<Map<String, dynamic>>.from(
                    _pendingWebEvents,
                  );
                  _pendingWebEvents.clear();
                  for (final event in pending) {
                    _sendWebEvent(controller, event);
                  }
                }
                controller.addJavaScriptHandler(
                  handlerName: 'FlutterBridge',
                  callback: (args) {
                    if (args.isEmpty) return;
                    try {
                      final data = jsonDecode(args[0]);
                      debugPrint('JS -> Flutter: ${data['event']}');
                      _handleFlutterMessage(data);
                    } catch (error) {
                      debugPrint('JS bridge error: $error');
                    }
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
          ),
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _onPetPointerDown,
              onPointerMove: _onPetPointerMove,
              onPointerUp: (event) => _onPetPointerEnd(event.pointer),
              onPointerCancel: (event) => _onPetPointerEnd(event.pointer),
            ),
          ),

          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: SizedBox(
              height: 55,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.launchArgs != null) ...[
                    GlassIconButton(
                      adaptiveIconSize: true,
                      padding: const EdgeInsets.all(8),
                      size: 55,
                      radius: 15,
                      style: GlassPresets.button,
                      icon: Icons.arrow_back,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 10),
                  ],
                  GlassIconButton(
                    adaptiveIconSize: true,
                    padding: const EdgeInsets.all(8),
                    size: 55,
                    radius: 15,
                    style: GlassPresets.button,
                    icon: Icons.menu,
                    onPressed: () {
                      setState(() {
                        _showOptions = true;
                        _overlayView = OverlayView.menu;
                      });
                    },
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _aiService.intimacy,
                      builder: (context, intimacy, _) {
                        return IntimacyThermometer(value: intimacy);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  GlassIconButton(
                    adaptiveIconSize: true,
                    padding: const EdgeInsets.all(8),
                    size: 55,
                    radius: 15,
                    style: GlassPresets.button,
                    icon: Icons.view_in_ar,
                    onPressed: _openAR,
                  ),
                ],
              ),
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
                  child: ValueListenableBuilder<AiCompanionConnectionState>(
                    valueListenable: _aiService.connectionState,
                    builder: (context, state, _) {
                      final hint = _buildStatusHint(state);
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (hint.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                hint,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _messageController,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: const InputDecoration(
                                    hintText: "Type a message...",
                                    hintStyle: TextStyle(color: Colors.white70),
                                    border: InputBorder.none,
                                  ),
                                  onSubmitted: (_) => _sendMessageFromText(),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.send),
                                color: Colors.white.withOpacity(0.9),
                                onPressed: _sendMessageFromText,
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.mic,
                                  color:
                                      _isSpeechRecognitionActive
                                          ? Colors.redAccent
                                          : Colors.white.withOpacity(0.9),
                                ),
                                onPressed: _startSpeechRecognition,
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          if (_vrmDownloading)
            Positioned.fill(
              child: AbsorbPointer(
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: Color(0x99000000)),
                  child: Center(
                    child: Card(
                      margin: const EdgeInsets.all(32),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              _vrmOverlayCaption.isEmpty
                                  ? 'Loading avatar…'
                                  : _vrmOverlayCaption,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            if (_vrmDownloadFraction != null) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: 240,
                                child: LinearProgressIndicator(
                                  value: _vrmDownloadFraction,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${(_vrmDownloadFraction! * 100).round()}%',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
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
