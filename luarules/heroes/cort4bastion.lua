-- Juggernaut, the Unkillable (cort4bastion, corjugg x1.6) - doc/v19-heroes/roster_cor.md section 0, SPEC 1.8.
-- Numbers: luarules/configs/heroes/cor.lua (cort4bastion). API: header of luarules/gadgets/unit_t4_heroes.lua.
--   a1 Power Shot (active, unit): the turret locks on and fires 4..8 gauss shells, 0.25 s apart; every shell that hits
--      the target adds 8% to the next; everything else on the line takes half. Immobile while firing.
--   a2 Circle Beam (active, self): anchored 3 s (-25% damage taken), the twin laser sweeps 360..540 deg around it;
--      every enemy it crosses takes the pass damage and burns for 4 s.
--   a3 Reactive Armor (passive): a hit of 300+ (not a beam) may fire a plasma shell back from the armour.
--   ult Resurrection (passive): a lethal hit drops it for 3 s (downed), then it rises with a stunning shockwave and
--      is Unbroken for 6 s (+damage, faster reload). The rank lowers the cooldown.

local L = VFS.Include("luarules/heroes/cort4_lib.lua")
local M = {}

local floor, max, min, sqrt, abs, pi = math.floor, math.max, math.min, math.sqrt, math.abs, math.pi
local TWO_PI = 2 * pi

local function b(h, key)
	return h.def.cfg[key]
end

---------------------------------------------------------------------------- a1 Power Shot

local function muzzle(api, unitID)
	return api.piecePos(unitID, "mainbarrelflare")
end

local function powerShell(api, unitID, h, ps, i)
	if not L.alive(unitID) then
		return
	end
	local mx, my, mz = muzzle(api, unitID)
	local t = ps.target
	local tx, ty, tz
	if L.alive(t) then
		tx, ty, tz = api.pos(t)
		ty = ty + 25
		ps.lx, ps.ly, ps.lz = tx, ty, tz
	else
		tx, ty, tz = ps.lx, ps.ly, ps.lz
	end
	if not tx then
		return
	end
	local d = ps.dmg * ps.mult
	L.flash(api, mx, my, mz, { radius = 90, color = L.ORANGE, ttl = 0.15, ground = false })
	L.beam(api, mx, my, mz, tx, ty, tz, { color = L.ORANGE, width = 14, ttl = 0.14, flare = 1.6, pulse = 2 })
	local last = i == ps.count
	L.shot(api, h, unitID, "powershot", mx, my, mz, tx, ty, tz, nil, function(ix, iy, iz)
		local hitTarget = false
		if L.alive(t) then
			local ux, _, uz = api.pos(t)
			if L.d2(ux, uz, ix, iz) <= (L.radius(t) + 90) ^ 2 then
				hitTarget = true
				api.damage(t, d, unitID, { dtype = "plasma" })
				ps.mult = ps.mult * (1 + (ps.stack or 0.08))
				ps.dealt = (ps.dealt or 0) + d
			end
		end
		-- the slug pierces: everything on the line from the muzzle to the impact (and a little beyond) takes half
		local ex, ez = ix + (ix - mx) * 0.25, iz + (iz - mz) * 0.25
		local line = api.line(mx, mz, ex, ez, 90, 0, unitID)
		local others = 0
		for _, uid in ipairs(line) do
			if uid ~= t then
				api.damage(uid, d * ps.pierce, unitID, { dtype = "plasma" })
				others = others + 1
			end
		end
		L.flash(api, ix, iy, iz, { radius = 110, color = L.WHITE, ttl = 0.25 })
		L.ring(api, ix, iz, { kind = "shock", r0 = 20, r1 = 130, width = 20, ttl = 0.25, color = L.col(L.ORANGE, 0.8) })
		if last then
			L.ring(api, ix, iz, { kind = "shock", r0 = 50, r1 = 320, width = 40, ttl = 0.4, color = L.ORANGE })
			L.flash(api, ix, iy, iz, { radius = 220, color = L.ORANGE, ttl = 0.4 })
		end
		L.log(api, h, "a1 power shot %d/%d dmg=%d hitTarget=%s pierced=%d mult=%.2f total=%d", i, ps.count, d, tostring(hitTarget),
			others, ps.mult, ps.dealt or 0)
	end)
