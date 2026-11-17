"""Fits recorded or generated sound files into the game.
Usage: python tools/import_sounds.py FOLDER
Every .wav under FOLDER is mixed to mono 16-bit, levelled, and written to
assets/audio/ under the same name. Loops get their end cross-faded into
their start, so they repeat without a click."""
import glob
import os
import sys
import wave
import numpy as np

LOOPS = {"engine_idle", "engine_move", "tracks", "fire_loop"}


def read(path):
    w = wave.open(path)
    n, ch, sw, sr = w.getnframes(), w.getnchannels(), w.getsampwidth(), w.getframerate()
    raw = w.readframes(n)
    if sw == 2:
        x = np.frombuffer(raw, np.int16).astype(float) / 32768
    elif sw == 3:
        b = np.frombuffer(raw, np.uint8).reshape(-1, 3).astype(np.int32)
        x = ((b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)) << 8 >> 8) / 8388608.0
    elif sw == 4:
        x = np.frombuffer(raw, np.int32).astype(float) / 2 ** 31
    else:
        x = (np.frombuffer(raw, np.uint8).astype(float) - 128) / 128
    return x.reshape(-1, ch).mean(1), sr


def write(path, x, sr):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())


for src in sorted(glob.glob(os.path.join(sys.argv[1], "**", "*.wav"), recursive=True)):
    name = os.path.splitext(os.path.basename(src))[0]
    x, sr = read(src)
    x = x - x.mean()
    if name in LOOPS:
        k = int(sr * 0.3)                       # equal-power cross-fade
        t = np.linspace(0, np.pi / 2, k)
        head = x[:k] * np.sin(t) + x[-k:] * np.cos(t)
        x = np.concatenate([head, x[k:-k]])
        x *= 0.8 / np.abs(x).max()
    else:
        fade = int(sr * 0.01)
        x[-fade:] *= np.linspace(1, 0, fade)
        x *= 0.92 / np.abs(x).max()
    write("assets/audio/%s.wav" % name, x, sr)
    print("%-16s %.2fs" % (name, len(x) / sr))
