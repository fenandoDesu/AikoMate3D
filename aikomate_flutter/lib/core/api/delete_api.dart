import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:aikomate_flutter/core/storage/secure_storage.dart';
import 'package:aikomate_flutter/core/config/env.dart';

final url = Env.apiUrl;

class DeletionResult {
  final bool success;
  final String? error;
  final Map<String, dynamic>? result;

  DeletionResult({required this.success, this.error, this.result});
}

Future<DeletionResult> deleteAccount() async {
  final token = await SecureStorage.getToken();

  if (token == null) {
    return DeletionResult(success: false, error: "No token");
  }

  try {
    final res = await http.delete(
      Uri.parse("$url/auth/me"),
      headers: {
        "Authorization": "Bearer $token",
      },
    );

    if (res.statusCode != 200) {
      final data = res.body.isNotEmpty ? jsonDecode(res.body) as Map<String, dynamic> : {};
      return DeletionResult(success: false, error: data["detail"] ?? "Failed to delete account");
    }

    await SecureStorage.deleteToken();

    return DeletionResult(success: true);
  } catch (e) {
    return DeletionResult(success: false, error: "Network error");
  }
}