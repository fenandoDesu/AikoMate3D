import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:aikomate_flutter/app/aikomate_app.dart';
import 'package:aikomate_flutter/core/auth/auth_session_notifier.dart';
import 'package:aikomate_flutter/features/ai_companion/ai_companion_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _initArChannel();
  final session = AuthSessionNotifier();
  await session.restore();
  runApp(AikoMateApp(session: session));
}

// AR MethodChannel is handled inside ViewerScreen to reuse its companion service.
AiCompanionService? _globalAiService;
final MethodChannel _arChannel = const MethodChannel('com.aikomate/ar');
bool _arChannelInitialized = false;

void _initArChannel() {
  if (_arChannelInitialized) return;
  _arChannelInitialized = true;

  _arChannel.setMethodCallHandler((call) async {
    if (call.method != 'speechResult') return;
    final args = (call.arguments as Map?) ?? {};
    final transcript = (args['transcript'] as String?)?.trim();
    final language = args['language'] as String? ?? 'en-US';
    if (transcript == null || transcript.isEmpty) return;

    final svc = _globalAiService ??= AiCompanionService();
    try {
      print('AR speech -> companion: "$transcript" [$language]');
      await svc.sendMessage(text: transcript, language: language);
      print('AR speech sent to companion');
    } catch (e) {
      print('AR speech send failed: $e');
    }
  });
}
