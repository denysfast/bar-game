--------------------------------------------------------------------------------
--
--  file:    gui_custom_build_marker.lua
--  brief:   shows which custom build (denysfast/bar-game tag) this client runs;
--           proves the modified game is loaded on every player, not the official one
--  Licensed under the terms of the GNU GPL, v2 or later.
--
--------------------------------------------------------------------------------

local widget = widget ---@type Widget

local CUSTOM_BUILD = "custom-v2"

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

local glText = gl.Text
local spGetViewGeometry = Spring.GetViewGeometry
local vsx, vsy = spGetViewGeometry()

function widget:ViewResize()
	vsx, vsy = spGetViewGeometry()
end

function widget:DrawScreen()
	glText("BAR custom build " .. CUSTOM_BUILD, 8, vsy - 14, 12, "o")
end
