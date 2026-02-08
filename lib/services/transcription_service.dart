import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/transcription.dart';

class TranscriptionService {
  final Map<String, Transcription> _cache = {};

  Future<Transcription> loadTranscription(String path) async {
    if (_cache.containsKey(path)) {
      return _cache[path]!;
    }

    try {
      final jsonString = await rootBundle.loadString(path);
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;
      final transcription = Transcription.fromJson(jsonData);
      _cache[path] = transcription;
      return transcription;
    } catch (e) {
      throw Exception('Failed to load transcription from $path: $e');
    }
  }

  void clearCache() {
    _cache.clear();
  }
}
