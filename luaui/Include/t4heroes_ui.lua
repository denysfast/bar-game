--------------------------------------------------------------------------------
-- Shared drawing kit of the custom T4 hero widgets (denysfast/bar-game): gui_t4_heroes.lua (portraits, hero
-- console, learn window, altar) and gui_t4_items.lua (item slots, stash, shop, ground items, toasts).
--   local K = VFS.Include("luaui/Include/t4heroes_ui.lua")   -- a fresh kit per widget (own font, own boxes)
-- Warcraft-like look: dark stone panels with a bronze double border, gold titles. Text goes through the BAR
-- font handler (WG.fonts; gl.Text draws nothing under the BAR UI). Panel backgrounds are cached display lists.
--------------------------------------------------------------------------------

local K = {}

local floor, max, min, sin, cos, pi = math.floor, math.max, math.min, math.sin, math.cos, math.pi
local glColor, glRect, glTexture, glTexRect, glBeginEnd, glVertex = gl.Color, gl.Rect, gl.Texture, gl.TexRect, gl.BeginEnd, gl.Vertex

K.ART = "bitmaps/t4heroes/"
K.GOLD = { 1, 0.82, 0.25, 1 }
K.WHITE = { 1, 1, 1, 1 }
K.GREY = { 0.62, 0.62, 0.62, 1 }
K.DARK = { 0.35, 0.35, 0.35, 1 }
K.RED = { 1, 0.35, 0.3, 1 }
K.GREEN = { 0.45, 1, 0.45, 1 }
K.BLUE = { 0.5, 0.75, 1, 1 }
K.ORANGE = { 1, 0.6, 0.25, 1 }
K.BRONZE = { 0.45, 0.34, 0.16, 1 }
K.HOVER = { 1, 0.9, 0.5, 1 }

K.vsx, K.vsy = Spring.GetViewGeometry()
K.ui = 1
K.font = nil

function K.resize()
	K.vsx, K.vsy = Spring.GetViewGeometry()
	K.ui = Spring.GetConfigFloat("ui_scale", 1) or 1
	K.font = nil
	K.clearLists()
end

function K.getFont()
	if not K.font then
		if WG.fonts and WG.fonts.getFont then
			K.font = WG.fonts.getFont(2, 1.2)
		else
			K.font = gl.LoadFont("fonts/Exo2-SemiBold.otf", 24, 4, 1.5)
		end
	end
	return K.font
end

---------------------------------------------------------------------------- numbers, colors

function K.fmtNum(v)
	v = v or 0
	local a = math.abs(v)
	local s
	if a >= 1e6 then
		s = string.format("%.1fM", a / 1e6)
	elseif a >= 1e4 then
		s = string.format("%dk", floor(a / 1000 + 0.5))
	elseif a >= 1000 then
		s = string.format("%.1fk", a / 1000)
	elseif a >= 10 or a == floor(a) then
		s = tostring(floor(a + 0.5))
	else
		s = string.format("%.1f", a)
	end
	return (v < 0 and "-" or "") .. s
end

function K.code(c)
	return "\255" .. string.char(max(1, min(255, floor(c[1] * 255)))) .. string.char(max(1, min(255, floor(c[2] * 255))))
		.. string.char(max(1, min(255, floor(c[3] * 255))))
end

function K.time(sec)
	sec = max(0, floor(sec + 0.5))
	return string.format("%d:%02d", floor(sec / 60), sec % 60)
end

---------------------------------------------------------------------------- primitives

function K.rect(x1, y1, x2, y2, c, a)
	glColor(c[1], c[2], c[3], a or c[4] or 1)
	glRect(x1, y1, x2, y2)
end

function K.frame(x1, y1, x2, y2, c, w)
	w = w or 2
	glColor(c[1], c[2], c[3], c[4] or 1)
	glRect(x1, y1, x2, y1 + w)
	glRect(x1, y2 - w, x2, y2)
	glRect(x1, y1, x1 + w, y2)
	glRect(x2 - w, y1, x2, y2)
end

function K.tex(path, x1, y1, x2, y2, r, g, b, a)
	glColor(r or 1, g or 1, b or 1, a or 1)
	glTexture(path)
	glTexRect(x1, y1, x2, y2)
	glTexture(false)
end

