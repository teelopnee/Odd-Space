#!/usr/bin/env python3
"""SPRITE FORGE - HD-2D pixel-art character renderer for ODD-SPACE.

Characters are built from 3D signed-distance primitives (round cones, ellipsoids,
rounded boxes) on a tiny forward-kinematics skeleton, animated procedurally,
then ray-marched orthographically at native pixel resolution and post-processed
into pixel art:  hue-shifted cel ramps, selective inner outlines, dark outer
outline, single-pixel eyes.  Result: smooth multi-frame, multi-direction sprite
sheets that read like hand-made HD-2D sprites and can be swapped 1:1 for
hand-drawn art later (same JSON metadata).

Output per character (assets/sprites/characters/):
  <name>.png   atlas: one row per (animation, direction), FRAME_W x FRAME_H cells
  <name>.json  {"frame_w","frame_h","dirs":[...],"anims":{name:{"fps","loop","frames","rows":{dir:row}}}}

Directions rendered: S, SE, E, NE, N  (W-side directions are mirrored in-engine).

Usage:  python3 tools/sprite_forge.py [name ...]      (numpy + Pillow)
"""
import colorsys
import json
import math
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "characters")
FRAME_W, FRAME_H = 64, 64
FOOT_ROW = 60                # pixel row of the ground line
ELEVATION = math.radians(22)  # sprites are seen slightly from above, like the game camera
DIRS = {"S": 0.0, "SE": 45.0, "E": 90.0, "NE": 135.0, "N": 180.0}
LIGHT = np.array([-0.55, 0.72, 0.42])
LIGHT = LIGHT / np.linalg.norm(LIGHT)

# --------------------------------------------------------------------------- colour


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def ramp(base_hex):
    """5-step hue-shifted ramp: [outline, shadow, base, light, highlight]."""
    r, g, b = hex_rgb(base_hex)
    h, s, v = colorsys.rgb_to_hsv(r, g, b)

    def shift(hh, toward, amt):
        d = ((toward - hh + 0.5) % 1.0) - 0.5
        return (hh + d * amt) % 1.0

    cool, warm = 0.70, 0.13  # shadows drift to violet, lights to warm yellow
    tones = [
        (shift(h, cool, 0.30), min(1, s * 1.15 + 0.12), v * 0.30),
        (shift(h, cool, 0.16), min(1, s * 1.08 + 0.05), v * 0.66),
        (h, s, v),
        (shift(h, warm, 0.10), s * 0.85, min(1, v * 1.16 + 0.04)),
        (shift(h, warm, 0.18), s * 0.55, min(1, v * 1.30 + 0.12)),
    ]
    return np.array([colorsys.hsv_to_rgb(*t) for t in tones])


# --------------------------------------------------------------------------- math


def norm(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else v


def v3(x, y, z):
    return np.array([x, y, z], dtype=np.float64)


class Frame3:
    """Character local frame: R (right hand side), U (up), F (forward)."""

    def __init__(self, facing_deg):
        p = math.radians(facing_deg)
        self.F = v3(math.sin(p), 0, math.cos(p))
        self.U = v3(0, 1, 0)
        self.R = np.cross(self.F, self.U)

    def w(self, x, y, z):
        """local (right, up, forward) -> world"""
        return self.R * x + self.U * y + self.F * z

    def d(self, x, y, z):
        return norm(self.w(x, y, z))


def rot_axis(v, axis, ang):
    axis = norm(axis)
    c, s = math.cos(ang), math.sin(ang)
    return v * c + np.cross(axis, v) * s + axis * np.dot(axis, v) * (1 - c)


# --------------------------------------------------------------------------- SDF primitives
# Each primitive: dict(kind, params..., mat)


def P_sphere(c, r, mat):
    return {"k": "sph", "c": np.asarray(c, float), "r": r, "mat": mat}


def P_cone(a, b, r1, r2, mat):
    return {"k": "cone", "a": np.asarray(a, float), "b": np.asarray(b, float), "r1": r1, "r2": r2, "mat": mat}


def P_ell(c, radii, basis, mat):
    return {"k": "ell", "c": np.asarray(c, float), "rad": np.asarray(radii, float), "M": np.asarray(basis, float), "mat": mat}


def P_box(c, half, basis, rnd, mat):
    return {"k": "box", "c": np.asarray(c, float), "h": np.asarray(half, float), "M": np.asarray(basis, float), "rnd": rnd, "mat": mat}


def sdf(prim, P):
    k = prim["k"]
    if k == "sph":
        return np.linalg.norm(P - prim["c"], axis=1) - prim["r"]
    if k == "ell":
        q = (P - prim["c"]) @ prim["M"].T
        r = prim["rad"]
        k0 = np.linalg.norm(q / r, axis=1)
        k1 = np.linalg.norm(q / (r * r), axis=1)
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)
    if k == "box":
        q = np.abs((P - prim["c"]) @ prim["M"].T) - prim["h"]
        outside = np.linalg.norm(np.maximum(q, 0.0), axis=1)
        inside = np.minimum(np.max(q, axis=1), 0.0)
        return outside + inside - prim["rnd"]
    # round cone (iq)
    a, b, r1, r2 = prim["a"], prim["b"], prim["r1"], prim["r2"]
    ba = b - a
    l2 = float(np.dot(ba, ba))
    if l2 < 1e-6:
        return np.linalg.norm(P - a, axis=1) - max(r1, r2)
    rr = r1 - r2
    a2 = l2 - rr * rr
    il2 = 1.0 / l2
    pa = P - a
    y = pa @ ba
    z = y - l2
    x2v = pa * l2 - np.outer(y, ba)
    x2 = np.sum(x2v * x2v, axis=1)
    y2 = y * y * l2
    z2 = z * z * l2
    kk = np.sign(rr) * rr * rr * x2
    d1 = np.sqrt(x2 + z2) * il2 - r2
    d2 = np.sqrt(x2 + y2) * il2 - r1
    d3 = (np.sqrt(np.maximum(x2 * a2 * il2, 0.0)) + y * rr) * il2 - r1
    return np.where(np.sign(z) * a2 * z2 > kk, d1, np.where(np.sign(y) * a2 * y2 < kk, d2, d3))


def scene_sdf(prims, P):
    best = np.full(len(P), 1e9)
    ids = np.full(len(P), -1, dtype=np.int32)
    for i, pr in enumerate(prims):
        d = sdf(pr, P)
        m = d < best
        best = np.where(m, d, best)
        ids = np.where(m, i, ids)
    return best, ids


# --------------------------------------------------------------------------- renderer


