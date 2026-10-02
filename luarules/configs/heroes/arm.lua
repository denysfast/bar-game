-- Custom heroes (denysfast/bar-game), v19: the Armada heroes (altar armt4gant). Included by
-- luarules/configs/t4_heroes.lua with the shared table H as `...`; returns `defs, order`.
--
-- A hero def:
--   title, role, aiRole = "front" | "center" | "back", aiPick (weight of the AI's pick), fx (effect scale),
--   xpRate (share of the experience it earns), weapons = { { keys = { "<weapondef key>", ... }, name = "..." } }
--   a1, a2, a3 (abilities), ult (ultimate) - 10 ranks each, values per rank: a number, a 10-array or H.lin(a, b)
--   module = false | "<path>"   behaviour code, default luarules/heroes/<name>.lua when that file exists
--   weaponDefs = function(T4, ud) return { <key> = weapondef, ... } end   extra weapondefs of the unitdef
--                (<name>_<key>; api.fire spawns them), made by gamedata/custom_t4.lua T4.hero
--   weaponCopies = { <suffix> = { keys = { "<weapon key>", ... }, set = { <weapondef field> = value } } }
--                copies <key>_<suffix> for api.swapWeapons (a beam / lightning copy only draws: its damage is 0)
-- An ability: name, desc, icon, text (function(r, H, b) | 10 strings | H.textf(template)), passive = true or
--   cmd = <id: Armada 36101-36199, Cortex 36201-36299, Legion 36301-36399>, action = "hero_<name>", target = "unit" | "map" | "ally" | nil (self), range, cooldown;
--   kind = "custom" (the module does it) or a kind of the generic kit (header of luarules/gadgets/unit_t4_heroes.lua).
-- v19 port: the v18 abilities with their three ranks spread over ten (H.lin(rank 1, rank 3)); a3 is a placeholder
-- until the content agents redo the heroes. Thor (armt4zeus) is the worked example of the module API.
local H = ...
local lin, tf = H.lin, H.textf

local heroes = {
	armt4atlas = {
		title = "Atlas, the Bulwark", role = "Assault / support", aiRole = "front", aiPick = 3,
		fx = 2.5,
		weapons = { { keys = { "armbantha_fire" }, name = "Pulse Cannon" }, { keys = { "tehlazerofdewm" }, name = "Doom Laser" }, { keys = { "bantha_rocket" }, name = "Starburst Rockets" } },
		a1 = {
			name = "Repair Field", kind = "aura_heal", passive = true,
			desc = "Allies and structures around Atlas regain health every second",
			radius = lin(700, 1100, 10), rate = lin(120, 400, 10),
			text = tf("{radius} radius, {rate} HP/s"),
		},
		a2 = {
			name = "Shoulder Battery", kind = "active_missiles", cmd = 36101, action = "hero_battery",
			desc = "A volley of homing rockets at the most valuable enemies within 1400",
			radius = 1400, count = lin(6, 12, 1), dmg = lin(2000, 3600, 50), aoe = 160, cooldown = lin(30, 22, 1),
			text = tf("{count} rockets x {dmg} dmg ({aoe} radius), cd {cooldown} s"),
		},
		a3 = {
			name = "Reinforced Frame", kind = "stats", passive = true,
			desc = "Heavier armour plates (placeholder)",
			armor = lin(0.02, 0.15, 0.01),
			text = tf("-{armor%} damage taken"),
		},
		ult = {
			name = "Doomsday Barrage", kind = "active_barrage", cmd = 36106, action = "hero_doomsday", target = "map",
			desc = "Launches tactical nukes from the shoulder silos onto an area within 2800",
			projectile = "nuke", range = 2800, radius = 550, count = lin(3, 8, 1), dmg = lin(6000, 9000, 100), aoe = 380,
			duration = 3, cooldown = lin(120, 100, 1),
			text = tf("{count} nukes x {dmg} dmg ({aoe} radius), cd {cooldown} s"),
		},
	},

	armt4olympus = {
		title = "Olympus, the Thunderer", role = "Strategic artillery", aiRole = "back", aiPick = 2, xpRate = 0.25,
		fx = 2.5,
		weapons = { { keys = { "shocker_low", "shocker_high" }, name = "Plasma Artillery" } },
		a1 = {
			name = "Spotter Uplink", kind = "stats", passive = true,
			desc = "Sight and radar of a spotter satellite",
			sight = lin(400, 1200, 10), radar = lin(1200, 3600, 50),
			text = tf("+{sight} sight, +{radar} radar"),
		},
		a2 = {
			name = "Blast Shield", kind = "active_shield", cmd = 36102, action = "hero_blastshield", fx = "hero-shield",
			desc = "A shield plate absorbs the damage Olympus takes",
			duration = lin(8, 12, 0.5), absorb = lin(15000, 50000, 500), cooldown = lin(40, 30, 1),
			text = tf("absorbs {absorb} damage for {duration} s, cd {cooldown} s"),
		},
		a3 = {
			name = "Fire Control", kind = "slayer", passive = true,
			desc = "More damage against targets of 3000+ metal (placeholder)",
			minCost = 3000, mult = lin(0.05, 0.3, 0.01),
			text = tf("+{mult%} damage vs 3000+ metal"),
		},
		ult = {
			name = "Orbital Strike", kind = "active_barrage", cmd = 36107, action = "hero_orbital", target = "map",
			desc = "Calls heavy plasma shells from orbit onto an area within 6000; high ranks end in a nuclear strike",
			projectile = "shell", range = 6000, radius = 450, count = lin(8, 18, 1), dmg = lin(5000, 8000, 100), aoe = 260,
			stun = lin(1, 2, 0.1), duration = 4, nova = { 0, 0, 0, 0, 0, 0, 10000, 12000, 13500, 15000 }, novaRadius = 600,
			targetFx = "hero-target-orbital", cooldown = lin(120, 90, 1),
			text = tf("{count} shells x {dmg} dmg, {stun.1} s stun, nuke {nova}, cd {cooldown} s"),
		},
	},

	armt4aegis = {
		title = "Aegis, the Warden", role = "Shield bearer", aiRole = "center", aiPick = 1.5,
		fx = 2.5,
		weapons = { { keys = { "mech_rapidlaser" }, name = "Rapid Lasers" } },
		a1 = {
			name = "Deflector Matrix", kind = "shield_cap", passive = true,
			desc = "Capacity and recharge of the plasma deflector over the army (unlearned: 30%)",
			cap = lin(0.5, 1.0, 0.05), base = 0.3, regen = lin(1.5, 2.6, 0.1),
			text = tf("{cap%} shield capacity, x{regen.1} recharge"),
		},
		a2 = {
			name = "Pulse Overload", kind = "active_nova", cmd = 36103, action = "hero_pulse", fx = "hero-nova-emp",
			desc = "Dumps half of the shield charge as an EMP shockwave that stuns everything around",
			radius = lin(500, 700, 10), dmg = lin(1500, 3500, 50), stun = lin(3, 5, 0.5), shieldRatio = lin(1.0, 1.8, 0.1),
			cooldown = lin(35, 25, 1),
			text = tf("{dmg} dmg + {shieldRatio.1}x the charge, {radius} radius, {stun.1} s stun, cd {cooldown} s"),
		},
		a3 = {
			name = "Warden's Presence", kind = "aura_armor", passive = true,
			desc = "Allies around take less damage (placeholder)",
			radius = 700, reduce = lin(0.03, 0.15, 0.01),
			text = tf("{radius} radius, -{reduce%} damage taken"),
		},
		ult = {
			name = "Aegis Dome", kind = "active_dome", cmd = 36104, action = "hero_dome",
			desc = "Allies under the dome cannot be damaged",
			radius = lin(800, 1000, 10), duration = lin(4, 8, 0.5), cooldown = lin(120, 100, 1),
			text = tf("{radius} radius, {duration.1} s invulnerable, cd {cooldown} s"),
		},
	},

	-- Thor (SPEC 1.8; today's armt4zeus with the armthor model): the worked example of the module API,
	-- luarules/heroes/armt4zeus.lua
	armt4zeus = {
		title = "Thor, the Storm Tank", role = "Electric tank", aiRole = "front", aiPick = 2,
		fx = 2.2,
		weapons = { { keys = { "thunder" }, name = "Thunder Coil" }, { keys = { "emp" }, name = "EMP Beams" } },
		a1 = {
			name = "Chain Lightning", kind = "custom", passive = true, icon = "ab_armt4zeus_a1",
			desc = "Lightning hits jump on to the enemies next to the target; every jump hits 5% harder than the one before",
			jumps = lin(1, 10, 1), jumpRange = lin(300, 750, 50), share = lin(0.25, 0.15, 0.01), stepBonus = 0.05,
			text = tf("jumps to {jumps} enemies within {jumpRange}: the first takes {share%} of the salvo, each next one 5% more"),
		},
		a2 = {
			name = "EMP Missile", kind = "custom", cmd = 36108, action = "hero_empmissile", target = "map", icon = "ab_armt4zeus_a2",
			desc = "A heavy EMP missile: damages and paralyses everything in the blast, heroes too (half as long)",
			range = lin(1200, 1800, 50), dmg = lin(2000, 9000, 100), aoe = lin(250, 450, 10), stun = lin(2, 6, 0.5),
			cooldown = lin(30, 18, 1),
			text = tf("{dmg} dmg, {stun.1} s paralysis in {aoe}, range {range}, cd {cooldown} s"),
		},
		a3 = {
			name = "Electro-Devour", kind = "custom", cmd = 36109, action = "hero_devour", target = "ally", icon = "ab_armt4zeus_a3",
			desc = "Consumes one of its own non-hero units with an electric strike and heals a share of the unit's health",
			range = 700, heal = lin(0.5, 2.0, 0.05), cooldown = lin(45, 25, 1),
			text = tf("heals {heal%} of the eaten unit's health, range {range}, cd {cooldown} s"),
		},
		ult = {
			name = "Rage Mode", kind = "custom", cmd = 36105, action = "hero_rage", icon = "ab_armt4zeus_ult",
			desc = "Thor grows, wrapped in red lightning: faster, harder hitting, and an electric orb above it strikes at twice the range",
			duration = lin(10, 25, 1), scale = lin(1.25, 1.5, 0.01), speed = lin(0.15, 0.4, 0.01), turn = lin(0.3, 0.8, 0.05),
			damage = lin(0.1, 0.3, 0.01), orbRange = 2, cooldown = lin(120, 80, 5),
			text = tf("{duration} s: +{speed%} speed, +{damage%} damage, orb at 2x range, cd {cooldown} s"),
		},
		weaponDefs = function(T4)
			local w = T4.missileWeapon({
				name = "Thor EMP missile", damage = 0, aoe = 16, model = "corshiprocket.s3o", velocity = 750,
				ceg = "custom:genericshellexplosion-huge-lightning", cegtag = "cruisemissiletrail-emp",
				soundhit = "emgpuls1", soundstart = "mismed1emp1", range = 4000, turnrate = 30000,
			})
			w.smoketrail = false
			w.customparams = { t4_ability = 1 }
			return { hero_empmissile = w }
		end,
		weaponCopies = {
			rage = { keys = { "thunder", "emp" }, set = { rgbcolor = "1 0.18 0.1", thickness = 3 } },
		},
	},
}

return heroes, { "armt4atlas", "armt4olympus", "armt4aegis", "armt4zeus" }
