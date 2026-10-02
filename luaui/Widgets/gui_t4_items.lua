--------------------------------------------------------------------------------
--
--  file:    gui_t4_items.lua
--  brief:   Diablo-style hero items of the custom T4 heroes (denysfast/bar-game), v19:
--           * the nine item slots (3 weapon / 3 defense / 3 utility) inside the hero console of gui_t4_heroes.lua
--             (WG.T4HeroesUI.itemsArea), rarity-coloured frames, active cooldowns
--           * Diablo tooltips: name in the rarity colour, base type + item level, implicit, affixes, unique powers,
--             set name with the pieces worn and the 2/3/4-piece bonuses lit when active, salvage value / price
--           * the team stash window (36): equip by click or by drag into a slot, salvage with a confirm
--           * the shop window (the team's shop building, items_shop_unit): shelf of 9, prices, buy, refresh with a
--             fee, the timer to the free refresh
--           * items on the ground in rarity colours with a name label on hover (all labels while Alt is held)
--           * toasts of the item events (pickup, buy, salvage, scrap, procs ...)
--  Protocol, rules params and events: the header of luarules/gadgets/unit_t4_hero_items.lua; data and the
--  tooltip text: luarules/configs/t4_hero_items.lua (I.decode, I.lines, I.icon, I.price, I.salvage).
--  Licensed under the terms of the GNU GPL, v2 or later.
--
--------------------------------------------------------------------------------

local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name = "T4 Hero Items",
		desc = "Diablo-style hero items: console slots, tooltips, team stash, shop, ground items and item toasts of the custom T4 heroes",
		author = "denysfast",
		date = "2026-10-02",
		license = "GNU GPL, v2 or later",
		layer = 4, -- draws after (over) gui_t4_heroes (layer 5) and gets the mouse first
		enabled = true,
	}
end

local I = VFS.Include("luarules/configs/t4_hero_items.lua")
local K = VFS.Include("luaui/Include/t4heroes_ui.lua")

local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetTeamRulesParam = Spring.GetTeamRulesParam
local spGetGameRulesParam = Spring.GetGameRulesParam
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam
local spValidUnitID = Spring.ValidUnitID
local spGetGameFrame = Spring.GetGameFrame
local spWorldToScreenCoords = Spring.WorldToScreenCoords
local floor, max, min, sin = math.floor, math.max, math.min, math.sin

local ART = K.ART
local GOLD, WHITE, GREY, RED, GREEN = K.GOLD, K.WHITE, K.GREY, K.RED, K.GREEN
local rect, frame, tex, text, addBox, hovered = K.rect, K.frame, K.tex, K.text, K.addBox, K.hovered
local fmtNum = K.fmtNum

local heroDefs = {}
local shopDefs = {}
for udid, ud in pairs(UnitDefs) do
	if ud.customParams and ud.customParams.t4_hero then
		heroDefs[udid] = ud.name
	end
end
for _, sname in pairs(I.SHOPS) do
	local sd = UnitDefNames[sname]
	if sd then
		shopDefs[sd.id] = true
	end
end

local showStash, showShop = false, false
local stashFilter        -- category shown in the stash (nil = all)
local stashSlot          -- the slot a stash click equips into (opened from that slot), nil = first free of its category
local salvageSel         -- { idx, uid } the stash item marked for salvage
local salvageConfirm = 0 -- timer: second click within 3 s confirms
local stashSeenVer = 0
local drag               -- { idx, uid, str, x0, y0, moved }
local slotRects = {}     -- slot -> { x1, y1, x2, y2 } (this frame)
local rects = {}         -- named rectangles of this frame (scenes): stash_<i>, shop_<i>, salvage
local toasts = {}
local tip
local shopAuto = false   -- the shop window was opened by selecting the shop building

local function myTeam()
	return Spring.GetMyTeamID()
end

local function heroArea()
	return WG.T4HeroesUI and WG.T4HeroesUI.itemsArea and WG.T4HeroesUI.itemsArea()
end

local function selectedHero()
	local a = heroArea()
	if a and spValidUnitID(a.uid) then
		return a.uid, a.own
	end
	local s = WG.T4HeroesUI and WG.T4HeroesUI.selectedHero and WG.T4HeroesUI.selectedHero()
	if s and spValidUnitID(s) then
		return s, spGetUnitTeam(s) == myTeam()
	end
end

local function closeHeroWindows()
	if WG.T4HeroesUI and WG.T4HeroesUI.closeWindows then
		WG.T4HeroesUI.closeWindows()
	end
end

local function sound(name, vol)
	Spring.PlaySoundFile("sounds/ui/" .. name, vol or 0.5, "ui")
end

---------------------------------------------------------------------------- data caches

local decoded = {} -- item string -> item table (false = bad)
local function decode(str)
	if not str or str == "" then
		return nil
	end
	local it = decoded[str]
	if it == nil then
		it = I.decode(str) or false
		decoded[str] = it
	end
	return it or nil
end

local function factionOfTeam(team)
	local side = select(5, Spring.GetTeamInfo(team or myTeam(), false))
	side = type(side) == "string" and side:lower() or ""
	if side:find("cor") then
		return "cor"
	elseif side:find("leg") then
		return "leg"
	end
	return "arm"
end

local function factionOf(uid, team)
	local name = uid and heroDefs[spGetUnitDefID(uid) or -1]
	if name then
		return I.factionOf(name)
	end
	return factionOfTeam(team)
end

local iconOk = {}
local function iconOf(it, faction)
	local p = I.icon(it, faction)
	local ok = iconOk[p]
	if ok == nil then
		ok = VFS.FileExists(p) and true or false
		iconOk[p] = ok
	end
	return ok and p or (ART .. I.categories[it.cat].glyph .. ".png")
end

local function stashTeam(uid)
	local team = uid and spGetUnitTeam(uid)
	if team and Spring.IsUnitAllied(uid) then
		return team
	end
	return myTeam()
end

