# v19 roster — Cortex (design, wave 1)

Ten Cortex heroes for `cort4gant`. The four current heroes get new kits (Juggernaut follows SPEC §1.8, which is
binding), and six are new. The design is concrete enough for content-cor to code from. All numbers are **before**
ability power (`api.power`: ×1.01/level; a normal r10 needs L27 → ×1.26, an ult r10 needs L100 → ×1.99).
`a→b` means `H.lin(a, b)` (r1→r10, linear); integers round down. "Heroes ½" means heroes get half of stun, slow,
root, pull or taunt time. Damage from abilities always goes through `api.damage` / `api.area` (it never hurts allies).

Cortex palette for FX: hot orange `{1,0.45,0.1}`, red `{1,0.2,0.1}`, amber `{1,0.7,0.25}`, white-hot core
`{1,0.95,0.85}`. Exceptions: EMP effects are cyan `{0.45,0.85,1}` (Commando, Cataphract stun) and nano effects are
green `{0.35,1,0.45}` (Printer).

Command ids: Cortex uses block `36200 + 10*i + slot` (i = row index below, slot a1=1 a2=2 a3=3 ult=4). This
assumes Armada keeps 361xx and Legion takes 363xx; the orchestrator decides.

## Summary

| i | unitname | Hero | Base unit (file) | Scale / fx / movedef | Role · aiRole | L1 HP / DPS / speed | Weapon range |
|---|---|---|---|---|---|---|---|
| 0 | `cort4bastion` | **Juggernaut**, the Unkillable | `corjugg` Behemoth (`units/CorGantry/corjugg.lua`) | 1.6 / 2.2 / T4BOT11 | killer tank, anti-big · front | 520k / 8.5k / 30 | 770 gauss, 565–715 lasers |
| 1 | `cort4colossus` | **Colossus**, the Warlord | `corkorg` (`units/CorGantry/corkorg.lua`) | 1.8 / 2.2 / T4BOT11 | initiator, crowd control · front | 440k / 10k / 34 | 830 gun, 1260 heat eye |
| 2 | `cort4hellwalker` | **Hellwalker**, the Inferno | `cordemon` Demon (`units/CorGantry/cordemon.lua`) | 2.0 / 2.5 / T4BOT8 | flame brawler, anti-swarm · front | 400k / 12k / 50 | 800 flame |
| 3 | `cort4armageddon` | **Armageddon**, the Doomsayer | `corcat` Catapult (`units/CorGantry/corcat.lua`) | 2.0 / 2.5 / T4BOT8 | rocket artillery, area siege · back | 220k / 8k / 34 | 2700 |
| 4 | `cort4vesuvius` | **Vesuvius**, the Twin-Barrel | `corves` (`units/Scavengers/Vehicles/corves.lua`) | 1.8 / 2.2 / T4TANK9 | siege tank, anti-structure/big · center | 380k / 10k / 34 | 1200 cannon, 960 missiles, 480 flamer |
| 5 | `cort4printer` | **Printer**, the Swarm Foundry | `corprinter` (`units/CorVehicles/T2/corprinter.lua`) | 2.8 / 2.2 / T4TANK9 | drone carrier, support · center | 300k / 5k (+drones) / 42 | 750 nano beam, drones 900 leash |
| 6 | `cort4commando` | **Commando**, the Ghost | `cormandot4` (`units/Scavengers/Bots/cormandot4.lua`) | 2.6 / 2.2 / T4BOT8 | assassin, cloak, EMP · front (flank) | 240k / 11k / 70 | 500 |
| 7 | `cort4deadeye` | **Deadeye**, the Marksman | `cordeadeye` (`units/Scavengers/Bots/cordeadeye.lua`) | 2.8 / 2.2 / T4BOT8 | sniper, anti-big · back | 220k / 9k / 30 | 1870 |
| 8 | `cort4karganeth` | **Karganeth**, the Hydra | `corkarganetht4` (`units/Scavengers/Bots/corkarganetht4.lua`) | 1.8 / 2.2 / T4TBOT9 | anti-air and anti-swarm, all-terrain · center | 340k / 10k / 40 | 1050 missiles, 1470 AA |
| 9 | `cort4cataphract` | **Cataphract**, the Lancer | `corsok` (`units/CorGantry/corsok.lua`) | 2.0 / 2.2 / T4HOVER8 (new) | hover flanker, lockdown · front (flank) | 300k / 10k / 64 | 1015 bolt, 560 depth charges |

Coverage: front 5 (two of them flankers), center 3, back 2. Anti-big: Juggernaut, Deadeye, Vesuvius. Anti-swarm:
Hellwalker, Armageddon, Karganeth. Assassin and backline hunters: Commando, Cataphract. Support: Printer, Colossus
(Warcry). Anti-air: Karganeth. Water: Cataphract (hover), Commando (amphibious).
Mobility: T4BOT/T4TANK, all-terrain (Karganeth), hover (Cataphract). The new units' DPS and HP come from
`T4.heroBalance`; the per-weapon multipliers below only shape the split.
Benched (fine as later swaps): `corthermite` (pyro spider), `corshiva`, `cortrem`, `corsiegebreaker`, `corgolt4`.
Naming trap: in stock BAR `corkorg` is *displayed* as "Juggernaut" and `corjugg` as "Behemoth". The hero
**Juggernaut** is built on `corjugg`, as SPEC §1.8 says, and Colossus stays on `corkorg`.

---

