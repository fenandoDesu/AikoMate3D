import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:aikomate_flutter/core/config/env.dart';
import 'package:aikomate_flutter/core/storage/secure_storage.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum AiCompanionConnectionState { idle, connecting, ready, error }

/// Manages the connection with the companion WS endpoint and plays the
/// streamed audio as soon as it completes.
class AiCompanionService {
  static const _defaultSampleRate = 48000;

  final ValueNotifier<AiCompanionConnectionState> connectionState =
      ValueNotifier(AiCompanionConnectionState.idle);
  final StreamController<String> _logController = StreamController.broadcast();

  final String avatarName;
  final String userName;

  WebSocketChannel? _channel;
  StreamSubscription? _wsSubscription;
  Future<void>? _connectionFuture;
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription? _playerSubscription;
  final List<Uint8List> _audioQueue = [];
  final List<int> _pendingAudio = [];
  bool _isPlaying = false;
  bool _disposed = false;

  AiCompanionService({
    this.avatarName = "Haruna",
    this.userName = "Guest",
  }) {
    _playerSubscription =
        _player.onPlayerComplete.listen((_) => _handlePlaybackComplete());
  }

  Stream<String> get logStream => _logController.stream;

  Future<void> ensureConnected() async {
    if (_disposed) return;
    if (_channel != null) return;
    if (_connectionFuture != null) {
      return _connectionFuture!;
    }

    _connectionFuture = _connect();
    try {
      await _connectionFuture;
    } finally {
      _connectionFuture = null;
    }
  }

  Future<void> sendMessage({
    required String text,
    String language = 'en-US',
  }) async {
    await ensureConnected();
    if (_channel == null) {
      throw StateError("WebSocket not available");
    }

    final payload = jsonEncode({
      "text": text,
      "language": language,
      "avatar_name": avatarName,
      "user_name": userName,
    });

    try {
      _channel!.sink.add(payload);
      _logController.add("Sent text: $text");
      _pendingAudio.clear();
    } catch (error) {
      _logController.add("Send failed: $error");
      _channel = null;
      connectionState.value = AiCompanionConnectionState.idle;
      rethrow;
    }
  }

  Future<void> _connect() async {
    connectionState.value = AiCompanionConnectionState.connecting;
    final token = await SecureStorage.getToken();
    if (token == null) {
      connectionState.value = AiCompanionConnectionState.error;
      throw StateError("Missing auth token");
    }

    final uri = Uri.parse(Env.chatWsUrl);
    _channel = IOWebSocketChannel.connect(uri, headers: {
      "Authorization": "Bearer $token",
    });

    _wsSubscription = _channel!.stream.listen(
      _handleRawMessage,
      onDone: _handleDone,
      onError: _handleError,
      cancelOnError: true,
    );

    connectionState.value = AiCompanionConnectionState.ready;
    _logController.add("Connected to companion (WS)");
  }

  void _handleRawMessage(dynamic data) {
    if (_disposed) return;
    if (data is String) {
      _handleJsonMessage(jsonDecode(data));
      return;
    }

    if (data is List<int>) {
      _pendingAudio.addAll(data);
    }
  }

  void _handleJsonMessage(Map<String, dynamic> message) {
    final type = message["type"];
    if (type == null) return;

    switch (type) {
      case "stream_start":
        _pendingAudio.clear();
        _audioQueue.clear();
        _isPlaying = false;
        _player.stop();
        break;
      case "sentence_audio_end":
        _flushPendingAudio();
        break;
      case "turn_end":
        _flushPendingAudio();
        break;
      case "error":
        _logController.add("Server error: ${message["message"]}");
        _pendingAudio.clear();
        _audioQueue.clear();
        break;
    }
  }

  void _flushPendingAudio() {
    if (_pendingAudio.isEmpty) return;
    final buffer = Uint8List.fromList(_pendingAudio);
    _pendingAudio.clear();

    final pcm = _extractPlayablePcm(buffer);
    if (pcm == null) {
      _logController.add("Dropped ${buffer.length} bytes of audio (unknown format)");
      return;
    }

    final wav = _buildWav(pcm, sampleRate: _defaultSampleRate);
    _audioQueue.add(wav);
    _schedulePlayNext();
  }

  Uint8List? _extractPlayablePcm(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    final floatCandidate = _tryFloat32(bytes);
    if (floatCandidate != null) return floatCandidate;
    return _tryInt16(bytes);
  }

  Uint8List? _tryFloat32(Uint8List bytes) {
    if (bytes.length < 4) return null;

    final count = bytes.length ~/ 4;
    if (count < 4) return null;
    final floatBuffer = Float32List.view(bytes.buffer, bytes.offsetInBytes, count);
    final maxAbs = floatBuffer.fold<double>(0.0, (prev, value) => max(prev, value.abs()));
    if (maxAbs <= 0.01) return null;

    final output = Int16List(count);
    for (var i = 0; i < count; i++) {
      final value = floatBuffer[i];
      if (value.isNaN) continue;
      final clamped = value.clamp(-1.0, 1.0);
      output[i] = (clamped * 32767).round();
    }

    return output.buffer.asUint8List();
  }

  Uint8List? _tryInt16(Uint8List bytes) {
    if (bytes.length < 2) return null;

    final count = bytes.length ~/ 2;
    if (count < 4) return null;
    final ints = Int16List.view(bytes.buffer, bytes.offsetInBytes, count);
    final maxAbs = ints.fold<int>(0, (prev, value) => max(prev, value.abs()));
    if (maxAbs <= 100) return null;

    final trimmed = bytes.sublist(0, count * 2);
    return Uint8List.fromList(trimmed);
  }

  Uint8List _buildWav(Uint8List pcm, {required int sampleRate}) {
    final header = ByteData(44);
    header.setUint32(0, _fourcc('RIFF'), Endian.little);
    header.setUint32(4, 36 + pcm.length, Endian.little);
    header.setUint32(8, _fourcc('WAVE'), Endian.little);
    header.setUint32(12, _fourcc('fmt '), Endian.little);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    header.setUint32(36, _fourcc('data'), Endian.little);
    header.setUint32(40, pcm.length, Endian.little);

    final builder = BytesBuilder(copy: false);
    builder.add(header.buffer.asUint8List());
    builder.add(pcm);
    return builder.toBytes();
  }

  int _fourcc(String tag) {
    final codes = tag.codeUnits;
    if (codes.length != 4) throw ArgumentError("Tag must be 4 characters");
    return codes[0] | (codes[1] << 8) | (codes[2] << 16) | (codes[3] << 24);
  }

  void _schedulePlayNext() {
    if (_isPlaying || _audioQueue.isEmpty || _disposed) return;
    final chunk = _audioQueue.removeAt(0);
    _isPlaying = true;

    _player.play(BytesSource(chunk)).catchError((error) {
      _logController.add("Playback error: $error");
      _isPlaying = false;
      _schedulePlayNext();
    });
  }

  void _handlePlaybackComplete() {
    _isPlaying = false;
    if (_audioQueue.isNotEmpty) {
      _schedulePlayNext();
    }
  }

  void _handleDone() {
    _logController.add("Connection closed.");
    _channel = null;
    connectionState.value = AiCompanionConnectionState.idle;
  }

  void _handleError(dynamic error) {
    _logController.add("WS error: $error");
    _channel = null;
    connectionState.value = AiCompanionConnectionState.error;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _player.stop();
    await _player.release();
    await _playerSubscription?.cancel();
    await _wsSubscription?.cancel();
    await _logController.close();
    connectionState.dispose();
    await _channel?.sink.close();
    _channel = null;
  }
}
