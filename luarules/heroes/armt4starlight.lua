-- Starlight, the Lance (armt4starlight, armmanni x2.4): the tachyon sniper (doc/v19-heroes/roster_arm.md 9).
-- Numbers: luarules/configs/heroes/arm.lua.
--
--   a1 Focusing Array (passive): each shot in a row on the same target adds damage (stacks); changing target resets.
--      The beam goes on behind the target and burns everything on that line for 50%.
--   a2 Prism Relay (active, ally): links to an allied unit; every shot also refracts from it to the most valuable enemy
--      within 700 of it. With no target of its own, Starlight fires through the prism alone.
--   a3 Phase Shift (active, map): teleports; a light mine left behind detonates a second later.
--   ult Solar Lance (active, unit or map): charges 2 s, then holds a solar lance on the target for 3..5 s; everything
--      else on the line takes 40%.

local L = VFS.Include("luarules/heroes/armt4_lib.lua", nil, VFS.ZIP_FIRST)

local M = {}

local VIOLET = { 0.75, 0.6, 1, 1 }
local PRISM = { 0.8, 0.6, 1, 1 }
local SOLAR = { 0.85, 0.8, 1, 1 }

local function b(h, key)
	return h.def.cfg[key]
end

local function flare(api, unitID)
	local x, y, z = api.piecePos(unitID, "flare")
	if not x then
		x, y, z = api.pos(unitID)
		y = y + 60
	end
	return x, y, z
end

local function shotDamage(api, h)
	local w = L.weapon(h, "atam")
	return (w and w.damage or 0) * api.dmgMult(h)
end

---------------------------------------------------------------------------- a1 Focusing Array

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	if isParalyzer or L.weaponKey(h, weaponDefID) ~= "atam" then
		return damage
	end
	local r = api.rank(h, "a1")
	if r <= 0 then
		return damage
	end
	local a1 = b(h, "a1")
	local st = h.store.focus
	local f = api.frame()
	if f - (st.lastHit or -999) > 15 then
		-- a new shot (a beam deals its damage over 0.3 s)
		if victimID == st.target then
			st.stacks = math.min(api.val(a1.stacks, r), st.stacks + 1)
		else
			st.stacks = 0
			st.target = victimID
		end
		st.mult = 1 + api.val(a1.focus, r) * st.stacks
		local ex, ey, ez = flare(api, unitID)
		local vx, vy, vz = api.pos(victimID)
		local fx = api.fx
		if vx then
			local dx, dz = vx - ex, vz - ez
			local d = math.max(1, math.sqrt(dx * dx + dz * dz))
			dx, dz = dx / d, dz / d
			local len = api.val(a1.pierce, r)
			local rad = L.radius(victimID)
			local sx, sz = vx + dx * (rad + 10), vz + dz * (rad + 10)
			local px, pz = vx + dx * (rad + len), vz + dz * (rad + len)
			local pdmg = shotDamage(api, h) * st.mult * (a1.pierceShare or 0.5)
			local hits = api.line(sx, sz, px, pz, 80, 0, unitID)
			local n = 0
			for _, uid in ipairs(hits) do
				if uid ~= victimID then
					api.damage(uid, pdmg, unitID, { dtype = "laser" })
					n = n + 1
				end
			end
			if fx then
				fx.beam(ex, ey, ez, vx, vy + 25, vz, { color = VIOLET, width = 6 + 4 * st.stacks, ttl = 0.25, flare = 1 + 0.2 * st.stacks })
				fx.beam(vx, vy + 25, vz, px, L.gy(px, pz) + 25, pz, { color = { 0.75, 0.6, 1, 0.5 }, width = 4 + 2 * st.stacks, ttl = 0.25 })
			end
			api.log("armt4starlight a1 focus rank=%d stacks=%d mult=%.2f shot=%d pierce=%d hits=%d", r, st.stacks, st.mult, shotDamage(api, h) * st.mult, pdmg, n)
		end
	end
	st.lastHit = f
	return damage * (st.mult or 1)
end

---------------------------------------------------------------------------- a2 Prism Relay

