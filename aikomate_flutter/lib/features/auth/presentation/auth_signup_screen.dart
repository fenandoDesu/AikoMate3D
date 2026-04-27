import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:aikomate_flutter/core/auth/auth_session_notifier.dart';
import 'package:aikomate_flutter/menu_sections_pages/signup.dart';

class AuthSignupScreen extends StatelessWidget {
  const AuthSignupScreen({super.key, required this.session});

  final AuthSessionNotifier session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SignupView(
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/login');
                }
              },
              onLogin: () => context.go('/login'),
              onSignupSuccess: () {
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
