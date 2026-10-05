-- Thor, the Stormbreaker (armt4zeus, armthor model x1.8): the human's concept (doc/v19-heroes/SPEC.md 1.8,
-- roster_arm.md 1). Numbers per rank: luarules/configs/heroes/arm.lua. API: header of luarules/gadgets/unit_t4_heroes.lua.
--
--   a1 Chain Lightning (passive): a Thunder Coil salvo that hits jumps on to 1..8 more enemies (jump range grows);
--      the first jump carries `share` of the salvo's damage on that target, every next one 5% more than the one before.
--      (Rage Mode's orb bolt does not chain since v23.) v23: jumps only reach enemies within 1.25x Thor's longest
--      weapon range of Thor itself (10 jumps of 750 used to walk the chain 7500 deep into the enemy base).
--   a2 EMP Missile (active, map): a homing EMP missile (MissileLauncher hero_empmissile, never the stock starburst):
--      damage + paralysis in the blast, heroes too (half as long, core rule).
--   a3 Electro-Devour (active, own unit): lightning drags one of its own non-hero units in (0.4 s) and Thor eats it:
--      heals 50%..200% of the unit's max health (no cap); healing past full HP becomes Static Overcharge
--      (+1% Coil damage per 1% of max HP overflow, max +30%, 12 s).
--   ult Rage Mode (active, self): Thor grows (x1.35 over 0.6 s), red lightning crawls over it; faster, hull and turret
--      turn faster (armt4zeus.cob SetTurretTurnMult), tougher; its lightning turns red and a storm orb darts above it,
--      adding one bolt per Coil reload on Thor's own target within the Coil's range (orbShare of a salvo, v23).

local L = VFS.Include("luarules/heroes/armt4_lib.lua", nil, VFS.ZIP_FIRST)

local M = {}

local BLUE = { 0.55, 0.85, 1, 1 }
local CHAIN = { 0.4, 0.7, 1, 1 }
local RED = { 1, 0.25, 0.15, 1 }
local ORB = { color = { 1, 0.2, 0.1, 1 }, radius = 26, height = 150, orbit = 70, speed = 1.5, crackle = 4 }
local SALVO_WINDOW = 12 -- frames: the hits of one lightning salvo (10 bolts) count as one

local function b(h, key)
	return h.def.cfg[key]
end

---------------------------------------------------------------------------- a1 Chain Lightning

-- the salvo damage `dmg` on `fromID` (at x, y, z: it may have died of the salvo) jumps on through the nearest enemies
local function chain(api, unitID, h, fromID, dmg, red, x, y, z)
	local r = api.rank(h, "a1")
	local a1 = b(h, "a1")
	if r <= 0 then
		return 0
	end
	if not x then
		x, y, z = api.pos(fromID)
	end
	if not x then
		return 0
	end
	local jumps = api.val(a1.jumps, r)
	local range = api.val(a1.jumpRange, r)
	local d = dmg * api.val(a1.share, r)
	local step = 1 + (a1.stepBonus or 0.05)
	local done = { [fromID] = true }
	local hx, _, hz = api.pos(unitID)
	local reach = (Spring.GetUnitRulesParam(unitID, "hero_range") or 1000) * 1.25
	local reach2 = reach * reach
	local points = { x, y + 30, z }
	local first, total, n = d, 0, 0
	for _ = 1, jumps do
		local best, bestD
		for _, uid in ipairs(api.enemiesIn(x, z, range, h.ally)) do
			if not done[uid] then
				local ux, _, uz = api.pos(uid)
				local dd = (ux - x) ^ 2 + (uz - z) ^ 2
				if hx and (ux - hx) ^ 2 + (uz - hz) ^ 2 > reach2 then
					dd = nil -- beyond Thor's reach
				end
				if dd and (not bestD or dd < bestD) then
					best, bestD = uid, dd
				end
			end
		end
		if not best then
			break
		end
		done[best] = true
		local nx, ny, nz = api.pos(best)
		api.damage(best, d, unitID, { dtype = "electric" })
		points[#points + 1], points[#points + 2], points[#points + 3] = nx, ny + 30, nz
		total = total + d
		n = n + 1
		d = d * step
		x, y, z = nx, ny, nz
	end
	local fx = api.fx
	if n > 0 and fx then
		fx.chain(points, { color = red and RED or CHAIN, width = 2.5 + 1.5 * (r - 1) / 9, branches = 2, jitter = 0.35, ttl = 0.35,
			delay = 0.05 })
	end
	if n > 0 then
		api.log("armt4zeus a1 chain rank=%d salvo=%d jumps=%d/%d range=%d first=%d total=%d", r, dmg, n, jumps, range, first, total)
	end
	return n, total
end

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	if not isParalyzer and damage > 0 and api.rank(h, "a1") > 0 and L.weaponKey(h, weaponDefID) == "thunder" then
		local p = h.store.pending
		local e = p[victimID]
		if not e then
			local x, y, z = api.pos(victimID)
			e = { dmg = 0, first = api.frame(), x = x, y = y, z = z }
			p[victimID] = e
		end
		e.dmg = e.dmg + damage
	end
	return damage
end

---------------------------------------------------------------------------- a2 EMP Missile

local function empMissile(api, unitID, h, r, x, y, z)
	local a2 = b(h, "a2")
	local hx, hy, hz = api.pos(unitID)
	if not hx or not x then
		return false
	end
	local dmg = api.val(a2.dmg, r) * api.power(h)
	local aoe = api.val(a2.aoe, r)
	local stun = api.val(a2.stun, r)
	local ally = h.ally
	local pid = api.fire(h, "hero_empmissile", hx, hy + 70, hz, x, y or L.gy(x, z), z, {
		key = "a2", dmg = dmg, aoe = aoe, stun = stun, dtype = "emp",
		onHit = function(ix, iz, hits)
			local fx = api.fx
			local gy = L.gy(ix, iz)
			if fx then
				fx.ring(ix, iz, { kind = "electric", r0 = 40, r1 = aoe, width = 28, ttl = 0.7, color = { 0.45, 0.75, 1, 0.9 } })
				fx.ring(ix, iz, { kind = "shock", r0 = 20, r1 = aoe * 1.3, width = 40, ttl = 0.45, color = "emp" })
				fx.flash(ix, gy + 30, iz, { radius = aoe * 0.35, color = { 0.55, 0.8, 1, 0.8 }, ttl = 0.3 })
				-- the paralysed: crawling arcs on the 16 most valuable
				table.sort(hits, function(a, c) return api.cost(a) > api.cost(c) end)
				for i = 1, math.min(16, #hits) do
					local t = stun * (api.isHero(hits[i]) and 0.5 or 1)
					fx.attach(hits[i], "electric", { color = "emp", intensity = 0.6, ttl = t })
				end
			end
			local heroesHit = 0
			for _, uid in ipairs(hits) do
				if api.isHero(uid) then
					heroesHit = heroesHit + 1
				end
			end
			api.log("armt4zeus a2 emp impact rank=%d dmg=%d aoe=%d stun=%.1f hit=%d heroes=%d", r, dmg, aoe, stun, #hits, heroesHit)
		end,
	})
	local fx = api.fx
	if fx then
		fx.flash(hx, hy + 90, hz, { radius = 70, color = "emp", ttl = 0.3 })
	end
	return pid ~= nil
end

---------------------------------------------------------------------------- a3 Electro-Devour

local function edible(api, h, uid)
	if not uid or not L.alive(uid) or api.isHero(uid) or Spring.GetUnitTeam(uid) ~= h.team then
		return false
	end
	local ud = UnitDefs[Spring.GetUnitDefID(uid) or -1]
	if not ud or ud.customParams.iscommander or (ud.speed or 0) <= 0 or ud.customParams.t4_summon then
		return false
	end
	local _, _, _, _, bp = Spring.GetUnitHealth(uid)
	return bp and bp >= 1
end

local function devour(api, unitID, h, r, targetID, x, z)
	local a3 = b(h, "a3")
	if not edible(api, h, targetID) and x then
		-- a click on the ground: the nearest own unit there
		local best, bestD
		for _, uid in ipairs(api.alliesIn(x, z, 200, h.ally)) do
			if edible(api, h, uid) then
				local ux, _, uz = api.pos(uid)
				local d = (ux - x) ^ 2 + (uz - z) ^ 2
				if not bestD or d < bestD then
					best, bestD = uid, d
				end
			end
		end
		targetID = best
	end
	if not edible(api, h, targetID) then
		return false
	end
	local hx, hy, hz = api.pos(unitID)
	local tx, ty, tz = api.pos(targetID)
	if L.dist(hx, hz, tx, tz) > api.val(a3.range, r) * 1.15 then
		return false
	end
	local fx = api.fx
	local red = h.store.rage ~= nil
	-- 0.4 s: the unit is dragged toward Thor through three bolts, crawling with electricity
	api.pull(targetID, hx, hz, math.max(0, L.dist(hx, hz, tx, tz) - L.radius(unitID) - L.radius(targetID)), 0.4)
	api.stun(targetID, 1, nil)
	if fx then
		fx.attach(targetID, "electric", { color = red and RED or "electric", intensity = 1.2, ttl = 0.45 })
		fx.attach(unitID, "link", { target = targetID, style = "drain", color = red and RED or "electric", ttl = 0.45 })
	end
	for i = 0, 2 do
		L.after(h, i * 4 + 1, function()
			local ax, ay, az = api.pos(unitID)
			local ux, uy, uz = api.pos(targetID)
			if ax and ux and api.fx then
				api.fx.bolt(ux, uy + 20, uz, ax, ay + 50, az, { color = red and RED or { 0.6, 0.9, 1, 1 }, width = 16, branches = 5,
					ttl = 0.45, seed = api.frame() * 7 + i })
			end
		end)
	end
	local ate = UnitDefs[Spring.GetUnitDefID(targetID)].name
	L.after(h, 12, function()
		if not L.alive(targetID) or not api.hero(unitID) then
			return
		end
		local ux, uy, uz = api.pos(targetID)
		local rad = L.radius(targetID)
		local info = api.consume(targetID)
		if not info then
			return
		end
		local share = api.val(a3.heal, r)
		local amount = info.maxHp * share -- effective HP
		local hp, maxHp = Spring.GetUnitHealth(unitID)
		local effMissing = (maxHp - hp) * (h.hpMult or 1)
		local effMax = maxHp * (h.hpMult or 1)
		local healed = api.heal(unitID, amount)
		local overflow = math.max(0, amount - effMissing)
		local oc = math.min(a3.overchargeMax or 0.3, overflow / effMax)
		local f2 = api.fx
		if f2 then
			f2.flash(ux, uy + 20, uz, { radius = math.max(60, rad * 2), color = red and RED or { 0.6, 0.9, 1, 1 }, ttl = 0.4 })
			local ax, _, az = api.pos(unitID)
			f2.pillar(ax, az, { radius = 70, height = 500, color = { 0.4, 1, 0.8, 0.8 }, ttl = 0.8 })
			f2.attach(unitID, "aura", { pattern = "heal", radius = L.radius(unitID) * 1.4, color = "heal", ttl = 1.2 })
		end
		if oc > 0.005 then
			api.buff(unitID, h, "overcharge", a3.overchargeTime or 12, { damage = oc })
			api.active(unitID, "a3", a3.overchargeTime or 12)
			if f2 then
				if h.store.ocFx then
					f2.detach(h.store.ocFx)
				end
				h.store.ocFx = f2.attach(unitID, "electric", { color = "cyan", intensity = 0.4, ttl = a3.overchargeTime or 12 })
			end
		end
		api.log("armt4zeus a3 devour rank=%d ate=%s maxHp=%d share=%.2f heal=%d healedEngineHp=%d overcharge=%.2f", r,
			ate, info.maxHp, share, amount, healed, oc)
	end)
	return true
end

-- autocast: hurt (AI below 50%, or 70% against a hero; players with autocast below 35%), and an own unit whose
-- meal heals at least 8% of max HP: the cheapest one that covers the missing health
local function devourPick(api, unitID, h, r)
	local a3 = b(h, "a3")
	local hp, maxHp = Spring.GetUnitHealth(unitID)
	if not hp then
		return nil
	end
	local frac = hp / maxHp
	local x, _, z = api.pos(unitID)
	local limit = h.ai and 0.5 or 0.35
	if h.ai and L.enemyHero(api, x, z, api.weaponReach(h) * 1.2, h.ally) then
		limit = 0.7
	end
	if frac > limit then
		return nil
	end
	local share = api.val(a3.heal, r)
	local effMax = maxHp * (h.hpMult or 1)
	local missing = (maxHp - hp) * (h.hpMult or 1)
	local best, bestCost, biggest, biggestHeal
	for _, uid in ipairs(api.alliesIn(x, z, api.val(a3.range, r), h.ally)) do
		if uid ~= unitID and edible(api, h, uid) then
			local ud = UnitDefs[Spring.GetUnitDefID(uid)]
			if not ud.isBuilder then
				local _, mhp = Spring.GetUnitHealth(uid)
				local heal = mhp * share
				if heal >= effMax * 0.08 then
					local c = api.cost(uid)
					if heal >= missing and (not bestCost or c < bestCost) then
						best, bestCost = uid, c
					end
					if not biggestHeal or heal > biggestHeal then
						biggest, biggestHeal = uid, heal
					end
				end
			end
		end
	end
	return best or biggest
end

---------------------------------------------------------------------------- ult Rage Mode

local function thunderInfo(api, h, unitID)
	local w, n = L.weapon(h, "thunder")
	if not w then
		return nil
	end
	local range = Spring.GetUnitWeaponState(unitID, n, "range") or w.range
	local reload = Spring.GetUnitWeaponState(unitID, n, "reloadTime") or w.reload
	return range, reload, w.damage * (w.burst or 1) * (w.projectiles or 1)
end

local function rageMods(api, h, r, scale)
	local ult = b(h, "ult")
	local turn = api.val(ult.turn, r)
	return { scale = scale, speed = api.val(ult.speed, r), turn = turn, turretTurn = turn, armor = api.val(ult.armor, r) }
end

local function rageOn(api, unitID, h, r)
	local ult = b(h, "ult")
	local dur = api.val(ult.duration, r)
	local f = api.frame()
	local rage = { r = r, start = f, untilFrame = f + math.floor(dur * 30), nextOrb = f + 18, shots = 0, dmg = 0 }
	h.store.rage = rage
	api.buff(unitID, h, "rage", dur + 1, rageMods(api, h, r, 1.06))
	api.swapWeapons(unitID, h, "rage")
	local fx = api.fx
	local x, y, z = api.pos(unitID)
	if fx then
		fx.flash(x, y + 60, z, { radius = 150, color = RED, ttl = 0.4 })
		fx.ring(x, z, { kind = "shock", r0 = 40, r1 = 420, width = 36, color = { 1, 0.2, 0.1, 0.8 }, ttl = 0.5 })
		fx.ring(x, z, { kind = "electric", r0 = 60, r1 = 320, width = 30, color = RED, ttl = 0.8 })
		rage.fx = {
			fx.attach(unitID, "electric", { color = RED, intensity = 1.0 }),
			fx.attach(unitID, "aura", { pattern = "electric", radius = 180, color = RED }),
			fx.attach(unitID, "orb", ORB),
			fx.attach(unitID, "trail", { color = RED, width = 14, length = 0.5 }),
			fx.attach(unitID, "tint", { pattern = "heat", color = "rage", strength = 0.5 }),
		}
	end
	api.active(unitID, "ult", dur)
	api.log("armt4zeus ult rage rank=%d dur=%d speed=+%.2f turn=+%.2f armor=%.2f", r, dur, api.val(ult.speed, r), api.val(ult.turn, r), api.val(ult.armor, r))
	return true
end

local function rageOff(api, unitID, h, quiet)
	local rage = h.store.rage
	if not rage then
		return
	end
	h.store.rage = nil
	api.swapWeapons(unitID, h, nil)
	api.unbuff(unitID, h, "rage")
	L.detach(api, rage.fx)
	if not quiet and api.fx then
		local x, y, z = api.pos(unitID)
		if x then
			api.fx.flash(x, y + 50, z, { radius = 110, color = RED, ttl = 0.35 })
		end
	end
	api.log("armt4zeus ult rage over: orb shots=%d dmg=%d", rage.shots or 0, rage.dmg or 0)
end

-- the orb strikes Thor's own target within the Coil range, once per Coil reload, with a share of a salvo
local function rageFrame(api, unitID, h, f)
	local rage = h.store.rage
	local ult = b(h, "ult")
	local endsIn = rage.untilFrame - f
	-- grow over the first 0.6 s, shrink over the last 0.6 s
	local grow = math.max(0, math.min(1, (f - rage.start) / 18, endsIn / 18))
	local want = 1 + ((ult.scale or 1.35) - 1) * grow
	if math.abs(want - (rage.scale or 1)) > 0.02 then
		rage.scale = want
		api.buff(unitID, h, "rage", (endsIn + 30) / 30, rageMods(api, h, rage.r, want))
	end
	if endsIn <= 0 then
		rageOff(api, unitID, h)
		return
	end
	if f < rage.nextOrb then
		return
	end
	local range, reload, salvo = thunderInfo(api, h, unitID)
	if not range then
		return
	end
	-- v23: the orb is one extra bolt on Thor's own target within the Coil's range (it struck the most valuable enemy at
	-- 2x range with a full salvo plus its chain - a second, longer-ranged Coil)
	local orbRange = range * (ult.orbRange or 1)
	local x, _, z = api.pos(unitID)
	local target = api.target(unitID)
	if not (target and L.unitDist(unitID, target) <= orbRange and Spring.GetUnitAllyTeam(target) ~= h.ally) then
		target = nil
	end
	if not target then
		rage.nextOrb = f + 6
		return
	end
	rage.nextOrb = f + math.max(9, math.floor(reload * 30))
	local fx = api.fx
	local ox, oy, oz
	if fx then
		ox, oy, oz = fx.orbPos(unitID, ORB, f)
	end
	if not ox then
		ox, oy, oz = x, select(2, api.pos(unitID)) + ORB.height, z
	end
	local tx, ty, tz = api.pos(target)
	if fx then
		fx.bolt(ox, oy, oz, tx, ty + 25, tz, { color = RED, width = 10, branches = 3, ttl = 0.35, intensity = 1.4 })
	end
	local dmg = salvo * api.dmgMult(h) * api.val(ult.orbShare or 0.5, rage.r)
	api.damage(target, dmg, unitID, { dtype = "electric" })
	rage.shots = rage.shots + 1
	rage.dmg = rage.dmg + dmg
	api.log("armt4zeus ult orb strike dmg=%d range=%d dist=%d", dmg, orbRange, L.dist(x, z, tx, tz))
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.pending = {}
	h.store.rage = nil
	-- the stock EMP missile (a manual stockpile weapon) is the a2 active now: it never fires on its own
	if api.weaponNum(h, "empmissile") then
		api.disableWeapon(unitID, h, "empmissile", true)
	end
end

function M.frame(api, unitID, h, f)
	L.tick(h, f)
	local p = h.store.pending
	for victim, e in pairs(p) do
		if f - e.first >= SALVO_WINDOW then
			p[victim] = nil
			if e.x then
				chain(api, unitID, h, victim, e.dmg, h.store.rage ~= nil, e.x, e.y, e.z)
			end
		end
	end
	if h.store.rage then
		rageFrame(api, unitID, h, f)
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a2" then
		if targetID and not x then
			x, y, z = api.pos(targetID)
		end
		return empMissile(api, unitID, h, rank, x, y, z)
	elseif key == "a3" then
		return devour(api, unitID, h, rank, targetID, x, z)
	elseif key == "ult" then
		if h.store.rage then
			return false
		end
		return rageOn(api, unitID, h, rank)
	end
	return false
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	if key == "a2" then
		local a2 = b(h, "a2")
		local range = api.val(a2.range, rank)
		local hero = L.enemyHero(api, x, z, range, h.ally)
		if hero then
			local hx, hy, hz = api.pos(hero)
			return hx, hy, hz
		end
		local cx, cz, cost, n = L.cluster(api, x, z, range, api.val(a2.aoe, rank) * 0.8, h.ally)
		if cx and n >= 6 and cost >= 8000 then
			return cx, L.gy(cx, cz), cz
		end
	elseif key == "a3" then
		local t = devourPick(api, unitID, h, rank)
		if t then
			local tx, ty, tz = api.pos(t)
			return tx, ty, tz, t
		end
	elseif key == "ult" then
		if h.store.rage then
			return nil
		end
		local range = thunderInfo(api, h, unitID) or 900
		local cost, n = api.enemyCostNear(x, z, range * 1.5, h.ally)
		if n >= 10 or cost >= 25000 or L.enemyHero(api, x, z, range, h.ally) or (L.hpFrac(unitID) < 0.35 and n > 0) then
			return x, y, z
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	rageOff(api, unitID, h, true)
end

return M