-- vertical gradient quad: c1 at the top, c2 at the bottom
function K.grad(x1, y1, x2, y2, c1, c2)
	glBeginEnd(GL.QUADS, function()
		glColor(c1[1], c1[2], c1[3], c1[4] or 1)
		glVertex(x1, y2)
		glVertex(x2, y2)
		glColor(c2[1], c2[2], c2[3], c2[4] or 1)
		glVertex(x2, y1)
		glVertex(x1, y1)
	end)
end

-- panel backgrounds as display lists (geometry -> list), rebuilt on resize
local lists, listCount = {}, 0
function K.clearLists()
	for _, l in pairs(lists) do
		gl.DeleteList(l)
	end
	lists, listCount = {}, 0
end

local function panelRaw(x1, y1, x2, y2, style)
	if style == "dark" then
		glColor(0.03, 0.03, 0.045, 0.95)
		glRect(x1, y1, x2, y2)
		K.frame(x1, y1, x2, y2, { 0.32, 0.26, 0.14, 1 }, 1)
		return
	end
	glColor(0.05, 0.05, 0.07, 0.93)
	glRect(x1, y1, x2, y2)
	K.grad(x1, (y1 + y2) / 2, x2, y2, { 0.17, 0.14, 0.11, 0.6 }, { 0.02, 0.02, 0.03, 0 })
	K.frame(x1, y1, x2, y2, K.BRONZE, 3)
	K.frame(x1 + 4, y1 + 4, x2 - 4, y2 - 4, { 0.22, 0.17, 0.09, 1 }, 1)
	-- corner studs
	local s = 5
	for _, p in ipairs({ { x1, y1 }, { x2 - s * 2, y1 }, { x1, y2 - s * 2 }, { x2 - s * 2, y2 - s * 2 } }) do
		glColor(0.7, 0.55, 0.25, 1)
		glRect(p[1] + 1, p[2] + 1, p[1] + s * 2 - 1, p[2] + s * 2 - 1)
		glColor(0.25, 0.18, 0.08, 1)
		glRect(p[1] + 3, p[2] + 3, p[1] + s * 2 - 3, p[2] + s * 2 - 3)
	end
end

function K.panel(x1, y1, x2, y2, style)
	x1, y1, x2, y2 = floor(x1), floor(y1), floor(x2), floor(y2)
	local key = x1 .. ":" .. y1 .. ":" .. x2 .. ":" .. y2 .. ":" .. (style or "")
	local l = lists[key]
	if not l then
		if listCount > 64 then
			K.clearLists()
		end
		l = gl.CreateList(panelRaw, x1, y1, x2, y2, style)
		lists[key] = l
		listCount = listCount + 1
	end
	gl.CallList(l)
end

function K.bar(x1, y1, x2, y2, frac, c, bg)
	K.rect(x1, y1, x2, y2, bg or { 0, 0, 0, 0.75 })
	frac = max(0, min(1, frac or 0))
	if frac > 0 then
		local xe = x1 + 1 + (x2 - x1 - 2) * frac
		K.rect(x1 + 1, y1 + 1, xe, y2 - 1, c)
		K.grad(x1 + 1, (y1 + y2) / 2, xe, y2 - 1, { 1, 1, 1, 0.28 }, { 1, 1, 1, 0 })
	end
end

-- the dark clock sweep of a cooldown over an icon, frac = share still to wait
function K.sweep(x1, y1, x2, y2, frac)
	if frac <= 0 then
		return
	end
	local cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
	local r = (x2 - x1) * 0.75
	gl.Scissor(x1, y1, x2 - x1, y2 - y1)
	glColor(0, 0, 0, 0.66)
	glBeginEnd(GL.TRIANGLE_FAN, function()
		glVertex(cx, cy)
		local steps = 36
		for i = 0, steps do
			local a = pi / 2 + (i / steps) * min(1, frac) * 2 * pi
			glVertex(cx + cos(a) * r, cy + sin(a) * r)
		end
	end)
	gl.Scissor(false)
	-- the bright edge of the sweep
	local a = pi / 2 + min(1, frac) * 2 * pi
	glColor(1, 0.85, 0.4, 0.5)
	glBeginEnd(GL.LINES, function()
		glVertex(cx, cy)
		glVertex(cx + cos(a) * (x2 - x1) * 0.5, cy + sin(a) * (y2 - y1) * 0.5)
	end)
end

function K.text(str, x, y, size, c, opts)
	local font = K.font
	font:SetTextColor(c[1], c[2], c[3], c[4] or 1)
	font:Print(str, x, y, size, opts or "o")
