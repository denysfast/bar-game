-- Custom heroes (denysfast/bar-game): the ten Legion T2 heroes (altar: legt2hall). Included by luarules/configs/t4_heroes.lua,
-- which passes the shared table H. See CUSTOM.md, section "Heroes".
--
-- Unitdefs: units/Legion/T2Heroes/legt2heroes.lua. Every value is absolute (HP, HP/s, damage, elmos, seconds);
-- fractions only where the kit keeps them: armor, temporary buffs (active_buff speed/damage/armor), auras,
-- crit/proc chances, lifesteal/thorns shares.
-- Commands 36401-36499.
local H = ...

local heroes = {
	legt2warden = {
		title = "Warden, the Iron Phalanx", role = "Riot vanguard", aiRole = "front",
		fx = 1.6,
		weapons = { { keys = { "legion_riot_cannon_t2" }, name = "Riot Cannon", kind = "plasma" } },
		a1 = {
			name = "Phalanx Plating", kind = "stats", passive = true,
			desc = "Heavier plates and field repair",
			ranks = {
				{ hp = 1500, armor = 0.06, regen = 15 },
				{ hp = 3000, armor = 0.12, regen = 30 },
				{ hp = 4500, armor = 0.18, regen = 45 },
			},
			text = { "+1500 HP, -6% damage taken, +15 HP/s", "+3000 HP, -12% damage taken, +30 HP/s", "+4500 HP, -18% damage taken, +45 HP/s" },
		},
		a2 = {
			name = "Shield Bash", kind = "active_nova", cmd = 36401, action = "hero_shieldbash", fx = "hero-nova-kinetic",
			desc = "Slams the shield into the ground: damages and stuns every enemy around",
			radius = { 260, 300, 340 }, dmg = { 900, 1600, 2400 }, stun = { 1.5, 2, 2.5 }, cooldown = { 24, 21, 18 },
			text = { "260 radius, 900 dmg, 1.5 s stun, cd 24s", "300 radius, 1600 dmg, 2 s stun, cd 21s", "340 radius, 2400 dmg, 2.5 s stun, cd 18s" },
		},
		ult = {
			name = "Testudo", kind = "active_guard", cmd = 36402, action = "hero_testudo",
			desc = "Locks shields with the army: allies within 650 take less damage",
			radius = 650, reduce = { 0.3, 0.4, 0.5 }, duration = 8, cooldown = { 75, 65, 55 },
			text = { "-30% damage taken for 8 s, cd 75s", "-40%, cd 65s", "-50%, cd 55s" },
		},
	},

	legt2pyre = {
		title = "Pyre, the Incinerator", role = "Heat-ray bruiser", aiRole = "front",
		fx = 1.5,
		weapons = { { keys = { "heatraylarge" }, name = "Sustained Heat Ray", kind = "heatray" } },
		a1 = {
			name = "Heat Haze", kind = "aura_burn", passive = true,
			desc = "The air around Pyre scorches every enemy, every second",
			radius = { 220, 260, 300 }, dps = { 90, 180, 300 },
			text = { "220 radius, 90 damage/s", "260 radius, 180/s", "300 radius, 300/s" },
		},
		a2 = {
			name = "Overheat", kind = "active_buff", cmd = 36403, action = "hero_overheat", fx = "hero-buff-power",
			desc = "Vents the reactor into the ray and the hull: more damage dealt, less taken, for a few seconds",
			buff = { damage = 0.35, armor = 0.15 }, duration = { 6, 7, 8 }, cooldown = { 30, 27, 24 },
			text = { "6 s: +35% damage, -15% damage taken, cd 30s", "7 s, cd 27s", "8 s, cd 24s" },
		},
		ult = {
			name = "Meltdown", kind = "active_beam", cmd = 36404, action = "hero_meltdown", target = "map",
			desc = "Focuses a column of heat on an area for 5 seconds",
			range = 1000, radius = 200, tick = { 220, 340, 480 }, duration = 5,
			nova = { false, false, false }, cooldown = { 80, 70, 60 },
			text = { "220 damage per 0.2 s, cd 80s", "340, cd 70s", "480, cd 60s" },
		},
	},

	legt2longshot = {
		title = "Longshot, the Arquebusier", role = "Rail sniper", aiRole = "back",
		fx = 1.5,
		weapons = { { keys = { "railgunt2" }, name = "Heavy Railgun", kind = "rail" } },
		a1 = {
			name = "Headshot", kind = "crit", passive = true,
			desc = "A chance for a rail slug to hit a weak point for multiplied damage",
			chance = { 0.15, 0.22, 0.3 }, mult = { 2.0, 2.5, 3.0 },
			text = { "15% chance for x2", "22% for x2.5", "30% for x3" },
		},
		a2 = {
			name = "Ghillie Field", kind = "active_cloak", cmd = 36405, action = "hero_ghillie", fx = "hero-cloak",
			desc = "Cloaks Longshot; moving slowly keeps the field up",
			duration = { 8, 12, 16 }, speed = 0.6, cooldown = { 40, 35, 30 },
			text = { "8 s cloak, cd 40s", "12 s cloak, cd 35s", "16 s cloak, cd 30s" },
		},
		ult = {
			name = "Piercing Rail", kind = "active_spear", cmd = 36406, action = "hero_piercingrail", target = "unit",
			desc = "One overcharged slug through the target and everything in its line; rank 3 detonates on impact",
			range = { 1300, 1450, 1600 }, pct = { 0.08, 0.12, 0.16 }, flat = 2500, line = 1600,
			nova = { false, false, true }, cooldown = { 70, 60, 50 },
			text = { "2500 + 8% of max HP, cd 70s", "+12%, cd 60s", "+16%, cd 50s, blast on impact" },
		},
	},

	legt2harrier = {
		title = "Harrier, the Swift Blade", role = "Raider", aiRole = "front",
		fx = 1.5,
		weapons = { { keys = { "armmg_weapon" }, name = "Twin Rapid Guns", kind = "cannon" } },
		a1 = {
			name = "Bloodletting", kind = "lifesteal", passive = true,
			desc = "Part of the damage dealt returns to Harrier as health",
			frac = { 0.1, 0.17, 0.25 },
			text = { "10% of damage as health", "17% of damage as health", "25% of damage as health" },
		},
		a2 = {
			name = "Adrenaline", kind = "active_buff", cmd = 36407, action = "hero_adrenaline", fx = "hero-buff-speed",
			desc = "Sprints and strikes harder for a few seconds",
			buff = { speed = 0.5, damage = 0.25 }, duration = { 5, 6, 7 }, cooldown = { 25, 22, 19 },
			text = { "5 s: +50% speed, +25% damage, cd 25s", "6 s, cd 22s", "7 s, cd 19s" },
		},
		ult = {
			name = "Hoplite Pack", kind = "active_summon", cmd = 36408, action = "hero_hoplitepack", fx = "hero-summon",
			desc = "Calls a pack of Hoplite raiders that fight beside Harrier until time runs out",
			unit = "legstr", count = { 3, 5, 7 }, duration = { 30, 40, 50 }, cooldown = { 90, 80, 70 },
			text = { "3 Hoplites for 30 s, cd 90s", "5 for 40 s, cd 80s", "7 for 50 s, cd 70s" },
		},
	},

	legt2scorch = {
		title = "Scorch, the Belcher", role = "Napalm skirmisher", aiRole = "center",
		fx = 1.6,
		weapons = { { keys = { "clusternapalm" }, name = "Napalm Launcher", kind = "mortar" } },
		a1 = {
			name = "Incendiary Payload", kind = "proc_blast", passive = true,
			desc = "A chance for a hit to burst into an extra fireball",
			chance = { 0.2, 0.28, 0.36 }, dmg = { 300, 500, 750 }, radius = { 120, 140, 160 },
			text = { "20%: 300 dmg in 120", "28%: 500 in 140", "36%: 750 in 160" },
		},
		a2 = {
			name = "Backdraft", kind = "active_nova", cmd = 36409, action = "hero_backdraft", fx = "hero-nova-fire",
			desc = "Vents the fuel tanks: a ring of fire around Scorch",
			radius = { 280, 330, 380 }, dmg = { 1000, 1700, 2500 }, cooldown = { 28, 25, 22 },
			text = { "280 radius, 1000 dmg, cd 28s", "330 radius, 1700 dmg, cd 25s", "380 radius, 2500 dmg, cd 22s" },
		},
		ult = {
			name = "Napalm Deluge", kind = "active_barrage", cmd = 36410, action = "hero_deluge", target = "map",
			desc = "Burning meteors rain on an area and leave it on fire; rank 3 ends in a firestorm blast",
			range = 1200, radius = 350, count = { 10, 16, 24 }, duration = 5, dmg = { 600, 800, 1000 },
			projectile = "meteor", nova = { false, false, true }, cooldown = { 80, 70, 60 },
			text = { "10 meteors x 600, cd 80s", "16 x 800, cd 70s", "24 x 1000 + firestorm, cd 60s" },
		},
	},

	legt2reaper = {
		title = "Reaper, the Rocket Legate", role = "Rocket artillery", aiRole = "back", xpRate = 0.6,
		fx = 1.6,
		weapons = { { keys = { "rocket_barrage" }, name = "Salvo Rockets", kind = "rockets" } },
		a1 = {
			name = "Target Uplink", kind = "stats", passive = true,
			desc = "Sight and radar to find targets for the salvos",
			ranks = { { sight = 150, radar = 600 }, { sight = 300, radar = 1100 }, { sight = 450, radar = 1600 } },
			text = { "+150 sight, +600 radar", "+300 sight, +1100 radar", "+450 sight, +1600 radar" },
		},
		a2 = {
			name = "Brace", kind = "active_buff", cmd = 36411, action = "hero_brace", fx = "hero-buff-armor",
			desc = "Anchors the launch rails: cannot move, deals more damage and takes less",
			buff = { immobile = true, damage = 0.4, armor = 0.25 }, duration = { 8, 10, 12 }, cooldown = { 35, 31, 27 },
			text = { "8 s: +40% damage, -25% damage taken, cd 35s", "10 s, cd 31s", "12 s, cd 27s" },
		},
		ult = {
			name = "Rocket Carpet", kind = "active_barrage", cmd = 36412, action = "hero_rocketcarpet", target = "map",
			desc = "Calls a carpet of heavy rockets on an area; rank 3 finishes with a blast",
			range = 1800, radius = 420, count = { 12, 18, 26 }, duration = 4, dmg = { 500, 650, 800 },
			projectile = "missile", nova = { false, false, true }, cooldown = { 85, 75, 65 },
			text = { "12 rockets x 500, cd 85s", "18 x 650, cd 75s", "26 x 800 + blast, cd 65s" },
		},
	},

	legt2gladius = {
		title = "Gladius, the Arena Champion", role = "Brawler tank", aiRole = "front",
		fx = 1.5,
		weapons = { { keys = { "legmgplasma" }, name = "Rotary Plasma Cannon", kind = "plasma" } },
		a1 = {
			name = "War Cry", kind = "aura_damage", passive = true,
			desc = "Allied units around Gladius deal more damage",
			radius = 700, mult = { 0.06, 0.11, 0.16 },
			text = { "+6% damage", "+11% damage", "+16% damage" },
		},
		a2 = {
			name = "Scutum", kind = "active_shield", cmd = 36413, action = "hero_scutum", fx = "hero-shield",
			desc = "Raises an energy scutum that absorbs damage",
			duration = { 6, 7, 8 }, absorb = { 3000, 5000, 7500 }, cooldown = { 30, 27, 24 },
			text = { "absorbs 3000 for 6 s, cd 30s", "5000 for 7 s, cd 27s", "7500 for 8 s, cd 24s" },
		},
		ult = {
			name = "Champion's Fury", kind = "active_buff", cmd = 36414, action = "hero_fury", fx = "hero-buff-power",
			desc = "The crowd roars: more damage, armor and speed",
			buff = { damage = 0.4, armor = 0.25, speed = 0.3 }, duration = { 8, 10, 12 }, cooldown = { 75, 65, 55 },
			text = { "8 s: +40% damage, -25% damage taken, +30% speed, cd 75s", "10 s, cd 65s", "12 s, cd 55s" },
		},
	},

	legt2vulcan = {
		title = "Vulcan, the Fireforged", role = "Heat-ray assault tank", aiRole = "front",
		fx = 1.5,
		weapons = { { keys = { "heat_ray" }, name = "Cleansing Heat Ray", kind = "heatray" } },
		a1 = {
			name = "Molten Hull", kind = "thorns", passive = true,
			desc = "Part of the damage Vulcan takes splashes back on the attacker as molten metal",
			frac = { 0.1, 0.17, 0.25 },
			text = { "10% of damage taken returned", "17% of damage taken returned", "25% of damage taken returned" },
		},
		a2 = {
			name = "Magma Ram", kind = "active_dash", cmd = 36415, action = "hero_magmaram", target = "map", fx = "hero-dash",
			desc = "Charges to a point and burns everything along the way",
			range = { 450, 550, 650 }, dmg = { 800, 1300, 1900 }, radius = 150, cooldown = { 26, 23, 20 },
			text = { "450 charge, 800 dmg, cd 26s", "550 charge, 1300 dmg, cd 23s", "650 charge, 1900 dmg, cd 20s" },
		},
		ult = {
			name = "Phoenix Core", kind = "undying", passive = true,
			desc = "Lethal damage instead leaves Vulcan standing, repaired; rank 3 is reborn in a fire blast",
			cooldown = { 240, 200, 160 }, heal = { 6000, 9000, 13000 }, nova = { false, false, true },
			text = { "revive with 6000 HP, cd 240s", "9000 HP, cd 200s", "13000 HP, cd 160s, fire blast" },
		},
	},

	legt2swarm = {
		title = "Swarm, the Hive Mother", role = "Drone carrier / support", aiRole = "center",
		fx = 1.5,
		weapons = { { keys = { "targeting" }, name = "Hive Arc Relay", kind = "lightning" } },
		a1 = {
			name = "Nanite Cloud", kind = "aura_heal", passive = true,
			desc = "Repair nanites mend allies and structures around the carrier",
			radius = { 450, 550, 650 }, rate = { 20, 40, 65 },
			text = { "450 radius, 20 HP/s", "550 radius, 40 HP/s", "650 radius, 65 HP/s" },
		},
		a2 = {
			name = "Seeker Swarm", kind = "active_missiles", cmd = 36416, action = "hero_seekers", fx = "hero-missile-launch",
			desc = "Launches homing seekers at the enemies around",
			radius = 900, count = { 6, 9, 12 }, dmg = { 350, 500, 650 }, cooldown = { 28, 25, 22 },
			text = { "6 seekers x 350, cd 28s", "9 x 500, cd 25s", "12 x 650, cd 22s" },
		},
		ult = {
			name = "Hive Ascendant", kind = "active_summon", cmd = 36417, action = "hero_hive", fx = "hero-summon",
			desc = "Releases a wing of heavy drones for a while",
			unit = "legheavydrone", count = { 3, 5, 7 }, duration = { 40, 50, 60 }, cooldown = { 100, 90, 80 },
			text = { "3 heavy drones for 40 s, cd 100s", "5 for 50 s, cd 90s", "7 for 60 s, cd 80s" },
		},
	},

	legt2gorgon = {
		title = "Gorgon, the Stone Gaze", role = "Siege rockets / control", aiRole = "back", xpRate = 0.6,
		fx = 1.6,
		weapons = { { keys = { "legmed_missile" }, name = "Hexaburst Rockets", kind = "missiles" } },
		a1 = {
			name = "Stone Gaze", kind = "aura_slow", passive = true,
			desc = "Enemies near the Gorgon move slower",
			radius = { 400, 480, 560 }, slow = { 0.15, 0.25, 0.35 },
			text = { "400 radius, -15% speed", "480 radius, -25% speed", "560 radius, -35% speed" },
		},
		a2 = {
			name = "Serpent Arcs", kind = "proc_chain", passive = true,
			desc = "A chance for a hit to throw arcs of lightning between nearby enemies",
			chance = { 0.2, 0.3, 0.4 }, dmg = { 250, 400, 600 }, jumps = { 2, 3, 4 }, radius = 350,
			text = { "20%: 250 dmg, 2 jumps", "30%: 400, 3 jumps", "40%: 600, 4 jumps" },
		},
		ult = {
			name = "Petrify", kind = "active_nova", cmd = 36418, action = "hero_petrify", fx = "hero-nova-emp",
			desc = "A pulse from the Gorgon's eye: stuns and paralyses every enemy around",
			radius = { 450, 550, 650 }, dmg = { 600, 1000, 1500 }, stun = { 3, 4, 5 }, emp = { 3000, 5000, 8000 },
			cooldown = { 80, 70, 60 },
			text = { "450 radius, 3 s stun, cd 80s", "550 radius, 4 s stun, cd 70s", "650 radius, 5 s stun, cd 60s" },
		},
	},
}

return heroes, {
	"legt2warden", "legt2pyre", "legt2longshot", "legt2harrier", "legt2scorch",
	"legt2reaper", "legt2gladius", "legt2vulcan", "legt2swarm", "legt2gorgon",
}
