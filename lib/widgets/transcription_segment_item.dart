import 'package:flutter/material.dart';
import '../models/transcription.dart';

class TranscriptionSegmentItem extends StatelessWidget {
  final TranscriptionSegment segment;
  final bool isActive;
  final bool showTranslation;
  final VoidCallback onTap;

  const TranscriptionSegmentItem({
    super.key,
    required this.segment,
    required this.isActive,
    required this.showTranslation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF2A2219) : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: const Color(0xFF2A2219),
              width: 0.5,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              segment.speaker,
              style: TextStyle(
                fontSize: isActive ? 13 : 12,
                fontWeight: FontWeight.w600,
                color: isActive ? const Color(0xFFB8956A) : const Color(0xFF8B7355),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              segment.text,
              style: TextStyle(
                fontSize: isActive ? 18 : 16,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? const Color(0xFFD4AF7A) : const Color(0xFFF5E6D3),
                height: 1.5,
              ),
            ),
            if (showTranslation && segment.translation.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                segment.translation,
                style: TextStyle(
                  fontFamily: 'NotoSerifKR',
                  fontSize: isActive ? 16 : 14,
                  fontWeight: FontWeight.normal,
                  color: isActive ? const Color(0xFFA8896A) : const Color(0xFF9B8B7A),
                  height: 1.6,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
