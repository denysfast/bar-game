-- Shared helpers of the Legion hero modules (luarules/heroes/legt4*.lua): palette, a no-op fx fallback, target
-- picking for autocast, a tiny per-hero task scheduler and per-target fx attachments. Not a hero module itself
-- (the core only loads luarules/heroes/<heroname>.lua); every Legion module VFS.Include's it.
local L = {}

local max, min, sqrt, floor, random = math.max, math.min, math.sqrt, math.floor, math.random
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitDefID = Spring.GetUnitDefID
local spValidUnitID = Spring.ValidUnitID
local spGetGroundHeight = Spring.GetGroundHeight

-- Legion palette (roster_leg.md), saturated a little: the effects blend additively, and the pale roster tints
-- (star / storm / soul / foam) burned out to white wherever a few of them overlapped
L.C = {
	SOLAR = { 1, 0.75, 0.3, 1 }, EMBER = { 1, 0.4, 0.08, 1 }, WHITEGOLD = { 1, 0.92, 0.65, 1 },
	STAR = { 0.4, 0.6, 1, 1 }, VOID = { 0.62, 0.38, 1, 1 },
	RAIL = { 0.2, 0.85, 1, 1 }, STORM = { 0.35, 0.6, 1, 1 },
	HIVE = { 1, 0.55, 0.15, 1 }, HEAL = { 0.35, 1, 0.45, 1 },
	SOUL = { 0.25, 1, 0.6, 1 }, AMBER = { 0.9, 0.55, 0.2, 1 }, VENOM = { 0.45, 1, 0.15, 1 },
	TIDE = { 0.2, 0.6, 1, 1 }, FOAM = { 0.6, 0.85, 1, 1 }, ABYSS = { 0.05, 0.15, 0.4, 0.9 },
	GORGON = { 0.25, 1, 0.45, 1 }, STONE = { 0.6, 0.62, 0.55, 1 }, WHITE = { 1, 1, 1, 1 },
}

-- colour with another alpha
function L.a(c, alpha)
	return { c[1], c[2], c[3], alpha }
end

-- the fx library, or a sink that swallows every call (no GG.HeroFX: abilities still work, just unseen)
local sink = setmetatable({}, { __index = function()
	return function() return nil end
end })
function L.fx(api)
	return api.fx or sink
end

function L.d2(x1, z1, x2, z2)
	return (x1 - x2) ^ 2 + (z1 - z2) ^ 2
end

function L.alive(uid)
	return uid and spValidUnitID(uid) and not Spring.GetUnitIsDead(uid)
end

function L.groundY(x, z)
	return max(0, spGetGroundHeight(x, z))
end

function L.radius(uid)
	return Spring.GetUnitRadius(uid) or 40
end

function L.ud(uid)
	return UnitDefs[spGetUnitDefID(uid) or -1]
end

function L.isStructure(uid)
	local ud = L.ud(uid)
	return not ud or ud.isImmobile or (ud.speed or 0) == 0
end

function L.isAir(uid)
	local ud = L.ud(uid)
	return ud and ud.canFly
end

