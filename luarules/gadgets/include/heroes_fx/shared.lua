-- Hero FX shared helpers (synced + unsynced): palette, option (de)serialisation for SendToUnsynced,
-- and the pure orb position functions. Loaded by luarules/gadgets/fx_t4_heroes.lua.

local S = {}

local mathSin, mathCos, mathPi = math.sin, math.cos, math.pi

-- Named colours usable wherever an opts.color is expected ({r,g,b,a} also works).
S.palette = {
	electric = { 0.45, 0.72, 1.0, 1.0 },
	lightning = { 0.55, 0.78, 1.0, 1.0 },
	cyan = { 0.3, 0.95, 1.0, 1.0 },
	emp = { 0.55, 0.8, 1.0, 1.0 },
	red = { 1.0, 0.16, 0.1, 1.0 },
	rage = { 1.0, 0.12, 0.08, 1.0 },
	laser = { 1.0, 0.22, 0.12, 1.0 },
	orange = { 1.0, 0.5, 0.12, 1.0 },
	fire = { 1.0, 0.42, 0.08, 1.0 },
	heat = { 1.0, 0.38, 0.1, 1.0 },
	gold = { 1.0, 0.78, 0.3, 1.0 },
	holy = { 1.0, 0.88, 0.55, 1.0 },
	green = { 0.35, 1.0, 0.45, 1.0 },
	heal = { 0.4, 1.0, 0.55, 1.0 },
	toxic = { 0.6, 1.0, 0.2, 1.0 },
	purple = { 0.72, 0.38, 1.0, 1.0 },
	void = { 0.55, 0.25, 1.0, 1.0 },
	shield = { 0.35, 0.68, 1.0, 1.0 },
	cloak = { 0.6, 0.85, 1.0, 1.0 },
	white = { 1.0, 1.0, 1.0, 1.0 },
	stone = { 0.55, 0.53, 0.5, 1.0 },
	ice = { 0.6, 0.85, 1.0, 1.0 },
	shadow = { 0.25, 0.2, 0.35, 1.0 },
	fog = { 0.7, 0.72, 0.75, 1.0 },
}

-- Resolve opts.color (name | {r,g,b[,a]} | nil) into r,g,b,a with a default.
function S.color(c, default)
	if type(c) == "string" then
		c = S.palette[c]
	end
	if type(c) ~= "table" then
		c = S.palette[default or "electric"] or S.palette.electric
	end
	return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
end

-- opts table -> compact string (numbers, strings, booleans, number arrays). Used by the synced half.
local tconcat = table.concat
function S.encode(opts)
	if type(opts) ~= "table" then
		return ""
	end
	local parts = {}
	local n = 0
	for k, v in pairs(opts) do
		local tv = type(v)
		local s
		if tv == "number" then
			s = k .. "=" .. v
		elseif tv == "string" then
			s = k .. "=$" .. v
		elseif tv == "boolean" then
			s = k .. (v and "=!t" or "=!f")
		elseif tv == "table" then
			s = k .. "=#" .. tconcat(v, ",")
		end
		if s then
			n = n + 1
			parts[n] = s
		end
	end
	return tconcat(parts, ";")
end

function S.decode(s)
	local o = {}
	if type(s) ~= "string" or s == "" then
		return o
	end
	for k, v in s:gmatch("([^=;]+)=([^;]*)") do
		local c = v:sub(1, 1)
		if c == "$" then
			o[k] = v:sub(2)
		elseif c == "#" then
			local t = {}
			for num in v:sub(2):gmatch("[^,]+") do
				t[#t + 1] = tonumber(num)
			end
			o[k] = t
		elseif v == "!t" then
			o[k] = true
		elseif v == "!f" then
			o[k] = false
		else
			o[k] = tonumber(v)
		end
	end
	return o
end

-- Orb defaults (shared by Lua and the shaders' fxOrbOffset)
S.ORB_HEIGHT = 70
S.ORB_SPEED = 0.35 -- revolutions per second
local TAU = 2 * mathPi

-- Offset of orb #index (0-based) of an orb group relative to its anchor at sim frame `frame`.
function S.orbOffset(opts, frame, index)
	opts = opts or {}
	local count = opts.count or 1
	local orbit = opts.orbit or 0
	local h = opts.height or S.ORB_HEIGHT
	local speed = opts.speed or S.ORB_SPEED
	local phase = (opts.phase or 0) + (index or 0) * TAU / count
	local a = phase + frame * speed * TAU / 30
	local bob = mathSin(frame * 0.07 + phase) * 4
	return mathCos(a) * orbit, h + bob, mathSin(a) * orbit
end

-- GG.HeroFX.orbPos(unitID, opts, frame, index) -> x, y, z (nil if the unit is gone).
-- Pure and deterministic: safe in synced code (e.g. start a bolt at the orb).
function S.orbPos(unitID, opts, frame, index)
	local x, y, z = Spring.GetUnitPosition(unitID)
	if not x then
		return nil
	end
	local dx, dy, dz = S.orbOffset(opts, frame or Spring.GetGameFrame(), index)
	return x + dx, y + dy, z + dz
end

-- Same for orbs anchored at a map point (attachPoint).
function S.orbPointPos(px, pz, opts, frame, index)
	local py = Spring.GetGroundHeight(px, pz)
	local dx, dy, dz = S.orbOffset(opts, frame or Spring.GetGameFrame(), index)
	return px + dx, py + dy, pz + dz
end

return S
