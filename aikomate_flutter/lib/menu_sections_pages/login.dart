import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final storage = const FlutterSecureStorage();

class LoginView extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onSignup;

  const LoginView({
    super.key,
    required this.onBack,
    required this.onSignup,
  });

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  String? error;
  bool loading = false;

  Future<void> login() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final res = await http.post(
        Uri.parse("https://api.japaneseblossom.com/auth/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": emailController.text,
          "password": passwordController.text,
        }),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode != 200) {
        setState(() {
          error = data["detail"];
        });
        return;
      }

      await storage.write(key: "token", value: data["token"]);

    } catch (e) {
      setState(() {
        error = "Network error";
      });
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
            onPressed: loading ? null : login,
            child: loading
                ? const CircularProgressIndicator()
                : const Text("Login"),
          ),

          const SizedBox(height: 12),

          // Signup link
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
          ]
        ],
      ),
    );
  }
}