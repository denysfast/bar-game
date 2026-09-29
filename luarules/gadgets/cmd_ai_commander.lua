local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "AI Commander",
		desc = "Lets an external commander (the player hosting the AIs, or modoption commander_players) take units away from skirmish AIs, order them, and pass strategy directives to the AI script",
		author = "denysfast",
		date = "2026-09-27",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = true,
	}
end

--[[
Protocol: Spring.SendLuaRulesMsg("aicmd:" .. json) from any client, typically the headless
commander client (LuaUI widget ai_commander_bridge.lua). The message rides the lockstep net,
so every client applies it identically.

  {"id":7, "team":2, "op":"order", "units":[..], "cmd":"fight", "pos":[x,z], "queue":false, "spread":true}
  {"id":8, "team":2, "op":"release", "units":[..]}        -- units omitted = release all of that team
  {"id":9, "team":2, "op":"ai", "text":"posture 1.5"}      -- forwarded to the AI script (AiLuaMessage)

Authority: the sender must host the AI of that team (Spring.GetAIInfo) or be named in the
modoption commander_players (comma separated). Units given an order are "commandeered": the AI
is told to let go of them (AI script UnitControl), and AllowCommand drops any non-Lua command
for them until they are released, so the AI cannot take them back by accident.

Results go back to LuaUI as Script.LuaUI.AICommanderEvent(json) on every client that has it.
]]

local PREFIX = "aicmd:"
local PREFIX_LEN = #PREFIX

