-- Medusa, the Gorgon (legt4medusa) - v19 Legion hero module (doc/v19-heroes/roster_leg.md section 10).
--   a1 Serpent Bite (passive): missile hits add Petrify stacks (6 s; each slows); at 5 the target turns to stone:
--      stunned (heroes half, at most once per 8 s), takes more damage from everyone (api.mark vuln), grey tint;
--      afterwards immune to Petrify for 6 s.
--   a2 Gorgon's Gaze (map, a direction): a 1.5 s sweep over a cone - every enemy in it gains Petrify stacks;
--      enemies already stone shatter (a share of max HP + splash around).
--   a3 Snake Pit (map): serpents circle a point and bite the enemies in it (once a second each, + 1 Petrify).
--   ult Stone Garden (map): after 1.5 s everything in the area turns to stone (structures too) and takes more damage;
--      when the stone ends every statue shatters.
local L = VFS.Include("luarules/heroes/legt4_lib.lua")
local C = L.C
local M = {}

local max, min, floor, sqrt, random, cos, sin, atan2, abs, pi = math.max, math.min, math.floor, math.sqrt, math.random, math.cos, math.sin, math.atan2, math.abs, math.pi
local PETRIFY, STONE = "legt4medusa_petrify", "legt4medusa_stone"

local function cfg(h, key)
	return h.def.cfg[key]
end

---------------------------------------------------------------------------- stone and shatter

local function isStone(h, uid, f)
	local s = h.store.stone[uid]
	return s and s.untilF > f
end

-- turn a unit to stone for `seconds` with `vuln` more damage taken; onEnd(uid) when it ends (a shatter)
local function petrify(api, unitID, h, uid, seconds, vuln, onEnd)
	if not L.alive(uid) then
		return false
	end
	local f = api.frame()
	local hero = api.isHero(uid)
	if hero then
		if f < (h.store.heroIcd[uid] or 0) then
			return false
		end
		h.store.heroIcd[uid] = f + floor((cfg(h, "a1").heroIcd or 8) * 30)
	end
	local fx = L.fx(api)
	local secs = hero and seconds * 0.5 or seconds
	api.stun(uid, seconds, unitID) -- heroes: half, by the core
	api.mark(uid, STONE, secs, { vuln = vuln, stacks = 1, max = 1, from = unitID })
	api.mark(uid, PETRIFY, 0, {})
	local old = h.store.stone[uid]
	if old then
		for _, id in ipairs(old.ids) do
			fx.detach(id)
		end
	end
	local s = { untilF = f + floor(secs * 30), onEnd = onEnd, ids = {
		fx.attach(uid, "tint", { pattern = "stone", color = C.STONE, strength = 1, ttl = secs + 0.2 }),
		fx.attach(uid, "electric", { color = C.STONE, intensity = 0.3, ttl = secs + 0.2 }),
	} }
	h.store.stone[uid] = s
	L.markOff(api, h.store.petFx, uid)
	return true
end

local function shatter(api, unitID, h, uid, pct, heroPct, cap, splash, splashR)
	if not L.alive(uid) then
		return 0
	end
	local x, y, z = api.pos(uid)
	local hero = api.isHero(uid)
	local d = (hero and heroPct or pct) * L.effMaxHp(api, uid)
	if not hero then
		d = min(cap or 40000, d)
	end
	api.damage(uid, d, unitID, { dtype = "rail" })
	local sp = splash * api.power(h)
	local n = 0
	for _, vid in ipairs(api.enemiesIn(x, z, splashR, h.ally)) do
		if vid ~= uid then
			api.damage(vid, sp, unitID, { dtype = "rail" })
			n = n + 1
		end
	end
	local fx = L.fx(api)
	fx.flash(x, y + 30, z, { radius = 120, color = C.STONE, ttl = 0.25 })
	fx.ring(x, z, { kind = "shock", r0 = 20, r1 = splashR, color = L.a(C.STONE, 0.9), width = 20, ttl = 0.4 })
	for k = 1, 3 do
		local a = random() * 6.283
		fx.bolt(x, y + 30, z, x + cos(a) * 110, y + 10, z + sin(a) * 110, { color = C.STONE, width = 3, branches = 0, ttl = 0.2 })
	end
	local s = h.store.stone[uid]
	if s then
		h.store.stone[uid] = nil
		api.mark(uid, STONE, 0, {})
		for _, id in ipairs(s.ids) do
			fx.detach(id)
		end
	end
	return d + n * sp
end

