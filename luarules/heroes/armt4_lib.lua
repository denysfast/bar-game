-- Shared helpers of the Armada hero modules (luarules/heroes/armt4*.lua). Not a hero module itself (no hero is named
-- armt4_lib): each module loads it with VFS.Include("luarules/heroes/armt4_lib.lua", nil, VFS.ZIP_FIRST).
-- Synced only. API: header of luarules/gadgets/unit_t4_heroes.lua; effects: GG.HeroFX (api.fx).

local L = {}

local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetGroundHeight = Spring.GetGroundHeight
local max, min, sqrt, floor = math.max, math.min, math.sqrt, math.floor

L.GAME_SPEED = Game.gameSpeed or 30

function L.cfg(h, key)
	return h.def.cfg[key]
end

-- the rank value of field `field` of ability `key` (at the learned rank, or r)
function L.v(api, h, key, field, r)
	local b = h.def.cfg[key]
	return api.val(b and b[field], r or api.rank(h, key))
end

function L.gy(x, z)
	return max(0, spGetGroundHeight(x, z))
end

function L.radius(uid)
	return Spring.GetUnitRadius(uid) or 40
end

function L.hpFrac(uid)
	local hp, maxHp = spGetUnitHealth(uid)
	if not hp or not maxHp or maxHp <= 0 then
		return 1
	end
	return hp / maxHp
end

function L.dist(x1, z1, x2, z2)
	return sqrt((x1 - x2) ^ 2 + (z1 - z2) ^ 2)
end

function L.unitDist(a, b)
	local ax, _, az = spGetUnitPosition(a)
	local bx, _, bz = spGetUnitPosition(b)
	if not ax or not bx then
		return math.huge
	end
	return sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

function L.alive(uid)
	return uid and Spring.ValidUnitID(uid) and not Spring.GetUnitIsDead(uid)
end

local structure, mobile, bot, air = {}, {}, {}, {}
for udid, ud in pairs(UnitDefs) do
	structure[udid] = ud.isImmobile or (ud.speed or 0) == 0
	mobile[udid] = (ud.speed or 0) > 0 and not ud.canFly
	air[udid] = ud.canFly or false
	local tl = tonumber(ud.customParams and ud.customParams.techlevel) or 1
	bot[udid] = mobile[udid] and ud.modCategories and ud.modCategories.bot and tl <= 2 or false
end
function L.isStructure(uid)
	return structure[spGetUnitDefID(uid) or -1] or false
end
function L.isMobile(uid)
	return mobile[spGetUnitDefID(uid) or -1] or false
end
function L.isBot(uid)
	return bot[spGetUnitDefID(uid) or -1] or false
end
function L.isAir(uid)
	return air[spGetUnitDefID(uid) or -1] or false
end
function L.isStructureDef(udid)
	return structure[udid] or false
end

