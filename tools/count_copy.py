#!/usr/bin/env python3
"""Count how many distinct lines the copy grammar can produce.

    python3 tools/count_copy.py            # summary of every dialogue family
    python3 tools/count_copy.py news chatter

Counts are exact for the grammar (alternatives x nested symbols); runtime
variables like {planet} or {target} are counted once even though they add more
variety in game (every planet, NPC, crew member and saga villain is different).
"""
import json, re, sys
from functools import lru_cache
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FILES = ["data/copy.json", "data/copy_people.json", "data/copy_reactions.json"]
RULES = {}
for f in FILES:
    for k, v in json.loads((ROOT / f).read_text())["rules"].items():
        RULES.setdefault(k, []).extend(v)
SYM = re.compile(r"#([a-z_]+)(?:\.([a-z]+))?#")


@lru_cache(maxsize=None)
def count_text(text: str) -> int:
    n = 1
    for m in SYM.finditer(text):
        n *= count_sym(m.group(1))
    return n


@lru_cache(maxsize=None)
def count_sym(sym: str) -> int:
    return sum(count_text(alt) for alt in RULES.get(sym, [sym]))


def total(prefix: str) -> int:
    return sum(count_sym(k) for k in RULES if k.startswith(prefix))


def main() -> None:
    if len(sys.argv) > 1:
        for s in sys.argv[1:]:
            print(f"{s:28s} {count_sym(s):>18,}")
        return
    react = json.loads((ROOT / "data/reactions.json").read_text())
    kinds = sorted({k for k in RULES if k.startswith("act_")})
    stances = ["approve", "disapprove", "fear", "amused"]
    moods = ["warm", "neutral", "cold", "afraid"]
    voices = [k[6:] for k in RULES if k.startswith("close_")]

    def judge(kind, st):
        k = f"judge_{kind}_{st}"
        return count_sym(k) if k in RULES else count_sym(f"judge_{st}")

    closes = sum(count_sym(f"close_{v}") for v in voices)
    opens = sum(count_sym(f"open_{m}") for m in moods)
    topics = sum(count_sym(k) for k in RULES if k.startswith("pc_") or k == "npc_life")
    remarks = topics * (1 + opens) * (1 + closes)
    now = sum(count_sym(f"now_{k[4:]}") * sum(judge(k[4:], s) for s in stances) for k in kinds) * (1 + closes)
    recall = count_sym("recall_open") * sum(count_sym(k) * sum(judge(k[4:], s) for s in stances) for k in kinds)
    gossip = count_sym("gossip_open") * sum(count_sym(k) * sum(judge(k[4:], s) for s in stances) for k in kinds)
    aside = count_sym("aside_open") * sum(count_sym(k) * sum(judge(k[4:], s) for s in stances) for k in kinds)
    after = sum(count_sym(k) for k in RULES if k.startswith("after_")) * (1 + closes)
    # Whole exchanges: verb outcome line x afterword x the NPC's counter-move x your reply.
    verbs = json.loads((ROOT / "data/interactions.json").read_text())["verbs"]
    counters = json.loads((ROOT / "data/counters.json").read_text())
    vkind = react["verb_kind"]

    def tpl_paths(tpls):
        total = 0
        for t in tpls:
            asks = sum(count_text(a) for a in t["ask"])
            replies = sum(sum(count_text(r) for r in c.get("reply", [])) + sum(count_text(r) for r in c.get("fail_reply", []))
                          for c in t["choices"])
            total += asks * replies
        return total

    exchanges = 0
    for vid, v in verbs.items():
        kind = vkind.get(vid, "talk")
        for outcome, key in (("success", "ok"), ("fail", "fail")):
            if outcome not in v:
                continue
            lines = sum(count_text(l) for l in v[outcome].get("lines", ["..."]))
            aft = 1 + count_sym(f"after_{kind}_{key}") if f"after_{kind}_{key}" in RULES else 1
            exchanges += lines * aft * max(1, tpl_paths(counters["counters"].get(f"{kind}_{key}", [])))
    approaches = sum(tpl_paths(v) for v in counters["approach"].values())
    rows = [
        ("interaction exchanges", exchanges),
        ("NPCs coming to you", approaches),
        ("NPC remarks about you", remarks),
        ("bystander reactions (seen)", now),
        ("memories brought up later", recall),
        ("street gossip about you", gossip),
        ("muttered asides", aside),
        ("interaction afterwords", after),
        ("small talk + replies", count_sym("chatter") + count_sym("reply")),
        ("venue greetings", sum(count_sym(k) * count_sym(k[:-6] + "_keeper")
            for k in RULES if k.endswith("_scene") and k[:-6] + "_keeper" in RULES)),
        ("news headlines", count_sym("news")),
        ("ads (headline x body)", count_sym("headline") * count_sym("ad_body")),
        ("slogans", count_sym("slogan")),
        ("radio", count_sym("radio")),
        ("PA announcements", count_sym("pa")),
        ("flyers + graffiti", count_sym("flyer") + count_sym("graffiti")),
    ]
    width = max(len(r[0]) for r in rows)
    for name, n in rows:
        print(f"{name:{width}s} {n:>22,}")
    print(f"{'TOTAL':{width}s} {sum(n for _, n in rows):>22,}")
    print(f"\n{len(RULES)} symbols, {sum(len(v) for v in RULES.values())} hand-written alternatives, "
          f"{len(kinds)} act kinds x {len(stances)} stances x {len(voices)} voices x {len(moods)} moods")


if __name__ == "__main__":
    main()