## 0. cort4bastion — Juggernaut, the Unkillable (corjugg ×1.6)
*A slow armoured killing machine. It erases one target at a time, burns everything that closes in, and when it
falls it gets back up.*
**Weapons:** `juggernaut_fire` (Gauss DGun, pierces its line), `juggernaut_bottom` ×2 (twin lasers), `juggernaut_top`.
**Drop** the old `T4_SHIELD`.
- **a1 Power Shot** (active, `unit`, cmd 36201). The turret locks onto the target and fires `4→8` Gauss shells
  (`cort4bastion_powershot`), one every 0.25 s, each `4000→8000`. Every shell that hits the same target adds +8%
  to the next one (r10: about 82k on one target). The shells pierce like the DGun, so anything on the line takes
  50%. Range = gun range + `200→600`. Cooldown `20→12` s. The hero is immobile while firing.
  *AI:* targets the highest-cost enemy in range (a hero, then units ≥ 8k metal). If there is none, it fires along a
  line that crosses ≥ 4 enemies. Not cast when HP < 25%.
  *FX:* on cast, `ring{kind="hex", r0=140→r1=60, color=red .8, ttl=count*0.25}` under the target as a lock
  reticle. Each shot: `flash` at the muzzle (`api.piecePos`) radius 90, orange, 0.15 s, plus a `beam` tracer muzzle→impact (width 14,
  core white-hot, color orange, ttl 0.12). The last shell adds `ring{kind="shock", 50→320, orange, ttl .4}`.
- **a2 Circle Beam** (active, `self`, cmd 36202). The hero anchors for 3 s (`immobile`, −25% damage taken). The
  turret turns 360° (r10: 540°) and the two lower lasers merge into one twin beam of length `650→950`. Every enemy
  the beam crosses takes `6000→14000` per pass and burns for `300→900`/s over 4 s. The beam's half-width (its
  splash) is `60→140`. Cooldown `28→18` s.
  *AI:* ≥ 5 enemies or ≥ 6000 metal of enemies within the length, and HP > 25%.
  *FX:* every 3 frames (ttl 0.12) draw 2 parallel `beam`s, ±12 elmos off the turret line (width 10, core white,
  color `{1,0.35,0.1}`, pulse). Under the hero, `ring{kind="rune", r=length, orange .35, ttl 3}`. Every 0.1 s a
  `flash` at the beam tip (radius 60, ttl .4) leaves a scorched arc. At the end, `ring{kind="shock", .3L→L}`.
- **a3 Reactive Armor** (passive). A hit of ≥ 300 damage (not a beam tick) has a `10%→35%` chance to fire back
  (internal cooldown 0.2 s). A plasma shell (`cort4bastion_reactive`, aoe 120) goes from the hit point at the
  attacker if it is within 1200, otherwise at the nearest enemy within 800. The shell deals `1500→4500` + 50% of
  the triggering hit, capped at 10k. From r6 it fires 2 shells.
  *FX:* at the hit point, `ring{kind="hex", 60→110, amber .6, ttl .25}` (an armour plate lights up) and a `flash`
  of radius 70.
- **ult Resurrection** (passive). A lethal hit (`dying` → true), when off cooldown, makes the Juggernaut collapse.
  For 3 s it is *downed*: invulnerable, untargetable and inert. Then it rises with `35%→80%` HP. Rising sends out
  a shockwave of `8000→30000` in 600 that stuns for 1.5 s, and grants **Unbroken** for 6 s: +`20%→50%` damage and
  −30% reload. Cooldown `300→120` s (the main thing the rank buys).
  *FX:* on the fall, a `flash` of radius 400 (white-orange, 0.5 s) and `attach electric` in dim red at low
  intensity for 3 s. A `ring{kind="rune", 300→80}` contracts over 3 s while a `pillar` grows (radius 120, height
  900, red-orange, 3 s). On the rise, `ring{kind="shock", 80→600, ttl .6}`, a `flash` of radius 500, and for the
  6 s of Unbroken `attach aura{pattern="heat", r=220, red}` + `attach electric{red}`.

## 1. cort4colossus — Colossus, the Warlord (corkorg ×1.8)
*The giant who starts fights. It grabs and hurls enemy machines, its every step shakes the line, and it drops
from the sky into the enemy's heart.*
**Weapons:** `corkorg_fire` (scatter gauss), `corkorg_laser` (Heat Eye), `corkorg_rocket`, `krogkick`, `krogfootstep`.
- **a1 Titan Grip** (active, `unit` enemy, range 450, cmd 36211). Grabs a non-hero enemy and hurls it up to
  `900→1600` away, toward the densest enemy cluster (the player can aim it with a map point). The victim takes
  `4000→15000`. Where it lands, enemies in 250 take `15%→40%` of the victim's max HP (cap 30k) and are stunned
  1.5 s. If the target is a **hero**, Colossus kicks it back 300 and stuns it `0.5→1.5` s (already halved).
  Cooldown `20→12` s.
  *AI:* the heaviest non-hero enemy in 450 whose landing hits ≥ 3 enemies; otherwise the nearest enemy hero.
  *FX:* on the grab, `ring{kind="hex", r 80, amber}` under the victim. In flight, `attach trail{orange}` on the
  victim. On landing, `ring{kind="shock", 40→300, ttl .5}` and a dusty orange `flash` of radius 220.
- **a2 Fault Line** (passive). Every `4→2.5` s while it moves (or on every 3rd kick), a footstep releases a quake:
  `1500→5000` in `300→500`, enemies slowed 40% for 2 s, and +1 *Fault* stack on them (max 3, 6 s). At 3 stacks the
  enemy is knocked down (stunned 1 s, heroes ½) and the stacks reset. Titan Grip landings add 1 stack.
  *FX:* `ring{kind="shock", 60→R, color {0.9,0.6,0.3,.7}, ttl .4}` at the foot. Each stack is one small
  `ring{kind="rune", r 40/55/70}` under the enemy (cap 30 enemies drawn). A knock-down adds a `flash` of radius 80.
