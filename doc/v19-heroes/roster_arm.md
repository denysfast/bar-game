# v19 heroes: the Armada roster (design-arm, wave 1)

> **Orchestrator decisions (binding over the text below):** Thor Electro-Devour has NO heal cap — heals 50%→200%
> of the eaten unit's max HP as the human said. Razor's ult drones are REAL summon units (respawning, like the
> Legion drone carrier), not FX-only orbs. Razor's shield is a Lua absorb pool (as designed).


Ten Armada heroes for the altar `armt4gant`: the 4 existing unitnames are redone (to keep saves) and 6 are new.
All of them are ground, amphibious or all-terrain units. Each hero has a different base model, all of them Armada.
Conventions used below:
- `r1→r10` means `H.lin(r1, r10)`. Counts are rounded to the nearest integer.
- Damage, heal and absorb numbers are level-1 values. Each is multiplied by `api.power(h)`.
- "Ability cd" is in seconds.
- Normal ranks unlock at levels 1, 3, 6 … 27. Ult ranks unlock at levels 10, 20 … 100.
- `cmd` ids: Armada uses the block 36101–36199. Hero i (0–9, in table order) uses `36101 + 4*i + slot`, with slot 0..3 = a1/a2/a3/ult. Only actives get a cmd.
- Damage types for items: abilities use the dtype of the weapon they come from (named per ability).

## Summary

| # | unitname | title | base file (unit) | scale | movement | aiRole | HP L1 | DPS L1 | speed | range x | P/A |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `armt4zeus` (keep) | Thor, the Stormbreaker | `units/ArmGantry/armthor.lua` | 1.8 | T4TANK9 | front (anti-medium/swarm) | 420k | 9.5k | 38 | 1.8 | 1/3 |
| 2 | `armt4atlas` (keep) | Atlas, the Bulwark (Bantha) | `units/ArmGantry/armbanth.lua` | 2.0 | T4BOT8 | front (anchor, anti-big) | 480k | 10k | 34 | 1.8 | 1/3 |
| 3 | `armt4peewee` (new) | Peewee Prime, the Vanguard of the Swarm | `units/Scavengers/Bots/armpwt4.lua` | 1.8 | T4BOT8 | front (brawler, anti-swarm, army leader) | 360k | 12k | 58 | 1.8 | 1/3 |
| 4 | `armt4aegis` (keep) | Razor, the Phantom | `units/ArmGantry/armraz.lua` | 2.0 | T4BOT8 | center (assassin/ganker) | 260k (+shield) | 10k | 72 | 1.6 | 2/2 |
| 5 | `armt4prowler` (new) | Prowler, the Riptide | `units/ArmGantry/armprowl.lua` | 2.6 | **T4ATANK8 (new)** | center (amphibious hunter, anti-big) | 330k | 11k | 52 | 1.9 | 1/3 |
| 6 | `armt4ratte` (new) | Ratte, the Landship | `units/Scavengers/Vehicles/armrattet4.lua` | 1.5 | T4TANK9 | center (siege, anti-structure/clump) | 500k | 9k | 24 | 1.3 | 2/2 |
| 7 | `armt4recluse` (new) | Recluse Matriarch | `units/Scavengers/Bots/armsptkt4.lua` | 1.6 | T4TBOT9 | center (zone control, anti-swarm, cliffs) | 300k | 9k | 40 | 1.8 | 1/3 |
| 8 | `armt4olympus` (keep) | Olympus, the Thunderer (Vanguard) | `units/ArmGantry/armvang.lua` | 2.2 | T4TBOT9 | back (artillery) | 220k | 8k | 30 | 2.3 | 1/3 |
| 9 | `armt4starlight` (new) | Starlight, the Lance | `units/ArmVehicles/T2/armmanni.lua` | 2.4 | T4TANK9 | back (sniper, anti-big) | 240k | 8.5k | 40 | 2.2 | 1/3 |
| 10 | `armt4hive` (new) | Hive Mother | `units/Scavengers/Vehicles/armdronecarryland.lua` | 1.5 | T4TANK9 | back (summoner/support) | 280k | 3k own + drones | 34 | 1.0 | 1/3 |

Role spread: 3 front, 4 center, 3 back.
- Hit types: chain/AoE (Thor, Peewee, Recluse), single big target (Atlas, Prowler, Starlight), siege (Ratte, Olympus), summons (Hive), assassin (Razor).
- Accent colours, so heroes are told apart in a fight: Thor cyan (red in Rage), Atlas white-gold, Peewee electric blue, Razor crimson, Prowler teal + orange, Ratte orange-white, Recluse pale green, Olympus ice blue, Starlight violet-white, Hive amber.
- `T4.heroBalance` entries are as in the table. Hive: `dps = 3000` covers only its own point-defence laser. The drones' DPS is set by a1, see there.
- `buildoptions` of `armt4gant` lists all 10. The hero cap of 3 is done by the core gadget.

---

## 1. armt4zeus: Thor, the Stormbreaker (armthor x1.8): human concept, binding
Thor is a slow, heavily armoured electric tank. It is the best hero against packs of medium units, and weak against a single big target, because its chains need neighbours.
Its Rage Mode turns it into a red storm.
**Weapons kept:**
- `thunder`: Thunder Coil, LightningCannon, burst 10. The only DPS weapon.
- `emp`: EMP beams, a paralyser with short range.
- `empmissile` is taken out of the auto-firing weapon list, and a2 fires it.

**a1 Chain Lightning (passive).** Every Thunder Coil bolt that hits jumps on to the nearest enemy not hit yet.
- Jump k deals `bolt dmg × f × 1.05^(k-1)`. Each next target takes +5%. Heroes count as targets.
- Numbers: jumps `1→10`, jumpRange `300→750`, f `0.30→0.18`. Total extra damage on a big pack: x0.30 of the bolt at r1, x2.26 at r10. Nothing extra against a lone target.
- Orb bolts in Rage also chain. dtype electric.
- FX: `chain(points, {color={0.55,0.85,1,1}, width=6→10, branches=2, jitter=0.35, ttl=0.25})`, plus a `flash` at each hop (radius 40, the same colour, ttl 0.15). In Rage the colour is `{1,0.25,0.15,1}`.

