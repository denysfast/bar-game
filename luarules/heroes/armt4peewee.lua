-- Peewee Prime, the Vanguard of the Swarm (armt4peewee, scavenger armpwt4 x1.8): a reckless brawler that is
-- stronger with an army around it (doc/v19-heroes/roster_arm.md 3). Numbers: luarules/configs/heroes/arm.lua.
--
--   a1 Pack Leader (passive): +1% damage and +0.5% damage reduction (max 15%) per allied mobile unit within 700
--      (counting at most `cap`); allied T1/T2 bots there get +speed and +damage.
--   a2 Jump Jets (active, map): a ballistic leap; the landing blasts radius 300 and throws units outward, then the
--      guns run hot (Hot Barrels: bigger white-blue plasma, +damage for 4 s).
--   a3 Bullet Hell (active, self): spins its guns and sprays every enemy in gun range (15 at most) at half speed.
--   ult Overrun (active, self): Peewee and every allied mobile unit within 900 charge - faster, harder hitting, Peewee
--      unstoppable; every enemy killed near it adds 0.5 s (up to +8 s).

local L = VFS.Include("luarules/heroes/armt4_lib.lua", nil, VFS.ZIP_FIRST)

local M = {}

local BLUE = { 0.45, 0.75, 1, 1 }
local PACK = { 0.4, 0.7, 1, 0.25 }

local function b(h, key)
	return h.def.cfg[key]
end

local function gunRange(api, unitID, h)
	local w, n = L.weapon(h, "emg")
	return w and (Spring.GetUnitWeaponState(unitID, n, "range") or w.range) or 810
end