- **a3 Warcry** (active, `self`, radius `800→1200`, cmd 36213). Lasts `6→10` s. Allied non-hero units get
  +`15%→40%` damage and +20% speed. **Taunt**: enemies in the radius are forced to target Colossus for `2→4` s
  (heroes ½). Colossus takes `−15%→−35%` damage while the cry lasts. Cooldown `40→26` s.
  *AI:* ≥ 8 allies and ≥ 6 enemies in the radius, and HP > 50%.
  *FX:* `ring{kind="rune", 100→R, red, ttl .8}`. Each buffed ally gets `attach aura{pattern="runes", r=unit
  radius, red}` for the duration (cap 40). From each taunted enemy, a thin red `beam` (width 3, ttl .4) to
  Colossus (cap 20).
- **ult Earthshatter** (active, `map`, range `1000→1600`, cmd 36214). Colossus leaps (1.2 s arc) and lands for
  `30000→80000` in `600→900` (40% at the edge), with a stun of `2→4` s. Six radial fissures, 900 long, then erupt
  3 times over 3 s for `4000→12000` per tick to enemies on them. Cooldown `120→80` s.
  *AI:* the densest enemy cluster in range with ≥ 15k metal, when HP > 40%. Below 25% HP it leaps away from the
  enemy centroid to escape.
  *FX:* at takeoff, a dust `flash` of radius 300 and `attach trail{orange}`. A `ring{kind="hex", R→R*0.3, red}`
  closes at the landing point over the flight. On landing, a `flash` of radius 700 (0.6 s), `ring{kind="shock",
  100→900, ttl .8}`, and 6 ground `beam`s (y+6, width 30, lava `{1,0.4,0.05}`, pulse, ttl 3) with a `flash` of
  radius 80 along each line per tick.

## 2. cort4hellwalker — Hellwalker, the Inferno (cordemon ×2)
*A walking furnace that thrives in crowds: whatever burns long enough explodes, and the explosions spread the fire.*
**Weapons:** `newdmaw` (flame, 800). `karg_shoulder` stays as AA (VTOL only, not counted in DPS).
- **a1 Combustion** (passive). Each 0.5 s in the Maw's flame gives an enemy +1 *Heat* (max 10, decays 1/s).
  At 10 it **combusts**: it takes 8% of its max HP (cap `3000→12000`) + `1500→5000`, enemies in 200 take the same
  flat damage and get +5 Heat. In a swarm this chains.
  *FX:* combustion is a `flash` of radius 180 (orange-yellow), `ring{kind="shock", 30→200, ttl .35}`, and a `pillar`
  (radius 40, height 250, ttl .4). At ≥ 7 Heat a small red `flash` (radius 40, ttl .3) pulses once a second.
- **a2 Hellcharge** (active, `map`, cmd 36222). Dashes `700→1100` through the line. Enemies on the path take
  `3000→9000`, are knocked aside 120 and get +5 Heat. The path becomes a fire wall for 5 s at `600→1800`/s. After the
  dash, flame range is +30% for 3 s. Cooldown `22→14` s.
  *AI:* a point behind a cluster when the path crosses ≥ 3 enemies; escape toward allies when HP < 30%.
  *FX:* `attach trail{fire, width 120}` for the dash. The wall is a ground `beam` (width 80, orange-red, pulse, ttl
  5) with a `flash` of radius 70 every 0.5 s along it. At the end, `ring{kind="shock", 50→350}`.
- **a3 Infernal Furnace** (active, `self`, radius `500→800`, cmd 36223). Inhales for 1.5 s, pulling enemies 200
  toward itself (heroes ½), then exhales a fire nova of `5000→16000` that also adds +5 Heat. Cooldown `30→20` s.
  *AI:* ≥ 6 enemies or ≥ 4000 metal of enemies in the radius, and HP > 30%.
  *FX:* while inhaling, `ring{kind="rune", R→80, orange, ttl 1.5}` and an orange `bolt` (jitter low, ttl .2) every
  0.3 s from each pulled enemy (cap 16). On the exhale, a `flash` of radius 600 and `ring{kind="shock", 60→R,
  width 60}`.
- **ult Hell on Earth** (active, `self`, transformation, cmd 36224). Lasts `8→15` s. Hellwalker grows to ×1.25
  and gets +25% speed. It burns everything within `450→700` for `1500→4500`/s, its flame gives double Heat, and
  2 meteors a second strike random enemies within 1200 (`3000→6000`, aoe 200). At the end it erupts for
  `15000→40000` in 600. Cooldown `110→75` s.
  *AI:* ≥ 20k metal of enemies within 900 and HP > 40%, or an enemy hero within 700.
  *FX:* `setScale` 1→1.25 over 0.5 s. `attach aura{pattern="heat", r=R, orange .6}`, `attach electric{color
  orange, intensity .7}` (the fire licks), `attach trail`. The meteors are a weapondef with a `flash` of radius
  200 on impact. The final eruption is a `pillar` (radius 250, height 1500, ttl 1.2), `ring{shock, →600}`, and a
  `flash` of radius 700.

## 3. cort4armageddon — Armageddon, the Doomsayer (corcat ×2)
*A walking rocket battery: rockets that split over crowds, a painter laser that dooms one target, and a last-word
barrage sealed with a nuke.*
**Weapons:** `exp_heavyrocket` (40-rocket salvo, 2700).
- **a1 Cluster Warheads** (passive). Every 2nd rocket of a salvo splits on impact into `2→5` bomblets
  (`cort4armageddon_bomblet`, aoe 90). They scatter 150 and each deals `10%→25%` of the rocket. Cap: 60 bomblets
  per salvo.
  *FX:* each bomblet makes a small `flash` (radius 60, orange, ttl .2), and the weapondef carries a small CEG.
