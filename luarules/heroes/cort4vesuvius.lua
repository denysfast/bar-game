-- Vesuvius, the Twin-Barrel (cort4vesuvius, corves x1.8) - doc/v19-heroes/roster_cor.md section 4. The human's
-- "twin-barrel tank with a rocket launcher": a twin plasma cannon (burst 2), two Banisher racks and a flamer.
--   a1 Twin Impact (passive): both shells of a pair landing within 150 resonate: an extra blast (250) and Shred on the
--      primary target (+5..15% damage taken for 5 s, stacks 3).
--   a2 Banisher Lock (active, unit in 1400): the racks ripple-fire 6..14 homing missiles over 2 s; +50% vs Shred.
--   a3 Siege Mode (toggle): up to 8..14 s immobile, -20% damage taken, +30..60% range; the shells become magma
--      copies (api.swapWeapons "magma") that leave lava pools. Cooldown 20 s from undeploy.
--   ult Eruption (active, map in 2400): 5..12 volcanic bombs in a high arc over 3 s, each leaves a 6 s lava pool;
--      then the ground erupts.

local L = VFS.Include("luarules/heroes/cort4_lib.lua")
local M = {}

local floor, max, min, sqrt, random, cos, sin = math.floor, math.max, math.min, math.sqrt, math.random, math.cos, math.sin

local FLARES = { "ban1Flare1", "ban2Flare1", "ban1Flare2", "ban2Flare2" }

local function b(h, key)
	return h.def.cfg[key]
end

local function cannon(h)
	local n = h.def.keyNum.corlevlr_weapon and h.def.keyNum.corlevlr_weapon[1]
	local w = n and h.def.weapons[n]
	if not w then
		return nil
	end
	local magma = h.def.copies.magma and h.def.copies.magma[w.wdid]
	return w.wdid, magma
end

---------------------------------------------------------------------------- lava pools (Siege Mode shells, Eruption)

local function lava(api, unitID, h, x, z, r, dps, seconds)
	local gy = L.gy(x, z)
	L.pool(api, h, unitID, x, z, r, dps, seconds, { pattern = "heat", color = { 1, 0.35, 0.05, 0.95 } })
	L.flash(api, x, gy + 10, z, { radius = r, color = { 1, 0.3, 0, 0.5 }, ttl = seconds })
	L.ring(api, x, z, { kind = "rune", r0 = r, r1 = r, width = 18, ttl = seconds, color = { 1, 0.45, 0.1, 0.6 }, rot = 0.4 })
end

---------------------------------------------------------------------------- a1 Twin Impact

local function shredFx(api, h, uid, stacks)
	h.store.shredFx = h.store.shredFx or {}
	local old = h.store.shredFx[uid]
	if old then
		L.detach(api, old)
	end
	h.store.shredFx[uid] = L.attach(api, uid, "mark", { color = { 0.85, 0.2, 0.1, 0.9 }, radius = L.radius(uid) + 30, stacks = stacks,
		max = 3, ttl = 5 })
end

