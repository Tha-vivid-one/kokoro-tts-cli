#!/bin/zsh
# Stop Kokoro TTS playback, generation, and daemon
killall afplay 2>/dev/null
pkill -f "from kokoro import" 2>/dev/null

# Stop daemon if running
if [ -f /tmp/kokoro-daemon.pid ]; then
    kill "$(cat /tmp/kokoro-daemon.pid)" 2>/dev/null
    rm -f /tmp/kokoro-daemon.pid
fi
rm -f /tmp/kokoro-daemon.sock
setopt nullglob 2>/dev/null; rm -f /tmp/kokoro-*.wav
