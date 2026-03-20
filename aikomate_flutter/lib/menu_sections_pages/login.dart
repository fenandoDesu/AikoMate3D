import 'package:flutter/material.dart';
import 'package:aikomate_flutter/core/api/login_api.dart';

class LoginView extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback? onSignup;
  final VoidCallback? onSuccess;
  final VoidCallback onLoginSuccess;

  const LoginView({
    super.key,
    required this.onBack,
    this.onSignup,
    this.onSuccess,
    required this.onLoginSuccess,
  });

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  String? error;
  bool loading = false;

  Future<void> handleLogin() async {
    setState(() {
      loading = true;
      error = null;
    });

    final result = await login(
      emailController.text.trim(),
      passwordController.text.trim(),
    );

    if (!mounted) return;

    if (!result.success) {
      setState(() {
        error = result.error ?? "Login failed";
        loading = false;
      });
      return;
    }

    setState(() => loading = false);

    widget.onSuccess?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey("login"),
      width: 320,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: widget.onBack,
              ),
              const Text("Login", style: TextStyle(color: Colors.white)),
              const SizedBox(width: 40),
            ],
          ),

          const SizedBox(height: 16),

          // Email
          TextField(
            controller: emailController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: "Email",
              hintStyle: TextStyle(color: Colors.white70),
            ),
          ),

          const SizedBox(height: 12),

          // Password
          TextField(
            controller: passwordController,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: "Password",
              hintStyle: TextStyle(color: Colors.white70),
            ),
          ),

          const SizedBox(height: 20),

          // Button
          ElevatedButton(
            onPressed: loading ? null : handleLogin,
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text("Login"),
          ),

          const SizedBox(height: 12),

          // Go to signup
          GestureDetector(
            onTap: widget.onSignup,
            child: const Text(
              "Don't have an account? Sign up",
              style: TextStyle(color: Colors.white70),
            ),
          ),

          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }
}