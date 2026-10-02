-- Apollyon, the Locust King (legt4apollyon) - v19 Legion hero module (doc/v19-heroes/roster_leg.md section 9).
--   a1 Spin-Up (passive): every second of gatling fire adds fire rate (buff `reload`, all weapons) up to a cap; 2 s
--      without firing it spins down 15%/s. At full spin the gatlings fire incendiary rounds (api.swapWeapons "hot"):
--      more damage and a 3 s burn on what they hit.
--   a2 Locust Swarm (map): micro-rockets (locust weapondef) in 3 waves over 2 s, each homing on a different enemy
--      around the point; spare ones burn the ground for 3 s.
--   a3 Siege Lockdown (self, toggle): anchored - immobile, armour, weapon range, rocket racks reload twice as fast,
--      the gatlings start half spun. Ends after `duration` or on a second cast.
--   ult Plague of Locusts (map): locked in place, a 10 s rain of locusts on the area (biased to units), every impact
--      leaves fire for 2 s; the gatlings stay at full spin.
local L = VFS.Include("luarules/heroes/legt4_lib.lua")
local C = L.C
local M = {}

local max, min, floor, sqrt, random, cos, sin = math.max, math.min, math.floor, math.sqrt, math.random, math.cos, math.sin

local function cfg(h, key)
	return h.def.cfg[key]
end

---------------------------------------------------------------------------- a1 Spin-Up

local function spinMax(api, h)
	local r = api.rank(h, "a1")
	return r > 0 and api.val(cfg(h, "a1").max, r) or 0
end

local function setSpin(api, unitID, h, s)
	local st = h.store
	local cap = spinMax(api, h)
	st.spin = max(0, min(cap, s))
	local q = floor(st.spin * 20 + 0.5) / 20
	if q ~= st.spinApplied then
		st.spinApplied = q
		if q > 0 then
			api.buff(unitID, h, "spin", nil, { reload = q })
		else
			api.unbuff(unitID, h, "spin")
		end
	end
	local full = cap > 0 and st.spin >= cap - 0.001
	local fx = L.fx(api)
	if st.spin > 0.02 then
		local alpha = 0.1 + 0.4 * st.spin / max(0.01, cap)
		if not st.spinAura then
			st.spinAura = fx.attach(unitID, "aura", { radius = 120 * 1.6, color = L.a(C.EMBER, alpha), pattern = "heat" })
		else
			fx.set(st.spinAura, { alpha = alpha })
		end
	elseif st.spinAura then
		fx.detach(st.spinAura)
		st.spinAura = nil
	end
	if full ~= (st.hot or false) then
		st.hot = full
		if full then
			api.swapWeapons(unitID, h, "hot")
			st.hotFx = { fx.attach(unitID, "electric", { color = C.EMBER, intensity = 0.4 }), fx.attach(unitID, "tint", { pattern = "heat", color = C.EMBER, strength = 0.45 }) }
			api.log("legt4apollyon a1 full spin %.2f: incendiary rounds", st.spin)
		else
			api.swapWeapons(unitID, h, nil)
			for _, id in ipairs(st.hotFx or {}) do
				fx.detach(id)
			end
			st.hotFx = nil
		end
	end
end

function M.fired(api, unitID, h, weaponNum)
	if h.store.gatNums[weaponNum] then
		h.store.lastFire = api.frame()
	end
end

local function spinTick(api, unitID, h, f)
	local r = api.rank(h, "a1")
	if r <= 0 then
		return
	end
	local a1 = cfg(h, "a1")
	local s = h.store.spin
	if h.store.forceSpin then
		s = max(s, h.store.forceSpin * spinMax(api, h))
	end
	if f - (h.store.lastFire or -1000) <= 30 then
		s = s + api.val(a1.rate, r)
	elseif f - (h.store.lastFire or -1000) > 60 then
		s = s - 0.15 * spinMax(api, h)
	end
	if h.store.forceSpin then
		s = max(s, h.store.forceSpin * spinMax(api, h))
	end
	setSpin(api, unitID, h, s)
end

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	if isParalyzer or damage <= 0 or not h.store.hot or not h.store.gatIds[weaponDefID] then
		return damage
	end
	local r = api.rank(h, "a1")
	local a1 = cfg(h, "a1")
	local f = api.frame()
	local b = h.store.burn[victimID]
	if not b then
		b = {}
		h.store.burn[victimID] = b
	end
	b.dps = api.val(a1.burn, r) * api.power(h)
	b.untilF = f + 90
	return damage * (1 + api.val(a1.hot, r))
end

