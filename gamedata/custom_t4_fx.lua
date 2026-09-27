-- Custom T4 heroes (denysfast/bar-game): scaled copies of CEG effects.
--
-- The heroes are 1.6-2.2x bigger models of T3 units, so their stock muzzle flashes, trails and
-- explosions looked like toys. explosions_post.lua calls FX.generate(ExplosionDefs): every CEG in
-- FX.sources gets a copy per scale in FX.scales, named "<name>--x<scale>" (FX.name), plus the one-off
-- pairs in FX.extra. The unitdefs (gamedata/custom_t4.lua) rename their references through FX.ref.
-- Both sides read the same lists here, so they always agree on which names exist.
--
-- Scaling of a spawner's properties: sizes x s, speeds and growth x s^0.65, lifetimes x s^0.35
-- (so distances travelled still grow ~ x s), gravity x s^0.3, particle counts x s^0.5. String
-- expressions are scaled only when they are plain sums (numbers, rN, iN, dN terms); anything with
-- other operators is left as it is. Nested CExpGenSpawner children are scaled recursively.

local FX = {}

FX.scales = { 2.2, 2.5 }

-- stock CEGs used by the hero weapons and unit scripts
FX.sources = {
	"footstep-large", "footstep-huge", "footstep-medium", "crusherkrog",
	"genericshellexplosion-small", "genericshellexplosion-medium", "genericshellexplosion-large",
	"genericshellexplosion-huge", "genericshellexplosion-large-bomb", "genericshellexplosion-medium-beam",
	"genericshellexplosion-catapult", "genericshellexplosion-tiny-aa",
	"genericshellexplosion-huge-lightning", "genericshellexplosion-large-lightning-thor",
	"laserhit-large-blue", "laserhit-medium-red", "laserhit-small-red", "laserhit-emp",
	"barrelshot-large-impulse", "barrelshot-huge", "barrelshot-lightning", "barrelshot-medium",
	"barrelshot-small", "barrelshot-small-impulse", "barrelshot-tiny", "barrelshot-flak",
	"rocketflare-large", "pilotlightxl", "burnblackbig", "burnblackxl", "flak", "flakshard",
	"heatray-large", "heatray-huge", "ministarfire-explosion", "starfire-explosion", "plasmahit-sparkonly",
	"missiletrailsmall-starburst", "missiletrailmedium-starburst", "missiletrailsmall-red",
	"missiletrailaa", "missiletrailtiny", "cruisemissiletrail-emp", "cruisemissiletrail-tacnuke",
	"arty-huge", "gausscannonprojectile", "burnflamexl", "demonflame", "starfire-small", "ministarfire",
	"railgun", "flaktrailaa", "flaktrailaamg",
}

-- one-off sizes of the big effects the abilities use
FX.extra = {
	{ "newnuketac", 0.45 }, { "newnuketac", 0.7 }, { "newnuketac", 1.5 },
	{ "genericshellexplosion-huge", 1.6 }, { "genericshellexplosion-huge", 4 },
	{ "genericshellexplosion-huge-lightning", 4 }, { "genericshellexplosion-huge-lightning", 1.6 },
	{ "lightning_stormbig", 2 },
	{ "commander-levelup", 3 }, { "commander-levelup", 5 }, { "shockwaveceg", 0.5 },
	{ "heatray-huge", 3 }, { "starfire-explosion", 2 }, { "crusherkrog", 5 },
	{ "genericshellexplosion-medium", 3 },
}

local function fmt(s)
	local t = string.format("%.2f", s):gsub("0+$", ""):gsub("%.$", "")
	return t
end

function FX.name(src, scale)
	return src .. "--x" .. fmt(scale)
end

local known = {}
for _, n in ipairs(FX.sources) do
	for _, s in ipairs(FX.scales) do
		known[FX.name(n, s)] = true
	end
end
for _, p in ipairs(FX.extra) do
	known[FX.name(p[1], p[2])] = true
end

-- the scaled name of a CEG reference, or the reference itself when no such copy is generated.
-- Accepts "custom:<name>" and bare names (cegtag).
function FX.ref(ref, scale)
	if type(ref) ~= "string" or ref == "" then
		return ref
	end
	local prefix, name = ref:match("^(custom:)(.+)$")
	if not prefix then
		prefix, name = "", ref
	end
	local best, bestD
	for _, s in ipairs(FX.scales) do
		local d = math.abs(s - scale)
		if not bestD or d < bestD then
			best, bestD = s, d
		end
	end
	local scaled = FX.name(name, best)
	if known[scaled] then
		return prefix .. scaled
	end
	return ref
