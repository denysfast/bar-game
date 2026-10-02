-- Cataphract, the Lancer (cort4cataphract, corsok x2, hover) - doc/v19-heroes/roster_cor.md section 9.
--   a1 Lance Charge (active, map): boosts 800..1300 (+30% over water) at 4x speed; enemies on the path take damage
--      and are knocked aside 150; the next disruptor bolt fires at once with +30..80%.
--   a2 Disruption (passive): each bolt hit adds a Disruption stack (max 3..6, 4 s, -8% speed each); at max the target
--      is EMP-stunned 1..2.5 s (heroes half) and the stacks reset.
--   a3 Phase Decoy (active, self): a hologram (15..40% of its HP, 6 s) taunts the enemies within 800 and explodes on
--      death or expiry; the Cataphract cloaks 2 s and gets +50% speed for 4 s.
--   ult Lancer's Gauntlet (active, enemy in 900): 3..7 chained lance dashes (0.4 s each) through the most valuable
--      enemies around, each hit + max Disruption; untargetable meanwhile, it ends at the last target.

local L = VFS.Include("luarules/heroes/cort4_lib.lua")
local M = {}

local floor, max, min, sqrt, random, cos, sin = math.floor, math.max, math.min, math.sqrt, math.random, math.cos, math.sin

local EMP = { 0.45, 0.85, 1, 1 }
local LANCE = { 1, 0.82, 0.5, 1 }

local function b(h, key)
	return h.def.cfg[key]
end

local function boltNum(h)
	return h.def.keyNum.corsok_laser and h.def.keyNum.corsok_laser[1]
end

---------------------------------------------------------------------------- a2 Disruption

local function disruptMax(api, unitID, h, uid, stunMult)
	local a2 = b(h, "a2")
	local r = max(1, api.rank(h, "a2"))
	api.mark(uid, "disrupt", 0.1, { stacks = -api.marks(uid, "disrupt") })
	api.stun(uid, api.val(a2.stun, r) * (stunMult or 1), unitID)
	local x, y, z = api.pos(uid)
	for k = 1, 3 do
		local a = k * 2.094 + random()
		local rr = L.radius(uid) + 40
		L.bolt(api, x + cos(a) * rr, y + 60, z + sin(a) * rr, x, y + 20, z, { color = EMP, width = 3, ttl = 0.3 })
	end
	L.flash(api, x, y + 25, z, { radius = 100, color = EMP, ttl = 0.35 })
	h.store.disruptStuns = (h.store.disruptStuns or 0) + 1
end

local function disrupt(api, unitID, h, uid)
	local r = api.rank(h, "a2")
	if r <= 0 or not L.alive(uid) then
		return
	end
	local a2 = b(h, "a2")
	local maxS = api.val(a2.max, r)
	local s = api.mark(uid, "disrupt", a2.time or 4, { max = maxS })
	api.slow(uid, (a2.slow or 0.08) * s, a2.time or 4)
	local x, _, z = api.pos(uid)
	L.ring(api, x, z, { kind = "electric", r0 = 40 + 10 * s, r1 = 40 + 10 * s + 8, width = 12, ttl = 0.7, color = L.AMBER })
	if s >= maxS then
		disruptMax(api, unitID, h, uid)
		L.log(api, h, "a2 disruption max=%d -> stun %.1f", maxS, api.val(a2.stun, r))
	end
end

---------------------------------------------------------------------------- a1 Lance Charge

