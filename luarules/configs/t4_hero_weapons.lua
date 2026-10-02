-- Custom heroes (denysfast/bar-game), v19: hero weapons - damage types, base stats, number formatting. Included by
-- luarules/configs/t4_heroes.lua, which passes the shared table H. The per-weapon trees of v14-v18 (weapon kinds,
-- tracks, perks, visual step copies) are gone: the five stats (H.stats) apply to every weapon of a hero at once.
local H = ...

-- rounding of an amount to a readable number
local function nice(v, minimum)
	local a = math.abs(v)
	local step
	if a >= 5000 then
		step = 100
	elseif a >= 1000 then
		step = 50
	elseif a >= 200 then
		step = 10
	elseif a >= 50 then
		step = 5
	elseif a >= 10 then
		step = 1
	elseif a >= 1 then
		step = 0.5
	else
		step = 0.05
	end
	local r = math.floor(a / step + 0.5) * step
	return math.max(minimum or 0, r)
end
H.nice = nice

local function num(v)
	if math.abs(v) >= 100 or v == math.floor(v) then
		return string.format("%d", math.floor(v + 0.5))
	end
	return string.format("%.1f", v)
end
H.fmtAmount = num

-- Damage types (SPEC section 6): every weapondef is classified once. Items add `dtype = { <type> = fraction }`.
-- Works on runtime WeaponDefs entries (type, name, paralyzer) and on weapondef tables of the unitdef phase
-- (weapontype, name, paralyzer).
H.damageTypes = { "electric", "plasma", "rocket", "laser", "flame", "rail", "emp" }
local typeCache = {}
function H.damageType(wd)
	if not wd then
		return "plasma"
	end
	if wd.id and typeCache[wd.id] then
		return typeCache[wd.id]
	end
	local t = wd.type or wd.weapontype or ""
	local name = string.lower((wd.name or "") .. " " .. (wd.description or ""))
	local cp = wd.customParams or wd.customparams or {}
	local out
	if wd.paralyzer then
		out = "emp"
	elseif t == "LightningCannon" or name:find("lightning") or name:find("thunder") then
		out = "electric"
	elseif t == "BeamLaser" or t == "LaserCannon" then
		out = (name:find("rail") or name:find("gauss")) and "rail" or "laser"
	elseif t == "Flame" then
		out = "flame"
	elseif t == "MissileLauncher" or t == "StarburstLauncher" or t == "TorpedoLauncher" or name:find("rocket") or name:find("missile") then
		out = "rocket"
	elseif name:find("rail") or name:find("sniper") or name:find("gauss") or cp.overpenetrate then
		out = "rail"
	else
		out = "plasma"
	end
	if wd.id then
		typeCache[wd.id] = out
	end
	return out
end

-- base stats of the real weapons of a hero (LuaRules / LuaUI; WeaponDefNames needed): a list of
-- { key, name, damage, range, reload, aoe, burst, projectiles, paralyzer, type, dtype } in the order of the hero's
-- `weapons` (the keys of its config), each weapondef <hero>_<key>
local baseCache = {}
function H.weaponBases(heroName)
	if baseCache[heroName] then
		return baseCache[heroName]
	end
	local hero = H.heroes[heroName]
	if not hero or not WeaponDefNames then
		return {}
	end
	local out = {}
	for _, w in ipairs(hero.weapons or {}) do
		for _, key in ipairs(w.keys or {}) do
			local wd = WeaponDefNames[heroName .. "_" .. key]
			if wd then
				local dmg = wd.damages and wd.damages[0] or 0
				out[#out + 1] = {
					key = key, name = w.name, damage = dmg, range = wd.range, reload = wd.reload,
					aoe = wd.damageAreaOfEffect or 0, burst = wd.salvoSize or 1, projectiles = wd.projectiles or 1,
					paralyzer = wd.paralyzer, type = wd.type, dtype = H.damageType(wd),
				}
			end
		end
	end
	baseCache[heroName] = out
	return out
end
