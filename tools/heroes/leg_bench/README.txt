Bench-only scenes of the v19 Legion heroes (not loaded by the game; bench.sh copies them in for a run).
  <hero>.lua      level 100, all ranks 10, every active cast + screenshots of each ability
  ac_<hero>.lua   same hero on autocast (the AI path): which actives fire by themselves
  dps_<hero>.lua  level 1, one 50M-HP target: single-target weapon DPS (damage f140..f440 / 10 s)
Run: S=$PWD/tools/heroes/leg_bench; W=<worktree> WD=cleg SCENE_GADGET=$S/zz_cleg_scene.lua SCENE_WIDGET=$S/zz_cleg_cam.lua \
     /mnt/data/bar-bench/bench.sh $S/helios.lua helios      (or runall.sh with S/worktree paths adjusted)
Write-dir springsettings: SoftParticles = 0. Logs: "[ability] legt4..." lines (game rules param hero_ability_log) and
"[scene] damage ..." (team 0 damage by weapon, w-1 = ability damage).
