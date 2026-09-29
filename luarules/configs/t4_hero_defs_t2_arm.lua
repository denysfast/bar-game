-- Custom heroes (denysfast/bar-game): the ten Armada T2 heroes (altar: armt2hall). Included by luarules/configs/t4_heroes.lua,
-- which passes the shared table H. See CUSTOM.md, section "Heroes".
-- Unitdefs: units/ArmT2Heroes/armt2heroes.lua. Abilities use the v15 ability kit only (kinds and parameters
-- implemented by the hero gadget); every value is absolute (HP, damage, elmos, seconds), per rank { r1, r2, r3 }.
-- Command ids: 36201-36299.
local H = ...

local heroes = {
	-- Boomer, the Demolisher (Fatboy x1.5)
	armt2boomer = {
		title = "Boomer, the Demolisher", role = "Siege / demolition", aiRole = "center",
		fx = 1.6,
		weapons = { { keys = { "arm_fatboy_notalaser" }, name = "Siege Plasma Cannon", kind = "plasma" } },
		a1 = {
			name = "Shockwave Shells", kind = "proc_blast", passive = true,
			desc = "Plasma hits may set off a second shockwave on the target",
			chance = { 0.25, 0.35, 0.45 }, dmg = { 500, 900, 1400 }, radius = { 150, 190, 230 },
			text = { "25% chance: 500 damage in 150", "35%: 900 in 190", "45%: 1400 in 230" },
		},
		a2 = {
			name = "Dig In", kind = "active_buff", cmd = 36201, action = "hero_boomer_digin", fx = "hero-buff-armor",
			desc = "Boomer anchors in place: takes less damage and hits harder",
			buff = { immobile = true, armor = 0.3, damage = 0.3 }, duration = { 8, 10, 12 }, cooldown = { 40, 36, 32 },
			text = { "8 s: -30% damage taken, +30% damage, cd 40s", "10 s, cd 36s", "12 s, cd 32s" },
		},
		ult = {
			name = "Carpet Bombardment", kind = "active_barrage", cmd = 36202, action = "hero_boomer_carpet", target = "map",
			desc = "Plasma shells rain down on an area for 5 seconds",
			range = 1500, radius = 420, count = { 12, 18, 26 }, duration = 5, dmg = { 700, 1000, 1400 },
			projectile = "shell", cooldown = { 90, 80, 70 },
			text = { "12 shells x 700, cd 90s", "18 x 1000, cd 80s", "26 x 1400, cd 70s" },
		},
	},

	-- Deadeye, the Silent Hunter (Sharpshooter x1.6)
	armt2deadeye = {
		title = "Deadeye, the Silent Hunter", role = "Assassin / sniper", aiRole = "back",
		fx = 1.4,
		weapons = { { keys = { "old_armsnipe_weapon" }, name = "Armor-Piercing Rifle", kind = "sniper" } },
		a1 = {
			name = "Headshot", kind = "crit", passive = true,
			desc = "A share of the shots hit a weak spot for multiplied damage",
			chance = { 0.15, 0.22, 0.3 }, mult = { 1.75, 2.25, 2.75 },
			text = { "15% chance for x1.75", "22% for x2.25", "30% for x2.75" },
		},
		a2 = {
			name = "Ghost Protocol", kind = "active_cloak", cmd = 36203, action = "hero_deadeye_ghost", fx = "hero-cloak",
			desc = "Vanishes from sight and moves faster, free of the cloak's energy upkeep",
			duration = { 8, 12, 16 }, speed = 0.25, cooldown = { 45, 40, 35 },
			text = { "8 s cloak, +25% speed, cd 45s", "12 s cloak, cd 40s", "16 s cloak, cd 35s" },
		},
		ult = {
			name = "Execution Round", kind = "active_spear", cmd = 36204, action = "hero_deadeye_execute", target = "unit",
			desc = "One round through the target and everything behind it: a share of the target's max HP plus a fixed hit",
			range = { 1600, 1900, 2200 }, pct = { 0.12, 0.18, 0.25 }, flat = 3000, line = 2500,
			cooldown = { 60, 55, 50 },
			text = { "12% max HP + 3000, range 1600, cd 60s", "18%, range 1900, cd 55s", "25%, range 2200, cd 50s" },
		},
	},

	-- Outlaw, the Gunslinger (Maverick x1.5)
	armt2outlaw = {
		title = "Outlaw, the Gunslinger", role = "Skirmisher", aiRole = "front",
		fx = 1.5,
		weapons = { { keys = { "armmav_weapon" }, name = "Gauss Impulse Guns", kind = "rail" } },
		a1 = {
			name = "Impulse Dash", kind = "active_dash", cmd = 36205, action = "hero_outlaw_dash", target = "map", fx = "hero-dash",
			desc = "Dashes to a point, hitting every enemy on the way",
			range = { 500, 650, 800 }, dmg = { 400, 800, 1300 }, radius = 120, cooldown = { 20, 17, 14 },
			text = { "500 dash, 400 damage, cd 20s", "650 dash, 800 damage, cd 17s", "800 dash, 1300 damage, cd 14s" },
		},
		a2 = {
			name = "Scavenger Rounds", kind = "lifesteal", passive = true,
			desc = "A share of the damage dealt repairs the Outlaw",
			frac = { 0.08, 0.14, 0.2 },
			text = { "8% of damage as HP", "14% of damage as HP", "20% of damage as HP" },
		},
		ult = {
			name = "Bullet Storm", kind = "active_bladestorm", cmd = 36206, action = "hero_outlaw_storm",
			desc = "Spins its guns: hits everything around several times a second and shrugs off damage",
			radius = { 350, 420, 500 }, dmg = { 250, 400, 600 }, duration = 6, armor = 0.4, cooldown = { 75, 65, 55 },
			text = { "350 radius, 250 per 0.25 s, cd 75s", "420 radius, 400, cd 65s", "500 radius, 600, cd 55s" },
		},
	},

	-- Hound, the Pack Leader (Fido x1.6)
	armt2hound = {
		title = "Hound, the Pack Leader", role = "Pack leader / summoner", aiRole = "center",
		fx = 1.5,
		weapons = { { keys = { "bfido" }, name = "Plasma Lobber", kind = "mortar" } },
		a1 = {
			name = "Pack Tactics", kind = "aura_damage", passive = true,
			desc = "Allied units around the Hound deal more damage",
			radius = 700, mult = { 0.06, 0.12, 0.18 },
			text = { "+6% damage in 700", "+12%", "+18%" },
		},
		a2 = {
			name = "Call the Pack", kind = "active_summon", cmd = 36207, action = "hero_hound_pack", fx = "hero-summon",
			desc = "Fidos join the Hound for a while",
			unit = "armfido", count = { 2, 3, 4 }, duration = { 30, 35, 40 }, cooldown = { 50, 45, 40 },
			text = { "2 Fidos for 30 s, cd 50s", "3 for 35 s, cd 45s", "4 for 40 s, cd 40s" },
		},
		ult = {
			name = "Release the Bulldogs", kind = "active_summon", cmd = 36208, action = "hero_hound_bulldogs", fx = "hero-summon",
			desc = "Heavy Bulldog tanks roll out to fight beside the Hound",
			unit = "armbull", count = { 2, 3, 4 }, duration = { 30, 35, 40 }, cooldown = { 100, 90, 80 },
			text = { "2 Bulldogs for 30 s, cd 100s", "3 for 35 s, cd 90s", "4 for 40 s, cd 80s" },
		},
	},

	-- Tesla, the Arc Knight (Zeus x1.5)
	armt2tesla = {
		title = "Tesla, the Arc Knight", role = "Brawler / lightning", aiRole = "front",
		fx = 1.5,
		weapons = { { keys = { "lightning" }, name = "Arc Rifle", kind = "lightning" } },
		a1 = {
			name = "Arc Discharge", kind = "proc_chain", passive = true,
			desc = "Hits may throw a separate chain lightning to more enemies",
			chance = { 0.25, 0.35, 0.45 }, dmg = { 250, 450, 700 }, jumps = { 2, 3, 4 }, radius = 450,
			text = { "25% chance: 250 damage, 2 jumps", "35%: 450, 3 jumps", "45%: 700, 4 jumps" },
		},
		a2 = {
			name = "Static Field", kind = "aura_emp", passive = true,
			desc = "Enemies around are shocked and paralysed every 2 seconds",
			radius = { 300, 380, 460 }, dmg = { 100, 200, 320 }, emp = { 800, 1600, 2600 }, period = 2,
			text = { "300 radius, 100 damage, 800 EMP", "380 radius, 200 damage, 1600 EMP", "460 radius, 320 damage, 2600 EMP" },
		},
		ult = {
			name = "Thunderstorm", kind = "active_barrage", cmd = 36209, action = "hero_tesla_storm", target = "map",
			desc = "Calls lightning bolts down on an area",
			range = 1400, radius = 420, count = { 10, 15, 22 }, duration = 5, dmg = { 600, 900, 1300 },
			projectile = "bolt", cooldown = { 90, 80, 70 },
			text = { "10 bolts x 600, cd 90s", "15 x 900, cd 80s", "22 x 1300, cd 70s" },
		},
	},

	-- Widow, the Rocket Matriarch (Recluse x1.5)
	armt2widow = {
		title = "Widow, the Rocket Matriarch", role = "All-terrain missiles", aiRole = "back",
		fx = 1.5,
		weapons = { { keys = { "adv_rocket" }, name = "Brood Rockets", kind = "missiles" } },
		a1 = {
			name = "Venom Volley", kind = "active_missiles", cmd = 36210, action = "hero_widow_volley", fx = "hero-missile-launch",
			desc = "Launches homing missiles at up to N enemies around",
			radius = 900, count = { 4, 6, 9 }, dmg = { 400, 600, 850 }, cooldown = { 25, 22, 19 },
			text = { "4 missiles x 400, cd 25s", "6 x 600, cd 22s", "9 x 850, cd 19s" },
		},
		a2 = {
			name = "Skitter", kind = "active_buff", cmd = 36211, action = "hero_widow_skitter", fx = "hero-buff-speed",
			desc = "Scuttles away fast and hard to hit",
			buff = { speed = 0.6, armor = 0.25 }, duration = { 4, 5, 6 }, cooldown = { 30, 26, 22 },
			text = { "4 s: +60% speed, -25% damage taken, cd 30s", "5 s, cd 26s", "6 s, cd 22s" },
		},
		ult = {
			name = "Hatch the Brood", kind = "active_summon", cmd = 36212, action = "hero_widow_brood", fx = "hero-summon",
			desc = "Recluse spiders hatch around the Widow",
			unit = "armsptk", count = { 3, 5, 7 }, duration = { 25, 30, 35 }, cooldown = { 100, 90, 80 },
			text = { "3 Recluses for 25 s, cd 100s", "5 for 30 s, cd 90s", "7 for 35 s, cd 80s" },
		},
	},

	-- Starlight, the Dawn Lance (Starlight x1.5)
	armt2starlight = {
		title = "Starlight, the Dawn Lance", role = "Tank destroyer", aiRole = "back",
		fx = 1.6,
		weapons = { { keys = { "atam" }, name = "Tachyon Lance", kind = "beam" } },
		a1 = {
			name = "Tank Buster", kind = "slayer", passive = true,
			desc = "More damage against expensive targets (1500 metal and up)",
			minCost = 1500, mult = { 0.2, 0.4, 0.6 },
			text = { "+20% vs 1500+ metal", "+40%", "+60%" },
		},
		a2 = {
			name = "Focusing Lens", kind = "active_buff", cmd = 36213, action = "hero_starlight_focus", fx = "hero-buff-power",
			desc = "Stops to focus the beam: more damage for a few seconds",
			buff = { immobile = true, damage = 0.4 }, duration = { 6, 8, 10 }, cooldown = { 40, 36, 32 },
			text = { "6 s: +40% damage, cd 40s", "8 s, cd 36s", "10 s, cd 32s" },
		},
		ult = {
			name = "Orbital Lance", kind = "active_beam", cmd = 36214, action = "hero_starlight_lance", target = "map",
			desc = "A tachyon beam from orbit burns an area; rank 3 ends in a blast",
			range = 1800, radius = 220, tick = { 450, 700, 1000 }, duration = 5, nova = { false, false, true },
			cooldown = { 90, 80, 70 },
			text = { "450 per 0.2 s for 5 s, cd 90s", "700, cd 80s", "1000 + final blast, cd 70s" },
		},
	},

	-- Bulldog, the Iron Wall (Bulldog x1.5)
	armt2bulldog = {
		title = "Bulldog, the Iron Wall", role = "Armoured spearhead", aiRole = "front",
		fx = 1.6,
		weapons = { { keys = { "arm_bull" }, name = "Heavy Plasma Cannon", kind = "cannon" } },
		a1 = {
			name = "Reinforced Hull", kind = "stats", passive = true,
			desc = "Thicker armour and self-repair",
			ranks = { { hp = 3000, armor = 0.06, regen = 20 }, { hp = 6000, armor = 0.12, regen = 40 }, { hp = 9000, armor = 0.18, regen = 60 } },
			text = { "+3000 HP, -6% damage taken, +20 HP/s", "+6000 HP, -12% damage taken, +40 HP/s", "+9000 HP, -18% damage taken, +60 HP/s" },
		},
		a2 = {
			name = "Battering Ram", kind = "active_dash", cmd = 36215, action = "hero_bulldog_ram", target = "map", fx = "hero-dash",
			desc = "Charges to a point, crushing every enemy on the way",
			range = { 400, 500, 600 }, dmg = { 800, 1400, 2100 }, radius = 150, cooldown = { 25, 22, 19 },
			text = { "400 charge, 800 damage, cd 25s", "500 charge, 1400 damage, cd 22s", "600 charge, 2100 damage, cd 19s" },
		},
		ult = {
			name = "Iron Wall", kind = "active_guard", cmd = 36216, action = "hero_bulldog_wall", fx = "hero-buff-armor",
			desc = "Allies within 800 take less damage for 10 seconds",
			radius = 800, reduce = { 0.25, 0.35, 0.45 }, duration = 10, cooldown = { 90, 80, 70 },
			text = { "-25% damage taken, cd 90s", "-35% damage taken, cd 80s", "-45% damage taken, cd 70s" },
		},
	},

	-- Envoy, the Ambassador of Ruin (Ambassador x1.5)
	armt2envoy = {
		title = "Envoy, the Ambassador of Ruin", role = "Long-range rockets", aiRole = "back", xpRate = 0.5,
		fx = 1.6,
		weapons = { { keys = { "armtruck_rocket" }, name = "Starburst Rockets", kind = "rockets" } },
		a1 = {
			name = "Forward Observer", kind = "stats", passive = true,
			desc = "Longer sight and radar",
			ranks = { { sight = 150, radar = 400 }, { sight = 300, radar = 800 }, { sight = 450, radar = 1200 } },
			text = { "+150 sight, +400 radar", "+300 sight, +800 radar", "+450 sight, +1200 radar" },
		},
		a2 = {
			name = "Countermeasures", kind = "active_shield", cmd = 36217, action = "hero_envoy_shield", fx = "hero-shield",
			desc = "A barrier absorbs incoming damage",
			duration = { 6, 8, 10 }, absorb = { 3000, 5500, 8500 }, cooldown = { 40, 36, 32 },
			text = { "absorbs 3000 for 6 s, cd 40s", "5500 for 8 s, cd 36s", "8500 for 10 s, cd 32s" },
		},
		ult = {
			name = "Final Ultimatum", kind = "active_barrage", cmd = 36218, action = "hero_envoy_ultimatum", target = "map",
			desc = "Tactical nukes fall on an area",
			range = 2600, radius = 350, count = { 1, 2, 3 }, duration = 4, dmg = { 5000, 6000, 7000 },
			projectile = "nuke", cooldown = { 150, 135, 120 },
			text = { "1 tactical nuke (5000), cd 150s", "2 nukes (6000), cd 135s", "3 nukes (7000), cd 120s" },
		},
	},

	-- Weaver, the Static Spinner (Webber x1.6)
	armt2weaver = {
		title = "Weaver, the Static Spinner", role = "EMP / support", aiRole = "center",
		fx = 1.4,
		weapons = { { keys = { "spider" }, name = "EMP Web Laser", kind = "emp" } },
		a1 = {
			name = "Tangle Web", kind = "aura_slow", passive = true,
			desc = "Enemies around are slowed",
			radius = { 350, 450, 550 }, slow = { 0.15, 0.25, 0.35 },
			text = { "-15% speed in 350", "-25% in 450", "-35% in 550" },
		},
		a2 = {
			name = "Field Repair", kind = "active_repair", cmd = 36219, action = "hero_weaver_repair", fx = "hero-nova-heal",
			desc = "Instantly repairs allies and structures around",
			radius = 600, heal = { 1200, 2200, 3500 }, cooldown = { 35, 31, 27 },
			text = { "+1200 HP in 600, cd 35s", "+2200, cd 31s", "+3500, cd 27s" },
		},
		ult = {
			name = "Grid Lock", kind = "active_nova", cmd = 36220, action = "hero_weaver_gridlock", fx = "hero-nova-emp",
			desc = "An EMP wave paralyses everything around",
			radius = { 450, 550, 650 }, dmg = { 400, 700, 1000 }, stun = { 4, 6, 8 }, emp = { 4000, 7000, 11000 },
			cooldown = { 80, 70, 60 },
			text = { "450 radius, 4 s stun, cd 80s", "550 radius, 6 s stun, cd 70s", "650 radius, 8 s stun, cd 60s" },
		},
	},
}

return heroes, {
	"armt2boomer", "armt2deadeye", "armt2outlaw", "armt2hound", "armt2tesla",
	"armt2widow", "armt2starlight", "armt2bulldog", "armt2envoy", "armt2weaver",
}
