local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "T4 Heroes",
		desc = "Custom T4 heroes: levels 1-100, abilities (generic kit + per-hero modules), five stats, hero cap and altar upgrades, revive, AI care",
		author = "denysfast",
		date = "2026-10-02",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = true,
	}
end

-- v19 (doc/v19-heroes/SPEC.md sections 2-4; CUSTOM.md, "T4 heroes"). Design data: luarules/configs/t4_heroes.lua,
-- abilities luarules/configs/heroes/<faction>.lua, behaviour modules luarules/heroes/<heroname>.lua.
--
-- Protocol (LuaRules messages from the owner's UI; only from a non-spectator of the hero's / altar's team):
--   t4hero:learn:<unitID>:<key>       spend a point (+ metal) on a rank: a1 | a2 | a3 | ult | vit | mob | dmg | rng | imp
--   t4hero:buylevel:<unitID>          buy one level for metal (price H.levelPrice, one per H.BUY_COOLDOWN s)
--   t4hero:altar:<altarID>            start the next altar upgrade, or cancel the running one (= CMD_ALTAR_UPGRADE)
--   (item messages, e.g. t4hero:salvage:..., belong to the items gadget: this one never swallows them)
-- Commands: CMD_HERO_AUTOCAST 36100 (heroes, mode 0/1), CMD_ALTAR_UPGRADE 36400 (altars, instant: start / cancel), ability commands
--   from the hero configs (Armada 36101-36199, Cortex 36201-36299, Legion 36301-36399, core 36400+).
-- Unit rules params of a hero (INLOS = everyone who sees it, ALLIED = its allies):
--   hero_level (INLOS), hero_xp (0..1 to the next level), hero_xp_abs, hero_xp_need, hero_points, hero_kills,
--   hero_rank_<key> (every key of H.allKeys), hero_autocast, hero_buy_price, hero_buy_ready          ALLIED
--   hero_hpmult (effective HP = engine HP x this), hero_dmgmult (the ONE weapon damage multiplier),
--   hero_armor (fraction), hero_regen (share of max HP/s), hero_regen_hps (effective HP/s), hero_dps,
--   hero_range (longest weapon), hero_speed (elmos/s), hero_power (ability power multiplier), hero_splash and
--   hero_pierce (fractions), hero_scale (model scale, 1 = normal)                                        INLOS
--   hero_ready_<key> (frame the ability is ready), hero_cd_<key> (cooldown length, frames)               ALLIED
--   hero_on_<key> (frame an active effect ends), hero_dur_<key> (its length, frames), hero_toggle_<key>
--   (1 while a toggle ability is on)                                                                      INLOS
--   hero_retreat (AI), hero_absorb / hero_absorb_max (absorb pool), hero_cloaked                         ALLIED
--   hero_revive_level (on a revive nanoframe, INLOS), hero_summon_expire (on a summoned unit, ALLIED)
-- Unit rules params of an altar: hero_next (AI teams only: the hero the skirmish AI should build next, "" = none).
-- Team rules params (ALLIED): hero_dead_<name> (the level a revive brings back), hero_revive_<name> (revive metal),
--   hero_built_<name>, hero_ai_bank, hero_ai_ebank (AI savings), hero_slots (1..H.MAX_HEROES), hero_slots_used,
--   hero_slots_research (estimated frame the running altar upgrade ends, 0 = none), hero_slots_research_level (1..4),
--   hero_slots_research_progress (0..1), hero_slots_research_bp (build power on it), hero_slots_research_stall (1 =
--   short of metal / energy).
-- Game rules param hero_ability_log = 1: "[ability]" infolog lines (benches).
-- Events to LuaUI (Script.LuaUI.T4HeroEvent(kind, unitID, a, b)): learn (rank), levelup (level), nometal (price),
--   bought (level, price), born / revived (level), died (level, revive level), cast (rank, index in H.abilityKeys),
--   undying (rank), research (altarID, upgrade level, end frame), slots (altarID or -1, slots), slotsfull (altarID).
--
-- Damage (one multiplier): the engine damage of a hero weapon is its base (unitdef, T4.heroBalance). UnitPreDamaged
-- multiplies a hero's own weapon hit ONCE by h.dmgMult = (1 + H.LEVEL_DAMAGE * (level - 1)) * (1 + damage mods), times
-- the item damage-type bonus, kit crit / slayer, then the module `hit` hook and the items `hit` hook. Ability damage
-- (api.damage / kit) is never multiplied there. Heroes take damage / hpMult * (1 - armor). The engine experience of
-- heroes is held at 0 (its reloadScale / healthScale would stack on the hero levels).
--
-- Generic ability kit (kind = ..., values per rank: number | 10-array | H.lin(a, b)):
--   passives   aura_heal {radius, rate HP/s}   aura_damage {radius, mult}   aura_armor {radius, reduce}
--              aura_burn {radius, dps}   aura_emp {radius, dmg, emp, period}   aura_slow {radius, slow}
--              stats {hp, armor, regen HP/s, speed, sight, radar (absolute) | ranks = {{...} x 10}}   crit {chance, mult}
--              slayer {minCost, mult}   lifesteal {frac}   thorns {frac}   proc_chain {chance, dmg, jumps, radius, weapon?}
--              proc_blast {chance, dmg, radius, fx?}   undying {cooldown, heal, nova, novaRadius?, novaStun?}
--              shield_cap {cap, base, regen}
--   actives    active_buff {duration, buff = {speed, armor, regen HP/s, damage, reload, range, turn, immobile, cloak,
--                           hidden, unstoppable, reflect, scale, shieldRegen}, trailDmg?}  (toggle = true: on / off)
--              active_guard {radius, reduce, duration}   active_dome {radius, duration}
--              active_nova {radius, dmg, stun, emp, heal, shieldRatio?}
--              active_barrage {range, radius, count, duration, dmg, aoe?, stun?, emp?, projectile = meteor|star|shell|
--                              missile|nuke|bolt, weapon?, from = sky|hero?, nova, novaRadius?, novaStun?, novaFx?}
--              active_beam {range, radius, tick (per 0.2 s), duration, drift?, nova}
--              active_spear {range, pct, flat, line, nova, weapon?}   active_dash {range, dmg, radius, stun?, burn?}
--              active_bladestorm {radius, dmg (per 0.2 s), duration, armor}   active_summon {unit, count, duration}
--              active_missiles {radius, count, dmg, aoe?, weapon?}   active_repair {radius, heal}
--              active_cloak {duration, speed}   active_shield {duration, absorb}
--   kind = "custom": the hero module does it (cast / autocast / hooks).
-- Ability def fields the core reads: passive, cmd, action, target ("unit" | "map" | "ally" | "unit_or_map" | nil =
--   self), range, cooldown, toggle (a second cast ends it, the cooldown starts at the end), cursor, name, desc.
--
-- Hero module API (luarules/heroes/<heroname>.lua, VFS.Include'd; returns a table of optional synced hooks; every
-- hook gets `api`, unitID, h; h.level, h.def (h.def.cfg = the config), h.team, h.ally, h.ai (an AI team's hero),
-- h.mods, h.dmgMult, h.power, h.store = private):
--   init(api, unitID, h)                         hero finished / revived
--   rank(api, unitID, h, key, rank)              a rank was learned (also stats)
--   frame(api, unitID, h, f)                     every 3 frames while alive
--   cast(api, unitID, h, key, rank, x, y, z, targetID) -> true = it happened (cooldown starts; toggle: turned on)
--   K.toggleOff(api, unitID, h, key, rank)         a toggle ability ends (second cast / api.toggleOff); cooldown starts
--   autocast(api, unitID, h, key, rank) -> x, y, z, targetID | nil   (AI and autocast; any non-nil x = cast)
--   hit(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer) -> damage   own weapon hits, after
--                                                the core multiplier (UnitPreDamaged); damage in engine HP
--   damaged(api, unitID, h, damage, attackerID, weaponDefID, isParalyzer, ax, az) -> damage   the hero is hit;
--                                                damage in engine HP (x h.hpMult = effective HP), after armor
--                                                and absorb; ax, az = attacker position (nil if none)
--   dying(api, unitID, h) -> true                keep it alive (UnitPreDamaged, lethal damage): the module heals it
--                                                or calls api.downed
--   destroyed(api, unitID, h)
--   projectile(api, unitID, h, proID, weaponDefID, originalWeaponDefID)   one of its projectiles was created
--                                                (after a swap: the copy's weaponDefID, the swapped-out one last)
--   summonHit(api, unitID, h, summonID, victimID, victimDefID, damage, weaponDefID) -> damage   a summon of the hero hit
--   impact(api, unitID, h, weaponDefID, x, y, z, projectileID)   one of its weapons / extra weapondefs exploded
--   fired(api, unitID, h, weaponNum)             a weapon fired (once per shot / salvo; reload start)
--   victimDestroyed(api, unitID, h, victimID, victimDefID)   it killed a unit
--   unitDied(api, unitID, h, deadID, deadDefID, x, z, allyOfHero)   any unit died within 1500 of it
--   mods(api, unitID, h, m)                      add to the stat mods (same keys as the items' mods, below)
-- api (synced; "per rank" = api.val(def.field, rank)):
--   H, val(v, r), rank(h, key), level(h), power(h), dmgMult(h), frame(), hero(uid) -> h, isHero(uid), pos(uid),
--   cost(uid), damageType(weaponDefID), log(fmt, ...), ceg(name, x, y, z), fx (= GG.HeroFX, nil until it exists),
--   toUI(kind, uid, a, b), delay(frames, fn)
--   damage(victimID, dmg, attackerID, opts) -> bool   opts {dtype, para = seconds (the damage is paralysis),
--       noHero, ally}; never hits allies; item damage-type bonus applied; ability power NOT applied (use api.power)
--   area(x, z, r, dmg, attackerID, opts) -> hit list (opts + stun = seconds)
--   line(x1, z1, x2, z2, width, dmg, attackerID, opts) -> hit list
--   stun(uid, seconds, attackerID)               heroes 50% of the time; unstoppable heroes immune
--   heal(uid, hp) -> healed (effective HP for heroes)
--   enemiesIn(x, z, r, ally), alliesIn(x, z, r, ally), nearestEnemies(x, z, r, ally, n) -> sorted by distance
--   buff(unitID, h, id, seconds | nil, mods), unbuff(unitID, h, id)   mods: damage, reload, speed, turn, range, armor,
--       (reload may be { [weaponKey | weaponNum] = frac } for single weapons), regen (HP/s), immobile, cloak (engine cloak when the unitdef can cloak), hidden, unstoppable, reflect (half vs heroes), scale,
--       turretTurn (calls the COB function SetTurretTurnMult(x1000) when the script has it - no stock script does)
--   setScale(unitID, s)                          model scale: unit rules param hero_scale + GG.HeroFX.scale(unitID, s)
--                                                (Recoil cannot scale a COB unit's model at runtime; the fx draws it)
--   fire(h, weaponName, fromX, fromY, fromZ, targetID | x, y, z, opts) -> projectileID   an extra weapondef
--       <hero>_<weaponName> (or a real weapon key); opts {dmg, aoe, stun, para, dtype, fx, onHit(x, z, hits), ttl,
--       gravity}: with dmg the projectile's own damage is replaced by the ability's (applied on impact); without it
--       the engine damage counts as a hero weapon hit. Beams / lightning hit at once. Never a starburst.
--   swapWeapons(unitID, h, suffix | nil)         projectiles drawn with the <key>_<suffix> copies (config weaponCopies)
--   summon(unitID, h, unitName, count, opts) -> ids   opts {expire, leash, guard = heroID (attack the hero's target,
--       stay in leash), spread, cap, respawn = {max, every} (+ group = id: a later call with the same id resizes it;
--       api.summonGroupSize(heroID, id, n)), build = seconds (still and stunned under a print effect), credit (default true: damage
--       counts as the hero's: XP, damage type), scaleWithLevel (HP / damage x ability power), persist (outlive the hero)}
--   order(uids, cmd, params, opts)
--   cooldown(unitID, h, key, seconds), ready(h, key), active(unitID, key, seconds), K.toggleOff(unitID, h, key)
--   absorb(unitID, h, amount, seconds)           an absorb pool (effective HP)
--   dash(unitID, h, x, z, opts) opts {seconds | speed (elmos/s), arc = height, untargetable, onStep(x, z), onLand(x, z)}
--   blink(unitID, x, z) -> ok   push(victimID, fromX, fromZ, dist, seconds)   pull(victimID, toX, toZ, dist, seconds)
--   throw(victimID, x, z, seconds, onLand)       enemies; heroes half the distance; buildings / aircraft immune
--   orbitAround(unitID, h, targetID, radius, seconds)   turretSpin(unitID, seconds, degPerSec, onStep(angle, x, z))
--       (emulated: the whole unit turns in place, MoveCtrl; the module deals the beam damage in onStep)
--   downed(unitID, h, seconds, onRise)           invulnerable, untargetable, still, weapons off, slumped
--   mark(uid, id, seconds, opts) / marks(uid, id) -> stacks   opts {stacks = 1, max, vuln (damage taken + per stack,
--       every attacker), from = heroID, slow, root, reveal, noDash (no dash / leap / blink / push for it)}
--   slow(uid, frac, seconds) (heroes half)   unitBuff(uid, id, seconds, {speed, damage, armor, regen, cloak})
--   taunt(victimID, byUnitID, seconds) (heroes half)   forceTarget(unitID, targetID, seconds)
--   target(unitID) -> targetID | nil, x, y, z   reloadNow(unitID, weaponNum | key)   piecePos(unitID, pieceName)
--   weaponNum(h, key), disableWeapon(unitID, h, key, off)
--   consume(uid, opts) -> info   destroy a unit without wreck / explosion; opts.credit = heroID gives the kill (XP);
--       commanders, altars and heroes are refused
--   reveal(x, z, r, seconds, ally)  (ground LOS through an invisible legt4skyeye sensor unit + units decloaked)   intercept(x, z, r, ally, maxCount) -> n   shieldDrain(uid) -> drained
--   cast(unitID, h, kitAbility, rank, tx, tz, targetID)   any generic kit ability, no cooldown
--   also: seenBy(uid, ally), caster(unitID, h, key), blast(caster, x, z, r, dmg, stun, emp, dtype),
--   bestCluster(x, z, range, radius, ally) -> metal, x, z, mostValuableEnemy(x, z, range, ally) -> uid, metal,
--   enemyCostNear(x, z, r, ally), weaponReach(h), endBuffs(unitID, h, flag), losCloak(uid, on)
-- Items (GG.T4HeroItems, the items gadget; every hook optional, api appended LAST; item power damage through
--   GG.T4Heroes.damage(target, dmg, attackerID, {dtype, item = true}) or while GG.T4HeroItems.isItemDamage() is true
--   gets no hero multiplier and no on-hit effects; after an equipment change it calls GG.T4Heroes.refresh(uid)):
--   mods(unitID, h, m),
--   hit(unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer, api) -> damage,
--   damaged(unitID, h, damage, attackerID, weaponDefID, isParalyzer, api) -> damage (engine HP),
--   dying(unitID, h, api) -> true, frame(unitID, h, f, api) every 3 frames, onHeroDeath(unitID, h, x, z),
--   onKill(heroID, victimID, victimDefID). GG.T4Heroes.give / equip / drop forward to it.
-- Stat mods (h.mods; vit/mob/dmg/rng/imp ranks, kit `stats`, module and item mods add up): hp (HP), regen (HP/s),
--   armor (fraction), speed (elmos/s), sight, radar (elmos), damage, range, splash (blast AREA share: radius x
--   sqrt(1 + splash)), pierce (share of a shot's damage spread over the enemies on a line behind its target, once
--   per projectile, fading along the line). No fire rate / salvo / pellets in stats or items (only buffs: reload).
--   power (ability power), cdr, crit (chance), critMult, lifesteal, thorns, xp, income (metal/s), dtype = {<type> = frac}.

local H = VFS.Include("luarules/configs/t4_heroes.lua")

local CMD_HERO_AUTOCAST = 36100
local CMD_ALTAR_UPGRADE = 36400

if gadgetHandler:IsSyncedCode() then
	----------------------------------------------------------------------------- synced

	local spGetUnitPosition = Spring.GetUnitPosition
	local spGetUnitsInCylinder = Spring.GetUnitsInCylinder
	local spGetUnitAllyTeam = Spring.GetUnitAllyTeam
	local spGetUnitHealth = Spring.GetUnitHealth
	local spGetUnitDefID = Spring.GetUnitDefID
	local spSetUnitRulesParam = Spring.SetUnitRulesParam
	local spValidUnitID = Spring.ValidUnitID
	local spGetGroundHeight = Spring.GetGroundHeight
	local MoveCtrl = Spring.MoveCtrl
	local random = math.random
	local max, min, floor, sqrt, abs = math.max, math.min, math.floor, math.sqrt, math.abs

	local ALLIED = { allied = true }
	local INLOS = { inlos = true }
	local GAME_SPEED = Game.gameSpeed
	local gravityPerFrame = -Game.gravity / (GAME_SPEED * GAME_SPEED)
	local val = H.val

	local xpMult = tonumber(Spring.GetModOptions().hero_xp_mult) or 1
	-- v22: one damage coefficient over every hero (weapons, abilities, items, summons; modoption hero_damage_mult)
	local heroDamageMult = tonumber(Spring.GetModOptions().hero_damage_mult) or H.DAMAGE_MULT
	if xpMult <= 0 then
		xpMult = 1
	end

	---------------------------------------------------------------- static data per hero unitdef

	local heroDefs = {}   -- unitDefID -> def
	local heroWeapon = {} -- weaponDefID -> true: the hero_* weapondefs and copies the gadget spawns
	local copyBase = {}   -- weaponDefID of a weapon copy (<key>_<suffix>) -> weaponDefID of the weapon it copies
	local wdType = {}     -- weaponDefID -> damage type (H.damageType)
	local explWatch = {}  -- weaponDefID -> true (Explosion)
	local projWatch = {}  -- weaponDefID -> true (ProjectileCreated)
	local foundryDefs = {} -- unitDefID -> true (the altars: fountain, AI retreat point, hero cap)
	local factoryDefs = {}
	local unitCost = {}
	local structureDefs = {}
	local airDefs = {}
	local commanderDefs = {}
	local isStarburst = {}
	local noCopy = {}
	local isBeam = {}
	for wdid, wd in pairs(WeaponDefs) do
		wdType[wdid] = H.damageType(wd)
		if wd.customParams and wd.customParams.t4_hero_weapon then
			heroWeapon[wdid] = true
		end
		if wd.type == "StarburstLauncher" then
			isStarburst[wdid] = true
		end
		-- never respawned as a copy: starbursts (v15.1 savegame crash) and unguided rockets with a trajectory height
		-- (a spawned one loses its target and misses - v19 dmgfix)
		if wd.type == "StarburstLauncher" or (wd.type == "MissileLauncher" and (wd.trajectoryHeight or 0) > 0) then
			noCopy[wdid] = true
		end
		if wd.type == "BeamLaser" or wd.type == "LightningCannon" then
			isBeam[wdid] = wd.beamTTL or 3
		end
	end

	for udid, ud in pairs(UnitDefs) do
		unitCost[udid] = ud.metalCost
		if ud.isImmobile or (ud.speed or 0) == 0 then
			structureDefs[udid] = true
		end
		if ud.canFly then
			airDefs[udid] = true
		end
		if ud.customParams and ud.customParams.iscommander then
			commanderDefs[udid] = true
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
				health = ud.health, speed = ud.speed, turnRate = ud.turnRate or 0, sight = ud.losRadius or ud.sightDistance or 0,
				airSight = ud.airLosRadius or 0, radar = ud.radarDistance or ud.radarRadius or 0, height = ud.height or 60,
				canCloak = ud.canCloak, fx = cfg.fx or 2,
				-- v20: a hero's whole damage scale (weapons and abilities; T4.heroBalance `dmgScale`, the artillery heroes)
				-- x the coefficient of all heroes (v22)
				dmgScale = (tonumber(ud.customParams.t4_dmg_scale) or 1) * heroDamageMult,
				weapons = {}, keyNum = {}, numOf = {}, extra = {}, copies = {}, cmds = {},
				altWeapon = {}, -- keys of the second arc of a gun (not counted in the DPS)
			}
			for key in (ud.customParams.t4_alt_weapons or ""):gmatch("%S+") do
				def.altWeapon[key] = true
			end
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
						burst = wd.salvoSize, projectiles = wd.projectiles,
						aoe = wd.damageAreaOfEffect or 0, damage = wd.damages and wd.damages[0] or 0,
						-- aim fix: ballistic reach and missile flight time follow the range
						velocity = wd.projectilespeed or 0, gravity = (wd.myGravity or 0) > 0 and wd.myGravity or -gravityPerFrame,
						flight = wd.flightTime or 0, paralyzer = wd.paralyzer, dtype = wdType[w.weaponDef],
					}
					def.keyNum[key] = def.keyNum[key] or {}
					def.keyNum[key][#def.keyNum[key] + 1] = n
					def.numOf[w.weaponDef] = n
				end
			end
			for wdid, wd in pairs(WeaponDefs) do
				if wd.name:sub(1, #prefix) == prefix and wd.customParams and wd.customParams.t4_hero_weapon then
					local key = wd.name:sub(#prefix + 1)
					def.extra[key] = wdid
					local of, suffix = wd.customParams.t4_copy_of, wd.customParams.t4_copy
					if of and suffix then
						for _, n in ipairs(def.keyNum[of] or {}) do
							local base = def.weapons[n].wdid
							copyBase[wdid] = base
							def.copies[suffix] = def.copies[suffix] or {}
							def.copies[suffix][base] = wdid
						end
					end
				end
			end
			def.keys = H.allKeys(ud.name)
			for _, key in ipairs(H.abilityKeys) do
				local b = cfg[key]
				if b and b.cmd then
					def.cmds[b.cmd] = key
				end
			end
			-- the behaviour module (luarules/heroes/<name>.lua)
			local path = H.modulePath(ud.name)
			if path and VFS.FileExists(path) then
				-- the module runs in its own environment over the gadget's (GG, Spring, UnitDefs ... visible; its globals stay its own)
				local env = setmetatable({}, { __index = getfenv(1) })
				local ok, mod = pcall(VFS.Include, path, env, VFS.ZIP_FIRST)
				if ok and type(mod) == "table" then
					def.mod = mod
				else
					Spring.Echo("[t4heroes] module " .. path .. " failed: " .. tostring(mod))
				end
			end
			heroDefs[udid] = def
		end
	end

	for _, def in pairs(heroDefs) do
		local mod = def.mod or {}
		-- extras (hero_* and the copies): their explosions apply ability damage / impact hooks
		for _, wdid in pairs(def.extra) do
			explWatch[wdid] = true
		end
		for n, w in pairs(def.weapons) do
			if w.flight > 0 or mod.projectile then
				projWatch[w.wdid] = true
			end
			if mod.impact then
				explWatch[w.wdid] = true
			end
		end
		for _, map in pairs(def.copies) do
			for base in pairs(map) do
				projWatch[base] = true
			end
		end
	end

	---------------------------------------------------------------- state

	local heroes = {}      -- unitID -> hero state
	local dead = {}        -- teamID -> name -> { level, picks }
	local pendingRevive = {} -- unitID (nanoframe) -> record
	local building = {}    -- unitID (hero nanoframe) -> { team, name }
	local altars = {}      -- unitID (finished altar) -> teamID
	local teamSlots = {}   -- teamID -> hero slots (1..H.MAX_HEROES)
	local research = {}    -- teamID -> { level, finish, altar }
	local isAITeam = {}
	local guardMult = {}   -- unitID -> damage taken multiplier (active_guard)
	local invuln = {}      -- unitID -> true (active_dome)
	local auraDamage = {}  -- unitID -> extra damage (aura_damage)
	local auraArmor = {}   -- unitID -> share of damage taken removed (aura_armor)
	local events = {}      -- timed ability effects, processed every 6 frames
	local delayed = {}     -- { frame, fn }
	local summoned = {}    -- unitID -> { owner, expire, leash, guard, credit, scale, name, group }
	local consumed = {}    -- unitID -> { credit = heroID | nil } (api.consume)
	local marks = {}       -- unitID -> id -> { stacks, expire, vuln, from, slow, root, reveal, max }
	local ctl = {} -- control state (api: slows, unit buffs, taunts, forced targets, reveals)
	ctl.eyes = {}      -- unitID of a sensor unit (api.reveal) -> frame it goes
	ctl.timedSlow = {}   -- unitID -> { frac, expire }
	ctl.unitBuffs = {}   -- unitID (non-hero) -> id -> { expire, mods }
	local ub = { damage = {}, armor = {}, speed = {}, regen = {}, cloak = {} } -- merged unit buffs per unitID
	local auraSlow = {}    -- unitID -> slow (aura_slow, refreshed every second)
	ctl.speedApplied = {} -- unitID -> speed factor applied (1 = none)
	local movers = {}      -- unitID -> ctl.forced movement (MoveCtrl): dash, push, pull, throw, orbit, spin, downed
	ctl.taunts = {}      -- unitID -> { by, expire }
	ctl.forced = {}      -- heroID -> { target, expire }
	ctl.revealed = {}    -- unitID -> allyTeam -> frame
	ctl.reveals = {}     -- { x, z, r, expire, ally }
	local scaled = {}      -- unitID -> model scale
	local inAbility = false -- true while the gadget deals ability damage (the damage callins see it)
	local inStun = false   -- true while the gadget stuns (the damage callins pass it untouched)

	for _, teamID in ipairs(Spring.GetTeamList()) do
		local _, _, _, isAI = Spring.GetTeamInfo(teamID, false)
		local luaAI = Spring.GetTeamLuaAI(teamID)
		isAITeam[teamID] = isAI and (luaAI == nil or luaAI == "") or false
		teamSlots[teamID] = 1
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
		return Spring.GetGameFrame()
	end

	local function alive(uid)
		return uid and spValidUnitID(uid) and not Spring.GetUnitIsDead(uid)
	end

	local function isEnemyOf(uid, ally)
		local a = spGetUnitAllyTeam(uid)
		return a and a ~= ally
	end

	local function enemiesIn(x, z, r, ally)
		local out = {}
		for _, uid in ipairs(spGetUnitsInCylinder(x, z, r)) do
			if isEnemyOf(uid, ally) and not Spring.GetUnitIsDead(uid) then
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

	-- Lua SpawnCEG takes the bare CEG name; weapondefs use the "custom:" prefix
	local function ceg(name, x, y, z)
		if x and name then
			Spring.SpawnCEG(name:gsub("^custom:", ""), x, y, z, 0, 1, 0, 0, 0)
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

	local function clampX(x)
		return max(32, min(Game.mapSizeX - 32, x))
	end
	local function clampZ(z)
		return max(32, min(Game.mapSizeZ - 32, z))
	end

	-- "[ability] ..." lines in the infolog while the game rules param hero_ability_log is 1 (bench scenes)
	local function alog(fmt, ...)
		if Spring.GetGameRulesParam("hero_ability_log") == 1 then
			Spring.Echo("[ability] " .. string.format(fmt, ...))
		end
	end

	local function seenBy(uid, ally)
		local los = Spring.GetUnitLosState(uid, ally, true)
		return los and los ~= 0
	end

	---------------------------------------------------------------- hooks: modules and items

	local hookErrors = {}
	-- FX owner context (fx_t4_heroes.lua: effects made inside are "team" visible for the owner's allies)
	local function fxOwner(o)
		local F = GG.HeroFX
		if F and F.owner then
			return F.owner(o)
		end
	end
	-- the current owner context (to restore it later in a callback)
	local function fxContext()
		local cur = fxOwner(nil)
		fxOwner(cur)
		return cur
	end

	-- call hook `name` of a hero module (pcall: a broken content module must not take the gadget down)
	local function modHook(h, name, ...)
		local mod = h.def.mod
		local fn = mod and mod[name]
		if not fn then
			return nil
		end
		local prev = fxOwner(h.unitID)
		local ok, a, b, c, d = pcall(fn, ...)
		fxOwner(prev)
		if not ok then
			local k = h.def.name .. "." .. name
			hookErrors[k] = (hookErrors[k] or 0) + 1
			if hookErrors[k] <= 5 then
				Spring.Echo("[t4heroes] module " .. k .. " error: " .. tostring(a))
			end
			return nil
		end
		return a, b, c, d
	end

	local function items()
		return GG.T4HeroItems
	end

	-- an item power deals its own (already scaled) damage: no hero multipliers, no on-hit effects for it
	local function itemDamage()
		local I = GG.T4HeroItems
		return I and I.isItemDamage and I.isItemDamage() or false
	end

	local function itemHook(name, ...)
		local I = GG.T4HeroItems
		local fn = I and I[name]
		if not fn then
			return nil
		end
		local ok, a = pcall(fn, ...)
		if not ok then
			hookErrors["items." .. name] = (hookErrors["items." .. name] or 0) + 1
			if hookErrors["items." .. name] <= 5 then
				Spring.Echo("[t4heroes] items." .. name .. " error: " .. tostring(a))
			end
			return nil
		end
		return a
	end

	local api = {} -- filled in below (API section); hooks get it

	---------------------------------------------------------------- damage primitives
	local abilityAttackMult, abilityVictim, abilityOnHit -- the kit, below

	-- the hero (or the hero a credited summon belongs to) behind an attacker
	local function heroOf(uid)
		if not uid then
			return nil
		end
		local h = heroes[uid]
		if h then
			return h, uid
		end
		local s = summoned[uid]
		if s and s.credit and heroes[s.owner] then
			return heroes[s.owner], s.owner
		end
	end

	local function dtypeBonus(h, dtype)
		local d = h and dtype and h.mods and h.mods.dtype
		return d and d[dtype] or 0
	end

	-- the engine reads AddUnitDamage's paralyze time as an integer: a fraction below 1 s turned the paralysis into plain
	-- damage (a stun of 3x max HP killed outright - a hero stunned for < 2 s, since heroes take half the time)
	local function paraSeconds(t)
		if not t or t <= 0 then
			return 0
		end
		return max(1, floor(t + 0.5))
	end

	-- ability damage to one unit: no hero multipliers, never to allies of `ally` (UnitPreDamaged drops it too)
	local function abilityHurt(uid, dmg, ownerID, paraTime, ally)
		if not dmg or dmg <= 0 or not alive(uid) then
			return false
		end
		if ally and spGetUnitAllyTeam(uid) == ally then
			return false
		end
		if not paraTime or paraTime <= 0 then
			-- v20: the attacker hero's damage scale (artillery heroes); item powers keep their own numbers, only the
			-- coefficient of all heroes (v22)
			local h = heroOf(ownerID)
			if h then
				dmg = dmg * (itemDamage() and heroDamageMult or h.def.dmgScale)
			end
		end
		local prev = inAbility
		inAbility = true
		Spring.AddUnitDamage(uid, dmg, paraSeconds(paraTime), (ownerID and spValidUnitID(ownerID)) and ownerID or nil)
		inAbility = prev
		return true
	end

	-- api.damage: + the attacker hero's item bonus for the damage type
	local function abilityDamage(uid, dmg, ownerID, opts)
		if not dmg or dmg <= 0 or not alive(uid) then
			return false
		end
		local ally = opts and opts.ally or (ownerID and spValidUnitID(ownerID) and spGetUnitAllyTeam(ownerID)) or nil
		if opts then
			if opts.noHero and heroes[uid] then
				return false
			end
			if opts.dtype and not opts.item then
				dmg = dmg * (1 + dtypeBonus(heroOf(ownerID), opts.dtype))
			end
		end
		return abilityHurt(uid, dmg, ownerID, opts and opts.para, ally)
	end

	local function unstoppable(uid)
		local h = heroes[uid]
		local bf = h and h.buff and h.buff.fx
		return bf and bf.unstoppable or false
	end

	-- paralysis for `seconds` (heroes half as long, unstoppable heroes not at all)
	local function stunUnit(uid, seconds, ownerID, ally)
		if not seconds or seconds <= 0 or not alive(uid) then
			return false
		end
		if ally and spGetUnitAllyTeam(uid) == ally then
			return false
		end
		if heroes[uid] then
			if unstoppable(uid) then
				return false
			end
			seconds = seconds * 0.5
		end
		local _, maxHp = spGetUnitHealth(uid)
		if not maxHp then
			return false
		end
		local prev = inStun
		inStun = true
		Spring.AddUnitDamage(uid, maxHp * 3, paraSeconds(seconds), (ownerID and spValidUnitID(ownerID)) and ownerID or nil)
		inStun = prev
		return true
	end

	-- healing in effective HP (a hero's health is divided by its toughness, see applyStats)
	local function healUnit(uid, amount)
		local hp, maxHp, _, _, bp = spGetUnitHealth(uid)
		if not hp or not bp or bp < 1 or hp >= maxHp or not amount or amount <= 0 then
			return 0
		end
		local v = heroes[uid]
		local add = min(maxHp - hp, amount / (v and v.hpMult or 1))
		Spring.SetUnitHealth(uid, hp + add)
		return add
	end

	---------------------------------------------------------------- stats
	local NEVER = 1e9
	local setCloak, setHidden -- below (buffs)
	local applyStats, applyHeroSpeed, setScale, applyScale, speedFactor
	do

		local spSetUnitWeaponDamages = Spring.SetUnitWeaponDamages
		local REACH_MARGIN = 1.15 -- a ballistic weapon's flat reach v^2/g is kept this much above its range

		-- what the hero's ranks, kit `stats` passives, module and items add: absolute units (hp, regen HP/s, speed,
		-- sight, radar) and fractions (the rest), see the header
		local function newMods()
			return { damage = 0, hp = 0, armor = 0, regen = 0, speed = 0, range = 0, sight = 0, radar = 0, splash = 0,
				pierce = 0, power = 0, cdr = 0, crit = 0, critMult = 0, lifesteal = 0, thorns = 0, xp = 0,
				income = 0, dtype = {} }
		end

		local STAT_FIELDS = { "hp", "armor", "regen", "speed", "sight", "radar" }

		local function sumMods(unitID, h)
			local d = h.def
			local m = newMods()
			local base = d
			-- the five stats: shares of the base stats
			for _, key in ipairs(H.statKeys) do
				local r = rankOf(h, key)
				local s = H.stats[key]
				if r > 0 then
					m.hp = m.hp + (s.hp or 0) * base.health * r
					m.regen = m.regen + (s.regen or 0) * base.health * r
					m.speed = m.speed + (s.speed or 0) * base.speed * r
					m.sight = m.sight + (s.sight or 0) * base.sight * r
					m.damage = m.damage + (s.damage or 0) * r
					m.range = m.range + (s.range or 0) * r
					m.splash = m.splash + (s.splash or 0) * r
					m.pierce = m.pierce + (s.pierce or 0) * r
				end
			end
			-- kit passives that are stats
			for _, key in ipairs(H.abilityKeys) do
				local b = d.cfg[key]
				local r = rankOf(h, key)
				if b and r > 0 then
					if b.kind == "stats" then
						local src = b.ranks and b.ranks[r] or b
						for _, k in ipairs(STAT_FIELDS) do
							local v = val(src[k], r)
							if type(v) == "number" then
								m[k] = m[k] + v
							end
						end
					elseif b.kind == "lifesteal" then
						m.lifesteal = m.lifesteal + val(b.frac, r)
					elseif b.kind == "thorns" then
						m.thorns = m.thorns + val(b.frac, r)
					end
				end
			end
			modHook(h, "mods", api, unitID, h, m)
			itemHook("mods", unitID, h, m)
			return m
		end

		-- model scale (Rage Mode & co): Recoil has no runtime model scaling for COB units (SetUnitPieceMatrix only accepts
		-- rotation/translation and blocks script animation), so the scale is published as the unit rules param
		-- hero_scale and handed to the fx library (GG.HeroFX.scale(unitID, s), unsynced redraw) when it has one
		function applyScale(unitID, s)
			local F = GG.HeroFX
			if F and F.scale then
				pcall(F.scale, unitID, s)
			end
		end

		function setScale(unitID, s)
			s = s or 1
			if abs(s - (scaled[unitID] or 1)) < 0.005 then
				return
			end
			scaled[unitID] = abs(s - 1) > 0.005 and s or nil
			applyScale(unitID, s)
			spSetUnitRulesParam(unitID, "hero_scale", s, INLOS)
		end

		-- weapons that must not fire (hidden, downed, api.disableWeapon)
		local function weaponOff(h, w)
			return (h.weaponsOff and next(h.weaponsOff)) or (h.disabled and h.disabled[w.key])
		end

		-- every weapon: range, aoe, reload (rate), aim fix for long ranges; the DPS and range params
		local function applyWeapons(unitID, h, m, bf)
			local def = h.def
			local rate = max(0.2, 1 + (bf.reload or 0)) -- fire rate: buffs only (v19 dmgfix: no rate in stats or items)
			local rangeMult = max(0.2, 1 + m.range + (bf.range or 0))
			-- Impact / item splash grow the blast AREA by their share (v19 dmgfix): radius x sqrt(1 + splash)
			local splash = sqrt(max(0.2, 1 + m.splash))
			local maxRange = 0
			local dps = 0
			local f = frameNow()
			h.ttlMult = {}
			for n, w in pairs(def.weapons) do
				if weaponOff(h, w) then
					Spring.SetUnitWeaponState(unitID, n, { reloadTime = 9999, reloadState = f + NEVER })
					h.offState = h.offState or {}
					h.offState[n] = true
				else
					local rw = bf.reloadW
					local reload = w.reload / (rw and max(0.2, rate + (rw[w.key] or rw[n] or 0)) or rate)
					if h.offState and h.offState[n] then
						h.offState[n] = nil
						Spring.SetUnitWeaponState(unitID, n, "reloadState", f + floor(reload * GAME_SPEED))
					end
					Spring.SetUnitWeaponState(unitID, n, "reloadTime", reload)
					local r = w.range * rangeMult
					-- a ballistic shell of speed v reaches v^2/g on flat ground: past that the engine cannot aim at all -
					-- the shell gets faster with the range (set before the range: the engine derives its range factor from both)
					if w.type == "Cannon" and w.velocity > 0 and w.gravity > 0 then
						local v = max(w.velocity, sqrt(r * REACH_MARGIN * w.gravity))
						Spring.SetUnitWeaponState(unitID, n, "projectileSpeed", v)
					end
					Spring.SetUnitWeaponState(unitID, n, "range", r)
					if r > maxRange and w.damage > 0 then
						maxRange = r
					end
					local aoe = w.aoe * splash
					if abs(aoe - w.aoe) > 0.5 and spSetUnitWeaponDamages then
						spSetUnitWeaponDamages(unitID, n, "damageAreaOfEffect", aoe)
					end
					if w.flight > 0 and r > w.range * 1.01 then
						h.ttlMult[w.wdid] = r / w.range
					end
					-- the shown DPS counts what T4.weaponDps balances: no paralyzers, not the other arc of a gun
					if w.damage > 0 and not def.altWeapon[w.key] and not w.paralyzer and w.range >= 150 then
						dps = dps + w.damage * h.dmgMult * def.dmgScale * (w.projectiles or 1) * (w.burst or 1) / max(0.03, reload)
					end
				end
			end
			if maxRange > 0 then
				Spring.SetUnitMaxRange(unitID, maxRange)
			end
			spSetUnitRulesParam(unitID, "hero_dps", floor(dps), INLOS)
			spSetUnitRulesParam(unitID, "hero_range", floor(maxRange), INLOS)
		end

		-- speed of a hero: its own (stats, buffs) x the slow / root / speed effects on it (speedFactor)
		speedFactor = {} -- unitID -> factor from slows, roots, unit buffs (1 = none)
		function applyHeroSpeed(unitID, h)
			if movers[unitID] then
				return -- MoveCtrl owns it; applied again when the movement ends
			end
			local spd = (h.moveSpeed or h.def.speed) * (speedFactor[unitID] or 1)
			pcall(MoveCtrl.SetGroundMoveTypeData, unitID, { maxSpeed = spd, maxWantedSpeed = spd, turnRate = h.turn or h.def.turnRate })
			spSetUnitRulesParam(unitID, "hero_speed", spd, INLOS)
		end


		function applyStats(unitID, h)
			local def = h.def
			local m = sumMods(unitID, h)
			local f = frameNow()
			local bf = h.buff and h.buff.expire > f and h.buff.fx or {}
			local L = h.level
			h.mods = m
			-- the ONE multiplier of the hero's own weapon hits (UnitPreDamaged)
			h.dmgMult = (1 + H.LEVEL_DAMAGE * (L - 1)) * (1 + m.damage + (bf.damage or 0))
			h.armor = min(0.75, m.armor)
			-- health growth is applied as damage taken / hpMult ("effective health"): the engine recomputes maxHealth
			-- from the unitdef whenever a unit gains engine experience, so a SetUnitMaxHealth would be lost
			local baseHp = max(1, def.health)
			h.hpMult = max(0.2, 1 + H.LEVEL_HP * (L - 1) + m.hp / baseHp)
			h.regen = m.regen / (baseHp * h.hpMult) -- share of the real max health per second
			h.power = (H.ABILITY_POWER_BASE or 1) * (1 + (H.ABILITY_POWER_PER_LEVEL or 0.01) * (L - 1)) * (1 + m.power)
			h.pierce = m.pierce
			spSetUnitRulesParam(unitID, "hero_hpmult", h.hpMult, INLOS)
			spSetUnitRulesParam(unitID, "hero_dmgmult", h.dmgMult, INLOS)
			spSetUnitRulesParam(unitID, "hero_armor", h.armor, INLOS)
			spSetUnitRulesParam(unitID, "hero_regen", h.regen, INLOS)
			spSetUnitRulesParam(unitID, "hero_regen_hps", floor(m.regen), INLOS)
			spSetUnitRulesParam(unitID, "hero_power", h.power, INLOS)
			spSetUnitRulesParam(unitID, "hero_splash", m.splash, INLOS)
			spSetUnitRulesParam(unitID, "hero_pierce", m.pierce, INLOS)

			applyWeapons(unitID, h, m, bf)

			-- movement: elmos per second like UnitDefs[].speed
			local speedMult = bf.immobile and 0.02 or max(0.2, 1 + (bf.speed or 0))
			h.moveSpeed = (def.speed + (bf.immobile and 0 or m.speed)) * speedMult
			h.turn = def.turnRate * max(0.2, 1 + (bf.turn or 0))
			applyHeroSpeed(unitID, h)

			-- sensors
			Spring.SetUnitSensorRadius(unitID, "los", def.sight + m.sight)
			Spring.SetUnitSensorRadius(unitID, "airLos", max(def.airSight, def.sight) + m.sight)
			if def.radar > 0 or m.radar > 0 then
				Spring.SetUnitSensorRadius(unitID, "radar", def.radar + m.radar)
			end

			-- buff states
			local s = bf.scale or 1
			if abs(s - (scaled[unitID] or 1)) > 0.005 then
				setScale(unitID, s)
			end
			if bf.turretTurn and Spring.GetCOBScriptID and Spring.GetCOBScriptID(unitID, "SetTurretTurnMult") then
				Spring.CallCOBScript(unitID, "SetTurretTurnMult", 0, floor((1 + bf.turretTurn) * 1000))
			end
		end

	end

	---------------------------------------------------------------- publish

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

	local function defByName(name)
		for _, d in pairs(heroDefs) do
			if d.name == name then
				return d
			end
		end
	end

	local function publishDead(teamID, name)
		local rec = dead[teamID] and dead[teamID][name]
		local def = defByName(name)
		if rec and def then
			Spring.SetTeamRulesParam(teamID, "hero_dead_" .. name, rec.level, ALLIED)
			Spring.SetTeamRulesParam(teamID, "hero_revive_" .. name, floor(def.cost * (1 + H.REVIVE_COST_PER_LEVEL * rec.level)), ALLIED)
		else
			Spring.SetTeamRulesParam(teamID, "hero_dead_" .. name, 0, ALLIED)
			Spring.SetTeamRulesParam(teamID, "hero_revive_" .. name, 0, ALLIED)
		end
	end

	---------------------------------------------------------------- hero cap and altar upgrades (SPEC section 3)
	local slotsUsed, canStartHero, queuedHeroes, publishSlots, refreshAltars, insertAltarCmd, startResearch, researchTick
	do

		-- names of the team's heroes that hold a slot: alive, dead (until revived), being built
		local function slotNames(teamID)
			local names = {}
			for _, h in pairs(heroes) do
				if h.team == teamID then
					names[h.def.name] = "alive"
				end
			end
			for name in pairs(dead[teamID] or {}) do
				names[name] = names[name] or "dead"
			end
			for _, b in pairs(building) do
				if b.team == teamID then
					names[b.name] = names[b.name] or "building"
				end
			end
			return names
		end

		function slotsUsed(teamID)
			local n = 0
			for _ in pairs(slotNames(teamID)) do
				n = n + 1
			end
			return n
		end

		-- may the team start hero `name` now: a revive always (once), a new hero only into a free slot;
		-- `queued` = heroes already waiting in the altar's queue (they take slots too). Returns ok, why.
		function canStartHero(teamID, name, queued)
			local names = slotNames(teamID)
			local st = names[name]
			if st == "alive" or st == "building" then
				return false, "exists"
			end
			if st == "dead" then
				return true, "revive"
			end
			local n = 0
			for _ in pairs(names) do
				n = n + 1
			end
			for qn in pairs(queued or {}) do
				if not names[qn] and qn ~= name then
					n = n + 1
				end
			end
			if n >= (teamSlots[teamID] or 1) then
				return false, "slots"
			end
			return true, "new"
		end

		-- heroes (names) in a factory's build queue
		function queuedHeroes(unitID)
			local out = {}
			local q = Spring.GetFactoryCommands(unitID, -1)
			if type(q) == "table" then
				for _, c in ipairs(q) do
					local id = c.id or c[1]
					if type(id) == "number" and id < 0 and heroDefs[-id] then
						out[heroDefs[-id].name] = true
					end
				end
			end
			return out
		end

		function publishSlots(teamID)
			Spring.SetTeamRulesParam(teamID, "hero_slots", teamSlots[teamID] or 1, ALLIED)
			Spring.SetTeamRulesParam(teamID, "hero_slots_used", slotsUsed(teamID), ALLIED)
			local r = research[teamID]
			Spring.SetTeamRulesParam(teamID, "hero_slots_research", r and r.finish or 0, ALLIED)
			Spring.SetTeamRulesParam(teamID, "hero_slots_research_level", r and r.level or 0, ALLIED)
			Spring.SetTeamRulesParam(teamID, "hero_slots_research_progress", r and r.progress or 0, ALLIED)
			Spring.SetTeamRulesParam(teamID, "hero_slots_research_bp", r and r.bp or 0, ALLIED)
			Spring.SetTeamRulesParam(teamID, "hero_slots_research_stall", r and r.stall or 0, ALLIED)
		end

		local altarTips = {} -- "<altar>:<cmd>" -> the original tooltip

		local function editDesc(unitID, cmdID, disabled, reason)
			local idx = Spring.FindUnitCmdDesc(unitID, cmdID)
			if not idx then
				return
			end
			local key = unitID .. ":" .. cmdID
			if not altarTips[key] then
				local d = Spring.GetUnitCmdDescs(unitID, idx, idx)
				altarTips[key] = d and d[1] and d[1].tooltip or ""
			end
			Spring.EditUnitCmdDesc(unitID, idx, { disabled = disabled, tooltip = reason and (altarTips[key] .. "\n\255\255\120\120" .. reason) or altarTips[key] })
		end

		-- the AI's next hero at an altar (unit rules param hero_next, read by the BARb factory script): a dead hero first
		-- (revive), else the heaviest aiPick that fits a free slot, "" when none (or the altar researches)
		-- v19-ai2 (AI agent): each AI team rolls its own hero order once (weighted random by aiPick, Efraimidis-Spirakis
		-- keys), so the AI rotates through all ten heroes of its faction across games instead of always the heaviest
		local aiRoll = {} -- teamID -> hero name -> key
		local function aiPickKey(teamID, d)
			local t = aiRoll[teamID]
			if not t then
				t = {}
				aiRoll[teamID] = t
			end
			local k = t[d.name]
			if not k then
				k = random() ^ (1 / max(0.1, d.cfg.aiPick or 1))
				t[d.name] = k
			end
			return k
		end

		local function aiNextHero(teamID, altarID)
			if research[teamID] then
				return ""
			end
			local udid = spGetUnitDefID(altarID)
			local opts = UnitDefs[udid] and UnitDefs[udid].buildOptions or {}
			local names = slotNames(teamID)
			local queued = queuedHeroes(altarID)
			local best, bestW
			for _, opt in ipairs(opts) do
				local d = heroDefs[opt]
				if d and not queued[d.name] then
					local ok, why = canStartHero(teamID, d.name, queued)
					if ok then
						local w = why == "revive" and 1000 or aiPickKey(teamID, d) -- v19-ai2: was (d.cfg.aiPick or 1) + random() * 0.01
						if not bestW or w > bestW then
							best, bestW = d.name, w
						end
					end
				end
			end
			if next(queued) then
				return "" -- the altar is already making one
			end
			return best or ""
		end

		-- build options of the team's altars: a new hero is disabled when the slots are full (a revive stays), the
		-- upgrade command shows the next upgrade (or is disabled at the top / while researching)
		function refreshAltars(teamID)
			local slots = teamSlots[teamID] or 1
			local used = slotsUsed(teamID)
			local r = research[teamID]
			for altarID, t in pairs(altars) do
				if t == teamID and alive(altarID) then
					local udid = spGetUnitDefID(altarID)
					local queued = queuedHeroes(altarID)
					for _, opt in ipairs(UnitDefs[udid].buildOptions or {}) do
						local d = heroDefs[opt]
						if d then
							local ok, why = canStartHero(teamID, d.name, queued)
							if not ok and why == "slots" then
								editDesc(altarID, -opt, true, string.format("All hero slots in use (%d/%d): research the next altar upgrade, or revive a fallen hero", used, slots))
							else
								editDesc(altarID, -opt, false, nil)
							end
						end
					end
					local nextUp = H.SLOT_UPGRADES[slots]
					local idx = Spring.FindUnitCmdDesc(altarID, CMD_ALTAR_UPGRADE)
					if idx then
						local tip, name
						if r then
							name = (H.SLOT_UPGRADES[r.level] or {}).name or "Upgrade"
							tip = string.format("%s: %d%% built (the altar does not build meanwhile; constructors that guard the altar help).%s",
								name, floor(r.progress * 100), r.prepaid and "" or "\nClick again: cancel, the spent metal and energy come back")
						elseif nextUp then
							name = nextUp.name
							tip = string.format("%s: hero slot %d of %d. Built like a unit: %d metal, %d energy, %d build time - drained while it builds; constructors that guard the altar help (the altar does not build meanwhile)",
								nextUp.name, slots + 1, H.MAX_HEROES, nextUp.metal, nextUp.energy, nextUp.buildtime)
						else
							name = "Altar upgraded"
							tip = string.format("All %d hero slots are open", H.MAX_HEROES)
						end
						Spring.EditUnitCmdDesc(altarID, idx, { name = name, tooltip = tip, disabled = (r and r.prepaid) or (not r and nextUp == nil) })
					end
					if isAITeam[teamID] then
						spSetUnitRulesParam(altarID, "hero_next", aiNextHero(teamID, altarID), ALLIED)
					end
				end
			end
			publishSlots(teamID)
		end

		function insertAltarCmd(altarID)
			if Spring.FindUnitCmdDesc(altarID, CMD_ALTAR_UPGRADE) then
				return
			end
			Spring.InsertUnitCmdDesc(altarID, {
				id = CMD_ALTAR_UPGRADE, type = CMDTYPE.ICON, name = "Altar Upgrade", action = "hero_altar_upgrade",
				tooltip = "Opens one more hero slot",
			})
		end

		-- v20: an altar upgrade is built like a unit (H.SLOT_UPGRADES: metal, energy, buildtime). Build power = the
		-- altar's own + the constructors that guard (assist) it within their build range; metal and energy are drained in
		-- proportion to the progress, a short storage slows it down. paid = true: the AI paid the whole price from its
		-- bank at the start (no drain).
		local function altarBuildPower(altarID)
			if not alive(altarID) then
				return 0
			end
			local ud = UnitDefs[spGetUnitDefID(altarID)]
			local bp = ud and ud.buildSpeed or 0
			local team = Spring.GetUnitTeam(altarID)
			local ax, _, az = spGetUnitPosition(altarID)
			local arad = Spring.GetUnitRadius(altarID) or 0
			for _, uid in ipairs(Spring.GetTeamUnits(team) or {}) do
				local bud = UnitDefs[spGetUnitDefID(uid)]
				if uid ~= altarID and bud and bud.isBuilder and (bud.buildSpeed or 0) > 0 and not heroes[uid] then
					local cmds = Spring.GetUnitCommands(uid, 1)
					local c = cmds and cmds[1]
					if c and c.id == CMD.GUARD and c.params and c.params[1] == altarID then
						local _, bp2 = spGetUnitHealth(uid)
						local ux, _, uz = spGetUnitPosition(uid)
						local reach = (bud.buildDistance or 128) + arad + 250 -- a guarding builder idles near the altar, not at it
						if ux and (ux - ax) ^ 2 + (uz - az) ^ 2 <= reach * reach then
							bp = bp + bud.buildSpeed
						end
					end
				end
			end
			return bp
		end

		local function setAltarBusy(altarID, busy)
			if alive(altarID) then
				local ud = UnitDefs[spGetUnitDefID(altarID)]
				Spring.SetUnitBuildSpeed(altarID, busy and 0 or (ud and ud.buildSpeed or 1))
			end
		end

		-- start the next altar upgrade at `altarID` (or cancel the running one: the spent resources come back).
		-- Returns true, or false and why: "max", "busy", "cancelled"
		function startResearch(teamID, altarID, paid)
			local slots = teamSlots[teamID] or 1
			local cur = research[teamID]
			if cur then
				if paid or cur.prepaid then
					return false, "busy"
				end
				research[teamID] = nil
				Spring.AddTeamResource(teamID, "metal", cur.spentM or 0)
				Spring.AddTeamResource(teamID, "energy", cur.spentE or 0)
				setAltarBusy(cur.altar, false)
				Spring.Echo(string.format("[t4heroes] team %d cancels %s at %d%%", teamID, (H.SLOT_UPGRADES[cur.level] or {}).name or "?", floor(cur.progress * 100)))
				refreshAltars(teamID)
				return false, "cancelled"
			end
			local up = H.SLOT_UPGRADES[slots]
			if not up then
				return false, "max"
			end
			local f = frameNow()
			research[teamID] = { level = slots, altar = altarID, progress = 0, spentM = 0, spentE = 0, prepaid = paid or nil,
				bp = 0, stall = 0, finish = f + floor(up.buildtime / max(1, altarBuildPower(altarID)) * GAME_SPEED) }
			setAltarBusy(altarID, true)
			if alive(altarID) then
				local x, y, z = spGetUnitPosition(altarID)
				ceg("hero-learn", x, y, z)
			end
			Spring.Echo(string.format("[t4heroes] team %d starts %s (slot %d) at altar %d", teamID, up.name, slots + 1, altarID))
			toUI("research", altarID, slots, research[teamID].finish)
			refreshAltars(teamID)
			return true
		end

		-- once a second (dt = 1 s)
		function researchTick(f)
			for teamID, r in pairs(research) do
				local up = H.SLOT_UPGRADES[r.level]
				if not alive(r.altar) then
					-- the altar is gone: another altar of the team continues the progress
					for aid, t in pairs(altars) do
						if t == teamID and alive(aid) then
							r.altar = aid
							setAltarBusy(aid, true)
							break
						end
					end
				end
				local bp = altarBuildPower(r.altar)
				local step = up and min(1 - r.progress, bp / max(1, up.buildtime)) or 1
				local frac = 1
				if step > 0 and up and not r.prepaid then
					local needM, needE = up.metal * step, up.energy * step
					local m = Spring.GetTeamResources(teamID, "metal") or 0
					local e = Spring.GetTeamResources(teamID, "energy") or 0
					frac = max(0, min(1, needM > 0 and m / needM or 1, needE > 0 and e / needE or 1))
					if frac > 0 then
						Spring.UseTeamResource(teamID, { metal = needM * frac, energy = needE * frac })
						r.spentM = r.spentM + needM * frac
						r.spentE = r.spentE + needE * frac
					end
				end
				r.progress = min(1, r.progress + step * frac)
				r.bp = floor(bp * frac)
				r.stall = (step > 0 and frac < 0.99) and 1 or 0
				local rate = up and bp * frac / max(1, up.buildtime) or 0
				r.finish = f + (rate > 0 and floor((1 - r.progress) / rate * GAME_SPEED) or 3600 * GAME_SPEED)
				if r.progress >= 1 - 1e-6 then
					research[teamID] = nil
					teamSlots[teamID] = min(H.MAX_HEROES, r.level + 1)
					setAltarBusy(r.altar, false)
					if alive(r.altar) then
						local x, y, z = spGetUnitPosition(r.altar)
						ceg("hero-levelup-big", x, y, z)
					end
					Spring.Echo(string.format("[t4heroes] team %d: altar upgrade done, %d hero slots", teamID, teamSlots[teamID]))
					toUI("slots", r.altar or -1, teamSlots[teamID])
					refreshAltars(teamID)
				else
					publishSlots(teamID)
				end
			end
		end

	end

	---------------------------------------------------------------- talents

	local prepaid = 0 -- metal an AI rank is paid with from the team's hero bank (see aiEconomy)

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

	-- v22: an AI rank is paid only from the team's hero bank (aiEconomy fills it with at most H.AI_BUY_SAVE of the
	-- metal income), never straight from the storage: the leveling budget of the AI stays a share of its income
	local function aiCanLearn(h, key)
		local state, cost = learnState(h, key)
		return state == "ok" and (cost or 0) <= prepaid
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
			return false, state
		end
		if cost and cost > 0 and prepaid >= cost then
			prepaid = prepaid - cost
		elseif cost and cost > 0 and not Spring.UseTeamResource(h.team, "metal", cost) then
			return false, "metal"
		end
		h.picks[#h.picks + 1] = key
		h.ranks[key] = rankOf(h, key) + 1
		applyStats(unitID, h)
		updateCmdDescs(unitID, h)
		publish(unitID, h)
		modHook(h, "rank", api, unitID, h, key, h.ranks[key])
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

	-- the metal of an ultimate / ability rank the level allows but the AI bank cannot pay yet, or nil
	local function aiWaitCost(h)
		for _, key in ipairs({ "ult", "a1", "a2", "a3" }) do
			if h.def.cfg[key] then
				local st, cost = learnState(h, key)
				if st == "metal" or (st == "ok" and (cost or 0) > prepaid) then
					return cost
				end
			end
		end
	end

	-- the AI spends its points (and metal): the ultimate whenever it can, then the abilities (lowest rank first),
	-- then the stats in the order of its role (H.AI_STAT_WEIGHTS: the lowest rank / weight next)
	local function learnAI(unitID, h)
		local guard = 0
		local weights = H.AI_STAT_WEIGHTS[h.def.cfg.aiRole or "center"] or H.AI_STAT_WEIGHTS.center
		while h.level - #h.picks > 0 and guard < 120 do
			guard = guard + 1
			local pick
			if h.def.cfg.ult and aiCanLearn(h, "ult") then
				pick = "ult"
			end
			if not pick then
				local bestR
				for _, key in ipairs({ "a1", "a2", "a3" }) do
					if h.def.cfg[key] and aiCanLearn(h, key) then
						local r = rankOf(h, key)
						if not bestR or r < bestR then
							pick, bestR = key, r
						end
					end
				end
			end
			if not pick then
				-- an ultimate / ability rank the level allows but the metal does not: keep the point for it (the AI
				-- bank pays it, see aiEconomy) instead of spending it on a stat
				if aiWaitCost(h) then
					return
				end
				local best
				for _, key in ipairs(H.statKeys) do
					if aiCanLearn(h, key) then
						local score = (rankOf(h, key) + 1) / (weights[key] or 1)
						if not best or score < best then
							pick, best = key, score
						end
					end
				end
			end
			if not pick or not learn(unitID, h, pick, true) then
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

	-- one level for metal (the Buy level button, t4hero:buylevel; an AI pays from its bank: paid = true).
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
		h.buyReady = f + (isAITeam[h.team] and H.AI_BUY_COOLDOWN or H.BUY_COOLDOWN) * GAME_SPEED
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
	local giveXPForDeath -- below (damage)
	local abilityUnitDestroyed, endMover -- below (kit, control)
	do

		local function newHero(unitID, udid, teamID, rec)
			local def = heroDefs[udid]
			local h = {
				unitID = unitID, def = def, team = teamID, ally = spGetUnitAllyTeam(unitID), level = 1, xp = 0, picks = {},
				ranks = {}, ready = {}, autocast = true, buff = nil, lastCrit = 0, undyingReady = 0, undyingUntil = 0, kills = 0,
				store = {}, disabled = {}, weaponsOff = {}, toggled = {}, dmgMult = 1, hpMult = 1, armor = 0, power = 1,
				ai = isAITeam[teamID] or false,
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
			local _, _, _, _, bp = spGetUnitHealth(unitID)
			if bp and bp < 1 then
				building[unitID] = { team = teamID, name = def.name }
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
			refreshAltars(teamID)
		end

		local CMD_TYPE = { map = CMDTYPE.ICON_MAP, unit = CMDTYPE.ICON_UNIT, ally = CMDTYPE.ICON_UNIT, unit_or_map = CMDTYPE.ICON_UNIT_OR_MAP }

		local function insertCmds(unitID, h)
			local cfg = h.def.cfg
			for cmdID, key in pairs(h.def.cmds) do
				local b = cfg[key]
				Spring.InsertUnitCmdDesc(unitID, {
					id = cmdID, type = CMD_TYPE[b.target or ""] or CMDTYPE.ICON, name = b.name, action = b.action,
					cursor = b.cursor or (b.target == "ally" and "Repair") or (b.target and "Attack") or nil,
					tooltip = b.name .. ": " .. (b.desc or ""), disabled = rankOf(h, key) == 0,
				})
			end
			Spring.InsertUnitCmdDesc(unitID, {
				id = CMD_HERO_AUTOCAST, type = CMDTYPE.ICON_MODE, name = "Autocast", action = "hero_autocast",
				tooltip = "Hero abilities cast themselves when useful", params = { 1, "hero_autocast_off", "hero_autocast_on" },
			})
		end

		function gadget:UnitFinished(unitID, unitDefID, teamID)
			if foundryDefs[unitDefID] then
				altars[unitID] = teamID
				insertAltarCmd(unitID)
				refreshAltars(teamID)
				return
			end
			local def = heroDefs[unitDefID]
			if not def then
				return
			end
			building[unitID] = nil
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
			modHook(h, "init", api, unitID, h) -- v19: before the AI learns ranks (rank hooks expect init state)
			if isAITeam[teamID] then
				learnAI(unitID, h)
			end
			publish(unitID, h)
			Spring.SetTeamRulesParam(teamID, "hero_built_" .. def.name, 1, ALLIED)
			local x, y, z = heroPos(unitID)
			if x then
				ceg(rec and "hero-revive" or "hero-levelup-big", x, y, z)
			end
			toUI(rec and "revived" or "born", unitID, h.level)
			refreshAltars(teamID)
		end


		function gadget:UnitDestroyed(unitID, unitDefID, teamID, attackerID)
			pendingRevive[unitID] = nil
			guardMult[unitID] = nil
			invuln[unitID] = nil
			auraDamage[unitID] = nil
			marks[unitID] = nil
			ctl.timedSlow[unitID] = nil
			ctl.unitBuffs[unitID] = nil
			ctl.taunts[unitID] = nil
			ctl.forced[unitID] = nil
			ctl.revealed[unitID] = nil
			scaled[unitID] = nil
			speedFactor[unitID] = nil
			ctl.speedApplied[unitID] = nil
			auraSlow[unitID] = nil
			for _, t in pairs(ub) do
				t[unitID] = nil
			end
			movers[unitID] = nil
			local wasBuilding = building[unitID]
			building[unitID] = nil
			if altars[unitID] then
				local t = altars[unitID]
				altars[unitID] = nil
				refreshAltars(t)
			end
			local summon = abilityUnitDestroyed(unitID) -- a summon gives no experience and drops nothing
			local eaten = consumed[unitID]
			consumed[unitID] = nil
			local _, _, _, _, bp = spGetUnitHealth(unitID)
			if bp and bp >= 1 and not summon then
				if eaten then
					if eaten.credit then
						giveXPForDeath(unitID, unitDefID, eaten.credit, true)
					end
				else
					giveXPForDeath(unitID, unitDefID, attackerID)
				end
			end
			local h = heroes[unitID]
			if wasBuilding and not h then
				refreshAltars(teamID)
			end
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
			modHook(h, "destroyed", api, unitID, h)
			itemHook("onHeroDeath", unitID, h, x, z)
			if x then
				ceg("hero-death", x, y, z)
			end
			toUI("died", unitID, h.level, level)
			refreshAltars(h.team)
		end

		function gadget:AllowUnitTransfer(unitID, unitDefID, oldTeam, newTeam, capture)
			local def = heroDefs[unitDefID]
			if def and not canStartHero(newTeam, def.name) then
				return false
			end
			return true
		end

		function gadget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
			local h = heroes[unitID]
			if h then
				h.team = newTeam
				h.ally = spGetUnitAllyTeam(unitID)
				h.ai = isAITeam[newTeam] or false
				h.retreating = false
				h.detached = false
				h.orderX = nil
				refreshAltars(oldTeam)
				refreshAltars(newTeam)
			end
			if altars[unitID] then
				altars[unitID] = newTeam
				refreshAltars(oldTeam)
				refreshAltars(newTeam)
			end
			if building[unitID] then
				building[unitID].team = newTeam
			end
			pendingRevive[unitID] = nil
		end

		-- builders may only start a hero that fits the team's slots (Lua-created units - scenes, cheats - are not checked)
		function gadget:AllowUnitCreation(unitDefID, builderID, builderTeam, x, y, z, facing)
			local def = heroDefs[unitDefID]
			if not def or not builderID then
				return true
			end
			local ok = canStartHero(builderTeam, def.name)
			if not ok then
				-- drop it from the altar's queue next frame (a factory would retry it forever)
				delayed[#delayed + 1] = { frame = frameNow() + 1, fn = function()
					if alive(builderID) then
						Spring.GiveOrderToUnit(builderID, -unitDefID, {}, { "right" })
					end
				end }
				toUI("slotsfull", builderID, teamSlots[builderTeam] or 1)
				return false
			end
			return true
		end

	end

	---------------------------------------------------------------- damage
	local pierceTick, slugTick
	do

		local slugHits = {}    -- projectileID * 65536 + victimID -> frame (pass-through slugs: one hit per victim)
		local passThrough = {} -- weaponDefID -> true: noexplode projectiles
		for wdid, wd in pairs(WeaponDefs) do
			if wd.noExplode then
				passThrough[wdid] = true
			end
		end
		function slugTick(f)
			for k, fr in pairs(slugHits) do
				if f - fr > 150 then
					slugHits[k] = nil
				end
			end
		end
		local pierceShots = {} -- projectileID (beams: "b<owner>:<weapon>") -> { owner, ally, len, share, dmg = {uid = dmg}, best, bestDmg }
		local inThorns = false

		local function vulnOf(uid, f)
			local ms = marks[uid]
			if not ms then
				return 0
			end
			local v = 0
			for _, mk in pairs(ms) do
				if mk.expire > f and mk.vuln then
					v = v + mk.vuln * mk.stacks
				end
			end
			return v
		end

		-- penetration (v19 dmgfix rules): once per projectile (a beam: per 6 frames per weapon), a budget of `pierce` x the
		-- damage of its most damaged victim, spread over the enemies on a line behind that victim, fading along it
		local function queuePierce(a, attackerID, victimID, dmg, projectileID, weaponDefID)
			local key = (projectileID and projectileID >= 0) and projectileID or ("b" .. attackerID .. ":" .. tostring(weaponDefID))
			local s = pierceShots[key]
			if not s then
				s = { owner = attackerID, ally = a.ally, len = H.PIERCE_LENGTH * a.def.fx, share = a.pierce, dmg = {} }
				pierceShots[key] = s
			end
			local d = (s.dmg[victimID] or 0) + dmg
			s.dmg[victimID] = d
			if not s.bestDmg or d > s.bestDmg then
				s.best, s.bestDmg = victimID, d
			end
		end

		function gadget:UnitPreDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
			if invuln[unitID] or ctl.eyes[unitID] then
				return 0, 0
			end
			local v = heroes[unitID]
			local f = frameNow()
			if v and (v.downedUntil or 0) > f then
				return 0, 0
			end
			local allied = attackerTeam and Spring.AreTeamsAllied(attackerTeam, unitTeam)
			-- hero warheads, novas, stuns and abilities never hurt their own side
			if allied and (heroWeapon[weaponDefID] or inAbility or inStun) then
				return 0, 0
			end
			if inStun then
				return damage, 1
			end
			local ability = inAbility or itemDamage()
			-- a projectile of the ability kit / api.fire with its own numbers: they apply when it explodes
			if projectileID and api.abProj[projectileID] and not ability then
				return 0, 0
			end
			if v and paralyzer and unstoppable(unitID) then
				return 0, 0
			end
			local m = (guardMult[unitID] or 1) * (1 - (auraArmor[unitID] or 0)) * (1 + vulnOf(unitID, f))
			local a = attackerID and heroes[attackerID]
			-- a pass-through slug (noexplode: Gauss, rails, disintegrators) hits a unit on several frames: once counts
			if a and not ability and projectileID and projectileID >= 0 and passThrough[weaponDefID] then
				local key = projectileID * 65536 + unitID
				if slugHits[key] then
					return 0, 0
				end
				slugHits[key] = f
			end
			if a and not ability then
				-- a hero's own weapon hit: the ONE multiplier (level, Firepower, damage mods, buffs) and the item bonus of
				-- the weapon's damage type
				local base = copyBase[weaponDefID] or weaponDefID
				local hm = a.dmgMult * a.def.dmgScale * (1 + dtypeBonus(a, wdType[base]))
				if not paralyzer then
					hm = hm * abilityAttackMult(a, unitID, unitDefID) -- kit crit / slayer
					local mods = a.mods
					if mods and mods.crit > 0 and random() < mods.crit then
						hm = hm * (2 + mods.critMult) -- items: crit chance, critMult adds to the x2
					end
				end
				local d = damage * hm
				local nd = modHook(a, "hit", api, attackerID, a, unitID, unitDefID, d, weaponDefID, paralyzer)
				if type(nd) == "number" then
					d = nd
				end
				nd = itemHook("hit", attackerID, a, unitID, unitDefID, d, weaponDefID, paralyzer, api)
				if type(nd) == "number" then
					d = nd
				end
				if not paralyzer and not allied and d > 0 and (a.pierce or 0) > 0 then
					queuePierce(a, attackerID, unitID, d, projectileID, weaponDefID)
				end
				m = m * (damage > 0 and d / damage or 0)
			elseif attackerID and not ability then
				local s = summoned[attackerID]
				if s then
					m = m * heroDamageMult -- v22: a hero's summons deal its damage coefficient too
					if s.scale then
						m = m * s.scale
					end
					local oh = heroes[s.owner]
					if oh and s.credit then
						m = m * (1 + dtypeBonus(oh, wdType[weaponDefID]))
					end
					-- the owner's module sees its summons' hits (Hive: per-hit slow)
					if oh and oh.def.mod and oh.def.mod.summonHit and damage > 0 then
						local nd = modHook(oh, "summonHit", api, s.owner, oh, attackerID, unitID, unitDefID, damage * m, weaponDefID)
						if type(nd) == "number" then
							m = max(0, nd) / damage
						end
					end
				end
				if auraDamage[attackerID] then
					m = m * (1 + auraDamage[attackerID])
				end
				if ub.damage[attackerID] then
					m = m * (1 + ub.damage[attackerID])
				end
			end
			if ub.armor[unitID] then
				m = m * (1 - ub.armor[unitID])
			end
			local sv = summoned[unitID]
			if sv and sv.scale then
				m = m / sv.scale
			end
			if v then
				m = m * (1 - v.armor) / (v.hpMult or 1)
				if v.undyingUntil > f then
					return 0, 0
				end
				-- buff armor, bladestorm, the absorb pool, undying (kit)
				m = abilityVictim(unitID, v, damage, m, paralyzer, f)
				if m <= 0 then
					return 0, 0
				end
				if v.def.mod and v.def.mod.damaged or (items() and items().damaged) then
					local ax, az
					if attackerID and spValidUnitID(attackerID) then
						ax, _, az = spGetUnitPosition(attackerID)
					end
					local dm = damage * m -- engine HP (x h.hpMult = effective HP)
					local ne = modHook(v, "damaged", api, unitID, v, dm, attackerID, weaponDefID, paralyzer, ax, az)
					if type(ne) == "number" then
						dm = max(0, ne)
					end
					ne = itemHook("damaged", unitID, v, dm, attackerID, weaponDefID, paralyzer, api)
					if type(ne) == "number" then
						dm = max(0, ne)
					end
					m = damage > 0 and dm / damage or 0
				end
				-- lethal: a module (resurrection ults) or an item may keep it alive
				if not paralyzer and m > 0 then
					local hp = spGetUnitHealth(unitID)
					if hp and damage * m >= hp then
						if modHook(v, "dying", api, unitID, v) == true or itemHook("dying", unitID, v, api) == true then
							v.undyingUntil = max(v.undyingUntil, f + 2)
							return 0, 0
						end
					end
				end
			end
			if m <= 0 then
				return 0, 0
			end
			if m ~= 1 then
				return damage * m, 1
			end
			return damage, 1
		end

		giveXPForDeath = function(unitID, unitDefID, attackerID, creditOnly)
			local cost = (unitCost[unitDefID] or 0) * (structureDefs[unitDefID] and H.XP_STRUCTURE or 1)
			if cost <= 0 then
				return
			end
			local ally = spGetUnitAllyTeam(unitID)
			local x, _, z = spGetUnitPosition(unitID)
			local killer, killerID = heroOf(attackerID)
			if killer and spGetUnitAllyTeam(killerID) ~= ally then
				killer.kills = (killer.kills or 0) + 1
				local bonus = H.XP_KILL * cost
				local victim = heroes[unitID]
				if victim then
					bonus = bonus + H.XP_HERO_KILL * cost * victim.level / 10
				end
				addXP(killerID, killer, bonus)
				modHook(killer, "victimDestroyed", api, killerID, killer, unitID, unitDefID)
				itemHook("onKill", killerID, unitID, unitDefID)
			end
			if x and attackerID and not creditOnly then
				local r2 = H.XP_SHARE_RADIUS * H.XP_SHARE_RADIUS
				for hid, h in pairs(heroes) do
					if hid ~= killerID and spGetUnitAllyTeam(hid) ~= ally then
						local hx, _, hz = spGetUnitPosition(hid)
						if hx and (hx - x) ^ 2 + (hz - z) ^ 2 < r2 then
							addXP(hid, h, H.XP_SHARE * cost)
						end
					end
				end
			end
		end

		function gadget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
			local victim = heroes[unitID]
			if victim and damage > 0 then
				victim.lastHit = frameNow()
				if attackerID and attackerTeam and not Spring.AreTeamsAllied(attackerTeam, unitTeam) then
					victim.attackers = victim.attackers or {}
					victim.attackers[attackerID] = victim.lastHit -- AI escorts focus them
				end
				-- thorns / reflect: part of the damage goes back to the attacker
				local bf = victim.buff and victim.buff.fx
				local th = (victim.mods and victim.mods.thorns or 0) + (bf and bf.reflect or 0) * (heroes[attackerID] and 0.5 or 1)
				if th > 0 and not paralyzer and not inThorns and attackerID and spValidUnitID(attackerID)
					and attackerTeam and not Spring.AreTeamsAllied(attackerTeam, unitTeam) then
					inThorns = true
					abilityHurt(attackerID, damage * (victim.hpMult or 1) * th, unitID, nil, victim.ally)
					inThorns = false
				end
			end
			if not attackerID or damage <= 0 then
				return
			end
			local h, heroID = heroOf(attackerID)
			if not h or (attackerTeam and Spring.AreTeamsAllied(attackerTeam, unitTeam)) then
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
			addXP(heroID, h, value)
			if inThorns or inAbility or paralyzer or heroID ~= attackerID or itemDamage() then
				return
			end
			abilityOnHit(attackerID, h, unitID) -- procs of the kit, a hit ends a cloak
			local ls = h.mods and h.mods.lifesteal or 0
			if ls > 0 then
				local hp, mhp = spGetUnitHealth(attackerID)
				if hp then
					Spring.SetUnitHealth(attackerID, min(mhp, hp + damage * ls / (h.hpMult or 1)))
				end
			end
		end

		-- every 6 frames: penetration damage on the lines behind the victims (ability path: no second multiplier)
		local PIERCE_FADE = 0.7
		function pierceTick(f)
			for key, p in pairs(pierceShots) do
				pierceShots[key] = nil
				local vx, _, vz = spGetUnitPosition(p.best)
				local ax, _, az = spGetUnitPosition(p.owner)
				local budget = p.bestDmg * p.share
				if vx and ax and budget >= 1 then
					local dx, dz = vx - ax, vz - az
					local dd = max(1, sqrt(dx * dx + dz * dz))
					dx, dz = dx / dd, dz / dd
					local line, seen = {}, {}
					for d = 100, p.len, 100 do
						local px, pz = vx + dx * d, vz + dz * d
						for _, uid in ipairs(spGetUnitsInCylinder(px, pz, 110)) do
							if not seen[uid] and not p.dmg[uid] and isEnemyOf(uid, p.ally) and not Spring.GetUnitIsDead(uid) then
								seen[uid] = true
								line[#line + 1] = { uid, d }
							end
						end
					end
					if #line > 0 then
						table.sort(line, function(a, b) return a[2] < b[2] end)
						local wsum, w = 0, 1
						for i = 1, #line do
							line[i][3] = w
							wsum = wsum + w
							w = w * PIERCE_FADE
						end
						local owner = spValidUnitID(p.owner) and p.owner or nil
						for i = 1, #line do
							abilityHurt(line[i][1], budget * line[i][3] / wsum, owner, nil, p.ally)
						end
						if f - (p.fxAt or -99) > 0 then
							local ex, ez = vx + dx * line[#line][2], vz + dz * line[#line][2]
							ceg("hero-wfx-pierce", ex, spGetGroundHeight(ex, ez) + 30, ez)
						end
					end
				end
			end
		end

	end

	---------------------------------------------------------------- projectiles: copies (api.swapWeapons), missile reach
	local projParams, replaceProjectile
	do

		projParams = { pos = { 0, 0, 0 }, speed = { 0, 0, 0 }, owner = -1, team = -1, gravity = 0, ttl = 900 }
		local beamParams = { pos = { 0, 0, 0 }, ["end"] = { 0, 0, 0 }, ttl = 3, owner = -1, team = -1 }
		local spSetProjectileDamages = Spring.SetProjectileDamages
		local weaponGravity = {} -- weaponDefID -> gravity per frame (negative) of a ballistic weapon with its own mygravity
		for wdid, wd in pairs(WeaponDefs) do
			if wd.type == "Cannon" and (wd.myGravity or 0) > 0 then
				weaponGravity[wdid] = -wd.myGravity
			end
		end

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

		-- a projectile of the hero is redrawn with weapondef `to` (a copy: same damage for projectiles, a beam copy only draws)
		function replaceProjectile(proID, ownerID, weaponDefID, to, h)
			local px, py, pz = Spring.GetProjectilePosition(proID)
			if not px then
				return proID
			end
			local n = h.def.numOf[weaponDefID] or 1
			if isBeam[weaponDefID] then
				local ex, ey, ez = beamEnd(proID, ownerID, n, px, py, pz)
				if not ex then
					return proID
				end
				Spring.DeleteProjectile(proID)
				beamParams.pos[1], beamParams.pos[2], beamParams.pos[3] = px, py, pz
				beamParams["end"][1], beamParams["end"][2], beamParams["end"][3] = ex, ey, ez
				beamParams.owner = ownerID
				beamParams.team = h.team
				beamParams.ttl = isBeam[weaponDefID]
				return Spring.SpawnProjectile(to, beamParams)
			end
			local vx, vy, vz = Spring.GetProjectileVelocity(proID)
			local _, target = Spring.GetProjectileTarget(proID)
			if not target then
				local tt, _, wt = Spring.GetUnitWeaponTarget(ownerID, n)
				if tt == 1 or tt == 2 then
					target = wt
				end
			end
			-- GetProjectileGravity reports the map gravity, not the weapon's own (mygravity)
			local grav = weaponGravity[weaponDefID] or (Spring.GetProjectileGravity and Spring.GetProjectileGravity(proID)) or gravityPerFrame
			local ttl = Spring.GetProjectileTimeToLive and Spring.GetProjectileTimeToLive(proID) or 900
			Spring.DeleteProjectile(proID)
			projParams.pos[1], projParams.pos[2], projParams.pos[3] = px, py, pz
			projParams.speed[1], projParams.speed[2], projParams.speed[3] = vx, vy, vz
			projParams.owner = ownerID
			projParams.team = h.team
			projParams.gravity = grav
			projParams.ttl = ttl
			projParams.tracking = type(target) == "number" and target or nil
			local newID = Spring.SpawnProjectile(to, projParams)
			projParams.tracking = nil
			if newID then
				local w = h.def.weapons[n]
				local aoe = w and w.aoe * sqrt(max(0.2, 1 + (h.mods and h.mods.splash or 0)))
				if aoe and w.aoe and abs(aoe - w.aoe) > 0.5 and spSetProjectileDamages then
					spSetProjectileDamages(newID, 0, "damageAreaOfEffect", aoe)
				end
				if type(target) == "number" then
					Spring.SetProjectileTarget(newID, target, string.byte("u"))
				elseif type(target) == "table" then
					Spring.SetProjectileTarget(newID, target[1], target[2], target[3])
				end
			end
			return newID or proID
		end

		function gadget:ProjectileCreated(proID, ownerID, weaponDefID)
			if not ownerID or not projWatch[weaponDefID] then
				return
			end
			local h = heroes[ownerID]
			if not h then
				return
			end
			local tm = h.ttlMult and h.ttlMult[weaponDefID]
			if tm then
				local ttl = Spring.GetProjectileTimeToLive(proID)
				if ttl and ttl > 0 then
					Spring.SetProjectileTimeToLive(proID, math.ceil(ttl * tm))
				end
			end
			local wdid = weaponDefID
			if h.swap and not noCopy[weaponDefID] then
				local map = h.def.copies[h.swap]
				local to = map and map[weaponDefID]
				if to then
					local newID = replaceProjectile(proID, ownerID, weaponDefID, to, h)
					if newID ~= proID then
						proID, wdid = newID, to
					end
				end
			end
			if proID and h.def.mod and h.def.mod.projectile then
				-- after a swap: the copy's weaponDefID, the original one as the extra argument
				modHook(h, "projectile", api, ownerID, h, proID, wdid, weaponDefID)
			end
		end

	end

	---------------------------------------------------------------- abilities: the generic kit
	-- Casting, damage, projectiles and timed effects of the kit (kinds: header). Values per rank (val).

	local cast -- kind -> cast function
	local K = {} -- the kit's functions used outside its block
	local abProj = {}  -- projectileID -> expiry frame: projectiles with the ability's own numbers (no engine damage)
	local shots = {}   -- projectileID -> shot { c, dmg, aoe, stun, emp, dtype, fx, onHit, expire }
	api.abProj = abProj
	do
		function K.abilityReady(h, key)
			return rankOf(h, key) > 0 and (h.ready[key] or 0) <= frameNow()
		end

		function K.startCooldown(unitID, h, key, seconds)
			local cd = (seconds or 30) * max(0.4, 1 - (h.mods and h.mods.cdr or 0))
			h.ready[key] = frameNow() + floor(cd * GAME_SPEED)
			spSetUnitRulesParam(unitID, "hero_ready_" .. key, h.ready[key], ALLIED)
			spSetUnitRulesParam(unitID, "hero_cd_" .. key, floor(cd * GAME_SPEED), ALLIED)
		end

		function K.markActive(unitID, key, seconds)
			spSetUnitRulesParam(unitID, "hero_on_" .. key, frameNow() + floor(seconds * GAME_SPEED), INLOS)
			spSetUnitRulesParam(unitID, "hero_dur_" .. key, floor(seconds * GAME_SPEED), INLOS)
		end

		-- who casts: kept by effects that outlive the hero (a barrage keeps falling after it dies)
		local function caster(unitID, h, key)
			local b = h.def.cfg[key]
			return { owner = unitID, ally = h.ally or spGetUnitAllyTeam(unitID), team = h.team, name = h.def.name, key = key,
				power = h.power or 1, extra = h.def.extra, novaWeapon = b and b.novaWeapon }
		end
		api.caster = caster

		local function ownerOf(c)
			return alive(c.owner) and c.owner or nil
		end

		-- damage (and stun / EMP) to every enemy of the caster within radius; returns the units hit
		local function abilityBlast(c, x, z, radius, dmg, stunSeconds, emp, dtype)
			local hit = enemiesIn(x, z, radius, c.ally)
			local owner = ownerOf(c)
			local opts = dtype and { dtype = dtype, ally = c.ally } or nil
			for _, uid in ipairs(hit) do
				if opts then
					abilityDamage(uid, dmg, owner, opts)
				else
					abilityHurt(uid, dmg, owner, nil, c.ally)
				end
				if emp and emp > 0 then
					abilityHurt(uid, emp, owner, 3, c.ally)
				end
				if stunSeconds and stunSeconds > 0 then
					stunUnit(uid, stunSeconds, owner, c.ally)
				end
			end
			return hit
		end
		api.blast = abilityBlast

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

		-- nova of an ability: a number is the finale's damage; true is novaDmg, or three times the ability's damage
		local function novaOf(b, r)
			local v = val(b.nova, r)
			if v == true then
				return val(b.novaDmg, r) or 3 * (val(b.dmg, r) or val(b.tick, r) or val(b.flat, r) or 3000)
			end
			return type(v) == "number" and v or 0
		end

		local abParams = { pos = { 0, 0, 0 }, speed = { 0, 0, 0 }, owner = -1, team = -1, gravity = 0, ttl = 900 }
		local abBeam = { pos = { 0, 0, 0 }, ["end"] = { 0, 0, 0 }, ttl = 8, owner = -1, team = -1 }

		-- the weapondef an ability spawns: its `weapon`, a hero_* extra of the hero named after the projectile,
		-- or the kit's own hero_ab_* (every hero has those, gamedata/custom_t4_abilities.lua)
		local WEAPON_FALLBACK = {
			missile = { "hero_missile", "hero_heavyrocket" }, shell = { "hero_shell", "hero_heavyshell" },
			meteor = { "hero_meteor" }, bolt = { "hero_stormbolt" }, nuke = { "hero_nuke", "hero_nova" },
			spear = { "hero_spear" }, chain = { "hero_chain" },
		}
		function K.abilityWeapon(h, b, proj)
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

		-- a spawned ability projectile deals no engine damage of its own (UnitPreDamaged): the numbers apply on impact
		function K.spawnAb(wdid, c, px, py, pz, vx, vy, vz, gravity, ttl)
			if not wdid or isStarburst[wdid] then
				return nil
			end
			abParams.pos[1], abParams.pos[2], abParams.pos[3] = px, py, pz
			abParams.speed[1], abParams.speed[2], abParams.speed[3] = vx, vy, vz
			abParams.owner = ownerOf(c) or -1
			abParams.team = c.team
			abParams.gravity = gravity or 0
			abParams.ttl = ttl or 900
			local pid = Spring.SpawnProjectile(wdid, abParams)
			if pid then
				abProj[pid] = frameNow() + (ttl or 900) + 30
			end
			return pid
		end

		-- a lightning bolt / beam drawn from a to b (hero_ab_bolt, or `wdid`: a LightningCannon / BeamLaser shot)
		function K.boltVisual(c, wdid, x1, y1, z1, x2, y2, z2, ttl)
			wdid = wdid or (c.extra and c.extra.hero_ab_bolt)
			if not wdid then
				return
			end
			abBeam.pos[1], abBeam.pos[2], abBeam.pos[3] = x1, y1, z1
			abBeam["end"][1], abBeam["end"][2], abBeam["end"][3] = x2, y2, z2
			abBeam.ttl = ttl or 8
			abBeam.owner = ownerOf(c) or -1
			abBeam.team = c.team
			return Spring.SpawnProjectile(wdid, abBeam)
		end

		function K.shotImpact(s, x, z)
			local y = spGetGroundHeight(x, z)
			local hit = abilityBlast(s.c, x, z, s.aoe, s.dmg, s.stun, s.emp, s.dtype)
			if s.para and s.para > 0 then
				for _, uid in ipairs(hit) do
					stunUnit(uid, s.para, ownerOf(s.c), s.c.ally)
				end
			end
			if s.fx then
				ceg(s.fx, x, y, z)
			end
			s.hits = (s.hits or 0) + #hit
			if s.onHit then
				local ok, err = pcall(s.onHit, x, z, hit)
				if not ok then
					Spring.Echo("[t4heroes] fire onHit error: " .. tostring(err))
				end
			end
			alog("%s %s impact dmg=%d aoe=%d hit=%d", s.c.name, s.c.key, s.dmg, s.aoe, #hit)
		end

		-- the nuclear (or EMP, or fire) finale of an ultimate: only its effect and sound, the damage is the ability's
		local FINALE_WEAPON = { ["hero-finale-emp"] = "hero_ab_finale_emp", ["hero-finale-fire"] = "hero_ab_finale_fire" }
		local function abilityFinale(c, x, z, dmg, radius, stunSeconds, fx)
			local y = spGetGroundHeight(x, z)
			local e = c.extra or {}
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
					K.shotImpact(s, px, pz)
				end
			end
			local h = attackerID and heroes[attackerID]
			if h and h.def.mod and h.def.mod.impact then
				modHook(h, "impact", api, attackerID, h, weaponDefID, px, py, pz, projectileID)
			end
			return false
		end

		---------------------------------------------------------------- abilities: self buffs

		-- h.buffs[id] = { expire, fx, r }; h.buff is their merge (applyStats reads it)
		local BUFF_SUM = { speed = true, damage = true, armor = true, regen = true, reload = true, turn = true, range = true,
			reflect = true, turretTurn = true }
		local BUFF_FLAG = { immobile = true, cloak = true, hidden = true, unstoppable = true }

		-- cloak: the engine cloak when the unitdef can cloak; otherwise the enemies' line of sight AND radar to the hero
		-- are switched off (v20: a radar blip stayed and enemy units kept shooting the "invisible" hero through it). The
		-- hero holds fire while cloaked (a shot would reveal it).
		local CLOAK_STATE = { los = false, prevLos = false, radar = false, contRadar = false }
		local CLOAK_MASK = { los = true, prevLos = true, radar = true, contRadar = true }
		local function losCloak(unitID, on)
			local myAlly = spGetUnitAllyTeam(unitID)
			for _, at in ipairs(Spring.GetAllyTeamList()) do
				if at ~= myAlly then
					if on then
						Spring.SetUnitLosState(unitID, at, CLOAK_STATE)
						Spring.SetUnitLosMask(unitID, at, CLOAK_MASK)
					else
						Spring.SetUnitLosMask(unitID, at, 0)
					end
				end
			end
		end
		api.losCloak = losCloak

		function setCloak(unitID, h, on)
			if on == (h.cloaked or false) then
				return
			end
			h.cloaked = on
			if h.def.canCloak then
				Spring.SetUnitCloak(unitID, on and 4 or false)
				Spring.SetUnitStealth(unitID, on and true or (UnitDefs[h.def.udid].stealth or false))
			else
				losCloak(unitID, on)
			end
			if on then
				local st = Spring.GetUnitStates(unitID)
				h.cloakFire = st and st.firestate or 2
				h.cloakFrom = frameNow()
				Spring.GiveOrderToUnit(unitID, CMD.FIRE_STATE, { 0 }, 0)
			else
				Spring.GiveOrderToUnit(unitID, CMD.FIRE_STATE, { h.cloakFire or 2 }, 0)
			end
			spSetUnitRulesParam(unitID, "hero_cloaked", on and 1 or 0, ALLIED)
			local x, y, z = heroPos(unitID)
			ceg("hero-cloak", x, y, z)
		end

		-- hidden (burrow): no collisions, untargetable, weapons off, sunk into the ground, unseen by enemies
		function setHidden(unitID, h, on)
			if on == (h.hidden or false) then
				return
			end
			h.hidden = on
			if on then
				Spring.SetUnitBlocking(unitID, false, false, false, false, false, false, false)
				Spring.SetUnitNeutral(unitID, true)
				h.weaponsOff.hidden = true
				if not h.cloaked then
					losCloak(unitID, true)
				end
				local x, y, z = spGetUnitPosition(unitID)
				MoveCtrl.Enable(unitID)
				MoveCtrl.SetPosition(unitID, x, spGetGroundHeight(x, z) - h.def.height * 0.6, z)
				movers[unitID] = { kind = "hidden", hero = true }
			else
				Spring.SetUnitBlocking(unitID, true, true, true, true, true, true, false)
				Spring.SetUnitNeutral(unitID, false)
				h.weaponsOff.hidden = nil
				if not h.cloaked then
					losCloak(unitID, false)
				end
				local x, _, z = spGetUnitPosition(unitID)
				if movers[unitID] and movers[unitID].kind == "hidden" then
					MoveCtrl.SetPosition(unitID, x, spGetGroundHeight(x, z), z)
					MoveCtrl.Disable(unitID)
					movers[unitID] = nil
				end
			end
			local x, y, z = heroPos(unitID)
			ceg("hero-dash", x, y, z)
		end

		function K.mergeBuffs(unitID, h, f)
			local merged, expire, nextEnd = {}, 0, nil
			for id, e in pairs(h.buffs or {}) do
				if e.expire > f then
					expire = max(expire, e.expire)
					nextEnd = nextEnd and min(nextEnd, e.expire) or e.expire
					for k, v in pairs(e.fx) do
						-- reload may be per weapon: { [weaponKey | weaponNum] = frac } (an api.buff table, or string keys)
						if k == "reload" and type(v) == "table" and (e.r == nil or type(next(v)) == "string") then
							merged.reloadW = merged.reloadW or {}
							for wk, wv in pairs(v) do
								merged.reloadW[wk] = (merged.reloadW[wk] or 0) + wv
							end
							v = nil
						else
							v = val(v, e.r)
						end
						if v == nil then
							-- (per-weapon reload, done)
						elseif BUFF_SUM[k] and type(v) == "number" then
							merged[k] = (merged[k] or 0) + v
						elseif k == "shieldRegen" or k == "scale" then
							merged[k] = max(merged[k] or 1, v)
						elseif BUFF_FLAG[k] and v then
							merged[k] = true
						end
					end
					if e.trailDmg then
						merged.trailDmg = max(merged.trailDmg or 0, e.trailDmg)
					end
				else
					h.buffs[id] = nil
					if h.toggled[id] then
						h.toggled[id] = nil
					end
				end
			end
			if merged.armor then
				merged.armor = min(0.8, merged.armor)
			end
			h.buff = expire > f and { expire = expire, fx = merged } or nil
			h.buffNext = nextEnd
			setCloak(unitID, h, merged.cloak or false)
			setHidden(unitID, h, merged.hidden or false)
			applyStats(unitID, h)
		end

		function K.addBuff(unitID, h, id, dur, fx, r, trailDmg)
			h.buffs = h.buffs or {}
			h.buffs[id] = { expire = dur and (frameNow() + floor(dur * GAME_SPEED)) or (frameNow() + NEVER), fx = fx or {}, r = r, trailDmg = trailDmg }
			K.mergeBuffs(unitID, h, frameNow())
		end

		function K.removeBuff(unitID, h, id)
			if h.buffs and h.buffs[id] then
				h.buffs[id] = nil
				K.mergeBuffs(unitID, h, frameNow())
				return true
			end
			return false
		end

		function K.endBuffs(unitID, h, flag)
			local changed = false
			for id, e in pairs(h.buffs or {}) do
				if e.fx[flag] then
					h.buffs[id] = nil
					changed = true
					spSetUnitRulesParam(unitID, "hero_on_" .. id, frameNow(), INLOS)
				end
			end
			if changed then
				K.mergeBuffs(unitID, h, frameNow())
			end
		end
		api.endBuffs = K.endBuffs

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

		-- the learned ability of a kind: b, rank, key
		local function learnedOf(h, kind)
			local cfg = h.def.cfg
			for _, key in ipairs(H.abilityKeys) do
				local b = cfg[key]
				if b and b.kind == kind then
					local r = rankOf(h, key)
					if r > 0 then
						return b, r, key
					end
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

		-- damage taken by a hero: bladestorm / buff armor, the absorb pool, undying (returns the new mult)
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
					K.markActive(unitID, key, 3)
					local c = caster(unitID, v, key)
					local nova = novaOf(b, r) * c.power
					delayed[#delayed + 1] = { frame = f + 1, fn = function()
						if heroes[unitID] then
							local _, maxHp = spGetUnitHealth(unitID)
							Spring.SetUnitHealth(unitID, maxHp * val(b.heal, r))
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
			abilityHurt(fromID, dmg, owner, nil, c.ally)
			ceg("hero-chain", x, y, z)
			local n = 1
			for _ = 1, jumps do
				local best, bestD
				for _, uid in ipairs(spGetUnitsInCylinder(x, z, radius)) do
					if not done[uid] and isEnemyOf(uid, c.ally) and not Spring.GetUnitIsDead(uid) then
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
				K.boltVisual(c, wdid, x, y + 25, z, nx, ny + 25, nz, 6)
				abilityHurt(best, dmg, owner, nil, c.ally)
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
				K.endBuffs(attackerID, h, "cloak")
			end
			local b, r, key = learnedOf(h, "proc_chain")
			if b and (h.procChain or 0) <= f then
				h.procChain = f + PROC_GAP
				if random() < val(b.chance, r) then
					local c = caster(attackerID, h, key)
					chainFrom(c, K.abilityWeapon(h, b, "chain"), victimID, val(b.dmg, r) * c.power, val(b.jumps, r), val(b.radius, r) or 450)
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

		local function castFx(name, unitID)
			local x, y, z = heroPos(unitID)
			ceg(name, x, y, z)
		end

		cast.active_buff = function(unitID, h, key, b, r)
			local dur = not b.toggle and val(b.duration, r) or nil
			K.addBuff(unitID, h, key, dur, b.buff, r, b.trailDmg and val(b.trailDmg, r) * (h.power or 1))
			if dur then
				K.markActive(unitID, key, dur)
			end
			castFx(b.fx or "hero-buff-power", unitID)
			return true
		end

		cast.active_guard = function(unitID, h, key, b, r)
			local dur = val(b.duration, r)
			events[#events + 1] = { kind = "guard", owner = unitID, expire = frameNow() + floor(dur * GAME_SPEED),
				radius = val(b.radius, r), mult = 1 - val(b.reduce, r), fx = b.tickFx or "hero-guard" }
			K.markActive(unitID, key, dur)
			castFx(b.fx or "hero-guard-cast", unitID)
			return true
		end

		cast.active_dome = function(unitID, h, key, b, r)
			local dur = val(b.duration, r)
			events[#events + 1] = { kind = "dome", owner = unitID, expire = frameNow() + floor(dur * GAME_SPEED),
				radius = val(b.radius, r), fx = b.tickFx or "hero-dome" }
			K.markActive(unitID, key, dur)
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
			local pid = K.spawnAb(wdid, c, x + s.ox, y + s.h, z + s.oz, -s.ox / s.t, -s.h / s.t, -s.oz / s.t)
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
			local pid = K.spawnAb(wdid, c, x + (random() - 0.5) * 70, y + 90, z + (random() - 0.5) * 70,
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
			local wdid = K.abilityWeapon(h, b, proj)
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
						K.boltVisual(c, wdid, x + random(-220, 220), y + 1700, z + random(-220, 220), x, y + 5, z, 8)
						K.shotImpact(shot, x, z)
					elseif from == "sky" then
						skyShot(c, wdid, proj, x, z, shot)
					elseif alive(unitID) then
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
			K.markActive(unitID, key, dur)
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
			K.markActive(unitID, key, dur)
			alog("%s %s beam tick=%d radius=%d duration=%d", c.name, key, val(b.tick, r) * c.power, val(b.radius, r), dur)
			return true
		end

		cast.active_spear = function(unitID, h, key, b, r, tx, tz, targetID)
			if not alive(targetID) then
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
			local wdid = K.abilityWeapon(h, b, "spear")
			local speed = wdid and WeaponDefs[wdid].projectilespeed or 120
			if wdid then
				K.spawnAb(wdid, c, x, y + 60, z, dx / d * speed, (dy - 40) / d * speed, dz / d * speed)
			end
			ceg("hero-pierce-big", x, y + 60, z)
			local pct = val(b.pct, r) or 0
			local flat = (val(b.flat, r) or 0) * c.power
			local line = (val(b.line, r) or 0) * c.power
			local nova = novaOf(b, r) * c.power
			delayed[#delayed + 1] = { frame = frameNow() + floor(d / speed) + 1, fn = function()
				local hitLine = {}
				local n = 0
				local len = sqrt(dx * dx + dz * dz)
				for s = 0, len, 100 do
					local px, pz = x + dx / max(1, len) * s, z + dz / max(1, len) * s
					for _, uid in ipairs(enemiesIn(px, pz, 110, c.ally)) do
						if uid ~= targetID and not hitLine[uid] then
							hitLine[uid] = true
							n = n + 1
							abilityHurt(uid, line, ownerOf(c), nil, c.ally)
						end
					end
				end
				local total = 0
				if alive(targetID) then
					local _, maxHp = spGetUnitHealth(targetID)
					local vh = heroes[targetID]
					total = (maxHp or 0) * (vh and vh.hpMult or 1) * pct + flat
					abilityHurt(targetID, total, ownerOf(c), nil, c.ally)
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

		local function fireAt(c, x, z, dps, seconds)
			events[#events + 1] = { kind = "fire", owner = c.owner, free = true, c = c, x = x, z = z, radius = 150,
				dmg = dps * 0.2, expire = frameNow() + floor(seconds * GAME_SPEED) }
			ceg("hero-firepatch", x, spGetGroundHeight(x, z), z)
		end

		-- the kit dash: api.dash with damage along the way
		cast.active_dash = function(unitID, h, key, b, r, tx, tz)
			if not tx or movers[unitID] or api.pinned(unitID) then
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
				tx, tz, d = x + dx / d * range, z + dz / d * range, range
			end
			local c = caster(unitID, h, key)
			local dmg = (val(b.dmg, r) or 0) * c.power
			local radius = val(b.radius, r) or 200
			local stunT = val(b.stun, r)
			local burn = (val(b.burn, r) or 0) * c.power
			local hit, n, lastFire = {}, 0, nil
			ceg(b.fx or "hero-dash", x, y, z)
			api.dash(unitID, h, tx, tz, { speed = (b.speed or 55) * GAME_SPEED, onStep = function(nx, nz)
				for _, uid in ipairs(enemiesIn(nx, nz, radius, c.ally)) do
					if not hit[uid] then
						hit[uid] = true
						n = n + 1
						abilityHurt(uid, dmg, unitID, nil, c.ally)
						if stunT and stunT > 0 then
							stunUnit(uid, stunT, unitID, c.ally)
						end
					end
				end
				ceg(b.trailFx or "hero-dash-trail", nx, spGetGroundHeight(nx, nz), nz)
				if burn > 0 and (not lastFire or (nx - lastFire[1]) ^ 2 + (nz - lastFire[2]) ^ 2 > 140 * 140) then
					lastFire = { nx, nz }
					fireAt(c, nx, nz, burn, b.burnTime or 4)
				end
			end, onLand = function(nx, nz)
				ceg("hero-dash", nx, spGetGroundHeight(nx, nz), nz)
				alog("%s %s dash dmg=%d radius=%d hit=%d burn=%d", c.name, key, dmg, radius, n, burn)
			end })
			K.markActive(unitID, key, d / ((b.speed or 55) * GAME_SPEED) + 0.3)
			return true
		end

		cast.active_bladestorm = function(unitID, h, key, b, r)
			local dur = val(b.duration, r)
			local c = caster(unitID, h, key)
			h.bladestorm = { expire = frameNow() + floor(dur * GAME_SPEED), armor = val(b.armor, r) or 0 }
			events[#events + 1] = { kind = "bladestorm", owner = unitID, expire = h.bladestorm.expire, c = c,
				radius = val(b.radius, r), dmg = val(b.dmg, r) * c.power, fx = b.fx or "hero-bladestorm" }
			K.markActive(unitID, key, dur)
			alog("%s %s bladestorm dmg=%d per 0.2 s radius=%d", c.name, key, val(b.dmg, r) * c.power, val(b.radius, r))
			return true
		end

		cast.active_summon = function(unitID, h, key, b, r)
			local ids = api.summon(unitID, h, b.unit, val(b.count, r), { expire = val(b.duration, r), spread = b.spread, fx = b.fx })
			K.markActive(unitID, key, val(b.duration, r))
			alog("%s %s summon %s x%d for %d s", h.def.name, key, tostring(b.unit), #ids, val(b.duration, r))
			return #ids > 0
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
			local wdid = K.abilityWeapon(h, b, "missile")
			local shot = { c = c, dmg = val(b.dmg, r) * c.power, aoe = val(b.aoe, r) or 150, stun = val(b.stun, r),
				emp = (val(b.emp, r) or 0) * c.power, fx = b.impactFx, expire = frameNow() + 900 }
			for i = 1, n do
				local t = targets[(i - 1) % #targets + 1].uid
				delayed[#delayed + 1] = { frame = frameNow() + 1 + (i - 1) * 2, fn = function()
					if alive(unitID) and spValidUnitID(t) then
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
			local n = healAllies(c, x, z, val(b.radius, r), heal, "hero-heal-spark")
			ceg(b.fx or "hero-nova-heal", x, y, z)
			alog("%s %s repair heal=%d radius=%d units=%d", c.name, key, heal, val(b.radius, r), n)
			return true
		end

		cast.active_cloak = function(unitID, h, key, b, r)
			local dur = val(b.duration, r)
			K.addBuff(unitID, h, key, dur, { cloak = true, speed = b.speed }, r)
			K.markActive(unitID, key, dur)
			alog("%s %s cloak %d s", h.def.name, key, dur)
			return true
		end

		cast.active_shield = function(unitID, h, key, b, r)
			local dur = val(b.duration, r)
			local amount = val(b.absorb, r) * (h.power or 1)
			api.absorb(unitID, h, amount, dur)
			h.absorb.key = key
			K.markActive(unitID, key, dur)
			castFx(b.fx or "hero-shield", unitID)
			alog("%s %s shield absorb=%d for %d s", h.def.name, key, amount, dur)
			return true
		end

		-- a toggle ability ends: the module's K.toggleOff / the kit's buff; the cooldown starts now
		function K.toggleOff(unitID, h, key)
			if not h.toggled[key] then
				return false
			end
			h.toggled[key] = nil
			local b = h.def.cfg[key]
			local r = rankOf(h, key)
			if b.kind == "custom" then
				modHook(h, "toggleOff", api, unitID, h, key, r)
			else
				K.removeBuff(unitID, h, key)
			end
			K.startCooldown(unitID, h, key, val(b.cooldown, r))
			spSetUnitRulesParam(unitID, "hero_toggle_" .. key, 0, INLOS)
			spSetUnitRulesParam(unitID, "hero_on_" .. key, frameNow(), INLOS)
			alog("%s %s toggled off", h.def.name, key)
			return true
		end

		-- cast an ability now; tx/tz/targetID for targeted ones. Returns true when it went off.
		function K.tryCast(unitID, h, key, tx, tz, targetID, ty)
			local b = h.def.cfg[key]
			if not b or b.passive or rankOf(h, key) <= 0 then
				return false
			end
			if b.toggle and h.toggled[key] then
				return K.toggleOff(unitID, h, key)
			end
			if not K.abilityReady(h, key) or (h.downedUntil or 0) > frameNow() then
				return false
			end
			local r = rankOf(h, key)
			local ok
			if b.kind == "custom" then
				if tx and not ty then
					ty = spGetGroundHeight(tx, tz)
				end
				ok = modHook(h, "cast", api, unitID, h, key, r, tx, ty, tz, targetID) == true
			elseif cast[b.kind] then
				ok = cast[b.kind](unitID, h, key, b, r, tx, tz, targetID)
			end
			if not ok then
				return false
			end
			if b.toggle then
				h.toggled[key] = true
				spSetUnitRulesParam(unitID, "hero_toggle_" .. key, 1, INLOS)
				spSetUnitRulesParam(unitID, "hero_on_" .. key, frameNow() + NEVER, INLOS)
			else
				K.startCooldown(unitID, h, key, val(b.cooldown, r))
			end
			alog("%s %s cast %s rank %d", h.def.name, key, b.kind, r)
			local idx = 0
			for i, k in ipairs(H.abilityKeys) do
				if k == key then
					idx = i
				end
			end
			toUI("cast", unitID, r, idx)
			return true
		end

		function K.castRange(b, r)
			if b.kind == "active_dash" then
				return 1e6 -- a dash goes as far as it can toward the point
			end
			return val(b.range, r) or 0
		end

		---------------------------------------------------------------- abilities: timed effects

		-- every 6 frames: beams, bladestorms, fire on the ground, burning trails
		function K.processEvents(f)
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
		function K.refreshProtection(f)
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

		-- every frame: projectiles that exploded; every 0.5 s summons; every 10 s stale shots
		function K.abilityFrame(f)
			for i = #exploded, 1, -1 do
				abProj[exploded[i]] = nil
				exploded[i] = nil
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
			local s = summoned[unitID]
			summoned[unitID] = nil
			if s and s.group then
				s.group.ids[unitID] = nil
			end
			return s ~= nil
		end

		---------------------------------------------------------------- abilities: passives, every second

		local AURA_FX = { aura_heal = "hero-aura-heal", aura_damage = "hero-aura-command", aura_armor = "hero-aura-armor", aura_slow = "hero-aura-slow" }

		function K.abilityPassivesBegin()
			for k in pairs(auraArmor) do
				auraArmor[k] = nil
			end
			for k in pairs(auraSlow) do
				auraSlow[k] = nil
			end
		end

		-- self buffs that ran out, buff regeneration, the absorb pool
		function K.abilityBuffTick(unitID, h, f, x, y, z)
			if h.buffNext and h.buffNext <= f then
				K.mergeBuffs(unitID, h, f)
			end
			local bf = h.buff and h.buff.expire > f and h.buff.fx
			if bf and bf.regen then
				healUnit(unitID, bf.regen)
			end
			if bf and not bf.cloak and not bf.hidden and f % 60 < 30 and (bf.armor or bf.speed or bf.damage) then
				ceg(bf.armor and "hero-buff-armor" or (bf.speed and "hero-buff-speed" or "hero-buff-power"), x, y, z)
			end
			local ab = h.absorb
			if ab then
				if ab.expire <= f or (ab.left <= 0 and not ab.keep) then
					h.absorb = nil
					spSetUnitRulesParam(unitID, "hero_absorb", 0, ALLIED)
					spSetUnitRulesParam(unitID, "hero_absorb_max", 0, ALLIED)
					if ab.key then
						spSetUnitRulesParam(unitID, "hero_on_" .. ab.key, f, INLOS)
					end
				else
					ceg("hero-shield-tick", x, y, z)
				end
			end
		end

		function K.abilityAuras(unitID, h, f, x, y, z, ally, healBest)
			local p = h.power or 1
			for _, key in ipairs(H.abilityKeys) do
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
							auraSlow[uid] = max(auraSlow[uid] or 0, s)
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
		function K.abilityShield(unitID, h)
			local num = h.def.shieldNum
			if not num then
				return
			end
			local _, charge = Spring.GetUnitShieldState(unitID, num)
			if not charge then
				return
			end
			local cap, regenMult = h.def.shieldPower, 1
			for _, key in ipairs(H.abilityKeys) do
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

	end

	---------------------------------------------------------------- control: movement, slows, marks, summons
	-- Forced movement uses MoveCtrl (movers[uid]); slows / roots / unit speed buffs are one speed factor per unit
	-- (speedTick); marks are timed stacks on any unit; summons are tracked units of a hero.

	local controlTick, summonTick, speedTick, marksTick, revealTick
	do
		local function groundY(x, z)
			return max(spGetGroundHeight(x, z), 0)
		end

		local function yawTo(dx, dz)
			return math.atan2(dx, dz)
		end

		-- start ctl.forced movement of a unit: m = { kind, frames, step = function(m, t) -> x, y, z, yaw | nil, done = fn }
		local function startMover(uid, m)
			if movers[uid] then
				endMover(uid, true)
			end
			m.start = frameNow()
			m.ctx = m.ctx or fxContext()
			movers[uid] = m
			MoveCtrl.Enable(uid)
			if m.untargetable then
				Spring.SetUnitNeutral(uid, true)
			end
		end

		endMover = function(uid, quiet)
			local m = movers[uid]
			if not m then
				return
			end
			movers[uid] = nil
			if alive(uid) then
				local x, _, z = spGetUnitPosition(uid)
				if x and m.kind ~= "hidden" then
					MoveCtrl.SetPosition(uid, x, groundY(x, z), z)
				end
				MoveCtrl.Disable(uid)
				if m.untargetable then
					Spring.SetUnitNeutral(uid, false)
				end
				local h = heroes[uid]
				if h then
					applyHeroSpeed(uid, h)
				end
				if m.onLand and not quiet then
					local prev = fxOwner(m.ctx)
					local ok, err = pcall(m.onLand, x, z)
					fxOwner(prev)
					if not ok then
						Spring.Echo("[t4heroes] movement onLand error: " .. tostring(err))
					end
				end
			end
		end

		-- every frame: ctl.forced movement
		local function moversTick(f)
			-- a snapshot: onStep / onLand may start or end movements and kill units
			local list = {}
			for uid, m in pairs(movers) do
				list[#list + 1] = uid
			end
			for _, uid in ipairs(list) do
				local m = movers[uid]
				if not m then
					-- ended meanwhile
				elseif not alive(uid) then
					movers[uid] = nil
				elseif m.step then
					local t = (f - m.start) / max(1, m.frames)
					if t >= 1 then
						endMover(uid)
					else
						local ok, x, y, z, yaw = pcall(m.step, m, t, f)
						if ok and x then
							x, z = clampX(x), clampZ(z)
							MoveCtrl.SetPosition(uid, x, y or groundY(x, z), z)
							if yaw then
								MoveCtrl.SetRotation(uid, m.pitch or 0, yaw, m.roll or 0)
							end
							if m.onStep and (f - m.start) % 2 == 0 then
								local prev = fxOwner(m.ctx)
								local ok2, err = pcall(m.onStep, x, z)
								fxOwner(prev)
								if not ok2 then
									Spring.Echo("[t4heroes] movement onStep error: " .. tostring(err))
									m.onStep = nil
								end
							end
						elseif not ok then
							Spring.Echo("[t4heroes] movement error: " .. tostring(x))
							endMover(uid, true)
						end
					end
				end
			end
		end

		-- a mark with noDash (Web Field): no dash, leap, blink, push / pull / throw for that unit
		local function pinned(uid)
			local ms = marks[uid]
			if ms then
				local f = frameNow()
				for _, mk in pairs(ms) do
					if mk.noDash and mk.expire > f then
						return true
					end
				end
			end
			return false
		end
		api.pinned = pinned

		local function canDisplace(uid)
			if pinned(uid) then
				return false
			end
			local udid = spGetUnitDefID(uid)
			if not udid or structureDefs[udid] or airDefs[udid] or foundryDefs[udid] then
				return false
			end
			return true
		end

		function api.dash(unitID, h, x, z, opts)
			opts = opts or {}
			if pinned(unitID) then
				return false
			end
			local x0, y0, z0 = spGetUnitPosition(unitID)
			if not x0 then
				return false
			end
			x, z = clampX(x), clampZ(z)
			local dx, dz = x - x0, z - z0
			local d = sqrt(dx * dx + dz * dz)
			local frames = opts.seconds and opts.seconds * GAME_SPEED or d / max(1, (opts.speed or 900) / GAME_SPEED)
			local arc = opts.arc or 0
			local yaw = yawTo(dx, dz)
			startMover(unitID, { kind = "dash", frames = max(2, floor(frames)), untargetable = opts.untargetable,
				onStep = opts.onStep, onLand = opts.onLand,
				step = function(m, t)
					local px, pz = x0 + dx * t, z0 + dz * t
					return px, groundY(px, pz) + arc * 4 * t * (1 - t), pz, yaw
				end })
			Spring.GiveOrderToUnit(unitID, CMD.STOP, {}, 0)
			return true
		end

		-- blink: to the nearest pathable point around x, z (ground snap); clears orders
		function api.blink(unitID, x, z)
			local udid = spGetUnitDefID(unitID)
			if pinned(unitID) then
				return false
			end
			if not udid then
				return false
			end
			x, z = clampX(x), clampZ(z)
			local tx, tz
			for ring = 0, 6 do
				local rr = ring * 48
				for a = 0, (ring == 0 and 0 or 7) do
					local px, pz = x + math.cos(a * 0.785) * rr, z + math.sin(a * 0.785) * rr
					if Spring.TestMoveOrder(udid, px, spGetGroundHeight(px, pz), pz) then
						tx, tz = px, pz
						break
					end
				end
				if tx then
					break
				end
			end
			if not tx then
				return false
			end
			local ox, oy, oz = spGetUnitPosition(unitID)
			ceg("hero-blink", ox, oy, oz)
			Spring.SetUnitPosition(unitID, tx, tz)
			Spring.GiveOrderToUnit(unitID, CMD.STOP, {}, 0)
			ceg("hero-blink", tx, spGetGroundHeight(tx, tz), tz)
			return true
		end

		-- displace an enemy from where it is toward / away from a point (heroes half the distance)
		local function displace(uid, tx, tz, dist, seconds, arc, onLand)
			if not alive(uid) or not canDisplace(uid) or unstoppable(uid) then
				return false
			end
			local x0, _, z0 = spGetUnitPosition(uid)
			local dx, dz = tx - x0, tz - z0
			local d = sqrt(dx * dx + dz * dz)
			if d < 1 then
				return false
			end
			if heroes[uid] then
				dist = dist * 0.5
			end
			dist = min(dist, d)
			dx, dz = dx / d * dist, dz / d * dist
			local m = { kind = "displace", frames = max(2, floor((seconds or 0.5) * GAME_SPEED)), onLand = onLand,
				step = function(_, t)
					local px, pz = x0 + dx * t, z0 + dz * t
					return px, groundY(px, pz) + (arc or 0) * 4 * t * (1 - t), pz
				end }
			startMover(uid, m)
			return true
		end

		function api.push(victimID, fromX, fromZ, dist, seconds)
			local x, _, z = spGetUnitPosition(victimID)
			if not x then
				return false
			end
			local dx, dz = x - fromX, z - fromZ
			local d = max(1, sqrt(dx * dx + dz * dz))
			return displace(victimID, x + dx / d * dist * 2, z + dz / d * dist * 2, dist, seconds)
		end

		function api.pull(victimID, toX, toZ, dist, seconds)
			return displace(victimID, toX, toZ, dist, seconds)
		end

		function api.throw(victimID, x, z, seconds, onLand)
			local x0, _, z0 = spGetUnitPosition(victimID)
			if not x0 then
				return false
			end
			local d = sqrt((x - x0) ^ 2 + (z - z0) ^ 2)
			return displace(victimID, x, z, d, seconds or 1, max(80, d * 0.35), onLand)
		end

		function api.orbitAround(unitID, h, targetID, radius, seconds)
			if not alive(targetID) then
				return false
			end
			local x, _, z = spGetUnitPosition(unitID)
			local tx, _, tz = spGetUnitPosition(targetID)
			local a0 = math.atan2(z - tz, x - tx)
			local w = max(0.6, (h and h.moveSpeed or 60) / max(50, radius)) -- radians per second
			startMover(unitID, { kind = "orbit", frames = floor(seconds * GAME_SPEED),
				step = function(m, t, f)
					if not alive(targetID) then
						return nil
					end
					local cx, _, cz = spGetUnitPosition(targetID)
					local a = a0 + w * (f - m.start) / GAME_SPEED
					local px, pz = cx + math.cos(a) * radius, cz + math.sin(a) * radius
					return px, groundY(px, pz), pz, yawTo(-math.sin(a), math.cos(a))
				end })
			return true
		end

		-- emulated turret spin: the whole unit turns in place; onStep(angle, x, z) every 2 frames
		function api.turretSpin(unitID, seconds, degPerSec, onStep)
			local x, _, z = spGetUnitPosition(unitID)
			if not x then
				return false
			end
			local h = heroes[unitID]
			local _, yaw0 = Spring.GetUnitRotation(unitID)
			yaw0 = yaw0 or 0
			local m
			m = { kind = "spin", frames = floor(seconds * GAME_SPEED),
				step = function(mm, t, f)
					local yaw = yaw0 + math.rad(degPerSec) * (f - mm.start) / GAME_SPEED
					mm.angle = yaw
					return x, groundY(x, z), z, yaw
				end }
			if onStep then
				m.onStep = function(px, pz)
					onStep(m.angle or yaw0, px, pz)
				end
			end
			startMover(unitID, m)
			return true
		end

		-- downed (resurrection ults): invulnerable, untargetable, still, weapons off, slumped; onRise(api, unitID, h)
		function api.downed(unitID, h, seconds, onRise)
			local f = frameNow()
			h.downedUntil = f + floor(seconds * GAME_SPEED)
			h.weaponsOff.downed = true
			applyStats(unitID, h)
			local x, _, z = spGetUnitPosition(unitID)
			local _, yaw = Spring.GetUnitRotation(unitID)
			startMover(unitID, { kind = "downed", frames = floor(seconds * GAME_SPEED), untargetable = true, pitch = 0.22, roll = 0.12,
				step = function()
					return x, groundY(x, z) - h.def.height * 0.12, z, yaw or 0
				end,
				onLand = function()
					h.downedUntil = nil
					h.weaponsOff.downed = nil
					if heroes[unitID] then
						applyStats(unitID, h)
						if onRise then
							local ok, err = pcall(onRise, api, unitID, h)
							if not ok then
								Spring.Echo("[t4heroes] downed onRise error: " .. tostring(err))
							end
						end
					end
				end })
			Spring.GiveOrderToUnit(unitID, CMD.STOP, {}, 0)
			return true
		end

		-- slows / roots / speed buffs: one factor per unit, applied when it changes (heroes: applyHeroSpeed)
		local function setUnitSpeed(uid, factor)
			local ud = UnitDefs[spGetUnitDefID(uid) or -1]
			if not ud or ud.canFly or (ud.speed or 0) <= 0 then
				return
			end
			local spd = ud.speed * factor
			pcall(MoveCtrl.SetGroundMoveTypeData, uid, { maxSpeed = spd, maxWantedSpeed = spd })
		end

		speedTick = function(f)
			local want = {}
			for uid, s in pairs(auraSlow) do
				want[uid] = { slow = s, speed = 0 }
			end
			for uid, s in pairs(ctl.timedSlow) do
				if s.expire <= f then
					ctl.timedSlow[uid] = nil
				else
					want[uid] = want[uid] or { slow = 0, speed = 0 }
					want[uid].slow = max(want[uid].slow, s.frac)
				end
			end
			for uid, ms in pairs(marks) do
				for _, mk in pairs(ms) do
					if mk.expire > f and (mk.slow or mk.root) then
						want[uid] = want[uid] or { slow = 0, speed = 0 }
						want[uid].slow = max(want[uid].slow, mk.slow or 0)
						want[uid].root = want[uid].root or mk.root
					end
				end
			end
			for uid, s in pairs(ub.speed) do
				want[uid] = want[uid] or { slow = 0, speed = 0 }
				want[uid].speed = s
			end
			for uid, w in pairs(want) do
				local factor
				local h = heroes[uid]
				if h and unstoppable(uid) then
					factor = 1 + w.speed
				else
					local slow = h and w.slow * 0.5 or w.slow
					factor = w.root and 0.02 or max(0.1, 1 - slow) * (1 + w.speed)
				end
				if abs(factor - (ctl.speedApplied[uid] or 1)) > 0.01 and alive(uid) and not movers[uid] then
					ctl.speedApplied[uid] = factor
					speedFactor[uid] = factor
					if h then
						applyHeroSpeed(uid, h)
					else
						setUnitSpeed(uid, factor)
					end
				end
			end
			for uid in pairs(ctl.speedApplied) do
				if not want[uid] then
					ctl.speedApplied[uid] = nil
					speedFactor[uid] = nil
					if alive(uid) then
						if heroes[uid] then
							applyHeroSpeed(uid, heroes[uid])
						else
							setUnitSpeed(uid, 1)
						end
					end
				end
			end
		end

		function api.slow(uid, frac, seconds)
			if not alive(uid) then
				return false
			end
			local f = frameNow()
			local cur = ctl.timedSlow[uid]
			local exp = f + floor(seconds * GAME_SPEED * (heroes[uid] and 0.5 or 1))
			if not cur or cur.expire <= f or frac >= cur.frac then
				ctl.timedSlow[uid] = { frac = frac, expire = max(exp, cur and cur.frac == frac and cur.expire or 0) }
			end
			return true
		end

		-- reveal a unit to an allyteam until `untilFrame` (LOS mask; a cloaked one is decloaked)
		local function revealUnit(uid, ally, untilFrame)
			if spGetUnitAllyTeam(uid) == ally then
				return
			end
			ctl.revealed[uid] = ctl.revealed[uid] or {}
			ctl.revealed[uid][ally] = max(ctl.revealed[uid][ally] or 0, untilFrame)
			local h = heroes[uid]
			if h and h.cloaked then
				K.endBuffs(uid, h, "cloak")
			end
			if Spring.GetUnitIsCloaked(uid) then
				Spring.SetUnitCloak(uid, false)
			end
			Spring.SetUnitLosState(uid, ally, { los = true, radar = true, prevLos = true, contRadar = true })
			Spring.SetUnitLosMask(uid, ally, { los = true, radar = true, prevLos = true, contRadar = true })
		end

		revealTick = function(f)
			for uid, untilF in pairs(ctl.eyes) do
				if untilF <= f then
					ctl.eyes[uid] = nil
					if alive(uid) then
						Spring.DestroyUnit(uid, false, true)
					end
				end
			end
			local keep = {}
			for _, rv in ipairs(ctl.reveals) do
				if rv.expire > f then
					keep[#keep + 1] = rv
					for _, uid in ipairs(spGetUnitsInCylinder(rv.x, rv.z, rv.r)) do
						revealUnit(uid, rv.ally, f + 20)
					end
				end
			end
			ctl.reveals = keep
			for uid, ms in pairs(marks) do
				for _, mk in pairs(ms) do
					if mk.expire > f and mk.reveal and mk.ally then
						revealUnit(uid, mk.ally, f + 20)
					end
				end
			end
			for uid, per in pairs(ctl.revealed) do
				for ally, until_ in pairs(per) do
					if until_ <= f then
						per[ally] = nil
						if alive(uid) then
							Spring.SetUnitLosMask(uid, ally, 0)
							local h = heroes[uid]
							if h and (h.cloaked or h.hidden) and not h.def.canCloak then
								api.losCloak(uid, true)
							end
						end
					end
				end
				if not next(per) then
					ctl.revealed[uid] = nil
				end
			end
		end

		-- reveal: real line of sight over the area (an invisible, invulnerable sensor unit - legt4skyeye - of a team of
		-- `ally`: ground, units, radar, air) plus the units inside forced visible and decloaked
		local EYE = UnitDefNames.legt4skyeye
		function api.reveal(x, z, r, seconds, ally)
			local f = frameNow()
			ctl.reveals[#ctl.reveals + 1] = { x = x, z = z, r = r, expire = f + floor(seconds * GAME_SPEED), ally = ally }
			local team = ally and Spring.GetTeamList(ally)
			team = team and team[1]
			if EYE and team then
				x, z = clampX(x), clampZ(z)
				local uid = Spring.CreateUnit(EYE.id, x, spGetGroundHeight(x, z), z, 0, team)
				if uid then
					Spring.SetUnitNoDraw(uid, true)
					Spring.SetUnitNoSelect(uid, true)
					Spring.SetUnitNoMinimap(uid, true)
					Spring.SetUnitNeutral(uid, true)
					Spring.SetUnitStealth(uid, true)
					Spring.SetUnitBlocking(uid, false, false, false, false, false, false, false)
					for _, sn in ipairs({ "los", "airLos", "radar" }) do
						Spring.SetUnitSensorRadius(uid, sn, r)
					end
					ctl.eyes[uid] = f + floor(seconds * GAME_SPEED)
				end
			end
			revealTick(f)
		end

		function api.mark(uid, id, seconds, opts)
			if not alive(uid) then
				return 0
			end
			opts = opts or {}
			local f = frameNow()
			marks[uid] = marks[uid] or {}
			local mk = marks[uid][id]
			if not mk or mk.expire <= f then
				mk = { stacks = 0 }
				marks[uid][id] = mk
			end
			mk.stacks = min(opts.max or 1e9, mk.stacks + (opts.stacks or 1))
			mk.expire = f + floor(seconds * GAME_SPEED)
			mk.vuln = opts.vuln or mk.vuln
			mk.from = opts.from or mk.from
			mk.ally = opts.from and spValidUnitID(opts.from) and spGetUnitAllyTeam(opts.from) or mk.ally
			mk.slow = opts.slow or mk.slow
			mk.root = opts.root or mk.root
			mk.reveal = opts.reveal or mk.reveal
			mk.noDash = opts.noDash or mk.noDash
			return mk.stacks
		end

		function api.marks(uid, id)
			local mk = marks[uid] and marks[uid][id]
			if mk and mk.expire > frameNow() then
				return mk.stacks
			end
			return 0
		end

		marksTick = function(f)
			for uid, ms in pairs(marks) do
				for id, mk in pairs(ms) do
					if mk.expire <= f then
						ms[id] = nil
					end
				end
				if not next(ms) then
					marks[uid] = nil
				end
			end
		end

		-- timed buffs of non-hero units: { speed, damage, armor, regen, cloak }
		local function mergeUnitBuffs(uid, f)
			local s = { damage = 0, armor = 0, speed = 0, regen = 0, cloak = false }
			local any = false
			for id, e in pairs(ctl.unitBuffs[uid] or {}) do
				if e.expire > f then
					any = true
					for k in pairs(s) do
						local v = e.mods[k]
						if k == "cloak" then
							s.cloak = s.cloak or (v and true or false)
						elseif type(v) == "number" then
							s[k] = s[k] + v
						end
					end
				else
					ctl.unitBuffs[uid][id] = nil
				end
			end
			if not any then
				ctl.unitBuffs[uid] = nil
			end
			ub.damage[uid] = s.damage ~= 0 and s.damage or nil
			ub.armor[uid] = s.armor ~= 0 and min(0.8, s.armor) or nil
			ub.speed[uid] = s.speed ~= 0 and s.speed or nil
			ub.regen[uid] = s.regen ~= 0 and s.regen or nil
			local was = ub.cloak[uid]
			ub.cloak[uid] = s.cloak or nil
			if (was or false) ~= (s.cloak or false) and alive(uid) then
				local ud = UnitDefs[spGetUnitDefID(uid)]
				if ud and ud.canCloak then
					Spring.SetUnitCloak(uid, s.cloak and 4 or false)
				else
					api.losCloak(uid, s.cloak)
				end
			end
		end

		function api.unitBuff(uid, id, seconds, mods)
			if not alive(uid) or heroes[uid] then
				return false
			end
			ctl.unitBuffs[uid] = ctl.unitBuffs[uid] or {}
			ctl.unitBuffs[uid][id] = { expire = frameNow() + floor((seconds or 1) * GAME_SPEED), mods = mods or {} }
			mergeUnitBuffs(uid, frameNow())
			return true
		end

		local function unitBuffTick(f)
			for uid in pairs(ctl.unitBuffs) do
				mergeUnitBuffs(uid, f)
			end
			if f % 30 == 13 then
				for uid, r in pairs(ub.regen) do
					healUnit(uid, r)
				end
			end
		end

		function api.taunt(victimID, byUnitID, seconds)
			if not alive(victimID) or not alive(byUnitID) or unstoppable(victimID) then
				return false
			end
			if heroes[victimID] then
				seconds = seconds * 0.5
			end
			ctl.taunts[victimID] = { by = byUnitID, expire = frameNow() + floor(seconds * GAME_SPEED) }
			if not structureDefs[spGetUnitDefID(victimID)] then
				Spring.GiveOrderToUnit(victimID, CMD.ATTACK, { byUnitID }, 0)
			end
			Spring.SetUnitTarget(victimID, byUnitID)
			return true
		end

		function api.forceTarget(unitID, targetID, seconds)
			if not alive(unitID) or not alive(targetID) then
				return false
			end
			ctl.forced[unitID] = { target = targetID, expire = frameNow() + floor(seconds * GAME_SPEED) }
			Spring.SetUnitTarget(unitID, targetID)
			return true
		end

		local function targetsTick(f)
			for uid, t in pairs(ctl.taunts) do
				if t.expire <= f or not alive(uid) or not alive(t.by) then
					ctl.taunts[uid] = nil
				else
					Spring.SetUnitTarget(uid, t.by)
				end
			end
			for uid, t in pairs(ctl.forced) do
				if t.expire <= f or not alive(uid) or not alive(t.target) then
					ctl.forced[uid] = nil
				else
					Spring.SetUnitTarget(uid, t.target)
				end
			end
		end

		---------------------------------------------------------------- summons

		local summonGroups = {} -- { owner, name, opts, ids = {uid = true}, max, every, nextAt }

		local function makeSummon(unitID, h, ud, opts, group)
			local x, _, z = spGetUnitPosition(unitID)
			if not x then
				return nil
			end
			local a = random() * 6.283
			local sp = opts.spread or 280
			local sx, sz = clampX(x + math.cos(a) * sp), clampZ(z + math.sin(a) * sp)
			local uid = Spring.CreateUnit(ud.id, sx, spGetGroundHeight(sx, sz), sz, random(0, 3), h.team)
			if not uid then
				return nil
			end
			local f = frameNow()
			local s = { owner = unitID, name = ud.name, leash = opts.leash, guard = opts.guard, group = group,
				credit = opts.credit ~= false, persist = opts.persist,
				scale = opts.scaleWithLevel and (h.power or 1) / (H.ABILITY_POWER_BASE or 1) or nil,
				expire = opts.expire and (f + floor(opts.expire * GAME_SPEED)) or nil }
			summoned[uid] = s
			if group then
				group.ids[uid] = true
			end
			if s.expire then
				spSetUnitRulesParam(uid, "hero_summon_expire", s.expire, ALLIED)
			end
			if opts.build and opts.build > 0 then
				-- "printed": still (stunned) for `build` seconds under the summon effect (a Lua-made nanoframe dies at once)
				s.buildFrom, s.buildFrames = f, floor(opts.build * GAME_SPEED)
				stunUnit(uid, opts.build, nil, nil)
			end
			if not s.guard then
				Spring.GiveOrderToUnit(uid, CMD.GUARD, { unitID }, 0)
			end
			ceg(opts.fx or "hero-summon", sx, spGetGroundHeight(sx, sz), sz)
			return uid
		end

		function api.summon(unitID, h, unitName, count, opts)
			opts = opts or {}
			local ud = UnitDefNames[unitName or ""]
			local ids = {}
			if not ud or not h then
				return ids
			end
			local group
			if opts.respawn then
				-- a group id (opts.group) is reused by a later call: it resizes the group (max, every, opts) instead
				local gid = opts.group or opts.respawn.group
				if gid then
					for _, g in ipairs(summonGroups) do
						if g.owner == unitID and g.id == gid then
							group = g
						end
					end
				end
				if group then
					group.max = opts.respawn.max or count
					group.every = floor((opts.respawn.every or 10) * GAME_SPEED)
					group.opts, group.ud = opts, ud
					local n = 0
					for uid in pairs(group.ids) do
						if alive(uid) then
							n = n + 1
						end
					end
					count = max(0, min(count or 1, group.max - n))
				else
					group = { id = gid, owner = unitID, h = h, ud = ud, opts = opts, ids = {}, max = opts.respawn.max or count,
						every = floor((opts.respawn.every or 10) * GAME_SPEED), nextAt = frameNow() }
					summonGroups[#summonGroups + 1] = group
				end
			end
			local have = 0
			if opts.cap then
				for _, s in pairs(summoned) do
					if s.owner == unitID and s.name == ud.name then
						have = have + 1
					end
				end
			end
			for _ = 1, count or 1 do
				if opts.cap and have >= opts.cap then
					break
				end
				local uid = makeSummon(unitID, h, ud, opts, group)
				if uid then
					ids[#ids + 1] = uid
					have = have + 1
				end
			end
			return ids
		end

		-- a respawn group's size: n (units over it are not killed, just not replaced); returns false without the group
		function api.summonGroupSize(heroID, groupId, n)
			for _, g in ipairs(summonGroups) do
				if g.owner == heroID and g.id == groupId then
					g.max = n
					return true
				end
			end
			return false
		end

		-- every frame: nanoframe summons grow; every 0.5 s: leash, guard, expiry, respawn
		summonTick = function(f, every)
			for uid, s in pairs(summoned) do
				if s.buildFrom then
					if f - s.buildFrom >= s.buildFrames then
						s.buildFrom = nil
					elseif (f - s.buildFrom) % 6 == 0 then
						local x, y, z = spGetUnitPosition(uid)
						ceg("hero-summon", x, y, z)
					end
				end
			end
			if not every then
				return
			end
			for uid, s in pairs(summoned) do
				local ownerAlive = heroes[s.owner] ~= nil
				if not alive(uid) then
					summoned[uid] = nil
				elseif (s.expire and s.expire <= f) or (not ownerAlive and not s.persist) then
					summoned[uid] = nil
					if s.group then
						s.group.ids[uid] = nil
					end
					local x, y, z = spGetUnitPosition(uid)
					ceg("hero-unsummon", x, y, z)
					Spring.DestroyUnit(uid, false, true)
				elseif ownerAlive and not s.buildFrom then
					local ox, _, oz = spGetUnitPosition(s.owner)
					local x, _, z = spGetUnitPosition(uid)
					local far = s.leash and ox and (x - ox) ^ 2 + (z - oz) ^ 2 > s.leash * s.leash
					if far then
						Spring.GiveOrderToUnit(uid, CMD.MOVE, { ox, spGetGroundHeight(ox, oz), oz }, 0)
						Spring.GiveOrderToUnit(uid, CMD.GUARD, { s.owner }, CMD.OPT_SHIFT)
					elseif s.guard then
						local t = api.target(s.guard)
						if t and t ~= s.lastTarget then
							s.lastTarget = t
							Spring.GiveOrderToUnit(uid, CMD.ATTACK, { t }, 0)
						elseif not t and (s.lastTarget or Spring.GetUnitCommandCount(uid) == 0) then
							s.lastTarget = nil
							Spring.GiveOrderToUnit(uid, CMD.GUARD, { s.guard }, 0)
						end
					end
				end
			end
			local keep = {}
			for _, g in ipairs(summonGroups) do
				if heroes[g.owner] then
					keep[#keep + 1] = g
					local n = 0
					for uid in pairs(g.ids) do
						if alive(uid) then
							n = n + 1
						else
							g.ids[uid] = nil
						end
					end
					if n >= g.max then
						g.nextAt = f + g.every
					elseif f >= g.nextAt then
						g.nextAt = f + g.every
						makeSummon(g.owner, g.h, g.ud, g.opts, g)
					end
				end
			end
			summonGroups = keep
		end

		controlTick = function(f)
			moversTick(f)
			if f % 6 == 1 then
				unitBuffTick(f)
			end
			if f % 15 == 2 then
				targetsTick(f)
			end
		end
	end

	---------------------------------------------------------------- the module API (header)

	do
		api.H = H
		api.val = val
		api.GAME_SPEED = GAME_SPEED
		function api.rank(h, key)
			return rankOf(h, key)
		end
		function api.level(h)
			return h.level
		end
		function api.power(h)
			return h.power or 1
		end
		function api.dmgMult(h)
			return h.dmgMult or 1
		end
		api.frame = frameNow
		function api.hero(uid)
			return heroes[uid]
		end
		function api.isHero(uid)
			return heroes[uid] ~= nil
		end
		function api.pos(uid)
			return spGetUnitPosition(uid)
		end
		api.cost = costOf
		function api.damageType(weaponDefID)
			return wdType[copyBase[weaponDefID] or weaponDefID]
		end
		function api.log(fmt, ...)
			alog(fmt, ...)
		end
		api.ceg = ceg
		api.toUI = toUI
		function api.delay(frames, fn)
			local ctx = fxContext()
			delayed[#delayed + 1] = { frame = frameNow() + max(1, floor(frames)), fn = function()
				local prev = fxOwner(ctx)
				local ok, err = pcall(fn)
				fxOwner(prev)
				if not ok then
					Spring.Echo("[t4heroes] api.delay error: " .. tostring(err))
				end
			end }
		end
		setmetatable(api, { __index = function(_, k)
			if k == "fx" then
				return GG.HeroFX
			end
		end })

		api.damage = abilityDamage
		function api.area(x, z, r, dmg, attackerID, opts)
			local ally = opts and opts.ally or (attackerID and spValidUnitID(attackerID) and spGetUnitAllyTeam(attackerID))
			local hit = {}
			for _, uid in ipairs(spGetUnitsInCylinder(x, z, r)) do
				if spGetUnitAllyTeam(uid) ~= ally and not Spring.GetUnitIsDead(uid) and not (opts and opts.noHero and heroes[uid]) then
					hit[#hit + 1] = uid
					if dmg and dmg > 0 then
						abilityDamage(uid, dmg, attackerID, opts)
					end
					if opts and opts.stun then
						stunUnit(uid, opts.stun, attackerID, ally)
					end
				end
			end
			return hit
		end
		function api.line(x1, z1, x2, z2, width, dmg, attackerID, opts)
			local ally = opts and opts.ally or (attackerID and spValidUnitID(attackerID) and spGetUnitAllyTeam(attackerID))
			local dx, dz = x2 - x1, z2 - z1
			local len = max(1, sqrt(dx * dx + dz * dz))
			local hw = max(8, (width or 100) * 0.5)
			local seen, hit = {}, {}
			for s = 0, len + hw, hw do
				local px, pz = x1 + dx / len * min(s, len), z1 + dz / len * min(s, len)
				for _, uid in ipairs(spGetUnitsInCylinder(px, pz, hw * 1.5)) do
					if not seen[uid] then
						seen[uid] = true
						if spGetUnitAllyTeam(uid) ~= ally and not Spring.GetUnitIsDead(uid) then
							local ux, _, uz = spGetUnitPosition(uid)
							local t = max(0, min(1, ((ux - x1) * dx + (uz - z1) * dz) / (len * len)))
							local qx, qz = x1 + dx * t - ux, z1 + dz * t - uz
							if qx * qx + qz * qz <= hw * hw * 1.6 then
								hit[#hit + 1] = uid
								if dmg and dmg > 0 then
									abilityDamage(uid, dmg, attackerID, opts)
								end
								if opts and opts.stun then
									stunUnit(uid, opts.stun, attackerID, ally)
								end
							end
						end
					end
				end
			end
			return hit
		end
		function api.stun(uid, seconds, attackerID)
			local ally = attackerID and spValidUnitID(attackerID) and spGetUnitAllyTeam(attackerID) or nil
			return stunUnit(uid, seconds, attackerID, ally)
		end
		api.heal = healUnit
		api.enemiesIn = enemiesIn
		api.alliesIn = alliesIn
		function api.nearestEnemies(x, z, r, ally, n)
			local list = {}
			for _, uid in ipairs(enemiesIn(x, z, r, ally)) do
				local ux, _, uz = spGetUnitPosition(uid)
				list[#list + 1] = { uid, (ux - x) ^ 2 + (uz - z) ^ 2 }
			end
			table.sort(list, function(a, b) return a[2] < b[2] end)
			local out = {}
			for i = 1, min(n or #list, #list) do
				out[i] = list[i][1]
			end
			return out
		end
		api.seenBy = seenBy

		function api.buff(unitID, h, id, seconds, mods)
			K.addBuff(unitID, h, id, seconds, mods, nil)
		end
		function api.unbuff(unitID, h, id)
			return K.removeBuff(unitID, h, id)
		end
		api.setScale = setScale

		-- fire(h, name, fromX, fromY, fromZ, targetID [, opts]) or fire(h, name, fromX, fromY, fromZ, x, y, z [, opts])
		function api.fire(h, name, fx, fy, fz, a, b, c, d)
			local wdid = h.def.extra[name] or (h.def.keyNum[name] and h.def.weapons[h.def.keyNum[name][1]].wdid)
			if not wdid then
				alog("%s: api.fire - no weapondef %s", h.def.name, tostring(name))
				return nil
			end
			if isStarburst[wdid] then
				alog("%s: api.fire refuses the starburst %s", h.def.name, tostring(name))
				return nil
			end
			local targetID, tx, ty, tz, opts
			if type(a) == "number" and (b == nil or type(b) == "table") then
				targetID, opts = a, b
				tx, ty, tz = spGetUnitPosition(targetID)
				if not tx then
					return nil
				end
				ty = ty + 20
			else
				tx, ty, tz, opts = a, b, c, d
			end
			opts = opts or {}
			local cst = api.caster(h.unitID, h, opts.key or name)
			local wd = WeaponDefs[wdid]
			local shot = opts.dmg and { c = cst, dmg = opts.dmg, aoe = opts.aoe or 100, stun = opts.stun, para = opts.para,
				dtype = opts.dtype, fx = opts.fx, onHit = opts.onHit, expire = frameNow() + 900 } or nil
			if isBeam[wdid] then
				K.boltVisual(cst, wdid, fx, fy, fz, tx, ty, tz, opts.ttl or isBeam[wdid])
				if shot then
					K.shotImpact(shot, tx, tz)
				elseif targetID then
					abilityDamage(targetID, (wd.damages and wd.damages[0] or 0) * (h.dmgMult or 1), h.unitID, { dtype = wdType[wdid] })
				end
				return -1
			end
			local dx, dy, dz = tx - fx, ty - fy, tz - fz
			local dist = max(1, sqrt(dx * dx + dy * dy + dz * dz))
			local speed = max(1, wd.projectilespeed or 10)
			local pid
			if shot then
				pid = K.spawnAb(wdid, cst, fx, fy, fz, dx / dist * speed, dy / dist * speed, dz / dist * speed, opts.gravity, opts.ttl and floor(opts.ttl * GAME_SPEED) or floor(dist / speed) + 120)
				if pid then
					shots[pid] = shot
				end
			else
				projParams.pos[1], projParams.pos[2], projParams.pos[3] = fx, fy, fz
				projParams.speed[1], projParams.speed[2], projParams.speed[3] = dx / dist * speed, dy / dist * speed, dz / dist * speed
				projParams.owner = h.unitID
				projParams.team = h.team
				projParams.gravity = opts.gravity or 0
				projParams.ttl = opts.ttl and floor(opts.ttl * GAME_SPEED) or floor(dist / speed) + 120
				projParams.tracking = targetID
				pid = Spring.SpawnProjectile(wdid, projParams)
				projParams.tracking = nil
			end
			if pid then
				if targetID then
					Spring.SetProjectileTarget(pid, targetID, string.byte("u"))
				else
					Spring.SetProjectileTarget(pid, tx, ty, tz)
				end
			end
			return pid
		end

		function api.swapWeapons(unitID, h, suffix)
			h.swap = suffix
		end

		function api.order(uids, cmd, params, opts)
			if type(uids) == "number" then
				uids = { uids }
			end
			Spring.GiveOrderToUnitArray(uids, cmd, params or {}, opts or 0)
		end

		function api.cooldown(unitID, h, key, seconds)
			K.startCooldown(unitID, h, key, seconds)
		end
		function api.ready(h, key)
			return K.abilityReady(h, key)
		end
		function api.active(unitID, key, seconds)
			K.markActive(unitID, key, seconds)
		end
		function api.toggleOff(unitID, h, key)
			return K.toggleOff(unitID, h, key)
		end
		function api.absorb(unitID, h, amount, seconds)
			local f = frameNow()
			local ab = h.absorb
			if ab and ab.expire > f then
				ab.left = ab.left + amount
				ab.max = max(ab.max or 0, ab.left)
				ab.expire = max(ab.expire, f + floor(seconds * GAME_SPEED))
			else
				h.absorb = { left = amount, max = amount, expire = f + floor(seconds * GAME_SPEED) }
			end
			spSetUnitRulesParam(unitID, "hero_absorb", floor(h.absorb.left), ALLIED)
			spSetUnitRulesParam(unitID, "hero_absorb_max", floor(h.absorb.max), ALLIED)
		end

		function api.target(unitID)
			for n = 1, 6 do
				local tt, _, wt = Spring.GetUnitWeaponTarget(unitID, n)
				if tt == 1 and wt then
					local x, y, z = spGetUnitPosition(wt)
					return wt, x, y, z
				elseif tt == 2 and type(wt) == "table" then
					return nil, wt[1], wt[2], wt[3]
				end
			end
			local cmds = Spring.GetUnitCommands(unitID, 1)
			local c = cmds and cmds[1]
			if c and c.id == CMD.ATTACK then
				if #c.params == 1 and alive(c.params[1]) then
					local x, y, z = spGetUnitPosition(c.params[1])
					return c.params[1], x, y, z
				elseif #c.params >= 3 then
					return nil, c.params[1], c.params[2], c.params[3]
				end
			end
			return nil
		end
		function api.weaponNum(h, key)
			if type(key) == "number" then
				return key
			end
			return h.def.keyNum[key] and h.def.keyNum[key][1]
		end
		function api.reloadNow(unitID, weapon)
			local h = heroes[unitID]
			local n = h and api.weaponNum(h, weapon) or tonumber(weapon)
			if n then
				Spring.SetUnitWeaponState(unitID, n, "reloadState", frameNow())
			end
		end
		function api.disableWeapon(unitID, h, key, off)
			h.disabled[key] = (off ~= false) or nil
			applyStats(unitID, h)
		end
		function api.piecePos(unitID, pieceName)
			local map = Spring.GetUnitPieceMap(unitID)
			local p = map and map[pieceName]
			if not p then
				return spGetUnitPosition(unitID)
			end
			local x, y, z = Spring.GetUnitPiecePosDir(unitID, p)
			return x, y, z
		end

		-- consume: destroy a unit without wreck / death explosion; opts.credit = heroID gets the kill (XP); never a
		-- commander, an altar or a hero. Returns { maxHp, cost, unitDefID } of the eaten unit
		function api.consume(uid, opts)
			if not alive(uid) then
				return nil
			end
			local udid = spGetUnitDefID(uid)
			if not udid or commanderDefs[udid] or foundryDefs[udid] or heroDefs[udid] then
				return nil
			end
			local _, maxHp = spGetUnitHealth(uid)
			consumed[uid] = { credit = opts and opts.credit }
			local x, y, z = spGetUnitPosition(uid)
			Spring.DestroyUnit(uid, false, true, opts and opts.credit or nil)
			return { maxHp = maxHp or 0, cost = unitCost[udid] or 0, unitDefID = udid, x = x, y = y, z = z }
		end

		-- intercept: enemy shells and missiles heading into the circle are deleted (not beams, lightning, flames, nukes)
		local interceptable = {}
		for wdid, wd in pairs(WeaponDefs) do
			local t = wd.type
			if (t == "Cannon" or t == "MissileLauncher" or t == "AircraftBomb" or t == "TorpedoLauncher")
				and not (wd.customParams and (wd.customParams.nuclear or wd.customParams.t4_ability)) and (wd.damageAreaOfEffect or 0) < 700 then
				interceptable[wdid] = true
			end
		end
		function api.intercept(x, z, r, ally, maxCount)
			local n = 0
			for _, p in ipairs(Spring.GetProjectilesInRectangle(x - r * 2, z - r * 2, x + r * 2, z + r * 2, false, false) or {}) do
				if maxCount and n >= maxCount then
					break
				end
				local wdid = Spring.GetProjectileDefID(p)
				if wdid and interceptable[wdid] then
					local team = Spring.GetProjectileTeamID(p)
					local pAlly = team and select(6, Spring.GetTeamInfo(team, false))
					if pAlly and pAlly ~= ally then
						local px, py, pz = Spring.GetProjectilePosition(p)
						local inside = px and (px - x) ^ 2 + (pz - z) ^ 2 <= r * r
						if not inside and px then
							local _, target = Spring.GetProjectileTarget(p)
							local tx, tz
							if type(target) == "table" then
								tx, tz = target[1], target[3]
							elseif type(target) == "number" then
								tx, _, tz = spGetUnitPosition(target)
							end
							inside = tx and (tx - x) ^ 2 + (tz - z) ^ 2 <= r * r
						end
						if inside then
							Spring.DeleteProjectile(p)
							ceg("hero-zap", px, py, pz)
							n = n + 1
						end
					end
				end
			end
			return n
		end

		function api.shieldDrain(uid)
			local ud = UnitDefs[spGetUnitDefID(uid) or -1]
			if not ud then
				return 0
			end
			local drained = 0
			for n, w in ipairs(ud.weapons or {}) do
				local wd = WeaponDefs[w.weaponDef]
				if wd and wd.type == "Shield" then
					local _, power = Spring.GetUnitShieldState(uid, n)
					if power and power > 0 then
						drained = drained + power
						Spring.SetUnitShieldState(uid, n, true, 0)
					end
				end
			end
			return drained
		end

		function api.cast(unitID, h, b, r, tx, tz, targetID)
			return cast[b.kind] and cast[b.kind](unitID, h, b.key or "item", b, r or 1, tx, tz, targetID) or false
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
		K.abilityPassivesBegin()
		local healBest = {}
		for unitID, h in pairs(heroes) do
			local x, y, z = heroPos(unitID)
			if x then
				local ally = spGetUnitAllyTeam(unitID)
				local hp, maxHp = spGetUnitHealth(unitID)
				K.abilityBuffTick(unitID, h, f, x, y, z)
				-- own regeneration: Vitality and the rest + the fountain at its altar + rest out of combat
				local regen = h.regen or 0
				if fountainNear(h.team, x, z) then
					regen = regen + H.FOUNTAIN_REGEN
				end
				if f - (h.lastHit or 0) > H.REST_DELAY * GAME_SPEED then
					regen = regen + H.REST_REGEN
				end
				if regen > 0 and hp and hp < maxHp and (h.downedUntil or 0) <= f then
					Spring.SetUnitHealth(unitID, min(maxHp, hp + maxHp * regen))
				end
				K.abilityAuras(unitID, h, f, x, y, z, ally, healBest)
				K.abilityShield(unitID, h)
				-- income (items)
				local inc = h.mods and h.mods.income or 0
				if inc > 0 then
					Spring.AddTeamResource(h.team, "metal", inc)
				end
				-- the engine's own experience would stack reload speed and health on the hero levels
				if (Spring.GetUnitExperience(unitID) or 0) > 0 then
					Spring.SetUnitExperience(unitID, 0)
				end
			end
		end
		for uid, rate in pairs(healBest) do
			healUnit(uid, rate)
		end
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
		api.bestCluster = bestCluster

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
		api.mostValuableEnemy = mostValuableEnemy

		local function enemyCostNear(x, z, r, ally)
			local sum, n = 0, 0
			for _, uid in ipairs(enemiesIn(x, z, r, ally)) do
				sum = sum + costOf(uid)
				n = n + 1
			end
			return sum, n
		end
		api.enemyCostNear = enemyCostNear

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
		function api.weaponReach(h)
			return weaponReach(h) * (1 + (h.mods and h.mods.range or 0))
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
			h.escaping = escaping
			local cfg = h.def.cfg
			for _, key in ipairs({ "ult", "a1", "a2", "a3" }) do
				local b = cfg[key]
				if b and not b.passive and K.abilityReady(h, key) and not movers[unitID] and not (b.toggle and h.toggled[key]) then
					local r = rankOf(h, key)
					local k = b.kind
					local worth = key == "ult" and AUTO_ULT or AUTO_MIN
					if k == "custom" then
						local tx, ty, tz, target = modHook(h, "autocast", api, unitID, h, key, r)
						if tx then
							K.tryCast(unitID, h, key, tonumber(tx) and tx or x, tz or z, target, ty)
						end
					elseif k == "active_guard" or k == "active_dome" then
						local near = enemyCostNear(x, z, 1100, ally)
						if near > max(AUTO_MIN, h.def.cost * 0.3) or (hpFrac < 0.5 and near > 0) then
							K.tryCast(unitID, h, key)
						end
					elseif k == "active_nova" then
						local rad = val(b.radius, r)
						local near = enemyCostNear(x, z, rad, ally)
						local heal = val(b.heal, r) or 0
						if near > worth or (heal > 0 and (near > 0 or hpFrac < 0.6) and alliedDamage(x, z, rad, ally) > heal * 3) then
							K.tryCast(unitID, h, key)
						end
					elseif k == "active_bladestorm" then
						if enemyCostNear(x, z, val(b.radius, r), ally) > worth then
							K.tryCast(unitID, h, key)
						end
					elseif k == "active_buff" then
						local bf = b.buff or {}
						local reach = weaponReach(h)
						if bf.immobile then
							if enemyCostNear(x, z, reach, ally) > AUTO_MIN then
								K.tryCast(unitID, h, key)
							end
						elseif bf.speed and not bf.damage and not bf.armor then
							if escaping or Spring.GetUnitNearestEnemy(unitID, reach * 1.5, true) then
								K.tryCast(unitID, h, key)
							end
						elseif Spring.GetUnitNearestEnemy(unitID, reach, true) then
							K.tryCast(unitID, h, key)
						end
					elseif k == "active_barrage" or k == "active_beam" then
						local score, tx, tz = bestCluster(x, z, K.castRange(b, r), val(b.radius, r) or 500, ally)
						if tx and score > worth then
							K.tryCast(unitID, h, key, tx, tz)
						end
					elseif k == "active_spear" then
						local target, value = mostValuableEnemy(x, z, K.castRange(b, r), ally)
						if target and value >= 3000 then
							K.tryCast(unitID, h, key, nil, nil, target)
						end
					elseif k == "active_dash" then
						local range = val(b.range, r)
						if escaping then
							local e = Spring.GetUnitNearestEnemy(unitID, 1500, true)
							local ex, _, ez = e and spGetUnitPosition(e)
							if ex then
								local dx, dz = x - ex, z - ez
								local d = max(1, sqrt(dx * dx + dz * dz))
								K.tryCast(unitID, h, key, x + dx / d * range, z + dz / d * range)
							end
						elseif hpFrac > 0.45 then
							local score, tx, tz = bestCluster(x, z, range, max(300, (val(b.radius, r) or 200) * 2), ally)
							if tx and score > AUTO_MIN and (tx - x) ^ 2 + (tz - z) ^ 2 > 250 * 250 then
								K.tryCast(unitID, h, key, tx, tz)
							end
						end
					elseif k == "active_summon" then
						if enemyCostNear(x, z, max(1400, weaponReach(h)), ally) > AUTO_MIN then
							K.tryCast(unitID, h, key)
						end
					elseif k == "active_missiles" then
						if enemyCostNear(x, z, val(b.radius, r), ally) > AUTO_MIN * 0.5 then
							K.tryCast(unitID, h, key)
						end
					elseif k == "active_repair" then
						local heal = val(b.heal, r) * (h.power or 1)
						if alliedDamage(x, z, val(b.radius, r), ally) > heal * 3 or hpFrac < 0.5 then
							K.tryCast(unitID, h, key)
						end
					elseif k == "active_cloak" then
						if escaping then
							K.tryCast(unitID, h, key)
						end
					elseif k == "active_shield" then
						if underFire and hpFrac < 0.9 and enemyCostNear(x, z, 1600, ally) > 0 then
							K.tryCast(unitID, h, key)
						end
					end
				end
			end
		end
	end

	---------------------------------------------------------------- AI heroes
	-- The skirmish AI never sent its heroes into its attack groups, so the gadget drives them: the AI is told to let go
	-- of a hero ("detach", misc/aicmdr.as), the hero marches with the strongest group of its army, keeps its role's
	-- place in it, and falls back to the fountain when hurt or outnumbered. Every AI hero takes an escort of army
	-- units from the AI (detach, given back with attach). infolog: "[heroai] ..." lines.
	local aiHero, aiEconomy, aiMakers, aiSummary, aiEscortsTick
	local escorts = {} -- heroID -> { units = { uid = true }, n }
	local bank = {}    -- teamID -> metal the AI put aside for ranks, levels and altar upgrades
	local ebank = {}   -- teamID -> energy the AI put aside for altar upgrades
	do -- a block: its helpers do not count toward the chunk's limit of 200 locals
		local visibleTo = seenBy

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

	-- units that build heroes (altars): hero unitDefIDs in build order
	local heroMakers = {}
	for udid, ud in pairs(UnitDefs) do
		for _, opt in ipairs(ud.buildOptions or {}) do
			if heroDefs[opt] then
				heroMakers[udid] = heroMakers[udid] or {}
				heroMakers[udid][#heroMakers[udid] + 1] = opt
			end
		end
	end
	-- these the AI script builds with (Factory::AiMakeTask, hero_next); the gadget runs every other hero producer
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
	local armyCache = {} -- teamID -> { frame, x, z, cost }
	local function armyGroup(teamID, f)
		local c = armyCache[teamID]
		if c and f - c.frame < 55 then
			return c
		end
		local cells = {}
		for _, uid in ipairs(Spring.GetTeamUnits(teamID)) do
			local udid = spGetUnitDefID(uid)
			if armyDefs[udid] and not escortOf[uid] and not summoned[uid] then
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

	-- enemy metal around vs allied metal around (enemy heroes at their grown strength, static defence x1.5, unarmed
	-- x0.1, only what the team can see or what shot the hero within 3 s). Returns the ratio, the enemy centre, foes.
	local function danger(unitID, h, x, z)
		local ally = spGetUnitAllyTeam(unitID)
		local shooters = h.attackers or {}
		local f = frameNow()
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
			elseif not Spring.GetUnitIsDead(uid) and (visibleTo(uid, ally) or f - (shooters[uid] or -999) < 90) then
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
		local projs = Spring.GetProjectilesInRectangle(x - 3000, z - 3000, x + 3000, z + 3000, false, false)
		for _, p in ipairs(projs or {}) do
			local aoe = bigShot[Spring.GetProjectileDefID(p) or -1]
			if aoe then
				local team = Spring.GetProjectileTeamID(p)
				local pAlly = team and select(6, Spring.GetTeamInfo(team, false))
				if pAlly and pAlly ~= ally then
					local tx, tz
					local ttype, target = Spring.GetProjectileTarget(p)
					if type(target) == "table" and target[1] and target[1] > 0 and target[3] > 0 then
						tx, tz = target[1], target[3]
					elseif type(target) == "number" and ttype == string.byte("u") then
						tx, _, tz = spGetUnitPosition(target)
					end
					local r2 = (aoe + 200) ^ 2
					if tx and (tx - x) ^ 2 + (tz - z) ^ 2 < r2 then
						return tx, tz, aoe
					end
					local px, _, pz = Spring.GetProjectilePosition(p)
					if px and (px - x) ^ 2 + (pz - z) ^ 2 < r2 then
						return px, pz, aoe
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
				if alive(uid) and Spring.GetUnitTeam(uid) == teamID then
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
			if not alive(uid) or Spring.GetUnitTeam(uid) ~= h.team then
				e.units[uid] = nil
				e.n = e.n - 1
				escortOf[uid] = nil
			else
				cost = cost + costOf(uid)
			end
		end
		local want = min(h.def.cost * H.AI_ESCORT_COST, max(g.cost * H.AI_ESCORT_GROUP, h.def.cost * 0.15))
		if e.n >= H.AI_ESCORT_MAX or (e.n >= H.AI_ESCORT_MIN and cost >= want) then
			return
		end
		local taken = GG.AICommanderUnits or {}
		local doctrine = GG.AIDoctrine and GG.AIDoctrine.owns or {} -- units of the AI's planned armies (ai_doctrine.lua)
		local cands = {}
		for _, uid in ipairs(spGetUnitsInCylinder(x, z, H.AI_ESCORT_RADIUS, h.team)) do
			local udid = spGetUnitDefID(uid)
			if armyDefs[udid] and not escortOf[uid] and not heroes[uid] and not taken[uid] and not doctrine[uid]
				and not summoned[uid] and not Spring.GetUnitTransporter(uid) then
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
			if #ids >= 3 or #ids == e.n then
				aiLog(f, h.team, "%s escort +%d -> %d units (%d metal)", h.def.name, #ids, e.n, cost)
			end
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
		local focus, fd
		for att, fr in pairs(h.attackers or {}) do
			if f - fr > 90 or not alive(att) then
				h.attackers[att] = nil
			elseif visibleTo(att, ally) then
				local ax, _, az = spGetUnitPosition(att)
				local d = ax and (ax - x) ^ 2 + (az - z) ^ 2
				if d and d < 1400 * 1400 and (not fd or d < fd) then
					focus, fd = att, d
				end
			end
		end
		if h.focusHero and alive(h.focusHero) then
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
					local lat = (i - (n + 1) / 2) * 70
					sx, sz = x + dx * 250 + px * lat, z + dz * 250 + pz * lat
				else
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
		h.retreatStart = f
		h.retreatX, h.retreatZ = rx, rz
		h.threatX, h.threatZ = ex, ez
		h.focusHero = nil
		orderMove(unitID, h, CMD.MOVE, rx, rz, f)
		spSetUnitRulesParam(unitID, "hero_retreat", 1, ALLIED)
		-- cover the way back (the kit's defensive actives; a module's autocast sees h.retreating)
		for _, key in ipairs(H.abilityKeys) do
			local b = h.def.cfg[key]
			if b and (b.kind == "active_guard" or b.kind == "active_dome" or b.kind == "active_shield" or b.kind == "active_cloak"
				or (b.kind == "active_buff" and b.buff and (b.buff.speed or b.buff.armor or b.buff.cloak))) then
				K.tryCast(unitID, h, key)
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
		if not hp or movers[unitID] then
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
			local ratio, ex, ez = danger(unitID, h, x, z)
			ex, ez = ex or h.threatX, ez or h.threatZ
			if ex then
				local dx, dz = unitDir(x, z, ex, ez)
				escortOrders(unitID, h, x, z, "cover", dx, dz, f)
			end
			if home < 700 * 700 and ratio < 0.5 and escorts[unitID] then
				escortRelease(unitID, h.team, "hero is home", f)
			end
			if frac >= back and f - (h.retreatStart or 0) > 8 * GAME_SPEED and ratio < 1 then
				h.retreating = false
				spSetUnitRulesParam(unitID, "hero_retreat", 0, ALLIED)
				aiLog(f, h.team, "%s back in the fight at %d%% hp", h.def.name, floor(frac * 100))
			elseif f - (h.lastOrder or 0) > 5 * GAME_SPEED and home > 400 * 400
				and Spring.GetUnitCommandCount(unitID) == 0 then
				orderMove(unitID, h, CMD.MOVE, h.retreatX, h.retreatZ, f)
			end
			return
		end
		local ratio, ex, ez, foes = danger(unitID, h, x, z)
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
		local g = armyGroup(h.team, f)
		local dg = GG.AIDoctrine and GG.AIDoctrine.heroArmy and GG.AIDoctrine.heroArmy(h.team, unitID, h.def.name)
		if dg then
			g = dg
		end
		local e = escorts[unitID]
		local escortCost = 0
		if e then
			for uid in pairs(e.units) do
				escortCost = escortCost + costOf(uid)
			end
		end
		local tx, tz
		local dx, dz = 0, 0
		if not g.x and escortCost > 0 then
			local ecx, ecz = escortCentre(unitID)
			g = { x = ecx, z = ecz, cost = 0, ex = g.ex, ez = g.ez }
		end
		local need = min(h.def.cost * 0.25, H.AI_ESCORT)
		if escortCost > 0 then
			need = need * 0.5
		end
		if g.x and g.cost + escortCost >= need then
			local off = H.AI_ROLE_OFFSET[h.def.cfg.aiRole or "center"] or 0
			tx, tz = g.x, g.z
			if g.ex then
				dx, dz = unitDir(g.x, g.z, g.ex, g.ez)
			end
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
			tx, tz = retreatPoint(h.team, x, z)
			if escorts[unitID] then
				escortRelease(unitID, h.team, "no army to march with", f)
			end
		end
		if not tx then
			return
		end
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
		local cx, cz = escortCentre(unitID)
		if cx and (dx ~= 0 or dz ~= 0) then
			local lead = (tx - cx) * dx + (tz - cz) * dz
			if lead > H.AI_FRONT_LEAD * 0.7 then
				tx, tz = tx - dx * (lead - H.AI_FRONT_LEAD * 0.7), tz - dz * (lead - H.AI_FRONT_LEAD * 0.7)
			end
			local ahead = (x - cx) * dx + (z - cz) * dz
			if ahead > H.AI_FRONT_LEAD and not h.focusHero then
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

	---------------------------------------------------------------- AI economy: hero producers, ranks, levels, altar upgrades
	do

		-- hero producers the AI script does not drive (none in v19): one of each hero that fits the slots
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
								for _, hid in ipairs(heroMakers[udid]) do
									local ok, why = canStartHero(teamID, heroDefs[hid].name)
									if ok then
										toAI(teamID, "detach " .. m)
										Spring.GiveOrderToUnit(m, -hid, {}, 0)
										aiLog(f, teamID, "%s %s %s", UnitDefs[udid].name, why == "revive" and "revives" or "builds", heroDefs[hid].name)
										stat(teamID, why == "revive" and "revives" or "built")
										break
									end
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

		-- the next altar upgrade an AI team wants: every slot in use, a finished altar, nothing researching
		local function upgradeWanted(teamID)
			local slots = teamSlots[teamID] or 1
			local up = H.SLOT_UPGRADES[slots]
			if not up or research[teamID] or slotsUsed(teamID) < slots then
				return nil
			end
			for altarID, t in pairs(altars) do
				if t == teamID and alive(altarID) then
					return up, altarID
				end
			end
		end

		local reviveLog = {}
		local ROLE_WEIGHT = { front = 1.2, center = 1.0, back = 0.7 }

		-- The AI's hero bank: storage is small (the AI builds no storage), so the price of a rank, a level or an altar
		-- upgrade (100k metal + 1M energy) is put aside over time - only overflow (storage fuller than AI_BUY_FULL), at
		-- most AI_BUY_SAVE of the income (v22: the whole leveling budget - ranks too are paid only from the bank), only up
		-- to what the next purchase needs, nothing while a dead hero waits for its revive. Order: unspent points (learnAI), then the altar upgrade, then a level of the best hero.
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
					local up, upAltar = upgradeWanted(teamID)
					if #mine > 0 or revive or up or (bank[teamID] or 0) > 0 or (ebank[teamID] or 0) > 0 then
						local cur, stor, _, inc = Spring.GetTeamResources(teamID, "metal")
						local ecur, estor, _, einc = Spring.GetTeamResources(teamID, "energy")
						cur, stor, inc = cur or 0, stor or 0, inc or 0
						ecur, estor, einc = ecur or 0, estor or 0, einc or 0
						local b = bank[teamID] or 0
						local eb = ebank[teamID] or 0
						local need, eneed = 0, 0
						local buyer, buyPrice
						local saving = false
						if not revive and #mine > 0 then
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
							-- unspent points: ranks paid from the bank; a rank that waits only for metal is saved for
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
									if h.level - #h.picks > 0 then
										local wait = aiWaitCost(h)
										if wait then
											saving = true
											need = max(need, wait)
										end
									end
									prepaid = 0
								end
							end
							if not saving and up then
								need = max(need, up.metal)
								eneed = up.energy
								if b >= up.metal and eb >= up.energy then
									if startResearch(teamID, upAltar, true) then
										b = b - up.metal
										eb = eb - up.energy
										aiLog(f, teamID, "researches %s at the altar (bank left %d metal, %d energy)", up.name, b, eb)
										stat(teamID, "upgrades")
										need, eneed = 0, 0
									end
								end
							elseif not saving then
								for _, o in ipairs(order) do
									local h = o.h
									if h.level < H.AI_BUY_MAX_LEVEL then
										buyer = o
										buyPrice = H.aiLevelPrice(h.def.name, h.level, h.def.cost)
										need = max(need, buyPrice or 0)
										break
									end
								end
							end
						end
						if not revive and need > 0 and b < need * 1.2 and inc >= H.AI_BUY_INCOME and cur > stor * H.AI_BUY_FULL then
							local take = min(inc * H.AI_BUY_SAVE, cur - stor * H.AI_BUY_FULL, need * 1.2 - b)
							if take > 0 and Spring.UseTeamResource(teamID, "metal", take) then
								b = b + take
								stat(teamID, "saved", take)
							end
						elseif b > need * 1.5 then
							local back = min(b - need * 1.5, max(0, stor - cur), max(3000, b * 0.1))
							if back > 0 then
								Spring.AddTeamResource(teamID, "metal", back)
								b = b - back
								stat(teamID, "returned", back)
								if f - (reviveLog[teamID] or -9999) > 1800 then
									reviveLog[teamID] = f
									aiLog(f, teamID, "bank %d > needed %d%s: %d metal back to storage", b + back, need,
										revive and (" (" .. revive .. " waits for its revive)") or "", back)
								end
							end
						end
						-- energy for the altar upgrade: overflow only
						if not revive and eneed > 0 and eb < eneed and ecur > estor * 0.4 then
							local take = min(max(einc, 0) * 0.6, ecur - estor * 0.4, eneed - eb)
							if take > 0 and Spring.UseTeamResource(teamID, "energy", take) then
								eb = eb + take
							end
						elseif eneed == 0 and eb > 0 then
							local back = min(eb, max(0, estor - ecur))
							if back > 0 then
								Spring.AddTeamResource(teamID, "energy", back)
								eb = eb - back
							end
						end
						local h = buyer and buyer.h
						if h and buyPrice and b >= buyPrice and f >= (h.buyReady or 0) then
							b = b - buyPrice
							local from = h.level
							buyLevel(buyer.uid, h, true)
							aiLog(f, teamID, "%s buys level %d -> %d for %d metal (bank left %d, income %d, bought %d of %d levels)",
								h.def.name, from, h.level, buyPrice, b, inc, h.bought or 0, h.level - 1)
							stat(teamID, "levels")
							stat(teamID, "levelMetal", buyPrice)
						end
						bank[teamID] = b
						ebank[teamID] = eb
						Spring.SetTeamRulesParam(teamID, "hero_ai_bank", floor(b), ALLIED)
						Spring.SetTeamRulesParam(teamID, "hero_ai_ebank", floor(eb), ALLIED)
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
							local rk = {}
							for _, key in ipairs(h.def.keys) do
								if rankOf(h, key) > 0 then
									rk[#rk + 1] = key .. rankOf(h, key)
								end
							end
							parts[#parts + 1] = string.format("%s L%d [%s] (%d bought) %d%% %s esc=%d", h.def.name, h.level, table.concat(rk, " "), h.bought or 0, floor(100 * (hp or 0) / max(1, maxHp or 1)),
								h.retreating and "retreat" or (h.focusHero and "hunt" or "march"), e and e.n or 0)
						end
					end
					local s = aiStats[teamID] or {}
					if #parts > 0 or next(s) then
						local cur, stor, _, inc = Spring.GetTeamResources(teamID, "metal")
						aiLog(f, teamID, "summary slots=%d/%d bank=%d ebank=%d metal=%d/%d income=%d saved=%d returned=%d levels=%d (%d metal) ranks=%d upgrades=%d escorted=%d released=%d retreats=%d hunts=%d avoids=%d dodges=%d | %s",
							slotsUsed(teamID), teamSlots[teamID] or 1, bank[teamID] or 0, ebank[teamID] or 0, cur or 0, stor or 0, inc or 0, s.saved or 0, s.returned or 0,
							s.levels or 0, s.levelMetal or 0, s.ranks or 0, s.upgrades or 0, s.escorted or 0, s.released or 0, s.retreats or 0,
							s.hunts or 0, s.avoids or 0, s.dodges or 0, table.concat(parts, "; "))
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
						team = team or Spring.GetUnitTeam(uid)
					end
					if team then
						escortRelease(heroID, team, "hero fell", f)
					end
					escorts[heroID] = nil
				end
			end
		end
	end
	end -- AI heroes

	---------------------------------------------------------------- frames
	do

		-- every frame: shots / reload of heroes whose module wants `fired`
		local function heroFrameTick(f)
			for unitID, h in pairs(heroes) do
				local mod = h.def.mod
				if mod and mod.fired then
					h.lastReload = h.lastReload or {}
					for n in pairs(h.def.weapons) do
						local rs = Spring.GetUnitWeaponState(unitID, n, "reloadState")
						if rs and rs > (h.lastReload[n] or 0) and rs > f then
							if h.lastReload[n] then
								modHook(h, "fired", api, unitID, h, n)
							end
							h.lastReload[n] = rs
						end
					end
				end
			end
		end

		function gadget:GameFrame(f)
			if #delayed > 0 then
				local keep = {}
				local now = delayed
				delayed = {}
				for _, d in ipairs(now) do
					if d.frame <= f then
						d.fn()
					else
						keep[#keep + 1] = d
					end
				end
				for _, d in ipairs(delayed) do
					keep[#keep + 1] = d
				end
				delayed = keep
			end
			K.abilityFrame(f)
			controlTick(f)
			summonTick(f, f % 15 == 4)
			-- AI heroes' escorts, bank, altar upgrades; also with no hero on the field yet
			if f % 30 == 17 then
				aiEscortsTick(f)
				aiEconomy(f)
				researchTick(f)
				if f % 150 == 17 then
					aiMakers(f)
					for teamID in pairs(isAITeam) do
						refreshAltars(teamID)
					end
				end
				if f % 3600 == 17 then
					aiSummary(f)
				end
			end
			if f % 15 == 9 then
				revealTick(f)
			end
			if next(heroes) == nil and #events == 0 then
				return
			end
			heroFrameTick(f)
			if f % 3 == 0 then
				local I = GG.T4HeroItems
				for unitID, h in pairs(heroes) do
					if h.def.mod and h.def.mod.frame then
						modHook(h, "frame", api, unitID, h, f)
					end
					if I and I.frame then
						itemHook("frame", unitID, h, f, api)
					end
				end
			end
			if f % 6 == 3 then
				K.processEvents(f)
				pierceTick(f)
			if f % 300 == 3 then
				slugTick(f)
			end
				speedTick(f)
				marksTick(f)
			end
			if f % 15 == 7 then
				K.refreshProtection(f)
			end
			if f % 30 == 13 then
				passives(f)
				for unitID, h in pairs(heroes) do
					if isAITeam[h.team] then
						aiHero(unitID, h, f)
					end
					if h.autocast or isAITeam[h.team] then
						autocast(unitID, h)
					end
					if isAITeam[h.team] and f % 300 == 13 and h.level - #h.picks > 0 then
						learnAI(unitID, h)
					end
					publish(unitID, h)
				end
			end
		end

		-- unitDied hooks: any death within 1500 of a hero whose module wants it
		local DIED_RADIUS2 = 1500 * 1500
		local baseUnitDestroyed = gadget.UnitDestroyed
		function gadget:UnitDestroyed(unitID, unitDefID, teamID, attackerID, ...)
			local x, _, z = spGetUnitPosition(unitID)
			if x then
				local ally = spGetUnitAllyTeam(unitID)
				for hid, h in pairs(heroes) do
					if hid ~= unitID and h.def.mod and h.def.mod.unitDied then
						local hx, _, hz = spGetUnitPosition(hid)
						if hx and (hx - x) ^ 2 + (hz - z) ^ 2 <= DIED_RADIUS2 then
							modHook(h, "unitDied", api, hid, h, unitID, unitDefID, x, z, ally == h.ally)
						end
					end
				end
			end
			return baseUnitDestroyed(self, unitID, unitDefID, teamID, attackerID, ...)
		end

	end

	---------------------------------------------------------------- commands and UI messages

	local function orderTarget(cmdParams)
		if #cmdParams == 1 then
			local tx, ty, tz = spGetUnitPosition(cmdParams[1])
			return tx, tz, cmdParams[1], ty
		elseif #cmdParams >= 3 then
			return cmdParams[1], cmdParams[3], nil, cmdParams[2]
		end
	end

	function gadget:AllowCommand(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions, cmdTag, playerID, fromSynced, fromLua)
		if cmdID < 0 then
			-- a hero from an altar: only into a free slot (a revive always); removing it from the queue is fine
			local def = heroDefs[-cmdID]
			if def and altars[unitID] and not (cmdOptions and cmdOptions.right) then
				local ok = canStartHero(teamID, def.name, queuedHeroes(unitID))
				if not ok then
					toUI("slotsfull", unitID, teamSlots[teamID] or 1)
					return false
				end
				delayed[#delayed + 1] = { frame = frameNow() + 1, fn = function() refreshAltars(teamID) end }
			end
			return true
		end
		if cmdID == CMD_ALTAR_UPGRADE then
			if altars[unitID] then
				startResearch(teamID, unitID)
			end
			return false
		end
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
		if b.toggle and h.toggled[key] then
			K.tryCast(unitID, h, key)
			return false
		end
		if not K.abilityReady(h, key) then
			return false
		end
		if not b.target then
			K.tryCast(unitID, h, key)
			return false
		end
		local tx, tz, targetID, ty = orderTarget(cmdParams)
		if not tx then
			return false
		end
		local x, _, z = heroPos(unitID)
		local r = rankOf(h, key)
		if (tx - x) ^ 2 + (tz - z) ^ 2 <= K.castRange(b, r) ^ 2 then
			K.tryCast(unitID, h, key, tx, tz, targetID, ty)
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
		if not K.abilityReady(h, key) then
			return true, true
		end
		local b = h.def.cfg[key]
		local tx, tz, targetID, ty = orderTarget(cmdParams)
		if not tx then
			return true, true
		end
		local x, _, z = heroPos(unitID)
		local range = K.castRange(b, rankOf(h, key))
		if (tx - x) ^ 2 + (tz - z) ^ 2 <= range ^ 2 then
			-- cast next frame: a cast orders the hero itself (dash/blink STOP, MOVE, ATTACK) and an order here clears the
			-- queue under the engine, whose FinishCommand then pops the empty deque (corrupt queue -> the owner's client
			-- crashed drawing the selected hero's commands, CommandDrawer::DrawMobileCAICommands; v22)
			delayed[#delayed + 1] = { frame = frameNow() + 1, fn = function()
				if heroes[unitID] == h then
					K.tryCast(unitID, h, key, tx, tz, targetID, ty)
				end
			end }
			return true, true
		end
		Spring.SetUnitMoveGoal(unitID, tx, spGetGroundHeight(tx, tz), tz, range * 0.9)
		return true, false
	end

	function gadget:RecvLuaMsg(msg, playerID)
		if msg:sub(1, 7) ~= "t4hero:" then
			return
		end
		local what, uid, key = msg:match("^t4hero:(%a+):(%d+):?([%w_]*)$")
		if what ~= "learn" and what ~= "buylevel" and what ~= "altar" then
			return -- not ours (items)
		end
		local _, _, spec, teamID = Spring.GetPlayerInfo(playerID, false)
		if spec then
			return true
		end
		uid = tonumber(uid)
		if what == "altar" then
			if uid and altars[uid] and Spring.GetUnitTeam(uid) == teamID then
				startResearch(teamID, uid)
			end
			return true
		end
		local h = uid and heroes[uid]
		if not h or Spring.GetUnitTeam(uid) ~= teamID then
			return true
		end
		if what == "learn" then
			learn(uid, h, key)
		elseif what == "buylevel" then
			buyLevel(uid, h)
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
		gadgetHandler:RegisterCMDID(CMD_ALTAR_UPGRADE)
		gadgetHandler:RegisterAllowCommand(CMD_ALTAR_UPGRADE)
		gadgetHandler:RegisterAllowCommand(CMD.BUILD)
		for wdid in pairs(projWatch) do
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
			publishSlots(teamID)
		end
		-- /luarules reload: pick up altars and heroes already on the field (heroes at level 1)
		for _, uid in ipairs(Spring.GetAllUnits()) do
			local udid = spGetUnitDefID(uid)
			local _, _, _, _, bp = spGetUnitHealth(uid)
			if (heroDefs[udid] or foundryDefs[udid]) and bp and bp >= 1 then
				gadget:UnitFinished(uid, udid, Spring.GetUnitTeam(uid))
			end
		end
		GG.T4Heroes = {
			H = H, api = api, heroes = heroes, dead = dead, escorts = escorts, bank = bank,
			learn = function(uid, key) local h = heroes[uid]; return h and learn(uid, h, key) end,
			setLevel = function(uid, level)
				local h = heroes[uid]
				if h then
					h.xp = H.xpFor(level, xpMult) * h.def.cost + 1
					while h.level < min(level, H.MAX_LEVEL) do
						levelUp(uid, h)
					end
					publish(uid, h)
				end
			end,
			addXP = function(uid, metal) local h = heroes[uid]; if h then addXP(uid, h, metal) end end,
			cast = function(uid, key, tx, tz, target) local h = heroes[uid]; return h and K.tryCast(uid, h, key, tx, tz, target) end,
			-- any kit ability table, no cooldown (tests): castAbility(uid, { kind = ..., ... }, rank, tx, tz, target)
			castAbility = function(uid, b, r, tx, tz, target) local h = heroes[uid]; return h and api.cast(uid, h, b, r, tx, tz, target) end,
			abilityPower = function(uid) local h = heroes[uid]; return h and h.power or 1 end,
			setAI = function(teamID, ai)
				isAITeam[teamID] = ai
				for _, h in pairs(heroes) do
					if h.team == teamID then
						h.ai = ai
					end
				end
			end,
			buyLevel = function(uid, paid) local h = heroes[uid]; if h then return buyLevel(uid, h, paid) end return false, "unknown" end,
			applyStats = function(uid) local h = heroes[uid]; if h then applyStats(uid, h) end end,
			refresh = function(uid) local h = heroes[uid]; if h then applyStats(uid, h); publish(uid, h) end end,
			-- damage without the hero multipliers (items: opts.item = true also skips the damage-type bonus)
			damage = function(target, dmg, attackerID, opts) return abilityDamage(target, dmg, attackerID, opts) end,
			-- hero cap (SPEC section 3)
			slots = function(teamID) return teamSlots[teamID] or 1, slotsUsed(teamID), research[teamID] end,
			setSlots = function(teamID, n) teamSlots[teamID] = max(1, min(H.MAX_HEROES, n)); refreshAltars(teamID) end,
			research = function(teamID, altarID, paid) return startResearch(teamID, altarID, paid) end,
			canStartHero = function(teamID, name) return canStartHero(teamID, name) end,
			learnState = function(uid, key) local h = heroes[uid]; if h then return learnState(h, key) end end,
			-- items live in the items gadget (GG.T4HeroItems): these forward to it
			give = function(uid, item) local I, h = GG.T4HeroItems, heroes[uid]; return I and I.give and h and I.give(h.team, item) or false end,
			equip = function(uid, item) local I = GG.T4HeroItems; return I and I.equip and I.equip(uid, item) or false end,
			drop = function(item, x, z) local I = GG.T4HeroItems; return I and I.drop and I.drop(item, x, z) or false end,
		}
	end

	function gadget:Shutdown()
		for uid in pairs(movers) do
			if alive(uid) then
				MoveCtrl.Disable(uid)
			end
		end
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
