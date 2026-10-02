-- Helios, the Sunbringer (legt4helios) - v19 Legion hero module (doc/v19-heroes/roster_leg.md section 1; API: header of
-- luarules/gadgets/unit_t4_heroes.lua). Numbers per rank: legt4helios in luarules/configs/heroes/leg.lua.
--   a1 Solar Heat (passive): heat-ray hits add Heat (once per 0.2 s per target, decays 4 s after the last stack); every
--      stack = more damage taken from Helios; 10 Heat = Ignite (blast in a radius, spreads Heat on -> chains).
--   a2 Corona Flare (self): burst around Helios - damage + Heat to enemies, heals allies (heroes 50%).
--   a3 Sunspot (map): a small sun hovers over the point, lashing enemies under it every 0.5 s; ignitions extend it.
--   ult Sunstrike (map): 0.8 s warning, a creeping column of sunlight for 6 s, then a Collapse igniting heated enemies.
local L = VFS.Include("luarules/heroes/legt4_lib.lua")
local C = L.C
local M = {}

local max, min, floor, sqrt, random = math.max, math.min, math.floor, math.sqrt, math.random
local HEAT_EVERY = 6 -- frames: one Heat per target per 0.2 s

local function cfg(h, key)
	return h.def.cfg[key]
end

---------------------------------------------------------------------------- a1 Solar Heat

local function heatOf(h, uid)
	local e = h.store.heat[uid]
	return e and e.n or 0
end

-- damage multiplier of everything Helios does to a target
local function heatMult(api, h, uid)
	local r = api.rank(h, "a1")
	if r <= 0 then
		return 1
	end
	return 1 + api.val(cfg(h, "a1").perStack, r) * heatOf(h, uid)
end

local function heatFx(api, h, uid, e)
	if e.n >= 5 then
		local rad = max(50, L.radius(uid) * 0.9)
		L.markOn(api, h.store.heatFx, uid, "aura", { radius = rad, color = L.a(C.EMBER, 0.15 + 0.06 * e.n), pattern = "heat" })
	else
		L.markOff(api, h.store.heatFx, uid)
	end
end

-- add n Heat to an enemy (abilities ignore the 0.2 s limit); 10 queues an ignition
local function addHeat(api, h, uid, n, f)
	if api.rank(h, "a1") <= 0 or not L.alive(uid) then
		return
	end
	local a1 = cfg(h, "a1")
	local e = h.store.heat[uid]
	if not e then
		e = { n = 0, immune = 0 }
		h.store.heat[uid] = e
	end
	e.last = f
	if f < e.immune then
		return
	end
	e.n = min(a1.maxHeat or 10, e.n + n)
	if e.n >= (a1.maxHeat or 10) then
		h.store.igniteQ[uid] = true
	end
	heatFx(api, h, uid, e)
end

-- the hero's ability damage to one enemy: x ability power, x its Heat
local function hurt(api, unitID, h, uid, base, opts)
	local d = base * api.power(h) * heatMult(api, h, uid)
	api.damage(uid, d, unitID, opts or { dtype = "flame" })
	return d
end

-- ignite: a blast around the target; every enemy in it takes flat + pct of its max HP (capped, heroes half) and
-- gains Heat; scale = share of the full blast (the Collapse ignites by stacks / 10)
local function ignite(api, unitID, h, uid, scale)
	local r = api.rank(h, "a1")
	if r <= 0 or not L.alive(uid) then
		return 0
	end
	local a1 = cfg(h, "a1")
	local f = api.frame()
	local e = h.store.heat[uid] or { n = 0, immune = 0 }
	h.store.heat[uid] = e
	if f < (e.immune or 0) then
		return 0
	end
	scale = scale or 1
	local x, y, z = api.pos(uid)
	local radius = api.val(a1.igniteRadius, r)
	local flat, pct, cap = api.val(a1.igniteFlat, r), api.val(a1.ignitePct, r), api.val(a1.igniteCap, r)
	local spread = api.val(a1.spread, r)
	local power = api.power(h)
	local fx = L.fx(api)
	fx.flash(x, y + 30, z, { radius = 120 + 100 * (r - 1) / 9, color = C.SOLAR, ttl = 0.35 })
	fx.ring(x, z, { kind = "shock", r0 = 40, r1 = radius, color = L.a(C.EMBER, 0.9), width = 18, ttl = 0.5 })
	fx.ring(x, z, { kind = "fire", r0 = 20, r1 = radius * 0.9, color = C.EMBER, ttl = 0.6 })
	e.n = 0
	e.immune = f + floor((a1.immune or 5) * 30)
	L.markOff(api, h.store.heatFx, uid)
	local total, n = 0, 0
	for _, vid in ipairs(api.enemiesIn(x, z, radius, h.ally)) do
		local d = min(cap, flat + pct * L.effMaxHp(api, vid)) * power * scale
		if api.isHero(vid) then
			d = d * 0.5
		end
		d = d * heatMult(api, h, vid)
		api.damage(vid, d, unitID, { dtype = "flame" })
		total, n = total + d, n + 1
		if vid ~= uid then
			local vx, vy, vz = api.pos(vid)
			if vx then
				fx.beam(x, y + 30, z, vx, vy + 25, vz, { color = L.a(C.EMBER, 0.8), width = 6, ttl = 0.25, flare = 0.6 })
			end
			addHeat(api, h, vid, spread, f)
		end
	end
	-- an ignition under a Sunspot makes it last longer
	for _, s in ipairs(h.store.spots) do
		if not s.task.dead and L.d2(s.x, s.z, x, z) <= s.radius * s.radius and s.ext < s.extMax then
			s.ext = s.ext + 1
			s.task.stop = s.task.stop + 30
		end
	end
	h.store.ignites = (h.store.ignites or 0) + 1
	api.log("legt4helios a1 ignite rank=%d target=%s scale=%.2f radius=%d hit=%d dmg=%d", r, tostring(uid), scale, radius, n, total)
	return total
