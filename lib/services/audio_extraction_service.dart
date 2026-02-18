import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Service for extracting audio stream URLs from YouTube videos.
///
/// Uses youtube_explode_dart to obtain direct audio URLs that can be
/// streamed with just_audio. Implements in-memory caching to avoid
/// repeated extraction calls for the same video.
class AudioExtractionService {
  final Map<String, String> _urlCache = {};
  final YoutubeExplode _yt = YoutubeExplode();

  /// Extract the audio stream URL for a YouTube video.
  ///
  /// Returns a direct URL to the highest bitrate audio stream.
  /// The URL is cached for the session to avoid repeated API calls.
  /// Audio URLs are typically valid for several hours.
  ///
  /// Throws an Exception if the video is unavailable, region-blocked,
  /// or if extraction fails for any other reason.
  Future<String> getAudioUrl(String youtubeVideoId) async {
    print('🔍 [AUDIO EXTRACTION] Starting extraction for: $youtubeVideoId');

    // Check cache first
    if (_urlCache.containsKey(youtubeVideoId)) {
      print('✅ [AUDIO EXTRACTION] Found in cache!');
      return _urlCache[youtubeVideoId]!;
    }

    try {
      // Extract audio stream manifest
      print('🔍 [AUDIO EXTRACTION] Fetching manifest...');
      final manifest =
          await _yt.videos.streamsClient.getManifest(youtubeVideoId);
      print('🔍 [AUDIO EXTRACTION] Got manifest, finding audio streams...');

      // Get the audio stream with highest bitrate
      final audioStream = manifest.audioOnly.withHighestBitrate();
      final url = audioStream.url.toString();
      print('✅ [AUDIO EXTRACTION] Got audio URL: ${url.substring(0, 100)}...');

      // Cache for session
      _urlCache[youtubeVideoId] = url;
      return url;
    } catch (e, stackTrace) {
      print('❌ [AUDIO EXTRACTION ERROR] Failed: $e');
      print('❌ [AUDIO EXTRACTION ERROR] Stack: $stackTrace');
      throw Exception('Failed to extract audio: $e');
    }
  }

  /// Dispose of resources when service is no longer needed.
  ///
  /// Should be called when the provider using this service is disposed.
  void dispose() {
    _yt.close();
  }
}
