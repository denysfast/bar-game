-- Custom T4 heroes (denysfast/bar-game): effects of hero levels, revives and abilities.
-- Spawned by luarules/gadgets/unit_t4_heroes.lua with Spring.SpawnCEG. Scaled copies of stock effects
-- live in gamedata/custom_t4_fx.lua.

-- an expanding ring on the ground
local function ring(color, size, growth, ttl, texture)
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
			texture = texture or [[blastwave]],
			alwaysvisible = true,
		},
	}
end

-- a vertical column of light
local function pillar(color, height, width, ttl, texture, y)
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

-- a bright billboard flash
local function flash(color, size, ttl, texture, y)
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
			fronttexture = texture or [[exploflare]],
			sidetexture = [[none]],
			length = 20,
			size = size,
			sizegrowth = [[0.4 r0.2]],
			ttl = ttl,
			pos = string.format("0, %d, 0", y or 60),
			alwaysvisible = true,
			drawOrder = 1,
		},
	}
end

-- a burst of particles
local function sparks(color, count, speed, life, size, o)
	o = o or {}
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
			sizemod = 1.0,
			texture = o.texture or [[flare]],
			useairlos = false,
			alwaysvisible = true,
		},
	}
end

local function cloud(texture, size, growth, heat)
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
			pos = [[0, 40, 0]],
			size = size,
			sizegrowth = growth,
			speed = [[0, 0, 0]],
			texture = texture,
			alwaysvisible = true,
		},
	}
end

local GOLD_RING = [[1 0.85 0.3 0.9   0.9 0.6 0.15 0.5   0 0 0 0.01]]
local GOLD_PILLAR = [[0 0 0 0   1 0.9 0.45 0.55   1 0.75 0.25 0.35   0.5 0.3 0.05 0.12   0 0 0 0]]
local GOLD_SPARK = [[1 0.95 0.6 1   1 0.7 0.2 0.7   0.4 0.2 0 0.2   0 0 0 0]]
local WHITE_PILLAR = [[0 0 0 0   0.85 0.95 1 0.7   0.6 0.8 1 0.45   0.2 0.35 0.6 0.15   0 0 0 0]]
local BLUE_RING = [[0.5 0.8 1 0.8   0.2 0.45 1 0.45   0 0 0 0.01]]
local BLUE_SPARK = [[0.8 0.95 1 1   0.35 0.6 1 0.7   0.1 0.2 0.6 0.2   0 0 0 0]]
local RED_RING = [[1 0.45 0.15 0.9   0.8 0.2 0.05 0.5   0 0 0 0.01]]
local DUST_RING = [[0.75 0.62 0.45 0.9   0.5 0.4 0.28 0.55   0 0 0 0.01]]
local FIRE = [[1 0.8 0.3 0.9   1 0.45 0.05 0.7   0.5 0.12 0 0.4   0.12 0.06 0.04 0.2   0 0 0 0]]

