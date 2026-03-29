import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'features/viewer/screens/viewer_screen.dart';
import 'features/ai_companion/ai_companion_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _initArChannel();
  runApp(const AikoMateApp());
}

class AikoMateApp extends StatelessWidget {
  const AikoMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AikoMate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ViewerScreen(),
    );
  }
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