- **a2 Doom Painter** (active, `unit`, range 3200, cmd 36232). A painter laser holds the target for 4 s. It takes
  +`15%→40%` damage from all sources, and the next salvo homes on it (rockets retarget to neighbours if it dies).
  Cooldown `25→15` s.
  *AI:* an enemy hero, otherwise the most expensive enemy ≥ 3000 metal (defenses included) within range.
  *FX:* a red `beam` (width 2, pulse, ttl 4) from the head piece to the target. Under the target,
  `ring{kind="hex", 200→90, red, ttl 4}`.
- **a3 Retro Rockets** (active, `map`, range `500→900`, cmd 36233). Fires the tubes into the ground to leap. The
  takeoff spot burns for `3000→9000` in 300 and slows enemies 50% for 3 s. Cooldown `30→18` s.
  *AI:* escape when a non-artillery enemy is within 700 and HP < 70%. It leaps away from the enemy centroid,
  toward allies.
  *FX:* at takeoff, a `flash` of radius 300 and `ring{kind="shock", 50→300}`. In flight, `attach trail{smoke
  orange}`. On landing, `ring{shock, →150}`.
- **ult Armageddon Protocol** (active, `map`, range `3200→4200`, radius 700, cmd 36234). A 2 s warning, then 6 s of
  rocket rain: `24→60` rockets of `2500→4500` (aoe 200), then a tactical nuke of `15000→40000` (aoe 600).
  Cooldown `120→80` s.
  *AI:* the densest enemy metal cluster in range ≥ 20k metal (structures count ×0.5), or a group containing an
  enemy hero.
  *FX:* `ring{kind="rune", r 700, red .6, ttl 8}` slowly rotating, and a thin `pillar` (radius 40, height 2000,
  red, 2 s) as the designator. Each rocket hit adds a `flash` of radius 150. The nuke adds a `flash` of radius 900
  (white) and `ring{shock, 100→1100, ttl 1.2}`.

## 4. cort4vesuvius — Vesuvius, the Twin-Barrel (corves ×1.8) — NEW
*The human's "twin-barrel tank with a rocket launcher": a twin plasma cannon, two Banisher racks and a flamer.
When both barrels land together the target cracks, and when it digs in it turns the field into lava.*
**Weapons:** `corlevlr_weapon` (twin plasma cannon). Set `burst = 2, burstrate = 0.2` so the two `BarrelFlare1/2`
fire as a pair at the same DPS. Also `banisher` ×2 (`ban1`, `ban2`) and `flamethrower` (close defense).
Range ×1.2.
- **a1 Twin Impact** (passive). When both shells of a pair land within 150 of each other, they **resonate**:
  +`2500→8000` in 250, and the primary target gets *Shred*, +`5%→15%` damage taken for 5 s (stacks 3).
  *FX:* resonance is a `flash` of radius 200 (amber-white) and `ring{kind="hex", 60→250, amber, ttl .35}`. Each
  Shred stack is a small `ring{kind="rune", r 70+15*stack, dull red, ttl 5}`.
- **a2 Banisher Lock** (active, `unit`, range 1400, cmd 36242). Both racks ripple-fire `6→14` heavy missiles over
  2 s (`cort4vesuvius_salvo`), `2500→5000` each, aoe 128. They deal +50% to a target with Shred. Cooldown `18→12` s.
  *AI:* an enemy defense or structure first (siege role), then a hero, then the highest-cost unit.
  *FX:* a `flash` (radius 60) at `ban1Flare1/2` and `ban2Flare1/2` per launch, and `ring{kind="hex", 150→80, red,
  ttl 2}` on the target.
- **a3 Siege Mode** (active, `self`, toggle, cmd 36243). Deploys for up to `8→14` s: immobile, −20% damage taken,
  cannon range +`30%→60%`. While deployed the shells are swapped to `_magma` copies (`api.swapWeapons(..., "magma")`)
  that leave a lava pool for 4 s (radius 150, `500→1500`/s). Undeploying is instant. Cooldown 20 s, which starts
  on undeploy.
  *AI:* deploy when targets (structures or ≥ 2 units) sit beyond normal range but inside extended range and no
  enemy ground unit is within 600. Undeploy when an enemy is within 500 or HP < 40%.
  *FX:* `attach aura{pattern="heat", r 180, orange}` and a static `ring{kind="rune", r 220, amber}` while
  deployed. Each pool is a `flash` (radius 150, `{1,0.3,0,.5}`, ttl 4) plus `ring{kind="rune", r 150, ttl 4}`.
- **ult Eruption** (active, `map`, range 2400, radius 500, cmd 36244). Fires `5→12` volcanic bombs in a high arc
  over 3 s (`cort4vesuvius_volcanic`), `10000→18000` each, aoe 300. Each leaves a 6 s lava pool of
  `1500→3500`/s. A final ground eruption deals `20000→50000` in 450. Cooldown `120→85` s.
  *AI:* the densest cluster with ≥ 15k metal; structures count fully.
  *FX:* each impact is a `flash` of radius 300 and `ring{shock, 50→300}`. Pools are drawn as in Siege Mode. The
  eruption is a `pillar` (radius 220, height 1800, `{1,0.35,0.05,.9}`, ttl 1.5), `ring{shock, 100→700}`, and a
  `flash` of radius 600.