**a2 EMP Missile (active, map/unit, range `1300→1800`, cd `28→16`).** Fires one heavy EMP missile at the point.
- On impact, every enemy in radius `300→520` takes `3000→10000` damage and is stunned `3→8` s. Heroes are stunned too, at 50% (core rule). dtype emp.
- AI: cast at the cost-weighted centre of ≥6 enemies (summed cost ≥8000) in range, or at an enemy hero.
- FX: the missile's own CEG trail. On impact:
  - `ring{kind="electric", r0=40, r1=R, color={0.45,0.75,1,0.9}, width=28, ttl=0.7}`
  - `ring{kind="shock", r1=1.3R, ttl=0.4}`
  - `flash{radius=0.7R, color={0.7,0.9,1,1}, ttl=0.35}`
  - `attach(victim,"electric",{color=cyan, intensity=0.6, ttl=stun})` on up to 16 stunned units, most expensive first.
- Weapondef: `hero_empmissile` is a **MissileLauncher** copy of `empmissile` (high `trajectoryheight`, tracks). It must not be a starburst: SpawnProjectile of a starburst is the v15.1 savegame crash.

**a3 Electro-Devour (active, ally, range `450→800`, cd `30→14`).** Strikes one of Thor's own non-hero, non-commander mobile units and eats it.
- The unit is pulled in by lightning for 0.4 s. Then it is destroyed with no wreck and no death explosion.
- Thor heals `0.5→2.0` × that unit's max HP. One devour heals at most 30% of Thor's max HP (balance knob).
- **Overflow** (heal beyond full HP) becomes Static Overcharge: +1% Thunder Coil damage per 1% of max HP that overflowed, up to +30%, for 12 s.
- AI: cast when HP < 50%, or HP < 70% while fighting an enemy hero, and an eligible ally is in range whose heal is ≥ 8% of max HP. It picks the cheapest unit that covers the missing HP.
- FX:
  - 3 bolts from the eaten unit to Thor over 0.4 s (`{0.6,0.9,1,1}`, width 16, branches 5, ttl 0.45, a new seed each time).
  - `attach(eaten,"electric")` for 0.4 s, then a `flash` at the unit (radius 2× its size).
  - On Thor: `pillar{radius=70, height=500, color={0.4,1,0.8,0.8}, ttl=0.8}` and `attach aura pattern="heal"` with ttl 1.2.
  - While Overcharge lasts: `attach "electric"` in cyan, intensity 0.4.

**ult Rage Mode (active, self, cd `140→80`, duration `10→20`).**
- Over 0.6 s the tank grows to scale 1.35 (`setScale`). Speed +`25%→60%`, turn rate of hull **and turret** +`50%→150%`, damage taken −`10%→25%`.
- `swapWeapons("red")`: `thunder_red` and `emp_red`.
- A red electric orb darts above the tank. Once per Thunder Coil reload it fires `hero_orbbolt` at Thor's target if that is within 2× range; otherwise at the most expensive enemy within 2× range.
  - `hero_orbbolt` is a LightningCannon with the same damage as the Coil and **2× its current range**.
- AI: cast when ≥10 enemies or ≥25k enemy cost are within 1.5× range, or an enemy hero is in range, or HP < 35% with enemies in range.
- FX:
  - On cast: `flash{radius=220, red}` and `ring{kind="shock", r1=600, color={1,0.2,0.1,0.9}, ttl=0.6}`.
  - For the duration: `attach "electric" {color={1,0.2,0.1,1}, intensity=1.0}`, `attach "aura" {pattern="electric", radius=180, red}`, `attach "orb" {color=red, radius=26, height=150, orbit=70, speed=1.5}` and `attach "trail"`.
  - The orb's bolts start at `orbPos`: `bolt{color={1,0.25,0.15,1}, width=10, branches=3}`.
  - At the end the scale shrinks back over 0.6 s, with a small red flash.

## 2. armt4atlas: Atlas, the Bulwark (Bantha x2.0)
Atlas is the anchor of an assault. It taunts the enemy army onto its plating and reflects the damage back. The Doom Laser marks big targets for the whole team.
Its ultimate sweeps the battlefield with a doom beam.
**Weapons kept:**
- `armbantha_fire`: Pulse Cannon.
- `tehlazerofdewm`: Doom Laser.
- `bantha_rocket`: Starburst Rockets. Never copied or spawned.
- `banthfootstep`: 0 damage. Re-used as the step sound/CEG.

**a1 Doom Lens (passive).** Every Doom Laser hit **Sunders** its target for 6 s. A sundered target takes +`6%→18%` damage from every allied source.
- Against targets that cost ≥5000, the Doom Laser deals +`20%→80%`.
- FX:
  - Doom shots get an extra `beam` overlay (`{1,0.95,0.75,1}`, width 14, core 0.6, ttl 0.15).
  - Sundered target: `attach "aura" {pattern="runes", color={1,0.55,0.2,0.6}, radius=1.2×unit radius, ttl=6}`.
  - `ring{kind="rune", ttl=0.5}` when the mark is applied.

**a2 Bulwark Protocol (active, self, cd `40→22`).**
- Atlas plants its feet for `5→10` s: immobile, damage taken −`30%→55%`.
- It **taunts**: every enemy within `500→900` is ordered to attack Atlas for the duration. Heroes are taunted for only 1.5 s.
- `10%→30%` of the damage Atlas takes (before the reduction) goes back to the attacker as an electric bolt. dtype electric.
- AI: cast when ≥6 enemies are within 900 and attacking allies, or when an enemy hero is within 900 and HP > 50%.
- FX:
  - `ring{kind="hex", r0=0, r1=radius, color={0.4,0.7,1,0.8}, ttl=0.5}` and `ring{kind="rune", r1=radius, color=orange, ttl=0.8}`, the taunt pulse.
  - `attach "sphere" {radius=200, color={0.6,0.8,1,0.35}, hex=true, fresnel=1}` for the duration. Every reflected hit calls `HeroFX.hit` at the hit point plus `bolt(hit→attacker, {0.5,0.8,1,1}, width 5, ttl 0.2)`.

