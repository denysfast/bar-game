-- Custom heroes (denysfast/bar-game), v19: the ten Armada heroes (altar armt4gant; v23: + Ambassador, eleven). Design: doc/v19-heroes/roster_arm.md.
-- Included by luarules/configs/t4_heroes.lua with the shared table H as `...`; returns `defs, order`.
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
--   cmd = <id: Armada 36101-36199>, action = "hero_<name>", target = "unit" | "map" | "ally" | "unit_or_map" | nil (self),
--   range, cooldown, toggle; kind = "custom" (the module luarules/heroes/<hero>.lua does it).
-- Every Armada ability is kind "custom". Damage / heal / absorb values are level-1 numbers: the modules multiply them
-- by api.power(h) (ability power, grows with the level). Command ids: hero i (0..10 in `order`) uses 36101 + 4 i + slot
-- (slot 0..3 = a1 a2 a3 ult), only actives have one.
local H = ...
local lin, tf = H.lin, H.textf

local heroes = {}

---------------------------------------------------------------------------------------------------- 1. Thor
heroes.armt4zeus = {
	title = "Thor, the Stormbreaker", role = "Electric tank (anti-swarm)", aiRole = "front", aiPick = 2.5,
	fx = 2.2,
	weapons = { { keys = { "thunder" }, name = "Thunder Coil" }, { keys = { "emp" }, name = "EMP Beams" } },
	a1 = {
		name = "Chain Lightning", kind = "custom", passive = true, icon = "ab_armt4zeus_a1",
		desc = "Thunder Coil hits jump on to the nearest enemies; every jump hits 5% harder than the one before; only enemies within 1.25x Thor's reach",
		jumps = lin(1, 8, 1), jumpRange = lin(300, 500, 10), share = lin(0.2, 0.1, 0.01), stepBonus = 0.05,
		text = tf("jumps to {jumps} enemies within {jumpRange}: the first takes {share%} of the salvo, each next one +5%"),
	},
	a2 = {
		name = "EMP Missile", kind = "custom", cmd = 36102, action = "hero_thor_empmissile", target = "map", icon = "ab_armt4zeus_a2",
		desc = "A heavy EMP missile: damages and paralyses everything in the blast, heroes too (half as long)",
		range = lin(1000, 1250, 10), dmg = lin(1200, 4000, 100), aoe = lin(300, 520, 10), stun = lin(2, 5, 0.5),
		cooldown = lin(28, 16, 1),
		text = tf("{dmg} dmg, {stun.1} s paralysis in {aoe} radius, range {range}, cd {cooldown} s"),
	},
	a3 = {
		name = "Electro-Devour", kind = "custom", cmd = 36103, action = "hero_thor_devour", target = "ally", icon = "ab_armt4zeus_a3",
		desc = "Pulls in one of its own non-hero units with lightning and eats it: heals a share of the unit's health; "
			.. "healing past full charges the Thunder Coil (Static Overcharge)",
		range = lin(450, 800, 10), heal = lin(0.5, 2.0, 0.05), overchargeMax = 0.3, overchargeTime = 12, cooldown = lin(30, 14, 1),
		text = tf("heals {heal%} of the eaten unit's health (overflow: up to +30% damage for 12 s), range {range}, cd {cooldown} s"),
	},
	ult = {
		name = "Rage Mode", kind = "custom", cmd = 36104, action = "hero_thor_rage", icon = "ab_armt4zeus_ult",
		desc = "Thor grows, wrapped in red lightning: faster, quicker turret, tougher; a storm orb above it adds one extra "
			.. "lightning bolt per Coil salvo at Thor's own target, within the Coil's range",
		duration = lin(6, 12, 1), scale = 1.35, speed = lin(0.25, 0.6, 0.01), turn = lin(0.5, 1.5, 0.05),
		armor = lin(0.1, 0.25, 0.01), orbRange = 1, orbShare = lin(0.25, 0.5, 0.01), cooldown = lin(140, 80, 5),
		text = tf("{duration} s: +{speed%} speed, +{turn%} turning, -{armor%} damage taken, orb bolt {orbShare%} of a salvo, cd {cooldown} s"),
	},
	weaponDefs = function(T4)
		local w = T4.missileWeapon({
			name = "Thor EMP missile", damage = 1, aoe = 16, model = "corshiprocket.s3o", velocity = 750,
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
}

---------------------------------------------------------------------------------------------------- 2. Atlas
heroes.armt4atlas = {
	title = "Atlas, the Bulwark", role = "Assault anchor (anti-big)", aiRole = "front", aiPick = 3,
	fx = 2.5,
	weapons = { { keys = { "armbantha_fire" }, name = "Pulse Cannon" }, { keys = { "tehlazerofdewm" }, name = "Doom Laser" },
		{ keys = { "bantha_rocket" }, name = "Starburst Rockets" } },
	a1 = {
		name = "Doom Lens", kind = "custom", passive = true, icon = "ab_armt4atlas_a1",
		desc = "Doom Laser hits Sunder the target (it takes more damage from every source) and burn big targets harder",
		sunder = lin(0.06, 0.18, 0.01), sunderTime = 6, bigCost = 5000, bigBonus = lin(0.2, 0.8, 0.05),
		text = tf("Sunder: +{sunder%} damage taken for 6 s; Doom Laser +{bigBonus%} vs 5000+ metal"),
	},
	a2 = {
		name = "Bulwark Protocol", kind = "custom", cmd = 36106, action = "hero_atlas_bulwark", icon = "ab_armt4atlas_a2",
		desc = "Plants its feet: immobile, much tougher, taunts every enemy around and lashes attackers with lightning",
		duration = lin(5, 10, 0.5), armor = lin(0.3, 0.55, 0.01), radius = lin(500, 900, 10), reflect = lin(0.1, 0.3, 0.01),
		cooldown = lin(40, 22, 1),
		text = tf("{duration.1} s: -{armor%} damage taken, taunts within {radius}, reflects {reflect%}, cd {cooldown} s"),
	},
	a3 = {
		-- v20: replaces Seismic Charge (the human did not like a charge on the Titan)
		name = "Titan Salvo", kind = "custom", cmd = 36107, action = "hero_atlas_salvo", target = "map", icon = "ab_armt4atlas_a3",
		desc = "Empties the shoulder racks: guided rockets rain on the area, every hit Sunders its target (Doom Lens value once learned), the last three rockets pin the ground (slow)",
		range = lin(1400, 1900, 10), count = lin(8, 16, 1), dmg = lin(500, 1200, 50), aoe = 180, radius = lin(250, 380, 10),
		sunder = 0.06, sunderTime = 6, slow = 0.35, cooldown = lin(24, 12, 1),
		text = tf("{count} rockets x {dmg} dmg within {radius}, each hit Sunders for 6 s, range {range}, cd {cooldown} s"),
	},
	ult = {
		name = "Doomsday Lance", kind = "custom", cmd = 36108, action = "hero_atlas_lance", target = "map", icon = "ab_armt4atlas_ult",
		desc = "The Doom Laser becomes a continuous lance 1.25x its range long and sweeps a 60 degree arc",
		duration = lin(4, 8, 0.5), dps = lin(4000, 10000, 250), width = 90, arc = 60, range = 1800, lenMult = 1.25, cooldown = lin(150, 90, 5),
		text = tf("{duration.1} s sweep, {dps} damage per second along the lance, cd {cooldown} s"),
	},
}

---------------------------------------------------------------------------------------------------- 3. Peewee Prime
heroes.armt4peewee = {
	title = "Peewee Prime, the Vanguard", role = "Brawler / army leader", aiRole = "front", aiPick = 2.5,
	fx = 2.2,
	weapons = { { keys = { "emg" }, name = "Rapid Plasma Guns" } },
	a1 = {
		name = "Pack Leader", kind = "custom", passive = true, icon = "ab_armt4peewee_a1",
		desc = "Stronger with an army around: +1% damage and +0.5% toughness per allied unit within 700; allied bots there run and hit harder",
		cap = lin(10, 30, 1), radius = 700, botBonus = lin(0.05, 0.2, 0.01),
		text = tf("counts up to {cap} allies; allied T1/T2 bots +{botBonus%} speed and damage"),
	},
	a2 = {
		name = "Jump Jets", kind = "custom", cmd = 36110, action = "hero_peewee_jump", target = "map", icon = "ab_armt4peewee_a2",
		desc = "Leaps onto a point: the landing blasts and throws units back, then the guns run hot",
		range = lin(500, 900, 10), dmg = lin(2000, 7000, 100), radius = 300, hot = lin(0.2, 0.5, 0.01), hotTime = 4,
		cooldown = lin(20, 9, 1),
		text = tf("{dmg} landing dmg in 300, then +{hot%} gun damage for 4 s, range {range}, cd {cooldown} s"),
	},
	a3 = {
		name = "Bullet Hell", kind = "custom", cmd = 36111, action = "hero_peewee_bullethell", icon = "ab_armt4peewee_a3",
		desc = "Spins and sprays plasma in every direction at half speed: every enemy in gun range is hit (15 at most)",
		duration = lin(3, 6, 0.5), dps = lin(300, 600, 25), targets = 15, cooldown = lin(30, 16, 1),
		text = tf("{duration.1} s, {dps} damage per second to every enemy in range, cd {cooldown} s"),
	},
	ult = {
		name = "Overrun", kind = "custom", cmd = 36112, action = "hero_peewee_overrun", icon = "ab_armt4peewee_ult",
		desc = "Peewee and the army around charge: faster, harder hitting, Peewee unstoppable; kills extend it",
		duration = lin(8, 16, 1), radius = 900, speed = lin(0.25, 0.6, 0.01), damage = lin(0.15, 0.4, 0.01),
		cooldown = lin(150, 90, 5),
		text = tf("{duration} s: +{speed%} speed, +{damage%} damage to the army within 900, cd {cooldown} s"),
	},
	weaponCopies = {
		hot = { keys = { "emg" }, set = { rgbcolor = "0.75 0.9 1", size = 9, intensity = 2 } },
	},
}

---------------------------------------------------------------------------------------------------- 4. Razor
heroes.armt4aegis = {
	title = "Razor, the Phantom", role = "Laser assassin", aiRole = "center", aiPick = 2,
	fx = 2.5,
	weapons = { { keys = { "mech_rapidlaser" }, name = "Rapid Lasers" } },
	a1 = {
		name = "Phantom Cloak", kind = "custom", cmd = 36113, action = "hero_razor_cloak", icon = "ab_armt4aegis_a1",
		desc = "Cloaks and speeds up; the first salvo out of the cloak is an Ambush. Enemies within 100 reveal it",
		duration = lin(6, 15, 0.5), speed = lin(0.2, 0.6, 0.01), ambush = lin(0.4, 1.0, 0.05), cooldown = lin(30, 14, 1),
		text = tf("{duration.1} s cloak, +{speed%} speed, Ambush +{ambush%} damage, cd {cooldown} s (after the cloak)"),
	},
	a2 = {
		name = "Deflector Shell", kind = "custom", passive = true, icon = "ab_armt4aegis_a2",
		desc = "A personal deflector soaks all damage before the hull and recharges out of combat",
		capacity = lin(15000, 90000, 500), regen = lin(300, 1800, 10), delay = 3, brokenDelay = 6,
		text = tf("absorbs {capacity}, recharges {regen}/s after 3 s without hits"),
	},
	a3 = {
		name = "Overcharge", kind = "custom", cmd = 36115, action = "hero_razor_overcharge", toggle = true, icon = "ab_armt4aegis_a3",
		desc = "Toggle: the lasers fire much faster, burning the hull a little; switches itself off at 25% health",
		rate = lin(0.5, 1.0, 0.01), hpCost = lin(0.004, 0.002, 0.0001), minHp = 0.25, cooldown = 3,
		text = function(r, _, b)
			return string.format("+%d%% fire rate, burns %.1f%% of max health per second", H.val(b.rate, r) * 100 + 0.5, H.val(b.hpCost, r) * 100)
		end,
	},
	ult = {
		name = "Razor Swarm", kind = "custom", passive = true, icon = "ab_armt4aegis_ult",
		desc = "A crown of red-laser drones circles Razor and shoots what it shoots; destroyed drones are rebuilt",
		count = { 4, 4, 5, 5, 6, 6, 7, 7, 8, 8 }, dps = lin(700, 1000, 10), rebuild = 8,
		text = tf("{count} drones x {dps} DPS, rebuilt every 8 s"),
	},
	weaponCopies = {
		oc = { keys = { "mech_rapidlaser" }, set = { rgbcolor = "1 0.35 0.08", thickness = 4.5, corethickness = 0.5 } },
	},
}

---------------------------------------------------------------------------------------------------- 5. Prowler
heroes.armt4prowler = {
	title = "Prowler, the Riptide", role = "Amphibious hunter (anti-big)", aiRole = "center", aiPick = 2,
	fx = 2.2,
	weapons = { { keys = { "armmech_cannon" }, name = "Twin Gauss" }, { keys = { "armamph_missile" }, name = "Tandem Missiles" } },
	a1 = {
		name = "Tandem Strike", kind = "custom", passive = true, icon = "ab_armt4prowler_a1",
		desc = "Gauss hits crack the armour (Breach); a missile on a breached target detonates every stack",
		maxStacks = lin(3, 8, 1), perStack = lin(1200, 3000, 50), stackTime = 6,
		text = tf("up to {maxStacks} Breach stacks, {perStack} bonus damage per stack on detonation"),
	},
	a2 = {
		name = "Harpoon", kind = "custom", cmd = 36118, action = "hero_prowler_harpoon", target = "unit", icon = "ab_armt4prowler_a2",
		desc = "A cable harpoon: damage, full Breach, drags the prey in (not heroes or heavier units) and roots it",
		range = lin(700, 1000, 10), dmg = lin(3000, 10000, 100), root = lin(1, 2.5, 0.1), heroRoot = 1.5, pullTime = 0.6,
		cooldown = lin(22, 10, 1),
		text = tf("{dmg} dmg, pull, {root.1} s root, range {range}, cd {cooldown} s"),
	},
	a3 = {
		name = "Riptide Fog", kind = "custom", cmd = 36119, action = "hero_prowler_fog", target = "map", icon = "ab_armt4prowler_a3",
		desc = "A sea-fog cloud: allies inside are cloaked, enemies slowed, Prowler moves faster in it",
		range = 800, radius = lin(300, 550, 10), duration = lin(5, 10, 0.5), slow = 0.3, speed = 0.3, cooldown = lin(35, 18, 1),
		text = tf("{radius} radius for {duration.1} s, cd {cooldown} s"),
	},
	ult = {
		name = "Apex Predator", kind = "custom", cmd = 36120, action = "hero_prowler_apex", target = "unit", icon = "ab_armt4prowler_ult",
		desc = "Marks one prey: revealed, Prowler runs it down and hits it harder; missiles detonate Breach without using it. "
			.. "A kill heals 25% and refunds half the cooldown",
		range = 1400, duration = lin(8, 14, 1), speed = lin(0.3, 0.7, 0.01), damage = lin(0.2, 0.35, 0.01),
		cooldown = lin(120, 70, 5),
		text = tf("{duration} s: +{speed%} speed, +{damage%} damage to the prey, cd {cooldown} s"),
	},
}

---------------------------------------------------------------------------------------------------- 6. Ratte
heroes.armt4ratte = {
	title = "Ratte, the Landship", role = "Siege landship", aiRole = "center", aiPick = 2,
	fx = 2.0,
	weapons = { { keys = { "arm_bosscannon" }, name = "Main Battery" } },
	a1 = {
		name = "Overpressure", kind = "custom", passive = true, icon = "ab_armt4ratte_a1",
		desc = "Every 4th salvo is overcharged: more damage, a wider blast that throws and stuns. Every salvo cracks buildings",
		mult = lin(1.5, 3.0, 0.05), building = lin(0.3, 1.2, 0.05), every = 4,
		text = tf("every 4th salvo x{mult.1} damage, 1.5x blast, 1 s stun; +{building%} vs buildings"),
	},
	a2 = {
		name = "Creeping Barrage", kind = "custom", cmd = 36122, action = "hero_ratte_barrage", target = "map", icon = "ab_armt4ratte_a2",
		desc = "A walking wall of shells from 400 in front of the point to 400 behind it",
		range = 1600, count = lin(6, 12, 1), dmg = lin(800, 1100, 50), radius = 220, duration = 4, cooldown = lin(35, 18, 1),
		text = tf("{count} shells x {dmg} dmg ({radius} radius) over 4 s, cd {cooldown} s"),
	},
	a3 = {
		name = "Landship Plating", kind = "custom", passive = true, icon = "ab_armt4ratte_a3",
		desc = "The bow armour turns frontal hits; crusher treads grind and slow what is in front of the hull",
		front = lin(0.1, 0.35, 0.01), crush = lin(800, 3000, 50),
		text = tf("-{front%} damage from the front, treads {crush} dmg/s + 50% slow"),
	},
	ult = {
		name = "Main Gun", kind = "custom", cmd = 36124, action = "hero_ratte_maingun", target = "map", icon = "ab_armt4ratte_ult",
		desc = "One shell from the landship's main gun: a huge blast (buildings x1.5) and a firestorm",
		range = lin(1500, 1600, 50), dmg = lin(5000, 10000, 500), radius = 500, fire = lin(200, 500, 50), fireRadius = 450,
		fireTime = 8, cooldown = lin(150, 90, 5),
		text = tf("{dmg} dmg at the centre ({radius}), firestorm {fire}/s for 8 s, range {range}, cd {cooldown} s"),
	},
	weaponCopies = {
		op = { keys = { "arm_bosscannon" }, set = { rgbcolor = "1 0.95 0.8", size = 9, intensity = 2 } },
	},
}

---------------------------------------------------------------------------------------------------- 7. Recluse
heroes.armt4recluse = {
	title = "Recluse Matriarch", role = "Zone control (all-terrain)", aiRole = "center", aiPick = 2, xpRate = 0.7,
	fx = 2.2,
	weapons = { { keys = { "adv_rocket" }, name = "Rocket Salvo" } },
	a1 = {
		name = "Web Rockets", kind = "custom", passive = true, icon = "ab_armt4recluse_a1",
		desc = "Rocket hits web the target: slowed (stacks up to 60%) and it takes more damage from Recluse",
		slow = lin(0.08, 0.2, 0.01), vuln = lin(0.05, 0.15, 0.01), time = 3, maxSlow = 0.6,
		text = tf("-{slow%} speed per hit (max 60%), +{vuln%} damage from Recluse, 3 s"),
	},
	a2 = {
		name = "Web Field", kind = "custom", cmd = 36126, action = "hero_recluse_webfield", target = "map", icon = "ab_armt4recluse_a2",
		desc = "A web canister bursts into a field: enemies inside are slowed 50% and revealed; rockets blast wider there",
		range = 1400, radius = lin(300, 550, 10), duration = lin(3, 5, 0.5), slow = 0.5, cooldown = lin(26, 14, 1),
		text = tf("{radius} radius for {duration.1} s, cd {cooldown} s"),
	},
	a3 = {
		name = "Cocoon", kind = "custom", cmd = 36127, action = "hero_recluse_cocoon", target = "unit", icon = "ab_armt4recluse_a3",
		desc = "Wraps an enemy (not a hero) in silk: stunned and taking +50% damage; if it dies, spiderlings hatch. Heroes are only rooted",
		range = 900, maxCost = lin(3000, 15000, 100), stun = lin(2, 5, 0.5), hatch = lin(1, 3, 1), heroRoot = lin(1, 2.5, 0.1),
		cooldown = lin(20, 10, 1),
		text = tf("up to {maxCost} metal, {stun.1} s stun, {hatch} spiderlings, cd {cooldown} s"),
	},
	ult = {
		name = "Rocket Monsoon", kind = "custom", cmd = 36128, action = "hero_recluse_monsoon", target = "map", icon = "ab_armt4recluse_ult",
		desc = "Plants itself and rains rockets on an area; every rocket webs",
		range = lin(1800, 2200, 50), duration = lin(6, 10, 0.5), count = lin(36, 90, 1), dmg = lin(900, 1400, 50), radius = 600,
		aoe = 160, cooldown = lin(120, 75, 5),
		text = tf("{count} rockets x {dmg} dmg over {duration.1} s in 600, range {range}, cd {cooldown} s"),
	},
}

---------------------------------------------------------------------------------------------------- 8. Olympus
heroes.armt4olympus = {
	title = "Olympus, the Thunderer", role = "Strategic artillery", aiRole = "back", aiPick = 2, xpRate = 0.25,
	fx = 2.5,
	weapons = { { keys = { "shocker_low", "shocker_high" }, name = "Plasma Artillery" } },
	a1 = {
		name = "Cluster Shells", kind = "custom", passive = true, icon = "ab_armt4olympus_a1",
		desc = "Every shell splits on impact into bomblets that scatter around",
		bomblets = lin(2, 7, 1), share = lin(0.12, 0.18, 0.01), scatter = 350,
		text = tf("{bomblets} bomblets x {share%} of the shell's damage"),
	},
	a2 = {
		name = "Spotter Flare", kind = "custom", cmd = 36130, action = "hero_olympus_flare", target = "map", icon = "ab_armt4olympus_a2",
		desc = "A flare lights up an area deep in the fog for the whole team; Olympus' shells landing in it hit harder",
		range = lin(3300, 4000, 50), radius = lin(600, 1200, 10), duration = lin(8, 20, 1), bonus = lin(0.1, 0.15, 0.01),
		cooldown = lin(40, 20, 1),
		text = tf("reveals {radius} for {duration} s, +{bonus%} shell damage there, range {range}, cd {cooldown} s"),
	},
	a3 = {
		name = "Siege Anchor", kind = "custom", cmd = 36131, action = "hero_olympus_anchor", toggle = true, icon = "ab_armt4olympus_a3",
		desc = "Toggle: digs in (1.5 s): immobile, longer range, more damage, tougher",
		range = lin(0.15, 0.4, 0.01), damage = lin(0.1, 0.25, 0.01), armor = 0.2, deploy = 1.5, cooldown = 3,
		text = tf("+{range%} range, +{damage%} damage, -20% damage taken while deployed"),
	},
	ult = {
		name = "Ion Lance", kind = "custom", cmd = 36132, action = "hero_olympus_ionlance", target = "map", icon = "ab_armt4olympus_ult",
		desc = "Calls an orbital ion lance: 3 s warning, then a blast that stuns, and three aftershocks",
		range = lin(3300, 4000, 100), radius = lin(350, 600, 10), dmg = lin(4000, 7000, 500), stun = 2, cooldown = lin(150, 90, 5),
		text = tf("{dmg} dmg at the centre of {radius}, 2 s stun, +3 aftershocks, range {range}, cd {cooldown} s"),
	},
}

---------------------------------------------------------------------------------------------------- 9. Starlight
heroes.armt4starlight = {
	title = "Starlight, the Lance", role = "Tachyon sniper (anti-big)", aiRole = "back", aiPick = 2, xpRate = 0.5,
	fx = 2.2,
	weapons = { { keys = { "atam" }, name = "Tachyon Lance" } },
	a1 = {
		name = "Focusing Array", kind = "custom", passive = true, icon = "ab_armt4starlight_a1",
		desc = "Shots in a row on one target focus the beam; the beam goes through and burns the line behind",
		focus = lin(0.08, 0.15, 0.01), stacks = lin(3, 6, 1), pierce = lin(300, 900, 10), pierceShare = 0.25,
		text = tf("+{focus%} damage per shot in a row (max {stacks}), pierces {pierce} for 25%"),
	},
	a2 = {
		name = "Prism Relay", kind = "custom", cmd = 36134, action = "hero_starlight_prism", target = "ally", icon = "ab_armt4starlight_a2",
		desc = "Links to an ally: every shot also refracts from it to the most valuable enemy within 500 of it",
		range = 1500, duration = lin(8, 16, 1), share = lin(0.4, 0.75, 0.05), reach = 500, cooldown = lin(30, 16, 1),
		text = tf("{duration} s, refracted shots {share%} damage, cd {cooldown} s"),
	},
	a3 = {
		name = "Phase Shift", kind = "custom", cmd = 36135, action = "hero_starlight_phase", target = "map", icon = "ab_armt4starlight_a3",
		desc = "Teleports; a light mine left behind detonates a second later",
		range = lin(500, 900, 10), dmg = lin(5000, 15000, 100), radius = 250, cooldown = lin(22, 10, 1),
		text = tf("range {range}, mine {dmg} dmg in 250, cd {cooldown} s"),
	},
	ult = {
		name = "Solar Lance", kind = "custom", cmd = 36136, action = "hero_starlight_lance", target = "unit_or_map", icon = "ab_armt4starlight_ult",
		desc = "Charges 2 s, then holds a solar lance on the target; everything else on the line burns too",
		range = lin(2100, 2500, 50), duration = lin(3, 5, 0.5), dps = lin(10000, 16000, 500), lineShare = 0.4, width = 100,
		charge = 2, cooldown = lin(140, 80, 5),
		text = tf("{duration.1} s x {dps} dmg/s (line 40%), range {range}, cd {cooldown} s"),
	},
}

---------------------------------------------------------------------------------------------------- 10. Hive Mother
heroes.armt4hive = {
	title = "Hive Mother", role = "Drone carrier", aiRole = "back", aiPick = 2,
	fx = 2.0,
	weapons = { { keys = { "hero_pdlaser" }, name = "Point-defence Laser" } },
	a1 = {
		name = "Drone Bay", kind = "custom", passive = true, icon = "ab_armt4hive_a1",
		desc = "Keeps a swarm of laser drones in the air; lost drones are rebuilt",
		count = lin(6, 16, 1), rebuild = lin(6, 3, 0.5), dps = lin(4000, 11000, 100), leash = 1300,
		text = tf("{count} drones, {dps} DPS together, one rebuilt every {rebuild.1} s"),
	},
	a2 = {
		name = "Swarm Directive", kind = "custom", cmd = 36138, action = "hero_hive_directive", target = "unit", icon = "ab_armt4hive_a2",
		desc = "Every drone focuses one enemy, harder; their hits slow it and it is revealed",
		range = 1300, duration = 8, damage = lin(0.3, 0.6, 0.01), cooldown = lin(20, 10, 1),
		text = tf("8 s, +{damage%} drone damage, up to 45% slow, cd {cooldown} s"),
	},
	a3 = {
		name = "Kamikaze Run", kind = "custom", cmd = 36139, action = "hero_hive_kamikaze", target = "map", icon = "ab_armt4hive_a3",
		desc = "Drones dive onto a point and explode; two are rebuilt at once",
		range = 1300, count = lin(2, 6, 1), dmg = lin(800, 1500, 50), radius = 200, cooldown = lin(24, 12, 1),
		text = tf("{count} drones x {dmg} dmg ({radius} radius), cd {cooldown} s"),
	},
	ult = {
		name = "Mothership Protocol", kind = "custom", cmd = 36140, action = "hero_hive_mothership", icon = "ab_armt4hive_ult",
		desc = "Anchors and launches Guardian gunships; drones rebuild 3x faster, the swarm hits harder, a repair field heals",
		duration = lin(8, 12, 1), guardians = lin(2, 4, 1), damage = lin(0.1, 0.25, 0.01), heal = lin(500, 2000, 50),
		radius = 800, cooldown = lin(140, 80, 5),
		text = tf("{duration} s: {guardians} Guardians, +{damage%} swarm damage, {heal} HP/s repair, cd {cooldown} s"),
	},
}

---------------------------------------------------------------------------------------------------- 11. Ambassador
-- v23: rocket artillery from the T2 Ambassador (armmerl). Artillery rules: dmgScale 1/3 (gamedata/custom_t4.lua), every
-- targeted ability within its weapon range (2600), no ability bursts more than ~3 s of its own DPS.
heroes.armt4ambassador = {
	title = "Ambassador, the Rocket Marshal", role = "Rocket artillery (marking, mobile)", aiRole = "back", aiPick = 2,
	xpRate = 0.25,
	fx = 2.2,
	weapons = { { keys = { "armtruck_rocket" }, name = "Starburst Rack" } },
}

-- v23: the rocket-artillery kit (warhead toggles + passive Rocket Mastery)
for k, v in pairs(H.rocketModes({ 36141, 36142, 36143 }, "hero_ambassador", { "ab_armt4recluse_ult", "ab_armt4ratte_a2", "ab_armt4olympus_ult", "ab_armt4olympus_a2" })) do
	heroes.armt4ambassador[k] = v
end

return heroes, { "armt4zeus", "armt4atlas", "armt4peewee", "armt4aegis", "armt4prowler", "armt4ratte", "armt4recluse",
	"armt4olympus", "armt4starlight", "armt4hive", "armt4ambassador" }
