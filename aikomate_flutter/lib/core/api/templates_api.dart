import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:aikomate_flutter/core/api/api_error.dart';
import 'package:aikomate_flutter/core/config/env.dart';
import 'package:aikomate_flutter/core/storage/secure_storage.dart';

// --- Presign + R2 upload (Haruna templates) ---

/// Body for `POST /templates/upload-url`.
class TemplateVrmPresignMeta {
  const TemplateVrmPresignMeta({
    required this.fileName,
    required this.fileType,
    required this.fileSize,
  });

  /// Must end with `.vrm` (server-validated).
  final String fileName;

  /// Exact `Content-Type` for the R2 `PUT` in step 3 (e.g. `model/vrm`).
  final String fileType;

  final int fileSize;

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'fileType': fileType,
    'fileSize': fileSize,
  };
}

class TemplateCoverImagePresignMeta {
  const TemplateCoverImagePresignMeta({
    required this.fileName,
    required this.fileType,
    required this.fileSize,
  });

  final String fileName;
  final String fileType;
  final int fileSize;

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'fileType': fileType,
    'fileSize': fileSize,
  };
}

/// `response.vrm` from presign (camelCase).
class TemplatePresignedTarget {
  const TemplatePresignedTarget({
    required this.uploadUrl,
    required this.key,
    required this.fileUrl,
  });

  final String uploadUrl;
  final String key;
  final String fileUrl;
}

class TemplateUploadUrlsResult {
  const TemplateUploadUrlsResult({
    required this.success,
    this.error,
    this.vrm,
    this.coverImage,
  });

  final bool success;
  final String? error;
  final TemplatePresignedTarget? vrm;
  final TemplatePresignedTarget? coverImage;
}

class CreateTemplateResult {
  const CreateTemplateResult({
    required this.success,
    this.error,
    this.statusCode,
    this.rawBody,
  });

  final bool success;
  final String? error;
  final int? statusCode;
  final Map<String, dynamic>? rawBody;
}

/// Generic JSON result for list/detail/patch/delete template routes.
class TemplatesJsonResult {
  const TemplatesJsonResult({
    required this.success,
    this.error,
    this.statusCode,
    this.json,
  });

  final bool success;
  final String? error;
  final int? statusCode;

  /// Decoded body: usually `Map<String, dynamic>`; some endpoints may return a list.
  final Object? json;
}

TemplatePresignedTarget? _parsePresignedTarget(dynamic raw) {
  if (raw is! Map) return null;
  final m = raw.cast<String, dynamic>();
  final upload = m['uploadUrl'] ?? m['upload_url'];
  final key = m['key'];
  final fileUrl = m['fileUrl'] ?? m['file_url'];
  if (upload is! String ||
      key is! String ||
      fileUrl is! String ||
      upload.isEmpty ||
      key.isEmpty ||
      fileUrl.isEmpty) {
    return null;
  }
  return TemplatePresignedTarget(uploadUrl: upload, key: key, fileUrl: fileUrl);
}

Future<Map<String, String>?> _bearerHeaders() async {
  final token = await SecureStorage.getToken();
  if (token == null || token.isEmpty) return null;
  return {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};
}

Object? _decodeJsonBody(String body) {
  if (body.isEmpty) return null;
  return jsonDecode(body);
}

Map<String, dynamic>? _asJsonMap(Object? decoded) {
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) return Map<String, dynamic>.from(decoded);
  return null;
}

