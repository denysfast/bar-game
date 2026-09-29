-- Custom heroes (denysfast/bar-game): hit effects of the v15 weapon trees - perks and track mechanics
-- (burn-through, afterburn, arcs, secondary blasts, paralysis, crits). Spawned by
-- luarules/gadgets/unit_t4_heroes.lua (weaponHit / weaponEffects); names listed in
-- luarules/configs/t4_hero_weapons.lua (perk `fx`). Sprites: bitmaps/projectiletextures/t4_*, groundfx t4g_*.
-- The helpers are a copy of the ones in effects/custom_t4_heroes.lua.

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

-- burn-through: a spark burst at the end of the line behind the target
E["hero-wfx-pierce"] = {
	flare = sprite([[t4_flare]], pop(1, 0.85, 0.6, 0.9), 120, 2, 8, 10),
	sparks = sparks(GOLD_SPARK, 10, 10, 14, 6, { emitrot = 45, emitrotspread = 45 }),
}
E["hero-wfx-pierce-big"] = {
	flare = sprite([[t4_flare]], pop(1, 0.9, 0.7, 1), 220, 4, 10, 10),
	ring = ground([[t4g_ring]], fade(1, 0.8, 0.5, 1), 30, 14, 10),
	sparks = sparks(GOLD_SPARK, 20, 12, 18, 8, { emitrot = 45, emitrotspread = 45 }),
}
-- afterburn: flames licking a burning target
E["hero-wfx-afterburn"] = {
	fire = sparks(FIRE, 3, 2, 30, 26, { texture = [[flamestream]], pos = [[-20 r40, 10, -20 r40]], gravity = [[0, 0.35, 0]], sizegrowth = 0.3 }),
}
-- paralysis on the target
E["hero-wfx-static"] = {
	arcs = sparks(BLUE_SPARK, 4, 0, 8, 40, { texture = [[t4_bolt]], directional = false, pos = [[-30 r60, 40 r40, -30 r60]], gravity = [[0, 0, 0]] }),
	glow = sprite([[t4_flare]], pop(0.5, 0.8, 1, 0.8), 70, 1, 8, 30),
}
-- an arc landing on the next enemy
E["hero-wfx-arc"] = {
	bolt = sparks(BLUE_SPARK, 3, 0, 6, 34, { texture = [[t4_bolt]], directional = false, pos = [[-20 r40, 20 r30, -20 r40]], gravity = [[0, 0, 0]] }),
	flash = sprite([[t4_flare]], pop(0.6, 0.8, 1, 1), 90, 2, 8, 20),
	sparks = sparks(BLUE_SPARK, 12, 8, 14, 6, { emitrot = 40, emitrotspread = 50 }),
}
-- secondary blast around the target
E["hero-wfx-shock"] = {
	ring = ground([[t4g_ring]], fade(1, 0.7, 0.35, 0.9), 30, 16, 12),
	flash = sprite([[t4_flare]], pop(1, 0.75, 0.4, 0.9), 150, 5, 9, 25),
	dust = sparks(DUST, 8, 5, 30, 40, { texture = [[bigexplosmoke]], emitrot = 80, emitrotspread = 10, gravity = [[0, 0.05, 0]], sizegrowth = 0.8, pos = [[0, 10, 0]] }),
	sparks = sparks(GOLD_SPARK, 18, 9, 18, 7, { emitrot = 50, emitrotspread = 40 }),
}
E["hero-wfx-shock-big"] = {
	ring = ground([[t4g_ring]], fade(1, 0.7, 0.35, 1), 45, 22, 14),
	flash = sprite([[t4_flare]], pop(1, 0.75, 0.4, 1), 260, 7, 10, 30),
	dust = sparks(DUST, 12, 7, 36, 60, { texture = [[bigexplosmoke]], emitrot = 80, emitrotspread = 10, gravity = [[0, 0.05, 0]], sizegrowth = 1, pos = [[0, 10, 0]] }),
	sparks = sparks(GOLD_SPARK, 28, 12, 20, 9, { emitrot = 50, emitrotspread = 40 }),
}
-- EMP blast around the target
E["hero-wfx-emp"] = {
	ring = ground([[t4g_ring]], fade(0.5, 0.8, 1, 1), 30, 18, 12),
	flash = sprite([[t4_flare]], pop(0.5, 0.75, 1, 1), 180, 5, 9, 25),
	arcs = sparks(BLUE_SPARK, 5, 6, 10, 30, { texture = [[t4_bolt]], emitrot = 85, emitrotspread = 8, pos = [[0, 20, 0]], gravity = [[0, 0, 0]] }),
}
-- perks
E["hero-wfx-scorch"] = {
	scorch = ground([[t4g_flames]], fade(1, 0.45, 0.1, 0.7), 70, 0.5, 40),
	fire = sparks(FIRE, 4, 3, 22, 18, { texture = [[flamestream]], pos = [[-15 r30, 5, -15 r30]], gravity = [[0, 0.3, 0]], sizegrowth = 0.3 }),
}
E["hero-wfx-heat"] = {
	glow = sprite([[t4_sun]], pop(1, 0.55, 0.2, 0.7), 110, 3, 14, 20),
	fire = sparks(FIRE, 6, 4, 18, 16, { texture = [[flamestream]], emitrot = 60, emitrotspread = 30, gravity = [[0, 0.2, 0]], sizegrowth = 0.4 }),
}
E["hero-wfx-sparks-gold"] = {
	sparks = sparks(GOLD_SPARK, 14, 9, 14, 6, { emitrot = 40, emitrotspread = 50 }),
	flare = sprite([[t4_flare]], pop(1, 0.85, 0.5, 0.8), 70, 2, 6, 10),
}
E["hero-wfx-sparks-blue"] = {
	sparks = sparks(BLUE_SPARK, 14, 10, 14, 6, { emitrot = 40, emitrotspread = 50 }),
	flare = sprite([[t4_flare]], pop(0.6, 0.8, 1, 0.8), 80, 2, 6, 10),
}
E["hero-wfx-plasma"] = {
	flash = sprite([[t4_flare]], pop(0.55, 0.75, 1, 1), 130, 4, 10, 15),
	ring = ground([[t4g_ring]], fade(0.5, 0.75, 1, 0.9), 25, 12, 12),
	sparks = sparks(BLUE_SPARK, 16, 8, 18, 7, { emitrot = 45, emitrotspread = 45 }),
}
E["hero-wfx-thunder"] = {
	bolt = sprite([[t4_bolt]], pop(0.8, 0.9, 1, 1), 260, 0, 6, 120),
	flash = sprite([[t4_flare]], pop(0.7, 0.85, 1, 1), 160, 4, 8, 20),
	ring = ground([[t4g_ring]], fade(0.5, 0.8, 1, 1), 30, 14, 10),
}
E["hero-wfx-crit"] = {
	flare = sprite([[t4_flare]], pop(1, 0.35, 0.25, 1), 160, 3, 10, 30),
	spikes = spikes([[1 0.4 0.2]], 6, 40, 8, 8),
	sparks = sparks(RED_SPARK, 16, 12, 16, 8, { gravity = [[0, -0.2, 0]] }),
}

return E
