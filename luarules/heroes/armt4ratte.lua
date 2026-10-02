-- Ratte, the Landship (armt4ratte, scavenger armrattet4 x1.5): the slowest, hardest Armada hero, a fortress breaker
-- (doc/v19-heroes/roster_arm.md 6). Numbers: luarules/configs/heroes/arm.lua.
--
--   a1 Overpressure (passive): every 4th Main Battery salvo is drawn with the white-hot copies (api.swapWeapons "op"):
--      x1.5..3 damage, a 1.5x blast that throws units out and stuns them 1 s. Every salvo hits buildings harder.
--   a2 Creeping Barrage (active, map): 8..20 shells walk in a line from 400 in front of the point to 400 behind it
--      over 4 s (falling from the sky: hero_barrage), each telegraphed by a rune circle.
--   a3 Landship Plating (passive): damage from the front 90 degrees is reduced; crusher treads grind and slow the
--      enemies at the bow.
--   ult Main Gun (active, map): 2 s windup, then one super shell on a high arc: falloff damage (buildings x1.5) and an
--      8 s firestorm.

local L = VFS.Include("luarules/heroes/armt4_lib.lua", nil, VFS.ZIP_FIRST)

local M = {}

local ORANGE = { 1, 0.55, 0.2, 1 }
local HOT = { 1, 0.85, 0.6, 1 }

local function b(h, key)
	return h.def.cfg[key]
end

---------------------------------------------------------------------------- a1 Overpressure

function M.projectile(api, unitID, h, proID, weaponDefID)
	if api.rank(h, "a1") <= 0 or L.weaponKey(h, weaponDefID) ~= "arm_bosscannon" then
		return
	end
	local st = h.store
	local f = api.frame()
	local every = b(h, "a1").every or 4
	if f ~= st.salvoFrame then
		st.salvoFrame = f
		st.salvos = (st.salvos or 0) + 1
		local op = L.isCopy(h, weaponDefID, "op")
		if op then
			st.opSalvos = (st.opSalvos or 0) + 1
			L.after(h, 2, function() api.swapWeapons(unitID, h, nil) end)
			local fx = api.fx
			if fx then
				local px, py, pz = Spring.GetProjectilePosition(proID)
				if px then
					fx.flash(px, py, pz, { radius = 150, color = "orange", ttl = 0.3 })
				end
			end
		elseif (st.salvos + 1) % every == 0 then
			-- the next salvo is the Overpressure one: its projectiles are spawned as the copies
			L.after(h, 2, function() api.swapWeapons(unitID, h, "op") end)
		end
	end
	if L.isCopy(h, weaponDefID, "op") then
		local w = L.weapon(h, "arm_bosscannon")
		if w and Spring.SetProjectileDamages then
			local splash = math.sqrt(math.max(0.2, 1 + (h.mods and h.mods.splash or 0)))
			Spring.SetProjectileDamages(proID, 0, "damageAreaOfEffect", w.aoe * 1.5 * splash)
		end
	end
end

function M.hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer)
	local r = api.rank(h, "a1")
	if r <= 0 or isParalyzer or L.weaponKey(h, weaponDefID) ~= "arm_bosscannon" then
		return damage
	end
	local a1 = b(h, "a1")
	if L.isCopy(h, weaponDefID, "op") then
		damage = damage * api.val(a1.mult, r)
	end
	if L.isStructureDef(victimDefID) then
		damage = damage * (1 + api.val(a1.building, r))
	end
	return damage
end

