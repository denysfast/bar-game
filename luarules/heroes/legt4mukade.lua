-- Mukade, the Great Centipede (legt4mukade) - v19 Legion hero module (doc/v19-heroes/roster_leg.md section 7).
--   a1 Burrow (map): dives (0.6 s), travels underground to the point (buff `hidden`: untargetable, unseen, no
--      collision, weapons off; a moving mound is the tell), then erupts: damage + stun around.
--   a2 Venom Rails (passive): rail hits inject Venom for 4 s - a share of the target's CURRENT HP per second (min /
--      max per second, heroes half; the strongest application wins and refreshes). A venomed unit that dies leaves
--      an acid pool for 4 s.
--   a3 Molting (passive, internal cooldown): below half health it sheds its carapace - the segments explode, it heals
--      over 3 s and its armour hardens for 5 s.
--   ult Coil (unit): lunges onto a big target and coils around it (api.orbitAround): the target is stunned and crushed
--      (a share of its max HP + flat per second, Venom at its maximum); Mukade takes less damage and keeps firing.
local L = VFS.Include("luarules/heroes/legt4_lib.lua")
local C = L.C
local M = {}

local max, min, floor, sqrt, random, cos, sin = math.max, math.min, math.floor, math.sqrt, math.random, math.cos, math.sin

local function cfg(h, key)
	return h.def.cfg[key]
end

---------------------------------------------------------------------------- a2 Venom Rails

local function venomOn(api, unitID, h, uid, dps, seconds)
	if not L.alive(uid) then
		return
	end
	local f = api.frame()
	local v = h.store.venom[uid]
	if not v or v.untilF <= f or dps >= v.dps then
		v = v or {}
		v.dps = (v.untilF or 0) > f and max(dps, v.dps or 0) or dps
		h.store.venom[uid] = v
	end
	v.untilF = f + floor((seconds or 4) * 30)
	L.markOn(api, h.store.venomFx, uid, "aura", { radius = max(40, L.radius(uid) * 0.7), color = L.a(C.VENOM, 0.5), pattern = "heat" }, seconds or 4)
end

local function venomDps(api, h, uid, r)
	local a2 = cfg(h, "a2")
	local p = api.power(h)
	local d = max((a2.minDps or 200) * p, min(api.val(a2.maxDps, r) * p, api.val(a2.pct, r) * L.effHp(api, uid)))
	if api.isHero(uid) then
		d = d * 0.5
	end
	return d
end

local function venomTick(api, unitID, h, f)
	local total = 0
	for uid, v in pairs(h.store.venom) do
		if v.untilF <= f or not L.alive(uid) then
			if v.untilF <= f then
				h.store.venom[uid] = nil
			end
		else
			api.damage(uid, v.dps * 0.5, unitID, { dtype = "flame" })
			total = total + v.dps * 0.5
		end
	end
	h.store.venomDmg = (h.store.venomDmg or 0) + total
end

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	if isParalyzer or damage <= 0 then
		return damage
	end
	local r = api.rank(h, "a2")
	if r > 0 and h.store.railIds[weaponDefID] then
		venomOn(api, unitID, h, victimID, venomDps(api, h, victimID, r), cfg(h, "a2").duration or 4)
	end
	return damage
end

local function acidPool(api, unitID, h, x, z)
	local r = api.rank(h, "a2")
	local a2 = cfg(h, "a2")
	local R = api.val(a2.pool, r)
	local d = api.val(a2.poolDps, r) * api.power(h) * 0.5
	local fx = L.fx(api)
	local y = L.groundY(x, z)
	fx.flash(x, y + 20, z, { radius = 80, color = C.VENOM, ttl = 0.35 })
	fx.ring(x, z, { kind = "rune", r0 = R, r1 = R, color = L.a(C.VENOM, 0.6), width = 16, ttl = 4, rot = 0.6 })
	fx.zone(x, z, { radius = R, pattern = "fog", color = L.a(C.VENOM, 0.45), ttl = 4 })
	local hits = 0
	L.task(h, 15, 4, function()
		hits = hits + #api.area(x, z, R, d, unitID, { dtype = "flame" })
	end, function()
		api.log("legt4mukade a2 acid pool radius=%d tick=%d hits=%d", R, d, hits)
	end)
end

function M.unitDied(api, unitID, h, deadID, deadDefID, x, z, allied)
	local v = h.store.venom[deadID]
	if v then
		h.store.venom[deadID] = nil
		if not allied and v.untilF > api.frame() and api.rank(h, "a2") > 0 and (h.store.pools or 0) < 8 then
			acidPool(api, unitID, h, x, z)
		end
	end
	local c = h.store.coil
	if c and deadID == c.target then
		c.killed = true
	end
end

---------------------------------------------------------------------------- a1 Burrow

