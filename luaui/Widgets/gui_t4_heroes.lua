--------------------------------------------------------------------------------
--
--  file:    gui_t4_heroes.lua
--  brief:   Warcraft 3 style UI of the custom T4 heroes (denysfast/bar-game):
--           * hero buttons at the top left (portrait, level, health, experience, unspent points,
--             fallen heroes with their revive level and price)
--           * the hero console at the bottom when a hero is selected: portrait, name, level and
--             experience, stats, nine item slots (weapon / defense / utility), the command card with the abilities
--             (cooldown sweeps, hotkeys Q W R) and the upgrade window (weapon trees, plating,
--             servos, abilities, each rank for a talent point and metal)
--           * the item picker (click a slot: equip from the team stash), the team stash window
--           * items lying on the ground, levels above heroes, aura rings, floating texts
--  The rules live in luarules/gadgets/unit_t4_heroes.lua, the design data in luarules/configs/t4_heroes.lua,
--  the art in bitmaps/t4heroes/ (generated with content-master, see CUSTOM.md).
--  Licensed under the terms of the GNU GPL, v2 or later.
--
--------------------------------------------------------------------------------

local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name = "T4 Heroes",
		desc = "Warcraft-style hero buttons, hero console, inventory, upgrade window and ground items of the custom T4 heroes",
		author = "denysfast",
		date = "2026-09-28",
		license = "GNU GPL, v2 or later",
		layer = 5,
		enabled = true,
	}
end

local H = VFS.Include("luarules/configs/t4_heroes.lua")

local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetTeamRulesParam = Spring.GetTeamRulesParam
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitHealth = Spring.GetUnitHealth
local spGetGameFrame = Spring.GetGameFrame
local spWorldToScreenCoords = Spring.WorldToScreenCoords
local spIsUnitInView = Spring.IsUnitInView
local spValidUnitID = Spring.ValidUnitID
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam
local spIsUnitAllied = Spring.IsUnitAllied
local floor, max, min, sin, cos, pi = math.floor, math.max, math.min, math.sin, math.cos, math.pi

local ART = "bitmaps/t4heroes/"

