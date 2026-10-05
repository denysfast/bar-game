-- Boreas, the Firestorm (legt4boreas) - v23 Legion hero module, the 11th Legion hero (API: header of
-- luarules/gadgets/unit_t4_heroes.lua; numbers per rank: legt4boreas in luarules/configs/heroes/leg.lua).
-- Incendiary rocket artillery built on the Boreas starburst truck; an artillery hero (dmgScale 1/3 in
-- T4.heroBalance), every targeted ability stays within its weapon range.
--   a1 Scorched Earth (passive): every rack rocket impact leaves the ground burning for 4 s (at most `maxFires` at
--      once); enemies the fire touched take +vuln damage from Boreas (its rockets and its fires) while they burn.
--   a2 Hellfire Volley (map): the racks ripple-fire `count` incendiary rockets (firerocket weapondef) over ~1.2 s,
--      each on an enemy around the point (else the ground); every impact burns like Scorched Earth.
--   a3 Thermal Vent (self): a flame burst around Boreas, then for `duration` s it runs hot (speed, armour) and drops
--      a burning trail.
--   ult Firestorm (map): a rune marks the area for 1.5 s (time to walk out), then rockets fall on it from the sky for
--      6 s (70% on units) and the whole area burns.
local L = VFS.Include("luarules/heroes/legt4_lib.lua")
local C = L.C
local M = {}

local max, min, floor, sqrt, random, cos, sin = math.max, math.min, math.floor, math.sqrt, math.random, math.cos, math.sin
local BURN_FRAMES = 20 -- an enemy counts as burning this long after a fire tick touched it

local function cfg(h, key)
	return h.def.cfg[key]
end

---------------------------------------------------------------------------- a1 Scorched Earth

local function burningMult(api, h, uid)
	local r = api.rank(h, "a1")
	local until_ = h.store.burning[uid]
	if r <= 0 or not until_ or until_ < api.frame() then
		return 1
	end
	return 1 + api.val(cfg(h, "a1").vuln, r)
end

-- burning ground: `dps` (base, x ability power) every 0.5 s in `radius` for `seconds`; marks what it touches
local function groundFire(api, unitID, h, x, z, radius, dps, seconds, ringFx)
	local fx = L.fx(api)
	if ringFx then
		fx.ring(x, z, { kind = "fire", r0 = radius * 0.3, r1 = radius, color = C.EMBER, ttl = seconds })
	end
	local d = dps * api.power(h) * 0.5
	h.store.fires = h.store.fires + 1
	L.task(h, 15, seconds, function(f)
		for _, uid in ipairs(api.enemiesIn(x, z, radius, h.ally)) do
			api.damage(uid, d * burningMult(api, h, uid), unitID, { dtype = "flame" })
			h.store.burning[uid] = f + BURN_FRAMES
		end
	end, function()
		h.store.fires = max(0, h.store.fires - 1)
	end)
end

-- a Scorched Earth fire at an impact (rank 0: a weak one for the abilities, none for the rack rockets)
local function scorch(api, unitID, h, x, z, fromAbility)
	local r = api.rank(h, "a1")
	local a1 = cfg(h, "a1")
	if r <= 0 then
		if fromAbility then
			groundFire(api, unitID, h, x, z, 120, 150, 3, true)
		end
		return
	end
	if h.store.fires >= (a1.maxFires or 6) + (fromAbility and 6 or 0) then
		return
	end
	groundFire(api, unitID, h, x, z, api.val(a1.radius, r), api.val(a1.dps, r), a1.duration or 4, true)
end

---------------------------------------------------------------------------- a2 Hellfire Volley

local function rackPos(api, unitID, k)
	local x, y, z = api.pos(unitID)
	local a = (k or random(6)) * 1.047
	return x + cos(a) * 40, y + 60, z + sin(a) * 40
end

