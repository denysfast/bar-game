local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "T4 Hero Items",
		desc = "Diablo-style hero items: rolled affixes, uniques, sets, team stash, shop, salvage, drops, item powers, AI",
		author = "denysfast",
		date = "2026-10-02",
		license = "GNU GPL, v2 or later",
		layer = -1, -- before the hero gadget: its RecvLuaMsg never sees the item messages
		enabled = true,
	}
end

-- v19 hero items (doc/v19-heroes/SPEC.md section 6). Data and pure helpers: luarules/configs/t4_hero_items.lua
-- (I.decode / I.lines / I.name / I.icon ... - the UI includes it too). The hero gadget
-- (luarules/gadgets/unit_t4_heroes.lua) owns the heroes and calls the hooks of GG.T4HeroItems:
--
--   mods(unitID, h, m)                     add the equipped items' stats + set bonuses into m (keys: SPEC section 6;
--                                          hp, regen, speed, sight, income in units, the rest fractions, m.dtype)
--   hit(attackerID, h, victimID, victimDefID, damage, weaponDefID, para) -> damage    the hero's hit: slayer,
--                                          execute, life on hit, mark, chain arcs (procs dealt next frame)
--   damaged(unitID, h, damage, attackerID, weaponDefID, para) -> damage   the hero is hit: invulnerability,
--                                          low-HP shield, reflect
--   dying(unitID, h) -> bool               lethal damage: true = keep it alive (Phoenix Heart)
--   frame(f)                               no-op (the gadget runs its own GameFrame); kept for API symmetry
--   onHeroDeath(unitID, h, x, z)           drops what it wore + a trophy (if not called, UnitDestroyed does it)
--   onKill(heroID, victimID, victimDefID)  drops, explode-on-kill, souls (if not called, UnitDestroyed does it)
-- Other GG.T4HeroItems functions (scenes, AI, UI gadgets): roll(opts), give(teamID, itemOrStr), equip(unitID,
-- itemOrStr[, slot]), drop(itemOrStr, x, z), stash(teamID), worn(unitID), handle(msg, teamID), I (the data).
-- After an equipment change the gadget calls GG.T4Heroes.refresh(unitID) so the hero recomputes its stats.
--
-- Protocol (LuaRules messages, from a player of the team; spectators are ignored):
--   t4hero:equip:<unitID>:<slot>_<stashIndex>[_<uid>]   stash item -> slot of its category (the worn one goes
--                                                       to that stash place); uid re-finds a moved item
--   t4hero:unequip:<unitID>:<slot>                      slot -> stash (fails when the stash is full)
--   t4hero:use:<unitID>:<slot>                          use the active power of a worn item (Blink)
--   t4hero:salvage:<stashIndex>[_<uid>]                 stash item -> metal (I.salvage)
--   t4hero:shopbuy:<shelfIndex>[_<uid>]                 buy a shelf item into the stash (needs a finished shop)
--   t4hero:shoprefresh                                  reroll the shelf for I.SHOP_REFRESH_FEE metal
-- Rules params (item strings: see the header of the config):
--   team (allied):  items_stash_n, items_stash_<1..n> (item string), items_stash_ver
--                   items_shop ("|"-joined 9 item strings, "" = sold), items_shop_next (frame of the free refresh),
--                   items_shop_ver, items_shop_unit (unitID of a finished shop of the team, 0 = none)
--   unit (in LOS):  items_slot_<1..9> (item string, "" = empty), items_ver, items_sets ("<set>:<count>,...")
--                   items_shield (shield HP left), items_souls (soul stacks)
--   unit (allied):  items_cd_<slot> (frame the active is ready), items_cdlen_<slot>, items_cheat (frame Phoenix
--                   Heart is ready)
--   game:           items_ground ("<id>:<x>:<z>:<rarity code>;..."), items_ground_<id> (item string, "" = gone)
-- UI events: Script.LuaUI.T4HeroItemEvent(kind, teamID, unitID, itemString, number) for allies and spectators;
--   kinds: pickup (number 1 = kept, 0 = scrapped), scrap, equip, unequip, salvage, buy, refresh, nometal,
--   stashfull, noshop, use, drop, dup (that unique / set piece is worn already), proc (a unique / set power
--   triggered: power key in itemString - chain, blastKill, slayer, execute, orbital, lowShield, cheatDeath, lifeOnHit,
--   reflect, mark, souls, staticWake; number = its damage / heal / shield HP / % / soul count; at most one per
--   power per hero every 2 s). items_cdlen_<slot> is published on equip (0 = no active), refreshed after a use.

local I = VFS.Include("luarules/configs/t4_hero_items.lua")

