-- Custom heroes (denysfast/bar-game): weapon kinds, their upgrade tracks and perks. Included by
-- luarules/configs/t4_heroes.lua, which passes the shared table H. See CUSTOM.md, section "Heroes".
local H = ...

-- Weapon trees (v15): every real weapon of a hero levels on its own. A weapon kind has four tracks of
-- WEAPON_RANKS ranks each. A rank adds a FIXED amount, computed once from the weapon's base stats
-- (`pct` of the base value, rounded to a readable number) and shown in units: rank 5 = 5x the amount.
-- Mechanics (`stat`) of a track:
--   damage     +N damage per shot (per pellet / per rocket)              pct of the base shot damage
--   range      +N elmos of range                                        pct of the base range
--   reload     -N seconds of reload (never below 25% of the base)       pct of the base reload
--   splash     +N elmos of blast radius                                 pct of the base area of effect
--   pellets    +N projectiles per shot                                  `per` (absolute)
--   salvo      +N shots per salvo                                       pct of the base salvo (at least 1)
--   pierce     +N damage to the enemies on a `len` line behind the target, per shot
--   burn       +N fire damage over 3 s on the target, per shot
--   discharge  +N paralysis on the target, per shot
--   chain      +N damage arcing to `jumps` enemies within `radius` of the target, per shot
--   blast      +N damage to the enemies within `radius` of the target, per shot
--   crit       +N% chance of `mult` x damage                            `per` (absolute chance)
-- pierce/burn/discharge/chain/blast are pct of the base shot damage and are dealt per shot, split over
-- the hits of a shot (a beam hits many times). Paralyzer weapons (EMP) arc and blast paralysis.
--
-- Perks: a weapon whose rank sum reaches `at` gains the perk: one more mechanic of the same kind (amount =
-- `pct` of the base shot damage) plus a hit effect (CEG from effects/custom_t4_weapons.lua).
--
-- Visual growth: the weapon draws its shots with copy <key>_s<N> (gamedata/custom_t4.lua T4.hero) once its
-- rank sum reaches H.weaponSteps[N]: thicker beams, bigger shells, flashes, trails and blasts - eight small
-- steps up to x2.
H.WEAPON_RANKS = 10
H.weaponSteps = { 3, 7, 11, 15, 20, 25, 31, 37 }
H.STEP_GROWTH = 0.125 -- visual size x(1 + STEP_GROWTH * step)
H.PERKS_AT = { 10, 20, 30 }

-- rounding of a per-rank amount to a readable number
local function nice(v, minimum)
	local a = math.abs(v)
	local step
	if a >= 5000 then
		step = 100
	elseif a >= 1000 then
		step = 50
	elseif a >= 200 then
		step = 10
	elseif a >= 50 then
		step = 5
	elseif a >= 10 then
		step = 1
	elseif a >= 1 then
		step = 0.5
	else
		step = 0.05
	end
	local r = math.floor(a / step + 0.5) * step
	return math.max(minimum or 0, r)
end
H.nice = nice

local S = {
	damage = { base = "damage", round = 1 },
	range = { base = "range", min = 10 },
	reload = { base = "reload" },
	splash = { base = "aoe", min = 4 },
	pellets = {},
	salvo = { base = "burst" },
	pierce = { base = "damage" },
	burn = { base = "damage" },
	discharge = { base = "damage" },
	chain = { base = "damage" },
	blast = { base = "damage" },
	crit = {},
}
H.trackStats = S

-- t(name, stat, pct, extra fields)
local function t(name, stat, pct, o)
	o = o or {}
	o.name, o.stat, o.pct = name, stat, pct
	return o
end
local function perk(at, name, stat, pct, fx, o)
	o = o or {}
	o.at, o.name, o.stat, o.pct, o.fx = at, name, stat, pct, fx
	return o
end

