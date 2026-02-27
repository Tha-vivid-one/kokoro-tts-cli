#!/bin/zsh
# Install Kokoro TTS locally
# Requires: Python 3.10-3.12, Homebrew (macOS)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing Kokoro TTS..."

# Check Python version
PYTHON=""
for v in python3.12 python3.11 python3.10; do
    if command -v $v &>/dev/null; then
        PYTHON=$v
        break
    fi
done

if [ -z "$PYTHON" ]; then
    echo "Python 3.10-3.12 required. Python 3.13+ doesn't work yet."
    echo "Install with: brew install python@3.12"
    exit 1
fi

echo "Using $($PYTHON --version)"

# Install espeak-ng (phoneme dependency)
if ! command -v espeak-ng &>/dev/null; then
    echo "Installing espeak-ng..."
    if command -v brew &>/dev/null; then
        brew install espeak-ng
    else
        echo "espeak-ng required. Install it for your platform:"
        echo "  macOS: brew install espeak-ng"
        echo "  Ubuntu: sudo apt install espeak-ng"
        exit 1
    fi
fi

# Create venv and install
echo "Creating virtual environment..."
$PYTHON -m venv "$SCRIPT_DIR/.venv"
"$SCRIPT_DIR/.venv/bin/pip" install -q kokoro soundfile pathvalidate numpy

# Make scripts executable
chmod +x "$SCRIPT_DIR/speak.sh" "$SCRIPT_DIR/stop.sh" "$SCRIPT_DIR/read-quote.sh"

# Test it
echo ""
echo "Testing..."
"$SCRIPT_DIR/speak.sh" "Kokoro is ready. You sound great."

echo ""
echo "Done. Usage:"
echo "  ./speak.sh \"hello world\""
echo "  ./speak.sh -v am_adam \"with a different voice\""
echo "  ./speak.sh -s 1.5 \"speak faster\""
echo "  echo \"piped text\" | ./speak.sh"
echo "  ./read-quote.sh quotes.md"