local function lanceCharge(api, unitID, h, r, x, z)
	local a1 = b(h, "a1")
	if not x then
		return false
	end
	local hx, hy, hz = api.pos(unitID)
	local range = api.val(a1.land, r)
	if Spring.GetGroundHeight(x, z) < 0 then
		range = range * 1.3
	end
	local tx, tz = L.toward(hx, hz, x, z, range)
	local dist = sqrt(L.d2(tx, tz, hx, hz))
	if dist < 100 then
		return false
	end
	local speed = max(4 * (h.moveSpeed or h.def.speed or 64), 700)
	local dmg = api.val(a1.dmg, r) * api.power(h)
	local hit, n, steps = {}, 0, 0
	local trail = L.attach(api, unitID, "trail", { color = L.AMBER, width = 90, length = 0.5, ttl = dist / speed + 0.4 })
	local ok = api.dash(unitID, h, tx, tz, { speed = speed, onStep = function(px, pz)
		steps = steps + 1
		local dx, dz = tx - px, tz - pz
		local d = max(1, sqrt(dx * dx + dz * dz))
		local bx, bz = px + dx / d * 70, pz + dz / d * 70
		if steps % 3 == 0 then
			L.ring(api, bx, bz, { kind = "shock", r0 = 60, r1 = 150, width = 18, ttl = 0.25, color = L.col(L.AMBER, 0.8) })
		end
		for _, uid in ipairs(api.enemiesIn(bx, bz, 140, h.ally)) do
			if not hit[uid] then
				hit[uid] = true
				n = n + 1
				api.damage(uid, dmg, unitID, { dtype = "laser" })
				api.push(uid, px, pz, a1.knock or 150, 0.3)
				local ux, uy, uz = api.pos(uid)
				L.flash(api, ux, uy + 25, uz, { radius = 120, color = LANCE, ttl = 0.3 })
			end
		end
	end, onLand = function()
		L.detach(api, trail)
		api.reloadNow(unitID, "corsok_laser")
		h.store.lance = { untilF = api.frame() + 120, bonus = api.val(a1.bolt, r) }
		L.log(api, h, "a1 lance charge rank=%d dist=%d dmg=%d hit=%d", r, dist, dmg, n)
	end })
	if not ok then
		L.detach(api, trail)
	end
	return ok
end

---------------------------------------------------------------------------- a3 Phase Decoy