-- the hero's own (non-hero) summons are allies; never count them as targets anyway
function L.enemies(api, x, z, r, ally, seenOnly)
	local out = {}
	for _, uid in ipairs(api.enemiesIn(x, z, r, ally)) do
		if not seenOnly or api.seenBy(uid, ally) then
			out[#out + 1] = uid
		end
	end
	return out
end

function L.enemyHeroes(api, x, z, r, ally)
	local out = {}
	for _, uid in ipairs(api.enemiesIn(x, z, r, ally)) do
		if api.isHero(uid) and api.seenBy(uid, ally) then
			out[#out + 1] = uid
		end
	end
	return out
end

-- the spot within `range` of x, z whose `radius` holds the most seen enemies (heroes count `heroW`, structures
-- `structW`): count, cx, cz, heroes inside
function L.cluster(api, x, z, range, radius, ally, heroW, structW)
	local cands = L.enemies(api, x, z, range, ally, true)
	local best, bx, bz, bh = 0
	local step = max(1, floor(#cands / 24))
	for i = 1, #cands, step do
		local cx, _, cz = spGetUnitPosition(cands[i])
		if cx then
			local score, heroes, sx, sz, n = 0, 0, 0, 0, 0
			for _, uid in ipairs(api.enemiesIn(cx, cz, radius, ally)) do
				if api.seenBy(uid, ally) then
					local w = 1
					if api.isHero(uid) then
						w, heroes = heroW or 3, heroes + 1
					elseif structW and L.isStructure(uid) then
						w = structW
					end
					score = score + w
					local ux, _, uz = spGetUnitPosition(uid)
					sx, sz, n = sx + ux, sz + uz, n + 1
				end
			end
			if score > best then
				best, bx, bz, bh = score, sx / n, sz / n, heroes
			end
		end
	end
	return best, bx, bz, bh or 0
end

-- centroid of the enemies around
function L.centroid(api, x, z, r, ally)
	local sx, sz, n = 0, 0, 0
	for _, uid in ipairs(api.enemiesIn(x, z, r, ally)) do
		local ux, _, uz = spGetUnitPosition(uid)
		sx, sz, n = sx + ux, sz + uz, n + 1
	end
	if n == 0 then
		return nil
	end
	return sx / n, sz / n, n
end

-- a point `dist` from x, z away from (ax, az), clamped to the map
function L.away(x, z, ax, az, dist)
	local dx, dz = x - ax, z - az
	local d = max(1, sqrt(dx * dx + dz * dz))
	return max(64, min(Game.mapSizeX - 64, x + dx / d * dist)), max(64, min(Game.mapSizeZ - 64, z + dz / d * dist))
end

-- clamp a point to `reach` from x, z
function L.clampTo(x, z, tx, tz, reach)
	local dx, dz = tx - x, tz - z
	local d = sqrt(dx * dx + dz * dz)
	if d > reach and d > 0 then
		tx, tz = x + dx / d * reach, z + dz / d * reach
	end
	return max(64, min(Game.mapSizeX - 64, tx)), max(64, min(Game.mapSizeZ - 64, tz))
end

function L.hpFrac(uid)
	local hp, maxHp = Spring.GetUnitHealth(uid)
	return hp and maxHp and maxHp > 0 and hp / maxHp or 1, hp, maxHp
end

-- the unit's max HP in effective units (heroes: x hpMult)
function L.effMaxHp(api, uid)
	local _, maxHp = Spring.GetUnitHealth(uid)
	local h = api.hero(uid)
	return (maxHp or 0) * (h and h.hpMult or 1)
end

function L.effHp(api, uid)
	local hp = Spring.GetUnitHealth(uid)
	local h = api.hero(uid)
	return (hp or 0) * (h and h.hpMult or 1)
end

-- units along a segment (enemies), sorted by the distance along it: { {uid, t, dist}... }
function L.alongLine(api, x1, z1, x2, z2, width, ally)
	local out, seen = {}, {}
	local dx, dz = x2 - x1, z2 - z1
	local len = max(1, sqrt(dx * dx + dz * dz))
	local hw = width * 0.5
	for s = 0, len + hw, hw do
		local px, pz = x1 + dx / len * min(s, len), z1 + dz / len * min(s, len)
		for _, uid in ipairs(api.enemiesIn(px, pz, hw + 60, ally)) do
			if not seen[uid] then
				seen[uid] = true
				local ux, _, uz = spGetUnitPosition(uid)
				local t = max(0, min(1, ((ux - x1) * dx + (uz - z1) * dz) / (len * len)))
				local qx, qz = x1 + dx * t - ux, z1 + dz * t - uz
				local rr = hw + L.radius(uid) * 0.5
				if qx * qx + qz * qz <= rr * rr then
					out[#out + 1] = { uid, t, t * len }
				end
			end
		end
	end
	table.sort(out, function(a, b) return a[2] < b[2] end)
	return out
end

-- v19 dmgfix: a piercing line is a budget, not a copy of the damage for everyone on it. The budget is spread over
-- the victims in order along the line with a falloff, no victim takes more than `cap`. Returns { {uid, dmg}... }
function L.budget(victims, budget, cap, falloff)
	falloff = falloff or 0.82
	local w, sum = 1, 0
	for i = 1, #victims do
		sum = sum + w
		w = w * falloff
	end
	local out = {}
	w = 1
	for i = 1, #victims do
		out[i] = { victims[i][1] or victims[i], min(cap, budget * w / max(1, sum)) }
		w = w * falloff
	end
	return out
end

-- wrap a movement callback (api.dash onStep / onLand): it runs on the next frame, outside the core's iteration over
-- its movers (a callback that pushes / pulls / kills there broke that loop: "invalid key to 'next'")
function L.later(api, fn)
	return function(a, b)
		api.delay(1, function()
			fn(a, b)
		end)
	end
end

---------------------------------------------------------------------------- tasks
-- h.store.tasks: { at = next frame, every = frames, stop = last frame, fn(f, t) -> false ends it, done(t) }
function L.task(h, every, seconds, fn, done, startIn)
	h.store.tasks = h.store.tasks or {}
	local f = Spring.GetGameFrame()
	local t = { at = f + (startIn or 0), every = max(1, every), stop = seconds and (f + (startIn or 0) + floor(seconds * 30)) or nil,
		fn = fn, done = done, start = f }
	h.store.tasks[#h.store.tasks + 1] = t
	return t
end

function L.runTasks(h, f)
	local ts = h.store.tasks
	if not ts or #ts == 0 then
		return
	end
	local keep = {}
	for _, t in ipairs(ts) do
		local alive = not t.dead
		if alive and t.stop and f >= t.stop then
			alive = false
		elseif alive and f >= t.at then
			t.at = t.at + t.every
			if t.at <= f then
				t.at = f + t.every
			end
			local ok, res = pcall(t.fn, f, t)
			if not ok then
				Spring.Echo("[legt4] task error: " .. tostring(res))
				alive = false
			elseif res == false then
				alive = false
			end
		end
		if alive then
			keep[#keep + 1] = t
		elseif t.done then
			local ok, err = pcall(t.done, t)
			if not ok then
				Spring.Echo("[legt4] task done error: " .. tostring(err))
			end
		end
	end
	-- tasks added while running
	for i = #ts + 1, #h.store.tasks do
		keep[#keep + 1] = h.store.tasks[i]
	end
	h.store.tasks = keep
end

-- end every task (hero died)
function L.endTasks(h)
	local ts = h.store.tasks or {}
	h.store.tasks = {}
	for _, t in ipairs(ts) do
		if t.done then
			pcall(t.done, t)
		end
	end
end

---------------------------------------------------------------------------- per-target attachments
-- set = h.store.<name> = { [uid] = { id, until } }: one attachment per target, refreshed / recoloured
function L.markOn(api, set, uid, kind, opts, seconds)
	local fx = L.fx(api)
	local e = set[uid]
	local f = Spring.GetGameFrame()
	if not e then
		e = { id = fx.attach(uid, kind, opts) }
		set[uid] = e
	elseif opts and e.id then
		fx.set(e.id, opts)
	end
	e.untilF = seconds and (f + floor(seconds * 30)) or nil
	return e
end

function L.markOff(api, set, uid)
	local e = set[uid]
	if e then
		set[uid] = nil
		if e.id then
			L.fx(api).detach(e.id)
		end
	end
end

-- drop expired / dead ones
function L.markSweep(api, set, f)
	for uid, e in pairs(set) do
		if (e.untilF and f >= e.untilF) or not L.alive(uid) then
			L.markOff(api, set, uid)
		end
	end
end

function L.markClear(api, set)
	for uid in pairs(set) do
		L.markOff(api, set, uid)
	end
end

-- per rank value of an ability field of hero h
function L.v(api, h, key, field, r)
	local b = h.def.cfg[key]
	return b and api.val(b[field], r or api.rank(h, key))
end

-- a ground flash at a unit (y from the unit)
function L.unitFlash(api, uid, radius, color, ttl, dy)
	local x, y, z = spGetUnitPosition(uid)
	if x then
		L.fx(api).flash(x, y + (dy or 20), z, { radius = radius, color = color, ttl = ttl or 0.3 })
	end
end

return L
