import 'package:flutter/material.dart';
import '../models/version.dart';

class VersionCard extends StatelessWidget {
  final Version version;
  final VoidCallback onTap;

  const VersionCard({
    super.key,
    required this.version,
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
            aspectRatio: 424 / 604, // Match version image dimensions
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Poster Image
                Image.asset(
                  version.posterImage,
                  fit: BoxFit.cover,
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
                // Text Overlay
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 60,
                        alignment: Alignment.topLeft,
                        child: Text(
                          version.title,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: const Color(0xFFF5E6D3),
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                height: 1.3,
                                letterSpacing: 0.5,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