class Camera:
    def __init__(self):
        e = ELEVATION
        self.fwd = norm(v3(0, -math.sin(e), -math.cos(e)))  # looking toward -z, down a bit
        self.right = v3(1, 0, 0)
        self.up = norm(np.cross(self.right, self.fwd))  # (0, cos e, -sin e)
        xs = np.arange(FRAME_W) - FRAME_W / 2 + 0.5
        ys = FOOT_ROW - (np.arange(FRAME_H) + 0.5)
        gx, gy = np.meshgrid(xs, ys)
        self.sx = gx.ravel()
        self.sy = gy.ravel()
        self.origins = np.outer(self.sx, self.right) + np.outer(self.sy, self.up) - self.fwd * 70.0


CAM = Camera()


def render(prims, mats):
    """Ray-march the primitive list; returns RGBA uint8 image (FRAME_H, FRAME_W, 4)."""
    n = len(CAM.sx)
    t = np.full(n, 30.0)
    alive = np.ones(n, dtype=bool)
    hit = np.zeros(n, dtype=bool)
    ids = np.full(n, -1, dtype=np.int32)
    for _ in range(56):
        idx = np.nonzero(alive)[0]
        if len(idx) == 0:
            break
        P = CAM.origins[idx] + np.outer(t[idx], CAM.fwd)
        d, pid = scene_sdf(prims, P)
        close = d < 0.05
        hit[idx[close]] = True
        ids[idx[close]] = pid[close]
        alive[idx[close]] = False
        t[idx] += np.maximum(d, 0.04) * 0.9
        far = t > 140.0
        alive &= ~far
    # Normals by central differences on the hit pixels.
    hidx = np.nonzero(hit)[0]
    img = np.zeros((n, 4))
    if len(hidx) == 0:
        return (img.reshape(FRAME_H, FRAME_W, 4) * 255).astype(np.uint8), np.full(n, -1), np.full(n, 1e9)
    P = CAM.origins[hidx] + np.outer(t[hidx], CAM.fwd)
    e = 0.12
    nrm = np.zeros((len(hidx), 3))
    for ax in range(3):
        o = np.zeros(3)
        o[ax] = e
        dp, _ = scene_sdf(prims, P + o)
        dm, _ = scene_sdf(prims, P - o)
        nrm[:, ax] = dp - dm
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
    lam = np.clip(nrm @ LIGHT, 0, 1)
    rim = np.clip(1.0 - np.abs(nrm @ (-CAM.fwd)), 0, 1) ** 3
    shade = 0.30 + 0.62 * lam + 0.18 * rim
    mat_ids = np.array([mats.index(prims[i]["mat"]) if prims[i]["mat"] in mats else 0 for i in range(len(prims))])
    m_of_hit = mat_ids[ids[hidx]]
    out = np.zeros((len(hidx), 3))
    for mi, mat in enumerate(mats):
        sel = m_of_hit == mi
        if not np.any(sel):
            continue
        r = MATS[mat]["ramp"]
        if MATS[mat].get("flat"):
            out[sel] = r[3] if MATS[mat].get("bright") else r[2]
            continue
        s = shade[sel] + (0.14 if MATS[mat].get("soft") else 0.0)
        band = np.where(s < 0.45, 1, np.where(s < 0.76, 2, np.where(s < 0.97, 3, 4)))
        if MATS[mat].get("no_highlight"):
            band = np.minimum(band, 3)
        out[sel] = r[band]
    img[hidx, :3] = out
    img[hidx, 3] = 1.0
    depth = np.full(n, 1e9)
    depth[hidx] = t[hidx]
    matmap = np.full(n, -1)
    matmap[hidx] = m_of_hit
    return img, matmap, depth


def outline(img, matmap, depth, mats):
    """Inner sel-out where depth jumps (farther part gets a dark line) + dark outer contour."""
    H, W = FRAME_H, FRAME_W
    img = img.reshape(H, W, 4)
    mm = matmap.reshape(H, W)
    dp = depth.reshape(H, W)
    solid = img[:, :, 3] > 0
    res = img.copy()
    dark = np.array([MATS[m]["ramp"][0] for m in mats])          # per-material darkest tone
    flat = np.array([bool(MATS[m].get("flat")) for m in mats])
    mm_safe = np.where(mm >= 0, mm, 0)
    inner = np.zeros((H, W), dtype=bool)
    outer_src = np.full((H, W), -1)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        nb_solid = np.zeros((H, W), dtype=bool)
        nb_dp = np.full((H, W), 1e9)
        nb_mm = np.full((H, W), -1)
        ys = slice(max(0, -dy), H - max(0, dy))
        yd = slice(max(0, dy), H - max(0, -dy))
        xs = slice(max(0, -dx), W - max(0, dx))
        xd = slice(max(0, dx), W - max(0, -dx))
        nb_solid[ys, xs] = solid[yd, xd]
        nb_dp[ys, xs] = dp[yd, xd]
        nb_mm[ys, xs] = mm[yd, xd]
        inner |= solid & nb_solid & ((dp - nb_dp) > 2.2)
        take = (~solid) & nb_solid & (outer_src < 0)
        outer_src = np.where(take, nb_mm, outer_src)
    inner &= ~flat[mm_safe]
    res[inner, :3] = dark[mm_safe[inner]] * 0.9 + img[inner, :3] * 0.1
    om = outer_src >= 0
    res[om, :3] = dark[outer_src[om]] * 0.55
    res[om, 3] = 1.0
    return (np.clip(res, 0, 1) * 255).astype(np.uint8)


def paint_decals(rgba, depth):
    """Paint eye decals where the point is visible (facing camera, not occluded)."""
    H, W = FRAME_H, FRAME_W
    dp = depth.reshape(H, W)
    for kind, pt, nrm in DECALS:
        if np.dot(nrm, -CAM.fwd) < 0.12:
            continue
        sx = float(np.dot(pt, CAM.right))
        sy = float(np.dot(pt, CAM.up))
        px = int(math.floor(sx + FRAME_W / 2))
        py = int(math.floor(FOOT_ROW - sy))
        if not (0 <= px < W and 1 <= py < H - 1):
            continue
        t_pt = float(np.dot(pt - CAM.origins[py * W + px], CAM.fwd))
        if dp[py, px] > 1e8 or t_pt - dp[py, px] > 1.6:
            continue  # hidden behind hair, hands...
        if kind == "eye":
            rgba[py, px, :3] = (26, 16, 44)
            rgba[py - 1, px, :3] = (40, 26, 60)
            rgba[py, px, 3] = rgba[py - 1, px, 3] = 255
        else:
            rgba[py, px, :3] = (60, 36, 50)
            rgba[py, px, 3] = 255
    return rgba


