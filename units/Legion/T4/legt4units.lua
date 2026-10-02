-- Custom T4 heroes, Legion (denysfast/bar-game), v19 roster (doc/v19-heroes/roster_leg.md). Built from Legion T3,
-- Scavenger and T2 units, see gamedata/custom_t4.lua; balance rows T4.heroBalance, abilities
-- luarules/configs/heroes/leg.lua, behaviour luarules/heroes/legt4*.lua, gadget luarules/gadgets/unit_t4_heroes.lua.
-- Lives under units/Legion/ so it only loads when the Legion faction is enabled.
local T4 = VFS.Include("gamedata/custom_t4.lua")

local units = {}

-- the ten heroes, in the order of the altar's build menu
local ORDER = {
	"legt4helios", "legt4starfall", "legt4longinus", "legt4tempest", "legt4myrmidon",
	"legt4keres", "legt4mukade", "legt4charybdis", "legt4apollyon", "legt4medusa",
}

-- Apex Forge: the Legion hero altar (Experimental Gantry model x1.5)
units.legt4gant = T4.foundry(T4.base("units/Legion/Labs/leggant.lua", "leggant"), {
	name = "legt4gant",
	value = 8, -- v15: the altar costs 2x (metal, energy, build time); health and build power stay
	scale = 1.5,
	workertime = 12,
	buildoptions = ORDER,
})

