-- Custom T4 heroes, Armada (denysfast/bar-game). Built from the T3 gantry units, see gamedata/custom_t4.lua;
-- levels, talents and abilities: luarules/configs/t4_heroes.lua + luarules/gadgets/unit_t4_heroes.lua.
-- A level-1 hero is the old T4 at 0.4x cost, health and damage (the same value for its metal, 2.5x
-- smaller); levels and talents grow it past the old titan.
local T4 = VFS.Include("gamedata/custom_t4.lua")
local FX = T4.FX

local units = {}

-- Colossus Forge: the Armada hero altar (Experimental Gantry model x1.5)
units.armt4gant = T4.foundry(T4.base("units/ArmBuildings/LandFactories/armshltx.lua", "armshltx"), {
	name = "armt4gant",
	value = 4,
	scale = 1.5,
	workertime = 12,
	buildoptions = { "armt4atlas", "armt4olympus", "armt4aegis", "armt4zeus" },
})

-- Atlas, the Bulwark (Bantha x2): the assault anchor. Repair Field, Guardian Protocol, and rockets
-- that end the game as tactical nukes.
local atlas = T4.derive(T4.base("units/ArmGantry/armbanth.lua", "armbanth"), {
	name = "armt4atlas",
	value = 8.8,
	health = 7.2,
	damage = 7.2,
	range = 1.8,
	aoe = 1.8,
	scale = 2.0,
	speed = 0.8,
	footprint = 8,
	movementclass = "T4BOT8",
})
units.armt4atlas = T4.hero(atlas, 2.5, {
	hero_heavyrocket = T4.missileWeapon({
		damage = 13000, aoe = 180, ceg = FX.custom("genericshellexplosion-huge", 1.6), name = "Heavy starburst warhead",
		model = atlas.weapondefs.bantha_rocket.model, cegtag = FX.ref("missiletrailmedium-starburst", 2.5),
		range = atlas.weapondefs.bantha_rocket.range, soundhit = "xplolrg4",
	}),
	hero_nuke = T4.missileWeapon({
		damage = 14000, aoe = 420, ceg = FX.custom("newnuketac", 0.7), range = atlas.weapondefs.bantha_rocket.range,
		name = "Doomsday tactical nuke",
	}),
})

-- Olympus, the Thunderer (Vanguard x2.2): strategic artillery from 4200. Spotter Uplink, Rapid
-- Barrage, and shells that turn nuclear.
local olympus = T4.derive(T4.base("units/ArmGantry/armvang.lua", "armvang"), {
	name = "armt4olympus",
	value = 14.4,
	health = 6,
	damage = 11.2,
	range = 2.9,
	aoe = 2.5,
	scale = 2.2,
	speed = 0.75,
	sight = 1.8,
	footprint = 9,
	movementclass = "T4TBOT9",
	overrides = { radardistance = 3600 },
})
units.armt4olympus = T4.hero(olympus, 2.5, {
	hero_heavyshell = T4.weaponFrom(olympus.weapondefs.shocker_low, {
		mult = 1.6, aoe = 380, ceg = FX.custom("genericshellexplosion-huge", 1.6), name = "Incendiary heavy shell",
	}),
	hero_nukeshell = T4.weaponFrom(olympus.weapondefs.shocker_low, {
		damage = 26000, aoe = 520, ceg = FX.custom("newnuketac", 0.7), name = "Nuclear artillery shell",
		soundhit = "nukearm",
	}),
})

-- Aegis, the Warden (Razorback x2): the shield bearer. Its deflector starts at 30% and grows with
-- Deflector Matrix; Pulse Overload dumps the charge as EMP; Aegis Dome makes the army invulnerable.
local aegis = T4.derive(T4.base("units/ArmGantry/armraz.lua", "armraz"), {
	name = "armt4aegis",
	value = 11.2,
	health = 3.2,
	damage = 4.8,
	range = 1.6,
	aoe = 1.6,
	scale = 2.0,
	speed = 0.85,
	footprint = 8,
	movementclass = "T4BOT8",
})
aegis.weapondefs.t4_shield = T4.shieldWeapon(700, 9000, 180)
aegis.weapons[#aegis.weapons + 1] = { def = "T4_SHIELD" }
units.armt4aegis = T4.hero(aegis, 2.5)

-- Zeus Prime, the Stormlord (Thor x1.8): chain lightning, a paralysing static field and a called
-- lightning storm; its EMP missiles become EMP nukes.
local zeus = T4.derive(T4.base("units/ArmGantry/armthor.lua", "armthor"), {
	name = "armt4zeus",
	value = 9.6,
	health = 6,
	damage = 4.4,
	range = 2.0,
	aoe = 2.0,
	scale = 1.8,
	speed = 0.8,
	footprint = 9,
	movementclass = "T4TANK9",
	weapons = {
		empmissile = { range = 1.0 },
	},
})
units.armt4zeus = T4.hero(zeus, 2.2, {
	hero_chain = T4.weaponFrom(zeus.weapondefs.thunder, {
		mult = 0.6, burst = 1, range = 900, name = "Chain lightning", energypershot = 0,
		ceg = FX.custom("genericshellexplosion-huge-lightning", 1.6),
	}),
	hero_stormbolt = T4.weaponFrom(zeus.weapondefs.thunder, {
		damage = 1, burst = 1, range = 4000, name = "Storm bolt", thickness = 9, corethickness = 0.6,
		ceg = FX.custom("lightning_stormbig", 2), soundstart = "lghthvy1",
	}),
	hero_empnuke = T4.missileWeapon({
		damage = 560000, aoe = 700, ceg = FX.custom("genericshellexplosion-huge-lightning", 4), name = "EMP nuke",
		model = zeus.weapondefs.empmissile.model, cegtag = FX.ref("cruisemissiletrail-emp", 2.2),
		range = zeus.weapondefs.empmissile.range, soundhit = "mismed1emp1",
	}),
})
local empnuke = units.armt4zeus.weapondefs.hero_empnuke
empnuke.paralyzer = true
empnuke.paralyzetime = zeus.weapondefs.empmissile.paralyzetime or 20

return units
