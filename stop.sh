#!/bin/zsh
# Stop Kokoro TTS playback
killall afplay 2>/dev/null
pkill -f "from kokoro import" 2>/dev/null
rm -f /tmp/kokoro-*.wav 2>/dev/null
