-- Custom T4 heroes (denysfast/bar-game): the design data shared by the hero gadget
-- (luarules/gadgets/unit_t4_heroes.lua), the hero UI widget (luaui/Widgets/gui_t4_heroes.lua)
-- and the unitdefs (units/*T4*/, gamedata/custom_t4.lua). See CUSTOM.md, section "T4 heroes".
--
-- A hero is unique per team, levels 1..99 from combat experience and spends one point per level - and metal -
-- on the branches of its upgrade window:
--   w<N>_<track>                     every weapon has its own tree of three tracks (H.weaponKinds)
--   plating / servos                 common chassis branches
--   a1 / a2                          two signature abilities, 3 ranks (levels 3 / 15 / 30)
--   ult                              the ultimate, 3 ranks (levels 20 / 45 / 70)
-- 99 points for 120+ ranks: a maxed hero still has to leave something out. Six inventory slots take items
-- (H.items) that drop from slain heroes.
--
-- Rank effects ("mods") of the abilities are summed over every learned rank:
--   damage, hp, armor, regen (share of max HP per second), speed, range, sight, radar       fractions
--   reload (fraction off the reload time), accuracy (fraction off the spread)                fractions
--   weaponDamage / weaponReload = { <weapon key> = fraction }, burst = { <weapon key> = extra shots }
--   swap = { weapon = <key>, to = <hero weapondef key>, every = N, other = <key>, scatter = R }   the highest
--          learned rank wins: every N-th projectile of that weapon is replaced by the hero weapondef (N = 1:
--          all of them, `other` replaces the rest), a salvo with `scatter` lands on random points within R
--          of the target instead of all on it
-- Abilities with code behind them are `kind` + per-rank arrays (see the gadget); `fx` names the CEG of a
-- self buff (effects/custom_t4_heroes.lua).

local H = {}

H.MAX_LEVEL = 99
H.DEATH_LEVELS = 5          -- a revived hero comes back this many levels lower
H.LEVEL_HP = 0.03           -- automatic growth per level above 1
H.LEVEL_DAMAGE = 0.03
-- experience, in units of the hero's own metal cost: reaching level L takes
-- XP_TOTAL * ((L - 1) / XP_REF) ^ XP_EXP (modoption hero_xp_mult divides the requirement).
-- v14: ten times v13 (5 costs for level 30), the curve simply continues to level 99 (~400 costs)
H.XP_TOTAL = 50.0
H.XP_REF = 29
H.XP_EXP = 1.7
H.XP_KILL = 0.25            -- the killer also gets this share of the victim's cost
H.XP_HERO_KILL = 0.25       -- a slain hero is worth this share of its cost more per 10 levels
H.XP_SHARE = 0.08           -- and every hero within XP_SHARE_RADIUS of a dying enemy this share
H.XP_SHARE_RADIUS = 1400
H.XP_STRUCTURE = 0.3        -- structures give this share of the experience units give
-- hero.xpRate scales everything a hero earns (long-range artillery farms bases from afar)
-- heroes regenerate REST_REGEN of max HP per second after REST_DELAY seconds without taking damage
H.REST_REGEN = 0.005
H.REST_DELAY = 10
-- revive: the dead hero is rebuilt at its foundry, level - DEATH_LEVELS, for
-- cost * (1 + REVIVE_COST_PER_LEVEL * new level) metal and energy, build time * (1 + REVIVE_TIME_PER_LEVEL * level)
H.REVIVE_COST_PER_LEVEL = 0.06
H.REVIVE_TIME_PER_LEVEL = 0.03
-- fountain: a hero near its own team's T4 foundry regains this share of max HP per second
H.FOUNTAIN_RADIUS = 1100
H.FOUNTAIN_REGEN = 0.02
-- AI heroes are driven by the hero gadget, not by the skirmish AI: they march with the strongest group
-- of their army (aiRole front: at its head, center: in it, back: behind it), fall back to the fountain
-- below AI_RETREAT_HP - or below AI_CAUTION_HP when the enemies around outweigh the allies
-- AI_DANGER times - and rejoin the army at AI_RETURN_HP
H.AI_RETREAT_HP = 0.35
H.AI_CAUTION_HP = 0.65
H.AI_DANGER = 1.6
H.AI_BURST = 0.3             -- or when it lost this share of its health within the last 5 seconds
H.AI_RETURN_HP = 0.9
H.AI_RETURN_HP_NO_FOUNTAIN = 0.7 -- no altar left to heal at: rejoin sooner
H.AI_ROLE_OFFSET = { front = 150, center = -100, back = -500 }
H.AI_ESCORT = 10000         -- the smallest army group (metal) a hero marches with; below it guards the altar

-- level needed for a rank of a branch
local function reqLinear(rank) return rank * 2 - 1 end
local function reqServo(rank) return rank * 4 - 1 end
local function reqWeapon(rank) return (rank - 1) * 3 + 1 end
local ABILITY_REQ = { 3, 15, 30 }
local ULT_REQ = { 20, 45, 70 }
local function reqAbility(rank) return ABILITY_REQ[rank] or math.huge end
local function reqUlt(rank) return ULT_REQ[rank] or math.huge end
H.req = { linear = reqLinear, servo = reqServo, weapon = reqWeapon, ability = reqAbility, ult = reqUlt }