## 5. cort4printer — Printer, the Swarm Foundry (corprinter ×2.8) — NEW
*The human's "drone carrier": a mobile nano-foundry that prints attack drones and pop-up turrets, then sends its
drones to rebuild a dying ally.*
**Weapons:** the base unit has none. It gets a new `printer_disassembler` (BeamLaser, green nanolathe look, 750,
5k DPS counted by `heroBalance`). It keeps its build power for repair, but the altar decides whether it may
construct anything.
- **a1 Drone Bay** (passive). Keeps `2→8` attack drones (`cort4printer_drone`, a cordrone copy ×1.5: 10k HP,
  `400→600` DPS each, leash 900, `api.summon`). A lost drone is reprinted every `10→5` s. Drone damage counts as
  the hero's (XP, item dtype `laser`).
  *FX:* each print is a `pillar` at the door piece (radius 30, height 120, green, ttl .6). Each drone has
  `attach trail{green .5}` (cap 8).
- **a2 Print Turret** (active, `map`, range 900, cmd 36252). Prints a `cort4printer_turret` (corhllllt Quad
  Guard copy: `12k→40k` HP, `800→2500` DPS) that builds up over 1.5 s and lasts `20→40` s. Up to `2→3` turrets at
  a time. Cooldown `30→18` s.
  *AI:* a point 300 ahead of the army toward the nearest enemy cluster, or next to an ally hero under fire.
  *FX:* a `pillar` (radius 80, height 400, green, ttl 1.5) and `ring{kind="hex", 40→120, green, ttl 1.5}`. While
  it lives, `attach aura{pattern="runes", r 90, green .3}`. On expiry, a `flash` of radius 120.
- **a3 Repair Swarm** (active, `ally` or `self`, range 1000, cmd 36253). All drones fly to the ally for 8 s,
  healing it and allies within 300 for `1500→5000` HP/s in total (r10: 40k). The drones do not shoot meanwhile.
  Cooldown `25→15` s.
  *AI:* an ally hero first, then the most expensive ally, below 60% HP and taking damage within 1000; or self
  below 50%.
  *FX:* every 0.3 s, a green `beam` (width 4, ttl .3) from each drone to the target (like a nanolathe), plus
  `attach aura{pattern="heal", r 150, green}` on the target for 8 s.
- **ult Swarm Protocol** (active, `map`, range 1800, radius 450, cmd 36254). Prints `12→30` kamikaze micro-drones
  (`cort4printer_swarm`, a homing MissileLauncher with the cordrone model) in waves over 5 s, `4000→8000` each,
  aoe 120. Cooldown `110→80` s.
  *AI:* the densest enemy cluster ≥ 15k metal in range, or around an enemy hero.
  *FX:* `ring{kind="hex", r 450, green-white, ttl 5}` at the target. Each impact is a `flash` of radius 120
  (green-white). Each wave launch is a `pillar` at the hero (radius 60, height 300, green, ttl .4).

## 6. cort4commando — Commando, the Ghost (cormandot4 ×2.6) — NEW
*A cloaked saboteur: it disappears, mines the enemy's path, steps behind a target and disintegrates it, then
blacks out the whole fight with EMP.*
**Weapons:** `commando_back_cannon` (Disintegrator DGun, range ×2 → 500, counted) and `commando_stunner` (EMP
scattergun, paralyzer, not counted). The base unit has `cancloak`, so engine cloak is allowed.
- **a1 Ghost Protocol** (passive). Cloaks after `5→2.5` s without firing or being hit (decloak distance 50), with
  +`10%→30%` speed while cloaked. The first shot from cloak is an **Ambush**: +`50%→150%` damage and a stun of
  `0.5→2` s (heroes ½).
  *FX:* `attach cloak` while cloaked. On an Ambush hit, a cyan `flash` (radius 120) and `ring{kind="electric",
  40→160, ttl .3}` on the victim.
- **a2 Disruptor Mines** (active, `map`, range 700, cmd 36262). Scatters `3→8` hidden mines in 200 (max 16 on the
  map, 60 s each). An enemy within 120 sets one off: `2000→5000` in 180 + EMP `1.5→3` s. Cooldown `20→12` s.
  *AI:* at its own position when chased (an enemy within 500 and HP < 70%), otherwise 300 ahead on the nearest
  enemy group's movement vector.
  *FX:* each mine is a faint `ring{kind="electric", r 50, cyan .25}`, visible **to allies only**. When one goes
  off, a `flash` of radius 180 (cyan), `ring{electric, 40→180, ttl .4}`, and 4 short `bolt`s.
- **a3 Shadowstep** (active, `unit` enemy, range `700→1100`, cmd 36263). Blinks behind the target and fires the
  disintegrator point-blank for `8000→24000`. The target is *Marked* for 5 s: +`10%→25%` damage from the Commando.
  From cloak it counts as an Ambush. Cooldown `18→10` s.
  *AI:* the enemy hero with the lowest HP fraction, otherwise a high-value back-line unit (artillery, AA,
  constructor). Only if ≤ 2 enemy combat units ≥ 1000 metal stand within 500 of the target, or the hero's HP
  is > 60%.
  *FX:* a cyan `bolt` from start to end (width 6, branches 0, ttl .15) as the slipstream. A `flash` of radius 120
  at both ends and `ring{kind="electric", 60→200}` on arrival. On the target, `ring{kind="hex", r 70, cyan, ttl 5}`
  for the mark.
