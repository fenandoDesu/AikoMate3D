import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:aikomate_flutter/core/api/api_error.dart';
import 'package:aikomate_flutter/core/storage/secure_storage.dart';
import 'package:aikomate_flutter/core/config/env.dart';

final url = Env.apiUrl;

class LoginResult {
  final bool success;
  final String? error;

  LoginResult(
    {
      required this.success, 
      this.error
    }
  );
}

Future<LoginResult> login(String email, String password) async {
  try {
    final res = await http.post(
      Uri.parse("$url/auth/login"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "email": email,
        "password": password,
      }),
    );

    final data = res.body.isNotEmpty
        ? jsonDecode(res.body) as Map<String, dynamic>
        : <String, dynamic>{};

    if (res.statusCode != 200) {
      return LoginResult(
        success: false,
        error: messageFromErrorBody(data, 'Login failed'),
      );
    }

    final token = data['token'];
    if (token is! String || token.isEmpty) {
      return LoginResult(success: false, error: 'Invalid response');
    }

    await SecureStorage.setToken(token);

    return LoginResult(success: true);
  } catch (error) {
    return LoginResult(success: false, error: "Network error:$error");
  }
}