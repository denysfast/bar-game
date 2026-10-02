return {
	hero = "legt4medusa", level = 100, learn = { "a1x10", "a2x10", "a3x10", "ultx10" }, autocast = true,
	hold = true, immortal = true, globalLos = true, heroZ = -300,
	groups = {
		{ unit = "corsumo", n = 10, x = 0, z = 700, spread = 300, hpMax = 80000 },
		{ unit = "armt4atlas", n = 1, x = 300, z = 900, team = 1 },
		{ unit = "legeheatraymech", n = 4, x = -300, z = -300, spread = 150, team = 0, hp = 0.5, hold = true },
		{ unit = "corak", n = 6, x = 100, z = 250, spread = 100, hp = 0.15, mortal = true },
		{ unit = "corjugg", n = 1, x = -400, z = 900, hpMax = 300000 },
	},
	dumps = { 600 }, status = 150,
	cam = { { frame = 50, x = 0, z = 400, height = 2200, angle = 0.85 } },
	shots = { { frame = 300, name = "ac_medusa_300" } },
	quit = 610,
}
