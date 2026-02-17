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


def translate_with_llm(
    en_speaker: str,
    en_text: str,
    kr_examples: List[Tuple[str, str]],
    client,
    provider: str = "claude"
) -> str:
    """
    Translate English text to Korean using LLM with Korean style examples.

    Args:
        en_speaker: English speaker name (or "" for narration)
        en_text: English text to translate
        kr_examples: List of (speaker, korean_text) tuples for style reference
        client: API client (Anthropic or OpenAI)
        provider: "claude" or "gpt"

    Returns:
        Korean translation
    """
    # Handle special cases like "..." or very short text
    if en_text.strip() in ["...", "…", "!",  "?"]:
        return en_text.strip()

    speaker_label = en_speaker if en_speaker else "Narration"

    # Build examples section
    examples_text = "\n".join([
        f"{'[Narration]' if not spk else spk}: {text}"
        for spk, text in kr_examples[:10]  # Use up to 10 examples
    ])

    prompt = f"""Translate this Reverse: 1999 game story segment from English to Korean.

CRITICAL RULES:
- Return ONLY the Korean translation (no explanations)
- Match the EXACT translation style and tone shown in the Korean examples below
- For narration: Use the same atmospheric, natural style as the Korean narration examples
- For dialogue: Use the same casual, character-appropriate patterns as the Korean dialogue examples
- Maintain the same level of formality and sentence structure as the examples

Korean style examples from the game:
{examples_text}

Now translate this English segment using the SAME STYLE as above:
Type: {speaker_label}
Text: {en_text}

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

        return translation

    except Exception as e:
        print(f"\nError calling LLM API: {e}")
        return ""


def translate_content_with_llm(
    en_chapters: List[List[Tuple]],
    kr_examples: List[Tuple[str, str]],
    client,
    provider: str = "claude"
) -> List[Tuple[str, str, str]]:
    """Translate English content to Korean using LLM with Korean style examples"""
    all_translated = []

    # Count total items for progress tracking
    total_items = sum(len(ch) for ch in en_chapters)
    current_item = 0

    # Process English content chapter by chapter
    for chapter_content in en_chapters:
        for en_speaker, en_text in chapter_content:
            current_item += 1
            print(f"Translating {current_item}/{total_items}...", end="\r", flush=True)

            if not en_text:
                all_translated.append((en_speaker, en_text, ""))
                continue

            # Translate with LLM using Korean examples for style
            kr_text = translate_with_llm(en_speaker, en_text, kr_examples, client, provider)
            all_translated.append((en_speaker, en_text, kr_text))

    print()  # New line after progress

    return all_translated


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
            # Flatten all Korean content for style examples
            kr_examples = [item for chapter in kr_chapters for item in chapter]
            print(f"  Found {len(kr_examples)} Korean examples for style reference")
        else:
            print("Warning: Failed to extract Korean data")
            kr_examples = []

    print(f"\nTranslating to Korean using {provider.upper()} with style matching (this may take a while)...")
    translated = translate_content_with_llm(en_chapters, kr_examples, client, provider)

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
