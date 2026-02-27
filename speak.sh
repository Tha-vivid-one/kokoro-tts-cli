#!/bin/zsh
# Speak text using Kokoro TTS (local, no API, no cloud)
# Usage: echo "text" | ./speak.sh
#    or: ./speak.sh "text to speak"
#    or: ./speak.sh -v am_adam "text with different voice"
#    or: ./speak.sh -s 1.5 "speak faster"
#    or: ./speak.sh -s 2 -v am_adam "fast + different voice"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VOICE="af_heart"
SPEED="1.0"
VENV="$SCRIPT_DIR/.venv/bin/python3"
TMPFILE=$(mktemp /tmp/kokoro-XXXXX.wav)

# Parse flags
while [[ "$1" == -* ]]; do
    case "$1" in
        -v) VOICE="$2"; shift 2 ;;
        -s) SPEED="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: speak.sh [OPTIONS] \"text to speak\""
            echo "  -v VOICE   Voice name (default: af_heart)"
            echo "  -s SPEED   Playback speed multiplier (default: 1.0)"
            echo "  -h         Show this help"
            echo ""
            echo "Pipe mode: echo \"text\" | speak.sh"
            echo ""
            echo "Voices: af_heart, af_bella, af_nicole, af_sky, am_adam, am_michael, bm_george, bf_emma..."
            echo "Full list: https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md"
            exit 0
            ;;
        *) shift ;;
    esac
done

if [ -n "$1" ]; then
    TEXT="$1"
else
    TEXT=$(cat)
fi

if [ -z "$TEXT" ]; then
    echo "No text provided. Usage: speak.sh \"text to speak\""
    exit 1
fi

# Check venv exists
if [ ! -f "$VENV" ]; then
    echo "Kokoro not installed. Run: ./install.sh"
    exit 1
fi

# Generate audio
"$VENV" -c "
import warnings
warnings.filterwarnings('ignore')
from kokoro import KPipeline
import soundfile as sf
import numpy as np

pipeline = KPipeline(lang_code='a')
generator = pipeline('''$TEXT''', voice='$VOICE')
audio_chunks = []
for gs, ps, audio in generator:
    audio_chunks.append(audio)
sf.write('$TMPFILE', np.concatenate(audio_chunks), 24000)
" 2>/dev/null

# Play audio at specified speed
afplay -r "$SPEED" "$TMPFILE"
rm -f "$TMPFILE"
