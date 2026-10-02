# v19 roster — Legion (design, wave 1)

Ten Legion heroes for v19: the 4 current ones redone, plus 6 new ones built on Legion T3, Scavenger and T2 models.
How to read the numbers:
- `a → b` is rank 1 → rank 10, linear in between (`H.lin(a, b)`).
- Damage, heal and absorb numbers are **base values**. Core multiplies them by `api.power(h)`, which adds +1% per hero level.
- Cooldowns are in seconds and ranges in elmos.
- "Heroes 50%" means a hero takes half the damage, stun or pull. Structures are never pulled or dragged.
- Active command ids use a proposed **Legion block 36300–36399**. The orchestrator should check it against the arm and cor blocks.

Legion palette used in the FX (RGBA):

| Name | RGBA | Used by |
|---|---|---|
| SOLAR | {1, .85, .45, 1} | heat (Helios, Apollyon) |
| EMBER | {1, .45, .1, 1} | heat (Helios, Apollyon) |
| STAR | {.55, .75, 1, 1} | Starfall |
| VOID | {.7, .5, 1, 1} | Starfall |
| RAIL | {.4, .9, 1, 1} | Longinus |
| STORM | {.6, .8, 1, 1} | Tempest |
| HIVE | {1, .6, .2, 1} | Myrmidon |
| HEAL | {.45, 1, .55, 1} | Myrmidon |
| SOUL | {.55, 1, .8, 1} | Keres |
| AMBER | {.9, .62, .3, 1} | Mukade |
| VENOM | {.5, 1, .25, 1} | Mukade |
| TIDE | {.3, .7, 1, 1} | Charybdis |
| FOAM | {.85, .95, 1, 1} | Charybdis |
| GORGON | {.3, 1, .5, 1} | Medusa |
| STONE | {.65, .7, .6, 1} | Medusa |

## Summary

HP, DPS and speed are the level-1 targets for `T4.heroBalance`. Cost is always 100k / 2M / 2.5M.

| # | unitname | Title | Base unit file | Scale / fp / movedef | Role / aiRole | HP | DPS | Speed | Range ×, aoe × |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `legt4helios` | Helios, the Sunbringer | `units/Legion/T3/legeheatraymech.lua` | 1.8 / 11 / T4BOT11 | heat combo + support / center | 340k | 10.5k | 34 | 1.75, 1.6 |
| 2 | `legt4starfall` | Starfall, the Astronomer | `units/Legion/T3/legelrpcmech.lua` | 1.6 / 11 / T4BOT11 | orbital siege, zones / back | 220k | 6.5k | 26 | 2.25, 1.8 |
| 3 | `legt4longinus` | Longinus, the Spear | `units/Legion/T3/legerailtank.lua` | 1.8 / 9 / T4TANK9 | anti-big hunter / center | 300k | 11k | 45 | 1.2, 1.5 |
| 4 | `legt4tempest` | Tempest, the Stormblade | `units/Legion/T3/legeshotgunmech.lua` | 2.0 / 8 / T4BOT8 | melee diver / front | 380k | 12k | 58 | 1.6, 1.6 |
| 5 | `legt4myrmidon` (new) | Myrmidon, the Hive Mother | `units/Legion/T3/legeallterrainmech.lua` | 2.0 / 9 / T4TBOT9 | summoner, support / back | 260k | 6.5k (+drones) | 32 | 1.8, 1.5 |
| 6 | `legt4keres` (new) | Keres, the Death-Spirit | `units/Legion/T3/legkeres.lua` | 2.4 / 9 / T4TANK9 | anti-swarm brawler / front | 480k | 9.5k | 40 | 1.6, 1.6 |
| 7 | `legt4mukade` (new) | Mukade, the Great Centipede | `units/Scavengers/Bots/legpede.lua` | 2.0 / 8 / T4BOT8 | burrowing assassin / front | 360k | 10k | 52 | 1.4, 1.5 |
| 8 | `legt4charybdis` (new) | Charybdis, the Maelstrom | `units/Legion/T3/legehovertank.lua` | 2.4 / 10 / **T4HOVER10** (new) | crowd control, hover / center | 320k | 9k | 60 | 1.8, 1.6 |
| 9 | `legt4apollyon` (new) | Apollyon, the Locust King | `units/Scavengers/Vehicles/legapollyon.lua` | 2.0 / 9 / T4TANK9 | suppression and siege / center | 440k | 10.5k | 30 | 1.5, 1.5 |
| 10 | `legt4medusa` (new) | Medusa, the Gorgon | `units/Legion/Vehicles/T2 Vehicles/legmed.lua` | 3.0 / 9 / T4TANK9 | petrify control artillery / back | 230k | 7.5k | 34 | 2.6, 1.8 |

Role split: front 3 (Tempest, Keres, Mukade), center 4 (Helios, Longinus, Charybdis, Apollyon), back 3 (Starfall, Myrmidon, Medusa).

All 10 base models exist in `objects3d/Units/` (plus `_dead`). The human's two examples are covered:
- **Drone carrier:** Myrmidon.
- **Twin-barrel tank with a rocket launcher:** Apollyon (twin gatling turrets and catapult rocket racks), and Keres as the brawler variant.

Altar `legt4gant` buildoptions: all 10, in the order of the table.

Suggested `xpRate` values:
- Starfall 0.25 (as now).
- Medusa 0.5.
- Myrmidon 0.6. Drone damage counts as hers.

---

## 1. legt4helios — Helios, the Sunbringer (redone)

*A walking star. Its twin heat rays pile Heat into what they touch until the target goes supernova, and every
explosion spreads the fire to the next one.*

**Weapons kept:**
- `heatray1` ×2 (`heatray`)
- `ultraheavyriotcannon` ×2 (`plasma`)
- `legflak_gun` (AA)
- `aimhull` and `bigfootstep`

**a1 Solar Heat** — passive.
- Each `heatray1` hit adds 1 Heat to the target. Limit: once per 0.2 s per target. All Heat decays 4 s after the last stack.
- Each Heat stack: the target takes **+2% → +4%** damage from Helios.
- At 10 Heat the target **Ignites**: **1500 → 6000 + 3% → 8% of its max HP**. Cap 20k → 60k; heroes take half. Radius **200 → 350**.
- Enemies caught in the blast gain **2 → 5 Heat**, so ignitions chain.
- An ignited unit cannot ignite again for 5 s.
- Hooks: `hit` (heat-ray weaponDefID), `frame` (decay).

FX:
- Target with ≥5 Heat: `attach aura` pattern `heat`, radius 0.6× unit radius, EMBER with alpha 0.15 + 0.06 × heat. Detached on decay.
- Ignite:
  - `flash` r 120 → 220, SOLAR, ttl 0.35.
  - `ring shock` r0 40 → r1 = blast radius, EMBER a .9, width 18, ttl 0.5.
  - A `beam` (width 6, EMBER a .8, ttl 0.25) from the blast to each neighbour that receives Heat.

