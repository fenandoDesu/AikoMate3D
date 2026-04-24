/// Stub when `dart:io` is unavailable (e.g. Flutter web).
class UserBackgroundLoopback {
  Future<String?> toHttpUrlIfDeviceFile(String url) async => null;

  void dispose() {}
}
