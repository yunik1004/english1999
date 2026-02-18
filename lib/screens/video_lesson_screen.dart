import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/video_lesson.dart';
import '../models/playback_mode.dart';
import '../providers/video_player_provider.dart';
import '../services/transcription_service.dart';
import '../services/preferences_service.dart';
import '../widgets/video_player_widget.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/transcription_list_widget.dart';
import '../widgets/responsive_video_layout.dart';

class VideoLessonScreen extends StatefulWidget {
  final VideoLesson videoLesson;
  final String chapterId;
  final String subchapterTitle;

  const VideoLessonScreen({
    super.key,
    required this.videoLesson,
    required this.chapterId,
    required this.subchapterTitle,
  });

  @override
  State<VideoLessonScreen> createState() => _VideoLessonScreenState();
}

class _VideoLessonScreenState extends State<VideoLessonScreen> {
  final TranscriptionService _transcriptionService = TranscriptionService();
  final PreferencesService _preferencesService = PreferencesService();
  bool _isLoading = true;
  String? _errorMessage;
  PlaybackMode _playbackMode = PlaybackMode.video;
  bool _isSwitchingMode = false;

  @override
  void initState() {
    super.initState();
    _loadTranscriptionAndInitializePlayer();
  }

  Future<void> _loadTranscriptionAndInitializePlayer() async {
    try {
      final transcription = await _transcriptionService
          .loadTranscription(widget.videoLesson.transcriptionPath);

      // Always start with video mode (audio mode has compatibility issues in web browsers)
      _playbackMode = PlaybackMode.video;

      if (mounted) {
        final provider = Provider.of<MediaPlayerProvider>(context, listen: false);
        await provider.initializePlayer(
          widget.videoLesson.youtubeVideoId,
          transcription,
          _playbackMode,
        );

        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/story/${widget.chapterId}'),
        ),
        title: Text(widget.subchapterTitle),
        actions: [
          // Mode toggle button
          Consumer<MediaPlayerProvider>(
            builder: (context, provider, _) {
              // Show loading indicator if switching
              if (_isSwitchingMode) {
                return Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                );
              }

              return IconButton(
                icon: Icon(
                  provider.mode.isAudio ? Icons.headphones : Icons.videocam,
                  color: provider.mode.isAudio
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                tooltip: provider.mode.isAudio
                    ? 'Switch to Video Mode'
                    : 'Switch to Audio Only',
                onPressed: _isSwitchingMode
                    ? null // Disable button during switch
                    : () async {
                        // Set switching flag
                        setState(() {
                          _isSwitchingMode = true;
                        });

                        try {
                          // Toggle mode
                          final newMode = provider.mode.isAudio
                              ? PlaybackMode.video
                              : PlaybackMode.audio;

                          // Switch mode in provider
                          await provider.switchMode(
                            newMode,
                            widget.videoLesson.youtubeVideoId,
                          );

                          // Save preference
                          await _preferencesService.setPlaybackMode(newMode);

                          // Update local state
                          setState(() {
                            _playbackMode = newMode;
                          });
                        } finally {
                          // Always clear switching flag
                          if (mounted) {
                            setState(() {
                              _isSwitchingMode = false;
                            });
                          }
                        }
                      },
              );
            },
          ),

          // Translation toggle
          Consumer<MediaPlayerProvider>(
            builder: (context, provider, _) {
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: IconButton(
                  icon: Icon(
                    Icons.translate,
                    color: provider.showTranslation
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  tooltip: provider.showTranslation ? 'Hide translation' : 'Show translation',
                  onPressed: provider.toggleTranslation,
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                )
              : Consumer<MediaPlayerProvider>(
                  builder: (context, provider, _) {
                    return ResponsiveVideoLayout(
                      videoPlayer: Stack(
                        children: [
                          // YouTube player always visible in DOM (Opacity keeps iframe playing)
                          // Offstage would apply display:none and pause the iframe
                          IgnorePointer(
                            ignoring: provider.mode.isAudio,
                            child: Opacity(
                              opacity: provider.mode.isAudio ? 0.0 : 1.0,
                              child: const VideoPlayerWidget(),
                            ),
                          ),
                          // Audio UI fills same space as video player
                          if (provider.mode.isAudio)
                            const Positioned.fill(
                              child: AudioPlayerWidget(),
                            ),
                        ],
                      ),
                      transcriptionList: const TranscriptionListWidget(),
                    );
                  },
                ),
    );
  }
}
