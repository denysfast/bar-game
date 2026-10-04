local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "AI General Ops",
		desc = "Strategic executors an AI general (external LLM commander) steers: expansion, economy, air wing, raids, commander guard",
		author = "denysfast",
		date = "2026-10-04",
		license = "GNU GPL, v2 or later",
		layer = 2,
		enabled = true,
	}
end

-- Custom (denysfast/bar-game), CUSTOM.md "Генералы ИИ". The general (an LLM agent behind the AI commander daemon)
-- never micros units: it switches these executors on per AI team through cmd_ai_commander.lua op "doctrine"
-- (ai_doctrine.lua hands every command it does not know to GG.AIGeneralOps.handle):
--   expand  {pos, builders}            a builder squad claims free metal spots (+ a light tower per 2 mexes)
--   eco     {build, count}             fusion / afus / converters / moho / energy by a borrowed constructor
--   air     {mode=build, count}        bombers queued on the air plants (an air plant is ordered if none)
--   air     {mode=strike, target}      the air wing (every bomber of the team) strikes: commander | base | [x,z] | unitID
--   air     {mode=hold|release}        the wing waits at the rally point / goes back to the AI
--   raid    {pos, size}                fast units hit enemy economy away from armies and towers
--   protect {on}                       commanders guard the factory nearest the start
--   report  {text}                     game rules param general_report_<ally> for the UI
-- Borrowed units sit in GG.AICommanderUnits (cmd_ai_commander.lua): the AI, the doctrine and the hero escorts
-- leave them alone until they are handed back ("attach").

if not gadgetHandler:IsSyncedCode() then
	local function aiMsg(_, teamID, text)
		Spring.SendSkirmishAIMessage(teamID, text)
	end
	function gadget:Initialize()
		gadgetHandler:AddSyncAction("genops_aimsg", aiMsg)
	end
	function gadget:Shutdown()
		gadgetHandler:RemoveSyncAction("genops_aimsg")
	end
	return
end

local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitAllyTeam = Spring.GetUnitAllyTeam
local spGetUnitIsDead = Spring.GetUnitIsDead
local spValidUnitID = Spring.ValidUnitID
local spGetGroundHeight = Spring.GetGroundHeight
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spGetUnitCommandCount = Spring.GetUnitCommandCount
local spGetUnitsInCylinder = Spring.GetUnitsInCylinder
local spGetUnitLosState = Spring.GetUnitLosState
local spTestBuildOrder = Spring.TestBuildOrder
local spSetUnitRulesParam = Spring.SetUnitRulesParam
local max, min, floor, sqrt, random = math.max, math.min, math.floor, math.sqrt, math.random

local GAME_SPEED = Game.gameSpeed
local MAPX, MAPZ = Game.mapSizeX, Game.mapSizeZ
local GAIA = Spring.GetGaiaTeamID()

---------------------------------------------------------------------------- static data

local SIDE_DEFS = {
	arm = { mex = "armmex", moho = "armmoho", tower = "armllt", fus = "armfus", afus = "armafus", conv = "armmakr",
		energy = { "armafus", "armfus", "armadvsol", "armsolar" }, airplant = "armap", strike = { "armthund" } },
	cor = { mex = "cormex", moho = "cormoho", tower = "corllt", fus = "corfus", afus = "corafus", conv = "cormakr",
		energy = { "corafus", "corfus", "coradvsol", "corsolar" }, airplant = "corap", strike = { "corshad" } },
	leg = { mex = "legmex", moho = "legmoho", tower = "leglht", fus = "legfus", afus = "legafus", conv = "legeconv",
		energy = { "legafus", "legfus", "legadvsol", "legsolar" }, airplant = "legap", strike = { "legmos" } },
}

local function defID(name)
	local ud = name and UnitDefNames[name]
	return ud and ud.id
end

local isCommander, mobileBuilder, isMex, isFactory, unitCost, unitSpeed, isArmedGround, isStrikeAir, isDefence = {}, {}, {}, {}, {}, {}, {}, {}, {}
local isAA = {}
for udid, ud in pairs(UnitDefs) do
	unitCost[udid] = ud.metalCost + ud.energyCost / 70
	unitSpeed[udid] = ud.speed or 0
	if ud.customParams and ud.customParams.iscommander then
		isCommander[udid] = true
	end
	if ud.isBuilder and ud.canMove and not ud.isFactory and (ud.buildSpeed or 0) > 0 and not isCommander[udid] then
		mobileBuilder[udid] = true
	end
	if ud.extractsMetal and ud.extractsMetal > 0 then
		isMex[udid] = true
	end
	if ud.isFactory then
		isFactory[udid] = true
	end
	local ground, air, bomb = false, false, false
	for _, w in ipairs(ud.weapons) do
		local wd = WeaponDefs[w.weaponDef]
		if wd and wd.damages and (wd.damages[0] or 0) > 1 then
			local cats = w.onlyTargets or {}
			if cats.vtol and not cats.surface and not cats.notair then
				air = true
			else
				ground = true
			end
			if wd.type == "AircraftBomb" then
				bomb = true
			end
		end
	end
	if ud.canFly and (bomb or ud.name == "legmos") then
		isStrikeAir[udid] = true
	end
	if not ud.canFly and (ud.speed or 0) > 0 and ground and not ud.isBuilder and not isCommander[udid] and not ud.name:find("t4", 1, true) then
		isArmedGround[udid] = true
	end
	if (ud.isImmobile or (ud.speed or 0) == 0) and (ground or air) then
		isDefence[udid] = true
		if air and not ground then
			isAA[udid] = true
		end
	end
	if (ud.speed or 0) > 0 and air and not ground and not ud.canFly then
		isAA[udid] = true -- mobile flak / AA bots count as AA cover too
	end
