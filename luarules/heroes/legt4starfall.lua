-- Starfall, the Astronomer (legt4starfall) - v19 Legion hero module (doc/v19-heroes/roster_leg.md section 2).
--   a1 Constellation (passive): the first impact of each salvo places a Star (8 s); consecutive Stars closer than
--      `link` are joined by a burning line that hurts the enemies on it every 0.5 s. Oldest Star dropped at the cap.
--   a2 Gravity Lens (map): a well pulls enemies to its centre for 6 s; Starfall's shells landing inside hit harder.
--   a3 Deep Sky Eye (map): reveals an area (LOS, radar, decloak); the enemies in it are Observed (+damage taken from
--      every source, api.mark vuln).
--   ult Starfall (map): meteors over 8 s (each places a Star, cap +5 meanwhile), then a Comet in the centre.
local L = VFS.Include("luarules/heroes/legt4_lib.lua")
local C = L.C
local M = {}

local max, min, floor, sqrt, random, cos, sin = math.max, math.min, math.floor, math.sqrt, math.random, math.cos, math.sin

local function cfg(h, key)
	return h.def.cfg[key]
end

---------------------------------------------------------------------------- a1 Constellation

local function dropStar(api, h, s)
	local fx = L.fx(api)
	for _, id in ipairs(s.ids) do
		fx.detach(id)
	end
	if s.link then
		fx.detach(s.link)
	end
	local nx = s.next
	if nx then
		fx.detach(nx.link)
		fx.detach(nx.glow)
		nx.link, nx.glow, nx.prev = nil, nil, nil
	end
end

