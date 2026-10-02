return {
	hero = "legt4helios", level = 100, learn = { "a1x10", "a2x10", "a3x10", "ultx10" },
	hold = true, immortal = true,
	groups = {
		{ unit = "corsumo", n = 8, x = 0, z = 750, spread = 260, hpMax = 1000000 },
		{ unit = "legeheatraymech", n = 3, x = -350, z = 100, spread = 120, team = 0, hp = 0.4 },
	},
	casts = { { frame = 250, key = "a3", x = 0, z = 750 }, { frame = 340, key = "a2" }, { frame = 420, key = "ult", x = 150, z = 800 } },
	dumps = { 240, 335, 415, 650 },
	cam = { { frame = 50, x = 0, z = 450, height = 1900, angle = 0.8 } },
	shots = { { frame = 200, name = "helios_a1_heat" }, { frame = 230, name = "helios_a1_ignite" }, { frame = 275, name = "helios_a3_sunspot" }, { frame = 305, name = "helios_a3_sunspot2" },
		{ frame = 343, name = "helios_a2_corona" }, { frame = 350, name = "helios_a2_corona2" }, { frame = 440, name = "helios_ult_warn" }, { frame = 500, name = "helios_ult_column" },
		{ frame = 580, name = "helios_ult_column2" }, { frame = 628, name = "helios_ult_collapse" } },
	quit = 660,
}