/// Step 1: `POST /templates/upload-url` (VRM presign).
Future<TemplateUploadUrlsResult> requestTemplateUploadUrls({
  required TemplateVrmPresignMeta vrm,
  required TemplateCoverImagePresignMeta coverImage,
}) async {
  final headers = await _bearerHeaders();
  if (headers == null) {
    return const TemplateUploadUrlsResult(
      success: false,
      error: 'Not signed in',
    );
  }

  try {
    final res = await http.post(
      Uri.parse('${Env.apiUrl}/templates/upload-url'),
      headers: headers,
      body: jsonEncode({
        'vrm': vrm.toJson(),
        'coverImage': coverImage.toJson(),
      }),
    );

    final data = _asJsonMap(_decodeJsonBody(res.body)) ?? <String, dynamic>{};

    if (res.statusCode != 200) {
      return TemplateUploadUrlsResult(
        success: false,
        error: messageFromErrorBody(data, 'Failed to get upload URLs'),
      );
    }

    final v = _parsePresignedTarget(data['vrm']) ?? _parsePresignedTarget(data);
    final c = _parsePresignedTarget(data['coverImage']);
    if (v == null || c == null) {
      return const TemplateUploadUrlsResult(
        success: false,
        error: 'Invalid upload URL response',
      );
    }

    return TemplateUploadUrlsResult(success: true, vrm: v, coverImage: c);
  } catch (e) {
    return TemplateUploadUrlsResult(success: false, error: 'Network error: $e');
  }
}

/// Step 2: `PUT` raw bytes to R2. [contentType] must equal presign `fileType`.
Future<http.Response> putFileToPresignedUrl({
  required String uploadUrl,
  required Uint8List bytes,
  required String contentType,
}) {
  return http.put(
    Uri.parse(uploadUrl),
    headers: {'Content-Type': contentType},
    body: bytes,
  );
}

Map<String, dynamic> _vrmPayloadForCreate({
  required String key,
  required String fileUrl,
  required int size,
  String? contentType,
}) {
  return {
    'key': key,
    'fileUrl': fileUrl,
    'size': size,
    if (contentType != null && contentType.isNotEmpty)
      'contentType': contentType,
  };
}

Map<String, dynamic> _coverImagePayloadForCreate({
  required String key,
  required String fileUrl,
  required int size,
  String? contentType,
}) {
  return {
    'key': key,
    'fileUrl': fileUrl,
    'size': size,
    if (contentType != null && contentType.isNotEmpty)
      'contentType': contentType,
  };
}

/// Max length for [fishAudioId] on `POST /templates` (Fish voice `reference_id`).
const templateFishAudioIdMaxLength = 128;

/// Step 3: `POST /templates` after R2 `PUT` succeeds.
///
/// [vrmContentType] should match the presign `fileType` / R2 `PUT` header (optional on server).
///
/// [fishAudioId] is optional: Fish Audio voice `reference_id` (same value as WS `fish_audio_id`).
/// Omit or leave empty to let the server pick a language default for TTS.
Future<CreateTemplateResult> createTemplate({
  required String name,
  required String title,
  required String description,
  required String prompt,
  required String visibility,
  required TemplatePresignedTarget vrmTarget,
  required TemplatePresignedTarget coverImageTarget,
  required int vrmSize,
  required int coverImageSize,
  String? vrmContentType,
  String? coverImageContentType,
  String? fishAudioId,
}) async {
  final headers = await _bearerHeaders();
  if (headers == null) {
    return const CreateTemplateResult(success: false, error: 'Not signed in');
  }

  final fishTrim = fishAudioId?.trim();
  if (fishTrim != null && fishTrim.length > templateFishAudioIdMaxLength) {
    return const CreateTemplateResult(
      success: false,
      error:
          'Fish Audio voice id must be at most $templateFishAudioIdMaxLength characters',
    );
  }

  try {
    final body = <String, dynamic>{
      'name': name,
      'title': title,
      'description': description,
      'prompt': prompt,
      'visibility': visibility,
      'vrm': _vrmPayloadForCreate(
        key: vrmTarget.key,
        fileUrl: vrmTarget.fileUrl,
        size: vrmSize,
        contentType: vrmContentType,
      ),
      'coverImage': _coverImagePayloadForCreate(
        key: coverImageTarget.key,
        fileUrl: coverImageTarget.fileUrl,
        size: coverImageSize,
        contentType: coverImageContentType,
      ),
    };
    if (fishTrim != null && fishTrim.isNotEmpty) {
      body['fishAudioId'] = fishTrim;
    }

    final res = await http.post(
      Uri.parse('${Env.apiUrl}/templates'),
      headers: headers,
      body: jsonEncode(body),
    );

    final data = _asJsonMap(_decodeJsonBody(res.body)) ?? <String, dynamic>{};

    if (res.statusCode != 200 && res.statusCode != 201) {
      return CreateTemplateResult(
        success: false,
        error: messageFromErrorBody(data, 'Failed to create template'),
        statusCode: res.statusCode,
        rawBody: data,
      );
    }

    return CreateTemplateResult(
      success: true,
      statusCode: res.statusCode,
      rawBody: data,
    );
  } catch (e) {
    return CreateTemplateResult(success: false, error: 'Network error: $e');
  }
}

