# Summarization Model Research

## Current Model: Qwen2.5-1.5B-Instruct-4bit (mlx-lm)
- Size: ~839MB on disk
- Runs via mlx-lm in the kokoro venv (no external app needed)
- Prompt: "Summarize in one casual sentence what was accomplished. No code or file paths. Talk like telling a coworker. If there are questions or choices, mention what decision is needed. Keep it under 25 words."

## Models Tested

| Model | Size | Result |
|-------|------|--------|
| SmolLM2-135M-Instruct | 90 MB | Failed — parrots input verbatim, no summarization ability |
| Qwen2.5-0.5B-Instruct | 350 MB | Failed — mostly parroting with minor rewording |
| Qwen2.5-1.5B-Instruct-4bit | 839 MB | Usable — good summaries but hallucination issues on edge cases |
| Gemma 3n E4B (LM Studio) | 5.5 GB | Good quality but requires LM Studio app dependency |

## Test Results (Qwen2.5-1.5B, 15 tests)

| # | Input Type | Summary | Verdict |
|---|-----------|---------|---------|
| 1 | One word ("Yes.") | Hallucinated "project on time and budget" | **Bad** |
| 2 | Simple confirm | "The code update was committed to the GitHub repository." | **Good** |
| 3 | Short explanation | Accurate, kept key details | **Good** |
| 4 | Bug fix | "Fixed the script to read from the last_assistant_message field" | **Good** |
| 5 | Question to user | Captures the choice needed | **Good** |
| 6 | Multiple options | Hallucinated a decision ("chose Option C") | **Bad** |
| 7 | Error message | "Need to convert a file path to NSImage" | **Good** |
| 8 | Code-heavy | Ignored code, summarized the fix | **Good** |
| 9 | Table/numbers | "2.2 GB, down from 8 GB" — correct | **Good** |
| 10 | Long technical | OK but vague ("chatbot") | **OK** |
| 11 | Scientific | Nailed the key finding about 1B inflection point | **Good** |
| 12 | Git log | Vague but acceptable | **OK** |
| 13 | Very long rambling | Hit the key milestones in order | **Good** |
| 14 | JSON/API | Focused on wrong detail | **OK** |
| 15 | Comparison/tradeoff | Too terse, lost the key insight | **Bad** |

## Known Issues
- **Hallucination on very short input**: When given <20 words, model invents context
- **Fabricates decisions**: On multi-option responses, may claim a choice was made
- **Loses nuance on comparisons**: Tradeoff analysis gets oversimplified

## Ideas to Explore
- Minimum length bypass: skip summarization for short messages (<20 words), speak directly
- Anti-hallucination prompt: add "Do not invent information not in the text"
- Larger model (3B) for better instruction following
- Hybrid: use Gemma via LM Studio when available, fall back to Qwen when not
- Fine-tune Qwen2.5-1.5B on a small dataset of (response, ideal_summary) pairs
