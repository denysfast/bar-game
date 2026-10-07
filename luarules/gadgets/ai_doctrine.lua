local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "AI Doctrine",
		desc = "Skirmish AI armies by plan: picks a composition, builds exactly it, then drives it as one force",
		author = "denysfast",
		date = "2026-09-30",
		license = "GNU GPL, v2 or later",
		layer = 1,
		enabled = true,
	}
end

-- Custom (denysfast/bar-game), CUSTOM.md "AI doctrine". For every skirmish-AI team (BARb):
--   1. plan   picks a composition (luarules/configs/ai_compositions_<side>.lua, 10 per tier T1..T4) that its
--             factories can build, scales its relative counts to a metal budget from the income;
--   2. build  names the next planned unit of each factory in the unit rules param "doctrine_next" - the AI
--             script builds it (script/hard/manager/factory.as, AiMakeTask); every 4th slot stays with the
--             stock pick (constructors, BARb's own home guard);
--   3. gather finished planned units are taken from the AI ("detach", misc/aicmdr.as) and wait at the rally
--             point; at 85% of the plan (or 60% after a while) the army launches and the next plan starts;
--   4. drive  the army marches as one: an anchor moves toward the target at the pace of the slowest unit and
--             never runs ahead of the army; every unit keeps its role's slot around it (front ahead, skirmishers
--             in the line, AA and support in the middle, artillery behind at its range); near enemies it
--             engages (fight toward them, artillery from its slot, siege armies stop at artillery range);
--             beaten armies fall back to the rally point, get their missing units rebuilt and go again.
-- Tactics: assault (bases), raid (economy, avoids armies), siege (structures from range), skirmish (enemy
-- armies), defend (stays home, intercepts), air (air strike group).
-- Logs "[doctrine] ..." to the infolog. GG.AIDoctrine: owns[unitID], armies, heroArmy(team, heroID, name).

if not gadgetHandler:IsSyncedCode() then
	----------------------------------------------------------------------------- unsynced: AI messages
	local function aiMsg(_, teamID, text)
		Spring.SendSkirmishAIMessage(teamID, text)
	end
	function gadget:Initialize()
		gadgetHandler:AddSyncAction("doctrine_aimsg", aiMsg)
	end
	function gadget:Shutdown()
		gadgetHandler:RemoveSyncAction("doctrine_aimsg")
	end
	return
end

local modOptions = Spring.GetModOptions()
if modOptions.ai_doctrine == "0" or modOptions.ai_doctrine == 0 or modOptions.ai_doctrine == false then
	return false
end

local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitAllyTeam = Spring.GetUnitAllyTeam
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitsInCylinder = Spring.GetUnitsInCylinder
local spGetUnitLosState = Spring.GetUnitLosState
local spGetGroundHeight = Spring.GetGroundHeight
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spGetUnitCommands = Spring.GetUnitCommandCount
local spValidUnitID = Spring.ValidUnitID
local spGetUnitIsDead = Spring.GetUnitIsDead
local spSetUnitRulesParam = Spring.SetUnitRulesParam
local spGetTeamResources = Spring.GetTeamResources
local max, min, floor, sqrt, abs, random = math.max, math.min, math.floor, math.sqrt, math.abs, math.random

local GAME_SPEED = Game.gameSpeed
local MAPX, MAPZ = Game.mapSizeX, Game.mapSizeZ
local ALLIED = { allied = true }

