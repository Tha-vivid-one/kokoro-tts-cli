#!/usr/bin/env bash
# TTS Stop Hook — summarizes via mlx-lm (Qwen2.5-1.5B) then pushes to queue
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

# Summarize via mlx-lm (local, no external API)
summary=$(echo "$cleaned" | "$VENV" "$SUMMARIZE" 2>/dev/null)

# Fall back to cleaned text if summarization fails
if [ -z "$summary" ]; then
  echo "[$(date)] mlx-lm summarization failed, using cleaned text" >> "$LOG"
  summary="$cleaned"
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
