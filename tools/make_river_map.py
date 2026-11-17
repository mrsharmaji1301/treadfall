"""Designs the Twin Banks map and writes it into world/levels.gd as RIVER.
A river with fords and an island splits the map. South bank: the player's
Command Centre. North bank: the enemy's. Three roads join them, each guarded
on both banks by a watch tower, a gun turret and an artillery post, with two
last-line guns in front of each Command Centre. Jungle fills the ground
between the roads, with loot hidden inside.

. sand  , road  W shallow water  R deep water  T palm  M rock  D dune
# brick  X concrete  S enemy spawn  P player spawn  C Command Centre
E enemy Command Centre  1 tower  2 turret  3 artillery  4 last-line gun
L hidden loot"""
import sys
import numpy as np
from collections import deque

W, H = 128, 84
rng = np.random.default_rng(23)
g = np.full((H, W), '.', dtype='<U1')
ROAD_FORDS = [22, 64, 106]
FORDS = ROAD_FORDS + [43]
ISLE = 86
BASE = (64, 79)
ENEMY = (64, 5)


def river_y(x):
    return 42 + 4.5 * np.sin(2 * np.pi * x / 100 + 0.9) + 1.6 * np.sin(x * 0.23 + 2)


def inside(x, y):
    return 0 <= x < W and 0 <= y < H


def blob(cx, cy, rx, ry, ch, wobble=0.35, seed=0):
    r = np.random.default_rng(seed)
    ph = r.random(4) * 6.28
    for y in range(H):
        for x in range(W):
            a = np.arctan2(y - cy, x - cx)
            k = 1 + wobble * (0.5 * np.sin(2 * a + ph[0]) + 0.3 * np.sin(3 * a + ph[1]) + 0.2 * np.sin(5 * a + ph[2]))
            if ((x - cx) / (rx * k)) ** 2 + ((y - cy) / (ry * k)) ** 2 <= 1 and g[y, x] == '.':
                g[y, x] = ch


def stroke(pts, ch, only='.', wide=False):
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = int(max(abs(x1 - x0), abs(y1 - y0))) * 2 + 1
        for i in range(n + 1):
            x = round(x0 + (x1 - x0) * i / n); y = round(y0 + (y1 - y0) * i / n)
            for dx, dy in ([(0, 0), (1, 0), (0, 1), (1, 1)] if wide else [(0, 0)]):
                if inside(x + dx, y + dy) and g[y + dy, x + dx] in only:
                    g[y + dy, x + dx] = ch


# ---- river
for x in range(W):
    cy = river_y(x + 0.5)
    near_isle = max(0.0, 1 - abs(x + 0.5 - ISLE) / 6.0)
    hw = 3.8 + 0.6 * np.sin(x * 0.17) + 2.2 * near_isle
    ford = any(abs(x - f) <= 2 for f in FORDS)
    for y in range(H):
        dy = y + 0.5 - cy
        if abs(dy) > hw:
            continue
        g[y, x] = 'W'
        if near_isle > 0.35:
            if abs(dy) < 1.3 and abs(x + 0.5 - ISLE) < 3.6:
                g[y, x] = '.'
            elif -hw + 1.0 < dy < -1.6:
                g[y, x] = 'R'
        elif not ford and abs(dy) <= 1.2:
            g[y, x] = 'R'

# ---- roads: three lanes base to base, and one cross track on each bank
lanes = [
    [(64, 76), (44, 74), (27, 66), (22, 55), (22, 49), (22, 35), (25, 24), (41, 12), (64, 8)],
    [(64, 76), (62, 63), (66, 53), (64, 48), (64, 36), (62, 30), (66, 20), (64, 8)],
    [(64, 76), (85, 74), (101, 66), (106, 55), (106, 49), (106, 35), (103, 24), (88, 12), (64, 8)],
]
cross = [[(22, 58), (43, 61), (62, 62), (85, 60), (106, 57)],
         [(23, 27), (44, 23), (64, 24), (86, 22), (104, 26)]]
for pts in lanes + cross:
    stroke(pts, ',', wide=True)
