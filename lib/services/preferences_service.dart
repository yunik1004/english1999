import 'package:shared_preferences/shared_preferences.dart';
import '../models/playback_mode.dart';

/// Service for managing user preferences with persistent storage.
///
/// Follows the same caching pattern as TranscriptionService and VersionService.
/// Uses SharedPreferences for simple key-value storage.
class PreferencesService {
  static const String _playbackModeKey = 'playback_mode';

  SharedPreferences? _prefs;

  /// Initialize the preferences service by loading SharedPreferences instance.
  ///
  /// Should be called early in app lifecycle (typically in main()).
  /// Uses ??= to ensure initialization happens only once.
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Get the user's saved playback mode preference.
  ///
  /// Returns PlaybackMode.video by default if no preference is saved.
  /// Automatically initializes if not already initialized.
  Future<PlaybackMode> getPlaybackMode() async {
    await initialize();
    final mode = _prefs!.getString(_playbackModeKey) ?? 'video';
    return mode == 'audio' ? PlaybackMode.audio : PlaybackMode.video;
  }

  /// Save the user's playback mode preference.
  ///
  /// Persists across app restarts.
  Future<void> setPlaybackMode(PlaybackMode mode) async {
    await initialize();
    await _prefs!.setString(_playbackModeKey, mode.name);
  }
}
