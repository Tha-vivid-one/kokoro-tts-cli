#!/usr/bin/env python3
"""Phase 2: Extract assistant messages from Claude Code transcripts.

Reads all .jsonl transcripts from ~/.claude/projects/,
extracts text content from assistant messages,
applies the same cleaning as tts-stop-hook.sh,
categorizes by length bucket and content type,
and outputs candidates for training data generation.

Usage:
  python3 extract_training_data.py              # Extract and categorize
  python3 extract_training_data.py --stats       # Show distribution stats only
  python3 extract_training_data.py --generate    # Generate ideal summaries via Claude API
"""
import json
import os
import re
import glob
import argparse
import hashlib
from pathlib import Path

TRANSCRIPTS = os.path.expanduser("~/.claude/projects/*/*.jsonl")
OUTPUT_DIR = Path(__file__).parent / "training_data"


def extract_text(message: dict) -> str:
    """Extract plain text from an assistant message's content blocks."""
    content = message.get("message", {}).get("content", [])
    texts = []
    for block in content:
        if isinstance(block, dict) and block.get("type") == "text":
            texts.append(block["text"])
    return "\n".join(texts)


def clean_text(text: str) -> str:
    """Mirror the cleaning logic from tts-stop-hook.sh."""
    lines = text.split("\n")
    cleaned = []
    in_code_block = False
    for line in lines:
        if line.strip().startswith("```"):
            in_code_block = not in_code_block
            continue
        if in_code_block:
            continue
        # Skip table rows
        if re.match(r"^\|.*\|$", line.strip()):
            continue
        # Strip inline code
        line = re.sub(r"`[^`]*`", "", line)
        # Strip URLs
        line = re.sub(r"https?://\S+", "", line)
        # Strip heading markers
        line = re.sub(r"^#+\s+", "", line)
        # Strip bold/italic
        line = re.sub(r"\*\*([^*]*)\*\*", r"\1", line)
        line = re.sub(r"\*([^*]*)\*", r"\1", line)
        # Strip list markers
        line = re.sub(r"^[*-]\s+", "", line)
        # Strip HTML tags
        line = re.sub(r"<[^>]*>", "", line)
        line = line.strip()
        if line:
            cleaned.append(line)
    return "\n".join(cleaned)


def detect_content_type(original: str, cleaned: str) -> list[str]:
    """Detect content categories present in the message."""
    types = []
    original_wc = len(original.split())
    cleaned_wc = len(cleaned.split())

    # Code-heavy: cleaned < 20% of original
    if original_wc > 50 and cleaned_wc < original_wc / 5:
        types.append("code_heavy")

    # Question: ? in last 200 chars
    if "?" in cleaned[-200:]:
        types.append("question")

    # Error
    if re.search(r"error|failed|traceback|exception|fatal", cleaned, re.I):
        types.append("error")

    # List: 3+ list items in original
    list_count = len(re.findall(r"^\s*[-*]\s+|^\s*\d+[.)]\s+", original, re.M))
    if list_count >= 3:
        types.append("list")

    # Table: original has table rows
    table_rows = len(re.findall(r"^\|.*\|$", original, re.M))
    if table_rows >= 3:
        types.append("table")

    # Confirmation/short
    if cleaned_wc < 20:
        types.append("short")

    # Plan/proposal
    if re.search(r"plan|proposal|approach|strategy|phase \d|step \d", cleaned, re.I):
        types.append("plan")

    if not types:
        types.append("general")

    return types


def get_length_bucket(word_count: int) -> str:
    if word_count < 20:
        return "tiny"
    elif word_count <= 60:
        return "short"
    elif word_count <= 150:
        return "medium"
    elif word_count <= 500:
        return "long"
    elif word_count <= 1000:
        return "very_long"
    else:
        return "massive"


def get_max_words(word_count: int) -> int:
    """Mirror the scaling table from tts-stop-hook.sh."""
    if word_count < 20:
        return 0  # passthrough
    elif word_count <= 60:
        return 20
    elif word_count <= 150:
        return 30
    elif word_count <= 500:
        return 40
    elif word_count <= 1000:
        return 50
    else:
        return 60


