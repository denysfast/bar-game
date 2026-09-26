local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "AI Unjam",
		desc = "Skirmish AI bases: keep factory exit lanes free of AI buildings and dismantle AI buildings that jam AI units inside the base (modoption ai_unjam)",
		author = "denysfast",
		date = "2026-09-26",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

--[[
Why: BARb places statics by its own spacing rules (block_map.json); with a large economy the base
fills up with nanos, converters and generators until factory exits and the gaps between buildings
close, and new units pile up inside the base. Two mechanisms, AI teams only:

1. dismantle - a ground unit is "trapped" when it is older than TRAP_AGE, still within TRAP_RADIUS of
             where it was built, and it is enclosed: along each of TRAP_RAYS directions a move test
             with its own footprint (Spring.TestMoveOrder, terrain + structures) fails before
             TRAP_ESCAPE elmos. (Spring.RequestPath from synced code crashes the engine with the
             multithreaded pathfinder - do not use it here.) A unit with a far move/fight order
             that has not moved for STUCK_TIME counts too. >= JAM_MIN of them close together is a
             jam: the statics of that team (or of an allied AI team) around it, preferring those
             towards the enemy, close and cheap, are removed as if reclaimed and 90% of their metal
             is refunded to the owner. The cleared spot is closed for AI statics for CLEAR_KEEP.
             (The "stuck with an order" test alone misses most jams: when a path is blocked the
             engine drops the order and the unit just stands there idle.)
2. lanes   - (mode "lanes" only) every AI factory also gets an exit lane in its build facing where AI
             statics may not be started. Off by default: CircuitAI keeps retrying the same spot
             (thousands of refusals per match); the wider factory yards in BARb's block_map.json keep
             the exits free the native way.

3. tech ladder (modoption ai_techup, default on) - tech follows the economy: once an AI team earns
             TECH_T2_INCOME m/s and owns TECH_REQUIRE finished T2 factories, its T1 factories are
             recycled (90% refund), one per TECH_STEP, idle ones first; once it earns TECH_T3_INCOME
             and owns TECH_REQUIRE T3 gantries, its T2 land factories follow. New obsolete factories
             are refused. T2 air / T2 sea are the top of their line and are kept. The BARb script
             (Factory::TechUp) makes the same choice for new factories, so this mostly cleans up.

Human-owned units are never touched and human construction is never blocked.
Mode: modoption ai_unjam = on | lanes | off ("off" only logs jams, for A/B measurements).
]]

local mode = Spring.GetModOptions().ai_unjam or "on"
local techupOpt = Spring.GetModOptions().ai_techup
local techupOn = techupOpt == nil or techupOpt == true or techupOpt == "1" or techupOpt == "true"
local TECH_T2_INCOME = 150
local TECH_T3_INCOME = 800
local TECH_REQUIRE = 2
local TECH_STEP = 30 * 30
local lanesOn = (mode == "lanes")
local dismantleOn = (mode == "on" or mode == "lanes")

local CHECK = 90                 -- frames between scans (3 s)
local STUCK_TIME = 20 * 30       -- frames without progress before a unit counts as stuck
local STUCK_MOVE = 24            -- elmos: moved less than this since the last scan = no progress
local TARGET_MIN_DIST = 300      -- only units that want to go somewhere far are considered
local JAM_MIN = 2                -- trapped/stuck units within JAM_CELL of each other = a jam
local TRAP_AGE = 30 * 30         -- frames after completion before a unit near its birth place is suspicious
local TRAP_RADIUS = 450          -- elmos from the birth place
local TRAP_ESCAPE = 420          -- elmos: a unit that can walk this far in some direction is not enclosed
local TRAP_RAYS = 16
local TRAP_RECHECK = 15 * 30     -- frames between path tests of one unit
local TRAP_CHECKS_PER_SCAN = 8   -- path tests per team per scan (cost bound)
local JAM_CELL = 320
local BLOCKER_RADIUS = 360
local REMOVE_PER_JAM = 2
local REFUND = 0.9
local CLEAR_RADIUS = 200
local CLEAR_KEEP = 5 * 60 * 30   -- 5 min
local TEAM_COOLDOWN = 15 * 30
local LOG_PERIOD = 2 * 60 * 30

