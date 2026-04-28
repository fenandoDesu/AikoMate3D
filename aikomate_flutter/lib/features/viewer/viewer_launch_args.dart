/// Passed to [ViewerScreen] when opening from a template (Discover, etc.).
class ViewerLaunchArgs {
  const ViewerLaunchArgs({
    required this.vrmUrl,
    required this.displayName,
    this.templateId,
    this.personalityPrompt,
    this.userName,
    this.fishAudioId,
  });

  /// Public HTTPS URL of the `.vrm` file (R2 / CDN).
  final String vrmUrl;

  /// Used for encrypted on-disk cache + reuse across sessions.
  final String? templateId;

  /// Shown to the companion WS as `avatar_name`.
  final String displayName;

  /// Template persona; sent on the WS as `prompt` when non-empty.
  final String? personalityPrompt;

  /// Logged-in display name for `user_name`; falls back in [ViewerScreen].
  final String? userName;

  /// Fish Audio voice id override for the companion WS; omit on server when null.
  final String? fishAudioId;
}
