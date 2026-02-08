class VideoLesson {
  final String id;
  final String youtubeVideoId;
  final String title;
  final String description;
  final String transcriptionPath;
  final String level;

  VideoLesson({
    required this.id,
    required this.youtubeVideoId,
    required this.title,
    required this.description,
    required this.transcriptionPath,
    required this.level,
  });

  factory VideoLesson.fromJson(Map<String, dynamic> json) {
    return VideoLesson(
      id: json['id'] as String,
      youtubeVideoId: json['youtubeVideoId'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      transcriptionPath: json['transcriptionPath'] as String,
      level: json['level'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'youtubeVideoId': youtubeVideoId,
      'title': title,
      'description': description,
      'transcriptionPath': transcriptionPath,
      'level': level,
    };
  }
}
