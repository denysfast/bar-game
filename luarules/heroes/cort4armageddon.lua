-- Armageddon, the Doomsayer (cort4armageddon, corcat x2) - doc/v19-heroes/roster_cor.md section 3.
--   a1 Cluster Warheads (passive): every 2nd rocket of a salvo splits on impact into 2..5 bomblets (aoe 90, scatter
--      150), each 10..25% of the rocket's damage; at most 60 bomblets per salvo.
--   a2 Doom Painter (active, unit in 3200): a painter laser holds the target 4 s: +15..40% damage taken from all
--      sources, and the rockets fired meanwhile home on it (on a neighbour if it dies).
--   a3 Retro Rockets (active, map): leaps 500..900; the takeoff spot burns (300) and slows 50% for 3 s.
--   ult Armageddon Protocol (active, map, radius 700): 2 s warning, 6 s of rocket rain, then a tactical nuke.

local L = VFS.Include("luarules/heroes/cort4_lib.lua")
local M = {}

local floor, max, min, sqrt, random, cos, sin = math.floor, math.max, math.min, math.sqrt, math.random, math.cos, math.sin

local function b(h, key)
	return h.def.cfg[key]
end

local function rocketInfo(h)
	local n = h.def.keyNum.exp_heavyrocket and h.def.keyNum.exp_heavyrocket[1]
	return n and h.def.weapons[n]
end

---------------------------------------------------------------------------- a1 Cluster Warheads

local function cluster(api, unitID, h, x, y, z)
	local r = api.rank(h, "a1")
	local a1 = b(h, "a1")
	local st = h.store
	st.impacts = (st.impacts or 0) + 1
	if st.impacts % 2 ~= 0 or (st.bomblets or 0) >= (a1.cap or 60) then
		return
	end
	local w = rocketInfo(h)
	local rocket = (w and w.damage or 0) * (h.dmgMult or 1)
	local each = rocket * api.val(a1.share, r)
	local n = min(api.val(a1.bomblets, r), (a1.cap or 60) - (st.bomblets or 0))
	st.bomblets = (st.bomblets or 0) + n
	local aoe = a1.aoe or 90
	local scatter = a1.scatter or 150
	local ally = h.ally
	for _ = 1, n do
		local a = random() * 6.283
		local d = scatter * (0.35 + 0.65 * random())
		local tx, tz = L.clampX(x + cos(a) * d), L.clampZ(z + sin(a) * d)
		L.lob(api, h, unitID, "bomblet", x, y + 8, z, tx, L.gy(tx, tz), tz, 0.45 + random() * 0.2, function(ix, iy, iz)
			local hits = api.area(ix, iz, aoe, each, unitID, { dtype = "rocket", ally = ally })
			L.flash(api, ix, L.gy(ix, iz) + 12, iz, { radius = 60, color = L.ORANGE, ttl = 0.22 })
			st.bombHits = (st.bombHits or 0) + #hits
		end, 0.35)
	end
end

---------------------------------------------------------------------------- a2 Doom Painter

local function doomPainter(api, unitID, h, r, targetID)
	local a2 = b(h, "a2")
	if not (targetID and L.alive(targetID)) or Spring.GetUnitAllyTeam(targetID) == h.ally then
		return false
	end
	local dur = a2.duration or 4
	local vuln = api.val(a2.vuln, r)
	api.mark(targetID, "doom", dur, { vuln = vuln, from = unitID })
	api.forceTarget(unitID, targetID, dur)
	api.active(unitID, "a2", dur)
	h.store.doom = { target = targetID, untilF = api.frame() + floor(dur * 30) }
	local tx, _, tz = api.pos(targetID)
	L.ring(api, tx, tz, { kind = "hex", r0 = 200, r1 = 90, width = 18, ttl = 0.8, color = L.RED })
	h.store.doomFx = {
		L.attach(api, unitID, "link", { target = targetID, style = "beam", color = L.RED, width = 2, ttl = dur }),
		L.attach(api, targetID, "mark", { color = L.RED, radius = L.radius(targetID) + 40, stacks = 4, max = 4, ttl = dur }),
		L.attach(api, targetID, "tint", { pattern = "rim", color = L.RED, strength = 0.7, ttl = dur }),
	}
	L.log(api, h, "a2 doom painter rank=%d vuln=+%.2f target=%s", r, vuln, UnitDefs[Spring.GetUnitDefID(targetID)].name)
	return true
end

