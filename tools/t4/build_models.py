#!/usr/bin/env python3
"""Regenerate the custom T4 models (objects3d/Units/T4/) from their T2/T3 sources.
Run from the repo root after changing a scale here or updating an upstream model:

    python3 tools/t4/build_models.py

The scale factors must match `scale` in the units/*T4*/ files (collision volumes, footprints)."""
import os
import subprocess
import sys

# t4 unit      source model (objects3d/Units/<src>.s3o)   scale
MODELS = [
    ("armt4gant",       "armshltx",        1.5),
    ("armt4atlas",      "armbanth",        2.0),
    ("armt4olympus",    "armvang",         2.2),
    ("armt4aegis",      "armraz",          2.0),
    ("armt4zeus",       "armthor",         1.8),
    ("cort4gant",       "corgant",         1.5),
    ("cort4colossus",   "corkorg",         1.8),
    ("cort4bastion",    "corjugg",         1.6),
    ("cort4armageddon", "corcat",          2.0),
    ("cort4hellwalker", "cordemon",        2.0),
    ("legt4gant",       "leggant",         1.5),
    ("legt4helios",     "legeheatraymech", 1.8),
    ("legt4starfall",   "legelrpcmech",    1.6),
    ("legt4longinus",   "legerailtank",    1.8),
    ("legt4tempest",    "legeshotgunmech", 2.0),
    # Armada T2 heroes (units/ArmT2Heroes/armt2heroes.lua) and their hall
    ("armt2hall",       "armalab",         1.3),
    ("armt2boomer",     "armfboy",         1.5),
    ("armt2deadeye",    "armsnipe",        1.6),
    ("armt2outlaw",     "armmav",          1.5),
    ("armt2hound",      "armfido",         1.6),
    ("armt2tesla",      "armzeus",         1.5),
    ("armt2widow",      "armsptk",         1.5),
    ("armt2starlight",  "armmanni",        1.5),
    ("armt2bulldog",    "armbull",         1.5),
    ("armt2envoy",      "armmerl",         1.5),
    ("armt2weaver",     "armspid",         1.6),
    # Cortex T2 heroes (units/CorT2Heroes/cort2heroes.lua)
    ("cort2hall",       "coralab",         1.3),
    ("cort2sumo",       "corsumo",         1.4),
    ("cort2can",        "corcan",          1.5),
    ("cort2pyro",       "corpyro",         1.6),
    ("cort2termite",    "cortermite",      1.5),
    ("cort2arbiter",    "corhrk",          1.5),
    ("cort2sheldon",    "cormort",         1.6),
    ("cort2goliath",    "corgol",          1.4),
    ("cort2tiger",      "correap",         1.5),
    ("cort2banisher",   "corban",          1.4),
    ("cort2tremor",     "cortrem",         1.4),
]

here = os.path.dirname(os.path.abspath(__file__))
src_dir = "objects3d/Units"
dst_dir = "objects3d/Units/T4"
os.makedirs(dst_dir, exist_ok=True)
for name, src, k in MODELS:
    for suffix in ("", "_dead"):
        s = f"{src_dir}/{src}{suffix}.s3o"
        if not os.path.exists(s):
            if suffix:
                continue
            sys.exit(f"missing {s}")
        subprocess.run([sys.executable, f"{here}/scale_s3o.py", s, f"{dst_dir}/{name}{suffix}.s3o", str(k)], check=True)
