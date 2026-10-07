-- bench-only: one-cast damage of every active hero ability vs a fresh level-1 enemy hero with 400k HP.
-- Config: luarules/configs/zz_herodmg_cfg.lua returns { prefix = "arm", levels = {50,75,99}, window = 750, target = "cort4hellwalker" }
local gadget = gadget
function gadget:GetInfo() return { name = "ZZ Hero Damage Bench", layer = 1000, enabled = true } end

if not gadgetHandler:IsSyncedCode() then
	local done = false
	function gadget:Initialize()
		Spring.SendCommands({ "setmaxspeed 200", "setspeed 200" })
	end
	function gadget:GameFrame(f)
		if f % 300 == 0 then Spring.SendCommands({ "setmaxspeed 200", "setspeed 200" }) end
		if not done and Spring.GetGameRulesParam("hdmg_done") == 1 then
			done = true
			Spring.SendCommands("quitforce")
		end
	end
	return
end

local C = VFS.Include("luarules/configs/zz_herodmg_cfg.lua")
local WINDOW = C.window or 750
local TARGET = C.target or "cort4hellwalker"
local cx, cz = Game.mapSizeX / 2, Game.mapSizeZ / 2
local function log(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end Spring.Echo("[hdmg] " .. table.concat(t, " ")) end
local function gy(x, z) return math.max(0, Spring.GetGroundHeight(x, z)) end

local jobs, ji = {}, 0
local cur -- current job state
local nextAt = 60

local function rv(v, r)
	if type(v) == "table" then return v[math.min(#v, r)] end
	return v
end

local function buildJobs(G)
	local H = G.H
	local names = {}
	for _, ud in pairs(UnitDefs) do
		if ud.name:sub(1, #C.prefix) == C.prefix and ud.name:find("t4") and H.branch(ud.name, "a1") then
			if not C.only or C.only[ud.name] then names[#names + 1] = ud.name end
		end
	end
	table.sort(names)
	for _, n in ipairs(names) do
		for _, L in ipairs(C.levels or { 50, 75, 99 }) do
			jobs[#jobs + 1] = { hero = n, level = L, key = nil }
			if C.weapon then jobs[#jobs + 1] = { hero = n, level = L, key = nil, wpn = true } end
			for _, key in ipairs({ "a1", "a2", "a3", "ult" }) do
				local b = H.branch(n, key)
				if b and not b.passive then
					jobs[#jobs + 1] = { hero = n, level = L, key = key }
				end
			end
		end
	end
	log("jobs", #jobs, "heroes", #names, table.concat(names, ","))
end

local function clearAll(G)
	for _, uid in ipairs(Spring.GetAllUnits()) do Spring.DestroyUnit(uid, false, true) end
	for t = 0, 1 do
		if G.dead[t] then for k in pairs(G.dead[t]) do G.dead[t][k] = nil end end
	end
end

local function learnBuild(G, uid, L)
	local learned = {}
	local function tryN(key, n)
		local c = 0
		for _ = 1, n do
			if G.learn(uid, key) then c = c + 1 else break end
		end
		learned[#learned + 1] = key .. "=" .. c
	end
	tryN("a1", 10); tryN("a2", 10); tryN("a3", 10); tryN("ult", 10)
	tryN("dmg", 15); tryN("imp", 15); tryN("rng", 15); tryN("vit", 15); tryN("mob", 15)
	return table.concat(learned, " ")
end

function gadget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
	if cur and cur.measuring and not paralyzer and damage > 0 then
		if unitID == cur.target then
			cur.dmg = cur.dmg + damage
			local k = weaponDefID and weaponDefID >= 0 and WeaponDefs[weaponDefID] and WeaponDefs[weaponDefID].name or ("w" .. tostring(weaponDefID))
			cur.byW[k] = (cur.byW[k] or 0) + damage
			if cur.dmg >= 400000 and not cur.f400 then cur.f400 = Spring.GetGameFrame() - cur.castAt end
		elseif unitTeam ~= 0 then
			cur.other = cur.other + damage
		end
	end
end

function gadget:UnitDestroyed(unitID)
	if cur and unitID == cur.target and cur.measuring and not cur.killedAt then
		cur.killedAt = Spring.GetGameFrame() - cur.castAt
	end
end

local function finish(G)
	local j = cur.job
	local t = {}
	for k, v in pairs(cur.byW) do t[#t + 1] = k .. "=" .. math.floor(v) end
	table.sort(t)
	log(string.format("RESULT hero=%s level=%d key=%s name=%s rank=%s cast=%s dist=%d dmg=%d killed=%s killFrame=%s f400=%s other=%d hp_left=%d | %s",
		j.hero, j.level, j.key or (j.wpn and "wpn" or "base"), cur.abName or "-", tostring(cur.rank), tostring(cur.ok), cur.dist or 0, math.floor(cur.dmg),
		cur.killedAt and "1" or "0", tostring(cur.killedAt), tostring(cur.f400), math.floor(cur.other),
		math.floor(cur.hpLeft or -1), table.concat(t, " ")))
	log("SERIES", j.hero, j.level, j.key or (j.wpn and "wpn" or "base"), table.concat(cur.series or {}, ","))
	cur = nil
	clearAll(G)
end

function gadget:GameFrame(f)
	local G = GG.T4Heroes
	if not G then return end
	if f == 20 then
		clearAll(G)
		Spring.SetGlobalLos(0, true)
		Spring.SetGlobalLos(1, true)
		buildJobs(G)
	end
	if f % 30 == 5 then
		for t = 0, 1 do
			Spring.SetTeamResource(t, "ms", 500000000); Spring.SetTeamResource(t, "metal", 500000000)
			Spring.SetTeamResource(t, "es", 500000000); Spring.SetTeamResource(t, "energy", 500000000)
		end
	end
	if f < 60 then return end
	if not cur and f >= nextAt then
		ji = ji + 1
		local j = jobs[ji]
		if not j then
			log("DONE")
			Spring.SetGameRulesParam("hdmg_done", 1)
			nextAt = math.huge
			return
		end
		Spring.SetTeamResource(0, "metal", 500000000)
		local hx, hz = cx, cz - 300
		local caster = Spring.CreateUnit(j.hero, hx, gy(hx, hz), hz, 0, 0)
		cur = { job = j, caster = caster, dmg = 0, other = 0, byW = {}, start = f }
		if not caster then log("ERR no caster", j.hero); cur = nil; nextAt = f + 5; return end
		local h = G.heroes[caster]
		if not h then log("ERR not hero", j.hero); clearAll(G); cur = nil; nextAt = f + 5; return end
		h.autocast = false
		G.setLevel(caster, j.level)
		cur.build = learnBuild(G, caster, j.level)
		Spring.GiveOrderToUnit(caster, CMD.FIRE_STATE, { 0 }, 0)
		Spring.GiveOrderToUnit(caster, CMD.MOVE_STATE, { 0 }, 0)
		local dist = 250
		if j.key then
			local b = h.def.cfg[j.key]
			cur.abName = (b.name or "?"):gsub(" ", "_")
			cur.rank = h.ranks[j.key] or 0
			local range = rv(b.range, math.max(1, cur.rank)) or 0
			if range > 0 then dist = math.max(120, math.min(250, range * 0.8)) else dist = 150 end
			cur.tkind = b.target or (b.toggle and "toggle") or "self"
		end
		cur.dist = dist
		local tx, tz = hx, hz + dist
		local target = Spring.CreateUnit(TARGET, tx, gy(tx, tz), tz, 2, 1)
		cur.target = target
		local th = target and G.heroes[target]
		if th then th.autocast = false end
		if target then
			Spring.GiveOrderToUnit(target, CMD.FIRE_STATE, { 0 }, 0)
			Spring.GiveOrderToUnit(target, CMD.MOVE_STATE, { 0 }, 0)
			local _, m = Spring.GetUnitHealth(target)
			cur.targetMax = m
		end
		cur.castAt = f + 20
		log(string.format("job %d/%d %s L%d %s level=%s power=%.2f ranks %s targetMaxHp=%s hpMult=%s", ji, #jobs, j.hero, j.level, j.key or "base",
			tostring(h.level), h.power or 0, cur.build, tostring(cur.targetMax), tostring(th and th.hpMult)))
		return
	end
	if cur and f == cur.castAt then
		cur.measuring = true
		local j = cur.job
		if j.key then
			local tx, _, tz = Spring.GetUnitPosition(cur.target)
			local ok
			if cur.tkind == "ally" then
				ok = "skip_ally"
			else
				ok = G.cast(cur.caster, j.key, tx, tz, cur.target)
			end
			cur.ok = ok
		elseif j.wpn then
			Spring.GiveOrderToUnit(cur.caster, CMD.FIRE_STATE, { 2 }, 0)
			Spring.GiveOrderToUnit(cur.caster, CMD.ATTACK, { cur.target }, 0)
			cur.ok = "weapon"
		else
			cur.ok = "baseline"
		end
	end
	if cur and cur.measuring and (f - cur.castAt) % 30 == 0 then
		cur.series = cur.series or {}
		cur.series[#cur.series + 1] = math.floor(cur.dmg)
	end
	if cur and cur.measuring and f >= cur.castAt + WINDOW then
		if Spring.ValidUnitID(cur.target) and not Spring.GetUnitIsDead(cur.target) then
			cur.hpLeft = Spring.GetUnitHealth(cur.target)
		else
			cur.hpLeft = 0
		end
		finish(G)
		nextAt = f + 10
	end
end
