One-cast damage of every active hero ability against a fresh level-1 enemy hero with 400k HP (cort4hellwalker).
Bench-only (run.sh copies zz_herodmg.lua into a snapshot of the worktree; the game never loads it from here).

Per hero and level (50 / 75 / 99): the build is a1/a2/a3 x10, ult as far as the level allows, then dmg, imp, rng,
vit, mob. A "base" job (no cast) measures what passives and summons do alone; every active gets a fresh caster
(hold fire, autocast off) and a fresh target, one cast, 25 s window. WPN=true adds a "wpn" job: the hero's guns
alone on the same target (to tell an ability's own damage from the gun it buffs).

Run on .142 (spring-headless, ~1 min a faction):
  for p in arm cor leg; do tools/heroes/dmg_bench/run.sh $PWD <tag> $p & done; wait
  python3 tools/heroes/dmg_bench/report.py /mnt/data/bar-bench/hdmg/<tag>
Optional 4th arg of run.sh: hero names, comma separated. Infolog lines: "[hdmg] RESULT ..." and "[hdmg] SERIES ..."
(cumulative damage to the target every second).