end

-- the name of a one-off copy (FX.extra), "custom:" prefixed
function FX.custom(src, scale)
	return "custom:" .. FX.name(src, scale)
end

------------------------------------------------------------------------------- scaling

local EXP = {
	size = 1, particlesize = 1, particlesizespread = 1, length = 1, width = 1, flashsize = 1,
	radius = 1, pos = 1, ringsize = 1, maxsize = 1, startsize = 1, endsize = 1,
	sizegrowth = 0.65, particlespeed = 0.65, particlespeedspread = 0.65, lengthgrowth = 0.65,
	circlegrowth = 0.65, speed = 0.65, expansionspeed = 0.65,
	ttl = 0.35, particlelife = 0.35, particlelifespread = 0.35, life = 0.35,
	gravity = 0.3,
}

local function scaleNumberString(str, mult)
	-- vectors are comma separated, each component a whitespace separated sum
	local out = {}
	for comp in (str .. ","):gmatch("([^,]*),") do
		local tokens = {}
		for tok in comp:gmatch("%S+") do
			local op, num = tok:match("^([ridRID]?)(%-?[%d%.]+)$")
			if not num or not tonumber(num) then
				return nil
			end
			tokens[#tokens + 1] = op .. (string.format("%.4f", tonumber(num) * mult):gsub("0+$", ""):gsub("%.$", ""))
		end
		out[#out + 1] = table.concat(tokens, " ")
	end
	return table.concat(out, ", ")
end

local function scaleValue(v, mult)
	if type(v) == "number" then
		return v * mult
	elseif type(v) == "string" then
		return scaleNumberString(v, mult) or v
	end
	return v
end

local function deepcopy(v)
	if type(v) ~= "table" then
		return v
	end
	local o = {}
	for k, x in pairs(v) do
		o[k] = deepcopy(x)
	end
	return o
end

-- ExplosionDefs keys can be any case; the engine matches them case-insensitively
local function findDef(defs, name)
	if defs[name] then
		return defs[name], name
	end
	local lname = name:lower()
	for k, v in pairs(defs) do
		if type(k) == "string" and k:lower() == lname then
			return v, k
		end
	end
end

local function scaleDef(defs, src, scale, depth)
	local newName = FX.name(src, scale)
	if defs[newName] or depth > 4 then
		return newName
	end
	local def = findDef(defs, src)
	if type(def) ~= "table" then
		return nil
	end
	local copy = deepcopy(def)
	defs[newName] = copy -- before the children, in case of cycles
	for spawnerName, spawner in pairs(copy) do
		if type(spawner) == "table" then
			if type(spawner.count) == "number" and scale > 1 then
				spawner.count = math.max(1, math.floor(spawner.count * scale ^ 0.5 + 0.5))
			end
			local props = spawner.properties
			if type(props) ~= "table" and spawnerName:lower() == "groundflash" then
				props = spawner -- the old-style groundflash keeps its values on the spawner itself
			end
			if type(props) == "table" then
				for k, v in pairs(props) do
					local lk = type(k) == "string" and k:lower()
					if lk == "explosiongenerator" and type(v) == "string" then
						local child = v:match("^custom:(.+)$")
						if child then
							local scaled = scaleDef(defs, child, scale, depth + 1)
							if scaled then
								props[k] = "custom:" .. scaled
							end
						end
					elseif lk == "numparticles" and scale > 1 then
						props[k] = scaleValue(v, scale ^ 0.5)
					elseif lk and EXP[lk] then
						props[k] = scaleValue(v, scale ^ EXP[lk])
					end
				end
			end
		end
	end
	return newName
end

function FX.generate(defs)
	local made, missing = 0, {}
	for _, src in ipairs(FX.sources) do
		for _, s in ipairs(FX.scales) do
			if scaleDef(defs, src, s, 0) then
				made = made + 1
			else
				missing[#missing + 1] = src
			end
		end
	end
	for _, p in ipairs(FX.extra) do
		if scaleDef(defs, p[1], p[2], 0) then
			made = made + 1
		else
			missing[#missing + 1] = p[1]
		end
	end
	if Spring and Spring.Echo and #missing > 0 then
		Spring.Echo("[t4fx] missing source CEGs: " .. table.concat(missing, ", "))
	end
	return made
end

return FX
