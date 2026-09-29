-- Custom T2 heroes, Armada (denysfast/bar-game): ten heroes from the Armada T2 bots and vehicles plus their
-- hall. Built like the T4 heroes (gamedata/custom_t4.lua: T4.derive + T4.hero), design data in
-- luarules/configs/t4_hero_defs_t2_arm.lua. A level-1 T2 hero is worth 3-5 of its base unit (2500-4500
-- metal), far below the T4 heroes; it levels, learns and revives the same way.
-- Models: tools/t4/build_models.py (scale here must match the scale there).
local T4 = VFS.Include("gamedata/custom_t4.lua")
local FX = T4.FX

local units = {}

-- Hall of Heroes: the Armada T2 hero hall (Advanced Bot Lab model x1.3), one per team, built by the T2
-- constructors (gamedata/alldefs_post.lua, t2HeroHall). Builds and revives the ten T2 heroes; heroes heal
-- fast next to it (the hero gadget treats every *t2hall as a fountain, like the T4 altars).
units.armt2hall = T4.foundry(T4.base("units/ArmBuildings/LandFactories/armalab.lua", "armalab"), {
	name = "armt2hall",
	value = 2.3, -- 5980 metal
	scale = 1.3,
	workertime = 3,
	buildoptions = {
		"armt2boomer", "armt2deadeye", "armt2outlaw", "armt2hound", "armt2tesla",
		"armt2widow", "armt2starlight", "armt2bulldog", "armt2envoy", "armt2weaver",
	},
})

-- shared T2 hero chassis tuning: nimbler than the T4 giants, the base unit's own death explosion
local function hero(path, key, p)
	local base = T4.base(path, key)
	p.accel = p.accel or 0.85
	p.turn = p.turn or 0.85
	p.sight = p.sight or 1.3
	p.aoe = p.aoe or 1.3
	p.explodeas = p.explodeas or base.explodeas
	p.selfdestructas = p.selfdestructas or base.selfdestructas
	return T4.derive(base, p)
end

local function nova(dmg, aoe, scale)
	return T4.novaWeapon({ damage = dmg, aoe = aoe, ceg = FX.custom("newnuketac", scale), name = "Hero nova" })
end

-- Boomer, the Demolisher (Fatboy x1.5): siege plasma that levels bases. Shockwave Shells, Dig In, and a
-- called Carpet Bombardment.
local boomer = hero("units/ArmBots/T2/armfboy.lua", "armfboy", {
	name = "armt2boomer",
	value = 3.2, -- 4480 metal (Fatboy 1400)
	health = 3.4,
	damage = 2.8,
	range = 1.15,
	scale = 1.5,
	speed = 0.9,
	footprint = 4,
	movementclass = "HBOT4",
})
units.armt2boomer = T4.hero(boomer, 1.6, {
	hero_shell = T4.shellWeapon({
		damage = 700, aoe = 220, ceg = "custom:genericshellexplosion-large", name = "Bombardment plasma shell",
		rgb = "0.6 0.8 1", size = 7, soundhit = "xplomed4",
	}),
})

-- Deadeye, the Silent Hunter (Sharpshooter x1.6): a cloaked long-range assassin. Headshot, Ghost Protocol
-- and the Execution Round that pierces a whole line.
local deadeye = hero("units/ArmBots/T2/armsnipe.lua", "armsnipe", {
	name = "armt2deadeye",
	value = 5, -- 3400 metal (Sharpshooter 680)
	health = 8,
	damage = 2.4,
	range = 1.35,
	aoe = 1.0,
	scale = 1.6,
	speed = 1.0,
	footprint = 3,
	movementclass = "BOT3",
})
units.armt2deadeye = T4.hero(deadeye, 1.4, {
	hero_spear = T4.weaponFrom(deadeye.weapondefs.old_armsnipe_weapon, {
		damage = 3000, range = 2400, name = "Execution Round", noexplode = true, size = 6,
		ceg = "custom:genericshellexplosion-large-lightning",
	}),
})

-- Outlaw, the Gunslinger (Maverick x1.5): a fast skirmisher. Impulse Dash, Scavenger Rounds and a Bullet
-- Storm around itself.
local outlaw = hero("units/ArmBots/T2/armmav.lua", "armmav", {
	name = "armt2outlaw",
	value = 5.5, -- 3575 metal (Maverick 650)
	health = 5,
	damage = 3.2,
	range = 1.25,
	scale = 1.5,
	speed = 1.05,
	footprint = 4,
	movementclass = "HBOT4",
})
units.armt2outlaw = T4.hero(outlaw, 1.5)

-- Hound, the Pack Leader (Fido x1.6): lobs plasma and never walks alone. Pack Tactics, Call the Pack and
-- Release the Bulldogs.
local hound = hero("units/ArmBots/T2/armfido.lua", "armfido", {
	name = "armt2hound",
	value = 9, -- 2565 metal (Fido 285)
	health = 7,
	damage = 4,
	range = 1.2,
	scale = 1.6,
	speed = 0.95,
	footprint = 3,
	movementclass = "BOT3",
})
units.armt2hound = T4.hero(hound, 1.5)

