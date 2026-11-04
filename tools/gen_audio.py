#!/usr/bin/env python3
"""Placeholder audio generator for ODD-SPACE (needs numpy).

Music = synthwave (detuned saw pads, arps, gated drums) + Karplus-Strong
plucked strings (koto/lute-like "ancient strings") -> retro-future + lonely.
All loops are rendered with their echo tails folded back to the start so they
loop seamlessly in Godot.  Replace with real tracks anytime: keep file names.

Usage:  python3 tools/gen_audio.py
"""
import os
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MUSIC_DIR = os.path.join(ROOT, "assets", "audio", "music")
SFX_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
SR = 22050
rng = np.random.default_rng(3032)


def write_wav(path, data):
    data = np.clip(data, -1.0, 1.0)
    pcm = (data * 32767 * 0.9).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


def t_arr(dur):
    return np.arange(int(dur * SR)) / SR


def saw(f, t, phase=0.0):
    return 2.0 * ((f * t + phase) % 1.0) - 1.0


def square(f, t, duty=0.5):
    return np.where((f * t) % 1.0 < duty, 1.0, -1.0)


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def env_adsr(n, a=0.01, d=0.1, s=0.7, r=0.1):
    e = np.ones(n) * s
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    na = max(1, min(na, n))
    e[:na] = np.linspace(0, 1, na)
    nd2 = max(0, min(nd, n - na))
    if nd2:
        e[na:na + nd2] = np.linspace(1, s, nd2)
    nr = min(nr, n)
    if nr:
        e[n - nr:] *= np.linspace(1, 0, nr)
    return e


def pluck(freq, dur, bright=0.5, decay=0.996):
    """Karplus-Strong plucked string."""
    n = int(dur * SR)
    period = max(2, int(SR / freq))
    buf = rng.uniform(-1, 1, period)
    buf = lowpass(buf, 2000 + 6000 * bright)
    out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % period]
        nxt = buf[(i + 1) % period]
        buf[i % period] = decay * 0.5 * (buf[i % period] + nxt)
    return out


def add(dst, src, start, gain=1.0):
    s = int(start * SR)
    if s >= len(dst):
        return
    e = min(len(dst), s + len(src))
    dst[s:e] += src[: e - s] * gain


def echo(x, delay, fb, mix):
    d = int(delay * SR)
    y = x.copy()
    for i in range(d, len(y)):
        y[i] += y[i - d] * fb
    return x * (1 - mix) + y * mix


def kick():
    t = t_arr(0.35)
    f = 50 + 120 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)


def snare():
    t = t_arr(0.25)
    noise = lowpass(rng.uniform(-1, 1, len(t)), 5000)
    return (noise * 0.8 + np.sin(2 * np.pi * 190 * t) * 0.4) * np.exp(-t * 18)


def hat():
    t = t_arr(0.06)
    n = rng.uniform(-1, 1, len(t))
    n = n - lowpass(n, 6000)
    return n * np.exp(-t * 60)


def render_song(bpm, bars, chords, melody, drums=True, dark=False):
    beat = 60.0 / bpm
    bar = beat * 4
    total = bar * (bars + 1)
    out = np.zeros(int(total * SR))
    for b in range(bars):
        chord = chords[b % len(chords)]
        t0 = b * bar
        # Pad: 3 detuned saws per chord tone, slow swell.
        tt = t_arr(bar + 0.3)
        pad = np.zeros(len(tt))
        for n in chord:
            for det in (-0.12, 0.0, 0.11):
                pad += saw(midi(n + 12 + det), tt, rng.random())
        pad = lowpass(pad / (len(chord) * 3), 900 if dark else 1400)
        add(out, pad * env_adsr(len(tt), 0.4, 0.3, 0.8, 0.5), t0, 0.32)
        # Bass: 8th notes, root with octave bounce.
        for k in range(8):
            note = chord[0] - 12 + (12 if k % 4 == 3 else 0)
            bt = t_arr(beat * 0.45)
            tone = lowpass(saw(midi(note), bt), 500) * env_adsr(len(bt), 0.005, 0.1, 0.6, 0.05)
            add(out, tone, t0 + k * beat / 2, 0.42 if not dark else 0.3)
        # Arp: 16ths over chord tones (skip in dark mode on odd bars).
        if not dark or b % 2 == 0:
            tones = chord + [chord[0] + 12]
            for k in range(16):
                n = tones[k % len(tones)] + 24
                at = t_arr(beat * 0.2)
                tone = square(midi(n), at, 0.25) * env_adsr(len(at), 0.002, 0.05, 0.3, 0.05)
                add(out, lowpass(tone, 3000), t0 + k * beat / 4, 0.07)
        # Drums.
        if drums:
            for k in range(4):
                add(out, kick(), t0 + k * beat, 0.55)
                add(out, hat(), t0 + k * beat + beat / 2, 0.2)
                if k in (1, 3):
                    add(out, snare(), t0 + k * beat, 0.35)
        elif dark and b % 2 == 0:
            add(out, kick(), t0, 0.35)
    # Melody on plucked "ancient strings" (koto/lute feel).
    for (bar_i, beat_i, note, length) in melody:
        if bar_i < bars:
            add(out, pluck(midi(note), length * beat + 0.8, 0.6, 0.997), bar_i * bar + beat_i * beat, 0.5)
    out = echo(out, beat * 0.75, 0.35, 0.35)
    # Fold the tail (last extra bar) back to the start for a seamless loop.
    loop_len = int(bar * bars * SR)
    tail = out[loop_len:]
    out = out[:loop_len]
    out[: len(tail)] += tail
    out /= max(1e-6, np.max(np.abs(out)))
    return out * 0.85


