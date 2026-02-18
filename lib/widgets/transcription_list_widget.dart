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
  final _listKey = GlobalKey();
  final Map<int, GlobalKey> _segmentKeys = {};
  int? _previousSegmentIndex;
  bool? _previousShowTranslation;
  int _previousSeekVersion = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _compensateScrollForHeightChange(int? activeIndex) {
    if (!_scrollController.hasClients) return;

    // Get the ListView's bounds on screen to determine visibility.
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null || !listBox.attached) return;
    final listTop = listBox.localToGlobal(Offset.zero).dy;
    final listBottom = listTop + listBox.size.height;

    bool _isVisible(RenderBox box) {
      final y = box.localToGlobal(Offset.zero).dy;
      final h = box.size.height;
      return y + h > listTop && y < listBottom;
    }

    // During build(), RenderObjects still hold the OLD layout — read positions now.
    int? anchorIndex;
    double anchorScreenY = 0.0;

    // Priority 1: use the active (highlighted) segment if it's visible.
    if (activeIndex != null) {
      final ctx = _segmentKeys[activeIndex]?.currentContext;
      if (ctx != null) {
        final box = ctx.findRenderObject() as RenderBox?;
        if (box != null && box.attached && _isVisible(box)) {
          anchorIndex = activeIndex;
          anchorScreenY = box.localToGlobal(Offset.zero).dy;
        }
      }
    }

    // Priority 2: item closest to the vertical center of the list.
    if (anchorIndex == null) {
      final listCenter = (listTop + listBottom) / 2;
      double bestDist = double.infinity;
      for (int i = 0; i < _segmentKeys.length; i++) {
        final ctx = _segmentKeys[i]?.currentContext;
        if (ctx == null) continue;
        final box = ctx.findRenderObject() as RenderBox?;
        if (box == null || !box.attached || !_isVisible(box)) continue;
        final itemCenter = box.localToGlobal(Offset.zero).dy + box.size.height / 2;
        final dist = (itemCenter - listCenter).abs();
        if (dist < bestDist) {
          bestDist = dist;
          anchorIndex = i;
          anchorScreenY = box.localToGlobal(Offset.zero).dy;
        }
      }
    }

    if (anchorIndex == null) return;
    final savedIndex = anchorIndex;
    final savedY = anchorScreenY;

    // After the new layout is rendered, restore the anchor item to its exact position.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final ctx = _segmentKeys[savedIndex]?.currentContext;
      if (ctx == null) return;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) return;
      final newY = box.localToGlobal(Offset.zero).dy;
      final diff = newY - savedY;
      if (diff.abs() > 0.5) {
        _scrollController.jumpTo(
          (_scrollController.offset + diff)
              .clamp(0.0, _scrollController.position.maxScrollExtent),
        );
      }
    });
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

        // When translation is toggled, all item heights change.
        // Compensate scroll offset so the first visible item stays in place.
        if (translationChanged) {
          _compensateScrollForHeightChange(provider.currentSegmentIndex);
        }

        // Auto-scroll when segment changes during playback
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
          key: _listKey,
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
