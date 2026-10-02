-- Commando, the Ghost (cort4commando, cormandot4 x2.6) - doc/v19-heroes/roster_cor.md section 6.
--   a1 Ghost Protocol (passive): cloaks (engine cloak, decloak distance 50) after 5..2.5 s without firing or being hit,
--      +10..30% speed while cloaked. The first shot from cloak is an Ambush: +50..150% damage and a 0.5..2 s stun.
--   a2 Disruptor Mines (active, map in 700): 3..8 hidden mines (allies see them; max 16, 60 s); an enemy within 120
--      sets one off: damage in 180 + EMP 1.5..3 s.
--   a3 Shadowstep (active, enemy in 700..1100): blinks behind the target and disintegrates it point-blank; it is
--      Marked for 5 s (+10..25% damage from the Commando). From cloak it is an Ambush.
--   ult Blackout (active, map in 1500): EMP storm in 600..900: damage, 3..6 s stun, enemy shields drained; the enemies
--      lose sight of the Commando for the stun + 3 s, and it deals +50% to stunned targets.

local L = VFS.Include("luarules/heroes/cort4_lib.lua")
local M = {}

local floor, max, min, sqrt, random, cos, sin = math.floor, math.max, math.min, math.sqrt, math.random, math.cos, math.sin

local EMP = { 0.45, 0.85, 1, 1 }
local EMP_WHITE = { 0.8, 0.95, 1, 1 }

local function b(h, key)
	return h.def.cfg[key]
end

---------------------------------------------------------------------------- a1 Ghost Protocol

local function uncloak(api, unitID, h, f, why)
	local st = h.store
	if st.cloaked then
		L.log(api, h, "a1 decloak (%s)", why or "?")
		st.cloaked = false
		Spring.SetUnitCloak(unitID, false)
		api.unbuff(unitID, h, "ghost")
		L.detachAll(api, st.cloakFx)
		local x, y, z = api.pos(unitID)
		L.flash(api, x, y + 60, z, { radius = 90, color = L.col(EMP, 0.7), ttl = 0.3, ground = false })
	end
	st.lastAct = f
end

local function cloak(api, unitID, h, r, f)
	local a1 = b(h, "a1")
	local st = h.store
	st.cloaked = true
	st.cloakAt = f
	st.engineCloaked = false
	Spring.SetUnitCloak(unitID, true, a1.decloak or 50)
	api.buff(unitID, h, "ghost", nil, { speed = api.val(a1.speed, r) })
	st.cloakFx = {
		L.attach(api, unitID, "cloak", { color = "cloak" }),
		L.attach(api, unitID, "tint", { pattern = "shadow", strength = 0.5, visible = "ally" }),
	}
	L.log(api, h, "a1 cloaked rank=%d speed=+%.2f", r, api.val(a1.speed, r))
end

local function ghostFrame(api, unitID, h, f)
	local r = api.rank(h, "a1")
	if r <= 0 then
		return
	end
	local st = h.store
	if st.cloaked then
		-- the engine cloaks at its next slow update (the cloak gadget may hold it back a few seconds after a shot);
		-- once cloaked, an engine decloak means it fired (or an enemy came within 50): that shot is the Ambush
		local isC = Spring.GetUnitIsCloaked(unitID)
		if isC then
			st.engineCloaked = true
		elseif st.engineCloaked then
			st.ambush = f + 60
			uncloak(api, unitID, h, f, "engine")
		end
	elseif f - (st.lastAct or 0) >= api.val(b(h, "a1").delay, r) * 30 and not Spring.GetUnitIsStunned(unitID) then
		cloak(api, unitID, h, r, f)
	end
end

local function ambushHit(api, unitID, h, victimID, damage)
	local a1 = b(h, "a1")
	local r = max(1, api.rank(h, "a1"))
	local d = damage * (1 + api.val(a1.ambush, r))
	api.stun(victimID, api.val(a1.stun, r), unitID)
	local x, y, z = api.pos(victimID)
	L.flash(api, x, y + 30, z, { radius = 120, color = EMP, ttl = 0.35 })
	L.ring(api, x, z, { kind = "electric", r0 = 40, r1 = 160, width = 22, ttl = 0.3, color = EMP })
	L.log(api, h, "a1 ambush rank=%d dmg %d -> %d stun=%.1f", r, damage, d, api.val(a1.stun, r))
	return d
end

---------------------------------------------------------------------------- a2 Disruptor Mines

