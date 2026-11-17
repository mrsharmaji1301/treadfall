#!/usr/bin/env python3
"""Turns the source art in "TANK assets" into the game's textures.

Run from the project root:
    python3 tools/import_assets.py "<path to TANK assets>"

The source folder is only read. Everything is written under assets/.
What it does: removes the small corner mark the image generator leaves,
downsizes, turns black or white backgrounds into real transparency, cuts
sprite sheets into even cells, and builds normal maps for a few surfaces.
Needs Pillow and numpy.
"""
import glob
import os
import shutil
import sys
import zipfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SRC = sys.argv[1] if len(sys.argv) > 1 else "../TANK assets"
OUT = "assets"
missing = []


def find(folder, name):
    """First file in a source folder (matched by its leading digits) whose
    name starts with `name`."""
    for d in sorted(glob.glob(os.path.join(SRC, folder + "*"))):
        hits = sorted(glob.glob(os.path.join(glob.escape(d), name + "*")))
        hits = [h for h in hits if not h.endswith(".zip")]
        if hits:
            h = hits[0]
            if os.path.isdir(h):
                h = os.path.join(h, "screen.png")
            return h
    missing.append(folder + "/" + name)
    return None


def out(rel):
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return path


def mark_box(im):
    w, h = im.size
    if w >= 2000:
        return (w - 180, h - 180, w - 45, h - 45)
    return (w - 145, h - 145, w - 60, h - 60)


def patch_tile(im):
    """Covers the corner mark with a feathered copy of the texture beside it."""
    x0, y0, x1, y1 = mark_box(im)
    bw, bh = x1 - x0, y1 - y0
    donor = im.crop((x0 - bw - 40, y0 - 30, x1 - bw - 40, y1 - 30))
    mask = Image.new("L", (bw, bh), 0)
    pad = bw // 6
    ImageDraw.Draw(mask).rectangle((pad, pad, bw - pad, bh - pad), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(pad * 0.5))
    im.paste(donor, (x0, y0), mask)
    return im


def blank_mark(im, color):
    ImageDraw.Draw(im).rectangle(mark_box(im), fill=color)
    return im


def tile(folder, name, rel, size=1024, quality=90, patch=True):
    src = find(folder, name)
    if not src:
        return None
    im = Image.open(src).convert("RGB")
    if patch and im.size[0] == im.size[1]:
        im = patch_tile(im)
    if im.size[0] > size:
        im = im.resize((size, size), Image.LANCZOS)
    im.save(out(rel), quality=quality)
    return im


