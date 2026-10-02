-- Custom heroes (denysfast/bar-game), v19: Diablo-style hero items. Data + pure helpers shared by the items
-- gadget (luarules/gadgets/unit_t4_hero_items.lua), the hero UI and the AI. See CUSTOM.md, "T4-герои", and
-- doc/v19-heroes/SPEC.md section 6.
--
-- Load it standalone:   local I = VFS.Include("luarules/configs/t4_hero_items.lua")
--
-- Items, like Diablo 2:
--   * 12 base types, 4 per category (weapon / defense / utility, 3 slots each = 9 slots). A base has an
--     implicit stat that grows with the item level.
--   * item level (ilvl) 1..5 picks the affix TIER: an affix of tier t has its own name (Tuned -> Charged ->
--     Overcharged -> Devastating -> Cataclysmic) and value range I.TIERS[t] x the affix's top value. An item of
--     ilvl L rolls tier L (65%) or L-1 (35%).
--   * rarity: magic (blue, 1-2 affixes: at most one prefix + one suffix, named "<Prefix> <Base> <of Suffix>"),
--     rare (yellow, 2-3 affixes, a random two-word name), unique (gold, a named item: 1-2 unique bonuses -
--     a special power and a big stat - with random values, + 1-3 random affixes), set (green, a named piece
--     with its own stats + 1 random affix; wearing 2/3/4 pieces of a set unlocks its bonuses).
--   * "fixed" values (implicits, unique bonuses, set piece stats) scale with ilvl by I.fixedScale(L) = 0.5+0.1L
--     (ilvl 5 = the numbers written below).
--
-- Stat keys (what GG.T4HeroItems.mods adds into the hero's mods table m; SPEC section 6):
--   hp (HP, absolute), regen (HP per second), speed (elmos/s), sight (elmos), income (metal/s)       units
--   armor (fraction of damage taken off), damage, range, splash, pierce, power (ability power), cdr,
--   crit (chance), critMult (added to the crit multiplier), lifesteal, thorns, xp                     fractions
--   dtype = { electric, plasma, rocket, laser, flame, rail, emp }   fraction more damage of that type
-- Powers (special effects the items gadget runs itself, by `key`): see I.powerText and the gadget.
--
-- Serialised item (rules params, LuaRules messages): one string, comma-separated fields
--   <base>,<ilvl>,<rarity code m|r|u|s>,<implicit q>,<uid>,<special>,<affixes>
--   special: ""                      magic
--            "r<a>:<b>"              rare: name word indices (I.rareWordsA / I.rareWordsB[category])
--            "u<idx>:<q1>:<q2>..."   unique I.uniques[idx], one quality per unique bonus (powers, then fixed)
--            "s<set>:<piece>:<q>"    set piece I.sets[set].pieces[piece], one quality for its stats
--   affixes: "<affix idx>.<tier>.<q>" joined by "/"   (q = quality 0..99 within the tier range)
--   e.g. "2,5,r,71,1043,r3:9,1.5.88/20.4.12/25.5.40"
-- I.decode(str) -> item table, I.encode(item) -> str, I.name(item), I.lines(item) (tooltip lines with colors),
-- I.stats(item), I.powers(item), I.icon(item, faction), I.price(item), I.salvage(item), I.score(...).

local I = {}

I.SLOTS = 9
I.STASH_SIZE = 36
I.MAX_ILVL = 5
I.PICKUP_RADIUS = 180
I.GROUND_LIFETIME = 300          -- seconds an item lies on the ground
I.DROP_CHANCE = 1 / 150000       -- per metal of a non-hero unit a hero kills (a 30k unit: 20%) ...
I.DROP_MAX = 0.35                -- ... at most
I.PROC_ICD = 1.2                 -- seconds between two procs of the same power on one hero
I.SHOP_SIZE = 9                  -- 3 per category
I.SHOP_REFRESH = 180             -- seconds between two free shelf refreshes
I.SHOP_REFRESH_FEE = 2500        -- metal for a refresh on demand
I.SHOP_ILVL_WEIGHTS = { 45, 35, 20 } -- ilvl 1..3 on the shelf
I.SHOP_RARE_CHANCE = 0.3         -- else magic
I.SHOPS = { arm = "armt4shop", cor = "cort4shop", leg = "legt4shop" }
I.ICON_DIR = "bitmaps/t4heroes/items/"

I.categoryOrder = { "weapon", "defense", "utility" }
I.categories = {
	weapon = { label = "Weapon", slots = { 1, 2, 3 }, color = { 1.0, 0.45, 0.18 }, glyph = "cat_weapon" },
	defense = { label = "Defense", slots = { 4, 5, 6 }, color = { 0.3, 0.72, 1.0 }, glyph = "cat_defense" },
	utility = { label = "Utility", slots = { 7, 8, 9 }, color = { 0.55, 0.95, 0.45 }, glyph = "cat_utility" },
}
I.slotCategory = {}
for cat, c in pairs(I.categories) do
	for _, s in ipairs(c.slots) do
		I.slotCategory[s] = cat
	end
end

local function hex(s)
	return { tonumber(s:sub(2, 3), 16) / 255, tonumber(s:sub(4, 5), 16) / 255, tonumber(s:sub(6, 7), 16) / 255 }
end

-- weight: drop odds (I.rollRarity shifts them with ilvl); salvage: metal by ilvl; price: shop metal by ilvl
I.rarityOrder = { "magic", "rare", "set", "unique" }
I.rarities = {
	magic = { code = "m", label = "Magic", hex = "#6969FF", weight = 60, perIlvl = 0, rank = 1,
		salvage = { 1500, 2500, 4000, 6000, 8500 }, price = { 4000, 7000, 11000, 16000, 22000 } },
	rare = { code = "r", label = "Rare", hex = "#FFFF64", weight = 28, perIlvl = 0.15, rank = 2,
		salvage = { 3000, 5000, 8000, 11000, 15000 }, price = { 9000, 15000, 22000, 30000, 40000 } },
	set = { code = "s", label = "Set", hex = "#00FF00", weight = 6, perIlvl = 0.25, rank = 3,
		salvage = { 5000, 8000, 12000, 17000, 24000 }, price = { 15000, 24000, 36000, 50000, 70000 } },
	unique = { code = "u", label = "Unique", hex = "#C7B377", weight = 6, perIlvl = 0.25, rank = 4,
		salvage = { 6000, 10000, 15000, 21000, 30000 }, price = { 18000, 28000, 42000, 60000, 85000 } },
}
I.rarityByCode = {}
for name, r in pairs(I.rarities) do
	r.name = name
	r.color = hex(r.hex)
	I.rarityByCode[r.code] = name
end
I.colors = { white = { 1, 1, 1 }, grey = { 0.6, 0.6, 0.6 }, blue = hex("#6969FF"), power = { 1.0, 0.55, 0.2 },
	setOff = { 0.45, 0.45, 0.45 }, flavor = { 0.78, 0.7, 0.5 } }

-- tier t of an affix rolls between these shares of its top value
I.TIERS = { { 0.15, 0.30 }, { 0.30, 0.48 }, { 0.48, 0.66 }, { 0.66, 0.83 }, { 0.83, 1.00 } }
function I.fixedScale(ilvl)
	return 0.5 + 0.1 * (ilvl or 5)
end

I.dtypes = { "electric", "plasma", "rocket", "laser", "flame", "rail", "emp" }
I.dtypeLabel = { electric = "electric", plasma = "plasma shell", rocket = "rocket", laser = "laser",
	flame = "flame", rail = "railgun", emp = "EMP" }

-- how a stat reads; `norm` = the value one affix gives at the top of tier 5 (the AI's unit of value);
-- `cap` = most the equipped items together may add (fractions; absolute stats: share of the hero's base)
I.statInfo = {
	damage = { label = "damage", pct = true, norm = 0.10 },
	range = { label = "range", pct = true, norm = 0.06, cap = 0.35 },
	splash = { label = "blast radius", pct = true, norm = 0.12 },
	pierce = { label = "penetration", pct = true, norm = 0.08 },
	critMult = { label = "critical damage", pct = true, norm = 0.30 },
	crit = { label = "critical chance", pct = true, norm = 0.05, cap = 0.4 },
	hp = { label = "HP", norm = 24000 },
	armor = { label = "damage reduction", pct = true, norm = 0.06, cap = 0.5 },
	regen = { label = "HP/s regeneration", norm = 120 },
	power = { label = "ability power", pct = true, norm = 0.10 },
	speed = { label = "speed", norm = 5, cap = 0.5, capBase = "speed" },
	sight = { label = "sight", norm = 280 },
	cdr = { label = "cooldown reduction", pct = true, norm = 0.07, cap = 0.4 },
	lifesteal = { label = "life steal", pct = true, norm = 0.025, cap = 0.15 },
	thorns = { label = "thorns (damage returned)", pct = true, norm = 0.10 },
	xp = { label = "experience", pct = true, norm = 0.10 },
	income = { label = "metal per second", norm = 5 },
	dtype = { label = "damage", pct = true, norm = 0.20 },
}

---------------------------------------------------------------------------------------------------- bases
-- implicit: top value at ilvl 5 (x I.fixedScale)
I.bases = {
	{ id = "targeting_core", name = "Targeting Core", cat = "weapon", implicit = { range = 0.03 },
		art = "a compact fire-control targeting computer with a glowing lens array" },
	{ id = "capacitor_bank", name = "Capacitor Bank", cat = "weapon", implicit = { damage = 0.04 },
		art = "a bank of cylindrical energy capacitors with arcing coils" },
	{ id = "warhead_rack", name = "Warhead Rack", cat = "weapon", implicit = { splash = 0.06 },
		art = "a rack of stubby explosive warheads in a armored cradle" },
	{ id = "rail_accelerator", name = "Rail Accelerator", cat = "weapon", implicit = { pierce = 0.04 },
		art = "a long magnetic rail accelerator barrel segment with glowing rings" },
	{ id = "armor_plating", name = "Armor Plating", cat = "defense", implicit = { hp = 12000 },
		art = "a thick layered composite armor plate with rivets" },
	{ id = "deflector_array", name = "Deflector Array", cat = "defense", implicit = { armor = 0.03 },
		art = "a hexagonal deflector field emitter array projecting a faint energy hex shield" },
	{ id = "nanite_reservoir", name = "Nanite Reservoir", cat = "defense", implicit = { regen = 60 },
		art = "a glass canister of glowing repair nanites in a metal frame" },
	{ id = "reactive_shell", name = "Reactive Shell", cat = "defense", implicit = { thorns = 0.05 },
		art = "spiked explosive reactive armor bricks on a hull section" },
	{ id = "servo_actuator", name = "Servo Actuator", cat = "utility", implicit = { speed = 3 },
		art = "a heavy robotic leg servo actuator joint with pistons" },
	{ id = "sensor_mast", name = "Sensor Mast", cat = "utility", implicit = { sight = 150 },
		art = "a folding radar and sensor mast with a rotating dish" },
	{ id = "tactical_processor", name = "Tactical Processor", cat = "utility", implicit = { cdr = 0.04 },
		art = "a glowing tactical processor chip module with circuit traces" },
	{ id = "fusion_cell", name = "Fusion Cell", cat = "utility", implicit = { power = 0.05 },
		art = "a miniature fusion reactor cell with a bright glowing core" },
}

---------------------------------------------------------------------------------------------------- affixes
-- kind prefix|suffix; names per tier 1..5; stats: top value at tier 5; w: weight per category
local function dt(kind, v)
	return { dtype = { [kind] = v } }
end
I.affixes = {
	{ id = "dmg", kind = "prefix", stats = { damage = 0.10 }, w = { weapon = 5, utility = 1 },
		names = { "Tuned", "Charged", "Overcharged", "Devastating", "Cataclysmic" } },
	{ id = "rng", kind = "prefix", stats = { range = 0.06 }, w = { weapon = 3, utility = 3 },
		names = { "Extended", "Long-Barrel", "Far-Reaching", "Horizon", "Orbital" } },
	{ id = "aoe", kind = "prefix", stats = { splash = 0.12 }, w = { weapon = 3 },
		names = { "Blasting", "Shattering", "Cratering", "Seismic", "Tectonic" } },
	{ id = "prc", kind = "prefix", stats = { pierce = 0.08 }, w = { weapon = 3 },
		names = { "Piercing", "Penetrating", "Lancing", "Impaling", "Skewering" } },
	{ id = "ele", kind = "prefix", stats = dt("electric", 0.20), w = { weapon = 2 },
		names = { "Static", "Arcing", "Voltaic", "Thunderous", "Tempest" } },
	{ id = "pla", kind = "prefix", stats = dt("plasma", 0.20), w = { weapon = 2 },
		names = { "Glowing", "Plasma", "Superheated", "Solar", "Stellar" } },
	{ id = "rkt", kind = "prefix", stats = dt("rocket", 0.20), w = { weapon = 2 },
		names = { "Guided", "Seeking", "Warhead", "Barrage", "Armageddon" } },
	{ id = "lsr", kind = "prefix", stats = dt("laser", 0.20), w = { weapon = 2 },
		names = { "Focused", "Coherent", "Photon", "Prismatic", "Gamma" } },
	{ id = "flm", kind = "prefix", stats = dt("flame", 0.20), w = { weapon = 2 },
		names = { "Smoldering", "Burning", "Incendiary", "Infernal", "Hellfire" } },
	{ id = "rai", kind = "prefix", stats = dt("rail", 0.20), w = { weapon = 2 },
		names = { "Magnetic", "Accelerated", "Hypersonic", "Railborne", "Relativistic" } },
	{ id = "emp", kind = "prefix", stats = dt("emp", 0.20), w = { weapon = 1 },
		names = { "Jamming", "Disruptive", "Ionized", "Paralytic", "Blackout" } },
	{ id = "cdm", kind = "prefix", stats = { critMult = 0.30 }, w = { weapon = 2 },
		names = { "Cruel", "Brutal", "Savage", "Merciless", "Executioner's" } },
	{ id = "hp", kind = "prefix", stats = { hp = 24000 }, w = { defense = 5, utility = 1 },
		names = { "Plated", "Reinforced", "Fortified", "Bastion", "Titanic" } },
	{ id = "arm", kind = "prefix", stats = { armor = 0.06 }, w = { defense = 4 },
		names = { "Hardened", "Deflecting", "Warded", "Impervious", "Adamant" } },
	{ id = "blw", kind = "prefix", stats = { hp = 12000, armor = 0.03 }, w = { defense = 3 },
		names = { "Sturdy", "Stalwart", "Citadel", "Fortress", "Monolith" } },
	{ id = "pow", kind = "prefix", stats = { power = 0.10 }, w = { utility = 4, weapon = 1 },
		names = { "Resonant", "Empowered", "Ascendant", "Mythic", "Transcendent" } },
	{ id = "nim", kind = "prefix", stats = { speed = 3, cdr = 0.03 }, w = { utility = 3 },
		names = { "Nimble", "Swift", "Agile", "Fleet", "Quicksilver" } },
	{ id = "reg", kind = "suffix", stats = { regen = 120 }, w = { defense = 4, utility = 1 },
		names = { "of Nanites", "of Repair", "of Regrowth", "of Restoration", "of Rebirth" } },
	{ id = "spd", kind = "suffix", stats = { speed = 5 }, w = { utility = 4, defense = 1 },
		names = { "of Haste", "of the Courier", "of the Gale", "of the Comet", "of Lightspeed" } },
	{ id = "sig", kind = "suffix", stats = { sight = 280 }, w = { utility = 3 },
		names = { "of Sight", "of the Scout", "of the Hawk", "of the Watchtower", "of Omniscience" } },
	{ id = "cdr", kind = "suffix", stats = { cdr = 0.07 }, w = { utility = 4, weapon = 1 },
		names = { "of Readiness", "of Alacrity", "of Swiftness", "of Celerity", "of Chronos" } },
	{ id = "crt", kind = "suffix", stats = { crit = 0.05 }, w = { weapon = 3, utility = 1 },
		names = { "of Precision", "of Accuracy", "of the Marksman", "of the Sniper", "of Deadeye" } },
	{ id = "lst", kind = "suffix", stats = { lifesteal = 0.025 }, w = { weapon = 2, defense = 2 },
		names = { "of the Leech", "of Siphoning", "of the Lamprey", "of Draining", "of the Vampire" } },
	{ id = "thn", kind = "suffix", stats = { thorns = 0.10 }, w = { defense = 3 },
		names = { "of Spikes", "of Thorns", "of Barbs", "of Retaliation", "of Retribution" } },
	{ id = "xp", kind = "suffix", stats = { xp = 0.10 }, w = { utility = 2 },
		names = { "of Learning", "of Insight", "of Wisdom", "of the Sage", "of Enlightenment" } },
	{ id = "inc", kind = "suffix", stats = { income = 5 }, w = { utility = 2 },
		names = { "of Salvage", "of Scrap", "of Industry", "of Wealth", "of the Magnate" } },
	{ id = "lif", kind = "suffix", stats = { hp = 18000 }, w = { defense = 3, weapon = 1, utility = 1 },
		names = { "of the Jackal", "of the Fox", "of the Wolf", "of the Tiger", "of the Mammoth" } },
}

-- rare names: "<A> <B>", B by category
I.rareWordsA = { "Grim", "Storm", "Dread", "Havoc", "Rune", "Blood", "Doom", "Iron", "Void", "Ember", "Viper",
	"Wraith", "Titan", "Sky", "Bone", "Hate", "Plague", "Star", "Ghoul", "Raven", "Steel", "Chaos", "Soul", "Death" }
I.rareWordsB = {
	weapon = { "Bite", "Fang", "Spike", "Song", "Scourge", "Thirst", "Call", "Sting", "Flay", "Edge", "Wrack", "Gnash" },
	defense = { "Ward", "Shell", "Hide", "Shroud", "Aegis", "Bulwark", "Carapace", "Coat", "Veil", "Wall", "Mantle", "Guard" },
	utility = { "Eye", "Heart", "Stride", "Mind", "Spark", "Whisper", "Engine", "Charm", "Gaze", "Pulse", "Wheel", "Lens" },
}

---------------------------------------------------------------------------------------------------- powers
-- A power is { key = <gadget effect>, roll = { lo, hi } (top values at ilvl 5, x I.fixedScale), fixed params }.
-- Set bonus powers have `v` instead of `roll`.
--   chain      on hit, `chance`: lightning arcs for v damage, jumps to `jumps` more enemies within `radius`
--   blastKill  a unit the hero kills explodes for v x its max HP (at most `cap`) within `radius`
--   slayer     +v damage to heroes and to units worth `minCost` metal or more
--   execute    +v damage to units under `below` of their health
--   orbital    every `period` s a beam from the sky hits the hero's target (or the nearest enemy in range) for v
--   lowShield  dropping under `below` health raises a shield of v x max HP for `duration` s (cooldown)
--   cheatDeath lethal damage instead leaves the hero at v of its health, invulnerable `invuln` s (cooldown)
--   lifeOnHit  every hit heals v HP (at most `perSecond` hits a second)
--   reflect    v of the damage taken is dealt back to the attacker
--   guardAura  allies within `radius` (the hero too) take v less damage
--   warAura    allies within `radius` (the hero too) deal v more damage
--   mark       hits mark the target for `duration` s: it takes v more damage from everyone
--   souls      every kill adds a soul (max `stacks`): +v damage per soul; one fades every `decay` s without a kill
--   staticWake every `period` s arcs strike `targets` enemies within `radius` for v damage
--   blink      ACTIVE ("Use"): jump v elmos forward (toward the move goal or the facing); `cooldown`
I.powerInfo = {
	chain = { label = "Chain Arc", pct = false, text = function(v, p)
		return string.format("%d%% chance on hit: lightning arcs for %s damage to %d more enemies", p.chance * 100, I.fmtNum(v), p.jumps)
	end },
	blastKill = { label = "Pyre", text = function(v, p)
		return string.format("Units it kills explode for %d%% of their health (max %s) within %d", v * 100 + 0.5, I.fmtNum(p.cap), p.radius)
	end },
	slayer = { label = "Giant Slayer", text = function(v, p)
		return string.format("+%d%% damage to heroes and units worth %s+ metal", v * 100 + 0.5, I.fmtNum(p.minCost))
	end },
	execute = { label = "Execute", text = function(v, p)
		return string.format("+%d%% damage to units under %d%% health", v * 100 + 0.5, p.below * 100)
	end },
	orbital = { label = "Sunforge", text = function(v, p)
		return string.format("Every %d s a sky beam strikes its target for %s damage", p.period, I.fmtNum(v))
	end },
	lowShield = { label = "Last Stand", text = function(v, p)
		return string.format("Under %d%% health: a shield of %d%% max HP for %d s (cooldown %d s)", p.below * 100, v * 100 + 0.5, p.duration, p.cooldown)
	end },
	cheatDeath = { label = "Rebirth", text = function(v, p)
		return string.format("Lethal damage leaves it at %d%% health, invulnerable %d s (cooldown %d s)", v * 100 + 0.5, p.invuln, p.cooldown)
	end },
	lifeOnHit = { label = "Life on Hit", text = function(v, p)
		return string.format("+%s HP per hit", I.fmtNum(v))
	end },
	reflect = { label = "Reflect", text = function(v, p)
		return string.format("Reflects %d%% of damage taken to the attacker", v * 100 + 0.5)
	end },
	guardAura = { label = "Guard Aura", text = function(v, p)
		return string.format("Aura: allies within %d take %d%% less damage", p.radius, v * 100 + 0.5)
	end },
	warAura = { label = "War Aura", text = function(v, p)
		return string.format("Aura: allies within %d deal %d%% more damage", p.radius, v * 100 + 0.5)
	end },
	mark = { label = "Mark", text = function(v, p)
		return string.format("Hits mark the target: +%d%% damage taken from all for %d s", v * 100 + 0.5, p.duration)
	end },
	souls = { label = "Souls", text = function(v, p)
		return string.format("Kills gather souls (max %d): +%.1f%% damage each", p.stacks, v * 100)
	end },
	staticWake = { label = "Static Wake", text = function(v, p)
		return string.format("Every %d s arcs strike %d enemies within %d for %s damage", p.period, p.targets, p.radius, I.fmtNum(v))
	end },
	blink = { label = "Blink", active = true, text = function(v, p)
		return string.format("Use: blink %d forward (cooldown %d s)", v, p.cooldown)
	end },
}

---------------------------------------------------------------------------------------------------- uniques
-- base: base id; powers: rolled specials; fixed: { stat = { lo, hi } } rolled big stats; affixes: random 1-3
I.uniques = {
	{ id = "stormcaller", name = "Stormcaller", base = "capacitor_bank",
		powers = { { key = "chain", roll = { 1000, 1800 }, chance = 0.15, jumps = 3, radius = 450 } },
		fixed = { dtype = { electric = { 0.15, 0.30 } } },
		flavor = "The coil remembers every storm it drank.",
		art = "a crackling storm capacitor coil wrapped in blue lightning, legendary relic" },
	{ id = "pyre", name = "Pyre of the Fallen", base = "warhead_rack",
		powers = { { key = "blastKill", roll = { 0.20, 0.35 }, radius = 300, cap = 15000 } },
		fixed = { splash = { 0.10, 0.20 } },
		flavor = "Nothing it kills dies quietly.",
		art = "a rack of burning warheads wreathed in orange fire and skulls of melted metal, legendary relic" },
	{ id = "giantsbane", name = "Giantsbane", base = "rail_accelerator",
		powers = { { key = "slayer", roll = { 0.20, 0.35 }, minCost = 5000 } },
		fixed = { pierce = { 0.05, 0.10 } },
		flavor = "Forged to fell the walking fortresses.",
		art = "a massive golden railgun barrel engraved with runes, legendary relic" },
	{ id = "verdict", name = "The Final Verdict", base = "targeting_core",
		powers = { { key = "execute", roll = { 0.25, 0.40 }, below = 0.30 } },
		fixed = { crit = { 0.04, 0.08 } },
		flavor = "Judgement is passed in the red of the health bar.",
		art = "a blood red targeting reticle core shaped like a gavel, legendary relic" },
	{ id = "sunforge", name = "Sunforge Lens", base = "targeting_core",
		powers = { { key = "orbital", roll = { 5000, 9000 }, period = 6 } },
		fixed = { dtype = { laser = { 0.15, 0.25 } } },
		flavor = "A satellite answers every glance.",
		art = "a golden sun lens focusing a beam of white-hot light downward, legendary relic" },
	{ id = "last_bastion", name = "Last Bastion", base = "armor_plating",
		powers = { { key = "lowShield", roll = { 0.15, 0.25 }, below = 0.35, duration = 8, cooldown = 60 } },
		fixed = { hp = { 15000, 30000 } },
		flavor = "When the hull breaks, the wall rises.",
		art = "a tower shield of golden armor plates with a glowing energy dome, legendary relic" },
	{ id = "phoenix_heart", name = "Phoenix Heart", base = "nanite_reservoir",
		powers = { { key = "cheatDeath", roll = { 0.30, 0.45 }, cooldown = 150, invuln = 2 } },
		fixed = { regen = { 60, 120 } },
		flavor = "It has burned out before. It will burn again.",
		art = "a burning phoenix shaped reactor heart of flame and nanites, legendary relic" },
	{ id = "bloodforged", name = "Bloodforged Carapace", base = "deflector_array",
		powers = { { key = "lifeOnHit", roll = { 150, 300 }, perSecond = 6 } },
		fixed = { lifesteal = { 0.01, 0.02 } },
		flavor = "Every hit it lands is a meal.",
		art = "a crimson organic-looking armored carapace with pulsing red veins, legendary relic" },
	{ id = "thornwall", name = "Thornwall", base = "reactive_shell",
		powers = { { key = "reflect", roll = { 0.20, 0.35 } } },
		fixed = { armor = { 0.03, 0.06 } },
		flavor = "Strike it and bleed.",
		art = "a hull plate bristling with long glowing metal thorns, legendary relic" },
	{ id = "bulwark", name = "Bulwark Beacon", base = "deflector_array",
		powers = { { key = "guardAura", roll = { 0.08, 0.14 }, radius = 800 } },
		fixed = { armor = { 0.02, 0.04 } },
		flavor = "The army breathes easier in its light.",
		art = "a tall beacon projecting a wide blue hexagonal shield over soldiers, legendary relic" },
	{ id = "chronoshift", name = "Chronoshift Drive", base = "servo_actuator",
		powers = { { key = "blink", roll = { 600, 900 }, cooldown = 25 } },
		fixed = { speed = { 4, 8 } },
		flavor = "It arrives a moment before it left.",
		art = "a servo actuator surrounded by a swirling time portal and clock rings, legendary relic" },
	{ id = "oracle", name = "Oracle Eye", base = "sensor_mast",
		powers = { { key = "mark", roll = { 0.08, 0.15 }, duration = 5 } },
		fixed = { sight = { 300, 500 } },
		flavor = "What it sees, everything strikes.",
		art = "a giant glowing mechanical eye on a sensor mast, legendary relic" },
	{ id = "soul_harvester", name = "Soul Harvester", base = "fusion_cell",
		powers = { { key = "souls", roll = { 0.010, 0.018 }, stacks = 20, decay = 3 } },
		fixed = { xp = { 0.15, 0.30 } },
		flavor = "The reactor burns on the last breath of the fallen.",
		art = "a fusion cell containing swirling ghostly green souls, legendary relic" },
	{ id = "warlord", name = "Warlord's Standard", base = "tactical_processor",
		powers = { { key = "warAura", roll = { 0.08, 0.14 }, radius = 900 } },
		fixed = { cdr = { 0.04, 0.08 } },
		flavor = "Where the standard goes, the army follows.",
		art = "a holographic war banner standard projected from a processor, legendary relic" },
	{ id = "static_wake", name = "Static Wake", base = "fusion_cell",
		powers = { { key = "staticWake", roll = { 1200, 2000 }, period = 2, targets = 3, radius = 550 } },
		fixed = { power = { 0.06, 0.12 } },
		flavor = "The air around it never stops crackling.",
		art = "a fusion cell radiating a ring of purple static lightning, legendary relic" },
}

---------------------------------------------------------------------------------------------------- sets
-- pieces: own stats (top values, x I.fixedScale x quality 85..100%) + 1 random affix;
-- bonuses[n]: active while the hero wears n or more pieces of the set (stats and powers with fixed `v`)
I.sets = {
	{ id = "tempest", name = "Tempest Regalia",
		pieces = {
			{ id = "tempest_coil", name = "Tempest Coil", base = "capacitor_bank", stats = { dtype = { electric = 0.12 }, damage = 0.04 },
				art = "an ornate electric coil in green and silver with storm clouds" },
			{ id = "tempest_mantle", name = "Tempest Mantle", base = "deflector_array", stats = { armor = 0.03, hp = 10000 },
				art = "an ornate green and silver deflector mantle crackling with lightning" },
			{ id = "tempest_striders", name = "Tempest Striders", base = "servo_actuator", stats = { speed = 4, cdr = 0.03 },
				art = "ornate green and silver mechanical leg servos trailing lightning" },
		},
		bonuses = {
			[2] = { stats = { dtype = { electric = 0.15 }, speed = 4 } },
			[3] = { stats = { damage = 0.08 }, powers = { { key = "chain", v = 1400, chance = 0.12, jumps = 4, radius = 500 } } },
		} },
	{ id = "juggernaut", name = "Juggernaut's Bulwark",
		pieces = {
			{ id = "jugg_plate", name = "Juggernaut Plate", base = "armor_plating", stats = { hp = 18000 },
				art = "a colossal green-tinted armor plate with a ram skull emblem" },
			{ id = "jugg_shell", name = "Juggernaut Shell", base = "reactive_shell", stats = { thorns = 0.06, armor = 0.02 },
				art = "a spiked green-tinted reactive armor shell with a ram skull emblem" },
			{ id = "jugg_core", name = "Juggernaut Core", base = "nanite_reservoir", stats = { regen = 80 },
				art = "a heavy green-tinted nanite reactor core with a ram skull emblem" },
			{ id = "jugg_treads", name = "Juggernaut Treads", base = "servo_actuator", stats = { speed = 3, hp = 8000 },
				art = "massive green-tinted tank treads with a ram skull emblem" },
		},
		bonuses = {
			[2] = { stats = { hp = 20000 } },
			[3] = { stats = { armor = 0.08, regen = 100 } },
			[4] = { powers = { { key = "lowShield", v = 0.25, below = 0.40, duration = 8, cooldown = 50 },
				{ key = "reflect", v = 0.15 } } },
		} },
	{ id = "hunter", name = "Hunter's Array",
		pieces = {
			{ id = "hunter_scope", name = "Hunter's Scope", base = "targeting_core", stats = { range = 0.03, crit = 0.03 },
				art = "a long hunting scope with a green crosshair glow" },
			{ id = "hunter_lance", name = "Hunter's Lance", base = "rail_accelerator", stats = { dtype = { rail = 0.12 }, pierce = 0.04 },
				art = "a sleek green-accented railgun lance barrel" },
			{ id = "hunter_eye", name = "Hunter's Eye", base = "sensor_mast", stats = { sight = 250 },
				art = "a predator-like sensor mast with a green glowing eye" },
		},
		bonuses = {
			[2] = { stats = { range = 0.05 } },
			[3] = { stats = { crit = 0.05 }, powers = { { key = "slayer", v = 0.20, minCost = 5000 } } },
		} },
	{ id = "inferno", name = "Inferno Covenant",
		pieces = {
			{ id = "inferno_rack", name = "Inferno Rack", base = "warhead_rack", stats = { dtype = { flame = 0.12 }, splash = 0.05 },
				art = "a rack of incendiary warheads glowing green-hot" },
			{ id = "inferno_cell", name = "Inferno Cell", base = "fusion_cell", stats = { dtype = { plasma = 0.12 }, power = 0.04 },
				art = "a fusion cell full of green-tinted plasma fire" },
			{ id = "inferno_shell", name = "Inferno Shell", base = "reactive_shell", stats = { thorns = 0.05, hp = 8000 },
				art = "a molten reactive armor shell with green flames" },
		},
		bonuses = {
			[2] = { stats = { dtype = { plasma = 0.15, flame = 0.15, rocket = 0.15 } } },
			[3] = { stats = { splash = 0.10 }, powers = { { key = "blastKill", v = 0.25, radius = 320, cap = 15000 } } },
		} },
	{ id = "fortune", name = "Scavenger's Fortune",
		pieces = {
			{ id = "fortune_ledger", name = "Scavenger's Ledger", base = "tactical_processor", stats = { income = 3, cdr = 0.03 },
				art = "a processor module covered with scrap metal coins and green glow" },
			{ id = "fortune_furnace", name = "Scavenger's Furnace", base = "fusion_cell", stats = { income = 3, xp = 0.08 },
				art = "a small salvage furnace cell melting scrap with green glow" },
		},
		bonuses = {
			[2] = { stats = { income = 6, xp = 0.15 } },
		} },
}

---------------------------------------------------------------------------------------------------- indices
I.baseIndex, I.affixIndex, I.uniqueIndex, I.setIndex, I.pieceIndex = {}, {}, {}, {}, {}
I.basesByCat = { weapon = {}, defense = {}, utility = {} }
for i, b in ipairs(I.bases) do
	b.index = i
	I.baseIndex[b.id] = i
	local t = I.basesByCat[b.cat]
	t[#t + 1] = i
end
for i, a in ipairs(I.affixes) do
	a.index = i
	I.affixIndex[a.id] = i
end
I.uniquesByCat = { weapon = {}, defense = {}, utility = {} }
for i, u in ipairs(I.uniques) do
	u.index = i
	I.uniqueIndex[u.id] = i
	u.cat = I.bases[I.baseIndex[u.base]].cat
	local t = I.uniquesByCat[u.cat]
	t[#t + 1] = i
end
I.piecesByCat = { weapon = {}, defense = {}, utility = {} }
for si, s in ipairs(I.sets) do
	s.index = si
	I.setIndex[s.id] = si
	for pi, p in ipairs(s.pieces) do
		p.index = pi
		p.set = si
		p.cat = I.bases[I.baseIndex[p.base]].cat
		I.pieceIndex[p.id] = { si, pi }
		local t = I.piecesByCat[p.cat]
		t[#t + 1] = { si, pi }
	end
end

---------------------------------------------------------------------------------------------------- formatting
function I.fmtNum(v)
	v = math.floor(v + 0.5)
	local s = tostring(math.abs(v))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (v < 0 and "-" or "") .. out
end

function I.fmtStat(key, v, dkind)
	local info = I.statInfo[key]
	if key == "dtype" then
		return string.format("+%d%% %s damage", v * 100 + 0.5, I.dtypeLabel[dkind] or dkind)
	end
	if not info then
		return key .. " " .. tostring(v)
	end
	if info.pct then
		local p = v * 100
		if p < 10 and math.abs(p - math.floor(p + 0.5)) > 0.05 then
			return string.format("+%.1f%% %s", p, info.label)
		end
		return string.format("+%d%% %s", p + 0.5, info.label)
	end
	if key == "speed" or key == "income" then
		return string.format("+%.1f %s", v, info.label)
	end
	return "+" .. I.fmtNum(v) .. " " .. info.label
end

-- rounding of rolled values: absolute stats to nice numbers, fractions to 0.1%
local function roundStat(key, v)
	if key == "hp" then
		return math.floor(v / 100 + 0.5) * 100
	elseif key == "regen" or key == "sight" then
		return math.floor(v + 0.5)
	elseif key == "speed" or key == "income" then
		return math.floor(v * 10 + 0.5) / 10
	end
	return math.floor(v * 1000 + 0.5) / 1000
end
I.roundStat = roundStat

local function lerp(a, b, t)
	return a + (b - a) * t
end

---------------------------------------------------------------------------------------------------- encode / decode
function I.encode(it)
	local special = ""
	if it.rarity == "rare" then
		special = string.format("r%d:%d", it.rname[1], it.rname[2])
	elseif it.rarity == "unique" then
		special = "u" .. it.unique .. (#it.uq > 0 and (":" .. table.concat(it.uq, ":")) or "")
	elseif it.rarity == "set" then
		special = string.format("s%d:%d:%d", it.set, it.piece, it.sq or 50)
	end
	local aff = {}
	for i, a in ipairs(it.affixes) do
		aff[i] = a[1] .. "." .. a[2] .. "." .. a[3]
	end
	return string.format("%d,%d,%s,%d,%d,%s,%s", it.base, it.ilvl, I.rarities[it.rarity].code, it.impQ or 50, it.uid or 0,
		special, table.concat(aff, "/"))
end

function I.decode(str)
	if type(str) ~= "string" or str == "" then
		return nil
	end
	local b, l, r, q, uid, special, aff = str:match("^(%d+),(%d+),(%a),(%d+),(%d+),([^,]*),(.*)$")
	b, l, q, uid = tonumber(b), tonumber(l), tonumber(q), tonumber(uid)
	local rarity = r and I.rarityByCode[r]
	if not b or not I.bases[b] or not rarity then
		return nil
	end
	local it = { base = b, ilvl = math.max(1, math.min(I.MAX_ILVL, l)), rarity = rarity, impQ = q, uid = uid, affixes = {},
		cat = I.bases[b].cat, str = str }
	local kind = special:sub(1, 1)
	local nums = {}
	for n in special:sub(2):gmatch("%d+") do
		nums[#nums + 1] = tonumber(n)
	end
	if rarity == "rare" then
		it.rname = { nums[1] or 1, nums[2] or 1 }
	elseif rarity == "unique" then
		if kind ~= "u" or not I.uniques[nums[1] or 0] then
			return nil
		end
		it.unique = nums[1]
		it.uq = {}
		for i = 2, #nums do
			it.uq[#it.uq + 1] = nums[i]
		end
	elseif rarity == "set" then
		local s = I.sets[nums[1] or 0]
		if kind ~= "s" or not s or not s.pieces[nums[2] or 0] then
			return nil
		end
		it.set, it.piece, it.sq = nums[1], nums[2], nums[3] or 50
	end
	for a, t, aq in aff:gmatch("(%d+)%.(%d+)%.(%d+)") do
		a, t = tonumber(a), tonumber(t)
		if I.affixes[a] and t >= 1 and t <= 5 then
			it.affixes[#it.affixes + 1] = { a, t, tonumber(aq) }
		end
	end
	return it
end

---------------------------------------------------------------------------------------------------- values
-- add a stats table ({ key = v, dtype = { kind = v } }) times `mult` into `out`
local function addStats(out, stats, mult, valueOf)
	for k, v in pairs(stats) do
		if k == "dtype" then
			out.dtype = out.dtype or {}
			for kind, dv in pairs(v) do
				local x = valueOf and valueOf("dtype", dv) or dv * mult
				out.dtype[kind] = (out.dtype[kind] or 0) + x
			end
		else
			local x = valueOf and valueOf(k, v) or v * mult
			out[k] = (out[k] or 0) + x
		end
	end
	return out
end
I.addStats = addStats

-- the value of one affix of an item: { key = v, dtype = {...} }
function I.affixStats(a)
	local def = I.affixes[a[1]]
	local tr = I.TIERS[a[2]]
	local share = lerp(tr[1], tr[2], (a[3] or 50) / 99)
	return addStats({}, def.stats, 1, function(k, v)
		return roundStat(k, v * share)
	end)
end

function I.implicitStats(it)
	local b = I.bases[it.base]
	local s = I.fixedScale(it.ilvl) * lerp(0.8, 1.0, (it.impQ or 50) / 99)
	return addStats({}, b.implicit, 1, function(k, v)
		return roundStat(k, v * s)
	end)
end

-- the rolled unique bonuses: powers (with v) and fixed stats
function I.uniqueRolls(it)
	local u = I.uniques[it.unique]
	local scale = I.fixedScale(it.ilvl)
	local qi = 0
	local powers, stats = {}, {}
	for _, p in ipairs(u.powers or {}) do
		qi = qi + 1
		local q = (it.uq[qi] or 50) / 99
		local v = lerp(p.roll[1], p.roll[2], q) * scale
		if p.key == "blink" then
			v = math.floor(v + 0.5)
		elseif v >= 50 then
			v = math.floor(v / 10 + 0.5) * 10
		else
			v = math.floor(v * 1000 + 0.5) / 1000
		end
		powers[#powers + 1] = { key = p.key, v = v, p = p, src = "u" .. u.index }
	end
	-- fixed stats in a stable order (by key)
	local keys = {}
	for k in pairs(u.fixed or {}) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local r = u.fixed[k]
		if k == "dtype" then
			local kinds = {}
			for kind in pairs(r) do
				kinds[#kinds + 1] = kind
			end
			table.sort(kinds)
			for _, kind in ipairs(kinds) do
				qi = qi + 1
				local q = (it.uq[qi] or 50) / 99
				stats.dtype = stats.dtype or {}
				stats.dtype[kind] = roundStat("dtype", lerp(r[kind][1], r[kind][2], q) * scale)
			end
		else
			qi = qi + 1
			local q = (it.uq[qi] or 50) / 99
			stats[k] = roundStat(k, lerp(r[1], r[2], q) * scale)
		end
	end
	return powers, stats
end

-- number of rolled qualities a unique needs
function I.uniqueRollCount(u)
	local n = #(u.powers or {})
	for k, r in pairs(u.fixed or {}) do
		if k == "dtype" then
			for _ in pairs(r) do
				n = n + 1
			end
		else
			n = n + 1
		end
	end
	return n
end

function I.pieceStats(it)
	local p = I.sets[it.set].pieces[it.piece]
	local s = I.fixedScale(it.ilvl) * lerp(0.85, 1.0, (it.sq or 50) / 99)
	return addStats({}, p.stats, 1, function(k, v)
		return roundStat(k, v * s)
	end)
end

-- all stats of one item (no set bonuses): { key = v, dtype = { kind = v } }
function I.stats(it)
	local out = {}
	addStats(out, I.implicitStats(it), 1)
	if it.rarity == "unique" then
		local _, st = I.uniqueRolls(it)
		addStats(out, st, 1)
	elseif it.rarity == "set" then
		addStats(out, I.pieceStats(it), 1)
	end
	for _, a in ipairs(it.affixes) do
		addStats(out, I.affixStats(a), 1)
	end
	return out
end

-- powers of one item (no set bonuses): { { key, v, p, src } }
function I.powers(it)
	if it.rarity == "unique" then
		return (I.uniqueRolls(it))
	end
	return {}
end

-- set bonuses for `count` worn pieces of set `si`: stats, powers (each { key, v, p, src })
function I.setBonus(si, count)
	local s = I.sets[si]
	local stats, powers = {}, {}
	for n = 2, 4 do
		local b = s.bonuses[n]
		if b and count >= n then
			addStats(stats, b.stats or {}, 1)
			for _, p in ipairs(b.powers or {}) do
				powers[#powers + 1] = { key = p.key, v = p.v, p = p, src = "s" .. si .. "_" .. n }
			end
		end
	end
	return stats, powers
end

---------------------------------------------------------------------------------------------------- names, text
function I.baseName(it)
	return I.bases[it.base].name
end

function I.name(it)
	if it.rarity == "unique" then
		return I.uniques[it.unique].name
	elseif it.rarity == "set" then
		return I.sets[it.set].pieces[it.piece].name
	elseif it.rarity == "rare" then
		local wa = I.rareWordsA[it.rname[1]] or "Grim"
		local wbList = I.rareWordsB[it.cat]
		return wa .. " " .. (wbList[it.rname[2]] or wbList[1])
	end
	local pre, suf
	for _, a in ipairs(it.affixes) do
		local def = I.affixes[a[1]]
		if def.kind == "prefix" then
			pre = pre or def.names[a[2]]
		else
			suf = suf or def.names[a[2]]
		end
	end
	local n = I.baseName(it)
	if pre then
		n = pre .. " " .. n
	end
	if suf then
		n = n .. " " .. suf
	end
	return n
end

function I.color(it)
	return I.rarities[it.rarity].color
end

local function statLines(lines, stats, color, kind)
	local keys = {}
	for k in pairs(stats) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	for _, k in ipairs(keys) do
		if k == "dtype" then
			local kinds = {}
			for dk in pairs(stats.dtype) do
				kinds[#kinds + 1] = dk
			end
			table.sort(kinds)
			for _, dk in ipairs(kinds) do
				lines[#lines + 1] = { text = I.fmtStat("dtype", stats.dtype[dk], dk), color = color, kind = kind }
			end
		else
			lines[#lines + 1] = { text = I.fmtStat(k, stats[k]), color = color, kind = kind }
		end
	end
end

function I.powerText(pw)
	local info = I.powerInfo[pw.key]
	return info and info.text(pw.v, pw.p) or pw.key
end

-- tooltip lines: { { text =, color = {r,g,b}, kind = }, ... }; kind: name | base | info | implicit (draw a separator
-- after these) | power | unique | piece | affix | setname | setpiece | setbonus | flavor.
-- wornPieces: optional { [setIdx] = count } lights the active set bonuses
function I.lines(it, wornPieces)
	local rc = I.color(it)
	local lines = { { text = I.name(it), color = rc, kind = "name" } }
	if it.rarity ~= "magic" then
		lines[#lines + 1] = { text = I.baseName(it), color = rc, kind = "base" }
	end
	lines[#lines + 1] = { text = string.format("%s %s - item level %d", I.rarities[it.rarity].label,
		I.categories[it.cat].label:lower(), it.ilvl), color = I.colors.grey, kind = "info" }
	statLines(lines, I.implicitStats(it), I.colors.white, "implicit")
	if it.rarity == "unique" then
		local pw, st = I.uniqueRolls(it)
		for _, p in ipairs(pw) do
			lines[#lines + 1] = { text = I.powerText(p), color = I.colors.power, kind = "power" }
		end
		statLines(lines, st, rc, "unique")
	elseif it.rarity == "set" then
		statLines(lines, I.pieceStats(it), rc, "piece")
	end
	local aff = {}
	for _, a in ipairs(it.affixes) do
		addStats(aff, I.affixStats(a), 1)
	end
	statLines(lines, aff, I.colors.blue, "affix")
	if it.rarity == "set" then
		local s = I.sets[it.set]
		local have = wornPieces and wornPieces[it.set] or 0
		lines[#lines + 1] = { text = s.name, color = rc, kind = "setname" }
		for _, p in ipairs(s.pieces) do
			lines[#lines + 1] = { text = "  " .. p.name, color = I.colors.grey, kind = "setpiece" }
		end
		for n = 2, 4 do
			local b = s.bonuses[n]
			if b then
				local col = have >= n and rc or I.colors.setOff
				local sub = {}
				statLines(sub, b.stats or {}, col, "setbonus")
				for _, p in ipairs(b.powers or {}) do
					sub[#sub + 1] = { text = I.powerText({ key = p.key, v = p.v, p = p }), color = col, kind = "setbonus" }
				end
				for _, l in ipairs(sub) do
					l.text = "(" .. n .. ") " .. l.text
					l.pieces = n
					lines[#lines + 1] = l
				end
			end
		end
	end
	if it.rarity == "unique" and I.uniques[it.unique].flavor then
		lines[#lines + 1] = { text = I.uniques[it.unique].flavor, color = I.colors.flavor, kind = "flavor" }
	end
	return lines
end

-- icon path; faction "arm" | "cor" | "leg" (bases have one icon per faction; uniques and set pieces their own)
function I.icon(it, faction)
	if it.rarity == "unique" then
		return I.ICON_DIR .. "u_" .. I.uniques[it.unique].id .. ".png"
	elseif it.rarity == "set" then
		return I.ICON_DIR .. "s_" .. I.sets[it.set].pieces[it.piece].id .. ".png"
	end
	return I.ICON_DIR .. I.bases[it.base].id .. "_" .. (faction or "arm") .. ".png"
end

function I.factionOf(unitDefName)
	local f = unitDefName and unitDefName:sub(1, 3)
	return (f == "arm" or f == "cor" or f == "leg") and f or "arm"
end

function I.price(it)
	return I.rarities[it.rarity].price[it.ilvl]
end

function I.salvage(it)
	return I.rarities[it.rarity].salvage[it.ilvl]
end

---------------------------------------------------------------------------------------------------- rolling
-- rnd(n) -> integer 1..n, rnd() -> [0,1) (math.random in synced code)
local function pickWeighted(rnd, list, weightOf)
	local total = 0
	for _, x in ipairs(list) do
		total = total + weightOf(x)
	end
	if total <= 0 then
		return nil
	end
	local r = rnd() * total
	for _, x in ipairs(list) do
		r = r - weightOf(x)
		if r <= 0 then
			return x
		end
	end
	return list[#list]
end

function I.rollRarity(rnd, ilvl)
	local L = ilvl or 1
	return pickWeighted(rnd, I.rarityOrder, function(r)
		local d = I.rarities[r]
		return d.weight * (1 + d.perIlvl * (L - 1))
	end)
end

local function rollTier(rnd, ilvl)
	if ilvl > 1 and rnd() < 0.35 then
		return ilvl - 1
	end
	return ilvl
end

-- add n random affixes of category cat to it (at most maxPre prefixes, maxSuf suffixes, no duplicates)
local function rollAffixes(rnd, it, n, maxPre, maxSuf)
	local used, pre, suf = {}, 0, 0
	for _, a in ipairs(it.affixes) do
		used[a[1]] = true
		if I.affixes[a[1]].kind == "prefix" then
			pre = pre + 1
		else
			suf = suf + 1
		end
	end
	for _ = 1, n do
		local a = pickWeighted(rnd, I.affixes, function(def)
			if used[def.index] then
				return 0
			end
			if def.kind == "prefix" and pre >= maxPre or def.kind == "suffix" and suf >= maxSuf then
				return 0
			end
			return def.w[it.cat] or 0
		end)
		if not a then
			break
		end
		used[a.index] = true
		if a.kind == "prefix" then
			pre = pre + 1
		else
			suf = suf + 1
		end
		it.affixes[#it.affixes + 1] = { a.index, rollTier(rnd, it.ilvl), rnd(100) - 1 }
	end
end

-- roll an item. opts: ilvl (1..5), rarity (else rolled from ilvl), cat (else random), uid
function I.roll(rnd, opts)
	opts = opts or {}
	local L = math.max(1, math.min(I.MAX_ILVL, math.floor(opts.ilvl or 1)))
	local rarity = opts.rarity or I.rollRarity(rnd, L)
	local cat = opts.cat or I.categoryOrder[rnd(3)]
	local it = { ilvl = L, rarity = rarity, cat = cat, affixes = {}, impQ = rnd(100) - 1, uid = opts.uid or 0 }
	if rarity == "unique" then
		local list = I.uniquesByCat[cat]
		local ui = list[rnd(#list)]
		local u = I.uniques[ui]
		it.unique = ui
		it.base = I.baseIndex[u.base]
		it.uq = {}
		for i = 1, I.uniqueRollCount(u) do
			it.uq[i] = rnd(100) - 1
		end
		rollAffixes(rnd, it, rnd(3), 2, 2)
	elseif rarity == "set" then
		local list = I.piecesByCat[cat]
		local sp = list[rnd(#list)]
		it.set, it.piece = sp[1], sp[2]
		it.base = I.baseIndex[I.sets[sp[1]].pieces[sp[2]].base]
		it.sq = rnd(100) - 1
		rollAffixes(rnd, it, 1, 1, 1)
	else
		local list = I.basesByCat[cat]
		it.base = opts.base or list[rnd(#list)]
		if rarity == "rare" then
			it.rname = { rnd(#I.rareWordsA), rnd(#I.rareWordsB[cat]) }
			rollAffixes(rnd, it, 1 + rnd(2), 2, 2)
		else
			if rnd() < 0.5 then
				rollAffixes(rnd, it, 2, 1, 1)
			else
				rollAffixes(rnd, it, 1, 1, 1)
			end
		end
	end
	it.str = I.encode(it)
	return it
end

-- item level of a drop from a unit worth `cost` metal, or from a hero of level `heroLevel`
function I.ilvlForCost(cost)
	if cost >= 30000 then
		return 5
	elseif cost >= 12000 then
		return 4
	elseif cost >= 5000 then
		return 3
	elseif cost >= 2000 then
		return 2
	end
	return 1
end
function I.ilvlForHero(level)
	return math.max(1, math.min(5, 1 + math.floor((level or 1) / 20)))
end

---------------------------------------------------------------------------------------------------- AI value
-- role weights of stats; dtype counts by the share of the hero's damage of that type (heroTypes[kind] 0..1)
I.roleWeights = {
	front = { hp = 1.3, armor = 1.3, regen = 1.0, thorns = 0.8, lifesteal = 0.9, damage = 0.9, crit = 0.6, critMult = 0.5,
		splash = 0.6, pierce = 0.6, range = 0.4, speed = 0.6, sight = 0.2, power = 0.8, cdr = 0.8, xp = 0.4, income = 0.4, dtype = 0.8 },
	center = { hp = 1.0, armor = 1.0, regen = 0.8, thorns = 0.5, lifesteal = 0.8, damage = 1.1, crit = 0.8, critMult = 0.6,
		splash = 0.8, pierce = 0.8, range = 0.8, speed = 0.6, sight = 0.3, power = 1.0, cdr = 0.9, xp = 0.4, income = 0.4, dtype = 1.0 },
	back = { hp = 0.8, armor = 0.8, regen = 0.6, thorns = 0.2, lifesteal = 0.5, damage = 1.3, crit = 1.0, critMult = 0.8,
		splash = 1.0, pierce = 0.8, range = 1.3, speed = 0.4, sight = 0.6, power = 1.0, cdr = 0.9, xp = 0.4, income = 0.4, dtype = 1.2 },
}
I.powerValue = { chain = 1.6, blastKill = 1.4, slayer = 1.6, execute = 1.3, orbital = 1.6, lowShield = 1.5, cheatDeath = 1.8,
	lifeOnHit = 1.3, reflect = 1.2, guardAura = 1.4, warAura = 1.5, mark = 1.3, souls = 1.5, staticWake = 1.4, blink = 0.8 }

function I.statScore(stats, role, heroTypes)
	local w = I.roleWeights[role] or I.roleWeights.center
	local s = 0
	for k, v in pairs(stats) do
		if k == "dtype" then
			for kind, dv in pairs(v) do
				s = s + dv / I.statInfo.dtype.norm * w.dtype * (heroTypes and heroTypes[kind] or 0)
			end
		elseif I.statInfo[k] then
			s = s + v / I.statInfo[k].norm * (w[k] or 0.5)
		end
	end
	return s
end

-- the AI's value of one item for a hero (role "front"|"center"|"back", heroTypes = { kind = share })
function I.score(it, role, heroTypes)
	local s = I.statScore(I.stats(it), role, heroTypes)
	for _, p in ipairs(I.powers(it)) do
		s = s + (I.powerValue[p.key] or 1) * I.fixedScale(it.ilvl)
	end
	if it.rarity == "set" then
		s = s + 0.5
	end
	return s
end

return I
