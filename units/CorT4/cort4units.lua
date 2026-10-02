-- Custom T4 heroes, Cortex (denysfast/bar-game), v19: ten heroes of the Titan Crucible. Built from the T3 gantry,
-- scavenger and T2 units, see gamedata/custom_t4.lua. Design doc/v19-heroes/roster_cor.md; abilities
-- luarules/configs/heroes/cor.lua + luarules/heroes/cort4*.lua; levels and stats luarules/gadgets/unit_t4_heroes.lua.
-- HP, DPS and speed come from T4.heroBalance (the per-weapon damage multipliers here only shape the split).
local T4 = VFS.Include("gamedata/custom_t4.lua")

local units = {}

-- the hero's own weapons never cost energy (the scavenger / gantry bases spend 500-1500 per shot)
local function freeShots(ud)
	for _, wd in pairs(ud.weapondefs or {}) do
		wd.energypershot = nil
		wd.metalpershot = nil
	end
end

-- the look of an ability projectile whose damage the hero module applies by the clock (L.lob / L.drop in
-- luarules/heroes/cort4_lib.lua): it flies through units and lands where it was aimed
local function groundOnly(wd)
	wd.collideenemy = false
	wd.collidefriendly = false
	wd.collidefeature = false
	wd.collideneutral = false
	wd.avoidfriendly = false
	wd.avoidfeature = false
	return wd
end

-- a builder base turned into a fighter: no construction
local function noBuild(ud, keepRepair)
	ud.buildoptions = nil
	ud.builder = keepRepair or false
	ud.canassist = false
	ud.canreclaim = false
	ud.canrestore = false
	ud.canrepair = keepRepair or false
	ud.cancapture = false
	ud.canresurrect = false
	if not keepRepair then
		ud.workertime = nil
		ud.builddistance = nil
	end
end

-- Titan Crucible: the Cortex hero altar (Experimental Gantry model x1.5)
units.cort4gant = T4.foundry(T4.base("units/CorBuildings/LandFactories/corgant.lua", "corgant"), {
	name = "cort4gant",
	value = 8, -- v15: the altar costs 2x (metal, energy, build time); health and build power stay
	scale = 1.5,
	workertime = 12,
	buildoptions = { "cort4bastion", "cort4colossus", "cort4hellwalker", "cort4armageddon", "cort4vesuvius",
		"cort4printer", "cort4commando", "cort4deadeye", "cort4karganeth", "cort4cataphract" },
})

