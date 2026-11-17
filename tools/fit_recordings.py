"""Cuts the downloaded recordings into the game's sound files.
Usage: python tools/fit_recordings.py FOLDER
FOLDER holds mono 48 kHz WAVs named fire, tracks, left, right, move
(convert MP3s first: ffmpeg -i in.mp3 -ac 1 -ar 48000 out.wav).
It also dulls assets/audio/hit_armour.wav into a thud."""
import os
import sys
import wave
import numpy as np

SR = 48000
src = sys.argv[1]


def read(path):
    w = wave.open(path)
    assert w.getframerate() == SR and w.getnchannels() == 1
    return np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(float) / 32768


def write(name, x):
    with wave.open("assets/audio/%s.wav" % name, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
    print("%-14s %.2fs rms %.3f" % (name, len(x) / SR, np.sqrt((x ** 2).mean())))


def loop(x, peak=0.8, fade=0.4):
    """Cross-fades the end into the start so the cut repeats cleanly."""
    k = int(SR * fade)
    t = np.linspace(0, np.pi / 2, k)
    x = np.concatenate([x[:k] * np.sin(t) + x[-k:] * np.cos(t), x[k:-k]])
    return x * peak / np.abs(x).max()


def shot(x, length, peak=0.92):
    start = max(np.argmax(np.abs(x) > 0.04 * np.abs(x).max()) - int(SR * 0.005), 0)
    x = x[start:start + int(SR * length)].copy()
    k = int(SR * length * 0.35)
    x[-k:] *= np.linspace(1, 0, k) ** 2
    return x * peak / np.abs(x).max()


def resample(x, rate):
    """rate < 1 plays slower and lower."""
    n = int(len(x) / rate)
    return np.interp(np.arange(n) * rate, np.arange(len(x)), x)


def lowpass(x, hz):
    f = np.fft.rfft(x)
    freq = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(f / (1 + (freq / hz) ** 4), len(x))


move = read(os.path.join(src, "move.wav"))
cut = move[int(SR * 20):int(SR * 27)]
write("engine_move", loop(cut))
write("engine_idle", loop(lowpass(resample(move[int(SR * 40):int(SR * 45)], 0.72), 2500)))

rattle = read(os.path.join(src, "tracks.wav"))
write("tracks", loop(rattle[int(SR * 0.15):], 0.8, 0.3))
# The same rattle, slowed and roughened, is the sound of a damaged tank.
write("engine_broken", loop(resample(rattle[int(SR * 0.15):], 0.62), 0.8, 0.3))

fire = read(os.path.join(src, "fire.wav"))
seg = fire[int(SR * 30):int(SR * 39)]
seg = np.tanh(seg / (4 * np.sqrt((seg ** 2).mean())))          # lift the quiet roar, tame the pops
write("fire_loop", loop(seg, 0.7, 0.5))

write("mg_shot", shot(read(os.path.join(src, "left.wav")), 0.9))
write("cannon_shot", shot(read(os.path.join(src, "right.wav")), 3.2))

# Armour hit: no recording yet. Take the ring out of the old one: slow it
# down, cut the highs, and let it die away quickly, leaving a heavy thud.
old = read("assets/audio/hit_armour.wav")
thud = lowpass(resample(old, 0.5), 900)[:int(SR * 0.6)]
thud *= np.exp(-np.arange(len(thud)) / (SR * 0.09))
write("hit_armour", thud * 0.9 / np.abs(thud).max())