-- kind -> { label, tracks = { id, ... }, track = { id = def }, perks = { ... } }
-- Track ids are unique within a kind; the branch key of a track is w<weapon index>_<id>.
H.weaponKinds = {
	beam = { label = "Laser Beam", tracks = { "damage", "range", "pierce" }, track = {
		damage = t("Focusing Lens", "damage", 0.06),
		range = t("Long Emitter", "range", 0.05),
		pierce = t("Burn-through", "pierce", 0.10, { len = 600 }),
		reload = t("Capacitor Bank", "reload", 0.05),
	}, perks = {
		perk(10, "Scorch Marks", "burn", 0.05, "hero-wfx-scorch"),
		perk(20, "Overcharged Lens", "pierce", 0.06, "hero-wfx-sparks-gold", { len = 600 }),
		perk(30, "Prism Split", "chain", 0.08, "hero-wfx-arc", { jumps = 1, radius = 300 }),
	} },
	heatray = { label = "Heat Ray", tracks = { "damage", "range", "burn", "blast" }, track = {
		damage = t("Thermal Core", "damage", 0.06),
		range = t("Beam Collimator", "range", 0.05),
		burn = t("Scorch", "burn", 0.12),
		blast = t("Heat Bloom", "blast", 0.08, { radius = 140 }),
	}, perks = {
		perk(10, "Melting Point", "burn", 0.05, "hero-wfx-scorch"),
		perk(20, "Heat Haze", "blast", 0.05, "hero-wfx-heat", { radius = 160 }),
		perk(30, "Solar Lance", "pierce", 0.08, "hero-wfx-sparks-gold", { len = 500 }),
	} },
	shotgun = { label = "Scatter Gun", tracks = { "damage", "pellets", "splash" }, track = {
		damage = t("Heavy Shot", "damage", 0.06, { unit = "damage per pellet" }),
		pellets = t("Extra Pellets", "pellets", nil, { per = 1 }),
		splash = t("Blast Shells", "splash", 0.12),
		reload = t("Pump Action", "reload", 0.05),
	}, perks = {
		perk(10, "Shrapnel", "blast", 0.04, "hero-wfx-sparks-gold", { radius = 120 }),
		perk(20, "Dragon's Breath", "burn", 0.06, "hero-wfx-scorch"),
		perk(30, "Stagger Rounds", "discharge", 0.10, "hero-wfx-static"),
	} },
	cannon = { label = "Cannon", tracks = { "damage", "splash", "range" }, track = {
		damage = t("Heavy Shells", "damage", 0.06),
		splash = t("High Explosive", "splash", 0.12),
		reload = t("Autoloader", "reload", 0.05),
		range = t("Long Barrel", "range", 0.05),
	}, perks = {
		perk(10, "Shockwave", "blast", 0.05, "hero-wfx-shock", { radius = 160 }),
		perk(20, "Incendiary Filler", "burn", 0.05, "hero-wfx-scorch"),
		perk(30, "Sabot Core", "pierce", 0.08, "hero-wfx-sparks-gold", { len = 400 }),
	} },
	plasma = { label = "Plasma Gun", tracks = { "damage", "splash", "burn" }, track = {
		damage = t("Plasma Density", "damage", 0.06),
		splash = t("Plasma Bloom", "splash", 0.12),
		burn = t("Ionized Residue", "burn", 0.10),
		reload = t("Magnetic Chamber", "reload", 0.05),
	}, perks = {
		perk(10, "Plasma Splash", "blast", 0.05, "hero-wfx-plasma", { radius = 160 }),
		perk(20, "Ion Storm", "discharge", 0.08, "hero-wfx-static"),
		perk(30, "Star Core", "chain", 0.06, "hero-wfx-arc", { jumps = 2, radius = 320 }),
	} },
	artillery = { label = "Artillery", tracks = { "damage", "range", "splash" }, track = {
		damage = t("Heavy Warheads", "damage", 0.06),
		range = t("Extended Charge", "range", 0.04),
		splash = t("Airburst Fuse", "splash", 0.12),
		reload = t("Loading Crane", "reload", 0.05),
	}, perks = {
		perk(10, "Cluster Shells", "blast", 0.06, "hero-wfx-shock", { radius = 220 }),
		perk(20, "Firestorm", "burn", 0.06, "hero-wfx-scorch"),
		perk(30, "Seismic Charge", "discharge", 0.08, "hero-wfx-static"),
	} },
	mortar = { label = "Mortar", tracks = { "damage", "splash", "burn", "range" }, track = {
		damage = t("Heavy Bombs", "damage", 0.06),
		splash = t("Wide Blast", "splash", 0.12),
		burn = t("Incendiary Filler", "burn", 0.10),
		range = t("Propellant", "range", 0.05),
	}, perks = {
		perk(10, "Fragmentation", "blast", 0.05, "hero-wfx-shock", { radius = 180 }),
		perk(20, "Napalm Pool", "burn", 0.06, "hero-wfx-scorch"),
		perk(30, "Concussion", "discharge", 0.08, "hero-wfx-static"),
	} },
	rockets = { label = "Rocket Salvo", tracks = { "damage", "salvo", "splash" }, track = {
		damage = t("Warheads", "damage", 0.06, { unit = "damage per rocket" }),
		salvo = t("Extra Tubes", "salvo", 0.12),
		splash = t("Fragmentation", "splash", 0.12),
		reload = t("Rack Reloader", "reload", 0.05),
	}, perks = {
		perk(10, "Thermobaric", "burn", 0.05, "hero-wfx-scorch"),
		perk(20, "Cluster Rockets", "blast", 0.05, "hero-wfx-shock", { radius = 160 }),
		perk(30, "Shock Warheads", "discharge", 0.06, "hero-wfx-static"),
	} },
	missiles = { label = "Guided Missiles", tracks = { "damage", "range", "blast" }, track = {
		damage = t("Shaped Charge", "damage", 0.06, { unit = "damage per missile" }),
		range = t("Booster Stage", "range", 0.05),
		blast = t("Proximity Fuse", "blast", 0.08, { radius = 160 }),
		reload = t("Launch Rails", "reload", 0.05),
	}, perks = {
		perk(10, "Tandem Warhead", "pierce", 0.06, "hero-wfx-sparks-gold", { len = 300 }),
		perk(20, "EMP Payload", "discharge", 0.08, "hero-wfx-static"),
		perk(30, "Seeker Swarm", "chain", 0.06, "hero-wfx-arc", { jumps = 2, radius = 350 }),
	} },
	lightning = { label = "Lightning", tracks = { "damage", "range", "chain", "discharge" }, track = {
		damage = t("Overcharge", "damage", 0.06),
		range = t("Arc Reach", "range", 0.05),
		chain = t("Forked Lightning", "chain", 0.10, { jumps = 2, radius = 350 }),
		discharge = t("Static Discharge", "discharge", 0.15),
	}, perks = {
		perk(10, "Ionize", "discharge", 0.06, "hero-wfx-static"),
		perk(20, "Thunderclap", "blast", 0.05, "hero-wfx-thunder", { radius = 180 }),
		perk(30, "Storm Arc", "chain", 0.08, "hero-wfx-arc", { jumps = 3, radius = 400 }),
	} },
	flame = { label = "Flamethrower", tracks = { "damage", "range", "burn", "splash" }, track = {
		damage = t("Hotter Fuel", "damage", 0.06),
		range = t("Pressurized Tank", "range", 0.05),
		burn = t("Napalm", "burn", 0.12),
		splash = t("Wide Nozzle", "splash", 0.12),
	}, perks = {
		perk(10, "Sticky Gel", "burn", 0.05, "hero-wfx-scorch"),
		perk(20, "Firestorm", "blast", 0.04, "hero-wfx-heat", { radius = 140 }),
		perk(30, "Hellfire Jet", "pierce", 0.06, "hero-wfx-scorch", { len = 300 }),
	} },
	rail = { label = "Railgun", tracks = { "damage", "range", "pierce" }, track = {
		damage = t("Coil Strength", "damage", 0.06),
		range = t("Barrel Extension", "range", 0.05),
		pierce = t("Penetrator", "pierce", 0.10, { len = 1200 }),
		reload = t("Capacitor Cycling", "reload", 0.05),
	}, perks = {
		perk(10, "Shockwave Trail", "blast", 0.04, "hero-wfx-shock", { radius = 140 }),
		perk(20, "Ionized Slug", "discharge", 0.06, "hero-wfx-static"),
		perk(30, "Magnetic Lance", "pierce", 0.06, "hero-wfx-sparks-blue", { len = 1200 }),
	} },
	sniper = { label = "Sniper Rifle", tracks = { "damage", "range", "crit" }, track = {
		damage = t("Match Rounds", "damage", 0.06),
		range = t("Scope", "range", 0.05),
		crit = t("Headshot", "crit", nil, { per = 0.03, mult = 3 }),
		reload = t("Bolt Action", "reload", 0.05),
	}, perks = {
		perk(10, "Armor Piercer", "pierce", 0.06, "hero-wfx-sparks-gold", { len = 400 }),
		perk(20, "Hollow Point", "burn", 0.06, "hero-wfx-scorch"),
		perk(30, "Deadeye", "crit", nil, "hero-wfx-crit", { per = 0.10, mult = 3 }),
	} },
	emp = { label = "EMP Launcher", tracks = { "damage", "range", "splash", "chain" }, track = {
		damage = t("Pulse Charge", "damage", 0.06),
		range = t("Long Relay", "range", 0.05),
		splash = t("Wide Pulse", "splash", 0.12),
		chain = t("EMP Arc", "chain", 0.10, { jumps = 2, radius = 350 }),
	}, perks = {
		perk(10, "Overload", "discharge", 0.06, "hero-wfx-static"),
		perk(20, "Static Web", "chain", 0.05, "hero-wfx-arc", { jumps = 2, radius = 350 }),
		perk(30, "Blackout", "blast", 0.05, "hero-wfx-emp", { radius = 220 }),
	} },
	flak = { label = "Flak", tracks = { "damage", "splash", "range" }, track = {
		damage = t("Shrapnel Load", "damage", 0.06),
		splash = t("Burst Radius", "splash", 0.12),
		reload = t("Rapid Feed", "reload", 0.05),
		range = t("High Velocity", "range", 0.05),
	}, perks = {
		perk(10, "Fragment Cloud", "blast", 0.04, "hero-wfx-sparks-gold", { radius = 140 }),
		perk(20, "Proximity Burst", "chain", 0.04, "hero-wfx-arc", { jumps = 2, radius = 300 }),
		perk(30, "Incendiary Flak", "burn", 0.05, "hero-wfx-scorch"),
	} },
}
H.weaponKindOrder = { "beam", "heatray", "shotgun", "cannon", "plasma", "artillery", "mortar", "rockets", "missiles",
	"lightning", "flame", "rail", "sniper", "emp", "flak" }