def normal_from(im, rel, strength=2.0, size=None):
    """Normal map from brightness, wrapping at the edges so it still tiles."""
    if im is None:
        return
    if size:
        im = im.resize((size, size), Image.LANCZOS)
    g = np.asarray(im.convert("L").filter(ImageFilter.GaussianBlur(1.0)), dtype=np.float32) / 255.0
    dx = (np.roll(g, -1, 1) - np.roll(g, 1, 1)) * strength
    dy = (np.roll(g, -1, 0) - np.roll(g, 1, 0)) * strength
    n = np.dstack([-dx, -dy, np.full_like(g, 0.25)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(out(rel), quality=92)


def smooth(x, lo, hi):
    t = np.clip((x - lo) / float(hi - lo), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def key_black(im, solid=True):
    """Black background to alpha. `solid` things get a hard-ish edge; glows
    and smoke use their brightness as alpha."""
    a = np.asarray(im.convert("RGB"), dtype=np.float32)
    peak = a.max(axis=2)
    if solid:
        alpha = smooth(peak, 14.0, 46.0)
    else:
        alpha = np.clip(peak / 255.0 * 1.35, 0.0, 1.0)
    rgb = a / np.maximum(peak[..., None] / 255.0, 0.12) if not solid else a
    if not solid:
        # Keep the hue, lift the colour so alpha carries the brightness.
        rgb = np.clip(rgb, 0, 255) * 0.85 + a * 0.15
    res = np.dstack([np.clip(rgb, 0, 255), alpha * 255.0]).astype(np.uint8)
    return Image.fromarray(res, "RGBA")


def key_white(im):
    a = np.asarray(im.convert("RGB"), dtype=np.float32)
    dist = 255.0 - a.min(axis=2)
    alpha = smooth(dist, 24.0, 72.0)
    al = np.maximum(alpha, 0.05)[..., None]
    rgb = (a - 255.0 * (1.0 - al)) / al
    res = np.dstack([np.clip(rgb, 0, 255), alpha * 255.0]).astype(np.uint8)
    return Image.fromarray(res, "RGBA")


def key_edges(im, tol=26, centre=False):
    """Clears only the background connected to the corners (and the middle,
    for a frame with a hole), so dark parts of the object itself stay."""
    im = im.convert("RGB")
    w, h = im.size
    flag = (255, 0, 255)
    seeds = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w // 2, 0), (w // 2, h - 1),
             (0, h // 2), (w - 1, h // 2)]
    if centre:
        seeds.append((w // 2, h // 2))
    work = im.copy()
    for s in seeds:
        if work.getpixel(s) != flag:
            ImageDraw.floodfill(work, s, flag, thresh=tol)
    a = np.asarray(work)
    hole = (a[..., 0] == 255) & (a[..., 1] == 0) & (a[..., 2] == 255)
    alpha = Image.fromarray(np.where(hole, 0, 255).astype(np.uint8))
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.0))
    res = im.convert("RGBA")
    res.putalpha(alpha)
    return res


def bleed(im, rounds=6):
    """Spreads edge colour into the transparent area, so no dark or white
    halo shows when the picture is filtered."""
    a = np.asarray(im, dtype=np.float32)
    rgb, alpha = a[..., :3].copy(), a[..., 3]
    known = alpha > 24
    for _ in range(rounds):
        acc = np.zeros_like(rgb)
        cnt = np.zeros(alpha.shape, dtype=np.float32)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            k = np.roll(known, (dy, dx), (0, 1))
            acc += np.roll(rgb, (dy, dx), (0, 1)) * k[..., None]
            cnt += k
        grow = (~known) & (cnt > 0)
        rgb[grow] = acc[grow] / cnt[grow][..., None]
        known = known | grow
    return Image.fromarray(np.dstack([rgb, alpha]).astype(np.uint8), "RGBA")


def crop_alpha(im, pad=4):
    box = im.getchannel("A").point(lambda v: 255 if v > 20 else 0).getbbox()
    if not box:
        return im
    return im.crop((max(box[0] - pad, 0), max(box[1] - pad, 0),
                    min(box[2] + pad, im.size[0]), min(box[3] + pad, im.size[1])))


def cutout(folder, name, rel, size, white=False, solid=True, fit=None):
    src = find(folder, name)
    if not src:
        return
    im = Image.open(src).convert("RGB")
    if white:
        im = key_white(im)
    else:
        im = key_black(blank_mark(im, (0, 0, 0)), solid)
    im = crop_alpha(im)
    if fit:
        im = im.resize(fit, Image.LANCZOS)
    else:
        im.thumbnail((size, size), Image.LANCZOS)
    if solid:
        im = bleed(im)
    im.save(out(rel))


def runs(flags, gap):
    spans, start, last = [], None, None
    for i, f in enumerate(flags):
        if f:
            if start is None:
                start = i
            elif i - last > gap:
                spans.append((start, last + 1))
                start = i
            last = i
    if start is not None:
        spans.append((start, last + 1))
    return spans


def above_pot(part):
    """Cuts a potted plant off just above the rim of its clay pot."""
    a = np.asarray(part, dtype=np.float32)
    solid = a[..., 3] > 60
    clay = solid & (a[..., 0] > 130) & (a[..., 0] - a[..., 1] > 45) & (a[..., 1] > 60) & (a[..., 2] < 110)
    rows = solid.sum(axis=1).astype(np.float32)
    share = clay.sum(axis=1) / np.maximum(rows, 1.0)
    for y in range(part.size[1] // 3, part.size[1]):
        if rows[y] > 4 and share[y] > 0.45:
            # The rim curves, so go a little higher than its first full row.
            return crop_alpha(part.crop((0, 0, part.size[0], max(y - int(part.size[1] * 0.07), 1))), 0)
    return part


def sheet(folder, name, rel, white, cell=256, ground=True, solid=True, trim=None):
    """Cuts a sheet of 4 things into a strip of 4 even cells. Side views sit
    on the bottom edge of their cell; top views are centred."""
    src = find(folder, name)
    if not src:
        return
    im = Image.open(src).convert("RGB")
    im = key_white(im) if white else key_black(blank_mark(im, (0, 0, 0)), solid)
    mask = np.asarray(im.getchannel("A")) > 40
    boxes = []
    for y0, y1 in runs(mask.any(axis=1), im.size[1] // 40):
        for x0, x1 in runs(mask[y0:y1].any(axis=0), im.size[0] // 50):
            boxes.append((x0, y0, x1, y1))
    boxes.sort(key=lambda b: -(b[2] - b[0]) * (b[3] - b[1]))
    boxes = sorted(boxes[:4], key=lambda b: (b[1] // (im.size[1] // 3), b[0]))
    if len(boxes) != 4:
        # Shapes touch each other: split the occupied area evenly instead.
        ys, xs = np.where(mask)
        x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
        if (x1 - x0) > 2 * (y1 - y0):
            q = (x1 - x0) / 4.0
            boxes = [(int(x0 + q * i), y0, int(x0 + q * (i + 1)), y1) for i in range(4)]
        else:
            mx, my = (x0 + x1) // 2, (y0 + y1) // 2
            boxes = [(x0, y0, mx, my), (mx, y0, x1, my), (x0, my, mx, y1), (mx, my, x1, y1)]
    strip = Image.new("RGBA", (cell * 4, cell), (0, 0, 0, 0))
    for i, b in enumerate(boxes):
        part = crop_alpha(im.crop(b), 0)
        if trim:
            part = trim(part)
            k = min((cell - 8) / part.size[0], (cell - 8) / part.size[1])
            part = part.resize((int(part.size[0] * k), int(part.size[1] * k)), Image.LANCZOS)
        part.thumbnail((cell - 8, cell - 8), Image.LANCZOS)
        x = i * cell + (cell - part.size[0]) // 2
        y = cell - part.size[1] - 2 if ground else (cell - part.size[1]) // 2
        strip.paste(part, (x, y))
    if solid:
        strip = bleed(strip)
    strip.save(out(rel))


def grid(folder, name, rel, size=512, solid=False):
    """A 2 x 2 effect sheet on black: keyed to alpha, kept as 2 x 2."""
    src = find(folder, name)
    if not src:
        return
    im = key_black(blank_mark(Image.open(src).convert("RGB"), (0, 0, 0)), solid)
    im.resize((size, size), Image.LANCZOS).save(out(rel))


def copy(folder, name, rel):
    src = find(folder, name)
    if src:
        shutil.copyfile(src, out(rel))


# ---- 1, 2: ground and water ------------------------------------------------
for n in ["sand", "sand_coarse", "dune", "road", "road_edge", "scrub", "grass", "jungle",
          "badland", "badland_cracked", "ash", "gravel", "concrete", "base_plates"]:
    im = tile("1.", "ground_" + n + ".", "terrain/ground_%s.jpg" % n)
    if n in ("sand", "road"):
        normal_from(im, "terrain/ground_%s_normal.jpg" % n, 2.5)
for n in ["bank", "wet_sand", "riverbed", "riverbed_deep", "oasis_mud"]:
    tile("2.", "ground_" + n + ".", "terrain/ground_%s.jpg" % n)
tile("2.", "water_normal", "water/water_normal.png")
for n in ["foam", "caustics", "flow"]:
    tile("2.", "water_" + n, "water/water_%s.jpg" % n, 512, 88)

# ---- 3: trees ---------------------------------------------------------------
for n in ["green", "dry", "young"]:
    cutout("3.", "palm_frond_" + n, "nature/palm_frond_%s.png" % n, 0, fit=(384, 1024))
normal_from(tile("3.", "palm_bark", "nature/palm_bark.jpg", 512), "nature/palm_bark_normal.jpg", 3.0)
normal_from(tile("3.", "acacia_bark", "nature/acacia_bark.jpg", 512), "nature/acacia_bark_normal.jpg", 3.0)
for n in ["palm_dates", "acacia_branch", "dead_tree_branch", "tamarisk_branch"]:
    cutout("3.", n, "nature/%s.png" % n, 512)
cutout("3.", "fallen_palm_log.png", "nature/fallen_palm_log.png", 512)
cutout("4.", "Cut_palm_stump", "nature/tree_stump.png", 256, white=True)

# ---- 4: plants (white backgrounds) -----------------------------------------
PLANTS = {"shrubs": "Desert_shrubs", "shrubs_green": "Leafy_green_oasis", "grass_green": "Grass_clumps",
          "grass_dry": "Desert_grass", "grass_tall": "Tall_wild_grass", "reeds": "River_reeds",
          "ferns": "Ferns_and", "cactus": "Cacti_and", "flowers": "Desert_wildflowers",
          "tumbleweed": "Dry_tumbleweeds", "vines": "Four_hanging"}
for key, src_name in PLANTS.items():
    sheet("4.", src_name, "nature/plants_%s.png" % key, True, trim=above_pot if key == "cactus" else None)
for key, src_name in {"lily_pads": "Green_lily", "leaf_litter": "Dry_leaves", "moss_patches": "Green_moss"}.items():
    sheet("4.", src_name, "nature/%s.png" % key, True, ground=False)

# ---- 5: rocks ---------------------------------------------------------------
ROCKS = {"cliff": "Sandstone_cliff", "red": "Red_sandstone", "dark": "Dark_grey_basalt",
         "mossy": "Grey_river_rock", "layers": "Sedimentary"}
for key, src_name in ROCKS.items():
    im = tile("5.", src_name, "nature/rock_%s.jpg" % key, 1024, 88)
    normal_from(im, "nature/rock_%s_normal.jpg" % key, 3.0, 512)
sheet("5.", "Pebbles", "nature/pebbles_sheet.png", True, ground=False)
sheet("5.", "Desert_boulders", "nature/boulders_sheet.png", True)

# ---- 7: building surfaces ---------------------------------------------------
BUILD = {"concrete_bunker": "Weathered_military_concrete", "concrete_damaged": "Cracked_concrete",
         "metal_plates": "Desert_tan_painted", "metal_dark": "Gunmetal", "metal_rust": "Rusted_steel",
         "metal_grate": "Steel_floor", "metal_olive": "Olive_green_armour", "metal_red_enemy": "Dark_red_painted",
         "sandbags": "Stacked_military", "camo_net": "Desert_camouflage_netting", "ruin_wall": "Sandstone_block",
         "ruin_plaster": "Cracked_mud", "mud_brick": "Sun_dried", "wood_planks": "Weathered_wooden",
         "wood_crate": "Military_wooden", "corrugated_metal": "Rusty_corrugated", "tarp": "Olive_canvas"}
for key, src_name in BUILD.items():
    im = tile("7.", src_name, "build/%s.jpg" % key, 1024, 88)
    if key in ("concrete_bunker", "metal_plates", "sandbags", "mud_brick", "metal_dark", "metal_red_enemy"):
        normal_from(im, "build/%s_normal.jpg" % key, 3.0, 512)
cutout("7.", "Barbed_wire", "build/barbed_wire.png", 512)
cutout("7.", "Chain_link", "build/chain_fence.png", 512)

# ---- 9: tank surfaces -------------------------------------------------------
TANK = {"paint_tan": "Desert_tan_tank", "paint_olive": "Olive_green_tank", "paint_red": "Dark_red_tank",
        "paint_grey": "Dark_grey_tank", "camo_desert": "Desert_camouflage_pattern", "damage": "Armour_with",
        "burnt": "Burnt_blackened", "track": "Steel_tank_track"}
for key, src_name in TANK.items():
    im = tile("9.", src_name, "tank/tank_%s.jpg" % key, 1024, 88)
    if key in ("damage", "burnt", "track"):
        normal_from(im, "tank/tank_%s_normal.jpg" % key, 3.0, 512)
cutout("9.", "Mud_splatter", "tank/tank_mud.png", 512)
cutout("9.", "Vertical_rust", "tank/tank_rust_streaks.png", 512)

# ---- 10: effects ------------------------------------------------------------
for key, src_name in {"smoke": "Grey_smoke", "fire": "Four_flame", "explosion": "Explosion_stages",
                      "dust": "Tan_dust"}.items():
    grid("10.", src_name, "fx/fx_%s_sheet.png" % key)
FX = {"muzzle_flash": "Cannon_muzzle", "muzzle_flash_front": "Star_shaped", "sparks": "Orange_sparks",
      "shockwave": "White_shockwave", "splash": "Water_splash", "ripple": "Concentric_water",
      "tracer": "Glowing_streak", "missile_trail": "White_smoke_trail", "shield": "Glowing_blue",
      "heal": "Glowing_green", "lens_dirt": "Dust_specks"}
for key, src_name in FX.items():
    cutout("10.", src_name, "fx/fx_%s.png" % key, 512, solid=False)
for key, src_name in {"scorch": "Scorch_mark", "crater": "Shell_crater"}.items():
    src = find("10.", src_name)
    if src:
        im = crop_alpha(key_edges(blank_mark(Image.open(src).convert("RGB"), (0, 0, 0)), 16))
        im.thumbnail((512, 512), Image.LANCZOS)
        im.save(out("fx/fx_%s.png" % key))

# ---- 11: icons (zips of folders, already transparent) -----------------------
for z in sorted(glob.glob(os.path.join(SRC, "11.*", "*.zip"))):
    with zipfile.ZipFile(z) as zf:
        for info in zf.infolist():
            if info.filename.endswith("screen.png"):
                name = info.filename.split("/")[-2].replace("icon_", "")
                with zf.open(info) as f:
                    im = Image.open(f).convert("RGBA")
                    im = crop_alpha(im, 8)
                    side = max(im.size)
                    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
                    sq.paste(im, ((side - im.size[0]) // 2, (side - im.size[1]) // 2))
                    sq.resize((160, 160), Image.LANCZOS).save(out("ui/icons/%s.png" % name))

# ---- 12: HUD and menus ------------------------------------------------------
for n in ["cursor", "hud_arrow", "hud_banner", "hud_button.", "hud_button_hover", "hud_crosshair",
          "hud_health_frame", "hud_ping", "hud_slot.", "hud_slot_active", "hud_top_bar"]:
    copy("12.", n, "ui/%s.png" % n.rstrip("."))
for key, src_name, hole in [("hud_minimap_frame", "ui_cutout_asset_hud_minimap", True),
                            ("hud_bar_frame", "ui_cutout_texture_asset", False),
                            ("hud_panel", "ui_element_cutout_hud_panel", False),
                            ("menu_logo_plate", "ui_element_menu_logo", False)]:
    src = find("12.", src_name)
    if src:
        crop_alpha(key_edges(Image.open(src), 26, hole)).save(out("ui/%s.png" % key))
for key, src_name in {"menu_background": "cinematic_wide_shot", "loading_screen": "cinematic_military",
                      "victory_screen": "cinematic_video_game_victory", "defeat_screen": "cinematic_video_game_defeat"}.items():
    src = find("12.", src_name)
    if src:
        Image.open(src).convert("RGB").save(out("ui/%s.jpg" % key), quality=90)

# ---- 13: sky ----------------------------------------------------------------
copy("13.", "sky_day", "sky/sky_day.hdr")
copy("13.", "sky_sunset", "sky/sky_sunset.hdr")
copy("13.", "clouds_sheet", "sky/clouds_sheet.png")
copy("13.", "sun_flare", "sky/sun_flare.png")

print("done. not found:", missing if missing else "nothing")
