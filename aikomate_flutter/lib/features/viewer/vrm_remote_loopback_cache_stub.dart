/// Stub when `dart:io` is unavailable (e.g. Flutter web).
class VrmRemoteLoopbackCache {
  Future<String> cacheFromRemoteUrl(
    String remoteUrl, {
    String? templateId,
    void Function(double fraction)? onProgress,
    void Function({required bool fromSealedStore})? onSource,
  }) async =>
      remoteUrl;

  void dispose() {}
}
