#!/usr/bin/env bash
# TTS Session End Hook — kill playback on session exit
# Does NOT kill the warm daemon (it auto-shuts down after 10 min idle)

killall afplay 2>/dev/null
exit 0
