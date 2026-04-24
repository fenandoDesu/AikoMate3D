import 'dart:async';
import 'dart:io';

/// Serves user-picked files at `http://127.0.0.1:<port>/user-bg/<id>` so the
/// WebView (loaded from `http://localhost`) can load them. Plain `file://`
/// URLs are blocked as cross-origin from that page.
class UserBackgroundLoopback {
  HttpServer? _server;
  int _port = 0;
  final Map<int, String> _tokenToPath = {};
  final Map<String, int> _pathToToken = {};
  int _nextToken = 1;

  ContentType _contentTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return ContentType('image', 'jpeg');
    }
    if (lower.endsWith('.png')) return ContentType('image', 'png');
    if (lower.endsWith('.webp')) return ContentType('image', 'webp');
    if (lower.endsWith('.gif')) return ContentType('image', 'gif');
    if (lower.endsWith('.mp4')) return ContentType('video', 'mp4');
    if (lower.endsWith('.webm')) return ContentType('video', 'webm');
    if (lower.endsWith('.mov')) return ContentType('video', 'quicktime');
    if (lower.endsWith('.m4v')) return ContentType('video', 'x-m4v');
    if (lower.endsWith('.glb')) {
      return ContentType('application', 'octet-stream');
    }
    if (lower.endsWith('.gltf')) return ContentType('model', 'gltf+json');
    return ContentType('application', 'octet-stream');
  }

  void _addCors(HttpHeaders headers) {
    // Page is http://localhost:8080; user media is another loopback port — different
    // origin. Three/WebGL requires CORS when TextureLoader uses crossOrigin=anonymous.
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
      if (segs.length != 2 || segs[0] != 'user-bg') {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      final token = int.tryParse(segs[1]);
      final path = token != null ? _tokenToPath[token] : null;
      if (path == null) {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      try {
        final file = File(path);
        if (!await file.exists()) {
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }
        final bytes = await file.readAsBytes();
        request.response.headers.contentType = _contentTypeForPath(path);
        request.response.add(bytes);
        await request.response.close();
      } catch (_) {
        request.response.statusCode = 500;
        await request.response.close();
      }
    });
  }

  int _tokenForPath(String path) {
    return _pathToToken.putIfAbsent(path, () {
      final id = _nextToken++;
      _tokenToPath[id] = path;
      return id;
    });
  }

  String? _localPathFromUrl(String url) {
    final t = url.trim();
    if (t.isEmpty) return null;
    if (t.startsWith('file://')) {
      try {
        return Uri.parse(t).toFilePath();
      } catch (_) {
        return null;
      }
    }
    if (!t.contains('://')) {
      if (t.startsWith('/')) return t;
      if (RegExp(r'^[A-Za-z]:[/\\]').hasMatch(t)) return t;
    }
    return null;
  }

  /// Returns an `http://127.0.0.1:...` URL if [url] refers to a readable local
  /// file, otherwise `null`.
  Future<String?> toHttpUrlIfDeviceFile(String url) async {
    final path = _localPathFromUrl(url);
    if (path == null) return null;
    if (!await File(path).exists()) return null;
    await _ensureServer();
    final token = _tokenForPath(path);
    // Use `localhost` (same host name as InAppLocalhostServer) + CORS — avoids
    // extra strictness around 127.0.0.1 vs localhost in some WebViews.
    return 'http://localhost:$_port/user-bg/$token';
  }

  void dispose() {
    final s = _server;
    _server = null;
    if (s != null) {
      unawaited(s.close(force: true));
    }
  }
}
