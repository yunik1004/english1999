#!/usr/bin/env python3
"""
Complete transcript extraction and translation script.
Fetches from web, extracts embedded JSON, parses narration + dialogue, translates to Korean using LLM.

Usage:
    uv pip install requests beautifulsoup4 lxml

    # LLM translation with Claude (API key can be stored in keys/anthropic.key)
    uv pip install anthropic
    python extract_all.py <chapter_number> -o <output.json> --llm-match claude

    # LLM translation with GPT (API key can be stored in keys/openai.key)
    uv pip install openai
    python extract_all.py <chapter_number> -o <output.json> --llm-match gpt

API Key Priority:
    1. --api-key argument (highest priority)
    2. keys/anthropic.key or keys/openai.key file
    3. ANTHROPIC_API_KEY or OPENAI_API_KEY environment variable

Examples:
    python extract_all.py 0 -o assets/data/transcriptions/0.json --llm-match claude
    python extract_all.py 0 -o assets/data/transcriptions/0.json --llm-match gpt
"""

import argparse
import json
import re
import os
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import List, Tuple, Optional

try:
    import requests
    from bs4 import BeautifulSoup
except ImportError:
    print("Error: Required libraries not found")
    print("Run: uv pip install requests beautifulsoup4 lxml")
    exit(1)

try:
    import anthropic
except ImportError:
    anthropic = None  # Optional dependency for LLM matching

try:
    import openai
except ImportError:
    openai = None  # Optional dependency for LLM matching


class KoreanExample:
    """Rich Korean example with surrounding context for better matching"""
    def __init__(
        self,
        speaker: str,
        text: str,
        chapter_idx: int,
        position: int,
        context_before: List[Tuple[str, str]],
        context_after: List[Tuple[str, str]],
        full_chapter: List[Tuple[str, str]]
    ):
        self.speaker = speaker
        self.text = text
        self.chapter_idx = chapter_idx
        self.position = position
        self.is_narration = (speaker == "")
        self.context_before = context_before  # [(speaker, text), ...]
        self.context_after = context_after    # [(speaker, text), ...]
        self.full_chapter = full_chapter      # Entire chapter for full context


def fetch_html(chapter: int, lang: str) -> str:
    """Fetch HTML from uttu.merui.net"""
    url = f"https://uttu.merui.net/story/{lang}/main/chapter-{chapter}/transcript"
    headers = {'User-Agent': 'Mozilla/5.0'}

    try:
        response = requests.get(url, headers=headers, params={'part': 3}, timeout=30)
        response.raise_for_status()
        return response.text
    except Exception as e:
        print(f"Error fetching {lang}: {e}")
        return ""


def extract_json_from_html(html: str) -> dict:
    """Extract embedded JSON data from HTML script tags"""
    soup = BeautifulSoup(html, 'lxml')

    # Find all script tags
    script_tags = soup.find_all('script')

    for script in script_tags:
        script_text = script.string
        if script_text and 'chapters' in script_text:
            # Check if it's pure JSON (starts with { or [)
            script_text = script_text.strip()
            if script_text.startswith('{'):
                try:
                    data = json.loads(script_text)
                    if 'chapters' in data:
                        return data
                except json.JSONDecodeError:
                    continue

    return {}


def parse_chapter_content(html_content: str, skip_first_if_matches: str = None) -> List[Tuple[str, str]]:
    """Parse HTML content to extract narration and dialogue

    Args:
        html_content: The HTML content to parse
        skip_first_if_matches: If provided, skip the first item if it matches this text
    """
    soup = BeautifulSoup(html_content, 'lxml')
    content = []
    seen = set()

    # Process all <i> and <b> tags in order
    for elem in soup.find_all(['i', 'b']):
        text = elem.get_text(strip=True)

        if not text or len(text) < 2:
            continue

        if elem.name == 'i':
            # Narration (no speaker)
            # Skip duplicate narration
            if text in seen:
                continue
            seen.add(text)
            content.append(("", text))

        elif elem.name == 'b':
            # Check if it's dialogue with "Name:" format
            if ':' in text:
                match = re.match(r'^([^:]+):\s*(.*)$', text)
                if match:
                    speaker = match.group(1).strip()
                    dialogue = match.group(2).strip()

                    if dialogue:
                        # Dialogue is inside the <b> tag
                        if dialogue not in seen:
                            seen.add(dialogue)
                            content.append((speaker, dialogue))
                    else:
                        # Dialogue is in sibling text node after the <b> tag
                        for sibling in elem.next_siblings:
                            # Check if it's a tag (has name attribute that is not None)
                            if hasattr(sibling, 'name') and sibling.name is not None:
                                # Stop at the next tag (like <br>, <b>, etc.)
                                break
                            elif isinstance(sibling, str):
                                # It's a text node (NavigableString)
                                dialogue_text = sibling.strip()
                                if dialogue_text and dialogue_text not in seen:
                                    seen.add(dialogue_text)
                                    content.append((speaker, dialogue_text))
                                    break  # Got the dialogue, stop here

    return content