-- { { idx, str, it } ... } in stash order (cached by items_stash_ver)
local stashCache = { team = -1, ver = -1, list = {} }
local function readStash(team)
	local ver = spGetTeamRulesParam(team, "items_stash_ver") or 0
	if stashCache.team == team and stashCache.ver == ver then
		return stashCache.list, ver
	end
	local list = {}
	local n = spGetTeamRulesParam(team, "items_stash_n") or 0
	for i = 1, n do
		local str = spGetTeamRulesParam(team, "items_stash_" .. i)
		local it = decode(str)
		if it then
			list[#list + 1] = { idx = i, str = str, it = it }
		end
	end
	stashCache.team, stashCache.ver, stashCache.list = team, ver, list
	return list, ver
end

-- worn items of a hero: slots[1..9] = { str, it } | nil, sets = { [setIdx] = count }, pieces = { [pieceName] = true }
local wornCache = {}
local function readWorn(uid)
	local ver = spGetUnitRulesParam(uid, "items_ver") or 0
	local c = wornCache[uid]
	if c and c.ver == ver then
		return c
	end
	c = { ver = ver, slots = {}, sets = {}, pieces = {} }
	for slot = 1, I.SLOTS do
		local str = spGetUnitRulesParam(uid, "items_slot_" .. slot)
		local it = decode(str)
		if it then
			c.slots[slot] = { str = str, it = it }
			if it.rarity == "set" then
				c.pieces[I.sets[it.set].pieces[it.piece].name] = true
			end
		end
	end
	for si, n in tostring(spGetUnitRulesParam(uid, "items_sets") or ""):gmatch("(%d+):(%d+)") do
		c.sets[tonumber(si)] = tonumber(n)
	end
	wornCache[uid] = c
	return c
end

local function activePower(it)
	for _, p in ipairs(I.powers(it)) do
		local info = I.powerInfo[p.key]
		if info and info.active then
			return p
		end
	end
end

---------------------------------------------------------------------------- Diablo tooltip

local tipCache = {}
local tipCacheN = 0
-- extra: list of { text, color } lines appended (actions); worn: the hero's readWorn() (set pieces / bonuses lit)
local function itemTip(it, worn, extraKey, extra)
	local key = it.str .. "|" .. (worn and worn.ver or "-") .. "|" .. (worn and tostring(worn) or "") .. "|" .. (extraKey or "")
	local t = tipCache[key]
	if t then
		return t
	end
	if tipCacheN > 300 then
		tipCache, tipCacheN = {}, 0
	end
	local rc = I.color(it)
	local lines = {}
	local src = I.lines(it, worn and worn.sets or nil)
	local prevKind
	for _, l in ipairs(src) do
		local e = { text = l.text, color = l.color }
		if l.kind == "name" then
			e.size = 1.2
		elseif l.kind == "base" or l.kind == "info" then
			e.size = 0.9
		elseif l.kind == "flavor" then
			e.size = 0.88
			e.sep = true
			e.text = "\"" .. l.text .. "\""
		end
		-- a rule after the header and after the implicit, before the set block
		if prevKind and (prevKind == "info" or prevKind == "implicit") and l.kind ~= "implicit" and l.kind ~= prevKind then
			e.sep = true
		elseif l.kind == "implicit" and prevKind == "info" then
			e.sep = true
		elseif l.kind == "setname" then
			e.sep = true
			local have = worn and worn.sets[it.set] or 0
			e.text = string.format("%s  (%d/%d)", l.text, have, #I.sets[it.set].pieces)
		elseif l.kind == "setpiece" then
			local nm = l.text:gsub("^%s+", "")
			if worn and worn.pieces[nm] then
				e.color = rc
			end
		end
		lines[#lines + 1] = e
		prevKind = l.kind
	end
	for i, x in ipairs(extra or {}) do
		lines[#lines + 1] = { text = x[1], color = x[2], size = x[3] or 0.9, sep = i == 1 }
	end
	t = { lines = lines, center = true, border = rc, width = 16 }
	tipCache[key] = t
	tipCacheN = tipCacheN + 1
	return t
end

---------------------------------------------------------------------------- actions

local function sendEquip(uid, slot, e)
	Spring.SendLuaRulesMsg(string.format("t4hero:equip:%d:%d_%d_%d", uid, slot, e.idx, e.it.uid or 0))
	sound("beep6.wav", 0.5)
end

local function sendUnequip(uid, slot)
	Spring.SendLuaRulesMsg("t4hero:unequip:" .. uid .. ":" .. slot)
	sound("beep6.wav", 0.4)
end

local function sendUse(uid, slot)
	Spring.SendLuaRulesMsg("t4hero:use:" .. uid .. ":" .. slot)
end

-- a stash item onto the selected hero: the chosen slot, else the first free slot of its category, else its first slot
local function equipAuto(uid, e, slot)
	local cat = e.it.cat
	if slot and I.slotCategory[slot] == cat then
		sendEquip(uid, slot, e)
		return
	end
	local worn = readWorn(uid)
	for _, s2 in ipairs(I.categories[cat].slots) do
		if not worn.slots[s2] then
			sendEquip(uid, s2, e)
			return
		end
	end
	sendEquip(uid, I.categories[cat].slots[1], e)
end

local function openStash(filter, slot)
	showStash = true
	stashFilter = filter
	stashSlot = slot
	closeHeroWindows()
end

local function closeWindows()
	showStash, showShop = false, false
	stashSlot, salvageSel, drag = nil, nil, nil
end

---------------------------------------------------------------------------- an item cell

-- icon + rarity frame + item level; returns nothing, adds the box
local function itemCell(e, x1, y1, s, faction, opts)
	opts = opts or {}
	local it = e.it
	local rc = I.color(it)
	local hov = hovered(x1, y1, x1 + s, y1 + s)
	rect(x1 - 2, y1 - 2, x1 + s + 2, y1 + s + 2, { 0, 0, 0, 0.9 })
	rect(x1, y1, x1 + s, y1 + s, { rc[1] * 0.18, rc[2] * 0.18, rc[3] * 0.18, 1 })
	local k = opts.dim and 0.35 or (hov and 1.12 or 1)
	tex(iconOf(it, faction), x1, y1, x1 + s, y1 + s, k, k, k, 1)
	local fw = max(2, floor(s * 0.05))
	frame(x1 - fw, y1 - fw, x1 + s + fw, y1 + s + fw, opts.selected and GOLD or { rc[1] * (opts.dim and 0.4 or 1), rc[2] * (opts.dim and 0.4 or 1), rc[3] * (opts.dim and 0.4 or 1), 1 }, fw)
	if hov and not opts.dim then
		frame(x1, y1, x1 + s, y1 + s, { 1, 1, 1, 0.5 }, 1)
	end
	-- item level pip
	local ls = s * 0.3
	rect(x1, y1, x1 + ls, y1 + ls, { 0, 0, 0, 0.75 })
	text(tostring(it.ilvl), x1 + ls / 2, y1 + ls * 0.14, ls * 0.85, { rc[1], rc[2], rc[3], 1 }, "co")
	return hov
end

---------------------------------------------------------------------------- the console slots

local function drawSlots(a)
	local uid, own = a.uid, a.own
	local f = spGetGameFrame()
	local worn = readWorn(uid)
	local faction = factionOf(uid)
	local x1, y1, x2, y2 = a.x1, a.y1, a.x2, a.y2
	local H0 = a.H0
	local th = floor(H0 * 0.13)
	-- header: Items, Stash N, Shop
	local team = stashTeam(uid)
	local list, ver = readStash(team)
	text("Items", x1, y2 - th * 0.78, th * 0.62, GOLD)
	local by1, by2 = y2 - th + 1, y2 - 1
	local shopUnit = spGetTeamRulesParam(team, "items_shop_unit") or 0
	local fresh = ver > stashSeenVer and #list > 0 and not showStash
	local bw = floor((x2 - x1) * 0.36)
	K.button(string.format("Stash %d", #list), x2 - bw * 2 - 4, by1, x2 - bw - 4, by2, GOLD, true, function()
		if showStash then
			showStash = false
		else
			openStash(nil, nil)
		end
	end, string.format("Team stash: %d / %d items. Pickups, drops and purchases land here.\nClick: open it - equip by click or drag, salvage for metal.", #list, I.STASH_SIZE),
		{ glow = fresh and (0.5 + 0.5 * sin(f * 0.25)) or 0, textColor = fresh and GOLD or WHITE, size = th * 0.5 })
	K.button("Shop", x2 - bw, by1, x2, by2, GOLD, shopUnit > 0, function()
		showShop = not showShop
		shopAuto = false
		if showShop then
			closeHeroWindows()
		end
	end, shopUnit > 0 and "The team's item shop: 9 items, refreshed every 3 minutes" or "Build an item shop (T2 constructors) to buy items", { size = th * 0.5 })
	-- three rows: category glyph + 3 slots
	local rowsH = y2 - th - y1
	local pitch = rowsH / 3
	local is = floor(min(pitch * 0.86, (x2 - x1) * 0.25))
	local glyph = floor(is * 0.55)
	local gap = floor((x2 - x1 - glyph - is * 3) / 3)
	for ci, catId in ipairs(I.categoryOrder) do
		local cat = I.categories[catId]
		local cc = cat.color
		local ry2 = floor(y2 - th - (ci - 1) * pitch - (pitch - is) / 2)
		local ry1 = ry2 - is
		rect(x1 - 2, ry1 - 3, x2 + 2, ry2 + 3, { cc[1], cc[2], cc[3], 0.07 })
		tex(ART .. cat.glyph .. ".png", x1, ry1 + (is - glyph) / 2, x1 + glyph, ry1 + (is + glyph) / 2, 1, 1, 1, 0.9)
		addBox(x1, ry1, x1 + glyph, ry2, nil, K.code(cc) .. cat.label .. " items\255\255\255\255: " ..
			(catId == "weapon" and "damage, range, splash, penetration, crits, damage types" or catId == "defense" and "health, armor, regeneration, thorns"
				or "speed, sight, ability power, cooldowns, experience, income"))
		for k, slot in ipairs(cat.slots) do
			local bx1 = x1 + glyph + gap + (k - 1) * (is + gap)
			local bx2, by = bx1 + is, ry1
			slotRects[slot] = { bx1, by, bx2, ry2 }
			local w = worn.slots[slot]
			local dropTarget = drag and drag.moved and drag.it.cat == catId
			if dropTarget then
				local glow = 0.5 + 0.5 * sin(f * 0.4)
				rect(bx1 - 5, by - 5, bx2 + 5, ry2 + 5, { 1, 0.85, 0.3, 0.3 + 0.4 * glow })
			end
			if w then
				local act = activePower(w.it)
				itemCell({ it = w.it }, bx1, by, is, faction)
				local tipFn = function()
					local extra = {}
					if act then
						extra[#extra + 1] = { "Click: use " .. I.powerInfo[act.key].label, GREEN }
					end
					if own then
						extra[#extra + 1] = { (act and "" or "Click: swap from the stash.  ") .. "Right click: back to the stash", GREY }
					end
					return itemTip(w.it, worn, "slot" .. (own and 1 or 0), extra)
				end
				addBox(bx1, by, bx2, ry2, own and function()
					if act then
						sendUse(uid, slot)
					else
						openStash(catId, slot)
					end
				end or nil, tipFn,
					own and function() sendUnequip(uid, slot) end or nil)
				-- active cooldown
				local ready = spGetUnitRulesParam(uid, "items_cd_" .. slot) or 0
				if act and ready > f then
					local len = spGetUnitRulesParam(uid, "items_cdlen_" .. slot) or ((act.p and act.p.cooldown or 30) * 30)
					K.sweep(bx1, by, bx2, ry2, (ready - f) / max(1, len))
					text(tostring(floor((ready - f) / 30) + 1), (bx1 + bx2) / 2, by + is * 0.3, is * 0.4, WHITE, "co")
				elseif act then
					local ps = is * 0.2
					rect(bx2 - ps - 2, ry2 - ps - 2, bx2 - 2, ry2 - 2, { 0.4, 1, 0.5, 0.9 })
				end
			else
				local hov = hovered(bx1, by, bx2, ry2)
				rect(bx1, by, bx2, ry2, { cc[1] * 0.1, cc[2] * 0.1, cc[3] * 0.1, 0.9 })
				tex(ART .. cat.glyph .. ".png", bx1 + is * 0.2, by + is * 0.2, bx2 - is * 0.2, ry2 - is * 0.2, 1, 1, 1, hov and 0.45 or 0.18)
				frame(bx1 - 2, by - 2, bx2 + 2, ry2 + 2, stashSlot == slot and showStash and GOLD or (hov and K.HOVER or { cc[1] * 0.4, cc[2] * 0.4, cc[3] * 0.4, 1 }), 2)
				addBox(bx1, by, bx2, ry2, own and function() openStash(catId, slot) end or nil,
					string.format("%sEmpty %s slot\255\255\255\255\n%s", K.code(cc), cat.label:lower(),
						own and "Click: pick an item from the team stash (or drag one here)" or "Heroes and big enemies drop items; the shop sells them"))
			end
		end
	end
end

---------------------------------------------------------------------------- window placement

local function windowBottom()
	local top = WG.T4HeroesUI and WG.T4HeroesUI.consoleTop and WG.T4HeroesUI.consoleTop()
	return (top or floor(K.vsy * 0.22)) + floor(K.vsy * 0.01)
end

local function stashSize()
	local c = floor(K.vsy * 0.047 * K.ui)
	local g = floor(c * 0.16)
	local pad = floor(c * 0.35)
	local cols, rows = 9, 4
	local head = floor(c * 1.55)
	local foot = floor(c * 1.05)
	local W = cols * c + (cols - 1) * g + pad * 2
	local Ht = head + rows * c + (rows - 1) * g + pad * 2 + foot
	return W, Ht, c, g, pad, head, foot
end

local function shopSize()
	local c = floor(K.vsy * 0.047 * K.ui)
	local pad = floor(c * 0.35)
	local cw, ch = floor(c * 3.6), floor(c * 1.3)
	local g = floor(c * 0.18)
	local head = floor(c * 0.95)
	local foot = floor(c * 1.05)
	local W = cw * 3 + g * 2 + pad * 2
	local Ht = head + ch * 3 + g * 2 + pad * 2 + foot
	return W, Ht, c, cw, ch, g, pad, head, foot
end

local function windowXs()
	local cx = K.vsx / 2
	local g = WG.T4HeroesUI and WG.T4HeroesUI.consoleGeometry
	if g then
		local x1, _, x2 = g()
		cx = (x1 + x2) / 2
	end
	local sw = showStash and (stashSize()) or 0
	local pw = showShop and (shopSize()) or 0
	local gap = (showStash and showShop) and 10 or 0
	local total = sw + pw + gap
	local x = floor(max(8, min(K.vsx - total - 8, cx - total / 2)))
	return x, x + sw + gap
end

---------------------------------------------------------------------------- stash window

local function drawStash(x1, yBottom)
	local uid, own = selectedHero()
	local team = stashTeam(uid)
	local list, ver = readStash(team)
	stashSeenVer = max(stashSeenVer, ver)
	local faction = factionOf(uid, team)
	local W, Ht, c, g, pad, head, foot = stashSize()
	local x2 = x1 + W
	local y1 = yBottom
	local y2 = y1 + Ht
	K.panel(x1, y1, x2, y2)
	addBox(x1, y1, x2, y2, nil, nil)
	local th = floor(c * 0.85)
	tex(ART .. "ui/ui_stash.png", x1 + pad, y2 - th - 2, x1 + pad + th - 6, y2 - 8)
	text(string.format("Team stash  %d / %d", #list, I.STASH_SIZE), x1 + pad + th, y2 - th * 0.72, th * 0.5, GOLD)
	text(fmtNum(Spring.GetTeamResources(myTeam(), "metal") or 0) .. " metal", x2 - pad - th * 0.9, y2 - th * 0.66, th * 0.36, WHITE, "ro")
	K.closeButton(x2 - pad * 0.6, y2 - pad * 0.6, floor(th * 0.55), function() showStash = false end)
	-- category filter tabs
	local tabs = { { nil, "All" }, { "weapon", "Weapon" }, { "defense", "Defense" }, { "utility", "Utility" } }
	local tw = floor(c * 1.85)
	local ty1, ty2 = y2 - head + floor(c * 0.08), y2 - th - floor(c * 0.04)
	for i, t in ipairs(tabs) do
		local on = stashFilter == t[1]
		local col = t[1] and I.categories[t[1]].color or GOLD
		local n = 0
		for _, e in ipairs(list) do
			if not t[1] or e.it.cat == t[1] then
				n = n + 1
			end
		end
		local bx1 = x1 + pad + (i - 1) * (tw + 4)
		K.button(string.format("%s %d", t[2], n), bx1, ty1, bx1 + tw, ty2, { col[1], col[2], col[3], 1 }, true,
			function() stashFilter = t[1]; stashSlot = nil end, nil, { textColor = on and { col[1], col[2], col[3], 1 } or GREY, border = on and 2 or 1, size = (ty2 - ty1) * 0.55 })
	end
	if stashSlot then
		local sc = I.categories[I.slotCategory[stashSlot]].color
		text(string.format("into slot %d", stashSlot), x2 - pad, ty1 + (ty2 - ty1) * 0.25, (ty2 - ty1) * 0.5, { sc[1], sc[2], sc[3], 1 }, "ro")
	end
	-- the grid: stash order, fixed places
	local gx, gy = x1 + pad, y2 - head - pad
	local selected
	for i = 1, I.STASH_SIZE do
		local col = (i - 1) % 9
		local row = floor((i - 1) / 9)
		local cx = gx + col * (c + g)
		local cy = gy - (row + 1) * c - row * g
		local e = list[i]
		rects["stash_" .. i] = { cx, cy, cx + c, cy + c }
		if e then
			local dim = stashFilter and e.it.cat ~= stashFilter
			local isSel = salvageSel and salvageSel.idx == e.idx and salvageSel.uid == e.it.uid
			if isSel then
				selected = e
			end
			if drag and drag.idx == e.idx and drag.moved then
				rect(cx, cy, cx + c, cy + c, { 0.1, 0.1, 0.1, 0.8 })
			else
				itemCell(e, cx, cy, c, faction, { dim = dim })
				if isSel then
					local glow = 0.5 + 0.5 * sin(spGetGameFrame() * 0.3)
					frame(cx - 4, cy - 4, cx + c + 4, cy + c + 4, { 1, 0.35 + 0.25 * glow, 0.1, 1 }, 2)
					tex(ART .. "ui/ui_salvage.png", cx + c * 0.55, cy + c * 0.55, cx + c, cy + c, 1, 1, 1, 0.95)
				end
			end
			local tipFn = function()
				local extra = { { string.format("Salvage value: %s metal", I.fmtNum(I.salvage(e.it))), { 0.85, 0.75, 0.5 } } }
				if own and uid and not dim then
					extra[#extra + 1] = { stashSlot and string.format("Click: equip into %s slot %d", I.categories[e.it.cat].label:lower(), stashSlot) or "Click: equip on the hero.  Drag: into a slot", GREEN }
				end
				if own then
					extra[#extra + 1] = { "Right click: mark it for salvage", GREY }
				end
				return itemTip(e.it, uid and readWorn(uid) or nil, "stash" .. (own and 1 or 0) .. (stashSlot or 0) .. (dim and "d" or ""), extra)
			end
			local box = addBox(cx, cy, cx + c, cy + c, (own and uid and not dim) and function() equipAuto(uid, e, stashSlot) end or nil,
				tipFn,
				own and function()
					if isSel then
						salvageSel = nil
					else
						salvageSel = { idx = e.idx, uid = e.it.uid }
						salvageConfirm = 0
					end
				end or nil, { stash = e })
			box.drag = own and uid and not dim
		else
			rect(cx, cy, cx + c, cy + c, { 0.06, 0.06, 0.07, 0.9 })
			frame(cx, cy, cx + c, cy + c, { 0.18, 0.16, 0.12, 1 }, 1)
		end
	end
	if salvageSel and not selected then
		salvageSel = nil
	end
	-- footer: salvage of the marked item, or the hint
	local fy1, fy2 = y1 + pad * 0.6, y1 + pad * 0.6 + foot * 0.72
	if selected then
		local value = I.salvage(selected.it)
		local now = Spring.GetTimer()
		local confirming = salvageConfirm ~= 0 and Spring.DiffTimers(now, salvageConfirm) < 3
		local rc = I.color(selected.it)
		text(K.fit(I.name(selected.it), (fy2 - fy1) * 0.46, W * 0.45), x1 + pad, fy1 + (fy2 - fy1) * 0.3, (fy2 - fy1) * 0.46, { rc[1], rc[2], rc[3], 1 })
		local bx1 = x2 - pad - floor(W * 0.46)
		rects.salvage = { bx1, fy1, x2 - pad, fy2 }
		K.button(confirming and string.format("Confirm: salvage for %s metal", I.fmtNum(value)) or string.format("Salvage for %s metal", I.fmtNum(value)),
			bx1, fy1, x2 - pad, fy2, confirming and RED or { 1, 0.6, 0.25, 1 }, true, function()
				if confirming then
					Spring.SendLuaRulesMsg(string.format("t4hero:salvage:%d_%d", selected.idx, selected.it.uid or 0))
					salvageSel, salvageConfirm = nil, 0
					sound("beep6.wav", 0.6)
				else
					salvageConfirm = Spring.GetTimer()
				end
			end, "Salvage: the item is destroyed and its metal goes to the team storage.\nClick twice to confirm.",
			{ icon = ART .. "ui/ui_salvage.png", textColor = confirming and RED or GOLD, border = confirming and 2 or 1, size = (fy2 - fy1) * 0.46 })
	else
		local hint = own and (uid and (stashSlot and string.format("Pick an item for %s slot %d.  Right click: mark for salvage", I.categories[I.slotCategory[stashSlot]].label:lower(), stashSlot)
			or "Click: equip on the selected hero.  Drag: into a slot.  Right click: mark for salvage") or "Select a hero to equip items.  Right click: mark for salvage")
			or "The stash of an allied team"
		text(hint, x1 + pad, fy1 + (fy2 - fy1) * 0.3, (fy2 - fy1) * 0.42, GREY)
	end
	return y2
end

---------------------------------------------------------------------------- shop window

local shopCache = { team = -1, ver = -1, list = {} }
local function readShop(team)
	local ver = spGetTeamRulesParam(team, "items_shop_ver") or 0
	if shopCache.team == team and shopCache.ver == ver then
		return shopCache.list
	end
	local list = {}
	local i = 0
	for str in ((spGetTeamRulesParam(team, "items_shop") or "") .. "|"):gmatch("([^|]*)|") do
		i = i + 1
		if i > I.SHOP_SIZE then
			break
		end
		list[i] = { idx = i, str = str, it = decode(str) }
	end
	shopCache.team, shopCache.ver, shopCache.list = team, ver, list
	return list
end

local function drawShop(x1, yBottom)
	local uid = selectedHero()
	local team = myTeam()
	local W, Ht, c, cw, ch, g, pad, head, foot = shopSize()
	local x2 = x1 + W
	local y1 = yBottom
	local y2 = y1 + Ht
	local f = spGetGameFrame()
	local shopUnit = spGetTeamRulesParam(team, "items_shop_unit") or 0
	local faction = factionOf(shopUnit > 0 and shopUnit or uid, team)
	local metal = Spring.GetTeamResources(team, "metal") or 0
	local stashN = spGetTeamRulesParam(team, "items_stash_n") or 0
	K.panel(x1, y1, x2, y2)
	addBox(x1, y1, x2, y2, nil, nil)
	tex(ART .. "ui/ui_shop.png", x1 + pad, y2 - head + 4, x1 + pad + head - 8, y2 - 4)
	text("Item shop", x1 + pad + head, y2 - head * 0.68, head * 0.42, GOLD)
	text(string.format("%s metal    stash %d / %d", fmtNum(metal), stashN, I.STASH_SIZE), x2 - pad - head * 0.7, y2 - head * 0.62, head * 0.32, WHITE, "ro")
	K.closeButton(x2 - pad * 0.6, y2 - pad * 0.6, floor(head * 0.5), function() showShop = false end)
	local spec = select(1, Spring.GetSpectatingState())
	if shopUnit == 0 then
		local msg = "No item shop: T2 constructors build one (" .. (UnitDefNames[I.SHOPS[faction]] and (UnitDefNames[I.SHOPS[faction]].translatedHumanName or UnitDefNames[I.SHOPS[faction]].humanName) or I.SHOPS[faction]) .. ")"
		text(msg, (x1 + x2) / 2, (y1 + y2) / 2, head * 0.36, GREY, "co")
		return y2
	end
	local list = readShop(team)
	local gy = y2 - head - pad
	for i = 1, I.SHOP_SIZE do
		local col = (i - 1) % 3
		local row = floor((i - 1) / 3)
		local cx = x1 + pad + col * (cw + g)
		local cy = gy - (row + 1) * ch - row * g
		local e = list[i]
		rects["shop_" .. i] = { cx, cy, cx + cw, cy + ch }
		if e and e.it then
			local it = e.it
			local rc = I.color(it)
			local price = I.price(it)
			local afford = metal >= price
			local hov = hovered(cx, cy, cx + cw, cy + ch)
			rect(cx, cy, cx + cw, cy + ch, hov and { 0.17, 0.14, 0.08, 0.95 } or { 0.07, 0.07, 0.09, 0.9 })
			frame(cx, cy, cx + cw, cy + ch, hov and K.HOVER or { rc[1] * 0.5, rc[2] * 0.5, rc[3] * 0.5, 1 }, 1)
			local is = ch - 8
			itemCell(e, cx + 4, cy + 4, is, faction)
			local tx = cx + is + 10
			local nameSize = ch * 0.22
			text(K.fit(I.name(it), nameSize, cw - is - 14), tx, cy + ch * 0.64, nameSize, { rc[1], rc[2], rc[3], 1 })
			text(string.format("%s %s, ilvl %d", I.rarities[it.rarity].label, I.categories[it.cat].label:lower(), it.ilvl), tx, cy + ch * 0.4, ch * 0.17, GREY)
			text(I.fmtNum(price) .. " M", tx, cy + ch * 0.1, ch * 0.22, afford and GOLD or RED)
			local can = not spec and afford and stashN < I.STASH_SIZE
			addBox(cx, cy, cx + cw, cy + ch, can and function()
				Spring.SendLuaRulesMsg(string.format("t4hero:shopbuy:%d_%d", e.idx, it.uid or 0))
				sound("beep6.wav", 0.6)
			end or nil, function()
				return itemTip(it, uid and readWorn(uid) or nil, "shop" .. (afford and 1 or 0) .. (stashN < I.STASH_SIZE and 1 or 0), {
					{ string.format("Price: %s metal", I.fmtNum(price)), afford and GOLD or RED, 1 },
					{ afford and (stashN < I.STASH_SIZE and "Click: buy into the team stash" or "The team stash is full") or "Not enough metal", afford and GREEN or RED },
				})
			end)
		else
			rect(cx, cy, cx + cw, cy + ch, { 0.04, 0.04, 0.05, 0.9 })
			frame(cx, cy, cx + cw, cy + ch, { 0.18, 0.16, 0.12, 1 }, 1)
			text("SOLD", cx + cw / 2, cy + ch * 0.38, ch * 0.26, { 0.4, 0.37, 0.3, 1 }, "co")
		end
	end
	-- footer: refresh with the fee, timer to the free refresh
	local fy1, fy2 = y1 + pad * 0.6, y1 + pad * 0.6 + foot * 0.72
	local nextF = spGetTeamRulesParam(team, "items_shop_next") or 0
	local left = max(0, (nextF - f) / 30)
	text(string.format("New items in %s", K.time(left)), x1 + pad, fy1 + (fy2 - fy1) * 0.3, (fy2 - fy1) * 0.46, { 0.8, 0.8, 0.8, 1 })
	local fee = I.SHOP_REFRESH_FEE
	local ok = not spec and metal >= fee
	K.button(string.format("Refresh now  %s M", I.fmtNum(fee)), x2 - pad - floor(W * 0.42), fy1, x2 - pad, fy2, ok and GOLD or RED, not spec, ok and function()
		Spring.SendLuaRulesMsg("t4hero:shoprefresh")
		sound("beep6.wav", 0.6)
	end or nil, string.format("Reroll the whole shelf now for %s metal.\nThe shelf also refreshes by itself every %d minutes.", I.fmtNum(fee), floor(I.SHOP_REFRESH / 60 + 0.5)),
		{ textColor = ok and GOLD or RED, size = (fy2 - fy1) * 0.46 })
	return y2
end

---------------------------------------------------------------------------- ground items

local ground = {} -- { id, x, z, code }
local groundStr
local groundScreen = {}
local function refreshGround()
	local str = spGetGameRulesParam("items_ground")
	if str == groundStr then
		return
	end
	groundStr = str
	ground = {}
	for id, x, z, code in tostring(str or ""):gmatch("(%d+):(%-?%d+):(%-?%d+):(%a)") do
		ground[#ground + 1] = { id = tonumber(id), x = tonumber(x), z = tonumber(z), rarity = I.rarityByCode[code] or "magic" }
	end
end

local function groundItem(g)
	local str = spGetGameRulesParam("items_ground_" .. g.id)
	if g.str ~= str then
		g.str = str
		g.it = decode(str)
	end
	return g.it
end

function widget:DrawWorldPreUnit()
	if #ground == 0 then
		return
	end
	local f = spGetGameFrame()
	gl.DepthTest(false)
	for _, g in ipairs(ground) do
		if Spring.IsSphereInView(g.x, 0, g.z, 200) then
			local c = I.rarities[g.rarity].color
			local gy = Spring.GetGroundHeight(g.x, g.z)
			local ph = f * 0.1 + g.id
			gl.LineWidth(4)
			gl.Color(c[1], c[2], c[3], 0.25)
			gl.DrawGroundCircle(g.x, gy, g.z, 78 + 6 * sin(ph), 40)
			gl.LineWidth(2)
			gl.Color(c[1], c[2], c[3], 0.6 + 0.3 * sin(ph * 1.5))
			gl.DrawGroundCircle(g.x, gy, g.z, 56 + 6 * sin(ph), 40)
		end
	end
	gl.LineWidth(1)
	gl.Color(1, 1, 1, 1)
end

local groundBoxes = {}
local function drawGround()
	groundScreen = {}
	groundBoxes = {}
	if #ground == 0 then
		return
	end
	local f = spGetGameFrame()
	local alt = select(1, Spring.GetModKeyState())
	local s = floor(K.vsy * 0.03 * K.ui)
	local faction = factionOfTeam(myTeam())
	for _, g in ipairs(ground) do
		local gy = Spring.GetGroundHeight(g.x, g.z)
		local sx, sy, sz = spWorldToScreenCoords(g.x, gy + 70 + 12 * sin(f * 0.08 + g.id), g.z)
		if sz < 1 and sx > -s and sx < K.vsx + s and sy > -s and sy < K.vsy + s then
			local it = groundItem(g)
			local c = I.rarities[g.rarity].color
			rect(sx - s * 0.66, sy - s * 0.66, sx + s * 0.66, sy + s * 0.66, { c[1], c[2], c[3], 0.25 + 0.15 * sin(f * 0.2 + g.id) })
			if it then
				tex(iconOf(it, faction), sx - s / 2, sy - s / 2, sx + s / 2, sy + s / 2)
			end
			frame(sx - s / 2 - 2, sy - s / 2 - 2, sx + s / 2 + 2, sy + s / 2 + 2, { c[1], c[2], c[3], 1 }, 2)
			groundScreen[#groundScreen + 1] = { sx = sx, sy = sy, r = s * 0.75, g = g }
			groundBoxes[#groundBoxes + 1] = { "ground_" .. g.id, sx - s / 2, sy - s / 2, sx + s / 2, sy + s / 2 }
			local hov = hovered(sx - s * 0.6, sy - s * 0.6, sx + s * 0.6, sy + s * 0.6)
			if it and (hov or alt) then
				local name = I.name(it)
				local ts = s * 0.42
				local w = K.width(name, ts) + ts
				rect(sx - w / 2, sy + s * 0.7, sx + w / 2, sy + s * 0.7 + ts * 1.5, { 0, 0, 0, 0.8 })
				frame(sx - w / 2, sy + s * 0.7, sx + w / 2, sy + s * 0.7 + ts * 1.5, { c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 1 }, 1)
				text(name, sx, sy + s * 0.7 + ts * 0.38, ts, { c[1], c[2], c[3], 1 }, "co")
			end
			if it then
				groundBoxes[#groundBoxes].tip = function()
					return itemTip(it, nil, "ground", {
						{ "A hero walking over it puts it into its team stash", GREY },
						{ "Right click with a hero selected: go get it", GREY },
					})
				end
			end
		end
	end
end

---------------------------------------------------------------------------- toasts

local function toast(str, c, icon)
	table.insert(toasts, 1, { text = str, color = c or WHITE, icon = icon, t0 = Spring.GetTimer() })
	if #toasts > 6 then
		toasts[#toasts] = nil
	end
end

local function drawToasts()
	if #toasts == 0 then
		return
	end
	local now = Spring.GetTimer()
	local size = floor(K.vsy * 0.017 * K.ui)
	local base = (WG.T4HeroesUI and WG.T4HeroesUI.consoleTop and WG.T4HeroesUI.consoleTop()) or floor(K.vsy * 0.2)
	if showStash or showShop then
		base = base + select(2, stashSize()) + floor(K.vsy * 0.02)
	end
	local x = K.vsx / 2
	local y = base + size * 1.2
	local keep = {}
	for _, t in ipairs(toasts) do
		local age = Spring.DiffTimers(now, t.t0)
		if age < 5 then
			keep[#keep + 1] = t
			local a = min(1, (5 - age) / 0.8) * min(1, age * 6 + 0.2)
			local w = K.width(t.text, size) + size * (t.icon and 2.6 or 1.2)
			rect(x - w / 2, y, x + w / 2, y + size * 1.6, { 0.02, 0.02, 0.03, 0.75 * a })
			frame(x - w / 2, y, x + w / 2, y + size * 1.6, { t.color[1] * 0.6, t.color[2] * 0.6, t.color[3] * 0.6, a }, 1)
			local tx = x - w / 2 + size * 0.6
			if t.icon then
				tex(t.icon, tx, y + size * 0.15, tx + size * 1.3, y + size * 1.45, 1, 1, 1, a)
				tx = tx + size * 1.5
			end
			text(t.text, tx, y + size * 0.42, size, { t.color[1], t.color[2], t.color[3], a }, "o")
			y = y + size * 1.9
		end
	end
	toasts = keep
end

local function heroName(uid)
	local name = uid and uid >= 0 and spValidUnitID(uid) and heroDefs[spGetUnitDefID(uid) or -1]
	local ud = name and UnitDefNames[name]
	if name and WG.T4HeroesUI and WG.T4HeroesUI.heroTitle then
		return (WG.T4HeroesUI.heroTitle(name):gsub(",.*$", ""))
	end
	return ud and (ud.translatedHumanName or ud.humanName) or "A hero"
end

function widget:T4HeroItemEvent(kind, teamID, unitID, str, num)
	local it = decode(str)
	local mine = teamID == myTeam()
	local rc = it and I.color(it) or WHITE
	local faction = factionOfTeam(teamID >= 0 and teamID or nil)
	local icon = it and iconOf(it, faction) or nil
	if kind == "pickup" and it then
		toast(num == 1 and string.format("%s picked up %s", heroName(unitID), I.name(it)) or string.format("%s scrapped: the stash is full", I.name(it)), rc, icon)
	elseif kind == "buy" and it then
		toast(string.format("Bought %s for %s metal", I.name(it), I.fmtNum(num)), rc, icon)
		sound("beep6.wav", 0.6)
	elseif kind == "salvage" and it then
		toast(string.format("Salvaged %s: +%s metal", I.name(it), I.fmtNum(num)), { 1, 0.75, 0.35 }, ART .. "ui/ui_salvage.png")
	elseif kind == "scrap" and it then
		toast(string.format("Stash full: %s scrapped for %s metal", I.name(it), I.fmtNum(num)), { 1, 0.6, 0.3 }, icon)
	elseif kind == "refresh" and mine and num > 0 then
		toast(string.format("Shop refreshed for %s metal", I.fmtNum(num)), GOLD, ART .. "ui/ui_shop.png")
	elseif kind == "nometal" and mine then
		toast(it and string.format("Not enough metal for %s (%s)", I.name(it), I.fmtNum(num)) or string.format("Not enough metal (%s)", I.fmtNum(num)), RED)
		sound("cantdothat.wav", 0.6)
	elseif kind == "stashfull" and mine then
		toast("The team stash is full - salvage something first", RED)
		sound("cantdothat.wav", 0.6)
	elseif kind == "noshop" and mine then
		toast("The team has no item shop", RED)
	elseif kind == "dup" and mine and it then
		toast(string.format("%s is worn already (one of each unique / set piece)", I.name(it)), RED, icon)
		sound("cantdothat.wav", 0.6)
	elseif kind == "proc" then
		local info = I.powerInfo[str]
		toast(string.format("%s: %s!", heroName(unitID), info and info.label or str), { 1, 0.55, 0.2 })
	elseif kind == "drop" and it and (it.rarity == "unique" or it.rarity == "set") then
		toast(string.format("%s dropped!", I.name(it)), rc, icon)
	end
end

---------------------------------------------------------------------------- widget callins

local lastRefresh = -100
function widget:GameFrame(f)
	if f - lastRefresh >= 15 then
		lastRefresh = f
		refreshGround()
		for uid in pairs(wornCache) do
			if not spValidUnitID(uid) then
				wornCache[uid] = nil
			end
		end
	end
end

function widget:SelectionChanged(sel)
	sel = sel or Spring.GetSelectedUnits()
	local shopSel = false
	for _, uid in ipairs(sel) do
		if shopDefs[spGetUnitDefID(uid) or -1] and Spring.IsUnitAllied(uid) then
			shopSel = true
			break
		end
	end
	if shopSel and not showShop then
		showShop, shopAuto = true, true
		closeHeroWindows()
	elseif not shopSel and shopAuto then
		showShop, shopAuto = false, false
	end
end

function widget:ViewResize()
	K.resize()
end

function widget:DrawScreen()
	if not K.getFont() then
		return
	end
	K.beginFrame()
	slotRects = {}
	rects = {}
	-- the learn window of the console replaces the item windows
	if WG.T4HeroesUI and WG.T4HeroesUI.learnOpen and WG.T4HeroesUI.learnOpen() then
		showStash, showShop = false, false
	end
	-- the ground items (drawn under the UI in DrawScreenEffects) are the lowest boxes
	for _, gb in ipairs(groundBoxes) do
		rects[gb[1]] = { gb[2], gb[3], gb[4], gb[5] }
		if gb.tip then
			addBox(gb[2], gb[3], gb[4], gb[5], nil, gb.tip)
		end
	end
	K.font:Begin()
	local a = heroArea()
	if a then
		drawSlots(a)
	end
	local yb = windowBottom()
	local sx, px = windowXs()
	if showStash then
		drawStash(sx, yb)
	end
	if showShop then
		drawShop(px, yb)
	end
	drawToasts()
	K.font:End()
	-- the dragged item under the cursor
	if drag and drag.moved then
		local mx, my = Spring.GetMouseState()
		local s = floor(K.vsy * 0.045 * K.ui)
		local uid = selectedHero()
		local rc = I.color(drag.it)
		tex(iconOf(drag.it, factionOf(uid)), mx - s / 2, my - s / 2, mx + s / 2, my + s / 2, 1, 1, 1, 0.85)
		frame(mx - s / 2 - 2, my - s / 2 - 2, mx + s / 2 + 2, my + s / 2 + 2, { rc[1], rc[2], rc[3], 1 }, 2)
	end
	gl.Color(1, 1, 1, 1)
	local mx, my = Spring.GetMouseState()
	tip = (not (drag and drag.moved)) and K.tipAt(mx, my) or nil
end

-- ground items under every UI panel (DrawScreenEffects runs before DrawScreen)
function widget:DrawScreenEffects()
	if Spring.IsGUIHidden() or not K.getFont() then
		groundBoxes = {}
		return
	end
	K.font:Begin()
	drawGround()
	K.font:End()
	gl.Color(1, 1, 1, 1)
end

function widget:DrawScreenPost()
	if tip then
		local mx, my = Spring.GetMouseState()
		K.drawTip(tip, mx, my)
	end
end

function widget:IsAbove(x, y)
	return K.boxAt(x, y) ~= nil
end

function widget:GetTooltip()
	return nil
end

function widget:MousePress(x, y, button)
	local bx = K.boxAt(x, y)
	if not bx then
		-- a click outside closes the stash (not the shop of a selected shop building)
		if showStash and button == 1 then
			showStash, stashSlot, salvageSel = false, nil, nil
		end
		-- right click on a ground item: the selected units walk to it (a hero picks it up on arrival)
		if button == 3 then
			for _, s in ipairs(groundScreen) do
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
	if button == 1 and bx.drag and bx[8] and bx[8].stash then
		local e = bx[8].stash
		drag = { idx = e.idx, uid = e.it.uid, it = e.it, e = e, x0 = x, y0 = y, moved = false, fn = bx[5] }
		return true
	end
	if button == 1 and bx[5] then
		bx[5]()
	elseif button == 3 and bx[7] then
		bx[7]()
	end
	return true
end

function widget:MouseMove(x, y)
	if drag and not drag.moved and (math.abs(x - drag.x0) + math.abs(y - drag.y0)) > 6 then
		drag.moved = true
	end
end

function widget:MouseRelease(x, y, button)
	if not drag then
		return false
	end
	local d = drag
	drag = nil
	if not d.moved then
		if d.fn then
			d.fn()
		end
		return true
	end
	local uid, own = selectedHero()
	if not uid or not own then
		return true
	end
	for slot, r in pairs(slotRects) do
		if x >= r[1] - 4 and x <= r[3] + 4 and y >= r[2] - 4 and y <= r[4] + 4 then
			if I.slotCategory[slot] == d.it.cat then
				sendEquip(uid, slot, d.e)
			else
				toast(string.format("That is a %s item: %s slots only", I.categories[d.it.cat].label:lower(), I.categories[d.it.cat].label:lower()), RED)
				sound("cantdothat.wav", 0.5)
			end
			return true
		end
	end
	return true
end

function widget:KeyPress(key)
	if key == 27 and (showStash or showShop) then
		closeWindows()
		return true
	end
	return false
end

function widget:Initialize()
	widgetHandler:RegisterGlobal("T4HeroItemEvent", function(...) widget:T4HeroItemEvent(...) end)
	K.resize()
	WG.T4Items = {
		closeWindows = closeWindows,
		openStash = function(filter, slot) openStash(filter, slot) end,
		openShop = function() showShop = true; closeHeroWindows() end,
		markSalvage = function(idx)
			local uid = selectedHero()
			local e = readStash(stashTeam(uid))[idx]
			if e then
				salvageSel = { idx = e.idx, uid = e.it.uid }
			end
		end,
		slotRect = function(slot) return slotRects[slot] end,
		rect = function(name) return rects[name] end,
		toast = toast,
	}
	refreshGround()
	widget:SelectionChanged(Spring.GetSelectedUnits())
end

function widget:Shutdown()
	K.clearLists()
	WG.T4Items = nil
	widgetHandler:DeregisterGlobal("T4HeroItemEvent")
end
