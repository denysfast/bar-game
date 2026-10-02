-- Deadeye, the Marksman (cort4deadeye, cordeadeye x2.8) - doc/v19-heroes/roster_cor.md section 7.
--   a1 Focus (passive): each volley at the same target as the last adds a Focus stack (max 5, +6..15% damage each);
--      another target resets them. The volley that reaches 5 stacks pierces a 1200 line at full damage (then the
--      stacks reset). Targets of 50k+ max HP take +10%.
--   a2 Recon Flare (active, map in 2400): reveals 600..1000 for 8..15 s (decloaks too); enemies inside are Exposed:
--      +8..20% damage taken from all sources.
--   a3 Tumble (active, map): a quick hop of 350..600; the gun reloads at once and the next volley within 3 s deals
--      +20..60%.
--   ult Kill Shot (active, unit in 3000..4500): channels 2 s (immobile, the laser sight seen by all), then a rail
--      round: 40k..90k + 8..20% of the target's max HP (cap +60k), piercing its line (others 50%). A kill refunds
--      half the cooldown.

local L = VFS.Include("luarules/heroes/cort4_lib.lua")
local M = {}

local floor, max, min, sqrt, random = math.floor, math.max, math.min, math.sqrt, math.random

local SIGHT = { 1, 0.15, 0.08, 1 }

local function b(h, key)
	return h.def.cfg[key]
end

local function gun(h)
	local n = h.def.keyNum.cor_burst_laser and h.def.keyNum.cor_burst_laser[1]
	return n, n and h.def.weapons[n]
end

---------------------------------------------------------------------------- a1 Focus

local function volleyStart(api, unitID, h, f)
	local r = api.rank(h, "a1")
	local a1 = b(h, "a1")
	local st = h.store
	local t = api.target(unitID)
	local v = { f = f, target = t, stacks = 0, mult = 1 }
	if r > 0 then
		if t and t == st.focusTarget then
			st.stacks = min(a1.max or 5, (st.stacks or 0) + 1)
		else
			st.stacks = 0
		end
		st.focusTarget = t
		v.stacks = st.stacks
		v.mult = 1 + v.stacks * api.val(a1.per, r)
		if st.stacks >= (a1.max or 5) then
			v.pierce = true
			st.stacks = 0
		end
		if t and L.alive(t) then
			L.detach(api, st.focusFx)
			st.focusFx = nil
			if v.stacks > 0 then
				st.focusFx = L.attach(api, t, "mark", { color = L.RED, radius = 60 + 15 * v.stacks + L.radius(t) * 0.5, stacks = v.stacks,
					max = a1.max or 5, ttl = 6.5 })
			end
			local tx, _, tz = api.pos(t)
			L.ring(api, tx, tz, { kind = "hex", r0 = 60 + 15 * v.stacks + 40, r1 = 60 + 15 * v.stacks, width = 14, ttl = 0.5, color = L.RED })
		end
	end
	-- Tumble's charged volley
	if st.tumbleUntil and f <= st.tumbleUntil then
		v.mult = v.mult * (1 + (st.tumbleBonus or 0))
		v.tumble = true
		st.tumbleUntil = nil
		L.detach(api, st.tumbleFx)
		st.tumbleFx = nil
	end
	st.volley = v
	L.log(api, h, "a1 volley stacks=%d mult=%.2f pierce=%s tumble=%s", v.stacks, v.mult, tostring(v.pierce), tostring(v.tumble))
end

local function pierceLine(api, unitID, h, victimID, d)
	local hx, hy, hz = api.piecePos(unitID, "flare")
	local vx, vy, vz = api.pos(victimID)
	local dx, dz = vx - hx, vz - hz
	local len = max(1, sqrt(dx * dx + dz * dz))
	local L1200 = b(h, "a1").line or 1200
	local ex, ez = hx + dx / len * max(len + 200, L1200), hz + dz / len * max(len + 200, L1200)
	local hits = api.line(hx, hz, ex, ez, 90, 0, unitID)
	local n = 0
	for _, uid in ipairs(hits) do
		if uid ~= victimID then
			api.damage(uid, d, unitID, { dtype = "laser" })
			local ux, uy, uz = api.pos(uid)
			L.flash(api, ux, uy + 25, uz, { radius = 100, color = L.RED, ttl = 0.3 })
			n = n + 1
		end
	end
	L.beam(api, hx, hy, hz, ex, L.gy(ex, ez) + 30, ez, { color = { 1, 0.25, 0.15, 1 }, width = 16, ttl = 0.25, flare = 1.2, pulse = 4 })
	return n
