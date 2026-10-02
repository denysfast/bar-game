-- Olympus, the Thunderer (armt4olympus, Vanguard x2.2): strategic artillery (doc/v19-heroes/roster_arm.md 8).
-- Numbers: luarules/configs/heroes/arm.lua.
--
--   a1 Cluster Shells (passive): every shell splits on impact into 2..7 bomblets (hero_bomblet) that scatter 150..350
--      around and deal a share of the shell's damage each (impact hook: shells hit the ground, not units).
--   a2 Spotter Flare (active, map): a flare lights an area for the whole team (api.reveal); Olympus' shells landing
--      in it hit harder.
--   a3 Siege Anchor (toggle): digs in for 1.5 s, then immobile with more range and damage and less damage taken.
--   ult Ion Lance (active, map): a 3 s shrinking rune warning, then an orbital lance: falloff damage, 2 s stun, and
--      three aftershocks one second apart (10% of the hit each).

local L = VFS.Include("luarules/heroes/armt4_lib.lua", nil, VFS.ZIP_FIRST)

local M = {}

local ICE = { 0.6, 0.85, 1, 1 }
local CYAN = { 0.5, 0.9, 1, 0.6 }

local function b(h, key)
	return h.def.cfg[key]
end

local SHELL = { shocker_low = true, shocker_high = true }

local function flareBonus(api, h, x, z)
	local f = api.frame()
	for _, fl in ipairs(h.store.flares) do
		if fl.untilFrame > f and L.dist(x, z, fl.x, fl.z) <= fl.radius then
			return fl.bonus
		end
	end
	return 0
end

---------------------------------------------------------------------------- a1 Cluster Shells

function M.impact(api, unitID, h, weaponDefID, x, y, z, projectileID)
	local r = api.rank(h, "a1")
	if r <= 0 or not SHELL[L.weaponKey(h, weaponDefID) or ""] then
		return
	end
	local a1 = b(h, "a1")
	local w = L.weapon(h, "shocker_low")
	local shell = (w and w.damage or 0) * api.dmgMult(h) * (1 + flareBonus(api, h, x, z))
	local n = api.val(a1.bomblets, r)
	local dmg = shell * api.val(a1.share, r)
	local gy = L.gy(x, z)
	local scatter = a1.scatter or 350
	local st = h.store
	for i = 1, n do
		local a = (i / n) * 6.283 + math.random() * 0.8
		local d = 150 + math.random() * (scatter - 150)
		local px, pz = x + math.cos(a) * d, z + math.sin(a) * d
		api.fire(h, "hero_bomblet", x + math.cos(a) * 40, gy + 220, z + math.sin(a) * 40, px, L.gy(px, pz), pz, { key = "a1", dmg = dmg, aoe = 90, dtype = "plasma",
			onHit = function(ix, iz, hits)
				st.bombHits = (st.bombHits or 0) + #hits
				if api.fx then
					api.fx.flash(ix, L.gy(ix, iz) + 20, iz, { radius = 40, color = ICE, ttl = 0.25 })
				end
			end })
	end
	if api.fx then
		api.fx.ring(x, z, { kind = "shock", r0 = 20, r1 = 200, color = ICE, ttl = 0.3, width = 24 })
	end
	st.splits = (st.splits or 0) + 1
	if st.splits % 5 == 1 then
		api.log("armt4olympus a1 cluster rank=%d shell=%d bomblets=%d x %d (bomblet hits so far %d)", r, shell, n, dmg, st.bombHits or 0)
	end
end

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	if #h.store.flares > 0 and SHELL[L.weaponKey(h, weaponDefID) or ""] then
		local x, _, z = api.pos(victimID)
		local bonus = x and flareBonus(api, h, x, z) or 0
		if bonus > 0 then
			damage = damage * (1 + bonus)
		end
	end
	return damage
end

---------------------------------------------------------------------------- a2 Spotter Flare

