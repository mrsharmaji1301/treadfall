"""Cuts tools/art_sheet.png (frond | rock | bark on white) into game textures.
Run after make_textures.py, because it replaces three of its outputs."""
import numpy as np
from PIL import Image

sheet = Image.open("tools/art_sheet.png").convert("RGB")


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def normal_map(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    l = np.sqrt(dx * dx + dy * dy + 1)
    n = np.stack([-dx / l, -dy / l, 1 / l], -1)
    return Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8))


def seamless(img):
    """Cross-fades the image with a half-shifted copy so the edges tile."""
    n = img.shape[0]
    r = np.abs(np.arange(n) - (n - 1) / 2) / (n / 2)
    edge = np.maximum(r[:, None], r[None, :])
    w = (1 - smooth(edge, 0.55, 1.0))[..., None]
    return img * w + np.roll(img, (n // 2, n // 2), (0, 1)) * (1 - w)


def tile(box, size, albedo, normal, gain, bump):
    img = np.asarray(sheet.crop(box).resize((size, size), Image.LANCZOS)) / 255.0
    img = seamless(img) * gain
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(albedo)
    normal_map(img.mean(2), bump).save(normal)


def frond():
    img = np.asarray(sheet.crop((30, 14, 390, 1012)).resize((384, 1024), Image.LANCZOS)) / 255.0
    alpha = smooth(1.0 - img.min(2), 0.07, 0.3)
    a = np.maximum(alpha, 0.05)[..., None]
    col = np.clip((img - (1 - a)) / a, 0, 1)          # take the white out of the edges
    col = np.where(alpha[..., None] < 0.06, np.array([0.3, 0.42, 0.14]), col)
    out = np.concatenate([col, alpha[..., None]], -1)
    Image.fromarray((out * 255).astype(np.uint8), "RGBA").save("assets/nature/palm_frond.png")


frond()
tile((420, 160, 970, 710), 512, "assets/nature/rock_albedo.png", "assets/nature/rock_normal.png", 0.9, 14.0)
tile((1008, 158, 1514, 664), 512, "assets/nature/palm_bark.png", "assets/nature/palm_bark_normal.png", 0.85, 12.0)
print("done")
