-- Custom T4 heroes (denysfast/bar-game): effects of hero levels, revives, abilities, weapon upgrades and items.
-- Spawned by luarules/gadgets/unit_t4_heroes.lua with Spring.SpawnCEG. Scaled copies of stock effects
-- live in gamedata/custom_t4_fx.lua.
--
-- v14: every ability effect is layered - a ground decal (rune / hex / ring from bitmaps/groundfx/t4g_*),
-- an expanding shockwave, a billboard burst (bitmaps/projectiletextures/t4_*), sparks, debris or smoke, and
-- a lingering glow. The sprites were generated with content-master (Krea 2) on pure black and keyed to
-- alpha by brightness.

-- colors with the alpha of every stage scaled: BAR blends particles premultiplied (ONE, ONE_MINUS_SRC_ALPHA),
-- a low alpha makes a glow add light instead of covering what is behind it
local function additive(color, k)
	local i = 0
	return (color:gsub("[%d%.%-]+", function(v)
		i = i + 1
		if i % 4 == 0 then
			return string.format("%.3f", tonumber(v) * k)
		end
		return v
	end))
end

local function dim(color, k)
	local i = 0
	return (color:gsub("[%d%.%-]+", function(v)
		i = i + 1
		if i % 4 ~= 0 then
			return string.format("%.3f", tonumber(v) * k)
		end
		return v
	end))
end

local GROUND_BRIGHTNESS = 0.75
local function ground(texture, color, size, growth, ttl)
	color = dim(additive(color, 0.4), GROUND_BRIGHTNESS)
	return {
		class = [[CSimpleGroundFlash]],
		count = 1,
		air = true,
		ground = true,
		water = true,
		properties = {
			colormap = color,
			size = size,
			sizegrowth = growth,
			ttl = ttl,
			texture = texture,
			alwaysvisible = true,
		},
	}
end

-- one camera-facing sprite (a particle system of one particle that does not move)
local SPRITE_SCALE = 0.5
local function sprite(texture, color, size, growth, life, y, o)
	o = o or {}
	size = size * SPRITE_SCALE
	growth = growth * SPRITE_SCALE
	color = additive(color, 0.35)
	return {
		class = [[CSimpleParticleSystem]],
		count = 1,
		air = true,
		ground = true,
		water = true,
		underwater = true,
		properties = {
			airdrag = 1,
			colormap = color,
			directional = false,
			emitrot = 0,
			emitrotspread = 0,
			emitvector = [[0, 1, 0]],
			gravity = [[0, 0, 0]],
			numparticles = o.count or 1,
			particlelife = life,
			particlelifespread = 0,
			particlesize = size,
			particlesizespread = o.sizespread or 0,
			particlespeed = 0,
			particlespeedspread = 0,
			pos = o.pos or string.format("0, %d, 0", y or 40),
			sizegrowth = growth,
			sizemod = 1.0,
			texture = texture,
			useairlos = false,
			alwaysvisible = true,
			drawOrder = o.drawOrder or 1,
		},
	}
end

-- a vertical column of light
local function pillar(color, height, width, ttl, texture, y)
	color = additive(color, 0)
	return {
		class = [[CBitmapMuzzleFlame]],
		count = 1,
		air = true,
		ground = true,
		water = true,
		underwater = true,
		properties = {
			colormap = color,
			dir = [[0, 1, 0]],
			frontoffset = 0,
			fronttexture = [[none]],
			sidetexture = texture or [[muzzleside]],
			length = height,
			size = width,
			sizegrowth = 0,
			ttl = ttl,
			pos = string.format("0, %d, 0", y or 0),
			alwaysvisible = true,
			drawOrder = 1,
		},
	}
end

