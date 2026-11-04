#!/usr/bin/env python3
"""Placeholder HD-2D pixel-art generator for ODD-SPACE.

Writes 6x7-frame sprite sheets (32x40 px per frame) to assets/sprites/characters/
and small tiling textures to assets/textures/.  Replace any PNG with real art
that keeps the same sheet layout (see src/actors/billboard_sprite.gd):

  row 0 idle(4) | 1 walk(6) | 2 roll/windup(4) | 3 attack(3)
  row 4 guard/stagger(2) | 5 hurt(2) | 6 down/dead(3)

Usage:  python3 tools/gen_sprites.py      (needs Pillow)
"""
import math
import os
import random

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHAR_DIR = os.path.join(ROOT, "assets", "sprites", "characters")
TEX_DIR = os.path.join(ROOT, "assets", "textures")
FW, FH = 32, 40
COLS, ROWS = 6, 7
OUTLINE = (20, 10, 30, 255)


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + (c[3],)


class Canvas:
    def __init__(self):
        self.img = Image.new("RGBA", (FW, FH), (0, 0, 0, 0))
        self.px = self.img.load()

    def put(self, x, y, c):
        if 0 <= x < FW and 0 <= y < FH:
            self.px[x, y] = c

    def rect(self, x0, y0, x1, y1, c, shade_rows=True):
        """Filled rect, inclusive, with a lit top row and a darker bottom row."""
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                col = c
                if shade_rows and y1 - y0 >= 2:
                    if y == y0:
                        col = shade(c, 1.18)
                    elif y == y1:
                        col = shade(c, 0.78)
                self.put(x, y, col)

    def circle(self, cx, cy, r, c):
        for y in range(int(cy - r - 1), int(cy + r + 2)):
            for x in range(int(cx - r - 1), int(cx + r + 2)):
                d = math.hypot(x - cx, y - cy)
                if d <= r:
                    lit = 1.2 if (x - cx) + (y - cy) < -r * 0.5 else (0.8 if (x - cx) + (y - cy) > r * 0.6 else 1.0)
                    self.put(x, y, shade(c, lit))

    def outline(self):
        src = self.img.copy()
        sp = src.load()
        for y in range(FH):
            for x in range(FW):
                if sp[x, y][3] == 0:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < FW and 0 <= ny < FH and sp[nx, ny][3] > 0 and sp[nx, ny] != OUTLINE:
                            self.px[x, y] = OUTLINE
                            break


# --- Humanoid --------------------------------------------------------------------------

