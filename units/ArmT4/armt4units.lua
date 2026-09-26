-- Custom T4 tier, Armada (denysfast/bar-game). Built from the T3 gantry units, see gamedata/custom_t4.lua.
local T4 = VFS.Include("gamedata/custom_t4.lua")

local units = {}

-- Colossus Forge: the Armada T4 foundry (Experimental Gantry model x1.5)
units.armt4gant = T4.foundry(T4.base("units/ArmBuildings/LandFactories/armshltx.lua", "armshltx"), {
	name = "armt4gant",
	value = 12,
	scale = 1.5,
	workertime = 18,
	buildoptions = { "armt4atlas", "armt4olympus", "armt4aegis", "armt4zeus" },
})

-- Atlas: assault titan (Bantha x2). Everything a Bantha does at 20x, plus a repair aura that keeps
-- the army around it alive - the centre of a late-game push.
units.armt4atlas = T4.derive(T4.base("units/ArmGantry/armbanth.lua", "armbanth"), {
	name = "armt4atlas",
	value = 22,
	health = 18,
	damage = 18,
	range = 1.8,
	aoe = 1.8,
	scale = 2.0,
	speed = 0.8,
	footprint = 8,
	movementclass = "T4BOT8",
	overrides = {
		customparams = { t4_heal_radius = 900, t4_heal_rate = 120 },
	},
})

-- Olympus: strategic artillery walker (Vanguard x2.2). Plasma shells from 4200 elmos with a 480
-- blast, its own long radar; slow and thin-skinned for its price - it needs an escort.
local olympus = T4.derive(T4.base("units/ArmGantry/armvang.lua", "armvang"), {
	name = "armt4olympus",
	value = 36,
	health = 15,
	damage = 28,
	range = 2.9,
	aoe = 2.5,
	scale = 2.2,
	speed = 0.75,
	sight = 1.8,
	footprint = 9,
	movementclass = "T4TBOT9",
	overrides = { radardistance = 3600 },
})
units.armt4olympus = olympus

-- Aegis: shield bearer (Razorback x2). A mobile 700-radius plasma deflector over the army plus
-- the Razorback's rapid lasers; fast enough to keep up with the push.
local aegis = T4.derive(T4.base("units/ArmGantry/armraz.lua", "armraz"), {
	name = "armt4aegis",
	value = 28,
	health = 8,
	damage = 12,
	range = 1.6,
	aoe = 1.6,
	scale = 2.0,
	speed = 0.85,
	footprint = 8,
	movementclass = "T4BOT8",
})
aegis.weapondefs.t4_shield = T4.shieldWeapon(700, 15000, 250)
aegis.weapons[#aegis.weapons + 1] = { def = "T4_SHIELD" }
units.armt4aegis = aegis

-- Zeus Prime: EMP storm tank (Thor x1.8). Chain lightning, a long EMP lance and stockpiled EMP
-- starbursts that paralyse whole armies (even T3) from 2100 elmos.
units.armt4zeus = T4.derive(T4.base("units/ArmGantry/armthor.lua", "armthor"), {
	name = "armt4zeus",
	value = 24,
	health = 15,
	damage = 11,
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

return units
