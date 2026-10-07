#!/usr/bin/env python3
"""Icons of the faction uniques and set pieces (dev tool): reads luarules/configs/t4_hero_items.lua and runs
art.py icon (Krea 2 on content-master, the shared --style item) for every unique / set piece that has a `faction`
(or belongs to a set listed in --neutral) and no icon yet in bitmaps/t4heroes/items/.

  CM_KEY_FILE=<file with the content-master key> python3 tools/heroes/item_art.py [--jobs 4] [--force] [--only id,id]

Needs the Python package lupa (Lua 5.1) to read the config. Prompt = the item's `art` + a rarity line (unique:
legendary golden aura, set: green set aura) + the faction style line I.factions[f].art + "dark background".
v24 set: generated without the "dark background" tail; re-rolled by hand (art.py icon, same prompt + tail) because of
white rims: u_leg_aquila --seed 977, s_siege_breech 1401, s_siege_core 1402, s_vanguard_jets 1403.
"""
import argparse, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ICONS = os.path.join(ROOT, "bitmaps/t4heroes/items")
ART = os.path.join(ROOT, "tools/heroes/art.py")
RARITY = {
    "u": "legendary relic item with a golden aura and gold trim",
    "s": "set item with a subtle emerald green aura",
}


def load():
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    src = open(os.path.join(ROOT, "luarules/configs/t4_hero_items.lua"), encoding="utf-8").read()
    return L.execute(src)


def jobs(I, neutral):
    out = []
    for u in I.uniques.values():
        if u.faction:
            out.append(("u_" + u.id, u.art, u.faction, "u", int(u.index)))
    for s in I.sets.values():
        if s.faction or s.id in neutral:
            for p in s.pieces.values():
                out.append(("s_" + p.id, p.art, s.faction, "s", int(s.index) * 10 + int(p.index)))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--only", default="")
    ap.add_argument("--neutral", default="warmaster", help="neutral sets that get icons too")
    a = ap.parse_args()
    I = load()
    only = set(filter(None, a.only.split(",")))
    todo = []
    for name, art, faction, kind, seed in jobs(I, set(a.neutral.split(","))):
        out = os.path.join(ICONS, name + ".png")
        if only and name not in only and name[2:] not in only:
            continue
        if os.path.exists(out) and not a.force and not only:
            continue
        style = I.factions[faction].art if faction else "sci-fi war machine hardware"
        todo.append((out, f"{art}, {RARITY[kind]}, {style}, dark background", 300 + seed))

    def run(job):
        out, subject, seed = job
        r = subprocess.run([sys.executable, ART, "icon", out, subject, "--seed", str(seed)], capture_output=True, text=True)
        return out, r.returncode, (r.stderr or r.stdout).strip()[-300:]

    print(f"{len(todo)} icons", flush=True)
    fails = 0
    with ThreadPoolExecutor(a.jobs) as ex:
        for out, rc, msg in ex.map(run, todo):
            print(("ok   " if rc == 0 else "FAIL ") + os.path.basename(out) + ("" if rc == 0 else " " + msg), flush=True)
            fails += rc != 0
    sys.exit(1 if fails else 0)


main()
