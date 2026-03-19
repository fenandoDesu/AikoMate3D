import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ArScreen extends StatefulWidget {
  const ArScreen({super.key});

  @override
  State<ArScreen> createState() => _ArScreenState();
}

class _ArScreenState extends State<ArScreen> {
  static const _channel = MethodChannel('com.aikomate/ar');

  @override
  void initState() {
    super.initState();
    // Launch native AR activity immediately
    WidgetsBinding.instance.addPostFrameCallback((_) => _openAR());
  }

  Future<void> _openAR() async {
    await _channel.invokeMethod('openAR');
    // When ArActivity finishes (user pressed back), pop this screen too
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // This screen is only visible for a split second before ArActivity launches
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}