def extract_content_by_chapter(data: dict, lang: str = 'en') -> List[List[Tuple[str, str]]]:
    """Extract content from each chapter separately, returning a list of chapter contents

    Args:
        data: The JSON data containing chapters
        lang: Language code ('en' or 'kr') for language-specific filtering
    """
    chapters_content = []

    if 'chapters' not in data:
        return chapters_content

    for i, chapter in enumerate(data['chapters']):
        if 'content' in chapter:
            chapter_content = parse_chapter_content(chapter['content'])

            # Skip specific items from first chapter
            if i == 0 and chapter_content:
                if lang == 'en':
                    # Skip Francis Scott Fitzgerald quote
                    if chapter_content[0][1] == "— FRANCIS SCOTT KEY FITZGERALD":
                        chapter_content = chapter_content[1:]
                elif lang == 'kr':
                    # Skip first Regulus dialogue "뭐야? 무슨 일이야?"
                    if chapter_content[0][0] == "레굴루스" and "뭐야" in chapter_content[0][1]:
                        chapter_content = chapter_content[1:]

            chapters_content.append(chapter_content)
        else:
            chapters_content.append([])

    return chapters_content


def build_korean_examples_with_context(kr_chapters: List[List[Tuple[str, str]]]) -> List[KoreanExample]:
    """
    Convert Korean chapters into rich KoreanExample objects with surrounding context.

    Args:
        kr_chapters: Korean content organized by chapter

    Returns:
        List of KoreanExample objects with contextual information
    """
    kr_examples = []

    for chapter_idx, chapter in enumerate(kr_chapters):
        for position, (speaker, text) in enumerate(chapter):
            # Extract context before (up to 2 items)
            context_before = []
            for i in range(max(0, position - 2), position):
                context_before.append(chapter[i])

            # Extract context after (up to 2 items)
            context_after = []
            for i in range(position + 1, min(len(chapter), position + 3)):
                context_after.append(chapter[i])

            # Create KoreanExample object with full chapter context
            example = KoreanExample(
                speaker=speaker,
                text=text,
                chapter_idx=chapter_idx,
                position=position,
                context_before=context_before,
                context_after=context_after,
                full_chapter=chapter  # Include entire chapter
            )
            kr_examples.append(example)

    return kr_examples


def pre_filter_candidates(
    en_speaker: str,
    en_text: str,
    kr_examples: List[KoreanExample],
    max_candidates: int = 20
) -> List[KoreanExample]:
    """
    Fast pre-filtering before LLM matching to reduce API cost.

    Filters:
    1. Same type (narration vs dialogue)
    2. If dialogue, same speaker name
    3. Length similarity (within 50% of English length)
    4. Remove duplicates

    Args:
        en_speaker: English speaker name ("" for narration)
        en_text: English text
        kr_examples: All Korean examples
        max_candidates: Maximum candidates to return

    Returns:
        Filtered list of top candidates sorted by length similarity
    """
    is_narration = (en_speaker == "")
    en_length = len(en_text)

    # Filter candidates
    candidates = []
    seen_texts = set()

    for ex in kr_examples:
        # Skip if already seen this text
        if ex.text in seen_texts:
            continue

        # Filter 1: Same type (narration vs dialogue)
        if ex.is_narration != is_narration:
            continue

        # Filter 2: Same speaker if dialogue
        if not is_narration and ex.speaker != en_speaker:
            continue

        # Filter 3: Length similarity (within 50%)
        kr_length = len(ex.text)
        length_ratio = kr_length / en_length if en_length > 0 else 1.0
        if length_ratio < 0.5 or length_ratio > 1.5:
            continue

        seen_texts.add(ex.text)
        candidates.append(ex)

    # Sort by length similarity (closest first)
    candidates.sort(key=lambda ex: abs(len(ex.text) - en_length))

    # Return top N candidates
    return candidates[:max_candidates]


