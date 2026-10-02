-- Colossus, the Warlord (cort4colossus, corkorg x1.8) - doc/v19-heroes/roster_cor.md section 1.
--   a1 Titan Grip (active, enemy unit in 450): grabs a non-hero machine and hurls it into the densest enemy cluster
--      (up to 900..1600): the victim takes the damage, where it lands enemies take a share of its max HP and are
--      stunned 1.5 s (+1 Fault). A hero is kicked back 300 and stunned instead.
--   a2 Fault Line (passive): every 4..2.5 s on the move (or every 3rd kick) a quake: damage, 40% slow 2 s, +1 Fault
--      (max 3, 6 s); the third stack knocks the enemy down (1 s stun, heroes half).
--   a3 Warcry (active, self): allies around +damage +20% speed, enemies taunted onto Colossus, Colossus takes less.
--   ult Earthshatter (active, map): a 1.2 s leap; the landing deals damage (40% at the edge) and stuns; six fissures
--      erupt three times.

local L = VFS.Include("luarules/heroes/cort4_lib.lua")
local M = {}

local floor, max, min, sqrt, cos, sin, pi, random = math.floor, math.max, math.min, math.sqrt, math.cos, math.sin, math.pi, math.random

local DUST = { 0.9, 0.6, 0.3, 0.7 }

local function b(h, key)
	return h.def.cfg[key]
end

---------------------------------------------------------------------------- Fault stacks (a2; Titan Grip adds them too)

local function faultFx(api, h, uid, stacks)
	local st = h.store
	st.faultFx = st.faultFx or {}
	local old = st.faultFx[uid]
	if old then
		L.detach(api, old)
		st.faultFx[uid] = nil
	end
	if stacks > 0 then
		local n = 0
		for _ in pairs(st.faultFx) do
			n = n + 1
		end
		if n < 30 then
			st.faultFx[uid] = L.attach(api, uid, "mark", { color = { 1, 0.55, 0.2, 0.9 }, radius = L.radius(uid) * 0.9 + 20,
				stacks = stacks, max = 3, ttl = 6 })
		end
	end
end

local function addFault(api, unitID, h, uid)
	local a2 = b(h, "a2")
	if api.rank(h, "a2") <= 0 or not L.alive(uid) then
		return
	end
	local maxS = a2.maxStacks or 3
	local s = api.mark(uid, "fault", a2.stackTime or 6, { max = maxS })
	if s >= maxS then
		api.mark(uid, "fault", 0.1, { stacks = -maxS })
		api.stun(uid, a2.knock or 1, unitID)
		local x, y, z = api.pos(uid)
		L.flash(api, x, y + 10, z, { radius = 80, color = L.AMBER, ttl = 0.35 })
		L.ring(api, x, z, { kind = "shock", r0 = 20, r1 = 90, width = 16, ttl = 0.3, color = DUST })
		faultFx(api, h, uid, 0)
		h.store.knocks = (h.store.knocks or 0) + 1
	else
		faultFx(api, h, uid, s)
	end
end

