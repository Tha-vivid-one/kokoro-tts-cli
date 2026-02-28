#!/usr/bin/env python3
"""Kokoro TTS daemon — keeps the model warm in memory, serves requests over a Unix socket."""

import json
import os
import signal
import socket
import sys
import threading
import time
import warnings

warnings.filterwarnings("ignore")

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SOCKET_PATH = "/tmp/kokoro-daemon.sock"
PID_FILE = "/tmp/kokoro-daemon.pid"
LOG_FILE = os.path.join(SCRIPT_DIR, "daemon.log")
IDLE_TIMEOUT = 600  # 10 minutes with no requests → auto-shutdown
SAMPLE_RATE = 24000

# Global state
pipeline = None
last_request_time = time.time()


def log(msg):
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")


def load_model():
    global pipeline
    t0 = time.time()
    log("Loading model...")
    from kokoro import KPipeline
    pipeline = KPipeline(lang_code="a")
    log(f"Model loaded in {time.time() - t0:.1f}s")


def generate_audio(text, voice, output_path):
    import numpy as np
    import soundfile as sf

    generator = pipeline(text, voice=voice)
    audio_chunks = []
    for _gs, _ps, audio in generator:
        audio_chunks.append(audio)
    sf.write(output_path, np.concatenate(audio_chunks), SAMPLE_RATE)


def handle_client(conn):
    global last_request_time
    last_request_time = time.time()

    try:
        data = b""
        while True:
            chunk = conn.recv(4096)
            if not chunk:
                break
            data += chunk

        request = json.loads(data.decode("utf-8"))
        text = request["text"]
        voice = request.get("voice", "af_heart")
        output_path = request["output"]

        t0 = time.time()
        log(f"Generating: \"{text[:50]}...\" voice={voice}")
        generate_audio(text, voice, output_path)
        gen_time = time.time() - t0
        log(f"Generated in {gen_time:.2f}s → {output_path}")
        conn.sendall(b"ok")
    except Exception as e:
        log(f"Error: {e}")
        try:
            conn.sendall(f"error: {e}".encode("utf-8"))
        except OSError:
            pass
    finally:
        conn.close()


def idle_watchdog():
    """Shut down the daemon after IDLE_TIMEOUT seconds of inactivity."""
    while True:
        time.sleep(30)
        if time.time() - last_request_time > IDLE_TIMEOUT:
            log("Idle timeout — shutting down")
            cleanup()
            os._exit(0)


def cleanup():
    try:
        os.unlink(SOCKET_PATH)
    except FileNotFoundError:
        pass
    try:
        os.unlink(PID_FILE)
    except FileNotFoundError:
        pass


def signal_handler(_sig, _frame):
    cleanup()
    sys.exit(0)


def main():
    cleanup()

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))

    load_model()

    watchdog = threading.Thread(target=idle_watchdog, daemon=True)
    watchdog.start()

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCKET_PATH)
    server.listen(1)
    os.chmod(SOCKET_PATH, 0o600)

    log(f"Daemon ready (PID {os.getpid()}), idle timeout {IDLE_TIMEOUT}s")
    print("ready", flush=True)

    while True:
        conn, _ = server.accept()
        handle_client(conn)


if __name__ == "__main__":
    main()
