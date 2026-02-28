# kokoro-tts-cli

Local text-to-speech that doesn't suck. No API keys, no cloud, no cost.

## The story

I wanted my terminal tools to read output aloud. Tried macOS `say` first — cycled through nine different voices and they were all bad. How are they the same ones from 2015?

Tried Piper (open source, recommended everywhere). It was passable, but could I listen to that for 6 hours straight?

Found [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) on HuggingFace. 54 voices, 82 million parameters, lightweight, **free** and fully local. **SOUNDS LIKE A REAL HUMAN**

This repo wraps it into simple shell scripts so you can use it from the terminal, pipe text into it, or schedule it with cron jobs.

If you think this is too hard to install give your favorite AI the URL and say "Read back when you've set it up"

## Install

```bash
git clone https://github.com/Tha-vivid-one/kokoro-tts-cli.git
cd kokoro-tts-cli
./install.sh
```

Requires Python 3.10-3.12 and Homebrew (for espeak-ng). Python 3.13+ doesn't work yet.

## Usage

```bash
# Basic
./speak.sh "hello world"

# Pipe text
echo "some command output" | ./speak.sh

# Different voice
./speak.sh -v am_adam "male voice"

# Speed up
./speak.sh -s 1.5 "faster"

# Both
./speak.sh -s 2 -v bf_emma "fast british woman"

# Stop playback
./stop.sh
```

## Warm daemon (instant generation)

The first time you run `speak.sh`, Kokoro loads the model from scratch (~5s). If you're using it frequently, the warm daemon keeps the model in memory so generation is near-instant (~1s).

```bash
# Start the daemon (loads model once, stays resident)
./warm.sh

# Now speak.sh uses the daemon automatically
./speak.sh "this was generated in about a second"

# Daemon auto-shuts down after 10 minutes of inactivity
# Or kill it manually:
./stop.sh
```

If the daemon isn't running, `speak.sh` falls back to cold start automatically. You don't need the daemon — it just makes things faster.

Logs are written to `daemon.log` in the repo directory. Check what's happening with `tail daemon.log`.

## Read random quotes aloud

```bash
# From the included sample file
./read-quote.sh

# From your own file
./read-quote.sh ~/path/to/your/quotes.md
```

It parses markdown, skips code blocks and headers, picks a random line, and reads it aloud.

## Schedule it (macOS)

A `cron-example.plist` is included. Edit the path, copy to `~/Library/LaunchAgents/`, and load it:

```bash
cp cron-example.plist ~/Library/LaunchAgents/com.kokoro.read-quote.plist
# Edit the path inside the plist first
launchctl load ~/Library/LaunchAgents/com.kokoro.read-quote.plist
```

Now you get a random quote read aloud at 9:30am and 2pm. No app, no notification, just a voice.

## Use with AI coding tools

The script accepts piped input, so any tool that can run shell commands can use it:

```bash
echo "whatever text to speak" | /path/to/speak.sh
```

Works with any AI assistant, shell script, or automation tool that can pipe to stdout.

## Available voices

54 voices across 8 languages. The English ones:

**American female:** af_heart (default), af_alloy, af_aoede, af_bella, af_jessica, af_kore, af_nicole, af_nova, af_river, af_sarah, af_sky

**American male:** am_adam, am_echo, am_eric, am_fenrir, am_liam, am_michael, am_onyx, am_puck

**British female:** bf_alice, bf_emma, bf_isabella, bf_lily

**British male:** bm_daniel, bm_fable, bm_george, bm_lewis

Listen to all of them: [Kokoro TTS Demo](https://huggingface.co/spaces/hexgrad/Kokoro-TTS)

## How big is it

- Python venv + dependencies: ~850MB (mostly PyTorch)
- Kokoro model + all 54 voices: ~313MB
- Total: ~1.2GB

The model downloads automatically on first run from HuggingFace.

## Credits

- [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) by hexgrad — the actual model doing the work
- Built because Apple ships 28 English TTS voices and most of them are novelty robots