**a3 Seismic Charge (active, map, range `600→1000`, cd `25→12`).** Atlas charges in a straight line to the point.
- Every 0.35 s a footstep shockwave hits radius 220: `2000→6000` damage and 50% slow for 3 s.
- The landing hits radius 400: `6000→18000` damage and a `1→2.5` s stun. dtype plasma.
- AI: cast when an enemy cluster (≥5) or an enemy hero is 500–1000 away and HP > 50%. It is never used to retreat.
- FX:
  - `attach "trail"` in white-gold for the dash.
  - Each step: `ring{kind="shock", r1=240, color={1,0.75,0.4,0.8}, ttl=0.4}`.
  - Landing: `flash{radius=260}`, `ring{kind="shock", r1=450, ttl=0.5}` and `ring{kind="rune", r1=400, gold, ttl=0.8}`.

**ult Doomsday Lance (active, map, cd `150→90`).** Atlas becomes immobile and charges for 0.8 s. Then the Doom Laser fires as a continuous beam `2×` its range long. It sweeps a 60° arc centred on the target over `4→8` s.
- Every enemy inside the beam (width 90) takes `12000→30000` damage per second.
- Units the beam kills burst for 10% of their max HP in radius 200.
- About 200k against a group at r10. dtype laser.
- AI: aim at the 60° cone, within 2× range, with the most enemy cost; cast only if that is ≥12 units or ≥40k cost.
- FX:
  - Charge: `attach "orb"` (white-gold, radius growing 10→40, height at the laser eye).
  - The beam: `beam{color={1,0.95,0.7,1}, width=40, core=0.5, pulse=8, ttl=0.1}`, re-emitted every 3 frames.
  - At the beam's end: `flash{radius=100, ttl=0.15}`.
  - Kill bursts: `flash` in orange with `ring{kind="shock", r1=200}`.

## 3. armt4peewee: Peewee Prime, the Vanguard of the Swarm (armpwt4 x1.8)
The smallest Armada bot, grown into a titan. Peewee Prime is a fast, reckless brawler that is stronger with an army around it. It sprays plasma into packs and leads the charge.
**Weapons kept:** `emg`, rapid plasma guns, range ~810.

**a1 Pack Leader (passive).**
- For each allied mobile unit within 700 (counting at most `10→30`), Peewee gains +1% damage and +0.5% damage reduction. The reduction is capped at 15%.
- Allied T1/T2 bots within 700 get +`5%→20%` speed and damage.
- FX: `attach "aura" {pattern="runes", color={0.4,0.7,1,0.25}, radius=700}`, permanent and faint. It pulses brighter when the count is at its cap.

**a2 Jump Jets (active, map, range `500→900`, cd `20→9`).** Peewee leaps along a ballistic arc (about 1 s).
- Landing: `4000→14000` damage in radius 300, and units are knocked back outward.
- Then **Hot Barrels**: +`20%→50%` EMG damage for 4 s. dtype plasma.
- AI: leap into a cluster of ≥6 enemies 400–900 away when HP > 50%. When HP < 25%, leap 800 toward the altar to escape.
- FX:
  - Take-off: `flash{radius=120, blue}` and `ring{kind="shock", r1=200}`.
  - In flight: `attach "trail"` in blue.
  - Landing: `ring{kind="shock", r0=0, r1=330, color={0.5,0.8,1,0.9}, ttl=0.45}` and `flash{radius=200}`.
  - Hot Barrels: `swapWeapons("hot")` (`emg_hot`: bigger, white-blue plasma) and `attach "electric"` in blue, intensity 0.4, for 4 s.

**a3 Bullet Hell (active, self, cd `30→16`, channel `3→6` s).** Peewee spins its torso and sprays every direction at 50% move speed.
- Every enemy within weapon range takes `1000→2400` damage per second, at most 15 targets.
- About 120k against 8 units at r10. dtype plasma.
- AI: cast when ≥6 enemies are within weapon range.
- FX:
  - Every 0.2 s, up to 15 tracer streaks: `beam(hero→target, {0.45,0.75,1,1}, width=5, core=0.8, ttl=0.08)`.
  - `ring{kind="shock", r1=160, ttl=0.3}` every 0.5 s.
  - `attach "aura" {pattern="heat", color=blue, radius=150}` while channelling.

**ult Overrun (active, self, cd `150→90`, duration `8→16`).** Affects Peewee and every allied mobile unit within 900 at the moment of the cast.
- They get +`25%→60%` speed and +`15%→40%` damage.
- Peewee is **unstoppable**: stuns and slows do not apply.
- Each enemy killed by a buffed unit adds 0.5 s to the duration, up to +8 s.
- AI: cast when ≥15 allied units are within 900 and enemies are within 1200, or when the army fights an enemy hero.
- FX:
  - `ring{kind="shock", r0=0, r1=900, color={0.4,0.75,1,0.8}, ttl=0.6}` and `flash{radius=300}`.
  - `attach "trail"` in blue on each buffed unit (at most 40).
  - On Peewee: `attach "electric"` in blue, intensity 0.8, plus `attach "aura" {pattern="electric", radius=220}`.

## 4. armt4aegis: Razor, the Phantom (armraz x2.0): human concept, binding
Razor is a very fast laser assassin. It strikes out of cloak, burns its own hull to fire faster, and hides behind a personal deflector.
A crown of red-laser drones circles it all the time.
**Weapons kept:** `mech_rapidlaser`, Rapid Lasers. The v18 `T4_SHIELD` weapon is **removed**: the shield is now a Lua absorb pool (a2).

**a1 Phantom Cloak (active, self, cd `30→14`, starts after the cloak ends).**
- Razor cloaks for `6→15` s with +`20%→60%` speed. It decloaks when an enemy comes within 100.
- **Ambush**: the first salvo out of cloak deals +`50%→150%` damage. That salvo ends the cloak.
- AI: cast when moving toward a target ≥1200 away (an enemy hero or a back-line unit), or when HP < 35% to escape.
- FX:
  - `ring{kind="hex", r0=0, r1=150, color={0.6,0.8,1,0.5}, ttl=0.4}`.
  - `attach "cloak"` and a faint `attach "trail"` while cloaked.
  - Ambush hit: `flash{radius=80, color={0.85,0.6,1,1}}` at the target.

