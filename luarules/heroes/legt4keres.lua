-- Keres, the Death-Spirit (legt4keres) - v19 Legion hero module (doc/v19-heroes/roster_leg.md section 6).
--   a1 Soul Harvest (passive): every enemy dying within 1000 (any killer) gives Souls (1 per 500 metal, a hero 10), up
--      to the cap; each Soul adds weapon damage. 10 s out of combat: -1 Soul per 3 s.
--   a2 Death Grip (unit): a chain hook drags the target 150 in front of Keres over 0.5 s (heroes half way, api.pull),
--      stuns it, and the riot cannon fires point-blank (target full, 300 splash half).
--   a3 Devour (unit): a broken non-hero enemy within 400 (HP below a flat value or a share of its max) is eaten whole
--      (api.consume, no wreck, kill credited): Keres heals a multiple of its remaining HP + 10% of its max, +5 Souls.
--   ult Danse Macabre (self): spends Souls as hunting spirits (deaths meanwhile add more) that each strike a different
--      enemy within 1200 once a second; Keres gains lifesteal.
local L = VFS.Include("luarules/heroes/legt4_lib.lua")
local C = L.C
local M = {}

local max, min, floor, sqrt, random, ceil = math.max, math.min, math.floor, math.sqrt, math.random, math.ceil

local function cfg(h, key)
	return h.def.cfg[key]
end

---------------------------------------------------------------------------- a1 Soul Harvest

local ORB = { color = L.a(C.SOUL, 0.8), radius = 18, height = 90, orbit = 140, speed = 0.2, crackle = 2 }

local function soulFx(api, unitID, h)
	local want = h.store.souls > 0 and ceil(h.store.souls / 10) or 0
	if want == h.store.orbCount then
		return
	end
	local fx = L.fx(api)
	fx.detach(h.store.orbs)
	h.store.orbs = nil
	if want > 0 then
		local o = { color = ORB.color, radius = ORB.radius, height = ORB.height, orbit = ORB.orbit, speed = ORB.speed, crackle = 2, count = want }
		h.store.orbs = fx.attach(unitID, "orb", o)
	end
	h.store.orbCount = want
end

local function setSouls(api, unitID, h, n)
	local r = api.rank(h, "a1")
	local cap = r > 0 and api.val(cfg(h, "a1").cap, r) or 0
	h.store.souls = max(0, min(cap, n))
	Spring.SetUnitRulesParam(unitID, "hero_keres_souls", h.store.souls, { allied = true })
	soulFx(api, unitID, h)
end

function M.unitDied(api, unitID, h, deadID, deadDefID, x, z, allied)
	if allied or h.store.consumed[deadID] then
		h.store.consumed[deadID] = nil
		if allied then
			return
		end
	end
	local hx, hy, hz = api.pos(unitID)
	if not hx then
		return
	end
	local inRange = L.d2(hx, hz, x, z) <= 1000 * 1000
	-- Danse Macabre: deaths add spirits while there were fewer Souls than the cap
	local dm = h.store.danse
	if dm and dm.grow and dm.count < dm.max and L.d2(hx, hz, x, z) <= 1200 * 1200 then
		dm.count = dm.count + 1
		dm.orb.count = dm.count
		local fx = L.fx(api)
		fx.detach(dm.ids[1])
		dm.ids[1] = fx.attach(unitID, "orb", dm.orb)
	end
	if not inRange or api.rank(h, "a1") <= 0 then
		return
	end
	local ud = UnitDefs[deadDefID]
	local gain
	if ud and ud.customParams and ud.customParams.t4_hero then
		gain = 10
	else
		gain = max(1, floor((ud and ud.metalCost or 0) / 500))
	end
	local before = h.store.souls
	setSouls(api, unitID, h, before + gain)
	h.store.lastCombat = api.frame()
	if h.store.souls > before and h.store.wispsThisFrame < 6 then
		h.store.wispsThisFrame = h.store.wispsThisFrame + 1
		local gy = L.groundY(x, z)
		L.fx(api).bolt(x, gy + 20, z, hx, hy + 60, hz, { color = L.a(C.SOUL, 0.7), width = 3, jitter = 0.2, branches = 0, ttl = 0.4 })
	end
