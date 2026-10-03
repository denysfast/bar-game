local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name = "Multiplayer Save Game",
		desc = "Saves a multiplayer match on every client at the same frame, so the lobby can resume it",
		author = "denysfast",
		date = "2026",
		license = "GNU GPL, v2 or later",
		layer = -9999,
		enabled = true,
	}
end

--[[
	How a multiplayer save works (needs the denysfast Recoil build, see the server wiki):
		1. A player asks for a save (top bar "Save" or /mpsave [name]). Their client pauses the
		   game and sends "mpsave:req:<name>" as a LuaUI message.
		2. The server relays the pause before the message, so every client handles the request
		   at the same paused frame and writes the engine save Saves/mp/<name>.ssf (a full
		   snapshot, like a singleplayer save) plus Saves/mp/<name>.lua with the team layout.
		3. Each client answers "mpsave:ok:<frame>:<name>"; the autohost records the save from
		   these answers, and the requester unpauses once every player has answered.
		4. Later, "!loadsave <name>" in the battle room makes the server script carry
		   MPSaveFile/MPSaveFrame and every client loads its own copy instead of starting fresh.
]]

local SAVE_DIR = "Saves/mp"
local MSG_REQ = "mpsave:req:"
local MSG_OK = "mpsave:ok:"
local ACK_TIMEOUT = 60 -- wall-clock seconds the requester waits for every player before unpausing anyway

local spGetGameSpeed = Spring.GetGameSpeed
local spGetGameFrame = Spring.GetGameFrame
local spGetPlayerInfo = Spring.GetPlayerInfo
local spEcho = Spring.Echo

local myPlayerID = Spring.GetMyPlayerID()

local pendingSave -- this client: save requested, answer after the engine wrote it
local request -- requester only: waiting for every player's answer

local function sanitizeName(name)
	name = name and name:gsub("[^%w_%-]", "_") or ""
	if name == "" then
		name = "mp_" .. os.date("%Y%m%d_%H%M%S")
	end
	return name:sub(1, 64)
end

local function isPaused()
	return select(3, spGetGameSpeed())
end

local function activePlayers()
	local players = {}
	for _, playerID in ipairs(Spring.GetPlayerList()) do
		local name, active, spectator = spGetPlayerInfo(playerID, false)
		if name and active and not spectator then
			players[playerID] = name
		end
	end
	return players
end

local function teamLayout()
	local teams = {}
	for _, teamID in ipairs(Spring.GetTeamList()) do
		local _, leader, isDead, isAI, side, allyTeam = Spring.GetTeamInfo(teamID, false)
		local team = { team = teamID, allyTeam = allyTeam, side = side, dead = isDead, players = {} }
		if isAI then
			local _, aiName, hostPlayer, shortName, version = Spring.GetAIInfo(teamID)
			team.ai = { name = aiName, shortName = shortName, version = version, host = hostPlayer and spGetPlayerInfo(hostPlayer, false) }
		end
		if Spring.GetGaiaTeamID() == teamID then
			team.gaia = true
		end
		teams[#teams + 1] = team
	end
	for _, playerID in ipairs(Spring.GetPlayerList()) do
		local name, _, spectator, teamID = spGetPlayerInfo(playerID, false)
		if name and not spectator then
			for i = 1, #teams do
				if teams[i].team == teamID then
					teams[i].players[#teams[i].players + 1] = name
				end
			end
		end
	end
	return teams
end

local function writeSave(name)
	local frame = spGetGameFrame()
	Spring.CreateDir(SAVE_DIR)
	table.save({
		name = name,
		date = os.date("*t"),
		gameName = Game.gameName,
		gameVersion = Game.gameVersion,
		engineVersion = Engine.version,
		map = Game.mapName,
		gameframe = frame,
		playerName = spGetPlayerInfo(myPlayerID, false),
		teams = teamLayout(),
	}, SAVE_DIR .. "/" .. name .. ".lua")
	-- the engine snapshots the whole simulation at the top of the next main-loop pass;
	-- the game stays paused until every player answered, so all copies hold this frame
	Spring.SendCommands("save mp/" .. name .. " -y")
	pendingSave = { name = name, frame = frame, updates = 0 }
end

local function requestSave(name)
	if Spring.IsReplay() then
		spEcho("Multiplayer save: replays cannot be saved")
		return
	end
	if Spring.GetSpectatingState() then
		spEcho("Multiplayer save: only players can save the game")
		return
	end
	if spGetGameFrame() <= 0 then
		spEcho("Multiplayer save: the game has not started yet")
		return
	end
	if request then
		spEcho("Multiplayer save: a save is already in progress")
		return
	end
	name = sanitizeName(name)
	local wasPaused = isPaused()
	request = { name = name, wasPaused = wasPaused, started = Spring.GetTimer(), answers = {} }
	if not wasPaused then
		Spring.SendCommands("pause 1")
	end
	Spring.SendLuaUIMsg(MSG_REQ .. name)
end

local function finishRequest(timedOut)
	local players = activePlayers()
	local missing = {}
	for playerID, playerName in pairs(players) do
		if not request.answers[playerID] then
			missing[#missing + 1] = playerName
		end
	end
	if timedOut and #missing > 0 then
		spEcho("Multiplayer save \"" .. request.name .. "\": no answer from " .. table.concat(missing, ", ") .. " - they cannot resume this save")
	end
	spEcho("Multiplayer save \"" .. request.name .. "\" done. Resume it later in the battle room with: !loadsave " .. request.name)
	if not request.wasPaused and isPaused() then
		Spring.SendCommands("pause 0")
	end
	request = nil
end

function widget:RecvLuaMsg(msg, playerID)
	if msg:sub(1, #MSG_REQ) == MSG_REQ then
		local name = sanitizeName(msg:sub(#MSG_REQ + 1))
		-- every client sees the same pause state here: the pause was relayed before this message
		if not isPaused() then
			spEcho("Multiplayer save \"" .. name .. "\" failed: the game could not be paused")
			if request and request.name == name then
				request = nil
			end
			return true
		end
		if not Spring.IsReplay() then
			writeSave(name)
		end
		return true
	end

	if msg:sub(1, #MSG_OK) == MSG_OK then
		local frame, name = msg:sub(#MSG_OK + 1):match("^(%d+):(.+)$")
		if request and name == request.name then
			request.answers[playerID] = tonumber(frame)
			local players = activePlayers()
			for pid in pairs(players) do
				if not request.answers[pid] then
					return true
				end
			end
			finishRequest(false)
		end
		return true
	end
end

function widget:Update()
	if pendingSave then
		pendingSave.updates = pendingSave.updates + 1
		if pendingSave.updates >= 3 then
			spEcho("Multiplayer save written: " .. SAVE_DIR .. "/" .. pendingSave.name .. ".ssf (frame " .. pendingSave.frame .. ")")
			Spring.SendLuaUIMsg(MSG_OK .. pendingSave.frame .. ":" .. pendingSave.name)
			pendingSave = nil
		end
	end
	if request and Spring.DiffTimers(Spring.GetTimer(), request.started) > ACK_TIMEOUT then
		finishRequest(true)
	end
end

local function mpsaveCmd(_, _, params)
	requestSave(params and params[1])
	return true
end

function widget:Initialize()
	if Spring.IsReplay() then
		widgetHandler:RemoveWidget()
		return
	end
	WG.mpsave = {
		Request = requestSave,
		InProgress = function()
			return request ~= nil
		end,
	}
	widgetHandler:AddAction("mpsave", mpsaveCmd, nil, "t")
end

function widget:Shutdown()
	WG.mpsave = nil
	widgetHandler:RemoveAction("mpsave")
end
