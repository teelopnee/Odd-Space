#!/usr/bin/env python3
"""Pixel-art VFX sprite sheets for ODD-SPACE (numpy + Pillow).

Each sheet is a single row of frames.  Played in-engine by src/core/fx_sprite.gd,
usually with HDR modulate (>1) so the scene's bloom makes them glow.
Writes assets/sprites/fx/<name>.png and fx.json (frame sizes / counts).
"""
import json
import math
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sprites", "fx")
rng = np.random.default_rng(77)
META = {}


def canvas(w, h):
    return np.zeros((h, w, 4), dtype=np.float64)


def save(name, frames, fps):
    h, w = frames[0].shape[:2]
    sheet = np.concatenate(frames, axis=1)
    img = Image.fromarray((np.clip(sheet, 0, 1) * 255).astype(np.uint8), "RGBA")
    img.save(os.path.join(OUT, name + ".png"))
    META[name] = {"w": w, "h": h, "frames": len(frames), "fps": fps}


def grid(w, h):
    y, x = np.mgrid[0:h, 0:w]
    return x + 0.5, y + 0.5


def palette_map(v, stops):
    """v in 0..1 -> colour from list of (pos, (r,g,b))"""
    out = np.zeros(v.shape + (3,))
    for i in range(len(stops) - 1):
        p0, c0 = stops[i]
        p1, c1 = stops[i + 1]
        m = (v >= p0) & (v <= p1)
        t = ((v - p0) / max(1e-6, p1 - p0))[m][:, None]
        out[m] = np.array(c0) * (1 - t) + np.array(c1) * t
    return out


def quantize(c, levels=5):
    return np.round(c * levels) / levels


def slash(name, w, h, start_deg, sweep_deg, radius, thick, frames=5):
    fr = []
    x, y = grid(w, h)
    cx, cy = w / 2, h / 2
    ang = np.degrees(np.arctan2(-(y - cy), x - cx)) % 360
    dist = np.hypot(x - cx, y - cy)
    for f in range(frames):
        k = (f + 1) / frames
        img = canvas(w, h)
        head = start_deg + sweep_deg * min(1.0, k * 1.4)
        tail = start_deg + sweep_deg * max(0.0, k * 1.4 - 0.75)
        lo, hi = min(tail, head), max(tail, head)
        a = (ang - lo) % 360
        span = (hi - lo)
        inarc = a <= span
        along = np.where(inarc, a / max(span, 1e-6), 0)
        if sweep_deg < 0:
            along = 1 - along
        width = thick * (0.25 + 0.75 * along) * (1.0 - 0.6 * max(0, k - 0.6) / 0.4)
        band = np.abs(dist - radius) < width
        m = inarc & band
        core = np.abs(dist - radius) < width * 0.45
        fade = 1.0 if k < 0.7 else 1.0 - (k - 0.7) / 0.3
        col = np.where(core[..., None], np.array([1.0, 1.0, 1.0]), np.array([0.45, 1.0, 1.0]))
        img[m, :3] = col[m]
        img[m, 3] = fade * (0.55 + 0.45 * along[m])
        fr.append(quantize(img, 6))
    save(name, fr, 22)


def spark(name, w, frames=5, color=(1.0, 0.95, 0.6)):
    fr = []
    x, y = grid(w, w)
    c = w / 2
    ang = np.arctan2(y - c, x - c)
    dist = np.hypot(x - c, y - c)
    for f in range(frames):
        k = f / (frames - 1)
        img = canvas(w, w)
        rays = np.abs(np.cos(ang * 4)) ** 8 * (w * 0.48) * (0.4 + 0.6 * math.sin(math.pi * min(1, k * 1.5)))
        core = dist < (w * 0.18) * (1 - k)
        ray = (dist < rays) & (dist > w * 0.05 * k)
        img[ray, :3] = color
        img[ray, 3] = 1 - k * 0.7
        img[core, :3] = (1, 1, 1)
        img[core, 3] = 1
        fr.append(img)
    save(name, fr, 24)


def explosion(name, w, frames=9):
    fr = []
    x, y = grid(w, w)
    c = w / 2
    noise = rng.random((w, w))
    for f in range(frames):
        k = f / (frames - 1)
        img = canvas(w, w)
        r = w * (0.18 + 0.32 * math.sqrt(k))
        d = np.hypot(x - c, y - c - k * w * 0.12) / r
        n = (noise * 0.35 + 0.65)
        heat = np.clip((1 - d) * 1.6 * n - k * 0.9, 0, 1)
        m = d < 1.0
        stops = [(0.0, (0.25, 0.22, 0.28)), (0.15, (0.5, 0.18, 0.2)), (0.4, (1.0, 0.35, 0.1)), (0.7, (1.0, 0.75, 0.2)), (1.0, (1.0, 1.0, 0.85))]
        col = palette_map(heat, stops)
        smoke = (heat < 0.12) & m
        img[m, :3] = col[m]
        img[m, 3] = 1.0
        img[smoke, 3] = np.clip(1.0 - k, 0, 1) * 0.85
        ring = (np.abs(d - 1.05) < 0.08) & (k < 0.4)
        img[ring, :3] = (1, 0.9, 0.6)
        img[ring, 3] = 1
        fr.append(quantize(img, 7))
    save(name, fr, 16)