local function refract(api, unitID, h, alone)
	local st = h.store.prism
	if not st or not L.alive(st.ally) then
		return false
	end
	local ax, ay, az = api.pos(st.ally)
	local enemy, value = api.mostValuableEnemy(ax, az, b(h, "a2").reach or 700, h.ally)
	if not enemy then
		return false
	end
	local dmg = shotDamage(api, h) * st.share
	api.damage(enemy, dmg, unitID, { dtype = "laser" })
	st.shots = st.shots + 1
	st.dealt = st.dealt + dmg
	local fx = api.fx
	if fx then
		local tx, ty, tz = api.pos(enemy)
		if alone then
			local ex, ey, ez = flare(api, unitID)
			fx.beam(ex, ey, ez, ax, ay + 80, az, { color = PRISM, width = 8, ttl = 0.25 })
		end
		fx.beam(ax, ay + 80, az, tx, ty + 25, tz, { color = { 0.85, 0.75, 1, 1 }, width = 10, ttl = 0.25, flare = 1.2 })
		fx.flash(ax, ay + 80, az, { radius = 40, color = PRISM, ttl = 0.2 })
	end
	return true
end

local function prism(api, unitID, h, r, allyID)
	local a2 = b(h, "a2")
	if not allyID or allyID == unitID or not L.alive(allyID) or Spring.GetUnitAllyTeam(allyID) ~= h.ally then
		api.log("armt4starlight a2 prism: no ally target (%s alive=%s ally=%s/%s)", tostring(allyID), tostring(L.alive(allyID)),
			tostring(allyID and Spring.GetUnitAllyTeam(allyID)), tostring(h.ally))
		return false
	end
	if L.unitDist(unitID, allyID) > (a2.range or 1500) * 1.1 then
		api.log("armt4starlight a2 prism: ally too far (%d)", L.unitDist(unitID, allyID))
		return false
	end
	local dur = api.val(a2.duration, r)
	local st = { ally = allyID, untilFrame = api.frame() + math.floor(dur * 30), share = api.val(a2.share, r), shots = 0, dealt = 0 }
	local fx = api.fx
	if fx then
		st.fx = {
			fx.attach(unitID, "link", { target = allyID, style = "beam", color = { 0.7, 0.55, 1, 0.35 }, width = 3, ttl = dur }),
			fx.attach(allyID, "orb", { color = PRISM, radius = 18, height = 80, orbit = 0, crackle = 2, ttl = dur }),
		}
	end
	h.store.prism = st
	api.active(unitID, "a2", dur)
	api.log("armt4starlight a2 prism rank=%d ally=%s dur=%d share=%.2f", r, UnitDefs[Spring.GetUnitDefID(allyID)].name, dur, st.share)
	return true
end

function M.fired(api, unitID, h, weaponNum)
	if h.store.prism then
		refract(api, unitID, h, false)
	end
end

local function prismFrame(api, unitID, h, f)
	local st = h.store.prism
	if f >= st.untilFrame or not L.alive(st.ally) then
		h.store.prism = nil
		L.detach(api, st.fx)
		api.log("armt4starlight a2 prism over: refracted shots=%d dealt=%d", st.shots, st.dealt)
		return
	end
	-- no target of its own: the shot goes through the prism alone (and spends the reload)
	local w, n = L.weapon(h, "atam")
	if w and not api.target(unitID) then
		local rs = Spring.GetUnitWeaponState(unitID, n, "reloadState") or 0
		if rs <= f and refract(api, unitID, h, true) then
			local reload = Spring.GetUnitWeaponState(unitID, n, "reloadTime") or w.reload
			Spring.SetUnitWeaponState(unitID, n, "reloadState", f + math.floor(reload * 30))
			h.lastReload = h.lastReload or {}
			h.lastReload[n] = f + math.floor(reload * 30) -- not a shot of its own: no `fired`
		end
	end
end

---------------------------------------------------------------------------- a3 Phase Shift

