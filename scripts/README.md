# Transcription Fetcher Scripts

Python scripts to automatically fetch YouTube video transcriptions and convert them to the app's JSON format.

## Setup

1. Install [uv](https://docs.astral.sh/uv/) (fast Python package manager):

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

2. Install dependencies:

```bash
cd scripts
uv sync
```

## Usage

### Fetch Single Transcription

Fetch transcription for a single video:

```bash
uv run fetch_transcriptions.py <video_id> <output_id>
```

Example:

```bash
uv run fetch_transcriptions.py y-m56nn4LeQ 1
```

This will:

- Fetch the transcript from YouTube video `y-m56nn4LeQ`
- Convert it to the app's JSON format
- Save it to `assets/data/transcriptions/1.json`

### Fetch All Transcriptions

Fetch transcriptions for all videos listed in `versions.json`:

```bash
uv run fetch_all_transcriptions.py
```

This will:

- Read all video IDs from `assets/data/versions.json`
- Fetch transcripts for each video
- Skip videos that already have transcription files
- Save each transcription to `assets/data/transcriptions/<story_id>.json`

## Output Format

The scripts convert YouTube transcripts to this JSON format:

```json
{
  "segments": [
    {
      "id": 1,
      "text": "Hello everyone, and welcome to today's English lesson.",
      "startTime": "00:00:00",
      "endTime": "00:00:03"
    },
    {
      "id": 2,
      "text": "Today we're going to learn about...",
      "startTime": "00:00:03",
      "endTime": "00:00:07"
    }
  ]
}
```

## Notes

- The scripts prioritize English transcripts
- If English is not available, they will use auto-generated transcripts
- Time format: `HH:MM:SS`
- Existing transcription files are skipped by `fetch_all_transcriptions.py`
