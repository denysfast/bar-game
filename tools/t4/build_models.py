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
