return {
	hero = "legt4myrmidon", level = 100, learn = { "a1x10", "a2x10", "a3x10", "ultx10" },
	hold = true, immortal = true,
	groups = { { unit = "corsumo", n = 8, x = 0, z = 1100, spread = 300, hpMax = 150000 }, { unit = "legeheatraymech", n = 3, x = -450, z = -100, spread = 150, team = 0, hp = 0.3 }, { unit = "corjugg", n = 1, x = 300, z = 900 } },
	casts = { { frame = 330, key = "a3", group = 3 }, { frame = 420, key = "ult" } },
	dumps = { 325, 415, 640 }, status = 90,
	cam = { { frame = 50, x = 0, z = 500, height = 2200, angle = 0.85 } },
	shots = { { frame = 200, name = "myrmidon_a1_drones" }, { frame = 300, name = "myrmidon_a2_repair" }, { frame = 345, name = "myrmidon_a3_dive" }, { frame = 352, name = "myrmidon_a3_dive2" },
		{ frame = 430, name = "myrmidon_ult_root" }, { frame = 560, name = "myrmidon_ult_mites" } },
	quit = 650,
}
