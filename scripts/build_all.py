#!/usr/bin/env python3
"""
build_all.py - Run the full transcription pipeline for all chapters.

Pipeline per chapter:
  1. extract_all.py  → temp/{id}.json          (scrape + Korean translation)
  2. align_whisper.py → temp/whisper_cache_{id}.json  (Whisper transcription)
  3. llm_align.py    → temp/aligned_{id}.json   (LLM timestamp alignment)

Automatically skips steps whose output already exists (resumable).
Final outputs are written to temp/aligned_{id}.json.
Copy to assets/data/transcriptions/{id}.json manually after review.

Usage:
    cd scripts
    uv run python build_all.py [--chapters 1 2 3] [--start-from 1] [--force-step extract|whisper|llm]
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).parent
TEMP_DIR = SCRIPT_DIR / "temp"
ASSETS_DIR = SCRIPT_DIR.parent / "assets" / "data" / "transcriptions"
VERSIONS_JSON = SCRIPT_DIR.parent / "assets" / "data" / "versions.json"
API_KEY_FILE = SCRIPT_DIR / "keys" / "anthropic.key"


def load_api_key() -> str:
    with open(API_KEY_FILE) as f:
        return f.read().strip()


def load_stories() -> list[dict]:
    with open(VERSIONS_JSON) as f:
        data = json.load(f)
    stories = []
    for version in data["versions"]:
        for story in version["stories"]:
            stories.append(story)
    return stories


def run(cmd: list[str], env: dict = None, label: str = "") -> bool:
    """Run a subprocess, streaming output. Returns True on success."""
    full_env = os.environ.copy()
    if env:
        full_env.update(env)
    print(f"\n{'='*60}")
    print(f"  {label}")
    print(f"  $ {' '.join(cmd)}")
    print(f"{'='*60}")
    result = subprocess.run(cmd, cwd=SCRIPT_DIR, env=full_env)
    if result.returncode != 0:
        print(f"\nERROR: command failed with exit code {result.returncode}", file=sys.stderr)
        return False
    return True


def process_chapter(story: dict, api_key: str, force_step: str | None = None) -> bool:
    story_id = story["id"]
    youtube_id = story["youtubeVideoId"]
    title = story["title"]

    print(f"\n{'#'*60}")
    print(f"  Chapter {story_id}: {title}")
    print(f"  YouTube: {youtube_id}")
    print(f"{'#'*60}")

    TEMP_DIR.mkdir(exist_ok=True)

    dialogue_json   = TEMP_DIR / f"{story_id}.json"
    whisper_cache   = TEMP_DIR / f"whisper_cache_{story_id}.json"
    aligned_output  = TEMP_DIR / f"aligned_{story_id}.json"

    # ----------------------------------------------------------------
    # Step 1: extract_all.py → dialogue JSON with Korean translations
    # ----------------------------------------------------------------
    if force_step == "extract" or not dialogue_json.exists():
        ok = run(
            ["uv", "run", "python", "extract_all.py",
             str(story_id),
             "-o", str(dialogue_json),
             "--llm-match", "claude"],
            env={"ANTHROPIC_API_KEY": api_key},
            label=f"[1/3] extract_all.py  →  {dialogue_json.name}",
        )
        if not ok:
            return False
    else:
        print(f"\n[1/3] SKIP (exists): {dialogue_json.name}")

    # ----------------------------------------------------------------
    # Step 2: align_whisper.py → Whisper cache + initial alignment
    # ----------------------------------------------------------------
    if force_step == "whisper" or not whisper_cache.exists():
        ok = run(
            ["uv", "run", "python", "align_whisper.py",
             "--dialogue", str(dialogue_json),
             "--youtube-id", youtube_id,
             "--output", str(TEMP_DIR / f"aligned_whisper_{story_id}.json"),
             "--model", "large-v3",
             "--whisper-cache", str(whisper_cache)],
            label=f"[2/3] align_whisper.py  →  {whisper_cache.name}",
        )
        if not ok:
            return False
    else:
        print(f"\n[2/3] SKIP (exists): {whisper_cache.name}")

    # ----------------------------------------------------------------
    # Step 3: llm_align.py → final LLM-based timestamp alignment
    # ----------------------------------------------------------------
    if force_step == "llm" or not aligned_output.exists():
        ok = run(
            ["uv", "run", "python", "llm_align.py",
             "--dialogue", str(dialogue_json),
             "--whisper-cache", str(whisper_cache),
             "--output", str(aligned_output),
             "--model", "claude-haiku-4-5-20251001"],
            env={"ANTHROPIC_API_KEY": api_key},
            label=f"[3/3] llm_align.py  →  {aligned_output.name}",
        )
        if not ok:
            return False
    else:
        print(f"\n[3/3] SKIP (exists): {aligned_output.name}")

    print(f"\n✓ Chapter {story_id} done  →  {aligned_output}")
    return True


def main():
    parser = argparse.ArgumentParser(description="Build all chapter transcriptions")
    parser.add_argument("--chapters", nargs="+", type=int,
                        help="Specific chapter IDs to process (default: all except 0)")
    parser.add_argument("--start-from", type=int, default=1,
                        help="Skip chapters with ID below this value (default: 1)")
    parser.add_argument("--force-step", choices=["extract", "whisper", "llm"],
                        help="Force re-run of a specific step even if output exists")
    args = parser.parse_args()

    api_key = load_api_key()
    stories = load_stories()

    # Filter chapters
    if args.chapters:
        stories = [s for s in stories if int(s["id"]) in args.chapters]
    else:
        stories = [s for s in stories if int(s["id"]) >= args.start_from]

    print(f"Processing {len(stories)} chapter(s): {[s['id'] for s in stories]}")

    failed = []
    for story in stories:
        ok = process_chapter(story, api_key, force_step=args.force_step)
        if not ok:
            failed.append(story["id"])
            print(f"\nWARNING: Chapter {story['id']} failed, continuing with next...")

    print(f"\n{'='*60}")
    print(f"DONE: {len(stories) - len(failed)}/{len(stories)} chapters succeeded")
    if failed:
        print(f"FAILED: chapters {failed}")
    print(f"\nOutputs in: {TEMP_DIR}")
    print("To deploy, copy to assets/data/transcriptions/:")
    for story in stories:
        sid = story["id"]
        if sid not in failed:
            print(f"  cp scripts/temp/aligned_{sid}.json assets/data/transcriptions/{sid}.json")


if __name__ == "__main__":
    main()