road = np.argwhere(g == ',')


def road_dist(x, y):
    return np.sqrt(((road[:, 1] - x) ** 2 + (road[:, 0] - y) ** 2).min())


# ---- oases and ponds, set back from the roads
for i, (cx, cy, rx, ry) in enumerate([(40, 30, 5.0, 3.2), (84, 31, 4.2, 2.8), (118, 22, 2.4, 1.8),
        (8, 16, 2.6, 2.0), (50, 16, 2.2, 1.6), (36, 50, 4.2, 3.0), (88, 49, 5.0, 3.4),
        (8, 64, 2.4, 3.0), (118, 68, 2.8, 2.0), (76, 67, 2.0, 1.5), (12, 34, 2.2, 1.6)]):
    blob(cx, cy, rx, ry, 'W', 0.42, i + 1)

# ---- defences along each lane, on both banks
defences = []


def place(x, y, ch):
    x = int(round(x)); y = int(round(y))
    for yy in range(y - 1, y + 2):
        for xx in range(x - 1, x + 2):
            if inside(xx, yy) and g[yy, xx] in 'TMD#XW':
                g[yy, xx] = '.'
    g[y, x] = ch
    defences.append((x, y, ch))


for li, pts in enumerate(lanes):
    dense = []
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        for i in range(40):
            dense.append((x0 + (x1 - x0) * i / 40, y0 + (y1 - y0) * i / 40))
    for south in (True, False):
        walk = dense if not south else dense[::-1]   # start from the far base, end at ours
        for dist, ch in ((6.5, '1'), (14, '2'), (23, '3')):
            best = None
            for x, y in dense:
                d = (y - river_y(x)) * (1 if south else -1)
                if d >= dist and (best is None or d < best[2]):
                    best = (x, y, d)
            side = 3 if (li + (0 if south else 1)) % 2 == 0 else -3
            place(best[0] + side, best[1], ch)
for x, y in [(58, 71), (70, 71), (58, 13), (70, 13)]:
    place(x, y, '4')

# ---- ridges
def free(x, y, gap=2.5):
    return g[y, x] == '.' and road_dist(x, y) >= gap and all(abs(x - dx) > 2 or abs(y - dy) > 2 for dx, dy, _ in defences)


for pts, ch in [([(33, 16), (36, 19), (35, 22)], 'M'), ([(52, 26), (55, 31), (53, 35)], 'M'),
                ([(76, 14), (79, 17)], 'M'), ([(94, 30), (97, 34)], 'M'), ([(110, 8), (116, 10)], 'M'),
                ([(4, 28), (9, 30)], 'M'), ([(12, 6), (16, 9)], 'M'), ([(74, 36), (78, 34)], 'M'),
                ([(117, 34), (122, 36)], 'M'), ([(30, 5), (34, 7)], 'M'), ([(96, 4), (100, 7)], 'M'),
                ([(33, 55), (35, 58)], 'D'), ([(52, 68), (55, 71)], 'D'), ([(75, 55), (78, 52)], 'D'),
                ([(93, 70), (97, 72)], 'D'), ([(112, 60), (117, 62)], 'D'), ([(4, 54), (9, 56)], 'D'),
                ([(14, 74), (18, 78)], 'M'), ([(110, 76), (114, 80)], 'M'), ([(48, 52), (50, 56)], 'M'),
                ([(12, 46), (15, 48)], 'D'), ([(116, 48), (120, 50)], 'D')]:
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = int(max(abs(x1 - x0), abs(y1 - y0))) * 2 + 1
        for i in range(n + 1):
            x = round(x0 + (x1 - x0) * i / n); y = round(y0 + (y1 - y0) * i / n)
            if inside(x, y) and free(x, y):
                g[y, x] = ch

