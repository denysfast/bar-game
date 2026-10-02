-- Recluse Matriarch (armt4recluse, scavenger armsptkt4 x1.6, all-terrain): the giant rocket spider of the cliffs
-- (doc/v19-heroes/roster_arm.md 7). Numbers: luarules/configs/heroes/arm.lua.
--
--   a1 Web Rockets (passive): every rocket hit webs the target for 3 s - slowed (stacking, max 60%) and it takes more
--      damage from Recluse.
--   a2 Web Field (active, map): a web canister bursts into a field: enemies inside are slowed 50% and revealed; Recluse's
--      rockets landing inside burst wider (an extra 1.5x splash ring).
--   a3 Cocoon (active, enemy unit): wraps a non-hero enemy up to a metal cap - stunned and +50% damage taken; if it dies
--      while cocooned, spiderlings hatch for Recluse (armt4recluse_spiderling, 20 s). Heroes are rooted and slowed.
--   ult Rocket Monsoon (active, map): plants itself and rains rockets on a 600 radius; every rocket webs.

local L = VFS.Include("luarules/heroes/armt4_lib.lua", nil, VFS.ZIP_FIRST)

local M = {}

local SILK = { 0.85, 1, 0.85, 0.6 }
local WEB = { 0.75, 1, 0.75, 0.4 }
local GREEN = { 0.6, 1, 0.6, 0.6 }

local function b(h, key)
	return h.def.cfg[key]
end

---------------------------------------------------------------------------- a1 Web Rockets

local function web(api, unitID, h, victimID)
	local r = api.rank(h, "a1")
	if r <= 0 or not L.alive(victimID) then
		return
	end
	local a1 = b(h, "a1")
	local per = api.val(a1.slow, r)
	local maxStacks = math.ceil((a1.maxSlow or 0.6) / per - 0.001)
	local stacks = api.mark(victimID, "web", a1.time or 3, { max = maxStacks, from = unitID })
	api.mark(victimID, "web", a1.time or 3, { stacks = 0, slow = math.min(a1.maxSlow or 0.6, stacks * per) })
	local fx = api.fx
	if fx then
		local st = h.store
		local f = api.frame()
		local e = st.webFx[victimID]
		if e and e.until_ > f then
			e.until_ = f + 90
		else
			st.webCount = 0
			for _, x in pairs(st.webFx) do
				if x.until_ > f then
					st.webCount = st.webCount + 1
				end
			end
			if st.webCount < 30 then
				st.webFx[victimID] = { until_ = f + 90, id = fx.attach(victimID, "aura", { pattern = "web", color = WEB, radius = math.max(40, L.radius(victimID) * 1.2), ttl = a1.time or 3 }) }
			else
				local x, _, z = api.pos(victimID)
				fx.ring(x, z, { kind = "web", r0 = 10, r1 = L.radius(victimID) * 1.2, color = WEB, ttl = 0.6, width = 14 })
			end
		end
	end
end

local function inField(h, x, z)
	for _, fd in ipairs(h.store.fields) do
		if L.dist(x, z, fd.x, fd.z) <= fd.radius then
			return true
		end
	end
	return false
end

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	if isParalyzer then
		return damage
	end
	local key = L.weaponKey(h, weaponDefID)
	if key ~= "adv_rocket" then
		return damage
	end
	local r = api.rank(h, "a1")
	if r > 0 then
		if api.marks(victimID, "web") > 0 then
			damage = damage * (1 + api.val(b(h, "a1").vuln, r))
		end
		web(api, unitID, h, victimID)
	end
	return damage
end