def parse_match_response(response_text: str) -> Tuple[int, float, str]:
    """
    Parse LLM matching response into structured data.

    Expected format:
        BEST_MATCH: [number]
        CONFIDENCE: [0.0-1.0]
        REASON: [explanation]

    Args:
        response_text: LLM response text

    Returns:
        (match_index, confidence, reason) tuple
        If parsing fails, returns (-1, 0.0, "Parse error")
    """
    try:
        lines = response_text.strip().split('\n')

        match_index = -1
        confidence = 0.0
        reason = "Parse error"

        for line in lines:
            line = line.strip()
            if line.startswith('BEST_MATCH:'):
                match_str = line.split(':', 1)[1].strip()
                # Extract first number
                numbers = re.findall(r'\d+', match_str)
                if numbers:
                    match_index = int(numbers[0])

            elif line.startswith('CONFIDENCE:'):
                conf_str = line.split(':', 1)[1].strip()
                # Extract float
                try:
                    confidence = float(conf_str)
                    confidence = max(0.0, min(1.0, confidence))  # Clamp to [0, 1]
                except ValueError:
                    confidence = 0.0

            elif line.startswith('REASON:'):
                reason = line.split(':', 1)[1].strip()

        return (match_index, confidence, reason)

    except Exception as e:
        print(f"Error parsing match response: {e}")
        return (-1, 0.0, f"Parse error: {str(e)}")


def find_matching_korean(
    en_speaker: str,
    en_text: str,
    kr_examples: List[KoreanExample],
    client,
    provider: str,
    cache: Optional[dict] = None,
    cache_lock: Optional[threading.Lock] = None
) -> Tuple[KoreanExample, float, str]:
    """
    Find the best matching Korean example using LLM semantic matching.

    Args:
        en_speaker: English speaker name ("" for narration)
        en_text: English text to match
        kr_examples: All Korean examples
        client: API client (Anthropic or OpenAI)
        provider: "claude" or "gpt"
        cache: Optional cache dict to avoid re-matching
        cache_lock: Optional lock for thread-safe cache access

    Returns:
        (matched_example, confidence, reason) tuple
    """
    # Check cache first (thread-safe)
    cache_key = (en_speaker, en_text)
    if cache is not None:
        if cache_lock:
            with cache_lock:
                if cache_key in cache:
                    return cache[cache_key]
        elif cache_key in cache:
            return cache[cache_key]

    # Pre-filter candidates
    candidates = pre_filter_candidates(en_speaker, en_text, kr_examples, max_candidates=20)

    if not candidates:
        # Fallback: return first example of same type
        is_narration = (en_speaker == "")
        for ex in kr_examples:
            if ex.is_narration == is_narration:
                return (ex, 0.1, "No candidates found, using fallback")
        # If still nothing, return first example
        return (kr_examples[0], 0.05, "No matching type, using first example")

    # Build matching prompt
    speaker_label = en_speaker if en_speaker else "Narration"

    candidates_text = ""
    for i, candidate in enumerate(candidates, 1):
        cand_speaker = candidate.speaker if candidate.speaker else "[Narration]"
        candidates_text += f"\n[{i}] Type: {cand_speaker}\n"
        candidates_text += f"    Text: \"{candidate.text}\"\n"

        # Show context
        if candidate.context_before:
            ctx_before = " | ".join([f"{s or '[Narr]'}: {t[:30]}..." for s, t in candidate.context_before[-2:]])
            candidates_text += f"    Before: {ctx_before}\n"
        if candidate.context_after:
            ctx_after = " | ".join([f"{s or '[Narr]'}: {t[:30]}..." for s, t in candidate.context_after[:2]])
            candidates_text += f"    After: {ctx_after}\n"

    prompt = f"""You are matching English and Korean game dialogue/narration.
Find which Korean text best matches the English text semantically.

English text to match:
Type: {speaker_label}
Text: "{en_text}"

Korean candidates (choose the most semantically similar):
{candidates_text}

SELECTION CRITERIA:
1. Meaning/content similarity (most important)
2. Same speaker character (if dialogue)
3. Similar tone and style
4. Similar context (situation in story)
5. Similar sentence structure or length

Respond in this EXACT format:
BEST_MATCH: [number]
CONFIDENCE: [0.0-1.0]
REASON: [1-2 sentences explaining why]"""

    try:
        if provider == "claude":
            message = client.messages.create(
                model="claude-sonnet-4-20250514",
                max_tokens=300,
                temperature=0.3,
                messages=[{"role": "user", "content": prompt}]
            )
            response_text = message.content[0].text.strip()
        else:  # gpt
            message = client.chat.completions.create(
                model="gpt-4o",
                max_tokens=300,
                temperature=0.3,
                messages=[{"role": "user", "content": prompt}]
            )
            response_text = message.choices[0].message.content.strip()

        # Parse response
        match_index, confidence, reason = parse_match_response(response_text)

        # Validate match_index
        if match_index < 1 or match_index > len(candidates):
            match_index = 1  # Default to first candidate

        matched_example = candidates[match_index - 1]  # Convert to 0-indexed

        # Cache result (thread-safe)
        if cache is not None:
            if cache_lock:
                with cache_lock:
                    cache[cache_key] = (matched_example, confidence, reason)
            else:
                cache[cache_key] = (matched_example, confidence, reason)

        return (matched_example, confidence, reason)

    except Exception as e:
        print(f"\nError during matching: {e}")
        # Fallback to first candidate
        return (candidates[0], 0.2, f"API error: {str(e)}")


