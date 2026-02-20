import 'package:flutter/material.dart';
import '../models/story.dart';

class StoryCard extends StatelessWidget {
  final Story story;
  final VoidCallback onTap;

  const StoryCard({
    super.key,
    required this.story,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(
          color: Color(0xFF2A2219),
          width: 1,
        ),
      ),
      color: const Color(0xFF1C1410),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 371 / 636, // Average chapter image dimensions
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: 0.70, // Show only top 70% to hide title text area
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Poster Image
                    Image.asset(
                      story.posterImage,
                      fit: BoxFit.fitWidth,
                      errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: const Color(0xFF2A2219),
                      child: const Center(
                        child: Icon(
                          Icons.broken_image,
                          size: 48,
                          color: Color(0xFF8B6F47),
                        ),
                      ),
                    );
                  },
                ),
                // Dark Gradient Overlay
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                ),
                // Text Overlay - Fixed container with consistent starting point
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                          story.title,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: const Color(0xFFF5E6D3),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                height: 1.3,
                                letterSpacing: 0.3,
                              ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        story.tag,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFFD4AF7A),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);
}
}
