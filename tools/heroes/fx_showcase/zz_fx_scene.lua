-- Hero FX showcase scene gadget (bench only; copied into the worktree by bench.sh as zz_hero_scene.lua).
-- Synced half drives most stations through the SYNCED GG.HeroFX (SendToUnsynced path);
-- the unsynced half drives the "zones" station and the stress test through the UNSYNCED GG.HeroFX.
local gadget = gadget
function gadget:GetInfo()
	return { name = "ZZ FX Scene", layer = 1000, enabled = true }
end

local S = VFS.Include("luarules/configs/zz_scene.lua")
local cx, cz = Game.mapSizeX / 2, Game.mapSizeZ / 2
local PI = math.pi
local function log(...)
	local t = {}
	for i, v in ipairs({ ... }) do t[i] = tostring(v) end
	Spring.Echo("[scene] " .. table.concat(t, " "))
end
local stationIndex = {}
for i, s in ipairs(S.stations) do stationIndex[s.name] = i end
local function stationPos(name)
	local s = S.stations[stationIndex[name]]
	return cx + s.dx, cz + s.dz
end
local function windowStart(name)
	return S.first + (stationIndex[name] - 1) * S.window
end
local function gy(x, z) return Spring.GetGroundHeight(x, z) end

if gadgetHandler:IsSyncedCode() then
	local U = {}
	local function spawn(name, x, z, team, facing)
		local u = Spring.CreateUnit(name, x, gy(x, z), z, facing or 0, team)
		if u then
			Spring.GiveOrderToUnit(u, CMD.FIRE_STATE, { 0 }, 0)
			Spring.GiveOrderToUnit(u, CMD.MOVE_STATE, { 0 }, 0)
		end
		return u
	end
	local function mid(u)
		local _, _, _, x, y, z = Spring.GetUnitPosition(u, true)
		return x, y, z
	end
	local function ring(name, n, r0, r1, a0, a1, team, unit)
		local sx, sz = stationPos(name)
		local t = {}
		for i = 1, n do
			local a = a0 + (a1 - a0) * (i - 1) / math.max(n - 1, 1)
			local r = r0 + (r1 - r0) * ((i * 0.37) % 1)
			t[#t + 1] = spawn(unit or "corak", sx + math.cos(a) * r, sz + math.sin(a) * r, team or 1, 0)
		end
		return t
	end

	local orbOpts = { color = "rage", radius = 16, height = 105, orbit = 45, speed = 0.45 }
	local droneOpts = { color = "red", radius = 9, height = 62, orbit = 58, speed = 0.4, count = 3, crackle = 1 }
	local ids = {}

	local act = {}
	function act.chain(t, f)
		if t == 10 or t == 40 or t == 70 or t == 100 then
			local x, y, z = mid(U.chain)
			local pts = { x, y + 25, z }
			for _, e in ipairs(U.chainE) do
				local ex, ey, ez = mid(e)
				if ex then pts[#pts + 1] = ex; pts[#pts + 1] = ey; pts[#pts + 1] = ez end
			end
			ids.chain = GG.HeroFX.chain(pts, { color = "electric", width = 3, ttl = 0.45, delay = 0.06 })
			if t == 10 then log("chain id", ids.chain, "points", #pts / 3) end
		end
	end
	function act.rage(t, f)
		if t > 0 and t % 12 == 0 then
			local ox, oy, oz = GG.HeroFX.orbPos(U.rage, orbOpts, f)
			local e = U.rageE[math.floor(t / 12) % #U.rageE + 1]
			local ex, ey, ez = mid(e)
			GG.HeroFX.bolt(ox, oy, oz, ex, ey, ez, { color = "rage", width = 4, ttl = 0.3 })
		end
		if t > 0 and t % 18 == 9 then
			local x, y, z = mid(U.rage)
			local e = U.rageE[math.floor(t / 18) % #U.rageE + 1]
			local ex, ey, ez = mid(e)
			GG.HeroFX.bolt(x, y + 20, z, ex, ey, ez, { color = "rage", width = 5, ttl = 0.35 })
		end
	end
	function act.emp(t, f)
		if t == 10 or t == 80 then
			local px, pz = stationPos("emp")
			pz = pz + 150
			GG.HeroFX.ring(px, pz, { kind = "electric", r0 = 20, r1 = 420, width = 30, ttl = 0.9, color = "emp" })
			GG.HeroFX.ring(px, pz, { kind = "shock", r0 = 10, r1 = 460, width = 40, ttl = 0.7, color = "emp" })
			GG.HeroFX.flash(px, gy(px, pz) + 25, pz, { radius = 140, color = "emp", ttl = 0.5 })
			for _, e in ipairs(U.empE) do
				GG.HeroFX.attach(e, "electric", { color = "emp", intensity = 0.8, ttl = 2 })
			end
		end
	end
	function act.sweep(t, f)
		if t == 10 then
			local x, y, z = Spring.GetUnitPosition(U.sweep)
			local R = 380
			for k = 0, 1 do
				local a = k * PI
				GG.HeroFX.beam(x, y + 38, z, x + R * math.cos(a), y, z + R * math.sin(a), { color = "laser", width = 6, ttl = 3, rot = 2 * PI / 3, ground = true })
				GG.HeroFX.ring(x, z, { kind = "sweep", r0 = 70, r1 = R, width = 26, ttl = 3.6, rot = 2 * PI / 3, angle = a, color = "fire" })
			end
			GG.HeroFX.attach(U.sweep, "aura", { pattern = "heat", radius = 150, ttl = 3.6 })
		end
	end
	function act.shield(t, f)
		if t >= 5 and t % 6 == 5 then
			local x, y, z = mid(U.shield)
			local e = U.shieldE[math.floor(t / 6) % #U.shieldE + 1]
			local ex, ey, ez = mid(e)
			local dx, dy, dz = ex - x, ey - y + 10, ez - z
			local l = math.sqrt(dx * dx + dy * dy + dz * dz)
			local hx, hy, hz = x + dx / l * 90, y + dy / l * 90, z + dz / l * 90
			GG.HeroFX.hit(ids.shield, hx, hy, hz)
			GG.HeroFX.beam(ex, ey + 6, ez, hx, hy, hz, { color = "green", width = 2.5, ttl = 0.16, flare = 0.7 })
		end
	end
	function act.resurrect(t, f)
		if t == 10 then
			local x, z = stationPos("resurrect")
			GG.HeroFX.pillar(x, z, { radius = 40, height = 900, color = "holy", ttl = 2.2 })
			GG.HeroFX.ring(x, z, { kind = "rune", r1 = 160, width = 34, ttl = 2.6, color = "gold" })
		end
	end
	function act.cloak(t, f)
		-- drive the unit on a fast circle with MoveCtrl so the trail has something to follow
		local x, z = stationPos("cloak")
		if t == -10 then
			Spring.MoveCtrl.Enable(U.cloak)
		end
		if t >= -10 and t < 140 then
			local a = (t + 10) * 0.045
			local px, pz = x + math.cos(a) * 260, z + math.sin(a) * 260
			Spring.MoveCtrl.SetPosition(U.cloak, px, gy(px, pz), pz)
			Spring.MoveCtrl.SetRotation(U.cloak, 0, -a, 0)
		end
	end
	function act.drones(t, f)
		if t > 0 and t % 9 == 0 then
			for k = 0, 2 do
				if ((t / 9) + k) % 2 == 0 then
					local ox, oy, oz = GG.HeroFX.orbPos(U.drones, droneOpts, f, k)
					local ex, ey, ez = mid(U.dronesE[k + 1])
					GG.HeroFX.beam(ox, oy, oz, ex, ey, ez, { color = "red", width = 2, ttl = 0.2, flare = 0.6 })
				end
			end
		end
	end
	function act.misc(t, f)
		if t == 20 then GG.HeroFX.set(ids.mark, { stacks = 3 }) end
		if t == 50 then GG.HeroFX.set(ids.mark, { stacks = 5 }) end
		if t == 30 then GG.HeroFX.set(ids.psphere, { radius = 150, time = 1.0 }) end
		if t == 40 then GG.HeroFX.set(ids.porb, { count = 5 }) end
	end
	function act.los(t, f)
		if t == 5 then
			local x, z = stationPos("los")
			GG.HeroFX.pillar(x - 700, z, { radius = 35, height = 700, color = "holy", ttl = 4 })
			GG.HeroFX.ring(x - 700, z, { kind = "rune", r1 = 140, ttl = 4, color = "gold" })
			-- out of our LOS: must not be drawn
			GG.HeroFX.pillar(x + 500, z + 650, { radius = 35, height = 700, color = "red", ttl = 4 })
			GG.HeroFX.ring(x + 500, z + 650, { kind = "rune", r1 = 140, ttl = 4, color = "red" })
			-- out of LOS, owned by our ally team (opts.ally -> "team" default): must be drawn
			GG.HeroFX.ring(x + 950, z - 150, { kind = "electric", r1 = 150, ttl = 4, color = "emp", ally = 0 })
			-- out of LOS, owner context set to one of our units: must be drawn
			local prev = GG.HeroFX.owner(U.misc)
			GG.HeroFX.pillar(x + 950, z + 350, { radius = 30, height = 600, color = "green", ttl = 4 })
			GG.HeroFX.owner(prev)
			-- out of LOS, owned by the enemy: must NOT be drawn
			GG.HeroFX.ring(x + 1100, z + 650, { kind = "hex", r1 = 150, ttl = 4, color = "red", ally = 1 })
			-- out of LOS but visible = "all": must be drawn
			GG.HeroFX.ring(x + 200, z - 650, { kind = "hex", r1 = 160, ttl = 4, color = "cyan", visible = "all" })
			log("los: in-LOS at", x - 700, z, "hidden at", x + 500, z + 650, "visible=all at", x + 200, z - 650,
				"inLos(hidden)", tostring(Spring.IsPosInLos(x + 500, 0, z + 650, 0)))
		end
	end

	function gadget:GameFrame(f)
		if f == 20 then
			for _, uid in ipairs(Spring.GetAllUnits()) do Spring.DestroyUnit(uid, false, true) end
		end
		if f == 30 then
			local x, z
			x, z = stationPos("chain"); U.chain = spawn("armthor", x, z - 150, 0, 0)
			U.chainE = ring("chain", 6, 180, 520, 0.6, 2.5, 1, "corak")
			x, z = stationPos("rage"); U.rage = spawn("armthor", x, z, 0, 0)
			U.rageE = ring("rage", 4, 260, 360, 0.3, 2.9, 1, "corak")
			x, z = stationPos("emp"); U.empF = spawn("armpw", x, z - 300, 0, 0)
			U.empE = ring("emp", 7, 60, 300, 0, 2 * PI * 6 / 7, 1, "corak")
			for _, e in ipairs(U.empE) do local ex, _, ez = Spring.GetUnitPosition(e); Spring.SetUnitPosition(e, ex, ez + 150) end
			x, z = stationPos("sweep"); U.sweep = spawn("corjugg", x, z, 0, 0)
			U.sweepE = ring("sweep", 8, 260, 340, 0, 2 * PI * 7 / 8, 1, "armpw")
			x, z = stationPos("shield"); U.shield = spawn("armraz", x, z, 0, 0)
			U.shieldE = ring("shield", 4, 260, 300, 0.5, 2.6, 1, "corak")
			x, z = stationPos("resurrect"); U.res = spawn("corjugg", x, z, 0, 0)
			x, z = stationPos("cloak"); U.cloak = spawn("armraz", x - 380, z, 0, 0); Spring.SetGameRulesParam("fx_follow_cloak", U.cloak)
			x, z = stationPos("drones"); U.drones = spawn("armraz", x, z, 0, 0)
			U.dronesE = ring("drones", 3, 230, 260, 0.4, 2.7, 1, "corak")
			x, z = stationPos("zones")
			for _, d in ipairs({ { -330, -330 }, { 330, -330 }, { -330, 330 }, { 330, 330 } }) do spawn("armpw", x + d[1], z + d[2], 0, 0) end
			x, z = stationPos("misc"); U.misc = spawn("armthor", x - 120, z + 120, 0, 0)
			U.miscE1 = spawn("corak", x + 160, z + 40, 1, 0)
			U.miscE2 = spawn("corak", x + 120, z + 230, 1, 0)
			U.miscE3 = spawn("corjugg", x - 250, z + 250, 1, 0)
			x, z = stationPos("los"); spawn("armpw", x - 700, z - 120, 0, 0)
			log("spawned", tostring(U.chain), tostring(U.rage), tostring(U.sweep), tostring(U.shield), "mapsize", Game.mapSizeX, Game.mapSizeZ)
		end
		if f == 60 then
			local FX = GG.HeroFX
			log("synced GG.HeroFX", tostring(FX), "synced flag", tostring(FX and FX.synced))
			FX.attach(U.rage, "electric", { color = "rage", intensity = 1.6 })
			FX.attach(U.rage, "orb", orbOpts)
			FX.attach(U.rage, "tint", { pattern = "heat", color = "rage", strength = 0.5 })
			ids.shield = FX.attach(U.shield, "sphere", { radius = 90, color = "shield", hex = true })
			FX.attach(U.cloak, "cloak", { color = "cloak" })
			FX.attach(U.cloak, "trail", { color = "cyan", width = 7, length = 0.8 })
			FX.attach(U.drones, "orb", droneOpts)
			ids.mark = FX.attach(U.miscE1, "mark", { color = "red", max = 5, stacks = 1 })
			FX.attach(U.misc, "link", { target = U.miscE2, style = "drain", color = "electric", width = 3 })
			FX.attach(U.misc, "link", { target = U.miscE1, style = "bolt", color = "purple", width = 2.5 })
			FX.attach(U.miscE3, "tint", { pattern = "stone" })
			local x, z = stationPos("misc")
			ids.porb = FX.attachPoint(x + 260, z - 170, "orb", { color = "purple", radius = 14, height = 60, orbit = 55, count = 2 })
			ids.psphere = FX.attachPoint(x - 250, z - 160, "sphere", { radius = 100, color = "gold" })
			FX.attachPoint(x - 250, z - 160, "aura", { pattern = "heal", radius = 110 })
			FX.attachPoint(x + 280, z + 260, "electric", { color = "electric", radius = 50 })
			log("attached shield", ids.shield, "mark", ids.mark, "psphere", ids.psphere)
		end
		for _, s in ipairs(S.stations) do
			local w0 = windowStart(s.name)
			if act[s.name] and f >= w0 - 10 and f < w0 + S.window then
				act[s.name](f - w0, f)
			end
		end
		if f == windowStart("stress") + 5 then
			local x, z = stationPos("stress")
			local FX = GG.HeroFX
			local n = 0
			local vis = { visible = "all" }
			for i = 1, 300 do
				local a = i * 2.39996
				local r = 60 + (i % 37) * 22
				local px, pz = x + math.cos(a) * r, z + math.sin(a) * r
				local py = gy(px, pz)
				local k = i % 6
				if k == 0 then
					FX.bolt(px, py + 200, pz, px + 60, py, pz + 40, { color = "electric", ttl = 4.5, visible = "all", impact = false })
				elseif k == 1 then
					FX.ring(px, pz, { kind = (i % 2 == 0) and "electric" or "shock", r1 = 70, width = 12, ttl = 4.5, visible = "all" })
				elseif k == 2 then
					FX.beam(px, py + 40, pz, px + 90, py + 10, pz, { color = "laser", width = 3, ttl = 4.5, visible = "all" })
				elseif k == 3 then
					FX.flash(px, py + 20, pz, { radius = 30, ttl = 4.5, color = "orange", ground = false, visible = "all" })
				elseif k == 4 then
					FX.attachPoint(px, pz, "orb", { color = "purple", radius = 8, height = 40, visible = "all", crackle = 1, ttl = 5 })
				else
					FX.zone(px, pz, { pattern = "hex", radius = 60, ttl = 4.5, visible = "all" })
				end
				n = n + 1
			end
			log("stress: issued", n, "effects")
		end
	end
else
	-- UNSYNCED half: drives the "zones" station and the stress debug through the unsynced API
	local done = {}
	function gadget:GameFrame(f)
		local FX = GG.HeroFX
		if not FX then return end
		if f == 60 then
			log("unsynced GG.HeroFX", tostring(FX), "synced flag", tostring(FX.synced))
		end
		local w0 = windowStart("zones")
		if f == w0 - 5 and not done.zones then
			done.zones = true
			local x, z = stationPos("zones")
			local pats = { "hex", "runes", "heal", "heat", "fog", "web", "swirl", "fire", "electric" }
			local k = 0
			for row = -1, 1 do
				for col = -1, 1 do
					k = k + 1
					local o = { radius = 125, pattern = pats[k], ttl = 5.5 }
					if pats[k] == "fire" then o.arc = 1.3; o.angle = 0; o.rot = 0.9; o.radius = 150 end
					local id = FX.zone(x + col * 300, z + row * 300, o)
					log("zone", pats[k], "id", id)
				end
			end
		end
		if f == windowStart("stress") then
			FX.debug(true)
		end
		if f % 150 == 0 and f > 100 then
			local st = FX.stats()
			local t = {}
			for kk, v in pairs(st) do t[#t + 1] = kk .. "=" .. tostring(v) end
			table.sort(t)
			log("fx stats", table.concat(t, " "))
		end
	end
end
