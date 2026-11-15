--!nocheck
-- StarterPlayerScripts.PerkMovement (2026-11-07, owner: movement - PERKS contract): the 2x Speed and 2x Jump perks.
--
-- Reads the LOCAL player's SpeedMul / JumpMul attributes (ShopService writes them on the server: 2 when the perk is
-- owned AND toggled on in the inventory, else 1) live every frame, so a toggle takes effect at once. Nothing is saved
-- or sent: the character is client-simulated, so the client is where WalkSpeed and the jump height matter. Every
-- client also draws the perk FX for every player (afterimages / wind lines / sonic boom for speed, shockwave + light
-- pillar + launch ribbon for a boosted jump).
--
-- WALK SPEED FOR EVERYONE (2026-11-11, owner: "increase movement speed, and make movement speed relative to health
-- (lower health = lower speed)"): the WalkSpeed multiplier is no longer only the perk's. Every frame the local
-- character walks at   kit base x SpeedMul x PvPShared.Balance.MOVE_SPEED_MUL x health factor,   where the health
-- factor is HEALTH_SPEED_MIN + (1 - HEALTH_SPEED_MIN) x clamp(Health / MaxHealth, 0, 1) - 1 at full health, down to
-- HEALTH_SPEED_MIN at (nearly) none. It is the SAME multiplier, so it rides the write/restore scheme below and the kits
-- still only ever read their own numbers. A giant form (Morphed: Kurama / Susanoo; TitanForm; FoxBeast; or a body
-- ScaleTo'd past GIANT_SCALE) gets the health factor only - its kit already sets the giant's own walk speed. A WalkSpeed
-- of 0 (a move rooting you) stays 0, the jump is untouched, and nothing is sent: only this client simulates the body.
-- The perk FX still key off the SpeedMul attribute alone.
--
-- NON-COMPOUNDING. Seven kits rewrite WalkSpeed / JumpPower / JumpHeight from their own RunService.Stepped loops and
-- several save-and-restore them around roots and stuns (GojoClient lockMovement, Carver / Tempest savedWalk, the
-- Zangetsu M1 slow), so multiplying the property in place would be saved, restored and multiplied again. Instead:
--   * pre-physics (Stepped; again task.defer'd behind every other Stepped handler; again in PreSimulation): whatever
--     the kits left in the property is the BASE; write base x mul + TAG (1/1024 - invisible, and no kit ever
--     produces it) and remember written -> base;
--   * post-physics (PostSimulation): put the base back if the property still holds our write.
-- So the kits only ever read their own numbers, and if one captures ours anyway (a Stepped handler that runs inside
-- that window) and restores it later, written -> base recognises the tagged value and maps it back to the base.
--
-- THE JUMP CAP (measured 2026-11-07: the whole map ray-cast from the sky at 2-3 stud pitch, street = terrain Y 2):
--   lowest building roof edge a player could land on = 19.6 studs above the street:
--     Crossing.Buildings.CR1.Cafe.Railing (the cafe terrace's railing) 19.65, Towers.NoraYokocho.Y8a roof deck 20.0.
--   Not roofs (props / canopies, all lower): bus shelters 7.5-8.4, EkiBox 7.9, market stalls 8.6, smoking booth 9.0,
--   koban 10.0, Aogaeru train car 12.0, ST1 door canopies 12.9, TW1 entrance canopies 14.0, signal/lamp arms 14.6-17,
--   boundary wall copings 15.8. Shopfront heads (10.8) and fascias (14) are under the building mass, not exposed.
--   A humanoid catches a ledge once its ROOT clears it (its legs do not collide), i.e. ~HipHeight above its feet, so:
--     feet apex + HipHeight + MARGIN(2) <= 19.6   ->   cap 15.4 studs for a stock 2.19-HipHeight avatar.
--   2x the stock 7.2 = 14.4 fits (a full 2x jump). A kit boost that would pass the cap is clamped to it (Gomu Gear
--   Fifth 15.1 x2 -> 15.4); a kit's own jump already above the cap (Vulpine Power 16.2) is left exactly as the kit
--   set it - the perk never lowers a jump. Giant forms (big HipHeight) get no boost at all.
--   Takeoff surface: a street-level floor (<= 3 studs above the street) gets the cap minus its own height (the apex
--   never passes street + 15.4). An elevated deck / platform / roof (top face >= 14 studs both ways) gets the same
--   cap relative to the deck, lowered by a 24-ray ring probe so nothing within 12 studs that the kit's own jump could
--   not reach becomes reachable. A small elevated perch (car roof, canopy, AC unit, sign, stall): no boost, the kit's
--   own jump only - so a perk hop onto a perch cannot be chained into a roof.
--   Mid-air jumps (One For All's Air Step sets vy 62): the first upward impulse during a boosted airtime is trimmed so
--   the arc peaks exactly where the same impulse would have taken an unboosted jumper at that moment, so the perk
--   never stacks height on top of a kit's air jump.
--
-- SANDBOX SLIDERS (2026-11-14): SpeedMul / JumpMul now come from the Run Speed / Jump Height sliders too
-- (ShopService.Ext.Sliders), anywhere from SLIDER_MIN to SLIDER_MAX - so they can also SLOW a walk or LOWER a jump.
-- With no workspace.City (the ragdoll sandbox) the roof cap above does not apply: the sandbox has no roofs to guard and
-- the slider is meant to launch you (StarterPlayerScripts.HeightLimit still keeps everyone inside the map's walls).
-- GRAVITY: a JumpHeight humanoid jumps the same height under any gravity (Roblox derives the takeoff speed from it) while
-- a JumpPower one jumps higher under less, so under a personal Gravity slider or Moon Gravity the JumpHeight is scaled by
-- STD_GRAVITY / workspace.Gravity: same legs, less pull, higher jump - for every kit alike. Only the slider / perk part
-- of a jump (JumpMul > 1) counts as a boosted jump for the jump FX.
--
-- Studio test hook: script.PerkMoveDebug (BindableFunction) - "state", "jump", "impulse" [vy], "fx" "jump"|"land"|
-- "boom"|"ghost". See the bottom of the file.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local STREET_Y = 2 -- the city's road / terrain surface (fallback when no terrain is under the player)
local ROOF_CLEAR = 19.6 -- lowest roof edge above the street (see the header)
local MARGIN = 2.4 -- the apex stays at least this far under it
-- (2026-11-07 integration) a real jump rises ~3.3% past JumpHeight (measured: JumpHeight 14.4 -> 14.87 studs, 7.2 ->
-- 7.31), so the cap is divided by this. With MARGIN 2.4 the cap is 14.47 on the street: the stock 2x (14.4) is untouched,
-- and a kit-boosted perk jump peaks with the root at ~17.2 above the street - under the Nora Yokocho wall AC units
-- (17.5), the lowest perch a normal jump can climb from onto a roof (24).
local OVERSHOOT = 1.035
local LOW_FLOOR = 3 -- floors up to this high above the street count as the street
local SLAB_MIN = 14 -- an elevated floor at least this wide both ways is a deck; narrower is a perch
local PROBE_RADII = { 4, 8, 12 }
local MUL_MAX = 3
local SLIDER_MIN, SLIDER_MAX = 0.2, 6 -- (2026-11-14) the range SpeedMul / JumpMul are read in (sandbox sliders)
local STD_GRAVITY = 196.2
local TAG = 1 / 1024
local FX_RANGE = 200
local AIR = Enum.Material.Air
local R15 = Enum.HumanoidRigType.R15
-- (2026-11-11) the game-wide walk speed knobs (PvPShared.Balance - read here, owned there). Neutral (1, 1) for the
-- moment before the module has loaded, so a slow load can only ever mean stock speed, never a wrong one.
local MOVE_SPEED_MUL, HEALTH_SPEED_MIN = 1, 1
local GIANT_SCALE = 1.5 -- a body ScaleTo'd past this is a giant form (KitServer's Kurama, ShifterService's titans)
task.spawn(function()
	pcall(function()
		local bal = require(ReplicatedStorage:WaitForChild("PvPShared", 30):WaitForChild("Balance", 30))
		local m, h = tonumber(bal.MOVE_SPEED_MUL), tonumber(bal.HEALTH_SPEED_MIN)
		if m and m == m then
			MOVE_SPEED_MUL = math.clamp(m, 0.5, MUL_MAX)
		end
		if h and h == h then
			HEALTH_SPEED_MIN = math.clamp(h, 0.1, 1)
		end
	end)
end)

local SPEED_COLOR = Color3.fromRGB(110, 255, 160)
local JUMP_COLOR = Color3.fromRGB(150, 170, 255)
local WHITE = Color3.new(1, 1, 1)
local DUST_COLOR = Color3.fromRGB(205, 210, 228)
task.spawn(function()
	pcall(function()
		local cat = require(ReplicatedStorage:WaitForChild("HudShared", 20):WaitForChild("PerkCatalog", 20))
		local s, j = cat.byId and cat.byId.SpeedX2, cat.byId and cat.byId.JumpX2
		if s and typeof(s.color) == "Color3" then
			SPEED_COLOR = s.color
		end
		if j and typeof(j.color) == "Color3" then
			JUMP_COLOR = j.color
		end
	end)
end)

local warned = {}
local function safe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		local k = tostring(err)
		if not warned[k] then
			warned[k] = true
			warn("[PerkMovement] " .. k)
		end
	end
end

local function mulOf(plr, name)
	local v = plr:GetAttribute(name)
	if type(v) ~= "number" or v ~= v then
		return 1
	end
	return math.clamp(v, SLIDER_MIN, SLIDER_MAX)
end
-- (2026-11-14) the ragdoll sandbox has no city: no roof cap there
local function capped()
	return workspace:FindFirstChild("City") ~= nil
end

local function legsOf(hum)
	if hum.RigType == R15 then
		return math.max(hum.HipHeight, 0)
	end
	return 2
end

-- (2026-11-11) a giant form: no MOVE_SPEED_MUL on top of the walk speed its kit already gave the giant
local function isGiant(char, hum, hrp)
	if char and (char:GetAttribute("Morphed") or char:GetAttribute("TitanForm") or char:GetAttribute("FoxBeast")) then
		return true
	end
	if hrp.Size.Y > 3.2 or legsOf(hum) > 5 then -- the same size test the perk FX use
		return true
	end
	if char and char:IsA("Model") then
		local ok, sc = pcall(char.GetScale, char)
		if ok and type(sc) == "number" and sc > GIANT_SCALE then
			return true
		end
	end
	return false
end

-- (2026-11-11) the local character's whole walk speed multiplier: SpeedMul (perk) x MOVE_SPEED_MUL (not for giants) x
-- the health factor (see the header)
local function healthFactor(hum)
	local mh, h = hum.MaxHealth, hum.Health
	local frac = 1
	if mh > 0 and h == h then
		frac = math.clamp(h / mh, 0, 1)
	end
	return HEALTH_SPEED_MIN + (1 - HEALTH_SPEED_MIN) * frac
end

local function walkFactor(char, hum, hrp)
	local f = mulOf(player, "SpeedMul") * healthFactor(hum)
	if not isGiant(char, hum, hrp) then
		f *= MOVE_SPEED_MUL
	end
	return f
end

---------------------------------------------------------------------------------------------------------------------
-- FX plumbing (client-local; every part is anchored and CanCollide / CanQuery / CanTouch false)
local fxRoot = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
local fxParams = RaycastParams.new()
fxParams.FilterType = Enum.RaycastFilterType.Exclude
fxParams.RespectCanCollide = true
local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { workspace.Terrain }

local mv -- the local movement state (below)

local function fxFolder()
	if not fxRoot or not fxRoot.Parent then
		fxRoot = Instance.new("Folder")
		fxRoot.Name = "PerkMoveFX"
		fxRoot.Parent = workspace
		rayParams.FilterDescendantsInstances = { fxRoot, mv and mv.char or nil }
	end
	return fxRoot
end

local function fxPart(cf, size, color, transparency, shape)
	local p = Instance.new("Part")
	p.Name = "PerkMoveFX"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Parent = fxFolder()
	return p
end

local function fade(p, t, goal)
	goal.Transparency = 1
	TweenService:Create(p, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	Debris:AddItem(p, t + 0.1)
end

local TEX_SHOCK = "rbxasset://textures/particles/explosion01_shockwave_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local function kp(t, v)
	return NumberSequenceKeypoint.new(t, v)
end

local function shock(color, s0, s1, life, dir)
	return {
		Texture = TEX_SHOCK, Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = dir or Enum.NormalId.Top, Speed = NumberRange.new(0.05), SpreadAngle = Vector2.zero,
		Lifetime = NumberRange.new(life), Size = NumberSequence.new(s0, s1), Rotation = NumberRange.new(0, 360),
		Transparency = NumberSequence.new({ kp(0, 0.05), kp(0.55, 0.45), kp(1, 1) }),
		LightEmission = 1, LightInfluence = 0, Color = ColorSequence.new(color), ZOffset = 0.3,
	}
end

local function dust(speed0, speed1, s0, s1, life)
	return {
		Texture = TEX_SMOKE, EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(88, 88),
		Speed = NumberRange.new(speed0, speed1), Drag = 6, Acceleration = Vector3.new(0, 4, 0),
		Lifetime = NumberRange.new(life * 0.7, life), Size = NumberSequence.new(s0, s1),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90),
		Transparency = NumberSequence.new({ kp(0, 0.45), kp(1, 1) }),
		LightEmission = 0.1, LightInfluence = 0.6, Color = ColorSequence.new(DUST_COLOR),
	}
end

local function sparks(color, speed0, speed1, spread, life)
	return {
		Texture = TEX_SPARK, EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(spread, spread),
		Speed = NumberRange.new(speed0, speed1), Drag = 2.5, Acceleration = Vector3.new(0, -40, 0),
		Lifetime = NumberRange.new(life * 0.6, life), Size = NumberSequence.new({ kp(0, 0.9), kp(1, 0) }),
		Transparency = NumberSequence.new(0, 0.3), LightEmission = 1, LightInfluence = 0,
		Color = ColorSequence.new(WHITE, color),
	}
end

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Parent = parent
	return e
end

-- one burst of particles at a world CFrame (an invisible anchored holder that removes itself)
local function emitAt(cf, props, count, life)
	local holder = fxPart(cf, Vector3.new(0.2, 0.2, 0.2), WHITE, 1)
	local a = Instance.new("Attachment")
	a.Parent = holder
	emitter(a, props):Emit(count)
	Debris:AddItem(holder, life)
end

-- the floor under a character (FX placement); ok = there is one within a stride of the feet
local function groundUnder(char, hum, hrp)
	local reach = legsOf(hum) + hrp.Size.Y * 0.5
	fxParams.FilterDescendantsInstances = { char, fxFolder() }
	local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -(reach + 4), 0), fxParams)
	if hit then
		return hit.Position, true
	end
	return hrp.Position - Vector3.new(0, reach, 0), false
end

local tracked = {} -- [character] = FX state

local function jumpFx(char, hum, hrp)
	local gp = groundUnder(char, hum, hrp)
	local up = Vector3.yAxis
	emitAt(CFrame.new(gp + up * 0.2), shock(JUMP_COLOR, 3, 19, 0.45), 1, 0.6)
	emitAt(CFrame.new(gp + up * 0.3), shock(WHITE, 1.5, 11, 0.28), 1, 0.45)
	emitAt(CFrame.new(gp + up * 0.4), dust(14, 26, 1.4, 4.2, 0.65), 12, 0.9)
	emitAt(CFrame.new(gp + up * 0.6), sparks(JUMP_COLOR, 24, 48, 22, 0.55), 16, 0.8)
	local pillar = fxPart(CFrame.new(gp + up * 5) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(10, 1.4, 1.4),
		JUMP_COLOR, 0.2, Enum.PartType.Cylinder)
	fade(pillar, 0.3, { Size = Vector3.new(14, 0.05, 0.05), CFrame = pillar.CFrame + up * 2 })
	local st = tracked[char]
	if st then
		st.riseUntil = os.clock() + 0.45
	end
end

local function landFx(char, hum, hrp)
	local gp = groundUnder(char, hum, hrp)
	emitAt(CFrame.new(gp + Vector3.yAxis * 0.2), shock(JUMP_COLOR, 2, 11, 0.32), 1, 0.5)
	emitAt(CFrame.new(gp + Vector3.yAxis * 0.4), dust(10, 18, 1.2, 3.4, 0.5), 8, 0.7)
end

-- the sonic boom left behind when a SpeedX2 runner hits full speed
local function boomFx(st, v)
	local dir = Vector3.new(v.X, 0, v.Z)
	if dir.Magnitude < 1 then
		return
	end
	dir = dir.Unit
	local pos = st.hrp.Position - dir * 2
	local cf = CFrame.lookAt(pos, pos - dir)
	emitAt(cf, shock(SPEED_COLOR, 2, 10, 0.32, Enum.NormalId.Front), 1, 0.5)
	emitAt(cf, shock(WHITE, 1, 6, 0.22, Enum.NormalId.Front), 1, 0.4)
	if st.dust then
		st.dust:Emit(6)
	end
end

local BODY = {
	Head = true, UpperTorso = true, LowerTorso = true, LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
	RightUpperArm = true, RightLowerArm = true, RightHand = true, LeftUpperLeg = true, LeftLowerLeg = true,
	LeftFoot = true, RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
	Torso = true, ["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
}
-- a neon afterimage of the body where it stands now, fading out behind the runner
local function ghostFx(st)
	local fx = fxFolder()
	if #fx:GetChildren() > 450 then
		return
	end
	for _, p in ipairs(st.char:GetChildren()) do
		if p:IsA("BasePart") and BODY[p.Name] and p.Transparency < 0.9 and p.LocalTransparencyModifier < 0.9 then
			local ok, g = pcall(p.Clone, p)
			if ok and g then
				for _, ch in ipairs(g:GetChildren()) do
					if not ch:IsA("DataModelMesh") then
						ch:Destroy()
					end
				end
				g.Anchored, g.CanCollide, g.CanQuery, g.CanTouch, g.CastShadow = true, false, false, false, false
				g.Material = Enum.Material.Neon
				g.Color = SPEED_COLOR
				g.Transparency = 0.62
				if g:IsA("MeshPart") then
					g.TextureID = ""
				end
				g.CFrame = p.CFrame
				g.Name = "PerkMoveGhost"
				g.Parent = fx
				fade(g, 0.28, {})
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- per-character FX rig: thin wind lines + a faint body-blur ribbon (speed), a launch ribbon under the feet (jump),
-- a heel dust emitter. Attachments sit on the root part; the Trails live in the FX folder.
local LINES = { -- {offset in root space (Y scaled by the root's half height), half length}
	{ Vector3.new(-1.3, 0.8, 0.3), 0.14 },
	{ Vector3.new(1.3, 0.25, 0.3), 0.14 },
	{ Vector3.new(-1.0, -0.8, 0.35), 0.12 },
	{ Vector3.new(1.05, 1.15, 0.2), 0.1 },
}

local function makeTrail(a0, a1, color, life, t0, emission, faceCam, widthEnd)
	local tr = Instance.new("Trail")
	tr.Name = "PerkMoveTrail"
	tr.Attachment0, tr.Attachment1 = a0, a1
	tr.Lifetime = life
	tr.MinLength = 0.05
	tr.FaceCamera = faceCam
	tr.LightEmission = emission
	tr.LightInfluence = 0
	tr.Color = ColorSequence.new(WHITE, color)
	tr.Transparency = NumberSequence.new({ kp(0, t0), kp(1, 1) })
	tr.WidthScale = NumberSequence.new({ kp(0, 1), kp(1, widthEnd) })
	tr.Enabled = false
	tr.Parent = fxFolder()
	return tr
end

local function clearRig(st)
	for _, a in ipairs(st.atts) do
		a:Destroy()
	end
	for _, t in ipairs(st.trails) do
		t:Destroy()
	end
	table.clear(st.atts)
	table.clear(st.trails)
	st.blur, st.rise, st.dust, st.rigFor = nil, nil, nil, nil
end

local function ensureRig(st)
	local hrp = st.hrp
	if st.rigFor == hrp and st.blur and st.blur.Parent and st.atts[1] and st.atts[1].Parent == hrp then
		return
	end
	clearRig(st)
	local function att(name, pos)
		local a = Instance.new("Attachment")
		a.Name = name
		a.Position = pos
		a.Parent = hrp
		table.insert(st.atts, a)
		return a
	end
	local sy = hrp.Size.Y * 0.5
	local foot = -sy - legsOf(st.hum)
	for i, d in ipairs(LINES) do
		local p = d[1] * Vector3.new(1, sy, 1)
		local a0 = att("PerkMove_L" .. i .. "a", p + Vector3.new(0, d[2], 0))
		local a1 = att("PerkMove_L" .. i .. "b", p - Vector3.new(0, d[2], 0))
		table.insert(st.trails, makeTrail(a0, a1, SPEED_COLOR, 0.32, 0.1, 1, true, 0.2))
	end
	st.blur = makeTrail(att("PerkMove_Ba", Vector3.new(0, 1.1 * sy, 0.55)), att("PerkMove_Bb", Vector3.new(0, -1.2 * sy, 0.55)),
		SPEED_COLOR, 0.14, 0.72, 0.6, false, 0.6)
	table.insert(st.trails, st.blur)
	st.rise = makeTrail(att("PerkMove_Ra", Vector3.new(-0.6, foot + 0.3, 0)), att("PerkMove_Rb", Vector3.new(0.6, foot + 0.3, 0)),
		JUMP_COLOR, 0.35, 0.15, 1, false, 0)
	table.insert(st.trails, st.rise)
	st.dust = emitter(att("PerkMove_D", Vector3.new(0, foot + 0.2, 0.6)), dust(4, 9, 0.9, 2.6, 0.45))
	st.rigFor = hrp
end

local function setTrails(st, on)
	for _, t in ipairs(st.trails) do
		t.Enabled = on
	end
end

local function updateChar(st, now, camPos)
	local hrp, hum = st.hrp, st.hum
	local sm, jm = mulOf(st.plr, "SpeedMul"), mulOf(st.plr, "JumpMul")
	local giant = hrp.Size.Y > 3.2 or legsOf(hum) > 5
	local wanted = (sm > 1 or jm > 1) and not giant and hum.Health > 0
	if not wanted or (hrp.Position - camPos).Magnitude > FX_RANGE then
		if st.rigFor then
			if wanted then
				setTrails(st, false)
			else
				clearRig(st)
			end
		end
		st.fast, st.prevVy = false, nil
		return
	end
	ensureRig(st)
	local v = hrp.AssemblyLinearVelocity
	local hs = Vector3.new(v.X, 0, v.Z).Magnitude
	local onGround
	if st.isLocal then
		onGround = hum.FloorMaterial ~= AIR
	else
		onGround = math.abs(v.Y) < 10
	end
	-- speed: wind lines + blur while fast, a sonic boom on reaching speed, heel dust and afterimages
	local wasFast = st.fast
	st.fast = sm > 1 and hs > (wasFast and 17 or 23) and (onGround or (wasFast and v.Y > -40))
	if st.fast ~= wasFast then
		for _, t in ipairs(st.trails) do
			if t ~= st.rise then
				t.Enabled = st.fast
			end
		end
	end
	if st.fast then
		if not wasFast and now - (st.slowSince or 0) > 0.5 then
			boomFx(st, v)
		end
		if onGround and now - (st.lastDust or 0) > 0.1 then
			st.lastDust = now
			st.dust:Emit(2)
		end
		if now - (st.lastGhost or 0) > 0.16 then
			st.lastGhost = now
			ghostFx(st)
		end
	elseif wasFast then
		st.slowSince = now
	end
	-- jump: the local jumper's FX come from its humanoid state; a remote one is read off its root's velocity
	if not st.isLocal and jm > 1 then
		local prev = st.prevVy or 0
		if v.Y > 60 and prev < 18 and now - (st.lastJumpFx or 0) > 0.35 then
			local _, ok = groundUnder(st.char, hum, hrp)
			if ok then
				st.lastJumpFx, st.remoteAir = now, true
				jumpFx(st.char, hum, hrp)
			end
		elseif st.remoteAir and prev < -18 and v.Y > -4 then
			st.remoteAir = false
			landFx(st.char, hum, hrp)
		end
	end
	st.prevVy = v.Y
	local rising = now < (st.riseUntil or 0)
	if st.rise.Enabled ~= rising then
		st.rise.Enabled = rising
	end
end

local frame = 0
local function fxStep()
	frame += 1
	local now = os.clock()
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if char then
			local st = tracked[char]
			if st and (st.hrp.Parent ~= char or st.hum.Parent ~= char) then
				clearRig(st)
				tracked[char], st = nil, nil
			end
			if not st then
				local hum = char:FindFirstChildOfClass("Humanoid")
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if hum and hrp and hrp:IsA("BasePart") then
					st = { char = char, hum = hum, hrp = hrp, plr = plr, isLocal = plr == player, atts = {}, trails = {} }
					tracked[char] = st
				end
			end
			if st then
				st.frame = frame
				safe(updateChar, st, now, camPos)
			end
		end
	end
	for char, st in pairs(tracked) do
		if st.frame ~= frame then
			clearRig(st)
			tracked[char] = nil
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- the local character's movement multiplier (see the header for why it lives only inside the physics step)
mv = {
	char = nil, hum = nil, hrp = nil,
	wrote = {}, base = {}, -- this frame's writes (read back) and the bases they replaced
	sMul = nil, jVal = nil,
	boost = nil, -- { hKit, hNew } from the last grounded pre-physics pass (the jump that starts uses it)
	capInfo = nil, air = nil, groundY = nil,
	last = {}, lastTrim = nil, lastJump = nil, -- debug
}

local function newMaps()
	return { WalkSpeed = {}, JumpHeight = {}, JumpPower = {} }
end
local maps, oldMaps, mapCount = newMaps(), newMaps(), 0

local function remember(prop, written, base)
	if maps[prop][written] == nil then
		mapCount += 1
		if mapCount > 192 then
			oldMaps, maps, mapCount = maps, newMaps(), 1
		end
	end
	maps[prop][written] = base
end

local function baseOf(prop, cur)
	local b = maps[prop][cur]
	if b == nil then
		b = oldMaps[prop][cur]
	end
	if b == nil then
		return cur
	end
	return b
end

local function write(hum, prop, base, value)
	hum[prop] = value + TAG
	local back = hum[prop]
	remember(prop, back, base)
	mv.wrote[prop], mv.base[prop] = back, base
	mv.last[prop] = back
end

-- the property holds an old write of ours (the perk went off mid-frame, or a kit restored a value it captured from
-- us): hand the kit its own number back
local function unwrite(hum, prop, cur, base)
	if cur ~= base then
		hum[prop] = base
	end
	mv.wrote[prop] = nil
end

local function streetY(pos)
	local hit = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -600, 0), terrainParams)
	if hit and hit.Position.Y > STREET_Y - 12 then
		return hit.Position.Y
	end
	return STREET_Y
end

local function topMinDim(part)
	if part:IsA("Terrain") or not part:IsA("BasePart") then
		return math.huge
	end
	local cf, s = part.CFrame, part.Size
	local ry, uy, ly = math.abs(cf.RightVector.Y), math.abs(cf.UpVector.Y), math.abs(cf.LookVector.Y)
	if uy >= ry and uy >= ly then
		return math.min(s.X, s.Z)
	elseif ry >= ly then
		return math.min(s.Y, s.Z)
	end
	return math.min(s.X, s.Y)
end

-- on a deck: the highest the jump may reach so nothing nearby that the kit's own jump cannot reach gets reachable
local function probeLimit(pos, floorY, kitReach, su)
	local top = ROOF_CLEAR + 1
	local limit = math.huge
	for _, r in ipairs(PROBE_RADII) do
		for i = 0, 7 do
			local a = i * math.pi / 4 + (r == 8 and math.pi / 8 or 0)
			local o = Vector3.new(pos.X + math.cos(a) * r, floorY + top, pos.Z + math.sin(a) * r)
			local hit = workspace:Raycast(o, Vector3.new(0, -(top - 0.25), 0), rayParams)
			if hit and hit.Normal.Y > 0.5 then
				local s = hit.Position.Y - floorY
				if s > kitReach + 0.1 then
					limit = math.min(limit, s - MARGIN - su)
				end
			end
		end
	end
	return limit
end

-- the most the boosted jump may lift the feet (studs) from where the character stands now
local function jumpCap(hum, hrp, hKit)
	local now, pos = os.clock(), hrp.Position
	local c = mv.capInfo
	if c and now - c.t < 0.15 and (pos - c.pos).Magnitude < 1.5 and math.abs(c.hKit - hKit) < 1e-3 then
		return c.val
	end
	local su = legsOf(hum)
	local val, class, f, floor = hKit, "none", 0, nil
	local hit = workspace:Raycast(pos, Vector3.new(0, -(su + hrp.Size.Y * 0.5 + 3), 0), rayParams)
	if hit then
		floor = hit.Instance
		f = hit.Position.Y - streetY(pos)
		if f <= LOW_FLOOR then
			class = "street"
			val = (ROOF_CLEAR - MARGIN - su - math.max(f, 0)) / OVERSHOOT
		elseif topMinDim(hit.Instance) >= SLAB_MIN then
			class = "deck"
			val = math.min(ROOF_CLEAR - MARGIN - su, probeLimit(pos, hit.Position.Y, hKit + su, su)) / OVERSHOOT
		else
			class = "perch"
		end
	end
	mv.capInfo = { t = now, pos = pos, hKit = hKit, val = val, class = class, f = f, su = su, floor = floor }
	return val
end

local function apply()
	local hum, hrp = mv.hum, mv.hrp
	if not hum or not hrp or not hum.Parent or not hrp.Parent or hum.Health <= 0 then
		return
	end
	-- WalkSpeed: base x walkFactor (SpeedMul x MOVE_SPEED_MUL x health - 2026-11-11). It can be under 1 now (low
	-- health, a hurt giant), so any factor but exactly 1 writes; a rooted 0 (base <= 0.05) is left alone
	local sm = walkFactor(mv.char or hum.Parent, hum, hrp)
	local cur = hum.WalkSpeed
	local base = baseOf("WalkSpeed", cur)
	if math.abs(sm - 1) > 1e-4 and base > 0.05 then
		if not (mv.wrote.WalkSpeed == cur and mv.base.WalkSpeed == base and mv.sMul == sm) then
			write(hum, "WalkSpeed", base, base * sm)
			mv.sMul = sm
		end
	elseif cur ~= base or mv.wrote.WalkSpeed then
		unwrite(hum, "WalkSpeed", cur, base)
	end
	-- the jump: height x JumpMul, capped (jumpCap); the kit's own value when it is already at or past the cap
	local useJP = hum.UseJumpPower
	local prop = useJP and "JumpPower" or "JumpHeight"
	local other = useJP and "JumpHeight" or "JumpPower"
	if mv.wrote[other] then -- UseJumpPower flipped under us
		unwrite(hum, other, hum[other], baseOf(other, hum[other]))
	end
	cur = hum[prop]
	base = baseOf(prop, cur)
	local grounded = hum.FloorMaterial ~= AIR
	local jm = mulOf(player, "JumpMul")
	local g = math.max(workspace.Gravity, 1)
	-- (2026-11-14) gravity: see the header (a JumpPower humanoid already rises higher under less gravity)
	local gk = useJP and 1 or math.clamp(STD_GRAVITY / g, 0.2, 20)
	local eff = jm * gk
	if math.abs(eff - 1) > 1e-3 and base > 0.05 and grounded then
		local hKit = useJP and base * base / (2 * g) or base
		local hNew = hKit * eff
		if eff > 1 and capped() then
			hNew = math.min(hNew, jumpCap(hum, hrp, hKit))
		end
		if math.abs(hNew - hKit) > 0.05 then
			local val = useJP and math.sqrt(2 * g * hNew) or hNew
			if not (mv.wrote[prop] == cur and mv.base[prop] == base and mv.jVal == val) then
				write(hum, prop, base, val)
				mv.jVal = val
			end
			mv.boost = (jm > 1) and { hKit = hKit, hNew = hNew } or nil
			return
		end
	end
	if grounded then
		mv.boost = nil
	end
	if cur ~= base or mv.wrote[prop] then
		unwrite(hum, prop, cur, base)
	end
end

local function restore()
	local hum = mv.hum
	if hum and hum.Parent then
		for prop, w in pairs(mv.wrote) do
			if hum[prop] == w then
				hum[prop] = mv.base[prop]
			end
		end
	end
	table.clear(mv.wrote)
end

local OFF_STATES = {
	[Enum.HumanoidStateType.Physics] = true, [Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true, [Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Dead] = true, [Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.Swimming] = true, [Enum.HumanoidStateType.Climbing] = true,
}

local function endAir(a, hrp, why)
	mv.air = nil
	mv.lastJump = { hKit = a.hKit, hNew = a.hNew, apex = a.maxY - a.y0, trimmed = a.trimmed or false, ended = why }
end

-- a boosted airtime: trims a kit's mid-air jump back to what it would have given without the perk, and plays the
-- landing FX
local function trackAir()
	local a, hum, hrp = mv.air, mv.hum, mv.hrp
	if not a then
		return
	end
	if not hum or not hrp or not hrp.Parent or OFF_STATES[hum:GetState()] or hum.PlatformStand
		or (mv.char and mv.char:GetAttribute("Flying")) then
		endAir(a, hrp, "interrupted")
		return
	end
	local t = os.clock() - a.t0
	local v = hrp.AssemblyLinearVelocity
	a.maxY = math.max(a.maxY, hrp.Position.Y)
	if t > 0.12 and hum.FloorMaterial ~= AIR then
		endAir(a, hrp, "landed")
		landFx(mv.char, hum, hrp)
		return
	end
	if not a.trimmed and t > 0.06 and v.Y > 0 and v.Y > a.prevVy + 15 then
		a.trimmed = true -- one trim per airtime: after it the arc is the kit's own
		local g = workspace.Gravity
		local yKit = math.max(0, a.vKit * t - 0.5 * g * t * t) -- where an unboosted jumper would be now
		local diff = (hrp.Position.Y - a.y0) - yKit
		if diff > 0.2 then
			local vy2 = v.Y * v.Y - 2 * g * diff
			local nvy = vy2 > 0 and math.sqrt(vy2) or 0
			hrp.AssemblyLinearVelocity = Vector3.new(v.X, nvy, v.Z)
			mv.lastTrim = { t = t, diff = diff, from = v.Y, to = nvy }
			v = hrp.AssemblyLinearVelocity
		end
	end
	a.prevVy = v.Y
	if t > 8 then
		endAir(a, hrp, "timeout")
	end
end

local function onCharacter(char)
	mv.char, mv.hum, mv.hrp = char, nil, nil
	mv.air, mv.boost, mv.capInfo, mv.groundY, mv.groundedAt, mv.sMul, mv.jVal = nil, nil, nil, nil, nil, nil, nil
	table.clear(mv.wrote)
	table.clear(mv.base)
	rayParams.FilterDescendantsInstances = { fxFolder(), char }
	local hum = char:WaitForChild("Humanoid", 15)
	local hrp = char:WaitForChild("HumanoidRootPart", 15)
	if not hum or not hrp or mv.char ~= char then
		return
	end
	mv.hum, mv.hrp = hum, hrp
	hum.StateChanged:Connect(function(_, new)
		if new ~= Enum.HumanoidStateType.Jumping or mv.hum ~= hum then
			return
		end
		local b = mv.boost
		-- only a jump off the ground (a kit forcing the Jumping state mid-air is not a boosted takeoff)
		if not b or not hrp.Parent or os.clock() - (mv.groundedAt or -1e9) > 0.25 then
			return
		end
		local y = hrp.Position.Y
		mv.air = {
			t0 = os.clock(), y0 = math.min(mv.groundY or y, y), maxY = y, prevVy = hrp.AssemblyLinearVelocity.Y,
			vKit = math.sqrt(2 * workspace.Gravity * b.hKit), hKit = b.hKit, hNew = b.hNew,
		}
		safe(jumpFx, char, hum, hrp)
	end)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

local function safeApply()
	safe(apply)
end

-- (2026-11-07 integration) the Humanoid reads WalkSpeed for the frame BETWEEN PreAnimation and Stepped (measured: a
-- value held only from Stepped to PostSimulation never moves the body; one held from PreAnimation to Stepped does), so
-- the speed write has to land in PreAnimation or the 2x Speed perk does nothing. The kits' Stepped loops still read
-- their own numbers back through baseOf (the written value is tagged), and PostSimulation still restores the base.
RunService.PreAnimation:Connect(safeApply)
RunService.Stepped:Connect(function()
	safe(apply)
	task.defer(safeApply) -- again, behind every other Stepped handler (the kits' movement loops run there)
end)
RunService.PreSimulation:Connect(safeApply)
RunService.PostSimulation:Connect(function()
	safe(restore)
	safe(trackAir)
	local hum, hrp = mv.hum, mv.hrp
	if hum and hrp and hrp.Parent and hum.FloorMaterial ~= AIR then
		mv.groundedAt = os.clock()
		if math.abs(hrp.AssemblyLinearVelocity.Y) < 5 then
			mv.groundY = hrp.Position.Y -- the takeoff reference (not updated on the launching frame itself)
		end
	end
end)
RunService.Heartbeat:Connect(fxStep)

---------------------------------------------------------------------------------------------------------------------
-- Studio-only test hook: script.PerkMoveDebug:Invoke(cmd, arg)
--   "state"          -> table: multipliers, the kit's base vs what we wrote, the cap and why, the last jump's measured
--                       apex (studs above the takeoff root) and any mid-air trim
--   "jump"           -> presses jump once (Humanoid.Jump = true)
--   "impulse", vy    -> sets the root's vertical velocity (a stand-in for One For All's Air Step, default 62)
--   "fx", kind       -> plays "jump" | "land" | "boom" | "ghost" on the local character
if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "PerkMoveDebug"
	hook.OnInvoke = function(cmd, arg)
		local char, hum, hrp = mv.char, mv.hum, mv.hrp
		if cmd == "state" then
			local c = mv.capInfo
			local jp = hum and (hum.UseJumpPower and "JumpPower" or "JumpHeight")
			local lj = mv.lastJump
			return {
				speedMul = mulOf(player, "SpeedMul"), jumpMul = mulOf(player, "JumpMul"),
				-- (2026-11-11) the whole walk factor and its parts
				walkFactor = hum and hrp and walkFactor(char or hum.Parent, hum, hrp), moveSpeedMul = MOVE_SPEED_MUL,
				healthFactor = hum and healthFactor(hum), giant = hum and hrp and isGiant(char or hum.Parent, hum, hrp),
				walkSpeedKit = hum and baseOf("WalkSpeed", hum.WalkSpeed), walkSpeedWritten = mv.last.WalkSpeed,
				jumpProp = jp, jumpKit = hum and baseOf(jp, hum[jp]), jumpWritten = jp and mv.last[jp],
				boostHKit = mv.boost and mv.boost.hKit, boostHNew = mv.boost and mv.boost.hNew,
				capClass = c and c.class, capStuds = c and c.val, floorAboveStreet = c and c.f,
				stepUp = c and c.su, floor = c and c.floor and c.floor:GetFullName(),
				airborne = mv.air ~= nil,
				lastJumpHKit = lj and lj.hKit, lastJumpHNew = lj and lj.hNew, lastJumpApex = lj and lj.apex,
				lastJumpTrimmed = lj and lj.trimmed, lastJumpEnded = lj and lj.ended,
				lastTrimDiff = mv.lastTrim and mv.lastTrim.diff, lastTrimFrom = mv.lastTrim and mv.lastTrim.from,
				lastTrimTo = mv.lastTrim and mv.lastTrim.to,
				roofClear = ROOF_CLEAR, margin = MARGIN, fxParts = #fxFolder():GetChildren(),
			}
		elseif cmd == "jump" then
			if hum then
				hum.Jump = true
			end
			return hum ~= nil
		elseif cmd == "impulse" then
			if hrp then
				local v = hrp.AssemblyLinearVelocity
				hrp.AssemblyLinearVelocity = Vector3.new(v.X, tonumber(arg) or 62, v.Z)
			end
			return hrp ~= nil
		elseif cmd == "fx" then
			if not (char and hum and hrp) then
				return false
			end
			local st = tracked[char]
			if arg == "jump" then
				jumpFx(char, hum, hrp)
			elseif arg == "land" then
				landFx(char, hum, hrp)
			elseif arg == "boom" and st then
				boomFx(st, hrp.CFrame.LookVector * 30)
			elseif arg == "ghost" and st then
				ghostFx(st)
			end
			return true
		end
		return nil
	end
	hook.Parent = script
end
