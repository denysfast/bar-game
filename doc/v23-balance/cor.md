# v23 balance: Cortex heroes, rank 10

Effective rank-10 numbers = config value x ability power (~2 at L100) x 0.7 (hero_damage_mult), artillery heroes x 1/3
more. The hero's weapon DPS gets the same factors, so the budgets compare the raw config numbers with the raw
`T4.heroBalance` dps: burst in any 1 s <= 3 x dps, sustained <= 1.5 x dps, ultimates telegraphed and <= ~6 s of dps
per target, stun <= ~5 s, targeting range <= ~1.25 x the longest weapon (artillery: its weapon range).

| Hero (weapon range) | Ability | Old | New | Why |
|---|---|---|---|---|
| Juggernaut (767) | Power Shot range | 970..1370 | 800..950 | 1.8x weapon range |
| Juggernaut | Reactive Armor | icd 0.2 s, cap 10000, dmg 1500..4500, retaliates at 1200 | icd 1 s, cap 6000, dmg 1500..4000, reach 1000 | under focus fire it fired up to 5 x 2 shells of 10k per second (~100k/s, 11x its dps) |
| Hellwalker (800) | Hell on Earth meteor range | 1200 | 1000 | meteors on random enemies beyond its reach |
| Armageddon (2700, arty) | Doom Painter range | 3200 | 2700 | past weapon range |
| Armageddon | Armageddon Protocol range | 3200..4200 | 2400..2700 | past weapon range (damage per target was fine) |
| Vesuvius (1200, siege 1920) | Eruption range | 2400 | 1800 | 2x weapon range |
| Printer (750) | Swarm Protocol range | 1800 | 950 | 2.4x weapon range |
| Commando (500) | Disruptor Mines range | 700 | 650 | 1.4x weapon range |
| Commando | Shadowstep range | 700..1100 | 550..650 | a 1100 blink + 10k hit from out of sight |
| Commando | Blackout | range 1500, radius 600..900, text said +50% | range 650, radius 500..700, text +20% (the real bonus) | 4 s stun of a whole army from 3x weapon range |
| Deadeye (1870) | Recon Flare range | 2400 | 2300 | 1.25x weapon range |
| Deadeye | Kill Shot | range 3000..4500, 40k..90k + 8..20% max HP (cap 60k) | range 2000..2300, 20k..36k + 5..12% (cap 20k) | up to 150k raw (210k effective) in one shot from 2.4x weapon range; now ~6 s of its dps, 2 s telegraphed channel kept |
| Cataphract (1015) | Lancer's Gauntlet dmg | 9000..21000 per dash | 8000..16000 | 7 dashes in 2.8 s = 52k/s; now 40k/s, still the strongest burst of its kit |

Checked and kept: Circle Beam, Resurrection (30k nova, 3 s downed telegraph), Colossus (all within budget, Titan
Grip throw 1600 <= 1.25 x 1330), Combustion / Hellcharge / Furnace, Cluster Warheads / Retro Rockets, Vesuvius
a1-a3 (Banisher 12.6k/s peak), Printer drones (12k dps total, within 1.5x) / turret / repair, Ghost Protocol,
Focus / Tumble, Karganeth (Hydra Lock radius 1300 vs 1310 cap, 8-16k/s spread over distinct targets), Lance Charge,
Disruption (2.5 s stun), Phase Decoy. All stuns <= 4 s.

## New hero: Negotiator, the Last Argument (cort4negotiator, corvroc x3)

Back-line starburst rocket artillery (range 2360, hp 220k, dps 7500, dmgScale 1/3, xpRate 0.15).

| Ability | Rank 1 -> 10 | Budget check |
|---|---|---|
| Target Lock (passive) | rocket hits Lock 4..8 s: +4..12% damage taken, revealed | debuff only |
| Missile Volley (unit) | 4..10 rockets x 900..1500 over 2 s, +25% vs Locked, range 1800..2300, cd 18..10 | peak 9.4k/s <= 22.5k |
| Siege Deploy (toggle) | 8..14 s immobile, -15% taken, +10..25% range, +15..35% fire rate, cd 20 | 1.35x dps |
| Saturation Barrage (ult, map) | 2.5 s warning circle 450..600, 20..48 rockets x 500..800 over 5 s, range 2000..2300 | ~3.3k per target, 7.7k/s over the area |
