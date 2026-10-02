-- Prowler, the Riptide (armt4prowler, armprowl x2.6, amphibious): the human's "twin-barrel tank with a rocket launcher",
-- a hunter of big targets (doc/v19-heroes/roster_arm.md 5). Numbers: luarules/configs/heroes/arm.lua.
--
--   a1 Tandem Strike (passive): every Twin Gauss hit adds a Breach stack (6 s); a Tandem Missile hit on a breached
--      target detonates every stack for bonus damage (rail).
--   a2 Harpoon (active, enemy unit): damage, maximum Breach, drags the prey to Prowler over 0.6 s (not heroes, not units
--      heavier than Prowler) and roots it; heroes are only rooted (1.5 s).
--   a3 Riptide Fog (active, map): a sea-fog cloud - allies inside are cloaked (Prowler until it fires), enemies slowed
--      30%, Prowler 30% faster inside.
--   ult Apex Predator (active, enemy unit): the prey is revealed, Prowler is faster and hits it harder, missiles detonate
--      Breach without using it up; if the prey dies, Prowler heals 25% and half of the cooldown comes back.

local L = VFS.Include("luarules/heroes/armt4_lib.lua", nil, VFS.ZIP_FIRST)

local M = {}

local BREACH = { 1, 0.6, 0.2, 0.6 }
local FOG = { 0.3, 0.5, 0.6, 0.6 }
local PREY = { 1, 0.2, 0.15, 0.7 }
local CABLE = { 0.8, 0.8, 0.85, 1 }

local function b(h, key)
	return h.def.cfg[key]
end

local function gunRange(api, unitID, h)
	local w, n = L.weapon(h, "armmech_cannon")
	return w and (Spring.GetUnitWeaponState(unitID, n, "range") or w.range) or 665
end

---------------------------------------------------------------------------- a1 Tandem Strike

local function detonate(api, unitID, h, victimID, consume)
	local r = api.rank(h, "a1")
	if r <= 0 or not L.alive(victimID) then
		return
	end
	local stacks = api.marks(victimID, "breach")
	if stacks <= 0 then
		return
	end
	local dmg = api.val(b(h, "a1").perStack, r) * stacks * api.power(h)
	api.damage(victimID, dmg, unitID, { dtype = "rail" })
	if consume then
		api.mark(victimID, "breach", 0, { stacks = -stacks })
	end
	local fx = api.fx
	if fx then
		local x, y, z = api.pos(victimID)
		if x then
			fx.flash(x, y + 25, z, { radius = 60 + 20 * stacks, color = { 1, 0.85, 0.6, 1 }, ttl = 0.3 })
			fx.ring(x, z, { kind = "shock", r0 = 10, r1 = 140, color = "orange", ttl = 0.3, width = 18 })
		end
		if consume and h.store.breachFx[victimID] then
			fx.detach(h.store.breachFx[victimID])
			h.store.breachFx[victimID] = nil
		end
	end
	h.store.detonations = (h.store.detonations or 0) + 1
	api.log("armt4prowler a1 detonate rank=%d stacks=%d dmg=%d consume=%s", r, stacks, dmg, tostring(consume))
end

local function addBreach(api, unitID, h, victimID, n)
	local a1 = b(h, "a1")
	local r = api.rank(h, "a1")
	local maxS = api.val(a1.maxStacks, r)
	local stacks = api.mark(victimID, "breach", a1.stackTime or 6, { max = maxS, stacks = n or 1 })
	local fx = api.fx
	if fx then
		local f = api.frame()
		local rad = L.radius(victimID)
		local id = h.store.breachFx[victimID]
		if id then
			fx.set(id, { stacks = stacks, max = maxS })
		else
			h.store.breachFx[victimID] = fx.attach(victimID, "mark", { color = BREACH, radius = math.max(40, rad * 1.1), stacks = stacks, max = maxS, ttl = a1.stackTime or 6 })
		end
		if f - (h.store.breachRing[victimID] or 0) >= 10 then
			h.store.breachRing[victimID] = f
			local x, _, z = api.pos(victimID)
			fx.ring(x, z, { kind = "rune", r0 = rad * 0.8, r1 = rad * 1.1 + 10, color = BREACH, ttl = 0.3, width = 12 })
		end
	end
	return stacks
