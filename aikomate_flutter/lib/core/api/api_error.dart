/// Normalizes FastAPI-style JSON error bodies for display.
///
/// `HTTPException` responses typically use `{ "detail": "message" }`.
/// Validation errors often use `{ "detail": [ { "msg": "...", ... }, ... ] }`.
String messageFromApiDetail(
  dynamic detail, [
  String fallback = 'Request failed',
]) {
  if (detail == null) return fallback;
  if (detail is String) return detail;
  if (detail is List) {
    final parts = <String>[];
    for (final item in detail) {
      if (item is Map && item['msg'] != null) {
        parts.add(item['msg'].toString());
      } else {
        parts.add(item.toString());
      }
    }
    if (parts.isEmpty) return fallback;
    return parts.join('; ');
  }
  return detail.toString();
}

String messageFromErrorBody(
  Map<String, dynamic> data, [
  String fallback = 'Request failed',
]) {
  return messageFromApiDetail(data['detail'], fallback);
}
