-- Custom T2 heroes, Cortex (denysfast/bar-game): ten heroes built from Cortex T2 bots and vehicles, and
-- the Cortex T2 Hero Hall that builds and revives them. Unitdefs via gamedata/custom_t4.lua (T4.derive +
-- T4.hero, models scaled by tools/t4/build_models.py); levels, talents and abilities:
-- luarules/configs/t4_hero_defs_t2_cor.lua + luarules/gadgets/unit_t4_heroes.lua.
-- A T2 hero costs 2500-6000 metal (3-5 of its base unit in value at level 1, x13 for the cheap Pyro),
-- clearly weaker than the T4 heroes, and levels the same way.
local T4 = VFS.Include("gamedata/custom_t4.lua")

local FX_SCALE = 1.5 -- CEG scale of the T2 heroes' flashes, trails and blasts (T4.hero)

local units = {}

-- Hero Hall: the Cortex T2 bot lab x1.3, one per team; builds and revives the ten heroes, heals them
-- like the T4 altar does (fountain)
local hall = T4.foundry(T4.base("units/CorBuildings/LandFactories/coralab.lua", "coralab"), {
	name = "cort2hall",
	value = 2.3, -- 2600 -> ~6000 metal
	scale = 1.3,
	workertime = 3,
	buildoptions = {
		"cort2sumo", "cort2can", "cort2pyro", "cort2termite", "cort2arbiter",
		"cort2sheldon", "cort2goliath", "cort2tiger", "cort2banisher", "cort2tremor",
	},
})
hall.health = 4500 * 5
hall.explodeas = "largeBuildingExplosionGeneric"
hall.selfdestructas = "largeBuildingExplosionGenericSelfd"
hall.customparams.techlevel = 2
hall.customparams.unitgroup = "builder"
hall.customparams.t2_hero_hall = 1
units.cort2hall = hall

-- common T2 hero chassis parameters on top of T4.derive
local function derive(path, base, p)
	p.turn = p.turn or 0.8
	p.accel = p.accel or 0.8
	p.sight = p.sight or 1.4
	p.aoe = p.aoe or 1.2
	p.explodeas = p.explodeas or "largeExplosionGeneric"
	p.selfdestructas = p.selfdestructas or "largeExplosionGenericSelfd"
	local ud = T4.derive(T4.base(path, base), p)
	ud.customparams.techlevel = 2
	ud.customparams.t2_hero = 1
	ud.customparams.subfolder = "T2Heroes"
	ud.selfdestructcountdown = 5
	return ud
end

local function nova(dmg, aoe, ceg, name)
	return T4.novaWeapon({ damage = dmg, aoe = aoe, ceg = ceg, name = name or "Hero nova", soundhit = "xplolrg4" })
end

-- a called-in artillery shell (active_barrage, projectile = "shell"): damage comes from the ability
local function barrageShell(name, dmg, aoe)
	return T4.shellWeapon({
		damage = dmg, aoe = aoe, ceg = "custom:genericshellexplosion-large", cegtag = "arty-huge",
		name = name, rgb = "1 0.6 0.2", size = 5, soundhit = "xplomed4", velocity = 800,
	})
end

-- Sumo, the Juggernaut (Sumo x1.4): the walking wall. Ironhide plating, Sumo Stance shields the allies
-- around, Unbreakable soaks a flood of damage.
units.cort2sumo = T4.hero(derive("units/CorBots/T2/corsumo.lua", "corsumo", {
	name = "cort2sumo",
	value = 2.5, -- 5500 metal
	health = 2.6, -- 40560
	damage = 2.0,
	range = 1.1,
	scale = 1.4,
	speed = 0.9,
	footprint = 4,
	movementclass = "HBOT4",
}), FX_SCALE)

-- Can, the Brawler (Can x1.5): a close-range laser bruiser that drinks from its hits, charges in
-- shoulder first and goes berserk.
units.cort2can = T4.hero(derive("units/CorBots/T2/corcan.lua", "corcan", {
	name = "cort2can",
	value = 5, -- 2800 metal
	health = 4.5, -- 27000
	damage = 2.5,
	range = 1.25,
	scale = 1.5,
	speed = 0.95,
	footprint = 3,
	movementclass = "BOT3",
}), FX_SCALE)

-- Pyro, the Firestarter (Pyro x1.6): a fast flamethrower that burns everything around it, dashes through
-- the enemy line on a trail of fire and ends in an inferno burst.
local pyro = derive("units/CorBots/T2/corpyro.lua", "corpyro", {
	name = "cort2pyro",
	value = 13, -- 2600 metal
	health = 14, -- 14840
	damage = 3.5,
	range = 1.3,
	scale = 1.6,
	speed = 0.85,
	footprint = 3,
	movementclass = "BOT3",
})
units.cort2pyro = T4.hero(pyro, FX_SCALE, {
	hero_nova = nova(2500, 480, "custom:genericshellexplosion-huge", "Inferno burst"),
})

-- Termite, the Infiltrator (Termite x1.5): an all-terrain heat-ray spider, radar-stealthy, that burrows
-- out of sight, shocks what walks near it and ends a fight with an EMP burst.
local termite = derive("units/CorBots/T2/cortermite.lua", "cortermite", {
	name = "cort2termite",
	value = 5.5, -- 2970 metal
	health = 5, -- 15500
	damage = 2.4,
	range = 1.3,
	scale = 1.5,
	speed = 0.9,
	footprint = 5,
	movementclass = "HTBOT6",
	overrides = { stealth = true },
})
units.cort2termite = T4.hero(termite, FX_SCALE, {
	hero_nova = nova(1500, 550, "custom:genericshellexplosion-huge-lightning", "EMP burst"),
})