# --------------------------------------------------------------------------- materials

MATS = {}
DECALS = []   # (kind, world_point, world_normal) appended by builders, painted after render


def define_mats(colors):
    """colors: name -> hex or (hex, flags)"""
    MATS.clear()
    for name, val in colors.items():
        flags = {}
        if isinstance(val, tuple):
            val, flags = val
        MATS[name] = {"ramp": ramp(val), **flags}
    defaults = {"metal": "#5a5a6a", "gloves": colors.get("boots", "#2a2236"), "cap": colors.get("hair", "#444444"),
                "coat": colors.get("top", "#666666"), "pack": "#5a4a3a", "accent": "#ffd23e", "club": "#4a3428",
                "helmet": "#e8ecff", "scarf": colors.get("accent", "#ff3ec8"), "hair": "#333333"}
    for k, v in defaults.items():
        if k not in MATS:
            MATS[k] = {"ramp": ramp(v)}
    for k, v in {"visor": "#3ee6ff", "emblem": "#ff3ec8", "flash": "#fff6b0"}.items():
        if k not in MATS:
            MATS[k] = {"ramp": ramp(v), "flat": True, "bright": True}
    MATS.setdefault("eye", {"ramp": ramp("#1a1030"), "flat": True})
    if "skin" in MATS:
        MATS["skin"]["soft"] = True
    MATS.setdefault("glow", {"ramp": ramp("#3ee6ff"), "flat": True, "bright": True})


# --------------------------------------------------------------------------- humanoid rig

HUMAN_ANIMS = [
    # name, frames, fps, loop
    ("idle", 8, 7, True),
    ("walk", 8, 11, True),
    ("run", 8, 14, True),
    ("roll", 6, 16, False),
    ("shoot", 6, 18, False),
    ("slash1", 6, 18, False),
    ("slash2", 6, 18, False),
    ("slash3", 7, 16, False),
    ("guard", 4, 14, False),
    ("hurt", 3, 12, False),
    ("dead", 6, 9, False),
    ("talk", 8, 7, True),
    ("charge", 6, 12, True),
]


def ease(t):
    return t * t * (3 - 2 * t)


def human_pose(anim, t):
    """Returns a pose dict of angles (radians) and offsets for normalized time t in [0,1)."""
    s = math.sin
    c = math.cos
    tau = 2 * math.pi
    p = {
        "bob": 0.0, "lean": 0.0, "twist": 0.0, "head_tilt": 0.0, "crouch": 0.0, "roll": 0.0,
        "lthigh": 0.0, "lknee": 0.05, "rthigh": 0.0, "rknee": 0.05,
        "larm": (0.06, 0.12), "rarm": (0.06, 0.12),  # (forward pitch, outward roll)
        "lelbow": 0.15, "relbow": 0.15,
        "rarm_dir": None, "rfore_dir": None, "larm_dir": None, "lfore_dir": None,
        "weapon": "holster", "flash": False, "trail": 0.0, "lay": 0.0, "tail": 0.0,
    }
    if anim == "idle":
        b = s(t * tau)
        p["bob"] = -0.6 + 0.6 * b
        p["larm"] = (0.05, 0.13 + 0.03 * b)
        p["rarm"] = (0.05, 0.13 + 0.03 * b)
        p["head_tilt"] = 0.04 * s(t * tau + 1)
        p["tail"] = 0.15 * s(t * tau)
    elif anim in ("walk", "run"):
        run = anim == "run"
        amp = 0.75 if run else 0.48
        ph = t * tau
        p["lthigh"] = amp * s(ph)
        p["rthigh"] = -amp * s(ph)
        p["lknee"] = 0.15 + (1.0 if run else 0.55) * max(0.0, -s(ph + 0.6))
        p["rknee"] = 0.15 + (1.0 if run else 0.55) * max(0.0, s(ph + 0.6))
        arm = 0.85 if run else 0.5
        p["larm"] = (-arm * s(ph) * 0.9, 0.12)
        p["rarm"] = (arm * s(ph) * 0.9, 0.12)
        p["lelbow"] = 1.2 if run else 0.35
        p["relbow"] = 1.2 if run else 0.35
        p["bob"] = (1.6 if run else 1.0) * abs(c(ph)) - (1.4 if run else 0.8)
        p["lean"] = 0.22 if run else 0.06
        p["twist"] = 0.12 * s(ph)
        p["tail"] = (0.6 if run else 0.3) + 0.2 * s(ph * 2)
    elif anim == "roll":
        k = t
        p["crouch"] = 0.75 if 0.05 < k < 0.95 else 0.35
        p["roll"] = ease(k) * tau
        p["lthigh"] = p["rthigh"] = 1.6
        p["lknee"] = p["rknee"] = 2.3
        p["larm"] = p["rarm"] = (1.3, 0.2)
        p["lelbow"] = p["relbow"] = 1.8
        p["tail"] = 0.9
    elif anim == "shoot":
        k = min(1.0, t * 1.6)
        aim = ease(k)
        p["rarm_dir"] = (0.05, -0.2 + 0.25 * aim, 0.4 + 0.6 * aim)
        p["rfore_dir"] = (0.02, 0.0 + 0.05 * aim, 1.0)
        p["weapon"] = "blaster"
        p["flash"] = 0.3 < t < 0.55
        p["lean"] = -0.08 if 0.3 < t < 0.6 else 0.02
        p["larm"] = (0.25, 0.18)
        p["lelbow"] = 0.9
        p["lthigh"], p["rthigh"] = 0.25, -0.2
    elif anim in ("slash1", "slash2", "slash3"):
        # anticipation -> strike -> follow through
        k = t
        if anim == "slash1":   # right to left horizontal
            a = -1.6 + 3.0 * ease(min(1, max(0, (k - 0.2) / 0.45)))
            p["rarm_dir"] = (math.sin(-a) * 0.9, 0.05, math.cos(a))
            p["rfore_dir"] = (math.sin(-a - 0.2), 0.05, math.cos(a + 0.2))
            p["twist"] = -0.35 + 0.7 * ease(min(1, max(0, (k - 0.2) / 0.45)))
        elif anim == "slash2":  # left to right rising
            a = 1.5 - 3.0 * ease(min(1, max(0, (k - 0.15) / 0.45)))
            p["rarm_dir"] = (math.sin(-a) * 0.9, -0.3 + 0.5 * k, math.cos(a))
            p["rfore_dir"] = (math.sin(-a + 0.3), -0.1 + 0.5 * k, math.cos(a))
            p["twist"] = 0.35 - 0.7 * ease(min(1, max(0, (k - 0.15) / 0.45)))
        else:                  # overhead smash
            a = -2.4 + 3.3 * ease(min(1, max(0, (k - 0.3) / 0.35)))
            p["rarm_dir"] = (0.05, math.cos(a + math.pi), -math.sin(a + math.pi) + 0.2)
            p["rfore_dir"] = (0.05, math.cos(a + math.pi - 0.2), -math.sin(a + math.pi - 0.2) + 0.3)
            p["crouch"] = 0.25 if 0.55 < k < 0.85 else 0.0
            p["lean"] = 0.25 if 0.55 < k else -0.1
        p["weapon"] = "baton"
        p["trail"] = 1.0 if 0.25 < k < 0.7 else 0.0
        p["larm"] = (0.3, 0.35)
        p["lelbow"] = 1.1
        p["lthigh"], p["rthigh"] = 0.35, -0.3
        p["lknee"] = 0.35
        p["tail"] = 0.6
    elif anim == "guard":
        k = ease(min(1, t * 2.0))
        p["rarm_dir"] = (-0.4 * k, 0.3 + 0.5 * k, 0.6)
        p["rfore_dir"] = (-0.9 * k, 0.6, 0.3)
        p["larm_dir"] = (0.4 * k, 0.3 + 0.4 * k, 0.6)
        p["lfore_dir"] = (0.9 * k, 0.5, 0.3)
        p["weapon"] = "baton"
        p["crouch"] = 0.18
        p["lthigh"], p["rthigh"] = 0.3, -0.25
        p["lknee"] = p["rknee"] = 0.5
    elif anim == "hurt":
        k = math.sin(t * math.pi)
        p["lean"] = -0.35 * k
        p["head_tilt"] = -0.3 * k
        p["larm"] = (-0.3 * k, 0.5 * k + 0.1)
        p["rarm"] = (-0.3 * k, 0.5 * k + 0.1)
        p["lthigh"] = 0.2 * k
        p["bob"] = -0.5 * k
    elif anim == "dead":
        k = ease(min(1.0, t * 1.25))
        p["lay"] = k
        p["lean"] = -0.4 * k
        p["larm"] = (-0.4, 0.5 * k + 0.1)
        p["rarm"] = (-0.2, 0.7 * k + 0.1)
        p["lthigh"] = 0.3 * k
        p["lknee"] = 0.6 * k
    elif anim == "talk":
        g = s(t * 2 * math.pi)
        p["rarm_dir"] = (0.25 + 0.15 * g, -0.35 + 0.15 * max(0, g), 0.6)
        p["rfore_dir"] = (0.1, 0.35 + 0.3 * g, 0.8)
        p["larm"] = (0.1, 0.15)
        p["head_tilt"] = 0.08 * g
        p["bob"] = -0.4 + 0.4 * abs(g)
    elif anim == "charge":
        g = s(t * 2 * math.pi)
        p["rarm_dir"] = (0.7, 0.2, 0.6)
        p["larm_dir"] = (-0.7, 0.2, 0.6)
        p["rfore_dir"] = (0.3, 0.6, 0.7)
        p["lfore_dir"] = (-0.3, 0.6, 0.7)
        p["crouch"] = 0.2 + 0.05 * g
        p["lthigh"], p["rthigh"] = 0.35, -0.35
        p["weapon"] = "baton"
        p["trail"] = 0.5
    return p


