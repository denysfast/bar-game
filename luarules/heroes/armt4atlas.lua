-- Atlas, the Bulwark (armt4atlas, Bantha x2): the assault anchor (doc/v19-heroes/roster_arm.md 2). Numbers per rank:
-- luarules/configs/heroes/arm.lua. API: header of luarules/gadgets/unit_t4_heroes.lua.
--
--   a1 Doom Lens (passive): every Doom Laser hit Sunders its target for 6 s (it takes more damage from every source);
--      the Doom Laser hits 5000+ metal targets harder.
--   a2 Bulwark Protocol (active, self): plants its feet - immobile, much less damage taken, taunts every enemy around
--      (heroes 1.5 s), reflects a share of the damage (before the reduction) back at the attackers as lightning.
--   a3 Titan Salvo (active, map; v20, replaced Seismic Charge): a salvo of guided rockets rains on the area, every hit
--      Sunders its target (the Doom Lens value once a1 is learned), the last three rockets also slow.
--   ult Doomsday Lance (active, map): charges 0.8 s, then the Doom Laser becomes a continuous lance twice its range long
--      and sweeps a 60 degree arc centred on the point; units it kills burst for 10% of their max HP.

local L = VFS.Include("luarules/heroes/armt4_lib.lua", nil, VFS.ZIP_FIRST)

local M = {}

local GOLD = { 1, 0.95, 0.7, 1 }
local SUNDER = { 1, 0.55, 0.2, 0.6 }
local SHIELD = { 0.4, 0.65, 1, 0.08 }

local function b(h, key)
	return h.def.cfg[key]
end

local function eye(api, unitID)
	local x, y, z = api.piecePos(unitID, "laserflare")
	if not x then
		x, y, z = api.pos(unitID)
		y = y + 140
	end
	return x, y, z
end

---------------------------------------------------------------------------- a1 Doom Lens

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	local r = api.rank(h, "a1")
	if r <= 0 or isParalyzer or L.weaponKey(h, weaponDefID) ~= "tehlazerofdewm" then
		return damage
	end
	local a1 = b(h, "a1")
	local f = api.frame()
	local seen = h.store.lens
	-- a beam deals its damage over a few frames: the effects once per shot and target
	if not seen[victimID] or f - seen[victimID] > 20 then
		seen[victimID] = f
		local fresh = api.marks(victimID, "sunder") == 0
		api.mark(victimID, "sunder", a1.sunderTime or 6, { vuln = api.val(a1.sunder, r), from = unitID, max = 1 })
		local fx = api.fx
		if fx then
			local x, y, z = api.pos(victimID)
			local ex, ey, ez = eye(api, unitID)
			fx.beam(ex, ey, ez, x, y + 25, z, { color = GOLD, width = 14, ttl = 0.18, flare = 1.4 })
			local rad = L.radius(victimID)
			if h.store.sunderFx[victimID] then
				fx.detach(h.store.sunderFx[victimID])
			end
			h.store.sunderFx[victimID] = fx.attach(victimID, "aura", { pattern = "runes", color = SUNDER, radius = math.max(50, rad * 1.2), ttl = a1.sunderTime or 6 })
			if fresh then
				fx.ring(x, z, { kind = "rune", r0 = rad * 0.6, r1 = rad * 1.5, color = SUNDER, ttl = 0.5, width = 16 })
			end
		end
		api.log("armt4atlas a1 sunder rank=%d victim=%s cost=%d vuln=%.2f", r, UnitDefs[victimDefID].name, api.cost(victimID), api.val(a1.sunder, r))
	end
	if api.cost(victimID) >= (a1.bigCost or 5000) then
		damage = damage * (1 + api.val(a1.bigBonus, r))
	end
	return damage
end

---------------------------------------------------------------------------- a2 Bulwark Protocol