def extract_all() -> list[dict]:
    """Extract all assistant messages from all transcripts."""
    files = sorted(glob.glob(TRANSCRIPTS))
    seen = set()
    candidates = []

    for filepath in files:
        with open(filepath) as f:
            for line in f:
                try:
                    obj = json.loads(line)
                except (json.JSONDecodeError, ValueError):
                    continue

                if obj.get("type") != "assistant":
                    continue

                text = extract_text(obj)
                if not text or len(text.strip()) < 10:
                    continue

                # Deduplicate by content hash
                content_hash = hashlib.md5(text.encode()).hexdigest()[:12]
                if content_hash in seen:
                    continue
                seen.add(content_hash)

                cleaned = clean_text(text)
                if not cleaned or len(cleaned.strip()) < 5:
                    continue

                original_wc = len(text.split())
                cleaned_wc = len(cleaned.split())
                content_types = detect_content_type(text, cleaned)
                bucket = get_length_bucket(cleaned_wc)
                max_words = get_max_words(cleaned_wc)

                candidates.append({
                    "id": content_hash,
                    "original_text": text[:5000],  # cap for storage
                    "cleaned_text": cleaned[:3000],
                    "original_word_count": original_wc,
                    "cleaned_word_count": cleaned_wc,
                    "content_types": content_types,
                    "length_bucket": bucket,
                    "max_summary_words": max_words,
                    "source_file": os.path.basename(filepath),
                })

    return candidates


def print_stats(candidates: list[dict]):
    """Print distribution statistics."""
    print(f"\nTotal unique assistant messages: {len(candidates)}\n")

    # Length bucket distribution
    buckets = {}
    for c in candidates:
        b = c["length_bucket"]
        buckets[b] = buckets.get(b, 0) + 1
    print("Length Buckets:")
    for b in ["tiny", "short", "medium", "long", "very_long", "massive"]:
        print(f"  {b:12s}: {buckets.get(b, 0):4d}")

    # Content type distribution
    types = {}
    for c in candidates:
        for t in c["content_types"]:
            types[t] = types.get(t, 0) + 1
    print("\nContent Types:")
    for t, count in sorted(types.items(), key=lambda x: -x[1]):
        print(f"  {t:12s}: {count:4d}")


