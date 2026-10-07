# v19 heroes — the shared spec (orchestrator contract)

Branch `v19-heroes` of `denysfast/bar-game` (base: `custom` @ custom-v18). Every agent works in its own
worktree on its own branch cut from `v19-heroes`, owns only the files listed for it, and is merged by the
orchestrator. If you need a change in a file you do not own, write it down in your report ("needs from core: …")
instead of editing it. Read `CUSTOM.md` (section "T4-герои") for the current (v18) system — v19 replaces most
of it.

Testing kit on .142: `/mnt/data/bar-bench` (see `bench.sh`: `W=<your worktree> WD=<your private name>
bench.sh <scene.lua> <tag>`; full `spring` under Xvfb + llvmpipe, screenshots, infolog). Scene gadget/widget:
`/mnt/data/bar-bench/scene/zz_hero_scene*.lua`, examples `scene/*.lua`. Copy the kit into your own scene files,
never edit the shared ones. llvmpipe: put `SoftParticles = 0` in your write-dir springsettings. Never edit game
files while your own run is going (BAR reloads gadgets live).

## 1. What the human asked (verbatim intent)

1. Long-range T4 heroes deal 3–4x too much damage, very visible with level — find the bug, fix it.
2. Every hero: exactly **4 abilities** = 3 normal + 1 ultimate; 1–3 passives and 1–3 actives (4 in total).
   Every ability has **10 ranks**. Normal ability rank r needs hero level `r == 1 and 1 or 3*(r-1)`
   (1, 3, 6, 9 … 27). Ultimate rank r needs level `10*r` (10 … 100).
3. Effects of abilities are made with **shaders and code**, not sprites (CEGs of flat sprites looked bad).
   Beautiful and impressive.
4. **Stats**, the same five for every hero with the same icons: HP + regen; speed + vision; damage; range;
   splash + penetration. Damage and range apply to **all** weapons of the hero at once (the v14–v18 per-weapon
   trees are gone).
5. **Items like Diablo**: blue = magic (1–2 random affixes), yellow = rare (2–3 random affixes), brown/gold =
   unique (1–2 unique powers with random values + 1–3 random affixes), green = set (set bonuses when the hero
   wears several pieces). Item levels 1–5. Damage-type bonuses (electric, plasma shells, rockets, lasers …).
   Items can be salvaged into metal. Every faction gets a **shop building** selling item levels 1–3, icons in
   the faction's style.
6. A team can have at most **3 heroes**. A dead hero cannot be replaced — only revived. Hiring the 2nd hero needs
   an altar (T4 forge) upgrade, the 3rd another one; each upgrade costs 2x the previous one.
7. **10 heroes per faction**, models and ideas from the gantry / scavenger / additional units (e.g. a drone
   carrier, a twin-barrel tank with a rocket launcher). The 4 current heroes of each faction are redone too.
8. Concepts given by the human (the rest by analogy):
   - **Thor** (Armada, `armthor` model; today `armt4zeus`) — electric tank, slow, armoured, great against medium
     targets, weaker vs single big ones. (1) passive Chain Lightning: the hit jumps to 1–10 units (by rank), jump
     range grows with rank, each next target takes **+5%** more damage than the previous; (2) EMP Missile becomes
     an active: power and stun time grow, stuns heroes too; (3) Electro-Devour: eats one of its own non-hero units
     with a special electric strike and heals a % of the eaten unit's HP (50% at rank 1 … 200% at rank 10);
     (4) ult Rage Mode: the tank grows in size, covered in red electricity, +speed, +turn rate (hull and turret),
     an electric orb darts above it with the tank's damage and 2x range; tank and orb shoot red lightning.
   - **Juggernaut** (Cortex, `corjugg`; today `cort4bastion`) — heavy killer tank that gets up after death.
     (1) Power Shot: pick a target, a fast series of its heavy cannon shots; range, damage and shot count (4 at
     rank 1 → 8 at rank 10) grow; (2) Circle Beam: stops for 3 s and sweeps a full circle with a twin laser,
     burning everything around; splash and damage grow; (3) passive Reactive Armor: when hit, plasma fires back
     from its armour (chance to retaliate); (4) ult Resurrection: rises after death; rank lowers the cooldown.
   - **Razor** (Armada, `armraz`; today `armt4aegis`) — very fast mobile laser assassin / ganker with stealth.
     (1) Cloak + walk speed; (2) Shield: permanent shield, ranks grow capacity and regen; (3) Overcharge: while
     on, faster attack, costs HP per second; (4) ult Drones: permanent passive drones circling it with red lasers
     (like the Legion drone carrier).