-- Tesla, the Arc Knight (Zeus x1.5): a lightning brawler. Arc Discharge, Static Field and a called
-- Thunderstorm.
local tesla = hero("units/ArmBots/T2/armzeus.lua", "armzeus", {
	name = "armt2tesla",
	value = 9, -- 3150 metal (Zeus 350)
	health = 6,
	damage = 4,
	range = 1.35,
	scale = 1.5,
	speed = 0.95,
	footprint = 4,
	movementclass = "HBOT4",
})
units.armt2tesla = T4.hero(tesla, 1.5, {
	hero_chain = T4.weaponFrom(tesla.weapondefs.lightning, {
		damage = 250, burst = 1, range = 600, name = "Arc discharge", energypershot = 0,
		ceg = "custom:genericshellexplosion-medium-lightning2",
	}),
	hero_stormbolt = T4.weaponFrom(tesla.weapondefs.lightning, {
		damage = 1, burst = 1, range = 3000, name = "Thunderstorm bolt", thickness = 6, corethickness = 0.5,
		ceg = "custom:lightning_stormbig", soundstart = "lghthvy1", energypershot = 0,
	}),
})

-- Widow, the Rocket Matriarch (Recluse x1.5): an all-terrain missile spider. Venom Volley, Skitter and
-- Hatch the Brood.
local widow = hero("units/ArmBots/T2/armsptk.lua", "armsptk", {
	name = "armt2widow",
	value = 8, -- 3200 metal (Recluse 400)
	health = 6,
	damage = 3.5,
	range = 1.3,
	scale = 1.5,
	speed = 1.0,
	footprint = 3,
	movementclass = "TBOT3",
})
units.armt2widow = T4.hero(widow, 1.5, {
	hero_missile = T4.missileWeapon({
		damage = 400, aoe = 90, ceg = "custom:genericshellexplosion-medium", name = "Venom missile",
		model = widow.weapondefs.adv_rocket.model, cegtag = "missiletrailsmall", range = 1200, velocity = 700,
		soundhit = "xplomed2", soundstart = "rocklit1",
	}),
})

-- Starlight, the Dawn Lance (Starlight x1.5): a tachyon tank destroyer. Tank Buster, Focusing Lens and
-- the Orbital Lance.
local starlight = hero("units/ArmVehicles/T2/armmanni.lua", "armmanni", {
	name = "armt2starlight",
	value = 3.5, -- 4200 metal (Starlight 1200)
	health = 4,
	damage = 2.2,
	range = 1.3,
	scale = 1.5,
	speed = 0.9,
	footprint = 4,
	movementclass = "HTANK4",
})
units.armt2starlight = T4.hero(starlight, 1.6, {
	hero_nova = nova(6000, 350, 0.45),
})

-- Bulldog, the Iron Wall (Bulldog x1.5): the armoured spearhead. Reinforced Hull, Battering Ram and Iron
-- Wall over the army.
local bulldog = hero("units/ArmVehicles/T2/armbull.lua", "armbull", {
	name = "armt2bulldog",
	value = 4.5, -- 4275 metal (Bulldog 950)
	health = 5.5,
	damage = 3,
	range = 1.15,
	scale = 1.5,
	speed = 0.9,
	footprint = 4,
	movementclass = "HTANK4",
})
units.armt2bulldog = T4.hero(bulldog, 1.6)

-- Envoy, the Ambassador of Ruin (Ambassador x1.5): long-range starburst rockets. Forward Observer,
-- Countermeasures and the Final Ultimatum (tactical nukes).
local envoy = hero("units/ArmVehicles/T2/armmerl.lua", "armmerl", {
	name = "armt2envoy",
	value = 4.5, -- 4140 metal (Ambassador 920)
	health = 5,
	damage = 2.5,
	range = 1.25,
	scale = 1.5,
	speed = 0.9,
	footprint = 4,
	movementclass = "HTANK4",
})
units.armt2envoy = T4.hero(envoy, 1.6, {
	hero_nuke = T4.missileWeapon({
		damage = 5000, aoe = 320, ceg = FX.custom("newnuketac", 0.45), range = 3000, name = "Ultimatum tactical nuke",
		model = envoy.weapondefs.armtruck_rocket.model, cegtag = "missiletrailmedium-starburst",
	}),
})

-- Weaver, the Static Spinner (Webber x1.6): an all-terrain EMP spider. Tangle Web, Field Repair and Grid
-- Lock (a paralysing EMP wave).
local weaver = hero("units/ArmBots/T2/armspid.lua", "armspid", {
	name = "armt2weaver",
	value = 11, -- 2750 metal (Webber 250)
	health = 7,
	damage = 4,
	range = 1.4,
	scale = 1.6,
	speed = 0.95,
	footprint = 3,
	movementclass = "TBOT3",
})
units.armt2weaver = T4.hero(weaver, 1.4)

return units
