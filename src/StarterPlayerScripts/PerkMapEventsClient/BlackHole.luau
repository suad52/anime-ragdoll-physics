--!nocheck
-- PerkMapEventsClient.BlackHole: the hole (a black core with a glowing rim, a tilted accretion disk of three bands and
-- orbiting embers, a shimmering lens shell, matter streaming in, a purple light, a deep drone) sized by the marker's
-- Power, and its pull on MY character: inside Reach it drags me in and lifts me off my feet; at the core I am spat
-- back out in a tumble. MapEventFX: bhSwallow (a flash at the core), bhCollapse, bhBurst (the shockwave at the end).
local M = { fx = {} }
local PURPLE, MAGENTA, ORANGE = Color3.fromRGB(150, 70, 255), Color3.fromRGB(255, 80, 200), Color3.fromRGB(255, 170, 70)
local CORE = 18 -- core diameter at full power
local holes = {}

function M.start(c, m)
	local S = { t = 0, embers = {}, id = m:GetAttribute("Id") }
	holes[S.id] = S
	local model = Instance.new("Model")
	model.Name = "BlackHole"
	model.Parent = c.folder
	S.model = model
	S.rim = c.part({ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = PURPLE, Transparency = 0.35, Size = Vector3.one, Parent = model })
	S.core = c.part({ Shape = Enum.PartType.Ball, Color = Color3.new(0, 0, 0), Size = Vector3.one, Parent = model })
	S.lens = c.part({ Shape = Enum.PartType.Ball, Material = Enum.Material.ForceField, Color = MAGENTA, Transparency = 0.2, Size = Vector3.one, Parent = model })
	S.disks = {}
	for i, d in ipairs({ { 3.9, PURPLE, 0.72 }, { 2.9, MAGENTA, 0.55 }, { 2.0, ORANGE, 0.35 } }) do
		S.disks[i] = { p = c.part({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = d[2], Transparency = 1, Size = Vector3.one, Parent = model }),
			k = d[1], tr = d[3] }
	end
	for i = 1, 18 do
		S.embers[i] = { p = c.part({ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = (i % 2 == 0) and ORANGE or MAGENTA,
			Size = Vector3.one * c.rng:NextNumber(0.6, 1.4), Parent = model }), a = c.rng:NextNumber(0, 6.28), r = c.rng:NextNumber(1.3, 3.8),
			w = c.rng:NextNumber(1.6, 3.2), y = c.rng:NextNumber(-0.12, 0.12) }
	end
	S.stream = c.part({ Transparency = 1, Size = Vector3.one * 90, Parent = model })
	S.inflow = c.emitter(S.stream, { rate = 0, shape = Enum.ParticleEmitterShape.Sphere, inout = Enum.ParticleEmitterShapeInOut.Inward,
		style = Enum.ParticleEmitterShapeStyle.Surface, life = NumberRange.new(1.1, 1.4), speed = NumberRange.new(30, 42),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 0.4) }), light = 1,
		color = ColorSequence.new(MAGENTA, PURPLE), texture = "rbxasset://textures/particles/sparkles_main.dds",
		tr = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.2), NumberSequenceKeypoint.new(1, 0.6) }) })
	S.light = Instance.new("PointLight")
	S.light.Color, S.light.Range, S.light.Brightness, S.light.Shadows = PURPLE, 60, 0, false
	S.light.Parent = S.core
	S.drone = c.sound(c.SND.drone, S.core, 0, 0.42, true, 520)
	S.hum = c.sound(c.SND.swell, S.core, 0, 0.3, true, 300)
	S.tilt = CFrame.Angles(math.rad(c.rng:NextNumber(14, 24)), c.rng:NextNumber(0, 6.28), 0)
	return S
end

