-- Razor, the Phantom (armt4aegis, Razorback x2): the human's concept - a very fast laser assassin with stealth
-- (doc/v19-heroes/SPEC.md 1.8, roster_arm.md 4). Numbers: luarules/configs/heroes/arm.lua.
--
--   a1 Phantom Cloak (active, self): cloaked (hidden from enemy sight, holds fire) and faster; an enemy within 100
--      reveals it. Leaving the cloak (attack order, timeout, AI ambush) arms the Ambush: the first salvo deals bonus
--      damage and every drone fires at that target at once. The cooldown starts when the cloak ends.
--   a2 Deflector Shell (passive): a Lua absorb pool (h.absorb, core abilityVictim) soaks all damage before HP and
--      recharges 3 s after the last hit (6 s after it broke). Unit rules params hero_absorb / hero_absorb_max.
--   a3 Overcharge (toggle): +fire rate (reload buff), burns max HP per second, switches itself off at 15% HP.
--   ult Razor Swarm (passive): real drone units (armt4aegis_drone, red beam lasers) circle Razor and shoot its target;
--      a lost drone is rebuilt every 8 s. Drone damage per rank (unit buff) and level (summon scaleWithLevel).
--      While Razor is cloaked the drones go dark and hold fire.

local L = VFS.Include("luarules/heroes/armt4_lib.lua", nil, VFS.ZIP_FIRST)

local M = {}

local CRIMSON = { 1, 0.2, 0.2, 1 }
local SHELL = { 0.5, 0.75, 1, 0.25 }
local OC = { 1, 0.45, 0.15, 1 }
local DRONE = "armt4aegis_drone"
local DRONE_BASE_DPS = 700 -- the drone weapondef (units/ArmT4/armt4units.lua): 350 / 0.5 s

local function b(h, key)
	return h.def.cfg[key]
end

local droneDefID = UnitDefNames[DRONE] and UnitDefNames[DRONE].id

local function drones(h)
	return droneDefID and Spring.GetTeamUnitsByDefs(h.team, droneDefID) or {}
end

---------------------------------------------------------------------------- ult Razor Swarm

