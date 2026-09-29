Bench-only render driver for hero portraits (not loaded by the game; copied in by bench.sh).
  W=<worktree> WD=art RES=1200x1200 SCENE_GADGET=$PWD/zz_render_gadget.lua SCENE_WIDGET=$PWD/zz_render_widget.lua \
    /mnt/data/bar-bench/bench.sh scene_all.lua all
Write-dir springsettings: XResolution/YResolution(Windowed) = 1200, SoftParticles = 0.
Crops: 860x860+170+200 (tall bots 1000x1000+100+60), then tools/heroes/renders/<base>.png.
Portraits: art.py edit <out> <render> "$(python3 tools/heroes/portrait_prompts.py <unit>)" --size 256 --seed 11
(corpyro seed 13, legbart seed 23). Contact sheet: tools/heroes/sheet.sh.
