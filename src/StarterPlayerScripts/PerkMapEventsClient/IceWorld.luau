--!nocheck
-- PerkMapEventsClient.IceWorld: while I am on the frozen map - a cold grade, snow blowing round me, frost creeping in
-- at the screen's edges, a cold wind - and MY character slides: standing on Material.Ice (the server's ice sheet), my
-- speed only slowly follows what I steer, so I glide on, overshoot and drift through turns; a hard turn at speed can
-- take my feet out from under me.
local M = {}

function M.start(c, m)
	local S = { k = 0, iceVel = Vector3.zero }
	S.snowPart = c.part({ Transparency = 1, Size = Vector3.new(90, 1, 90) })
	S.snow = c.emitter(S.snowPart, { rate = 0, texture = "rbxasset://textures/particles/sparkles_main.dds", life = NumberRange.new(3, 5),
		speed = NumberRange.new(6, 12), dir = Enum.NormalId.Bottom, spread = Vector2.new(25, 25), size = NumberSequence.new(0.25, 0.45),
		accel = Vector3.new(4, 0, 2), color = ColorSequence.new(Color3.fromRGB(255, 255, 255)), light = 0.4,
		tr = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.85, 0.2), NumberSequenceKeypoint.new(1, 1) }) })
	S.wind = c.sound(c.SND.flow, S.snowPart, 0, 1.6, true, 400)
	local gui = Instance.new("ScreenGui")
	gui.Name = "IceFrost"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 3
	S.edges = {}
	for _, e in ipairs({ { UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.22), 90 }, { UDim2.fromScale(0, 0.78), UDim2.fromScale(1, 0.22), 270 },
		{ UDim2.fromScale(0, 0), UDim2.fromScale(0.16, 1), 0 }, { UDim2.fromScale(0.84, 0), UDim2.fromScale(0.16, 1), 180 } }) do
		local f = Instance.new("Frame")
		f.Position, f.Size = e[1], e[2]
		f.BackgroundColor3 = Color3.fromRGB(225, 242, 255)
		f.BorderSizePixel = 0
		f.BackgroundTransparency = 1
		local g = Instance.new("UIGradient")
		g.Rotation = e[3]
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.6, 0.85), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = f
		f.Parent = gui
		table.insert(S.edges, f)
	end
	gui.Parent = c.player:WaitForChild("PlayerGui")
	S.gui = gui
	return S
end

function M.step(c, S, m, dt)
	local hrp, hum = c.root()
	local here = hrp and c.onMap(m, hrp.Position, 20) and not S.fading
	S.k += ((here and 1 or 0) - S.k) * (1 - math.exp(-dt * 1.5))
	local k = S.k
	c.grade(Color3.fromRGB(214, 236, 255), 0.03, 0.08, -0.25, k)
	S.snow.Rate = 140 * k
	S.wind.Volume = 0.45 * k
	for _, f in ipairs(S.edges) do
		f.BackgroundTransparency = 1 - k
	end
	local cam = workspace.CurrentCamera
	if cam then
		S.snowPart.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 24, 0))
	end
	if not here or hum.Health <= 0 then
		S.iceVel = hrp and (hrp.AssemblyLinearVelocity * c.FLAT) or Vector3.zero
		return
	end
	local v = hrp.AssemblyLinearVelocity
	local flat = v * c.FLAT
	if hum.FloorMaterial ~= Enum.Material.Ice or c.tumbling() or hum.PlatformStand then
		S.iceVel = flat -- off the ice (or in the air): keep whatever speed we leave with
		return
	end
	local want = hum.MoveDirection * hum.WalkSpeed
	local sp = S.iceVel.Magnitude
	if sp > 22 and want.Magnitude > 1 and S.iceVel.Unit:Dot(want.Unit) < -0.3 and c.rng:NextNumber() < dt * 1.2 then
		c.tumble(S.iceVel * 0.8 + c.UP * 9, 1.1)
		return
	end
	-- steering grips a little; letting go you coast a long way (playtest: 1.1 both ways stopped in ~7 studs)
	local grip = want.Magnitude > 0.5 and 1.1 or 0.45
	S.iceVel = S.iceVel:Lerp(want, 1 - math.exp(-dt * grip))
	hrp.AssemblyLinearVelocity = Vector3.new(S.iceVel.X, v.Y, S.iceVel.Z)
end

function M.stop(c, S, m)
	S.fading = true
	task.spawn(function()
		for _ = 1, 30 do
			pcall(M.step, c, S, m, 0.1)
			task.wait(0.1)
		end
		S.snowPart:Destroy()
		S.gui:Destroy()
	end)
end

return M
