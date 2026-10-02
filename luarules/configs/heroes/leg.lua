-- Custom heroes (denysfast/bar-game), v19: the Legion heroes (altar legt4gant). Included by
-- luarules/configs/t4_heroes.lua with the shared table H as `...`; returns `defs, order`. Format: header of
-- luarules/configs/heroes/arm.lua. v19 port of the v18 abilities (three ranks spread over ten); a3 is a placeholder.
local H = ...
local lin, tf = H.lin, H.textf

local heroes = {
	legt4helios = {
		title = "Helios, the Sunbringer", role = "Heat / support", aiRole = "center", aiPick = 2.5,
		fx = 2.2,
		weapons = { { keys = { "heatray1" }, name = "Heat Ray" }, { keys = { "ultraheavyriotcannon" }, name = "Riot Cannon" }, { keys = { "legflak_gun" }, name = "Flak Battery" } },
		a1 = {
			name = "Solar Flare", kind = "active_nova", cmd = 36321, action = "hero_flare", fx = "hero-nova-fire",
			desc = "A blinding burst: burns enemies around and repairs allies",
			radius = lin(600, 800, 10), dmg = lin(4000, 9500, 100), heal = lin(3000, 8000, 100), cooldown = lin(35, 25, 1),
			text = tf("{radius} radius, {dmg} dmg, allies +{heal} HP, cd {cooldown} s"),
		},
		a2 = {
			name = "Heat Haze", kind = "aura_slow", passive = true,
			desc = "Enemies around wade through shimmering heat and move slower",
			radius = lin(600, 800, 10), slow = lin(0.2, 0.4, 0.01),
			text = tf("{radius} radius, -{slow%} speed"),
		},
		a3 = {
			name = "Sunfire Rounds", kind = "proc_blast", passive = true,
			desc = "Shots may flare up around what they hit (placeholder)",
			chance = lin(0.1, 0.25, 0.01), dmg = lin(1000, 3000, 50), radius = 180, fx = "hero-nova-fire",
			text = tf("{chance%} per shot: {dmg} dmg in {radius}"),
		},
		ult = {
			name = "Sunstrike", kind = "active_beam", cmd = 36322, action = "hero_sunstrike", target = "map",
			desc = "A beam of the sun burns an area for 6 seconds, creeping after the enemies; high ranks end in a nuclear flare",
			range = 2200, radius = 300, tick = lin(1500, 3000, 50), duration = 6, drift = 90,
			nova = { 0, 0, 0, 0, 0, 0, 10000, 12000, 14000, 16000 }, novaRadius = 600, cooldown = lin(90, 70, 1),
			text = tf("{radius} radius, {tick} dmg per 0.2 s for 6 s, flare {nova}, cd {cooldown} s"),
		},
	},

	legt4starfall = {
		title = "Starfall, the Astronomer", role = "Orbital artillery", aiRole = "back", aiPick = 2, xpRate = 0.25,
		fx = 2.5,
		weapons = { { keys = { "shocker_low" }, name = "Starfire Cannon" } },
		a1 = {
			name = "Deep Sky Radar", kind = "stats", passive = true,
			desc = "Radar and sight reach deep into enemy land",
			radar = lin(1500, 4500, 50), sight = lin(500, 1500, 10),
			text = tf("+{radar} radar, +{sight} sight"),
		},
		a2 = {
			name = "Starburst Rounds", kind = "proc_blast", passive = true,
			desc = "Plasma rounds may burst into a star blast around what they hit",
			chance = lin(0.25, 0.55, 0.01), dmg = lin(1500, 3500, 50), radius = lin(200, 280, 10), fx = "hero-blast-star",
			text = tf("{chance%} per shot: {dmg} dmg in {radius}"),
		},
		a3 = {
			name = "Astral Plating", kind = "stats", passive = true,
			desc = "Less damage taken (placeholder)",
			armor = lin(0.02, 0.12, 0.01),
			text = tf("-{armor%} damage taken"),
		},
		ult = {
			name = "Meteor Storm", kind = "active_barrage", cmd = 36323, action = "hero_meteorstorm", target = "map",
			desc = "Calls plasma meteors from orbit anywhere within 9000; high ranks end with a nuke",
			projectile = "star", range = 9000, radius = 750, count = lin(10, 24, 1), dmg = lin(5000, 7000, 100), aoe = 300,
			duration = 8, nova = { 0, 0, 0, 0, 0, 0, 14000, 16000, 18000, 20000 }, novaRadius = 700, cooldown = lin(120, 90, 1),
			text = tf("{count} meteors x {dmg} dmg ({aoe} radius), nuke {nova}, cd {cooldown} s"),
		},
	},

	legt4longinus = {
		title = "Longinus, the Spear", role = "Titan hunter", aiRole = "center", aiPick = 2,
		fx = 2.2,
		weapons = { { keys = { "t3_rail_accelerator" }, name = "Rail Accelerators" } },
		a1 = {
			name = "Titan Slayer", kind = "slayer", passive = true,
			desc = "More damage against expensive targets (10000+ metal)",
			minCost = 10000, mult = lin(0.25, 0.8, 0.01),
			text = tf("+{mult%} damage vs 10000+ metal"),
		},
		a2 = {
			name = "Phase Cloak", kind = "active_cloak", cmd = 36327, action = "hero_phase",
			desc = "Fades from sight and moves faster; holds fire until the cloak ends, an order to attack breaks it",
			duration = lin(6, 12, 0.5), speed = 0.4, cooldown = lin(40, 30, 1),
			text = tf("invisible for {duration.1} s, +40% speed, cd {cooldown} s"),
		},
		a3 = {
			name = "Rail Capacitors", kind = "crit", passive = true,
			desc = "A chance of a double-strength shot (placeholder)",
			chance = lin(0.05, 0.2, 0.01), mult = 2,
			text = tf("{chance%} chance of x2 damage"),
		},
		ult = {
			name = "Spear of Longinus", kind = "active_spear", cmd = 36324, action = "hero_spear", target = "unit",
			desc = "One colossal rail shot through everything in its line; high ranks detonate a nuke on impact",
			range = lin(2400, 3200, 50), pct = lin(0.15, 0.35, 0.01), flat = lin(15000, 25000, 500), line = lin(5000, 12000, 500),
			nova = { 0, 0, 0, 0, 0, 0, 14000, 16000, 18000, 20000 }, novaRadius = 600, cooldown = lin(90, 60, 1),
			text = tf("{pct%} of max HP + {flat}, {line} to the line, nuke {nova}, cd {cooldown} s"),
		},
	},

	legt4tempest = {
		title = "Tempest, the Stormblade", role = "Melee assault", aiRole = "front", aiPick = 2.5,
		fx = 2.5,
		weapons = { { keys = { "shotgun" }, name = "Storm Shotgun" }, { keys = { "adv_rocket" }, name = "Rocket Pods" }, { keys = { "leg_t2_microflak_mobile" }, name = "Micro Flak" } },
		a1 = {
			name = "Critical Strike", kind = "crit", passive = true,
			desc = "A chance to deal multiplied damage",
			chance = lin(0.15, 0.35, 0.01), mult = lin(2.5, 3.5, 0.1),
			text = tf("{chance%} chance of x{mult.1} damage"),
		},
		a2 = {
			name = "Mirror Images", kind = "active_summon", cmd = 36325, action = "hero_mirror",
			desc = "Storm images of its shotgun mech fight at Tempest's side for a while",
			unit = "legeshotgunmech", count = lin(1, 3, 1), duration = lin(15, 25, 1), cooldown = lin(45, 35, 1),
			text = tf("{count} images for {duration} s, cd {cooldown} s"),
		},
		a3 = {
			name = "Storm Step", kind = "stats", passive = true,
			desc = "Faster (placeholder)",
			speed = lin(2, 12, 1),
			text = tf("+{speed} speed"),
		},
		ult = {
			name = "Bladestorm", kind = "active_bladestorm", cmd = 36326, action = "hero_bladestorm",
			desc = "Spins into a storm of blades: shreds everything around, takes half damage",
			radius = lin(420, 580, 10), dmg = lin(900, 2300, 50), duration = 6, armor = 0.5, cooldown = lin(75, 55, 1),
			text = tf("{radius} radius, {dmg} dmg per 0.2 s for 6 s, cd {cooldown} s"),
		},
	},
}

return heroes, { "legt4helios", "legt4starfall", "legt4longinus", "legt4tempest" }
