-- Custom heroes (denysfast/bar-game): the twelve T4 heroes (altar: <side>t4gant). Included by luarules/configs/t4_heroes.lua,
-- which passes the shared table H. See CUSTOM.md, section "T4 heroes".
--
-- Ability kit (v15, luarules/gadgets/unit_t4_heroes.lua; every hero - T4 and T2 - uses it). a1 / a2: ranks at
-- levels 3 / 15 / 30, ult: 20 / 45 / 70. Values per rank { r1, r2, r3 } in absolute units (a plain number = every
-- rank); damage, healing and absorb grow with the hero level (H.ABILITY_POWER_PER_LEVEL). Abilities never change a
-- weapon. Actives: cmd (T4 36101-36199), action, cooldown, target = "map" | "unit" + range, fx (CEG), text.
--   passives   aura_heal {radius, rate HP/s}   aura_damage {radius, mult}   aura_armor {radius, reduce}
--              aura_burn {radius, dps}   aura_emp {radius, dmg, emp, period}   aura_slow {radius, slow}
--              stats {ranks = {{hp, armor, regen HP/s, speed, sight, radar}, ...}}   crit {chance, mult}
--              slayer {minCost, mult}   lifesteal {frac}   thorns {frac}   proc_chain {chance, dmg, jumps, radius, weapon?}
--              proc_blast {chance, dmg, radius, fx?}   undying {cooldown, heal, nova, novaRadius?, novaStun?}
--              shield_cap {cap, base, regen}
--   actives    active_buff {duration, buff = {speed, armor, regen HP/s, damage, immobile, shieldRegen, cloak}, trailDmg?}
--              active_guard {radius, reduce, duration, tickFx?}   active_dome {radius, duration, tickFx?}
--              active_nova {radius, dmg, stun, emp, heal, shieldRatio?}
--              active_barrage {range, radius, count, duration, dmg, aoe?, stun?, emp?, projectile = meteor|star|shell|
--                              missile|nuke|bolt, weapon?, from = sky|hero?, nova, novaRadius?, novaStun?, novaFx?, targetFx?}
--              active_beam {range, radius, tick (per 0.2 s), duration, drift? (elmos/s), nova}
--              active_spear {range, pct (of max HP), flat, line, nova, weapon?}
--              active_dash {range, dmg, radius, stun?, burn? (dps of the fire left behind), burnTime?}
--              active_bladestorm {radius, dmg (per 0.2 s), duration, armor}   active_summon {unit, count, duration}
--              active_missiles {radius, count, dmg, aoe?, weapon?}   active_repair {radius, heal}
--              active_cloak {duration, speed}   active_shield {duration, absorb}
--   nova: a number (the finale's damage) or true (novaDmg, else 3x the ability's damage).
local H = ...

H.ABILITY_POWER_PER_LEVEL = 0.015 -- ability damage / healing / absorb: +1.5% per hero level above 1

