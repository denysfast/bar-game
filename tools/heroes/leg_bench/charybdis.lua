return {
	hero = "legt4charybdis", level = 100, learn = { "a1x10", "a2x10", "a3x10", "ultx10" },
	hold = true, immortal = true,
	groups = { { unit = "corsumo", n = 6, x = 0, z = 700, spread = 250, hpMax = 150000 }, { unit = "corak", n = 12, x = 100, z = 950, spread = 350, mortal = true }, { unit = "corsumo", n = 10, x = 0, z = 1100, spread = 450, at = 330, hpMax = 22000, mortal = true } },
	casts = { { frame = 150, key = "a2", x = 0, z = 750 }, { frame = 260, key = "a3", x = -300, z = 600 }, { frame = 340, key = "ult", x = 0, z = 950 } },
	dumps = { 145, 255, 335, 600 }, status = 90,
	cam = { { frame = 50, x = 0, z = 650, height = 1900, angle = 0.85 } },
	shots = { { frame = 130, name = "charybdis_a1_undertow" }, { frame = 152, name = "charybdis_a2_warn" }, { frame = 168, name = "charybdis_a2_spout" }, { frame = 200, name = "charybdis_a2_mist" },
		{ frame = 268, name = "charybdis_a3_surge" }, { frame = 290, name = "charybdis_a3_wake" }, { frame = 380, name = "charybdis_ult_maw" }, { frame = 470, name = "charybdis_ult_maw2" }, { frame = 553, name = "charybdis_ult_blast" } },
	quit = 610,
}