def build_human(cfg, facing, anim, t):
    """cfg: character config. Returns list of primitives in world space."""
    fr = Frame3(facing)
    p = human_pose(anim, t)
    S = cfg.get("scale", 1.0)
    big = cfg.get("big", 1.0)          # torso width factor
    prims = []
    # --- dimensions (pixels ~ units)
    hip_h = 17.0 * S
    thigh_l, shin_l = 7.8 * S, 7.6 * S
    torso_h = 12.0 * S
    head_r = 8.3 * cfg.get("head", 1.0)
    shoulder_w = 6.6 * S * big
    hip_w = 3.1 * S * big
    crouch = p["crouch"]
    pelvis = fr.w(0, hip_h - crouch * 7.0 + p["bob"], 0)
    lean = p["lean"]
    twist = p["twist"]
    # Body frame after lean (pitch forward about R) and twist (yaw about U).
    up = rot_axis(fr.U, fr.R, -lean)
    fwd = rot_axis(fr.F, fr.R, -lean)
    fwd_t = rot_axis(fwd, up, twist)
    right_t = np.cross(fwd_t, up)

    def body(x, y, z):
        return pelvis + right_t * x + up * y + fwd_t * z

    chest = body(0, torso_h * 0.72, 0.2)
    neck = body(0, torso_h + 1.0, 0.3)
    head_c = neck + rot_axis(up, right_t, -p["head_tilt"]) * (head_r * 0.92) + fwd_t * 0.4

    # --- legs
    def leg(side, thigh, knee):
        hip = pelvis + fr.R * (side * hip_w) + up * 0.5
        d1 = norm(-fr.U * math.cos(thigh) + fr.F * math.sin(thigh))
        kneep = hip + d1 * thigh_l
        a2 = thigh - knee
        d2 = norm(-fr.U * math.cos(a2) + fr.F * math.sin(a2))
        ankle = kneep + d2 * shin_l
        return hip, kneep, ankle

    lhip, lknee, lank = leg(-1, p["lthigh"], p["lknee"])
    rhip, rknee, rank = leg(1, p["rthigh"], p["rknee"])
    pants = "pants"
    boots = "boots"
    for hip, kn, an in ((lhip, lknee, lank), (rhip, rknee, rank)):
        prims.append(P_cone(hip, kn, 3.1 * S * min(big, 1.25), 2.6 * S, pants))
        prims.append(P_cone(kn, an, 2.6 * S, 2.3 * S, pants))
        prims.append(P_cone(kn + (an - kn) * 0.45, an, 2.75 * S, 2.6 * S, boots))
        foot_c = an + fr.F * 1.6 * S - fr.U * 1.0
        prims.append(P_ell(foot_c, [2.3 * S, 1.6 * S, 3.3 * S], [fr.R, fr.U, fr.F], boots))

    # --- torso
    basis = [right_t, up, fwd_t]
    prims.append(P_ell(body(0, 2.2, 0), [5.0 * S * big, 3.8 * S, 3.6 * S], basis, pants))
    prims.append(P_ell(chest, [6.2 * S * big, 6.6 * S, 4.2 * S], basis, "top"))
    prims.append(P_ell(body(0, 3.8, 0.1), [5.5 * S * big, 2.2 * S, 3.9 * S], basis, "accent"))  # belt
    if cfg.get("emblem"):
        prims.append(P_sphere(chest + fwd_t * 4.0 * S + right_t * 2.2 * S + up * 1.5, 1.0, "emblem"))
    if cfg.get("coat"):
        # Long coat: flared cone from chest to knees + tail swing
        tail = p["tail"]
        hem = body(0, -7.5 * S, -1.0 - 2.5 * tail)
        prims.append(P_cone(body(0, torso_h * 0.6, 0.0), hem, 6.4 * S * big, 6.0 * S * big, "coat"))
        prims.append(P_ell(chest + fwd_t * -0.3, [6.6 * S * big, 6.9 * S, 4.5 * S], basis, "coat"))
        prims.append(P_ell(chest + fwd_t * 3.4 * S, [2.2 * S, 5.6 * S, 1.6 * S], basis, "top"))  # shirt front
    if cfg.get("pack"):
        kind = cfg["pack"]
        mat = "pack"
        pc = chest - fwd_t * 5.0 * S + up * 0.5
        if kind == "jetpack":
            prims.append(P_box(pc, [3.2 * S, 4.2 * S, 1.8 * S], basis, 1.0, mat))
            for sd in (-1, 1):
                noz = pc + right_t * sd * 2.4 * S - up * 5.0 * S
                prims.append(P_cone(pc + right_t * sd * 2.4 * S - up * 2.0, noz, 1.4, 1.2, "metal"))
                prims.append(P_sphere(noz - up * 0.8, 0.9, "glow"))
        else:
            prims.append(P_ell(pc, [3.8 * S, 4.4 * S, 2.4 * S], basis, mat))
    if cfg.get("scarf"):
        prims.append(P_ell(neck - up * 0.6, [5.2, 2.3, 4.6], basis, "scarf"))
        tail = p["tail"]
        prims.append(P_cone(neck - fwd_t * 2.5, neck - fwd_t * (5 + 4 * tail) - up * (6 - 3 * tail) + right_t * 2, 1.6, 1.1, "scarf"))
    if cfg.get("pads"):
        for sd in (-1, 1):
            prims.append(P_sphere(body(sd * shoulder_w, torso_h * 0.95, 0), 2.7 * S, "accent"))

    # --- arms
    def arm(side, swing, elbow, adir, fdir):
        sh = body(side * shoulder_w, torso_h * 0.92, 0)
        if adir is not None:
            d1 = norm(fr.R * adir[0] * side + fr.U * adir[1] + fr.F * adir[2]) if side < 0 else norm(fr.R * adir[0] + fr.U * adir[1] + fr.F * adir[2])
        else:
            pitch, rollo = swing
            d1 = norm(-fr.U * math.cos(pitch) + fr.F * math.sin(pitch))
            d1 = norm(d1 * math.cos(rollo) + fr.R * side * math.sin(rollo))
        el = sh + d1 * 6.2 * S
        if fdir is not None:
            d2 = norm(fr.R * fdir[0] + fr.U * fdir[1] + fr.F * fdir[2])
        else:
            pitch = swing[0] + elbow
            d2 = norm(-fr.U * math.cos(pitch) + fr.F * math.sin(pitch))
            d2 = norm(d2 * math.cos(swing[1] * 0.6) + fr.R * side * math.sin(swing[1] * 0.6))
        hand = el + d2 * 5.8 * S
        return sh, el, hand, d2

    lsh, lel, lhand, ld = arm(-1, p["larm"], p["lelbow"], p["larm_dir"], p["lfore_dir"])
    rsh, rel, rhand, rd = arm(1, p["rarm"], p["relbow"], p["rarm_dir"], p["rfore_dir"])
    sleeve = "coat" if cfg.get("coat") else "top"
    for sh, el, hand in ((lsh, lel, lhand), (rsh, rel, rhand)):
        prims.append(P_cone(sh, el, 2.35 * S * min(big, 1.3), 2.05 * S, sleeve))
        prims.append(P_cone(el, hand, 2.05 * S, 1.75 * S, sleeve if cfg.get("long_sleeves", True) else "skin"))
        prims.append(P_sphere(hand, 1.85 * S, "gloves" if "gloves" in MATS else "skin"))

    # --- weapon in right hand
    w = p["weapon"] if cfg.get("armed", True) else "none"
    if w == "holster" and cfg.get("gun"):
        prims.append(P_box(rhip + fr.R * 2.6 + fr.F * 0.5 - fr.U * 2.0, [0.9, 2.4, 1.6], [fr.R, fr.U, fr.F], 0.4, "metal"))
    elif w == "blaster" and cfg.get("gun"):
        gd = rd
        gb = [np.cross(gd, fr.U) if abs(np.dot(gd, fr.U)) < 0.95 else fr.R, fr.U, gd]
        gb[0] = norm(gb[0])
        prims.append(P_box(rhand + gd * 3.2, [1.0, 1.3, 3.4], gb, 0.4, "metal"))
        prims.append(P_sphere(rhand + gd * 6.8, 0.8, "glow"))
        if p["flash"]:
            prims.append(P_sphere(rhand + gd * 9.0, 2.2, "flash"))
    elif w == "baton" and cfg.get("melee", True):
        tip = rhand + rd * 13.0 * S
        prims.append(P_cone(rhand - rd * 1.5, rhand + rd * 2.5, 1.0, 1.0, "metal"))
        prims.append(P_cone(rhand + rd * 2.5, tip, 1.15, 0.9, "glow"))
    elif w in ("baton", "blaster", "holster") and cfg.get("club"):
        tip = rhand + rd * 11.0
        prims.append(P_cone(rhand, tip, 1.3, 2.4, "club"))

    # --- head
    hb = [right_t, up, fwd_t]
    if cfg.get("robot"):
        prims.append(P_box(head_c, [head_r * 0.85, head_r * 0.8, head_r * 0.75], hb, 1.6, "metal"))
        prims.append(P_box(head_c + fwd_t * head_r * 0.62, [head_r * 0.62, head_r * 0.45, 0.6], hb, 0.6, "visor"))
        prims.append(P_cone(head_c + up * head_r * 0.7, head_c + up * head_r * 1.4, 0.5, 0.4, "metal"))
        prims.append(P_sphere(head_c + up * head_r * 1.5, 0.9, "emblem"))
    else:
        prims.append(P_ell(head_c, [head_r, head_r * 1.02, head_r * 0.96], hb, "skin"))
        prims.append(P_sphere(head_c + fwd_t * head_r * 0.15 - up * head_r * 0.55, head_r * 0.52, "skin"))  # jaw
        # eyes: tiny dark spheres just under the face surface -> only visible when facing us
        for sd in (-1, 1):
            # Eyes are painted as 2D decals after rendering (crisp 1x2 pixels).
            ln = norm(fwd_t * 0.86 + right_t * sd * 0.42 - up * 0.08)
            DECALS.append(("eye", head_c + ln * head_r * 0.98, ln))
        hair = cfg.get("hair_style", "short")
        hc = "hair"
        if cfg.get("helmet"):
            prims.append(P_ell(head_c + up * 0.9 - fwd_t * 0.3, [head_r * 1.12, head_r * 1.08, head_r * 1.12], hb, "helmet"))
            prims.append(P_ell(head_c + fwd_t * head_r * 0.82 + up * 0.2, [head_r * 0.85, head_r * 0.36, head_r * 0.42], hb, "visor"))
        elif hair != "bald":
            prims.append(P_ell(head_c + up * head_r * 0.42 - fwd_t * head_r * 0.30, [head_r * 1.07, head_r * 0.82, head_r * 1.0], hb, hc))
            prims.append(P_ell(head_c + up * head_r * 0.66 + fwd_t * head_r * 0.48, [head_r * 0.82, head_r * 0.24, head_r * 0.38], hb, hc))  # bangs
            for sd in (-1, 1):  # sideburns frame the face
                prims.append(P_ell(head_c + right_t * sd * head_r * 0.86 + up * head_r * 0.15 - fwd_t * head_r * 0.1, [head_r * 0.22, head_r * 0.5, head_r * 0.42], hb, hc))
            if hair == "spiky":
                for i, (ax, ay) in enumerate(((-0.7, 0.6), (-0.25, 0.95), (0.25, 0.9), (0.7, 0.55), (0.0, 0.7))):
                    base = head_c + up * head_r * 0.55 + right_t * ax * head_r * 0.7 - fwd_t * 1.5
                    tipd = norm(up * ay + right_t * ax * 0.8 - fwd_t * (0.6 + 0.4 * p["tail"]))
                    prims.append(P_cone(base, base + tipd * head_r * 0.95, 2.6, 0.3, hc))
            elif hair == "long":
                prims.append(P_cone(head_c - fwd_t * head_r * 0.5, head_c - fwd_t * (head_r * 0.6 + 1.5 * p["tail"]) - up * head_r * 1.9, head_r * 0.85, head_r * 0.55, hc))
            elif hair == "mohawk":
                for i in range(5):
                    a = -0.5 + i * 0.3
                    base = head_c + up * head_r * 0.7 + fwd_t * a * head_r * 0.9
                    prims.append(P_cone(base, base + up * (3.5 - abs(a) * 2) - fwd_t * 1.0, 1.8, 0.3, hc))
            elif hair == "bun":
                prims.append(P_sphere(head_c + up * head_r * 0.8 - fwd_t * head_r * 0.75, head_r * 0.45, hc))
            elif hair == "ponytail":
                prims.append(P_cone(head_c + up * head_r * 0.5 - fwd_t * head_r * 0.8, head_c - fwd_t * (head_r * 1.5 + 2 * p["tail"]) - up * head_r * 0.6, 2.4, 1.2, hc))
        if cfg.get("cap"):
            prims.append(P_ell(head_c + up * head_r * 0.55, [head_r * 1.08, head_r * 0.55, head_r * 1.05], hb, "cap"))
            prims.append(P_ell(head_c + up * head_r * 0.45 + fwd_t * head_r * 0.95, [head_r * 0.7, 0.6, head_r * 0.6], hb, "cap"))
        if cfg.get("beard"):
            prims.append(P_ell(head_c - up * head_r * 0.62 + fwd_t * head_r * 0.42, [head_r * 0.62, head_r * 0.42, head_r * 0.4], hb, "hair"))
        if cfg.get("goggles"):  # pushed up on the forehead/hair
            prims.append(P_ell(head_c + up * head_r * 0.95 + fwd_t * head_r * 0.2, [head_r * 0.95, head_r * 0.22, head_r * 0.5], hb, "visor"))

    # Whole-body transforms for roll / lying down.
    pivot = fr.w(0, 9.0, 0)
    if p["roll"] != 0.0:
        prims = [_rotate_prim(pr, pivot, fr.R, -p["roll"]) for pr in prims]
        DECALS[:] = [(k, _rotate_point(pt, pivot, fr.R, -p["roll"]), rot_axis(n, fr.R, -p["roll"])) for k, pt, n in DECALS]
    if p["lay"] > 0.0:
        foot = fr.w(0, 0, 0)
        ang = -p["lay"] * math.pi / 2 * 0.98
        off = fr.U * (2.5 * p["lay"]) + fr.F * 15.0 * p["lay"]  # keep the fallen body centred in frame
        prims = [_rotate_prim(pr, foot, fr.R, ang) for pr in prims]
        prims = [_translate(pr, off) for pr in prims]
        DECALS[:] = [(k, _rotate_point(pt, foot, fr.R, ang) + off, rot_axis(n, fr.R, ang)) for k, pt, n in DECALS]
        if p["lay"] > 0.6:
            DECALS[:] = [("eye_closed", pt, n) for k, pt, n in DECALS]
    if p["trail"] > 0 and cfg.get("melee", True) and w == "baton":
        pass
    return prims


