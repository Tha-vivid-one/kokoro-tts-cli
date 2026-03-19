#!/usr/bin/env bash
# TTS Interrupt Hook — kills running TTS playback immediately
# Only kills afplay, NOT the warm daemon

killall afplay 2>/dev/null
exit 0
