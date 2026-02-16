import 'dart:async';
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../models/transcription.dart';

class VideoPlayerProvider extends ChangeNotifier {
  YoutubePlayerController? _controller;
  Timer? _positionTimer;
  Transcription? _transcription;
  Duration _currentPosition = Duration.zero;
  int? _currentSegmentIndex;
  bool _isInitialized = false;
  String? _errorMessage;

  YoutubePlayerController? get controller => _controller;
  Duration get currentPosition => _currentPosition;
  int? get currentSegmentIndex => _currentSegmentIndex;
  Transcription? get transcription => _transcription;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;

  void initializePlayer(String youtubeVideoId, Transcription transcription) {
    _transcription = transcription;

    _controller = YoutubePlayerController.fromVideoId(
      videoId: youtubeVideoId,
      autoPlay: false,
      params: const YoutubePlayerParams(
        showControls: true,
        mute: false,
        showFullscreenButton: true,
        loop: false,
        enableCaption: false,
      ),
    );

    _isInitialized = true;
    notifyListeners();

    // Start position polling
    _positionTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => _updatePosition(),
    );
  }

  void _updatePosition() async {
    if (_controller == null) {
      return;
    }

    try {
      final position = await _controller!.currentTime;
      final positionDuration = Duration(milliseconds: (position * 1000).round());

      if (positionDuration != _currentPosition) {
        _currentPosition = positionDuration;
        _updateCurrentSegment();
        notifyListeners();
      }
    } catch (e) {
      // Position not available yet, ignore
    }
  }

  void _updateCurrentSegment() {
    if (_transcription == null) return;

    final segment = _transcription!.getCurrentSegment(_currentPosition);
    if (segment != null) {
      final index = _transcription!.segments.indexOf(segment);
      if (index != -1 && index != _currentSegmentIndex) {
        _currentSegmentIndex = index;
      }
    } else {
      // No active segment - clear current segment
      if (_currentSegmentIndex != null) {
        _currentSegmentIndex = null;
      }
    }
  }

  void seekToSegment(TranscriptionSegment segment) async {
    if (_controller == null || _transcription == null) return;

    try {
      // Add 0.1 seconds to ensure we're inside the target segment
      final seekTime = (segment.startTime.inMilliseconds + 100) / 1000.0;

      // Try direct seek with allowSeekAhead flag
      await _controller!.seekTo(seconds: seekTime, allowSeekAhead: true);

      // Wait a moment for seek to process
      await Future.delayed(const Duration(milliseconds: 300));

      // Play the video
      await _controller!.playVideo();

      // Update state with the adjusted time
      _currentPosition = Duration(milliseconds: segment.startTime.inMilliseconds + 100);
      final index = _transcription!.segments.indexOf(segment);
      if (index != -1) {
        _currentSegmentIndex = index;
      }
      notifyListeners();

      debugPrint('Seeked to ${seekTime}s for segment: ${segment.text}');
    } catch (e) {
      debugPrint('Error seeking: $e');
    }
  }

  void play() {
    _controller?.playVideo();
    notifyListeners();
  }

  void pause() {
    _controller?.pauseVideo();
    notifyListeners();
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _controller?.close();
    super.dispose();
  }
}