def _rotate_point(pt, pivot, axis, ang):
    return pivot + rot_axis(pt - pivot, axis, ang)


def _rotate_prim(pr, pivot, axis, ang):
    q = dict(pr)
    if pr["k"] in ("sph", "ell", "box"):
        q["c"] = _rotate_point(pr["c"], pivot, axis, ang)
        if "M" in pr:
            q["M"] = np.array([rot_axis(row, axis, ang) for row in pr["M"]])
    else:
        q["a"] = _rotate_point(pr["a"], pivot, axis, ang)
        q["b"] = _rotate_point(pr["b"], pivot, axis, ang)
    return q


def _translate(pr, off):
    q = dict(pr)
    if pr["k"] == "cone":
        q["a"] = pr["a"] + off
        q["b"] = pr["b"] + off
    else:
        q["c"] = pr["c"] + off
    return q


# --------------------------------------------------------------------------- creatures


def build_drone(cfg, facing, anim, t):
    fr = Frame3(facing)
    tau = 2 * math.pi
    bob = math.sin(t * tau) * 1.2
    tilt = 0.0
    y = 30.0 + bob
    eye_mat = "glow"
    if anim in ("walk", "run"):
        tilt = 0.3
    if anim in ("shoot", "slash1", "slash2", "slash3", "charge"):
        eye_mat = "flash" if t > 0.3 else "glow"
    if anim == "hurt":
        tilt = -0.4
    if anim == "dead":
        y = 30 - 24 * ease(min(1, t * 1.3))
        tilt = 1.2 * t
    c = fr.w(0, y, 0)
    fwd = rot_axis(fr.F, fr.R, -tilt)
    up = rot_axis(fr.U, fr.R, -tilt)
    basis = [fr.R, up, fwd]
    prims = [
        P_ell(c, [8.5, 7.5, 8.5], basis, "shell"),
        P_ell(c, [9.6, 2.0, 9.6], basis, "metal"),
        P_ell(c + fwd * 6.6 + up * 0.8, [3.6, 3.6, 2.2], basis, "metal"),
        P_sphere(c + fwd * 7.8 + up * 0.8, 2.4, eye_mat),
        P_cone(c + up * 6.5, c + up * 11.0 - fwd * 2.0, 0.6, 0.4, "metal"),
        P_sphere(c + up * 11.4 - fwd * 2.0, 1.0, "emblem"),
    ]
    for sd in (-1, 1):
        pod = c + fr.R * sd * 10.0 - up * 1.0
        prims.append(P_ell(pod, [2.4, 3.4, 3.6], basis, "metal"))
        prims.append(P_sphere(pod - up * 3.4, 1.4, "glow"))
    return prims


