import 'dart:async';
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../models/transcription.dart';
import '../models/playback_mode.dart';

class MediaPlayerProvider extends ChangeNotifier {
  YoutubePlayerController? _controller;
  Timer? _positionTimer;
  Transcription? _transcription;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  int? _currentSegmentIndex;
  bool _isInitialized = false;
  String? _errorMessage;
  bool _showTranslation = false;
  PlaybackMode _mode = PlaybackMode.video;
  bool _isPlaying = false;
  bool _durationFetched = false;
  int _seekVersion = 0;
  bool _isSeeking = false;
  Timer? _seekDebounceTimer;

  YoutubePlayerController? get controller => _controller;
  Duration get currentPosition => _currentPosition;
  Duration get totalDuration => _totalDuration;
  int? get currentSegmentIndex => _currentSegmentIndex;
  Transcription? get transcription => _transcription;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;
  bool get showTranslation => _showTranslation;
  PlaybackMode get mode => _mode;
  bool get isPlaying => _isPlaying;
  int get seekVersion => _seekVersion;

  Future<void> initializePlayer(
    String youtubeVideoId,
    Transcription transcription,
    PlaybackMode mode,
  ) async {
    _transcription = transcription;
    _mode = mode;
    await _initializeVideoPlayer(youtubeVideoId);
  }

  Future<void> _initializeVideoPlayer(String youtubeVideoId) async {
    _positionTimer?.cancel();
    await _controller?.close();
    _controller = null;

    _controller = YoutubePlayerController(
      params: YoutubePlayerParams(
        showControls: _mode.isVideo,
        mute: false,
        showFullscreenButton: _mode.isVideo,
        loop: false,
        enableCaption: false,
        origin: 'https://www.youtube-nocookie.com',
      ),
    );

    _controller!.cueVideoById(videoId: youtubeVideoId);

    _totalDuration = Duration.zero;
    _durationFetched = false;

    _isInitialized = true;
    _errorMessage = null;
    notifyListeners();

    _positionTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => _updatePosition(),
    );
  }

  void _updatePosition() async {
    if (_controller == null) return;

    // Position polling - runs every tick
    try {
      final position = await _controller!.currentTime;
      final positionDuration = Duration(milliseconds: (position * 1000).round());

      bool changed = false;

      // Skip position updates while seeking - keep manually set seek position
      if (!_isSeeking && positionDuration != _currentPosition) {
        _currentPosition = positionDuration;
        _updateCurrentSegment();
        changed = true;
      }

      final playerState = _controller!.value.playerState;
      if (_mode.isVideo) {
        // In video mode: YouTube native controls are the authority, keep in sync
        final actuallyPlaying = playerState == PlayerState.playing ||
            playerState == PlayerState.buffering;
        if (actuallyPlaying != _isPlaying) {
          _isPlaying = actuallyPlaying;
          changed = true;
        }
      } else {
        // In audio mode: custom controls are the authority, only stop on end
        if (_isPlaying && playerState == PlayerState.ended) {
          _isPlaying = false;
          changed = true;
        }
      }

      if (changed) notifyListeners();
    } catch (e) {
      // Position not available yet
    }

    // Duration polling - only until we get a valid value, with timeout
    if (!_durationFetched) {
      try {
        final durationSecs = await _controller!.duration
            .timeout(const Duration(milliseconds: 800));
        if (durationSecs > 0) {
          _totalDuration = Duration(milliseconds: (durationSecs * 1000).round());
          _durationFetched = true;
          notifyListeners();
        }
      } catch (e) {
        // Timeout or not available yet - will retry next tick
      }
    }
  }

  void _updateCurrentSegment() {
    if (_isSeeking) return; // Don't override segment while seek is processing
    if (_transcription == null) return;
    final segment = _transcription!.getCurrentSegment(_currentPosition);
    if (segment != null) {
      final index = _transcription!.segments.indexOf(segment);
      if (index != -1 && index != _currentSegmentIndex) {
        _currentSegmentIndex = index;
      }
    } else {
      if (_currentSegmentIndex != null) {
        _currentSegmentIndex = null;
      }
    }
  }

  Future<void> switchMode(PlaybackMode newMode, String youtubeVideoId) async {
    if (_mode == newMode) return;
    _mode = newMode;
    // Final sync of play state via async JS call (more reliable than cached value)
    try {
      final state = await _controller!.playerState
          .timeout(const Duration(milliseconds: 500));
      _isPlaying = state == PlayerState.playing || state == PlayerState.buffering;
    } catch (_) {
      // Fall back to cached value
      _isPlaying = _controller?.value.playerState == PlayerState.playing;
    }
    notifyListeners();
  }

  void seekToSegment(TranscriptionSegment segment) async {
    if (_transcription == null || _controller == null) return;
    try {
      final seekPosition = Duration(milliseconds: segment.startTime.inMilliseconds + 100);
      final seekTime = seekPosition.inMilliseconds / 1000.0;
      await _controller!.seekTo(seconds: seekTime, allowSeekAhead: true);
      await Future.delayed(const Duration(milliseconds: 300));
      await _controller!.playVideo();
      _isPlaying = true;
      _currentPosition = seekPosition;
      final index = _transcription!.segments.indexOf(segment);
      if (index != -1) _currentSegmentIndex = index;
      notifyListeners();
    } catch (e) {
      debugPrint('Error seeking: $e');
    }
  }

  void seekTo(double seconds) {
    _isSeeking = true;
    // Cancel any previous debounce timer so rapid seeks don't prematurely unlock
    _seekDebounceTimer?.cancel();

    // Fire-and-forget: don't await so multiple rapid calls can't race each other
    _controller?.seekTo(seconds: seconds, allowSeekAhead: true);
    _currentPosition = Duration(milliseconds: (seconds * 1000).round());
    _updateCurrentSegmentForSeek();
    _seekVersion++;
    notifyListeners();

    _seekDebounceTimer = Timer(const Duration(milliseconds: 600), () {
      _isSeeking = false;
      _seekDebounceTimer = null;
    });
  }

  // Like _updateCurrentSegment but also matches gaps between segments
  // by finding the last segment that started before the current position.
  void _updateCurrentSegmentForSeek() {
    if (_transcription == null) return;
    final segments = _transcription!.segments;

    // Check if position is within an active segment
    for (int i = 0; i < segments.length; i++) {
      if (segments[i].isActive(_currentPosition)) {
        _currentSegmentIndex = i;
        return;
      }
    }

    // In a gap: find the last segment that started before this position
    int? lastBefore;
    for (int i = 0; i < segments.length; i++) {
      if (segments[i].startTime <= _currentPosition) {
        lastBefore = i;
      } else {
        break;
      }
    }
    if (lastBefore != null) {
      _currentSegmentIndex = lastBefore;
    }
  }

  void play() {
    _controller?.playVideo();
    _isPlaying = true;
    notifyListeners();
  }

  void pause() {
    _controller?.pauseVideo();
    _isPlaying = false;
    notifyListeners();
  }

  void toggleTranslation() {
    _showTranslation = !_showTranslation;
    notifyListeners();
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _controller?.close();
    super.dispose();
  }
}
