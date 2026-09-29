-- Custom heroes (denysfast/bar-game): weapon kinds and their upgrade tracks. Included by luarules/configs/t4_heroes.lua,
-- which passes the shared table H. See CUSTOM.md, section "Heroes".
local H = ...

-- Weapon trees (v14): every real weapon of a hero levels on its own. A weapon kind has three tracks of
-- WEAPON_RANKS ranks; `per` is one rank of the track:
--   damage     fraction of the weapon's damage
--   range      fraction of its range
--   reload     fraction off its reload time
--   splash     fraction of its area of effect
--   pellets    extra projectiles per shot
--   salvo      extra shots per salvo: `per` of the base salvo (at least 1)
--   pierce     share of each hit dealt again to the enemies on a line behind the target (`len` elmos)
--   burn       share of each hit dealt again as fire over 3 seconds
--   discharge  share of each hit dealt again as paralysis (EMP)
-- The visual tier of a weapon (thicker beams, bigger shells and blasts) follows the sum of its ranks.
H.WEAPON_RANKS = 10
H.weaponTiers = { 0, 6, 15, 24 }   -- rank sum where tiers 1..4 start
local T = {
	damage = { name = "Damage", icon = "stat_damage", stat = "damage", per = 0.10, fmt = "+%d%% damage" },
	range = { name = "Range", icon = "stat_range", stat = "range", per = 0.04, fmt = "+%d%% range" },
	reload = { name = "Rate of fire", icon = "stat_reload", stat = "reload", per = 0.05, fmt = "-%d%% reload" },
	splash = { name = "Splash", icon = "stat_splash", stat = "splash", per = 0.12, fmt = "+%d%% blast radius" },
	pellets = { name = "Pellets", icon = "stat_pellets", stat = "pellets", per = 1, fmt = "+%d pellets", abs = true },
	salvo = { name = "Salvo", icon = "stat_salvo", stat = "salvo", per = 0.12, fmt = "+%d%% rockets per salvo" },
	pierce = { name = "Burn-through", icon = "stat_pierce", stat = "pierce", per = 0.07, len = 600, fmt = "%d%% of the hit burns through the line" },
	penetration = { name = "Penetration", icon = "stat_penetration", stat = "pierce", per = 0.08, len = 1200, fmt = "%d%% of the hit pierces the line" },
	burn = { name = "Afterburn", icon = "stat_burn", stat = "burn", per = 0.06, fmt = "%d%% of the hit burns on for 3 s" },
	discharge = { name = "Discharge", icon = "stat_discharge", stat = "discharge", per = 0.15, fmt = "%d%% of the hit as paralysis" },
}
H.tracks = T
H.weaponKinds = {
	beam = { label = "Beam", tracks = { "damage", "range", "pierce" } },
	shotgun = { label = "Shotgun", tracks = { "damage", "splash", "pellets" } },
	cannon = { label = "Cannon", tracks = { "damage", "splash", "reload" } },
	artillery = { label = "Artillery", tracks = { "damage", "range", "splash" } },
	rockets = { label = "Rockets", tracks = { "damage", "salvo", "splash" } },
	lightning = { label = "Lightning", tracks = { "damage", "range", "discharge" } },
	flame = { label = "Flamethrower", tracks = { "damage", "range", "burn" } },
	rail = { label = "Rail", tracks = { "damage", "range", "penetration" } },
	emp = { label = "EMP", tracks = { "damage", "range", "reload" } },
}