local function placeStar(api, unitID, h, x, z)
	local r = api.rank(h, "a1")
	if r <= 0 then
		return
	end
	local a1 = cfg(h, "a1")
	local f = api.frame()
	local stars = h.store.stars
	local cap = api.val(a1.stars, r) + ((h.store.ultUntil or 0) > f and 5 or 0)
	while #stars >= cap do
		dropStar(api, h, table.remove(stars, 1))
	end
	local fx = L.fx(api)
	local ttl = a1.ttl or 8
	local y = L.groundY(x, z)
	local s = { x = x, z = z, y = y, expire = f + floor(ttl * 30), ids = {} }
	fx.flash(x, y + 30, z, { radius = 60, color = C.STAR, ttl = 0.4 })
	s.ids[#s.ids + 1] = fx.ring(x, z, { kind = "rune", r0 = 70, r1 = 70, color = L.a(C.STAR, 0.8), width = 16, ttl = ttl, rot = 1.2 })
	s.ids[#s.ids + 1] = fx.attachPoint(x, z, "orb", { color = C.STAR, radius = 14, height = 40, orbit = 0, crackle = 4, ttl = ttl })
	local prev = stars[#stars]
	if prev and prev.expire > f and L.d2(prev.x, prev.z, x, z) <= api.val(a1.link, r) ^ 2 then
		local life = (min(prev.expire, s.expire) - f) / 30
		s.link = fx.beam(prev.x, prev.y + 40, prev.z, x, y + 40, z, { color = L.a(C.STAR, 0.7), width = 5, ttl = life, pulse = 1.5, flare = 0.4 })
		s.glow = fx.beam(prev.x, prev.y + 40, prev.z, x, y + 40, z, { color = L.a(C.VOID, 0.25), width = 22, ttl = life, pulse = 0.6, flare = 0 })
		s.ids[#s.ids + 1] = s.glow
		s.prev = prev
		prev.next = s
	end
	stars[#stars + 1] = s
end

-- the lines burn the enemies on them
local function constellationTick(api, unitID, h, f)
	local r = api.rank(h, "a1")
	if r <= 0 then
		return
	end
	local a1 = cfg(h, "a1")
	local keep = {}
	for _, s in ipairs(h.store.stars) do
		if s.expire > f then
			keep[#keep + 1] = s
		else
			dropStar(api, h, s)
		end
	end
	h.store.stars = keep
	local dmg = api.val(a1.dmg, r) * api.power(h)
	local fx = L.fx(api)
	local total, n = 0, 0
	for _, s in ipairs(keep) do
		local p = s.prev
		if p and p.expire > f then
			local hit = api.line(p.x, p.z, s.x, s.z, (a1.width or 40) * 2, dmg, unitID, { dtype = "plasma" })
			for i, uid in ipairs(hit) do
				total, n = total + dmg, n + 1
				if i <= 6 then
					L.unitFlash(api, uid, 25, C.STAR, 0.3)
				end
			end
		end
	end
	if n > 0 then
		api.log("legt4starfall a1 lines tick rank=%d hits=%d dmg=%d", r, n, total)
	end
end

function M.impact(api, unitID, h, weaponDefID, x, y, z, projectileID)
	if h.store.mainIds[weaponDefID] and api.rank(h, "a1") > 0 then
		local f = api.frame()
		if f - (h.store.lastSalvo or -1000) > 75 then
			h.store.lastSalvo = f
			placeStar(api, unitID, h, x, z)
		else
			h.store.lastSalvo = f
		end
	end
end

---------------------------------------------------------------------------- a2 Gravity Lens

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	if isParalyzer or damage <= 0 or #h.store.lenses == 0 then
		return damage
	end
	local x, _, z = api.pos(victimID)
	local f = api.frame()
	for _, l in ipairs(h.store.lenses) do
		if l.untilF > f and L.d2(l.x, l.z, x, z) <= l.radius * l.radius then
			l.bonusDmg = (l.bonusDmg or 0) + damage * l.bonus
			return damage * (1 + l.bonus)
		end
	end
	return damage
end

local function gravityLens(api, unitID, h, r, x, z)
	local a2 = cfg(h, "a2")
	local R = api.val(a2.radius, r)
	local dur = a2.duration or 6
	local pull = api.val(a2.pull, r)
	local fx = L.fx(api)
	local y = L.groundY(x, z)
	local l = { x = x, z = z, radius = R, bonus = api.val(a2.bonus, r), untilF = api.frame() + floor(dur * 30), pulled = 0 }
	h.store.lenses[#h.store.lenses + 1] = l
	l.zone = fx.zone(x, z, { radius = R, pattern = "swirl", color = L.a(C.VOID, 0.5), rot = 2.5, ttl = dur })
	l.pillar = fx.pillar(x, z, { radius = 25, height = 600, color = L.a(C.VOID, 0.5), ttl = dur, ring = false })
	l.core = fx.attachPoint(x, z, "orb", { color = { 0.25, 0.1, 0.5, 1 }, radius = 34, height = 60, crackle = 8, ttl = dur })
	fx.flash(x, y + 40, z, { radius = 220, color = C.VOID, ttl = 0.5 })
	L.task(h, 6, dur, function(f, t)
		local n = (f - t.start) / 6
		if n % 4 == 0 then
			fx.ring(x, z, { kind = "rune", r0 = R, r1 = R * 0.1, color = L.a(C.VOID, 0.7), width = 14, ttl = 0.75, rot = -2 })
		end
		if n % 2 == 1 then
			fx.flash(x, y + 50, z, { radius = 60, color = C.VOID, ttl = 0.5 })
		end
		for _, uid in ipairs(api.enemiesIn(x, z, R, h.ally)) do
			if not L.isStructure(uid) and not L.isAir(uid) then
				local ux, _, uz = api.pos(uid)
				if L.d2(ux, uz, x, z) > 40 * 40 then
					api.pull(uid, x, z, pull * 0.2, 0.2)
					l.pulled = l.pulled + 1
				end
			end
		end
	end, function()
		api.log("legt4starfall a2 lens over rank=%d radius=%d pullSteps=%d bonusDmg=%d", r, R, l.pulled, l.bonusDmg or 0)
	end)
	api.log("legt4starfall a2 lens rank=%d radius=%d pull=%d bonus=%.2f", r, R, pull, l.bonus)
	return true
end

---------------------------------------------------------------------------- a3 Deep Sky Eye

local function skyEye(api, unitID, h, r, x, z)
	local a3 = cfg(h, "a3")
	local R = api.val(a3.radius, r)
	local dur = api.val(a3.duration, r)
	local vuln = api.val(a3.vuln, r)
	local fx = L.fx(api)
	local y = L.groundY(x, z)
	api.reveal(x, z, R, dur, h.ally)
	fx.pillar(x, z, { radius = 60, height = 3000, color = L.a(C.STAR, 0.5), ttl = 0.6 })
	fx.ring(x, z, { kind = "hex", r0 = R * 0.2, r1 = R, color = L.a(C.STAR, 0.6), width = 30, ttl = 1 })
	local ids = {
		fx.ring(x, z, { kind = "rune", r0 = R, r1 = R, color = L.a(C.STAR, 0.35), width = 10, ttl = dur, rot = 0.15 }),
		fx.attachPoint(x, z, "orb", { color = C.STAR, radius = 70, height = 900, crackle = 5, ttl = dur, visible = "all" }),
		fx.zone(x, z, { radius = R, pattern = "glow", color = L.a(C.STAR, 0.08), ttl = dur }),
	}
	local observed = {}
	local seen = 0
	L.task(h, 30, dur, function(f)
		local list = api.enemiesIn(x, z, R, h.ally)
		for i, uid in ipairs(list) do
			api.mark(uid, "legt4starfall_observed", 1.2, { vuln = vuln, max = 1, stacks = 1, from = unitID })
			if not observed[uid] then
				seen = seen + 1
			end
			if i <= 40 then
				L.markOn(api, observed, uid, "aura", { radius = max(40, L.radius(uid) * 0.7), color = L.a(C.STAR, 0.5), pattern = "runes" }, 1.2)
			end
		end
		L.markSweep(api, observed, f)
	end, function()
		L.markClear(api, observed)
		api.log("legt4starfall a3 eye over rank=%d radius=%d dur=%d vuln=%.2f observed=%d", r, R, dur, vuln, seen)
	end)
	api.log("legt4starfall a3 eye rank=%d radius=%d dur=%d vuln=%.2f", r, R, dur, vuln)
	return true
end

---------------------------------------------------------------------------- ult Starfall

local function skyStart(tx, tz)
	local y = L.groundY(tx, tz)
	return tx - 700, y + 3000, tz - 450
end

local function starfall(api, unitID, h, r, x, z)
	local ult = cfg(h, "ult")
	local R = ult.radius or 750
	local count = api.val(ult.count, r)
	local dur = ult.duration or 8
	local dmg = api.val(ult.dmg, r) * api.power(h)
	local aoe = ult.aoe or 280
	local fx = L.fx(api)
	local f0 = api.frame()
	h.store.ultUntil = f0 + floor((dur + 4) * 30)
	fx.ring(x, z, { kind = "rune", r0 = R, r1 = R, color = L.a(C.STAR, 0.6), width = 24, ttl = 1.2, rot = 0.6 })
	fx.zone(x, z, { radius = R, pattern = "runes", color = L.a(C.STAR, 0.25), ttl = dur + 3, rot = 0.2 })
	api.active(unitID, "ult", dur + 3)
	local st = { n = 0, hits = 0, dmg = 0 }
	local every = max(3, floor(dur * 30 / count))
	L.task(h, every, dur, function()
		if st.n >= count then
			return false
		end
		st.n = st.n + 1
		local tx, tz
		local list = api.enemiesIn(x, z, R, h.ally)
		if #list > 0 and random() < 0.65 then
			tx, _, tz = api.pos(list[random(#list)])
			tx, tz = tx + (random() - 0.5) * 120, tz + (random() - 0.5) * 120
		else
			local a, d = random() * 6.283, sqrt(random()) * R
			tx, tz = x + cos(a) * d, z + sin(a) * d
		end
		local sx, sy, sz = skyStart(tx, tz)
		api.fire(h, "meteor", sx, sy, sz, tx, L.groundY(tx, tz), tz, {
			key = "ult", dmg = dmg, aoe = aoe, dtype = "plasma", gravity = 0,
			onHit = function(ix, iz, hits)
				local iy = L.groundY(ix, iz)
				fx.flash(ix, iy + 30, iz, { radius = 140, color = C.STAR, ttl = 0.35 })
				fx.ring(ix, iz, { kind = "shock", r0 = 20, r1 = aoe, color = L.a(C.STAR, 0.8), width = 24, ttl = 0.5 })
				placeStar(api, unitID, h, ix, iz)
				st.hits = st.hits + #hits
				st.dmg = st.dmg + #hits * dmg
			end,
		})
	end, function()
		if not L.alive(unitID) then
			return
		end
		-- the Comet
		local comet = api.val(ult.comet, r) * api.power(h)
		local caoe = ult.cometAoe or 600
		local sx, sy, sz = skyStart(x, z)
		local dist = sqrt((x - sx) ^ 2 + (L.groundY(x, z) - sy) ^ 2 + (z - sz) ^ 2)
		local flight = floor(dist / 1300 * 30)
		api.delay(max(1, flight - 12), function()
			fx.pillar(x, z, { radius = 200, height = 3000, color = { 0.8, 0.9, 1, 0.9 }, ttl = 0.5 })
		end)
		api.fire(h, "comet", sx, sy, sz, x, L.groundY(x, z), z, {
			key = "ult", dmg = comet, aoe = caoe, dtype = "plasma", gravity = 0,
			onHit = function(ix, iz, hits)
				local iy = L.groundY(ix, iz)
				fx.flash(ix, iy + 60, iz, { radius = 600, color = { 0.85, 0.9, 1, 1 }, ttl = 0.7 })
				fx.ring(ix, iz, { kind = "shock", r0 = 40, r1 = 900, color = L.a(C.STAR, 0.9), width = 70, ttl = 1.1 })
				fx.ring(ix, iz, { kind = "rune", r0 = 200, r1 = caoe, color = L.a(C.VOID, 0.7), width = 30, ttl = 1.5, rot = 2 })
				placeStar(api, unitID, h, ix, iz)
				api.log("legt4starfall ult comet rank=%d dmg=%d aoe=%d hit=%d", r, comet, caoe, #hits)
			end,
		})
		api.log("legt4starfall ult meteors rank=%d count=%d dmg=%d hits=%d total=%d", r, st.n, dmg, st.hits, st.dmg)
	end)
	api.log("legt4starfall ult starfall rank=%d count=%d dmg=%d", r, count, dmg)
	return true
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.stars = {}
	h.store.lenses = {}
	h.store.tasks = {}
	local ids = {}
	for _, w in pairs(h.def.weapons) do
		if w.key == "shocker_low" then
			ids[w.wdid] = true
		end
	end
	h.store.mainIds = ids
end

function M.frame(api, unitID, h, f)
	L.runTasks(h, f)
	if f % 15 == 0 then
		constellationTick(api, unitID, h, f)
		local keep = {}
		for _, l in ipairs(h.store.lenses) do
			if l.untilF > f then
				keep[#keep + 1] = l
			end
		end
		h.store.lenses = keep
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if not x then
		return false
	end
	if key == "a2" then
		return gravityLens(api, unitID, h, rank, x, z)
	elseif key == "a3" then
		return skyEye(api, unitID, h, rank, x, z)
	elseif key == "ult" then
		return starfall(api, unitID, h, rank, x, z)
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
		local n, cx, cz, heroes = L.cluster(api, x, z, a2.range, api.val(a2.radius, rank), h.ally, 3)
		if cx and (n >= 5 or (heroes > 0 and n >= 5)) then
			return cx, L.groundY(cx, cz), cz
		end
	elseif key == "a3" then
		local a3 = cfg(h, "a3")
		-- an enemy hero we lost sight of (its last radar / LOS position), else a big fight
		for _, uid in ipairs(api.enemiesIn(x, z, a3.range, h.ally)) do
			if api.isHero(uid) then
				local los = Spring.GetUnitLosState(uid, h.ally)
				if los and los.radar and not los.los then
					local ux, uy, uz = api.pos(uid)
					return ux, uy, uz
				end
			end
		end
		local n, cx, cz = L.cluster(api, x, z, a3.range, api.val(a3.radius, rank) * 0.5, h.ally, 3)
		if cx and n >= 10 then
			return cx, L.groundY(cx, cz), cz
		end
	elseif key == "ult" then
		local ult = cfg(h, "ult")
		local n, cx, cz, heroes = L.cluster(api, x, z, min(ult.range, api.weaponReach(h) * 1.3), ult.radius, h.ally, 3, 0.5)
		if cx and (n >= 8 or (heroes > 0 and n >= 6)) then
			return cx, L.groundY(cx, cz), cz
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	L.endTasks(h)
	for _, s in ipairs(h.store.stars or {}) do
		dropStar(api, h, s)
	end
	h.store.stars = {}
end

return M
