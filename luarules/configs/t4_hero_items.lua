-- Custom heroes (denysfast/bar-game): items. Included by luarules/configs/t4_heroes.lua,
-- which passes the shared table H. See CUSTOM.md, section "Heroes".
local H = ...

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
