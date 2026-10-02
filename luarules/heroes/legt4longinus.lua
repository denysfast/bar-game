-- Longinus, the Spear (legt4longinus) - v19 Legion hero module (doc/v19-heroes/roster_leg.md section 3).
--   a1 Sunder (passive): rail hits add Sunder stacks (6 s, refreshed): +damage taken from every source per stack
--      (api.mark vuln). Heroes and 10000+ metal targets gain 2 stacks per hit.
--   a2 Hunter's Mark (unit): the prey is revealed, the rails are forced onto it, Longinus deals more to it; a kill
--      while marked resets the cooldown and heals a share of the prey's max HP.
--   a3 Phase Rail (map, dash): 0.4 s untouchable rail-phase; the enemies on the path share a damage budget (v19
--      dmgfix: penetration is a budget, not a full copy per victim) and gain a Sunder stack; the rails reload.
--   ult Spear of Longinus (unit): 1.5 s charge (immobile), one rail through the target and on along a line:
--      the target takes % of its max HP + flat, the rest of the line shares a budget (+3 Sunder), the line burns 5 s.
local L = VFS.Include("luarules/heroes/legt4_lib.lua")
local C = L.C
local M = {}

local max, min, floor, sqrt, random = math.max, math.min, math.floor, math.sqrt, math.random
local SUNDER = "legt4longinus_sunder"

local function cfg(h, key)
	return h.def.cfg[key]
end

---------------------------------------------------------------------------- a1 Sunder

local function sunder(api, unitID, h, uid, stacks)
	local r = api.rank(h, "a1")
	if r <= 0 or not L.alive(uid) then
		return 0
	end
	local a1 = cfg(h, "a1")
	local maxS = api.val(a1.maxStacks, r)
	local before = api.marks(uid, SUNDER)
	local n = api.mark(uid, SUNDER, a1.duration or 6, { stacks = stacks, max = maxS, vuln = api.val(a1.perStack, r), from = unitID })
	L.markOn(api, h.store.sunderFx, uid, "aura", { radius = max(50, L.radius(uid) * 1.1), color = L.a(C.RAIL, 0.15 + 0.07 * n), pattern = "runes" }, a1.duration or 6)
	if n >= maxS and before < maxS then
		L.unitFlash(api, uid, 80, C.RAIL, 0.25, 30)
		api.log("legt4longinus a1 sunder max stacks=%d on %s (+%d%% damage taken)", n, tostring(uid), floor(n * api.val(a1.perStack, r) * 100))
	end
	return n
end

local function isBig(api, uid)
	return api.isHero(uid) or api.cost(uid) >= 10000
end

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	if isParalyzer or damage <= 0 then
		return damage
	end
	if h.store.railIds[weaponDefID] then
		sunder(api, unitID, h, victimID, isBig(api, victimID) and 2 or 1)
	end
	local hm = h.store.hunt
	if hm and hm.target == victimID and api.frame() < hm.untilF then
		hm.bonusDmg = hm.bonusDmg + damage * hm.bonus
		return damage * (1 + hm.bonus)
	end
	return damage
end

---------------------------------------------------------------------------- a2 Hunter's Mark

local function huntEnd(api, h)
	local hm = h.store.hunt
	if hm then
		h.store.hunt = nil
		local fx = L.fx(api)
		fx.detach(hm.aura)
		fx.detach(hm.mark)
	end
end

local function huntMark(api, unitID, h, r, targetID)
	if not L.alive(targetID) or Spring.GetUnitAllyTeam(targetID) == h.ally then
		return false
	end
	local a2 = cfg(h, "a2")
	local dur = api.val(a2.duration, r)
	huntEnd(api, h)
	local fx = L.fx(api)
	local _, maxHp = Spring.GetUnitHealth(targetID)
	local hm = { target = targetID, untilF = api.frame() + floor(dur * 30), bonus = api.val(a2.bonus, r), bonusDmg = 0,
		maxHp = L.effMaxHp(api, targetID), rank = r }
	api.mark(targetID, "legt4longinus_hunt", dur, { reveal = true, from = unitID })
	api.forceTarget(unitID, targetID, dur)
	local rad = max(50, L.radius(targetID) * 1.3)
	hm.aura = fx.attach(targetID, "aura", { radius = rad, color = L.a(C.RAIL, 0.7), pattern = "runes", ttl = dur, visible = "all" })
	hm.mark = fx.attach(targetID, "mark", { radius = rad * 1.1, color = C.RAIL, stacks = 1, max = 1, ttl = dur, visible = "all" })
	local tx, ty, tz = api.pos(targetID)
	local x, y, z = api.pos(unitID)
	fx.pillar(tx, tz, { radius = 30, height = 800, color = L.a(C.RAIL, 0.8), ttl = 0.5 })
	fx.beam(x, y + 40, z, tx, ty + 30, tz, { color = L.a(C.RAIL, 0.5), width = 3, ttl = 0.4, flare = 0.5 })
	h.store.hunt = hm
	api.log("legt4longinus a2 mark rank=%d target=%s dur=%d bonus=%.2f maxHp=%d", r, tostring(targetID), dur, hm.bonus, hm.maxHp)
	return true
