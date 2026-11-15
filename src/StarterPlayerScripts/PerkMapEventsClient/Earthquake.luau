--!nocheck
-- PerkMapEventsClient.Earthquake: while it runs and I am on that map - the camera shakes, the ground rumbles, dust
-- kicks up round my feet, my character is bounced and now and then thrown off its feet. MapEventFX "fissure": a crack
-- tears open along a line (dark gashes, raised lips of rock, a dust burst, flying stones) and closes up again.
local M = { fx = {} }
local ROCK = Color3.fromRGB(96, 84, 72)
local DARK = Color3.fromRGB(26, 20, 18)

local function strength(c, m)
	local now = c.now()
	return math.clamp((now - (m:GetAttribute("T0") or now)) / 1.5, 0, 1) * math.clamp(((m:GetAttribute("Ends") or now) - now) / 2, 0, 1)
end

function M.start(c, m)
	local S = { nextHop = 0 }
	S.anchor = c.part({ Transparency = 1, Size = Vector3.new(14, 1, 14) })
	S.dust = c.emitter(S.anchor, { rate = 0, life = NumberRange.new(0.8, 1.5), speed = NumberRange.new(3, 9), dir = Enum.NormalId.Top, spread = Vector2.new(60, 60),
		size = NumberSequence.new(1.5, 4.5), accel = Vector3.new(0, 3, 0), color = ColorSequence.new(Color3.fromRGB(170, 150, 120), Color3.fromRGB(130, 118, 100)) })
	S.rumble = c.sound(c.SND.drone, S.anchor, 0, 0.45, true, 400)
	S.rumble2 = c.sound(c.SND.flow, S.anchor, 0, 0.3, true, 400)
	return S
end

function M.step(c, S, m, dt)
	local hrp, hum = c.root()
	local k = strength(c, m)
	local here = hrp and c.onMap(m, hrp.Position)
	if not here then
		S.rumble.Volume, S.rumble2.Volume, S.dust.Rate = 0, 0, 0
		return
	end
	S.anchor.CFrame = CFrame.new(hrp.Position - Vector3.new(0, 2.8, 0))
	S.rumble.Volume = 1.6 * k
	S.rumble2.Volume = 0.9 * k
	S.dust.Rate = 26 * k
	c.shake(0.5 * k)
	c.grade(Color3.fromRGB(255, 236, 214), -0.02, 0.06, -0.1, 0.6 * k)
	if hum.Health <= 0 or c.tumbling() then
		return
	end
	local now = os.clock()
	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	if grounded and now >= S.nextHop and k > 0.2 then
		S.nextHop = now + c.rng:NextNumber(0.45, 1.1) / math.max(k, 0.3)
		local v = hrp.AssemblyLinearVelocity
		hrp.AssemblyLinearVelocity = Vector3.new(v.X + c.rng:NextNumber(-5, 5), math.max(v.Y, 0) + c.rng:NextNumber(9, 17) * k, v.Z + c.rng:NextNumber(-5, 5))
		if c.rng:NextNumber() < 0.09 * k then -- thrown off your feet
			local a = c.rng:NextNumber() * math.pi * 2
			c.tumble(Vector3.new(math.cos(a) * 14, 12, math.sin(a) * 14), 1)
		end
	end
end

function M.stop(c, S, m)
	c.tween(S.rumble, 1.5, { Volume = 0 })
	c.tween(S.rumble2, 1.5, { Volume = 0 })
	S.dust.Rate = 0
	c.Debris:AddItem(S.anchor, 2)
end