end

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	if isParalyzer or damage <= 0 then
		return damage
	end
	local m = heatMult(api, h, victimID)
	if h.store.heatIds[weaponDefID] and api.rank(h, "a1") > 0 then
		local f = api.frame()
		local e = h.store.heat[victimID]
		if not e or not e.lastAdd or f - e.lastAdd >= HEAT_EVERY then
			addHeat(api, h, victimID, 1, f)
			e = h.store.heat[victimID]
			if e then
				e.lastAdd = f
			end
		end
	end
	return damage * m
end

---------------------------------------------------------------------------- a2 Corona Flare

local function corona(api, unitID, h, r)
	local a2 = cfg(h, "a2")
	local x, y, z = api.pos(unitID)
	local radius = api.val(a2.radius, r)
	local fx = L.fx(api)
	local f = api.frame()
	fx.flash(x, y + 60, z, { radius = 300 + 150 * (r - 1) / 9, color = C.SOLAR, ttl = 0.4 })
	fx.ring(x, z, { kind = "shock", r0 = 60, r1 = radius, color = L.a(C.EMBER, 0.9), width = 40, ttl = 0.6 })
	fx.ring(x, z, { kind = "rune", r0 = radius * 0.3, r1 = radius, color = L.a(C.SOLAR, 0.6), width = 26, ttl = 1.2, rot = 0.8 })
	fx.ring(x, z, { kind = "fire", r0 = radius * 0.2, r1 = radius, color = C.EMBER, ttl = 0.7 })
	fx.pillar(x, z, { radius = 120, height = 900, color = L.a(C.SOLAR, 0.6), ttl = 0.5 })
	local dmg, total, n = api.val(a2.dmg, r), 0, 0
	local heat = api.val(a2.heat, r)
	for _, uid in ipairs(api.enemiesIn(x, z, radius, h.ally)) do
		total = total + hurt(api, unitID, h, uid, dmg)
		addHeat(api, h, uid, heat, f)
		n = n + 1
	end
	local heal, healed, hn = api.val(a2.heal, r) * api.power(h), 0, 0
	for _, uid in ipairs(api.alliesIn(x, z, radius, h.ally)) do
		local hp, maxHp, _, _, bp = Spring.GetUnitHealth(uid)
		if hp and bp and bp >= 1 and hp < maxHp then
			healed = healed + (api.heal(uid, api.isHero(uid) and heal * 0.5 or heal) or 0)
			hn = hn + 1
			if hn <= 12 then
				L.unitFlash(api, uid, 60, C.SOLAR, 0.3)
			end
		end
	end
	api.log("legt4helios a2 corona rank=%d radius=%d enemies=%d dmg=%d allies=%d heal=%d", r, radius, n, total, hn, heal)
	return true
end

---------------------------------------------------------------------------- a3 Sunspot

local SUN_H = 220

