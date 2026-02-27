#!/bin/zsh
# Read a random quote aloud from a markdown file
# Usage: ./read-quote.sh quotes.md
#    or: ./read-quote.sh (uses quotes.md in same directory)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEAK="$SCRIPT_DIR/speak.sh"
QUOTES_FILE="${1:-$SCRIPT_DIR/quotes.md}"

if [ ! -f "$QUOTES_FILE" ]; then
    echo "Quotes file not found: $QUOTES_FILE"
    echo "Usage: read-quote.sh [path/to/quotes.md]"
    exit 1
fi

# Extract plain-text quotes (skip code blocks, headers, empty lines, short lines)
quotes=()
in_code_block=false

while IFS= read -r line; do
    if [[ "$line" == '```'* ]]; then
        if $in_code_block; then in_code_block=false; else in_code_block=true; fi
        continue
    fi
    $in_code_block && continue

    [[ -z "$line" ]] && continue
    [[ "$line" == '#'* ]] && continue
    [[ "$line" == '---' ]] && continue
    [[ "$line" == '!'* ]] && continue

    # Clean markdown formatting
    clean=$(echo "$line" | sed 's/\*\*//g; s/==//g; s/^- //; s/^> //')
    [[ -z "$clean" ]] && continue
    [[ ${#clean} -lt 15 ]] && continue

    quotes+=("$clean")
done < "$QUOTES_FILE"

if [[ ${#quotes[@]} -eq 0 ]]; then
    echo "No quotes found in $QUOTES_FILE"
    exit 1
fi

# Pick a random quote
random_index=$((RANDOM % ${#quotes[@]} + 1))
quote="${quotes[$random_index]}"

echo "📖 $quote"
"$SPEAK" "$quote"
