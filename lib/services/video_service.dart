import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/video_lesson.dart';

class VideoService {
  List<VideoLesson>? _cachedVideos;

  Future<List<VideoLesson>> loadVideos() async {
    if (_cachedVideos != null) {
      return _cachedVideos!;
    }

    try {
      final jsonString = await rootBundle.loadString('assets/data/videos.json');
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;
      final videosList = jsonData['videos'] as List;
      _cachedVideos = videosList
          .map((videoJson) => VideoLesson.fromJson(videoJson))
          .toList();
      return _cachedVideos!;
    } catch (e) {
      throw Exception('Failed to load videos: $e');
    }
  }

  Future<List<VideoLesson>> getVideosByLevel(String level) async {
    final videos = await loadVideos();
    return videos.where((v) => v.level == level).toList();
  }

  Future<VideoLesson?> getVideoById(String id) async {
    final videos = await loadVideos();
    try {
      return videos.firstWhere((v) => v.id == id);
    } catch (e) {
      return null;
    }
  }

  void clearCache() {
    _cachedVideos = null;
  }
}