**a2 Corona Flare** — active, self. `cmd 36301`, `hero_coronaflare`, cd **30 → 18**.
- A burst around Helios in radius **600 → 900**.
- Enemies take **4000 → 14000** and gain **+4 → +8 Heat**, so they ignite with a1.
- Allies in the radius heal **3000 → 12000**; heroes heal 50%.

AI: cast when any of these is true:
- ≥4 enemies, or an enemy hero, within 0.8 × radius;
- ≥3 allied units below 70% HP within the radius.

FX:
- `flash` at hero y+60, r 300 → 450, SOLAR, ttl 0.4.
- `ring shock` r0 60 → radius, EMBER a .9, width 40, ttl 0.6.
- `ring rune` (a sun glyph) r1 = radius, SOLAR a .6, ttl 1.2.
- `pillar` r 120, h 900, SOLAR a .6, ttl 0.5.
- Healed allies: `flash` r 60, SOLAR, ttl 0.3.

**a3 Sunspot** — active, map. `cmd 36302`, `hero_sunspot`, range 1400, cd **26 → 16**.
- A miniature sun hovers 220 above the point for **8 → 14 s**.
- Every 0.5 s it lashes **2 → 6** enemies within **450 → 700** for **500 → 1500** each, and adds 1 Heat.
- Each ignition inside its radius extends it by +1 s, up to +6 s.

AI: aim at the centroid of the biggest enemy cluster (≥3 units) in range; prefer clusters that already hold Heat.

FX:
- The sun: point orb (FX need `orbAt`). Fallback: `flash` r 90, SOLAR a .9, ttl 0.6, re-emitted every 0.5 s (pulsing core).
- `ring rune` on the ground at radius, EMBER a .35, ttl = duration.
- Lashes: `beam` sun → target, width 10, core {1,1,.8}, EMBER a .9, ttl 0.25, pulse 4.

**ult Sunstrike** — active, map. `cmd 36303`, `hero_sunstrike`, range 2400, cd **100 → 60**.
- 0.8 s warning, then a column of sunlight burns radius **300 → 450** for 6 s.
- The column creeps at 90 elmo/s toward the enemy with the most Heat; with no Heat, toward the cluster centroid.
- Every 0.2 s: **400 → 1000** to each enemy inside, plus 1 Heat. This sets off ignitions inside the column.
- **Collapse** at the end: every enemy within 900 holding Heat ignites at once, with damage scaled by stacks/10.
- Estimate at r10: 30 ticks × 1000 = 30k per unit, plus ignitions. That is about 250k on an 8-unit group.

AI: cast when either is true:
- ≥6 enemies within 450 of a point in range;
- an enemy hero has ≥3 units near it. Aim at the hero.

FX:
- Warning: `ring rune` r1 = radius, SOLAR a .6, ttl 0.8.
- Column: `pillar` radius = R, h 2400, SOLAR a .75, ttl 0.3. A new pillar every 0.2 s at the new position gives a smooth creep.
- `ring shock` pulses 0.3R → R, EMBER a .7, every 0.6 s.
- Ground `flash` r 0.8R, every 1 s.
- Collapse:
  - `flash` r 900, {1,1,.85,1}, ttl 0.6.
  - `ring shock` r1 900, width 60, ttl 0.9.
  - Each ignition with its own FX.
- `swapWeapons("_corona")` while active: `heatray1_corona` has a white-gold core and thickness ×1.4.

## 2. legt4starfall — Starfall, the Astronomer (redone)

*Astraeus writes on the battlefield with the sky. Its shells leave burning stars that link into constellations.
It bends enemies into its shelling with gravity, and calls the stars down.*

**Weapons kept:**
- `shocker_low` (`artillery`, burst 4, ~7000 range)
- `cluster_munition` (submunition)

**a1 Constellation** — passive.
- The first impact of each salvo places a **Star** for 8 s.
- Up to **3 → 7** Stars; the oldest is dropped first.
- Consecutive Stars closer than **1200 → 2000** are linked.
- Enemies within 40 of a link line take **250 → 900** every 0.5 s (dtype `plasma`).
- Hooks: `hit` (first hit per salvo, keyed by frame), `frame` (segment distance check every 15 frames).

FX:
- New Star: `flash` r 40, STAR, ttl 0.4, plus `ring rune` r 70, STAR a .8, ttl 8 (the star glyph).
- Link: `beam` y+12, width 5, core {.9,.95,1}, STAR a .7, pulse 1.5, ttl 8. It must be cut when a Star is dropped early (FX need: `beam` returns an id for `detach`).
- Victim tick: `flash` r 25, STAR.

**a2 Gravity Lens** — active, map. `cmd 36304`, `hero_gravitylens`, range = weapon range, cd **40 → 24**.
- A gravity well for 6 s, radius **400 → 650**.
- Pulls enemies toward the centre at **50 → 140** elmo/s.
- Starfall's shells landing inside deal **+25% → +60%**.

AI: cast while attacking, when either is true:
- an enemy cluster of ≥5 is in range;
- an enemy hero with ≥2 escorts is in range.

FX:
- Collapsing ripples: `ring rune` r0 R → r1 0.1R, VOID a .7, width 14, ttl 0.75, re-emitted every 0.75 s.
- Dark core: `flash` r 60, VOID, re-emitted every 0.5 s.
- `pillar` r 25, h 600, VOID a .5, ttl 6.

**a3 Deep Sky Eye** — active, map. `cmd 36305`, `hero_skyeye`, range 9000, cd **50 → 28**.
- An orbital eye over radius **1200 → 2400** for **10 → 20 s**.
- The area is revealed to the ally team: LOS, radar and decloak.
- Enemies inside are **Observed**: **+10% → +25%** damage taken from **all** allied sources.

AI targets, in order:
1. the last known position of an enemy hero that is out of LOS;
2. the biggest enemy cluster (≥10) while allies are fighting it.

FX:
- `pillar` r 60, h 3000, STAR a .5, ttl 0.6.
- `ring hex` r0 0.2R → R, ttl 1.
- `ring rune` r1 R, width 10, STAR a .35, ttl = duration.
- Observed units: `attach aura` pattern `runes`, 0.7× unit radius, STAR a .5. Refreshed every 1 s while inside.

**ult Starfall** — active, map. `cmd 36306`, `hero_starfall`, range 9000, radius 750, cd **120 → 80**.
- Over 8 s, **10 → 24** meteors fall. Weapon `legt4starfall_meteor`, fired by `api.fire` from 3000 above; impacts are random in the radius and biased toward units.
- Each meteor deals **2500 → 4000** in 280 and places a Star. The Star cap is +5 while the ult runs.
- A final **Comet** hits the centre for **6000 → 15000** in 600.
- Estimate at r10: about 96k from meteors, plus the comet and the constellation lines. About 200k on a group.