def draw_humanoid(cv, p, pose):
    """pose: dict(bob, leg_a, leg_b, arm, lean, lift_a, lift_b, gun, flash, shield, tint)"""
    bob = pose.get("bob", 0)
    lean = pose.get("lean", 0)
    big = p.get("big", False)
    skin, hair = hexc(p["skin"]), hexc(p["hair"])
    body, legs = hexc(p["body"]), hexc(p.get("legs", p["body"]))
    accent = hexc(p.get("accent", "#ffd23e"))
    boots = hexc(p.get("boots", "#2a2030"))
    tint = pose.get("tint")

    def t(c):
        if tint is None:
            return c
        return tuple(int(c[i] * (1 - tint[3]) + tint[i] * tint[3]) for i in range(3)) + (255,)

    tx0, tx1 = (9, 22) if big else (12, 20)
    # Back pack / jetpack (behind the body, on the left = back when facing right).
    pack = p.get("pack")
    if pack == "jetpack":
        cv.rect(tx0 - 4 + lean, 17 + bob, tx0 - 1 + lean, 26 + bob, t(hexc("#7a8090")))
        cv.rect(tx0 - 4 + lean, 27 + bob, tx0 - 2 + lean, 28 + bob, t(hexc("#ff7a2a")))
    elif pack == "bag":
        cv.rect(tx0 - 3 + lean, 18 + bob, tx0 - 1 + lean, 25 + bob, t(hexc("#5a4a3a")))
    elif pack == "tank":
        cv.rect(tx0 - 3 + lean, 16 + bob, tx0 - 1 + lean, 27 + bob, t(hexc("#4ad0ff")))
    # Legs.
    la, lb = pose.get("leg_a", 0), pose.get("leg_b", 0)
    ya, yb = pose.get("lift_a", 0), pose.get("lift_b", 0)
    lx = (12, 17) if big else (13, 17)
    lw = 4 if big else 2
    for (x, off, lift) in ((lx[0], la, ya), (lx[1], lb, yb)):
        cv.rect(x + off, 27 + bob - lift, x + off + lw, 36 - lift, t(legs))
        cv.rect(x + off, 36 - lift, x + off + lw + 1, 39 - lift, t(boots), False)
    # Torso.
    cv.rect(tx0 + lean, 16 + bob, tx1 + lean, 27 + bob, t(body))
    if p.get("coat"):
        cv.rect(tx0 - 1 + lean, 22 + bob, tx1 + 1 + lean, 30 + bob, t(hexc(p["coat"])))
    cv.rect(tx0 + lean, 25 + bob, tx1 + lean, 25 + bob, t(accent), False)  # belt
    if p.get("emblem"):
        cv.rect(tx1 - 3 + lean, 18 + bob, tx1 - 2 + lean, 19 + bob, t(hexc(p["emblem"])), False)
    # Back arm.
    cv.rect(tx0 - 1 + lean, 17 + bob, tx0 + lean, 24 + bob, t(shade(body, 0.75)))
    # Head.
    hx0, hy0 = 12 + lean, 5 + bob
    if p.get("robot"):
        cv.rect(hx0, hy0 + 1, hx0 + 9, hy0 + 10, t(hexc("#9aa4b8")))
        cv.rect(hx0 + 3, hy0 + 3, hx0 + 9, hy0 + 8, t(hexc("#3ee6ff")), False)
        cv.put(hx0 + 7, hy0 + 5, (10, 20, 40, 255))
        cv.rect(hx0 + 4, hy0 - 2, hx0 + 4, hy0, t(hexc("#c0c8d8")), False)
        cv.put(hx0 + 4, hy0 - 3, hexc("#ff3e5a"))
    else:
        cv.rect(hx0 + 1, hy0 + 1, hx0 + 9, hy0 + 10, t(skin))
        cv.rect(hx0 + 2, hy0 + 11, hx0 + 6, hy0 + 11, t(shade(skin, 0.8)), False)  # neck/chin
        # Eye + mouth (facing right).
        cv.put(hx0 + 7, hy0 + 5, (25, 15, 35, 255))
        cv.put(hx0 + 7, hy0 + 4, (25, 15, 35, 255))
        cv.put(hx0 + 8, hy0 + 8, shade(skin, 0.6))
        style = p.get("hair_style", "short")
        if style != "bald":
            cv.rect(hx0, hy0, hx0 + 9, hy0 + 2, t(hair), False)
            cv.rect(hx0, hy0, hx0 + 3, hy0 + 7, t(hair), False)
        if style == "long":
            cv.rect(hx0 - 1, hy0 + 2, hx0 + 2, hy0 + 13, t(hair), False)
        elif style == "mohawk":
            cv.rect(hx0 + 3, hy0 - 3, hx0 + 6, hy0, t(hair), False)
        elif style == "bun":
            cv.circle(hx0 + 1, hy0, 2.2, t(hair))
        elif style == "spiky":
            for i in range(0, 10, 3):
                cv.rect(hx0 + i, hy0 - 2, hx0 + i + 1, hy0, t(hair), False)
        if p.get("helmet"):
            cv.rect(hx0, hy0 - 1, hx0 + 10, hy0 + 6, t(hexc(p["helmet"])))
            cv.rect(hx0 + 5, hy0 + 3, hx0 + 10, hy0 + 6, t(hexc(p.get("visor", "#3ee6ff"))), False)
        if p.get("hat"):
            cv.rect(hx0 - 1, hy0 - 2, hx0 + 10, hy0 + 1, t(hexc(p["hat"])), False)
            cv.rect(hx0 + 4, hy0 + 1, hx0 + 12, hy0 + 1, t(hexc(p["hat"])), False)
        if p.get("visor") and not p.get("helmet"):
            cv.rect(hx0 + 5, hy0 + 3, hx0 + 9, hy0 + 5, t(hexc(p["visor"])), False)
        if p.get("beard"):
            cv.rect(hx0 + 4, hy0 + 8, hx0 + 9, hy0 + 11, t(hexc(p["beard"])), False)
    # Front arm + weapon.
    arm = pose.get("arm", "down")
    ac = t(shade(body, 1.05))
    if arm == "down":
        cv.rect(tx1 - 1 + lean, 17 + bob, tx1 + 1 + lean, 25 + bob, ac)
        cv.rect(tx1 - 1 + lean, 26 + bob, tx1 + 1 + lean, 27 + bob, t(skin), False)
        if p.get("gun"):
            cv.rect(tx1 + lean, 25 + bob, tx1 + 4 + lean, 26 + bob, t(hexc("#3a3a4a")), False)
    elif arm == "forward":
        cv.rect(tx1 - 1 + lean, 18 + bob, tx1 + 5 + lean, 20 + bob, ac)
        cv.rect(tx1 + 6 + lean, 18 + bob, tx1 + 7 + lean, 20 + bob, t(skin), False)
        if p.get("gun"):
            cv.rect(tx1 + 5 + lean, 17 + bob, tx1 + 11 + lean, 19 + bob, t(hexc("#3a3a4a")), False)
            cv.put(tx1 + 11 + lean, 17 + bob, hexc("#ff3ec8"))
            if pose.get("flash"):
                cv.circle(tx1 + 13 + lean, 18 + bob, 2.2, hexc("#fff4a0"))
        elif p.get("club"):
            cv.rect(tx1 + 6 + lean, 12 + bob, tx1 + 8 + lean, 20 + bob, t(hexc("#5a4030")), False)
    elif arm == "up":
        cv.rect(tx1 - 1 + lean, 12 + bob, tx1 + 1 + lean, 19 + bob, ac)
        cv.rect(tx1 - 1 + lean, 10 + bob, tx1 + 1 + lean, 11 + bob, t(skin), False)
        if p.get("club"):
            cv.rect(tx1 - 4 + lean, 4 + bob, tx1 - 2 + lean, 11 + bob, t(hexc("#5a4030")), False)
    if pose.get("shield"):
        for y in range(10, 34):
            cv.put(tx1 + 5 + lean, y + bob, hexc("#7dffff", 230))
            if y % 2 == 0:
                cv.put(tx1 + 6 + lean, y + bob, hexc("#3ee6ff", 180))