local function sunspot(api, unitID, h, r, x, z)
	local a3 = cfg(h, "a3")
	local radius = api.val(a3.radius, r)
	local dur = api.val(a3.duration, r)
	local fx = L.fx(api)
	local gy = L.groundY(x, z)
	local orbOpts = { color = C.SOLAR, radius = 46, height = SUN_H, orbit = 0, crackle = 6 }
	local s = { x = x, z = z, radius = radius, ext = 0, extMax = a3.extendMax or 6, dmg = 0, lashes = 0 }
	s.orb = fx.attachPoint(x, z, "orb", orbOpts)
	s.halo = fx.attachPoint(x, z, "orb", { color = L.a(C.EMBER, 0.6), radius = 18, height = SUN_H, orbit = 70, speed = 0.6, count = 3, crackle = 2 })
	s.zone = fx.zone(x, z, { radius = radius, pattern = "heat", color = L.a(C.EMBER, 0.35) })
	s.rune = fx.ring(x, z, { kind = "rune", r0 = radius, r1 = radius, color = L.a(C.EMBER, 0.45), width = 22, ttl = dur + 6, rot = 0.3 })
	fx.flash(x, gy + SUN_H, z, { radius = 160, color = C.SOLAR, ttl = 0.5, ground = false })
	local targets = api.val(a3.targets, r)
	local dmg = api.val(a3.dmg, r)
	s.task = L.task(h, 15, dur, function(f)
		local list = L.enemies(api, x, z, radius, h.ally, false)
		-- prefer the hottest, then random
		table.sort(list, function(a, b) return heatOf(h, a) > heatOf(h, b) end)
		local sy = gy + SUN_H
		fx.flash(x, sy, z, { radius = 90, color = L.a(C.SOLAR, 0.9), ttl = 0.6, ground = false })
		for i = 1, min(targets, #list) do
			local uid = list[i]
			local ux, uy, uz = api.pos(uid)
			fx.beam(x, sy, z, ux, uy + 20, uz, { color = L.a(C.EMBER, 0.9), width = 10, ttl = 0.3, pulse = 4, flare = 0.8 })
			s.dmg = s.dmg + hurt(api, unitID, h, uid, dmg)
			addHeat(api, h, uid, 1, f)
			s.lashes = s.lashes + 1
		end
	end, function()
		for _, id in ipairs({ s.orb, s.halo, s.zone, s.rune }) do
			fx.detach(id)
		end
		api.log("legt4helios a3 sunspot over rank=%d lashes=%d dmg=%d extended=%d", r, s.lashes, s.dmg, s.ext)
	end)
	h.store.spots[#h.store.spots + 1] = s
	api.log("legt4helios a3 sunspot rank=%d radius=%d dur=%d targets=%d dmg=%d", r, radius, dur, targets, dmg)
	return true
end

---------------------------------------------------------------------------- ult Sunstrike

local function sunstrike(api, unitID, h, r, x, z)
	local ult = cfg(h, "ult")
	local R = api.val(ult.radius, r)
	local tick = api.val(ult.tick, r)
	local dur = ult.duration or 6
	local fx = L.fx(api)
	local s = { x = x, z = z, dmg = 0, ticks = 0 }
	fx.ring(x, z, { kind = "rune", r0 = R, r1 = R, color = L.a(C.SOLAR, 0.7), width = 26, ttl = 0.9, rot = 1.5 })
	fx.ring(x, z, { kind = "shock", r0 = R * 1.6, r1 = R * 0.2, color = L.a(C.SOLAR, 0.5), width = 20, ttl = 0.8 })
	api.swapWeapons(unitID, h, "corona")
	api.active(unitID, "ult", dur + 0.8)
	local step = (ult.creep or 90) * 0.2
	L.task(h, 6, dur, function(f, t)
		-- creep toward the hottest enemy near, else the centroid
		local best, bh
		for _, uid in ipairs(api.enemiesIn(s.x, s.z, 1200, h.ally)) do
			local hv = heatOf(h, uid)
			if hv > 0 and (not bh or hv > bh) then
				best, bh = uid, hv
			end
		end
		local tx, tz
		if best then
			tx, _, tz = api.pos(best)
		else
			tx, tz = L.centroid(api, s.x, s.z, 900, h.ally)
		end
		if tx then
			local dx, dz = tx - s.x, tz - s.z
			local d = sqrt(dx * dx + dz * dz)
			if d > 1 then
				local k = min(step, d) / d
				s.x, s.z = s.x + dx * k, s.z + dz * k
			end
		end
		local n = (f - t.start) / 6
		fx.pillar(s.x, s.z, { radius = R * 0.7, height = 2400, color = L.a(C.SOLAR, 0.18), ttl = 0.24, ring = n % 3 == 0 })
		fx.pillar(s.x, s.z, { radius = R * 0.25, height = 2600, color = L.a(C.WHITEGOLD, 0.35), ttl = 0.24, ring = false })
		if n % 3 == 0 then
			fx.ring(s.x, s.z, { kind = "shock", r0 = R * 0.3, r1 = R, color = L.a(C.EMBER, 0.7), width = 30, ttl = 0.6 })
		end
		if n % 5 == 0 then
			fx.ring(s.x, s.z, { kind = "fire", r0 = R * 0.4, r1 = R * 1.05, color = L.a(C.EMBER, 0.7), ttl = 1.1 })
		end
		for _, uid in ipairs(api.enemiesIn(s.x, s.z, R, h.ally)) do
			s.dmg = s.dmg + hurt(api, unitID, h, uid, tick)
			addHeat(api, h, uid, 1, f)
		end
		s.ticks = s.ticks + 1
	end, function()
		api.swapWeapons(unitID, h, nil)
		if not L.alive(unitID) then
			return
		end
		-- Collapse: every heated enemy within 900 ignites by stacks / 10
		local cx, cz = s.x, s.z
		local cr = ult.collapse or 900
		fx.flash(cx, L.groundY(cx, cz) + 60, cz, { radius = cr * 0.45, color = { 1, 0.95, 0.75, 0.7 }, ttl = 0.6 })
		fx.ring(cx, cz, { kind = "shock", r0 = 60, r1 = cr, color = L.a(C.SOLAR, 0.95), width = 60, ttl = 0.9 })
		fx.ring(cx, cz, { kind = "fire", r0 = 100, r1 = cr, color = C.EMBER, ttl = 1.2 })
		fx.pillar(cx, cz, { radius = R * 0.8, height = 3000, color = L.a(C.WHITEGOLD, 0.6), ttl = 0.5 })
		local ign, idmg = 0, 0
		for _, uid in ipairs(api.enemiesIn(cx, cz, cr, h.ally)) do
			local hv = heatOf(h, uid)
			if hv > 0 then
				idmg = idmg + ignite(api, unitID, h, uid, hv / 10)
				ign = ign + 1
			end
		end
		api.log("legt4helios ult sunstrike over rank=%d radius=%d ticks=%d dmg=%d collapse ignites=%d dmg=%d", r, R, s.ticks, s.dmg, ign, idmg)
	end, 24)
	api.log("legt4helios ult sunstrike rank=%d radius=%d tick=%d", r, R, tick)
	return true
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.heat = {}
	h.store.heatFx = {}
	h.store.igniteQ = {}
	h.store.spots = {}
	h.store.tasks = {}
	local ids = {}
	for _, w in pairs(h.def.weapons) do
		if w.key == "heatray1" then
			ids[w.wdid] = true
		end
	end
	for _, map in pairs(h.def.copies or {}) do
		for base, copy in pairs(map) do
			if ids[base] then
				ids[copy] = true
			end
		end
	end
	h.store.heatIds = ids
end

function M.frame(api, unitID, h, f)
	-- ignitions queued by the hits
	for uid in pairs(h.store.igniteQ) do
		h.store.igniteQ[uid] = nil
		ignite(api, unitID, h, uid, 1)
	end
	L.runTasks(h, f)
	if f % 15 == 0 then
		local a1 = cfg(h, "a1")
		local decay = floor((a1.decay or 4) * 30)
		for uid, e in pairs(h.store.heat) do
			if not L.alive(uid) or (f - (e.last or 0) > decay and f >= (e.immune or 0)) then
				h.store.heat[uid] = nil
				L.markOff(api, h.store.heatFx, uid)
			end
		end
		local keep = {}
		for _, s in ipairs(h.store.spots) do
			if s.task.stop and f < s.task.stop then
				keep[#keep + 1] = s
			end
		end
		h.store.spots = keep
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a2" then
		return corona(api, unitID, h, rank)
	elseif key == "a3" and x then
		return sunspot(api, unitID, h, rank, x, z)
	elseif key == "ult" and x then
		return sunstrike(api, unitID, h, rank, x, z)
	end
	return false
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	if key == "a2" then
		local R = api.val(cfg(h, "a2").radius, rank)
		local near = L.enemies(api, x, z, R * 0.8, h.ally, true)
		if #near >= 4 or #L.enemyHeroes(api, x, z, R * 0.8, h.ally) > 0 then
			return x, y, z
		end
		local hurtAllies = 0
		for _, uid in ipairs(api.alliesIn(x, z, R, h.ally)) do
			if uid ~= unitID and L.hpFrac(uid) < 0.7 then
				hurtAllies = hurtAllies + 1
			end
		end
		if hurtAllies >= 3 then
			return x, y, z
		end
	elseif key == "a3" then
		local a3 = cfg(h, "a3")
		local n, cx, cz = L.cluster(api, x, z, a3.range, api.val(a3.radius, rank) * 0.8, h.ally, 3)
		if cx and n >= 3 then
			return cx, L.groundY(cx, cz), cz
		end
	elseif key == "ult" then
		local ult = cfg(h, "ult")
		local n, cx, cz, heroes = L.cluster(api, x, z, ult.range, 450, h.ally, 1)
		if cx and (n >= 6 or (heroes > 0 and n >= 4)) then
			return cx, L.groundY(cx, cz), cz
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	L.endTasks(h)
	L.markClear(api, h.store.heatFx or {})
	api.swapWeapons(unitID, h, nil)
end

return M
