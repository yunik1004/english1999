import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/video_player_provider.dart';

class AudioPlayerWidget extends StatefulWidget {
  const AudioPlayerWidget({super.key});

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  double? _dragValue;

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MediaPlayerProvider>(
      builder: (context, provider, _) {
        final position = provider.currentPosition;
        final total = provider.totalDuration;
        final sliderMax = total.inSeconds > 0 ? total.inSeconds.toDouble() : 1.0;
        final sliderValue = total.inSeconds > 0
            ? position.inSeconds.toDouble().clamp(0.0, sliderMax)
            : 0.0;

        // During drag: show local drag position; otherwise show actual playback position
        final displayValue = (_dragValue ?? sliderValue).clamp(0.0, sliderMax);
        final displayPosition = _dragValue != null
            ? Duration(seconds: _dragValue!.round())
            : position;

        return Container(
          color: const Color(0xFF1C1410),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Progress slider
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: const Color(0xFFD4A853),
                  inactiveTrackColor: Colors.white24,
                  thumbColor: const Color(0xFFD4A853),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  trackHeight: 3,
                ),
                child: Slider(
                  value: displayValue,
                  min: 0,
                  max: sliderMax,
                  // During drag: only update local state — no provider calls, no async
                  onChanged: (value) {
                    setState(() => _dragValue = value);
                  },
                  // On release: single seek call
                  onChangeEnd: (value) {
                    setState(() => _dragValue = null);
                    provider.seekTo(value);
                  },
                ),
              ),
              // Time labels
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(displayPosition),
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    Text(
                      _formatDuration(total),
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Playback controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.replay_10, color: Colors.white70, size: 28),
                    onPressed: () {
                      final newSec = (position.inSeconds - 10).clamp(0, total.inSeconds).toDouble();
                      provider.seekTo(newSec);
                    },
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      provider.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 44,
                    ),
                    onPressed: provider.isPlaying ? provider.pause : provider.play,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.forward_10, color: Colors.white70, size: 28),
                    onPressed: () {
                      final newSec = (position.inSeconds + 10).clamp(0, total.inSeconds).toDouble();
                      provider.seekTo(newSec);
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