def humanoid_frame(p, anim, i):
    cv = Canvas()
    gun = p.get("gun", False)
    if anim == "idle":
        draw_humanoid(cv, p, {"bob": 1 if i in (2, 3) else 0, "arm": "down"})
    elif anim == "walk":
        cycle = [(-2, 2, 1, 0), (-1, 1, 0, 0), (0, 0, 0, 1), (2, -2, 0, 1), (1, -1, 0, 0), (0, 0, 1, 0)][i]
        draw_humanoid(cv, p, {"bob": 1 if i in (1, 4) else 0, "leg_a": cycle[0], "leg_b": cycle[1],
                              "lift_a": cycle[2], "lift_b": cycle[3], "arm": "down"})
    elif anim == "roll":
        body = hexc(p["body"])
        cy = [30, 31, 31, 30][i]
        cv.circle(16, cy, 7.5, body)
        ang = i * math.pi / 2
        hx, hy = 16 + int(4 * math.cos(ang)), cy + int(4 * math.sin(ang))
        cv.circle(hx, hy, 3.2, hexc(p["skin"]) if not p.get("robot") else hexc("#9aa4b8"))
        cv.circle(16 - int(4 * math.cos(ang)), cy - int(4 * math.sin(ang)), 2.0, hexc(p.get("hair", "#333333")))
        if i in (1, 2):
            for k in range(3):
                cv.put(5 + k * 2, cy - 4 + k * 3, hexc("#ffffff", 120))
    elif anim == "attack":
        draw_humanoid(cv, p, {"arm": "forward" if gun or i > 0 else "up", "flash": i == 0 and gun, "lean": 1 if i == 0 else 0})
    elif anim == "guard":
        draw_humanoid(cv, p, {"arm": "forward", "shield": True, "lean": -1 if i == 1 else 0})
    elif anim == "hurt":
        draw_humanoid(cv, p, {"lean": -2, "arm": "up", "tint": (255, 255, 255, 0.35 if i == 0 else 0.1)})
    elif anim == "dead":
        if i == 0:
            draw_humanoid(cv, p, {"lean": -3, "bob": 2, "arm": "up"})
        else:
            body = hexc(p["body"])
            y0 = 33 if i == 1 else 35
            cv.rect(6, y0, 22, y0 + 4, body)
            cv.rect(23, y0 - 1, 29, y0 + 4, hexc(p["skin"]) if not p.get("robot") else hexc("#9aa4b8"))
            cv.rect(23, y0 - 1, 29, y0, hexc(p.get("hair", "#333333")), False)
            cv.rect(1, y0 + 1, 5, y0 + 3, hexc(p.get("legs", p["body"])))
    cv.outline()
    return cv.img


