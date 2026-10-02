-- Charybdis, the Maelstrom (legt4charybdis) - v19 Legion hero module (doc/v19-heroes/roster_leg.md section 8).
-- "Over water" = the ground at the point is below sea level.
--   a1 Undertow (passive): heat-ray hits slow the target (stacking per hit, once per 0.3 s per target, twice as fast
--      over water, 3 s); targets slowed >= 30% take more from its rockets and depth charges.
--   a2 Waterspout (map): after 0.5 s a spout tosses the enemies up (damage + stun); a mist stays 5 s and keeps the
--      enemies in it at maximum Undertow.
--   a3 Surge (map, dash): rides a wave to the point - enemies on the path are knocked aside, hit and drowned in
--      Undertow; the wake slows for 4 s. Further and twice as often over water.
--   ult Maw of the Deep (map): a maelstrom pulls enemies in for 7 s (outer / core damage); the core swallows small
--      non-hero units whole; it ends with a tidal blast throwing the survivors out.
local L = VFS.Include("luarules/heroes/legt4_lib.lua")
local C = L.C
local M = {}

local max, min, floor, sqrt, random, cos, sin = math.max, math.min, math.floor, math.sqrt, math.random, math.cos, math.sin

local function cfg(h, key)
	return h.def.cfg[key]
end

local function water(x, z)
	return Spring.GetGroundHeight(x, z) < 0
end

---------------------------------------------------------------------------- a1 Undertow

local function undertowOn(api, unitID, h, uid, slow)
	local r = api.rank(h, "a1")
	if r <= 0 or not L.alive(uid) then
		return 0
	end
	local a1 = cfg(h, "a1")
	local f = api.frame()
	local e = h.store.under[uid]
	if not e or e.untilF <= f then
		e = { slow = 0 }
		h.store.under[uid] = e
	end
	e.slow = min(api.val(a1.max, r), slow and (e.slow + slow) or api.val(a1.max, r))
	e.untilF = f + floor((a1.duration or 3) * 30)
	api.slow(uid, e.slow, a1.duration or 3)
	L.markOn(api, h.store.underFx, uid, "aura", { radius = max(45, L.radius(uid) * 0.8), color = L.a(C.TIDE, 0.2 + 0.5 * e.slow), pattern = "swirl" }, a1.duration or 3)
	return e.slow
end

local function slowOf(h, uid, f)
	local e = h.store.under[uid]
	return e and e.untilF > f and e.slow or 0
end

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	if isParalyzer or damage <= 0 then
		return damage
	end
	local r = api.rank(h, "a1")
	if r <= 0 then
		return damage
	end
	local a1 = cfg(h, "a1")
	local f = api.frame()
	if h.store.rayIds[weaponDefID] then
		local e = h.store.under[victimID]
		if not e or not e.lastAdd or f - e.lastAdd >= 9 then
			local x, _, z = api.pos(victimID)
			local per = api.val(a1.per, r) * (x and water(x, z) and 2 or 1)
			undertowOn(api, unitID, h, victimID, per)
			h.store.under[victimID].lastAdd = f
		end
	elseif h.store.bonusIds[weaponDefID] and slowOf(h, victimID, f) >= (a1.threshold or 0.3) then
		local b = api.val(a1.bonus, r)
		h.store.bonusDmg = (h.store.bonusDmg or 0) + damage * b
		return damage * (1 + b)
	end
	return damage
end

---------------------------------------------------------------------------- a2 Waterspout

