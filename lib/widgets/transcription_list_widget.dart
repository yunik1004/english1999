import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/video_player_provider.dart';
import 'transcription_segment_item.dart';

class TranscriptionListWidget extends StatefulWidget {
  const TranscriptionListWidget({super.key});

  @override
  State<TranscriptionListWidget> createState() =>
      _TranscriptionListWidgetState();
}

class _TranscriptionListWidgetState extends State<TranscriptionListWidget> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _segmentKeys = {};
  int? _previousSegmentIndex;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSegment(int segmentIndex) {
    final key = _segmentKeys[segmentIndex];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.3,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerProvider>(
      builder: (context, provider, _) {
        if (provider.transcription == null) {
          return const Center(
            child: Text('No transcription available'),
          );
        }

        final segments = provider.transcription!.segments;

        // Initialize keys for all segments
        for (int i = 0; i < segments.length; i++) {
          if (!_segmentKeys.containsKey(i)) {
            _segmentKeys[i] = GlobalKey();
          }
        }

        // Auto-scroll when segment changes
        if (provider.currentSegmentIndex != null &&
            provider.currentSegmentIndex != _previousSegmentIndex) {
          _previousSegmentIndex = provider.currentSegmentIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToSegment(provider.currentSegmentIndex!);
          });
        }

        return ListView.builder(
          controller: _scrollController,
          itemCount: segments.length,
          itemBuilder: (context, index) {
            final segment = segments[index];
            final isActive = index == provider.currentSegmentIndex;

            return TranscriptionSegmentItem(
              key: _segmentKeys[index],
              segment: segment,
              isActive: isActive,
              onTap: () => provider.seekToSegment(segment),
            );
          },
        );
      },
    );
  }
}