end

---------------------------------------------------------------------------- a2 Recon Flare

local function reconFlare(api, unitID, h, r, x, z)
	local a2 = b(h, "a2")
	if not x then
		return false
	end
	local hx, hy, hz = api.pos(unitID)
	x, z = L.toward(hx, hz, x, z, a2.range or 2400)
	local R = api.val(a2.radius, r)
	local dur = api.val(a2.duration, r)
	api.reveal(x, z, R, dur, h.ally)
	local gy = L.gy(x, z)
	local fl = { x = x, z = z, R = R, untilF = api.frame() + floor(dur * 30), vuln = api.val(a2.vuln, r), exposed = {}, n = 0 }
	h.store.flares[#h.store.flares + 1] = fl
	L.beam(api, hx, hy + 80, hz, x, gy + 600, z, { color = L.col(L.RED, 0.8), width = 3, ttl = 0.4, flare = 1 })
	L.pillar(api, x, z, { radius = 25, height = 600, color = L.RED, ttl = dur, ring = false })
	L.ring(api, x, z, { kind = "rune", r0 = R, r1 = R, width = 30, ttl = dur, color = L.col(L.RED, 0.3), rot = 0.2 })
	L.ring(api, x, z, { kind = "shock", r0 = 40, r1 = R, width = 40, ttl = 0.6, color = L.col(L.RED, 0.6) })
	L.flash(api, x, gy + 600, z, { radius = 200, color = { 1, 0.4, 0.3, 1 }, ttl = 0.6, ground = false })
	L.log(api, h, "a2 recon flare rank=%d radius=%d dur=%.1f vuln=+%.2f", r, R, dur, fl.vuln)
	return true
end

local function flaresFrame(api, unitID, h, f)
	local keep = {}
	for _, fl in ipairs(h.store.flares) do
		if fl.untilF > f then
			keep[#keep + 1] = fl
			if f % 15 == 0 then
				local left = (fl.untilF - f) / 30
				for _, uid in ipairs(api.enemiesIn(fl.x, fl.z, fl.R, h.ally)) do
					api.mark(uid, "exposed", 1, { vuln = fl.vuln, from = unitID })
					if not fl.exposed[uid] and fl.n < 30 then
						fl.exposed[uid] = true
						fl.n = fl.n + 1
						L.attach(api, uid, "mark", { color = L.col(L.RED, 0.8), radius = 50 + L.radius(uid) * 0.4, stacks = 0, max = 1, ttl = left })
					end
				end
			end
			if f % 30 == 0 then
				L.flash(api, fl.x, L.gy(fl.x, fl.z) + 590, fl.z, { radius = 140, color = { 1, 0.35, 0.25, 1 }, ttl = 0.5, ground = false })
				L.flash(api, fl.x, L.gy(fl.x, fl.z) + 10, fl.z, { radius = fl.R * 0.5, color = L.col(L.RED, 0.25), ttl = 0.9 })
			end
		end
	end
	h.store.flares = keep
end

---------------------------------------------------------------------------- a3 Tumble

local function tumble(api, unitID, h, r, x, z)
	local a3 = b(h, "a3")
	if not x then
		return false
	end
	local hx, hy, hz = api.pos(unitID)
	local tx, tz = L.toward(hx, hz, x, z, api.val(a3.range, r))
	if L.d2(tx, tz, hx, hz) < 30 * 30 then
		-- in place: a small sidestep
		tx, tz = L.clampX(hx + 80), hz
	end
	L.ring(api, hx, hz, { kind = "shock", r0 = 30, r1 = 120, width = 22, ttl = 0.3, color = { 1, 0.6, 0.5, 0.9 } })
	local trail = L.attach(api, unitID, "trail", { color = { 1, 0.55, 0.45, 0.9 }, width = 40, length = 0.4, ttl = 0.6 })
	local ok = api.dash(unitID, h, tx, tz, { seconds = 0.4, arc = 70, onLand = function()
		L.detach(api, trail)
		api.reloadNow(unitID, "cor_burst_laser")
	end })
	if not ok then
		L.detach(api, trail)
		return false
	end
	local st = h.store
	st.tumbleUntil = api.frame() + floor(((a3.window or 3) + 0.4) * 30)
	st.tumbleBonus = api.val(a3.bonus, r)
	L.detach(api, st.tumbleFx)
	st.tumbleFx = L.attach(api, unitID, "electric", { color = L.RED, intensity = 0.4, ttl = (a3.window or 3) + 0.4 })
	L.log(api, h, "a3 tumble rank=%d bonus=+%.2f", r, st.tumbleBonus)
	return true
end

---------------------------------------------------------------------------- ult Kill Shot

local function killShot(api, unitID, h, r, targetID)
	local ult = b(h, "ult")
	if not (targetID and L.alive(targetID)) or Spring.GetUnitAllyTeam(targetID) == h.ally then
		return false
	end
	local ch = ult.channel or 2
	api.buff(unitID, h, "killshot", ch, { immobile = true })
	api.forceTarget(unitID, targetID, ch)
	api.active(unitID, "ult", ch)
	local tx, _, tz = api.pos(targetID)
	local fx = {
		L.attach(api, unitID, "link", { target = targetID, style = "beam", color = SIGHT, width = 3, ttl = ch, visible = "all" }),
		L.attach(api, targetID, "mark", { color = SIGHT, radius = L.radius(targetID) + 60, stacks = 1, max = 1, ttl = ch, visible = "all" }),
	}
	L.ring(api, tx, tz, { kind = "hex", r0 = 200, r1 = 60, width = 18, ttl = ch, color = SIGHT, visible = "all" })
	h.store.ks = { target = targetID, fx = fx }
	api.delay(floor(ch * 30), function()
		local ks = h.store.ks
		h.store.ks = nil
		if not ks then
			return
		end
		L.detachAll(api, ks.fx)
		if not L.alive(unitID) then
			return
		end
		local t = ks.target
		if not L.alive(t) then
			api.cooldown(unitID, h, "ult", api.val(ult.cooldown, r) * 0.25)
			L.log(api, h, "ult kill shot: the target was gone, cooldown cut")
			return
		end
		local p = api.power(h)
		local dmg = (api.val(ult.dmg, r) + min(ult.pctCap or 60000, api.val(ult.pct, r) * L.maxHp(api, t))) * p
		local mx, my, mz = api.piecePos(unitID, "flare")
		local ux, uy, uz = api.pos(t)
		local dx, dz = ux - mx, uz - mz
		local len = max(1, sqrt(dx * dx + dz * dz))
		local ex, ez = ux + dx / len * 800, uz + dz / len * 800
		api.damage(t, dmg, unitID, { dtype = "rail" })
		local others = 0
		for _, uid in ipairs(api.line(mx, mz, ex, ez, 100, 0, unitID)) do
			if uid ~= t then
				api.damage(uid, dmg * (ult.pierce or 0.5), unitID, { dtype = "rail" })
				local ox, oy, oz = api.pos(uid)
				L.flash(api, ox, oy + 25, oz, { radius = 160, color = L.ORANGE, ttl = 0.35 })
				others = others + 1
			end
		end
		L.beam(api, mx, my, mz, ex, L.gy(ex, ez) + 30, ez, { color = { 1, 0.4, 0.15, 1 }, width = 30, ttl = 0.45, flare = 2, pulse = 5, visible = "all" })
		L.beam(api, mx, my, mz, ex, L.gy(ex, ez) + 30, ez, { color = L.WHITE, width = 10, ttl = 0.3, flare = 1, visible = "all" })
		L.flash(api, mx, my, mz, { radius = 200, color = L.WHITE, ttl = 0.35, ground = false })
		L.flash(api, ux, uy + 30, uz, { radius = 160, color = L.ORANGE, ttl = 0.4 })
		L.ring(api, ux, uz, { kind = "shock", r0 = 50, r1 = 400, width = 46, ttl = 0.45, color = L.ORANGE })
		api.delay(2, function()
			local killed = not L.alive(t)
			if killed and L.alive(unitID) then
				api.cooldown(unitID, h, "ult", api.val(ult.cooldown, r) * 0.5)
			end
			L.log(api, h, "ult kill shot rank=%d dmg=%d pierced=%d killed=%s", r, dmg, others, tostring(killed))
		end)
	end)
	L.log(api, h, "ult channel rank=%d target=%s", r, UnitDefs[Spring.GetUnitDefID(targetID)].name)
	return true
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.flares = h.store.flares or {}
	h.store.stacks = 0
	h.store.focusTarget = nil
	h.store.volley = nil
end

function M.fired(api, unitID, h, weaponNum)
	local n = gun(h)
	if weaponNum == n then
		volleyStart(api, unitID, h, api.frame())
	end
end

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	if isParalyzer or damage <= 0 then
		return damage
	end
	local _, w = gun(h)
	if not w or (weaponDefID ~= w.wdid and api.damageType(weaponDefID) ~= "laser") then
		return damage
	end
	local v = h.store.volley
	local d = damage
	if v and api.frame() - v.f < 45 then
		d = d * v.mult
		if v.pierce then
			local n = pierceLine(api, unitID, h, victimID, d)
			v.pierced = (v.pierced or 0) + n
		end
	end
	if api.rank(h, "a1") > 0 and L.maxHp(api, victimID) >= (b(h, "a1").big or 50000) then
		d = d * (1 + (b(h, "a1").bigBonus or 0.1))
	end
	return d
end

function M.frame(api, unitID, h, f)
	L.tick(api, unitID, h, f)
	flaresFrame(api, unitID, h, f)
	local st = h.store
	if st.tumbleUntil and f > st.tumbleUntil then
		st.tumbleUntil = nil
		L.detach(api, st.tumbleFx)
		st.tumbleFx = nil
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a2" then
		return reconFlare(api, unitID, h, rank, x, z)
	elseif key == "a3" then
		return tumble(api, unitID, h, rank, x, z)
	elseif key == "ult" then
		return killShot(api, unitID, h, rank, targetID)
	end
	return false
end

local function isArtillery(uid)
	local ud = UnitDefs[Spring.GetUnitDefID(uid) or -1]
	for _, w in ipairs(ud and ud.weapons or {}) do
		local wd = WeaponDefs[w.weaponDef]
		if wd and wd.range > 1300 then
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
	if key == "a2" then
		local range = b(h, "a2").range or 2400
		local best, bestC
		for _, uid in ipairs(api.enemiesIn(x, z, range, h.ally)) do
			if not api.seenBy(uid, h.ally) then
				local los = Spring.GetUnitLosState(uid, h.ally)
				if los and los.radar then
					local c = api.cost(uid)
					if not bestC or c > bestC then
						best, bestC = uid, c
					end
				end
			end
		end
		if best then
			local tx, ty, tz = api.pos(best)
			return tx, ty, tz
		end
		local metal, cx, cz = api.bestCluster(x, z, range, api.val(b(h, "a2").radius, rank), h.ally)
		if cx and metal >= 4000 then
			return cx, L.gy(cx, cz), cz
		end
	elseif key == "a3" then
		local range = api.val(b(h, "a3").range, rank)
		local threat = false
		for _, uid in ipairs(L.enemies(api, h, x, z, 600)) do
			if not isArtillery(uid) and not L.isStructure(uid) then
				threat = true
				break
			end
		end
		if threat or L.hpDrop(h, unitID, f, 2) >= 0.1 then
			local ex, ez = L.escapePoint(api, h, unitID, range)
			if ex then
				return ex, L.gy(ex, ez), ez
			end
		end
		local n, w = gun(h)
		if n then
			local rs = Spring.GetUnitWeaponState(unitID, n, "reloadState") or 0
			local t = api.target(unitID)
			if t and rs - f >= 90 and (api.isHero(t) or api.cost(t) >= 5000) then
				return x + 60, y, z
			end
		end
	elseif key == "ult" then
		if hpf <= 0.5 then
			return nil
		end
		for _, uid in ipairs(L.enemies(api, h, x, z, 800)) do
			if not L.isStructure(uid) then
				return nil
			end
		end
		local ult = b(h, "ult")
		local range = api.val(ult.range, rank)
		local est = api.val(ult.dmg, rank) * api.power(h)
		local best, bestS
		for _, uid in ipairs(L.enemies(api, h, x, z, range)) do
			local hp, mhp = Spring.GetUnitHealth(uid)
			local th = api.hero(uid)
			local eff = (hp or 0) * (th and th.hpMult or 1)
			local s
			if th and eff <= est + min(ult.pctCap or 60000, api.val(ult.pct, rank) * L.maxHp(api, uid)) * api.power(h) then
				s = 1e12
			else
				s = api.cost(uid) * (th and 3 or 1) * max(0.1, 1 - (hp or 0) / max(1, mhp or 1))
			end
			if not bestS or s > bestS then
				best, bestS = uid, s
			end
		end
		if best and (bestS >= 1e12 or api.cost(best) >= 3000) then
			local tx, ty, tz = api.pos(best)
			return tx, ty, tz, best
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	local ks = h.store.ks
	if ks then
		L.detachAll(api, ks.fx)
		h.store.ks = nil
	end
	L.detach(api, h.store.tumbleFx)
	L.detach(api, h.store.focusFx)
end

return M
