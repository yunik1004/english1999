import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/version.dart';
import '../models/story.dart';
import '../models/video_lesson.dart';
import '../widgets/story_card.dart';

class StoriesScreen extends StatefulWidget {
  final Version version;

  const StoriesScreen({
    super.key,
    required this.version,
  });

  @override
  State<StoriesScreen> createState() => _StoriesScreenState();
}

class _StoriesScreenState extends State<StoriesScreen> {
  void _navigateToVideo(Story story) {
    // Create VideoLesson directly from story data
    final video = VideoLesson(
      id: '${widget.version.id}-${story.id}',
      youtubeVideoId: story.youtubeVideoId,
      title: story.title,
      transcriptionPath: story.transcriptionPath,
    );

    // Pass both video and story info as a map
    context.go(
      '/story/${widget.version.id}/${story.id}',
      extra: {
        'video': video,
        'story': story,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final stories = widget.version.stories;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !kIsWeb) context.go('/');
      },
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: Text(widget.version.title),
      ),
      body: stories.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.video_library_outlined,
                    size: 64,
                    color: Theme.of(context).iconTheme.color,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No lessons available',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 320, // Maximum card width
                childAspectRatio: 0.65, // Width:Height ratio (2:3 poster with padding)
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: stories.length,
              itemBuilder: (context, index) {
                return StoryCard(
                  story: stories[index],
                  onTap: () => _navigateToVideo(stories[index]),
                );
              },
            ),
      ),
    );
  }
}