if gadgetHandler:IsSyncedCode() then
	----------------------------------------------------------------------------- synced

	local spGetUnitPosition = Spring.GetUnitPosition
	local spGetUnitsInCylinder = Spring.GetUnitsInCylinder
	local spGetUnitAllyTeam = Spring.GetUnitAllyTeam
	local spGetUnitTeam = Spring.GetUnitTeam
	local spGetUnitHealth = Spring.GetUnitHealth
	local spSetUnitHealth = Spring.SetUnitHealth
	local spGetUnitDefID = Spring.GetUnitDefID
	local spGetUnitIsDead = Spring.GetUnitIsDead
	local spValidUnitID = Spring.ValidUnitID
	local spSetUnitRulesParam = Spring.SetUnitRulesParam
	local spSetTeamRulesParam = Spring.SetTeamRulesParam
	local spSetGameRulesParam = Spring.SetGameRulesParam
	local spGetGameFrame = Spring.GetGameFrame
	local spGetGroundHeight = Spring.GetGroundHeight
	local spSpawnCEG = Spring.SpawnCEG
	local random = math.random
	local max, min, floor, sqrt = math.max, math.min, math.floor, math.sqrt

	local ALLIED = { allied = true }
	local INLOS = { inlos = true }
	local GAME_SPEED = Game.gameSpeed
	local GAIA = Spring.GetGaiaTeamID()
	local GAIA_ALLY = select(6, Spring.GetTeamInfo(GAIA, false))

	---------------------------------------------------------------- static data
	local unitCost, unitHealth, isHeroDef, maxRange = {}, {}, {}, {}
	local shopDefs, builderShop = {}, {} -- shop unitDefID -> true; builder unitDefID -> shop unitDefID it can build
	local altarDefs = {}
	for name, sname in pairs(I.SHOPS) do
		local sd = UnitDefNames[sname]
		if sd then
			shopDefs[sd.id] = true
		end
	end
	for udid, ud in pairs(UnitDefs) do
		unitCost[udid] = ud.metalCost or 0
		unitHealth[udid] = ud.health or 1
		maxRange[udid] = ud.maxWeaponRange or 0
		if ud.customParams and ud.customParams.t4_hero then
			isHeroDef[udid] = true
		end
		if ud.name == "armt4gant" or ud.name == "cort4gant" or ud.name == "legt4gant" then
			altarDefs[udid] = true
		end
		for _, opt in ipairs(ud.buildOptions or {}) do
			if shopDefs[opt] then
				builderShop[udid] = opt
			end
		end
	end

	-- damage type of a weapondef (the same rules as the hero gadget's H.damageType, SPEC section 6)
	local function damageType(wd)
		local n = (wd.name or ""):lower()
		if wd.type == "LightningCannon" or n:find("lightning") or n:find("thunder") then
			return "electric"
		elseif wd.paralyzer then
			return "emp"
		elseif wd.type == "BeamLaser" or wd.type == "LaserCannon" then
			return "laser"
		elseif wd.type == "Flame" then
			return "flame"
		elseif wd.type == "MissileLauncher" or wd.type == "StarburstLauncher" or n:find("rocket") or n:find("missile") then
			return "rocket"
		elseif n:find("rail") or n:find("sniper") then
			return "rail"
		elseif wd.type == "Cannon" then
			return "plasma"
		end
	end
	-- share of a hero unitdef's damage per type (the AI values damage-type affixes by it)
	local heroTypesCache = {}
	local function heroTypes(udid)
		if heroTypesCache[udid] then
			return heroTypesCache[udid]
		end
		local ud = UnitDefs[udid]
		local sum, out = 0, {}
		for _, w in ipairs(ud and ud.weapons or {}) do
			local wd = WeaponDefs[w.weaponDef]
			local kind = wd and damageType(wd)
			if kind and wd.damages then
				local d = (wd.damages[0] or 0) * (wd.salvoSize or 1) * (wd.projectiles or 1) / max(0.1, wd.reload or 1)
				if d > 0 then
					out[kind] = (out[kind] or 0) + d
					sum = sum + d
				end
			end
		end
		for k, v in pairs(out) do
			out[k] = sum > 0 and v / sum or 0
		end
		heroTypesCache[udid] = out
		return out
	end

	local isAITeam = {}
	for _, teamID in ipairs(Spring.GetTeamList()) do
		local _, _, _, isAI = Spring.GetTeamInfo(teamID, false)
		local luaAI = Spring.GetTeamLuaAI(teamID)
		isAITeam[teamID] = isAI and (luaAI == nil or luaAI == "") or false
	end

	---------------------------------------------------------------- state
	local nextUid = 1
	local stash = {}       -- teamID -> { item, ... } (item = decoded table with .str), oldest first
	local stashVer = {}
	local shelf = {}       -- teamID -> { items = { [1..9] = item | false }, next = frame, ver }
	local shops = {}       -- teamID -> { [unitID] = true } finished shops
	local ground = {}      -- id -> { item, x, z, expire }
	local groundDirty = false
	local state = {}       -- hero unitID -> { slots = {[slot] = item}, team, cd = {}, cdByUid = {}, ... }
	local queue = {}       -- deferred effects: { at = frame, fn = function }
	local marks = {}       -- unitID -> { v, expire }
	local guard, war = {}, {} -- unitID -> damage taken reduction / damage bonus of the item auras (refreshed every second)
	local pendingKill = {} -- victimID -> { hero, defID, x, z, maxHp, team }
	local pendingDeath = {} -- hero unitID -> { x, z, level, team }
	local inProc = 0
	local procKills = {}    -- unitID -> frame: killed by an item power (its death sets off no Pyre: no chain reactions)
	local aiDirty = {}
	local aiNext = {}

	local function frameNow()
		return spGetGameFrame()
	end
	local function heroesTbl()
		return GG.T4Heroes and GG.T4Heroes.heroes or {}
	end
	local function log(fmt, ...)
		Spring.Echo("[t4items] " .. string.format(fmt, ...))
	end
	local function toUI(kind, teamID, unitID, str, num)
		if Spring.GetGameRulesParam("items_debug") == 1 then
			Spring.Echo(string.format("[t4items] event %s team %s unit %s %s %s", kind, tostring(teamID), tostring(unitID), tostring(str), tostring(num)))
		end
		SendToUnsynced("t4heroitems_event", kind, teamID or -1, unitID or -1, str or "", num or 0)
	end
	local function refreshHero(unitID)
		local G = GG.T4Heroes
		if G and G.refresh then
			G.refresh(unitID)
		end
	end
	local function newUid()
		local u = nextUid
		nextUid = nextUid + 1
		return u
	end
	local function asItem(x)
		if type(x) == "string" then
			local it = I.decode(x)
			if it and (it.uid or 0) == 0 then
				it.uid = newUid()
				it.str = I.encode(it)
			end
			return it
		end
		return x
	end
	local function rollItem(opts)
		opts = opts or {}
		opts.uid = newUid()
		return I.roll(random, opts)
	end
	local function isEnemy(uid, ally)
		local a = spGetUnitAllyTeam(uid)
		return a and a ~= ally and a ~= GAIA_ALLY
	end
	local function enemiesNear(x, z, r, ally, n)
		local list = {}
		for _, uid in ipairs(spGetUnitsInCylinder(x, z, r)) do
			if isEnemy(uid, ally) and not spGetUnitIsDead(uid) then
				local ux, _, uz = spGetUnitPosition(uid)
				if ux then
					list[#list + 1] = { uid = uid, d = (ux - x) ^ 2 + (uz - z) ^ 2 }
				end
			end
		end
		table.sort(list, function(a, b) return a.d < b.d end)
		local out = {}
		for i = 1, min(#list, n or #list) do
			out[i] = list[i].uid
		end
		return out
	end
	local function later(frames, fn)
		queue[#queue + 1] = { at = frameNow() + frames, fn = fn }
	end
	-- item power damage, dealt outside the damage callins (next frame) and never re-triggering item powers
	local function dealDamage(target, amount, attackerID, dtype, what)
		if not spValidUnitID(target) or spGetUnitIsDead(target) or amount <= 0 then
			return
		end
		if Spring.GetGameRulesParam("items_debug") == 1 then
			log("power %s: %d damage to %d by %s", what or dtype or "?", amount, target, tostring(attackerID))
		end
		inProc = inProc + 1
		local G = GG.T4Heroes
		if G and G.damage then
			G.damage(target, amount, attackerID, { dtype = dtype, item = true })
		else
			Spring.AddUnitDamage(target, amount, 0, attackerID, -1)
		end
		inProc = inProc - 1
		local hp = spGetUnitHealth(target)
		if not hp or hp <= 0 or spGetUnitIsDead(target) then
			procKills[target] = frameNow()
		end
	end
	-- UI toast of a power that triggered: at most one per power per hero every PROC_TOAST seconds
	local PROC_TOAST = 2 * GAME_SPEED
	local function procEvent(unitID, s, key, num)
		s = s or state[unitID]
		if not s then
			return
		end
		local f = frameNow()
		s.toast = s.toast or {}
		if (s.toast[key] or -1e9) + PROC_TOAST > f then
			return
		end
		s.toast[key] = f
		toUI("proc", s.team, unitID, key, floor(num or 0))
	end
	local function procScale(h)
		return 1 + 0.015 * max(0, ((h and h.level) or 1) - 1)
	end

	---------------------------------------------------------------- FX (GG.HeroFX when present, CEGs otherwise)
	local FALLBACK_CEG = { magic = "hero-itemdrop-rare", rare = "hero-itemdrop-legendary", set = "hero-itemdrop-common",
		unique = "hero-itemdrop-legendary" }
	local function rgba(c, a)
		return { c[1], c[2], c[3], a or 1 }
	end
	local function fxDrop(it, x, z)
		local F = GG.HeroFX
		local c = I.rarities[it.rarity].color
		if F and F.pillar then
			F.pillar(x, z, { radius = 30, height = it.rarity == "magic" and 500 or 900, color = rgba(c, 0.9), ttl = 3 })
			F.ring(x, z, { r0 = 20, r1 = 120, color = rgba(c, 0.9), ttl = 1, kind = "rune" })
		else
			spSpawnCEG(FALLBACK_CEG[it.rarity], x, spGetGroundHeight(x, z), z, 0, 1, 0, 0, 0)
		end
	end
	local function fxPickup(it, x, y, z)
		local F = GG.HeroFX
		local c = I.rarities[it.rarity].color
		if F and F.flash then
			F.flash(x, y + 40, z, { radius = 140, color = rgba(c, 1), ttl = 0.6 })
		else
			spSpawnCEG((FALLBACK_CEG[it.rarity] or ""):gsub("drop", "pickup"), x, y, z, 0, 1, 0, 0, 0)
		end
	end
	local ELECTRIC = { 0.45, 0.7, 1.0, 1 }
	local function fxBolt(x1, y1, z1, x2, y2, z2, color)
		local F = GG.HeroFX
		if F and F.bolt then
			F.bolt(x1, y1, z1, x2, y2, z2, { color = color or ELECTRIC, width = 10, ttl = 0.35, branches = 2 })
		else
			spSpawnCEG("hero-zap", x2, y2, z2, 0, 1, 0, 0, 0)
		end
	end
	local function fxFlash(x, y, z, color, radius, ceg)
		local F = GG.HeroFX
		if F and F.flash then
			F.flash(x, y, z, { radius = radius or 200, color = color, ttl = 0.6 })
		elseif ceg then
			spSpawnCEG(ceg, x, y, z, 0, 1, 0, 0, 0)
		end
	end

	---------------------------------------------------------------- hero state, computed effects
	local function st(unitID)
		local s = state[unitID]
		if not s then
			s = { slots = {}, cd = {}, cdByUid = {}, procReady = {}, souls = 0, lastKill = 0, shield = 0, shieldExp = 0,
				shieldReady = 0, cheatReady = 0, invulnUntil = 0, timers = {}, lohSecond = -1, lohCount = 0,
				team = spGetUnitTeam(unitID), ally = spGetUnitAllyTeam(unitID) }
			state[unitID] = s
		end
		return s
	end

	-- recompute stats, powers and set counts of a hero's worn items
	local function compute(s)
		local stats, powers, sets = {}, {}, {}
		for slot = 1, I.SLOTS do
			local it = s.slots[slot]
			if it then
				I.addStats(stats, I.stats(it), 1)
				for _, p in ipairs(I.powers(it)) do
					p.slot = slot
					powers[#powers + 1] = p
				end
				if it.rarity == "set" then
					sets[it.set] = (sets[it.set] or 0) + 1
				end
			end
		end
		for si, n in pairs(sets) do
			local bst, bpw = I.setBonus(si, n)
			I.addStats(stats, bst, 1)
			for _, p in ipairs(bpw) do
				powers[#powers + 1] = p
			end
		end
		local byKey = {}
		for _, p in ipairs(powers) do
			byKey[p.key] = byKey[p.key] or {}
			table.insert(byKey[p.key], p)
		end
		s.stats, s.powers, s.pw, s.sets = stats, powers, byKey, sets
	end

	-- cooldown (frames) of an item's active power for this hero, 0 = no active
	local function activeCdLen(s, it)
		for _, p in ipairs(I.powers(it)) do
			local info = I.powerInfo[p.key]
			if info and info.active then
				local cdr = min(0.4, s.stats and s.stats.cdr or 0)
				return floor(p.p.cooldown * (1 - cdr) * GAME_SPEED)
			end
		end
		return 0
	end

	local function publishSlots(unitID, s)
		local sets = {}
		for slot = 1, I.SLOTS do
			local it = s.slots[slot]
			spSetUnitRulesParam(unitID, "items_slot_" .. slot, it and it.str or "", INLOS)
			spSetUnitRulesParam(unitID, "items_cd_" .. slot, s.cd[slot] or 0, ALLIED)
			spSetUnitRulesParam(unitID, "items_cdlen_" .. slot, it and activeCdLen(s, it) or 0, ALLIED)
		end
		for si, n in pairs(s.sets or {}) do
			sets[#sets + 1] = si .. ":" .. n
		end
		spSetUnitRulesParam(unitID, "items_sets", table.concat(sets, ","), INLOS)
		s.ver = (s.ver or 0) + 1
		spSetUnitRulesParam(unitID, "items_ver", s.ver, INLOS)
	end

	local function itemsChanged(unitID, s)
		compute(s)
		publishSlots(unitID, s)
		refreshHero(unitID)
	end

	---------------------------------------------------------------- stash
	local function publishStash(teamID)
		local s = stash[teamID] or {}
		local oldN = Spring.GetTeamRulesParam(teamID, "items_stash_n") or 0
		for i, it in ipairs(s) do
			spSetTeamRulesParam(teamID, "items_stash_" .. i, it.str, ALLIED)
		end
		for i = #s + 1, oldN do
			spSetTeamRulesParam(teamID, "items_stash_" .. i, "", ALLIED)
		end
		spSetTeamRulesParam(teamID, "items_stash_n", #s, ALLIED)
		stashVer[teamID] = (stashVer[teamID] or 0) + 1
		spSetTeamRulesParam(teamID, "items_stash_ver", stashVer[teamID], ALLIED)
		if isAITeam[teamID] then
			aiDirty[teamID] = true
		end
	end

	local function rarityRank(it)
		return I.rarities[it.rarity].rank * 10 + it.ilvl
	end

	-- into the team stash; a full stash scraps its oldest lowest item for metal - or the new one when nothing
	-- in it is lower. Returns true (kept) or false (scrapped), and the metal paid.
	local function stashAdd(teamID, it, unitID)
		if not it then
			return false, 0
		end
		stash[teamID] = stash[teamID] or {}
		local s = stash[teamID]
		local scrapped
		if #s >= I.STASH_SIZE then
			local low, lowIdx = math.huge, nil
			for i, x in ipairs(s) do
				local r = rarityRank(x)
				if r < low then
					low, lowIdx = r, i
				end
			end
			if rarityRank(it) <= low then
				scrapped = it
			else
				scrapped = table.remove(s, lowIdx)
			end
			local metal = I.salvage(scrapped)
			Spring.AddTeamResource(teamID, "metal", metal)
			toUI("scrap", teamID, unitID, scrapped.str, metal)
		end
		if scrapped ~= it then
			s[#s + 1] = it
		end
		publishStash(teamID)
		return scrapped ~= it, scrapped and I.salvage(scrapped) or 0
	end

	-- stash index of an item: idx if it holds uid (or uid is nil), else the place of uid
	local function findStash(teamID, idx, uid)
		local s = stash[teamID]
		if not s then
			return nil
		end
		if idx and s[idx] and (not uid or s[idx].uid == uid) then
			return idx
		end
		if uid then
			for i, it in ipairs(s) do
				if it.uid == uid then
					return i
				end
			end
		end
	end

	---------------------------------------------------------------- equipment
	-- the same unique / set piece can't be worn twice by one hero
	local function dupSlot(s, it, exceptSlot)
		for slot = 1, I.SLOTS do
			local w = s.slots[slot]
			if w and slot ~= exceptSlot then
				if it.rarity == "unique" and w.rarity == "unique" and w.unique == it.unique then
					return slot
				elseif it.rarity == "set" and w.rarity == "set" and w.set == it.set and w.piece == it.piece then
					return slot
				end
			end
		end
	end

	local function setSlot(s, slot, it)
		local old = s.slots[slot]
		if old then
			s.cdByUid[old.uid] = s.cd[slot]
		end
		s.slots[slot] = it
		s.cd[slot] = it and s.cdByUid[it.uid] or nil
		return old
	end

	local function firstSlotFor(s, cat)
		local slots = I.categories[cat].slots
		for _, slot in ipairs(slots) do
			if not s.slots[slot] then
				return slot
			end
		end
		return slots[#slots]
	end

	local function equipFromStash(unitID, slot, idx, uid)
		local s = st(unitID)
		local teamID = spGetUnitTeam(unitID)
		idx = findStash(teamID, idx, uid)
		local it = idx and stash[teamID][idx]
		if not it or I.slotCategory[slot] ~= it.cat then
			return false
		end
		if dupSlot(s, it, slot) then
			toUI("dup", teamID, unitID, it.str)
			return false
		end
		local old = setSlot(s, slot, it)
		if old then
			stash[teamID][idx] = old -- the worn one takes the stash place
		else
			table.remove(stash[teamID], idx)
		end
		publishStash(teamID)
		itemsChanged(unitID, s)
		toUI("equip", teamID, unitID, it.str, slot)
		return true
	end

	local function unequip(unitID, slot)
		local s = state[unitID]
		local teamID = spGetUnitTeam(unitID)
		if not s or not s.slots[slot] then
			return false
		end
		stash[teamID] = stash[teamID] or {}
		if #stash[teamID] >= I.STASH_SIZE then
			toUI("stashfull", teamID, unitID)
			return false
		end
		local old = setSlot(s, slot, nil)
		stash[teamID][#stash[teamID] + 1] = old
		publishStash(teamID)
		itemsChanged(unitID, s)
		toUI("unequip", teamID, unitID, old.str, slot)
		return true
	end

	-- scenes / GG: wear an item right away (into `slot` or the first free slot of its category); the replaced
	-- one goes to the stash
	local function equipDirect(unitID, it, slot)
		it = asItem(it)
		if not it then
			return false
		end
		local s = st(unitID)
		slot = slot or firstSlotFor(s, it.cat)
		if I.slotCategory[slot] ~= it.cat or dupSlot(s, it, slot) then
			return false
		end
		local old = setSlot(s, slot, it)
		if old then
			stashAdd(spGetUnitTeam(unitID), old, unitID)
		end
		itemsChanged(unitID, s)
		return true
	end

	---------------------------------------------------------------- salvage, shop
	local function salvage(teamID, idx, uid)
		idx = findStash(teamID, idx, uid)
		if not idx then
			return false
		end
		local it = table.remove(stash[teamID], idx)
		local metal = I.salvage(it)
		Spring.AddTeamResource(teamID, "metal", metal)
		publishStash(teamID)
		toUI("salvage", teamID, -1, it.str, metal)
		return true, metal
	end

	local function shopUnit(teamID)
		for uid in pairs(shops[teamID] or {}) do
			if spValidUnitID(uid) and not spGetUnitIsDead(uid) then
				return uid
			end
		end
		return nil
	end

	local function publishShelf(teamID)
		local sh = shelf[teamID]
		if not sh then
			return
		end
		local parts = {}
		for i = 1, I.SHOP_SIZE do
			parts[i] = sh.items[i] and sh.items[i].str or ""
		end
		sh.ver = (sh.ver or 0) + 1
		spSetTeamRulesParam(teamID, "items_shop", table.concat(parts, "|"), ALLIED)
		spSetTeamRulesParam(teamID, "items_shop_next", sh.next, ALLIED)
		spSetTeamRulesParam(teamID, "items_shop_ver", sh.ver, ALLIED)
		spSetTeamRulesParam(teamID, "items_shop_unit", shopUnit(teamID) or 0, ALLIED)
	end

	local function shopIlvl()
		local w = I.SHOP_ILVL_WEIGHTS
		local r = random() * (w[1] + w[2] + w[3])
		for l = 1, 3 do
			r = r - w[l]
			if r <= 0 then
				return l
			end
		end
		return 1
	end

	local function rollShelf(teamID)
		local items = {}
		local i = 0
		for _, cat in ipairs(I.categoryOrder) do
			for _ = 1, I.SHOP_SIZE / 3 do
				i = i + 1
				items[i] = rollItem({ cat = cat, ilvl = shopIlvl(), rarity = random() < I.SHOP_RARE_CHANCE and "rare" or "magic" })
			end
		end
		shelf[teamID] = { items = items, next = frameNow() + I.SHOP_REFRESH * GAME_SPEED, ver = shelf[teamID] and shelf[teamID].ver or 0 }
		publishShelf(teamID)
	end

	local function shopBuy(teamID, idx, uid, paid)
		local sh = shelf[teamID]
		if not shopUnit(teamID) or not sh then
			toUI("noshop", teamID)
			return false
		end
		local it = sh.items[idx]
		if not it or (uid and it.uid ~= uid) then
			return false
		end
		if #(stash[teamID] or {}) >= I.STASH_SIZE then
			toUI("stashfull", teamID)
			return false
		end
		local price = I.price(it)
		if not paid and not Spring.UseTeamResource(teamID, "metal", price) then
			toUI("nometal", teamID, -1, it.str, price)
			return false
		end
		sh.items[idx] = false
		stashAdd(teamID, it)
		publishShelf(teamID)
		toUI("buy", teamID, -1, it.str, price)
		return true
	end

	local function shopRefresh(teamID, free)
		if not shopUnit(teamID) then
			toUI("noshop", teamID)
			return false
		end
		if not free and not Spring.UseTeamResource(teamID, "metal", I.SHOP_REFRESH_FEE) then
			toUI("nometal", teamID, -1, "", I.SHOP_REFRESH_FEE)
			return false
		end
		rollShelf(teamID)
		toUI("refresh", teamID, -1, "", free and 0 or I.SHOP_REFRESH_FEE)
		return true
	end

	---------------------------------------------------------------- ground items
	local function publishGround()
		local parts = {}
		for id, g in pairs(ground) do
			parts[#parts + 1] = string.format("%d:%d:%d:%s", id, g.x, g.z, I.rarities[g.item.rarity].code)
		end
		spSetGameRulesParam("items_ground", table.concat(parts, ";"))
		groundDirty = false
	end

	local function dropItem(it, x, z)
		it = asItem(it)
		if not it then
			return
		end
		x = max(32, min(Game.mapSizeX - 32, x))
		z = max(32, min(Game.mapSizeZ - 32, z))
		local id = 1 -- the smallest free id: the number of items_ground_<id> params stays small
		while ground[id] do
			id = id + 1
		end
		ground[id] = { item = it, x = floor(x), z = floor(z), expire = frameNow() + I.GROUND_LIFETIME * GAME_SPEED }
		spSetGameRulesParam("items_ground_" .. id, it.str)
		groundDirty = true
		fxDrop(it, x, z)
		toUI("drop", -1, -1, it.str, id)
		return id
	end

	local function removeGround(id)
		ground[id] = nil
		spSetGameRulesParam("items_ground_" .. id, "")
		groundDirty = true
	end

	local function pickups()
		if not next(ground) then
			return
		end
		local r2 = I.PICKUP_RADIUS * I.PICKUP_RADIUS
		for unitID in pairs(heroesTbl()) do
			local x, y, z = spGetUnitPosition(unitID)
			if x and not spGetUnitIsDead(unitID) then
				for id, g in pairs(ground) do
					if (g.x - x) ^ 2 + (g.z - z) ^ 2 <= r2 then
						removeGround(id)
						local teamID = spGetUnitTeam(unitID)
						local kept = stashAdd(teamID, g.item, unitID)
						fxPickup(g.item, x, y, z)
						toUI("pickup", teamID, unitID, g.item.str, kept and 1 or 0)
						log("team %d picked up %s (%s ilvl %d)%s", teamID, I.name(g.item), g.item.rarity, g.item.ilvl,
							kept and "" or " - stash full, scrapped")
					end
				end
			end
		end
	end

	---------------------------------------------------------------- powers
	local function procReady(s, key, f, icd)
		if (s.procReady[key] or 0) > f then
			return false
		end
		s.procReady[key] = f + floor((icd or I.PROC_ICD) * GAME_SPEED)
		return true
	end

	local function chainArc(heroID, h, victimID, p, v)
		local s = state[heroID]
		later(1, function()
			local hx, hy, hz = spGetUnitPosition(heroID)
			local px, py, pz = hx, (hy or 0) + 60, hz
			local hit = {}
			local cur = victimID
			local dmg = v * procScale(h)
			for _ = 0, p.jumps do
				if not cur or not spValidUnitID(cur) then
					break
				end
				local x, y, z = spGetUnitPosition(cur)
				if not x then
					break
				end
				hit[cur] = true
				if px then
					fxBolt(px, py, pz, x, y + 30, z)
				end
				dealDamage(cur, dmg, heroID, "electric", "chain")
				px, py, pz = x, y + 30, z
				local nxt
				for _, uid in ipairs(enemiesNear(x, z, p.radius, s and s.ally or spGetUnitAllyTeam(heroID), 8)) do
					if not hit[uid] then
						nxt = uid
						break
					end
				end
				cur = nxt
			end
		end)
	end

	local function blastAt(heroID, h, x, z, dmg, radius, ally, exceptID)
		later(1, function()
			local y = spGetGroundHeight(x, z)
			fxFlash(x, y + 30, z, { 1.0, 0.5, 0.15, 1 }, radius, "hero-nova-fire")
			local F = GG.HeroFX
			if F and F.ring then
				F.ring(x, z, { r0 = 30, r1 = radius, color = { 1, 0.45, 0.1, 0.9 }, ttl = 0.6, kind = "shock" })
			end
			for _, uid in ipairs(enemiesNear(x, z, radius, ally)) do
				if uid ~= exceptID then
					dealDamage(uid, dmg, heroID, "flame", "blastKill")
				end
			end
		end)
	end

	local function sumPower(s, key)
		local list = s.pw and s.pw[key]
		if not list then
			return 0, nil
		end
		local v, best = 0, nil
		for _, p in ipairs(list) do
			v = v + p.v
			best = best or p
		end
		return v, best
	end

	---------------------------------------------------------------- hooks for the hero gadget
	local Hooks = {}

	-- the stat caps: fractions as written, speed as a share of the base speed
	function Hooks.mods(unitID, h, m)
		local s = state[unitID]
		if not s then
			return m
		end
		if not s.stats then
			compute(s)
		end
		for k, v in pairs(s.stats) do
			if k == "dtype" then
				m.dtype = m.dtype or {}
				for kind, dv in pairs(v) do
					m.dtype[kind] = (m.dtype[kind] or 0) + dv
				end
			else
				local info = I.statInfo[k]
				if info and info.cap then
					if info.capBase == "speed" then
						local base = h and h.def and h.def.speed or (UnitDefs[spGetUnitDefID(unitID) or 0] or {}).speed or 0
						if base > 0 then
							v = min(v, info.cap * base)
						end
					else
						v = min(v, info.cap)
					end
				end
				m[k] = (m[k] or 0) + v
			end
		end
		local soul = s.pw and s.pw.souls and s.pw.souls[1]
		if soul and s.souls > 0 then
			m.damage = (m.damage or 0) + s.souls * soul.v
		end
		return m
	end

	function Hooks.hit(attackerID, h, victimID, victimDefID, damage, weaponDefID, para)
		local s = state[attackerID]
		if inProc > 0 or para or not s or not s.pw or damage <= 0 then
			return damage
		end
		local pw = s.pw
		local f = frameNow()
		local mult = 1
		if pw.slayer then
			local heroVictim = isHeroDef[victimDefID]
			for _, p in ipairs(pw.slayer) do
				if heroVictim or (unitCost[victimDefID] or 0) >= p.p.minCost then
					mult = mult + p.v
					procEvent(attackerID, s, "slayer", p.v * 100)
				end
			end
		end
		if pw.execute then
			local hp, maxHp = spGetUnitHealth(victimID)
			if hp and maxHp and maxHp > 0 then
				for _, p in ipairs(pw.execute) do
					if hp / maxHp < p.p.below then
						mult = mult + p.v
						procEvent(attackerID, s, "execute", p.v * 100)
					end
				end
			end
		end
		if pw.mark then
			local v, p = sumPower(s, "mark")
			local mk = marks[victimID]
			if not mk or mk.v <= v or mk.expire < f then
				if not mk or mk.expire < f then
					procEvent(attackerID, s, "mark", v * 100)
				end
				marks[victimID] = { v = v, expire = f + p.p.duration * GAME_SPEED }
			end
		end
		if pw.lifeOnHit then
			local sec = floor(f / GAME_SPEED)
			if s.lohSecond ~= sec then
				s.lohSecond, s.lohCount = sec, 0
			end
			local v, p = sumPower(s, "lifeOnHit")
			if s.lohCount < (p.p.perSecond or 6) then
				s.lohCount = s.lohCount + 1
				local hp, maxHp = spGetUnitHealth(attackerID)
				if hp and hp < maxHp then
					spSetUnitHealth(attackerID, min(maxHp, hp + v / max(0.2, (h and h.hpMult) or 1))) -- v in effective HP
					procEvent(attackerID, s, "lifeOnHit", v)
				end
			end
		end
		if pw.chain then
			for i, p in ipairs(pw.chain) do
				if random() < p.p.chance and procReady(s, "chain" .. i, f) then
					chainArc(attackerID, h, victimID, p.p, p.v)
					procEvent(attackerID, s, "chain", p.v * procScale(h))
				end
			end
		end
		return damage * mult
	end

	function Hooks.damaged(unitID, h, damage, attackerID, weaponDefID, para)
		local s = state[unitID]
		if not s or para or damage <= 0 then
			return damage
		end
		local f = frameNow()
		if s.invulnUntil > f then
			return 0
		end
		local pw = s.pw or {}
		local hp, maxHp = spGetUnitHealth(unitID)
		if pw.lowShield and hp and maxHp and s.shieldReady <= f and hp - damage < maxHp * pw.lowShield[1].p.below then
			local v, p = sumPower(s, "lowShield")
			s.shield = v * maxHp
			s.shieldExp = f + p.p.duration * GAME_SPEED
			s.shieldReady = f + p.p.cooldown * GAME_SPEED
			spSetUnitRulesParam(unitID, "items_shield", floor(s.shield), INLOS)
			local F = GG.HeroFX
			if F and F.attach then
				if s.shieldFx and F.detach then
					F.detach(s.shieldFx)
				end
				s.shieldFx = F.attach(unitID, "sphere", { color = { 1.0, 0.85, 0.4, 0.5 }, hex = true, ttl = p.p.duration })
			end
			procEvent(unitID, s, "lowShield", s.shield)
		end
		if s.shield > 0 then
			if s.shieldExp > f then
				local take = min(damage, s.shield)
				s.shield = s.shield - take
				damage = damage - take
				local F = GG.HeroFX
				if s.shieldFx and F and F.hit then
					local x, y, z = spGetUnitPosition(unitID)
					F.hit(s.shieldFx, x, y, z)
				end
			else
				s.shield = 0
			end
		end
		if pw.reflect and inProc == 0 and attackerID and attackerID ~= unitID and damage > 0 then
			local v = sumPower(s, "reflect")
			local amount = min(damage * ((h and h.hpMult) or 1) * v, 20000) -- damage is engine HP: back to effective HP
			procEvent(unitID, s, "reflect", amount)
			later(1, function()
				dealDamage(attackerID, amount, unitID, nil, "reflect")
			end)
		end
		return damage
	end

	function Hooks.dying(unitID, h)
		local s = state[unitID]
		if not s or not (s.pw and s.pw.cheatDeath) then
			return false
		end
		local f = frameNow()
		if s.cheatReady > f then
			return false
		end
		local v, p = sumPower(s, "cheatDeath")
		v = min(0.8, v)
		s.cheatReady = f + p.p.cooldown * GAME_SPEED
		s.invulnUntil = f + p.p.invuln * GAME_SPEED
		spSetUnitRulesParam(unitID, "items_cheat", s.cheatReady, ALLIED)
		later(1, function()
			if spValidUnitID(unitID) and not spGetUnitIsDead(unitID) then
				local _, maxHp = spGetUnitHealth(unitID)
				spSetUnitHealth(unitID, maxHp * v)
				local x, y, z = spGetUnitPosition(unitID)
				fxFlash(x, y + 60, z, { 1.0, 0.55, 0.15, 1 }, 400, "hero-revive")
				local F = GG.HeroFX
				if F and F.pillar then
					F.pillar(x, z, { radius = 120, height = 1200, color = { 1, 0.6, 0.2, 0.9 }, ttl = 1.5 })
				end
			end
		end)
		procEvent(unitID, s, "cheatDeath", v * 100)
		log("Phoenix Heart: hero %d cheats death (%.0f%% health)", unitID, v * 100)
		return true
	end

	function Hooks.frame(f)
	end

	---------------------------------------------------------------- deaths, kills, drops
	local function heroDeath(unitID, level, x, z, teamID)
		local s = state[unitID]
		local drops = {}
		if s then
			for slot = 1, I.SLOTS do
				if s.slots[slot] then
					drops[#drops + 1] = s.slots[slot]
				end
			end
			local F = GG.HeroFX
			if s.shieldFx and F and F.detach then
				F.detach(s.shieldFx)
			end
		end
		state[unitID] = nil
		pendingDeath[unitID] = nil
		if not x then
			return
		end
		drops[#drops + 1] = rollItem({ ilvl = I.ilvlForHero(level) }) -- the trophy
		for i, it in ipairs(drops) do
			local a = i / #drops * 6.283
			local d = #drops > 1 and 160 or 0
			dropItem(it, x + math.cos(a) * d, z + math.sin(a) * d)
		end
		log("hero %d (team %s, level %d) fell: %d items on the ground", unitID, tostring(teamID), level or 1, #drops)
	end

	function Hooks.onHeroDeath(unitID, h, x, z)
		local pd = pendingDeath[unitID]
		if not pd and not state[unitID] and not x then
			return
		end
		if not x and pd then
			x, z = pd.x, pd.z
		end
		heroDeath(unitID, (h and h.level) or (pd and pd.level) or 1, x, z, h and h.team or (pd and pd.team))
	end

	local function processKill(heroID, victimID, victimDefID, pk)
		pendingKill[victimID] = nil
		local heroes = heroesTbl()
		local h = heroes[heroID]
		local s = state[heroID]
		local x, z = pk and pk.x, pk and pk.z
		if not x then
			local vx, _, vz = spGetUnitPosition(victimID)
			x, z = vx, vz
		end
		local f = frameNow()
		if s and s.pw then
			if s.pw.souls then
				local p = s.pw.souls[1]
				if s.souls < p.p.stacks then
					s.souls = s.souls + 1
					s.needRefresh = true
					procEvent(heroID, s, "souls", s.souls)
					spSetUnitRulesParam(heroID, "items_souls", s.souls, INLOS)
				end
				s.lastKill = f
			end
			if s.pw.blastKill and x and not procKills[victimID] then
				local v, p = sumPower(s, "blastKill")
				local maxHp = pk and pk.maxHp or unitHealth[victimDefID] or 0
				local dmg = min(p.p.cap, maxHp * v) * procScale(h)
				blastAt(heroID, h, x, z, dmg, p.p.radius, s.ally, victimID)
				procEvent(heroID, s, "blastKill", dmg)
			end
		end
		-- drops (heroes drop in heroDeath)
		if x and not isHeroDef[victimDefID] and (pk == nil or pk.team ~= (s and s.team or spGetUnitTeam(heroID))) then
			local cost = unitCost[victimDefID] or 0
			if random() < min(I.DROP_MAX, cost * I.DROP_CHANCE) then
				local it = rollItem({ ilvl = I.ilvlForCost(cost) })
				dropItem(it, x, z)
				log("drop: %s (%s ilvl %d) from %s killed by hero %d", I.name(it), it.rarity, it.ilvl,
					UnitDefs[victimDefID] and UnitDefs[victimDefID].name or "?", heroID)
			end
		end
	end

	function Hooks.onKill(heroID, victimID, victimDefID)
		local pk = pendingKill[victimID]
		if pk and pk.done then
			return
		end
		if pk then
			pk.done = true
		end
		processKill(heroID, victimID, victimDefID or (pk and pk.defID) or spGetUnitDefID(victimID), pk)
	end

	---------------------------------------------------------------- actives
	local function useSlot(unitID, slot)
		local s = state[unitID]
		local it = s and s.slots[slot]
		if not it then
			return false
		end
		local f = frameNow()
		if (s.cd[slot] or 0) > f then
			return false
		end
		local active
		for _, p in ipairs(I.powers(it)) do
			if I.powerInfo[p.key] and I.powerInfo[p.key].active then
				active = p
			end
		end
		if not active then
			return false
		end
		if active.key == "blink" then
			local x, y, z = spGetUnitPosition(unitID)
			if not x then
				return false
			end
			local dx, dz
			local cmds = Spring.GetUnitCommands(unitID, 1)
			local c = cmds and cmds[1]
			if c and c.id == CMD.MOVE and c.params[3] then
				dx, dz = c.params[1] - x, c.params[3] - z
			elseif s.blinkDir then
				dx, dz = s.blinkDir[1], s.blinkDir[2]
			else
				local ux, _, uz = Spring.GetUnitDirection(unitID)
				dx, dz = ux, uz
			end
			s.blinkDir = nil
			local len = sqrt(dx * dx + dz * dz)
			if len < 1e-3 then
				return false
			end
			local dist = active.v
			if c and c.id == CMD.MOVE then
				dist = min(dist, len)
			end
			local tx = max(64, min(Game.mapSizeX - 64, x + dx / len * dist))
			local tz = max(64, min(Game.mapSizeZ - 64, z + dz / len * dist))
			fxFlash(x, y + 50, z, { 0.6, 0.8, 1.0, 1 }, 260, "hero-phase")
			Spring.SetUnitPosition(unitID, tx, tz)
			fxFlash(tx, spGetGroundHeight(tx, tz) + 50, tz, { 0.6, 0.8, 1.0, 1 }, 260, "hero-phase")
		end
		local cdr = min(0.4, s.stats and s.stats.cdr or 0)
		local len = floor(active.p.cooldown * (1 - cdr) * GAME_SPEED)
		s.cd[slot] = f + len
		s.cdByUid[it.uid] = s.cd[slot]
		spSetUnitRulesParam(unitID, "items_cd_" .. slot, s.cd[slot], ALLIED)
		spSetUnitRulesParam(unitID, "items_cdlen_" .. slot, len, ALLIED)
		toUI("use", s.team, unitID, it.str, slot)
		return true
	end

	---------------------------------------------------------------- periodic powers (every second)
	local function secondTick(f)
		for k in pairs(guard) do
			guard[k] = nil
		end
		for k in pairs(war) do
			war[k] = nil
		end
		for uid, pf in pairs(procKills) do
			if f - pf > 2 * GAME_SPEED then
				procKills[uid] = nil
			end
		end
		for uid, mk in pairs(marks) do
			if mk.expire < f or not spValidUnitID(uid) then
				marks[uid] = nil
			end
		end
		local heroes = heroesTbl()
		for unitID, s in pairs(state) do
			local h = heroes[unitID]
			local pw = s.pw
			if pw and h and not spGetUnitIsDead(unitID) then
				local x, y, z = spGetUnitPosition(unitID)
				if x then
					s.ally = spGetUnitAllyTeam(unitID)
					if pw.guardAura or pw.warAura then
						local gv, gp = sumPower(s, "guardAura")
						local wv, wp = sumPower(s, "warAura")
						local r = max(gp and gp.p.radius or 0, wp and wp.p.radius or 0)
						for _, uid in ipairs(spGetUnitsInCylinder(x, z, r)) do
							if spGetUnitAllyTeam(uid) == s.ally then
								local ux, _, uz = spGetUnitPosition(uid)
								local d2 = ux and (ux - x) ^ 2 + (uz - z) ^ 2 or math.huge
								if gp and d2 <= gp.p.radius ^ 2 then
									guard[uid] = max(guard[uid] or 0, min(0.5, gv))
								end
								if wp and d2 <= wp.p.radius ^ 2 then
									war[uid] = max(war[uid] or 0, wv)
								end
							end
						end
					end
					if pw.orbital then
						local v, p = sumPower(s, "orbital")
						if (s.timers.orbital or 0) <= f then
							local range = maxRange[spGetUnitDefID(unitID)] or 1000
							local target = Spring.GetUnitNearestEnemy(unitID, max(600, range), true)
							if target then
								s.timers.orbital = f + p.p.period * GAME_SPEED
								local tx, ty, tz = spGetUnitPosition(target)
								local F = GG.HeroFX
								if F and F.beam then
									F.beam(tx, ty + 2500, tz, tx, ty, tz, { color = { 1.0, 0.85, 0.4, 1 }, width = 40, ttl = 0.8, core = 1 })
									if F.ring then
										F.ring(tx, tz, { r0 = 20, r1 = 220, color = { 1, 0.8, 0.3, 0.9 }, ttl = 0.6, kind = "shock" })
									end
								else
									spSpawnCEG("hero-nova-fire", tx, ty, tz, 0, 1, 0, 0, 0)
								end
								local dmg = v * procScale(h)
								procEvent(unitID, s, "orbital", dmg)
								later(4, function()
									dealDamage(target, dmg, unitID, "laser", "orbital")
								end)
							end
						end
					end
					if pw.staticWake then
						local v, p = sumPower(s, "staticWake")
						if (s.timers.wake or 0) <= f then
							local targets = enemiesNear(x, z, p.p.radius, s.ally, p.p.targets)
							if #targets > 0 then
								s.timers.wake = f + p.p.period * GAME_SPEED
								local dmg = v * procScale(h)
								procEvent(unitID, s, "staticWake", dmg)
								for _, t in ipairs(targets) do
									local tx, ty, tz = spGetUnitPosition(t)
									fxBolt(x, y + 80, z, tx, ty + 20, tz, { 0.75, 0.45, 1.0, 1 })
									later(1, function()
										dealDamage(t, dmg, unitID, "electric", "staticWake")
									end)
								end
							end
						end
					end
					if pw.souls and s.souls > 0 then
						local p = pw.souls[1]
						if f - s.lastKill > p.p.decay * GAME_SPEED * 3 and (s.timers.soulDecay or 0) <= f then
							s.timers.soulDecay = f + p.p.decay * GAME_SPEED
							s.souls = s.souls - 1
							s.needRefresh = true
							spSetUnitRulesParam(unitID, "items_souls", s.souls, INLOS)
						end
					end
				end
				if s.shield > 0 and s.shieldExp <= f then
					s.shield = 0
				end
				spSetUnitRulesParam(unitID, "items_shield", floor(s.shield), INLOS)
				if s.needRefresh then
					s.needRefresh = false
					refreshHero(unitID)
				end
			end
		end
	end

	---------------------------------------------------------------- AI: equip, shop, salvage, build the shop
	local function roleOf(h)
		return h and h.def and (h.def.cfg and h.def.cfg.aiRole or h.def.aiRole) or "center"
	end

	local function aiScore(it, h, unitID, s)
		local udid = spGetUnitDefID(unitID)
		local sc = I.score(it, roleOf(h), heroTypes(udid))
		if it.rarity == "set" and s then
			local n = 0
			for _, w in pairs(s.slots) do
				if w ~= it and w.rarity == "set" and w.set == it.set then
					n = n + 1
				end
			end
			sc = sc + 0.6 * n
		end
		return sc
	end

	local function aiHeroes(teamID)
		local list = {}
		for unitID, h in pairs(heroesTbl()) do
			if spGetUnitTeam(unitID) == teamID and not spGetUnitIsDead(unitID) then
				list[#list + 1] = { uid = unitID, h = h }
			end
		end
		table.sort(list, function(a, b) return (a.h.level or 1) > (b.h.level or 1) end)
		return list
	end

	local function aiEquipTeam(teamID)
		local changedStash = false
		for _, e in ipairs(aiHeroes(teamID)) do
			local unitID, h = e.uid, e.h
			local s = st(unitID)
			local changed = false
			for _, cat in ipairs(I.categoryOrder) do
				local slots = I.categories[cat].slots
				local cand = {}
				for _, slot in ipairs(slots) do
					if s.slots[slot] then
						cand[#cand + 1] = { it = s.slots[slot], slot = slot }
					end
				end
				for _, it in ipairs(stash[teamID] or {}) do
					if it.cat == cat then
						cand[#cand + 1] = { it = it }
					end
				end
				for _, c in ipairs(cand) do
					c.score = aiScore(c.it, h, unitID, s) + (c.slot and 0.05 or 0)
				end
				table.sort(cand, function(a, b) return a.score > b.score end)
				local want, keyUsed = {}, {}
				for _, c in ipairs(cand) do
					local key = c.it.rarity == "unique" and ("u" .. c.it.unique) or (c.it.rarity == "set" and ("s" .. c.it.set .. ":" .. c.it.piece)) or ("i" .. c.it.uid)
					if #want < #slots and not keyUsed[key] then
						keyUsed[key] = true
						want[#want + 1] = c
					end
				end
				local keep = {}
				for _, c in ipairs(want) do
					if c.slot then
						keep[c.slot] = true
					end
				end
				-- off: worn items not wanted; on: wanted stash items
				for _, slot in ipairs(slots) do
					if s.slots[slot] and not keep[slot] then
						local old = setSlot(s, slot, nil)
						stash[teamID] = stash[teamID] or {}
						table.insert(stash[teamID], old)
						changed, changedStash = true, true
					end
				end
				for _, c in ipairs(want) do
					if not c.slot then
						for i, it in ipairs(stash[teamID]) do
							if it == c.it then
								table.remove(stash[teamID], i)
								break
							end
						end
						local slot = firstSlotFor(s, cat)
						setSlot(s, slot, c.it)
						changed, changedStash = true, true
						log("AI team %d: %s (lv %d, %s) equips %s [%s ilvl %d] in slot %d (score %.2f)", teamID,
							h.def and h.def.name or "?", h.level or 1, roleOf(h), I.name(c.it), c.it.rarity, c.it.ilvl, slot, c.score)
					end
				end
			end
			if changed then
				itemsChanged(unitID, s)
			end
		end
		if changedStash then
			publishStash(teamID)
		end
		aiDirty[teamID] = nil
	end

	-- the best gain an item would bring to any hero of the team over its worst worn item of that category
	local function aiGain(teamID, it, heroes)
		local best = -1
		for _, e in ipairs(heroes) do
			local s = st(e.uid)
			local sc = aiScore(it, e.h, e.uid, s)
			local worst = math.huge
			for _, slot in ipairs(I.categories[it.cat].slots) do
				local w = s.slots[slot]
				local ws = w and aiScore(w, e.h, e.uid, s) or 0
				worst = min(worst, ws)
			end
			best = max(best, sc - worst)
		end
		return best
	end

	-- AI item budget: every 10 s an AI team with heroes and a shop puts aside up to ITEM_SHARE of its metal income
	-- into its own item bank (taken from storage like the hero gadget's hero_ai_bank, which is already out of
	-- storage - so the two never fight over the same metal; we start at a lower storage fill than it does).
	-- A purchase is paid from the item bank first, then from storage down to ITEM_FLOOR.
	-- Team rules param items_ai_bank (allied).
	local ITEM_SHARE = 0.22
	local ITEM_FLOOR = 8000
	local ITEM_FILL = 0.12    -- take only while storage is fuller than this
	local itemBank = {}

	local function aiBankTick(teamID, heroes)
		local cur, stor, _, inc = Spring.GetTeamResources(teamID, "metal")
		cur, stor, inc = cur or 0, stor or 0, inc or 0
		local b = itemBank[teamID] or 0
		local sh = shelf[teamID]
		local want = 0
		if #heroes > 0 and sh and shopUnit(teamID) then
			for _, it in pairs(sh.items) do
				if it then
					want = max(want, I.price(it))
				end
			end
			want = max(15000, want * 1.3)
		end
		if b < want and inc > 0 and cur > stor * ITEM_FILL then
			local take = min(inc * ITEM_SHARE * 10, cur - stor * ITEM_FILL, want - b)
			if take > 0 and Spring.UseTeamResource(teamID, "metal", take) then
				b = b + take
			end
		elseif b > want then
			local back = min(b - want, max(0, stor - cur))
			if back > 0 then
				Spring.AddTeamResource(teamID, "metal", back)
				b = b - back
			end
		end
		itemBank[teamID] = b
		spSetTeamRulesParam(teamID, "items_ai_bank", floor(b), ALLIED)
	end

	-- pay `price` from the item bank, then from storage above ITEM_FLOOR
	local function aiPay(teamID, price, dry)
		local b = itemBank[teamID] or 0
		local cur = Spring.GetTeamResources(teamID, "metal") or 0
		local fromStore = max(0, price - b)
		if fromStore > 0 and cur - fromStore < ITEM_FLOOR then
			return false
		end
		if dry then
			return true
		end
		if fromStore > 0 and not Spring.UseTeamResource(teamID, "metal", fromStore) then
			return false
		end
		itemBank[teamID] = b - (price - fromStore)
		spSetTeamRulesParam(teamID, "items_ai_bank", floor(itemBank[teamID]), ALLIED)
		return true
	end

	local function aiShop(teamID, heroes, f)
		local sh = shelf[teamID]
		if not sh or not shopUnit(teamID) then
			return
		end
		local bestIdx, bestGain, bestPrice
		for i, it in pairs(sh.items) do
			if it then
				local price = I.price(it)
				local gain = aiGain(teamID, it, heroes)
				if gain > 0.3 and aiPay(teamID, price, true) and (not bestGain or gain / price > bestGain / bestPrice) then
					bestIdx, bestGain, bestPrice = i, gain, price
				end
			end
		end
		if bestIdx then
			local it = sh.items[bestIdx]
			if #(stash[teamID] or {}) < I.STASH_SIZE and aiPay(teamID, bestPrice) then
				if shopBuy(teamID, bestIdx, nil, true) then
					log("AI team %d buys %s [%s ilvl %d] for %d metal (gain %.2f, item bank left %d)", teamID, I.name(it), it.rarity,
						it.ilvl, bestPrice, bestGain, itemBank[teamID] or 0)
					aiDirty[teamID] = true
				else
					itemBank[teamID] = (itemBank[teamID] or 0) + bestPrice -- not sold: keep the metal for items
				end
			end
		elseif (itemBank[teamID] or 0) >= 15000 and f - (sh.aiRefreshed or 0) > 120 * GAME_SPEED
			and aiPay(teamID, I.SHOP_REFRESH_FEE, true) then
			-- nothing worth buying and the budget is full: pay for a new shelf
			sh.aiRefreshed = f
			if aiPay(teamID, I.SHOP_REFRESH_FEE) then
				shopRefresh(teamID, true)
				log("AI team %d refreshes the shelf (item bank %d)", teamID, itemBank[teamID] or 0)
			end
		end
	end

	-- salvage: over 12 stash items, everything clearly worse than what every hero wears in its category
	-- (gain < -0.15 for each hero, all of their slots of that category full); over 30, the worst down to 30
	local function aiSalvage(teamID, heroes)
		local s = stash[teamID]
		if not s or #s <= 12 or #heroes == 0 then
			return
		end
		local scored = {}
		for _, it in ipairs(s) do
			scored[#scored + 1] = { it = it, gain = aiGain(teamID, it, heroes) }
		end
		table.sort(scored, function(a, b) return a.gain < b.gain end)
		local n = #s
		for _, c in ipairs(scored) do
			if not (c.gain < -0.15 or n > 30) then
				break
			end
			local idx = findStash(teamID, nil, c.it.uid)
			if idx then
				local ok, metal = salvage(teamID, idx)
				if ok then
					n = n - 1
					log("AI team %d salvages %s [%s ilvl %d] for %d metal (gain %.2f, stash %d)", teamID, I.name(c.it), c.it.rarity,
						c.it.ilvl, metal, c.gain, n)
				end
			end
			if n <= 12 then
				break
			end
		end
	end

	-- AI teams build their shop with a builder borrowed from the skirmish AI (BARb would re-task it at once):
	-- "detach" it, order the build at a site checked with TestBuildOrder near the altar, follow the nanoframe,
	-- send up to SHOP_HELPERS more builders to help, retry with another builder / site on a timeout, and hand
	-- every borrowed unit back ("attach") when the shop stands or the job is given up.
	local SHOP_HELPERS = 2
	local SHOP_START_TIMEOUT = 75 * GAME_SPEED   -- no nanoframe this long after the order: retry
	local SHOP_JOB_TIMEOUT = 6 * 60 * GAME_SPEED -- the whole job; then give up for SHOP_COOLDOWN
	local SHOP_COOLDOWN = 90 * GAME_SPEED
	local shopJob = {}   -- teamID -> { builder, helpers = {}, def, x, z, issued, started, tries, bad = {uid=true} }
	local shopRetry = {} -- teamID -> frame the next job may start

	local function toAI(teamID, text)
		SendToUnsynced("t4heroitems_aimsg", teamID, text)
	end

	local function alive(uid)
		return uid and spValidUnitID(uid) and not spGetUnitIsDead(uid)
	end

	local function teamShopFrames(teamID)
		for _, sname in pairs(I.SHOPS) do
			local sd = UnitDefNames[sname]
			if sd then
				for _, uid in ipairs(Spring.GetTeamUnitsByDefs(teamID, sd.id) or {}) do
					return uid, sd.id
				end
			end
		end
	end

	local function borrowed(uid)
		local G = GG.T4Heroes
		if G and G.escorts then
			for _, e in pairs(G.escorts) do
				if e.units and e.units[uid] then
					return true
				end
			end
		end
		return (GG.AICommanderUnits or {})[uid]
	end

	local function releaseJob(teamID, why)
		local job = shopJob[teamID]
		if not job then
			return
		end
		local ids = {}
		local all = { job.builder }
		for _, h in ipairs(job.helpers) do
			all[#all + 1] = h
		end
		for _, uid in pairs(all) do
			if alive(uid) and spGetUnitTeam(uid) == teamID then
				Spring.GiveOrderToUnit(uid, CMD.STOP, {}, 0)
				ids[#ids + 1] = uid
			end
		end
		if #ids > 0 then
			toAI(teamID, "attach " .. table.concat(ids, ","))
		end
		log("AI team %d: shop job ends (%s), %d builders handed back", teamID, why, #ids)
		shopJob[teamID] = nil
	end

	local function altarPos(teamID)
		for _, uid in ipairs(Spring.GetTeamUnits(teamID)) do
			if altarDefs[spGetUnitDefID(uid)] then
				local x, _, z = spGetUnitPosition(uid)
				return x, z
			end
		end
	end

	-- builders that can make a shop, best first (finished, ground, few orders, near the altar)
	local function shopBuilders(teamID, ax, az, exclude)
		local list = {}
		for _, uid in ipairs(Spring.GetTeamUnits(teamID)) do
			local udid = spGetUnitDefID(uid)
			local sdid = builderShop[udid]
			if sdid and not exclude[uid] and alive(uid) and not borrowed(uid) then
				local _, _, _, _, bp = spGetUnitHealth(uid)
				if bp and bp >= 1 then
					local x, _, z = spGetUnitPosition(uid)
					local d = ax and sqrt((x - ax) ^ 2 + (z - az) ^ 2) or 0
					local score = d + (UnitDefs[udid].canFly and 1500 or 0) + Spring.GetUnitCommandCount(uid) * 150
					list[#list + 1] = { uid = uid, sdid = sdid, x = x, z = z, score = score }
				end
			end
		end
		table.sort(list, function(a, b) return a.score < b.score end)
		return list
	end

	local function findSite(teamID, sdid, cx, cz, tries)
		local rings = { 260, 380, 520, 680, 860, 1060 }
		for ri = 1, #rings do
			local r = rings[ri] + (tries or 0) * 60
			for k = 0, 15 do
				local a = k / 16 * 6.283 + ri * 0.7 + (tries or 0)
				local x = floor((cx + math.cos(a) * r) / 16) * 16 + 8
				local z = floor((cz + math.sin(a) * r) / 16) * 16 + 8
				if x > 96 and z > 96 and x < Game.mapSizeX - 96 and z < Game.mapSizeZ - 96 then
					local y = spGetGroundHeight(x, z)
					if y > 0 and Spring.TestBuildOrder(sdid, x, y, z, 0) == 2 then
						return x, y, z
					end
				end
			end
		end
	end

	local function startJob(teamID, f, job)
		local ax, az = altarPos(teamID)
		job = job or { helpers = {}, tries = 0, bad = {}, began = f }
		local cands = shopBuilders(teamID, ax, az, job.bad)
		local c = cands[1]
		if not c then
			return false
		end
		local x, y, z = findSite(teamID, c.sdid, ax or c.x, az or c.z, job.tries)
		if not x then
			job.bad[c.uid] = true
			return false
		end
		job.builder, job.def, job.x, job.z, job.issued = c.uid, c.sdid, x, z, f
		job.tries = job.tries + 1
		toAI(teamID, "detach " .. c.uid)
		Spring.GiveOrderToUnit(c.uid, CMD.STOP, {}, 0)
		Spring.GiveOrderToUnit(c.uid, -c.sdid, { x, y, z, 0 }, 0)
		shopJob[teamID] = job
		log("AI team %d: builder %d (%s) detached, builds a %s at %d,%d (try %d)", teamID, c.uid, UnitDefs[spGetUnitDefID(c.uid)].name,
			UnitDefs[c.sdid].name, x, z, job.tries)
		return true
	end

	local function aiBuildShop(teamID, heroes, f)
		local job = shopJob[teamID]
		if shopUnit(teamID) then
			if job then
				releaseJob(teamID, "shop finished")
			end
			return
		end
		if not job then
			if #heroes == 0 or f < (shopRetry[teamID] or 0) or (Spring.GetTeamResources(teamID, "metal") or 0) < 2000 then
				return
			end
			local nano = teamShopFrames(teamID)
			if nano then
				-- a frame is standing (the AI's own or an old job): adopt it
				job = { helpers = {}, tries = 1, bad = {}, began = f, issued = f, nano = nano }
				shopJob[teamID] = job
			elseif not startJob(teamID, f) then
				shopRetry[teamID] = f + SHOP_COOLDOWN
				return
			end
			job = shopJob[teamID]
		end
		if f - job.began > SHOP_JOB_TIMEOUT then
			releaseJob(teamID, "timeout")
			shopRetry[teamID] = f + SHOP_COOLDOWN
			return
		end
		local nano = teamShopFrames(teamID)
		if nano then
			job.nano = nano
			job.started = job.started or f
		end
		if not alive(job.builder) then
			job.builder = nil
		end
		if job.nano and alive(job.nano) then
			-- everyone borrowed keeps building it; up to SHOP_HELPERS more join
			local workers = { job.builder }
			for _, h in ipairs(job.helpers) do
				workers[#workers + 1] = h
			end
			if #job.helpers < SHOP_HELPERS or not job.builder then
				local ax, az = spGetUnitPosition(job.nano)
				local ex = { [job.builder or -1] = true }
				for _, h in ipairs(job.helpers) do
					ex[h] = true
				end
				for _, c in ipairs(shopBuilders(teamID, ax, az, ex)) do
					if #job.helpers >= SHOP_HELPERS and job.builder then
						break
					end
					if c.score < 2500 then
						toAI(teamID, "detach " .. c.uid)
						if not job.builder then
							job.builder = c.uid
						else
							job.helpers[#job.helpers + 1] = c.uid
						end
						workers[#workers + 1] = c.uid
					end
				end
			end
			for _, uid in pairs(workers) do
				if alive(uid) and Spring.GetUnitCommandCount(uid) == 0 then
					Spring.GiveOrderToUnit(uid, CMD.REPAIR, { job.nano }, 0)
				end
			end
			return
		end
		-- no frame yet: the builder must still be on its way with the order
		local idle = not job.builder or Spring.GetUnitCommandCount(job.builder) == 0
		if idle or f - job.issued > SHOP_START_TIMEOUT then
			if job.builder then
				job.bad[job.builder] = true
				toAI(teamID, "attach " .. job.builder)
				Spring.GiveOrderToUnit(job.builder, CMD.STOP, {}, 0)
				job.builder = nil
			end
			if job.tries >= 4 or not startJob(teamID, f, job) then
				releaseJob(teamID, "no builder could start it")
				shopRetry[teamID] = f + SHOP_COOLDOWN
			end
		end
	end

	local function aiAutoUse(teamID, heroes)
		for _, e in ipairs(heroes) do
			local s = state[e.uid]
			if s and s.pw and s.pw.blink then
				local hp, maxHp = spGetUnitHealth(e.uid)
				if hp and hp < maxHp * 0.3 then
					local x, _, z = spGetUnitPosition(e.uid)
					local en = Spring.GetUnitNearestEnemy(e.uid, 1500, true)
					local ex, _, ez = en and spGetUnitPosition(en)
					if ex then
						s.blinkDir = { x - ex, z - ez }
						useSlot(e.uid, s.pw.blink[1].slot)
					end
				end
			end
		end
	end

	local function aiTick(f)
		for teamID, isAI in pairs(isAITeam) do
			if isAI then
				local heroes = aiHeroes(teamID)
				if #heroes > 0 then
					if aiDirty[teamID] or f >= (aiNext[teamID] or 0) then
						aiEquipTeam(teamID)
					end
					if f >= (aiNext[teamID] or 0) then
						aiNext[teamID] = f + 10 * GAME_SPEED
						aiBankTick(teamID, heroes)
						aiShop(teamID, heroes, f)
						aiSalvage(teamID, heroes)
					end
					aiAutoUse(teamID, heroes)
					if f % (2 * GAME_SPEED) < 15 then
						aiBuildShop(teamID, heroes, f)
					end
				end
			end
		end
	end

	---------------------------------------------------------------- messages
	local function handle(msg, teamID)
		local what, rest = msg:match("^t4hero:(%a+):?(.*)$")
		if what == "equip" then
			local uid, slot, idx, iuid = rest:match("^(%d+):(%d+)_(%d+)_?(%d*)$")
			uid, slot, idx = tonumber(uid), tonumber(slot), tonumber(idx)
			if uid and heroesTbl()[uid] and spGetUnitTeam(uid) == teamID and I.slotCategory[slot] then
				equipFromStash(uid, slot, idx, tonumber(iuid))
			end
			return true
		elseif what == "unequip" or what == "use" then
			local uid, slot = rest:match("^(%d+):(%d+)$")
			uid, slot = tonumber(uid), tonumber(slot)
			if uid and spGetUnitTeam(uid) == teamID and I.slotCategory[slot] then
				if what == "unequip" then
					unequip(uid, slot)
				else
					useSlot(uid, slot)
				end
			end
			return true
		elseif what == "salvage" then
			local idx, iuid = rest:match("^(%d+)_?(%d*)$")
			if idx then
				salvage(teamID, tonumber(idx), tonumber(iuid))
			end
			return true
		elseif what == "shopbuy" then
			local idx, iuid = rest:match("^(%d+)_?(%d*)$")
			if idx then
				shopBuy(teamID, tonumber(idx), tonumber(iuid))
			end
			return true
		elseif what == "shoprefresh" then
			shopRefresh(teamID)
			return true
		end
		return false
	end

	function gadget:RecvLuaMsg(msg, playerID)
		if msg:sub(1, 7) ~= "t4hero:" then
			return
		end
		local _, _, spec, teamID = Spring.GetPlayerInfo(playerID, false)
		if spec then
			return
		end
		if handle(msg, teamID) then
			return true
		end
	end

	---------------------------------------------------------------- damage callin: auras and marks
	function gadget:UnitPreDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID)
		if not (next(guard) or next(marks) or next(war)) then
			return damage, 1
		end
		local m = 1
		local g = guard[unitID]
		if g then
			m = m * (1 - g)
		end
		local mk = marks[unitID]
		if mk and mk.expire >= frameNow() then
			m = m * (1 + mk.v)
		end
		if attackerID then
			local w = war[attackerID]
			if w then
				m = m * (1 + w)
			end
		end
		return damage * m, 1
	end

	---------------------------------------------------------------- unit callins
	local function addShop(unitID, teamID)
		shops[teamID] = shops[teamID] or {}
		shops[teamID][unitID] = true
		if not shelf[teamID] then
			rollShelf(teamID)
		else
			publishShelf(teamID)
		end
	end

	function gadget:UnitFinished(unitID, unitDefID, teamID)
		if shopDefs[unitDefID] then
			addShop(unitID, teamID)
		end
	end

	function gadget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
		if shopDefs[unitDefID] then
			if shops[oldTeam] then
				shops[oldTeam][unitID] = nil
				publishShelf(oldTeam)
			end
			local _, _, _, _, bp = spGetUnitHealth(unitID)
			if bp and bp >= 1 then
				addShop(unitID, newTeam)
			end
		end
		local s = state[unitID]
		if s then
			s.team, s.ally = newTeam, spGetUnitAllyTeam(unitID)
		end
	end

	function gadget:UnitDestroyed(unitID, unitDefID, teamID, attackerID)
		if shopDefs[unitDefID] and shops[teamID] then
			shops[teamID][unitID] = nil
			publishShelf(teamID)
		end
		marks[unitID] = nil
		if inProc > 0 then
			procKills[unitID] = frameNow()
		end
		local x, _, z = spGetUnitPosition(unitID)
		-- a hero: drop in the next frame unless the hero gadget calls onHeroDeath first
		local h = heroesTbl()[unitID]
		if state[unitID] or (h and isHeroDef[unitDefID]) then
			pendingDeath[unitID] = { x = x, z = z, level = h and h.level or 1, team = teamID }
		end
		-- killed by a hero: drops / powers in the next frame unless the hero gadget calls onKill first
		if attackerID and heroesTbl()[attackerID] and spGetUnitAllyTeam(attackerID) ~= spGetUnitAllyTeam(unitID) then
			local _, maxHp, _, _, bp = spGetUnitHealth(unitID)
			if bp and bp >= 1 then
				pendingKill[unitID] = { hero = attackerID, defID = unitDefID, x = x, z = z, maxHp = maxHp, team = teamID }
			end
		end
	end

	---------------------------------------------------------------- frames
	function gadget:GameFrame(f)
		-- deferred power effects
		if #queue > 0 then
			local q = queue
			queue = {}
			for _, e in ipairs(q) do
				if e.at <= f then
					e.fn()
				else
					queue[#queue + 1] = e
				end
			end
		end
		-- the hero gadget did not report these deaths / kills: handle them here
		for victimID, pk in pairs(pendingKill) do
			if not pk.done then
				processKill(pk.hero, victimID, pk.defID, pk)
			end
			pendingKill[victimID] = nil
		end
		for unitID, pd in pairs(pendingDeath) do
			heroDeath(unitID, pd.level, pd.x, pd.z, pd.team)
		end
		if f % 15 == 3 then
			pickups()
		end
		if f % GAME_SPEED == 7 then
			secondTick(f)
			for id, g in pairs(ground) do
				if g.expire <= f then
					removeGround(id)
				end
			end
			for teamID, sh in pairs(shelf) do
				if sh.next <= f and shopUnit(teamID) then
					shopRefresh(teamID, true)
				end
			end
			for unitID in pairs(state) do
				if not spValidUnitID(unitID) then
					state[unitID] = nil
				end
			end
		end
		if f % 15 == 11 then
			aiTick(f)
		end
		if groundDirty then
			publishGround()
		end
	end

	---------------------------------------------------------------- init
	function gadget:Initialize()
		for _, teamID in ipairs(Spring.GetTeamList()) do
			publishStash(teamID)
			spSetTeamRulesParam(teamID, "items_shop", "", ALLIED)
			spSetTeamRulesParam(teamID, "items_shop_unit", 0, ALLIED)
		end
		for _, uid in ipairs(Spring.GetAllUnits()) do
			local udid = spGetUnitDefID(uid)
			if shopDefs[udid] then
				local _, _, _, _, bp = spGetUnitHealth(uid)
				if bp and bp >= 1 then
					addShop(uid, spGetUnitTeam(uid))
				end
			end
		end
		publishGround()
		local api = {
			I = I,
			mods = Hooks.mods, hit = Hooks.hit, damaged = Hooks.damaged, dying = Hooks.dying, frame = Hooks.frame,
			onHeroDeath = Hooks.onHeroDeath, onKill = Hooks.onKill,
			-- scenes / AI / tests
			roll = function(opts) return rollItem(opts) end,
			give = function(teamID, it) return stashAdd(teamID, asItem(it)) end,
			equip = function(unitID, it, slot) return equipDirect(unitID, it, slot) end,
			equipFromStash = function(unitID, slot, idx, uid) return equipFromStash(unitID, slot, idx, uid) end,
			unequip = function(unitID, slot) return unequip(unitID, slot) end,
			use = function(unitID, slot) return useSlot(unitID, slot) end,
			salvage = function(teamID, idx, uid) return salvage(teamID, idx, uid) end,
			shopBuy = function(teamID, idx, uid) return shopBuy(teamID, idx, uid) end,
			shopRefresh = function(teamID, free) return shopRefresh(teamID, free) end,
			shelf = function(teamID) return shelf[teamID] end,
			drop = function(it, x, z) return dropItem(it, x, z) end,
			stash = function(teamID) return stash[teamID] or {} end,
			worn = function(unitID) return state[unitID] and state[unitID].slots or {} end,
			state = function(unitID) return state[unitID] end,
			handle = handle,
			-- true while an item power deals its damage: the hero gadget should not multiply it again
			-- (it is already scaled by the hero's level) nor run on-hit effects for it
			isItemDamage = function() return inProc > 0 end,
			setAI = function(teamID, ai) isAITeam[teamID] = ai end,
			aiEquip = function(teamID) aiEquipTeam(teamID) end,
			ground = ground,
		}
		GG.T4HeroItems = api
	end

	function gadget:Shutdown()
		GG.T4HeroItems = nil
	end
else
	----------------------------------------------------------------------------- unsynced
	local spGetMyAllyTeamID = Spring.GetMyAllyTeamID
	local spGetSpectatingState = Spring.GetSpectatingState

	local function itemEvent(_, kind, teamID, unitID, str, num)
		local _, fullView = spGetSpectatingState()
		if teamID >= 0 and not fullView then
			local ally = select(6, Spring.GetTeamInfo(teamID, false))
			if ally ~= spGetMyAllyTeamID() then
				return
			end
		end
		if Script.LuaUI("T4HeroItemEvent") then
			Script.LuaUI.T4HeroItemEvent(kind, teamID, unitID, str, num)
		end
	end

	function gadget:Initialize()
		gadgetHandler:AddSyncAction("t4heroitems_event", itemEvent)
		-- detach / attach builders for the AI's shop (only the client hosting that AI delivers it)
		gadgetHandler:AddSyncAction("t4heroitems_aimsg", function(_, teamID, text)
			Spring.SendSkirmishAIMessage(teamID, text)
		end)
	end

	function gadget:Shutdown()
		gadgetHandler:RemoveSyncAction("t4heroitems_event")
		gadgetHandler:RemoveSyncAction("t4heroitems_aimsg")
	end
end