**a2 Deflector Shell (passive).** A personal absorb pool soaks **all** damage types before HP.
- Capacity `15000→90000`. It regenerates `300→1800` per second after 3 s with no hits.
- When the shell breaks, its regeneration starts after 6 s instead.
- Implemented in the `damaged` hook. Unit rules param `hero_absorb` / `hero_absorb_max` for the UI bar.
- FX:
  - `attach "sphere" {radius=130, color={0.5,0.75,1,0.25}, hex=true, fresnel=1.5}`. Alpha follows the pool fraction; the sphere is hidden at 0.
  - `HeroFX.hit` at each absorbed hit.
  - On break: `flash{radius=160}` and `ring{kind="hex", r1=220, ttl=0.4}`.

**a3 Overcharge (active toggle, self, 3 s between toggles).**
- While on, rate of fire is +`30%→100%`. It costs `1.2%→0.8%` of max HP per second.
- It turns itself off at 15% HP, so it can never kill Razor.
- AI: turn on when an enemy is in weapon range and HP > 45%. Turn off when HP < 35% or after 4 s with no enemy.
- FX:
  - `swapWeapons("oc")` (`mech_rapidlaser_oc`: thicker, orange-red core).
  - `attach "electric" {color={1,0.45,0.15,1}, intensity=0.5}` and `attach "aura" {pattern="heat", color=orange, radius=120}`.

**ult Razor Swarm (passive).** Permanent drones circle Razor. Count per rank: `{2,2,3,3,4,4,5,5,6,6}`.
- Each drone fires `hero_dronelaser` for `700→1400` DPS. Range is 0.8× the laser's.
- Target: Razor's target, otherwise the nearest enemy.
- The drones are FX orbs and cannot be targeted. Each drone's synced position comes from `orbPos`, and the shot from `api.fire`.
- While Razor is cloaked the drones go dark and hold fire. On Ambush every drone fires at the ambush target at once.
- About +8.4k DPS at r10. dtype laser.
- FX:
  - Per drone: `attach "orb" {color={1,0.2,0.2,1}, radius=14, height=110, orbit=160, speed=0.6, phase=i/N}` and `attach "trail"`.
  - Per shot: `beam(orbPos→target, {1,0.15,0.1,1}, width=4, core=0.6, ttl=0.12)`.
- Design choice: the human says "like the Legion drone carrier". Untargetable orbs keep Razor's speed, with no pathing or air leash. If the human wants killable drones, the same numbers work through `api.summon`.

## 5. armt4prowler: Prowler, the Riptide (armprowl x2.6)
The human's "twin-barrel tank with a rocket launcher". Prowler is an amphibious hunter.
- Its gauss twin-cannon cracks armour and its missiles detonate the cracks.
- It harpoons its prey into range and hides its pack in sea fog.

**Weapons kept:**
- `armmech_cannon`: Twin Gauss.
- `armamph_missile`: Tandem Missiles. `onlytargetcategory` is changed from VTOL to `SURFACE VTOL`, so it hits ground too.

**a1 Tandem Strike (passive).** Each gauss hit adds one **Breach** stack (max `3→8`, lasts 6 s).
- A missile that hits a breached target detonates all its stacks: `1200→3000` × stacks bonus damage that ignores armour. dtype rail.
- FX:
  - Each stack: `ring{kind="rune", r1=1.1×unit radius, color={1,0.6,0.2,0.6}, ttl=0.3}`.
  - Detonation: `flash{radius=60+20×stacks, color={1,0.85,0.6,1}}` and `ring{kind="shock", r1=140, ttl=0.3}`.

**a2 Harpoon (active, unit, range `700→1000`, cd `22→10`).** Prowler fires a cable harpoon.
- It deals `3000→10000` damage and gives the target maximum Breach stacks.
- It pulls the target to Prowler over 0.6 s, then roots it `1→2.5` s. The pull only works on non-hero units with mass ≤ Prowler's. Heroes are only rooted, for 1.5 s.
- AI: target an enemy hero or a unit that costs ≥5000, when it is in harpoon range but outside gun range. Also a fleeing enemy hero below 40% HP.
- FX:
  - `beam(prowler→target, {0.8,0.8,0.85,1}, width=3, core=0.8, ttl=0.1)`, re-emitted every 3 frames for as long as the pull lasts.
  - `flash{radius=50}` on hit, and `ring{kind="shock", r1=120}` at the target when the pull ends.

**a3 Riptide Fog (active, map, range 800, cd `35→18`).** A sea-fog cloud of radius `300→550` lasts `5→10` s.
- Allies inside, Prowler included, are cloaked. They decloak when they fire.
- Enemies inside are slowed 30%. Prowler moves 30% faster inside it.
- AI: cast on Prowler's own position when HP < 45% with enemies near, or on an allied group about to engage, with ≥4 allies within 500.
- FX:
  - `zone{pattern="fog", color={0.6,0.7,0.8,0.35}, radius}` (FX need, see the end).
  - Fallback: `ring{kind="hex"}` every 1 s, with low-alpha `flash` puffs (radius 120, ttl 1.2) at 6 random points.
  - `attach "cloak"` on the cloaked allies.

**ult Apex Predator (active, unit enemy, range 1400, cd `120→70`, duration `10→20`).** Marks one prey. The prey is revealed for the duration.
- Prowler moves +`30%→70%` faster toward it, and its gauss and missiles deal +`30%→60%` damage to it.
- Every missile hit detonates Breach **without** using up the stacks.
- If the prey dies while marked, Prowler heals 25% of max HP and half of the ult cooldown is refunded.
- AI: target an enemy hero within 1400 with HP ≤ 60%, or any enemy that costs ≥20k.
- FX:
  - On the prey: `attach "aura" {pattern="runes", color={1,0.2,0.15,0.7}, radius=1.5×unit}` and `pillar{radius=40, height=600, red, ttl=1}` on the cast.
  - Tether: `beam(prowler→prey, {1,0.3,0.2,0.3}, width=2, ttl=0.5)`, re-emitted every 0.5 s.
  - On Prowler: `attach "trail"` in red.

