-- Tempest, the Stormblade (legt4tempest) - v19 Legion hero module (doc/v19-heroes/roster_leg.md section 4).
--   a1 Momentum (passive): moving above half speed builds Momentum (+25/s, 100 max), standing loses it (-50/s); it
--      adds speed. At 100 the next shotgun blast is a Breach Shot: damage x breach, knockback, and a piercing line
--      behind the main victim (a share of the blast as a budget - v19 dmgfix). Consumes the Momentum.
--   a2 Storm Charge (unit / map): a 900 elmo/s lightning dash; enemies on the path are hit and stunned, a thunderclap
--      on arrival; Momentum is set to 100.
--   a3 Storm Echoes (self): storm images (stock legeshotgunmech, api.summon) with 15% of its HP and a share of its
--      damage; they fire a Breach Shot with Tempest and explode when they fade or die.
--   ult Eye of the Storm (self): spins - lightning lashes everything around every 0.2 s, shotgun blasts all around,
--      half damage taken, unstoppable, reflects damage; ends with a thunderclap.
local L = VFS.Include("luarules/heroes/legt4_lib.lua")
local C = L.C
local M = {}

local max, min, floor, sqrt, random, cos, sin, atan2 = math.max, math.min, math.floor, math.sqrt, math.random, math.cos, math.sin, math.atan2
local BREACH_WINDOW = 20 -- frames: the pellets of one blast

local function cfg(h, key)
	return h.def.cfg[key]
end

---------------------------------------------------------------------------- a1 Momentum

local function setMomentum(api, unitID, h, m)
	local st = h.store
	st.mom = max(0, min(100, m))
	local q = floor(st.mom / 10 + 0.5) * 10
	local r = api.rank(h, "a1")
	if r > 0 and q ~= st.momApplied then
		st.momApplied = q
		api.buff(unitID, h, "momentum", nil, { speed = api.val(cfg(h, "a1").speedMax, r) * q / 100 })
	end
	local fx = L.fx(api)
	if st.mom >= 50 and not st.trail then
		st.trail = fx.attach(unitID, "trail", { color = L.a(C.STORM, 0.6), width = 20, length = 0.6 })
	elseif st.mom < 50 and st.trail then
		fx.detach(st.trail)
		st.trail = nil
	end
	if st.mom >= 100 and not st.charged then
		st.charged = fx.attach(unitID, "electric", { color = C.STORM, intensity = 0.6 })
	elseif st.mom < 100 and st.charged then
		fx.detach(st.charged)
		st.charged = nil
	end
end

local function momentumTick(api, unitID, h, f)
	if api.rank(h, "a1") <= 0 then
		return
	end
	local vx, _, vz = Spring.GetUnitVelocity(unitID)
	local sp = vx and sqrt(vx * vx + vz * vz) * 30 or 0
	local full = max(1, h.moveSpeed or h.def.speed or 50)
	local m = h.store.mom
	if sp > full * 0.5 then
		m = m + 25 * 0.1
	elseif sp < full * 0.1 then
		m = m - 50 * 0.1
	end
	if not h.store.breachFrame then
		setMomentum(api, unitID, h, m)
	end
end

-- the echoes fire their Breach Shot with Tempest: a fan of bolts and the blast's share on their target
local function echoBreach(api, unitID, h, mult)
	local a3 = cfg(h, "a3")
	local share = api.val(a3.dmgShare, api.rank(h, "a3"))
	local fx = L.fx(api)
	for uid in pairs(h.store.echoes) do
		if L.alive(uid) then
			local ex, ey, ez = api.pos(uid)
			local t = api.target(uid) or api.nearestEnemies(ex, ez, 700, h.ally, 1)[1]
			if t and L.alive(t) then
				local tx, ty, tz = api.pos(t)
				local a = atan2(tz - ez, tx - ex)
				for k = -2, 2 do
					local b = a + k * 0.13
					fx.bolt(ex, ey + 50, ez, ex + cos(b) * 600, ey + 30, ez + sin(b) * 600, { color = L.a(C.STORM, 0.9), width = 4, branches = 1, ttl = 0.2 })
				end
				local d = h.store.salvoDmg * share * mult
				api.damage(t, d, unitID, { dtype = "laser" })
				h.store.echoDmg = (h.store.echoDmg or 0) + d
			end
		end
	end
end

