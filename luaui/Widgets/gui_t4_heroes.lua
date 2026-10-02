--------------------------------------------------------------------------------
--
--  file:    gui_t4_heroes.lua
--  brief:   Warcraft 3 / Dota style UI of the custom T4 heroes (denysfast/bar-game), v19:
--           * the hero bar right of the minimap: up to 3 hero slots (alive: portrait, level, HP, XP, points;
--             fallen: revive level and price; free slot; locked slot "needs Altar Upgrade I/II" with the research)
--           * the hero console at the bottom when a hero is selected: portrait, HP / absorb / XP bars, name,
--             level, stat readout (DPS, range, speed, armor, regen, ability power, splash, penetration), buy level,
--             the four abilities on Q / W / E / R (a1 a2 a3 ult: icon, 10 rank pips, cooldown sweep, active / toggle
--             glow, passive marker), the five stats (Vitality, Mobility, Firepower, Reach, Impact, 15 ranks),
--             Dota-style learning: a "+" with the metal price over every branch that can take a rank now
--             (also Ctrl+Q/W/E/R), the learn window (U), autocast; the item area is left to gui_t4_items.lua
--           * the altar panel when a hero altar is selected: hero slots, the next Altar Upgrade, its research
--           * levels above heroes, aura rings, floating texts of the hero events
--  Rules: luarules/gadgets/unit_t4_heroes.lua (its header lists every rules param / message / event used here),
--  design data: luarules/configs/t4_heroes.lua + luarules/configs/heroes/<faction>.lua, art: bitmaps/t4heroes/.
--  Items (slots, stash, shop, ground items): luaui/Widgets/gui_t4_items.lua. Drawing kit: luaui/Include/t4heroes_ui.lua.
--  Licensed under the terms of the GNU GPL, v2 or later.
--
--------------------------------------------------------------------------------

local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name = "T4 Heroes",
		desc = "Warcraft-style hero bar, hero console (abilities Q/W/E/R, stats, learning), learn window and altar panel of the custom T4 heroes",
		author = "denysfast",
		date = "2026-10-02",
		license = "GNU GPL, v2 or later",
		layer = 5, -- above gui_t4_items (layer 4) in input order, below it in drawing
		enabled = true,
	}
end

local H = VFS.Include("luarules/configs/t4_heroes.lua")
local K = VFS.Include("luaui/Include/t4heroes_ui.lua")

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
local floor, max, min, sin = math.floor, math.max, math.min, math.sin

local ART = K.ART
local GOLD, WHITE, GREY, RED, GREEN, BLUE, ORANGE = K.GOLD, K.WHITE, K.GREY, K.RED, K.GREEN, K.BLUE, K.ORANGE
local rect, frame, tex, bar, text, addBox, hovered = K.rect, K.frame, K.tex, K.bar, K.text, K.addBox, K.hovered
local fmtNum = K.fmtNum

local CMD_HERO_AUTOCAST = 36100
local CMD_ALTAR_UPGRADE = 36400
local STAT_COLORS = { vit = { 0.45, 1, 0.45 }, mob = { 0.4, 0.9, 1 }, dmg = { 1, 0.55, 0.2 }, rng = { 0.75, 0.5, 1 }, imp = { 1, 0.82, 0.3 } }