## 6. armt4ratte: Ratte, the Landship (armrattet4 x1.5)
Ratte is the scavengers' land battleship in Armada colours. It is the slowest hero and the hardest to kill, built to crack fortress lines.
Its giant 5-shell plasma battery outranges defences. Its ultimate is one shell from the main gun.
**Weapons kept:** `arm_bosscannon`, Main Battery: 5 projectiles, AoE 292, about 1300 range.

**a1 Overpressure (passive).** Every 4th salvo is an **Overpressure** salvo, counted in the `projectile` hook.
- Overpressure: `1.5→3.0`× damage, 1.5× AoE, units in the blast are knocked back and stunned 1 s.
- **Every** salvo deals +`30%→120%` against buildings. dtype plasma.
- FX:
  - The Overpressure salvo uses `swapWeapons("op")` for that salvo (`arm_bosscannon_op`: bigger, white-hot) with a muzzle `flash{radius=150, orange}`.
  - Impact: `ring{kind="shock", r1=1.5×AoE, color={1,0.8,0.5,0.9}, ttl=0.5}` and a `flash`.

**a2 Creeping Barrage (active, map, range 1.6× gun range, cd `35→18`).** Over 4 s, `8→20` shells walk in a line from 400 in front of the point to 400 behind it.
- Each shell: `3000→6000` damage in radius 220.
- About 120k at r10.
- AI: aim along the axis of the densest enemy cluster (≥6), or along a line of ≥3 enemy buildings, defences first.
- FX:
  - 0.6 s before each shell: `ring{kind="rune", r1=250, color={1,0.45,0.2,0.7}, ttl=0.6}` at its impact point.
  - Impact: stock CEG plus `ring{kind="shock", r1=260, ttl=0.35}`.
- Weapondef: `hero_barrage` (a Cannon shell, high arc).

**a3 Landship Plating (passive).**
- Damage from the front 90° arc is −`10%→35%`.
- **Crusher Treads**: enemies within 120 of the hull front take `800→3000` damage per second and are slowed 50%.
- Hit direction comes from the attacker's position. If the attacker is dead, the projectile's origin is used.
- FX:
  - `attach "sphere" {radius=190, color={1,0.7,0.4,0.0}, hex=true}`. It is invisible except for `HeroFX.hit` ripples on blocked frontal hits.
  - Treads: `ring{kind="shock", r1=150, color={0.8,0.6,0.4,0.5}, ttl=0.3}` at the bow every 0.5 s while crushing.

**ult Main Gun (active, map, range `2500→4000`, cd `150→90`).**
- 2 s windup, immobile. Then one super shell flies on a high arc (about 3 s).
- Impact: `20000→45000` damage at the centre, falling to 30% at the 500 edge. Buildings take ×1.5.
- It leaves a firestorm of radius 450 for 8 s that deals `1000→2500` per second.
- About 250k against a clump at r10. dtype plasma / flame (firestorm).
- AI: aim where 500 radius covers ≥40k enemy cost or ≥4 buildings including defences.
- FX:
  - Windup: `attach "aura" {pattern="heat", color=orange, radius=260}` and a growing `flash` at the muzzle.
  - Launch: `flash{radius=200, white}`.
  - Target telegraph: `ring{kind="rune", r1=500, color=red, ttl=flight time}`.
  - Impact: `flash{radius=700, color={1,0.85,0.6,1}, ttl=0.6}`, `ring{kind="shock", r0=0, r1=900, ttl=0.8}` and `pillar{radius=250, height=1500, orange, ttl=0.7}`.
  - Firestorm: `zone{pattern="heat"}` (FX need). Fallback: `ring{kind="hex", red-orange}` every 1 s with flicker flashes.
- Weapondef: `hero_supershell` (a Cannon, slow, `mygravity` tuned). Damage is dealt through the kit's impact path.

## 7. armt4recluse: Recluse Matriarch (armsptkt4 x1.6, all-terrain)
The giant rocket spider fights from cliffs. It webs the battlefield, cocoons its prey, and buries a pack under a monsoon of rockets.
**Weapons kept:** `adv_rocket`, parabolic multi-rocket launcher, burst 6, about 1800 range.

**a1 Web Rockets (passive).** Every rocket hit applies **Webbed** for 3 s.
- Webbed: −`8%→20%` speed per hit, stacking up to 60%.
- Webbed units take +`5%→15%` damage from Recluse.
- FX: `attach "aura" {pattern="hex", color={0.75,1,0.75,0.4}, radius=1.2×unit, ttl=3}`, refreshed on each hit. Above 30 webbed units, a `ring{kind="hex"}` is used per hit instead.

**a2 Web Field (active, map, range 1400, cd `26→14`).** A web canister bursts into a field of radius `300→550` for `6→12` s.
- Enemies in the field are slowed 50% and revealed. Heroes in it cannot dash or leap.
- Recluse's rockets get +50% AoE inside the field.
- AI: cast on an enemy cluster of ≥6, or on an enemy hero moving toward allies.
- FX:
  - `ring{kind="hex", r1=R, color={0.85,1,0.85,0.5}, ttl=duration}` and `ring{kind="rune", r1=0.6R}`.
  - Silk strands: every 1 s, `chain{points = rim → centre → opposite rim, color={0.9,1,0.9,0.6}, width=2, jitter=0.05, ttl=1.0}`, 6 strands at different angles. Static silk, not lightning.

**a3 Cocoon (active, unit enemy, range 900, cd `20→10`).** Wraps a non-hero enemy that costs ≤ `3000→15000`.
- The target is stunned `4→10` s and takes +50% damage.
- If it dies while cocooned, it hatches `1→3` spiderlings for Recluse (`armt4recluse_spiderling`, 20 s, leash 600).
- On a hero: root `1→2.5` s and 30% slow.
- AI: cast on the most expensive enemy within 900 under the cost cap. If an enemy hero is in range and closing, cast on it.
- FX:
  - `chain(recluse→target, {0.9,1,0.9,1}, width=3, jitter=0.08, ttl=0.5)`.
  - `attach "sphere" {radius=1.1×unit, color={0.85,1,0.85,0.6}, hex=true, fresnel=0.5, ttl=stun}`.
  - Hatch: `flash{radius=80, green}`.