end

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	if isParalyzer then
		return damage
	end
	local key = L.weaponKey(h, weaponDefID)
	local apex = h.store.apex
	if apex and apex.prey == victimID and (key == "armmech_cannon" or key == "armamph_missile") then
		damage = damage * (1 + apex.damage)
	end
	if api.rank(h, "a1") > 0 then
		if key == "armmech_cannon" then
			addBreach(api, unitID, h, victimID, 1)
		elseif key == "armamph_missile" then
			local consume = not (apex and apex.prey == victimID)
			L.after(h, 1, function() detonate(api, unitID, h, victimID, consume) end)
		end
	end
	return damage
end

---------------------------------------------------------------------------- a2 Harpoon

local function harpoon(api, unitID, h, r, targetID)
	if not targetID or not L.alive(targetID) or Spring.GetUnitAllyTeam(targetID) == h.ally then
		return false
	end
	local a2 = b(h, "a2")
	if L.unitDist(unitID, targetID) > api.val(a2.range, r) * 1.1 then
		return false
	end
	local hx, hy, hz = api.pos(unitID)
	local tx, ty, tz = api.pos(targetID)
	local dmg = api.val(a2.dmg, r) * api.power(h)
	api.damage(targetID, dmg, unitID, { dtype = "rail" })
	local stacks = 0
	if api.rank(h, "a1") > 0 then
		stacks = addBreach(api, unitID, h, targetID, 99)
	end
	local isHero = api.isHero(targetID)
	local ud = UnitDefs[Spring.GetUnitDefID(targetID) or -1]
	local pulled = false
	local pullTime = a2.pullTime or 0.6
	if not isHero and ud and (ud.mass or 0) <= (UnitDefs[Spring.GetUnitDefID(unitID)].mass or 0) and not L.isStructure(targetID) then
		local d = L.dist(hx, hz, tx, tz) - L.radius(unitID) - L.radius(targetID) - 20
		pulled = d > 30 and api.pull(targetID, hx, hz, d, pullTime) or false
	end
	local root = isHero and (a2.heroRoot or 1.5) or api.val(a2.root, r)
	L.after(h, pulled and pullTime * 30 or 1, function()
		if L.alive(targetID) then
			api.mark(targetID, "harpoon", root, { root = true, from = unitID })
			local f2 = api.fx
			if f2 then
				local x, _, z = api.pos(targetID)
				f2.ring(x, z, { kind = "shock", r0 = 10, r1 = 120, color = CABLE, ttl = 0.35, width = 18 })
			end
		end
	end)
	local fx = api.fx
	if fx then
		fx.attach(unitID, "link", { target = targetID, style = "beam", color = CABLE, width = 3, ttl = pulled and pullTime + 0.1 or 0.3 })
		fx.flash(tx, ty + 25, tz, { radius = 50, color = CABLE, ttl = 0.3 })
	end
	api.log("armt4prowler a2 harpoon rank=%d dmg=%d stacks=%d pulled=%s hero=%s root=%.1f", r, dmg, stacks, tostring(pulled), tostring(isHero), root)
	return true
end

---------------------------------------------------------------------------- a3 Riptide Fog

local function fog(api, unitID, h, r, x, z)
	local a3 = b(h, "a3")
	local hx, _, hz = api.pos(unitID)
	if L.dist(hx, hz, x, z) > (a3.range or 800) * 1.1 then
		local d = L.dist(hx, hz, x, z)
		x, z = hx + (x - hx) / d * a3.range, hz + (z - hz) / d * a3.range
	end
	local radius = api.val(a3.radius, r)
	local dur = api.val(a3.duration, r)
	local f = api.frame()
	local st = { x = x, z = z, radius = radius, untilFrame = f + math.floor(dur * 30), next = f, cloaked = {} }
	local fx = api.fx
	if fx then
		st.zone = fx.zone(x, z, { radius = radius, pattern = "fog", color = FOG, ttl = dur })
		fx.ring(x, z, { kind = "fog", r0 = radius * 0.3, r1 = radius, color = FOG, ttl = 1.2, width = 60 })
	end
	h.store.fog = st
	api.active(unitID, "a3", dur)
	api.log("armt4prowler a3 fog rank=%d radius=%d dur=%.1f", r, radius, dur)
	return true
