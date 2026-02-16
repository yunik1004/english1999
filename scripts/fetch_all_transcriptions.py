#!/usr/bin/env python3
"""
Fetch all YouTube transcriptions from versions.json and save them.

Usage:
    python fetch_all_transcriptions.py
"""

import json
import os
import sys
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
        print(f"  ✗ Error: {e}")
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
    # Read versions.json
    versions_path = "../assets/data/versions.json"

    with open(versions_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    print("Fetching transcriptions for all videos...")
    print("=" * 60)

    total_videos = 0
    success_count = 0
    skip_count = 0

    # Iterate through all versions and stories
    for version in data['versions']:
        print(f"\n📖 Version: {version['title']}")

        for story in version['stories']:
            total_videos += 1
            story_id = story['id']
            video_id = story['youtubeVideoId']
            title = story['title']

            output_path = f"../assets/data/transcriptions/{story_id}.json"

            # Skip if already exists
            if os.path.exists(output_path):
                print(f"  ⊘ Story {story_id}: {title} - Already exists, skipping")
                skip_count += 1
                continue

            print(f"  ⟳ Story {story_id}: {title}")
            print(f"    Video ID: {video_id}")

            # Fetch transcript
            youtube_transcript = fetch_transcript(video_id)

            if not youtube_transcript:
                print(f"    ✗ Failed to fetch transcript")
                continue

            # Convert to app format
            app_format = convert_to_app_format(youtube_transcript)

            # Save to file
            with open(output_path, 'w', encoding='utf-8') as f:
                json.dump(app_format, f, indent=2, ensure_ascii=False)

            print(f"    ✓ Saved {len(app_format['segments'])} segments")
            success_count += 1

    print("\n" + "=" * 60)
    print(f"Summary:")
    print(f"  Total videos: {total_videos}")
    print(f"  Successfully fetched: {success_count}")
    print(f"  Skipped (already exists): {skip_count}")
    print(f"  Failed: {total_videos - success_count - skip_count}")


if __name__ == "__main__":
    main()
