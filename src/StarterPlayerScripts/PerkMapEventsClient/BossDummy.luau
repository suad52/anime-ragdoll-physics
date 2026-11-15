--!nocheck
-- PerkMapEventsClient.BossDummy: the boss is a server dummy with its own health bar. Here: its one-shot effects -
-- bossWarn (a red ring pulsing on the ground where it will land / stomp), bossStomp (a shockwave ring, a dust wall,
-- stones, a shake by distance), bossRoar (a red pulse at the screen's edge, a shake, a deep roar), bossSwat (a whoosh
-- and a hit), bossDown (it crashes down: dust and a big shake) and bossSink (dust as it sinks away).
local M = { fx = {} }
local RED = Color3.fromRGB(255, 50, 50)
local DUST = Color3.fromRGB(170, 150, 122)

function M.start(c, m)
	return {}
end

local function distTo(c, pos)
	local hrp = c.root()
	return hrp and (hrp.Position - pos).Magnitude or 9999
end

local function ring(c, pos, d0, d1, t, color, tr, thick)
	local g = c.ground(pos.X, pos.Z, pos.Y + 20)
	local r = c.part({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = color, Transparency = tr or 0.2,
		Size = Vector3.new(thick or 0.4, d0, d0), CFrame = CFrame.new(g + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.pi / 2) })
	c.tween(r, t, { Size = Vector3.new(thick or 0.4, d1, d1), Transparency = 1 })
	c.Debris:AddItem(r, t + 0.1)
	return r
end

M.fx.bossWarn = function(c, d)
	if typeof(d.pos) ~= "Vector3" or distTo(c, d.pos) > 500 then
		return
	end
	local r = (d.r or 40) * 2
	local g = c.ground(d.pos.X, d.pos.Z, d.pos.Y + 20)
	local disc = c.part({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = RED, Transparency = 0.75,
		Size = Vector3.new(0.2, r, r), CFrame = CFrame.new(g + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2) })
	local t = d.t or 1
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < t do
			local a = (os.clock() - t0) / t
			disc.Transparency = 0.55 + 0.3 * math.abs(math.sin(a * 18))
			task.wait()
		end
		disc:Destroy()
	end)
	ring(c, d.pos, r, r * 0.1, t, RED, 0.1, 0.6)
end

M.fx.bossStomp = function(c, d)
	if typeof(d.pos) ~= "Vector3" then
		return
	end
	local dist = distTo(c, d.pos)
	if dist > 600 then
		return
	end
	local r = (d.r or 40) * 2
	c.kick(math.clamp(1.8 * (1 - dist / 220), 0.15, 1.8))
	ring(c, d.pos, 6, r * 1.15, 0.6, Color3.fromRGB(255, 230, 190), 0.1, 1.2)
	ring(c, d.pos, 4, r * 0.8, 0.45, RED, 0.3, 0.6)
	local g = c.ground(d.pos.X, d.pos.Z, d.pos.Y + 20)
	local p = c.part({ Transparency = 1, Size = Vector3.new(r * 0.5, 1, r * 0.5), CFrame = CFrame.new(g + Vector3.new(0, 1, 0)) })
	local e = c.emitter(p, { life = NumberRange.new(1, 1.8), speed = NumberRange.new(18, 34), dir = Enum.NormalId.Top, spread = Vector2.new(75, 75),
		size = NumberSequence.new(4, 10), drag = 2, accel = Vector3.new(0, 4, 0), color = ColorSequence.new(DUST, Color3.fromRGB(130, 118, 100)) })
	e:Emit(60)
	c.Debris:AddItem(p, 2.5)
	for _ = 1, 10 do
		local s = c.rng:NextNumber(0.8, 2)
		local rock = Instance.new("Part")
		rock.Size = Vector3.new(s, s, s)
		rock.Color, rock.Material = Color3.fromRGB(96, 84, 72), Enum.Material.Slate
		rock.CanCollide, rock.CanQuery, rock.CanTouch, rock.CastShadow = false, false, false, false
		rock.CFrame = CFrame.new(g + Vector3.new(c.rng:NextNumber(-8, 8), 1, c.rng:NextNumber(-8, 8)))
		rock.Parent = c.folder
		rock.AssemblyLinearVelocity = Vector3.new(c.rng:NextNumber(-30, 30), c.rng:NextNumber(30, 60), c.rng:NextNumber(-30, 30))
		rock.AssemblyAngularVelocity = Vector3.new(c.rng:NextNumber(-10, 10), c.rng:NextNumber(-10, 10), c.rng:NextNumber(-10, 10))
		c.Debris:AddItem(rock, 2)
	end
	c.soundAt(c.SND.boom, g, 2, 0.45, 700)
end

local function vignette(c, color, t)
	local gui = Instance.new("ScreenGui")
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 4
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 0.55
	f.BorderSizePixel = 0
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.25, 1), NumberSequenceKeypoint.new(0.75, 1), NumberSequenceKeypoint.new(1, 0) })
	g.Parent = f
	local g2 = f:Clone()
	g2:FindFirstChildOfClass("UIGradient").Rotation = 90
	f.Parent = gui
	g2.Parent = gui
	gui.Parent = c.player:WaitForChild("PlayerGui")
	c.tween(f, t, { BackgroundTransparency = 1 })
	c.tween(g2, t, { BackgroundTransparency = 1 })
	c.Debris:AddItem(gui, t + 0.1)
end

M.fx.bossRoar = function(c, d)
	if typeof(d.pos) ~= "Vector3" then
		return
	end
	local dist = distTo(c, d.pos)
	if dist > 500 then
		return
	end
	c.kick(math.clamp(1.2 * (1 - dist / 300), 0.2, 1.2))
	vignette(c, RED, 1.2)
	c.soundAt(c.SND.swell, d.pos, 2.5, 0.22, 700)
	c.soundAt(c.SND.drone, d.pos, 2, 0.35, 700)
end

M.fx.bossSwat = function(c, d)
	if typeof(d.pos) ~= "Vector3" then
		return
	end
	c.soundAt(c.SND.whoosh, d.pos, 1.2, 0.6, 200)
	if distTo(c, d.pos) < 8 then
		c.kick(1.2)
		vignette(c, Color3.fromRGB(255, 255, 255), 0.4)
	end
end

M.fx.bossDown = function(c, d)
	if typeof(d.pos) ~= "Vector3" then
		return
	end
	local dist = distTo(c, d.pos)
	c.kick(math.clamp(1.6 * (1 - dist / 300), 0.2, 1.6))
	task.delay(0.6, function()
		M.fx.bossStomp(c, { pos = d.pos, r = 30 })
	end)
end

M.fx.bossSink = function(c, d)
	if typeof(d.pos) ~= "Vector3" then
		return
	end
	local g = c.ground(d.pos.X, d.pos.Z, d.pos.Y + 20)
	local p = c.part({ Transparency = 1, Size = Vector3.new(16, 1, 16), CFrame = CFrame.new(g + Vector3.new(0, 1, 0)) })
	local e = c.emitter(p, { rate = 60, life = NumberRange.new(1, 2), speed = NumberRange.new(4, 10), dir = Enum.NormalId.Top, spread = Vector2.new(60, 60),
		size = NumberSequence.new(4, 9), color = ColorSequence.new(DUST) })
	task.delay(2, function()
		e.Enabled = false
	end)
	c.Debris:AddItem(p, 4.5)
	c.soundAt(c.SND.drone, g, 1.5, 0.3, 400)
end

return M
