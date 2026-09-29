-- Custom T4 heroes (denysfast/bar-game): the design data shared by the hero gadget
-- (luarules/gadgets/unit_t4_heroes.lua), the hero UI widget (luaui/Widgets/gui_t4_heroes.lua)
-- and the unitdefs (units/*T4*/, gamedata/custom_t4.lua). See CUSTOM.md, section "T4 heroes".
--
-- A hero is unique per team, levels 1..99 from combat experience and spends one point per level - and metal -
-- on the branches of its upgrade window:
--   w<N>_<track>                     every weapon has its own tree of three tracks (H.weaponKinds)
--   plating / servos                 common chassis branches
--   a1 / a2                          two signature abilities, 3 ranks (levels 3 / 15 / 30)
--   ult                              the ultimate, 3 ranks (levels 20 / 45 / 70)
-- 99 points for 120+ ranks: a maxed hero still has to leave something out. Six inventory slots take items
-- (H.items) that drop from slain heroes.
--
-- Rank effects ("mods") of the abilities are summed over every learned rank:
--   damage, hp, armor, regen (share of max HP per second), speed, range, sight, radar       fractions
--   reload (fraction off the reload time), accuracy (fraction off the spread)                fractions
--   weaponDamage / weaponReload = { <weapon key> = fraction }, burst = { <weapon key> = extra shots }
--   swap = { weapon = <key>, to = <hero weapondef key>, every = N, other = <key>, scatter = R }   the highest
--          learned rank wins: every N-th projectile of that weapon is replaced by the hero weapondef (N = 1:
--          all of them, `other` replaces the rest), a salvo with `scatter` lands on random points within R
--          of the target instead of all on it
-- Abilities with code behind them are `kind` + per-rank arrays (see the gadget); `fx` names the CEG of a
-- self buff (effects/custom_t4_heroes.lua).

local H = {}

H.MAX_LEVEL = 99
H.DEATH_LEVELS = 5          -- a revived hero comes back this many levels lower
H.LEVEL_HP = 0.03           -- automatic growth per level above 1
H.LEVEL_DAMAGE = 0.03
-- experience, in units of the hero's own metal cost: reaching level L takes
-- XP_TOTAL * ((L - 1) / XP_REF) ^ XP_EXP (modoption hero_xp_mult divides the requirement).
-- v14: ten times v13 (5 costs for level 30), the curve simply continues to level 99 (~400 costs)
H.XP_TOTAL = 50.0
H.XP_REF = 29
H.XP_EXP = 1.7
H.XP_KILL = 0.25            -- the killer also gets this share of the victim's cost
H.XP_HERO_KILL = 0.25       -- a slain hero is worth this share of its cost more per 10 levels
H.XP_SHARE = 0.08           -- and every hero within XP_SHARE_RADIUS of a dying enemy this share
H.XP_SHARE_RADIUS = 1400
H.XP_STRUCTURE = 0.3        -- structures give this share of the experience units give
-- hero.xpRate scales everything a hero earns (long-range artillery farms bases from afar)
-- heroes regenerate REST_REGEN of max HP per second after REST_DELAY seconds without taking damage
H.REST_REGEN = 0.005
H.REST_DELAY = 10
-- revive: the dead hero is rebuilt at its foundry, level - DEATH_LEVELS, for
-- cost * (1 + REVIVE_COST_PER_LEVEL * new level) metal and energy, build time * (1 + REVIVE_TIME_PER_LEVEL * level)
H.REVIVE_COST_PER_LEVEL = 0.06
H.REVIVE_TIME_PER_LEVEL = 0.03
-- fountain: a hero near its own team's T4 foundry regains this share of max HP per second
H.FOUNTAIN_RADIUS = 1100
H.FOUNTAIN_REGEN = 0.02
-- AI heroes are driven by the hero gadget, not by the skirmish AI: they march with the strongest group
-- of their army (aiRole front: at its head, center: in it, back: behind it), fall back to the fountain
-- below AI_RETREAT_HP - or below AI_CAUTION_HP when the enemies around outweigh the allies
-- AI_DANGER times - and rejoin the army at AI_RETURN_HP
H.AI_RETREAT_HP = 0.35
H.AI_CAUTION_HP = 0.65
H.AI_DANGER = 1.6
H.AI_BURST = 0.3             -- or when it lost this share of its health within the last 5 seconds
H.AI_RETURN_HP = 0.9
H.AI_RETURN_HP_NO_FOUNTAIN = 0.7 -- no altar left to heal at: rejoin sooner
H.AI_ROLE_OFFSET = { front = 150, center = -100, back = -500 }
H.AI_ESCORT = 10000         -- the smallest army group (metal) a hero marches with; below it guards the altar
-- v15: an escort of army units taken from the skirmish AI walks with every AI hero and covers its retreat
H.AI_ESCORT_MIN = 6          -- units
H.AI_ESCORT_MAX = 15
H.AI_ESCORT_COST = 0.6       -- metal of the escort, share of the hero's cost (capped by a third of the army group)
H.AI_ESCORT_RADIUS = 1600    -- escorts are recruited this close to the hero
H.AI_FRONT_LEAD = 300        -- a hero never walks further than this ahead of its escort

