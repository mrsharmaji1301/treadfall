"""Generates the game's textures (sand, camouflage, tracks) with numpy.
All output is original and tileable. Run: python tools/make_textures.py"""
import numpy as np
from PIL import Image, ImageDraw

rng = np.random.default_rng(1990)


def noise(n, lo, hi, aniso=None):
    """Tileable band-limited noise in 0..1. lo/hi are cycles per tile."""
    w = rng.standard_normal((n, n))
    f = np.fft.fft2(w)
    ky = np.fft.fftfreq(n)[:, None] * n
    kx = np.fft.fftfreq(n)[None, :] * n
    if aniso:  # ripples: narrow band along x, limited spread along y
        cx, sx, sy = aniso
        mask = np.exp(-((np.abs(kx) - cx) ** 2) / (2 * sx ** 2) - (ky ** 2) / (2 * sy ** 2))
    else:
        k = np.sqrt(kx ** 2 + ky ** 2)
        mask = ((k >= lo) & (k <= hi)) / np.maximum(k, 1.0)
    out = np.real(np.fft.ifft2(f * mask))
    out -= out.min()
    return out / out.max()


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def normal_map(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    nz = np.ones_like(h)
    l = np.sqrt(dx * dx + dy * dy + nz * nz)
    n = np.stack([-dx / l, -dy / l, nz / l], -1)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def save(arr, path):
    Image.fromarray(np.clip(arr * 255, 0, 255).astype(np.uint8)).save(path)


def mix(a, b, t):
    return a + (b - a) * t[..., None]


def sand(n=1024):
    grain = rng.random((n, n))
    grain = (grain + np.roll(grain, 1, 0) + np.roll(grain, 1, 1)) / 3
    mottle = noise(n, 2, 9)
    clumps = noise(n, 10, 40)
    ripples = noise(n, 0, 0, aniso=(46, 7, 9))
    patch = smooth(noise(n, 1, 4), 0.42, 0.62)
    pebbles = smooth(noise(n, 60, 140), 0.78, 0.86)
    base = np.array([0.71, 0.60, 0.44])
    warm = np.array([0.62, 0.49, 0.33])
    pale = np.array([0.80, 0.71, 0.56])
    col = np.broadcast_to(base, (n, n, 3)).copy()
    col = mix(col, warm, smooth(mottle, 0.35, 0.8) * 0.55)
    col = mix(col, pale, smooth(clumps, 0.5, 0.9) * 0.3)
    col *= (0.93 + 0.14 * grain)[..., None]
    col *= (1.0 - 0.10 * patch * (1 - ripples))[..., None]
    col = mix(col, np.array([0.36, 0.29, 0.21]), pebbles * 0.7)
    save(col, "assets/terrain/sand_albedo.png")
    h = 0.30 * grain + 0.55 * patch * ripples + 0.25 * clumps + 0.5 * pebbles
    Image.fromarray(normal_map(h, 9.0)).save("assets/terrain/sand_normal.png")


def camo(n=1024):
    tan = np.array([0.66, 0.55, 0.42])
    brown = np.array([0.43, 0.32, 0.25])
    green = np.array([0.42, 0.44, 0.32])
    a = noise(n, 1, 5)
    b = noise(n, 1, 5)
    col = np.broadcast_to(tan, (n, n, 3)).copy()
    col = mix(col, green, smooth(b, 0.56, 0.60))
    col = mix(col, brown, smooth(a, 0.58, 0.62))
    dust = smooth(noise(n, 3, 14), 0.4, 0.85)
    col = mix(col, np.array([0.74, 0.66, 0.53]), dust * 0.45)
    stain = smooth(noise(n, 8, 60), 0.55, 0.95)
    col *= (1.0 - 0.28 * stain)[..., None]
    col *= (0.95 + 0.1 * rng.random((n, n)))[..., None]
    chips = smooth(noise(n, 70, 200), 0.80, 0.84)
    col = mix(col, np.array([0.2, 0.18, 0.16]), chips * 0.85)
    save(col, "assets/tank/camo_albedo.png")
    h = 0.5 * noise(n, 30, 160) + 0.3 * stain - 0.6 * chips
    Image.fromarray(normal_map(h, 5.0)).save("assets/tank/camo_normal.png")


def track(n=128):
    v, u = np.mgrid[0:n, 0:n]
    phase = (u + np.abs(v - n / 2) * 0.6) % 32
    ridge = smooth(phase, 0, 3) * (1 - smooth(phase, 17, 20))
    edge = (np.abs(v - n / 2) > n * 0.44).astype(float)
    val = 0.07 + 0.2 * ridge + 0.05 * edge
    col = val[..., None] * np.array([1.0, 0.93, 0.85])
    col = mix(col, np.array([0.45, 0.37, 0.27]), (1 - ridge) * 0.35 * rng.random((n, n)))
    save(col, "assets/tank/track_albedo.png")
    Image.fromarray(normal_map(ridge, 3.0)).save("assets/tank/track_normal.png")


sand()
camo()
track()


def rgba(col, alpha, path):
    out = np.concatenate([np.clip(col, 0, 1), np.clip(alpha, 0, 1)[..., None]], -1)
    Image.fromarray((out * 255).astype(np.uint8), "RGBA").save(path)


def frond(w=256, h=512, k=4):
    """Palm frond, tip at the top, stem at the bottom. Alpha cut-out."""
    W, H = w * k, h * k
    col = Image.new("RGB", (W, H), (70, 96, 40))
    mask = Image.new("L", (W, H), 0)
    dc, dm = ImageDraw.Draw(col), ImageDraw.Draw(mask)
    cx = W / 2
    r = np.random.default_rng(7)
    n = 46
    for i in range(n):
        t = i / (n - 1)                      # 0 stem .. 1 tip
        y = H * (0.97 - 0.93 * t)
        length = W * 0.47 * (0.35 + 0.65 * np.sin(np.pi * min(t * 1.15 + 0.08, 1.0)) ** 0.7)
        length *= r.uniform(0.86, 1.0)
        for side in (-1, 1):
            ang = np.radians(r.uniform(48, 60) - 30 * t)   # leaflets sweep toward the tip
            ex = cx + side * length * np.cos(ang)
            ey = y - length * np.sin(ang) + r.uniform(-6, 6) * k
            half = k * r.uniform(3.2, 4.6)
            mx, my = (cx + ex) / 2, (y + ey) / 2
            px, py = -(ey - y), (ex - cx)
            pl = max((px * px + py * py) ** 0.5, 1e-6)
            px, py = px / pl * half, py / pl * half
            poly = [(cx, y + half), (mx + px, my + py), (ex, ey), (mx - px, my - py), (cx, y - half)]
            g = r.uniform(0.8, 1.15)
            shade = (int(58 * g + 40 * t), int(98 * g + 22 * t), int(38 * g))
            dc.polygon(poly, fill=shade)
            dm.polygon(poly, fill=255)
            dc.line([(cx, y), (ex, ey)], fill=(int(96 * g), int(128 * g), int(60 * g)), width=k)
    rib = 3 * k
    dc.polygon([(cx - rib, H), (cx + rib, H), (cx + k, H * 0.04), (cx - k, H * 0.04)], fill=(128, 132, 72))
    dm.polygon([(cx - rib, H), (cx + rib, H), (cx + k, H * 0.04), (cx - k, H * 0.04)], fill=255)
    col = np.asarray(col.resize((w, h), Image.LANCZOS)) / 255.0
    a = np.asarray(mask.resize((w, h), Image.LANCZOS)) / 255.0
    col = col * (0.9 + 0.2 * rng.random((h, w)))[..., None]
    rgba(col, a, "assets/nature/palm_frond.png")


def tuft(n=128, k=4):
    N = n * k
    col = Image.new("RGB", (N, N), (104, 112, 58))
    mask = Image.new("L", (N, N), 0)
    dc, dm = ImageDraw.Draw(col), ImageDraw.Draw(mask)
    r = np.random.default_rng(11)
    for i in range(46):
        bx = N * r.uniform(0.38, 0.62)
        lean = r.uniform(-0.55, 0.55)
        ht = N * r.uniform(0.45, 0.96)
        wd = k * r.uniform(1.6, 3.0)
        pts_l, pts_r = [], []
        for s in range(7):
            t = s / 6
            x = bx + lean * ht * t * (0.4 + 0.6 * t)
            y = N - ht * t
            ww = wd * (1 - t)
            pts_l.append((x - ww, y)); pts_r.append((x + ww, y))
        g = r.uniform(0.75, 1.2)
        dc.polygon(pts_l + pts_r[::-1], fill=(int(96 * g), int(112 * g), int(50 * g)))
        dm.polygon(pts_l + pts_r[::-1], fill=255)
    col = np.asarray(col.resize((n, n), Image.LANCZOS)) / 255.0
    a = np.asarray(mask.resize((n, n), Image.LANCZOS)) / 255.0
    yy = np.linspace(1.15, 0.7, n)[:, None, None]      # yellow tips, dark roots
    rgba(col * yy * np.array([1.0, 0.96, 0.85]), a, "assets/nature/grass_tuft.png")


def bark(n=256):
    v = np.arange(n)[:, None] / n
    wob = noise(n, 1, 6)
    rings = (v * 14 + wob * 1.2) % 1.0
    scar = smooth(rings, 0.0, 0.12) * (1 - smooth(rings, 0.7, 1.0))
    fibre = noise(n, 0, 0, aniso=(40, 12, 3))
    h = 0.6 * scar + 0.25 * fibre + 0.15 * noise(n, 20, 90)
    base = np.array([0.42, 0.34, 0.26])
    col = np.broadcast_to(base, (n, n, 3)) * (0.55 + 0.6 * h)[..., None]
    col = mix(col, np.array([0.55, 0.5, 0.42]), smooth(noise(n, 2, 8), 0.5, 0.9) * 0.4)
    save(col, "assets/nature/palm_bark.png")
    Image.fromarray(normal_map(h, 6.0)).save("assets/nature/palm_bark_normal.png")


def rock(n=512):
    big = noise(n, 1, 5)
    mid = noise(n, 6, 30)
    fine = noise(n, 40, 180)
    strata = 0.5 + 0.5 * np.sin((np.arange(n)[:, None] / n * 9 + big * 2.5) * 2 * np.pi)
    crack = 1 - smooth(np.abs(noise(n, 2, 7) - 0.5), 0.0, 0.012)
    h = 0.45 * mid + 0.2 * fine + 0.25 * strata - 0.7 * crack
    col = np.broadcast_to(np.array([0.50, 0.42, 0.33]), (n, n, 3)).copy()
    col = mix(col, np.array([0.62, 0.54, 0.42]), smooth(strata, 0.5, 1.0) * 0.5)
    col = mix(col, np.array([0.36, 0.31, 0.27]), smooth(big, 0.45, 0.8) * 0.6)
    col *= (0.82 + 0.3 * mid)[..., None]
    col *= (0.92 + 0.16 * fine)[..., None]
    col = mix(col, np.array([0.2, 0.17, 0.14]), crack * 0.4)
    save(col, "assets/nature/rock_albedo.png")
    Image.fromarray(normal_map(h, 7.0)).save("assets/nature/rock_normal.png")


def water(n=512):
    h = 0.6 * noise(n, 3, 10) + 0.4 * noise(n, 10, 34)
    Image.fromarray(normal_map(h, 26.0)).save("assets/water/water_normal.png")


def rut(w=128, h=64):
    """Track print: u runs along the track, v across it."""
    u = np.arange(w)[None, :] / (w - 1)
    v = np.arange(h)[:, None] / (h - 1)
    across = smooth(v, 0.0, 0.22) * (1 - smooth(v, 0.78, 1.0))
    along = smooth(u, 0.0, 0.2) * (1 - smooth(u, 0.8, 1.0))
    cleat = 0.5 + 0.5 * np.sin((u * 5 + np.abs(v - 0.5) * 0.9) * 2 * np.pi)
    edge = 1 - smooth(np.abs(v - 0.5), 0.2, 0.42)       # deeper along both edges
    a = across * along * (0.55 + 0.2 * cleat + 0.25 * (1 - edge))
    a *= 0.8 + 0.2 * rng.random((h, w))
    col = np.broadcast_to(np.array([0.34, 0.26, 0.17]), (h, w, 3)) * (0.85 + 0.3 * cleat)[..., None]
    rgba(col, a, "assets/terrain/track_rut.png")


frond()
tuft()
bark()
rock()
water()
rut()
print("done")


def damage(n=512):
    """Battle damage for tank paint: three masks that grow with each stage,
    plus the soot, bare metal and rust that show through."""
    burn = noise(n, 2, 8)
    pock = noise(n, 18, 50)
    scratch = noise(n, 0, 0, aniso=(30, 10, 2))
    for stage, (b, p) in enumerate([(0.70, 0.86), (0.58, 0.80), (0.46, 0.74)], 1):
        m = np.maximum(smooth(burn, b, b + 0.1), smooth(pock, p, p + 0.03))
        m = np.maximum(m, smooth(scratch, 0.82 - 0.05 * stage, 0.9) * 0.8)
        save(m, "assets/tank/damage_mask_%d.png" % stage)
    soot = np.broadcast_to(np.array([0.085, 0.075, 0.07]), (n, n, 3)).copy()
    soot = mix(soot, np.array([0.33, 0.17, 0.08]), smooth(noise(n, 6, 30), 0.55, 0.8) * 0.6)
    core = smooth(pock, 0.9, 0.93)
    soot = mix(soot, np.array([0.5, 0.5, 0.52]), core)
    soot *= (0.85 + 0.3 * rng.random((n, n)))[..., None]
    save(soot, "assets/tank/damage_albedo.png")
    h = -1.2 * smooth(pock, 0.78, 0.92) - 0.5 * smooth(burn, 0.5, 0.8) + 0.3 * noise(n, 40, 120)
    Image.fromarray(normal_map(h, 9.0)).save("assets/tank/damage_normal.png")


damage()