local function resonate(api, unitID, h, x, z)
	local r = api.rank(h, "a1")
	local a1 = b(h, "a1")
	local dmg = api.val(a1.dmg, r) * api.power(h)
	local hits = api.area(x, z, a1.radius or 250, dmg, unitID, { dtype = "plasma" })
	local primary = api.nearestEnemies(x, z, a1.near or 150, h.ally, 1)[1]
	local stacks = 0
	if primary then
		stacks = api.mark(primary, "shred", a1.shredTime or 5, { vuln = api.val(a1.shred, r), max = a1.maxShred or 3, from = unitID })
		shredFx(api, h, primary, stacks)
	end
	local y = L.gy(x, z)
	L.flash(api, x, y + 30, z, { radius = 200, color = { 1, 0.85, 0.55, 1 }, ttl = 0.35 })
	L.ring(api, x, z, { kind = "hex", r0 = 60, r1 = 250, width = 24, ttl = 0.35, color = L.AMBER })
	h.store.resonances = (h.store.resonances or 0) + 1
	L.log(api, h, "a1 resonance rank=%d dmg=%d hit=%d shred=%d (total %d)", r, dmg, #hits, stacks, h.store.resonances)
end

local function shellImpact(api, unitID, h, magma, x, z)
	local f = api.frame()
	if api.rank(h, "a1") > 0 then
		local last = h.store.lastImp
		if last and f - last.f <= 14 and L.d2(last.x, last.z, x, z) <= (b(h, "a1").near or 150) ^ 2 then
			h.store.lastImp = nil
			resonate(api, unitID, h, (x + last.x) / 2, (z + last.z) / 2)
		else
			h.store.lastImp = { f = f, x = x, z = z }
		end
	end
	if magma and h.store.siege then
		local a3 = b(h, "a3")
		local r = max(1, api.rank(h, "a3"))
		lava(api, unitID, h, x, z, a3.poolRadius or 150, api.val(a3.pool, r) * api.power(h), a3.poolTime or 4)
	end
end

---------------------------------------------------------------------------- a2 Banisher Lock

local function banisherLock(api, unitID, h, r, targetID)
	local a2 = b(h, "a2")
	if not (targetID and L.alive(targetID)) or Spring.GetUnitAllyTeam(targetID) == h.ally then
		return false
	end
	local count = api.val(a2.count, r)
	local dmg = api.val(a2.dmg, r) * api.power(h)
	local aoe = a2.aoe or 128
	local bonus = a2.shredBonus or 0.5
	local st = { n = 0, hits = 0, bonus = 0, dealt = 0 }
	local tx0, _, tz0 = api.pos(targetID)
	L.ring(api, tx0, tz0, { kind = "hex", r0 = 150, r1 = 80, width = 16, ttl = 2, color = L.RED })
	L.attach(api, targetID, "mark", { color = L.RED, radius = L.radius(targetID) + 30, stacks = count, max = count, ttl = (a2.time or 2) + 1.5 })
	for i = 1, count do
		api.delay(floor((i - 1) * (a2.time or 2) * 30 / count) + 1, function()
			if not L.alive(unitID) then
				return
			end
			local piece = FLARES[(i - 1) % 4 + 1]
			local fx, fy, fz = api.piecePos(unitID, piece)
			local t = L.alive(targetID) and targetID or nil
			local tx, ty, tz
			if t then
				tx, ty, tz = api.pos(t)
			else
				tx, ty, tz = tx0, L.gy(tx0, tz0), tz0
			end
			-- launch up and outward, then home in
			local mx, mz = fx + (tx - fx) * 0.3, fz + (tz - fz) * 0.3
			L.flash(api, fx, fy, fz, { radius = 60, color = L.ORANGE, ttl = 0.2, ground = false })
			L.shot(api, h, unitID, "salvo", fx, fy, fz, mx, fy + 350, mz, 22, function(ix, iy, iz)
				local hits = api.area(ix, iz, aoe, dmg, unitID, { dtype = "rocket" })
				st.n, st.hits, st.dealt = st.n + 1, st.hits + #hits, st.dealt + dmg * #hits
				if L.alive(targetID) and api.marks(targetID, "shred") > 0 then
					local ux, _, uz = api.pos(targetID)
					if L.d2(ux, uz, ix, iz) <= (aoe + L.radius(targetID)) ^ 2 then
						api.damage(targetID, dmg * bonus, unitID, { dtype = "rocket" })
						st.bonus = st.bonus + dmg * bonus
					end
				end
				L.flash(api, ix, iy + 20, iz, { radius = 120, color = L.ORANGE, ttl = 0.3 })
				L.ring(api, ix, iz, { kind = "shock", r0 = 20, r1 = aoe * 1.2, width = 22, ttl = 0.3, color = L.col(L.ORANGE, 0.8) })
				if st.n == count then
					L.log(api, h, "a2 banisher lock rank=%d missiles=%d dmg=%d hits=%d shredBonus=%d", r, count, dmg, st.hits, st.bonus)
				end
			end, t)
		end)
	end
	api.forceTarget(unitID, targetID, a2.time or 2)
	return true
end

---------------------------------------------------------------------------- a3 Siege Mode

local function siegeOn(api, unitID, h, r)
	local a3 = b(h, "a3")
	if h.store.siege then
		return false
	end
	local dur = api.val(a3.duration, r)
	api.buff(unitID, h, "siege", nil, { immobile = true, armor = a3.armor or 0.2, range = api.val(a3.range, r) })
	api.swapWeapons(unitID, h, "magma")
	h.store.siege = { untilF = api.frame() + floor(dur * 30), fx = {
		L.attach(api, unitID, "aura", { radius = 180, color = L.col(L.ORANGE, 0.85), pattern = "heat" }),
		L.attach(api, unitID, "aura", { radius = 220, color = L.col(L.AMBER, 0.7), pattern = "runes" }),
		L.attach(api, unitID, "tint", { pattern = "heat", color = L.ORANGE, strength = 0.35 }),
	} }
	local x, _, z = api.pos(unitID)
	L.ring(api, x, z, { kind = "shock", r0 = 60, r1 = 260, width = 30, ttl = 0.4, color = L.AMBER })
	L.log(api, h, "a3 siege on rank=%d dur=%.1f range=+%.2f", r, dur, api.val(a3.range, r))
	return true
end

local function siegeOff(api, unitID, h)
	local s = h.store.siege
	h.store.siege = nil
	api.unbuff(unitID, h, "siege")
	api.swapWeapons(unitID, h, nil)
	if s then
		L.detachAll(api, s.fx)
	end
	L.log(api, h, "a3 siege off")
end

---------------------------------------------------------------------------- ult Eruption

local function eruption(api, unitID, h, r, x, z)
	local ult = b(h, "ult")
	if not x then
		return false
	end
	local hx, _, hz = api.pos(unitID)
	local cx, cz = L.toward(hx, hz, x, z, ult.range or 2400)
	local R = ult.radius or 500
	local count = api.val(ult.count, r)
	local p = api.power(h)
	local dmg = api.val(ult.dmg, r) * p
	local pool = api.val(ult.pool, r) * p
	local nova = api.val(ult.nova, r) * p
	local ally = h.ally
	local st = { n = 0, hits = 0 }
	local flight = 2.2
	L.ring(api, cx, cz, { kind = "hex", r0 = R * 1.15, r1 = R, width = 24, ttl = (ult.time or 3) + flight, color = L.col(L.ORANGE, 0.7) })
	for i = 1, count do
		api.delay(floor((i - 1) * (ult.time or 3) * 30 / count) + 1, function()
			if not L.alive(unitID) then
				return
			end
			local piece = i % 2 == 0 and "BarrelFlare1" or "BarrelFlare2"
			local fx, fy, fz = api.piecePos(unitID, piece)
			local a = random() * 6.283
			local d = R * sqrt(random())
			local tx, tz = L.clampX(cx + cos(a) * d), L.clampZ(cz + sin(a) * d)
			L.flash(api, fx, fy, fz, { radius = 110, color = L.ORANGE, ttl = 0.2, ground = false })
			L.lob(api, h, unitID, "volcanic", fx, fy, fz, tx, L.gy(tx, tz), tz, flight, function(ix, iy, iz)
				local hits = api.area(ix, iz, ult.aoe or 300, dmg, unitID, { dtype = "plasma", ally = ally })
				st.n, st.hits = st.n + 1, st.hits + #hits
				L.flash(api, ix, iy + 30, iz, { radius = 300, color = { 1, 0.55, 0.15, 1 }, ttl = 0.45 })
				L.ring(api, ix, iz, { kind = "shock", r0 = 50, r1 = 300, width = 40, ttl = 0.45, color = L.ORANGE })
				if L.alive(unitID) then
					lava(api, unitID, h, ix, iz, ult.poolRadius or 220, pool, ult.poolTime or 6)
				end
			end, 1.0)
		end)
	end
	api.delay(floor(((ult.time or 3) + flight) * 30) + 12, function()
		local hits = api.area(cx, cz, ult.novaRadius or 450, nova, unitID, { dtype = "plasma", ally = ally })
		L.pillar(api, cx, cz, { radius = 220, height = 1800, color = { 1, 0.35, 0.05, 0.9 }, ttl = 1.5 })
		L.ring(api, cx, cz, { kind = "shock", r0 = 100, r1 = 700, width = 80, ttl = 0.6, color = L.ORANGE })
		L.ring(api, cx, cz, { kind = "fire", r0 = 60, r1 = ult.novaRadius or 450, width = 120, ttl = 1.2, color = L.col(L.LAVA, 0.95) })
		L.flash(api, cx, L.gy(cx, cz) + 60, cz, { radius = 600, color = { 1, 0.6, 0.25, 1 }, ttl = 0.6 })
		L.log(api, h, "ult eruption nova=%d hit=%d (bombs %d x %d, %d hits)", nova, #hits, st.n, dmg, st.hits)
	end)
	api.active(unitID, "ult", (ult.time or 3) + flight + 1)
	L.log(api, h, "ult cast rank=%d bombs=%d dmg=%d pool=%d nova=%d", r, count, dmg, pool, nova)
	return true
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.siege = nil
	h.store.lastImp = nil
end

function M.impact(api, unitID, h, weaponDefID, x, y, z, projectileID)
	if L.impact(api, unitID, h, weaponDefID, x, y, z, projectileID) then
		return
	end
	local base, magma = cannon(h)
	if weaponDefID == base or (magma and weaponDefID == magma) then
		shellImpact(api, unitID, h, weaponDefID == magma, x, z)
	end
end

function M.frame(api, unitID, h, f)
	L.tick(api, unitID, h, f)
	local s = h.store.siege
	if s then
		if f >= s.untilF then
			api.toggleOff(unitID, h, "a3")
		elseif (h.ai or h.autocast) and f % 30 == 0 then
			local x, _, z = api.pos(unitID)
			local close = false
			for _, uid in ipairs(L.enemies(api, h, x, z, 500)) do
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
		siegeOff(api, unitID, h)
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a2" then
		return banisherLock(api, unitID, h, rank, targetID)
	elseif key == "a3" then
		return siegeOn(api, unitID, h, rank)
	elseif key == "ult" then
		return eruption(api, unitID, h, rank, x, z)
	end
	return false
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	if key == "a2" then
		local range = b(h, "a2").range or 1400
		local t = L.mostValuable(api, h, x, z, range, nil, function(uid)
			return L.isStructure(uid)
		end)
		t = t or L.enemyHero(api, h, x, z, range)
		if not t then
			local best, cost = L.mostValuable(api, h, x, z, range)
			if best and cost >= 1500 then
				t = best
			end
		end
		if t then
			local tx, ty, tz = api.pos(t)
			return tx, ty, tz, t
		end
	elseif key == "a3" then
		if h.store.siege then
			return nil
		end
		local reach = api.weaponReach(h)
		local ext = reach * (1 + api.val(b(h, "a3").range, rank))
		for _, uid in ipairs(L.enemies(api, h, x, z, 600)) do
			if not L.isStructure(uid) and not L.isAir(uid) then
				return nil
			end
		end
		local far, structures = 0, 0
		for _, uid in ipairs(L.enemies(api, h, x, z, ext)) do
			local ux, _, uz = api.pos(uid)
			if L.d2(ux, uz, x, z) > reach * reach then
				far = far + 1
				if L.isStructure(uid) then
					structures = structures + 1
				end
			end
		end
		if structures >= 1 or far >= 2 then
			return x, y, z
		end
	elseif key == "ult" then
		local ult = b(h, "ult")
		local metal, cx, cz = api.bestCluster(x, z, ult.range or 2400, ult.radius or 500, h.ally)
		if cx and metal >= 15000 then
			return cx, L.gy(cx, cz), cz
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	if h.store.siege then
		L.detachAll(api, h.store.siege.fx)
		h.store.siege = nil
	end
end

return M