-- v15: buying levels for metal (the Buy level button; the AI saves its overflow metal for it)
H.BUY_BASE = 0.6            -- a level costs cost * (BUY_BASE + BUY_PER_LEVEL * level) ...
H.BUY_PER_LEVEL = 0.05
H.BUY_COOLDOWN = 20         -- seconds between two bought levels of one hero
H.AI_BUY_MAX_LEVEL = 60     -- the AI buys levels up to this one (combat takes a hero further)
H.AI_BUY_SAVE = 0.25        -- the AI puts aside at most this share of its metal income ...
H.AI_BUY_FULL = 0.5         -- ... and only while its storage is fuller than this (metal that would overflow)
H.AI_BUY_INCOME = 100       -- ... and its metal income is at least this

-- level needed for a rank of a branch
local function reqLinear(rank) return rank * 2 - 1 end
local function reqServo(rank) return rank * 4 - 1 end
local function reqWeapon(rank) return (rank - 1) * 3 + 1 end
local ABILITY_REQ = { 3, 15, 30 }
local ULT_REQ = { 20, 45, 70 }
local function reqAbility(rank) return ABILITY_REQ[rank] or math.huge end
local function reqUlt(rank) return ULT_REQ[rank] or math.huge end
H.req = { linear = reqLinear, servo = reqServo, weapon = reqWeapon, ability = reqAbility, ult = reqUlt }

