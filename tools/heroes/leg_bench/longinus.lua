return {
	hero = "legt4longinus", level = 100, learn = { "a1x10", "a2x10", "a3x10", "ultx10" },
	hold = true, immortal = true, heroFacing = 0, globalLos = true,
	groups = { { unit = "corsumo", n = 8, x = 0, z = 1250, line = { 0, 220 }, hpMax = 100000 }, { unit = "corjugg", n = 1, x = 0, z = 900 }, { unit = "corak", n = 1, x = -500, z = 700, mortal = true } },
	casts = { { frame = 90, key = "a2", group = 2 }, { frame = 200, key = "a3", x = 0, z = 350 }, { frame = 300, key = "ult", group = 2 }, { frame = 470, key = "a2", group = 3 } },
	dumps = { 195, 295, 460, 640 },
	cam = { { frame = 50, x = 0, z = 900, height = 2600, angle = 0.8 } },
	shots = { { frame = 100, name = "longinus_a2_mark" }, { frame = 180, name = "longinus_a1_sunder" }, { frame = 207, name = "longinus_a3_phase" }, { frame = 320, name = "longinus_ult_charge" },
		{ frame = 348, name = "longinus_ult_fire" }, { frame = 360, name = "longinus_ult_fire2" }, { frame = 420, name = "longinus_ult_wound" }, { frame = 490, name = "longinus_a2_kill" } },
	quit = 650,
}
