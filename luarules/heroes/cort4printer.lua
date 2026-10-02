-- Printer, the Swarm Foundry (cort4printer, corprinter x2.8) - doc/v19-heroes/roster_cor.md section 5. The human's
-- "drone carrier": a nano-foundry that prints drones and turrets.
--   a1 Drone Bay (passive): keeps 2..8 attack drones (cort4printer_drone: 10k HP, 400..600 DPS x ability power, leash
--      900); a lost drone is reprinted every 10..5 s. Drone damage counts as the hero's (summon credit).
--   a2 Print Turret (active, map in 900): prints a quad laser guard (12k..40k HP, 800..2500 DPS) for 20..40 s; at most
--      2..3 at a time (the oldest goes).
--   a3 Repair Swarm (active, ally or self in 1000): every drone flies to the ally for 8 s (no shooting); it and the
--      allies within 300 regain 1500..5000 HP/s in total.
--   ult Swarm Protocol (active, map in 1800): waves of kamikaze micro-drones (homing missiles) dive onto the area.

local L = VFS.Include("luarules/heroes/cort4_lib.lua")
local M = {}

local floor, max, min, sqrt, random, cos, sin = math.floor, math.max, math.min, math.sqrt, math.random, math.cos, math.sin

local NANO = { 0.35, 1, 0.45, 1 }
local NANO_WHITE = { 0.75, 1, 0.8, 1 }

local function b(h, key)
	return h.def.cfg[key]
end

-- weapon damage of a summoned unit: every weapon scaled so its unitdef DPS reaches `dps` (all armour classes but air
-- in proportion)
local function setDps(uid, dps)
	local ud = UnitDefs[Spring.GetUnitDefID(uid) or -1]
	if not ud then
		return
	end
	local base = 0
	for _, w in ipairs(ud.weapons) do
		local wd = WeaponDefs[w.weaponDef]
		base = base + (wd.damages[0] or 0) * (wd.salvoSize or 1) * (wd.projectiles or 1) / max(0.03, wd.reload)
	end
	if base <= 0 then
		return
	end
	local k = dps / base
	for n, w in ipairs(ud.weapons) do
		local wd = WeaponDefs[w.weaponDef]
		for _, idx in pairs(Game.armorTypes or {}) do
			local v = wd.damages[idx]
			if v and v > 0 then
				pcall(Spring.SetUnitWeaponDamages, uid, n, idx, v * k)
			end
		end
	end
end

local function setHp(uid, hp)
	Spring.SetUnitMaxHealth(uid, hp)
	Spring.SetUnitHealth(uid, hp)
end

---------------------------------------------------------------------------- a1 Drone Bay

local function printFx(api, unitID)
	local x, y, z = api.piecePos(unitID, "door")
	L.pillar(api, x, z, { radius = 30, height = 120, color = NANO, ttl = 0.6, ring = false })
	L.flash(api, x, y + 20, z, { radius = 60, color = NANO, ttl = 0.4, ground = false })
end