function M.step(c, S, m, dt)
	S.t += dt
	local power = m:GetAttribute("Power") or 0
	if S.fading then
		power = S.fading
	end
	local pos = m.Position
	local size = CORE * power
	local at = CFrame.new(pos)
	S.core.Size = Vector3.one * math.max(size, 0.05)
	S.core.CFrame = at
	S.rim.Size = Vector3.one * math.max(size * 1.18, 0.05)
	S.rim.CFrame = at
	S.lens.Size = Vector3.one * math.max(size * 2.3, 0.05)
	S.lens.CFrame = at
	local disk = at * S.tilt * CFrame.Angles(0, S.t * 0.6, 0)
	for _, D in ipairs(S.disks) do
		local d = size * D.k
		D.p.Size = Vector3.new(0.3, math.max(d, 0.05), math.max(d, 0.05))
		D.p.CFrame = disk * CFrame.Angles(0, 0, math.pi / 2)
		D.p.Transparency = power > 0.02 and D.tr or 1
	end
	for _, E in ipairs(S.embers) do
		E.a += dt * E.w * (1 + 1.5 / E.r)
		local r = E.r * size * 0.55
		E.p.CFrame = disk * CFrame.new(math.cos(E.a) * r, E.y * size, math.sin(E.a) * r)
		E.p.Transparency = power > 0.05 and 0 or 1
	end
	S.stream.CFrame = at
	S.inflow.Rate = 90 * power
	S.light.Brightness = 4 * power
	S.light.Range = 40 + 50 * power
	S.drone.Volume = 2 * power
	S.hum.Volume = 0.6 * power
	if S.fading then
		return
	end
	local hrp, hum = c.root()
	if not hrp or hum.Health <= 0 or not c.onMap(m, hrp.Position, 60) then
		return
	end
	local reach = m:GetAttribute("Reach") or 250
	local off = pos - hrp.Position
	local d = off.Magnitude
	local near = math.clamp(1 - d / reach, 0, 1)
	c.grade(Color3.fromRGB(230, 214, 255), -0.08, 0.12, -0.25, near * power)
	c.shake(0.35 * near * power)
	if d >= reach or os.clock() < (S.freeAt or 0) then
		return
	end
	local core = (m:GetAttribute("Core") or 9) * 1.6
	if d < core and power > 0.5 then -- spat back out
		S.freeAt = os.clock() + 3
		local a = c.rng:NextNumber() * math.pi * 2
		c.tumble(Vector3.new(math.cos(a), 0.35, math.sin(a)).Unit * 120, 2)
		c.kick(1.2)
		return
	end
	local k = near ^ 0.6 * power
	if k < 0.08 then
		return
	end
	local want = off.Unit * (8 + 85 * k)
	local v = hrp.AssemblyLinearVelocity
	hrp.AssemblyLinearVelocity = v:Lerp(want, math.min(1, dt * (0.8 + 5 * k)))
end

function M.stop(c, S, m)
	holes[S.id] = nil
	S.fading = 0
	task.delay(0.2, function()
		S.model:Destroy()
	end)
end

M.fx.bhSwallow = function(c, d)
	if not holes[d.id] then
		return
	end
	local f = c.part({ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 220, 255), Transparency = 0.2,
		Size = Vector3.one * (d.small and 6 or 12), CFrame = CFrame.new(d.pos) })
	c.tween(f, 0.35, { Size = Vector3.one * 0.5, Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	c.Debris:AddItem(f, 0.4)
	if not d.small then
		c.soundAt(c.SND.whoosh, d.pos, 1, 0.55, 260)
	end
end

M.fx.bhCollapse = function(c, d)
	c.soundAt(c.SND.swell, d.pos, 1.6, 0.6, 600)
end

M.fx.bhBurst = function(c, d)
	local pos = d.pos
	local hrp = c.root()
	local dist = hrp and (hrp.Position - pos).Magnitude or 999
	c.kick(math.clamp(1.6 * (1 - dist / 300), 0.2, 1.6))
	c.soundAt(c.SND.boom, pos, 2, 0.5, 900)
	local flash = c.part({ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 235, 255), Size = Vector3.one * 4, CFrame = CFrame.new(pos) })
	c.tween(flash, 0.6, { Size = Vector3.one * 70, Transparency = 1 })
	c.Debris:AddItem(flash, 0.7)
	local ring = c.part({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = PURPLE, Transparency = 0.2,
		Size = Vector3.new(1.5, 8, 8), CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2) })
	c.tween(ring, 1.4, { Size = Vector3.new(0.5, 420, 420), Transparency = 1 })
	c.Debris:AddItem(ring, 1.5)
	local ring2 = c.part({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = MAGENTA, Transparency = 0.3,
		Size = Vector3.new(1, 6, 6), CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(70), 0, math.pi / 2) })
	c.tween(ring2, 1.1, { Size = Vector3.new(0.4, 260, 260), Transparency = 1 })
	c.Debris:AddItem(ring2, 1.2)
end

return M
