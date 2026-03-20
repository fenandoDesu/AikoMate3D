import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SignupView extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback? onLogin;

  const SignupView({
    super.key,
    required this.onBack,
    this.onLogin,
  });

  @override
  State<SignupView> createState() => _SignupViewState();
}

class _SignupViewState extends State<SignupView> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final storage = const FlutterSecureStorage();

  String? error;
  bool loading = false;

  Future<void> signup() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final res = await http.post(
        Uri.parse("https://api.japaneseblossom.com/auth/signup"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "name": nameController.text,
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

      // 🔐 store token (same as login)
      await storage.write(key: "token", value: data["token"]);

      // 👉 After signup, go back or switch to logged state later
      widget.onBack();

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
          // 🔝 Header
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

          // 👤 Name
          TextField(
            controller: nameController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: "Name",
              hintStyle: TextStyle(color: Colors.white70),
            ),
          ),

          const SizedBox(height: 12),

          // 📧 Email
          TextField(
            controller: emailController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: "Email",
              hintStyle: TextStyle(color: Colors.white70),
            ),
          ),

          const SizedBox(height: 12),

          // 🔒 Password
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

          // 🔘 Button
          ElevatedButton(
            onPressed: loading ? null : signup,
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text("Create"),
          ),

          const SizedBox(height: 12),

          // 🔁 Switch to login
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