local function waterspout(api, unitID, h, r, x, z)
	local a2 = cfg(h, "a2")
	local R = api.val(a2.radius, r) * (water(x, z) and 1.3 or 1)
	local fx = L.fx(api)
	local y = L.groundY(x, z)
	fx.ring(x, z, { kind = "shock", r0 = R, r1 = R * 0.2, color = L.a(C.TIDE, 0.6), width = 26, ttl = 0.5 })
	fx.ring(x, z, { kind = "swirl", r0 = R * 0.2, r1 = R, color = L.a(C.TIDE, 0.5), width = 30, ttl = 0.6, rot = 4 })
	api.delay(15, function()
		if not h then
			return
		end
		local dmg = api.val(a2.dmg, r) * api.power(h)
		local stun = api.val(a2.stun, r)
		local n = 0
		for _, uid in ipairs(api.enemiesIn(x, z, R, h.ally)) do
			api.damage(uid, dmg, unitID, { dtype = "plasma" })
			if not L.isStructure(uid) then
				local ux, _, uz = api.pos(uid)
				local px, pz = L.away(ux, uz, x, z, 60)
				api.throw(uid, px, pz, 0.9)
			end
			api.stun(uid, stun, unitID)
			undertowOn(api, unitID, h, uid, nil)
			n = n + 1
		end
		fx.pillar(x, z, { radius = R * 0.6, height = 1200, color = L.a(C.TIDE, 0.75), ttl = 0.6 })
		fx.pillar(x, z, { radius = R * 0.3, height = 1400, color = L.a(C.FOAM, 0.9), ttl = 0.4, ring = false })
		fx.flash(x, y + 40, z, { radius = R, color = C.FOAM, ttl = 0.35 })
		fx.ring(x, z, { kind = "shock", r0 = 30, r1 = R * 1.2, color = L.a(C.FOAM, 0.9), width = 30, ttl = 0.6 })
		-- the mist
		local mist = a2.mist or 5
		local ids = {
			fx.zone(x, z, { radius = R, pattern = "fog", color = L.a(C.FOAM, 0.35), ttl = mist }),
			fx.ring(x, z, { kind = "rune", r0 = R, r1 = R, color = L.a(C.FOAM, 0.25), width = 14, ttl = mist, rot = 0.5 }),
		}
		L.task(h, 15, mist, function()
			for _, uid in ipairs(api.enemiesIn(x, z, R, h.ally)) do
				undertowOn(api, unitID, h, uid, nil)
			end
		end)
		api.log("legt4charybdis a2 spout rank=%d radius=%d dmg=%d stun=%.1f hit=%d", r, R, dmg, stun, n)
	end)
	return true
end

---------------------------------------------------------------------------- a3 Surge