local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamLuaAI = Spring.GetTeamLuaAI
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitCommands = Spring.GetUnitCommands
local spGetUnitsInCylinder = Spring.GetUnitsInCylinder
local spGetUnitBuildFacing = Spring.GetUnitBuildFacing
local spAreTeamsAllied = Spring.AreTeamsAllied
local spDestroyUnit = Spring.DestroyUnit
local spAddTeamResource = Spring.AddTeamResource
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitIsBeingBuilt = Spring.GetUnitIsBeingBuilt
local spTestMoveOrder = Spring.TestMoveOrder
local spGetGroundHeight = Spring.GetGroundHeight
local spGetTeamStartPosition = Spring.GetTeamStartPosition
local mapX, mapZ = Game.mapSizeX, Game.mapSizeZ

local CMD_MOVE, CMD_FIGHT, CMD_ATTACK, CMD_PATROL = CMD.MOVE, CMD.FIGHT, CMD.ATTACK, CMD.PATROL

local gaiaTeamID = Spring.GetGaiaTeamID()
local aiTeams = {}
for _, teamID in ipairs(Spring.GetTeamList()) do
	if teamID ~= gaiaTeamID then
		local _, _, _, isAiTeam = spGetTeamInfo(teamID, false)
		local luaAI = spGetTeamLuaAI(teamID)
		local isGamemodeAI = luaAI and (luaAI:find("Raptors") or luaAI:find("Scavengers"))
		if isAiTeam and not isGamemodeAI then
			aiTeams[teamID] = { stuck = 0, removed = 0, denied = 0, jams = 0, lastAction = -TEAM_COOLDOWN,
				obsoleteTier = 0, recycled = 0, lastRecycle = -TECH_STEP }
		end
	end
end
if next(aiTeams) == nil then
	return -- nothing to do without skirmish AIs
end

-- unit classes
local isFactory, isStatic, isGroundMobile, isExempt, lane = {}, {}, {}, {}, {}
-- factory tier for the tech ladder: 1 = any T1 factory, 2 = T2 land factory (T2 air/sea are kept), 3 = T3
local facTier = {}
local T2_LAND = { armalab = true, armavp = true, coralab = true, coravp = true, legalab = true, legavp = true }
for udid, ud in pairs(UnitDefs) do
	local static = not ud.canMove or (ud.speed or 0) == 0
	if ud.isFactory then
		local tl = tonumber(ud.customParams and ud.customParams.techlevel or 1) or 1
		if tl <= 1 then facTier[udid] = 1 elseif tl >= 3 then facTier[udid] = 3 elseif T2_LAND[ud.name] then facTier[udid] = 2 else facTier[udid] = 22 end
	end
	if ud.isFactory and not ud.canFly then
		isFactory[udid] = true
		-- lane size in elmos from the factory footprint: T1 ~ 2x wide x4 long, bigger factories more
		local w = (ud.xsize or 8) * 8
		lane[udid] = { half = math.max(96, w * 0.75), len = math.max(420, w * 5) }
	end
	if static then
		isStatic[udid] = true
		-- never dismantle or block these: resource spots, commanders' stuff, factories themselves
		if (ud.extractsMetal or 0) > 0 or ud.needGeo or (ud.customParams and (ud.customParams.geothermal or ud.customParams.iscommander))
			or ud.isFactory then
			isExempt[udid] = true
		end
	elseif not ud.canFly and not ud.isBuilding then
		isGroundMobile[udid] = ud.moveDef and ud.moveDef.name or true
	end
end

-- factory lanes: id -> {x1, z1, x2, z2, team}
local lanes = {}
-- cleared spots: list of {x, z, untilFrame}
local cleared = {}

local function laneRect(unitID, udid)
	local x, _, z = spGetUnitPosition(unitID)
	local f = spGetUnitBuildFacing(unitID) or 0
	local l = lane[udid]
	local halfDepth = (UnitDefs[udid].zsize or 8) * 4
	-- facing 0 = south (+z), 1 = east (+x), 2 = north (-z), 3 = west (-x)
	if f == 0 then return x - l.half, z + halfDepth, x + l.half, z + halfDepth + l.len end
	if f == 2 then return x - l.half, z - halfDepth - l.len, x + l.half, z - halfDepth end
	if f == 1 then return x + halfDepth, z - l.half, x + halfDepth + l.len, z + l.half end
	return x - halfDepth - l.len, z - l.half, x - halfDepth, z + l.half