local function liveDrones(h)
	local keep = {}
	for _, uid in ipairs(h.store.drones) do
		if L.alive(uid) then
			keep[#keep + 1] = uid
		end
	end
	h.store.drones = keep
	return keep
end

local function droneBay(api, unitID, h, f)
	local r = api.rank(h, "a1")
	if r <= 0 then
		return
	end
	local a1 = b(h, "a1")
	local drones = liveDrones(h)
	local want = api.val(a1.count, r)
	if #drones < want and f >= (h.store.nextPrint or 0) then
		local ids = api.summon(unitID, h, "cort4printer_drone", 1, { spread = 70, fx = "blank" })
		local uid = ids[1]
		if uid then
			drones[#drones + 1] = uid
			setHp(uid, a1.hp or 10000)
			setDps(uid, api.val(a1.dps, r) * api.power(h))
			printFx(api, unitID)
			if #drones <= 8 then
				L.attach(api, uid, "trail", { color = L.col(NANO, 0.5), width = 7, length = 0.4 })
			end
			L.log(api, h, "a1 drone printed %d/%d dps=%d", #drones, want, api.val(a1.dps, r) * api.power(h))
		end
		-- the first drones come quickly, then one per reprint interval
		h.store.nextPrint = f + ((#drones < 2 and not h.store.everFull) and 30 or floor(api.val(a1.reprint, r) * 30))
		if #drones >= want then
			h.store.everFull = true
		end
	end
end

-- drones: attack what the Printer attacks, stay within the leash; or repair (a3)
local function droneOrders(api, unitID, h, f)
	local drones = h.store.drones
	if #drones == 0 then
		return
	end
	local rep = h.store.repair
	local hx, _, hz = api.pos(unitID)
	if rep then
		local tx, ty, tz = api.pos(rep.target)
		if tx then
			for i, uid in ipairs(drones) do
				local a = i / #drones * 6.283 + f * 0.02
				Spring.GiveOrderToUnit(uid, CMD.MOVE, { tx + cos(a) * 110, ty + 100, tz + sin(a) * 110 }, 0)
			end
		end
		return
	end
	local leash = b(h, "a1").leash or 900
	local target = api.target(unitID)
	for _, uid in ipairs(drones) do
		local x, _, z = api.pos(uid)
		if L.d2(x, z, hx, hz) > leash * leash then
			Spring.GiveOrderToUnit(uid, CMD.MOVE, { hx, L.gy(hx, hz) + 80, hz }, 0)
			Spring.GiveOrderToUnit(uid, CMD.GUARD, { unitID }, CMD.OPT_SHIFT)
		elseif target and L.alive(target) then
			local cmd = Spring.GetUnitCommands(uid, 1)
			local c = cmd and cmd[1]
			if not (c and c.id == CMD.ATTACK and c.params[1] == target) then
				Spring.GiveOrderToUnit(uid, CMD.ATTACK, { target }, 0)
			end
		elseif Spring.GetUnitCommandCount(uid) == 0 then
			Spring.GiveOrderToUnit(uid, CMD.GUARD, { unitID }, 0)
		end
	end
end

---------------------------------------------------------------------------- a2 Print Turret

local function liveTurrets(api, h)
	local keep = {}
	for _, t in ipairs(h.store.turrets) do
		if L.alive(t.id) then
			t.x, t.y, t.z = api.pos(t.id)
			keep[#keep + 1] = t
		else
			if t.x then
				L.flash(api, t.x, t.y + 40, t.z, { radius = 120, color = NANO, ttl = 0.5 })
				L.ring(api, t.x, t.z, { kind = "hex", r0 = 120, r1 = 30, width = 16, ttl = 0.5, color = NANO })
			end
			L.detach(api, t.fx)
		end
	end
	h.store.turrets = keep
	return keep
end

local function printTurret(api, unitID, h, r, x, z)
	local a2 = b(h, "a2")
	if not x then
		return false
	end
	local hx, _, hz = api.pos(unitID)
	x, z = L.toward(hx, hz, x, z, a2.range or 900)
	local turrets = liveTurrets(api, h)
	local maxT = api.val(a2.max, r)
	while #turrets >= maxT do
		local old = table.remove(turrets, 1)
		Spring.DestroyUnit(old.id, false, true)
		L.detach(api, old.fx)
	end
	local dur = api.val(a2.duration, r)
	local ids = api.summon(unitID, h, "cort4printer_turret", 1, { spread = 0, expire = dur, fx = "blank" })
	local uid = ids[1]
	if not uid then
		return false
	end
	Spring.SetUnitPosition(uid, x, z)
	setHp(uid, api.val(a2.hp, r))
	setDps(uid, api.val(a2.dps, r) * api.power(h))
	api.stun(uid, a2.build or 1.5, nil)
	local gy = L.gy(x, z)
	L.pillar(api, x, z, { radius = 80, height = 400, color = NANO, ttl = a2.build or 1.5 })
	L.ring(api, x, z, { kind = "hex", r0 = 40, r1 = 120, width = 18, ttl = a2.build or 1.5, color = NANO })
	L.attach(api, uid, "tint", { pattern = "rim", color = NANO, strength = 0.9, ttl = a2.build or 1.5 })
	local hxp, hyp, hzp = api.piecePos(unitID, "emitnano")
	L.beam(api, hxp, hyp, hzp, x, gy + 60, z, { color = NANO, width = 6, ttl = a2.build or 1.5, pulse = 3 })
	turrets[#turrets + 1] = { id = uid, x = x, y = gy, z = z,
		fx = L.attach(api, uid, "aura", { radius = 90, color = L.col(NANO, 0.3), pattern = "runes", ttl = dur }) }
	L.log(api, h, "a2 print turret rank=%d hp=%d dps=%d dur=%d (%d/%d)", r, api.val(a2.hp, r), api.val(a2.dps, r) * api.power(h), dur,
		#turrets, maxT)
	return true
end

---------------------------------------------------------------------------- a3 Repair Swarm

local function repairSwarm(api, unitID, h, r, targetID, x, z)
	local a3 = b(h, "a3")
	if not (targetID and L.alive(targetID)) and x then
		local best, bd
		for _, uid in ipairs(api.alliesIn(x, z, 200, h.ally)) do
			local ux, _, uz = api.pos(uid)
			local d = L.d2(ux, uz, x, z)
			if not bd or d < bd then
				best, bd = uid, d
			end
		end
		targetID = best
	end
	targetID = targetID or unitID
	if not L.alive(targetID) or Spring.GetUnitAllyTeam(targetID) ~= h.ally then
		return false
	end
	local dur = a3.duration or 8
	for _, uid in ipairs(liveDrones(h)) do
		Spring.GiveOrderToUnit(uid, CMD.FIRE_STATE, { 0 }, 0)
	end
	h.store.repair = { target = targetID, untilF = api.frame() + floor(dur * 30), healed = 0, heal = api.val(a3.heal, r) * api.power(h),
		fx = L.attach(api, targetID, "aura", { radius = 150, color = NANO, pattern = "heal", ttl = dur }) }
	api.active(unitID, "a3", dur)
	L.log(api, h, "a3 repair swarm rank=%d heal=%d/s target=%s drones=%d", r, h.store.repair.heal,
		UnitDefs[Spring.GetUnitDefID(targetID)].name, #h.store.drones)
	return true
end

local function repairTick(api, unitID, h, f)
	local rep = h.store.repair
	if f >= rep.untilF or not L.alive(rep.target) then
		h.store.repair = nil
		L.detach(api, rep.fx)
		for _, uid in ipairs(liveDrones(h)) do
			Spring.GiveOrderToUnit(uid, CMD.FIRE_STATE, { 2 }, 0)
			Spring.GiveOrderToUnit(uid, CMD.GUARD, { unitID }, 0)
		end
		L.log(api, h, "a3 repair swarm over: healed=%d", rep.healed)
		return
	end
	local tx, ty, tz = api.pos(rep.target)
	if f % 9 == 0 then
		local drones = h.store.drones
		if #drones > 0 then
			for _, uid in ipairs(drones) do
				local dx, dy, dz = api.pos(uid)
				if dx then
					L.beam(api, dx, dy, dz, tx, ty + 30, tz, { color = NANO, width = 4, ttl = 0.32, pulse = 4, flare = 0.6 })
				end
			end
		else
			local ex, ey, ez = api.piecePos(unitID, "emitnano")
			L.beam(api, ex, ey, ez, tx, ty + 30, tz, { color = NANO, width = 6, ttl = 0.32, pulse = 4, flare = 0.6 })
		end
	end
	if f % 15 == 0 then
		local amount = rep.heal * 0.5
		local others = {}
		for _, uid in ipairs(api.alliesIn(tx, tz, b(h, "a3").radius or 300, h.ally)) do
			if uid ~= rep.target and not L.isStructure(uid) then
				others[#others + 1] = uid
			end
		end
		local main = #others > 0 and 0.6 or 1
		local healed = api.heal(rep.target, amount * main)
		local ht = api.hero(rep.target)
		healed = healed * (ht and ht.hpMult or 1)
		if #others > 0 then
			local each = amount * (1 - main) / #others
			for _, uid in ipairs(others) do
				healed = healed + api.heal(uid, each)
			end
		end
		rep.healed = rep.healed + healed
	end
end

---------------------------------------------------------------------------- ult Swarm Protocol

local function swarmProtocol(api, unitID, h, r, x, z)
	local ult = b(h, "ult")
	if not x then
		return false
	end
	local hx, _, hz = api.pos(unitID)
	local cx, cz = L.toward(hx, hz, x, z, ult.range or 1800)
	local R = ult.radius or 450
	local count = api.val(ult.count, r)
	local waves = ult.waves or 5
	local dmg = api.val(ult.dmg, r) * api.power(h)
	local aoe = ult.aoe or 120
	local ally = h.ally
	local st = { n = 0, hits = 0 }
	L.ring(api, cx, cz, { kind = "hex", r0 = R, r1 = R, width = 26, ttl = ult.time or 5, color = L.col(NANO_WHITE, 0.8), rot = 0.3 })
	L.ring(api, cx, cz, { kind = "glow", r0 = R * 0.2, r1 = R, width = 60, ttl = ult.time or 5, color = L.col(NANO, 0.3) })
	local launched = 0
	for w = 1, waves do
		local n = floor(count * w / waves) - floor(count * (w - 1) / waves)
		api.delay(floor((w - 1) * (ult.time or 5) * 30 / waves) + 1, function()
			if not L.alive(unitID) then
				return
			end
			local ex, ey, ez = api.piecePos(unitID, "emitnano")
			L.pillar(api, ex, ez, { radius = 60, height = 300, color = NANO, ttl = 0.4, ring = false })
			local enemies = L.enemies(api, h, cx, cz, R)
			for k = 1, n do
				launched = launched + 1
				local t = #enemies > 0 and enemies[random(1, #enemies)] or nil
				local a = random() * 6.283
				local d = R * sqrt(random())
				local tx, tz = L.clampX(cx + cos(a) * d), L.clampZ(cz + sin(a) * d)
				local ox, oz = cos(k * 2.4) * 60, sin(k * 2.4) * 60
				local pid = L.shot(api, h, unitID, "swarm", ex + ox * 0.3, ey + 30, ez + oz * 0.3, ex + ox, ey + 600, ez + oz, 14,
					function(ix, iy, iz)
						local hits = api.area(ix, iz, aoe, dmg, unitID, { dtype = "laser", ally = ally })
						st.n, st.hits = st.n + 1, st.hits + #hits
						L.flash(api, ix, iy + 20, iz, { radius = 120, color = NANO_WHITE, ttl = 0.3 })
						L.ring(api, ix, iz, { kind = "shock", r0 = 20, r1 = aoe * 1.2, width = 20, ttl = 0.3, color = L.col(NANO, 0.8) })
						if st.n == count then
							L.log(api, h, "ult swarm done: %d drones x %d dmg, %d hits", count, dmg, st.hits)
						end
					end)
				if pid then
					if t then
						Spring.SetProjectileTarget(pid, t, string.byte("u"))
					else
						Spring.SetProjectileTarget(pid, tx, L.gy(tx, tz), tz)
					end
				end
			end
		end)
	end
	api.active(unitID, "ult", ult.time or 5)
	L.log(api, h, "ult swarm protocol rank=%d count=%d dmg=%d at %d,%d", r, count, dmg, cx, cz)
	return true
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.drones = h.store.drones or {}
	h.store.turrets = h.store.turrets or {}
	h.store.nextPrint = api.frame() + 15
	h.store.repair = nil
end

function M.rank(api, unitID, h, key, rank)
	if key == "a1" then
		-- stronger drones for the ones already out
		local p = api.val(b(h, "a1").dps, rank) * api.power(h)
		for _, uid in ipairs(liveDrones(h)) do
			setDps(uid, p)
		end
	end
end

function M.frame(api, unitID, h, f)
	L.tick(api, unitID, h, f)
	if f % 15 == 0 then
		droneBay(api, unitID, h, f)
		droneOrders(api, unitID, h, f)
		liveTurrets(api, h)
	end
	if h.store.repair then
		repairTick(api, unitID, h, f)
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a2" then
		return printTurret(api, unitID, h, rank, x, z)
	elseif key == "a3" then
		return repairSwarm(api, unitID, h, rank, targetID, x, z)
	elseif key == "ult" then
		return swarmProtocol(api, unitID, h, rank, x, z)
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
		local a2 = b(h, "a2")
		for _, uid in ipairs(api.alliesIn(x, z, a2.range or 900, h.ally)) do
			local ah = api.hero(uid)
			if uid ~= unitID and ah and f - (ah.lastHit or -999) < 90 then
				local ux, _, uz = api.pos(uid)
				return ux + 120, L.gy(ux + 120, uz), uz
			end
		end
		local metal, cx, cz = api.bestCluster(x, z, 1600, 300, h.ally)
		if cx and metal >= 2500 then
			local d = sqrt(L.d2(cx, cz, x, z))
			local px, pz = L.toward(x, z, cx, cz, min(a2.range or 900, max(150, d - 300)))
			return px, L.gy(px, pz), pz
		end
	elseif key == "a3" then
		local range = b(h, "a3").range or 1000
		local best, bestScore
		for _, uid in ipairs(api.alliesIn(x, z, range, h.ally)) do
			if not L.isStructure(uid) then
				local frac = L.hpFrac(uid)
				local ah = api.hero(uid)
				local hurt = ah and f - (ah.lastHit or -999) < 90
				if (uid == unitID and frac < 0.5) or (uid ~= unitID and frac < 0.6 and (hurt or not ah)) then
					local score = api.cost(uid) * (ah and 4 or 1) * (1 - frac)
					if not bestScore or score > bestScore then
						best, bestScore = uid, score
					end
				end
			end
		end
		if best then
			local tx, ty, tz = api.pos(best)
			return tx, ty, tz, best
		end
	elseif key == "ult" then
		local ult = b(h, "ult")
		local metal, cx, cz = api.bestCluster(x, z, ult.range or 1800, ult.radius or 450, h.ally)
		if cx and (metal >= 15000 or L.enemyHero(api, h, cx, cz, ult.radius or 450)) then
			return cx, L.gy(cx, cz), cz
		end
	end
	return nil
end

function M.impact(api, unitID, h, weaponDefID, x, y, z, projectileID)
	L.impact(api, unitID, h, weaponDefID, x, y, z, projectileID)
end

function M.destroyed(api, unitID, h)
	if h.store.repair then
		L.detach(api, h.store.repair.fx)
		h.store.repair = nil
	end
	h.store.drones = {}
end

return M
