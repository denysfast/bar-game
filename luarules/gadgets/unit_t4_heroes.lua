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
--   t4hero:buylevel:<unitID>            buy one level for metal (v15; price H.levelPrice, one per H.BUY_COOLDOWN s)
-- Unit rules params: hero_level (in LOS), hero_xp (0..1 to the next level), hero_points,
--   hero_rank_<branch>, hero_ready_<branch> (frame the ability is ready), hero_on_<branch> (frame an
--   active effect ends; in LOS), hero_retreat (AI care). Team rules params (allies):
--   hero_dead_<name> (the level a revive brings back), hero_revive_<name> (revive metal cost).
-- v15: hero_buy_price (metal of the next bought level, 0 at the top), hero_buy_ready (frame the next level can
--   be bought) - unit, allied; hero_ai_bank - team, allied: metal an AI team put aside for ranks and levels.

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
		-- every weapon any rank swaps is watched; the swap itself is looked up per unit
		for _, key in ipairs({ "a1", "a2", "ult" }) do
			local b = def.cfg[key]
			if b and b.ranks then
				for _, r in ipairs(b.ranks) do
					for _, sw in ipairs({ r.swap, r.swap2 }) do
						for _, wdid in ipairs(keyWdids(def, sw and sw.weapon or "")) do
							swapWatch[wdid] = true
						end
					end
				end
			end
			if b and (b.kind == "chain" or b.kind == "cluster") then
				for _, wdid in ipairs(keyWdids(def, b.weapon)) do
					explWatch[wdid] = true
				end
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

	local function nukeAt(h, x, z)
		local wdid = h.def.extra.hero_nova
		if wdid then
			local y = spGetGroundHeight(x, z)
			Spring.SpawnExplosion(x, y + 5, z, 0, 0, 0, { weaponDef = wdid, owner = h.unitID, damageGround = true })
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
		for _, key in ipairs({ "a1", "a2", "ult" }) do
			local b = cfg[key]
			local r = rankOf(h, key)
			if b and r > 0 and b.ranks and b.ranks[r] then
				add(b.ranks[r], 1)
			end
		end
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

		-- projectile swaps: weaponDefID -> { to, every, other }
		h.swaps = {}
		for _, sw in ipairs(m.swaps) do
			for _, n in ipairs(def.keyNum[sw.weapon] or {}) do
				h.swaps[def.weapons[n].wdid] = { to = def.extra[sw.to], every = sw.every or 1, other = sw.other and def.extra[sw.other], num = n, scatter = sw.scatter }
			end
		end

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
		spSetUnitRulesParam(unitID, "hero_buy_price", H.levelPrice(h.def.name, h.level, h.def.cost) or 0, ALLIED)
		spSetUnitRulesParam(unitID, "hero_buy_ready", h.buyReady or 0, ALLIED)
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

	local prepaid = 0 -- metal an AI rank is paid with from the team's hero bank (v15, see aiEconomy)

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
		if cost > 0 and (Spring.GetTeamResources(h.team, "metal") or 0) < cost and prepaid < cost then
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
		return state == "ok" and ((cost or 0) <= prepaid or (cost or 0) * 1.5 <= (Spring.GetTeamResources(h.team, "metal") or 0))
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
		if cost and cost > 0 and prepaid >= cost then
			prepaid = prepaid - cost
		elseif cost and cost > 0 and not Spring.UseTeamResource(h.team, "metal", cost) then
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

	-- v15: one level for metal (the Buy level button, t4hero:buylevel; an AI pays from its bank: paid = true).
	-- Returns true, or false and why: "max", "cooldown", "metal"
	local function buyLevel(unitID, h, paid)
		if h.level >= H.MAX_LEVEL then
			return false, "max"
		end
		local f = frameNow()
		if f < (h.buyReady or 0) then
			return false, "cooldown"
		end
		local price = H.levelPrice(h.def.name, h.level, h.def.cost)
		if not paid and ((Spring.GetTeamResources(h.team, "metal") or 0) < price or not Spring.UseTeamResource(h.team, "metal", price)) then
			toUI("nometal", unitID, price)
			return false, "metal"
		end
		h.buyReady = f + H.BUY_COOLDOWN * GAME_SPEED
		-- the experience moves on by one level's worth: the progress toward the next level is kept
		local lo = H.xpFor(h.level, xpMult) * h.def.cost
		local hi = H.xpFor(h.level + 1, xpMult) * h.def.cost
		h.xp = max(h.xp, lo) + (hi - lo)
		repeat
			levelUp(unitID, h)
		until h.level >= H.MAX_LEVEL or h.xp < H.xpFor(h.level + 1, xpMult) * h.def.cost
		h.bought = (h.bought or 0) + 1
		publish(unitID, h)
		toUI("bought", unitID, h.level, price)
		return true
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
				cursor = b.target and "Attack" or nil, tooltip = b.name .. ": " .. b.desc,
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
		local _, _, _, _, bp = spGetUnitHealth(unitID)
		if bp and bp >= 1 then
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
		-- hero warheads and novas never hurt their own side (a mini-nuke carpet over a melee hero)
		if heroWeapon[weaponDefID] and attackerTeam and spAreTeamsAllied(attackerTeam, unitTeam) then
			return 0, 0
		end
		local m = guardMult[unitID] or 1
		local a = attackerID and heroes[attackerID]
		if a then
			m = m * a.dmgMult * (a.wdmg and a.wdmg[weaponDefID] or 1)
			local cfg = a.def.cfg
			local r = rankOf(a, "a1")
			if r > 0 and not paralyzer then
				local b = cfg.a1
				if b.kind == "crit" and random() < b.chance[r] then
					m = m * b.mult[r]
					local f = frameNow()
					if f - a.lastCrit > 8 then
						a.lastCrit = f
						local x, y, z = spGetUnitPosition(unitID)
						if x then
							ceg("hero-crit", x, y + 20, z)
						end
					end
				elseif b.kind == "slayer" and (unitCost[unitDefID] or 0) >= b.minCost then
					m = m * (1 + b.mult[r])
				end
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
		elseif attackerID and auraDamage[attackerID] then
			m = m * (1 + auraDamage[attackerID])
		end
		local v = heroes[unitID]
		if v then
			m = m * (1 - v.armor) / (v.hpMult or 1)
			local f = frameNow()
			if v.bladestorm and v.bladestorm.expire > f then
				m = m * (1 - v.bladestorm.armor)
			end
			if v.undyingUntil > f then
				return 0, 0
			end
			if not paralyzer and v.def.cfg.ult.kind == "undying" then
				local r = rankOf(v, "ult")
				local hp = spGetUnitHealth(unitID)
				if r > 0 and v.undyingReady <= f and hp and damage * m >= hp then
					local b = v.def.cfg.ult
					v.undyingReady = f + b.cooldown[r] * GAME_SPEED
					v.undyingUntil = f + 3 * GAME_SPEED
					spSetUnitRulesParam(unitID, "hero_ready_ult", v.undyingReady, ALLIED)
					spSetUnitRulesParam(unitID, "hero_cd_ult", b.cooldown[r] * GAME_SPEED, ALLIED)
					spSetUnitRulesParam(unitID, "hero_on_ult", v.undyingUntil, INLOS)
					delayed[#delayed + 1] = { frame = f + 1, fn = function()
						if heroes[unitID] then
							local _, maxHp = spGetUnitHealth(unitID)
							spSetUnitHealth(unitID, maxHp * b.heal[r])
							local x, y, z = spGetUnitPosition(unitID)
							ceg("hero-undying", x, y, z)
							if b.nova[r] then
								nukeAt(v, x, z)
							end
							toUI("undying", unitID, r)
						end
					end }
					return 0, 0
				end
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
			if attackerID and attackerTeam and not spAreTeamsAllied(attackerTeam, unitTeam) then victim.attackers = victim.attackers or {}; victim.attackers[attackerID] = victim.lastHit end -- AI escorts focus them
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
		if paralyzer or inThorns then
			return
		end
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

	---------------------------------------------------------------- projectile swaps (nuclear rockets & co)

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

	function gadget:ProjectileCreated(proID, ownerID, weaponDefID)
		if not swapWatch[weaponDefID] or not ownerID then
			return
		end
		local h = heroes[ownerID]
		if not h then
			return
		end
		local sw = h.swaps and h.swaps[weaponDefID]
		local to
		if sw then
			h.shots[weaponDefID] = (h.shots[weaponDefID] or 0) + 1
			to = (h.shots[weaponDefID] % sw.every == 0) and sw.to or sw.other
		end
		if not to then
			tierSwap(proID, ownerID, weaponDefID, h)
			return
		end
		local px, py, pz = Spring.GetProjectilePosition(proID)
		local vx, vy, vz = Spring.GetProjectileVelocity(proID)
		if not px then
			return
		end
		local _, target = Spring.GetProjectileTarget(proID)
		if not target then
			-- at creation the projectile has no target yet: take the weapon's
			local tt, _, wt = Spring.GetUnitWeaponTarget(ownerID, sw.num)
			if tt == 1 or tt == 2 then
				target = wt
			end
		end
		local grav = Spring.GetProjectileGravity and Spring.GetProjectileGravity(proID) or gravityPerFrame
		Spring.DeleteProjectile(proID)
		projParams.pos[1], projParams.pos[2], projParams.pos[3] = px, py, pz
		-- a little spread, so a multi-rocket salvo does not fly as one
		local sp = sqrt(vx * vx + vy * vy + vz * vz) * 0.08
		projParams.speed[1], projParams.speed[2], projParams.speed[3] = vx + (random() - 0.5) * sp, vy, vz + (random() - 0.5) * sp
		projParams.owner = ownerID
		projParams.team = h.team
		projParams.gravity = grav
		projParams.ttl = 900
		projParams.tracking = type(target) == "number" and target or nil
		projParams.upTime = upTime[to] -- starbursts climb this many frames, then turn to the target
		if sw.scatter and target then
			-- a salvo carpets the area around the target instead of converging on one point
			local tx, ty, tz
			if type(target) == "number" then
				tx, ty, tz = spGetUnitPosition(target)
			else
				tx, ty, tz = target[1], target[2], target[3]
			end
			if tx then
				local ax, az = randomPointIn(tx, tz, sw.scatter)
				target = { ax, spGetGroundHeight(ax, az), az }
				projParams.tracking = nil
			end
		end
		local newID = spSpawnProjectile(to, projParams)
		projParams.tracking = nil
		projParams.upTime = nil
		if newID and target then
			if type(target) == "number" then
				Spring.SetProjectileTarget(newID, target, string.byte("u"))
			elseif type(target) == "table" then
				Spring.SetProjectileTarget(newID, target[1], target[2], target[3])
			end
		end
	end

	---------------------------------------------------------------- chain lightning / cluster payload

	local lightningParams = { pos = { 0, 0, 0 }, ["end"] = { 0, 0, 0 }, ttl = 2, owner = -1, team = -1 }

	function gadget:Explosion(weaponDefID, px, py, pz, attackerID, projectileID)
		if not explWatch[weaponDefID] or not attackerID then
			return false
		end
		weaponDefID = tierBase[weaponDefID] or weaponDefID
		local h = heroes[attackerID]
		if not h then
			return false
		end
		local cfg = h.def.cfg
		for _, key in ipairs({ "a1", "a2" }) do
			local b = cfg[key]
			local r = rankOf(h, key)
			if r > 0 and b.kind == "chain" and h.def.extra.hero_chain then
				local ally = spGetUnitAllyTeam(attackerID)
				local targets = enemiesIn(px, pz, b.radius, ally)
				local n = 0
				for _, uid in ipairs(targets) do
					local x, y, z = spGetUnitPosition(uid)
					if x and ((x - px) ^ 2 + (z - pz) ^ 2) > 900 then
						lightningParams.pos[1], lightningParams.pos[2], lightningParams.pos[3] = px, py + 10, pz
						lightningParams["end"][1], lightningParams["end"][2], lightningParams["end"][3] = x, y + 20, z
						lightningParams.owner = attackerID
						lightningParams.team = h.team
						spSpawnProjectile(h.def.extra.hero_chain, lightningParams)
						n = n + 1
						if n >= b.jumps[r] then
							break
						end
					end
				end
			elseif r > 0 and b.kind == "cluster" and h.def.extra[b.to] then
				for i = 1, b.count[r] do
					local ang = random() * 6.283
					local sp = 2 + random() * 3.5
					projParams.pos[1], projParams.pos[2], projParams.pos[3] = px, py + 20, pz
					projParams.speed[1], projParams.speed[2], projParams.speed[3] = math.cos(ang) * sp, 5 + random() * 4, math.sin(ang) * sp
					projParams.owner = attackerID
					projParams.team = h.team
					projParams.gravity = gravityPerFrame
					spSpawnProjectile(h.def.extra[b.to], projParams)
				end
			end
		end
		return false
	end

	---------------------------------------------------------------- abilities

	local function abilityReady(h, key)
		return rankOf(h, key) > 0 and (h.ready[key] or 0) <= frameNow()
	end

	local function startCooldown(unitID, h, key, b, r)
		local cd = type(b.cooldown) == "table" and b.cooldown[r] or b.cooldown or 30
		cd = cd * max(0.4, 1 - (h.mods and h.mods.cdr or 0))
		h.ready[key] = frameNow() + floor(cd * GAME_SPEED)
		spSetUnitRulesParam(unitID, "hero_ready_" .. key, h.ready[key], ALLIED)
		spSetUnitRulesParam(unitID, "hero_cd_" .. key, floor(cd * GAME_SPEED), ALLIED)
	end

	local function markActive(unitID, key, seconds)
		spSetUnitRulesParam(unitID, "hero_on_" .. key, frameNow() + floor(seconds * GAME_SPEED), INLOS)
		spSetUnitRulesParam(unitID, "hero_dur_" .. key, floor(seconds * GAME_SPEED), INLOS)
	end

	local cast = {}

	cast.active_guard = function(unitID, h, key, b, r)
		events[#events + 1] = { kind = "guard", owner = unitID, expire = frameNow() + b.duration * GAME_SPEED, radius = b.radius, mult = 1 - b.reduce[r] }
		markActive(unitID, key, b.duration)
		local x, y, z = heroPos(unitID)
		ceg("hero-guard-cast", x, y, z)
		return true
	end

	cast.active_dome = function(unitID, h, key, b, r)
		events[#events + 1] = { kind = "dome", owner = unitID, expire = frameNow() + b.duration[r] * GAME_SPEED, radius = b.radius }
		markActive(unitID, key, b.duration[r])
		local x, y, z = heroPos(unitID)
		ceg("hero-dome-cast", x, y, z)
		return true
	end

	cast.active_buff = function(unitID, h, key, b, r)
		local dur = type(b.duration) == "table" and b.duration[r] or b.duration
		h.buff = { expire = frameNow() + floor(dur * GAME_SPEED), fx = b.buff, key = key, trailDmg = b.trailDmg and b.trailDmg[r] }
		applyStats(unitID, h)
		markActive(unitID, key, dur)
		local x, y, z = heroPos(unitID)
		ceg(b.fx or "hero-barrage", x, y, z)
		return true
	end

	cast.active_pulse = function(unitID, h, key, b, r)
		local num = h.def.shieldNum
		if not num then
			return false
		end
		local _, power = Spring.GetUnitShieldState(unitID, num)
		power = power or 0
		local used = power * 0.5
		Spring.SetUnitShieldState(unitID, num, true, power - used)
		local x, y, z = heroPos(unitID)
		damageArea(x, z, b.radius[r], spGetUnitAllyTeam(unitID), used * b.ratio[r], unitID, b.stun[r])
		ceg("hero-pulse", x, y, z)
		ceg("custom:genericshellexplosion-huge-lightning--x4", x, y + 30, z)
		return true
	end

	cast.active_stomp = function(unitID, h, key, b, r)
		local x, y, z = heroPos(unitID)
		damageArea(x, z, b.radius[r], spGetUnitAllyTeam(unitID), b.dmg[r], unitID, b.stun[r])
		ceg("hero-stomp", x, y, z)
		ceg("custom:crusherkrog--x5", x, y, z)
		return true
	end

	cast.active_flare = function(unitID, h, key, b, r)
		local x, y, z = heroPos(unitID)
		local ally = spGetUnitAllyTeam(unitID)
		damageArea(x, z, b.radius[r], ally, b.dmg[r], unitID)
		for _, uid in ipairs(alliesIn(x, z, b.radius[r], ally)) do
			local hp, maxHp = spGetUnitHealth(uid)
			if hp and maxHp then
				spSetUnitHealth(uid, min(maxHp, hp + maxHp * b.heal))
			end
		end
		ceg("hero-flare", x, y, z)
		ceg("custom:heatray-huge--x3", x, y + 10, z)
		return true
	end

	cast.active_bladestorm = function(unitID, h, key, b, r)
		h.bladestorm = { expire = frameNow() + b.duration * GAME_SPEED, armor = b.armor }
		events[#events + 1] = { kind = "bladestorm", owner = unitID, expire = h.bladestorm.expire, radius = b.radius[r], dmg = b.dmg[r] }
		markActive(unitID, key, b.duration)
		return true
	end

	cast.active_storm = function(unitID, h, key, b, r, tx, tz)
		local f = frameNow()
		local ticks = floor(b.duration * GAME_SPEED / 6)
		events[#events + 1] = { kind = "storm", owner = unitID, x = tx, z = tz, expire = f + b.duration * GAME_SPEED,
			radius = b.radius, perTick = b.bolts[r] / ticks, acc = 0, dmg = b.dmg[r], emp = b.emp }
		ceg("hero-target", tx, spGetGroundHeight(tx, tz), tz)
		ceg("hero-storm-cloud", tx, spGetGroundHeight(tx, tz), tz)
		markActive(unitID, key, b.duration)
		return true
	end

	cast.active_meteors = function(unitID, h, key, b, r, tx, tz)
		local f = frameNow()
		local ticks = floor(b.duration * GAME_SPEED / 6)
		events[#events + 1] = { kind = "meteors", owner = unitID, x = tx, z = tz, expire = f + b.duration * GAME_SPEED,
			radius = b.radius, perTick = b.count[r] / ticks, acc = 0, wdid = h.def.extra[b.weapon], nova = b.nova[r] }
		ceg("hero-target", tx, spGetGroundHeight(tx, tz), tz)
		markActive(unitID, key, b.duration)
		return true
	end

	cast.active_sunbeam = function(unitID, h, key, b, r, tx, tz)
		events[#events + 1] = { kind = "sunbeam", owner = unitID, x = tx, z = tz, expire = frameNow() + b.duration * GAME_SPEED,
			radius = b.radius, dmg = b.tick[r], nova = b.nova[r] }
		ceg("hero-sunbeam-start", tx, spGetGroundHeight(tx, tz), tz)
		markActive(unitID, key, b.duration)
		return true
	end

	cast.active_spear = function(unitID, h, key, b, r, tx, tz, targetID)
		if not targetID or not spValidUnitID(targetID) then
			return false
		end
		local x, y, z = heroPos(unitID)
		local ex, ey, ez = spGetUnitPosition(targetID)
		local dx, dy, dz = ex - x, ey - y, ez - z
		local d = sqrt(dx * dx + dy * dy + dz * dz)
		if d > b.range[r] then
			return false
		end
		local wdid = h.def.extra.hero_spear
		if wdid then
			local v = 60
			projParams.pos[1], projParams.pos[2], projParams.pos[3] = x, y + 60, z
			projParams.speed[1], projParams.speed[2], projParams.speed[3] = dx / d * v, (dy - 40) / d * v, dz / d * v
			projParams.owner = unitID
			projParams.team = h.team
			projParams.gravity = 0
			local pid = spSpawnProjectile(wdid, projParams)
			if pid then
				Spring.SetProjectileTarget(pid, targetID, string.byte("u"))
			end
		end
		local _, maxHp = spGetUnitHealth(targetID)
		local impact = frameNow() + floor(d / 60) + 1
		delayed[#delayed + 1] = { frame = impact, fn = function()
			if spValidUnitID(targetID) and not spGetUnitIsDead(targetID) then
				spAddUnitDamage(targetID, (maxHp or 0) * b.pct[r] + b.flat, 0, unitID)
				local px, py, pz = spGetUnitPosition(targetID)
				ceg("custom:genericshellexplosion-huge-lightning--x4", px, py + 20, pz)
				if b.nova[r] and heroes[unitID] then
					nukeAt(heroes[unitID], px, pz)
				end
			end
		end }
		return true
	end

	-- cast an ability now; tx/tz/targetID for targeted ones. Returns true when it went off.
	local function tryCast(unitID, h, key, tx, tz, targetID)
		local b = h.def.cfg[key]
		if not b or not cast[b.kind] or not abilityReady(h, key) then
			return false
		end
		local r = rankOf(h, key)
		if not cast[b.kind](unitID, h, key, b, r, tx, tz, targetID) then
			return false
		end
		startCooldown(unitID, h, key, b, r)
		toUI("cast", unitID, r, key == "a1" and 4 or (key == "a2" and 5 or 6)) -- index in H.branchOrder
		return true
	end

	local function castRange(b, r)
		if type(b.range) == "table" then
			return b.range[r]
		end
		return b.range or 0
	end

	---------------------------------------------------------------- timed effects

	local stormParams = { pos = { 0, 0, 0 }, ["end"] = { 0, 0, 0 }, ttl = 3, owner = -1, team = -1 }

	local function processEvents(f)
		local keep = {}
		for _, e in ipairs(events) do
			local h = heroes[e.owner]
			if e.expire > f and (h or e.kind == "storm" or e.kind == "meteors" or e.kind == "sunbeam") then
				keep[#keep + 1] = e
				local ownerAlly = h and spGetUnitAllyTeam(e.owner) or e.ally
				e.ally = ownerAlly
				local teamID = h and h.team or e.team
				e.team = teamID
				if e.kind == "storm" then
					e.acc = e.acc + e.perTick
					while e.acc >= 1 do
						e.acc = e.acc - 1
						local targets = enemiesIn(e.x, e.z, e.radius, ownerAlly)
						local x, z
						if #targets > 0 and random() < 0.75 then
							x, _, z = spGetUnitPosition(targets[random(#targets)])
						end
						if not x then
							x, z = randomPointIn(e.x, e.z, e.radius)
						end
						local y = spGetGroundHeight(x, z)
						stormParams.pos[1], stormParams.pos[2], stormParams.pos[3] = x + random(-200, 200), y + 1600, z + random(-200, 200)
						stormParams["end"][1], stormParams["end"][2], stormParams["end"][3] = x, y + 5, z
						stormParams.owner = h and e.owner or -1
						stormParams.team = teamID
						if h and h.def.extra.hero_stormbolt then
							spSpawnProjectile(h.def.extra.hero_stormbolt, stormParams)
						end
						for _, uid in ipairs(enemiesIn(x, z, 140, ownerAlly)) do
							spAddUnitDamage(uid, e.dmg, 0, h and e.owner or nil)
							spAddUnitDamage(uid, e.emp, 3, h and e.owner or nil)
						end
						ceg("custom:lightning_stormbig--x2", x, y + 10, z)
						ceg("hero-zap", x, y, z)
					end
					if f % 30 < 6 then
						ceg("hero-storm-cloud", e.x, spGetGroundHeight(e.x, e.z), e.z)
					end
				elseif e.kind == "meteors" then
					e.acc = e.acc + e.perTick
					while e.acc >= 1 do
						e.acc = e.acc - 1
						local targets = enemiesIn(e.x, e.z, e.radius, ownerAlly)
						local x, z
						if #targets > 0 and random() < 0.6 then
							x, _, z = spGetUnitPosition(targets[random(#targets)])
						end
						if not x then
							x, z = randomPointIn(e.x, e.z, e.radius)
						end
						local y = spGetGroundHeight(x, z)
						-- falls from 2400 above at an angle, lands in ~2 s
						local fall = 60
						local vy = -2400 / fall
						projParams.pos[1], projParams.pos[2], projParams.pos[3] = x - 700, y + 2400, z - 300
						projParams.speed[1], projParams.speed[2], projParams.speed[3] = 700 / fall, vy, 300 / fall
						projParams.owner = h and e.owner or -1
						projParams.team = teamID
						projParams.gravity = 0
						if e.wdid then
							spSpawnProjectile(e.wdid, projParams)
						end
					end
				elseif e.kind == "sunbeam" then
					local y = spGetGroundHeight(e.x, e.z)
					ceg("hero-sunbeam", e.x, y, e.z)
					for _, uid in ipairs(enemiesIn(e.x, e.z, e.radius, ownerAlly)) do
						spAddUnitDamage(uid, e.dmg, 0, h and e.owner or nil)
					end
				elseif e.kind == "bladestorm" and h then
					local x, y, z = heroPos(e.owner)
					damageArea(x, z, e.radius, ownerAlly, e.dmg, e.owner)
					ceg("hero-bladestorm", x, y, z)
				end
			elseif e.kind == "meteors" or e.kind == "sunbeam" then
				-- the finale
				if e.nova and heroes[e.owner] then
					local owner = heroes[e.owner]
					delayed[#delayed + 1] = { frame = f + 70, fn = function()
						if heroes[e.owner] then
							nukeAt(owner, e.x, e.z)
						end
					end }
				end
			end
		end
		events = keep

		-- burning trail of Hellcharge
		for unitID, h in pairs(heroes) do
			if h.buff and h.buff.expire > f and h.buff.trailDmg then
				local x, y, z = heroPos(unitID)
				if x then
					damageArea(x, z, 160, spGetUnitAllyTeam(unitID), h.buff.trailDmg * 0.2, unitID)
					ceg("hero-firepatch", x, y, z)
				end
			end
		end
	end

	-- guard / dome / command aura sets, every 0.5 s
	local function refreshProtection(f)
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
						ceg(e.kind == "dome" and "hero-dome" or "hero-guard", x, y, z)
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
		local healBest = {}
		for unitID, h in pairs(heroes) do
			local x, y, z = heroPos(unitID)
			if x then
				local ally = spGetUnitAllyTeam(unitID)
				local cfg = h.def.cfg
				local hp, maxHp = spGetUnitHealth(unitID)
				-- buff expiry
				if h.buff and h.buff.expire <= f then
					h.buff = nil
					applyStats(unitID, h)
				end
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
				for _, key in ipairs({ "a1", "a2" }) do
					local b = cfg[key]
					local r = rankOf(h, key)
					if r > 0 then
						if f % 60 < 30 and (b.kind == "aura_heal" or b.kind == "aura_damage") then
							ceg(b.kind == "aura_heal" and "hero-aura-heal" or "hero-aura-command", x, y, z)
						end
						if b.kind == "aura_heal" then
							for _, uid in ipairs(alliesIn(x, z, b.radius[r], ally)) do
								if (healBest[uid] or 0) < b.rate[r] then
									healBest[uid] = uid == unitID and b.rate[r] * 0.5 or b.rate[r]
								end
							end
						elseif b.kind == "aura_damage" then
							for _, uid in ipairs(alliesIn(x, z, b.radius, ally)) do
								if uid ~= unitID then
									auraDamage[uid] = max(auraDamage[uid] or 0, b.mult[r])
								end
							end
						elseif b.kind == "aura_burn" then
							local hit = damageArea(x, z, b.radius[r], ally, b.dps[r], unitID)
							for i = 1, min(4, 1 + #hit) do
								local px, pz = randomPointIn(x, z, b.radius[r] * 0.9)
								ceg("hero-firepatch", px, spGetGroundHeight(px, pz), pz)
							end
						elseif b.kind == "aura_emp" and f % (b.period * GAME_SPEED) < GAME_SPEED then
							local hit = enemiesIn(x, z, b.radius[r], ally)
							for i, uid in ipairs(hit) do
								spAddUnitDamage(uid, b.dmg[r], 0, unitID)
								spAddUnitDamage(uid, b.emp[r], 2, unitID)
								if i <= 6 then
									local ux, uy, uz = spGetUnitPosition(uid)
									ceg("hero-static", ux, uy, uz)
								end
							end
						end
					end
				end
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
				-- shield capacity (Aegis) and shield recharge boosts (Siege Protocol)
				local num = h.def.shieldNum
				if num then
					local enabled, power = Spring.GetUnitShieldState(unitID, num)
					if power then
						local cap, regenMult = h.def.shieldPower, 1
						local b = cfg.a1
						if b.kind == "shield_cap" then
							local r = rankOf(h, "a1")
							cap = h.def.shieldPower * (r > 0 and b.cap[r] or b.base)
							regenMult = r > 0 and b.regen[r] or 1
						end
						if h.buff and h.buff.fx.shieldRegen then
							regenMult = regenMult * h.buff.fx.shieldRegen
						end
						local p = min(cap, power + h.def.shieldRegen * (regenMult - 1))
						if p ~= power then
							Spring.SetUnitShieldState(unitID, num, true, p)
						end
					end
				end
			end
		end
		for uid, rate in pairs(healBest) do
			local hp, maxHp, _, _, bp = spGetUnitHealth(uid)
			if hp and bp and bp >= 1 and hp < maxHp then
				spSetUnitHealth(uid, min(maxHp, hp + rate))
			end
		end
	end

	---------------------------------------------------------------- autocast (AI always, players with autocast on)

	local function visibleTo(uid, ally)
		local los = spGetUnitLosState(uid, ally, true)
		return los and los ~= 0
	end

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
					sum = sum + costOf(uid)
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

	local AUTO_MIN = 2500 -- metal of enemies that justifies an area ability

	local function autocast(unitID, h)
		local x, y, z = heroPos(unitID)
		if not x then
			return
		end
		local ally = spGetUnitAllyTeam(unitID)
		local hp, maxHp = spGetUnitHealth(unitID)
		local hpFrac = hp and maxHp and hp / maxHp or 1
		local cfg = h.def.cfg
		for _, key in ipairs({ "ult", "a1", "a2" }) do
			local b = cfg[key]
			if b and cast[b.kind] and abilityReady(h, key) then
				local r = rankOf(h, key)
				local k = b.kind
				if k == "active_guard" or k == "active_dome" then
					local near = enemyCostNear(x, z, 1100, ally)
					if near > h.def.cost * 0.4 or (hpFrac < 0.5 and near > 0) then
						tryCast(unitID, h, key)
					end
				elseif k == "active_pulse" then
					local _, power = Spring.GetUnitShieldState(unitID, h.def.shieldNum)
					local near = enemyCostNear(x, z, b.radius[r], ally)
					if power and power > h.def.shieldPower * 0.2 and near > AUTO_MIN then
						tryCast(unitID, h, key)
					end
				elseif k == "active_stomp" or k == "active_flare" or k == "active_bladestorm" then
					local rad = type(b.radius) == "table" and b.radius[r] or b.radius
					if enemyCostNear(x, z, rad, ally) > AUTO_MIN then
						tryCast(unitID, h, key)
					end
				elseif k == "active_buff" then
					local reach = 0
					for _, w in pairs(h.def.weapons) do
						reach = max(reach, w.range)
					end
					if b.buff.speed and not b.buff.reload then
						reach = reach * 1.6 -- a charge closes in
					end
					if Spring.GetUnitNearestEnemy(unitID, reach, true) then
						tryCast(unitID, h, key)
					end
				elseif k == "active_storm" or k == "active_meteors" or k == "active_sunbeam" then
					local score, tx, tz = bestCluster(x, z, castRange(b, r), b.radius, ally)
					if tx and score > AUTO_MIN then
						tryCast(unitID, h, key, tx, tz)
					end
				elseif k == "active_spear" then
					local target, value = mostValuableEnemy(x, z, castRange(b, r), ally)
					if target and value >= 3000 then
						tryCast(unitID, h, key, nil, nil, target)
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
	-- v15: every AI hero takes an escort of 6-15 army units from the AI (detach, given back with attach): they
	-- screen the hero on the march, focus the enemies that shoot it, and stand between it and the enemy while
	-- it retreats. The hero stays inside its army (a front hero at most AI_FRONT_LEAD ahead of the escort),
	-- does not walk into static defence, hunts weaker enemy heroes and steps back from stronger ones, dodges
	-- nukes. Hero producers that the AI script does not drive (the T2 hero halls) are run from here.
	-- infolog: "[heroai] ..." lines.
	local aiHero, aiEconomy, aiMakers, aiSummary, aiEscortsTick
	local escorts = {} -- heroID -> { units = { uid = true }, n }
	local bank = {}    -- teamID -> metal the AI put aside for ranks and levels
	do -- a block: its helpers do not count toward the chunk's limit of 200 locals

	local armyDefs = {} -- mobile ground combat units the heroes escort
	local armedDefs = {} -- anything with a weapon (danger estimate)
	for udid, ud in pairs(UnitDefs) do
		if ud.canMove and not ud.canFly and not ud.isBuilder and #ud.weapons > 0 and (ud.speed or 0) > 0 and not heroDefs[udid] then
			armyDefs[udid] = true
		end
		if #ud.weapons > 0 then
			armedDefs[udid] = true
		end
	end

	-- units that build heroes (T4 altars, T2 hero halls): hero unitDefIDs in build order
	local heroMakers = {}
	for udid, ud in pairs(UnitDefs) do
		for _, opt in ipairs(ud.buildOptions or {}) do
			if heroDefs[opt] then
				heroMakers[udid] = heroMakers[udid] or {}
				heroMakers[udid][#heroMakers[udid] + 1] = opt
			end
		end
	end
	-- these the AI script builds with (Factory::AiMakeTask); the gadget runs every other hero producer
	local scriptMakers = { armt4gant = true, cort4gant = true, legt4gant = true }
	local makerList = {}
	for udid in pairs(heroMakers) do
		if not scriptMakers[UnitDefs[udid].name] then
			makerList[#makerList + 1] = udid
		end
	end

	-- projectiles worth running from: nukes, heavy artillery, hero warheads
	local bigShot = {}
	for wdid, wd in pairs(WeaponDefs) do
		local aoe = wd.damageAreaOfEffect or 0
		if aoe >= 350 then
			bigShot[wdid] = aoe
		end
	end

	local escortOf = {} -- uid -> heroID
	local aiStats = {}  -- teamID -> counters for the periodic infolog line

	local function gameTime(f)
		return string.format("%d:%02d", floor(f / 1800), floor(f / 30) % 60)
	end

	local function aiLog(f, teamID, fmt, ...)
		Spring.Echo(string.format("[heroai] t=%s team=%d ", gameTime(f), teamID) .. string.format(fmt, ...))
	end

	local function stat(teamID, key, n)
		local s = aiStats[teamID]
		if not s then
			s = {}
			aiStats[teamID] = s
		end
		s[key] = (s[key] or 0) + (n or 1)
	end

	local function isMaker(udid)
		return foundryDefs[udid] or heroMakers[udid]
	end

	local function retreatPoint(teamID, x, z)
		local best, bx, bz
		for _, uid in ipairs(Spring.GetTeamUnits(teamID)) do
			local udid = spGetUnitDefID(uid)
			local prio = isMaker(udid) and 1 or (factoryDefs[udid] and 2 or nil)
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
	-- (escorts do not count: a hero must not follow its own bodyguard)
	local armyCache = {} -- teamID -> { frame, x, z, cost }
	local function armyGroup(teamID, f)
		local c = armyCache[teamID]
		if c and f - c.frame < 55 then
			return c
		end
		local cells = {}
		for _, uid in ipairs(Spring.GetTeamUnits(teamID)) do
			local udid = spGetUnitDefID(uid)
			if armyDefs[udid] and not escortOf[uid] then
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
		x = max(64, min(Game.mapSizeX - 64, x))
		z = max(64, min(Game.mapSizeZ - 64, z))
		Spring.GiveOrderToUnit(unitID, cmd, { x, spGetGroundHeight(x, z), z }, 0)
	end

	-- a hero's fighting weight: metal cost at its grown strength and current health
	local function heroPower(uid, h)
		local hp, maxHp = spGetUnitHealth(uid)
		local frac = hp and maxHp and maxHp > 0 and hp / maxHp or 1
		return h.def.cost * (h.hpMult or 1) * (h.dmgMult or 1) * frac
	end

	-- enemy metal around vs allied metal around: enemy heroes at their grown strength, static defence x1.5,
	-- unarmed things x0.1, only what the team can see. Returns the ratio, the enemy centre and the enemy heroes.
	local function danger(unitID, h, x, z)
		local ally = spGetUnitAllyTeam(unitID)
		local enemy, friend, ex, ez = 0, 0, 0, 0
		local foes
		for _, uid in ipairs(spGetUnitsInCylinder(x, z, 1300)) do
			local a = spGetUnitAllyTeam(uid)
			local udid = spGetUnitDefID(uid)
			local c = unitCost[udid] or 0
			local hh = heroes[uid]
			if a == ally then
				if hh then
					friend = friend + heroPower(uid, hh)
				elseif armedDefs[udid] then
					friend = friend + c
				end
			elseif not spGetUnitIsDead(uid) and visibleTo(uid, ally) then
				local w = c
				if hh then
					w = heroPower(uid, hh)
					foes = foes or {}
					foes[#foes + 1] = uid
				elseif not armedDefs[udid] then
					w = c * 0.1
				elseif structureDefs[udid] then
					w = c * 1.5
				end
				local ux, _, uz = spGetUnitPosition(uid)
				if ux then
					enemy = enemy + w
					ex, ez = ex + ux * w, ez + uz * w
				end
			end
		end
		if enemy > 0 then
			ex, ez = ex / enemy, ez / enemy
		else
			ex, ez = nil, nil
		end
		return enemy / max(1, friend), ex, ez, foes, enemy, friend
	end

	-- visible enemy static defence (armed structures) around a point, in metal
	local function defenceNear(x, z, r, ally)
		local sum = 0
		for _, uid in ipairs(spGetUnitsInCylinder(x, z, r)) do
			local udid = spGetUnitDefID(uid)
			if structureDefs[udid] and armedDefs[udid] and isEnemyOf(uid, ally) and visibleTo(uid, ally) then
				sum = sum + (unitCost[udid] or 0)
			end
		end
		return sum
	end

	-- a nuke / heavy shell about to land near the hero: the point and the blast radius
	local function incomingBlast(x, z, ally)
		local projs = Spring.GetProjectilesInRectangle(x - 1600, z - 1600, x + 1600, z + 1600, false, false)
		for _, p in ipairs(projs or {}) do
			local aoe = bigShot[Spring.GetProjectileDefID(p) or -1]
			if aoe then
				local team = Spring.GetProjectileTeamID(p)
				local pAlly = team and select(6, Spring.GetTeamInfo(team, false))
				if pAlly and pAlly ~= ally then
					local tx, tz
					local ttype, target = Spring.GetProjectileTarget(p)
					if type(target) == "table" then
						tx, tz = target[1], target[3]
					elseif type(target) == "number" and ttype == string.byte("u") then
						tx, _, tz = spGetUnitPosition(target)
					end
					if not tx then
						tx, _, tz = Spring.GetProjectilePosition(p)
					end
					if tx and (tx - x) ^ 2 + (tz - z) ^ 2 < (aoe + 200) ^ 2 then
						return tx, tz, aoe
					end
				end
			end
		end
	end

	---------------------------------------------------------------- escorts

	local function escortList(heroID)
		local e = escorts[heroID]
		local out = {}
		if e then
			for uid in pairs(e.units) do
				out[#out + 1] = uid
			end
		end
		return out
	end

	local function escortRelease(heroID, teamID, why, f, only)
		local e = escorts[heroID]
		if not e then
			return
		end
		local ids = {}
		for _, uid in ipairs(only or escortList(heroID)) do
			if e.units[uid] then
				e.units[uid] = nil
				e.n = e.n - 1
				escortOf[uid] = nil
				if spValidUnitID(uid) and not spGetUnitIsDead(uid) and spGetUnitTeam(uid) == teamID then
					Spring.GiveOrderToUnit(uid, CMD.STOP, {}, 0)
					ids[#ids + 1] = uid
				end
			end
		end
		if #ids > 0 then
			toAI(teamID, "attach " .. table.concat(ids, ","))
			if why then
				local h = heroes[heroID]
				aiLog(f, teamID, "%s escort released %d units (%s), %d left", h and h.def.name or ("hero " .. heroID), #ids, why, e.n)
				stat(teamID, "released", #ids)
			end
		end
		if e.n <= 0 then
			escorts[heroID] = nil
		end
	end

	-- drop dead / given-away units, then take nearby army units from the AI up to the escort size
	local function escortRecruit(heroID, h, x, z, g, f)
		local e = escorts[heroID]
		if not e then
			e = { units = {}, n = 0 }
			escorts[heroID] = e
		end
		local cost = 0
		for uid in pairs(e.units) do
			if not spValidUnitID(uid) or spGetUnitIsDead(uid) or spGetUnitTeam(uid) ~= h.team then
				e.units[uid] = nil
				e.n = e.n - 1
				escortOf[uid] = nil
			else
				cost = cost + costOf(uid)
			end
		end
		local want = min(h.def.cost * H.AI_ESCORT_COST, max(g.cost / 3, h.def.cost * 0.15))
		if e.n >= H.AI_ESCORT_MAX or (e.n >= H.AI_ESCORT_MIN and cost >= want) then
			return
		end
		local taken = GG.AICommanderUnits or {}
		local cands = {}
		for _, uid in ipairs(spGetUnitsInCylinder(x, z, H.AI_ESCORT_RADIUS, h.team)) do
			local udid = spGetUnitDefID(uid)
			if armyDefs[udid] and not escortOf[uid] and not heroes[uid] and not taken[uid]
				and not Spring.GetUnitTransporter(uid) then
				local _, _, _, _, bp = spGetUnitHealth(uid)
				local ux, _, uz = spGetUnitPosition(uid)
				if bp and bp >= 1 and ux then
					cands[#cands + 1] = { uid = uid, d = (ux - x) ^ 2 + (uz - z) ^ 2, c = unitCost[udid] or 0 }
				end
			end
		end
		table.sort(cands, function(a, b) return a.d < b.d end)
		local ids = {}
		for _, cand in ipairs(cands) do
			if e.n >= H.AI_ESCORT_MAX or (e.n >= H.AI_ESCORT_MIN and cost >= want) then
				break
			end
			e.units[cand.uid] = true
			e.n = e.n + 1
			escortOf[cand.uid] = heroID
			cost = cost + cand.c
			ids[#ids + 1] = cand.uid
		end
		if #ids > 0 then
			toAI(h.team, "detach " .. table.concat(ids, ","))
			e.lastOrder = nil
			aiLog(f, h.team, "%s escort +%d -> %d units (%d metal)", h.def.name, #ids, e.n, cost)
			stat(h.team, "escorted", #ids)
		end
	end

	-- escort orders: march = a screen ahead of and around the hero; cover = a line between the retreating
	-- hero and the enemy; a hero under fire gets its attackers focused
	local function escortOrders(heroID, h, x, z, mode, dx, dz, f)
		local e = escorts[heroID]
		if not e or e.n <= 0 then
			return
		end
		local ally = spGetUnitAllyTeam(heroID)
		-- the nearest enemy that shot the hero within 3 s
		local focus, fd
		for att, fr in pairs(h.attackers or {}) do
			if f - fr > 90 or not spValidUnitID(att) or spGetUnitIsDead(att) then
				h.attackers[att] = nil
			elseif visibleTo(att, ally) then
				local ax, _, az = spGetUnitPosition(att)
				local d = ax and (ax - x) ^ 2 + (az - z) ^ 2
				if d and d < 1400 * 1400 and (not fd or d < fd) then
					focus, fd = att, d
				end
			end
		end
		if h.focusHero and spValidUnitID(h.focusHero) and not spGetUnitIsDead(h.focusHero) then
			focus = h.focusHero
		end
		if focus and focus ~= e.focus then
			e.focus = focus
			stat(h.team, "focus")
		end
		local reissue = not e.lastOrder or f - e.lastOrder >= 60
		if not reissue and not (focus and focus ~= e.lastFocus) then
			return
		end
		e.lastOrder = f
		e.lastFocus = focus
		local ids = escortList(heroID)
		local n = #ids
		local px, pz = -dz, dx -- lateral
		for i, uid in ipairs(ids) do
			local ux, _, uz = spGetUnitPosition(uid)
			if ux then
				local sx, sz
				if mode == "cover" then
					-- a line across the way the enemy comes, 250 in front of the hero
					local lat = (i - (n + 1) / 2) * 70
					sx, sz = x + dx * 250 + px * lat, z + dz * 250 + pz * lat
				else
					-- a screen: the front half-circle around the hero, 220 out
					local a = (i - 0.5) / n * 3.4 - 1.7
					local ca, sa = math.cos(a), math.sin(a)
					sx, sz = x + (dx * ca - px * sa) * 220, z + (dz * ca - pz * sa) * 220
				end
				if focus and (mode == "cover" or (ux - x) ^ 2 + (uz - z) ^ 2 < 1100 * 1100) then
					Spring.GiveOrderToUnit(uid, CMD.ATTACK, { focus }, 0)
					Spring.GiveOrderToUnit(uid, CMD.FIGHT, { sx, spGetGroundHeight(sx, sz), sz }, CMD.OPT_SHIFT)
				elseif (ux - sx) ^ 2 + (uz - sz) ^ 2 > 120 * 120 or Spring.GetUnitCommandCount(uid) == 0 then
					sx = max(64, min(Game.mapSizeX - 64, sx))
					sz = max(64, min(Game.mapSizeZ - 64, sz))
					Spring.GiveOrderToUnit(uid, CMD.FIGHT, { sx, spGetGroundHeight(sx, sz), sz }, 0)
				end
			end
		end
	end

	local function escortCentre(heroID)
		local e = escorts[heroID]
		if not e or e.n <= 0 then
			return nil
		end
		local sx, sz, n = 0, 0, 0
		for uid in pairs(e.units) do
			local ux, _, uz = spGetUnitPosition(uid)
			if ux then
				sx, sz, n = sx + ux, sz + uz, n + 1
			end
		end
		if n == 0 then
			return nil
		end
		return sx / n, sz / n, n
	end

	local function unitDir(ax, az, bx, bz)
		local dx, dz = bx - ax, bz - az
		local d = sqrt(dx * dx + dz * dz)
		if d < 1 then
			return 0, 0, 0
		end
		return dx / d, dz / d, d
	end

	---------------------------------------------------------------- retreat

	local function startRetreat(unitID, h, x, z, f, why, ex, ez)
		local rx, rz = retreatPoint(h.team, x, z)
		if not rx then
			return
		end
		h.retreating = true
		h.retreatX, h.retreatZ = rx, rz
		h.threatX, h.threatZ = ex, ez
		h.focusHero = nil
		orderMove(unitID, h, CMD.MOVE, rx, rz, f)
		spSetUnitRulesParam(unitID, "hero_retreat", 1, ALLIED)
		-- cover the way back
		for _, key in ipairs({ "a1", "a2", "ult" }) do
			local b = h.def.cfg[key]
			if b and (b.kind == "active_guard" or b.kind == "active_dome" or b.kind == "active_shield" or b.kind == "active_cloak"
				or (b.kind == "active_buff" and b.buff and (b.buff.speed or b.buff.armor or b.buff.cloak))) then
				tryCast(unitID, h, key)
			end
		end
		local hp, maxHp = spGetUnitHealth(unitID)
		local e = escorts[unitID]
		aiLog(f, h.team, "%s L%d retreats (%s) hp=%d%%, escort of %d covers", h.def.name, h.level, why,
			floor(100 * (hp or 0) / max(1, maxHp or 1)), e and e.n or 0)
		stat(h.team, "retreats")
		if e and e.n > 0 then
			stat(h.team, "covered")
		end
	end

	function aiHero(unitID, h, f)
		local hp, maxHp = spGetUnitHealth(unitID)
		if not hp then
			return
		end
		local frac = hp / maxHp
		local x, _, z = heroPos(unitID)
		local ally = spGetUnitAllyTeam(unitID)
		if not h.detached then
			h.detached = true
			toAI(h.team, "detach " .. unitID)
		end
		-- health 5 seconds ago: a burst (artillery, nukes) means getting out even far from any enemy
		h.hpHist = h.hpHist or {}
		local sec = floor(f / GAME_SPEED)
		h.hpHist[sec % 6] = frac
		local before = h.hpHist[(sec + 1) % 6] or frac
		-- a nuke or heavy shell on its way: step out of the blast first
		local bx, bz, aoe = incomingBlast(x, z, ally)
		if bx then
			local dx, dz = unitDir(bx, bz, x, z)
			if dx == 0 and dz == 0 then
				dx, dz = unitDir(x, z, retreatPoint(h.team, x, z))
			end
			orderMove(unitID, h, CMD.MOVE, x + dx * (aoe + 350), z + dz * (aoe + 350), f)
			h.dodgeUntil = f + 4 * GAME_SPEED
			if f - (h.lastDodgeLog or -9999) > 300 then
				h.lastDodgeLog = f
				aiLog(f, h.team, "%s dodges a blast (aoe %d)", h.def.name, aoe)
				stat(h.team, "dodges")
			end
			return
		end
		if h.dodgeUntil and f < h.dodgeUntil then
			return
		end
		if h.retreating then
			local back = H.AI_RETURN_HP
			if not fountainNear(h.team, h.retreatX, h.retreatZ) then
				back = H.AI_RETURN_HP_NO_FOUNTAIN
			end
			local home = (x - h.retreatX) ^ 2 + (z - h.retreatZ) ^ 2
			-- the escort stands between the hero and the enemy until it is home
			local ratio, ex, ez = danger(unitID, h, x, z)
			ex, ez = ex or h.threatX, ez or h.threatZ
			if ex then
				local dx, dz = unitDir(x, z, ex, ez)
				escortOrders(unitID, h, x, z, "cover", dx, dz, f)
			end
			if home < 700 * 700 and ratio < 0.5 and escorts[unitID] then
				escortRelease(unitID, h.team, "hero is home", f)
			end
			if frac >= back then
				h.retreating = false
				spSetUnitRulesParam(unitID, "hero_retreat", 0, ALLIED)
				aiLog(f, h.team, "%s back in the fight at %d%% hp", h.def.name, floor(frac * 100))
			elseif f - (h.lastOrder or 0) > 5 * GAME_SPEED and home > 400 * 400
				and Spring.GetUnitCommandCount(unitID) == 0 then
				orderMove(unitID, h, CMD.MOVE, h.retreatX, h.retreatZ, f)
			end
			return
		end
		local ratio, ex, ez, foes, enemy, friend = danger(unitID, h, x, z)
		-- the strongest enemy hero in sight vs this one
		local myPow = heroPower(unitID, h)
		local foe, foePow
		for _, uid in ipairs(foes or {}) do
			local p = heroPower(uid, heroes[uid])
			if not foePow or p > foePow then
				foe, foePow = uid, p
			end
		end
		local why
		if frac < H.AI_RETREAT_HP then
			why = "low hp"
		elseif frac < H.AI_CAUTION_HP and ratio > H.AI_DANGER then
			why = string.format("outnumbered x%.1f", ratio)
		elseif frac < 0.85 and ratio > H.AI_DANGER * 2.5 then
			why = string.format("overwhelmed x%.1f", ratio)
		elseif before - frac > H.AI_BURST and frac < 0.8 then
			why = "burst damage"
		elseif foe and foePow > myPow * 1.5 and frac < 0.75 and ratio > 0.8 then
			why = "stronger enemy hero " .. heroes[foe].def.name
		end
		if why then
			startRetreat(unitID, h, x, z, f, why, ex, ez)
			return
		end
		-- march with the army
		local g = armyGroup(h.team, f)
		local e = escorts[unitID]
		local escortCost = 0
		if e then
			for uid in pairs(e.units) do
				escortCost = escortCost + costOf(uid)
			end
		end
		local tx, tz
		local dx, dz = 0, 0
		-- an escort worth a quarter of the hero, at most 10k metal (the expensive heroes otherwise waited
		-- at the altar for an army cell of 35-45k that the AI rarely gathers); the hero's own escort counts
		if g.x and g.cost + escortCost >= min(h.def.cost * 0.25, H.AI_ESCORT) then
			local off = H.AI_ROLE_OFFSET[h.def.cfg.aiRole or "center"] or 0
			tx, tz = g.x, g.z
			if g.ex then
				dx, dz = unitDir(g.x, g.z, g.ex, g.ez)
			end
			-- enemy static defence ahead that the group cannot take: hang back behind the army
			local def = defenceNear(g.x + dx * 500, g.z + dz * 500, 1200, ally)
			if def > 0 and def * 1.5 > g.cost + escortCost then
				off = min(off, -250)
				if f - (h.lastDefLog or -9999) > 1800 then
					h.lastDefLog = f
					aiLog(f, h.team, "%s holds back: enemy defence %d metal ahead", h.def.name, def)
					stat(h.team, "holds")
				end
			end
			tx, tz = g.x + dx * off, g.z + dz * off
			escortRecruit(unitID, h, x, z, g, f)
		else
			-- no army to walk with: guard the altar, the escort goes back to the AI
			tx, tz = retreatPoint(h.team, x, z)
			if escorts[unitID] then
				escortRelease(unitID, h.team, "no army to march with", f)
			end
		end
		if not tx then
			return
		end
		-- enemy heroes: hunt a weaker one, step back from a stronger one
		h.focusHero = nil
		if foe then
			if myPow >= foePow * 1.25 and ratio < 1.2 then
				h.focusHero = foe
				if h.lastHunt ~= foe then
					h.lastHunt = foe
					aiLog(f, h.team, "%s hunts enemy hero %s (power %d vs %d)", h.def.name, heroes[foe].def.name, myPow, foePow)
					stat(h.team, "hunts")
				end
			elseif foePow > myPow * 1.3 then
				local cx, cz = escortCentre(unitID)
				cx, cz = cx or g.x or x, cz or g.z or z
				tx, tz = cx - dx * 250, cz - dz * 250
				if h.lastAvoid ~= foe then
					h.lastAvoid = foe
					aiLog(f, h.team, "%s avoids enemy hero %s (power %d vs %d)", h.def.name, heroes[foe].def.name, myPow, foePow)
					stat(h.team, "avoids")
				end
			end
		end
		-- inside the army: never more than AI_FRONT_LEAD ahead of the escort
		local cx, cz = escortCentre(unitID)
		if cx and (dx ~= 0 or dz ~= 0) then
			local lead = (tx - cx) * dx + (tz - cz) * dz
			if lead > H.AI_FRONT_LEAD * 0.7 then
				tx, tz = tx - dx * (lead - H.AI_FRONT_LEAD * 0.7), tz - dz * (lead - H.AI_FRONT_LEAD * 0.7)
			end
			local ahead = (x - cx) * dx + (z - cz) * dz
			if ahead > H.AI_FRONT_LEAD and not h.focusHero then
				-- too far out: back to the escort (a move, not a fight: no chasing)
				if f - (h.lastOrder or 0) > 2 * GAME_SPEED then
					orderMove(unitID, h, CMD.MOVE, cx + dx * 120, cz + dz * 120, f)
					stat(h.team, "pullbacks")
				end
				escortOrders(unitID, h, x, z, "march", dx, dz, f)
				return
			end
		end
		if h.focusHero then
			if h.lastFocusOrder ~= h.focusHero or f - (h.lastOrder or 0) > 5 * GAME_SPEED then
				h.lastFocusOrder = h.focusHero
				h.lastOrder = f
				Spring.GiveOrderToUnit(unitID, CMD.ATTACK, { h.focusHero }, 0)
			end
		else
			h.lastFocusOrder = nil
			tx = max(64, min(Game.mapSizeX - 64, tx))
			tz = max(64, min(Game.mapSizeZ - 64, tz))
			local moved = not h.orderX or (tx - h.orderX) ^ 2 + (tz - h.orderZ) ^ 2 > 350 * 350
			local far = (tx - x) ^ 2 + (tz - z) ^ 2 > 300 * 300
			if (moved and far) or (far and Spring.GetUnitCommandCount(unitID) == 0) then
				orderMove(unitID, h, CMD.FIGHT, tx, tz, f)
			end
		end
		if dx == 0 and dz == 0 and ex then
			dx, dz = unitDir(x, z, ex, ez)
		end
		if dx ~= 0 or dz ~= 0 then
			escortOrders(unitID, h, x, z, "march", dx, dz, f)
		end
	end

	---------------------------------------------------------------- AI economy: hero producers, ranks, levels

	-- T2 hero halls (and any hero producer the AI script does not drive): one of each hero, a dead one again
	function aiMakers(f)
		for teamID, ai in pairs(isAITeam) do
			if ai and #makerList > 0 then
				for _, m in ipairs(Spring.GetTeamUnitsByDefs(teamID, makerList) or {}) do
					local _, _, _, _, bp = spGetUnitHealth(m)
					if bp and bp >= 1 then
						local queue = Spring.GetFactoryCommands(m, -1)
						local busy = Spring.GetUnitIsBuilding(m) or (type(queue) == "table" and #queue > 0)
						if not busy then
							local udid = spGetUnitDefID(m)
							local pick, revive
							for _, hid in ipairs(heroMakers[udid]) do
								if Spring.GetTeamUnitDefCount(teamID, hid) == 0 then
									local isDead = dead[teamID] and dead[teamID][heroDefs[hid].name]
									if not pick or (revive and not isDead) then
										pick, revive = hid, isDead
									end
								end
							end
							if pick then
								toAI(teamID, "detach " .. m)
								Spring.GiveOrderToUnit(m, -pick, {}, 0)
								aiLog(f, teamID, "%s %s %s", UnitDefs[udid].name, revive and "revives" or "builds", heroDefs[pick].name)
								stat(teamID, revive and "revives" or "built")
							end
						end
					end
				end
			end
		end
	end

	-- a dead hero one of the team's producers can rebuild: the revive gets the metal first
	local function reviveWanted(teamID)
		local d = dead[teamID]
		if not d or next(d) == nil then
			return false
		end
		for _, uid in ipairs(Spring.GetTeamUnits(teamID)) do
			local opts = heroMakers[spGetUnitDefID(uid)]
			if opts then
				for _, hid in ipairs(opts) do
					if d[heroDefs[hid].name] and Spring.GetTeamUnitDefCount(teamID, hid) == 0 then
						return heroDefs[hid].name
					end
				end
			end
		end
		return false
	end

	local reviveLog = {}
	local ROLE_WEIGHT = { front = 1.2, center = 1.0, back = 0.7 }

	-- The AI's hero bank: storage is small (the AI builds no metal storage), so the price of a rank or a
	-- level (tens to hundreds of thousands) is put aside over time - only overflow metal (storage fuller
	-- than AI_BUY_FULL), at most AI_BUY_SAVE of the income, and nothing while a dead hero waits for its
	-- revive (then the bank flows back into the storage). The bank pays for unspent points first (the
	-- same plan as learnAI), then for levels of the best hero: alive, not retreating, fighting roles and
	-- lower levels first, one level per BUY_COOLDOWN, up to AI_BUY_MAX_LEVEL.
	function aiEconomy(f)
		for teamID, ai in pairs(isAITeam) do
			if ai then
				local mine = {}
				for uid, h in pairs(heroes) do
					if h.team == teamID then
						mine[#mine + 1] = uid
					end
				end
				local revive = reviveWanted(teamID)
				if #mine > 0 or revive or (bank[teamID] or 0) > 0 then
					local cur, stor, _, inc = Spring.GetTeamResources(teamID, "metal")
					cur, stor, inc = cur or 0, stor or 0, inc or 0
					local b = bank[teamID] or 0
					if revive then
						local back = min(b, max(0, stor - cur), max(3000, b * 0.1))
						if back > 0 then
							Spring.AddTeamResource(teamID, "metal", back)
							b = b - back
							if f - (reviveLog[teamID] or -9999) > 1800 then
								reviveLog[teamID] = f
								aiLog(f, teamID, "saving paused: %s waits for its revive, %d metal back to storage (bank %d)", revive, back, b)
							end
						end
					elseif inc >= H.AI_BUY_INCOME and cur > stor * H.AI_BUY_FULL then
						local take = min(inc * H.AI_BUY_SAVE, cur - stor * H.AI_BUY_FULL)
						if take > 0 and Spring.UseTeamResource(teamID, "metal", take) then
							b = b + take
							stat(teamID, "saved", take)
						end
					end
					if not revive and #mine > 0 then
						-- best hero first
						local order = {}
						for _, uid in ipairs(mine) do
							local h = heroes[uid]
							local hp, maxHp = spGetUnitHealth(uid)
							local score = (ROLE_WEIGHT[h.def.cfg.aiRole or "center"] or 1) / (1 + h.level / 30)
							if h.retreating then
								score = score * 0.3
							end
							if hp and maxHp and hp / maxHp < 0.5 then
								score = score * 0.5
							end
							order[#order + 1] = { uid = uid, h = h, score = score }
						end
						table.sort(order, function(a, c) return a.score > c.score end)
						-- unspent points: ranks paid from the bank
						local saving = false
						for _, o in ipairs(order) do
							local h = o.h
							if h.level - #h.picks > 0 then
								prepaid = b
								local picks = #h.picks
								learnAI(o.uid, h)
								if #h.picks > picks then
									aiLog(f, teamID, "%s L%d learns %d rank(s) from the bank (%d -> %d)", h.def.name, h.level, #h.picks - picks, b, prepaid)
									stat(teamID, "ranks", #h.picks - picks)
								end
								b = prepaid
								-- still points and a rank waits only for metal: save for it, no levels meanwhile
								if h.level - #h.picks > 0 then
									for _, key in ipairs(h.def.keys) do
										if learnState(h, key) == "metal" then
											saving = true
											break
										end
									end
								end
								prepaid = 0
							end
						end
						local top = order[1]
						local h = top and top.h
						if h and not saving and h.level < H.AI_BUY_MAX_LEVEL and f >= (h.buyReady or 0) then
							local price = H.levelPrice(h.def.name, h.level, h.def.cost)
							if price and b >= price then
								b = b - price
								local from = h.level
								buyLevel(top.uid, h, true)
								aiLog(f, teamID, "%s buys level %d -> %d for %d metal (bank left %d, income %d)", h.def.name, from, h.level, price, b, inc)
								stat(teamID, "levels")
								stat(teamID, "levelMetal", price)
							end
						end
					end
					bank[teamID] = b
					spSetTeamRulesParam(teamID, "hero_ai_bank", floor(b), ALLIED)
				end
			end
		end
	end

	-- every 2 minutes: what the AI heroes of each team are doing
	function aiSummary(f)
		for teamID, ai in pairs(isAITeam) do
			if ai then
				local parts = {}
				for uid, h in pairs(heroes) do
					if h.team == teamID then
						local hp, maxHp = spGetUnitHealth(uid)
						local e = escorts[uid]
						parts[#parts + 1] = string.format("%s L%d %d%% %s esc=%d", h.def.name, h.level, floor(100 * (hp or 0) / max(1, maxHp or 1)),
							h.retreating and "retreat" or (h.focusHero and "hunt" or "march"), e and e.n or 0)
					end
				end
				local s = aiStats[teamID] or {}
				if #parts > 0 or next(s) then
					local cur, stor, _, inc = Spring.GetTeamResources(teamID, "metal")
					aiLog(f, teamID, "summary bank=%d metal=%d/%d income=%d saved=%d levels=%d (%d metal) ranks=%d escorted=%d released=%d retreats=%d covered=%d focus=%d hunts=%d avoids=%d holds=%d pullbacks=%d dodges=%d built=%d revives=%d | %s",
						bank[teamID] or 0, cur or 0, stor or 0, inc or 0, s.saved or 0, s.levels or 0, s.levelMetal or 0, s.ranks or 0,
						s.escorted or 0, s.released or 0, s.retreats or 0, s.covered or 0, s.focus or 0, s.hunts or 0, s.avoids or 0,
						s.holds or 0, s.pullbacks or 0, s.dodges or 0, s.built or 0, s.revives or 0, table.concat(parts, "; "))
				end
			end
		end
	end

	-- escorts of heroes that are gone go back to the AI
	function aiEscortsTick(f)
		for heroID in pairs(escorts) do
			local h = heroes[heroID]
			if not h then
				local team
				for uid in pairs(escorts[heroID].units) do
					team = team or spGetUnitTeam(uid)
				end
				if team then
					escortRelease(heroID, team, "hero fell", f)
				end
				escorts[heroID] = nil
			end
		end
	end
	end -- AI heroes

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
		if f % 15 == 11 then
			expireGround(f)
			pickups()
			if groundDirty then
				publishGround()
			end
		end
		-- AI heroes' escorts, bank, hero halls (v15); also with no hero on the field yet
		if f % 30 == 17 then
			aiEscortsTick(f)
			aiEconomy(f)
			if f % 150 == 17 then
				aiMakers(f)
			end
			if f % 3600 == 17 then
				aiSummary(f)
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
		elseif what == "buylevel" then
			buyLevel(uid, h)
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
			dead = dead, setAI = function(teamID, ai) isAITeam[teamID] = ai end,
			buyLevel = function(uid, paid) local h = heroes[uid]; if h then return buyLevel(uid, h, paid) end return false, "unknown" end,
			escorts = escorts, bank = bank }
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
