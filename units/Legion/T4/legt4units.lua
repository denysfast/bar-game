-- Custom T4 heroes, Legion (denysfast/bar-game). Built from the T3 gantry units, see gamedata/custom_t4.lua;
-- levels, talents and abilities: luarules/configs/t4_heroes.lua + luarules/gadgets/unit_t4_heroes.lua.
-- Lives under units/Legion/ so it only loads when the Legion faction is enabled.
local T4 = VFS.Include("gamedata/custom_t4.lua")
local FX = T4.FX

local units = {}

-- Apex Forge: the Legion hero altar (Experimental Gantry model x1.5)
units.legt4gant = T4.foundry(T4.base("units/Legion/Labs/leggant.lua", "leggant"), {
	name = "legt4gant",
	value = 4,
	scale = 1.5,
	workertime = 12,
	buildoptions = { "legt4helios", "legt4starfall", "legt4longinus", "legt4tempest" },
})


-- Helios, the Sunbringer (heat-ray mech x1.8): twin heat rays, Solar Flare, Heat Haze and Sunstrike -
-- a beam of the sun that ends in a nuclear flare.
local helios = T4.derive(T4.base("units/Legion/T3/legeheatraymech.lua", "legeheatraymech"), {
	name = "legt4helios",
	value = 6.8,
	health = 3,
	damage = 5.2,
	range = 1.75,
	aoe = 1.6,
	scale = 1.8,
	speed = 0.8,
	footprint = 11,
	movementclass = "T4BOT11",
})
units.legt4helios = T4.hero(helios, 2.2)

-- Starfall, the Astronomer (ELRPC mech x1.6): plasma volleys from ~7000 elmos, Starburst Rounds, and a
-- Meteor Storm called from orbit.
local starfall = T4.derive(T4.base("units/Legion/T3/legelrpcmech.lua", "legelrpcmech"), {
	name = "legt4starfall",
	value = 9.2,
	health = 8.8,
	damage = 8,
	range = 2.25,
	aoe = 1.8,
	scale = 1.6,
	speed = 0.75,
	sight = 1.8,
	footprint = 11,
	movementclass = "T4BOT11",
	overrides = { radardistance = 4500 },
})
units.legt4starfall = T4.hero(starfall, 2.5)

-- Longinus, the Spear (rail tank x1.8): the titan hunter. Titan Slayer, Phase Cloak, and the
-- Spear of Longinus - one rail shot through everything, nuclear at rank 3.
local longinus = T4.derive(T4.base("units/Legion/T3/legerailtank.lua", "legerailtank"), {
	name = "legt4longinus",
	value = 9.2,
	health = 7.2,
	damage = 4.8,
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
units.legt4longinus = T4.hero(longinus, 2.2)

-- Tempest, the Stormblade (shotgun mech x2): the melee blademaster. Critical Strike, Mirror Images and
-- Bladestorm.
local tempest = T4.derive(T4.base("units/Legion/T3/legeshotgunmech.lua", "legeshotgunmech"), {
	name = "legt4tempest",
	value = 8.4,
	health = 7.2,
	damage = 5.6,
	range = 1.6,
	aoe = 1.6,
	scale = 2.0,
	speed = 0.9,
	footprint = 8,
	movementclass = "T4BOT8",
})
units.legt4tempest = T4.hero(tempest, 2.5)

return units
