import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SettingsStorage {
  static const _storage = FlutterSecureStorage();
  static const _key = "settings";

  static Future<Map<String, dynamic>> readAll() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> writeAll(Map<String, dynamic> data) async {
    await _storage.write(key: _key, value: jsonEncode(data));
  }

  static Future<void> update(Map<String, dynamic> patch) async {
    final current = await readAll();
    current.addAll(patch);
    await writeAll(current);
  }
}
