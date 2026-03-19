#!/usr/bin/env bash
# Kokoro TTS Queue Consumer
# Polls /tmp/kokoro-queue/ for items and speaks them in order via speak.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEAK="$SCRIPT_DIR/speak.sh"
QUEUE_DIR="/tmp/kokoro-queue"
PID_FILE="/tmp/kokoro-queue-consumer.pid"
LOG="/tmp/kokoro-hook.log"

mkdir -p "$QUEUE_DIR"
echo $$ > "$PID_FILE"

log() {
  echo "[$(date)] [consumer] $1" >> "$LOG"
}

cleanup() {
  rm -f "$PID_FILE"
  log "Consumer stopped"
  exit 0
}

trap cleanup SIGTERM SIGINT

log "Consumer started (PID $$)"

while true; do
  # Find oldest queue item (sorted by filename = sequence order)
  item=$(ls "$QUEUE_DIR"/*.json 2>/dev/null | sort | head -1)

  if [ -z "$item" ]; then
    sleep 0.5
    continue
  fi

  # Read queue item
  text=$(jq -r '.text // empty' "$item" 2>/dev/null)
  voice=$(jq -r '.voice // "af_heart"' "$item" 2>/dev/null)
  session_id=$(jq -r '.session_id // "unknown"' "$item" 2>/dev/null)

  # Remove from queue immediately (before speaking, so we don't re-process on crash)
  rm -f "$item"

  if [ -z "$text" ]; then
    log "Empty text in queue item, skipping"
    continue
  fi

  log "Speaking queue item (session: ${session_id:0:8}...): ${text:0:60}..."

  # Speak — blocks until afplay finishes (or is killed)
  echo "$text" | "$SPEAK" -v "$voice" 2>> "$LOG"

  log "Finished speaking"
done