AI: cast when either is true:
- ≥8 enemies within 750 of a point;
- an enemy hero has ≥3 units around it.

Structures count ×0.5 in the score.

FX:
- `ring rune` r1 750, STAR a .6, ttl 1.
- Meteor impact:
  - `flash` r 140, STAR, ttl 0.35.
  - `ring shock` r1 280, STAR a .8, ttl 0.5.
- Comet:
  - `pillar` r 200, h 3000, {.8,.9,1,.9}, ttl 0.5, 0.4 s before impact.
  - `flash` r 600, ttl 0.7.
  - `ring shock` r1 900, width 70, ttl 1.1.

## 3. legt4longinus — Longinus, the Spear (redone)

*The titan hunter. It marks the prey, cracks its armour plate by plate, rail-phases through enemy lines, and
ends the hunt with one spear through everything.*

**Weapons kept:** `t3_rail_accelerator` ×3 (`rail`, `noexplode`, reload 4).

**a1 Sunder** — passive.
- Each rail hit adds a Sunder stack for 6 s; hits refresh it.
- Each stack: **+3% → +6%** damage taken from **all** sources. Up to **5 → 10** stacks.
- Targets of ≥10k metal, and heroes, gain 2 stacks per hit.
- Uses `api.vulnerable` (API need).

FX:
- Sundered unit: `attach aura` pattern `runes`, 1.1× unit radius, RAIL with alpha 0.15 + 0.07 × stacks.
- At max stacks: `flash` r 80, RAIL, ttl 0.25 ("plate cracked").

**a2 Hunter's Mark** — active, unit. `cmd 36307`, `hero_huntmark`, range **2200 → 3000**, cd **24 → 12**.
- Marks an enemy for **8 → 14 s**.
- The target is revealed and decloaked.
- All three rails retarget to it when in range (`api.setTarget`).
- Longinus deals **+20% → +50%** to it.
- If the target dies while marked, the cooldown resets and Longinus heals **4% → 12%** of the victim's max HP (cap 40k).

AI targets, in order:
1. an enemy hero in range;
2. the highest-metal mobile enemy of ≥5000 metal.

FX:
- On the target: `attach aura` `runes`, 1.3× unit radius, RAIL a .7, for the duration.
- At cast:
  - `pillar` r 30, h 800, ttl 0.5.
  - Designator `beam` barrel → target, width 3, RAIL a .5, ttl 0.3.
- On a kill reset: `ring shock` r1 300 at Longinus, plus `flash` r 120.

**a3 Phase Rail** — active, map (dash). `cmd 36308`, `hero_phaserail`, range **600 → 1100**, cd **28 → 14**.
- Longinus rail-phases to the point in 0.4 s. During the dash it takes no damage and passes through units.
- Enemies within 80 of the path take **2500 → 8000** and 1 Sunder stack.
- On arrival all rails reload instantly.

AI:
- **Escape:** HP < 35% and an enemy within 600. Dash at full range away from the enemy centroid.
- **Engage:** the marked target is out of weapon range by less than the dash range. Dash toward it.

FX:
- `beam` start → end, y+40, width 30 → 45, core white, RAIL a .9, pulse, ttl 0.6.
- `attach trail` RAIL during the dash.
- `flash` r 120 at start and end, ttl 0.3.
- For each enemy hit: `bolt` from the path to the enemy, branches 3, ttl 0.2.

**ult Spear of Longinus** — active, unit. `cmd 36309`, `hero_spear`, range **2400 → 4200**, cd **100 → 60**.
- 1.5 s charge; Longinus is immobile.
- Then one rail fires through the target and on along a line of **4000 → 7000**, width 100. It ignores shields and terrain.
- Main target: **15% → 35% of its max HP + 15000 → 40000**. Heroes take half the % part.
- Everything else on the line: **8000 → 20000** and 3 Sunder stacks.
- The line keeps burning for 5 s: **400 → 1200**/s to enemies on it.
- Estimate at r10: 10 units on the line take about 200k, plus the main target.

AI targets, in order:
1. an enemy hero, or a unit of ≥15000 metal;
2. the line with the highest total metal, if it holds ≥6 enemies.

FX:
- Charge:
  - `attach electric` RAIL on Longinus, intensity 0 → 1 over 1.5 s.
  - 3× `ring electric` r0 300 → r1 60, contracting.
- Fire:
  - `beam` full line, width 60, core white, RAIL, ttl 0.5.
  - Glow `beam` width 140, a .35, ttl 0.9.
  - `api.fire("spear")`: visual rail projectile, damage 0.
  - `flash` r 250 at the muzzle and r 300 at the target.
- Wound:
  - `beam` y+8, width 40, RAIL a .5, pulse 4, ttl 5.
  - Every 0.5 s a `chain` of 6 jittered points along the line, ttl 0.2.

## 4. legt4tempest — Tempest, the Stormblade (redone)

*A close-quarters storm. It builds momentum on the run, crashes into the line in a lightning charge, and becomes
the eye of a storm that hurls the enemy's fire back.*

**Weapons kept:**
- `shotgun` (14 pellets)
- `adv_rocket` (burst 12)
- `leg_t2_microflak_mobile` (AA)

**a1 Momentum** — passive.
- Movement above 50% speed builds +25 Momentum per second, up to 100. Standing still loses 50 per second.
- Momentum gives +0.10% → +0.25% speed per point.
- At 100 Momentum the next shotgun blast is a **Breach Shot**:
  - **×1.6 → ×3.0** damage on all pellets;
  - pellets pierce along a 400 line;
  - non-hero targets are knocked back **80 → 200**.
- A Breach Shot consumes the Momentum.
- Hooks: `frame` (velocity), `projectile` and `hit` (shotgun salvo).

FX:
- Momentum ≥50: `attach trail` STORM a .6.
- Momentum 100: `attach electric` STORM, intensity 0.6.
- Breach Shot:
  - `flash` r 140 at the muzzle, ttl 0.25.
  - 5 `bolt`s, 600 long, fanned 30°, STORM a .9, branches 1, ttl 0.2.

**a2 Storm Charge** — active, unit or map. `cmd 36310`, `hero_stormcharge`, range **700 → 1200**, cd **22 → 10**.
- Tempest dashes to the target at 900 elmo/s.
- Enemies within 80 of the path take **1500 → 5000** and are stunned **0.5 → 1.5 s**.
- On arrival, a thunderclap deals **2000 → 8000** in radius **250 → 350**.
- The charge sets Momentum to 100, so the next shot is a Breach Shot.

AI:
- Charge an enemy hero in range if Tempest HP > 40%.
- Otherwise charge a cluster of ≥4 enemies.
- Never charge into ≥3 armed enemy structures.

