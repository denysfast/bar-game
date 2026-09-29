local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "T4 Heroes",
		desc = "Custom T4 heroes: one per team, levels 1-30 from combat, talents, abilities, revive at the foundry (-5 levels), AI care",
		author = "denysfast",
		date = "2026-09-27",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = true,
	}
end

-- Design data: luarules/configs/t4_heroes.lua. UI: luaui/Widgets/gui_t4_heroes.lua. CUSTOM.md, "T4 heroes".
--
-- Protocol (LuaRules messages from the owner's UI):
--   t4hero:learn:<unitID>:<branch>      spend a talent point (arsenal|plating|servos|a1|a2|ult)
-- Unit rules params: hero_level (in LOS), hero_xp (0..1 to the next level), hero_points,
--   hero_rank_<branch>, hero_ready_<branch> (frame the ability is ready), hero_on_<branch> (frame an
--   active effect ends; in LOS), hero_retreat (AI care), hero_absorb (active_shield left), hero_cloaked,
--   hero_summon_expire (on a summoned unit). Game rules param hero_ability_log = 1: "[ability]" infolog lines.
--   Team rules params (allies):
--   hero_dead_<name> (the level a revive brings back), hero_revive_<name> (revive metal cost).

local H = VFS.Include("luarules/configs/t4_heroes.lua")

local CMD_HERO_AUTOCAST = 36100

if gadgetHandler:IsSyncedCode() then
	----------------------------------------------------------------------------- synced

	local spGetUnitPosition = Spring.GetUnitPosition
	local spGetUnitsInCylinder = Spring.GetUnitsInCylinder
	local spGetUnitAllyTeam = Spring.GetUnitAllyTeam
	local spGetUnitTeam = Spring.GetUnitTeam
	local spGetUnitHealth = Spring.GetUnitHealth
	local spSetUnitHealth = Spring.SetUnitHealth
	local spGetUnitDefID = Spring.GetUnitDefID
	local spAddUnitDamage = Spring.AddUnitDamage
	local spSpawnCEG = Spring.SpawnCEG
	local spSetUnitRulesParam = Spring.SetUnitRulesParam
	local spSetTeamRulesParam = Spring.SetTeamRulesParam
	local spSetUnitWeaponState = Spring.SetUnitWeaponState
	local spGetGameFrame = Spring.GetGameFrame
	local spValidUnitID = Spring.ValidUnitID
	local spGetUnitIsDead = Spring.GetUnitIsDead
	local spSpawnProjectile = Spring.SpawnProjectile
	local spGetGroundHeight = Spring.GetGroundHeight
	local spGetUnitLosState = Spring.GetUnitLosState
	local spAreTeamsAllied = Spring.AreTeamsAllied
	local random = math.random
	local max, min, floor, sqrt = math.max, math.min, math.floor, math.sqrt

	local ALLIED = { allied = true }
	local INLOS = { inlos = true }
	local GAME_SPEED = Game.gameSpeed
	local gravityPerFrame = -Game.gravity / (GAME_SPEED * GAME_SPEED)

	local modOptions = Spring.GetModOptions()
	local xpMult = tonumber(modOptions.hero_xp_mult) or 1
	if xpMult <= 0 then
		xpMult = 1
	end

	---------------------------------------------------------------- static data per hero unitdef

	local heroDefs = {}   -- unitDefID -> def
	local swapWatch = {}  -- weaponDefID -> true (ProjectileCreated)
	local heroWeapon = {} -- weaponDefID -> true: the hero_* weapondefs the gadget spawns
	for wdid, wd in pairs(WeaponDefs) do
		if wd.customParams and wd.customParams.t4_hero_weapon then
			heroWeapon[wdid] = true
		end
	end
	local tierBase = {}   -- weaponDefID of a tier copy -> weaponDefID of the weapon it copies (set per hero def)
	local explWatch = {}  -- weaponDefID -> true (Explosion)
	local foundryDefs = {} -- unitDefID -> true (the T4 foundries: fountain + AI retreat point)
	local factoryDefs = {}
	local unitCost = {}
	local structureDefs = {}

	for udid, ud in pairs(UnitDefs) do
		unitCost[udid] = ud.metalCost
		if ud.isImmobile or (ud.speed or 0) == 0 then
			structureDefs[udid] = true
		end
		if ud.name == "armt4gant" or ud.name == "cort4gant" or ud.name == "legt4gant" then
			foundryDefs[udid] = true
		elseif ud.isFactory then
			factoryDefs[udid] = true
		end
		local cfg = H.heroes[ud.name]
		if cfg and ud.customParams.t4_hero then
			local def = {
				name = ud.name, cfg = cfg, udid = udid,
				cost = ud.metalCost, energy = ud.energyCost, buildTime = ud.buildTime,
				health = ud.health, speed = ud.speed, sight = ud.losRadius or ud.sightDistance or 0,
				airSight = ud.airLosRadius or 0, radar = ud.radarDistance or ud.radarRadius or 0,
				weapons = {}, keyNum = {}, extra = {}, cmds = {},
			}
			local prefix = ud.name .. "_"
			for n, w in ipairs(ud.weapons) do
				local wd = WeaponDefs[w.weaponDef]
				local key = wd.name:sub(#prefix + 1)
				if wd.type == "Shield" then
					def.shieldNum = n
					def.shieldPower = wd.shieldPower
					def.shieldRegen = wd.shieldPowerRegen
				elseif wd.range > 0 then
					def.weapons[n] = {
						key = key, wdid = w.weaponDef, range = wd.range, reload = wd.reload, type = wd.type,
						accuracy = wd.accuracy, spray = wd.sprayAngle, burst = wd.salvoSize, projectiles = wd.projectiles,
						aoe = wd.damageAreaOfEffect or 0, damage = wd.damages and wd.damages[0] or 0,
					}
					def.keyNum[key] = def.keyNum[key] or {}
					def.keyNum[key][#def.keyNum[key] + 1] = n
				end
			end
			for wdid, wd in pairs(WeaponDefs) do
				if wd.name:sub(1, #prefix) == prefix and wd.customParams and wd.customParams.t4_hero_weapon then
					def.extra[wd.name:sub(#prefix + 1)] = wdid
				end
			end
			-- weapon trees (v14): tree index per weapon number, tier copies per weapon number
			def.trees = {}
			def.treeOf = {}
			def.tierWdid = {}
			for wi, wcfg in ipairs(cfg.weapons or {}) do
				local tree = { index = wi, kind = wcfg.kind, name = wcfg.name, nums = {} }
				for _, key in ipairs(wcfg.keys) do
					for _, n in ipairs(def.keyNum[key] or {}) do
						tree.nums[#tree.nums + 1] = n
						def.treeOf[n] = wi
						def.tierWdid[n] = {}
						for tier = 2, 4 do
							def.tierWdid[n][tier] = def.extra[key .. "_t" .. tier]
						end
					end
				end
				def.trees[wi] = tree
			end
			def.keys = H.allKeys(ud.name)
			for _, key in ipairs({ "a1", "a2", "ult" }) do
				local b = cfg[key]
				if b and b.cmd then
					def.cmds[b.cmd] = key
				end
			end
			heroDefs[udid] = def
		end
	end

	-- weapon key -> weaponDefIDs of the hero's own weapons
	local function keyWdids(def, key)
		local out = {}
		for _, n in ipairs(def.keyNum[key] or {}) do
			out[#out + 1] = def.weapons[n].wdid
		end
		return out
	end

	for _, def in pairs(heroDefs) do
		-- the ability kit's projectiles (hero_* extras, not the tier copies): their explosions apply the damage
		for _, wdid in pairs(def.extra) do
			if not WeaponDefs[wdid].customParams.t4_tier then
				explWatch[wdid] = true
			end
		end
		-- visual tiers: every weapon of a tree is watched, its copies map back to it
		for n, copies in pairs(def.tierWdid) do
			local base = def.weapons[n].wdid
			for _, wdid in pairs(copies) do
				tierBase[wdid] = base
				if explWatch[base] then
					explWatch[wdid] = true
				end
			end
			if next(copies) then
				swapWatch[base] = true
			end
		end
	end

	---------------------------------------------------------------- state

	local dropItem, randomItem -- items on the ground, defined below
	local heroes = {}      -- unitID -> hero state
	local dead = {}        -- teamID -> name -> { level, picks }
	local pendingRevive = {} -- unitID (nanoframe) -> record
	local isAITeam = {}
	local guardMult = {}   -- unitID -> damage taken multiplier (Guardian Protocol)
	local invuln = {}      -- unitID -> true (Aegis Dome)
	local auraDamage = {}  -- unitID -> extra damage (Command Aura)
	local events = {}      -- timed ability effects, processed every 6 frames
	local delayed = {}     -- { frame, fn }

	for _, teamID in ipairs(Spring.GetTeamList()) do
		local _, _, _, isAI = Spring.GetTeamInfo(teamID, false)
		local luaAI = Spring.GetTeamLuaAI(teamID)
		isAITeam[teamID] = isAI and (luaAI == nil or luaAI == "") or false
	end

	local function toUI(kind, unitID, a, b)
		SendToUnsynced("t4hero_event", kind, unitID, a or 0, b or 0)
	end

	local function toAI(teamID, text)
		SendToUnsynced("t4hero_aimsg", teamID, text)
	end

	---------------------------------------------------------------- helpers

	local function rankOf(h, key)
		return h.ranks[key] or 0
	end

	local function frameNow()
		return spGetGameFrame()
	end

	local function isEnemyOf(uid, ally)
		local a = spGetUnitAllyTeam(uid)
		return a and a ~= ally
	end

	local function enemiesIn(x, z, r, ally)
		local out = {}
		for _, uid in ipairs(spGetUnitsInCylinder(x, z, r)) do
			if isEnemyOf(uid, ally) and not spGetUnitIsDead(uid) then
				out[#out + 1] = uid
			end
		end
		return out
	end

	local function alliesIn(x, z, r, ally)
		local out = {}
		for _, uid in ipairs(spGetUnitsInCylinder(x, z, r)) do
			if spGetUnitAllyTeam(uid) == ally then
				out[#out + 1] = uid
			end
		end
		return out
	end

	local function costOf(uid)
		return unitCost[spGetUnitDefID(uid) or -1] or 0
	end

	local function stun(uid, seconds, attackerID)
		local _, maxHp = spGetUnitHealth(uid)
		if maxHp then
			spAddUnitDamage(uid, maxHp * 3, seconds, attackerID)
		end
	end

	local function damageArea(x, z, r, ally, dmg, attackerID, stunSeconds)
		local hit = enemiesIn(x, z, r, ally)
		for _, uid in ipairs(hit) do
			spAddUnitDamage(uid, dmg, 0, attackerID)
			if stunSeconds and stunSeconds > 0 then
				stun(uid, stunSeconds, attackerID)
			end
		end
		return hit
	end

	-- Lua SpawnCEG takes the bare CEG name; weapondefs use the "custom:" prefix
	local function ceg(name, x, y, z)
		if x then
			spSpawnCEG(name:gsub("^custom:", ""), x, y, z, 0, 1, 0, 0, 0)
		end
	end

	local function heroPos(unitID)
		local x, y, z = spGetUnitPosition(unitID)
		return x, y, z
	end

	local function randomPointIn(x, z, r)
		local a = random() * 6.283
		local d = sqrt(random()) * r
		return x + math.cos(a) * d, z + math.sin(a) * d
	end

	---------------------------------------------------------------- ability kit: shared state (v15)
	-- a1/a2/ult are `kind`s of the kit (CUSTOM.md, "Ability kit"; casts and passives in the "abilities"
	-- sections below) with per-rank values { r1, r2, r3 } (a plain number = every rank). Abilities never
	-- touch the hero's weapons: their damage is their own, dealt by the gadget to enemies only (abilityHurt),
	-- and grows with the hero's level by H.ABILITY_POWER_PER_LEVEL - not with items, crits or weapon ranks.

	local ABILITY_KEYS = { "a1", "a2", "ult" }
	local POWER_PER_LEVEL = H.ABILITY_POWER_PER_LEVEL or 0.015
	local inAbility = false -- true while the gadget deals ability damage (the damage callins see it)
	local auraArmor = {}   -- unitID -> share of damage taken removed (aura_armor)
	local slowed = {}      -- unitID -> slow applied (aura_slow)
	local summoned = {}    -- unitID -> { owner, expire } (active_summon)
	local abProj = {}      -- projectileID -> frame: projectiles of the kit (no engine damage of their own)
	-- defined with the casts below; the damage callins and the lifecycle call them
	local abilityAttackMult, abilityVictim, abilityOnHit, abilityUnitDestroyed

	-- a per-rank value
	local function val(v, r)
		if type(v) == "table" then
			return v[r] or v[#v]
		end
		return v
	end

	-- ability damage, healing and absorb grow with the hero's level
	local function abilityPower(h)
		return 1 + POWER_PER_LEVEL * (((h and h.level) or 1) - 1)
	end

	-- the learned ability of a kind: b, rank, key
	local function learnedOf(h, kind)
		local cfg = h.def.cfg
		for _, key in ipairs(ABILITY_KEYS) do
			local b = cfg[key]
			if b and b.kind == kind then
				local r = rankOf(h, key)
				if r > 0 then
					return b, r, key
				end
			end
		end
	end

	-- the stat passives, added to the mods sumMods builds: `stats` ranks are absolute (HP, HP/s, elmos/s,
	-- elmos) and become shares of the hero's base, the unit the stat code works in
	local function abilityMods(h, m)
		local d = h.def
		for _, key in ipairs(ABILITY_KEYS) do
			local b = d.cfg[key]
			local r = rankOf(h, key)
			if b and r > 0 then
				if b.kind == "stats" and b.ranks and b.ranks[r] then
					local s = b.ranks[r]
					m.hp = m.hp + (s.hp or 0) / max(1, d.health)
					m.armor = m.armor + (s.armor or 0)
					m.regen = m.regen + (s.regen or 0) / max(1, d.health)
					m.speed = m.speed + (s.speed or 0) / max(1, d.speed)
					m.sight = m.sight + (s.sight or 0) / max(1, d.sight)
					if d.radar > 0 then
						m.radar = m.radar + (s.radar or 0) / d.radar
					end
				elseif b.kind == "lifesteal" then
					m.lifesteal = m.lifesteal + val(b.frac, r)
				elseif b.kind == "thorns" then
					m.thorns = m.thorns + val(b.frac, r)
				end
			end
		end
	end

	---------------------------------------------------------------- items on the ground
	-- Published as one game rules string "hero_ground": "<id>:<item index>:<x>:<z>;..." (everyone sees
	-- them, like Warcraft items on the ground).

	local ground = {}      -- id -> { item, x, z, expire }
	local groundNext = 1
	local groundDirty = false

	local function publishGround()
		local parts = {}
		for id, g in pairs(ground) do
			parts[#parts + 1] = string.format("%d:%d:%d:%d", id, H.itemIndex[g.item], g.x, g.z)
		end
		Spring.SetGameRulesParam("hero_ground", table.concat(parts, ";"))
		groundDirty = false
	end

	dropItem = function(item, x, z)
		if not item or not H.items[item] then
			return
		end
		x = max(32, min(Game.mapSizeX - 32, x))
		z = max(32, min(Game.mapSizeZ - 32, z))
		local id = groundNext
		groundNext = groundNext + 1
		ground[id] = { item = item, x = floor(x), z = floor(z), expire = spGetGameFrame() + H.ITEM_LIFETIME * GAME_SPEED }
		groundDirty = true
		ceg("hero-itemdrop-" .. H.items[item].rarity, x, spGetGroundHeight(x, z), z)
	end

	-- a random item; a higher level shifts the odds to the rarer ones
	randomItem = function(level)
		local byRarity = {}
		for _, id in ipairs(H.itemOrder) do
			local r = H.items[id].rarity
			byRarity[r] = byRarity[r] or {}
			byRarity[r][#byRarity[r] + 1] = id
		end
		local total, weights = 0, {}
		for r, info in pairs(H.rarities) do
			local w = info.weight
			if r ~= "common" then
				w = w * (1 + (level or 0) / 20)
			end
			weights[r] = w
			total = total + w
		end
		local pick = random() * total
		for r, w in pairs(weights) do
			pick = pick - w
			if pick <= 0 and byRarity[r] then
				return byRarity[r][random(#byRarity[r])]
			end
		end
		return H.itemOrder[random(#H.itemOrder)]
	end

	---------------------------------------------------------------- stats

	local ITEM_KEYS = { "damage", "hp", "armor", "speed", "range", "reload", "sight", "lifesteal", "thorns", "cdr", "xp", "splash", "burn" }

	local function sumMods(h)
		local cfg = h.def.cfg
		local m = { damage = 0, hp = 0, armor = 0, regen = 0, speed = 0, range = 0, reload = 0, sight = 0,
			radar = 0, accuracy = 0, lifesteal = 0, thorns = 0, cdr = 0, xp = 0, splash = 0, burn = 0,
			crit = nil, aura = nil, zap = nil,
			weaponDamage = {}, weaponReload = {}, burst = {}, projectiles = {}, swaps = {}, tree = {} }
		local function add(t, rankMult)
			for k, v in pairs(t) do
				if type(v) == "number" and m[k] then
					m[k] = m[k] + v * rankMult
				elseif k == "weaponDamage" or k == "weaponReload" or k == "burst" then
					for wk, wv in pairs(v) do
						m[k][wk] = (m[k][wk] or 0) + wv * rankMult
					end
				elseif k == "projectiles" then
					for wk, wv in pairs(v) do
						m.projectiles[wk] = wv
					end
				elseif k == "swap" or k == "swap2" then
					m.swaps[#m.swaps + 1] = v
				end
			end
		end
		for key, b in pairs(H.common) do
			local r = rankOf(h, key)
			if r > 0 then
				add(b.per, r)
			end
		end
		abilityMods(h, m) -- stat passives of the abilities (never weapon changes)
		-- weapon trees
		for wi, tree in ipairs(h.def.trees) do
			local t = { ranks = {}, rankSum = 0, damage = 0, range = 0, reload = 0, splash = 0, pierce = 0, pierceLen = 0, burn = 0, discharge = 0 }
			for _, track in ipairs(H.weaponKinds[tree.kind].tracks) do
				local r = rankOf(h, "w" .. wi .. "_" .. track)
				local tr = H.tracks[track]
				t.ranks[tr.stat] = r
				t.rankSum = t.rankSum + r
				if t[tr.stat] and not tr.abs then
					t[tr.stat] = t[tr.stat] + tr.per * r
				end
				if tr.len and r > 0 then
					t.pierceLen = tr.len
				end
			end
			t.tier = H.weaponTier(t.rankSum)
			m.tree[wi] = t
		end
		-- items
		for slot = 1, H.INVENTORY do
			local it = h.items[slot] and H.items[h.items[slot]]
			if it then
				for _, k in ipairs(ITEM_KEYS) do
					if it.stats[k] then
						m[k] = m[k] + it.stats[k]
					end
				end
				if it.stats.crit and (not m.crit or it.stats.crit[1] > m.crit[1]) then
					m.crit = it.stats.crit
				end
				if it.aura and (not m.aura or it.aura.damage > m.aura.damage) then
					m.aura = it.aura
				end
				if it.zap then
					m.zap = it.zap
				end
			end
		end
		return m
	end

	local spSetUnitWeaponDamages = Spring.SetUnitWeaponDamages
	local EMPTY_TREE = { ranks = {}, rankSum = 0, damage = 0, range = 0, reload = 0, splash = 0, pierce = 0, pierceLen = 0, burn = 0, discharge = 0, tier = 1 }

	local function applyStats(unitID, h)
		local def = h.def
		local m = sumMods(h)
		local frame = frameNow()
		local buff = h.buff and h.buff.expire > frame and h.buff.fx or {}
		local L = h.level
		h.mods = m
		h.dmgMult = (1 + H.LEVEL_DAMAGE * (L - 1)) * (1 + m.damage + (buff.damage or 0))
		h.armor = min(0.75, m.armor)
		h.regen = m.regen

		-- health growth is applied as damage taken / hpMult ("effective health"): the engine recomputes
		-- maxHealth from the unitdef whenever a unit gains engine experience (modrules healthScale), so a
		-- SetUnitMaxHealth would be lost after the next hit
		h.hpMult = max(0.2, (1 + H.LEVEL_HP * (L - 1)) * (1 + m.hp))
		spSetUnitRulesParam(unitID, "hero_hpmult", h.hpMult, INLOS)
		spSetUnitRulesParam(unitID, "hero_dmgmult", h.dmgMult, INLOS)
		spSetUnitRulesParam(unitID, "hero_armor", h.armor, INLOS)
		spSetUnitRulesParam(unitID, "hero_regen", m.regen, INLOS)

		-- weapons: global mods x the weapon's own tree
		local reloadMult = max(0.2, (1 - m.reload) * (1 - (buff.reload or 0)))
		local accMult = max(0.1, 1 - m.accuracy)
		local maxRange = 0
		local dps = 0
		h.wdmg = {}
		h.wfx = {}
		for n, w in pairs(def.weapons) do
			local wi = def.treeOf[n]
			local t = wi and m.tree[wi] or EMPTY_TREE
			local wr = max(0.15, reloadMult * (1 - (m.weaponReload[w.key] or 0)) * (1 - t.reload))
			spSetUnitWeaponState(unitID, n, "reloadTime", w.reload * wr)
			local r = w.range * (1 + m.range + t.range + (buff.range or 0))
			spSetUnitWeaponState(unitID, n, "range", r)
			if r > maxRange and w.damage > 0 then
				maxRange = r
			end
			if accMult < 1 then
				spSetUnitWeaponState(unitID, n, "accuracy", w.accuracy * accMult)
				spSetUnitWeaponState(unitID, n, "sprayAngle", w.spray * accMult)
			end
			local burst = w.burst + (m.burst[w.key] or 0)
			local salvo = t.ranks.salvo or 0
			if salvo > 0 then
				burst = burst + math.ceil(max(w.burst, 3) * H.tracks.salvo.per * salvo)
			end
			if burst ~= w.burst then
				spSetUnitWeaponState(unitID, n, "burst", burst)
			end
			local proj = (m.projectiles[w.key] or w.projectiles) + (t.ranks.pellets or 0) * H.tracks.pellets.per
			if proj ~= w.projectiles then
				spSetUnitWeaponState(unitID, n, "projectiles", proj)
			end
			local aoe = w.aoe * (1 + t.splash + m.splash)
			if w.aoe > 0 and spSetUnitWeaponDamages then
				spSetUnitWeaponDamages(unitID, n, "damageAreaOfEffect", aoe)
			end
			local mult = (1 + (m.weaponDamage[w.key] or 0)) * (1 + t.damage)
			h.wdmg[w.wdid] = mult
			if w.damage > 0 then
				dps = dps + w.damage * mult * h.dmgMult * proj * burst / max(0.05, w.reload * wr)
			end
			for _, cw in pairs(def.tierWdid[n] or {}) do
				h.wdmg[cw] = mult
			end
			h.wfx[w.wdid] = { n = n, tier = t.tier, aoe = aoe, baseAoe = w.aoe, pierce = t.pierce, pierceLen = t.pierceLen,
				burn = t.burn + m.burn, discharge = t.discharge }
		end
		for wi, t in pairs(m.tree) do
			spSetUnitRulesParam(unitID, "hero_wtier_" .. wi, t.tier, INLOS)
		end
		if maxRange > 0 then
			Spring.SetUnitMaxRange(unitID, maxRange)
		end
		spSetUnitRulesParam(unitID, "hero_dps", floor(dps), INLOS)
		spSetUnitRulesParam(unitID, "hero_range", floor(maxRange), INLOS)

		-- movement
		local speedMult = buff.immobile and 0.02 or max(0.2, 1 + m.speed + (buff.speed or 0))
		local spd = def.speed * speedMult -- elmos per second, like UnitDefs[].speed
		Spring.MoveCtrl.SetGroundMoveTypeData(unitID, { maxSpeed = spd, maxWantedSpeed = spd })
		spSetUnitRulesParam(unitID, "hero_speed", spd, INLOS)

		-- sensors
		if m.sight > 0 then
			Spring.SetUnitSensorRadius(unitID, "los", def.sight * (1 + m.sight))
			Spring.SetUnitSensorRadius(unitID, "airLos", max(def.airSight, def.sight) * (1 + m.sight))
		end
		if m.radar > 0 and def.radar > 0 then
			Spring.SetUnitSensorRadius(unitID, "radar", def.radar * (1 + m.radar))
		end
	end

	local function publish(unitID, h)
		spSetUnitRulesParam(unitID, "hero_level", h.level, INLOS)
		local lo = H.xpFor(h.level, xpMult) * h.def.cost
		local hi = H.xpFor(h.level + 1, xpMult) * h.def.cost
		local frac = h.level >= H.MAX_LEVEL and 1 or max(0, min(1, (h.xp - lo) / max(1, hi - lo)))
		spSetUnitRulesParam(unitID, "hero_xp", frac, ALLIED)
		spSetUnitRulesParam(unitID, "hero_xp_abs", floor(h.xp - lo), ALLIED)
		spSetUnitRulesParam(unitID, "hero_xp_need", floor(hi - lo), ALLIED)
		spSetUnitRulesParam(unitID, "hero_points", h.level - #h.picks, ALLIED)
		spSetUnitRulesParam(unitID, "hero_kills", h.kills or 0, ALLIED)
		for _, key in ipairs(h.def.keys) do
			spSetUnitRulesParam(unitID, "hero_rank_" .. key, rankOf(h, key), ALLIED)
		end
		spSetUnitRulesParam(unitID, "hero_autocast", h.autocast and 1 or 0, ALLIED)
	end

	local function publishItems(unitID, h)
		for slot = 1, H.INVENTORY do
			local id = h.items[slot]
			spSetUnitRulesParam(unitID, "hero_item_" .. slot, id and H.itemIndex[id] or 0, INLOS)
			spSetUnitRulesParam(unitID, "hero_itemcd_" .. slot, h.itemReady[slot] or 0, ALLIED)
		end
	end

	local function publishDead(teamID, name)
		local rec = dead[teamID] and dead[teamID][name]
		if rec then
			local def
			for _, d in pairs(heroDefs) do
				if d.name == name then
					def = d
				end
			end
			spSetTeamRulesParam(teamID, "hero_dead_" .. name, rec.level, ALLIED)
			spSetTeamRulesParam(teamID, "hero_revive_" .. name, floor(def.cost * (1 + H.REVIVE_COST_PER_LEVEL * rec.level)), ALLIED)
		else
			spSetTeamRulesParam(teamID, "hero_dead_" .. name, 0, ALLIED)
			spSetTeamRulesParam(teamID, "hero_revive_" .. name, 0, ALLIED)
		end
	end

	---------------------------------------------------------------- talents

	-- "ok", or why not: "points", "level", "max", "metal", "unknown"
	local function learnState(h, key)
		local name = h.def.name
		local b = H.branch(name, key)
		if not b then
			return "unknown"
		end
		local r = rankOf(h, key)
		if r >= H.maxRank(name, key) then
			return "max"
		end
		if h.level - #h.picks <= 0 then
			return "points"
		end
		if h.level < H.reqLevel(name, key, r + 1) then
			return "level"
		end
		local cost = H.metalCost(name, key, r + 1)
		if cost > 0 and (Spring.GetTeamResources(h.team, "metal") or 0) < cost then
			return "metal", cost
		end
		return "ok", cost
	end

	local function canLearn(h, key)
		return learnState(h, key) == "ok"
	end

	-- the AI keeps a reserve for its army: a rank only when it has half as much metal again
	local function aiCanLearn(h, key)
		local state, cost = learnState(h, key)
		return state == "ok" and (cost or 0) * 1.5 <= (Spring.GetTeamResources(h.team, "metal") or 0)
	end

	local function updateCmdDescs(unitID, h)
		for cmdID, key in pairs(h.def.cmds) do
			local idx = Spring.FindUnitCmdDesc(unitID, cmdID)
			if idx then
				Spring.EditUnitCmdDesc(unitID, idx, { disabled = rankOf(h, key) == 0 })
			end
		end
	end

	local function learn(unitID, h, key, silent)
		local state, cost = learnState(h, key)
		if state ~= "ok" then
			if state == "metal" and not silent then
				toUI("nometal", unitID, cost)
			end
			return false
		end
		if cost and cost > 0 and not Spring.UseTeamResource(h.team, "metal", cost) then
			return false
		end
		h.picks[#h.picks + 1] = key
		h.ranks[key] = rankOf(h, key) + 1
		applyStats(unitID, h)
		updateCmdDescs(unitID, h)
		publish(unitID, h)
		if not silent then
			toUI("learn", unitID, h.ranks[key])
			local x, y, z = heroPos(unitID)
			if x and frameNow() - (h.lastLearnFx or -100) > 10 then
				h.lastLearnFx = frameNow()
				ceg(key == "ult" and "hero-levelup-big" or "hero-learn", x, y, z)
			end
		end
		return true
	end

	-- the AI spends its points (and metal): the ultimate and the abilities as soon as it can, then the
	-- damage of its weapons, plating and the rest of the trees in turn
	local function learnAI(unitID, h)
		local guard = 0
		while h.level - #h.picks > 0 and guard < 120 do
			guard = guard + 1
			local done = false
			for _, key in ipairs({ "ult", "a1", "a2" }) do
				if aiCanLearn(h, key) then
					done = learn(unitID, h, key, true)
					break
				end
			end
			if not done then
				-- the cheapest useful rank: weapon damage first, then plating, then anything
				local best, bestScore
				for _, key in ipairs(h.def.keys) do
					if aiCanLearn(h, key) then
						local r = rankOf(h, key)
						local score = r * 2
						if key:find("_damage$") then
							score = score - 3
						elseif key == "plating" then
							score = score - 2
						elseif key == "servos" then
							score = score + 4
						end
						if not bestScore or score < bestScore then
							best, bestScore = key, score
						end
					end
				end
				if best then
					done = learn(unitID, h, best, true)
				end
			end
			if not done then
				break
			end
		end
	end

	---------------------------------------------------------------- experience

	local function levelUp(unitID, h)
		h.level = h.level + 1
		applyStats(unitID, h)
		local x, y, z = heroPos(unitID)
		local f = frameNow()
		-- several levels at once (a big kill) show one effect
		if x and f - (h.lastLevelFx or -100) > 20 then
			h.lastLevelFx = f
			ceg(h.level % 5 == 0 and "hero-levelup-big" or "hero-levelup", x, y, z)
			ceg(h.level % 5 == 0 and "custom:commander-levelup--x5" or "custom:commander-levelup--x3", x, y + 20, z)
		end
		toUI("levelup", unitID, h.level)
		if isAITeam[h.team] then
			learnAI(unitID, h)
		end
	end

	local function addXP(unitID, h, metal)
		if h.level >= H.MAX_LEVEL or metal <= 0 then
			return
		end
		h.xp = h.xp + metal * (h.def.cfg.xpRate or 1) * (1 + (h.mods and h.mods.xp or 0))
		local leveled = false
		while h.level < H.MAX_LEVEL and h.xp >= H.xpFor(h.level + 1, xpMult) * h.def.cost do
			levelUp(unitID, h)
			leveled = true
		end
		if leveled then
			publish(unitID, h)
		end
	end

	---------------------------------------------------------------- lifecycle

	local function newHero(unitID, udid, teamID, rec)
		local def = heroDefs[udid]
		local h = {
			unitID = unitID, def = def, team = teamID, level = 1, xp = 0, picks = {}, ranks = {},
			ready = {}, shots = {}, autocast = true, buff = nil, lastCrit = 0, undyingReady = 0, undyingUntil = 0,
			items = {}, itemReady = {}, kills = 0,
		}
		if rec then
			h.level = rec.level
			h.xp = H.xpFor(rec.level, xpMult) * def.cost
			for _, key in ipairs(rec.picks) do
				h.picks[#h.picks + 1] = key
				h.ranks[key] = rankOf(h, key) + 1
			end
		end
		heroes[unitID] = h
		return h
	end

	function gadget:UnitCreated(unitID, unitDefID, teamID)
		local def = heroDefs[unitDefID]
		if not def then
			return
		end
		local rec = dead[teamID] and dead[teamID][def.name]
		if rec then
			-- a revive: the same hero, five levels down, at a price that grows with its level
			local mult = 1 + H.REVIVE_COST_PER_LEVEL * rec.level
			local tmult = 1 + H.REVIVE_TIME_PER_LEVEL * rec.level
			Spring.SetUnitCosts(unitID, { metalCost = def.cost * mult, energyCost = def.energy * mult, buildTime = def.buildTime * tmult })
			pendingRevive[unitID] = rec
			spSetUnitRulesParam(unitID, "hero_revive_level", rec.level, INLOS)
		end
	end

	local function insertCmds(unitID, h)
		local cfg = h.def.cfg
		for cmdID, key in pairs(h.def.cmds) do
			local b = cfg[key]
			local ctype = CMDTYPE.ICON
			if b.target == "map" then
				ctype = CMDTYPE.ICON_MAP
			elseif b.target == "unit" then
				ctype = CMDTYPE.ICON_UNIT
			end
			Spring.InsertUnitCmdDesc(unitID, {
				id = cmdID, type = ctype, name = b.name, action = b.action,
				cursor = b.cursor or (b.target and "Attack") or nil, tooltip = b.name .. ": " .. b.desc,
				disabled = rankOf(h, key) == 0,
			})
		end
		Spring.InsertUnitCmdDesc(unitID, {
			id = CMD_HERO_AUTOCAST, type = CMDTYPE.ICON_MODE, name = "Autocast", action = "hero_autocast",
			tooltip = "Hero abilities cast themselves when useful", params = { 1, "hero_autocast_off", "hero_autocast_on" },
		})
	end

	function gadget:UnitFinished(unitID, unitDefID, teamID)
		local def = heroDefs[unitDefID]
		if not def then
			return
		end
		local rec = pendingRevive[unitID]
		pendingRevive[unitID] = nil
		if rec then
			Spring.SetUnitCosts(unitID, { metalCost = def.cost, energyCost = def.energy, buildTime = def.buildTime })
			dead[teamID][def.name] = nil
			publishDead(teamID, def.name)
		end
		local h = newHero(unitID, unitDefID, teamID, rec)
		applyStats(unitID, h)
		insertCmds(unitID, h)
		if isAITeam[teamID] then
			learnAI(unitID, h)
		end
		publish(unitID, h)
		publishItems(unitID, h)
		spSetTeamRulesParam(teamID, "hero_built_" .. def.name, 1, ALLIED)
		local x, y, z = heroPos(unitID)
		if x then
			ceg(rec and "hero-revive" or "hero-levelup-big", x, y, z)
		end
		toUI(rec and "revived" or "born", unitID, h.level)
	end

	local function giveXPForDeath(unitID, unitDefID, attackerID)
		local cost = (unitCost[unitDefID] or 0) * (structureDefs[unitDefID] and H.XP_STRUCTURE or 1)
		if cost <= 0 then
			return
		end
		local ally = spGetUnitAllyTeam(unitID)
		local x, _, z = spGetUnitPosition(unitID)
		local killer = attackerID and heroes[attackerID]
		if killer and spGetUnitAllyTeam(attackerID) ~= ally then
			killer.kills = (killer.kills or 0) + 1
			if not heroes[unitID] and x and random() < min(H.ITEM_DROP_MAX, (unitCost[unitDefID] or 0) * H.ITEM_DROP_CHANCE) then
				dropItem(randomItem(0), x, z)
			end
			local bonus = H.XP_KILL * cost
			local victim = heroes[unitID]
			if victim then
				bonus = bonus + H.XP_HERO_KILL * cost * victim.level / 10
			end
			addXP(attackerID, killer, bonus)
		end
		if x and attackerID then
			local r2 = H.XP_SHARE_RADIUS * H.XP_SHARE_RADIUS
			for hid, h in pairs(heroes) do
				if hid ~= attackerID and spGetUnitAllyTeam(hid) ~= ally then
					local hx, _, hz = spGetUnitPosition(hid)
					if hx and (hx - x) ^ 2 + (hz - z) ^ 2 < r2 then
						addXP(hid, h, H.XP_SHARE * cost)
					end
				end
			end
		end
	end

	function gadget:UnitDestroyed(unitID, unitDefID, teamID, attackerID)
		pendingRevive[unitID] = nil
		guardMult[unitID] = nil
		invuln[unitID] = nil
		auraDamage[unitID] = nil
		local summon = abilityUnitDestroyed(unitID) -- a summon gives no experience and drops nothing
		local _, _, _, _, bp = spGetUnitHealth(unitID)
		if bp and bp >= 1 and not summon then
			giveXPForDeath(unitID, unitDefID, attackerID)
		end
		local h = heroes[unitID]
		if not h then
			return
		end
		heroes[unitID] = nil
		-- the team remembers its hero: a revive brings it back DEATH_LEVELS lower with the first picks
		local level = max(1, h.level - H.DEATH_LEVELS)
		local picks = {}
		for i = 1, min(#h.picks, level) do
			picks[i] = h.picks[i]
		end
		dead[h.team] = dead[h.team] or {}
		dead[h.team][h.def.name] = { level = level, picks = picks }
		publishDead(h.team, h.def.name)
		local x, y, z = spGetUnitPosition(unitID)
		if x then
			-- everything it carried falls where it died, plus a trophy that is better the higher it was
			local drops = {}
			for slot = 1, H.INVENTORY do
				if h.items[slot] then
					drops[#drops + 1] = h.items[slot]
				end
			end
			drops[#drops + 1] = randomItem(h.level)
			for i, id in ipairs(drops) do
				local a = i / #drops * 6.283
				local d = #drops > 1 and 140 or 0
				dropItem(id, x + math.cos(a) * d, z + math.sin(a) * d)
			end
		end
		if x then
			ceg("hero-death", x, y, z)
		end
		toUI("died", unitID, h.level, level)
	end

	function gadget:AllowUnitTransfer(unitID, unitDefID, oldTeam, newTeam, capture)
		if heroDefs[unitDefID] and Spring.GetTeamUnitDefCount(newTeam, unitDefID) > 0 then
			return false
		end
		return true
	end

	function gadget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
		local h = heroes[unitID]
		if h then
			h.team = newTeam
			h.retreating = false
			h.detached = false
			h.orderX = nil
		end
		local rec = pendingRevive[unitID]
		if rec then
			pendingRevive[unitID] = nil
		end
	end

	---------------------------------------------------------------- damage

	function gadget:UnitPreDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
		if invuln[unitID] then
			return 0, 0
		end
		-- hero warheads, novas and abilities never hurt their own side (a meteor rain over a melee hero)
		if (heroWeapon[weaponDefID] or inAbility) and attackerTeam and spAreTeamsAllied(attackerTeam, unitTeam) then
			return 0, 0
		end
		-- a projectile of the ability kit: its damage is the ability's, applied when it explodes
		if projectileID and abProj[projectileID] and not inAbility then
			return 0, 0
		end
		local m = (guardMult[unitID] or 1) * (1 - (auraArmor[unitID] or 0))
		local a = attackerID and heroes[attackerID]
		if a and not inAbility then
			m = m * a.dmgMult * (a.wdmg and a.wdmg[weaponDefID] or 1)
			if not paralyzer then
				m = m * abilityAttackMult(a, unitID, unitDefID) -- crit / slayer passives
			end
			local crit = a.mods and a.mods.crit
			if crit and not paralyzer and random() < crit[1] then
				m = m * crit[2]
				local f = frameNow()
				if f - a.lastCrit > 8 then
					a.lastCrit = f
					local x, y, z = spGetUnitPosition(unitID)
					if x then
						ceg("hero-crit", x, y + 20, z)
					end
				end
			end
		elseif not a and attackerID and auraDamage[attackerID] then
			m = m * (1 + auraDamage[attackerID])
		end
		local v = heroes[unitID]
		if v then
			m = m * (1 - v.armor) / (v.hpMult or 1)
			local f = frameNow()
			if v.undyingUntil > f then
				return 0, 0
			end
			-- bladestorm / buff armor, the absorb shield, undying
			m = abilityVictim(unitID, v, damage, m, paralyzer, f)
			if m <= 0 then
				return 0, 0
			end
		end
		if m ~= 1 then
			return damage * m, 1
		end
		return damage, 1
	end

	-- weapon tree effects of hero hits, resolved every 6 frames (beams hit 30 times a second)
	local pierceHits = {}  -- "<owner>:<victim>" -> { owner, victim, dmg, dx, dz, len }
	local burning = {}     -- victim -> { owner, pool }
	local discharge = {}   -- victim -> { owner, dmg }
	local inThorns = false

	function gadget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
		local victim = heroes[unitID]
		if victim and damage > 0 then
			victim.lastHit = frameNow()
			-- thorns: part of the damage goes back to the attacker
			local th = victim.mods and victim.mods.thorns or 0
			if th > 0 and not paralyzer and not inThorns and attackerID and spValidUnitID(attackerID)
				and attackerTeam and not spAreTeamsAllied(attackerTeam, unitTeam) then
				inThorns = true
				spAddUnitDamage(attackerID, damage * (victim.hpMult or 1) * th, 0, unitID)
				inThorns = false
			end
		end
		if not attackerID or damage <= 0 then
			return
		end
		local h = heroes[attackerID]
		if not h or (attackerTeam and spAreTeamsAllied(attackerTeam, unitTeam)) then
			return
		end
		local _, maxHp, _, _, bp = spGetUnitHealth(unitID)
		if not maxHp or maxHp <= 0 or (bp and bp < 1) then
			return
		end
		local value = min(damage, maxHp) / maxHp * (unitCost[unitDefID] or 0) * (structureDefs[unitDefID] and H.XP_STRUCTURE or 1)
		if paralyzer then
			value = value * 0.25
		end
		addXP(attackerID, h, value)
		if paralyzer or inThorns or inAbility then
			return
		end
		abilityOnHit(attackerID, h, unitID) -- procs of the abilities, a hit ends a cloak
		local mods = h.mods or {}
		if (mods.lifesteal or 0) > 0 then
			local hp, mhp = spGetUnitHealth(attackerID)
			if hp then
				spSetUnitHealth(attackerID, min(mhp, hp + damage * mods.lifesteal / (h.hpMult or 1)))
			end
		end
		local fx = h.wfx and h.wfx[tierBase[weaponDefID] or weaponDefID]
		if not fx then
			return
		end
		if fx.pierce > 0 then
			local key = attackerID .. ":" .. unitID
			local p = pierceHits[key]
			if not p then
				local ax, _, az = spGetUnitPosition(attackerID)
				local vx, _, vz = spGetUnitPosition(unitID)
				if ax and vx then
					local dx, dz = vx - ax, vz - az
					local d = max(1, sqrt(dx * dx + dz * dz))
					p = { owner = attackerID, victim = unitID, dmg = 0, dx = dx / d, dz = dz / d, len = fx.pierceLen, tier = fx.tier }
					pierceHits[key] = p
				end
			end
			if p then
				p.dmg = p.dmg + damage * fx.pierce
			end
		end
		if fx.burn > 0 then
			local b = burning[unitID]
			if not b then
				b = { owner = attackerID, pool = 0 }
				burning[unitID] = b
			end
			b.pool = b.pool + damage * fx.burn
		end
		if fx.discharge > 0 then
			local d = discharge[unitID]
			if not d then
				d = { owner = attackerID, dmg = 0 }
				discharge[unitID] = d
			end
			d.dmg = d.dmg + damage * fx.discharge
		end
	end

	local function weaponEffects(f)
		for key, p in pairs(pierceHits) do
			pierceHits[key] = nil
			local vx, vy, vz = spGetUnitPosition(p.victim)
			local ally = spValidUnitID(p.owner) and spGetUnitAllyTeam(p.owner)
			if vx and ally then
				local hit = {}
				local step = 140
				for d = step, p.len, step do
					local px, pz = vx + p.dx * d, vz + p.dz * d
					for _, uid in ipairs(spGetUnitsInCylinder(px, pz, 110)) do
						if uid ~= p.victim and not hit[uid] and isEnemyOf(uid, ally) then
							hit[uid] = true
							spAddUnitDamage(uid, p.dmg, 0, p.owner)
						end
					end
				end
				local ex, ez = vx + p.dx * p.len, vz + p.dz * p.len
				ceg(p.tier >= 3 and "hero-pierce-big" or "hero-pierce", ex, spGetGroundHeight(ex, ez) + 30, ez)
			end
		end
		for uid, b in pairs(burning) do
			if not spValidUnitID(uid) or spGetUnitIsDead(uid) or b.pool < 1 then
				burning[uid] = nil
			else
				local dmg = b.pool * 0.12
				b.pool = b.pool - dmg
				spAddUnitDamage(uid, dmg, 0, spValidUnitID(b.owner) and b.owner or nil)
				if f % 12 < 6 then
					local x, y, z = spGetUnitPosition(uid)
					ceg("hero-afterburn", x, y + 10, z)
				end
			end
		end
		for uid, d in pairs(discharge) do
			discharge[uid] = nil
			if spValidUnitID(uid) and not spGetUnitIsDead(uid) then
				spAddUnitDamage(uid, d.dmg, 2, spValidUnitID(d.owner) and d.owner or nil)
				local x, y, z = spGetUnitPosition(uid)
				ceg("hero-static", x, y, z)
			end
		end
	end

	---------------------------------------------------------------- visual tiers of upgraded weapons

	local upTime = {}
	for wdid, wd in pairs(WeaponDefs) do
		if wd.type == "StarburstLauncher" then
			upTime[wdid] = math.floor((wd.uptime or 1) * GAME_SPEED)
		end
	end

	local projParams = { pos = { 0, 0, 0 }, speed = { 0, 0, 0 }, owner = -1, team = -1, gravity = 0, ttl = 900 }

	local beamParams = { pos = { 0, 0, 0 }, ["end"] = { 0, 0, 0 }, ttl = 3, owner = -1, team = -1 }
	local isBeam = {}
	for wdid, wd in pairs(WeaponDefs) do
		if wd.type == "BeamLaser" or wd.type == "LightningCannon" then
			isBeam[wdid] = wd.beamTTL or 3
		end
	end
	local spSetProjectileDamages = Spring.SetProjectileDamages

	-- the end point of a beam: its velocity is start -> end in Recoil; otherwise the weapon's target
	local function beamEnd(proID, ownerID, num, px, py, pz)
		local vx, vy, vz = Spring.GetProjectileVelocity(proID)
		if vx and (vx * vx + vy * vy + vz * vz) > 100 then
			return px + vx, py + vy, pz + vz
		end
		local tt, _, wt = Spring.GetUnitWeaponTarget(ownerID, num)
		if tt == 1 and wt then
			local x, y, z = spGetUnitPosition(wt)
			if x then
				return x, y + 20, z
			end
		elseif tt == 2 and type(wt) == "table" then
			return wt[1], wt[2], wt[3]
		end
	end

	-- an upgraded weapon draws its shot with the copy of its visual tier
	local function tierSwap(proID, ownerID, weaponDefID, h)
		local fx = h.wfx and h.wfx[weaponDefID]
		if not fx or fx.tier < 2 then
			return
		end
		local to = h.def.tierWdid[fx.n] and h.def.tierWdid[fx.n][fx.tier]
		if not to then
			return
		end
		local px, py, pz = Spring.GetProjectilePosition(proID)
		if not px then
			return
		end
		if isBeam[weaponDefID] then
			local ex, ey, ez = beamEnd(proID, ownerID, fx.n, px, py, pz)
			if not ex then
				return
			end
			Spring.DeleteProjectile(proID)
			beamParams.pos[1], beamParams.pos[2], beamParams.pos[3] = px, py, pz
			beamParams["end"][1], beamParams["end"][2], beamParams["end"][3] = ex, ey, ez
			beamParams.owner = ownerID
			beamParams.team = h.team
			beamParams.ttl = isBeam[weaponDefID]
			spSpawnProjectile(to, beamParams)
			return
		end
		local vx, vy, vz = Spring.GetProjectileVelocity(proID)
		local _, target = Spring.GetProjectileTarget(proID)
		if not target then
			local tt, _, wt = Spring.GetUnitWeaponTarget(ownerID, fx.n)
			if tt == 1 or tt == 2 then
				target = wt
			end
		end
		local grav = Spring.GetProjectileGravity and Spring.GetProjectileGravity(proID) or gravityPerFrame
		local ttl = Spring.GetProjectileTimeToLive and Spring.GetProjectileTimeToLive(proID) or 900
		Spring.DeleteProjectile(proID)
		projParams.pos[1], projParams.pos[2], projParams.pos[3] = px, py, pz
		projParams.speed[1], projParams.speed[2], projParams.speed[3] = vx, vy, vz
		projParams.owner = ownerID
		projParams.team = h.team
		projParams.gravity = grav
		projParams.ttl = ttl
		projParams.tracking = type(target) == "number" and target or nil
		projParams.upTime = upTime[to]
		local newID = spSpawnProjectile(to, projParams)
		projParams.tracking = nil
		projParams.upTime = nil
		if newID then
			if fx.aoe ~= fx.baseAoe and spSetProjectileDamages then
				spSetProjectileDamages(newID, 0, "damageAreaOfEffect", fx.aoe)
			end
			if type(target) == "number" then
				Spring.SetProjectileTarget(newID, target, string.byte("u"))
			elseif type(target) == "table" then
				Spring.SetProjectileTarget(newID, target[1], target[2], target[3])
			end
		end
	end

	-- v15: abilities never swap a weapon's projectiles; only the visual tier of an upgraded weapon does
	function gadget:ProjectileCreated(proID, ownerID, weaponDefID)
		if not swapWatch[weaponDefID] or not ownerID then
			return
		end
		local h = heroes[ownerID]
		if h then
			tierSwap(proID, ownerID, weaponDefID, h)
		end
	end

	---------------------------------------------------------------- abilities: the kit (v15)
	-- Casting, damage, projectiles and timed effects of the ability kit. Kinds and their parameters:
	-- CUSTOM.md, "Ability kit" (and the header of luarules/configs/t4_hero_defs_t4.lua).

	local abilityReady, markActive, seenBy, healUnit, cast, dashes, tryCast, castRange, processEvents, refreshProtection, abilityFrame, abilityPassivesBegin, abilityBuffTick, abilityAuras, abilityShield, abilityPassivesEnd
	do
		function abilityReady(h, key)
			return rankOf(h, key) > 0 and (h.ready[key] or 0) <= frameNow()
		end

		local function startCooldown(unitID, h, key, b, r)
			local cd = val(b.cooldown, r) or 30
			cd = cd * max(0.4, 1 - (h.mods and h.mods.cdr or 0))
			h.ready[key] = frameNow() + floor(cd * GAME_SPEED)
			spSetUnitRulesParam(unitID, "hero_ready_" .. key, h.ready[key], ALLIED)
			spSetUnitRulesParam(unitID, "hero_cd_" .. key, floor(cd * GAME_SPEED), ALLIED)
		end

		function markActive(unitID, key, seconds)
			spSetUnitRulesParam(unitID, "hero_on_" .. key, frameNow() + floor(seconds * GAME_SPEED), INLOS)
			spSetUnitRulesParam(unitID, "hero_dur_" .. key, floor(seconds * GAME_SPEED), INLOS)
		end

		-- "[ability] ..." lines in the infolog while the game rules param hero_ability_log is 1 (bench scenes)
		local function alog(fmt, ...)
			if Spring.GetGameRulesParam("hero_ability_log") == 1 then
				Spring.Echo("[ability] " .. string.format(fmt, ...))
			end
		end

		function seenBy(uid, ally)
			local los = spGetUnitLosState(uid, ally, true)
			return los and los ~= 0
		end

		-- who casts: kept by effects that outlive the hero (a barrage keeps falling after it dies)
		local function caster(unitID, h, key)
			local b = h.def.cfg[key]
			return { owner = unitID, ally = spGetUnitAllyTeam(unitID), team = h.team, name = h.def.name, key = key,
				power = abilityPower(h), extra = h.def.extra, novaWeapon = b and b.novaWeapon }
		end

		local function ownerOf(c)
			return spValidUnitID(c.owner) and not spGetUnitIsDead(c.owner) and c.owner or nil
		end

		-- ability damage to one unit: no hero multipliers, never to allies (UnitPreDamaged drops it)
		local function abilityHurt(uid, dmg, ownerID, paraTime)
			if not dmg or dmg <= 0 or not spValidUnitID(uid) or spGetUnitIsDead(uid) then
				return
			end
			local prev = inAbility
			inAbility = true
			spAddUnitDamage(uid, dmg, paraTime or 0, (ownerID and spValidUnitID(ownerID)) and ownerID or nil)
			inAbility = prev
		end

		local function abilityStun(uid, seconds, ownerID)
			local _, maxHp = spGetUnitHealth(uid)
			if maxHp and seconds and seconds > 0 then
				abilityHurt(uid, maxHp * 3, ownerID, seconds)
			end
		end

		-- damage (and stun / EMP) to every enemy of the caster within radius; returns the units hit
		local function abilityBlast(c, x, z, radius, dmg, stunSeconds, emp)
			local hit = enemiesIn(x, z, radius, c.ally)
			local owner = ownerOf(c)
			for _, uid in ipairs(hit) do
				abilityHurt(uid, dmg, owner)
				if emp and emp > 0 then
					abilityHurt(uid, emp, owner, 3)
				end
				if stunSeconds and stunSeconds > 0 then
					abilityStun(uid, stunSeconds, owner)
				end
			end
			return hit
		end

		-- healing in effective HP (a hero's health is divided by its toughness, see applyStats)
		function healUnit(uid, amount)
			local hp, maxHp, _, _, bp = spGetUnitHealth(uid)
			if not hp or not bp or bp < 1 or hp >= maxHp then
				return 0
			end
			local v = heroes[uid]
			local add = min(maxHp - hp, amount / (v and v.hpMult or 1))
			spSetUnitHealth(uid, hp + add)
			return add
		end

		local function healAllies(c, x, z, radius, amount, fx)
			local n, total = 0, 0
			for _, uid in ipairs(alliesIn(x, z, radius, c.ally)) do
				local add = healUnit(uid, amount)
				if add > 0 then
					n = n + 1
					total = total + add
					if fx and n <= 12 then
						local ux, uy, uz = spGetUnitPosition(uid)
						ceg(fx, ux, uy, uz)
					end
				end
			end
			return n, total
		end

		-- nova[] of an ability: a number is the finale's damage; true is novaDmg, or three times the
		-- ability's own damage (dmg / tick / flat)
		local function novaOf(b, r)
			local v = val(b.nova, r)
			if v == true then
				return val(b.novaDmg, r) or 3 * (val(b.dmg, r) or val(b.tick, r) or val(b.flat, r) or 3000)
			end
			return type(v) == "number" and v or 0
		end

		local abParams = { pos = { 0, 0, 0 }, speed = { 0, 0, 0 }, owner = -1, team = -1, gravity = 0, ttl = 900 }
		local abBeam = { pos = { 0, 0, 0 }, ["end"] = { 0, 0, 0 }, ttl = 8, owner = -1, team = -1 }
		local shots = {} -- projectileID -> shot { c, dmg, aoe, stun, emp, fx, expire }: applied when it explodes

		-- the weapondef an ability spawns: its `weapon`, a hero_* extra of the hero named after the projectile,
		-- or the kit's own hero_ab_* (every hero has those, gamedata/custom_t4_abilities.lua)
		local WEAPON_FALLBACK = {
			missile = { "hero_missile", "hero_heavyrocket" }, shell = { "hero_shell", "hero_heavyshell" },
			meteor = { "hero_meteor" }, bolt = { "hero_stormbolt" }, nuke = { "hero_nuke", "hero_nova" },
			spear = { "hero_spear" }, chain = { "hero_chain" },
		}
		local function abilityWeapon(h, b, proj)
			local e = h.def.extra
			if b.weapon and e[b.weapon] then
				return e[b.weapon]
			end
			for _, name in ipairs(WEAPON_FALLBACK[proj] or {}) do
				if e[name] then
					return e[name]
				end
			end
			local kit = e["hero_ab_" .. (proj == "chain" and "bolt" or proj)]
			if kit then
				return kit
			end
			alog("%s: no weapondef for %s (%s), skipped", h.def.name, proj, tostring(b.weapon))
		end

		-- a spawned ability projectile deals no engine damage of its own (UnitPreDamaged): the ability's numbers
		-- apply when it explodes
		local function spawnAb(wdid, c, px, py, pz, vx, vy, vz)
			if not wdid then
				return nil
			end
			abParams.pos[1], abParams.pos[2], abParams.pos[3] = px, py, pz
			abParams.speed[1], abParams.speed[2], abParams.speed[3] = vx, vy, vz
			abParams.owner = ownerOf(c) or -1
			abParams.team = c.team
			local pid = spSpawnProjectile(wdid, abParams)
			if pid then
				abProj[pid] = frameNow() + 900
			end
			return pid
		end

		-- a lightning bolt drawn from a to b (hero_ab_bolt, or the ability's `weapon`: a LightningCannon shot)
		local function boltVisual(c, wdid, x1, y1, z1, x2, y2, z2, ttl)
			wdid = wdid or (c.extra and c.extra.hero_ab_bolt)
			if not wdid then
				return
			end
			abBeam.pos[1], abBeam.pos[2], abBeam.pos[3] = x1, y1, z1
			abBeam["end"][1], abBeam["end"][2], abBeam["end"][3] = x2, y2, z2
			abBeam.ttl = ttl or 8
			abBeam.owner = ownerOf(c) or -1
			abBeam.team = c.team
			spSpawnProjectile(wdid, abBeam)
		end

		local function abilityImpact(s, x, z)
			local y = spGetGroundHeight(x, z)
			local hit = abilityBlast(s.c, x, z, s.aoe, s.dmg, s.stun, s.emp)
			if s.fx then
				ceg(s.fx, x, y, z)
			end
			s.hits = (s.hits or 0) + #hit
			alog("%s %s impact dmg=%d aoe=%d hit=%d", s.c.name, s.c.key, s.dmg, s.aoe, #hit)
		end

		-- the nuclear (or EMP, or fire) finale of an ultimate: the hero's own hero_nova weapondef (T2 heroes) or
		-- a nuke of the kit sized by the radius - only its effect and sound, the damage is the ability's
		local FINALE_WEAPON = { ["hero-finale-emp"] = "hero_ab_finale_emp", ["hero-finale-fire"] = "hero_ab_finale_fire" }
		local function abilityFinale(c, x, z, dmg, radius, stunSeconds, fx)
			local y = spGetGroundHeight(x, z)
			local e = c.extra or {}
			-- an EMP / fire finale is its own effect; otherwise a nuke sized by the radius under hero-finale
			local own = fx and e[FINALE_WEAPON[fx] or ""]
			local wdid = own or e[c.novaWeapon or "hero_nova"] or (radius >= 520 and e.hero_ab_nova) or (radius >= 300 and e.hero_ab_novamed) or e.hero_ab_novasmall
			if wdid then
				Spring.SpawnExplosion(x, y + 5, z, 0, 0, 0, { weaponDef = wdid, owner = ownerOf(c) or -1, damageGround = false,
					craterAreaOfEffect = 0, damageAreaOfEffect = 0 })
			end
			if not own then
				ceg(fx or "hero-finale", x, y, z)
			end
			local hit = abilityBlast(c, x, z, radius, dmg, stunSeconds)
			alog("%s %s finale dmg=%d radius=%d stun=%s hit=%d", c.name, c.key, dmg, radius, tostring(stunSeconds), #hit)
		end

		local exploded = {} -- ability projectiles that exploded this frame (their engine damage follows the callin)

		function gadget:Explosion(weaponDefID, px, py, pz, attackerID, projectileID)
			if projectileID and abProj[projectileID] then
				exploded[#exploded + 1] = projectileID
				local s = shots[projectileID]
				if s then
					shots[projectileID] = nil
					abilityImpact(s, px, pz)
				end
			end
			return false
		end

		---------------------------------------------------------------- abilities: self buffs

		-- active_buff / active_cloak: h.buffs[key] = { expire, fx, r }; h.buff is their merge (applyStats reads
		-- speed / damage / immobile of it). Only these keys exist - a buff never changes a weapon.
		local BUFF_SUM = { speed = true, damage = true, armor = true, regen = true }
		local BUFF_FLAG = { immobile = true, cloak = true }

		local function setCloak(unitID, h, on)
			if on == (h.cloaked or false) then
				return
			end
			h.cloaked = on
			-- the engine cloak needs a canCloak unitdef (unit_cloak.lua vetoes the rest): the enemies' line of
			-- sight to the hero is switched off instead (a radar blip stays, like a cloaked unit's)
			local myAlly = spGetUnitAllyTeam(unitID)
			for _, at in ipairs(Spring.GetAllyTeamList()) do
				if at ~= myAlly then
					if on then
						Spring.SetUnitLosState(unitID, at, { los = false, prevLos = false })
						Spring.SetUnitLosMask(unitID, at, { los = true, prevLos = true })
					else
						Spring.SetUnitLosMask(unitID, at, 0)
					end
				end
			end
			if on then
				local st = Spring.GetUnitStates(unitID)
				h.cloakFire = st and st.firestate or 2
				h.cloakFrom = frameNow()
				Spring.GiveOrderToUnit(unitID, CMD.FIRE_STATE, { 0 }, 0) -- holds fire: a shot would reveal it
			else
				Spring.GiveOrderToUnit(unitID, CMD.FIRE_STATE, { h.cloakFire or 2 }, 0)
			end
			spSetUnitRulesParam(unitID, "hero_cloaked", on and 1 or 0, ALLIED)
			local x, y, z = heroPos(unitID)
			ceg("hero-cloak", x, y, z)
		end

		local function mergeBuffs(unitID, h, f)
			local merged, expire, nextEnd = {}, 0, nil
			for key, e in pairs(h.buffs or {}) do
				if e.expire > f then
					expire = max(expire, e.expire)
					nextEnd = nextEnd and min(nextEnd, e.expire) or e.expire
					for k, v in pairs(e.fx) do
						v = val(v, e.r)
						if BUFF_SUM[k] then
							merged[k] = (merged[k] or 0) + v
						elseif k == "shieldRegen" then
							merged[k] = max(merged[k] or 1, v)
						elseif BUFF_FLAG[k] and v then
							merged[k] = true
						end
					end
					if e.trailDmg then
						merged.trailDmg = max(merged.trailDmg or 0, e.trailDmg)
					end
				else
					h.buffs[key] = nil
				end
			end
			if merged.armor then
				merged.armor = min(0.8, merged.armor)
			end
			h.buff = expire > f and { expire = expire, fx = merged } or nil
			h.buffNext = nextEnd
			setCloak(unitID, h, merged.cloak or false)
			applyStats(unitID, h)
		end

		local function addBuff(unitID, h, key, dur, fx, r, trailDmg)
			h.buffs = h.buffs or {}
			h.buffs[key] = { expire = frameNow() + floor(dur * GAME_SPEED), fx = fx or {}, r = r, trailDmg = trailDmg }
			mergeBuffs(unitID, h, frameNow())
		end

		local function endBuffs(unitID, h, flag)
			local changed = false
			for key, e in pairs(h.buffs or {}) do
				if e.fx[flag] then
					h.buffs[key] = nil
					changed = true
					spSetUnitRulesParam(unitID, "hero_on_" .. key, frameNow(), INLOS)
				end
			end
			if changed then
				mergeBuffs(unitID, h, frameNow())
			end
		end

		---------------------------------------------------------------- abilities: passives on hits

		local function critFx(a, victimID)
			local f = frameNow()
			if f - a.lastCrit > 8 then
				a.lastCrit = f
				local x, y, z = spGetUnitPosition(victimID)
				if x then
					ceg("hero-crit", x, y + 20, z)
				end
			end
		end

		-- crit / slayer of a hero's own hits (UnitPreDamaged)
		abilityAttackMult = function(a, victimID, victimDefID)
			local m = 1
			local b, r = learnedOf(a, "crit")
			if b and random() < val(b.chance, r) then
				m = m * val(b.mult, r)
				critFx(a, victimID)
			end
			b, r = learnedOf(a, "slayer")
			if b and (unitCost[victimDefID] or 0) >= (b.minCost or 10000) then
				m = m * (1 + val(b.mult, r))
			end
			return m
		end

		-- damage taken by a hero: bladestorm / buff armor, the absorb shield, undying (returns the new mult)
		abilityVictim = function(unitID, v, damage, m, paralyzer, f)
			if v.bladestorm and v.bladestorm.expire > f then
				m = m * (1 - v.bladestorm.armor)
			end
			local bf = v.buff and v.buff.expire > f and v.buff.fx
			if bf and bf.armor then
				m = m * (1 - bf.armor)
			end
			if paralyzer then
				return m
			end
			local ab = v.absorb
			if ab and ab.expire > f and ab.left > 0 then
				local eff = damage * m * (v.hpMult or 1)
				local take = min(ab.left, eff)
				ab.left = ab.left - take
				m = eff > 0 and m * (eff - take) / eff or m
				if f - (ab.fxFrame or 0) > 12 then
					ab.fxFrame = f
					local x, y, z = spGetUnitPosition(unitID)
					ceg("hero-shield-hit", x, y, z)
				end
				spSetUnitRulesParam(unitID, "hero_absorb", floor(ab.left), ALLIED)
			end
			local b, r, key = learnedOf(v, "undying")
			if b and v.undyingReady <= f then
				local hp = spGetUnitHealth(unitID)
				if hp and damage * m >= hp then
					local cd = val(b.cooldown, r) * max(0.4, 1 - (v.mods and v.mods.cdr or 0))
					v.undyingReady = f + floor(cd * GAME_SPEED)
					v.undyingUntil = f + 3 * GAME_SPEED
					spSetUnitRulesParam(unitID, "hero_ready_" .. key, v.undyingReady, ALLIED)
					spSetUnitRulesParam(unitID, "hero_cd_" .. key, floor(cd * GAME_SPEED), ALLIED)
					markActive(unitID, key, 3)
					local c = caster(unitID, v, key)
					local nova = novaOf(b, r) * c.power
					delayed[#delayed + 1] = { frame = f + 1, fn = function()
						if heroes[unitID] then
							local _, maxHp = spGetUnitHealth(unitID)
							spSetUnitHealth(unitID, maxHp * val(b.heal, r))
							local x, y, z = spGetUnitPosition(unitID)
							ceg("hero-undying", x, y, z)
							if nova > 0 then
								abilityFinale(c, x, z, nova, val(b.novaRadius, r) or 650, val(b.novaStun, r))
							end
							toUI("undying", unitID, r)
							alog("%s %s undying heal=%.2f nova=%d", c.name, key, val(b.heal, r), nova)
						end
					end }
					return 0
				end
			end
			return m
		end

		-- chain lightning from a hit target to the next enemies (proc_chain)
		local function chainFrom(c, wdid, fromID, dmg, jumps, radius)
			local x, y, z = spGetUnitPosition(fromID)
			if not x then
				return
			end
			local done = { [fromID] = true }
			local owner = ownerOf(c)
			abilityHurt(fromID, dmg, owner)
			ceg("hero-chain", x, y, z)
			local n = 1
			for _ = 1, jumps do
				local best, bestD
				for _, uid in ipairs(spGetUnitsInCylinder(x, z, radius)) do
					if not done[uid] and isEnemyOf(uid, c.ally) and not spGetUnitIsDead(uid) then
						local ux, _, uz = spGetUnitPosition(uid)
						local d = (ux - x) ^ 2 + (uz - z) ^ 2
						if not bestD or d < bestD then
							best, bestD = uid, d
						end
					end
				end
				if not best then
					break
				end
				done[best] = true
				local nx, ny, nz = spGetUnitPosition(best)
				boltVisual(c, wdid, x, y + 25, z, nx, ny + 25, nz, 6)
				abilityHurt(best, dmg, owner)
				ceg("hero-chain", nx, ny, nz)
				x, y, z = nx, ny, nz
				n = n + 1
			end
			alog("%s %s chain dmg=%d targets=%d", c.name, c.key, dmg, n)
		end

		local PROC_GAP = 10 -- frames between two rolls of a proc: a chance per shot, not per beam frame

		-- a hero's weapon hit an enemy (UnitDamaged): procs, and a hit ends its cloak
		abilityOnHit = function(attackerID, h, victimID)
			local f = frameNow()
			if h.cloaked and f - (h.cloakFrom or 0) > GAME_SPEED then -- shots fired before the cloak do not count
				endBuffs(attackerID, h, "cloak")
			end
			local b, r, key = learnedOf(h, "proc_chain")
			if b and (h.procChain or 0) <= f then
				h.procChain = f + PROC_GAP
				if random() < val(b.chance, r) then
					local c = caster(attackerID, h, key)
					chainFrom(c, abilityWeapon(h, b, "chain"), victimID, val(b.dmg, r) * c.power, val(b.jumps, r), val(b.radius, r) or 450)
				end
			end
			b, r, key = learnedOf(h, "proc_blast")
			if b and (h.procBlast or 0) <= f then
				h.procBlast = f + PROC_GAP
				if random() < val(b.chance, r) then
					local c = caster(attackerID, h, key)
					local x, y, z = spGetUnitPosition(victimID)
					if x then
						local rad = val(b.radius, r) or 200
						local hit = abilityBlast(c, x, z, rad, val(b.dmg, r) * c.power)
						ceg(b.fx or "hero-blast", x, y, z)
						alog("%s %s blast dmg=%d radius=%d hit=%d", c.name, key, val(b.dmg, r) * c.power, rad, #hit)
					end
				end
			end
		end

		---------------------------------------------------------------- abilities: casts

		cast = {}
		dashes = {} -- unitID -> dash in progress (moved every frame)

		local function castFx(name, unitID)
			local x, y, z = heroPos(unitID)
			ceg(name, x, y, z)
		end

		cast.active_buff = function(unitID, h, key, b, r)
			local dur = val(b.duration, r)
			addBuff(unitID, h, key, dur, b.buff, r, b.trailDmg and val(b.trailDmg, r) * abilityPower(h))
			markActive(unitID, key, dur)
			castFx(b.fx or "hero-buff-power", unitID)
			return true
		end

		cast.active_guard = function(unitID, h, key, b, r)
			local dur = val(b.duration, r)
			events[#events + 1] = { kind = "guard", owner = unitID, expire = frameNow() + floor(dur * GAME_SPEED),
				radius = val(b.radius, r), mult = 1 - val(b.reduce, r), fx = b.tickFx or "hero-guard" }
			markActive(unitID, key, dur)
			castFx(b.fx or "hero-guard-cast", unitID)
			return true
		end

		cast.active_dome = function(unitID, h, key, b, r)
			local dur = val(b.duration, r)
			events[#events + 1] = { kind = "dome", owner = unitID, expire = frameNow() + floor(dur * GAME_SPEED),
				radius = val(b.radius, r), fx = b.tickFx or "hero-dome" }
			markActive(unitID, key, dur)
			castFx(b.fx or "hero-dome-cast", unitID)
			return true
		end

		local function novaFx(b, r)
			if (val(b.dmg, r) or 0) <= 0 and (val(b.heal, r) or 0) > 0 then
				return "hero-nova-heal"
			elseif (val(b.emp, r) or 0) > 0 or b.shieldRatio then
				return "hero-nova-emp"
			end
			return "hero-nova-kinetic"
		end

		cast.active_nova = function(unitID, h, key, b, r)
			local x, y, z = heroPos(unitID)
			local c = caster(unitID, h, key)
			local rad = val(b.radius, r)
			local dmg = val(b.dmg, r) or 0
			local num = h.def.shieldNum
			if b.shieldRatio and num then
				-- dumps half of the shield charge into the blast
				local _, charge = Spring.GetUnitShieldState(unitID, num)
				if charge and charge > 0 then
					Spring.SetUnitShieldState(unitID, num, true, charge * 0.5)
					dmg = dmg + charge * 0.5 * val(b.shieldRatio, r)
				end
			end
			local hit = abilityBlast(c, x, z, rad, dmg * c.power, val(b.stun, r), (val(b.emp, r) or 0) * c.power)
			local heal = (val(b.heal, r) or 0) * c.power
			local healed = 0
			if heal > 0 then
				healed = healAllies(c, x, z, rad, heal, "hero-heal-spark")
			end
			ceg(b.fx or novaFx(b, r), x, y, z)
			alog("%s %s nova dmg=%d radius=%d stun=%s hit=%d healed=%d", c.name, key, dmg * c.power, rad, tostring(val(b.stun, r)), #hit, healed)
			return true
		end

		-- a point of the area: most shots go for an enemy in it
		local function pickPoint(c, cx, cz, radius, bias)
			if random() < bias then
				local list = enemiesIn(cx, cz, radius, c.ally)
				if #list > 0 then
					local x, _, z = spGetUnitPosition(list[random(#list)])
					if x then
						return x + (random() - 0.5) * 60, z + (random() - 0.5) * 60
					end
				end
			end
			return randomPointIn(cx, cz, radius)
		end

		-- from the sky: height, horizontal offset of the start, frames to land
		local SKY = {
			meteor = { h = 2400, ox = -700, oz = -300, t = 60 },
			star = { h = 2800, ox = 500, oz = -650, t = 75 },
			shell = { h = 3600, ox = 90, oz = 60, t = 38 },
			missile = { h = 3000, ox = 0, oz = 0, t = 70 },
			nuke = { h = 4200, ox = 0, oz = 0, t = 95 },
		}
		local DEFAULT_AOE = { meteor = 220, star = 280, shell = 220, missile = 160, nuke = 380, bolt = 150 }
		local IMPACT_FX = { bolt = "hero-impact-bolt" }

		local function skyShot(c, wdid, proj, x, z, shot)
			local s = SKY[proj] or SKY.meteor
			local y = spGetGroundHeight(x, z)
			local pid = spawnAb(wdid, c, x + s.ox, y + s.h, z + s.oz, -s.ox / s.t, -s.h / s.t, -s.oz / s.t)
			if pid then
				shots[pid] = shot
				if proj == "missile" or proj == "nuke" then
					Spring.SetProjectileTarget(pid, x, y, z)
				end
			end
		end

		-- launched from the hero, arcing over onto a point or a unit; returns the frames it needs
		local function heroShot(c, wdid, fromID, tx, tz, targetID, shot)
			local x, y, z = spGetUnitPosition(fromID)
			if not x or not wdid then
				return 60
			end
			local ty = spGetGroundHeight(tx, tz)
			local dx, dz = tx - x, tz - z
			local d = max(1, sqrt(dx * dx + dz * dz))
			local pid = spawnAb(wdid, c, x + (random() - 0.5) * 70, y + 90, z + (random() - 0.5) * 70,
				dx / d * 4 + (random() - 0.5) * 4, 10 + random() * 4, dz / d * 4 + (random() - 0.5) * 4)
			if pid then
				if targetID then
					Spring.SetProjectileTarget(pid, targetID, string.byte("u"))
				else
					Spring.SetProjectileTarget(pid, tx, ty, tz)
				end
				shots[pid] = shot
			end
			local speed = WeaponDefs[wdid].projectilespeed or 25
			return floor(d / max(5, speed * 0.75)) + 35
		end

		cast.active_barrage = function(unitID, h, key, b, r, tx, tz)
			if not tx then
				return false
			end
			local c = caster(unitID, h, key)
			local proj = b.projectile or "meteor"
			local wdid = abilityWeapon(h, b, proj)
			local count = val(b.count, r)
			local dur = val(b.duration, r) or 4
			local radius = val(b.radius, r) or 500
			local from = b.from or ((proj == "missile" or proj == "nuke") and "hero" or "sky")
			local f = frameNow()
			local shot = { c = c, dmg = (val(b.dmg, r) or 0) * c.power, aoe = val(b.aoe, r) or DEFAULT_AOE[proj] or 200,
				stun = val(b.stun, r), emp = (val(b.emp, r) or 0) * c.power, fx = b.impactFx or IMPACT_FX[proj],
				expire = f + floor(dur * GAME_SPEED) + 900 }
			local last = f
			for i = 1, count do
				local at = f + 1 + floor((i - 1) * dur * GAME_SPEED / max(1, count))
				local travel = proj == "bolt" and 0 or (from == "sky" and (SKY[proj] or SKY.meteor).t or 90)
				last = max(last, at + travel)
				delayed[#delayed + 1] = { frame = at, fn = function()
					local x, z = pickPoint(c, tx, tz, radius, b.bias or 0.6)
					x = max(16, min(Game.mapSizeX - 16, x))
					z = max(16, min(Game.mapSizeZ - 16, z))
					if proj == "bolt" then
						local y = spGetGroundHeight(x, z)
						boltVisual(c, wdid, x + random(-220, 220), y + 1700, z + random(-220, 220), x, y + 5, z, 8)
						abilityImpact(shot, x, z)
					elseif from == "sky" then
						skyShot(c, wdid, proj, x, z, shot)
					elseif spValidUnitID(unitID) and not spGetUnitIsDead(unitID) then
						heroShot(c, wdid, unitID, x, z, nil, shot)
					end
				end }
			end
			if from == "hero" then
				local x, _, z = heroPos(unitID)
				if x then
					local d = sqrt((tx - x) ^ 2 + (tz - z) ^ 2)
					last = last + floor(d / 18)
				end
				castFx("hero-missile-launch", unitID)
			end
			local nova = novaOf(b, r) * c.power
			if nova > 0 then
				delayed[#delayed + 1] = { frame = last + 12, fn = function()
					abilityFinale(c, tx, tz, nova, val(b.novaRadius, r) or max(450, radius * 0.85), val(b.novaStun, r), b.novaFx)
				end }
			end
			ceg(b.targetFx or "hero-target", tx, spGetGroundHeight(tx, tz), tz)
			markActive(unitID, key, dur)
			alog("%s %s barrage %s x%d dmg=%d aoe=%d radius=%d nova=%d", c.name, key, proj, count, shot.dmg, shot.aoe, radius, nova)
			return true
		end

		cast.active_beam = function(unitID, h, key, b, r, tx, tz)
			if not tx then
				return false
			end
			local c = caster(unitID, h, key)
			local dur = val(b.duration, r) or 6
			local nova = novaOf(b, r) * c.power
			events[#events + 1] = { kind = "beam", owner = unitID, free = true, c = c, x = tx, z = tz,
				expire = frameNow() + floor(dur * GAME_SPEED), radius = val(b.radius, r), tick = val(b.tick, r) * c.power,
				drift = val(b.drift, r) or 0, fx = b.fx or "hero-sunbeam", hits = 0,
				finale = nova > 0 and { dmg = nova, radius = val(b.novaRadius, r) or 600, stun = val(b.novaStun, r), fx = b.novaFx } or nil }
			ceg(b.startFx or "hero-sunbeam-start", tx, spGetGroundHeight(tx, tz), tz)
			markActive(unitID, key, dur)
			alog("%s %s beam tick=%d radius=%d duration=%d", c.name, key, val(b.tick, r) * c.power, val(b.radius, r), dur)
			return true
		end

		cast.active_spear = function(unitID, h, key, b, r, tx, tz, targetID)
			if not targetID or not spValidUnitID(targetID) or spGetUnitIsDead(targetID) then
				return false
			end
			local c = caster(unitID, h, key)
			if spGetUnitAllyTeam(targetID) == c.ally then
				return false
			end
			local x, y, z = heroPos(unitID)
			local ex, ey, ez = spGetUnitPosition(targetID)
			local dx, dy, dz = ex - x, ey - y, ez - z
			local d = max(1, sqrt(dx * dx + dy * dy + dz * dz))
			if d > val(b.range, r) * 1.05 then
				return false
			end
			local wdid = abilityWeapon(h, b, "spear")
			local speed = wdid and WeaponDefs[wdid].projectilespeed or 120
			if wdid then
				spawnAb(wdid, c, x, y + 60, z, dx / d * speed, (dy - 40) / d * speed, dz / d * speed)
			end
			ceg("hero-pierce-big", x, y + 60, z)
			local pct = val(b.pct, r) or 0
			local flat = (val(b.flat, r) or 0) * c.power
			local line = (val(b.line, r) or 0) * c.power
			local nova = novaOf(b, r) * c.power
			delayed[#delayed + 1] = { frame = frameNow() + floor(d / speed) + 1, fn = function()
				-- everything on the line between the hero and the target
				local hitLine = {}
				local n = 0
				local len = sqrt(dx * dx + dz * dz)
				for s = 0, len, 100 do
					local px, pz = x + dx / max(1, len) * s, z + dz / max(1, len) * s
					for _, uid in ipairs(enemiesIn(px, pz, 110, c.ally)) do
						if uid ~= targetID and not hitLine[uid] then
							hitLine[uid] = true
							n = n + 1
							abilityHurt(uid, line, ownerOf(c))
						end
					end
				end
				local total = 0
				if spValidUnitID(targetID) and not spGetUnitIsDead(targetID) then
					local _, maxHp = spGetUnitHealth(targetID)
					local vh = heroes[targetID]
					total = (maxHp or 0) * (vh and vh.hpMult or 1) * pct + flat
					abilityHurt(targetID, total, ownerOf(c))
					ex, ey, ez = spGetUnitPosition(targetID)
				end
				ceg(b.impactFx or "hero-spear-hit", ex, ey, ez)
				if nova > 0 then
					abilityFinale(c, ex, ez, nova, val(b.novaRadius, r) or 600, val(b.novaStun, r), b.novaFx)
				end
				alog("%s %s spear target dmg=%d (%.0f%% + %d) line=%d x%d", c.name, key, total, pct * 100, flat, line, n)
			end }
			return true
		end

		cast.active_dash = function(unitID, h, key, b, r, tx, tz)
			if not tx or dashes[unitID] then
				return false
			end
			local x, y, z = heroPos(unitID)
			local dx, dz = tx - x, tz - z
			local d = sqrt(dx * dx + dz * dz)
			if d < 60 then
				return false
			end
			local range = val(b.range, r)
			if d > range then
				dx, dz, d = dx / d * range, dz / d * range, range
			end
			local steps = max(4, floor(d / (b.speed or 55)))
			local c = caster(unitID, h, key)
			dashes[unitID] = { c = c, x0 = x, z0 = z, dx = dx / steps, dz = dz / steps, step = 0, steps = steps,
				dmg = (val(b.dmg, r) or 0) * c.power, radius = val(b.radius, r) or 200, stun = val(b.stun, r), hit = {}, n = 0,
				burn = (val(b.burn, r) or 0) * c.power, burnTime = b.burnTime or 4, fireAt = 0, trail = b.trailFx or "hero-dash-trail" }
			ceg(b.fx or "hero-dash", x, y, z)
			markActive(unitID, key, steps / GAME_SPEED + 0.3)
			return true
		end

		cast.active_bladestorm = function(unitID, h, key, b, r)
			local dur = val(b.duration, r)
			local c = caster(unitID, h, key)
			h.bladestorm = { expire = frameNow() + floor(dur * GAME_SPEED), armor = val(b.armor, r) or 0 }
			events[#events + 1] = { kind = "bladestorm", owner = unitID, expire = h.bladestorm.expire, c = c,
				radius = val(b.radius, r), dmg = val(b.dmg, r) * c.power, fx = b.fx or "hero-bladestorm" }
			markActive(unitID, key, dur)
			alog("%s %s bladestorm dmg=%d per 0.2 s radius=%d", c.name, key, val(b.dmg, r) * c.power, val(b.radius, r))
			return true
		end

		cast.active_summon = function(unitID, h, key, b, r)
			local ud = UnitDefNames[b.unit or ""]
			if not ud then
				return false
			end
			local x, y, z = heroPos(unitID)
			local n = val(b.count, r)
			local dur = val(b.duration, r)
			local expire = frameNow() + floor(dur * GAME_SPEED)
			local made = 0
			for i = 1, n do
				local a = i / n * 6.283 + random() * 0.5
				local sx = max(64, min(Game.mapSizeX - 64, x + math.cos(a) * (b.spread or 280)))
				local sz = max(64, min(Game.mapSizeZ - 64, z + math.sin(a) * (b.spread or 280)))
				local uid = Spring.CreateUnit(ud.id, sx, spGetGroundHeight(sx, sz), sz, random(0, 3), h.team)
				if uid then
					made = made + 1
					summoned[uid] = { owner = unitID, expire = expire }
					spSetUnitRulesParam(uid, "hero_summon_expire", expire, ALLIED)
					Spring.GiveOrderToUnit(uid, CMD.GUARD, { unitID }, 0)
					ceg(b.fx or "hero-summon", sx, spGetGroundHeight(sx, sz), sz)
				end
			end
			markActive(unitID, key, dur)
			alog("%s %s summon %s x%d for %d s", h.def.name, key, b.unit, made, dur)
			return made > 0
		end

		cast.active_missiles = function(unitID, h, key, b, r)
			local x, y, z = heroPos(unitID)
			local c = caster(unitID, h, key)
			local targets = {}
			for _, uid in ipairs(enemiesIn(x, z, val(b.radius, r), c.ally)) do
				if seenBy(uid, c.ally) then
					targets[#targets + 1] = { uid = uid, value = costOf(uid) * (heroes[uid] and 3 or 1) }
				end
			end
			if #targets == 0 then
				return false
			end
			table.sort(targets, function(p, q) return p.value > q.value end)
			local n = val(b.count, r)
			local wdid = abilityWeapon(h, b, "missile")
			local shot = { c = c, dmg = val(b.dmg, r) * c.power, aoe = val(b.aoe, r) or 150, stun = val(b.stun, r),
				emp = (val(b.emp, r) or 0) * c.power, fx = b.impactFx, expire = frameNow() + 900 }
			for i = 1, n do
				local t = targets[(i - 1) % #targets + 1].uid
				delayed[#delayed + 1] = { frame = frameNow() + 1 + (i - 1) * 2, fn = function()
					if spValidUnitID(unitID) and not spGetUnitIsDead(unitID) and spValidUnitID(t) then
						local tx, _, tz = spGetUnitPosition(t)
						heroShot(c, wdid, unitID, tx, tz, t, shot)
					end
				end }
			end
			ceg(b.fx or "hero-missile-launch", x, y, z)
			alog("%s %s missiles x%d dmg=%d aoe=%d targets=%d", c.name, key, n, shot.dmg, shot.aoe, #targets)
			return true
		end

		cast.active_repair = function(unitID, h, key, b, r)
			local x, y, z = heroPos(unitID)
			local c = caster(unitID, h, key)
			local heal = val(b.heal, r) * c.power
			local n, total = healAllies(c, x, z, val(b.radius, r), heal, "hero-heal-spark")
			ceg(b.fx or "hero-nova-heal", x, y, z)
			alog("%s %s repair heal=%d radius=%d units=%d", c.name, key, heal, val(b.radius, r), n)
			return true
		end

		cast.active_cloak = function(unitID, h, key, b, r)
			local dur = val(b.duration, r)
			addBuff(unitID, h, key, dur, { cloak = true, speed = b.speed }, r)
			markActive(unitID, key, dur)
			alog("%s %s cloak %d s cloaked=%s", h.def.name, key, dur, tostring(Spring.GetUnitIsCloaked(unitID)))
			return true
		end

		cast.active_shield = function(unitID, h, key, b, r)
			local dur = val(b.duration, r)
			local amount = val(b.absorb, r) * abilityPower(h)
			h.absorb = { left = amount, expire = frameNow() + floor(dur * GAME_SPEED), key = key }
			spSetUnitRulesParam(unitID, "hero_absorb", floor(amount), ALLIED)
			markActive(unitID, key, dur)
			castFx(b.fx or "hero-shield", unitID)
			alog("%s %s shield absorb=%d for %d s", h.def.name, key, amount, dur)
			return true
		end

		-- cast an ability now; tx/tz/targetID for targeted ones. Returns true when it went off.
		function tryCast(unitID, h, key, tx, tz, targetID)
			local b = h.def.cfg[key]
			if not b or not cast[b.kind] or not abilityReady(h, key) then
				return false
			end
			local r = rankOf(h, key)
			if not cast[b.kind](unitID, h, key, b, r, tx, tz, targetID) then
				return false
			end
			startCooldown(unitID, h, key, b, r)
			alog("%s %s cast %s rank %d", h.def.name, key, b.kind, r)
			toUI("cast", unitID, r, key == "a1" and 4 or (key == "a2" and 5 or 6)) -- index in H.branchOrder
			return true
		end

		function castRange(b, r)
			if b.kind == "active_dash" then
				return 1e6 -- a dash goes as far as it can toward the point
			end
			return val(b.range, r) or 0
		end

		---------------------------------------------------------------- abilities: timed effects

		local function fireAt(c, x, z, dps, seconds)
			events[#events + 1] = { kind = "fire", owner = c.owner, free = true, c = c, x = x, z = z, radius = 150,
				dmg = dps * 0.2, expire = frameNow() + floor(seconds * GAME_SPEED) }
			ceg("hero-firepatch", x, spGetGroundHeight(x, z), z)
		end

		-- every 6 frames: beams, bladestorms, fire on the ground, burning trails
		function processEvents(f)
			local keep = {}
			for _, e in ipairs(events) do
				local h = heroes[e.owner]
				if e.expire > f and (h or e.free) then
					keep[#keep + 1] = e
					if e.kind == "beam" then
						if e.drift > 0 then
							-- the beam creeps toward the enemies around it
							local sx, sz, sw = 0, 0, 0
							for _, uid in ipairs(enemiesIn(e.x, e.z, e.radius * 2.5, e.c.ally)) do
								local ux, _, uz = spGetUnitPosition(uid)
								local w = costOf(uid) + 1
								sx, sz, sw = sx + ux * w, sz + uz * w, sw + w
							end
							if sw > 0 then
								local dx, dz = sx / sw - e.x, sz / sw - e.z
								local d = sqrt(dx * dx + dz * dz)
								local step = min(d, e.drift * 0.2)
								if d > 1 then
									e.x, e.z = e.x + dx / d * step, e.z + dz / d * step
								end
							end
						end
						ceg(e.fx, e.x, spGetGroundHeight(e.x, e.z), e.z)
						e.hits = e.hits + #abilityBlast(e.c, e.x, e.z, e.radius, e.tick)
					elseif e.kind == "bladestorm" and h then
						local x, y, z = heroPos(e.owner)
						abilityBlast(e.c, x, z, e.radius, e.dmg)
						ceg(e.fx, x, y, z)
					elseif e.kind == "fire" then
						abilityBlast(e.c, e.x, e.z, e.radius, e.dmg)
						if f % 30 < 6 then
							ceg("hero-firepatch", e.x, spGetGroundHeight(e.x, e.z), e.z)
						end
					end
				elseif e.finale then
					local fin = e.finale
					e.finale = nil
					alog("%s %s beam done hits=%d", e.c.name, e.c.key, e.hits or 0)
					delayed[#delayed + 1] = { frame = f + 20, fn = function()
						abilityFinale(e.c, e.x, e.z, fin.dmg, fin.radius, fin.stun, fin.fx)
					end }
				end
			end
			events = keep

			-- burning trails of self buffs (active_buff trailDmg)
			for unitID, h in pairs(heroes) do
				local bf = h.buff and h.buff.expire > f and h.buff.fx
				if bf and bf.trailDmg then
					local x, y, z = heroPos(unitID)
					if x and (not h.trailX or (x - h.trailX) ^ 2 + (z - h.trailZ) ^ 2 > 140 * 140) then
						h.trailX, h.trailZ = x, z
						fireAt(caster(unitID, h, h.buffs and next(h.buffs) or "a2"), x, z, bf.trailDmg, 4)
					end
				end
			end
		end

		-- guard / dome sets, every 0.5 s
		function refreshProtection(f)
			for k in pairs(guardMult) do
				guardMult[k] = nil
			end
			for k in pairs(invuln) do
				invuln[k] = nil
			end
			for _, e in ipairs(events) do
				if (e.kind == "guard" or e.kind == "dome") and e.expire > f and heroes[e.owner] then
					local x, y, z = heroPos(e.owner)
					if x then
						local ally = spGetUnitAllyTeam(e.owner)
						for _, uid in ipairs(alliesIn(x, z, e.radius, ally)) do
							if e.kind == "dome" then
								invuln[uid] = true
							else
								guardMult[uid] = min(guardMult[uid] or 1, e.mult)
							end
						end
						if f % 30 < 15 then
							ceg(e.fx, x, y, z)
						end
					end
				end
			end
		end

		-- every frame: dashes; summons that run out; shots that never exploded
		function abilityFrame(f)
			for i = #exploded, 1, -1 do
				abProj[exploded[i]] = nil
				exploded[i] = nil
			end
			for unitID, d in pairs(dashes) do
				if not spValidUnitID(unitID) or spGetUnitIsDead(unitID) then
					dashes[unitID] = nil
				else
					d.step = d.step + 1
					local nx = max(64, min(Game.mapSizeX - 64, d.x0 + d.dx * d.step))
					local nz = max(64, min(Game.mapSizeZ - 64, d.z0 + d.dz * d.step))
					Spring.SetUnitPosition(unitID, nx, nz)
					local ny = spGetGroundHeight(nx, nz)
					for _, uid in ipairs(enemiesIn(nx, nz, d.radius, d.c.ally)) do
						if not d.hit[uid] then
							d.hit[uid] = true
							d.n = d.n + 1
							abilityHurt(uid, d.dmg, unitID)
							if d.stun and d.stun > 0 then
								abilityStun(uid, d.stun, unitID)
							end
						end
					end
					if d.step % 2 == 0 then
						ceg(d.trail, nx, ny, nz)
					end
					if d.burn > 0 and d.step >= d.fireAt then
						d.fireAt = d.step + max(1, floor(140 / max(1, sqrt(d.dx * d.dx + d.dz * d.dz))))
						fireAt(d.c, nx, nz, d.burn, d.burnTime)
					end
					if d.step >= d.steps then
						dashes[unitID] = nil
						ceg("hero-dash", nx, ny, nz)
						alog("%s %s dash dmg=%d radius=%d hit=%d burn=%d", d.c.name, d.c.key, d.dmg, d.radius, d.n, d.burn)
					end
				end
			end
			if f % 15 == 4 then
				for uid, s in pairs(summoned) do
					if s.expire <= f then
						summoned[uid] = nil
						if spValidUnitID(uid) and not spGetUnitIsDead(uid) then
							local x, y, z = spGetUnitPosition(uid)
							ceg("hero-unsummon", x, y, z)
							Spring.DestroyUnit(uid, false, true)
						end
					end
				end
			end
			if f % 300 == 17 then
				for pid, s in pairs(shots) do
					if s.expire <= f then
						shots[pid] = nil
					end
				end
				for pid, e in pairs(abProj) do
					if e <= f then
						abProj[pid] = nil
					end
				end
			end
		end

		abilityUnitDestroyed = function(unitID)
			auraArmor[unitID] = nil
			slowed[unitID] = nil
			dashes[unitID] = nil
			local s = summoned[unitID]
			summoned[unitID] = nil
			return s ~= nil
		end

		---------------------------------------------------------------- abilities: passives, every second

		local AURA_FX = { aura_heal = "hero-aura-heal", aura_damage = "hero-aura-command", aura_armor = "hero-aura-armor", aura_slow = "hero-aura-slow" }
		local slowWant = {}

		function abilityPassivesBegin()
			for k in pairs(auraArmor) do
				auraArmor[k] = nil
			end
			for k in pairs(slowWant) do
				slowWant[k] = nil
			end
		end

		-- self buffs that ran out, buff regeneration, the absorb shield
		function abilityBuffTick(unitID, h, f, x, y, z)
			if h.buffNext and h.buffNext <= f then
				mergeBuffs(unitID, h, f)
			end
			local bf = h.buff and h.buff.expire > f and h.buff.fx
			if bf and bf.regen then
				healUnit(unitID, bf.regen)
			end
			if bf and not bf.cloak and f % 60 < 30 then -- a cloaked hero shows nothing
				ceg(bf.armor and "hero-buff-armor" or (bf.speed and "hero-buff-speed" or "hero-buff-power"), x, y, z)
			end
			local ab = h.absorb
			if ab then
				if ab.expire <= f or ab.left <= 0 then
					h.absorb = nil
					spSetUnitRulesParam(unitID, "hero_absorb", 0, ALLIED)
					spSetUnitRulesParam(unitID, "hero_on_" .. ab.key, f, INLOS)
				else
					ceg("hero-shield-tick", x, y, z)
				end
			end
		end

		function abilityAuras(unitID, h, f, x, y, z, ally, healBest)
			local p = abilityPower(h)
			for _, key in ipairs(ABILITY_KEYS) do
				local b = h.def.cfg[key]
				local r = rankOf(h, key)
				if b and r > 0 then
					local k = b.kind
					local rad = val(b.radius, r)
					if AURA_FX[k] and f % 60 < 30 then
						ceg(b.fx or AURA_FX[k], x, y, z)
					end
					if k == "aura_heal" then
						local rate = val(b.rate, r) * p
						for _, uid in ipairs(alliesIn(x, z, rad, ally)) do
							local v = uid == unitID and rate * 0.5 or rate
							if (healBest[uid] or 0) < v then
								healBest[uid] = v
							end
						end
					elseif k == "aura_damage" then
						for _, uid in ipairs(alliesIn(x, z, rad, ally)) do
							if uid ~= unitID then
								auraDamage[uid] = max(auraDamage[uid] or 0, val(b.mult, r))
							end
						end
					elseif k == "aura_armor" then
						for _, uid in ipairs(alliesIn(x, z, rad, ally)) do
							if uid ~= unitID then
								auraArmor[uid] = max(auraArmor[uid] or 0, val(b.reduce, r))
							end
						end
					elseif k == "aura_burn" then
						local c = caster(unitID, h, key)
						local hit = abilityBlast(c, x, z, rad, val(b.dps, r) * p)
						for _ = 1, min(4, 1 + #hit) do
							local px, pz = randomPointIn(x, z, rad * 0.9)
							ceg(b.fx or "hero-firepatch", px, spGetGroundHeight(px, pz), pz)
						end
					elseif k == "aura_emp" and f % (floor((b.period or 2) * GAME_SPEED)) < GAME_SPEED then
						local c = caster(unitID, h, key)
						local hit = abilityBlast(c, x, z, rad, (val(b.dmg, r) or 0) * p, nil, (val(b.emp, r) or 0) * p)
						for i = 1, min(6, #hit) do
							local ux, uy, uz = spGetUnitPosition(hit[i])
							ceg("hero-static", ux, uy, uz)
						end
					elseif k == "aura_slow" then
						local s = val(b.slow, r)
						local hit = enemiesIn(x, z, rad, ally)
						for i, uid in ipairs(hit) do
							slowWant[uid] = max(slowWant[uid] or 0, s)
							if i <= 6 and f % 60 < 30 then
								local ux, uy, uz = spGetUnitPosition(uid)
								ceg("hero-slow", ux, uy, uz)
							end
						end
					end
				end
			end
		end

		-- shield capacity (shield_cap) and shield recharge boosts (buff shieldRegen)
		function abilityShield(unitID, h)
			local num = h.def.shieldNum
			if not num then
				return
			end
			local _, charge = Spring.GetUnitShieldState(unitID, num)
			if not charge then
				return
			end
			local cap, regenMult = h.def.shieldPower, 1
			for _, key in ipairs(ABILITY_KEYS) do
				local b = h.def.cfg[key]
				if b and b.kind == "shield_cap" then
					local r = rankOf(h, key)
					cap = h.def.shieldPower * (r > 0 and val(b.cap, r) or b.base or 1)
					regenMult = r > 0 and val(b.regen, r) or 1
				end
			end
			if h.buff and h.buff.fx.shieldRegen then
				regenMult = regenMult * h.buff.fx.shieldRegen
			end
			local p = min(cap, charge + h.def.shieldRegen * (regenMult - 1))
			if p ~= charge then
				Spring.SetUnitShieldState(unitID, num, true, p)
			end
		end

		-- speed of a unit under aura_slow (ground units; heroes keep their grown speed)
		local function setSlow(uid, s)
			local ud = UnitDefs[spGetUnitDefID(uid) or -1]
			if not ud or ud.canFly or (ud.speed or 0) <= 0 then
				return
			end
			local h = heroes[uid]
			local base = h and (Spring.GetUnitRulesParam(uid, "hero_speed") or ud.speed) or ud.speed
			local spd = base * (1 - s)
			pcall(Spring.MoveCtrl.SetGroundMoveTypeData, uid, { maxSpeed = spd, maxWantedSpeed = spd })
		end

		function abilityPassivesEnd()
			for uid, s in pairs(slowWant) do
				if spValidUnitID(uid) and not spGetUnitIsDead(uid) then
					setSlow(uid, s)
					slowed[uid] = s
				end
			end
			for uid in pairs(slowed) do
				if not slowWant[uid] then
					slowed[uid] = nil
					if spValidUnitID(uid) and not spGetUnitIsDead(uid) then
						if heroes[uid] then
							applyStats(uid, heroes[uid])
						else
							setSlow(uid, 0)
						end
					end
				end
			end
		end
	end

	---------------------------------------------------------------- passives, every second

	local function fountainNear(teamID, x, z)
		for _, uid in ipairs(spGetUnitsInCylinder(x, z, H.FOUNTAIN_RADIUS, teamID)) do
			if foundryDefs[spGetUnitDefID(uid)] then
				local _, _, _, _, bp = spGetUnitHealth(uid)
				if bp and bp >= 1 then
					return true
				end
			end
		end
		return false
	end

	local function passives(f)
		for k in pairs(auraDamage) do
			auraDamage[k] = nil
		end
		abilityPassivesBegin()
		local healBest = {}
		for unitID, h in pairs(heroes) do
			local x, y, z = heroPos(unitID)
			if x then
				local ally = spGetUnitAllyTeam(unitID)
				local cfg = h.def.cfg
				local hp, maxHp = spGetUnitHealth(unitID)
				-- self buffs that ran out, buff regeneration, the absorb shield
				abilityBuffTick(unitID, h, f, x, y, z)
				-- own regeneration: plating + the fountain at its foundry
				local regen = h.regen or 0
				if fountainNear(h.team, x, z) then
					regen = regen + H.FOUNTAIN_REGEN
				end
				if f - (h.lastHit or 0) > H.REST_DELAY * GAME_SPEED then
					regen = regen + H.REST_REGEN
				end
				if regen > 0 and hp and hp < maxHp then
					spSetUnitHealth(unitID, min(maxHp, hp + maxHp * regen))
				end
				-- auras of the abilities
				abilityAuras(unitID, h, f, x, y, z, ally, healBest)
				-- item aura (Warlord's Banner) and the Crown of Storms
				local m = h.mods or {}
				if m.aura then
					for _, uid in ipairs(alliesIn(x, z, m.aura.radius, ally)) do
						if uid ~= unitID then
							auraDamage[uid] = max(auraDamage[uid] or 0, m.aura.damage)
						end
					end
				end
				if m.zap and f % (m.zap.period * GAME_SPEED) < GAME_SPEED then
					local target = Spring.GetUnitNearestEnemy(unitID, m.zap.radius, true)
					if target then
						local tx, ty, tz = spGetUnitPosition(target)
						ceg("hero-zap", tx, ty, tz)
						spAddUnitDamage(target, m.zap.damage * h.dmgMult, 0, unitID)
					end
				end
				-- shield capacity (shield_cap) and shield recharge boosts (buff shieldRegen)
				abilityShield(unitID, h)
			end
		end
		for uid, rate in pairs(healBest) do
			healUnit(uid, rate)
		end
		abilityPassivesEnd()
	end

	---------------------------------------------------------------- autocast (AI always, players with autocast on)

	local autocast
	do
		local visibleTo = seenBy

		-- the enemy spot within range with the most metal around it
		local function bestCluster(x, z, range, radius, ally)
			local cands = {}
			for _, uid in ipairs(spGetUnitsInCylinder(x, z, range)) do
				if isEnemyOf(uid, ally) and visibleTo(uid, ally) then
					cands[#cands + 1] = uid
				end
			end
			local best, bx, bz = 0
			local step = max(1, floor(#cands / 30))
			for i = 1, #cands, step do
				local cx, _, cz = spGetUnitPosition(cands[i])
				if cx then
					local sum = 0
					for _, uid in ipairs(enemiesIn(cx, cz, radius, ally)) do
						sum = sum + costOf(uid) * (heroes[uid] and 2 or 1)
					end
					if sum > best then
						best, bx, bz = sum, cx, cz
					end
				end
			end
			return best, bx, bz
		end

		local function mostValuableEnemy(x, z, range, ally)
			local best, bestID = 0
			for _, uid in ipairs(spGetUnitsInCylinder(x, z, range)) do
				if isEnemyOf(uid, ally) and visibleTo(uid, ally) then
					local c = costOf(uid)
					if heroes[uid] then
						c = c * 3
					end
					if c > best then
						best, bestID = c, uid
					end
				end
			end
			return bestID, best
		end

		local function enemyCostNear(x, z, r, ally)
			local sum, n = 0, 0
			for _, uid in ipairs(enemiesIn(x, z, r, ally)) do
				sum = sum + costOf(uid)
				n = n + 1
			end
			return sum, n
		end

		-- missing health of allies around (effective HP)
		local function alliedDamage(x, z, r, ally)
			local sum = 0
			for _, uid in ipairs(alliesIn(x, z, r, ally)) do
				local hp, maxHp, _, _, bp = spGetUnitHealth(uid)
				if hp and bp and bp >= 1 then
					local v = heroes[uid]
					sum = sum + (maxHp - hp) * (v and v.hpMult or 1)
				end
			end
			return sum
		end

		local function weaponReach(h)
			local reach = 0
			for _, w in pairs(h.def.weapons) do
				reach = max(reach, w.range)
			end
			return max(reach, 400)
		end

		local AUTO_MIN = 2500 -- metal of enemies that justifies an area ability
		local AUTO_ULT = 4000 -- ... an area ultimate

		function autocast(unitID, h)
			local x, y, z = heroPos(unitID)
			if not x then
				return
			end
			local ally = spGetUnitAllyTeam(unitID)
			local hp, maxHp = spGetUnitHealth(unitID)
			local hpFrac = hp and maxHp and hp / maxHp or 1
			local f = frameNow()
			local underFire = f - (h.lastHit or -1000) < 3 * GAME_SPEED
			local escaping = h.retreating or (hpFrac < 0.4 and underFire)
			local cfg = h.def.cfg
			for _, key in ipairs({ "ult", "a1", "a2" }) do
				local b = cfg[key]
				if b and cast[b.kind] and abilityReady(h, key) and not dashes[unitID] then
					local r = rankOf(h, key)
					local k = b.kind
					local worth = key == "ult" and AUTO_ULT or AUTO_MIN
					if k == "active_guard" or k == "active_dome" then
						local near = enemyCostNear(x, z, 1100, ally)
						if near > max(AUTO_MIN, h.def.cost * 0.3) or (hpFrac < 0.5 and near > 0) then
							tryCast(unitID, h, key)
						end
					elseif k == "active_nova" then
						local rad = val(b.radius, r)
						local near = enemyCostNear(x, z, rad, ally)
						local heal = val(b.heal, r) or 0
						if near > worth or (heal > 0 and (near > 0 or hpFrac < 0.6) and alliedDamage(x, z, rad, ally) > heal * 3) then
							tryCast(unitID, h, key)
						end
					elseif k == "active_bladestorm" then
						if enemyCostNear(x, z, val(b.radius, r), ally) > worth then
							tryCast(unitID, h, key)
						end
					elseif k == "active_buff" then
						local bf = b.buff or {}
						local reach = weaponReach(h)
						if bf.immobile then
							-- anchors only with a fight in reach
							if enemyCostNear(x, z, reach, ally) > AUTO_MIN then
								tryCast(unitID, h, key)
							end
						elseif bf.speed and not bf.damage and not bf.armor then
							if escaping or Spring.GetUnitNearestEnemy(unitID, reach * 1.5, true) then
								tryCast(unitID, h, key)
							end
						elseif Spring.GetUnitNearestEnemy(unitID, reach, true) then
							tryCast(unitID, h, key)
						end
					elseif k == "active_barrage" or k == "active_beam" then
						local score, tx, tz = bestCluster(x, z, castRange(b, r), val(b.radius, r) or 500, ally)
						if tx and score > worth then
							tryCast(unitID, h, key, tx, tz)
						end
					elseif k == "active_spear" then
						local target, value = mostValuableEnemy(x, z, castRange(b, r), ally)
						if target and value >= 3000 then
							tryCast(unitID, h, key, nil, nil, target)
						end
					elseif k == "active_dash" then
						local range = val(b.range, r)
						if escaping then
							-- away from the nearest enemy
							local e = Spring.GetUnitNearestEnemy(unitID, 1500, true)
							local ex, _, ez = e and spGetUnitPosition(e)
							if ex then
								local dx, dz = x - ex, z - ez
								local d = max(1, sqrt(dx * dx + dz * dz))
								tryCast(unitID, h, key, x + dx / d * range, z + dz / d * range)
							end
						elseif hpFrac > 0.45 then
							local score, tx, tz = bestCluster(x, z, range, max(300, (val(b.radius, r) or 200) * 2), ally)
							if tx and score > AUTO_MIN and (tx - x) ^ 2 + (tz - z) ^ 2 > 250 * 250 then
								tryCast(unitID, h, key, tx, tz)
							end
						end
					elseif k == "active_summon" then
						if enemyCostNear(x, z, max(1400, weaponReach(h)), ally) > AUTO_MIN then
							tryCast(unitID, h, key)
						end
					elseif k == "active_missiles" then
						if enemyCostNear(x, z, val(b.radius, r), ally) > AUTO_MIN * 0.5 then
							tryCast(unitID, h, key)
						end
					elseif k == "active_repair" then
						local heal = val(b.heal, r) * abilityPower(h)
						if alliedDamage(x, z, val(b.radius, r), ally) > heal * 3 or hpFrac < 0.5 then
							tryCast(unitID, h, key)
						end
					elseif k == "active_cloak" then
						if escaping then
							tryCast(unitID, h, key)
						end
					elseif k == "active_shield" then
						if underFire and hpFrac < 0.9 and enemyCostNear(x, z, 1600, ally) > 0 then
							tryCast(unitID, h, key)
						end
					end
				end
			end
		end
	end


	---------------------------------------------------------------- AI heroes
	-- The skirmish AI never sent its heroes into its attack groups (they idled at home), so the gadget
	-- drives them: the AI is told to let go of a hero ("detach", misc/aicmdr.as), the hero marches with
	-- the strongest group of its army, keeps its role's place in it, and falls back to the fountain when
	-- hurt or outnumbered.

	local armyDefs = {} -- mobile ground combat units the heroes escort
	for udid, ud in pairs(UnitDefs) do
		if ud.canMove and not ud.canFly and not ud.isBuilder and #ud.weapons > 0 and (ud.speed or 0) > 0 and not heroDefs[udid] then
			armyDefs[udid] = true
		end
	end

	local function retreatPoint(teamID, x, z)
		local best, bx, bz
		for _, uid in ipairs(Spring.GetTeamUnits(teamID)) do
			local udid = spGetUnitDefID(uid)
			local prio = foundryDefs[udid] and 1 or (factoryDefs[udid] and 2 or nil)
			if prio then
				local ux, _, uz = spGetUnitPosition(uid)
				local d = (ux - x) ^ 2 + (uz - z) ^ 2 + (prio - 1) * 1e12
				if not best or d < best then
					best, bx, bz = d, ux, uz
				end
			end
		end
		if not bx then
			local sx, _, sz = Spring.GetTeamStartPosition(teamID)
			bx, bz = sx, sz
		end
		return bx, bz
	end

	-- where the enemy is: the start position of the nearest enemy team that is still alive
	local function enemyHome(teamID, x, z)
		local ally = select(6, Spring.GetTeamInfo(teamID, false))
		local best, bx, bz
		for _, t in ipairs(Spring.GetTeamList()) do
			local _, _, isDead, _, _, a = Spring.GetTeamInfo(t, false)
			if a ~= ally and not isDead and t ~= Spring.GetGaiaTeamID() then
				local sx, _, sz = Spring.GetTeamStartPosition(t)
				if sx and sx >= 0 then
					local d = (sx - x) ^ 2 + (sz - z) ^ 2
					if not best or d < best then
						best, bx, bz = d, sx, sz
					end
				end
			end
		end
		return bx, bz
	end

	-- the strongest group of the team's army: 1000-elmo cells by metal, the front-most of the big ones
	local armyCache = {} -- teamID -> { frame, x, z, cost }
	local function armyGroup(teamID, f)
		local c = armyCache[teamID]
		if c and f - c.frame < 55 then
			return c
		end
		local cells = {}
		for _, uid in ipairs(Spring.GetTeamUnits(teamID)) do
			local udid = spGetUnitDefID(uid)
			if armyDefs[udid] then
				local x, _, z = spGetUnitPosition(uid)
				if x then
					local key = floor(x / 1000) .. ":" .. floor(z / 1000)
					local cell = cells[key]
					if not cell then
						cell = { x = 0, z = 0, cost = 0 }
						cells[key] = cell
					end
					local cost = unitCost[udid]
					cell.x, cell.z, cell.cost = cell.x + x * cost, cell.z + z * cost, cell.cost + cost
				end
			end
		end
		local maxCost = 0
		for _, cell in pairs(cells) do
			maxCost = max(maxCost, cell.cost)
		end
		local sx, _, sz = Spring.GetTeamStartPosition(teamID)
		local ex, ez = enemyHome(teamID, sx or 0, sz or 0)
		local best, bestD
		for _, cell in pairs(cells) do
			if cell.cost >= maxCost * 0.6 then
				local cx, cz = cell.x / cell.cost, cell.z / cell.cost
				local d = ex and ((cx - ex) ^ 2 + (cz - ez) ^ 2) or 0
				if not bestD or d < bestD then
					best, bestD = { x = cx, z = cz, cost = cell.cost }, d
				end
			end
		end
		c = { frame = f, x = best and best.x, z = best and best.z, cost = best and best.cost or 0, ex = ex, ez = ez }
		armyCache[teamID] = c
		return c
	end

	local function orderMove(unitID, h, cmd, x, z, f)
		h.lastOrder = f
		h.orderX, h.orderZ = x, z
		Spring.GiveOrderToUnit(unitID, cmd, { x, spGetGroundHeight(x, z), z }, 0)
	end

	-- enemy metal around vs allied metal around (the hero counted at its grown strength)
	local function danger(unitID, h, x, z)
		local ally = spGetUnitAllyTeam(unitID)
		local enemy, friend = 0, 0
		for _, uid in ipairs(spGetUnitsInCylinder(x, z, 1100)) do
			local a = spGetUnitAllyTeam(uid)
			local c = costOf(uid)
			if a == ally then
				friend = friend + (uid == unitID and c * (h.hpMult or 1) * (h.dmgMult or 1) or c)
			elseif not spGetUnitIsDead(uid) then
				enemy = enemy + c
			end
		end
		return enemy / max(1, friend)
	end

	local function startRetreat(unitID, h, x, z, f)
		local rx, rz = retreatPoint(h.team, x, z)
		if not rx then
			return
		end
		h.retreating = true
		h.retreatX, h.retreatZ = rx, rz
		orderMove(unitID, h, CMD.MOVE, rx, rz, f)
		spSetUnitRulesParam(unitID, "hero_retreat", 1, ALLIED)
		-- cover the way back
		for _, key in ipairs({ "a1", "a2", "ult" }) do
			local b = h.def.cfg[key]
			if b and (b.kind == "active_guard" or b.kind == "active_dome" or (b.kind == "active_buff" and b.buff.speed)) then
				tryCast(unitID, h, key)
			end
		end
	end

	local function aiHero(unitID, h, f)
		local hp, maxHp = spGetUnitHealth(unitID)
		if not hp then
			return
		end
		local frac = hp / maxHp
		local x, _, z = heroPos(unitID)
		if not h.detached then
			h.detached = true
			toAI(h.team, "detach " .. unitID)
		end
		if h.retreating then
			local back = H.AI_RETURN_HP
			if not fountainNear(h.team, h.retreatX, h.retreatZ) then
				back = H.AI_RETURN_HP_NO_FOUNTAIN
			end
			if frac >= back then
				h.retreating = false
				spSetUnitRulesParam(unitID, "hero_retreat", 0, ALLIED)
			elseif f - (h.lastOrder or 0) > 5 * GAME_SPEED and (x - h.retreatX) ^ 2 + (z - h.retreatZ) ^ 2 > 400 * 400
				and Spring.GetUnitCommandCount(unitID) == 0 then
				orderMove(unitID, h, CMD.MOVE, h.retreatX, h.retreatZ, f)
			end
			return
		end
		-- health 5 seconds ago: a burst (artillery, nukes) means getting out even far from any enemy
		h.hpHist = h.hpHist or {}
		local sec = floor(f / GAME_SPEED)
		h.hpHist[sec % 6] = frac
		local before = h.hpHist[(sec + 1) % 6] or frac
		if frac < H.AI_RETREAT_HP or (frac < H.AI_CAUTION_HP and danger(unitID, h, x, z) > H.AI_DANGER)
			or (before - frac > H.AI_BURST and frac < 0.8) then
			startRetreat(unitID, h, x, z, f)
			return
		end
		-- march with the army
		local g = armyGroup(h.team, f)
		local tx, tz
		-- an escort worth a quarter of the hero, at most 10k metal (the expensive heroes otherwise waited
		-- at the altar for an army cell of 35-45k that the AI rarely gathers)
		if g.x and g.cost >= min(h.def.cost * 0.25, H.AI_ESCORT) then
			local off = H.AI_ROLE_OFFSET[h.def.cfg.aiRole or "center"] or 0
			tx, tz = g.x, g.z
			if g.ex then
				local dx, dz = g.ex - g.x, g.ez - g.z
				local d = sqrt(dx * dx + dz * dz)
				if d > 1 then
					tx, tz = g.x + dx / d * off, g.z + dz / d * off
				end
			end
		else
			-- no army to walk with: guard the altar
			tx, tz = retreatPoint(h.team, x, z)
		end
		if not tx then
			return
		end
		tx = max(64, min(Game.mapSizeX - 64, tx))
		tz = max(64, min(Game.mapSizeZ - 64, tz))
		local moved = not h.orderX or (tx - h.orderX) ^ 2 + (tz - h.orderZ) ^ 2 > 350 * 350
		local far = (tx - x) ^ 2 + (tz - z) ^ 2 > 300 * 300
		if (moved and far) or (far and Spring.GetUnitCommandCount(unitID) == 0) then
			orderMove(unitID, h, CMD.FIGHT, tx, tz, f)
		end
	end

	---------------------------------------------------------------- inventory

	local function freeSlot(h)
		for slot = 1, H.INVENTORY do
			if not h.items[slot] then
				return slot
			end
		end
	end

	local function pickups()
		if not next(ground) then
			return
		end
		local r2 = H.ITEM_PICKUP_RADIUS * H.ITEM_PICKUP_RADIUS
		for unitID, h in pairs(heroes) do
			local slot = freeSlot(h)
			if slot then
				local x, y, z = heroPos(unitID)
				if x then
					for id, g in pairs(ground) do
						if (g.x - x) ^ 2 + (g.z - z) ^ 2 <= r2 then
							h.items[slot] = g.item
							h.itemReady[slot] = 0
							ground[id] = nil
							groundDirty = true
							applyStats(unitID, h)
							publishItems(unitID, h)
							ceg("hero-itempickup-" .. H.items[g.item].rarity, x, y, z)
							toUI("pickup", unitID, H.itemIndex[g.item])
							slot = freeSlot(h)
							if not slot then
								break
							end
						end
					end
				end
			end
		end
	end

	local function expireGround(f)
		for id, g in pairs(ground) do
			if g.expire <= f then
				ground[id] = nil
				groundDirty = true
			end
		end
	end

	local function dropSlot(unitID, h, slot)
		local id = h.items[slot]
		if not id then
			return
		end
		h.items[slot] = nil
		h.itemReady[slot] = nil
		local x, _, z = heroPos(unitID)
		local dx, _, dz = Spring.GetUnitDirection(unitID)
		dropItem(id, x + (dx or 0) * 220, z + (dz or 1) * 220)
		applyStats(unitID, h)
		publishItems(unitID, h)
	end

	local function useSlot(unitID, h, slot)
		local id = h.items[slot]
		local it = id and H.items[id]
		local act = it and it.active
		local f = frameNow()
		if not act or (h.itemReady[slot] or 0) > f then
			return false
		end
		local x, y, z = heroPos(unitID)
		if act.kind == "heal" then
			local hp, maxHp = spGetUnitHealth(unitID)
			spSetUnitHealth(unitID, min(maxHp, hp + maxHp * act.amount))
			ceg("hero-itemheal", x, y, z)
		elseif act.kind == "invuln" then
			h.undyingUntil = max(h.undyingUntil, f + act.duration * GAME_SPEED)
			markActive(unitID, "item" .. slot, act.duration)
			ceg("hero-phase", x, y, z)
		elseif act.kind == "dash" then
			local dx, _, dz = Spring.GetUnitDirection(unitID)
			local nx = max(64, min(Game.mapSizeX - 64, x + dx * act.distance))
			local nz = max(64, min(Game.mapSizeZ - 64, z + dz * act.distance))
			ceg("hero-blink", x, y, z)
			Spring.SetUnitPosition(unitID, nx, nz)
			ceg("hero-blink", nx, spGetGroundHeight(nx, nz), nz)
		end
		h.itemReady[slot] = f + act.cooldown * GAME_SPEED
		publishItems(unitID, h)
		toUI("useitem", unitID, H.itemIndex[id])
		return true
	end

	-- AI heroes and autocast players use their items by themselves
	local function autoItems(unitID, h)
		local hp, maxHp = spGetUnitHealth(unitID)
		if not hp then
			return
		end
		local frac = hp / maxHp
		for slot = 1, H.INVENTORY do
			local it = h.items[slot] and H.items[h.items[slot]]
			local act = it and it.active
			if act and ((act.kind == "heal" and frac < 0.55) or (act.kind == "invuln" and frac < 0.3)) then
				useSlot(unitID, h, slot)
			end
		end
	end

	---------------------------------------------------------------- frames

	function gadget:GameFrame(f)
		if #delayed > 0 then
			local keep = {}
			for _, d in ipairs(delayed) do
				if d.frame <= f then
					d.fn()
				else
					keep[#keep + 1] = d
				end
			end
			delayed = keep
		end
		abilityFrame(f)
		if f % 15 == 11 then
			expireGround(f)
			pickups()
			if groundDirty then
				publishGround()
			end
		end
		if next(heroes) == nil and #events == 0 then
			return
		end
		if f % 6 == 3 then
			processEvents(f)
			weaponEffects(f)
		end
		if f % 15 == 7 then
			refreshProtection(f)
		end
		if f % 30 == 13 then
			passives(f)
			for unitID, h in pairs(heroes) do
				if isAITeam[h.team] then
					aiHero(unitID, h, f)
				end
				if h.autocast or isAITeam[h.team] then
					autocast(unitID, h)
					autoItems(unitID, h)
				end
				-- the AI learns what it could not afford before
				if isAITeam[h.team] and f % 300 == 13 and h.level - #h.picks > 0 then
					learnAI(unitID, h)
				end
				publish(unitID, h)
			end
		end
	end

	---------------------------------------------------------------- commands and UI messages

	local function orderTarget(cmdParams)
		if #cmdParams == 1 then
			local tx, _, tz = spGetUnitPosition(cmdParams[1])
			return tx, tz, cmdParams[1]
		elseif #cmdParams >= 3 then
			return cmdParams[1], cmdParams[3], nil
		end
	end

	function gadget:AllowCommand(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions, cmdTag, playerID, fromSynced, fromLua)
		local h = heroes[unitID]
		if not h then
			return true
		end
		if cmdID == CMD_HERO_AUTOCAST then
			h.autocast = (cmdParams[1] or 1) == 1
			local idx = Spring.FindUnitCmdDesc(unitID, CMD_HERO_AUTOCAST)
			if idx then
				Spring.EditUnitCmdDesc(unitID, idx, { params = { h.autocast and 1 or 0, "hero_autocast_off", "hero_autocast_on" } })
			end
			publish(unitID, h)
			return false
		end
		local key = h.def.cmds[cmdID]
		if not key then
			return true
		end
		local b = h.def.cfg[key]
		if not abilityReady(h, key) then
			return false
		end
		if not b.target then
			tryCast(unitID, h, key)
			return false
		end
		local tx, tz, targetID = orderTarget(cmdParams)
		if not tx then
			return false
		end
		local x, _, z = heroPos(unitID)
		local r = rankOf(h, key)
		if (tx - x) ^ 2 + (tz - z) ^ 2 <= castRange(b, r) ^ 2 then
			tryCast(unitID, h, key, tx, tz, targetID)
			return false
		end
		return true -- out of range: queue it, CommandFallback walks into range
	end

	function gadget:CommandFallback(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions, cmdTag)
		local h = heroes[unitID]
		local key = h and h.def.cmds[cmdID]
		if not key then
			return false
		end
		if not abilityReady(h, key) then
			return true, true
		end
		local b = h.def.cfg[key]
		local tx, tz, targetID = orderTarget(cmdParams)
		if not tx then
			return true, true
		end
		local x, _, z = heroPos(unitID)
		local range = castRange(b, rankOf(h, key))
		if (tx - x) ^ 2 + (tz - z) ^ 2 <= range ^ 2 then
			tryCast(unitID, h, key, tx, tz, targetID)
			return true, true
		end
		Spring.SetUnitMoveGoal(unitID, tx, spGetGroundHeight(tx, tz), tz, range * 0.9)
		return true, false
	end

	function gadget:RecvLuaMsg(msg, playerID)
		if msg:sub(1, 7) ~= "t4hero:" then
			return
		end
		local _, _, spec, teamID = Spring.GetPlayerInfo(playerID, false)
		if spec then
			return
		end
		local what, uid, key = msg:match("^t4hero:(%a+):(%d+):?([%w_]*)$")
		uid = tonumber(uid)
		local h = uid and heroes[uid]
		if not h or spGetUnitTeam(uid) ~= teamID then
			return
		end
		if what == "learn" then
			learn(uid, h, key)
		elseif what == "use" then
			useSlot(uid, h, tonumber(key) or 0)
		elseif what == "drop" then
			dropSlot(uid, h, tonumber(key) or 0)
		elseif what == "swap" then
			local a, b = key:match("^(%d)_(%d)$")
			a, b = tonumber(a), tonumber(b)
			if a and b and a >= 1 and b >= 1 and a <= H.INVENTORY and b <= H.INVENTORY then
				h.items[a], h.items[b] = h.items[b], h.items[a]
				h.itemReady[a], h.itemReady[b] = h.itemReady[b], h.itemReady[a]
				publishItems(uid, h)
			end
		end
		return true
	end

	function gadget:Initialize()
		for _, def in pairs(heroDefs) do
			for cmdID in pairs(def.cmds) do
				gadgetHandler:RegisterCMDID(cmdID)
				gadgetHandler:RegisterAllowCommand(cmdID)
			end
		end
		gadgetHandler:RegisterCMDID(CMD_HERO_AUTOCAST)
		gadgetHandler:RegisterAllowCommand(CMD_HERO_AUTOCAST)
		for wdid in pairs(swapWatch) do
			Script.SetWatchProjectile(wdid, true)
		end
		for wdid in pairs(explWatch) do
			Script.SetWatchExplosion(wdid, true)
		end
		for _, teamID in ipairs(Spring.GetTeamList()) do
			for _, name in ipairs(H.order) do
				if UnitDefNames[name] then
					publishDead(teamID, name)
				end
			end
		end
		-- /luarules reload: pick up heroes already on the field at level 1
		for _, uid in ipairs(Spring.GetAllUnits()) do
			local udid = spGetUnitDefID(uid)
			if heroDefs[udid] then
				local _, _, _, _, bp = spGetUnitHealth(uid)
				if bp and bp >= 1 then
					gadget:UnitFinished(uid, udid, spGetUnitTeam(uid))
				end
			end
		end
		publishGround()
		GG.T4Heroes = { heroes = heroes, learn = function(uid, key) local h = heroes[uid]; return h and learn(uid, h, key) end,
			give = function(uid, item) local h = heroes[uid]; local slot = h and freeSlot(h)
				if slot and H.items[item] then h.items[slot] = item; h.itemReady[slot] = 0; applyStats(uid, h); publishItems(uid, h) end end,
			drop = function(item, x, z) dropItem(item, x, z) end, randomItem = function(level) return randomItem(level) end,
			setLevel = function(uid, level) local h = heroes[uid]
				if h then h.xp = H.xpFor(level, xpMult) * h.def.cost + 1
					while h.level < min(level, H.MAX_LEVEL) do levelUp(uid, h) end publish(uid, h) end end,
			addXP = function(uid, metal) local h = heroes[uid]; if h then addXP(uid, h, metal) end end,
			cast = function(uid, key, tx, tz, target) local h = heroes[uid]; return h and tryCast(uid, h, key, tx, tz, target) end,
			-- any ability table of the kit, no cooldown (items, tests): castAbility(uid, { kind = ..., ... }, rank, tx, tz, target)
			castAbility = function(uid, b, r, tx, tz, target) local h = heroes[uid]
				return h and cast[b.kind] and cast[b.kind](uid, h, b.key or "item", b, r or 1, tx, tz, target) or false end,
			abilityPower = function(uid) return abilityPower(heroes[uid]) end,
			dead = dead, setAI = function(teamID, ai) isAITeam[teamID] = ai end }
	end

	function gadget:Shutdown()
		GG.T4Heroes = nil
	end
else
	----------------------------------------------------------------------------- unsynced

	local spSendSkirmishAIMessage = Spring.SendSkirmishAIMessage

	local function aiMsg(_, teamID, text)
		-- only the client hosting that AI delivers it; elsewhere this is a no-op
		spSendSkirmishAIMessage(teamID, text)
	end

	local function heroEvent(_, kind, unitID, a, b)
		if Script.LuaUI("T4HeroEvent") then
			Script.LuaUI.T4HeroEvent(kind, unitID, a, b)
		end
	end

	function gadget:Initialize()
		gadgetHandler:AddSyncAction("t4hero_aimsg", aiMsg)
		gadgetHandler:AddSyncAction("t4hero_event", heroEvent)
	end

	function gadget:Shutdown()
		gadgetHandler:RemoveSyncAction("t4hero_aimsg")
		gadgetHandler:RemoveSyncAction("t4hero_event")
	end
end