**ult Rocket Monsoon (active, map, range `1800→2600`, cd `120→75`).**
- Recluse plants itself for `6→10` s and rains `36→90` rockets on radius 600.
- Each rocket: `1600→2600` damage, AoE 160, applies Webbed.
- About 230k at r10. dtype rocket.
- AI: aim at a cluster of ≥10 enemies or ≥30k cost in radius 600.
- FX:
  - `ring{kind="rune", r1=600, color={0.6,1,0.6,0.6}, ttl=duration}`.
  - On Recluse: `attach "aura" {pattern="runes", green, radius=250}`.
  - A muzzle `flash` per volley. The rockets are `hero_monsoon` (a MissileLauncher copy of `adv_rocket`).

## 8. armt4olympus: Olympus, the Thunderer (Vanguard x2.2)
Olympus is strategic artillery. It splits its shells over packs, calls spotter flares deep into the fog, digs in for range, and drops an ion lance from orbit.
**Weapons kept:**
- `shocker_low` / `shocker_high`, with `alt`.
- `smart_trajectory_dummy`.

**a1 Cluster Shells (passive).** On impact every shell splits into `2→7` bomblets. They scatter over radius 150–350, and each deals `12%→18%` of the shell's damage (`hero_bomblet`). dtype plasma.
- Needs the **impact hook**, because shells hit ground, not units.
- FX: the bomblets' own small CEG, plus a `flash{radius=40, color={0.6,0.85,1,1}}` per bomblet and a `ring{kind="shock", r1=200, ttl=0.3}` at the split.

**a2 Spotter Flare (active, map, range `4000→7000`, cd `40→20`).** A flare reveals radius `600→1200` for `8→20` s, for the whole allyteam.
- Olympus's shells landing inside deal +`15%→40%` damage and ignore radar wobble.
- AI: cast at the centroid of enemy radar blips in range that are not in LOS, or at its attack target when that is not in LOS.
- FX:
  - `pillar{radius=40, height=900, color={0.5,0.9,1,0.6}, ttl=duration}` that fades.
  - `ring{kind="rune", r1=R, cyan, ttl=2}`, re-emitted every 2 s.
  - A `flash` at launch.
- Implementation: summon `armt4olympus_flare` (an invisible, untargetable sensor unit with sight R, expiring).

**a3 Siege Anchor (active toggle, self).** Deploying takes 1.5 s.
- While deployed: immobile, range +`15%→40%`, damage +`10%→25%`, damage taken −20%.
- AI: deploy when an enemy is within 1.4× range and none is within 900. Undeploy when an enemy comes within 900 or a move order arrives.
- FX: on deploy `ring{kind="hex", r1=220, color={0.5,0.75,1,0.8}}`; while deployed `attach "aura" {pattern="runes", blue, radius=200}`.

**ult Ion Lance (active, map, range `6000→9000`, cd `150→90`).**
- 3 s telegraph. Then the lance hits radius `350→600`: `25000→50000` damage at the centre, falling to 30% at the edge, and a 2 s stun.
- 3 aftershock pulses follow, one per second, each 10% of the hit.
- About 300k against 10 units at r10. dtype electric.
- AI: aim at the highest-value cluster (≥30k cost in radius 500), or at a stationary enemy hero (speed < 10).
- FX:
  - Telegraph: `ring{kind="rune", r0=R, r1=0, color={0.6,0.85,1,0.7}, ttl=3}`, a shrinking rune circle.
  - Hit: `pillar{radius=0.6R, height=3000, color={0.8,0.95,1,1}, ttl=1.2}`, `flash{radius=R, ttl=0.5}` and `ring{kind="shock", r0=0, r1=1.5R, ttl=0.7}`.
  - Aftershocks: `ring{kind="electric", r1=R}`.

## 9. armt4starlight: Starlight, the Lance (armmanni x2.4)
Starlight is the tachyon sniper. Its beam focuses the longer it stays on one target and goes through it.
- It refracts through allied units to reach around corners and blinks away from divers.
- It ends heroes with a solar lance.

**Weapons kept:** the tachyon beam (`armmanni` BeamLaser), about 2090 range.

**a1 Focusing Array (passive).**
- Each shot in a row on the same target adds +`10%→25%` damage, up to `3→6` stacks. Changing target resets it.
- The beam goes `300→900` beyond the target and deals 50% to everything on that line.
- dtype laser. Needs the line helper.
- FX:
  - Overlay `beam(hero→target, {0.75,0.6,1,1}, width=6+4×stacks, core=0.5+0.08×stacks, ttl=0.2)`.
  - Pierce segment: the same `beam` at alpha 0.5.

**a2 Prism Relay (active, ally, range 1500, cd `30→16`, duration `8→16`).** Starlight links to an allied unit.
- Each of Starlight's shots also refracts from that ally to the most expensive enemy within 700 of the ally, for `50%→100%` of the shot's damage (`hero_prism`).
- AI: cast when there is no target in Starlight's range but an ally within 1500 has enemies within 700. It picks the ally with the most enemy cost around it.
- FX:
  - Link: `beam(starlight→ally, {0.7,0.55,1,0.35}, width=3, ttl=0.5)`, re-emitted every 0.5 s.
  - On the ally: `attach "orb" {color={0.8,0.6,1,1}, radius=18, height=80, orbit=0}`, the prism.
  - Refracted shot: `beam(ally→enemy, {0.85,0.75,1,1}, width=10, core=0.7, ttl=0.25)`.

**a3 Phase Shift (active, map, range `500→900`, cd `22→10`).**
- Starlight teleports instantly.
- At the spot it left, a light mine detonates after 1 s: `5000→15000` damage in radius 250.
- AI: when an enemy is within 600 and HP < 70%, blink away from the nearest threats (0.8× range). If no threat, never.
- FX:
  - Both ends: `flash{radius=120, color={0.85,0.75,1,1}}`.
  - Streak: `beam(old→new, width=20, core=1, ttl=0.15)`.
  - Mine: `ring{kind="rune", r1=250, ttl=1}`, then `flash` and `ring{kind="shock", r1=300}`.

