-- Thor, the Storm Tank (armt4zeus, armthor model) - v19 reference module of the hero ability API
-- (doc/v19-heroes/SPEC.md sections 1.8 and 4; API: header of luarules/gadgets/unit_t4_heroes.lua).
-- Loaded by the hero gadget with VFS.Include (synced); returns the hooks. Numbers per rank: the `armt4zeus`
-- entry of luarules/configs/heroes/arm.lua (api.val(b.field, rank)).
--
--   a1 Chain Lightning (passive): a lightning salvo that hits an enemy jumps on to 1..10 enemies (jump range grows
--      with the rank); the first jump carries `share` of the salvo's damage on that target, every next one 5% more
--      than the one before.
--   a2 EMP Missile (active, map): a homing EMP missile (MissileLauncher weapondef hero_empmissile): damage plus
--      paralysis in its blast - heroes too, half as long (api.stun).
--   a3 Electro-Devour (active, own unit): consumes one of its own non-hero units (no wreck) and heals 50%..200% of
--      that unit's max health (effective HP, no cap).
--   ult Rage Mode (active, self): grows (model scale), wrapped in red lightning; faster, turns faster, hits harder;
--      its lightning turns red (api.swapWeapons -> thunder_rage copies) and an electric orb above it strikes the
--      nearest enemy within twice the tank's lightning range with the tank's own salvo damage, every reload.
-- Effects: GG.HeroFX (api.fx) when the fx library is there, else the stock lightning weapondefs / CEGs.

local M = {}

local BLUE = { 0.55, 0.72, 1.0, 1.0 }
local RED = { 1.0, 0.22, 0.12, 1.0 }
local ORB = { radius = 26, height = 150, orbit = 70, speed = 1.6 }
local SALVO_WINDOW = 12 -- frames: the hits of one lightning salvo (10 bolts) count as one

local function b(h, key)
	return h.def.cfg[key]
end

-- a lightning bolt from a to b: the fx library, else the hero's lightning weapondef as a visual (no damage)
local function bolt(api, h, x1, y1, z1, x2, y2, z2, red)
	local fx = api.fx
	if fx and fx.bolt then
		fx.bolt(x1, y1, z1, x2, y2, z2, { color = red and RED or BLUE, width = red and 9 or 6, ttl = 0.3, branches = 2 })
	else
		api.fire(h, red and "thunder_rage" or "hero_ab_bolt", x1, y1, z1, x2, y2, z2, { ttl = 6 })
	end
end

-- where the orb is (synced): the fx library's pure function, else the same kind of orbit
local function orbPos(api, unitID, f)
	local fx = api.fx
	if fx and fx.orbPos then
		local x, y, z = fx.orbPos(unitID, ORB, f)
		if x then
			return x, y, z
		end
	end
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	local a = f / 30 * ORB.speed
	return x + math.cos(a) * ORB.orbit, y + ORB.height + math.sin(f / 13) * 12, z + math.sin(a) * ORB.orbit
end

---------------------------------------------------------------------------- a1 Chain Lightning