FX:
- `attach trail` STORM during the dash.
- A `chain` along the path segment every 0.1 s, width 8, branches 2, ttl 0.25.
- Arrival:
  - `flash` r 220, ttl 0.3.
  - `ring electric` r0 50 → r1 = radius, width 30, ttl 0.5.
- `bolt` to each stunned unit, ttl 0.15.

**a3 Storm Echoes** — active, self. `cmd 36311`, `hero_echoes`, cd **50 → 30**.
- Summons **1 → 3** storm images (`legeshotgunmech`, as in v18) for **12 → 24 s**, leash 600.
- Each image has 15% of Tempest's HP and deals **30% → 60%** of its damage.
- When Tempest fires a Breach Shot, every image fires one too.
- Images explode on expiry or death: **1500 → 4000** in 200, plus a 0.5 s stun.

AI: cast in combat when ≥3 enemies or an enemy hero are within 900.

FX:
- Spawn: `pillar` r 60, h 700, STORM a .7, ttl 0.4, plus `ring shock` r1 200.
- Each image, for its lifetime:
  - `attach electric` STORM, intensity 0.8;
  - `attach aura` pattern `electric`, r 90, a .3.
- Explosion: `flash` r 160, plus `ring electric` r1 200, ttl 0.4.

**ult Eye of the Storm** — active, self. `cmd 36312`, `hero_eyestorm`, cd **80 → 55**.
- For **5 → 8 s** Tempest spins; it can still move at 70% speed.
- Enemies within **450 → 650** take **300 → 700** every 0.2 s.
- Its shotgun and rockets fire all around (`api.fire` weapon copies).
- Tempest takes −50% damage and cannot be stunned.
- It **reflects 25% → 60%** of the damage it takes back to the attacker as `electric`; heroes take half.
- It ends with a thunderclap: **5000 → 15000** in 700, and a stun of **1 → 2.5 s**.
- Estimate at r10: 28k per unit; 8 units ≈ 224k, plus the clap.

AI: cast when Tempest HP > 25% and either is true:
- ≥5 enemies within 500;
- an enemy hero is within 500.

FX:
- `attach electric` STORM, intensity 1, ttl = duration.
- `attach aura` pattern `electric`, radius R, a .45.
- Every 0.2 s, 2 `bolt`s to random enemies in R, width 10, branches 2, ttl 0.15.
- `ring electric` at R, refreshed every 0.4 s.
- Reflect: `bolt` Tempest → attacker, FOAM, width 6, ttl 0.15. At most 4 per second per attacker.
- Clap:
  - `flash` r 400, ttl 0.5.
  - `ring shock` r1 700, width 50, ttl 0.7.
  - `pillar` r 150, h 1500, ttl 0.35.
- `swapWeapons("_storm")`: `shotgun_storm` has blue-white tracers.

## 5. legt4myrmidon — Myrmidon, the Hive Mother (new)

*The all-terrain carrier mech walks over cliffs while a hive of heat-ray drones works for her. They hunt, repair
her allies and dive like missiles. At the climax she roots and becomes a living hive.*