**ult Solar Lance (active, unit/map, range `4000→6000`, cd `140→80`).**
- 2 s charge, immobile. Then a lance holds on the target for `3→5` s.
- The primary target takes `20000→40000` per second. Everything else on the line (width 100) takes 40% of that.
- Up to 200k on one hero at r10. dtype laser.
- AI: target an enemy hero, or the most expensive enemy in range. The line with the most enemies on it breaks ties.
- FX:
  - Charge: `attach "orb" {color=white-violet, radius 10→40, height=40, orbit=0}` and a growing `flash`.
  - Lance: `beam{color={0.85,0.8,1,1}, width=60, core=0.4, pulse=6, ttl=0.1}`, re-emitted every 3 frames.
  - At the target: `pillar{radius=120, height=1200}` and `ring{kind="shock", r1=300}` every 0.5 s.

## 10. armt4hive: Hive Mother (armdronecarryland x1.5): the human's "drone carrier"
The Hive Mother is a carrier tank that fights through its swarm. Its drones focus prey, dive as kamikazes, and in the end it anchors as a mothership.
**Weapons:**
- `plasma` (0 damage, stockpile) is dropped, and the carrier customparams are removed, so that `unit_carrier_spawner` does not run a second drone system.
- New `hero_pdlaser` (BeamLaser, 900 range): its own 3k DPS.

**a1 Drone Bay (passive).** Keeps `6→16` drones alive: `armt4hive_drone`, armdrone x1.8, HP `5000→9000` (grows with the hero level).
- One drone is rebuilt every `6→3` s.
- The drones together deal `3500→9000` DPS, split evenly: `hero_dronelaser_hive`, damage set per rank.
- Leash 1300, engage 1250. Drones attack the Hive's target first.
- FX:
  - Launch: `flash{radius=40, amber}` at the deck.
  - Each drone: `attach "trail" {color={1,0.7,0.2,1}}`.

**a2 Swarm Directive (active, unit enemy, range 1600, cd `20→10`, duration 8 s).** Every drone focuses the target, with +`30%→90%` damage.
- Each drone hit adds a 3% slow, up to 45%. The target is revealed.
- AI: target an enemy hero, or the most expensive enemy within 1600, when ≥4 drones are alive.
- FX:
  - `beam(hive→target, {1,0.75,0.3,0.5}, width=3, ttl=0.3)`, the order line.
  - Target: `attach "aura" {pattern="runes", color={1,0.7,0.2,0.6}, radius=1.3×unit}` for the duration.
  - Drone trails turn bright amber.

**a3 Kamikaze Run (active, map, range 1800, cd `24→12`).** Up to `3→10` drones dive at the point and explode.
- Each: `4000→9000` damage in radius 200 (`hero_dronebomb`). About 90k at r10.
- Then 2 drones are rebuilt at once.
- AI: aim at a cluster of ≥5 enemies or an enemy hero, when drones ≥ the dive count + 2.
- FX: each diving drone gets `attach "trail" {color={1,0.4,0.1,1}}`. Each blast: `flash{radius=180, orange}` and `ring{kind="shock", r1=220, ttl=0.35}`.

**ult Mothership Protocol (active, self, cd `140→80`, duration `10→20`).** The Hive anchors (immobile) and launches `3→8` Guardians.
- Guardians: `armt4hive_guardian`, the armdroneold model x2.5, HP 20k, missiles, 1500 DPS each. They last for the duration plus 10 s.
- While anchored: drone rebuild ×3 speed, and all drones and guardians get +`20%→50%` damage and −20% damage taken.
- A repair field of radius 800 heals drones and allies `500→2000` HP/s.
- About 240k from the guardians at r10.
- AI: cast when ≥10 enemies or an enemy hero are within 1500 and the Hive is not being dived (no enemy within 400).
- FX:
  - `ring{kind="hex", r0=0, r1=800, color={1,0.75,0.3,0.7}, ttl=0.6}` on the cast.
  - `attach "aura" {pattern="heal", color={1,0.8,0.4,0.4}, radius=800}` for the duration.
  - `pillar{radius=60, height=700, amber, ttl=0.8}` per guardian launch.
  - Guardians: `attach "electric"` in amber, intensity 0.3.

---

## API needs (beyond SPEC §4)
1. **Movement control.** `api.dash(uid, x, z, {seconds, arc=height, onStep=fn, onLand=fn})` through MoveCtrl.
   - Used by Atlas Seismic Charge (ground) and Peewee Jump Jets (arc).
   - `api.teleport(uid, x, z)` for Starlight Phase Shift: SetUnitPosition, clear orders, keep facing.
   - `api.pull(uid, toX, toZ, seconds)` and `api.knockback(uid, fromX, fromZ, strength)` for the Prowler Harpoon, Ratte Overpressure and the Peewee landing.
   - Respect mass, and let the engine refuse buildings and immobile units.
2. **Taunt.** `api.taunt(enemyID, heroID, seconds)`: forced attack order or SetUnitTarget, restored afterwards (Atlas Bulwark).
3. **Buffs and debuffs on non-hero units.**
   - `api.unitBuff(uid, id, seconds, {speed, damage, armor, regen, cloak})` for Peewee Pack Leader/Overrun and the Prowler fog cloak.
   - `api.mark(uid, id, seconds, {damageTaken, damageTakenFrom=heroID|ally, slow, root, reveal, noDash})` for Sundered, Webbed, Breach, Cocoon, the Hive latch and the Apex prey.
   - Marks must be applied in UnitPreDamaged for **all** attackers, with slows through `SetUnitMaxSpeed` or MoveCtrl.
4. **Buff mods missing from `api.buff`:**
   - `unstoppable`: immune to stun and slow (Peewee).
   - `frontArmor = {arc, reduce}`, or let the `damaged` hook get the hit direction (Ratte).
   - `turretTurn` (Thor Rage). Turret speed is in `armthor.bos` (`KT1_*` macros), so the script needs a `SetTurretSpeedMult` or a static-var the core can set with `CallCOBScript`. Who owns `scripts/Units/*.bos`?
