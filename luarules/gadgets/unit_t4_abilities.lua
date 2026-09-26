local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "T4 Abilities",
		desc = "Passive abilities of the custom T4 units: repair aura (t4_heal_radius / t4_heal_rate), veterancy by damage dealt (t4_xp_damage / t4_xp_range)",
		author = "denysfast",
		date = "2026-09-27",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

-- veterancy: a T4 grows its damage and range with combat experience, on every weapon. The engine
-- experience barely moves for a T4 (it scales with target cost / own cost), so a titan counts its own:
-- the metal value of the damage it dealt to enemies. level = dealt / (dealt + own cost) - half of the
-- max bonus once it has dealt its own price, approaching the max after several times that.
local vet = {} -- unitDefID -> { damage = max bonus, range = max bonus, cost, weapons = { [n] = base range } }
for udid, ud in pairs(UnitDefs) do
	local cp = ud.customParams
	local dmg, rng = tonumber(cp and cp.t4_xp_damage), tonumber(cp and cp.t4_xp_range)
	if dmg or rng then
		local weapons = {}
		for n, w in ipairs(ud.weapons) do
			local wd = WeaponDefs[w.weaponDef]
			if wd and wd.range > 0 and wd.type ~= "Shield" then
				weapons[n] = wd.range
			end
		end
		vet[udid] = { damage = dmg or 0, range = rng or 0, cost = math.max(1, ud.metalCost), weapons = weapons }
	end
end
local dealt = {}      -- unitID -> metal value of damage dealt
local level = {}      -- unitID -> applied level 0..1
local damageMult = {} -- unitID -> current damage multiplier
local unitCost = {}   -- unitDefID -> metal cost
for udid, ud in pairs(UnitDefs) do
	unitCost[udid] = ud.metalCost
end

local spSetUnitWeaponState = Spring.SetUnitWeaponState
local spSetUnitMaxRange = Spring.SetUnitMaxRange
local spSetUnitRulesParam = Spring.SetUnitRulesParam
local spAreTeamsAllied = Spring.AreTeamsAllied

local function applyLevel(unitID, v, lvl)
	level[unitID] = lvl
	damageMult[unitID] = 1 + v.damage * lvl
	local rangeMult = 1 + v.range * lvl
	local maxRange = 0
	for n, base in pairs(v.weapons) do
		local r = base * rangeMult
		spSetUnitWeaponState(unitID, n, "range", r)
		if r > maxRange then
			maxRange = r
		end
	end
	if maxRange > 0 then
		spSetUnitMaxRange(unitID, maxRange)
	end
	spSetUnitRulesParam(unitID, "t4_veterancy", lvl, { inlos = true })
end

function gadget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
	if paralyzer or not attackerID or damage <= 0 then
		return
	end
	local v = attackerDefID and vet[attackerDefID]
	if not v or (attackerTeam and spAreTeamsAllied(attackerTeam, unitTeam)) then
		return
	end
	local _, maxHp = Spring.GetUnitHealth(unitID)
	if not maxHp or maxHp <= 0 then
		return
	end
	local value = math.min(damage, maxHp) / maxHp * (unitCost[unitDefID] or 0)
	local total = (dealt[attackerID] or 0) + value
	dealt[attackerID] = total
	local lvl = total / (total + v.cost)
	if lvl - (level[attackerID] or 0) >= 0.02 then -- weapon state updates in steps, not on every hit
		applyLevel(attackerID, v, lvl)
	end
end

function gadget:UnitPreDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID)
	local m = attackerID and damageMult[attackerID]
	if m then
		return damage * m, 1
	end
	return damage, 1
end

-- repair aura: every second, allied units (and structures) within t4_heal_radius of a finished
-- aura unit regain t4_heal_rate HP, capped at their max health. Auras do not stack on a unit
-- beyond the strongest one, so a pack of T4s is not an immortality field.
local aura = {}
for udid, ud in pairs(UnitDefs) do
	local cp = ud.customParams
	local r, rate = tonumber(cp and cp.t4_heal_radius), tonumber(cp and cp.t4_heal_rate)
	if r and rate then
		aura[udid] = { radius = r, rate = rate }
	end
end

local active = {} -- unitID -> aura
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitsInCylinder = Spring.GetUnitsInCylinder
local spGetUnitAllyTeam = Spring.GetUnitAllyTeam
local spGetUnitHealth = Spring.GetUnitHealth
local spSetUnitHealth = Spring.SetUnitHealth

function gadget:UnitFinished(unitID, unitDefID)
	if aura[unitDefID] then
		active[unitID] = aura[unitDefID]
	end
end

function gadget:UnitDestroyed(unitID)
	active[unitID] = nil
	damageMult[unitID] = nil
	dealt[unitID] = nil
	level[unitID] = nil
end

function gadget:UnitGiven(unitID, unitDefID)
	if aura[unitDefID] then
		active[unitID] = aura[unitDefID]
	end
end

function gadget:GameFrame(frame)
	if next(aura) == nil or frame % 30 ~= 11 or next(active) == nil then
		return
	end
	local best = {} -- target unitID -> heal this second
	for unitID, a in pairs(active) do
		local x, _, z = spGetUnitPosition(unitID)
		if x then
			local ally = spGetUnitAllyTeam(unitID)
			for _, uid in ipairs(spGetUnitsInCylinder(x, z, a.radius)) do
				if uid ~= unitID and spGetUnitAllyTeam(uid) == ally and (best[uid] or 0) < a.rate then
					best[uid] = a.rate
				end
			end
		end
	end
	for uid, rate in pairs(best) do
		local hp, maxHp, _, _, buildProgress = spGetUnitHealth(uid)
		if hp and buildProgress and buildProgress >= 1 and hp < maxHp then
			spSetUnitHealth(uid, math.min(maxHp, hp + rate))
		end
	end
end
