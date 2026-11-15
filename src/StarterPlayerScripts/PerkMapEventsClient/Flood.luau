--!nocheck
-- PerkMapEventsClient.Flood: the water over the whole map, its top at the marker's Level (a deep blue body tagged
-- FloodWater so StarterPlayerScripts.FloodView tints the screen under it, a lighter bobbing surface, foam round me, a
-- rushing-water loop), and MY character in it: once the water is over my waist I float up to the surface and swim
-- (move keys / stick steer me, JUMP leaps out near the surface); a splash when I go in.
-- (2026-11-15, owner: "theres no swimming animation") while I am in the water my character plays Roblox's own R15 swim
-- (moving) / swim-idle (treading water) animations at Action priority, over the falling pose the humanoid is in; they
-- fade out when I leave the water, when I get knocked into a tumble, or when the flood ends. (The engine's Swimming
-- state only exists in terrain water, so the default Animate script never plays them here.)
-- Those animations stroke upright: in terrain water it is the engine that lays the body flat. So while a character
-- is swimming (its swim track is playing - mine, or anyone's, since tracks replicate) this screen pitches its Root
-- joint face-down (SWIM_TILT) and lifts it (SWIM_LIFT, so the back is at the surface and the head out), after the
-- animation step each frame. Treading water stays upright.
-- (2026-11-15, flood lag) the water body is only resized when the level really moves (it is ~650 x 720 studs).
local M = {}
local DEEP, TOP = Color3.fromRGB(34, 104, 190), Color3.fromRGB(128, 196, 244)
local SWIM_ID, SWIM_IDLE_ID = "rbxassetid://507784897", "rbxassetid://507785072"
local SWIM_TILT, SWIM_LIFT = math.rad(-75), 1.5
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local function swimTrackOn(hum)
	local an = hum and hum:FindFirstChildOfClass("Animator")
	if not an then
		return false
	end
	for _, tr in ipairs(an:GetPlayingAnimationTracks()) do
		if tr.IsPlaying and tr.WeightTarget > 0.5 and tr.Animation and tr.Animation.AnimationId == SWIM_ID then
			return true
		end
	end
	return false
end
-- every frame, after the animation step: lay swimmers flat (see the header)
local function tiltStep(S, dt)
	local now = os.clock()
	local lp = Players.LocalPlayer
	local seen = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local ch = pl.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		local lt = ch and ch:FindFirstChild("LowerTorso")
		local j = lt and lt:FindFirstChild("Root")
		if hum and j and (j:IsA("Motor6D") or j:IsA("AnimationConstraint")) then
			seen[ch] = true
			local T = S.tilt[ch]
			if not T or T.j ~= j then
				T = { j = j, k = 0, checkAt = 0, swim = false }
				S.tilt[ch] = T
			end
			if now >= T.checkAt then
				T.checkAt = now + 0.15
				if pl == lp then
					T.swim = S.animMode == "swim" and hum.Health > 0
				else
					T.swim = hum.Health > 0 and swimTrackOn(hum)
				end
			end
			local goal = T.swim and 1 or 0
			T.k = math.clamp(T.k + (goal - T.k) * math.min(1, dt * 6), 0, 1)
			if goal == 0 and T.k < 0.02 then
				T.k = 0
				if T.last then
					if j.Transform == T.last then
						j.Transform = T.base
					end
					T.last = nil
				end
			else
				local cur = j.Transform
				local base = (T.last and cur == T.last) and T.base or cur -- (the animator did not write it this frame)
				T.base = base
				j.Transform = CFrame.new(0, SWIM_LIFT * T.k, 0) * CFrame.Angles(SWIM_TILT * T.k, 0, 0) * base
				T.last = j.Transform
			end
		end
	end
	for ch in pairs(S.tilt) do
		if not seen[ch] then
			S.tilt[ch] = nil
		end
	end
end
local function untiltAll(S)
	for _, T in pairs(S.tilt) do
		if T.last and T.j.Parent and T.j.Transform == T.last then
			T.j.Transform = T.base
		end
	end
	S.tilt = {}
end

-- my swim tracks, loaded once per character
local function swimTracks(S, hum)
	if S.animHum ~= hum then
		S.animHum = hum
		S.swimT, S.idleT = nil, nil
		local an = hum and hum:FindFirstChildOfClass("Animator")
		if an then
			local function load(id)
				local ok, tr = pcall(function()
					local a = Instance.new("Animation")
					a.AnimationId = id
					return an:LoadAnimation(a)
				end)
				if ok and tr then
					tr.Priority = Enum.AnimationPriority.Action
					tr.Looped = true
					return tr
				end
				return nil
			end
			S.swimT, S.idleT = load(SWIM_ID), load(SWIM_IDLE_ID)
		end
	end
	return S.swimT, S.idleT
end
-- mode: "swim" | "idle" | nil (out of the water)
local function swimAnim(S, hum, mode, speed)
	if mode == S.animMode and mode ~= "swim" then
		return
	end
	local sw, id = swimTracks(S, hum)
	if mode == "swim" then
		if sw and not sw.IsPlaying then
			sw:Play(0.3)
		end
		if sw then
			sw:AdjustSpeed(math.clamp((speed or 12) / 11, 0.7, 1.5))
		end
		if id and id.IsPlaying then
			id:Stop(0.3)
		end
	elseif mode == "idle" then
		if id and not id.IsPlaying then
			id:Play(0.35)
		end
		if sw and sw.IsPlaying then
			sw:Stop(0.35)
		end
	else
		if sw and sw.IsPlaying then
			sw:Stop(0.3)
		end
		if id and id.IsPlaying then
			id:Stop(0.3)
		end
	end
	S.animMode = mode
end

function M.start(c, m)
	local S = { t = 0, inWater = false }
	local ac, ah = m:GetAttribute("AreaC"), m:GetAttribute("AreaH")
	S.ac, S.ah = ac, ah
	S.base = m:GetAttribute("Base") or 0
	local model = Instance.new("Model")
	model.Name = "Flood"
	model.Parent = c.folder
	S.model = model
	S.w, S.d = ah.X * 2 + 80, ah.Z * 2 + 80
	S.water = c.part({ Color = DEEP, Transparency = 0.38, Size = Vector3.new(S.w, 0.2, S.d), Parent = model })
	game:GetService("CollectionService"):AddTag(S.water, "FloodWater")
	S.surface = c.part({ Color = TOP, Transparency = 0.3, Reflectance = 0.15, Size = Vector3.new(S.w, 0.2, S.d), Parent = model })
	S.foamPart = c.part({ Transparency = 1, Size = Vector3.new(26, 0.5, 26), Parent = model })
	S.foam = c.emitter(S.foamPart, { rate = 0, life = NumberRange.new(1.5, 2.5), speed = NumberRange.new(0.5, 2), dir = Enum.NormalId.Top, spread = Vector2.new(80, 80),
		size = NumberSequence.new(1.2, 3.5), color = ColorSequence.new(Color3.fromRGB(235, 248, 255)), light = 0.2,
		tr = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) }) })
	S.flow = c.sound(c.SND.flow, S.foamPart, 0, 0.9, true, 200)
	S.tilt = {}
	S.tiltConn = RunService.Stepped:Connect(function(_, dt)
		local ok, err = pcall(tiltStep, S, dt)
		if not ok and not S.tiltWarned then
			S.tiltWarned = true
			warn("[Flood] swim tilt: " .. tostring(err))
		end
	end)
	return S
