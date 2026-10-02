return {
	hero = "legt4mukade", level = 100, learn = { "a1x10", "a2x10", "a3x10", "ultx10" },
	hold = true, immortal = true,
	groups = { { unit = "corak", n = 10, x = 0, z = 1700, spread = 250, mortal = true }, { unit = "corjugg", n = 1, x = 350, z = 1500 }, { unit = "corsumo", n = 6, x = -200, z = 1900, spread = 200, hpMax = 150000 }, { unit = "corsumo", n = 4, x = -500, z = 1300, spread = 150, hold = false, hpMax = 400000 } },
	casts = { { frame = 120, key = "a1", x = 0, z = 1650 }, { frame = 420, key = "ult", group = 2 } },
	hurt = { { frame = 340, frac = 0.502 } },
	dumps = { 115, 410, 650 }, status = 60,
	cam = { { frame = 50, follow = true, dz = 350, height = 1900, angle = 0.85 } },
	shots = { { frame = 125, name = "mukade_a1_dive" }, { frame = 160, name = "mukade_a1_tunnel" }, { frame = 260, name = "mukade_a1_erupt" }, { frame = 320, name = "mukade_a2_venom" },
		{ frame = 352, name = "mukade_a3_molt" }, { frame = 440, name = "mukade_ult_coil" }, { frame = 520, name = "mukade_ult_coil2" } },
	quit = 660,
}
