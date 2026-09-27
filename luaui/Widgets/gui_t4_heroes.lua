--------------------------------------------------------------------------------
--
--  file:    gui_t4_heroes.lua
--  brief:   UI of the custom T4 heroes (denysfast/bar-game): the team's hero roster (level, health,
--           experience, unspent points, fallen heroes with their revive level and price), the talent
--           panel of the selected hero (learn a rank, cast an ability, cooldowns), levels above the
--           heroes in the world, aura rings and floating texts. The rules live in
--           luarules/gadgets/unit_t4_heroes.lua, the design data in luarules/configs/t4_heroes.lua.
--  Licensed under the terms of the GNU GPL, v2 or later.
--
--------------------------------------------------------------------------------

local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name = "T4 Heroes",
		desc = "Hero roster, talent panel, hero levels and auras of the custom T4 heroes",
		author = "denysfast",
		date = "2026-09-27",
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
local floor, max, min = math.floor, math.max, math.min

local heroDefIDs = {} -- unitDefID -> hero name
local heroDefList = {}
for udid, ud in pairs(UnitDefs) do
	if H.heroes[ud.name] and ud.customParams.t4_hero then
		heroDefIDs[udid] = ud.name
		heroDefList[#heroDefList + 1] = udid
	end
end

local vsx, vsy = Spring.GetViewGeometry()
local font, fontSize
local uiScale = 1

local tracked = {}  -- unitID -> hero name, every hero this client can see
local floating = {} -- { x, y, z, text, r, g, b, t0, dur, size }
local roster = {}   -- rows of the team's heroes
local selectedHero  -- unitID with the talent panel
local boxes = {}    -- clickable regions of the last frame: { x1, y1, x2, y2, fn, tip }
local hoverTip

-- colors
local GOLD = { 1, 0.82, 0.25, 1 }
local WHITE = { 1, 1, 1, 1 }
local GREY = { 0.62, 0.62, 0.62, 1 }
local RED = { 1, 0.35, 0.3, 1 }
local GREEN = { 0.45, 1, 0.45, 1 }
local BLUE = { 0.5, 0.75, 1, 1 }

local function getFont()
	if WG.fonts and WG.fonts.getFont then
		font, fontSize = WG.fonts.getFont(2, 1.2)
	else
		font, fontSize = gl.LoadFont("fonts/Exo2-SemiBold.otf", 24, 4, 1.5), 24
	end
	return font
end

function widget:ViewResize()
	vsx, vsy = Spring.GetViewGeometry()
	uiScale = Spring.GetConfigFloat("ui_scale", 1)
	font = nil
end

local function heroName(name)
	local cfg = H.heroes[name]
	return cfg and cfg.title or name
end

local function shortName(name)
	local ud = UnitDefNames[name]
	return ud and ud.translatedHumanName or ud and ud.humanName or name
end

---------------------------------------------------------------------------- tracking

local function refreshTracked()
	for uid in pairs(tracked) do
		if not spValidUnitID(uid) then
			tracked[uid] = nil
		end
	end
	for _, teamID in ipairs(Spring.GetTeamList()) do
		local units = Spring.GetTeamUnitsByDefs(teamID, heroDefList)
		for _, uid in ipairs(units or {}) do
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
	local units = Spring.GetTeamUnitsByDefs(team, heroDefList) or {}
	for _, uid in ipairs(units) do
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
	selectedHero = nil
	local best
	for _, uid in ipairs(Spring.GetSelectedUnits()) do
		if tracked[uid] or heroDefIDs[spGetUnitDefID(uid) or -1] then
			local _, _, _, _, bp = spGetUnitHealth(uid)
			if bp and bp >= 1 then
				local pts = spGetUnitRulesParam(uid, "hero_points") or 0
				if not best or pts > best then
					best, selectedHero = pts, uid
				end
			end
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

local function focusUnit(uid)
	Spring.SelectUnitArray({ uid })
	local x, y, z = spGetUnitPosition(uid)
	if x then
		Spring.SetCameraTarget(x, y, z, 0.3)
	end
end

---------------------------------------------------------------------------- drawing helpers

local function rect(x1, y1, x2, y2, c)
	gl.Color(c[1], c[2], c[3], c[4] or 1)
	gl.Rect(x1, y1, x2, y2)
end

local function panelBg(x1, y1, x2, y2)
	if WG.FlowUI and WG.FlowUI.Draw and WG.FlowUI.Draw.Element then
		WG.FlowUI.Draw.Element(x1, y1, x2, y2, 1, 1, 1, 1)
	else
		rect(x1, y1, x2, y2, { 0, 0, 0, 0.6 })
	end
end

local function bar(x1, y1, x2, y2, frac, c)
	rect(x1, y1, x2, y2, { 0, 0, 0, 0.55 })
	if frac > 0 then
		rect(x1 + 1, y1 + 1, x1 + 1 + (x2 - x1 - 2) * min(1, frac), y2 - 1, c)
	end
end

local function text(str, x, y, size, c, opts)
	font:SetTextColor(c[1], c[2], c[3], c[4] or 1)
	font:Print(str, x, y, size, opts or "o")
end

local function addBox(x1, y1, x2, y2, fn, tip)
	boxes[#boxes + 1] = { x1, y1, x2, y2, fn, tip }
end

local function button(x1, y1, x2, y2, label, enabled, c, fn, tip)
	local mx, my = Spring.GetMouseState()
	local hover = mx >= x1 and mx <= x2 and my >= y1 and my <= y2
	local bg = enabled and (hover and { c[1] * 0.55, c[2] * 0.55, c[3] * 0.55, 0.95 } or { c[1] * 0.35, c[2] * 0.35, c[3] * 0.35, 0.9 })
		or { 0.12, 0.12, 0.12, 0.8 }
	rect(x1, y1, x2, y2, bg)
	text(label, (x1 + x2) / 2, (y1 + y2) / 2 - (y2 - y1) * 0.28, (y2 - y1) * 0.62, enabled and c or GREY, "co")
	if enabled and fn then
		addBox(x1, y1, x2, y2, fn, tip)
	elseif tip then
		addBox(x1, y1, x2, y2, nil, tip)
	end
end

---------------------------------------------------------------------------- roster

local function drawRoster(x2, yTop)
	if #roster == 0 then
		return yTop
	end
	local rowH = floor(vsy * 0.03 * uiScale)
	local w = floor(vsy * 0.26 * uiScale)
	local x1 = x2 - w
	local pad = floor(rowH * 0.18)
	local y2 = yTop
	local y1 = y2 - rowH * (#roster + 1) - pad * 2
	panelBg(x1, y1, x2, y2)
	text("HEROES", x1 + pad * 2, y2 - pad - rowH * 0.7, rowH * 0.55, GOLD)
	local frame = spGetGameFrame()
	for i, r in ipairs(roster) do
		local ry2 = y2 - pad - rowH * i
		local ry1 = ry2 - rowH + 2
		local nameX = x1 + pad * 2
		if r.uid and not r.building then
			local lvl = spGetUnitRulesParam(r.uid, "hero_level") or 1
			local xp = spGetUnitRulesParam(r.uid, "hero_xp") or 0
			local pts = spGetUnitRulesParam(r.uid, "hero_points") or 0
			local hp, maxHp = spGetUnitHealth(r.uid)
			local retreat = (spGetUnitRulesParam(r.uid, "hero_retreat") or 0) > 0
			if r.uid == selectedHero then
				rect(x1 + pad, ry1, x2 - pad, ry2, { 1, 0.8, 0.2, 0.12 })
			end
			text(string.format("%d", lvl), nameX + rowH * 0.45, ry1 + rowH * 0.25, rowH * 0.6, GOLD, "co")
			text(shortName(r.name), nameX + rowH * 1.1, ry1 + rowH * 0.38, rowH * 0.5, retreat and BLUE or WHITE)
			local bx1 = x1 + w * 0.52
			local bx2 = x2 - pad * 2 - (pts > 0 and rowH or 0)
			bar(bx1, ry1 + rowH * 0.5, bx2, ry1 + rowH * 0.85, hp and maxHp and hp / maxHp or 0, { 0.3, 0.9, 0.3, 0.95 })
			bar(bx1, ry1 + rowH * 0.15, bx2, ry1 + rowH * 0.4, xp, { 0.95, 0.75, 0.2, 0.95 })
			if pts > 0 then
				local blink = (frame % 30 < 20) and 1 or 0.6
				text("+" .. pts, x2 - pad * 2 - rowH * 0.5, ry1 + rowH * 0.25, rowH * 0.6, { 1, 0.85, 0.2, blink }, "co")
			end
			addBox(x1, ry1, x2, ry2, function() focusUnit(r.uid) end,
				string.format("%s - level %d%s. Click to select.", heroName(r.name), lvl, pts > 0 and (", " .. pts .. " talent points to spend") or ""))
		elseif r.uid and r.building then
			text("..", nameX + rowH * 0.45, ry1 + rowH * 0.25, rowH * 0.6, GREY, "co")
			text(shortName(r.name), nameX + rowH * 1.1, ry1 + rowH * 0.38, rowH * 0.5, GREY)
			bar(x1 + w * 0.52, ry1 + rowH * 0.3, x2 - pad * 2, ry1 + rowH * 0.7, r.progress or 0, { 0.5, 0.75, 1, 0.9 })
			addBox(x1, ry1, x2, ry2, nil, r.deadLevel > 0 and string.format("Reviving %s at level %d", heroName(r.name), r.deadLevel)
				or string.format("Building %s", heroName(r.name)))
		else
			text(string.format("%d", r.deadLevel), nameX + rowH * 0.45, ry1 + rowH * 0.25, rowH * 0.6, RED, "co")
			text(shortName(r.name), nameX + rowH * 1.1, ry1 + rowH * 0.38, rowH * 0.5, RED)
			text(string.format("fallen  %dk", floor(r.revive / 1000 + 0.5)), x2 - pad * 2, ry1 + rowH * 0.38, rowH * 0.45, GREY, "ro")
			addBox(x1, ry1, x2, ry2, nil, string.format("%s has fallen. Rebuild it at the hero altar to revive it at level %d for %d metal.",
				heroName(r.name), r.deadLevel, r.revive))
		end
	end
	return y1
end

---------------------------------------------------------------------------- talent panel

local function rankPips(rank, maxRank)
	local s = ""
	for i = 1, maxRank do
		s = s .. (i <= rank and "\255\255\210\064|" or "\255\090\090\090|")
	end
	return s
end

local function branchText(name, key, rank)
	local b = H.branch(name, key)
	if H.common[key] then
		return b.desc
	end
	local cur = rank > 0 and b.text[rank] or nil
	local nxt = b.text[rank + 1]
	if cur and nxt then
		return cur .. "  >  " .. nxt
	end
	return cur or ("next: " .. (nxt or ""))
end

local function drawPanel(x2, yTop, uid)
	local name = heroDefIDs[spGetUnitDefID(uid) or -1]
	if not name then
		return
	end
	local cfg = H.heroes[name]
	local own = spGetUnitTeam(uid) == myTeam()
	local lvl = spGetUnitRulesParam(uid, "hero_level") or 1
	local xp = spGetUnitRulesParam(uid, "hero_xp") or 0
	local pts = spGetUnitRulesParam(uid, "hero_points") or 0
	local hpMult = spGetUnitRulesParam(uid, "hero_hpmult") or 1
	local autocast = (spGetUnitRulesParam(uid, "hero_autocast") or 1) == 1
	local frame = spGetGameFrame()

	local rowH = floor(vsy * 0.042 * uiScale)
	local w = floor(vsy * 0.42 * uiScale)
	local pad = floor(rowH * 0.15)
	local headH = floor(rowH * 1.35)
	local x1 = x2 - w
	local y2 = yTop
	local y1 = y2 - headH - rowH * #H.branchOrder - pad * 3
	panelBg(x1, y1, x2, y2)

	-- header: title, level, experience, points, autocast
	local hy = y2 - pad - headH
	text(cfg.title, x1 + pad * 2, hy + headH * 0.58, headH * 0.36, GOLD)
	text(string.format("Level %d   %s", lvl, cfg.role), x1 + pad * 2, hy + headH * 0.28, headH * 0.26, WHITE)
	local hp, maxHp = spGetUnitHealth(uid)
	if hp then
		text(string.format("HP %dk / %dk", floor(hp * hpMult / 1000), floor(maxHp * hpMult / 1000)), x2 - pad * 2, hy + headH * 0.62, headH * 0.24, GREEN, "ro")
	end
	bar(x1 + pad * 2, hy + headH * 0.06, x2 - pad * 2, hy + headH * 0.2, lvl >= H.MAX_LEVEL and 1 or xp, { 0.95, 0.75, 0.2, 0.95 })
	if own then
		if pts > 0 then
			text(string.format("%d point%s", pts, pts > 1 and "s" or ""), x2 - pad * 2, hy + headH * 0.32, headH * 0.26, GOLD, "ro")
		end
		local ax2 = x2 - pad * 2 - headH * 2.2
		button(ax2 - headH * 2.4, hy + headH * 0.24, ax2, hy + headH * 0.56, autocast and "autocast" or "manual", true,
			autocast and GREEN or GREY, function() toggleAutocast(uid) end,
			"Autocast: the hero casts its abilities by itself when they would help")
	end

	-- one row per branch
	for i, key in ipairs(H.branchOrder) do
		local b = H.branch(name, key)
		local ry2 = hy - pad - rowH * (i - 1)
		local ry1 = ry2 - rowH + 2
		addBox(x1, ry1, x2, ry2, nil, b.name .. ": " .. (b.desc or "")) -- first: the buttons drawn later win the click
		local rank = spGetUnitRulesParam(uid, "hero_rank_" .. key) or 0
		local maxRank = H.maxRank(name, key)
		local req = H.reqLevel(name, key, rank + 1)
		local canLearn = own and pts > 0 and rank < maxRank and lvl >= req
		local isUlt = key == "ult"
		local titleC = isUlt and { 1, 0.55, 0.25, 1 } or (H.common[key] and WHITE or BLUE)
		if isUlt then
			rect(x1 + pad, ry1, x2 - pad, ry2, { 1, 0.4, 0.1, 0.08 })
		end
		text(b.name, x1 + pad * 2, ry1 + rowH * 0.56, rowH * 0.34, titleC)
		text(rankPips(rank, maxRank), x1 + pad * 2 + w * 0.36, ry1 + rowH * 0.56, rowH * 0.34, WHITE)
		local sub = branchText(name, key, rank)
		if rank < maxRank and lvl < req then
			sub = sub .. string.format("   (level %d)", req)
		end
		text(sub, x1 + pad * 2, ry1 + rowH * 0.16, rowH * 0.25, GREY)

		local bx2 = x2 - pad * 2
		local bs = rowH * 0.62
		if own then
			button(bx2 - bs, ry1 + (rowH - bs) / 2, bx2, ry1 + (rowH + bs) / 2, "+", canLearn, GOLD,
				function() learn(uid, key) end, b.name .. ": " .. (b.desc or ""))
		end
		-- active abilities: cooldown / cast
		if b.cmd and rank > 0 then
			local ready = spGetUnitRulesParam(uid, "hero_ready_" .. key) or 0
			local on = spGetUnitRulesParam(uid, "hero_on_" .. key) or 0
			local cx2 = bx2 - bs - pad * 2
			local cx1 = cx2 - rowH * 1.9
			if on > frame then
				button(cx1, ry1 + (rowH - bs) / 2, cx2, ry1 + (rowH + bs) / 2, string.format("%ds", floor((on - frame) / 30) + 1), false, GREEN, nil, "Active")
			elseif ready > frame then
				button(cx1, ry1 + (rowH - bs) / 2, cx2, ry1 + (rowH + bs) / 2, string.format("%ds", floor((ready - frame) / 30) + 1), false, GREY, nil, "Cooldown")
			elseif own then
				button(cx1, ry1 + (rowH - bs) / 2, cx2, ry1 + (rowH + bs) / 2, b.target and "aim" or "cast", true, isUlt and { 1, 0.55, 0.25, 1 } or BLUE,
					function() castAbility(uid, key) end, b.name .. ": " .. b.desc)
			end
		elseif b.kind == "undying" and rank > 0 then
			local ready = spGetUnitRulesParam(uid, "hero_ready_ult") or 0
			local cx2 = bx2 - bs - pad * 2
			button(cx2 - rowH * 1.9, ry1 + (rowH - bs) / 2, cx2, ry1 + (rowH + bs) / 2,
				ready > frame and string.format("%ds", floor((ready - frame) / 30) + 1) or "ready", false, ready > frame and GREY or GREEN, nil, "Undying")
		end
	end
end

---------------------------------------------------------------------------- world overlay

local AURA_COLORS = {
	aura_heal = { 0.3, 1, 0.4 }, aura_damage = { 1, 0.5, 0.2 }, aura_burn = { 1, 0.35, 0.05 }, aura_emp = { 0.4, 0.7, 1 },
}

function widget:DrawWorldPreUnit()
	local frame = spGetGameFrame()
	gl.DepthTest(false)
	gl.LineWidth(2)
	for uid, name in pairs(tracked) do
		if spIsUnitInView(uid) then
			local cfg = H.heroes[name]
			local x, y, z = spGetUnitPosition(uid)
			if x and cfg then
				for _, key in ipairs({ "a1", "a2" }) do
					local b = cfg[key]
					local c = b and AURA_COLORS[b.kind]
					local r = spGetUnitRulesParam(uid, "hero_rank_" .. key) or 0
					if c and r > 0 then
						local radius = type(b.radius) == "table" and b.radius[r] or b.radius
						gl.Color(c[1], c[2], c[3], 0.28)
						gl.DrawGroundCircle(x, y, z, radius, 64)
					end
				end
				for _, key in ipairs({ "a2", "ult" }) do
					local b = cfg[key]
					if b and (b.kind == "active_guard" or b.kind == "active_dome") and (spGetUnitRulesParam(uid, "hero_on_" .. key) or 0) > frame then
						local pulse = 0.55 + 0.25 * math.sin(frame * 0.3)
						gl.Color(b.kind == "active_dome" and 0.5 or 1, b.kind == "active_dome" and 0.8 or 0.85, b.kind == "active_dome" and 1 or 0.3, pulse)
						gl.LineWidth(4)
						gl.DrawGroundCircle(x, y, z, b.radius, 72)
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
	local frame = spGetGameFrame()
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
						bar(sx - size * 2, sy, sx + size * 2, sy + size * 0.3, xp, { 0.95, 0.75, 0.2, 0.9 })
						local pts = spGetUnitRulesParam(uid, "hero_points") or 0
						if pts > 0 and spGetUnitTeam(uid) == myTeam() then
							text("+" .. pts, sx + size * 2.6, sy - size * 0.1, size, { 1, 0.85, 0.2, (frame % 30 < 20) and 1 or 0.5 }, "co")
						end
					end
				end
			end
		end
	end
	-- floating texts
	local now = Spring.GetTimer()
	local keep = {}
	for _, f in ipairs(floating) do
		local age = Spring.DiffTimers(now, f.t0)
		if age < f.dur then
			keep[#keep + 1] = f
			local sx, sy, sz = spWorldToScreenCoords(f.x, f.y + age * 60, f.z)
			if sz < 1 then
				local a = min(1, (f.dur - age) / 0.6)
				text(f.text, sx, sy, f.size, { f.r, f.g, f.b, a }, "co")
			end
		end
	end
	floating = keep
end

---------------------------------------------------------------------------- events from the gadget

-- one floating text per hero and kind: several levels gained at once show only the last one
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
			Spring.Echo(string.format("\255\255\090\070%s has fallen at level %d - rebuild it at the hero altar to revive it at level %d.", heroName(name), a, b))
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
	elseif kind == "cast" and name then
		local key = H.branchOrder[b]
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
	font:Begin()
	drawWorldLabels()
	local top = vsy - floor(vsy * 0.075)
	local x2 = vsx - floor(vsy * 0.008)
	local yAfter = drawRoster(x2, top)
	if selectedHero and spValidUnitID(selectedHero) then
		drawPanel(x2, yAfter - floor(vsy * 0.006), selectedHero)
	end
	font:End()
	gl.Color(1, 1, 1, 1)
	local mx, my = Spring.GetMouseState()
	hoverTip = nil
	for i = #boxes, 1, -1 do
		local bx = boxes[i]
		if mx >= bx[1] and mx <= bx[3] and my >= bx[2] and my <= bx[4] then
			hoverTip = bx[6]
			break
		end
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

function widget:GetTooltip(x, y)
	return hoverTip
end

function widget:MousePress(x, y, button)
	if button ~= 1 then
		return false
	end
	for i = #boxes, 1, -1 do
		local bx = boxes[i]
		if x >= bx[1] and x <= bx[3] and y >= bx[2] and y <= bx[4] then
			if bx[5] then
				bx[5]()
			end
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
	refreshTracked()
	refreshRoster()
	pickSelected()
end

function widget:Shutdown()
	widgetHandler:DeregisterGlobal("T4HeroEvent")
end