end

local function splash(c, pos, big)
	local p = c.part({ Transparency = 1, Size = Vector3.new(4, 0.5, 4), CFrame = CFrame.new(pos) })
	local e = c.emitter(p, { life = NumberRange.new(0.5, 0.9), speed = NumberRange.new(12, big and 26 or 18), dir = Enum.NormalId.Top, spread = Vector2.new(30, 30),
		size = NumberSequence.new(0.8, 2.2), accel = Vector3.new(0, -60, 0), color = ColorSequence.new(Color3.fromRGB(220, 240, 255)), light = 0.3,
		tr = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }) })
	e:Emit(big and 40 or 18)
	c.Debris:AddItem(p, 1.5)
	c.soundAt(c.SND.whoosh, pos, big and 0.9 or 0.5, 1.6, 120)
end

function M.step(c, S, m, dt)
	S.t += dt
	local level = m:GetAttribute("Level") or S.base
	if S.fading then
		level = S.base + (level - S.base) * S.fading
	end
	local depth = math.max(level - S.base, 0.05)
	local bottom = S.base - 3
	local h = level - bottom
	if not S.lastH or math.abs(h - S.lastH) > 0.02 then
		S.lastH = h
		S.water.Size = Vector3.new(S.w, h, S.d)
		S.water.CFrame = CFrame.new(S.ac.X, bottom + h / 2, S.ac.Z)
	end
	S.surface.CFrame = CFrame.new(S.ac.X, level + 0.05 + math.sin(S.t * 1.7) * 0.12, S.ac.Z)
	local show = depth > 0.3
	S.water.Transparency = show and 0.38 or 1
	S.surface.Transparency = show and 0.3 or 1
	local hrp, hum = c.root()
	if not hrp or not c.onMap(m, hrp.Position, 40) then
		S.foam.Rate, S.flow.Volume = 0, 0
		if hum then
			swimAnim(S, hum, nil)
		end
		return
	end
	S.flow.Volume = show and 0.7 or 0
	S.foamPart.CFrame = CFrame.new(hrp.Position.X, level, hrp.Position.Z)
	local under = level - hrp.Position.Y
	S.foam.Rate = (show and under > -3) and 14 or 0
	if hum.Health <= 0 or S.fading then
		swimAnim(S, hum, nil)
		return
	end
	local wet = under > -0.6 and depth > 2.6
	if wet and not S.inWater then
		splash(c, Vector3.new(hrp.Position.X, level, hrp.Position.Z), hrp.AssemblyLinearVelocity.Y < -25)
	end
	S.inWater = wet
	if not wet or c.tumbling() then
		swimAnim(S, hum, nil)
		return
	end
	-- swim: float with the chest just under the surface, steer with the move input, JUMP near the top leaps out
	local v = hrp.AssemblyLinearVelocity
	-- (2026-11-15) 0.5 higher than before: treading water, the face was half under
	local vyWant = math.clamp((level - 0.4 - hrp.Position.Y) * 4, -14, 16)
	if os.clock() - c.jumpAt < 0.15 and under < 2.2 then
		c.jumpAt = 0
		vyWant = 38
		v = Vector3.new(v.X, 38, v.Z)
		splash(c, Vector3.new(hrp.Position.X, level, hrp.Position.Z), false)
	end
	local want = hum.MoveDirection * 17
	local kH, kV = math.min(1, dt * 3.5), math.min(1, dt * 4)
	-- (playtest 2026-11-15) the water carries me: this frame's gravity is paid back first (buoyancy), then the speed
	-- eases toward floating at the surface - without it gravity won and I bobbed on the bottom in 10 studs of water
	local vy = v.Y + workspace.Gravity * dt
	vy += (vyWant - vy) * kV
	-- standing on the bottom, the humanoid holds its feet to the floor every step: off the floor it goes at once
	if hum.FloorMaterial ~= Enum.Material.Air and vyWant > 3 then
		vy = math.max(vy, 20)
	end
	hrp.AssemblyLinearVelocity = Vector3.new(v.X + (want.X - v.X) * kH, vy, v.Z + (want.Z - v.Z) * kH)
	-- the stroke while I move, treading water while I don't (a little slack so it doesn't flicker between them)
	local flat = Vector3.new(v.X, 0, v.Z).Magnitude
	local moving = hum.MoveDirection.Magnitude > 0.1 or flat > (S.animMode == "swim" and 4 or 7)
	swimAnim(S, hum, moving and "swim" or "idle", math.max(flat, 8))
end

function M.stop(c, S, m)
	if S.animHum then
		pcall(swimAnim, S, S.animHum, nil)
	end
	task.spawn(function()
		for i = 1, 15 do
			S.fading = 1 - i / 15
			pcall(M.step, c, S, m, 0.1)
			task.wait(0.1)
		end
		if S.tiltConn then
			S.tiltConn:Disconnect()
			S.tiltConn = nil
		end
		untiltAll(S)
		S.model:Destroy()
	end)
end

return M