local function bulwark(api, unitID, h, r)
	local a2 = b(h, "a2")
	local dur = api.val(a2.duration, r)
	local armor = api.val(a2.armor, r)
	local radius = api.val(a2.radius, r)
	api.buff(unitID, h, "bulwark", dur, { immobile = true, armor = armor, reflect = api.val(a2.reflect, r) / math.max(0.2, 1 - armor) })
	api.active(unitID, "a2", dur)
	local x, _, z = api.pos(unitID)
	local n = 0
	for _, uid in ipairs(api.enemiesIn(x, z, radius, h.ally)) do
		if api.taunt(uid, unitID, api.isHero(uid) and 3 or dur) then
			n = n + 1
		end
	end
	local fx = api.fx
	local st = { untilFrame = api.frame() + math.floor(dur * 30), lastFx = 0 }
	if fx then
		fx.ring(x, z, { kind = "hex", r0 = radius * 0.6, r1 = radius, color = { 0.4, 0.7, 1, 0.6 }, ttl = 0.5, width = 30 })
		fx.ring(x, z, { kind = "rune", r0 = radius * 0.7, r1 = radius, color = "orange", ttl = 0.8, width = 30 })
		st.sphere = fx.attach(unitID, "sphere", { radius = 200, color = SHIELD, hex = true, fresnel = 1, height = 90, ttl = dur })
	end
	h.store.bulwark = st
	api.log("armt4atlas a2 bulwark rank=%d dur=%.1f armor=%.2f taunted=%d radius=%d", r, dur, armor, n, radius)
	return true
end

function M.damaged(api, unitID, h, damage, attackerID, weaponDefID, isParalyzer, ax, az)
	local st = h.store.bulwark
	if st and api.frame() < st.untilFrame and ax and attackerID then
		local f = api.frame()
		local fx = api.fx
		if fx and f - st.lastFx >= 5 then
			st.lastFx = f
			local x, y, z = api.pos(unitID)
			local dx, dz = ax - x, az - z
			local d = math.max(1, math.sqrt(dx * dx + dz * dz))
			local hx, hy, hz = x + dx / d * 190, y + 90, z + dz / d * 190
			fx.hit(st.sphere, hx, hy, hz)
			local _, ay = api.pos(attackerID)
			fx.bolt(hx, hy, hz, ax, (ay or hy) + 20, az, { color = { 0.5, 0.8, 1, 1 }, width = 5, ttl = 0.2 })
		end
	end
	return damage
end

---------------------------------------------------------------------------- a3 Titan Salvo

-- v20 (replaces Seismic Charge): one guided rocket every 0.1 s from the shoulder rack, launched up and turning onto a
-- random point of the area; every hit Sunders (the Doom Lens value once a1 is learned), the last three also slow
local function salvo(api, unitID, h, r, tx, tz)
	local a3 = b(h, "a3")
	local x, _, z = api.pos(unitID)
	local range = api.val(a3.range, r)
	local dx, dz = tx - x, tz - z
	local d = math.sqrt(dx * dx + dz * dz)
	if d > range then
		tx, tz = x + dx / d * range, z + dz / d * range
	end
	local count = math.floor(api.val(a3.count, r) + 0.5)
	local dmg = api.val(a3.dmg, r) * api.power(h)
	local radius = api.val(a3.radius, r)
	local r1 = api.rank(h, "a1")
	local vuln = r1 > 0 and api.val(b(h, "a1").sunder, r1) or (a3.sunder or 0.06)
	local st = { hits = 0, fired = 0 }
	local fx = api.fx
	if fx then
		fx.ring(tx, tz, { kind = "rune", r0 = radius * 0.8, r1 = radius, color = SUNDER, ttl = count * 0.1 + 1.2, width = 22 })
	end
	for i = 1, count do
		api.delay(1 + (i - 1) * 3, function()
			if not L.alive(unitID) then
				return
			end
			local sx, sy, sz = api.piecePos(unitID, "missleflare")
			if not sx then
				sx, sy, sz = api.pos(unitID)
				sy = sy + 150
			end
			local ang = math.random() * 2 * math.pi
			local rr = radius * math.sqrt(math.random())
			local px, pz = tx + math.cos(ang) * rr, tz + math.sin(ang) * rr
			local py = L.gy(px, pz)
			local last = i > count - 3
			local pid = api.fire(h, "hero_ab_missile", sx, sy, sz, sx + (px - sx) * 0.08, sy + 400, sz + (pz - sz) * 0.08, {
				key = "a3", dmg = dmg, aoe = a3.aoe or 180, dtype = "rocket", ttl = 10,
				onHit = function(hx, hz, hits)
					st.hits = st.hits + #hits
					for _, uid in ipairs(hits) do
						api.mark(uid, "sunder", a3.sunderTime or 6, { vuln = vuln, from = unitID, max = 1 })
						if last then
							api.slow(uid, a3.slow or 0.35, 2.5)
						end
					end
					local f2 = api.fx
					if f2 then
						f2.ring(hx, hz, { kind = last and "shock" or "rune", r0 = 20, r1 = (a3.aoe or 180) * 1.1, color = last and GOLD or SUNDER, ttl = 0.4, width = 18 })
					end
				end })
			if pid and pid > 0 then
				Spring.SetProjectileTarget(pid, px, py, pz)
				st.fired = st.fired + 1
			end
			if i == count then
				api.delay(150, function()
					api.log("armt4atlas a3 salvo rank=%d rockets=%d/%d dmg=%d hits=%d vuln=%.2f", r, st.fired, count, dmg, st.hits, vuln)
				end)
			end
		end)
	end
	api.active(unitID, "a3", count * 0.1 + 1)
	return true
