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
        title: 'English 1999',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,

          // Reverse: 1999 inspired color scheme - warm mystical tones
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFB8956A), // Warm golden bronze
            secondary: Color(0xFFD4AF7A), // Light golden accent
            surface: Color(0xFF1C1410), // Deep warm dark brown
            onPrimary: Color(0xFF1C1410), // Dark text on primary
            onSecondary: Color(0xFF1C1410), // Dark text on secondary
            onSurface: Color(0xFFF5E6D3), // Warm cream for text
            tertiary: Color(0xFF8B6F47), // Bronze accent
            error: Color(0xFFCF6679),
          ),

          scaffoldBackgroundColor: const Color(0xFF0D0A08),

          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1C1410),
            foregroundColor: Color(0xFFF5E6D3),
            elevation: 0,
            centerTitle: true,
          ),

          cardTheme: CardThemeData(
            color: const Color(0xFF1C1410),
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(
                color: Color(0xFF2A2219),
                width: 1,
              ),
            ),
          ),

          textTheme: const TextTheme(
            headlineLarge: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Color(0xFFF5E6D3),
              letterSpacing: 0.5,
            ),
            headlineMedium: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Color(0xFFF5E6D3),
            ),
            bodyLarge: TextStyle(
              fontSize: 16,
              color: Color(0xFFF5E6D3),
              height: 1.5,
            ),
            bodyMedium: TextStyle(
              fontSize: 14,
              color: Color(0xFFC9B69A),
            ),
          ),

          iconTheme: const IconThemeData(
            color: Color(0xFFD4AF7A),
          ),

          progressIndicatorTheme: const ProgressIndicatorThemeData(
            color: Color(0xFFB8956A), // Warm golden bronze for loading indicators
            circularTrackColor: Color(0xFF2A2219),
          ),

          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB8956A),
              foregroundColor: const Color(0xFF1C1410),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),

          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF1C1410),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF8B6F47)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF8B6F47)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFB8956A), width: 2),
            ),
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
