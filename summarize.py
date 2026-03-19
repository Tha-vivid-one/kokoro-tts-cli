#!/usr/bin/env python3
"""Summarize text using a small local model via mlx-lm.

Usage:
  echo "text" | ./summarize.py --max-words 40 --word-count 200 --content-hint "..."
  echo "short text" | ./summarize.py --max-words 0   # passthrough, no model

Downloads the model on first run (~1GB for Qwen2.5-1.5B-Instruct-4bit).
"""
import sys
import os
import argparse

os.environ["TOKENIZERS_PARALLELISM"] = "false"
import warnings
warnings.filterwarnings("ignore")

MODEL_ID = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"


def build_prompt(word_count: int, max_words: int, content_hint: str) -> str:
    lines = [
        "You are a narrator summarizing what a coding assistant just did.",
        f"The assistant's response was {word_count} words.",
        f"Summarize in one or two sentences. Maximum {max_words} words.",
    ]
    if content_hint:
        lines.append(content_hint)
    lines.append("Speak in third person. No code, no file paths, no markdown.")
    lines.append("Do not invent information not present in the text.")
    lines.append(f"Stay under {max_words} words. This is a hard limit.")
    return " ".join(lines)


def summarize(text: str, max_words: int, word_count: int, content_hint: str) -> str:
    from mlx_lm import load, generate

    model, tokenizer = load(MODEL_ID)
    system_prompt = build_prompt(word_count, max_words, content_hint)

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": text[:3000]},
    ]

    prompt = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
    response = generate(model, tokenizer, prompt=prompt, max_tokens=150, verbose=False)
    return response.strip()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--max-words", type=int, default=40)
    parser.add_argument("--word-count", type=int, default=100)
    parser.add_argument("--content-hint", type=str, default="")
    args = parser.parse_args()

    text = sys.stdin.read().strip()
    if not text:
        sys.exit(1)

    # Passthrough: max-words=0 means don't summarize
    if args.max_words == 0:
        print(text)
        sys.exit(0)

    print(summarize(text, args.max_words, args.word_count, args.content_hint))
