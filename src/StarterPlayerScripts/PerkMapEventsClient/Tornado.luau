--!nocheck
-- PerkMapEventsClient.Tornado: the funnel (stacked spinning translucent rings, smoke, a dust skirt, orbiting debris,
-- a roar) following the marker, and the pull on MY character: inside Radius it is dragged round and up, and thrown
-- out of the top in a tumble.
local M = {}
local RINGS = 15

function M.start(c, m)
	local S = { rings = {}, debris = {}, t = 0, pos = m.Position, a = 0 }
	local model = Instance.new("Model")
	model.Name = "Tornado"
	model.Parent = c.folder
	S.model = model
	for i = 1, RINGS do
		local d = 7 + i * 5.4
		local k = i / RINGS
		local r = c.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.6, d, d), Parent = model,
			Color = Color3.fromRGB(72, 76, 86):Lerp(Color3.fromRGB(176, 182, 194), k), Transparency = 1 })
		S.rings[i] = { p = r, d = d, tr = 0.42 + 0.3 * k }
		if i % 4 == 2 then
			c.emitter(r, { rate = 18, life = NumberRange.new(1.2, 2), speed = NumberRange.new(2, 7), size = NumberSequence.new(d * 0.18, d * 0.32),
				color = ColorSequence.new(Color3.fromRGB(110, 114, 124), Color3.fromRGB(160, 164, 174)),
				tr = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }), rot = NumberRange.new(-120, 120) })
		end
	end
	local skirt = c.part({ Size = Vector3.new(30, 1, 30), Transparency = 1, Parent = model })
	S.skirt = skirt
	S.dust = c.emitter(skirt, { rate = 40, life = NumberRange.new(1, 1.8), speed = NumberRange.new(14, 26), spread = Vector2.new(70, 70),
		dir = Enum.NormalId.Top, size = NumberSequence.new(4, 11), accel = Vector3.new(0, 6, 0), drag = 1.5,
		color = ColorSequence.new(Color3.fromRGB(150, 128, 98), Color3.fromRGB(120, 110, 96)), rot = NumberRange.new(-200, 200) })
	for i = 1, 16 do
		local s = c.rng:NextNumber(0.6, 1.8)
		local p = c.part({ Size = Vector3.new(s, s * 0.6, s * 1.2), Parent = model,
			Material = (i % 3 == 0) and Enum.Material.WoodPlanks or Enum.Material.Slate,
			Color = (i % 3 == 0) and Color3.fromRGB(140, 104, 66) or Color3.fromRGB(90, 86, 82) })
		S.debris[i] = { p = p, h = c.rng:NextNumber(2, 58), r = c.rng:NextNumber(6, 30), a = c.rng:NextNumber(0, 6.28), w = c.rng:NextNumber(2.5, 5),
			spin = Vector3.new(c.rng:NextNumber(-6, 6), c.rng:NextNumber(-6, 6), c.rng:NextNumber(-6, 6)) }
	end
	S.roar = c.sound(c.SND.flow, skirt, 0, 0.5, true, 340)
	S.drone = c.sound(c.SND.drone, skirt, 0, 0.7, true, 300)
	S.fadeIn = 0
	return S
end

function M.step(c, S, m, dt)
	S.t += dt
	S.fadeIn = math.min(1, S.fadeIn + dt / 1.5)
	local f = S.fading or S.fadeIn
	S.pos = S.pos:Lerp(m.Position, 1 - math.exp(-dt * 6))
	local base = S.pos
	for i, R in ipairs(S.rings) do
		local sway = Vector3.new(math.sin(S.t * 1.4 + i * 0.45), 0, math.cos(S.t * 1.1 + i * 0.5)) * i * 0.45
		R.p.CFrame = CFrame.new(base + sway + Vector3.new(0, i * 4.1 - 1, 0)) * CFrame.Angles(0, S.t * (5 - i * 0.15) + i, math.pi / 2)
		R.p.Transparency = 1 - (1 - R.tr) * f
	end
	S.skirt.CFrame = CFrame.new(base + Vector3.new(0, 0.6, 0))
	S.dust.Rate = 40 * f
	for _, D in ipairs(S.debris) do
		D.a += dt * D.w
		local r = D.r * (0.6 + D.h / 70)
		D.p.CFrame = CFrame.new(base + Vector3.new(math.cos(D.a) * r, D.h, math.sin(D.a) * r)) * CFrame.Angles(D.spin.X * S.t, D.spin.Y * S.t, D.spin.Z * S.t)
		D.p.Transparency = 1 - f
	end
	S.roar.Volume = 1.5 * f
	S.drone.Volume = 0.7 * f
	if S.fading then
		return
	end
	local hrp, hum = c.root()
	if not hrp or hum.Health <= 0 or not c.onMap(m, hrp.Position) then
		return
	end
	local R = m:GetAttribute("Radius") or 60
	local TOP = m:GetAttribute("Top") or 58
	local off = (hrp.Position - base) * c.FLAT
	local dist = math.max(off.Magnitude, 1)
	local h = hrp.Position.Y - base.Y
	if dist < R * 1.5 then
		c.shake(0.55 * (1 - dist / (R * 1.5)))
	end
	if os.clock() < (S.freeAt or 0) or dist >= R or h > TOP + 25 then
		return
	end
	local pull = math.clamp(1 - dist / R, 0, 1)
	if pull < 0.18 then
		return -- the edge: you can still walk out of it
	end
	local radial = off / dist
	local tang = c.UP:Cross(radial)
	if h > TOP then
		S.freeAt = os.clock() + 2
		c.tumble(radial * 70 + tang * 25 + c.UP * 14, 1.6)
		return
	end
	local want = tang * (34 + 46 * pull) - radial * 22 * pull + c.UP * (16 + 34 * pull)
	local v = hrp.AssemblyLinearVelocity
	hrp.AssemblyLinearVelocity = v:Lerp(want, math.min(1, dt * (2 + 9 * pull)))
	hrp.AssemblyAngularVelocity = Vector3.new(0, 6 * pull, 0)
end

function M.stop(c, S, m)
	S.fading = 1
	task.spawn(function()
		for i = 1, 20 do
			S.fading = 1 - i / 20
			local ok = pcall(M.step, c, S, m, 0.05)
			if not ok then
				break
			end
			task.wait(0.05)
		end
		S.model:Destroy()
	end)
end

return M
