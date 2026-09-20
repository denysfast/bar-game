local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "AI Resource Bonus",
		desc = "Time-scaled metal/energy income bonus for AI teams (modoptions ai_bonus_*); publishes bonus and known enemy nukes to the AI via rules params",
		author = "denysfast",
		date = "2026-09-21",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

local modOptions = Spring.GetModOptions()
local bonusMax = tonumber(modOptions.ai_bonus_max) or 0
local bonusStart = tonumber(modOptions.ai_bonus_start) or 0
local rampMinutes = tonumber(modOptions.ai_bonus_ramp) or 30
local delayMinutes = tonumber(modOptions.ai_bonus_delay) or 0
local curve = modOptions.ai_bonus_curve or "linear"
local reveal = modOptions.ai_reveal or "buildings" -- none | buildings | all

local DEBUG_BONUS = false
-- Once per second, in the middle of the engine's 30-frame income window (reset happens at frame % 30 == 0):
-- the income reported next second then contains exactly one of our additions, which we subtract back out.
local UPDATE_FRAMES = 30
local UPDATE_PHASE = 15
local NUKE_SCAN_FRAMES = 150
local REVEAL_FRAMES = 15 -- the engine refreshes LOS state often; keep the radar flag alive

local spGetTeamResources = Spring.GetTeamResources
local spAddTeamResource = Spring.AddTeamResource
local spSetTeamRulesParam = Spring.SetTeamRulesParam
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamLuaAI = Spring.GetTeamLuaAI
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitAllyTeam = Spring.GetUnitAllyTeam
local spGetUnitLosState = Spring.GetUnitLosState
local spGetAllUnits = Spring.GetAllUnits
local spSetUnitLosState = Spring.SetUnitLosState
local gaiaTeamID = Spring.GetGaiaTeamID()

