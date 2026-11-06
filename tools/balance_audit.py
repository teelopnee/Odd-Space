#!/usr/bin/env python3
"""Balance audit for the critique log (docs/REVIEW.md): weapon DPS and enemy threat at a glance.

    python3 tools/balance_audit.py

Flags outliers: any weapon more than 40% above the median DPS of its slot, and any enemy whose
single attack takes more than 22% of base HP. Numbers ignore crits, weak spots and overclock.
"""
import json
from pathlib import Path
from statistics import median

ROOT = Path(__file__).resolve().parent.parent
E = json.loads((ROOT / "data/enemies.json").read_text())
W = json.loads((ROOT / "data/weapons.json").read_text())
BASE_DMG, FIRE_RATE, HP = 10.0, 4.0, 100.0
COMBO, CTIME = [1.0, 1.15, 2.0], [0.30, 0.30, 0.46]

def melee_dps(w):
    return sum(BASE_DMG * 1.25 * c * w["dmg"] for c in COMBO) / sum(t * w["speed"] for t in CTIME)

def ranged_dps(w):
    per = BASE_DMG * w["dmg"] * w.get("pellets", 1)
    if w.get("special") == "chain":
        per = BASE_DMG * w["dmg"] * (1 + 0.8 + 0.64)
    return per * FIRE_RATE * w.get("rate", 1.0)

for slot, fn in (("melee", melee_dps), ("ranged", ranged_dps)):
    rows = {k: fn(v) for k, v in W[slot].items()}
    med = median(rows.values())
    print(f"== {slot} (median {med:.0f} dps)")
    for k, dps in rows.items():
        flag = "  <-- OUTLIER" if dps > med * 1.4 else ""
        print(f"  {W[slot][k]['name']:16s} {dps:6.1f} dps{flag}")

print("\n== enemies (normal difficulty)")
for k, e in E.items():
    if not isinstance(e, dict):
        continue
    hit = e["damage"] * e.get("burst", 1)
    flag = "  <-- HEAVY HITTER" if hit / HP > 0.22 else ""
    print(f"  {e['name']:18s} hp {e['hp']:4d}  one attack = {hit/HP*100:3.0f}% of your HP  "
          f"telegraph {e.get('telegraph', 0.5):.2f}s{flag}")
