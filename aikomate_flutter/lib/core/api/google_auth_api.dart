import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:aikomate_flutter/core/api/api_error.dart';
import 'package:aikomate_flutter/core/config/env.dart';
import 'package:aikomate_flutter/core/storage/secure_storage.dart';

final _url = Env.apiUrl;

class GoogleAuthResult {
  final bool success;
  final String? error;

  GoogleAuthResult({required this.success, this.error});
}

Future<GoogleAuthResult> googleAuth(String idToken) async {
  try {
    final res = await http.post(
      Uri.parse('$_url/auth/google'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'idToken': idToken}),
    );

    final data = res.body.isNotEmpty
        ? jsonDecode(res.body) as Map<String, dynamic>
        : <String, dynamic>{};

    if (res.statusCode != 200) {
      return GoogleAuthResult(
        success: false,
        error: messageFromErrorBody(data, 'Google sign-in failed'),
      );
    }

    final token = data['token'];
    if (token is! String || token.isEmpty) {
      return GoogleAuthResult(success: false, error: 'Invalid response');
    }

    await SecureStorage.setToken(token);
    return GoogleAuthResult(success: true);
  } catch (e) {
    return GoogleAuthResult(success: false, error: 'Network error');
  }
}
