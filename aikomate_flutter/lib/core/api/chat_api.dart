import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:aikomate_flutter/core/api/api_error.dart';
import 'package:aikomate_flutter/core/config/env.dart';
import 'package:aikomate_flutter/core/storage/secure_storage.dart';

class ChatSuggestionsResult {
  const ChatSuggestionsResult({
    required this.success,
    this.error,
    this.suggestions = const [],
  });

  final bool success;
  final String? error;
  final List<String> suggestions;
}

List<String> _parseSuggestionList(Object? decoded) {
  if (decoded is! Map) return const [];
  final m = Map<String, dynamic>.from(decoded);
  dynamic raw =
      m['suggestions'] ??
      m['chips'] ??
      m['items'] ??
      m['messages'] ??
      m['texts'];
  if (raw is! List) return const [];
  final out = <String>[];
  for (final e in raw) {
    if (e is String && e.trim().isNotEmpty) {
      out.add(e.trim());
    } else if (e is Map) {
      final t = e['text'] ?? e['label'] ?? e['message'];
      if (t != null && t.toString().trim().isNotEmpty) {
        out.add(t.toString().trim());
      }
    }
    if (out.length >= 6) break;
  }
  return out.take(3).toList();
}

/// `POST /chat/suggestions` with `{ template_id, language }`.
Future<ChatSuggestionsResult> postChatSuggestions({
  required String templateId,
  required String language,
}) async {
  final token = await SecureStorage.getToken();
  if (token == null || token.isEmpty) {
    return const ChatSuggestionsResult(success: false, error: 'Not signed in');
  }

  final base = Env.apiUrl.replaceAll(RegExp(r'/+$'), '');
  try {
    final res = await http.post(
      Uri.parse('$base/chat/suggestions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'template_id': templateId, 'language': language}),
    );
    final decoded =
        res.body.isNotEmpty ? jsonDecode(res.body) as Object? : null;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return ChatSuggestionsResult(
        success: true,
        suggestions: _parseSuggestionList(decoded),
      );
    }
    final errMap =
        decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
    return ChatSuggestionsResult(
      success: false,
      error: messageFromErrorBody(errMap, 'Suggestions failed'),
    );
  } catch (e) {
    return ChatSuggestionsResult(success: false, error: 'Network error: $e');
  }
}
