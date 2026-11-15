--!nocheck
-- ZangetsuKit.Client.Shunpo (owner: shunpo): E - SHUNPO 瞬歩, the flash-step cut (DESIGN §7.4, FLAIR pass). Every
-- client plays every cast from the server's broadcasts on the server timeline (e = ctx.now() - t0):
--   ShunpoCast   { id, userId, t0, from, to, face, departAt, arriveAt, cutAt, targets = { { model, along, pos } }, mode,
--                  len, secondAt }
--   ShunpoCut    { id, userId, models, dirs, wave (1 | 2), mode, poses }
--   ShunpoCancel { id, userId }
-- Beats (D = departAt 0.26, A = arriveAt 0.46, C = cutAt 1.12, HO = Config HandoffAt 1.52; clip "Shunpo" /
-- "ShunpoBankai", strikeAt 1.12, then "ShunpoFlourish" / "ShunpoFlourishBankai" from HO):
--   0.00 GATHER   callout; caster rooted, a camera squeeze; Zap + a rising Swell; reiatsu flames lick up off his feet;
--                 0.03 a ring collapses into his feet; 0.05 dust is drawn in; 0.06 the blade wreathes in reiatsu
--                 (bladeGlow 0.35 -> 1); 0.08 streaks pour into the blade; 0.10 a tremble (caster); 0.12 / 0.20
--                 crackling arcs over his body; 0.16 an arc runs the blade, pebbles hop;
--                 0.21 the edge flashes (a star at the tip, a high Zap).
--   D    VANISH   a LAUNCH afterimage left behind; he vanishes to A; the FLASH-STEP BURST: staggered shock rings in three
--                 planes (flat 1 -> 12 at D, standing across the path at D+0.04, a flat inner one at D+0.08), a radial
--                 crack of streaks, a flare + light, ground cracks under the push-off foot, a dust doughnut; the
--                 SONIC CRACK (a high Thunder + Crackle + Whoosh + Zap); caster: the mover,
--                 speed lines, a shake with an FOV kick (Tensa: a red flash). NO blade Trail (it drew a plank).
--   D..A TRAVEL   the main cut line is drawn along with him and left hanging; a CHAIN OF AFTERIMAGES, each FK-posed in a
--                 different slash pose (Clips.ShunpoAfterimages, turned GhostYaw off the dash, alternating sides), each
--                 leaving a glinting CUT LINE hanging where its blade went (the chord of its swing) + a glint + a
--                 quick arc flash (first 2); as he passes each body a tick and a faint mark across it.
--   A    ARRIVE   he reappears back-turned in AFTERCUT, skidding: dust line, flat ring, flare, sparks, the soft "ting"
--                 and a star on the blade; caster: rooted to RootEnd, a slow FOV lean-in.
--   A..C SILENCE  only a low Drone fading out; every hanging line breathes (3 Hz); frost glints hang along the path; the
--                 CASTER's screen desaturates at the edges (ColorCorrection + a cold edge vignette) and his camera
--                 takes the MONEY FRAME (a scripted shot from in front of him looking back down the path at the frozen
--                 bodies and the hanging chain, A+0.02 -> C+0.3); 1.02 a glint runs to the tip as he cocks the chiburi.
--   C    THE CUT  (ShunpoCut wave 1) callout "Zan"; the screen snaps back with a saturation pop; the chiburi snap
--                 (clip) with a flick arc, droplets and a flung streak; every hanging line SHATTERS (main + the nearest
--                 cut line; the rest burst into glints); every body bursts: an X of two slash lines, glows, shock
--                 rings in 2-3 planes, reiatsu sparks + a flame burst, a light flash, a comet trail, crackles (the
--                 nearest FullBodies get all of it, the rest a lean set); Shatter + staggered Hit2 + HitHeavy +
--                 Whoosh (+ Cannon for a crowd); every client holds his pose ClientHitStop; caster: impact frame
--                 (flash 0.14; Tensa: a crimson one), shake, tally. A whiff still shatters everything.
--   C+.12 WAVE 2  (Tensa Zangetsu only) a crimson third line through each X, black flame bursts, a ring, a low Hit2.
--   C..C+2.6 AFTER arcs crawl the blade (C+0.2 / C+0.38); residual rings settle under the first bodies (C+0.25);
--                 the marks fade into embers (C+0.3 / C+0.7); wisps rise off each cut body (C+0.6, 1.4 s); dust settles
--                 (C+0.5); Tensa: ash rises; steam off the blade 1.2 s; HO the CHIBURI FLOURISH: the overhead twirl
--                 (its own clip, arm only - he can walk) with a halo ribbon, a glint + a high Zap at the end of the
--                 spin, and a soft clack as the blade lands on his shoulder.
-- Tensa Zangetsu (payload mode): black-crimson afterimages (dark copies alternating with Crimson ForceField; the coat
-- only as its big panels) and more of them (Mode.Shunpo MaxGhosts / GhostEvery), black-cored lines with a Crimson
-- edge, Crimson X marks, black flames, a
-- red departure flash, a crimson impact frame, a reddened hush.
-- Tiers (others' casts, camera distance): <= NearDist everything; <= MidDist no path ghosts / glints / wisps;
-- beyond: the line, the X marks, the sounds. A part governor keeps this cast's folder (its afterimages live in it)
-- under Budget; the emitter budget (~30) is kept by pooling the repeated small bursts (ticks, glints, lean bodies,
-- embers) on one queued emitter each. Everything is gone by ~3 s after the cut (the folder at 8 s); the Heartbeat
-- loops (the silent-beat pulse, ended at the cut; the pump, connected only while it has work) never outlive the cast.
-- Local-caster-only layers (callout, root, mover, camera, hush, money shot, tally) check caster == ctx.player.
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

-- (2026-11-08) "remove the extra character animation on ichigo's shunpo": no posed copies of Ichigo any more - neither
-- the LAUNCH afterimage left where he departs nor the chain of slash-pose afterimages along the path (with their
-- hanging cut lines). The rest of the move (the main cut line, rings, the money frame, the cut, his own chiburi
-- flourish) is unchanged. true brings the copies back.
local AFTERIMAGES = false -- (2026-11-10) the owner asked to remove the extra character copies (afterimages) on Shunpo

return function(ctx)
	local H = {}

	local FX, S, CFG = ctx.FX, ctx.S, ctx.CFG
	local PAL = ctx.PAL or CFG.Palette or {}
	local SC = CFG.Shunpo or {}
	local SM = (type(CFG.Mode) == "table" and type(CFG.Mode.Shunpo) == "table") and CFG.Mode.Shunpo or {}
	local SW = type(CFG.Sword) == "table" and CFG.Sword or {}
	local UP = ctx.UP or Vector3.yAxis
	local FLAT = ctx.FLAT or Vector3.new(1, 0, 1)
	local WHITE = ctx.WHITE or Color3.new(1, 1, 1)
	local TAU = ctx.TAU or math.pi * 2
	local rng = Random.new()
	local C3 = Color3.fromRGB
	local CORE = PAL.Core or C3(240, 250, 255)
	local REIATSU = PAL.Reiatsu or C3(150, 215, 255)
	local ICE = PAL.Ice or C3(80, 160, 255)
	local FROST = PAL.Frost or C3(205, 235, 255)
	local BLACK = PAL.Black or C3(14, 10, 14)
	local CRIMSON = PAL.Crimson or C3(220, 20, 40)
	local EMBER = PAL.Ember or C3(255, 90, 60)
	local BLOOD = PAL.Blood or C3(110, 0, 18)
	local QUAD, SINE = Enum.EasingStyle.Quad, Enum.EasingStyle.Sine
	local OUT, IN = Enum.EasingDirection.Out, Enum.EasingDirection.In

	local function num(k, d, mode)
		local v = mode and SM[k]
		if type(v) == "number" then
			return v
		end
		v = SC[k]
		return type(v) == "number" and v or d
	end
	local ROOT_END = num("RootEnd", 1.66)
	local HANDOFF = num("HandoffAt", 1.52)
	local HITSTOP = num("ClientHitStop", 0.05)
	local GHOST_ALPHA, GHOST_LIFE = num("GhostAlpha", 0.42), num("GhostLife", 0.8)
	local GHOST_YAW = math.rad(num("GhostYaw", 32))
	local GLINT_EVERY = num("GlintEvery", 8)
	local FULL_BODIES, WISP_BODIES = num("FullBodies", 3), num("WispBodies", 4)
	local NEAR, MID = num("NearDist", 160), num("MidDist", 250)
	local BUDGET = num("Budget", 380)
	local HUSH_SAT = num("HushSat", -0.55)
	local GRIP_Y = type(SW.HandleGripY) == "number" and SW.HandleGripY or -0.30
	local NEAR_CAM = 30 -- a cut body closer than this to the camera counts towards the point-blank bloom limit (2)

	local casts = {} -- "userId#id" -> live cast state (ids are per-player counters)
	local function keyOf(d)
		return tostring(d.userId) .. "#" .. tostring(d.id)
	end

	---------------------------------------------------------------------------------------------------
	-- helpers

	local warned = {}
	local function warnOnce(key, msg)
		if not warned[key] then
			warned[key] = true
			warn("[Zangetsu.Shunpo] " .. msg)
		end
	end

	-- a Shared builder, guarded: one missing or failing builder never takes a beat down with it
	local function S_(name, ...)
		local fn = S and S[name]
		if type(fn) ~= "function" then
			warnOnce(name, "Shared." .. name .. " is missing")
			return nil
		end
		local ok, r = pcall(fn, ...)
		if not ok then
			warnOnce(name .. "!", "Shared." .. name .. " failed: " .. tostring(r))
			return nil
		end
		return r
	end
	-- a GojoFX primitive, guarded the same way
	local function FX_(name, ...)
		local fn = FX and FX[name]
		if type(fn) ~= "function" then
			warnOnce("FX." .. name, "GojoFX." .. name .. " is missing")
			return nil
		end
		local ok, r = pcall(fn, ...)
		if not ok then
			warnOnce("FX." .. name .. "!", "GojoFX." .. name .. " failed: " .. tostring(r))
			return nil
		end
		return r
	end
	local function call(obj, method, ...)
		if type(obj) == "table" or typeof(obj) == "Instance" then
			local fn = obj[method]
			if type(fn) == "function" then
				local ok, err = pcall(fn, obj, ...)
				if not ok then
					warnOnce("m." .. method, method .. " failed: " .. tostring(err))
				end
				return ok
			end
		end
		return false
	end
	local function kill(h)
		if h == nil then
			return
		end
		if typeof(h) == "Instance" then
			pcall(function()
				h:Destroy()
			end)
		elseif type(h) == "table" then
			if not call(h, "Destroy") then
				call(h, "destroy")
			end
		end
	end

	-- §11 glow-size rule (no white-outs): through Shared's glowFor, or the same formula
	local function glowFor(pos, size)
		if S and type(S.glowFor) == "function" then
			local ok, v = pcall(S.glowFor, pos, size)
			if ok and type(v) == "number" then
				return v
			end
		end
		return size * math.clamp(ctx.camDist(pos) / 30, 0.45, 1)
	end
	-- camera-facing rings shrink near the lens
	local function ringK(pos)
		return math.clamp(ctx.camDist(pos) / 30, 0.6, 1)
	end
	local function camFacing(pos)
		local ok, v = pcall(ctx.camFacing, pos)
		if ok and typeof(v) == "Vector3" and v.Magnitude > 0.5 then
			return v.Unit
		end
		local cam = workspace.CurrentCamera
		return cam and (cam.CFrame.Position - pos).Unit or UP
	end

	local function sndOn(key, parent, vol, pitch)
		if parent and typeof(parent) == "Instance" and parent.Parent then
			local ok, s = pcall(ctx.sound, key, parent, vol, pitch)
			return ok and s or nil
		end
	end

	local function torsoOf(m)
		if typeof(m) ~= "Instance" or not m.Parent then
			return nil
		end
		return m:FindFirstChild("UpperTorso") or m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Torso")
	end

	local function feetUnder(pos)
		local ok, y = pcall(ctx.groundY, pos)
		if ok and type(y) == "number" and pos.Y - y < 12 then
			return Vector3.new(pos.X, y + 0.1, pos.Z)
		end
		return pos - UP * 3.1
	end

	local function swordInfo(char)
		local ok, info = pcall(ctx.sword, char)
		return ok and info or nil
	end
	local function swordPoints(char)
		local info = swordInfo(char)
		if info and info.tip and info.base and info.tip.Parent then
			return info.base.WorldPosition, info.tip.WorldPosition, info
		end
		local hand = char and char:FindFirstChild("RightHand")
		if hand then
			return hand.Position, hand.Position + hand.CFrame.UpVector * -4, info
		end
		return nil
	end
	local function formOf(char)
		local ok, f = pcall(ctx.form, char)
		return ok and f or nil
	end

	-- parts this cast owns right now: its folder (the path afterimages live in it) + the start afterimages (kit folder)
	local function partsIn(inst)
		local n = 0
		if typeof(inst) == "Instance" and inst.Parent then
			for _, d in ipairs(inst:GetDescendants()) do
				if d:IsA("BasePart") then
					n += 1
				end
			end
		end
		return n
	end
	local function partsOf(c)
		local n = 0
		if S and type(S.partCount) == "function" then
			local ok, v = pcall(S.partCount, c.f)
			n = ok and type(v) == "number" and v or partsIn(c.f)
		else
			n = partsIn(c.f)
		end
		for g, cnt in pairs(c.ghosts) do
			if g.Parent then
				n += cnt
			else
				c.ghosts[g] = nil
			end
		end
		return n
	end
	local function room(c, extra)
		return partsOf(c) + (extra or 0) < BUDGET
	end
	local function track(c, g)
		if typeof(g) == "Instance" then
			c.ghosts[g] = partsIn(g)
		end
	end

	-- schedule a beat at cast time t (seconds after t0); skipped once the cast is dead
	local function at(c, t, fn)
		local delay = t - (ctx.now() - c.t0)
		task.delay(math.max(delay, 0), function()
			if c.dead then
				return
			end
			local ok, err = pcall(fn)
			if not ok then
				warnOnce("beat" .. tostring(t), "beat " .. tostring(t) .. ": " .. tostring(err))
			end
		end)
	end
	-- a nested timer: counts from NOW (inside a beat), not from the cast
	local function after(c, secs, fn)
		task.delay(math.max(secs, 0), function()
			if c.dead then
				return
			end
			local ok, err = pcall(fn)
			if not ok then
				warnOnce("after", "nested beat: " .. tostring(err))
			end
		end)
	end

	---------------------------------------------------------------------------------------------------
	-- POSED AFTERIMAGES: a copy of the character in any clip pose (the chain of different cuts along the path).
	-- Every limb's world CFrame is solved from the character's own joints (Motor6D: Part0 * C0 * T * C1^-1;
	-- AnimationConstraint: Part0 * A0 * T * A1^-1) with T = the pose's joint value (ProceduralAnimator's angles), the
	-- blade from the SwordGrip motor; every other visible part (hair, hats, sword pieces, the Bankai coat) keeps its
	-- current offset from the limb it is joined to. The look is Shared.ghost's (ForceField / the dark copy).
	local JORDER = { "Root", "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow",
		"LeftWrist", "RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle" }
	local JSET = {}
	for _, n in ipairs(JORDER) do
		JSET[n] = true
	end
	JSET.SwordGrip = true
	local function poseCF(v)
		if typeof(v) == "CFrame" then
			return v
		end
		if type(v) ~= "table" then
			return CFrame.identity
		end
		local cf = CFrame.Angles(math.rad(v[1] or 0), math.rad(v[2] or 0), math.rad(v[3] or 0))
		if typeof(v.pos) == "Vector3" then
			cf = CFrame.new(v.pos) * cf
		end
		return cf
	end
	local function enabled(j)
		local ok, v = pcall(function()
			return j.Enabled
		end)
		return not ok or v ~= false
	end
	local rigs = setmetatable({}, { __mode = "k" })
	local function rigOf(char)
		local r = rigs[char]
		local form = char:GetAttribute("SwordForm")
		if r and os.clock() - r.at < 3 and r.hrp.Parent == char and r.form == form then
			return r
		end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return nil
		end
		local J = {}
		for _, d in ipairs(char:GetDescendants()) do
			if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and JSET[d.Name] then
				if not J[d.Name] or (enabled(d) and not enabled(J[d.Name])) then
					J[d.Name] = d
				end
			end
		end
		local vis = {}
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") and d ~= hrp and d.Transparency < 0.9 and d.Archivable then
				local s = d.Size
				if math.max(s.X, s.Y, s.Z) >= 0.3 then
					table.insert(vis, d)
				end
			end
		end
		-- the lighter copy for the Tensa Zangetsu chain: the Bankai coat keeps only its big panels (no linings, hems,
		-- collar or shoulder caps), which is what lets the denser chain fit the part budget
		local coat = char:FindFirstChild("ZangetsuCoat")
		local lite = {}
		for _, d in ipairs(vis) do
			local keep = true
			if coat and d:IsDescendantOf(coat) then
				local s = d.Size
				local a = math.max(s.X * s.Y, s.Y * s.Z, s.X * s.Z)
				keep = a >= 1.2 and not string.find(d.Name, "Lining")
			end
			if keep then
				table.insert(lite, d)
			end
		end
		local sword = char:FindFirstChild("ZangetsuSword")
		r = { hrp = hrp, J = J, vis = vis, lite = lite, own = {}, at = os.clock(), sword = sword, form = form }
		rigs[char] = r
		return r
	end
	-- the limb (or the sword Handle) a piece hangs off, and its offset from it: a Weld / Motor's C0 * C1^-1 (exact,
	-- even before physics has placed the piece) or, for a WeldConstraint / rigid constraint / no joint, the current one
	local function ownerOf(r, p, V, handle)
		local rec = r.own[p]
		if rec ~= nil then
			return rec or nil
		end
		local ok, joints = pcall(function()
			return p:GetJoints()
		end)
		for _, j in ipairs(ok and joints or {}) do
			local other, rel
			if j:IsA("JointInstance") then
				if j.Part0 == p then
					other, rel = j.Part1, j.C1 * j.C0:Inverse()
				else
					other, rel = j.Part0, j.C0 * j.C1:Inverse()
				end
			elseif j:IsA("WeldConstraint") then
				other = (j.Part0 == p) and j.Part1 or j.Part0
			elseif j:IsA("Constraint") then
				local p0 = j.Attachment0 and j.Attachment0.Parent
				local p1 = j.Attachment1 and j.Attachment1.Parent
				other = (p0 == p) and p1 or p0
			end
			if other and V[other] then
				rec = { o = other, rel = rel }
				break
			end
		end
		if not rec and handle and r.sword and p:IsDescendantOf(r.sword) then
			rec = { o = handle }
		end
		if not rec then
			local best, o = math.huge, nil
			for limb in pairs(V) do
				local dd = (limb.Position - p.Position).Magnitude
				if dd < best then
					best, o = dd, limb
				end
			end
			rec = o and { o = o } or nil
		end
		r.own[p] = rec or false
		return rec
	end
	-- -> folder (in c.f), blade = { grip, tip, dir, edge, len } or nil
	local function ghostPosed(c, char, rootCF, pose, color, alpha, life, black, lite)
		local r = rigOf(char)
		if not r then
			return nil
		end
		local hrp = r.hrp
		local V = { [hrp] = rootCF }
		local rel = rootCF * hrp.CFrame:Inverse()
		local function vOf(p)
			return V[p] or (rel * p.CFrame)
		end
		for _, name in ipairs(JORDER) do
			local j = r.J[name]
			if j and j.Parent then
				local T = poseCF(pose[name])
				if j:IsA("Motor6D") then
					if j.Part0 and j.Part1 then
						V[j.Part1] = vOf(j.Part0) * j.C0 * T * j.C1:Inverse()
					end
				else
					local a0, a1 = j.Attachment0, j.Attachment1
					if a0 and a1 and a0.Parent and a1.Parent and a0.Parent:IsA("BasePart") and a1.Parent:IsA("BasePart") then
						V[a1.Parent] = vOf(a0.Parent) * a0.CFrame * T * a1.CFrame:Inverse()
					end
				end
			end
		end
		local g = r.J.SwordGrip
		local handle
		if g and g:IsA("Motor6D") and g.Part0 and g.Part1 then
			handle = g.Part1
			V[handle] = vOf(g.Part0) * g.C0 * poseCF(pose.SwordGrip) * g.C1:Inverse()
		end
		local folder = Instance.new("Folder")
		folder.Name = "ShunpoAfterimage"
		local parts = {}
		for _, d in ipairs(lite and r.lite or r.vis) do
			if d.Parent and d.Transparency < 0.9 then
				local cf = V[d]
				if not cf then
					local own = ownerOf(r, d, V, handle)
					if own then
						cf = vOf(own.o) * (own.rel or own.o.CFrame:ToObjectSpace(d.CFrame))
					else
						cf = rel * d.CFrame
					end
				end
				local ok, cl = pcall(function()
					return d:Clone()
				end)
				if ok and cl then
					for _, ch in ipairs(cl:GetChildren()) do
						if not ch:IsA("DataModelMesh") then
							ch:Destroy()
						end
					end
					cl.Anchored = true
					cl.CanCollide = false
					cl.CanQuery = false
					cl.CanTouch = false
					cl.CastShadow = false
					cl.Massless = true
					cl.LocalTransparencyModifier = 0
					if black then
						if d.Name == "Edge" then
							cl.Material = Enum.Material.Neon
							cl.Color = color
							cl.Transparency = math.min(alpha * 0.6, 0.9)
						else
							cl.Material = Enum.Material.SmoothPlastic
							cl.Color = BLACK
							cl.Reflectance = 0
							cl.Transparency = alpha
							pcall(function()
								if cl:IsA("MeshPart") then
									cl.TextureID = ""
								end
								local mesh = cl:FindFirstChildWhichIsA("SpecialMesh")
								if mesh then
									mesh.TextureId = ""
									mesh.VertexColor = Vector3.new(0.06, 0.04, 0.06)
								end
							end)
						end
					else
						cl.Material = Enum.Material.ForceField
						cl.Color = color
						cl.Transparency = alpha
					end
					cl.CFrame = cf
					cl.Parent = folder
					table.insert(parts, cl)
				end
			end
		end
		if #parts == 0 then
			folder:Destroy()
			return nil
		end
		folder.Parent = c.f
		local info = TweenInfo.new(life, QUAD, IN)
		for _, p in ipairs(parts) do
			TweenService:Create(p, info, { Transparency = 1 }):Play()
		end
		Debris:AddItem(folder, life + 0.1)
		local blade
		if handle and V[handle] then
			local hcf = V[handle]
			local form = formOf(char) == "Bankai" and "Bankai" or "Shikai"
			local tipS = type(SW[form]) == "table" and SW[form].Tip or (form == "Bankai" and 4.34 or 4.95)
			local grip = (hcf * CFrame.new(0, GRIP_Y, 0)).Position -- the grip point (s = 0); s along the blade: s + GRIP_Y
			local tip = (hcf * CFrame.new(0, tipS + GRIP_Y, 0)).Position
			local dir = tip - grip
			if dir.Magnitude > 0.5 then
				blade = { grip = grip, tip = tip, dir = dir.Unit, edge = hcf:VectorToWorldSpace(Vector3.zAxis), len = dir.Magnitude }
			end
		end
		return folder, blade
	end

	-- how many visible parts an afterimage of this character clones (for the governor)
	local function ghostSize(char, lite)
		local r = char and rigOf(char)
		return math.max(r and #(lite and r.lite or r.vis) or 0, 15)
	end

	---------------------------------------------------------------------------------------------------
	-- the PUMP (the emitter budget): pooled one-emitter hosts per cast (ticks, glints, lean bursts, embers), each fired
	-- at most ONCE per frame from a queue (one moved emitter fired twice in a frame clumps its puffs at the last spot),
	-- plus the wisp emitters riding the cut bodies. One Heartbeat loop per cast, connected only while it has work.
	local function poolProps(c, key)
		local m = c.mode
		if key == "tick" then
			return { Texture = FX.TEX.star, Color = FX.cs(m and CRIMSON or FROST, WHITE), Lifetime = NumberRange.new(0.18, 0.35),
				Speed = NumberRange.new(8, 22), SpreadAngle = Vector2.new(180, 180), Size = FX.nsk({ { 0, 0.4 }, { 1, 0 } }),
				Transparency = FX.nsk({ { 0, 0 }, { 0.8, 0.2 }, { 1, 1 } }), Drag = 3, Acceleration = Vector3.new(0, -30, 0),
				Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-300, 300), Brightness = 2 }
		elseif key == "glint" then
			return { Texture = FX.TEX.star, Color = FX.cs(WHITE, m and CRIMSON or FROST), Lifetime = NumberRange.new(0.25, 0.55),
				Speed = NumberRange.new(0.5, 3), SpreadAngle = Vector2.new(180, 180),
				Size = FX.nsk({ { 0, 0.2 }, { 0.15, 0.85 }, { 1, 0 } }), Transparency = FX.nsk({ { 0, 0 }, { 0.6, 0.25 }, { 1, 1 } }),
				Drag = 2, Acceleration = Vector3.new(0, -2, 0), Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-120, 120), Brightness = 2.2 }
		elseif key == "lean" then
			return { Texture = FX.TEX.star, Color = FX.cs(m and CRIMSON or CORE, m and EMBER or FROST), Lifetime = NumberRange.new(0.22, 0.45),
				Speed = NumberRange.new(25, 55), SpreadAngle = Vector2.new(50, 50), Size = FX.nsk({ { 0, 0.45 }, { 1, 0 } }),
				Transparency = FX.nsk({ { 0, 0 }, { 0.8, 0.2 }, { 1, 1 } }), Drag = 3, Acceleration = Vector3.new(0, -30, 0),
				Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-300, 300), Brightness = 2 }
		end
		return { Texture = FX.TEX.star, Color = FX.cs(m and EMBER or FROST, m and CRIMSON or REIATSU), Lifetime = NumberRange.new(0.5, 1.0),
			Speed = NumberRange.new(1, 4), SpreadAngle = Vector2.new(180, 180), Size = FX.nsk({ { 0, 0.35 }, { 1, 0 } }),
			Transparency = FX.nsk({ { 0, 0.1 }, { 0.7, 0.3 }, { 1, 1 } }), Drag = 1, Acceleration = Vector3.new(0, 3, 0),
			Rotation = NumberRange.new(0, 360), Brightness = 1.8 }
	end
	local function pooled(c, key)
		c.pool = c.pool or {}
		local p = c.pool[key]
		if p and p.host.Parent then
			return p
		end
		local host = FX.part("ShunpoPump", Enum.PartType.Block, Enum.Material.SmoothPlastic, WHITE, nil)
		host.Transparency = 1
		host.Size = Vector3.one * 0.2
		host.CFrame = CFrame.new(c.to or c.from or Vector3.zero)
		host.Parent = c.f
		local a = Instance.new("Attachment")
		a.Parent = host
		local props = poolProps(c, key)
		props.EmissionDirection = Enum.NormalId.Top
		p = { host = host, a = a, e = FX.emitter(a, props), q = {} }
		c.pool[key] = p
		return p
	end
	local function ensurePump(c)
		if c.pumpConn or c.dead then
			return
		end
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local busy = false
			if not c.dead then
				for _, p in pairs(c.pool or {}) do
					local job = table.remove(p.q, 1)
					if job and p.e.Parent then
						p.host.CFrame = CFrame.new(job.pos)
						p.a.CFrame = job.dir and FX.yAlong(job.dir) or CFrame.identity
						p.e:Emit(job.n)
					end
					if #p.q > 0 then
						busy = true
					end
				end
				local clock = os.clock()
				local ws = c.wisps or {}
				for i = #ws, 1, -1 do
					local w = ws[i]
					local tt = torsoOf(w.m)
					if clock > w.untilT or not tt or not w.e.Parent then
						if w.e.Parent then
							w.e.Rate = 0
						end
						Debris:AddItem(w.host, 0.8)
						table.remove(ws, i)
					else
						w.host.CFrame = CFrame.new(tt.Position)
						busy = true
					end
				end
			end
			if c.dead or not busy then
				conn:Disconnect()
				if c.pumpConn == conn then
					c.pumpConn = nil
				end
			end
		end)
		c.pumpConn = conn
	end
	local function puff(c, key, pos, dir, n)
		if typeof(pos) ~= "Vector3" or c.dead then
			return
		end
		local p = pooled(c, key)
		table.insert(p.q, { pos = pos, dir = dir, n = n })
		ensurePump(c)
	end
	local function retire(c, key)
		local p = c.pool and c.pool[key]
		if p then
			kill(p.host)
			c.pool[key] = nil
		end
	end
	-- reiatsu wisps rising off a cut body for `secs` (one emitter that rides its torso)
	local function wisp(c, m, secs)
		local tt = torsoOf(m)
		if not tt or c.dead then
			return
		end
		local host = FX.part("ShunpoWisp", Enum.PartType.Block, Enum.Material.SmoothPlastic, WHITE, nil)
		host.Transparency = 1
		host.Size = Vector3.one * 0.6
		host.CFrame = CFrame.new(tt.Position)
		host.Parent = c.f
		local e = FX.emitter(host, {
			Texture = (S and S.TEX and S.TEX.fire) or FX.TEX.glow, Color = FX.cs(c.mode and CRIMSON or FROST, c.mode and EMBER or REIATSU),
			Lifetime = NumberRange.new(0.4, 0.7), Speed = NumberRange.new(2, 4), EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(25, 25), Acceleration = Vector3.new(0, 5, 0), Size = FX.nsk({ { 0, 0.6 }, { 1, 0 } }),
			Transparency = FX.nsk({ { 0, 0.4 }, { 1, 1 } }), Rotation = NumberRange.new(0, 360), Brightness = 1.6, Rate = 0,
		})
		e.Rate = 14
		c.wisps = c.wisps or {}
		table.insert(c.wisps, { m = m, host = host, e = e, untilT = os.clock() + secs })
		ensurePump(c)
	end

	---------------------------------------------------------------------------------------------------
	-- layers

	-- the hanging glints along the path: ONE emitter on a thin invisible host spanning the line (no per-glint hosts)
	local function glintHost(c, a, b)
		local len = (b - a).Magnitude
		if len < 2 then
			return nil
		end
		local host = FX.part("ShunpoGlints", Enum.PartType.Block, Enum.Material.SmoothPlastic, WHITE, nil)
		host.Transparency = 1
		host.Size = Vector3.new(0.6, 0.6, len)
		host.CFrame = CFrame.lookAt((a + b) / 2, b)
		host.Parent = c.f
		local e = FX.emitter(host, {
			Texture = FX.TEX.star, Color = FX.cs(c.mode and CRIMSON or FROST, c.mode and EMBER or WHITE),
			Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(0, 0.4), SpreadAngle = Vector2.new(180, 180),
			Size = FX.nsk({ { 0, 0.5 }, { 0.5, 0.4 }, { 1, 0 } }),
			Transparency = FX.nsk({ { 0, 0.3 }, { 0.6, 0.45 }, { 1, 1 } }),
			Acceleration = Vector3.new(0, -1.2, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90),
			Brightness = 1.6, Rate = 0,
		})
		e.Rate = math.clamp(len / GLINT_EVERY, 1, 8) * 2.4
		return { host = host, e = e, n = math.clamp(math.floor(len / GLINT_EVERY), 1, 8) }
	end

	-- a line style: Shikai white core + frost edge; Tensa black core + crimson edge
	local function lineStyle(mode, width)
		if mode then
			return { width = width, core = BLACK, edge = CRIMSON, black = true }
		end
		return { width = width, core = WHITE, edge = FROST }
	end

	-- the cut line a path afterimage leaves: the chord of its swing, from where its blade was 105 deg back along the
	-- swing (the edge leads, so the blade came from the -edge side) to just past where the tip stopped
	local function chordOf(blade)
		local d = blade.dir
		local e = blade.edge - d * blade.edge:Dot(d)
		if e.Magnitude < 0.2 then
			e = d:Cross(UP)
			if e.Magnitude < 0.2 then
				e = d:Cross(Vector3.xAxis)
			end
		end
		e = e.Unit
		local R = blade.len * 0.95
		local th = math.rad(105)
		local p0 = blade.grip + (d * math.cos(th) - e * math.sin(th)) * R
		local p1 = blade.grip + d * R * 1.12
		return p0, p1, d, e
	end

	-- the flash-step burst at a body's feet (departure / arrival): staggered rings in three planes
	local function burstRings(c, feet, chest, big)
		local f = c.f
		local col = c.mode and CRIMSON or FROST
		FX_("ring", f, feet + UP * 0.15, UP, 1, big and 12 or 7, col, 0.32, { alpha = 0.22 })
		after(c, 0.04, function()
			if c.len > 2 or not big then
				local p = chest + c.face * 1.5
				FX_("ring", f, p, c.face, 1, (big and 6.5 or 4.5) * ringK(p), col, 0.24, { alpha = 0.45 })
			end
		end)
		after(c, 0.08, function()
			if big then
				FX_("ring", f, feet + UP * 0.25, UP, 0.6, 6, c.mode and EMBER or CORE, 0.22, { alpha = 0.3 })
			end
			if big and c.tier >= 3 then
				local side = c.face:Cross(UP)
				FX_("ring", f, chest, side, 1, 5 * ringK(chest), col, 0.2, { alpha = 0.5 })
			end
		end)
	end

	-- one body's cut burst. full = the whole layer stack; bloom = full-size glows (point-blank limit); rank = 1.. by
	-- camera distance
	local function cutBurst(c, m, pos, dir, full, bloom, mode, rank)
		local f = c.f
		local cam = workspace.CurrentCamera
		local R = cam and cam.CFrame.RightVector or Vector3.xAxis
		local U = cam and cam.CFrame.UpVector or UP
		local spin = rng:NextNumber(-0.26, 0.26)
		local r1 = (R * math.cos(spin) + U * math.sin(spin))
		local u1 = (U * math.cos(spin) - R * math.sin(spin))
		local d1, d2 = (r1 + u1 * 1.15).Unit * 3.2, (r1 - u1 * 1.15).Unit * 3.2
		local lo = lineStyle(mode, 0.2)
		lo.draw, lo.hold, lo.life = 0.03, 0.42, 0.7
		local x1 = S_("slashLine", f, pos + d1, pos - d1, lo)
		local lo2 = lineStyle(mode, 0.2)
		lo2.draw, lo2.hold, lo2.life = 0.03, 0.38, 0.7
		after(c, 0.035, function()
			S_("slashLine", f, pos - d2, pos + d2, lo2)
		end)
		local k = bloom and 1 or 0.5
		if full then
			FX_("glow", f, pos, glowFor(pos, 5) * k, mode and CRIMSON or CORE, 0.16, { brightness = 2.2 })
			if rank == 1 then
				FX_("glow", f, pos, glowFor(pos, 2.4) * k, mode and EMBER or WHITE, 0.08, { brightness = 2.6 })
			end
			if rank <= 2 and not mode then -- Tensa: wave 2 rings the first body
				FX_("ring", f, pos, camFacing(pos), 1, 8 * ringK(pos) * k, FROST, 0.35, { alpha = 0.22 })
			end
			if rank <= 2 then
				FX_("ring", f, feetUnder(pos) + UP * 0.2, UP, 1, 7, mode and CRIMSON or REIATSU, 0.4, { alpha = 0.3 })
			end
			if rank == 1 then
				local side = (c.face or Vector3.new(0, 0, -1)):Cross(UP)
				after(c, 0.05, function()
					FX_("ring", f, pos, side, 1, 6 * ringK(pos), mode and EMBER or FROST, 0.28, { alpha = 0.45 })
				end)
			end
			if rank <= 2 then
				FX_("light", f, pos, mode and CRIMSON or FROST, 6, 16, 0.3)
			end
			puff(c, "lean", pos, dir, 18)
			if not mode and rank <= 2 then -- Tensa Zangetsu's black flame bursts come with wave 2 (0.12 s later)
				S_("reiatsuFlame", f, pos, { color = CORE, color2 = REIATSU, count = 8, height = 3.5, size = 1.1, life = 0.55 })
			end
			if rank <= 2 then
				S_("bodyArc", f, m, mode and CRIMSON or REIATSU, 0.07)
				after(c, 0.15, function()
					S_("bodyArc", f, m, mode and EMBER or FROST, 0.06)
				end)
			end
			local tt = torsoOf(m)
			if tt then
				local tr = FX_("trail", tt, mode and CRIMSON or FROST, 1.2, 0.3, { alpha = 0.2 })
				if tr then
					local a0, a1 = tr.Attachment0, tr.Attachment1
					Debris:AddItem(tr, 0.6)
					if a0 then
						Debris:AddItem(a0, 0.6)
					end
					if a1 then
						Debris:AddItem(a1, 0.6)
					end
				end
			end
		elseif c.tier >= 2 then
			puff(c, "lean", pos, dir, 10)
		end
		return x1
	end

	-- the caster's silent beat: the screen drains of colour at the edges (a ColorCorrection + a cold edge vignette)
	local function hushOn(c)
		local cam = workspace.CurrentCamera
		if not cam or c.cc then
			return
		end
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "ZangetsuShunpoHush"
		cc.Parent = cam
		c.cc = cc
		TweenService:Create(cc, TweenInfo.new(0.2, QUAD, OUT), {
			Saturation = HUSH_SAT, Contrast = 0.08, Brightness = -0.02,
			TintColor = c.mode and C3(255, 222, 222) or C3(224, 236, 255),
		}):Play()
		Debris:AddItem(cc, 3)
		-- the edge pulse decays, so a second, weaker one keeps the edges dark through the back half of the beat
		local vcol = c.mode and BLOOD or C3(70, 90, 120)
		pcall(ctx.vignette, 0.3, math.max(c.C - c.A, 0.3) * 0.7, vcol)
		after(c, math.max(c.C - c.A, 0.3) * 0.45, function()
			if c.cc then
				pcall(ctx.vignette, 0.24, math.max(c.C - c.A, 0.3) * 0.6, vcol)
			end
		end)
	end
	-- the cut: colour snaps back with a pop, then settles
	local function hushOff(c, pop)
		local cc = c.cc
		c.cc = nil
		if not cc or not cc.Parent then
			return
		end
		if pop then
			cc.Saturation = 0.3
			cc.Contrast = 0.12
			cc.Brightness = 0.02
			cc.TintColor = WHITE
			TweenService:Create(cc, TweenInfo.new(0.35, QUAD, OUT), { Saturation = 0, Contrast = 0, Brightness = 0 }):Play()
			Debris:AddItem(cc, 0.4)
		else
			cc:Destroy()
		end
	end

	-- the caster's MONEY FRAME: for the silent beat the camera cuts round in front of him (low, off one shoulder - the
	-- left unless a wall is there) looking back past him down the path: his back to the frozen bodies, the chain of
	-- afterimages and the hanging cut lines behind him. It drifts in slowly, takes the cut with a jolt and an FOV kick,
	-- and hands back C + 0.3 (0.94 s; ctx.shot caps a shot at 1.2). Skipped when both sides are walled or the dash was
	-- too short to have a chain (Config Shunpo.Shot = false turns it off)
	local function moneyShot(c, char)
		if SC.Shot == false or not c.isLocal or c.len < 4 or not char then
			return
		end
		local face, to = c.face, c.to
		local side = face:Cross(UP)
		local eye = to + UP * 1.5
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ignore = { char }
		for _, n in ipairs({ "NPCs", "LocalFX", "FX", "KitFX" }) do
			local x = workspace:FindFirstChild(n)
			if x then
				table.insert(ignore, x)
			end
		end
		params.FilterDescendantsInstances = ignore
		local pick
		for _, sgn in ipairs({ -1, 1 }) do
			local want = to + face * 8.6 + side * (7 * sgn) + UP * 2.2
			if not workspace:Raycast(eye, want - eye, params) then
				pick = sgn
				break
			end
		end
		if not pick then
			return
		end
		local look = to - face * math.clamp(c.len * 0.27, 4, 9) - side * (0.5 * pick) + UP * 0.4
		local cutE = c.C - c.A - 0.02
		local dur = math.min(cutE + 0.3, 1.15)
		c.shotUntil = os.clock() + dur
		pcall(ctx.shot, {
			char = char, t0 = c.t0 + c.A + 0.02, dur = dur, face = face, base = CFrame.lookAt(to, to + face),
			cuts = { 0.01 }, cutColor = c.mode and CRIMSON or FROST,
			path = function(e)
				local k = math.clamp(e / math.max(cutE, 0.1), 0, 1)
				local s = k * k * (3 - 2 * k)
				local pos = to + face * (8.6 - 1.4 * s) + side * (7 * pick * (1 - 0.1 * s)) + UP * (2.2 + 0.3 * s)
				local fov = 58 - 4 * s
				if e > cutE then
					local j = math.clamp((e - cutE) / 0.25, 0, 1)
					local amp = 0.35 * (1 - j)
					pos += Vector3.new(math.noise(e * 40, 1.3), math.noise(2.1, e * 40), math.noise(e * 40, 5.7)) * amp
					fov = 54 + 8 * (1 - j) * (1 - j)
				end
				return pos, look, fov
			end,
		})
	end

	-- the arm-only chiburi flourish (the overhead twirl + the hand-back to the carry)
	-- (2026-11-10) OFF: the owner asked again to remove the extra character animation on Shunpo - the afterimages were
	-- already gone (AFTERIMAGES = false), so the extra animation is this post-cut sword twirl. true brings it back.
	local FLOURISH = false
	local function flourish(c)
		if c.flourished or not c.char then
			return
		end
		c.flourished = true
		if not FLOURISH then
			return
		end
		local char = c.char
		local name = c.bankaiClip and "ShunpoFlourishBankai" or "ShunpoFlourish"
		if not (ctx.Clips and ctx.Clips[name]) then
			return
		end
		pcall(ctx.playClip, char, name, 0)
		if c.tier >= 2 then
			after(c, 0.03, function()
				S_("bladeTrail", char, c.mode and BLACK or CORE, c.mode and CRIMSON or REIATSU, 0.12, 0.21, { black = c.mode, width = 0.6 })
			end)
		end
		after(c, 0.23, function()
			local _, tip = swordPoints(char)
			if tip and c.tier >= 2 then
				FX_("sparks", c.f, tip, { count = 1, size = 1.7, speed = { 0, 0.3 }, life = 0.3, drag = 0,
					accel = Vector3.zero, color = WHITE, color2 = c.mode and CRIMSON or FROST })
			end
			local hrp = char:FindFirstChild("HumanoidRootPart")
			sndOn("Zap", hrp, 0.22, 2.3)
		end)
		after(c, 0.44, function()
			sndOn("Hit", char:FindFirstChild("HumanoidRootPart"), 0.18, 1.7)
		end)
	end

	---------------------------------------------------------------------------------------------------
	-- ShunpoCast

	H.ShunpoCast = function(d)
		if type(d) ~= "table" or typeof(d.from) ~= "Vector3" or typeof(d.to) ~= "Vector3" then
			return
		end
		local D = tonumber(d.departAt) or 0.26
		local A = tonumber(d.arriveAt) or 0.46
		local CUT = tonumber(d.cutAt) or 1.12
		local t0 = tonumber(d.t0) or ctx.now()
		local e0 = ctx.now() - t0
		if e0 > CUT + 2 then
			return -- long past: nothing left worth drawing
		end
		local key = keyOf(d)
		local old = casts[key]
		if old then
			old.dead = true
		end
		local char, plr = ctx.charOf(d.userId)
		local isLocal = plr ~= nil and plr == ctx.player
		local mode = d.mode == true
		local from, to = d.from, d.to
		local face = ctx.flat(d.face or (to - from), Vector3.new(0, 0, -1))
		local path = (to - from) * FLAT
		local len = path.Magnitude
		local mid = (from + to) / 2
		local dist = isLocal and 0 or ctx.camDist(mid)
		local tier = (isLocal or dist <= NEAR) and 3 or (dist <= MID and 2 or 1)
		local f = ctx.castFolder("Shunpo", 8)
		local c = {
			key = key, t0 = t0, f = f, char = char, isLocal = isLocal, mode = mode, tier = tier, from = from, to = to,
			face = face, len = len, D = D, A = A, C = CUT, ghosts = {}, dead = false, cutDone = false, id = d.id,
			chords = {}, marks = {},
		}
		casts[key] = c
		task.delay(math.max(CUT + 3 - e0, 0.1), function()
			if casts[key] == c then
				casts[key] = nil
			end
		end)

		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local lineA, lineB = from + UP * 1.2, to + UP * 1.2
		local accent = mode and CRIMSON or FROST

		-- the clip (every client, from the server timeline)
		if char then
			local clipName = "Shunpo"
			local formB = formOf(char) == "Bankai"
			if (formB or mode) and ctx.Clips and ctx.Clips.ShunpoBankai then
				clipName = "ShunpoBankai"
				c.bankaiClip = true
			end
			local ok, tr = pcall(ctx.playClip, char, clipName, e0)
			c.track = ok and tr or nil
			-- the pose the start afterimage keeps: the clip's last key before the vanish (LAUNCH)
			local clip = ctx.Clips and ctx.Clips[clipName]
			if type(clip) == "table" and type(clip.keys) == "table" then
				local best
				for _, k in ipairs(clip.keys) do
					if type(k.t) == "number" and k.t <= D + 1e-3 and (not best or k.t > best.t) then
						best = k
					end
				end
				c.launchPose = best and best.pose
			end
		end

		-- 0.00 GATHER: the reiatsu converges into the blade and his body
		if e0 < D then
			if isLocal then
				-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (was callout "Shunpo")
				pcall(ctx.root, A + 0.05, face)
				pcall(ctx.lean, { fov = -3, attack = 0.2, hold = 0.04, release = 0.12 })
			end
			if hrp then
				sndOn("Zap", hrp, 0.4, 1.8)
				sndOn("Swell", hrp, 0.3, 1.7)
			end
			if char and tier >= 2 then
				-- Tensa Zangetsu: one black flame (each is 2 emitters) between the feet instead of one per foot
				for _, foot in ipairs(mode and { "LowerTorso" } or { "LeftFoot", "RightFoot" }) do
					local fp = char:FindFirstChild(foot)
					if fp and mode and hrp then
						S_("reiatsuFlame", f, feetUnder(hrp.Position) + UP * 0.2, { black = true, color = BLACK, color2 = CRIMSON,
							count = 8, height = 2.6, size = 0.8, life = 0.5, spread = 30 })
					elseif fp then
						S_("reiatsuFlame", f, fp.Position, { color = CORE, color2 = REIATSU, count = 5, height = 2.4, size = 0.65, life = 0.5 })
					end
				end
			end
			at(c, 0.03, function()
				if tier >= 2 and hrp then
					FX_("ring", f, feetUnder(hrp.Position) + UP * 0.15, UP, 6, 1, accent, 0.2, { ease = "in", alpha = 0.4 })
				end
			end)
			at(c, 0.05, function()
				if tier >= 3 and hrp then
					S_("dustRing", f, feetUnder(hrp.Position), 5, 3, -16, { s0 = 1, s1 = 2.6, life = 0.4 })
				end
			end)
			at(c, 0.06, function()
				if tier >= 2 and char then
					local g = S_("bladeGlow", char, mode and { black = true, rate = 30 } or { color = CORE, color2 = REIATSU, rate = 34 })
					if g then
						c.glow = g
						call(g, "set", 0.35)
						after(c, 0.08, function()
							call(g, "set", 0.7)
						end)
						after(c, 0.14, function()
							call(g, "set", 1)
						end)
					end
				end
			end)
			at(c, 0.08, function()
				if tier >= 3 and char then
					local base, tip = swordPoints(char)
					if base then
						FX_("streaks", f, (base + tip) / 2, { inward = 3.5, count = 14, color = mode and CRIMSON or CORE,
							color2 = mode and EMBER or FROST, life = 0.2, size = 0.3 })
					end
				end
			end)
			at(c, 0.10, function()
				if isLocal then
					pcall(ctx.shake, 0.12, 0.14, 45, 0)
				end
			end)
			for _, t in ipairs({ 0.12, 0.20 }) do
				at(c, t, function()
					if tier >= 3 and char then
						S_("bodyArc", f, char, mode and CRIMSON or REIATSU, 0.06)
					end
				end)
			end
			at(c, 0.16, function()
				if tier >= 3 and char then
					local base, tip = swordPoints(char)
					if base then
						FX_("bolt", f, base, tip, { color = mode and CRIMSON or REIATSU, width = 0.06, jag = 0.3, segments = 5, life = 0.1 })
					end
					if hrp then
						S_("shards", f, feetUnder(hrp.Position) + UP * 0.3, { count = 5, color = C3(110, 104, 96), size = 0.22,
							speed = { 4, 9 }, life = 0.5, dir = UP })
					end
				end
			end)
			at(c, 0.21, function()
				if tier >= 2 and char then
					local _, tip = swordPoints(char)
					if tip then
						FX_("sparks", f, tip, { count = 1, size = 1.8, speed = { 0, 0.3 }, life = 0.22, drag = 0,
							accel = Vector3.zero, color = WHITE, color2 = accent })
					end
				end
				sndOn("Zap", hrp, 0.2, 2.4)
			end)
		end

		-- D VANISH: the flash-step burst + the sonic crack
		if e0 < A then
			at(c, D, function()
				local e = ctx.now() - t0
				if c.glow then
					kill(c.glow)
					c.glow = nil
				end
				if char and hrp then
					if AFTERIMAGES and tier >= 2 and e < D + 0.05 then
						-- the start afterimage: the LAUNCH pose left behind (a posed copy, so it is exact on every
						-- client and, in Tensa Zangetsu, as light as the chain)
						local okP, g = false, nil
						if c.launchPose then
							okP, g = pcall(ghostPosed, c, char, hrp.CFrame, c.launchPose, mode and CRIMSON or FROST,
								mode and 0.38 or 0.32, mode and 0.5 or 0.45, mode, mode)
						end
						if not (okP and g) then
							if mode then
								track(c, S_("ghostAt", char, hrp.CFrame, CRIMSON, 0.38, 0.5, { black = true }))
							else
								track(c, S_("ghost", char, FROST, 0.32, 0.45))
							end
						end
					end
					pcall(ctx.vanish, char, math.max(A - e + 0.02, 0.02))
				end
				local feet = feetUnder(from)
				local chest = from + UP * 1.2
				if tier >= 2 then
					burstRings(c, feet, chest, true)
					S_("dustRing", f, feet, 2, 3, 30, { s0 = 1.6, s1 = 5.5, life = 0.9 })
					FX_("glow", f, from + UP * 0.6, glowFor(from, 3.2), accent, 0.12, { brightness = 2.2 })
					FX_("light", f, from + UP * 1, accent, 5, 14, 0.18)
					FX_("sparks", f, from + UP * 0.6, { count = 10, color = mode and CRIMSON or WHITE, color2 = mode and EMBER or FROST,
						speed = { 10, 28 }, size = 0.4, life = 0.35 })
					FX_("streaks", f, chest, { count = 14, color = mode and CRIMSON or CORE, color2 = accent, speed = { 40, 80 },
						size = 0.35, life = 0.18 })
				end
				if tier >= 3 then
					S_("cracks", f, feet, 5, 2.6, mode and CRIMSON or REIATSU, 0.9, { width = 0.16, grow = 0.08 })
				end
				if hrp then
					sndOn("Thunder", hrp, 0.3, 2.3)
					sndOn("Crackle", hrp, 0.45, 1.5)
					sndOn("Whoosh", hrp, 0.9, 1.6)
					sndOn("Zap", hrp, 0.6, 1.4)
				end
				if isLocal then
					pcall(ctx.move, { t0 = t0 + D, dur = A - D, from = from, to = to, face = face, exitVel = face * 8 })
					FX_("speedLines", A - D + 0.08, { color = FROST, alpha = 0.5 })
					pcall(ctx.shake, 0.35, 0.18, 30, 7)
					if mode then
						pcall(ctx.flash, CRIMSON, 0.12, 0.22)
					end
				end
			end)
		end

		-- D -> A TRAVEL: the main cut line (drawn along with him, left hanging through the silent beat)
		if len >= 1 and e0 < CUT then
			at(c, D, function()
				local e = ctx.now() - t0
				local lo = lineStyle(mode, 0.18)
				lo.draw = math.max(A - e, 0)
				lo.hold = math.max(CUT - math.max(e, A), 0) + 0.05
				lo.life = 0.25
				c.line = S_("slashLine", f, lineA, lineB, lo)
			end)
		end

		-- the chain of afterimages (tier 3 only), each in a different slash pose, spread evenly along the path, as many
		-- as the part budget allows; each one leaves its cut line hanging in the air
		local poses = ctx.Clips and ctx.Clips.ShunpoAfterimages and ctx.Clips.ShunpoAfterimages.poses
		if AFTERIMAGES and tier >= 3 and char and len >= 3 and e0 < A then
			local gs = ghostSize(char, mode)
			local every, maxG = num("GhostEvery", 5, mode), num("MaxGhosts", 8, mode)
			local n = math.max(math.min(math.floor(len / every), maxG), 1)
			local fit = math.floor((BUDGET - 80 - gs) / (gs + 2))
			n = math.max(math.min(n, fit), 0)
			for k = 1, n do
				local frac = k / (n + 1)
				local p = from + (to - from) * frac
				at(c, D + frac * (A - D), function()
					if not room(c, gs + 8) then -- keep a little headroom for the arrival beat that follows
						return
					end
					local yaw = (k % 2 == 1 and 1 or -1) * GHOST_YAW * rng:NextNumber(0.75, 1.15)
					local cf = CFrame.lookAt(p, p + face) * CFrame.Angles(0, yaw, 0)
					local col = mode and CRIMSON or REIATSU:Lerp(FROST, (k - 1) / math.max(n - 1, 1))
					local black = mode and k % 2 == 1
					local pose = type(poses) == "table" and #poses > 0 and poses[(k - 1) % #poses + 1] or nil
					local g, blade
					if pose then
						local ok, a, b = pcall(ghostPosed, c, char, cf, pose, col, black and 0.4 or GHOST_ALPHA, GHOST_LIFE, black, mode)
						if ok then
							g, blade = a, b
						else
							warnOnce("ghostPosed", "posed afterimage: " .. tostring(a))
						end
					end
					if not g then -- no poses (an old Clips) or the rig would not solve: the current pose
						track(c, S_("ghostAt", char, cf, col, black and 0.45 or GHOST_ALPHA, GHOST_LIFE, { black = black }))
					end
					if blade and len >= 1 then
						local p0, p1 = chordOf(blade)
						local lo = lineStyle(mode, 0.11)
						local e = ctx.now() - t0
						lo.draw, lo.hold, lo.life = 0.05, math.max(CUT - e, 0) + 0.1, 0.2
						local ln = S_("slashLine", f, p0, p1, lo)
						if ln then
							call(ln, "setAlpha", 0.15)
							table.insert(c.chords, { line = ln, a = p0, b = p1 })
						end
						puff(c, "glint", p1, nil, 3)
						if k <= 2 then
							-- a quick flash of the swing itself: Shared's arc runs from its -X end through LookVector to
							-- its +X end, so with a half-sweep h the +X end is the blade (dd) and the -X end 2h back
							-- toward -edge (where the blade came from)
							local _, _, dd, ee = chordOf(blade)
							local h = math.rad(55)
							local m = (dd * math.cos(h) - ee * math.sin(h)).Unit
							local r = (dd * math.sin(h) + ee * math.cos(h)).Unit
							local upv = (-m):Cross(r)
							if upv.Magnitude > 0.1 then
								S_("slashArc", f, CFrame.fromMatrix(blade.grip, r, upv.Unit), blade.len * 0.9, {
									sweep = 110, width = 0.5, thick = 0.08, core = mode and BLACK or WHITE, edge = accent, draw = 0.04,
									life = 0.22, layers = 1, black = mode, glint = false, smear = false })
							end
						end
					end
				end)
			end
		end

		-- the ticks as he passes each body (no damage yet) + a faint mark across it, held until the cut
		if type(d.targets) == "table" and e0 < A + 0.1 then
			local segLen = (lineB - lineA).Magnitude
			for i, tg in ipairs(d.targets) do
				if type(tg) == "table" and i <= 12 then
					local frac = math.clamp((tonumber(tg.along) or 0) / math.max(segLen, 1e-3), 0, 1)
					at(c, D + frac * (A - D), function()
						local tt = torsoOf(tg.model)
						local pos = tt and tt.Position or tg.pos
						if typeof(pos) ~= "Vector3" then
							return
						end
						if tier >= 2 then
							puff(c, "tick", pos, nil, 6)
							if i == 1 then
								FX_("glow", f, pos, glowFor(pos, 2), accent, 0.14, { brightness = 1.6 })
							end
						end
						if tier >= 3 and i == 1 then
							FX_("ring", f, pos, camFacing(pos), 1, 3 * ringK(pos), accent, 0.2, { alpha = 0.5 })
						end
						if tier >= 2 and i <= 8 then
							local side = face:Cross(UP)
							local a0 = pos + side * 1.6 + UP * 1.1
							local b0 = pos - side * 1.6 - UP * 0.9
							local lo = lineStyle(mode, 0.07)
							local e = ctx.now() - t0
							lo.draw, lo.hold, lo.life = 0.04, math.max(CUT - e, 0) + 0.06, 0.12
							local mk = S_("slashLine", f, a0, b0, lo)
							if mk then
								call(mk, "setAlpha", 0.35)
								table.insert(c.marks, mk)
							end
						end
						if i <= 6 then
							sndOn("Hit2", tt or hrp, 0.3, 2.0)
						end
					end)
				end
			end
		end

		-- A ARRIVE
		if e0 < A + 0.3 then
			at(c, A, function()
				local e = ctx.now() - t0
				local feet = feetUnder(to)
				if tier >= 2 then
					S_("dustLine", f, feet, face, 3, 2, 8, { s0 = 1.5, s1 = 4.5, life = 0.9 }) -- slow: the money shot's lens is ahead
					burstRings(c, feet, to + UP * 1.2, false)
					FX_("glow", f, to + UP * 0.4, glowFor(to, 2.5), accent, 0.12, { brightness = 2 })
					FX_("sparks", f, feet + UP * 0.5, { dir = -face + UP * 0.3, spread = 35, count = 8, color = mode and EMBER or WHITE,
						color2 = accent, speed = { 12, 26 }, size = 0.35, life = 0.35 })
				end
				if tier >= 3 and char then
					after(c, 0.03, function()
						local _, tip = swordPoints(char)
						if tip then
							FX_("sparks", f, tip, { count = 1, size = 1.6, speed = { 0, 0.3 }, life = 0.35, drag = 0,
								accel = Vector3.zero, color = WHITE, color2 = accent })
						end
					end)
				end
				if hrp then
					sndOn("Shatter", hrp, 0.25, 2.2)
					sndOn("Whoosh", hrp, 0.35, 2.1)
				end
				-- the ticks are over: retire their pooled emitter (its sparks live 0.35 s)
				after(c, 0.5, function()
					retire(c, "tick")
				end)
				if isLocal and e < A + 0.2 then
					pcall(ctx.root, math.max(ROOT_END - e, 0.05), face)
					pcall(ctx.lean, { fov = -4, attack = 0.5, hold = 0.1, release = 0.2 })
				end
			end)
		elseif isLocal and e0 < ROOT_END then
			pcall(ctx.root, ROOT_END - e0, face)
		end

		-- A -> C THE SILENT BEAT
		if e0 < CUT then
			at(c, math.max(A, e0), function()
				local e = ctx.now() - t0
				if hrp then
					local dr = sndOn("Drone", hrp, 0.25, 1.6)
					if dr then
						c.drone = dr
						pcall(function()
							TweenService:Create(dr, TweenInfo.new(math.max(CUT - e, 0.1), SINE, IN), { Volume = 0 }):Play()
						end)
						Debris:AddItem(dr, math.max(CUT - e, 0.1) + 0.2)
					end
				end
				if tier >= 3 and len >= 2 then
					c.glints = glintHost(c, lineA, lineB)
				end
				if isLocal then
					after(c, 0.02, function()
						if not c.cutDone then
							hushOn(c)
							moneyShot(c, char)
						end
					end)
				end
				-- the pulse: every hanging line breathes (3 Hz) until the cut
				local conn
				conn = RunService.Heartbeat:Connect(function()
					local now = ctx.now() - t0
					if c.dead or c.cutDone or now >= CUT + 0.05 then
						conn:Disconnect()
						return
					end
					if now >= A then
						local w = math.sin(now * TAU * 3)
						if c.line then
							call(c.line, "setAlpha", 0.7 + 0.1 * w) -- lit transparency 0.6 <-> 0.8
						end
						for i, ch in ipairs(c.chords) do
							call(ch.line, "setAlpha", 0.32 + 0.14 * math.sin(now * TAU * 3 + i * 1.3))
						end
						for _, mk in ipairs(c.marks) do
							call(mk, "setAlpha", 0.55 + 0.15 * w)
						end
					end
				end)
				c.pulse = conn
			end)
			-- 1.02 the chiburi lift: a glint runs to the tip
			at(c, CUT - 0.1, function()
				if tier >= 3 and char and not c.cutDone then
					local base, tip = swordPoints(char)
					if tip then
						FX_("sparks", f, tip, { count = 1, size = 1.3, speed = { 0, 0.2 }, life = 0.25, drag = 0,
							accel = Vector3.zero, color = WHITE, color2 = accent })
						FX_("streaks", f, (base + tip) / 2, { dir = (tip - base).Unit, spread = 4, count = 3, color = WHITE,
							color2 = accent, speed = { 18, 26 }, size = 0.18, life = 0.12 })
					end
				end
			end)
		end

		-- the safety net: no ShunpoCut / ShunpoCancel by C + 0.6 (a dropped message) -> drop the lines quietly
		at(c, CUT + 0.6, function()
			if not c.cutDone then
				c.cutDone = true
				if c.isLocal and c.shotUntil and os.clock() < c.shotUntil then
					pcall(ctx.stopShot)
				end
				kill(c.line)
				c.line = nil
				for _, ch in ipairs(c.chords) do
					kill(ch.line)
				end
				c.chords = {}
				for _, mk in ipairs(c.marks) do
					kill(mk)
				end
				c.marks = {}
				if c.glints then
					kill(c.glints.host)
				end
				for _, p in pairs(c.pool or {}) do
					kill(p.host)
				end
				c.pool = nil
				hushOff(c, false)
				flourish(c)
			end
		end)
	end

	---------------------------------------------------------------------------------------------------
	-- ShunpoCut

	local function cutWave1(c, d)
		local mode = d.mode == true or c.mode
		local f = c.f
		local char = c.char
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local models = type(d.models) == "table" and d.models or {}
		local dirs = type(d.dirs) == "table" and d.dirs or {}
		local poses = type(d.poses) == "table" and d.poses or {}
		local accent = mode and CRIMSON or FROST
		c.cutDone = true
		if c.pulse then
			c.pulse:Disconnect()
			c.pulse = nil
		end
		if c.isLocal then
			hushOff(c, true)
		end

		-- the main line shatters into glints along the whole path; the hanging cut line nearest the camera shatters too,
		-- the rest burst into glints (one pooled emitter) and fade
		if c.line then
			if not call(c.line, "shatter") then
				kill(c.line)
			end
			c.line = nil
		end
		local ch = c.chords
		c.chords = {}
		table.sort(ch, function(a, b)
			return ctx.camDist((a.a + a.b) / 2) < ctx.camDist((b.a + b.b) / 2)
		end)
		for i, it in ipairs(ch) do
			if i == 1 and c.tier >= 3 then
				if not call(it.line, "shatter") then
					kill(it.line)
				end
			else
				call(it.line, "fade", 0.14)
				if c.tier >= 2 then
					puff(c, "glint", (it.a + it.b) / 2, nil, 4)
					puff(c, "glint", it.b, nil, 2)
				end
			end
		end
		for _, mk in ipairs(c.marks) do
			call(mk, "fade", 0.06)
		end
		c.marks = {}
		-- the hanging glints drift down and fade
		if c.glints and c.glints.e and c.glints.e.Parent then
			local g = c.glints
			g.e.Rate = 0
			g.e.Lifetime = NumberRange.new(1.0, 1.5)
			g.e.Acceleration = Vector3.new(0, -3, 0)
			g.e:Emit(g.n * 2)
			Debris:AddItem(g.host, 1.8)
		end

		-- the chiburi: a flick arc at his right side, reiatsu droplets thrown off the blade, one flung streak
		if char and c.tier >= 2 then
			local _, tip = swordPoints(char)
			local side = c.face:Cross(UP)
			if hrp then
				local sh = hrp.Position + UP * 1.4 + side * 1.2
				local bladeDir = (side * 0.9 - UP * 0.4).Unit
				S_("slashArc", f, CFrame.lookAt(sh, sh + bladeDir, c.face), 4.2, mode
					and { sweep = 80, width = 0.35, thick = 0.08, core = BLACK, edge = CRIMSON, draw = 0.04, life = 0.25, layers = 2, black = true }
					or { sweep = 80, width = 0.35, thick = 0.08, core = WHITE, edge = FROST, draw = 0.04, life = 0.25, layers = 2 })
			end
			if tip then
				local fling = (side - UP * 0.6).Unit
				FX_("sparks", f, tip, { dir = fling, spread = 25, count = 12, color = mode and CRIMSON or WHITE,
					color2 = mode and EMBER or FROST, speed = { 25, 45 }, size = 0.35, life = 0.5, accel = Vector3.new(0, -40, 0) })
				local lo = lineStyle(mode, 0.07)
				lo.draw, lo.hold, lo.life = 0.05, 0.02, 0.18
				S_("slashLine", f, tip, tip + fling * 3.2, lo)
			end
		end
		if hrp then
			sndOn("Whoosh", hrp, 0.4, 2.0)
		end

		-- the hit-stop: every client holds the caster's pose
		local frozen = 0
		if #models > 0 and c.track then
			pcall(ctx.freeze, c.track, HITSTOP)
			frozen = HITSTOP
		end
		-- the chiburi flourish takes over from the main clip at its hand-off (on the clip's own clock)
		do
			local tt = c.track and type(c.track.time) == "number" and c.track.time or (ctx.now() - c.t0)
			after(c, math.max(HANDOFF - tt, 0) + frozen, function()
				flourish(c)
			end)
		end

		-- sounds: one Shatter for the cut, staggered Hit2 per body, the heavy layer when something was cut
		if hrp then
			sndOn("Shatter", hrp, 0.8, 1.2)
			if #models > 0 then
				sndOn("HitHeavy", hrp, 0.6, 1.0)
				sndOn("Whoosh", hrp, 0.6, 0.8)
			end
			if #models >= 3 then
				sndOn("Cannon", hrp, 0.35, 1.4)
			end
		end

		-- the bodies: nearest the camera first; the first FullBodies get the full burst, the first 2 within NEAR_CAM
		-- bloom at full size, the rest small
		local list = {}
		for i, m in ipairs(models) do
			local tt = torsoOf(m)
			local pos = tt and tt.Position or poses[i]
			if typeof(pos) == "Vector3" then
				local dir = typeof(dirs[i]) == "Vector3" and dirs[i] or (c.face + UP).Unit
				table.insert(list, { m = m, pos = pos, dir = dir, cd = ctx.camDist(pos) })
			end
		end
		table.sort(list, function(a, b)
			return a.cd < b.cd
		end)
		c.cut = list
		local near = 0
		for i, h in ipairs(list) do
			local bloom = true
			if h.cd < NEAR_CAM then
				near += 1
				bloom = near <= 2
			end
			local full = c.tier >= 3 and i <= FULL_BODIES and room(c)
			if c.tier >= 2 or i <= 4 then
				cutBurst(c, h.m, h.pos, h.dir, full, bloom, mode, i)
			end
			if i <= 6 then
				after(c, 0.02 * (i - 1), function()
					sndOn("Hit2", torsoOf(h.m) or hrp, 0.7, 1.0 + rng:NextNumber(0, 0.3))
				end)
			end
		end
		if #list > 0 and c.tier >= 3 then
			local h = list[1]
			FX_("streaks", f, h.pos, { dir = h.dir, spread = 25, count = 16, color = mode and CRIMSON or CORE,
				color2 = mode and EMBER or FROST, speed = { 60, 120 }, size = 0.45, life = 0.3 })
		end

		-- the caster's camera
		if c.isLocal then
			-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (was callout "Zan")
			if #models > 0 then
				if mode then
					pcall(ctx.impact, { tint = C3(255, 200, 200), flash = CRIMSON, flashAlpha = 0.16, lines = true, lineTime = 0.3,
						lineColor = CRIMSON })
				else
					pcall(ctx.impact, { tint = FROST, flashAlpha = 0.14, lines = true, lineTime = 0.3, lineColor = FROST })
				end
				pcall(ctx.shake, 0.6, 0.35, 26, 7)
				-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (no "×n CUT" tally)
			else
				if mode then
					pcall(ctx.flash, CRIMSON, 0.1, 0.25)
				end
				pcall(ctx.shake, 0.25, 0.2, 26, 3)
			end
		end

		-- AFTERMATH
		if char and c.tier >= 3 then
			for _, t in ipairs({ 0.2, 0.38 }) do
				after(c, t, function()
					local base, tip = swordPoints(char)
					if base then
						FX_("bolt", f, base, tip, { color = mode and CRIMSON or REIATSU, width = 0.05, jag = 0.25, segments = 5, life = 0.1 })
					end
				end)
			end
		end
		if c.tier >= 2 then
			after(c, 0.25, function()
				for i, h in ipairs(list) do
					if i > 2 then
						break
					end
					local tt = torsoOf(h.m)
					FX_("ring", f, feetUnder(tt and tt.Position or h.pos) + UP * 0.15, UP, 1.5, 7, mode and CRIMSON or REIATSU, 1.0,
						{ alpha = 0.6 })
				end
			end)
			for _, t in ipairs({ 0.3, 0.7 }) do
				after(c, t, function()
					for i, h in ipairs(list) do
						if i > 4 then
							break
						end
						local tt = torsoOf(h.m)
						puff(c, "ember", tt and tt.Position or h.pos, nil, 5)
					end
				end)
			end
			after(c, 2.2, function()
				for _, p in pairs(c.pool or {}) do
					kill(p.host)
				end
				c.pool = nil
			end)
		end
		if c.tier >= 3 then
			-- the wisps start once the cut's one-shots have burnt out (the emitter budget; fewer under wave 2's flames)
			after(c, 0.6, function()
				for i, h in ipairs(list) do
					if i > (mode and math.min(WISP_BODIES, 2) or WISP_BODIES) then
						break
					end
					local tt = torsoOf(h.m)
					if tt and ctx.camDist(tt.Position) <= 40 then
						wisp(c, h.m, 1.4)
					end
				end
			end)
			after(c, 0.5, function()
				for i, h in ipairs(list) do
					if i > 2 then
						break
					end
					local tt = torsoOf(h.m)
					local p = feetUnder(tt and tt.Position or h.pos)
					-- never under the lens: the money shot has handed back and the follow camera can sit right over a
					-- body near the start of the path
					if ctx.camDist(p) > 12 then
						S_("dust", f, p + UP * 0.3, UP * 2 + c.face * 1.5, { s0 = 2, s1 = 6, count = 2, life = 1.6 })
						if mode then
							S_("ash", f, (tt and tt.Position or h.pos), { count = 10, radius = 1.5, life = 1.6, rise = 3 })
						end
					end
				end
			end)
			local info = char and swordInfo(char)
			if info and info.blade then
				local st = S_("steam", info.blade, 10)
				if st then
					c.steam = st
					after(c, 1.2, function()
						call(st, "stop")
					end)
				end
			end
		end
	end

	local function cutWave2(c, d)
		local f = c.f
		local list = c.cut
		if not list then
			list = {}
			for i, m in ipairs(type(d.models) == "table" and d.models or {}) do
				local tt = torsoOf(m)
				local pos = tt and tt.Position or (type(d.poses) == "table" and d.poses[i])
				if typeof(pos) == "Vector3" then
					table.insert(list, { m = m, pos = pos, cd = ctx.camDist(pos) })
				end
			end
		end
		local cam = workspace.CurrentCamera
		local R = cam and cam.CFrame.RightVector or Vector3.xAxis
		for i, h in ipairs(list) do
			local tt = torsoOf(h.m)
			local pos = tt and tt.Position or h.pos
			S_("slashLine", f, pos + R * 3.2, pos - R * 3.2, { width = 0.22, core = BLACK, edge = CRIMSON, draw = 0.02, hold = 0.2,
				life = 0.55, black = true })
			if c.tier >= 2 and i <= 2 then
				S_("reiatsuFlame", f, pos, { black = true, color = BLACK, color2 = CRIMSON, count = 9, height = 3.8, size = 1.15, life = 0.6 })
			end
			if c.tier >= 3 and i == 1 then
				FX_("ring", f, pos, camFacing(pos), 1, 6.5 * ringK(pos), CRIMSON, 0.25, { alpha = 0.3 })
				FX_("glow", f, pos, glowFor(pos, 3), EMBER, 0.12, { brightness = 2 })
			end
			if i <= 4 then
				after(c, 0.02 * (i - 1), function()
					sndOn("Hit2", tt or (c.char and c.char:FindFirstChild("HumanoidRootPart")), 0.6, 0.8)
				end)
			end
		end
		if c.isLocal and #list > 0 then
			pcall(ctx.shake, 0.35, 0.2, 30, 3)
			pcall(ctx.flash, CRIMSON, 0.08, 0.2)
		end
	end

	H.ShunpoCut = function(d)
		if type(d) ~= "table" then
			return
		end
		local key = keyOf(d)
		local c = casts[key]
		if not c then
			-- a late joiner who never saw the cast: draw the bursts in a fresh folder, core layer only
			local char, plr = ctx.charOf(d.userId)
			c = {
				key = key, t0 = ctx.now() - 1.12, f = ctx.castFolder("Shunpo", 4), char = char, isLocal = plr == ctx.player,
				mode = d.mode == true, tier = 1, face = Vector3.new(0, 0, -1), ghosts = {}, dead = false, id = d.id,
				chords = {}, marks = {}, flourished = true, len = 0, A = 0, C = 0,
			}
			if char then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if hrp then
					c.face = ctx.flat(hrp.CFrame.LookVector, c.face)
				end
			end
			casts[key] = c
			task.delay(3, function()
				if casts[key] == c then
					casts[key] = nil
				end
			end)
		end
		if c.dead then
			return
		end
		local ok, err
		if d.wave == 2 then
			ok, err = pcall(cutWave2, c, d)
		elseif not c.cutDone then
			ok, err = pcall(cutWave1, c, d)
		else
			ok = true
		end
		if not ok then
			warnOnce("cut" .. tostring(d.wave), "ShunpoCut wave " .. tostring(d.wave) .. ": " .. tostring(err))
		end
	end

	---------------------------------------------------------------------------------------------------
	-- ShunpoCancel / reset

	local function stopCast(c, fast)
		c.dead = true
		if c.pumpConn then
			c.pumpConn:Disconnect()
			c.pumpConn = nil
		end
		for _, w in ipairs(c.wisps or {}) do
			kill(w.host)
		end
		c.wisps = nil
		for _, p in pairs(c.pool or {}) do
			kill(p.host)
		end
		c.pool = nil
		if c.pulse then
			c.pulse:Disconnect()
			c.pulse = nil
		end
		kill(c.line)
		c.line = nil
		for _, ch in ipairs(c.chords or {}) do
			kill(ch.line)
		end
		c.chords = {}
		for _, mk in ipairs(c.marks or {}) do
			kill(mk)
		end
		c.marks = {}
		if c.glints then
			kill(c.glints.host)
			c.glints = nil
		end
		if c.glow then
			kill(c.glow)
			c.glow = nil
		end
		hushOff(c, false)
		if c.isLocal and c.shotUntil and os.clock() < c.shotUntil then
			pcall(ctx.stopShot)
		end
		c.shotUntil = nil
		if c.drone then
			pcall(function()
				c.drone:Destroy()
			end)
			c.drone = nil
		end
		if c.steam then
			call(c.steam, "stop")
			c.steam = nil
		end
		for g in pairs(c.ghosts) do
			kill(g)
		end
		c.ghosts = {}
		if c.track and type(c.track.stop) == "function" then
			pcall(c.track.stop, c.track, 0.15)
		end
		if fast and c.f then
			kill(c.f)
		end
		if c.isLocal then
			pcall(ctx.stopMove)
			pcall(ctx.unroot)
		end
	end

	H.ShunpoCancel = function(d)
		if type(d) ~= "table" then
			return
		end
		local c = casts[keyOf(d)]
		if c and not c.dead then
			stopCast(c, false)
		end
	end

	H.__reset = function()
		for key, c in pairs(casts) do
			if c.isLocal then
				stopCast(c, true)
				casts[key] = nil
			end
		end
	end

	return H
end
