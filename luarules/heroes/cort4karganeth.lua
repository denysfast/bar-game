-- Karganeth, the Hydra (cort4karganeth, corkarganetht4 x1.8) - doc/v19-heroes/roster_cor.md section 8.
--   a1 Hydra Lock (passive): every 4..2 s the pods fire one homing micro-missile at each of up to 2..8 different
--      enemies within 1300: 800..2000 each, x2 against aircraft.
--   a2 Flak Canopy (active, self, 8 s): shoots down 1..3 enemy shells / rockets / bombs a second heading into
--      700..1100 (not beams, not nukes); the AA pods deal +50..150% meanwhile.
--   a3 Adaptive Plating (passive): 3 hits of one damage type within 4 s -> -10..30% from that type for 10 s (2 types).
--   ult Hydra Unleashed (active, self, 8..12 s): x1.2, +30% speed, a lock volley every second at up to 4..10 targets.

local L = VFS.Include("luarules/heroes/cort4_lib.lua")
local M = {}

local floor, max, min, sqrt, random = math.floor, math.max, math.min, math.sqrt, math.random

local FLARES = { "flare1", "flare2", "flare3", "flare4" }
local TYPE_COLOR = {
	electric = { 0.3, 0.95, 1, 0.8 }, laser = { 1, 0.2, 0.15, 0.8 }, plasma = { 1, 0.7, 0.25, 0.8 }, rocket = { 1, 0.5, 0.12, 0.8 },
	flame = { 1, 0.9, 0.2, 0.8 }, rail = { 1, 1, 1, 0.8 }, emp = { 0.72, 0.4, 1, 0.8 },
}

local function b(h, key)
	return h.def.cfg[key]
end

---------------------------------------------------------------------------- lock volleys (a1, ult)