end

-- birth place of AI ground units: unitID -> {x, z, frame, lastTest, trapped}
local born = {}

-- where the enemy is, per AI team (first enemy start position); fallback map centre
local enemyGoal = {}
local function computeGoals()
	for teamID in pairs(aiTeams) do
		local gx, gz = mapX / 2, mapZ / 2
		for _, other in ipairs(Spring.GetTeamList()) do
			if other ~= gaiaTeamID and not spAreTeamsAllied(other, teamID) then
				local x, _, z = spGetTeamStartPosition(other)
				if x and x >= 0 then gx, gz = x, z; break end
			end
		end
		enemyGoal[teamID] = { gx, gz }
	end
end
computeGoals()
function gadget:GameStart()
	computeGoals() -- start positions are final only now
end

function gadget:UnitFinished(unitID, unitDefID, teamID)
	if not aiTeams[teamID] then return end
	if lanesOn and isFactory[unitDefID] then
		local x1, z1, x2, z2 = laneRect(unitID, unitDefID)
		lanes[unitID] = { x1, z1, x2, z2 }
	end
	if isGroundMobile[unitDefID] then
		local x, _, z = spGetUnitPosition(unitID)
		born[unitID] = { x, z, Spring.GetGameFrame(), -TRAP_RECHECK, false }
	end
end

function gadget:UnitDestroyed(unitID)
	lanes[unitID] = nil
	born[unitID] = nil
end