end

---------------------------------------------------------------------------- ult Doomsday Lance

local function doomRange(api, unitID, h)
	local w, n = L.weapon(h, "tehlazerofdewm")
	if not w then
		return 1440
	end
	return Spring.GetUnitWeaponState(unitID, n, "range") or w.range
end

local function lanceOn(api, unitID, h, r, tx, tz)
	local ult = b(h, "ult")
	local x, _, z = api.pos(unitID)
	local dur = api.val(ult.duration, r)
	local f = api.frame()
	local st = {
		r = r, start = f + 24, stop = f + 24 + math.floor(dur * 30), angle = math.atan2(tz - z, tx - x),
		arc = math.rad(ult.arc or 60), len = 2 * doomRange(api, unitID, h), dps = api.val(ult.dps, r) * api.power(h),
		width = ult.width or 90, dealt = 0, kills = 0, hits = 0,
	}
	h.store.lance = st
	api.buff(unitID, h, "lance", dur + 1, { immobile = true })
	api.active(unitID, "ult", dur + 0.8)
	local fx = api.fx
	if fx then
		local ex, ey, ez = eye(api, unitID)
		st.orb = fx.attach(unitID, "orb", { color = GOLD, radius = 10, height = ey - select(2, api.pos(unitID)), orbit = 0, crackle = 5 })
		fx.set(st.orb, { radius = 40, time = 0.8 })
		fx.flash(ex, ey, ez, { radius = 90, color = GOLD, ttl = 0.8 })
		fx.ring(x, z, { kind = "sweep", r0 = 120, r1 = st.len, arc = st.arc, angle = st.angle, color = { 1, 0.8, 0.4, 0.25 }, ttl = 0.8 + dur, width = 20 })
	end
	api.log("armt4atlas ult lance rank=%d dur=%.1f len=%d dps=%d", r, dur, st.len, st.dps)
	return true
end

local function lanceOff(api, unitID, h)
	local st = h.store.lance
	if not st then
		return
	end
	h.store.lance = nil
	api.unbuff(unitID, h, "lance")
	L.detach(api, st.orb)
	api.log("armt4atlas ult lance over: dealt=%d hits=%d kills=%d", st.dealt, st.hits, st.kills)
end

