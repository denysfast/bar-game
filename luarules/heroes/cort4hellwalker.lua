-- Hellwalker, the Inferno (cort4hellwalker, cordemon x2) - doc/v19-heroes/roster_cor.md section 2.
--   a1 Combustion (passive): every 0.5 s in the Maw's flame an enemy gains 1 Heat (max 10, -1/s). At 10 it combusts:
--      8% of its max HP (capped) + flat damage, the flat damage and +5 Heat to the enemies within 200 (chains).
--   a2 Hellcharge (active, map): dashes 700..1100 through the line: damage, knock-aside, +5 Heat; the path burns as a
--      fire wall for 5 s; then +30% flame range for 3 s.
--   a3 Infernal Furnace (active, self): inhales 1.5 s pulling enemies in, then a fire nova (+5 Heat).
--   ult Hell on Earth (active, self): x1.25, +25% speed; burns everything around, double Heat, 2 meteors a second on
--      random enemies within 1200; erupts at the end.

local L = VFS.Include("luarules/heroes/cort4_lib.lua")
local M = {}

local floor, max, min, sqrt, random = math.floor, math.max, math.min, math.sqrt, math.random

local FIRE = { 1, 0.5, 0.12, 1 }

local function b(h, key)
	return h.def.cfg[key]
end

---------------------------------------------------------------------------- a1 Combustion (Heat)

local function heatOf(h, uid, f)
	local e = h.store.heat[uid]
	if not e then
		return 0, nil
	end
	local a1 = b(h, "a1")
	local v = max(0, e.v - (f - e.t) / 30 * (a1.decay or 1))
	e.v, e.t = v, f
	return v, e
end

local combust