end

local function powerShot(api, unitID, h, r, x, z, targetID)
	local a1 = b(h, "a1")
	if not (targetID and L.alive(targetID)) and x then
		local near = api.nearestEnemies(x, z, 250, h.ally, 1)
		targetID = near[1]
	end
	if not (targetID and L.alive(targetID)) or Spring.GetUnitAllyTeam(targetID) == h.ally then
		return false
	end
	local count = api.val(a1.count, r)
	local interval = a1.interval or 0.25
	local ps = { target = targetID, count = count, dmg = api.val(a1.dmg, r) * api.power(h), mult = 1, stack = a1.stack,
		pierce = a1.pierce or 0.5 }
	h.store.ps = ps
	local dur = count * interval + 0.4
	api.buff(unitID, h, "powershot", dur, { immobile = true })
	api.forceTarget(unitID, targetID, dur)
	api.active(unitID, "a1", dur)
	local tx, _, tz = api.pos(targetID)
	L.ring(api, tx, tz, { kind = "hex", r0 = 140, r1 = 60, width = 18, ttl = count * interval + 0.3, color = L.col(L.RED, 0.8) })
	L.attach(api, targetID, "mark", { color = L.col(L.RED, 0.9), radius = 70, stacks = count, max = count, ttl = dur })
	for i = 1, count do
		api.delay(floor((i - 1) * interval * 30) + 4, function()
			powerShell(api, unitID, h, ps, i)
		end)
	end
	L.log(api, h, "a1 cast rank=%d count=%d dmg=%d target=%s", r, count, ps.dmg, UnitDefs[Spring.GetUnitDefID(targetID)].name)
	return true
end

