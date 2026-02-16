import 'story.dart';

class Version {
  final String id;
  final String title;
  final String posterImage;
  final List<Story> stories;

  Version({
    required this.id,
    required this.title,
    required this.posterImage,
    required this.stories,
  });

  factory Version.fromJson(Map<String, dynamic> json) {
    final storiesList = json['stories'] as List;
    final stories = storiesList
        .map((storyJson) => Story.fromJson(storyJson))
        .toList();

    return Version(
      id: json['id'] as String,
      title: json['title'] as String,
      posterImage: json['posterImage'] as String,
      stories: stories,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'posterImage': posterImage,
      'stories': stories.map((s) => s.toJson()).toList(),
    };
  }
}