-- add Heat to an enemy; combusts at the maximum (queued, so chains resolve in order)
local function addHeat(api, unitID, h, uid, n, f)
	if api.rank(h, "a1") <= 0 or not L.alive(uid) then
		return
	end
	local a1 = b(h, "a1")
	local v, e = heatOf(h, uid, f)
	if not e then
		e = { v = 0, t = f, gain = -99 }
		h.store.heat[uid] = e
	end
	e.v = min(a1.maxHeat or 10, v + n)
	if e.v >= (a1.maxHeat or 10) and not e.boom then
		e.boom = true
		local q = h.store.boomQ
		q[#q + 1] = uid
	end
end

combust = function(api, unitID, h, uid, f)
	local a1 = b(h, "a1")
	local r = api.rank(h, "a1")
	h.store.heat[uid] = nil
	if not L.alive(uid) then
		return
	end
	local x, y, z = api.pos(uid)
	local p = api.power(h)
	local flat = api.val(a1.flat, r) * p
	local own = min(api.val(a1.cap, r), (a1.pct or 0.08) * L.maxHp(api, uid)) * p + flat
	api.damage(uid, own, unitID, { dtype = "flame" })
	local n = 0
	for _, o in ipairs(api.enemiesIn(x, z, a1.radius or 200, h.ally)) do
		if o ~= uid then
			api.damage(o, flat, unitID, { dtype = "flame" })
			addHeat(api, unitID, h, o, a1.spread or 5, f)
			n = n + 1
		end
	end
	L.flash(api, x, y + 25, z, { radius = 180, color = { 1, 0.75, 0.25, 1 }, ttl = 0.4 })
	L.ring(api, x, z, { kind = "shock", r0 = 30, r1 = 200, width = 30, ttl = 0.35, color = FIRE })
	L.pillar(api, x, z, { radius = 40, height = 250, color = L.col(FIRE, 0.9), ttl = 0.4, ring = false })
	h.store.booms = (h.store.booms or 0) + 1
	L.log(api, h, "a1 combust rank=%d own=%d flat=%d spread=%d (total %d)", r, own, flat, n, h.store.booms)
end

local function processBooms(api, unitID, h, f)
	local q = h.store.boomQ
	local n = 0
	while #q > 0 and n < 24 do
		local uid = table.remove(q, 1)
		combust(api, unitID, h, uid, f)
		n = n + 1
	end
end

---------------------------------------------------------------------------- a2 Hellcharge

local function hellcharge(api, unitID, h, r, x, z)
	local a2 = b(h, "a2")
	if not x then
		return false
	end
	local hx, hy, hz = api.pos(unitID)
	local range = api.val(a2.range, r)
	local tx, tz = L.toward(hx, hz, x, z, range)
	if L.d2(tx, tz, hx, hz) < 100 * 100 then
		return false
	end
	local dmg = api.val(a2.dmg, r) * api.power(h)
	local hit = {}
	local n = 0
	local dist = sqrt(L.d2(tx, tz, hx, hz))
	local secs = dist / 1400
	local trail = L.attach(api, unitID, "trail", { color = FIRE, width = 120, length = 0.6, ttl = secs + 0.4 })
	local tint = L.attach(api, unitID, "tint", { pattern = "heat", color = FIRE, strength = 0.8, ttl = secs + 0.5 })
	local ok = api.dash(unitID, h, tx, tz, { speed = 1400, onStep = function(px, pz)
		for _, uid in ipairs(api.enemiesIn(px, pz, 150, h.ally)) do
			if not hit[uid] then
				hit[uid] = true
				n = n + 1
				api.damage(uid, dmg, unitID, { dtype = "flame" })
				api.push(uid, px, pz, 120, 0.3)
				addHeat(api, unitID, h, uid, a2.heat or 5, api.frame())
				local ux, uy, uz = api.pos(uid)
				L.flash(api, ux, uy + 20, uz, { radius = 90, color = FIRE, ttl = 0.3 })
			end
		end
	end, onLand = function(lx, lz)
		L.detach(api, trail)
		L.detach(api, tint)
		local wall = api.val(a2.wall, r) * api.power(h)
		local wt = a2.wallTime or 5
		local p = L.pool(api, h, unitID, hx, hz, 45, wall, wt, { line = { hx, hz, lx, lz }, noFx = true })
		L.beam(api, hx, L.gy(hx, hz) + 6, hz, lx, L.gy(lx, lz) + 6, lz, { color = { 1, 0.3, 0.06, 1 }, width = 80, ttl = wt, pulse = 1.5, flare = 0.2 })
		L.beam(api, hx, L.gy(hx, hz) + 10, hz, lx, L.gy(lx, lz) + 10, lz, { color = { 1, 0.75, 0.3, 1 }, width = 26, ttl = wt, pulse = 3, flare = 0.1 })
		p.onTick = function()
			for _ = 1, 2 do
				local s = random()
				local px, pz = hx + (lx - hx) * s, hz + (lz - hz) * s
				L.flash(api, px, L.gy(px, pz) + 15, pz, { radius = 70, color = FIRE, ttl = 0.6 })
			end
		end
		L.ring(api, lx, lz, { kind = "shock", r0 = 50, r1 = 350, width = 40, ttl = 0.45, color = FIRE })
		api.buff(unitID, h, "hellcharge", 3, { range = a2.flameRange or 0.3 })
		L.log(api, h, "a2 hellcharge rank=%d dist=%d dmg=%d hit=%d wall=%d", r, dist, dmg, n, wall)
	end })
	if not ok then
		L.detach(api, trail)
		L.detach(api, tint)
	end
	return ok
end

---------------------------------------------------------------------------- a3 Infernal Furnace

local function furnace(api, unitID, h, r)
	local a3 = b(h, "a3")
	local x, y, z = api.pos(unitID)
	local R = api.val(a3.radius, r)
	local inhale = a3.inhale or 1.5
	local pulled = {}
	for _, uid in ipairs(api.enemiesIn(x, z, R, h.ally)) do
		if api.pull(uid, x, z, a3.pull or 200, inhale) then
			pulled[#pulled + 1] = uid
		end
	end
	L.ring(api, x, z, { kind = "rune", r0 = R, r1 = 80, width = 36, ttl = inhale, color = L.ORANGE, rot = -2 })
	L.ring(api, x, z, { kind = "swirl", r0 = R, r1 = 60, width = 90, ttl = inhale, color = L.col(FIRE, 0.6), rot = -3 })
	local glow = L.attach(api, unitID, "tint", { pattern = "heat", color = FIRE, strength = 0.9, ttl = inhale + 0.3 })
	for k = 0, floor(inhale / 0.3) - 1 do
		api.delay(k * 9 + 1, function()
			local hx, hy, hz = api.pos(unitID)
			if not hx then
				return
			end
			for i = 1, min(16, #pulled) do
				local uid = pulled[i]
				if L.alive(uid) then
					local ux, uy, uz = api.pos(uid)
					L.bolt(api, ux, uy + 20, uz, hx, hy + 60, hz, { color = FIRE, width = 3, ttl = 0.25, jitter = 0.15, branches = 0 })
				end
			end
		end)
	end
	api.delay(floor(inhale * 30), function()
		L.detach(api, glow)
		if not L.alive(unitID) then
			return
		end
		local hx, hy, hz = api.pos(unitID)
		local dmg = api.val(a3.dmg, r) * api.power(h)
		local hits = api.area(hx, hz, R, dmg, unitID, { dtype = "flame" })
		local f = api.frame()
		for _, uid in ipairs(hits) do
			addHeat(api, unitID, h, uid, a3.heat or 5, f)
		end
		L.flash(api, hx, hy + 40, hz, { radius = 600, color = { 1, 0.6, 0.2, 1 }, ttl = 0.5 })
		L.ring(api, hx, hz, { kind = "shock", r0 = 60, r1 = R, width = 60, ttl = 0.5, color = FIRE })
		L.ring(api, hx, hz, { kind = "fire", r0 = 40, r1 = R * 0.95, width = 120, ttl = 0.8, color = FIRE })
		L.log(api, h, "a3 furnace rank=%d radius=%d pulled=%d dmg=%d hit=%d", r, R, #pulled, dmg, #hits)
	end)
	api.active(unitID, "a3", inhale)
	return true
end

---------------------------------------------------------------------------- ult Hell on Earth

local function meteor(api, unitID, h, hell)
	local x, _, z = api.pos(unitID)
	local list = L.enemies(api, h, x, z, hell.meteorRange)
	local t = list[random(1, max(1, #list))]
	local tx, tz
	if t then
		tx, _, tz = api.pos(t)
	else
		local a = random() * 6.283
		local d = 200 + random() * (hell.meteorRange - 200)
		tx, tz = L.clampX(x + math.cos(a) * d), L.clampZ(z + math.sin(a) * d)
	end
	L.drop(api, h, unitID, "meteor", tx, tz, 1500, 45, function(ix, iy, iz)
		local hits = api.area(ix, iz, hell.meteorAoe, hell.meteor, unitID, { dtype = "flame" })
		local f = api.frame()
		for _, uid in ipairs(hits) do
			addHeat(api, unitID, h, uid, 2, f)
		end
		L.flash(api, ix, L.gy(ix, iz) + 30, iz, { radius = 200, color = { 1, 0.6, 0.2, 1 }, ttl = 0.45 })
		L.ring(api, ix, iz, { kind = "shock", r0 = 30, r1 = hell.meteorAoe * 1.3, width = 34, ttl = 0.4, color = FIRE })
		L.ring(api, ix, iz, { kind = "fire", r0 = 20, r1 = hell.meteorAoe, width = 60, ttl = 0.9, color = L.col(FIRE, 0.9) })
		hell.meteors = hell.meteors + 1
		hell.dealt = hell.dealt + #hits * hell.meteor
	end)
end

local function hellOn(api, unitID, h, r)
	local ult = b(h, "ult")
	if h.store.hell then
		return false
	end
	local dur = api.val(ult.duration, r)
	local R = api.val(ult.radius, r)
	local f = api.frame()
	local p = api.power(h)
	local hell = { untilF = f + floor(dur * 30), R = R, burn = api.val(ult.burn, r) * p, meteor = api.val(ult.meteor, r) * p,
		meteorAoe = ult.meteorAoe or 200, meteorRange = ult.meteorRange or 1200, nova = api.val(ult.nova, r) * p,
		novaRadius = ult.novaRadius or 600, nextMeteor = f + 10, meteors = 0, dealt = 0, burned = 0, r = r }
	hell.fx = {
		L.attach(api, unitID, "aura", { radius = R, color = L.col(L.ORANGE, 0.6), pattern = "heat", ttl = dur }),
		L.attach(api, unitID, "aura", { radius = R * 0.55, color = L.col(FIRE, 0.7), pattern = "fire", ttl = dur }),
		L.attach(api, unitID, "electric", { color = L.ORANGE, intensity = 0.7, ttl = dur }),
		L.attach(api, unitID, "tint", { pattern = "heat", color = FIRE, strength = 0.75, ttl = dur }),
		L.attach(api, unitID, "trail", { color = FIRE, width = 70, length = 0.7, ttl = dur }),
	}
	h.store.hell = hell
	api.buff(unitID, h, "hell", dur, { scale = ult.scale or 1.25, speed = ult.speed or 0.25 })
	api.active(unitID, "ult", dur)
	local x, y, z = api.pos(unitID)
	L.flash(api, x, y + 50, z, { radius = 400, color = FIRE, ttl = 0.5 })
	L.ring(api, x, z, { kind = "fire", r0 = 60, r1 = R, width = 100, ttl = 0.8, color = FIRE })
	L.log(api, h, "ult hell on earth rank=%d dur=%.1f radius=%d burn=%d meteor=%d", r, dur, R, hell.burn, hell.meteor)
	return true
end

local function hellEnd(api, unitID, h)
	local hell = h.store.hell
	h.store.hell = nil
	if not hell then
		return
	end
	L.detachAll(api, hell.fx)
	if not L.alive(unitID) then
		return
	end
	local x, y, z = api.pos(unitID)
	local hits = api.area(x, z, hell.novaRadius, hell.nova, unitID, { dtype = "flame" })
	L.pillar(api, x, z, { radius = 250, height = 1500, color = { 1, 0.45, 0.1, 0.95 }, ttl = 1.2 })
	L.ring(api, x, z, { kind = "shock", r0 = 80, r1 = hell.novaRadius, width = 80, ttl = 0.6, color = FIRE })
	L.ring(api, x, z, { kind = "fire", r0 = 60, r1 = hell.novaRadius, width = 140, ttl = 1.2, color = FIRE })
	L.flash(api, x, y + 60, z, { radius = 700, color = { 1, 0.7, 0.35, 1 }, ttl = 0.6 })
	L.log(api, h, "ult eruption nova=%d hit=%d meteors=%d meteorDmg=%d burned=%d", hell.nova, #hits, hell.meteors, hell.dealt, hell.burned)
end

local function hellFrame(api, unitID, h, f)
	local hell = h.store.hell
	if f >= hell.untilF then
		hellEnd(api, unitID, h)
		return
	end
	local x, _, z = api.pos(unitID)
	if f % 15 == 0 then
		local hits = api.area(x, z, hell.R, hell.burn * 0.5, unitID, { dtype = "flame" })
		hell.burned = hell.burned + #hits * hell.burn * 0.5
		for _, uid in ipairs(hits) do
			addHeat(api, unitID, h, uid, 1, f)
		end
	end
	if f >= hell.nextMeteor then
		hell.nextMeteor = f + 15
		meteor(api, unitID, h, hell)
	end
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.heat = {}
	h.store.boomQ = {}
	h.store.hell = nil
end

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	if not isParalyzer and damage > 0 and api.rank(h, "a1") > 0 and api.damageType(weaponDefID) == "flame" then
		local f = api.frame()
		local _, e = heatOf(h, victimID, f)
		if not e or f - e.gain >= 15 then
			addHeat(api, unitID, h, victimID, h.store.hell and 2 or 1, f)
			local ne = h.store.heat[victimID]
			if ne then
				ne.gain = f
			end
		end
	end
	return damage
end

function M.frame(api, unitID, h, f)
	L.tick(api, unitID, h, f)
	if #h.store.boomQ > 0 then
		processBooms(api, unitID, h, f)
	end
	if h.store.hell then
		hellFrame(api, unitID, h, f)
	end
	if f % 30 == 0 then
		local n = 0
		for uid in pairs(h.store.heat) do
			local v = heatOf(h, uid, f)
			if not L.alive(uid) or v <= 0 then
				h.store.heat[uid] = nil
			elseif v >= 7 and n < 20 then
				n = n + 1
				local x, y, z = api.pos(uid)
				L.flash(api, x, y + 20, z, { radius = 40 + 6 * v, color = L.RED, ttl = 0.3 })
			end
		end
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a2" then
		return hellcharge(api, unitID, h, rank, x, z)
	elseif key == "a3" then
		return furnace(api, unitID, h, rank)
	elseif key == "ult" then
		return hellOn(api, unitID, h, rank)
	end
	return false
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	local hpf = L.hpFrac(unitID)
	if key == "a2" then
		local range = api.val(b(h, "a2").range, rank)
		if hpf < 0.3 then
			local ex, ez = L.escapePoint(api, h, unitID, range)
			if ex then
				return ex, L.gy(ex, ez), ez
			end
			return nil
		end
		local metal, cx, cz = api.bestCluster(x, z, range * 0.8, 250, h.ally)
		if cx and metal > 0 then
			local tx, tz = L.toward(x, z, cx, cz, 99999)
			local dx, dz = cx - x, cz - z
			local d = max(1, sqrt(dx * dx + dz * dz))
			tx, tz = L.clampX(x + dx / d * range), L.clampZ(z + dz / d * range)
			local crossed = api.line(x, z, tx, tz, 200, 0, unitID)
			if #crossed >= 3 then
				return tx, L.gy(tx, tz), tz
			end
		end
	elseif key == "a3" then
		local R = api.val(b(h, "a3").radius, rank)
		local cost, n = api.enemyCostNear(x, z, R, h.ally)
		if hpf > 0.3 and (n >= 6 or cost >= 4000) then
			return x, y, z
		end
	elseif key == "ult" then
		if h.store.hell then
			return nil
		end
		local cost = api.enemyCostNear(x, z, 900, h.ally)
		if (hpf > 0.4 and cost >= 20000) or L.enemyHero(api, h, x, z, 700) then
			return x, y, z
		end
	end
	return nil
end

function M.impact(api, unitID, h, weaponDefID, x, y, z, projectileID)
	L.impact(api, unitID, h, weaponDefID, x, y, z, projectileID)
end

function M.destroyed(api, unitID, h)
	if h.store.hell then
		L.detachAll(api, h.store.hell.fx)
		h.store.hell = nil
	end
end

return M