-- drop a weapon (key, lowercase) from a derived unitdef: its slot and its weapondef
local function dropWeapon(ud, key)
	local keep = {}
	for _, w in ipairs(ud.weapons or {}) do
		if string.lower(w.def or "") ~= key then
			keep[#keep + 1] = w
		end
	end
	ud.weapons = keep
	if ud.weapondefs then
		ud.weapondefs[key] = nil
	end
end

-- 1. Helios, the Sunbringer (heat-ray mech x1.8): Heat stacks that ignite, Corona Flare, Sunspot, Sunstrike.
local helios = T4.derive(T4.base("units/Legion/T3/legeheatraymech.lua", "legeheatraymech"), {
	name = "legt4helios",
	value = 6.8,
	range = 1.75,
	aoe = 1.6,
	scale = 1.8,
	footprint = 11,
	movementclass = "T4BOT11",
})
units.legt4helios = T4.hero(helios, 2.2)

-- 2. Starfall, the Astronomer (ELRPC mech x1.6): orbital artillery ~7000; Constellation, Gravity Lens, Deep Sky
-- Eye, Starfall.
local starfall = T4.derive(T4.base("units/Legion/T3/legelrpcmech.lua", "legelrpcmech"), {
	name = "legt4starfall",
	value = 9.2,
	range = 2.25,
	aoe = 1.8,
	scale = 1.6,
	sight = 1.8,
	footprint = 11,
	movementclass = "T4BOT11",
	overrides = { radardistance = 4500 },
})
units.legt4starfall = T4.hero(starfall, 2.5)

-- 3. Longinus, the Spear (rail tank x1.8): the titan hunter. Sunder, Hunter's Mark, Phase Rail, Spear of Longinus.
local longinus = T4.derive(T4.base("units/Legion/T3/legerailtank.lua", "legerailtank"), {
	name = "legt4longinus",
	value = 9.2,
	range = 1.2,
	aoe = 1.5,
	scale = 1.8,
	footprint = 9,
	movementclass = "T4TANK9",
	weapons = {
		t3_rail_accelerator = { noexplode = true, reloadtime = 4 },
	},
})
units.legt4longinus = T4.hero(longinus, 2.2)

-- 4. Tempest, the Stormblade (shotgun mech x2): close-quarters storm. Momentum, Storm Charge, Storm Echoes, Eye of
-- the Storm.
local tempest = T4.derive(T4.base("units/Legion/T3/legeshotgunmech.lua", "legeshotgunmech"), {
	name = "legt4tempest",
	value = 8.4,
	range = 1.6,
	aoe = 1.6,
	scale = 2.0,
	footprint = 8,
	movementclass = "T4BOT8",
})
units.legt4tempest = T4.hero(tempest, 2.5)

-- 5. Myrmidon, the Hive Mother (all-terrain carrier mech x2): plasma artillery and a hive of heat-ray drones
-- (api.summon, not the stock carrier controller). Drone Bay, Repair Swarm, Sacrificial Dive, Hive Ascendant.
local myrmidon = T4.derive(T4.base("units/Legion/T3/legeallterrainmech.lua", "legeallterrainmech"), {
	name = "legt4myrmidon",
	value = 8,
	range = 1.8,
	aoe = 1.5,
	scale = 2.0,
	footprint = 9,
	movementclass = "T4TBOT9",
})
dropWeapon(myrmidon, "drone_controller")
units.legt4myrmidon = T4.hero(myrmidon, 2.2)

-- 6. Keres, the Death-Spirit (Keres riot tank x2.4): anti-swarm brawler. Soul Harvest, Death Grip, Devour,
-- Danse Macabre.
local keres = T4.derive(T4.base("units/Legion/T3/legkeres.lua", "legkeres"), {
	name = "legt4keres",
	value = 30,
	range = 1.6,
	aoe = 1.6,
	scale = 2.4,
	footprint = 9,
	movementclass = "T4TANK9",
})
units.legt4keres = T4.hero(keres, 2.2)

-- 7. Mukade, the Great Centipede (Legion centipede x2): burrowing assassin. Burrow, Venom Rails, Molting, Coil.
local mukade = T4.derive(T4.base("units/Scavengers/Bots/legpede.lua", "legpede"), {
	name = "legt4mukade",
	value = 15,
	range = 1.4,
	aoe = 1.5,
	scale = 2.0,
	footprint = 8,
	movementclass = "T4BOT8",
})
units.legt4mukade = T4.hero(mukade, 2.2)

-- 8. Charybdis, the Maelstrom (heavy hovertank x2.4): crowd control, stronger over water. Undertow, Waterspout,
-- Surge, Maw of the Deep.
local charybdis = T4.derive(T4.base("units/Legion/T3/legehovertank.lua", "legehovertank"), {
	name = "legt4charybdis",
	value = 60,
	range = 1.8,
	aoe = 1.6,
	scale = 2.4,
	footprint = 10,
	movementclass = "T4HOVER10",
	-- the sweepfire heat ray fires every frame for 1.8 s of its 3 s reload (one shot to T4.weaponDps): its share is
	-- set here so the real DPS on land is ~6000 heat ray + ~3000 rockets (+ depth charges on water), see heroBalance
	damage = 1,
	weapons = { heat_ray = { damage = 0.444 }, depthcharge = { damage = 0.444 } },
})
units.legt4charybdis = T4.hero(charybdis, 2.2)

-- 9. Apollyon, the Locust King (Scavenger weapons platform x2): suppression and siege. Spin-Up, Locust Swarm,
-- Siege Lockdown, Plague of Locusts.
local apollyon = T4.derive(T4.base("units/Scavengers/Vehicles/legapollyon.lua", "legapollyon"), {
	name = "legt4apollyon",
	value = 6,
	range = 1.5,
	aoe = 1.5,
	scale = 2.0,
	footprint = 9,
	movementclass = "T4TANK9",
})
-- the scavenger base unit's heap points at Units/cor6X6.s3o, which does not exist: the standard 6x6 heap
if apollyon.featuredefs and apollyon.featuredefs.heap then
	apollyon.featuredefs.heap.object = "Units/cor6X6A.s3o"
end
units.legt4apollyon = T4.hero(apollyon, 2.2)

-- 10. Medusa, the Gorgon (Medusa rocket tank x3): petrify control artillery. Serpent Bite, Gorgon's Gaze, Snake
-- Pit, Stone Garden. Its hexaburst starburst missiles keep their flight time over the longer range
-- (T4.scaleWeapon: velocity x sqrt(range), flight time x range / velocity).
local medusa = T4.derive(T4.base("units/Legion/Vehicles/T2 Vehicles/legmed.lua", "legmed"), {
	name = "legt4medusa",
	value = 60,
	range = 2.6,
	aoe = 1.8,
	scale = 3.0,
	footprint = 9,
	movementclass = "T4TANK9",
})
units.legt4medusa = T4.hero(medusa, 2.5)

---------------------------------------------------------------------------- summons (not buildable)

local function summonDef(ud, p)
	ud.objectname = "Units/T4/" .. p.name .. ".s3o"
	-- a tiny cost, not 0: the engine derives unit power from the cost (power 0 -> division-by-zero cautions)
	ud.metalcost = 1
	ud.energycost = 0
	ud.buildtime = 10
	ud.power = ud.power or 1
	ud.health = p.health
	ud.speed = p.speed or ud.speed
	ud.featuredefs = nil
	ud.corpse = nil
	ud.leavetracks = false
	ud.reclaimable = false
	ud.capturable = false
	ud.cantbetransported = true
	ud.collisionvolumescales = ud.collisionvolumescales and T4.scaleVec(ud.collisionvolumescales, p.scale) or nil
	ud.collisionvolumeoffsets = ud.collisionvolumeoffsets and T4.scaleVec(ud.collisionvolumeoffsets, p.scale) or nil
	ud.customparams = ud.customparams or {}
	ud.customparams.t4_summon = 1
	ud.customparams.subfolder = "T4"
	ud.customparams.nohealthbars = nil
	ud.customparams.drone = nil
	for _, wd in pairs(ud.weapondefs or {}) do
		local d = wd.damage and wd.damage.default or 0
		wd.damage = { default = d * p.damage, vtol = d * p.damage * 0.3 }
		wd.collidefriendly = false
		wd.avoidfriendly = false
		if p.range then
			wd.range = wd.range * p.range
		end
	end
	return ud
end

-- Myrmidon's hive drones (heavy drone x1.5): 5000 HP (x ability power), heat ray ~220 DPS (125 base x1.76)
units.legt4myrmdrone = summonDef(T4.base("units/Legion/Air/T2 Air/legheavydronesmall.lua", "legheavydronesmall"), {
	name = "legt4myrmdrone", health = 5000, speed = 220, scale = 1.5, damage = 1.76, range = 1.3,
})

-- swarm-mites of Hive Ascendant (legdrone x1.6): 900 HP, ~120 DPS (26.7 base x4.5), expire after 20 s
units.legt4myrmmite = summonDef(T4.base("units/Legion/Air/legdrone.lua", "legdrone"), {
	name = "legt4myrmmite", health = 900, scale = 1.6, damage = 4.5, range = 1.3,
})

-- an invisible line-of-sight anchor (Starfall's Deep Sky Eye and the areas of its long-range casts): real LOS, radar and
-- air LOS over a map point for a few seconds. Created / sized / removed by luarules/heroes/legt4starfall.lua
-- (Spring.SetUnitSensorRadius), neutral, not drawn, not selectable, no collision, no wreck.
do
	local eye = T4.base("units/Legion/Utilities/legeyes.lua", "legeyes")
	eye.metalcost, eye.energycost, eye.buildtime = 1, 0, 10 -- not 0: unit power derives from the cost
	eye.power = 1
	eye.health = 1000000
	eye.energyupkeep = 0
	eye.cloakcost = 0
	eye.initcloaked = false
	eye.sightdistance = 600
	eye.radardistance = 600
	eye.airsightdistance = 600
	eye.corpse = nil
	eye.featuredefs = nil
	eye.blocking = false
	eye.canselect = false
	eye.reclaimable = false
	eye.capturable = false
	eye.collisionvolumescales = "1 1 1"
	eye.explodeas = ""
	eye.selfdestructas = ""
	eye.customparams.t4_summon = 1
	eye.customparams.subfolder = "T4"
	eye.customparams.nohealthbars = 1
	units.legt4skyeye = eye
end

return units
