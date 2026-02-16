import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/video_lesson.dart';
import '../providers/video_player_provider.dart';
import '../services/transcription_service.dart';
import '../widgets/video_player_widget.dart';
import '../widgets/transcription_list_widget.dart';
import '../widgets/responsive_video_layout.dart';

class VideoLessonScreen extends StatefulWidget {
  final VideoLesson videoLesson;

  const VideoLessonScreen({
    super.key,
    required this.videoLesson,
  });

  @override
  State<VideoLessonScreen> createState() => _VideoLessonScreenState();
}

class _VideoLessonScreenState extends State<VideoLessonScreen> {
  final TranscriptionService _transcriptionService = TranscriptionService();
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTranscriptionAndInitializePlayer();
  }

  Future<void> _loadTranscriptionAndInitializePlayer() async {
    try {
      final transcription = await _transcriptionService
          .loadTranscription(widget.videoLesson.transcriptionPath);

      if (mounted) {
        final provider = Provider.of<VideoPlayerProvider>(context, listen: false);
        provider.initializePlayer(
          widget.videoLesson.youtubeVideoId,
          transcription,
        );

        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load transcription: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.videoLesson.title),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
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
              : const ResponsiveVideoLayout(
                  videoPlayer: VideoPlayerWidget(),
                  transcriptionList: TranscriptionListWidget(),
                ),
    );
  }
}
