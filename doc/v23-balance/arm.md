# v23 balance: Armada heroes (rank 10, level 100)

Effective ability damage = config value x power 1.99 x 0.7 (= x1.39); artillery (Olympus, Ambassador) another x1/3 (= x0.46).
Limits: targeted range <= ~1.25x the hero's longest weapon (artillery: <= its weapon range); one-second burst <= ~3 s of
its own L100 DPS (heroBalance dps x2); sustained abilities <= ~1.5x; stuns <= 5 s on units at rank 10.

| Hero | Ability | Old (rank 10) | New (rank 10) | Why |
|---|---|---|---|---|
| Thor | Rage Mode orb (earlier commit) | full salvo + chain on the most valuable enemy at 2x Coil range | one bolt on Thor's own target within Coil range, 25..50% of a salvo | long-range auto-target delete |
| Thor | Chain Lightning | 10 jumps x 750, chain walked anywhere (up to 7500 deep), 15% share (+5%/jump) = ~1.9 salvos | 8 jumps x 500, only enemies within 1.25x Thor's range (code), 10% share = ~0.95 salvo | auto-targets far beyond its weapon; extra damage > 1.5x DPS |
| Thor | EMP Missile | range 1800, 8 s paralysis | range 1250, 5 s | range 1.7x weapon; stun cap |
| Atlas | Titan Salvo | range 2200 | range 1900 | > 1.25x weapon (1548) |
| Atlas | Doomsday Lance | lance 2x Doom range (2880), cone pick within 2880 | 1.25x (1800, `lenMult`, code + text) | sweep hit 1.9x weapon range |
| Razor | Overcharge | +150% fire rate (permanent toggle) | +100% | sustained 2.5x DPS |
| Razor | Razor Swarm | 12 drones x 1400 (~23k DPS) | 8 drones x 1000 (~11k DPS) | passive drones out-damaged Razor itself |
| Ratte | Creeping Barrage | range 2100 | 1600 | > 1.25x weapon (1300) |
| Ratte | Main Gun | range 4000 (13.9k + firestorm) | range 1600 | 3x weapon range one-shell strike |
| Recluse | Cocoon | 10 s stun | 5 s | stun cap |
| Recluse | Rocket Monsoon | range 2600 | 2200 | > 1.25x weapon (1800) |
| Olympus | Spotter Flare | range 7000 (autocast on radar blips) | 4000 | artillery: within its (anchored) weapon range |
| Olympus | Ion Lance | range 9000 | 4000 | map-wide strike |
| Starlight | Focusing Array | +25%/stack x6 (+150%) | +15% x6 (+90%); text 50% -> 25% pierce (the code always used 25%) | sustained single-target > 1.5x; UI lied |
| Starlight | Prism Relay | 100% refraction, reach 700 | 75%, reach 500 (ally 1500 + 500 < weapon 2090) | doubled DPS; picked targets past its range |
| Starlight | Solar Lance | range 6000, 30.6k dmg/s x 5 s | range 2500, 22.2k dmg/s x 5 s | 3x range auto-target delete (picked the most valuable enemy at 6000) |
| Hive Mother | Drone Bay | 14000 DPS (19.5k eff.) | 11000 (15.3k eff.) | swarm + directive above the cap |
| Hive Mother | Swarm Directive | range 1600, +90% | 1300 (sight), +60% | beyond sight; focus 2.8x DPS |
| Hive Mother | Kamikaze Run | range 1800 | 1300 | beyond sight / laser range |

Unchanged (within the limits): Peewee Prime (all), Prowler (all: Harpoon 13.9k + detonation 33k < 66k burst cap; Apex range
1400 < 1.25x 1140), Atlas Doom Lens / Bulwark, Thor Electro-Devour, Ratte Overpressure / Plating, Recluse Web Rockets /
Web Field, Olympus Cluster Shells / Siege Anchor, Razor Cloak / Deflector, Starlight Phase Shift, Hive Mothership.

## New hero: Ambassador, the Rocket Marshal (`armt4ambassador`, 11th Armada hero)

armmerl x3.0 (model `objects3d/Units/T4/armt4ambassador*.s3o`, `tools/t4/build_models.py`), back-line rocket artillery:
230k HP, 7500 DPS, speed 34, `dmgScale` 1/3, weapon range 2600 (4-rocket starburst salvos), radar 2800, xp x0.25.
Commands 36142..36144. Icons reuse Olympus / Recluse / Peewee / Ratte art.

| Ability | Rank 10 (effective at L100) | Check |
|---|---|---|
| Target Painter (passive) | rocket hits paint 6 s: revealed, +12% damage taken | - |
| Guided Volley | 10 homing rockets x 3000 (1.39k eff.) within 500 of a point <= 2400 away; painted first, max 1/3 of the volley on one target | 1 s burst <= 13.9k eff. total, ~4.6k on one target vs 15k cap |
| Scoot Jets | 0.8 s hop up to 700, rack reloaded, +50% speed 4 s | - |
| Saturation Barrage | 2 s red-ring warning, then 60 rockets x 2000 (0.93k eff.) over 8 s in 600, range <= 2600; immobile | ~7k eff./s over the whole area <= 1.5x DPS |
