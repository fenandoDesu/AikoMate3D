import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'read_platform_file_io.dart'
    if (dart.library.html) 'read_platform_file_stub.dart' as impl;

Future<Uint8List?> readPlatformFileBytes(PlatformFile f) async {
  final b = f.bytes;
  if (b != null) return b;
  return impl.readPathAsBytes(f.path);
}
