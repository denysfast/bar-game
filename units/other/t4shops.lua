-- Custom heroes (denysfast/bar-game), v19: the hero item shops (one per faction), built by T2 constructors
-- (gamedata/alldefs_post.lua, t4Foundry). The shelf, prices and buying live in
-- luarules/gadgets/unit_t4_hero_items.lua (team rules param items_shop); the building only has to exist.
-- Models: each faction's hardened T2 metal vault - an armory of hero gear - without its storage.
local T4 = VFS.Include("gamedata/custom_t4.lua")

local function shop(path, base, name, faction)
	local ud = T4.base(path, base)
	ud.metalcost = 6000
	ud.energycost = 60000
	ud.buildtime = 60000
	ud.health = 30000
	ud.metalstorage = 0
	ud.energystorage = 0
	ud.maxthisunit = 1 -- one shop per team: the shelf belongs to the team
	ud.sightdistance = 400
	local cp = ud.customparams or {}
	ud.customparams = cp
	cp.t4_item_shop = faction
	cp.techlevel = 2
	cp.unitgroup = "util"
	cp.subfolder = "other"
	cp.i18nfromunit = nil
	if ud.featuredefs and ud.featuredefs.dead then
		ud.featuredefs.dead.metal = math.floor(ud.metalcost * 0.4)
	end
	if ud.featuredefs and ud.featuredefs.heap then
		ud.featuredefs.heap.metal = math.floor(ud.metalcost * 0.15)
	end
	return ud
end

return {
	armt4shop = shop("units/ArmBuildings/SeaEconomy/armuwadvms.lua", "armuwadvms", "armt4shop", "arm"),
	cort4shop = shop("units/CorBuildings/SeaEconomy/coruwadvms.lua", "coruwadvms", "cort4shop", "cor"),
	legt4shop = shop("units/Legion/Economy/legamstor.lua", "legamstor", "legt4shop", "leg"),
}