-- Arbiter, the Judge (Arbiter x1.5): heavy starburst rockets from far behind the line, a target
-- designator for the army and swarms of homing missiles.
local arbiter = derive("units/CorBots/T2/corhrk.lua", "corhrk", {
	name = "cort2arbiter",
	value = 6, -- 3600 metal
	health = 18, -- 10980
	damage = 2.5,
	range = 1.2,
	scale = 1.5,
	speed = 0.85,
	footprint = 4,
	movementclass = "HBOT4",
	weapons = {
		corhrk_rocket = { burst = 3, burstrate = 0.4 },
	},
})
units.cort2arbiter = T4.hero(arbiter, FX_SCALE, {
	hero_missile = T4.missileWeapon({
		name = "Judgement missile", damage = 1000, aoe = 110, model = "corkbmissl1.s3o",
		ceg = "custom:genericshellexplosion-medium", cegtag = "missiletrailmedium-starburst",
		soundhit = "xplomed2", soundstart = "rocklit1", range = 1800, velocity = 700,
	}),
})

-- Sheldon, the Bombardier (Sheldon x1.6): a plasma mortar that splits its shells, digs in for more
-- punch and calls a mortar barrage on an area.
local sheldon = derive("units/CorBots/T2/cormort.lua", "cormort", {
	name = "cort2sheldon",
	value = 7, -- 2800 metal
	health = 12, -- 11280
	damage = 3.5,
	range = 1.2,
	scale = 1.6,
	speed = 0.85,
	footprint = 3,
	movementclass = "BOT3",
	weapons = {
		cor_mort = { burst = 2, burstrate = 0.3 },
	},
})
units.cort2sheldon = T4.hero(sheldon, FX_SCALE, {
	hero_shell = barrageShell("Mortar barrage shell", 500, 150),
})

-- Goliath, the Immovable (Goliath x1.4): the heavy tank with a plasma deflector over its escort, an
-- armor phalanx aura and a dome that nothing gets through for a few seconds.
local goliath = derive("units/CorVehicles/T2/corgol.lua", "corgol", {
	name = "cort2goliath",
	value = 3.2, -- 5280 metal
	health = 4, -- 31200
	damage = 2.2,
	range = 1.15,
	aoe = 1.0,
	scale = 1.4,
	speed = 0.85,
	footprint = 6,
	movementclass = "HTANK7",
})
goliath.weapondefs.t4_shield = T4.shieldWeapon(320, 3000, 45)
goliath.weapondefs.t4_shield.name = "Goliath Plasma Deflector"
goliath.weapons[#goliath.weapons + 1] = { def = "T4_SHIELD" }
units.cort2goliath = T4.hero(goliath, FX_SCALE)

-- Tiger, the Striker (Tiger x1.5): the fast assault tank that hunts big targets, pounces and calls its
-- pride of Tigers into the fight.
units.cort2tiger = T4.hero(derive("units/CorVehicles/T2/correap.lua", "correap", {
	name = "cort2tiger",
	value = 5, -- 3450 metal
	health = 4.5, -- 23850
	damage = 3.5,
	range = 1.2,
	scale = 1.5,
	speed = 0.9,
	footprint = 4,
	movementclass = "HTANK4",
}), FX_SCALE)

-- Banisher, the Exiler (Banisher x1.4): heavy guided missiles whose warheads arc to the next target,
-- long-range telemetry, and a banishment strike through a whole line of enemies.
local banisher = derive("units/CorVehicles/T2/corban.lua", "corban", {
	name = "cort2banisher",
	value = 4.5, -- 4500 metal
	health = 8, -- 20000
	damage = 2.5,
	range = 1.3,
	scale = 1.4,
	speed = 0.85,
	footprint = 4,
	movementclass = "HTANK4",
})
local zeusLightning = T4.base("units/ArmBots/T2/armzeus.lua", "armzeus").weapondefs.lightning
units.cort2banisher = T4.hero(banisher, FX_SCALE, {
	hero_chain = T4.weaponFrom(zeusLightning, {
		damage = 400, burst = 1, range = 700, name = "Arc warhead", energypershot = 0,
		ceg = "custom:genericshellexplosion-medium-lightning",
	}),
	hero_spear = T4.weaponFrom(banisher.weapondefs.banisher, {
		damage = 3000, range = 1900, name = "Banishment missile", tracks = true, turnrate = 30000,
		aoe = 220, ceg = "custom:genericshellexplosion-huge", flighttime = 6, targetable = 0,
	}),
	hero_nova = nova(4000, 400, "custom:genericshellexplosion-huge", "Banishment blast"),
})

-- Tremor, the Earthshaker (Tremor x1.4): the carpet artillery. Seismic quakes around it, a slowing
-- field and a carpet barrage that turns an area into craters.
local tremor = derive("units/CorVehicles/T2/cortrem.lua", "cortrem", {
	name = "cort2tremor",
	value = 2.8, -- 5180 metal
	health = 7, -- 21000
	damage = 1.6,
	range = 1.15,
	scale = 1.4,
	speed = 0.85,
	footprint = 4,
	movementclass = "HTANK4",
})
units.cort2tremor = T4.hero(tremor, FX_SCALE, {
	hero_shell = barrageShell("Carpet barrage shell", 450, 180),
	hero_nova = nova(1000, 450, "custom:genericshellexplosion-large", "Ground quake"),
})

return units