def build_grub(cfg, facing, anim, t):
    fr = Frame3(facing)
    tau = 2 * math.pi
    prims = []
    n = 6
    speed = 1.0 if anim in ("walk", "run") else 0.3
    lunge = 0.0
    if anim in ("shoot", "slash1", "slash2", "slash3"):
        lunge = math.sin(min(1, t * 1.4) * math.pi) * 6
    curl = ease(min(1, t * 1.3)) if anim == "dead" else 0.0
    pts = []
    for i in range(n):
        z = (n / 2 - i) * 4.2 + lunge * (1 - i / n)
        x = math.sin(t * tau * speed * 2 + i * 0.9) * 1.6 * (1 - curl)
        y = 4.5 + abs(math.sin(t * tau * speed * 2 + i * 0.9)) * 1.2 + (i == 0) * 1.5
        if curl:
            ang = i / n * math.pi * 1.4 * curl
            z = z * (1 - curl) + math.cos(ang) * 8 * curl
            y = y + math.sin(ang) * 6 * curl
        pts.append(fr.w(x, y, z))
    for i, pt in enumerate(pts):
        r = 4.6 - abs(i - 1.5) * 0.45
        prims.append(P_sphere(pt, max(2.4, r), "shell" if i % 2 == 0 else "shell2"))
        if 0 < i < n - 1 and not curl:
            for sd in (-1, 1):
                leg_t = pt + fr.R * sd * 5.5 - fr.U * 4.0 + fr.F * math.sin(t * tau * 2 + i) * 1.4
                prims.append(P_cone(pt, leg_t, 0.9, 0.5, "metal"))
    head = pts[0]
    open_j = 0.8 if anim in ("shoot", "slash1", "slash2", "slash3", "charge") else 0.25
    for sd in (-1, 1):
        base = head + fr.F * 3.4 + fr.R * sd * 1.8
        prims.append(P_cone(base, base + fr.F * 3.5 + fr.R * sd * open_j * 3.5 - fr.U * 0.5, 1.1, 0.3, "mandible"))
    for sd in (-1, 1):
        prims.append(P_sphere(head + fr.F * 3.2 + fr.R * sd * 2.0 + fr.U * 1.6, 0.9, "glow"))
    return prims