-- metal every rank costs on top of the talent point (paid from the team's storage when learned)
H.ABILITY_METAL = { 15000, 30000, 50000 }
H.ULT_METAL = { 40000, 70000, 100000 }
H.STAT_METAL = 1500          -- stat and weapon ranks: STAT_METAL * rank

H.branchOrder = { "plating", "servos", "a1", "a2", "ult" }
H.abilityKeys = { "a1", "a2", "ult" }
H.hotkeys = { a1 = "Q", a2 = "W", ult = "R" }

-- the common branches; `per` is one rank, the text is shown with the rank count
-- (v14: Arsenal is gone - every weapon has its own tree, see H.weaponKinds)
H.common = {
	plating = {
		name = "Plating", icon = "stat_plating", maxRank = 15, req = "linear",
		desc = "+8% max health and +0.02% health regeneration per second per rank",
		per = { hp = 0.08, regen = 0.0002 },
	},
	servos = {
		name = "Servos", icon = "stat_servos", maxRank = 10, req = "servo",
		desc = "+5% speed, +5% sight per rank",
		per = { speed = 0.05, sight = 0.05 },
	},
}

-- Weapon trees (v14): every real weapon of a hero levels on its own. A weapon kind has three tracks of
-- WEAPON_RANKS ranks; `per` is one rank of the track:
--   damage     fraction of the weapon's damage
--   range      fraction of its range
--   reload     fraction off its reload time
--   splash     fraction of its area of effect
--   pellets    extra projectiles per shot
--   salvo      extra shots per salvo: `per` of the base salvo (at least 1)
--   pierce     share of each hit dealt again to the enemies on a line behind the target (`len` elmos)
--   burn       share of each hit dealt again as fire over 3 seconds
--   discharge  share of each hit dealt again as paralysis (EMP)
-- The visual tier of a weapon (thicker beams, bigger shells and blasts) follows the sum of its ranks.
H.WEAPON_RANKS = 10
H.weaponTiers = { 0, 6, 15, 24 }   -- rank sum where tiers 1..4 start
local T = {
	damage = { name = "Damage", icon = "stat_damage", stat = "damage", per = 0.10, fmt = "+%d%% damage" },
	range = { name = "Range", icon = "stat_range", stat = "range", per = 0.04, fmt = "+%d%% range" },
	reload = { name = "Rate of fire", icon = "stat_reload", stat = "reload", per = 0.05, fmt = "-%d%% reload" },
	splash = { name = "Splash", icon = "stat_splash", stat = "splash", per = 0.12, fmt = "+%d%% blast radius" },
	pellets = { name = "Pellets", icon = "stat_pellets", stat = "pellets", per = 1, fmt = "+%d pellets", abs = true },
	salvo = { name = "Salvo", icon = "stat_salvo", stat = "salvo", per = 0.12, fmt = "+%d%% rockets per salvo" },
	pierce = { name = "Burn-through", icon = "stat_pierce", stat = "pierce", per = 0.07, len = 600, fmt = "%d%% of the hit burns through the line" },
	penetration = { name = "Penetration", icon = "stat_penetration", stat = "pierce", per = 0.08, len = 1200, fmt = "%d%% of the hit pierces the line" },
	burn = { name = "Afterburn", icon = "stat_burn", stat = "burn", per = 0.06, fmt = "%d%% of the hit burns on for 3 s" },
	discharge = { name = "Discharge", icon = "stat_discharge", stat = "discharge", per = 0.15, fmt = "%d%% of the hit as paralysis" },
}
H.tracks = T
H.weaponKinds = {
	beam = { label = "Beam", tracks = { "damage", "range", "pierce" } },
	shotgun = { label = "Shotgun", tracks = { "damage", "splash", "pellets" } },
	cannon = { label = "Cannon", tracks = { "damage", "splash", "reload" } },
	artillery = { label = "Artillery", tracks = { "damage", "range", "splash" } },
	rockets = { label = "Rockets", tracks = { "damage", "salvo", "splash" } },
	lightning = { label = "Lightning", tracks = { "damage", "range", "discharge" } },
	flame = { label = "Flamethrower", tracks = { "damage", "range", "burn" } },
	rail = { label = "Rail", tracks = { "damage", "range", "penetration" } },
	emp = { label = "EMP", tracks = { "damage", "range", "reload" } },
}

-- Items (v14): six slots per hero, Warcraft style. They drop from slain heroes (all their items, where they
-- fell) and, rarely, from expensive enemies a hero kills; a hero walking over one picks it up.
--   stats: damage, hp, armor, speed, range, reload, sight (fractions), lifesteal, thorns, crit = {chance, mult},
--          cdr (fraction off ability cooldowns), xp (fraction more experience), splash (fraction of blast radius)
--   aura = { radius, damage }  allies around deal more damage
--   active = { kind, cooldown, ... }   used from the inventory: heal (share of max HP), invuln (seconds),
--          dash (elmos forward); zap = { period, damage, radius } strikes the nearest enemy by itself
H.INVENTORY = 6
H.ITEM_PICKUP_RADIUS = 180
H.ITEM_LIFETIME = 300        -- seconds an item lies on the ground
H.ITEM_DROP_CHANCE = 1 / 150000 -- per metal of a slain enemy (a 30k titan: 20%), max ITEM_DROP_MAX
H.ITEM_DROP_MAX = 0.35
H.rarities = {
	common = { color = { 0.85, 0.85, 0.85 }, weight = 55 },
	rare = { color = { 0.3, 0.6, 1.0 }, weight = 28 },
	epic = { color = { 0.75, 0.35, 1.0 }, weight = 13 },
	legendary = { color = { 1.0, 0.65, 0.1 }, weight = 4 },
}
H.items = {
	plasma_core = { name = "Plasma Core", rarity = "common", stats = { damage = 0.12 }, desc = "+12% damage" },
	armor_plate = { name = "Composite Plate", rarity = "common", stats = { hp = 0.12 }, desc = "+12% health" },
	servo_boots = { name = "Servo Treads", rarity = "common", stats = { speed = 0.12 }, desc = "+12% speed" },
	targeting_lens = { name = "Targeting Lens", rarity = "common", stats = { range = 0.06 }, desc = "+6% range" },
	capacitor = { name = "Rapid Capacitor", rarity = "common", stats = { reload = 0.08 }, desc = "8% faster reload" },
	nanite_vial = { name = "Nanite Vial", rarity = "common", stats = {}, active = { kind = "heal", amount = 0.2, cooldown = 60 },
		desc = "Use: repair 20% health (cd 60 s)" },
	vampiric_coil = { name = "Vampiric Coil", rarity = "rare", stats = { lifesteal = 0.03 }, desc = "3% of damage dealt heals the hero" },
	thorn_mesh = { name = "Thorn Mesh", rarity = "rare", stats = { thorns = 0.15, armor = 0.04 }, desc = "Returns 15% of damage taken, -4% damage taken" },
	overclock_chip = { name = "Overclock Chip", rarity = "rare", stats = { damage = 0.22, hp = -0.05 }, desc = "+22% damage, -5% health" },
	reactive_shell = { name = "Reactive Shell", rarity = "rare", stats = { armor = 0.10 }, desc = "-10% damage taken" },
	scout_uplink = { name = "Scout Uplink", rarity = "rare", stats = { sight = 0.3, range = 0.05 }, desc = "+30% sight, +5% range" },
	blink_drive = { name = "Blink Drive", rarity = "rare", stats = { speed = 0.05 }, active = { kind = "dash", distance = 700, cooldown = 30 },
		desc = "+5% speed. Use: blink 700 forward (cd 30 s)" },
	warlords_banner = { name = "Warlord's Banner", rarity = "epic", stats = {}, aura = { radius = 900, damage = 0.12 },
		desc = "Allies within 900 deal +12% damage" },
	phase_shield = { name = "Phase Shield", rarity = "epic", stats = { hp = 0.08 }, active = { kind = "invuln", duration = 3, cooldown = 90 },
		desc = "+8% health. Use: invulnerable for 3 s (cd 90 s)" },
	crit_matrix = { name = "Crit Matrix", rarity = "epic", stats = { crit = { 0.15, 2.0 } }, desc = "15% chance to deal double damage" },
	chrono_crystal = { name = "Chrono Crystal", rarity = "epic", stats = { cdr = 0.2 }, desc = "Ability cooldowns -20%" },
	titan_heart = { name = "Titan Heart", rarity = "epic", stats = { hp = 0.3, damage = 0.05 }, desc = "+30% health, +5% damage" },
	shrapnel_amp = { name = "Shrapnel Amplifier", rarity = "epic", stats = { splash = 0.3, damage = 0.06 }, desc = "+30% blast radius, +6% damage" },
	orb_annihilation = { name = "Orb of Annihilation", rarity = "legendary", stats = { damage = 0.35, burn = 0.08 },
		desc = "+35% damage, hits burn for 8% more" },
	aegis_relic = { name = "Aegis of the Ancients", rarity = "legendary", stats = { armor = 0.2, hp = 0.2 }, desc = "-20% damage taken, +20% health" },
	chronos_engine = { name = "Chronos Engine", rarity = "legendary", stats = { reload = 0.25, speed = 0.15, cdr = 0.1 },
		desc = "25% faster reload, +15% speed, cooldowns -10%" },
	soul_harvester = { name = "Soul Harvester", rarity = "legendary", stats = { xp = 0.5, damage = 0.15 }, desc = "+50% experience, +15% damage" },
	storm_crown = { name = "Crown of Storms", rarity = "legendary", stats = { damage = 0.1 }, zap = { period = 3, damage = 9000, radius = 1000 },
		desc = "+10% damage. Every 3 s lightning strikes the nearest enemy within 1000 (9000)" },
	dragon_reactor = { name = "Dragon Reactor", rarity = "legendary", stats = { damage = 0.25, hp = 0.25, speed = 0.1 },
		desc = "+25% damage, +25% health, +10% speed" },
}
H.itemOrder = {
	"plasma_core", "armor_plate", "servo_boots", "targeting_lens", "capacitor", "nanite_vial",
	"vampiric_coil", "thorn_mesh", "overclock_chip", "reactive_shell", "scout_uplink", "blink_drive",
	"warlords_banner", "phase_shield", "crit_matrix", "chrono_crystal", "titan_heart", "shrapnel_amp",
	"orb_annihilation", "aegis_relic", "chronos_engine", "soul_harvester", "storm_crown", "dragon_reactor",
}
H.itemIndex = {}
for i, id in ipairs(H.itemOrder) do
	H.itemIndex[id] = i
end

H.heroes = {
	---------------------------------------------------------------------------- Armada
	armt4atlas = {
		title = "Atlas, the Bulwark", role = "Assault / support", aiRole = "front",
		fx = 2.5,
		weapons = { { keys = { "armbantha_fire" }, name = "Pulse Cannon", kind = "cannon" }, { keys = { "tehlazerofdewm" }, name = "Doom Laser", kind = "beam" }, { keys = { "bantha_rocket" }, name = "Starburst Rockets", kind = "rockets" } },
		a1 = {
			name = "Repair Field", kind = "aura_heal", passive = true,
			desc = "Allies (and structures) around Atlas regain health every second",
			radius = { 700, 900, 1100 }, rate = { 12, 26, 44 },
			text = { "700 radius, 12 HP/s", "900 radius, 26 HP/s", "1100 radius, 44 HP/s" },
		},
		a2 = {
			name = "Guardian Protocol", kind = "active_guard", cmd = 36101, action = "hero_guardian",
			desc = "Allies within 800 take less damage for 8 seconds",
			radius = 800, reduce = { 0.25, 0.35, 0.45 }, duration = 8, cooldown = { 50, 45, 40 },
			text = { "-25% damage taken, cd 50s", "-35%, cd 45s", "-45%, cd 40s" },
		},
		ult = {
			name = "Doomsday Rockets", kind = "mods", passive = true,
			desc = "The shoulder starburst rockets grow into a salvo, then heavy warheads, then tactical nukes",
			ranks = {
				{ projectiles = { bantha_rocket = 3 } },
				{ projectiles = { bantha_rocket = 3 }, swap = { weapon = "bantha_rocket", to = "hero_heavyrocket", every = 1, scatter = 160 } },
				{ projectiles = { bantha_rocket = 3 }, swap = { weapon = "bantha_rocket", to = "hero_nuke", every = 1, scatter = 220 } },
			},
			text = { "3 rockets per salvo", "heavy warheads: x2 damage, x2 blast", "every rocket is a tactical nuke" },
		},
	},

	armt4olympus = {
		title = "Olympus, the Thunderer", role = "Strategic artillery", aiRole = "back", xpRate = 0.25,
		fx = 2.5,
		weapons = { { keys = { "shocker_low", "shocker_high" }, name = "Plasma Artillery", kind = "artillery" } },
		a1 = {
			name = "Spotter Uplink", kind = "mods", passive = true,
			desc = "Radar, sight, range and accuracy",
			ranks = {
				{ radar = 0.15, sight = 0.15, range = 0.05, accuracy = 0.3 },
				{ radar = 0.30, sight = 0.30, range = 0.10, accuracy = 0.5 },
				{ radar = 0.45, sight = 0.45, range = 0.15, accuracy = 0.65 },
			},
			text = { "+15% radar/sight, +5% range, -30% spread", "+30%, +10%, -50%", "+45%, +15%, -65%" },
		},
		a2 = {
			name = "Rapid Barrage", kind = "active_buff", cmd = 36102, action = "hero_barrage", fx = "hero-barrage",
			desc = "For 8 seconds the guns reload three times faster",
			buff = { reload = 0.66 }, duration = { 6, 8, 10 }, cooldown = { 45, 40, 35 },
			text = { "6 s, cd 45s", "8 s, cd 40s", "10 s, cd 35s" },
		},
		ult = {
			name = "Nuclear Shells", kind = "mods", passive = true,
			desc = "Incendiary heavy shells, then every third shell nuclear, then all of them",
			ranks = {
				{ swap = { weapon = "shocker_low", to = "hero_heavyshell", every = 1 }, swap2 = { weapon = "shocker_high", to = "hero_heavyshell", every = 1 } },
				{ swap = { weapon = "shocker_low", to = "hero_nukeshell", every = 3, other = "hero_heavyshell" }, swap2 = { weapon = "shocker_high", to = "hero_nukeshell", every = 3, other = "hero_heavyshell" } },
				{ swap = { weapon = "shocker_low", to = "hero_nukeshell", every = 1 }, swap2 = { weapon = "shocker_high", to = "hero_nukeshell", every = 1 } },
			},
			text = { "heavy shells: +60% damage and blast", "every 3rd shell is nuclear", "every shell is nuclear" },
		},
	},

	armt4aegis = {
		title = "Aegis, the Warden", role = "Shield bearer", aiRole = "center",
		fx = 2.5,
		weapons = { { keys = { "mech_rapidlaser" }, name = "Rapid Lasers", kind = "beam" } },
		a1 = {
			name = "Deflector Matrix", kind = "shield_cap", passive = true,
			desc = "Capacity and recharge of the plasma deflector over the army",
			cap = { 0.5, 0.75, 1.0 }, base = 0.3, regen = { 1.5, 2.0, 2.6 },
			text = { "50% capacity, x1.5 recharge", "75%, x2", "100%, x2.6" },
		},
		a2 = {
			name = "Pulse Overload", kind = "active_pulse", cmd = 36103, action = "hero_pulse",
			desc = "Dumps half of the shield charge as an EMP shockwave",
			radius = { 500, 600, 700 }, ratio = { 1.0, 1.4, 1.8 }, stun = { 3, 4, 5 }, cooldown = { 35, 30, 25 },
			text = { "500 radius, 3 s stun", "600, 4 s, x1.4 damage", "700, 5 s, x1.8 damage" },
		},
		ult = {
			name = "Aegis Dome", kind = "active_dome", cmd = 36104, action = "hero_dome",
			desc = "Allies within 900 cannot be damaged for a few seconds",
			radius = 900, duration = { 4, 7, 10 }, cooldown = { 120, 110, 100 },
			text = { "4 s invulnerability, cd 120s", "7 s, cd 110s", "10 s, cd 100s" },
		},
	},

	armt4zeus = {
		title = "Zeus Prime, the Stormlord", role = "EMP / lightning", aiRole = "front",
		fx = 2.2,
		weapons = { { keys = { "thunder" }, name = "Thunder Coil", kind = "lightning" }, { keys = { "empmissile" }, name = "EMP Missiles", kind = "emp" }, { keys = { "emp" }, name = "EMP Beams", kind = "beam" } },
		a1 = {
			name = "Chain Lightning", kind = "chain", passive = true,
			desc = "Every lightning strike jumps to more enemies",
			weapon = "thunder", jumps = { 1, 2, 3 }, radius = 450, frac = 0.6,
			text = { "1 jump, 60% damage", "2 jumps", "3 jumps" },
		},
		a2 = {
			name = "Static Field", kind = "aura_emp", passive = true,
			desc = "Enemies around are shocked and paralysed every 2 seconds",
			radius = { 450, 550, 650 }, emp = { 2500, 5000, 8000 }, dmg = { 250, 500, 800 }, period = 2,
			text = { "450 radius, 2500 EMP", "550, 5000 EMP", "650, 8000 EMP" },
		},
		ult = {
			name = "Wrath of the Storm", kind = "active_storm", cmd = 36105, action = "hero_storm", target = "map",
			desc = "Calls a lightning storm on an area; at rank 3 the EMP missiles become EMP nukes",
			range = 2000, radius = 550, bolts = { 12, 18, 26 }, dmg = { 2200, 3200, 4500 }, emp = 6000,
			duration = 5, cooldown = { 90, 80, 70 },
			ranks = { {}, {}, { swap = { weapon = "empmissile", to = "hero_empnuke", every = 1 } } },
			text = { "12 bolts, cd 90s", "18 bolts, cd 80s", "26 bolts + EMP nukes" },
		},
	},

	---------------------------------------------------------------------------- Cortex
	cort4colossus = {
		title = "Colossus, the Warlord", role = "Flagship", aiRole = "front",
		fx = 2.2,
		weapons = { { keys = { "corkorg_fire" }, name = "Plasma Scatter Gun", kind = "shotgun" }, { keys = { "corkorg_laser" }, name = "Heat Eye", kind = "beam" }, { keys = { "corkorg_rocket" }, name = "Warlord Rockets", kind = "rockets" } },
		a1 = {
			name = "War Stomp", kind = "active_stomp", cmd = 36111, action = "hero_stomp",
			desc = "Slams the ground: damages and stuns everything around",
			radius = { 450, 550, 650 }, dmg = { 3000, 5500, 8500 }, stun = { 2, 3, 4 }, cooldown = { 30, 27, 24 },
			text = { "450 radius, 3000 dmg, 2 s stun", "550, 5500, 3 s", "650, 8500, 4 s" },
		},
		a2 = {
			name = "Command Aura", kind = "aura_damage", passive = true,
			desc = "Allied units around deal more damage",
			radius = 900, mult = { 0.08, 0.16, 0.25 },
			text = { "+8% damage", "+16%", "+25%" },
		},
		ult = {
			name = "Undying", kind = "undying", passive = true,
			desc = "Lethal damage instead leaves Colossus standing, healed; rank 3 is reborn in a nuclear blast",
			cooldown = { 300, 240, 180 }, heal = { 0.4, 0.6, 0.8 }, nova = { false, false, true },
			text = { "revive at 40% HP, cd 300s", "60% HP, cd 240s", "80% HP, cd 180s, nuclear rebirth" },
		},
	},

	cort4bastion = {
		title = "Bastion, the Citadel", role = "Walking fortress", aiRole = "front",
		fx = 2.2,
		weapons = { { keys = { "juggernaut_fire" }, name = "Gauss Cannon", kind = "rail" }, { keys = { "juggernaut_bottom", "juggernaut_top" }, name = "Laser Turrets", kind = "beam" } },
		a1 = {
			name = "Reactive Armor", kind = "mods", passive = true,
			desc = "Less damage taken, faster self-repair",
			ranks = { { armor = 0.08, regen = 0.0004 }, { armor = 0.16, regen = 0.0008 }, { armor = 0.24, regen = 0.0012 } },
			text = { "-8% damage taken", "-16%", "-24%" },
		},
		a2 = {
			name = "Siege Protocol", kind = "active_buff", cmd = 36112, action = "hero_siege", fx = "hero-siege",
			desc = "Anchors in place: longer range, more damage, stronger shield",
			buff = { range = 0.4, damage = 0.4, immobile = true, shieldRegen = 3 }, duration = { 10, 13, 16 }, cooldown = { 45, 40, 35 },
			text = { "10 s, +40% range/damage", "13 s", "16 s" },
		},
		ult = {
			name = "Annihilator", kind = "mods", passive = true,
			desc = "The gauss cannon reloads faster, hits harder, then fires nuclear shells",
			ranks = {
				{ weaponReload = { juggernaut_fire = 0.4 } },
				{ weaponReload = { juggernaut_fire = 0.4 }, weaponDamage = { juggernaut_fire = 1.0 } },
				{ weaponReload = { juggernaut_fire = 0.4 }, weaponDamage = { juggernaut_fire = 1.0 }, swap = { weapon = "juggernaut_fire", to = "hero_nukeshell", every = 1 } },
			},
			text = { "gauss reload -40%", "gauss damage x2", "nuclear gauss shells" },
		},
	},

	cort4armageddon = {
		title = "Armageddon, the Doomsayer", role = "Rocket artillery", aiRole = "back", xpRate = 0.15,
		fx = 2.5,
		weapons = { { keys = { "exp_heavyrocket" }, name = "Heavy Rocket Racks", kind = "rockets" } },
		a1 = {
			name = "Saturation", kind = "mods", passive = true,
			desc = "More rockets in every salvo",
			ranks = { { burst = { exp_heavyrocket = 10 } }, { burst = { exp_heavyrocket = 20 } }, { burst = { exp_heavyrocket = 30 } } },
			text = { "+10 rockets", "+20 rockets", "+30 rockets" },
		},
		a2 = {
			name = "Long-Range Uplink", kind = "mods", passive = true,
			desc = "Range and radar",
			ranks = { { range = 0.1, radar = 0.2 }, { range = 0.2, radar = 0.4 }, { range = 0.3, radar = 0.6 } },
			text = { "+10% range, +20% radar", "+20%, +40%", "+30%, +60%" },
		},
		ult = {
			name = "Armageddon Protocol", kind = "mods", passive = true,
			desc = "Nuclear warheads in the salvo: one, then several, then every rocket",
			ranks = {
				{ swap = { weapon = "exp_heavyrocket", to = "hero_nukerocket", every = 40 } },
				{ swap = { weapon = "exp_heavyrocket", to = "hero_nukerocket", every = 12 } },
				{ swap = { weapon = "exp_heavyrocket", to = "hero_mininuke", every = 1, scatter = 380 } },
			},
			text = { "1 tactical nuke per salvo", "a nuke every 12th rocket", "every rocket is a mini-nuke" },
		},
	},

	cort4hellwalker = {
		title = "Hellwalker, the Inferno", role = "Flame assault", aiRole = "front",
		fx = 2.5,
		weapons = { { keys = { "newdmaw" }, name = "Hellfire Maw", kind = "flame" }, { keys = { "karg_shoulder" }, name = "Shoulder Missiles", kind = "rockets" } },
		a1 = {
			name = "Immolation", kind = "aura_burn", passive = true,
			desc = "Burns every enemy around, every second",
			radius = { 320, 400, 480 }, dps = { 450, 900, 1500 },
			text = { "320 radius, 450 dps", "400, 900 dps", "480, 1500 dps" },
		},
		a2 = {
			name = "Hellcharge", kind = "active_buff", cmd = 36113, action = "hero_hellcharge", fx = "hero-hellcharge",
			desc = "Sprints and leaves a trail of fire",
			buff = { speed = 0.8, trail = true }, trailDmg = { 600, 1000, 1500 }, duration = { 5, 6, 7 }, cooldown = { 30, 27, 24 },
			text = { "5 s, +80% speed, 600 fire", "6 s, 1000 fire", "7 s, 1500 fire" },
		},
		ult = {
			name = "Rain of Fire", kind = "active_meteors", cmd = 36114, action = "hero_rainfire", target = "map",
			desc = "Meteors fall on an area; at rank 3 it ends in a nuclear fireball",
			weapon = "hero_meteor", range = 1600, radius = 550, count = { 12, 20, 30 }, duration = 6,
			nova = { false, false, true }, cooldown = { 75, 70, 60 },
			text = { "12 meteors, cd 75s", "20 meteors, cd 70s", "30 meteors + nuclear fireball" },
		},
	},

	---------------------------------------------------------------------------- Legion
	legt4helios = {
		title = "Helios, the Sunbringer", role = "Heat / support", aiRole = "center",
		fx = 2.2,
		weapons = { { keys = { "heatray1" }, name = "Heat Ray", kind = "beam" }, { keys = { "ultraheavyriotcannon" }, name = "Riot Cannon", kind = "cannon" }, { keys = { "legflak_gun" }, name = "Flak Battery", kind = "cannon" } },
		a1 = {
			name = "Solar Aura", kind = "aura_heal", passive = true,
			desc = "Allies (and structures) around Helios regain health every second",
			radius = { 700, 900, 1100 }, rate = { 12, 26, 44 },
			text = { "700 radius, 12 HP/s", "900 radius, 26 HP/s", "1100 radius, 44 HP/s" },
		},
		a2 = {
			name = "Solar Flare", kind = "active_flare", cmd = 36121, action = "hero_flare",
			desc = "A blinding burst: burns enemies around and heals allies",
			radius = { 600, 700, 800 }, dmg = { 5000, 8500, 13000 }, heal = 0.08, cooldown = { 40, 35, 30 },
			text = { "600 radius, 5000 dmg", "700, 8500", "800, 13000" },
		},
		ult = {
			name = "Sunstrike", kind = "active_sunbeam", cmd = 36122, action = "hero_sunstrike", target = "map",
			desc = "A beam of the sun burns an area for 6 seconds; rank 3 ends in a nuclear flare",
			range = 2000, radius = 280, tick = { 1800, 2800, 4000 }, duration = 6,
			nova = { false, false, true }, cooldown = { 90, 80, 70 },
			text = { "1800 per 0.2 s, cd 90s", "2800, cd 80s", "4000 + nuclear flare" },
		},
	},

	legt4starfall = {
		title = "Starfall, the Astronomer", role = "Orbital artillery", aiRole = "back", xpRate = 0.25,
		fx = 2.5,
		weapons = { { keys = { "shocker_low" }, name = "Starfire Cannon", kind = "artillery" } },
		a1 = {
			name = "Deep Sky Radar", kind = "mods", passive = true,
			desc = "Radar, sight and range",
			ranks = { { radar = 0.25, sight = 0.25, range = 0.08 }, { radar = 0.5, sight = 0.5, range = 0.16 }, { radar = 0.75, sight = 0.75, range = 0.24 } },
			text = { "+25% radar/sight, +8% range", "+50%, +16%", "+75%, +24%" },
		},
		a2 = {
			name = "Cluster Payload", kind = "cluster", passive = true,
			desc = "Every plasma round bursts into bomblets on impact",
			weapon = "shocker_low", to = "hero_bomblet", count = { 3, 5, 7 }, spread = 260,
			text = { "3 bomblets", "5 bomblets", "7 bomblets" },
		},
		ult = {
			name = "Meteor Storm", kind = "active_meteors", cmd = 36123, action = "hero_meteorstorm", target = "map",
			desc = "Calls down plasma meteors from orbit anywhere in radar range; rank 3 ends with a nuke",
			weapon = "hero_starmeteor", range = 9000, radius = 700, count = { 8, 14, 20 }, duration = 8,
			nova = { false, false, true }, cooldown = { 120, 105, 90 },
			text = { "8 meteors, cd 120s", "14 meteors, cd 105s", "20 meteors + nuke" },
		},
	},

	legt4longinus = {
		title = "Longinus, the Spear", role = "Titan hunter", aiRole = "center",
		fx = 2.2,
		weapons = { { keys = { "t3_rail_accelerator" }, name = "Rail Accelerators", kind = "rail" } },
		a1 = {
			name = "Titan Slayer", kind = "slayer", passive = true,
			desc = "More damage against expensive targets (10000+ metal)",
			minCost = 10000, mult = { 0.25, 0.5, 0.8 },
			text = { "+25% vs big targets", "+50%", "+80%" },
		},
		a2 = {
			name = "Magnetic Coils", kind = "mods", passive = true,
			desc = "Faster reload and longer range of the rails",
			ranks = { { reload = 0.12, range = 0.05 }, { reload = 0.24, range = 0.1 }, { reload = 0.36, range = 0.15 } },
			text = { "reload -12%, range +5%", "-24%, +10%", "-36%, +15%" },
		},
		ult = {
			name = "Spear of Longinus", kind = "active_spear", cmd = 36124, action = "hero_spear", target = "unit",
			desc = "One colossal rail shot through everything in its line; rank 3 detonates a nuke on impact",
			range = { 2400, 2800, 3200 }, pct = { 0.15, 0.25, 0.35 }, flat = 20000, line = 12000,
			nova = { false, false, true }, cooldown = { 90, 75, 60 },
			text = { "15% max HP + 20000, cd 90s", "25%, cd 75s", "35%, cd 60s, nuclear impact" },
		},
	},

	legt4tempest = {
		title = "Tempest, the Stormblade", role = "Melee assault", aiRole = "front",
		fx = 2.5,
		weapons = { { keys = { "shotgun" }, name = "Storm Shotgun", kind = "shotgun" }, { keys = { "adv_rocket" }, name = "Rocket Pods", kind = "rockets" }, { keys = { "leg_t2_microflak_mobile" }, name = "Micro Flak", kind = "cannon" } },
		a1 = {
			name = "Critical Strike", kind = "crit", passive = true,
			desc = "A chance to deal multiplied damage",
			chance = { 0.15, 0.25, 0.35 }, mult = { 2.5, 3.0, 3.5 },
			text = { "15% for x2.5", "25% for x3", "35% for x3.5" },
		},
		a2 = {
			name = "Overdrive", kind = "active_buff", cmd = 36125, action = "hero_overdrive", fx = "hero-overdrive",
			desc = "Faster movement and fire for a few seconds",
			buff = { speed = 0.6, reload = 0.4 }, duration = { 6, 7, 8 }, cooldown = { 30, 27, 24 },
			text = { "6 s, +60% speed, x1.7 fire rate", "7 s", "8 s" },
		},
		ult = {
			name = "Bladestorm", kind = "active_bladestorm", cmd = 36126, action = "hero_bladestorm",
			desc = "Spins into a storm of blades: shreds everything around, takes half damage",
			radius = { 420, 500, 580 }, dmg = { 900, 1500, 2300 }, duration = 6, armor = 0.5, cooldown = { 75, 65, 55 },
			text = { "420 radius, 900 per 0.25 s", "500, 1500", "580, 2300" },
		},
	},
}

-- the flat list of hero unit names in UI order
H.order = {
	"armt4atlas", "armt4olympus", "armt4aegis", "armt4zeus",
	"cort4colossus", "cort4bastion", "cort4armageddon", "cort4hellwalker",
	"legt4helios", "legt4starfall", "legt4longinus", "legt4tempest",
}

-- weapon branch keys: w<index>_<track>, e.g. w2_pierce
function H.weaponBranch(heroName, key)
	local hero = H.heroes[heroName]
	local wi, track = key:match("^w(%d+)_(%a+)$")
	if not hero or not wi then
		return nil
	end
	local w = hero.weapons and hero.weapons[tonumber(wi)]
	local t = H.tracks[track]
	if not w or not t then
		return nil
	end
	return {
		name = t.name, icon = t.icon, maxRank = H.WEAPON_RANKS, req = "weapon", weapon = tonumber(wi), track = track,
		desc = w.name .. " - " .. string.format(t.fmt, t.abs and t.per or math.floor(t.per * 100 + 0.5)) .. " per rank",
	}
end

-- every learnable key of a hero, in panel order
function H.allKeys(heroName)
	local hero = H.heroes[heroName]
	local out = {}
	for wi, w in ipairs(hero and hero.weapons or {}) do
		for _, track in ipairs(H.weaponKinds[w.kind].tracks) do
			out[#out + 1] = "w" .. wi .. "_" .. track
		end
	end
	for _, key in ipairs(H.branchOrder) do
		out[#out + 1] = key
	end
	return out
end

function H.branch(heroName, key)
	local hero = H.heroes[heroName]
	if not hero then
		return nil
	end
	return H.common[key] or hero[key] or H.weaponBranch(heroName, key)
end

function H.metalCost(heroName, key, rank)
	if key == "ult" then
		return H.ULT_METAL[rank] or 0
	elseif key == "a1" or key == "a2" then
		return H.ABILITY_METAL[rank] or 0
	end
	return H.STAT_METAL * rank
end

function H.weaponTier(rankSum)
	local tier = 1
	for i, start in ipairs(H.weaponTiers) do
		if rankSum >= start then
			tier = i
		end
	end
	return tier
end


function H.maxRank(heroName, key)
	local b = H.branch(heroName, key)
	if not b then
		return 0
	end
	return b.maxRank or 3
end

function H.reqLevel(heroName, key, rank)
	local b = H.branch(heroName, key)
	if not b then
		return math.huge
	end
	local req = b.req or (key == "ult" and "ult" or "ability")
	return H.req[req](rank)
end

-- cumulative experience (in own-cost units) to reach a level
function H.xpFor(level, mult)
	if level <= 1 then
		return 0
	end
	return H.XP_TOTAL * ((level - 1) / H.XP_REF) ^ H.XP_EXP / (mult or 1)
end

return H