for kind, k in pairs(H.weaponKinds) do
	k.icon = "wpn_" .. kind
	for id, tr in pairs(k.track) do
		tr.id = id
		tr.icon = "trk_" .. kind .. "_" .. id
	end
end

-- the track definition of a kind
function H.weaponTrack(kind, id)
	local k = H.weaponKinds[kind]
	return k and k.track[id]
end

---------------------------------------------------------------------------- base stats and amounts

local baseCache = {}
-- base stats of weapon `wi` of a hero, from its first weapondef key (LuaRules and LuaUI; WeaponDefNames needed)
function H.weaponBase(heroName, wi)
	local ck = heroName .. "#" .. wi
	if baseCache[ck] then
		return baseCache[ck]
	end
	local hero = H.heroes[heroName]
	local w = hero and hero.weapons and hero.weapons[wi]
	local wd = w and WeaponDefNames and WeaponDefNames[heroName .. "_" .. w.keys[1]]
	if not wd then
		return nil
	end
	local dmg = wd.damages and wd.damages[0] or 0
	if dmg <= 1 and wd.damages then
		for i = 1, #wd.damages do
			dmg = math.max(dmg, wd.damages[i] or 0)
		end
	end
	local b = {
		damage = dmg, range = wd.range, reload = wd.reload, aoe = wd.damageAreaOfEffect or 0,
		burst = wd.salvoSize or 1, projectiles = wd.projectiles or 1, paralyzer = wd.paralyzer, type = wd.type,
	}
	baseCache[ck] = b
	return b
