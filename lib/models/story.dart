class Story {
  final String id;
  final String title;
  final String tag;
  final String posterImage;
  final String youtubeVideoId;
  final String transcriptionPath;

  Story({
    required this.id,
    required this.title,
    required this.tag,
    required this.posterImage,
    required this.youtubeVideoId,
    required this.transcriptionPath,
  });

  factory Story.fromJson(Map<String, dynamic> json) {
    return Story(
      id: json['id'] as String,
      title: json['title'] as String,
      tag: json['tag'] as String,
      posterImage: json['posterImage'] as String,
      youtubeVideoId: json['youtubeVideoId'] as String,
      transcriptionPath: json['transcriptionPath'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'tag': tag,
      'posterImage': posterImage,
      'youtubeVideoId': youtubeVideoId,
      'transcriptionPath': transcriptionPath,
    };
  }
}
