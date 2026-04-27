import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:aikomate_flutter/core/auth/auth_session_notifier.dart';
import 'package:aikomate_flutter/menu_sections_pages/login.dart';

class AuthLoginScreen extends StatelessWidget {
  const AuthLoginScreen({super.key, required this.session});

  final AuthSessionNotifier session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: LoginView(
              onBack: () {},
              onSignup: () => context.push('/signup'),
              onLoginSuccess: () {
                session.setLoggedIn();
                session.refreshFromMe().then((_) {
                  if (context.mounted) context.go('/hub/discover');
                });
              },
            ),
          ),
        ),
      ),
    );
  }
}
