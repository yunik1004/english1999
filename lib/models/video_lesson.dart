class VideoLesson {
  final String id;
  final String youtubeVideoId;
  final String title;
  final String transcriptionPath;

  VideoLesson({
    required this.id,
    required this.youtubeVideoId,
    required this.title,
    required this.transcriptionPath,
  });

  factory VideoLesson.fromJson(Map<String, dynamic> json) {
    return VideoLesson(
      id: json['id'] as String,
      youtubeVideoId: json['youtubeVideoId'] as String,
      title: json['title'] as String,
      transcriptionPath: json['transcriptionPath'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'youtubeVideoId': youtubeVideoId,
      'title': title,
      'transcriptionPath': transcriptionPath,
    };
  }
}