## 2. Progression (core)

- `H.MAX_LEVEL = 100`. One point per level. Hero level 1 starts with 1 point.
- Branches: `a1`, `a2`, `a3`, `ult` (abilities, 10 ranks each) and five stats `vit`, `mob`, `dmg`, `rng`, `imp`.
  Hotkeys Q / W / E / R for a1 / a2 / a3 / ult.
- Stats (same for all heroes, icons `bitmaps/t4heroes/stat_<key>.png`), 15 ranks each, rank r needs level r,
  values per rank as shares of the hero's **base** stat (shown in units in the UI):
  | key | name | per rank |
  |---|---|---|
  | `vit` | Vitality | +5% base HP, +0.025% base HP per second regen |
  | `mob` | Mobility | +3% base speed, +4% base sight |
  | `dmg` | Firepower | +5% damage, all weapons |
  | `rng` | Reach | +3% range, all weapons |
  | `imp` | Impact | +6% splash radius (area of effect), +3% penetration |
  Penetration: that share of a hit's damage also hits enemies on a line behind the target (length 600 * hero fx
  scale); for weapons without splash it is the main area bonus.
- 4 abilities x 10 + 5 stats x 15 = 115 ranks for 100 points: a maxed hero still leaves something out.
- Metal per rank (team storage, paid on learn): ability `5000 * r`, ult `12000 * r`, stat `2500 * r`.
- Automatic growth per level: HP +3%, damage **+1.5%** (was 3%; tune after the damage bug fix).
- Ability values are per rank: a number, a 10-array, or `H.lin(a, b)` (rank 1 = a, rank 10 = b, linear).
  Ability damage/heal/absorb also grows with hero level by `H.ABILITY_POWER_PER_LEVEL` (1%/level).

## 3. Hero cap, altar upgrades

- At most 3 heroes per team (alive or dead — a dead hero keeps its slot until revived). Each hero type once.
- Slot 1 comes with the altar. Slot 2 needs **Altar Upgrade I** (100k metal, 1M energy), slot 3 needs **Altar
  Upgrade II** (200k metal, 2M energy). Upgrades are a command on the altar (instant payment, 45 s research, the
  altar cannot build meanwhile); state in team rules param `hero_slots` (1..3), `hero_slots_research` (frame).
  Losing the altar does not lose the upgrades.
- When the slots are full the altar's hero build options are disabled (`EditUnitCmdDesc` disabled + reason);
  revive of a dead hero is still offered.

## 4. The ability module API (core owns, content uses)

Ability data lives in `luarules/configs/heroes/<faction>.lua` (one file per faction, returns `defs, order`, gets
`H` as `...`). An ability def:

```lua
a1 = { name = "Chain Lightning", passive = true, kind = "custom",           -- or a generic kit kind
       icon = "ab_armt4thor_a1", desc = "...", text = function(r, H) return "..." end, -- or text = { 10 strings }
       -- actives: cmd = <unique id 36101..36499>, action = "hero_<name>", target = "unit"|"map"|"ally"|"self",
       --          range = <per rank>, cooldown = <per rank>
       jumps = H.lin(1, 10), jumpRange = H.lin(300, 750), stepBonus = 0.05, ... }
```

Hero behaviour code: `luarules/heroes/<heroname>.lua` (NOT under luarules/gadgets — not auto-loaded), loaded by the
core gadget with `VFS.Include(path, nil, VFS.ZIP_FIRST)`; returns a table of optional synced hooks. All hooks get
`api` (below), `unitID`, `h` (hero state: `h.level`, `h.def`, `h.team`, `h.ally`, `h.mods`, `h.store` — a private
table the module may use):

