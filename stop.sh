#!/bin/zsh
# Stop Kokoro TTS playback, generation, daemon, and queue consumer
killall afplay 2>/dev/null
pkill -f "from kokoro import" 2>/dev/null

# Stop queue consumer
if [ -f /tmp/kokoro-queue-consumer.pid ]; then
    kill "$(cat /tmp/kokoro-queue-consumer.pid)" 2>/dev/null
    rm -f /tmp/kokoro-queue-consumer.pid
fi

# Stop daemon if running
if [ -f /tmp/kokoro-daemon.pid ]; then
    kill "$(cat /tmp/kokoro-daemon.pid)" 2>/dev/null
    rm -f /tmp/kokoro-daemon.pid
fi
rm -f /tmp/kokoro-daemon.sock

# Clean up queue and temp files
rm -rf /tmp/kokoro-queue
setopt nullglob 2>/dev/null; rm -f /tmp/kokoro-*.wav
