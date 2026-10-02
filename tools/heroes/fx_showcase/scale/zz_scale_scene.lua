-- bench only: two armt4zeus; the right one grows to 1.4 through the SYNCED GG.HeroFX.scale
local gadget = gadget
function gadget:GetInfo() return { name = "ZZ FX Scale Scene", layer = 1000, enabled = true } end
if not gadgetHandler:IsSyncedCode() then return end
local cx, cz = Game.mapSizeX / 2 - 1300, Game.mapSizeZ / 2 - 900
local A, B
function gadget:GameFrame(f)
	if f == 20 then
		for _, u in ipairs(Spring.GetAllUnits()) do Spring.DestroyUnit(u, false, true) end
	end
	if f == 30 then
		A = Spring.CreateUnit("armt4zeus", cx - 170, Spring.GetGroundHeight(cx - 170, cz), cz, 0, 0)
		B = Spring.CreateUnit("armt4zeus", cx + 170, Spring.GetGroundHeight(cx + 170, cz), cz, 0, 1)
		for _, u in ipairs({ A, B }) do Spring.GiveOrderToUnit(u, CMD.FIRE_STATE, { 0 }, 0) end
		Spring.SetGameRulesParam("scale_cx", cx); Spring.SetGameRulesParam("scale_cz", cz)
		Spring.Echo("[scene] scale units", A, B)
	end
	if f == 70 then
		GG.HeroFX.scale(B, 1.4, 1.0)
		GG.HeroFX.attach(B, "electric", { color = "rage", intensity = 1.2 })
		Spring.Echo("[scene] scale B -> 1.4")
	end
	if f == 140 then GG.HeroFX.scale(B, 1.0, 0.5) end
end
