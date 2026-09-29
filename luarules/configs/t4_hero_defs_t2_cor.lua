-- Custom heroes (denysfast/bar-game): the ten Cortex T2 heroes (altar: cort2hall). Included by luarules/configs/t4_heroes.lua,
-- which passes the shared table H. See CUSTOM.md, section "Heroes".
-- Unitdefs: units/CorT2Heroes/cort2heroes.lua. Ability kinds are the v15 ability kit (the gadget); every value is
-- absolute (HP, damage, elmos, seconds) except army auras/buffs (fractions). Command ids 36301-36399.
local H = ...

local heroes = {
	cort2sumo = {
		title = "Sumo, the Juggernaut", role = "Juggernaut / guard", aiRole = "front",
		fx = 1.5,
		weapons = { { keys = { "corsumo_weapon" }, name = "Heavy Laser", kind = "beam" } },
		a1 = {
			name = "Ironhide", kind = "stats", passive = true,
			desc = "Layered plating: more health and less damage taken",
			ranks = { { hp = 2000, armor = 0.05 }, { hp = 4500, armor = 0.10 }, { hp = 7500, armor = 0.15 } },
			text = { "+2000 HP, -5% damage taken", "+4500 HP, -10% damage taken", "+7500 HP, -15% damage taken" },
		},
		a2 = {
			name = "Sumo Stance", kind = "active_guard", cmd = 36301, action = "hero_sumostance", fx = "hero-buff-armor",
			desc = "Plants its feet and covers the allies within 700: they take less damage for 7 seconds",
			radius = 700, reduce = { 0.20, 0.30, 0.40 }, duration = 7, cooldown = { 45, 40, 35 },
			text = { "700 radius, -20% damage taken, 7 s, cd 45 s", "-30% radius, cd 40 s", "-40% radius, cd 35 s" },
		},
		ult = {
			name = "Unbreakable", kind = "active_shield", cmd = 36302, action = "hero_unbreakable", fx = "hero-shield",
			desc = "A kinetic barrier absorbs incoming damage for a few seconds",
			duration = { 6, 8, 10 }, absorb = { 12000, 20000, 32000 }, cooldown = { 90, 80, 70 },
			text = { "absorbs 12000 HP for 6 s, cd 90 s", "20000 HP for 8 s, cd 80 s", "32000 HP for 10 s, cd 70 s" },
		},
	},

	cort2can = {
		title = "Can, the Brawler", role = "Close-range brawler", aiRole = "front",
		fx = 1.5,
		weapons = { { keys = { "cor_canlaser" }, name = "Brawler Laser", kind = "beam" } },
		a1 = {
			name = "Scrapper", kind = "lifesteal", passive = true,
			desc = "Every hit repairs Can by a share of the damage dealt",
			frac = { 0.08, 0.14, 0.20 },
			text = { "8% of damage dealt as HP", "14% of damage dealt as HP", "20% of damage dealt as HP" },
		},
		a2 = {
			name = "Shoulder Charge", kind = "active_dash", cmd = 36303, action = "hero_shouldercharge", target = "map", fx = "hero-dash",
			desc = "Charges to a point, smashing every enemy on the way",
			range = { 500, 600, 700 }, dmg = { 1200, 2000, 3000 }, radius = 160, cooldown = { 20, 17, 14 },
			text = { "500 range, 1200 damage, cd 20 s", "600 range, 2000 damage, cd 17 s", "700 range, 3000 damage, cd 14 s" },
		},
		ult = {
			name = "Berserk", kind = "active_buff", cmd = 36304, action = "hero_berserk", fx = "hero-buff-power",
			desc = "Goes berserk: more damage, less damage taken, fast self-repair",
			buff = { damage = 0.4, armor = 0.3, regen = 250 }, duration = { 6, 8, 10 }, cooldown = { 70, 60, 50 },
			text = { "6 s: +40% damage, -30% damage taken, +250 HP/s, cd 70 s", "8 s, cd 60 s", "10 s, cd 50 s" },
		},
	},

	cort2pyro = {
		title = "Pyro, the Firestarter", role = "Flame raider", aiRole = "front",
		fx = 1.5,
		weapons = { { keys = { "flamethrower" }, name = "Napalm Thrower", kind = "flame" } },
		a1 = {
			name = "Immolation", kind = "aura_burn", passive = true,
			desc = "Burns every enemy around, every second",
			radius = { 220, 280, 340 }, dps = { 60, 120, 200 },
			text = { "220 radius, 60 damage/s", "280 radius, 120 damage/s", "340 radius, 200 damage/s" },
		},
		a2 = {
			name = "Flame Dash", kind = "active_dash", cmd = 36305, action = "hero_flamedash", target = "map", fx = "hero-dash",
			desc = "Dashes to a point on a trail of fire, burning every enemy on the way",
			range = { 450, 550, 650 }, dmg = { 800, 1400, 2200 }, radius = 180, cooldown = { 18, 15, 12 },
			text = { "450 range, 800 damage, cd 18 s", "550 range, 1400 damage, cd 15 s", "650 range, 2200 damage, cd 12 s" },
		},
		ult = {
			name = "Inferno Burst", kind = "active_nova", cmd = 36306, action = "hero_infernoburst", fx = "hero-nova-fire",
			desc = "Erupts in a ring of fire that scorches everything around",
			radius = { 400, 480, 560 }, dmg = { 2500, 4000, 6000 }, cooldown = { 60, 55, 50 },
			text = { "400 radius, 2500 damage, cd 60 s", "480 radius, 4000 damage, cd 55 s", "560 radius, 6000 damage, cd 50 s" },
		},
	},

	cort2termite = {
		title = "Termite, the Infiltrator", role = "Stealth / EMP", aiRole = "center",
		fx = 1.5,
		weapons = { { keys = { "cor_termite_laser" }, name = "Heat Ray", kind = "heatray" } },
		a1 = {
			name = "Burrow", kind = "active_cloak", cmd = 36307, action = "hero_burrow", fx = "hero-cloak",
			desc = "Burrows out of sight: cloaked and a little faster until the time runs out",
			duration = { 6, 9, 12 }, speed = 0.2, cooldown = { 35, 30, 25 },
			text = { "6 s cloak, +20% speed, cd 35 s", "9 s cloak, cd 30 s", "12 s cloak, cd 25 s" },
		},
		a2 = {
			name = "Static Legs", kind = "aura_emp", passive = true,
			desc = "Enemies near the spider are shocked and paralysed every 2 seconds",
			radius = { 280, 340, 400 }, dmg = { 60, 120, 200 }, emp = { 600, 1200, 2000 }, period = 2,
			text = { "280 radius, 60 damage + 600 EMP", "340 radius, 120 + 1200 EMP", "400 radius, 200 + 2000 EMP" },
		},
		ult = {
			name = "EMP Burst", kind = "active_nova", cmd = 36308, action = "hero_empburst", fx = "hero-nova-emp",
			desc = "Discharges an EMP shockwave: damages and stuns everything around",
			radius = { 450, 550, 650 }, dmg = { 800, 1500, 2500 }, stun = { 3, 4, 5 }, emp = { 3000, 6000, 10000 },
			cooldown = { 60, 55, 50 },
			text = { "450 radius, 800 damage, 3 s stun, cd 60 s", "550 radius, 1500 damage, 4 s stun, cd 55 s", "650 radius, 2500 damage, 5 s stun, cd 50 s" },
		},
	},

	cort2arbiter = {
		title = "Arbiter, the Judge", role = "Rocket support", aiRole = "back", xpRate = 0.6,
		fx = 1.5,
		weapons = { { keys = { "corhrk_rocket" }, name = "Heavy Starburst Rockets", kind = "rockets" } },
		a1 = {
			name = "Verdict", kind = "crit", passive = true,
			desc = "A chance to deal multiplied damage",
			chance = { 0.12, 0.20, 0.28 }, mult = { 2.0, 2.5, 3.0 },
			text = { "12% chance for x2 damage", "20% for x2.5", "28% for x3" },
		},
		a2 = {
			name = "Target Designator", kind = "aura_damage", passive = true,
			desc = "Allied units around deal more damage to what the Arbiter marks",
			radius = 800, mult = { 0.06, 0.10, 0.15 },
			text = { "800 radius, allies +6% damage", "+10% radius", "+15% radius" },
		},
		ult = {
			name = "Judgement Swarm", kind = "active_missiles", cmd = 36309, action = "hero_judgement", fx = "hero-missile-launch",
			desc = "Launches a swarm of homing missiles at the enemies around",
			weapon = "hero_missile", radius = 1400, count = { 8, 12, 18 }, dmg = { 700, 1000, 1400 }, cooldown = { 60, 55, 50 },
			text = { "8 missiles of 700 damage within 1400, cd 60 s", "12 missiles of 1000, cd 55 s", "18 missiles of 1400, cd 50 s" },
		},
	},

	cort2sheldon = {
		title = "Sheldon, the Bombardier", role = "Mortar artillery", aiRole = "back", xpRate = 0.6,
		fx = 1.5,
		weapons = { { keys = { "cor_mort" }, name = "Plasma Mortar", kind = "mortar" } },
		a1 = {
			name = "Shrapnel Shells", kind = "proc_blast", passive = true,
			desc = "A chance that a hit bursts into an extra blast of shrapnel",
			chance = { 0.20, 0.30, 0.40 }, dmg = { 300, 550, 850 }, radius = { 120, 150, 180 },
			text = { "20% chance: 300 damage in 120", "30%: 550 in 150", "40%: 850 in 180" },
		},
		a2 = {
			name = "Dig In", kind = "active_buff", cmd = 36310, action = "hero_digin", fx = "hero-buff-armor",
			desc = "Digs in: cannot move, takes less damage and hits harder",
			buff = { armor = 0.3, damage = 0.3, immobile = true }, duration = { 8, 11, 14 }, cooldown = { 40, 35, 30 },
			text = { "8 s: -30% damage taken, +30% damage, cd 40 s", "11 s, cd 35 s", "14 s, cd 30 s" },
		},
		ult = {
			name = "Mortar Barrage", kind = "active_barrage", cmd = 36311, action = "hero_mortarbarrage", target = "map", fx = "hero-target",
			desc = "Calls a barrage of mortar shells on an area",
			weapon = "hero_shell", projectile = "shell", range = 1400, radius = 400, count = { 14, 22, 32 }, duration = 5,
			dmg = { 400, 600, 850 }, cooldown = { 75, 70, 60 },
			text = { "14 shells of 400 damage in 400, cd 75 s", "22 shells of 600, cd 70 s", "32 shells of 850, cd 60 s" },
		},
	},

	cort2goliath = {
		title = "Goliath, the Immovable", role = "Shield tank", aiRole = "front",
		fx = 1.5,
		weapons = { { keys = { "cor_gol" }, name = "Heavy Cannon", kind = "cannon" } },
		a1 = {
			name = "Bulwark Projector", kind = "shield_cap", passive = true,
			desc = "Capacity and recharge of the plasma deflector over the escort",
			cap = { 0.5, 0.75, 1.0 }, base = 0.3, regen = { 1.5, 2.0, 2.6 },
			text = { "50% capacity, x1.5 recharge", "75% capacity, x2 recharge", "100% capacity, x2.6 recharge" },
		},
		a2 = {
			name = "Iron Phalanx", kind = "aura_armor", passive = true,
			desc = "Allied units around take less damage",
			radius = 600, reduce = { 0.08, 0.14, 0.20 },
			text = { "600 radius, allies -8% damage taken", "-14% radius", "-20% radius" },
		},
		ult = {
			name = "Goliath Dome", kind = "active_dome", cmd = 36312, action = "hero_goliathdome", fx = "hero-shield",
			desc = "Allies within 650 cannot be damaged for a few seconds",
			radius = 650, duration = { 3, 5, 7 }, cooldown = { 110, 100, 90 },
			text = { "3 s invulnerability, cd 110 s", "5 s invulnerability, cd 100 s", "7 s invulnerability, cd 90 s" },
		},
	},

	cort2tiger = {
		title = "Tiger, the Striker", role = "Assault tank", aiRole = "front",
		fx = 1.5,
		weapons = { { keys = { "cor_reap" }, name = "Assault Plasma", kind = "plasma" } },
		a1 = {
			name = "Big Game Hunter", kind = "slayer", passive = true,
			desc = "More damage against expensive targets (1500+ metal)",
			minCost = 1500, mult = { 0.20, 0.35, 0.50 },
			text = { "+20% damage vs 1500+ metal", "+35%", "+50%" },
		},
		a2 = {
			name = "Pounce", kind = "active_buff", cmd = 36313, action = "hero_pounce", fx = "hero-buff-speed",
			desc = "A burst of speed with armor up",
			buff = { speed = 0.6, armor = 0.2 }, duration = { 5, 6, 7 }, cooldown = { 30, 26, 22 },
			text = { "5 s: +60% speed, -20% damage taken, cd 30 s", "6 s, cd 26 s", "7 s, cd 22 s" },
		},
		ult = {
			name = "Pride", kind = "active_summon", cmd = 36314, action = "hero_pride", fx = "hero-summon",
			desc = "Calls in a pride of Tiger tanks that fight at its side until time runs out",
			unit = "correap", count = { 2, 3, 4 }, duration = { 30, 40, 50 }, cooldown = { 120, 110, 100 },
			text = { "2 Tigers for 30 s, cd 120 s", "3 Tigers for 40 s, cd 110 s", "4 Tigers for 50 s, cd 100 s" },
		},
	},

	cort2banisher = {
		title = "Banisher, the Exiler", role = "Missile artillery", aiRole = "back", xpRate = 0.6,
		fx = 1.5,
		weapons = { { keys = { "banisher" }, name = "Banisher Missiles", kind = "missiles" } },
		a1 = {
			name = "Arc Warheads", kind = "proc_chain", passive = true,
			desc = "A chance that a hit arcs a lightning chain to the enemies nearby",
			weapon = "hero_chain", chance = { 0.25, 0.35, 0.45 }, dmg = { 400, 700, 1000 }, jumps = { 2, 3, 4 }, radius = 400,
			text = { "25% chance: 400 damage, 2 jumps", "35%: 700, 3 jumps", "45%: 1000, 4 jumps" },
		},
		a2 = {
			name = "Telemetry", kind = "stats", passive = true,
			desc = "Long-range sensors: sight and radar",
			ranks = { { sight = 150, radar = 500 }, { sight = 300, radar = 1000 }, { sight = 450, radar = 1500 } },
			text = { "+150 sight, +500 radar", "+300 sight, +1000 radar", "+450 sight, +1500 radar" },
		},
		ult = {
			name = "Banishment", kind = "active_spear", cmd = 36315, action = "hero_banishment", target = "unit", fx = "hero-target",
			desc = "A heavy missile through the whole line to the target; rank 3 ends in a blast",
			weapon = "hero_spear", range = { 1400, 1600, 1800 }, pct = { 0.15, 0.22, 0.30 }, flat = 3000, line = 2000,
			nova = { false, false, true }, cooldown = { 80, 70, 60 },
			text = { "15% of target max HP + 3000, cd 80 s", "22%, cd 70 s", "30%, cd 60 s, 4000 blast" },
		},
	},

	cort2tremor = {
		title = "Tremor, the Earthshaker", role = "Carpet artillery", aiRole = "back", xpRate = 0.4,
		fx = 1.5,
		weapons = { { keys = { "tremor_spread_fire" }, name = "Rapid Artillery", kind = "artillery" } },
		a1 = {
			name = "Ground Quake", kind = "active_nova", cmd = 36316, action = "hero_groundquake", fx = "hero-nova-kinetic",
			desc = "Shakes the ground around: damages and stuns the enemies that got close",
			radius = { 350, 420, 500 }, dmg = { 600, 1000, 1600 }, stun = { 1, 1.5, 2 }, cooldown = { 30, 27, 24 },
			text = { "350 radius, 600 damage, 1 s stun, cd 30 s", "420 radius, 1000 damage, 1.5 s stun, cd 27 s", "500 radius, 1600 damage, 2 s stun, cd 24 s" },
		},
		a2 = {
			name = "Seismic Field", kind = "aura_slow", passive = true,
			desc = "Enemies around are slowed by the constant tremors",
			radius = { 400, 500, 600 }, slow = { 0.15, 0.25, 0.35 },
			text = { "400 radius, -15% speed", "500 radius, -25% speed", "600 radius, -35% speed" },
		},
		ult = {
			name = "Carpet Barrage", kind = "active_barrage", cmd = 36317, action = "hero_carpetbarrage", target = "map", fx = "hero-target",
			desc = "Carpets an area with artillery shells",
			weapon = "hero_shell", projectile = "shell", range = 2200, radius = 600, count = { 24, 36, 50 }, duration = 6,
			dmg = { 350, 500, 700 }, cooldown = { 90, 80, 70 },
			text = { "24 shells of 350 damage in 600, cd 90 s", "36 shells of 500, cd 80 s", "50 shells of 700, cd 70 s" },
		},
	},
}

return heroes, {
	"cort2sumo", "cort2can", "cort2pyro", "cort2termite", "cort2arbiter",
	"cort2sheldon", "cort2goliath", "cort2tiger", "cort2banisher", "cort2tremor",
}