local heroDefIDs = {} -- unitDefID -> hero name
local heroDefList = {}
for udid, ud in pairs(UnitDefs) do
	if H.heroes[ud.name] and ud.customParams.t4_hero then
		heroDefIDs[udid] = ud.name
		heroDefList[#heroDefList + 1] = udid
	end
end

local vsx, vsy = Spring.GetViewGeometry()
local font
local uiScale = 1

local tracked = {}  -- unitID -> hero name, every hero this client can see
local floating = {}
local roster = {}   -- rows of the team's heroes
local selectedHero  -- unitID shown in the console
local boxes = {}    -- clickable regions of the last frame: { x1, y1, x2, y2, fn, tip, fnRight }
local hoverTip
local showUpgrades = false
local groundItems = {} -- { id, item, x, z }
local groundStr
local picker          -- { uid, slot }: the item picker popup over a slot
local showStash = false
local stashSeenVer = 0  -- the stash version the player has looked at (the Stash button glows on new items)
local slotRects = {}    -- slot -> { x1, y1, x2, y2 } of the last frame (scenes, the picker anchor)

-- colors
local GOLD = { 1, 0.82, 0.25, 1 }
local WHITE = { 1, 1, 1, 1 }
local GREY = { 0.6, 0.6, 0.6, 1 }
local DARK = { 0.35, 0.35, 0.35, 1 }
local RED = { 1, 0.35, 0.3, 1 }
local GREEN = { 0.45, 1, 0.45, 1 }
local BLUE = { 0.5, 0.75, 1, 1 }
local ORANGE = { 1, 0.6, 0.25, 1 }

local function getFont()
	if WG.fonts and WG.fonts.getFont then
		font = WG.fonts.getFont(2, 1.2)
	else
		font = gl.LoadFont("fonts/Exo2-SemiBold.otf", 24, 4, 1.5)
	end
	return font
end

function widget:ViewResize()
	vsx, vsy = Spring.GetViewGeometry()
	uiScale = Spring.GetConfigFloat("ui_scale", 1)
	font = nil
end

local function heroTitle(name)
	local cfg = H.heroes[name]
	return cfg and cfg.title or name
end

local function shortName(name)
	local ud = UnitDefNames[name]
	return ud and (ud.translatedHumanName or ud.humanName) or name
end

local function fmtNum(v)
	if v >= 1e6 then
		return string.format("%.1fM", v / 1e6)
	elseif v >= 1e4 then
		return string.format("%dk", floor(v / 1000 + 0.5))
	elseif v >= 1000 then
		return string.format("%.1fk", v / 1000)
	end
	return tostring(floor(v + 0.5))
end

---------------------------------------------------------------------------- tracking

local function refreshTracked()
	for uid in pairs(tracked) do
		if not spValidUnitID(uid) then
			tracked[uid] = nil
		end
	end
	for _, teamID in ipairs(Spring.GetTeamList()) do
		for _, uid in ipairs(Spring.GetTeamUnitsByDefs(teamID, heroDefList) or {}) do
			tracked[uid] = heroDefIDs[spGetUnitDefID(uid)]
		end
	end
end

local function myTeam()
	return Spring.GetMyTeamID()
end

local function refreshRoster()
	roster = {}
	local team = myTeam()
	local alive = {}
	for _, uid in ipairs(Spring.GetTeamUnitsByDefs(team, heroDefList) or {}) do
		local _, _, _, _, bp = spGetUnitHealth(uid)
		local name = heroDefIDs[spGetUnitDefID(uid)]
		if name then
			alive[name] = { uid = uid, building = bp and bp < 1, progress = bp }
		end
	end
	for _, name in ipairs(H.order) do
		if UnitDefNames[name] then
			local deadLevel = spGetTeamRulesParam(team, "hero_dead_" .. name) or 0
			local built = (spGetTeamRulesParam(team, "hero_built_" .. name) or 0) > 0
			local a = alive[name]
			if a or deadLevel > 0 or built then
				roster[#roster + 1] = {
					name = name, uid = a and a.uid, building = a and a.building, progress = a and a.progress,
					deadLevel = deadLevel, revive = spGetTeamRulesParam(team, "hero_revive_" .. name) or 0,
				}
			end
		end
	end
end

local function pickSelected()
	local keep
	for _, uid in ipairs(Spring.GetSelectedUnits()) do
		if heroDefIDs[spGetUnitDefID(uid) or -1] then
			local _, _, _, _, bp = spGetUnitHealth(uid)
			if bp and bp >= 1 then
				if uid == selectedHero then
					return
				end
				keep = keep or uid
			end
		end
	end
	selectedHero = keep
	if not keep then
		showUpgrades = false
	end
end

local function refreshGround()
	local str = Spring.GetGameRulesParam("hero_ground")
	if str == groundStr then
		return
	end
	groundStr = str
	groundItems = {}
	for id, idx, x, z in (str or ""):gmatch("(%d+):(%d+):(%-?%d+):(%-?%d+)") do
		local item = H.itemOrder[tonumber(idx)]
		if item then
			groundItems[#groundItems + 1] = { id = tonumber(id), item = item, x = tonumber(x), z = tonumber(z) }
		end
	end
end

---------------------------------------------------------------------------- actions

local function learn(uid, key)
	Spring.SendLuaRulesMsg("t4hero:learn:" .. uid .. ":" .. key)
	Spring.PlaySoundFile("sounds/ui/beep6.wav", 0.5, "ui")
end

local function castAbility(uid, key)
	local b = H.heroes[heroDefIDs[spGetUnitDefID(uid)]][key]
	if not b or not b.cmd then
		return
	end
	if b.target then
		-- targeted: arm the command, the player clicks the map / a unit
		Spring.SelectUnitArray({ uid })
		local idx = Spring.GetCmdDescIndex(b.cmd)
		if idx then
			Spring.SetActiveCommand(idx)
		end
	else
		Spring.GiveOrderToUnit(uid, b.cmd, {}, 0)
	end
end

local function toggleAutocast(uid)
	local on = (spGetUnitRulesParam(uid, "hero_autocast") or 1) == 1
	Spring.GiveOrderToUnit(uid, 36100, { on and 0 or 1 }, 0)
end

local function focusUnit(uid, camera)
	Spring.SelectUnitArray({ uid })
	if camera then
		local x, y, z = spGetUnitPosition(uid)
		if x then
			Spring.SetCameraTarget(x, y, z, 0.3)
		end
	end
end

local lastRosterClick = { uid = nil, t = nil }

---------------------------------------------------------------------------- drawing helpers

local function rect(x1, y1, x2, y2, c, a)
	gl.Color(c[1], c[2], c[3], a or c[4] or 1)
	gl.Rect(x1, y1, x2, y2)
end

local function frame(x1, y1, x2, y2, c, w)
	w = w or 2
	rect(x1, y1, x2, y1 + w, c)
	rect(x1, y2 - w, x2, y2, c)
	rect(x1, y1, x1 + w, y2, c)
	rect(x2 - w, y1, x2, y2, c)
end

-- a Warcraft-like panel: dark stone fill, bronze double border
local function panel(x1, y1, x2, y2)
	gl.Color(0.05, 0.05, 0.07, 0.86)
	gl.Rect(x1, y1, x2, y2)
	gl.BeginEnd(GL.QUADS, function()
		gl.Color(0.16, 0.14, 0.12, 0.6)
		gl.Vertex(x1, y2)
		gl.Vertex(x2, y2)
		gl.Color(0.02, 0.02, 0.03, 0.0)
		gl.Vertex(x2, (y1 + y2) / 2)
		gl.Vertex(x1, (y1 + y2) / 2)
	end)
	frame(x1, y1, x2, y2, { 0.45, 0.34, 0.16, 1 }, 3)
	frame(x1 + 4, y1 + 4, x2 - 4, y2 - 4, { 0.22, 0.17, 0.09, 1 }, 1)
end

local function tex(path, x1, y1, x2, y2, r, g, b, a)
	gl.Color(r or 1, g or 1, b or 1, a or 1)
	gl.Texture(path)
	gl.TexRect(x1, y1, x2, y2)
	gl.Texture(false)
end

local function bar(x1, y1, x2, y2, frac, c, bg)
	rect(x1, y1, x2, y2, bg or { 0, 0, 0, 0.7 })
	if frac > 0 then
		rect(x1 + 1, y1 + 1, x1 + 1 + (x2 - x1 - 2) * min(1, frac), y2 - 1, c)
		gl.BeginEnd(GL.QUADS, function()
			gl.Color(1, 1, 1, 0.25)
			gl.Vertex(x1 + 1, y2 - 1)
			gl.Vertex(x1 + 1 + (x2 - x1 - 2) * min(1, frac), y2 - 1)
			gl.Color(1, 1, 1, 0)
			gl.Vertex(x1 + 1 + (x2 - x1 - 2) * min(1, frac), (y1 + y2) / 2)
			gl.Vertex(x1 + 1, (y1 + y2) / 2)
		end)
	end
end

-- the dark clock sweep of a cooldown over an icon, frac = share still to wait
local function sweep(x1, y1, x2, y2, frac)
	if frac <= 0 then
		return
	end
	local cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
	local r = (x2 - x1) * 0.75
	gl.Scissor(x1, y1, x2 - x1, y2 - y1)
	gl.Color(0, 0, 0, 0.66)
	gl.BeginEnd(GL.TRIANGLE_FAN, function()
		gl.Vertex(cx, cy)
		local steps = 40
		local a0 = pi / 2
		for i = 0, steps do
			local a = a0 + (i / steps) * frac * 2 * pi
			gl.Vertex(cx + cos(a) * r, cy + sin(a) * r)
		end
	end)
	gl.Scissor(false)
end

local function text(str, x, y, size, c, opts)
	font:SetTextColor(c[1], c[2], c[3], c[4] or 1)
	font:Print(str, x, y, size, opts or "o")
end

local function addBox(x1, y1, x2, y2, fn, tip, fnRight)
	boxes[#boxes + 1] = { x1, y1, x2, y2, fn, tip, fnRight }
end

local function hovered(x1, y1, x2, y2)
	local mx, my = Spring.GetMouseState()
	return mx >= x1 and mx <= x2 and my >= y1 and my <= y2
end

-- an icon button: art, a frame that lights up under the mouse, disabled -> greyed
local function iconButton(path, x1, y1, x2, y2, enabled, border, fn, tip, fnRight)
	local hov = hovered(x1, y1, x2, y2)
	rect(x1 - 2, y1 - 2, x2 + 2, y2 + 2, { 0, 0, 0, 0.9 })
	if path then
		local k = enabled and (hov and 1.15 or 1) or 0.38
		tex(path, x1, y1, x2, y2, k, k, k, 1)
	end
	frame(x1 - 2, y1 - 2, x2 + 2, y2 + 2, hov and enabled and { 1, 0.9, 0.5, 1 } or (border or { 0.45, 0.34, 0.16, 1 }), 2)
	addBox(x1, y1, x2, y2, enabled and fn or nil, tip, fnRight)
	return hov
end

---------------------------------------------------------------------------- tooltips (rich text)

local function rankLine(name, key, rank)
	local b = H.branch(name, key)
	if not b then
		return ""
	end
	if b.text then
		local cur = rank > 0 and b.text[rank] or nil
		local nxt = b.text[rank + 1]
		local s = ""
		if cur then
			s = s .. "\n\255\120\255\120Now: " .. cur
		end
		if nxt then
			s = s .. "\n\255\255\210\080Next: " .. nxt
		end
		return s
	end
	return ""
end

local function learnTip(uid, name, key)
	local b = H.branch(name, key)
	local rank = spGetUnitRulesParam(uid, "hero_rank_" .. key) or 0
	local maxRank = H.maxRank(name, key)
	local s = "\255\255\210\064" .. b.name .. "\255\255\255\255  (" .. rank .. "/" .. maxRank .. ")\n" .. (b.desc or "")
	s = s .. rankLine(name, key, rank)
	if (key == "a1" or key == "a2" or key == "ult") and b.kind then
		-- ability damage / healing grow with the hero's level (the gadget's abilityPower)
		local lvl = spGetUnitRulesParam(uid, "hero_level") or 1
		s = s .. string.format("\n\255\200\160\255Ability power x%.2f at level %d", 1 + (H.ABILITY_POWER_PER_LEVEL or 0.015) * (lvl - 1), lvl)
	end
	if rank < maxRank then
		local req = H.reqLevel(name, key, rank + 1)
		local cost = H.metalCost(name, key, rank + 1)
		s = s .. string.format("\n\255\200\200\200Rank %d: level %d, 1 point, %s metal", rank + 1, req, fmtNum(cost))
	end
	return s
end

local function colorCode(c)
	return "\255" .. string.char(max(1, floor(c[1] * 255))) .. string.char(max(1, floor(c[2] * 255))) .. string.char(max(1, floor(c[3] * 255)))
end

local function itemTip(item)
	local it = H.items[item]
	local c = H.rarities[it.rarity].color
	local cat = H.itemCategories[it.category]
	return string.format("%s%s\255\255\255\255  %s%s\255\180\180\180 %s\n\255\255\255\255%s", colorCode(c), it.name,
		colorCode(cat.color), cat.label, it.rarity, it.desc)
end

---------------------------------------------------------------------------- hero buttons (top left)

local function drawHeroButtons()
	if #roster == 0 then
		return
	end
	local size = floor(vsy * 0.062 * uiScale)
	local gap = floor(size * 0.42)
	-- right of the minimap, like the hero icons of Warcraft 3 at the top left
	local x1 = floor(vsy * 0.012)
	local y = vsy - floor(vsy * 0.012)
	local _, _, mmW = Spring.GetMiniMapGeometry()
	if mmW and mmW > 0 then
		x1 = mmW + floor(vsy * 0.012)
	end
	local f = spGetGameFrame()
	for _, r in ipairs(roster) do
		local y2 = y
		local y1 = y2 - size
		local xa, xb = x1, x1 + size
		local portrait = ART .. "portrait_" .. r.name .. ".png"
		if r.uid and not r.building then
			local lvl = spGetUnitRulesParam(r.uid, "hero_level") or 1
			local xp = spGetUnitRulesParam(r.uid, "hero_xp") or 0
			local pts = spGetUnitRulesParam(r.uid, "hero_points") or 0
			local hp, maxHp = spGetUnitHealth(r.uid)
			local sel = r.uid == selectedHero
			if pts > 0 then
				local glow = 0.5 + 0.5 * sin(f * 0.2)
				rect(xa - 5, y1 - 5, xb + 5, y2 + 5, { 1, 0.8, 0.2, 0.35 + 0.35 * glow })
			end
			iconButton(portrait, xa, y1, xb, y2, true, sel and GOLD or nil, function()
				local now = Spring.GetTimer()
				local dbl = lastRosterClick.uid == r.uid and lastRosterClick.t and Spring.DiffTimers(now, lastRosterClick.t) < 0.4
				focusUnit(r.uid, dbl)
				lastRosterClick.uid, lastRosterClick.t = r.uid, now
			end, string.format("%s - level %d%s\nClick: select, double click: go to", heroTitle(r.name), lvl,
				pts > 0 and ("\n\255\255\210\064" .. pts .. " skill points to spend") or ""))
			-- level badge
			local bs = size * 0.36
			rect(xb - bs, y1, xb, y1 + bs, { 0, 0, 0, 0.85 })
			frame(xb - bs, y1, xb, y1 + bs, GOLD, 1)
			text(tostring(lvl), xb - bs / 2, y1 + bs * 0.2, bs * 0.66, GOLD, "co")
			bar(xa, y1 - size * 0.14, xb, y1 - size * 0.04, hp and maxHp and hp / maxHp or 0, { 0.2, 0.9, 0.25, 1 })
			bar(xa, y1 - size * 0.25, xb, y1 - size * 0.16, xp, { 0.55, 0.35, 1, 1 })
		elseif r.uid and r.building then
			iconButton(portrait, xa, y1, xb, y2, false, nil, nil,
				r.deadLevel > 0 and string.format("Reviving %s at level %d", heroTitle(r.name), r.deadLevel) or string.format("Building %s", heroTitle(r.name)))
			bar(xa, y1 - size * 0.14, xb, y1 - size * 0.04, r.progress or 0, { 0.5, 0.75, 1, 0.9 })
		else
			iconButton(portrait, xa, y1, xb, y2, false, { 0.5, 0.1, 0.1, 1 }, nil,
				string.format("%s has fallen at level %d.\nRebuild it at the hero altar to revive it (%s metal).", heroTitle(r.name), r.deadLevel, fmtNum(r.revive)))
			text("x", (xa + xb) / 2, y1 + size * 0.2, size * 0.7, { 0.8, 0.1, 0.1, 0.8 }, "co")
			text(tostring(r.deadLevel), xb - size * 0.18, y1 + size * 0.05, size * 0.28, RED, "co")
		end
		y = y1 - gap
	end
end

---------------------------------------------------------------------------- items: slots, picker, team stash
-- Nine slots in three rows (H.itemCategories: weapon 1-3, defense 4-6, utility 7-9). Everything picked up goes
-- to the team stash (team rules params hero_stash_n / hero_stash_<i>); a click on a slot opens the picker of the
-- stash items of its category, a right click puts the worn item back into the stash.

local stashCache = { team = -1, ver = -1, list = {} }

local function stashTeam(uid)
	local team = uid and spGetUnitTeam(uid)
	if team and spIsUnitAllied(uid) then
		return team
	end
	return myTeam()
end

-- { { idx = <stash index>, item = <id> }, ... } of a team (cached by hero_stash_ver)
local function readStash(team)
	local ver = spGetTeamRulesParam(team, "hero_stash_ver") or 0
	if stashCache.team == team and stashCache.ver == ver then
		return stashCache.list, ver
	end
	local list = {}
	local n = spGetTeamRulesParam(team, "hero_stash_n") or 0
	for i = 1, n do
		local item = H.itemOrder[spGetTeamRulesParam(team, "hero_stash_" .. i) or 0]
		if item then
			list[#list + 1] = { idx = i, item = item }
		end
	end
	stashCache.team, stashCache.ver, stashCache.list = team, ver, list
	return list, ver
end

local function byRarity(a, b)
	local ra, rb = H.rarities[H.items[a.item].rarity].rank, H.rarities[H.items[b.item].rarity].rank
	if ra ~= rb then
		return ra > rb
	end
	if a.item ~= b.item then
		return H.items[a.item].name < H.items[b.item].name
	end
	return a.idx < b.idx
end

local function stashOf(team, cat)
	local out = {}
	for _, e in ipairs(readStash(team)) do
		if not cat or H.items[e.item].category == cat then
			out[#out + 1] = e
		end
	end
	table.sort(out, byRarity)
	return out
end

local function wornItem(uid, slot)
	return H.itemOrder[spGetUnitRulesParam(uid, "hero_item_" .. slot) or 0]
end

local function sendEquip(uid, slot, e)
	Spring.SendLuaRulesMsg(string.format("t4hero:equip:%d:%d_%d_%d", uid, slot, e.idx, H.itemIndex[e.item]))
	Spring.PlaySoundFile("sounds/ui/beep6.wav", 0.5, "ui")
end

local function sendUnequip(uid, slot)
	Spring.SendLuaRulesMsg("t4hero:unequip:" .. uid .. ":" .. slot)
	Spring.PlaySoundFile("sounds/ui/beep6.wav", 0.4, "ui")
end

local function sendUse(uid, slot)
	Spring.SendLuaRulesMsg("t4hero:use:" .. uid .. ":" .. slot)
end

local function openPicker(uid, slot)
	if picker and picker.uid == uid and picker.slot == slot then
		picker = nil
		return
	end
	picker = { uid = uid, slot = slot }
	showStash = false
	showUpgrades = false
end

local function itemCooldown(uid, slot, item, f)
	local act = H.items[item].active
	if not act then
		return 0, 1
	end
	local ready = spGetUnitRulesParam(uid, "hero_itemcd_" .. slot) or 0
	local len = spGetUnitRulesParam(uid, "hero_itemcdlen_" .. slot) or act.cooldown * 30
	return max(0, ready - f), max(1, len)
end

-- one item slot of the console
local function drawSlot(uid, own, slot, bx1, by1, bx2, by2, f)
	local cat = H.itemCategories[H.slotCategory[slot]]
	local cc = cat.color
	local item = wornItem(uid, slot)
	slotRects[slot] = { bx1, by1, bx2, by2 }
	local isPicked = picker and picker.uid == uid and picker.slot == slot
	local open = own and function() openPicker(uid, slot) end or nil
	if item then
		local it = H.items[item]
		local rc = H.rarities[it.rarity].color
		local on = spGetUnitRulesParam(uid, "hero_on_item" .. slot) or 0
		if on > f then
			local glow = 0.5 + 0.5 * sin(f * 0.35)
			rect(bx1 - 5, by1 - 5, bx2 + 5, by2 + 5, { 0.4, 1, 0.5, 0.35 + 0.4 * glow })
		end
		iconButton(ART .. "item_" .. item .. ".png", bx1, by1, bx2, by2, true, isPicked and GOLD or { rc[1], rc[2], rc[3], 1 }, open,
			itemTip(item) .. (own and ("\n\255\180\180\180Click: swap / " .. (it.active and "use / " or "") .. "unequip.  Right click: back to the stash") or ""),
			own and function() sendUnequip(uid, slot) end or nil)
		local left, len = itemCooldown(uid, slot, item, f)
		if left > 0 then
			sweep(bx1, by1, bx2, by2, left / len)
			text(tostring(floor(left / 30) + 1), (bx1 + bx2) / 2, by1 + (by2 - by1) * 0.3, (by2 - by1) * 0.4, WHITE, "co")
		elseif it.active then
			-- a small "ready" pip on active items
			local ps = (bx2 - bx1) * 0.18
			rect(bx2 - ps - 2, by2 - ps - 2, bx2 - 2, by2 - 2, { 0.4, 1, 0.5, 0.9 })
		end
	else
		local hov = own and hovered(bx1, by1, bx2, by2)
		rect(bx1, by1, bx2, by2, { cc[1] * 0.12, cc[2] * 0.12, cc[3] * 0.12, 0.85 })
		tex(ART .. cat.glyph .. ".png", bx1 + (bx2 - bx1) * 0.18, by1 + (by2 - by1) * 0.18, bx2 - (bx2 - bx1) * 0.18, by2 - (by2 - by1) * 0.18,
			1, 1, 1, hov and 0.45 or 0.22)
		frame(bx1 - 2, by1 - 2, bx2 + 2, by2 + 2, isPicked and GOLD or (hov and { 1, 0.9, 0.5, 1 } or { cc[1] * 0.45, cc[2] * 0.45, cc[3] * 0.45, 1 }), 2)
		addBox(bx1, by1, bx2, by2, open, string.format("%sEmpty %s slot\255\255\255\255\n%s", colorCode(cc), cat.label:lower(),
			own and "Click: equip an item from the team stash" or "Items drop from slain heroes and big enemies"))
	end
end

-- the nine slots and the Stash button inside the console rectangle x1..x2, y1..y2
local function drawInventory(uid, own, x1, y1, x2, y2)
	local f = spGetGameFrame()
	local th = (y2 - y1) * 0.16
	local rowsH = y2 - y1 - th
	local pitch = rowsH / 3
	local is = floor(pitch * 0.84)
	local glyph = floor(is * 0.5)
	local gap = floor((x2 - x1 - glyph - is * 3) / 3.5)
	gap = max(3, min(gap, floor(is * 0.2)))
	local total = glyph + gap + is * 3 + gap * 2
	local ox = floor(x1 + (x2 - x1 - total) / 2)
	-- title: "Items" and the Stash button
	local team = stashTeam(uid)
	local list, ver = readStash(team)
	text("Items", ox, y2 - th * 0.82, th * 0.62, GOLD)
	local sw = floor(is * 1.9)
	local sx2 = ox + total
	local sx1 = sx2 - sw
	local sy1, sy2 = floor(y2 - th * 0.95), floor(y2 - th * 0.08)
	local fresh = ver > stashSeenVer and #list > 0
	local glow = fresh and (0.5 + 0.5 * sin(f * 0.25)) or 0
	local hov = hovered(sx1, sy1, sx2, sy2)
	rect(sx1, sy1, sx2, sy2, showStash and { 0.3, 0.22, 0.05, 0.95 } or { 0.1 + 0.25 * glow, 0.08 + 0.18 * glow, 0.02, 0.95 })
	frame(sx1, sy1, sx2, sy2, hov and { 1, 0.9, 0.5, 1 } or GOLD, 1)
	text(string.format("Stash %d", #list), (sx1 + sx2) / 2, sy1 + (sy2 - sy1) * 0.22, (sy2 - sy1) * 0.62, fresh and GOLD or WHITE, "co")
	addBox(sx1, sy1, sx2, sy2, function()
		showStash = not showStash
		picker = nil
		if showStash then
			showUpgrades = false
		end
	end, string.format("Team stash: %d / %d items. Everything your heroes pick up lands here;\nopen it to see them all, click a slot to equip one.", #list, H.STASH_SIZE))
	for ci, catId in ipairs(H.categoryOrder) do
		local cat = H.itemCategories[catId]
		local cc = cat.color
		local ry2 = floor(y2 - th - (ci - 1) * pitch - (pitch - is) / 2)
		local ry1 = ry2 - is
		-- category tint and glyph
		rect(ox - 3, ry1 - 3, ox + total + 3, ry2 + 3, { cc[1], cc[2], cc[3], 0.07 })
		tex(ART .. cat.glyph .. ".png", ox, ry1 + (is - glyph) / 2, ox + glyph, ry1 + (is + glyph) / 2, 1, 1, 1, 0.9)
		addBox(ox, ry1, ox + glyph, ry2, nil, colorCode(cc) .. cat.label .. " items\255\255\255\255: " ..
			(catId == "weapon" and "damage, fire rate, blast, crits, procs" or catId == "defense" and "health, armor, regeneration, shields"
				or "range, speed, sight, cooldowns, auras, experience"))
		for k, slot in ipairs(cat.slots) do
			local bx1 = ox + glyph + gap + (k - 1) * (is + gap)
			drawSlot(uid, own, slot, bx1, ry1, bx1 + is, ry2, f)
		end
	end
end

-- a list row of an item: icon, name, short stats; returns nothing (adds its box)
local function itemRow(e, x1, y1, w, h, enabled, fn, extraTip, note)
	local it = H.items[e.item]
	local rc = H.rarities[it.rarity].color
	local hov = hovered(x1, y1, x1 + w, y1 + h)
	rect(x1, y1, x1 + w, y1 + h, hov and enabled and { 0.25, 0.2, 0.1, 0.9 } or { 0.08, 0.08, 0.1, 0.85 })
	local pad = floor(h * 0.08)
	local k = enabled and 1 or 0.4
	tex(ART .. "item_" .. e.item .. ".png", x1 + pad, y1 + pad, x1 + h - pad, y1 + h - pad, k, k, k, 1)
	frame(x1 + pad - 1, y1 + pad - 1, x1 + h - pad + 1, y1 + h - pad + 1, { rc[1] * k, rc[2] * k, rc[3] * k, 1 }, 1)
	local tx = x1 + h + pad
	text(it.name, tx, y1 + h * 0.52, h * 0.34, enabled and { rc[1], rc[2], rc[3], 1 } or GREY)
	text(note or it.short or "", tx, y1 + h * 0.14, h * 0.28, enabled and { 0.78, 0.78, 0.78, 1 } or DARK)
	addBox(x1, y1, x1 + w, y1 + h, enabled and fn or nil, itemTip(e.item) .. (extraTip or ""))
end

local function smallButton(label, x1, y1, x2, y2, c, enabled, fn, tip)
	local hov = enabled and hovered(x1, y1, x2, y2)
	rect(x1, y1, x2, y2, enabled and { c[1] * 0.25, c[2] * 0.25, c[3] * 0.25, 0.95 } or { 0.12, 0.12, 0.12, 0.9 })
	frame(x1, y1, x2, y2, hov and { 1, 0.9, 0.5, 1 } or (enabled and c or DARK), 1)
	text(label, (x1 + x2) / 2, y1 + (y2 - y1) * 0.26, (y2 - y1) * 0.5, enabled and WHITE or GREY, "co")
	addBox(x1, y1, x2, y2, enabled and fn or nil, tip)
end

-- the picker over a slot: the worn item (unequip / use) and the team stash items of the slot's category
local function drawPicker(uid, yBottom)
	local slot = picker.slot
	local catId = H.slotCategory[slot]
	local cat = H.itemCategories[catId]
	local cc = cat.color
	local own = spGetUnitTeam(uid) == myTeam()
	local f = spGetGameFrame()
	local list = stashOf(stashTeam(uid), catId)
	local worn = wornItem(uid, slot)
	local wornHere = {}
	for s2 = 1, H.INVENTORY do
		local w2 = wornItem(uid, s2)
		if w2 then
			wornHere[w2] = s2
		end
	end
	local rh = floor(vsy * 0.042 * uiScale)
	local rw = floor(rh * 6.8)
	local cols = #list > 16 and 3 or (#list > 7 and 2 or 1)
	local rows = max(1, math.ceil(#list / cols))
	local pad = floor(rh * 0.3)
	local head = floor(rh * 0.9)
	local wornH = worn and (rh + pad * 2) or 0
	local W = cols * rw + (cols - 1) * pad + pad * 2
	W = max(W, floor(rh * 8.5))
	rw = floor((W - pad * 2 - (cols - 1) * pad) / cols)
	local Ht = head + wornH + rows * (rh + 3) + pad * 2 + floor(rh * 0.5)
	local anchor = slotRects[slot]
	local cx = anchor and (anchor[1] + anchor[3]) / 2 or vsx / 2
	local x1 = floor(max(8, min(vsx - W - 8, cx - W / 2)))
	local x2 = x1 + W
	local y1 = yBottom + floor(vsy * 0.01)
	local y2 = min(vsy - 8, y1 + Ht)
	panel(x1, y1, x2, y2)
	addBox(x1, y1, x2, y2, nil, nil)
	-- header
	rect(x1 + 5, y2 - head, x2 - 5, y2 - 5, { cc[1] * 0.3, cc[2] * 0.3, cc[3] * 0.3, 0.6 })
	tex(ART .. cat.glyph .. ".png", x1 + pad, y2 - head + 4, x1 + pad + head - 10, y2 - 6)
	local idxInCat = 1
	for k, s2 in ipairs(cat.slots) do
		if s2 == slot then
			idxInCat = k
		end
	end
	text(string.format("%s slot %d", cat.label, idxInCat), x1 + pad + head, y2 - head * 0.72, head * 0.45, { cc[1], cc[2], cc[3], 1 })
	iconButton(nil, x2 - head * 0.8, y2 - head * 0.8, x2 - head * 0.3, y2 - head * 0.3, true, RED, function() picker = nil end, "Close (Esc)")
	text("x", x2 - head * 0.55, y2 - head * 0.72, head * 0.4, RED, "co")
	local y = y2 - head - pad
	-- the worn item
	if worn then
		local it = H.items[worn]
		local by1 = y - rh
		local bw = floor(rh * 2.2)
		local btnX2 = x2 - pad
		local rowW = btnX2 - x1 - pad
		if own then
			rowW = rowW - bw - pad
			if it.active then
				rowW = rowW - bw - pad
			end
		end
		itemRow({ item = worn }, x1 + pad, by1, rowW, rh, true, nil, "", it.short)
		if own then
			smallButton("Unequip", btnX2 - bw, by1 + rh * 0.18, btnX2, by1 + rh * 0.82, GOLD, true, function() sendUnequip(uid, slot) end,
				"Back to the team stash (right click on the slot does the same)")
			if it.active then
				local left = itemCooldown(uid, slot, worn, f)
				smallButton(left > 0 and string.format("%ds", floor(left / 30) + 1) or "Use", btnX2 - bw * 2 - pad, by1 + rh * 0.18, btnX2 - bw - pad,
					by1 + rh * 0.82, GREEN, left <= 0, function() sendUse(uid, slot) end, "Use now (autocast also uses it when it helps)")
			end
		end
		y = by1 - pad
		rect(x1 + pad, y + 1, x2 - pad, y + 2, { 0.45, 0.34, 0.16, 1 })
		y = y - pad * 0.6
	end
	text(#list > 0 and string.format("Team stash: %d %s item%s", #list, cat.label:lower(), #list == 1 and "" or "s") or "", x1 + pad, y - rh * 0.4,
		rh * 0.3, GREY)
	y = y - rh * 0.5
	if #list == 0 then
		text("No " .. cat.label:lower() .. " items in the team stash.", x1 + pad, y - rh * 0.55, rh * 0.32, WHITE)
		text("Slain heroes and big enemies drop items - walk over them.", x1 + pad, y - rh * 0.95, rh * 0.26, GREY)
	end
	for i, e in ipairs(list) do
		local col = floor((i - 1) / rows)
		local row = (i - 1) % rows
		local rx = x1 + pad + col * (rw + pad)
		local ry = y - (row + 1) * (rh + 3)
		local elsewhere = wornHere[e.item]
		itemRow(e, rx, ry, rw, rh, own and not elsewhere, function() sendEquip(uid, slot, e) end,
			own and (worn and "\n\255\180\180\180Click: swap it in (the worn one goes to the stash)" or "\n\255\180\180\180Click: equip") or "",
			elsewhere and "Already worn by this hero" or nil)
	end
	return y2
end

-- the whole team stash, by category
local function drawStashWindow(uid, yBottom)
	local own = uid and spGetUnitTeam(uid) == myTeam()
	local team = stashTeam(uid)
	local _, ver = readStash(team)
	stashSeenVer = max(stashSeenVer, ver)
	local rh = floor(vsy * 0.038 * uiScale)
	local rw = floor(rh * 6.6)
	local pad = floor(rh * 0.35)
	local head = floor(rh * 1.1)
	local lists, rows = {}, 1
	local total = 0
	for _, catId in ipairs(H.categoryOrder) do
		lists[catId] = stashOf(team, catId)
		rows = max(rows, #lists[catId])
		total = total + #lists[catId]
	end
	local maxRows = floor((vsy - yBottom - head - pad * 4 - rh) / (rh + 3))
	local colsPer = rows > maxRows and 2 or 1
	local rowsShown = math.ceil(rows / colsPer)
	local W = 3 * colsPer * rw + (3 * colsPer - 1) * pad + pad * 4
	local Ht = head + rh * 1.1 + rowsShown * (rh + 3) + pad * 3
	local x1 = floor(max(8, (vsx - W) / 2))
	local x2 = x1 + W
	local y1 = yBottom + floor(vsy * 0.01)
	local y2 = min(vsy - 8, y1 + Ht)
	panel(x1, y1, x2, y2)
	addBox(x1, y1, x2, y2, nil, nil)
	text(string.format("Team stash  %d / %d", total, H.STASH_SIZE), x1 + pad * 1.5, y2 - head * 0.72, head * 0.45, GOLD)
	text("When full, the oldest item of the lowest rarity is scrapped for metal", x2 - head * 1.2, y2 - head * 0.66, head * 0.34, GREY, "ro")
	iconButton(nil, x2 - head * 0.8, y2 - head * 0.8, x2 - head * 0.3, y2 - head * 0.3, true, RED, function() showStash = false end, "Close (Esc)")
	text("x", x2 - head * 0.55, y2 - head * 0.72, head * 0.4, RED, "co")
	local hero = uid and heroDefIDs[spGetUnitDefID(uid) or -1] and uid
	for ci, catId in ipairs(H.categoryOrder) do
		local cat = H.itemCategories[catId]
		local cc = cat.color
		local cx1 = x1 + pad * 2 + (ci - 1) * colsPer * (rw + pad)
		local ty = y2 - head - rh * 0.9
		tex(ART .. cat.glyph .. ".png", cx1, ty, cx1 + rh * 0.8, ty + rh * 0.8)
		text(string.format("%s  (%d)", cat.label, #lists[catId]), cx1 + rh, ty + rh * 0.2, rh * 0.42, { cc[1], cc[2], cc[3], 1 })
		for i, e in ipairs(lists[catId]) do
			local col = floor((i - 1) / rowsShown)
			local row = (i - 1) % rowsShown
			local rx = cx1 + col * (rw + pad)
			local ry = ty - pad * 0.5 - (row + 1) * (rh + 3)
			local fn
			if own and hero then
				fn = function()
					-- into the first empty slot of its category, else open the picker of its first slot
					for _, s2 in ipairs(cat.slots) do
						if not wornItem(hero, s2) then
							sendEquip(hero, s2, e)
							return
						end
					end
					openPicker(hero, cat.slots[1])
				end
			end
			itemRow(e, rx, ry, rw, rh, true, fn, fn and "\n\255\180\180\180Click: equip on the selected hero" or "")
		end
	end
	return y2
end

---------------------------------------------------------------------------- console (bottom)

local function stat(label, value, x, y, size, c)
	text(label, x, y, size, GREY)
	text(value, x + size * 6.4, y, size, c or WHITE)
end

local function drawConsole(uid)
	local name = heroDefIDs[spGetUnitDefID(uid) or -1]
	if not name then
		return
	end
	local cfg = H.heroes[name]
	local own = spGetUnitTeam(uid) == myTeam()
	local lvl = spGetUnitRulesParam(uid, "hero_level") or 1
	local xp = spGetUnitRulesParam(uid, "hero_xp") or 0
	local xpAbs = spGetUnitRulesParam(uid, "hero_xp_abs") or 0
	local xpNeed = spGetUnitRulesParam(uid, "hero_xp_need") or 0
	local pts = spGetUnitRulesParam(uid, "hero_points") or 0
	local hpMult = spGetUnitRulesParam(uid, "hero_hpmult") or 1
	local f = spGetGameFrame()

	-- between BAR's order menu (bottom left) and the player list (bottom right)
	local left, right = floor(vsx * 0.3), vsx - floor(vsx * 0.12)
	if WG.ordermenu and WG.ordermenu.getPosition then
		local ox, _, ow = WG.ordermenu.getPosition()
		if ox and ow then
			left = floor((ox + ow) * vsx) + 6
		end
	end
	for _, w in ipairs({ WG.unitgroups, WG.idlebuilders }) do
		if w and w.getPosition then
			local _, _, r, top = w.getPosition()
			if r and r > 1 and top and top > 1 and top < vsy * 0.3 and r < vsx * 0.6 then
				left = max(left, floor(r) + 6)
			end
		end
	end
	if WG.advplayerlist_api and WG.advplayerlist_api.GetPosition then
		local pos = WG.advplayerlist_api.GetPosition()
		if pos and pos[2] and pos[2] > left + 200 and pos[1] and pos[1] < vsy * 0.4 then
			right = floor(pos[2]) - 6
		end
	end
	local H0 = floor(min(vsy * 0.215 * uiScale, (right - left) / 5.3))
	local W = floor(H0 * 5.3)
	local x1 = floor(left + (right - left - W) / 2)
	local x2 = x1 + W
	local y1 = floor(vsy * 0.005)
	local y2 = y1 + H0
	local pad = floor(H0 * 0.06)
	panel(x1, y1, x2, y2)
	addBox(x1, y1, x2, y2, nil, nil)

	-- portrait
	local ps = H0 - pad * 2 - floor(H0 * 0.2)
	local px1, py2 = x1 + pad, y2 - pad
	local px2, py1 = px1 + ps, py2 - ps
	rect(px1 - 3, py1 - 3, px2 + 3, py2 + 3, { 0, 0, 0, 1 })
	tex(ART .. "portrait_" .. name .. ".png", px1, py1, px2, py2)
	frame(px1 - 3, py1 - 3, px2 + 3, py2 + 3, GOLD, 2)
	-- health and experience under the portrait
	local hp, maxHp = spGetUnitHealth(uid)
	local by2 = py1 - pad * 0.6
	local bh = floor(H0 * 0.075)
	bar(px1, by2 - bh, px2, by2, hp and maxHp and hp / maxHp or 0, { 0.15, 0.85, 0.2, 1 })
	if hp then
		text(string.format("%s / %s", fmtNum(hp * hpMult), fmtNum(maxHp * hpMult)), (px1 + px2) / 2, by2 - bh * 0.85, bh * 0.8, WHITE, "co")
	end
	bar(px1, by2 - bh * 2 - 3, px2, by2 - bh - 3, lvl >= H.MAX_LEVEL and 1 or xp, { 0.55, 0.35, 1, 1 })
	addBox(px1, by2 - bh * 2 - 3, px2, by2 - bh - 3, nil, lvl >= H.MAX_LEVEL and "Maximum level"
		or string.format("Experience: %s / %s metal of damage to reach level %d", fmtNum(xpAbs), fmtNum(xpNeed), lvl + 1))

	-- name, level, stats
	local sx = px2 + pad * 2
	local ts = H0 * 0.105
	text(cfg.title, sx, y2 - pad - ts, ts, GOLD)
	text(string.format("Level %d  %s", lvl, cfg.role), sx, y2 - pad - ts * 2.1, ts * 0.75, WHITE)
	local ss = H0 * 0.068
	local sy = y2 - pad - ts * 3.2
	local dps = spGetUnitRulesParam(uid, "hero_dps") or 0
	local armor = spGetUnitRulesParam(uid, "hero_armor") or 0
	local speed = spGetUnitRulesParam(uid, "hero_speed") or 0
	local range = spGetUnitRulesParam(uid, "hero_range") or 0
	local regen = spGetUnitRulesParam(uid, "hero_regen") or 0
	local dmgMult = spGetUnitRulesParam(uid, "hero_dmgmult") or 1
	local kills = spGetUnitRulesParam(uid, "hero_kills") or 0
	local col2 = sx + ss * 12.5
	stat("Damage", string.format("%s dps", fmtNum(dps)), sx, sy, ss, ORANGE)
	stat("Power", string.format("x%.2f", dmgMult), col2, sy, ss, ORANGE)
	stat("Armor", string.format("%d%%", floor(armor * 100 + 0.5)), sx, sy - ss * 1.35, ss, BLUE)
	stat("Toughness", string.format("x%.2f", hpMult), col2, sy - ss * 1.35, ss, GREEN)
	stat("Speed", string.format("%d", floor(speed + 0.5)), sx, sy - ss * 2.7, ss)
	stat("Range", string.format("%d", range), col2, sy - ss * 2.7, ss)
	stat("Regen", string.format("%.2f%%/s", regen * 100), sx, sy - ss * 4.05, ss, GREEN)
	stat("Kills", tostring(kills), col2, sy - ss * 4.05, ss, RED)
	-- weapon tiers
	local wy = sy - ss * 5.5
	for wi, w in ipairs(cfg.weapons or {}) do
		local tier = spGetUnitRulesParam(uid, "hero_wtier_" .. wi) or 1
		local stars = string.rep("\255\255\210\064*", tier) .. string.rep("\255\090\090\090*", 4 - tier)
		text(w.name .. " " .. stars, sx + ((wi - 1) % 2) * ss * 12.5, wy - floor((wi - 1) / 2) * ss * 1.3, ss * 0.9, WHITE)
	end

	-- items: nine slots in three category rows, between the stats and the command card
	local cardX1 = x2 - pad - floor(H0 * 0.36) * 3 - floor(floor(H0 * 0.36) * 0.13) * 2
	drawInventory(uid, own, x1 + floor(W * 0.545), y1 + pad, cardX1 - pad, y2 - pad)

	-- command card: abilities, upgrades, autocast
	local cs = floor(H0 * 0.36)
	local cg = floor(cs * 0.13)
	local cx1 = x2 - pad - cs * 3 - cg * 2
	local cy2 = y2 - pad - H0 * 0.02
	for i, key in ipairs(H.abilityKeys) do
		local b = cfg[key]
		local bx1 = cx1 + (i - 1) * (cs + cg)
		local bx2, by1 = bx1 + cs, cy2 - cs
		local rank = spGetUnitRulesParam(uid, "hero_rank_" .. key) or 0
		local maxRank = H.maxRank(name, key)
		local ready = spGetUnitRulesParam(uid, "hero_ready_" .. key) or 0
		local cd = spGetUnitRulesParam(uid, "hero_cd_" .. key) or 0
		local on = spGetUnitRulesParam(uid, "hero_on_" .. key) or 0
		local dur = spGetUnitRulesParam(uid, "hero_dur_" .. key) or 0
		local castable = own and rank > 0 and b.cmd and ready <= f
		local tip = learnTip(uid, name, key) .. (b.cmd and ("\n\255\180\180\180Hotkey: " .. H.hotkeys[key] .. (b.target and "  (aim on the map)" or "")) or "\n\255\180\180\180Passive")
		if on > f then
			local glow = 0.5 + 0.5 * sin(f * 0.35)
			rect(bx1 - 6, by1 - 6, bx2 + 6, cy2 + 6, { 0.4, 1, 0.5, 0.4 + 0.4 * glow })
		end
		iconButton(ART .. "ab_" .. name .. "_" .. key .. ".png", bx1, by1, bx2, cy2, rank > 0, key == "ult" and ORANGE or nil,
			castable and function() castAbility(uid, key) end or nil, tip)
		if on > f and dur > 0 then
			bar(bx1, cy2 - cs * 0.1, bx2, cy2, (on - f) / dur, { 0.4, 1, 0.5, 1 })
		elseif ready > f and cd > 0 then
			sweep(bx1, by1, bx2, cy2, (ready - f) / cd)
			text(tostring(floor((ready - f) / 30) + 1), (bx1 + bx2) / 2, by1 + cs * 0.32, cs * 0.38, WHITE, "co")
		end
		-- rank pips and hotkey
		for p = 1, maxRank do
			local pw = cs / (maxRank * 1.6)
			local pxx = bx1 + cs * 0.1 + (p - 1) * pw * 1.5
			rect(pxx, by1 + 3, pxx + pw, by1 + 3 + cs * 0.07, p <= rank and GOLD or { 0.2, 0.2, 0.2, 0.9 })
		end
		if b.cmd then
			rect(bx1, cy2 - cs * 0.26, bx1 + cs * 0.26, cy2, { 0, 0, 0, 0.8 })
			text(H.hotkeys[key], bx1 + cs * 0.13, cy2 - cs * 0.21, cs * 0.2, GOLD, "co")
		end
	end
	-- second row: learn skills, autocast
	local ry2 = cy2 - cs - cg
	local ry1 = ry2 - cs * 0.62
	if own then
		local bx2 = cx1 + cs * 2 + cg
		local hov = hovered(cx1, ry1, bx2, ry2)
		local glowOn = pts > 0 and (0.5 + 0.5 * sin(f * 0.25)) or 0
		rect(cx1, ry1, bx2, ry2, { 0.1 + 0.25 * glowOn, 0.08 + 0.18 * glowOn, 0.02, 0.95 })
		frame(cx1, ry1, bx2, ry2, hov and { 1, 0.9, 0.5, 1 } or GOLD, 2)
		text(pts > 0 and string.format("Upgrades  (+%d)", pts) or "Upgrades", (cx1 + bx2) / 2, (ry1 + ry2) / 2 - cs * 0.1, cs * 0.24, pts > 0 and GOLD or WHITE, "co")
		addBox(cx1, ry1, bx2, ry2, function() showUpgrades = not showUpgrades; picker = nil; showStash = false end, "Open the upgrade window: weapons, plating, servos and abilities (hotkey: U)")
		local auto = (spGetUnitRulesParam(uid, "hero_autocast") or 1) == 1
		local ax1 = bx2 + cg
		local ax2 = ax1 + cs
		rect(ax1, ry1, ax2, ry2, auto and { 0.05, 0.3, 0.08, 0.95 } or { 0.15, 0.15, 0.15, 0.95 })
		frame(ax1, ry1, ax2, ry2, hovered(ax1, ry1, ax2, ry2) and { 1, 0.9, 0.5, 1 } or (auto and GREEN or GREY), 2)
		text(auto and "Auto" or "Manual", (ax1 + ax2) / 2, (ry1 + ry2) / 2 - cs * 0.1, cs * 0.22, auto and GREEN or GREY, "co")
		addBox(ax1, ry1, ax2, ry2, function() toggleAutocast(uid) end, "Autocast: the hero uses its abilities and items by itself when they help")
	end
	return y2
end

---------------------------------------------------------------------------- upgrade window

-- v15: the tooltip of a weapon track or a chassis branch - per rank and in total, in units
local function branchTip(uid, name, key)
	local b = H.branch(name, key)
	local rank = spGetUnitRulesParam(uid, "hero_rank_" .. key) or 0
	local maxRank = H.maxRank(name, key)
	local s = "\255\255\210\064" .. b.name .. "\255\255\255\255  (" .. rank .. "/" .. maxRank .. ")"
	if H.common[key] then
		s = s .. "\n" .. H.commonText(name, key, 1) .. " per rank"
		if rank > 0 then
			s = s .. "\n\255\120\255\120Now: " .. H.commonText(name, key, rank)
		end
	else
		local cfg = H.heroes[name]
		local w = cfg.weapons[b.weapon]
		local tr = H.weaponTrack(w.kind, b.track)
		local base = H.weaponBase(name, b.weapon)
		local amount = H.trackAmount(tr, base)
		s = s .. "\n" .. w.name .. ": " .. H.trackText(tr, amount, base) .. " per rank"
		if rank > 0 then
			s = s .. "\n\255\120\255\120Now: " .. H.trackText(tr, amount * rank, base)
		end
	end
	if rank < maxRank then
		local req = H.reqLevel(name, key, rank + 1)
		local cost = H.metalCost(name, key, rank + 1)
		s = s .. string.format("\n\255\200\200\200Rank %d: level %d, 1 point, %s metal", rank + 1, req, fmtNum(cost))
	end
	return s
end

-- the tooltip of a weapon: kind, visual step, perks
local function weaponTip(name, wi, rankSum)
	local w = H.heroes[name].weapons[wi]
	local k = H.weaponKinds[w.kind]
	local base = H.weaponBase(name, wi)
	local s = "\255\255\210\064" .. w.name .. "\255\255\255\255  (" .. k.label .. ")"
	s = s .. string.format("\nRank sum %d: visual step %d/%d (bigger shots, flashes and blasts as it grows)", rankSum,
		H.weaponStep(rankSum), #H.weaponSteps)
	for _, p in ipairs(k.perks or {}) do
		local on = rankSum >= p.at
		s = s .. "\n" .. (on and "\255\120\255\120" or "\255\150\150\150") .. "Perk at " .. p.at .. ": " .. p.name .. " - "
			.. H.trackText(p, H.trackAmount(p, base), base)
	end
	return s
end

local function drawUpgrades(uid, yBottom)
	local name = heroDefIDs[spGetUnitDefID(uid) or -1]
	if not name then
		return
	end
	local cfg = H.heroes[name]
	local own = spGetUnitTeam(uid) == myTeam()
	local lvl = spGetUnitRulesParam(uid, "hero_level") or 1
	local pts = spGetUnitRulesParam(uid, "hero_points") or 0
	local metal = Spring.GetTeamResources(myTeam(), "metal") or 0

	local is = floor(vsy * 0.046 * uiScale)
	local gap = floor(is * 0.35)
	local rowH = is + is * 1.05
	local nW = #(cfg.weapons or {})
	local rows = nW + 1
	local W = floor(is * 20)
	local Ht = floor(rowH * rows + is * 2.3)
	local x1 = floor((vsx - W) / 2)
	local x2 = x1 + W
	local y1 = yBottom + floor(vsy * 0.01)
	local y2 = y1 + Ht
	panel(x1, y1, x2, y2)
	addBox(x1, y1, x2, y2, nil, nil)
	text("Upgrades", x1 + is * 0.4, y2 - is * 0.8, is * 0.5, GOLD)
	text(string.format("Level %d    %d skill point%s    %s metal", lvl, pts, pts == 1 and "" or "s", fmtNum(metal)),
		x2 - is * 1.6, y2 - is * 0.75, is * 0.38, pts > 0 and GOLD or WHITE, "ro")
	iconButton(nil, x2 - is * 0.95, y2 - is * 0.95, x2 - is * 0.35, y2 - is * 0.35, true, RED, function() showUpgrades = false end, "Close (U)")
	text("x", x2 - is * 0.65, y2 - is * 0.84, is * 0.45, RED, "co")

	-- a learn button: icon, rank, the metal price of the next rank (red: not enough metal or level), the total
	local function learnButton(key, bx, by, total, tip)
		local b = H.branch(name, key)
		local rank = spGetUnitRulesParam(uid, "hero_rank_" .. key) or 0
		local maxRank = H.maxRank(name, key)
		local req = H.reqLevel(name, key, rank + 1)
		local cost = H.metalCost(name, key, rank + 1)
		local can = own and pts > 0 and rank < maxRank and lvl >= req and metal >= cost
		local icon = b.icon and (ART .. b.icon .. ".png") or (ART .. "ab_" .. name .. "_" .. key .. ".png")
		iconButton(icon, bx, by, bx + is, by + is, rank > 0 or can, can and GOLD or nil, function() learn(uid, key) end, tip or learnTip(uid, name, key))
		if can then
			local glow = 0.5 + 0.5 * sin(spGetGameFrame() * 0.25)
			frame(bx - 4, by - 4, bx + is + 4, by + is + 4, { 1, 0.85, 0.2, 0.4 + 0.5 * glow }, 2)
		end
		text(rank .. "/" .. maxRank, bx + is * 0.5, by - is * 0.33, is * 0.26, rank >= maxRank and GOLD or WHITE, "co")
		if rank < maxRank then
			local c = (lvl < req or metal < cost) and RED or GREEN
			text(lvl < req and ("lv " .. req) or fmtNum(cost), bx + is * 0.5, by - is * 0.6, is * 0.24, c, "co")
		end
		if total and total ~= "" then
			text(total, bx + is * 0.5, by - is * 0.87, is * 0.22, ORANGE, "co")
		end
	end

	local tx = x1 + is * 5.6
	local tstep = is * 1.75
	local y = y2 - is * 1.3 - is
	for wi, w in ipairs(cfg.weapons or {}) do
		local k = H.weaponKinds[w.kind]
		local base = H.weaponBase(name, wi)
		local rankSum = 0
		for _, id in ipairs(k.tracks) do
			rankSum = rankSum + (spGetUnitRulesParam(uid, "hero_rank_w" .. wi .. "_" .. id) or 0)
		end
		local step = H.weaponStep(rankSum)
		-- weapon kind icon, name, kind, visual step pips, perks
		local ix = x1 + is * 0.35
		tex(ART .. k.icon .. ".png", ix, y, ix + is, y + is)
		frame(ix - 2, y - 2, ix + is + 2, y + is + 2, { 0.45, 0.34, 0.16, 1 }, 2)
		local nx = ix + is * 1.2
		text(w.name, nx, y + is * 0.66, is * 0.32, WHITE)
		text(k.label, nx, y + is * 0.33, is * 0.24, GREY)
		local pw = is * 0.2
		for p = 1, #H.weaponSteps do
			local px = nx + (p - 1) * pw * 1.35
			rect(px, y + is * 0.05, px + pw, y + is * 0.05 + pw * 0.7, p <= step and GOLD or { 0.22, 0.22, 0.22, 0.95 })
		end
		-- perks: a diamond each, lit once the rank sum reaches it; the next one named
		local nextPerk
		for pi, p in ipairs(k.perks or {}) do
			local on = rankSum >= p.at
			local cx, cy, r = nx + is * 0.1 + (pi - 1) * is * 0.3, y - is * 0.2, is * 0.09
			gl.Color(on and 1 or 0.3, on and 0.55 or 0.3, on and 0.15 or 0.3, 1)
			gl.Shape(GL.TRIANGLE_FAN, { { v = { cx, cy + r } }, { v = { cx + r, cy } }, { v = { cx, cy - r } }, { v = { cx - r, cy } } })
			if not on and not nextPerk then
				nextPerk = p
			end
		end
		text(nextPerk and (nextPerk.name .. " at " .. nextPerk.at) or "all perks", nx + is * 0.95, y - is * 0.28, is * 0.2,
			nextPerk and GREY or GOLD)
		addBox(ix, y - is * 0.35, tx - is * 0.3, y + is, nil, weaponTip(name, wi, rankSum))
		for ti, id in ipairs(k.tracks) do
			local key = "w" .. wi .. "_" .. id
			local tr = k.track[id]
			local rank = spGetUnitRulesParam(uid, "hero_rank_" .. key) or 0
			learnButton(key, tx + (ti - 1) * tstep, y, H.trackShort(tr, H.trackAmount(tr, base) * rank), branchTip(uid, name, key))
		end
		y = y - rowH
	end
	-- chassis: plating and servos in units
	text("Chassis", x1 + is * 0.4, y + is * 0.55, is * 0.32, WHITE)
	text("health, regeneration, speed, sight", x1 + is * 0.4, y + is * 0.22, is * 0.22, GREY)
	for i, key in ipairs({ "plating", "servos" }) do
		local rank = spGetUnitRulesParam(uid, "hero_rank_" .. key) or 0
		local a = H.commonAmount(name, key)
		local total = ""
		if rank > 0 then
			total = key == "plating" and ("+" .. fmtNum((a.hp or 0) * rank) .. " HP") or ("+" .. H.fmtAmount((a.speed or 0) * rank) .. " spd")
		end
		learnButton(key, tx + (i - 1) * tstep, y, total, branchTip(uid, name, key))
	end
	-- abilities on the right, spanning the rows
	local ax = x1 + is * 13.1
	text("Abilities", ax, y2 - is * 1.3, is * 0.36, WHITE)
	for i, key in ipairs(H.abilityKeys) do
		local b = cfg[key]
		if b then
			learnButton(key, ax + (i - 1) * is * 2.2, y2 - is * 1.55 - is - gap)
			text(b.name, ax + (i - 1) * is * 2.2 + is * 0.5, y2 - is * 1.55 - is * 2.35 - gap, is * 0.22, key == "ult" and ORANGE or BLUE, "co")
		end
	end
	text(string.format("Metal per rank - weapons and chassis: %s x rank\nabilities: %s / %s / %s\nultimate: %s / %s / %s",
		fmtNum(H.STAT_METAL), fmtNum(H.ABILITY_METAL[1]), fmtNum(H.ABILITY_METAL[2]), fmtNum(H.ABILITY_METAL[3]),
		fmtNum(H.ULT_METAL[1]), fmtNum(H.ULT_METAL[2]), fmtNum(H.ULT_METAL[3])), ax, y + is * 0.6, is * 0.24, GREY)
end

---------------------------------------------------------------------------- world overlay

local AURA_COLORS = {
	aura_heal = { 0.3, 1, 0.4 }, aura_damage = { 1, 0.5, 0.2 }, aura_burn = { 1, 0.35, 0.05 }, aura_emp = { 0.4, 0.7, 1 },
	aura_armor = { 1, 0.8, 0.3 }, aura_slow = { 1, 0.6, 0.15 },
}

function widget:DrawWorldPreUnit()
	local f = spGetGameFrame()
	gl.DepthTest(false)
	gl.LineWidth(2)
	for uid, name in pairs(tracked) do
		if spIsUnitInView(uid) then
			local cfg = H.heroes[name]
			local x, y, z = spGetUnitPosition(uid)
			if x and cfg then
				for _, key in ipairs(H.abilityKeys) do
					local b = cfg[key]
					local c = b and AURA_COLORS[b.kind]
					local r = spGetUnitRulesParam(uid, "hero_rank_" .. key) or 0
					if c and r > 0 then
						local radius = type(b.radius) == "table" and b.radius[r] or b.radius
						gl.Color(c[1], c[2], c[3], 0.28)
						gl.DrawGroundCircle(x, y, z, radius, 64)
					end
				end
				for _, key in ipairs(H.abilityKeys) do
					local b = cfg[key]
					if b and (b.kind == "active_guard" or b.kind == "active_dome") and (spGetUnitRulesParam(uid, "hero_on_" .. key) or 0) > f then
						local pulse = 0.55 + 0.25 * sin(f * 0.3)
						local r = math.max(1, spGetUnitRulesParam(uid, "hero_rank_" .. key) or 1)
						gl.Color(b.kind == "active_dome" and 0.5 or 1, b.kind == "active_dome" and 0.8 or 0.85, b.kind == "active_dome" and 1 or 0.3, pulse)
						gl.LineWidth(4)
						gl.DrawGroundCircle(x, y, z, type(b.radius) == "table" and (b.radius[r] or b.radius[#b.radius]) or b.radius, 72)
						gl.LineWidth(2)
					end
				end
			end
		end
	end
	-- items on the ground: a rarity ring
	for _, g in ipairs(groundItems) do
		local c = H.rarities[H.items[g.item].rarity].color
		local gy = Spring.GetGroundHeight(g.x, g.z)
		gl.Color(c[1], c[2], c[3], 0.5 + 0.3 * sin(f * 0.15 + g.id))
		gl.LineWidth(3)
		gl.DrawGroundCircle(g.x, gy, g.z, 60 + 8 * sin(f * 0.1 + g.id), 32)
	end
	gl.LineWidth(1)
	gl.Color(1, 1, 1, 1)
end

-- the ground items as floating icons (screen space, so they stay readable at any zoom)
local itemScreen = {} -- id -> { sx, sy, r, item }
local function drawGroundItems()
	itemScreen = {}
	local f = spGetGameFrame()
	local _, camY = Spring.GetCameraPosition()
	for _, g in ipairs(groundItems) do
		local gy = Spring.GetGroundHeight(g.x, g.z)
		local sx, sy, sz = spWorldToScreenCoords(g.x, gy + 70 + 12 * sin(f * 0.08 + g.id), g.z)
		if sz < 1 and sx > 0 and sx < vsx and sy > 0 and sy < vsy then
			local s = floor(vsy * 0.03 * uiScale)
			local it = H.items[g.item]
			local c = H.rarities[it.rarity].color
			rect(sx - s * 0.62, sy - s * 0.62, sx + s * 0.62, sy + s * 0.62, { c[1], c[2], c[3], 0.35 + 0.2 * sin(f * 0.2 + g.id) })
			tex(ART .. "item_" .. g.item .. ".png", sx - s / 2, sy - s / 2, sx + s / 2, sy + s / 2)
			frame(sx - s / 2 - 1, sy - s / 2 - 1, sx + s / 2 + 1, sy + s / 2 + 1, { c[1], c[2], c[3], 1 }, 2)
			itemScreen[#itemScreen + 1] = { sx = sx, sy = sy, r = s * 0.7, g = g }
			if hovered(sx - s / 2, sy - s / 2, sx + s / 2, sy + s / 2) then
				hoverTip = itemTip(g.item) .. "\n\255\180\180\180A hero walking over it puts it into its team stash.\nRight click with a hero selected: go get it"
			end
		end
	end
end

local function drawWorldLabels()
	local f = spGetGameFrame()
	local size = floor(vsy * 0.016 * uiScale)
	for uid, name in pairs(tracked) do
		if spIsUnitInView(uid) then
			local lvl = spGetUnitRulesParam(uid, "hero_level")
			local x, y, z = spGetUnitPosition(uid)
			if lvl and x then
				local ud = UnitDefs[spGetUnitDefID(uid)]
				local h = (ud and ud.height or 80) + 20
				local sx, sy, sz = spWorldToScreenCoords(x, y + h, z)
				if sz < 1 then
					local allied = spIsUnitAllied(uid)
					local c = allied and GOLD or RED
					text("Lv " .. lvl, sx, sy + size * 0.4, size, c, "co")
					if allied then
						local xp = spGetUnitRulesParam(uid, "hero_xp") or 0
						bar(sx - size * 2, sy, sx + size * 2, sy + size * 0.3, xp, { 0.55, 0.35, 1, 0.9 })
						local pts = spGetUnitRulesParam(uid, "hero_points") or 0
						if pts > 0 and spGetUnitTeam(uid) == myTeam() then
							text("+" .. pts, sx + size * 2.6, sy - size * 0.1, size, { 1, 0.85, 0.2, (f % 30 < 20) and 1 or 0.5 }, "co")
						end
					end
				end
			end
		end
	end
	local now = Spring.GetTimer()
	local keep = {}
	for _, fl in ipairs(floating) do
		local age = Spring.DiffTimers(now, fl.t0)
		if age < fl.dur then
			keep[#keep + 1] = fl
			local sx, sy, sz = spWorldToScreenCoords(fl.x, fl.y + age * 60, fl.z)
			if sz < 1 then
				local a = min(1, (fl.dur - age) / 0.6)
				text(fl.text, sx, sy, fl.size, { fl.r, fl.g, fl.b, a }, "co")
			end
		end
	end
	floating = keep
end

---------------------------------------------------------------------------- events from the gadget

local function float(uid, str, c, size, dur, kind)
	local x, y, z = spGetUnitPosition(uid)
	if not x then
		return
	end
	for i = #floating, 1, -1 do
		if floating[i].uid == uid and floating[i].kind == kind then
			table.remove(floating, i)
		end
	end
	local ud = UnitDefs[spGetUnitDefID(uid) or -1]
	floating[#floating + 1] = { uid = uid, kind = kind, x = x, y = y + (ud and ud.height or 80) + 60, z = z, text = str,
		r = c[1], g = c[2], b = c[3], t0 = Spring.GetTimer(), dur = dur or 2.5, size = floor(vsy * (size or 0.03) * uiScale) }
end

local function visible(uid)
	if spIsUnitAllied(uid) then
		return true
	end
	local _, specFull = Spring.GetSpectatingState()
	if specFull then
		return true
	end
	return Spring.IsUnitInLos and Spring.IsUnitInLos(uid) or false
end

function widget:T4HeroEvent(kind, uid, a, b)
	if not spValidUnitID(uid) or not visible(uid) then
		return
	end
	local name = heroDefIDs[spGetUnitDefID(uid) or -1]
	local mine = spGetUnitTeam(uid) == myTeam()
	if kind == "levelup" then
		float(uid, "LEVEL " .. a, GOLD, a % 5 == 0 and 0.045 or 0.034, 3, "level")
		if mine then
			local x, y, z = spGetUnitPosition(uid)
			Spring.PlaySoundFile("sounds/ui/commanderspawn-mono.wav", 0.5, x, y, z, "ui")
		end
	elseif kind == "died" then
		float(uid, "FALLEN", RED, 0.04, 4, "state")
		if mine and name then
			Spring.Echo(string.format("\255\255\090\070%s has fallen at level %d - its items lie where it fell. Rebuild it at the hero altar to revive it at level %d.", heroTitle(name), a, b))
		end
	elseif kind == "revived" then
		float(uid, "REVIVED  Lv " .. a, { 0.6, 0.85, 1 }, 0.042, 4, "state")
		if mine then
			local x, y, z = spGetUnitPosition(uid)
			Spring.PlaySoundFile("sounds/ui/teleport-short-mono.wav", 0.7, x, y, z, "ui")
		end
	elseif kind == "born" then
		float(uid, "HERO", GOLD, 0.04, 3, "state")
	elseif kind == "undying" then
		float(uid, "UNDYING!", { 1, 0.5, 0.15 }, 0.045, 3, "state")
	elseif kind == "nometal" and mine then
		float(uid, "Not enough metal: " .. fmtNum(a), RED, 0.026, 2.5, "warn")
		Spring.PlaySoundFile("sounds/ui/cantdothat.wav", 0.6, "ui")
	elseif kind == "pickup" then
		local item = H.itemOrder[a]
		if item then
			local c = H.rarities[H.items[item].rarity].color
			float(uid, "+ " .. H.items[item].name .. (b == 1 and "  (to stash)" or "  (scrapped)"), c, 0.028, 2.5, "item")
		end
	elseif kind == "scrap" and spIsUnitAllied(uid) then
		local item = H.itemOrder[a]
		if item then
			Spring.Echo(string.format("Team stash full: %s scrapped for %d metal", H.items[item].name, b))
		end
	elseif kind == "cheatdeath" then
		float(uid, "PHOENIX!", { 1, 0.6, 0.2 }, 0.045, 3, "state")
	elseif kind == "stashfull" and mine then
		float(uid, "Team stash is full", RED, 0.026, 2.5, "warn")
		Spring.PlaySoundFile("sounds/ui/cantdothat.wav", 0.6, "ui")
	elseif kind == "itemdup" and mine then
		float(uid, "Already wearing that item", RED, 0.026, 2.5, "warn")
		Spring.PlaySoundFile("sounds/ui/cantdothat.wav", 0.6, "ui")
	elseif kind == "cast" and name then
		local key = H.abilityKeys[b - 3] -- the gadget sends 4 / 5 / 6
		local br = key and H.branch(name, key)
		if br then
			float(uid, br.name, key == "ult" and { 1, 0.6, 0.25 } or { 0.7, 0.85, 1 }, key == "ult" and 0.036 or 0.028, 2.2, "cast" .. b)
		end
	end
end

---------------------------------------------------------------------------- widget callins

local lastRefresh = -100

function widget:GameFrame(f)
	if f - lastRefresh >= 15 then
		lastRefresh = f
		refreshTracked()
		refreshRoster()
		pickSelected()
		refreshGround()
	end
end

function widget:SelectionChanged()
	pickSelected()
end

function widget:UnitCreated(uid, udid)
	if heroDefIDs[udid] then
		tracked[uid] = heroDefIDs[udid]
	end
end

function widget:UnitDestroyed(uid)
	tracked[uid] = nil
	if uid == selectedHero then
		selectedHero = nil
	end
end

function widget:DrawScreen()
	if not font and not getFont() then
		return
	end
	boxes = {}
	hoverTip = nil
	font:Begin()
	drawWorldLabels()
	drawGroundItems()
	drawHeroButtons()
	if selectedHero and spValidUnitID(selectedHero) then
		local top = drawConsole(selectedHero)
		if picker and (picker.uid ~= selectedHero or not top) then
			picker = nil
		end
		if showUpgrades and top then
			drawUpgrades(selectedHero, top)
		elseif picker and top then
			drawPicker(selectedHero, top)
		elseif showStash and top then
			drawStashWindow(selectedHero, top)
		end
	else
		picker = nil
	end
	font:End()
	gl.Color(1, 1, 1, 1)
	local mx, my = Spring.GetMouseState()
	for i = #boxes, 1, -1 do
		local bx = boxes[i]
		if bx[6] and mx >= bx[1] and mx <= bx[3] and my >= bx[2] and my <= bx[4] then
			hoverTip = bx[6]
			break
		end
	end
	-- a tooltip box of our own, near the cursor (the BAR tooltip does not show multi-line colored text well)
	if hoverTip then
		local size = floor(vsy * 0.015 * uiScale)
		local lines = {}
		for line in (hoverTip .. "\n"):gmatch("([^\n]*)\n") do
			lines[#lines + 1] = line
		end
		local w = 0
		for _, line in ipairs(lines) do
			w = max(w, font:GetTextWidth(line) * size)
		end
		local hgt = #lines * size * 1.3 + size * 0.6
		local tx = min(mx + 18, vsx - w - size * 1.4)
		local ty = min(my + 18 + hgt, vsy - 4)
		rect(tx, ty - hgt, tx + w + size * 1.2, ty, { 0.02, 0.02, 0.03, 0.93 })
		frame(tx, ty - hgt, tx + w + size * 1.2, ty, { 0.45, 0.34, 0.16, 1 }, 2)
		font:Begin()
		for i, line in ipairs(lines) do
			text(line, tx + size * 0.6, ty - size * 0.3 - i * size * 1.3 + size * 0.25, size, WHITE, "o")
		end
		font:End()
	end
end

function widget:IsAbove(x, y)
	for _, bx in ipairs(boxes) do
		if x >= bx[1] and x <= bx[3] and y >= bx[2] and y <= bx[4] then
			return true
		end
	end
	return false
end

function widget:GetTooltip()
	return nil
end

function widget:MousePress(x, y, button)
	local inside = false
	for _, bx in ipairs(boxes) do
		if x >= bx[1] and x <= bx[3] and y >= bx[2] and y <= bx[4] then
			inside = true
			break
		end
	end
	if not inside and (picker or showStash) then
		picker = nil
		showStash = false
	end
	for i = #boxes, 1, -1 do
		local bx = boxes[i]
		if x >= bx[1] and x <= bx[3] and y >= bx[2] and y <= bx[4] then
			if button == 1 and bx[5] then
				bx[5]()
			elseif button == 3 and bx[7] then
				bx[7]()
			end
			return true
		end
	end
	-- right click on a ground item: the selected heroes walk to it (and pick it up on arrival)
	if button == 3 and selectedHero then
		for _, s in ipairs(itemScreen) do
			if (x - s.sx) ^ 2 + (y - s.sy) ^ 2 <= s.r * s.r then
				local gy = Spring.GetGroundHeight(s.g.x, s.g.z)
				local shift = select(4, Spring.GetModKeyState())
				Spring.GiveOrderToUnitArray(Spring.GetSelectedUnits(), CMD.MOVE, { s.g.x, gy, s.g.z }, shift and { "shift" } or 0)
				return true
			end
		end
	end
	return false
end

local HOTKEY = { q = "a1", w = "a2", r = "ult" }

function widget:KeyPress(key, mods, isRepeat)
	if key == 27 and (picker or showStash) then -- escape
		picker = nil
		showStash = false
		return true
	end
	if not selectedHero or mods.ctrl or mods.alt or isRepeat then
		return false
	end
	-- only when the selection is heroes alone, so the usual Q/W/R binds keep working for armies
	for _, uid in ipairs(Spring.GetSelectedUnits()) do
		if not heroDefIDs[spGetUnitDefID(uid) or -1] then
			return false
		end
	end
	local sym = Spring.GetKeySymbol and Spring.GetKeySymbol(key)
	sym = type(sym) == "string" and sym:lower() or string.char(key):lower()
	if sym == "u" then
		showUpgrades = not showUpgrades
		picker = nil
		showStash = false
		return true
	end
	local ab = HOTKEY[sym]
	if ab and spGetUnitTeam(selectedHero) == myTeam() then
		local name = heroDefIDs[spGetUnitDefID(selectedHero)]
		local b = H.heroes[name][ab]
		if b and b.cmd then
			castAbility(selectedHero, ab)
			return true
		end
	end
	return false
end

function widget:Initialize()
	if not next(heroDefIDs) then
		widgetHandler:RemoveWidget()
		return
	end
	widgetHandler:RegisterGlobal("T4HeroEvent", function(...) widget:T4HeroEvent(...) end)
	widget:ViewResize()
	WG.T4HeroesUI = {
		setUpgrades = function(v) showUpgrades = v end,
		-- items (scenes, other widgets): open the picker of a slot / the stash window of the selected hero
		openPicker = function(slot) if selectedHero then picker = nil; openPicker(selectedHero, slot) end end,
		openStash = function() showStash = true; picker = nil; showUpgrades = false end,
		closeItems = function() picker = nil; showStash = false end,
		slotRect = function(slot) return slotRects[slot] end,
	}
	refreshTracked()
	refreshRoster()
	pickSelected()
	refreshGround()
end

function widget:Shutdown()
	WG.T4HeroesUI = nil
	widgetHandler:DeregisterGlobal("T4HeroEvent")
end