local function burrow(api, unitID, h, r, x, z)
	if h.store.burrow or h.store.coil then
		return false
	end
	local a1 = cfg(h, "a1")
	local x0, y0, z0 = api.pos(unitID)
	local reach = api.val(a1.reach, r)
	local tx, tz = L.clampTo(x0, z0, x, z, reach)
	local dist = sqrt(L.d2(x0, z0, tx, tz))
	local maxT = api.val(a1.maxTime, r)
	local speed = max((h.moveSpeed or 52) * (1 + api.val(a1.speedBonus, r)), reach / maxT)
	local travel = min(maxT, dist / speed)
	local fx = L.fx(api)
	fx.ring(x0, z0, { kind = "shock", r0 = 30, r1 = 260, color = L.a(C.AMBER, 0.9), width = 30, ttl = 0.5 })
	fx.flash(x0, y0 + 30, z0, { radius = 120, color = C.AMBER, ttl = 0.25 })
	api.ceg("hero-dash", x0, y0, z0)
	local b = { x = x0, z = z0, tx = tx, tz = tz }
	h.store.burrow = b
	-- 0.6 s dive, then hidden and moving underground
	api.buff(unitID, h, "burrow_dive", 0.6, { immobile = true, unstoppable = true })
	api.delay(18, function()
		if not L.alive(unitID) or h.store.burrow ~= b then
			return
		end
		api.buff(unitID, h, "burrow", nil, { hidden = true })
		-- underground: the model is not drawn; its own side sees a sand swirl moving with it, everyone in LOS the mound
		Spring.SetUnitNoDraw(unitID, true)
		b.swirl = fx.attach(unitID, "aura", { radius = 140, color = L.a(C.AMBER, 0.45), pattern = "swirl", visible = "ally", ally = h.ally })
		local steps = max(1, floor(travel * 10))
		local i = 0
		L.task(h, 3, travel + 0.2, function()
			i = i + 1
			local t = min(1, i / steps)
			local px, pz = x0 + (tx - x0) * t, z0 + (tz - z0) * t
			local gy = L.groundY(px, pz)
			pcall(Spring.MoveCtrl.SetPosition, unitID, px, gy - (h.def.height or 60) * 0.6, pz)
			b.x, b.z = px, pz
			if i % 3 == 0 then
				fx.ring(px, pz, { kind = "shock", r0 = 40, r1 = 160, color = L.a(C.AMBER, 0.6), width = 26, ttl = 0.5 })
			end
			if t >= 1 then
				return false
			end
		end, function()
			h.store.burrow = nil
			api.unbuff(unitID, h, "burrow")
			fx.detach(b.swirl)
			if L.alive(unitID) then
				Spring.SetUnitNoDraw(unitID, false)
			end
			if not L.alive(unitID) then
				return
			end
			local ex, ey, ez = api.pos(unitID)
			local R = api.val(a1.radius, r)
			local dmg = api.val(a1.dmg, r) * api.power(h)
			local hit = api.area(ex, ez, R, dmg, unitID, { dtype = "rail", stun = api.val(a1.stun, r) })
			fx.pillar(ex, ez, { radius = 120, height = 700, color = L.a(C.AMBER, 0.8), ttl = 0.35 })
			fx.flash(ex, ey + 40, ez, { radius = 250, color = C.AMBER, ttl = 0.35 })
			fx.ring(ex, ez, { kind = "shock", r0 = 40, r1 = R, color = L.a(C.AMBER, 0.9), width = 40, ttl = 0.6 })
			fx.ring(ex, ez, { kind = "fire", r0 = 30, r1 = R * 0.8, color = C.AMBER, ttl = 0.6 })
			api.ceg("hero-dash", ex, ey, ez)
			api.log("legt4mukade a1 burrow rank=%d dist=%d travel=%.1f s eruption dmg=%d radius=%d hit=%d stun=%.1f", r, dist, travel, dmg, R, #hit, api.val(a1.stun, r))
		end)
	end)
	return true
end

---------------------------------------------------------------------------- a3 Molting

local function molt(api, unitID, h, r)
	local a3 = cfg(h, "a3")
	local fx = L.fx(api)
	local x, y, z = api.pos(unitID)
	local dx, _, dz = Spring.GetUnitDirection(unitID)
	dx, dz = dx or 0, dz or 1
	local dmg = api.val(a3.dmg, r) * api.power(h)
	local R = a3.radius or 300
	local hitSet, hits = {}, 0
	for k = -1.5, 1.5, 1 do
		local px, pz = x + dx * k * 70, z + dz * k * 70
		fx.flash(px, L.groundY(px, pz) + 30, pz, { radius = 90, color = C.SOLAR, ttl = 0.3 })
		for _, uid in ipairs(api.enemiesIn(px, pz, R * 0.6, h.ally)) do
			if not hitSet[uid] then
				hitSet[uid] = true
				api.damage(uid, dmg, unitID, { dtype = "rail" })
				hits = hits + 1
			end
		end
	end
	fx.ring(x, z, { kind = "shock", r0 = 40, r1 = R, color = L.a(C.AMBER, 0.9), width = 26, ttl = 0.5 })
	fx.attach(unitID, "aura", { radius = 200, color = L.a(C.HEAL, 0.5), pattern = "heal", ttl = 3 })
	fx.attach(unitID, "sphere", { radius = max(100, L.radius(unitID)), color = L.a(C.AMBER, 0.25), hex = true, ttl = 5 })
	api.buff(unitID, h, "molting", 5, { armor = api.val(a3.armor, r) })
	local heal = L.effMaxHp(api, unitID) * api.val(a3.heal, r)
	L.task(h, 15, 3, function()
		api.heal(unitID, heal / 6)
	end)
	api.cooldown(unitID, h, "a3", api.val(a3.icd, r))
	h.store.moltReady = api.frame() + floor(api.val(a3.icd, r) * 30)
	api.log("legt4mukade a3 molt rank=%d heal=%d armor=+%.2f burst=%d hit=%d", r, heal, api.val(a3.armor, r), dmg, hits)
end

function M.damaged(api, unitID, h, damage, attackerID, weaponDefID, isParalyzer, ax, az)
	local c = h.store.coil
	if c then
		damage = damage * (1 - (cfg(h, "ult").reduce or 0.4))
	end
	local r = api.rank(h, "a3")
	if r > 0 and not isParalyzer and api.frame() >= (h.store.moltReady or 0) then
		local hp, maxHp = Spring.GetUnitHealth(unitID)
		if hp and maxHp and hp - damage < maxHp * 0.5 then
			h.store.moltQ = true
		end
	end
	return damage
end

---------------------------------------------------------------------------- ult Coil

local function coilable(api, h, uid)
	if not L.alive(uid) or Spring.GetUnitAllyTeam(uid) == h.ally or L.isAir(uid) then
		return false
	end
	return api.isHero(uid) or L.isStructure(uid) or api.cost(uid) >= (cfg(h, "ult").minCost or 2000)
end

local function coilEnd(api, unitID, h)
	local c = h.store.coil
	if not c then
		return
	end
	h.store.coil = nil
	local fx = L.fx(api)
	for _, id in ipairs(c.ids) do
		fx.detach(id)
	end
	if L.alive(unitID) then
		local x, _, z = api.pos(unitID)
		api.dash(unitID, h, x + 1, z + 1, { seconds = 0.1 }) -- ends the orbit mover
	end
	if c.killed then
		api.heal(unitID, L.effMaxHp(api, unitID) * 0.15)
		local cd = api.val(cfg(h, "ult").cooldown, c.r)
		api.cooldown(unitID, h, "ult", cd * 0.7 - (api.frame() - c.start) / 30)
	end
	api.log("legt4mukade ult coil over rank=%d dmg=%d killed=%s", c.r, c.dmg, tostring(c.killed))
end

local function coil(api, unitID, h, r, targetID)
	if h.store.burrow or h.store.coil or not coilable(api, h, targetID) then
		return false
	end
	local ult = cfg(h, "ult")
	local x, y, z = api.pos(unitID)
	local tx, ty, tz = api.pos(targetID)
	local tr = L.radius(targetID)
	if L.d2(x, z, tx, tz) > ((ult.range or 700) + tr + 80) ^ 2 then
		return false
	end
	local dur = api.val(ult.duration, r)
	local fx = L.fx(api)
	local trail = fx.attach(unitID, "trail", { color = C.AMBER, width = 24, length = 0.5, ttl = 0.6 })
	local dx, dz = x - tx, z - tz
	local d = max(1, sqrt(dx * dx + dz * dz))
	local rad = tr + 60
	local lx, lz = tx + dx / d * rad, tz + dz / d * rad
	local c = { target = targetID, r = r, dmg = 0, start = api.frame(), ids = { trail } }
	h.store.coil = c
	api.dash(unitID, h, lx, lz, { seconds = 0.35, arc = 40, onLand = L.later(api, function()
		if h.store.coil ~= c then
			return
		end
		if not L.alive(targetID) then
			coilEnd(api, unitID, h)
			return
		end
		api.orbitAround(unitID, h, targetID, rad, dur)
		api.stun(targetID, dur, unitID)
		local gx, _, gz = api.pos(targetID)
		c.ids[#c.ids + 1] = fx.attach(targetID, "electric", { color = C.EMBER, intensity = 0.8, ttl = dur })
		c.ids[#c.ids + 1] = fx.attach(targetID, "aura", { radius = rad, color = L.a(C.EMBER, 0.6), pattern = "hex", ttl = dur })
		local pct, flat = api.val(ult.pct, r), api.val(ult.flat, r) * api.power(h)
		local maxV = api.val(cfg(h, "a2").maxDps, max(1, api.rank(h, "a2"))) * api.power(h)
		L.task(h, 30, dur, function()
			if h.store.coil ~= c or not L.alive(targetID) then
				return false
			end
			local dmg = pct * L.effMaxHp(api, targetID) + flat
			api.damage(targetID, dmg, unitID, { dtype = "rail" })
			c.dmg = c.dmg + dmg
			if api.rank(h, "a2") > 0 then
				venomOn(api, unitID, h, targetID, api.isHero(targetID) and maxV * 0.5 or maxV, 2)
			end
			L.unitFlash(api, targetID, 100, C.EMBER, 0.2, 30)
		end, function()
			coilEnd(api, unitID, h)
		end, 1)
	end) })
	api.active(unitID, "ult", dur + 0.4)
	api.log("legt4mukade ult coil rank=%d target=%s dur=%.1f", r, tostring(targetID), dur)
	return true
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.tasks = {}
	h.store.venom = {}
	h.store.venomFx = {}
	h.store.coil = nil
	h.store.burrow = nil
	local ids = {}
	for _, w in pairs(h.def.weapons) do
		if w.key == "railgunt2" then
			ids[w.wdid] = true
		end
	end
	h.store.railIds = ids
end

function M.frame(api, unitID, h, f)
	L.runTasks(h, f)
	if f % 15 == 0 then
		venomTick(api, unitID, h, f)
	end
	if f % 30 == 0 then
		L.markSweep(api, h.store.venomFx, f)
	end
	if h.store.moltQ then
		h.store.moltQ = nil
		local r = api.rank(h, "a3")
		if r > 0 and f >= (h.store.moltReady or 0) then
			molt(api, unitID, h, r)
		end
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a1" and x then
		return burrow(api, unitID, h, rank, x, z)
	elseif key == "ult" then
		return coil(api, unitID, h, rank, targetID)
	end
	return false
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x or h.store.burrow or h.store.coil then
		return nil
	end
	local frac = L.hpFrac(unitID)
	if key == "a1" then
		local a1 = cfg(h, "a1")
		local reach = api.val(a1.reach, rank)
		if frac < 0.25 then
			-- escape toward the allies
			local sx, sz, n = 0, 0, 0
			for _, uid in ipairs(api.alliesIn(x, z, 4000, h.ally)) do
				if uid ~= unitID then
					local ux, _, uz = api.pos(uid)
					sx, sz, n = sx + ux, sz + uz, n + 1
				end
			end
			if n > 0 then
				local px, pz = L.clampTo(x, z, sx / n, sz / n, reach)
				return px, L.groundY(px, pz), pz
			end
			local cx, cz = L.centroid(api, x, z, 900, h.ally)
			if cx then
				local px, pz = L.away(x, z, cx, cz, reach)
				return px, L.groundY(px, pz), pz
			end
			return nil
		end
		if frac > 0.5 then
			local R = api.val(a1.radius, rank)
			for _, uid in ipairs(api.enemiesIn(x, z, reach, h.ally)) do
				local ud = L.ud(uid)
				if api.seenBy(uid, h.ally) and ud and ((ud.maxWeaponRange or 0) > 1000 or api.cost(uid) >= 3000) then
					local tx, _, tz = api.pos(uid)
					if #api.enemiesIn(tx, tz, R, h.ally) >= 2 and L.d2(x, z, tx, tz) > 500 * 500 then
						return tx, L.groundY(tx, tz), tz
					end
				end
			end
		end
	elseif key == "ult" then
		local ult = cfg(h, "ult")
		for _, uid in ipairs(L.enemyHeroes(api, x, z, 1500, h.ally)) do
			local tx, ty, tz = api.pos(uid)
			if L.d2(x, z, tx, tz) <= ((ult.range or 700) + L.radius(uid)) ^ 2 then
				return tx, ty, tz, uid
			end
			Spring.GiveOrderToUnit(unitID, CMD.MOVE, { tx, ty, tz }, 0)
			return nil
		end
		local best, bestC
		for _, uid in ipairs(api.enemiesIn(x, z, ult.range or 700, h.ally)) do
			if api.seenBy(uid, h.ally) and not L.isStructure(uid) and coilable(api, h, uid) and api.cost(uid) >= 8000 and (not bestC or api.cost(uid) > bestC) then
				best, bestC = uid, api.cost(uid)
			end
		end
		if best then
			local tx, ty, tz = api.pos(best)
			return tx, ty, tz, best
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	L.endTasks(h)
	if h.store.burrow and L.alive(unitID) then
		Spring.SetUnitNoDraw(unitID, false)
	end
	h.store.coil = nil
	h.store.burrow = nil
	L.markClear(api, h.store.venomFx or {})
	h.store.venom = {}
end

return M