----------------------------------------------------------------------------------------------- 0 Juggernaut
-- Juggernaut, the Unkillable (Behemoth x1.6): Power Shot, Circle Beam, Reactive Armor, Resurrection.
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
freeShots(bastion)
units.cort4bastion = T4.hero(bastion, 2.2, {
	-- Power Shot shells: a fast flat gauss slug (the damage is the ability's, applied on impact)
	powershot = T4.shellWeapon({ name = "Power Shot", damage = 1, aoe = 40, velocity = 1500, size = 7, rgb = "1 0.6 0.2",
		ceg = "custom:blank", soundstart = "krogun1", soundhit = "xplomed2", range = 2000 }),
	-- Reactive Armor: a plasma shell fired back from the armour
	reactive = T4.shellWeapon({ name = "Reactive Plasma", damage = 1, aoe = 120, velocity = 1100, size = 5, rgb = "1 0.7 0.25",
		ceg = "custom:blank", soundstart = "cannon2", soundhit = "xplomed2", range = 1600 }),
})

----------------------------------------------------------------------------------------------- 1 Colossus
-- Colossus, the Warlord (Korgoth x1.8): Titan Grip, Fault Line, Warcry, Earthshatter.
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
freeShots(colossus)
units.cort4colossus = T4.hero(colossus, 2.2)

----------------------------------------------------------------------------------------------- 2 Hellwalker
-- Hellwalker, the Inferno (Demon x2): Combustion, Hellcharge, Infernal Furnace, Hell on Earth.
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
-- the shoulder pods stay anti-air only: no ground damage, so the balance counts only the Maw
hellwalker.weapondefs.karg_shoulder.damage = { default = 1, vtol = 2400 }
freeShots(hellwalker)
units.cort4hellwalker = T4.hero(hellwalker, 2.5, {
	-- Hell on Earth meteors (the damage is the ability's; the impact is drawn by the module)
	meteor = groundOnly(T4.shellWeapon({ name = "Hellfire Meteor", damage = 1, aoe = 200, velocity = 1350, size = 16, rgb = "1 0.45 0.08",
		ceg = "custom:blank", soundhit = "xplolrg4", range = 9000 })),
})

----------------------------------------------------------------------------------------------- 3 Armageddon
-- Armageddon, the Doomsayer (Catapult x2): Cluster Warheads, Doom Painter, Retro Rockets, Armageddon Protocol.
local armageddon = T4.derive(T4.base("units/CorGantry/corcat.lua", "corcat"), {
	name = "cort4armageddon",
	value = 10.4,
	health = 5.6,
	damage = 3.2,
	range = 2.0, -- 2700 at level 1
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
freeShots(armageddon)
local bomblet = T4.shellWeapon({ name = "Cluster Bomblet", damage = 1, aoe = 90, velocity = 420, size = 3.2, rgb = "1 0.55 0.15",
	ceg = "custom:blank", soundhit = "xplosml2", range = 600 })
bomblet.soundhit = "xplosml2"
groundOnly(bomblet)
local rain = T4.missileWeapon({ name = "Armageddon Rain", damage = 1, aoe = 200, model = "catapultmissile.s3o", velocity = 1100,
	ceg = "custom:blank", cegtag = "missiletrailsmall-red", soundhit = "rockhit", soundstart = "rapidrocket3", range = 5000 })
rain.customparams = { t4_ability = 1 }
rain.smoketrail = false
groundOnly(rain)
units.cort4armageddon = T4.hero(armageddon, 2.5, {
	bomblet = bomblet,
	rain = rain,
	nuke = (function()
		local w = T4.nukeWeapon({ name = "Armageddon Warhead", damage = 1, aoe = 600, ceg = "custom:blank", customparams = { t4_ability = 1 } })
		w.smoketrail = false
		return groundOnly(w)
	end)(),
})

----------------------------------------------------------------------------------------------- 4 Vesuvius
-- Vesuvius, the Twin-Barrel (Vesuvius x1.8): Twin Impact, Banisher Lock, Siege Mode, Eruption.
local vesuviusBase = T4.base("units/Scavengers/Vehicles/corves.lua", "corves")
local vesuvius = T4.derive(vesuviusBase, {
	name = "cort4vesuvius",
	value = 8,
	health = 4,
	damage = 2,
	range = 1.2,
	aoe = 1.5,
	scale = 1.8,
	speed = 0.8,
	footprint = 9,
	movementclass = "T4TANK9",
	weapons = {
		-- the two barrels fire as a pair (Twin Impact); a smaller blast than the tactical-nuke shell of the base
		corlevlr_weapon = { burst = 2, burstrate = 0.2, aoe = 0.6, explosiongenerator = "custom:genericshellexplosion-huge" },
		flamethrower = { damage = 0.4 }, -- close defense, not the main gun
	},
})
freeShots(vesuvius)
do
	local ban = T4.deepcopy(vesuviusBase.weapondefs.banisher)
	local salvo = T4.weaponFrom(ban, { damage = 1, aoe = 128, ceg = "custom:blank" })
	salvo.name = "Banisher Lock"
	salvo.trajectoryheight = nil -- a respawned rocket with a trajectory loses its target
	salvo.customparams = { t4_ability = 1 }
	salvo.range = 3000
	salvo.flighttime = 6
	salvo.weaponvelocity = 900
	local volcanic = T4.shellWeapon({ name = "Volcanic Bomb", damage = 1, aoe = 300, velocity = 900, size = 14, rgb = "1 0.35 0.05",
		ceg = "custom:blank", soundstart = "krogun1", soundhit = "xplonuk2", range = 4000 })
	volcanic.customparams = { t4_ability = 1 }
	groundOnly(volcanic)
	units.cort4vesuvius = T4.hero(vesuvius, 2.2, { salvo = salvo, volcanic = volcanic })
end

----------------------------------------------------------------------------------------------- 5 Printer
-- Printer, the Swarm Foundry (Printer x2.8): Drone Bay, Print Turret, Repair Swarm, Swarm Protocol.
local printerBase = T4.base("units/CorVehicles/T2/corprinter.lua", "corprinter")
noBuild(printerBase, true)
printerBase.weapondefs = {
	printer_disassembler = {
		name = "Disassembler Beam",
		weapontype = "BeamLaser",
		areaofeffect = 16,
		avoidfeature = false,
		beamtime = 0.3,
		beamttl = 0.5,
		corethickness = 0.35,
		craterareaofeffect = 0,
		craterboost = 0,
		cratermult = 0,
		edgeeffectiveness = 0.6,
		explosiongenerator = "custom:laserhit-medium-green",
		impactonly = 1,
		impulsefactor = 0,
		laserflaresize = 9,
		noselfdamage = true,
		range = 750,
		reloadtime = 0.6,
		rgbcolor = "0.3 1 0.4",
		rgbcolor2 = "0.8 1 0.85",
		soundstart = "lasrhvy3",
		soundtrigger = 1,
		thickness = 3.5,
		tolerance = 10000,
		turret = true,
		weaponvelocity = 1500,
		damage = { default = 1500 },
	},
}
printerBase.weapons = { { def = "PRINTER_DISASSEMBLER", onlytargetcategory = "SURFACE" } }
local printer = T4.derive(printerBase, {
	name = "cort4printer",
	value = 8,
	health = 20,
	damage = 1,
	range = 1.0,
	aoe = 1.0,
	scale = 2.8,
	speed = 0.8,
	footprint = 9,
	movementclass = "T4TANK9",
	weapons = {
		printer_disassembler = { size = 2 },
	},
})
printer.workertime = 1200 -- repair only (no build options)
printer.repairspeed = 1200
printer.builddistance = 400
units.cort4printer = T4.hero(printer, 2.2, {
	swarm = (function()
		local w = T4.missileWeapon({ name = "Micro-drone", damage = 1, aoe = 120, model = "Units/cordrone.s3o", velocity = 750,
			ceg = "custom:blank", cegtag = "missiletrailsmall-simple", soundhit = "xplomed2",
			soundstart = "mismed1", range = 3000, turnrate = 32000 })
		w.smoketrail = false
		w.customparams = { t4_ability = 1 }
		return w
	end)(),
})

-- Drone Bay: an attack drone (cordrone x1.5), 10k HP; its damage is set per rank by the hero module
do
	local d = T4.base("units/CorAircraft/cordrone.lua", "cordrone")
	d.objectname = "Units/T4/cort4printer_drone.s3o"
	d.health = 10000
	d.metalcost = 50
	d.energycost = 0
	d.buildtime = 10
	d.speed = 300
	d.cruisealtitude = 80
	d.sightdistance = 900
	d.customparams.t4_summon = 1
	d.customparams.drone = nil
	d.customparams.subfolder = "T4"
	local w = d.weapondefs.heat_ray
	w.range = 450
	w.reloadtime = 1
	w.rgbcolor = "0.3 1 0.4"
	w.rgbcolor2 = "0.8 1 0.85"
	w.thickness = 2.6
	w.laserflaresize = 7
	w.explosiongenerator = "custom:laserhit-small-green"
	w.damage = { default = 400, vtol = 100 }
	units.cort4printer_drone = d
end

-- Print Turret: a printed quad laser guard (corhllllt x1.5); HP and damage set per rank by the hero module
do
	local t = T4.base("units/Scavengers/Buildings/DefenseOffense/corhllllt.lua", "corhllllt")
	t.objectname = "Units/T4/cort4printer_turret.s3o"
	t.metalcost = 50
	t.energycost = 0
	t.buildtime = 10
	t.health = 12000
	t.footprintx = 3
	t.footprintz = 3
	t.yardmap = "ooooooooo"
	t.collisionvolumescales = T4.scaleVec(t.collisionvolumescales, 1.5)
	t.collisionvolumeoffsets = T4.scaleVec(t.collisionvolumeoffsets, 1.5)
	t.corpse = nil
	t.featuredefs = nil
	t.sightdistance = 700
	t.customparams.t4_summon = 1
	t.customparams.subfolder = "T4"
	t.customparams.buildinggrounddecalsizex = 6
	t.customparams.buildinggrounddecalsizey = 6
	for _, w in pairs(t.weapondefs) do
		w.range = 600
		w.energypershot = nil
		w.rgbcolor = "0.35 1 0.45"
		w.explosiongenerator = "custom:laserhit-small-green"
	end
	units.cort4printer_turret = t
end

----------------------------------------------------------------------------------------------- 6 Commando
-- Commando, the Ghost (Epic Commando x2.6): Ghost Protocol, Disruptor Mines, Shadowstep, Blackout.
local commandoBase = T4.base("units/Scavengers/Bots/cormandot4.lua", "cormandot4")
noBuild(commandoBase)
commandoBase.cloakcost = 0
commandoBase.customparams.firestateoncloak = nil -- Ghost Protocol: the first shot from cloak is the Ambush
-- the Disintegrator goes to weapon slot 1 (aimed by the arm, quick): in slot 2 the scavenger script's back turret
-- needs ~5 s to unfold and never fired while the EMP scattergun kept re-aiming the arm
commandoBase.weapons = { commandoBase.weapons[2], commandoBase.weapons[1] }
commandoBase.weapons[1].badtargetcategory = nil
commandoBase.cloakcostmoving = 0
local commando = T4.derive(commandoBase, {
	name = "cort4commando",
	value = 8,
	health = 20,
	damage = 1,
	range = 2.0,
	aoe = 1.5,
	scale = 2.6,
	speed = 1.0,
	footprint = 8,
	movementclass = "T4BOT8",
	overrides = { mincloakdistance = 50, radardistancejam = 400 },
})
freeShots(commando)
units.cort4commando = T4.hero(commando, 2.2)

----------------------------------------------------------------------------------------------- 7 Deadeye
-- Deadeye, the Marksman (Deadeye x2.8): Focus, Recon Flare, Tumble, Kill Shot.
local deadeye = T4.derive(T4.base("units/Scavengers/Bots/cordeadeye.lua", "cordeadeye"), {
	name = "cort4deadeye",
	value = 8,
	health = 20,
	damage = 1,
	range = 2.2, -- 1870
	aoe = 1.5,
	scale = 2.8,
	speed = 0.8,
	sight = 2.4,
	footprint = 8,
	movementclass = "T4BOT8",
	weapons = {
		-- a volley every 6 s (not a 100k alpha strike every 12); red-hot Cortex bolts
		cor_burst_laser = { reloadtime = 6, rgbcolor = "1 0.25 0.1", rgbcolor2 = "1 0.75 0.4",
			explosiongenerator = "custom:laserhit-large-red" },
	},
	overrides = { radardistance = 2000 },
})
freeShots(deadeye)
units.cort4deadeye = T4.hero(deadeye, 2.2)

----------------------------------------------------------------------------------------------- 8 Karganeth
-- Karganeth, the Hydra (Epic Karganeth x1.8): Hydra Lock, Flak Canopy, Adaptive Plating, Hydra Unleashed.
local karganeth = T4.derive(T4.base("units/Scavengers/Bots/corkarganetht4.lua", "corkarganetht4"), {
	name = "cort4karganeth",
	value = 8,
	health = 20,
	damage = 1,
	range = 1.4, -- missiles 1050, AA 1470
	aoe = 1.5,
	scale = 1.8,
	speed = 0.8,
	footprint = 9,
	movementclass = "T4ATBOT9",
	weapons = {
		karg_shoulder = { reloadtime = 2 },
	},
})
-- anti-air only: its vtol damage is set here (the balance counts ground damage)
karganeth.weapondefs.karg_shoulder.damage = { vtol = 9000 }
freeShots(karganeth)
do
	local hydra = T4.missileWeapon({ name = "Hydra Micro-missile", damage = 1, aoe = 70, model = "corkbmissl1.s3o", velocity = 950,
		ceg = "custom:blank", cegtag = "missiletrailsmall-red", soundhit = "xplosml2", soundstart = "rocklit1",
		range = 2000, turnrate = 60000 })
	hydra.smoketrail = false
	hydra.customparams = { t4_ability = 1 }
	units.cort4karganeth = T4.hero(karganeth, 2.2, { hydra = hydra })
end

----------------------------------------------------------------------------------------------- 9 Cataphract
-- Cataphract, the Lancer (Sokolov x2): Lance Charge, Disruption, Phase Decoy, Lancer's Gauntlet.
local cataphract = T4.derive(T4.base("units/CorGantry/corsok.lua", "corsok"), {
	name = "cort4cataphract",
	value = 8,
	health = 20,
	damage = 1,
	range = 1.4, -- 1015
	aoe = 1.5,
	scale = 2.0,
	speed = 1.0,
	footprint = 8,
	movementclass = "T4HOVER8",
	weapons = {
		corsok_laser = { rgbcolor = "1 0.6 0.15", rgbcolor2 = "1 0.9 0.6", explosiongenerator = "custom:laserhit-large-red" },
	},
})
freeShots(cataphract)
units.cort4cataphract = T4.hero(cataphract, 2.2)

-- Phase Decoy: a hologram of the Cataphract (same model, no weapons, no wreck); HP set by the hero module
do
	local d = T4.deepcopy(units.cort4cataphract)
	d.weapondefs = nil
	d.weapons = nil
	d.maxthisunit = nil
	d.metalcost = 50
	d.energycost = 0
	d.buildtime = 10
	d.mass = 50
	d.health = 60000
	d.corpse = nil
	d.featuredefs = nil
	d.explodeas = "smallexplosiongeneric"
	d.selfdestructas = "smallexplosiongeneric"
	d.customparams.t4_hero = nil
	d.customparams.t4_fx = nil
	d.customparams.t4_alt_weapons = nil
	d.customparams.t4_summon = 1
	d.sightdistance = 400
	units.cort4cataphract_decoy = d
end

return units
