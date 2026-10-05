# v23 balance: Legion heroes (rank 10, level 100)

Method: effective ability damage = base x `api.power` (L100 ~1.99) x `dmgScale` (0.7; artillery 1/3 x 0.7). Weapon
DPS at L100 is ~2x `heroBalance.dps` x the same `dmgScale`, so the budgets below are in **base numbers** against
`heroBalance.dps`: burst (any 1 s, one target) <= 3x dps, sustained <= 1.5x dps, targeted range <= 1.25x the
hero's longest weapon (artillery: <= its weapon range), stun <= ~5 s.

| Hero | Weapon reach | dps | burst / sustained budget | range budget |
|---|---|---|---|---|
| Helios | 1400 | 10500 | 31.5k / 15.8k | 1750 |
| Starfall (arty) | 6975 | 7800 | 23.4k / 11.7k | 6975 |
| Longinus | 1200 | 8800 | 26.4k / 13.2k | 1500 |
| Tempest | 1120 (flak 1280) | 14500 | 43.5k / 21.8k | 1400-1600 |
| Myrmidon | 1980 | 6500 | 19.5k / 9.8k | 2475 |
| Keres | 770 | 9500 | 28.5k / 14.3k | 960 |
| Mukade | 1190 | 14500 | 43.5k / 21.8k | 1490 |
| Charybdis | 900 | 4850 (real ~9000) | 14.5k / 7.3k | 1125 |
| Apollyon | 1800 | 14500 | 43.5k / 21.8k | 2250 |
| Medusa (arty) | 2600 | 7500 | 22.5k / 11.3k | 2600 |
| Boreas (arty, new) | 2600 | 7500 | 22.5k / 11.3k | 2600 |

## Changes

| Hero / ability | Old (rank 10) | New (rank 10) | Why |
|---|---|---|---|
| Helios a1 Solar Heat | ignite cap 10000, spread 3 Heat; every igniting unit blasted everyone in 220 | cap 6000, spread 2; **a unit takes one ignite blast per 0.5 s** (the ignited one always) | a pack hitting 10 Heat together stacked a dozen blasts (up to ~140k x1.4) on each unit in one frame |
| Helios ult Sunstrike | range 2400 | 1750 | 1.7x its heat-ray reach |
| Starfall a2 Gravity Lens | range 7000 | 6900 | past its cannon reach |
| Starfall a3 Deep Sky Eye | range 9000 | 6900 | revealed / Observed areas 2000 past anything it can shoot |
| Starfall ult Starfall | range 9000, autocast to 1.3x weapon reach | 6900, autocast within weapon reach | meteors 2000+ beyond its range |
| Longinus a2 Hunter's Mark | range 3000 | 1500 | marked (revealed, focused) prey 2.5x its rail reach |
| Longinus ult Spear | range 4200; 25% max HP (heroes 12.5%) + 25000; line 7000 sharing 12000 x4 | range 1500; 8% (heroes 4%) + 12000; line 2400 sharing 7000 x4 | one-shot of a 400k hero at 3.5x weapon range (~70k effective in one hit); now ~28k on a 400k hero, ~20k on a 60k-HP T3, within the 3 s weapon budget |
| Keres a2 Death Grip | range 1400 | 950 | dragged units from 1.8x its gun reach |
| Keres ult Danse Macabre | spirits strike within 1200 | 950 | spirits picked targets beyond reach |
| Mukade ult Coil | 7 s stun (heroes 3.5) | 5 s (heroes 2.5) | stun cap |
| Charybdis a2 Waterspout | range 1400 | 1100 | 1.55x its rocket reach |
| Charybdis ult Maw of the Deep | range 1600 | 1100 | 1.8x its reach |
| Apollyon a2 Locust Swarm | range 2400 | 2200 | over 1.25x racks reach |
| Apollyon a3 Siege Lockdown | +60% weapon range (racks 2880) | +35% (2430) | the anchored racks outranged artillery heroes |
| Apollyon ult Plague of Locusts | range 3000 | 2200 | 1.7x its reach |

Checked and kept (within the rules at rank 10): Helios a2 Corona Flare (self, 900, 3500 x heat), a3 Sunspot (1400,
4 lashes x 250 / 0.5 s); Starfall a1 lines (900 / 0.5 s, once per tick), meteors 24 x 700 + comet 3500 (arty
scale); Longinus a1, a3 Phase Rail (dash, shared 8000 budget); all of Tempest (charge 1200, ult 700 / 0.2 s in 650 =
3.5k/s, clap 15000, stun <= 2.5 s); Myrmidon (dive 8 x 1500, range 1800); Keres a1, a3 Devour (400 range); Mukade
Burrow (dash), Venom (<= 5000/s), Molting; Charybdis a1, a3 Surge (dash, 6000 per victim), Maw damage (<= 1000/s
core); Medusa (all ranges <= 2600, stone <= 5 s, arty scale). Stuns: api.stun halves them on heroes.

## New hero: Boreas, the Firestorm (`legt4boreas`, 11th Legion hero)

Base: `legavroc` (Boreas starburst rocket truck) x3.2 model (`tools/t4/build_models.py`), range x2.0 (2600),
reload 18 s -> 3 s (damage rescaled by `T4.heroBalance`: hp 230k, dps 7500, speed 36, dmgScale 1/3 - the artillery
row, like Medusa), sight x4.5, `T4TANK9`, back line, aiPick 2, xpRate 0.5. Commands 36329-36331.

| Ability | Rank 10 | Budget check |
|---|---|---|
| a1 Scorched Earth (passive) | rack impacts burn the ground 4 s: 800/s in 240 (max 6 fires); burning enemies +15% damage from Boreas | sustained 800/s << 11.3k |
| a2 Hellfire Volley (map, <= 2600) | 10 rockets x 1600 (aoe 200) over ~1.2 s, one per enemy, spares scatter in 320; each burns | worst case one target 16k <= 22.5k |
| a3 Thermal Vent (self) | 1200 in 320, then 6 s +50% speed, +25% armour, burning trail | escape tool |
| ult Firestorm (map, <= 2600) | 1.5 s telegraph (rune + closing ring), then 40 rockets x 800 (aoe 180, 70% on units) over 6 s in 700, area burns 500/s | per target ~5.3k/s worst case <= 11.3k; walk-out window |

Bench (`tools/heroes/leg_bench/ac_boreas.lua`, L100 autocast, 20 s): loads, every ability fires, no Lua errors.
