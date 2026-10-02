-- Shared helpers of the Cortex hero modules (luarules/heroes/cort4*.lua): colours, nil-safe GG.HeroFX calls,
-- target picks, ballistic lobs, ground pools (lava / fire) and burns. Not a hero module itself (no hero is named
-- cort4_lib): each module VFS.Include's it. All synced; every effect goes through GG.HeroFX (shaders, no CEGs).

local L = {}

local max, min, sqrt, floor, random = math.max, math.min, math.sqrt, math.floor, math.random
local spGetGroundHeight = Spring.GetGroundHeight
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitDefID = Spring.GetUnitDefID

-- Cortex palette (roster_cor.md): hot orange, red, amber, white-hot; EMP cyan, nano green
L.ORANGE = { 1, 0.45, 0.1, 1 }
L.RED = { 1, 0.2, 0.1, 1 }
L.AMBER = { 1, 0.7, 0.25, 1 }
L.WHITE = { 1, 0.95, 0.85, 1 }
L.CYAN = { 0.45, 0.85, 1, 1 }
L.GREEN = { 0.35, 1, 0.45, 1 }
L.LAVA = { 1, 0.4, 0.05, 1 }

function L.col(c, a)
	return { c[1], c[2], c[3], a or c[4] or 1 }
end

---------------------------------------------------------------------------- fx (nil-safe)

local function F(api)
	return api.fx
end

local function call(api, name, ...)
	local fx = api.fx
	local fn = fx and fx[name]
	if fn then
		return fn(...)
	end
end

function L.ring(api, x, z, o) return call(api, "ring", x, z, o) end
function L.flash(api, x, y, z, o) return call(api, "flash", x, y, z, o) end
function L.beam(api, x1, y1, z1, x2, y2, z2, o) return call(api, "beam", x1, y1, z1, x2, y2, z2, o) end
function L.bolt(api, x1, y1, z1, x2, y2, z2, o) return call(api, "bolt", x1, y1, z1, x2, y2, z2, o) end
function L.chain(api, pts, o) return call(api, "chain", pts, o) end
function L.pillar(api, x, z, o) return call(api, "pillar", x, z, o) end
function L.zone(api, x, z, o) return call(api, "zone", x, z, o) end
function L.attach(api, uid, kind, o) return call(api, "attach", uid, kind, o) end
function L.attachPoint(api, x, z, kind, o) return call(api, "attachPoint", x, z, kind, o) end
function L.set(api, id, o) if id then return call(api, "set", id, o) end end
function L.hitFx(api, id, x, y, z) if id then return call(api, "hit", id, x, y, z) end end
function L.detach(api, id)
	if id then
		call(api, "detach", id)
	end
end
function L.detachAll(api, ids)
	for k, id in pairs(ids or {}) do
		L.detach(api, id)
		ids[k] = nil
	end
end
L.F = F

---------------------------------------------------------------------------- small helpers

function L.b(h, key)
	return h.def.cfg[key]
end

-- rank value of a field of ability `key` (current rank)
function L.v(api, h, key, field, r)
	return api.val(h.def.cfg[key][field], r or api.rank(h, key))
end

function L.gy(x, z)
	return max(0, spGetGroundHeight(x, z))
end

function L.d2(x1, z1, x2, z2)
	return (x1 - x2) ^ 2 + (z1 - z2) ^ 2
end

function L.alive(uid)
	return uid and Spring.ValidUnitID(uid) and not Spring.GetUnitIsDead(uid)
end

function L.isAir(uid)
	local ud = UnitDefs[spGetUnitDefID(uid) or -1]
	return ud and ud.canFly or false
end

function L.isStructure(uid)
	local ud = UnitDefs[spGetUnitDefID(uid) or -1]
	return ud and (ud.isImmobile or (ud.speed or 0) == 0) or false
end

function L.maxHp(api, uid)
	local _, m = Spring.GetUnitHealth(uid)
	local h = api.hero(uid)
	return (m or 0) * (h and h.hpMult or 1)
end

function L.hpFrac(uid)
	local hp, m = Spring.GetUnitHealth(uid)
	return hp and m and m > 0 and hp / m or 0
end