def translate_with_llm(
    en_speaker: str,
    en_text: str,
    matched_kr: KoreanExample,
    additional_examples: List[KoreanExample],
    client,
    provider: str = "claude"
) -> str:
    """
    Translate English text to Korean using matched example as primary style guide.

    Args:
        en_speaker: English speaker name (or "" for narration)
        en_text: English text to translate
        matched_kr: The matched Korean example with context
        additional_examples: 3-5 additional examples of same type
        client: API client (Anthropic or OpenAI)
        provider: "claude" or "gpt"

    Returns:
        Korean translation
    """
    # Handle special cases like "..." or very short text
    if en_text.strip() in ["...", "…", "!",  "?"]:
        return en_text.strip()

    speaker_label = en_speaker if en_speaker else "[Narration]"

    # Format the entire matched chapter as context
    full_context_text = "\n".join([
        f"{s or '[Narration]'}: {t}"
        for s, t in matched_kr.full_chapter
    ])

    # Format additional examples
    additional_text = "\n".join([
        f"{ex.speaker or '[Narration]'}: {ex.text}"
        for ex in additional_examples[:5]
    ])

    prompt = f"""Translate this Reverse: 1999 game segment from English to Korean.

MATCHED REFERENCE:
The text "{matched_kr.text}" from the Korean version semantically matches what you need to translate.

FULL DIALOGUE/CHAPTER CONTEXT (use this to find correct terminology and maintain consistency):
Below is the entire dialogue section containing the matched reference.
Use this to identify character names, organization names, and terminology as they appear in the official Korean version.

{full_context_text}

ADDITIONAL STYLE EXAMPLES from other sections:
{additional_text if additional_text else "(none)"}

NOW TRANSLATE THIS ENGLISH TEXT:
Type: {speaker_label}
English: "{en_text}"

CRITICAL RULES:
1. Match the EXACT style and tone of the matched Korean reference above
2. Use EXACT terminology from the Korean examples:
   - Character names (e.g., "Regulus" → use Korean version from examples)
   - Organization names (e.g., "Manus Vindictae" → use Korean version from examples)
   - Location names, item names, etc. - use official Korean terms
   - Do NOT transliterate - find and use the actual Korean name from the examples
3. Use similar grammar and formality level as the matched example
4. For dialogue: maintain character voice from matched example
5. For narration: maintain atmospheric style from matched example
6. Do NOT include speaker name in the translation (e.g., "레굴루스:" or "Regulus:")
7. Return ONLY the Korean translation text (no explanations, no speaker prefix)

Korean translation:"""

    try:
        if provider == "claude":
            message = client.messages.create(
                model="claude-sonnet-4-20250514",
                max_tokens=500,
                temperature=0.3,
                messages=[{"role": "user", "content": prompt}]
            )
            translation = message.content[0].text.strip()
        else:  # gpt
            message = client.chat.completions.create(
                model="gpt-4o",
                max_tokens=500,
                temperature=0.3,
                messages=[{"role": "user", "content": prompt}]
            )
            translation = message.choices[0].message.content.strip()

        # Remove quotes if LLM wrapped the response
        translation = translation.strip('"').strip("'").strip()

        # Remove speaker prefix if present (e.g., "레굴루스: " or "Regulus: ")
        # Check if translation starts with a speaker name followed by colon
        if ':' in translation[:30]:  # Only check first 30 chars
            # Split on first colon
            parts = translation.split(':', 1)
            if len(parts) == 2:
                # Check if the part before colon looks like a name (no spaces, reasonable length)
                potential_speaker = parts[0].strip()
                if len(potential_speaker) < 20 and ' ' not in potential_speaker:
                    # Likely a speaker prefix, remove it
                    translation = parts[1].strip()

        # Clean up malformed quotation marks
        # 1. Fix escaped quotes: \" → "
        translation = translation.replace('\\"', '"')

        # 2. Remove stray single quotes around Korean text
        # Pattern: '폭풍우를 → 폭풍우를
        translation = re.sub(r"'([가-힣]+)", r"\1", translation)

        # Pattern: 폭풍우'가 → 폭풍우가
        translation = re.sub(r"([가-힣])'", r"\1", translation)

        # 3. Remove orphaned double quotes around Korean text
        # Pattern: 순간 이동" 신비술 → 순간 이동 신비술 (closing quote without opening)
        translation = re.sub(r'([가-힣])"(\s)', r'\1\2', translation)

        # Pattern: "순간 이동 → 순간 이동 (opening quote without closing)
        translation = re.sub(r'(\s)"([가-힣])', r'\1\2', translation)

        # 4. Fix malformed quotes with particles
        # Pattern: 폭풍우"가 → 폭풍우가 (quote before particle)
        translation = re.sub(r'"([가-힣]{1,2}(?:[,.\s]|$))', r'\1', translation)

        # Pattern: 폭풍우가" → 폭풍우가 (quote after particle at word end)
        translation = re.sub(r'([가-힣])"(?=\s|$)', r'\1', translation)

        # 5. Clean up any remaining orphaned quotes in the middle of Korean text
        # Character-by-character scan for quotes between Korean and non-Korean
        parts = []
        i = 0
        while i < len(translation):
            char = translation[i]
            # Check if this is a quote character
            if char in ['"', "'"]:
                # Look ahead and behind to see if it's properly used
                prev_char = translation[i-1] if i > 0 else ''
                next_char = translation[i+1] if i < len(translation)-1 else ''

                # Check context
                is_prev_kr = bool(re.match(r'[가-힣]', prev_char))
                is_next_kr = bool(re.match(r'[가-힣]', next_char))
                is_prev_space = prev_char in [' ', '\t', '\n', '']
                is_next_space = next_char in [' ', '\t', '\n', '']

                # Remove quote if it's orphaned (between Korean and space/punctuation)
                if (is_prev_kr and is_next_space) or (is_prev_space and is_next_kr):
                    # Orphaned quote, skip it
                    i += 1
                    continue

                # Remove quote if it's between Korean characters
                if is_prev_kr and is_next_kr:
                    # Quote between Korean chars - likely malformed, skip it
                    i += 1
                    continue

            parts.append(char)
            i += 1

        translation = ''.join(parts)

        return translation

    except Exception as e:
        print(f"\nError calling LLM API: {e}")
        return ""