end

---------------------------------------------------------------------------- state

local teams = {}      -- teamID -> { side, ally, expand = {squads}, wing = {...}, raid = {...}, protect = bool }
local allyMemory = {} -- allyTeam -> { coms = {uid -> {x, z, f, team}}, eco = {uid -> {x, z, cost, def, f}} }

local function log(fmt, ...)
	Spring.Echo("[genops] " .. string.format(fmt, ...))
end

local function frameNow()
	return Spring.GetGameFrame()
end

local function toAI(teamID, text)
	SendToUnsynced("genops_aimsg", teamID, text)
end

local function taken()
	GG.AICommanderUnits = GG.AICommanderUnits or {}
	return GG.AICommanderUnits
end

local function alive(uid)
	return uid and spValidUnitID(uid) and not spGetUnitIsDead(uid)
end

local function borrow(teamID, ids)
	local t, fresh = taken(), {}
	for _, uid in ipairs(ids) do
		if not t[uid] then
			t[uid] = teamID
			spSetUnitRulesParam(uid, "ai_cmdr", 1)
			fresh[#fresh + 1] = uid
		end
	end
	if #fresh > 0 then
		toAI(teamID, "detach " .. table.concat(fresh, ","))
	end
end

local function handBack(teamID, ids)
	local t, back = taken(), {}
	for _, uid in ipairs(ids) do
		if t[uid] then
			t[uid] = nil
			if alive(uid) then
				spSetUnitRulesParam(uid, "ai_cmdr", 0)
				spGiveOrderToUnit(uid, CMD.STOP, {}, 0)
				back[#back + 1] = uid
			end
		end
	end
	if #back > 0 then
		toAI(teamID, "attach " .. table.concat(back, ","))
	end
end

local function sideOf(teamID)
	local _, _, _, _, side = Spring.GetTeamInfo(teamID, false)
	side = (side or ""):lower()
	for _, s in ipairs({ "arm", "cor", "leg" }) do
		if side:find(s) then
			return s
		end
	end
	for _, uid in ipairs(Spring.GetTeamUnits(teamID)) do
		local udid = spGetUnitDefID(uid)
		if isCommander[udid] then
			return UnitDefs[udid].name:sub(1, 3)
		end
	end
	return "arm"
end

local function startPos(teamID)
	local x, _, z = Spring.GetTeamStartPosition(teamID)
	if not x or x < 0 then
		x, z = MAPX / 2, MAPZ / 2
	end
	return x, z
end

local function enemyHome(teamID, ally)
	local sx, sz = startPos(teamID)
	local best, bx, bz
	for _, t in ipairs(Spring.GetTeamList()) do
		local _, _, isDead, _, _, a = Spring.GetTeamInfo(t, false)
		if a ~= ally and not isDead and t ~= GAIA then
			local x, z = startPos(t)
			local d = (x - sx) ^ 2 + (z - sz) ^ 2
			if not best or d < best then
				best, bx, bz = d, x, z
			end
		end
	end
	return bx or MAPX - sx, bz or MAPZ - sz
end

local function rally(teamID, ally)
	local sx, sz = startPos(teamID)
	local ex, ez = enemyHome(teamID, ally)
	local dx, dz = ex - sx, ez - sz
	local d = max(1, sqrt(dx * dx + dz * dz))
	return sx + dx / d * min(1200, d * 0.15), sz + dz / d * min(1200, d * 0.15)
end

local function teamState(teamID)
	local t = teams[teamID]
	if not t then
		local _, _, _, _, _, ally = Spring.GetTeamInfo(teamID, false)
		t = { team = teamID, ally = ally, side = sideOf(teamID), squads = {}, wing = { units = {}, mode = "off" }, raid = nil, protect = false, guards = {} }
		teams[teamID] = t
	end
	return t
end

local function sdef(t, key)
	return SIDE_DEFS[t.side] and SIDE_DEFS[t.side][key]
end

local function visibleTo(uid, ally)
	local los = spGetUnitLosState(uid, ally, true)
	return los and (los % 2 == 1)
end

local function enemyArmed(x, z, r, ally)
	local s = 0
	for _, uid in ipairs(spGetUnitsInCylinder(x, z, r)) do
		if spGetUnitAllyTeam(uid) ~= ally and spGetUnitTeam(uid) ~= GAIA and visibleTo(uid, ally) then
			local udid = spGetUnitDefID(uid)
			if isArmedGround[udid] or (isDefence[udid] and not isAA[udid]) or isCommander[udid] then
				s = s + (unitCost[udid] or 0) * (isDefence[udid] and 1.5 or 1)
			end
		end
	end
	return s
end

-- a free buildable spot near (x, z) for udid (spiral)
local function findSpot(udid, x, z, step)
	step = step or 64
	for ring = 0, 14 do
		local n = ring == 0 and 1 or ring * 8
		for i = 0, n - 1 do
			local a = i / n * 6.2832
			local px, pz = x + math.cos(a) * ring * step, z + math.sin(a) * ring * step
			px, pz = max(64, min(MAPX - 64, px)), max(64, min(MAPZ - 64, pz))
			local py = spGetGroundHeight(px, pz)
			if spTestBuildOrder(udid, px, py, pz, 0) > 0 then
				return px, pz
			end
		end
	end
end

local function canBuild(uid, udid)
	local ud = UnitDefs[spGetUnitDefID(uid) or -1]
	if not ud then
		return false
	end
	for _, b in ipairs(ud.buildOptions or {}) do
		if b == udid then
			return true
		end
	end
	return false
end

-- constructors of a team, idle ones and those near (x, z) first
local function pickBuilders(teamID, n, x, z, needDef)
	local t, cands = taken(), {}
	local owns = GG.AIDoctrine and GG.AIDoctrine.owns or {}
	for _, uid in ipairs(Spring.GetTeamUnits(teamID)) do
		local udid = spGetUnitDefID(uid)
		if mobileBuilder[udid] and not t[uid] and not owns[uid] and (not needDef or canBuild(uid, needDef)) then
			local _, _, _, _, bp = spGetUnitHealth(uid)
			local ux, _, uz = spGetUnitPosition(uid)
			if bp and bp >= 1 and ux then
				local idle = spGetUnitCommandCount(uid) == 0
				cands[#cands + 1] = { uid = uid, s = (ux - x) ^ 2 + (uz - z) ^ 2 + (idle and 0 or 4e6) }
			end
		end
	end
	table.sort(cands, function(a, b) return a.s < b.s end)
	local out = {}
	for i = 1, min(n, #cands) do
		out[i] = cands[i].uid
	end
	return out
end

---------------------------------------------------------------------------- memory: enemy commanders and economy

local function refreshMemory(ally, f)
	local m = allyMemory[ally]
	if not m then
		m = { coms = {}, eco = {}, frame = -999 }
		allyMemory[ally] = m
	end
	if f - m.frame < 45 then
		return m
	end
	m.frame = f
	for _, uid in ipairs(Spring.GetAllUnits()) do
		local team = spGetUnitTeam(uid)
		if team ~= GAIA and spGetUnitAllyTeam(uid) ~= ally and visibleTo(uid, ally) then
			local udid = spGetUnitDefID(uid)
			local x, _, z = spGetUnitPosition(uid)
			if x then
				if isCommander[udid] then
					m.coms[uid] = { x = x, z = z, f = f, team = team }
				elseif (isMex[udid] or isFactory[udid] or (UnitDefs[udid].energyMake or 0) > 5 or mobileBuilder[udid]) then
					m.eco[uid] = { x = x, z = z, f = f, cost = unitCost[udid] or 0 }
				end
			end
		end
	end
	for uid, c in pairs(m.coms) do
		if not alive(uid) then
			m.coms[uid] = nil
		end
	end
	for uid in pairs(m.eco) do
		if not alive(uid) or spGetUnitAllyTeam(uid) == ally then
			m.eco[uid] = nil
		end
	end
	return m
end

---------------------------------------------------------------------------- protect: commanders guard a factory at home

local function protectTick(t, f)
	local sx, sz = startPos(t.team)
	local fac, best
	for _, uid in ipairs(Spring.GetTeamUnits(t.team)) do
		local udid = spGetUnitDefID(uid)
		if isFactory[udid] then
			local _, _, _, _, bp = spGetUnitHealth(uid)
			local x, _, z = spGetUnitPosition(uid)
			if bp and bp >= 1 and x then
				local d = (x - sx) ^ 2 + (z - sz) ^ 2
				if not best or d < best then
					fac, best = uid, d
				end
			end
		end
	end
	if not fac then
		return
	end
	for _, uid in ipairs(Spring.GetTeamUnits(t.team)) do
		if isCommander[spGetUnitDefID(uid)] then
			if not t.guards[uid] then
				borrow(t.team, { uid })
				t.guards[uid] = true
			end
			if t.guardFac ~= fac or spGetUnitCommandCount(uid) == 0 then
				spGiveOrderToUnit(uid, CMD.GUARD, { fac }, 0)
			end
		end
	end
	t.guardFac = fac
end

local function protectOff(t)
	local ids = {}
	for uid in pairs(t.guards) do
		ids[#ids + 1] = uid
	end
	handBack(t.team, ids)
	t.guards, t.guardFac = {}, nil
end

---------------------------------------------------------------------------- expand: builder squads claim metal spots

local function spotFree(x, z)
	for _, uid in ipairs(spGetUnitsInCylinder(x, z, 60)) do
		if isMex[spGetUnitDefID(uid)] then
			return false
		end
	end
	return true
end

local function freeSpots(t, px, pz, radius)
	local spots = GG.resource_spot_finder and GG.resource_spot_finder.metalSpotsList or {}
	local out = {}
	for _, s in ipairs(spots) do
		local d2 = (s.x - px) ^ 2 + (s.z - pz) ^ 2
		if d2 < radius * radius and spotFree(s.x, s.z) and enemyArmed(s.x, s.z, 800, t.ally) < 200 then
			out[#out + 1] = { x = s.x, z = s.z, d = d2 }
		end
	end
	table.sort(out, function(a, b) return a.d < b.d end)
	return out
end

local function assignSpots(t, sq, f)
	local mex, tower = defID(sdef(t, "mex")), defID(sdef(t, "tower"))
	if not mex then
		return false
	end
	local spots = freeSpots(t, sq.x, sq.z, sq.radius)
	-- spots already claimed by another squad builder this round
	local claimed = {}
	for _, other in ipairs(t.squads) do
		for _, c in pairs(other.claims or {}) do
			claimed[floor(c[1]) .. ":" .. floor(c[2])] = true
		end
	end
	local any = false
	sq.claims = sq.claims or {}
	for _, uid in ipairs(sq.units) do
		if alive(uid) and spGetUnitCommandCount(uid) == 0 then
			local ux, _, uz = spGetUnitPosition(uid)
			local queue, cx, cz = 0, ux, uz
			for _ = 1, 3 do
				local pick, pd
				for _, s in ipairs(spots) do
					local key = floor(s.x) .. ":" .. floor(s.z)
					if not claimed[key] then
						local d = (s.x - cx) ^ 2 + (s.z - cz) ^ 2
						if not pd or d < pd then
							pick, pd = s, d
						end
					end
				end
				if not pick then
					break
				end
				claimed[floor(pick.x) .. ":" .. floor(pick.z)] = true
				sq.claims[uid] = { pick.x, pick.z }
				spGiveOrderToUnit(uid, -mex, { pick.x, spGetGroundHeight(pick.x, pick.z), pick.z, 0 }, queue > 0 and CMD.OPT_SHIFT or 0)
				sq.mexes = (sq.mexes or 0) + 1
				if tower and sq.mexes % 2 == 0 then
					local hx, hz = enemyHome(t.team, t.ally)
					local dx, dz = hx - pick.x, hz - pick.z
					local d = max(1, sqrt(dx * dx + dz * dz))
					local tx, tz = findSpot(tower, pick.x + dx / d * 140, pick.z + dz / d * 140, 48)
					if tx then
						spGiveOrderToUnit(uid, -tower, { tx, spGetGroundHeight(tx, tz), tz, 0 }, CMD.OPT_SHIFT)
					end
				end
				queue, cx, cz = queue + 1, pick.x, pick.z
				any = true
			end
		elseif alive(uid) then
			any = true -- still busy
		end
	end
	return any
end

local function expandStart(t, req, f)
	if #t.squads >= 2 then
		return false, "two expansion squads already work"
	end
	local x, z
	if type(req.pos) == "table" and tonumber(req.pos[1]) then
		x, z = tonumber(req.pos[1]), tonumber(req.pos[2])
	else
		x, z = startPos(t.team)
	end
	local n = max(2, min(8, tonumber(req.builders) or 4))
	local ids = pickBuilders(t.team, n, x, z)
	if #ids == 0 then
		return false, "no free constructor"
	end
	borrow(t.team, ids)
	local sq = { units = ids, x = x, z = z, radius = req.pos and 3000 or 6000, since = f, mexes = 0 }
	t.squads[#t.squads + 1] = sq
	assignSpots(t, sq, f)
	log("t=%d team=%d expand squad %d builders around %d,%d", floor(f / 1800), t.team, #ids, x, z)
	return true
end

local function expandTick(t, f)
	local keep = {}
	for _, sq in ipairs(t.squads) do
		local live = {}
		for _, uid in ipairs(sq.units) do
			if alive(uid) then
				live[#live + 1] = uid
			end
		end
		sq.units = live
		local busy = #live > 0 and assignSpots(t, sq, f)
		if #live == 0 or not busy or f - sq.since > 4 * 60 * GAME_SPEED then
			handBack(t.team, live)
			log("t=%d team=%d expand squad done: %d mexes ordered, %d builders back", floor(f / 1800), t.team, sq.mexes or 0, #live)
		else
			keep[#keep + 1] = sq
		end
	end
	t.squads = keep
end

---------------------------------------------------------------------------- eco: borrowed constructor builds at home

local function ecoBuild(t, req, f)
	local what = tostring(req.build or "energy")
	local count = max(1, min(12, tonumber(req.count) or 1))
	local udid
	if what == "fusion" then
		udid = defID(sdef(t, "fus"))
	elseif what == "afus" then
		udid = defID(sdef(t, "afus"))
	elseif what == "converters" then
		udid = defID(sdef(t, "conv"))
	elseif what == "moho" then
		udid = defID(sdef(t, "moho"))
	else
		for _, n in ipairs(sdef(t, "energy") or {}) do
			local d = defID(n)
			if d and #pickBuilders(t.team, 1, 0, 0, d) > 0 then
				udid = d
				break
			end
		end
	end
	if not udid then
		return false, "unknown build " .. what
	end
	local sx, sz = startPos(t.team)
	local ids = pickBuilders(t.team, what == "converters" and 2 or 1, sx, sz, udid)
	if #ids == 0 then
		return false, "no constructor can build " .. UnitDefs[udid].name .. ((what == "fusion" or what == "afus" or what == "moho") and " (needs T2 constructors)" or "")
	end
	borrow(t.team, ids)
	local placed = 0
	if what == "moho" then
		-- upgrade our own mexes nearest the base
		local mexes = {}
		for _, uid in ipairs(Spring.GetTeamUnits(t.team)) do
			local d = spGetUnitDefID(uid)
			if isMex[d] and d ~= udid then
				local x, _, z = spGetUnitPosition(uid)
				mexes[#mexes + 1] = { x = x, z = z, d = (x - sx) ^ 2 + (z - sz) ^ 2 }
			end
		end
		table.sort(mexes, function(a, b) return a.d < b.d end)
		for i = 1, min(count, #mexes) do
			local m = mexes[i]
			spGiveOrderToUnit(ids[1 + (i - 1) % #ids], -udid, { m.x, spGetGroundHeight(m.x, m.z), m.z, 0 }, CMD.OPT_SHIFT)
			placed = placed + 1
		end
	else
		local ox, oz = sx, sz
		local hx, hz = enemyHome(t.team, t.ally)
		local dx, dz = sx - hx, sz - hz
		local d = max(1, sqrt(dx * dx + dz * dz))
		ox, oz = sx + dx / d * 400, sz + dz / d * 400 -- behind the start, away from the enemy
		for i = 1, count do
			local px, pz = findSpot(udid, ox + random(-300, 300), oz + random(-300, 300), 96)
			if px then
				spGiveOrderToUnit(ids[1 + (i - 1) % #ids], -udid, { px, spGetGroundHeight(px, pz), pz, 0 }, CMD.OPT_SHIFT)
				placed = placed + 1
			end
		end
	end
	t.eco = t.eco or {}
	t.eco[#t.eco + 1] = { units = ids, since = f }
	log("t=%d team=%d eco %s x%d by %d constructors", floor(f / 1800), t.team, UnitDefs[udid].name, placed, #ids)
	return placed > 0, placed == 0 and "no place found" or nil
end

local function ecoTick(t, f)
	local keep = {}
	for _, job in ipairs(t.eco or {}) do
		local busy, live = false, {}
		for _, uid in ipairs(job.units) do
			if alive(uid) then
				live[#live + 1] = uid
				if spGetUnitCommandCount(uid) > 0 then
					busy = true
				end
			end
		end
		if busy and f - job.since < 6 * 60 * GAME_SPEED then
			keep[#keep + 1] = job
		else
			handBack(t.team, live)
		end
	end
	t.eco = keep
end

---------------------------------------------------------------------------- air: bombers built, gathered and sent

local function strikeDefs(t)
	local out = {}
	for _, n in ipairs(sdef(t, "strike") or {}) do
		local d = defID(n)
		if d then
			out[#out + 1] = d
		end
	end
	return out
end

local function airBuild(t, req, f)
	local count = max(1, min(60, tonumber(req.count) or 10))
	local plants = {}
	local defs = strikeDefs(t)
	for _, uid in ipairs(Spring.GetTeamUnits(t.team)) do
		local udid = spGetUnitDefID(uid)
		if isFactory[udid] then
			local _, _, _, _, bp = spGetUnitHealth(uid)
			for _, d in ipairs(defs) do
				if bp and bp >= 1 and canBuild(uid, d) then
					plants[#plants + 1] = { uid = uid, def = d }
					break
				end
			end
		end
	end
	if #plants == 0 then
		local ap = defID(sdef(t, "airplant"))
		local sx, sz = startPos(t.team)
		local ids = ap and pickBuilders(t.team, 2, sx, sz, ap) or {}
		if #ids == 0 then
			return false, "no air plant and no constructor for one"
		end
		local px, pz = findSpot(ap, sx + random(-500, 500), sz + random(-500, 500), 96)
		if not px then
			return false, "no place for an air plant"
		end
		borrow(t.team, ids)
		for _, uid in ipairs(ids) do
			spGiveOrderToUnit(uid, -ap, { px, spGetGroundHeight(px, pz), pz, 0 }, 0)
		end
		t.eco = t.eco or {}
		t.eco[#t.eco + 1] = { units = ids, since = f }
		t.wing.pendingBuild = (t.wing.pendingBuild or 0) + count
		log("t=%d team=%d air: building an air plant first, %d bombers wait", floor(f / 1800), t.team, count)
		return true
	end
	for i = 1, count do
		local p = plants[1 + (i - 1) % #plants]
		spGiveOrderToUnit(p.uid, -p.def, {}, 0)
	end
	log("t=%d team=%d air: %d strike aircraft queued on %d plants", floor(f / 1800), t.team, count, #plants)
	return true
end

local function wingUnits(t)
	local out, n = {}, 0
	for uid in pairs(t.wing.units) do
		if alive(uid) and spGetUnitTeam(uid) == t.team then
			out[#out + 1] = uid
			n = n + 1
		else
			t.wing.units[uid] = nil
		end
	end
	return out, n
end

local function wingCenter(ids)
	local sx, sz, n = 0, 0, 0
	for _, uid in ipairs(ids) do
		local x, _, z = spGetUnitPosition(uid)
		if x then
			sx, sz, n = sx + x, sz + z, n + 1
		end
	end
	if n == 0 then
		return nil
	end
	return sx / n, sz / n
end

local function wingCollect(t)
	if t.wing.mode == "off" then
		return
	end
	local fresh = {}
	local tk = taken()
	for _, uid in ipairs(Spring.GetTeamUnits(t.team)) do
		local udid = spGetUnitDefID(uid)
		if isStrikeAir[udid] and not t.wing.units[uid] and not tk[uid] then
			local _, _, _, _, bp = spGetUnitHealth(uid)
			if bp and bp >= 1 then
				t.wing.units[uid] = true
				fresh[#fresh + 1] = uid
			end
		end
	end
	if #fresh > 0 then
		borrow(t.team, fresh)
		local rx, rz = rally(t.team, t.ally)
		for _, uid in ipairs(fresh) do
			if t.wing.mode == "strike" and t.wing.tx then
				spGiveOrderToUnit(uid, CMD.FIGHT, { t.wing.tx, spGetGroundHeight(t.wing.tx, t.wing.tz), t.wing.tz }, 0)
			else
				spGiveOrderToUnit(uid, CMD.MOVE, { rx + random(-250, 250), 0, rz + random(-250, 250) }, 0)
			end
		end
	end
end

local function nearestCommander(t, x, z, f)
	local m = refreshMemory(t.ally, f)
	local best, bd, vis
	for uid, c in pairs(m.coms) do
		local seen = visibleTo(uid, t.ally)
		local d = (c.x - x) ^ 2 + (c.z - z) ^ 2
		-- a commander in sight now beats a remembered one
		local score = d + (seen and 0 or 4e7) + (f - c.f) * 1000
		if not bd or score < bd then
			best, bd, vis = uid, score, seen
		end
	end
	return best, vis
end

local function airStrike(t, req, f)
	local ids, n = wingUnits(t)
	t.wing.mode = "strike"
	t.wing.target = req.target or "commander"
	t.wing.startN = max(n, 1)
	t.wing.since = f
	t.wing.tx, t.wing.tz, t.wing.unit = nil, nil, nil
	local target = t.wing.target
	if type(target) == "table" and tonumber(target[1]) then
		t.wing.tx, t.wing.tz = tonumber(target[1]), tonumber(target[2])
	elseif tonumber(target) then
		t.wing.unit = tonumber(target)
	elseif target == "base" then
		t.wing.tx, t.wing.tz = enemyHome(t.team, t.ally)
	end
	log("t=%d team=%d air strike (%s) with %d aircraft", floor(f / 1800), t.team, tostring(type(target) == "table" and (target[1] .. "," .. target[2]) or target), n)
	return n > 0, n == 0 and "no strike aircraft yet (air mode=build first)" or nil
end

local function airTick(t, f)
	wingCollect(t)
	local ids, n = wingUnits(t)
	local w = t.wing
	if w.pendingBuild and w.pendingBuild > 0 and f % 300 < 30 then
		-- bombers wait for the air plant ordered by airBuild: queue them once it stands
		local ap = defID(sdef(t, "airplant"))
		for _, uid in ipairs(Spring.GetTeamUnits(t.team)) do
			if spGetUnitDefID(uid) == ap then
				local _, _, _, _, bp = spGetUnitHealth(uid)
				if bp and bp >= 1 then
					local count = w.pendingBuild
					w.pendingBuild = nil
					airBuild(t, { count = count }, f)
					break
				end
			end
		end
	end
	if n == 0 then
		return
	end
	local rx, rz = rally(t.team, t.ally)
	if w.mode == "hold" or w.mode == "build" then
		if f % 300 < 30 then
			for _, uid in ipairs(ids) do
				if spGetUnitCommandCount(uid) == 0 then
					spGiveOrderToUnit(uid, CMD.MOVE, { rx + random(-250, 250), 0, rz + random(-250, 250) }, 0)
				end
			end
		end
		return
	end
	if w.mode ~= "strike" then
		return
	end
	-- losses: back home at half the wing
	if n < w.startN * 0.5 and f - w.since > 10 * GAME_SPEED then
		log("t=%d team=%d air strike called off: %d of %d aircraft left", floor(f / 1800), t.team, n, w.startN)
		w.mode = "hold"
		w.lastResult = string.format("called off, %d of %d left", n, w.startN)
		for _, uid in ipairs(ids) do
			spGiveOrderToUnit(uid, CMD.MOVE, { rx + random(-250, 250), 0, rz + random(-250, 250) }, 0)
		end
		return
	end
	local cx, cz = wingCenter(ids)
	if w.target == "commander" or w.unit then
		local tgt, vis = w.unit, w.unit and alive(w.unit) and visibleTo(w.unit, t.ally)
		if w.target == "commander" then
			tgt, vis = nearestCommander(t, cx, cz, f)
		end
		if tgt and vis then
			if w.attacking ~= tgt or f % 150 < 30 then
				w.attacking = tgt
				for _, uid in ipairs(ids) do
					spGiveOrderToUnit(uid, CMD.ATTACK, { tgt }, 0)
				end
			end
		elseif tgt then
			local c = allyMemory[t.ally] and allyMemory[t.ally].coms[tgt]
			if c and (w.tx ~= c.x or w.tz ~= c.z) then
				w.tx, w.tz, w.attacking = c.x, c.z, nil
				for _, uid in ipairs(ids) do
					spGiveOrderToUnit(uid, CMD.MOVE, { c.x + random(-150, 150), 0, c.z + random(-150, 150) }, 0)
				end
			end
		elseif w.target == "commander" and not w.tx then
			-- nobody seen yet: fly over the enemy start to find one
			w.tx, w.tz = enemyHome(t.team, t.ally)
			for _, uid in ipairs(ids) do
				spGiveOrderToUnit(uid, CMD.MOVE, { w.tx + random(-200, 200), 0, w.tz + random(-200, 200) }, 0)
			end
		elseif w.unit and not alive(w.unit) then
			w.mode, w.lastResult = "hold", "target destroyed"
			log("t=%d team=%d air strike: target %d destroyed", floor(f / 1800), t.team, w.unit)
		end
	elseif w.tx then
		if f % 300 < 30 then
			for _, uid in ipairs(ids) do
				if spGetUnitCommandCount(uid) == 0 then
					spGiveOrderToUnit(uid, CMD.FIGHT, { w.tx + random(-300, 300), spGetGroundHeight(w.tx, w.tz), w.tz + random(-300, 300) }, 0)
				end
			end
		end
	end
end

---------------------------------------------------------------------------- raid: fast squad on enemy economy

local function raidTarget(t, sq, f)
	local m = refreshMemory(t.ally, f)
	local cx, cz = sq.cx or startPos(t.team), sq.cz
	local cells = {}
	for _, e in pairs(m.eco) do
		local key = floor(e.x / 1024) .. ":" .. floor(e.z / 1024)
		local c = cells[key]
		if not c then
			c = { x = 0, z = 0, v = 0, n = 0 }
			cells[key] = c
		end
		c.x, c.z, c.v, c.n = c.x + e.x, c.z + e.z, c.v + e.cost, c.n + 1
	end
	local best, bx, bz
	for _, c in pairs(cells) do
		local x, z = c.x / c.n, c.z / c.n
		local guard = enemyArmed(x, z, 900, t.ally)
		local d = cz and sqrt((x - cx) ^ 2 + (z - cz) ^ 2) or 0
		local score = c.v / (1 + guard / max(1, sq.strength or 1) * 3) / (1 + d / 4000)
		if guard < (sq.strength or 0) * 0.8 and (not best or score > best) then
			best, bx, bz = score, x, z
		end
	end
	return bx, bz
end

local function raidStart(t, req, f)
	if t.raid then
		return false, "a raid squad already runs"
	end
	local size = max(4, min(30, tonumber(req.size) or 12))
	local owns = GG.AIDoctrine and GG.AIDoctrine.owns or {}
	local tk = taken()
	local cands = {}
	for _, uid in ipairs(Spring.GetTeamUnits(t.team)) do
		local udid = spGetUnitDefID(uid)
		if isArmedGround[udid] and unitSpeed[udid] >= 75 and (unitCost[udid] or 0) <= 600 and not tk[uid] and not owns[uid] then
			local _, _, _, _, bp = spGetUnitHealth(uid)
			if bp and bp >= 1 then
				cands[#cands + 1] = { uid = uid, s = unitSpeed[udid] }
			end
		end
	end
	table.sort(cands, function(a, b) return a.s > b.s end)
	local ids, strength = {}, 0
	for i = 1, min(size, #cands) do
		ids[i] = cands[i].uid
		strength = strength + (unitCost[spGetUnitDefID(cands[i].uid)] or 0)
	end
	if #ids < 3 then
		return false, "fewer than 3 fast armed units free"
	end
	borrow(t.team, ids)
	t.raid = { units = ids, startN = #ids, strength = strength, since = f }
	if type(req.pos) == "table" and tonumber(req.pos[1]) then
		t.raid.tx, t.raid.tz = tonumber(req.pos[1]), tonumber(req.pos[2])
		t.raid.forced = true
	end
	log("t=%d team=%d raid squad %d units (%d metal)", floor(f / 1800), t.team, #ids, strength)
	return true
end

local function raidTick(t, f)
	local sq = t.raid
	if not sq then
		return
	end
	local live, strength = {}, 0
	for _, uid in ipairs(sq.units) do
		if alive(uid) then
			live[#live + 1] = uid
			strength = strength + (unitCost[spGetUnitDefID(uid)] or 0)
		end
	end
	sq.units, sq.strength = live, strength
	if #live < max(2, sq.startN * 0.4) then
		handBack(t.team, live)
		log("t=%d team=%d raid squad spent: %d of %d left, kills by the squad end here", floor(f / 1800), t.team, #live, sq.startN)
		t.raid = nil
		return
	end
	local cx, cz = wingCenter(live)
	sq.cx, sq.cz = cx, cz
	local arrived = sq.tx and (cx - sq.tx) ^ 2 + (cz - sq.tz) ^ 2 < 450 * 450
	if not sq.tx or (arrived and f - (sq.arrived or f) > 12 * GAME_SPEED) or f - (sq.retarget or 0) > 40 * GAME_SPEED then
		local tx, tz = raidTarget(t, sq, f)
		if not sq.forced or arrived then
			sq.forced = false
			if tx then
				sq.tx, sq.tz = tx, tz
			end
		end
		sq.retarget, sq.arrived = f, nil
		if sq.tx then
			for _, uid in ipairs(live) do
				spGiveOrderToUnit(uid, CMD.FIGHT, { sq.tx + random(-200, 200), spGetGroundHeight(sq.tx, sq.tz), sq.tz + random(-200, 200) }, 0)
			end
		end
	elseif arrived and not sq.arrived then
		sq.arrived = f
	end
	-- an army in the way: pull out and pick another target
	if enemyArmed(cx, cz, 900, t.ally) > strength * 1.2 then
		sq.retarget = 0
		sq.forced = false
	end
end

---------------------------------------------------------------------------- dispatch

local function status(t)
	local _, n = wingUnits(t)
	local squads = {}
	for _, sq in ipairs(t.squads) do
		squads[#squads + 1] = { builders = #sq.units, mexes = sq.mexes or 0 }
	end
	local rn = 0
	if t.raid then
		for _, uid in ipairs(t.raid.units) do
			if alive(uid) then
				rn = rn + 1
			end
		end
	end
	return {
		expand = squads,
		air = { mode = t.wing.mode, aircraft = n, target = type(t.wing.target) == "table" and table.concat(t.wing.target, ",") or t.wing.target,
			x = t.wing.tx and floor(t.wing.tx), z = t.wing.tz and floor(t.wing.tz), last = t.wing.lastResult, pending = t.wing.pendingBuild },
		raid = t.raid and { units = rn, start = t.raid.startN, x = t.raid.tx and floor(t.raid.tx), z = t.raid.tz and floor(t.raid.tz) } or nil,
		protect = t.protect,
	}
end

local function handle(teamID, cmd, req)
	local t = teamState(teamID)
	local f = frameNow()
	local ok, err = true, nil
	if cmd == "expand" then
		ok, err = expandStart(t, req, f)
	elseif cmd == "eco" then
		ok, err = ecoBuild(t, req, f)
	elseif cmd == "air" then
		local mode = tostring(req.mode or "build")
		if mode == "build" then
			if t.wing.mode == "off" then
				t.wing.mode = "build"
			end
			ok, err = airBuild(t, req, f)
		elseif mode == "strike" then
			ok, err = airStrike(t, req, f)
		elseif mode == "hold" then
			t.wing.mode = "hold"
		elseif mode == "release" then
			local ids = wingUnits(t)
			handBack(teamID, ids)
			t.wing = { units = {}, mode = "off" }
		else
			ok, err = false, "air mode: build|strike|hold|release"
		end
	elseif cmd == "raid" then
		if req.stop then
			if t.raid then
				handBack(teamID, t.raid.units)
				t.raid = nil
			end
		else
			ok, err = raidStart(t, req, f)
		end
	elseif cmd == "protect" then
		local on = req.on ~= false and req.on ~= 0 and req.on ~= "false"
		t.protect = on
		if on then
			protectTick(t, f)
		else
			protectOff(t)
		end
	elseif cmd == "report" then
		local text = tostring(req.text or ""):sub(1, 200)
		Spring.SetGameRulesParam("general_report_" .. t.ally, text)
		Spring.SetGameRulesParam("general_report_frame_" .. t.ally, f)
		log("t=%d ally=%d general: %s", floor(f / 1800), t.ally, text)
	else
		return false, "unknown doctrine command " .. tostring(cmd)
	end
	return ok, err, { executors = status(t) }
end

function gadget:Initialize()
	GG.AIGeneralOps = {
		handle = handle,
		status = function(teamID)
			return teams[teamID] and status(teams[teamID]) or nil
		end,
	}
end

function gadget:Shutdown()
	GG.AIGeneralOps = nil
end

function gadget:GameFrame(f)
	if f % 30 ~= 23 then
		return
	end
	for teamID, t in pairs(teams) do
		local _, _, isDead = Spring.GetTeamInfo(teamID, false)
		if not isDead then
			if t.protect and f % 300 == 23 then
				protectTick(t, f)
			end
			if #t.squads > 0 and f % 90 == 23 then
				expandTick(t, f)
			end
			if t.eco and #t.eco > 0 and f % 150 == 23 then
				ecoTick(t, f)
			end
			if t.wing.mode ~= "off" then
				airTick(t, f)
			end
			if t.raid and f % 60 == 23 then
				raidTick(t, f)
			end
		end
	end
end

function gadget:UnitDestroyed(unitID)
	for _, t in pairs(teams) do
		t.wing.units[unitID] = nil
		t.guards[unitID] = nil
	end
end
