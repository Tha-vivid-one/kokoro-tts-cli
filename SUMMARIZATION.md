# Summarization Model Research

## Current Production Model: Qwen2.5-1.5B-Instruct-4bit (mlx-lm)
- Size: ~839MB on disk (4-bit quantized)
- Runs via mlx-lm in the kokoro venv (no external app needed)
- **Not fine-tuned** — running zero-shot with Phase 1 dynamic prompting
- 93% word budget compliance, 80% quality (9 Good, 3 OK, 3 Bad on 15 tests)
- Phase 1 improvements (scaling table, content detection, anti-hallucination prompt) made this reliable enough for daily use

## Models Tested (Zero-Shot)

| Model | Size | Result |
|-------|------|--------|
| SmolLM2-135M-Instruct | 90 MB | Failed — parrots input verbatim, no summarization ability |
| Qwen2.5-0.5B-Instruct | 350 MB | Failed — mostly parroting with minor rewording |
| Qwen2.5-1.5B-Instruct-4bit | 839 MB | **Reliable** — 93% budget compliance with Phase 1 prompting. Production model. |
| Gemma 3n E4B (LM Studio) | 5.5 GB | Good quality but requires LM Studio app dependency |

## Models Tested (Fine-Tuned with LoRA)

All trained on 125 examples from 72 real Claude Code transcripts, evaluated on 15 test scenarios.

| Model | Params | Size | Budget Compliance | Quality | Notes |
|-------|--------|------|------------------|---------|-------|
| SmolLM2-135M | 135M | 90 MB | 47% (7/15) | 5 Good / 3 OK / 7 Bad | Too small. Hallucinations, fabricated details. |
| Qwen3-0.6B | 0.6B | 335 MB | 80% (12/15) | 8 Good / 5 OK / 2 Bad | Best small model. Decent but budget compliance gap. |
| Gemma 3 1B IT | 1B | 733 MB | 13% (2/15) | Unusable | EOS token bug caused repetition loops. All outputs over budget. |
| Qwen2.5-1.5B (bad data) | 1.5B | 839 MB | 33% (5/15) | Degraded | Training hurt constraint following. Worse than zero-shot. |
| Qwen2.5-1.5B (fixed data) | 1.5B | 839 MB | 67% (10/15) | Improved | Better than bad data but still worse than zero-shot (93%). |

## Key Finding: Fine-Tuning Degraded Constraint Following

Fine-tuning Qwen2.5-1.5B made it worse at word budget compliance (93% → 33-67%), even though summary style improved. The model already knows how to summarize — it just needed better prompts (Phase 1), not training data.

**Root cause**: Training examples taught the model the right *style* but overrode its built-in instruction-following ability. Even after fixing training data quality (removing over-budget examples), the fine-tuned model couldn't match zero-shot performance.

**Lesson learned**: For models that already follow instructions well (like Qwen2.5-1.5B), prompt engineering beats fine-tuning on small datasets. Fine-tuning is more useful for models that can't do the task at all (like SmolLM2-135M, which went from 0% to 47%).

## Training Data Quality Issue (Discovered & Fixed)

Initial training data had 22% bad examples:
- 12 summaries over their word budget (teaching the model to ignore limits)
- 15 summaries under 40% of budget (teaching vagueness)

Fixed by trimming over-budget examples and expanding under-budget ones. This improved Qwen2.5-1.5B from 33% to 67% compliance, confirming that training data quality matters — but still couldn't beat zero-shot.

**Future fine-tuning advice**: Use only 3-5 test scenarios to avoid overfitting evaluation. The 15-test suite was overkill for iterating on training. Keep training data strictly within word budgets.

## Fine-Tuning Pipeline

Training data and pipeline are model-agnostic and reusable:
- **157 training pairs** extracted from 72 real Claude Code conversation transcripts
- Categorized by length bucket (tiny/short/medium/long/very_long/massive) and content type (question/error/list/plan/table/code_heavy/general)
- 125 train / 32 validation split in mlx-lm chat format
- LoRA fine-tuning via `mlx_lm lora` on Apple Silicon
- Data lives in `training_data/train.jsonl` and `training_data/valid.jsonl`
- Extraction script: `extract_training_data.py`

## Test Results (Qwen2.5-1.5B Zero-Shot + Phase 1 Prompting, 15 tests)

| # | Input Type | Summary | Verdict |
|---|-----------|---------|---------|
| 1 | One word ("Yes.") | Passthrough (<20w, no model call) | **Good** |
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

## Candidate Models for Future Testing

Researched 2026-03-19. IFEval measures instruction/constraint following.

| Rank | Model | Params | Size (4-bit) | IFEval | Status |
|------|-------|--------|-------------|--------|--------|
| 1 | Gemma 3 1B IT (`mlx-community/gemma-3-1b-it-4bit`) | 1B | 733 MB | **80.2** | Tested — EOS bug, unusable after LoRA |
| 2 | Qwen2.5-1.5B (`mlx-community/Qwen2.5-1.5B-Instruct-4bit`) | 1.5B | 869 MB | 42.5 | **Production (zero-shot)** |
| 3 | Qwen3-0.6B (`mlx-community/Qwen3-0.6B-4bit`) | 0.6B | 335 MB | ~50-65 est | Tested — 80% budget, best small model |
| 4 | Llama 3.2 1B (`mlx-community/Llama-3.2-1B-Instruct-4bit`) | 1B | 695 MB | 59.5 | Untested |
| 5 | Gemma 3 270M (`mlx-community/gemma-3-270m-it-4bit`) | 270M | 151 MB | 51.2 | Untested |

## Known Issues (Qwen2.5-1.5B Zero-Shot)
- **Fabricates decisions**: On multi-option responses, may claim a choice was made
- **Loses nuance on comparisons**: Tradeoff analysis gets oversimplified
- Short input hallucination solved by Phase 1 passthrough (<20 words skips model)

## Phase 1 Improvements (Implemented)
- Scaling table: input word count maps to summary word budget (20-60 words)
- Content-type detection: questions, errors, lists, code-only, tables
- Passthrough for <20 word inputs (no model call, solved hallucination on short input)
- Anti-hallucination prompt: "Do not invent information not present in the text"
- Dynamic prompt construction with word count and content hints