local function lanceFrame(api, unitID, h, f)
	local st = h.store.lance
	if f < st.start then
		return
	end
	if f >= st.stop then
		lanceOff(api, unitID, h)
		return
	end
	local t = (f - st.start) / math.max(1, st.stop - st.start)
	local a = st.angle + (t - 0.5) * st.arc
	local x, _, z = api.pos(unitID)
	local ex, ey, ez = eye(api, unitID)
	local tx, tz = x + math.cos(a) * st.len, z + math.sin(a) * st.len
	local ty = L.gy(tx, tz)
	local fx = api.fx
	if fx then
		fx.beam(ex, ey, ez, tx, ty + 10, tz, { color = { 1, 0.85, 0.45, 1 }, width = 16, ttl = 0.13, pulse = 8, ground = true, flare = 1.6 })
		fx.flash(tx, ty + 20, tz, { radius = 70, color = { 1, 0.7, 0.3, 0.8 }, ttl = 0.15 })
	end
	-- 3 frames of damage on the line; the units it kills burst
	local hits = api.line(x, z, tx, tz, st.width, 0, unitID)
	local tick = st.dps * 0.1
	for _, uid in ipairs(hits) do
		local ux, uy, uz = api.pos(uid)
		local _, maxHp = Spring.GetUnitHealth(uid)
		api.damage(uid, tick, unitID, { dtype = "laser" })
		st.dealt = st.dealt + tick
		st.hits = st.hits + 1
		if ux and (not L.alive(uid) or (Spring.GetUnitHealth(uid) or 0) <= 0) then
			st.kills = st.kills + 1
			api.area(ux, uz, 200, (maxHp or 0) * 0.1, unitID, { dtype = "laser" })
			if fx then
				fx.flash(ux, uy + 20, uz, { radius = 90, color = "orange", ttl = 0.3 })
				fx.ring(ux, uz, { kind = "shock", r0 = 10, r1 = 200, color = "orange", ttl = 0.35, width = 22 })
			end
		end
	end
end

-- the 60 degree cone within 2x Doom range with the most enemy metal
local function bestCone(api, unitID, h)
	local x, _, z = api.pos(unitID)
	local len = 2 * doomRange(api, unitID, h)
	local list = L.seenEnemies(api, x, z, len, h.ally)
	if #list == 0 then
		return nil
	end
	local angles = {}
	for _, uid in ipairs(list) do
		local ux, _, uz = api.pos(uid)
		angles[#angles + 1] = { math.atan2(uz - z, ux - x), api.cost(uid) * (api.isHero(uid) and 3 or 1) }
	end
	local bestA, bestC, bestN = nil, 0, 0
	for i = 0, 23 do
		local a0 = i * math.pi / 12
		local c, n = 0, 0
		for _, e in ipairs(angles) do
			local da = math.abs(((e[1] - a0 + math.pi) % (2 * math.pi)) - math.pi)
			if da <= math.pi / 6 then
				c, n = c + e[2], n + 1
			end
		end
		if c > bestC then
			bestA, bestC, bestN = a0, c, n
		end
	end
	return bestA, bestC, bestN, len
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.lens = {}
	h.store.sunderFx = {}
	h.store.bulwark = nil
	h.store.lance = nil
end

function M.frame(api, unitID, h, f)
	if f % 90 == 0 then
		for uid, fr in pairs(h.store.lens) do
			if f - fr > 300 then
				h.store.lens[uid] = nil
				h.store.sunderFx[uid] = nil
			end
		end
	end
	if h.store.lance then
		lanceFrame(api, unitID, h, f)
	end
	if h.store.bulwark and f >= h.store.bulwark.untilFrame then
		h.store.bulwark = nil
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a2" then
		return bulwark(api, unitID, h, rank)
	elseif key == "a3" then
		if targetID and not x then
			x, y, z = api.pos(targetID)
		end
		return x and salvo(api, unitID, h, rank, x, z) or false
	elseif key == "ult" then
		if h.store.lance or not x then
			return false
		end
		return lanceOn(api, unitID, h, rank, x, z)
	end
	return false
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	local hp = L.hpFrac(unitID)
	if key == "a2" then
		local cost, n = api.enemyCostNear(x, z, 900, h.ally)
		if n >= 6 or (hp > 0.5 and L.enemyHero(api, x, z, 900, h.ally)) then
			return x, y, z
		end
	elseif key == "a3" then
		local range = L.v(api, h, "a3", "range", rank)
		local cx, cz, _, n = L.cluster(api, x, z, range, 300, h.ally)
		if cx and n >= 5 then
			return cx, L.gy(cx, cz), cz
		end
		local hero = L.enemyHero(api, x, z, range, h.ally)
		if hero then
			local hx, hy, hz = api.pos(hero)
			return hx, hy, hz
		end
	elseif key == "ult" then
		local a, cost, n, len = bestCone(api, unitID, h)
		if a and (n >= 12 or cost >= 40000) then
			local tx, tz = x + math.cos(a) * len * 0.6, z + math.sin(a) * len * 0.6
			return tx, L.gy(tx, tz), tz
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	lanceOff(api, unitID, h)
end

return M
