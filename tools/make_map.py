"""Designs the Oasis Crossing map and prints it as level rows.
. sand  W water  T palm  M rock ridge  D dune ridge  # brick  X concrete
S enemy spawn  P player spawn  C base"""
import numpy as np
from collections import deque

W, H = 48, 32
rng = np.random.default_rng(7)
g = np.full((H, W), '.', dtype='<U1')


def blob(cx, cy, rx, ry, ch, wobble=0.35, seed=0):
    r = np.random.default_rng(seed)
    ph = r.random(4) * 6.28
    for y in range(H):
        for x in range(W):
            a = np.arctan2(y - cy, x - cx)
            k = 1 + wobble * (0.5 * np.sin(2 * a + ph[0]) + 0.3 * np.sin(3 * a + ph[1]) + 0.2 * np.sin(5 * a + ph[2]))
            if ((x - cx) / (rx * k)) ** 2 + ((y - cy) / (ry * k)) ** 2 <= 1 and g[y, x] == '.':
                g[y, x] = ch


def stroke(pts, ch, gaps=()):
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = int(max(abs(x1 - x0), abs(y1 - y0))) * 2 + 1
        for i in range(n + 1):
            x = round(x0 + (x1 - x0) * i / n); y = round(y0 + (y1 - y0) * i / n)
            if 0 <= x < W and 0 <= y < H and g[y, x] == '.' and not any(abs(x - gx) <= 1 and abs(y - gy) <= 1 for gx, gy in gaps):
                g[y, x] = ch


# Three different water patches: a big central oasis, a long narrow pool, a small pond.
blob(24, 14, 5.2, 3.4, 'W', 0.45, 1)
blob(8, 19, 2.2, 4.2, 'W', 0.5, 2)
blob(39, 9, 2.6, 1.9, 'W', 0.4, 3)
blob(41, 23, 1.6, 1.3, 'W', 0.3, 4)

# Dune ridges and rock ridges that split the map into three lanes, with gaps.
stroke([(13, 3), (14, 9), (16, 13)], 'D')
stroke([(15, 18), (14, 23), (16, 27)], 'D')
stroke([(33, 4), (32, 8)], 'D')
stroke([(33, 18), (35, 22), (34, 27)], 'D')
stroke([(3, 10), (7, 11)], 'M')
stroke([(19, 6), (23, 5), (27, 7)], 'M')
stroke([(42, 15), (46, 16)], 'M')
stroke([(21, 22), (27, 22)], 'M', gaps=[(24, 22)])
stroke([(2, 26), (5, 27)], 'M')

# Palms: rings round the water plus separate groves, never evenly spaced.
for y in range(H):
    for x in range(W):
        if g[y, x] != '.':
            continue
        near = sum(g[yy, xx] == 'W' for yy in range(max(0, y - 2), min(H, y + 3)) for xx in range(max(0, x - 2), min(W, x + 3)))
        if 0 < near <= 7 and rng.random() < 0.2:
            g[y, x] = 'T'
for cx, cy, n, spread in [(5, 5, 7, 2.2), (44, 4, 5, 1.8), (28, 27, 6, 2.0), (10, 28, 4, 1.6), (38, 16, 4, 1.5), (20, 10, 3, 1.2), (45, 28, 5, 1.8)]:
    for _ in range(n):
        x = int(round(cx + rng.normal(0, spread))); y = int(round(cy + rng.normal(0, spread)))
        if 0 <= x < W and 0 <= y < H and g[y, x] == '.':
            g[y, x] = 'T'

# Base at the bottom centre behind brick walls, ruins in the lanes.
cx, cy = 24, 29
for y in range(H):
    for x in range(W):
        if abs(x - cx) <= 3 and abs(y - cy) <= 2:
            g[y, x] = '.'
for x in range(cx - 2, cx + 3):
    g[cy - 2, x] = '#'
for y in range(cy - 2, cy + 2):
    g[y, cx - 2] = '#'; g[y, cx + 2] = '#'
g[cy, cx] = 'C'
g[cy, cx - 5] = 'P'
for x0, y0, w, h in [(6, 15, 3, 1), (30, 12, 1, 3), (40, 19, 3, 1), (18, 26, 1, 3), (24, 8, 3, 1), (36, 26, 2, 2)]:
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            if g[y, x] == '.':
                g[y, x] = '#'
for x, y in [(11, 14), (37, 13), (24, 19), (25, 19)]:
    if g[y, x] == '.':
        g[y, x] = 'X'
spawns = [(6, 1), (24, 1), (42, 1)]
for x, y in spawns:
    for yy in range(0, 4):
        for xx in range(x - 2, x + 3):
            if g[yy, xx] in 'TMD#X':
                g[yy, xx] = '.'
    g[y, x] = 'S'
for yy in range(cy - 1, cy + 3):
    for xx in range(cx - 7, cx - 3):
        if g[yy, xx] in 'TMDX#W':
            g[yy, xx] = '.'
g[cy, cx - 5] = 'P'

# Every spawn must reach the base without breaking anything unbreakable.
def reach(start):
    seen = {start}; q = deque([start])
    while q:
        x, y = q.popleft()
        if (x, y) == (cx, cy):
            return True
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < W and 0 <= ny < H and (nx, ny) not in seen and g[ny, nx] in '.W#SPC':
                seen.add((nx, ny)); q.append((nx, ny))
    return False
assert all(reach(s) for s in spawns) and reach((cx - 5, cy)), "map is blocked"

rows = ["".join(r) for r in g]
print("\n".join(rows))
open("tools/oasis_rows.txt", "w").write("\n".join(rows))
from PIL import Image
col = {'.': (214, 184, 132), 'W': (60, 140, 160), 'T': (60, 120, 50), 'M': (110, 95, 80), 'D': (240, 215, 160), '#': (150, 100, 60), 'X': (130, 130, 130), 'S': (220, 40, 40), 'P': (40, 220, 60), 'C': (255, 255, 255)}
im = Image.new('RGB', (W, H))
for y in range(H):
    for x in range(W):
        im.putpixel((x, y), col[g[y, x]])
im.resize((W * 16, H * 16), Image.NEAREST).save('map_preview.png')
