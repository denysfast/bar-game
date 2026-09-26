-- Custom T4 tier, Legion (denysfast/bar-game). Built from the T3 gantry units, see gamedata/custom_t4.lua.
-- Lives under units/Legion/ so it only loads when the Legion faction is enabled.
local T4 = VFS.Include("gamedata/custom_t4.lua")

local units = {}

-- Apex Forge: the Legion T4 foundry (Experimental Gantry model x1.5)
units.legt4gant = T4.foundry(T4.base("units/Legion/Labs/leggant.lua", "leggant"), {
	name = "legt4gant",
	value = 12,
	scale = 1.5,
	workertime = 18,
	buildoptions = { "legt4helios", "legt4starfall", "legt4longinus", "legt4tempest" },
})

-- Helios: thermal titan (heat-ray mech x1.8). Twin heat rays at 1400, the ultra-heavy riot cannons
-- and flak, plus a repair aura - the Legion's anchor of a push.
units.legt4helios = T4.derive(T4.base("units/Legion/T3/legeheatraymech.lua", "legeheatraymech"), {
	name = "legt4helios",
	value = 17,
	health = 7.5,
	damage = 13,
	range = 1.75,
	aoe = 1.6,
	scale = 1.8,
	speed = 0.8,
	footprint = 11,
	movementclass = "T4BOT11",
	overrides = {
		customparams = { t4_heal_radius = 1000, t4_heal_rate = 150 },
	},
})

-- Starfall: orbital-range plasma mech (ELRPC mech x1.6). Cluster plasma volleys from ~7000 elmos
-- with its own long radar: it shells the enemy base from its own.
units.legt4starfall = T4.derive(T4.base("units/Legion/T3/legelrpcmech.lua", "legelrpcmech"), {
	name = "legt4starfall",
	value = 23,
	health = 22,
	damage = 20,
	range = 2.25,
	aoe = 1.8,
	scale = 1.6,
	speed = 0.75,
	sight = 1.8,
	footprint = 11,
	movementclass = "T4BOT11",
	overrides = { radardistance = 4500 },
})

-- Longinus: rail titan (rail tank x1.8). A 2200-elmo rail shot that goes through everything in its
-- line - built to kill other T4s and whole columns of T3.
units.legt4longinus = T4.derive(T4.base("units/Legion/T3/legerailtank.lua", "legerailtank"), {
	name = "legt4longinus",
	value = 23,
	health = 18,
	damage = 12,
	range = 1.2,
	aoe = 1.5,
	scale = 1.8,
	speed = 0.8,
	footprint = 9,
	movementclass = "T4TANK9",
	weapons = {
		t3_rail_accelerator = { noexplode = true, reloadtime = 4 },
	},
})

-- Tempest: assault storm (shotgun mech x2). Fast, shreds anything up close with kinetic shotguns,
-- rains multi-rockets and keeps the sky clear with rotary flak.
units.legt4tempest = T4.derive(T4.base("units/Legion/T3/legeshotgunmech.lua", "legeshotgunmech"), {
	name = "legt4tempest",
	value = 21,
	health = 18,
	damage = 14,
	range = 1.6,
	aoe = 1.6,
	scale = 2.0,
	speed = 0.9,
	footprint = 8,
	movementclass = "T4BOT8",
})

return units