# --------------------------------------------------------------------------- characters

CREATURE_ANIMS = [("idle", 8, 8, True), ("walk", 8, 12, True), ("run", 8, 14, True), ("shoot", 6, 14, False),
                  ("slash1", 6, 14, False), ("guard", 4, 10, False), ("hurt", 3, 12, False), ("dead", 6, 9, False),
                  ("charge", 6, 12, True), ("roll", 6, 14, False), ("slash2", 6, 14, False), ("slash3", 7, 14, False), ("talk", 8, 7, True)]

CHARACTERS = {
    # name: (builder, materials, cfg)
    "player": ("human", {
        "skin": "#f2c39a", "hair": "#2cc9c0", "top": "#ff8a2a", "pants": "#3a3550", "boots": "#2a2236",
        "accent": "#ffd23e", "coat": "#e8742a", "scarf": "#2cc9c0", "pack": "#5a4a3a", "metal": "#6a6a80",
        "emblem": ("#3ee6ff", {"flat": True, "bright": True}), "visor": ("#3ee6ff", {"flat": True, "bright": True}),
        "flash": ("#fff6b0", {"flat": True, "bright": True}), "gloves": "#2a2236"},
        {"hair_style": "spiky", "scarf": True, "pack": "bag", "gun": True, "emblem": True, "goggles": True}),
    "officer": ("human", {
        "skin": "#d79f75", "hair": "#202024", "top": "#26357a", "pants": "#1c2450", "boots": "#14141e",
        "accent": "#e8ecff", "helmet": "#e8ecff", "visor": ("#3ee6ff", {"flat": True, "bright": True}), "pack": "#7a8094",
        "metal": "#4a4a5a", "emblem": ("#4a6dff", {"flat": True, "bright": True}), "flash": ("#ffb0d0", {"flat": True, "bright": True}),
        "gloves": "#14141e"},
        {"helmet": True, "pack": "jetpack", "gun": True, "emblem": True, "pads": True, "melee": False}),
    "pirate": ("human", {
        "skin": "#c08060", "hair": "#ff3ec8", "top": "#5a2a20", "pants": "#3a2a20", "boots": "#20140e",
        "accent": "#ffd23e", "coat": "#4a2418", "pack": "#6a6a6a", "metal": "#5a5048",
        "emblem": ("#ffd23e", {"flat": True, "bright": True}), "flash": ("#ffd0a0", {"flat": True, "bright": True}), "gloves": "#20140e"},
        {"hair_style": "mohawk", "coat": True, "pack": "jetpack", "gun": True, "melee": False}),
    "brute": ("human", {
        "skin": "#b0704e", "hair": "#1a1a1a", "top": "#5a4a20", "pants": "#3a3020", "boots": "#1e1810",
        "accent": "#ffd23e", "metal": "#5a5a68", "club": "#4a3428", "emblem": ("#ffd23e", {"flat": True, "bright": True}),
        "gloves": "#2a2018"},
        {"hair_style": "bald", "big": 1.45, "scale": 1.12, "head": 0.85, "club": True, "pads": True, "melee": False, "beard": True}),
    "civilian_a": ("human", {"skin": "#e0b080", "hair": "#5a3a20", "top": "#5a6a8a", "pants": "#3a4a6a", "boots": "#2a2a30", "accent": "#a0a0b0"},
                   {"hair_style": "short", "armed": False}),
    "civilian_b": ("human", {"skin": "#8a5a3a", "hair": "#141010", "top": "#3a7a4a", "pants": "#2a4a30", "boots": "#20201a", "accent": "#c0d080"},
                   {"hair_style": "bald", "beard": True, "armed": False, "cap": True}),
    "civilian_c": ("human", {"skin": "#f0d0b0", "hair": "#f0d060", "top": "#7a3a8a", "pants": "#3a2a4a", "boots": "#2a1a2a", "accent": "#ff3ec8", "coat": "#5a2a6a"},
                   {"hair_style": "long", "coat": True, "armed": False}),
    "civilian_d": ("human", {"skin": "#d8a880", "hair": "#a03020", "top": "#c0c0c8", "pants": "#4a4a58", "boots": "#22222a", "accent": "#3ee6ff", "visor": ("#ff3ec8", {"flat": True, "bright": True})},
                   {"hair_style": "ponytail", "goggles": True, "armed": False}),
    "merchant": ("human", {"skin": "#d09060", "hair": "#6a4a2a", "top": "#c09030", "pants": "#4a3a2a", "boots": "#2a2018", "accent": "#ffffff", "cap": "#a03030", "pack": "#5a4a3a"},
                 {"hair_style": "short", "cap": True, "beard": True, "pack": "bag", "armed": False, "big": 1.2}),
    "crew_vex": ("human", {"skin": "#6a4030", "hair": "#101010", "top": "#20306a", "pants": "#18204a", "boots": "#101018", "accent": "#ffd23e", "metal": "#4a4a5a",
                           "emblem": ("#ffd23e", {"flat": True, "bright": True}), "flash": ("#fff6b0", {"flat": True, "bright": True}), "gloves": "#101018"},
                 {"hair_style": "short", "gun": True, "emblem": True, "pads": True}),
    "crew_nuggets": ("human", {"skin": "#f0c090", "hair": "#e03a2a", "top": "#d9a24a", "pants": "#b07a2a", "boots": "#5a3a1a", "accent": "#ff5a2a"},
                     {"hair_style": "bun", "big": 1.35, "armed": False}),
    "crew_pip": ("human", {"skin": "#d0a080", "hair": "#3a2a1a", "top": "#2a4a3a", "pants": "#1a2a20", "boots": "#141810", "accent": "#ffd23e", "coat": "#20382a", "cap": "#20201a",
                           "metal": "#5a5a60", "flash": ("#fff6b0", {"flat": True, "bright": True})},
                 {"hair_style": "short", "coat": True, "cap": True, "gun": True}),
    "crew_varga": ("human", {"skin": "#f0d8c8", "hair": "#b8b8c0", "top": "#e8e8f0", "pants": "#7a7a90", "boots": "#3a3a48", "accent": "#ff3e5a", "coat": "#f4f4fa",
                             "emblem": ("#ff3e5a", {"flat": True, "bright": True})},
                    {"hair_style": "bun", "coat": True, "emblem": True, "armed": False}),
    "crew_kevin": ("human", {"skin": "#9aa4b8", "top": "#8a94a8", "pants": "#6a7488", "boots": "#4a5468", "accent": "#3ee6ff", "metal": "#9aa4b8",
                             "visor": ("#3ee6ff", {"flat": True, "bright": True}), "emblem": ("#ff3ec8", {"flat": True, "bright": True}), "hair": "#9aa4b8"},
                   {"robot": True, "armed": False, "long_sleeves": True}),
    "crew_rook": ("human", {"skin": "#e0c0a0", "hair": "#f0f0f0", "top": "#5a2a6a", "pants": "#3a1a4a", "boots": "#20102a", "accent": "#c0a0ff", "coat": "#4a2058", "club": "#3a2a20",
                            "scarf": "#c0a0ff"},
                  {"hair_style": "bun", "coat": True, "club": True, "scarf": True, "melee": False, "scale": 0.94}),
    "drone": ("drone", {"shell": "#c8a440", "metal": "#5a5a6a", "emblem": ("#ff3ec8", {"flat": True, "bright": True}), "flash": ("#ff5a7a", {"flat": True, "bright": True})}, {}),
    "grub": ("grub", {"shell": "#8fc84a", "shell2": "#6aa83a", "metal": "#3a4a2a", "mandible": "#f0e0a0"}, {}),
}