local function volley(api, unitID, h, maxTargets, dmg, airMult, radius, tag)
	local x, _, z = api.pos(unitID)
	local list = api.nearestEnemies(x, z, radius, h.ally, 60)
	local picked = {}
	-- aircraft first, then the nearest
	for _, uid in ipairs(list) do
		if #picked >= maxTargets then
			break
		end
		if L.isAir(uid) and api.seenBy(uid, h.ally) then
			picked[#picked + 1] = uid
		end
	end
	for _, uid in ipairs(list) do
		if #picked >= maxTargets then
			break
		end
		if not L.isAir(uid) and api.seenBy(uid, h.ally) then
			picked[#picked + 1] = uid
		end
	end
	if #picked == 0 then
		return 0
	end
	local tx0, ty0, tz0 = api.piecePos(unitID, "turret")
	for i, uid in ipairs(picked) do
		local ux, uy, uz = api.pos(uid)
		L.beam(api, tx0, ty0 + 20, tz0, ux, uy + 20, uz, { color = L.RED, width = 2, ttl = 0.3, flare = 0.5 })
		api.delay(6 + i, function()
			if not (L.alive(unitID) and L.alive(uid)) then
				return
			end
			local fx, fy, fz = api.piecePos(unitID, FLARES[(i - 1) % 4 + 1])
			local air = L.isAir(uid)
			local d = dmg * (air and airMult or 1)
			L.shot(api, h, unitID, "hydra", fx, fy, fz, fx + (random() - 0.5) * 200, fy + 300, fz + (random() - 0.5) * 200, 26,
				function(ix, iy, iz)
					local hitIt = false
					if L.alive(uid) then
						local px, py, pz = api.pos(uid)
						if (px - ix) ^ 2 + (pz - iz) ^ 2 + (py - iy) ^ 2 <= (L.radius(uid) + 120) ^ 2 then
							api.damage(uid, d, unitID, { dtype = "rocket" })
							hitIt = true
						end
					end
					if not hitIt then
						api.area(ix, iz, 70, d * 0.5, unitID, { dtype = "rocket" })
					end
					L.flash(api, ix, iy + 10, iz, { radius = 70, color = L.ORANGE, ttl = 0.25, ground = not air })
					h.store.hydraHits = (h.store.hydraHits or 0) + (hitIt and 1 or 0)
				end, uid)
		end)
	end
	L.log(api, h, "%s volley targets=%d dmg=%d", tag, #picked, dmg)
	return #picked
end

---------------------------------------------------------------------------- a2 Flak Canopy

local interceptable = {}
for wdid, wd in pairs(WeaponDefs) do
	local t = wd.type
	if (t == "Cannon" or t == "MissileLauncher" or t == "AircraftBomb" or t == "TorpedoLauncher" or t == "StarburstLauncher")
		and not (wd.customParams and wd.customParams.nuclear) and (wd.damageAreaOfEffect or 0) < 700 and (wd.targetable or 0) == 0 then
		interceptable[wdid] = true
	end
end

-- enemy projectiles heading into the circle, nearest first (positions kept for the effects)
local function incoming(h, x, z, r, limit)
	local out = {}
	for _, p in ipairs(Spring.GetProjectilesInRectangle(x - r * 2, z - r * 2, x + r * 2, z + r * 2, false, false) or {}) do
		local wdid = Spring.GetProjectileDefID(p)
		if wdid and interceptable[wdid] then
			local team = Spring.GetProjectileTeamID(p)
			local pAlly = team and select(6, Spring.GetTeamInfo(team, false))
			if pAlly and pAlly ~= h.ally then
				local px, py, pz = Spring.GetProjectilePosition(p)
				if px then
					local inside = (px - x) ^ 2 + (pz - z) ^ 2 <= r * r
					if not inside then
						local _, target = Spring.GetProjectileTarget(p)
						local tx, tz
						if type(target) == "table" then
							tx, tz = target[1], target[3]
						elseif type(target) == "number" and Spring.ValidUnitID(target) then
							tx, _, tz = Spring.GetUnitPosition(target)
						end
						inside = tx and (tx - x) ^ 2 + (tz - z) ^ 2 <= r * r
					end
					if inside then
						out[#out + 1] = { p, px, py, pz }
						if limit and #out >= limit then
							break
						end
					end
				end
			end
		end
	end
	return out
end

local function flakOn(api, unitID, h, r)
	local a2 = b(h, "a2")
	local dur = a2.duration or 8
	local R = api.val(a2.radius, r)
	h.store.flak = { untilF = api.frame() + floor(dur * 30), R = R, rate = api.val(a2.rate, r), acc = 1, aa = api.val(a2.aa, r), shot = 0,
		sphere = L.attach(api, unitID, "sphere", { radius = R, color = { 1, 0.4, 0.15, 0.25 }, hex = true, fresnel = 2.2, ttl = dur, height = 0 }) }
	api.active(unitID, "a2", dur)
	local x, _, z = api.pos(unitID)
	L.ring(api, x, z, { kind = "hex", r0 = 80, r1 = R, width = 30, ttl = 0.6, color = { 1, 0.4, 0.15, 0.7 } })
	L.log(api, h, "a2 flak canopy rank=%d radius=%d rate=%.1f aa=+%.2f", r, R, h.store.flak.rate, h.store.flak.aa)
	return true
end

local function flakFrame(api, unitID, h, f)
	local fl = h.store.flak
	if f >= fl.untilF then
		h.store.flak = nil
		L.log(api, h, "a2 flak canopy over: intercepted=%d", fl.shot)
		return
	end
	fl.acc = min(fl.rate, fl.acc + fl.rate * 3 / 30)
	if fl.acc < 1 then
		return
	end
	local x, _, z = api.pos(unitID)
	local list = incoming(h, x, z, fl.R, floor(fl.acc))
	local tx, ty, tz = api.piecePos(unitID, "turret")
	for _, e in ipairs(list) do
		Spring.DeleteProjectile(e[1])
		fl.acc = fl.acc - 1
		fl.shot = fl.shot + 1
		L.beam(api, tx, ty + 30, tz, e[2], e[3], e[4], { color = L.RED, width = 4, ttl = 0.15, flare = 0.8 })
		L.flash(api, e[2], e[3], e[4], { radius = 90, color = L.ORANGE, ttl = 0.25, ground = false })
		L.hitFx(api, fl.sphere, e[2], e[3], e[4])
	end
end

---------------------------------------------------------------------------- a3 Adaptive Plating

local function adapt(api, unitID, h, dtype, damage)
	local r = api.rank(h, "a3")
	if r <= 0 or not dtype then
		return damage
	end
	local a3 = b(h, "a3")
	local f = api.frame()
	local st = h.store
	local ad = st.adapted
	-- the reduction of an adapted type
	local e = ad[dtype]
	if e and e.untilF > f then
		return damage * (1 - api.val(a3.reduce, r))
	end
	local log = st.typeHits[dtype] or {}
	st.typeHits[dtype] = log
	log[#log + 1] = f
	while #log > 0 and log[1] < f - (a3.window or 4) * 30 do
		table.remove(log, 1)
	end
	if #log >= (a3.hits or 3) then
		st.typeHits[dtype] = {}
		-- at most `types` adapted at once: a new one replaces the oldest
		local n, oldest, oldestF = 0, nil, nil
		for k, v in pairs(ad) do
			if v.untilF > f then
				n = n + 1
				if not oldestF or v.from < oldestF then
					oldest, oldestF = k, v.from
				end
			else
				ad[k] = nil
			end
		end
		if n >= (a3.types or 2) and oldest then
			ad[oldest] = nil
		end
		ad[dtype] = { from = f, untilF = f + floor((a3.duration or 10) * 30) }
		local c = TYPE_COLOR[dtype] or L.AMBER
		L.attach(api, unitID, "sphere", { radius = L.radius(unitID) * 1.15, color = c, hex = true, ttl = 0.6, fresnel = 3 })
		local x, _, z = api.pos(unitID)
		L.ring(api, x, z, { kind = "hex", r0 = 60, r1 = 130, width = 16, ttl = 0.5, color = c })
		L.log(api, h, "a3 adapted to %s rank=%d reduce=%.2f", dtype, r, api.val(a3.reduce, r))
	end
	return damage
end

---------------------------------------------------------------------------- ult Hydra Unleashed

local function hydraOn(api, unitID, h, r)
	local ult = b(h, "ult")
	if h.store.hydra then
		return false
	end
	local dur = api.val(ult.duration, r)
	api.buff(unitID, h, "hydra", dur, { scale = ult.scale or 1.2, speed = ult.speed or 0.3 })
	api.active(unitID, "ult", dur)
	h.store.hydra = { untilF = api.frame() + floor(dur * 30), nextF = api.frame() + 5, r = r, fx = {
		L.attach(api, unitID, "electric", { color = { 1, 0.35, 0.1, 1 }, intensity = 0.8, ttl = dur }),
		L.attach(api, unitID, "aura", { radius = 300, color = L.col(L.RED, 0.7), pattern = "runes", ttl = dur }),
		L.attach(api, unitID, "tint", { pattern = "heat", color = L.RED, strength = 0.45, ttl = dur }),
	} }
	local x, y, z = api.pos(unitID)
	L.flash(api, x, y + 40, z, { radius = 260, color = L.RED, ttl = 0.4 })
	L.ring(api, x, z, { kind = "shock", r0 = 60, r1 = 400, width = 40, ttl = 0.4, color = L.ORANGE })
	L.log(api, h, "ult hydra unleashed rank=%d dur=%.1f", r, dur)
	return true
end

local function hydraFrame(api, unitID, h, f)
	local hy = h.store.hydra
	if f >= hy.untilF then
		h.store.hydra = nil
		L.detachAll(api, hy.fx)
		return
	end
	if f >= hy.nextF then
		hy.nextF = f + 30
		local ult = b(h, "ult")
		volley(api, unitID, h, api.val(ult.targets, hy.r), api.val(ult.dmg, hy.r) * api.power(h), ult.air or 2, ult.radius or 1300, "ult")
	end
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.adapted = {}
	h.store.typeHits = {}
	h.store.nextLock = api.frame() + 30
end

function M.frame(api, unitID, h, f)
	L.tick(api, unitID, h, f)
	local r = api.rank(h, "a1")
	if r > 0 and f >= (h.store.nextLock or 0) then
		local a1 = b(h, "a1")
		local n = volley(api, unitID, h, api.val(a1.targets, r), api.val(a1.dmg, r) * api.power(h), a1.air or 2, a1.radius or 1300, "a1")
		h.store.nextLock = f + (n > 0 and floor(api.val(a1.period, r) * 30) or 15)
	end
	if h.store.flak then
		flakFrame(api, unitID, h, f)
	end
	if h.store.hydra then
		hydraFrame(api, unitID, h, f)
	end
end

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	local fl = h.store.flak
	if fl and damage > 0 then
		local n = h.def.keyNum.karg_shoulder and h.def.keyNum.karg_shoulder[1]
		if n and h.def.weapons[n].wdid == weaponDefID then
			return damage * (1 + fl.aa)
		end
	end
	return damage
end

function M.damaged(api, unitID, h, damage, attackerID, weaponDefID, isParalyzer)
	if damage <= 0 or not weaponDefID or weaponDefID < 0 then
		return damage
	end
	return adapt(api, unitID, h, api.damageType(weaponDefID), damage)
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a2" then
		if h.store.flak then
			return false
		end
		return flakOn(api, unitID, h, rank)
	elseif key == "ult" then
		return hydraOn(api, unitID, h, rank)
	end
	return false
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	if key == "a2" then
		if h.store.flak then
			return nil
		end
		local air = 0
		for _, uid in ipairs(L.enemies(api, h, x, z, 1500)) do
			if L.isAir(uid) then
				air = air + 1
			end
		end
		local R = api.val(b(h, "a2").radius, rank)
		-- v19-balance: 3 shells in the air at one instant almost never happened; keep a decaying count of the shells
		-- seen over the last seconds (checked once a second)
		local n = #incoming(h, x, z, R, 6)
		h.store.flakSeen = (h.store.flakSeen or 0) * 0.6 + n
		if air >= 3 or n >= 3 or h.store.flakSeen >= 2.5 then
			return x, y, z
		end
	elseif key == "ult" then
		if h.store.hydra then
			return nil
		end
		local list = L.enemies(api, h, x, z, b(h, "ult").radius or 1300)
		local air = 0
		for _, uid in ipairs(list) do
			if L.isAir(uid) then
				air = air + 1
			end
		end
		if #list >= 6 or air >= 3 then
			return x, y, z
		end
	end
	return nil
end

function M.impact(api, unitID, h, weaponDefID, x, y, z, projectileID)
	L.impact(api, unitID, h, weaponDefID, x, y, z, projectileID)
end

function M.destroyed(api, unitID, h)
	if h.store.hydra then
		L.detachAll(api, h.store.hydra.fx)
		h.store.hydra = nil
	end
	h.store.flak = nil
end

return M