- **ult Blackout** (active, `map`, range 1500, radius `600→900`, cmd 36264). An EMP storm deals `10000→25000` to
  every enemy inside and stuns `3→6` s (heroes ½). Enemy shields in the area drop to 0. Enemies lose sight of the
  Commando for the stun + 3 s, and it deals +50% to stunned targets. Cooldown `120→80` s.
  *AI:* a cluster containing an enemy hero, or ≥ 15k metal, when HP > 40%. Follow up with Shadowstep onto that
  hero.
  *FX:* `ring{kind="electric", 100→R, cyan .9, ttl .6}` and a `flash` of radius R (white-cyan, .4 s). Every
  0.5 s during the stun, a `bolt` from y+600 to up to 12 stunned units (ttl .25), and `attach electric{cyan, .6}`
  on stunned units (cap 20).

## 7. cort4deadeye — Deadeye, the Marksman (cordeadeye ×2.8) — NEW
*A four-legged long gun. It focuses one big target until its bolts punch through, picks the moment, and ends heroes
with one shot.*
**Weapons:** `cor_burst_laser` (3-bolt heavy blaster). Range ×2.2 → 1870, with `reloadtime` 12 → 6 so a volley
is not a 100k alpha strike.
- **a1 Focus** (passive). Each volley that hits the same target as the last one adds a Focus stack (max 5),
  +`6%→15%` damage per stack. Switching targets resets the stacks. At 5 stacks the next volley **penetrates**:
  the bolts pierce a 1200 line and hit everything on it at full damage. Targets with ≥ 50k max HP take +10%.
  *FX:* `ring{kind="hex", r 60+15*stack, red, ttl=reload}` around the target, re-emitted each volley. A
  penetrating volley draws a `beam` 1200 long along the line (width 16, core white, red, ttl .25) and a `flash` of
  radius 100 on each pierced unit.
- **a2 Recon Flare** (active, `map`, range 2400, cmd 36272). Fires a flare that reveals radius `600→1000` for
  `8→15` s (a spotter summon) and decloaks units inside. Enemies inside are *Exposed*: +`8%→20%` damage taken from
  all sources. Cooldown `25→15` s.
  *AI:* the highest-value enemy radar blip in range that is not in LOS; otherwise the cluster in front of the army.
  *FX:* a `pillar` (radius 25, height 600, red, ttl=duration) and `ring{kind="rune", r=R, red .3, ttl=duration}`.
  A `flash` of radius 140 pulses every 1 s at the flare. Exposed enemies get `ring{kind="hex", r 50, red}`.
- **a3 Tumble** (active, `map`, range `350→600`, cmd 36273). A quick evasive hop. The weapon reloads instantly and
  the next volley within 3 s deals +`20%→60%`. Cooldown `16→9` s.
  *AI:* hop toward allies when a non-artillery enemy is within 600 or HP fell 10% in 2 s. Also hop in place to
  refire when a hero or ≥ 5k-metal target is in range and the reload has ≥ 3 s left.
  *FX:* `attach trail{red-white}` for 0.4 s and `ring{shock, 30→120}` at departure. `attach electric{red, .4}`
  until the charged volley fires.
- **ult Kill Shot** (active, `unit`, range `3000→4500`, cmd 36274). Channels 2 s (immobile; the laser sight is
  visible to everyone), then fires a rail round for `40000→90000` + `8%→20%` of the target's max HP (cap +60k).
  It pierces its line (others take 50%). If it kills the target, 50% of the cooldown is refunded. Cooldown
  `100→60` s.
  *AI:* an enemy hero whose current HP ≤ the estimated damage (a finisher), otherwise the enemy with the highest
  cost × missing HP. Requires HP > 50% and no enemy within 800.
  *FX:* during the channel, a red `beam` (width 3, pulse, ttl 2) from the muzzle to the target and
  `ring{kind="hex", 200→60, red, ttl 2}`. The shot is a `beam` (width 30, core white, red-orange, ttl .4), a
  `flash` of radius 200 at the muzzle, a `flash` of radius 160 on each hit, and `ring{shock, 50→400}` at the target.

## 8. cort4karganeth — Karganeth, the Hydra (corkarganetht4 ×1.8) — NEW
*An all-terrain missile crab: it locks many targets at once, swats aircraft, shoots incoming shells out of the sky
and adapts its plating to what hurts it.*
**Weapons:** `super_missile` (1050, counted) and `karg_shoulder` (AA, VTOL only, 1470). The AA damage is only
`vtol`, so the `heroBalance` multiplier skips it: set its `damage.vtol` explicitly (about 9000) and `reloadtime`
to about 2.
- **a1 Hydra Lock** (passive). Every `4→2` s the shoulder pods fire one micro-missile (`cort4karganeth_hydra`,
  homing, targets air and ground) at each of up to `2→8` *different* enemies within 1300. Each deals `800→2000`,
  doubled against aircraft.
  *FX:* before each volley, a red lock-line `beam` (width 2, ttl .3) from the turret to each target. Each impact is
  a `flash` of radius 70 (orange).
- **a2 Flak Canopy** (active, `self`, radius `700→1100`, 8 s, cmd 36282). Shoots down `1→3` enemy shells, rockets
  or bombs per second that would land within the radius (not beams, not strategic nukes). AA damage is
  +`50%→150%` meanwhile. Cooldown `35→22` s.
  *AI:* ≥ 3 enemy aircraft within 1500, or ≥ 3 hostile projectiles inbound into the radius (artillery, Armageddon
  and Starfall-style salvos), or a tactical nuke inbound.
  *FX:* `attach sphere{r=R, hex=true, color {1,0.4,0.15,.25}, fresnel}`. Each intercept is a red `beam` (width 4,
  ttl .15) from the turret to the projectile, a `flash` of radius 90 there, and `GG.HeroFX.hit` on the sphere.
