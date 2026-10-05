-- Negotiator, the Last Argument (cort4negotiator, corvroc x3) - v23, the eleventh Cortex hero.
-- Numbers: luarules/configs/heroes/cor.lua (cort4negotiator). API: header of luarules/gadgets/unit_t4_heroes.lua.
-- Back-line rocket artillery: its whole damage is scaled by T4.heroBalance dmgScale (1/3, like Armageddon).
--   a1 Target Lock (passive): a starburst rocket hit Locks the enemy for 4..8 s: +4..12% damage taken from every
--      source and it stays revealed. Missile Volley deals +25% to a Locked target.
--   a2 Missile Volley (active, unit in 1800..2300 - never past the starburst range): 4..10 homing rockets ripple
--      over 2 s at one target, each in a 120 blast.
--   a3 Siege Deploy (toggle): up to 8..14 s braced on its jacks - immobile, -15% damage taken, +10..25% range,
--      +15..35% fire rate. Cast again to pack up; cooldown 20 s from then.
--   ult Saturation Barrage (active, map in 2000..2300): a 2.5 s painted warning circle (450..600), then 20..48
--      rockets rain on it over 5 s; every enemy hit is Locked.

local L = VFS.Include("luarules/heroes/cort4_lib.lua")
local M = {}

local floor, max, sqrt, random, cos, sin = math.floor, math.max, math.sqrt, math.random, math.cos, math.sin

local LOCK = { 1, 0.3, 0.15, 1 }

local function b(h, key)
	return h.def.cfg[key]
end

local function rocketInfo(h)
	local n = h.def.keyNum.cortruck_rocket and h.def.keyNum.cortruck_rocket[1]
	return n and h.def.weapons[n]
end

---------------------------------------------------------------------------- a1 Target Lock

local function lock(api, unitID, h, victimID)
	local r = api.rank(h, "a1")
	if r <= 0 or not L.alive(victimID) then
		return
	end
	local a1 = b(h, "a1")
	local dur = api.val(a1.duration, r)
	local fresh = api.marks(victimID, "lock") == 0
	api.mark(victimID, "lock", dur, { vuln = api.val(a1.vuln, r), from = unitID, reveal = true })
	if fresh then
		L.attach(api, victimID, "mark", { color = LOCK, radius = L.radius(victimID) + 30, stacks = 1, max = 1, ttl = dur })
	end
end

---------------------------------------------------------------------------- a2 Missile Volley

local function volley(api, unitID, h, r, targetID)
	local a2 = b(h, "a2")
	if not (targetID and L.alive(targetID)) or Spring.GetUnitAllyTeam(targetID) == h.ally then
		return false
	end
	local hx, _, hz = api.pos(unitID)
	local tx0, _, tz0 = api.pos(targetID)
	local range = api.val(a2.range, r)
	if L.d2(hx, hz, tx0, tz0) > range * range then
		return false
	end
	local count = api.val(a2.count, r)
	local dmg = api.val(a2.dmg, r) * api.power(h)
	local aoe = a2.aoe or 120
	local bonus = a2.lockBonus or 0.25
	local time = a2.time or 2
	local st = { n = 0, hits = 0, bonus = 0 }
	L.ring(api, tx0, tz0, { kind = "hex", r0 = 160, r1 = 80, width = 16, ttl = time, color = LOCK })
	for i = 1, count do
		api.delay(floor((i - 1) * time * 30 / count) + 1, function()
			if not L.alive(unitID) then
				return
			end
			local fx, fy, fz = api.pos(unitID)
			fy = fy + 60
			local t = L.alive(targetID) and targetID or nil
			local tx, tz = tx0, tz0
			if t then
				tx, _, tz = api.pos(t)
			end
			-- launch steeply, then home in
			local mx, mz = fx + (tx - fx) * 0.25, fz + (tz - fz) * 0.25
			L.flash(api, fx, fy, fz, { radius = 60, color = L.ORANGE, ttl = 0.2, ground = false })
			L.shot(api, h, unitID, "volley", fx, fy, fz, mx, fy + 450, mz, 22, function(ix, iy, iz)
				local hits = api.area(ix, iz, aoe, dmg, unitID, { dtype = "rocket" })
				st.n, st.hits = st.n + 1, st.hits + #hits
				if L.alive(targetID) and api.marks(targetID, "lock") > 0 then
					local ux, _, uz = api.pos(targetID)
					if L.d2(ux, uz, ix, iz) <= (aoe + L.radius(targetID)) ^ 2 then
						api.damage(targetID, dmg * bonus, unitID, { dtype = "rocket" })
						st.bonus = st.bonus + dmg * bonus
					end
				end
				L.flash(api, ix, iy + 20, iz, { radius = 110, color = L.ORANGE, ttl = 0.3 })
				L.ring(api, ix, iz, { kind = "shock", r0 = 20, r1 = aoe * 1.2, width = 22, ttl = 0.3, color = L.col(L.ORANGE, 0.8) })
				if st.n == count then
					L.log(api, h, "a2 volley rank=%d rockets=%d dmg=%d hits=%d lockBonus=%d", r, count, dmg, st.hits, st.bonus)
				end
			end, t)
		end)
	end
	api.forceTarget(unitID, targetID, time)
	return true