local function phase(api, unitID, h, r, tx, tz)
	local a3 = b(h, "a3")
	local x, y, z = api.pos(unitID)
	local range = api.val(a3.range, r)
	local d = L.dist(x, z, tx, tz)
	if d < 50 then
		return false
	end
	if d > range then
		tx, tz = x + (tx - x) / d * range, z + (tz - z) / d * range
	end
	if not api.blink(unitID, tx, tz) then
		return false
	end
	local nx, ny, nz = api.pos(unitID)
	local dmg = api.val(a3.dmg, r) * api.power(h)
	local R = a3.radius or 250
	local fx = api.fx
	if fx then
		fx.flash(x, y + 40, z, { radius = 80, color = { 0.8, 0.65, 1, 0.9 }, ttl = 0.35 })
		fx.flash(nx, ny + 40, nz, { radius = 80, color = { 0.8, 0.65, 1, 0.9 }, ttl = 0.35 })
		fx.beam(x, y + 40, z, nx, ny + 40, nz, { color = { 0.8, 0.65, 1, 1 }, width = 7, ttl = 0.2 })
		fx.ring(x, z, { kind = "rune", r0 = R * 0.9, r1 = R, color = VIOLET, ttl = 1, width = 20, rot = 2 })
	end
	local ally = h.ally
	L.after(h, 30, function()
		local hits = api.area(x, z, R, dmg, unitID, { dtype = "laser", ally = ally })
		if api.fx then
			api.fx.flash(x, L.gy(x, z) + 40, z, { radius = 220, color = SOLAR, ttl = 0.4 })
			api.fx.ring(x, z, { kind = "shock", r0 = 20, r1 = 300, color = SOLAR, ttl = 0.4, width = 30 })
		end
		api.log("armt4starlight a3 light mine rank=%d dmg=%d hits=%d", r, dmg, #hits)
	end)
	api.log("armt4starlight a3 phase shift rank=%d dist=%d", r, L.dist(x, z, nx, nz))
	return true
end

---------------------------------------------------------------------------- ult Solar Lance

local function lanceOn(api, unitID, h, r, x, z, targetID)
	local ult = b(h, "ult")
	local hx, _, hz = api.pos(unitID)
	local range = api.val(ult.range, r)
	if targetID and (not L.alive(targetID) or Spring.GetUnitAllyTeam(targetID) == h.ally) then
		targetID = nil
	end
	if targetID then
		x, _, z = api.pos(targetID)
	end
	if not x or L.dist(hx, hz, x, z) > range * 1.05 then
		return false
	end
	local dur = api.val(ult.duration, r)
	local charge = ult.charge or 2
	local f = api.frame()
	local st = { r = r, target = targetID, x = x, z = z, start = f + math.floor(charge * 30), stop = f + math.floor((charge + dur) * 30),
		dps = api.val(ult.dps, r) * api.power(h), lineShare = ult.lineShare or 0.4, width = ult.width or 100, dealt = 0, lineDealt = 0, nextFx = 0 }
	api.buff(unitID, h, "solar", charge + dur + 0.5, { immobile = true })
	api.active(unitID, "ult", charge + dur)
	local fx = api.fx
	if fx then
		local ex, ey, ez = flare(api, unitID)
		st.orb = fx.attach(unitID, "orb", { color = SOLAR, radius = 10, height = ey - select(2, api.pos(unitID)), orbit = 0, crackle = 4, ttl = charge + 0.2 })
		fx.set(st.orb, { radius = 40, time = charge })
		fx.flash(ex, ey, ez, { radius = 90, color = { 0.85, 0.75, 1, 0.8 }, ttl = charge })
		fx.ring(x, z, { kind = "rune", r0 = 280, r1 = 300, color = SOLAR, ttl = charge + dur, width = 20, rot = 1 })
	end
	h.store.lance = st
	api.log("armt4starlight ult solar lance rank=%d dur=%.1f dps=%d target=%s", r, dur, st.dps, targetID and UnitDefs[Spring.GetUnitDefID(targetID)].name or "ground")
	return true
end

local function lanceFrame(api, unitID, h, f)
	local st = h.store.lance
	if f >= st.stop then
		h.store.lance = nil
		api.unbuff(unitID, h, "solar")
		api.log("armt4starlight ult solar lance over: target=%d line=%d", st.dealt, st.lineDealt)
		return
	end
	if f < st.start then
		return
	end
	if st.target and L.alive(st.target) then
		st.x, _, st.z = api.pos(st.target)
	else
		st.target = nil
	end
	local hx, _, hz = api.pos(unitID)
	local ex, ey, ez = flare(api, unitID)
	local tick = st.dps * 0.1
	local ty = L.gy(st.x, st.z)
	if st.target then
		api.damage(st.target, tick, unitID, { dtype = "laser" })
		st.dealt = st.dealt + tick
		ty = select(2, api.pos(st.target)) or ty
	end
	for _, uid in ipairs(api.line(hx, hz, st.x, st.z, st.width, 0, unitID)) do
		if uid ~= st.target then
			api.damage(uid, tick * st.lineShare, unitID, { dtype = "laser" })
			st.lineDealt = st.lineDealt + tick * st.lineShare
		end
	end
	local fx = api.fx
	if fx then
		fx.beam(ex, ey, ez, st.x, ty + 25, st.z, { color = { 0.85, 0.75, 1, 1 }, width = 28, ttl = 0.13, pulse = 2, flare = 1.5 })
		if f >= st.nextFx then
			st.nextFx = f + 15
			fx.pillar(st.x, st.z, { radius = 55, height = 1200, color = { 0.8, 0.65, 1, 0.6 }, ttl = 0.6, ring = false })
			fx.ring(st.x, st.z, { kind = "shock", r0 = 20, r1 = 220, color = { 0.8, 0.65, 1, 0.7 }, ttl = 0.4, width = 22 })
		end
	end
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.focus = { stacks = 0 }
	h.store.prism, h.store.lance = nil, nil
end

function M.frame(api, unitID, h, f)
	L.tick(h, f)
	if h.store.prism then
		prismFrame(api, unitID, h, f)
	end
	if h.store.lance then
		lanceFrame(api, unitID, h, f)
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a2" then
		return prism(api, unitID, h, rank, targetID)
	elseif key == "a3" then
		if not x then
			return false
		end
		return phase(api, unitID, h, rank, x, z)
	elseif key == "ult" then
		if h.store.lance then
			return false
		end
		return lanceOn(api, unitID, h, rank, x, z, targetID)
	end
	return false
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	if key == "a2" then
		if h.store.prism or api.target(unitID) then
			return nil
		end
		local best, bestC
		for _, uid in ipairs(api.alliesIn(x, z, b(h, "a2").range or 1500, h.ally)) do
			if uid ~= unitID and L.isMobile(uid) then
				local ux, _, uz = api.pos(uid)
				local c = api.enemyCostNear(ux, uz, 700, h.ally)
				if c > 0 and (not bestC or c > bestC) then
					best, bestC = uid, c
				end
			end
		end
		if best then
			local tx, ty, tz = api.pos(best)
			return tx, ty, tz, best
		end
	elseif key == "a3" then
		if L.hpFrac(unitID) >= 0.7 then
			return nil
		end
		local near = L.seenEnemies(api, x, z, 600, h.ally)
		if #near == 0 then
			return nil
		end
		local sx, sz = 0, 0
		for _, uid in ipairs(L.seenEnemies(api, x, z, 900, h.ally)) do
			local ux, _, uz = api.pos(uid)
			sx, sz = sx + ux - x, sz + uz - z
		end
		local d = math.max(1, math.sqrt(sx * sx + sz * sz))
		local range = L.v(api, h, "a3", "range", rank) * 0.8
		local tx, tz = x - sx / d * range, z - sz / d * range
		return tx, L.gy(tx, tz), tz
	elseif key == "ult" then
		local range = L.v(api, h, "ult", "range", rank)
		local hero = L.enemyHero(api, x, z, range, h.ally)
		local t = hero or api.mostValuableEnemy(x, z, range, h.ally)
		if t and (hero or api.cost(t) >= 3000) then
			local tx, ty, tz = api.pos(t)
			return tx, ty, tz, t
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	if h.store.prism then
		L.detach(api, h.store.prism.fx)
	end
	h.store.prism, h.store.lance = nil, nil
end

return M