5. **Impact hook.** `impact(api, unitID, h, weaponDefID, x, y, z, projectileID)` from `Explosion` / `SetWatchExplosion`. Shells that hit ground (Olympus bomblets, Ratte Overpressure knockback) never reach `hit`.
6. **Fired hook.** `fired(api, unitID, h, weaponNum, targetID|x,y,z)`, once per shot or salvo (Starlight Prism and Focus stacks, Ratte salvo counter, Razor Ambush). `projectile` fires per projectile, and not cleanly for beams.
7. **Line damage.** `api.line(x1, z1, x2, z2, width, dmg, attackerID, opts)` for the Doomsday Lance, Solar Lance and the Starlight pierce.
8. **Weapon helpers:**
   - `api.target(uid)`: the hero's current weapon target (orb and drone targeting).
   - `api.resetReload(uid, weaponNum)`.
   - `api.fireRateMult` through the `reload` buff (Razor Overcharge) must also scale burst rate.
9. **Consume an own unit.** `api.consume(uid)`: DestroyUnit with no wreck and no death explosion, which also skips the XP and kill bookkeeping. Exclude commanders and the altar (Thor Electro-Devour).
10. **Summon extras:**
    - `opts.respawn = {max, every}`, maintained by the core (Hive Drone Bay).
    - `opts.guard = heroID`: drones attack the hero's target.
    - `api.order(uids, cmd, params)` (Swarm Directive, Kamikaze).
    - Summons give no hero XP to enemies and drop no items.
11. **Reveal.** `api.reveal(x, z, r, seconds, allyTeam)` or `api.reveal(uid, seconds)`. It can be built by summoning a shared invisible sensor unit `armt4_sensor`: no model, sight r, invulnerable, `nocollide`. Used by the Olympus flare, Web Field, Apex prey and Swarm Directive.
12. **Absorb pool UI.** Unit rules params `hero_absorb`, `hero_absorb_max` (Razor), for the ui agent.
13. **FX needs (for the fx agent):**
    - `GG.HeroFX.zone(x, z, {radius, color, pattern = "electric"|"heat"|"heal"|"runes"|"hex"|"fog", ttl})`: a ground disc at a point, not attached to a unit (Ratte firestorm, Prowler fog, Web Field). Otherwise a sensor unit + `attach "aura"` is the fallback.
    - `attach "orb"` needs `phase` (several orbs evenly spread: the Razor drones) and an animated `radius` (the Starlight/Atlas charge).
    - `attach "sphere"` alpha must be changeable at runtime (Razor pool fraction).
14. **Movement class `T4ATANK8`** (amphibious T4 tank: `maxwaterdepth = DEPTH.AMPHIBIOUS`, `speedModClass = Tank`, footprint 8, crush max) for Prowler, in `gamedata/movedefs.lua`. Nobody owns that file in SPEC §7, so the core should take it.
15. **Starburst ban (reminder).** `api.fire` and `swapWeapons` must never spawn or copy a StarburstLauncher (the v15.1 savegame crash). The Thor EMP missile becomes a MissileLauncher copy. Atlas `bantha_rocket` stays untouched.

## New weapondefs and unitdefs (content-arm)
| Hero | weapondef / unitdef | Kind | Use |
|---|---|---|---|
| Thor | `thunder_red`, `emp_red` | swap copies (red, draw-only damage as the `_sN` copies) | Rage |
| Thor | `hero_orbbolt` | LightningCannon, range 2× thunder, thunder dmg | Rage orb |
| Thor | `hero_empmissile` | MissileLauncher copy of `empmissile` (not starburst) | a2 |
| Atlas | none (the lance is FX + `api.line`) | — | `banthfootstep` re-used for step sound |
| Peewee | `emg_hot` | swap copy, bigger white-blue plasma | Hot Barrels |
| Razor | `mech_rapidlaser_oc`, `hero_dronelaser` (red BeamLaser, beamtime 0.1) | swap / fire | Overcharge, drones; drop `t4_shield` |
| Prowler | `armamph_missile` override `onlytargetcategory = "SURFACE VTOL"` | edit | ground missiles |
| Ratte | `arm_bosscannon_op`, `hero_barrage`, `hero_supershell` | swap / Cannon / slow Cannon | a1, a2, ult |
| Recluse | `hero_monsoon` (MissileLauncher copy of `adv_rocket`), `hero_webcanister` (0-dmg Cannon); unit `armt4recluse_spiderling` (armspid x1.4, EMP laser) | fire / summon | ult, a2, a3 |
| Olympus | `hero_bomblet` (small Cannon), `hero_flare` (0-dmg Cannon); unit `armt4olympus_flare` (sensor) | fire / summon | a1, a2 |
| Starlight | `hero_prism` (tachyon BeamLaser copy) | fire | a2 |
| Hive | `hero_pdlaser` (own BeamLaser, 3k DPS), `hero_dronebomb`; units `armt4hive_drone` (armdrone x1.8, `hero_dronelaser_hive`), `armt4hive_guardian` (armdroneold x2.5, missiles); strip carrier customparams | weapon / summon | a1, a3, ult |
| shared | unit `armt4_sensor` (invisible reveal) | summon | reveal |

Notes for core/balance:
- **Hive DPS.** `T4.heroBalance` normalises only the unit's own weapons. Hive's 3k is the pd laser; the drone DPS comes from a1 (`3500→9000`), so the console should add it to the shown DPS.
- **Thor Electro-Devour cap.** The 30%-of-max-HP heal cap is my addition against "eat a 13.5k Bantha for 138k". If the human wants the plain 200%, drop the cap.
- **Razor drones.** Untargetable FX orbs are my reading of "like the Legion drone carrier". Switching to real units is a data change.
- **New models.** The six new heroes need generated `Units/T4/<name>.s3o` and `_dead.s3o` (the same scaling pipeline as the existing four). armvadert4 and armdronecarryland have no `_dead` model in scavboss; Hive must use `armdronecarry_dead.s3o`.
