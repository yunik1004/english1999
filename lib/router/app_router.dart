import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/versions_screen.dart';
import '../screens/stories_screen.dart';
import '../screens/video_lesson_screen.dart';
import '../models/version.dart';
import '../models/video_lesson.dart';
import '../models/story.dart';
import '../services/version_service.dart';

// Track previous path to determine navigation direction
String? _previousPath;

// Custom page transition builder for slide animations
CustomTransitionPage buildPageWithSlideTransition({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  // Calculate route depth based on path segments
  final currentPath = state.uri.path;
  final currentDepth = currentPath.split('/').where((s) => s.isNotEmpty).length;
  final previousDepth = _previousPath?.split('/').where((s) => s.isNotEmpty).length ?? 0;

  // Determine if we're going back (to a shallower route) or forward (to a deeper route)
  final isGoingBack = currentDepth < previousDepth;

  // Update previous path for next navigation
  _previousPath = currentPath;

  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // Slide from left when going back, from right when going forward
      final begin = isGoingBack ? const Offset(-1.0, 0.0) : const Offset(1.0, 0.0);
      const end = Offset.zero;
      const curve = Curves.easeInOutCubic;

      var slideTween = Tween(begin: begin, end: end).chain(
        CurveTween(curve: curve),
      );

      return SlideTransition(
        position: animation.drive(slideTween),
        child: child,
      );
    },
  );
}

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    // Versions list screen (home)
    GoRoute(
      path: '/',
      name: 'versions',
      pageBuilder: (context, state) => buildPageWithSlideTransition(
        context: context,
        state: state,
        child: const VersionsScreen(),
      ),
    ),

    // Stories screen for a specific version
    GoRoute(
      path: '/story/:versionId',
      name: 'stories',
      pageBuilder: (context, state) {
        final versionId = state.pathParameters['versionId']!;
        final version = state.extra is Version ? state.extra as Version : null;

        final child = version != null
            ? StoriesScreen(version: version)
            : StoriesScreenLoader(versionId: versionId);

        return buildPageWithSlideTransition(
          context: context,
          state: state,
          child: child,
        );
      },
    ),

    // Video lesson screen for a specific version and story
    GoRoute(
      path: '/story/:versionId/:storyId',
      name: 'video',
      pageBuilder: (context, state) {
        final versionId = state.pathParameters['versionId']!;
        final storyId = state.pathParameters['storyId']!;

        // Check if extra is a Map containing video and story info
        VideoLesson? video;
        String? storyTitle;

        if (state.extra is Map) {
          final extraMap = state.extra as Map;
          video = extraMap['video'] as VideoLesson?;
          final story = extraMap['story'];
          storyTitle = story?.title;
        }

        final child = video != null && storyTitle != null
            ? VideoLessonScreen(
                videoLesson: video,
                chapterId: versionId,
                subchapterTitle: storyTitle,
              )
            : VideoLessonScreenLoader(
                chapterId: versionId,
                subchapterId: storyId,
              );

        return buildPageWithSlideTransition(
          context: context,
          state: state,
          child: child,
        );
      },
    ),
  ],
);

// Loading wrapper for StoriesScreen when accessed via URL
class StoriesScreenLoader extends StatelessWidget {
  final String versionId;

  const StoriesScreenLoader({
    super.key,
    required this.versionId,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Version?>(
      future: _loadVersion(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Loading...')),
            body: Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Error')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Version not found'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.go('/'),
                    child: const Text('Go Home'),
                  ),
                ],
              ),
            ),
          );
        }

        return StoriesScreen(version: snapshot.data!);
      },
    );
  }

  Future<Version?> _loadVersion() async {
    final versionService = VersionService();
    return await versionService.getVersionById(versionId);
  }
}

// Loading wrapper for VideoLessonScreen when accessed via URL
class VideoLessonScreenLoader extends StatelessWidget {
  final String chapterId;
  final String subchapterId;

  const VideoLessonScreenLoader({
    super.key,
    required this.chapterId,
    required this.subchapterId,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _loadVideoData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Loading...')),
            body: Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Error')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Video not found'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.go('/'),
                    child: const Text('Go Home'),
                  ),
                ],
              ),
            ),
          );
        }

        final data = snapshot.data!;
        return VideoLessonScreen(
          videoLesson: data['video'] as VideoLesson,
          chapterId: chapterId,
          subchapterTitle: data['storyTitle'] as String,
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _loadVideoData() async {
    final versionService = VersionService();
    final version = await versionService.getVersionById(chapterId);

    if (version == null) return null;

    final story = version.stories.firstWhere(
      (s) => s.id == subchapterId,
      orElse: () => throw Exception('Story not found'),
    );

    // Create VideoLesson directly from story data
    final video = VideoLesson(
      id: '${chapterId}-${subchapterId}',
      youtubeVideoId: story.youtubeVideoId,
      title: story.title,
      transcriptionPath: story.transcriptionPath,
    );

    return {
      'video': video,
      'storyTitle': story.title,
    };
  }
}