# ---- jungle: clumps of palms that wall off the ground between the roads
def value_noise(cell, seed):
    r = np.random.default_rng(seed)
    gw, gh = W // cell + 2, H // cell + 2
    grid = r.random((gh, gw))
    out = np.zeros((H, W))
    for y in range(H):
        for x in range(W):
            fx, fy = x / cell, y / cell
            i, j = int(fx), int(fy)
            tx, ty = fx - i, fy - j
            tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
            out[y, x] = (grid[j, i] * (1 - tx) + grid[j, i + 1] * tx) * (1 - ty) + (grid[j + 1, i] * (1 - tx) + grid[j + 1, i + 1] * tx) * ty
    return out


noise = 0.65 * value_noise(7, 1) + 0.35 * value_noise(3, 2)
for y in range(H):
    for x in range(W):
        if g[y, x] != '.':
            continue
        if abs(x - BASE[0]) < 11 and abs(y - BASE[1]) < 9:
            continue
        if abs(x - ENEMY[0]) < 11 and abs(y - ENEMY[1]) < 9:
            continue
        rd = road_dist(x, y)
        if rd < 2.2 or any(abs(x - dx) <= 2 and abs(y - dy) <= 2 for dx, dy, _ in defences):
            continue
        north = y < river_y(x)
        by_river = abs(y + 0.5 - river_y(x + 0.5)) < 6.5
        level = 0.56 if not north else 0.6        # the south bank is the greener one
        if by_river:
            level += 0.1
        if noise[y, x] > level - min(rd, 8) * 0.008:
            g[y, x] = 'T'
# rings round the oases
for y in range(H):
    for x in range(W):
        if g[y, x] == '.':
            box = g[max(0, y - 2):y + 3, max(0, x - 2):x + 3]
            near = int(np.sum(box == 'W'))
            if 0 < near <= 8 and abs(y + 0.5 - river_y(x + 0.5)) > 8 and road_dist(x, y) > 2 and rng.random() < 0.3:
                g[y, x] = 'T'
# island palms
for x in (84, 87, 88):
    yy = int(river_y(x + 0.5))
    if g[yy, x] == '.':
        g[yy, x] = 'T'

# ---- loot hidden in the thick of the jungle, reached by one narrow gap
loot = []
cands = []
for y in range(3, H - 3):
    for x in range(3, W - 3):
        if g[y, x] == 'T':
            box = g[y - 2:y + 3, x - 2:x + 3]
            if np.sum(box == 'T') >= 17:
                cands.append((int(np.sum(box == 'T')), x, y))
cands.sort(reverse=True)
for _, x, y in cands:
    if all(abs(x - lx) + abs(y - ly) >= 16 for lx, ly in loot) and len(loot) < 14:
        loot.append((x, y))
def flood(start):
    seen = {start}; q = deque([start])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if inside(nx, ny) and (nx, ny) not in seen and g[ny, nx] in '.,WD#SPCEL':
                seen.add((nx, ny)); q.append((nx, ny))
    return seen


def connect(sx, sy):
    """Cuts the shortest gap through the palms from a spot to open ground."""
    open_ground = flood((BASE[0], BASE[1] - 4))
    if (sx, sy) in open_ground and g[sy, sx] != 'T':
        return
    prev = {(sx, sy): None}
    q = deque([(sx, sy)])
    end = None
    while q:
        x, y = q.popleft()
        if (x, y) in open_ground:
            end = (x, y)
            break
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if inside(nx, ny) and (nx, ny) not in prev and g[ny, nx] in 'T.,WD':
                prev[(nx, ny)] = (x, y)
                q.append((nx, ny))
    assert end is not None, "no way to open ground"
    while end is not None:
        if g[end[1], end[0]] == 'T':
            g[end[1], end[0]] = '.'
        end = prev[end]


for lx, ly in loot:
    connect(lx, ly)
    g[ly, lx] = 'L'
connect(ISLE, int(river_y(ISLE + 0.5)))

# ---- ruins for cover
ruins = [(30, 44, 3, 1), (72, 46, 1, 3), (96, 44, 2, 2), (50, 40, 3, 1), (116, 42, 1, 3),
         (14, 60, 3, 1), (90, 62, 2, 1), (40, 26, 1, 3), (72, 26, 3, 1), (112, 30, 1, 2),
         (48, 66, 2, 1), (80, 18, 2, 1), (16, 20, 1, 3), (100, 14, 3, 1)]