**Weapons kept:**
- `plasma_low` and `plasma_high` (`artillery`; an alt pair, `alt = { plasma_high = true }` as on Olympus)
- `smart_trajectory_dummy` (range scaled with the cannons)
- `cluster_munition` (the cannons' submunition)
- `light_antiair_missile`

**Removed:** `drone_controller`, from both the weapons list and the weapondefs.
- The stock `unit_carrier_spawner` has no runtime interface, so its drone count cannot grow with rank.
- Drones come from `api.summon` instead.

**a1 Drone Bay** — passive.
- Keeps **2 → 8** hero drones alive.
- Drone unitdef: `legt4myrmdrone`, a new unitdef from `legheavydronesmall` ×1.5.
  - 5000 HP, +3% per hero level.
  - Heat ray of about 220 DPS × `api.power`.
- Drones are rebuilt one at a time every **12 → 5 s**.
- Leash 1400. Drones attack her target, or the nearest enemy within 1000 of her.
- Their damage and kills count as hers (API need).

FX:
- Launch: `flash` r 50, HIVE, ttl 0.25, at her back, plus `ring shock` r1 120.
- Each drone: `attach trail`, HIVE a .5.

**a2 Repair Swarm** — passive.
- A drone with no enemy within 1000 beam-repairs the most damaged allied unit within 600 of it: **150 → 600** HP/s.
- Heroes get 50% of that; the Mother gets 100%.
- From rank 4, 1 drone stays on repair duty in combat; from rank 8, 2 drones.

FX:
- `beam` drone → ally, width 4, core {.9,1,.9}, HEAL a .8, pulse 6, ttl 0.35, re-emitted every 0.33 s.
- Healed unit: `attach aura` pattern `heal`, 0.8× unit radius, HEAL a .4, ttl 0.5, refreshed.

**a3 Sacrificial Dive** — active, unit. `cmd 36313`, `hero_dive`, range 1800, cd **30 → 16**.
- Up to **2 → 8** drones dive onto the target and detonate: **2500 → 7000** each, in 180; heroes take 70%.
- For the next 10 s drones rebuild 3× faster.

AI: cast when ≥2 drones are alive and either is true:
- an enemy hero, or a unit of ≥4000 metal, is in range;
- a cluster of ≥5 enemies is within 360.

FX:
- Cast: `ring rune` r1 250 at the Mother, HIVE a .6, ttl 0.6 (command glyph).
- Each diver: `attach trail` EMBER a .9 and `attach electric` EMBER.
- Each impact:
  - `flash` r 140, HIVE, ttl 0.3.
  - `ring shock` r1 180, EMBER a .85, ttl 0.4.

**ult Hive Ascendant** — active, self (recast ends it). `cmd 36314`, `hero_hive`, cd **110 → 70**, counted from the end.
- She roots for **14 → 24 s**: immobile, +30% armour.
- Cannons: reload ×0.6, range +25%.
- She hatches swarm-mites: one every **1.0 → 0.5 s**, up to **10 → 30** alive.
  - Mite unitdef: `legt4myrmmite`, from `legdrone` ×1.6.
  - 900 HP, about 120 DPS, expires after 20 s.
- Drone Bay rebuild time ×0.3.
- Estimate at r10: about 70k from mites, plus about 260k from the boosted cannons over 24 s.

AI:
- Cast when ≥8 enemies, or an enemy hero, are within 1800 **and** ≥5 allied units are within 1500.
- Recast (end it) when no enemy has been within 2200 for 4 s.

FX:
- Root: `ring hex` r0 100 → r1 450, HIVE a .8, width 20, ttl 0.8.
- For the duration: `attach aura` pattern `runes`, r 450, EMBER a .35.
- Each hatch: `flash` r 45, HIVE, ttl 0.2.
- Beacon: `pillar` r 25, h 600, HIVE a .4, every 2 s.

## 6. legt4keres — Keres, the Death-Spirit (new)

*The anti-swarm tank of a death goddess. Every death around it feeds it a soul. It hooks the dangerous, devours the
broken, and at the end lets the souls loose to hunt.*

**Weapons kept:**
- `legkeres_cannon` (heavy riot cannon, `cannon`, aoe 200 → 320)
- `legkeres_gatling` ×2 (rotary cannons, `plasma`)

**a1 Soul Harvest** — passive.
- Every enemy that dies within 1000 of Keres, by any killer, gives Souls: 1 per 500 metal of its cost (minimum 1; a hero gives 10).
- Soul cap: **20 → 50**.
- Each Soul: **+0.4% → +0.8%** damage.
- After 10 s out of combat, Souls decay at 1 per 3 s.
- Needs the `unitDied` hook (API need).

FX:
- Orbiting souls: `attach orb` × ceil(souls/10), r 18, height 90, orbit 140, speed 1.2, SOUL a .8, phase-offset.
- Each Soul gained: `bolt` corpse → Keres, width 3, jitter 0.2, SOUL a .7, ttl 0.4 (a wisp).

**a2 Death Grip** — active, unit. `cmd 36315`, `hero_deathgrip`, range **900 → 1400**, cd **20 → 10**.
- A chain hook drags the target to 150 in front of Keres over 0.5 s. Heroes are dragged half way; structures cannot be targeted.
- The target is stunned **1 → 2.5 s**.
- The riot cannon fires point-blank: **3000 → 10000** + 300 splash.

AI: skip targets already within 400. Pick the enemy with the highest score:
- score = metal;
- ×1.5 for units with weapon range >1200;
- ×2 for heroes.

FX:
- Chain: `beam` Keres → target, width 6, core {.8,1,.9}, SOUL a .9, ttl 0.15, re-emitted every 0.1 s while dragging.
- Target: `attach electric` SOUL, intensity 0.7, ttl = stun.
- Shot: `flash` r 160.

**a3 Devour** — active, unit. `cmd 36316`, `hero_devour`, range 400, cd **16 → 7**.
- Target: a non-hero enemy with current HP below **8000 → 30000**, or below **25% → 45%** of its max.
- The target is killed without a wreck, credited to Keres.
- Keres heals **100% → 250%** of the HP the target had left, plus 10% of the target's max HP.
- Keres gains +5 Souls.

AI:
- The highest-metal eligible enemy within 400.
- If Keres HP < 60%, also within 900: move in, then cast.

FX:
- `pillar` radius = victim radius, h 500, SOUL a .7, ttl 0.4.
- Swallow: `ring rune` r0 1.5× victim radius → r1 30, SOUL a .9, ttl 0.5.
- `chain` of 3 points victim → Keres.
- `flash` r 100 on Keres.

**ult Danse Macabre** — active, self. `cmd 36317`, `hero_macabre`, cd **90 → 60**.
- For **8 → 12 s** Keres releases its Souls as up to **10 → 24** hunting spirits.
- Spirits are drawn from stored Souls. If there were fewer Souls than the cap, every death nearby adds a spirit.
- Each spirit strikes an enemy within 1200 once per second for **300 → 800**. Spirits prefer different targets (anti-swarm).
- Keres gains **10% → 30%** lifesteal.
- Estimate at r10: 24 × 12 × 800 ≈ 230k.

AI: cast when either is true:
- ≥8 enemies within 1200 and Souls ≥ 50% of the cap;
- Keres HP < 40% with ≥3 enemies near.

FX:
- Spirits: `attach orb` × count, orbit 200–600, height 120, varied speed, SOUL a .9. Positions come from `orbPos`.
- Strike: `bolt` orbPos → target, width 5, jitter 0.6, branches 0, ttl 0.2.
- `attach aura` pattern `runes`, r 500, SOUL a .3.

## 7. legt4mukade — Mukade, the Great Centipede (new)

*A 300-elmo armoured centipede. It dives underground, erupts under the enemy back line, poisons with its rails,
sheds its shell when wounded, and coils around the biggest prey.*

**Weapons kept:**
- `railgunt2` ×2 (`rail`)
- `adv_rocket` ×2 (`rockets`)
- `armmg_weapon` ×2 (MG)

**Model note:** the collision box is 52×56×288 after scaling; check its turning in a scene.

**a1 Burrow** — active, map. `cmd 36318`, `hero_burrow`, range **1500 → 2600**, cd **30 → 14**.
- Mukade dives in 0.6 s, then travels underground to the point:
  - speed **+40% → +80%**;
  - untargetable, invisible, no collision;
  - cannot fire;
  - at most **4 → 8 s**.
- It erupts at the point: **3000 → 10000** in **300 → 450**, and a stun of **0.8 → 1.6 s**.

AI:
- **Dive** when Mukade HP > 50% and the eruption would hit ≥2 enemies, and either:
  - an enemy with range > 1000 (artillery) is in cast range;
  - an enemy of ≥3000 metal is in cast range.
- **Escape** when HP < 25%: dive at full range toward allies or the altar.

FX:
- Dive:
  - `ring shock` r1 260, AMBER a .9, ttl 0.5.
  - `flash` r 120, ttl 0.2.
- Underground, every 0.3 s: `ring shock` r0 40 → r1 160 at its position, AMBER a .6. This moving mound is a deliberate tell for enemies with LOS.
- Eruption:
  - `pillar` r 120, h 700, AMBER a .8, ttl 0.35.
  - `flash` r 250.
  - `ring shock` r1 = radius, width 40, ttl 0.6.
  - Plus the stock dirt CEG.

**a2 Venom Rails** — passive.
- Rail hits inject Venom for 4 s: **2% → 5%** of the target's **current** HP per second.
  - Minimum 200/s; maximum **1500 → 5000**/s per target.
  - Heroes take half.
  - The strongest application wins and refreshes the timer.
- A unit that dies while venomed bursts into an acid pool for 4 s: radius **150 → 250**, **400 → 1200**/s.

FX:
- Venomed unit: `attach aura` pattern `heat`, 0.7× unit radius, VENOM a .5, ttl 4, refreshed.
- Acid pool: `ring rune` r1 = radius, VENOM a .6, ttl 4, plus `flash` r 80 at birth.

**a3 Molting** — passive. Internal cooldown **90 → 45 s**, shown via `api.cooldown`.
- When HP falls below 50%, Mukade sheds its carapace:
  - it heals **10% → 30%** of max HP over 3 s;
  - armour +25% → +50% for 5 s;
  - the shed segments explode for **2000 → 6000** in 300.

FX:
- 4 `flash`es along the body axis, r 90, SOLAR, ttl 0.3.
- `ring shock` r1 300, AMBER.
- Then `attach aura` pattern `heal`, r 200, ttl 3.
- Hardened shell: `attach sphere` hex, fresnel, 1.0× unit radius, AMBER a .25, ttl 5.

**ult Coil** — active, unit. `cmd 36319`, `hero_coil`, range 700, cd **90 → 60**.
- Targets: units of ≥2000 metal, heroes, and structures.
- Mukade lunges onto the target and coils around it for **4 → 7 s**.
- The target is stunned; heroes for 50% of the time.
- The target takes **3% → 7% of its max HP + 1000 → 3000** per second, and Venom at its maximum.
- Mukade takes −40% damage; its rails and rockets keep firing at other enemies.
- If the target dies during the coil, Mukade heals 15% and the cooldown runs 30% faster.
- Estimate at r10 on a 500k hero: about 266k.

AI targets, in order:
1. an enemy hero within 700; walk in if it is ≤1500 away;
2. the highest-cost mobile enemy of ≥8000 metal.

FX:
- Lunge: `attach trail` AMBER.
- Coil:
  - Mukade is MoveCtrl'd around the target at radius target r + 60, one turn per 2 s (API need).
  - `attach electric` on the target, EMBER, intensity 0.8.
  - `ring hex` at the coil radius, EMBER a .6, width 16, ttl = duration.
  - Every 1 s, a crush `flash` r 100, ttl 0.2.

## 8. legt4charybdis — Charybdis, the Maelstrom (new)

*The heavy hovertank named after the sea monster. It drowns enemies in undertow, throws them skyward with
waterspouts, and opens a whirlpool maw that swallows armies. It is stronger over water.*

**Weapons kept:**
- `heat_ray` (sweepfire, `heatray`, 425 → 765)
- `depthcharge` (torpedo)
- `parabolic_rockets` ×2 (`rockets`)

**Needs** a new `T4HOVER10` movedef: hover, fp 10, `CRUSH.MAXIMUM`.

**a1 Undertow** — passive.
- Each heat-ray hit slows its target by **4% → 8%**. Limit: once per 0.3 s per target.
- Stacks up to **30% → 60%** and lasts 3 s.
- Targets slowed ≥30% take **+15% → +35%** from Charybdis's rockets and depthcharges.
- Over water, stacks build twice as fast.

FX: slowed unit: `attach aura` pattern `runes`, 0.8× unit radius, TIDE with alpha 0.2 + 0.5 × slow. A `swirl` pattern would be better (FX need).

**a2 Waterspout** — active, map. `cmd 36320`, `hero_waterspout`, range 1400, cd **22 → 12**.
- 0.5 s after the cast a spout erupts in radius **250 → 380**; ×1.3 over water.
- Enemies are tossed up (stun **1 → 2 s**) and take **3000 → 9000**.
- A mist stays for 5 s. Enemies inside it get maximum Undertow.

AI: cast on a cluster of ≥3 enemies, or on an enemy hero.

FX:
- Warning: `ring shock` r0 R → r1 0.2R, TIDE a .6, ttl 0.5 (water sucked in).
- Eruption:
  - Outer `pillar`: r 0.6R, h 1200, TIDE a .75, ttl 0.6.
  - Inner core `pillar`: r 0.3R, h 1400, FOAM a .9, ttl 0.4.
  - `flash` r R, ttl 0.35.
  - `ring shock` r1 1.2R, width 30, ttl 0.6.
- Mist: `ring rune` at R, FOAM a .25, ttl 5.

**a3 Surge** — active, map (dash). `cmd 36321`, `hero_surge`, range **500 → 900** (×1.5 over water), cd **16 → 8** (halved over water).
- Charybdis rides a wave to the point in 0.5 s.
- Enemies within 120 of the path are knocked 150 aside, take **1500 → 6000**, and get maximum Undertow.
- The wake slows by 40% for 4 s.

AI:
- **Engage** when ≥3 enemies lie on the path to the current target.
- **Escape** when HP < 30%: away from the enemy centroid.

FX:
- `attach trail` TIDE a .8.
- Wake: `beam` y+5, start → end, width 120, TIDE a .35, pulse 3, ttl 4.
- Arrival: `flash` r 160, FOAM, plus `ring shock` r1 250, ttl 0.4.

**ult Maw of the Deep** — active, map. `cmd 36322`, `hero_maw`, range 1600, cd **110 → 75**.
- A maelstrom of radius **700 → 1000** for 7 s.
- It pulls enemies to the centre at **120 → 260** elmo/s. Heroes are pulled half as hard; structures are immune.
- Damage:
  - outer ring: **200 → 500**/s;
  - core (r 160): **1500 → 4000**/s.
- Non-hero units in the core with HP below **6000 → 25000** are swallowed: killed without a wreck, credited to Charybdis.
- It ends with a tidal blast of **3000 → 10000** across R that throws survivors outward.
- Over water: radius +20%, pull +30%.
- Estimate at r10: about 25k per unit, plus swallows; about 250k on a 10-unit group.

AI: cast when either is true:
- ≥8 mobile enemies within 700 of a point;
- an enemy hero with 4 more enemies around it.

FX:
- Inward waves: `ring shock` r0 R → r1 0.15R, TIDE a .7, width 30, ttl 0.5, every 0.5 s.
- `ring rune` at R, a .4, ttl 7.
- Abyss: `pillar` r 160, h 300, {.05,.15,.4,.9}, ttl 7.
- Spray: `pillar` r 90, h 900, FOAM a .6.
- Swallow: `flash` r 80 on the victim, plus `bolt` victim → centre, ttl 0.2.
- End:
  - `ring shock` r0 0.1R → r1 1.3R, width 80, FOAM a .9, ttl 0.8.
  - `flash` r R, ttl 0.5.
- A real spiral needs a ring `swirl` kind (FX need).

## 9. legt4apollyon — Apollyon, the Locust King (new)

*The scavenger weapons platform, with twin-barrel gatling turrets and catapult rocket racks. The longer it fires,
the hotter it burns. It can anchor itself as a fortress and loose a plague of locust rockets.*

**Weapons kept:**
- `legapollyon_gatling_big` ×4 (`plasma`)
- `legapollyon_gatling_small` ×2
- `legapollyon_gatling_aa` ×2 (AA)
- `legapollyon_missile` ×2 (`rockets`, 1200 → 1800)

**a1 Spin-Up** — passive.
- Continuous gatling fire adds **+3% → +5%** fire rate per second, up to **+30% → +80%**.
- After 2 s without firing, the spin drops by 15% per second.
- At full spin the gatlings fire incendiary rounds (`swapWeapons("_hot")`):
  - **+20% → +40%** damage;
  - burn **300 → 800**/s for 3 s.

FX:
- `attach aura` pattern `heat`, r 120, EMBER with alpha 0.1 → 0.5 by spin.
- Full spin: `attach electric` EMBER, intensity 0.4 (red-hot barrels).
- `_hot` copies have orange-red, thicker tracers.

**a2 Locust Swarm** — active, map. `cmd 36323`, `hero_locusts`, range **1800 → 2400**, cd **22 → 12**.
- **12 → 36** micro-rockets (`legt4apollyon_locust`) launch in 3 waves over 2 s.
- Each homes on a different enemy within 500 of the point: **600 → 1200** in 120.
- Rockets with no target burn the ground for 3 s: 300/s in r 100.
- Estimate at r10: 43k.

AI: cast on a cluster of ≥4 enemies within 500 of a point.

FX:
- Rockets are real, with a small scaled trail CEG.
- `flash` r 60 on the racks for each wave.
- Target designator: `ring hex` r1 500, EMBER a .5, ttl 2.5.
- Burning ground: `ring rune` r 100, EMBER a .5, ttl 3.

**a3 Siege Lockdown** — active, self (recast ends it). `cmd 36324`, `hero_lockdown`, cd **30 → 18**, counted from the end.
- Apollyon anchors for up to **8 → 15 s**: immobile, armour **+25% → +50%**.
- Gatling range **+30% → +60%**.
- Rocket reload ×0.5.
- Spin starts at 50%.

AI:
- Cast when ≥6 enemies are within 1.3× gatling range and no enemy hero is within 400.
- Recast (end it) when every enemy has left 1.6× range, or when HP < 25%.

FX:
- `ring hex` r0 60 → r1 260, EMBER a .9, width 24, ttl 0.6.
- Armour field: `attach sphere` hex, fresnel, 1.2× unit radius, EMBER a .25. Hits ripple it through `opts.hit`.
- Anchors: 4 `pillar`s at the outriggers, r 18, h 120, EMBER a .6, ttl = duration.

**ult Plague of Locusts** — active, map. `cmd 36325`, `hero_plague`, range 3000, cd **120 → 80**.
- Apollyon locks in place and channels for 10 s.
- **60 → 120** locusts rain on a 700 radius, biased toward units: **900 → 1800** each, in 150.
- Each impact leaves fire for 2 s: **200 → 500**/s in r 120.
- The gatlings stay at full spin during the channel.
- Estimate at r10: about 216k, plus fire.

AI: skip if an enemy hero is within 600 of Apollyon. Otherwise cast when either is true:
- ≥10 enemies within 700 of a point;
- ≥5 enemy structures there (base siege).

FX:
- `ring rune` r1 700, EMBER a .5, ttl 10.
- `ring shock` pulse every 1 s.
- `flash` r 50 on the racks every 0.25 s.
- Each impact: `flash` r 70, EMBER, ttl 0.25.

## 10. legt4medusa — Medusa, the Gorgon (new)

*A rocket tank whose hexaburst missiles are serpents. Their bites turn flesh to stone. Her gaze petrifies a whole
front, and the statues shatter.*

**Weapons kept:**
- `legmed_missile` (StarburstLauncher, burst 6, `missiles`, 1000 → 2600)
  - It gets no step copies, as with every starburst.
  - Check `flighttime 5` / `weapontimer` at 2600 range.
- `laser` (targeting dummy, damage 0)

**a1 Serpent Bite** — passive.
- Each missile hit adds a Petrify stack for 6 s; hits refresh it.
- Each stack slows by **6% → 10%**.
- At 5 stacks the target turns to **stone**:
  - stunned **1.5 → 3 s**; heroes 50%, at most once per 8 s;
  - takes **+20% → +40%** damage while stone.
- Afterwards it is immune to Petrify for 6 s.

FX:
- Stacked unit: `attach aura` `runes`, 0.7× unit radius, GORGON with alpha 0.1 × stacks.
- Stone unit:
  - `attach electric` STONE, intensity 0.3;
  - a grey tint (FX need `tint`).

**a2 Gorgon's Gaze** — active, map (direction). `cmd 36326`, `hero_gaze`, range **1400 → 2000**, cd **28 → 16**.
- A 1.5 s gaze sweeps a cone of **40° → 60°**.
- Every enemy in the cone gains **+3 → +5** Petrify stacks.
- Enemies that are already stone **shatter**:
  - **8% → 20%** of their max HP; heroes 4% → 10%; non-heroes capped at 40k;
  - plus **1000 → 3000** to anything within 150.

AI: cast when the cone holds either:
- ≥3 enemies, with stone units counted ×2;
- an enemy hero plus 1 more enemy.

FX:
- Fan: **7 → 9** `beam`s from the head (y+60), length = range, width 14, core {.85,1,.9}, GORGON a .6, pulse 3. They are emitted across the cone one after another over 1.5 s, ttl 0.6 each, to read as a sweep.
- `ring rune` r 120 at the head.
- Shatter:
  - `flash` r 120, STONE, ttl 0.25;
  - `ring shock` r1 150, STONE;
  - 3 short fragment `bolt`s.
- A `cone` primitive would be nicer (FX need, optional).

**a3 Snake Pit** — active, map. `cmd 36327`, `hero_snakepit`, range 2600, cd **26 → 15**.
- A nest of **6 → 12** serpents circles a point at radius **350 → 450** for **6 → 9 s**.
- Each serpent bites an enemy that enters its area, at most once per second: **800 → 2000** and +1 Petrify stack.

AI:
- Cast on a cluster of ≥3 enemies.
- **Defensive:** cast between Medusa and an enemy group within 1200 that is closing in.

FX:
- Serpents: point-anchored orbiters (FX need `orbit`), 4 → 8 elements, GORGON, r 14, height 60.
- Bite: `bolt` serpent → victim, width 4, jitter 0.2, GORGON, ttl 0.15.
- `ring rune` at the radius, GORGON a .4, ttl = duration.

**ult Stone Garden** — active, map. `cmd 36328`, `hero_stonegarden`, range 2600, cd **110 → 75**.
- 1.5 s warning.
- Then everything in radius **600 → 900** turns to stone for **3 → 6 s**: heroes 50%; structures too, which stops their weapons.
- Stone units take **+30% → +60%** damage.
- When the stone ends, every statue shatters:
  - **4% → 10%** of its max HP; heroes 3% → 6%; non-heroes capped at 40k;
  - plus **2000 → 6000** to everything within 200, so shatters chain.
- Estimate: about 150–250k on a group, more with allied fire during the stone.

AI: cast when the radius holds either:
- ≥6 enemies;
- an enemy hero with 3 more units.

Prefer casting when allies are near, so they benefit from the damage bonus.

FX:
- Warning:
  - `ring rune` r1 R, GORGON a .8, width 20, ttl 1.5;
  - contracting `ring shock` R → 0.1R, a .5.
- `pillar` r 100, h 1500, GORGON a .6, ttl 0.4.
- Petrify wave:
  - `flash` r R, STONE a .9, ttl 0.4;
  - `ring shock` r0 0 → R, width 50, STONE, ttl 0.6.
- Statues: tint (FX need) plus a grey `attach electric`.
- Shatter: `flash` r 100, plus `ring shock` r1 200 per statue.

---

## API needs (not in SPEC §4)

1. **`api.pull(uid, x, z, speed, seconds)` and `api.knock(uid, dx, dz, dist)`.**
   - Displacement of mobile enemies. Heroes ×0.5; structures immune.
   - Built on `AddUnitImpulse`, or `MoveCtrl` for a short glide.
   - Users: Gravity Lens, Death Grip, Breach Shot, Surge, Maw.
2. **`api.dash(unitID, h, x, z, { speed, intangible, onPath(uid), onArrive })`.**
   - A MoveCtrl dash with a terrain and pathability check.
   - Users: Phase Rail, Storm Charge, Surge, Coil lunge.
   - `api.orbitAround(unitID, targetID, radius, period, seconds)` for Coil.
3. **`api.vulnerable(uid, id, seconds, frac, opts{maxStacks})`.**
   - A damage-taken multiplier applied in core `UnitPreDamaged` for **every** attacker.
   - Users: Sunder, Deep Sky Eye, Stone, Observed.
4. **`api.slow(uid, id, seconds, frac)`.**
   - For non-hero units too (`SetGroundMoveTypeData maxSpeed`, restored afterwards). The v17 `aura_slow` already does this; expose it.
   - Users: Undertow, Petrify stacks, Surge wake.
5. **`api.reveal(allyTeam, x, z, r, seconds)` and `api.revealUnit(uid, allyTeam, seconds)`.**
   - LOS, radar and decloak.
   - Users: Deep Sky Eye, Hunter's Mark.
6. **`api.untargetable(unitID, seconds)` and `api.hide(unitID, bool)`.**
   - Neutral, no blocking, no collision, cloak, hidden model, weapons held.
   - User: Burrow.
7. **`api.devour(victimID, h, opts{noWreck=true})`.**
   - Kill without a wreck, credited to the hero (XP, kill, item drop rules).
   - Users: Devour, Maw.
8. **New hook `unitDied(api, unitID, h, victimID, victimDefID, attackerID, x, y, z)`.**
   - For enemy deaths within 1500 of the hero, or by the hero.
   - Users: Soul Harvest, Danse Macabre, Hunter's Mark reset, Venom acid pool.
9. **`api.setTarget(unitID, targetID, seconds)`.**
   - Forces the weapons onto the target (`SetUnitTarget`) while it is in range.
   - User: Hunter's Mark.
10. **`api.summon` options and attribution.**
    - Options: `guard = unitID` (attack the hero's target, else nearest within N), `noWreck`, `hpMult`, `dmgMult` (`api.power`), `noXPValue`.
    - The damage and kills of summons must count as the hero's: XP, item damage-type bonuses, kill credit.
    - Users: Myrmidon drones and mites, Tempest echoes.
11. **Buff mods `ccImmune` (no stun) and `reflect` (fraction).**
    - Or leave reflect to the module `damaged` hook; it needs the attacker position.
    - User: Eye of the Storm.
12. **Toggle actives: `toggle = true` in the def.**
    - A second cast calls `cast` again so the module can end the effect; the cooldown starts at the end (`api.cooldown`).
    - Users: Hive Ascendant, Siege Lockdown.
13. **FX additions:**
    - `GG.HeroFX.orbAt(x, y, z, opts)` and `GG.HeroFX.orbit(x, y, z, { count, radius, height, speed, color, ttl })`.
      - Point-anchored orbs and orbiters.
      - Positions must be a pure function, like `orbPos`, so synced code can aim bites from them.
      - Users: Sunspot, Snake Pit.
    - `beam`, `ring` and `pillar` should return an id that `detach` can cut early. User: Constellation links.
    - `ring kind = "swirl"` (spiral) and `attach aura pattern = "swirl"`. Users: Undertow, Maw.
    - `attach(unitID, "tint", { color, ttl })`: a model colour or desaturation overlay. User: stone in Medusa.
    - `cone(x, z, dirX, dirZ, len, angle, opts)`: optional, for Gorgon's Gaze.
14. **`gamedata/movedefs.lua`: new `T4HOVER10`.**
    - Hover, footprint 10, `CRUSH.MAXIMUM`, `maxslope MODERATE`.
    - Nobody in SPEC §7 owns this file; core should add it.

## New unitdefs and weapondefs (content-leg, wave 2)

**Weapondefs.** Extra weapondefs go through the `T4.hero(ud, fx, extra)` third argument, as `<hero>_<key>`.

| Hero | Key | Made with | Purpose |
|---|---|---|---|
| Starfall | `meteor` | `T4.shellWeapon` from `shocker_low` (aoe 280) | ult meteors |
| Starfall | `comet` | same, aoe 600, size ×2.5 | ult finale |
| Longinus | `spear` | `T4.weaponFrom(t3_rail_accelerator, { damage = 0, thickness ×4, laserflaresize ×3 })` | visual only; line damage goes through `api` |
| Keres | `grip` | `T4.weaponFrom(legkeres_cannon, { damage = 0 })` | visual point-blank shot (damage through `api`); optional |
| Apollyon | `locust` | `T4.missileWeapon` (`legsmallrocket.s3o`, homing, aoe 120–150, trail `missiletrailsmall` scaled) | a2 and ult |
| Medusa | `serpent` | `T4.missileWeapon` (`leghomingmissile.s3o`, homing) | Snake Pit launch flourish (optional) |

`T4.missileWeapon` is used instead of starburst for the Apollyon and Medusa missiles: a spawned starburst never turns to its target.

**Swapped weapon copies** (made in the unitdef as `<key>_<suffix>`):
- `heatray1_corona` (Helios ult)
- `shotgun_storm` (Tempest ult)
- `legapollyon_gatling_big_hot` and `legapollyon_gatling_small_hot` (Apollyon full spin)

**New unitdefs:**
- `legt4myrmdrone`: `legheavydronesmall` model ×1.5.
  - 5000 HP, heat ray about 220 DPS, speed 220.
  - Metal 0; no wreck; not buildable.
- `legt4myrmmite`: `legdrone` model ×1.6.
  - 900 HP, MG about 120 DPS.
  - Expires in 20 s; no wreck.
- Tempest echoes keep the stock `legeshotgunmech`, as in v18.

These need scaled s3o models in `objects3d/Units/T4/` like the heroes: `legt4myrmidon`, `legt4keres`, `legt4mukade`, `legt4charybdis`, `legt4apollyon` and `legt4medusa`, each with `_dead`. Add `legt4myrmdrone` and `legt4myrmmite` if they are scaled rather than reused.

**Unit file changes:**
- `units/Legion/T4/legt4units.lua`: 6 new `T4.derive` and `T4.hero` blocks, plus the `legt4gant` buildoptions list.
- Myrmidon: remove `drone_controller`.
- Medusa: check the StarburstLauncher `flighttime` and `weapontimer` at range 2600.
- `T4.heroBalance`: 6 new rows from the summary table. Helios DPS changes 11k → 10.5k.
