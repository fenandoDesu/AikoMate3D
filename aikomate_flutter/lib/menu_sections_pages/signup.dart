import 'package:flutter/material.dart';
import 'package:aikomate_flutter/core/api/signup_api.dart'; // <-- your signup()

class SignupView extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback? onLogin;
  final VoidCallback? onSuccess;
  final VoidCallback onSignupSuccess;

  const SignupView({
    super.key,
    required this.onBack,
    this.onLogin,
    this.onSuccess,
    required this.onSignupSuccess
  });

  @override
  State<SignupView> createState() => _SignupViewState();
}

class _SignupViewState extends State<SignupView> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  String? error;
  bool loading = false;

  Future<void> handleSignup() async {
    if (nameController.text.isEmpty ||
        emailController.text.isEmpty ||
        passwordController.text.isEmpty) {
      setState(() => error = "Fill all fields");
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    final result = await signup(
      nameController.text.trim(),
      emailController.text.trim(),
      passwordController.text.trim(),
    );

    if (!mounted) return;

    if (!result.success) {
      setState(() {
        error = result.error ?? "Signup failed";
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
      key: const ValueKey("signup"),
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
              const Text(
                "Create Account",
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(width: 40),
            ],
          ),

          const SizedBox(height: 16),

          // Name
          TextField(
            controller: nameController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: "Name",
              hintStyle: TextStyle(color: Colors.white70),
            ),
          ),

          const SizedBox(height: 12),

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
            onPressed: loading ? null : handleSignup,
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text("Create"),
          ),

          const SizedBox(height: 12),

          // Go to login
          GestureDetector(
            onTap: widget.onLogin,
            child: const Text(
              "Already have an account? Login",
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