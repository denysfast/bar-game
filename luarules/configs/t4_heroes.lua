-- Custom T4 heroes (denysfast/bar-game), v19: the design data shared by the hero gadget
-- (luarules/gadgets/unit_t4_heroes.lua), the hero UI, the unitdefs (gamedata/custom_t4.lua T4.hero) and the items
-- gadget. Spec: doc/v19-heroes/SPEC.md; CUSTOM.md, section "T4 heroes".
--
-- A hero levels 1..H.MAX_LEVEL from combat (or bought levels) and gets one point per level (level 1 = 1 point).
-- A point - plus metal from the team storage - buys one rank of a branch:
--   a1 / a2 / a3        three abilities, 10 ranks each; rank r needs level  r == 1 and 1 or 3 * (r - 1)  (1, 3, 6 .. 27)
--   ult                 the ultimate, 10 ranks; rank r needs level 10 * r (10 .. 100)
--   vit mob dmg rng imp the five stats every hero shares, 15 ranks each; rank r needs level r
-- 4 x 10 + 5 x 15 = 115 ranks for 100 points: a maxed hero still leaves something out.
-- Stats apply to ALL weapons of the hero at once; there are no per-weapon trees any more (v14-v18).
--
-- Abilities: luarules/configs/heroes/<faction>.lua (arm, cor, leg) - one file per faction, gets H as `...` and
-- returns `defs, order`. Behaviour code of a hero (optional): luarules/heroes/<heroname>.lua, loaded by the gadget
-- (see the module API at the top of the gadget). Ability values per rank: a number, a 10-array or H.lin(a, b).

local H = {}

H.MAX_LEVEL = 100
H.DEATH_LEVELS = 5          -- a revived hero comes back this many levels lower
H.LEVEL_HP = 0.03           -- automatic growth per level above 1, shares of the base
H.LEVEL_DAMAGE = 0.015      -- v19: was 0.03
-- experience, in units of the hero's own metal cost: reaching level L takes
-- XP_TOTAL * ((L - 1) / XP_REF) ^ XP_EXP (modoption hero_xp_mult divides the requirement): level 30 = 50 costs, 100 = ~400
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
-- revive: the dead hero is rebuilt at its altar, level - DEATH_LEVELS, for
-- cost * (1 + REVIVE_COST_PER_LEVEL * new level) metal and energy, build time * (1 + REVIVE_TIME_PER_LEVEL * level)
H.REVIVE_COST_PER_LEVEL = 0.06
H.REVIVE_TIME_PER_LEVEL = 0.03
-- fountain: a hero near its own team's altar regains this share of max HP per second
H.FOUNTAIN_RADIUS = 1100
H.FOUNTAIN_REGEN = 0.02

-- v19 hero cap (SPEC section 3): at most MAX_HEROES per team, alive or dead (a dead hero keeps its slot until it is
-- revived), each hero type once. Slot 1 comes with the altar, slot N+1 with altar upgrade N (a command on the altar:
-- paid at once, `time` seconds of research during which the altar does not build). Losing the altar keeps them.
H.MAX_HEROES = 3
H.SLOT_UPGRADES = {
	{ name = "Altar Upgrade I", metal = 100000, energy = 1000000, time = 45 },
	{ name = "Altar Upgrade II", metal = 200000, energy = 2000000, time = 45 },
}

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
H.AI_ESCORT_MIN = 12
H.AI_ESCORT_MAX = 30
H.AI_ESCORT_COST = 1.5       -- metal of the escort, share of the hero's cost (capped by H.AI_ESCORT_GROUP of the army group)
H.AI_ESCORT_GROUP = 0.5
H.AI_ESCORT_RADIUS = 2200    -- escorts are recruited this close to the hero
H.AI_FRONT_LEAD = 300        -- a hero never walks further than this ahead of its escort
-- the order an AI hero learns its stats in, by role (weights: the stat with the lowest rank / weight goes next;
-- the ultimate and the abilities always come first)
H.AI_STAT_WEIGHTS = {
	front = { vit = 3, dmg = 2.5, imp = 1.5, mob = 1, rng = 0.7 },
	center = { dmg = 3, vit = 2, rng = 1.5, imp = 1.5, mob = 1 },
	back = { rng = 3, dmg = 2.5, imp = 1.5, vit = 1, mob = 0.7 },
}

-- buying levels for metal (the Buy level button; the AI saves its overflow metal for it)
H.BUY_BASE = 0.6            -- a level costs cost * (BUY_BASE + BUY_PER_LEVEL * level) ...
H.BUY_PER_LEVEL = 0.05
H.BUY_COOLDOWN = 20         -- seconds between two bought levels of one hero
H.AI_BUY_COOLDOWN = 8
H.AI_BUY_DISCOUNT = 0.75    -- the AI pays a quarter of the price
H.AI_BUY_MAX_LEVEL = 80     -- the AI buys levels up to this one (combat takes a hero further)
H.AI_BUY_SAVE = 0.4         -- the AI puts aside at most this share of its metal income ...
H.AI_BUY_FULL = 0.3         -- ... and only while its storage is fuller than this (metal that would overflow)
H.AI_BUY_INCOME = 60        -- ... and its metal income is at least this