```lua
return {
  init      = function(api, unitID, h) end,                         -- hero finished / revived
  rank      = function(api, unitID, h, key, rank) end,              -- a rank was learned
  frame     = function(api, unitID, h, f) end,                      -- every 3 frames while alive
  cast      = function(api, unitID, h, key, rank, x, y, z, targetID) return true end, -- active used (true = cast happened, cooldown starts)
  autocast  = function(api, unitID, h, key, rank) return x, y, z, targetID end, -- AI / autocast picks a target, nil = not now
  hit       = function(api, unitID, h, victimID, victimDefID, damage, weaponDefID, isParalyzer) return damage end, -- the hero's weapon hits (UnitPreDamaged, after core multipliers)
  damaged   = function(api, unitID, h, damage, attackerID, weaponDefID, isParalyzer) return damage end,      -- the hero is hit
  dying     = function(api, unitID, h) return false end,            -- true = core keeps it alive (resurrection ults); called from UnitPreDamaged when damage would kill
  destroyed = function(api, unitID, h) end,
  projectile= function(api, unitID, h, proID, weaponDefID) end,     -- one of the hero's projectiles was created
}
```

`api` (core implements, synced; "rank value" = `api.val(def.field, rank)`):
- `val(v, r)`, `rank(h, key)`, `level(h)`, `power(h)` (ability power multiplier), `frame()`.
- `damage(victimID, dmg, attackerID, opts)` — opts `{ para = seconds, dtype = "electric"|..., noHero = bool }`;
  ability damage, counts as the hero's (XP, items' damage-type bonuses), never hits allies.
- `area(x, z, r, dmg, attackerID, opts)`, `stun(uid, seconds, attackerID)` (works on heroes; heroes take 50% of
  the time), `heal(uid, hp)`, `enemiesIn(x, z, r, ally)`, `alliesIn(x, z, r, ally)`, `nearestEnemies(x, z, r, ally, n)`.
- `buff(unitID, h, id, seconds, mods)` / `unbuff(unitID, h, id)` — timed stat mods merged into the hero's stats
  (`damage, reload, speed, turn, range, armor, regen, immobile, cloak, scale`); `seconds = nil` = until unbuff.
- `setScale(unitID, s)` — visual model scale (root piece matrix) — used by Rage Mode.
- `fire(h, weaponName, fromX, fromY, fromZ, targetID | x, y, z, opts)` — spawn one of the hero's extra weapondefs
  (`<hero>_<key>`), damage applied through the kit's impact path.
- `swapWeapons(unitID, h, suffix | nil)` — while set, the hero's projectiles are replaced by the `<key>_<suffix>`
  copies made in the unitdef (e.g. red lightning during Rage Mode).
- `summon(unitID, h, unitName, count, opts)` → unitIDs (drones; `opts.leash`, `opts.expire`).
- `fx` = `GG.HeroFX` (section 5), `ceg(name, x, y, z)`, `log(fmt, ...)`.
- `cooldown(unitID, h, key, seconds)`, `ready(h, key)`, `active(unitID, key, seconds)` (UI "on" marker).
The generic kit kinds of v15–v18 stay available (values now 10 ranks long) so simple abilities need no module.

## 5. FX library (fx agent owns): `GG.HeroFX`

Shader-based effects, instanced GL4 drawing in an unsynced gadget (`luarules/gadgets/fx_t4_heroes.lua` +
`luarules/gadgets/include/heroes_fx/*` / `shaders/GLSL/heroes/*`). Callable from **synced** code (it forwards
through SendToUnsynced) and from unsynced code. Everything respects LOS (drawn only where the local player sees,
specs see all). All positions are world elmos; colors `{r,g,b,a}` 0..1; `ttl` in seconds.

```lua
GG.HeroFX.bolt(x1,y1,z1, x2,y2,z2, { color=, width=, ttl=, branches=, seed=, jitter= })   -- jagged lightning + glow
GG.HeroFX.chain(points, opts)                    -- {x,y,z, x,y,z, ...}: a chain of bolts hop to hop
GG.HeroFX.beam(x1,y1,z1, x2,y2,z2, { color=, width=, ttl=, core=, pulse= })               -- laser with hot core + glow
GG.HeroFX.ring(x, z, { r0=, r1=, color=, ttl=, width=, kind = "shock"|"rune"|"hex"|"electric" })  -- ground ring
GG.HeroFX.flash(x, y, z, { radius=, color=, ttl= })   -- volumetric-looking glow burst
GG.HeroFX.pillar(x, z, { radius=, height=, color=, ttl= })                                -- light column
id = GG.HeroFX.attach(unitID, kind, opts)   -- persistent until detach / opts.ttl:
     "aura"   ground disc around the unit (opts.radius, color, pattern = "electric"|"heat"|"heal"|"runes")
     "sphere" shield bubble (opts.radius, color, hex = bool, fresnel) — opts.hit(x,y,z) ripples
     "electric" arcs crawling over the unit's body (opts.color, intensity) — e.g. Rage Mode red electricity
     "orb"    a floating energy orb (opts.color, radius, height, orbit, speed); its position is a pure function
              GG.HeroFX.orbPos(unitID, opts, frame) -> x,y,z usable in synced code too (bolts start there)
     "cloak"  refraction shimmer while cloaked (owner/allies see a faint outline)
     "trail"  glowing trail behind a fast unit
GG.HeroFX.detach(id)
GG.HeroFX.hit(id, x, y, z)                  -- ripple on a sphere
```