local function mineBoom(api, unitID, h, m)
	local a2 = b(h, "a2")
	local r = max(1, api.rank(h, "a2"))
	L.detach(api, m.fx)
	local dmg = api.val(a2.dmg, r) * api.power(h)
	local emp = api.val(a2.emp, r)
	local hits = api.area(m.x, m.z, a2.aoe or 180, dmg, unitID, { dtype = "emp", ally = h.ally })
	for _, uid in ipairs(hits) do
		api.stun(uid, emp, unitID)
	end
	local gy = L.gy(m.x, m.z)
	L.flash(api, m.x, gy + 20, m.z, { radius = 180, color = EMP, ttl = 0.4 })
	L.ring(api, m.x, m.z, { kind = "electric", r0 = 40, r1 = 180, width = 30, ttl = 0.4, color = EMP })
	for k = 1, 4 do
		local t = hits[k]
		local tx, ty, tz
		if t then
			tx, ty, tz = api.pos(t)
			ty = ty + 20
		else
			local a = random() * 6.283
			tx, tz = m.x + cos(a) * 150, m.z + sin(a) * 150
			ty = L.gy(tx, tz) + 5
		end
		L.bolt(api, m.x, gy + 15, m.z, tx, ty, tz, { color = EMP, width = 3, ttl = 0.3 })
	end
	L.log(api, h, "a2 mine dmg=%d emp=%.1f hit=%d", dmg, emp, #hits)
end

local function mines(api, unitID, h, r, x, z)
	local a2 = b(h, "a2")
	if not x then
		return false
	end
	local hx, hy, hz = api.pos(unitID)
	x, z = L.toward(hx, hz, x, z, a2.range or 700)
	local f = api.frame()
	local list = h.store.mines
	local count = api.val(a2.count, r)
	for k = 1, count do
		local a = k / count * 6.283 + random() * 0.6
		local d = (a2.spread or 200) * sqrt(random() * 0.8 + 0.2)
		local mx, mz = L.clampX(x + cos(a) * d), L.clampZ(z + sin(a) * d)
		local m = { x = mx, z = mz, untilF = f + floor((a2.life or 60) * 30) }
		m.fx = L.ring(api, mx, mz, { kind = "hex", r0 = 50, r1 = 50, width = 8, ttl = a2.life or 60, color = { 0.45, 0.85, 1, 0.3 },
			rot = 0.5, visible = "ally", ally = h.ally })
		list[#list + 1] = m
		L.bolt(api, hx, hy + 80, hz, mx, L.gy(mx, mz) + 5, mz, { color = L.col(EMP, 0.6), width = 1.5, ttl = 0.2, branches = 0,
			visible = "ally", ally = h.ally })
	end
	while #list > (a2.max or 16) do
		local old = table.remove(list, 1)
		L.detach(api, old.fx)
	end
	L.log(api, h, "a2 mines rank=%d placed=%d active=%d", r, count, #list)
	return true
end

local function minesFrame(api, unitID, h, f)
	local list = h.store.mines
	if #list == 0 or f % 6 ~= 0 then
		return
	end
	local a2 = b(h, "a2")
	local keep = {}
	for _, m in ipairs(list) do
		if m.untilF <= f then
			L.detach(api, m.fx)
		else
			local trig = false
			for _, uid in ipairs(api.enemiesIn(m.x, m.z, a2.trigger or 120, h.ally)) do
				if not L.isAir(uid) then
					trig = true
					break
				end
			end
			if trig then
				mineBoom(api, unitID, h, m)
			else
				keep[#keep + 1] = m
			end
		end
	end
	h.store.mines = keep
end

---------------------------------------------------------------------------- a3 Shadowstep

local function mark(api, h, uid, frac, seconds)
	local st = h.store
	local f = api.frame()
	local old = st.marked[uid]
	if old then
		L.detach(api, old.fx)
	end
	st.marked[uid] = { untilF = f + floor(seconds * 30), frac = frac,
		fx = L.attach(api, uid, "mark", { color = EMP, radius = 70 + L.radius(uid) * 0.5, stacks = 1, max = 1, ttl = seconds }) }
end

local function shadowstep(api, unitID, h, r, targetID)
	local a3 = b(h, "a3")
	if not (targetID and L.alive(targetID)) or Spring.GetUnitAllyTeam(targetID) == h.ally then
		return false
	end
	local f = api.frame()
	local x0, y0, z0 = api.pos(unitID)
	local tx, ty, tz = api.pos(targetID)
	local dx, dz = tx - x0, tz - z0
	local d = max(1, sqrt(dx * dx + dz * dz))
	local back = L.radius(targetID) + 90
	local bx, bz = L.clampX(tx + dx / d * back), L.clampZ(tz + dz / d * back)
	local fromCloak = h.store.cloaked
	if not api.blink(unitID, bx, bz) then
		return false
	end
	local x1, y1, z1 = api.pos(unitID)
	Spring.SetUnitRotation(unitID, 0, math.atan2(tx - x1, tz - z1), 0)
	L.bolt(api, x0, y0 + 70, z0, x1, y1 + 70, z1, { color = EMP, width = 6, ttl = 0.18, branches = 0, jitter = 0.05 })
	L.flash(api, x0, y0 + 50, z0, { radius = 120, color = EMP, ttl = 0.35 })
	L.flash(api, x1, y1 + 50, z1, { radius = 120, color = EMP, ttl = 0.35 })
	L.ring(api, x1, z1, { kind = "electric", r0 = 60, r1 = 200, width = 26, ttl = 0.4, color = EMP })
	local dmg = api.val(a3.dmg, r) * api.power(h)
	if fromCloak then
		dmg = ambushHit(api, unitID, h, targetID, dmg)
	end
	uncloak(api, unitID, h, f)
	local mx, my, mz = api.piecePos(unitID, "flare")
	L.beam(api, mx, my, mz, tx, ty + 30, tz, { color = EMP_WHITE, width = 12, ttl = 0.22, flare = 1.5, pulse = 3 })
	L.flash(api, tx, ty + 30, tz, { radius = 150, color = EMP_WHITE, ttl = 0.3 })
	api.damage(targetID, dmg, unitID, { dtype = "plasma" })
	mark(api, h, targetID, api.val(a3.mark, r), a3.markTime or 5)
	api.forceTarget(unitID, targetID, 3)
	L.log(api, h, "a3 shadowstep rank=%d dmg=%d ambush=%s mark=+%.2f", r, dmg, tostring(fromCloak), api.val(a3.mark, r))
	return true
end

---------------------------------------------------------------------------- ult Blackout

local function blackout(api, unitID, h, r, x, z)
	local ult = b(h, "ult")
	if not x then
		return false
	end
	local hx, _, hz = api.pos(unitID)
	x, z = L.toward(hx, hz, x, z, ult.range or 1500)
	local R = api.val(ult.radius, r)
	local dmg = api.val(ult.dmg, r) * api.power(h)
	local stun = api.val(ult.stun, r)
	local hits = api.area(x, z, R, dmg, unitID, { dtype = "emp" })
	local drained = 0
	local stunned = {}
	for _, uid in ipairs(hits) do
		api.stun(uid, stun, unitID)
		drained = drained + (api.shieldDrain(uid) or 0)
		stunned[#stunned + 1] = uid
		if #stunned <= 20 then
			L.attach(api, uid, "electric", { color = EMP, intensity = 0.6, ttl = api.isHero(uid) and stun * 0.5 or stun })
		end
	end
	local f = api.frame()
	h.store.blackoutUntil = f + floor((stun + 3) * 30)
	api.losCloak(unitID, true)
	h.store.losHidden = true
	api.delay(floor((stun + 3) * 30), function()
		if L.alive(unitID) and h.store.losHidden then
			h.store.losHidden = false
			api.losCloak(unitID, false)
		end
	end)
	local gy = L.gy(x, z)
	L.ring(api, x, z, { kind = "electric", r0 = 100, r1 = R, width = 50, ttl = 0.6, color = L.col(EMP, 0.9) })
	L.ring(api, x, z, { kind = "shock", r0 = 60, r1 = R * 1.05, width = 70, ttl = 0.5, color = L.col(EMP_WHITE, 0.8) })
	L.zone(api, x, z, { radius = R, pattern = "electric", color = L.col(EMP, 0.5), ttl = stun })
	L.flash(api, x, gy + 60, z, { radius = R, color = EMP_WHITE, ttl = 0.4 })
	for k = 0, floor(stun / 0.5) - 1 do
		api.delay(k * 15 + 3, function()
			local n = 0
			for _, uid in ipairs(stunned) do
				if n >= 12 then
					break
				end
				if L.alive(uid) and Spring.GetUnitIsStunned(uid) then
					n = n + 1
					local ux, uy, uz = api.pos(uid)
					L.bolt(api, ux + (random() - 0.5) * 200, uy + 600, uz + (random() - 0.5) * 200, ux, uy + 20, uz,
						{ color = EMP, width = 4, ttl = 0.25 })
				end
			end
		end)
	end
	h.store.followUp = L.enemyHero(api, h, x, z, R)
	api.active(unitID, "ult", stun + 3)
	L.log(api, h, "ult blackout rank=%d radius=%d dmg=%d stun=%.1f hit=%d shieldsDrained=%d", r, R, dmg, stun, #hits, drained)
	return true
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.lastAct = api.frame()
	h.store.cloaked = false
	h.store.mines = h.store.mines or {}
	h.store.marked = {}
end

function M.frame(api, unitID, h, f)
	L.tick(api, unitID, h, f)
	ghostFrame(api, unitID, h, f)
	minesFrame(api, unitID, h, f)
	if f % 30 == 0 then
		for uid, m in pairs(h.store.marked) do
			if m.untilF <= f or not L.alive(uid) then
				h.store.marked[uid] = nil
			end
		end
	end
end

function M.fired(api, unitID, h, weaponNum)
	local f = api.frame()
	if h.store.cloaked then
		h.store.ambush = f + 60
	end
	uncloak(api, unitID, h, f, "fired")
end

function M.damaged(api, unitID, h, damage, attackerID, weaponDefID, isParalyzer)
	if damage > 0 then
		uncloak(api, unitID, h, api.frame(), "hit")
	end
	return damage
end

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	if isParalyzer or damage <= 0 then
		return damage
	end
	-- the Disintegrator slug passes through: one hit per victim per shot
	local gun = h.def.keyNum.commando_back_cannon and h.def.keyNum.commando_back_cannon[1]
	if gun and h.def.weapons[gun].wdid == weaponDefID then
		damage = L.slugHit(api, h, victimID, weaponDefID, damage, gun, 12)
		if damage <= 0 then
			return 0
		end
	end
	local f = api.frame()
	if h.store.ambush and f <= h.store.ambush then
		h.store.ambush = nil
		damage = ambushHit(api, unitID, h, victimID, damage)
	end
	local m = h.store.marked[victimID]
	if m and m.untilF > f then
		damage = damage * (1 + m.frac)
	end
	if h.store.blackoutUntil and f < h.store.blackoutUntil and Spring.GetUnitIsStunned(victimID) then
		damage = damage * (1 + (b(h, "ult").bonus or 0.5))
	end
	return damage
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a2" then
		return mines(api, unitID, h, rank, x, z)
	elseif key == "a3" then
		return shadowstep(api, unitID, h, rank, targetID)
	elseif key == "ult" then
		return blackout(api, unitID, h, rank, x, z)
	end
	return false
end

local function backline(uid)
	local ud = UnitDefs[Spring.GetUnitDefID(uid) or -1]
	if not ud then
		return false
	end
	if ud.isBuilder and (ud.speed or 0) > 0 then
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

local function guarded(api, h, uid)
	local x, _, z = api.pos(uid)
	local n = 0
	for _, o in ipairs(api.enemiesIn(x, z, 500, h.ally)) do
		if o ~= uid and api.cost(o) >= 1000 and not L.isStructure(o) then
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
	local hpf = L.hpFrac(unitID)
	if key == "a2" then
		local chased = false
		for _, uid in ipairs(L.enemies(api, h, x, z, 500)) do
			if not L.isStructure(uid) then
				chased = true
				break
			end
		end
		if chased and hpf < 0.7 then
			return x, y, z
		end
		local metal, cx, cz = api.bestCluster(x, z, 1000, 250, h.ally)
		if cx and metal >= 2500 then
			local d = sqrt(L.d2(cx, cz, x, z))
			local px, pz = L.toward(x, z, cx, cz, min(700, max(100, d - 300)))
			return px, L.gy(px, pz), pz
		end
	elseif key == "a3" then
		local range = api.val(b(h, "a3").range, rank)
		local t = h.store.followUp
		if not (t and L.alive(t)) then
			t = L.enemyHero(api, h, x, z, range)
		end
		if not t then
			t = L.mostValuable(api, h, x, z, range, nil, backline)
		end
		if t and L.alive(t) and (guarded(api, h, t) <= 2 or hpf > 0.6) then
			h.store.followUp = nil
			local tx, ty, tz = api.pos(t)
			return tx, ty, tz, t
		end
	elseif key == "ult" then
		if hpf < 0.4 then
			return nil
		end
		local ult = b(h, "ult")
		local R = api.val(ult.radius, rank)
		local metal, cx, cz = api.bestCluster(x, z, ult.range or 1500, R, h.ally)
		if cx and (metal >= 15000 or L.enemyHero(api, h, cx, cz, R)) then
			return cx, L.gy(cx, cz), cz
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	L.detachAll(api, h.store.cloakFx)
	h.store.cloaked = false
	for _, m in ipairs(h.store.mines or {}) do
		L.detach(api, m.fx)
	end
	h.store.mines = {}
end

return M