end

---------------------------------------------------------------------------- a3 Siege Deploy

local function deployOn(api, unitID, h, r)
	local a3 = b(h, "a3")
	if h.store.deploy then
		return false
	end
	local dur = api.val(a3.duration, r)
	api.buff(unitID, h, "deploy", nil, { immobile = true, armor = a3.armor or 0.15, range = api.val(a3.range, r),
		reload = api.val(a3.reload, r) })
	h.store.deploy = { untilF = api.frame() + floor(dur * 30), fx = {
		L.attach(api, unitID, "aura", { radius = 170, color = L.col(L.AMBER, 0.75), pattern = "runes" }),
		L.attach(api, unitID, "tint", { pattern = "rim", color = L.AMBER, strength = 0.3 }),
	} }
	local x, _, z = api.pos(unitID)
	L.ring(api, x, z, { kind = "shock", r0 = 60, r1 = 240, width = 30, ttl = 0.4, color = L.AMBER })
	L.log(api, h, "a3 deploy on rank=%d dur=%.1f range=+%.2f reload=+%.2f", r, dur, api.val(a3.range, r), api.val(a3.reload, r))
	return true
end

local function deployOff(api, unitID, h)
	local s = h.store.deploy
	h.store.deploy = nil
	api.unbuff(unitID, h, "deploy")
	if s then
		L.detachAll(api, s.fx)
	end
	L.log(api, h, "a3 deploy off")
end

---------------------------------------------------------------------------- ult Saturation Barrage

