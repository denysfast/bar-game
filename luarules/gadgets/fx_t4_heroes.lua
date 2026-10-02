--------------------------------------------------------------------------------
-- Hero FX — shader effects library for T4 hero abilities (GG.HeroFX)
--------------------------------------------------------------------------------
-- Everything is drawn with instanced GL4 shaders (shaders/GLSL/heroes/*): no CEG sprites.
-- Callable from SYNCED gadgets (calls are forwarded with SendToUnsynced, ids are returned at once)
-- and from UNSYNCED code (same functions). Effects are drawn only where the local player may see
-- them (LOS of the local ally team; spectators with full view see everything).
-- Units: world elmos; ttl in seconds; colour = {r,g,b[,a]} 0..1 or a palette name (see
-- include/heroes_fx/shared.lua: electric, emp, red, rage, laser, orange, fire, heat, gold, holy,
-- green, heal, toxic, purple, void, shield, cloak, white, stone, ice, shadow, fog, cyan).
-- Every call returns an id; detach(id) ends any effect early (soft fade), set(id, {...}) changes it.
--
-- PRIMITIVES (one-shot unless noted; all accept opts.visible = "los"(default)|"ally"|"all" and
-- opts.ally = allyTeamID (owner team for "ally"; defaults to the attached unit's ally team)):
--   bolt(x1,y1,z1, x2,y2,z2, {color, width=3, ttl=0.35, branches=auto, seed, jitter=auto,
--        grow=0.07 (leader travel time s), intensity=1, impact=true (flash at the end)})
--   chain({x,y,z, x,y,z, ...}, {bolt opts..., delay=0.05 s per hop, flash=true})
--   beam(x1,y1,z1, x2,y2,z2, {color, width=4, ttl=0.5, pulse=1 (flow speed), flare=1 (end flare size),
--        rot=0 (rad/s sweep around p1 = start point), ground=false (snap the far end to the ground)})
--   ring(x, z, {kind="shock"|"rune"|"hex"|"electric"|"heat"|"heal"|"glow"|"sweep"|"fog"|"web"|"fire"|"swirl",
--        r0=10, r1=300, width=24, ttl=1, color, rot (rad/s: rune spin / sweep / sector spin), angle,
--        arc (radians; >0 = sector/cone centred on angle; angle measured from +x towards +z)})
--   zone(x, z, {radius=200, pattern="electric"|..., color, ttl=nil (persistent), arc, angle, rot})
--   flash(x, y, z, {radius=60, color, ttl=0.5, ground=true (light pool on the ground)})
--   pillar(x, z, {radius=30, height=600, color, ttl=1.5, ring=true (shock ring at the base)})
-- ATTACHMENTS (persistent until detach(id) or opts.ttl; follow the unit on the GPU):
--   attach(unitID, kind, opts) -> id
--     "aura"     ground disc: radius, color, pattern = "electric"|"heat"|"heal"|"runes"|"hex"|"fog"|"web"|"swirl"|"fire"|"glow"
--     "sphere"   shield bubble: radius, color, hex=true, hexScale=7, fresnel=2.6, height (centre above base)
--     "electric" arcs crawling over the body (+ model overlay): color, intensity=1, overlay=true
--     "orb"      floating energy orb(s): color, radius=14, height=70, orbit=0, speed=0.35 (rev/s), phase=0,
--                count=1 (orbs spread evenly), crackle=3 (tendrils per orb)
--     "cloak"    refraction-like shimmer, visible to the owner's allies only
--     "trail"    glowing ribbon behind the unit: color, width=8, length=0.6 (s), height
--     "mark"     reticle under the unit with stack segments: color, radius, stacks=0, max=5
--     "link"     tether to opts.target (unitID): style = "beam"|"bolt"|"drain" (drain flows target -> unit)
--     "tint"     overlay on the unit's model: pattern = "rim"|"stone"|"heat"|"electric"|"ice"|"shadow", strength=1
--   attachPoint(x, z, kind, opts) -> id   same for a map point: "aura"/"zone", "sphere", "orb", "electric", "mark"
--   orbPos(unitID, opts, frame, index) -> x,y,z      pure, synced-safe position of orb #index (0-based)
--   orbPointPos(x, z, opts, frame, index) -> x,y,z   same for attachPoint orbs
--   detach(id)                  soft fade-out of any effect (attachments and one-shots alike)
--   hit(id, x, y, z)            ripple on a "sphere" at world point x,y,z (last 4 hits are animated)
--   set(id, {radius=, color=, alpha=, stacks=, max=, angle=, rot=, arc=, intensity=, scale=, target=, time=})
--                               change a running effect; radius/alpha/scale animate over opts.time seconds
--
-- TYPICAL VALUES
--   chain lightning:   GG.HeroFX.chain({hx,hy+30,hz, x1,y1,z1, x2,y2,z2}, {color="electric", width=3, ttl=0.4, delay=0.06})
--   red rage:          GG.HeroFX.attach(uid, "electric", {color="rage", intensity=1.6})
--                      GG.HeroFX.attach(uid, "orb", {color="rage", radius=16, height=110, orbit=40, speed=0.5})
--                      GG.HeroFX.attach(uid, "tint", {pattern="heat", color="rage", strength=0.6})
--                      bolt from the orb: local ox,oy,oz = GG.HeroFX.orbPos(uid, orbOpts, Spring.GetGameFrame())
--                      GG.HeroFX.bolt(ox,oy,oz, tx,ty,tz, {color="rage", width=4, ttl=0.3})
--   EMP blast:         GG.HeroFX.ring(x,z, {kind="electric", r0=20, r1=420, width=30, ttl=0.9, color="emp"})
--                      GG.HeroFX.ring(x,z, {kind="shock", r0=10, r1=460, width=40, ttl=0.7, color="emp"})
--                      GG.HeroFX.flash(x,y+20,z, {radius=140, color="emp", ttl=0.5})
--   circle laser sweep (3 s, twin beam): for k = 0, 1 do
--                      local a = k * math.pi
--                      GG.HeroFX.beam(x,y+40,z, x+R*cos(a),y,z+R*sin(a), {color="laser", width=6, ttl=3, rot=2*math.pi/3, ground=true})
--                      GG.HeroFX.ring(x,z, {kind="sweep", r1=R, r0=R*0.2, width=26, ttl=3.6, rot=2*math.pi/3, angle=a, color="fire"}) end
--   flamethrower cone: GG.HeroFX.ring(x,z, {kind="fire", r1=320, arc=0.7, angle=math.atan2(dz,dx), ttl=0.8, color="fire"})
--   shield bubble:     id = GG.HeroFX.attach(uid, "sphere", {radius=90, color="shield", hex=true}); on hit: GG.HeroFX.hit(id, x,y,z)
--   resurrection:      GG.HeroFX.pillar(x,z, {radius=40, height=900, color="holy", ttl=2.2})
--                      GG.HeroFX.ring(x,z, {kind="rune", r1=150, width=30, ttl=2.5, color="gold"})
--   cloak:             id = GG.HeroFX.attach(uid, "cloak", {color="cloak"})   (detach on decloak)
--   drone lasers:      GG.HeroFX.beam(dx,dy,dz, tx,ty,tz, {color="red", width=2, ttl=0.18, flare=0.6})
--   debuff mark:       id = GG.HeroFX.attach(enemy, "mark", {color="red", max=5, stacks=1}); GG.HeroFX.set(id, {stacks=3})
--   devour tether:     GG.HeroFX.attach(heroID, "link", {target=victim, style="drain", color="electric", ttl=1})
--------------------------------------------------------------------------------

local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Hero FX",
		desc = "GG.HeroFX: shader effects (lightning, lasers, ground rings, shields, orbs...) for T4 hero abilities",
		author = "BAR custom",
		date = "2026",
		license = "GNU GPL, v2 or later",
		layer = -50,
		enabled = true,
	}
end

local Shared = VFS.Include("luarules/gadgets/include/heroes_fx/shared.lua")

--------------------------------------------------------------------------------
-- SYNCED: forward to the unsynced renderer
--------------------------------------------------------------------------------
if gadgetHandler:IsSyncedCode() then
	local SendToUnsynced = SendToUnsynced
	local encode = Shared.encode
	local tconcat = table.concat
	local nextID = 0
	local function newID()
		nextID = nextID + 1
		return nextID
	end

	local FX = { synced = true, palette = Shared.palette, orbPos = Shared.orbPos, orbPointPos = Shared.orbPointPos }
	function FX.bolt(x1, y1, z1, x2, y2, z2, opts)
		local id = newID()
		SendToUnsynced("herofx", "bolt", id, x1, y1, z1, x2, y2, z2, encode(opts))
		return id
	end
	function FX.chain(points, opts)
		local id = newID()
		SendToUnsynced("herofx", "chain", id, tconcat(points, ","), encode(opts))
		return id
	end
	function FX.beam(x1, y1, z1, x2, y2, z2, opts)
		local id = newID()
		SendToUnsynced("herofx", "beam", id, x1, y1, z1, x2, y2, z2, encode(opts))
		return id
	end
	function FX.ring(x, z, opts)
		local id = newID()
		SendToUnsynced("herofx", "ring", id, x, z, encode(opts))
		return id
	end
	function FX.zone(x, z, opts)
		local id = newID()
		SendToUnsynced("herofx", "zone", id, x, z, encode(opts))
		return id
	end
	function FX.flash(x, y, z, opts)
		local id = newID()
		SendToUnsynced("herofx", "flash", id, x, y, z, encode(opts))
		return id
	end
	function FX.pillar(x, z, opts)
		local id = newID()
		SendToUnsynced("herofx", "pillar", id, x, z, encode(opts))
		return id
	end
	function FX.attach(unitID, kind, opts)
		local id = newID()
		SendToUnsynced("herofx", "attach", id, unitID, kind, encode(opts))
		return id
	end
	function FX.attachPoint(x, z, kind, opts)
		local id = newID()
		SendToUnsynced("herofx", "attachPoint", id, x, z, kind, encode(opts))
		return id
	end
	function FX.detach(id)
		if id then
			SendToUnsynced("herofx", "detach", id)
		end
	end
	function FX.hit(id, x, y, z)
		if id then
			SendToUnsynced("herofx", "hit", id, x, y, z)
		end
	end
	function FX.set(id, opts)
		if id then
			SendToUnsynced("herofx", "set", id, encode(opts))
		end
	end

	GG.HeroFX = FX
	function gadget:Initialize()
		GG.HeroFX = FX
	end
	function gadget:Shutdown()
		if GG.HeroFX == FX then
			GG.HeroFX = nil
		end
	end
	return
end

--------------------------------------------------------------------------------
-- UNSYNCED: renderer
--------------------------------------------------------------------------------
local spGetGameFrame = Spring.GetGameFrame
local spIsPosInLos = Spring.IsPosInLos
local spIsUnitInLos = Spring.IsUnitInLos
local spGetUnitAllyTeam = Spring.GetUnitAllyTeam
local spGetLocalAllyTeamID = Spring.GetLocalAllyTeamID
local spGetSpectatingState = Spring.GetSpectatingState
local spGetGroundHeight = Spring.GetGroundHeight
local spValidUnitID = Spring.ValidUnitID
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitViewPosition = Spring.GetUnitViewPosition
local spGetUnitRadius = Spring.GetUnitRadius
local spGetUnitHeight = Spring.GetUnitHeight
local spGetUnitHeading = Spring.GetUnitHeading
local spGetUnitCollisionVolumeData = Spring.GetUnitCollisionVolumeData
local spGetTimer = Spring.GetTimer
local spDiffTimers = Spring.DiffTimers

local glBlending = gl.Blending
local glDepthTest = gl.DepthTest
local glDepthMask = gl.DepthMask
local glCulling = gl.Culling
local glTexture = gl.Texture
local glPolygonOffset = gl.PolygonOffset
local GL_ONE = GL.ONE
local GL_SRC_ALPHA = GL.SRC_ALPHA
local GL_ONE_MINUS_SRC_ALPHA = GL.ONE_MINUS_SRC_ALPHA

local mathMax, mathMin, mathFloor, mathSqrt = math.max, math.min, math.floor, math.sqrt
local mathSin, mathCos, mathRandom, mathPi, mathAtan2 = math.sin, math.cos, math.random, math.pi, math.atan2
local TAU = 2 * mathPi
local FOREVER = 1.0e8
local DETACH_FADE = 15

local LuaShader = gl.LuaShader
local IVT = gl.InstanceVBOTable
local IVIT = gl.InstanceVBOIdTable
local uploadAllElements = IVT.uploadAllElements
local colorOf = Shared.color
local decode = Shared.decode

local SHADER_DIR = "shaders/GLSL/heroes/"
local BOLT_SEGS = 40
local GROUND_RES = 48

local fullView = false
local myAlly = spGetLocalAllyTeamID()
local debugStats = false
local statTime, statFrames, statMax = 0, 0, 0

--------------------------------------------------------------------------------
-- GL setup
--------------------------------------------------------------------------------
local commonSrc
local function loadSrc(file, isVS)
	local src = VFS.LoadFile(SHADER_DIR .. file)
	if not src then
		Spring.Echo("[HeroFX] missing shader file " .. file)
		return nil
	end
	local common = (isVS and "#define HEROFX_VS 1\n" or "") .. commonSrc
	return (src:gsub("//__HEROFX_COMMON__", function()
		return common
	end))
end

local function compile(name, base, defines, uniformInt)
	local cfg = {
		ATTACHED = 0,
		BOLTMODE = 0,
		SEGS = BOLT_SEGS,
		USEQUATERNIONS = (Engine.FeatureSupport and Engine.FeatureSupport.transformsInGL4) and 1 or 0,
	}
	for k, v in pairs(defines or {}) do
		cfg[k] = v
	end
	local vs, fs = loadSrc(base .. ".vert.glsl", true), loadSrc(base .. ".frag.glsl", false)
	if not vs or not fs then
		return nil
	end
	local sh = LuaShader.CheckShaderUpdates({
		vsSrc = vs,
		fsSrc = fs,
		shaderName = "HeroFX_" .. name,
		uniformInt = uniformInt or {},
		uniformFloat = {},
		shaderConfig = cfg,
		forceupdate = true,
		silent = true,
	})
	if not sh then
		Spring.Echo("[HeroFX] shader compile failed: " .. name)
	end
	return sh
end

local function makeVertexVBO(layout, data, count)
	local vbo = gl.GetVBO(GL.ARRAY_BUFFER, false)
	vbo:Define(count, layout)
	vbo:Upload(data)
	return vbo
end
local function makeIndexVBO(idx)
	local vbo = gl.GetVBO(GL.ELEMENT_ARRAY_BUFFER, false)
	vbo:Define(#idx)
	vbo:Upload(idx)
	return vbo
end

local meshes = {}
local function buildMeshes()
	-- lightning / ribbon strip: (t, side)
	local d = {}
	for i = 0, BOLT_SEGS do
		local t = i / BOLT_SEGS
		d[#d + 1] = t; d[#d + 1] = -1; d[#d + 1] = 0; d[#d + 1] = 0
		d[#d + 1] = t; d[#d + 1] = 1; d[#d + 1] = 0; d[#d + 1] = 0
	end
	meshes.strip = { vbo = makeVertexVBO({ { id = 0, name = "tv", size = 4 } }, d, 2 * (BOLT_SEGS + 1)), count = 2 * (BOLT_SEGS + 1), prim = GL.TRIANGLE_STRIP }
	-- quad strip
	local q = { -1, -1, 0, 0, 1, -1, 0, 0, -1, 1, 0, 0, 1, 1, 0, 0 }
	meshes.quad = { vbo = makeVertexVBO({ { id = 0, name = "quad", size = 4 } }, q, 4), count = 4, prim = GL.TRIANGLE_STRIP }
	-- ground grid
	local plane = IVT.makePlaneVBO(1, 1, GROUND_RES, GROUND_RES, "HeroFXPlane")
	local pidx, pidxData = IVT.makePlaneIndexVBO(GROUND_RES, GROUND_RES, true, "HeroFXPlaneIdx")
	meshes.plane = { vbo = plane, index = pidx, count = #pidxData }
	-- unit sphere
	local sv, si = {}, {}
	local stacks, sectors = 20, 36
	for i = 0, stacks do
		local phi = mathPi / 2 - i * mathPi / stacks
		local cy, sy = mathCos(phi), mathSin(phi)
		for j = 0, sectors do
			local th = j * TAU / sectors
			sv[#sv + 1] = cy * mathCos(th); sv[#sv + 1] = sy; sv[#sv + 1] = cy * mathSin(th); sv[#sv + 1] = 0
		end
	end
	for i = 0, stacks - 1 do
		local k1, k2 = i * (sectors + 1), (i + 1) * (sectors + 1)
		for j = 0, sectors - 1 do
			if i ~= 0 then si[#si + 1] = k1 + j; si[#si + 1] = k2 + j; si[#si + 1] = k1 + j + 1 end
			if i ~= stacks - 1 then si[#si + 1] = k1 + j + 1; si[#si + 1] = k2 + j; si[#si + 1] = k2 + j + 1 end
		end
	end
	meshes.sphere = { vbo = makeVertexVBO({ { id = 0, name = "sph", size = 4 } }, sv, #sv / 4), index = makeIndexVBO(si), count = #si }
	-- open tube for pillars
	local tv, ti = {}, {}
	local around, rings = 32, 16
	for i = 0, rings do
		local y = i / rings
		for j = 0, around do
			local a = j / around
			tv[#tv + 1] = mathCos(a * TAU); tv[#tv + 1] = y; tv[#tv + 1] = mathSin(a * TAU); tv[#tv + 1] = a
		end
	end
	for i = 0, rings - 1 do
		local k1, k2 = i * (around + 1), (i + 1) * (around + 1)
		for j = 0, around - 1 do
			ti[#ti + 1] = k1 + j; ti[#ti + 1] = k2 + j; ti[#ti + 1] = k1 + j + 1
			ti[#ti + 1] = k1 + j + 1; ti[#ti + 1] = k2 + j; ti[#ti + 1] = k2 + j + 1
		end
	end
	meshes.tube = { vbo = makeVertexVBO({ { id = 0, name = "tube", size = 4 } }, tv, #tv / 4), index = makeIndexVBO(ti), count = #ti }
end

--------------------------------------------------------------------------------
-- Batches: one instance buffer per primitive type, rebuilt only when its visible set changes
--------------------------------------------------------------------------------
local function L(n)
	local t = {}
	for i = 1, n do
		t[i] = { id = i, name = "a" .. i, size = 4 }
	end
	return t
end
local function withUnit(layout, id)
	layout[#layout + 1] = { id = id, name = "instData", type = GL.UNSIGNED_INT, size = 4 }
	return layout
end

local batches = {}
local B = {}

local function newBatch(name, layout, unitAttr, mesh, endOffset, size)
	local vbo = IVT.makeInstanceVBOTable(layout, size or 64, "HeroFX_" .. name, unitAttr)
	vbo.VAO = vbo:makeVAOandAttach(mesh.vbo, vbo.instanceVBO, mesh.index)
	local b = {
		name = name, vbo = vbo, layout = layout, unitAttr = unitAttr, mesh = mesh,
		step = vbo.instanceStep, list = {}, n = 0, dirty = false, lastN = 0, endOffset = endOffset,
	}
	batches[#batches + 1] = b
	B[name] = b
	return b
end

local function growBatch(b, need)
	local size = b.vbo.maxElements
	while size <= need + 1 do
		size = size * 2
	end
	local vbo = IVT.makeInstanceVBOTable(b.layout, size, "HeroFX_" .. b.name, b.unitAttr)
	vbo.VAO = vbo:makeVAOandAttach(b.mesh.vbo, vbo.instanceVBO, b.mesh.index)
	b.vbo:Delete()
	b.vbo = vbo
	b.lastN = 0
end

local function newTintBatch(size)
	local vertVBO = gl.GetVBO(GL.ARRAY_BUFFER, false)
	local indxVBO = gl.GetVBO(GL.ELEMENT_ARRAY_BUFFER, false)
	vertVBO:ModelsVBO()
	indxVBO:ModelsVBO()
	local layout = {
		{ id = 6, name = "i_color", size = 4 },
		{ id = 7, name = "i_par", size = 4 },
		{ id = 8, name = "i_anim", size = 4 },
		{ id = 9, name = "instData", type = GL.UNSIGNED_INT, size = 4 },
	}
	local vbo = IVIT.makeInstanceVBOTable(layout, size, "HeroFX_tint", 9, "unitID")
	vbo.VAO = IVIT.makeVAOandAttach(vertVBO, vbo.instanceVBO, indxVBO)
	local b = {
		name = "tint", vbo = vbo, layout = layout, step = vbo.instanceStep, list = {}, n = 0, dirty = false,
		lastN = 0, endOffset = 8, tint = true, vert = vertVBO, indx = indxVBO,
	}
	batches[#batches + 1] = b
	B.tint = b
	return b
end

local function rebuild(b)
	local list = b.list
	local need = 0
	for i = 1, b.n do
		local r = list[i]
		if r.vis then
			need = need + r.ninst
		end
	end
	if need >= b.vbo.maxElements - 1 then
		if b.tint then
			local size = b.vbo.maxElements
			while size <= need + 1 do size = size * 2 end
			b.vbo.instanceVBO:Delete()
			b.vbo.VAO:Delete()
			local vbo = IVIT.makeInstanceVBOTable(b.layout, size, "HeroFX_tint", 9, "unitID")
			vbo.VAO = IVIT.makeVAOandAttach(b.vert, vbo.instanceVBO, b.indx)
			b.vbo = vbo
		else
			growBatch(b, need)
		end
	end
	local vbo = b.vbo
	local data = vbo.instanceData
	local uids = vbo.indextoUnitID
	local step = b.step
	local n, off = 0, 0
	for i = 1, b.n do
		local r = list[i]
		if r.vis then
			local d = r.data
			for j = 1, r.ninst * step do
				data[off + j] = d[j]
			end
			if uids then
				for j = 1, r.ninst do
					uids[n + j] = r.unitID
				end
			end
			n = n + r.ninst
			off = off + r.ninst * step
		end
	end
	if uids then
		for j = n + 1, b.lastN do
			uids[j] = nil
		end
	end
	b.lastN = n
	vbo.usedElements = n
	if b.tint then
		local VAO = vbo.VAO
		VAO:ClearSubmission()
		if n > 0 then
			vbo.instanceVBO:Upload(data, nil, 0, 1, n * step)
			for i = 1, n do
				local u = uids[i]
				vbo.instanceVBO:InstanceDataFromUnitIDs(u, 9, i - 1)
				VAO:AddUnitsToSubmission(u)
			end
		end
	elseif n > 0 then
		uploadAllElements(vbo)
	end
	b.dirty = false
end

local function drawBatch(b)
	local vbo = b.vbo
	local n = vbo.usedElements
	if n == 0 then
		return
	end
	local m = b.mesh
	if m.index then
		vbo.VAO:DrawElements(GL.TRIANGLES, m.count, 0, n, 0)
	else
		vbo.VAO:DrawArrays(m.prim, m.count, 0, n, 0)
	end
end

--------------------------------------------------------------------------------
-- Records, groups (ids), visibility
--------------------------------------------------------------------------------
local groups = {} -- id -> { rec, rec, ... }
local unitRecs = {} -- unitID -> { [rec] = true }
local perFrame = { links = {}, nLinks = 0, trails = {}, nTrails = 0 }
local unsyncedNextID = 10000000

local VIS_LOS, VIS_ALLY, VIS_ALL = 0, 1, 2

local function visModeOf(o)
	local v = o.visible
	if v == "ally" or v == "allies" or v == "team" then
		return VIS_ALLY
	elseif v == "all" or v == "always" then
		return VIS_ALL
	end
	return VIS_LOS
end

local function unitVisible(u, allyOnly)
	if not spValidUnitID(u) then
		return false
	end
	if fullView then
		return true
	end
	if spGetUnitAllyTeam(u) == myAlly then
		return true
	end
	if allyOnly then
		return false
	end
	return spIsUnitInLos(u, myAlly) and true or false
end

local function recVisible(r)
	if r.visMode == VIS_ALLY and not fullView and r.ally ~= myAlly then
		return false
	end
	if fullView or r.visMode == VIS_ALL then
		if r.unitID then
			return spValidUnitID(r.unitID) and true or false
		end
		return true
	end
	if r.unitID then
		local v = unitVisible(r.unitID, r.allyOnly)
		if not v and r.target then
			v = unitVisible(r.target, r.allyOnly)
		end
		return v
	end
	local lp = r.lp
	if lp then
		for i = 1, #lp, 3 do
			if spIsPosInLos(lp[i], lp[i + 1], lp[i + 2], myAlly) then
				return true
			end
		end
		return false
	end
	return true
end

local function addToGroup(gid, r)
	local g = groups[gid]
	if not g then
		g = {}
		groups[gid] = g
	end
	g[#g + 1] = r
	r.gid = gid
end

local function addRec(b, r, gid)
	b.n = b.n + 1
	b.list[b.n] = r
	r.batch = b
	r.vis = recVisible(r)
	if r.vis then
		b.dirty = true
	end
	addToGroup(gid, r)
	local u = r.unitID
	if u then
		local t = unitRecs[u]
		if not t then
			t = {}
			unitRecs[u] = t
		end
		t[r] = true
		if r.target then
			local t2 = unitRecs[r.target]
			if not t2 then
				t2 = {}
				unitRecs[r.target] = t2
			end
			t2[r] = true
		end
	end
end

local function forgetRec(r)
	local g = r.gid and groups[r.gid]
	if g then
		for i = #g, 1, -1 do
			if g[i] == r then
				table.remove(g, i)
			end
		end
		if #g == 0 then
			groups[r.gid] = nil
		end
	end
	if r.unitID and unitRecs[r.unitID] then
		unitRecs[r.unitID][r] = nil
	end
	if r.target and unitRecs[r.target] then
		unitRecs[r.target][r] = nil
	end
end

-- end an effect softly: rewrite its end frame in the instance data
local function endRec(r, now, fade)
	local e = now + (fade or DETACH_FADE)
	if r.endF <= e then
		return
	end
	r.endF = e
	local b = r.batch
	if b and b.endOffset then
		local d, step = r.data, b.step
		for k = 0, r.ninst - 1 do
			d[k * step + b.endOffset] = e
		end
		if r.vis then
			b.dirty = true
		end
	end
end

local function sweep(now)
	for bi = 1, #batches do
		local b = batches[bi]
		local list = b.list
		local i = 1
		while i <= b.n do
			local r = list[i]
			if r.dead or r.endF <= now then
				list[i] = list[b.n]
				list[b.n] = nil
				b.n = b.n - 1
				if r.vis then
					b.dirty = true
				end
				forgetRec(r)
			else
				i = i + 1
			end
		end
	end
	for _, kind in ipairs({ "links", "trails" }) do
		local list = perFrame[kind]
		local nk = kind == "links" and "nLinks" or "nTrails"
		local i = 1
		while i <= perFrame[nk] do
			local r = list[i]
			if r.dead or r.endF <= now then
				list[i] = list[perFrame[nk]]
				list[perFrame[nk]] = nil
				perFrame[nk] = perFrame[nk] - 1
				forgetRec(r)
			else
				i = i + 1
			end
		end
	end
end

local function updateVisibility()
	for bi = 1, #batches do
		local b = batches[bi]
		local list = b.list
		for i = 1, b.n do
			local r = list[i]
			local v = recVisible(r)
			if v ~= r.vis then
				r.vis = v
				b.dirty = true
			end
		end
	end
	for i = 1, perFrame.nLinks do
		local r = perFrame.links[i]
		r.vis = recVisible(r)
	end
	for i = 1, perFrame.nTrails do
		local r = perFrame.trails[i]
		r.vis = recVisible(r)
	end
end

--------------------------------------------------------------------------------
-- Instance data helpers
--------------------------------------------------------------------------------
local function put4(d, i, a, b, c, e)
	d[i] = a
	d[i + 1] = b
	d[i + 2] = c
	d[i + 3] = e
	return i + 4
end

local function newRec(o, ninst)
	return { o = o, ninst = ninst, data = {}, visMode = visModeOf(o), ally = o.ally, endF = FOREVER }
end

local function ttlFrames(o, default)
	local t = o.ttl or default
	if not t then
		return nil
	end
	return mathMax(1, t * 30)
end

local function rgba(o, default)
	local r, g, b, a = colorOf(o.color, default)
	if o.alpha then
		a = a * o.alpha
	end
	return r, g, b, a
end

local function unitMid(u)
	local bx, by, bz, mx, my, mz = spGetUnitPosition(u, true)
	if not bx then
		return nil
	end
	return bx, by, bz, my - by
end

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------
local FX = { synced = false, palette = Shared.palette, orbPos = Shared.orbPos, orbPointPos = Shared.orbPointPos }
local impl = {}

local function newID()
	unsyncedNextID = unsyncedNextID + 1
	return unsyncedNextID
end

local function rnd(seed)
	-- small LCG so branch layouts are stable for a given seed
	local s = seed
	return function()
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

-- flash ----------------------------------------------------------------------
function impl.flash(gid, x, y, z, o, start)
	local now = start or spGetGameFrame()
	local radius = o.radius or 60
	local ttl = ttlFrames(o, 0.5)
	local r = newRec(o, 1)
	local cr, cg, cb, ca = rgba(o, "holy")
	local d = r.data
	local i = put4(d, 1, x, y, z, radius)
	i = put4(d, i, cr, cg, cb, ca * (o.intensity or 1))
	i = put4(d, i, now, now + ttl, o.seed or mathRandom() * 100, 0)
	i = put4(d, i, 0, 0, 0, 0)
	put4(d, i, 1, 1, 0, 0)
	r.endF = now + ttl
	r.lp = { x, y, z }
	addRec(B.billboard, r, gid)
	if o.ground ~= false and radius >= 25 then
		local gy = spGetGroundHeight(x, z)
		if y - gy < radius * 2.5 then
			impl.ring(gid, x, z, { kind = "glow", r1 = radius * 1.9, ttl = (o.ttl or 0.5) * 1.3, color = o.color or "holy", alpha = 0.8 * (o.alpha or 1),
				visible = o.visible, ally = o.ally }, now)
		end
	end
	return gid
end

-- bolt -----------------------------------------------------------------------
function impl.bolt(gid, x1, y1, z1, x2, y2, z2, o, start)
	local now = start or spGetGameFrame()
	local ttl = ttlFrames(o, 0.35)
	local width = o.width or 3
	local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
	local len = mathSqrt(dx * dx + dy * dy + dz * dz)
	if len < 1 then
		return gid
	end
	local seed = o.seed or mathFloor(mathRandom() * 100000)
	local rand = rnd(seed)
	local nb = o.branches or mathMin(5, mathMax(1, mathFloor(len / 110)))
	local r = newRec(o, 1 + nb)
	local cr, cg, cb, ca = rgba(o, "electric")
	local grow = (o.grow or 0.07) * 30
	local inten = o.intensity or 1
	local d = r.data
	local i = 1
	local jit = o.jitter or 0
	local sd = (seed % 997) + 0.5
	-- main bolt
	i = put4(d, i, x1, y1, z1, width)
	i = put4(d, i, x2, y2, z2, jit)
	i = put4(d, i, cr, cg, cb, ca)
	i = put4(d, i, now, now + ttl, sd, grow)
	i = put4(d, i, -1, 0, 0, 0)
	i = put4(d, i, inten, 0, o.glow or 0, 0)
	-- branches: anchored on the main path, angled away from it
	local ux, uy, uz = dx / len, dy / len, dz / len
	for k = 1, nb do
		local a = 0.15 + 0.7 * rand()
		local bl = len * (0.12 + 0.22 * rand())
		local rx, ry, rz = rand() * 2 - 1, rand() * 2 - 1, rand() * 2 - 1
		local bx, by, bz = ux * 0.75 + rx * 0.9, uy * 0.75 + ry * 0.6, uz * 0.75 + rz * 0.9
		local bn = mathSqrt(bx * bx + by * by + bz * bz)
		bx, by, bz = bx / bn * bl, by / bn * bl, bz / bn * bl
		i = put4(d, i, x1, y1, z1, width)
		i = put4(d, i, x2, y2, z2, jit)
		i = put4(d, i, cr, cg, cb, ca)
		i = put4(d, i, now, now + ttl * (0.6 + 0.4 * rand()), sd, grow)
		i = put4(d, i, a, bx, by, bz)
		i = put4(d, i, inten, (sd * 7.3 + k * 13.1) % 1000, o.glow or 0, 0)
	end
	r.endF = now + ttl
	r.lp = { x1, y1, z1, x2, y2, z2 }
	addRec(B.bolt, r, gid)
	if o.impact ~= false then
		impl.flash(gid, x2, y2, z2, { radius = mathMax(width * 7, 20) * (o.impactScale or 1), ttl = mathMin(ttl / 30, 0.35), color = o.color or "electric",
			ground = false, visible = o.visible, ally = o.ally, alpha = o.alpha }, now + grow)
	end
	return gid
end

function impl.chain(gid, pts, o)
	local now = spGetGameFrame()
	local delay = (o.delay or 0.05) * 30
	local n = mathFloor(#pts / 3)
	for k = 1, n - 1 do
		local j = (k - 1) * 3
		local start = now + (k - 1) * delay
		local bo = {}
		for kk, v in pairs(o) do
			bo[kk] = v
		end
		bo.seed = (o.seed or mathFloor(mathRandom() * 100000)) + k * 31
		bo.impact = false
		impl.bolt(gid, pts[j + 1], pts[j + 2], pts[j + 3], pts[j + 4], pts[j + 5], pts[j + 6], bo, start)
		if o.flash ~= false then
			impl.flash(gid, pts[j + 4], pts[j + 5], pts[j + 6], { radius = (o.width or 3) * 9, ttl = 0.35, color = o.color or "electric", ground = false,
				visible = o.visible, ally = o.ally }, start + (o.grow or 0.07) * 30)
		end
	end
	return gid
end

-- beam -----------------------------------------------------------------------
function impl.beam(gid, x1, y1, z1, x2, y2, z2, o, start)
	local now = start or spGetGameFrame()
	local ttl = ttlFrames(o, 0.5)
	local r = newRec(o, 1)
	local cr, cg, cb, ca = rgba(o, "laser")
	local d = r.data
	local i = put4(d, 1, x1, y1, z1, o.width or 4)
	i = put4(d, i, x2, y2, z2, o.flare or 1)
	i = put4(d, i, cr, cg, cb, ca * (o.intensity or 1))
	i = put4(d, i, now, now + ttl, o.seed or mathRandom() * 100, o.pulse or 1)
	put4(d, i, o.rot or 0, o.ground and 1 or 0, o.rotDelay and o.rotDelay * 30 or 0, 0)
	r.endF = now + ttl
	if o.rot and o.rot ~= 0 then
		-- sweeping: LOS on the pivot and a few points of the swept circle
		local R = mathSqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2)
		r.lp = { x1, y1, z1, x1 + R, y1, z1, x1 - R, y1, z1, x1, y1, z1 + R, x1, y1, z1 - R }
	else
		r.lp = { x1, y1, z1, x2, y2, z2 }
	end
	addRec(B.beam, r, gid)
	return gid
end

-- ground ---------------------------------------------------------------------
local groundKinds = {
	shock = 0, rune = 1, runes = 1, hex = 2, electric = 3, heat = 4, heal = 5, glow = 6, sweep = 7,
	fog = 8, web = 9, mark = 10, fire = 11, swirl = 12,
}
local groundDefaultColor = {
	shock = "electric", rune = "gold", runes = "gold", hex = "shield", electric = "electric", heat = "heat", heal = "heal",
	glow = "holy", sweep = "fire", fog = "fog", web = "white", mark = "red", fire = "fire", swirl = "void",
}

-- writes one ground instance into d at index i (24 floats)
local function groundData(d, i, cx, cz, o, kindName, now, endF)
	local kind = groundKinds[kindName] or 0
	local r0 = o.r0 or 10
	local r1 = o.r1 or o.radius or 300
	local width = o.width or (kind == 2 and 26 or kind == 10 and 4 or 24)
	local R = mathMax(r0, r1) + width * 2.5 + 30
	if kind == 10 then
		R = r1 * 1.4 + 6
	end
	local cr, cg, cb, ca = colorOf(o.color, groundDefaultColor[kindName] or "electric")
	ca = ca * (o.alpha or 1) * (o.intensity or 1)
	local p1, p2 = o.rot or 0, o.angle or 0
	if kind == 10 then
		p1 = o.max or 5
	end
	local an = o._anim
	i = put4(d, i, cx, cz, R, kind)
	i = put4(d, i, r0, r1, width, o.seed or (mathRandom() * 100))
	i = put4(d, i, cr, cg, cb, ca)
	i = put4(d, i, now, endF, p1, p2)
	i = put4(d, i, o.arc or 0, o.angle or 0, (kind ~= 7 and kind ~= 1 and kind ~= 12) and (o.rot or 0) or 0, o.stacks or 0)
	if an then
		i = put4(d, i, an[1], an[2], an[3], an[4])
	else
		i = put4(d, i, 1, 1, 0, 0)
	end
	return i
end

function impl.ring(gid, x, z, o, start)
	local now = start or spGetGameFrame()
	local ttl = ttlFrames(o, 1.0)
	local r = newRec(o, 1)
	local kindName = o.kind or "shock"
	r.kindName = kindName
	r.cx, r.cz = x, z
	r.start = now
	groundData(r.data, 1, x, z, o, kindName, now, now + ttl)
	r.endF = now + ttl
	local y = spGetGroundHeight(x, z)
	r.lp = { x, y, z }
	local R = o.r1 or o.radius or 300
	if R > 250 then
		local lp = r.lp
		lp[4], lp[5], lp[6] = x + R * 0.7, y, z
		lp[7], lp[8], lp[9] = x - R * 0.7, y, z
		lp[10], lp[11], lp[12] = x, y, z + R * 0.7
		lp[13], lp[14], lp[15] = x, y, z - R * 0.7
	end
	r.make = function(rec)
		groundData(rec.data, 1, rec.cx, rec.cz, rec.o, rec.kindName, rec.start, rec.endF)
	end
	addRec(B.ground, r, gid)
	return gid
end

function impl.zone(gid, x, z, o)
	local zo = {}
	for k, v in pairs(o) do
		zo[k] = v
	end
	zo.kind = o.pattern or o.kind or "electric"
	if zo.kind == "runes" then zo.kind = "rune" end
	zo.r1 = o.radius or o.r1 or 200
	zo.ttl = o.ttl or (FOREVER / 30)
	if zo.kind == "rune" then
		zo.width = o.width or zo.r1 * 0.18
	end
	return impl.ring(gid, x, z, zo)
end

-- pillar ---------------------------------------------------------------------
function impl.pillar(gid, x, z, o)
	local now = spGetGameFrame()
	local ttl = ttlFrames(o, 1.5)
	local y = spGetGroundHeight(x, z)
	local radius = o.radius or 30
	local r = newRec(o, 1)
	local cr, cg, cb, ca = rgba(o, "gold")
	local d = r.data
	local i = put4(d, 1, x, y - 4, z, radius)
	i = put4(d, i, cr, cg, cb, ca * (o.intensity or 1))
	put4(d, i, now, now + ttl, o.seed or mathRandom() * 100, o.height or 600)
	r.endF = now + ttl
	r.lp = { x, y, z }
	addRec(B.pillar, r, gid)
	impl.ring(gid, x, z, { kind = "glow", r1 = radius * 4, ttl = o.ttl or 1.5, color = o.color or "gold", visible = o.visible, ally = o.ally }, now)
	if o.ring ~= false then
		impl.ring(gid, x, z, { kind = "shock", r0 = radius, r1 = radius * 6, width = radius * 0.8, ttl = 0.8, color = o.color or "gold", visible = o.visible, ally = o.ally }, now)
	end
	return gid
end

--------------------------------------------------------------------------------
-- Attachments
--------------------------------------------------------------------------------
local attachKinds = {}

local function attachCommon(r, unitID, o, now)
	r.unitID = unitID
	r.ally = o.ally or spGetUnitAllyTeam(unitID)
	local ttl = o.ttl and mathMax(1, o.ttl * 30) or nil
	r.endF = ttl and (now + ttl) or FOREVER
	r.start = now
	return r.endF
end

local function unitShape(unitID)
	local radius = spGetUnitRadius(unitID) or 30
	local height = spGetUnitHeight(unitID) or radius
	local sx, sy, sz, ox, oy, oz = spGetUnitCollisionVolumeData(unitID)
	local _, by, _, midOff = unitMid(unitID)
	midOff = midOff or height * 0.5
	if not sx or sx <= 0 then
		sx, sy, sz, oy = radius * 1.6, height, radius * 1.6, 0
	end
	return radius, height, sx * 0.5, sy * 0.5, sz * 0.5, midOff + (oy or 0)
end

-- aura (ground disc following a unit) / mark
local function groundAttach(gid, unitID, o, now, kindName, point)
	local r = newRec(o, 1)
	r.kindName = kindName
	local endF
	if point then
		r.endF = o.ttl and now + mathMax(1, o.ttl * 30) or FOREVER
		r.start = now
		endF = r.endF
		r.cx, r.cz = point[1], point[2]
		r.lp = { point[1], spGetGroundHeight(point[1], point[2]), point[2] }
	else
		endF = attachCommon(r, unitID, o, now)
		r.cx, r.cz = 0, 0
	end
	local radius = o.radius or (unitID and (spGetUnitRadius(unitID) or 40) * (kindName == "mark" and 0.9 or 1.6)) or 150
	local go = r.o
	go.r1 = radius
	if kindName == "rune" and not go.width then
		go.width = radius * 0.2
	end
	r.make = function(rec)
		local i = groundData(rec.data, 1, rec.cx, rec.cz, rec.o, rec.kindName, rec.start, rec.endF)
		if rec.unitID then
			put4(rec.data, i, 0, 0, 0, 0) -- instData placeholder
		end
	end
	r.make(r)
	addRec(point and B.ground or B.groundU, r, gid)
	return r
end

function attachKinds.aura(gid, unitID, o, now, point)
	local p = o.pattern or "electric"
	if p == "runes" then p = "rune" end
	return groundAttach(gid, unitID, o, now, p, point)
end
attachKinds.zone = attachKinds.aura

function attachKinds.mark(gid, unitID, o, now, point)
	return groundAttach(gid, unitID, o, now, "mark", point)
end

-- sphere / cloak
local function sphereData(rec)
	local o = rec.o
	local d = rec.data
	local cr, cg, cb, ca = colorOf(o.color, rec.cloak and "cloak" or "shield")
	ca = ca * (o.alpha or 1) * (o.intensity or 1)
	local sc = o.scale or 1
	local rx, ry, rz = rec.ext[1] * sc, rec.ext[2] * sc, rec.ext[3] * sc
	local i = put4(d, 1, rec.offY, rx, ry, rz)
	i = put4(d, i, cr, cg, cb, ca)
	i = put4(d, i, rec.start, rec.endF, rec.seed, rec.cloak and 1 or 0)
	i = put4(d, i, (o.hex == false) and 0 or (o.hexScale or 7), o.fresnel or 0, rec.heading and 1 or 0, 0)
	local an = o._anim
	if an then
		i = put4(d, i, an[1], an[2], an[3], an[4])
	else
		i = put4(d, i, 1, 1, 0, 0)
	end
	local hits = rec.hits
	for k = 1, 4 do
		local h = hits[k]
		if h then
			i = put4(d, i, h[1], h[2], h[3], h[4])
		else
			i = put4(d, i, 0, 1, 0, -1000)
		end
	end
	if rec.anchor then
		put4(d, i, rec.anchor[1], rec.anchor[2], rec.anchor[3], 0)
	else
		put4(d, i, 0, 0, 0, 0)
	end
end

function attachKinds.sphere(gid, unitID, o, now, point, cloak)
	local r = newRec(o, 1)
	r.cloak = cloak
	r.seed = mathRandom() * 100
	r.hits = {}
	r.hitN = 0
	if point then
		r.endF = o.ttl and now + mathMax(1, o.ttl * 30) or FOREVER
		r.start = now
		local y = spGetGroundHeight(point[1], point[2])
		r.anchor = { point[1], y, point[2] }
		r.lp = { point[1], y, point[2] }
		local rad = o.radius or 120
		r.ext = { rad, rad, rad }
		r.offY = o.height or 0
	else
		attachCommon(r, unitID, o, now)
		local radius, height, hx, hy, hz, midOff = unitShape(unitID)
		if cloak then
			local m = o.radius and (o.radius / radius) or 1.05
			r.ext = { hx * m * 1.05, hy * m * 1.1, hz * m * 1.05 }
			r.offY = midOff
			r.heading = true
			r.allyOnly = true
		else
			local rad = o.radius or mathMax(radius * 1.3, mathMax(hx, hz) * 1.25)
			r.ext = { rad, rad * (o.flatten or 1), rad }
			r.offY = o.height or midOff * 0.6
		end
	end
	r.make = sphereData
	sphereData(r)
	addRec(point and B.sphere or B.sphereU, r, gid)
	if cloak and o.overlay ~= false and unitID then
		attachKinds.tint(gid, unitID, { pattern = "rim", color = o.color or "cloak", strength = 0.45, ttl = o.ttl }, now, nil, true)
	end
	return r
end

function attachKinds.cloak(gid, unitID, o, now, point)
	return attachKinds.sphere(gid, unitID, o, now, point, true)
end

-- electric crawl (arcs) + optional electric model overlay
local function arcsData(rec)
	local o = rec.o
	local d = rec.data
	local cr, cg, cb, ca = colorOf(o.color, "electric")
	ca = ca * (o.alpha or 1)
	local inten = o.intensity or 1
	local sc = o.scale or 1
	local i = 1
	for k = 0, rec.ninst - 1 do
		if rec.mode == 0 then
			i = put4(d, i, rec.ext[1] * sc, rec.ext[2] * sc, rec.ext[3] * sc, rec.offY * sc)
			i = put4(d, i, k, rec.ninst, o.reach or 0.45, (o.width or 1.7) * mathSqrt(sc))
		else
			i = put4(d, i, rec.orbRadius, 0, 0, 0)
			i = put4(d, i, k, rec.ninst, rec.orbRadius * (o.reachMul or 2.2), o.width or 1.3)
		end
		i = put4(d, i, cr, cg, cb, ca)
		i = put4(d, i, rec.start, rec.endF, rec.seed, o.period or 7)
		if rec.orb then
			i = put4(d, i, rec.orb[1], rec.orb[2], rec.orb[3], rec.orb[4])
		else
			i = put4(d, i, 0, 0, 0, 0)
		end
		i = put4(d, i, inten, rec.mode, o.glow or 7, o.jitterScale or 1)
		-- 7th slot: anchor for point arcs, placeholder for the unit's instData otherwise
		if rec.anchor then
			i = put4(d, i, rec.anchor[1], rec.anchor[2], rec.anchor[3], 0)
		else
			i = put4(d, i, 0, 0, 0, 0)
		end
	end
end

function attachKinds.electric(gid, unitID, o, now, point)
	local inten = o.intensity or 1
	local n = o.arcs or mathFloor(3 + 5 * inten + 0.5)
	local r = newRec(o, n)
	r.mode = 0
	r.seed = mathRandom() * 500
	if point then
		r.endF = o.ttl and now + mathMax(1, o.ttl * 30) or FOREVER
		r.start = now
		local y = spGetGroundHeight(point[1], point[2])
		r.anchor = { point[1], y, point[2] }
		r.point = true
		r.lp = { point[1], y, point[2] }
		local rad = o.radius or 60
		r.ext = { rad, rad * 0.8, rad }
		r.offY = o.height or rad * 0.5
	else
		attachCommon(r, unitID, o, now)
		local radius, height, hx, hy, hz, midOff = unitShape(unitID)
		r.ext = { hx * 0.95, hy * 0.85, hz * 0.95 }
		r.offY = midOff
	end
	r.make = arcsData
	arcsData(r)
	addRec(point and B.arcs or B.arcsU, r, gid)
	if not point and o.overlay ~= false then
		attachKinds.tint(gid, unitID, { pattern = "electric", color = o.color or "electric", strength = mathMin(1.2, 0.55 * inten + 0.2), ttl = o.ttl }, now)
	end
	return r
end

-- orb(s): billboard + tendrils
local function orbData(rec)
	local o = rec.o
	local d = rec.data
	local cr, cg, cb, ca = colorOf(o.color, "electric")
	ca = ca * (o.alpha or 1) * (o.intensity or 1)
	local count = rec.ninst
	local i = 1
	for k = 0, count - 1 do
		local phase = (o.phase or 0) + k * TAU / count
		i = put4(d, i, rec.anchor and rec.anchor[1] or 0, rec.anchor and rec.anchor[2] or 0, rec.anchor and rec.anchor[3] or 0, o.radius or 14)
		i = put4(d, i, cr, cg, cb, ca)
		i = put4(d, i, rec.start, rec.endF, rec.seed + k * 17, 1)
		i = put4(d, i, o.orbit or 0, o.height or Shared.ORB_HEIGHT, o.speed or Shared.ORB_SPEED, phase)
		local an = o._anim
		if an then
			i = put4(d, i, an[1], an[2], an[3], an[4])
		else
			i = put4(d, i, 1, 1, 0, 0)
		end
		if not rec.anchor then
			i = put4(d, i, 0, 0, 0, 0) -- instData placeholder
		end
	end
end

function attachKinds.orb(gid, unitID, o, now, point)
	local count = mathMax(1, mathFloor(o.count or 1))
	local r = newRec(o, count)
	r.seed = mathRandom() * 100
	if point then
		r.endF = o.ttl and now + mathMax(1, o.ttl * 30) or FOREVER
		r.start = now
		local y = spGetGroundHeight(point[1], point[2])
		r.anchor = { point[1], y, point[2] }
		r.lp = { point[1], y + (o.height or Shared.ORB_HEIGHT), point[2] }
	else
		attachCommon(r, unitID, o, now)
	end
	r.make = orbData
	orbData(r)
	addRec(point and B.billboard or B.billboardU, r, gid)
	-- crackling tendrils per orb
	local crackle = o.crackle or 3
	if crackle > 0 then
		for k = 0, count - 1 do
			local t = newRec({ color = o.color, alpha = o.alpha, width = (o.radius or 14) * 0.09, intensity = o.intensity, period = 5, glow = 6, visible = o.visible, ally = o.ally }, crackle)
			t.mode = 1
			t.seed = r.seed * 3 + k * 11
			t.orbRadius = o.radius or 14
			t.orb = { o.orbit or 0, o.height or Shared.ORB_HEIGHT, o.speed or Shared.ORB_SPEED, (o.phase or 0) + k * TAU / count }
			if point then
				t.start, t.endF, t.anchor, t.point, t.lp = r.start, r.endF, r.anchor, true, r.lp
			else
				attachCommon(t, unitID, o, now)
			end
			t.make = arcsData
			arcsData(t)
			t.orbChild = true
			addRec(point and B.arcs or B.arcsU, t, gid)
		end
	end
	return r
end

-- model overlay
local tintPatterns = { rim = 0, stone = 1, petrify = 1, heat = 2, electric = 3, ice = 4, frost = 4, shadow = 5, void = 5 }
local tintDefaultColor = { rim = "white", stone = "stone", petrify = "stone", heat = "heat", electric = "electric", ice = "ice", frost = "ice", shadow = "shadow", void = "void" }
local function tintData(rec)
	local o = rec.o
	local d = rec.data
	local p = o.pattern or "rim"
	local cr, cg, cb, ca = colorOf(o.color, tintDefaultColor[p] or "white")
	ca = ca * (o.alpha or 1)
	local an = o._anim
	local i = put4(d, 1, cr, cg, cb, ca)
	i = put4(d, i, tintPatterns[p] or 0, o.strength or 1, rec.start, rec.endF)
	if an then
		i = put4(d, i, an[2], an[3], an[4], rec.seed)
	else
		i = put4(d, i, 1, 0, 0, rec.seed)
	end
	put4(d, i, 0, 0, 0, 0)
end

function attachKinds.tint(gid, unitID, o, now, point, allyOnly)
	if point or not unitID then
		return nil
	end
	local r = newRec(o, 1)
	attachCommon(r, unitID, o, now)
	r.seed = mathRandom() * 100
	r.allyOnly = allyOnly
	r.make = tintData
	tintData(r)
	addRec(B.tint, r, gid)
	return r
end

-- trail (per-frame ribbon)
local TRAIL_POINTS = 24
function attachKinds.trail(gid, unitID, o, now, point)
	if point then
		return nil
	end
	local r = newRec(o, 0)
	attachCommon(r, unitID, o, now)
	local _, height = unitShape(unitID)
	r.height = o.height or height * 0.35
	r.pts = {}
	r.head = 0
	r.count = 0
	r.lenF = mathMax(4, (o.length or 0.6) * 30)
	r.seed = mathRandom() * 100
	r.vis = recVisible(r)
	perFrame.nTrails = perFrame.nTrails + 1
	perFrame.trails[perFrame.nTrails] = r
	addToGroup(gid, r)
	local t = unitRecs[unitID] or {}
	unitRecs[unitID] = t
	t[r] = true
	return r
end

-- link (per-frame tether between two units)
function attachKinds.link(gid, unitID, o, now, point)
	if point or not o.target or not spValidUnitID(o.target) then
		return nil
	end
	local r = newRec(o, 0)
	attachCommon(r, unitID, o, now)
	r.target = o.target
	r.style = o.style or "beam"
	r.seed = mathFloor(mathRandom() * 1000)
	local _, ha = unitShape(unitID)
	local _, hb = unitShape(o.target)
	r.ha = o.height or ha * 0.5
	r.hb = o.targetHeight or hb * 0.5
	r.vis = recVisible(r)
	perFrame.nLinks = perFrame.nLinks + 1
	perFrame.links[perFrame.nLinks] = r
	addToGroup(gid, r)
	for _, u in ipairs({ unitID, o.target }) do
		local t = unitRecs[u] or {}
		unitRecs[u] = t
		t[r] = true
	end
	return r
end

function impl.attach(gid, unitID, kind, o)
	if not unitID or not spValidUnitID(unitID) then
		return gid
	end
	local f = attachKinds[kind]
	if not f then
		Spring.Echo("[HeroFX] unknown attach kind " .. tostring(kind))
		return gid
	end
	f(gid, unitID, o, spGetGameFrame())
	return gid
end

function impl.attachPoint(gid, x, z, kind, o)
	local f = attachKinds[kind]
	if not f then
		Spring.Echo("[HeroFX] unknown attachPoint kind " .. tostring(kind))
		return gid
	end
	f(gid, nil, o, spGetGameFrame(), { x, z })
	return gid
end

--------------------------------------------------------------------------------
-- detach / hit / set
--------------------------------------------------------------------------------
function impl.detach(gid)
	local g = groups[gid]
	if not g then
		return
	end
	local now = spGetGameFrame()
	for i = 1, #g do
		endRec(g[i], now, g[i].orbChild and 6 or DETACH_FADE)
	end
end

function impl.hit(gid, x, y, z)
	local g = groups[gid]
	if not g then
		return
	end
	local now = spGetGameFrame()
	for i = 1, #g do
		local r = g[i]
		if r.make == sphereData and not r.cloak then
			local cx, cy, cz
			if r.anchor then
				cx, cy, cz = r.anchor[1], r.anchor[2] + r.offY, r.anchor[3]
			else
				local bx, by, bz = spGetUnitPosition(r.unitID)
				if bx then
					cx, cy, cz = bx, by + r.offY, bz
				end
			end
			if cx then
				local dx, dy, dz = x - cx, y - cy, z - cz
				local l = mathSqrt(dx * dx + dy * dy + dz * dz)
				if l > 0.01 then
					r.hitN = r.hitN % 4 + 1
					r.hits[r.hitN] = { dx / l, dy / l, dz / l, now }
					sphereData(r)
					if r.vis then
						r.batch.dirty = true
					end
				end
			end
		end
	end
end

local function currentAnimScale(an, now)
	-- current value of an in-flight scale animation (relative to its target)
	if not an then
		return 1, 1
	end
	local t = an[4] > 0 and mathMin(1, mathMax(0, (now - an[3]) / an[4])) or 1
	t = t * t * (3 - 2 * t)
	return an[1] + (1 - an[1]) * t, an[2] + (1 - an[2]) * t
end

function impl.set(gid, s)
	local g = groups[gid]
	if not g then
		return
	end
	local now = spGetGameFrame()
	local dur = (s.time or 0) * 30
	for i = 1, #g do
		local r = g[i]
		local o = r.o
		-- animated radius / scale / alpha: keep the old value as the animation start
		local curS, curA = currentAnimScale(o._anim, now)
		local fromS, fromA = curS, curA
		if s.radius and (o.radius or o.r1) then
			local old = o.radius or o.r1
			fromS = curS * old / s.radius
			o.radius = s.radius
			o.r1 = s.radius
			if r.ext and not r.cloak then
				r.ext = { s.radius, s.radius * (o.flatten or 1), s.radius }
			end
		elseif s.radius and r.ext then
			fromS = curS * r.ext[1] / s.radius
			r.ext = { s.radius, s.radius * (o.flatten or 1), s.radius }
		end
		if s.radius and r.orbRadius then
			r.orbRadius = s.radius
		end
		if s.scale then
			fromS = fromS * (o.scale or 1) / s.scale
			o.scale = s.scale
		end
		if s.alpha then
			fromA = curA * (o.alpha or 1) / mathMax(s.alpha, 0.001)
			o.alpha = s.alpha
		end
		if dur > 0 and (fromS ~= 1 or fromA ~= 1) then
			o._anim = { fromS, mathMin(fromA, 20), now, dur }
		elseif s.radius or s.scale or s.alpha then
			o._anim = nil
		end
		for _, k in ipairs({ "color", "stacks", "max", "angle", "rot", "arc", "intensity", "width", "strength", "pattern" }) do
			if s[k] ~= nil then
				o[k] = s[k]
			end
		end
		if s.target and r.target then
			if unitRecs[r.target] then unitRecs[r.target][r] = nil end
			r.target = s.target
			local t = unitRecs[s.target] or {}
			unitRecs[s.target] = t
			t[r] = true
		end
		if r.make then
			r.make(r)
			if r.vis and r.batch then
				r.batch.dirty = true
			end
		end
	end
end

-- public unsynced API (same signatures as the synced forwarder)
function FX.bolt(x1, y1, z1, x2, y2, z2, opts) return impl.bolt(newID(), x1, y1, z1, x2, y2, z2, opts or {}) end
function FX.chain(points, opts) return impl.chain(newID(), points, opts or {}) end
function FX.beam(x1, y1, z1, x2, y2, z2, opts) return impl.beam(newID(), x1, y1, z1, x2, y2, z2, opts or {}) end
function FX.ring(x, z, opts) return impl.ring(newID(), x, z, opts or {}) end
function FX.zone(x, z, opts) return impl.zone(newID(), x, z, opts or {}) end
function FX.flash(x, y, z, opts) return impl.flash(newID(), x, y, z, opts or {}) end
function FX.pillar(x, z, opts) return impl.pillar(newID(), x, z, opts or {}) end
function FX.attach(unitID, kind, opts) return impl.attach(newID(), unitID, kind, opts or {}) end
function FX.attachPoint(x, z, kind, opts) return impl.attachPoint(newID(), x, z, kind, opts or {}) end
function FX.detach(id) if id then impl.detach(id) end end
function FX.hit(id, x, y, z) if id then impl.hit(id, x, y, z) end end
function FX.set(id, opts) if id and opts then impl.set(id, opts) end end
function FX.debug(on) debugStats = on and true or false end
function FX.stats()
	local t = {}
	for _, b in ipairs(batches) do
		t[b.name] = b.vbo.usedElements .. "/" .. b.n
	end
	t.links, t.trails = perFrame.nLinks, perFrame.nTrails
	return t
end

-- synced -> unsynced
local function onSync(_, op, id, ...)
	if op == "bolt" then
		local x1, y1, z1, x2, y2, z2, s = ...
		impl.bolt(id, x1, y1, z1, x2, y2, z2, decode(s))
	elseif op == "chain" then
		local ps, s = ...
		local pts = {}
		for v in ps:gmatch("[^,]+") do
			pts[#pts + 1] = tonumber(v)
		end
		impl.chain(id, pts, decode(s))
	elseif op == "beam" then
		local x1, y1, z1, x2, y2, z2, s = ...
		impl.beam(id, x1, y1, z1, x2, y2, z2, decode(s))
	elseif op == "ring" then
		local x, z, s = ...
		impl.ring(id, x, z, decode(s))
	elseif op == "zone" then
		local x, z, s = ...
		impl.zone(id, x, z, decode(s))
	elseif op == "flash" then
		local x, y, z, s = ...
		impl.flash(id, x, y, z, decode(s))
	elseif op == "pillar" then
		local x, z, s = ...
		impl.pillar(id, x, z, decode(s))
	elseif op == "attach" then
		local u, kind, s = ...
		impl.attach(id, u, kind, decode(s))
	elseif op == "attachPoint" then
		local x, z, kind, s = ...
		impl.attachPoint(id, x, z, kind, decode(s))
	elseif op == "detach" then
		impl.detach(id)
	elseif op == "hit" then
		local x, y, z = ...
		impl.hit(id, x, y, z)
	elseif op == "set" then
		impl.set(id, decode((...)))
	end
end

--------------------------------------------------------------------------------
-- Per-frame primitives: links, trails
--------------------------------------------------------------------------------
local function buildLinks(now)
	local bb, bm = B.linkBolt, B.linkBeam
	local nb, nm = 0, 0
	for i = 1, perFrame.nLinks do
		local r = perFrame.links[i]
		if r.vis and r.endF > now then
			local ax, ay, az = spGetUnitViewPosition(r.unitID)
			local tx, ty, tz = spGetUnitViewPosition(r.target)
			if ax and tx then
				ay, ty = ay + r.ha, ty + r.hb
				local o = r.o
				local cr, cg, cb, ca = colorOf(o.color, r.style == "bolt" and "electric" or "laser")
				ca = ca * (o.alpha or 1) * (o.intensity or 1)
				if r.style == "bolt" then
					if nb + 1 >= bb.vbo.maxElements then growBatch(bb, nb + 1) end
					local d = bb.vbo.instanceData
					local k = nb * bb.step + 1
					k = put4(d, k, ax, ay, az, o.width or 3)
					k = put4(d, k, tx, ty, tz, 0)
					k = put4(d, k, cr, cg, cb, ca)
					k = put4(d, k, r.start, r.endF, r.seed % 997 + 0.5, 0)
					k = put4(d, k, -1, 0, 0, 0)
					put4(d, k, 1, 0, o.glow or 0, 0)
					nb = nb + 1
				else
					if nm + 1 >= bm.vbo.maxElements then growBatch(bm, nm + 1) end
					local d = bm.vbo.instanceData
					local k = nm * bm.step + 1
					if r.style == "drain" then
						ax, ay, az, tx, ty, tz = tx, ty, tz, ax, ay, az
					end
					k = put4(d, k, ax, ay, az, o.width or 3)
					k = put4(d, k, tx, ty, tz, o.flare or 0.6)
					k = put4(d, k, cr, cg, cb, ca)
					k = put4(d, k, r.start, r.endF, r.seed, o.pulse or (r.style == "drain" and 2.2 or 1))
					put4(d, k, 0, 0, 0, 0)
					nm = nm + 1
				end
			end
		end
	end
	bb.vbo.usedElements = nb
	bm.vbo.usedElements = nm
	if nb > 0 then uploadAllElements(bb.vbo) end
	if nm > 0 then uploadAllElements(bm.vbo) end
end

local function sampleTrails(now)
	for i = 1, perFrame.nTrails do
		local r = perFrame.trails[i]
		local x, y, z = spGetUnitPosition(r.unitID)
		if x then
			local pts = r.pts
			local h = r.head
			local last = h > 0 and (h - 1) * 4 or (r.count > 0 and (TRAIL_POINTS - 1) * 4 or nil)
			local moved = true
			if last then
				local dx, dz = x - pts[last + 1], z - pts[last + 3]
				moved = dx * dx + dz * dz > 1
			end
			if moved or (now % 4 == 0) then
				local k = h * 4
				pts[k + 1], pts[k + 2], pts[k + 3], pts[k + 4] = x, y + r.height, z, now
				r.head = (h + 1) % TRAIL_POINTS
				r.count = mathMin(r.count + 1, TRAIL_POINTS)
			end
		end
	end
end

local function buildTrails(now)
	local b = B.trail
	local n = 0
	for i = 1, perFrame.nTrails do
		local r = perFrame.trails[i]
		if r.vis and r.count > 1 then
			local hx, hy, hz = spGetUnitViewPosition(r.unitID)
			if hx then
				hy = hy + r.height
				local o = r.o
				local cr, cg, cb, ca = colorOf(o.color, "electric")
				local env = mathMin(1, (now - r.start) / 10) * mathMin(1, mathMax(0, (r.endF - now) / DETACH_FADE))
				ca = ca * (o.alpha or 1) * env
				local w = o.width or 8
				local pts = r.pts
				local px, py, pz, pAge = hx, hy, hz, 0
				local dist = 0
				local idx = r.head
				for k = 1, r.count do
					idx = (idx - 1) % TRAIL_POINTS
					local j = idx * 4
					local qx, qy, qz, qf = pts[j + 1], pts[j + 2], pts[j + 3], pts[j + 4]
					local age = (now - qf) / r.lenF
					if age >= 1 then
						break
					end
					local sx, sy, sz = qx - px, qy - py, qz - pz
					local sl = mathSqrt(sx * sx + sy * sy + sz * sz)
					if sl > 0.5 then
						if n + 1 >= b.vbo.maxElements then growBatch(b, n + 1) end
						local d = b.vbo.instanceData
						local q = n * b.step + 1
						q = put4(d, q, px, py, pz, w)
						q = put4(d, q, qx, qy, qz, pAge)
						q = put4(d, q, cr, cg, cb, ca)
						put4(d, q, age, 1, r.seed, dist)
						n = n + 1
						dist = dist + sl
					end
					px, py, pz, pAge = qx, qy, qz, age
				end
			end
		end
	end
	b.vbo.usedElements = n
	if n > 0 then uploadAllElements(b.vbo) end
end

--------------------------------------------------------------------------------
-- Callins
--------------------------------------------------------------------------------
local shaders = {}

local function initGL()
	local cs = VFS.LoadFile(SHADER_DIR .. "herofx_common.glsl")
	if not cs then
		return false
	end
	commonSrc = cs
	buildMeshes()
	local hm = { heightmapTex = 0 }
	shaders.bolt = compile("bolt", "bolt", { BOLTMODE = 0 })
	shaders.arcsU = compile("arcsU", "bolt", { BOLTMODE = 1, ATTACHED = 1 })
	shaders.arcs = compile("arcs", "bolt", { BOLTMODE = 1, ATTACHED = 0 })
	shaders.beam = compile("beam", "beam", {}, hm)
	shaders.ground = compile("ground", "ground", {}, hm)
	shaders.groundU = compile("groundU", "ground", { ATTACHED = 1 }, hm)
	shaders.billboard = compile("billboard", "billboard", {})
	shaders.billboardU = compile("billboardU", "billboard", { ATTACHED = 1 })
	shaders.pillar = compile("pillar", "pillar", {})
	shaders.sphere = compile("sphere", "sphere", {})
	shaders.sphereU = compile("sphereU", "sphere", { ATTACHED = 1 })
	shaders.trail = compile("trail", "trail", {})
	shaders.tint = compile("tint", "tint", { ATTACHED = 1 })
	for name, sh in pairs(shaders) do
		if not sh then
			Spring.Echo("[HeroFX] disabled: shader " .. name .. " failed")
			return false
		end
	end

	newBatch("bolt", L(6), nil, meshes.strip, 14, 256)
	newBatch("arcsU", withUnit(L(6), 7), 7, meshes.strip, 14, 128)
	newBatch("arcs", L(7), nil, meshes.strip, 14, 64)
	newBatch("beam", L(5), nil, meshes.quad, 14, 64)
	newBatch("ground", L(6), nil, meshes.plane, 14, 64)
	newBatch("groundU", withUnit(L(6), 7), 7, meshes.plane, 14, 32)
	newBatch("billboard", L(5), nil, meshes.quad, 10, 128)
	newBatch("billboardU", withUnit(L(5), 6), 6, meshes.quad, 10, 32)
	newBatch("pillar", L(3), nil, meshes.tube, 10, 16)
	newBatch("sphere", L(10), nil, meshes.sphere, 10, 16)
	newBatch("sphereU", withUnit(L(9), 10), 10, meshes.sphere, 10, 32)
	newTintBatch(32)
	-- per-frame batches (no records; filled every draw frame)
	newBatch("linkBolt", L(6), nil, meshes.strip, nil, 16)
	newBatch("linkBeam", L(5), nil, meshes.quad, nil, 16)
	newBatch("trail", L(4), nil, meshes.quad, nil, 128)
	return true
end

function gadget:Initialize()
	if not gl.CreateShader or not gl.GetVBO then
		Spring.Echo("[HeroFX] no GL4 support: effects disabled (API stays callable)")
		-- keep a no-op API so callers never break
		local noop = function() return nil end
		GG.HeroFX = setmetatable({ orbPos = Shared.orbPos, orbPointPos = Shared.orbPointPos, palette = Shared.palette }, { __index = function() return noop end })
		gadgetHandler:AddSyncAction("herofx", function() end)
		return
	end
	local ok, err = pcall(initGL)
	if not ok or not err then
		Spring.Echo("[HeroFX] init failed: " .. tostring(err))
		local noop = function() return nil end
		GG.HeroFX = setmetatable({ orbPos = Shared.orbPos, orbPointPos = Shared.orbPointPos, palette = Shared.palette }, { __index = function() return noop end })
		gadgetHandler:AddSyncAction("herofx", function() end)
		return
	end
	gadgetHandler:AddSyncAction("herofx", onSync)
	GG.HeroFX = FX
	gadget:PlayerChanged()
end

function gadget:Shutdown()
	gadgetHandler:RemoveSyncAction("herofx")
	if GG.HeroFX == FX then
		GG.HeroFX = nil
	end
	for _, b in ipairs(batches) do
		if b.vbo then
			b.vbo:Delete()
		end
	end
	for _, sh in pairs(shaders) do
		if sh then
			sh:Delete()
		end
	end
end

function gadget:PlayerChanged()
	local _, fv = spGetSpectatingState()
	fullView = fv and true or false
	myAlly = spGetLocalAllyTeamID()
	updateVisibility()
end

function gadget:UnitDestroyed(unitID)
	local t = unitRecs[unitID]
	if not t then
		return
	end
	for r in pairs(t) do
		r.dead = true
		if r.vis and r.batch then
			r.batch.dirty = true
		end
		r.vis = false
	end
	unitRecs[unitID] = nil
	sweep(spGetGameFrame())
end

function gadget:GameFrame(n)
	sweep(n)
	if n % 3 == 0 then
		updateVisibility()
	end
	if perFrame.nTrails > 0 and n % 2 == 0 then
		sampleTrails(n)
	end
end

local function rebuildDirty()
	for i = 1, #batches do
		local b = batches[i]
		if b.dirty then
			rebuild(b)
		end
	end
end

local function beginFX()
	glDepthTest(true)
	glDepthMask(false)
	glCulling(false)
	glBlending(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)
end

local function endFX()
	glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
	glDepthMask(true)
	glDepthTest(false)
end

function gadget:DrawWorldPreUnit()
	if B.ground == nil then
		return
	end
	local t0 = debugStats and spGetTimer()
	rebuildDirty()
	if B.ground.vbo.usedElements + B.groundU.vbo.usedElements == 0 then
		return
	end
	beginFX()
	glTexture(0, "$heightmap")
	if B.ground.vbo.usedElements > 0 then
		shaders.ground:Activate()
		drawBatch(B.ground)
		shaders.ground:Deactivate()
	end
	if B.groundU.vbo.usedElements > 0 then
		shaders.groundU:Activate()
		drawBatch(B.groundU)
		shaders.groundU:Deactivate()
	end
	glTexture(0, false)
	endFX()
	if t0 then
		statTime = statTime + spDiffTimers(spGetTimer(), t0, true)
	end
end

local function drawPass(sh, b, pass)
	if b.vbo.usedElements == 0 then
		return
	end
	sh:Activate()
	if pass then
		sh:SetUniform("passMode", pass)
	end
	drawBatch(b)
	sh:Deactivate()
end

function gadget:DrawWorld()
	if B.bolt == nil then
		return
	end
	local t0 = debugStats and spGetTimer()
	local now = spGetGameFrame()
	rebuildDirty()
	if perFrame.nLinks > 0 or B.linkBolt.vbo.usedElements + B.linkBeam.vbo.usedElements > 0 then
		buildLinks(now)
	end
	if perFrame.nTrails > 0 or B.trail.vbo.usedElements > 0 then
		buildTrails(now)
	end

	-- model overlays first (depth-tested against the model they cover)
	if B.tint.vbo.usedElements > 0 then
		glDepthTest(true)
		glDepthMask(false)
		glCulling(GL.BACK)
		glPolygonOffset(-2, -2)
		glBlending(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)
		shaders.tint:Activate()
		B.tint.vbo.VAO:Submit()
		shaders.tint:Deactivate()
		glPolygonOffset(false)
		glCulling(false)
	end

	beginFX()
	drawPass(shaders.sphere, B.sphere)
	drawPass(shaders.sphereU, B.sphereU)
	drawPass(shaders.pillar, B.pillar, 0)
	drawPass(shaders.pillar, B.pillar, 1)
	drawPass(shaders.trail, B.trail)
	if B.beam.vbo.usedElements > 0 then
		glTexture(0, "$heightmap")
		drawPass(shaders.beam, B.beam)
		glTexture(0, false)
	end
	drawPass(shaders.beam, B.linkBeam)
	-- lightning: wide glow first, hot cores on top
	drawPass(shaders.bolt, B.bolt, 0)
	drawPass(shaders.bolt, B.linkBolt, 0)
	drawPass(shaders.arcsU, B.arcsU, 0)
	drawPass(shaders.arcs, B.arcs, 0)
	drawPass(shaders.bolt, B.bolt, 1)
	drawPass(shaders.bolt, B.linkBolt, 1)
	drawPass(shaders.arcsU, B.arcsU, 1)
	drawPass(shaders.arcs, B.arcs, 1)
	drawPass(shaders.billboard, B.billboard)
	drawPass(shaders.billboardU, B.billboardU)
	endFX()

	if t0 then
		local dt = spDiffTimers(spGetTimer(), t0, true)
		statTime = statTime + dt
		statFrames = statFrames + 1
		if dt > statMax then statMax = dt end
		if statFrames >= 150 then
			local inst = 0
			for _, b in ipairs(batches) do inst = inst + b.vbo.usedElements end
			Spring.Echo(string.format("[HeroFX] lua %.3f ms/frame avg, %.3f max, %d instances", statTime / statFrames, statMax, inst))
			statTime, statFrames, statMax = 0, 0, 0
		end
	end
end
