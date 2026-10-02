local widget = widget
function widget:GetInfo() return { name = "ZZ FX Scale Cam", layer = 1000, enabled = true } end
local shots = { [60] = "scale_before_1.0", [86] = "scale_growing", [115] = "scale_after_1.4", [170] = "scale_back_1.0" }
function widget:GameFrame(f)
	if f == 40 then Spring.SendCommands("hideinterface 1") end
	if f == 45 then
		local x, z = Spring.GetGameRulesParam("scale_cx"), Spring.GetGameRulesParam("scale_cz")
		local cs = Spring.GetCameraState()
		cs.name = "ta"; cs.mode = 1; cs.px, cs.py, cs.pz = x, Spring.GetGroundHeight(x, z), z + 120
		cs.height = 520; cs.angle = 0.9; cs.flipped = -1
		Spring.SetCameraState(cs, 0)
	end
	if shots[f] then Spring.SendCommands("screenshot png"); Spring.Echo("[scene] shot " .. shots[f]) end
	if f == 175 then Spring.SendCommands("quitforce") end
end