function M.impact(api, unitID, h, weaponDefID, x, y, z, projectileID)
	if #h.store.fields == 0 or L.weaponKey(h, weaponDefID) ~= "adv_rocket" or not inField(h, x, z) then
		return
	end
	-- inside a Web Field the rockets burst wider: the ring between the blast and 1.5x of it takes half a rocket
	local w = L.weapon(h, "adv_rocket")
	local aoe = (w and w.aoe or 160) * math.sqrt(math.max(0.2, 1 + (h.mods and h.mods.splash or 0)))
	local dmg = (w and w.damage or 0) * api.dmgMult(h) * 0.5
	for _, uid in ipairs(api.enemiesIn(x, z, aoe * 1.5, h.ally)) do
		local ux, _, uz = api.pos(uid)
		if L.dist(x, z, ux, uz) > aoe * 0.8 then
			api.damage(uid, dmg, unitID, { dtype = "rocket" })
		end
	end
	if api.fx then
		api.fx.ring(x, z, { kind = "web", r0 = aoe * 0.8, r1 = aoe * 1.5, color = SILK, ttl = 0.35, width = 16 })
	end
end

---------------------------------------------------------------------------- a2 Web Field

local function silk(api, fd)
	local fx = api.fx
	if not fx then
		return
	end
	for i = 0, 5 do
		local a = fd.spin + i * math.pi / 6
		local x1, z1 = fd.x + math.cos(a) * fd.radius, fd.z + math.sin(a) * fd.radius
		local x2, z2 = fd.x - math.cos(a) * fd.radius, fd.z - math.sin(a) * fd.radius
		fx.chain({ x1, L.gy(x1, z1) + 8, z1, fd.x, L.gy(fd.x, fd.z) + 14, fd.z, x2, L.gy(x2, z2) + 8, z2 },
			{ color = { 0.9, 1, 0.9, 0.6 }, width = 2, jitter = 0.05, branches = 0, ttl = 1.0, delay = 0, flash = false, impact = false })
	end
	fd.spin = fd.spin + 0.3
end

