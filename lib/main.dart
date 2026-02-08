import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/video_lesson.dart';
import 'providers/video_player_provider.dart';
import 'screens/video_lesson_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => VideoPlayerProvider(),
      child: MaterialApp(
        title: 'English Learning App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          scaffoldBackgroundColor: Colors.white,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            elevation: 2,
          ),
        ),
        home: VideoLessonScreen(
          videoLesson: VideoLesson(
            id: 'sample-001',
            youtubeVideoId: 'r0x4k0yxd8s',
            title: 'Sample English Lesson',
            description: 'Sample video for testing',
            transcriptionPath: 'assets/data/transcriptions/sample_lesson.json',
            level: 'beginner',
          ),
        ),
      ),
    );
  }
}