end

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	if isParalyzer or damage <= 0 then
		return damage
	end
	h.store.lastCombat = api.frame()
	local r = api.rank(h, "a1")
	local d = damage
	if r > 0 and h.store.souls > 0 then
		d = d * (1 + api.val(cfg(h, "a1").perSoul, r) * h.store.souls)
	end
	local dm = h.store.danse
	if dm then
		local v = api.hero(victimID)
		dm.steal = dm.steal + d * (v and v.hpMult or 1) * dm.lifesteal
	end
	return d
end

function M.damaged(api, unitID, h, damage)
	h.store.lastCombat = api.frame()
	return damage
end

---------------------------------------------------------------------------- a2 Death Grip

local function grippable(api, h, uid)
	return L.alive(uid) and Spring.GetUnitAllyTeam(uid) ~= h.ally and not L.isStructure(uid) and not L.isAir(uid)
end

local function deathGrip(api, unitID, h, r, targetID)
	if not grippable(api, h, targetID) then
		return false
	end
	local a2 = cfg(h, "a2")
	local x, y, z = api.pos(unitID)
	local tx, ty, tz = api.pos(targetID)
	local range = api.val(a2.range, r)
	if L.d2(x, z, tx, tz) > (range + 60) ^ 2 then
		return false
	end
	local fx = L.fx(api)
	-- 150 in front of Keres, toward the target
	local dx, dz = tx - x, tz - z
	local d = max(1, sqrt(dx * dx + dz * dz))
	local px, pz = x + dx / d * (150 + L.radius(targetID)), z + dz / d * (150 + L.radius(targetID))
	local pulled = api.pull(targetID, px, pz, d, 0.5)
	local stun = api.val(a2.stun, r)
	api.stun(targetID, stun + 0.5, unitID)
	fx.attach(targetID, "electric", { color = C.SOUL, intensity = 0.7, ttl = stun + 0.5 })
	fx.attach(targetID, "tint", { pattern = "shadow", color = C.SOUL, strength = 0.6, ttl = stun + 0.5 })
	L.task(h, 3, 0.55, function()
		local kx, ky, kz = api.pos(unitID)
		local gx, gy, gz = api.pos(targetID)
		if kx and gx then
			fx.beam(kx, ky + 45, kz, gx, gy + 25, gz, { color = L.a(C.SOUL, 0.9), width = 6, ttl = 0.15, pulse = -6, flare = 0.5 })
		end
	end, function()
		if not L.alive(unitID) then
			return
		end
		local gx, gy, gz = api.pos(targetID)
		if not gx then
			return
		end
		local dmg = api.val(a2.dmg, r) * api.power(h)
		api.damage(targetID, dmg, unitID, { dtype = "plasma" })
		local splash = 0
		for _, uid in ipairs(api.enemiesIn(gx, gz, a2.splash or 300, h.ally)) do
			if uid ~= targetID then
				api.damage(uid, dmg * 0.5, unitID, { dtype = "plasma" })
				splash = splash + 1
			end
		end
		local kx, ky, kz = api.pos(unitID)
		fx.flash(gx, gy + 30, gz, { radius = 160, color = C.SOUL, ttl = 0.35 })
		fx.ring(gx, gz, { kind = "shock", r0 = 20, r1 = a2.splash or 300, color = L.a(C.SOUL, 0.8), width = 22, ttl = 0.45 })
		fx.beam(kx, ky + 45, kz, gx, gy + 25, gz, { color = L.a(C.WHITE, 0.9), width = 14, ttl = 0.2, flare = 1.5 })
		api.log("legt4keres a2 grip rank=%d pulled=%s stun=%.1f dmg=%d splash=%d", r, tostring(pulled), stun, dmg, splash)
	end)
	return true
end

---------------------------------------------------------------------------- a3 Devour

local function edible(api, h, uid, r)
	if not L.alive(uid) or api.isHero(uid) or Spring.GetUnitAllyTeam(uid) == h.ally then
		return false
	end
	local ud = L.ud(uid)
	if not ud or ud.customParams.iscommander then
		return false
	end
	local a3 = cfg(h, "a3")
	local hp, maxHp = Spring.GetUnitHealth(uid)
	return hp and (hp <= api.val(a3.hpFlat, r) or hp <= maxHp * api.val(a3.hpPct, r))
end

