--------------------------------------------------------------------------------
--
--  file:    gui_ai_generals.lua
--  brief:   AI Generals panel (custom v22): which ally team has an LLM general
--           (role, harness, model, effort from the modoptions general_N_*) and the
--           general's latest report (game rules param general_report_N).
--           Reports are shown only to spectators and to players of that ally team.
--  Licensed under the terms of the GNU GPL, v2 or later.
--
--------------------------------------------------------------------------------

local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name = "AI Generals",
		desc = "Shows the LLM generals of the AI ally teams and their latest reports (top-left)",
		author = "denysfast",
		date = "2026-10-04",
		license = "GNU GPL, v2 or later",
		layer = 9998,
		enabled = true,
	}
end

local MAX_ALLY = 3
local REFRESH_SECONDS = 1

local ROLE_NAMES = {
	sneaky = "Подлый",
	economist = "Лейт-гейм экономист",
	aggressor = "Агрессор",
	air_marshal = "Маршал авиации",
	strategist = "Стратег",
}

local spGetViewGeometry = Spring.GetViewGeometry
local spGetGameRulesParam = Spring.GetGameRulesParam
local spGetSpectatingState = Spring.GetSpectatingState
local spGetMyAllyTeamID = Spring.GetMyAllyTeamID

local glCallList = gl.CallList
local glCreateList = gl.CreateList
local glDeleteList = gl.DeleteList

local vsx, vsy = spGetViewGeometry()
local font
local textSize = 15
local generals = {} -- array of { ally = N, header = "Союз N: ...", report = string|nil }
local reportVisible = {} -- [i] = bool, whether the viewer may read generals[i].report
local displayList
local dirty = true
local sinceRefresh = REFRESH_SECONDS

local function trim(s)
	return (s and s:match("^%s*(.-)%s*$")) or ""
end

local function readGenerals()
	local modOptions = Spring.GetModOptions() or {}
	local allyExists = {}
	for _, allyTeamID in ipairs(Spring.GetAllyTeamList()) do
		allyExists[allyTeamID] = true
	end
	generals = {}
	for n = 0, MAX_ALLY do
		local role = trim(modOptions["general_" .. n .. "_role"])
		if role ~= "" and role ~= "none" and allyExists[n] then
			local parts = { ROLE_NAMES[role] or role, "·" }
			local harness = trim(modOptions["general_" .. n .. "_harness"])
			parts[#parts + 1] = harness ~= "" and harness or "pi-agent"
			local model = trim(modOptions["general_" .. n .. "_model"])
			if model ~= "" then
				parts[#parts + 1] = model
			end
			local effort = trim(modOptions["general_" .. n .. "_effort"])
			if effort ~= "" and effort ~= "default" then
				parts[#parts + 1] = effort
			end
			generals[#generals + 1] = {
				ally = n,
				header = "Союз " .. n .. ": " .. table.concat(parts, " "),
				report = nil,
			}
			reportVisible[#generals] = false
		end
	end
end

local function getFont()
	if WG.fonts and WG.fonts.getFont then
		font = WG.fonts.getFont(1, 1)
	else
		font = gl.LoadFont("fonts/Exo2-SemiBold.otf", 24, 4, 1.5)
	end
	return font
end

-- re-read reports and viewer rights; marks the panel dirty only when something changed
local function refresh()
	local spec = spGetSpectatingState()
	local myAlly = spGetMyAllyTeamID()
	for i = 1, #generals do
		local g = generals[i]
		local visible = spec or myAlly == g.ally
		local report = spGetGameRulesParam("general_report_" .. g.ally)
		if type(report) ~= "string" or report == "" then
			report = nil
		end
		if visible ~= reportVisible[i] or report ~= g.report then
			reportVisible[i] = visible
			g.report = report
			dirty = true
		end
	end
end

local function buildList()
	if displayList then
		glDeleteList(displayList)
		displayList = nil
	end
	local scale = (vsy / 1080) * Spring.GetConfigFloat("ui_scale", 1)
	textSize = math.floor(15 * scale + 0.5)
	local lineH = math.floor(textSize * 1.3 + 0.5)
	local pad = math.floor(8 * scale + 0.5)
	local maxW = math.floor(vsx * 0.27)
	local x0 = math.floor(vsx * 0.006)
	local top = vsy - math.floor(200 * scale) -- below the custom build marker line

	-- lay out the text once: { str, r, g, b }
	local lines, width = {}, 0
	for i = 1, #generals do
		local g = generals[i]
		lines[#lines + 1] = { g.header, 1, 0.85, 0.3 }
		width = math.max(width, font:GetTextWidth(g.header) * textSize)
		if g.report and reportVisible[i] then
			local wrapped = font:WrapText(g.report, maxW, vsy, textSize)
			for line in (wrapped .. "\n"):gmatch("(.-)\n") do
				if line ~= "" then
					lines[#lines + 1] = { "  " .. line, 0.85, 0.85, 0.85 }
					width = math.max(width, font:GetTextWidth("  " .. line) * textSize)
				end
			end
		end
	end
	width = math.min(width, maxW + textSize)
	local bottom = top - #lines * lineH - pad * 2

	displayList = glCreateList(function()
		gl.Color(0, 0, 0, 0.45)
		gl.Rect(x0, bottom, x0 + width + pad * 2, top)
		gl.Color(1, 1, 1, 1)
		font:Begin()
		for i = 1, #lines do
			local l = lines[i]
			font:SetTextColor(l[2], l[3], l[4], 1)
			font:Print(l[1], x0 + pad, top - pad - i * lineH + (lineH - textSize) * 0.5, textSize, "o")
		end
		font:End()
	end)
	dirty = false
end

function widget:Initialize()
	readGenerals()
	if #generals == 0 then
		widgetHandler:RemoveWidget()
		return
	end
	refresh()
end

function widget:Shutdown()
	if displayList then
		glDeleteList(displayList)
		displayList = nil
	end
end

function widget:ViewResize()
	vsx, vsy = spGetViewGeometry()
	font = nil -- the font handler re-creates its fonts on resize
	dirty = true
end

function widget:PlayerChanged()
	sinceRefresh = REFRESH_SECONDS -- spectator switch / team change: re-check rights now
end

function widget:Update(dt)
	sinceRefresh = sinceRefresh + dt
	if sinceRefresh >= REFRESH_SECONDS then
		sinceRefresh = 0
		refresh()
	end
end

function widget:DrawScreen()
	if not font then
		if not getFont() then
			return
		end
		dirty = true
	end
	if dirty then
		buildList()
	end
	if displayList then
		glCallList(displayList)
	end
end