local function alliedMobile(api, unitID, h, x, z, r)
	local out = {}
	for _, uid in ipairs(api.alliesIn(x, z, r, h.ally)) do
		if uid ~= unitID and not api.isHero(uid) and L.isMobile(uid) then
			out[#out + 1] = uid
		end
	end
	return out
end

---------------------------------------------------------------------------- a1 Pack Leader

local function pack(api, unitID, h, f)
	local r = api.rank(h, "a1")
	if r <= 0 then
		return
	end
	local a1 = b(h, "a1")
	local x, _, z = api.pos(unitID)
	local radius = a1.radius or 700
	local list = alliedMobile(api, unitID, h, x, z, radius)
	local cap = api.val(a1.cap, r)
	local n = math.min(cap, #list)
	if n ~= h.store.packN then
		h.store.packN = n
		if n > 0 then
			api.buff(unitID, h, "pack", nil, { damage = n * 0.01, armor = math.min(0.15, n * 0.005) })
		else
			api.unbuff(unitID, h, "pack")
		end
	end
	local bonus = api.val(a1.botBonus, r)
	local bots = 0
	for _, uid in ipairs(list) do
		if L.isBot(uid) then
			api.unitBuff(uid, "peewee_pack", 1.6, { speed = bonus, damage = bonus })
			bots = bots + 1
		end
	end
	local fx = api.fx
	if fx then
		if not h.store.packFx then
			h.store.packFx = fx.attach(unitID, "aura", { pattern = "runes", color = PACK, radius = radius })
		end
		local alpha = n >= cap and 0.55 or 0.12 + 0.25 * n / math.max(1, cap)
		if math.abs(alpha - (h.store.packAlpha or 0)) > 0.04 then
			h.store.packAlpha = alpha
			fx.set(h.store.packFx, { alpha = alpha, time = 0.5 })
		end
	end
	if f % 300 == 0 then
		api.log("armt4peewee a1 pack rank=%d allies=%d counted=%d bots=%d damage=+%.2f", r, #list, n, bots, n * 0.01)
	end
end

---------------------------------------------------------------------------- a2 Jump Jets

local function hotBarrels(api, unitID, h, r)
	local a2 = b(h, "a2")
	local t = a2.hotTime or 4
	api.buff(unitID, h, "hot", t, { damage = api.val(a2.hot, r) })
	api.swapWeapons(unitID, h, "hot")
	h.store.hotUntil = api.frame() + math.floor(t * 30)
	local fx = api.fx
	if fx then
		fx.attach(unitID, "electric", { color = BLUE, intensity = 0.4, ttl = t })
	end
	L.after(h, t * 30 + 1, function()
		if (h.store.hotUntil or 0) <= api.frame() and api.hero(unitID) then
			api.swapWeapons(unitID, h, nil)
		end
	end)
end

local function jump(api, unitID, h, r, tx, tz)
	local a2 = b(h, "a2")
	local x, y, z = api.pos(unitID)
	local range = api.val(a2.range, r)
	local dx, dz = tx - x, tz - z
	local d = math.sqrt(dx * dx + dz * dz)
	if d < 60 then
		return false
	end
	if d > range then
		tx, tz = x + dx / d * range, z + dz / d * range
		d = range
	end
	local dmg = api.val(a2.dmg, r) * api.power(h)
	local radius = a2.radius or 300
	local fx = api.fx
	local trail
	if fx then
		fx.flash(x, y + 20, z, { radius = 120, color = BLUE, ttl = 0.35 })
		fx.ring(x, z, { kind = "shock", r0 = 20, r1 = 200, color = BLUE, ttl = 0.35, width = 26 })
		trail = fx.attach(unitID, "trail", { color = BLUE, width = 22, length = 0.5, ttl = 1.4 })
	end
	return api.dash(unitID, h, tx, tz, { seconds = 1, arc = 120 + d * 0.25, untargetable = true,
		onLand = function(lx, lz)
			local hits = api.area(lx, lz, radius, dmg, unitID, { dtype = "plasma" })
			-- next frame: onLand runs inside the core's movement loop, a new movement must not start in it
			L.after(h, 1, function()
				for _, uid in ipairs(hits) do
					if L.alive(uid) then
						api.push(uid, lx, lz, 160, 0.4)
					end
				end
			end)
			local f2 = api.fx
			if f2 then
				f2.ring(lx, lz, { kind = "shock", r0 = 0, r1 = 330, color = { 0.5, 0.8, 1, 0.9 }, ttl = 0.45, width = 40 })
				f2.flash(lx, L.gy(lx, lz) + 30, lz, { radius = 200, color = BLUE, ttl = 0.4 })
				f2.detach(trail)
			end
			hotBarrels(api, unitID, h, r)
			api.log("armt4peewee a2 jump rank=%d dist=%d dmg=%d hits=%d hot=+%.2f", r, d, dmg, #hits, api.val(a2.hot, r))
		end })
end

---------------------------------------------------------------------------- a3 Bullet Hell

local function bulletHell(api, unitID, h, r)
	local a3 = b(h, "a3")
	local dur = api.val(a3.duration, r)
	api.buff(unitID, h, "bullethell", dur, { speed = -0.5 })
	api.active(unitID, "a3", dur)
	local f = api.frame()
	local st = { r = r, untilFrame = f + math.floor(dur * 30), next = f, ring = f, dealt = 0, ticks = 0, maxTargets = 0,
		dps = api.val(a3.dps, r) * api.power(h) }
	local fx = api.fx
	if fx then
		st.aura = fx.attach(unitID, "aura", { pattern = "heat", color = BLUE, radius = 150, ttl = dur })
		st.elec = fx.attach(unitID, "electric", { color = BLUE, intensity = 0.5, ttl = dur })
	end
	h.store.hell = st
	return true
end

local function hellFrame(api, unitID, h, f)
	local st = h.store.hell
	if f >= st.untilFrame then
		h.store.hell = nil
		api.log("armt4peewee a3 bullet hell over rank=%d dealt=%d ticks=%d maxTargets=%d", st.r, st.dealt, st.ticks, st.maxTargets)
		return
	end
	if f < st.next then
		return
	end
	st.next = f + 6
	local x, y, z = api.pos(unitID)
	local targets = api.nearestEnemies(x, z, gunRange(api, unitID, h), h.ally, 40)
	local fx = api.fx
	local n = 0
	local per = st.dps * 0.2
	for _, uid in ipairs(targets) do
		if n >= (b(h, "a3").targets or 15) then
			break
		end
		if api.seenBy(uid, h.ally) and not L.isAir(uid) then
			n = n + 1
			api.damage(uid, per, unitID, { dtype = "plasma" })
			st.dealt = st.dealt + per
			if fx then
				local tx, ty, tz = api.pos(uid)
				local a = math.random() * 6.283
				fx.beam(x + math.cos(a) * 30, y + 70, z + math.sin(a) * 30, tx, ty + 15, tz, { color = BLUE, width = 5, ttl = 0.09, flare = 0.6 })
			end
		end
	end
	st.ticks = st.ticks + 1
	st.maxTargets = math.max(st.maxTargets, n)
	if fx and f >= st.ring then
		st.ring = f + 15
		fx.ring(x, z, { kind = "shock", r0 = 20, r1 = 160, color = BLUE, ttl = 0.3, width = 20 })
	end
end

---------------------------------------------------------------------------- ult Overrun

local function applyOverrun(api, h, st, f)
	local left = (st.untilFrame - f) / 30
	if left <= 0 then
		return
	end
	for uid in pairs(st.units) do
		if L.alive(uid) then
			api.unitBuff(uid, "peewee_overrun", left, { speed = st.speed, damage = st.damage })
		else
			st.units[uid] = nil
		end
	end
end

local function overrun(api, unitID, h, r)
	local ult = b(h, "ult")
	local dur = api.val(ult.duration, r)
	local f = api.frame()
	local st = { r = r, untilFrame = f + math.floor(dur * 30), base = dur, ext = 0, speed = api.val(ult.speed, r),
		damage = api.val(ult.damage, r), units = {}, kills = 0, dirty = false }
	api.buff(unitID, h, "overrun", dur, { speed = st.speed, damage = st.damage, unstoppable = true })
	local x, y, z = api.pos(unitID)
	local list = alliedMobile(api, unitID, h, x, z, ult.radius or 900)
	local fx = api.fx
	for i, uid in ipairs(list) do
		st.units[uid] = true
		if fx and i <= 40 then
			fx.attach(uid, "trail", { color = BLUE, width = 8, length = 0.5, ttl = dur })
		end
	end
	applyOverrun(api, h, st, f)
	if fx then
		fx.ring(x, z, { kind = "shock", r0 = 0, r1 = ult.radius or 900, color = { 0.4, 0.75, 1, 0.8 }, ttl = 0.6, width = 50 })
		fx.flash(x, y + 50, z, { radius = 300, color = BLUE, ttl = 0.5 })
		st.fx = {
			fx.attach(unitID, "electric", { color = BLUE, intensity = 0.8 }),
			fx.attach(unitID, "aura", { pattern = "electric", color = BLUE, radius = 220 }),
			fx.attach(unitID, "trail", { color = BLUE, width = 18, length = 0.6 }),
		}
	end
	h.store.overrun = st
	api.active(unitID, "ult", dur)
	api.log("armt4peewee ult overrun rank=%d dur=%d allies=%d speed=+%.2f damage=+%.2f", r, dur, #list, st.speed, st.damage)
	return true
end

local function overrunFrame(api, unitID, h, f)
	local st = h.store.overrun
	if f >= st.untilFrame then
		h.store.overrun = nil
		api.unbuff(unitID, h, "overrun")
		L.detach(api, st.fx)
		api.log("armt4peewee ult overrun over: kills=%d extended=%.1f s", st.kills, st.ext)
		return
	end
	if st.dirty and f % 30 == 0 then
		st.dirty = false
		local left = (st.untilFrame - f) / 30
		api.buff(unitID, h, "overrun", left, { speed = st.speed, damage = st.damage, unstoppable = true })
		api.active(unitID, "ult", left)
		applyOverrun(api, h, st, f)
	end
end

function M.unitDied(api, unitID, h, deadID, deadDefID, x, z, allied)
	local st = h.store.overrun
	if st and not allied and st.ext < 8 then
		st.ext = st.ext + 0.5
		st.kills = st.kills + 1
		st.untilFrame = st.untilFrame + 15
		st.dirty = true
	end
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.packN = nil
	h.store.packFx = nil
end

function M.frame(api, unitID, h, f)
	L.tick(h, f)
	if f % 30 == 0 then
		pack(api, unitID, h, f)
	end
	if h.store.hell then
		hellFrame(api, unitID, h, f)
	end
	if h.store.overrun then
		overrunFrame(api, unitID, h, f)
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a2" then
		if targetID and not x then
			x, y, z = api.pos(targetID)
		end
		return x and jump(api, unitID, h, rank, x, z) or false
	elseif key == "a3" then
		if h.store.hell then
			return false
		end
		return bulletHell(api, unitID, h, rank)
	elseif key == "ult" then
		if h.store.overrun then
			return false
		end
		return overrun(api, unitID, h, rank)
	end
	return false
end

local function altarDir(api, h, x, z)
	local def = UnitDefNames.armt4gant
	local best, bd
	for _, uid in ipairs(def and Spring.GetTeamUnitsByDefs(h.team, def.id) or {}) do
		local ax, _, az = api.pos(uid)
		local d = L.dist(x, z, ax, az)
		if not bd or d < bd then
			best, bd = { ax, az }, d
		end
	end
	return best
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	local hp = L.hpFrac(unitID)
	if key == "a2" then
		local range = L.v(api, h, "a2", "range", rank)
		if hp < 0.25 then
			local a = altarDir(api, h, x, z)
			if a and L.dist(x, z, a[1], a[2]) > 400 then
				local d = L.dist(x, z, a[1], a[2])
				local s = math.min(range, 800, d) / d
				local tx, tz = x + (a[1] - x) * s, z + (a[2] - z) * s
				return tx, L.gy(tx, tz), tz
			end
			return nil
		end
		if hp > 0.5 then
			local cx, cz, _, n = L.cluster(api, x, z, range, 300, h.ally)
			if cx and n >= 6 and L.dist(x, z, cx, cz) >= 400 then
				return cx, L.gy(cx, cz), cz
			end
		end
	elseif key == "a3" then
		local n = #L.seenEnemies(api, x, z, gunRange(api, unitID, h), h.ally)
		if n >= 6 then
			return x, y, z
		end
	elseif key == "ult" then
		local allies = #alliedMobile(api, unitID, h, x, z, 900)
		local _, enemies = api.enemyCostNear(x, z, 1200, h.ally)
		if (allies >= 15 and enemies > 0) or (allies >= 8 and L.enemyHero(api, x, z, 1200, h.ally)) then
			return x, y, z
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	local st = h.store.overrun
	if st then
		L.detach(api, st.fx)
		h.store.overrun = nil
	end
	h.store.hell = nil
	h.store.packFx = nil
end

return M
