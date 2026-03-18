import 'package:flutter/material.dart';
import 'features/viewer/screens/viewer_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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