---------------------------------------------------------------------------- a1 Serpent Bite

local function addPetrify(api, unitID, h, uid, n)
	local r = api.rank(h, "a1")
	if r <= 0 or not L.alive(uid) then
		return
	end
	local a1 = cfg(h, "a1")
	local f = api.frame()
	if isStone(h, uid, f) or f < (h.store.immune[uid] or 0) then
		return
	end
	local need = a1.need or 5
	local cur = api.marks(uid, PETRIFY)
	local stacks = min(need, cur + n)
	api.mark(uid, PETRIFY, a1.duration or 6, { stacks = stacks - cur, max = need, slow = api.val(a1.slow, r) * stacks, from = unitID })
	if stacks >= need then
		local secs = api.val(a1.stone, r)
		if petrify(api, unitID, h, uid, secs, api.val(a1.vuln, r)) then
			h.store.immune[uid] = f + floor((secs + (a1.immune or 6)) * 30)
			h.store.stoned = (h.store.stoned or 0) + 1
			api.log("legt4medusa a1 stone %s for %.1f s (+%d%% damage taken)", tostring(uid), secs, floor(api.val(a1.vuln, r) * 100))
		end
	else
		L.markOn(api, h.store.petFx, uid, "aura", { radius = max(40, L.radius(uid) * 0.7), color = L.a(C.GORGON, 0.1 * stacks + 0.1), pattern = "runes" }, a1.duration or 6)
	end
end

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	if not isParalyzer and damage > 0 and h.store.missileIds[weaponDefID] then
		addPetrify(api, unitID, h, victimID, 1)
	end
	return damage
end

---------------------------------------------------------------------------- a2 Gorgon's Gaze

local function angleDiff(a, b)
	local d = (a - b) % (2 * pi)
	if d > pi then
		d = d - 2 * pi
	end
	return d
end

local function gaze(api, unitID, h, r, x, z)
	local a2 = cfg(h, "a2")
	local hx, hy, hz = api.pos(unitID)
	local dir = atan2(z - hz, x - hx)
	local range = api.val(a2.range, r)
	local half = math.rad(api.val(a2.angle, r)) * 0.5
	local stacks = api.val(a2.stacks, r)
	local nBeams = 7 + floor((r - 1) / 4.5)
	local fx = L.fx(api)
	local hy60 = hy + 60
	fx.ring(hx, hz, { kind = "rune", r0 = 120, r1 = 120, color = L.a(C.GORGON, 0.8), width = 16, ttl = 1.6, rot = 3 })
	fx.ring(hx, hz, { kind = "fog", r0 = 60, r1 = range, color = L.a(C.GORGON, 0.25), width = 30, ttl = 1.7, arc = half * 2, angle = dir })
	local done, st = {}, { stacked = 0, shattered = 0, dmg = 0 }
	for i = 0, nBeams - 1 do
		api.delay(1 + floor(i * 45 / max(1, nBeams - 1)), function()
			local px, py, pz = api.pos(unitID)
			if not px then
				return
			end
			local a = dir - half + (2 * half) * i / max(1, nBeams - 1)
			local ex, ez = px + cos(a) * range, pz + sin(a) * range
			fx.beam(px, py + 60, pz, ex, L.groundY(ex, ez) + 20, ez, { color = L.a(C.GORGON, 0.6), width = 14, ttl = 0.6, pulse = 3, flare = 0.8 })
			fx.beam(px, py + 60, pz, ex, L.groundY(ex, ez) + 20, ez, { color = { 0.85, 1, 0.9, 0.8 }, width = 4, ttl = 0.4, pulse = 5, flare = 0 })
			-- the sector swept so far
			local f = api.frame()
			local lo = dir - half
			local hi = a
			for _, uid in ipairs(api.enemiesIn(px, pz, range, h.ally)) do
				if not done[uid] then
					local ux, _, uz = api.pos(uid)
					local ua = atan2(uz - pz, ux - px)
					local da = angleDiff(ua, lo)
					if da >= -0.05 and da <= angleDiff(hi, lo) + 0.05 then
						done[uid] = true
						if isStone(h, uid, f) then
							st.dmg = st.dmg + shatter(api, unitID, h, uid, api.val(a2.shatterPct, r), api.val(a2.heroPct, r), a2.cap, api.val(a2.splash, r), a2.splashRadius or 150)
							st.shattered = st.shattered + 1
						else
							addPetrify(api, unitID, h, uid, stacks)
							st.stacked = st.stacked + 1
						end
					end
				end
			end
			if i == nBeams - 1 then
				api.log("legt4medusa a2 gaze rank=%d range=%d angle=%d stacks=%d hit=%d shattered=%d dmg=%d", r, range, api.val(a2.angle, r), stacks, st.stacked, st.shattered, st.dmg)
			end
		end)
	end
	return true
