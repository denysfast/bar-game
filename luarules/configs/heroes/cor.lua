-- Custom heroes (denysfast/bar-game), v19: the ten Cortex heroes (altar cort4gant; v23: + Negotiator). Included by
-- luarules/configs/t4_heroes.lua with the shared table H as `...`; returns `defs, order`. Format: header of
-- luarules/configs/heroes/arm.lua. Design: doc/v19-heroes/roster_cor.md. Every ability is kind = "custom": the
-- behaviour is in luarules/heroes/<hero>.lua (shared helpers luarules/heroes/cort4_lib.lua). Numbers are per rank
-- (r1 -> r10, H.lin) and before ability power (the modules multiply damage / healing by api.power).
-- Command ids: 36200 + 10 * row + slot (a1 = 1, a2 = 2, a3 = 3, ult = 4).
local H = ...
local lin, tf = H.lin, H.textf

local function ab(t)
	t.kind = t.kind or "custom"
	return t
end

local heroes = {
	------------------------------------------------------------------------------------------- 0 Juggernaut
	cort4bastion = {
		title = "Juggernaut, the Unkillable", role = "Killer tank", aiRole = "front", aiPick = 3,
		fx = 2.2,
		weapons = { { keys = { "juggernaut_fire" }, name = "Gauss Cannon" }, { keys = { "juggernaut_bottom", "juggernaut_top" }, name = "Twin Lasers" } },
		a1 = ab({
			name = "Power Shot", cmd = 36201, action = "hero_powershot", target = "unit", icon = "ab_cort4bastion_a1",
			desc = "Locks the turret on one target and fires a rapid series of heavy gauss shells; every shell that hits it adds 8% to the next, anything on the line takes half",
			range = lin(800, 950, 10), count = lin(4, 8, 1), dmg = lin(2000, 4500, 100), stack = 0.08, pierce = 0.3,
			interval = 0.25, cooldown = lin(20, 12, 1),
			text = tf("{count} shells x {dmg} dmg (+8% per hit), range {range}, cd {cooldown} s"),
		}),
		a2 = ab({
			name = "Circle Beam", cmd = 36202, action = "hero_circlebeam", icon = "ab_cort4bastion_a2",
			desc = "Anchors for 3 s (25% less damage taken) and sweeps a twin laser all around, burning everything it crosses",
			duration = 3, sweep = lin(360, 540, 20), length = lin(650, 950, 10), dmg = lin(1200, 2800, 100),
			burn = lin(60, 180, 10), burnTime = 4, width = lin(60, 140, 5), armor = 0.25, cooldown = lin(28, 18, 1),
			text = tf("{sweep} deg sweep, {length} long: {dmg} dmg per pass + {burn} dmg/s burn, cd {cooldown} s"),
		}),
		a3 = ab({
			name = "Reactive Armor", passive = true, icon = "ab_cort4bastion_a3",
			desc = "Heavy hits make the armour fire a plasma shell back at the attacker (or the nearest enemy)",
			minHit = 300, chance = lin(0.10, 0.35, 0.01), dmg = lin(1500, 4000, 100), share = 0.5, cap = 6000,
			shells = { 1, 1, 1, 1, 1, 2, 2, 2, 2, 2 }, icd = 1, aoe = 120, reach = 1000,
			text = tf("{chance%} per hit of 300+ (once a second): {shells} shell(s) x {dmg} dmg + 50% of the hit (cap 6000), reach 1000"),
		}),
		ult = ab({
			name = "Resurrection", passive = true, icon = "ab_cort4bastion_ult",
			desc = "A lethal blow drops the Juggernaut for 3 s; then it rises with a stunning shockwave and fights Unbroken",
			cooldown = lin(300, 120, 10), down = 3, heal = lin(0.35, 0.8, 0.05), nova = lin(8000, 30000, 500), novaRadius = 600,
			stun = 1.5, unbroken = 6, damage = lin(0.2, 0.5, 0.01), reload = 0.43,
			text = tf("rises with {heal%} HP, {nova} dmg shockwave, +{damage%} damage for 6 s, cd {cooldown} s"),
		}),
	},

	------------------------------------------------------------------------------------------- 1 Colossus
	cort4colossus = {
		title = "Colossus, the Warlord", role = "Initiator", aiRole = "front", aiPick = 3,
		fx = 2.2,
		weapons = { { keys = { "corkorg_fire" }, name = "Plasma Scatter Gun" }, { keys = { "corkorg_laser" }, name = "Heat Eye" }, { keys = { "corkorg_rocket" }, name = "Warlord Rockets" } },
		a1 = ab({
			name = "Titan Grip", cmd = 36211, action = "hero_titangrip", target = "unit", icon = "ab_cort4colossus_a1",
			desc = "Grabs an enemy machine and hurls it into the densest enemy cluster; the landing crushes and stuns. A hero is kicked back instead",
			range = 450, throw = lin(900, 1600, 10), dmg = lin(2500, 9000, 100), share = lin(0.15, 0.4, 0.01), cap = 30000,
			splash = 250, stun = 1.5, heroStun = lin(0.5, 1.5, 0.1), cooldown = lin(20, 12, 1),
			text = tf("{dmg} dmg, thrown up to {throw}: {share%} of its HP to those it lands on, cd {cooldown} s"),
		}),
		a2 = ab({
			name = "Fault Line", passive = true, icon = "ab_cort4colossus_a2",
			desc = "Its steps quake the ground: damage and a slow around it, and Fault stacks - the third knocks the enemy down",
			period = lin(4, 2.5, 0.1), dmg = lin(1500, 5000, 100), radius = lin(300, 500, 10), slow = 0.4, slowTime = 2,
			maxStacks = 3, stackTime = 6, knock = 1,
			text = tf("every {period.1} s on the move: {dmg} dmg in {radius}, 40% slow, Fault stacks"),
		}),
		a3 = ab({
			name = "Warcry", cmd = 36213, action = "hero_warcry", icon = "ab_cort4colossus_a3",
			desc = "Rallies the army (damage, speed) and taunts the enemies around onto Colossus, which takes less damage",
			radius = lin(800, 1200, 10), duration = lin(6, 10, 0.5), damage = lin(0.05, 0.15, 0.01), speed = 0.2,
			taunt = lin(2, 4, 0.1), armor = lin(0.15, 0.35, 0.01), cooldown = lin(40, 26, 1),
			text = tf("{duration.1} s in {radius}: army +{damage%} damage, enemies taunted {taunt.1} s, -{armor%} damage taken, cd {cooldown} s"),
		}),
		ult = ab({
			name = "Earthshatter", cmd = 36214, action = "hero_earthshatter", target = "map", icon = "ab_cort4colossus_ult",
			desc = "Leaps onto a point, landing in a stunning quake; six fissures erupt three times",
			range = lin(1000, 1600, 10), dmg = lin(2000, 5000, 100), radius = lin(600, 900, 10), stun = lin(2, 4, 0.1),
			fissure = lin(250, 750, 50), fissureLen = 900, ticks = 3, leap = 1.2, cooldown = lin(120, 80, 5),
			text = tf("{dmg} dmg in {radius}, {stun.1} s stun, fissures 3 x {fissure}, range {range}, cd {cooldown} s"),
		}),
	},

	------------------------------------------------------------------------------------------- 2 Hellwalker
	cort4hellwalker = {
		title = "Hellwalker, the Inferno", role = "Flame brawler", aiRole = "front", aiPick = 2,
		fx = 2.5,
		weapons = { { keys = { "newdmaw" }, name = "Hellfire Maw" }, { keys = { "karg_shoulder" }, name = "Shoulder Missiles" } },
		a1 = ab({
			name = "Combustion", passive = true, icon = "ab_cort4hellwalker_a1",
			desc = "Its flame heats enemies up; at 10 Heat they explode, setting the enemies around ablaze",
			maxHeat = 10, decay = 1, cap = lin(1000, 3000, 100), flat = lin(300, 800, 50), pct = 0.08, radius = 200, spread = 2,
			text = tf("at 10 Heat: 8% of max HP (cap {cap}) + {flat} dmg, {flat} to enemies in 200"),
		}),
		a2 = ab({
			name = "Hellcharge", cmd = 36222, action = "hero_hellcharge", target = "map", cursor = "Move", icon = "ab_cort4hellwalker_a2",
			desc = "Dashes through the line, burning and knocking aside what it passes, and leaves a wall of fire",
			range = lin(700, 1100, 10), dmg = lin(1000, 3000, 100), wall = lin(100, 300, 10), wallTime = 5, heat = 3,
			flameRange = 0.3, cooldown = lin(22, 14, 1),
			text = tf("{range} dash, {dmg} dmg, fire wall {wall} dmg/s for 5 s, cd {cooldown} s"),
		}),
		a3 = ab({
			name = "Infernal Furnace", cmd = 36223, action = "hero_furnace", icon = "ab_cort4hellwalker_a3",
			desc = "Inhales, pulling the enemies around in, then exhales a fire nova",
			radius = lin(500, 800, 10), dmg = lin(1300, 4000, 100), pull = 200, inhale = 1.5, heat = 5, cooldown = lin(30, 20, 1),
			text = tf("pulls in {radius}, then {dmg} dmg nova, cd {cooldown} s"),
		}),
		ult = ab({
			name = "Hell on Earth", cmd = 36224, action = "hero_hellonearth", icon = "ab_cort4hellwalker_ult",
			desc = "Becomes a living inferno: burns everything around, calls meteors, double Heat, and erupts at the end",
			duration = lin(6, 10, 0.5), radius = lin(450, 700, 10), burn = lin(150, 400, 10), scale = 1.25, speed = 0.25,
			meteor = lin(500, 900, 50), meteorAoe = 200, meteorRange = 1000, nova = lin(1500, 4000, 100), novaRadius = 600,
			cooldown = lin(110, 75, 5),
			text = tf("{duration.1} s: {burn} dmg/s in {radius}, meteors {meteor}, eruption {nova}, cd {cooldown} s"),
		}),
	},

	------------------------------------------------------------------------------------------- 3 Armageddon
	cort4armageddon = {
		title = "Armageddon, the Doomsayer", role = "Rocket artillery", aiRole = "back", aiPick = 2, xpRate = 0.15,
		fx = 2.5,
		weapons = { { keys = { "exp_heavyrocket" }, name = "Heavy Rocket Racks" } },
		a1 = ab({
			name = "Cluster Warheads", passive = true, icon = "ab_cort4armageddon_a1",
			desc = "Every second rocket of a salvo splits into bomblets where it lands",
			bomblets = lin(2, 5, 1), share = lin(0.10, 0.25, 0.01), scatter = 150, aoe = 90, cap = 60,
			text = tf("{bomblets} bomblets x {share%} of a rocket, every 2nd rocket"),
		}),
		a2 = ab({
			name = "Doom Painter", cmd = 36232, action = "hero_doompainter", target = "unit", icon = "ab_cort4armageddon_a2",
			desc = "Paints a target with a laser: it takes more damage from everything, and the next salvo homes on it",
			range = 2700, duration = 4, vuln = lin(0.1, 0.25, 0.01), cooldown = lin(25, 15, 1),
			text = tf("+{vuln%} damage taken for 4 s, salvo homes on it, range {range}, cd {cooldown} s"),
		}),
		a3 = ab({
			name = "Retro Rockets", cmd = 36233, action = "hero_retrorockets", target = "map", cursor = "Move", icon = "ab_cort4armageddon_a3",
			desc = "Fires the tubes into the ground to leap away; the takeoff spot burns and slows",
			range = lin(500, 900, 10), dmg = lin(1500, 4500, 100), radius = 300, slow = 0.5, slowTime = 3, cooldown = lin(30, 18, 1),
			text = tf("leap {range}, {dmg} dmg in 300 + 50% slow, cd {cooldown} s"),
		}),
		ult = ab({
			name = "Armageddon Protocol", cmd = 36234, action = "hero_armageddon", target = "map", icon = "ab_cort4armageddon_ult",
			desc = "Designates an area: after a warning, a rain of rockets falls on it, sealed with a tactical nuke",
			range = lin(2400, 2700, 50), radius = 700, warn = 2, duration = 6, count = lin(24, 60, 1), dmg = lin(500, 800, 50),
			aoe = 200, nuke = lin(3000, 7000, 500), nukeAoe = 600, cooldown = lin(120, 80, 5),
			text = tf("{count} rockets x {dmg} + {nuke} nuke, range {range}, cd {cooldown} s"),
		}),
	},

	------------------------------------------------------------------------------------------- 4 Vesuvius
	cort4vesuvius = {
		title = "Vesuvius, the Twin-Barrel", role = "Siege tank", aiRole = "center", aiPick = 2,
		fx = 2.2,
		weapons = { { keys = { "corlevlr_weapon" }, name = "Twin Plasma Cannon" }, { keys = { "banisher" }, name = "Banisher Racks" }, { keys = { "flamethrower" }, name = "Flamer" } },
		a1 = ab({
			name = "Twin Impact", passive = true, icon = "ab_cort4vesuvius_a1",
			desc = "When both shells of a pair land together they resonate: an extra blast and Shred on the target",
			dmg = lin(2500, 8000, 100), radius = 250, near = 150, shred = lin(0.05, 0.15, 0.01), shredTime = 5, maxShred = 3,
			text = tf("resonance {dmg} dmg in 250, Shred +{shred%} damage taken (x3)"),
		}),
		a2 = ab({
			name = "Banisher Lock", cmd = 36242, action = "hero_banisherlock", target = "unit", icon = "ab_cort4vesuvius_a2",
			desc = "Both racks ripple-fire heavy missiles at one target; +50% against a Shredded one",
			range = 1400, count = lin(6, 14, 1), dmg = lin(700, 1200, 50), aoe = 128, time = 2, shredBonus = 0.5,
			cooldown = lin(18, 12, 1),
			text = tf("{count} missiles x {dmg} dmg, range {range}, cd {cooldown} s"),
		}),
		a3 = ab({
			name = "Siege Mode", cmd = 36243, action = "hero_siegemode", toggle = true, icon = "ab_cort4vesuvius_a3",
			desc = "Digs in: immobile, tougher, longer range, and the shells leave pools of lava. Cast again to undeploy",
			duration = lin(8, 14, 0.5), armor = 0.2, range = lin(0.3, 0.6, 0.01), pool = lin(500, 1500, 10), poolRadius = 150,
			poolTime = 4, cooldown = 20,
			text = tf("up to {duration.1} s: +{range%} range, -20% damage taken, lava {pool} dmg/s, cd 20 s"),
		}),
		ult = ab({
			name = "Eruption", cmd = 36244, action = "hero_eruption", target = "map", icon = "ab_cort4vesuvius_ult",
			desc = "Lobs volcanic bombs onto an area, each leaving lava, then the ground erupts",
			range = 1800, radius = 500, count = lin(5, 12, 1), dmg = lin(1000, 1600, 100), aoe = 300, time = 3,
			pool = lin(120, 280, 10), poolRadius = 220, poolTime = 6, nova = lin(1800, 4500, 100), novaRadius = 450,
			cooldown = lin(120, 85, 5),
			text = tf("{count} bombs x {dmg}, lava {pool} dmg/s, eruption {nova}, range 1800, cd {cooldown} s"),
		}),
	},

	------------------------------------------------------------------------------------------- 5 Printer
	cort4printer = {
		title = "Printer, the Swarm Foundry", role = "Drone carrier", aiRole = "center", aiPick = 2,
		fx = 2.2,
		weapons = { { keys = { "printer_disassembler" }, name = "Disassembler Beam" } },
		a1 = ab({
			name = "Drone Bay", passive = true, icon = "ab_cort4printer_a1",
			desc = "Keeps a wing of attack drones that fight for it; lost ones are reprinted",
			count = lin(2, 8, 1), dps = lin(800, 1500, 10), hp = 10000, leash = 900, reprint = lin(10, 5, 0.5),
			text = tf("{count} drones x {dps} dps, reprint every {reprint.1} s"),
		}),
		a2 = ab({
			name = "Print Turret", cmd = 36252, action = "hero_printturret", target = "map", icon = "ab_cort4printer_a2",
			desc = "Prints a quad laser turret on the spot for a while",
			range = 900, hp = lin(12000, 40000, 500), dps = lin(400, 1100, 50), duration = lin(20, 40, 1), max = lin(2, 3, 1),
			build = 1.5, cooldown = lin(30, 18, 1),
			text = tf("turret {hp} HP, {dps} dps for {duration} s (max {max}), cd {cooldown} s"),
		}),
		a3 = ab({
			name = "Repair Swarm", cmd = 36253, action = "hero_repairswarm", target = "ally", icon = "ab_cort4printer_a3",
			desc = "Sends every drone to repair an ally (or itself) and the allies around it",
			range = 1000, duration = 8, heal = lin(1500, 5000, 50), radius = 300, cooldown = lin(25, 15, 1),
			text = tf("{heal} HP/s for 8 s around an ally, cd {cooldown} s"),
		}),
		ult = ab({
			name = "Swarm Protocol", cmd = 36254, action = "hero_swarmprotocol", target = "map", icon = "ab_cort4printer_ult",
			desc = "Prints waves of kamikaze micro-drones that dive onto an area",
			range = 950, radius = 450, count = lin(12, 30, 1), dmg = lin(900, 1800, 100), aoe = 120, waves = 5, time = 5,
			cooldown = lin(110, 80, 5),
			text = tf("{count} drones x {dmg} dmg, range {range}, cd {cooldown} s"),
		}),
	},

	------------------------------------------------------------------------------------------- 6 Commando
	cort4commando = {
		title = "Commando, the Ghost", role = "Assassin", aiRole = "front", aiPick = 2,
		fx = 2.2,
		weapons = { { keys = { "commando_back_cannon" }, name = "Disintegrator" }, { keys = { "commando_stunner" }, name = "EMP Scattergun" } },
		a1 = ab({
			name = "Ghost Protocol", passive = true, icon = "ab_cort4commando_a1",
			desc = "Cloaks when it has not fired or been hit for a while, faster while cloaked; the first shot from cloak is an Ambush",
			delay = lin(5, 2.5, 0.1), speed = lin(0.1, 0.3, 0.01), ambush = lin(0.5, 1.5, 0.05), stun = lin(0.5, 2, 0.1),
			decloak = 50,
			text = tf("cloak after {delay.1} s, +{speed%} speed; Ambush +{ambush%} dmg, {stun.1} s stun"),
		}),
		a2 = ab({
			name = "Disruptor Mines", cmd = 36262, action = "hero_mines", target = "map", icon = "ab_cort4commando_a2",
			desc = "Scatters hidden EMP mines; an enemy that comes close sets one off",
			range = 650, count = lin(3, 8, 1), spread = 200, dmg = lin(700, 1700, 100), aoe = 180, emp = lin(1.5, 3, 0.1),
			trigger = 120, life = 60, max = 16, cooldown = lin(20, 12, 1),
			text = tf("{count} mines: {dmg} dmg + {emp.1} s EMP, cd {cooldown} s"),
		}),
		a3 = ab({
			name = "Shadowstep", cmd = 36263, action = "hero_shadowstep", target = "unit", icon = "ab_cort4commando_a3",
			desc = "Blinks behind an enemy and disintegrates it point-blank; it is Marked and takes more from the Commando",
			range = lin(550, 650, 10), dmg = lin(4000, 10000, 100), mark = lin(0.1, 0.15, 0.01), markTime = 5,
			cooldown = lin(18, 10, 1),
			text = tf("{dmg} dmg, Mark +{mark%} for 5 s, range {range}, cd {cooldown} s"),
		}),
		ult = ab({
			name = "Blackout", cmd = 36264, action = "hero_blackout", target = "map", icon = "ab_cort4commando_ult",
			desc = "An EMP storm: damage, a long stun, shields drained, and the enemies lose sight of the Commando",
			range = 650, radius = lin(500, 700, 10), dmg = lin(2000, 5000, 100), stun = lin(2, 4, 0.1), bonus = 0.2,
			cooldown = lin(120, 80, 5),
			text = tf("{dmg} dmg in {radius}, {stun.1} s stun, +20% vs stunned, range 650, cd {cooldown} s"),
		}),
	},

	------------------------------------------------------------------------------------------- 7 Deadeye
	cort4deadeye = {
		title = "Deadeye, the Marksman", role = "Sniper", aiRole = "back", aiPick = 2,
		fx = 2.2,
		weapons = { { keys = { "cor_burst_laser" }, name = "Heavy Blaster" } },
		a1 = ab({
			name = "Focus", passive = true, icon = "ab_cort4deadeye_a1",
			desc = "Volleys at the same target stack Focus (more damage); at 5 stacks the next volley pierces its whole line",
			per = lin(0.06, 0.15, 0.01), max = 5, line = 1200, big = 50000, bigBonus = 0.1,
			text = tf("+{per%} damage per stack (5), then a piercing volley"),
		}),
		a2 = ab({
			name = "Recon Flare", cmd = 36272, action = "hero_reconflare", target = "map", icon = "ab_cort4deadeye_a2",
			desc = "A flare reveals an area (cloaked units too); enemies in it are Exposed and take more damage",
			range = 2300, radius = lin(600, 1000, 10), duration = lin(8, 15, 0.5), vuln = lin(0.08, 0.2, 0.01),
			cooldown = lin(25, 15, 1),
			text = tf("reveals {radius} for {duration.1} s, +{vuln%} damage taken, cd {cooldown} s"),
		}),
		a3 = ab({
			name = "Tumble", cmd = 36273, action = "hero_tumble", target = "map", cursor = "Move", icon = "ab_cort4deadeye_a3",
			desc = "A quick evasive hop: the gun reloads at once and the next volley hits harder",
			range = lin(350, 600, 10), bonus = lin(0.1, 0.25, 0.01), window = 3, cooldown = lin(16, 9, 1),
			text = tf("hop {range}, instant reload, next volley +{bonus%}, cd {cooldown} s"),
		}),
		ult = ab({
			name = "Kill Shot", cmd = 36274, action = "hero_killshot", target = "unit", icon = "ab_cort4deadeye_ult",
			desc = "Channels 2 s, then fires a rail round that pierces its line; a kill refunds half the cooldown",
			range = lin(2000, 2300, 50), channel = 2, dmg = lin(20000, 36000, 1000), pct = lin(0.05, 0.12, 0.01), pctCap = 20000,
			pierce = 0.35, cooldown = lin(100, 60, 5),
			text = tf("{dmg} + {pct%} of max HP (cap 20000), range {range}, cd {cooldown} s"),
		}),
	},

	------------------------------------------------------------------------------------------- 8 Karganeth
	cort4karganeth = {
		title = "Karganeth, the Hydra", role = "Anti-air and anti-swarm", aiRole = "center", aiPick = 2,
		fx = 2.2,
		weapons = { { keys = { "super_missile" }, name = "Super Missiles" }, { keys = { "karg_shoulder" }, name = "AA Pods" } },
		a1 = ab({
			name = "Hydra Lock", passive = true, icon = "ab_cort4karganeth_a1",
			desc = "The shoulder pods lock several enemies at once and fire a micro-missile at each (double against aircraft)",
			period = lin(4, 2, 0.1), targets = lin(2, 8, 1), radius = 1300, dmg = lin(800, 2000, 50), air = 2,
			text = tf("every {period.1} s: {targets} missiles x {dmg} dmg (x2 vs air)"),
		}),
		a2 = ab({
			name = "Flak Canopy", cmd = 36282, action = "hero_flakcanopy", icon = "ab_cort4karganeth_a2",
			desc = "A flak umbrella shoots down incoming shells, rockets and bombs, and the AA pods hit harder",
			radius = lin(700, 1100, 10), duration = 8, rate = lin(1, 3, 0.25), aa = lin(0.5, 1.5, 0.05), cooldown = lin(35, 22, 1),
			text = tf("8 s: {rate.1} intercepts/s in {radius}, +{aa%} AA damage, cd {cooldown} s"),
		}),
		a3 = ab({
			name = "Adaptive Plating", passive = true, icon = "ab_cort4karganeth_a3",
			desc = "Three hits of one damage type within 4 s: the plating adapts and takes less of that type for 10 s (2 types)",
			reduce = lin(0.1, 0.3, 0.01), hits = 3, window = 4, duration = 10, types = 2,
			text = tf("-{reduce%} from an adapted damage type"),
		}),
		ult = ab({
			name = "Hydra Unleashed", cmd = 36284, action = "hero_hydra", icon = "ab_cort4karganeth_ult",
			desc = "Grows, speeds up and fires a lock volley every second on top of its own weapons",
			duration = lin(8, 12, 0.5), scale = 1.2, speed = 0.3, targets = lin(4, 10, 1), dmg = lin(600, 1150, 50),
			radius = 1300, air = 2, cooldown = lin(110, 80, 5),
			text = tf("{duration.1} s: {targets} missiles x {dmg} every second, cd {cooldown} s"),
		}),
	},

	------------------------------------------------------------------------------------------- 9 Cataphract
	cort4cataphract = {
		title = "Cataphract, the Lancer", role = "Hover flanker", aiRole = "front", aiPick = 2,
		fx = 2.2,
		weapons = { { keys = { "corsok_laser" }, name = "Disruptor Bolt" }, { keys = { "depthcharge" }, name = "Depth Charges" } },
		a1 = ab({
			name = "Lance Charge", cmd = 36291, action = "hero_lancecharge", target = "map", cursor = "Move", icon = "ab_cort4cataphract_a1",
			desc = "Boosts forward at four times its speed, ramming everything on the path; the next bolt fires at once and harder",
			range = lin(1040, 1690, 10), land = lin(800, 1300, 10), dmg = lin(600, 1500, 100), knock = 150,
			bolt = lin(0.1, 0.25, 0.01), cooldown = lin(18, 10, 1),
			text = tf("charge {land} (+30% on water), {dmg} dmg, next bolt +{bolt%}, cd {cooldown} s"),
		}),
		a2 = ab({
			name = "Disruption", passive = true, icon = "ab_cort4cataphract_a2",
			desc = "Each bolt adds a Disruption stack (slower); at max stacks the target is EMP-stunned",
			max = lin(3, 6, 1), slow = 0.08, time = 4, stun = lin(1, 2.5, 0.1),
			text = tf("max {max} stacks, -8% speed each, then {stun.1} s stun"),
		}),
		a3 = ab({
			name = "Phase Decoy", cmd = 36293, action = "hero_phasedecoy", icon = "ab_cort4cataphract_a3",
			desc = "Leaves a hologram that taunts the enemies and explodes; the Cataphract cloaks and speeds away",
			hp = lin(0.15, 0.4, 0.01), life = 6, taunt = 800, cloak = 2, speed = 0.5, speedTime = 4, dmg = lin(3000, 10000, 100),
			aoe = 250, cooldown = lin(28, 16, 1),
			text = tf("decoy {hp%} HP for 6 s, explodes for {dmg}, cd {cooldown} s"),
		}),
		ult = ab({
			name = "Lancer's Gauntlet", cmd = 36294, action = "hero_gauntlet", target = "unit", icon = "ab_cort4cataphract_ult",
			desc = "Chains lance dashes through the most valuable enemies around, untargetable meanwhile",
			range = 900, dashes = lin(3, 7, 1), dmg = lin(8000, 16000, 500), hop = 0.4, cooldown = lin(100, 70, 5),
			text = tf("{dashes} dashes x {dmg} dmg + Disruption, cd {cooldown} s"),
		}),
	},
	------------------------------------------------------------------------------------------- 10 Negotiator (v23)
	-- command ids 36296 + slot (a1 = 36296 unused, passive): the free slots 6..9 of row 9 (row 10 = 36301+ belongs to Legion)
	cort4negotiator = {
		title = "Negotiator, the Last Argument", role = "Rocket artillery", aiRole = "back", aiPick = 2, xpRate = 0.15,
		fx = 2.2,
		weapons = { { keys = { "cortruck_rocket" }, name = "Starburst Rockets" } },
	},
}

-- the Vesuvius siege shells (Siege Mode): copies of its cannon that leave lava (api.swapWeapons "magma")
heroes.cort4vesuvius.weaponCopies = {
	magma = { keys = { "corlevlr_weapon" }, set = { rgbcolor = "1 0.35 0.05", name = "Magma shell" } },
}

-- v23: the rocket-artillery kit (warhead toggles + passive Rocket Mastery)
for k, v in pairs(H.rocketModes({ 36296, 36297, 36298 }, "hero_negotiator", { "ab_cort4armageddon_a2", "ab_cort4vesuvius_a2", "ab_cort4armageddon_ult", "ab_cort4vesuvius_a3" })) do
	heroes.cort4negotiator[k] = v
end

return heroes, { "cort4bastion", "cort4colossus", "cort4hellwalker", "cort4armageddon", "cort4vesuvius",
	"cort4printer", "cort4commando", "cort4deadeye", "cort4karganeth", "cort4cataphract", "cort4negotiator" }