// --- Read / mutate templates (Haruna) ---

Uri _templatesUri(String path, [Map<String, String>? query]) {
  final base = Env.apiUrl.replaceAll(RegExp(r'/+$'), '');
  final p = path.startsWith('/') ? path : '/$path';
  final u = Uri.parse('$base$p');
  if (query == null || query.isEmpty) return u;
  return u.replace(queryParameters: query);
}

Future<TemplatesJsonResult> _authorizedJson({
  required String method,
  required Uri uri,
  Map<String, dynamic>? body,
}) async {
  final headers = await _bearerHeaders();
  if (headers == null) {
    return const TemplatesJsonResult(success: false, error: 'Not signed in');
  }

  try {
    late http.Response res;
    switch (method.toUpperCase()) {
      case 'GET':
        res = await http.get(uri, headers: headers);
        break;
      case 'PATCH':
        res = await http.patch(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        );
        break;
      case 'DELETE':
        res = await http.delete(uri, headers: headers);
        break;
      case 'POST':
        if (body == null) {
          final h = Map<String, String>.from(headers)..remove('Content-Type');
          res = await http.post(uri, headers: h);
        } else {
          res = await http.post(uri, headers: headers, body: jsonEncode(body));
        }
        break;
      default:
        return const TemplatesJsonResult(
          success: false,
          error: 'Unsupported method',
        );
    }

    final decoded = _decodeJsonBody(res.body);
    final ok = res.statusCode >= 200 && res.statusCode < 300;

    if (ok) {
      return TemplatesJsonResult(
        success: true,
        statusCode: res.statusCode,
        json: decoded,
      );
    }

    final errMap = _asJsonMap(decoded) ?? <String, dynamic>{};
    return TemplatesJsonResult(
      success: false,
      error: messageFromErrorBody(errMap, 'Request failed'),
      statusCode: res.statusCode,
      json: decoded,
    );
  } catch (e) {
    return TemplatesJsonResult(success: false, error: 'Network error: $e');
  }
}

/// `GET /templates/mine?page=&limit=`
Future<TemplatesJsonResult> getMyTemplates({int? page, int? limit}) {
  final q = <String, String>{};
  if (page != null) q['page'] = '$page';
  if (limit != null) q['limit'] = '$limit';
  return _authorizedJson(
    method: 'GET',
    uri: _templatesUri('/templates/mine', q.isEmpty ? null : q),
  );
}

/// `GET /templates/public/cards?page=&limit=` — public + active only, card-safe fields.
Future<TemplatesJsonResult> getPublicTemplates({int? page, int? limit}) {
  final q = <String, String>{};
  if (page != null) q['page'] = '$page';
  if (limit != null) q['limit'] = '$limit';
  return _authorizedJson(
    method: 'GET',
    uri: _templatesUri('/templates/public/cards', q.isEmpty ? null : q),
  );
}

/// `GET /templates/recents?page=&limit=` — recently used templates for the user.
Future<TemplatesJsonResult> getTemplateRecents({int? page, int? limit}) {
  final q = <String, String>{};
  if (page != null) q['page'] = '$page';
  if (limit != null) q['limit'] = '$limit';
  return _authorizedJson(
    method: 'GET',
    uri: _templatesUri('/templates/recents', q.isEmpty ? null : q),
  );
}