for f in ROAD_FORDS:
    cy = int(river_y(f + 0.5))
    ruins += [(f - 5, cy - 8, 2, 1), (f + 4, cy + 7, 2, 1)]
for x0, y0, w, h in ruins:
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            if inside(x, y) and g[y, x] == '.':
                g[y, x] = '#'
for x, y in [(18, 44), (56, 38), (70, 46), (112, 44), (30, 52), (92, 38), (60, 56), (67, 28)]:
    if g[y, x] == '.':
        g[y, x] = 'X'

# ---- the two Command Centres behind brick walls
for (cx, cy), ch, gate in ((BASE, 'C', -1), (ENEMY, 'E', 1)):
    for y in range(cy - 3, cy + 4):
        for x in range(cx - 4, cx + 5):
            if inside(x, y) and g[y, x] in 'TMDX#W,L':
                g[y, x] = '.'
    for x in range(cx - 2, cx + 3):
        g[cy + 2 * gate, x] = '#'
    for y in range(cy - 2, cy + 3):
        if (y - cy) * gate >= -1:
            g[y, cx - 2] = '#'; g[y, cx + 2] = '#'
    g[cy, cx] = ch
g[BASE[1], BASE[0] - 5] = 'P'
spawns = [(54, 3), (74, 3), (64, 10)]
for x, y in spawns:
    for yy in range(max(0, y - 1), y + 2):
        for xx in range(x - 1, x + 2):
            if g[yy, xx] in 'TMD#XW':
                g[yy, xx] = '.'
    g[y, x] = 'S'


def reach(start, goal):
    seen = {start}; q = deque([start])
    while q:
        x, y = q.popleft()
        if (x, y) == goal:
            return True
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if inside(nx, ny) and (nx, ny) not in seen and g[ny, nx] in '.,WD#SPCEL':
                seen.add((nx, ny)); q.append((nx, ny))
    return False


me = (BASE[0] - 5, BASE[1])
assert all(reach(s, BASE) for s in spawns), "spawns cannot reach the base"
assert reach(me, ENEMY), "player cannot reach the enemy base"
assert reach(me, (ISLE, int(river_y(ISLE + 0.5)))), "island cannot be reached"
for l in loot:
    assert reach(me, l), "loot cannot be reached"

rows = ["".join(r) for r in g]
path = "world/levels.gd"
src = open(path).read()
block = "## Twin Banks: a river with fords and an island splits the map, a Command\n## Centre on each bank, three guarded roads. Made by tools/make_river_map.py.\nconst RIVER := [\n" + "".join('\t"%s",\n' % r for r in rows) + "]\n"
if "const RIVER := [" in src:
    a = src.index("## Twin Banks")
    b = src.index("]\n", src.index("const RIVER := [")) + 2
    src = src[:a] + block + src[b:]
else:
    src = src.rstrip("\n") + "\n\n" + block
open(path, "w").write(src)
print({c: int(np.sum(g == c)) for c in 'WRTMD#X,L1234'}, 'loot', len(loot))
if len(sys.argv) > 1:
    from PIL import Image
    col = {'.': (214, 184, 132), ',': (176, 146, 100), 'W': (70, 160, 175), 'R': (20, 80, 130), 'T': (50, 110, 45),
           'M': (110, 95, 80), 'D': (240, 215, 160), '#': (150, 100, 60), 'X': (130, 130, 130), 'S': (220, 40, 40),
           'P': (40, 220, 60), 'C': (255, 255, 255), 'E': (0, 0, 0), 'L': (255, 230, 0),
           '1': (255, 0, 255), '2': (255, 120, 0), '3': (160, 0, 0), '4': (90, 0, 160)}
    im = Image.new('RGB', (W, H))
    for y in range(H):
        for x in range(W):
            im.putpixel((x, y), col[g[y, x]])
    im.resize((W * 8, H * 8), Image.NEAREST).save(sys.argv[1])
