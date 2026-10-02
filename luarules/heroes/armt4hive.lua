-- Hive Mother (armt4hive, scavenger armdronecarryland x1.5): the drone carrier that fights through its swarm
-- (doc/v19-heroes/roster_arm.md 10). Numbers: luarules/configs/heroes/arm.lua. The stock carrier system
-- (unit_carrier_spawner) is not used: the drones are hero summons (api.summon) managed here.
--
--   a1 Drone Bay (passive): keeps 6..16 laser drones (armt4hive_drone) in the air, one rebuilt every 6..3 s; together
--      they deal 3500..9000 DPS (unit damage buff over the drone weapon, HP and damage grow with the level). They attack
--      the Hive's target, else the nearest enemy within 1250 of the Hive; leash 1300.
--   a2 Swarm Directive (active, enemy unit): every drone focuses the target for 8 s with more damage; their hits slow it
--      (up to 45%) and it is revealed.
--   a3 Kamikaze Run (active, map): 3..10 drones dive onto the point and explode (hero_dronebomb); 2 are rebuilt at once.
--   ult Mothership Protocol (active, self): anchors and launches Guardian gunships (armt4hive_guardian); drones rebuild 3x
--      faster, the swarm hits harder and takes less damage, a repair field heals drones and allies around.

local L = VFS.Include("luarules/heroes/armt4_lib.lua", nil, VFS.ZIP_FIRST)

local M = {}

local AMBER = { 1, 0.7, 0.2, 1 }
local BRIGHT = { 1, 0.85, 0.4, 1 }
local DRONE = "armt4hive_drone"
local GUARD = "armt4hive_guardian"
local DRONE_BASE_DPS = 580 -- the drone weapondef (units/ArmT4/armt4units.lua): 145 / 0.25 s
local droneDef = UnitDefNames[DRONE] and UnitDefNames[DRONE].id
local guardDef = UnitDefNames[GUARD] and UnitDefNames[GUARD].id

local function b(h, key)
	return h.def.cfg[key]
end

local function drones(h)
	return droneDef and Spring.GetTeamUnitsByDefs(h.team, droneDef) or {}
end

local function guardians(h)
	return guardDef and Spring.GetTeamUnitsByDefs(h.team, guardDef) or {}
end

---------------------------------------------------------------------------- a1 Drone Bay

local function deck(api, unitID)
	local x, y, z = api.pos(unitID)
	return x, y + 70, z
end

