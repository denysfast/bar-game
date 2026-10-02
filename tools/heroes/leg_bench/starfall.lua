return {
	hero = "legt4starfall", level = 100, learn = { "a1x10", "a2x10", "a3x10", "ultx10" },
	hold = true, immortal = true,
	groups = { { unit = "corsumo", n = 10, x = 0, z = 2600, spread = 420, hpMax = 250000 }, { unit = "corak", n = 10, x = 300, z = 2400, spread = 300, mortal = true } },
	casts = { { frame = 90, key = "a3", x = 0, z = 2600 }, { frame = 440, key = "a2", x = 0, z = 2600 }, { frame = 300, key = "ult", x = 0, z = 2600 } },
	dumps = { 135, 295, 640 },
	cam = { { frame = 50, x = 0, z = 2500, height = 1500, angle = 0.95 } },
	shots = { { frame = 100, name = "starfall_a3_eye" }, { frame = 470, name = "starfall_a2_lens" }, { frame = 520, name = "starfall_a2_lens2" },
		{ frame = 330, name = "starfall_ult_meteors" }, { frame = 420, name = "starfall_ult_meteors2" }, { frame = 540, name = "starfall_ult_comet" }, { frame = 600, name = "starfall_a1_constellation" } },
	quit = 650,
}
