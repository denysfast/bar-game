return {
	hero = "legt4apollyon", level = 100, learn = { "a1x10", "a2x10", "a3x10", "ultx10" },
	hold = true, immortal = true, globalLos = true,
	groups = { { unit = "corsumo", n = 10, x = 0, z = 1000, spread = 300, hpMax = 150000 }, { unit = "corak", n = 16, x = -200, z = 1600, spread = 300, mortal = true }, { unit = "corak", n = 16, x = 300, z = 1300, spread = 400, mortal = true, at = 300 } },
	casts = { { frame = 90, key = "a3" }, { frame = 200, key = "a2", x = -200, z = 1600 }, { frame = 320, key = "ult", x = 200, z = 1200 } },
	dumps = { 195, 315, 640 }, status = 90,
	cam = { { frame = 50, x = 0, z = 800, height = 2300, angle = 0.85 } },
	shots = { { frame = 100, name = "apollyon_a3_lockdown" }, { frame = 215, name = "apollyon_a2_locusts" }, { frame = 260, name = "apollyon_a2_burn" }, { frame = 380, name = "apollyon_ult_plague" },
		{ frame = 500, name = "apollyon_ult_plague2" }, { frame = 620, name = "apollyon_a1_fullspin" } },
	quit = 650,
}
