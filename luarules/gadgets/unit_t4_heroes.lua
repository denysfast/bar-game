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
--   t4hero:equip:<unitID>:<slot>_<stashIndex>[_<itemIndex>]   equip a team stash item into a slot of its category
--   t4hero:unequip:<unitID>:<slot>      the item goes back to the team stash
--   t4hero:use:<unitID>:<slot>          use an active item
-- Items: unit rules params hero_item_<slot> (item index, in LOS), hero_itemcd_<slot> (frame ready),
--   hero_itemcdlen_<slot>, hero_barrier; team rules params (allies) hero_stash_n, hero_stash_<i>, hero_stash_ver.
-- Unit rules params: hero_level (in LOS), hero_xp (0..1 to the next level), hero_points,
--   hero_rank_<branch>, hero_ready_<branch> (frame the ability is ready), hero_on_<branch> (frame an
--   active effect ends; in LOS), hero_retreat (AI care). Team rules params (allies):
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

	---------------------------------------------------------------- items: stats
	-- Equipped items (h.items[slot], slots 1..H.INVENTORY) add to the mods of sumMods. Stats in units (hp, speed,
	-- range, sight, radar) are turned into the fractions applyStats uses, from the hero's own base values, so the
	-- hero gets exactly that many HP / elmos; regen, income, auras, procs and the other specials are collected
	-- in h.itemFx and handled by the item code below (itemPassives, itemAttackMult, itemDefense, itemOnHit).

	local ITEM_FRACTIONS = { "damage", "armor", "reload", "splash", "burn", "lifesteal", "thorns", "cdr", "xp" }

	local function addItemMods(h, m)
		local def = h.def
		local fx = { regen = 0, income = 0, chains = {}, blasts = {}, zaps = {}, slayers = {}, executes = {} }
		local abs = { hp = 0, speed = 0, range = 0, sight = 0, radar = 0 }
		local critChance, critMult = 0, 0
		for slot = 1, H.INVENTORY do
			local id = h.items[slot]
			local it = id and H.items[id]
			if it then
				local st = it.stats
				for _, k in ipairs(ITEM_FRACTIONS) do
					if st[k] then
						m[k] = (m[k] or 0) + st[k]
					end
				end
				for k in pairs(abs) do
					if st[k] then
						abs[k] = abs[k] + st[k]
					end
				end
				fx.regen = fx.regen + (st.regen or 0)
				fx.income = fx.income + (st.income or 0)
				if st.crit then
					critChance = critChance + st.crit[1]
					critMult = max(critMult, st.crit[2])
				end
				if it.procChain then
					fx.chains[#fx.chains + 1] = { id = id, p = it.procChain }
				end
				if it.procBlast then
					fx.blasts[#fx.blasts + 1] = { id = id, p = it.procBlast }
				end
				if it.zap then
					fx.zaps[#fx.zaps + 1] = it.zap
				end
				if it.slayer then
					fx.slayers[#fx.slayers + 1] = it.slayer
				end
				if it.execute then
					fx.executes[#fx.executes + 1] = it.execute
				end
				if it.barrier then
					local b = fx.barrier or { cap = 0, regen = 0, delay = it.barrier.delay }
					b.cap = b.cap + it.barrier.cap
					b.regen = max(b.regen, it.barrier.regen)
					b.delay = min(b.delay, it.barrier.delay)
					fx.barrier = b
				end
				if it.lastStand and (not fx.lastStand or it.lastStand.armor > fx.lastStand.armor) then
					fx.lastStand = it.lastStand
				end
				if it.cheatDeath then
					fx.cheatDeath = it.cheatDeath
				end
				if it.aura then
					local a = fx.aura or { radius = 0, damage = 0, armor = 0, heal = 0 }
					a.radius = max(a.radius, it.aura.radius)
					a.damage = max(a.damage, it.aura.damage or 0)
					a.armor = max(a.armor, it.aura.armor or 0)
					a.heal = max(a.heal, it.aura.heal or 0)
					fx.aura = a
				end
			end
		end
		if critChance > 0 then
			m.crit = { min(0.5, critChance), critMult }
		end
		-- an Overcharge Cell in use
		local b = h.itemBuff
		if b and b.expire > spGetGameFrame() then
			m.damage = (m.damage or 0) + b.damage
			m.reload = (m.reload or 0) + b.reload
		end
		-- units -> fractions of the base values (hp: of the level-grown health, so +N HP is exactly N)
		local levelHp = 1 + H.LEVEL_HP * (h.level - 1)
		if abs.hp ~= 0 and def.health > 0 then
			m.hp = (m.hp or 0) + abs.hp / (def.health * levelHp)
		end
		if abs.speed ~= 0 and def.speed > 0 then
			m.speed = (m.speed or 0) + abs.speed / def.speed
		end
		if abs.sight ~= 0 and def.sight > 0 then
			m.sight = (m.sight or 0) + abs.sight / def.sight
		end
		if abs.radar ~= 0 and def.radar > 0 then
			m.radar = (m.radar or 0) + abs.radar / def.radar
		end
		if abs.range ~= 0 then
			local longest = 0
			for _, w in pairs(def.weapons) do
				if w.damage > 0 then
					longest = max(longest, w.range)
				end
			end
			if longest > 0 then
				m.range = (m.range or 0) + abs.range / longest
			end
		end
		fx.abs = abs
		h.itemFx = fx
	end


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
		addItemMods(h, m)
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
			items = {}, itemReady = {}, itemCd = {}, kills = 0,
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

	---------------------------------------------------------------- items: combat
	-- Hooks of the item specials in the damage callins (one line each there): itemAttackMult (slayer, execute),
	-- itemDefense (aura armor, last stand, shield and barrier absorb, cheat death, item invulnerability),
	-- itemOnHit (procs). Proc damage goes through UnitPreDamaged like any hero damage, so it grows with the
	-- hero's power.

	local itemGuard = {}      -- unitID -> damage taken reduction of an item aura (Bulwark Beacon), refreshed every second
	local itemProcReady = {}  -- "<hero>:<item>" -> frame the proc may fire again

	local function itemCeg(name, fallback, x, y, z)
		if x and not spSpawnCEG(name, x, y, z, 0, 1, 0, 0, 0) and fallback then
			spSpawnCEG(fallback, x, y, z, 0, 1, 0, 0, 0)
		end
	end

	local function itemAttackMult(a, victimID, victimDefID)
		local fx = a.itemFx
		if not fx then
			return 1
		end
		local mult = 1
		for _, s in ipairs(fx.slayers) do
			if (unitCost[victimDefID] or 0) >= s.minCost then
				mult = mult * (1 + s.mult)
			end
		end
		if #fx.executes > 0 then
			local hp, maxHp = spGetUnitHealth(victimID)
			if hp and maxHp and maxHp > 0 then
				for _, e in ipairs(fx.executes) do
					if hp / maxHp < e.below then
						mult = mult * (1 + e.mult)
					end
				end
			end
		end
		return mult
	end

	-- m: the damage multiplier so far; returns the new one (0: no damage)
	local function itemDefense(unitID, v, damage, m, paralyzer)
		local g = itemGuard[unitID]
		if g then
			m = m * (1 - g)
		end
		if not v or paralyzer or damage <= 0 then
			return m
		end
		local f = frameNow()
		if (v.itemInvulnUntil or 0) > f then
			return 0
		end
		local fx = v.itemFx
		if not fx then
			return m
		end
		local hp, maxHp = spGetUnitHealth(unitID)
		if fx.lastStand and hp and hp < maxHp * fx.lastStand.below then
			m = m * (1 - fx.lastStand.armor)
		end
		v.itemLastHit = f
		-- the active shield first, then the barrier; both hold effective HP
		local hpMult = v.hpMult or 1
		local eff = damage * m * hpMult
		local sh = v.itemShield
		if sh and sh.expire > f and sh.hp > 0 and eff > 0 then
			local take = min(eff, sh.hp)
			sh.hp = sh.hp - take
			eff = eff - take
		end
		if (v.itemBarrier or 0) > 0 and eff > 0 then
			local take = min(eff, v.itemBarrier)
			v.itemBarrier = v.itemBarrier - take
			eff = eff - take
		end
		m = eff / (damage * hpMult)
		local c = fx.cheatDeath
		if c and hp and damage * m >= hp and (v.itemCheatReady or 0) <= f then
			v.itemCheatReady = f + c.cooldown * GAME_SPEED
			v.itemInvulnUntil = f + c.invuln * GAME_SPEED
			spSetUnitRulesParam(unitID, "hero_item_cheat", v.itemCheatReady, ALLIED)
			delayed[#delayed + 1] = { frame = f + 1, fn = function()
				if heroes[unitID] then
					local _, mhp = spGetUnitHealth(unitID)
					spSetUnitHealth(unitID, mhp * c.heal)
					local x, y, z = spGetUnitPosition(unitID)
					itemCeg("hero-undying", "hero-revive", x, y, z)
					toUI("cheatdeath", unitID)
				end
			end }
			return 0
		end
		return m
	end

	local function itemOnHit(attackerID, h, victimID)
		local fx = h.itemFx
		if not fx or (#fx.chains == 0 and #fx.blasts == 0) then
			return
		end
		local f = frameNow()
		local ally = spGetUnitAllyTeam(attackerID)
		for _, c in ipairs(fx.chains) do
			local key = attackerID .. ":" .. c.id
			if (itemProcReady[key] or 0) <= f and random() < c.p.chance then
				itemProcReady[key] = f + floor(H.ITEM_PROC_ICD * GAME_SPEED)
				local hit = { [victimID] = true }
				local cur = victimID
				for j = 0, c.p.jumps do
					local x, y, z = spGetUnitPosition(cur)
					if not x then
						break
					end
					ceg("hero-zap", x, y, z)
					spAddUnitDamage(cur, c.p.dmg, 0, attackerID)
					local nxt, best
					for _, uid in ipairs(enemiesIn(x, z, c.p.radius, ally)) do
						if not hit[uid] then
							local ux, _, uz = spGetUnitPosition(uid)
							local d = (ux - x) ^ 2 + (uz - z) ^ 2
							if not best or d < best then
								nxt, best = uid, d
							end
						end
					end
					if not nxt then
						break
					end
					hit[nxt] = true
					cur = nxt
				end
			end
		end
		for _, b in ipairs(fx.blasts) do
			local key = attackerID .. ":" .. b.id
			if (itemProcReady[key] or 0) <= f and random() < b.p.chance then
				itemProcReady[key] = f + floor(H.ITEM_PROC_ICD * GAME_SPEED)
				local x, y, z = spGetUnitPosition(victimID)
				if x then
					itemCeg("hero-nova-fire", "hero-crit", x, y, z)
					damageArea(x, z, b.p.radius, ally, b.p.dmg, attackerID)
				end
			end
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
		if a then
			m = m * itemAttackMult(a, unitID, unitDefID) -- items: slayer / execute
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
		m = itemDefense(unitID, v, damage, m, paralyzer) -- items: aura armor, last stand, shields, cheat death
		if m <= 0 then
			return 0, 0
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
		itemOnHit(attackerID, h, unitID) -- items: procs
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
				-- item auras and the Crown of Storms: itemPassives
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

	---------------------------------------------------------------- items: team stash and equipment
	-- Every pickup goes to the picking hero's TEAM stash (H.STASH_SIZE). A full stash scraps the oldest item of
	-- its lowest rarity for metal (H.rarities[].scrap) - or the new item itself when nothing in the stash is
	-- rarer-or-equal cheaper than it, so a pickup never fails and never loses a better item.
	-- Team rules params (allies): hero_stash_n, hero_stash_<i> = item index (H.itemOrder), hero_stash_ver (bumped
	-- on every change). A hero equips per category slot (H.slotCategory: 1-3 weapon, 4-6 defense, 7-9 utility);
	-- the same item can't be worn twice by one hero. Item cooldowns stay with the hero per item (h.itemCd), so
	-- swapping an item out and in does not reset it.

	local stash = {}        -- teamID -> { item id, ... } oldest first
	local stashVer = {}     -- teamID -> version
	local aiEquipDirty = {} -- teamID -> true: re-equip the AI heroes of that team soon

	local function publishStash(teamID)
		local s = stash[teamID] or {}
		local oldN = Spring.GetTeamRulesParam(teamID, "hero_stash_n") or 0
		for i, id in ipairs(s) do
			spSetTeamRulesParam(teamID, "hero_stash_" .. i, H.itemIndex[id], ALLIED)
		end
		for i = #s + 1, max(oldN, #s) do
			spSetTeamRulesParam(teamID, "hero_stash_" .. i, 0, ALLIED)
		end
		spSetTeamRulesParam(teamID, "hero_stash_n", #s, ALLIED)
		stashVer[teamID] = (stashVer[teamID] or 0) + 1
		spSetTeamRulesParam(teamID, "hero_stash_ver", stashVer[teamID], ALLIED)
		aiEquipDirty[teamID] = true
	end

	-- into the team stash; returns true, or false + metal when the item (or another) was scrapped
	local function stashAdd(teamID, item, unitID)
		if not H.items[item] then
			return false
		end
		stash[teamID] = stash[teamID] or {}
		local s = stash[teamID]
		local scrapped, metal
		if #s >= H.STASH_SIZE then
			local lowRank, lowIdx = math.huge, nil
			for i, id in ipairs(s) do
				local r = H.rarities[H.items[id].rarity].rank
				if r < lowRank then
					lowRank, lowIdx = r, i
				end
			end
			if H.rarities[H.items[item].rarity].rank <= lowRank then
				scrapped = item
			else
				scrapped = table.remove(s, lowIdx)
			end
			metal = H.rarities[H.items[scrapped].rarity].scrap
			Spring.AddTeamResource(teamID, "metal", metal)
			toUI("scrap", unitID or -1, H.itemIndex[scrapped], metal)
		end
		if scrapped ~= item then
			s[#s + 1] = item
		end
		publishStash(teamID)
		return scrapped == nil, metal
	end

	local function stashRemoveAt(teamID, idx)
		local s = stash[teamID]
		local id = s and table.remove(s, idx)
		if id then
			publishStash(teamID)
		end
		return id
	end

	local function equippedSlotOf(h, item)
		for slot = 1, H.INVENTORY do
			if h.items[slot] == item then
				return slot
			end
		end
	end

	local function firstSlotFor(h, cat)
		local slots = H.itemCategories[cat].slots
		for _, slot in ipairs(slots) do
			if not h.items[slot] then
				return slot
			end
		end
		return slots[#slots]
	end

	-- put an item into a slot (no stash involved); the replaced one is returned
	local function setSlot(unitID, h, slot, item)
		local old = h.items[slot]
		if old then
			h.itemCd[old] = h.itemReady[slot]
		end
		h.items[slot] = item
		h.itemReady[slot] = item and h.itemCd[item] or nil
		return old
	end

	local function itemsChanged(unitID, h)
		applyStats(unitID, h)
		publishItems(unitID, h)
	end

	-- UI: equip stash item #idx (checked against item index `want` when given) into slot
	local function equipFromStash(unitID, h, slot, idx, want)
		local cat = H.slotCategory[slot]
		local s = stash[h.team]
		if not cat or not s then
			return false
		end
		if want and H.itemOrder[want] and s[idx] ~= H.itemOrder[want] then
			-- the stash moved under the click: take the first copy of that item
			idx = nil
			for i, id in ipairs(s) do
				if id == H.itemOrder[want] then
					idx = i
					break
				end
			end
		end
		local item = idx and s[idx]
		if not item or H.items[item].category ~= cat then
			return false
		end
		local other = equippedSlotOf(h, item)
		if other and other ~= slot then
			toUI("itemdup", unitID, H.itemIndex[item])
			return false
		end
		table.remove(s, idx)
		local old = setSlot(unitID, h, slot, item)
		if old then
			s[#s + 1] = old
		end
		publishStash(h.team)
		itemsChanged(unitID, h)
		toUI("equip", unitID, H.itemIndex[item], slot)
		return true
	end

	local function unequip(unitID, h, slot)
		if not h.items[slot] then
			return false
		end
		stash[h.team] = stash[h.team] or {}
		if #stash[h.team] >= H.STASH_SIZE then
			toUI("stashfull", unitID)
			return false
		end
		local old = setSlot(unitID, h, slot, nil)
		stash[h.team][#stash[h.team] + 1] = old
		publishStash(h.team)
		itemsChanged(unitID, h)
		return true
	end

	-- scenes / GG: equip an item directly, into the first free slot of its category (else the last one; the
	-- replaced item goes to the stash)
	local function equipDirect(unitID, h, item)
		local it = H.items[item]
		if not it or equippedSlotOf(h, item) then
			return false
		end
		local slot = firstSlotFor(h, it.category)
		local old = setSlot(unitID, h, slot, item)
		if old then
			stashAdd(h.team, old, unitID)
		end
		itemsChanged(unitID, h)
		return slot
	end

	local function pickups()
		if not next(ground) then
			return
		end
		local r2 = H.ITEM_PICKUP_RADIUS * H.ITEM_PICKUP_RADIUS
		for unitID, h in pairs(heroes) do
			local x, y, z = heroPos(unitID)
			if x then
				for id, g in pairs(ground) do
					if (g.x - x) ^ 2 + (g.z - z) ^ 2 <= r2 then
						ground[id] = nil
						groundDirty = true
						local kept = stashAdd(h.team, g.item, unitID)
						ceg("hero-itempickup-" .. H.items[g.item].rarity, x, y, z)
						toUI("pickup", unitID, H.itemIndex[g.item], kept and 1 or 0)
						Spring.Echo(string.format("[t4hero] team %d picked up %s into its stash (%d items)%s", h.team, g.item,
							#(stash[h.team] or {}), kept and "" or " - stash full, scrapped for metal"))
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

	local function itemCooldown(h, act)
		return act.cooldown * max(0.4, 1 - (h.mods and h.mods.cdr or 0))
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
		if not x then
			return false
		end
		local ally = spGetUnitAllyTeam(unitID)
		local k = act.kind
		if k == "heal" then
			local hp, maxHp = spGetUnitHealth(unitID)
			spSetUnitHealth(unitID, min(maxHp, hp + act.amount / (h.hpMult or 1)))
			ceg("hero-itemheal", x, y, z)
		elseif k == "invuln" then
			h.itemInvulnUntil = max(h.itemInvulnUntil or 0, f + act.duration * GAME_SPEED)
			markActive(unitID, "item" .. slot, act.duration)
			ceg("hero-phase", x, y, z)
		elseif k == "dash" then
			local dx, _, dz = Spring.GetUnitDirection(unitID)
			local nx = max(64, min(Game.mapSizeX - 64, x + dx * act.distance))
			local nz = max(64, min(Game.mapSizeZ - 64, z + dz * act.distance))
			ceg("hero-blink", x, y, z)
			Spring.SetUnitPosition(unitID, nx, nz)
			ceg("hero-blink", nx, spGetGroundHeight(nx, nz), nz)
		elseif k == "shield" then
			h.itemShield = { hp = act.absorb, expire = f + act.duration * GAME_SPEED }
			markActive(unitID, "item" .. slot, act.duration)
			itemCeg("hero-shield", "hero-phase", x, y, z)
		elseif k == "emp" then
			for _, uid in ipairs(enemiesIn(x, z, act.radius, ally)) do
				spAddUnitDamage(uid, act.dmg, 0, unitID)
				stun(uid, act.stun, unitID)
			end
			itemCeg("hero-nova-emp", "hero-static-field", x, y, z)
		elseif k == "overcharge" then
			h.itemBuff = { expire = f + act.duration * GAME_SPEED, damage = act.damage, reload = act.reload }
			markActive(unitID, "item" .. slot, act.duration)
			applyStats(unitID, h)
			itemCeg("hero-buff-power", "hero-overdrive", x, y, z)
		elseif k == "repair" then
			for _, uid in ipairs(alliesIn(x, z, act.radius, ally)) do
				local hp, maxHp, _, _, bp = spGetUnitHealth(uid)
				if hp and bp and bp >= 1 then
					local ah = heroes[uid]
					spSetUnitHealth(uid, min(maxHp, hp + act.amount / (ah and ah.hpMult or 1)))
				end
			end
			itemCeg("hero-nova-heal", "hero-itemheal", x, y, z)
		elseif k == "recall" then
			local bx, bz
			local best
			for _, uid in ipairs(Spring.GetTeamUnits(h.team) or {}) do
				if foundryDefs[spGetUnitDefID(uid) or -1] then
					local ux, _, uz = spGetUnitPosition(uid)
					local d = (ux - x) ^ 2 + (uz - z) ^ 2
					if not best or d < best then
						best, bx, bz = d, ux, uz + 260
					end
				end
			end
			if not bx then
				return false
			end
			ceg("hero-blink", x, y, z)
			Spring.SetUnitPosition(unitID, bx, bz)
			Spring.GiveOrderToUnit(unitID, CMD.STOP, {}, 0)
			ceg("hero-blink", bx, spGetGroundHeight(bx, bz), bz)
		end
		h.itemReady[slot] = f + floor(itemCooldown(h, act) * GAME_SPEED)
		h.itemCd[id] = h.itemReady[slot]
		spSetUnitRulesParam(unitID, "hero_itemcdlen_" .. slot, floor(itemCooldown(h, act) * GAME_SPEED), ALLIED)
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
		local f = frameNow()
		local x, _, z = heroPos(unitID)
		local ally = spGetUnitAllyTeam(unitID)
		local fighting = f - (h.lastHit or -1000) < 5 * GAME_SPEED
		for slot = 1, H.INVENTORY do
			local it = h.items[slot] and H.items[h.items[slot]]
			local act = it and it.active
			if act and (h.itemReady[slot] or 0) <= f then
				local k, use = act.kind, false
				if k == "heal" then
					use = frac < 0.55
				elseif k == "invuln" then
					use = frac < 0.3
				elseif k == "shield" then
					use = fighting and frac < 0.7
				elseif k == "emp" then
					local n = #enemiesIn(x, z, act.radius, ally)
					use = n >= 3 or (n >= 1 and frac < 0.4)
				elseif k == "overcharge" then
					local range = Spring.GetUnitRulesParam(unitID, "hero_range") or 900
					use = Spring.GetUnitNearestEnemy(unitID, range, true) ~= nil
				elseif k == "repair" then
					local hurt = frac < 0.6 and 3 or 0
					for _, uid in ipairs(alliesIn(x, z, act.radius, ally)) do
						local ahp, amax = spGetUnitHealth(uid)
						if ahp and amax - ahp > act.amount * 0.5 then
							hurt = hurt + 1
						end
					end
					use = hurt >= 3
				elseif k == "dash" then
					use = isAITeam[h.team] and h.retreating and frac < 0.45
				elseif k == "recall" then
					use = isAITeam[h.team] and h.retreating and frac < 0.3
				end
				if use then
					useSlot(unitID, h, slot)
				end
			end
		end
	end

	-- every second (after passives): item auras, the Crown, regen, income, barrier, the overcharge end
	local function itemPassives(f)
		for k in pairs(itemGuard) do
			itemGuard[k] = nil
		end
		for unitID, h in pairs(heroes) do
			local fx = h.itemFx
			local x, y, z = heroPos(unitID)
			if fx and x then
				local ally = spGetUnitAllyTeam(unitID)
				local a = fx.aura
				if a then
					if f % 60 < 30 then
						ceg(a.heal > 0 and "hero-aura-heal" or "hero-aura-command", x, y, z)
					end
					for _, uid in ipairs(alliesIn(x, z, a.radius, ally)) do
						if uid ~= unitID and a.damage > 0 then
							auraDamage[uid] = max(auraDamage[uid] or 0, a.damage)
						end
						if a.armor > 0 then
							itemGuard[uid] = max(itemGuard[uid] or 0, a.armor)
						end
						if a.heal > 0 then
							local hp, maxHp, _, _, bp = spGetUnitHealth(uid)
							if hp and bp and bp >= 1 and hp < maxHp then
								local ah = heroes[uid]
								spSetUnitHealth(uid, min(maxHp, hp + a.heal / (ah and ah.hpMult or 1)))
							end
						end
					end
				end
				for _, zap in ipairs(fx.zaps) do
					if f % (zap.period * GAME_SPEED) < GAME_SPEED then
						local target = Spring.GetUnitNearestEnemy(unitID, zap.radius, true)
						if target then
							local tx, ty, tz = spGetUnitPosition(target)
							ceg("hero-zap", tx, ty, tz)
							spAddUnitDamage(target, zap.damage, 0, unitID)
						end
					end
				end
				if fx.regen > 0 then
					local hp, maxHp = spGetUnitHealth(unitID)
					if hp and hp < maxHp then
						spSetUnitHealth(unitID, min(maxHp, hp + fx.regen / (h.hpMult or 1)))
					end
				end
				if fx.income > 0 then
					Spring.AddTeamResource(h.team, "metal", fx.income)
				end
				local b = fx.barrier
				if b then
					if f - (h.itemLastHit or -1e6) >= b.delay * GAME_SPEED then
						h.itemBarrier = min(b.cap, (h.itemBarrier or 0) + b.regen)
					end
					spSetUnitRulesParam(unitID, "hero_barrier", floor(h.itemBarrier or 0), INLOS)
				elseif h.itemBarrier then
					h.itemBarrier = nil
					spSetUnitRulesParam(unitID, "hero_barrier", 0, INLOS)
				end
			end
			if h.itemBuff and h.itemBuff.expire <= f then
				h.itemBuff = nil
				applyStats(unitID, h)
			end
			if h.itemShield and h.itemShield.expire <= f then
				h.itemShield = nil
			end
		end
	end

	-- AI teams: every hero wears the best items of the team stash for its role (higher levels choose first)
	local function itemScore(item, role)
		local it = H.items[item]
		local w = H.itemRoleWeights[role] or H.itemRoleWeights.center
		local k = 1
		for _, t in ipairs(it.tags or {}) do
			k = k + (w[t] or 0)
		end
		if it.active then
			k = k + 0.15
		end
		if role == "front" and it.stats.hp and it.stats.hp < 0 then
			k = k - 0.4
		end
		return H.rarities[it.rarity].score * k
	end

	local function aiEquipTeam(teamID)
		local list = {}
		for unitID, h in pairs(heroes) do
			if h.team == teamID then
				list[#list + 1] = { uid = unitID, h = h }
			end
		end
		table.sort(list, function(p, q) return p.h.level > q.h.level end)
		local teamChanged = false
		for _, e in ipairs(list) do
			local h, unitID = e.h, e.uid
			local role = h.def.cfg.aiRole or "center"
			local changed = false
			for _, cat in ipairs(H.categoryOrder) do
				local s = stash[teamID] or {}
				local slots = H.itemCategories[cat].slots
				-- candidates: what it wears + the stash items of this category
				local cand = {}
				for _, slot in ipairs(slots) do
					if h.items[slot] then
						cand[#cand + 1] = { item = h.items[slot], slot = slot }
					end
				end
				for i, id in ipairs(s) do
					if H.items[id].category == cat then
						cand[#cand + 1] = { item = id, idx = i }
					end
				end
				for _, c in ipairs(cand) do
					c.score = itemScore(c.item, role) + (c.slot and 0.01 or 0) -- keep what it wears on a tie
				end
				table.sort(cand, function(p, q) return p.score > q.score end)
				local want, seen = {}, {}
				for _, c in ipairs(cand) do
					if #want < #slots and not seen[c.item] then
						seen[c.item] = true
						want[#want + 1] = c
					end
				end
				local keep = {}
				for _, c in ipairs(want) do
					if c.slot then
						keep[c.slot] = true
					end
				end
				-- stash indices of the new ones, highest first so removals don't shift the others
				local take = {}
				for _, c in ipairs(want) do
					if c.idx then
						take[#take + 1] = c
					end
				end
				table.sort(take, function(p, q) return p.idx > q.idx end)
				local back = {}
				for _, slot in ipairs(slots) do
					if h.items[slot] and not keep[slot] then
						back[#back + 1] = setSlot(unitID, h, slot, nil)
					end
				end
				for _, c in ipairs(take) do
					table.remove(s, c.idx)
				end
				for _, c in ipairs(take) do
					local slot = firstSlotFor(h, cat)
					setSlot(unitID, h, slot, c.item)
					changed = true
					Spring.Echo(string.format("[t4hero] AI team %d: %s (%s, lv %d) equips %s (%s) in slot %d", teamID, h.def.name, role,
						h.level, c.item, H.items[c.item].rarity, slot))
				end
				for _, id in ipairs(back) do
					s[#s + 1] = id
				end
				stash[teamID] = s
				changed = changed or #back > 0
			end
			if changed then
				teamChanged = true
				itemsChanged(unitID, h)
			end
		end
		if teamChanged then
			publishStash(teamID)
		end
		aiEquipDirty[teamID] = nil
	end

	local function aiEquip(f)
		for teamID, isAI in pairs(isAITeam) do
			if isAI and (aiEquipDirty[teamID] or f % 300 == 13) then
				local any = false
				for _, h in pairs(heroes) do
					if h.team == teamID then
						any = true
						break
					end
				end
				if any then
					aiEquipTeam(teamID)
				else
					aiEquipDirty[teamID] = nil
				end
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
			itemPassives(f)
			aiEquip(f)
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
		elseif what == "equip" then
			-- <slot>_<stash index>[_<item index>]
			local slot, idx, want = key:match("^(%d+)_(%d+)_?(%d*)$")
			slot, idx = tonumber(slot), tonumber(idx)
			if slot and idx and H.slotCategory[slot] then
				equipFromStash(uid, h, slot, idx, tonumber(want))
			end
		elseif what == "unequip" then
			local slot = tonumber(key)
			if slot and H.slotCategory[slot] then
				unequip(uid, h, slot)
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
		for _, teamID in ipairs(Spring.GetTeamList()) do
			publishStash(teamID)
		end
		GG.T4Heroes = { heroes = heroes, learn = function(uid, key) local h = heroes[uid]; return h and learn(uid, h, key) end,
			-- give: into the hero's team stash; equip: straight into a slot of its category (scenes)
			give = function(uid, item) local h = heroes[uid]; if h then return stashAdd(h.team, item, uid) end end,
			equip = function(uid, item) local h = heroes[uid]; if h then return equipDirect(uid, h, item) end end,
			stashAdd = function(teamID, item) return stashAdd(teamID, item) end, stash = stash,
			useItem = function(uid, slot) local h = heroes[uid]; return h and useSlot(uid, h, slot) end,
			equipFromStash = function(uid, slot, idx) local h = heroes[uid]; return h and equipFromStash(uid, h, slot, idx) end,
			unequip = function(uid, slot) local h = heroes[uid]; return h and unequip(uid, h, slot) end,
			drop = function(item, x, z) dropItem(item, x, z) end, randomItem = function(level) return randomItem(level) end,
			setLevel = function(uid, level) local h = heroes[uid]
				if h then h.xp = H.xpFor(level, xpMult) * h.def.cost + 1
					while h.level < min(level, H.MAX_LEVEL) do levelUp(uid, h) end publish(uid, h) end end,
			addXP = function(uid, metal) local h = heroes[uid]; if h then addXP(uid, h, metal) end end,
			cast = function(uid, key, tx, tz, target) local h = heroes[uid]; return h and tryCast(uid, h, key, tx, tz, target) end,
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
