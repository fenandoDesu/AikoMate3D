import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:aikomate_flutter/core/api/memory_api.dart';
import 'package:aikomate_flutter/core/storage/secure_storage.dart';
import 'package:aikomate_flutter/reusable_widgets/glass.dart';

class HistoryView extends StatefulWidget {
  const HistoryView({
    super.key,
    required this.onBack,
    this.templateId,
  });

  final VoidCallback onBack;

  /// When set, scopes `GET`/`DELETE` `/memory/history` to this template.
  final String? templateId;

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  bool _loading = true;
  bool _deleting = false;
  String? _error;
  List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final token = await SecureStorage.getToken();
    if (token == null) {
      setState(() {
        _loading = false;
        _error = "Missing auth token";
      });
      return;
    }

    try {
      final res = await http.get(
        memoryHistoryUri(templateId: widget.templateId),
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = "Failed to load history";
        });
        return;
      }

      final data = res.body.isNotEmpty ? jsonDecode(res.body) : [];
      final list = _extractMessages(data);

      setState(() {
        _messages = list;
        _loading = false;
      });
    } catch (error) {
      setState(() {
        _loading = false;
        _error = "Network error: $error";
      });
    }
  }

  List<Map<String, dynamic>> _extractMessages(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (data is Map && data["history"] is List) {
      final list = data["history"] as List;
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  Future<void> _deleteHistory() async {
    if (_deleting) return;
    setState(() {
      _deleting = true;
      _error = null;
    });

    final token = await SecureStorage.getToken();
    if (token == null) {
      setState(() {
        _deleting = false;
        _error = "Missing auth token";
      });
      return;
    }

    try {
      final res = await http.delete(
        memoryHistoryUri(templateId: widget.templateId),
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode != 200 && res.statusCode != 204) {
        setState(() {
          _deleting = false;
          _error = "Failed to delete history";
        });
        return;
      }

      setState(() {
        _messages = [];
        _deleting = false;
      });
    } catch (error) {
      setState(() {
        _deleting = false;
        _error = "Deletion failed: $error";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      style: GlassPresets.panel,
      radius: 22,
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 360,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GlassIconButton(
                  adaptiveIconSize: true,
                  size: 40,
                  radius: 12,
                  style: GlassPresets.button,
                  icon: Icons.arrow_back,
                  onPressed: widget.onBack,
                ),
                const Text(
                  "History",
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                GlassIconButton(
                  adaptiveIconSize: true,
                  size: 40,
                  radius: 12,
                  style: GlassPresets.button,
                  icon: Icons.delete_outline,
                  onPressed: _messages.isEmpty || _deleting ? () {} : _deleteHistory,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else if (_messages.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    "No history yet",
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _messages.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final role = msg["role"]?.toString() ?? "assistant";
                    final content = msg["content"]?.toString() ?? "";
                    final roleLabel =
                        role == "assistant" ? "Assistant" : "You";
                    final roleColor = role == "assistant"
                        ? Colors.white
                        : Colors.white70;

                    return GlassContainer(
                      style: GlassPresets.card,
                      radius: 16,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            roleLabel,
                            style: TextStyle(
                              color: roleColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            content,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