end

function K.width(str, size)
	return K.font:GetTextWidth(str) * size
end

-- text shortened with ".." to fit maxW
function K.fit(str, size, maxW)
	if K.width(str, size) <= maxW then
		return str
	end
	local s = str
	while #s > 1 and K.width(s .. "..", size) > maxW do
		s = s:sub(1, -2)
	end
	return s .. ".."
end

-- split a long text into lines of at most n characters (by words)
function K.wrap(str, n)
	local out, line = {}, ""
	for word in tostring(str or ""):gmatch("%S+") do
		if line ~= "" and #line + 1 + #word > n then
			out[#out + 1] = line
			line = word
		else
			line = line == "" and word or (line .. " " .. word)
		end
	end
	if line ~= "" then
		out[#out + 1] = line
	end
	return out
end

function K.hovered(x1, y1, x2, y2)
	local mx, my = Spring.GetMouseState()
	return mx >= x1 and mx <= x2 and my >= y1 and my <= y2
end

-- a small padlock (locked hero slot)
function K.lock(cx, cy, s, c)
	c = c or { 0.75, 0.65, 0.45, 1 }
	glColor(c[1], c[2], c[3], c[4] or 1)
	glRect(cx - s * 0.5, cy - s * 0.55, cx + s * 0.5, cy + s * 0.1)
	local t = max(2, s * 0.14)
	glRect(cx - s * 0.36, cy + s * 0.1, cx - s * 0.36 + t, cy + s * 0.45)
	glRect(cx + s * 0.36 - t, cy + s * 0.1, cx + s * 0.36, cy + s * 0.45)
	glRect(cx - s * 0.36, cy + s * 0.45 - t, cx + s * 0.36, cy + s * 0.45)
	glColor(0.1, 0.08, 0.05, 1)
	glRect(cx - s * 0.07, cy - s * 0.38, cx + s * 0.07, cy - s * 0.1)
end

---------------------------------------------------------------------------- clickable boxes and buttons

-- boxes of the last frame: { x1, y1, x2, y2, fn, tip, fnRight, drag }; the topmost (last added) wins
K.boxes = {}
function K.beginFrame()
	K.boxes = {}
end

function K.addBox(x1, y1, x2, y2, fn, tip, fnRight, data)
	local b = { x1, y1, x2, y2, fn, tip, fnRight, data }
	K.boxes[#K.boxes + 1] = b
	return b
end

function K.boxAt(x, y)
	for i = #K.boxes, 1, -1 do
		local b = K.boxes[i]
		if x >= b[1] and x <= b[3] and y >= b[2] and y <= b[4] then
			return b
		end
	end
end

function K.tipAt(x, y)
	for i = #K.boxes, 1, -1 do
		local b = K.boxes[i]
		if x >= b[1] and x <= b[3] and y >= b[2] and y <= b[4] then
			if b[6] then
				return type(b[6]) == "function" and b[6]() or b[6]
			end
			if b[5] or b[7] then
				return nil
			end
		end
	end
end

-- an icon button: art, a frame that lights up under the mouse; disabled -> greyed
function K.iconButton(path, x1, y1, x2, y2, enabled, border, fn, tip, fnRight)
	local hov = K.hovered(x1, y1, x2, y2)
	K.rect(x1 - 2, y1 - 2, x2 + 2, y2 + 2, { 0, 0, 0, 0.9 })
	if path then
		local k = enabled and (hov and 1.15 or 1) or 0.38
		K.tex(path, x1, y1, x2, y2, k, k, k, 1)
	end
	K.frame(x1 - 2, y1 - 2, x2 + 2, y2 + 2, hov and (fn or fnRight) and K.HOVER or (border or K.BRONZE), 2)
	K.addBox(x1, y1, x2, y2, fn, tip, fnRight)
	return hov
end

-- a text button; c = accent color; enabled false = grey, no click
function K.button(label, x1, y1, x2, y2, c, enabled, fn, tip, opts)
	opts = opts or {}
	local hov = enabled and K.hovered(x1, y1, x2, y2)
	local glow = opts.glow or 0
	if enabled then
		K.rect(x1, y1, x2, y2, { c[1] * 0.18 + 0.2 * glow, c[2] * 0.18 + 0.15 * glow, c[3] * 0.18, 0.95 })
		K.grad(x1, (y1 + y2) / 2, x2, y2, { 1, 1, 1, hov and 0.16 or 0.08 }, { 1, 1, 1, 0 })
	else
		K.rect(x1, y1, x2, y2, { 0.1, 0.1, 0.1, 0.9 })
	end
	K.frame(x1, y1, x2, y2, hov and K.HOVER or (enabled and c or K.DARK), opts.border or 1)
	local h = y2 - y1
	local size = opts.size or h * 0.5
	local tc = opts.textColor or (enabled and (opts.bright and c or K.WHITE) or K.GREY)
	local x = (x1 + x2) / 2
	if opts.icon then
		local is = h - 6
		K.tex(opts.icon, x1 + 3, y1 + 3, x1 + 3 + is, y2 - 3, 1, 1, 1, enabled and 1 or 0.4)
		x = (x1 + is + 3 + x2) / 2
		label = K.fit(label, size, x2 - x1 - is - 10)
	end
	K.text(label, x, y1 + (h - size) * 0.5 + size * 0.2, size, tc, "co")
	K.addBox(x1, y1, x2, y2, enabled and fn or nil, tip)
	return hov
end

-- a close "x" in the top right corner of a window
function K.closeButton(x2, y2, s, fn)
	local x1, y1 = x2 - s, y2 - s
	local hov = K.hovered(x1, y1, x2, y2)
	K.rect(x1, y1, x2, y2, hov and { 0.4, 0.1, 0.08, 1 } or { 0.15, 0.04, 0.03, 0.95 })
	K.frame(x1, y1, x2, y2, hov and K.HOVER or { 0.6, 0.2, 0.15, 1 }, 1)
	K.text("x", (x1 + x2) / 2, y1 + s * 0.22, s * 0.7, K.RED, "co")
	K.addBox(x1, y1, x2, y2, fn, "Close (Esc)")
end

---------------------------------------------------------------------------- tooltips
-- A tip is a string (lines split by "\n", inline color codes) or a table:
--   { lines = { { text =, color = {r,g,b}, size = <x the base size>, sep = true (a rule above) } }, center = bool,
--     border = {r,g,b}, width = <min width in base sizes> }

local function tipLines(tip)
	if type(tip) == "table" then
		return tip.lines, tip
	end
	local lines = {}
	for line in (tip .. "\n"):gmatch("([^\n]*)\n") do
		lines[#lines + 1] = { text = line }
	end
	return lines, {}
end

function K.drawTip(tip, mx, my)
	if not tip or tip == "" then
		return
	end
	local font = K.getFont()
	if not font then
		return
	end
	local size = floor(K.vsy * 0.0155 * K.ui)
	local lines, o = tipLines(tip)
	local w = (o.width or 0) * size
	local hgt = size * 0.7
	for _, l in ipairs(lines) do
		local s = size * (l.size or 1)
		w = max(w, K.width(l.text, s))
		hgt = hgt + s * 1.28 + (l.sep and size * 0.5 or 0)
	end
	local pad = size * 0.7
	local W = w + pad * 2
	local tx = min(mx + 20, K.vsx - W - 4)
	if tx < 4 then
		tx = 4
	end
	local ty = min(my + 20 + hgt, K.vsy - 4)
	if ty - hgt < 4 then
		ty = hgt + 4
	end
	K.rect(tx, ty - hgt, tx + W, ty, { 0.015, 0.015, 0.025, 0.95 })
	local bc = o.border or K.BRONZE
	K.frame(tx, ty - hgt, tx + W, ty, { bc[1], bc[2], bc[3], 1 }, 2)
	K.frame(tx + 3, ty - hgt + 3, tx + W - 3, ty - 3, { bc[1] * 0.4, bc[2] * 0.4, bc[3] * 0.4, 1 }, 1)
	font:Begin()
	local y = ty - size * 0.35
	for _, l in ipairs(lines) do
		local s = size * (l.size or 1)
		if l.sep then
			y = y - size * 0.25
			K.rect(tx + pad, y, tx + W - pad, y + 1, { 0.45, 0.4, 0.3, 0.8 })
			y = y - size * 0.25
		end
		y = y - s * 1.28
		local c = l.color or K.WHITE
		if o.center then
			K.text(l.text, tx + W / 2, y + s * 0.3, s, { c[1], c[2], c[3], 1 }, "co")
		else
			K.text(l.text, tx + pad, y + s * 0.3, s, { c[1], c[2], c[3], 1 }, "o")
		end
	end
	font:End()
end

return K
