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
  bool? _previousShowTranslation;
  int _previousSeekVersion = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSegment(int segmentIndex) {
    final key = _segmentKeys[segmentIndex];

    // If the widget is already rendered, scroll directly
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.3,
      );
      return;
    }

    // Widget not yet rendered (outside ListView's build window).
    // Jump to an estimated position to bring it into the render area,
    // then ensureVisible once it's built.
    if (!_scrollController.hasClients) return;
    final totalSegments = _segmentKeys.length;
    if (totalSegments == 0) return;

    final maxExtent = _scrollController.position.maxScrollExtent;
    final estimatedOffset = (segmentIndex / totalSegments) * maxExtent;
    _scrollController.jumpTo(estimatedOffset.clamp(0.0, maxExtent));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          alignment: 0.3,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MediaPlayerProvider>(
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

        // Check if only translation state changed (not segment)
        final translationChanged = _previousShowTranslation != null &&
            _previousShowTranslation != provider.showTranslation;
        _previousShowTranslation = provider.showTranslation;

        // Force scroll on explicit seek (slider drag), regardless of segment change
        final seeked = provider.seekVersion != _previousSeekVersion;
        if (seeked) {
          _previousSeekVersion = provider.seekVersion;
          if (provider.currentSegmentIndex != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToSegment(provider.currentSegmentIndex!);
            });
          }
        }

        // Auto-scroll when segment changes during playback (but not on translation toggle)
        if (!translationChanged &&
            !seeked &&
            provider.currentSegmentIndex != null &&
            provider.currentSegmentIndex != _previousSegmentIndex) {
          _previousSegmentIndex = provider.currentSegmentIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToSegment(provider.currentSegmentIndex!);
          });
        }
        if (seeked) _previousSegmentIndex = provider.currentSegmentIndex;

        return ListView.builder(
          controller: _scrollController,
          itemCount: segments.length,
          cacheExtent: 2000,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          itemBuilder: (context, index) {
            final segment = segments[index];
            final isActive = index == provider.currentSegmentIndex;

            return RepaintBoundary(
              child: TranscriptionSegmentItem(
                key: _segmentKeys[index],
                segment: segment,
                isActive: isActive,
                showTranslation: provider.showTranslation,
                onTap: () => provider.seekToSegment(segment),
              ),
            );
          },
        );
      },
    );
  }
}