local function droneTick(api, unitID, h, f)
	local r = api.rank(h, "ult")
	if r <= 0 or not droneDefID then
		return
	end
	local ult = b(h, "ult")
	local want = api.val(ult.count, r)
	local list = drones(h)
	local st = h.store
	if #list < want and f >= (st.nextDrone or 0) then
		local n = st.nextDrone and 1 or (want - #list) -- the first time: the whole crown at once
		local ids = api.summon(unitID, h, DRONE, n, { guard = unitID, leash = 450, scaleWithLevel = true, spread = 140 })
		st.nextDrone = f + math.floor((ult.rebuild or 8) * 30)
		for _, uid in ipairs(ids) do
			list[#list + 1] = uid
		end
		if #ids > 0 then
			api.log("armt4aegis ult swarm: built %d drone(s), now %d/%d", #ids, #list, want)
		end
	elseif #list >= want then
		st.nextDrone = f + math.floor((ult.rebuild or 8) * 30)
	end
	local bonus = api.val(ult.dps, r) / DRONE_BASE_DPS - 1
	local cloaked = st.cloak ~= nil
	local fx = api.fx
	st.droneFx = st.droneFx or {}
	for _, uid in ipairs(list) do
		api.unitBuff(uid, "razor_swarm", 2, { damage = bonus, cloak = cloaked })
		if fx and not st.droneFx[uid] then
			st.droneFx[uid] = fx.attach(uid, "trail", { color = CRIMSON, width = 6, length = 0.4 })
		end
		local want = cloaked and 0 or 2
		if st.droneFire ~= want then
			Spring.GiveOrderToUnit(uid, CMD.FIRE_STATE, { want }, 0)
		end
	end
	st.droneFire = cloaked and 0 or 2
end

-- the Ambush: every drone fires at the target at once (one second of its DPS, with the ambush bonus)
local function droneVolley(api, unitID, h, targetID, mult)
	local r = api.rank(h, "ult")
	if r <= 0 then
		return 0
	end
	local per = api.val(b(h, "ult").dps, r) * (api.power(h) / (api.H.ABILITY_POWER_BASE or 1.5)) * mult
	local tx, ty, tz = api.pos(targetID)
	local n = 0
	for _, uid in ipairs(drones(h)) do
		local dx, dy, dz = api.pos(uid)
		if dx and L.dist(dx, dz, tx, tz) < 1200 then
			n = n + 1
			api.damage(targetID, per, unitID, { dtype = "laser" })
			if api.fx then
				api.fx.beam(dx, dy, dz, tx, ty + 20, tz, { color = { 1, 0.15, 0.1, 1 }, width = 4, ttl = 0.15, flare = 0.8 })
			end
		end
	end
	return n, per * n
end

---------------------------------------------------------------------------- a1 Phantom Cloak

local function cloakOn(api, unitID, h, r)
	local a1 = b(h, "a1")
	local dur = api.val(a1.duration, r)
	api.buff(unitID, h, "cloak", dur, { cloak = true, speed = api.val(a1.speed, r) })
	api.active(unitID, "a1", dur)
	local f = api.frame()
	local st = { r = r, untilFrame = f + math.floor(dur * 30) }
	local fx = api.fx
	local x, _, z = api.pos(unitID)
	if fx then
		fx.ring(x, z, { kind = "hex", r0 = 0, r1 = 150, color = { 0.6, 0.8, 1, 0.5 }, ttl = 0.4, width = 30 })
		st.fx = { fx.attach(unitID, "cloak", { color = "cloak" }), fx.attach(unitID, "trail", { color = { 0.6, 0.8, 1, 0.25 }, width = 10, length = 0.5 }) }
	end
	h.store.cloak = st
	droneTick(api, unitID, h, f)
	api.log("armt4aegis a1 cloak rank=%d dur=%.1f speed=+%.2f", r, dur, api.val(a1.speed, r))
	return true
end

local function cloakOff(api, unitID, h, why)
	local st = h.store.cloak
	if not st then
		return
	end
	h.store.cloak = nil
	api.unbuff(unitID, h, "cloak")
	L.detach(api, st.fx)
	local f = api.frame()
	h.store.ambushUntil = f + 90
	h.store.ambushHit = nil
	-- the cooldown starts when the cloak ends
	api.cooldown(unitID, h, "a1", api.val(b(h, "a1").cooldown, st.r))
	api.active(unitID, "a1", 0)
	droneTick(api, unitID, h, f)
	api.log("armt4aegis a1 cloak ends (%s)", why)
end

local function cloakFrame(api, unitID, h, f)
	local st = h.store.cloak
	if f >= st.untilFrame then
		cloakOff(api, unitID, h, "timeout")
		return
	end
	local x, _, z = api.pos(unitID)
	local near = Spring.GetUnitNearestEnemy(unitID, 100 + L.radius(unitID), false)
	if near then
		cloakOff(api, unitID, h, "revealed")
		return
	end
	local target = api.target(unitID)
	if target and Spring.GetUnitAllyTeam(target) ~= h.ally and L.unitDist(unitID, target) <= api.weaponReach(h) + L.radius(target) + 60 then
		cloakOff(api, unitID, h, "attack")
		return
	end
	if h.ai and #L.seenEnemies(api, x, z, api.weaponReach(h) * 0.85, h.ally) > 0 then
		cloakOff(api, unitID, h, "ambush")
	end
end

---------------------------------------------------------------------------- a2 Deflector Shell

local function shellTick(api, unitID, h, f)
	local r = api.rank(h, "a2")
	if r <= 0 then
		return
	end
	local a2 = b(h, "a2")
	local cap = api.val(a2.capacity, r) * api.power(h)
	local st = h.store
	local ab = h.absorb
	if not ab or not st.shellOwn then
		ab = { left = cap, max = cap, expire = f + 1e8 }
		h.absorb = ab
		st.shellOwn = true
		st.shellLeft = cap
	end
	ab.expire = f + 1e8
	ab.max = cap
	local x, y, z = api.pos(unitID)
	local fx = api.fx
	if fx and not st.shellFx then
		st.shellFx = fx.attach(unitID, "sphere", { radius = 130, color = SHELL, hex = true, fresnel = 1.5, height = 75 })
	end
	if ab.left < (st.shellLeft or cap) - 1 then
		-- hit: ripple toward the nearest enemy, recharge waits
		st.shellHit = f
		local e = Spring.GetUnitNearestEnemy(unitID, 2500, true)
		if fx and st.shellFx and f - (st.shellRipple or 0) >= 4 then
			st.shellRipple = f
			local ex, _, ez = e and api.pos(e)
			local dx, dz = (ex or x + 1) - x, (ez or z) - z
			local d = math.max(1, math.sqrt(dx * dx + dz * dz))
			fx.hit(st.shellFx, x + dx / d * 125, y + 75, z + dz / d * 125)
		end
		if ab.left <= 0 and (st.shellLeft or 0) > 0 then
			st.shellBroken = f
			if fx then
				fx.flash(x, y + 70, z, { radius = 160, color = SHELL, ttl = 0.35 })
				fx.ring(x, z, { kind = "hex", r0 = 60, r1 = 220, color = { 0.5, 0.75, 1, 0.8 }, ttl = 0.4, width = 30 })
			end
			api.log("armt4aegis a2 shell broken (cap %d)", cap)
		end
	end
	local delay = (st.shellBroken and (st.shellHit or 0) <= st.shellBroken + 1) and (a2.brokenDelay or 6) or (a2.delay or 3)
	if ab.left < cap and f - (st.shellHit or -1e9) >= delay * 30 then
		ab.left = math.min(cap, ab.left + api.val(a2.regen, r) * api.power(h) * 0.1)
		if ab.left >= cap then
			st.shellBroken = nil
		end
	end
	st.shellLeft = ab.left
	local frac = ab.left / math.max(1, cap)
	if fx and st.shellFx and math.abs(frac - (st.shellFrac or -1)) > 0.04 then
		st.shellFrac = frac
		fx.set(st.shellFx, { alpha = frac > 0.01 and (0.2 + 0.45 * frac) or 0, time = 0.3 })
	end
	if f % 15 == 0 then
		Spring.SetUnitRulesParam(unitID, "hero_absorb", math.floor(ab.left), { allied = true })
		Spring.SetUnitRulesParam(unitID, "hero_absorb_max", math.floor(cap), { allied = true })
	end
end

---------------------------------------------------------------------------- a3 Overcharge

local function overchargeOn(api, unitID, h, r)
	local a3 = b(h, "a3")
	api.buff(unitID, h, "overcharge", nil, { reload = api.val(a3.rate, r) })
	api.swapWeapons(unitID, h, "oc")
	local st = { r = r, since = api.frame(), quiet = api.frame() }
	local fx = api.fx
	if fx then
		st.fx = { fx.attach(unitID, "electric", { color = OC, intensity = 0.5 }), fx.attach(unitID, "aura", { pattern = "heat", color = "orange", radius = 120 }) }
	end
	h.store.oc = st
	api.log("armt4aegis a3 overcharge on rank=%d rate=+%.2f", r, api.val(a3.rate, r))
	return true
end

function M.toggleOff(api, unitID, h, key, rank)
	if key ~= "a3" then
		return
	end
	local st = h.store.oc
	h.store.oc = nil
	api.unbuff(unitID, h, "overcharge")
	api.swapWeapons(unitID, h, nil)
	if st then
		L.detach(api, st.fx)
		api.log("armt4aegis a3 overcharge off after %.1f s, burned %d HP", (api.frame() - st.since) / 30, st.burned or 0)
	end
end

local function overchargeFrame(api, unitID, h, f)
	local st = h.store.oc
	local a3 = b(h, "a3")
	local hp, maxHp = Spring.GetUnitHealth(unitID)
	if not hp then
		return
	end
	local burn = maxHp * api.val(a3.hpCost, st.r) * 0.1
	if (hp - burn) / maxHp <= (a3.minHp or 0.15) then
		api.toggleOff(unitID, h, "a3")
		return
	end
	Spring.SetUnitHealth(unitID, hp - burn)
	st.burned = (st.burned or 0) + burn * (h.hpMult or 1)
	if h.ai or h.autocast then
		local x, _, z = api.pos(unitID)
		if #L.seenEnemies(api, x, z, api.weaponReach(h), h.ally) > 0 then
			st.quiet = f
		end
		if hp / maxHp < 0.35 or f - st.quiet > 120 then
			api.toggleOff(unitID, h, "a3")
		end
	end
end

---------------------------------------------------------------------------- hits

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	local f = api.frame()
	local st = h.store
	if st.cloak then
		cloakOff(api, unitID, h, "fired") -- a shot out of the cloak (attack order): this is the Ambush
	end
	if (st.ambushUntil or 0) > f and not isParalyzer then
		local r = api.rank(h, "a1")
		local mult = 1 + api.val(b(h, "a1").ambush, r)
		if not st.ambushHit then
			-- the first salvo out of the cloak: ~0.7 s of hits
			st.ambushHit = f + 21
			st.ambushTarget = victimID
			local n, dealt = droneVolley(api, unitID, h, victimID, mult)
			if api.fx then
				local x, y, z = api.pos(victimID)
				api.fx.flash(x, y + 20, z, { radius = 80, color = { 0.85, 0.6, 1, 1 }, ttl = 0.4 })
			end
			api.log("armt4aegis a1 ambush rank=%d mult=%.2f victim=%s drones=%d droneDmg=%d", r, mult, UnitDefs[victimDefID].name, n or 0, dealt or 0)
		end
		if f <= st.ambushHit then
			damage = damage * mult
		else
			st.ambushUntil = 0
		end
	end
	return damage
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.cloak = nil
	h.store.oc = nil
	h.store.shellFx = nil
	h.store.shellOwn = nil
	h.store.droneFx = {}
	h.store.nextDrone = nil
end

function M.rank(api, unitID, h, key, rank)
	if key == "ult" then
		h.store.nextDrone = nil -- the new drone(s) at once
	end
end

function M.frame(api, unitID, h, f)
	shellTick(api, unitID, h, f)
	if h.store.cloak then
		cloakFrame(api, unitID, h, f)
	end
	if h.store.oc then
		overchargeFrame(api, unitID, h, f)
	end
	if f % 30 == 0 then
		droneTick(api, unitID, h, f)
		for uid in pairs(h.store.droneFx or {}) do
			if not L.alive(uid) then
				h.store.droneFx[uid] = nil
			end
		end
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a1" then
		if h.store.cloak then
			return false
		end
		return cloakOn(api, unitID, h, rank)
	elseif key == "a3" then
		return overchargeOn(api, unitID, h, rank)
	end
	return false
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	local hp = L.hpFrac(unitID)
	if key == "a1" then
		if h.store.cloak then
			return nil
		end
		if hp < 0.35 and Spring.GetUnitNearestEnemy(unitID, 1200, true) then
			return x, y, z
		end
		-- moving toward a far target (an enemy hero or the back line)
		local target = api.target(unitID)
		local cmds = Spring.GetUnitCommands(unitID, 1)
		local moving = cmds and cmds[1] and (cmds[1].id == CMD.MOVE or cmds[1].id == CMD.FIGHT or cmds[1].id == CMD.ATTACK)
		if moving and h.ai and #L.seenEnemies(api, x, z, api.weaponReach(h), h.ally) == 0 then
			local hero = L.enemyHero(api, x, z, 2500, h.ally)
			if hero and L.unitDist(unitID, hero) >= 1200 then
				return x, y, z
			end
		end
		if target and L.unitDist(unitID, target) >= 1200 then
			return x, y, z
		end
	elseif key == "a3" then
		if not h.store.oc and hp > 0.45 and #L.seenEnemies(api, x, z, api.weaponReach(h), h.ally) > 0 then
			return x, y, z
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	if h.store.cloak then
		L.detach(api, h.store.cloak.fx)
	end
	if h.store.oc then
		L.detach(api, h.store.oc.fx)
	end
	if h.absorb and h.store.shellOwn then
		h.absorb = nil
	end
	h.store.cloak, h.store.oc = nil, nil
end

return M