end

local function setHeroCloak(api, unitID, h, on)
	if (h.store.fogCloak or false) == on then
		return
	end
	h.store.fogCloak = on
	api.losCloak(unitID, on)
	local fx = api.fx
	if fx then
		if on then
			h.store.fogCloakFx = fx.attach(unitID, "cloak", { color = "cloak" })
		elseif h.store.fogCloakFx then
			fx.detach(h.store.fogCloakFx)
			h.store.fogCloakFx = nil
		end
	end
end

local function fogFrame(api, unitID, h, f)
	local st = h.store.fog
	if f >= st.untilFrame then
		h.store.fog = nil
		setHeroCloak(api, unitID, h, false)
		return
	end
	if f < st.next then
		return
	end
	st.next = f + 15
	local a3 = b(h, "a3")
	local fx = api.fx
	local n = 0
	for _, uid in ipairs(api.alliesIn(st.x, st.z, st.radius, h.ally)) do
		if uid ~= unitID and not api.isHero(uid) and L.isMobile(uid) then
			api.unitBuff(uid, "riptide", 0.8, { cloak = true })
			if fx and not st.cloaked[uid] and n < 20 then
				st.cloaked[uid] = fx.attach(uid, "cloak", { color = "cloak", ttl = (st.untilFrame - f) / 30 })
				n = n + 1
			end
		end
	end
	for _, uid in ipairs(api.enemiesIn(st.x, st.z, st.radius, h.ally)) do
		api.slow(uid, a3.slow or 0.3, 0.8)
	end
	local x, _, z = api.pos(unitID)
	local inside = L.dist(x, z, st.x, st.z) <= st.radius
	if inside then
		api.buff(unitID, h, "fog", 0.8, { speed = a3.speed or 0.3 })
	end
	setHeroCloak(api, unitID, h, inside and f - (h.store.lastFired or -999) > 30)
end

function M.fired(api, unitID, h, weaponNum)
	h.store.lastFired = api.frame()
	if h.store.fogCloak then
		setHeroCloak(api, unitID, h, false)
	end
end

---------------------------------------------------------------------------- ult Apex Predator

local function apexOn(api, unitID, h, r, targetID)
	if not targetID or not L.alive(targetID) or Spring.GetUnitAllyTeam(targetID) == h.ally then
		return false
	end
	local ult = b(h, "ult")
	if L.unitDist(unitID, targetID) > (ult.range or 1400) * 1.1 then
		return false
	end
	local dur = api.val(ult.duration, r)
	local st = { prey = targetID, r = r, untilFrame = api.frame() + math.floor(dur * 30), damage = api.val(ult.damage, r) }
	api.mark(targetID, "apex", dur, { reveal = true, from = unitID })
	api.forceTarget(unitID, targetID, dur) -- the hunt: its guns stay on the prey ...
	Spring.GiveOrderToUnit(unitID, CMD.ATTACK, { targetID }, 0) -- ... and it closes in
	api.buff(unitID, h, "apex", dur, { speed = api.val(ult.speed, r) })
	api.active(unitID, "ult", dur)
	local fx = api.fx
	if fx then
		local x, _, z = api.pos(targetID)
		st.fx = {
			fx.attach(targetID, "aura", { pattern = "runes", color = PREY, radius = math.max(60, L.radius(targetID) * 1.5), ttl = dur }),
			fx.attach(unitID, "link", { target = targetID, style = "beam", color = { 1, 0.3, 0.2, 0.3 }, width = 2, ttl = dur }),
			fx.attach(unitID, "trail", { color = { 1, 0.25, 0.15, 1 }, width = 14, length = 0.5, ttl = dur }),
			fx.attach(targetID, "mark", { color = PREY, radius = math.max(50, L.radius(targetID) * 1.3), ttl = dur }),
		}
		fx.pillar(x, z, { radius = 40, height = 600, color = { 1, 0.25, 0.15, 0.9 }, ttl = 1 })
	end
	h.store.apex = st
	api.log("armt4prowler ult apex rank=%d prey=%s dur=%d damage=+%.2f", r, UnitDefs[Spring.GetUnitDefID(targetID)].name, dur, st.damage)
	return true
end

