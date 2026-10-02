local widget = widget
function widget:GetInfo() return { name = "ZZ Hero Scene Cam (cleg)", layer = 1000, enabled = true } end
local S = VFS.Include("luarules/configs/zz_scene.lua")
local cx, cz = Game.mapSizeX / 2, Game.mapSizeZ / 2
function widget:Initialize()
	if S.hideUI then Spring.SendCommands("hideinterface 1") end
end
local follow
local function place(c)
	local hero = Spring.GetGameRulesParam("scene_hero")
	local x, z
	if c.follow and hero then
		local ux, _, uz = Spring.GetUnitPosition(hero)
		x, z = (ux or cx) + (c.dx or 0), (uz or cz) + (c.dz or 300)
	else
		x, z = cx + (c.x or 0), cz + (c.z or 300)
	end
	local cs = Spring.GetCameraState()
	cs.name = "ta"; cs.mode = 1
	cs.px, cs.py, cs.pz = x, Spring.GetGroundHeight(x, z), z
	cs.height = c.height or 2000; cs.angle = c.angle or 0.75; cs.flipped = -1
	Spring.SetCameraState(cs, 0)
end
function widget:GameFrame(f)
	local hero = Spring.GetGameRulesParam("scene_hero")
	if f == 45 and hero and not S.noSelect then Spring.SelectUnitArray({ hero }) end
	for _, c in ipairs(S.cam or {}) do
		if f == c.frame then follow = c.follow and c or nil; place(c) end
	end
	if follow and f % 3 == 0 then place(follow) end
	for _, s in ipairs(S.shots or {}) do
		if f == s.frame then Spring.SendCommands("screenshot png") Spring.Echo("[scene] shot " .. (s.name or f)) end
	end
	if f == (S.quit or 600) then Spring.SendCommands("quitforce") end
end