BUILDERS = {"human": build_human, "drone": build_drone, "grub": build_grub}


def forge(name):
    kind, colors, cfg = CHARACTERS[name]
    define_mats(colors)
    mats = list(MATS.keys())
    anims = HUMAN_ANIMS if kind == "human" else CREATURE_ANIMS
    rows = []
    meta = {"frame_w": FRAME_W, "frame_h": FRAME_H, "foot_row": FOOT_ROW, "dirs": list(DIRS.keys()), "anims": {}}
    max_frames = max(a[1] for a in anims)
    for (aname, nframes, fps, loop) in anims:
        meta["anims"][aname] = {"fps": fps, "loop": loop, "frames": nframes, "rows": {}}
        for dname, deg in DIRS.items():
            row_imgs = []
            for f in range(nframes):
                t = f / nframes
                DECALS.clear()
                prims = BUILDERS[kind](cfg, deg, aname, t)
                img, matmap, depth = render(prims, mats)
                row_imgs.append(paint_decals(outline(img, matmap, depth, mats), depth))
            meta["anims"][aname]["rows"][dname] = len(rows)
            rows.append(row_imgs)
    sheet = Image.new("RGBA", (FRAME_W * max_frames, FRAME_H * len(rows)), (0, 0, 0, 0))
    for r, row_imgs in enumerate(rows):
        for c, arr in enumerate(row_imgs):
            sheet.paste(Image.fromarray(arr, "RGBA"), (c * FRAME_W, r * FRAME_H))
    os.makedirs(OUT_DIR, exist_ok=True)
    sheet.save(os.path.join(OUT_DIR, name + ".png"), optimize=True)
    with open(os.path.join(OUT_DIR, name + ".json"), "w") as f:
        json.dump(meta, f, indent=1)
    return sheet.size


def _job(n):
    return n, forge(n)


if __name__ == "__main__":
    from multiprocessing import Pool
    names = sys.argv[1:] or list(CHARACTERS.keys())
    with Pool(min(len(names), os.cpu_count() or 2)) as pool:
        for n, size in pool.imap_unordered(_job, names):
            print("forged", n, size, flush=True)