/// `GET /templates/{templateId}`
Future<TemplatesJsonResult> getTemplate(String templateId) {
  return _authorizedJson(
    method: 'GET',
    uri: _templatesUri('/templates/$templateId'),
  );
}

/// `PATCH /templates/{templateId}` — owner updates text / visibility (shape per API).
Future<TemplatesJsonResult> patchTemplate(
  String templateId,
  Map<String, dynamic> updates,
) {
  return _authorizedJson(
    method: 'PATCH',
    uri: _templatesUri('/templates/$templateId'),
    body: updates,
  );
}

/// `DELETE /templates/{templateId}`
Future<TemplatesJsonResult> deleteTemplate(String templateId) {
  return _authorizedJson(
    method: 'DELETE',
    uri: _templatesUri('/templates/$templateId'),
  );
}

/// `GET /templates/admin/pending?page=&limit=` — requires `user.admin === true`.
Future<TemplatesJsonResult> getAdminPendingTemplates({int? page, int? limit}) {
  final q = <String, String>{};
  if (page != null) q['page'] = '$page';
  if (limit != null) q['limit'] = '$limit';
  return _authorizedJson(
    method: 'GET',
    uri: _templatesUri('/templates/admin/pending', q.isEmpty ? null : q),
  );
}

/// `POST /templates/admin/{templateId}/approve`
Future<TemplatesJsonResult> approveTemplateAdmin(String templateId) {
  return _authorizedJson(
    method: 'POST',
    uri: _templatesUri('/templates/admin/$templateId/approve'),
    body: null,
  );
}

/// `POST /templates/admin/{templateId}/decline` with optional `{ "moderationNote": "..." }`.
Future<TemplatesJsonResult> declineTemplateAdmin(
  String templateId, {
  String? moderationNote,
}) {
  return _authorizedJson(
    method: 'POST',
    uri: _templatesUri('/templates/admin/$templateId/decline'),
    body:
        moderationNote == null || moderationNote.isEmpty
            ? <String, dynamic>{}
            : {'moderationNote': moderationNote},
  );
}

/// Parses paginated `{ items, page, limit, total }` from list endpoints.
class TemplatesListPage {
  TemplatesListPage({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
  });

  final List<Map<String, dynamic>> items;
  final int page;
  final int limit;
  final int total;

  static List<Map<String, dynamic>> _parseItems(dynamic rawItems) {
    if (rawItems is! List) return const <Map<String, dynamic>>[];
    final items = <Map<String, dynamic>>[];
    for (final e in rawItems) {
      if (e is Map<String, dynamic>) {
        items.add(e);
      } else if (e is Map) {
        items.add(Map<String, dynamic>.from(e));
      }
    }
    return items;
  }

  static TemplatesListPage _buildPage({
    required List<Map<String, dynamic>> items,
    int? page,
    int? limit,
    int? total,
  }) {
    return TemplatesListPage(
      items: items,
      page: page ?? 1,
      limit: limit ?? items.length,
      total: total ?? items.length,
    );
  }

