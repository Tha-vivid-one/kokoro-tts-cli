#!/usr/bin/env bash
# TTS Stop Hook — summarizes via Gemma 3n (LM Studio) then speaks via Kokoro
# Only speaks if the warm daemon is running (menu bar icon = on/off)

SPEAK="/Users/lincoln/kokoro-tts-cli/speak.sh"
LOG="/tmp/kokoro-hook.log"
MAX_CHARS=3000
SOCKET="/tmp/kokoro-daemon.sock"
VOICE_FILE="/tmp/kokoro-voice.txt"
LM_STUDIO="http://localhost:1234/v1/chat/completions"
SUMMARY_MODEL="google/gemma-3n-e4b"

# Require daemon to be running
if [ ! -S "$SOCKET" ]; then
  exit 0
fi

# Read selected voice (set by menu bar app)
VOICE_ARG=""
if [ -f "$VOICE_FILE" ]; then
  voice=$(cat "$VOICE_FILE")
  if [ -n "$voice" ]; then
    VOICE_ARG="-v $voice"
  fi
fi

# Read the hook payload from stdin
input=$(cat)
last_message=$(echo "$input" | jq -r '.last_assistant_message // empty' 2>/dev/null)

if [ -z "$last_message" ]; then
  echo "[$(date)] No assistant message in payload" >> "$LOG"
  exit 0
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

# Summarize via LM Studio (Gemma 3n)
escaped=$(echo "$cleaned" | jq -Rs '.')
payload=$(cat <<ENDJSON
{
  "model": "$SUMMARY_MODEL",
  "messages": [
    {"role": "system", "content": "You are a spoken summary generator for a coding assistant. Produce 1-2 short spoken sentences. Rules: Be accurate and specific. No filler words. No first person. No code, URLs, or file paths. Do not interpret or editorialize. If the response contains a detailed plan, long explanation, multiple options, or asks the user questions, summarize the key point and say to check the output for details. If the response asks the user to choose or answer something, mention what decision is needed. Keep it under 30 words."},
    {"role": "user", "content": $escaped}
  ],
  "max_tokens": 150,
  "temperature": 0.3
}
ENDJSON
)

summary=$(curl -s --max-time 10 "$LM_STUDIO" \
  -H "Content-Type: application/json" \
  -d "$payload" 2>/dev/null | jq -r '.choices[0].message.content // empty' 2>/dev/null)

# Fall back to cleaned text if summarization fails
if [ -z "$summary" ]; then
  echo "[$(date)] LM Studio summarization failed, using cleaned text" >> "$LOG"
  summary="$cleaned"
fi

echo "[$(date)] Speaking: ${summary:0:80}..." >> "$LOG"
echo "$summary" | "$SPEAK" $VOICE_ARG 2>> "$LOG"

exit 0
