return {
	hero = "legt4keres", level = 100, learn = { "a1x10", "a2x10", "a3x10", "ultx10" },
	hold = true, immortal = true,
	groups = { { unit = "corak", n = 14, x = 0, z = 550, spread = 300, mortal = true }, { unit = "corjugg", n = 1, x = 300, z = 1200 }, { unit = "corsumo", n = 1, x = -250, z = 300, hp = 0.2, mortal = true, at = 230 },
		{ unit = "corsumo", n = 8, x = 0, z = 700, spread = 400, hpMax = 150000 }, { unit = "corak", n = 14, x = 0, z = 650, spread = 400, mortal = true, at = 320 } },
	casts = { { frame = 150, key = "a2", group = 2 }, { frame = 240, key = "a3", group = 3 }, { frame = 330, key = "ult" } },
	dumps = { 145, 235, 325, 660 }, status = 60,
	cam = { { frame = 50, x = 0, z = 500, height = 1900, angle = 0.85 } },
	shots = { { frame = 130, name = "keres_a1_souls" }, { frame = 160, name = "keres_a2_grip" }, { frame = 172, name = "keres_a2_shot" }, { frame = 243, name = "keres_a3_devour" },
		{ frame = 360, name = "keres_ult_danse" }, { frame = 450, name = "keres_ult_danse2" } },
	quit = 670,
}