-- steer the painted salvo onto the target
local function steer(api, h, f)
	local doom = h.store.doom
	local list = h.store.homing
	if not list or #list == 0 then
		return
	end
	local t = doom and doom.target
	if not L.alive(t) then
		-- the target died: the rockets go for its neighbours
		if doom and doom.lx then
			local near = api.nearestEnemies(doom.lx, doom.lz, 600, h.ally, 1)[1]
			if near then
				doom.target = near
				t = near
			end
		end
	end
	if not L.alive(t) then
		h.store.homing = {}
		return
	end
	local tx, ty, tz = api.pos(t)
	if doom then
		doom.lx, doom.lz = tx, tz
	end
	local keep = {}
	for _, pid in ipairs(list) do
		local px, py, pz = Spring.GetProjectilePosition(pid)
		if px then
			keep[#keep + 1] = pid
			local vx, vy, vz = Spring.GetProjectileVelocity(pid)
			local speed = sqrt(vx * vx + vy * vy + vz * vz)
			local dx, dy, dz = tx - px, ty + 15 - py, tz - pz
			local d = max(1, sqrt(dx * dx + dy * dy + dz * dz))
			local hd = sqrt(dx * dx + dz * dz)
			if vy < 0 or hd < 700 then
				local k = 0.5
				local nx, ny, nz = vx + (dx / d * speed - vx) * k, vy + (dy / d * speed - vy) * k, vz + (dz / d * speed - vz) * k
				Spring.SetProjectileVelocity(pid, nx, ny, nz)
			end
		end
	end
	h.store.homing = keep
end

---------------------------------------------------------------------------- a3 Retro Rockets

local function retro(api, unitID, h, r, x, z)
	local a3 = b(h, "a3")
	if not x then
		return false
	end
	local hx, hy, hz = api.pos(unitID)
	local tx, tz = L.toward(hx, hz, x, z, api.val(a3.range, r))
	if L.d2(tx, tz, hx, hz) < 80 * 80 then
		return false
	end
	local dmg = api.val(a3.dmg, r) * api.power(h)
	local R = a3.radius or 300
	local hits = api.area(hx, hz, R, dmg, unitID, { dtype = "flame" })
	for _, uid in ipairs(hits) do
		api.slow(uid, a3.slow or 0.5, a3.slowTime or 3)
	end
	L.pool(api, h, unitID, hx, hz, R * 0.8, 0, 2.5, { pattern = "fire", color = L.col(L.ORANGE, 0.9) })
	L.flash(api, hx, hy + 20, hz, { radius = 300, color = L.ORANGE, ttl = 0.5 })
	L.ring(api, hx, hz, { kind = "shock", r0 = 50, r1 = 300, width = 40, ttl = 0.45, color = L.ORANGE })
	local trail = L.attach(api, unitID, "trail", { color = { 1, 0.55, 0.25, 0.8 }, width = 60, length = 0.7, ttl = 1.2 })
	local ok = api.dash(unitID, h, tx, tz, { seconds = 0.9, arc = 280, onLand = function(lx, lz)
		L.detach(api, trail)
		L.ring(api, lx, lz, { kind = "shock", r0 = 30, r1 = 150, width = 30, ttl = 0.35, color = L.AMBER })
		L.flash(api, lx, L.gy(lx, lz) + 15, lz, { radius = 120, color = L.AMBER, ttl = 0.3 })
	end })
	L.log(api, h, "a3 retro rockets rank=%d dmg=%d hit=%d leap=%d", r, dmg, #hits, sqrt(L.d2(tx, tz, hx, hz)))
	return ok
end

---------------------------------------------------------------------------- ult Armageddon Protocol

local function protocol(api, unitID, h, r, x, z)
	local ult = b(h, "ult")
	if not x then
		return false
	end
	local hx, _, hz = api.pos(unitID)
	local cx, cz = L.toward(hx, hz, x, z, api.val(ult.range, r))
	local R = ult.radius or 700
	local warn = ult.warn or 2
	local dur = ult.duration or 6
	local count = api.val(ult.count, r)
	local p = api.power(h)
	local dmg = api.val(ult.dmg, r) * p
	local aoe = ult.aoe or 200
	local nuke = api.val(ult.nuke, r) * p
	local ally = h.ally
	local st = { rockets = 0, hits = 0 }
	L.ring(api, cx, cz, { kind = "rune", r0 = R, r1 = R, width = 34, ttl = warn + dur + 1.5, color = L.col(L.RED, 0.6), rot = 0.15 })
	L.ring(api, cx, cz, { kind = "hex", r0 = R * 1.1, r1 = R, width = 20, ttl = warn, color = L.col(L.RED, 0.8) })
	L.pillar(api, cx, cz, { radius = 40, height = 2000, color = L.col(L.RED, 0.9), ttl = warn + 0.3, ring = true })
	for i = 1, count do
		api.delay(floor(warn * 30 + (i - 1) * dur * 30 / count) + 1, function()
			local a = random() * 6.283
			local d = R * sqrt(random())
			local px, pz = L.clampX(cx + cos(a) * d), L.clampZ(cz + sin(a) * d)
			L.drop(api, h, unitID, "rain", px, pz, 1800, 55, function(ix, iy, iz)
				local hits = api.area(ix, iz, aoe, dmg, unitID, { dtype = "rocket", ally = ally })
				st.rockets = st.rockets + 1
				st.hits = st.hits + #hits
				L.flash(api, ix, iy + 25, iz, { radius = 150, color = L.ORANGE, ttl = 0.35 })
				L.ring(api, ix, iz, { kind = "shock", r0 = 20, r1 = aoe, width = 24, ttl = 0.3, color = L.col(L.ORANGE, 0.8) })
			end, 0.2)
		end)
	end
	api.delay(floor((warn + dur) * 30) + 10, function()
		L.drop(api, h, unitID, "nuke", cx, cz, 2400, 50, function(ix, iy, iz)
			local hits = api.area(ix, iz, ult.nukeAoe or 600, nuke, unitID, { dtype = "rocket", ally = ally })
			L.flash(api, ix, iy + 80, iz, { radius = 900, color = L.WHITE, ttl = 0.8 })
			L.ring(api, ix, iz, { kind = "shock", r0 = 100, r1 = 1100, width = 120, ttl = 1.2, color = L.ORANGE })
			L.ring(api, ix, iz, { kind = "fire", r0 = 80, r1 = ult.nukeAoe or 600, width = 160, ttl = 1.5, color = L.col(L.LAVA, 0.95) })
			L.pillar(api, ix, iz, { radius = 160, height = 1600, color = { 1, 0.55, 0.2, 0.9 }, ttl = 1.4 })
			L.log(api, h, "ult nuke dmg=%d hit=%d (rain: %d rockets x %d, %d hits)", nuke, #hits, st.rockets, dmg, st.hits)
		end, 0.05)
	end)
	api.active(unitID, "ult", warn + dur + 2)
	L.log(api, h, "ult armageddon protocol rank=%d count=%d dmg=%d nuke=%d at %d,%d", r, count, dmg, nuke, cx, cz)
	return true
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.homing = {}
	h.store.impacts = 0
	h.store.bomblets = 0
end

function M.fired(api, unitID, h, weaponNum)
	local w = h.def.weapons[weaponNum]
	if w and w.key == "exp_heavyrocket" then
		if (h.store.bomblets or 0) > 0 then
			L.log(api, h, "a1 salvo bomblets=%d hits=%d", h.store.bomblets, h.store.bombHits or 0)
		end
		h.store.bomblets = 0
		h.store.bombHits = 0
		h.store.impacts = 0
	end
end

function M.projectile(api, unitID, h, proID, weaponDefID)
	local doom = h.store.doom
	if doom and api.frame() < doom.untilF then
		local w = rocketInfo(h)
		if w and weaponDefID == w.wdid then
			local list = h.store.homing
			list[#list + 1] = proID
			if L.alive(doom.target) then
				Spring.SetProjectileTarget(proID, doom.target, string.byte("u"))
			end
		end
	end
end

function M.impact(api, unitID, h, weaponDefID, x, y, z, projectileID)
	if L.impact(api, unitID, h, weaponDefID, x, y, z, projectileID) then
		return
	end
	local w = rocketInfo(h)
	if w and weaponDefID == w.wdid and api.rank(h, "a1") > 0 then
		cluster(api, unitID, h, x, y, z)
	end
end

function M.frame(api, unitID, h, f)
	L.tick(api, unitID, h, f)
	steer(api, h, f)
	local doom = h.store.doom
	if doom and f >= doom.untilF and #h.store.homing == 0 then
		h.store.doom = nil
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a2" then
		return doomPainter(api, unitID, h, rank, targetID)
	elseif key == "a3" then
		return retro(api, unitID, h, rank, x, z)
	elseif key == "ult" then
		return protocol(api, unitID, h, rank, x, z)
	end
	return false
end

local function isArtillery(uid)
	local ud = UnitDefs[Spring.GetUnitDefID(uid) or -1]
	if not ud then
		return false
	end
	for _, w in ipairs(ud.weapons or {}) do
		local wd = WeaponDefs[w.weaponDef]
		if wd and wd.range > 1200 then
			return true
		end
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
		local range = b(h, "a2").range or 3200
		local t = L.enemyHero(api, h, x, z, range)
		if not t then
			local best, cost = L.mostValuable(api, h, x, z, range)
			if best and cost >= 3000 then
				t = best
			end
		end
		if t then
			local tx, ty, tz = api.pos(t)
			return tx, ty, tz, t
		end
	elseif key == "a3" then
		if hpf < 0.7 then
			for _, uid in ipairs(L.enemies(api, h, x, z, 700)) do
				if not isArtillery(uid) and not L.isStructure(uid) then
					local ex, ez = L.escapePoint(api, h, unitID, api.val(b(h, "a3").range, rank))
					if ex then
						return ex, L.gy(ex, ez), ez
					end
					break
				end
			end
		end
	elseif key == "ult" then
		local ult = b(h, "ult")
		local range = api.val(ult.range, rank)
		local metal, cx, cz = api.bestCluster(x, z, range, ult.radius or 700, h.ally)
		if cx and (metal >= 20000 or L.enemyHero(api, h, cx, cz, ult.radius or 700)) then
			return cx, L.gy(cx, cz), cz
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	h.store.doom = nil
	h.store.homing = {}
end

return M