---------------------------------------------------------------------------- branches

H.ABILITY_RANKS = 10
H.STAT_RANKS = 15
H.abilityKeys = { "a1", "a2", "a3", "ult" }
H.statKeys = { "vit", "mob", "dmg", "rng", "imp" }
H.branchOrder = { "a1", "a2", "a3", "ult", "vit", "mob", "dmg", "rng", "imp" }
H.hotkeys = { a1 = "Q", a2 = "W", a3 = "E", ult = "R" }
H.isAbility = { a1 = true, a2 = true, a3 = true, ult = true }
H.isStat = { vit = true, mob = true, dmg = true, rng = true, imp = true }

-- level needed for rank r of a branch
function H.reqAbility(r)
	return r == 1 and 1 or 3 * (r - 1)
end
function H.reqUlt(r)
	return 10 * r
end
function H.reqStat(r)
	return r
end

-- metal every rank costs on top of the point (paid from the team's storage when learned)
H.ABILITY_METAL = 5000
H.ULT_METAL = 12000
H.STAT_METAL = 2500

-- the five stats (SPEC section 2). Per rank, shares of the hero's BASE stat (the UI shows them in units):
--   hp / regen: of the base health (regen per second), speed / sight: of the base speed / sight,
--   damage / range / splash (area of effect) / pierce: fractions, all weapons
-- Penetration (pierce): that share of a hit's damage also hits the enemies on a line behind the target
-- (H.PIERCE_LENGTH * the hero's fx scale long).
H.stats = {
	vit = { name = "Vitality", icon = "stat_vit", hp = 0.05, regen = 0.00025,
		desc = "Health and regeneration" },
	mob = { name = "Mobility", icon = "stat_mob", speed = 0.03, sight = 0.04,
		desc = "Speed and vision" },
	dmg = { name = "Firepower", icon = "stat_dmg", damage = 0.05,
		desc = "Damage of all weapons" },
	rng = { name = "Reach", icon = "stat_rng", range = 0.03,
		desc = "Range of all weapons" },
	imp = { name = "Impact", icon = "stat_imp", splash = 0.06, pierce = 0.03,
		desc = "Splash radius and penetration of all weapons" },
}
H.PIERCE_LENGTH = 600

---------------------------------------------------------------------------- ability values

-- rank values a .. b over the 10 ranks (rank 1 = a, rank 10 = b, linear); `step` rounds them (e.g. 1, 50)
function H.lin(a, b, step)
	local out = {}
	for r = 1, H.ABILITY_RANKS do
		local v = a + (b - a) * (r - 1) / (H.ABILITY_RANKS - 1)
		if step then
			v = math.floor(v / step + 0.5) * step
		end
		out[r] = v
	end
	return out
end

-- a per-rank value: a number (every rank), an array (rank r; past the end the last one), or nil
function H.val(v, r)
	if type(v) == "table" then
		return v[r] or v[#v]
	end
	return v
end

-- ability power (damage / healing / absorb of abilities): ABILITY_POWER_BASE, +ABILITY_POWER_PER_LEVEL per level
H.ABILITY_POWER_BASE = 1.0 -- v19 integration: roster anchors are at power 1 (L100 = 1.99)
H.ABILITY_POWER_PER_LEVEL = 0.01

-- text of an ability rank: `text` is a function(r, H, b), an array of 10 strings, or nil (the description)
-- H.textf("{radius} radius, {rate} HP/s") builds such a function from the rank values of the ability's fields
-- ({field%} = percent of a fraction, {field.1} = one decimal)
function H.textf(template)
	return function(r, _, b)
		return (template:gsub("{([%w_]+)([%%%.]?%d?)}", function(field, fmt)
			local v = b and H.val(b[field], r)
			if type(v) ~= "number" then
				return "?"
			end
			if fmt == "%" then
				return string.format("%d%%", math.floor(v * 100 + 0.5))
			elseif fmt:sub(1, 1) == "." then
				return string.format("%." .. (tonumber(fmt:sub(2)) or 1) .. "f", v)
			end
			if math.abs(v) >= 100 or v == math.floor(v) then
				return string.format("%d", math.floor(v + 0.5))
			end
			return string.format("%.1f", v)
		end))
	end
end

-- the data files live next to this one; each chunk gets H as `...` (the earlier parts already filled in)
local function part(path)
	local fn = assert(loadstring(VFS.LoadFile(path), path))
	return fn(H)
end
part("luarules/configs/t4_hero_weapons.lua")

H.heroes = {}
H.order = {}
H.factions = { "arm", "cor", "leg" }
for _, faction in ipairs(H.factions) do
	local path = "luarules/configs/heroes/" .. faction .. ".lua"
	if VFS.FileExists(path) then
		local defs, order = part(path)
		for name, def in pairs(defs or {}) do
			def.name = name
			def.faction = faction
			H.heroes[name] = def
		end
		for _, name in ipairs(order or {}) do
			H.order[#H.order + 1] = name
		end
	end
end
-- behaviour module of a hero: luarules/heroes/<name>.lua unless the def names another (`module = path | false`)
function H.modulePath(heroName)
	local hero = H.heroes[heroName]
	if not hero or hero.module == false then
		return nil
	end
	return hero.module or ("luarules/heroes/" .. heroName .. ".lua")
end

---------------------------------------------------------------------------- base stats and branches

-- base stats of a hero unitdef (LuaRules and LuaUI; UnitDefNames needed)
local heroBaseCache = {}
function H.heroBase(heroName)
	if heroBaseCache[heroName] then
		return heroBaseCache[heroName]
	end
	local ud = UnitDefNames and UnitDefNames[heroName]
	if not ud then
		return nil
	end
	local b = { health = ud.health, speed = ud.speed, sight = ud.losRadius or ud.sightDistance or 0,
		radar = ud.radarDistance or ud.radarRadius or 0, cost = ud.metalCost }
	heroBaseCache[heroName] = b
	return b
end

-- what `ranks` ranks of a stat add, in units: { hp, regen (HP/s), speed, sight, damage, range, splash, pierce }
-- (damage / range / splash / pierce stay fractions)
function H.statAmount(heroName, key, ranks)
	local s = H.stats[key]
	local base = H.heroBase(heroName)
	local out = {}
	if not s then
		return out
	end
	ranks = ranks or 1
	if s.hp and base then
		out.hp = base.health * s.hp * ranks
		out.regen = base.health * s.regen * ranks
	end
	if s.speed and base then
		out.speed = base.speed * s.speed * ranks
		out.sight = base.sight * s.sight * ranks
	end
	for _, k in ipairs({ "damage", "range", "splash", "pierce" }) do
		if s[k] then
			out[k] = s[k] * ranks
		end
	end
	return out
end

-- the effect of `ranks` ranks of a stat in words
function H.statText(heroName, key, ranks)
	local a = H.statAmount(heroName, key, ranks)
	local f = H.fmtAmount
	local pct = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
	if key == "vit" then
		return "+" .. f(a.hp or 0) .. " HP, +" .. f(a.regen or 0) .. " HP/s"
	elseif key == "mob" then
		return "+" .. f(a.speed or 0) .. " speed, +" .. f(a.sight or 0) .. " sight"
	elseif key == "dmg" then
		return "+" .. pct(a.damage or 0) .. " damage, all weapons"
	elseif key == "rng" then
		return "+" .. pct(a.range or 0) .. " range, all weapons"
	elseif key == "imp" then
		return "+" .. pct(a.splash or 0) .. " splash radius, " .. pct(a.pierce or 0) .. " penetration"
	end
	return ""
end

-- every learnable key of a hero, in panel order
function H.allKeys(heroName)
	local hero = H.heroes[heroName]
	local out = {}
	for _, key in ipairs(H.branchOrder) do
		if H.isStat[key] or (hero and hero[key]) then
			out[#out + 1] = key
		end
	end
	return out
end

function H.branch(heroName, key)
	if H.stats[key] then
		return H.stats[key]
	end
	local hero = H.heroes[heroName]
	return hero and H.isAbility[key] and hero[key] or nil
end

function H.maxRank(heroName, key)
	local b = H.branch(heroName, key)
	if not b then
		return 0
	end
	return H.isStat[key] and H.STAT_RANKS or (b.maxRank or H.ABILITY_RANKS)
end

function H.reqLevel(heroName, key, rank)
	if not H.branch(heroName, key) then
		return math.huge
	end
	if H.isStat[key] then
		return H.reqStat(rank)
	elseif key == "ult" then
		return H.reqUlt(rank)
	end
	return H.reqAbility(rank)
end

function H.metalCost(heroName, key, rank)
	if key == "ult" then
		return H.ULT_METAL * rank
	elseif H.isAbility[key] then
		return H.ABILITY_METAL * rank
	end
	return H.STAT_METAL * rank
end

-- the text of ability `key` at rank r (1..10)
function H.abilityText(heroName, key, r)
	local b = H.branch(heroName, key)
	if not b or not H.isAbility[key] then
		return ""
	end
	local t = b.text
	if type(t) == "function" then
		local ok, s = pcall(t, r, H, b)
		return ok and s or ""
	elseif type(t) == "table" then
		return t[r] or t[#t] or ""
	end
	return b.desc or ""
end

-- cumulative experience (in own-cost units) to reach a level
function H.xpFor(level, mult)
	if level <= 1 then
		return 0
	end
	return H.XP_TOTAL * ((level - 1) / H.XP_REF) ^ H.XP_EXP / (mult or 1)
end

-- metal to buy the next level at `level`: cost * (BUY_BASE + BUY_PER_LEVEL * level), and never less than
-- the metal of damage that level takes in combat. Nil at the top.
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

-- what an AI team pays for that level
function H.aiLevelPrice(heroName, level, cost)
	local p = H.levelPrice(heroName, level, cost)
	return p and math.floor(p * (1 - H.AI_BUY_DISCOUNT) / 100 + 0.5) * 100
end

return H
