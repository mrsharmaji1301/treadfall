"""Synthesises every sound in the game with numpy. All original, no samples.
Run: python tools/make_sounds.py   (writes 16-bit mono WAVs to assets/audio)
Replace any file with a recording of the same name to upgrade it."""
import wave
import numpy as np

SR = 44100
rng = np.random.default_rng(1990)


def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


def band(x, lo, hi):
    """Zero-phase band-pass by FFT masking. Circular, so loops stay seamless."""
    f = np.fft.rfft(x)
    freq = np.fft.rfftfreq(len(x), 1 / SR)
    edge = lambda f0, w: 0.5 * (1 + np.tanh((freq - f0) / max(w, 1e-6)))
    mask = edge(lo, lo * 0.15 + 1) * (1 - edge(hi, hi * 0.15 + 1))
    return np.fft.irfft(f * mask, len(x))


def noise(sec):
    return rng.standard_normal(int(SR * sec))


def env(sec, attack, decay):
    t = t_axis(sec)
    return np.minimum(t / max(attack, 1e-4), 1.0) * np.exp(-t / decay)


def save(name, x, peak=0.9):
    x = x / (np.abs(x).max() + 1e-9) * peak
    with wave.open("assets/audio/%s.wav" % name, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def engine():
    """Idling diesel, loopable: firing pulses at 19 Hz over a low drone."""
    sec = 2.0
    t = t_axis(sec)
    x = np.zeros_like(t)
    for k, a in enumerate([1.0, 0.8, 0.55, 0.4, 0.3, 0.2, 0.14, 0.1], 1):
        x += a * np.sin(2 * np.pi * 19 * k * t + rng.uniform(0, 6.28))
    pulse = 0.55 + 0.45 * np.sin(2 * np.pi * 19 * t) ** 2
    rattle = band(noise(sec), 90, 900) * (0.5 + 0.5 * np.sin(2 * np.pi * 9.5 * t) ** 4)
    x = x * pulse + 0.7 * rattle + 0.25 * band(noise(sec), 30, 120)
    save("engine_idle", x, 0.8)


def tracks():
    """Track links clattering over the sprockets plus ground rumble, loopable."""
    sec = 1.5
    n = int(SR * sec)
    x = 0.5 * band(noise(sec), 40, 300)
    for i in range(21):                      # 14 clacks a second
        at = int(i * n / 21 + rng.uniform(-200, 200)) % n
        ln = int(SR * 0.05)
        click = band(noise(0.05), 600, 5000) * np.exp(-np.arange(ln) / (SR * 0.008))
        idx = (at + np.arange(ln)) % n
        x[idx] += click * rng.uniform(0.5, 1.0)
    squeak = 0.08 * np.sin(2 * np.pi * (1900 + 300 * np.sin(2 * np.pi * 2 * t_axis(sec))) * t_axis(sec))
    save("tracks", x + squeak * (band(noise(sec), 1, 6) > 0), 0.8)


def cannon():
    sec = 1.6
    t = t_axis(sec)
    crack = band(noise(sec), 200, 7000) * env(sec, 0.001, 0.05)
    boom = band(noise(sec), 30, 400) * env(sec, 0.004, 0.32)
    thump = np.sin(2 * np.pi * (95 * np.exp(-t * 9) + 38) * t) * env(sec, 0.002, 0.25)
    tail = band(noise(sec), 80, 900) * env(sec, 0.08, 0.5) * 0.25
    save("cannon_shot", 0.8 * crack + 1.2 * boom + 1.3 * thump + tail)


def gun():
    sec = 0.45
    t = t_axis(sec)
    crack = band(noise(sec), 500, 9000) * env(sec, 0.0005, 0.025)
    body = band(noise(sec), 90, 900) * env(sec, 0.002, 0.07)
    thump = np.sin(2 * np.pi * (160 * np.exp(-t * 25) + 60) * t) * env(sec, 0.001, 0.06)
    save("mg_shot", crack + 0.9 * body + 0.8 * thump, 0.8)


def hit_metal():
    sec = 0.7
    t = t_axis(sec)
    x = band(noise(sec), 1500, 9000) * env(sec, 0.0005, 0.012)
    for f, a, d in [(430, 1.0, 0.16), (1130, 0.7, 0.12), (1870, 0.5, 0.09), (2950, 0.35, 0.06), (4210, 0.2, 0.04)]:
        x += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * env(sec, 0.001, d)
    x += 0.8 * band(noise(sec), 60, 300) * env(sec, 0.002, 0.08)
    save("hit_armour", x, 0.85)


def hit_dirt():
    sec = 0.5
    t = t_axis(sec)
    x = band(noise(sec), 60, 1400) * env(sec, 0.002, 0.07)
    x += np.sin(2 * np.pi * (110 * np.exp(-t * 20) + 45) * t) * env(sec, 0.001, 0.07)
    x += 0.3 * band(noise(sec), 2000, 8000) * env(sec, 0.03, 0.12)   # grit falling back
    save("hit_sand", x, 0.7)


def explosion():
    sec = 2.8
    t = t_axis(sec)
    blast = band(noise(sec), 25, 500) * env(sec, 0.004, 0.55)
    crack = band(noise(sec), 300, 6000) * env(sec, 0.001, 0.09)
    sub = np.sin(2 * np.pi * (70 * np.exp(-t * 5) + 28) * t) * env(sec, 0.003, 0.5)
    debris = band(noise(sec), 1200, 7000) * env(sec, 0.25, 0.6) * (band(noise(sec), 3, 30) > 0.2) * 0.25
    save("explosion_tank", 1.3 * blast + 0.7 * crack + 1.4 * sub + debris)


def splash():
    sec = 1.0
    t = t_axis(sec)
    x = band(noise(sec), 500, 6000) * env(sec, 0.03, 0.22)
    x += 0.6 * band(noise(sec), 150, 700) * env(sec, 0.01, 0.12)
    for i in range(9):                                     # bubbles
        f0 = rng.uniform(500, 1500)
        st = rng.uniform(0.1, 0.6)
        tt = np.clip(t - st, 0, None)
        x += 0.15 * np.sin(2 * np.pi * (f0 + 900 * tt) * tt) * np.exp(-tt / 0.03) * (t > st)
    save("water_splash", x, 0.6)


def pickup():
    sec = 0.6
    t = t_axis(sec)
    x = np.zeros_like(t)
    for i, f in enumerate([660, 880, 1320]):
        tt = np.clip(t - i * 0.07, 0, None)
        x += (np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(4 * np.pi * f * tt)) * np.exp(-tt / 0.16) * (t >= i * 0.07)
    save("pickup", x, 0.6)


def alarm():
    sec = 0.7
    t = t_axis(sec)
    f = np.where((t % 0.35) < 0.175, 392.0, 311.0)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.tanh(3 * np.sin(ph)) * np.minimum(t / 0.01, 1) * np.minimum((sec - t) / 0.05, 1)
    save("base_alarm", band(x, 150, 4000), 0.55)


def missile():
    sec = 1.4
    t = t_axis(sec)
    hiss = band(noise(sec), 700, 9000) * (np.minimum(t / 0.05, 1) * np.exp(-t / 0.9))
    roar = band(noise(sec), 80, 700) * env(sec, 0.02, 0.5)
    save("missile_launch", hiss + 0.8 * roar, 0.7)


def mine():
    sec = 0.25
    t = t_axis(sec)
    x = np.sin(2 * np.pi * 1760 * t) * ((t < 0.07) | ((t > 0.12) & (t < 0.19)))
    save("mine_drop", x * np.minimum(t / 0.004, 1), 0.4)


for f in (engine, tracks, cannon, gun, hit_metal, hit_dirt, explosion, splash, pickup, alarm, missile, mine):
    f()


def engine_move():
    """The same diesel under load: faster firing, more growl. Loopable."""
    sec = 2.0
    t = t_axis(sec)
    x = np.zeros_like(t)
    for k, a in enumerate([1.0, 0.9, 0.7, 0.55, 0.45, 0.35, 0.25, 0.18, 0.12], 1):
        x += a * np.sin(2 * np.pi * 31 * k * t + rng.uniform(0, 6.28))
    pulse = 0.6 + 0.4 * np.sin(2 * np.pi * 31 * t) ** 2
    growl = band(noise(sec), 120, 1600) * (0.6 + 0.4 * np.sin(2 * np.pi * 15.5 * t) ** 2)
    save("engine_move", x * pulse + 0.9 * growl + 0.3 * band(noise(sec), 30, 140), 0.8)


def fire_loop():
    """Burning wreck: low roar with random crackles. Loopable."""
    sec = 3.0
    n = int(SR * sec)
    x = band(noise(sec), 60, 700) * (0.7 + 0.3 * band(noise(sec), 0.5, 4) / 0.05).clip(0.3, 1.3)
    for i in range(70):
        at = int(rng.uniform(0, n))
        ln = int(SR * rng.uniform(0.004, 0.02))
        idx = (at + np.arange(ln)) % n
        x[idx] += band(noise(ln / SR + 0.001)[:ln], 1500, 9000)[:ln] * np.exp(-np.arange(ln) / (ln * 0.3)) * rng.uniform(1, 4)
    save("fire_loop", x, 0.6)


def shell_whoosh():
    sec = 0.6
    t = t_axis(sec)
    sweep = np.sin(2 * np.pi * np.cumsum(900 - 700 * t / sec) / SR)
    x = band(noise(sec), 400, 5000) * np.sin(np.pi * t / sec) ** 2 * (0.6 + 0.4 * sweep)
    save("shell_whoosh", x, 0.5)


def hit_wall():
    sec = 0.9
    t = t_axis(sec)
    x = band(noise(sec), 80, 2500) * env(sec, 0.002, 0.09)
    x += np.sin(2 * np.pi * (140 * np.exp(-t * 18) + 50) * t) * env(sec, 0.001, 0.08)
    rubble = band(noise(sec), 700, 6000) * env(sec, 0.08, 0.25) * (band(noise(sec), 8, 60) > 0.0)
    save("hit_wall", x + 0.5 * rubble, 0.75)


for f in (engine_move, fire_loop, shell_whoosh, hit_wall):
    f()
print("done")
