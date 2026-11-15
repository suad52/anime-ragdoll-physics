--!nocheck
-- PerkMapEventsClient.Zombies: the zombies themselves are server dummies (their arms-out walk is SandboxReactions'
-- "zombie" pose). Here: a sickly green, darker grade and a low drifting fog while I am on that map, and the one-shot
-- effects - zombieRise (earth bursting up where one climbs out), zombieBite (a puff and a crunch), zombieDust (a body
-- crumbling at the end). No blood.
local M = { fx = {} }
local EARTH = Color3.fromRGB(104, 84, 62)

function M.start(c, m)
	local S = { k = 0 }
	S.fogPart = c.part({ Transparency = 1, Size = Vector3.new(120, 1, 120) })
	S.fog = c.emitter(S.fogPart, { rate = 0, life = NumberRange.new(5, 8), speed = NumberRange.new(0.5, 2), dir = Enum.NormalId.Top, spread = Vector2.new(80, 80),
		size = NumberSequence.new(10, 18), color = ColorSequence.new(Color3.fromRGB(150, 176, 130)),
		tr = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.78), NumberSequenceKeypoint.new(1, 1) }) })
	return S
end

function M.step(c, S, m, dt)
	local hrp = c.root()
	local here = hrp and c.onMap(m, hrp.Position, 20) and not S.fading
	S.k += ((here and 1 or 0) - S.k) * (1 - math.exp(-dt * 1.2))
	c.grade(Color3.fromRGB(220, 240, 206), -0.06, 0.1, -0.3, S.k)
	S.fog.Rate = 9 * S.k
	if hrp then
		S.fogPart.CFrame = CFrame.new(hrp.Position - Vector3.new(0, 2.5, 0))
	end
end

function M.stop(c, S, m)
	S.fading = true
	task.spawn(function()
		for _ = 1, 30 do
			pcall(M.step, c, S, m, 0.1)
			task.wait(0.1)
		end
		S.fogPart:Destroy()
	end)
end

local function near(c, pos, r)
	local hrp = c.root()
	return hrp ~= nil and (hrp.Position - pos).Magnitude < r
end

M.fx.zombieRise = function(c, d)
	if typeof(d.pos) ~= "Vector3" or not near(c, d.pos, 400) then
		return
	end
	local hole = c.part({ Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(46, 36, 28), Material = Enum.Material.Ground,
		Size = Vector3.new(0.2, 4.5, 4.5), CFrame = CFrame.new(d.pos + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.pi / 2) })
	local p = c.part({ Transparency = 1, Size = Vector3.new(3, 0.5, 3), CFrame = CFrame.new(d.pos + Vector3.new(0, 0.5, 0)) })
	local e = c.emitter(p, { life = NumberRange.new(0.8, 1.4), speed = NumberRange.new(8, 18), dir = Enum.NormalId.Top, spread = Vector2.new(40, 40),
		size = NumberSequence.new(1.5, 4), accel = Vector3.new(0, -20, 0), color = ColorSequence.new(EARTH, Color3.fromRGB(80, 66, 52)) })
	e:Emit(26)
	for _ = 1, 5 do
		local s = c.rng:NextNumber(0.5, 1.1)
		local r = Instance.new("Part")
		r.Size = Vector3.new(s, s * 0.7, s)
		r.Color, r.Material = EARTH, Enum.Material.Ground
		r.CanCollide, r.CanQuery, r.CanTouch, r.CastShadow = false, false, false, false
		r.CFrame = CFrame.new(d.pos + Vector3.new(0, 1, 0))
		r.Parent = c.folder
		r.AssemblyLinearVelocity = Vector3.new(c.rng:NextNumber(-10, 10), c.rng:NextNumber(18, 30), c.rng:NextNumber(-10, 10))
		c.Debris:AddItem(r, 1.4)
	end
	c.soundAt(c.SND.crack, d.pos, 0.6, 0.45, 160)
	c.Debris:AddItem(p, 2)
	task.delay(6, function()
		c.tween(hole, 2, { Transparency = 1 })
		c.Debris:AddItem(hole, 2.1)
	end)
end

M.fx.zombieBite = function(c, d)
	if typeof(d.pos) ~= "Vector3" or not near(c, d.pos, 200) then
		return
	end
	local p = c.part({ Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(d.pos) })
	local e = c.emitter(p, { life = NumberRange.new(0.3, 0.5), speed = NumberRange.new(6, 12), size = NumberSequence.new(0.8, 2),
		color = ColorSequence.new(Color3.fromRGB(170, 200, 140)) })
	e:Emit(10)
	c.Debris:AddItem(p, 1)
	c.soundAt(c.SND.hit, d.pos, 0.8, 0.8, 120)
	if near(c, d.pos, 6) then
		c.kick(0.5)
	end
end

M.fx.zombieDust = function(c, d)
	if typeof(d.pos) ~= "Vector3" or not near(c, d.pos, 300) then
		return
	end
	local p = c.part({ Transparency = 1, Size = Vector3.new(3, 5, 3), CFrame = CFrame.new(d.pos) })
	local e = c.emitter(p, { life = NumberRange.new(1, 2), speed = NumberRange.new(1, 4), size = NumberSequence.new(2, 5), accel = Vector3.new(0, 4, 0),
		color = ColorSequence.new(Color3.fromRGB(140, 160, 120), Color3.fromRGB(110, 110, 100)) })
	e:Emit(30)
	c.Debris:AddItem(p, 2.5)
end

return M