end

local function huntTick(api, unitID, h, f)
	local hm = h.store.hunt
	if not hm then
		return
	end
	if f >= hm.untilF then
		api.log("legt4longinus a2 mark over bonusDmg=%d", hm.bonusDmg)
		huntEnd(api, h)
		return
	end
	if not L.alive(hm.target) then
		-- killed while marked: reset + heal
		local a2 = cfg(h, "a2")
		local heal = min(a2.healCap or 40000, hm.maxHp * api.val(a2.heal, hm.rank))
		api.heal(unitID, heal)
		api.cooldown(unitID, h, "a2", 0)
		local x, y, z = api.pos(unitID)
		local fx = L.fx(api)
		fx.ring(x, z, { kind = "shock", r0 = 30, r1 = 300, color = L.a(C.RAIL, 0.9), width = 24, ttl = 0.5 })
		fx.flash(x, y + 40, z, { radius = 120, color = C.RAIL, ttl = 0.4 })
		api.log("legt4longinus a2 kill reset heal=%d bonusDmg=%d", heal, hm.bonusDmg)
		huntEnd(api, h)
	end
end

---------------------------------------------------------------------------- a3 Phase Rail

local function railNums(h)
	local out = {}
	for n, w in pairs(h.def.weapons) do
		if w.key == "t3_rail_accelerator" then
			out[#out + 1] = n
		end
	end
	return out
end

local function phaseRail(api, unitID, h, r, x, z)
	local a3 = cfg(h, "a3")
	local x0, y0, z0 = api.pos(unitID)
	local tx, tz = L.clampTo(x0, z0, x, z, api.val(a3.reach, r))
	local fx = L.fx(api)
	local width = a3.width or 160
	local victims = L.alongLine(api, x0, z0, tx, tz, width, h.ally)
	local d = api.val(a3.dmg, r) * api.power(h)
	local trail = fx.attach(unitID, "trail", { color = C.RAIL, width = 26, length = 0.5, ttl = 0.8 })
	fx.flash(x0, y0 + 40, z0, { radius = 120, color = C.RAIL, ttl = 0.3 })
	fx.attach(unitID, "electric", { color = C.RAIL, intensity = 1.2, ttl = 0.6 })
	local ty = L.groundY(tx, tz)
	local wide = 30 + 15 * (r - 1) / 9
	fx.beam(x0, y0 + 40, z0, tx, ty + 40, tz, { color = L.a(C.RAIL, 0.9), width = wide, ttl = 0.6, pulse = 6, flare = 1.2 })
	fx.beam(x0, y0 + 40, z0, tx, ty + 40, tz, { color = L.a(C.WHITE, 0.9), width = wide * 0.3, ttl = 0.45, pulse = 8, flare = 0 })
	local ok = api.dash(unitID, h, tx, tz, { seconds = 0.4, untargetable = true, onLand = L.later(api, function(lx, lz)
		local ly = L.groundY(lx, lz)
		fx.flash(lx, ly + 40, lz, { radius = 120, color = C.RAIL, ttl = 0.3 })
		fx.ring(lx, lz, { kind = "electric", r0 = 30, r1 = 220, color = C.RAIL, width = 20, ttl = 0.4 })
		local total = 0
		for _, e in ipairs(L.budget(victims, d * 3, d, 0.85)) do
			local uid, dmg = e[1], e[2]
			if L.alive(uid) then
				api.damage(uid, dmg, unitID, { dtype = "rail" })
				sunder(api, unitID, h, uid, 1)
				total = total + dmg
				local ux, uy, uz = api.pos(uid)
				fx.bolt(ux, uy + 120, uz, ux, uy + 20, uz, { color = C.RAIL, width = 3, branches = 3, ttl = 0.2 })
			end
		end
		for _, n in ipairs(railNums(h)) do
			api.reloadNow(unitID, n)
		end
		api.log("legt4longinus a3 phase rail rank=%d dist=%d victims=%d dmg=%d", r, sqrt(L.d2(x0, z0, lx, lz)), #victims, total)
	end) })
	if not ok then
		fx.detach(trail)
	end
	return ok
end

---------------------------------------------------------------------------- ult Spear of Longinus

local function spear(api, unitID, h, r, targetID, x, z)
	local ult = cfg(h, "ult")
	if targetID and (not L.alive(targetID) or Spring.GetUnitAllyTeam(targetID) == h.ally) then
		targetID = nil
	end
	if not targetID and not x then
		return false
	end
	local charge = ult.charge or 1.5
	local fx = L.fx(api)
	api.buff(unitID, h, "spear_charge", charge, { immobile = true })
	local elec = fx.attach(unitID, "electric", { color = C.RAIL, intensity = 0.1, ttl = charge + 0.3 })
	local hx, _, hz = api.pos(unitID)
	for i = 0, 2 do
		api.delay(1 + i * 15, function()
			local px, _, pz = api.pos(unitID)
			if px then
				fx.ring(px, pz, { kind = "electric", r0 = 300, r1 = 60, color = C.RAIL, width = 22, ttl = 0.5 })
			end
		end)
	end
	L.task(h, 6, charge, function(f, t)
		fx.set(elec, { intensity = 0.1 + 1.4 * (f - t.start) / (charge * 30) })
	end)
	local lastX, lastZ = x, z
	if targetID then
		lastX, _, lastZ = api.pos(targetID)
	end
	api.active(unitID, "ult", charge + 5)
	api.delay(floor(charge * 30), function()
		fx.detach(elec)
		if not L.alive(unitID) then
			return
		end
		local x0, y0, z0 = api.pos(unitID)
		local tx, tz = lastX, lastZ
		if targetID and L.alive(targetID) then
			tx, _, tz = api.pos(targetID)
		end
		local dx, dz = tx - x0, tz - z0
		local d = max(1, sqrt(dx * dx + dz * dz))
		local len = api.val(ult.line, r)
		local ex, ez = x0 + dx / d * len, z0 + dz / d * len
		ex, ez = max(0, min(Game.mapSizeX, ex)), max(0, min(Game.mapSizeZ, ez))
		local ey = L.groundY(ex, ez)
		local power = api.power(h)
		-- the main target
		local main = 0
		if targetID and L.alive(targetID) then
			local pct = api.val(ult.pct, r) * (api.isHero(targetID) and 0.5 or 1)
			main = pct * L.effMaxHp(api, targetID) + api.val(ult.flat, r) * power
			api.damage(targetID, main, unitID, { dtype = "rail" })
			sunder(api, unitID, h, targetID, 3)
		end
		-- the line: a shared budget
		local width = ult.width or 100
		local list = {}
		for _, e in ipairs(L.alongLine(api, x0, z0, ex, ez, width, h.ally)) do
			if e[1] ~= targetID then
				list[#list + 1] = e
			end
		end
		local lineDmg = api.val(ult.lineDmg, r) * power
		local total = 0
		for _, e in ipairs(L.budget(list, lineDmg * 4, lineDmg, 0.85)) do
			if L.alive(e[1]) then
				api.damage(e[1], e[2], unitID, { dtype = "rail" })
				sunder(api, unitID, h, e[1], 3)
				total = total + e[2]
			end
		end
		-- the shot
		fx.beam(x0, y0 + 45, z0, ex, ey + 45, ez, { color = L.a(C.RAIL, 1), width = 60, ttl = 0.5, pulse = 10, flare = 2 })
		fx.beam(x0, y0 + 45, z0, ex, ey + 45, ez, { color = L.a(C.WHITE, 1), width = 18, ttl = 0.4, pulse = 12, flare = 0 })
		fx.beam(x0, y0 + 45, z0, ex, ey + 45, ez, { color = L.a(C.RAIL, 0.35), width = 140, ttl = 0.9, pulse = 2, flare = 0 })
		fx.flash(x0, y0 + 45, z0, { radius = 250, color = C.RAIL, ttl = 0.4 })
		fx.flash(tx, L.groundY(tx, tz) + 40, tz, { radius = 300, color = C.WHITE, ttl = 0.5 })
		fx.ring(tx, tz, { kind = "shock", r0 = 40, r1 = 500, color = L.a(C.RAIL, 0.9), width = 40, ttl = 0.6 })
		api.fire(h, "spear", x0, y0 + 45, z0, ex, ey + 45, ez)
		-- the wound: burns 5 s
		local burn = api.val(ult.burn, r) * power
		local wound = fx.beam(x0, y0 + 8, z0, ex, ey + 8, ez, { color = L.a(C.RAIL, 0.5), width = 40, ttl = 5, pulse = 4, flare = 0, ground = true })
		local burned = 0
		L.task(h, 15, 5, function()
			local hit = api.line(x0, z0, ex, ez, width, burn * 0.5, unitID, { dtype = "rail" })
			burned = burned + #hit * burn * 0.5
			local pts = {}
			for i = 0, 5 do
				local t = (i + random()) / 6
				local px, pz = x0 + (ex - x0) * t + (random() - 0.5) * 60, z0 + (ez - z0) * t + (random() - 0.5) * 60
				pts[#pts + 1], pts[#pts + 2], pts[#pts + 3] = px, L.groundY(px, pz) + 20, pz
			end
			fx.chain(pts, { color = C.RAIL, width = 3, ttl = 0.2, delay = 0.02, flash = false })
		end, function()
			fx.detach(wound)
			api.log("legt4longinus ult wound over burn=%d", burned)
		end)
		api.log("legt4longinus ult spear rank=%d main=%d line=%d victims=%d lineDmg=%d len=%d", r, main, total, #list, lineDmg, len)
	end)
	return true
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.sunderFx = {}
	h.store.tasks = {}
	local ids = {}
	for _, w in pairs(h.def.weapons) do
		if w.key == "t3_rail_accelerator" then
			ids[w.wdid] = true
		end
	end
	h.store.railIds = ids
end

function M.frame(api, unitID, h, f)
	L.runTasks(h, f)
	huntTick(api, unitID, h, f)
	if f % 30 == 0 then
		L.markSweep(api, h.store.sunderFx, f)
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a2" then
		return huntMark(api, unitID, h, rank, targetID)
	elseif key == "a3" and x then
		return phaseRail(api, unitID, h, rank, x, z)
	elseif key == "ult" then
		return spear(api, unitID, h, rank, targetID, x, z)
	end
	return false
end

local function bestPrey(api, h, x, z, range, minCost)
	local best, bestV
	for _, uid in ipairs(api.enemiesIn(x, z, range, h.ally)) do
		if api.seenBy(uid, h.ally) and not L.isStructure(uid) then
			local v = api.cost(uid) * (api.isHero(uid) and 10 or 1)
			if (api.isHero(uid) or api.cost(uid) >= minCost) and (not bestV or v > bestV) then
				best, bestV = uid, v
			end
		end
	end
	return best
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	if key == "a2" then
		local t = bestPrey(api, h, x, z, api.val(cfg(h, "a2").range, rank), 5000)
		if t then
			local tx, ty, tz = api.pos(t)
			return tx, ty, tz, t
		end
	elseif key == "a3" then
		local reach = api.val(cfg(h, "a3").reach, rank)
		local frac = L.hpFrac(unitID)
		if frac < 0.35 then
			local cx, cz, n = L.centroid(api, x, z, 600, h.ally)
			if cx then
				local ax, az = L.away(x, z, cx, cz, reach)
				return ax, L.groundY(ax, az), az
			end
		end
		local hm = h.store.hunt
		if hm and L.alive(hm.target) then
			local tx, _, tz = api.pos(hm.target)
			local d = sqrt(L.d2(x, z, tx, tz))
			local wr = api.weaponReach(h)
			if d > wr and d - wr < reach then
				local px, pz = L.clampTo(x, z, tx, tz, min(reach, d - wr * 0.7))
				return px, L.groundY(px, pz), pz
			end
		end
	elseif key == "ult" then
		local range = api.val(cfg(h, "ult").range, rank)
		local t = bestPrey(api, h, x, z, range, 15000)
		if t then
			local tx, ty, tz = api.pos(t)
			return tx, ty, tz, t
		end
		-- the line with the most enemies on it
		local len = api.val(cfg(h, "ult").line, rank)
		local bestN, bestT = 0
		local cands = L.enemies(api, x, z, range, h.ally, true)
		for i = 1, #cands, max(1, floor(#cands / 12)) do
			local tx, _, tz = api.pos(cands[i])
			local dx, dz = tx - x, tz - z
			local d = max(1, sqrt(dx * dx + dz * dz))
			local n = #L.alongLine(api, x, z, x + dx / d * len, z + dz / d * len, 100, h.ally)
			if n > bestN then
				bestN, bestT = n, cands[i]
			end
		end
		if bestT and bestN >= 6 then
			local tx, ty, tz = api.pos(bestT)
			return tx, ty, tz, bestT
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	L.endTasks(h)
	huntEnd(api, h)
	L.markClear(api, h.store.sunderFx or {})
end

return M
