-- Custom heroes (denysfast/bar-game): the projectiles of the ability kit, shared by every hero (T4 and T2).
-- T4.hero (gamedata/custom_t4.lua) adds them to each hero unitdef as <unit>_hero_ab_*; the hero gadget
-- (luarules/gadgets/unit_t4_heroes.lua) spawns them for barrages, missiles, spears and novas.
--
-- They are pure visuals: every one deals 0 damage. The gadget watches their explosions and applies the
-- ability's own numbers (damage, radius, stun, EMP) to enemies only, so an ability does exactly what its
-- text says, never hurts allies and never touches the hero's weapons.
--
--   hero_ab_meteor   burning meteor (Rain of Fire)          hero_ab_star     violet plasma meteor (Meteor Storm)
--   hero_ab_shell    orbital plasma shell, falls straight   hero_ab_missile  homing rocket, launched from the hero
--   hero_ab_nuke     tactical nuke missile                  hero_ab_bolt     a lightning bolt from the sky
--   hero_ab_spear    a colossal rail slug                   hero_ab_nova     explosion-only: nuclear finale (sound + CEG)
--   hero_ab_novamed / hero_ab_novasmall  smaller finales      hero_ab_blast    explosion-only: a heavy blast
return function(T4)
	local FX = T4.FX
	local out = {}

	local function visual(w)
		w.damage = { default = 0 }
		w.craterareaofeffect = 0
		w.craterboost = 0
		w.cratermult = 0
		w.impulsefactor = 0
		w.customparams = { t4_hero_weapon = 1, t4_ability = 1 }
		return w
	end

	out.hero_ab_meteor = visual(T4.shellWeapon({
		name = "Hero meteor", aoe = 16, damage = 0, ceg = "custom:hero-impact-meteor", cegtag = "meteortrail",
		rgb = "1 0.4 0.05", size = 14, soundhit = "xplolrg4", range = 9000,
	}))
	out.hero_ab_star = visual(T4.shellWeapon({
		name = "Hero plasma meteor", aoe = 16, damage = 0, ceg = "custom:hero-impact-star", cegtag = FX.ref("starfire-small", 2.5),
		rgb = "0.7 0.5 1", size = 16, soundhit = "xplolrg2", range = 9000,
	}))
	out.hero_ab_shell = visual(T4.shellWeapon({
		name = "Hero orbital shell", aoe = 16, damage = 0, ceg = "custom:hero-impact-shell", cegtag = FX.ref("arty-huge", 2.5),
		rgb = "0.55 0.8 1", size = 12, soundhit = "xplolrg3", range = 9000,
	}))
	out.hero_ab_missile = visual(T4.missileWeapon({
		name = "Hero homing rocket", aoe = 16, damage = 0, model = "cormissile.s3o",
		ceg = "custom:hero-impact-missile", cegtag = FX.ref("missiletrailmedium-starburst", 2.2),
		soundhit = "xplomed4", soundstart = "rocklit1", velocity = 850, turnrate = 32000, range = 4000,
	}))
	out.hero_ab_missile.smoketrail = false
	out.hero_ab_nuke = visual(T4.missileWeapon({
		name = "Hero tactical nuke", aoe = 16, damage = 0, model = "cortronmissile.s3o",
		ceg = FX.custom("newnuketac", 0.7), cegtag = "cruisemissiletrail-tacnuke",
		soundhit = "nukearm", soundstart = "misicbm1", velocity = 750, turnrate = 24000, range = 5000,
	}))
	local lightning = T4.base("units/ArmBots/T2/armzeus.lua", "armzeus").weapondefs.lightning
	out.hero_ab_bolt = visual(T4.weaponFrom(lightning, {
		name = "Hero storm bolt", damage = 0, burst = 1, range = 5000, thickness = 9, corethickness = 0.6,
		beamttl = 8, duration = 1, intensity = 30, rgbcolor = "0.55 0.65 1", soundstart = "lghthvy1",
		ceg = "custom:hero-zap",
	}))
	local rail = T4.base("units/Legion/T3/legerailtank.lua", "legerailtank").weapondefs.t3_rail_accelerator
	out.hero_ab_spear = visual(T4.weaponFrom(rail, {
		name = "Hero spear", damage = 0, range = 5000, thickness = 14, corethickness = 0.5, laserflaresize = 30,
		noexplode = true, weaponvelocity = 3600, rgbcolor = "0.7 0.9 1", ceg = "custom:hero-spear-hit",
	}))
	out.hero_ab_nova = visual(T4.novaWeapon({
		name = "Hero nuclear finale", aoe = 16, damage = 0, ceg = FX.custom("newnuketac", 1.5), soundhit = "nukearm",
	}))
	out.hero_ab_novamed = visual(T4.novaWeapon({
		name = "Hero nuclear finale (medium)", aoe = 16, damage = 0, ceg = FX.custom("newnuketac", 0.7), soundhit = "nukearm",
	}))
	out.hero_ab_novasmall = visual(T4.novaWeapon({
		name = "Hero nuclear finale (small)", aoe = 16, damage = 0, ceg = FX.custom("newnuketac", 0.45), soundhit = "xplolrg4",
	}))
	out.hero_ab_blast = visual(T4.novaWeapon({
		name = "Hero blast", aoe = 16, damage = 0, ceg = FX.custom("genericshellexplosion-huge", 1.6), soundhit = "xplolrg4",
	}))
	for _, w in pairs(out) do
		w.camerashake = nil
	end
	return out
end
