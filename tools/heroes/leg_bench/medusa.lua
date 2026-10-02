return {
	hero = "legt4medusa", level = 100, learn = { "a1x10", "a2x10", "a3x10", "ultx10" },
	hold = true, immortal = true, globalLos = true,
	groups = { { unit = "corsumo", n = 8, x = 0, z = 1500, spread = 300, hpMax = 150000 }, { unit = "armt4atlas", n = 1, x = 400, z = 1300, team = 1 }, { unit = "corak", n = 10, x = -300, z = 1300, spread = 250, mortal = true } },
	casts = { { frame = 150, key = "a3", x = -250, z = 1350 }, { frame = 300, key = "a2", x = 0, z = 1400 }, { frame = 380, key = "ult", x = 0, z = 1450 } },
	dumps = { 145, 295, 375, 660 }, status = 90,
	cam = { { frame = 50, x = 0, z = 1100, height = 2300, angle = 0.85 } },
	shots = { { frame = 140, name = "medusa_a1_petrify" }, { frame = 200, name = "medusa_a3_pit" }, { frame = 315, name = "medusa_a2_gaze" }, { frame = 340, name = "medusa_a2_gaze2" },
		{ frame = 400, name = "medusa_ult_warn" }, { frame = 440, name = "medusa_ult_stone" }, { frame = 600, name = "medusa_ult_shatter" } },
	quit = 670,
}
