-- art-agent render driver (untracked, copied into the worktree for a run)
local gadget = gadget
function gadget:GetInfo() return { name = "ZZ Hero Scene", layer = 1000, enabled = true } end
if not gadgetHandler:IsSyncedCode() then return end
local S = VFS.Include("luarules/configs/zz_scene.lua")
local cx, cz = Game.mapSizeX / 2, Game.mapSizeZ / 2
local P, T0 = S.period or 40, 40
local cur
function gadget:GameFrame(f)
	if f == 20 then
		for at = 0, 2 do pcall(Spring.SetGlobalLos, at, true) end
		for _, uid in ipairs(Spring.GetAllUnits()) do Spring.DestroyUnit(uid, false, true) end
	end
	if f >= T0 and (f - T0) % P == 0 then
		local i = math.floor((f - T0) / P) + 1
		if cur then Spring.DestroyUnit(cur, false, true); cur = nil end
		local u = S.units[i]
		if u then
			local name = type(u) == "table" and u[1] or u
			local team = name:sub(1, 3) == "cor" and 1 or 0
			if UnitDefNames[name] then
				local j = (S.slot or 0) + i - 1
				local px, pz = cx - 2200 + (j % 9) * 550, cz - 1500 + math.floor(j / 9) * 700
				if type(u) == "table" and u.x then px, pz = u.x, u.z end
				cur = Spring.CreateUnit(name, px, Spring.GetGroundHeight(px, pz), pz, 0, team)
				if cur then
					Spring.GiveOrderToUnit(cur, CMD.FIRE_STATE, { 0 }, 0)
					Spring.GiveOrderToUnit(cur, CMD.MOVE_STATE, { 0 }, 0)
				end
			end
			if cur then
				local ux, uy, uz = Spring.GetUnitPosition(cur)
				Spring.SetGameRulesParam("scene_x", ux); Spring.SetGameRulesParam("scene_y", uy); Spring.SetGameRulesParam("scene_z", uz)
			end
			Spring.SetGameRulesParam("scene_unit", cur or -1)
			Spring.SetGameRulesParam("scene_idx", i)
			Spring.Echo("[scene] spawn " .. name .. " " .. tostring(cur))
		end
	end
end
