-- v23: the rocket-artillery heroes (Ambassador armt4ambassador, Negotiator cort4negotiator, Boreas legt4boreas) share
-- one kit: three warhead toggles (only one at a time; casting one switches the rack over until another is chosen or
-- it is cast again) and a passive ultimate. Numbers per rank: H.rocketModes in luarules/configs/t4_heroes.lua.
--
--   a1 Long-Range Rockets  (toggle): +range, a little less damage.
--   a2 Cluster Warheads    (toggle): less direct damage; every rocket impact scatters bomblets over an area.
--   a3 Tactical Nukes      (toggle): much slower reload, more direct damage; the first impact of each salvo is a
--                                    tactical nuclear blast (area damage, a nuke flash everyone sees).
--   ult Rocket Mastery     (passive): +range, +fire rate, +damage of the rack.
--
-- Usage (luarules/heroes/<hero>.lua): return VFS.Include("luarules/heroes/t4_rocketmodes.lua")({ color = {r,g,b,a} })

return function(opts)
	opts = opts or {}
	local COLOR = opts.color or { 1, 0.6, 0.2, 1 }
	local NUKE = { 1, 0.85, 0.5, 1 }
	local MODES = { a1 = "long", a2 = "cluster", a3 = "nuke" }

	local M = {}

	local function cfg(h, key)
		return h.def.cfg[key]
	end

	local function dist(x1, z1, x2, z2)
		return math.sqrt((x1 - x2) ^ 2 + (z1 - z2) ^ 2)
	end

	local function mastery(api, unitID, h)
		local r = api.rank(h, "ult")
		if r <= 0 then
			return
		end
		local u = cfg(h, "ult")
		api.buff(unitID, h, "rmastery", nil, { range = api.val(u.range, r), reload = api.val(u.reload, r),
			damage = api.val(u.damage, r) })
	end

	local function modeMods(api, h, key, r)
		local b = cfg(h, key)
		if key == "a1" then
			return { range = api.val(b.range, r), damage = -(b.dmgCut or 0.15) }
		elseif key == "a2" then
			return { damage = -(b.dmgCut or 0.35) }
		end
		return { reload = -api.val(b.slow, r), damage = api.val(b.damage, r) }
	end

	function M.init(api, unitID, h)
		h.store.mode = nil
		h.store.nukeArmed = false
		mastery(api, unitID, h)
	end

	function M.rank(api, unitID, h, key, rank)
		if key == "ult" then
			mastery(api, unitID, h)
		elseif h.store.mode == key then
			api.buff(unitID, h, "rmode", nil, modeMods(api, h, key, rank))
		end
	end

	function M.cast(api, unitID, h, key, rank)
		if not MODES[key] then
			return false
		end
		for other in pairs(MODES) do
			if other ~= key and h.store.mode == other then
				api.toggleOff(unitID, h, other)
			end
		end
		h.store.mode = key
		h.store.nukeArmed = key == "a3"
		api.buff(unitID, h, "rmode", nil, modeMods(api, h, key, rank))
		local x, y, z = api.pos(unitID)
		if api.fx and x then
			api.fx.flash(x, y + 60, z, { radius = 80, color = key == "a3" and NUKE or COLOR, ttl = 0.3 })
		end
		api.log("%s rocket mode %s rank=%d", h.def.name, MODES[key], rank)
		return true
	end

	function M.toggleOff(api, unitID, h, key)
		if h.store.mode == key then
			h.store.mode = nil
			h.store.nukeArmed = false
			api.unbuff(unitID, h, "rmode")
		end
	end

	-- every salvo re-arms the nuke: its first impact is the blast
	function M.fired(api, unitID, h)
		if h.store.mode == "a3" then
			h.store.nukeArmed = true
		end
	end

	function M.impact(api, unitID, h, weaponDefID, x, y, z)
		local mode = h.store.mode
		if not mode then
			return
		end
		local isRack = false
		for _, w in pairs(h.def.weapons) do
			if w.wdid == weaponDefID then
				isRack = true
			end
		end
		if not isRack then
			return
		end
		local key = mode
		local r = api.rank(h, key)
		if r <= 0 then
			return
		end
		local b = cfg(h, key)
		local p = api.power(h)
		if key == "a2" then
			local n = math.floor(api.val(b.bomblets, r) + 0.5)
			local spread = api.val(b.spread, r)
			local aoe = api.val(b.aoe, r)
			local dmg = api.val(b.dmg, r) * p
			for i = 1, n do
				local a = (i / n) * 2 * math.pi + math.random() * 0.6
				local d = spread * (0.35 + 0.65 * math.random())
				local bx, bz = x + math.cos(a) * d, z + math.sin(a) * d
				api.delay(3 + i * 2, function()
					local by = Spring.GetGroundHeight(bx, bz)
					api.area(bx, bz, aoe, dmg, unitID, { dtype = "explosive" })
					if api.fx then
						api.fx.flash(bx, by + 15, bz, { radius = aoe * 0.8, color = COLOR, ttl = 0.25 })
					end
					api.ceg("genericshellexplosion-medium-aoe", bx, by + 5, bz)
				end)
			end
		elseif key == "a3" and h.store.nukeArmed then
			h.store.nukeArmed = false
			local R = api.val(b.radius, r)
			local dmg = api.val(b.blast, r) * p
			local hits = api.area(x, z, R, dmg, unitID, { dtype = "explosive" })
			api.ceg("newnuketac", x, y, z)
			if api.fx then
				api.fx.flash(x, y + 40, z, { radius = R * 0.6, color = NUKE, ttl = 0.5 })
				api.fx.ring(x, z, { kind = "shock", r0 = 30, r1 = R * 1.2, width = 50, ttl = 0.6, color = NUKE })
			end
			api.log("%s tactical nuke rank=%d dmg=%d radius=%d hit=%d", h.def.name, r, dmg, R, hits and #hits or 0)
		end
	end

	-- AI and player autocast: nukes when an enemy hero or a pack of 8+ is in rack range, clusters vs 4+, else long range
	function M.autocast(api, unitID, h, key, rank)
		local x, y, z = api.pos(unitID)
		if not x then
			return nil
		end
		local reach = 0
		for _, w in pairs(h.def.weapons) do
			reach = math.max(reach, w.range or 0)
		end
		local list = api.enemiesIn(x, z, reach * 1.3, h.ally)
		local hero = false
		for _, uid in ipairs(list) do
			if api.isHero(uid) then
				hero = true
			end
		end
		local want
		if (hero or #list >= 8) and api.rank(h, "a3") > 0 then
			want = "a3"
		elseif #list >= 4 and api.rank(h, "a2") > 0 then
			want = "a2"
		elseif api.rank(h, "a1") > 0 then
			want = "a1"
		end
		if want == key and h.store.mode ~= key then
			return x, y, z
		end
		return nil
	end

	return M
end
