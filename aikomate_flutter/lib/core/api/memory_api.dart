import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:aikomate_flutter/core/api/api_error.dart';
import 'package:aikomate_flutter/core/config/env.dart';
import 'package:aikomate_flutter/core/storage/secure_storage.dart';

String _apiBase() => Env.apiUrl.replaceAll(RegExp(r'/+$'), '');

/// `GET` / `DELETE` `/memory/history` with optional `template_id` query.
Uri memoryHistoryUri({String? templateId}) {
  final uri = Uri.parse('${_apiBase()}/memory/history');
  if (templateId == null || templateId.isEmpty) return uri;
  return uri.replace(queryParameters: {'template_id': templateId});
}

/// `GET /memory/me` with optional `template_id` query.
Uri memoryMeUri({String? templateId}) {
  final uri = Uri.parse('${_apiBase()}/memory/me');
  if (templateId == null || templateId.isEmpty) return uri;
  return uri.replace(queryParameters: {'template_id': templateId});
}

class MemoryJsonResult {
  const MemoryJsonResult({
    required this.success,
    this.error,
    this.statusCode,
    this.json,
  });

  final bool success;
  final String? error;
  final int? statusCode;
  final Object? json;
}

Map<String, dynamic>? _asJsonMap(Object? decoded) {
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) return Map<String, dynamic>.from(decoded);
  return null;
}

/// `GET /memory/me?template_id=` — optional scoped memory profile.
Future<MemoryJsonResult> getMemoryMe({String? templateId}) async {
  final token = await SecureStorage.getToken();
  if (token == null || token.isEmpty) {
    return const MemoryJsonResult(success: false, error: 'Not signed in');
  }

  try {
    final res = await http.get(
      memoryMeUri(templateId: templateId),
      headers: {'Authorization': 'Bearer $token'},
    );
    final decoded =
        res.body.isNotEmpty ? jsonDecode(res.body) as Object? : null;
    final ok = res.statusCode >= 200 && res.statusCode < 300;
    if (ok) {
      return MemoryJsonResult(
        success: true,
        statusCode: res.statusCode,
        json: decoded,
      );
    }
    final errMap = _asJsonMap(decoded) ?? <String, dynamic>{};
    return MemoryJsonResult(
      success: false,
      error: messageFromErrorBody(errMap, 'Request failed'),
      statusCode: res.statusCode,
      json: decoded,
    );
  } catch (e) {
    return MemoryJsonResult(success: false, error: 'Network error: $e');
  }
}
