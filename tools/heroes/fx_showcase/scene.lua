-- Hero FX showcase: stations, timing and camera shots (shared by the scene gadget and widget).
-- Run: W=<worktree> WD=fx SCENE_GADGET=$W/tools/heroes/fx_showcase/zz_fx_scene.lua \
--      SCENE_WIDGET=$W/tools/heroes/fx_showcase/zz_fx_scene_cam.lua /mnt/data/bar-bench/bench.sh $W/tools/heroes/fx_showcase/scene.lua <tag>
local S = {}
S.first = 150      -- frame of the first station window
S.window = 150     -- frames per station
S.only = nil       -- set to a station name to run just that one
S.stations = {
	{ name = "chain", dx = -1300, dz = -900, shots = { 13, 18, 46, 74 } },
	{ name = "rage", dx = -400, dz = -900, shots = { 20, 62, 101 }, height = 620 },
	{ name = "emp", dx = 500, dz = -900, shots = { 14, 22, 34, 90 } },
	{ name = "sweep", dx = 1400, dz = -900, shots = { 30, 62, 96 } },
	{ name = "shield", dx = -1300, dz = 0, shots = { 22, 52 }, height = 560 },
	{ name = "resurrect", dx = -400, dz = 0, shots = { 16, 36, 70 }, height = 1100 },
	{ name = "cloak", dx = 500, dz = 0, shots = { 40, 75 }, height = 520, follow = true },
	{ name = "drones", dx = 1400, dz = 0, shots = { 22, 57 }, height = 620 },
	{ name = "zones", dx = -1300, dz = 900, shots = { 40, 95 }, height = 1300 },
	{ name = "misc", dx = -400, dz = 900, shots = { 30, 80 }, height = 800 },
	{ name = "los", dx = 500, dz = 900, shots = { 25 }, height = 3000, camDz = 600 },
	{ name = "stress", dx = 1400, dz = 900, shots = { 40, 120 }, height = 1900 },
}
S.quit = S.first + #S.stations * S.window + 10
return S