local function surge(api, unitID, h, r, x, z)
	local a3 = cfg(h, "a3")
	local x0, y0, z0 = api.pos(unitID)
	local wet = water(x0, z0)
	local tx, tz = L.clampTo(x0, z0, x, z, api.val(a3.reach, r) * (wet and 1.5 or 1))
	local fx = L.fx(api)
	local power = api.power(h)
	local dmg = api.val(a3.dmg, r) * power
	local width = a3.width or 240
	local victims = L.alongLine(api, x0, z0, tx, tz, width, h.ally)
	local trail = fx.attach(unitID, "trail", { color = L.a(C.TIDE, 0.8), width = 40, length = 0.6 })
	local ok = api.dash(unitID, h, tx, tz, { seconds = 0.5, onLand = L.later(api, function(lx, lz)
		fx.detach(trail)
		local ly = L.groundY(lx, lz)
		fx.flash(lx, ly + 30, lz, { radius = 160, color = C.FOAM, ttl = 0.35 })
		fx.ring(lx, lz, { kind = "shock", r0 = 30, r1 = 250, color = L.a(C.FOAM, 0.9), width = 26, ttl = 0.4 })
		-- path: knocked aside, hit, drowned
		local dx, dz = tx - x0, tz - z0
		local d = max(1, sqrt(dx * dx + dz * dz))
		local nx, nz = -dz / d, dx / d
		for _, e in ipairs(victims) do
			local uid = e[1]
			if L.alive(uid) then
				api.damage(uid, dmg, unitID, { dtype = "plasma" })
				undertowOn(api, unitID, h, uid, nil)
				local ux, _, uz = api.pos(uid)
				local side = ((ux - x0) * nx + (uz - z0) * nz) >= 0 and 1 or -1
				api.push(uid, ux - nx * side * 10, uz - nz * side * 10, a3.knock or 150, 0.4)
			end
		end
		-- the wake
		local wake = a3.wake or 4
		local beam = fx.beam(x0, L.groundY(x0, z0) + 5, z0, lx, ly + 5, lz, { color = L.a(C.TIDE, 0.35), width = 120, ttl = wake, pulse = 3, flare = 0, ground = true })
		L.task(h, 15, wake, function()
			for _, w in ipairs(L.alongLine(api, x0, z0, lx, lz, 140, h.ally)) do
				api.slow(w[1], a3.wakeSlow or 0.4, 1)
			end
		end)
		if wet then
			api.cooldown(unitID, h, "a3", api.val(a3.cooldown, r) * 0.5)
		end
		api.log("legt4charybdis a3 surge rank=%d dist=%d water=%s victims=%d dmg=%d", r, d, tostring(wet), #victims, dmg)
	end) })
	if not ok then
		fx.detach(trail)
	end
	return ok
end

---------------------------------------------------------------------------- ult Maw of the Deep

local function maw(api, unitID, h, r, x, z)
	local ult = cfg(h, "ult")
	local wet = water(x, z)
	local R = api.val(ult.radius, r) * (wet and 1.2 or 1)
	local dur = ult.duration or 7
	local pull = api.val(ult.pull, r) * (wet and 1.3 or 1)
	local power = api.power(h)
	local outer = api.val(ult.outer, r) * power * 0.2
	local core = api.val(ult.core, r) * power * 0.2
	local coreR = ult.coreRadius or 160
	local swallow = api.val(ult.swallow, r)
	local fx = L.fx(api)
	local y = L.groundY(x, z)
	local st = { dmg = 0, swallowed = 0 }
	local ids = {
		fx.zone(x, z, { radius = R, pattern = "swirl", color = L.a(C.TIDE, 0.55), rot = 1.6, ttl = dur }),
		fx.ring(x, z, { kind = "rune", r0 = R, r1 = R, color = L.a(C.TIDE, 0.4), width = 20, ttl = dur, rot = -0.4 }),
		fx.pillar(x, z, { radius = coreR, height = 300, color = C.ABYSS, ttl = dur, ring = false }),
		fx.attachPoint(x, z, "orb", { color = L.a(C.FOAM, 0.8), radius = 12, height = 30, orbit = R * 0.55, speed = 0.5, count = 6, crackle = 1, ttl = dur }),
	}
	api.active(unitID, "ult", dur)
	L.task(h, 6, dur, function(f, t)
		local n = (f - t.start) / 6
		if n % 3 == 0 then
			fx.ring(x, z, { kind = "shock", r0 = R, r1 = R * 0.15, color = L.a(C.TIDE, 0.7), width = 30, ttl = 0.5 })
		end
		if n % 5 == 0 then
			fx.pillar(x, z, { radius = 90, height = 900, color = L.a(C.FOAM, 0.6), ttl = 0.6, ring = false })
		end
		for _, uid in ipairs(api.enemiesIn(x, z, R, h.ally)) do
			local ux, uy, uz = api.pos(uid)
			local d2 = L.d2(ux, uz, x, z)
			local inCore = d2 <= coreR * coreR
			if inCore and not api.isHero(uid) and not L.isStructure(uid) and L.effHp(api, uid) < swallow then
				fx.flash(ux, uy + 20, uz, { radius = 80, color = C.TIDE, ttl = 0.3 })
				fx.bolt(ux, uy + 20, uz, x, y + 5, z, { color = C.FOAM, width = 4, ttl = 0.2 })
				if api.consume(uid, { credit = unitID }) then
					st.swallowed = st.swallowed + 1
				end
			else
				local dd = inCore and core or outer
				api.damage(uid, dd, unitID, { dtype = "plasma" })
				st.dmg = st.dmg + dd
				if not L.isStructure(uid) and not L.isAir(uid) and d2 > 50 * 50 then
					api.pull(uid, x, z, pull * 0.2, 0.2)
				end
			end
		end
	end, function()
		if not h then
			return
		end
		local blast = api.val(ult.blast, r) * power
		local hit = 0
		for _, uid in ipairs(api.enemiesIn(x, z, R, h.ally)) do
			api.damage(uid, blast, unitID, { dtype = "plasma" })
			if not L.isStructure(uid) then
				api.push(uid, x, z, 220, 0.5)
			end
			hit = hit + 1
		end
		fx.ring(x, z, { kind = "shock", r0 = R * 0.1, r1 = R * 1.3, color = L.a(C.FOAM, 0.9), width = 80, ttl = 0.8 })
		fx.flash(x, y + 40, z, { radius = R, color = C.FOAM, ttl = 0.5 })
		api.log("legt4charybdis ult maw over rank=%d radius=%d water=%s dmg=%d swallowed=%d blast=%d hit=%d", r, R, tostring(wet), st.dmg, st.swallowed, blast, hit)
	end)
	api.log("legt4charybdis ult maw rank=%d radius=%d pull=%d outer=%d core=%d swallow<%d", r, R, pull, outer * 5, core * 5, swallow)
	return true
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.tasks = {}
	h.store.under = {}
	h.store.underFx = {}
	local ray, bonus = {}, {}
	for _, w in pairs(h.def.weapons) do
		if w.key == "heat_ray" then
			ray[w.wdid] = true
		elseif w.key == "parabolic_rockets" or w.key == "depthcharge" then
			bonus[w.wdid] = true
		end
	end
	h.store.rayIds, h.store.bonusIds = ray, bonus
end

function M.frame(api, unitID, h, f)
	L.runTasks(h, f)
	if f % 30 == 0 then
		L.markSweep(api, h.store.underFx, f)
		for uid, e in pairs(h.store.under) do
			if e.untilF <= f then
				h.store.under[uid] = nil
			end
		end
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if not x then
		return false
	end
	if key == "a2" then
		return waterspout(api, unitID, h, rank, x, z)
	elseif key == "a3" then
		return surge(api, unitID, h, rank, x, z)
	elseif key == "ult" then
		return maw(api, unitID, h, rank, x, z)
	end
	return false
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	if key == "a2" then
		local a2 = cfg(h, "a2")
		for _, uid in ipairs(L.enemyHeroes(api, x, z, a2.range, h.ally)) do
			local tx, ty, tz = api.pos(uid)
			return tx, ty, tz
		end
		local n, cx, cz = L.cluster(api, x, z, a2.range, api.val(a2.radius, rank), h.ally, 3)
		if cx and n >= 3 then
			return cx, L.groundY(cx, cz), cz
		end
	elseif key == "a3" then
		local a3 = cfg(h, "a3")
		local reach = api.val(a3.reach, rank)
		if L.hpFrac(unitID) < 0.3 then
			local cx, cz = L.centroid(api, x, z, 900, h.ally)
			if cx then
				local px, pz = L.away(x, z, cx, cz, reach)
				return px, L.groundY(px, pz), pz
			end
		end
		local t, tx, ty, tz = api.target(unitID)
		if tx then
			local px, pz = L.clampTo(x, z, tx, tz, reach)
			if #L.alongLine(api, x, z, px, pz, a3.width or 240, h.ally) >= 3 then
				return px, L.groundY(px, pz), pz
			end
		end
	elseif key == "ult" then
		local ult = cfg(h, "ult")
		local n, cx, cz, heroes = L.cluster(api, x, z, ult.range, 700, h.ally, 1, 0)
		if cx and (n >= 8 or (heroes > 0 and n >= 5)) then
			return cx, L.groundY(cx, cz), cz
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	L.endTasks(h)
	L.markClear(api, h.store.underFx or {})
	h.store.under = {}
end

return M