local function quake(api, unitID, h, why)
	local r = api.rank(h, "a2")
	local a2 = b(h, "a2")
	local foot = h.store.foot == "lfootstep" and "rfootstep" or "lfootstep"
	h.store.foot = foot
	local x, y, z = api.piecePos(unitID, foot)
	local R = api.val(a2.radius, r)
	local dmg = api.val(a2.dmg, r) * api.power(h)
	local hits = api.area(x, z, R, dmg, unitID, { dtype = "plasma" })
	for _, uid in ipairs(hits) do
		api.slow(uid, a2.slow or 0.4, a2.slowTime or 2)
		addFault(api, unitID, h, uid)
	end
	L.ring(api, x, z, { kind = "shock", r0 = 60, r1 = R, width = 70, ttl = 0.6, color = DUST })
	L.ring(api, x, z, { kind = "shock", r0 = 30, r1 = R * 0.6, width = 40, ttl = 0.45, color = { 1, 0.75, 0.45, 0.8 } })
	L.ring(api, x, z, { kind = "fog", r0 = 40, r1 = R * 0.8, width = 90, ttl = 1.0, color = { 0.75, 0.6, 0.45, 0.6 } })
	L.flash(api, x, y + 10, z, { radius = 140, color = { 1, 0.7, 0.4, 0.8 }, ttl = 0.35 })
	L.log(api, h, "a2 quake (%s) rank=%d dmg=%d radius=%d hit=%d knocks=%d", why, r, dmg, R, #hits, h.store.knocks or 0)
end

---------------------------------------------------------------------------- a1 Titan Grip

local function titanGrip(api, unitID, h, r, targetID)
	local a1 = b(h, "a1")
	if not (targetID and L.alive(targetID)) or Spring.GetUnitAllyTeam(targetID) == h.ally then
		return false
	end
	if L.isStructure(targetID) or L.isAir(targetID) then
		return false
	end
	local hx, hy, hz = api.pos(unitID)
	local tx, ty, tz = api.pos(targetID)
	local dmg = api.val(a1.dmg, r) * api.power(h)
	local gx, gy, gz = api.piecePos(unitID, "rgunflare")
	L.beam(api, gx, gy, gz, tx, ty + 20, tz, { color = L.AMBER, width = 8, ttl = 0.35, flare = 1.2 })
	L.ring(api, tx, tz, { kind = "hex", r0 = 100, r1 = 70, width = 14, ttl = 0.6, color = L.AMBER })
	if api.isHero(targetID) then
		-- a hero is kicked back and stunned (api.push / api.stun halve it for heroes: the given values are the result)
		api.damage(targetID, dmg, unitID, { dtype = "plasma" })
		api.push(targetID, hx, hz, 600, 0.4)
		api.stun(targetID, 2 * api.val(a1.heroStun, r), unitID)
		L.flash(api, tx, ty + 30, tz, { radius = 160, color = L.AMBER, ttl = 0.3 })
		L.ring(api, tx, tz, { kind = "shock", r0 = 30, r1 = 220, width = 30, ttl = 0.4, color = DUST })
		L.log(api, h, "a1 kick hero rank=%d dmg=%d stun=%.1f", r, dmg, api.val(a1.heroStun, r))
		return true
	end
	local reach = api.val(a1.throw, r)
	local metal, cx, cz = api.bestCluster(hx, hz, reach, a1.splash or 250, h.ally)
	if not cx or metal <= 0 then
		-- nobody to throw it at: as far as it goes, straight ahead
		cx, cz = L.toward(hx, hz, tx, tz, 99999)
		local dx, dz = tx - hx, tz - hz
		local d = max(1, sqrt(dx * dx + dz * dz))
		cx, cz = L.clampX(hx + dx / d * reach), L.clampZ(hz + dz / d * reach)
	end
	local _, vmax = Spring.GetUnitHealth(targetID)
	local share = min(a1.cap or 30000, api.val(a1.share, r) * (vmax or 0)) * api.power(h)
	local trail = L.attach(api, targetID, "trail", { color = L.ORANGE, width = 30, length = 0.5, ttl = 1.2 })
	local ok = api.throw(targetID, cx, cz, 1.0, function(lx, lz) L.later(api, function()
		L.detach(api, trail)
		api.damage(targetID, dmg, unitID, { dtype = "plasma" })
		local splash = a1.splash or 250
		local hits = api.area(lx, lz, splash, 0, unitID)
		for _, uid in ipairs(hits) do
			if uid ~= targetID then
				api.damage(uid, share, unitID, { dtype = "plasma" })
			end
			api.stun(uid, a1.stun or 1.5, unitID)
			addFault(api, unitID, h, uid)
		end
		local ly = L.gy(lx, lz)
		L.ring(api, lx, lz, { kind = "shock", r0 = 40, r1 = 340, width = 60, ttl = 0.7, color = L.ORANGE })
		L.ring(api, lx, lz, { kind = "fire", r0 = 30, r1 = 220, width = 70, ttl = 0.6, color = L.col(L.ORANGE, 0.8) })
		L.ring(api, lx, lz, { kind = "fog", r0 = 60, r1 = 300, width = 100, ttl = 1.4, color = { 0.8, 0.6, 0.4, 0.7 } })
		L.flash(api, lx, ly + 30, lz, { radius = 220, color = { 1, 0.6, 0.3, 1 }, ttl = 0.45 })
		for i = 1, min(12, #hits) do
			local ux, uy, uz = api.pos(hits[i])
			if ux then
				L.flash(api, ux, uy + 20, uz, { radius = 60, color = L.AMBER, ttl = 0.6 })
			end
		end
		L.log(api, h, "a1 throw landed rank=%d victimDmg=%d splash=%d hit=%d dist=%d", r, dmg, share, #hits,
			sqrt(L.d2(lx, lz, tx, tz)))
	end) end)
	if not ok then
		L.detach(api, trail)
		return false
	end
	L.log(api, h, "a1 grab rank=%d victim=%s to %d,%d (cluster %d metal)", r, UnitDefs[Spring.GetUnitDefID(targetID)].name, cx, cz, metal or 0)
	return true
end

---------------------------------------------------------------------------- a3 Warcry

local function warcry(api, unitID, h, r)
	local a3 = b(h, "a3")
	local x, y, z = api.pos(unitID)
	local R = api.val(a3.radius, r)
	local dur = api.val(a3.duration, r)
	local buffed, taunted = 0, 0
	for _, uid in ipairs(api.alliesIn(x, z, R, h.ally)) do
		if uid ~= unitID and not api.isHero(uid) and not L.isStructure(uid) then
			api.unitBuff(uid, "warcry", dur, { damage = api.val(a3.damage, r), speed = a3.speed or 0.2 })
			buffed = buffed + 1
			if buffed <= 40 then
				L.attach(api, uid, "aura", { radius = L.radius(uid) + 18, color = L.col(L.RED, 0.75), pattern = "runes", ttl = dur })
			end
		end
	end
	local taunt = api.val(a3.taunt, r)
	for _, uid in ipairs(api.enemiesIn(x, z, R, h.ally)) do
		if api.taunt(uid, unitID, taunt) then
			taunted = taunted + 1
			if taunted <= 20 then
				local ux, uy, uz = api.pos(uid)
				L.beam(api, ux, uy + 20, uz, x, y + 120, z, { color = L.RED, width = 3, ttl = 0.5, flare = 0.5 })
			end
		end
	end
	api.buff(unitID, h, "warcry", dur, { armor = api.val(a3.armor, r) })
	api.active(unitID, "a3", dur)
	L.ring(api, x, z, { kind = "rune", r0 = 100, r1 = R, width = 40, ttl = 0.8, color = L.RED })
	L.ring(api, x, z, { kind = "shock", r0 = 80, r1 = R, width = 60, ttl = 0.6, color = L.col(L.RED, 0.7) })
	local ex, ey, ez = api.piecePos(unitID, "head")
	L.flash(api, ex, ey + 20, ez, { radius = 160, color = L.RED, ttl = 0.5, ground = false })
	h.store.cryFx = {
		L.attach(api, unitID, "aura", { radius = 260, color = L.col(L.RED, 0.8), pattern = "runes", ttl = dur }),
		L.attach(api, unitID, "tint", { pattern = "rim", color = L.RED, strength = 0.6, ttl = dur }),
	}
	L.log(api, h, "a3 warcry rank=%d radius=%d dur=%.1f allies=%d taunted=%d", r, R, dur, buffed, taunted)
	return true
end

---------------------------------------------------------------------------- ult Earthshatter

local function fissures(api, unitID, h, r, cx, cz)
	local ult = b(h, "ult")
	local len = ult.fissureLen or 900
	local dmg = api.val(ult.fissure, r) * api.power(h)
	local a0 = random() * pi
	local lines = {}
	local gy = L.gy(cx, cz)
	for k = 0, 5 do
		local a = a0 + k * pi / 3 + (random() - 0.5) * 0.25
		local ex, ez = L.clampX(cx + cos(a) * len), L.clampZ(cz + sin(a) * len)
		lines[#lines + 1] = { ex, ez }
		L.beam(api, cx, gy + 6, cz, ex, L.gy(ex, ez) + 6, ez, { color = L.LAVA, width = 30, ttl = (ult.ticks or 3) + 0.4, pulse = 2, flare = 0.3 })
	end
	local total = 0
	for t = 1, ult.ticks or 3 do
		api.delay(t * 30 - 10, function()
			local n = 0
			local seen = {}
			for _, l in ipairs(lines) do
				-- one hit per enemy per eruption (the fissures meet at the centre)
				for _, uid in ipairs(api.line(cx, cz, l[1], l[2], 120, 0, unitID)) do
					if not seen[uid] then
						seen[uid] = true
						n = n + 1
						api.damage(uid, dmg, unitID, { dtype = "flame", ally = h.ally })
					end
				end
				for s = 1, 4 do
					local f = (s - 0.5 + random() * 0.5) / 4
					local px, pz = cx + (l[1] - cx) * f, cz + (l[2] - cz) * f
					L.flash(api, px, L.gy(px, pz) + 12, pz, { radius = 80, color = L.LAVA, ttl = 0.5 })
				end
				L.pillar(api, l[1], l[2], { radius = 30, height = 220, color = L.col(L.LAVA, 0.8), ttl = 0.5, ring = false })
			end
			total = total + n
			L.log(api, h, "ult fissure tick %d dmg=%d hits=%d", t, dmg, n)
		end)
	end
end

local function earthshatter(api, unitID, h, r, x, z)
	local ult = b(h, "ult")
	if not x then
		return false
	end
	local hx, hy, hz = api.pos(unitID)
	local tx, tz = L.toward(hx, hz, x, z, api.val(ult.range, r))
	local R = api.val(ult.radius, r)
	local leap = ult.leap or 1.2
	L.flash(api, hx, hy + 20, hz, { radius = 300, color = { 0.85, 0.65, 0.45, 0.8 }, ttl = 0.5 })
	L.ring(api, hx, hz, { kind = "fog", r0 = 80, r1 = 340, width = 90, ttl = 1.0, color = { 0.75, 0.6, 0.45, 0.6 } })
	local trail = L.attach(api, unitID, "trail", { color = L.ORANGE, width = 60, length = 0.5, ttl = leap + 0.3 })
	L.ring(api, tx, tz, { kind = "hex", r0 = R, r1 = R * 0.3, width = 30, ttl = leap, color = L.RED })
	local ok = api.dash(unitID, h, tx, tz, { seconds = leap, arc = 420, untargetable = true, onLand = function(lx, lz) L.later(api, function()
		L.detach(api, trail)
		local dmg = api.val(ult.dmg, r) * api.power(h)
		local stun = api.val(ult.stun, r)
		local n, dealt = 0, 0
		for _, uid in ipairs(api.enemiesIn(lx, lz, R, h.ally)) do
			local ux, _, uz = api.pos(uid)
			local f = sqrt(L.d2(ux, uz, lx, lz)) / R
			local d = dmg * (1 - 0.6 * min(1, f))
			api.damage(uid, d, unitID, { dtype = "plasma" })
			api.stun(uid, stun, unitID)
			addFault(api, unitID, h, uid)
			n, dealt = n + 1, dealt + d
		end
		local ly = L.gy(lx, lz)
		L.flash(api, lx, ly + 40, lz, { radius = 700, color = { 1, 0.7, 0.45, 1 }, ttl = 0.6 })
		L.ring(api, lx, lz, { kind = "shock", r0 = 100, r1 = 900, width = 90, ttl = 0.8, color = L.ORANGE })
		L.ring(api, lx, lz, { kind = "fog", r0 = 120, r1 = R, width = 140, ttl = 1.4, color = { 0.7, 0.55, 0.4, 0.6 } })
		L.ring(api, lx, lz, { kind = "fire", r0 = 50, r1 = R * 0.6, width = 80, ttl = 0.8, color = L.col(L.LAVA, 0.9) })
		fissures(api, unitID, h, r, lx, lz)
		L.log(api, h, "ult land rank=%d dmg=%d radius=%d stun=%.1f hit=%d dealt=%d", r, dmg, R, stun, n, dealt)
	end) end })
	if not ok then
		L.detach(api, trail)
		return false
	end
	return true
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.moved = 0
	h.store.kicks = 0
end

function M.frame(api, unitID, h, f)
	L.tick(api, unitID, h, f)
	local r = api.rank(h, "a2")
	if r > 0 then
		local vx, _, vz = Spring.GetUnitVelocity(unitID)
		local speed = vx and sqrt(vx * vx + vz * vz) * 30 or 0
		if speed > 6 then
			h.store.moved = (h.store.moved or 0) + 3
			if h.store.moved >= api.val(b(h, "a2").period, r) * 30 then
				h.store.moved = 0
				quake(api, unitID, h, "step")
			end
		end
	end
	if h.store.cryFx and (Spring.GetUnitRulesParam(unitID, "hero_on_a3") or 0) < f then
		h.store.cryFx = nil
	end
end

function M.fired(api, unitID, h, weaponNum)
	local w = h.def.weapons[weaponNum]
	if w and w.key == "krogkick" and api.rank(h, "a2") > 0 then
		h.store.kicks = (h.store.kicks or 0) + 1
		if h.store.kicks % 3 == 0 then
			quake(api, unitID, h, "kick")
		end
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a1" then
		return titanGrip(api, unitID, h, rank, targetID)
	elseif key == "a3" then
		return warcry(api, unitID, h, rank)
	elseif key == "ult" then
		return earthshatter(api, unitID, h, rank, x, z)
	end
	return false
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	local hpf = L.hpFrac(unitID)
	if key == "a1" then
		local a1 = b(h, "a1")
		local best, bestHp
		for _, uid in ipairs(L.enemies(api, h, x, z, a1.range or 450)) do
			if not api.isHero(uid) and not L.isStructure(uid) and not L.isAir(uid) then
				local _, m = Spring.GetUnitHealth(uid)
				if m and (not bestHp or m > bestHp) then
					best, bestHp = uid, m
				end
			end
		end
		if best then
			local metal, _, _ = api.bestCluster(x, z, api.val(a1.throw, rank), a1.splash or 250, h.ally)
			local _, n = api.enemyCostNear(x, z, api.val(a1.throw, rank), h.ally)
			if metal > 0 and n >= 4 then
				local tx, ty, tz = api.pos(best)
				return tx, ty, tz, best
			end
		end
		local hero = L.enemyHero(api, h, x, z, a1.range or 450)
		if hero then
			local tx, ty, tz = api.pos(hero)
			return tx, ty, tz, hero
		end
	elseif key == "a3" then
		local a3 = b(h, "a3")
		local R = api.val(a3.radius, rank)
		local allies = 0
		for _, uid in ipairs(api.alliesIn(x, z, R, h.ally)) do
			if uid ~= unitID and not L.isStructure(uid) then
				allies = allies + 1
			end
		end
		local _, enemies = api.enemyCostNear(x, z, R, h.ally)
		-- v19-balance: the AI never met 8 allies + 6 enemies around its front hero; the taunt alone is worth it
		if hpf > 0.35 and enemies >= 5 and (allies >= 3 or enemies >= 8) then
			return x, y, z
		end
	elseif key == "ult" then
		local ult = b(h, "ult")
		local range = api.val(ult.range, rank)
		if hpf < 0.25 then
			local ex, ez = L.escapePoint(api, h, unitID, range)
			if ex then
				return ex, L.gy(ex, ez), ez
			end
			return nil
		end
		if hpf > 0.4 then
			local metal, cx, cz = api.bestCluster(x, z, range, api.val(ult.radius, rank), h.ally)
			if cx and metal >= 15000 then
				return cx, L.gy(cx, cz), cz
			end
		end
	end
	return nil
end

function M.impact(api, unitID, h, weaponDefID, x, y, z, projectileID)
	L.impact(api, unitID, h, weaponDefID, x, y, z, projectileID)
end

function M.unitDied(api, unitID, h, deadID)
	local st = h.store.faultFx
	if st and st[deadID] then
		L.detach(api, st[deadID])
		st[deadID] = nil
	end
end

return M
