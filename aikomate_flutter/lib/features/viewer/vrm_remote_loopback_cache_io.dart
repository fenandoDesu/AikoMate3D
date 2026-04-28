import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const _kSealingKeyName = 'aikomate_vrm_seal_aes256_v1';
const _kSealedDir = 'aikomate_vrm_sealed';
const _kSealMagic = [0x41, 0x49, 0x4b, 0x31]; // "AIK1"

/// Downloads a remote `.vrm` in Dart (no browser CORS), optionally persists an
/// **encrypted** copy in app-private storage (key only in secure storage), then
/// serves plaintext from a loopback URL with CORS for the WebView.
class VrmRemoteLoopbackCache {
  static const _secure = FlutterSecureStorage();

  HttpServer? _server;
  int _port = 0;
  final Map<int, File> _tokenToFile = {};
  int _nextToken = 1;

  void _addCors(HttpHeaders headers) {
    headers.set('Access-Control-Allow-Origin', '*');
    headers.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
    headers.set('Access-Control-Allow-Headers', '*');
  }

  Future<void> _ensureServer() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _port = server.port;
    server.listen((request) async {
      _addCors(request.response.headers);

      if (request.method == 'OPTIONS') {
        request.response.statusCode = 204;
        await request.response.close();
        return;
      }

      if (request.method != 'GET') {
        request.response.statusCode = 405;
        await request.response.close();
        return;
      }

      final segs = request.uri.pathSegments;
      if (segs.length != 2 || segs[0] != 'cached-vrm') {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }

      final token = int.tryParse(segs[1]);
      final file = token != null ? _tokenToFile[token] : null;
      if (file == null || !await file.exists()) {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }

      try {
        final bytes = await file.readAsBytes();
        request.response.headers.contentType = ContentType('model', 'vrm');
        request.response.add(bytes);
        await request.response.close();
      } catch (_) {
        request.response.statusCode = 500;
        await request.response.close();
      }
    });
  }

  Future<enc.Key> _loadSealingKey() async {
    final existing = await _secure.read(key: _kSealingKeyName);
    if (existing != null && existing.length >= 40) {
      return enc.Key.fromBase64(existing);
    }
    final k = enc.Key.fromSecureRandom(32);
    await _secure.write(key: _kSealingKeyName, value: k.base64);
    return k;
  }

  String _stemForCache(String? templateId, String remoteUrl) {
    final u = remoteUrl.trim();
    final idPart =
        (templateId != null && templateId.isNotEmpty)
            ? _sanitizeId(templateId)
            : 'noid';
    final h = u.hashCode.toRadixString(36).replaceAll('-', 'n');
    return '${idPart}_$h';
  }

  String _sanitizeId(String id) {
    final s = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (s.length <= 80) return s;
    return s.substring(0, 80);
  }

  Future<File> _sealedFile(String stem) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}$_kSealedDir');
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$stem.sealed');
  }

  Future<void> _writeSealed(enc.Key key, File sealed, Uint8List plain) async {
    final iv = enc.IV.fromLength(16);
    final encrypter = enc.Encrypter(enc.AES(key));
    final encrypted = encrypter.encryptBytes(plain, iv: iv);

    final out = BytesBuilder(copy: false);
    out.add(_kSealMagic);
    out.add(iv.bytes);
    out.add(encrypted.bytes);
    await sealed.writeAsBytes(out.toBytes(), flush: true);
  }

  Future<Uint8List> _readSealed(enc.Key key, File sealed) async {
    final raw = await sealed.readAsBytes();
    if (raw.length < 4 + 16 + 16) {
      throw const FormatException('Sealed VRM file too small');
    }
    for (var i = 0; i < 4; i++) {
      if (raw[i] != _kSealMagic[i]) {
        throw const FormatException('Invalid sealed VRM header');
      }
    }
    final iv = enc.IV(Uint8List.sublistView(raw, 4, 20));
    final cipher = Uint8List.sublistView(raw, 20);
    final encrypter = enc.Encrypter(enc.AES(key));
    return Uint8List.fromList(
      encrypter.decryptBytes(enc.Encrypted(cipher), iv: iv),
    );
  }

  Future<File> _writeSessionPlain(Uint8List plain) async {
    final tmp = await getTemporaryDirectory();
    final name =
        'aikomate_vrm_play_${DateTime.now().microsecondsSinceEpoch}_'
        '${math.Random.secure().nextInt(1 << 30)}.vrm';
    final f = File('${tmp.path}${Platform.pathSeparator}$name');
    await f.writeAsBytes(plain, flush: true);
    return f;
  }

  /// [onProgress] applies while downloading from the network (not when reading cache).
  /// [onSource] is `fromSealedStore: true` when bytes come from encrypted app-private cache.
  Future<String> cacheFromRemoteUrl(
    String remoteUrl, {
    String? templateId,
    void Function(double fraction)? onProgress,
    void Function({required bool fromSealedStore})? onSource,
  }) async {
    final trimmed = remoteUrl.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Empty VRM URL');
    }
    final uri = Uri.parse(trimmed);
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ArgumentError('Unsupported URL scheme: ${uri.scheme}');
    }

    await _ensureServer();

    final stem = _stemForCache(templateId, trimmed);
    final sealed = await _sealedFile(stem);
    final key = await _loadSealingKey();

    if (await sealed.exists() && await sealed.length() > 32) {
      try {
        onSource?.call(fromSealedStore: true);
        final plain = await _readSealed(key, sealed);
        final play = await _writeSessionPlain(plain);
        final token = _nextToken++;
        _tokenToFile[token] = play;
        return 'http://localhost:$_port/cached-vrm/$token';
      } catch (e, st) {
        debugPrint('Sealed VRM unreadable, re-downloading: $e\n$st');
        try {
          await sealed.delete();
        } catch (_) {}
      }
    }

    final client = http.Client();
    try {
      onSource?.call(fromSealedStore: false);
      final request = http.Request('GET', uri);
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'VRM download failed (${response.statusCode})',
          uri: uri,
        );
      }

      final builder = BytesBuilder(copy: false);
      final total = response.contentLength;
      var received = 0;

      await for (final chunk in response.stream) {
        builder.add(chunk);
        received += chunk.length;
        if (onProgress != null && total != null && total > 0) {
          onProgress(received / total);
        }
      }
      final plain = builder.takeBytes();

      try {
        await _writeSealed(key, sealed, plain);
      } catch (e, st) {
        debugPrint('Failed to write sealed VRM cache (non-fatal): $e\n$st');
      }

      final play = await _writeSessionPlain(plain);
      final token = _nextToken++;
      _tokenToFile[token] = play;
      return 'http://localhost:$_port/cached-vrm/$token';
    } finally {
      client.close();
    }
  }

  /// If [url] is a loopback URL returned by [cacheFromRemoteUrl], returns the
  /// backing local plaintext `.vrm` file path for native consumers (AR).
  String? localFilePathForLoopbackUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    final segs = uri.pathSegments;
    if (segs.length != 2 || segs[0] != 'cached-vrm') return null;

    final token = int.tryParse(segs[1]);
    if (token == null) return null;

    return _tokenToFile[token]?.path;
  }

  void dispose() {
    for (final f in _tokenToFile.values) {
      try {
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    _tokenToFile.clear();
    final s = _server;
    _server = null;
    if (s != null) {
      unawaited(s.close(force: true));
    }
  }
}