local function devour(api, unitID, h, r, targetID)
	local a3 = cfg(h, "a3")
	if not edible(api, h, targetID, r) then
		return false
	end
	local x, y, z = api.pos(unitID)
	local tx, ty, tz = api.pos(targetID)
	if L.d2(x, z, tx, tz) > ((a3.range or 400) + L.radius(targetID) + 60) ^ 2 then
		return false
	end
	local hp, maxHp = Spring.GetUnitHealth(targetID)
	local rad = L.radius(targetID)
	local fx = L.fx(api)
	h.store.consumed[targetID] = true
	local info = api.consume(targetID, { credit = unitID })
	if not info then
		h.store.consumed[targetID] = nil
		return false
	end
	local heal = hp * api.val(a3.heal, r) + maxHp * (a3.healMax or 0.1)
	local healed = api.heal(unitID, heal)
	setSouls(api, unitID, h, h.store.souls + (a3.souls or 5))
	fx.pillar(tx, tz, { radius = max(40, rad), height = 500, color = L.a(C.SOUL, 0.7), ttl = 0.4 })
	fx.ring(tx, tz, { kind = "rune", r0 = rad * 1.5, r1 = 30, color = L.a(C.SOUL, 0.9), width = 18, ttl = 0.5, rot = -4 })
	fx.chain({ tx, ty + 30, tz, (tx + x) / 2, (ty + y) / 2 + 80, (tz + z) / 2, x, y + 50, z }, { color = C.SOUL, width = 5, ttl = 0.35, delay = 0.05 })
	fx.flash(x, y + 50, z, { radius = 100, color = C.SOUL, ttl = 0.35 })
	api.log("legt4keres a3 devour rank=%d ate=%s hpLeft=%d maxHp=%d heal=%d souls=%d", r, UnitDefs[info.unitDefID].name, hp, maxHp, heal, h.store.souls)
	return true
end

---------------------------------------------------------------------------- ult Danse Macabre

local function danseOff(api, unitID, h)
	local dm = h.store.danse
	if not dm then
		return
	end
	h.store.danse = nil
	local fx = L.fx(api)
	for _, id in ipairs(dm.ids) do
		fx.detach(id)
	end
	api.log("legt4keres ult danse over strikes=%d dmg=%d lifesteal heal=%d spirits=%d", dm.strikes, dm.dmg, dm.healed, dm.count)
end