- **a3 Adaptive Plating** (passive). After 3 hits of one damage type (`H.damageType`) within 4 s, Karganeth takes
  −`10%→30%` from that type for 10 s. Up to 2 types are adapted at once; a new one replaces the oldest.
  *FX:* on adapting, `attach sphere{r body, hex, ttl .6}` flickers in the type's color (electric cyan, laser
  red, plasma amber, rocket orange, flame yellow, rail white, emp violet), and a small `ring{hex}` at the feet.
- **ult Hydra Unleashed** (active, `self`, transformation, `8→12` s, cmd 36284). Karganeth grows to ×1.2, gets +30%
  speed, and every 1 s fires a lock volley at up to `4→10` targets within 1300 for `800→1600` each (air ×2).
  Its own weapons keep firing. Cooldown `110→80` s.
  *AI:* ≥ 6 enemies or ≥ 3 aircraft within 1300.
  *FX:* `setScale` ×1.2, `attach electric{red-orange, .8}`, and `attach aura{pattern="runes", r 300, red}`. Each
  volley uses the lock-line `beam`s.

## 9. cort4cataphract — Cataphract, the Lancer (corsok ×2.0) — NEW
*A hover lancer that skims water and land, charges through the line, locks one target down with disruptor bolts and
chains lance strikes across a battlefield.*
**Weapons:** `corsok_laser` (Disruptor Bolt; range ×1.4 → 1015) and `depthcharge` (anti-sub). Put `depthcharge` in
`heroBalance.alt` so it does not dilute the DPS on land.
- **a1 Lance Charge** (active, `map`, range `800→1300` (+30% over water), cmd 36291). Boosts at 4× speed. Enemies
  on the path take `4000→12000` and are knocked aside 150. The next disruptor bolt fires immediately at
  +`30%→80%`. Cooldown `18→10` s.
  *AI:* a back-line target (artillery, AA, constructor, or a hero below 50% HP) 600–1300 away; escape toward
  allies at HP < 35%.
  *FX:* `attach trail{amber, width 90}` for the dash, plus `ring{kind="shock", 60→150}` at the bow every 0.2 s. A
  `flash` of radius 120 on each ram.
- **a2 Disruption** (passive). Each bolt hit adds a Disruption stack (max `3→6`, 4 s): −8% speed per stack. At max
  stacks the target is EMP-stunned `1→2.5` s (heroes ½) and the stacks reset.
  *FX:* `ring{kind="electric", r 40+10*stack, amber}` under the target. At max, 3 cyan `bolt`s around the target
  (ttl .3) and a `flash` of radius 100.
- **a3 Phase Decoy** (active, `self`, cmd 36293). Leaves a hologram (`cort4cataphract_decoy`: same model,
  `15%→40%` of hero HP, 6 s; enemies within 800 are taunted onto it). The Cataphract cloaks for 2 s with +50%
  speed for 4 s. The decoy explodes on death or expiry for `3000→10000` in 250. Cooldown `28→16` s.
  *AI:* HP < 50% under fire from ≥ 3 enemies, or when it is the target of an enemy ult channel (Kill Shot and
  similar).
  *FX:* a `flash` of radius 120 (white-amber) and `ring{kind="hex", 60→160}` where the decoy appears, with
  `attach cloak` on the hero. The decoy's explosion is a `flash` of radius 250 and `ring{shock, →250}`.
- **ult Lancer's Gauntlet** (active, `unit` or `self`, cmd 36294). Chains `3→7` lance dashes (0.4 s each). Each
  goes to the highest-value enemy within 900 of the current spot that has not been hit yet, and deals
  `12000→30000` + max Disruption. The hero is untargetable during the chain and ends at the last target.
  Cooldown `100→70` s.
  *AI:* ≥ 3 enemies within 900 worth ≥ 10k together, or an enemy hero within 900 below 50% HP.
  *FX:* each dash is a `bolt` from start to end (width 20, amber-white, branches 2, ttl .3) plus a `flash` of
  radius 200 on the hit. At the end, `GG.HeroFX.chain(all points, {color amber .5, ttl .6})` and `ring{shock,
  →600}`.

---

## API needs (not in SPEC §4; ask core)
1. **`api.leap(unitID, h, x, z, seconds, opts)` / `api.dash(unitID, h, x, z, speed, opts)`**: MoveCtrl movement
   with a ballistic or flat path, `onLand` / `onStep(x, z)` callbacks for path damage, and `opts.untargetable`.
   Used by Colossus (ult), Armageddon (a3), Hellwalker (a2), Cataphract (a1, ult) and Deadeye (a3). One helper,
   many users.
2. **`api.blink(unitID, x, z)`**: a teleport with ground snap and a pathability check (Commando a3).
3. **`api.throw(victimID, x, z, seconds, onLand)`** and **`api.pull/push(victimID, x, z, dist, seconds)`**: move
   an *enemy* unit. Heroes get ½ distance; buildings are immune (Colossus a1, Hellwalker a3, Cataphract knockback).
4. **`api.downed(unitID, h, seconds, onRise)`**: invulnerable, untargetable (neutral and dropped from target
   lists), stunned, weapons off, the model slumped (piece tilt). Juggernaut's ult. Core's `dying` must allow a
   hook that returns `true` to start it.
5. **Enemy debuffs with stacks**: `api.mark(uid, id, seconds, {stacks=, max=, vuln=, slow=, root=, from=})`,
   `api.marks(uid, id)`. Vulnerability (damage taken +x%, optionally only from `from`) must be applied in core's
   `UnitPreDamaged`. Users: Doom Painter, Shred, Exposed, Commando Mark, Fault, Heat, Disruption.
