#!/usr/bin/env python3
"""Pixel-art environment textures + normal maps for ODD-SPACE (numpy + Pillow).

Every surface texture is built from a height field, so we also emit a matching
normal map (<name>_n.png, OpenGL/Godot convention).  Lit by the scene's point
lights, the normal maps make panels, bolts, grates and rocks catch neon and
lamp light - a big part of the HD-2D look.

Also writes: space backdrop (station windows), skyline/mountain silhouettes
(planet horizons, tinted in-engine), and a foliage atlas (wind-swayed plants).
"""
import math
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures")
S = 64


def rng(seed):
    return np.random.default_rng(seed)


def tile_noise(size, cells, seed, octaves=3):
    """Tileable value-noise fbm in 0..1."""
    r = rng(seed)
    out = np.zeros((size, size))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        c = cells * (2 ** o)
        g = r.random((c, c))
        y, x = np.mgrid[0:size, 0:size] / size * c
        x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
        fx, fy = x - x0, y - y0
        fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        x1, y1 = (x0 + 1) % c, (y0 + 1) % c
        x0, y0 = x0 % c, y0 % c
        v = (g[y0, x0] * (1 - fx) * (1 - fy) + g[y0, x1] * fx * (1 - fy) + g[y1, x0] * (1 - fx) * fy + g[y1, x1] * fx * fy)
        out += v * amp
        total += amp
        amp *= 0.5
    return out / total


def normal_from_height(h, strength=2.0):
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * strength
    n = np.stack([-dx, dy, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return (n * 0.5 + 0.5)


def quant(c, levels=10):
    return np.round(np.clip(c, 0, 1) * levels) / levels


def save(name, albedo, height=None, strength=2.0, levels=10):
    a = (quant(albedo, levels) * 255).astype(np.uint8)
    mode = "RGBA" if a.shape[-1] == 4 else "RGB"
    Image.fromarray(a, mode).save(os.path.join(OUT, name + ".png"))
    if height is not None:
        n = (normal_from_height(height, strength) * 255).astype(np.uint8)
        Image.fromarray(n, "RGB").save(os.path.join(OUT, name + "_n.png"))


def rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)]) / 255.0


def colorize(v, dark, light):
    return dark[None, None, :] * (1 - v[..., None]) + light[None, None, :] * v[..., None]


def bevel_panels(size, n, border=2):
    """Height map of n x n raised panels with bevelled edges."""
    y, x = np.mgrid[0:size, 0:size]
    p = size // n
    lx, ly = x % p, y % p
    d = np.minimum(np.minimum(lx, p - 1 - lx), np.minimum(ly, p - 1 - ly))
    return np.clip(d / border, 0, 1), lx, ly, p


# ---------------------------------------------------------------- surfaces