local function barrage(api, unitID, h, r, x, z)
	local ult = b(h, "ult")
	if not x then
		return false
	end
	local hx, _, hz = api.pos(unitID)
	local cx, cz = L.toward(hx, hz, x, z, api.val(ult.range, r))
	local R = api.val(ult.radius, r)
	local warn = ult.warn or 2.5
	local dur = ult.duration or 5
	local count = api.val(ult.count, r)
	local dmg = api.val(ult.dmg, r) * api.power(h)
	local aoe = ult.aoe or 160
	local ally = h.ally
	local st = { rockets = 0, hits = 0 }
	-- the warning everyone sees: a painted circle and a target beam from the sky
	L.ring(api, cx, cz, { kind = "rune", r0 = R, r1 = R, width = 30, ttl = warn + dur + 0.5, color = L.col(LOCK, 0.6), rot = 0.2 })
	L.ring(api, cx, cz, { kind = "hex", r0 = R * 1.15, r1 = R, width = 20, ttl = warn, color = L.col(LOCK, 0.85) })
	L.pillar(api, cx, cz, { radius = 35, height = 1800, color = L.col(LOCK, 0.9), ttl = warn + 0.3, ring = true })
	for i = 1, count do
		api.delay(floor(warn * 30 + (i - 1) * dur * 30 / count) + 1, function()
			local a = random() * 6.283
			local d = R * sqrt(random())
			local px, pz = L.clampX(cx + cos(a) * d), L.clampZ(cz + sin(a) * d)
			L.drop(api, h, unitID, "barrage", px, pz, 1800, 55, function(ix, iy, iz)
				local hits = api.area(ix, iz, aoe, dmg, unitID, { dtype = "rocket", ally = ally })
				st.rockets = st.rockets + 1
				st.hits = st.hits + #hits
				if L.alive(unitID) then
					for _, uid in ipairs(hits) do
						lock(api, unitID, h, uid)
					end
				end
				L.flash(api, ix, iy + 25, iz, { radius = 130, color = L.ORANGE, ttl = 0.3 })
				L.ring(api, ix, iz, { kind = "shock", r0 = 20, r1 = aoe, width = 22, ttl = 0.3, color = L.col(L.ORANGE, 0.8) })
				if st.rockets == count then
					L.log(api, h, "ult barrage done rockets=%d x %d hits=%d", count, dmg, st.hits)
				end
			end, 0.2)
		end)
	end
	api.active(unitID, "ult", warn + dur + 1)
	L.log(api, h, "ult saturation barrage rank=%d count=%d dmg=%d radius=%d at %d,%d", r, count, dmg, R, cx, cz)
	return true
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.deploy = nil
end

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	local w = rocketInfo(h)
	if w and weaponDefID == w.wdid and not isParalyzer then
		lock(api, unitID, h, victimID)
	end
	return damage
end

function M.impact(api, unitID, h, weaponDefID, x, y, z, projectileID)
	L.impact(api, unitID, h, weaponDefID, x, y, z, projectileID)
end

function M.frame(api, unitID, h, f)
	L.tick(api, unitID, h, f)
	local s = h.store.deploy
	if s then
		if f >= s.untilF then
			api.toggleOff(unitID, h, "a3")
		elseif (h.ai or h.autocast) and f % 30 == 0 then
			local x, _, z = api.pos(unitID)
			local close = false
			for _, uid in ipairs(L.enemies(api, h, x, z, 600)) do
				if not L.isStructure(uid) and not L.isAir(uid) then
					close = true
					break
				end
			end
			if close or L.hpFrac(unitID) < 0.4 then
				api.toggleOff(unitID, h, "a3")
			end
		end
	end
end

function M.toggleOff(api, unitID, h, key, rank)
	if key == "a3" then
		deployOff(api, unitID, h)
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a2" then
		return volley(api, unitID, h, rank, targetID)
	elseif key == "a3" then
		return deployOn(api, unitID, h, rank)
	elseif key == "ult" then
		return barrage(api, unitID, h, rank, x, z)
	end
	return false
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	if key == "a2" then
		local range = api.val(b(h, "a2").range, rank)
		local t = L.enemyHero(api, h, x, z, range)
		if not t then
			local best, cost = L.mostValuable(api, h, x, z, range)
			if best and cost >= 2000 then
				t = best
			end
		end
		if t then
			local tx, ty, tz = api.pos(t)
			return tx, ty, tz, t
		end
	elseif key == "a3" then
		if h.store.deploy then
			return nil
		end
		for _, uid in ipairs(L.enemies(api, h, x, z, 800)) do
			if not L.isStructure(uid) and not L.isAir(uid) then
				return nil
			end
		end
		local reach = api.weaponReach(h)
		local n = 0
		for _, uid in ipairs(L.enemies(api, h, x, z, reach * (1 + api.val(b(h, "a3").range, rank)))) do
			if not L.isAir(uid) then
				n = n + 1
			end
		end
		if n >= 3 then
			return x, y, z
		end
	elseif key == "ult" then
		local ult = b(h, "ult")
		local R = api.val(ult.radius, rank)
		local metal, cx, cz = api.bestCluster(x, z, api.val(ult.range, rank), R, h.ally)
		if cx and (metal >= 15000 or L.enemyHero(api, h, cx, cz, R)) then
			return cx, L.gy(cx, cz), cz
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	if h.store.deploy then
		L.detachAll(api, h.store.deploy.fx)
		h.store.deploy = nil
	end
end

return M