def sample_candidates(candidates: list[dict], target: int = 200) -> list[dict]:
    """Sample ~target candidates with good distribution across buckets and types."""
    # Group by bucket
    by_bucket = {}
    for c in candidates:
        b = c["length_bucket"]
        by_bucket.setdefault(b, []).append(c)

    # Target per bucket (proportional but with minimums)
    buckets = ["tiny", "short", "medium", "long", "very_long", "massive"]
    selected = []

    # Ensure coverage: take up to target/len(buckets) from each, with content type diversity
    per_bucket = max(15, target // len(buckets))

    for bucket in buckets:
        pool = by_bucket.get(bucket, [])
        if not pool:
            continue

        # Sort by content type diversity (prefer messages with rarer types)
        type_counts = {}
        for c in pool:
            for t in c["content_types"]:
                type_counts[t] = type_counts.get(t, 0) + 1

        def diversity_score(c):
            return sum(1.0 / type_counts[t] for t in c["content_types"])

        pool.sort(key=diversity_score, reverse=True)
        selected.extend(pool[:per_bucket])

    # Deduplicate and trim to target
    seen_ids = set()
    final = []
    for c in selected:
        if c["id"] not in seen_ids:
            seen_ids.add(c["id"])
            final.append(c)
    return final[:target]


def generate_summaries(candidates: list[dict]):
    """Generate ideal summaries using Claude API."""
    try:
        import anthropic
    except ImportError:
        print("ERROR: pip install anthropic")
        return

    client = anthropic.Anthropic()
    output_file = OUTPUT_DIR / "training_pairs.jsonl"
    OUTPUT_DIR.mkdir(exist_ok=True)

    existing_ids = set()
    if output_file.exists():
        with open(output_file) as f:
            for line in f:
                try:
                    existing_ids.add(json.loads(line)["id"])
                except:
                    pass

    remaining = [c for c in candidates if c["id"] not in existing_ids]
    print(f"\n{len(existing_ids)} already done, {len(remaining)} remaining\n")

    with open(output_file, "a") as out:
        for i, c in enumerate(remaining):
            max_words = c["max_summary_words"]

            # Passthrough for tiny messages
            if max_words == 0:
                pair = {
                    "id": c["id"],
                    "input": c["cleaned_text"],
                    "summary": c["cleaned_text"],
                    "max_words": 0,
                    "content_types": c["content_types"],
                    "length_bucket": c["length_bucket"],
                    "passthrough": True,
                }
                out.write(json.dumps(pair) + "\n")
                print(f"  [{i+1}/{len(remaining)}] {c['id']} passthrough ({c['cleaned_word_count']}w)")
                continue

            # Build the same prompt structure as summarize.py
            content_hints = []
            if "question" in c["content_types"]:
                content_hints.append("The response ends with a question. You MUST include that question in your summary.")
            if "error" in c["content_types"]:
                content_hints.append("This is an error report. State the error clearly.")
                max_words += 10
            if "list" in c["content_types"]:
                content_hints.append(f"The response contains a list. Summarize what the items are about, don't enumerate each one.")

            system_prompt = (
                f"You are generating an ideal spoken summary of a coding assistant's response. "
                f"The response was {c['cleaned_word_count']} words. "
                f"Write exactly the summary that should be spoken aloud — one or two sentences, "
                f"maximum {max_words} words. "
                f"Third person narrator voice (\"The assistant...\", \"Code was...\"). "
                f"No code, no file paths, no markdown. "
                f"Do not invent information not in the text. "
                f"Stay under {max_words} words — this is a hard limit. "
            )
            if content_hints:
                system_prompt += " ".join(content_hints)

            try:
                response = client.messages.create(
                    model="claude-haiku-4-5-20251001",
                    max_tokens=200,
                    system=system_prompt,
                    messages=[{"role": "user", "content": c["cleaned_text"][:3000]}],
                )
                summary = response.content[0].text.strip()

                pair = {
                    "id": c["id"],
                    "input": c["cleaned_text"][:3000],
                    "summary": summary,
                    "max_words": max_words,
                    "actual_words": len(summary.split()),
                    "content_types": c["content_types"],
                    "length_bucket": c["length_bucket"],
                    "passthrough": False,
                }
                out.write(json.dumps(pair) + "\n")
                out.flush()

                status = "OK" if len(summary.split()) <= max_words else "OVER"
                print(f"  [{i+1}/{len(remaining)}] {c['id']} {c['length_bucket']:8s} "
                      f"max={max_words}w actual={len(summary.split())}w [{status}] "
                      f"{summary[:60]}...")

            except Exception as e:
                print(f"  [{i+1}/{len(remaining)}] {c['id']} ERROR: {e}")

    print(f"\nDone. Output: {output_file}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--stats", action="store_true", help="Show distribution stats only")
    parser.add_argument("--generate", action="store_true", help="Generate ideal summaries via Claude API")
    parser.add_argument("--target", type=int, default=200, help="Target number of training pairs")
    args = parser.parse_args()

    print("Extracting assistant messages from transcripts...")
    all_candidates = extract_all()
    print_stats(all_candidates)

    if args.stats:
        exit(0)

    sampled = sample_candidates(all_candidates, args.target)
    print(f"\nSampled {len(sampled)} candidates for training data")

    # Save candidates
    OUTPUT_DIR.mkdir(exist_ok=True)
    candidates_file = OUTPUT_DIR / "candidates.jsonl"
    with open(candidates_file, "w") as f:
        for c in sampled:
            f.write(json.dumps(c) + "\n")
    print(f"Saved candidates to {candidates_file}")

    if args.generate:
        generate_summaries(sampled)