local function volley(api, unitID, h, r, x, z)
	local a2 = cfg(h, "a2")
	local count = api.val(a2.count, r)
	local dmg = api.val(a2.dmg, r) * api.power(h)
	local aoe = a2.aoe or 200
	local R = a2.radius or 320
	local fx = L.fx(api)
	fx.ring(x, z, { kind = "hex", r0 = R, r1 = R, color = L.a(C.EMBER, 0.5), width = 18, ttl = 2, rot = 0.6 })
	local st = { fired = 0, hits = 0 }
	local targets = L.enemies(api, x, z, R, h.ally, false)
	L.task(h, 4, 1.5, function()
		if st.fired >= count or not L.alive(unitID) then
			return false
		end
		st.fired = st.fired + 1
		local sx, sy, sz = rackPos(api, unitID, st.fired)
		fx.flash(sx, sy + 10, sz, { radius = 50, color = C.EMBER, ttl = 0.2, ground = false })
		local onHit = function(ix, iz, hits)
			st.hits = st.hits + #hits
			scorch(api, unitID, h, ix, iz, true)
		end
		-- each rocket on a different enemy first, the spare ones scatter over the area
		local t = targets[st.fired]
		if t and L.alive(t) then
			api.fire(h, "firerocket", sx, sy, sz, t, { key = "a2", dmg = dmg, aoe = aoe, dtype = "rocket", onHit = onHit })
		else
			local a, d = random() * 6.283, sqrt(random()) * R
			local px, pz = x + cos(a) * d, z + sin(a) * d
			api.fire(h, "firerocket", sx, sy, sz, px, L.groundY(px, pz), pz, { key = "a2", dmg = dmg, aoe = aoe, dtype = "rocket", onHit = onHit })
		end
	end, function()
		api.log("legt4boreas a2 volley rank=%d fired=%d dmg=%d hits=%d", r, st.fired, dmg, st.hits)
	end)
	return true
end

---------------------------------------------------------------------------- a3 Thermal Vent