function L.radius(uid)
	return Spring.GetUnitRadius(uid) or 30
end

-- visible enemies within r of x, z
function L.enemies(api, h, x, z, r)
	local out = {}
	for _, uid in ipairs(api.enemiesIn(x, z, r, h.ally)) do
		if api.seenBy(uid, h.ally) then
			out[#out + 1] = uid
		end
	end
	return out
end

function L.enemyHero(api, h, x, z, r, maxFrac)
	local best, bestF
	for _, uid in ipairs(L.enemies(api, h, x, z, r)) do
		if api.isHero(uid) then
			local f = L.hpFrac(uid)
			if (not maxFrac or f <= maxFrac) and (not bestF or f < bestF) then
				best, bestF = uid, f
			end
		end
	end
	return best
end

-- the most valuable visible enemy (heroes x3), skipping `skip[uid]`, optional filter(uid)
function L.mostValuable(api, h, x, z, r, skip, filter)
	local best, bestC = nil, 0
	for _, uid in ipairs(L.enemies(api, h, x, z, r)) do
		if not (skip and skip[uid]) and (not filter or filter(uid)) then
			local c = api.cost(uid) * (api.isHero(uid) and 3 or 1)
			if c > bestC then
				best, bestC = uid, c
			end
		end
	end
	return best, bestC
end

-- centroid of the visible enemies within r (and their count)
function L.enemyCentroid(api, h, x, z, r)
	local sx, sz, n = 0, 0, 0
	for _, uid in ipairs(L.enemies(api, h, x, z, r)) do
		local ux, _, uz = spGetUnitPosition(uid)
		sx, sz, n = sx + ux, sz + uz, n + 1
	end
	if n == 0 then
		return nil
	end
	return sx / n, sz / n, n
end

-- a point `dist` from x, z away from (ax, az) (escape), clamped to the map
function L.away(x, z, ax, az, dist)
	local dx, dz = x - ax, z - az
	local d = max(1, sqrt(dx * dx + dz * dz))
	return L.clampX(x + dx / d * dist), L.clampZ(z + dz / d * dist)
end

function L.toward(x, z, tx, tz, dist)
	local dx, dz = tx - x, tz - z
	local d = max(1, sqrt(dx * dx + dz * dz))
	dist = min(dist, d)
	return L.clampX(x + dx / d * dist), L.clampZ(z + dz / d * dist), d
end

function L.clampX(x)
	return max(64, min(Game.mapSizeX - 64, x))
end
function L.clampZ(z)
	return max(64, min(Game.mapSizeZ - 64, z))
end

-- the allies' centroid within r (escape target)
function L.allyCentroid(api, h, x, z, r, selfID)
	local sx, sz, n = 0, 0, 0
	for _, uid in ipairs(api.alliesIn(x, z, r, h.ally)) do
		if uid ~= selfID then
			local ux, _, uz = spGetUnitPosition(uid)
			sx, sz, n = sx + ux, sz + uz, n + 1
		end
	end
	if n == 0 then
		return nil
	end
	return sx / n, sz / n
end

-- an escape point: away from the enemies, toward the allies
function L.escapePoint(api, h, unitID, dist)
	local x, _, z = spGetUnitPosition(unitID)
	local ex, ez = L.enemyCentroid(api, h, x, z, 1500)
	local ax, az = L.allyCentroid(api, h, x, z, 2500, unitID)
	if ax and L.d2(ax, az, x, z) > 200 * 200 then
		return L.toward(x, z, ax, az, dist)
	elseif ex then
		return L.away(x, z, ex, ez, dist)
	end
	return nil
end

-- hp lost recently (share of max): h.store._hpLog keeps {frame, frac}
function L.hpDrop(h, unitID, f, seconds)
	local log = h.store._hpLog
	if not log then
		log = {}
		h.store._hpLog = log
	end
	local frac = L.hpFrac(unitID)
	log[#log + 1] = { f, frac }
	while #log > 1 and log[1][1] < f - seconds * 30 do
		table.remove(log, 1)
	end
	return max(0, log[1][2] - frac)
end

---------------------------------------------------------------------------- projectiles

-- a ballistic lob of the hero's extra weapondef `name` from p0 to p1 in `seconds` (arc by the given gravity, elmos per
-- frame^2); the projectile is only the look (no engine damage, api.abProj): onImpact(x, y, z) runs by the clock when
-- it lands - also when the hero died meanwhile
function L.lob(api, h, unitID, name, x0, y0, z0, x1, y1, z1, seconds, onImpact, gravity)
	local frames = max(5, floor(seconds * 30))
	local wdid = h.def.extra[name]
	if wdid then
		local g = -(gravity or 0.16)
		local vx, vz = (x1 - x0) / frames, (z1 - z0) / frames
		local vy = ((y1 - y0) - 0.5 * g * frames * frames) / frames
		local pid = Spring.SpawnProjectile(wdid, {
			pos = { x0, y0, z0 }, speed = { vx, vy, vz }, owner = L.alive(unitID) and unitID or -1, team = h.team, gravity = g,
			ttl = frames + 30,
		})
		if pid then
			api.abProj[pid] = api.frame() + frames + 60
		end
	else
		api.log("%s: no weapondef %s", h.def.name, name)
	end
	if onImpact then
		api.delay(frames, function()
			onImpact(x1, y1, z1)
		end)
	end
	return frames
end

-- a straight shot of an extra weapondef with the ability's own handling: fn(x, y, z) on impact (no engine damage)
function L.shot(api, h, unitID, name, x0, y0, z0, x1, y1, z1, speed, onImpact, targetID)
	local wdid = h.def.extra[name]
	if not wdid then
		api.log("%s: no weapondef %s", h.def.name, name)
		return nil
	end
	local dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
	local d = max(1, sqrt(dx * dx + dy * dy + dz * dz))
	local s = speed or (WeaponDefs[wdid].projectilespeed or 20)
	local pid = Spring.SpawnProjectile(wdid, {
		pos = { x0, y0, z0 }, speed = { dx / d * s, dy / d * s, dz / d * s }, owner = unitID, team = h.team, gravity = 0,
		ttl = floor(d / s) + 150, tracking = targetID,
	})
	if pid then
		if targetID then
			Spring.SetProjectileTarget(pid, targetID, string.byte("u"))
		else
			Spring.SetProjectileTarget(pid, x1, y1, z1)
		end
		api.abProj[pid] = api.frame() + floor(d / s) + 200
		h.store._lob = h.store._lob or {}
		h.store._lob[pid] = onImpact or true
	end
	return pid
end

-- a strike from the sky: a visual projectile of `name` falls from `height` above (x, z) (slightly slanted) and
-- onImpact(x, y, z) runs when it lands, by the clock (it works even if the hero died meanwhile)
function L.drop(api, h, unitID, name, x, z, height, speed, onImpact, slant)
	local gy = L.gy(x, z)
	local sl = slant or 0.25
	local a = random() * 6.283
	local ox, oz = math.cos(a) * height * sl, math.sin(a) * height * sl
	local x0, y0, z0 = x + ox, gy + height, z + oz
	local dist = sqrt(ox * ox + oz * oz + height * height)
	local frames = max(2, floor(dist / speed))
	local wdid = h.def.extra[name]
	if wdid then
		local pid = Spring.SpawnProjectile(wdid, {
			pos = { x0, y0, z0 }, speed = { (x - x0) / frames, (gy - y0) / frames, (z - z0) / frames },
			owner = L.alive(unitID) and unitID or -1, team = h.team, gravity = 0, ttl = frames + 30,
		})
		if pid then
			api.abProj[pid] = api.frame() + frames + 60
		end
	end
	api.delay(frames, function()
		onImpact(x, gy, z)
	end)
	return frames
end

-- the module's impact hook calls this first: true when it was one of the lib's projectiles
function L.impact(api, unitID, h, weaponDefID, x, y, z, projectileID)
	local t = h.store._lob
	local fn = t and projectileID and t[projectileID]
	if not fn then
		return false
	end
	t[projectileID] = nil
	if type(fn) == "function" then
		local ok, err = pcall(fn, x, y, z)
		if not ok then
			Spring.Echo("[cort4] impact error " .. h.def.name .. ": " .. tostring(err))
		end
	end
	return true
end

---------------------------------------------------------------------------- ground pools and burns

-- a damaging pool (lava / fire wall) at x, z: dps for `seconds` (ability damage, ticks every 0.5 s); the look
-- is drawn once at creation (zone + optional flash)
function L.pool(api, h, unitID, x, z, r, dps, seconds, o)
	o = o or {}
	h.store._pools = h.store._pools or {}
	local f = api.frame()
	local p = { x = x, z = z, r = r, dps = dps, untilF = f + floor(seconds * 30), dtype = o.dtype or "flame", heat = o.heat,
		line = o.line }
	h.store._pools[#h.store._pools + 1] = p
	if not o.noFx then
		p.fx = L.zone(api, x, z, { radius = r, pattern = o.pattern or "heat", color = o.color or L.col(L.LAVA, 0.9), ttl = seconds })
	end
	return p
end

-- a burn on a unit: dps for `seconds` (refreshes, the stronger one wins)
function L.burn(api, h, uid, dps, seconds)
	h.store._burns = h.store._burns or {}
	local f = api.frame()
	local b = h.store._burns[uid]
	local untilF = f + floor(seconds * 30)
	if not b or b.untilF < f or dps >= b.dps then
		h.store._burns[uid] = { dps = dps, untilF = untilF }
	else
		b.untilF = max(b.untilF, untilF)
	end
end

-- every frame call (cheap): pools and burns tick every 15 frames
function L.tick(api, unitID, h, f)
	if f % 15 ~= 0 then
		return
	end
	local pools = h.store._pools
	if pools and #pools > 0 then
		local keep = {}
		for _, p in ipairs(pools) do
			if p.untilF > f then
				keep[#keep + 1] = p
				local hits
				if p.line then
					hits = api.line(p.line[1], p.line[2], p.line[3], p.line[4], p.r * 2, p.dps * 0.5, unitID, { dtype = p.dtype })
				else
					hits = api.area(p.x, p.z, p.r, p.dps * 0.5, unitID, { dtype = p.dtype })
				end
				if p.onTick then
					p.onTick(hits)
				end
			end
		end
		h.store._pools = keep
	end
	local burns = h.store._burns
	if burns then
		for uid, b in pairs(burns) do
			if b.untilF <= f or not L.alive(uid) then
				burns[uid] = nil
			else
				api.damage(uid, b.dps * 0.5, unitID, { dtype = "flame" })
			end
		end
	end
end

---------------------------------------------------------------------------- pass-through slugs

-- a DGun slug (noexplode) damages a unit on every frame it overlaps it (x4..x15 on big targets, the first contact at
-- the edge of its blast for ~15%): one shot counts once per victim, at the weapon's full damage.
-- L.slugHit(api, h, victimID, weaponDefID, damage, weaponNum) -> the damage to deal (0 for a repeat)
function L.slugHit(api, h, victimID, weaponDefID, damage, n, window)
	if L.repeatHit(api, h, victimID, weaponDefID, window) then
		return 0
	end
	local w = n and h.def.weapons[n]
	return w and math.max(damage, w.damage * (h.dmgMult or 1)) or damage
end

function L.repeatHit(api, h, victimID, weaponDefID, window)
	local f = api.frame()
	local seen = h.store._slug
	if not seen then
		seen = {}
		h.store._slug = seen
	end
	local key = victimID * 65536 + weaponDefID
	local last = seen[key]
	if last and f - last < (window or 15) then
		return true
	end
	seen[key] = f
	if f % 300 == 0 then
		for k, t in pairs(seen) do
			if f - t > 60 then
				seen[k] = nil
			end
		end
	end
	return false
end

---------------------------------------------------------------------------- movement callbacks

-- run fn on the next frame. Movement callbacks (api.dash / throw / downed onLand, onStep) run inside the core's
-- movers loop: a unit killed or a new movement started there changes that table while it is traversed ("invalid key
-- to 'next'"), so anything that may kill, push or dash goes through this
function L.later(api, fn)
	api.delay(1, fn)
end

---------------------------------------------------------------------------- debug numbers

-- "[ability]" log lines (benches: game rules param hero_ability_log = 1)
function L.log(api, h, fmt, ...)
	api.log(h.def.name .. " " .. fmt, ...)
end

return L