-- metal every rank costs on top of the talent point (paid from the team's storage when learned)
H.ABILITY_METAL = { 15000, 30000, 50000 }
H.ULT_METAL = { 40000, 70000, 100000 }
H.STAT_METAL = 1500          -- stat and weapon ranks: STAT_METAL * rank

H.branchOrder = { "plating", "servos", "a1", "a2", "ult" }
H.abilityKeys = { "a1", "a2", "ult" }
H.hotkeys = { a1 = "Q", a2 = "W", ult = "R" }

-- the common branches; `per` is one rank, the text is shown with the rank count
-- (v14: Arsenal is gone - every weapon has its own tree, see H.weaponKinds)
H.common = {
	plating = {
		name = "Plating", icon = "stat_plating", maxRank = 15, req = "linear",
		desc = "+8% max health and +0.02% health regeneration per second per rank",
		per = { hp = 0.08, regen = 0.0002 },
	},
	servos = {
		name = "Servos", icon = "stat_servos", maxRank = 10, req = "servo",
		desc = "+5% speed, +5% sight per rank",
		per = { speed = 0.05, sight = 0.05 },
	},
}

-- the data files live next to this one; each chunk gets H as `...` (the earlier parts already filled in)
local function part(path)
	local fn = assert(loadstring(VFS.LoadFile(path), path))
	return fn(H)
end
part("luarules/configs/t4_hero_weapons.lua")
part("luarules/configs/t4_hero_items.lua")
H.heroes = {}
H.order = {}
for _, path in ipairs({
	"luarules/configs/t4_hero_defs_t4.lua",
	"luarules/configs/t4_hero_defs_t2_arm.lua",
	"luarules/configs/t4_hero_defs_t2_cor.lua",
	"luarules/configs/t4_hero_defs_t2_leg.lua",
}) do
	local defs, order = part(path)
	for name, def in pairs(defs or {}) do
		H.heroes[name] = def
	end
	for _, name in ipairs(order or {}) do
		H.order[#H.order + 1] = name
	end
end

-- weapon branch keys: w<index>_<track>, e.g. w2_pierce
function H.weaponBranch(heroName, key)
	local hero = H.heroes[heroName]
	local wi, track = key:match("^w(%d+)_(%a+)$")
	if not hero or not wi then
		return nil
	end
	local w = hero.weapons and hero.weapons[tonumber(wi)]
	local t = H.tracks[track]
	if not w or not t then
		return nil
	end
	return {
		name = t.name, icon = t.icon, maxRank = H.WEAPON_RANKS, req = "weapon", weapon = tonumber(wi), track = track,
		desc = w.name .. " - " .. string.format(t.fmt, t.abs and t.per or math.floor(t.per * 100 + 0.5)) .. " per rank",
	}
end

-- every learnable key of a hero, in panel order
function H.allKeys(heroName)
	local hero = H.heroes[heroName]
	local out = {}
	for wi, w in ipairs(hero and hero.weapons or {}) do
		for _, track in ipairs(H.weaponKinds[w.kind].tracks) do
			out[#out + 1] = "w" .. wi .. "_" .. track
		end
	end
	for _, key in ipairs(H.branchOrder) do
		out[#out + 1] = key
	end
	return out
end

function H.branch(heroName, key)
	local hero = H.heroes[heroName]
	if not hero then
		return nil
	end
	return H.common[key] or hero[key] or H.weaponBranch(heroName, key)
end

function H.metalCost(heroName, key, rank)
	if key == "ult" then
		return H.ULT_METAL[rank] or 0
	elseif key == "a1" or key == "a2" then
		return H.ABILITY_METAL[rank] or 0
	end
	return H.STAT_METAL * rank
end

function H.weaponTier(rankSum)
	local tier = 1
	for i, start in ipairs(H.weaponTiers) do
		if rankSum >= start then
			tier = i
		end
	end
	return tier
end


function H.maxRank(heroName, key)
	local b = H.branch(heroName, key)
	if not b then
		return 0
	end
	return b.maxRank or 3
end

function H.reqLevel(heroName, key, rank)
	local b = H.branch(heroName, key)
	if not b then
		return math.huge
	end
	local req = b.req or (key == "ult" and "ult" or "ability")
	return H.req[req](rank)
end

-- cumulative experience (in own-cost units) to reach a level
function H.xpFor(level, mult)
	if level <= 1 then
		return 0
	end
	return H.XP_TOTAL * ((level - 1) / H.XP_REF) ^ H.XP_EXP / (mult or 1)
end

-- metal to buy the next level at `level` (v15): cost * (BUY_BASE + BUY_PER_LEVEL * level), and never less than
-- the metal of damage that level takes in combat (the experience between the two levels at hero_xp_mult 1).
-- Level 10 of a 100k hero: 134k, level 30: 297k, level 60: 485k; a 4k T2 hero: 5.4k / 11.9k / 19.4k. Nil at the top.
function H.levelPrice(heroName, level, cost)
	if level >= H.MAX_LEVEL then
		return nil
	end
	if not cost then
		local ud = UnitDefNames and UnitDefNames[heroName]
		cost = ud and (ud.metalCost or ud.metalcost) or 0
	end
	local combat = H.xpFor(level + 1) - H.xpFor(level)
	return math.floor(cost * math.max(H.BUY_BASE + H.BUY_PER_LEVEL * level, combat) / 100 + 0.5) * 100
end

return H