6. **`api.slow(uid, frac, seconds)` / root on enemies**, heroes ½ (via MoveCtrl/`SetGroundMoveTypeData` speed).
7. **`api.taunt(victimID, heroID|decoyID, seconds)`**: forced `SetUnitTarget` that re-asserts every 0.5 s; heroes
   ½ (Warcry, Phase Decoy).
8. **`api.piecePos(unitID, pieceName)`** for FX and `api.fire` muzzles (BarrelFlare1/2, ban1Flare1…, flare1–4,
   door), plus **`api.turretSpin(unitID, piece, degPerSec, seconds)`** to drive the turret (a COB call or piece
   override while the weapons hold) for Circle Beam.
9. **`api.reloadNow(unitID, weaponNum)`** (Tumble, Lance Charge) and a per-hero "next shot ×m" in the `hit` hook,
   which the module can track itself.
10. **`api.intercept(x, z, r, ally, maxCount)`**: delete enemy ballistic or missile projectiles heading into a
    radius and return their positions. Exclude beams, lightning, and nukes with `targetable` (Flak Canopy).
11. **Summons**: `opts.owner` credit, so summon damage counts as the hero's (XP, dtype); `opts.build = seconds`
    (spawn as a nanoframe and finish it, the print effect); `opts.cap` (max alive); summons give no XP or loot to
    the enemy (Printer drones and turrets, the decoy, the spotter).
12. **`api.reveal(x, z, r, seconds, ally)`**: a sight-only, untargetable spotter that also decloaks
    (`Spring.SetUnitCloak` on enemies inside), for Recon Flare. An invisible `cort4deadeye_flare` unitdef is fine.
13. **FX visibility `opts.visible = "ally"`** for hidden things (Commando mines). SPEC §5 only does LOS.
14. **Engine cloak for heroes whose base has `cancloak`** (Commando): `api.buff{cloak=true}` should use the engine
    cloak (`SetUnitCloak`) when the unitdef allows it, and LOS masks otherwise.
15. **Shields off**: `api.shieldDrain(uid)` (Blackout); `Spring.SetUnitShieldState` on enemies in the area.
16. **Damage by type for a3 Adaptive Plating**: the `damaged` hook needs `weaponDefID` → `H.damageType` exposed as
    `api.damageType(weaponDefID)`.
17. Chain-tracking helpers used by Hellwalker's Combustion: per-victim counters keyed by `unitID` that clear on
    `UnitDestroyed` (or a `victimDestroyed` hook in the module).

Needs from core (not API): new movedefs **`T4HOVER8`** (HHOVER4 at footprint 8, `CRUSH.MAXIMUM`) and optionally
**`T4ATBOT9`** (T4TBOT9 with `maxwaterdepth = DEPTH.AMPHIBIOUS`, so Karganeth stays amphibious like its base). New
`T4.heroBalance` rows for the six new heroes (table above), `cort4gant.buildoptions` with all 10, and
`T4.heroBalance.cort4cataphract.alt = { depthcharge = true }`.

## New weapondefs / unitdefs (content-cor, in `cort4units.lua` via `T4.hero(ud, fx, extra)`)
| Key | From | Purpose |
|---|---|---|
| `cort4bastion_powershot` | `T4.weaponFrom(juggernaut_fire)` (Cannon, vel 1400 if DGun can't be spawned) | Power Shot shells (damage via api) |
| `cort4bastion_reactive` | `T4.weaponFrom(cor_gol @ corgol, {damage=1, aoe=120, size .6})` | Reactive Armor shell |
| `cort4hellwalker_meteor` | the existing kit meteor (`hero_ab_meteor`) | Hell on Earth meteors |
| `cort4armageddon_bomblet` | small Cannon (aoe 90, model none, orange CEG) | Cluster Warheads |
| `cort4armageddon_rain` / `_nuke` | `T4.missileWeapon` / `T4.nukeWeapon` | Armageddon Protocol |
| `cort4vesuvius_salvo` | `T4.weaponFrom(banisher)` (homing, `tracks`) | Banisher Lock |
| `corlevlr_weapon_magma` | a copy of `corlevlr_weapon` (+range, orange fire trail) | Siege Mode `swapWeapons("magma")` |
| `cort4vesuvius_volcanic` | `corlevlr_weapon` ×1.5 size, high arc, fire `cegtag` | Eruption bombs |
| `printer_disassembler` | new BeamLaser (750, green, thickness 6) | Printer's main gun |
| `cort4printer_swarm` | `T4.missileWeapon{model="cordrone.s3o"}` | Swarm Protocol |
| `cort4deadeye_killshot` | a visual rail (LaserCannon, 0 damage) | Kill Shot tracer under the FX beam |
| `cort4karganeth_hydra` | `T4.missileWeapon{model="corkbmissl1.s3o"}`, air+ground | Hydra Lock / Unleashed |
| unitdef `cort4printer_drone` | `cordrone` ×1.5, HP 10k, no cost/wreck, `customparams.t4_summon` | Drone Bay |
| unitdef `cort4printer_turret` | `corhllllt` ×1.5, no cost/wreck | Print Turret |
| unitdef `cort4cataphract_decoy` | the hero model, no weapons, `t4_summon` | Phase Decoy |
| unitdef `cort4deadeye_flare` | an invisible sight-only dummy (no model, neutral, stealth) | Recon Flare |

Models to build (`tools/t4/build_models.py`): `cort4vesuvius` (corves ×1.8), `cort4printer` (corprinter ×2.8),
`cort4commando` (cormandot4 ×2.6), `cort4deadeye` (cordeadeye ×2.8), `cort4karganeth` (corkarganetht4 ×1.8) and
`cort4cataphract` (corsok ×2.0), each with its `_dead`. Juggernaut keeps footprint 11, speed 28 → 30.
