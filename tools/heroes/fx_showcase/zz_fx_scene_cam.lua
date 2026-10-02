-- Hero FX showcase camera + screenshots (bench only; copied by bench.sh as zz_hero_scene_cam.lua).
local widget = widget
function widget:GetInfo()
	return { name = "ZZ FX Scene Cam", layer = 1000, enabled = true }
end
local S = VFS.Include("luarules/configs/zz_scene.lua")
local cx, cz = Game.mapSizeX / 2, Game.mapSizeZ / 2

local function setCam(x, z, height, angle)
	local cs = Spring.GetCameraState()
	cs.name = "ta"
	cs.mode = 1
	cs.px, cs.py, cs.pz = x, Spring.GetGroundHeight(x, z), z
	cs.height = height or 800
	cs.angle = angle or 0.8
	cs.flipped = -1
	Spring.SetCameraState(cs, 0)
end

function widget:GameFrame(f)
	if f == 40 then
		Spring.SendCommands("hideinterface 1")
	end
	for i, s in ipairs(S.stations) do
		local w0 = S.first + (i - 1) * S.window
		if f == w0 - 8 then
			setCam(cx + s.dx, cz + s.dz + (s.camDz or 220), s.height or 800, s.angle)
		end
		for _, off in ipairs(s.shots or {}) do
			if f == w0 + off then
				Spring.SendCommands("screenshot png")
				Spring.Echo("[scene] shot " .. s.name .. "_" .. off)
			end
		end
	end
	if f == S.quit then
		Spring.SendCommands("quitforce")
	end
end