-- a burst of particles
local SPARK_SCALE = 0.55
local function sparks(color, count, speed, life, size, o)
	o = o or {}
	if not o.texture or o.texture == [[flare]] then
		size = size * SPARK_SCALE
		color = additive(color, 0.4)
	elseif o.texture == [[flamestream]] then
		color = additive(color, 0.3)
	end
	return {
		class = [[CSimpleParticleSystem]],
		count = 1,
		air = true,
		ground = true,
		water = true,
		properties = {
			airdrag = o.airdrag or 0.93,
			colormap = color,
			directional = o.directional ~= false,
			emitrot = o.emitrot or 0,
			emitrotspread = o.emitrotspread or 90,
			emitvector = o.emitvector or [[0, 1, 0]],
			gravity = o.gravity or [[0, 0.15, 0]],
			numparticles = count,
			particlelife = life,
			particlelifespread = life * 0.6,
			particlesize = size,
			particlesizespread = size,
			particlespeed = speed,
			particlespeedspread = speed,
			pos = o.pos or [[0, 20, 0]],
			sizegrowth = o.sizegrowth or 0,
			sizemod = o.sizemod or 1.0,
			texture = o.texture or [[flare]],
			useairlos = false,
			alwaysvisible = true,
		},
	}
end

local function spikes(color, count, length, width, ttl)
	return {
		class = [[CExploSpikeProjectile]],
		count = count,
		air = true,
		ground = true,
		water = true,
		properties = {
			alpha = 1,
			alphadecay = 1 / ttl,
			color = color,
			dir = [[-1 r2, 0.1 r0.9, -1 r2]],
			length = length,
			lengthgrowth = length * 0.08,
			width = width,
			pos = [[0, 30, 0]],
			alwaysvisible = true,
		},
	}
end

local function cloud(texture, size, growth, heat, y)
	return {
		class = [[CHeatCloudProjectile]],
		count = 1,
		air = true,
		ground = true,
		water = true,
		properties = {
			heat = heat or 12,
			heatfalloff = 0.5,
			maxheat = heat or 12,
			pos = string.format("0, %d, 0", y or 40),
			size = size,
			sizegrowth = growth,
			speed = [[0, 0, 0]],
			texture = texture,
			alwaysvisible = true,
		},
	}
end

-- a delayed child effect
local function later(name, delay, pos)
	return {
		class = [[CExpGenSpawner]],
		count = 1,
		air = true,
		ground = true,
		water = true,
		properties = {
			delay = delay,
			explosiongenerator = "custom:" .. name,
			pos = pos or [[0, 0, 0]],
		},
	}
end