local function burnTick(api, unitID, h, f)
	local total = 0
	for uid, b in pairs(h.store.burn) do
		if b.untilF <= f or not L.alive(uid) then
			h.store.burn[uid] = nil
		else
			api.damage(uid, b.dps * 0.5, unitID, { dtype = "flame" })
			total = total + b.dps * 0.5
		end
	end
	h.store.burnDmg = (h.store.burnDmg or 0) + total
end

---------------------------------------------------------------------------- fire on the ground

local function groundFire(api, unitID, h, x, z, radius, dps, seconds, ringFx)
	local fx = L.fx(api)
	if ringFx then
		fx.ring(x, z, { kind = "fire", r0 = radius * 0.3, r1 = radius, color = C.EMBER, ttl = seconds })
	end
	local d = dps * api.power(h) * 0.5
	L.task(h, 15, seconds, function()
		api.area(x, z, radius, d, unitID, { dtype = "flame" })
	end)
end

---------------------------------------------------------------------------- a2 Locust Swarm

local function rackPos(api, unitID, k)
	local x, y, z = api.pos(unitID)
	local a = (k or random(6)) * 1.047
	return x + cos(a) * 50, y + 70, z + sin(a) * 50
end

local function locusts(api, unitID, h, r, x, z)
	local a2 = cfg(h, "a2")
	local count = api.val(a2.count, r)
	local dmg = api.val(a2.dmg, r) * api.power(h)
	local aoe = a2.aoe or 120
	local R = a2.radius or 500
	local fx = L.fx(api)
	fx.ring(x, z, { kind = "hex", r0 = R, r1 = R, color = L.a(C.EMBER, 0.5), width = 18, ttl = 2.5, rot = 0.6 })
	local st = { hits = 0, fired = 0, burns = 0 }
	local per = math.ceil(count / 3)
	for wave = 0, 2 do
		api.delay(1 + wave * 30, function()
			if not L.alive(unitID) then
				return
			end
			local targets = L.enemies(api, x, z, R, h.ally, false)
			local hx, hy, hz = api.pos(unitID)
			fx.flash(hx, hy + 80, hz, { radius = 60, color = C.EMBER, ttl = 0.25, ground = false })
			for i = 1, min(per, count - st.fired) do
				st.fired = st.fired + 1
				local sx, sy, sz = rackPos(api, unitID, i)
				local t = targets[((st.fired - 1) % max(1, #targets)) + 1]
				local onHit = function(ix, iz, hits)
					st.hits = st.hits + #hits
				end
				if t and st.fired <= #targets * 2 then
					api.fire(h, "locust", sx, sy, sz, t, { key = "a2", dmg = dmg, aoe = aoe, dtype = "rocket", onHit = onHit })
				else
					local a, d = random() * 6.283, sqrt(random()) * R
					local px, pz = x + cos(a) * d, z + sin(a) * d
					api.fire(h, "locust", sx, sy, sz, px, L.groundY(px, pz), pz, { key = "a2", dmg = dmg, aoe = aoe, dtype = "rocket", onHit = function(ix, iz, hits)
						st.hits = st.hits + #hits
						groundFire(api, unitID, h, ix, iz, 100, 300, 3, true)
						st.burns = st.burns + 1
					end })
				end
			end
			if wave == 2 then
				api.delay(60, function()
					api.log("legt4apollyon a2 locusts rank=%d fired=%d dmg=%d hits=%d burns=%d", r, st.fired, dmg, st.hits, st.burns)
				end)
			end
		end)
	end
	return true
end

---------------------------------------------------------------------------- a3 Siege Lockdown

local function lockOff(api, unitID, h)
	local lk = h.store.lock
	if not lk then
		return
	end
	h.store.lock = nil
	if lk.task then
		lk.task.dead = true
	end
	h.store.forceSpin = h.store.plague and 1 or nil
	api.unbuff(unitID, h, "lockdown")
	local fx = L.fx(api)
	for _, id in ipairs(lk.ids) do
		fx.detach(id)
	end
	api.log("legt4apollyon a3 lockdown over")
end

local function lockOn(api, unitID, h, r)
	local a3 = cfg(h, "a3")
	local dur = api.val(a3.duration, r)
	api.buff(unitID, h, "lockdown", nil, { immobile = true, armor = api.val(a3.armor, r), range = api.val(a3.range, r) })
	h.store.forceSpin = max(h.store.forceSpin or 0, 0.5)
	local fx = L.fx(api)
	local x, y, z = api.pos(unitID)
	local rad = L.radius(unitID)
	fx.ring(x, z, { kind = "hex", r0 = 60, r1 = 260, color = L.a(C.EMBER, 0.9), width = 24, ttl = 0.6 })
	local lk = { ids = { fx.attach(unitID, "sphere", { radius = rad * 1.2, color = L.a(C.EMBER, 0.25), hex = true, fresnel = 2.6 }) } }
	lk.sphere = lk.ids[1]
	local _, yaw = Spring.GetUnitRotation(unitID)
	for k = 0, 3 do
		local a = (yaw or 0) + 0.785 + k * 1.571
		local px, pz = x + sin(a) * rad * 0.9, z + cos(a) * rad * 0.9
		lk.ids[#lk.ids + 1] = fx.pillar(px, pz, { radius = 18, height = 120, color = L.a(C.EMBER, 0.6), ttl = dur, ring = false })
	end
	h.store.lock = lk
	-- the rocket racks reload twice as fast: a reload at half their cycle
	lk.task = L.task(h, 120, dur, function()
		for n in pairs(h.store.rackNums) do
			api.reloadNow(unitID, n)
		end
	end, function()
		if h.store.lock == lk and L.alive(unitID) then
			api.toggleOff(unitID, h, "a3")
		end
	end, 120)
	api.active(unitID, "a3", dur)
	api.log("legt4apollyon a3 lockdown rank=%d dur=%d armor=%.2f range=+%.2f", r, dur, api.val(a3.armor, r), api.val(a3.range, r))
	return true
end

function M.toggleOff(api, unitID, h, key, rank)
	if key == "a3" then
		lockOff(api, unitID, h)
	end
end

function M.damaged(api, unitID, h, damage, attackerID, weaponDefID, isParalyzer, ax, az)
	local lk = h.store.lock
	if lk and ax then
		local f = api.frame()
		if f - (lk.lastHit or 0) >= 6 then
			lk.lastHit = f
			local x, y, z = api.pos(unitID)
			local dx, dz = ax - x, az - z
			local d = max(1, sqrt(dx * dx + dz * dz))
			local rr = L.radius(unitID) * 1.2
			L.fx(api).hit(lk.sphere, x + dx / d * rr, y + 40, z + dz / d * rr)
		end
	end
	return damage
end

---------------------------------------------------------------------------- ult Plague of Locusts

local function plague(api, unitID, h, r, x, z)
	local ult = cfg(h, "ult")
	local dur = ult.duration or 10
	local count = api.val(ult.count, r)
	local dmg = api.val(ult.dmg, r) * api.power(h)
	local aoe = ult.aoe or 150
	local R = ult.radius or 700
	local fire = api.val(ult.fire, r)
	local fx = L.fx(api)
	api.buff(unitID, h, "plague", dur, { immobile = true })
	h.store.plague = true
	h.store.forceSpin = 1
	api.active(unitID, "ult", dur)
	local ids = {
		fx.ring(x, z, { kind = "rune", r0 = R, r1 = R, color = L.a(C.EMBER, 0.5), width = 22, ttl = dur, rot = 0.25 }),
		fx.zone(x, z, { radius = R, pattern = "fire", color = L.a(C.EMBER, 0.18), ttl = dur }),
	}
	local st = { n = 0, hits = 0, fires = 0 }
	local every = max(3, floor(dur * 30 / count))
	local perStep = max(1, math.ceil(count / (dur * 30 / every)))
	L.task(h, every, dur, function(f, t)
		local hx, hy, hz = api.pos(unitID)
		if not hx then
			return false
		end
		if (f - t.start) % 30 < every then
			fx.ring(x, z, { kind = "shock", r0 = R * 0.3, r1 = R, color = L.a(C.EMBER, 0.6), width = 26, ttl = 0.6 })
		end
		fx.flash(hx, hy + 80, hz, { radius = 50, color = C.EMBER, ttl = 0.2, ground = false })
		local list = api.enemiesIn(x, z, R, h.ally)
		for _ = 1, perStep do
			if st.n >= count then
				return false
			end
			st.n = st.n + 1
			local tx, tz
			if #list > 0 and random() < 0.7 then
				tx, _, tz = api.pos(list[random(#list)])
				tx, tz = tx + (random() - 0.5) * 100, tz + (random() - 0.5) * 100
			else
				local a, d = random() * 6.283, sqrt(random()) * R
				tx, tz = x + cos(a) * d, z + sin(a) * d
			end
			local ty = L.groundY(tx, tz)
			api.fire(h, "locust", tx - 250 + random() * 100, ty + 1400, tz - 250 + random() * 100, tx, ty, tz, {
				key = "ult", dmg = dmg, aoe = aoe, dtype = "rocket",
				onHit = function(ix, iz, hits)
					local iy = L.groundY(ix, iz)
					fx.flash(ix, iy + 20, iz, { radius = 70, color = C.EMBER, ttl = 0.25 })
					st.hits = st.hits + #hits
					if st.fires < 40 then
						st.fires = st.fires + 1
						groundFire(api, unitID, h, ix, iz, 120, fire, 2, false)
					end
				end,
			})
		end
	end, function()
		h.store.plague = nil
		h.store.forceSpin = h.store.lock and 0.5 or nil
		for _, id in ipairs(ids) do
			fx.detach(id)
		end
		api.log("legt4apollyon ult plague over rank=%d locusts=%d dmg=%d hits=%d fires=%d", r, st.n, dmg, st.hits, st.fires)
	end)
	api.log("legt4apollyon ult plague rank=%d count=%d dmg=%d fire=%d", r, count, dmg, fire)
	return true
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.tasks = {}
	h.store.spin = 0
	h.store.spinApplied = nil
	h.store.hot = false
	h.store.burn = {}
	h.store.lock = nil
	h.store.plague = nil
	h.store.forceSpin = nil
	local gatIds, gatNums, rackNums = {}, {}, {}
	for n, w in pairs(h.def.weapons) do
		if w.key == "legapollyon_gatling_big" or w.key == "legapollyon_gatling_small" then
			gatIds[w.wdid] = true
			gatNums[n] = true
		elseif w.key == "legapollyon_missile" then
			rackNums[n] = true
		end
	end
	for _, map in pairs(h.def.copies or {}) do
		for base, copy in pairs(map) do
			if gatIds[base] then
				gatIds[copy] = true
			end
		end
	end
	h.store.gatIds, h.store.gatNums, h.store.rackNums = gatIds, gatNums, rackNums
end

function M.frame(api, unitID, h, f)
	L.runTasks(h, f)
	if f % 30 == 0 then
		spinTick(api, unitID, h, f)
		-- AI: end the lockdown when the enemies left or it is losing
		local lk = h.store.lock
		if lk and h.ai then
			local x, _, z = api.pos(unitID)
			if #api.nearestEnemies(x, z, api.weaponReach(h) * 1.6, h.ally, 1) == 0 or L.hpFrac(unitID) < 0.25 then
				api.toggleOff(unitID, h, "a3")
			end
		end
	end
	if f % 15 == 0 then
		burnTick(api, unitID, h, f)
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a2" and x then
		return locusts(api, unitID, h, rank, x, z)
	elseif key == "a3" then
		if h.store.lock then
			return false
		end
		return lockOn(api, unitID, h, rank)
	elseif key == "ult" and x then
		return plague(api, unitID, h, rank, x, z)
	end
	return false
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	if key == "a2" then
		local a2 = cfg(h, "a2")
		local n, cx, cz = L.cluster(api, x, z, api.val(a2.range, rank), a2.radius or 500, h.ally, 3)
		if cx and n >= 4 then
			return cx, L.groundY(cx, cz), cz
		end
	elseif key == "a3" then
		local reach = api.weaponReach(h)
		if #L.enemies(api, x, z, reach * 1.3, h.ally, true) >= 6 and #L.enemyHeroes(api, x, z, 400, h.ally) == 0 then
			return x, y, z
		end
	elseif key == "ult" then
		local ult = cfg(h, "ult")
		if #L.enemyHeroes(api, x, z, 600, h.ally) > 0 then
			return nil
		end
		local n, cx, cz = L.cluster(api, x, z, ult.range, ult.radius or 700, h.ally, 3)
		local _, sx, sz = L.cluster(api, x, z, ult.range, ult.radius or 700, h.ally, 0, 1)
		if cx and n >= 10 then
			return cx, L.groundY(cx, cz), cz
		end
		local ns = 0
		if sx then
			for _, uid in ipairs(api.enemiesIn(sx, sz, ult.radius or 700, h.ally)) do
				if L.isStructure(uid) then
					ns = ns + 1
				end
			end
			if ns >= 5 then
				return sx, L.groundY(sx, sz), sz
			end
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	L.endTasks(h)
	lockOff(api, unitID, h)
	local fx = L.fx(api)
	fx.detach(h.store.spinAura)
	for _, id in ipairs(h.store.hotFx or {}) do
		fx.detach(id)
	end
	h.store.spinAura, h.store.hotFx, h.store.hot = nil, nil, false
	api.swapWeapons(unitID, h, nil)
	h.store.burn = {}
end

return M