-- AI teams: skirmish AIs (BARb, SimpleAI...) but not the Lua "gamemode" AIs (Raptors/Scavengers) which have their own economy
local aiTeams = {}
local aiTeamList = {}
for _, teamID in ipairs(Spring.GetTeamList()) do
	if teamID ~= gaiaTeamID then
		local _, _, _, isAiTeam, _, allyTeamID = spGetTeamInfo(teamID, false)
		local luaAI = spGetTeamLuaAI(teamID)
		local isGamemodeAI = luaAI and (luaAI:find("Raptors") or luaAI:find("Scavengers"))
		if isAiTeam and not isGamemodeAI then
			aiTeams[teamID] = { allyTeamID = allyTeamID, addedMetal = 0, addedEnergy = 0 }
			aiTeamList[#aiTeamList + 1] = teamID
		end
	end
end

-- nuke launchers (stockpiled, interceptable) and anti-nukes (interceptors), by UnitDefID
local nukeDefs, antiNukeDefs = {}, {}
for unitDefID, ud in pairs(UnitDefs) do
	for _, w in ipairs(ud.weapons) do
		local wd = WeaponDefs[w.weaponDef]
		if wd then
			if wd.stockpile and (wd.targetable or 0) > 0 then
				nukeDefs[unitDefID] = true
			elseif (wd.interceptor or 0) > 0 then
				antiNukeDefs[unitDefID] = true
			end
		end
	end
end

-- what an AI ally team is allowed to "see": enemy structures + commanders, or everything
local revealDefs = {}
if reveal ~= "none" then
	for unitDefID, ud in pairs(UnitDefs) do
		if reveal == "all" or not ud.canMove or ud.customParams.iscommander then
			revealDefs[unitDefID] = true
		end
	end
end
local aiAllyTeams = {}
for _, teamID in ipairs(aiTeamList) do
	aiAllyTeams[aiTeams[teamID].allyTeamID] = true
end

-- CircuitAI attacks only enemies it has a contact for; without scouts that finds nothing, and its waves roam.
-- Mark the chosen enemy units as permanent radar contacts for every AI ally team.
local function revealEnemies()
	for _, unitID in ipairs(spGetAllUnits()) do
		if revealDefs[spGetUnitDefID(unitID)] then
			local unitAllyTeam = spGetUnitAllyTeam(unitID)
			for allyTeamID in pairs(aiAllyTeams) do
				if allyTeamID ~= unitAllyTeam then
					local los = spGetUnitLosState(unitID, allyTeamID, false)
					if not (los and los.los) then
						-- full LOS, not just radar: CircuitAI ignores radar blips whose UnitDef it does not know
						spSetUnitLosState(unitID, allyTeamID, { los = true, radar = true, prevLos = true, contRadar = true })
					end
				end
			end
		end
	end
end

local function bonusFraction(frame)
	local minutes = frame / 1800
	local t = (minutes - delayMinutes) / math.max(rampMinutes, 0.01)
	t = math.min(math.max(t, 0), 1)
	if curve == "slow_start" then
		t = t * t
	elseif curve == "fast_start" then
		t = math.sqrt(t)
	end
	return (bonusStart + (bonusMax - bonusStart) * t) / 100
end

function gadget:Initialize()
	if #aiTeamList == 0 or (bonusMax <= 0 and bonusStart <= 0) then
		Spring.Log(gadget:GetInfo().name, LOG.INFO, "inactive (ai teams: " .. #aiTeamList .. ", max: " .. bonusMax .. "%)")
	else
		Spring.Log(gadget:GetInfo().name, LOG.INFO, string.format("active for %d AI team(s): %d%% -> %d%% over %d min after %d min (%s), reveal=%s",
			#aiTeamList, bonusStart, bonusMax, rampMinutes, delayMinutes, curve, reveal))
	end
	for _, teamID in ipairs(aiTeamList) do
		spSetTeamRulesParam(teamID, "ai_bonus_pct", 0)
		spSetTeamRulesParam(teamID, "ai_bonus_max_pct", bonusMax)
		spSetTeamRulesParam(teamID, "ai_known_enemy_nukes", 0)
		spSetTeamRulesParam(teamID, "ai_known_enemy_antinukes", 0)
	end
end

-- nukes the AI's allyteam has ever seen (LOS or radar) and that are still alive
local seenNukes = {} -- [allyTeamID][unitID] = true

local function scanEnemyNukes(frame)
	local counts = {}
	local seenNow = {}
	for _, unitID in ipairs(spGetAllUnits()) do
		local unitDefID = spGetUnitDefID(unitID)
		if nukeDefs[unitDefID] or antiNukeDefs[unitDefID] then
			local unitAllyTeam = spGetUnitAllyTeam(unitID)
			for _, teamID in ipairs(aiTeamList) do
				local allyTeamID = aiTeams[teamID].allyTeamID
				if allyTeamID ~= unitAllyTeam then
					seenNukes[allyTeamID] = seenNukes[allyTeamID] or {}
					local los = spGetUnitLosState(unitID, allyTeamID, false)
					if los and (los.los or los.radar or los.prevLos) then
						seenNukes[allyTeamID][unitID] = true
					end
					if seenNukes[allyTeamID][unitID] then
						seenNow[allyTeamID] = seenNow[allyTeamID] or {}
						seenNow[allyTeamID][unitID] = true
						counts[allyTeamID] = counts[allyTeamID] or { nukes = 0, anti = 0 }
						if nukeDefs[unitDefID] then
							counts[allyTeamID].nukes = counts[allyTeamID].nukes + 1
						else
							counts[allyTeamID].anti = counts[allyTeamID].anti + 1
						end
					end
				end
			end
		end
	end
	-- forget dead ones
	for allyTeamID, seen in pairs(seenNukes) do
		for unitID in pairs(seen) do
			if not (seenNow[allyTeamID] and seenNow[allyTeamID][unitID]) then
				seen[unitID] = nil
			end
		end
	end
	for _, teamID in ipairs(aiTeamList) do
		local c = counts[aiTeams[teamID].allyTeamID] or { nukes = 0, anti = 0 }
		spSetTeamRulesParam(teamID, "ai_known_enemy_nukes", c.nukes)
		spSetTeamRulesParam(teamID, "ai_known_enemy_antinukes", c.anti)
	end
end

function gadget:GameFrame(frame)
	if #aiTeamList == 0 then
		return
	end
	if frame % NUKE_SCAN_FRAMES == 7 then
		scanEnemyNukes(frame)
	end
	if reveal ~= "none" and frame % REVEAL_FRAMES == 3 then
		revealEnemies()
	end
	if frame % UPDATE_FRAMES ~= UPDATE_PHASE then
		return
	end
	local fraction = bonusFraction(frame)
	local dt = UPDATE_FRAMES / 30
	for _, teamID in ipairs(aiTeamList) do
		local t = aiTeams[teamID]
		local _, _, _, mIncome = spGetTeamResources(teamID, "metal")
		local _, _, _, eIncome = spGetTeamResources(teamID, "energy")
		-- reported income (last 30-frame window) contains exactly our previous addition: strip it, or the bonus compounds
		local baseM = math.max(0, (mIncome or 0) - t.addedMetal)
		local baseE = math.max(0, (eIncome or 0) - t.addedEnergy)
		local addM = baseM * fraction * dt
		local addE = baseE * fraction * dt
		if addM > 0 then spAddTeamResource(teamID, "metal", addM) end
		if addE > 0 then spAddTeamResource(teamID, "energy", addE) end
		t.addedMetal = addM
		t.addedEnergy = addE
		do
			spSetTeamRulesParam(teamID, "ai_bonus_pct", math.floor(fraction * 100 + 0.5))
			if DEBUG_BONUS then
				Spring.Echo(string.format("[ai_bonus] f=%d team=%d mIncome=%.1f baseM=%.1f addM/s=%.1f eIncome=%.1f baseE=%.1f addE/s=%.1f", frame, teamID, mIncome, baseM, t.addedMetal, eIncome, baseE, t.addedEnergy))
			end
		end
	end
end
