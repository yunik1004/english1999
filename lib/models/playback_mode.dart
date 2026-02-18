/// Enum representing the playback mode for media content.
///
/// Used to switch between video and audio-only playback in the app.
enum PlaybackMode {
  /// Standard video playback with YouTube iframe player
  video,

  /// Audio-only playback with extracted audio stream
  audio;

  /// Human-readable display name for the mode
  String get displayName => this == video ? 'Video Mode' : 'Audio Only';

  /// Check if this mode is video
  bool get isVideo => this == video;

  /// Check if this mode is audio-only
  bool get isAudio => this == audio;
}