local function danse(api, unitID, h, r)
	local ult = cfg(h, "ult")
	local dur = api.val(ult.duration, r)
	local maxS = api.val(ult.spirits, r)
	local cap = api.rank(h, "a1") > 0 and api.val(cfg(h, "a1").cap, api.rank(h, "a1")) or 0
	local souls = h.store.souls
	local count = min(maxS, souls)
	setSouls(api, unitID, h, souls - count)
	local fx = L.fx(api)
	local dm = { count = max(1, count), max = maxS, grow = souls < cap or cap == 0, strikes = 0, dmg = 0, steal = 0, healed = 0,
		lifesteal = api.val(ult.lifesteal, r) }
	dm.orb = { color = L.a(C.SOUL, 0.9), radius = 14, height = 120, orbit = 380, speed = 0.45, crackle = 3, count = dm.count }
	dm.ids = {
		fx.attach(unitID, "orb", dm.orb),
		fx.attach(unitID, "aura", { radius = 500, color = L.a(C.SOUL, 0.3), pattern = "runes" }),
		fx.attach(unitID, "tint", { pattern = "shadow", color = C.SOUL, strength = 0.5 }),
	}
	h.store.danse = dm
	api.active(unitID, "ult", dur)
	local x, _, z = api.pos(unitID)
	fx.ring(x, z, { kind = "shock", r0 = 60, r1 = 600, color = L.a(C.SOUL, 0.8), width = 30, ttl = 0.6 })
	local R = ult.radius or 1200
	local dmgEach = api.val(ult.dmg, r) * api.power(h)
	L.task(h, 30, dur, function(f)
		local hx, _, hz = api.pos(unitID)
		if not hx or h.store.danse ~= dm then
			return false
		end
		local list = api.nearestEnemies(hx, hz, R, h.ally, dm.count)
		for i = 1, dm.count do
			local uid = list[((i - 1) % max(1, #list)) + 1]
			if uid then
				local ox, oy, oz
				local fxl = api.fx
				if fxl and fxl.orbPos then
					ox, oy, oz = fxl.orbPos(unitID, dm.orb, f, i - 1)
				end
				if not ox or not oy then
					ox, oy, oz = api.pos(unitID)
				end
				local ux, uy, uz = api.pos(uid)
				api.delay(1 + (i % 6), function()
					if L.alive(uid) then
						api.damage(uid, dmgEach, unitID, { dtype = "flame" })
						fx.bolt(ox, oy, oz, ux, uy + 20, uz, { color = C.SOUL, width = 5, jitter = 0.6, branches = 0, ttl = 0.2 })
					end
				end)
				dm.strikes = dm.strikes + 1
				dm.dmg = dm.dmg + dmgEach
				dm.steal = dm.steal + dmgEach * dm.lifesteal
			end
		end
		-- lifesteal of the second
		if dm.steal > 0 then
			api.heal(unitID, dm.steal)
			dm.healed = dm.healed + dm.steal
			dm.steal = 0
		end
	end, function()
		danseOff(api, unitID, h)
	end)
	api.log("legt4keres ult danse rank=%d dur=%.1f spirits=%d (souls %d) dmg=%d lifesteal=%.2f", r, dur, dm.count, souls, dmgEach, dm.lifesteal)
	return true
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.tasks = {}
	h.store.consumed = {}
	h.store.souls = 0
	h.store.orbCount = 0
	h.store.lastCombat = 0
	h.store.wispsThisFrame = 0
	h.store.danse = nil
end

function M.frame(api, unitID, h, f)
	L.runTasks(h, f)
	h.store.wispsThisFrame = 0
	if f % 90 == 0 and h.store.souls > 0 and f - h.store.lastCombat > 300 and not h.store.danse then
		setSouls(api, unitID, h, h.store.souls - 1)
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a2" then
		return deathGrip(api, unitID, h, rank, targetID)
	elseif key == "a3" then
		return devour(api, unitID, h, rank, targetID)
	elseif key == "ult" then
		if h.store.danse then
			return false
		end
		return danse(api, unitID, h, rank)
	end
	return false
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	if key == "a2" then
		local range = api.val(cfg(h, "a2").range, rank)
		local best, bestS
		for _, uid in ipairs(api.enemiesIn(x, z, range, h.ally)) do
			if api.seenBy(uid, h.ally) and grippable(api, h, uid) then
				local ux, _, uz = api.pos(uid)
				if L.d2(x, z, ux, uz) > 400 * 400 then
					local s = api.cost(uid)
					local ud = L.ud(uid)
					if ud and (ud.maxWeaponRange or 0) > 1200 then
						s = s * 1.5
					end
					if api.isHero(uid) then
						s = s * 2
					end
					if not bestS or s > bestS then
						best, bestS = uid, s
					end
				end
			end
		end
		if best and bestS >= 500 then
			local tx, ty, tz = api.pos(best)
			return tx, ty, tz, best
		end
	elseif key == "a3" then
		local reach = (cfg(h, "a3").range or 400) + 60
		local best, bestC
		for _, uid in ipairs(api.enemiesIn(x, z, L.hpFrac(unitID) < 0.6 and 900 or reach, h.ally)) do
			if api.seenBy(uid, h.ally) and edible(api, h, uid, rank) and (not bestC or api.cost(uid) > bestC) then
				best, bestC = uid, api.cost(uid)
			end
		end
		if best then
			local tx, ty, tz = api.pos(best)
			if L.d2(x, z, tx, tz) <= (reach + L.radius(best)) ^ 2 then
				return tx, ty, tz, best
			end
			Spring.GiveOrderToUnit(unitID, CMD.MOVE, { tx, ty, tz }, 0)
		end
	elseif key == "ult" then
		local cap = api.rank(h, "a1") > 0 and api.val(cfg(h, "a1").cap, api.rank(h, "a1")) or 1
		local near = #L.enemies(api, x, z, 1200, h.ally, true)
		if (near >= 8 and h.store.souls >= cap * 0.5) or (L.hpFrac(unitID) < 0.4 and near >= 3) then
			return x, y, z
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	L.endTasks(h)
	danseOff(api, unitID, h)
	L.fx(api).detach(h.store.orbs)
	h.store.orbs = nil
	h.store.orbCount = 0
	h.store.souls = 0
end

return M