function M.projectile(api, unitID, h, proID, weaponDefID)
	if not h.store.shotIds[weaponDefID] then
		return
	end
	local f = api.frame()
	if h.store.mom >= 100 and api.rank(h, "a1") > 0 and not h.store.breachFrame then
		h.store.breachFrame = f
		h.store.breachHits = {}
		local x, y, z = api.pos(unitID)
		local fx = L.fx(api)
		local px, py, pz = Spring.GetProjectilePosition(proID)
		local vx, _, vz = Spring.GetProjectileVelocity(proID)
		local a = atan2(vz or 0, vx or 1)
		fx.flash(px or x, (py or y) + 10, pz or z, { radius = 140, color = C.STORM, ttl = 0.25 })
		for k = -2, 2 do
			local b = a + k * 0.13
			fx.bolt(px or x, py or y, pz or z, (px or x) + cos(b) * 600, (py or y) - 10, (pz or z) + sin(b) * 600, { color = L.a(C.STORM, 0.9), width = 5, branches = 1, ttl = 0.2 })
		end
		local mult = api.val(cfg(h, "a1").breach, api.rank(h, "a1"))
		if next(h.store.echoes) then
			echoBreach(api, unitID, h, mult)
		end
	end
end

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	if isParalyzer or damage <= 0 then
		return damage
	end
	local bf = h.store.breachFrame
	if bf and h.store.shotIds[weaponDefID] and api.frame() - bf <= BREACH_WINDOW then
		local r = api.rank(h, "a1")
		local d = damage * api.val(cfg(h, "a1").breach, r)
		local bh = h.store.breachHits
		bh[victimID] = (bh[victimID] or 0) + d
		return d
	end
	return damage
end

