local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "DBG AI Census",
		desc = "Dev tool: every 5 minutes logs unit counts, income and metal of every AI team ([census] lines in infolog). Enable with modoption debugcommands or via /luarules enablegadget",
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

local PERIOD = 9000 -- frames = 5 minutes
local DEBUG_ALL_TEAMS = true

function gadget:GameFrame(frame)
	if frame % PERIOD ~= 100 then
		return
	end
	for _, teamID in ipairs(Spring.GetTeamList()) do
		local _, _, _, isAI = Spring.GetTeamInfo(teamID, false)
		if isAI or DEBUG_ALL_TEAMS then
			local units = Spring.GetTeamUnits(teamID)
			local counts = {}
			for _, unitID in ipairs(units) do
				local name = UnitDefs[Spring.GetUnitDefID(unitID)].name
				counts[name] = (counts[name] or 0) + 1
			end
			local parts = {}
			for name, count in pairs(counts) do
				parts[#parts + 1] = name .. "=" .. count
			end
			table.sort(parts)
			-- how close does this team's army get to enemy commanders (debug for attack targeting)
			local nearest = -1
			for _, unitID in ipairs(units) do
				local ud = UnitDefs[Spring.GetUnitDefID(unitID)]
				if ud.canMove and #ud.weapons > 0 and not ud.isBuilder then
					local x, y, z = Spring.GetUnitPosition(unitID)
					for _, enemyID in ipairs(Spring.GetAllUnits()) do
						if Spring.GetUnitAllyTeam(enemyID) ~= Spring.GetUnitAllyTeam(unitID) and UnitDefs[Spring.GetUnitDefID(enemyID)].customParams.iscommander then
							local ex, ey, ez = Spring.GetUnitPosition(enemyID)
							local d = math.sqrt((x - ex) ^ 2 + (z - ez) ^ 2)
							if nearest < 0 or d < nearest then nearest = d end
						end
					end
				end
			end
			parts[#parts + 1] = "nearestArmyToEnemyCom=" .. math.floor(nearest)
			local metal, storage, _, income = Spring.GetTeamResources(teamID, "metal")
			Spring.Echo(string.format("[census] f=%d team=%d units=%d mIncome=%.0f metal=%.0f/%.0f :: %s",
				frame, teamID, #units, income, metal, storage, table.concat(parts, " ")))
		end
	end
end