if gadgetHandler:IsSyncedCode() then
	local Json = Json or VFS.Include("common/luaUtilities/json.lua")

	local spGetUnitTeam = Spring.GetUnitTeam
	local spGetUnitDefID = Spring.GetUnitDefID
	local spGetUnitPosition = Spring.GetUnitPosition
	local spGiveOrderToUnit = Spring.GiveOrderToUnit
	local spGetGroundHeight = Spring.GetGroundHeight
	local spValidUnitID = Spring.ValidUnitID
	local spSetUnitRulesParam = Spring.SetUnitRulesParam
	local spGetPlayerInfo = Spring.GetPlayerInfo
	local mapX, mapZ = Game.mapSizeX, Game.mapSizeZ

	local CMD_MOVE = CMD.MOVE
	local CMD_FIGHT = CMD.FIGHT
	local CMD_ATTACK = CMD.ATTACK
	local CMD_PATROL = CMD.PATROL
	local CMD_GUARD = CMD.GUARD
	local CMD_STOP = CMD.STOP
	local CMD_RECLAIM = CMD.RECLAIM
	local CMD_REPAIR = CMD.REPAIR
	local CMD_WAIT = CMD.WAIT
	local CMD_FIRE_STATE = CMD.FIRE_STATE
	local CMD_MOVE_STATE = CMD.MOVE_STATE
	local CMD_AREA_ATTACK = CMD.AREA_ATTACK
	local CMD_SELFD = CMD.SELFD

	local allowedNames = {}
	for name in string.gmatch(Spring.GetModOptions().commander_players or "", "[^,%s]+") do
		allowedNames[name] = true
	end

	-- skirmish AI teams (not Raptors/Scavengers) and who hosts them
	local aiTeams = {}
	for _, teamID in ipairs(Spring.GetTeamList()) do
		local _, _, _, isAiTeam = Spring.GetTeamInfo(teamID, false)
		if isAiTeam then
			local luaAI = Spring.GetTeamLuaAI(teamID)
			if not luaAI or luaAI == "" then
				aiTeams[teamID] = true
			end
		end
	end

	local commandeered = {} -- unitID -> teamID
	GG.AICommanderUnits = commandeered -- read by unit_t4_heroes.lua: hero escorts never take these
	local issuing = false -- true while this gadget gives orders (AllowCommand lets them through)
	local blockedCount = 0

	local function sendEvent(ev)
		SendToUnsynced("aicmd_evt", Json.encode(ev))
	end

	local function isAuthorized(playerID, teamID)
		if not aiTeams[teamID] then
			return false, "team " .. tostring(teamID) .. " is not a skirmish AI team"
		end
		local name = spGetPlayerInfo(playerID, false)
		if name and allowedNames[name] then
			return true
		end
		local _, _, hostingPlayerID = Spring.GetAIInfo(teamID)
		if hostingPlayerID == playerID then
			return true
		end
		return false, "player " .. tostring(name) .. " neither hosts the AI of team " .. teamID .. " nor is in commander_players"
	end

	local function forwardToAI(teamID, text)
		SendToUnsynced("aicmd_ai", teamID, text)
	end

	local function commandeer(unitID, teamID, fresh)
		if commandeered[unitID] then
			return
		end
		commandeered[unitID] = teamID
		spSetUnitRulesParam(unitID, "ai_cmdr", 1)
		fresh[#fresh + 1] = unitID
	end

	local function release(unitID)
		local teamID = commandeered[unitID]
		if not teamID then
			return
		end
		commandeered[unitID] = nil
		if spValidUnitID(unitID) then
			spSetUnitRulesParam(unitID, "ai_cmdr", 0)
			issuing = true
			spGiveOrderToUnit(unitID, CMD_STOP, {}, 0) -- idle unit: the AI picks it up on its next pass
			issuing = false
		end
	end

	local function clampPos(x, z)
		x = math.max(8, math.min(mapX - 8, x))
		z = math.max(8, math.min(mapZ - 8, z))
		return x, spGetGroundHeight(x, z), z
	end

	-- spread targets in a filled disc around the point so a group does not pile up on one spot
	local function spreadOffset(i, n)
		if n <= 1 then
			return 0, 0
		end
		local spacing = 36
		local angle = (i - 1) * 2.39996 -- golden angle: an even filled disc
		local r = spacing * math.sqrt(i - 1)
		return math.cos(angle) * r, math.sin(angle) * r
	end

	local simpleCmds = {
		move = CMD_MOVE, fight = CMD_FIGHT, patrol = CMD_PATROL,
		attack = CMD_ATTACK, guard = CMD_GUARD, stop = CMD_STOP, wait = CMD_WAIT,
		reclaim = CMD_RECLAIM, repair = CMD_REPAIR, area_attack = CMD_AREA_ATTACK,
		selfd = CMD_SELFD,
	}
	local fireStates = { hold = 0, ["return"] = 1, free = 2 }
	local moveStates = { hold = 0, maneuver = 1, roam = 2 }

	local function doOrder(req, teamID)
		local units = req.units or {}
		local cmdName = req.cmd or "move"
		local opts = req.queue and { "shift" } or 0
		local fresh = {}
		local ok, skipped = 0, 0

		-- collect valid units of the team
		local valid = {}
		for _, unitID in ipairs(units) do
			unitID = tonumber(unitID)
			if unitID and spValidUnitID(unitID) and spGetUnitTeam(unitID) == teamID then
				valid[#valid + 1] = unitID
			else
				skipped = skipped + 1
			end
		end
		if #valid == 0 then
			return false, "no valid units of team " .. teamID
		end
		if not (simpleCmds[cmdName] or cmdName == "firestate" or cmdName == "movestate" or cmdName == "build") then
			return false, "unknown cmd " .. tostring(cmdName)
		end
		if cmdName == "build" and not (UnitDefNames[req.def or ""] and req.pos) then
			return false, "build needs a known def and pos"
		end

		issuing = true
		for i, unitID in ipairs(valid) do
			commandeer(unitID, teamID, fresh)
			if cmdName == "firestate" then
				spGiveOrderToUnit(unitID, CMD_FIRE_STATE, { fireStates[req.state] or 2 }, 0)
			elseif cmdName == "movestate" then
				spGiveOrderToUnit(unitID, CMD_MOVE_STATE, { moveStates[req.state] or 1 }, 0)
			elseif cmdName == "build" then
				local ud = UnitDefNames[req.def or ""]
				if ud and req.pos then
					local x, y, z = clampPos(req.pos[1], req.pos[#req.pos])
					spGiveOrderToUnit(unitID, -ud.id, { x, y, z, tonumber(req.facing) or 0 }, opts)
				end
			else
				local cmdID = simpleCmds[cmdName]
				local params = {}
				if req.target then
					params = { tonumber(req.target) }
				elseif req.pos then
					local ox, oz = 0, 0
					if req.spread ~= false and (cmdName == "move" or cmdName == "fight" or cmdName == "patrol") then
						ox, oz = spreadOffset(i, #valid)
					end
					local x, y, z = clampPos(req.pos[1] + ox, req.pos[#req.pos] + oz)
					params = { x, y, z }
					if cmdName == "area_attack" or cmdName == "reclaim" or cmdName == "repair" then
						params[4] = tonumber(req.radius) or 200
					end
				end
				spGiveOrderToUnit(unitID, cmdID, params, opts)
			end
			ok = ok + 1
		end
		issuing = false

		if #fresh > 0 then
			forwardToAI(teamID, "detach " .. table.concat(fresh, ","))
		end
		return true, nil, { ordered = ok, skipped = skipped, newlyCommandeered = #fresh }
	end

	local function doRelease(req, teamID)
		local n = 0
		local ids = {}
		if req.units then
			for _, unitID in ipairs(req.units) do
				unitID = tonumber(unitID)
				if unitID and commandeered[unitID] == teamID then
					release(unitID)
					ids[#ids + 1] = unitID
					n = n + 1
				end
			end
		else
			for unitID, t in pairs(commandeered) do
				if t == teamID then
					ids[#ids + 1] = unitID
				end
			end
			for _, unitID in ipairs(ids) do
				release(unitID)
			end
			n = #ids
		end
		if #ids > 0 then
			forwardToAI(teamID, "attach " .. table.concat(ids, ","))
		end
		return true, nil, { released = n }
	end

	function gadget:RecvLuaMsg(msg, playerID)
		if msg:sub(1, PREFIX_LEN) ~= PREFIX then
			return
		end
		local okDecode, req = pcall(Json.decode, msg:sub(PREFIX_LEN + 1))
		if not okDecode or type(req) ~= "table" then
			sendEvent({ type = "result", ok = false, error = "bad json" })
			return true
		end
		local teamID = tonumber(req.team)
		local authorized, why = isAuthorized(playerID, teamID)
		if not authorized then
			sendEvent({ type = "result", id = req.id, ok = false, error = why })
			return true
		end

		local ok, err, data
		if req.op == "order" then
			ok, err, data = doOrder(req, teamID)
		elseif req.op == "release" then
			ok, err, data = doRelease(req, teamID)
		elseif req.op == "ai" then
			forwardToAI(teamID, tostring(req.text or ""))
			ok = true
		elseif req.op == "ping" then
			ok, data = true, { frame = Spring.GetGameFrame() }
		else
			ok, err = false, "unknown op " .. tostring(req.op)
		end
		sendEvent({ type = "result", id = req.id, team = teamID, op = req.op, ok = ok, error = err, data = data })
		return true
	end

	function gadget:AllowCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOptions, cmdTag, playerID, fromSynced, fromLua)
		if commandeered[unitID] and not issuing and not fromLua then
			blockedCount = blockedCount + 1
			return false
		end
		return true
	end

	function gadget:UnitDestroyed(unitID)
		commandeered[unitID] = nil
	end

	function gadget:UnitTaken(unitID)
		commandeered[unitID] = nil
	end

	-- AI script replies: ai.CallRules("aicmd_<kind> {json}"), raised only on the client hosting the AI.
	-- Nothing synced changes here; the reply just goes to this client's LuaUI.
	function gadget:RecvSkirmishAIMessage(aiTeam, dataStr)
		if dataStr:sub(1, 6) == "aicmd_" then
			SendToUnsynced("aicmd_aireply", aiTeam, dataStr)
			return ""
		end
	end

	local reportedBlocked = 0
	function gadget:GameFrame(n)
		if n % 900 == 0 and blockedCount ~= reportedBlocked then
			reportedBlocked = blockedCount
			Spring.SetGameRulesParam("ai_cmdr_blocked", blockedCount)
			Spring.Log("AI Commander", LOG.INFO, "commands to commandeered units dropped so far: " .. blockedCount)
		end
	end
else
	local spSendSkirmishAIMessage = Spring.SendSkirmishAIMessage

	local function toAI(_, teamID, text)
		-- only the client that hosts this AI actually delivers it; elsewhere it is a no-op
		spSendSkirmishAIMessage(teamID, text)
	end

	local function toUI(_, json)
		if Script.LuaUI("AICommanderEvent") then
			Script.LuaUI.AICommanderEvent(json)
		end
	end

	local function aiReply(_, aiTeam, dataStr)
		local kind, body = dataStr:match("^aicmd_(%w+) (.*)$")
		if kind then
			toUI(nil, '{"type":"ai_' .. kind .. '","team":' .. tostring(aiTeam) .. ',"data":' .. body .. "}")
		end
	end

	function gadget:RecvSkirmishAIMessage(aiTeam, dataStr)
		if dataStr:sub(1, 6) == "aicmd_" then
			aiReply(nil, aiTeam, dataStr)
			return ""
		end
	end

	function gadget:Initialize()
		gadgetHandler:AddSyncAction("aicmd_aireply", aiReply)
		gadgetHandler:AddSyncAction("aicmd_ai", toAI)
		gadgetHandler:AddSyncAction("aicmd_evt", toUI)
	end

	function gadget:Shutdown()
		gadgetHandler:RemoveSyncAction("aicmd_ai")
		gadgetHandler:RemoveSyncAction("aicmd_aireply")
		gadgetHandler:RemoveSyncAction("aicmd_evt")
	end
end