def dust(name, w, frames=6):
    fr = []
    x, y = grid(w, w)
    puffs = [(w * 0.35, w * 0.6, 0.28), (w * 0.6, w * 0.55, 0.24), (w * 0.5, w * 0.4, 0.2)]
    for f in range(frames):
        k = f / (frames - 1)
        img = canvas(w, w)
        for (px, py, r) in puffs:
            rr = w * r * (0.5 + 0.7 * k)
            d = np.hypot(x - px, y - (py - k * w * 0.15))
            m = d < rr
            shade = np.where(d < rr * 0.55, 0.92, 0.72)
            img[m, :3] = np.stack([shade[m], shade[m] * 0.95, shade[m] * 1.02], axis=1)
            img[m, 3] = 0.85 * (1 - k)
        fr.append(img)
    save(name, fr, 18)


def shatter(name, w, frames=7):
    fr = []
    shards = [(rng.uniform(0, 2 * math.pi), rng.uniform(0.5, 1.0), rng.integers(2, 4)) for _ in range(18)]
    c = w / 2
    for f in range(frames):
        k = f / (frames - 1)
        img = canvas(w, w)
        x, y = grid(w, w)
        ring = np.abs(np.hypot(x - c, y - c) - (w * 0.15 + k * w * 0.32)) < 1.2 * (1 - k) + 0.3
        img[ring, :3] = (0.9, 1.0, 1.0)
        img[ring, 3] = 1 - k
        for (a, sp, size) in shards:
            dist = (w * 0.1) + k * w * 0.42 * sp
            sx, sy = int(c + math.cos(a) * dist), int(c + math.sin(a) * dist + k * k * w * 0.1)
            for dy in range(size):
                for dx in range(size - dy):
                    if 0 <= sx + dx < w and 0 <= sy + dy < w:
                        img[sy + dy, sx + dx] = (0.6, 1.0, 1.0, 1 - k * 0.8)
        fr.append(img)
    save(name, fr, 18)


def muzzle(name, w, frames=3):
    fr = []
    x, y = grid(w, w)
    c = w / 2
    for f in range(frames):
        k = f / frames
        img = canvas(w, w)
        d = np.hypot((x - c) * 0.6, y - c)
        m = d < w * (0.45 - k * 0.3)
        img[m, :3] = (1, 0.95, 0.7)
        img[m, 3] = 1
        core = d < w * (0.2 - k * 0.15)
        img[core, :3] = (1, 1, 1)
        fr.append(img)
    save(name, fr, 30)


def chip(name, w=10, frames=4):
    fr = []
    for f in range(frames):
        img = canvas(w, w)
        widths = [w, int(w * 0.6), 2, int(w * 0.6)]
        cw = max(2, widths[f])
        x0 = (w - cw) // 2
        img[2:w - 2, x0:x0 + cw, :3] = (1.0, 0.82, 0.24)
        img[2:w - 2, x0:x0 + cw, 3] = 1
        img[3:w - 3, x0 + 1:max(x0 + 2, x0 + cw - 1), :3] = (1.0, 0.95, 0.6)
        fr.append(img)
    save(name, fr, 12)


def ring(name, w, frames=6, color=(1.0, 0.3, 0.35)):
    """Ground telegraph ring (drawn flat on the floor)."""
    fr = []
    x, y = grid(w, w)
    c = w / 2
    d = np.hypot(x - c, y - c)
    for f in range(frames):
        k = f / (frames - 1)
        img = canvas(w, w)
        edge = np.abs(d - w * 0.46) < 1.2
        fill = d < w * 0.46 * k
        img[fill, :3] = color
        img[fill, 3] = 0.28
        img[edge, :3] = color
        img[edge, 3] = 0.9
        fr.append(img)
    save(name, fr, 12)


def shield_icon(name, w=16):
    img = canvas(w, w)
    for y in range(w):
        half = (w // 2 - 1) if y < w * 0.55 else max(0, int((w // 2 - 1) * (1 - (y - w * 0.55) / (w * 0.45))))
        for x in range(w // 2 - half, w // 2 + half):
            edge = x in (w // 2 - half, w // 2 + half - 1) or y in (0, 1) or half <= 1
            img[y, x] = (0.15, 0.25, 0.4, 1) if edge else (0.55, 0.85, 1.0, 1) if y < w * 0.45 else (0.3, 0.55, 0.85, 1)
    save(name, [img], 1)


def main():
    os.makedirs(OUT, exist_ok=True)
    slash("slash_h", 64, 64, 200, -220, 22, 6)
    slash("slash_rise", 64, 64, 300, 220, 22, 6)
    slash("slash_down", 72, 72, 120, -200, 26, 8, frames=6)
    spark("hit_spark", 32)
    spark("crit_spark", 40, color=(1.0, 0.45, 1.0))
    explosion("explosion", 64)
    dust("dust", 24)
    shatter("break", 64)
    muzzle("muzzle", 20)
    chip("chip")
    ring("telegraph", 64)
    shield_icon("shield")
    with open(os.path.join(OUT, "fx.json"), "w") as f:
        json.dump(META, f, indent=1)
    print("fx written:", ", ".join(META))


if __name__ == "__main__":
    main()
