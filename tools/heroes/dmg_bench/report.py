import re, sys, glob, collections
R = re.compile(r"RESULT hero=(\S+) level=(\d+) key=(\S+) name=(\S+) rank=(\S+) cast=(\S+) dist=(\d+) dmg=(\d+) killed=(\d) killFrame=(\S+) f400=(\S+) other=(\d+) hp_left=(-?\d+) \| ?(.*)")
rows = []
for f in sorted(glob.glob(sys.argv[1] + "/*/infolog.txt")):
    for line in open(f, errors="ignore"):
        m = R.search(line)
        if m: rows.append(m.groups())
base = {(r[0], r[1]): int(r[7]) for r in rows if r[2] == "base"}
out = []
for r in rows:
    if r[2] == "base": continue
    hero, L, key, name, rank, ok, dist, dmg, killed, kf, f400, other, hpl, byw = r
    b = base.get((hero, L), 0)
    net = int(dmg) - b
    out.append((hero, int(L), key, name, ok, int(dmg), b, net, killed == "1", kf, f400, byw))
json_out = []
print(f"{'hero':18} {'L':>3} {'key':4} {'ability':24} {'cast':10} {'dmg':>8} {'base':>7} {'%400k':>6} kill t400")
for o in out:
    hero, L, key, name, ok, dmg, b, net, k, kf, f400, byw = o
    flag = "KILL" if k else ("  >400k" if net >= 400000 else "")
    t = f"{int(f400)/30:.1f}s" if f400 not in ("nil",) else "-"
    print(f"{hero:18} {L:>3} {key:4} {name[:24]:24} {str(ok)[:10]:10} {dmg:>8} {b:>7} {net/4000:>5.0f}% {flag:5} {t}")