local function vent(api, unitID, h, r)
	local a3 = cfg(h, "a3")
	local x, y, z = api.pos(unitID)
	if not x then
		return false
	end
	local fx = L.fx(api)
	local R = a3.burstRadius or 320
	local burst = api.val(a3.burst, r) * api.power(h)
	fx.flash(x, y + 40, z, { radius = 180, color = C.EMBER, ttl = 0.4 })
	fx.ring(x, z, { kind = "shock", r0 = 40, r1 = R, color = L.a(C.EMBER, 0.9), width = 24, ttl = 0.45 })
	fx.ring(x, z, { kind = "fire", r0 = 30, r1 = R, color = C.EMBER, ttl = 0.8 })
	local hit = api.area(x, z, R, burst, unitID, { dtype = "flame" })
	local dur = api.val(a3.duration, r)
	api.buff(unitID, h, "vent", dur, { speed = api.val(a3.speed, r), armor = api.val(a3.armor, r) })
	api.active(unitID, "a3", dur)
	local trail = fx.attach(unitID, "trail", { color = L.a(C.EMBER, 0.8), width = 40, length = 0.8 })
	L.task(h, 15, dur, function()
		local tx, _, tz = api.pos(unitID)
		if tx then
			scorch(api, unitID, h, tx, tz, true)
		end
	end, function()
		fx.detach(trail)
	end)
	api.log("legt4boreas a3 vent rank=%d burst=%d hit=%d dur=%.1f", r, burst, #hit, dur)
	return true
end

---------------------------------------------------------------------------- ult Firestorm

local function firestorm(api, unitID, h, r, x, z)
	local ult = cfg(h, "ult")
	local R = api.val(ult.radius, r)
	local dur = ult.duration or 6
	local warn = floor((ult.warn or 1.5) * 30)
	local count = api.val(ult.count, r)
	local dmg = api.val(ult.dmg, r) * api.power(h)
	local aoe = ult.aoe or 180
	local burn = api.val(ult.burn, r) * api.power(h) * 0.5
	local fx = L.fx(api)
	-- the telegraph: a rune and a shrinking ring for the warning time
	fx.ring(x, z, { kind = "rune", r0 = R, r1 = R, color = L.a(C.EMBER, 0.7), width = 26, ttl = dur + warn / 30, rot = 0.3 })
	fx.ring(x, z, { kind = "shock", r0 = R * 1.3, r1 = R * 0.2, color = L.a(C.SOLAR, 0.6), width = 22, ttl = warn / 30 })
	api.active(unitID, "ult", dur + warn / 30)
	local st = { n = 0, hits = 0, burned = 0 }
	local zone
	local every = max(3, floor(dur * 30 / count))
	local perStep = max(1, math.ceil(count / (dur * 30 / every)))
	L.task(h, every, dur, function(f, t)
		if not zone then
			zone = fx.zone(x, z, { radius = R, pattern = "fire", color = L.a(C.EMBER, 0.22), ttl = dur })
		end
		if (f - t.start) % 30 < every then
			fx.ring(x, z, { kind = "fire", r0 = R * 0.3, r1 = R, color = C.EMBER, ttl = 0.8 })
			-- the whole area burns, once a second at 2x the half-second share
			for _, uid in ipairs(api.enemiesIn(x, z, R, h.ally)) do
				api.damage(uid, burn * 2 * burningMult(api, h, uid), unitID, { dtype = "flame" })
				h.store.burning[uid] = f + 30 + BURN_FRAMES
				st.burned = st.burned + 1
			end
		end
		local list = api.enemiesIn(x, z, R, h.ally)
		for _ = 1, perStep do
			if st.n >= count then
				return
			end
			st.n = st.n + 1
			local tx, tz
			if #list > 0 and random() < 0.7 then
				tx, _, tz = api.pos(list[random(#list)])
				tx, tz = tx + (random() - 0.5) * 120, tz + (random() - 0.5) * 120
			else
				local a, d = random() * 6.283, sqrt(random()) * R
				tx, tz = x + cos(a) * d, z + sin(a) * d
			end
			local ty = L.groundY(tx, tz)
			api.fire(h, "firerocket", tx - 300 + random() * 120, ty + 1600, tz - 300 + random() * 120, tx, ty, tz, {
				key = "ult", dmg = dmg, aoe = aoe, dtype = "rocket",
				onHit = function(ix, iz, hits)
					fx.flash(ix, L.groundY(ix, iz) + 20, iz, { radius = 70, color = C.EMBER, ttl = 0.25 })
					st.hits = st.hits + #hits
				end,
			})
		end
	end, function()
		if zone then
			fx.detach(zone)
		end
		api.log("legt4boreas ult firestorm over rank=%d rockets=%d dmg=%d hits=%d burned=%d", r, st.n, dmg, st.hits, st.burned)
	end, warn)
	api.log("legt4boreas ult firestorm rank=%d radius=%d count=%d dmg=%d", r, R, count, dmg)
	return true
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.tasks = {}
	h.store.fires = 0
	h.store.burning = {}
	local ids = {}
	for _, w in pairs(h.def.weapons) do
		if w.key == "armtruck_rocket" then
			ids[w.wdid] = true
		end
	end
	h.store.rackIds = ids
end

function M.frame(api, unitID, h, f)
	L.runTasks(h, f)
	if f % 300 == 0 then
		local keep = {}
		for uid, until_ in pairs(h.store.burning) do
			if until_ >= f then
				keep[uid] = until_
			end
		end
		h.store.burning = keep
	end
end

-- the rack rockets: +vuln on burning targets; their impacts set the ground on fire
function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	if isParalyzer or damage <= 0 then
		return damage
	end
	return damage * burningMult(api, h, victimID)
end

function M.impact(api, unitID, h, weaponDefID, x, y, z, projectileID)
	if h.store.rackIds and h.store.rackIds[weaponDefID] then
		scorch(api, unitID, h, x, z, false)
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a2" and x then
		return volley(api, unitID, h, rank, x, z)
	elseif key == "a3" then
		return vent(api, unitID, h, rank)
	elseif key == "ult" and x then
		return firestorm(api, unitID, h, rank, x, z)
	end
	return false
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	local reach = api.weaponReach(h)
	if key == "a2" then
		local a2 = cfg(h, "a2")
		local n, cx, cz = L.cluster(api, x, z, min(api.val(a2.range, rank), reach), a2.radius or 320, h.ally, 3)
		if cx and n >= 4 then
			return cx, L.groundY(cx, cz), cz
		end
	elseif key == "a3" then
		-- an escape: hurt with enemies close, or a brawler on top of it
		local near = #L.enemies(api, x, z, 700, h.ally, true)
		if (L.hpFrac(unitID) < 0.5 and near >= 1) or near >= 6 or #L.enemyHeroes(api, x, z, 500, h.ally) > 0 then
			return x, y, z
		end
	elseif key == "ult" then
		local ult = cfg(h, "ult")
		local n, cx, cz, heroes = L.cluster(api, x, z, min(ult.range, reach), api.val(ult.radius, rank), h.ally, 3, 0.5)
		if cx and (n >= 10 or (heroes > 0 and n >= 6)) then
			return cx, L.groundY(cx, cz), cz
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	L.endTasks(h)
	h.store.burning = {}
	h.store.fires = 0
end

return M
