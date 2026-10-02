return {
	hero = "legt4tempest", level = 100, learn = { "a1x10", "a2x10", "a3x10", "ultx10" }, heroZ = -500,
	hold = true, immortal = true, heroMove = { 0, 100 },
	groups = { { unit = "corsumo", n = 8, x = 0, z = 650, spread = 260, hpMax = 100000 }, { unit = "corak", n = 8, x = 200, z = 900, spread = 250, mortal = true }, { unit = "corjugg", n = 1, x = -200, z = 1300 } },
	casts = { { frame = 230, key = "a3" }, { frame = 300, key = "a2", group = 3 }, { frame = 420, key = "ult" } },
	dumps = { 225, 295, 415, 640 }, status = 60,
	cam = { { frame = 50, follow = true, dz = 300, height = 1800, angle = 0.85 } },
	shots = { { frame = 150, name = "tempest_a1_momentum" }, { frame = 200, name = "tempest_a1_breach" }, { frame = 240, name = "tempest_a3_echoes" }, { frame = 310, name = "tempest_a2_charge" },
		{ frame = 330, name = "tempest_a2_clap" }, { frame = 440, name = "tempest_ult_eye" }, { frame = 520, name = "tempest_ult_eye2" }, { frame = 663, name = "tempest_ult_clap" } },
	quit = 690,
}