return {
	["hero-levelup"] = {
		ring = ring(GOLD_RING, 60, 32, 28),
		ring2 = ring(GOLD_RING, 30, 18, 40, [[groundflashwhite]]),
		pillar = pillar(GOLD_PILLAR, 1400, 70, 55),
		core = pillar(WHITE_PILLAR, 900, 26, 40),
		sparks = sparks(GOLD_SPARK, 40, 9, 60, 10, { gravity = [[0, 0.25, 0]] }),
		flash = flash(GOLD_SPARK, 260, 18),
	},
	-- every fifth level and every ultimate rank
	["hero-levelup-big"] = {
		ring = ring(GOLD_RING, 80, 48, 34),
		ring2 = ring(BLUE_RING, 40, 30, 45),
		pillar = pillar(GOLD_PILLAR, 2600, 140, 80),
		core = pillar(WHITE_PILLAR, 1800, 50, 60),
		sparks = sparks(GOLD_SPARK, 80, 14, 80, 14, { gravity = [[0, 0.3, 0]] }),
		sparks2 = sparks(BLUE_SPARK, 40, 11, 70, 12, { gravity = [[0, 0.2, 0]] }),
		nova = cloud([[bluenovaexplo]], 60, 18),
		flash = flash(GOLD_SPARK, 520, 24),
	},
	["hero-revive"] = {
		pillar = pillar(WHITE_PILLAR, 3200, 160, 110),
		core = pillar(GOLD_PILLAR, 2400, 60, 90),
		ring = ring(BLUE_RING, 100, 40, 40),
		ring2 = ring(GOLD_RING, 50, 22, 60),
		sparks = sparks(BLUE_SPARK, 70, 12, 90, 12, { gravity = [[0, 0.35, 0]] }),
		flash = flash(BLUE_SPARK, 700, 30),
	},
	["hero-death"] = {
		ring = ring(RED_RING, 120, 45, 40),
		pillar = pillar([[0 0 0 0   1 0.3 0.1 0.5   0.4 0.05 0 0.2   0 0 0 0]], 1600, 110, 60),
	},
	["hero-guard"] = {
		ring = ring([[1 0.85 0.35 0.35   0.9 0.7 0.2 0.2   0 0 0 0.01]], 800, 0, 34, [[groundflash]]),
		edge = ring(GOLD_RING, 780, 1, 30),
		sparks = sparks(GOLD_SPARK, 18, 5, 40, 8, { pos = [[-500 r1000, 30, -500 r1000]], gravity = [[0, 0.2, 0]] }),
	},
	["hero-dome"] = {
		ring = ring([[0.6 0.85 1 0.4   0.3 0.6 1 0.25   0 0 0 0.01]], 900, 0, 18, [[groundflash]]),
		edge = ring(BLUE_RING, 880, 1, 16),
		dome = cloud([[bluenovaexplo]], 850, 0, 4),
		sparks = sparks(BLUE_SPARK, 24, 4, 40, 10, { pos = [[-600 r1200, 60 r300, -600 r1200]], gravity = [[0, 0.05, 0]] }),
	},
	["hero-stomp"] = {
		ring = ring(DUST_RING, 80, 36, 22),
		ring2 = ring(DUST_RING, 40, 24, 30, [[groundflash]]),
		dust = sparks([[0.6 0.5 0.36 0.7   0.45 0.36 0.25 0.5   0 0 0 0]], 60, 14, 60, 40,
			{ emitrot = 80, emitrotspread = 10, texture = [[dirtpuff]], gravity = [[0, -0.1, 0]], pos = [[0, 10, 0]] }),
		flash = flash([[1 0.9 0.7 0.8   0.6 0.4 0.2 0.4   0 0 0 0]], 500, 12),
	},
	["hero-pulse"] = {
		ring = ring(BLUE_RING, 60, 36, 20),
		ring2 = ring(BLUE_RING, 30, 26, 28, [[groundflashwhite]]),
		sparks = sparks(BLUE_SPARK, 50, 18, 30, 10, { emitrot = 85, emitrotspread = 10 }),
		flash = flash(BLUE_SPARK, 600, 14),
	},
	["hero-sunbeam"] = {
		beam = pillar([[0 0 0 0   1 0.95 0.75 0.9   1 0.7 0.25 0.6   0.5 0.2 0 0.2   0 0 0 0]], 3500, 220, 9),
		core = pillar([[0 0 0 0   1 1 1 1   1 0.95 0.8 0.7   0 0 0 0]], 3500, 70, 8),
		ground = ring([[1 0.85 0.5 0.9   1 0.5 0.1 0.5   0 0 0 0.01]], 320, -2, 10, [[groundflashwhite]]),
		fire = sparks(FIRE, 6, 6, 30, 30, { texture = [[flame]], pos = [[-200 r400, 10, -200 r400]], gravity = [[0, 0.3, 0]] }),
	},
	["hero-flare"] = {
		flash = flash([[1 1 1 1   1 0.95 0.8 0.8   1 0.7 0.3 0.3   0 0 0 0]], 1800, 22),
		ring = ring([[1 0.95 0.7 0.9   1 0.6 0.2 0.5   0 0 0 0.01]], 100, 40, 22),
		nova = cloud([[orangenovaexplo]], 100, 40, 15),
	},
	["hero-bladestorm"] = {
		ring = ring([[0.6 0.9 1 0.6   0.4 0.6 1 0.3   0 0 0 0.01]], 480, -4, 10),
		sparks = sparks(BLUE_SPARK, 30, 22, 14, 10, { emitrot = 88, emitrotspread = 4, pos = [[0, 40, 0]], gravity = [[0, 0, 0]], texture = [[shard2]] }),
	},
	["hero-firepatch"] = {
		fire = sparks(FIRE, 5, 2, 50, 38, { texture = [[flame]], pos = [[-40 r80, 5, -40 r80]], gravity = [[0, 0.25, 0]] }),
		glow = ring([[1 0.5 0.1 0.5   0.5 0.15 0 0.3   0 0 0 0.01]], 160, 0, 50, [[groundflash]]),
	},
	["hero-crit"] = {
		sparks = sparks([[1 1 1 1   1 0.3 0.2 0.8   0.3 0 0 0.2   0 0 0 0]], 16, 12, 16, 8, { gravity = [[0, -0.2, 0]] }),
		flash = flash([[1 0.9 0.9 1   1 0.3 0.2 0.5   0 0 0 0]], 140, 8, nil, 30),
	},
	["hero-undying"] = {
		pillar = pillar([[0 0 0 0   1 0.5 0.15 0.8   1 0.25 0.05 0.5   0.4 0.05 0 0.15   0 0 0 0]], 2800, 170, 100),
		core = pillar(GOLD_PILLAR, 2000, 60, 80),
		ring = ring(RED_RING, 120, 42, 40),
		sparks = sparks(FIRE, 80, 14, 80, 16, { texture = [[flame]], gravity = [[0, 0.3, 0]] }),
		flash = flash([[1 0.8 0.4 1   1 0.3 0.1 0.6   0 0 0 0]], 900, 26),
	},
	["hero-static"] = {
		sparks = sparks(BLUE_SPARK, 10, 8, 12, 14, { texture = [[lightning]], pos = [[0, 30, 0]], gravity = [[0, 0, 0]] }),
	},
	-- ability cast marker on the target area
	["hero-target"] = {
		ring = ring([[1 0.3 0.2 0.8   1 0.1 0.05 0.4   0 0 0 0.01]], 600, -8, 40),
	},
}