function M.impact(api, unitID, h, weaponDefID, x, y, z, projectileID)
	if not L.isCopy(h, weaponDefID, "op") then
		return
	end
	local w = L.weapon(h, "arm_bosscannon")
	local R = (w and w.aoe or 350) * 1.5
	local hits = api.area(x, z, R, 0, unitID, { stun = 1 })
	for _, uid in ipairs(hits) do
		api.push(uid, x, z, 140, 0.4)
	end
	local fx = api.fx
	if fx then
		fx.ring(x, z, { kind = "shock", r0 = 20, r1 = R, color = { 1, 0.8, 0.5, 0.9 }, ttl = 0.5, width = 36 })
		fx.flash(x, L.gy(x, z) + 30, z, { radius = R * 0.4, color = HOT, ttl = 0.3 })
	end
	local f = api.frame()
	if f ~= h.store.opLogFrame then
		h.store.opLogFrame = f
		api.log("armt4ratte a1 overpressure impact rank=%d mult=%.2f blast=%d hits=%d", api.rank(h, "a1"), api.val(b(h, "a1").mult, api.rank(h, "a1")), R, #hits)
	end
end

---------------------------------------------------------------------------- a2 Creeping Barrage

local function barrage(api, unitID, h, r, px, pz)
	local a2 = b(h, "a2")
	local x, _, z = api.pos(unitID)
	local reach = api.weaponReach(h) * 1.6
	local dx, dz = px - x, pz - z
	local d = math.max(1, math.sqrt(dx * dx + dz * dz))
	if d > reach * 1.05 then
		px, pz = x + dx / d * reach, z + dz / d * reach
	end
	dx, dz = dx / d, dz / d
	local n = api.val(a2.count, r)
	local dmg = api.val(a2.dmg, r) * api.power(h)
	local radius = a2.radius or 220
	local dur = a2.duration or 4
	local st = { hits = 0, shells = 0 }
	for i = 0, n - 1 do
		local t = n > 1 and i / (n - 1) or 0
		local side = ((i % 3) - 1) * 60
		local sx = px + dx * (-400 + 800 * t) - dz * side
		local sz = pz + dz * (-400 + 800 * t) + dx * side
		L.after(h, 1 + math.floor(t * dur * 30), function()
			local gy = L.gy(sx, sz)
			local fromX, fromZ = sx - dx * 350, sz - dz * 350
			local pid = api.fire(h, "hero_barrage", fromX, gy + 1300, fromZ, sx, gy, sz, { key = "a2", dmg = dmg, aoe = radius, dtype = "plasma",
				onHit = function(ix, iz, hits)
					st.hits = st.hits + #hits
					st.shells = st.shells + 1
					if api.fx then
						api.fx.ring(ix, iz, { kind = "shock", r0 = 20, r1 = 260, color = ORANGE, ttl = 0.35, width = 28 })
					end
					if st.shells == n then
						api.log("armt4ratte a2 barrage rank=%d shells=%d dmg=%d hits=%d total=%d", r, n, dmg, st.hits, st.hits * dmg)
					end
				end })
			if api.fx and pid then
				api.fx.ring(sx, sz, { kind = "rune", r0 = 200, r1 = 250, color = { 1, 0.45, 0.2, 0.7 }, ttl = 1.4, width = 18 })
			end
		end)
	end
	api.log("armt4ratte a2 barrage cast rank=%d shells=%d dmg=%d at %d", r, n, dmg, L.dist(x, z, px, pz))
	return true
end

---------------------------------------------------------------------------- a3 Landship Plating

function M.damaged(api, unitID, h, damage, attackerID, weaponDefID, isParalyzer, ax, az)
	local r = api.rank(h, "a3")
	if r <= 0 or isParalyzer or not ax then
		return damage
	end
	local x, y, z = api.pos(unitID)
	local fx_, fz_ = L.facing(unitID)
	local dx, dz = ax - x, az - z
	local d = math.sqrt(dx * dx + dz * dz)
	if d < 1 then
		return damage
	end
	if (dx * fx_ + dz * fz_) / d >= 0.7071 then
		local st = h.store
		local f = api.frame()
		st.frontBlocked = (st.frontBlocked or 0) + damage * api.val(b(h, "a3").front, r) * (h.hpMult or 1)
		if api.fx and st.plateFx and f - (st.plateRipple or 0) >= 5 then
			st.plateRipple = f
			api.fx.hit(st.plateFx, x + dx / d * 180, y + 60, z + dz / d * 180)
		end
		return damage * (1 - api.val(b(h, "a3").front, r))
	end
	return damage
end

local function treads(api, unitID, h, f)
	local r = api.rank(h, "a3")
	if r <= 0 then
		return
	end
	local x, _, z = api.pos(unitID)
	local fx_, fz_ = L.facing(unitID)
	local rad = L.radius(unitID)
	local bx, bz = x + fx_ * rad * 0.9, z + fz_ * rad * 0.9
	local hits = api.area(bx, bz, 140, api.val(b(h, "a3").crush, r) * api.power(h) * 0.5, unitID, { dtype = "plasma" })
	for _, uid in ipairs(hits) do
		api.slow(uid, 0.5, 1)
	end
	if #hits > 0 and api.fx then
		api.fx.ring(bx, bz, { kind = "shock", r0 = 30, r1 = 150, color = { 0.8, 0.6, 0.4, 0.5 }, ttl = 0.3, width = 20 })
	end
	if f % 300 == 0 and (h.store.frontBlocked or 0) > 0 then
		api.log("armt4ratte a3 plating: frontal damage blocked so far %d (effective HP)", h.store.frontBlocked)
	end
end

---------------------------------------------------------------------------- ult Main Gun

local function mainGun(api, unitID, h, r, tx, tz)
	local ult = b(h, "ult")
	local x, y, z = api.pos(unitID)
	local range = api.val(ult.range, r)
	if L.dist(x, z, tx, tz) > range * 1.05 then
		local d = L.dist(x, z, tx, tz)
		tx, tz = x + (tx - x) / d * range, z + (tz - z) / d * range
	end
	local dmg = api.val(ult.dmg, r) * api.power(h)
	local fire = api.val(ult.fire, r) * api.power(h)
	local R = ult.radius or 500
	api.buff(unitID, h, "maingun", 2, { immobile = true })
	api.active(unitID, "ult", 5)
	local fx = api.fx
	local orb
	if fx then
		fx.attach(unitID, "aura", { pattern = "heat", color = "orange", radius = 260, ttl = 2 })
		orb = fx.attach(unitID, "orb", { color = HOT, radius = 8, height = 90, orbit = 0, crackle = 2, ttl = 2.1 })
		fx.set(orb, { radius = 45, time = 2 })
		fx.ring(tx, tz, { kind = "rune", r0 = R * 0.9, r1 = R, color = { 1, 0.2, 0.1, 0.8 }, ttl = 5.2, width = 30, rot = 0.6 })
	end
	local ally = h.ally
	L.after(h, 60, function()
		local hx, hy, hz = api.pos(unitID)
		if not hx then
			return
		end
		if api.fx then
			api.fx.flash(hx, hy + 90, hz, { radius = 200, color = "white", ttl = 0.4 })
			api.fx.ring(hx, hz, { kind = "shock", r0 = 40, r1 = 300, color = HOT, ttl = 0.4, width = 30 })
		end
		-- the shell climbs out of sight ...
		api.fire(h, "hero_supershell", hx, hy + 100, hz, hx + (tx - hx) * 0.05, hy + 2600, hz + (tz - hz) * 0.05, { ttl = 1.2 })
	end)
	-- ... and falls on the target
	L.after(h, 60 + 30, function()
		local gy = L.gy(tx, tz)
		api.fire(h, "hero_supershell", tx - (tx - x) * 0.2, gy + 2200, tz - (tz - z) * 0.2, tx, gy, tz, { key = "ult", dmg = 1, aoe = 1, dtype = "plasma",
			onHit = function(ix, iz)
				local hits = L.falloff(api, unitID, ix, iz, R, dmg, 0.3, { dtype = "plasma", ally = ally },
					function(uid) return L.isStructure(uid) and 1.5 or 1 end)
				local f2 = api.fx
				local iy = L.gy(ix, iz)
				if f2 then
					f2.flash(ix, iy + 60, iz, { radius = 700, color = HOT, ttl = 0.6 })
					f2.ring(ix, iz, { kind = "shock", r0 = 0, r1 = 900, color = HOT, ttl = 0.8, width = 60 })
					f2.pillar(ix, iz, { radius = 250, height = 1500, color = "orange", ttl = 0.7 })
					f2.zone(ix, iz, { radius = ult.fireRadius or 450, pattern = "fire", color = "fire", ttl = ult.fireTime or 8 })
				end
				h.store.storms[#h.store.storms + 1] = { x = ix, z = iz, untilFrame = api.frame() + (ult.fireTime or 8) * 30, dps = fire, dealt = 0 }
				api.log("armt4ratte ult main gun impact rank=%d dmg=%d radius=%d hits=%d firestorm=%d/s", r, dmg, R, #hits, fire)
			end })
	end)
	api.log("armt4ratte ult main gun cast rank=%d at %d", r, L.dist(x, z, tx, tz))
	return true
end

local function stormTick(api, unitID, h, f)
	local keep = {}
	for _, s in ipairs(h.store.storms) do
		if f < s.untilFrame then
			keep[#keep + 1] = s
			local hits = api.area(s.x, s.z, b(h, "ult").fireRadius or 450, s.dps * 0.5, unitID, { dtype = "flame", ally = h.ally })
			s.dealt = s.dealt + #hits * s.dps * 0.5
		else
			api.log("armt4ratte ult firestorm over: dealt=%d", s.dealt)
		end
	end
	h.store.storms = keep
end

---------------------------------------------------------------------------- hooks

function M.init(api, unitID, h)
	h.store.storms = {}
	h.store.plateFx = nil
	api.swapWeapons(unitID, h, nil)
end

function M.frame(api, unitID, h, f)
	L.tick(h, f)
	if f % 15 == 0 then
		treads(api, unitID, h, f)
		if #h.store.storms > 0 then
			stormTick(api, unitID, h, f)
		end
	end
	if api.rank(h, "a3") > 0 and not h.store.plateFx and api.fx then
		h.store.plateFx = api.fx.attach(unitID, "sphere", { radius = 190, color = { 1, 0.7, 0.4, 0.04 }, hex = true, fresnel = 2, height = 50 })
	end
end

function M.cast(api, unitID, h, key, rank, x, y, z, targetID)
	if targetID and not x then
		x, y, z = api.pos(targetID)
	end
	if not x then
		return false
	end
	if key == "a2" then
		return barrage(api, unitID, h, rank, x, z)
	elseif key == "ult" then
		return mainGun(api, unitID, h, rank, x, z)
	end
	return false
end

-- the best spot for the main gun: 40k+ enemy metal in 500, or 4+ buildings (defences count double)
local function gunSpot(api, unitID, h, range)
	local x, _, z = api.pos(unitID)
	local cands = L.seenEnemies(api, x, z, range, h.ally)
	local best, bx, bz = 0
	local step = math.max(1, math.floor(#cands / 40))
	for i = 1, #cands, step do
		local cx, _, cz = api.pos(cands[i])
		local cost, bld = 0, 0
		for _, uid in ipairs(api.enemiesIn(cx, cz, 500, h.ally)) do
			cost = cost + api.cost(uid)
			if L.isStructure(uid) then
				bld = bld + 1
			end
		end
		local score = cost + bld * 10000
		if (cost >= 40000 or bld >= 4) and score > best then
			best, bx, bz = score, cx, cz
		end
	end
	return bx, bz
end

function M.autocast(api, unitID, h, key, rank)
	local x, y, z = api.pos(unitID)
	if not x then
		return nil
	end
	if key == "a2" then
		local reach = api.weaponReach(h) * 1.6
		local cx, cz, _, n = L.cluster(api, x, z, reach, 400, h.ally)
		if cx and n >= 6 then
			return cx, L.gy(cx, cz), cz
		end
		local bx, bz = gunSpot(api, unitID, h, reach)
		if bx then
			return bx, L.gy(bx, bz), bz
		end
	elseif key == "ult" then
		local bx, bz = gunSpot(api, unitID, h, L.v(api, h, "ult", "range", rank))
		if bx then
			return bx, L.gy(bx, bz), bz
		end
	end
	return nil
end

function M.destroyed(api, unitID, h)
	api.swapWeapons(unitID, h, nil)
end

return M