# --- Non-humanoids ----------------------------------------------------------------------

def drone_frame(p, anim, i):
    cv = Canvas()
    shell = hexc(p.get("body", "#c0a040"))
    bob = [0, 1, 1, 0, -1, 0][i % 6] if anim in ("idle", "walk") else 0
    cy = 16 + bob
    if anim == "dead":
        cy = 30 + i * 2
    cv.circle(15, cy, 8, shell if anim != "hurt" else hexc("#ffffff"))
    cv.rect(5, cy - 1, 25, cy + 1, shade(shell, 0.7), False)
    lens = hexc("#ff3e5a") if anim in ("windup", "attack") else hexc(p.get("eye", "#3ee6ff"))
    cv.circle(19, cy - 1, 3, (20, 10, 30, 255))
    cv.circle(19, cy - 1, 2, lens)
    cv.rect(13, cy - 12, 13, cy - 8, hexc("#8a8a9a"), False)
    cv.put(13, cy - 13, hexc("#ff3ec8"))
    if anim != "dead":
        cv.rect(4, cy + 4, 7, cy + 6, hexc("#7a8090"), False)
        cv.rect(4, cy + 7, 6, cy + 8 + (i % 2), hexc("#3ee6ff"), False)
    if anim == "attack" and i == 0:
        cv.circle(26, cy - 1, 2.5, hexc("#fff4a0"))
    cv.outline()
    return cv.img


def grub_frame(p, anim, i):
    cv = Canvas()
    col = hexc(p.get("body", "#9ad04a"))
    segs = 5
    for s in range(segs):
        phase = (i if anim == "walk" else 0) * 1.2 + s * 1.3
        x = 6 + s * 4
        y = 33 - int(1.5 * math.sin(phase)) if anim != "dead" else 36
        r = 3.5 if s < segs - 1 else 4.5
        c = col if anim != "hurt" else hexc("#ffffff")
        cv.circle(x, y, r, shade(c, 0.85 + 0.05 * s))
    hx = 6 + (segs - 1) * 4
    if anim != "dead":
        cv.put(hx + 2, 31, (20, 10, 30, 255))
        open_jaw = anim in ("windup", "attack")
        cv.rect(hx + 4, 33 - (2 if open_jaw else 0), hx + 6, 33 - (2 if open_jaw else 0), hexc("#f0e0a0"), False)
        cv.rect(hx + 4, 35 + (1 if open_jaw else 0), hx + 6, 35 + (1 if open_jaw else 0), hexc("#f0e0a0"), False)
        if anim == "windup":
            cv.rect(hx - 2, 26, hx, 27, hexc("#ff7a2a"), False)
    cv.outline()
    return cv.img