M.fx.fissure = function(c, d)
	local pos, dir, len = d.pos, d.dir, d.len or 30
	if typeof(pos) ~= "Vector3" or typeof(dir) ~= "Vector3" then
		return
	end
	local hrp = c.root()
	local dist = hrp and (hrp.Position - pos).Magnitude or 999
	if dist > 600 then
		return
	end
	c.kick(math.clamp(1.4 * (1 - dist / 160), 0, 1.4))
	local rnd = Random.new(d.seed or 1)
	local model = Instance.new("Model")
	model.Name = "Fissure"
	model.Parent = c.folder
	local side = c.UP:Cross(dir).Unit
	local n = math.max(6, math.floor(len / 4))
	local start = pos - dir * len / 2
	local last = start
	local parts = {}
	for i = 1, n do
		local a = i / n
		local wob = (i < n) and rnd:NextNumber(-1.6, 1.6) or 0
		local nxt = start + dir * len * a + side * wob
		local g = c.ground(nxt.X, nxt.Z, nxt.Y + 20)
		nxt = Vector3.new(nxt.X, g.Y, nxt.Z)
		local mid = (last + nxt) / 2
		local w = (1 - math.abs(a - 0.5) * 1.6) * rnd:NextNumber(1.6, 2.8)
		local seg = c.part({ Size = Vector3.new(math.max(w, 0.4), 0.3, (nxt - last).Magnitude + 0.6), Color = DARK, Material = Enum.Material.Slate, Parent = model })
		seg.CFrame = CFrame.lookAt(mid + Vector3.new(0, 0.06, 0), nxt + Vector3.new(0, 0.06, 0))
		table.insert(parts, seg)
		for _, s in ipairs({ -1, 1 }) do
			local lip = c.part({ Size = Vector3.new(rnd:NextNumber(1.2, 2.4), rnd:NextNumber(0.5, 1.1), (nxt - last).Magnitude * 0.9),
				Color = ROCK, Material = Enum.Material.Slate, Parent = model })
			lip.CFrame = CFrame.lookAt(mid, nxt) * CFrame.new(s * (w / 2 + 0.6), 0.2, 0) * CFrame.Angles(0, 0, s * math.rad(rnd:NextNumber(14, 30)))
			table.insert(parts, lip)
		end
		last = nxt
	end
	local burst = c.part({ Transparency = 1, Size = Vector3.new(4, 1, len), CFrame = CFrame.lookAt(pos, pos + dir) * CFrame.new(0, 0.5, 0) })
	local e = c.emitter(burst, { life = NumberRange.new(1.2, 2.2), speed = NumberRange.new(10, 26), dir = Enum.NormalId.Top, spread = Vector2.new(35, 35),
		size = NumberSequence.new(3, 9), accel = Vector3.new(0, -6, 0), drag = 1.2, color = ColorSequence.new(Color3.fromRGB(176, 154, 122), Color3.fromRGB(128, 116, 100)) })
	e:Emit(math.floor(len * 1.6))
	c.Debris:AddItem(burst, 3)
	for _ = 1, 8 do
		local s = rnd:NextNumber(0.6, 1.6)
		local at = pos + dir * rnd:NextNumber(-len / 2, len / 2) + Vector3.new(0, 1, 0)
		local r = Instance.new("Part")
		r.Size = Vector3.new(s, s, s)
		r.Color, r.Material = ROCK, Enum.Material.Slate
		r.CanCollide, r.CanQuery, r.CanTouch, r.CastShadow = false, false, false, false
		r.CFrame = CFrame.new(at) * CFrame.Angles(rnd:NextNumber(0, 6), rnd:NextNumber(0, 6), 0)
		r.Parent = c.folder
		r.AssemblyLinearVelocity = Vector3.new(rnd:NextNumber(-14, 14), rnd:NextNumber(30, 55), rnd:NextNumber(-14, 14))
		r.AssemblyAngularVelocity = Vector3.new(rnd:NextNumber(-12, 12), rnd:NextNumber(-12, 12), rnd:NextNumber(-12, 12))
		c.Debris:AddItem(r, 2)
	end
	c.soundAt(c.SND.crack, pos, 1.4, 0.6, 320)
	task.delay(7, function()
		for _, p in ipairs(parts) do
			if p.Parent then
				c.tween(p, 2.5, { Transparency = 1 })
			end
		end
		task.wait(2.6)
		model:Destroy()
	end)
end

return M
