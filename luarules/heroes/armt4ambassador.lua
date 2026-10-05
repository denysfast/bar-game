-- Ambassador, the Rocket Marshal (armt4ambassador, armmerl x3.0, v23): back-line rocket artillery that marks targets
-- for the army and hops away from danger. Numbers per rank: luarules/configs/heroes/arm.lua. API: header of
-- luarules/gadgets/unit_t4_heroes.lua. Artillery: the core scales all its damage (weapon and abilities) by dmgScale 1/3.
--
--   a1 Target Painter (passive): every Starburst Rack hit paints the target for 6 s (api.mark "amb_paint"): revealed
--      and +vuln damage taken from every source (one stack).
--   a2 Guided Volley (active, map, within the weapon range): `count` homing rockets (hero_guided) at the enemies within
--      `radius` of the point, painted ones first, dealt round-robin (at most a third of the volley on one target, so the
--      volley is never a single-target delete), fired 0.1 s apart.
--   a3 Scoot Jets (active, map): a short ballistic hop (0.8 s); on landing the rack is reloaded and it drives faster.
--   ult Saturation Barrage (active, map, within the weapon range): plants itself; a red rune ring marks the area for
--      `warn` s (counterplay: walk out), then `count` rockets fall on it over `duration` s (hero_saturation).

local L = VFS.Include("luarules/heroes/armt4_lib.lua", nil, VFS.ZIP_FIRST)

local M = {}

local RED = { 1, 0.3, 0.15, 1 }
local AMBER = { 1, 0.7, 0.25, 1 }
local PAINT = "amb_paint"

local function b(h, key)
	return h.def.cfg[key]
end

local function clampTo(x, z, tx, tz, range)
	local d = L.dist(x, z, tx, tz)
	if d > range and d > 0 then
		return x + (tx - x) / d * range, z + (tz - z) / d * range
	end
	return tx, tz
end

---------------------------------------------------------------------------- a1 Target Painter

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	local r = api.rank(h, "a1")
	if r > 0 and not isParalyzer and damage > 0 and L.weaponKey(h, weaponDefID) == "armtruck_rocket" then
		local a1 = b(h, "a1")
		local fresh = api.marks(victimID, PAINT) == 0
		api.mark(victimID, PAINT, a1.time or 6, { vuln = api.val(a1.vuln, r), from = unitID, max = 1, reveal = true })
		if fresh and api.fx then
			api.fx.attach(victimID, "aura", { pattern = "runes", color = RED, radius = L.radius(victimID) + 20, ttl = a1.time or 6 })
		end
	end
	return damage
end

---------------------------------------------------------------------------- a2 Guided Volley

