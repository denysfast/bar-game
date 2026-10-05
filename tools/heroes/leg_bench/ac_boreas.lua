return {
	hero = "legt4boreas", level = 100, learn = { "a1x10", "a2x10", "a3x10", "ultx10" }, autocast = true,
	hold = true, immortal = true, globalLos = true, heroZ = -300,
	groups = {
		{ unit = "corsumo", n = 10, x = 0, z = 1500, spread = 300, hpMax = 80000 },
		{ unit = "armt4atlas", n = 1, x = 300, z = 1700, team = 1 },
		{ unit = "corak", n = 6, x = 100, z = 0, spread = 100, hp = 0.15, mortal = true },
		{ unit = "corjugg", n = 1, x = -400, z = 1800, hpMax = 300000 },
	},
	dumps = { 600 }, status = 150,
	cam = { { frame = 50, x = 0, z = 800, height = 2600, angle = 0.85 } },
	shots = { { frame = 300, name = "ac_boreas_300" } },
	quit = 610,
}