def translate_content_with_llm(
    en_chapters: List[List[Tuple]],
    kr_examples: List[KoreanExample],
    client,
    provider: str = "claude",
    limit: Optional[int] = None,
    max_workers: int = 10
) -> List[Tuple[str, str, str]]:
    """Translate English content using semantic matching with multithreading"""
    cache = {}  # Match cache: (speaker, text) -> (matched_example, confidence, reason)
    cache_lock = threading.Lock()  # Thread-safe cache access
    progress_lock = threading.Lock()  # Thread-safe progress tracking

    # Flatten all items with their original indices
    all_items = []
    for chapter_content in en_chapters:
        for en_speaker, en_text in chapter_content:
            all_items.append((len(all_items), en_speaker, en_text))

    # Apply limit if specified
    if limit:
        all_items = all_items[:limit]

    total_items = len(all_items)
    completed = [0]  # Use list to allow modification in nested function

    if limit:
        print(f"Starting translation with semantic matching (limit: {limit} items, {max_workers} workers)...")
    else:
        print(f"Starting translation with semantic matching ({max_workers} workers)...")

    def process_item(index: int, en_speaker: str, en_text: str) -> Tuple[int, str, str, str]:
        """Process a single translation item"""
        try:
            if not en_text:
                with progress_lock:
                    completed[0] += 1
                    print(f"Matching & Translating {completed[0]}/{total_items}...", end="\r", flush=True)
                return (index, en_speaker, en_text, "")

            # Find matching Korean example (with thread-safe cache)
            matched_example, confidence, reason = find_matching_korean(
                en_speaker, en_text, kr_examples, client, provider, cache, cache_lock
            )

            # Get additional examples of same type for context
            is_narration = (en_speaker == "")
            same_type_examples = [
                ex for ex in kr_examples
                if ex.is_narration == is_narration
            ][:5]

            # Translate using matched example as primary guide
            kr_text = translate_with_llm(
                en_speaker,
                en_text,
                matched_example,
                same_type_examples,
                client,
                provider
            )

            with progress_lock:
                completed[0] += 1
                print(f"Matching & Translating {completed[0]}/{total_items}...", end="\r", flush=True)

            return (index, en_speaker, en_text, kr_text)

        except Exception as e:
            print(f"\nError processing item {index}: {e}")
            with progress_lock:
                completed[0] += 1
            return (index, en_speaker, en_text, "")

    # Use ThreadPoolExecutor for parallel processing
    results = [None] * len(all_items)  # Pre-allocate to maintain order

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        # Submit all tasks
        future_to_index = {
            executor.submit(process_item, idx, speaker, text): idx
            for idx, speaker, text in all_items
        }

        # Collect results as they complete
        for future in as_completed(future_to_index):
            idx, en_speaker, en_text, kr_text = future.result()
            results[idx] = (en_speaker, en_text, kr_text)

    print()  # New line after progress
    print(f"Cache stats: {len(cache)} unique matches")

    return results