end

---------------------------------------------------------------------------- a3 Snake Pit

local function snakePit(api, unitID, h, r, x, z)
	local a3 = cfg(h, "a3")
	local n = api.val(a3.serpents, r)
	local R = api.val(a3.radius, r)
	local dur = api.val(a3.duration, r)
	local dmg = api.val(a3.dmg, r) * api.power(h)
	local fx = L.fx(api)
	local orb = { color = C.GORGON, radius = 14, height = 60, orbit = R * 0.85, speed = 0.3, count = n, crackle = 2, ttl = dur }
	local ids = {
		fx.attachPoint(x, z, "orb", orb),
		fx.ring(x, z, { kind = "rune", r0 = R, r1 = R, color = L.a(C.GORGON, 0.4), width = 16, ttl = dur, rot = 0.5 }),
		fx.zone(x, z, { radius = R, pattern = "web", color = L.a(C.GORGON, 0.2), ttl = dur }),
	}
	local orbPointPos = api.fx and api.fx.orbPointPos
	local bitten = {}
	local st = { bites = 0, dmg = 0 }
	L.task(h, 15, dur, function(f)
		local list = api.enemiesIn(x, z, R, h.ally)
		local budget = max(1, floor(n / 2 + 0.5))
		local k = 0
		for _, uid in ipairs(list) do
			if budget <= 0 then
				break
			end
			if (bitten[uid] or 0) <= f then
				bitten[uid] = f + 30
				budget = budget - 1
				k = k + 1
				local ux, uy, uz = api.pos(uid)
				local sx, sy, sz
				if orbPointPos then
					sx, sy, sz = orbPointPos(x, z, orb, f, (st.bites + k) % n)
				end
				sx, sy, sz = sx or x, sy or L.groundY(x, z) + 60, sz or z
				fx.bolt(sx, sy, sz, ux, uy + 20, uz, { color = C.GORGON, width = 4, jitter = 0.2, branches = 0, ttl = 0.15 })
				api.damage(uid, dmg, unitID, { dtype = "rocket" })
				addPetrify(api, unitID, h, uid, 1)
				st.dmg = st.dmg + dmg
			end
		end
		st.bites = st.bites + k
	end, function()
		api.log("legt4medusa a3 snake pit over rank=%d serpents=%d bites=%d dmg=%d", r, n, st.bites, st.dmg)
	end)
	api.log("legt4medusa a3 snake pit rank=%d serpents=%d radius=%d dur=%.1f bite=%d", r, n, R, dur, dmg)
	return true
end

---------------------------------------------------------------------------- ult Stone Garden

local function stoneGarden(api, unitID, h, r, x, z)
	local ult = cfg(h, "ult")
	local R = api.val(ult.radius, r)
	local fx = L.fx(api)
	local y = L.groundY(x, z)
	fx.ring(x, z, { kind = "rune", r0 = R, r1 = R, color = L.a(C.GORGON, 0.8), width = 20, ttl = 1.5, rot = 1 })
	fx.ring(x, z, { kind = "shock", r0 = R, r1 = R * 0.1, color = L.a(C.GORGON, 0.5), width = 24, ttl = 1.5 })
	fx.zone(x, z, { radius = R, pattern = "runes", color = L.a(C.GORGON, 0.2), ttl = 1.5 })
	api.delay(45, function()
		local secs = api.val(ult.stone, r)
		local vuln = api.val(ult.vuln, r)
		fx.pillar(x, z, { radius = 100, height = 1500, color = L.a(C.GORGON, 0.6), ttl = 0.4 })
		fx.flash(x, y + 40, z, { radius = R, color = L.a(C.STONE, 0.9), ttl = 0.4 })
		fx.ring(x, z, { kind = "shock", r0 = 0, r1 = R, color = C.STONE, width = 50, ttl = 0.6 })
		local st = { stoned = 0, dmg = 0, shattered = 0 }
		local pct, heroPct, cap = api.val(ult.shatterPct, r), api.val(ult.heroPct, r), ult.cap
		local splash, splashR = api.val(ult.splash, r), ult.splashRadius or 200
		for _, uid in ipairs(api.enemiesIn(x, z, R, h.ally)) do
			-- the garden ignores the heroes' once-per-8-s guard of Serpent Bite (it is the ultimate)
			h.store.heroIcd[uid] = nil
			if petrify(api, unitID, h, uid, secs, vuln, function(vid)
				st.dmg = st.dmg + shatter(api, unitID, h, vid, pct, heroPct, cap, splash, splashR)
				st.shattered = st.shattered + 1
			end) then
				st.stoned = st.stoned + 1
			end
		end
		api.delay(floor(secs * 30) + 2, function()
			api.log("legt4medusa ult stone garden over rank=%d radius=%d stoned=%d shattered=%d dmg=%d", r, R, st.stoned, st.shattered, st.dmg)
		end)
		api.log("legt4medusa ult stone garden rank=%d radius=%d stone=%.1f s vuln=%.2f stoned=%d", r, R, secs, vuln, st.stoned)
	end)
	api.active(unitID, "ult", 1.5 + api.val(ult.stone, r))
	return true
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.tasks = {}
	h.store.stone = {}
	h.store.immune = {}
	h.store.heroIcd = {}
	h.store.petFx = {}
	local ids = {}
	for _, w in pairs(h.def.weapons) do
		if w.key == "legmed_missile" then
			ids[w.wdid] = true
		end
	end
	h.store.missileIds = ids