-- visible enemies within r (the AI never targets what its team cannot see)
function L.seenEnemies(api, x, z, r, ally)
	local out = {}
	for _, uid in ipairs(api.enemiesIn(x, z, r, ally)) do
		if api.seenBy(uid, ally) then
			out[#out + 1] = uid
		end
	end
	return out
end

-- the nearest visible enemy hero within r
function L.enemyHero(api, x, z, r, ally)
	for _, uid in ipairs(api.nearestEnemies(x, z, r, ally, 40)) do
		if api.isHero(uid) and api.seenBy(uid, ally) then
			return uid
		end
	end
end

-- the best spot for an area ability: among the visible enemies within `range` of x, z, the one with the most enemy
-- metal within `radius` around it. Returns cx, cz (the cost-weighted centre of that group), cost, count
function L.cluster(api, x, z, range, radius, ally, heroWeight)
	local cands = L.seenEnemies(api, x, z, range, ally)
	local best, bx, bz, bn = 0, nil, nil, 0
	local step = max(1, floor(#cands / 40))
	for i = 1, #cands, step do
		local cx, _, cz = spGetUnitPosition(cands[i])
		if cx then
			local sum, n, sx, sz = 0, 0, 0, 0
			for _, uid in ipairs(api.enemiesIn(cx, cz, radius, ally)) do
				local c = api.cost(uid) * (api.isHero(uid) and (heroWeight or 2) or 1)
				local ux, _, uz = spGetUnitPosition(uid)
				sum, n = sum + c, n + 1
				sx, sz = sx + ux * c, sz + uz * c
			end
			if sum > best then
				best, bn = sum, n
				bx, bz = sum > 0 and sx / sum or cx, sum > 0 and sz / sum or cz
			end
		end
	end
	return bx, bz, best, bn
end

-- weapondef id -> the hero's weapon key (base weapons and their api.swapWeapons copies)
function L.weaponKey(h, weaponDefID)
	local map = h.store._wkey
	if not map then
		map = {}
		for _, w in pairs(h.def.weapons) do
			map[w.wdid] = w.key
		end
		for _, copies in pairs(h.def.copies or {}) do
			for base, copy in pairs(copies) do
				map[copy] = map[base]
			end
		end
		for key, wdid in pairs(h.def.extra or {}) do
			map[wdid] = map[wdid] or key
		end
		h.store._wkey = map
	end
	return map[weaponDefID]
end

-- is weaponDefID the api.swapWeapons copy <key>_<suffix>?
function L.isCopy(h, weaponDefID, suffix)
	local c = h.def.copies and h.def.copies[suffix]
	if not c then
		return false
	end
	for _, copy in pairs(c) do
		if copy == weaponDefID then
			return true
		end
	end
	return false
end

-- base stats of a weapon key of the hero (first weapon with that key)
function L.weapon(h, key)
	local nums = h.def.keyNum[key]
	return nums and h.def.weapons[nums[1]], nums and nums[1]
end

function L.detach(api, ...)
	local fx = api.fx
	if not fx then
		return
	end
	for i = 1, select("#", ...) do
		local id = select(i, ...)
		if type(id) == "table" then
			for _, x in pairs(id) do
				fx.detach(x)
			end
		elseif id then
			fx.detach(id)
		end
	end
end

-- facing of a unit as a unit vector (x, z)
function L.facing(uid)
	local dx, _, dz = Spring.GetUnitDirection(uid)
	if not dx then
		return 0, 1
	end
	local d = sqrt(dx * dx + dz * dz)
	if d < 1e-3 then
		return 0, 1
	end
	return dx / d, dz / d
end

-- timers of a module (processed by L.tick from the frame hook; die with the hero)
function L.after(h, frames, fn)
	local t = h.store._timers
	if not t then
		t = {}
		h.store._timers = t
	end
	t[#t + 1] = { at = Spring.GetGameFrame() + max(1, floor(frames)), fn = fn }
end

function L.tick(h, f)
	local t = h.store._timers
	if not t or #t == 0 then
		return
	end
	local keep, due = {}, {}
	for _, e in ipairs(t) do
		if e.at <= f then
			due[#due + 1] = e
		else
			keep[#keep + 1] = e
		end
	end
	h.store._timers = keep
	for _, e in ipairs(due) do
		local ok, err = pcall(e.fn)
		if not ok then
			Spring.Echo("[armt4] timer error: " .. tostring(err))
		end
	end
end

-- falloff damage in a circle: `dmg` at the centre to `edge` x dmg at the rim; extra(uid) -> multiplier (optional)
function L.falloff(api, unitID, x, z, radius, dmg, edge, opts, extra)
	local hits = {}
	local ally = opts and opts.ally
	for _, uid in ipairs(api.enemiesIn(x, z, radius, ally or Spring.GetUnitAllyTeam(unitID))) do
		local ux, _, uz = spGetUnitPosition(uid)
		if ux then
			local d = sqrt((ux - x) ^ 2 + (uz - z) ^ 2) / radius
			local m = 1 - (1 - (edge or 0.3)) * min(1, d)
			local e = extra and extra(uid) or 1
			api.damage(uid, dmg * m * e, unitID, opts)
			hits[#hits + 1] = uid
		end
	end
	return hits
end

return L