def create_segments(content: List[Tuple[str, str, str]]) -> List[dict]:
    """Create timed segments from content"""
    segments = []
    current_time = 0.0

    for speaker, text_en, text_kr in content:
        if not text_en:
            continue

        # Estimate duration based on text length
        char_count = len(text_en)
        duration = max(2.0, min(20.0, char_count * 0.05))

        segment = {
            "startTime": round(current_time, 1),
            "endTime": round(current_time + duration, 1),
            "text": text_en,
            "speaker": speaker,
            "translation": text_kr
        }

        segments.append(segment)
        current_time += duration

    return segments


def load_api_key_from_file(filename: str) -> Optional[str]:
    """Load API key from file if it exists"""
    try:
        with open(filename, 'r') as f:
            return f.read().strip()
    except FileNotFoundError:
        return None


def main():
    parser = argparse.ArgumentParser(
        description='Extract complete transcript with narration and dialogue from embedded JSON using LLM matching'
    )
    parser.add_argument('chapter', type=int, help='Chapter number')
    parser.add_argument('-o', '--output', required=True, help='Output JSON file')
    parser.add_argument('--llm-match', choices=['claude', 'gpt'], required=True,
                        help='LLM provider for semantic matching (claude or gpt)')
    parser.add_argument('--api-key', help='API key for LLM provider (or set ANTHROPIC_API_KEY/OPENAI_API_KEY env var)')
    parser.add_argument('--limit', type=int, help='Limit to first N items (for debugging)')
    parser.add_argument('--workers', type=int, default=10, help='Number of parallel workers for translation (default: 10)')

    args = parser.parse_args()

    provider = args.llm_match

    # Get script directory for loading key files
    script_dir = os.path.dirname(os.path.abspath(__file__))

    if provider == 'claude':
        if anthropic is None:
            print("Error: anthropic library not found")
            print("Run: uv pip install anthropic")
            return 1

        # Get API key (priority: --api-key > file > env var)
        api_key = args.api_key
        if not api_key:
            key_file = os.path.join(script_dir, 'keys', 'anthropic.key')
            api_key = load_api_key_from_file(key_file)
        if not api_key:
            api_key = os.environ.get('ANTHROPIC_API_KEY')

        if not api_key:
            print("Error: Anthropic API key not provided")
            print("Options:")
            print("  1. Save key to: keys/anthropic.key")
            print("  2. Set ANTHROPIC_API_KEY environment variable")
            print("  3. Use --api-key argument")
            return 1

        # Initialize Anthropic client
        client = anthropic.Anthropic(api_key=api_key)

    else:  # gpt
        if openai is None:
            print("Error: openai library not found")
            print("Run: uv pip install openai")
            return 1

        # Get API key (priority: --api-key > file > env var)
        api_key = args.api_key
        if not api_key:
            key_file = os.path.join(script_dir, 'keys', 'openai.key')
            api_key = load_api_key_from_file(key_file)
        if not api_key:
            api_key = os.environ.get('OPENAI_API_KEY')

        if not api_key:
            print("Error: OpenAI API key not provided")
            print("Options:")
            print("  1. Save key to: keys/openai.key")
            print("  2. Set OPENAI_API_KEY environment variable")
            print("  3. Use --api-key argument")
            return 1

        # Initialize OpenAI client
        client = openai.OpenAI(api_key=api_key)

    print(f"Fetching English content for chapter {args.chapter}...")
    en_html = fetch_html(args.chapter, 'en')
    if not en_html:
        print("Failed to fetch English content")
        return 1

    print("Extracting embedded JSON from English page...")
    en_data = extract_json_from_html(en_html)
    if not en_data:
        print("Failed to extract JSON data from English page")
        return 1

    print("Parsing English content (narration + dialogue)...")
    en_chapters = extract_content_by_chapter(en_data, lang='en')
    en_total = sum(len(ch) for ch in en_chapters)
    print(f"  Found {en_total} items across {len(en_chapters)} chapters")
    print(f"  Narration: {sum(1 for ch in en_chapters for s, _ in ch if not s)}")
    print(f"  Dialogue: {sum(1 for ch in en_chapters for s, _ in ch if s)}")

    print(f"\nFetching Korean content for style reference...")
    kr_html = fetch_html(args.chapter, 'kr')
    if not kr_html:
        print("Warning: Failed to fetch Korean content, will translate without style examples")
        kr_examples = []
    else:
        print("Extracting Korean style examples...")
        kr_data = extract_json_from_html(kr_html)
        if kr_data:
            kr_chapters = extract_content_by_chapter(kr_data, lang='kr')
            # Build Korean examples with context for semantic matching
            print("Building Korean examples with context...")
            kr_examples = build_korean_examples_with_context(kr_chapters)
            print(f"  Built {len(kr_examples)} Korean examples with context")
        else:
            print("Warning: Failed to extract Korean data")
            kr_examples = []

    print(f"\nTranslating to Korean using {provider.upper()} with semantic matching (this may take a while)...")
    translated = translate_content_with_llm(en_chapters, kr_examples, client, provider, limit=args.limit, max_workers=args.workers)

    print("Creating timed segments...")
    segments = create_segments(translated)

    # Create output
    output_data = {"segments": segments}

    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump(output_data, f, ensure_ascii=False, indent=2)

    print(f"\nSuccess!")
    print(f"Saved to: {args.output}")
    print(f"Total segments: {len(segments)}")
    print(f"  Narration: {sum(1 for s in segments if not s['speaker'])}")
    print(f"  Dialogue: {sum(1 for s in segments if s['speaker'])}")

    # Show first few segments as preview
    print("\nFirst 5 segments:")
    for i, seg in enumerate(segments[:5]):
        speaker_label = seg['speaker'] if seg['speaker'] else "[Narration]"
        print(f"  {i}. {speaker_label}: {seg['text'][:50]}...")

    return 0


if __name__ == '__main__':
    exit(main())