local function volley(api, unitID, h, r, tx, tz)
	local a2 = b(h, "a2")
	local x, y, z = api.pos(unitID)
	if not x then
		return false
	end
	tx, tz = clampTo(x, z, tx, tz, api.val(a2.range, r))
	local radius = api.val(a2.radius, r)
	local list = api.enemiesIn(tx, tz, radius, h.ally)
	if #list == 0 then
		return false
	end
	-- painted first, then the most valuable
	table.sort(list, function(p, q)
		local pp, qp = api.marks(p, PAINT) > 0, api.marks(q, PAINT) > 0
		if pp ~= qp then
			return pp
		end
		return api.cost(p) > api.cost(q)
	end)
	local n = math.floor(api.val(a2.count, r) + 0.5)
	local perTarget = math.max(1, math.ceil(n / 3))
	local dmg = api.val(a2.dmg, r) * api.power(h)
	local aoe = a2.aoe or 120
	local plan, per = {}, {}
	for i = 1, n do
		local t = list[((i - 1) % #list) + 1]
		per[t] = (per[t] or 0) + 1
		if per[t] <= perTarget then
			plan[#plan + 1] = t
		end
	end
	local fired = 0
	for i, t in ipairs(plan) do
		L.after(h, 1 + (i - 1) * 3, function()
			local hx, hy, hz = api.pos(unitID)
			if not hx or not L.alive(t) then
				return
			end
			fired = fired + 1
			api.fire(h, "hero_guided", hx, hy + 60, hz, t, { key = "a2", dmg = dmg, aoe = aoe, dtype = "rocket" })
		end)
	end
	if api.fx then
		api.fx.flash(x, y + 60, z, { radius = 90, color = AMBER, ttl = 0.3 })
		api.fx.ring(tx, tz, { kind = "rune", r0 = radius * 0.9, r1 = radius, color = AMBER, ttl = 1.2, width = 18 })
	end
	api.log("armt4ambassador a2 volley rank=%d rockets=%d targets=%d dmg=%d dist=%d", r, #plan, #list, dmg, L.dist(x, z, tx, tz))
	return true
end

---------------------------------------------------------------------------- a3 Scoot Jets

local function scoot(api, unitID, h, r, tx, tz)
	local a3 = b(h, "a3")
	local x, y, z = api.pos(unitID)
	if not x then
		return false
	end
	tx, tz = clampTo(x, z, tx, tz, api.val(a3.range, r))
	local d = L.dist(x, z, tx, tz)
	if d < 60 then
		return false
	end
	local fx = api.fx
	local trail
	if fx then
		fx.flash(x, y + 20, z, { radius = 110, color = AMBER, ttl = 0.3 })
		trail = fx.attach(unitID, "trail", { color = AMBER, width = 20, length = 0.5, ttl = 1.2 })
	end
	return api.dash(unitID, h, tx, tz, { seconds = 0.8, arc = 80 + d * 0.2,
		onLand = function(lx, lz)
			-- next frame: onLand runs inside the core's movement loop
			L.after(h, 1, function()
				if not api.hero(unitID) then
					return
				end
				api.reloadNow(unitID, "armtruck_rocket")
				api.buff(unitID, h, "scoot", a3.speedTime or 4, { speed = api.val(a3.speed, r) })
			end)
			local f2 = api.fx
			if f2 then
				f2.ring(lx, lz, { kind = "shock", r0 = 10, r1 = 180, color = AMBER, ttl = 0.35, width = 22 })
				f2.detach(trail)
			end
			api.log("armt4ambassador a3 scoot rank=%d dist=%d", r, d)
		end })
end

---------------------------------------------------------------------------- ult Saturation Barrage

local function saturation(api, unitID, h, r, tx, tz)
	local ult = b(h, "ult")
	local x, y, z = api.pos(unitID)
	if not x then
		return false
	end
	tx, tz = clampTo(x, z, tx, tz, api.val(ult.range, r))
	local warn = ult.warn or 2
	local dur = api.val(ult.duration, r)
	local n = math.floor(api.val(ult.count, r) + 0.5)
	local dmg = api.val(ult.dmg, r) * api.power(h)
	local R = api.val(ult.radius, r)
	local aoe = ult.aoe or 160
	api.buff(unitID, h, "saturation", warn + dur, { immobile = true })
	api.active(unitID, "ult", warn + dur)
	local fx = api.fx
	if fx then
		-- the telegraph: everyone sees the ring for `warn` s before the first rocket
		fx.ring(tx, tz, { kind = "rune", r0 = R * 0.92, r1 = R, color = RED, ttl = warn + dur, width = 28, rot = 0.4 })
		fx.ring(tx, tz, { kind = "shock", r0 = R, r1 = R * 0.2, color = RED, ttl = warn, width = 30 })
		fx.attach(unitID, "aura", { pattern = "runes", color = RED, radius = 220, ttl = warn + dur })
	end
	local st = { rockets = 0, hits = 0 }
	local volleys = math.max(1, math.floor(dur * 2))
	local per = math.ceil(n / volleys)
	local fired = 0
	local start = math.floor(warn * 30)
	for v = 0, volleys - 1 do
		L.after(h, start + v * 15, function()
			local hx, hy, hz = api.pos(unitID)
			if not hx then
				return
			end
			if api.fx then
				api.fx.flash(hx, hy + 60, hz, { radius = 70, color = RED, ttl = 0.2 })
			end
			for _ = 1, per do
				if fired >= n then
					break
				end
				fired = fired + 1
				local a = math.random() * 6.283
				local dd = math.sqrt(math.random()) * R
				local px, pz = tx + math.cos(a) * dd, tz + math.sin(a) * dd
				local gy = L.gy(px, pz)
				local sx, sz = px + (hx - px) * 0.25, pz + (hz - pz) * 0.25
				api.fire(h, "hero_saturation", sx, gy + 1400, sz, px, gy, pz, { key = "ult", dmg = dmg, aoe = aoe, dtype = "rocket",
					onHit = function(ix, iz, hits)
						st.rockets = st.rockets + 1
						st.hits = st.hits + #hits
						if st.rockets == n then
							api.log("armt4ambassador ult saturation rank=%d rockets=%d dmg=%d hits=%d", r, n, dmg, st.hits)
						end
					end })
			end
		end)
	end
	api.log("armt4ambassador ult saturation cast rank=%d rockets=%d over %.1f s (+%.1f s warning) at %d", r, n, dur, warn, L.dist(x, z, tx, tz))
	return true
end

---------------------------------------------------------------------------- hooks

function M.frame(api, unitID, h, f)
	L.tick(h, f)
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if targetID and not x then
		x, y, z = api.pos(targetID)
	end
	if not x then
		return false
	end
	if key == "a2" then
		return volley(api, unitID, h, rank, x, z)
	elseif key == "a3" then
		return scoot(api, unitID, h, rank, x, z)
	elseif key == "ult" then
		return saturation(api, unitID, h, rank, x, z)
	end
	return false
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	if key == "a2" then
		local range = L.v(api, h, "a2", "range", rank)
		local hero = L.enemyHero(api, x, z, range, h.ally)
		if hero then
			local hx, hy, hz = api.pos(hero)
			return hx, hy, hz
		end
		local cx, cz, cost, n = L.cluster(api, x, z, range, L.v(api, h, "a2", "radius", rank), h.ally)
		if cx and (n >= 4 or cost >= 6000) then
			return cx, L.gy(cx, cz), cz
		end
	elseif key == "a3" then
		-- hop away from the nearest enemy that came close
		local near = api.nearestEnemies(x, z, 700, h.ally, 1)
		local e = near and near[1]
		if e and api.seenBy(e, h.ally) then
			local ex, _, ez = api.pos(e)
			local d = math.max(1, L.dist(x, z, ex, ez))
			local range = L.v(api, h, "a3", "range", rank)
			local px, pz = x + (x - ex) / d * range, z + (z - ez) / d * range
			return px, L.gy(px, pz), pz
		end
	elseif key == "ult" then
		local range = L.v(api, h, "ult", "range", rank)
		local cx, cz, cost, n = L.cluster(api, x, z, range, L.v(api, h, "ult", "radius", rank), h.ally)
		if cx and (n >= 10 or cost >= 30000) then
			return cx, L.gy(cx, cz), cz
		end
	end
	return nil
end

return M