end

-- the fixed amount one rank of a track (or a perk) adds, from the weapon's base stats
function H.trackAmount(tr, base)
	if not tr or not base then
		return 0
	end
	local st = tr.stat
	if tr.per then
		return tr.per
	end
	if st == "salvo" then
		return math.max(1, math.floor((base.burst or 1) * tr.pct + 0.5))
	end
	if st == "reload" then
		return math.max(0.01, math.floor((base.reload or 1) * tr.pct * 100 + 0.5) / 100)
	end
	if st == "splash" and (base.aoe or 0) < 8 then
		return 4
	end
	local src = S[st] and S[st].base or "damage"
	return nice((base[src] or 0) * (tr.pct or 0), S[st] and S[st].min)
end

local function num(v)
	if v >= 100 or v == math.floor(v) then
		return string.format("%d", math.floor(v + 0.5))
	end
	return string.format("%.1f", v)
end
H.fmtAmount = num

-- the effect of `amount` of a track in words, e.g. "+180 damage per shot"; `base` names paralysis
function H.trackText(tr, amount, base)
	local st = tr.stat
	local para = base and base.paralyzer
	if st == "damage" then
		return "+" .. num(amount) .. " " .. (tr.unit or (para and "paralysis per shot" or "damage per shot"))
	elseif st == "range" then
		return "+" .. num(amount) .. " range"
	elseif st == "reload" then
		return string.format("-%.2f s reload", amount)
	elseif st == "splash" then
		return "+" .. num(amount) .. " blast radius"
	elseif st == "pellets" then
		return "+" .. num(amount) .. (amount == 1 and " pellet" or " pellets")
	elseif st == "salvo" then
		return "+" .. num(amount) .. " per salvo"
	elseif st == "pierce" then
		return "+" .. num(amount) .. " damage along " .. (tr.len or 600) .. " behind the target"
	elseif st == "burn" then
		return "+" .. num(amount) .. " fire damage over 3 s"
	elseif st == "discharge" then
		return "+" .. num(amount) .. " paralysis on the target"
	elseif st == "chain" then
		return "+" .. num(amount) .. (para and " paralysis" or " damage") .. " arcing to " .. (tr.jumps or 1) .. " more"
	elseif st == "blast" then
		return "+" .. num(amount) .. (para and " paralysis" or " damage") .. " within " .. (tr.radius or 150) .. " of the target"
	elseif st == "crit" then
		return string.format("+%d%% chance of x%d damage", math.floor(amount * 100 + 0.5), tr.mult or 2)
	end
	return "+" .. num(amount)
end

-- a short form of a track's total for the upgrade window, e.g. "+1590 dmg"
local SHORT = { damage = "dmg", range = "range", splash = "radius", pellets = "pellets", salvo = "salvo", pierce = "line",
	burn = "burn", discharge = "para", chain = "arc", blast = "blast" }
function H.trackShort(tr, total)
	local st = tr.stat
	if total <= 0 then
		return ""
	elseif st == "reload" then
		return string.format("-%.2f s", total)
	elseif st == "crit" then
		return string.format("%d%% x%d", math.floor(total * 100 + 0.5), tr.mult or 2)
	end
	local v = total >= 10000 and string.format("%.1fk", total / 1000) or num(total)
	return "+" .. v .. " " .. (SHORT[st] or "")
end

-- the visual step (0 .. #H.weaponSteps) of a weapon rank sum
function H.weaponStep(rankSum)
	local s = 0
	for i, at in ipairs(H.weaponSteps) do
		if rankSum >= at then
			s = i
		end
	end
	return s
end
