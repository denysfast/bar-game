-- Custom T2 heroes, Legion (denysfast/bar-game, heroes v15): the T2 Hero Hall and ten heroes built from
-- Legion T2 bots and vehicles (models scaled 1.4-1.6, see tools/t4/build_models.py). Same hero system as
-- the T4 heroes (gamedata/custom_t4.lua T4.derive + T4.hero); design data in
-- luarules/configs/t4_hero_defs_t2_leg.lua. Lives under units/Legion/ so it only loads with the Legion faction.
local T4 = VFS.Include("gamedata/custom_t4.lua")
local FX = T4.FX

local units = {}

local BOTS = "units/Legion/Bots/T2 Bots/"
local VEH = "units/Legion/Vehicles/T2 Vehicles/"

local HEROES = {
	"legt2warden", "legt2pyre", "legt2longshot", "legt2harrier", "legt2scorch",
	"legt2reaper", "legt2gladius", "legt2vulcan", "legt2swarm", "legt2gorgon",
}

-- scale a yardmap string ("ooo eee ...") to a new footprint by nearest sampling
local function scaleYardmap(ym, fx, fz, nfx, nfz)
	local cells = {}
	for c in ym:gsub("%s", ""):gmatch(".") do
		cells[#cells + 1] = c
	end
	local rows = {}
	for r = 0, nfz - 1 do
		local sr = math.min(fz - 1, math.floor(r * fz / nfz))
		local row = {}
		for c = 0, nfx - 1 do
			local sc = math.min(fx - 1, math.floor(c * fx / nfx))
			row[#row + 1] = cells[sr * fx + sc + 1] or "o"
		end
		rows[#rows + 1] = table.concat(row)
	end
	return table.concat(rows, " ")
end

-- Legion T2 Hero Hall: the Advanced Bot Lab x1.3, one per team, builds and revives the ten T2 heroes and
-- heals them nearby (the hero gadget treats every *t2hall as a fountain)
local labBase = T4.base("units/Legion/Labs/legalab.lua", "legalab")
local hall = T4.foundry(labBase, {
	name = "legt2hall",
	value = 2.3,
	scale = 1.3,
	workertime = 3,
	buildoptions = HEROES,
})
hall.yardmap = scaleYardmap(labBase.yardmap, labBase.footprintx, labBase.footprintz, hall.footprintx, hall.footprintz)
hall.health = math.floor(labBase.health * 5)
hall.explodeas = "largeBuildingexplosiongeneric"
hall.selfdestructas = "largeBuildingexplosiongenericSelfd"
hall.customparams.techlevel = 2
hall.customparams.unitgroup = "builder"
units.legt2hall = hall

local function nova(dmg, aoe, scale)
	return T4.novaWeapon({ damage = dmg, aoe = aoe, ceg = FX.custom("newnuketac", scale), name = "Hero nova" })
end

---------------------------------------------------------------------------------------------- Warden
-- Warden, the Iron Phalanx (Phalanx x1.5): the shielded riot bot grown into a wall that walks.
local warden = T4.derive(T4.base(BOTS .. "legshot.lua", "legshot"), {
	name = "legt2warden",
	value = 6.4,
	health = 5,
	damage = 3,
	range = 1.25,
	aoe = 1.4,
	scale = 1.5,
	speed = 0.9,
	footprint = 3,
	movementclass = "BOT3",
})
warden.customparams.reactive_armor_health = 2000
units.legt2warden = T4.hero(warden, 1.6)

---------------------------------------------------------------------------------------------- Pyre
-- Pyre, the Incinerator (Incinerator x1.4): a sustained heavy heat ray that melts whole lines.
local pyre = T4.derive(T4.base(BOTS .. "leginc.lua", "leginc"), {
	name = "legt2pyre",
	value = 2.4,
	health = 2.6,
	damage = 1.9,
	range = 1.1,
	aoe = 1.3,
	scale = 1.4,
	speed = 1.1,
	footprint = 4,
	movementclass = "HBOT4",
})
units.legt2pyre = T4.hero(pyre, 1.5)

---------------------------------------------------------------------------------------------- Longshot
-- Longshot, the Arquebusier (Arquebus x1.5): the all-terrain railgun sniper.
local longshot = T4.derive(T4.base(BOTS .. "legsrail.lua", "legsrail"), {
	name = "legt2longshot",
	value = 4.8,
	health = 4.5,
	damage = 3.2,
	range = 1.25,
	aoe = 1.3,
	scale = 1.5,
	speed = 0.9,
	footprint = 6,
	movementclass = "HTBOT6",
})
units.legt2longshot = T4.hero(longshot, 1.5, {
	hero_spear = T4.weaponFrom(longshot.weapondefs.railgunt2, {
		damage = 3000, range = 1600, thickness = 6, laserflaresize = 12,
		name = "Piercing Rail", noexplode = true, energypershot = 0,
		ceg = FX.custom("genericshellexplosion-huge-lightning", 1.6),
	}),
	hero_nova = nova(5000, 320, 0.45),
})

---------------------------------------------------------------------------------------------- Harrier
-- Harrier, the Swift Blade (Hoplite x1.6): the raider that leads a pack of Hoplites.
local harrier = T4.derive(T4.base(BOTS .. "legstr.lua", "legstr"), {
	name = "legt2harrier",
	value = 7.3,
	health = 6,
	damage = 3.2,
	range = 1.15,
	aoe = 1.3,
	scale = 1.6,
	speed = 0.95,
	footprint = 4,
	movementclass = "HBOT4",
})
units.legt2harrier = T4.hero(harrier, 1.5)

---------------------------------------------------------------------------------------------- Scorch
-- Scorch, the Belcher (Belcher x1.5): lobbed napalm and a rain of burning meteors.
local scorch = T4.derive(T4.base(BOTS .. "legbart.lua", "legbart"), {
	name = "legt2scorch",
	value = 5.45,
	health = 6.5,
	damage = 3.3,
	range = 1.15,
	aoe = 1.35,
	scale = 1.5,
	speed = 0.9,
	footprint = 4,
	movementclass = "HBOT4",
})
do
	local cp = scorch.weapondefs.clusternapalm.customparams
	cp.area_onhit_damage = math.floor(cp.area_onhit_damage * 3.3)
	cp.area_onhit_range = math.floor(cp.area_onhit_range * 1.35)
end
units.legt2scorch = T4.hero(scorch, 1.6, {
	hero_meteor = (function()
		local w = T4.shellWeapon({
			damage = 900, aoe = 200, ceg = "custom:genericshellexplosion-large", cegtag = "burnflame",
			name = "Napalm meteor", rgb = "1 0.45 0.1", size = 9, soundhit = "flamhit1",
		})
		-- the meteors leave burning ground like the napalm shells
		w.customparams = {
			area_onhit_ceg = "fire-area-75-repeat", area_onhit_damageCeg = "burnflamexl-gen", area_onhit_resistance = "fire",
			area_onhit_damage = 150, area_onhit_range = 75, area_onhit_time = 5,
		}
		return w
	end)(),
	hero_nova = nova(4500, 360, 0.45),
})

---------------------------------------------------------------------------------------------- Reaper
-- Reaper, the Rocket Legate (Thanatos x1.5): salvo rockets from far behind the line.
local reaper = T4.derive(T4.base(BOTS .. "leghrk.lua", "leghrk"), {
	name = "legt2reaper",
	value = 5.07,
	health = 8,
	damage = 3,
	range = 1.2,
	aoe = 1.35,
	scale = 1.5,
	speed = 0.95,
	footprint = 4,
	movementclass = "HBOT4",
})
units.legt2reaper = T4.hero(reaper, 1.6, {
	hero_heavyrocket = T4.missileWeapon({
		damage = 700, aoe = 170, ceg = "custom:genericshellexplosion-large", cegtag = "missiletrailmedium",
		model = "legsmallrocket.s3o", name = "Legate rocket", soundhit = "rockhit3", soundstart = "rockhvy3", velocity = 800,
	}),
	hero_nova = nova(5000, 380, 0.45),
})

---------------------------------------------------------------------------------------------- Gladius
-- Gladius, the Arena Champion (Gladiator x1.5): burst plasma, a scutum shield and a champion's fury.
local gladius = T4.derive(T4.base(VEH .. "legaskirmtank.lua", "legaskirmtank"), {
	name = "legt2gladius",
	value = 7.1,
	health = 7,
	damage = 3.4,
	range = 1.1,
	aoe = 1.35,
	scale = 1.5,
	speed = 0.9,
	footprint = 4,
	movementclass = "HTANK4",
})
units.legt2gladius = T4.hero(gladius, 1.5)

---------------------------------------------------------------------------------------------- Vulcan
-- Vulcan, the Fireforged (Prometheus x1.4): the heat-ray assault tank that will not stay dead.
local vulcan = T4.derive(T4.base(VEH .. "legaheattank.lua", "legaheattank"), {
	name = "legt2vulcan",
	value = 3.84,
	health = 3.6,
	damage = 2.6,
	range = 1.15,
	aoe = 1.3,
	scale = 1.4,
	speed = 0.9,
	footprint = 4,
	movementclass = "HTANK4",
})
units.legt2vulcan = T4.hero(vulcan, 1.5, {
	hero_nova = nova(6000, 400, 0.45),
})

---------------------------------------------------------------------------------------------- Swarm
-- Swarm, the Hive Mother (Mantis x1.5): the drone carrier. Its targeting tower becomes an arc emitter: the
-- stock Mantis script never lets weapon 1 fire (AimPrimary returns 0, the weapon only picks targets for the
-- drones), so the hero runs scripts/Units/legt2swarm.cob - the same script with AimPrimary returning 1
-- (tools/t4/cob_aim_patch.py). The arc keeps the carrier customparams: the drones still take its target.
local swarmBase = T4.base(VEH .. "legvcarry.lua", "legvcarry")
local swarm = T4.derive(swarmBase, {
	name = "legt2swarm",
	value = 7.5,
	health = 9,
	damage = 1,
	range = 1,
	aoe = 1,
	scale = 1.5,
	speed = 1.0,
	footprint = 4,
	movementclass = "HTANK4",
})
swarm.script = "Units/legt2swarm.cob"
do
	local cp = T4.deepcopy(swarmBase.weapondefs.targeting.customparams)
	cp.maxunits = 8
	cp.startingdronecount = 4
	cp.spawnrate = 8
	cp.controlradius = 1000
	cp.engagementrange = 850
	-- drones are bought per spawn (metal/energy above), not from a stockpile the arc would need to fire
	cp.stockpilelimit = nil
	cp.stockpilemetal = nil
	cp.stockpileenergy = nil
	cp.dronesusestockpile = nil
	cp.spark_ceg = "genericshellexplosion-splash-lightning"
	cp.spark_forkdamage = "0.4"
	cp.spark_maxunits = "3"
	cp.spark_range = "90"
	swarm.weapondefs.targeting = {
		name = "Hive Arc Relay",
		weapontype = "LightningCannon",
		areaofeffect = 12,
		avoidfeature = false,
		beamttl = 1,
		burst = 6,
		burstrate = 0.05,
		craterareaofeffect = 0,
		craterboost = 0,
		cratermult = 0,
		duration = 1,
		edgeeffectiveness = 0.15,
		explosiongenerator = "custom:genericshellexplosion-medium-lightning2",
		firestarter = 30,
		impactonly = 1,
		impulsefactor = 0,
		intensity = 20,
		laserflaresize = 7,
		noselfdamage = true,
		range = 800,
		reloadtime = 1.6,
		rgbcolor = "0.55 1 0.45",
		soundhit = "xplomed3",
		soundhitwet = "sizzle",
		soundstart = "lghthvy1",
		soundtrigger = true,
		thickness = 2.2,
		turret = true,
		weaponvelocity = 400,
		customparams = cp,
		damage = { default = 60, vtol = 20 },
	}
end
units.legt2swarm = T4.hero(swarm, 1.5, {
	hero_heavyrocket = T4.missileWeapon({
		damage = 600, aoe = 120, ceg = "custom:genericshellexplosion-medium", cegtag = "missiletrailsmall",
		model = "legsmallrocket.s3o", name = "Hive seeker", soundhit = "rockhit3", soundstart = "rockhvy3", velocity = 900,
	}),
})
-- the visual tier copies of the arc must not look like carrier weapons to unit_carrier_spawner
for key, wd in pairs(units.legt2swarm.weapondefs) do
	if key ~= "targeting" and wd.customparams then
		wd.customparams.carried_unit = nil
	end
end

---------------------------------------------------------------------------------------------- Gorgon
-- Gorgon, the Stone Gaze (Medusa x1.4): painted-target homing rocket salvos, a slowing gaze, serpent arcs
-- and the Petrify pulse.
local gorgon = T4.derive(T4.base(VEH .. "legmed.lua", "legmed"), {
	name = "legt2gorgon",
	value = 3,
	health = 4,
	damage = 2.4,
	range = 1.15,
	aoe = 1.35,
	scale = 1.4,
	speed = 0.95,
	footprint = 4,
	movementclass = "HTANK4",
})
units.legt2gorgon = T4.hero(gorgon, 1.6, {
	hero_chain = T4.weaponFrom(swarm.weapondefs.targeting, {
		damage = 250, burst = 1, range = 450, name = "Serpent arc", rgbcolor = "0.4 1 0.6",
		customparams = {},
	}),
})

return units