local function flare(api, unitID, h, r, tx, tz)
	local a2 = b(h, "a2")
	local x, y, z = api.pos(unitID)
	local range = api.val(a2.range, r)
	local d = L.dist(x, z, tx, tz)
	if d > range * 1.05 then
		tx, tz = x + (tx - x) / d * range, z + (tz - z) / d * range
	end
	local radius = api.val(a2.radius, r)
	local dur = api.val(a2.duration, r)
	local bonus = api.val(a2.bonus, r)
	local ally = h.ally
	if api.fx then
		api.fx.flash(x, y + 120, z, { radius = 90, color = CYAN, ttl = 0.3 })
	end
	local pid = api.fire(h, "hero_flare", x, y + 120, z, tx, L.gy(tx, tz) + 40, tz, { key = "a2", dmg = 1, aoe = 1,
		onHit = function(ix, iz)
			local f = api.frame()
			local fl = { x = ix, z = iz, radius = radius, untilFrame = f + math.floor(dur * 30), bonus = bonus, nextRing = f }
			h.store.flares[#h.store.flares + 1] = fl
			api.reveal(ix, iz, radius, dur, ally)
			if api.fx then
				api.fx.pillar(ix, iz, { radius = 40, height = 900, color = CYAN, ttl = dur })
				api.fx.flash(ix, L.gy(ix, iz) + 60, iz, { radius = 160, color = CYAN, ttl = 0.5 })
				fl.zone = api.fx.zone(ix, iz, { radius = radius, pattern = "glow", color = { 0.5, 0.9, 1, 0.12 }, ttl = dur })
			end
			api.log("armt4olympus a2 flare rank=%d radius=%d dur=%d bonus=+%.2f", r, radius, dur, bonus)
		end })
	return pid ~= nil
end

local function flareTick(api, unitID, h, f)
	local keep = {}
	for _, fl in ipairs(h.store.flares) do
		if fl.untilFrame > f then
			keep[#keep + 1] = fl
			if f >= fl.nextRing then
				fl.nextRing = f + 60
				if api.fx then
					api.fx.ring(fl.x, fl.z, { kind = "rune", r0 = fl.radius * 0.9, r1 = fl.radius, color = CYAN, ttl = 2, width = 20 })
				end
			end
		end
	end
	h.store.flares = keep
end

---------------------------------------------------------------------------- a3 Siege Anchor

local function anchorOn(api, unitID, h, r)
	local a3 = b(h, "a3")
	local f = api.frame()
	local st = { r = r, since = f, deployed = false }
	h.store.anchor = st
	api.buff(unitID, h, "anchor", nil, { immobile = true })
	Spring.GiveOrderToUnit(unitID, CMD.STOP, {}, 0)
	local x, _, z = api.pos(unitID)
	if api.fx then
		api.fx.ring(x, z, { kind = "hex", r0 = 60, r1 = 220, color = { 0.5, 0.75, 1, 0.8 }, ttl = a3.deploy or 1.5, width = 30 })
	end
	L.after(h, (a3.deploy or 1.5) * 30, function()
		if h.store.anchor ~= st then
			return
		end
		st.deployed = true
		api.buff(unitID, h, "anchor", nil, { immobile = true, range = api.val(a3.range, r), damage = api.val(a3.damage, r), armor = a3.armor or 0.2 })
		if api.fx then
			st.aura = api.fx.attach(unitID, "aura", { pattern = "runes", color = { 0.5, 0.75, 1, 0.5 }, radius = 200 })
		end
		api.log("armt4olympus a3 anchor deployed rank=%d range=+%.2f damage=+%.2f", r, api.val(a3.range, r), api.val(a3.damage, r))
	end)
	return true
end

function M.toggleOff(api, unitID, h, key, rank)
	if key ~= "a3" then
		return
	end
	local st = h.store.anchor
	h.store.anchor = nil
	api.unbuff(unitID, h, "anchor")
	if st then
		L.detach(api, st.aura)
		api.log("armt4olympus a3 anchor up after %.1f s", (api.frame() - st.since) / 30)
	end
end

local function anchorFrame(api, unitID, h, f)
	if not (h.ai or h.autocast) then
		return
	end
	local st = h.store.anchor
	if f - st.since < 60 then
		return
	end
	local x, _, z = api.pos(unitID)
	local cmds = Spring.GetUnitCommands(unitID, 1)
	local moving = cmds and cmds[1] and cmds[1].id == CMD.MOVE
	if moving or #api.enemiesIn(x, z, 900, h.ally) > 0 then
		api.toggleOff(unitID, h, "a3")
	end
end

---------------------------------------------------------------------------- ult Ion Lance

local function ionLance(api, unitID, h, r, tx, tz)
	local ult = b(h, "ult")
	local x, _, z = api.pos(unitID)
	local range = api.val(ult.range, r)
	local d = L.dist(x, z, tx, tz)
	if d > range * 1.05 then
		tx, tz = x + (tx - x) / d * range, z + (tz - z) / d * range
	end
	local R = api.val(ult.radius, r)
	local dmg = api.val(ult.dmg, r) * api.power(h)
	local ally = h.ally
	local fx = api.fx
	if fx then
		fx.ring(tx, tz, { kind = "rune", r0 = R, r1 = R * 0.1, color = { 0.6, 0.85, 1, 0.7 }, ttl = 3, width = 30, rot = 1.2 })
		fx.ring(tx, tz, { kind = "glow", r0 = R * 0.95, r1 = R, color = { 0.6, 0.85, 1, 0.3 }, ttl = 3, width = 20 })
		fx.pillar(tx, tz, { radius = 12, height = 3000, color = { 0.7, 0.9, 1, 0.5 }, ttl = 3, ring = false })
	end
	api.active(unitID, "ult", 6)
	local st = { total = 0 }
	L.after(h, 90, function()
		local hits = L.falloff(api, unitID, tx, tz, R, dmg, 0.3, { dtype = "electric", ally = ally })
		for _, uid in ipairs(hits) do
			api.stun(uid, ult.stun or 2, unitID)
		end
		local gy = L.gy(tx, tz)
		if api.fx then
			api.fx.pillar(tx, tz, { radius = R * 0.6, height = 3000, color = { 0.8, 0.95, 1, 1 }, ttl = 1.2 })
			api.fx.flash(tx, gy + 60, tz, { radius = R, color = { 0.8, 0.95, 1, 1 }, ttl = 0.5 })
			api.fx.ring(tx, tz, { kind = "shock", r0 = 0, r1 = R * 1.5, color = { 0.8, 0.95, 1, 1 }, ttl = 0.7, width = 60 })
			api.fx.ring(tx, tz, { kind = "electric", r0 = R * 0.3, r1 = R, color = "electric", ttl = 0.8, width = 30 })
		end
		api.log("armt4olympus ult ion lance rank=%d dmg=%d radius=%d hits=%d", r, dmg, R, #hits)
		for k = 1, 3 do
			L.after(h, k * 30, function()
				local h2 = L.falloff(api, unitID, tx, tz, R, dmg * 0.1, 0.3, { dtype = "electric", ally = ally })
				if api.fx then
					api.fx.ring(tx, tz, { kind = "electric", r0 = R * 0.2, r1 = R, color = "electric", ttl = 0.6, width = 26 })
				end
				api.log("armt4olympus ult aftershock %d dmg=%d hits=%d", k, dmg * 0.1, #h2)
			end)
		end
	end)
	return true
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.flares = {}
	h.store.anchor = nil
end

function M.frame(api, unitID, h, f)
	L.tick(h, f)
	if #h.store.flares > 0 then
		flareTick(api, unitID, h, f)
	end
	if h.store.anchor then
		anchorFrame(api, unitID, h, f)
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if key == "a3" then
		return anchorOn(api, unitID, h, rank)
	end
	if targetID and not x then
		x, y, z = api.pos(targetID)
	end
	if not x then
		return false
	end
	if key == "a2" then
		return flare(api, unitID, h, rank, x, z)
	elseif key == "ult" then
		return ionLance(api, unitID, h, rank, x, z)
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
		-- the centre of the enemy radar blips in range that are not in sight, else the attack target out of sight
		local sx, sz, n = 0, 0, 0
		for _, uid in ipairs(api.enemiesIn(x, z, range, h.ally)) do
			local los = Spring.GetUnitLosState(uid, h.ally, true)
			if los and los % 2 == 0 and math.floor(los / 2) % 2 == 1 then -- on radar, not in sight
				local ux, _, uz = api.pos(uid)
				sx, sz, n = sx + ux, sz + uz, n + 1
			end
		end
		if n >= 3 then
			return sx / n, L.gy(sx / n, sz / n), sz / n
		end
		local t, tx, ty, tz = api.target(unitID)
		if tx and not (t and api.seenBy(t, h.ally)) then
			return tx, ty, tz
		end
	elseif key == "a3" then
		if h.store.anchor then
			return nil
		end
		local cmds = Spring.GetUnitCommands(unitID, 1)
		if cmds and cmds[1] and cmds[1].id == CMD.MOVE then
			return nil
		end
		local reach = api.weaponReach(h)
		if #api.enemiesIn(x, z, 900, h.ally) == 0 and #L.seenEnemies(api, x, z, reach * 1.4, h.ally) > 0 then
			return x, y, z
		end
	elseif key == "ult" then
		local range = L.v(api, h, "ult", "range", rank)
		local hero = L.enemyHero(api, x, z, range, h.ally)
		if hero then
			local vx, _, vz = Spring.GetUnitVelocity(hero)
			if vx and math.sqrt(vx * vx + vz * vz) * 30 < 10 then
				local hx, hy, hz = api.pos(hero)
				return hx, hy, hz
			end
		end
		local cx, cz, cost = L.cluster(api, x, z, range, 500, h.ally)
		if cx and cost >= 30000 then
			return cx, L.gy(cx, cz), cz
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	if h.store.anchor then
		L.detach(api, h.store.anchor.aura)
		h.store.anchor = nil
	end
end

return M
