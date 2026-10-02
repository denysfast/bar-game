-- Custom heroes (denysfast/bar-game), v19: the Cortex heroes (altar cort4gant). Included by
-- luarules/configs/t4_heroes.lua with the shared table H as `...`; returns `defs, order`. Format: header of
-- luarules/configs/heroes/arm.lua. v19 port of the v18 abilities (three ranks spread over ten); a3 is a placeholder.
local H = ...
local lin, tf = H.lin, H.textf

local heroes = {
	cort4colossus = {
		title = "Colossus, the Warlord", role = "Flagship", aiRole = "front", aiPick = 3,
		fx = 2.2,
		weapons = { { keys = { "corkorg_fire" }, name = "Plasma Scatter Gun" }, { keys = { "corkorg_laser" }, name = "Heat Eye" }, { keys = { "corkorg_rocket" }, name = "Warlord Rockets" } },
		a1 = {
			name = "War Stomp", kind = "active_nova", cmd = 36211, action = "hero_stomp", fx = "hero-nova-kinetic",
			desc = "Slams the ground: damages and stuns everything around",
			radius = lin(450, 650, 10), dmg = lin(3000, 8500, 100), stun = lin(2, 4, 0.5), cooldown = lin(30, 24, 1),
			text = tf("{radius} radius, {dmg} dmg, {stun.1} s stun, cd {cooldown} s"),
		},
		a2 = {
			name = "Command Aura", kind = "aura_damage", passive = true,
			desc = "Allied units around deal more damage",
			radius = 900, mult = lin(0.08, 0.25, 0.01),
			text = tf("{radius} radius, +{mult%} damage"),
		},
		a3 = {
			name = "Warlord's Hide", kind = "stats", passive = true,
			desc = "More health (placeholder)",
			hp = lin(10000, 60000, 1000),
			text = tf("+{hp} HP"),
		},
		ult = {
			name = "Undying", kind = "undying", passive = true,
			desc = "A lethal blow instead leaves Colossus standing, healed, and reborn in a nuclear blast",
			cooldown = lin(240, 160, 5), heal = lin(0.4, 0.8, 0.05), nova = lin(8000, 22000, 500), novaRadius = 700,
			text = tf("back at {heal%} HP, {nova} dmg blast, cd {cooldown} s"),
		},
	},

	cort4bastion = {
		title = "Bastion, the Citadel", role = "Walking fortress", aiRole = "front", aiPick = 2,
		fx = 2.2,
		weapons = { { keys = { "juggernaut_fire" }, name = "Gauss Cannon" }, { keys = { "juggernaut_bottom", "juggernaut_top" }, name = "Laser Turrets" } },
		a1 = {
			name = "Reactive Armor", kind = "stats", passive = true,
			desc = "Less damage taken, faster self-repair",
			armor = lin(0.08, 0.24, 0.01), regen = lin(300, 1000, 50),
			text = tf("-{armor%} damage taken, +{regen} HP/s"),
		},
		a2 = {
			name = "Siege Protocol", kind = "active_buff", cmd = 36212, action = "hero_siege", fx = "hero-siege",
			desc = "Anchors in place: hardened armor, fast repair, a stronger shield",
			buff = { immobile = true, armor = lin(0.3, 0.5, 0.01), regen = lin(1000, 3000, 100), shieldRegen = 3 },
			duration = lin(8, 12, 0.5), cooldown = lin(40, 30, 1),
			text = function(r)
				return string.format("%.1f s: -%d%% damage taken, +%d HP/s, cd %d s", H.val(lin(8, 12, 0.5), r),
					H.val(lin(30, 50, 1), r), H.val(lin(1000, 3000, 100), r), H.val(lin(40, 30, 1), r))
			end,
		},
		a3 = {
			name = "Thorn Plating", kind = "thorns", passive = true,
			desc = "Part of the damage taken goes back to the attacker (placeholder)",
			frac = lin(0.05, 0.2, 0.01),
			text = tf("reflects {frac%} of the damage taken"),
		},
		ult = {
			name = "Citadel", kind = "active_guard", cmd = 36215, action = "hero_citadel", fx = "hero-citadel-cast", tickFx = "hero-citadel",
			desc = "Raises an armor dome: every ally inside takes far less damage",
			radius = lin(900, 1100, 10), reduce = lin(0.4, 0.7, 0.01), duration = lin(8, 12, 0.5), cooldown = lin(110, 90, 1),
			text = tf("{radius} radius, -{reduce%} damage taken for {duration.1} s, cd {cooldown} s"),
		},
	},

	cort4armageddon = {
		title = "Armageddon, the Doomsayer", role = "Rocket artillery", aiRole = "back", aiPick = 2, xpRate = 0.15,
		fx = 2.5,
		weapons = { { keys = { "exp_heavyrocket" }, name = "Heavy Rocket Racks" } },
		a1 = {
			name = "Salvage Nanites", kind = "lifesteal", passive = true,
			desc = "Part of the damage the rockets deal repairs Armageddon",
			frac = lin(0.05, 0.12, 0.005),
			text = tf("heals {frac%} of damage dealt"),
		},
		a2 = {
			name = "Hunter Swarm", kind = "active_missiles", cmd = 36216, action = "hero_swarm",
			desc = "Homing rockets at the most valuable enemies within 2400",
			radius = 2400, count = lin(8, 16, 1), dmg = lin(1500, 3000, 50), aoe = 140, cooldown = lin(35, 25, 1),
			text = tf("{count} rockets x {dmg} dmg ({aoe} radius), cd {cooldown} s"),
		},
		a3 = {
			name = "Cluster Warheads", kind = "proc_blast", passive = true,
			desc = "Rockets may burst into bomblets around what they hit (placeholder)",
			chance = lin(0.1, 0.3, 0.01), dmg = lin(800, 2500, 50), radius = lin(160, 240, 10), fx = "hero-blast",
			text = tf("{chance%} per shot: {dmg} dmg in {radius}"),
		},
		ult = {
			name = "Armageddon Protocol", kind = "active_barrage", cmd = 36217, action = "hero_armageddon", target = "map",
			desc = "A rain of rockets on an area within 3200, sealed with a tactical nuke",
			projectile = "missile", range = 3200, radius = 700, count = lin(24, 40, 1), dmg = lin(1800, 3000, 50), aoe = 200,
			duration = 4, nova = lin(10000, 22000, 500), novaRadius = 550, cooldown = lin(120, 100, 1),
			text = tf("{count} rockets x {dmg} dmg + {nova} nuke, cd {cooldown} s"),
		},
	},

	cort4hellwalker = {
		title = "Hellwalker, the Inferno", role = "Flame assault", aiRole = "front", aiPick = 2,
		fx = 2.5,
		weapons = { { keys = { "newdmaw" }, name = "Hellfire Maw" }, { keys = { "karg_shoulder" }, name = "Shoulder Missiles" } },
		a1 = {
			name = "Immolation", kind = "aura_burn", passive = true,
			desc = "Burns every enemy around, every second",
			radius = lin(320, 480, 10), dps = lin(450, 1500, 50),
			text = tf("{radius} radius, {dps} dmg/s"),
		},
		a2 = {
			name = "Hellcharge", kind = "active_dash", cmd = 36213, action = "hero_hellcharge", target = "map", cursor = "Move",
			desc = "Charges through the enemy line, burning everything it passes and leaving fire behind",
			range = lin(700, 1000, 10), dmg = lin(2500, 6000, 100), radius = 220, burn = lin(600, 1500, 50),
			cooldown = lin(24, 18, 1),
			text = tf("{range} range, {dmg} dmg, fire {burn} dmg/s for 4 s, cd {cooldown} s"),
		},
		a3 = {
			name = "Infernal Core", kind = "stats", passive = true,
			desc = "Self-repair (placeholder)",
			regen = lin(200, 1200, 50),
			text = tf("+{regen} HP/s"),
		},
		ult = {
			name = "Rain of Fire", kind = "active_barrage", cmd = 36214, action = "hero_rainfire", target = "map",
			desc = "Meteors fall on an area within 1800; high ranks end in a fireball",
			projectile = "meteor", range = 1800, radius = 600, count = lin(14, 32, 1), dmg = lin(3000, 5000, 100), aoe = 220,
			duration = 6, nova = { 0, 0, 0, 0, 0, 0, 12000, 14000, 16000, 18000 }, novaRadius = 600, novaFx = "hero-finale-fire",
			cooldown = lin(90, 70, 1),
			text = tf("{count} meteors x {dmg} dmg, fireball {nova}, cd {cooldown} s"),
		},
	},
}

return heroes, { "cort4colossus", "cort4bastion", "cort4armageddon", "cort4hellwalker" }