-- the enemy line from the hero that crosses the most enemies (AI fallback)
local function bestLine(api, h, x, z, range)
	local list = L.enemies(api, h, x, z, range)
	local best, bestN = nil, 0
	for i = 1, min(#list, 14) do
		local t = list[i]
		local tx, _, tz = api.pos(t)
		local dx, dz = tx - x, tz - z
		local len = max(1, sqrt(dx * dx + dz * dz))
		local n = 0
		for _, u in ipairs(list) do
			local ux, _, uz = api.pos(u)
			local s = ((ux - x) * dx + (uz - z) * dz) / len
			if s > 0 and s < len * 1.3 then
				local px, pz = x + dx / len * s, z + dz / len * s
				if L.d2(px, pz, ux, uz) < 90 * 90 then
					n = n + 1
				end
			end
		end
		if n > bestN then
			best, bestN = t, n
		end
	end
	return best, bestN
end

---------------------------------------------------------------------------- a2 Circle Beam

local function yawDir(yaw)
	return math.sin(yaw), math.cos(yaw)
end

local function circleBeam(api, unitID, h, r)
	local a2 = b(h, "a2")
	if h.store.cb then
		return false
	end
	local dur = a2.duration or 3
	local sweep = api.val(a2.sweep, r)
	local len = api.val(a2.length, r)
	local cb = {
		len = len, dmg = api.val(a2.dmg, r) * api.power(h), burn = api.val(a2.burn, r) * api.power(h), burnTime = a2.burnTime or 4,
		width = api.val(a2.width, r), sweep = math.rad(sweep), passes = {}, swept = 0, hits = 0, dealt = 0, steps = 0,
		untilF = api.frame() + floor(dur * 30),
	}
	local x, _, z = api.pos(unitID)
	cb.x, cb.z = x, z
	local _, yaw0 = Spring.GetUnitRotation(unitID)
	cb.yaw0 = yaw0 or 0
	cb.prev = cb.yaw0
	h.store.cb = cb
	api.buff(unitID, h, "circlebeam", dur, { immobile = true, armor = a2.armor or 0.25 })
	api.active(unitID, "a2", dur)
	local rate = sweep / dur -- deg/s
	cb.rate = math.rad(rate)
	api.turretSpin(unitID, dur, rate, function(yaw, px, pz)
		local c = h.store.cb
		if not c then
			return
		end
		c.steps = c.steps + 1
		local dyaw = yaw - c.prev
		c.prev = yaw
		c.swept = c.swept + abs(dyaw)
		local dx, dz = yawDir(yaw)
		-- the beam: two parallel lasers from the lower laser flares (they turn with the hull)
		if c.steps % 2 == 1 then
			local gy = L.gy(px, pz)
			for _, piece in ipairs({ "rlaserflare", "llaserflare" }) do
				local fx, fy, fz = api.piecePos(unitID, piece)
				local ex, ez = fx + dx * c.len, fz + dz * c.len
				L.beam(api, fx, fy, fz, ex, L.gy(ex, ez) + 8, ez, { color = { 1, 0.35, 0.1, 1 }, width = 14, ttl = 0.16,
					pulse = 3, flare = 1.4 })
			end
			local tx, tz = px + dx * c.len, pz + dz * c.len
			L.flash(api, tx, L.gy(tx, tz) + 10, tz, { radius = 90, color = L.ORANGE, ttl = 0.6 })
			if c.steps % 4 == 1 then
				local mx, mz = px + dx * c.len * 0.55, pz + dz * c.len * 0.55
				L.flash(api, mx, L.gy(mx, mz) + 8, mz, { radius = 55, color = { 1, 0.5, 0.15, 0.7 }, ttl = 0.6 })
			end
			if gy then
				c.gy = gy
			end
		end
		-- damage: every enemy whose bearing the beam swept past (once per pass)
		for _, uid in ipairs(api.enemiesIn(px, pz, c.len + 40, h.ally)) do
			local ux, _, uz = api.pos(uid)
			local ex, ez = ux - px, uz - pz
			local dist = sqrt(ex * ex + ez * ez)
			if dist > 20 then
				local uyaw = math.atan2(ex, ez)
				-- bearing relative to the start, in the sweep direction
				local rel = (uyaw - c.yaw0) % TWO_PI
				local tol = math.atan((c.width + L.radius(uid) * 0.5) / dist)
				local pass = floor((c.swept - rel + tol) / TWO_PI)
				if c.swept + tol >= rel and pass >= 0 and (c.passes[uid] or -1) < pass then
					c.passes[uid] = pass
					api.damage(uid, c.dmg, unitID, { dtype = "laser" })
					L.burn(api, h, uid, c.burn, c.burnTime)
					c.hits = c.hits + 1
					c.dealt = c.dealt + c.dmg
				end
			end
		end
	end)
	L.ring(api, x, z, { kind = "rune", r0 = len, r1 = len, width = 26, ttl = dur, color = L.col(L.ORANGE, 0.35), rot = 0.6 })
	L.ring(api, x, z, { kind = "glow", r0 = 60, r1 = 180, width = 40, ttl = dur, color = L.col(L.ORANGE, 0.5) })
	L.log(api, h, "a2 cast rank=%d sweep=%d len=%d dmg=%d burn=%d", r, sweep, len, cb.dmg, cb.burn)
	return true
end

local function circleBeamEnd(api, unitID, h)
	local cb = h.store.cb
	h.store.cb = nil
	if not cb then
		return
	end
	L.ring(api, cb.x, cb.z, { kind = "shock", r0 = cb.len * 0.3, r1 = cb.len, width = 50, ttl = 0.5, color = L.ORANGE })
	L.log(api, h, "a2 done swept=%d deg hits=%d dealt=%d", math.deg(cb.swept), cb.hits, cb.dealt)
end

---------------------------------------------------------------------------- a3 Reactive Armor

local isBeamWeapon = {}
for wdid, wd in pairs(WeaponDefs) do
	if wd.type == "BeamLaser" or wd.type == "LightningCannon" then
		isBeamWeapon[wdid] = true
	end
end

local function reactive(api, unitID, h, dm, attackerID, weaponDefID, ax, az)
	local r = api.rank(h, "a3")
	if r <= 0 or (weaponDefID and isBeamWeapon[weaponDefID]) then
		return
	end
	local a3 = b(h, "a3")
	local eff = dm * (h.hpMult or 1)
	if eff < (a3.minHit or 300) then
		return
	end
	local f = api.frame()
	if f < (h.store.reactiveReady or 0) then
		return
	end
	if math.random() >= api.val(a3.chance, r) then
		return
	end
	h.store.reactiveReady = f + floor((a3.icd or 0.2) * 30)
	local x, y, z = api.pos(unitID)
	local target
	if attackerID and L.alive(attackerID) and Spring.GetUnitAllyTeam(attackerID) ~= h.ally then
		local tx, _, tz = api.pos(attackerID)
		if L.d2(tx, tz, x, z) <= 1200 * 1200 then
			target = attackerID
		end
	end
	if not target then
		target = api.nearestEnemies(x, z, 800, h.ally, 1)[1]
	end
	if not target then
		return
	end
	local tx, ty, tz = api.pos(target)
	-- the armour plate that was hit: on the hull toward the attacker
	local hx, hz = ax or tx, az or tz
	local dx, dz = hx - x, hz - z
	local dd = max(1, sqrt(dx * dx + dz * dz))
	local rad = L.radius(unitID) * 0.7
	local px, py, pz = x + dx / dd * rad, y + 45, z + dz / dd * rad
	local dmg = min(a3.cap or 10000, api.val(a3.dmg, r) + (a3.share or 0.5) * eff) * api.power(h)
	local shells = api.val(a3.shells, r)
	L.ring(api, px, pz, { kind = "hex", r0 = 60, r1 = 110, width = 16, ttl = 0.25, color = L.col(L.AMBER, 0.6) })
	L.flash(api, px, py, pz, { radius = 70, color = L.AMBER, ttl = 0.3 })
	for s = 1, shells do
		local ox, oz = (s - 1) * 40 * (dz / dd), -(s - 1) * 40 * (dx / dd)
		L.shot(api, h, unitID, "reactive", px + ox, py, pz + oz, tx, ty + 20, tz, nil, function(ix, iy, iz)
			local hits = api.area(ix, iz, a3.aoe or 120, dmg, unitID, { dtype = "plasma" })
			L.flash(api, ix, iy, iz, { radius = 120, color = L.AMBER, ttl = 0.3 })
			L.log(api, h, "a3 reactive shell dmg=%d hit=%d (trigger %d)", dmg, #hits, eff)
		end, target)
	end
end

---------------------------------------------------------------------------- ult Resurrection

local function rise(api, unitID, h)
	local ult = b(h, "ult")
	local r = max(1, api.rank(h, "ult"))
	local st = h.store.res
	h.store.res = nil
	if st then
		L.detachAll(api, st.fx)
	end
	local _, maxHp = Spring.GetUnitHealth(unitID)
	if maxHp then
		Spring.SetUnitHealth(unitID, maxHp * api.val(ult.heal, r))
	end
	local x, y, z = api.pos(unitID)
	local nova = api.val(ult.nova, r) * api.power(h)
	local hits = api.area(x, z, ult.novaRadius or 600, nova, unitID, { stun = ult.stun or 1.5, dtype = "plasma" })
	local dur = ult.unbroken or 6
	api.buff(unitID, h, "unbroken", dur, { damage = api.val(ult.damage, r), reload = ult.reload or 0.43 })
	api.active(unitID, "ult", dur)
	L.ring(api, x, z, { kind = "shock", r0 = 80, r1 = ult.novaRadius or 600, width = 70, ttl = 0.6, color = L.ORANGE })
	L.ring(api, x, z, { kind = "fire", r0 = 60, r1 = (ult.novaRadius or 600) * 0.9, width = 90, ttl = 0.9, color = L.col(L.RED, 0.9) })
	L.flash(api, x, y + 40, z, { radius = 320, color = L.WHITE, ttl = 0.5 })
	L.pillar(api, x, z, { radius = 90, height = 700, color = L.col(L.ORANGE, 0.9), ttl = 0.8 })
	h.store.unbroken = {
		L.attach(api, unitID, "aura", { radius = 220, color = L.col(L.RED, 0.8), pattern = "heat", ttl = dur }),
		L.attach(api, unitID, "electric", { color = L.RED, intensity = 1.2, ttl = dur }),
		L.attach(api, unitID, "tint", { pattern = "heat", color = L.RED, strength = 0.5, ttl = dur }),
	}
	L.log(api, h, "ult rise rank=%d hp=%.2f nova=%d hit=%d unbroken=+%.2f", r, api.val(ult.heal, r), nova, #hits, api.val(ult.damage, r))
end

local function fall(api, unitID, h)
	local ult = b(h, "ult")
	local r = api.rank(h, "ult")
	local x, y, z = api.pos(unitID)
	local down = ult.down or 3
	api.cooldown(unitID, h, "ult", api.val(ult.cooldown, r))
	h.store.res = {
		fx = {
			L.attach(api, unitID, "electric", { color = { 0.7, 0.12, 0.05, 1 }, intensity = 0.5, ttl = down }),
			L.attach(api, unitID, "tint", { pattern = "stone", strength = 0.6, ttl = down }),
		},
	}
	L.flash(api, x, y + 40, z, { radius = 260, color = { 1, 0.7, 0.5, 0.8 }, ttl = 0.5 })
	L.ring(api, x, z, { kind = "rune", r0 = 300, r1 = 80, width = 34, ttl = down, color = L.col(L.RED, 0.85), rot = 1.2 })
	L.pillar(api, x, z, { radius = 120, height = 900, color = { 1, 0.3, 0.08, 0.85 }, ttl = down, ring = true })
	api.downed(unitID, h, down, function(a, u, hh)
		L.later(a, function()
			if L.alive(u) then
				rise(a, u, hh)
			end
		end)
	end)
	L.log(api, h, "ult fall rank=%d cooldown=%d", r, api.val(ult.cooldown, r))
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.ps = nil
	h.store.cb = nil
	h.store.res = nil
end

function M.frame(api, unitID, h, f)
	L.tick(api, unitID, h, f)
	local cb = h.store.cb
	if cb and f >= cb.untilF then
		circleBeamEnd(api, unitID, h)
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a1" then
		return powerShot(api, unitID, h, rank, x, z, targetID)
	elseif key == "a2" then
		return circleBeam(api, unitID, h, rank)
	end
	return false
end

-- the Gauss DGun slug pierces (noexplode): one shot counts once per victim (L.repeatHit)
function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	local n = h.def.keyNum.juggernaut_fire and h.def.keyNum.juggernaut_fire[1]
	if n and h.def.weapons[n].wdid == weaponDefID then
		return L.slugHit(api, h, victimID, weaponDefID, damage, n, 15)
	end
	return damage
end

function M.damaged(api, unitID, h, damage, attackerID, weaponDefID, isParalyzer, ax, az)
	if not isParalyzer and damage > 0 then
		reactive(api, unitID, h, damage, attackerID, weaponDefID, ax, az)
	end
	return damage
end

function M.dying(api, unitID, h)
	if h.store.res or api.rank(h, "ult") <= 0 or not api.ready(h, "ult") then
		return false
	end
	fall(api, unitID, h)
	return true
end

function M.impact(api, unitID, h, weaponDefID, x, y, z, projectileID)
	L.impact(api, unitID, h, weaponDefID, x, y, z, projectileID)
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	local hpf = L.hpFrac(unitID)
	if key == "a1" then
		if hpf < 0.25 then
			return nil
		end
		local range = api.val(b(h, "a1").range, rank)
		local t = L.enemyHero(api, h, x, z, range)
		if not t then
			local best, cost = L.mostValuable(api, h, x, z, range)
			if best and cost >= 8000 then
				t = best
			end
		end
		if not t then
			local lt, n = bestLine(api, h, x, z, range)
			if lt and n >= 4 then
				t = lt
			end
		end
		if t then
			local tx, ty, tz = api.pos(t)
			return tx, ty, tz, t
		end
	elseif key == "a2" then
		if hpf < 0.25 then
			return nil
		end
		local len = api.val(b(h, "a2").length, rank)
		local cost, n = api.enemyCostNear(x, z, len, h.ally)
		if n >= 5 or cost >= 6000 then
			return x, y, z
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	h.store.cb = nil
	if h.store.res then
		L.detachAll(api, h.store.res.fx)
		h.store.res = nil
	end
end

return M