local heroDefIDs = {} -- unitDefID -> hero name
local heroDefList = {}
local altarDefIDs = {}
for udid, ud in pairs(UnitDefs) do
	if H.heroes[ud.name] and ud.customParams.t4_hero then
		heroDefIDs[udid] = ud.name
		heroDefList[#heroDefList + 1] = udid
	end
	if ud.name == "armt4gant" or ud.name == "cort4gant" or ud.name == "legt4gant" then
		altarDefIDs[udid] = true
	end
end
local altarDefList = {}
for udid in pairs(altarDefIDs) do
	altarDefList[#altarDefList + 1] = udid
end

local tracked = {}  -- unitID -> hero name, every hero this client can see
local floating = {}
local cards = {}    -- the hero bar: { kind = "alive" | "building" | "dead" | "free" | "locked", ... }
local teamAltars = {}
local selectedHero  -- unitID shown in the console
local selectedAltar
local showLearn = false
local itemsArea     -- the rectangle of the console left to the items widget (this frame)
local consoleTop    -- top of the console / altar panel this frame (windows open above it)
local tip           -- tooltip of this frame (drawn in DrawScreenPost)
local rects = {}    -- named rectangles of this frame (scenes / tests): ability_<key>, stat_<key>, card_<i>, learn

local function myTeam()
	return Spring.GetMyTeamID()
end

local function heroTitle(name)
	local cfg = H.heroes[name]
	return cfg and cfg.title or name
end

local function metalNow()
	return Spring.GetTeamResources(myTeam(), "metal") or 0
end

---------------------------------------------------------------------------- art lookups

local exists = {}
local function fileExists(path)
	local e = exists[path]
	if e == nil then
		e = VFS.FileExists(path) and true or false
		exists[path] = e
	end
	return e
end

-- the portrait of a hero, or its unit buildpic while the portrait art is missing
local function portraitOf(name)
	local path = ART .. "portrait_" .. name .. ".png"
	if fileExists(path) then
		return path
	end
	local ud = UnitDefNames[name]
	return ud and ("#" .. ud.id) or path
end

-- ability icon: the def's icon, ab_<hero>_<key>, else the generic one
local function abilityIcon(name, key)
	local b = H.branch(name, key)
	if b and b.icon and fileExists(ART .. b.icon .. ".png") then
		return ART .. b.icon .. ".png"
	end
	local p = ART .. "ab_" .. name .. "_" .. key .. ".png"
	if fileExists(p) then
		return p
	end
	return ART .. "ui/ab_generic.png"
end

local function statIcon(key)
	return ART .. "stat_" .. key .. ".png"
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

-- the team's hero slots (SPEC section 3): heroes alive / being built / fallen, then free and locked slots
local function refreshCards()
	cards = {}
	local team = myTeam()
	teamAltars = {}
	for _, uid in ipairs(Spring.GetTeamUnitsByDefs(team, altarDefList) or {}) do
		local _, _, _, _, bp = spGetUnitHealth(uid)
		if bp and bp >= 1 then
			teamAltars[#teamAltars + 1] = uid
		end
	end
	local alive = {}
	for _, uid in ipairs(Spring.GetTeamUnitsByDefs(team, heroDefList) or {}) do
		local _, _, _, _, bp = spGetUnitHealth(uid)
		local name = heroDefIDs[spGetUnitDefID(uid)]
		if name and (not alive[name] or (bp or 0) >= 1) then
			alive[name] = { uid = uid, building = bp and bp < 1, progress = bp }
		end
	end
	for _, name in ipairs(H.order) do
		if UnitDefNames[name] then
			local deadLevel = spGetTeamRulesParam(team, "hero_dead_" .. name) or 0
			local a = alive[name]
			if a then
				cards[#cards + 1] = { kind = a.building and "building" or "alive", name = name, uid = a.uid, progress = a.progress, deadLevel = deadLevel }
			elseif deadLevel > 0 then
				cards[#cards + 1] = { kind = "dead", name = name, deadLevel = deadLevel, revive = spGetTeamRulesParam(team, "hero_revive_" .. name) or 0 }
			end
		end
	end
	if #cards == 0 and #teamAltars == 0 then
		cards = {}
		return
	end
	local slots = spGetTeamRulesParam(team, "hero_slots") or 1
	for i = #cards + 1, H.MAX_HEROES do
		if i <= slots then
			cards[#cards + 1] = { kind = "free", slot = i }
		else
			cards[#cards + 1] = { kind = "locked", slot = i, upgrade = i - 1 }
		end
	end
end

local function pickSelected()
	local keep, altar
	for _, uid in ipairs(Spring.GetSelectedUnits()) do
		local udid = spGetUnitDefID(uid) or -1
		if heroDefIDs[udid] then
			local _, _, _, _, bp = spGetUnitHealth(uid)
			if bp and bp >= 1 then
				if uid == selectedHero then
					keep = uid
					break
				end
				keep = keep or uid
			end
		elseif altarDefIDs[udid] and not altar then
			altar = uid
		end
	end
	selectedHero = keep
	selectedAltar = altar
	if not keep then
		showLearn = false
	end
end

---------------------------------------------------------------------------- actions

local function sound(name, vol)
	Spring.PlaySoundFile("sounds/ui/" .. name, vol or 0.5, "ui")
end

local function learn(uid, key)
	Spring.SendLuaRulesMsg("t4hero:learn:" .. uid .. ":" .. key)
	sound("beep6.wav", 0.5)
end

local function castAbility(uid, key)
	local name = heroDefIDs[spGetUnitDefID(uid) or -1]
	local b = name and H.heroes[name][key]
	if not b or not b.cmd or b.passive then
		return false
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
	return true
end

local function toggleAutocast(uid)
	local on = (spGetUnitRulesParam(uid, "hero_autocast") or 1) == 1
	Spring.GiveOrderToUnit(uid, CMD_HERO_AUTOCAST, { on and 0 or 1 }, 0)
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

local lastCardClick = { uid = nil, t = nil }

local function closeItemWindows()
	if WG.T4Items and WG.T4Items.closeWindows then
		WG.T4Items.closeWindows()
	end
end

local function setLearn(v)
	showLearn = v and true or false
	if showLearn then
		closeItemWindows()
	end
end

---------------------------------------------------------------------------- learn rules (client mirror of learnState)

-- state of the next rank of a branch: rank, maxRank, req (level), cost (metal), can (point + level), afford (metal)
local function branchState(uid, name, key, lvl, pts, metal)
	local rank = spGetUnitRulesParam(uid, "hero_rank_" .. key) or 0
	local maxRank = H.maxRank(name, key)
	local s = { rank = rank, maxRank = maxRank }
	if rank < maxRank then
		s.req = H.reqLevel(name, key, rank + 1)
		s.cost = H.metalCost(name, key, rank + 1)
		s.levelOk = lvl >= s.req
		s.can = pts > 0 and s.levelOk
		s.afford = metal >= s.cost
	end
	return s
end

---------------------------------------------------------------------------- tooltips

local function addLine(lines, str, c, size, sep)
	lines[#lines + 1] = { text = str, color = c, size = size, sep = sep }
end

local function addWrapped(lines, str, c, n, size)
	for _, l in ipairs(K.wrap(str, n or 62)) do
		addLine(lines, l, c, size)
	end
end

-- stat bonus of `ranks` ranks in units (SPEC section 2): HP, HP/s, speed, sight, damage % (+dps), range, splash, penetration
local function statUnits(uid, name, key, ranks)
	if ranks <= 0 then
		return "nothing yet"
	end
	local a = H.statAmount(name, key, ranks)
	local pct = function(v) return string.format("%d%%", floor(v * 100 + 0.5)) end
	if key == "vit" then
		return string.format("+%s HP, +%s HP/s", fmtNum(a.hp or 0), fmtNum(a.regen or 0))
	elseif key == "mob" then
		return string.format("+%s speed, +%s sight", H.fmtAmount and H.fmtAmount(a.speed or 0) or fmtNum(a.speed or 0), fmtNum(a.sight or 0))
	elseif key == "dmg" then
		local dps = uid and spGetUnitRulesParam(uid, "hero_dps") or 0
		local mult = uid and spGetUnitRulesParam(uid, "hero_dmgmult") or 1
		local base = mult > 0 and dps / mult or 0
		return string.format("+%s damage, all weapons%s", pct(a.damage or 0), base > 0 and string.format(" (+%s dps)", fmtNum(base * (a.damage or 0))) or "")
	elseif key == "rng" then
		local ud = UnitDefNames[name]
		local r = ud and ud.maxWeaponRange or 0
		return string.format("+%s range, all weapons%s", pct(a.range or 0), r > 0 and string.format(" (+%d)", floor(r * (a.range or 0) + 0.5)) or "")
	elseif key == "imp" then
		return string.format("+%s splash radius, +%s penetration", pct(a.splash or 0), pct(a.pierce or 0))
	end
	return ""
end

local function reqLine(lines, name, key, s)
	if s.rank >= s.maxRank then
		addLine(lines, "Maximum rank", GOLD)
		return
	end
	local c = (s.levelOk and s.afford) and { 0.8, 0.8, 0.8 } or RED
	addLine(lines, string.format("Rank %d: level %d, 1 point, %s metal", s.rank + 1, s.req, fmtNum(s.cost)), c, 0.9)
end

local function abilityTip(uid, name, key, s, lvl)
	local b = H.branch(name, key)
	local lines = {}
	addLine(lines, b.name or key, key == "ult" and ORANGE or GOLD, 1.15)
	local kind
	if b.passive then
		kind = "Passive"
	else
		kind = (key == "ult" and "Ultimate" or "Active") .. (b.toggle and " (toggle)" or "") .. "  -  hotkey " .. H.hotkeys[key]
		if b.target then
			kind = kind .. ", " .. (b.target == "ally" and "target an own unit" or b.target == "unit" and "target an enemy" or "target the map")
		end
	end
	addLine(lines, kind, b.passive and { 0.6, 0.75, 1 } or { 0.85, 0.85, 0.85 }, 0.9)
	local r = max(1, s.rank)
	local cd = b.cooldown and H.val(b.cooldown, r)
	local range = b.range and H.val(b.range, r)
	if cd or range then
		addLine(lines, (cd and string.format("Cooldown %d s", floor(cd + 0.5)) or "") .. (cd and range and "    " or "") .. (range and string.format("Range %d", floor(range + 0.5)) or ""), { 0.7, 0.85, 1 }, 0.9)
	end
	if b.desc then
		addWrapped(lines, b.desc, { 0.85, 0.8, 0.7 }, 62, 0.92)
	end
	addLine(lines, string.format("Rank %d / %d", s.rank, s.maxRank), WHITE, 1, true)
	if s.rank > 0 then
		addWrapped(lines, "Now: " .. H.abilityText(name, key, s.rank), { 0.5, 1, 0.5 }, 66, 0.92)
	else
		addLine(lines, "Not learned yet", GREY, 0.92)
	end
	if s.rank < s.maxRank then
		addWrapped(lines, "Next: " .. H.abilityText(name, key, s.rank + 1), { 1, 0.85, 0.35 }, 66, 0.92)
	end
	reqLine(lines, name, key, s)
	if not b.passive then
		local power = uid and spGetUnitRulesParam(uid, "hero_power")
		if power then
			addLine(lines, string.format("Ability power x%.2f at level %d", power, lvl), { 0.8, 0.65, 1 }, 0.85)
		end
	end
	return { lines = lines, border = key == "ult" and ORANGE or nil }
end

local function statTip(uid, name, key, s)
	local st = H.stats[key]
	local c = STAT_COLORS[key]
	local lines = {}
	addLine(lines, st.name, c, 1.15)
	addLine(lines, st.desc .. " - every weapon of the hero", { 0.85, 0.8, 0.7 }, 0.92)
	addLine(lines, string.format("Rank %d / %d", s.rank, s.maxRank), WHITE, 1, true)
	addLine(lines, "Now: " .. statUnits(uid, name, key, s.rank), { 0.5, 1, 0.5 }, 0.92)
	if s.rank < s.maxRank then
		addLine(lines, "Next: " .. statUnits(uid, name, key, s.rank + 1), { 1, 0.85, 0.35 }, 0.92)
		addLine(lines, "Per rank: " .. statUnits(uid, name, key, 1), GREY, 0.85)
	end
	reqLine(lines, name, key, s)
	return { lines = lines, border = c }
end

---------------------------------------------------------------------------- the "+" learn badge (Dota)

-- a pill "+ <price>" centred above the top edge of a button; red price = not enough metal
local function learnBadge(uid, key, s, cx, yTop, w, h)
	local x1, x2 = floor(cx - w / 2), floor(cx + w / 2)
	local y1, y2 = floor(yTop - h * 0.25), floor(yTop + h * 0.75)
	local hov = hovered(x1, y1, x2, y2)
	local glow = 0.5 + 0.5 * sin(spGetGameFrame() * 0.25)
	rect(x1 - 2, y1 - 2, x2 + 2, y2 + 2, { 1, 0.8, 0.2, 0.25 + 0.3 * glow })
	rect(x1, y1, x2, y2, hov and { 0.35, 0.26, 0.05, 1 } or { 0.16, 0.11, 0.02, 1 })
	frame(x1, y1, x2, y2, hov and K.HOVER or GOLD, 1)
	local size = h * 0.9
	local price = fmtNum(s.cost)
	local plusW = K.width("+", size)
	local psize = min(h * 0.74, (w - plusW - 4) / max(1, K.width(" " .. price, 1)))
	local tw = plusW + K.width(" " .. price, psize)
	local tx = cx - tw / 2
	text("+", tx, y1 + h * 0.12, size, GOLD, "o")
	text(" " .. price, tx + plusW, y1 + (h - psize) * 0.5 + psize * 0.18, psize, s.afford and { 1, 0.95, 0.7, 1 } or RED, "o")
	addBox(x1, y1, x2, y2, s.afford and function() learn(uid, key) end or nil,
		string.format("Learn rank %d for 1 point and %s metal%s (Ctrl + hotkey)", s.rank + 1, fmtNum(s.cost), s.afford and "" or "\n\255\255\090\090Not enough metal"))
end

---------------------------------------------------------------------------- hero bar (top left)

-- cards right of the minimap, one row of up to H.MAX_HEROES
local function cardLayout(n)
	local margin = floor(K.vsy * 0.012)
	local x1 = margin
	local mmX, mmY, mmW, mmH = Spring.GetMiniMapGeometry()
	if mmW and mmW > 0 and (mmX or 0) < K.vsx * 0.3 then
		x1 = (mmX or 0) + mmW + margin
	end
	local size = floor(K.vsy * 0.066 * K.ui)
	local gap = floor(size * 0.22)
	return x1, K.vsy - margin, size, gap
end

local function drawHeroBar()
	if #cards == 0 then
		return
	end
	local x0, yTop, size, gap = cardLayout(#cards)
	local f = spGetGameFrame()
	local barH = max(3, floor(size * 0.09))
	local team = myTeam()
	for i, c in ipairs(cards) do
		local xa = x0 + (i - 1) * (size + gap)
		local xb = xa + size
		local y2 = yTop
		local y1 = y2 - size
		rects["card_" .. i] = { xa, y1, xb, y2 }
		if c.kind == "alive" then
			local uid = c.uid
			local lvl = spGetUnitRulesParam(uid, "hero_level") or 1
			local xp = spGetUnitRulesParam(uid, "hero_xp") or 0
			local pts = spGetUnitRulesParam(uid, "hero_points") or 0
			local hp, maxHp = spGetUnitHealth(uid)
			local sel = uid == selectedHero
			if pts > 0 then
				local glow = 0.5 + 0.5 * sin(f * 0.2)
				rect(xa - 4, y1 - 4, xb + 4, y2 + 4, { 1, 0.8, 0.2, 0.3 + 0.35 * glow })
			end
			K.iconButton(portraitOf(c.name), xa, y1, xb, y2, true, sel and GOLD or nil, function()
				local now = Spring.GetTimer()
				local dbl = lastCardClick.uid == uid and lastCardClick.t and Spring.DiffTimers(now, lastCardClick.t) < 0.4
				focusUnit(uid, dbl)
				lastCardClick.uid, lastCardClick.t = uid, now
			end, string.format("%s - level %d\n%s%sClick: select, double click: go to", heroTitle(c.name), lvl,
				hp and maxHp and string.format("Health %d%%\n", floor(hp / maxHp * 100 + 0.5)) or "",
				pts > 0 and ("\255\255\210\064" .. pts .. " skill point" .. (pts == 1 and "" or "s") .. " to spend\255\255\255\255\n") or ""))
			local bs = max(12, floor(size * 0.36))
			rect(xb - bs, y1, xb, y1 + bs, { 0, 0, 0, 0.85 })
			frame(xb - bs, y1, xb, y1 + bs, GOLD, 1)
			text(tostring(lvl), xb - bs / 2, y1 + bs * 0.22, bs * 0.62, GOLD, "co")
			if pts > 0 then
				text("+" .. pts, xa + size * 0.06, y2 - size * 0.32, size * 0.28, { 1, 0.85, 0.2, 1 }, "o")
			end
			local absorb = spGetUnitRulesParam(uid, "hero_absorb") or 0
			local absorbMax = spGetUnitRulesParam(uid, "hero_absorb_max") or 0
			bar(xa, y1 - 2 - barH, xb, y1 - 2, hp and maxHp and hp / maxHp or 0, { 0.2, 0.9, 0.25, 1 })
			if absorb > 0 and absorbMax > 0 then
				rect(xa + 1, y1 - 2 - barH * 0.45, xa + 1 + (size - 2) * min(1, absorb / absorbMax), y1 - 3, { 0.85, 0.9, 1, 0.9 })
			end
			bar(xa, y1 - 3 - barH * 2, xb, y1 - 3 - barH, xp, { 0.55, 0.35, 1, 1 })
		elseif c.kind == "building" then
			K.iconButton(portraitOf(c.name), xa, y1, xb, y2, false, nil, function() focusUnit(c.uid, true) end,
				c.deadLevel > 0 and string.format("Reviving %s at level %d", heroTitle(c.name), c.deadLevel) or string.format("Building %s", heroTitle(c.name)))
			bar(xa, y1 - 2 - barH, xb, y1 - 2, c.progress or 0, { 0.5, 0.75, 1, 0.9 })
			text(string.format("%d%%", floor((c.progress or 0) * 100)), (xa + xb) / 2, y1 + size * 0.38, size * 0.24, WHITE, "co")
		elseif c.kind == "dead" then
			K.iconButton(portraitOf(c.name), xa, y1, xb, y2, false, { 0.55, 0.1, 0.1, 1 }, function()
				if teamAltars[1] then
					focusUnit(teamAltars[1], true)
				end
			end, string.format("%s has fallen at level %d.\nIt keeps its hero slot: revive it at the hero altar\nfor %s metal (it comes back at level %d).\nClick: select the altar",
				heroTitle(c.name), c.deadLevel + H.DEATH_LEVELS, fmtNum(c.revive), c.deadLevel))
			rect(xa, y1, xb, y2, { 0.2, 0, 0, 0.3 })
			rect(xa, y1 + size * 0.28, xb, y1 + size * 0.72, { 0, 0, 0, 0.55 })
			text("FALLEN", (xa + xb) / 2, y1 + size * 0.55, size * 0.2, { 1, 0.3, 0.25, 1 }, "co")
			text("Lv " .. c.deadLevel, (xa + xb) / 2, y1 + size * 0.33, size * 0.2, WHITE, "co")
			rect(xa, y1 - 3 - barH * 2, xb, y1 - 2, { 0.2, 0.04, 0.03, 0.9 })
			text(fmtNum(c.revive) .. " M", (xa + xb) / 2, y1 - 2 - barH * 1.8, barH * 1.5, { 1, 0.75, 0.4, 1 }, "co")
		elseif c.kind == "free" then
			local hov = hovered(xa, y1, xb, y2)
			rect(xa, y1, xb, y2, { 0.06, 0.06, 0.08, 0.85 })
			frame(xa, y1, xb, y2, hov and K.HOVER or { 0.4, 0.33, 0.18, 1 }, 2)
			text("+", (xa + xb) / 2, y1 + size * 0.3, size * 0.5, { 1, 0.85, 0.35, 0.8 }, "co")
			text("free", (xa + xb) / 2, y1 + size * 0.1, size * 0.18, GREY, "co")
			addBox(xa, y1, xb, y2, teamAltars[1] and function() focusUnit(teamAltars[1], true) end or nil,
				string.format("Hero slot %d is free: build a hero at the hero altar%s", c.slot, teamAltars[1] and "\nClick: select the altar" or "\n(build a hero altar first)"))
		else -- locked
			local up = H.SLOT_UPGRADES[c.upgrade] or {}
			local rFrame = spGetTeamRulesParam(team, "hero_slots_research") or 0
			local rLevel = spGetTeamRulesParam(team, "hero_slots_research_level") or 0
			local researching = rFrame > f and rLevel == c.upgrade
			local hov = hovered(xa, y1, xb, y2)
			rect(xa, y1, xb, y2, { 0.03, 0.03, 0.04, 0.85 })
			frame(xa, y1, xb, y2, hov and K.HOVER or { 0.25, 0.22, 0.18, 1 }, 2)
			K.lock((xa + xb) / 2, y1 + size * 0.6, size * 0.34, researching and { 1, 0.85, 0.35, 1 } or { 0.55, 0.5, 0.42, 1 })
			local nm = (up.name or "Altar Upgrade"):gsub("^Altar ", "")
			text(nm, (xa + xb) / 2, y1 + size * 0.12, size * 0.17, researching and GOLD or GREY, "co")
			local t
			if researching then
				local total = (up.time or 45) * 30
				bar(xa, y1 - 2 - barH, xb, y1 - 2, 1 - (rFrame - f) / total, { 1, 0.75, 0.2, 1 })
				t = string.format("Hero slot %d: %s is being researched, %d s left", c.slot, up.name or "", math.ceil((rFrame - f) / 30))
			else
				t = string.format("Hero slot %d is locked: needs %s\n(%s metal, %s energy, %d s of research at the altar)%s", c.slot, up.name or "an altar upgrade",
					fmtNum(up.metal or 0), fmtNum(up.energy or 0), up.time or 45,
					c.upgrade > (spGetTeamRulesParam(team, "hero_slots") or 1) and ("\nafter " .. ((H.SLOT_UPGRADES[c.upgrade - 1] or {}).name or "the previous one")) or "")
			end
			addBox(xa, y1, xb, y2, teamAltars[1] and function() focusUnit(teamAltars[1], true) end or nil, t .. (teamAltars[1] and "\nClick: select the altar" or ""))
		end
	end
end

---------------------------------------------------------------------------- console (bottom)

-- the free strip between BAR's order menu (bottom left) and the player list (bottom right)
local function bottomStrip()
	local vsx, vsy = K.vsx, K.vsy
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
	return left, right
end

local CONSOLE_W = 4.35 -- console width in console heights

-- a two-column readout: rows = { { label, value, color }, ... } (odd = left column, even = right); widths measured,
-- the font shrinks until both columns fit `width`
local function readoutGrid(rows, x, yTop, width, size, step)
	local function colW(from)
		local lw, vw = 0, 0
		for i = from, #rows, 2 do
			lw = max(lw, K.width(rows[i][1], size))
			vw = max(vw, K.width(rows[i][2], size))
		end
		return lw, vw
	end
	local l1, v1 = colW(1)
	local l2, v2 = colW(2)
	local gap = size * 0.5
	local total = l1 + gap + v1 + size * 1.2 + l2 + gap + v2
	if total > width then
		local k = width / total
		size, l1, v1, l2, v2, gap = size * k, l1 * k, v1 * k, l2 * k, v2 * k, gap * k
	end
	local x2 = x + width - (l2 + gap + v2)
	for i, r in ipairs(rows) do
		local row = floor((i - 1) / 2)
		local y = yTop - row * step
		local cx = (i % 2 == 1) and x or x2
		local lw = (i % 2 == 1) and l1 or l2
		text(r[1], cx, y, size, GREY)
		text(r[2], cx + lw + gap, y, size, r[3] or WHITE)
	end
end

local function drawBuyLevel(uid, name, lvl, x1, y1, x2, y2, f)
	if lvl >= H.MAX_LEVEL then
		rect(x1, y1, x2, y2, { 0.12, 0.1, 0.04, 0.9 })
		frame(x1, y1, x2, y2, GOLD, 1)
		text("Maximum level", (x1 + x2) / 2, y1 + (y2 - y1) * 0.28, (y2 - y1) * 0.48, GOLD, "co")
		return
	end
	local price = spGetUnitRulesParam(uid, "hero_buy_price") or H.levelPrice(name, lvl) or 0
	local ready = spGetUnitRulesParam(uid, "hero_buy_ready") or 0
	local cur, storage = Spring.GetTeamResources(myTeam(), "metal")
	cur, storage = cur or 0, storage or 0
	local wait = ready > f and math.ceil((ready - f) / 30) or 0
	local ok = price > 0 and cur >= price and wait == 0
	local label = wait > 0 and string.format("Buy level  (%d s)", wait) or string.format("Buy level  %s M", fmtNum(price))
	local tipStr = string.format("Buy level %d for %s metal (%s in storage%s).\n"
		.. "The price grows with the level and the hero's cost: %d%% + %d%% per level of its cost, and never\n"
		.. "less than the metal of damage that level takes in combat. One level per %d seconds.",
		lvl + 1, fmtNum(price), fmtNum(cur), storage < price and (", storage holds only " .. fmtNum(storage)) or "",
		floor(H.BUY_BASE * 100 + 0.5), floor(H.BUY_PER_LEVEL * 100 + 0.5), H.BUY_COOLDOWN)
	K.button(label, x1, y1, x2, y2, ok and GOLD or { 0.7, 0.2, 0.15, 1 }, true, ok and function() Spring.SendLuaRulesMsg("t4hero:buylevel:" .. uid) end or nil,
		tipStr, { textColor = ok and GOLD or RED, border = 2 })
end

-- one ability button: icon, hotkey, passive band, rank pips, cooldown sweep, active / toggle glow, the "+" badge
local function drawAbility(uid, name, key, own, lvl, pts, metal, bx1, by1, cs, f)
	local b = H.branch(name, key)
	local bx2, by2 = bx1 + cs, by1 + cs
	local s = branchState(uid, name, key, lvl, pts, metal)
	local ready = spGetUnitRulesParam(uid, "hero_ready_" .. key) or 0
	local cd = spGetUnitRulesParam(uid, "hero_cd_" .. key) or 0
	local on = spGetUnitRulesParam(uid, "hero_on_" .. key) or 0
	local dur = spGetUnitRulesParam(uid, "hero_dur_" .. key) or 0
	local toggled = (spGetUnitRulesParam(uid, "hero_toggle_" .. key) or 0) == 1
	local active = on > f or toggled
	local castable = own and s.rank > 0 and b.cmd and not b.passive and ready <= f
	rects["ability_" .. key] = { bx1, by1, bx2, by2 }
	if active then
		local glow = 0.5 + 0.5 * sin(f * 0.35)
		local c = toggled and { 0.35, 0.85, 1 } or { 0.4, 1, 0.5 }
		rect(bx1 - 6, by1 - 6, bx2 + 6, by2 + 6, { c[1], c[2], c[3], 0.35 + 0.4 * glow })
	end
	local border = key == "ult" and ORANGE or (b.passive and { 0.4, 0.5, 0.65, 1 } or nil)
	K.iconButton(abilityIcon(name, key), bx1, by1, bx2, by2, s.rank > 0, border,
		castable and function() castAbility(uid, key) end or nil,
		function() return abilityTip(uid, name, key, s, lvl) end)
	if b.passive then
		rect(bx1, by1, bx2, by1 + cs * 0.2, { 0, 0, 0, 0.7 })
		text("PASSIVE", (bx1 + bx2) / 2, by1 + cs * 0.055, cs * 0.14, { 0.65, 0.78, 1, 1 }, "co")
	end
	if on > f and dur > 0 then
		bar(bx1, by2 - cs * 0.09, bx2, by2, (on - f) / dur, { 0.4, 1, 0.5, 1 })
	elseif toggled then
		rect(bx2 - cs * 0.34, by2 - cs * 0.22, bx2, by2, { 0, 0.15, 0.25, 0.9 })
		text("ON", bx2 - cs * 0.17, by2 - cs * 0.18, cs * 0.16, { 0.4, 0.9, 1, 1 }, "co")
	end
	if ready > f and cd > 0 and s.rank > 0 then
		K.sweep(bx1, by1, bx2, by2, (ready - f) / cd)
		text(tostring(floor((ready - f) / 30) + 1), (bx1 + bx2) / 2, by1 + cs * 0.34, cs * 0.36, WHITE, "co")
	end
	if not b.passive then
		rect(bx1, by2 - cs * 0.26, bx1 + cs * 0.26, by2, { 0, 0, 0, 0.8 })
		text(H.hotkeys[key], bx1 + cs * 0.13, by2 - cs * 0.205, cs * 0.19, GOLD, "co")
	end
	-- 10 rank pips under the icon
	local n = s.maxRank
	local pg = max(1, floor(cs * 0.025))
	local pw = (cs - pg * (n - 1)) / n
	local py2 = by1 - cs * 0.06
	local py1 = py2 - max(3, cs * 0.075)
	for p = 1, n do
		local px = bx1 + (p - 1) * (pw + pg)
		local nextLvl = p == s.rank + 1 and s.can
		rect(px, py1, px + pw, py2, p <= s.rank and (key == "ult" and ORANGE or GOLD) or (nextLvl and { 0.5, 0.42, 0.15, 1 } or { 0.16, 0.16, 0.16, 0.95 }))
	end
	if own and s.can and s.rank < s.maxRank then
		learnBadge(uid, key, s, (bx1 + bx2) / 2, by2, cs * 0.92, cs * 0.3)
	end
end

local function drawStat(uid, name, key, own, lvl, pts, metal, bx1, by1, ss)
	local s = branchState(uid, name, key, lvl, pts, metal)
	local c = STAT_COLORS[key]
	local bx2, by2 = bx1 + ss, by1 + ss
	rects["stat_" .. key] = { bx1, by1, bx2, by2 }
	K.iconButton(statIcon(key), bx1, by1, bx2, by2, true, { c[1] * 0.55, c[2] * 0.55, c[3] * 0.55, 1 }, nil,
		function() return statTip(uid, name, key, s) end)
	if s.rank == 0 then
		rect(bx1, by1, bx2, by2, { 0, 0, 0, 0.45 })
	end
	-- rank under the icon and a thin progress line
	text(string.format("%d/%d", s.rank, s.maxRank), (bx1 + bx2) / 2, by1 - ss * 0.34, ss * 0.27, s.rank >= s.maxRank and GOLD or { 0.85, 0.85, 0.85, 1 }, "co")
	rect(bx1, by1 - ss * 0.08, bx2, by1 - ss * 0.03, { 0.12, 0.12, 0.12, 0.9 })
	rect(bx1, by1 - ss * 0.08, bx1 + ss * s.rank / s.maxRank, by1 - ss * 0.03, { c[1], c[2], c[3], 1 })
	if own and s.can and s.rank < s.maxRank then
		learnBadge(uid, key, s, (bx1 + bx2) / 2, by2, ss * 1.12, ss * 0.36)
	end
end

local function consoleGeometry()
	local left, right = bottomStrip()
	local H0 = floor(min(K.vsy * 0.215 * K.ui, (right - left) / CONSOLE_W))
	local W = floor(H0 * CONSOLE_W)
	local x1 = floor(left + (right - left - W) / 2)
	local y1 = floor(K.vsy * 0.005)
	return x1, y1, x1 + W, y1 + H0, H0
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
	local metal = metalNow()
	local f = spGetGameFrame()

	local x1, y1, x2, y2, H0 = consoleGeometry()
	local u = function(v) return floor(H0 * v) end
	K.panel(x1, y1, x2, y2)
	addBox(x1, y1, x2, y2, nil, nil)

	-- portrait, level badge, HP / absorb / XP bars
	local ps = u(0.62)
	local px1, py2 = x1 + u(0.07), y2 - u(0.07)
	local px2, py1 = px1 + ps, py2 - ps
	rect(px1 - 3, py1 - 3, px2 + 3, py2 + 3, { 0, 0, 0, 1 })
	tex(portraitOf(name), px1, py1, px2, py2)
	frame(px1 - 3, py1 - 3, px2 + 3, py2 + 3, GOLD, 2)
	local bs = u(0.17)
	rect(px2 - bs, py1, px2, py1 + bs, { 0, 0, 0, 0.85 })
	frame(px2 - bs, py1, px2, py1 + bs, GOLD, 1)
	text(tostring(lvl), px2 - bs / 2, py1 + bs * 0.22, bs * 0.6, GOLD, "co")
	addBox(px1, py1, px2, py2, nil, string.format("%s\n%s - level %d", cfg.title or name, cfg.role or "", lvl))
	local hp, maxHp = spGetUnitHealth(uid)
	local bh = u(0.075)
	local hy2 = py1 - u(0.045)
	bar(px1, hy2 - bh, px2, hy2, hp and maxHp and hp / maxHp or 0, { 0.15, 0.85, 0.2, 1 })
	local absorb = spGetUnitRulesParam(uid, "hero_absorb") or 0
	local absorbMax = spGetUnitRulesParam(uid, "hero_absorb_max") or 0
	if absorb > 0 and absorbMax > 0 then
		rect(px1 + 1, hy2 - bh * 0.35, px1 + 1 + (ps - 2) * min(1, absorb / absorbMax), hy2 - 1, { 0.85, 0.92, 1, 0.95 })
	end
	if hp then
		text(string.format("%s / %s", fmtNum(hp * hpMult), fmtNum(maxHp * hpMult)), (px1 + px2) / 2, hy2 - bh * 0.82, bh * 0.78, WHITE, "co")
	end
	addBox(px1, hy2 - bh, px2, hy2, nil, string.format("Health %s / %s (effective)%s", fmtNum((hp or 0) * hpMult), fmtNum((maxHp or 0) * hpMult),
		absorb > 0 and string.format("\nAbsorb shield %s / %s", fmtNum(absorb), fmtNum(absorbMax)) or ""))
	local xy2 = hy2 - bh - u(0.03)
	bar(px1, xy2 - bh * 0.8, px2, xy2, lvl >= H.MAX_LEVEL and 1 or xp, { 0.55, 0.35, 1, 1 })
	text(lvl >= H.MAX_LEVEL and "MAX" or string.format("%d%%", floor(xp * 100)), (px1 + px2) / 2, xy2 - bh * 0.7, bh * 0.62, { 0.9, 0.85, 1, 1 }, "co")
	addBox(px1, xy2 - bh * 0.8, px2, xy2, nil, lvl >= H.MAX_LEVEL and "Maximum level"
		or string.format("Experience: %s / %s metal of damage to reach level %d", fmtNum(xpAbs), fmtNum(xpNeed), lvl + 1))

	-- name, level, readout, buy level
	local sx = x1 + u(0.77)
	local colW = u(1.08)
	local ts = H0 * 0.1
	text(K.fit(cfg.title or name, ts, colW), sx, y2 - u(0.07) - ts * 0.85, ts, GOLD)
	local lvlStr = string.format("Level %d   %s", lvl, cfg.role or "")
	text(K.fit(lvlStr, ts * 0.68, colW), sx, y2 - u(0.07) - ts * 1.9, ts * 0.68, WHITE)
	local rs = H0 * 0.064
	local ry = y2 - u(0.36)
	local dps = spGetUnitRulesParam(uid, "hero_dps") or 0
	local range = spGetUnitRulesParam(uid, "hero_range") or 0
	local speed = spGetUnitRulesParam(uid, "hero_speed") or 0
	local armor = spGetUnitRulesParam(uid, "hero_armor") or 0
	local regenHps = spGetUnitRulesParam(uid, "hero_regen_hps") or 0
	local power = spGetUnitRulesParam(uid, "hero_power") or 1
	local splash = spGetUnitRulesParam(uid, "hero_splash") or 0
	local pierce = spGetUnitRulesParam(uid, "hero_pierce") or 0
	local kills = spGetUnitRulesParam(uid, "hero_kills") or 0
	local step = rs * 1.38
	readoutGrid({
		{ "Damage", fmtNum(dps) .. " dps", ORANGE }, { "Range", tostring(floor(range + 0.5)), { 0.8, 0.65, 1, 1 } },
		{ "Speed", string.format("%d", floor(speed + 0.5)) }, { "Armor", string.format("%d%%", floor(armor * 100 + 0.5)), BLUE },
		{ "Regen", fmtNum(regenHps) .. " HP/s", GREEN }, { "Power", string.format("x%.2f", power), { 0.8, 0.65, 1, 1 } },
		{ "Splash", string.format("+%d%%", floor(splash * 100 + 0.5)), { 1, 0.82, 0.3, 1 } }, { "Pierce", string.format("%d%%", floor(pierce * 100 + 0.5)), { 1, 0.82, 0.3, 1 } },
	}, sx, ry, colW, rs, step)
	addBox(sx, ry - step * 3 - rs * 0.3, sx + colW, ry + rs * 1.1, nil, string.format(
		"Damage: %s per second, all weapons (weapon damage x%.2f)\nRange: %d (longest weapon)\nSpeed: %d    Armor: %d%% less damage taken\n"
		.. "Regeneration: %s HP per second    Toughness x%.2f\nAbility power x%.2f (ability damage, healing, shields)\n"
		.. "Splash: +%d%% blast radius    Penetration: %d%% of a hit also strikes the enemies behind the target\nKills: %d",
		fmtNum(dps), spGetUnitRulesParam(uid, "hero_dmgmult") or 1, floor(range + 0.5), floor(speed + 0.5), floor(armor * 100 + 0.5),
		fmtNum(regenHps), hpMult, power, floor(splash * 100 + 0.5), floor(pierce * 100 + 0.5), kills))
	if own then
		drawBuyLevel(uid, name, lvl, sx, y1 + u(0.06), sx + colW, y1 + u(0.165), f)
		local by1, by2 = y1 + u(0.19), y1 + u(0.295)
		local lx2 = sx + floor(colW * 0.64)
		local glowOn = pts > 0 and (0.5 + 0.5 * sin(f * 0.25)) or 0
		K.button(pts > 0 and string.format("Learn  +%d   [U]", pts) or "Learn  [U]", sx, by1, lx2, by2, GOLD, true,
			function() setLearn(not showLearn) end,
			"The learn window: every ability and stat, what the next rank gives and costs (hotkey U).\nOn the console: click a \"+\" (or Ctrl + Q/W/E/R) to learn a rank.",
			{ glow = glowOn, textColor = pts > 0 and GOLD or WHITE, size = (by2 - by1) * 0.56 })
		local auto = (spGetUnitRulesParam(uid, "hero_autocast") or 1) == 1
		K.button(auto and "Autocast" or "Manual", lx2 + u(0.03), by1, sx + colW, by2, auto and GREEN or GREY, true, function() toggleAutocast(uid) end,
			"Autocast: the hero uses its abilities by itself when they help (click to toggle)", { textColor = auto and GREEN or GREY, size = (by2 - by1) * 0.52 })
	end

	-- the item area (gui_t4_items.lua draws it)
	itemsArea = { x1 = x1 + u(1.92), y1 = y1 + u(0.06), x2 = x1 + u(2.80), y2 = y2 - u(0.05), uid = uid, own = own, H0 = H0 }

	-- abilities Q W E R
	local ax1 = x1 + u(2.88)
	local cs = u(0.30)
	local cg = floor((u(1.41) - cs * 4) / 3)
	local aby1 = y2 - u(0.15) - cs
	for i, key in ipairs(H.abilityKeys) do
		if cfg[key] then
			drawAbility(uid, name, key, own, lvl, pts, metal, ax1 + (i - 1) * (cs + cg), aby1, cs, f)
		end
	end
	-- the five stats
	local ss = u(0.25)
	local sg = floor((u(1.41) - ss * 5) / 4)
	local sby1 = y1 + u(0.15)
	for i, key in ipairs(H.statKeys) do
		drawStat(uid, name, key, own, lvl, pts, metal, ax1 + (i - 1) * (ss + sg), sby1, ss)
	end
	return y2
end

---------------------------------------------------------------------------- learn window (U)

local function drawLearn(uid, yBottom)
	local name = heroDefIDs[spGetUnitDefID(uid) or -1]
	if not name then
		return
	end
	local cfg = H.heroes[name]
	local own = spGetUnitTeam(uid) == myTeam()
	local lvl = spGetUnitRulesParam(uid, "hero_level") or 1
	local pts = spGetUnitRulesParam(uid, "hero_points") or 0
	local metal = metalNow()
	local rh = floor(K.vsy * 0.052 * K.ui)
	local pad = floor(rh * 0.3)
	local colW = floor(rh * 9.6)
	local head = floor(rh * 0.9)
	local W = colW * 2 + pad * 3
	local rows = 5
	local Ht = head + pad + rows * (rh + pad) + floor(rh * 0.55) + pad
	local x1 = floor((K.vsx - W) / 2)
	local x2 = x1 + W
	local y1 = yBottom + floor(K.vsy * 0.01)
	local y2 = min(K.vsy - 8, y1 + Ht)
	K.panel(x1, y1, x2, y2)
	addBox(x1, y1, x2, y2, nil, nil)
	text("Learn", x1 + pad * 1.5, y2 - head * 0.72, head * 0.48, GOLD)
	text(string.format("%s  -  level %d    %s%d point%s\255\255\255\255    %s metal", cfg.title or name, lvl, pts > 0 and "\255\255\210\064" or "", pts, pts == 1 and "" or "s", fmtNum(metal)),
		x2 - head * 1.1, y2 - head * 0.66, head * 0.36, WHITE, "ro")
	K.closeButton(x2 - pad, y2 - pad, floor(head * 0.55), function() showLearn = false end)

	local function row(key, cx, cy, isStat)
		local b = H.branch(name, key)
		local s = branchState(uid, name, key, lvl, pts, metal)
		local icon = isStat and statIcon(key) or abilityIcon(name, key)
		local c = isStat and STAT_COLORS[key] or (key == "ult" and ORANGE or GOLD)
		local hov = hovered(cx, cy, cx + colW, cy + rh)
		rect(cx, cy, cx + colW, cy + rh, hov and { 0.16, 0.13, 0.07, 0.9 } or { 0.07, 0.07, 0.09, 0.85 })
		local is = rh - 6
		K.iconButton(icon, cx + 3, cy + 3, cx + 3 + is, cy + 3 + is, s.rank > 0 or isStat, nil, nil, nil)
		local tx = cx + rh + pad * 0.5
		local nameStr = (b.name or key) .. (isStat and "" or (b.passive and "  (passive)" or ("  [" .. H.hotkeys[key] .. "]")))
		text(nameStr, tx, cy + rh * 0.66, rh * 0.25, { c[1], c[2], c[3], 1 })
		-- pips
		local n = s.maxRank
		local pw = rh * (isStat and 0.12 or 0.18)
		local pxs = tx + rh * 3.6
		for p = 1, n do
			rect(pxs + (p - 1) * pw * 1.3, cy + rh * 0.7, pxs + (p - 1) * pw * 1.3 + pw, cy + rh * 0.82,
				p <= s.rank and { c[1], c[2], c[3], 1 } or { 0.2, 0.2, 0.2, 0.95 })
		end
		local now = s.rank > 0 and (isStat and statUnits(uid, name, key, s.rank) or H.abilityText(name, key, s.rank)) or "not learned"
		local nxt = s.rank < s.maxRank and (isStat and statUnits(uid, name, key, s.rank + 1) or H.abilityText(name, key, s.rank + 1)) or nil
		local tw = colW - rh - pad * 0.5 - rh * 1.9
		text(K.fit("Now: " .. now, rh * 0.21, tw), tx, cy + rh * 0.4, rh * 0.21, s.rank > 0 and { 0.55, 1, 0.55, 1 } or GREY)
		if nxt then
			text(K.fit("Next: " .. nxt, rh * 0.21, tw), tx, cy + rh * 0.12, rh * 0.21, { 1, 0.85, 0.35, 1 })
		end
		addBox(cx, cy, cx + colW - rh * 1.8, cy + rh, nil, function()
			return isStat and statTip(uid, name, key, s) or abilityTip(uid, name, key, s, lvl)
		end)
		-- the learn button: "+ price" or the level it needs
		local bx1, bx2 = cx + colW - rh * 1.75, cx + colW - pad * 0.5
		local by1, by2 = cy + rh * 0.2, cy + rh * 0.8
		if s.rank >= s.maxRank then
			text("MAX", (bx1 + bx2) / 2, by1 + rh * 0.14, rh * 0.28, GOLD, "co")
		elseif not s.levelOk then
			K.button("lv " .. s.req, bx1, by1, bx2, by2, GREY, false, nil, string.format("Rank %d needs hero level %d", s.rank + 1, s.req))
		else
			local ok = own and pts > 0 and s.afford
			K.button("+ " .. fmtNum(s.cost), bx1, by1, bx2, by2, s.afford and GOLD or RED, ok, function() learn(uid, key) end,
				string.format("Learn rank %d: 1 point and %s metal%s", s.rank + 1, fmtNum(s.cost),
					pts == 0 and "\n\255\255\090\090No points left" or (not s.afford and "\n\255\255\090\090Not enough metal" or "")),
				{ textColor = s.afford and (pts > 0 and GOLD or GREY) or RED, glow = ok and (0.5 + 0.5 * sin(spGetGameFrame() * 0.25)) or 0 })
		end
	end

	local top = y2 - head - pad
	text("Abilities", x1 + pad, top - rh * 0.32, rh * 0.26, WHITE)
	text("Stats  (same for every hero)", x1 + pad * 2 + colW, top - rh * 0.32, rh * 0.26, WHITE)
	top = top - rh * 0.45
	for i, key in ipairs(H.abilityKeys) do
		if cfg[key] then
			row(key, x1 + pad, top - i * (rh + pad), false)
		end
	end
	for i, key in ipairs(H.statKeys) do
		row(key, x1 + pad * 2 + colW, top - i * (rh + pad), true)
	end
	text(string.format("Metal per rank: abilities %s x rank (level 1, 3, 6 ... 27), ultimate %s x rank (level 10, 20 ... 100), stats %s x rank (level = rank)",
		fmtNum(H.ABILITY_METAL), fmtNum(H.ULT_METAL), fmtNum(H.STAT_METAL)), x1 + pad, y1 + pad * 0.9, rh * 0.2, GREY)
	return y2
end

---------------------------------------------------------------------------- altar panel

local function drawAltar(altarID)
	local team = spGetUnitTeam(altarID)
	if not team or not spIsUnitAllied(altarID) then
		return
	end
	local own = team == myTeam()
	local f = spGetGameFrame()
	local slots = spGetTeamRulesParam(team, "hero_slots") or 1
	local used = spGetTeamRulesParam(team, "hero_slots_used") or 0
	local rFrame = spGetTeamRulesParam(team, "hero_slots_research") or 0
	local rLevel = spGetTeamRulesParam(team, "hero_slots_research_level") or 0
	local researching = rFrame > f
	local cx1, cy1, cx2, _, H0 = consoleGeometry()
	local W = floor(H0 * 2.9)
	local Hh = floor(H0 * 0.78)
	local x1 = floor((cx1 + cx2 - W) / 2)
	local x2, y1 = x1 + W, cy1
	local y2 = y1 + Hh
	local u = function(v) return floor(H0 * v) end
	K.panel(x1, y1, x2, y2)
	addBox(x1, y1, x2, y2, nil, nil)
	local is = u(0.34)
	tex(ART .. "ui/ui_altar.png", x1 + u(0.08), y2 - u(0.08) - is, x1 + u(0.08) + is, y2 - u(0.08))
	frame(x1 + u(0.08) - 2, y2 - u(0.08) - is - 2, x1 + u(0.08) + is + 2, y2 - u(0.08) + 2, GOLD, 1)
	local tx = x1 + u(0.5)
	text("Hero Altar", tx, y2 - u(0.17), H0 * 0.1, GOLD)
	text(string.format("Hero slots: %d used of %d open (max %d)", used, slots, H.MAX_HEROES), tx, y2 - u(0.28), H0 * 0.062, WHITE)
	-- three sockets: the heroes in them (portraits; fallen ones dark red), free, locked
	local inSlot = {}
	if own then
		for _, c in ipairs(cards) do
			if c.name then
				inSlot[#inSlot + 1] = c
			end
		end
	end
	local ss = u(0.17)
	for i = 1, H.MAX_HEROES do
		local sx = tx + (i - 1) * (ss + u(0.06))
		local sy = y2 - u(0.36) - ss
		local open = i <= slots
		rect(sx, sy, sx + ss, sy + ss, open and (i <= used and { 0.35, 0.25, 0.05, 1 } or { 0.12, 0.1, 0.05, 1 }) or { 0.04, 0.04, 0.05, 1 })
		frame(sx, sy, sx + ss, sy + ss, open and GOLD or { 0.3, 0.27, 0.22, 1 }, 1)
		if not open then
			K.lock(sx + ss / 2, sy + ss / 2, ss * 0.6, researching and rLevel == i - 1 and GOLD or { 0.5, 0.45, 0.38, 1 })
		elseif inSlot[i] then
			local c = inSlot[i]
			local dead = c.kind == "dead"
			tex(portraitOf(c.name), sx + 1, sy + 1, sx + ss - 1, sy + ss - 1, dead and 0.85 or 1, dead and 0.4 or 1, dead and 0.35 or 1, 1)
		elseif i <= used then
			text("H", sx + ss / 2, sy + ss * 0.22, ss * 0.6, GOLD, "co")
		end
		local who = inSlot[i] and (heroTitle(inSlot[i].name) .. (inSlot[i].kind == "dead" and string.format(" (fallen, revive for %s metal)", fmtNum(inSlot[i].revive or 0)) or ""))
		addBox(sx, sy, sx + ss, sy + ss, nil, open and (i <= used and string.format("Slot %d: %s\nA dead hero keeps its slot until it is revived", i, who or "taken") or string.format("Slot %d: free - build a hero here", i))
			or string.format("Slot %d: needs %s", i, (H.SLOT_UPGRADES[i - 1] or {}).name or "an altar upgrade"))
	end
	local up = H.SLOT_UPGRADES[slots]
	local by1, by2 = y1 + u(0.07), y1 + u(0.2)
	if researching then
		local rup = H.SLOT_UPGRADES[rLevel] or {}
		local total = (rup.time or 45) * 30
		bar(x1 + u(0.08), by1, x2 - u(0.08), by2, 1 - (rFrame - f) / total, { 1, 0.72, 0.2, 1 })
		text(string.format("%s: researching, %d s left", rup.name or "Upgrade", math.ceil((rFrame - f) / 30)), (x1 + x2) / 2, by1 + (by2 - by1) * 0.25, (by2 - by1) * 0.5, WHITE, "co")
		addBox(x1 + u(0.08), by1, x2 - u(0.08), by2, nil, "The altar does not build while it researches.\nLosing the altar keeps finished upgrades.")
	elseif up then
		local m = Spring.GetTeamResources(team, "metal") or 0
		local e = Spring.GetTeamResources(team, "energy") or 0
		local ok = own and m >= up.metal and e >= up.energy
		K.button(string.format("%s:  %s M  %s E  (%d s)", up.name, fmtNum(up.metal), fmtNum(up.energy), up.time), x1 + u(0.08), by1, x2 - u(0.08), by2,
			ok and GOLD or { 0.7, 0.2, 0.15, 1 }, own, function()
				Spring.SendLuaRulesMsg("t4hero:altar:" .. altarID)
				sound("beep6.wav", 0.5)
			end,
			string.format("%s opens hero slot %d of %d.\nPaid at once: %s metal (%s in storage), %s energy (%s).\n%d s of research; the altar does not build meanwhile.\nEach upgrade costs twice the previous one. Losing the altar keeps the upgrades.",
				up.name, slots + 1, H.MAX_HEROES, fmtNum(up.metal), fmtNum(m), fmtNum(up.energy), fmtNum(e), up.time),
			{ textColor = ok and GOLD or RED, border = 2 })
	else
		text("All hero slots are open", (x1 + x2) / 2, by1 + (by2 - by1) * 0.25, (by2 - by1) * 0.5, GOLD, "co")
	end
	return y2
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
					if c and r > 0 and b.radius then
						gl.Color(c[1], c[2], c[3], 0.28)
						gl.DrawGroundCircle(x, y, z, H.val(b.radius, r), 64)
					end
					if b and (b.kind == "active_guard" or b.kind == "active_dome") and (spGetUnitRulesParam(uid, "hero_on_" .. key) or 0) > f and b.radius then
						local pulse = 0.55 + 0.25 * sin(f * 0.3)
						local dome = b.kind == "active_dome"
						gl.Color(dome and 0.5 or 1, dome and 0.8 or 0.85, dome and 1 or 0.3, pulse)
						gl.LineWidth(4)
						gl.DrawGroundCircle(x, y, z, H.val(b.radius, max(1, r)), 72)
						gl.LineWidth(2)
					end
				end
			end
		end
	end
	gl.LineWidth(1)
	gl.Color(1, 1, 1, 1)
end

local function drawWorldLabels()
	local f = spGetGameFrame()
	local size = floor(K.vsy * 0.016 * K.ui)
	local team = myTeam()
	for uid in pairs(tracked) do
		if spIsUnitInView(uid) then
			local lvl = spGetUnitRulesParam(uid, "hero_level")
			local x, y, z = spGetUnitPosition(uid)
			if lvl and x then
				local ud = UnitDefs[spGetUnitDefID(uid)]
				local scale = spGetUnitRulesParam(uid, "hero_scale") or 1
				local h = (ud and ud.height or 80) * scale + 20
				local sx, sy, sz = spWorldToScreenCoords(x, y + h, z)
				if sz < 1 then
					local allied = spIsUnitAllied(uid)
					text("Lv " .. lvl, sx, sy + size * 0.4, size, allied and GOLD or RED, "co")
					if allied then
						local xp = spGetUnitRulesParam(uid, "hero_xp") or 0
						bar(sx - size * 2, sy, sx + size * 2, sy + size * 0.3, xp, { 0.55, 0.35, 1, 0.9 })
						local pts = spGetUnitRulesParam(uid, "hero_points") or 0
						if pts > 0 and spGetUnitTeam(uid) == team then
							text("+" .. pts, sx + size * 2.6, sy - size * 0.1, size, { 1, 0.85, 0.2, (f % 30 < 20) and 1 or 0.5 }, "co")
						end
					end
				end
			end
		end
	end
	-- the research bar over the team's altars
	local rFrame = spGetTeamRulesParam(team, "hero_slots_research") or 0
	if rFrame > f then
		local rLevel = spGetTeamRulesParam(team, "hero_slots_research_level") or 0
		local up = H.SLOT_UPGRADES[rLevel] or {}
		for _, aid in ipairs(teamAltars) do
			if spIsUnitInView(aid) then
				local x, y, z = spGetUnitPosition(aid)
				local ud = UnitDefs[spGetUnitDefID(aid) or -1]
				local sx, sy, sz = spWorldToScreenCoords(x, y + (ud and ud.height or 100) + 40, z)
				if sz < 1 then
					bar(sx - size * 4, sy, sx + size * 4, sy + size * 0.5, 1 - (rFrame - f) / ((up.time or 45) * 30), { 1, 0.72, 0.2, 1 })
					text(string.format("%s  %d s", up.name or "Upgrade", math.ceil((rFrame - f) / 30)), sx, sy + size * 0.8, size * 0.9, GOLD, "co")
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
		r = c[1], g = c[2], b = c[3], t0 = Spring.GetTimer(), dur = dur or 2.5, size = floor(K.vsy * (size or 0.03) * K.ui) }
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
		if kind == "slots" and a == -1 then
			Spring.Echo(string.format("\255\255\210\064Altar upgrade done: %d hero slots open", b or 0))
		end
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
	elseif kind == "learn" and mine then
		float(uid, "Rank " .. tostring(a), { 1, 0.85, 0.35 }, 0.024, 1.6, "learn")
	elseif kind == "died" then
		float(uid, "FALLEN", RED, 0.04, 4, "state")
		if mine and name then
			Spring.Echo(string.format("\255\255\090\070%s has fallen at level %d - it keeps its hero slot. Revive it at the hero altar (it comes back at level %d).", heroTitle(name), a, b))
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
	elseif kind == "bought" then
		float(uid, "LEVEL " .. a .. " BOUGHT", GOLD, 0.03, 2.5, "level")
	elseif kind == "nometal" and mine then
		float(uid, "Not enough metal: " .. fmtNum(a), RED, 0.026, 2.5, "warn")
		sound("cantdothat.wav", 0.6)
	elseif kind == "noenergy" and mine then
		float(uid, "Not enough energy: " .. fmtNum(a), RED, 0.026, 2.5, "warn")
		sound("cantdothat.wav", 0.6)
	elseif kind == "research" then
		local up = H.SLOT_UPGRADES[a] or {}
		float(uid, (up.name or "Altar upgrade") .. " started", GOLD, 0.03, 3, "state")
	elseif kind == "slots" then
		float(uid, string.format("%d HERO SLOTS", b or 0), GOLD, 0.04, 4, "state")
		if mine then
			sound("beep6.wav", 0.7)
		end
	elseif kind == "slotsfull" and mine then
		float(uid, "All hero slots in use", RED, 0.026, 2.5, "warn")
		sound("cantdothat.wav", 0.6)
	elseif kind == "cast" and name then
		local key = H.abilityKeys[b]
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
		refreshCards()
		pickSelected()
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
	if uid == selectedAltar then
		selectedAltar = nil
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
	rects = {}
	itemsArea, consoleTop = nil, nil
	K.font:Begin()
	drawHeroBar()
	if selectedHero and spValidUnitID(selectedHero) then
		consoleTop = drawConsole(selectedHero)
		if showLearn and consoleTop then
			drawLearn(selectedHero, consoleTop)
		end
	elseif selectedAltar and spValidUnitID(selectedAltar) then
		consoleTop = drawAltar(selectedAltar)
	end
	K.font:End()
	gl.Color(1, 1, 1, 1)
	local mx, my = Spring.GetMouseState()
	tip = K.tipAt(mx, my)
end

-- world labels under every UI panel (DrawScreenEffects runs before DrawScreen)
function widget:DrawScreenEffects()
	if Spring.IsGUIHidden() or not K.getFont() then
		return
	end
	K.font:Begin()
	drawWorldLabels()
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
		return false
	end
	if button == 1 and bx[5] then
		bx[5]()
	elseif button == 3 and bx[7] then
		bx[7]()
	end
	return true
end

local HOTKEY = { q = "a1", w = "a2", e = "a3", r = "ult" }

function widget:KeyPress(key, mods, isRepeat)
	if key == 27 and showLearn then -- escape
		showLearn = false
		return true
	end
	if not selectedHero or mods.alt or isRepeat then
		return false
	end
	-- only when the selection is heroes alone, so the usual Q/W/E/R binds keep working for armies
	for _, uid in ipairs(Spring.GetSelectedUnits()) do
		if not heroDefIDs[spGetUnitDefID(uid) or -1] then
			return false
		end
	end
	local sym = Spring.GetKeySymbol and Spring.GetKeySymbol(key)
	sym = type(sym) == "string" and sym:lower() or (key < 256 and string.char(key):lower() or "")
	if sym == "u" and not mods.ctrl then
		setLearn(not showLearn)
		return true
	end
	local ab = HOTKEY[sym]
	if ab and spGetUnitTeam(selectedHero) == myTeam() then
		local name = heroDefIDs[spGetUnitDefID(selectedHero)]
		local b = H.heroes[name][ab]
		if not b then
			return false
		end
		if mods.ctrl then
			-- Ctrl + hotkey: learn a rank (Dota)
			learn(selectedHero, ab)
			return true
		end
		if b.cmd and not b.passive then
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
	K.resize()
	WG.T4HeroesUI = {
		-- the learn window (scenes call setUpgrades, the v18 name)
		setUpgrades = setLearn,
		setLearn = setLearn,
		closeWindows = function() showLearn = false end,
		-- the console rectangle the items widget fills this frame: { x1, y1, x2, y2, uid, own, H0 } or nil
		itemsArea = function() return itemsArea end,
		-- the top of the console / altar panel this frame (windows open above it), nil when none
		consoleTop = function() return consoleTop end,
		consoleGeometry = consoleGeometry,
		selectedHero = function() return selectedHero end,
		learnOpen = function() return showLearn end,
		rect = function(name) return rects[name] end,
		heroTitle = heroTitle,
	}
	refreshTracked()
	refreshCards()
	pickSelected()
end

function widget:Shutdown()
	K.clearLists()
	WG.T4HeroesUI = nil
	widgetHandler:DeregisterGlobal("T4HeroEvent")
end