def build_music():
    os.makedirs(MUSIC_DIR, exist_ok=True)
    # A minor: Am F C G  (MIDI roots around A2=45)
    theme_chords = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]
    pent = [69, 72, 74, 76, 79, 81]
    melody = []
    pattern = [(0, 0, 0, 1.5), (0, 1.5, 2, 0.5), (0, 2, 3, 2), (1, 0, 1, 1), (1, 1, 0, 1), (1, 2, 2, 2),
               (2, 0, 4, 1.5), (2, 1.5, 3, 0.5), (2, 2, 2, 2), (3, 0, 1, 1), (3, 1, 2, 1), (3, 2, 0, 2)]
    for rep in range(2):
        for (b, bt, idx, ln) in pattern:
            melody.append((b + rep * 4, bt, pent[idx] + (0 if rep == 0 else 12 if idx < 2 else 0), ln))
    write_wav(os.path.join(MUSIC_DIR, "odd_duck_theme.wav"), render_song(100, 8, theme_chords, melody, drums=True))
    # D minor dark: Dm Bb Gm A
    dark_chords = [[50, 53, 57], [46, 50, 53], [43, 46, 50], [45, 49, 52]]
    dpent = [62, 65, 67, 69, 72, 74]
    dmel = [(0, 0, dpent[3], 3), (1, 1, dpent[2], 2), (2, 0, dpent[0], 3), (3, 2, dpent[1], 2),
            (4, 0, dpent[4], 2), (4, 2, dpent[3], 2), (5, 1, dpent[2], 3), (6, 0, dpent[1], 2), (7, 0, dpent[0], 4)]
    write_wav(os.path.join(MUSIC_DIR, "derelict_ambient.wav"), render_song(84, 8, dark_chords, dmel, drums=False, dark=True))


def sweep(f0, f1, dur, wave_fn="square", decay=8.0):
    t = t_arr(dur)
    f = f0 * (f1 / f0) ** (t / dur)
    ph = np.cumsum(f) / SR
    if wave_fn == "square":
        x = np.where(ph % 1.0 < 0.5, 1.0, -1.0)
    elif wave_fn == "saw":
        x = 2 * (ph % 1.0) - 1
    else:
        x = np.sin(2 * np.pi * ph)
    return x * np.exp(-t * decay)


def noise_burst(dur, cutoff, decay):
    t = t_arr(dur)
    return lowpass(rng.uniform(-1, 1, len(t)), cutoff) * np.exp(-t * decay)


def tone(f, dur, fn="sine", decay=10.0):
    t = t_arr(dur)
    x = np.sin(2 * np.pi * f * t) if fn == "sine" else square(f, t)
    return x * np.exp(-t * decay)


def cat(*parts):
    return np.concatenate(parts)


def mix(*parts):
    """Sum arrays of different lengths (zero-padded)."""
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def build_sfx():
    os.makedirs(SFX_DIR, exist_ok=True)
    sfx = {
        "shoot": sweep(1400, 300, 0.14, "square", 14) * 0.5,
        "enemy_shoot": sweep(700, 150, 0.18, "saw", 12) * 0.5,
        "enemy_hit": mix(noise_burst(0.09, 4000, 30) * 0.7, tone(180, 0.09, "square", 30) * 0.3),
        "hurt": sweep(500, 120, 0.25, "square", 9) * 0.6,
        "parry": mix(sum(tone(f, 0.6, "sine", 6) for f in (1240, 1873, 2611, 3307)) * 0.3, noise_burst(0.05, 8000, 60) * 0.4),
        "parry_swing": noise_burst(0.12, 2500, 25) * 0.4,
        "roll": noise_burst(0.25, 1200, 10) * 0.6,
        "swing": noise_burst(0.18, 1800, 16) * 0.5,
        "explosion": mix(noise_burst(1.1, 900, 3.5) * 0.9, sweep(90, 30, 1.0, "sine", 3) * 0.8),
        "break": mix(noise_burst(0.3, 3000, 12) * 0.7, sweep(300, 80, 0.3, "square", 10) * 0.3),
        "enemy_die": mix(sweep(600, 60, 0.45, "saw", 6) * 0.5, noise_burst(0.3, 2000, 10) * 0.3),
        "radio": cat(tone(1800, 0.06, "square", 5), np.zeros(int(0.05 * SR)), tone(1800, 0.06, "square", 5), np.zeros(int(0.05 * SR)), noise_burst(0.2, 3000, 8) * 0.4) * 0.35,
        "alert": cat(tone(880, 0.12, "square", 4), tone(660, 0.16, "square", 4)) * 0.4,
        "blip": tone(1320, 0.05, "sine", 30) * 0.5,
        "confirm": cat(tone(990, 0.06, "square", 20), tone(1480, 0.1, "square", 15)) * 0.35,
        "coin": cat(tone(1568, 0.06, "square", 18), tone(2093, 0.18, "square", 10)) * 0.35,
        "pickup": cat(*[tone(f, 0.05, "square", 20) for f in (523, 659, 784, 1046)]) * 0.35,
        "heal": sweep(400, 1600, 0.6, "sine", 3) * 0.4,
        "warp": mix(sweep(80, 2400, 1.4, "saw", 1.5) * 0.35, noise_burst(1.4, 2500, 2.0) * 0.3),
    }
    for name, data in sfx.items():
        data = np.asarray(data, dtype=np.float64)
        data /= max(1e-6, np.max(np.abs(data)))
        write_wav(os.path.join(SFX_DIR, name + ".wav"), data * 0.8)


if __name__ == "__main__":
    build_sfx()
    build_music()
    print("audio written")