ANIMS = [("idle", 4), ("walk", 6), ("roll", 4), ("attack", 3), ("guard", 2), ("hurt", 2), ("dead", 3)]


def build_sheet(name, frame_fn, params):
    sheet = Image.new("RGBA", (FW * COLS, FH * ROWS), (0, 0, 0, 0))
    for row, (anim, count) in enumerate(ANIMS):
        for i in range(count):
            sheet.paste(frame_fn(params, anim, i), (i * FW, row * FH))
    path = os.path.join(CHAR_DIR, name + ".png")
    sheet.save(path)
    return path


CHARACTERS = {
    "player": dict(skin="#f1c27d", hair="#2ad0c0", hair_style="spiky", body="#ff8c2a", legs="#d06a1a", accent="#3ee6ff", pack="bag", gun=True, emblem="#3ee6ff"),
    "officer": dict(skin="#d8a070", hair="#202020", body="#28367a", legs="#1c2450", accent="#e8ecff", helmet="#e8ecff", visor="#3ee6ff", pack="jetpack", gun=True, emblem="#4a6dff"),
    "pirate": dict(skin="#c08060", hair="#ff3ec8", hair_style="mohawk", body="#6a3a2a", legs="#3a2a20", accent="#ffd23e", coat="#4a2a1a", pack="jetpack", gun=True),
    "brute": dict(skin="#b07050", hair="#1a1a1a", hair_style="bald", body="#5a4a20", legs="#3a3020", accent="#ffd23e", big=True, club=True, emblem="#ffd23e"),
    "civilian_a": dict(skin="#e0b080", hair="#5a3a20", body="#5a6a8a", legs="#3a4a6a", accent="#a0a0b0"),
    "civilian_b": dict(skin="#8a5a3a", hair="#000000", hair_style="bald", body="#3a7a4a", legs="#2a4a30", accent="#c0d080", beard="#2a2020"),
    "civilian_c": dict(skin="#f0d0b0", hair="#f0d060", hair_style="long", body="#7a3a8a", legs="#3a2a4a", accent="#ff3ec8"),
    "merchant": dict(skin="#d09060", hair="#6a4a2a", body="#c09030", legs="#4a3a2a", accent="#ffffff", hat="#a03030", beard="#6a4a2a", pack="bag"),
    "crew_vex": dict(skin="#6a4030", hair="#101010", body="#20306a", legs="#18204a", accent="#ffd23e", gun=True, emblem="#ffd23e"),
    "crew_nuggets": dict(skin="#f0c090", hair="#e03a2a", hair_style="bun", body="#d9a24a", legs="#b07a2a", accent="#ff5a2a", big=True),
    "crew_pip": dict(skin="#d0a080", hair="#3a2a1a", body="#2a4a3a", legs="#1a2a20", accent="#ffd23e", coat="#20382a", hat="#20201a", gun=True),
    "crew_varga": dict(skin="#f0d8c8", hair="#b0b0b0", hair_style="bun", body="#e8e8f0", legs="#8a8aa0", accent="#ff3e5a", emblem="#ff3e5a"),
    "crew_kevin": dict(skin="#9aa4b8", hair="#9aa4b8", body="#8a94a8", legs="#6a7488", accent="#3ee6ff", robot=True, emblem="#ff3ec8"),
    "crew_rook": dict(skin="#e0c0a0", hair="#f0f0f0", hair_style="bun", body="#5a2a6a", legs="#3a1a4a", accent="#c0a0ff", coat="#4a2058", club=True),
}


# --- Tiling textures ---------------------------------------------------------------------

def noise_tex(name, size, base, fn):
    img = Image.new("RGBA", (size, size), base)
    px = img.load()
    rnd = random.Random(sum(map(ord, name)))
    for y in range(size):
        for x in range(size):
            px[x, y] = fn(x, y, rnd, px[x, y])
    img.save(os.path.join(TEX_DIR, name + ".png"))


