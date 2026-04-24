import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:aikomate_flutter/core/api/api_error.dart';
import 'package:aikomate_flutter/core/storage/secure_storage.dart';
import 'package:aikomate_flutter/core/config/env.dart';

final url = Env.apiUrl;

class SignupResult {
  final bool success;
  final String? error;

  SignupResult(
    {
      required this.success, 
      this.error
    }
  );
}


Future<SignupResult> signup(String name, String email, String password) async {
  try {
    final res = await http.post(
      Uri.parse("$url/auth/signup"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "name": name,
        "email": email,
        "password": password,
      }),
    );

    final data = res.body.isNotEmpty
        ? jsonDecode(res.body) as Map<String, dynamic>
        : <String, dynamic>{};

    if (res.statusCode != 200) {
      return SignupResult(
        success: false,
        error: messageFromErrorBody(data, 'Signup failed'),
      );
    }

    final token = data['token'];
    if (token is! String || token.isEmpty) {
      return SignupResult(success: false, error: 'Invalid response');
    }

    await SecureStorage.setToken(token);

    return SignupResult(success: true);
  } catch (e) {
    return SignupResult(success: false, error: "Network error");
  }
}