def floor_metal():
    h, lx, ly, p = bevel_panels(S, 2, 2)
    n = tile_noise(S, 4, 1)
    h = h * 0.8 + n * 0.15
    bolts = np.zeros_like(h)
    for bx, by in ((3, 3), (p - 4, 3), (3, p - 4), (p - 4, p - 4)):
        bolts += ((lx - bx) ** 2 + (ly - by) ** 2 <= 1.5).astype(float)
    h += bolts * 0.6
    # Tread pattern on alternating panels.
    y, x = np.mgrid[0:S, 0:S]
    tread = (((x // p + y // p) % 2 == 0) & (((lx + ly) % 6) < 1) & (h > 0.95)).astype(float)
    h += tread * 0.25
    v = 0.5 + h * 0.35 + (n - 0.5) * 0.1 - (1 - np.clip(h, 0, 1)) * 0.25
    scratches = (tile_noise(S, 16, 9, 1) > 0.82) & (h > 0.9)
    v = np.where(scratches, v + 0.12, v)
    alb = colorize(np.clip(v, 0, 1), rgb("#2a2c3a"), rgb("#c8ccdc"))
    save("floor_metal", alb, h, 3.0)


def floor_grate():
    y, x = np.mgrid[0:S, 0:S]
    bar = ((x % 8) < 2) | ((y % 16) < 2)
    h = np.where(bar, 1.0, 0.0) + tile_noise(S, 4, 2) * 0.1
    v = np.where(bar, 0.75, 0.12) + (tile_noise(S, 8, 3) - 0.5) * 0.15
    alb = colorize(np.clip(v, 0, 1), rgb("#14141e"), rgb("#b8bccc"))
    save("floor_grate", alb, h, 4.0)


def floor_tile():
    h, lx, ly, p = bevel_panels(S, 4, 1)
    n = tile_noise(S, 8, 4)
    v = 0.8 + n * 0.15 - (1 - h) * 0.45
    alb = colorize(np.clip(v, 0, 1), rgb("#3a4050"), rgb("#e8f0f4"))
    save("floor_tile", alb, h * 0.6 + n * 0.1, 2.0)


def wall_panel():
    y, x = np.mgrid[0:S, 0:S]
    seam_h = (y % 32) < 1
    seam_v = (x % 32) < 1
    h = np.ones((S, S)) * 0.8
    h[seam_h | seam_v] = 0.0
    h[((y % 32) == 1) | ((x % 32) == 1)] = 0.45
    # vent slats in the lower-left panel of each 32x32 cell
    vent = ((x % 32) > 6) & ((x % 32) < 25) & ((y % 32) > 18) & ((y % 32) < 28)
    slats = vent & ((y % 3) == 0)
    h[vent] = 0.35
    h[slats] = 0.9
    rivets = (((x % 32) - 4) ** 2 + ((y % 32) - 4) ** 2 <= 1) | (((x % 32) - 27) ** 2 + ((y % 32) - 4) ** 2 <= 1)
    h[rivets] = 1.0
    n = tile_noise(S, 4, 5)
    v = 0.45 + h * 0.4 + (n - 0.5) * 0.2
    v[vent & ~slats] = 0.12
    alb = colorize(np.clip(v, 0, 1), rgb("#1e1c2a"), rgb("#c4c4d4"))
    save("wall_panel", alb, h + n * 0.1, 3.0)


def hazard():
    y, x = np.mgrid[0:S, 0:S]
    stripe = ((x + y) // 8) % 2 == 0
    n = tile_noise(S, 8, 6)
    wear = n > 0.72
    col = np.where(stripe[..., None], rgb("#ffcc33"), rgb("#1c1820"))
    col = np.where(wear[..., None], col * 0.55 + rgb("#4a4450") * 0.45, col)
    save("hazard", col, n * 0.4, 1.5)


def crate():
    y, x = np.mgrid[0:S, 0:S]
    edge = (x < 4) | (x > S - 5) | (y < 4) | (y > S - 5)
    rib = ((y % 12) < 2) & ~edge
    h = np.where(edge, 1.0, np.where(rib, 0.7, 0.4))
    stencil = (np.abs(x - S / 2) < 10) & (np.abs(y - S / 2) < 5) & (((x // 3) % 2) == 0)
    n = tile_noise(S, 8, 7)
    v = 0.55 + h * 0.3 + (n - 0.5) * 0.2
    alb = colorize(np.clip(v, 0, 1), rgb("#3a3028"), rgb("#e0d0b0"))
    alb[stencil] = alb[stencil] * 0.55
    save("crate", alb, h + n * 0.1, 3.0)


def ground(name, seed, dark, light, pebble=0.0, ripple=0.0, moss=0.0):
    n = tile_noise(S, 4, seed, 4)
    h = n.copy()
    y, x = np.mgrid[0:S, 0:S]
    if ripple:
        h += np.sin((y + n * 12) * 0.5) * 0.15 * ripple
    if pebble:
        r = rng(seed + 100)
        for _ in range(int(40 * pebble)):
            px, py, pr = r.integers(0, S), r.integers(0, S), r.uniform(1.0, 2.5)
            d = np.sqrt(((x - px + S / 2) % S - S / 2) ** 2 + ((y - py + S / 2) % S - S / 2) ** 2)
            h += np.clip(1 - d / pr, 0, 1) * 0.6
    v = 0.3 + h * 0.6
    alb = colorize(np.clip(v, 0, 1), rgb(dark), rgb(light))
    if moss:
        m = tile_noise(S, 6, seed + 7) > 0.6
        alb[m] = alb[m] * 0.6 + rgb("#4a8a3a") * 0.4
    save(name, alb, h, 2.5)


def rock_cliff():
    y, x = np.mgrid[0:S, 0:S]
    n = tile_noise(S, 4, 11, 4)
    strata = np.sin((y + n * 10) * 0.45) * 0.3
    cracks = (tile_noise(S, 8, 12, 2) > 0.7).astype(float) * -0.5
    h = n * 0.7 + strata + cracks * 0.3
    v = 0.35 + h * 0.5
    alb = colorize(np.clip(v, 0, 1), rgb("#262230"), rgb("#b4aab8"))
    save("rock_cliff", alb, h, 3.0)


def building_panel():
    y, x = np.mgrid[0:S, 0:S]
    h = np.ones((S, S)) * 0.7
    h[(y % 16) < 1] = 0.1
    h[(x % 32) < 1] = 0.2
    win = ((x % 16) > 3) & ((x % 16) < 12) & ((y % 16) > 4) & ((y % 16) < 12)
    h[win] = 0.25
    n = tile_noise(S, 4, 13)
    v = 0.5 + h * 0.35 + (n - 0.5) * 0.25
    v[win] = 0.15
    alb = colorize(np.clip(v, 0, 1), rgb("#1a1a24"), rgb("#c0c0cc"))
    save("building_panel", alb, h + n * 0.1, 2.5)


def concrete():
    n = tile_noise(S, 6, 14, 4)
    y, x = np.mgrid[0:S, 0:S]
    h = n * 0.6 - ((x % 32 < 1) | (y % 32 < 1)) * 0.4
    v = 0.45 + n * 0.4
    alb = colorize(np.clip(v, 0, 1), rgb("#2a2a30"), rgb("#b8b4bc"))
    save("concrete", alb, h, 2.0)


def asphalt():
    """City street: dark grainy tarmac with cracks and worn paint flecks."""
    n = tile_noise(S, 8, 21, 4)
    grain = tile_noise(S, 32, 22, 1)
    crack = tile_noise(S, 4, 23, 2)
    cracks = np.abs(crack - 0.5) < 0.012
    h = n * 0.4 + grain * 0.3 - cracks * 0.5
    v = 0.28 + n * 0.25 + (grain - 0.5) * 0.2
    v = np.where(cracks, v - 0.15, v)
    alb = colorize(np.clip(v, 0, 1), rgb("#101016"), rgb("#6a6878"))
    y, x = np.mgrid[0:S, 0:S]
    paint = (tile_noise(S, 16, 24, 1) > 0.86) & ((x // 8 + y // 8) % 5 == 0)
    alb = np.where(paint[..., None], rgb("#c8b060")[None, None, :] * 0.8, alb)
    save("asphalt", alb, h, 1.6)


def planks():
    """Boardwalk: horizontal weathered planks with dark gaps and nails."""
    y, x = np.mgrid[0:S, 0:S]
    board = y // 8
    gap = (y % 8) == 0
    r = rng(31)
    offs = r.integers(0, S, size=S // 8)
    seam = ((x + offs[board]) % 32) == 0
    grain = tile_noise(S, 4, 32, 3)
    streak = np.sin((x * 0.35 + grain * 6.0 + board * 1.7)) * 0.5 + 0.5
    tone = r.random(S // 8)[board] * 0.25
    v = 0.45 + streak * 0.2 + tone - 0.12
    nail = (((x + offs[board]) % 32 == 3) | ((x + offs[board]) % 32 == 29)) & ((y % 8) == 4)
    v = np.where(gap | seam, 0.05, v)
    v = np.where(nail, 0.85, v)
    h = np.where(gap | seam, 0.0, 0.8 + streak * 0.15)
    alb = colorize(np.clip(v, 0, 1), rgb("#1e140c"), rgb("#b08a5c"))
    save("planks", alb, h, 2.5)


# ---------------------------------------------------------------- backdrops

def space_backdrop():
    W, H = 512, 256
    r = rng(21)
    y, x = np.mgrid[0:H, 0:W]
    n1 = np.array(Image.fromarray((tile_noise(128, 4, 22, 5) * 255).astype(np.uint8)).resize((W, H), Image.BILINEAR)) / 255.0
    n2 = np.array(Image.fromarray((tile_noise(128, 6, 23, 5) * 255).astype(np.uint8)).resize((W, H), Image.BILINEAR)) / 255.0
    col = np.zeros((H, W, 3))
    col += rgb("#05030e")
    neb = np.clip((n1 - 0.45) * 2.2, 0, 1)
    neb2 = np.clip((n2 - 0.5) * 2.5, 0, 1)
    col += neb[..., None] * rgb("#7a1a8a") * 0.9 + neb2[..., None] * rgb("#1a5aa0") * 0.8
    col += (neb * neb2)[..., None] * rgb("#ff7ac8") * 0.6
    stars = r.random((H, W)) > 0.9965
    big = r.random((H, W)) > 0.9994
    col[stars] = 0.85
    for yy, xx in zip(*np.nonzero(big)):
        for dy, dx in ((0, 1), (1, 0), (0, -1), (-1, 0)):
            if 0 <= yy + dy < H and 0 <= xx + dx < W:
                col[yy + dy, xx + dx] = col[yy + dy, xx + dx] * 0.4 + 0.6 * rgb("#a0d0ff")
        col[yy, xx] = 1.0
    # A ringed gas giant.
    cx, cy, R = 380, 150, 70
    d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
    planet = d < R
    band = np.sin((y - cy) * 0.18 + np.sin(x * 0.03) * 1.5) * 0.5 + 0.5
    lit = np.clip(((cx - 30 - x) * 0.6 + (cy - 30 - y) * 0.4) / R + 0.6, 0.12, 1.0)
    pc = (rgb("#e08a4a") * band[..., None] + rgb("#7a3a6a") * (1 - band[..., None])) * lit[..., None]
    col[planet] = pc[planet]
    e = ((x - cx) / (R * 1.85)) ** 2 + ((y - cy) / (R * 0.32)) ** 2
    ring = (e > 0.72) & (e < 1.0) & ~(planet & (y < cy))
    col[ring] = col[ring] * 0.35 + rgb("#f0c8a0") * 0.65
    save("space_backdrop", col, None, levels=24)


def silhouettes():
    """Grayscale horizon layers (white = solid), tinted in-engine. 512x128 RGBA."""
    W, H = 512, 128
    r = rng(31)

    def save_mask(name, heights, windows=False):
        img = np.zeros((H, W, 4))
        for xx in range(W):
            top = int(H - heights[xx])
            img[top:, xx, :3] = 1.0
            img[top:, xx, 3] = 1.0
        if windows:
            m = img[..., 3] > 0
            wl = (r.random((H, W)) > 0.93) & m & (np.arange(H)[:, None] % 4 != 0) & (np.arange(W)[None, :] % 3 != 0)
            img[wl, :3] = (1.0, 0.85, 0.4)
            img[wl & (r.random((H, W)) > 0.6), :3] = (0.4, 1.0, 1.0)
        a = (np.clip(img, 0, 1) * 255).astype(np.uint8)
        Image.fromarray(a, "RGBA").save(os.path.join(OUT, name + ".png"))

    # Megacity skyline.
    hs = np.zeros(W)
    x = 0
    while x < W:
        w = r.integers(10, 40)
        hh = r.integers(25, 120)
        hs[x:x + w] = hh
        if r.random() < 0.3:
            ax = x + w // 2
            hs[ax:ax + 2] = min(127, hh + r.integers(8, 20))
        x += w + r.integers(0, 4)
    save_mask("skyline_city", hs, windows=True)
    # Mountains.
    t = np.arange(W) / W * 2 * math.pi
    hs = 50 + 30 * np.sin(t * 2 + 1) + 18 * np.sin(t * 5 + 2) + 8 * np.sin(t * 13) + r.random(W) * 3
    save_mask("skyline_mountains", np.clip(hs, 5, 127))
    # Spires / crystals.
    hs = np.full(W, 20.0)
    for _ in range(26):
        cx, hh, w = r.integers(0, W), r.integers(30, 120), r.integers(6, 22)
        for xx in range(max(0, cx - w), min(W, cx + w)):
            hs[xx] = max(hs[xx], hh * (1 - abs(xx - cx) / w))
    save_mask("skyline_spires", hs)


def foliage():
    """8 plant sprites (32x32 each) in a 256x32 atlas. Drawn white-ish, tinted per planet."""
    W = 32
    atlas = np.zeros((W, W * 8, 4))
    r = rng(41)

    def put(img, x, y, c):
        if 0 <= x < W and 0 <= y < W:
            img[y, x, :3] = c
            img[y, x, 3] = 1.0

    for i in range(8):
        img = np.zeros((W, W, 4))
        kind = i % 4
        if kind == 0:  # grass tuft
            for b in range(9):
                bx = 6 + b * 2 + r.integers(-1, 2)
                hgt = r.integers(10, 26)
                lean = r.uniform(-0.35, 0.35)
                for yy in range(hgt):
                    sh = 0.55 + 0.45 * (yy / hgt)
                    put(img, int(bx + lean * yy), W - 1 - yy, (sh * 0.7, sh, sh * 0.6))
        elif kind == 1:  # fern fronds
            for f in range(5):
                ang = math.radians(-70 + f * 35)
                for t in range(18):
                    px = int(16 + math.sin(ang) * t * 0.9)
                    py = int(W - 2 - math.cos(ang) * t * 0.9 + t * t * 0.02)
                    sh = 0.5 + 0.5 * (t / 18)
                    put(img, px, py, (sh * 0.6, sh, sh * 0.7))
                    if t % 3 == 0:
                        put(img, px + 1, py - 1, (sh * 0.5, sh * 0.9, sh * 0.6))
                        put(img, px - 1, py - 1, (sh * 0.5, sh * 0.9, sh * 0.6))
        elif kind == 2:  # glowing mushroom cluster
            for m in range(3):
                mx, mh, mr = 9 + m * 7, r.integers(6, 14), r.integers(3, 6)
                for yy in range(mh):
                    put(img, mx, W - 1 - yy, (0.85, 0.85, 0.9))
                cy = W - 1 - mh
                for dy in range(-mr, 1):
                    for dx in range(-mr, mr + 1):
                        if dx * dx + (dy * 1.6) ** 2 <= mr * mr:
                            glow = 1.0 if dy > -mr * 0.5 else 0.8
                            put(img, mx + dx, cy + dy, (glow, glow * 0.9, 1.0))
        else:  # crystal shard / cable cactus
            for c in range(3):
                cx, ch, cw = 10 + c * 6, r.integers(12, 28), r.integers(2, 4)
                for yy in range(ch):
                    w = max(1, int(cw * (1 - yy / ch)))
                    for dx in range(-w, w + 1):
                        sh = 0.6 + 0.4 * (dx > 0)
                        put(img, cx + dx, W - 1 - yy, (sh * 0.9, sh * 0.95, sh))
        atlas[:, i * W:(i + 1) * W] = img
    # outline for readability
    a = atlas[..., 3] > 0
    out = atlas.copy()
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        sh = np.zeros_like(a)
        sh[max(0, dy):a.shape[0] + min(0, dy), max(0, dx):a.shape[1] + min(0, dx)] = \
            a[max(0, -dy):a.shape[0] + min(0, -dy), max(0, -dx):a.shape[1] + min(0, -dx)]
        edge = sh & ~a
        out[edge] = (0.08, 0.1, 0.08, 1.0)
    Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "foliage.png"))


def gradient_shaft():
    """Vertical alpha gradient used for fake volumetric light shafts."""
    H = 64
    y = np.linspace(0, 1, H)
    img = np.zeros((H, 16, 4))
    img[..., :3] = 1.0
    img[..., 3] = ((1 - y) ** 1.5)[:, None] * np.sin(np.linspace(0, math.pi, 16))[None, :]
    Image.fromarray((img * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "light_shaft.png"))


def main():
    os.makedirs(OUT, exist_ok=True)
    floor_metal()
    floor_grate()
    floor_tile()
    wall_panel()
    hazard()
    crate()
    ground("ground_rock", 50, "#2a2630", "#c0b8b0", pebble=1.0)
    ground("ground_sand", 51, "#5a4a3a", "#f0dcb4", ripple=1.0)
    ground("ground_moss", 52, "#1a2a1a", "#9ac080", pebble=0.4, moss=1.0)
    ground("ground_crystal", 53, "#201830", "#b8a8e0", pebble=0.6)
    ground("ground_rust", 54, "#3a1a10", "#e0904a", pebble=0.7)
    rock_cliff()
    building_panel()
    concrete()
    asphalt()
    planks()
    space_backdrop()
    silhouettes()
    foliage()
    gradient_shaft()
    print("textures written to", OUT)


if __name__ == "__main__":
    main()
