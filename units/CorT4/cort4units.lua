-- Custom T4 heroes, Cortex (denysfast/bar-game). Built from the T3 gantry units, see gamedata/custom_t4.lua;
-- levels, talents and abilities: luarules/configs/t4_heroes.lua + luarules/gadgets/unit_t4_heroes.lua.
local T4 = VFS.Include("gamedata/custom_t4.lua")
local FX = T4.FX

local units = {}

-- Titan Crucible: the Cortex hero altar (Experimental Gantry model x1.5)
units.cort4gant = T4.foundry(T4.base("units/CorBuildings/LandFactories/corgant.lua", "corgant"), {
	name = "cort4gant",
	value = 8, -- v15: the altar costs 2x (metal, energy, build time); health and build power stay
	scale = 1.5,
	workertime = 12,
	buildoptions = { "cort4colossus", "cort4bastion", "cort4armageddon", "cort4hellwalker" },
})

local function nova(dmg, aoe, scale)
	return T4.novaWeapon({ damage = dmg, aoe = aoe, ceg = FX.custom("newnuketac", scale), name = "Nuclear nova" })
end

-- Colossus, the Warlord (Korgoth x1.8): War Stomp, a Command Aura for the army, and Undying -
-- it refuses to die, and at rank 3 it is reborn in a nuclear blast.
local colossus = T4.derive(T4.base("units/CorGantry/corkorg.lua", "corkorg"), {
	name = "cort4colossus",
	value = 6.2,
	health = 2.4,
	damage = 4.8,
	range = 1.4,
	aoe = 1.8,
	scale = 1.8,
	speed = 0.8,
	footprint = 11,
	movementclass = "T4BOT11",
	weapons = {
		krogkick = { aoe = 2.5, damage = 12 },
		krogfootstep = { aoe = 2.2 },
	},
})
units.cort4colossus = T4.hero(colossus, 2.2, {
	hero_nova = nova(24000, 650, 1.5),
})

-- Bastion, the Citadel (Juggernaut x1.6): Reactive Armor, Siege Protocol, and a gauss cannon that
-- ends as a nuclear gun.
local bastion = T4.derive(T4.base("units/CorGantry/corjugg.lua", "corjugg"), {
	name = "cort4bastion",
	value = 6.8,
	health = 3.2,
	damage = 4.4,
	range = 1.3,
	aoe = 1.6,
	scale = 1.6,
	speed = 0.8,
	footprint = 11,
	movementclass = "T4BOT11",
	overrides = {
		autoheal = 320,
		idleautoheal = 1600,
		idletime = 600,
	},
	weapons = {
		juggernaut_fire = { damage = 2 }, -- DGun hits every unit on its path
	},
})
bastion.weapondefs.t4_shield = T4.shieldWeapon(800, 12000, 200)
bastion.weapons[#bastion.weapons + 1] = { def = "T4_SHIELD" }
units.cort4bastion = T4.hero(bastion, 2.2, {
	hero_nukeshell = T4.shellWeapon({
		damage = 12000, aoe = 420, ceg = FX.custom("newnuketac", 0.7), name = "Nuclear gauss shell",
		velocity = bastion.weapondefs.juggernaut_fire.weaponvelocity or 600, gravity = 0.01,
		range = bastion.weapondefs.juggernaut_fire.range, rgb = "1 0.35 0.1", size = 9, soundhit = "nukearm",
	}),
})

-- Armageddon, the Doomsayer (Catapult x2): forty-rocket salvos from 2700 elmos (growing); Saturation adds
-- rockets, the ultimate puts nuclear warheads into the salvo - at rank 3 every rocket.
local armageddon = T4.derive(T4.base("units/CorGantry/corcat.lua", "corcat"), {
	name = "cort4armageddon",
	value = 10.4,
	health = 5.6,
	damage = 3.2, -- 5.2 (the old titan x0.4) out-damaged every other hero 3x from 2700 and farmed levels
	range = 2.0, -- 2700 at level 1: Long-Range Uplink and Servos take it past the old 3500
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
units.cort4armageddon = T4.hero(armageddon, 2.5, {
	-- homing: a copied Catapult rocket keeps turnrate 0 and only flies its arc when the engine fires it,
	-- a spawned one would fly straight on
	hero_nukerocket = T4.weaponFrom(armageddon.weapondefs.exp_heavyrocket, {
		damage = 16000, aoe = 430, ceg = FX.custom("newnuketac", 0.7), cegtag = "cruisemissiletrail-tacnuke",
		name = "Armageddon nuclear rocket", soundhit = "nukearm", tracks = true, turnrate = 22000, dance = 0, wobble = 0,
		flighttime = 12, targetable = 0,
	}),
	hero_mininuke = T4.weaponFrom(armageddon.weapondefs.exp_heavyrocket, {
		damage = 1600, aoe = 230, ceg = FX.custom("newnuketac", 0.45), name = "Armageddon mini-nuke",
		tracks = true, turnrate = 20000, flighttime = 12, targetable = 0,
	}),
})

-- Hellwalker, the Inferno (Demon x2): Immolation around it, Hellcharge through the enemy lines,
-- Rain of Fire from the sky - ending in a nuclear fireball.
local hellwalker = T4.derive(T4.base("units/CorGantry/cordemon.lua", "cordemon"), {
	name = "cort4hellwalker",
	value = 9.2,
	health = 5.2,
	damage = 4.4,
	range = 1.6,
	aoe = 1.3,
	scale = 2.0,
	speed = 0.9,
	footprint = 8,
	movementclass = "T4BOT8",
	weapons = {
		dmaw = { damage = 3.2 },
		newdmaw = { damage = 3.2 },
	},
})
units.cort4hellwalker = T4.hero(hellwalker, 2.5, {
	hero_meteor = T4.shellWeapon({
		damage = 3500, aoe = 240, ceg = FX.custom("genericshellexplosion-huge", 1.6), cegtag = "meteortrail",
		name = "Hellfire meteor", rgb = "1 0.4 0.05", size = 14, soundhit = "xplolrg4",
	}),
	hero_nova = nova(20000, 600, 1.5),
})

return units