def build_textures():
    os.makedirs(TEX_DIR, exist_ok=True)

    def floor(x, y, r, c):
        v = 200 + r.randint(-10, 10)
        if x % 16 in (0, 15) or y % 16 in (0, 15):
            v -= 70
        if (x % 16, y % 16) in ((3, 3), (12, 3), (3, 12), (12, 12)):
            v += 40
        if 6 <= x % 16 <= 9 and y % 16 == 8:
            v -= 30
        return (v, v, min(255, v + 12), 255)
    noise_tex("floor_metal", 32, (200, 200, 210, 255), floor)

    def wall(x, y, r, c):
        v = 190 + r.randint(-8, 8)
        if y % 16 == 0 or x % 32 == 0:
            v -= 80
        if y % 16 == 1:
            v += 30
        if x % 32 in (4, 27) and y % 16 in (4, 11):
            v += 50
        return (v, v, v + 8 if v < 247 else 255, 255)
    noise_tex("wall_panel", 32, (190, 190, 200, 255), wall)

    def crate(x, y, r, c):
        v = 180 + r.randint(-12, 12)
        if x in (0, 1, 30, 31) or y in (0, 1, 30, 31):
            v = 120
        elif x == y or x == 31 - y:
            v = 140
        elif y % 6 == 0:
            v -= 25
        return (v, int(v * 0.85), int(v * 0.6), 255)
    noise_tex("crate", 32, (180, 150, 100, 255), crate)

    def ground(x, y, r, c):
        v = 170 + r.randint(-25, 25)
        if r.random() < 0.05:
            v -= 60
        return (v, v, v, 255)
    noise_tex("ground_rock", 32, (170, 170, 170, 255), ground)

    def cliff(x, y, r, c):
        v = 150 + r.randint(-20, 20) + int(20 * math.sin(y * 0.6 + x * 0.15))
        if (y + x // 6) % 9 == 0:
            v -= 50
        return (v, v, v, 255)
    noise_tex("rock_cliff", 32, (150, 150, 150, 255), cliff)

    def building(x, y, r, c):
        v = 185 + r.randint(-6, 6)
        if y % 8 == 0:
            v -= 60
        if x % 16 == 0:
            v -= 40
        return (v, v, v + 6, 255)
    noise_tex("building_panel", 32, (185, 185, 190, 255), building)

    def hazard(x, y, r, c):
        stripe = ((x + y) // 4) % 2 == 0
        return (255, 210, 60, 255) if stripe else (40, 30, 40, 255)
    noise_tex("hazard", 32, (255, 210, 60, 255), hazard)


def build_icon():
    """Simple duck-ship icon (SVG) for the project."""
    svg = """<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2a0a40"/><stop offset="1" stop-color="#ff3ec8"/></linearGradient></defs>
<rect width="128" height="128" rx="20" fill="#07031a"/>
<circle cx="64" cy="70" r="40" fill="url(#g)"/>
<g fill="#07031a"><rect x="20" y="78" width="88" height="5"/><rect x="20" y="90" width="88" height="6"/><rect x="20" y="102" width="88" height="7"/></g>
<ellipse cx="60" cy="62" rx="30" ry="14" fill="#ffb030" stroke="#140a1e" stroke-width="4"/>
<circle cx="86" cy="50" r="11" fill="#ffb030" stroke="#140a1e" stroke-width="4"/>
<circle cx="89" cy="47" r="4" fill="#3ee6ff"/>
<path d="M96 52 L112 55 L96 59 Z" fill="#ff6a1a" stroke="#140a1e" stroke-width="3"/>
<rect x="24" y="58" width="10" height="9" fill="#3ee6ff"/>
</svg>"""
    with open(os.path.join(ROOT, "icon.svg"), "w") as f:
        f.write(svg)


def main():
    os.makedirs(CHAR_DIR, exist_ok=True)
    for name, params in CHARACTERS.items():
        build_sheet(name, humanoid_frame, params)
    build_sheet("drone", drone_frame, {"body": "#c0a040", "eye": "#3ee6ff"})
    build_sheet("grub", grub_frame, {"body": "#9ad04a"})
    build_textures()
    build_icon()
    print("sprites + textures written")


if __name__ == "__main__":
    main()