local heroes = {
	---------------------------------------------------------------------------- Armada
	armt4atlas = {
		title = "Atlas, the Bulwark", role = "Assault / support", aiRole = "front",
		fx = 2.5,
		weapons = { { keys = { "armbantha_fire" }, name = "Pulse Cannon", kind = "cannon" }, { keys = { "tehlazerofdewm" }, name = "Doom Laser", kind = "beam" }, { keys = { "bantha_rocket" }, name = "Starburst Rockets", kind = "rockets" } },
		a1 = {
			name = "Repair Field", kind = "aura_heal", passive = true,
			desc = "Allies and structures around Atlas regain health every second",
			radius = { 700, 900, 1100 }, rate = { 120, 250, 400 },
			text = { "700 radius, 120 HP/s", "900 radius, 250 HP/s", "1100 radius, 400 HP/s" },
		},
		a2 = {
			name = "Shoulder Battery", kind = "active_missiles", cmd = 36101, action = "hero_battery",
			desc = "A volley of homing rockets at the most valuable enemies within 1400",
			radius = 1400, count = { 6, 9, 12 }, dmg = { 2000, 2800, 3600 }, aoe = 160, cooldown = { 30, 26, 22 },
			text = { "6 rockets x 2000 dmg (160 radius), cd 30 s", "9 rockets x 2800 dmg, cd 26 s", "12 rockets x 3600 dmg, cd 22 s" },
		},
		ult = {
			name = "Doomsday Barrage", kind = "active_barrage", cmd = 36106, action = "hero_doomsday", target = "map",
			desc = "Launches tactical nukes from the shoulder silos onto an area within 2800",
			projectile = "nuke", range = 2800, radius = 550, count = { 3, 5, 8 }, dmg = { 6000, 7500, 9000 }, aoe = 380,
			duration = 3, cooldown = { 120, 110, 100 },
			text = { "3 nukes x 6000 dmg (380 radius), cd 120 s", "5 nukes x 7500 dmg, cd 110 s", "8 nukes x 9000 dmg, cd 100 s" },
		},
	},

	armt4olympus = {
		title = "Olympus, the Thunderer", role = "Strategic artillery", aiRole = "back", xpRate = 0.25,
		fx = 2.5,
		weapons = { { keys = { "shocker_low", "shocker_high" }, name = "Plasma Artillery", kind = "artillery" } },
		a1 = {
			name = "Spotter Uplink", kind = "stats", passive = true,
			desc = "Sight and radar of a spotter satellite",
			ranks = { { sight = 400, radar = 1200 }, { sight = 800, radar = 2400 }, { sight = 1200, radar = 3600 } },
			text = { "+400 sight, +1200 radar", "+800 sight, +2400 radar", "+1200 sight, +3600 radar" },
		},
		a2 = {
			name = "Blast Shield", kind = "active_shield", cmd = 36102, action = "hero_blastshield", fx = "hero-shield",
			desc = "A shield plate absorbs the damage Olympus takes",
			duration = { 8, 10, 12 }, absorb = { 15000, 30000, 50000 }, cooldown = { 40, 35, 30 },
			text = { "absorbs 15000 damage for 8 s, cd 40 s", "30000 for 10 s, cd 35 s", "50000 for 12 s, cd 30 s" },
		},
		ult = {
			name = "Orbital Strike", kind = "active_barrage", cmd = 36107, action = "hero_orbital", target = "map",
			desc = "Calls heavy plasma shells from orbit onto an area within 6000; rank 3 ends in a nuclear strike",
			projectile = "shell", range = 6000, radius = 450, count = { 8, 12, 18 }, dmg = { 5000, 6500, 8000 }, aoe = 260,
			stun = { 1, 1.5, 2 }, duration = 4, nova = { 0, 0, 15000 }, novaRadius = 600, targetFx = "hero-target-orbital",
			cooldown = { 120, 105, 90 },
			text = { "8 shells x 5000 dmg (260 radius), 1 s stun, cd 120 s", "12 shells x 6500 dmg, cd 105 s", "18 shells x 8000 dmg + 15000 nuke, cd 90 s" },
		},
	},

	armt4aegis = {
		title = "Aegis, the Warden", role = "Shield bearer", aiRole = "center",
		fx = 2.5,
		weapons = { { keys = { "mech_rapidlaser" }, name = "Rapid Lasers", kind = "beam" } },
		a1 = {
			name = "Deflector Matrix", kind = "shield_cap", passive = true,
			desc = "Capacity and recharge of the plasma deflector over the army (unlearned: 2700 shield)",
			cap = { 0.5, 0.75, 1.0 }, base = 0.3, regen = { 1.5, 2.0, 2.6 },
			text = { "4500 shield, 270 HP/s recharge", "6750 shield, 360 HP/s", "9000 shield, 470 HP/s" },
		},
		a2 = {
			name = "Pulse Overload", kind = "active_nova", cmd = 36103, action = "hero_pulse", fx = "hero-nova-emp",
			desc = "Dumps half of the shield charge as an EMP shockwave that stuns everything around",
			radius = { 500, 600, 700 }, dmg = { 1500, 2500, 3500 }, stun = { 3, 4, 5 }, shieldRatio = { 1.0, 1.4, 1.8 },
			cooldown = { 35, 30, 25 },
			text = { "1500 dmg + the charge, 500 radius, 3 s stun, cd 35 s", "2500 + 1.4x charge, 600 radius, 4 s, cd 30 s", "3500 + 1.8x charge, 700 radius, 5 s, cd 25 s" },
		},
		ult = {
			name = "Aegis Dome", kind = "active_dome", cmd = 36104, action = "hero_dome",
			desc = "Allies under the dome cannot be damaged",
			radius = { 800, 900, 1000 }, duration = { 4, 6, 8 }, cooldown = { 120, 110, 100 },
			text = { "800 radius, 4 s invulnerable, cd 120 s", "900 radius, 6 s, cd 110 s", "1000 radius, 8 s, cd 100 s" },
		},
	},

	armt4zeus = {
		title = "Zeus Prime, the Stormlord", role = "EMP / lightning", aiRole = "front",
		fx = 2.2,
		weapons = { { keys = { "thunder" }, name = "Thunder Coil", kind = "lightning" }, { keys = { "empmissile" }, name = "EMP Missiles", kind = "emp" }, { keys = { "emp" }, name = "EMP Beams", kind = "beam" } },
		a1 = {
			name = "Chain Lightning", kind = "proc_chain", passive = true,
			desc = "Hits may call a lightning bolt that jumps from the target to the enemies next to it",
			chance = { 0.2, 0.3, 0.4 }, dmg = { 1500, 2500, 3500 }, jumps = { 2, 3, 5 }, radius = 500,
			text = { "20% per shot: 1500 dmg, 2 jumps", "30%: 2500 dmg, 3 jumps", "40%: 3500 dmg, 5 jumps" },
		},
		a2 = {
			name = "Static Field", kind = "aura_emp", passive = true,
			desc = "Every 2 seconds enemies around are shocked and paralysed",
			radius = { 450, 550, 650 }, dmg = { 250, 500, 800 }, emp = { 2500, 5000, 8000 }, period = 2,
			text = { "450 radius, 250 dmg + 2500 EMP", "550 radius, 500 + 5000 EMP", "650 radius, 800 + 8000 EMP" },
		},
		ult = {
			name = "Wrath of the Storm", kind = "active_barrage", cmd = 36105, action = "hero_storm", target = "map",
			desc = "A lightning storm over an area within 2400; rank 3 ends in an EMP blast that stuns everything",
			projectile = "bolt", range = 2400, radius = 600, count = { 16, 24, 34 }, dmg = { 2500, 3200, 4000 },
			emp = { 4000, 6000, 8000 }, aoe = 150, duration = 5, targetFx = "hero-storm-cloud",
			nova = { 0, 0, 12000 }, novaStun = 5, novaRadius = 650, novaFx = "hero-finale-emp", cooldown = { 90, 80, 70 },
			text = { "16 bolts x 2500 dmg + 4000 EMP, cd 90 s", "24 bolts x 3200 + 6000 EMP, cd 80 s", "34 bolts x 4000 + EMP blast (12000, 5 s stun), cd 70 s" },
		},
	},

	---------------------------------------------------------------------------- Cortex
	cort4colossus = {
		title = "Colossus, the Warlord", role = "Flagship", aiRole = "front",
		fx = 2.2,
		weapons = { { keys = { "corkorg_fire" }, name = "Plasma Scatter Gun", kind = "shotgun" }, { keys = { "corkorg_laser" }, name = "Heat Eye", kind = "beam" }, { keys = { "corkorg_rocket" }, name = "Warlord Rockets", kind = "rockets" } },
		a1 = {
			name = "War Stomp", kind = "active_nova", cmd = 36111, action = "hero_stomp", fx = "hero-nova-kinetic",
			desc = "Slams the ground: damages and stuns everything around",
			radius = { 450, 550, 650 }, dmg = { 3000, 5500, 8500 }, stun = { 2, 3, 4 }, cooldown = { 30, 27, 24 },
			text = { "450 radius, 3000 dmg, 2 s stun, cd 30 s", "550 radius, 5500 dmg, 3 s, cd 27 s", "650 radius, 8500 dmg, 4 s, cd 24 s" },
		},
		a2 = {
			name = "Command Aura", kind = "aura_damage", passive = true,
			desc = "Allied units around deal more damage",
			radius = 900, mult = { 0.08, 0.16, 0.25 },
			text = { "900 radius, +8% damage", "+16% damage", "+25% damage" },
		},
		ult = {
			name = "Undying", kind = "undying", passive = true,
			desc = "A lethal blow instead leaves Colossus standing, healed, and reborn in a nuclear blast",
			cooldown = { 240, 200, 160 }, heal = { 0.4, 0.6, 0.8 }, nova = { 8000, 14000, 22000 }, novaRadius = 700,
			text = { "back at 40% HP, 8000 dmg blast (700), cd 240 s", "60% HP, 14000 dmg, cd 200 s", "80% HP, 22000 dmg, cd 160 s" },
		},
	},

	cort4bastion = {
		title = "Bastion, the Citadel", role = "Walking fortress", aiRole = "front",
		fx = 2.2,
		weapons = { { keys = { "juggernaut_fire" }, name = "Gauss Cannon", kind = "rail" }, { keys = { "juggernaut_bottom", "juggernaut_top" }, name = "Laser Turrets", kind = "beam" } },
		a1 = {
			name = "Reactive Armor", kind = "stats", passive = true,
			desc = "Less damage taken, faster self-repair",
			ranks = { { armor = 0.08, regen = 300 }, { armor = 0.16, regen = 600 }, { armor = 0.24, regen = 1000 } },
			text = { "-8% damage taken, +300 HP/s", "-16%, +600 HP/s", "-24%, +1000 HP/s" },
		},
		a2 = {
			name = "Siege Protocol", kind = "active_buff", cmd = 36112, action = "hero_siege", fx = "hero-siege",
			desc = "Anchors in place: hardened armor, fast repair, a stronger shield",
			buff = { immobile = true, armor = { 0.3, 0.4, 0.5 }, regen = { 1000, 2000, 3000 }, shieldRegen = 3 },
			duration = { 8, 10, 12 }, cooldown = { 40, 35, 30 },
			text = { "8 s: -30% damage taken, +1000 HP/s, cd 40 s", "10 s: -40%, +2000 HP/s, cd 35 s", "12 s: -50%, +3000 HP/s, cd 30 s" },
		},
		ult = {
			name = "Citadel", kind = "active_guard", cmd = 36115, action = "hero_citadel", fx = "hero-citadel-cast", tickFx = "hero-citadel",
			desc = "Raises an armor dome: every ally inside takes far less damage",
			radius = { 900, 1000, 1100 }, reduce = { 0.4, 0.55, 0.7 }, duration = { 8, 10, 12 }, cooldown = { 110, 100, 90 },
			text = { "900 radius, -40% damage taken for 8 s, cd 110 s", "1000 radius, -55% for 10 s, cd 100 s", "1100 radius, -70% for 12 s, cd 90 s" },
		},
	},

	cort4armageddon = {
		title = "Armageddon, the Doomsayer", role = "Rocket artillery", aiRole = "back", xpRate = 0.15,
		fx = 2.5,
		weapons = { { keys = { "exp_heavyrocket" }, name = "Heavy Rocket Racks", kind = "rockets" } },
		a1 = {
			name = "Salvage Nanites", kind = "lifesteal", passive = true,
			desc = "Part of the damage the rockets deal repairs Armageddon",
			frac = { 0.05, 0.08, 0.12 },
			text = { "heals 5% of damage dealt", "8%", "12%" },
		},
		a2 = {
			name = "Hunter Swarm", kind = "active_missiles", cmd = 36116, action = "hero_swarm",
			desc = "Homing rockets at the most valuable enemies within 2400",
			radius = 2400, count = { 8, 12, 16 }, dmg = { 1500, 2200, 3000 }, aoe = 140, cooldown = { 35, 30, 25 },
			text = { "8 rockets x 1500 dmg (140 radius), cd 35 s", "12 x 2200 dmg, cd 30 s", "16 x 3000 dmg, cd 25 s" },
		},
		ult = {
			name = "Armageddon Protocol", kind = "active_barrage", cmd = 36117, action = "hero_armageddon", target = "map",
			desc = "A rain of rockets on an area within 3200, sealed with a tactical nuke",
			projectile = "missile", range = 3200, radius = 700, count = { 24, 32, 40 }, dmg = { 1800, 2400, 3000 }, aoe = 200,
			duration = 4, nova = { 10000, 15000, 22000 }, novaRadius = 550, cooldown = { 120, 110, 100 },
			text = { "24 rockets x 1800 dmg + 10000 nuke, cd 120 s", "32 x 2400 + 15000 nuke, cd 110 s", "40 x 3000 + 22000 nuke, cd 100 s" },
		},
	},

	cort4hellwalker = {
		title = "Hellwalker, the Inferno", role = "Flame assault", aiRole = "front",
		fx = 2.5,
		weapons = { { keys = { "newdmaw" }, name = "Hellfire Maw", kind = "flame" }, { keys = { "karg_shoulder" }, name = "Shoulder Missiles", kind = "rockets" } },
		a1 = {
			name = "Immolation", kind = "aura_burn", passive = true,
			desc = "Burns every enemy around, every second",
			radius = { 320, 400, 480 }, dps = { 450, 900, 1500 },
			text = { "320 radius, 450 dmg/s", "400 radius, 900 dmg/s", "480 radius, 1500 dmg/s" },
		},
		a2 = {
			name = "Hellcharge", kind = "active_dash", cmd = 36113, action = "hero_hellcharge", target = "map", cursor = "Move",
			desc = "Charges through the enemy line, burning everything it passes and leaving fire behind",
			range = { 700, 850, 1000 }, dmg = { 2500, 4000, 6000 }, radius = 220, burn = { 600, 1000, 1500 },
			cooldown = { 24, 21, 18 },
			text = { "700 range, 2500 dmg, fire 600 dmg/s for 4 s, cd 24 s", "850, 4000 dmg, fire 1000/s, cd 21 s", "1000, 6000 dmg, fire 1500/s, cd 18 s" },
		},
		ult = {
			name = "Rain of Fire", kind = "active_barrage", cmd = 36114, action = "hero_rainfire", target = "map",
			desc = "Meteors fall on an area within 1800; rank 3 ends in a fireball",
			projectile = "meteor", range = 1800, radius = 600, count = { 14, 22, 32 }, dmg = { 3000, 4000, 5000 }, aoe = 220,
			duration = 6, nova = { 0, 0, 18000 }, novaRadius = 600, novaFx = "hero-finale-fire", cooldown = { 90, 80, 70 },
			text = { "14 meteors x 3000 dmg (220 radius), cd 90 s", "22 x 4000 dmg, cd 80 s", "32 x 5000 dmg + 18000 fireball, cd 70 s" },
		},
	},

	---------------------------------------------------------------------------- Legion
	legt4helios = {
		title = "Helios, the Sunbringer", role = "Heat / support", aiRole = "center",
		fx = 2.2,
		weapons = { { keys = { "heatray1" }, name = "Heat Ray", kind = "beam" }, { keys = { "ultraheavyriotcannon" }, name = "Riot Cannon", kind = "cannon" }, { keys = { "legflak_gun" }, name = "Flak Battery", kind = "cannon" } },
		a1 = {
			name = "Solar Flare", kind = "active_nova", cmd = 36121, action = "hero_flare", fx = "hero-nova-fire",
			desc = "A blinding burst: burns enemies around and repairs allies",
			radius = { 600, 700, 800 }, dmg = { 4000, 6500, 9500 }, heal = { 3000, 5000, 8000 }, cooldown = { 35, 30, 25 },
			text = { "600 radius, 4000 dmg, allies +3000 HP, cd 35 s", "700, 6500 dmg, +5000 HP, cd 30 s", "800, 9500 dmg, +8000 HP, cd 25 s" },
		},
		a2 = {
			name = "Heat Haze", kind = "aura_slow", passive = true,
			desc = "Enemies around wade through shimmering heat and move slower",
			radius = { 600, 700, 800 }, slow = { 0.2, 0.3, 0.4 },
			text = { "600 radius, -20% speed", "700 radius, -30%", "800 radius, -40%" },
		},
		ult = {
			name = "Sunstrike", kind = "active_beam", cmd = 36122, action = "hero_sunstrike", target = "map",
			desc = "A beam of the sun burns an area for 6 seconds, creeping after the enemies; rank 3 ends in a nuclear flare",
			range = 2200, radius = 300, tick = { 1500, 2200, 3000 }, duration = 6, drift = 90,
			nova = { 0, 0, 16000 }, novaRadius = 600, cooldown = { 90, 80, 70 },
			text = { "300 radius, 1500 dmg per 0.2 s for 6 s, cd 90 s", "2200 per 0.2 s, cd 80 s", "3000 per 0.2 s + 16000 flare, cd 70 s" },
		},
	},

	legt4starfall = {
		title = "Starfall, the Astronomer", role = "Orbital artillery", aiRole = "back", xpRate = 0.25,
		fx = 2.5,
		weapons = { { keys = { "shocker_low" }, name = "Starfire Cannon", kind = "artillery" } },
		a1 = {
			name = "Deep Sky Radar", kind = "stats", passive = true,
			desc = "Radar and sight reach deep into enemy land",
			ranks = { { radar = 1500, sight = 500 }, { radar = 3000, sight = 1000 }, { radar = 4500, sight = 1500 } },
			text = { "+1500 radar, +500 sight", "+3000 radar, +1000 sight", "+4500 radar, +1500 sight" },
		},
		a2 = {
			name = "Starburst Rounds", kind = "proc_blast", passive = true,
			desc = "Plasma rounds may burst into a star blast around what they hit",
			chance = { 0.25, 0.4, 0.55 }, dmg = { 1500, 2500, 3500 }, radius = { 200, 240, 280 }, fx = "hero-blast-star",
			text = { "25% per shot: 1500 dmg in 200", "40%: 2500 dmg in 240", "55%: 3500 dmg in 280" },
		},
		ult = {
			name = "Meteor Storm", kind = "active_barrage", cmd = 36123, action = "hero_meteorstorm", target = "map",
			desc = "Calls plasma meteors from orbit anywhere within 9000; rank 3 ends with a nuke",
			projectile = "star", range = 9000, radius = 750, count = { 10, 16, 24 }, dmg = { 5000, 6000, 7000 }, aoe = 300,
			duration = 8, nova = { 0, 0, 20000 }, novaRadius = 700, cooldown = { 120, 105, 90 },
			text = { "10 meteors x 5000 dmg (300 radius), cd 120 s", "16 x 6000 dmg, cd 105 s", "24 x 7000 dmg + 20000 nuke, cd 90 s" },
		},
	},

	legt4longinus = {
		title = "Longinus, the Spear", role = "Titan hunter", aiRole = "center",
		fx = 2.2,
		weapons = { { keys = { "t3_rail_accelerator" }, name = "Rail Accelerators", kind = "rail" } },
		a1 = {
			name = "Titan Slayer", kind = "slayer", passive = true,
			desc = "More damage against expensive targets (10000+ metal)",
			minCost = 10000, mult = { 0.25, 0.5, 0.8 },
			text = { "+25% damage vs 10000+ metal", "+50%", "+80%" },
		},
		a2 = {
			name = "Phase Cloak", kind = "active_cloak", cmd = 36127, action = "hero_phase",
			desc = "Fades from sight and moves faster; holds fire until the cloak ends, an order to attack breaks it",
			duration = { 6, 9, 12 }, speed = 0.4, cooldown = { 40, 35, 30 },
			text = { "invisible for 6 s, +40% speed, cd 40 s", "9 s, cd 35 s", "12 s, cd 30 s" },
		},
		ult = {
			name = "Spear of Longinus", kind = "active_spear", cmd = 36124, action = "hero_spear", target = "unit",
			desc = "One colossal rail shot through everything in its line; rank 3 detonates a nuke on impact",
			range = { 2400, 2800, 3200 }, pct = { 0.15, 0.25, 0.35 }, flat = { 15000, 20000, 25000 }, line = { 5000, 8000, 12000 },
			nova = { 0, 0, 20000 }, novaRadius = 600, cooldown = { 90, 75, 60 },
			text = { "15% of max HP + 15000, 5000 to the line, cd 90 s", "25% + 20000, line 8000, cd 75 s", "35% + 25000, line 12000, 20000 nuke, cd 60 s" },
		},
	},

	legt4tempest = {
		title = "Tempest, the Stormblade", role = "Melee assault", aiRole = "front",
		fx = 2.5,
		weapons = { { keys = { "shotgun" }, name = "Storm Shotgun", kind = "shotgun" }, { keys = { "adv_rocket" }, name = "Rocket Pods", kind = "rockets" }, { keys = { "leg_t2_microflak_mobile" }, name = "Micro Flak", kind = "cannon" } },
		a1 = {
			name = "Critical Strike", kind = "crit", passive = true,
			desc = "A chance to deal multiplied damage",
			chance = { 0.15, 0.25, 0.35 }, mult = { 2.5, 3.0, 3.5 },
			text = { "15% chance of x2.5 damage", "25% of x3", "35% of x3.5" },
		},
		a2 = {
			name = "Mirror Images", kind = "active_summon", cmd = 36125, action = "hero_mirror",
			desc = "Storm images of its shotgun mech fight at Tempest's side for a while",
			unit = "legeshotgunmech", count = { 1, 2, 3 }, duration = { 15, 20, 25 }, cooldown = { 45, 40, 35 },
			text = { "1 image for 15 s, cd 45 s", "2 images for 20 s, cd 40 s", "3 images for 25 s, cd 35 s" },
		},
		ult = {
			name = "Bladestorm", kind = "active_bladestorm", cmd = 36126, action = "hero_bladestorm",
			desc = "Spins into a storm of blades: shreds everything around, takes half damage",
			radius = { 420, 500, 580 }, dmg = { 900, 1500, 2300 }, duration = 6, armor = 0.5, cooldown = { 75, 65, 55 },
			text = { "420 radius, 900 dmg per 0.2 s for 6 s, cd 75 s", "500, 1500 per 0.2 s, cd 65 s", "580, 2300 per 0.2 s, cd 55 s" },
		},
	},
}

return heroes, {
	"armt4atlas", "armt4olympus", "armt4aegis", "armt4zeus",
	"cort4colossus", "cort4bastion", "cort4armageddon", "cort4hellwalker",
	"legt4helios", "legt4starfall", "legt4longinus", "legt4tempest",
}
