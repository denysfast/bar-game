-- Custom T4 tier, Cortex (denysfast/bar-game). Built from the T3 gantry units, see gamedata/custom_t4.lua.
local T4 = VFS.Include("gamedata/custom_t4.lua")

local units = {}

-- Titan Crucible: the Cortex T4 foundry (Experimental Gantry model x1.5)
units.cort4gant = T4.foundry(T4.base("units/CorBuildings/LandFactories/corgant.lua", "corgant"), {
	name = "cort4gant",
	value = 12,
	scale = 1.5,
	workertime = 18,
	buildoptions = { "cort4colossus", "cort4bastion", "cort4armageddon", "cort4hellwalker" },
})

-- Colossus: the Cortex flagship (Korgoth x1.8). Eradicator heat ray at 1530, gauss battery,
-- heavy rockets, and a stomp that flattens anything that gets under its feet.
units.cort4colossus = T4.derive(T4.base("units/CorGantry/corkorg.lua", "corkorg"), {
	name = "cort4colossus",
	value = 15.5,
	health = 6,
	damage = 12,
	range = 1.4,
	aoe = 1.8,
	scale = 1.8,
	speed = 0.8,
	footprint = 11,
	movementclass = "T4BOT11",
	weapons = {
		krogkick = { aoe = 2.5, damage = 30 },
		krogfootstep = { aoe = 2.2 },
	},
})

-- Bastion: walking fortress (Juggernaut x1.6). 3.7 million HP, its own plasma deflector,
-- and it repairs itself; slow, but nothing short of another T4 stops it.
local bastion = T4.derive(T4.base("units/CorGantry/corjugg.lua", "corjugg"), {
	name = "cort4bastion",
	value = 17,
	health = 8,
	damage = 11,
	range = 1.3,
	aoe = 1.6,
	scale = 1.6,
	speed = 0.8,
	footprint = 11,
	movementclass = "T4BOT11",
	overrides = {
		autoheal = 800,
		idleautoheal = 4000,
		idletime = 600,
	},
	weapons = {
		juggernaut_fire = { damage = 5 }, -- DGun hits every unit on its path
	},
})
bastion.weapondefs.t4_shield = T4.shieldWeapon(800, 30000, 500)
bastion.weapons[#bastion.weapons + 1] = { def = "T4_SHIELD" }
units.cort4bastion = bastion

-- Armageddon: rocket storm (Catapult x2). Forty-rocket salvos at 3500 elmos with a wide blast:
-- it deletes armies and bases, but it is fragile up close.
units.cort4armageddon = T4.derive(T4.base("units/CorGantry/corcat.lua", "corcat"), {
	name = "cort4armageddon",
	value = 26,
	health = 14,
	damage = 13,
	range = 2.6,
	aoe = 2.5,
	scale = 2.0,
	speed = 0.8,
	sight = 1.8,
	footprint = 8,
	movementclass = "T4BOT8",
	weapons = {
		exp_heavyrocket = { burst = 40 },
	},
	overrides = { radardistance = 3000 },
})

-- Hellwalker: flame titan (Demon x2). Fast for its size, a 800-elmo firestorm and shoulder rockets;
-- it runs into a base and burns it down.
units.cort4hellwalker = T4.derive(T4.base("units/CorGantry/cordemon.lua", "cordemon"), {
	name = "cort4hellwalker",
	value = 23,
	health = 13,
	damage = 11,
	range = 1.6,
	aoe = 1.3,
	scale = 2.0,
	speed = 0.9,
	footprint = 8,
	movementclass = "T4BOT8",
	weapons = {
		dmaw = { damage = 8 },
		newdmaw = { damage = 8 },
	},
})

return units
