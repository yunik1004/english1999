import 'package:flutter/material.dart';
import '../models/transcription.dart';

class TranscriptionSegmentItem extends StatelessWidget {
  final TranscriptionSegment segment;
  final bool isActive;
  final VoidCallback onTap;

  const TranscriptionSegmentItem({
    super.key,
    required this.segment,
    required this.isActive,
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
          color: isActive ? const Color(0xFFE3F2FD) : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: Colors.grey.shade300,
              width: 0.5,
            ),
          ),
        ),
        child: Text(
          segment.text,
          style: TextStyle(
            fontSize: isActive ? 18 : 16,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? const Color(0xFF1976D2) : Colors.black87,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
