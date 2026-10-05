-- Custom heroes (denysfast/bar-game), v19: the Legion heroes (altar legt4gant; v23: 11th, Boreas). Included by
-- luarules/configs/t4_heroes.lua with the shared table H as `...`; returns `defs, order`. Format: header of
-- luarules/configs/heroes/arm.lua. Design: doc/v19-heroes/roster_leg.md. Every ability is kind = "custom": the
-- behaviour lives in luarules/heroes/<hero>.lua (shared helpers luarules/heroes/legt4_lib.lua).
-- Damage / heal numbers here are BASE values: the modules multiply them by api.power(h) (ability power, grows with the
-- hero level). Dash abilities (Phase Rail, Storm Charge, Surge, Burrow) have a huge `range` so a click anywhere goes
-- off at once; the module clamps the move to `reach`. Command ids: Legion block 36301-36331 (Boreas 36329-36331).
local H = ...
local lin, tf = H.lin, H.textf

local DASH = 99999

local heroes = {
	---------------------------------------------------------------------------- 1. Helios
	legt4helios = {
		title = "Helios, the Sunbringer", role = "Heat / support", aiRole = "center", aiPick = 2.5,
		fx = 2.2,
		weapons = { { keys = { "heatray1" }, name = "Heat Rays" }, { keys = { "ultraheavyriotcannon" }, name = "Riot Cannons" }, { keys = { "legflak_gun" }, name = "Flak Battery" } },
		a1 = {
			name = "Solar Heat", kind = "custom", passive = true, icon = "ab_legt4helios_a1",
			desc = "Heat rays pile Heat on their target; every stack makes it take more damage from Helios, and at 10 Heat it ignites: a blast that spreads Heat to the next ones (a unit takes one ignite blast per 0.5 s)",
			perStack = lin(0.02, 0.04, 0.001), maxHeat = 10, igniteFlat = lin(400, 1200, 50), ignitePct = lin(0.01, 0.02, 0.005),
			igniteCap = lin(3000, 6000, 500), igniteRadius = lin(150, 220, 5), spread = lin(1, 2, 1), decay = 4, immune = 10,
			text = tf("+{perStack%} damage taken per Heat; ignite {igniteFlat} + {ignitePct%} max HP in {igniteRadius}, spreads {spread} Heat"),
		},
		a2 = {
			name = "Corona Flare", kind = "custom", cmd = 36301, action = "hero_coronaflare", icon = "ab_legt4helios_a2",
			desc = "A solar burst around Helios: burns and heats the enemies, repairs the allies",
			radius = lin(600, 900, 10), dmg = lin(1000, 3500, 100), heat = lin(4, 8, 1), heal = lin(3000, 12000, 100),
			cooldown = lin(30, 18, 1),
			text = tf("{radius} radius: {dmg} dmg and +{heat} Heat to enemies, allies +{heal} HP, cd {cooldown} s"),
		},
		a3 = {
			name = "Sunspot", kind = "custom", cmd = 36302, action = "hero_sunspot", target = "map", icon = "ab_legt4helios_a3",
			desc = "A miniature sun hovers over the point and lashes the enemies under it with heat rays; ignitions under it make it last longer",
			range = 1400, duration = lin(8, 14, 1), targets = lin(2, 4, 1), radius = lin(450, 700, 10), dmg = lin(100, 250, 25),
			extendMax = 6, cooldown = lin(26, 16, 1),
			text = tf("{duration} s, every 0.5 s {targets} lashes of {dmg} in {radius}, cd {cooldown} s"),
		},
		ult = {
			name = "Sunstrike", kind = "custom", cmd = 36303, action = "hero_sunstrike", target = "map", icon = "ab_legt4helios_ult",
			desc = "A column of sunlight burns an area for 6 s, creeping after the hottest enemy, and collapses: every heated enemy around ignites",
			range = 1750, radius = lin(250, 350, 10), tick = lin(100, 220, 10), duration = 6, creep = 90, collapse = 900,
			cooldown = lin(100, 60, 5),
			text = tf("{radius} radius, {tick} dmg per 0.2 s for 6 s, collapse ignites in 900, cd {cooldown} s"),
		},
		weaponCopies = {
			corona = { keys = { "heatray1" }, set = { rgbcolor = "1 0.95 0.75", rgbcolor2 = "1 1 1", thickness = 5.6, corethickness = 0.5 } },
		},
	},

	---------------------------------------------------------------------------- 2. Starfall
	legt4starfall = {
		title = "Starfall, the Astronomer", role = "Orbital artillery", aiRole = "back", aiPick = 2, xpRate = 0.25,
		fx = 2.5,
		weapons = { { keys = { "shocker_low" }, name = "Starfire Cannon" } },
		a1 = {
			name = "Constellation", kind = "custom", passive = true, icon = "ab_legt4starfall_a1",
			desc = "The first shell of each salvo leaves a Star for 8 s; consecutive Stars link into burning constellation lines",
			stars = lin(3, 7, 1), link = lin(1200, 2000, 50), dmg = lin(250, 900, 10), width = 40, ttl = 8,
			text = tf("up to {stars} Stars, linked within {link}: {dmg} dmg per 0.5 s on the lines"),
		},
		a2 = {
			name = "Gravity Lens", kind = "custom", cmd = 36304, action = "hero_gravitylens", target = "map", icon = "ab_legt4starfall_a2",
			desc = "A gravity well for 6 s pulls the enemies to its centre; the cannon reloads at once and its shells landing inside hit harder",
			range = 6900, radius = lin(400, 650, 10), pull = lin(30, 70, 5), bonus = lin(0.15, 0.3, 0.01), duration = 6,
			cooldown = lin(40, 24, 1),
			text = tf("{radius} radius, pull {pull}/s, +{bonus%} shell damage inside, cd {cooldown} s"),
		},
		a3 = {
			name = "Deep Sky Eye", kind = "custom", cmd = 36305, action = "hero_skyeye", target = "map", icon = "ab_legt4starfall_a3",
			desc = "An orbital eye reveals an area (sight, radar, cloaked units); the enemies under it are Observed and take more damage from everyone",
			range = 6900, radius = lin(1200, 2400, 50), duration = lin(10, 20, 1), vuln = lin(0.05, 0.12, 0.01),
			cooldown = lin(50, 28, 1),
			text = tf("{radius} radius for {duration} s, Observed take +{vuln%} damage, cd {cooldown} s"),
		},
		ult = {
			name = "Starfall", kind = "custom", cmd = 36306, action = "hero_starfall", target = "map", icon = "ab_legt4starfall_ult",
			desc = "Meteors rain on an area for 8 s, each leaving a Star; a final Comet hits the centre",
			range = 6900, radius = 750, count = lin(10, 24, 1), dmg = lin(500, 700, 50), aoe = 280, comet = lin(1500, 3500, 500),
			cometAoe = 600, duration = 8, cooldown = lin(120, 80, 5),
			text = tf("{count} meteors x {dmg} ({aoe} radius), Comet {comet} in 600, cd {cooldown} s"),
		},
		weaponDefs = function(T4)
			local meteor = T4.shellWeapon({
				name = "Starfall meteor", aoe = 16, damage = 0, ceg = "custom:ministarfire-explosion", cegtag = T4.FX.ref("starfire-small", 2.5),
				rgb = "0.6 0.75 1", size = 18, soundhit = "xplolrg2", range = 9000, velocity = 1100,
			})
			local comet = T4.shellWeapon({
				name = "Starfall comet", aoe = 16, damage = 0, ceg = "custom:starfire-explosion", cegtag = T4.FX.ref("starfire-small", 2.5),
				rgb = "0.85 0.9 1", size = 42, soundhit = "xplonuk3", range = 9000, velocity = 1300,
			})
			for _, w in ipairs({ meteor, comet }) do
				w.customparams = { t4_ability = 1 }
				w.targetable = 0
			end
			return { meteor = meteor, comet = comet }
		end,
	},

	---------------------------------------------------------------------------- 3. Longinus
	legt4longinus = {
		title = "Longinus, the Spear", role = "Titan hunter", aiRole = "center", aiPick = 2,
		fx = 2.2,
		weapons = { { keys = { "t3_rail_accelerator" }, name = "Rail Accelerators" } },
		a1 = {
			name = "Sunder", kind = "custom", passive = true, icon = "ab_legt4longinus_a1",
			desc = "Rail hits crack the target's armour: every Sunder stack makes it take more damage from all sources (2 stacks a hit on heroes and 10000+ metal targets)",
			perStack = lin(0.03, 0.06, 0.005), maxStacks = lin(5, 10, 1), duration = 6, bigCost = 10000,
			text = tf("+{perStack%} damage taken per stack, up to {maxStacks} stacks for 6 s"),
		},
		a2 = {
			name = "Hunter's Mark", kind = "custom", cmd = 36307, action = "hero_huntmark", target = "unit", icon = "ab_legt4longinus_a2",
			desc = "Marks the prey: revealed, the rails focus it, Longinus deals more damage to it; a marked kill resets the cooldown and heals",
			range = lin(1300, 1500, 50), duration = lin(6, 10, 1), bonus = lin(0.15, 0.3, 0.01), heal = lin(0.04, 0.12, 0.005),
			healCap = 40000, cooldown = lin(24, 12, 1),
			text = tf("{duration} s, +{bonus%} damage to it, kill: reset + heal {heal%} of its max HP, cd {cooldown} s"),
		},
		a3 = {
			name = "Phase Rail", kind = "custom", cmd = 36308, action = "hero_phaserail", target = "map", icon = "ab_legt4longinus_a3",
			desc = "Rail-phases to the point in 0.4 s, untouchable and through units; the enemies on the path are hit and Sundered; the rails reload on arrival",
			range = DASH, reach = lin(600, 1100, 50), dmg = lin(2500, 8000, 100), width = 160, cooldown = lin(28, 14, 1),
			text = tf("up to {reach}, {dmg} to the path (a shared budget), rails reload, cd {cooldown} s"),
		},
		ult = {
			name = "Spear of Longinus", kind = "custom", cmd = 36309, action = "hero_spear", target = "unit", icon = "ab_legt4longinus_ult",
			desc = "A 1.5 s charge, then one rail through the target and on along a line, through shields and terrain; the line burns for 5 s",
			range = lin(1300, 1500, 50), pct = lin(0.04, 0.08, 0.005), flat = lin(5000, 12000, 500), line = lin(1600, 2400, 100),
			lineDmg = lin(3000, 7000, 500), burn = lin(400, 1200, 50), charge = 1.5, width = 100, cooldown = lin(100, 60, 5),
			text = tf("{pct%} max HP + {flat}; the line ({line}) shares {lineDmg} x4, burns {burn}/s, cd {cooldown} s"),
		},
		weaponDefs = function(T4, ud)
			local rail = ud.weapondefs.t3_rail_accelerator
			local w = T4.weaponFrom(rail, { damage = 0, noexplode = true, range = 8000, name = "Spear of Longinus" })
			w.thickness = (rail.thickness or 2) * 4
			w.corethickness = (rail.corethickness or 0.3) * 2
			w.laserflaresize = (rail.laserflaresize or 8) * 3
			w.rgbcolor = "0.4 0.9 1"
			w.weaponvelocity = 4000
			w.customparams = { t4_ability = 1 }
			return { spear = w }
		end,
	},

	---------------------------------------------------------------------------- 4. Tempest
	legt4tempest = {
		title = "Tempest, the Stormblade", role = "Melee assault", aiRole = "front", aiPick = 2.5,
		fx = 2.5,
		weapons = { { keys = { "shotgun" }, name = "Storm Shotgun" }, { keys = { "adv_rocket" }, name = "Rocket Pods" }, { keys = { "leg_t2_microflak_mobile" }, name = "Micro Flak" } },
		a1 = {
			name = "Momentum", kind = "custom", passive = true, icon = "ab_legt4tempest_a1",
			desc = "Running builds Momentum (faster with it); at 100 the next shotgun blast is a Breach Shot: multiplied, piercing, knocking back",
			speedMax = lin(0.10, 0.25, 0.01), breach = lin(1.6, 3.0, 0.1), knock = lin(80, 200, 10), pierce = 400,
			text = tf("up to +{speedMax%} speed at 100 Momentum; Breach Shot x{breach.1} damage, knockback {knock}"),
		},
		a2 = {
			name = "Storm Charge", kind = "custom", cmd = 36310, action = "hero_stormcharge", target = "unit_or_map", icon = "ab_legt4tempest_a2",
			desc = "Dashes in a lightning charge: the enemies on the path are hit and stunned, a thunderclap on arrival; the next shot is a Breach Shot",
			range = lin(700, 1200, 50), speed = 900, pathDmg = lin(300, 900, 50), stun = lin(0.5, 1.5, 0.1), clap = lin(400, 1400, 100),
			clapRadius = lin(250, 350, 10), cooldown = lin(22, 10, 1),
			text = tf("{range} range, path {pathDmg} + {stun.1} s stun, clap {clap} in {clapRadius}, cd {cooldown} s"),
		},
		a3 = {
			name = "Storm Echoes", kind = "custom", cmd = 36311, action = "hero_echoes", icon = "ab_legt4tempest_a3",
			desc = "Storm images of Tempest fight beside it; they fire Breach Shots with it and explode when they fade",
			count = lin(1, 3, 1), duration = lin(8, 14, 1), dmgShare = lin(0.2, 0.25, 0.01), hpShare = 0.15,
			boom = lin(800, 2000, 100), boomRadius = 200, cooldown = lin(50, 30, 1),
			text = tf("{count} images for {duration} s at {dmgShare%} damage, explode for {boom}, cd {cooldown} s"),
		},
		ult = {
			name = "Eye of the Storm", kind = "custom", cmd = 36312, action = "hero_eyestorm", icon = "ab_legt4tempest_ult",
			desc = "Tempest becomes a spinning storm: lightning lashes everything around, it takes half damage, cannot be stunned and reflects damage; it ends with a thunderclap",
			duration = lin(5, 8, 0.5), radius = lin(450, 650, 10), tick = lin(300, 700, 25), reflect = lin(0.25, 0.6, 0.01),
			clap = lin(5000, 15000, 250), clapRadius = 700, clapStun = lin(1, 2.5, 0.1), cooldown = lin(80, 55, 5),
			text = tf("{duration.1} s: {tick} per 0.2 s in {radius}, reflects {reflect%}, clap {clap}, cd {cooldown} s"),
		},
		weaponCopies = {
			storm = { keys = { "shotgun" }, set = { rgbcolor = "0.6 0.85 1", thickness = 3.4, corethickness = 0.6 } },
		},
	},

	---------------------------------------------------------------------------- 5. Myrmidon
	legt4myrmidon = {
		title = "Myrmidon, the Hive Mother", role = "Summoner / support", aiRole = "back", aiPick = 2, xpRate = 0.6,
		fx = 2.2,
		weapons = { { keys = { "plasma_low", "plasma_high" }, name = "Hive Mortars" }, { keys = { "light_antiair_missile" }, name = "AA Missiles" } },
		a1 = {
			name = "Drone Bay", kind = "custom", passive = true, icon = "ab_legt4myrmidon_a1",
			desc = "A hive of heat-ray drones guards her and attacks her targets; lost drones are rebuilt one at a time",
			drones = lin(2, 8, 1), rebuild = lin(12, 5, 0.5), leash = 1400,
			text = tf("{drones} drones, one rebuilt every {rebuild.1} s"),
		},
		a2 = {
			name = "Repair Swarm", kind = "custom", passive = true, icon = "ab_legt4myrmidon_a2",
			desc = "Idle drones beam-repair the most damaged allies near them; from rank 4 one drone, from rank 8 two stay on repair in combat",
			heal = lin(150, 600, 10), radius = 600,
			text = tf("{heal} HP/s per drone (heroes half, the Mother full)"),
		},
		a3 = {
			name = "Sacrificial Dive", kind = "custom", cmd = 36313, action = "hero_dive", target = "unit_or_map", icon = "ab_legt4myrmidon_a3",
			desc = "Drones dive onto the target like missiles and detonate; for 10 s the drones rebuild 3x faster",
			range = 1800, divers = lin(2, 8, 1), dmg = lin(600, 1500, 100), aoe = 180, cooldown = lin(30, 16, 1),
			text = tf("up to {divers} drones x {dmg} in {aoe}, cd {cooldown} s"),
		},
		ult = {
			name = "Hive Ascendant", kind = "custom", cmd = 36314, action = "hero_hive", toggle = true, icon = "ab_legt4myrmidon_ult",
			desc = "She roots and becomes a living hive: tougher, faster and longer-ranged cannons, a stream of swarm-mites, drones rebuilt fast. Cast again to end it",
			duration = lin(10, 16, 1), interval = lin(1.2, 0.8, 0.05), mites = lin(3, 8, 1), armor = 0.3, reload = 0.4, rangeBonus = 0.25,
			cooldown = lin(110, 70, 5),
			text = tf("up to {duration} s: +30% armour, cannons faster and +25% range, a mite every {interval.1} s (max {mites}), cd {cooldown} s"),
		},
	},

	---------------------------------------------------------------------------- 6. Keres
	legt4keres = {
		title = "Keres, the Death-Spirit", role = "Anti-swarm brawler", aiRole = "front", aiPick = 2.5,
		fx = 2.2,
		weapons = { { keys = { "legkeres_cannon" }, name = "Riot Cannon" }, { keys = { "legkeres_gatling" }, name = "Rotary Cannons" } },
		a1 = {
			name = "Soul Harvest", kind = "custom", passive = true, icon = "ab_legt4keres_a1",
			desc = "Every enemy dying near Keres gives Souls (1 per 500 metal, a hero 10); each Soul adds damage. Out of combat they slowly fade",
			cap = lin(20, 50, 1), perSoul = lin(0.004, 0.008, 0.0005), radius = 1000,
			text = function(r, H, b) return string.format("up to %d Souls, +%.1f%% damage each", H.val(b.cap, r), H.val(b.perSoul, r) * 100) end,
		},
		a2 = {
			name = "Death Grip", kind = "custom", cmd = 36315, action = "hero_deathgrip", target = "unit", icon = "ab_legt4keres_a2",
			desc = "A chain hook drags the target in front of Keres and stuns it; the riot cannon fires point-blank",
			range = lin(800, 950, 50), stun = lin(1, 2.5, 0.1), dmg = lin(1000, 3000, 100), splash = 300, cooldown = lin(20, 10, 1),
			text = tf("{range} range, {stun.1} s stun, {dmg} dmg in {splash}, cd {cooldown} s"),
		},
		a3 = {
			name = "Devour", kind = "custom", cmd = 36316, action = "hero_souldevour", target = "unit", icon = "ab_legt4keres_a3",
			desc = "Devours a broken non-hero enemy whole (no wreck): Keres heals a multiple of the HP it had left plus 10% of its max, and gains 5 Souls",
			range = 400, hpFlat = lin(8000, 30000, 500), hpPct = lin(0.25, 0.45, 0.01), heal = lin(1.0, 2.5, 0.05), healMax = 0.1, souls = 5,
			cooldown = lin(16, 7, 1),
			text = tf("below {hpFlat} HP or {hpPct%}: heal {heal%} of its HP + 10% max, cd {cooldown} s"),
		},
		ult = {
			name = "Danse Macabre", kind = "custom", cmd = 36317, action = "hero_macabre", icon = "ab_legt4keres_ult",
			desc = "Keres lets its Souls loose as hunting spirits that strike different enemies every second; it gains lifesteal",
			duration = lin(8, 12, 0.5), spirits = lin(10, 24, 1), dmg = lin(300, 800, 25), radius = 950, lifesteal = lin(0.1, 0.3, 0.01),
			cooldown = lin(90, 60, 5),
			text = tf("{duration.1} s: up to {spirits} spirits x {dmg}/s within {radius}, +{lifesteal%} lifesteal, cd {cooldown} s"),
		},
	},

	---------------------------------------------------------------------------- 7. Mukade
	legt4mukade = {
		title = "Mukade, the Great Centipede", role = "Burrowing assassin", aiRole = "front", aiPick = 2,
		fx = 2.2,
		weapons = { { keys = { "railgunt2" }, name = "Venom Rails" }, { keys = { "adv_rocket" }, name = "Rocket Pods" }, { keys = { "armmg_weapon" }, name = "Machine Guns" } },
		a1 = {
			name = "Burrow", kind = "custom", cmd = 36318, action = "hero_burrow", target = "map", icon = "ab_legt4mukade_a1",
			desc = "Dives underground (untargetable, unseen, cannot fire) and travels fast to the point, then erupts: damage and stun around",
			range = DASH, reach = lin(1500, 2600, 50), speedBonus = lin(0.4, 0.8, 0.05), maxTime = lin(4, 8, 0.5), dmg = lin(1400, 4500, 100),
			radius = lin(300, 450, 10), stun = lin(0.8, 1.6, 0.1), cooldown = lin(30, 14, 1),
			text = tf("up to {reach}, eruption {dmg} in {radius} + {stun.1} s stun, cd {cooldown} s"),
		},
		a2 = {
			name = "Venom Rails", kind = "custom", passive = true, icon = "ab_legt4mukade_a2",
			desc = "Rail hits inject Venom (a share of the target's current HP per second); a venomed unit that dies bursts into an acid pool",
			pct = lin(0.02, 0.05, 0.005), minDps = 200, maxDps = lin(1500, 5000, 100), duration = 4, pool = lin(150, 250, 10),
			poolDps = lin(400, 1200, 50),
			text = tf("{pct%} of current HP/s for 4 s (max {maxDps}/s), acid pool {poolDps}/s in {pool}"),
		},
		a3 = {
			name = "Molting", kind = "custom", passive = true, icon = "ab_legt4mukade_a3",
			desc = "Below half health Mukade sheds its carapace: the shed segments explode, it heals over 3 s and hardens for 5 s",
			icd = lin(90, 45, 5), heal = lin(0.10, 0.30, 0.01), armor = lin(0.25, 0.5, 0.01), dmg = lin(2000, 6000, 100), radius = 300,
			text = tf("heal {heal%} over 3 s, +{armor%} armour 5 s, burst {dmg}; every {icd} s"),
		},
		ult = {
			name = "Coil", kind = "custom", cmd = 36319, action = "hero_coil", target = "unit", icon = "ab_legt4mukade_ult",
			desc = "Lunges onto a big target and coils around it: it is crushed (a share of its max HP per second) and stunned; Mukade takes less damage and keeps firing",
			range = 700, duration = lin(3, 5, 0.5), pct = lin(0.01, 0.017, 0.001), flat = lin(500, 1500, 100), reduce = 0.4, minCost = 2000,
			cooldown = lin(90, 60, 5),
			text = tf("{duration.1} s: {pct%} max HP + {flat} per s, -40% damage taken, cd {cooldown} s"),
		},
	},

	---------------------------------------------------------------------------- 8. Charybdis
	legt4charybdis = {
		title = "Charybdis, the Maelstrom", role = "Crowd control hover", aiRole = "center", aiPick = 2,
		fx = 2.2,
		weapons = { { keys = { "heat_ray" }, name = "Sweepfire Heatray" }, { keys = { "parabolic_rockets" }, name = "Rocket Racks" }, { keys = { "depthcharge" }, name = "Depth Charges" } },
		a1 = {
			name = "Undertow", kind = "custom", passive = true, icon = "ab_legt4charybdis_a1",
			desc = "Heat-ray hits drag the target down (stacking slow, twice as fast over water); heavily slowed targets take more from its rockets and depth charges",
			per = lin(0.04, 0.08, 0.005), max = lin(0.3, 0.6, 0.01), duration = 3, bonus = lin(0.15, 0.35, 0.01), threshold = 0.3,
			text = tf("-{per%} speed per hit up to -{max%}; +{bonus%} rocket damage on slowed targets"),
		},
		a2 = {
			name = "Waterspout", kind = "custom", cmd = 36320, action = "hero_waterspout", target = "map", icon = "ab_legt4charybdis_a2",
			desc = "A waterspout erupts at the point: enemies are tossed up and stunned; a mist stays 5 s and drowns them in Undertow (bigger over water)",
			range = 1100, radius = lin(250, 380, 10), stun = lin(1, 2, 0.1), dmg = lin(1000, 3200, 100), mist = 5, cooldown = lin(22, 12, 1),
			text = tf("{radius} radius, {dmg} dmg, {stun.1} s stun, mist 5 s, cd {cooldown} s"),
		},
		a3 = {
			name = "Surge", kind = "custom", cmd = 36321, action = "hero_surge", target = "map", icon = "ab_legt4charybdis_a3",
			desc = "Rides a wave to the point: enemies on the path are knocked aside, hit and slowed; the wake slows. Further and twice as often over water",
			range = DASH, reach = lin(500, 900, 25), dmg = lin(1500, 6000, 100), width = 240, knock = 150, wakeSlow = 0.4, wake = 4,
			cooldown = lin(16, 8, 1),
			text = tf("up to {reach}, {dmg} to the path, wake -40% speed, cd {cooldown} s (halved over water)"),
		},
		ult = {
			name = "Maw of the Deep", kind = "custom", cmd = 36322, action = "hero_maw", target = "map", icon = "ab_legt4charybdis_ult",
			desc = "A maelstrom pulls enemies to its maw for 7 s; the core swallows small units whole; it ends with a tidal blast",
			range = 1100, radius = lin(700, 1000, 10), duration = 7, pull = lin(60, 130, 5), outer = lin(100, 250, 10),
			core = lin(400, 1000, 50), coreRadius = 160, swallow = lin(3000, 8000, 500), blast = lin(1500, 4500, 100),
			cooldown = lin(110, 75, 5),
			text = tf("{radius} radius, pull {pull}/s, {outer}/s ({core}/s in the core), swallows < {swallow} HP, blast {blast}, cd {cooldown} s"),
		},
	},

	---------------------------------------------------------------------------- 9. Apollyon
	legt4apollyon = {
		title = "Apollyon, the Locust King", role = "Suppression / siege", aiRole = "center", aiPick = 2,
		fx = 2.2,
		weapons = { { keys = { "legapollyon_gatling_big", "legapollyon_gatling_small" }, name = "Twin Gatlings" }, { keys = { "legapollyon_missile" }, name = "Catapult Racks" } },
		a1 = {
			name = "Spin-Up", kind = "custom", passive = true, icon = "ab_legt4apollyon_a1",
			desc = "Continuous gatling fire spins the barrels faster; at full spin they fire incendiary rounds",
			rate = lin(0.03, 0.05, 0.005), max = lin(0.3, 0.8, 0.05), hot = lin(0.2, 0.4, 0.01), burn = lin(300, 800, 25),
			text = tf("+{rate%} fire rate per s up to +{max%}; full spin: +{hot%} damage, burn {burn}/s"),
		},
		a2 = {
			name = "Locust Swarm", kind = "custom", cmd = 36323, action = "hero_locusts", target = "map", icon = "ab_legt4apollyon_a2",
			desc = "Micro-rockets in three waves, each homing on a different enemy around the point; spare ones burn the ground",
			range = lin(1600, 2200, 50), count = lin(12, 36, 1), dmg = lin(600, 1200, 50), aoe = 120, radius = 500,
			cooldown = lin(22, 12, 1),
			text = tf("{count} rockets x {dmg} ({aoe} radius) in {radius}, cd {cooldown} s"),
		},
		a3 = {
			name = "Siege Lockdown", kind = "custom", cmd = 36324, action = "hero_lockdown", toggle = true, icon = "ab_legt4apollyon_a3",
			desc = "Anchors itself: immobile, armoured, longer weapon range, faster rocket racks, gatlings spun up. Cast again to end it",
			duration = lin(8, 15, 1), armor = lin(0.25, 0.5, 0.01), range = lin(0.2, 0.35, 0.01), cooldown = lin(30, 18, 1),
			text = tf("up to {duration} s: +{armor%} armour, +{range%} range, cd {cooldown} s"),
		},
		ult = {
			name = "Plague of Locusts", kind = "custom", cmd = 36325, action = "hero_plague", target = "map", icon = "ab_legt4apollyon_ult",
			desc = "Locks in place and rains locust rockets on an area for 10 s; every impact leaves fire",
			range = 2200, count = lin(60, 120, 5), dmg = lin(180, 330, 10), aoe = 150, fire = lin(50, 100, 10), radius = 700,
			duration = 10, cooldown = lin(120, 80, 5),
			text = tf("{count} locusts x {dmg} in {radius}, fire {fire}/s, cd {cooldown} s"),
		},
		weaponDefs = function(T4)
			local w = T4.missileWeapon({
				name = "Locust micro-rocket", damage = 0, aoe = 16, model = "legsmallrocket.s3o", velocity = 900, turnrate = 34000,
				ceg = "custom:genericshellexplosion-medium-bomb", cegtag = "missiletrailsmall", soundhit = "xplomed2", soundstart = "rocklit1",
				range = 4000,
			})
			w.smoketrail = false
			w.weapontimer = 0.6
			w.customparams = { t4_ability = 1 }
			return { locust = w }
		end,
		weaponCopies = {
			hot = { keys = { "legapollyon_gatling_big", "legapollyon_gatling_small" }, set = { rgbcolor = "1 0.35 0.08", size = 3.4 } },
		},
	},

	---------------------------------------------------------------------------- 10. Medusa
	legt4medusa = {
		title = "Medusa, the Gorgon", role = "Petrify artillery", aiRole = "back", aiPick = 2, xpRate = 0.5,
		fx = 2.5,
		weapons = { { keys = { "legmed_missile" }, name = "Serpent Missiles" } },
		a1 = {
			name = "Serpent Bite", kind = "custom", passive = true, icon = "ab_legt4medusa_a1",
			desc = "Missile hits add Petrify (each stack slows); at 5 stacks the target turns to stone: stunned and taking more damage",
			slow = lin(0.06, 0.1, 0.005), need = 5, stone = lin(1.5, 3, 0.1), vuln = lin(0.2, 0.4, 0.01), immune = 6, heroIcd = 8,
			duration = 6,
			text = tf("-{slow%} speed per stack; stone {stone.1} s, +{vuln%} damage taken"),
		},
		a2 = {
			name = "Gorgon's Gaze", kind = "custom", cmd = 36326, action = "hero_gaze", target = "map", icon = "ab_legt4medusa_a2",
			desc = "Her gaze sweeps a cone: every enemy in it gains Petrify stacks; enemies already stone shatter",
			range = lin(1400, 2000, 50), angle = lin(40, 60, 2), stacks = lin(3, 5, 1), shatterPct = lin(0.02, 0.06, 0.005),
			heroPct = lin(0.04, 0.1, 0.005), cap = 40000, splash = lin(250, 800, 50), splashRadius = 150, cooldown = lin(28, 16, 1),
			text = tf("{angle} deg cone to {range}, +{stacks} stacks; shatter {shatterPct%} max HP + {splash}, cd {cooldown} s"),
		},
		a3 = {
			name = "Snake Pit", kind = "custom", cmd = 36327, action = "hero_snakepit", target = "map", icon = "ab_legt4medusa_a3",
			desc = "A nest of serpents circles the point and bites every enemy in it (once a second each), adding Petrify",
			range = 2600, serpents = lin(6, 12, 1), radius = lin(350, 450, 10), duration = lin(6, 9, 0.5), dmg = lin(250, 650, 50),
			cooldown = lin(26, 15, 1),
			text = tf("{serpents} serpents in {radius} for {duration.1} s, bites {dmg}, cd {cooldown} s"),
		},
		ult = {
			name = "Stone Garden", kind = "custom", cmd = 36328, action = "hero_stonegarden", target = "map", icon = "ab_legt4medusa_ult",
			desc = "After 1.5 s everything in the area turns to stone (structures too) and takes more damage; when the stone ends every statue shatters",
			range = 2600, radius = lin(600, 900, 10), stone = lin(3, 5, 0.5), vuln = lin(0.15, 0.25, 0.01), shatterPct = lin(0.005, 0.015, 0.001),
			heroPct = lin(0.03, 0.06, 0.005), cap = 40000, splash = lin(250, 700, 50), splashRadius = 200, cooldown = lin(110, 75, 5),
			text = tf("{radius} radius, stone {stone.1} s (+{vuln%} damage), shatter {shatterPct%} + {splash}, cd {cooldown} s"),
		},
	},

	---------------------------------------------------------------------------- 11. Boreas
	legt4boreas = {
		title = "Boreas, the Firestorm", role = "Incendiary rocket artillery", aiRole = "back", aiPick = 2, xpRate = 0.5,
		fx = 2.5,
		weapons = { { keys = { "armtruck_rocket" }, name = "Firestorm Racks" } },
		a1 = {
			name = "Scorched Earth", kind = "custom", passive = true, icon = "ab_legt4helios_a1",
			desc = "Every rocket impact leaves the ground burning for 4 s; enemies standing in the fire take more damage from Boreas",
			dps = lin(250, 800, 25), radius = lin(160, 240, 10), vuln = lin(0.05, 0.15, 0.01), duration = 4, maxFires = 6,
			text = tf("burning ground {dps}/s in {radius} for 4 s; +{vuln%} damage from Boreas to the burning"),
		},
		a2 = {
			name = "Hellfire Volley", kind = "custom", cmd = 36329, action = "hero_hellfire", target = "map", icon = "ab_legt4apollyon_a2",
			desc = "The racks ripple-fire a volley of incendiary rockets onto the point (within weapon range); each sets the ground on fire",
			range = lin(2200, 2600, 50), count = lin(4, 10, 1), dmg = lin(700, 1600, 50), aoe = 200, radius = 320,
			cooldown = lin(24, 14, 1),
			text = tf("{count} rockets x {dmg} ({aoe} radius) in {radius} at up to {range}, cd {cooldown} s"),
		},
		a3 = {
			name = "Thermal Vent", kind = "custom", cmd = 36330, action = "hero_thermalvent", icon = "ab_legt4helios_a2",
			desc = "Vents the reactors: a burst of flame around Boreas, then it runs hot - faster and tougher for a few seconds, leaving fire behind",
			duration = lin(3, 6, 0.5), speed = lin(0.25, 0.5, 0.05), armor = lin(0.1, 0.25, 0.01), burst = lin(400, 1200, 50),
			burstRadius = 320, cooldown = lin(30, 16, 1),
			text = tf("{burst} in {burstRadius}, then {duration.1} s +{speed%} speed, +{armor%} armour, cd {cooldown} s"),
		},
		ult = {
			name = "Firestorm", kind = "custom", cmd = 36331, action = "hero_firestorm", target = "map", icon = "ab_legt4apollyon_ult",
			desc = "Marks an area within weapon range; after 1.5 s a rocket storm falls on it for 6 s and the whole area burns",
			range = 2600, radius = lin(500, 700, 25), count = lin(20, 40, 2), dmg = lin(400, 800, 50), aoe = 180,
			burn = lin(200, 500, 25), warn = 1.5, duration = 6, cooldown = lin(110, 75, 5),
			text = tf("after 1.5 s: {count} rockets x {dmg} in {radius} over 6 s, area burns {burn}/s, cd {cooldown} s"),
		},
		weaponDefs = function(T4)
			local w = T4.missileWeapon({
				name = "Boreas incendiary rocket", damage = 0, aoe = 16, model = "leglargerocket.s3o", velocity = 800, turnrate = 30000,
				ceg = "custom:genericshellexplosion-large-bomb", cegtag = "missiletrailmedium", soundhit = "xplomed4", soundstart = "Rockhvy1",
				range = 4000,
			})
			w.weapontimer = 0.8
			w.customparams = { t4_ability = 1 }
			return { firerocket = w }
		end,
	},
}

return heroes, { "legt4helios", "legt4starfall", "legt4longinus", "legt4tempest", "legt4myrmidon",
	"legt4keres", "legt4mukade", "legt4charybdis", "legt4apollyon", "legt4medusa", "legt4boreas" }