## 6. Items (items agent owns): Diablo-style

- Data: `luarules/configs/t4_hero_items.lua` (rewritten): base types per category (weapon / defense / utility,
  3 slots each, 9 slots), affix pool (prefix/suffix names, Diablo-style: "Charged Capacitor of the Storm"),
  uniques, sets with 2/3/4-piece bonuses, rarity table (colors: magic `#6969FF`, rare `#FFFF64`, unique
  `#C7B377`, set `#00FF00`), item level 1–5 scaling the affix ranges.
- Affixes (stat keys the core understands, added to `h.mods`): `hp`, `regen` (HP/s), `armor` (fraction), `speed`,
  `sight` (elmos), `damage` (fraction, all weapons), `range` (fraction), `splash`, `pierce` (fractions),
  `dtype = { electric, plasma, rocket, laser, flame, rail, emp }` (fraction bonus to that damage type), `power`
  (ability power), `cdr`, `crit` (chance), `critMult`, `lifesteal`, `thorns`, `xp`, `income` (metal/s).
  Uniques/sets add named special powers implemented in the items gadget through the same hooks as abilities.
- Damage types: core classifies every weapondef once (`H.damageType(wd)`): LightningCannon / names with
  lightning|thunder → electric; paralyzer → emp; BeamLaser/LaserCannon → laser; Flame → flame; MissileLauncher /
  StarburstLauncher / names with rocket|missile → rocket; rail/sniper → rail; other Cannon → plasma.
- An item instance is a rolled record `{ base, ilvl, rarity, affixes = {{id, value}...}, unique|set id, seed }`,
  serialised into rules params as a compact string; the team stash (36) and hero slots hold instances.