  static TemplatesListPage? tryParse(TemplatesJsonResult r) {
    if (!r.success || r.json == null) return null;
    final root = r.json;

    if (root is List) {
      final items = _parseItems(root);
      return _buildPage(items: items);
    }

    if (root is! Map) return null;
    final m = Map<String, dynamic>.from(root);

    final directItems = _parseItems(m['items']);
    if (directItems.isNotEmpty || m['items'] is List) {
      return _buildPage(
        items: directItems,
        page: (m['page'] as num?)?.toInt(),
        limit: (m['limit'] as num?)?.toInt(),
        total: (m['total'] as num?)?.toInt(),
      );
    }

    for (final key in const ['data', 'result', 'results', 'payload']) {
      final nested = m[key];
      if (nested is Map) {
        final n = Map<String, dynamic>.from(nested);
        final nestedItems = _parseItems(
          n['items'] ?? n['templates'] ?? n['cards'] ?? n['list'],
        );
        if (nestedItems.isNotEmpty ||
            n['items'] is List ||
            n['templates'] is List ||
            n['cards'] is List ||
            n['list'] is List) {
          return _buildPage(
            items: nestedItems,
            page: (n['page'] as num?)?.toInt() ?? (m['page'] as num?)?.toInt(),
            limit:
                (n['limit'] as num?)?.toInt() ?? (m['limit'] as num?)?.toInt(),
            total:
                (n['total'] as num?)?.toInt() ?? (m['total'] as num?)?.toInt(),
          );
        }
      }
    }

    final aliasItems = _parseItems(m['templates'] ?? m['cards'] ?? m['list']);
    if (aliasItems.isNotEmpty ||
        m['templates'] is List ||
        m['cards'] is List ||
        m['list'] is List) {
      return _buildPage(
        items: aliasItems,
        page: (m['page'] as num?)?.toInt(),
        limit: (m['limit'] as num?)?.toInt(),
        total: (m['total'] as num?)?.toInt(),
      );
    }

    return null;
  }
}

/// Normalizes a Mongo id from JSON — string, or `{ "$oid": "..." }`.
String? normalizeMongoId(dynamic raw) {
  if (raw == null) return null;
  if (raw is String) {
    final t = raw.trim();
    return t.isEmpty ? null : t;
  }
  if (raw is Map) {
    final oid = raw[r'$oid'] ?? raw['oid'];
    if (oid is String && oid.trim().isNotEmpty) return oid.trim();
  }
  return null;
}

/// Resolves the **template** id from list/detail payload shapes (Discover cards,
/// recents rows, etc.). Prefer explicit `templateId` / nested `template` over
/// root `id` when the API uses `id` for a parent document (e.g. a recents entry).
String? templateIdFromItem(Map<String, dynamic> item) {
  for (final key in const ['templateId', 'template_id']) {
    final v = normalizeMongoId(item[key]);
    if (v != null) return v;
  }

  final nested = item['template'];
  if (nested is String) {
    final v = normalizeMongoId(nested);
    if (v != null) return v;
  }
  if (nested is Map) {
    final m = Map<String, dynamic>.from(nested);
    for (final key in const ['id', '_id', 'templateId', 'template_id']) {
      final v = normalizeMongoId(m[key]);
      if (v != null) return v;
    }
  }

  for (final key in const ['id', '_id']) {
    final v = normalizeMongoId(item[key]);
    if (v != null) return v;
  }
  return null;
}

String? vrmFileUrlFromItem(Map<String, dynamic> item) {
  final vrm = item['vrm'];
  if (vrm is! Map) return null;
  final m = Map<String, dynamic>.from(vrm);
  final u = m['fileUrl'] ?? m['file_url'];
  return u?.toString();
}

String? coverImageUrlFromItem(Map<String, dynamic> item) {
  final direct =
      item['coverImageFileUrl'] ??
      item['cover_image_file_url'] ??
      item['coverUrl'] ??
      item['cover_url'];
  if (direct is String && direct.isNotEmpty) return direct;

  final cover = item['coverImage'];
  if (cover is Map) {
    final m = Map<String, dynamic>.from(cover);
    final u = m['fileUrl'] ?? m['file_url'] ?? m['url'];
    return u?.toString();
  }
  if (cover is String && cover.isNotEmpty) return cover;
  return null;
}

String? fishAudioIdFromMap(Map<String, dynamic> map) {
  final v = map['fishAudioId'] ?? map['fish_audio_id'];
  final s = v?.toString().trim();
  if (s == null || s.isEmpty) return null;
  return s;
}

DateTime? lastUsedAtFromItem(Map<String, dynamic> item) {
  final v = item['lastUsedAt'] ?? item['last_used_at'];
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString());
}
