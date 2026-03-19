#!/usr/bin/env python3
"""Summarize text using a small local model via mlx-lm.
Usage: echo "text to summarize" | ./summarize.py
       ./summarize.py "text to summarize"

Downloads the model on first run (~90MB for SmolLM2-135M).
"""
import sys
import os

# Suppress warnings
os.environ["TOKENIZERS_PARALLELISM"] = "false"
import warnings
warnings.filterwarnings("ignore")

MODEL_ID = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
SYSTEM_PROMPT = (
    "You are a spoken summary generator for a coding assistant. "
    "Produce 1-2 short spoken sentences. Rules: Be accurate and specific. "
    "No filler words. No first person. No code, URLs, or file paths. "
    "Do not interpret or editorialize. If the response contains a detailed plan, "
    "long explanation, or asks the user questions, summarize the key point and "
    "say to check the output for details. Keep it under 30 words."
)

def summarize(text: str) -> str:
    from mlx_lm import load, generate

    model, tokenizer = load(MODEL_ID)

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": text[:3000]},
    ]

    prompt = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
    response = generate(model, tokenizer, prompt=prompt, max_tokens=150, verbose=False)
    return response.strip()

if __name__ == "__main__":
    if len(sys.argv) > 1:
        text = " ".join(sys.argv[1:])
    else:
        text = sys.stdin.read()

    if not text.strip():
        print("No text provided", file=sys.stderr)
        sys.exit(1)

    print(summarize(text))