-- colormaps (r g b a per stage, fading to 0)
local function fade(r, g, b, a, stages)
	local parts = {}
	stages = stages or 4
	for i = 0, stages - 1 do
		local k = 1 - i / stages
		parts[#parts + 1] = string.format("%.2f %.2f %.2f %.2f", r * k, g * k, b * k, a * k)
	end
	parts[#parts + 1] = "0 0 0 0.01"
	return table.concat(parts, "   ")
end
local function pop(r, g, b, a)
	-- fades in quickly, holds, fades out
	return string.format("0 0 0 0.01   %.2f %.2f %.2f %.2f   %.2f %.2f %.2f %.2f   %.2f %.2f %.2f %.2f   0 0 0 0.01",
		r, g, b, a, r * 0.8, g * 0.8, b * 0.8, a * 0.8, r * 0.35, g * 0.35, b * 0.35, a * 0.35)
end

local GOLD_PILLAR = [[0 0 0 0   1 0.9 0.45 0.55   1 0.75 0.25 0.35   0.5 0.3 0.05 0.12   0 0 0 0]]
local GOLD_SPARK = [[1 0.95 0.6 1   1 0.7 0.2 0.7   0.4 0.2 0 0.2   0 0 0 0]]
local WHITE_PILLAR = [[0 0 0 0   0.85 0.95 1 0.7   0.6 0.8 1 0.45   0.2 0.35 0.6 0.15   0 0 0 0]]
local BLUE_SPARK = [[0.8 0.95 1 1   0.35 0.6 1 0.7   0.1 0.2 0.6 0.2   0 0 0 0]]
local GREEN_SPARK = [[0.8 1 0.8 1   0.3 1 0.4 0.7   0.05 0.4 0.1 0.2   0 0 0 0]]
local RED_SPARK = [[1 0.9 0.7 1   1 0.35 0.1 0.8   0.4 0.05 0 0.3   0 0 0 0]]
local FIRE = [[1 0.8 0.3 0.9   1 0.45 0.05 0.7   0.5 0.12 0 0.4   0.12 0.06 0.04 0.2   0 0 0 0]]
local SMOKE = [[0 0 0 0.01   0.06 0.055 0.05 0.35   0.05 0.045 0.04 0.3   0.03 0.03 0.03 0.18   0 0 0 0.01]]
local DUST = [[0 0 0 0.01   0.22 0.18 0.13 0.5   0.17 0.14 0.1 0.4   0.1 0.08 0.06 0.22   0 0 0 0.01]]
local VIOLET_SPARK = [[0.95 0.85 1 1   0.7 0.4 1 0.7   0.25 0.1 0.5 0.2   0 0 0 0]]

local E = {}

---------------------------------------------------------------------------- levels, revive, death

E["hero-levelup"] = {
	rune = ground([[t4g_rune]], fade(1, 0.85, 0.35, 0.9), 180, 4, 45),
	ring = ground([[t4g_ring]], fade(1, 0.8, 0.3, 0.9), 80, 28, 26),
	pillar = pillar(GOLD_PILLAR, 1400, 70, 55),
	core = pillar(WHITE_PILLAR, 900, 26, 40),
	sparks = sparks(GOLD_SPARK, 40, 9, 60, 10, { gravity = [[0, 0.25, 0]] }),
	flare = sprite([[t4_flare]], pop(1, 0.9, 0.5, 1), 220, 2, 20, 80),
}
-- every fifth level and every ultimate rank
E["hero-levelup-big"] = {
	rune = ground([[t4g_rune]], fade(1, 0.85, 0.35, 1), 320, 3, 70),
	ring = ground([[t4g_ring]], fade(1, 0.85, 0.4, 1), 120, 44, 34),
	ring2 = ground([[t4g_ring]], fade(0.4, 0.7, 1, 0.8), 60, 30, 45),
	pillar = pillar(GOLD_PILLAR, 2600, 140, 80),
	core = pillar(WHITE_PILLAR, 1800, 50, 60),
	sparks = sparks(GOLD_SPARK, 80, 14, 80, 14, { gravity = [[0, 0.3, 0]] }),
	sparks2 = sparks(BLUE_SPARK, 40, 11, 70, 12, { gravity = [[0, 0.2, 0]] }),
	flare = sprite([[t4_flare]], pop(1, 0.9, 0.55, 1), 520, 3, 26, 100),
}
-- a rank learned
E["hero-learn"] = {
	rune = ground([[t4g_rune]], fade(0.5, 0.85, 1, 0.8), 150, 2, 36),
	sparks = sparks(BLUE_SPARK, 24, 6, 45, 8, { gravity = [[0, 0.35, 0]], pos = [[-60 r120, 10, -60 r120]] }),
	flare = sprite([[t4_flare]], pop(0.6, 0.85, 1, 0.8), 140, 1, 16, 90),
}
E["hero-revive"] = {
	rune = ground([[t4g_rune]], fade(0.6, 0.85, 1, 1), 380, 2, 110),
	pillar = pillar(WHITE_PILLAR, 3200, 160, 110),
	core = pillar(GOLD_PILLAR, 2400, 60, 90),
	ring = ground([[t4g_ring]], fade(0.5, 0.8, 1, 0.9), 120, 40, 40),
	sparks = sparks(BLUE_SPARK, 70, 12, 90, 12, { gravity = [[0, 0.35, 0]] }),
	flare = sprite([[t4_flare]], pop(0.7, 0.9, 1, 1), 700, 3, 30, 120),
}
E["hero-death"] = {
	ring = ground([[t4g_ring]], fade(1, 0.35, 0.1, 1), 150, 45, 40),
	scorch = ground([[t4g_flames]], fade(1, 0.4, 0.1, 0.9), 300, 1, 90),
	pillar = pillar([[0 0 0 0   1 0.3 0.1 0.5   0.4 0.05 0 0.2   0 0 0 0]], 1600, 110, 60),
	smoke = sparks(SMOKE, 20, 4, 120, 80, { texture = [[bigexplosmoke]], gravity = [[0, 0.12, 0]], sizegrowth = 1.5, pos = [[-80 r160, 30, -80 r160]] }),
}

---------------------------------------------------------------------------- abilities

-- Guardian Protocol (Atlas): a golden hex shield over the army. Cast, then every second while active.
E["hero-guard-cast"] = {
	hex = ground([[t4g_hex]], pop(1, 0.85, 0.35, 0.9), 820, 0, 60),
	ring = ground([[t4g_ring]], fade(1, 0.9, 0.5, 1), 100, 70, 14),
	dome = sprite([[t4_hex]], pop(1, 0.8, 0.3, 0.55), 520, 6, 30, 110),
	flare = sprite([[t4_flare]], pop(1, 0.9, 0.6, 1), 500, 4, 18, 120),
	sparks = sparks(GOLD_SPARK, 50, 10, 50, 10, { emitrot = 70, emitrotspread = 20 }),
}
E["hero-guard"] = {
	hex = ground([[t4g_hex]], pop(1, 0.85, 0.35, 0.45), 800, 0, 32),
	edge = ground([[t4g_ring]], pop(1, 0.85, 0.35, 0.8), 800, 0, 30),
	sparks = sparks(GOLD_SPARK, 20, 4, 40, 9, { pos = [[-560 r1120, 20, -560 r1120]], gravity = [[0, 0.3, 0]] }),
}
-- Aegis Dome: allies inside are invulnerable
E["hero-dome-cast"] = {
	flash = sprite([[t4_flare]], pop(0.7, 0.9, 1, 1), 900, 6, 20, 150),
	ring = ground([[t4g_ring]], fade(0.6, 0.85, 1, 1), 100, 85, 12),
	hex = ground([[t4g_hex]], pop(0.5, 0.8, 1, 0.9), 900, 0, 50),
	sparks = sparks(BLUE_SPARK, 80, 16, 40, 12, { emitrot = 80, emitrotspread = 10 }),
}
E["hero-dome"] = {
	dome = sprite([[t4_hex]], pop(0.45, 0.75, 1, 0.5), 560, 0, 32, 110),
	hex = ground([[t4g_hex]], pop(0.4, 0.7, 1, 0.5), 900, 0, 32),
	edge = ground([[t4g_ring]], pop(0.5, 0.8, 1, 0.9), 900, 0, 30),
	sparks = sparks(BLUE_SPARK, 18, 3, 50, 12, { pos = [[-600 r1200, 40 r300, -600 r1200]], gravity = [[0, 0.1, 0]] }),
}
-- Pulse Overload (Aegis): the shield charge dumped as an EMP shockwave
E["hero-pulse"] = {
	flash = sprite([[t4_flare]], pop(0.7, 0.9, 1, 1), 700, 8, 16, 80),
	ring = ground([[t4g_ring]], fade(0.5, 0.85, 1, 1), 60, 48, 16),
	ring2 = ground([[t4g_ring]], fade(0.8, 0.95, 1, 1), 30, 36, 22),
	glow = ground([[groundflashwhite]], fade(0.4, 0.7, 1, 0.8), 600, 0, 20),
	arcs = sparks(BLUE_SPARK, 30, 22, 18, 40, { texture = [[t4_bolt]], emitrot = 85, emitrotspread = 8, pos = [[0, 40, 0]], gravity = [[0, 0, 0]] }),
	sparks = sparks(BLUE_SPARK, 60, 20, 30, 10, { emitrot = 80, emitrotspread = 15 }),
	after = later("hero-static-field", 8),
}
E["hero-static-field"] = {
	arcs = sparks(BLUE_SPARK, 14, 0, 10, 90, { texture = [[t4_bolt]], directional = false, pos = [[-400 r800, 40 r60, -400 r800]], gravity = [[0, 0, 0]] }),
}
-- War Stomp (Colossus): the ground cracks, dust wall, rocks
E["hero-stomp"] = {
	flash = sprite([[t4_flare]], pop(1, 0.85, 0.6, 1), 500, 6, 12, 40),
	ring = ground([[t4g_ring]], fade(1, 0.8, 0.5, 1), 80, 40, 18),
	crack = ground([[t4g_rune]], fade(1, 0.45, 0.15, 1), 520, 0, 80),
	scorch = ground([[groundflash]], fade(0.9, 0.6, 0.3, 0.8), 650, 0, 30),
	dustwall = sparks(DUST, 90, 16, 55, 55, { emitrot = 85, emitrotspread = 5, texture = [[bigexplosmoke]], gravity = [[0, -0.05, 0]], pos = [[0, 10, 0]], sizegrowth = 0.8 }),
	rocks = sparks([[0.5 0.42 0.35 1   0.4 0.33 0.27 1   0.3 0.25 0.2 0.8   0 0 0 0]], 40, 12, 45, 9,
		{ emitrot = 35, emitrotspread = 30, texture = [[bigexplosmoke]], gravity = [[0, -0.45, 0]], airdrag = 0.98, pos = [[0, 20, 0]] }),
	spikes = spikes([[1 0.7 0.35]], 10, 60, 14, 14),
}
-- Siege Protocol (Bastion): anchors, red energy
E["hero-siege"] = {
	rune = ground([[t4g_rune]], pop(1, 0.55, 0.2, 1), 460, 0, 90),
	ring = ground([[t4g_ring]], fade(1, 0.6, 0.25, 1), 80, 44, 18),
	ring2 = ground([[t4g_ring]], fade(1, 0.85, 0.5, 1), 40, 30, 24),
	flare = sprite([[t4_flare]], pop(1, 0.6, 0.3, 1), 700, 6, 22, 90),
	sun = sprite([[t4_sun]], pop(1, 0.45, 0.2, 0.8), 300, 4, 30, 120),
	spikes = spikes([[1 0.55 0.25]], 12, 70, 16, 16),
	dust = sparks(DUST, 50, 10, 45, 40, { emitrot = 85, emitrotspread = 5, texture = [[bigexplosmoke]], pos = [[0, 10, 0]], sizegrowth = 0.6 }),
	sparks = sparks(RED_SPARK, 60, 10, 40, 12, { gravity = [[0, 0.3, 0]] }),
}
-- self buffs: Rapid Barrage (Olympus), Overdrive (Tempest), Hellcharge (Hellwalker)
E["hero-barrage"] = {
	rune = ground([[t4g_rune]], pop(0.5, 0.8, 1, 1), 420, 0, 50),
	ring = ground([[t4g_ring]], fade(0.5, 0.8, 1, 1), 60, 40, 18),
	flare = sprite([[t4_flare]], pop(0.6, 0.85, 1, 1), 900, 6, 22, 140),
	ring2 = ground([[t4g_ring]], fade(0.8, 0.95, 1, 1), 30, 30, 24),
	spikes = spikes([[0.6 0.85 1]], 10, 60, 12, 14),
	sparks = sparks(BLUE_SPARK, 60, 12, 40, 12, { emitrot = 60, emitrotspread = 30 }),
	muzzle = sprite([[t4_sun]], pop(0.5, 0.75, 1, 0.8), 260, 3, 24, 160),
}
E["hero-overdrive"] = {
	ring = ground([[t4g_ring]], fade(0.4, 0.95, 1, 1), 60, 38, 18),
	ring2 = ground([[t4g_ring]], fade(0.8, 1, 1, 1), 30, 26, 24),
	blades = ground([[t4g_blades]], pop(0.5, 0.95, 1, 1), 420, 0, 40),
	flare = sprite([[t4_flare]], pop(0.5, 0.95, 1, 1), 600, 4, 18, 90),
	bolts = sprite([[t4_bolt]], pop(0.6, 0.95, 1, 1), 300, 0, 14, 90, { count = 3, sizespread = 150, pos = [[-80 r160, 60 r60, -80 r160]] }),
	sparks = sparks(BLUE_SPARK, 60, 14, 28, 12, { emitrot = 80, emitrotspread = 10 }),
}
E["hero-hellcharge"] = {
	flames = ground([[t4g_flames]], pop(1, 0.55, 0.1, 1), 420, 0, 40),
	flare = sprite([[t4_flare]], pop(1, 0.6, 0.2, 1), 420, 3, 18, 80),
	fire = sparks(FIRE, 40, 8, 40, 40, { texture = [[flamestream]], gravity = [[0, 0.3, 0]], sizegrowth = 0.6 }),
	ring = ground([[t4g_ring]], fade(1, 0.5, 0.1, 1), 60, 32, 16),
}
-- Solar Flare (Helios): a blinding sun at the hero, rays, burning ring, healing sparkles
E["hero-flare"] = {
	sun = sprite([[t4_sun]], pop(1, 0.95, 0.8, 1), 500, 12, 26, 120),
	flare = sprite([[t4_flare]], pop(0.8, 0.75, 0.6, 1), 800, 10, 20, 120),
	ring = ground([[t4g_ring]], fade(1, 0.85, 0.4, 1), 100, 44, 20),
	sunmark = ground([[t4g_sun]], pop(0.8, 0.55, 0.2, 0.6), 700, 0, 50),
	rays = spikes([[1 0.9 0.5]], 18, 140, 22, 18),
	heal = sparks(GREEN_SPARK, 50, 6, 50, 9, { pos = [[-700 r1400, 20, -700 r1400]], gravity = [[0, 0.35, 0]] }),
	embers = sparks(FIRE, 50, 14, 50, 14, { emitrot = 70, emitrotspread = 20 }),
}
-- Sunstrike (Helios): a column of sunlight from the sky, every 0.2 s while it burns
E["hero-sunbeam"] = {
	beam = pillar([[0 0 0 0   1 0.95 0.7 0.9   1 0.75 0.3 0.7   0.6 0.3 0.05 0.3   0 0 0 0]], 3200, 300, 9),
	core = pillar([[0 0 0 0   1 1 1 1   1 0.97 0.85 0.9   0 0 0 0]], 3200, 110, 8),
	sun = sprite([[t4_sun]], pop(1, 0.9, 0.6, 0.9), 520, 0, 9, 1600),
	mark = ground([[t4g_sun]], pop(1, 0.75, 0.3, 1), 420, 0, 10),
	scorch = ground([[groundflashwhite]], fade(1, 0.6, 0.2, 0.8), 360, 0, 10),
	fire = sparks(FIRE, 8, 7, 34, 34, { texture = [[flamestream]], pos = [[-200 r400, 10, -200 r400]], gravity = [[0, 0.4, 0]], sizegrowth = 0.5 }),
	embers = sparks(GOLD_SPARK, 14, 10, 30, 8, { emitrot = 45, emitrotspread = 40 }),
}
E["hero-sunbeam-start"] = {
	flash = sprite([[t4_flare]], pop(1, 0.95, 0.7, 1), 1400, 10, 24, 400),
	ring = ground([[t4g_ring]], fade(1, 0.85, 0.4, 1), 80, 50, 18),
}
-- Bladestorm (Tempest): a whirl of blades, every 0.2 s while it lasts
E["hero-bladestorm"] = {
	blades = ground([[t4g_blades]], pop(0.7, 0.95, 1, 1), 560, 0, 8),
	blades2 = sprite([[t4_blades]], pop(0.6, 0.9, 1, 0.8), 700, 0, 8, 60),
	edge = ground([[t4g_ring]], pop(0.5, 0.85, 1, 0.8), 560, 0, 8),
	shards = sparks(BLUE_SPARK, 30, 24, 12, 12, { emitrot = 88, emitrotspread = 4, pos = [[0, 50, 0]], gravity = [[0, 0, 0]], texture = [[shard2]] }),
	sparks = sparks([[1 1 1 1   0.7 0.9 1 0.8   0.2 0.4 0.8 0.2   0 0 0 0]], 16, 14, 14, 6, { emitrot = 80, emitrotspread = 20 }),
}
-- Immolation / Hellcharge trail (Hellwalker): burning ground
E["hero-firepatch"] = {
	flames = ground([[t4g_flames]], pop(1, 0.55, 0.1, 0.9), 170, 0, 45),
	fire = sparks(FIRE, 6, 2, 50, 44, { texture = [[flamestream]], pos = [[-50 r100, 5, -50 r100]], gravity = [[0, 0.35, 0]], sizegrowth = 0.4 }),
	smoke = sparks(SMOKE, 2, 1, 80, 50, { texture = [[bigexplosmoke]], pos = [[-40 r80, 60, -40 r80]], gravity = [[0, 0.2, 0]], sizegrowth = 1 }),
}
-- Undying (Colossus): reborn in fire
E["hero-undying"] = {
	flash = sprite([[t4_flare]], pop(1, 0.7, 0.3, 1), 1200, 10, 26, 150),
	sun = sprite([[t4_sun]], pop(1, 0.5, 0.15, 1), 500, 10, 40, 200),
	rune = ground([[t4g_rune]], fade(1, 0.45, 0.1, 1), 520, 1, 100),
	pillar = pillar([[0 0 0 0   1 0.5 0.15 0.8   1 0.25 0.05 0.5   0.4 0.05 0 0.15   0 0 0 0]], 2800, 170, 100),
	core = pillar(GOLD_PILLAR, 2000, 60, 80),
	ring = ground([[t4g_ring]], fade(1, 0.45, 0.15, 1), 120, 42, 40),
	fire = sparks(FIRE, 90, 14, 80, 18, { texture = [[flamestream]], gravity = [[0, 0.3, 0]], sizegrowth = 0.4 }),
}
-- Chain lightning / Static field hit
E["hero-static"] = {
	arcs = sparks(BLUE_SPARK, 4, 0, 8, 40, { texture = [[t4_bolt]], directional = false, pos = [[-30 r60, 40 r40, -30 r60]], gravity = [[0, 0, 0]] }),
	glow = sprite([[t4_flare]], pop(0.5, 0.8, 1, 0.8), 70, 1, 8, 30),
}
-- a strike of the Crown of Storms / a storm bolt landing
E["hero-zap"] = {
	bolt = sprite([[t4_bolt]], pop(0.8, 0.9, 1, 1), 900, 0, 8, 420),
	flash = sprite([[t4_flare]], pop(0.7, 0.85, 1, 1), 260, 4, 10, 30),
	ring = ground([[t4g_ring]], fade(0.5, 0.8, 1, 1), 40, 16, 12),
	sparks = sparks(BLUE_SPARK, 20, 9, 18, 7, { emitrot = 45, emitrotspread = 40 }),
}
E["hero-storm-cloud"] = {
	cloud = sparks([[0.12 0.14 0.2 0.8   0.1 0.12 0.18 0.7   0.06 0.07 0.1 0.4   0 0 0 0]], 6, 2, 60, 260,
		{ texture = [[bigexplosmoke]], pos = [[-500 r1000, 1500 r200, -500 r1000]], gravity = [[0, 0, 0]], sizegrowth = 1 }),
	glow = sprite([[t4_flare]], pop(0.5, 0.7, 1, 0.5), 900, 2, 10, 1500),
}
-- crits and weapon upgrades
E["hero-crit"] = {
	flare = sprite([[t4_flare]], pop(1, 0.35, 0.25, 1), 160, 3, 10, 30),
	spikes = spikes([[1 0.4 0.2]], 6, 40, 8, 8),
	sparks = sparks(RED_SPARK, 16, 12, 16, 8, { gravity = [[0, -0.2, 0]] }),
}
E["hero-pierce"] = {
	flare = sprite([[t4_flare]], pop(1, 0.85, 0.6, 0.9), 120, 2, 8, 10),
	sparks = sparks(GOLD_SPARK, 10, 10, 14, 6, { emitrot = 45, emitrotspread = 45 }),
}
E["hero-pierce-big"] = {
	flare = sprite([[t4_flare]], pop(1, 0.9, 0.7, 1), 220, 4, 10, 10),
	ring = ground([[t4g_ring]], fade(1, 0.8, 0.5, 1), 30, 14, 10),
	sparks = sparks(GOLD_SPARK, 20, 12, 18, 8, { emitrot = 45, emitrotspread = 45 }),
}
E["hero-afterburn"] = {
	fire = sparks(FIRE, 3, 2, 30, 26, { texture = [[flamestream]], pos = [[-20 r40, 10, -20 r40]], gravity = [[0, 0.35, 0]], sizegrowth = 0.3 }),
}
-- the target circle of an area ability
E["hero-target"] = {
	rune = ground([[t4g_rune]], pop(1, 0.3, 0.2, 1), 620, 0, 50),
	ring = ground([[t4g_ring]], fade(1, 0.25, 0.1, 1), 700, -10, 40),
}

---------------------------------------------------------------------------- items

local RARITY = {
	common = { 0.85, 0.85, 0.85 },
	rare = { 0.3, 0.6, 1.0 },
	epic = { 0.75, 0.35, 1.0 },
	legendary = { 1.0, 0.65, 0.1 },
}
for name, c in pairs(RARITY) do
	E["hero-itemdrop-" .. name] = {
		beam = pillar(string.format("0 0 0 0   %.2f %.2f %.2f 0.8   %.2f %.2f %.2f 0.4   0 0 0 0", c[1], c[2], c[3], c[1] * 0.6, c[2] * 0.6, c[3] * 0.6), 700, 40, 45),
		flare = sprite([[t4_flare]], pop(c[1], c[2], c[3], 1), 180, 2, 20, 60),
		ring = ground([[t4g_ring]], fade(c[1], c[2], c[3], 1), 30, 10, 20),
		sparks = sparks(string.format("1 1 1 1   %.2f %.2f %.2f 0.8   0 0 0 0", c[1], c[2], c[3]), 20, 6, 30, 7, { gravity = [[0, 0.2, 0]] }),
	}
	E["hero-itempickup-" .. name] = {
		flare = sprite([[t4_flare]], pop(c[1], c[2], c[3], 1), 240, 3, 16, 80),
		ring = ground([[t4g_ring]], fade(c[1], c[2], c[3], 1), 40, 16, 16),
		sparks = sparks(string.format("1 1 1 1   %.2f %.2f %.2f 0.8   0 0 0 0", c[1], c[2], c[3]), 26, 5, 40, 8, { gravity = [[0, 0.35, 0]] }),
	}
end
E["hero-itemheal"] = {
	rune = ground([[t4g_rune]], pop(0.3, 1, 0.45, 0.9), 260, 1, 40),
	sparks = sparks(GREEN_SPARK, 40, 5, 50, 10, { pos = [[-80 r160, 10, -80 r160]], gravity = [[0, 0.4, 0]] }),
	flare = sprite([[t4_flare]], pop(0.4, 1, 0.5, 1), 260, 2, 18, 80),
}
E["hero-phase"] = {
	hex = sprite([[t4_hex]], pop(0.8, 0.5, 1, 0.8), 420, 0, 90, 80),
	flare = sprite([[t4_flare]], pop(0.85, 0.6, 1, 1), 300, 4, 16, 80),
	sparks = sparks(VIOLET_SPARK, 30, 6, 40, 8, { gravity = [[0, 0.2, 0]] }),
}
E["hero-blink"] = {
	flare = sprite([[t4_flare]], pop(0.8, 0.5, 1, 1), 360, 6, 14, 60),
	ring = ground([[t4g_ring]], fade(0.7, 0.4, 1, 1), 40, 22, 14),
	sparks = sparks(VIOLET_SPARK, 40, 10, 30, 8, {}),
}
E["hero-aura-heal"] = {
	rune = ground([[t4g_rune]], pop(0.15, 0.6, 0.25, 0.4), 260, 1, 40),
	sparks = sparks(GREEN_SPARK, 14, 3, 50, 8, { pos = [[-300 r600, 10, -300 r600]], gravity = [[0, 0.3, 0]] }),
}
E["hero-aura-command"] = {
	rune = ground([[t4g_rune]], pop(0.6, 0.2, 0.08, 0.4), 260, 1, 40),
	sparks = sparks(RED_SPARK, 12, 3, 50, 8, { pos = [[-300 r600, 10, -300 r600]], gravity = [[0, 0.3, 0]] }),
}

return E
