import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:aikomate_flutter/core/storage/secure_storage.dart';
import 'package:aikomate_flutter/core/config/env.dart';

final url = Env.apiUrl;

class AuthResult {
  final bool success;
  final String? error;
  final Map<String, dynamic>? result;

  AuthResult({required this.success, this.error, this.result});
}

Future<AuthResult> auth() async {
  final String? token = await SecureStorage.getToken();
  if (token == null) return AuthResult(success: false, error: "No token", result: null);

  try {
    final res = await http.get(
      Uri.parse("$url/auth/me"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (res.statusCode != 200) return AuthResult(success: false, error: "Invalid token", result: null);

    final data = res.body.isNotEmpty
        ? jsonDecode(res.body)
        : <String, dynamic>{};

    // result returns id, name, email, credits, admin, ...
    final map = data is Map<String, dynamic>
        ? data
        : Map<String, dynamic>.from(data as Map);
    return AuthResult(success: true, error: null, result: map);
  } catch (error) {
    return AuthResult(
      success: false,
      error: "Network error:$error",
      result: null,
    );
  }
}