-- after the blast: knockback, the piercing line behind the main victim, Momentum spent
local function breachEnd(api, unitID, h)
	local r = api.rank(h, "a1")
	local a1 = cfg(h, "a1")
	local x, _, z = api.pos(unitID)
	local best, bestD, total, n = nil, 0, 0, 0
	for uid, d in pairs(h.store.breachHits) do
		total, n = total + d, n + 1
		if d > bestD and L.alive(uid) then
			best, bestD = uid, d
		end
		if L.alive(uid) and not api.isHero(uid) then
			api.push(uid, x, z, api.val(a1.knock, r), 0.35)
		end
	end
	local pierced = 0
	if best then
		local bx, _, bz = api.pos(best)
		local dx, dz = bx - x, bz - z
		local d = max(1, sqrt(dx * dx + dz * dz))
		local len = a1.pierce or 400
		local ex, ez = bx + dx / d * len, bz + dz / d * len
		local list = {}
		for _, e in ipairs(L.alongLine(api, bx, bz, ex, ez, 120, h.ally)) do
			if e[1] ~= best then
				list[#list + 1] = e
			end
		end
		for _, e in ipairs(L.budget(list, bestD * 0.5, bestD * 0.35, 0.8)) do
			api.damage(e[1], e[2], unitID, { dtype = "laser" })
			pierced = pierced + e[2]
		end
		L.fx(api).beam(bx, L.groundY(bx, bz) + 40, bz, ex, L.groundY(ex, ez) + 40, ez, { color = L.a(C.STORM, 0.7), width = 10, ttl = 0.3, pulse = 8 })
	end
	api.log("legt4tempest a1 breach rank=%d x%.1f hits=%d dmg=%d pierce=%d echoes=%d", r, api.val(a1.breach, r), n, total, pierced, h.store.echoDmg or 0)
	h.store.echoDmg = 0
	h.store.breachFrame = nil
	h.store.breachHits = nil
	setMomentum(api, unitID, h, 0)
end

---------------------------------------------------------------------------- a2 Storm Charge

local function stormCharge(api, unitID, h, r, x, z, targetID)
	local a2 = cfg(h, "a2")
	local x0, y0, z0 = api.pos(unitID)
	local tx, tz = x, z
	if targetID and L.alive(targetID) then
		tx, _, tz = api.pos(targetID)
		local dx, dz = tx - x0, tz - z0
		local d = max(1, sqrt(dx * dx + dz * dz))
		local stop = max(0, d - 120 - L.radius(targetID))
		tx, tz = x0 + dx / d * stop, z0 + dz / d * stop
	end
	if not tx then
		return false
	end
	tx, tz = L.clampTo(x0, z0, tx, tz, api.val(a2.range, r) * 1.05)
	local fx = L.fx(api)
	local power = api.power(h)
	local trail = fx.attach(unitID, "trail", { color = C.STORM, width = 30, length = 0.5 })
	local elec = fx.attach(unitID, "electric", { color = C.STORM, intensity = 1.2 })
	local px, pz = x0, z0
	local hitSet, pathHits, pathDmg = {}, 0, 0
	local pd, stun = api.val(a2.pathDmg, r) * power, api.val(a2.stun, r)
	local ok = api.dash(unitID, h, tx, tz, { speed = a2.speed or 900, onStep = function(sx, sz)
		local sy = L.groundY(sx, sz)
		if L.d2(px, pz, sx, sz) > 60 * 60 then
			fx.chain({ px, L.groundY(px, pz) + 50, pz, sx, sy + 50, sz }, { color = C.STORM, width = 8, branches = 2, ttl = 0.25, flash = false })
			px, pz = sx, sz
		end
		for _, uid in ipairs(api.enemiesIn(sx, sz, 80 + 60, h.ally)) do
			if not hitSet[uid] then
				hitSet[uid] = true
				api.damage(uid, pd, unitID, { dtype = "electric" })
				api.stun(uid, stun, unitID)
				local ux, uy, uz = api.pos(uid)
				fx.bolt(sx, sy + 60, sz, ux, uy + 20, uz, { color = C.STORM, width = 4, ttl = 0.15 })
				pathHits, pathDmg = pathHits + 1, pathDmg + pd
			end
		end
	end, onLand = function(lx, lz)
		fx.detach(trail)
		fx.detach(elec)
		local ly = L.groundY(lx, lz)
		local R = api.val(a2.clapRadius, r)
		local clap = api.val(a2.clap, r) * power
		local hit = api.area(lx, lz, R, clap, unitID, { dtype = "electric" })
		fx.flash(lx, ly + 50, lz, { radius = 220, color = C.STORM, ttl = 0.3 })
		fx.ring(lx, lz, { kind = "electric", r0 = 50, r1 = R, color = C.STORM, width = 30, ttl = 0.5 })
		fx.ring(lx, lz, { kind = "shock", r0 = 30, r1 = R * 1.1, color = L.a(C.FOAM, 0.8), width = 24, ttl = 0.4 })
		if api.rank(h, "a1") > 0 then
			setMomentum(api, unitID, h, 100)
		end
		api.log("legt4tempest a2 charge rank=%d dist=%d path hits=%d dmg=%d stun=%.1f clap=%d hit=%d", r, sqrt(L.d2(x0, z0, lx, lz)), pathHits, pathDmg, stun, clap, #hit)
	end })
	if not ok then
		fx.detach(trail)
		fx.detach(elec)
	end
	return ok
end

---------------------------------------------------------------------------- a3 Storm Echoes

local function echoes(api, unitID, h, r)
	local a3 = cfg(h, "a3")
	local count, dur = api.val(a3.count, r), api.val(a3.duration, r)
	local ids = api.summon(unitID, h, "legeshotgunmech", count, { expire = dur, leash = 600, guard = unitID, spread = 180, credit = true })
	if #ids == 0 then
		return false
	end
	local fx = L.fx(api)
	local _, maxHp = Spring.GetUnitHealth(unitID)
	local hp = L.effMaxHp(api, unitID) * (a3.hpShare or 0.15)
	-- their damage: a share of Tempest's (its DPS x level multiplier) over the stock mech's DPS
	local echoUd = UnitDefNames.legeshotgunmech
	local echoDps = 1233
	local myDps = (Spring.GetUnitRulesParam(unitID, "hero_dps") or 12000)
	local k = max(0, api.val(a3.dmgShare, r) * myDps / echoDps - 1)
	for _, uid in ipairs(ids) do
		Spring.SetUnitMaxHealth(uid, hp)
		Spring.SetUnitHealth(uid, hp)
		api.unitBuff(uid, "legt4tempest_echo", dur, { damage = k })
		h.store.echoes[uid] = { born = api.frame() }
		local ex, ey, ez = api.pos(uid)
		fx.pillar(ex, ez, { radius = 60, height = 700, color = L.a(C.STORM, 0.7), ttl = 0.4 })
		fx.ring(ex, ez, { kind = "shock", r0 = 20, r1 = 200, color = C.STORM, width = 20, ttl = 0.4 })
		fx.attach(uid, "electric", { color = C.STORM, intensity = 0.8, ttl = dur })
		fx.attach(uid, "tint", { pattern = "electric", color = C.STORM, strength = 0.8, ttl = dur })
		fx.attach(uid, "aura", { radius = 90, color = L.a(C.STORM, 0.3), pattern = "electric", ttl = dur })
	end
	h.store.salvoDmg = (h.store.pelletDmg or 580) * 14 * api.dmgMult(h)
	api.log("legt4tempest a3 echoes rank=%d count=%d dur=%d hp=%d damage x%.2f (tempest dps %d)", r, #ids, dur, hp, 1 + k, myDps)
	return true
end

function M.unitDied(api, unitID, h, deadID, deadDefID, x, z, allied)
	local e = h.store.echoes[deadID]
	if not e then
		return
	end
	h.store.echoes[deadID] = nil
	local r = max(1, api.rank(h, "a3"))
	local a3 = cfg(h, "a3")
	local R = a3.boomRadius or 200
	local d = api.val(a3.boom, r) * api.power(h)
	local hit = api.area(x, z, R, d, unitID, { dtype = "electric", stun = 0.5 })
	local fx = L.fx(api)
	local y = L.groundY(x, z)
	fx.flash(x, y + 40, z, { radius = 160, color = C.STORM, ttl = 0.35 })
	fx.ring(x, z, { kind = "electric", r0 = 20, r1 = R, color = C.STORM, width = 24, ttl = 0.4 })
	api.log("legt4tempest a3 echo burst dmg=%d hit=%d", d, #hit)
end

---------------------------------------------------------------------------- ult Eye of the Storm

local function eyeOff(api, unitID, h)
	local e = h.store.eye
	if not e then
		return
	end
	h.store.eye = nil
	local fx = L.fx(api)
	for _, id in ipairs(e.ids) do
		fx.detach(id)
	end
	api.unbuff(unitID, h, "eyestorm")
	api.swapWeapons(unitID, h, nil)
end

local function eyeOfStorm(api, unitID, h, r)
	local ult = cfg(h, "ult")
	local dur = api.val(ult.duration, r)
	local R = api.val(ult.radius, r)
	local tick = api.val(ult.tick, r) * api.power(h)
	local fx = L.fx(api)
	api.buff(unitID, h, "eyestorm", dur, { speed = -0.3, armor = 0.5, unstoppable = true, reflect = api.val(ult.reflect, r) })
	api.swapWeapons(unitID, h, "storm")
	api.active(unitID, "ult", dur)
	local e = { dmg = 0, ticks = 0, reflected = {}, ids = {
		fx.attach(unitID, "electric", { color = C.STORM, intensity = 1.6 }),
		fx.attach(unitID, "aura", { radius = R, color = L.a(C.STORM, 0.45), pattern = "electric" }),
		fx.attach(unitID, "aura", { radius = R * 0.55, color = L.a(C.FOAM, 0.3), pattern = "swirl" }),
		fx.attach(unitID, "orb", { color = C.FOAM, radius = 12, height = 120, orbit = R * 0.45, speed = 1.2, count = 4, crackle = 4 }),
	} }
	h.store.eye = e
	L.task(h, 6, dur, function(f, t)
		local x, y, z = api.pos(unitID)
		if not x or not h.store.eye then
			return false
		end
		local n = (f - t.start) / 6
		local list = api.enemiesIn(x, z, R, h.ally)
		for _, uid in ipairs(list) do
			api.damage(uid, tick, unitID, { dtype = "electric" })
			e.dmg = e.dmg + tick
		end
		for k = 1, min(2, #list) do
			local uid = list[random(#list)]
			local ux, uy, uz = api.pos(uid)
			fx.bolt(x, y + 80, z, ux, uy + 20, uz, { color = C.STORM, width = 10, branches = 2, ttl = 0.15 })
		end
		if n % 2 == 0 then
			fx.ring(x, z, { kind = "electric", r0 = R * 0.9, r1 = R, color = C.STORM, width = 26, ttl = 0.45 })
		end
		-- shotgun blasts all around
		if n % 3 == 0 and #list > 0 then
			for k = 1, min(3, #list) do
				local uid = list[random(#list)]
				local ux, uy, uz = api.pos(uid)
				api.fire(h, "shotgun_storm", x, y + 60, z, uid)
			end
		end
		e.ticks = e.ticks + 1
	end, function()
		local x, y, z = api.pos(unitID)
		eyeOff(api, unitID, h)
		if not x or not L.alive(unitID) then
			return
		end
		local CR = ult.clapRadius or 700
		local clap = api.val(ult.clap, r) * api.power(h)
		local hit = api.area(x, z, CR, clap, unitID, { dtype = "electric", stun = api.val(ult.clapStun, r) })
		fx.flash(x, y + 60, z, { radius = 400, color = C.FOAM, ttl = 0.5 })
		fx.ring(x, z, { kind = "shock", r0 = 50, r1 = CR, color = L.a(C.STORM, 0.95), width = 50, ttl = 0.7 })
		fx.ring(x, z, { kind = "electric", r0 = 80, r1 = CR * 0.9, color = C.STORM, width = 30, ttl = 0.6 })
		fx.pillar(x, z, { radius = 150, height = 1500, color = L.a(C.STORM, 0.8), ttl = 0.35 })
		api.log("legt4tempest ult eye over rank=%d ticks=%d tickDmg=%d clap=%d hit=%d", r, e.ticks, e.dmg, clap, #hit)
	end)
	api.log("legt4tempest ult eye rank=%d dur=%.1f radius=%d tick=%d reflect=%.2f", r, dur, R, tick, api.val(ult.reflect, r))
	return true
end

-- reflect visual (the core reflects the damage: buff `reflect`)
function M.damaged(api, unitID, h, damage, attackerID, weaponDefID, isParalyzer, ax, az)
	local e = h.store.eye
	if e and attackerID and ax then
		local f = api.frame()
		local last = e.reflected[attackerID]
		if not last or f - last >= 8 then
			e.reflected[attackerID] = f
			local x, y, z = api.pos(unitID)
			local _, ay = api.pos(attackerID)
			L.fx(api).bolt(x, y + 60, z, ax, (ay or y) + 20, az, { color = C.FOAM, width = 6, ttl = 0.15 })
		end
	end
	return damage
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.tasks = {}
	h.store.echoes = {}
	h.store.mom = 0
	h.store.momApplied = nil
	local ids = {}
	for _, w in pairs(h.def.weapons) do
		if w.key == "shotgun" then
			ids[w.wdid] = true
			h.store.pelletDmg = w.damage
		end
	end
	for _, map in pairs(h.def.copies or {}) do
		for base, copy in pairs(map) do
			if ids[base] then
				ids[copy] = true
			end
		end
	end
	h.store.shotIds = ids
	h.store.salvoDmg = (h.store.pelletDmg or 580) * 14
end

function M.frame(api, unitID, h, f)
	L.runTasks(h, f)
	momentumTick(api, unitID, h, f)
	if h.store.breachFrame and f - h.store.breachFrame > BREACH_WINDOW then
		breachEnd(api, unitID, h)
	end
	if f % 30 == 0 then
		h.store.salvoDmg = (h.store.pelletDmg or 580) * 14 * api.dmgMult(h)
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a2" then
		return stormCharge(api, unitID, h, rank, x, z, targetID)
	elseif key == "a3" then
		return echoes(api, unitID, h, rank)
	elseif key == "ult" then
		if h.store.eye then
			return false
		end
		return eyeOfStorm(api, unitID, h, rank)
	end
	return false
end

local function armedStructuresNear(api, h, x, z, r)
	local n = 0
	for _, uid in ipairs(api.enemiesIn(x, z, r, h.ally)) do
		local ud = L.ud(uid)
		if ud and L.isStructure(uid) and #(ud.weapons or {}) > 0 then
			n = n + 1
		end
	end
	return n
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	local frac = L.hpFrac(unitID)
	if key == "a2" then
		local range = api.val(cfg(h, "a2").range, rank)
		if frac > 0.4 then
			for _, uid in ipairs(L.enemyHeroes(api, x, z, range, h.ally)) do
				local tx, ty, tz = api.pos(uid)
				if armedStructuresNear(api, h, tx, tz, 700) < 3 then
					return tx, ty, tz, uid
				end
			end
		end
		local n, cx, cz = L.cluster(api, x, z, range, 300, h.ally, 3)
		if cx and n >= 4 and armedStructuresNear(api, h, cx, cz, 700) < 3 then
			return cx, L.groundY(cx, cz), cz
		end
	elseif key == "a3" then
		if #L.enemies(api, x, z, 900, h.ally, true) >= 3 or #L.enemyHeroes(api, x, z, 900, h.ally) > 0 then
			return x, y, z
		end
	elseif key == "ult" then
		if frac > 0.25 and (#L.enemies(api, x, z, 500, h.ally, true) >= 5 or #L.enemyHeroes(api, x, z, 500, h.ally) > 0) then
			return x, y, z
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	L.endTasks(h)
	eyeOff(api, unitID, h)
	local fx = L.fx(api)
	fx.detach(h.store.trail)
	fx.detach(h.store.charged)
	h.store.trail, h.store.charged = nil, nil
end

return M
