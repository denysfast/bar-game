-- Custom heroes (denysfast/bar-game): items. Included by luarules/configs/t4_heroes.lua,
-- which passes the shared table H. See CUSTOM.md, section "Heroes".
local H = ...

-- Items (v15): three categories - weapon, defense, utility - with three slots each (nine slots). Everything
-- a hero picks up goes into its TEAM's shared stash (H.STASH_SIZE); a hero equips stash items into the slots
-- of their category. Items drop from slain heroes (everything they wore, where they fell, plus a trophy) and,
-- rarely, from expensive enemies a hero kills; a hero walking over one puts it into its team's stash.
--
-- stats (summed over the equipped items):
--   in units:     hp (effective HP), regen (effective HP per second), speed (elmos/s), range (elmos, every
--                 weapon), sight (elmos), radar (elmos), income (metal per second to the team)
--   fractions:    damage, reload (fraction off the reload time), armor (fraction of damage taken), splash
--                 (fraction more blast radius), burn (fraction of a hit that burns on), lifesteal, thorns
--                 (fraction of damage taken returned), cdr (fraction off ability AND item cooldowns), xp
--   crit = { chance, mult }            chances add up (max 50%), the best multiplier counts
-- special passives (one table each, the gadget handles them; damage numbers grow with the hero's power):
--   procChain = { chance, dmg, jumps, radius }   a hit may fire chain lightning (0.6 s internal cooldown)
--   procBlast = { chance, dmg, radius }          a hit may detonate on the target (0.6 s internal cooldown)
--   slayer = { minCost, mult }                   more damage against units worth minCost metal or more
--   execute = { below, mult }                    more damage against units under `below` of their health
--   zap = { period, damage, radius }             strikes the nearest enemy by itself every `period` s
--   barrier = { cap, regen, delay }              an energy barrier absorbs damage up to cap, recharges
--                                                regen HP/s after `delay` s without taking damage
--   lastStand = { below, armor }                 under `below` health: `armor` less damage taken
--   cheatDeath = { cooldown, heal, invuln }      lethal damage leaves the hero at `heal` of its health
--   aura = { radius, damage, armor, heal }       allies around deal +damage, take -armor, heal HP/s
-- active = { kind, cooldown, ... }  "Use" in the picker, autocast and the AI use them by themselves:
--   heal { amount }                   repair the hero (effective HP)
--   invuln { duration }               the hero takes no damage
--   dash { distance }                 blink forward
--   shield { absorb, duration }       a shield absorbs up to `absorb` damage
--   emp { radius, stun, dmg }         an EMP pulse around the hero
--   overcharge { duration, damage, reload }   weapons overcharge for a while
--   repair { radius, amount }         repair allies (and the hero) around
--   recall { }                        teleport back to the team's hero altar
H.INVENTORY = 9
H.STASH_SIZE = 36
H.ITEM_PICKUP_RADIUS = 180
H.ITEM_LIFETIME = 300        -- seconds an item lies on the ground
H.ITEM_DROP_CHANCE = 1 / 150000 -- per metal of a slain enemy (a 30k titan: 20%), max ITEM_DROP_MAX
H.ITEM_DROP_MAX = 0.35
H.ITEM_PROC_ICD = 0.6        -- seconds between two procs of the same item
-- score: the AI's value of an item of that rarity; scrap: metal a full stash pays for an item it throws away
H.rarities = {
	common = { color = { 0.85, 0.85, 0.85 }, weight = 55, score = 1, scrap = 1500, rank = 1 },
	rare = { color = { 0.3, 0.6, 1.0 }, weight = 28, score = 2, scrap = 4000, rank = 2 },
	epic = { color = { 0.75, 0.35, 1.0 }, weight = 13, score = 3.3, scrap = 9000, rank = 3 },
	legendary = { color = { 1.0, 0.65, 0.1 }, weight = 4, score = 5, scrap = 20000, rank = 4 },
}
H.rarityOrder = { "common", "rare", "epic", "legendary" }
H.categoryOrder = { "weapon", "defense", "utility" }
H.itemCategories = {
	weapon = { label = "Weapon", slots = { 1, 2, 3 }, color = { 1.0, 0.45, 0.18 }, glyph = "cat_weapon" },
	defense = { label = "Defense", slots = { 4, 5, 6 }, color = { 0.3, 0.72, 1.0 }, glyph = "cat_defense" },
	utility = { label = "Utility", slots = { 7, 8, 9 }, color = { 0.55, 0.95, 0.45 }, glyph = "cat_utility" },
}
H.slotCategory = {}
for cat, c in pairs(H.itemCategories) do
	for _, s in ipairs(c.slots) do
		H.slotCategory[s] = cat
	end
end
-- the AI equips by rarity score x (1 + the weight of the item's tags for the hero's aiRole)
H.itemRoleWeights = {
	front = { tank = 0.6, sustain = 0.4, dps = 0.2, burst = 0.1, mobility = 0.2, range = 0.0, support = 0.2, economy = 0.0 },
	center = { tank = 0.3, sustain = 0.3, dps = 0.4, burst = 0.3, mobility = 0.2, range = 0.2, support = 0.4, economy = 0.1 },
	back = { tank = 0.1, sustain = 0.2, dps = 0.6, burst = 0.4, mobility = 0.1, range = 0.6, support = 0.2, economy = 0.2 },
}

H.items = {
	------------------------------------------------------------------ weapon
	plasma_core = { name = "Plasma Core", category = "weapon", rarity = "common", tags = { "dps" },
		stats = { damage = 0.10 }, short = "+10% damage", desc = "A superheated plasma cell in the weapon feed.\n+10% damage" },
	capacitor = { name = "Rapid Capacitor", category = "weapon", rarity = "common", tags = { "dps" },
		stats = { reload = 0.08 }, short = "-8% reload", desc = "Faster charge cycles.\n8% faster reload" },
	frag_casing = { name = "Fragmentation Casing", category = "weapon", rarity = "common", tags = { "dps", "burst" },
		stats = { splash = 0.20, damage = 0.03 }, short = "+20% blast, +3% dmg", desc = "Shells burst into shrapnel.\n+20% blast radius, +3% damage" },
	tracer_rounds = { name = "Tracer Rounds", category = "weapon", rarity = "common", tags = { "burst" },
		stats = { crit = { 0.08, 1.8 } }, short = "8% crit x1.8", desc = "Marks weak points for follow-up hits.\n8% chance to deal x1.8 damage" },
	overclock_chip = { name = "Overclock Chip", category = "weapon", rarity = "rare", tags = { "dps" },
		stats = { damage = 0.20, hp = -2500 }, short = "+20% dmg, -2500 HP", desc = "Runs the guns past the safety limits.\n+20% damage, -2500 health" },
	vampiric_coil = { name = "Vampiric Coil", category = "weapon", rarity = "rare", tags = { "sustain", "dps" },
		stats = { lifesteal = 0.04 }, short = "4% lifesteal", desc = "Drains the energy of whatever it hits.\n4% of damage dealt heals the hero" },
	arc_emitter = { name = "Arc Emitter", category = "weapon", rarity = "rare", tags = { "burst", "dps" },
		stats = {}, procChain = { chance = 0.12, dmg = 1800, jumps = 3, radius = 450 },
		short = "12%: chain lightning", desc = "Hits have a 12% chance to arc lightning:\n1800 damage, jumps to 3 enemies within 450" },
	thermite_loader = { name = "Thermite Loader", category = "weapon", rarity = "rare", tags = { "dps" },
		stats = { burn = 0.08, damage = 0.05 }, short = "+8% burn, +5% dmg", desc = "Incendiary rounds.\nHits burn for 8% more over 3 s, +5% damage" },
	crit_matrix = { name = "Crit Matrix", category = "weapon", rarity = "epic", tags = { "burst", "dps" },
		stats = { crit = { 0.15, 2.2 } }, short = "15% crit x2.2", desc = "Predictive targeting core.\n15% chance to deal x2.2 damage" },
	shrapnel_amp = { name = "Shrapnel Amplifier", category = "weapon", rarity = "epic", tags = { "dps", "burst" },
		stats = { splash = 0.35, damage = 0.08 }, short = "+35% blast, +8% dmg", desc = "Focuses the blast into a wider cone.\n+35% blast radius, +8% damage" },
	titan_breaker = { name = "Titan Breaker", category = "weapon", rarity = "epic", tags = { "dps", "burst" },
		stats = { damage = 0.05 }, slayer = { minCost = 3000, mult = 0.30 },
		short = "+30% vs big units", desc = "Armor-piercing penetrators.\n+30% damage to units worth 3000+ metal, +5% damage" },
	overcharge_cell = { name = "Overcharge Cell", category = "weapon", rarity = "epic", tags = { "burst", "dps" },
		stats = { damage = 0.06 }, active = { kind = "overcharge", duration = 8, damage = 0.40, reload = 0.30, cooldown = 60 },
		short = "Use: overcharge", desc = "+6% damage.\nUse: +40% damage and 30% faster reload for 8 s (cd 60 s)" },
	orb_annihilation = { name = "Orb of Annihilation", category = "weapon", rarity = "legendary", tags = { "dps", "burst" },
		stats = { damage = 0.28, burn = 0.06 }, procBlast = { chance = 0.10, dmg = 4000, radius = 220 },
		short = "+28% dmg, 10% blast", desc = "A caged antimatter orb.\n+28% damage, hits burn 6% more,\n10% chance: a 4000 damage blast on the target" },
	storm_crown = { name = "Crown of Storms", category = "weapon", rarity = "legendary", tags = { "dps", "burst" },
		stats = { damage = 0.08 }, zap = { period = 3, damage = 9000, radius = 1000 },
		short = "Lightning every 3 s", desc = "+8% damage.\nEvery 3 s lightning strikes the nearest enemy within 1000 (9000 damage)" },
	executioner = { name = "Executioner's Edge", category = "weapon", rarity = "legendary", tags = { "burst", "dps" },
		stats = { crit = { 0.10, 2.0 } }, execute = { below = 0.30, mult = 0.50 },
		short = "+50% vs <30% HP", desc = "Finishes the wounded.\n+50% damage to units under 30% health,\n10% chance to deal x2 damage" },
	singularity_driver = { name = "Singularity Driver", category = "weapon", rarity = "legendary", tags = { "dps", "burst" },
		stats = { damage = 0.18, reload = 0.12 }, procBlast = { chance = 0.08, dmg = 6000, radius = 300 },
		short = "+18% dmg, -12% reload", desc = "Feeds the guns from a micro black hole.\n+18% damage, 12% faster reload,\n8% chance: an implosion of 6000 damage on the target" },

	------------------------------------------------------------------ defense
	armor_plate = { name = "Composite Plate", category = "defense", rarity = "common", tags = { "tank" },
		stats = { hp = 5000 }, short = "+5000 HP", desc = "Layered ceramic armor.\n+5000 health" },
	nano_weave = { name = "Nano-Weave Lining", category = "defense", rarity = "common", tags = { "sustain" },
		stats = { regen = 150 }, short = "+150 HP/s", desc = "Repair nanites under the hull.\nRegenerates 150 health per second" },
	deflector_mesh = { name = "Deflector Mesh", category = "defense", rarity = "common", tags = { "tank" },
		stats = { armor = 0.05 }, short = "-5% damage taken", desc = "A deflecting field lattice.\n-5% damage taken" },
	nanite_vial = { name = "Nanite Vial", category = "defense", rarity = "common", tags = { "sustain" },
		stats = {}, active = { kind = "heal", amount = 6000, cooldown = 45 }, short = "Use: +6000 HP",
		desc = "A canister of repair swarm.\nUse: repair 6000 health (cd 45 s)" },
	reactive_shell = { name = "Reactive Shell", category = "defense", rarity = "rare", tags = { "tank" },
		stats = { armor = 0.09, hp = 1500 }, short = "-9% dmg taken", desc = "Explosive reactive armor.\n-9% damage taken, +1500 health" },
	thorn_mesh = { name = "Thorn Mesh", category = "defense", rarity = "rare", tags = { "tank" },
		stats = { thorns = 0.15, armor = 0.04 }, short = "15% thorns", desc = "Charged spikes along the hull.\nReturns 15% of damage taken, -4% damage taken" },
	barrier_projector = { name = "Barrier Projector", category = "defense", rarity = "rare", tags = { "tank", "sustain" },
		stats = {}, barrier = { cap = 6000, regen = 600, delay = 5 }, short = "6000 barrier",
		desc = "An energy barrier absorbs up to 6000 damage.\nRecharges 600/s after 5 s without damage" },
	adaptive_armor = { name = "Adaptive Armor", category = "defense", rarity = "rare", tags = { "tank" },
		stats = { hp = 2000 }, lastStand = { below = 0.40, armor = 0.25 }, short = "-25% dmg under 40%",
		desc = "Hardens when the hull is breached.\nUnder 40% health: -25% damage taken. +2000 health" },
	titan_heart = { name = "Titan Heart", category = "defense", rarity = "epic", tags = { "tank", "sustain" },
		stats = { hp = 12000, regen = 100 }, short = "+12000 HP", desc = "A salvaged titan reactor.\n+12000 health, +100 health per second" },
	phase_shield = { name = "Phase Shield", category = "defense", rarity = "epic", tags = { "tank" },
		stats = { hp = 3000 }, active = { kind = "invuln", duration = 3, cooldown = 90 }, short = "Use: invulnerable 3 s",
		desc = "Shifts the hull out of phase.\n+3000 health. Use: invulnerable for 3 s (cd 90 s)" },
	bulwark_beacon = { name = "Bulwark Beacon", category = "defense", rarity = "epic", tags = { "support", "tank" },
		stats = { hp = 4000 }, aura = { radius = 800, armor = 0.12 }, short = "Aura: allies -12% dmg",
		desc = "Projects deflector fields over the army.\nAllies within 800 take -12% damage. +4000 health" },
	shield_burst = { name = "Shield Burst Generator", category = "defense", rarity = "epic", tags = { "tank" },
		stats = { armor = 0.04 }, active = { kind = "shield", absorb = 15000, duration = 8, cooldown = 50 },
		short = "Use: 15000 shield", desc = "-4% damage taken.\nUse: a shield absorbs up to 15000 damage for 8 s (cd 50 s)" },
	aegis_relic = { name = "Aegis of the Ancients", category = "defense", rarity = "legendary", tags = { "tank", "sustain" },
		stats = { armor = 0.15, hp = 8000, regen = 150 }, short = "-15% dmg, +8000 HP",
		desc = "A relic of the first war.\n-15% damage taken, +8000 health, +150 health per second" },
	dragon_reactor = { name = "Dragon Reactor", category = "defense", rarity = "legendary", tags = { "tank", "dps" },
		stats = { hp = 15000, damage = 0.10, speed = 5 }, short = "+15000 HP, +10% dmg",
		desc = "A furnace that feeds armor and guns.\n+15000 health, +10% damage, +5 speed" },
	phoenix_core = { name = "Phoenix Core", category = "defense", rarity = "legendary", tags = { "tank", "sustain" },
		stats = { hp = 5000 }, cheatDeath = { cooldown = 120, heal = 0.40, invuln = 2 }, short = "Cheats death (120 s)",
		desc = "+5000 health. Lethal damage instead leaves the hero\nat 40% health and invulnerable for 2 s (once per 120 s)" },
	retribution_engine = { name = "Retribution Engine", category = "defense", rarity = "legendary", tags = { "tank", "sustain" },
		stats = { thorns = 0.30, armor = 0.10, regen = 250 }, short = "30% thorns, -10% dmg",
		desc = "Turns every hit into a counter-strike.\nReturns 30% of damage taken, -10% damage taken,\n+250 health per second" },

	------------------------------------------------------------------ utility
	servo_boots = { name = "Servo Treads", category = "utility", rarity = "common", tags = { "mobility" },
		stats = { speed = 5 }, short = "+5 speed", desc = "High-torque drive servos.\n+5 speed" },
	targeting_lens = { name = "Targeting Lens", category = "utility", rarity = "common", tags = { "range" },
		stats = { range = 60 }, short = "+60 range", desc = "A long-focus fire control lens.\n+60 range to every weapon" },
	scout_uplink = { name = "Scout Uplink", category = "utility", rarity = "common", tags = { "range" },
		stats = { sight = 300 }, short = "+300 sight", desc = "A link to recon drones.\n+300 sight" },
	salvage_drone = { name = "Salvage Drone", category = "utility", rarity = "common", tags = { "economy" },
		stats = { income = 10 }, short = "+10 metal/s", desc = "Strips the battlefield for scrap.\n+10 metal per second to the team" },
	blink_drive = { name = "Blink Drive", category = "utility", rarity = "rare", tags = { "mobility" },
		stats = { speed = 3 }, active = { kind = "dash", distance = 700, cooldown = 25 }, short = "Use: blink 700",
		desc = "A short-range fold drive.\n+3 speed. Use: blink 700 forward (cd 25 s)" },
	repair_array = { name = "Field Repair Array", category = "utility", rarity = "rare", tags = { "support", "sustain" },
		stats = {}, active = { kind = "repair", radius = 700, amount = 5000, cooldown = 40 }, short = "Use: repair allies",
		desc = "Deploys repair drones.\nUse: repair 5000 health of the hero and every ally within 700 (cd 40 s)" },
	tactical_uplink = { name = "Tactical Uplink", category = "utility", rarity = "rare", tags = { "support", "burst" },
		stats = { cdr = 0.15 }, short = "-15% cooldowns", desc = "Battle-net priority access.\nAbility and item cooldowns -15%" },
	rangefinder = { name = "Rangefinder Array", category = "utility", rarity = "rare", tags = { "range" },
		stats = { range = 120, sight = 200 }, short = "+120 range", desc = "Laser rangefinders and ballistic computer.\n+120 range, +200 sight" },
	warlords_banner = { name = "Warlord's Banner", category = "utility", rarity = "epic", tags = { "support" },
		stats = {}, aura = { radius = 900, damage = 0.12 }, short = "Aura: allies +12% dmg",
		desc = "A holo-standard the army rallies to.\nAllies within 900 deal +12% damage" },
	chrono_crystal = { name = "Chrono Crystal", category = "utility", rarity = "epic", tags = { "burst", "support" },
		stats = { cdr = 0.22 }, short = "-22% cooldowns", desc = "A crystal that bends local time.\nAbility and item cooldowns -22%" },
	emp_emitter = { name = "EMP Pulse Emitter", category = "utility", rarity = "epic", tags = { "support", "burst" },
		stats = {}, active = { kind = "emp", radius = 650, stun = 4, dmg = 3000, cooldown = 45 }, short = "Use: EMP pulse",
		desc = "Use: an EMP pulse stuns enemies within 650 for 4 s\nand deals 3000 damage (cd 45 s)" },
	recall_beacon = { name = "Recall Beacon", category = "utility", rarity = "epic", tags = { "mobility", "sustain" },
		stats = { speed = 4 }, active = { kind = "recall", cooldown = 120 }, short = "Use: recall to altar",
		desc = "+4 speed.\nUse: teleport back to the hero altar (cd 120 s)" },
	chronos_engine = { name = "Chronos Engine", category = "utility", rarity = "legendary", tags = { "dps", "mobility" },
		stats = { reload = 0.15, speed = 8, cdr = 0.15 }, short = "-15% reload, -15% cd",
		desc = "A time-dilation core.\n15% faster reload, +8 speed, cooldowns -15%" },
	soul_harvester = { name = "Soul Harvester", category = "utility", rarity = "legendary", tags = { "economy", "dps" },
		stats = { xp = 0.5, damage = 0.08 }, short = "+50% experience", desc = "Harvests the combat data of the fallen.\n+50% experience, +8% damage" },
	sanctuary_matrix = { name = "Sanctuary Matrix", category = "utility", rarity = "legendary", tags = { "support", "sustain" },
		stats = {}, aura = { radius = 900, heal = 150 }, active = { kind = "repair", radius = 900, amount = 12000, cooldown = 60 },
		short = "Aura: allies +150 HP/s", desc = "Allies within 900 regenerate 150 health per second.\nUse: repair 12000 health of every ally within 900 (cd 60 s)" },
	oracle_eye = { name = "Oracle Eye", category = "utility", rarity = "legendary", tags = { "range", "support" },
		stats = { sight = 600, radar = 1200, range = 150, cdr = 0.10 }, short = "+150 range, +600 sight",
		desc = "Sees everything, everywhere.\n+600 sight, +1200 radar, +150 range, cooldowns -10%" },
}
H.itemOrder = {
	-- weapon
	"plasma_core", "capacitor", "frag_casing", "tracer_rounds",
	"overclock_chip", "vampiric_coil", "arc_emitter", "thermite_loader",
	"crit_matrix", "shrapnel_amp", "titan_breaker", "overcharge_cell",
	"orb_annihilation", "storm_crown", "executioner", "singularity_driver",
	-- defense
	"armor_plate", "nano_weave", "deflector_mesh", "nanite_vial",
	"reactive_shell", "thorn_mesh", "barrier_projector", "adaptive_armor",
	"titan_heart", "phase_shield", "bulwark_beacon", "shield_burst",
	"aegis_relic", "dragon_reactor", "phoenix_core", "retribution_engine",
	-- utility
	"servo_boots", "targeting_lens", "scout_uplink", "salvage_drone",
	"blink_drive", "repair_array", "tactical_uplink", "rangefinder",
	"warlords_banner", "chrono_crystal", "emp_emitter", "recall_beacon",
	"chronos_engine", "soul_harvester", "sanctuary_matrix", "oracle_eye",
}
H.itemIndex = {}
for i, id in ipairs(H.itemOrder) do
	H.itemIndex[id] = i
	H.items[id].id = id
end
