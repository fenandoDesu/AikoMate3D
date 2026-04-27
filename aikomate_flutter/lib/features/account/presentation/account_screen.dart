import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:aikomate_flutter/core/auth/auth_session_notifier.dart';
import 'package:aikomate_flutter/core/storage/secure_storage.dart';
import 'package:aikomate_flutter/menu_sections_pages/profile.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, required this.session});

  final AuthSessionNotifier session;

  void _onLogout(BuildContext context) {
    SecureStorage.deleteToken().then((_) {
      session.setLoggedOut();
      if (context.mounted) context.go('/login');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ProfileView(
              onBack: () => context.go('/hub/discover'),
              onLogout: () => _onLogout(context),
            ),
          ),
        ),
      ),
    );
  }
}