local function apexOff(api, unitID, h)
	local st = h.store.apex
	if not st then
		return
	end
	h.store.apex = nil
	api.unbuff(unitID, h, "apex")
	L.detach(api, st.fx)
end

function M.unitDied(api, unitID, h, deadID, deadDefID, x, z, allied)
	local st = h.store.apex
	if st and st.prey == deadID then
		local _, maxHp = Spring.GetUnitHealth(unitID)
		local healed = api.heal(unitID, (maxHp or 0) * (h.hpMult or 1) * 0.25)
		local f = api.frame()
		local left = math.max(0, ((h.ready and h.ready.ult or f) - f) / 30)
		api.cooldown(unitID, h, "ult", left / 2 / math.max(0.4, 1 - (h.mods and h.mods.cdr or 0)))
		local fx = api.fx
		if fx then
			local hx, _, hz = api.pos(unitID)
			fx.pillar(hx, hz, { radius = 60, height = 500, color = "heal", ttl = 0.8 })
			fx.flash(x, L.gy(x, z) + 30, z, { radius = 120, color = PREY, ttl = 0.4 })
		end
		api.log("armt4prowler ult prey killed: healed=%d cooldown left %.1f -> %.1f s", healed, left, left / 2)
		apexOff(api, unitID, h)
	end
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.breachFx = {}
	h.store.breachRing = {}
	h.store.fog, h.store.apex, h.store.fogCloak = nil, nil, nil
end

function M.frame(api, unitID, h, f)
	L.tick(h, f)
	if h.store.fog then
		fogFrame(api, unitID, h, f)
	end
	local st = h.store.apex
	if st and (f >= st.untilFrame or not L.alive(st.prey)) then
		apexOff(api, unitID, h)
	end
	if f % 90 == 0 then
		for uid in pairs(h.store.breachFx) do
			if api.marks(uid, "breach") == 0 then
				h.store.breachFx[uid] = nil
				h.store.breachRing[uid] = nil
			end
		end
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a2" then
		return harpoon(api, unitID, h, rank, targetID)
	elseif key == "a3" then
		if not x and targetID then
			x, y, z = api.pos(targetID)
		end
		if not x then
			x, y, z = api.pos(unitID)
		end
		return fog(api, unitID, h, rank, x, z)
	elseif key == "ult" then
		if h.store.apex then
			return false
		end
		return apexOn(api, unitID, h, rank, targetID)
	end
	return false
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	local hp = L.hpFrac(unitID)
	if key == "a2" then
		local range = L.v(api, h, "a2", "range", rank)
		local gun = gunRange(api, unitID, h)
		local best, bestC
		for _, uid in ipairs(L.seenEnemies(api, x, z, range, h.ally)) do
			local d = L.unitDist(unitID, uid)
			local c = api.cost(uid)
			local hero = api.isHero(uid)
			if (hero and (d > gun or L.hpFrac(uid) < 0.4)) or (c >= 5000 and d > gun) then
				c = hero and c * 3 or c
				if not bestC or c > bestC then
					best, bestC = uid, c
				end
			end
		end
		if best then
			local tx, ty, tz = api.pos(best)
			return tx, ty, tz, best
		end
	elseif key == "a3" then
		local _, near = api.enemyCostNear(x, z, 900, h.ally)
		if hp < 0.45 and near > 0 then
			return x, y, z
		end
		local allies = 0
		for _, uid in ipairs(api.alliesIn(x, z, 500, h.ally)) do
			if L.isMobile(uid) then
				allies = allies + 1
			end
		end
		local _, enemies = api.enemyCostNear(x, z, 1100, h.ally)
		if allies >= 5 and enemies >= 3 then
			return x, y, z
		end
	elseif key == "ult" then
		local hero = L.enemyHero(api, x, z, b(h, "ult").range or 1400, h.ally)
		if hero and L.hpFrac(hero) <= 0.6 then
			local tx, ty, tz = api.pos(hero)
			return tx, ty, tz, hero
		end
		local t, c = api.mostValuableEnemy(x, z, b(h, "ult").range or 1400, h.ally)
		if t and c >= 20000 then
			local tx, ty, tz = api.pos(t)
			return tx, ty, tz, t
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	apexOff(api, unitID, h)
	h.store.fog = nil
end

return M