local function build(api, unitID, h, n)
	local ids = api.summon(unitID, h, DRONE, n, { leash = b(h, "a1").leash or 1300, scaleWithLevel = true, spread = 110 })
	local fx = api.fx
	local st = h.store
	for _, uid in ipairs(ids) do
		if fx then
			st.trail[uid] = fx.attach(uid, "trail", { color = AMBER, width = 6, length = 0.4 })
		end
	end
	if fx and #ids > 0 then
		local x, y, z = deck(api, unitID)
		fx.flash(x, y, z, { radius = 40 + 10 * #ids, color = AMBER, ttl = 0.3 })
	end
	return ids
end

local function swarmTarget(api, unitID, h)
	local d = h.store.directive
	if d and L.alive(d.target) then
		return d.target
	end
	local t = api.target(unitID)
	if t and Spring.GetUnitAllyTeam(t) ~= h.ally then
		return t
	end
	local x, _, z = api.pos(unitID)
	local near = api.nearestEnemies(x, z, 1250, h.ally, 10)
	for _, uid in ipairs(near) do
		if api.seenBy(uid, h.ally) and not L.isAir(uid) then
			return uid
		end
	end
end

local function bayTick(api, unitID, h, f)
	local r = api.rank(h, "a1")
	if r <= 0 or not droneDef then
		return
	end
	local a1 = b(h, "a1")
	local st = h.store
	local want = api.val(a1.count, r)
	local list = drones(h)
	local ms = st.mothership
	local every = api.val(a1.rebuild, r) / (ms and 3 or 1)
	if #list < want then
		if not st.nextDrone then
			for _, uid in ipairs(build(api, unitID, h, want - #list)) do
				list[#list + 1] = uid
			end
			st.nextDrone = f + math.floor(every * 30)
		elseif f >= st.nextDrone then
			for _, uid in ipairs(build(api, unitID, h, 1)) do
				list[#list + 1] = uid
			end
			st.nextDrone = f + math.floor(every * 30)
			st.rebuilt = (st.rebuilt or 0) + 1
		end
	else
		st.nextDrone = f + math.floor(every * 30)
	end
	-- damage: the bay's DPS split evenly, + directive / mothership
	local perDrone = api.val(a1.dps, r) / want
	local dmg = perDrone / DRONE_BASE_DPS - 1 + (st.directive and st.directive.damage or 0) + (ms and ms.damage or 0)
	local armor = ms and 0.2 or 0
	local target = swarmTarget(api, unitID, h)
	for _, uid in ipairs(list) do
		api.unitBuff(uid, "hive_bay", 1, { damage = dmg, armor = armor })
		local c = Spring.GetUnitCommands(uid, 1)
		local cur = c and c[1]
		if target then
			if not (cur and cur.id == CMD.ATTACK and cur.params[1] == target) then
				Spring.GiveOrderToUnit(uid, CMD.ATTACK, { target }, 0)
			end
		elseif not (cur and (cur.id == CMD.GUARD or cur.id == CMD.MOVE)) then
			Spring.GiveOrderToUnit(uid, CMD.GUARD, { unitID }, 0)
		end
	end
	if f % 300 == 0 then
		api.log("armt4hive a1 bay rank=%d drones=%d/%d perDrone=%d dps (+%.2f) rebuilt=%d", r, #list, want, perDrone, dmg, st.rebuilt or 0)
	end
end

---------------------------------------------------------------------------- a2 Swarm Directive

local function directive(api, unitID, h, r, targetID)
	if not targetID or not L.alive(targetID) or Spring.GetUnitAllyTeam(targetID) == h.ally then
		return false
	end
	local a2 = b(h, "a2")
	if L.unitDist(unitID, targetID) > (a2.range or 1600) * 1.1 then
		return false
	end
	local dur = a2.duration or 8
	local f = api.frame()
	local st = { target = targetID, untilFrame = f + math.floor(dur * 30), damage = api.val(a2.damage, r), slow = 0 }
	api.mark(targetID, "directive", dur, { reveal = true, from = unitID })
	local fx = api.fx
	if fx then
		local x, y, z = deck(api, unitID)
		local tx, ty, tz = api.pos(targetID)
		fx.beam(x, y, z, tx, ty + 20, tz, { color = { 1, 0.75, 0.3, 0.5 }, width = 3, ttl = 0.3 })
		st.fx = { fx.attach(targetID, "aura", { pattern = "runes", color = { 1, 0.7, 0.2, 0.6 }, radius = math.max(60, L.radius(targetID) * 1.3), ttl = dur }) }
		for i, uid in ipairs(drones(h)) do
			if i <= 20 then
				st.fx[#st.fx + 1] = fx.attach(uid, "trail", { color = BRIGHT, width = 9, length = 0.5, ttl = dur })
			end
		end
	end
	h.store.directive = st
	api.active(unitID, "a2", dur)
	bayTick(api, unitID, h, f)
	api.log("armt4hive a2 directive rank=%d target=%s damage=+%.2f drones=%d", r, UnitDefs[Spring.GetUnitDefID(targetID)].name, st.damage, #drones(h))
	return true
end

local function directiveFrame(api, unitID, h, f)
	local st = h.store.directive
	if f >= st.untilFrame or not L.alive(st.target) then
		h.store.directive = nil
		L.detach(api, st.fx)
		api.log("armt4hive a2 directive over: slow reached %.2f", st.slow)
		return
	end
	if f % 15 ~= 0 then
		return
	end
	local tx, _, tz = api.pos(st.target)
	local n = 0
	for _, uid in ipairs(drones(h)) do
		local x, _, z = api.pos(uid)
		if x and L.dist(x, z, tx, tz) < 500 then
			n = n + 1
		end
	end
	st.slow = math.min(0.45, st.slow + 0.03 * n * 0.25)
	if st.slow > 0 then
		api.slow(st.target, st.slow, 1)
	end
end

---------------------------------------------------------------------------- a3 Kamikaze Run

local function kamikaze(api, unitID, h, r, tx, tz)
	local a3 = b(h, "a3")
	local x, _, z = api.pos(unitID)
	local range = a3.range or 1800
	local d = L.dist(x, z, tx, tz)
	if d > range * 1.05 then
		tx, tz = x + (tx - x) / d * range, z + (tz - z) / d * range
	end
	local list = drones(h)
	if #list == 0 then
		return false
	end
	table.sort(list, function(a, c) return L.unitDist(a, unitID) < L.unitDist(c, unitID) end)
	local k = math.min(api.val(a3.count, r), #list)
	local dmg = api.val(a3.dmg, r) * api.power(h)
	local R = a3.radius or 200
	local st = { hits = 0, booms = 0 }
	for i = 1, k do
		local uid = list[i]
		local dx, dy, dz = api.pos(uid)
		local a = i * 2.4
		local spread = i == 1 and 0 or 60 + 30 * (i % 3)
		local px, pz = tx + math.cos(a) * spread, tz + math.sin(a) * spread
		local gy = L.gy(px, pz)
		api.consume(uid)
		api.fire(h, "hero_dronebomb", dx, dy, dz, px, gy, pz, { key = "a3", dmg = dmg, aoe = R, dtype = "rocket",
			onHit = function(ix, iz, hits)
				st.hits = st.hits + #hits
				st.booms = st.booms + 1
				if api.fx then
					api.fx.flash(ix, L.gy(ix, iz) + 30, iz, { radius = 180, color = "orange", ttl = 0.35 })
					api.fx.ring(ix, iz, { kind = "shock", r0 = 10, r1 = 220, color = "orange", ttl = 0.35, width = 26 })
				end
				if st.booms == k then
					api.log("armt4hive a3 kamikaze rank=%d drones=%d dmg=%d hits=%d total=%d", r, k, dmg, st.hits, st.hits * dmg)
				end
			end })
		if api.fx then
			api.fx.beam(dx, dy, dz, px, gy + 10, pz, { color = { 1, 0.4, 0.1, 0.7 }, width = 5, ttl = 0.5 })
		end
	end
	-- two rebuilt at once
	local want = api.val(b(h, "a1").count, api.rank(h, "a1"))
	local missing = want - (#list - k)
	if missing > 0 and api.rank(h, "a1") > 0 then
		build(api, unitID, h, math.min(2, missing))
	end
	return true
end

---------------------------------------------------------------------------- ult Mothership Protocol

local function mothership(api, unitID, h, r)
	local ult = b(h, "ult")
	local dur = api.val(ult.duration, r)
	local f = api.frame()
	local st = { untilFrame = f + math.floor(dur * 30), damage = api.val(ult.damage, r), heal = api.val(ult.heal, r) * api.power(h),
		radius = ult.radius or 800, healed = 0 }
	api.buff(unitID, h, "mothership", dur, { immobile = true })
	api.active(unitID, "ult", dur)
	local n = api.val(ult.guardians, r)
	local ids = api.summon(unitID, h, GUARD, n, { expire = dur + 10, leash = 1500, guard = unitID, scaleWithLevel = true, spread = 200 })
	local x, y, z = api.pos(unitID)
	local fx = api.fx
	if fx then
		fx.ring(x, z, { kind = "hex", r0 = 0, r1 = st.radius, color = { 1, 0.75, 0.3, 0.7 }, ttl = 0.6, width = 50 })
		st.fx = { fx.attach(unitID, "aura", { pattern = "heal", color = { 1, 0.8, 0.4, 0.4 }, radius = st.radius, ttl = dur }) }
		for _, uid in ipairs(ids) do
			local gx, _, gz = api.pos(uid)
			fx.pillar(gx, gz, { radius = 60, height = 700, color = AMBER, ttl = 0.8 })
			fx.attach(uid, "electric", { color = AMBER, intensity = 0.3, ttl = dur + 10 })
		end
	end
	h.store.mothership = st
	h.store.nextDrone = math.min(h.store.nextDrone or f, f + 30)
	api.log("armt4hive ult mothership rank=%d dur=%d guardians=%d damage=+%.2f heal=%d/s", r, dur, #ids, st.damage, st.heal)
	return true
end

local function mothershipFrame(api, unitID, h, f)
	local st = h.store.mothership
	if f >= st.untilFrame then
		h.store.mothership = nil
		L.detach(api, st.fx)
		api.log("armt4hive ult mothership over: healed=%d", st.healed)
		return
	end
	if f % 15 ~= 0 then
		return
	end
	local x, _, z = api.pos(unitID)
	for _, uid in ipairs(api.alliesIn(x, z, st.radius, h.ally)) do
		st.healed = st.healed + api.heal(uid, st.heal * 0.5)
	end
	for _, uid in ipairs(guardians(h)) do
		api.unitBuff(uid, "hive_ms", 1, { damage = st.damage, armor = 0.2 })
	end
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.trail = {}
	h.store.nextDrone = nil
	h.store.directive, h.store.mothership = nil, nil
end

function M.rank(api, unitID, h, key, rank)
	if key == "a1" then
		h.store.nextDrone = nil
	end
end

function M.frame(api, unitID, h, f)
	L.tick(h, f)
	if h.store.directive then
		directiveFrame(api, unitID, h, f)
	end
	if h.store.mothership then
		mothershipFrame(api, unitID, h, f)
	end
	if f % 15 == 0 then
		bayTick(api, unitID, h, f)
	end
	if f % 150 == 0 then
		for uid in pairs(h.store.trail) do
			if not L.alive(uid) then
				h.store.trail[uid] = nil
			end
		end
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a2" then
		return directive(api, unitID, h, rank, targetID)
	elseif key == "a3" then
		if targetID and not x then
			x, y, z = api.pos(targetID)
		end
		return x and kamikaze(api, unitID, h, rank, x, z) or false
	elseif key == "ult" then
		if h.store.mothership then
			return false
		end
		return mothership(api, unitID, h, rank)
	end
	return false
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	local n = #drones(h)
	if key == "a2" then
		if n < 4 then
			return nil
		end
		local range = b(h, "a2").range or 1600
		local t = L.enemyHero(api, x, z, range, h.ally) or api.mostValuableEnemy(x, z, range, h.ally)
		if t and (api.isHero(t) or api.cost(t) >= 2000) then
			local tx, ty, tz = api.pos(t)
			return tx, ty, tz, t
		end
	elseif key == "a3" then
		if n < L.v(api, h, "a3", "count", rank) + 2 then
			return nil
		end
		local range = b(h, "a3").range or 1800
		local hero = L.enemyHero(api, x, z, range, h.ally)
		if hero then
			local hx, hy, hz = api.pos(hero)
			return hx, hy, hz
		end
		local cx, cz, _, cnt = L.cluster(api, x, z, range, 250, h.ally)
		if cx and cnt >= 4 then
			return cx, L.gy(cx, cz), cz
		end
	elseif key == "ult" then
		if #api.enemiesIn(x, z, 400, h.ally) > 0 then
			return nil
		end
		local _, cnt = api.enemyCostNear(x, z, 1500, h.ally)
		if cnt >= 10 or L.enemyHero(api, x, z, 1500, h.ally) then
			return x, y, z
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	if h.store.directive then
		L.detach(api, h.store.directive.fx)
	end
	if h.store.mothership then
		L.detach(api, h.store.mothership.fx)
	end
	h.store.directive, h.store.mothership = nil, nil
end

return M
