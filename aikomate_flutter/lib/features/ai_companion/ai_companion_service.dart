import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
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
  /// Fish Audio sends 16-bit LE mono PCM at 44.1 kHz.
  static const _defaultSampleRate = 44100;

  final ValueNotifier<AiCompanionConnectionState> connectionState =
      ValueNotifier(AiCompanionConnectionState.idle);
  final StreamController<String> _logController = StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _eventController =
      StreamController.broadcast();

  final String avatarName;
  final String userName;

  WebSocketChannel? _channel;
  StreamSubscription? _wsSubscription;
  Future<void>? _connectionFuture;
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription? _playerSubscription;
  final List<Uint8List> _audioQueue = [];
  final List<double> _audioDurationQueue = [];
  final List<int> _pendingAudio = [];
  bool _isPlaying = false;
  bool _disposed = false;
  bool _audioStarted = false;
  bool _streamEnded = false;
  double _queuedAudioDuration = 0.0;
  double _audioDurationAccum = 0.0;
  List<Map<String, dynamic>> _fullPhonemes = [];
  Map<String, dynamic>? _pendingStartSpeech;
  String _replyText = '';

  AiCompanionService({
    this.avatarName = "Haruna",
    this.userName = "Fernando",
  }) {
    _playerSubscription =
        _player.onPlayerComplete.listen((_) => _handlePlaybackComplete());
  }

  Stream<String> get logStream => _logController.stream;
  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;

  void _emitEvent(Map<String, dynamic> event) {
    if (_disposed) return;
    _eventController.add(event);
  }

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
    final fishAudioId = "a2fcdd688eed4521baf39ffc05ca7d3f";
    final intimacyLevel = 4;

    final payload = jsonEncode({
      "text": text,
      "language": language,
      "avatar_name": avatarName,
      "user_name": userName,
      "fish_audio_id": fishAudioId,
      "intimacy": intimacyLevel,
    });

    Future<void> attemptSend() async {
      print('Companion WS send -> "$text" [$language]');
      _channel!.sink.add(payload);
      _logController.add("Sent text: $text");
      _pendingAudio.clear();
    }

    try {
      await attemptSend();
    } catch (error) {
      // Retry once after forcing a reconnect (helps if AR reopens after idle).
      _logController.add("Send failed, retrying: $error");
      _channel = null;
      connectionState.value = AiCompanionConnectionState.idle;
      await ensureConnected();
      if (_channel == null) {
        throw StateError("WebSocket not available after retry");
      }
      await attemptSend();
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
      final textPreview = data.toString();
      final preview = textPreview.substring(0, math.min(120, textPreview.length));
      print('Companion WS text msg: $preview');
      _handleJsonMessage(jsonDecode(data));
      return;
    }

    if (data is List<int>) {
      print('Companion WS binary chunk: ${data.length} bytes');
      _pendingAudio.addAll(data);
    }
  }

  void _handleJsonMessage(Map<String, dynamic> message) {
    final type = message["type"];
    if (type == null) return;

    switch (type) {
      case "stream_start":
        print('Companion WS: stream_start');
        _pendingAudio.clear();
        _audioQueue.clear();
        _audioDurationQueue.clear();
        _isPlaying = false;
        _audioStarted = false;
        _streamEnded = false;
        _queuedAudioDuration = 0.0;
        _audioDurationAccum = 0.0;
        _fullPhonemes = [];
        _pendingStartSpeech = null;
        _replyText = '';
        _player.stop();
        break;
      case "sentence_chunk":
        _handleSentenceChunk(message);
        break;
      case "sentence_audio_end":
        print('Companion WS: sentence_audio_end');
        if (message["is_last"] == true) {
          _streamEnded = true;
        }
        _flushPendingAudio();
        break;
      case "turn_end":
        print('Companion WS: turn_end');
        _streamEnded = true;
        _flushPendingAudio();
        _maybeEndSpeech();
        break;
      case "error":
        _logController.add("Server error: ${message["message"]}");
        _pendingAudio.clear();
        _audioQueue.clear();
        _audioDurationQueue.clear();
        break;
    }
  }

  void _handleSentenceChunk(Map<String, dynamic> message) {
    final text = message["text"] as String? ?? '';
    if (text.isNotEmpty) {
      _replyText = '$_replyText $text'.trim();
    }

    final phonemeList = message["phonemes"] as List<dynamic>? ?? [];
    double offset = 0.0;
    if (_fullPhonemes.isNotEmpty) {
      final last = _fullPhonemes.last;
      offset =
          (last["start"] as num).toDouble() + (last["duration"] as num).toDouble();
    }

    for (final raw in phonemeList) {
      if (raw is! Map) continue;
      final phoneme = raw["phoneme"]?.toString();
      final start = raw["start"];
      final duration = raw["duration"];
      if (phoneme == null || start is! num || duration is! num) continue;
      _fullPhonemes.add({
        "phoneme": phoneme,
        "start": start.toDouble() + offset,
        "duration": duration.toDouble(),
      });
    }

    final phonemeSnapshot =
        List<Map<String, dynamic>>.from(_fullPhonemes);
    if (_pendingStartSpeech == null && !_audioStarted) {
      _pendingStartSpeech = {
        "event": "start_speech",
        "phonemes": phonemeSnapshot,
        "reply_text": _replyText.trim(),
        "audioDuration": _audioDurationAccum + _queuedAudioDuration,
      };
    } else if (_audioStarted) {
      _emitEvent({
        "event": "update_phonemes",
        "phonemes": phonemeSnapshot,
        "audioDuration": _audioDurationAccum + _queuedAudioDuration,
      });
    }
  }

  void _maybeEndSpeech() {
    if (!_streamEnded) return;
    if (_isPlaying || _audioQueue.isNotEmpty) return;
    _emitEvent({
      "event": "end_speech",
      "reply_text": _replyText.trim(),
    });
    _streamEnded = false;
    _audioStarted = false;
    _pendingStartSpeech = null;
  }

  void _flushPendingAudio() {
    if (_pendingAudio.isEmpty) return;
    final buffer = Uint8List.fromList(_pendingAudio);
    _pendingAudio.clear();
    print('Companion flush audio: ${buffer.length} bytes');

    final pcm = _extractPlayablePcm(buffer);
    if (pcm == null) {
      _logController.add("Dropped ${buffer.length} bytes of audio (unknown format)");
      return;
    }

    final wav = _buildWav(pcm, sampleRate: _defaultSampleRate);
    final durationSec = pcm.length / 2 / _defaultSampleRate;
    _audioQueue.add(wav);
    _audioDurationQueue.add(durationSec);
    _queuedAudioDuration += durationSec;
    if (!_audioStarted) {
      _audioStarted = true;
      if (_pendingStartSpeech != null) {
        _pendingStartSpeech!["audioDuration"] =
            _audioDurationAccum + _queuedAudioDuration;
        _emitEvent(_pendingStartSpeech!);
        _pendingStartSpeech = null;
      }
    }
    _schedulePlayNext();
  }

  Uint8List? _extractPlayablePcm(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    // Fish Audio sends int16 PCM; try that first so we don't accidentally
    // halve the sample count by reinterpreting as float32.
    final int16 = _tryInt16(bytes);
    if (int16 != null) return int16;
    return _tryFloat32(bytes);
  }

  Uint8List? _tryFloat32(Uint8List bytes) {
    if (bytes.length < 4) return null;

    final count = bytes.length ~/ 4;
    if (count < 4) return null;
    final floatBuffer = Float32List.view(bytes.buffer, bytes.offsetInBytes, count);
    final maxAbs = floatBuffer.fold<double>(0.0, (prev, value) => math.max(prev, value.abs()));
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
    final maxAbs = ints.fold<int>(0, (prev, value) => math.max(prev, value.abs()));
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
    const channels = 1;
    const bytesPerSample = 2;
    final byteRate = sampleRate * channels * bytesPerSample;
    final blockAlign = channels * bytesPerSample;

    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bytesPerSample * 8, Endian.little);
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
    if (_audioDurationQueue.isNotEmpty) {
      final duration = _audioDurationQueue.removeAt(0);
      _audioDurationAccum += duration;
      _queuedAudioDuration =
          math.max(0.0, _queuedAudioDuration - duration);
    }
    if (_audioQueue.isNotEmpty) {
      _schedulePlayNext();
    }
    _maybeEndSpeech();
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
    await _eventController.close();
    connectionState.dispose();
    await _channel?.sink.close();
    _channel = null;
  }
}
