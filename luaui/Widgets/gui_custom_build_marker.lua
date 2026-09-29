--------------------------------------------------------------------------------
--
--  file:    gui_custom_build_marker.lua
--  brief:   shows which custom build (denysfast/bar-game tag) this client runs;
--           proves the modified game is loaded on every player, not the official one
--  Licensed under the terms of the GNU GPL, v2 or later.
--
--------------------------------------------------------------------------------

local widget = widget ---@type Widget

local CUSTOM_BUILD = "custom-v17"

function widget:GetInfo()
	return {
		name = "Custom Build Marker",
		desc = "Draws the custom build tag top-centre, above every other widget",
		author = "denysfast",
		date = "2026-09-20",
		license = "GNU GPL, v2 or later",
		layer = 9999, -- draw after the minimap and the rest of the HUD so it is never covered
		enabled = true,
	}
end

local spGetViewGeometry = Spring.GetViewGeometry
local vsx, vsy = spGetViewGeometry()
local font, fontSize

local function getFont()
	-- BAR renders text through its font handler (gl.Text is a no-op with the BAR UI);
	-- fall back to the engine default font when the handler is not loaded yet
	if WG.fonts and WG.fonts.getFont then
		font, fontSize = WG.fonts.getFont(2, 1.6)
	else
		font, fontSize = gl.LoadFont("fonts/Exo2-SemiBold.otf", 24, 4, 1.5), 24
	end
	return font
end

function widget:ViewResize()
	vsx, vsy = spGetViewGeometry()
	font = nil -- font handler re-creates its fonts on resize
end

function widget:DrawScreen()
	if not font and not getFont() then
		return
	end
	font:Begin()
	font:SetTextColor(1, 0.85, 0.2, 1)
	font:Print("BAR custom build " .. CUSTOM_BUILD, vsx / 2, vsy - fontSize * 3, fontSize, "co")
	font:End()
end
