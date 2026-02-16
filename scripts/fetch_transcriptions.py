#!/usr/bin/env python3
"""
Fetch YouTube video transcriptions and convert them to the app's JSON format.

Usage:
    python fetch_transcriptions.py <video_id> <output_id>

Example:
    python fetch_transcriptions.py y-m56nn4LeQ 1
"""

import sys
import json
import re
from datetime import timedelta
from youtube_transcript_api import YouTubeTranscriptApi


def seconds_to_timestamp(seconds):
    """Convert seconds to HH:MM:SS.XX format with millisecond precision."""
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = seconds % 60  # Keep as float
    return f"{hours:02d}:{minutes:02d}:{secs:05.2f}"


def clean_text(text):
    """Remove annotations like [music], [applause], etc. from text."""
    # Remove anything in square brackets
    text = re.sub(r'\[.*?\]', '', text)
    # Remove extra whitespace
    text = ' '.join(text.split())
    return text.strip()


def fetch_transcript(video_id):
    """Fetch transcript from YouTube video."""
    try:
        # Create API instance and fetch English transcript
        ytt_api = YouTubeTranscriptApi()
        transcript = ytt_api.fetch(video_id, languages=['en'])
        return transcript
    except Exception as e:
        print(f"Error fetching transcript: {e}")
        return None


def convert_to_app_format(youtube_transcript):
    """Convert YouTube transcript to app's JSON format."""
    segments = []

    for i, entry in enumerate(youtube_transcript):
        # In version 1.2.4, entry is a FetchedTranscriptSnippet object
        start_seconds = entry.start
        duration = entry.duration
        end_seconds = start_seconds + duration

        # Remove overlaps: adjust endTime if it overlaps with next segment's startTime
        if i < len(youtube_transcript) - 1:
            next_start = youtube_transcript[i + 1].start
            if end_seconds > next_start:
                end_seconds = next_start

        cleaned_text = clean_text(entry.text)

        # Skip segments that are empty after cleaning
        if not cleaned_text:
            continue

        segment = {
            "text": cleaned_text,
            "speaker": "Speaker 1",
            "translation": "",
            "startTime": seconds_to_timestamp(start_seconds),
            "endTime": seconds_to_timestamp(end_seconds)
        }
        segments.append(segment)

    return {"segments": segments}


def main():
    if len(sys.argv) != 3:
        print("Usage: python fetch_transcriptions.py <video_id> <output_id>")
        print("Example: python fetch_transcriptions.py y-m56nn4LeQ 1")
        sys.exit(1)

    video_id = sys.argv[1]
    output_id = sys.argv[2]

    print(f"Fetching transcript for video: {video_id}")

    # Fetch transcript from YouTube
    youtube_transcript = fetch_transcript(video_id)

    if not youtube_transcript:
        print("Failed to fetch transcript.")
        sys.exit(1)

    print(f"Found {len(youtube_transcript)} transcript entries")

    # Convert to app format
    app_format = convert_to_app_format(youtube_transcript)

    # Save to file
    output_path = f"../assets/data/transcriptions/{output_id}.json"
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(app_format, f, indent=2, ensure_ascii=False)

    print(f"✓ Saved transcription to {output_path}")
    print(f"✓ Total segments: {len(app_format['segments'])}")


if __name__ == "__main__":
    main()
