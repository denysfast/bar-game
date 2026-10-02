-- Myrmidon, the Hive Mother (legt4myrmidon) - v19 Legion hero module (doc/v19-heroes/roster_leg.md section 5).
--   a1 Drone Bay (passive): keeps N hive drones (legt4myrmdrone, api.summon: guard her, attack her target, leash
--      1400, damage / toughness grow with her level), one rebuilt every `rebuild` s.
--   a2 Repair Swarm (passive): drones with no enemy near (and 1 / 2 on duty from rank 4 / 8) beam-repair the most
--      damaged ally within 600 of them.
--   a3 Sacrificial Dive (unit / map): drones dive as homing warheads and detonate (heroes take 70%); drones rebuild
--      3x faster for 10 s.
--   ult Hive Ascendant (self, toggle): roots - armour, faster and longer-ranged cannons, a stream of swarm-mites
--      (legt4myrmmite, 20 s), drones rebuilt fast. Ends after `duration` or on a second cast.
local L = VFS.Include("luarules/heroes/legt4_lib.lua")
local C = L.C
local M = {}

local max, min, floor, sqrt, random = math.max, math.min, math.floor, math.sqrt, math.random

local function cfg(h, key)
	return h.def.cfg[key]
end

local function droneList(h)
	local out = {}
	for uid in pairs(h.store.drones) do
		if L.alive(uid) then
			out[#out + 1] = uid
		else
			h.store.drones[uid] = nil
		end
	end
	table.sort(out)
	return out
end

---------------------------------------------------------------------------- a1 Drone Bay

local function launchDrone(api, unitID, h)
	local ids = api.summon(unitID, h, "legt4myrmdrone", 1, { leash = 1400, guard = unitID, credit = true, scaleWithLevel = true, spread = 120, fx = "hero-summon" })
	local fx = L.fx(api)
	local x, y, z = api.pos(unitID)
	fx.flash(x, y + 120, z, { radius = 50, color = C.HIVE, ttl = 0.25 })
	fx.ring(x, z, { kind = "shock", r0 = 20, r1 = 120, color = C.HIVE, width = 14, ttl = 0.35 })
	for _, uid in ipairs(ids) do
		h.store.drones[uid] = true
		fx.attach(uid, "trail", { color = L.a(C.HIVE, 0.5), width = 6, length = 0.4 })
		h.store.built = (h.store.built or 0) + 1
	end
	return #ids
end

local function bayTick(api, unitID, h, f)
	local r = api.rank(h, "a1")
	if r <= 0 then
		return
	end
	local a1 = cfg(h, "a1")
	local want = api.val(a1.drones, r)
	local have = #droneList(h)
	if have >= want then
		h.store.nextDrone = nil
		return
	end
	local every = api.val(a1.rebuild, r)
	if (h.store.boostUntil or 0) > f then
		every = every / 3
	end
	if h.store.hive then
		every = every * 0.3
	end
	local frames = max(9, floor(every * 30))
	if not h.store.nextDrone then
		h.store.nextDrone = (h.store.firstFill and f or f + frames)
		h.store.firstFill = false
	end
	if f >= h.store.nextDrone then
		launchDrone(api, unitID, h)
		h.store.nextDrone = have + 1 < want and f + frames or nil
	end
end

---------------------------------------------------------------------------- a2 Repair Swarm

local function repairTick(api, unitID, h, f)
	local r = api.rank(h, "a2")
	if r <= 0 then
		return
	end
	local a2 = cfg(h, "a2")
	local heal = api.val(a2.heal, r) * api.power(h) * 0.3 -- per 0.3 s
	local duty = r >= 8 and 2 or (r >= 4 and 1 or 0)
	local fx = L.fx(api)
	local healedTotal = 0
	for i, d in ipairs(droneList(h)) do
		local dx, dy, dz = api.pos(d)
		local inCombat = #api.nearestEnemies(dx, dz, 1000, h.ally, 1) > 0
		if not inCombat or i <= duty then
			local best, bestMiss
			for _, uid in ipairs(api.alliesIn(dx, dz, a2.radius or 600, h.ally)) do
				if not h.store.drones[uid] then
					local hp, maxHp, _, _, bp = Spring.GetUnitHealth(uid)
					if hp and bp and bp >= 1 and hp < maxHp * 0.98 then
						local v = api.hero(uid)
						local miss = (maxHp - hp) * (v and v.hpMult or 1)
						if not bestMiss or miss > bestMiss then
							best, bestMiss = uid, miss
						end
					end
				end
			end
			if best then
				local amount = heal
				if api.isHero(best) and best ~= unitID then
					amount = amount * 0.5
				end
				local add = api.heal(best, amount) or 0
				healedTotal = healedTotal + amount
				local bx, by, bz = api.pos(best)
				fx.beam(dx, dy, dz, bx, by + 25, bz, { color = L.a(C.HEAL, 0.8), width = 4, ttl = 0.35, pulse = 6, flare = 0.6 })
				L.markOn(api, h.store.healFx, best, "aura", { radius = max(40, L.radius(best) * 0.8), color = L.a(C.HEAL, 0.4), pattern = "heal" }, 0.5)
			end
		end
	end
	if healedTotal > 0 then
		h.store.repaired = (h.store.repaired or 0) + healedTotal
	end
end

---------------------------------------------------------------------------- a3 Sacrificial Dive

local function dive(api, unitID, h, r, x, z, targetID)
	local a3 = cfg(h, "a3")
	local drones = droneList(h)
	if #drones == 0 then
		return false
	end
	if targetID and not L.alive(targetID) then
		targetID = nil
	end
	if not targetID and not x then
		return false
	end
	local n = min(#drones, api.val(a3.divers, r))
	local d = api.val(a3.dmg, r) * api.power(h)
	local aoe = a3.aoe or 180
	local fx = L.fx(api)
	local hx, _, hz = api.pos(unitID)
	fx.ring(hx, hz, { kind = "rune", r0 = 250, r1 = 250, color = L.a(C.HIVE, 0.6), width = 20, ttl = 0.6, rot = 2 })
	local st = { hits = 0, dmg = 0 }
	-- the drones nearest the target dive first
	local tx, tz = x, z
	if targetID then
		tx, _, tz = api.pos(targetID)
	end
	table.sort(drones, function(a, b)
		local ax, _, az = api.pos(a)
		local bx, _, bz = api.pos(b)
		return L.d2(ax, az, tx, tz) < L.d2(bx, bz, tx, tz)
	end)
	for i = 1, n do
		local did = drones[i]
		local sx, sy, sz = api.pos(did)
		h.store.drones[did] = nil
		fx.flash(sx, sy, sz, { radius = 50, color = C.EMBER, ttl = 0.25, ground = false })
		api.consume(did)
		local px, pz = tx + (random() - 0.5) * 80 * (i - 1), tz + (random() - 0.5) * 80 * (i - 1)
		local onHit = function(ix, iz, hits)
			local iy = L.groundY(ix, iz)
			fx.flash(ix, iy + 30, iz, { radius = 140, color = C.HIVE, ttl = 0.3 })
			fx.ring(ix, iz, { kind = "shock", r0 = 20, r1 = aoe, color = L.a(C.EMBER, 0.85), width = 20, ttl = 0.4 })
			for _, uid in ipairs(api.enemiesIn(ix, iz, aoe, h.ally)) do
				local dd = api.isHero(uid) and d * 0.7 or d
				api.damage(uid, dd, unitID, { dtype = "rocket" })
				st.hits, st.dmg = st.hits + 1, st.dmg + dd
			end
			api.log("legt4myrmidon a3 dive impact dmg=%d total hits=%d total dmg=%d", d, st.hits, st.dmg)
		end
		if targetID and i == 1 then
			api.fire(h, "hero_ab_missile", sx, sy, sz, targetID, { key = "a3", dmg = 0, aoe = 1, onHit = onHit })
		else
			api.fire(h, "hero_ab_missile", sx, sy, sz, px, L.groundY(px, pz), pz, { key = "a3", dmg = 0, aoe = 1, onHit = onHit })
		end
	end
	h.store.boostUntil = api.frame() + 300
	api.log("legt4myrmidon a3 dive rank=%d drones=%d dmg=%d", r, n, d)
	return true
end

---------------------------------------------------------------------------- ult Hive Ascendant

local function hiveOff(api, unitID, h)
	local hv = h.store.hive
	if not hv then
		return
	end
	h.store.hive = nil
	if hv.task then
		hv.task.dead = true
	end
	api.unbuff(unitID, h, "hive")
	local fx = L.fx(api)
	for _, id in ipairs(hv.ids) do
		fx.detach(id)
	end
	api.log("legt4myrmidon ult hive over mites=%d", hv.mites)
end

local function hiveOn(api, unitID, h, r)
	local ult = cfg(h, "ult")
	local dur = api.val(ult.duration, r)
	local interval = api.val(ult.interval, r)
	local cap = api.val(ult.mites, r)
	api.buff(unitID, h, "hive", nil, { immobile = true, armor = ult.armor or 0.3, reload = ult.reload or 0.67, range = ult.rangeBonus or 0.25 })
	local fx = L.fx(api)
	local x, y, z = api.pos(unitID)
	fx.ring(x, z, { kind = "hex", r0 = 100, r1 = 450, color = L.a(C.HIVE, 0.8), width = 20, ttl = 0.8 })
	local hv = { mites = 0, start = api.frame(), lastEnemy = api.frame(), ids = {
		fx.attach(unitID, "aura", { radius = 450, color = L.a(C.EMBER, 0.35), pattern = "runes" }),
		fx.attach(unitID, "aura", { radius = 260, color = L.a(C.HIVE, 0.3), pattern = "hex" }),
		fx.attach(unitID, "tint", { pattern = "heat", color = C.HIVE, strength = 0.35 }),
	} }
	h.store.hive = hv
	hv.task = L.task(h, max(3, floor(interval * 30)), dur, function(f, t)
		local hx, hy, hz = api.pos(unitID)
		if not hx then
			return false
		end
		local ids = api.summon(unitID, h, "legt4myrmmite", 1, { expire = 20, guard = unitID, cap = cap, credit = true, scaleWithLevel = true, spread = 160, fx = "hero-summon" })
		for _, uid in ipairs(ids) do
			hv.mites = hv.mites + 1
			local mx, my, mz = api.pos(uid)
			fx.flash(mx, my + 20, mz, { radius = 45, color = C.HIVE, ttl = 0.2 })
		end
		if (f - t.start) % 60 < t.every then
			fx.pillar(hx, hz, { radius = 25, height = 600, color = L.a(C.HIVE, 0.4), ttl = 0.6 })
		end
	end, function()
		if h.store.hive == hv and L.alive(unitID) then
			api.toggleOff(unitID, h, "ult")
		end
	end)
	api.active(unitID, "ult", dur)
	api.log("legt4myrmidon ult hive rank=%d dur=%d interval=%.2f cap=%d", r, dur, interval, cap)
	return true
end

function M.toggleOff(api, unitID, h, key, rank)
	if key == "ult" then
		hiveOff(api, unitID, h)
	end
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.tasks = {}
	h.store.drones = {}
	h.store.healFx = {}
	h.store.firstFill = true
	h.store.hive = nil
end

function M.rank(api, unitID, h, key, rank)
	if key == "a1" and rank == 1 then
		h.store.firstFill = true
	end
end

function M.frame(api, unitID, h, f)
	L.runTasks(h, f)
	if f % 15 == 0 then
		bayTick(api, unitID, h, f)
	end
	if f % 9 == 0 then
		repairTick(api, unitID, h, f)
	end
	if f % 30 == 0 then
		L.markSweep(api, h.store.healFx, f)
		local hv = h.store.hive
		if hv then
			local x, _, z = api.pos(unitID)
			if #api.nearestEnemies(x, z, 2200, h.ally, 1) > 0 then
				hv.lastEnemy = f
			elseif h.ai and f - hv.lastEnemy > 120 then
				api.toggleOff(unitID, h, "ult")
			end
		end
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a3" then
		return dive(api, unitID, h, rank, x, z, targetID)
	elseif key == "ult" then
		if h.store.hive then
			return false
		end
		return hiveOn(api, unitID, h, rank)
	end
	return false
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	if key == "a3" then
		if #droneList(h) < 2 then
			return nil
		end
		local range = cfg(h, "a3").range
		for _, uid in ipairs(api.enemiesIn(x, z, range, h.ally)) do
			if api.seenBy(uid, h.ally) and (api.isHero(uid) or api.cost(uid) >= 4000) then
				local tx, ty, tz = api.pos(uid)
				return tx, ty, tz, uid
			end
		end
		local n, cx, cz = L.cluster(api, x, z, range, 360, h.ally, 3)
		if cx and n >= 5 then
			return cx, L.groundY(cx, cz), cz
		end
	elseif key == "ult" then
		local near = #L.enemies(api, x, z, 1800, h.ally, true)
		local heroes = #L.enemyHeroes(api, x, z, 1800, h.ally)
		if (near >= 8 or heroes > 0) and #api.alliesIn(x, z, 1500, h.ally) >= 6 then
			return x, y, z
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	L.endTasks(h)
	hiveOff(api, unitID, h)
	L.markClear(api, h.store.healFx or {})
	h.store.drones = {}
	h.store.nextDrone = nil
end

return M
