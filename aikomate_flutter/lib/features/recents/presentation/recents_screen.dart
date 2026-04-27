import 'package:flutter/material.dart';
import 'package:aikomate_flutter/menu_sections_pages/history.dart';

class RecentsScreen extends StatelessWidget {
  const RecentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recents')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: HistoryView(onBack: () {}),
          ),
        ),
      ),
    );
  }
}
