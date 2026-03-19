#!/usr/bin/env bash
# TTS Stop Hook — smart summarization with length scaling and content detection
# Only queues if the warm daemon is running (menu bar icon = on/off)

SUMMARIZE="/Users/lincoln/kokoro-tts-cli/summarize.py"
VENV="/Users/lincoln/kokoro-tts-cli/.venv/bin/python3"
LOG="/tmp/kokoro-hook.log"
MAX_CHARS=3000
SOCKET="/tmp/kokoro-daemon.sock"
VOICE_FILE="/tmp/kokoro-voice.txt"
MUTE_FILE="/tmp/kokoro-muted-sessions.json"
QUEUE_DIR="/tmp/kokoro-queue"

# Require daemon to be running
if [ ! -S "$SOCKET" ]; then
  exit 0
fi

# Read the hook payload from stdin
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)
last_message=$(echo "$input" | jq -r '.last_assistant_message // empty' 2>/dev/null)

# Check if this session is muted
if [ -n "$session_id" ] && [ -f "$MUTE_FILE" ]; then
  is_muted=$(jq -r --arg sid "$session_id" 'if . | index($sid) then "yes" else "no" end' "$MUTE_FILE" 2>/dev/null)
  if [ "$is_muted" = "yes" ]; then
    exit 0
  fi
fi

if [ -z "$last_message" ]; then
  echo "[$(date)] No assistant message in payload" >> "$LOG"
  exit 0
fi

# Read selected voice (set by menu bar app)
voice="af_heart"
if [ -f "$VOICE_FILE" ]; then
  v=$(cat "$VOICE_FILE")
  [ -n "$v" ] && voice="$v"
fi

# Measure original length before cleaning (for code-only detection)
original_word_count=$(echo "$last_message" | wc -w | tr -d ' ')

# Strip code blocks and markdown before summarizing
cleaned=$(echo "$last_message" | sed \
  -e '/^```/,/^```/d' \
  -e '/^|.*|$/d' \
  -e 's/`[^`]*`//g' \
  -e 's/https\?:\/\/[^ ]*//g' \
  -e 's/^#\+ //g' \
  -e 's/\*\*\([^*]*\)\*\*/\1/g' \
  -e 's/\*\([^*]*\)\*/\1/g' \
  -e 's/^[*-] //g' \
  -e 's/<[^>]*>//g' \
  -e '/^$/d'
)
cleaned="${cleaned:0:$MAX_CHARS}"

if [ -z "$cleaned" ]; then
  echo "[$(date)] Message was empty after cleaning" >> "$LOG"
  exit 0
fi

# --- Word count and scaling table ---
word_count=$(echo "$cleaned" | wc -w | tr -d ' ')

# Code-only detection: if cleaned is <20% of original, it was mostly code
if [ "$original_word_count" -gt 50 ] && [ "$word_count" -lt $((original_word_count / 5)) ]; then
  summary="Code was generated. Check the output."
  echo "[$(date)] Code-only response detected (${word_count}/${original_word_count} words after clean)" >> "$LOG"
  # Skip to queue
  mkdir -p "$QUEUE_DIR"
  (
    flock -x 9
    counter=$(cat "$QUEUE_DIR/.counter" 2>/dev/null || echo 0)
    counter=$((counter + 1))
    echo "$counter" > "$QUEUE_DIR/.counter"
    filename=$(printf "%06d_%s.json" "$counter" "$(date +%s)")
    jq -n --arg sid "$session_id" --arg text "$summary" --arg voice "$voice" --argjson ts "$(date +%s)" \
      '{session_id: $sid, text: $text, voice: $voice, queued_at: $ts}' > "$QUEUE_DIR/$filename"
    echo "[$(date)] Queued item $filename: ${summary}" >> "$LOG"
  ) 9>"$QUEUE_DIR/.lock"
  exit 0
fi

# Scaling table: input word count → max summary words
if [ "$word_count" -lt 20 ]; then
  max_words=0  # passthrough
elif [ "$word_count" -le 60 ]; then
  max_words=20
elif [ "$word_count" -le 150 ]; then
  max_words=30
elif [ "$word_count" -le 500 ]; then
  max_words=40
elif [ "$word_count" -le 1000 ]; then
  max_words=50
else
  max_words=60
fi

# --- Content-type detection ---
content_hint=""

# Question detection: ? in last 200 chars
last_200="${cleaned: -200}"
if echo "$last_200" | grep -q '?'; then
  content_hint="The response ends with a question. You MUST include that question in your summary."
fi

# Error detection
if echo "$cleaned" | grep -qi 'error\|failed\|traceback\|exception\|fatal'; then
  if [ -n "$content_hint" ]; then
    content_hint="$content_hint This is an error report. State the error clearly."
  else
    content_hint="This is an error report. State the error clearly. Use an urgent tone."
  fi
  max_words=$((max_words + 10))
fi

# List detection: 3+ list items
list_count=$(echo "$cleaned" | grep -cE '^\s*([-*]|[0-9]+[.)]) ')
if [ "$list_count" -ge 3 ]; then
  if [ -n "$content_hint" ]; then
    content_hint="$content_hint The response lists $list_count items."
  else
    content_hint="The response lists $list_count items. Summarize what the items are about, don't enumerate each one."
  fi
fi

# --- Passthrough or summarize ---
if [ "$max_words" -eq 0 ]; then
  # Short input: speak directly, no model call
  summary="$cleaned"
  echo "[$(date)] Passthrough (${word_count} words, under 20)" >> "$LOG"
else
  # Summarize via mlx-lm with scaling args
  summary=$(echo "$cleaned" | "$VENV" "$SUMMARIZE" \
    --max-words "$max_words" \
    --word-count "$word_count" \
    --content-hint "$content_hint" 2>/dev/null)

  # Fall back to cleaned text if summarization fails
  if [ -z "$summary" ]; then
    echo "[$(date)] mlx-lm summarization failed, using cleaned text" >> "$LOG"
    summary="$cleaned"
  fi

  # Log scaling info
  actual_words=$(echo "$summary" | wc -w | tr -d ' ')
  echo "[$(date)] Scaling: input=${word_count}w max=${max_words}w actual=${actual_words}w hint='${content_hint:0:40}'" >> "$LOG"
fi

# Push to queue
mkdir -p "$QUEUE_DIR"
(
  flock -x 9
  counter=$(cat "$QUEUE_DIR/.counter" 2>/dev/null || echo 0)
  counter=$((counter + 1))
  echo "$counter" > "$QUEUE_DIR/.counter"
  filename=$(printf "%06d_%s.json" "$counter" "$(date +%s)")
  jq -n --arg sid "$session_id" --arg text "$summary" --arg voice "$voice" --argjson ts "$(date +%s)" \
    '{session_id: $sid, text: $text, voice: $voice, queued_at: $ts}' > "$QUEUE_DIR/$filename"
  echo "[$(date)] Queued item $filename (session: ${session_id:0:8}...): ${summary:0:60}..." >> "$LOG"
) 9>"$QUEUE_DIR/.lock"

exit 0
