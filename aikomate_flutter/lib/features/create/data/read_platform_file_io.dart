import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readPathAsBytes(String? path) async {
  if (path == null) return null;
  return File(path).readAsBytes();
}