-- tunables
local START_FRAME = 5 * 60 * GAME_SPEED      -- no plans before minute 5 (the opening is the AI's own)
local MAX_ARMIES = 3                          -- per team, forming one included
local PLAN_SHARE = 1                          -- planned units before one stock pick (1 = every other slot: the stock AI keeps
                                              -- its defence and constructors)
local LAUNCH_SHARE = 0.85                     -- launch at this share of the planned metal (by tactic below) ...
local LAUNCH_BY_TACTIC = { raid = 0.6, assault = 0.75, siege = 0.7, skirmish = 0.7, air = 0.7, defend = 0.5 }
local LAUNCH_LATE = 0.6                       -- ... or this after LAUNCH_WAIT
local LAUNCH_WAIT = 4 * 60 * GAME_SPEED
local GATHER_SHARE = 0.7                      -- v22: launch only with this share of the army's metal at the rally point
local RETREAT_STRENGTH = 0.25                 -- fall back below this share of the launch strength (v22: was 0.35)
local RETREAT_ODDS = 3.0                      -- or when the enemy around is this many times stronger than the army
                                              -- and the allied armies next to it (v22: was 2.2, own army only)
local HIT_MEMORY = 8 * GAME_SPEED             -- v22: an army shot by enemies it cannot see goes for them this long
-- v22 late game: "late" = 0 below LATE_FROM m/s of income, 1 at LATE_FULL; it scales the budget, the unit cap,
-- the number of armies, the factory share of the plan and the weight of T2 (mass) compositions
local LATE_FROM, LATE_FULL = 600, 4000
local LATE_BUDGET = 4                         -- budget hi x (1 + LATE_BUDGET * late)
local LATE_UNITS = 2.5                        -- unit cap x (1 + LATE_UNITS * late): a T2 army up to 140 units
local LATE_ARMIES = 3                         -- MAX_ARMIES + LATE_ARMIES * late
local LATE_T2 = 1.2                           -- T2 weight + LATE_T2 * late (T2 spam)
-- v23 late game without T2/T1 land armies (they only lag the game): from NO_LOW_INCOME m/s of metal income
-- (modoption ai_late_t2, 0 = off) with a finished T3 gantry, plans skip T1/T2 land factories (T3/T4 armies only,
-- their T2 parts are left out) and the stock AI gets TeamRulesParam ai_no_t2 = 1 (factory.as: T2 land factories
-- make constructors only). Off again below NO_LOW_OFF of that income or without a gantry
local NO_LOW_INCOME = tonumber(Spring.GetModOptions().ai_late_t2) or 2000
local NO_LOW_OFF = 0.7
-- v22 levy: the stock AI's own army idling at home is taken into a doctrine army and sent
local LEVY_FROM = 18 * 60 * GAME_SPEED
local LEVY_MIN = 6000                         -- metal of idle stock army before a levy
local LEVY_KEEP = 0.25                        -- share of the stock army left to the AI (home guard)
local LEVY_RADIUS = 3500                      -- around the start and the factories
local REFILL_SHARE = 0.8                      -- a beaten army goes again at this share of its plan
local CELL = 1024                             -- enemy map grid
local BUDGET = {                              -- army metal: clamp(income * seconds, lo, hi)
	{ sec = 45, lo = 2500, hi = 7000 },
	{ sec = 55, lo = 10000, hi = 32000 },
	{ sec = 65, lo = 35000, hi = 110000 },
	{ sec = 70, lo = 60000, hi = 220000 },  -- plus the hero
}
local TIER_ODDS = {                           -- max tier available -> weights of tiers 1..4
	{ 1 },
	{ 0.3, 0.7 },
	{ 0.1, 0.35, 0.55 },
	{ 0.05, 0.2, 0.35, 0.4 },
}
local MAX_UNITS = { 36, 40, 32, 32 }          -- per tier: a cheap-unit composition does not become a 90-unit blob
local ENGAGE_SHARE = 0.08                     -- enemies worth an engagement: this share of the army's strength

---------------------------------------------------------------------------- static data

local SIDES = { "arm", "cor", "leg" }
local comps = {}
for _, side in ipairs(SIDES) do
	local path = "luarules/configs/ai_compositions_" .. side .. ".lua"
	if VFS.FileExists(path) then
		local ok, data = pcall(VFS.Include, path)
		if ok and type(data) == "table" then
			comps[side] = data
		else
			Spring.Echo("[doctrine] cannot load " .. path .. ": " .. tostring(data))
		end
	end
end

local FACTORY_TIER = {}
for _, n in ipairs({ "armlab", "armvp", "armap", "armhp", "corlab", "corvp", "corap", "corhp", "leglab", "legvp", "legap", "leghp", "armfhp", "corfhp", "legfhp" }) do
	FACTORY_TIER[n] = 1
end
for _, n in ipairs({ "armalab", "armavp", "armaap", "coralab", "coravp", "coraap", "legalab", "legavp", "legaap" }) do
	FACTORY_TIER[n] = 2
end
for _, n in ipairs({ "armshltx", "corgant", "leggant" }) do
	FACTORY_TIER[n] = 3
end
for _, n in ipairs({ "armt4gant", "cort4gant", "legt4gant" }) do
	FACTORY_TIER[n] = 4
end

local LOW_AIR = { armap = true, armaap = true, corap = true, coraap = true, legap = true, legaap = true }

local unitCost, unitSpeed, unitRange, unitRole, isStructure, isFactory, factoryBuilds = {}, {}, {}, {}, {}, {}, {}
local isLowLand = {} -- v23: T1/T2 land factory udid (quiet in the late game, see NO_LOW_INCOME)
local unitSize = {} -- elmos between two of them in a formation line
local ecoDefs = {}
for udid, ud in pairs(UnitDefs) do
	unitCost[udid] = ud.metalCost + ud.energyCost / 70
	unitSpeed[udid] = ud.speed or 0
	unitSize[udid] = max(70, (math.max(ud.xsize or 2, ud.zsize or 2)) * 8 * 1.6)
	isStructure[udid] = ud.isImmobile or (ud.speed or 0) == 0
	if ud.extractsMetal and ud.extractsMetal > 0 or (ud.energyMake or 0) > 5 or ud.customParams.energyconv_capacity or ud.isBuilder then
		ecoDefs[udid] = true
	end
	local range, ground, air, lobbed = 0, false, false, false
	for _, w in ipairs(ud.weapons) do
		local wd = WeaponDefs[w.weaponDef]
		if wd and (wd.damages and (wd.damages[0] or 0) > 1 or wd.paralyzer) and wd.type ~= "Shield" then
			local toAir = w.onlyTargets and w.onlyTargets.vtol and not w.onlyTargets.notair
			local cats = w.onlyTargets or {}
			local airOnly = (cats.vtol and not cats.surface and not cats.notair) or (wd.canAttackGround == false)
			if airOnly then
				air = true
			else
				ground = true
				range = max(range, wd.range or 0)
				if wd.type == "Cannon" and (wd.highTrajectory == 1 or (wd.range or 0) >= 900) or wd.type == "StarburstLauncher" then
					lobbed = true
				end
			end
		end
	end
	unitRange[udid] = range
	local role
	if ud.canFly then
		role = "air"
	elseif not ground and air then
		role = "aa"
	elseif not ground then
		role = "support"
	elseif range >= 1000 or (lobbed and range >= 700) then
		role = "artillery"
	elseif range >= 480 then
		role = "skirm"
	else
		role = "front"
	end
	unitRole[udid] = role
	local tier = FACTORY_TIER[ud.name]
	if tier then
		isFactory[udid] = tier
		isLowLand[udid] = tier <= 2 and not LOW_AIR[ud.name] or nil
		factoryBuilds[udid] = {}
		for _, b in ipairs(ud.buildOptions or {}) do
			factoryBuilds[udid][b] = true
		end
	end
end

local function defID(name)
	local ud = UnitDefNames[name]
	return ud and ud.id
end

---------------------------------------------------------------------------- state

local teams = {}      -- teamID -> { side, ally, armies, factories = {uid = tier}, used = {compId,...}, next army id }
local owns = {}       -- unitID -> army (planned units, forming or launched)
local pending = {}    -- unitID (nanoframe) -> army
local facState = {}   -- factory unitID -> { planned = n since skip, skip = bool, next = defName }
local enemyGrid = {}  -- allyTeam -> { frame, cells = { key -> {x, z, army, eco, def, struct, value} } }
local armyId = 0

local function log(fmt, ...)
	Spring.Echo("[doctrine] " .. string.format(fmt, ...))
end

local function toAI(teamID, text)
	SendToUnsynced("doctrine_aimsg", teamID, text)
end

local function frameNow()
	return Spring.GetGameFrame()
end

local function lateOf(teamID)
	local _, _, _, income = spGetTeamResources(teamID, "metal")
	return max(0, min(1, ((income or 0) - LATE_FROM) / (LATE_FULL - LATE_FROM))), income or 0
end

local function sideOf(teamID)
	local _, _, _, _, side = Spring.GetTeamInfo(teamID, false)
	side = (side or ""):lower()
	if side:find("arm") then
		return "arm"
	elseif side:find("cor") then
		return "cor"
	elseif side:find("leg") then
		return "leg"
	end
	-- random side: look at the commander
	for _, uid in ipairs(Spring.GetTeamUnits(teamID)) do
		local ud = UnitDefs[spGetUnitDefID(uid)]
		if ud and ud.customParams.iscommander then
			return ud.name:sub(1, 3)
		end
	end
	return nil
end

local function startPos(teamID)
	local x, _, z = Spring.GetTeamStartPosition(teamID)
	if not x or x < 0 then
		x, z = MAPX / 2, MAPZ / 2
	end
	return x, z
end

local function enemyHome(teamID)
	local ally = select(6, Spring.GetTeamInfo(teamID, false))
	local sx, sz = startPos(teamID)
	local best, bx, bz
	for _, t in ipairs(Spring.GetTeamList()) do
		local _, _, isDead, _, _, a = Spring.GetTeamInfo(t, false)
		if a ~= ally and not isDead and t ~= Spring.GetGaiaTeamID() then
			local x, z = startPos(t)
			local d = (x - sx) ^ 2 + (z - sz) ^ 2
			if not best or d < best then
				best, bx, bz = d, x, z
			end
		end
	end
	return bx or MAPX - sx, bz or MAPZ - sz
end

local function clampMap(x, z)
	return max(96, min(MAPX - 96, x)), max(96, min(MAPZ - 96, z))
end

local function norm(dx, dz)
	local d = sqrt(dx * dx + dz * dz)
	if d < 1 then
		return 0, 1, 0
	end
	return dx / d, dz / d, d
end

---------------------------------------------------------------------------- enemy picture (what the ally team sees)

local function visible(uid, ally)
	local los = spGetUnitLosState(uid, ally, true)
	return los and los ~= 0
end

local function enemyCells(ally, f)
	local g = enemyGrid[ally]
	if g and f - g.frame < 90 then
		return g.cells
	end
	local cells = {}
	for _, uid in ipairs(Spring.GetAllUnits()) do
		local a = spGetUnitAllyTeam(uid)
		if a ~= ally and spGetUnitTeam(uid) ~= Spring.GetGaiaTeamID() and visible(uid, ally) then
			local udid = spGetUnitDefID(uid)
			local x, _, z = spGetUnitPosition(uid)
			local _, _, _, _, bp = spGetUnitHealth(uid)
			if x and udid and (bp or 1) > 0.3 then
				local key = floor(x / CELL) .. ":" .. floor(z / CELL)
				local c = cells[key]
				if not c then
					c = { x = 0, z = 0, w = 0, army = 0, eco = 0, def = 0, struct = 0, n = 0 }
					cells[key] = c
				end
				local cost = unitCost[udid] or 0
				c.x, c.z, c.w, c.n = c.x + x, c.z + z, c.w + 1, c.n + 1
				if isStructure[udid] then
					c.struct = c.struct + cost
					if (unitRange[udid] or 0) > 0 and unitRole[udid] ~= "aa" then
						c.def = c.def + cost
					end
					if ecoDefs[udid] or isFactory[udid] then
						c.eco = c.eco + cost
					end
				elseif unitRange[udid] and unitRange[udid] > 0 then
					c.army = c.army + cost
				elseif ecoDefs[udid] then
					c.eco = c.eco + cost
				end
			end
		end
	end
	for _, c in pairs(cells) do
		c.x, c.z = c.x / c.w, c.z / c.w
	end
	enemyGrid[ally] = { frame = f, cells = cells }
	return cells
end

-- enemy fighting strength around a point (visible units only)
local function enemyStrength(x, z, r, ally)
	local sum, sx, sz, n = 0, 0, 0, 0
	for _, uid in ipairs(spGetUnitsInCylinder(x, z, r)) do
		local a = spGetUnitAllyTeam(uid)
		if a ~= ally and spGetUnitTeam(uid) ~= Spring.GetGaiaTeamID() and not spGetUnitIsDead(uid) and visible(uid, ally) then
			local udid = spGetUnitDefID(uid)
			if (unitRange[udid] or 0) > 0 then
				local c = unitCost[udid] or 0
				local hp, mhp = spGetUnitHealth(uid)
				c = c * (hp and mhp and mhp > 0 and hp / mhp or 1)
				if isStructure[udid] then
					c = c * 1.5
				end
				local ux, _, uz = spGetUnitPosition(uid)
				sum, sx, sz, n = sum + c, sx + ux * c, sz + uz * c, n + 1
			end
		end
	end
	if sum > 0 then
		return sum, sx / sum, sz / sum, n
	end
	return 0
end

---------------------------------------------------------------------------- planning

local function teamFactories(t)
	local out, maxTier = {}, 0
	for uid, tier in pairs(t.factories) do
		if spValidUnitID(uid) and not spGetUnitIsDead(uid) then
			local _, _, _, _, bp = spGetUnitHealth(uid)
			if bp and bp >= 1 and not (t.noLow and isLowLand[spGetUnitDefID(uid)]) then
				out[#out + 1] = uid
				if tier > maxTier then
					maxTier = tier
				end
			end
		else
			t.factories[uid] = nil
		end
	end
	return out, maxTier
end

local function canBuildDef(facs, udid)
	for _, uid in ipairs(facs) do
		local b = factoryBuilds[spGetUnitDefID(uid)]
		if b and b[udid] then
			return true
		end
	end
	return false
end

local function teamHasUnit(teamID, name)
	local udid = defID(name)
	return udid and Spring.GetTeamUnitDefCount(teamID, udid) > 0
end

-- the hero a T4 composition is led by: its own hero when the team has it, else (v19: ten heroes per side, the
-- compositions name four of them) any living hero of the team, the ones not leading another army first
local function compHero(teamID, t, name)
	if teamHasUnit(teamID, name) then
		return name
	end
	local all = GG.T4Heroes and GG.T4Heroes.heroes
	if not all then
		return nil
	end
	local leading = {}
	for _, a in ipairs(t and t.armies or {}) do
		if a.hero then
			leading[a.hero] = true
		end
	end
	local pick, spare
	for uid, h in pairs(all) do
		if h.team == teamID and h.def and h.def.name and not spGetUnitIsDead(uid) then
			if not leading[h.def.name] then
				if not pick or h.def.name < pick then
					pick = h.def.name
				end
			elseif not spare or h.def.name < spare then
				spare = h.def.name
			end
		end
	end
	return pick or spare
end

-- share of the composition (by count weight) the current factories can build
local function feasibility(comp, facs, teamID, t)
	local total, ok = 0, 0
	for _, e in ipairs(comp.units) do
		local udid = defID(e[1])
		if e.hero then
			if not (udid and compHero(teamID, t, e[1])) then
				return 0
			end
		elseif udid and (e[2] or 0) > 0 then
			total = total + e[2]
			if canBuildDef(facs, udid) then
				ok = ok + e[2]
			end
		end
	end
	return total > 0 and ok / total or 0
end

local function pickTier(maxTier, late, noLow)
	local w = {}
	for i, x in ipairs(TIER_ODDS[min(4, max(1, maxTier))]) do
		w[i] = x
	end
	if noLow and maxTier >= 3 then
		w[1], w[2] = 0, 0 -- v23: T3/T4 armies only
	elseif w[2] then
		w[2] = w[2] + LATE_T2 * (late or 0) -- late game: mass T2 armies
	end
	local sum = 0
	for _, x in ipairs(w) do
		sum = sum + x
	end
	local r = random() * sum
	for i, x in ipairs(w) do
		r = r - x
		if r <= 0 then
			return i
		end
	end
	return #w
end

local function recentlyUsed(t, id)
	for _, u in ipairs(t.used) do
		if u == id then
			return true
		end
	end
	return false
end

local function makePlan(t, comp, tier, facs, income, late)
	local b = BUDGET[tier]
	late = late or 0
	local budget = max(b.lo, min(b.hi * (1 + LATE_BUDGET * late), income * b.sec))
	local weightCost, entries = 0, {}
	for _, e in ipairs(comp.units) do
		local udid = defID(e[1])
		if udid and not e.hero and (e[2] or 0) > 0 and canBuildDef(facs, udid) then
			entries[#entries + 1] = { udid = udid, name = e[1], w = e[2], role = e.role }
			weightCost = weightCost + e[2] * unitCost[udid]
		end
	end
	if weightCost <= 0 then
		return nil
	end
	local k = budget / weightCost
	-- a cheap composition hits the unit cap before the budget
	local wsum = 0
	for _, e in ipairs(entries) do
		wsum = wsum + e.w
	end
	k = min(k, MAX_UNITS[tier] * (1 + LATE_UNITS * late) / wsum)
	local want, metal, count = {}, 0, 0
	for _, e in ipairs(entries) do
		local n = max(1, floor(e.w * k + 0.5))
		want[e.udid] = n
		metal = metal + n * unitCost[e.udid]
		count = count + n
	end
	if comp.min and count < comp.min then
		local s = comp.min / count
		metal, count = 0, 0
		for udid, n in pairs(want) do
			want[udid] = max(n, floor(n * s + 0.5))
			metal = metal + want[udid] * unitCost[udid]
			count = count + want[udid]
		end
	end
	local roleOver = {}
	for _, e in ipairs(entries) do
		if e.role then
			roleOver[e.udid] = e.role
		end
	end
	local hero
	for _, e in ipairs(comp.units) do
		if e.hero then
			hero = compHero(t.team, t, e[1]) or e[1]
		end
	end
	return { want = want, metal = metal, count = count, roleOver = roleOver, hero = hero }
end

local function newArmy(teamID, t, f)
	local facs, maxTier = teamFactories(t)
	if #facs == 0 or not comps[t.side] then
		return nil
	end
	local late, income = lateOf(teamID)
	-- the tier: the best one available, sometimes a cheaper army for variety; T4 needs a living hero
	for try = 1, 8 do
		local tier = try <= 6 and pickTier(maxTier, late, t.noLow) or (try == 7 and 2 or 1)
		if try <= 3 and t.dir and t.dir.tier then
			tier = min(maxTier, t.dir.tier) -- the general's tier, while it is buildable
		end
		if t.noLow and maxTier >= 3 then
			tier = max(3, tier) -- v23: no T1/T2 armies in the late game, the general's pick and the last tries too
		end
		local list = comps[t.side]["t" .. tier] or {}
		local cands, sum = {}, 0
		-- v22: after 4 misses a composition the factories make only in part (>= 50%) is fine too (the rest is
		-- left out of the plan); the last two tries go for T2, then T1 (the AI never stays without a plan)
		local need = try <= 4 and 0.75 or 0.5
		for _, comp in ipairs(list) do
			local feas = feasibility(comp, facs, teamID, t)
			if feas >= need and (try > 6 or not recentlyUsed(t, comp.id)) then
				-- tactics the situation calls for weigh more; a general's preferences on top (v22)
				local w = feas * (t.dir and t.dir.prefer and t.dir.prefer[comp.tactic or "assault"] or 1)
				if comp.tactic == "defend" then
					w = w * (t.threatened and 3 or 0.4)
				end
				cands[#cands + 1] = { comp = comp, w = w }
				sum = sum + w
			end
		end
		if #cands > 0 then
			local r = random() * sum
			local pick = cands[#cands].comp
			for _, c in ipairs(cands) do
				r = r - c.w
				if r <= 0 then
					pick = c.comp
					break
				end
			end
			local plan = makePlan(t, pick, tier, facs, income, late)
			if plan then
				armyId = armyId + 1
				local sx, sz = startPos(teamID)
				local ex, ez = enemyHome(teamID)
				local dx, dz, d = norm(ex - sx, ez - sz)
				local rx, rz = clampMap(sx + dx * min(1600, d * 0.22), sz + dz * min(1600, d * 0.22))
				local army = {
					id = armyId, team = teamID, ally = t.ally, comp = pick, tier = tier, tactic = pick.tactic or "assault",
					want = plan.want, planMetal = plan.metal, planCount = plan.count, roleOver = plan.roleOver, hero = plan.hero,
					units = {}, n = 0, made = {}, state = "forming", since = f, rallyX = rx, rallyZ = rz,
					launchStrength = 0, kills = 0, losses = 0, engagements = 0, launches = 0,
					spreadSum = 0, spreadN = 0,
				}
				t.armies[#t.armies + 1] = army
				t.used[#t.used + 1] = pick.id
				if #t.used > 4 then
					table.remove(t.used, 1)
				end
				local parts = {}
				for udid, n in pairs(plan.want) do
					parts[#parts + 1] = UnitDefs[udid].name .. "x" .. n
				end
				table.sort(parts)
				log("t=%d team=%d army#%d plan %s T%d %s \"%s\": %d units, %d metal%s | %s", floor(f / 1800), teamID, army.id,
					pick.id, tier, army.tactic, pick.name or pick.id, plan.count, plan.metal, plan.hero and (" + hero " .. plan.hero) or "",
					table.concat(parts, " "))
				return army
			end
		end
	end
	return nil
end

---------------------------------------------------------------------------- production

-- what the forming army still needs, counting units alive in it and those under construction for it
local function missing(army)
	local have = {}
	for uid in pairs(army.units) do
		local udid = spGetUnitDefID(uid)
		if udid then
			have[udid] = (have[udid] or 0) + 1
		end
	end
	for uid, a in pairs(pending) do
		if a == army then
			local udid = spGetUnitDefID(uid)
			if udid then
				have[udid] = (have[udid] or 0) + 1
			end
		end
	end
	local out = {}
	for udid, n in pairs(army.want) do
		local m = n - (have[udid] or 0)
		if m > 0 then
			out[udid] = m
		end
	end
	return out
end

local function armyNeeding(t)
	-- a beaten army refilling at the rally point first (its veterans are there), then the forming one
	for _, a in ipairs(t.armies) do
		if a.state == "regroup" then
			return a
		end
	end
	for _, a in ipairs(t.armies) do
		if a.state == "forming" then
			return a
		end
	end
end

-- what every gathering army still needs: udid -> { army, missing }, a refilling army before the forming one
local function teamNeeds(t)
	local out = {}
	for _, state in ipairs({ "regroup", "forming" }) do
		for _, a in ipairs(t.armies) do
			if a.state == state then
				for udid, m in pairs(missing(a)) do
					if not out[udid] then
						out[udid] = { army = a, m = m }
					end
				end
			end
		end
	end
	return out
end

local function updateProduction(teamID, t)
	local needs = teamNeeds(t)
	for uid, tier in pairs(t.factories) do
		local fs = facState[uid]
		if not fs then
			fs = { planned = 0, skip = false, next = "" }
			facState[uid] = fs
		end
		local nextName = ""
		local fdid = spGetUnitDefID(uid) or -1
		if not fs.skip and tier < 4 and not (t.noLow and isLowLand[fdid]) then
			local b = factoryBuilds[fdid]
			local best, bestShare
			for udid, nd in pairs(needs) do
				if b and b[udid] then
					local share = nd.m / max(1, nd.army.want[udid]) + (nd.army.state == "regroup" and 1 or 0)
					if not bestShare or share > bestShare or (share == bestShare and udid < best) then
						best, bestShare = udid, share
					end
				end
			end
			if best then
				nextName = UnitDefs[best].name
			end
		end
		if nextName ~= fs.next then
			fs.next = nextName
			spSetUnitRulesParam(uid, "doctrine_next", nextName, ALLIED)
		end
	end
end

---------------------------------------------------------------------------- the army in the field

local function roleOf(army, uid)
	local udid = spGetUnitDefID(uid)
	return army.roleOver[udid] or unitRole[udid] or "skirm"
end

local function addUnit(army, uid)
	army.units[uid] = true
	army.n = army.n + 1
	owns[uid] = army
	army.made[#army.made + 1] = uid
	army.grew = Spring.GetGameFrame()
	spSetUnitRulesParam(uid, "doctrine_army", army.id) -- public: spectators and the bench camera see the armies
end

local function removeUnit(army, uid)
	if army.units[uid] then
		army.units[uid] = nil
		army.n = army.n - 1
	end
	owns[uid] = nil
end

local function armyStats(army)
	local cx, cz, cost, strength, slow, n = 0, 0, 0, 0, 1e9, 0
	local maxRange = 0
	for uid in pairs(army.units) do
		local x, _, z = spGetUnitPosition(uid)
		local udid = spGetUnitDefID(uid)
		if x and udid then
			local c = unitCost[udid] or 0
			local hp, mhp = spGetUnitHealth(uid)
			local s = c * (hp and mhp and mhp > 0 and hp / mhp or 1)
			cx, cz, cost, strength, n = cx + x * c, cz + z * c, cost + c, strength + s, n + 1
			local sp = unitSpeed[udid] or 0
			if sp > 0 and sp < slow then
				slow = sp
			end
			maxRange = max(maxRange, unitRange[udid] or 0)
		end
	end
	if cost <= 0 then
		return nil
	end
	cx, cz = cx / cost, cz / cost
	local spread = 0
	for uid in pairs(army.units) do
		local x, _, z = spGetUnitPosition(uid)
		if x then
			spread = spread + sqrt((x - cx) ^ 2 + (z - cz) ^ 2)
		end
	end
	-- the main body: units within 900 of the anchor (the anchor waits for it, stragglers do not hold it)
	local bx, bz, bc, bn = 0, 0, 0, 0
	if army.anchorX then
		for uid in pairs(army.units) do
			local x, _, z = spGetUnitPosition(uid)
			if x and (x - army.anchorX) ^ 2 + (z - army.anchorZ) ^ 2 < 900 * 900 then
				local c = unitCost[spGetUnitDefID(uid)] or 1
				bx, bz, bc, bn = bx + x * c, bz + z * c, bc + c, bn + 1
			end
		end
	end
	local body = bc > 0 and { x = bx / bc, z = bz / bc, share = bc / cost, n = bn } or nil
	return { x = cx, z = cz, cost = cost, strength = strength, slow = slow < 1e9 and slow or 60, n = n, range = maxRange,
		spread = spread / max(1, n), body = body }
end

-- the target of an army by its tactic, from what its ally team sees
-- v22: the targets of the ally team's other armies in the field (one force hits one place)
local function alliedTargets(army)
	local out = {}
	for _, tm in pairs(teams) do
		if tm.ally == army.ally then
			for _, a in ipairs(tm.armies) do
				if a ~= army and a.target and (a.state == "march" or a.state == "engage") and a.tactic ~= "raid" and a.tactic ~= "defend" then
					out[#out + 1] = a.target
				end
			end
		end
	end
	return out
end

-- v22: fighting strength of the ally team's other armies in the field within r of (x, z)
local function alliedNear(army, x, z, r)
	local s = 0
	for _, tm in pairs(teams) do
		if tm.ally == army.ally then
			for _, a in ipairs(tm.armies) do
				local st = a.last
				if a ~= army and st and (a.state == "march" or a.state == "engage") and (st.x - x) ^ 2 + (st.z - z) ^ 2 < r * r then
					s = s + st.strength
				end
			end
		end
	end
	return s
end

local function chooseTarget(army, st, f)
	-- v22: the external commander's focus point beats everything but home defence
	local dir = teams[army.team] and teams[army.team].dir
	if dir and dir.focus and army.tactic ~= "defend" then
		return dir.focus[1], dir.focus[2], "focus", 1e12
	end
	local cells = enemyCells(army.ally, f)
	local best, bx, bz, kind
	local hx, hz = startPos(army.team)
	local focus = (army.tactic == "assault" or army.tactic == "siege" or army.tactic == "skirmish") and alliedTargets(army) or {}
	for _, c in pairs(cells) do
		local d = sqrt((c.x - st.x) ^ 2 + (c.z - st.z) ^ 2)
		local home = sqrt((c.x - hx) ^ 2 + (c.z - hz) ^ 2)
		local score, k
		local t = army.tactic
		if t == "raid" then
			-- economy far from enemy armies and defences
			if c.eco > 0 and c.army + c.def * 1.5 < st.strength * 0.6 then
				score, k = c.eco / (1 + d / 1500), "eco"
			end
		elseif t == "siege" then
			if c.struct > 0 then
				score, k = (c.struct + c.def) / (1 + d / 2500), "base"
			end
		elseif t == "skirmish" then
			if c.army > 0 and c.army < st.strength * 1.4 and d < 5000 then
				score, k = c.army / (1 + d / 2000), "army"
			elseif c.eco > 0 then
				score, k = c.eco * 0.3 / (1 + d / 2000), "eco"
			end
		elseif t == "defend" then
			if home < 3000 and (c.army > 0 or c.def > 0) then
				score, k = (c.army + c.def) / (1 + home / 1000), "intruders"
			end
		else -- assault, air
			local v = c.struct + c.eco + c.army * 0.8
			if v > 0 and (c.army + c.def * 1.5) < st.strength * (t == "air" and 1.0 or 1.6) then
				score, k = v / (1 + d / 2500), c.struct > 0 and "base" or "army"
			end
		end
		if score then
			for _, ft in ipairs(focus) do
				if (ft[1] - c.x) ^ 2 + (ft[2] - c.z) ^ 2 < 1600 * 1600 then
					score = score * 1.6 -- join the push of another army
					break
				end
			end
		end
		if score and (not best or score > best) then
			best, bx, bz, kind = score, c.x, c.z, k
		end
	end
	if not bx then
		if army.tactic == "defend" then
			return army.rallyX, army.rallyZ, "hold", 0
		end
		-- nothing known worth it: first the enemy start, then sweep the enemy half (metal spots first), a new
		-- point every time the army gets there (scouting in force: survivors and expansions are found)
		local ex, ez = enemyHome(army.team)
		if not army.swept or (st.x - ex) ^ 2 + (st.z - ez) ^ 2 > 2500 * 2500 and not army.sweeping then
			army.sweeping = true
			return ex, ez, "enemy start", 0
		end
		local spots = GG.resource_spot_finder and GG.resource_spot_finder.metalSpotsList or {}
		local hx, hz = startPos(army.team)
		local best, bx, bz
		for i = 1, 12 do
			local x, z
			local spot = #spots > 0 and spots[random(#spots)]
			if spot then
				x, z = spot.x, spot.z
			else
				x, z = random(200, MAPX - 200), random(200, MAPZ - 200)
			end
			-- the enemy's side of the map, far from where we swept last
			local score = sqrt((x - hx) ^ 2 + (z - hz) ^ 2) - sqrt((x - ex) ^ 2 + (z - ez) ^ 2) * 0.5
			if army.lastSweep then
				score = score + sqrt((x - army.lastSweep[1]) ^ 2 + (z - army.lastSweep[2]) ^ 2) * 0.3
			end
			if not best or score > best then
				best, bx, bz = score, x, z
			end
		end
		army.lastSweep = { bx, bz }
		return bx, bz, "sweep", 0
	end
	return bx, bz, kind, best
end

-- what the army's current target is still worth (the same score as chooseTarget, for its cell)
local function currentTargetValue(army, f)
	if not army.target then
		return nil
	end
	local cells = enemyCells(army.ally, f)
	local c = cells[floor(army.target[1] / CELL) .. ":" .. floor(army.target[2] / CELL)]
	if not c then
		return nil
	end
	local st = army.last
	local d = st and sqrt((c.x - st.x) ^ 2 + (c.z - st.z) ^ 2) or 0
	local t = army.tactic
	if t == "raid" then
		return c.eco > 0 and c.eco / (1 + d / 1500) or nil
	elseif t == "siege" then
		return c.struct > 0 and (c.struct + c.def) / (1 + d / 2500) or nil
	elseif t == "skirmish" then
		return c.army > 0 and c.army / (1 + d / 2000) or nil
	end
	local v = c.struct + c.eco + c.army * 0.8
	return v > 0 and v / (1 + d / 2500) or nil
end

local function order(uid, cmd, x, z, opts)
	local y = spGetGroundHeight(x, z)
	spGiveOrderToUnit(uid, cmd, { x, y, z }, opts or 0)
end

-- every unit to its role's slot around (ax, az), facing (dx, dz); fight = FIGHT instead of MOVE
-- v22: the roles stand in blocks one behind the other (front line ahead of the anchor, then skirmishers, AA,
-- support, artillery at its range), every block as wide as the army's common row, rows centred: a rectangle
-- instead of role lines drawn over each other
local ROLE_ORDER = { "front", "skirm", "aa", "support", "air", "artillery" }
local function formation(army, ax, az, dx, dz, fight, f)
	local byRole, total = {}, 0
	for uid in pairs(army.units) do
		local r = roleOf(army, uid)
		if not byRole[r] then
			byRole[r] = {}
		end
		byRole[r][#byRole[r] + 1] = uid
		total = total + 1
	end
	local px, pz = -dz, dx -- perpendicular
	local width = max(6, floor(sqrt(total) * 1.7 + 0.5))
	local cursor
	for _, role in ipairs(ROLE_ORDER) do
		local list = byRole[role]
		if list then
			table.sort(list)
			local n = #list
			local gap = 70
			for _, uid in ipairs(list) do
				gap = max(gap, unitSize[spGetUnitDefID(uid) or -1] or 70)
			end
			local perRow = min(n, width)
			local rows = floor((n - 1) / perRow) + 1
			local rowGap = gap * 1.15
			if not cursor then
				cursor = 120 + (rows - 1) * rowGap -- the first block's front row ahead of the anchor
			end
			local top = cursor
			if role == "artillery" then
				local range = 0
				for _, uid in ipairs(list) do
					range = max(range, unitRange[spGetUnitDefID(uid) or -1] or 600)
				end
				top = min(cursor, -min(700, max(250, range * 0.55)))
			elseif role == "air" then
				top = 0
			end
			for i, uid in ipairs(list) do
				local row = floor((i - 1) / perRow)
				local inRow = min(perRow, n - row * perRow)
				local col = (i - 1) % perRow - (inRow - 1) / 2
				local a = top - row * rowGap
				local sx = ax + dx * a + px * col * gap
				local sz = az + dz * a + pz * col * gap
				sx, sz = clampMap(sx, sz)
				local ux, _, uz = spGetUnitPosition(uid)
				if ux then
					local prev = army.slot and army.slot[uid]
					local moved = not prev or (prev[1] - sx) ^ 2 + (prev[2] - sz) ^ 2 > 150 * 150
					local idle = spGetUnitCommands(uid) == 0
					local far = (ux - sx) ^ 2 + (uz - sz) ^ 2 > 120 * 120
					if (moved or idle) and (far or fight) then
						order(uid, fight and CMD.FIGHT or CMD.MOVE, sx, sz)
						army.slot = army.slot or {}
						army.slot[uid] = { sx, sz }
					end
				end
			end
			if role ~= "air" and role ~= "artillery" then
				cursor = top - rows * rowGap - 30
			end
		end
	end
end

local function launch(army, st, f)
	army.state = "march"
	army.launchStrength = st.strength
	army.launches = army.launches + 1
	army.since = f
	army.anchorX, army.anchorZ = st.x, st.z
	army.target = nil
	local counts = {}
	for uid in pairs(army.units) do
		local r = roleOf(army, uid)
		counts[r] = (counts[r] or 0) + 1
	end
	local parts = {}
	for r, n in pairs(counts) do
		parts[#parts + 1] = r .. "=" .. n
	end
	table.sort(parts)
	log("t=%d team=%d army#%d %s launches (%s, %d units, %d metal, %s)", floor(f / 1800), army.team, army.id, army.comp.id,
		army.launches > 1 and "again" or "first time", st.n, st.cost, table.concat(parts, " "))
end

local function retreat(army, st, f, why)
	army.state = "retreat"
	army.since = f
	army.retreats = (army.retreats or 0) + 1
	log("t=%d team=%d army#%d %s retreats (%s): %d units left, strength %d of %d, kills %d metal, losses %d", floor(f / 1800),
		army.team, army.id, army.comp.id, why, st.n, st.strength, army.launchStrength, army.kills, army.losses)
end

-- a unit that has not moved 40 elmos in 30 s while far from its slot is stuck (cliffs, water, a wreck
-- field): it goes back to the AI and leaves the army (so it does not hold the march)
local function releaseStuck(army, f)
	army.pos = army.pos or {}
	for uid in pairs(army.units) do
		local x, _, z = spGetUnitPosition(uid)
		if x then
			local p = army.pos[uid]
			if not p or (p[1] - x) ^ 2 + (p[2] - z) ^ 2 > 40 * 40 then
				army.pos[uid] = { x, z, f }
			elseif f - p[3] > 30 * GAME_SPEED and army.anchorX and (x - army.anchorX) ^ 2 + (z - army.anchorZ) ^ 2 > 1100 * 1100 then
				removeUnit(army, uid)
				army.pos[uid] = nil
				army.stuck = (army.stuck or 0) + 1
				spSetUnitRulesParam(uid, "doctrine_army", 0)
				toAI(army.team, "attach " .. uid)
			end
		end
	end
end

-- a gathering army whose missing units no factory can make (BARb replaced or lost the factory) or that
-- has not grown for STALL frames settles for what it has: the plan shrinks to it, or a handful of units
-- goes back to the AI and the army is dropped (so a new plan can start)
local STALL = 4 * 60 * GAME_SPEED
local function settle(army, f)
	local t = teams[army.team]
	if not t or (army.state ~= "forming" and army.state ~= "regroup") then
		return
	end
	local miss = missing(army)
	if next(miss) == nil then
		return -- complete: nothing to settle
	end
	if army.levy then
		-- a levy is what the AI had: no refills, the plan is what is left (dropped below three units)
		local have, metal, n = {}, 0, 0
		for uid in pairs(army.units) do
			local udid = spGetUnitDefID(uid)
			if udid then
				have[udid] = (have[udid] or 0) + 1
				metal, n = metal + (unitCost[udid] or 0), n + 1
			end
		end
		if n >= 3 then
			army.want, army.planMetal = have, metal
			return
		end
	end
	local facs = teamFactories(t)
	local makeable = false
	for udid in pairs(miss) do
		if canBuildDef(facs, udid) then
			makeable = true
			break
		end
	end
	local stalled = f - (army.grew or army.since) > STALL
	if makeable and not stalled then
		return
	end
	local have, n, metal = {}, 0, 0
	for uid in pairs(army.units) do
		local udid = spGetUnitDefID(uid)
		if udid then
			have[udid] = (have[udid] or 0) + 1
			n = n + 1
			metal = metal + (unitCost[udid] or 0)
		end
	end
	if n < 3 then
		for uid in pairs(army.units) do
			removeUnit(army, uid)
			spSetUnitRulesParam(uid, "doctrine_army", 0)
			toAI(army.team, "attach " .. uid)
		end
		army.n = 0
		army.state = "dead"
		log("t=%d team=%d army#%d %s dropped (%s): its units go back to the AI", floor(f / 1800), army.team, army.id, army.comp.id,
			makeable and "stalled" or "no factory for it")
		return
	end
	army.want = have
	army.planMetal = metal
	army.grew = f
	log("t=%d team=%d army#%d %s settles for %d units, %d metal (%s)", floor(f / 1800), army.team, army.id, army.comp.id, n, metal,
		makeable and "stalled" or "no factory for the rest")
end

local function driveArmy(army, f)
	-- v22: units the external commander took (cmd_ai_commander) leave the army: two drivers fight over them
	local taken = GG.AICommanderUnits
	if taken then
		for uid in pairs(army.units) do
			if taken[uid] then
				removeUnit(army, uid)
				spSetUnitRulesParam(uid, "doctrine_army", 0)
			end
		end
	end
	settle(army, f)
	if army.state == "dead" then
		return false
	end
	local st = armyStats(army)
	if not st then
		return false
	end
	army.last = st
	local t = army.tactic
	if army.state == "forming" or army.state == "regroup" then
		-- gather at the rally point; launch when (nearly) complete
		local hx, hz = startPos(army.team)
		local fdx, fdz = norm(army.rallyX - hx, army.rallyZ - hz)
		formation(army, army.rallyX, army.rallyZ, fdx, fdz, false, f)
		local share = st.cost / max(1, army.planMetal)
		local waited = f - army.since
		local want = army.state == "regroup" and REFILL_SHARE or (LAUNCH_BY_TACTIC[t] or LAUNCH_SHARE)
		local ready = share >= want or (waited > LAUNCH_WAIT and share >= LAUNCH_LATE) or (army.state == "regroup" and waited > LAUNCH_WAIT * 1.5 and share >= 0.4)
		-- a beaten army waits at least a minute, and nobody launches into a stronger enemy at the doorstep
		if army.state == "regroup" and waited < 60 * GAME_SPEED then
			ready = false
		end
		-- v22 commander directives: gather holds every army at the rally point, go launches what is there
		local dir = teams[army.team] and teams[army.team].dir
		local goNow = dir and dir.go and dir.go >= (army.since or 0) and st.n >= 3
		if dir and dir.gather then
			ready = false
		end
		if ready and waited < LAUNCH_WAIT * 1.5 and not goNow then
			-- v22: the army leaves as one body - most of it at the rally point first
			local at = 0
			for uid in pairs(army.units) do
				local x, _, z = spGetUnitPosition(uid)
				if x and (x - army.rallyX) ^ 2 + (z - army.rallyZ) ^ 2 < 1000 * 1000 then
					at = at + (unitCost[spGetUnitDefID(uid)] or 0)
				end
			end
			if at < st.cost * GATHER_SHARE then
				ready = false
			end
		end
		if goNow then
			ready = true
		elseif ready then
			local near = enemyStrength(army.rallyX, army.rallyZ, 2600, army.ally)
			if near > st.strength * 2 and t ~= "defend" then
				ready = false
				army.heldBack = (army.heldBack or 0) + 1
			end
		end
		if ready then
			launch(army, st, f)
		elseif army.state == "regroup" and waited > 20 * GAME_SPEED then
			-- veterans that cannot go again alone join the army forming at home (one bigger force)
			local tm = teams[army.team]
			for _, other in ipairs(tm and tm.armies or {}) do
				if other ~= army and other.state == "forming" then
					for uid in pairs(army.units) do
						removeUnit(army, uid)
						addUnit(other, uid)
						other.roleOver[spGetUnitDefID(uid)] = other.roleOver[spGetUnitDefID(uid)] or army.roleOver[spGetUnitDefID(uid)]
					end
					other.planMetal = other.planMetal + st.cost
					log("t=%d team=%d army#%d %s merges into army#%d %s: %d units, %d metal", floor(f / 1800), army.team, army.id, army.comp.id,
						other.id, other.comp.id, st.n, st.cost)
					break
				end
			end
		end
		-- a gathering army does not stand under fire: it answers intruders near the rally point (a home
		-- army further out) and attacks on the base, unless they are far stronger
		local es, ex, ez = enemyStrength(army.rallyX, army.rallyZ, t == "defend" and 2500 or 1300, army.ally)
		local ht = teams[army.team] and teams[army.team].homeThreat
		if ht and (es <= 0 or ht.s > es) then
			es, ex, ez = ht.s, ht.x, ht.z
		end
		if es > 0 and es < st.strength * 2 then
			if f - (army.guardOrder or 0) > 3 * GAME_SPEED then
				army.guardOrder = f
				for uid in pairs(army.units) do
					order(uid, CMD.FIGHT, ex, ez)
				end
			end
			return true
		end
		return true
	end

	if army.state == "retreat" then
		local d = sqrt((st.x - army.rallyX) ^ 2 + (st.z - army.rallyZ) ^ 2)
		if f - (army.retreatOrder or 0) > 5 * GAME_SPEED then
			army.retreatOrder = f
			for uid in pairs(army.units) do
				order(uid, CMD.MOVE, army.rallyX + random(-200, 200), army.rallyZ + random(-200, 200))
			end
		end
		if d < 700 or f - army.since > 90 * GAME_SPEED then
			army.state = "regroup"
			army.since = f
			army.slot = nil
			log("t=%d team=%d army#%d %s regroups at the rally point: %d units, refilling to its plan", floor(f / 1800), army.team, army.id, army.comp.id, st.n)
		end
		return true
	end

	local dir = teams[army.team] and teams[army.team].dir
	if dir and dir.gather and t ~= "defend" then
		retreat(army, st, f, "mustered by the commander")
		return true
	end
	-- march / engage: retarget every 10 s or when the target is gone
	if not army.target or f - (army.targetFrame or 0) > 10 * GAME_SPEED then
		local tx, tz, kind, score = chooseTarget(army, st, f)
		-- keep the current target while it is still worth going (within 1.5x of the best), so the army
		-- does not swing between two far bases
		if army.target and army.targetScore and score and army.targetFrame and army.targetFrame > 0 then
			local cur = currentTargetValue(army, f)
			if cur and cur * 1.5 >= score then
				tx, tz, kind, score = army.target[1], army.target[2], army.targetKind, cur
			end
		end
		-- v22: a sweep point stands until the army gets there (or something real turns up): a new random point
		-- every 10 s had armies turning round and round
		local sweeping = { sweep = true, ["enemy start"] = true }
		if army.target and army.targetFrame and army.targetFrame > 0 and sweeping[army.targetKind] and sweeping[kind] then
			tx, tz, kind, score = army.target[1], army.target[2], army.targetKind, army.targetScore
		end
		if kind ~= army.targetKind or not army.target or (tx - army.target[1]) ^ 2 + (tz - army.target[2]) ^ 2 > 800 * 800 then
			log("t=%d team=%d army#%d %s targets %s at %d,%d (%d away)", floor(f / 1800), army.team, army.id, army.comp.id, kind,
				tx, tz, sqrt((tx - st.x) ^ 2 + (tz - st.z) ^ 2))
		end
		army.target, army.targetKind, army.targetFrame, army.targetScore = { tx, tz }, kind, f, score
	end
	local tx, tz = army.target[1], army.target[2]
	-- the base under attack: armies within 6000 of home turn back (raiders and air strikes go on)
	local ht = teams[army.team] and teams[army.team].homeThreat
	if ht and t ~= "raid" and t ~= "air" and ht.s < st.strength * 2.5 then
		local hx, hz = startPos(army.team)
		if (st.x - hx) ^ 2 + (st.z - hz) ^ 2 < 6000 * 6000 then
			if army.targetKind ~= "home defence" then
				log("t=%d team=%d army#%d %s turns back: the base is attacked (%d metal of enemies)", floor(f / 1800), army.team, army.id, army.comp.id, ht.s)
			end
			tx, tz = ht.x, ht.z
			army.target, army.targetKind, army.targetFrame = { tx, tz }, "home defence", f
		end
	end

	-- losses and odds
	local engageR = max(900, st.range * 1.2 + 350)
	local es, ex, ez, en = enemyStrength(st.x, st.z, engageR + 400, army.ally)
	local allin = dir and dir.allin
	if st.strength < army.launchStrength * (allin and 0.05 or RETREAT_STRENGTH) then
		retreat(army, st, f, "losses")
		return true
	end
	local own = st.strength + 0.7 * alliedNear(army, st.x, st.z, 2500)
	if es > own * (allin and 8 or RETREAT_ODDS) and t ~= "defend" then
		retreat(army, st, f, string.format("outnumbered %.1fx", es / max(1, own)))
		return true
	end
	-- v22: shot by enemies it cannot see (outranged by artillery, heroes, long-range defences): go for them
	-- instead of marching on under fire (armies used to melt with no engagement at all)
	local hit = army.hit and f - army.hit[3] < HIT_MEMORY and t ~= "raid" and t ~= "air" and army.hit
	local blind = false
	if hit and es <= st.strength * ENGAGE_SHARE then
		blind = true
		es, ex, ez, en = max(es, st.strength * ENGAGE_SHARE + 1), hit[1], hit[2], en or 0
	end
	if t == "raid" and es > st.strength * 0.9 and army.targetKind ~= "army" then
		-- raiders do not take fair fights: pick another target
		army.targetFrame = 0
	end

	if es > st.strength * ENGAGE_SHARE or (army.state == "engage" and es > 0) then
		-- engage: the front and skirmishers fight toward the enemy, artillery from its slot, AA with the army
		if army.state ~= "engage" then
			army.state = "engage"
			army.engagements = army.engagements + 1
			army.engageStart = f
			log("t=%d team=%d army#%d %s engages%s: own %d vs enemy %d (%d units)", floor(f / 1800), army.team, army.id, army.comp.id,
				blind and " an unseen shooter" or "", st.strength, es, en or 0)
		end
		local dx, dz = norm(ex - st.x, ez - st.z)
		-- siege: hold at artillery range of the enemy
		local ax, az = st.x, st.z
		local dist = sqrt((ex - st.x) ^ 2 + (ez - st.z) ^ 2)
		if t == "siege" and not blind then
			local keep = max(600, st.range * 0.85)
			local adv = max(0, dist - keep)
			ax, az = st.x + dx * min(adv, 200), st.z + dz * min(adv, 200)
		else
			local adv = blind and min(450, dist) or min(300, dist * 0.5)
			ax, az = st.x + dx * adv, st.z + dz * adv
		end
		army.anchorX, army.anchorZ = clampMap(ax, az)
		formation(army, army.anchorX, army.anchorZ, dx, dz, true, f)
		return true
	end
	if army.state == "engage" then
		army.state = "march"
		log("t=%d team=%d army#%d %s fight over after %ds: %d units, strength %d of %d", floor(f / 1800), army.team, army.id,
			army.comp.id, floor((f - (army.engageStart or f)) / GAME_SPEED), st.n, st.strength, army.launchStrength)
	end

	army.spreadSum, army.spreadN = army.spreadSum + st.spread, army.spreadN + 1
	-- an air strike group flies straight at its target (formation is for the ground)
	if t == "air" then
		if f - (army.airOrder or 0) > 5 * GAME_SPEED then
			army.airOrder = f
			for uid in pairs(army.units) do
				order(uid, CMD.FIGHT, tx + random(-250, 250), tz + random(-250, 250))
			end
		end
		if sqrt((tx - st.x) ^ 2 + (tz - st.z) ^ 2) < 400 then
			army.targetFrame = 0
		end
		return true
	end
	-- march: the anchor walks toward the target at the pace of the slowest unit, never far ahead of the main body
	releaseStuck(army, f)
	local dx, dz, dist = norm(tx - army.anchorX, tz - army.anchorZ)
	local body = st.body
	local lag = body and sqrt((army.anchorX - body.x) ^ 2 + (army.anchorZ - body.z) ^ 2) or 9999
	local step = st.slow * 1.0 * 0.9 -- one second at 90% of the slowest speed
	if not body or body.share < 0.5 then
		-- the army is not around its anchor (just launched, or strung out): the anchor comes back to it
		army.anchorX, army.anchorZ = st.x, st.z
		step = 0
	elseif lag > 350 then
		step = 0 -- wait for the main body to catch up
	end
	army.lag = lag
	if t == "siege" and army.targetKind == "base" and dist < max(600, st.range * 0.85) then
		step = 0 -- in range: bombard
	end
	if dist < 250 and army.targetKind ~= "hold" then
		army.targetFrame = 0 -- arrived: next target
		if army.targetKind == "enemy start" or army.targetKind == "sweep" then
			army.swept, army.sweeping = true, false
		end
	end
	army.anchorX, army.anchorZ = clampMap(army.anchorX + dx * min(step, dist), army.anchorZ + dz * min(step, dist))
	formation(army, army.anchorX, army.anchorZ, dx, dz, t == "siege" and army.targetKind == "base" and step == 0, f)
	return true
end

---------------------------------------------------------------------------- lifecycle

-- modoption ai_doctrine_teams = "0,2": only these teams plan (A/B tests against the stock AI in one game)
local onlyTeams
if modOptions.ai_doctrine_teams and modOptions.ai_doctrine_teams ~= "" then
	onlyTeams = {}
	for n in tostring(modOptions.ai_doctrine_teams):gmatch("%d+") do
		onlyTeams[tonumber(n)] = true
	end
end

local function isAITeam(teamID)
	local _, _, _, isAI = Spring.GetTeamInfo(teamID, false)
	local luaAI = Spring.GetTeamLuaAI(teamID)
	return isAI and (luaAI == nil or luaAI == "") and (not onlyTeams or onlyTeams[teamID])
end

-- v22: directives of an external commander (cmd_ai_commander.lua op "doctrine") for one AI team:
--   status            the team's armies
--   focus {pos=[x,z]} every army but defence goes for that point (clear: back to its own targets)
--   gather            armies in the field fall back to the rally point, forming ones wait: one big force
--   go                every army gathered or forming (3+ units) launches now; ends gather
--   allin / normal    armies retreat only when nearly wiped out / the usual thresholds
local function directive(teamID, cmd, req)
	local t = teams[teamID]
	if not t then
		return false, "team " .. tostring(teamID) .. " has no doctrine"
	end
	t.dir = t.dir or {}
	local d, f = t.dir, frameNow()
	if cmd == "focus" then
		local p = req.pos
		if type(p) ~= "table" or not tonumber(p[1]) or not tonumber(p[2]) then
			return false, "focus needs pos [x, z]"
		end
		d.focus = { clampMap(tonumber(p[1]), tonumber(p[2])) }
		for _, a in ipairs(t.armies) do
			a.targetFrame = 0 -- retarget now
		end
	elseif cmd == "clear" then
		d.focus = nil
	elseif cmd == "gather" then
		d.gather, d.go = true, nil
		d.gatherFrame = d.gatherFrame or f
	elseif cmd == "go" then
		d.gather, d.go, d.gatherFrame = nil, f, nil
	elseif cmd == "allin" then
		d.allin = true
	elseif cmd == "normal" then
		d.allin, d.gather, d.gatherFrame = nil, nil, nil
	elseif cmd == "prefer" then
		-- weights for the plan choice: tactics {raid=2, assault=1, ...}, tier "auto" or 1..4
		local tac = type(req.tactics) == "table" and req.tactics or {}
		d.prefer = d.prefer or {}
		for k, v in pairs(tac) do
			if tonumber(v) then
				-- defend is capped: a general that weighs it high keeps every army at home
				d.prefer[k] = max(0, min(k == "defend" and 2 or 10, tonumber(v)))
			end
		end
		if tonumber(req.tier) then
			d.tier = max(1, min(4, floor(tonumber(req.tier))))
		elseif req.tier == "auto" then
			d.tier = nil
		end
	elseif cmd ~= "status" then
		-- the general's executors (expansion, economy, air wing, raids, commander guard, reports): ai_general_ops.lua
		if GG.AIGeneralOps then
			return GG.AIGeneralOps.handle(teamID, cmd, req)
		end
		return false, "unknown doctrine command " .. cmd
	end
	if (cmd == "focus" or cmd == "gather" or cmd == "go" or cmd == "allin" or cmd == "normal" or cmd == "clear")
		and req.byStaff == nil and GG.AIGeneralOps and GG.AIGeneralOps.noteManual then
		GG.AIGeneralOps.noteManual(teamID, "army") -- a general's own army order pauses the staff's push
	end
	if cmd ~= "status" then
		log("t=%d team=%d commander directive %s%s", floor(f / 1800), teamID, cmd,
			d.focus and string.format(" (focus %d,%d)", d.focus[1], d.focus[2]) or "")
	end
	local out = {}
	for _, a in ipairs(t.armies) do
		local st = a.last
		out[#out + 1] = { id = a.id, comp = a.comp.id, tactic = a.tactic, state = a.state, units = st and st.n or a.n,
			metal = st and floor(st.cost) or 0, x = st and floor(st.x) or nil, z = st and floor(st.z) or nil,
			target = a.targetKind, tx = a.target and floor(a.target[1]) or nil, tz = a.target and floor(a.target[2]) or nil,
			plan = floor(a.planMetal or 0), kills = floor(a.kills), losses = floor(a.losses) }
	end
	return true, nil, { armies = out, focus = d.focus, gather = d.gather or false, allin = d.allin or false,
		prefer = d.prefer, tier = d.tier, executors = GG.AIGeneralOps and GG.AIGeneralOps.status(teamID) or nil,
		rally = (t.armies[1] and { floor(t.armies[1].rallyX), floor(t.armies[1].rallyZ) }) or nil }
end

function gadget:Initialize()
	for _, teamID in ipairs(Spring.GetTeamList()) do
		if isAITeam(teamID) then
			local _, _, _, _, _, ally = Spring.GetTeamInfo(teamID, false)
			teams[teamID] = { team = teamID, ally = ally, armies = {}, factories = {}, used = {} }
		end
	end
	local n = 0
	for side, c in pairs(comps) do
		for tier = 1, 4 do
			n = n + #(c["t" .. tier] or {})
		end
	end
	log("loaded %d compositions for %d AI teams", n, (function() local k = 0 for _ in pairs(teams) do k = k + 1 end return k end)())
	for _, uid in ipairs(Spring.GetAllUnits()) do
		gadget:UnitFinished(uid, spGetUnitDefID(uid), spGetUnitTeam(uid))
	end
	GG.AIDoctrine = {
		owns = owns,
		teams = teams,
		directive = directive,
		-- the army a hero marches with: its own hero-led composition, else the strongest launched army
		heroArmy = function(teamID, heroID, heroName)
			local t = teams[teamID]
			if not t then
				return nil
			end
			local best, bestCost
			for _, a in ipairs(t.armies) do
				local st = a.last
				if st and (a.state == "march" or a.state == "engage") then
					if a.hero == heroName then
						best, bestCost = a, 1e18
					elseif st.cost > (bestCost or 0) then
						best, bestCost = a, st.cost
					end
				end
			end
			if not best then
				return nil
			end
			best.heroes = best.heroes or {}
			if not best.heroes[heroID] then
				best.heroes[heroID] = true
				log("t=%d team=%d army#%d %s is joined by hero %s%s", floor(Spring.GetGameFrame() / 1800), teamID, best.id, best.comp.id, heroName,
					best.hero == heroName and " (its own)" or "")
			end
			local tx, tz = best.target and best.target[1], best.target and best.target[2]
			return { x = best.last.x, z = best.last.z, cost = best.last.cost, ex = tx, ez = tz }
		end,
	}
end

function gadget:Shutdown()
	GG.AIDoctrine = nil
end

function gadget:UnitCreated(unitID, unitDefID, teamID, builderID)
	local t = teams[teamID]
	if not t or not builderID then
		return
	end
	local fs = facState[builderID]
	if not fs then
		return
	end
	-- a planned unit started: reserve it for the army that needs it; every PLAN_SHARE planned units the
	-- factory makes one stock pick (skip until a non-planned unit comes out)
	local nd = teamNeeds(t)[unitDefID]
	local wanted = nd ~= nil
	if wanted then
		pending[unitID] = nd.army -- the stock pick may be a planned unit too: it counts
	end
	if fs.skip then
		fs.skip = false -- the one stock slot is used, whatever it built
		return
	end
	if wanted then
		fs.planned = fs.planned + 1
		-- v22: late game the plan takes up to 3 slots of 4 (the stock AI has its levy-free home guard and builders)
		if fs.planned >= PLAN_SHARE + floor(2 * lateOf(teamID) + 0.5) then
			fs.skip = true
			fs.planned = 0
			fs.next = ""
			spSetUnitRulesParam(builderID, "doctrine_next", "", ALLIED)
		end
	end
end

function gadget:UnitFinished(unitID, unitDefID, teamID)
	local t = teams[teamID]
	if not t then
		return
	end
	local ud = UnitDefs[unitDefID]
	if isFactory[unitDefID] then
		t.factories[unitID] = isFactory[unitDefID]
		return
	end
	local army = pending[unitID]
	pending[unitID] = nil
	if army and army.state ~= "dead" then
		addUnit(army, unitID)
		toAI(teamID, "detach " .. unitID)
		order(unitID, CMD.MOVE, army.rallyX + random(-250, 250), army.rallyZ + random(-250, 250))
	end
end

function gadget:UnitDestroyed(unitID, unitDefID, teamID, attackerID)
	pending[unitID] = nil
	facState[unitID] = nil
	local t = teams[teamID]
	if t then
		t.factories[unitID] = nil
	end
	local army = owns[unitID]
	if army then
		army.losses = army.losses + (unitCost[unitDefID] or 0)
		removeUnit(army, unitID)
	end
	local killer = attackerID and owns[attackerID]
	if killer and spGetUnitAllyTeam(attackerID) ~= select(6, Spring.GetTeamInfo(teamID, false)) then
		killer.kills = killer.kills + (unitCost[unitDefID] or 0)
	end
end

function gadget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
	local army = owns[unitID]
	if army and newTeam ~= army.team then
		removeUnit(army, unitID)
	end
end

local function summary(f)
	-- every team's worth (A/B tests: the stock teams too)
	for _, teamID in ipairs(Spring.GetTeamList()) do
		if teamID ~= Spring.GetGaiaTeamID() then
			local v = 0
			for _, uid in ipairs(Spring.GetTeamUnits(teamID)) do
				v = v + (unitCost[spGetUnitDefID(uid)] or 0)
			end
			local _, _, isDead, _, _, ally = Spring.GetTeamInfo(teamID, false)
			log("t=%d worth team=%d ally=%d doctrine=%d dead=%d value=%d", floor(f / 1800), teamID, ally, teams[teamID] and 1 or 0, isDead and 1 or 0, v)
		end
	end
	for teamID, t in pairs(teams) do
		local parts = {}
		for _, a in ipairs(t.armies) do
			local st = a.last
			local toT = (st and a.target) and sqrt((a.target[1] - st.x) ^ 2 + (a.target[2] - st.z) ^ 2) or 0
			parts[#parts + 1] = string.format("#%d %s T%d %s %s %du %dm kills=%d losses=%d eng=%d spread=%d target=%s:%d lag=%d stuck=%d", a.id, a.comp.id, a.tier, a.tactic, a.state,
				st and st.n or 0, st and st.cost or 0, a.kills, a.losses, a.engagements, a.spreadN > 0 and a.spreadSum / a.spreadN or 0,
				a.targetKind or "-", toT, a.lag or 0, a.stuck or 0)
		end
		local _, _, _, income = spGetTeamResources(teamID, "metal")
		local value, armyValue = 0, 0
		for _, uid in ipairs(Spring.GetTeamUnits(teamID)) do
			local udid = spGetUnitDefID(uid)
			value = value + (unitCost[udid] or 0)
			if owns[uid] then
				armyValue = armyValue + (unitCost[udid] or 0)
			end
		end
		log("t=%d team=%d summary income=%d armies=%d value=%d planned=%d | %s", floor(f / 1800), teamID, income or 0, #t.armies, value, armyValue, table.concat(parts, "; "))
	end
end

---------------------------------------------------------------------------- hero altar assist
-- v19: the hero altar (T4 foundry) has a 496k build time; BARb leaves it to the one T2 constructor that started it
-- (40+ minutes). While a team's altar is a nanoframe, its nearest mobile constructors are taken from the AI
-- ("detach") and help build it, then handed back ("attach").
local ALTAR_HELPERS_MIN = 4
local ALTAR_HELPERS_MAX = 14
local ALTAR_HELPER_PER_INCOME = 120   -- one more helper per this much metal income
local ALTAR_HELPER_RADIUS = 3500
local altarDefs, mobileBuilder = {}, {}
for udid, ud in pairs(UnitDefs) do
	if ud.name:find("t4gant", 1, true) then
		altarDefs[#altarDefs + 1] = udid
	end
	if ud.isBuilder and ud.canMove and not ud.isFactory and (ud.buildSpeed or 0) > 0
		and not (ud.customParams and ud.customParams.iscommander) then
		mobileBuilder[udid] = true
	end
end
local altarHelp = {} -- teamID -> { altar = uid, units = { uid = true }, n }

local function altarRelease(teamID, why)
	local a = altarHelp[teamID]
	if not a then
		return
	end
	local ids = {}
	for uid in pairs(a.units) do
		if spValidUnitID(uid) and not spGetUnitIsDead(uid) and spGetUnitTeam(uid) == teamID then
			spGiveOrderToUnit(uid, CMD.STOP, {}, 0)
			ids[#ids + 1] = uid
		end
	end
	if #ids > 0 then
		toAI(teamID, "attach " .. table.concat(ids, ","))
	end
	log("t=%d team=%d altar helpers released: %d (%s)", floor(frameNow() / 1800), teamID, #ids, why)
	altarHelp[teamID] = nil
end

local function altarAssist(teamID, f)
	local frame
	for _, uid in ipairs(Spring.GetTeamUnitsByDefs(teamID, altarDefs) or {}) do
		local _, _, _, _, bp = spGetUnitHealth(uid)
		if bp and bp < 1 then
			frame = uid
		end
	end
	local a = altarHelp[teamID]
	if not frame then
		if a then
			altarRelease(teamID, "altar done or gone")
		end
		return
	end
	if a and a.altar ~= frame then
		altarRelease(teamID, "new frame")
		a = nil
	end
	if not a then
		a = { altar = frame, units = {}, n = 0 }
		altarHelp[teamID] = a
	end
	local n = 0
	for uid in pairs(a.units) do
		if spValidUnitID(uid) and not spGetUnitIsDead(uid) and spGetUnitTeam(uid) == teamID then
			n = n + 1
			if spGetUnitCommands(uid) == 0 then
				spGiveOrderToUnit(uid, CMD.REPAIR, { frame }, 0)
			end
		else
			a.units[uid] = nil
		end
	end
	a.n = n
	local _, _, _, income = spGetTeamResources(teamID, "metal")
	local want = min(ALTAR_HELPERS_MAX, ALTAR_HELPERS_MIN + floor((income or 0) / ALTAR_HELPER_PER_INCOME))
	if n >= want then
		return
	end
	local ax, _, az = spGetUnitPosition(frame)
	if not ax then
		return
	end
	local taken = GG.AICommanderUnits or {}
	local cands = {}
	for _, uid in ipairs(spGetUnitsInCylinder(ax, az, ALTAR_HELPER_RADIUS, teamID)) do
		if mobileBuilder[spGetUnitDefID(uid)] and not a.units[uid] and not owns[uid] and not taken[uid] then
			local _, _, _, _, bp = spGetUnitHealth(uid)
			local ux, _, uz = spGetUnitPosition(uid)
			if bp and bp >= 1 and ux then
				cands[#cands + 1] = { uid = uid, d = (ux - ax) ^ 2 + (uz - az) ^ 2 }
			end
		end
	end
	table.sort(cands, function(p, q) return p.d < q.d end)
	local ids = {}
	for i = 1, min(#cands, want - n) do
		local uid = cands[i].uid
		a.units[uid] = true
		ids[#ids + 1] = uid
	end
	if #ids > 0 then
		toAI(teamID, "detach " .. table.concat(ids, ","))
		for _, uid in ipairs(ids) do
			spGiveOrderToUnit(uid, CMD.REPAIR, { frame }, 0)
		end
		local _, _, _, _, bp = spGetUnitHealth(frame)
		log("t=%d team=%d altar %.0f%% built: +%d helpers -> %d (want %d)", floor(f / 1800), teamID, (bp or 0) * 100, #ids, n + #ids, want)
	end
end

---------------------------------------------------------------------------- v22 levy: the stock army goes to war
-- BARb keeps most of its army at home (its attack groups launch at a capped power, the rest guards); late game
-- that was millions of metal standing still. Every 20 s the armed mobile units the AI owns around its start and
-- factories are counted; past LEVY_MIN metal all but LEVY_KEEP of them (every 4th unit by cost stays) become a
-- doctrine army that gathers at the rally point and attacks like a planned one.
local levyDef = {}
for udid, ud in pairs(UnitDefs) do
	local armed = (unitRange[udid] or 0) > 0 or unitRole[udid] == "aa"
	if armed and not isStructure[udid] and not ud.canFly and not ud.isBuilder and not ud.customParams.iscommander
		and not ud.name:find("t4", 1, true) and (ud.speed or 0) > 0 then
		levyDef[udid] = true
	end
end
local MAX_LEVIES = 2

local function levy(teamID, t, f)
	-- not while the base is attacked (that army is the home guard) and not before the economy is past the opening
	if not t.side or t.threatened or t.homeThreat or lateOf(teamID) <= 0 then
		return
	end
	local nLevy = 0
	for _, a in ipairs(t.armies) do
		if a.levy then
			nLevy = nLevy + 1
		end
	end
	if nLevy >= MAX_LEVIES then
		return
	end
	local spots = { { startPos(teamID) } }
	for uid in pairs(t.factories) do
		local x, _, z = spGetUnitPosition(uid)
		if x then
			spots[#spots + 1] = { x, z }
		end
	end
	local heroes = GG.T4Heroes and GG.T4Heroes.heroes or {}
	local taken = GG.AICommanderUnits or {}
	local helpers = altarHelp[teamID] and altarHelp[teamID].units or {}
	local cands, total = {}, 0
	for _, uid in ipairs(Spring.GetTeamUnits(teamID)) do
		local udid = spGetUnitDefID(uid)
		if udid and levyDef[udid] and not owns[uid] and not pending[uid] and not heroes[uid] and not taken[uid] and not helpers[uid] then
			local x, _, z = spGetUnitPosition(uid)
			local _, _, _, _, bp = spGetUnitHealth(uid)
			if x and bp and bp >= 1 then
				for _, p in ipairs(spots) do
					if (x - p[1]) ^ 2 + (z - p[2]) ^ 2 < LEVY_RADIUS * LEVY_RADIUS then
						cands[#cands + 1] = { uid = uid, c = unitCost[udid] or 0 }
						total = total + (unitCost[udid] or 0)
						break
					end
				end
			end
		end
	end
	if total < LEVY_MIN / (1 - LEVY_KEEP) then
		return
	end
	table.sort(cands, function(p, q) return p.c > q.c or (p.c == q.c and p.uid < q.uid) end)
	local army = {
		id = 0, team = teamID, ally = t.ally, comp = { id = "levy", name = "Levy" }, tier = 0, tactic = "assault", levy = true,
		want = {}, planMetal = 0, planCount = 0, roleOver = {}, units = {}, n = 0, made = {}, state = "forming", since = f,
		launchStrength = 0, kills = 0, losses = 0, engagements = 0, launches = 0, spreadSum = 0, spreadN = 0,
	}
	local ids, metal = {}, 0
	for i, c in ipairs(cands) do
		if i % 4 ~= 0 then -- every 4th stays home
			local udid = spGetUnitDefID(c.uid)
			addUnit(army, c.uid)
			army.want[udid] = (army.want[udid] or 0) + 1
			ids[#ids + 1] = c.uid
			metal = metal + c.c
		end
	end
	if #ids < 4 then
		for _, uid in ipairs(ids) do
			removeUnit(army, uid)
		end
		return
	end
	armyId = armyId + 1
	army.id = armyId
	army.planMetal, army.planCount = metal, #ids
	local sx, sz = startPos(teamID)
	local ex, ez = enemyHome(teamID)
	local dx, dz, d = norm(ex - sx, ez - sz)
	army.rallyX, army.rallyZ = clampMap(sx + dx * min(1600, d * 0.22), sz + dz * min(1600, d * 0.22))
	t.armies[#t.armies + 1] = army
	toAI(teamID, "detach " .. table.concat(ids, ","))
	for _, uid in ipairs(ids) do
		order(uid, CMD.MOVE, army.rallyX + random(-300, 300), army.rallyZ + random(-300, 300))
	end
	log("t=%d team=%d army#%d levy: %d idle stock units, %d metal (of %d at home)", floor(f / 1800), teamID, army.id, #ids, metal, total)
end

function gadget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID)
	local army = owns[unitID]
	if not army or not attackerID or damage <= 0 then
		return
	end
	local x, _, z = spGetUnitPosition(attackerID)
	if x and spGetUnitAllyTeam(attackerID) ~= army.ally then
		local h = army.hit
		if h then
			h[1], h[2], h[3] = x, z, Spring.GetGameFrame()
		else
			army.hit = { x, z, Spring.GetGameFrame() }
		end
	end
end

function gadget:GameFrame(f)
	if f % 30 ~= 17 then
		return
	end
	for teamID, t in pairs(teams) do
		if not t.side then
			t.side = sideOf(teamID)
		end
		if t.side and f >= START_FRAME then
			-- v23: late game without T1/T2 land armies (NO_LOW_INCOME), with a hysteresis
			if NO_LOW_INCOME > 0 then
				-- the income averaged over ~30 s: recycled factories (ai_techup) and reclaim spike it for a second
				local _, income = lateOf(teamID)
				t.incAvg = (t.incAvg or income) + (income - (t.incAvg or income)) / 30
				income = t.incAvg
				local _, maxTier = teamFactories(t)
				local noLow = maxTier >= 3 and income >= NO_LOW_INCOME * (t.noLow and NO_LOW_OFF or 1)
				if noLow ~= (t.noLow or false) then
					t.noLow = noLow or nil
					Spring.SetTeamRulesParam(teamID, "ai_no_t2", noLow and 1 or 0)
					log("t=%d team=%d late game: T1/T2 land armies %s (income %d m/s)", floor(f / 1800), teamID, noLow and "off" or "back on", income)
				end
			end
			-- threatened: enemies at home (the start and every factory), every 5 s
			if f % 150 == 17 then
				local hx, hz = startPos(teamID)
				local best = { enemyStrength(hx, hz, 3200, t.ally) }
				for uid in pairs(t.factories) do
					local fx, _, fz = spGetUnitPosition(uid)
					if fx then
						local e = { enemyStrength(fx, fz, 1600, t.ally) }
						if e[1] > best[1] then
							best = e
						end
					end
				end
				t.threatened = best[1] > 3000
				t.homeThreat = best[1] > 1500 and { s = best[1], x = best[2], z = best[3] } or nil
			end
			-- drop dead armies, start a new plan when nothing is forming
			local keep, forming = {}, false
			for _, a in ipairs(t.armies) do
				if a.state ~= "dead" and (a.n > 0 or (a.state == "forming" and not a.levy)) then
					keep[#keep + 1] = a
					if a.state == "forming" and not a.levy then
						forming = true
					end
				elseif a.state ~= "dead" then
					a.state = "dead"
					log("t=%d team=%d army#%d %s destroyed: launched %d times, %d engagements, kills %d metal, losses %d, march spread %d", floor(f / 1800),
						teamID, a.id, a.comp.id, a.launches, a.engagements, a.kills, a.losses, a.spreadN > 0 and a.spreadSum / a.spreadN or 0)
				end
			end
			t.armies = keep
			local late = lateOf(teamID)
			if not forming and #t.armies < MAX_ARMIES + floor(LATE_ARMIES * late + 0.5) then
				newArmy(teamID, t, f)
			end
			if f >= LEVY_FROM and f % 600 == 317 then
				levy(teamID, t, f)
			end
			if f % 150 == 47 then
				altarAssist(teamID, f)
			end
			-- a general's gather is a muster, not a posture: after 4 min the gathered force goes by itself
			local dir = t.dir
			if dir and dir.gather and dir.gatherFrame and f - dir.gatherFrame > 4 * 60 * GAME_SPEED then
				dir.gather, dir.go, dir.gatherFrame = nil, f, nil
				log("t=%d team=%d commander gather expired after 4 min: the gathered armies go", floor(f / 1800), teamID)
			end
			updateProduction(teamID, t)
			for _, a in ipairs(t.armies) do
				driveArmy(a, f)
			end
		end
	end
	if f % 3600 == 17 then
		summary(f)
	end
end
