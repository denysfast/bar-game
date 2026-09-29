#!/usr/bin/env python3
"""Copy a compiled unit script (.cob) with one aim function made to always allow firing.

    python3 tools/t4/cob_aim_patch.py scripts/Units/legvcarry.cob scripts/Units/legt2swarm.cob AimPrimary

Some stock scripts keep a weapon that only picks targets (carriers: AimPrimary ends in `return (0)`, so the
engine never fires it). A hero built on such a unit needs that weapon to fire; there is no BOS compiler in
the repo, so this patches the bytecode: the last `PUSH_CONSTANT 0; RETURN` of the function becomes
`PUSH_CONSTANT 1; RETURN`. Everything else (pieces, docking callins) stays byte-identical.
"""
import struct
import sys

PUSH_CONSTANT = 0x10021001
RETURN = 0x10065000

src, dst, fn = sys.argv[1], sys.argv[2], sys.argv[3]
b = bytearray(open(src, "rb").read())
(ver, nscripts, _npieces, codelen, _nstatic, _u2, off_idx, off_names, _off_pieces, off_code, _u3) = struct.unpack_from("<11i", b, 0)
starts = struct.unpack_from(f"<{nscripts}i", b, off_idx)
name_offs = struct.unpack_from(f"<{nscripts}i", b, off_names)
names = [b[o:b.index(b"\0", o)].decode() for o in name_offs]
lower = [n.lower() for n in names]
if fn.lower() not in lower:
    sys.exit(f"{fn} not in {names}")
i = lower.index(fn.lower())
start = starts[i]
end = min([s for s in starts if s > start] + [codelen])
code = list(struct.unpack_from(f"<{codelen}i", b, off_code))
patched = None
for w in range(end - 3, start - 1, -1):
    if (code[w] & 0xffffffff) == PUSH_CONSTANT and code[w + 1] == 0 and (code[w + 2] & 0xffffffff) == RETURN:
        patched = w + 1
        break
if patched is None:
    sys.exit(f"{fn}: no 'return (0)' found")
struct.pack_into("<i", b, off_code + patched * 4, 1)
open(dst, "wb").write(b)
print(f"{dst}: {names[i]} returns 1 (word {patched})")