- Salvage: any stash item → metal (`rarity x ilvl` table). Protocol `t4hero:salvage:<teamStashIndex>`.
- Shop: one building per faction (`armt4shop`, `cort4shop`, `legt4shop`), built by T2 constructors; a shelf of
  9 rolled items (3 per category) of the shop's faction; buy for metal into the team stash. v24: the shelf is rerolled
  at a refresh level 1..5 (`I.SHOP_LEVELS`, 25k..1M metal; level = highest ilvl, sets/uniques from level 2, only the
  faction's own); the free 3-minute refresh is level 1. Icons: one per base type per faction (faction palette),
  uniques/sets their own.
- Drops (as v15): heroes and big units killed by heroes; ilvl from the victim (cost / hero level); rarity odds
  magic 60 / rare 28 / set 6 / unique 6, rarer with higher ilvl.
- Hooks for core (items gadget `luarules/gadgets/unit_t4_hero_items.lua` publishes `GG.T4HeroItems`):
  `mods(unitID, h, m)` adds the equipped affixes/sets into `m`; `hit`, `damaged`, `dying`, `frame` like the
  ability hooks; `onHeroDeath(unitID, h, x, z)`; `onKill(heroID, victimID, victimDefID)` (drops).

## 7. Ownership

| Agent | Owns |
|---|---|
| dmgfix | investigation + the minimal fix (reports the root cause; core merges the formula changes) |
| core | `luarules/gadgets/unit_t4_heroes.lua`, `luarules/configs/t4_heroes.lua`, `luarules/configs/t4_hero_weapons.lua`, the API, altar upgrades, `gamedata/custom_t4.lua` (hero helpers) |
| fx | `luarules/gadgets/fx_t4_heroes.lua`, its includes and shaders, a showcase scene |
| items | `luarules/configs/t4_hero_items.lua`, `luarules/gadgets/unit_t4_hero_items.lua`, shop unitdefs (`units/*T4*/*shop*` or a new file), item icons |
| design-arm/cor/leg | `doc/v19-heroes/roster_<faction>.md` (wave 1, design only) |
| content-arm/cor/leg | `luarules/configs/heroes/<faction>.lua`, `luarules/heroes/<hero>.lua`, `units/*T4*/<faction>t4units.lua`, models, portraits, ability icons (wave 2) |
| ui | `luaui/Widgets/gui_t4_heroes.lua` (+ new widgets) (wave 2) |
| ai | AI hero picks, upgrades, learning, item buying (wave 2) |

## 4b. API additions requested from core (wave 1 designers; core implements, exact signatures in the header of unit_t4_heroes.lua once landed)

Movement: `api.dash(unitID, h, x, z, {seconds|speed, arc, untargetable, onStep, onLand})`, `api.blink(unitID, x, z)`,
`api.push/pull/throw` (enemy units; heroes half; buildings immune), `api.orbitAround(unitID, h, targetID, radius, seconds)`.
Debuffs: `api.mark(uid, id, seconds, {stacks, max, vuln, from, slow, root, reveal})`, `api.marks(uid, id)`,
`api.slow(uid, frac, seconds)`, `api.unitBuff(uid, id, seconds, mods)` (non-hero allies), `api.taunt(victimID, byID, seconds)`,
`api.forceTarget(unitID, targetID, seconds)`. Buff mods also `unstoppable`, `reflect`, `hidden` (burrow), `turretTurn`.
Hooks also: `impact(api, unitID, h, weaponDefID, x, y, z, projectileID)`, `fired(api, unitID, h, weaponNum)`,
`unitDied(api, unitID, h, deadID, deadDefID, x, z, allied)` (deaths within ~1500), `damaged` gets the attacker position.
Helpers: `api.line`, `api.target`, `api.reloadNow`, `api.piecePos`, `api.turretSpin`, `api.consume(uid, {credit})`,
`api.reveal`, `api.intercept`, `api.shieldDrain`, `api.damageType`, `api.downed(unitID, h, seconds, onRise)`.
Summon opts: owner credit, `respawn={max, every}`, `guard`, `cap`, `build`, `expire`, `leash`, `scaleWithLevel`; `api.order`.
Toggle actives: ability `toggle = true`. Absorb params `hero_absorb`, `hero_absorb_max`. Never spawn/copy StarburstLauncher.
Movedefs: T4ATANK8, T4HOVER8, T4HOVER10, T4ATBOT9. Ability command ids: Armada 36101–36199, Cortex 36201–36299,
Legion 36301–36399, core ≥ 36400.
Damage rules (dmgfix findings): heroes keep 0 engine experience; on-hit extras once per projectile; splash grows AREA
(radius × sqrt(1 + bonus)); Firepower and items are pure damage (no salvo/pellets/reload); penetration is a per-shot budget.

## 5b. FX library as implemented (v19-fx, merged)

Usage doc at the top of `luarules/gadgets/fx_t4_heroes.lua`. Deltas vs §5: every call returns an id (`detach(id)` cuts
any effect early); `GG.HeroFX.hit(id, x, y, z)` for shield ripples; `orbPos(unitID, opts, frame, index)` and
`orbPointPos(x, z, opts, frame, index)` (pure, synced-safe); `set(id, {radius, color, alpha, stacks, angle, …, time})`;
`zone(x, z, opts)`, `attachPoint(x, z, kind, opts)`; `opts.visible = "los"|"ally"|"all"`; attach kinds also `mark`,
`link` (beam/bolt/drain tether), `tint` (rim/stone/heat/electric/ice/shadow on the model); ring kinds also
glow/sweep/fog/web/fire/swirl/mark; `opts.arc/angle/rot` for cones and sweeps. `cloak` is cosmetic — real cloak via api.
Showcase: `/mnt/data/bar-bench/out/fx/showcase/`, scene kit `tools/heroes/fx_showcase/`.

## 6b. Items as implemented (v19-items, merged)

Protocol and params in the header of `luarules/gadgets/unit_t4_hero_items.lua`; data and helpers (`I.decode`, `I.lines`,
`I.icon`) in `luarules/configs/t4_hero_items.lua`. Shops `armt4shop/cort4shop/legt4shop` (`units/other/t4shops.lua`).
