#!/usr/bin/env python3
"""
align_whisper.py - Align dialogue JSON with YouTube audio using Whisper.

Downloads audio from a YouTube video, transcribes it with Whisper to get
word-level timestamps, then aligns each dialogue sentence to find its real
start/end time in the video.

Includes automatic gap-filling: after initial transcription, any long silence
gaps are re-transcribed with the expected dialogue text as initial_prompt so
that chanting/music sections are not silently skipped.

Usage:
    uv run python align_whisper.py \\
        --dialogue temp/0.json \\
        --youtube-id r0x4k0yxd8s \\
        --output ../assets/data/transcriptions/0.json \\
        [--model large-v3] \\
        [--language en] \\
        [--device cpu] \\
        [--whisper-cache temp/whisper_cache.json]
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from typing import List, Optional, Tuple


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

@dataclass
class Word:
    text: str          # normalized (lowercase, no punctuation)
    raw: str           # original text from Whisper
    start: float       # seconds
    end: float         # seconds


@dataclass
class AlignedSegment:
    text: str
    speaker: str
    translation: str
    start: float       # seconds
    end: float         # seconds
    matched: bool
    score: float
    word_start_idx: int = -1
    word_end_idx: int = -1


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def fmt_time(sec: float) -> str:
    """Convert float seconds to HH:MM:SS.ss string."""
    h = int(sec // 3600)
    m = int((sec % 3600) // 60)
    s = sec % 60
    return f"{h:02d}:{m:02d}:{s:05.2f}"


def normalize_word(w: str) -> str:
    """Lowercase and strip punctuation, keeping apostrophes for contractions."""
    w = w.lower()
    w = re.sub(r"[^a-z0-9']", "", w)
    w = w.strip("'")
    return w


def normalize_text(text: str) -> List[str]:
    """Split dialogue text into normalized word tokens."""
    text = re.sub(r'[\u2014\u2013\u2026\u201c\u201d\u2018\u2019""]', ' ', text)
    words = text.split()
    result = []
    for w in words:
        n = normalize_word(w)
        if n:
            result.append(n)
    return result


def word_match_score(ref: List[str], hyp: List[str]) -> float:
    """
    Compute word-level F1 between reference and hypothesis word lists.
    Uses fuzzy per-word matching (Levenshtein similarity > 0.8).
    """
    if not ref or not hyp:
        return 0.0

    from rapidfuzz.distance import Levenshtein

    used = [False] * len(hyp)
    matches = 0
    for r in ref:
        for j, h in enumerate(hyp):
            if not used[j] and Levenshtein.normalized_similarity(r, h) >= 0.8:
                matches += 1
                used[j] = True
                break

    precision = matches / len(hyp) if hyp else 0.0
    recall = matches / len(ref) if ref else 0.0
    if precision + recall == 0:
        return 0.0
    return 2 * precision * recall / (precision + recall)


# ---------------------------------------------------------------------------
# Step 1: Download audio
# ---------------------------------------------------------------------------

def download_audio(youtube_id: str, output_path: str) -> None:
    """Download best audio-only stream from YouTube as WAV."""
    url = f"https://www.youtube.com/watch?v={youtube_id}"
    cmd = [
        "yt-dlp",
        "-x",
        "--audio-format", "wav",
        "--audio-quality", "0",
        "-o", output_path,
        "--no-playlist",
        url,
    ]
    print(f"[1/3] Downloading audio from YouTube ({youtube_id})...")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"yt-dlp stderr:\n{result.stderr}", file=sys.stderr)
        raise RuntimeError(f"yt-dlp failed (exit {result.returncode})")
    print(f"      Audio saved to: {output_path}")


# ---------------------------------------------------------------------------
# Step 2: Whisper transcription + automatic gap-filling
# ---------------------------------------------------------------------------

_REPO_MAP = {
    "tiny":     "mlx-community/whisper-tiny-mlx",
    "base":     "mlx-community/whisper-base-mlx",
    "small":    "mlx-community/whisper-small-mlx",
    "medium":   "mlx-community/whisper-medium-mlx",
    "large-v2": "mlx-community/whisper-large-v2-mlx",
    "large-v3": "mlx-community/whisper-large-v3-mlx",
}


def transcribe(audio_path: str, model_size: str, language: str, device: str) -> List[Word]:
    """
    Run Whisper on the full audio file.
    - macOS: uses mlx-whisper (Apple Silicon GPU via Metal)
    - Other: uses faster-whisper (CPU / CUDA)
    Returns a flat list of Word objects with timestamps.
    """
    import platform
    on_mac = platform.system() == "Darwin"

    if on_mac:
        return _transcribe_mlx(audio_path, model_size, language, initial_prompt=None)
    else:
        return _transcribe_faster(audio_path, model_size, language, device)


def _transcribe_mlx(
    audio_path: str,
    model_size: str,
    language: str,
    initial_prompt: Optional[str] = None,
    start_offset: float = 0.0,
) -> List[Word]:
    """Transcribe using mlx-whisper (Apple Silicon Metal GPU)."""
    import mlx_whisper

    repo = _REPO_MAP.get(model_size, f"mlx-community/whisper-{model_size}-mlx")

    kwargs = dict(
        path_or_hf_repo=repo,
        word_timestamps=True,
        language=language,
        condition_on_previous_text=False,  # avoid hallucination loops on short clips
    )
    if initial_prompt:
        kwargs["initial_prompt"] = initial_prompt

    result = mlx_whisper.transcribe(audio_path, **kwargs)

    words: List[Word] = []
    for seg in result.get("segments", []):
        for w in seg.get("words", []):
            raw = w.get("word", "")
            norm = normalize_word(raw)
            if not norm:
                continue
            words.append(Word(
                text=norm,
                raw=raw,
                start=round(w["start"] + start_offset, 3),
                end=round(w["end"] + start_offset, 3),
            ))

    return words


def _transcribe_faster(audio_path: str, model_size: str, language: str, device: str) -> List[Word]:
    """Transcribe using faster-whisper (CPU / CUDA)."""
    from faster_whisper import WhisperModel

    print(f"[2/3] Transcribing with faster-whisper ({model_size}) on {device}...")
    model = WhisperModel(model_size, device=device, compute_type="int8")
    segments, _ = model.transcribe(
        audio_path,
        language=language,
        word_timestamps=True,
        vad_filter=True,
        vad_parameters={"min_silence_duration_ms": 500},
    )

    words: List[Word] = []
    for seg in segments:
        if seg.words is None:
            continue
        for w in seg.words:
            norm = normalize_word(w.word)
            if not norm:
                continue
            words.append(Word(text=norm, raw=w.word, start=w.start, end=w.end))

    print(f"      Got {len(words)} words from Whisper")
    return words


def _extract_audio_segment(input_path: str, output_path: str, start_sec: float, end_sec: float) -> None:
    """Extract a time range from an audio file using ffmpeg."""
    cmd = [
        "ffmpeg",
        "-y",               # overwrite output
        "-i", input_path,
        "-ss", str(start_sec),
        "-to", str(end_sec),
        "-acodec", "pcm_s16le",
        "-ar", "16000",     # Whisper expects 16kHz
        output_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg failed: {result.stderr[-300:]}")


def _quick_greedy_align(words: List[Word], dialogue: List[dict]) -> List[AlignedSegment]:
    """
    Fast pass-1-only alignment (no fill, no interpolation).
    Used internally to detect which dialogue segments are unmatched.
    """
    SEARCH_WINDOW = 3000
    MATCH_THRESHOLD = 0.35

    results: List[AlignedSegment] = []
    cursor = 0

    for seg in dialogue:
        ref_words = normalize_text(seg["text"])
        n = len(ref_words)

        if n == 0:
            results.append(AlignedSegment(
                text=seg["text"], speaker=seg.get("speaker", ""),
                translation=seg.get("translation", ""),
                start=0.0, end=0.0,
                matched=False, score=0.0,
            ))
            continue

        search_end = min(cursor + SEARCH_WINDOW, len(words))
        best_score = 0.0
        best_start = cursor
        for j in range(cursor, max(cursor + 1, search_end - n + 1)):
            if j + n > len(words):
                break
            hyp = [words[j + k].text for k in range(n)]
            score = word_match_score(ref_words, hyp)
            if score > best_score:
                best_score = score
                best_start = j

        matched = best_score >= MATCH_THRESHOLD
        if matched:
            best_end = best_start + n - 1
            results.append(AlignedSegment(
                text=seg["text"], speaker=seg.get("speaker", ""),
                translation=seg.get("translation", ""),
                start=words[best_start].start,
                end=words[best_end].end,
                matched=True, score=best_score,
                word_start_idx=best_start, word_end_idx=best_end,
            ))
            cursor = best_end + 1
        else:
            results.append(AlignedSegment(
                text=seg["text"], speaker=seg.get("speaker", ""),
                translation=seg.get("translation", ""),
                start=0.0, end=0.0,
                matched=False, score=best_score,
            ))

    return results


def auto_fill_gaps(
    audio_path: str,
    words: List[Word],
    dialogue: List[dict],
    model_size: str,
    language: str = "en",
    gap_threshold: float = 6.0,
) -> List[Word]:
    """
    After initial transcription, find long silence gaps that contain unmatched
    dialogue lines. For each gap, extract that audio section and re-transcribe
    it with an initial_prompt of the expected dialogue text so that Whisper
    focuses on finding those words.

    Returns an improved word list with the gap-filled words inserted.
    """
    import platform
    on_mac = platform.system() == "Darwin"

    print(f"\n[2b/3] Auto-filling gaps (threshold={gap_threshold:.0f}s)...")

    # Step 1: Quick alignment to find unmatched clusters and their time bounds
    prelim = _quick_greedy_align(words, dialogue)
    n = len(dialogue)

    # Step 2: Find runs of unmatched segments and their surrounding time bounds
    gaps_to_fill: List[Tuple[float, float, List[str]]] = []  # (t_start, t_end, texts)

    i = 0
    while i < n:
        if prelim[i].matched:
            i += 1
            continue

        run_start = i
        while i < n and not prelim[i].matched:
            i += 1
        run_end = i  # exclusive

        # Find bounding matched anchors
        t_before: Optional[float] = None
        t_after: Optional[float] = None

        for j in range(run_start - 1, -1, -1):
            if prelim[j].matched:
                t_before = prelim[j].end
                break
        for j in range(run_end, n):
            if prelim[j].matched:
                t_after = prelim[j].start
                break

        if t_before is None or t_after is None:
            continue

        # Check if there is a genuine Whisper silence in this time range
        gap_duration = t_after - t_before
        if gap_duration < gap_threshold:
            continue  # Not a real gap, Whisper just scored low

        # Count how many Whisper words fall in the gap window
        words_in_gap = sum(1 for w in words if w.start >= t_before and w.end <= t_after)
        if words_in_gap > 5:
            continue  # Whisper already has content here, alignment issue not transcription

        texts = [dialogue[j]["text"] for j in range(run_start, run_end)]
        print(f"  Gap found: {t_before:.1f}s–{t_after:.1f}s ({gap_duration:.1f}s), "
              f"{run_end - run_start} unmatched lines")
        gaps_to_fill.append((t_before, t_after, texts))

    if not gaps_to_fill:
        print("  No gaps to fill.")
        return words

    # Step 3: Re-transcribe each gap section
    improved = list(words)  # copy

    for gap_start, gap_end, texts in gaps_to_fill:
        prompt = " ".join(texts)
        # Add a small buffer around the gap
        seg_start = max(0.0, gap_start - 1.0)
        seg_end = gap_end + 1.0

        print(f"\n  Re-transcribing {seg_start:.1f}s–{seg_end:.1f}s "
              f"({seg_end - seg_start:.0f}s clip)...")
        print(f"  initial_prompt: \"{prompt[:100]}\"")

        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
            tmp_path = tmp.name

        try:
            _extract_audio_segment(audio_path, tmp_path, seg_start, seg_end)

            if on_mac:
                patch_words = _transcribe_mlx(
                    tmp_path,
                    model_size=model_size,
                    language=language,
                    initial_prompt=prompt,
                    start_offset=seg_start,
                )
            else:
                # For non-Mac: use faster-whisper with initial_prompt
                patch_words = _transcribe_faster_with_prompt(
                    tmp_path, model_size, language, "cpu", prompt, seg_start
                )

        finally:
            os.unlink(tmp_path)

        if not patch_words:
            print(f"  WARNING: no words found in gap, skipping.")
            continue

        # Filter to only words within the gap (±1s buffer)
        patch_words = [w for w in patch_words
                       if w.start >= gap_start - 1.0 and w.end <= gap_end + 1.0]

        if not patch_words:
            print(f"  WARNING: patch words all outside gap range, skipping.")
            continue

        print(f"  Found {len(patch_words)} words:")
        for w in patch_words:
            print(f"    [{w.start:.2f}-{w.end:.2f}] {w.raw.strip()}")

        # Remove existing words in gap range (usually zero), insert patch words
        improved = [w for w in improved
                    if not (w.start >= gap_start and w.end <= gap_end)]

        # Find insertion position (after last word before gap_start)
        insert_pos = 0
        for k, w in enumerate(improved):
            if w.end <= gap_start:
                insert_pos = k + 1

        for k, pw in enumerate(patch_words):
            improved.insert(insert_pos + k, pw)

    print(f"\n  Word count: {len(words)} → {len(improved)} after gap-fill")
    return improved


def _transcribe_faster_with_prompt(
    audio_path: str, model_size: str, language: str, device: str,
    initial_prompt: str, start_offset: float
) -> List[Word]:
    """faster-whisper transcription of a short segment with initial_prompt."""
    from faster_whisper import WhisperModel

    model = WhisperModel(model_size, device=device, compute_type="int8")
    segments, _ = model.transcribe(
        audio_path,
        language=language,
        word_timestamps=True,
        vad_filter=False,   # don't skip anything in short clips
        initial_prompt=initial_prompt,
    )

    words: List[Word] = []
    for seg in segments:
        if seg.words is None:
            continue
        for w in seg.words:
            norm = normalize_word(w.word)
            if not norm:
                continue
            words.append(Word(
                text=norm, raw=w.word,
                start=round(w.start + start_offset, 3),
                end=round(w.end + start_offset, 3),
            ))
    return words


# ---------------------------------------------------------------------------
# Step 3: Greedy sequential alignment
# ---------------------------------------------------------------------------

SEARCH_WINDOW = 3000
MATCH_THRESHOLD = 0.35


def _best_match_in_range(
    ref_words: List[str],
    words: List[Word],
    start: int,
    end: int,
) -> Tuple[float, int]:
    n = len(ref_words)
    best_score = 0.0
    best_start = start

    for j in range(start, max(start + 1, end - n + 1)):
        if j + n > len(words):
            break
        hyp = [words[j + k].text for k in range(n)]
        score = word_match_score(ref_words, hyp)
        if score > best_score:
            best_score = score
            best_start = j

    return best_score, best_start


def align(
    dialogue: List[dict],
    words: List[Word],
) -> List[AlignedSegment]:
    """
    Two-pass alignment of dialogue segments to Whisper words.
    Pass 1: greedy cursor scan.
    Pass 2: fill unmatched in bounded regions.
    Pass 3: linearly interpolate remaining unmatched.
    """
    print(f"[3/3] Aligning {len(dialogue)} segments to {len(words)} Whisper words...")

    results: List[AlignedSegment] = []
    cursor = 0

    # ---- Pass 1: greedy cursor ----
    for seg in dialogue:
        ref_words = normalize_text(seg["text"])
        n = len(ref_words)

        if n == 0:
            results.append(AlignedSegment(
                text=seg["text"], speaker=seg.get("speaker", ""),
                translation=seg.get("translation", ""),
                start=float(seg.get("startTime", 0.0)),
                end=float(seg.get("endTime", 0.0)),
                matched=False, score=0.0,
            ))
            continue

        search_end = min(cursor + SEARCH_WINDOW, len(words))
        best_score, best_start = _best_match_in_range(ref_words, words, cursor, search_end)
        matched = best_score >= MATCH_THRESHOLD

        if matched:
            best_end = best_start + n - 1
            results.append(AlignedSegment(
                text=seg["text"], speaker=seg.get("speaker", ""),
                translation=seg.get("translation", ""),
                start=words[best_start].start,
                end=words[best_end].end,
                matched=True, score=best_score,
                word_start_idx=best_start, word_end_idx=best_end,
            ))
            cursor = best_end + 1
        else:
            results.append(AlignedSegment(
                text=seg["text"], speaker=seg.get("speaker", ""),
                translation=seg.get("translation", ""),
                start=float(seg.get("startTime", 0.0)),
                end=float(seg.get("endTime", 0.0)),
                matched=False, score=best_score,
            ))

    # ---- Pass 2: fill unmatched in bounded regions ----
    n_segs = len(results)
    for i in range(n_segs):
        if results[i].matched or not normalize_text(results[i].text):
            continue

        prev_word_end = 0
        for j in range(i - 1, -1, -1):
            if results[j].matched:
                prev_word_end = results[j].word_end_idx + 1
                break

        next_word_start = len(words)
        for j in range(i + 1, n_segs):
            if results[j].matched:
                next_word_start = results[j].word_start_idx
                break

        if prev_word_end >= next_word_start:
            continue

        ref_words = normalize_text(results[i].text)
        n = len(ref_words)
        best_score, best_start = _best_match_in_range(
            ref_words, words, prev_word_end, next_word_start
        )

        if best_score >= MATCH_THRESHOLD and best_start + n <= len(words):
            best_end = best_start + n - 1
            results[i].start = words[best_start].start
            results[i].end = words[best_end].end
            results[i].matched = True
            results[i].score = best_score
            results[i].word_start_idx = best_start
            results[i].word_end_idx = best_end

    # ---- Pass 3: interpolate truly unmatched ----
    _interpolate_unmatched(results)

    matched_count = sum(1 for r in results if r.matched)
    unmatched = n_segs - matched_count
    print(f"      Matched: {matched_count}/{n_segs} segments "
          f"({100*matched_count/n_segs:.1f}%)")
    if unmatched > 0:
        print(f"      {unmatched} segment(s) interpolated from neighbors.")

    return results


def _interpolate_unmatched(results: List[AlignedSegment]) -> None:
    n = len(results)
    i = 0
    while i < n:
        if results[i].matched:
            i += 1
            continue

        run_start = i
        while i < n and not results[i].matched:
            i += 1
        run_end = i

        t_before = results[run_start - 1].end if run_start > 0 else 0.0
        t_after = results[run_end].start if run_end < n else (
            results[run_end - 1].end + 2.0 * (run_end - run_start)
        )

        gap = t_after - t_before
        seg_dur = gap / (run_end - run_start)

        for k, idx in enumerate(range(run_start, run_end)):
            results[idx].start = t_before + k * seg_dur
            results[idx].end = t_before + (k + 1) * seg_dur


# ---------------------------------------------------------------------------
# Step 4: Post-processing & output
# ---------------------------------------------------------------------------

def fix_overlaps(segments: List[AlignedSegment]) -> None:
    for i in range(len(segments) - 1):
        if segments[i].matched and segments[i + 1].matched:
            if segments[i].end > segments[i + 1].start:
                segments[i].end = max(segments[i].start, segments[i + 1].start - 0.05)


def build_output(segments: List[AlignedSegment]) -> dict:
    out_segs = []
    for s in segments:
        out_segs.append({
            "text": s.text,
            "speaker": s.speaker,
            "translation": s.translation,
            "startTime": fmt_time(s.start),
            "endTime": fmt_time(s.end),
        })
    return {"segments": out_segs}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Align dialogue JSON with YouTube audio using Whisper"
    )
    parser.add_argument("--dialogue", required=True,
                        help="Path to input dialogue JSON (e.g. temp/0.json)")
    parser.add_argument("--youtube-id", required=True,
                        help="YouTube video ID (e.g. r0x4k0yxd8s)")
    parser.add_argument("--output", required=True,
                        help="Path for output transcription JSON")
    parser.add_argument("--model", default="large-v3",
                        choices=["tiny", "base", "small", "medium", "large-v2", "large-v3"])
    parser.add_argument("--language", default="en")
    parser.add_argument("--device", default="cpu",
                        choices=["cpu", "cuda", "auto"])
    parser.add_argument("--keep-audio", action="store_true")
    parser.add_argument("--whisper-cache", metavar="FILE",
                        help="Save/load Whisper words JSON to skip re-transcription")
    parser.add_argument("--no-gap-fill", action="store_true",
                        help="Disable automatic gap-filling (faster, less accurate)")
    parser.add_argument("--gap-threshold", type=float, default=6.0,
                        help="Min silence gap in seconds to trigger re-transcription (default: 6)")
    args = parser.parse_args()

    # Load dialogue JSON
    with open(args.dialogue, encoding="utf-8") as f:
        dialogue_data = json.load(f)
    segments = dialogue_data["segments"]
    print(f"Loaded {len(segments)} dialogue segments from {args.dialogue}")

    # ----------------------------------------------------------------
    # Cache path: load existing words (no gap-fill, no audio needed)
    # ----------------------------------------------------------------
    if args.whisper_cache and os.path.exists(args.whisper_cache):
        print(f"[1-2/3] Loading Whisper words from cache: {args.whisper_cache}")
        with open(args.whisper_cache, encoding="utf-8") as f:
            raw = json.load(f)
        words = [Word(text=w["text"], raw=w["raw"], start=w["start"], end=w["end"])
                 for w in raw]
        print(f"        Loaded {len(words)} cached words")

        aligned = align(segments, words)
        fix_overlaps(aligned)
        output = build_output(aligned)
        os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
        with open(args.output, "w", encoding="utf-8") as f:
            json.dump(output, f, ensure_ascii=False, indent=2)
        print(f"\nOutput written to: {args.output}")
        print("\nSample (first 5 segments):")
        for s in output["segments"][:5]:
            print(f"  [{s['startTime']} → {s['endTime']}] {s['text'][:60]}")
        return

    # ----------------------------------------------------------------
    # No cache: download + transcribe + gap-fill + align
    # ----------------------------------------------------------------
    tmp_dir = tempfile.mkdtemp(prefix="align_whisper_")
    audio_path = os.path.join(tmp_dir, f"{args.youtube_id}.wav")

    try:
        # Step 1: Download
        download_audio(args.youtube_id, audio_path)

        # Step 2a: Full transcription
        print(f"[2/3] Transcribing with mlx-whisper ({args.model}) on Apple Silicon GPU...")
        import platform
        if platform.system() == "Darwin":
            repo = _REPO_MAP.get(args.model, f"mlx-community/whisper-{args.model}-mlx")
            print(f"      Model: {repo}")
            words = _transcribe_mlx(audio_path, args.model, args.language)
        else:
            words = _transcribe_faster(audio_path, args.model, args.language, args.device)

        if not words:
            print("ERROR: Whisper returned no words.", file=sys.stderr)
            sys.exit(1)
        print(f"      Got {len(words)} words from Whisper")

        # Step 2b: Auto gap-fill (using the audio still on disk)
        if not args.no_gap_fill:
            words = auto_fill_gaps(
                audio_path, words, segments,
                model_size=args.model,
                language=args.language,
                gap_threshold=args.gap_threshold,
            )

        # Save improved cache if requested
        if args.whisper_cache:
            cache_path = args.whisper_cache
            os.makedirs(os.path.dirname(os.path.abspath(cache_path)), exist_ok=True)
            with open(cache_path, "w", encoding="utf-8") as f:
                json.dump([{"text": w.text, "raw": w.raw, "start": w.start, "end": w.end}
                           for w in words], f, ensure_ascii=False, indent=2)
            print(f"      Whisper words (with gap-fill) cached to: {cache_path}")

        # Step 3: Align
        aligned = align(segments, words)

        # Step 4: Post-process & write
        fix_overlaps(aligned)
        output = build_output(aligned)

        os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
        with open(args.output, "w", encoding="utf-8") as f:
            json.dump(output, f, ensure_ascii=False, indent=2)
        print(f"\nOutput written to: {args.output}")

        print("\nSample (first 5 segments):")
        for s in output["segments"][:5]:
            print(f"  [{s['startTime']} → {s['endTime']}] {s['text'][:60]}")

    finally:
        if not args.keep_audio:
            import shutil
            shutil.rmtree(tmp_dir, ignore_errors=True)
        else:
            print(f"Audio kept at: {audio_path}")


if __name__ == "__main__":
    main()
