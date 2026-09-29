local widget = widget
function widget:GetInfo() return { name = "ZZ Hero Scene Cam", layer = 1000, enabled = true } end
local S = VFS.Include("luarules/configs/zz_scene.lua")
local P, T0 = S.period or 40, 40
local function entry(u) if type(u) == "table" then return u[1], u end return u, {} end
function widget:Initialize()
	for _, n in ipairs({"Health Bars GL4", "Unit Energy Icons", "Rank Icons GL4", "Selected Units GL4", "Commands FX", "Unit Team Platter", "Given Units", "Unit Stats", "T4 Heroes"}) do
		Spring.SendCommands("luaui disablewidget " .. n)
	end
end
function widget:GameFrame(f)
	if f == 25 then Spring.SendCommands("hideinterface 1") Spring.SendCommands("disticon 10000") end
	if f < T0 then return end
	local k = (f - T0) % P
	local i = math.floor((f - T0) / P) + 1
	local u = S.units[i]
	if not u then
		if f > T0 + #S.units * P + 5 then Spring.SendCommands("quitforce") end
		return
	end
	local name, o = entry(u)
	if k == 3 or k == P - 12 then
		Spring.WarpMouse(2, 2)
		local uid = Spring.GetGameRulesParam("scene_unit")
		local ud = UnitDefNames[name]
		if uid and uid >= 0 and ud then
			local x, y, z = Spring.GetGameRulesParam('scene_x'), Spring.GetGameRulesParam('scene_y'), Spring.GetGameRulesParam('scene_z')
			if not x then Spring.Echo('[scene] nounit ' .. name) return end
			local d = Spring.GetUnitDefDimensions(ud.id) or {}
			local h = (d.maxy or ud.height or 40)
			local r = math.max(math.abs(d.maxx or 0), math.abs(d.minx or 0), math.abs(d.maxz or 0), math.abs(d.minz or 0), 10)
			local size = math.max(h, r * 2.2)
			local pitch = o.pitch or 0.30          -- radians below horizontal
			local yaw = o.yaw or 0.65              -- 0 = camera straight in front (+z side) of the unit
			-- direction the camera looks: from (+z, +x) side towards the unit
			local dx, dz = -math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch)
			local dy = -math.sin(pitch)
			local dist = size * (o.d or 1.9)
			local fy = y + h * (o.fy or 0.5)
			local cs = Spring.GetCameraState()
			cs.name = o.cam or "fps"; cs.mode = o.mode or 0
			cs.px, cs.py, cs.pz = x - dx * dist, fy - dy * dist, z - dz * dist
			cs.rx = o.rx or (math.pi / 2 + pitch)
			cs.ry = o.ry or -yaw
			cs.rz = 0
			cs.dx, cs.dy, cs.dz = dx, dy, dz
			cs.oldHeight = cs.py
			Spring.SetCameraState(cs, 0)
			if k == 3 or k == P - 4 then
				local cx, cy, cz = Spring.GetCameraPosition()
				local ex, ey, ez = Spring.GetCameraDirection()
				Spring.Echo(string.format("[scene] cam %s h=%.0f r=%.0f pos=%.0f,%.0f,%.0f unit=%.0f,%.0f,%.0f dir=%.2f,%.2f,%.2f want=%.2f,%.2f,%.2f",
					o.tag or name, h, r, cx, cy, cz, x, y, z, ex, ey, ez, dx, dy, dz))
			end
		end
	end
	if k == P - 4 then
		local ex, ey, ez = Spring.GetCameraDirection()
		local cx, cy, cz = Spring.GetCameraPosition()
		local st = Spring.GetCameraState()
		Spring.Echo(string.format('[scene] camnow %s %s pos=%.0f,%.0f,%.0f dir=%.2f,%.2f,%.2f rx=%s ry=%s', o.tag or name, tostring(st.name), cx, cy, cz, ex, ey, ez, tostring(st.rx), tostring(st.ry)))
	end
	if k == P - 2 then
		Spring.SendCommands("screenshot png")
		Spring.Echo("[scene] shot " .. (o.tag or name))
	end
end
