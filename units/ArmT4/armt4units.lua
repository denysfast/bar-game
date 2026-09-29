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
	value = 8, -- v15: the altar costs 2x (metal, energy, build time); health and build power stay
	scale = 1.5,
	workertime = 12,
	buildoptions = { "armt4atlas", "armt4olympus", "armt4aegis", "armt4zeus" },
})

-- Atlas, the Bulwark (Bantha x2): the assault anchor. Repair Field, Shoulder Battery, and a Doomsday
-- Barrage of tactical nukes.
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
units.armt4atlas = T4.hero(atlas, 2.5)

-- Olympus, the Thunderer (Vanguard x2.2): strategic artillery from 4200. Spotter Uplink, Blast
-- Shield, and an Orbital Strike.
local olympus = T4.derive(T4.base("units/ArmGantry/armvang.lua", "armvang"), {
	name = "armt4olympus",
	value = 14.4,
	health = 6,
	damage = 11.2,
	range = 2.3, -- 3340 at level 1, Spotter Uplink and Servos grow it
	aoe = 2.5,
	scale = 2.2,
	speed = 0.75,
	sight = 1.8,
	footprint = 9,
	movementclass = "T4TBOT9",
	overrides = { radardistance = 3600 },
})
units.armt4olympus = T4.hero(olympus, 2.5)

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
-- lightning storm that ends in an EMP blast.
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
units.armt4zeus = T4.hero(zeus, 2.2)

return units