local function decoyBoom(api, unitID, h, x, z)
	local d = h.store.decoy
	if not d or d.done then
		return
	end
	d.done = true
	L.detach(api, d.fx)
	local hits = api.area(x, z, d.aoe, d.dmg, unitID, { dtype = "plasma", ally = h.ally })
	local gy = L.gy(x, z)
	L.flash(api, x, gy + 40, z, { radius = 250, color = { 1, 0.85, 0.6, 1 }, ttl = 0.45 })
	L.ring(api, x, z, { kind = "shock", r0 = 40, r1 = d.aoe, width = 40, ttl = 0.4, color = L.AMBER })
	L.ring(api, x, z, { kind = "hex", r0 = d.aoe, r1 = 40, width = 20, ttl = 0.4, color = L.col(L.AMBER, 0.6) })
	L.log(api, h, "a3 decoy exploded dmg=%d hit=%d taunted=%d", d.dmg, #hits, d.taunted)
end

local function phaseDecoy(api, unitID, h, r)
	local a3 = b(h, "a3")
	local life = a3.life or 6
	local x, y, z = api.pos(unitID)
	local ids = api.summon(unitID, h, "cort4cataphract_decoy", 1, { spread = 0, expire = life, fx = "blank" })
	local dec = ids[1]
	if not dec then
		return false
	end
	local _, yaw = Spring.GetUnitRotation(unitID)
	Spring.SetUnitPosition(dec, x, z)
	Spring.SetUnitRotation(dec, 0, yaw or 0, 0)
	local hp = api.val(a3.hp, r) * L.maxHp(api, unitID)
	Spring.SetUnitMaxHealth(dec, hp)
	Spring.SetUnitHealth(dec, hp)
	local fx = math.sin(yaw or 0)
	local fz = math.cos(yaw or 0)
	Spring.GiveOrderToUnit(dec, CMD.MOVE, { L.clampX(x + fx * 700), y, L.clampZ(z + fz * 700) }, 0)
	local taunted = 0
	for _, uid in ipairs(api.enemiesIn(x, z, a3.taunt or 800, h.ally)) do
		if api.taunt(uid, dec, life) then
			taunted = taunted + 1
		end
	end
	h.store.decoy = { id = dec, dmg = api.val(a3.dmg, r) * api.power(h), aoe = a3.aoe or 250, taunted = taunted,
		fx = L.attach(api, dec, "tint", { pattern = "rim", color = L.AMBER, strength = 1, ttl = life + 1 }) }
	api.buff(unitID, h, "phase", a3.cloak or 2, { cloak = true })
	api.buff(unitID, h, "phasespeed", a3.speedTime or 4, { speed = a3.speed or 0.5 })
	L.attach(api, unitID, "cloak", { color = "cloak", ttl = a3.cloak or 2 })
	L.flash(api, x, y + 40, z, { radius = 120, color = { 1, 0.9, 0.7, 1 }, ttl = 0.4 })
	L.ring(api, x, z, { kind = "hex", r0 = 60, r1 = 160, width = 20, ttl = 0.5, color = L.AMBER })
	api.active(unitID, "a3", life)
	L.log(api, h, "a3 phase decoy rank=%d hp=%d taunted=%d", r, hp, taunted)
	return true
end

---------------------------------------------------------------------------- ult Lancer's Gauntlet

local function gauntlet(api, unitID, h, r, targetID)
	local ult = b(h, "ult")
	local x, y, z = api.pos(unitID)
	if not (targetID and L.alive(targetID) and Spring.GetUnitAllyTeam(targetID) ~= h.ally) then
		targetID = L.mostValuable(api, h, x, z, ult.range or 900)
	end
	if not targetID then
		return false
	end
	local dashes = api.val(ult.dashes, r)
	local dmg = api.val(ult.dmg, r) * api.power(h)
	local hop = ult.hop or 0.4
	local done = {}
	local pts = { x, y + 40, z }
	local st = { n = 0, dealt = 0 }
	api.buff(unitID, h, "gauntlet", dashes * hop + 0.5, { unstoppable = true })
	local fx = L.attach(api, unitID, "trail", { color = LANCE, width = 70, length = 0.4, ttl = dashes * hop + 0.5 })
	local function finish(lx, lz)
		L.detach(api, fx)
		L.chain(api, pts, { color = L.col(L.AMBER, 0.5), width = 4, ttl = 0.6, delay = 0.03, flash = false })
		L.ring(api, lx, lz, { kind = "shock", r0 = 60, r1 = 600, width = 50, ttl = 0.5, color = L.AMBER })
		L.log(api, h, "ult gauntlet rank=%d dashes=%d/%d dmg=%d dealt=%d", r, st.n, dashes, dmg, st.dealt)
	end
	local function step(t)
		if not L.alive(unitID) then
			return
		end
		local cx, cy, cz = api.pos(unitID)
		if not (t and L.alive(t)) or st.n >= dashes then
			finish(cx, cz)
			return
		end
		done[t] = true
		local tx, ty, tz = api.pos(t)
		local dx, dz = tx - cx, tz - cz
		local d = max(1, sqrt(dx * dx + dz * dz))
		local stop = L.radius(t) + 50
		local ex, ez = tx - dx / d * stop, tz - dz / d * stop
		api.dash(unitID, h, ex, ez, { seconds = hop, untargetable = true, onLand = function(lx, lz)
			local ly = L.gy(lx, lz)
			L.bolt(api, cx, cy + 40, cz, lx, ly + 40, lz, { color = LANCE, width = 20, ttl = 0.3, branches = 2 })
			if L.alive(t) then
				local ux, uy, uz = api.pos(t)
				api.damage(t, dmg, unitID, { dtype = "laser" })
				st.dealt = st.dealt + dmg
				disruptMax(api, unitID, h, t)
				L.flash(api, ux, uy + 30, uz, { radius = 200, color = LANCE, ttl = 0.35 })
				pts[#pts + 1], pts[#pts + 2], pts[#pts + 3] = ux, uy + 30, uz
			end
			st.n = st.n + 1
			local nxt = L.mostValuable(api, h, lx, lz, ult.range or 900, done)
			step(nxt)
		end })
	end
	step(targetID)
	return true
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.decoy = nil
	h.store.lance = nil
end

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	if isParalyzer or damage <= 0 then
		return damage
	end
	local n = boltNum(h)
	if not (n and h.def.weapons[n].wdid == weaponDefID) then
		return damage
	end
	local ln = h.store.lance
	if ln then
		h.store.lance = nil
		if api.frame() <= ln.untilF then
			damage = damage * (1 + ln.bonus)
			local x, y, z = api.pos(victimID)
			L.flash(api, x, y + 30, z, { radius = 140, color = LANCE, ttl = 0.3 })
			L.log(api, h, "a1 charged bolt +%.2f -> %d", ln.bonus, damage)
		end
	end
	disrupt(api, unitID, h, victimID)
	return damage
end

function M.frame(api, unitID, h, f)
	L.tick(api, unitID, h, f)
	local d = h.store.decoy
	if d and not d.done then
		if L.alive(d.id) then
			d.x, _, d.z = api.pos(d.id)
		elseif d.x then
			decoyBoom(api, unitID, h, d.x, d.z)
		end
	end
end

function M.unitDied(api, unitID, h, deadID, deadDefID, x, z)
	local d = h.store.decoy
	if d and d.id == deadID and not d.done then
		decoyBoom(api, unitID, h, x, z)
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a1" then
		return lanceCharge(api, unitID, h, rank, x, z)
	elseif key == "a3" then
		return phaseDecoy(api, unitID, h, rank)
	elseif key == "ult" then
		return gauntlet(api, unitID, h, rank, targetID)
	end
	return false
end

local function backline(uid)
	local ud = UnitDefs[Spring.GetUnitDefID(uid) or -1]
	if not ud or (ud.speed or 0) <= 0 then
		return false
	end
	if ud.isBuilder then
		return true
	end
	for _, w in ipairs(ud.weapons or {}) do
		local wd = WeaponDefs[w.weaponDef]
		if wd and (wd.range > 1100 or (w.onlyTargets and w.onlyTargets.vtol and not w.onlyTargets.surface)) then
			return true
		end
	end
	return false
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	local hpf = L.hpFrac(unitID)
	local f = api.frame()
	if key == "a1" then
		local a1 = b(h, "a1")
		local range = api.val(a1.land, rank)
		if hpf < 0.35 then
			local ex, ez = L.escapePoint(api, h, unitID, range)
			if ex then
				return ex, L.gy(ex, ez), ez
			end
			return nil
		end
		local best, bestC
		for _, uid in ipairs(L.enemies(api, h, x, z, range)) do
			local ux, _, uz = api.pos(uid)
			if L.d2(ux, uz, x, z) >= 600 * 600 then
				local c = 0
				if api.isHero(uid) and L.hpFrac(uid) < 0.5 then
					c = api.cost(uid) * 3
				elseif backline(uid) then
					c = api.cost(uid)
				end
				if c > 0 and (not bestC or c > bestC) then
					best, bestC = uid, c
				end
			end
		end
		if best then
			local tx, ty, tz = api.pos(best)
			return tx, ty, tz
		end
	elseif key == "a3" then
		if h.store.decoy and not h.store.decoy.done then
			return nil
		end
		local n = 0
		for _, t in pairs(h.attackers or {}) do
			if f - t < 90 then
				n = n + 1
			end
		end
		if hpf < 0.5 and n >= 3 then
			return x, y, z
		end
	elseif key == "ult" then
		local R = b(h, "ult").range or 900
		local hero = L.enemyHero(api, h, x, z, R, 0.5)
		local cost, n = api.enemyCostNear(x, z, R, h.ally)
		local t = hero or (n >= 3 and cost >= 10000 and L.mostValuable(api, h, x, z, R)) or nil
		if t then
			local tx, ty, tz = api.pos(t)
			return tx, ty, tz, t
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	local d = h.store.decoy
	if d then
		L.detach(api, d.fx)
	end
end

return M
