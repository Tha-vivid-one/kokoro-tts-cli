#!/bin/zsh
# Start the Kokoro TTS daemon if not already running
# Usage: ./warm.sh
#
# The daemon keeps the model loaded in memory so subsequent
# speak.sh calls skip the ~5s model load and generate instantly.
# Auto-shuts down after 10 minutes of inactivity.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON="$SCRIPT_DIR/kokoro-daemon.py"
VENV="$SCRIPT_DIR/.venv/bin/python3"
PID_FILE=/tmp/kokoro-daemon.pid
SOCKET=/tmp/kokoro-daemon.sock

# Check venv exists
if [ ! -f "$VENV" ]; then
    echo "Kokoro not installed. Run: ./install.sh"
    exit 1
fi

# Check if daemon is already running
if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
        if [ -S "$SOCKET" ]; then
            echo "Kokoro daemon already running (PID $pid)"
            exit 0
        fi
        kill "$pid" 2>/dev/null
    fi
    rm -f "$PID_FILE"
fi

# Ensure queue directory exists
mkdir -p /tmp/kokoro-queue

# Start daemon in background, wait for ready signal
"$VENV" "$DAEMON" &
daemon_pid=$!

for i in {1..60}; do
    if [ -S "$SOCKET" ]; then
        echo "Kokoro daemon ready (PID $daemon_pid)"

        # Start queue consumer if not already running
        CONSUMER_PID_FILE=/tmp/kokoro-queue-consumer.pid
        if [ -f "$CONSUMER_PID_FILE" ]; then
            consumer_pid=$(cat "$CONSUMER_PID_FILE")
            if kill -0 "$consumer_pid" 2>/dev/null; then
                echo "Queue consumer already running (PID $consumer_pid)"
                exit 0
            fi
        fi
        bash "$SCRIPT_DIR/queue-consumer.sh" &
        echo "Queue consumer started"
        exit 0
    fi
    sleep 0.5
done

echo "Daemon failed to start" >&2
kill "$daemon_pid" 2>/dev/null
exit 1
