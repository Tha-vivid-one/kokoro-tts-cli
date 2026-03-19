#!/bin/bash
# Install Kokoro Menu as a login item
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST="$SCRIPT_DIR/com.kokoro.menu.plist"
DEST="$HOME/Library/LaunchAgents/com.kokoro.menu.plist"

# Unload if already loaded
launchctl unload "$DEST" 2>/dev/null

# Copy and load
cp "$PLIST" "$DEST"
launchctl load "$DEST"

echo "Kokoro Menu installed and running. It will auto-start on login."
echo "To uninstall: launchctl unload ~/Library/LaunchAgents/com.kokoro.menu.plist && rm ~/Library/LaunchAgents/com.kokoro.menu.plist"
