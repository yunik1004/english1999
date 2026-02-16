class Transcription {
  final List<TranscriptionSegment> segments;

  Transcription({required this.segments});

  factory Transcription.fromJson(Map<String, dynamic> json) {
    return Transcription(
      segments: (json['segments'] as List)
          .map((segment) => TranscriptionSegment.fromJson(segment))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'segments': segments.map((segment) => segment.toJson()).toList(),
    };
  }

  TranscriptionSegment? getCurrentSegment(Duration currentTime) {
    for (var segment in segments) {
      if (segment.isActive(currentTime)) {
        return segment;
      }
    }
    return null;
  }
}

class TranscriptionSegment {
  final String text;
  final String speaker;
  final Duration startTime;
  final Duration endTime;

  TranscriptionSegment({
    required this.text,
    required this.speaker,
    required this.startTime,
    required this.endTime,
  });

  factory TranscriptionSegment.fromJson(Map<String, dynamic> json) {
    return TranscriptionSegment(
      text: json['text'] as String,
      speaker: json['speaker'] as String? ?? 'Speaker 1',
      startTime: _parseTime(json['startTime'] as String),
      endTime: _parseTime(json['endTime'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'speaker': speaker,
      'startTime': _formatTime(startTime),
      'endTime': _formatTime(endTime),
    };
  }

  bool isActive(Duration currentTime) {
    return currentTime >= startTime && currentTime < endTime;
  }

  static Duration _parseTime(String timeString) {
    final parts = timeString.split(':');
    if (parts.length == 3) {
      final hours = int.parse(parts[0]);
      final minutes = int.parse(parts[1]);
      final secondsWithDecimal = double.parse(parts[2]);
      final seconds = secondsWithDecimal.floor();
      final milliseconds = ((secondsWithDecimal - seconds) * 1000).round();
      return Duration(
        hours: hours,
        minutes: minutes,
        seconds: seconds,
        milliseconds: milliseconds,
      );
    }
    return Duration.zero;
  }

  static String _formatTime(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}
