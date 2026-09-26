local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name = "AI Commander Bridge",
		desc = "Streams the game state per ally team to an external commander over TCP and relays its orders to the AI Commander gadget. Inactive unless springsettings AICommanderBridge = host:port",
		author = "denysfast",
		date = "2026-09-27",
		license = "GNU GPL, v2 or later",
		layer = -100,
		enabled = true,
	}
end

--[[
Wire format: one JSON object per line, both directions.
  widget -> daemon: hello (once per connection: map, catalog, teams), snap (every SnapFrames),
                    event (unit destroyed/finished, team died, game over), cmdr (gadget results / AI replies)
  daemon -> widget: {"type":"cmd","payload":{...}}   -> Spring.SendLuaRulesMsg("aicmd:"..payload)
                    {"type":"console","cmd":"..."}   -> Spring.SendCommands
                    {"type":"say","text":"..."}      -> in-game chat
Snapshot visibility is computed per ally team (what that team's LOS/radar shows), so the daemon can
serve each team's commander exactly what its AIs could see.
]]

local target = Spring.GetConfigString("AICommanderBridge", "")
if target == "" then
	return
end
local HOST, PORT = target:match("^([^:]+):(%d+)$")
PORT = tonumber(PORT)
if not HOST or not PORT then
	Spring.Echo("[AICommanderBridge] bad AICommanderBridge setting: " .. target)
	return
end
local SNAP_FRAMES = Spring.GetConfigInt("AICommanderSnapFrames", 30)

local Json = Json or VFS.Include("common/luaUtilities/json.lua")
local socket = socket

local spGetAllUnits = Spring.GetAllUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitLosState = Spring.GetUnitLosState
local spGetUnitCurrentCommand = Spring.GetUnitCurrentCommand
local spGetUnitCommandCount = Spring.GetUnitCommandCount
local spGetUnitIsBuilding = Spring.GetUnitIsBuilding
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetUnitIsStunned = Spring.GetUnitIsStunned
local spGetUnitExperience = Spring.GetUnitExperience
local spGetTeamResources = Spring.GetTeamResources
local spGetTeamInfo = Spring.GetTeamInfo
local spGetGameFrame = Spring.GetGameFrame
local floor = math.floor

local client
local outbuf = {}
local inbuf = ""
local lastConnectTry = -1e9
local helloSent = false
local gaiaTeamID = Spring.GetGaiaTeamID()

local allyTeams = {} -- allyTeamID -> {teams}
local teamAlly = {}
for _, allyTeamID in ipairs(Spring.GetAllyTeamList()) do
	local teams = Spring.GetTeamList(allyTeamID)
	local list = {}
	for _, teamID in ipairs(teams) do
		if teamID ~= gaiaTeamID then
			list[#list + 1] = teamID
			teamAlly[teamID] = allyTeamID
		end
	end
	if #list > 0 then
		allyTeams[allyTeamID] = list
	end
end

local damageTaken = {} -- unitID -> damage since last snapshot
local gameOver = false

local function send(obj)
	if not client then
		return
	end
	outbuf[#outbuf + 1] = Json.encode(obj) .. "\n"
end

local function flush()
	if not client or #outbuf == 0 then
		return
	end
	local data = table.concat(outbuf)
	outbuf = {}
	local i = 1
	local n = #data
	local tries = 0
	while i <= n do
		local last, err, partial = client:send(data, i)
		if last then
			i = last + 1
		elseif err == "timeout" then
			i = (partial or (i - 1)) + 1
			tries = tries + 1
			if tries > 200 then
				-- the daemon is not reading: keep the rest for the next flush
				outbuf[1] = data:sub(i)
				return
			end
			socket.sleep(0.001)
		else
			Spring.Echo("[AICommanderBridge] send failed: " .. tostring(err))
			client:close()
			client = nil
			return
		end
	end
end

local function round(v)
	return floor(v + 0.5)
end

local function teamInfo(teamID)
	local _, leader, isDead, isAI, side, allyTeamID = spGetTeamInfo(teamID, false)
	local info = { id = teamID, ally = allyTeamID, side = side, dead = isDead and true or false }
	local sx, _, sz = Spring.GetTeamStartPosition(teamID)
	if sx and sx >= 0 then
		info.start = { round(sx), round(sz) }
	end
	if isAI then
		local _, aiName, hostingPlayerID, shortName = Spring.GetAIInfo(teamID)
		info.ai = shortName or aiName
		info.aiName = aiName
		info.aiHost = hostingPlayerID
	else
		info.leader = leader and Spring.GetPlayerInfo(leader, false) or nil
	end
	return info
end

local function buildCatalog()
	local defs = {}
	for udid, ud in pairs(UnitDefs) do
		local name = ud.name
		if not name:find("_scav", 1, true) and not name:find("^raptor") and not ud.customParams.isscavenger then
			local maxRange, dps = 0, 0
			for _, w in ipairs(ud.weapons) do
				local wd = WeaponDefs[w.weaponDef]
				if wd and not wd.customParams.bogus then
					if wd.range > maxRange then
						maxRange = wd.range
					end
					-- best armor class: anti-air weapons do almost nothing to the default (ground) class
					local dmg = 0
					for _, v in pairs(wd.damages or {}) do
						if type(v) == "number" and v > dmg then
							dmg = v
						end
					end
					local reload = wd.reload and wd.reload > 0 and wd.reload or 1
					dps = dps + dmg * (wd.salvoSize or 1) * (wd.projectiles or 1) / reload
				end
			end
			local opts = {}
			for i, bo in ipairs(ud.buildOptions or {}) do
				opts[i] = bo
			end
			defs[#defs + 1] = {
				id = udid,
				name = name,
				human = ud.translatedHumanName or ud.humanName,
				tip = ud.translatedTooltip or ud.tooltip,
				m = round(ud.metalCost or 0),
				e = round(ud.energyCost or 0),
				bt = round(ud.buildTime or 0),
				hp = round(ud.health or 0),
				speed = round(ud.speed or 0),
				range = round(maxRange),
				dps = round(dps),
				tech = tonumber(ud.customParams.techlevel) or 1,
				mobile = ud.canMove and not ud.isBuilding or false,
				fly = ud.canFly or false,
				factory = ud.isFactory or false,
				builder = (ud.isBuilder and not ud.isFactory) or false,
				bp = round(ud.buildSpeed or 0),
				mex = (ud.extractsMetal or 0) > 0,
				emake = round((ud.energyMake or 0) + (ud.windGenerator or 0) + (ud.tidalGenerator or 0) - math.min(0, ud.energyUpkeep or 0)),
				radar = round(ud.radarDistance or 0),
				los = round(ud.sightDistance or 0),
				stealth = ud.stealth or false,
				water = (ud.minWaterDepth or -1) > 0 or false,
				commander = ud.customParams.iscommander and true or false,
				opts = opts,
			}
		end
	end
	return defs
end

local function buildMap()
	local step = 64
	local cols, rows = floor(Game.mapSizeX / step), floor(Game.mapSizeZ / step)
	local heights = {}
	for r = 0, rows - 1 do
		local row = {}
		for c = 0, cols - 1 do
			row[c + 1] = round(Spring.GetGroundHeight(c * step + step / 2, r * step + step / 2))
		end
		heights[r + 1] = row
	end
	local spots = {}
	local finder = WG.resource_spot_finder
	if finder and finder.metalSpotsList then
		for i, s in ipairs(finder.metalSpotsList) do
			spots[i] = { round(s.x), round(s.z), s.worth }
		end
	end
	local boxes = {}
	for allyTeamID in pairs(allyTeams) do
		local x1, z1, x2, z2 = Spring.GetAllyTeamStartBox(allyTeamID)
		if x1 then
			boxes[tostring(allyTeamID)] = { round(x1), round(z1), round(x2), round(z2) }
		end
	end
	return {
		name = Game.mapName,
		sizeX = Game.mapSizeX,
		sizeZ = Game.mapSizeZ,
		step = step,
		heights = heights,
		metalSpots = spots,
		startBoxes = boxes,
		waterDamage = Game.waterDamage,
	}
end

local function sendHello()
	local teams = {}
	for allyTeamID, list in pairs(allyTeams) do
		for _, teamID in ipairs(list) do
			teams[#teams + 1] = teamInfo(teamID)
		end
	end
	local myName = Spring.GetPlayerInfo(Spring.GetMyPlayerID(), false)
	local spec, fullView = Spring.GetSpectatingState()
	send({
		type = "hello",
		match = Spring.GetConfigString("AICommanderMatch", ""),
		player = myName,
		playerID = Spring.GetMyPlayerID(),
		spec = spec,
		fullView = fullView,
		game = Game.gameName .. " " .. Game.gameVersion,
		gameID = Game.gameID or "",
		frame = spGetGameFrame(),
		modOptions = Spring.GetModOptions(),
		teams = teams,
		map = buildMap(),
		catalog = buildCatalog(),
	})
	helloSent = true
end

local function connect()
	lastConnectTry = os.clock()
	local c = socket.tcp()
	c:settimeout(2)
	local ok, err = c:connect(HOST, PORT)
	if not ok then
		Spring.Echo("[AICommanderBridge] cannot connect to " .. target .. ": " .. tostring(err))
		c:close()
		return
	end
	c:settimeout(0)
	c:setoption("tcp-nodelay", true)
	client = c
	inbuf = ""
	outbuf = {}
	Spring.Echo("[AICommanderBridge] connected to " .. target)
	sendHello()
	flush()
end

local function handleLine(line)
	local ok, msg = pcall(Json.decode, line)
	if not ok or type(msg) ~= "table" then
		return
	end
	if msg.type == "cmd" and type(msg.payload) == "table" then
		Spring.SendLuaRulesMsg("aicmd:" .. Json.encode(msg.payload))
	elseif msg.type == "console" and type(msg.cmd) == "string" then
		Spring.SendCommands(msg.cmd)
	elseif msg.type == "say" and type(msg.text) == "string" then
		Spring.SendCommands("say " .. msg.text)
	elseif msg.type == "hello" then
		sendHello()
	end
end

local function poll()
	if not client then
		if os.clock() - lastConnectTry > 2 then
			connect()
		end
		return
	end
	while true do
		local data, err, partial = client:receive(65536)
		local chunk = data or partial
		if chunk and #chunk > 0 then
			inbuf = inbuf .. chunk
		end
		if err == "closed" then
			Spring.Echo("[AICommanderBridge] daemon closed the connection")
			client:close()
			client = nil
			break
		end
		if not data then
			break
		end
	end
	while true do
		local nl = inbuf:find("\n", 1, true)
		if not nl then
			break
		end
		local line = inbuf:sub(1, nl - 1)
		inbuf = inbuf:sub(nl + 1)
		if #line > 0 then
			handleLine(line)
		end
	end
end

local function resources(teamID)
	local m = { spGetTeamResources(teamID, "metal") }
	local e = { spGetTeamResources(teamID, "energy") }
	-- current, storage, pull, income, expense
	return {
		m = { round(m[1] or 0), round(m[2] or 0), round(m[3] or 0), round((m[4] or 0) * 10) / 10, round((m[5] or 0) * 10) / 10 },
		e = { round(e[1] or 0), round(e[2] or 0), round(e[3] or 0), round(e[4] or 0), round(e[5] or 0) },
	}
end

local LOS_INLOS, LOS_INRADAR, LOS_PREVLOS = 1, 2, 4

local function snapshot()
	local frame = spGetGameFrame()
	local all = spGetAllUnits()
	local perAlly = {}
	for allyTeamID, teams in pairs(allyTeams) do
		local teamsOut = {}
		for i, teamID in ipairs(teams) do
			local info = teamInfo(teamID)
			info.res = resources(teamID)
			teamsOut[i] = info
		end
		perAlly[allyTeamID] = { teams = teamsOut, units = {}, enemies = {} }
	end

	for _, unitID in ipairs(all) do
		local teamID = spGetUnitTeam(unitID)
		local owner = teamAlly[teamID]
		local defID = spGetUnitDefID(unitID)
		local x, _, z = spGetUnitPosition(unitID)
		-- gaia (critters, map features-as-units) is nobody's enemy
		if x and defID and teamID ~= gaiaTeamID then
			local hp, maxHp, _, _, buildProgress = spGetUnitHealth(unitID)
			local hpFrac = (hp and maxHp and maxHp > 0) and round(hp / maxHp * 100) or 0
			if owner and perAlly[owner] then
				-- own-side view: everything about the unit
				local flags = 0
				if spGetUnitRulesParam(unitID, "ai_cmdr") == 1 then
					flags = flags + 1
				end
				local nCmds = spGetUnitCommandCount(unitID) or 0
				if nCmds == 0 then
					flags = flags + 2
				end
				if buildProgress and buildProgress < 1 then
					flags = flags + 4
				end
				local building = spGetUnitIsBuilding(unitID)
				if building then
					flags = flags + 8
				end
				if spGetUnitIsStunned(unitID) then
					flags = flags + 16
				end
				local cmdID = nCmds > 0 and spGetUnitCurrentCommand(unitID) or 0
				local dmg = damageTaken[unitID]
				local u = perAlly[owner].units
				u[#u + 1] = { unitID, defID, teamID, round(x), round(z), hpFrac, flags, cmdID or 0, dmg and round(dmg) or 0, building or 0, buildProgress and round(buildProgress * 100) or 100 }
			end
			for allyTeamID, view in pairs(perAlly) do
				if allyTeamID ~= owner then
					local los = spGetUnitLosState(unitID, allyTeamID, true) or 0
					local inLos = (los % 2) >= 1
					local inRadar = (los % 4) >= 2
					local prevLos = (los % 8) >= 4
					if inLos then
						local e = view.enemies
						e[#e + 1] = { unitID, defID, teamID, round(x), round(z), hpFrac, 1 }
					elseif inRadar then
						local e = view.enemies
						-- radar blip: type only if the unit was seen before
						e[#e + 1] = { unitID, prevLos and defID or -1, teamID, round(x), round(z), -1, 2 }
					elseif prevLos and UnitDefs[defID] and not UnitDefs[defID].canMove then
						-- remembered structure (ghost): it cannot have moved
						local e = view.enemies
						e[#e + 1] = { unitID, defID, teamID, round(x), round(z), -1, 4 }
					end
				end
			end
		end
	end
	damageTaken = {}

	local out = {}
	for allyTeamID, view in pairs(perAlly) do
		out[tostring(allyTeamID)] = view
	end
	local _, speedFactor, paused = Spring.GetGameSpeed()
	send({ type = "snap", frame = frame, speed = speedFactor, paused = paused, allies = out })
end

local function losBy(unitID)
	local seen = {}
	for allyTeamID in pairs(allyTeams) do
		local los = spGetUnitLosState(unitID, allyTeamID, true) or 0
		if los % 2 >= 1 then
			seen[#seen + 1] = allyTeamID
		end
	end
	return seen
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
	if not client then
		return
	end
	local x, _, z = spGetUnitPosition(unitID)
	send({
		type = "event", ev = "destroyed", frame = spGetGameFrame(),
		unit = unitID, def = unitDefID, team = unitTeam,
		x = x and round(x), z = z and round(z),
		attacker = attackerID, attackerDef = attackerDefID, attackerTeam = attackerTeam,
		seenBy = losBy(unitID),
	})
	damageTaken[unitID] = nil
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
	if not client then
		return
	end
	local x, _, z = spGetUnitPosition(unitID)
	send({ type = "event", ev = "finished", frame = spGetGameFrame(), unit = unitID, def = unitDefID, team = unitTeam, x = x and round(x), z = z and round(z) })
end

function widget:UnitDamaged(unitID, unitDefID, unitTeam, damage)
	if damage > 0 then
		damageTaken[unitID] = (damageTaken[unitID] or 0) + damage
	end
end

function widget:TeamDied(teamID)
	send({ type = "event", ev = "team_died", frame = spGetGameFrame(), team = teamID })
end

function widget:GameOver(winners)
	gameOver = true
	send({ type = "event", ev = "game_over", frame = spGetGameFrame(), winners = winners })
	flush()
end

function widget:GameStart()
	send({ type = "event", ev = "game_start", frame = spGetGameFrame() })
end

local function onCommanderEvent(json)
	if not client then
		return
	end
	local ok, ev = pcall(Json.decode, json)
	if ok and type(ev) == "table" then
		send({ type = "cmdr", data = ev })
	end
end

function widget:GameFrame(n)
	if n % SNAP_FRAMES == 0 then
		snapshot()
	end
	poll()
	flush()
end

function widget:Update()
	poll()
	flush()
end

function widget:Initialize()
	if not socket then
		Spring.Echo("[AICommanderBridge] LuaSocket unavailable")
		widgetHandler:RemoveWidget()
		return
	end
	widgetHandler:RegisterGlobal("AICommanderEvent", onCommanderEvent)
	local spec = Spring.GetSpectatingState()
	if spec then
		Spring.SendCommands("specfullview 1")
	end
	connect()
end

function widget:Shutdown()
	widgetHandler:DeregisterGlobal("AICommanderEvent")
	if client then
		flush()
		client:close()
		client = nil
	end
end
