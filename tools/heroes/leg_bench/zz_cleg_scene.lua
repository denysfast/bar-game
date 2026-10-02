-- bench-only scene driver for the Legion hero content (copied into the worktree by bench.sh as zz_hero_scene.lua)
local gadget = gadget
function gadget:GetInfo() return { name = "ZZ Hero Scene (cleg)", layer = 1000, enabled = true } end
if not gadgetHandler:IsSyncedCode() then return end
local S = VFS.Include("luarules/configs/zz_scene.lua")
local cx, cz = Game.mapSizeX / 2, Game.mapSizeZ / 2
local hero
local groups = {}
local dmg = { total = 0, byW = {}, win = 0 }
local function log(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end Spring.Echo("[scene] " .. table.concat(t, " ")) end
local function gy(x, z) return math.max(0, Spring.GetGroundHeight(x, z)) end

local function spawnGroup(i, g)
	local ids = {}
	for k = 1, g.n or 1 do
		local a = (k - 1) / math.max(1, (g.n or 1)) * 6.283
		local r = (g.n or 1) > 1 and (g.spread or 200) * (0.4 + 0.6 * ((k * 7) % 5) / 4) or 0
		local x, z = cx + (g.x or 0) + math.cos(a) * r, cz + (g.z or 700) + math.sin(a) * r
		if g.line then x, z = cx + (g.x or 0) + (k - 1) * g.line[1], cz + (g.z or 700) + (k - 1) * g.line[2] end
		local uid = Spring.CreateUnit(g.unit or "corsumo", x, gy(x, z), z, g.facing or 2, g.team or 1)
		if uid then
			ids[#ids + 1] = uid
			if g.hpMax then
				Spring.SetUnitMaxHealth(uid, g.hpMax)
				Spring.SetUnitHealth(uid, g.hpMax)
			end
			if g.hp then
				local _, m = Spring.GetUnitHealth(uid)
				Spring.SetUnitHealth(uid, m * g.hp)
			end
			if g.hold ~= false and S.hold then
				Spring.GiveOrderToUnit(uid, CMD.FIRE_STATE, { 0 }, 0)
			end
			if g.move then
				local mx, mz = cx + g.move[1], cz + g.move[2]
				Spring.GiveOrderToUnit(uid, CMD.MOVE, { mx, gy(mx, mz), mz }, 0)
			end
		end
	end
	groups[i] = ids
	return ids
end

local function first(ids)
	for _, uid in ipairs(ids or {}) do
		if Spring.ValidUnitID(uid) and not Spring.GetUnitIsDead(uid) then return uid end
	end
end

function gadget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
	if attackerTeam == 0 and unitTeam ~= 0 and damage > 0 and not paralyzer then
		local wd = WeaponDefs[weaponDefID or -1]
		local k = wd and wd.name or ("w" .. tostring(weaponDefID))
		dmg.byW[k] = (dmg.byW[k] or 0) + damage
		dmg.total = dmg.total + damage
		dmg.win = dmg.win + damage
	end
end

local function dumpDamage(tag)
	local t = {}
	for k, v in pairs(dmg.byW) do t[#t + 1] = k .. "=" .. math.floor(v) end
	table.sort(t)
	log("damage", tag, "total", math.floor(dmg.total), table.concat(t, " "))
	dmg.byW = {}
	dmg.total = 0
end

function gadget:GameFrame(f)
	local G = GG.T4Heroes
	if f == 20 then
		for _, uid in ipairs(Spring.GetAllUnits()) do Spring.DestroyUnit(uid, false, true) end
		Spring.SetGameRulesParam("hero_ability_log", 1)
		if S.globalLos then Spring.SetGlobalLos(0, true) end
	end
	if f == 30 then
		local hx, hz = cx + (S.heroX or 0), cz + (S.heroZ or 0)
		hero = Spring.CreateUnit(S.hero, hx, gy(hx, hz), hz, S.heroFacing or 0, 0)
		Spring.SetGameRulesParam("scene_hero", hero)
		for i, g in ipairs(S.groups or {}) do
			if not g.at then spawnGroup(i, g) end
		end
		log("hero", hero, S.hero)
	end
	for i, g in ipairs(S.groups or {}) do
		if g.at and f == g.at then spawnGroup(i, g) end
	end
	if f == 40 and hero and G then
		Spring.SetTeamResource(0, "ms", 50000000)
		Spring.SetTeamResource(0, "metal", 50000000)
		G.setLevel(hero, S.level or 100)
		for _, key in ipairs(S.learn or {}) do
			local n = key:match("x(%d+)$")
			local k = key:gsub("x%d+$", "")
			for _ = 1, tonumber(n or 1) do G.learn(hero, k) end
		end
		local h = G.heroes[hero]
		h.autocast = S.autocast or false
		local t = {}
		for k, v in pairs(h.ranks) do t[#t + 1] = k .. "=" .. v end
		table.sort(t)
		log("level", h.level, "ranks", table.concat(t, " "), "power", string.format("%.2f", h.power or 0), "dmgMult", string.format("%.2f", h.dmgMult or 0))
		Spring.GiveOrderToUnit(hero, CMD.FIRE_STATE, { S.heroFire or 2 }, 0)
		if S.heroMove then
			local mx, mz = cx + S.heroMove[1], cz + S.heroMove[2]
			Spring.GiveOrderToUnit(hero, CMD.MOVE, { mx, gy(mx, mz), mz }, 0)
		end
	end
	if f % 30 == 5 and f > 30 then
		Spring.SetTeamResource(0, "es", 10000000)
		Spring.SetTeamResource(0, "energy", 10000000)
	end
	if S.immortal and f % 10 == 0 then
		for gi, ids in pairs(groups) do
			if ((S.groups[gi] or {}).team or 1) ~= 0 and not (S.groups[gi] or {}).mortal then
				for _, uid in ipairs(ids) do
					local hp, m = Spring.GetUnitHealth(uid)
					if hp then Spring.SetUnitHealth(uid, m) end
				end
			end
		end
	end
	for _, o in ipairs(S.orders or {}) do
		if f == o.frame and hero then
			local params = o.params
			if o.x then local x, z = cx + o.x, cz + o.z; params = { x, gy(x, z), z } end
			if o.group then params = { first(groups[o.group]) } end
			Spring.GiveOrderToUnit(o.unit == "hero" and hero or first(groups[o.unit or 1]), o.cmd, params or {}, o.opts or 0)
		end
	end
	for _, c in ipairs(S.casts or {}) do
		if f == c.frame and hero and G then
			local tx, tz, target
			if c.group then
				target = first(groups[c.group])
				if target then
					local x, _, z = Spring.GetUnitPosition(target)
					tx, tz = x, z
				end
			elseif c.x then
				tx, tz = cx + c.x, cz + c.z
			end
			if c.unitOnly then tx, tz = nil, nil end
			local ok = G.cast(hero, c.key, tx, tz, target)
			log("cast", c.key, tostring(ok), "target", tostring(target))
		end
	end
	if S.dpsEvery and f % S.dpsEvery == 0 and f > 40 then
		dumpDamage("t" .. f)
	end
	for _, d in ipairs(S.dumps or {}) do
		if f == d then dumpDamage("f" .. f) end
	end
	if S.status and f % S.status == 0 and hero then
		local hp, m = Spring.GetUnitHealth(hero)
		local alive = 0
		for _, ids in pairs(groups) do for _, uid in ipairs(ids) do if Spring.ValidUnitID(uid) and not Spring.GetUnitIsDead(uid) then alive = alive + 1 end end end
		local x, _, z = Spring.GetUnitPosition(hero)
		log("status f", f, "hero hp", hp and math.floor(hp) or -1, "/", m and math.floor(m) or -1, "pos", x and math.floor(x - cx) or "-", z and math.floor(z - cz) or "-", "enemies alive", alive)
	end
	for _, hu in ipairs(S.hurt or {}) do
		if f == hu.frame and hero then
			local _, m = Spring.GetUnitHealth(hero)
			Spring.SetUnitHealth(hero, m * hu.frac)
			Spring.AddUnitDamage(hero, m * 0.03)
			log("hurt hero to", hu.frac)
		end
	end
	if S.kill and hero then
		for _, k in ipairs(S.kill) do
			if f == k.frame then
				local uid = first(groups[k.group])
				if uid then Spring.DestroyUnit(uid, false, false, k.byHero and hero or nil) end
			end
		end
	end
end