end

function M.frame(api, unitID, h, f)
	L.runTasks(h, f)
	for uid, s in pairs(h.store.stone) do
		if s.untilF <= f or not L.alive(uid) then
			h.store.stone[uid] = nil
			local fx = L.fx(api)
			for _, id in ipairs(s.ids) do
				fx.detach(id)
			end
			if s.onEnd and L.alive(uid) then
				s.onEnd(uid)
			end
		end
	end
	if f % 30 == 0 then
		L.markSweep(api, h.store.petFx, f)
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if not x then
		return false
	end
	if key == "a2" then
		return gaze(api, unitID, h, rank, x, z)
	elseif key == "a3" then
		return snakePit(api, unitID, h, rank, x, z)
	elseif key == "ult" then
		return stoneGarden(api, unitID, h, rank, x, z)
	end
	return false
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	local f = api.frame()
	if key == "a2" then
		local a2 = cfg(h, "a2")
		local range = api.val(a2.range, rank)
		local half = math.rad(api.val(a2.angle, rank)) * 0.5
		local list = L.enemies(api, x, z, range, h.ally, true)
		local best, bestA
		for i = 1, #list, max(1, floor(#list / 16)) do
			local ux, _, uz = api.pos(list[i])
			local a = atan2(uz - z, ux - x)
			local score, heroes = 0, 0
			for _, vid in ipairs(list) do
				local vx, _, vz = api.pos(vid)
				if abs(angleDiff(atan2(vz - z, vx - x), a)) <= half then
					score = score + (isStone(h, vid, f) and 2 or 1)
					if api.isHero(vid) then
						heroes = heroes + 1
					end
				end
			end
			if heroes > 0 and score >= 2 then
				score = score + 10
			end
			if not best or score > best then
				best, bestA = score, a
			end
		end
		if best and best >= 3 then
			local tx, tz = x + cos(bestA) * 600, z + sin(bestA) * 600
			return tx, L.groundY(tx, tz), tz
		end
	elseif key == "a3" then
		local a3 = cfg(h, "a3")
		local R = api.val(a3.radius, rank)
		local n, cx, cz = L.cluster(api, x, z, a3.range, R, h.ally, 3)
		if cx and n >= 3 then
			return cx, L.groundY(cx, cz), cz
		end
		-- defensive: between Medusa and a group closing in
		local ex, ez, ne = L.centroid(api, x, z, 1200, h.ally)
		if ex and ne >= 2 then
			local px, pz = (x + ex) / 2, (z + ez) / 2
			return px, L.groundY(px, pz), pz
		end
	elseif key == "ult" then
		local ult = cfg(h, "ult")
		local R = api.val(ult.radius, rank)
		local n, cx, cz, heroes = L.cluster(api, x, z, ult.range, R, h.ally, 1)
		if cx and (n >= 6 or (heroes > 0 and n >= 4)) then
			return cx, L.groundY(cx, cz), cz
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	L.endTasks(h)
	local fx = L.fx(api)
	for uid, s in pairs(h.store.stone or {}) do
		for _, id in ipairs(s.ids) do
			fx.detach(id)
		end
	end
	h.store.stone = {}
	L.markClear(api, h.store.petFx or {})
end

return M