local function webField(api, unitID, h, r, tx, tz)
	local a2 = b(h, "a2")
	local x, y, z = api.pos(unitID)
	local range = a2.range or 1400
	local d = L.dist(x, z, tx, tz)
	if d > range * 1.05 then
		tx, tz = x + (tx - x) / d * range, z + (tz - z) / d * range
	end
	local radius = api.val(a2.radius, r)
	local dur = api.val(a2.duration, r)
	local ally = h.ally
	local pid = api.fire(h, "hero_webcanister", x, y + 80, z, tx, L.gy(tx, tz), tz, { key = "a2", dmg = 1, aoe = 1,
		onHit = function(ix, iz)
			local f = api.frame()
			local fd = { x = ix, z = iz, radius = radius, untilFrame = f + math.floor(dur * 30), next = f, spin = 0, slowed = 0 }
			h.store.fields[#h.store.fields + 1] = fd
			api.reveal(ix, iz, radius, dur, ally)
			local fx = api.fx
			if fx then
				fd.zone = fx.zone(ix, iz, { radius = radius, pattern = "web", color = SILK, ttl = dur })
				fx.ring(ix, iz, { kind = "hex", r0 = radius * 0.95, r1 = radius, color = SILK, ttl = dur, width = 20 })
				fx.ring(ix, iz, { kind = "rune", r0 = radius * 0.5, r1 = radius * 0.6, color = SILK, ttl = dur, width = 16, rot = 0.3 })
				fx.flash(ix, L.gy(ix, iz) + 30, iz, { radius = 120, color = SILK, ttl = 0.4 })
			end
			silk(api, fd)
			api.log("armt4recluse a2 web field rank=%d radius=%d dur=%.1f", r, radius, dur)
		end })
	return pid ~= nil
end

local function fieldTick(api, unitID, h, f)
	local keep = {}
	for _, fd in ipairs(h.store.fields) do
		if f < fd.untilFrame then
			keep[#keep + 1] = fd
			if f >= fd.next then
				fd.next = f + 15
				for _, uid in ipairs(api.enemiesIn(fd.x, fd.z, fd.radius, h.ally)) do
					api.slow(uid, b(h, "a2").slow or 0.5, 0.8)
					fd.slowed = fd.slowed + 1
				end
				if (f - fd.untilFrame) % 30 < 15 then
					silk(api, fd)
				end
			end
		else
			api.log("armt4recluse a2 web field over: slow ticks=%d", fd.slowed)
		end
	end
	h.store.fields = keep
end

---------------------------------------------------------------------------- a3 Cocoon

local function cocoon(api, unitID, h, r, targetID)
	if not targetID or not L.alive(targetID) or Spring.GetUnitAllyTeam(targetID) == h.ally then
		return false
	end
	local a3 = b(h, "a3")
	if L.unitDist(unitID, targetID) > (a3.range or 900) * 1.1 then
		return false
	end
	local isHero = api.isHero(targetID)
	if not isHero and api.cost(targetID) > api.val(a3.maxCost, r) then
		return false
	end
	local x, y, z = api.pos(unitID)
	local tx, ty, tz = api.pos(targetID)
	local fx = api.fx
	local dur
	if isHero then
		dur = api.val(a3.heroRoot, r)
		api.mark(targetID, "cocoon", dur, { root = true, from = unitID })
		api.slow(targetID, 0.6, dur + 1) -- heroes take half: 30%
	else
		dur = api.val(a3.stun, r)
		api.stun(targetID, dur, unitID)
		api.mark(targetID, "cocoon", dur, { vuln = 0.5, from = unitID })
		h.store.cocoons[targetID] = { untilFrame = api.frame() + math.floor(dur * 30), r = r }
	end
	if fx then
		fx.chain({ x, y + 50, z, tx, ty + 20, tz }, { color = { 0.9, 1, 0.9, 1 }, width = 3, jitter = 0.08, branches = 0, ttl = 0.5 })
		fx.attach(targetID, "sphere", { radius = math.max(40, L.radius(targetID) * 1.1), color = { 0.85, 1, 0.85, 0.6 }, hex = true, fresnel = 0.5, ttl = dur })
		fx.attach(targetID, "tint", { pattern = "stone", color = { 0.85, 1, 0.85, 1 }, strength = 0.7, ttl = dur })
	end
	api.log("armt4recluse a3 cocoon rank=%d target=%s cost=%d hero=%s dur=%.1f", r, UnitDefs[Spring.GetUnitDefID(targetID)].name, api.cost(targetID), tostring(isHero), dur)
	return true
end

function M.unitDied(api, unitID, h, deadID, deadDefID, x, z, allied)
	local c = h.store.cocoons[deadID]
	if not c then
		return
	end
	h.store.cocoons[deadID] = nil
	if api.frame() > c.untilFrame then
		return
	end
	local n = api.val(b(h, "a3").hatch, c.r)
	local ids = api.summon(unitID, h, "armt4recluse_spiderling", n, { expire = 20, leash = 600, guard = unitID, scaleWithLevel = true })
	for i, uid in ipairs(ids) do
		local a = i * 2.1
		local sx, sz = x + math.cos(a) * 40, z + math.sin(a) * 40
		Spring.SetUnitPosition(uid, sx, sz)
	end
	if api.fx then
		api.fx.flash(x, L.gy(x, z) + 30, z, { radius = 80, color = "green", ttl = 0.4 })
		api.fx.ring(x, z, { kind = "web", r0 = 10, r1 = 140, color = SILK, ttl = 0.6, width = 20 })
	end
	api.log("armt4recluse a3 cocoon hatch: %d spiderlings", #ids)
end

---------------------------------------------------------------------------- ult Rocket Monsoon

local function monsoon(api, unitID, h, r, tx, tz)
	local ult = b(h, "ult")
	local x, y, z = api.pos(unitID)
	local range = api.val(ult.range, r)
	local d = L.dist(x, z, tx, tz)
	if d > range * 1.05 then
		tx, tz = x + (tx - x) / d * range, z + (tz - z) / d * range
	end
	local dur = api.val(ult.duration, r)
	local n = api.val(ult.count, r)
	local dmg = api.val(ult.dmg, r) * api.power(h)
	local R = ult.radius or 600
	local aoe = ult.aoe or 160
	api.buff(unitID, h, "monsoon", dur, { immobile = true })
	api.active(unitID, "ult", dur)
	local fx = api.fx
	if fx then
		fx.ring(tx, tz, { kind = "rune", r0 = R * 0.92, r1 = R, color = GREEN, ttl = dur + 1, width = 26, rot = 0.4 })
		fx.attach(unitID, "aura", { pattern = "runes", color = GREEN, radius = 250, ttl = dur })
	end
	local st = { hits = 0, rockets = 0, n = n }
	local volleys = math.max(1, math.floor(dur * 2))
	local per = math.ceil(n / volleys)
	local fired = 0
	for v = 0, volleys - 1 do
		L.after(h, 1 + v * 15, function()
			local hx, hy, hz = api.pos(unitID)
			if not hx then
				return
			end
			if api.fx then
				api.fx.flash(hx, hy + 70, hz, { radius = 70, color = GREEN, ttl = 0.2 })
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
				api.fire(h, "hero_monsoon", sx, gy + 1400, sz, px, gy, pz, { key = "ult", dmg = dmg, aoe = aoe, dtype = "rocket",
					onHit = function(ix, iz, hits)
						st.rockets = st.rockets + 1
						st.hits = st.hits + #hits
						for _, uid in ipairs(hits) do
							web(api, unitID, h, uid)
						end
						if st.rockets == n then
							api.log("armt4recluse ult monsoon rank=%d rockets=%d dmg=%d hits=%d total=%d", r, n, dmg, st.hits, st.hits * dmg)
						end
					end })
			end
		end)
	end
	api.log("armt4recluse ult monsoon cast rank=%d rockets=%d over %.1f s at %d", r, n, dur, L.dist(x, z, tx, tz))
	return true
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.fields = {}
	h.store.cocoons = {}
	h.store.webFx = {}
end

function M.frame(api, unitID, h, f)
	L.tick(h, f)
	if #h.store.fields > 0 then
		fieldTick(api, unitID, h, f)
	end
	if f % 150 == 0 then
		for uid, e in pairs(h.store.webFx) do
			if e.until_ < f then
				h.store.webFx[uid] = nil
			end
		end
		for uid, c in pairs(h.store.cocoons) do
			if c.untilFrame < f then
				h.store.cocoons[uid] = nil
			end
		end
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a3" then
		return cocoon(api, unitID, h, rank, targetID)
	end
	if targetID and not x then
		x, y, z = api.pos(targetID)
	end
	if not x then
		return false
	end
	if key == "a2" then
		return webField(api, unitID, h, rank, x, z)
	elseif key == "ult" then
		return monsoon(api, unitID, h, rank, x, z)
	end
	return false
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	if key == "a2" then
		local range = b(h, "a2").range or 1400
		local hero = L.enemyHero(api, x, z, range, h.ally)
		if hero and L.unitDist(unitID, hero) < 1100 then
			local hx, hy, hz = api.pos(hero)
			return hx, hy, hz
		end
		local cx, cz, _, n = L.cluster(api, x, z, range, L.v(api, h, "a2", "radius", rank), h.ally)
		if cx and n >= 6 then
			return cx, L.gy(cx, cz), cz
		end
	elseif key == "a3" then
		local a3 = b(h, "a3")
		local range = a3.range or 900
		local hero = L.enemyHero(api, x, z, range, h.ally)
		if hero and L.unitDist(unitID, hero) < 700 then
			local hx, hy, hz = api.pos(hero)
			return hx, hy, hz, hero
		end
		local cap = api.val(a3.maxCost, rank)
		local best, bestC
		for _, uid in ipairs(L.seenEnemies(api, x, z, range, h.ally)) do
			local c = api.cost(uid)
			if not api.isHero(uid) and c <= cap and (not bestC or c > bestC) then
				best, bestC = uid, c
			end
		end
		if best and bestC >= 300 then
			local tx, ty, tz = api.pos(best)
			return tx, ty, tz, best
		end
	elseif key == "ult" then
		local range = L.v(api, h, "ult", "range", rank)
		local cx, cz, cost, n = L.cluster(api, x, z, range, 600, h.ally)
		if cx and (n >= 10 or cost >= 30000) then
			return cx, L.gy(cx, cz), cz
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	h.store.fields = {}
end

return M