-- enclosed: no direction lets the unit walk TRAP_ESCAPE elmos (its footprint vs terrain and structures)
local rayDirs = {}
for i = 0, TRAP_RAYS - 1 do
	local a = i * 2 * math.pi / TRAP_RAYS
	rayDirs[#rayDirs + 1] = { math.cos(a), math.sin(a) }
end
local function enclosed(udid, x, z)
	if not spTestMoveOrder then return false end
	for _, d in ipairs(rayDirs) do
		local open = true
		for dist = 48, TRAP_ESCAPE, 40 do
			local px, pz = x + d[1] * dist, z + d[2] * dist
			if px < 8 or pz < 8 or px > mapX - 8 or pz > mapZ - 8
				or not spTestMoveOrder(udid, px, spGetGroundHeight(px, pz), pz, 0, 0, 0, true, true, false) then
				open = false
				break
			end
		end
		if open then
			return false
		end
	end
	return true
end

local function inBlockedArea(x, z, radius)
	for _, r in pairs(lanes) do
		if x + radius > r[1] and x - radius < r[3] and z + radius > r[2] and z - radius < r[4] then
			return true
		end
	end
	local frame = Spring.GetGameFrame()
	for i = #cleared, 1, -1 do
		local c = cleared[i]
		if c[3] < frame then
			table.remove(cleared, i)
		elseif (x - c[1]) ^ 2 + (z - c[2]) ^ 2 < (CLEAR_RADIUS + radius) ^ 2 then
			return true
		end
	end
	return false
end

-- deny AI statics inside lanes / freshly cleared spots
function gadget:AllowUnitCreation(unitDefID, builderID, builderTeam, x, y, z, facing)
	if not aiTeams[builderTeam] or not x or not isStatic[unitDefID] then
		return true
	end
	if isExempt[unitDefID] and not isFactory[unitDefID] then
		return true
	end
	if not dismantleOn and not (techupOn and isFactory[unitDefID]) then
		return true
	end
	if isFactory[unitDefID] then
		local tier = facTier[unitDefID]
		if techupOn and tier and tier <= aiTeams[builderTeam].obsoleteTier then
			aiTeams[builderTeam].denied = aiTeams[builderTeam].denied + 1
			return false -- tech has moved on for this team
		end
		return true -- a new factory decides its own lane; CircuitAI spaces factories itself
	end
	local ud = UnitDefs[unitDefID]
	local radius = math.max(ud.xsize or 2, ud.zsize or 2) * 4
	if inBlockedArea(x, z, radius) then
		aiTeams[builderTeam].denied = aiTeams[builderTeam].denied + 1
		return false
	end
	return true
end

-- stuck tracking
local track = {} -- unitID -> {x, z, since}

local function wantsToGo(unitID, x, z)
	local cmds = spGetUnitCommands(unitID, 1)
	local c = cmds and cmds[1]
	if not c then return nil end
	if c.id ~= CMD_MOVE and c.id ~= CMD_FIGHT and c.id ~= CMD_PATROL and c.id ~= CMD_ATTACK then return nil end
	local p = c.params
	if not p or #p < 3 then return nil end
	local dx, dz = p[1] - x, p[3] - z
	local d = math.sqrt(dx * dx + dz * dz)
	if d < TARGET_MIN_DIST then return nil end
	return dx / d, dz / d
end

local function dismantle(teamID, cx, cz, dirx, dirz, frame)
	local info = aiTeams[teamID]
	local candidates = {}
	for _, uid in ipairs(spGetUnitsInCylinder(cx, cz, BLOCKER_RADIUS)) do
		local owner = spGetUnitTeam(uid)
		local udid = spGetUnitDefID(uid)
		if udid and isStatic[udid] and not isExempt[udid] and aiTeams[owner]
			and (owner == teamID or spAreTeamsAllied(owner, teamID)) and not spGetUnitIsBeingBuilt(uid) then
			local x, _, z = spGetUnitPosition(uid)
			local dx, dz = x - cx, z - cz
			local dist = math.sqrt(dx * dx + dz * dz)
			local ahead = (dist > 1) and (dx * dirx + dz * dirz) / dist or 0
			-- prefer: in the way (ahead), close, cheap
			local score = dist - 180 * ahead + 0.02 * (UnitDefs[udid].metalCost or 0)
			candidates[#candidates + 1] = { uid = uid, owner = owner, udid = udid, score = score, x = x, z = z }
		end
	end
	table.sort(candidates, function(a, b) return a.score < b.score end)
	local removed = 0
	for i = 1, math.min(REMOVE_PER_JAM, #candidates) do
		local c = candidates[i]
		local ud = UnitDefs[c.udid]
		spAddTeamResource(c.owner, "metal", (ud.metalCost or 0) * REFUND)
		spDestroyUnit(c.uid, false, true)
		cleared[#cleared + 1] = { c.x, c.z, frame + CLEAR_KEEP }
		removed = removed + 1
		Spring.Echo(string.format("[unjam] team=%d removed %s (owner %d) at %d,%d for a jam at %d,%d",
			teamID, ud.name, c.owner, c.x, c.z, cx, cz))
	end
	cleared[#cleared + 1] = { cx, cz, frame + CLEAR_KEEP }
	for _, b in pairs(born) do
		if (b[1] - cx) ^ 2 + (b[2] - cz) ^ 2 < (BLOCKER_RADIUS * 2) ^ 2 then b[4] = -TRAP_RECHECK end
	end
	info.removed = info.removed + removed
	info.lastAction = frame
end

local spGetTeamResources = Spring.GetTeamResources
local spGetUnitIsBuilding = Spring.GetUnitIsBuilding

local function techLadder(teamID, info, frame)
	local _, _, _, income = spGetTeamResources(teamID, "metal")
	income = income or 0
	local byTier = { [1] = {}, [2] = {}, [3] = {}, [22] = {} }
	for _, uid in ipairs(spGetTeamUnits(teamID)) do
		local udid = spGetUnitDefID(uid)
		local tier = udid and facTier[udid]
		if tier and not spGetUnitIsBeingBuilt(uid) then
			local list = byTier[tier]
			list[#list + 1] = uid
		end
	end
	local t2count = #byTier[2] + #byTier[22]
	if income >= TECH_T3_INCOME and #byTier[3] >= TECH_REQUIRE then
		info.obsoleteTier = 2
	elseif income >= TECH_T2_INCOME and t2count >= TECH_REQUIRE then
		info.obsoleteTier = math.max(info.obsoleteTier, 1)
	end
	if info.obsoleteTier == 0 or frame - info.lastRecycle < TECH_STEP then
		return
	end
	local victim
	for tier = 1, info.obsoleteTier do
		for _, uid in ipairs(byTier[tier]) do
			if not spGetUnitIsBuilding(uid) then victim = uid; break end
			victim = victim or uid
		end
		if victim then break end
	end
	if victim then
		local ud = UnitDefs[spGetUnitDefID(victim)]
		spAddTeamResource(teamID, "metal", (ud.metalCost or 0) * REFUND)
		spDestroyUnit(victim, false, true)
		info.recycled = info.recycled + 1
		info.lastRecycle = frame
		Spring.Echo(string.format("[techup] team=%d recycled %s income=%d obsoleteTier=%d", teamID, ud.name, income, info.obsoleteTier))
	end
end

function gadget:GameFrame(frame)
	if frame % CHECK ~= 17 then
		return
	end
	if techupOn then
		for teamID, info in pairs(aiTeams) do
			techLadder(teamID, info, frame)
		end
	end
	for teamID, info in pairs(aiTeams) do
		local stuckList = {}
		local tests = 0
		local g = enemyGoal[teamID]
		for _, uid in ipairs(spGetTeamUnits(teamID)) do
			local udid = spGetUnitDefID(uid)
			if udid and isGroundMobile[udid] then
				local x, y, z = spGetUnitPosition(uid)
				local counted = false
				-- a) trapped near the birth place: the pathfinder cannot get out
				local b = born[uid]
				if b then
					if (x - b[1]) ^ 2 + (z - b[2]) ^ 2 > TRAP_RADIUS * TRAP_RADIUS then
						born[uid] = nil -- it left; stop watching
					elseif frame - b[3] >= TRAP_AGE then
						if frame - b[4] >= TRAP_RECHECK and tests < TRAP_CHECKS_PER_SCAN then
							tests = tests + 1
							b[4] = frame
							b[5] = enclosed(udid, x, z)
						end
						if b[5] then
							local dx, dz = g[1] - x, g[2] - z
							local d = math.max(1, math.sqrt(dx * dx + dz * dz))
							stuckList[#stuckList + 1] = { x = x, z = z, dx = dx / d, dz = dz / d }
							counted = true
						end
					end
				end
				-- b) has a far order but makes no progress
				local t = track[uid]
				local dirx, dirz = wantsToGo(uid, x, z)
				if not dirx then
					track[uid] = nil
				elseif not t then
					track[uid] = { x, z, frame }
				elseif (x - t[1]) ^ 2 + (z - t[2]) ^ 2 > STUCK_MOVE * STUCK_MOVE then
					t[1], t[2], t[3] = x, z, frame
				elseif frame - t[3] >= STUCK_TIME and not counted then
					stuckList[#stuckList + 1] = { x = x, z = z, dx = dirx, dz = dirz }
				end
			end
		end
		info.stuck = math.max(info.stuck, #stuckList)
		-- cluster into cells and act on the biggest jam
		if #stuckList >= JAM_MIN then
			local cells = {}
			for _, s in ipairs(stuckList) do
				local key = math.floor(s.x / JAM_CELL) .. ":" .. math.floor(s.z / JAM_CELL)
				local c = cells[key]
				if not c then c = { n = 0, x = 0, z = 0, dx = 0, dz = 0 }; cells[key] = c end
				c.n, c.x, c.z, c.dx, c.dz = c.n + 1, c.x + s.x, c.z + s.z, c.dx + s.dx, c.dz + s.dz
			end
			local best
			for _, c in pairs(cells) do
				if c.n >= JAM_MIN and (not best or c.n > best.n) then best = c end
			end
			if best then
				info.jams = info.jams + 1
				if dismantleOn and frame - info.lastAction >= TEAM_COOLDOWN then
					local n = best.n
					local len = math.sqrt(best.dx * best.dx + best.dz * best.dz)
					dismantle(teamID, best.x / n, best.z / n, len > 0 and best.dx / len or 0, len > 0 and best.dz / len or 0, frame)
				end
			end
		end
		if frame % LOG_PERIOD < CHECK then
			Spring.Echo(string.format("[unjam] t=%dmin team=%d mode=%s stuckPeak=%d jams=%d removed=%d deniedBuilds=%d lanes=%d obsoleteTier=%d recycled=%d",
				math.floor(frame / 1800), teamID, mode, info.stuck, info.jams, info.removed, info.denied, (function() local n = 0 for _ in pairs(lanes) do n = n + 1 end return n end)(), info.obsoleteTier, info.recycled))
			info.stuck, info.jams = 0, 0
		end
	end
	-- forget dead units
	if frame % (CHECK * 20) == 17 then
		for uid in pairs(track) do
			if not spGetUnitDefID(uid) then track[uid] = nil end
		end
	end
end
