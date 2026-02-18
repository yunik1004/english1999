#!/usr/bin/env python3
"""
LLM-based alignment of dialogue JSON to Whisper word-level timestamps.

Usage:
    cd scripts
    uv run python llm_align.py \
        --dialogue temp/0.json \
        --whisper-cache temp/whisper_cache.json \
        --output ../assets/data/transcriptions/0.json \
        [--model claude-haiku-4-5-20251001] \
        [--batch-size 10] \
        [--window 400]
"""

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path

import anthropic


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

@dataclass
class Word:
    idx: int
    text: str   # normalized (lowercase, no punct)
    raw: str    # original Whisper text
    start: float
    end: float


@dataclass
class DialogueSeg:
    idx: int
    text: str
    speaker: str
    translation: str
    start: float   # placeholder input
    end: float     # placeholder input


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def fmt_time(sec: float) -> str:
    """Convert seconds to HH:MM:SS.ss string."""
    h = int(sec // 3600)
    m = int((sec % 3600) // 60)
    s = sec % 60
    return f"{h:02d}:{m:02d}:{s:05.2f}"


def load_words(cache_path: str) -> list[Word]:
    with open(cache_path, encoding="utf-8") as f:
        raw = json.load(f)
    return [
        Word(idx=i, text=w["text"], raw=w["raw"], start=w["start"], end=w["end"])
        for i, w in enumerate(raw)
    ]


def load_dialogue(dialogue_path: str) -> list[DialogueSeg]:
    with open(dialogue_path, encoding="utf-8") as f:
        data = json.load(f)
    segs = []
    for i, s in enumerate(data["segments"]):
        segs.append(DialogueSeg(
            idx=i,
            text=s["text"],
            speaker=s.get("speaker", ""),
            translation=s.get("translation", ""),
            start=float(s.get("startTime", 0)),
            end=float(s.get("endTime", 0)),
        ))
    return segs


def build_word_block(words: list[Word], window_start: int, window_end: int) -> str:
    """Format a slice of words as a numbered block for the LLM."""
    lines = []
    for w in words[window_start:window_end]:
        lines.append(f"W{w.idx:04d} [{w.start:.2f}-{w.end:.2f}]: {w.raw.strip()}")
    return "\n".join(lines)


def build_prompt(word_block: str, batch: list[DialogueSeg]) -> str:
    dialogue_lines = "\n".join(
        f"D{seg.idx:03d}: {seg.text}" for seg in batch
    )
    return f"""You are aligning English dialogue lines to a Whisper word-level transcription.

WHISPER WORDS (format: W<index> [start-end]: word):
{word_block}

DIALOGUE LINES TO MATCH (must be matched in order):
{dialogue_lines}

TASK:
For each dialogue line D###, find the span of Whisper words that best corresponds to it.
- Lines appear in chronological order — a later line's match must come after an earlier line's match.
- Whisper may have slight transcription errors or paraphrases; use best judgment.
- The word span (w_end - w_start + 1) should be close to the number of words in the dialogue line. Do NOT pick a span that is more than 3x longer than the dialogue word count.
- If you can only find the end of a line but not the beginning (or vice versa), prefer returning null over a very wide span guess.
- Return ONLY a JSON object mapping dialogue index (as string) to word index range:
  {{"DDD": {{"w_start": NNNN, "w_end": NNNN, "start": FLOAT, "end": FLOAT}}, ...}}
  where w_start/w_end are the W#### indices (plain integers, NO leading zeros) of the first and last matching words.
- If a line cannot be matched at all, use null: {{"DDD": null}}
- IMPORTANT: Use plain integers without leading zeros (e.g. 197, not 0197).
- Do not include any explanation or markdown — only the JSON object.
"""


def parse_llm_response(response_text: str) -> dict:
    """Extract JSON from LLM response, handling markdown fences and leading zeros."""
    text = response_text.strip()
    # Strip markdown code fences if present
    text = re.sub(r"^```(?:json)?\s*", "", text)
    text = re.sub(r"\s*```$", "", text)
    # Fix leading zeros in integer values (e.g. 0197 → 197) which are invalid JSON
    text = re.sub(r':\s*0+([1-9]\d*)\b', r': \1', text)
    return json.loads(text)


# ---------------------------------------------------------------------------
# Main alignment loop
# ---------------------------------------------------------------------------

def align_with_llm(
    words: list[Word],
    dialogue: list[DialogueSeg],
    client: anthropic.Anthropic,
    model: str,
    batch_size: int,
    window: int,
) -> list[dict]:
    """
    Process dialogue in batches, calling the LLM to match each segment
    to Whisper word spans.

    Returns list of output dicts (Flutter-compatible, already formatted).
    """
    results: dict[int, dict] = {}  # idx -> output segment dict
    cursor = 0  # current word index in whisper words list
    n_words = len(words)

    batches = [dialogue[i:i+batch_size] for i in range(0, len(dialogue), batch_size)]
    total_batches = len(batches)

    for batch_num, batch in enumerate(batches):
        print(f"[{batch_num+1}/{total_batches}] Processing D{batch[0].idx:03d}–D{batch[-1].idx:03d} "
              f"(cursor={cursor})", flush=True)

        # Build word window: start a bit before cursor (for context), extend forward
        win_start = max(0, cursor - 20)
        win_end = min(n_words, win_start + window)

        word_block = build_word_block(words, win_start, win_end)
        prompt = build_prompt(word_block, batch)

        try:
            message = client.messages.create(
                model=model,
                max_tokens=2048,
                messages=[{"role": "user", "content": prompt}],
            )
            raw_response = message.content[0].text
        except Exception as e:
            print(f"  ERROR calling API: {e}", file=sys.stderr)
            # Mark all in batch as unmatched
            for seg in batch:
                results[seg.idx] = _unmatched_seg(seg)
            continue

        try:
            mapping = parse_llm_response(raw_response)
        except json.JSONDecodeError as e:
            print(f"  ERROR parsing LLM response: {e}\n  Response: {raw_response[:200]}",
                  file=sys.stderr)
            for seg in batch:
                results[seg.idx] = _unmatched_seg(seg)
            # Advance cursor estimate based on word density (total_words / total_duration * batch_time)
            # Use ratio of batch start index vs total segments to estimate word position
            batch_frac = batch[-1].idx / len(dialogue)
            cursor = max(cursor, int(batch_frac * n_words))
            continue

        # Process results, advance cursor
        last_matched_w_end = cursor
        matched = 0
        for seg in batch:
            key = str(seg.idx)
            # Try both zero-padded and plain keys
            entry = mapping.get(key) or mapping.get(f"D{seg.idx:03d}") or mapping.get(f"D{seg.idx}")
            if entry is None or entry == "null":
                print(f"  D{seg.idx:03d} UNMATCHED: \"{seg.text[:40]}\"")
                results[seg.idx] = _unmatched_seg(seg)
                continue

            try:
                w_start_idx = int(entry["w_start"])
                w_end_idx = int(entry["w_end"])
                # Clamp to valid range
                w_start_idx = max(0, min(w_start_idx, n_words - 1))
                w_end_idx = max(w_start_idx, min(w_end_idx, n_words - 1))

                # Reject if span is suspiciously wide (LLM guessed a bad start/end)
                span_words = w_end_idx - w_start_idx + 1
                dialogue_words = len(seg.text.split())
                max_allowed_span = max(20, dialogue_words * 3)
                if span_words > max_allowed_span:
                    print(f"  D{seg.idx:03d} SPAN TOO WIDE ({span_words} words for {dialogue_words}-word line): \"{seg.text[:40]}\"")
                    results[seg.idx] = _unmatched_seg(seg)
                    continue

                start_sec = words[w_start_idx].start
                end_sec = words[w_end_idx].end

                results[seg.idx] = {
                    "text": seg.text,
                    "speaker": seg.speaker,
                    "translation": seg.translation,
                    "startTime": fmt_time(start_sec),
                    "endTime": fmt_time(end_sec),
                    "_matched": True,
                    "_w_start": w_start_idx,
                    "_w_end": w_end_idx,
                }
                last_matched_w_end = w_end_idx
                matched += 1
            except (KeyError, TypeError, ValueError) as e:
                print(f"  D{seg.idx:03d} parse error: {e}")
                results[seg.idx] = _unmatched_seg(seg)

        print(f"  Matched {matched}/{len(batch)}")
        # Advance cursor to just past last matched word (or keep if nothing matched)
        if last_matched_w_end > cursor:
            cursor = last_matched_w_end + 1

    # Interpolate unmatched segments
    _interpolate_unmatched(results, dialogue)

    # Return in order
    return [results[seg.idx] for seg in dialogue]


def _unmatched_seg(seg: DialogueSeg) -> dict:
    return {
        "text": seg.text,
        "speaker": seg.speaker,
        "translation": seg.translation,
        "startTime": fmt_time(seg.start),
        "endTime": fmt_time(seg.end),
        "_matched": False,
    }


def _interpolate_unmatched(results: dict, dialogue: list[DialogueSeg]):
    """
    For unmatched segments, linearly interpolate between surrounding matched anchors.
    If no surrounding anchors exist, leave the placeholder timestamps.
    """
    n = len(dialogue)

    # Find runs of unmatched
    i = 0
    while i < n:
        seg = dialogue[i]
        r = results.get(seg.idx, {})
        if r.get("_matched", False):
            i += 1
            continue

        # Start of unmatched run
        run_start = i
        while i < n and not results.get(dialogue[i].idx, {}).get("_matched", False):
            i += 1
        run_end = i  # exclusive

        # Find anchors
        prev_anchor = None
        next_anchor = None
        if run_start > 0:
            prev_anchor = results.get(dialogue[run_start - 1].idx)
        if run_end < n:
            next_anchor = results.get(dialogue[run_end].idx)

        if prev_anchor is None and next_anchor is None:
            continue  # can't interpolate

        run_len = run_end - run_start

        for j in range(run_start, run_end):
            seg_j = dialogue[j]
            pos = j - run_start  # 0-based position within the run

            if prev_anchor and next_anchor:
                t0 = _parse_fmt(prev_anchor["endTime"])
                t1 = _parse_fmt(next_anchor["startTime"])
                if t1 > t0:
                    span = (t1 - t0) / (run_len + 1)
                    start_sec = t0 + (pos + 0) * span
                    end_sec = t0 + (pos + 1) * span
                else:
                    # Anchors are in wrong order — just spread evenly after prev
                    start_sec = t0 + pos * 2.0
                    end_sec = start_sec + 2.0
            elif prev_anchor:
                t0 = _parse_fmt(prev_anchor["endTime"])
                start_sec = t0 + pos * 2.0
                end_sec = start_sec + 2.0
            else:
                t1 = _parse_fmt(next_anchor["startTime"])
                # Spread backwards from t1
                start_sec = t1 - (run_len - pos) * 2.0
                end_sec = start_sec + 2.0

            results[seg_j.idx]["startTime"] = fmt_time(max(0, start_sec))
            results[seg_j.idx]["endTime"] = fmt_time(max(0, end_sec))


def _parse_fmt(s: str) -> float:
    """Parse HH:MM:SS.ss back to float seconds."""
    parts = s.split(":")
    return int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Align dialogue to Whisper cache using LLM")
    parser.add_argument("--dialogue", required=True, help="Input dialogue JSON (e.g. temp/0.json)")
    parser.add_argument("--whisper-cache", required=True, help="Whisper word cache JSON")
    parser.add_argument("--output", required=True, help="Output transcription JSON path")
    parser.add_argument("--model", default="claude-haiku-4-5-20251001",
                        help="Claude model ID (default: claude-haiku-4-5-20251001)")
    parser.add_argument("--batch-size", type=int, default=10,
                        help="Dialogue lines per API call (default: 10)")
    parser.add_argument("--window", type=int, default=400,
                        help="Whisper words window per batch (default: 400)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print first prompt only, don't call API")
    args = parser.parse_args()

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key and not args.dry_run:
        print("ERROR: ANTHROPIC_API_KEY environment variable not set.", file=sys.stderr)
        sys.exit(1)

    print(f"Loading whisper cache: {args.whisper_cache}")
    words = load_words(args.whisper_cache)
    print(f"  {len(words)} words, duration {words[-1].end:.1f}s")

    print(f"Loading dialogue: {args.dialogue}")
    dialogue = load_dialogue(args.dialogue)
    print(f"  {len(dialogue)} segments")

    if args.dry_run:
        batch = dialogue[:args.batch_size]
        word_block = build_word_block(words, 0, min(args.window, len(words)))
        prompt = build_prompt(word_block, batch)
        print("\n--- DRY RUN: First prompt ---\n")
        print(prompt[:3000])
        print("...\n(truncated)")
        return

    client = anthropic.Anthropic(api_key=api_key)

    segments = align_with_llm(
        words=words,
        dialogue=dialogue,
        client=client,
        model=args.model,
        batch_size=args.batch_size,
        window=args.window,
    )

    # Strip internal metadata fields
    output_segs = []
    matched_count = 0
    for s in segments:
        if s.get("_matched"):
            matched_count += 1
        out = {k: v for k, v in s.items() if not k.startswith("_")}
        output_segs.append(out)

    output = {"segments": output_segs}
    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    total = len(dialogue)
    print(f"\nDone: {matched_count}/{total} matched ({100*matched_count/total:.1f}%)")
    print(f"Output written to: {out_path}")


if __name__ == "__main__":
    main()