-- the salvo damage `dmg` on `fromID` jumps on through the nearest enemies
local function chain(api, unitID, h, fromID, dmg, red)
	local r = api.rank(h, "a1")
	local a1 = b(h, "a1")
	if r <= 0 or not a1 then
		return 0
	end
	local x, y, z = api.pos(fromID)
	if not x then
		return 0
	end
	local jumps = api.val(a1.jumps, r)
	local range = api.val(a1.jumpRange, r)
	local d = dmg * api.val(a1.share, r)
	local step = 1 + (a1.stepBonus or 0.05)
	local done = { [fromID] = true }
	local points = { x, y + 25, z }
	local first, last, n = d, d, 0
	for _ = 1, jumps do
		local best, bestD
		for _, uid in ipairs(api.enemiesIn(x, z, range, h.ally)) do
			if not done[uid] then
				local ux, _, uz = api.pos(uid)
				local dd = (ux - x) ^ 2 + (uz - z) ^ 2
				if not bestD or dd < bestD then
					best, bestD = uid, dd
				end
			end
		end
		if not best then
			break
		end
		done[best] = true
		local nx, ny, nz = api.pos(best)
		if not (api.fx and api.fx.chain) then
			bolt(api, h, x, y + 25, z, nx, ny + 25, nz, red)
		end
		api.damage(best, d, unitID, { dtype = "electric" })
		api.ceg("hero-chain", nx, ny, nz)
		points[#points + 1], points[#points + 2], points[#points + 3] = nx, ny + 25, nz
		last = d
		n = n + 1
		d = d * step
		x, y, z = nx, ny, nz
	end
	if n > 0 and api.fx and api.fx.chain then
		api.fx.chain(points, { color = red and RED or BLUE, width = red and 8 or 6, ttl = 0.35, branches = 1 })
	end
	if n > 0 then
		api.log("armt4zeus a1 chain rank=%d salvo=%d jumps=%d/%d range=%d first=%d last=%d", r, dmg, n, jumps, range, first, last)
	end
	return n
end

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	if not isParalyzer and damage > 0 and api.rank(h, "a1") > 0 and api.damageType(weaponDefID) == "electric" then
		local p = h.store.pending
		local e = p[victimID]
		if not e then
			e = { dmg = 0, first = api.frame() }
			p[victimID] = e
		end
		e.dmg = e.dmg + damage
	end
	return damage
end

---------------------------------------------------------------------------- a2 EMP Missile

local function empMissile(api, unitID, h, r, x, y, z, targetID)
	local a2 = b(h, "a2")
	local hx, hy, hz = api.pos(unitID)
	if not hx or not x then
		return false
	end
	local dmg = api.val(a2.dmg, r) * api.power(h)
	local aoe = api.val(a2.aoe, r)
	local stun = api.val(a2.stun, r)
	local pid = api.fire(h, "hero_empmissile", hx, hy + 70, hz, x, y or 0, z, {
		key = "a2", dmg = dmg, aoe = aoe, stun = stun, dtype = "emp", fx = "hero-nova-emp",
		onHit = function(ix, iz, hits)
			local fx = api.fx
			if fx and fx.ring then
				fx.ring(ix, iz, { r0 = 30, r1 = aoe, color = { 0.6, 0.75, 1, 0.9 }, ttl = 0.6, kind = "electric" })
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
	api.ceg("hero-missile-launch", hx, hy + 40, hz)
	return pid ~= nil
end

---------------------------------------------------------------------------- a3 Electro-Devour

local function edible(api, h, uid)
	if not uid or api.isHero(uid) or Spring.GetUnitTeam(uid) ~= h.team or Spring.GetUnitIsDead(uid) then
		return false
	end
	local ud = UnitDefs[Spring.GetUnitDefID(uid) or -1]
	if not ud or ud.customParams.iscommander or (ud.speed or 0) <= 0 then
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
		for _, uid in ipairs(api.alliesIn(x, z, 160, h.ally)) do
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
	bolt(api, h, hx, hy + 40, hz, tx, ty + 20, tz, h.store.rage ~= nil)
	local fx = api.fx
	if fx and fx.flash then
		fx.flash(tx, ty + 20, tz, { radius = 90, color = { 0.6, 0.8, 1, 1 }, ttl = 0.5 })
	end
	api.ceg("hero-zap", tx, ty, tz)
	local info = api.consume(targetID)
	if not info then
		return false
	end
	local share = api.val(a3.heal, r)
	local healed = api.heal(unitID, info.maxHp * share) -- effective HP; engine HP returned
	api.ceg("hero-heal-spark", hx, hy, hz)
	api.log("armt4zeus a3 devour rank=%d ate=%s maxHp=%d share=%.2f heal=%d healedEngineHp=%d", r,
		UnitDefs[info.unitDefID].name, info.maxHp, share, info.maxHp * share, healed)
	return true
end

-- autocast: hurt, and an own unit worth eating close by (the AI, or any hero below 35%)
local function devourPick(api, unitID, h, r)
	local a3 = b(h, "a3")
	local hp, maxHp = Spring.GetUnitHealth(unitID)
	if not hp or hp / maxHp > (h.ai and 0.55 or 0.35) then
		return nil
	end
	local x, _, z = api.pos(unitID)
	local best, bestHp
	for _, uid in ipairs(api.alliesIn(x, z, api.val(a3.range, r), h.ally)) do
		if uid ~= unitID and edible(api, h, uid) then
			local ud = UnitDefs[Spring.GetUnitDefID(uid)]
			if not ud.isBuilder then
				local _, mhp = Spring.GetUnitHealth(uid)
				if mhp and (not bestHp or mhp > bestHp) then
					best, bestHp = uid, mhp
				end
			end
		end
	end
	return best
end

---------------------------------------------------------------------------- ult Rage Mode

local function thunderInfo(api, h, unitID)
	local n = api.weaponNum(h, "thunder")
	local w = n and h.def.weapons[n]
	if not w then
		return nil
	end
	local range = Spring.GetUnitWeaponState(unitID, n, "range") or w.range
	local reload = Spring.GetUnitWeaponState(unitID, n, "reloadTime") or w.reload
	return range, reload, w.damage * (w.burst or 1) * (w.projectiles or 1)
end

local function rageOn(api, unitID, h, r)
	local ult = b(h, "ult")
	local dur = api.val(ult.duration, r)
	api.buff(unitID, h, "rage", dur, {
		scale = api.val(ult.scale, r), speed = api.val(ult.speed, r), turn = api.val(ult.turn, r),
		damage = api.val(ult.damage, r), turretTurn = api.val(ult.turn, r),
	})
	api.swapWeapons(unitID, h, "rage")
	local f = api.frame()
	local rage = { untilFrame = f + math.floor(dur * 30), nextOrb = f + 15 }
	local fx = api.fx
	if fx and fx.attach then
		rage.elec = fx.attach(unitID, "electric", { color = RED, intensity = 1.0 })
		rage.orb = fx.attach(unitID, "orb", { color = RED, radius = ORB.radius, height = ORB.height, orbit = ORB.orbit, speed = ORB.speed })
		rage.aura = fx.attach(unitID, "aura", { radius = 160, color = { 1, 0.25, 0.15, 0.7 }, pattern = "electric" })
	end
	h.store.rage = rage
	api.active(unitID, "ult", dur)
	local x, y, z = api.pos(unitID)
	api.ceg("hero-levelup-big", x, y, z)
	api.log("armt4zeus ult rage rank=%d dur=%d scale=%.2f speed=+%.2f damage=+%.2f", r, dur, api.val(ult.scale, r), api.val(ult.speed, r), api.val(ult.damage, r))
	return true
end

local function rageOff(api, unitID, h)
	local rage = h.store.rage
	if not rage then
		return
	end
	h.store.rage = nil
	api.swapWeapons(unitID, h, nil)
	api.unbuff(unitID, h, "rage")
	local fx = api.fx
	if fx and fx.detach then
		for _, id in ipairs({ rage.elec, rage.orb, rage.aura }) do
			if id then
				fx.detach(id)
			end
		end
	end
	api.log("armt4zeus ult rage over: orb shots=%d dmg=%d", rage.shots or 0, rage.dmg or 0)
end

-- the orb strikes the nearest seen enemy within twice the lightning range, every reload, with the salvo damage
local function rageFrame(api, unitID, h, f)
	local rage = h.store.rage
	if f >= rage.untilFrame then
		rageOff(api, unitID, h)
		return
	end
	local ox, oy, oz = orbPos(api, unitID, f)
	if not ox then
		return
	end
	if not (api.fx and api.fx.attach) then
		-- fallback look: red sparks on the tank, a spark where the orb is
		if f % 6 == 0 then
			api.ceg("hero-zap", ox, oy, oz)
		end
		if f % 15 == 0 then
			local x, y, z = api.pos(unitID)
			api.ceg("hero-static", x, y + 20, z)
		end
	end
	if f < rage.nextOrb then
		return
	end
	local range, reload, salvo = thunderInfo(api, h, unitID)
	if not range then
		return
	end
	local orbRange = range * (b(h, "ult").orbRange or 2)
	local x, _, z = api.pos(unitID)
	local target
	for _, uid in ipairs(api.nearestEnemies(x, z, orbRange, h.ally, 12)) do
		if api.seenBy(uid, h.ally) then
			target = uid
			break
		end
	end
	if not target then
		rage.nextOrb = f + 10
		return
	end
	rage.nextOrb = f + math.max(10, math.floor(reload * 30))
	local tx, ty, tz = api.pos(target)
	bolt(api, h, ox, oy, oz, tx, ty + 20, tz, true)
	local dmg = salvo * api.dmgMult(h)
	api.damage(target, dmg, unitID, { dtype = "electric" })
	rage.shots = (rage.shots or 0) + 1
	rage.dmg = (rage.dmg or 0) + dmg
	chain(api, unitID, h, target, dmg, true) -- the passive works for the orb's strikes too
	api.log("armt4zeus ult orb strike dmg=%d range=%d dist=%d", dmg, orbRange, math.sqrt((tx - x) ^ 2 + (tz - z) ^ 2))
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.pending = {}
	h.store.rage = nil
	-- the stock EMP missile (manual stockpile weapon) is the a2 active now
	if api.weaponNum(h, "empmissile") then
		api.disableWeapon(unitID, h, "empmissile", true)
	end
end

function M.rank(api, unitID, h, key, rank)
	api.log("armt4zeus learned %s rank %d (level %d)", key, rank, h.level)
end

function M.frame(api, unitID, h, f)
	local p = h.store.pending
	if p then
		for victim, e in pairs(p) do
			if f - e.first >= SALVO_WINDOW then
				p[victim] = nil
				if Spring.ValidUnitID(victim) then
					chain(api, unitID, h, victim, e.dmg, h.store.rage ~= nil)
				end
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
		return empMissile(api, unitID, h, rank, x, y, z, targetID)
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
		local score, tx, tz = api.bestCluster(x, z, api.val(a2.range, rank), api.val(a2.aoe, rank), h.ally)
		local hero
		for _, uid in ipairs(api.nearestEnemies(x, z, api.val(a2.range, rank), h.ally, 20)) do
			if api.isHero(uid) and api.seenBy(uid, h.ally) then
				hero = uid
				break
			end
		end
		if hero then
			local hx, hy, hz = api.pos(hero)
			return hx, hy, hz, hero
		end
		if tx and score >= 3000 then
			return tx, Spring.GetGroundHeight(tx, tz), tz
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
		local range = thunderInfo(api, h, unitID) or 800
		if api.enemyCostNear(x, z, range * 1.5, h.ally) >= 8000 then
			return x, y, z
		end
		for _, uid in ipairs(api.nearestEnemies(x, z, range * 2, h.ally, 10)) do
			if api.isHero(uid) then
				return x, y, z
			end
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	rageOff(api, unitID, h)
end

return M
