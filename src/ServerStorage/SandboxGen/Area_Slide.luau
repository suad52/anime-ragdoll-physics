--!nocheck
-- MEGA SLIDE: a spiral staircase round a concrete core up to a deck 84 studs up, and a helter-skelter slide winding back
-- down round the tower into a splash pool. The slide floor is a conveyor (tag Conveyor) so bodies always keep moving.
local function station(K, model, cf, kind, every, max, extra)
	local attrs = { Kind = kind, Every = every or 8, Max = max or 1 }
	for k, v in pairs(extra or {}) do
		attrs[k] = v
	end
	return K.part(model, "Station", Vector3.new(2, 0.2, 2), cf, nil, nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, tag = "DummyStation", attrs = attrs })
end
return function(K, model, cf, A)
	local PAL, C = K.PAL, K.C
	local T = cf * CFrame.new(0, 0.4, 4)
	local N, RISE, STEP = 104, 0.8, math.rad(12)
	local H = 0.4 + N * RISE
	local function ring(theta, r, y)
		return T * CFrame.Angles(0, theta, 0) * CFrame.new(r, y, 0)
	end
	K.cyl(model, "Core", 16, H, T * CFrame.new(0, H / 2, 0), C(168, 164, 156), Enum.Material.Concrete)
	for b = 1, 5 do
		K.cyl(model, "Band", 16.3, 1.2, T * CFrame.new(0, b * H / 6, 0), (b % 2 == 0) and PAL.hazard or PAL.steelDark, Enum.Material.Metal, { CastShadow = false })
	end
	K.cyl(model, "Foot", 31, 0.6, T * CFrame.new(0, 0.3, 0), PAL.concreteDark)
	local stairs = K.model(model, "Stairs")
	local lastPost
	for i = 0, N - 1 do
		local y = 0.4 + i * RISE
		K.part(stairs, "Step", Vector3.new(6, 0.7, 3.5), ring(i * STEP, 11, y), (i % 2 == 0) and PAL.steel or C(110, 116, 126), Enum.Material.DiamondPlate)
		if i % 3 == 0 and i < N - 3 then
			local top = ring(i * STEP, 14.2, y + 3.6).Position
			K.cyl(stairs, "Post", 0.3, 3.6, ring(i * STEP, 14.2, y + 1.8), PAL.hazard, Enum.Material.Metal, { CastShadow = false })
			if lastPost then
				K.part(stairs, "Rail", Vector3.new(0.28, 0.28, (top - lastPost).Magnitude + 0.2), CFrame.lookAt((top + lastPost) / 2, top), PAL.hazard, Enum.Material.Metal, { CastShadow = false })
			end
			lastPost = top
		end
	end
	-- the deck: the core's top plus three quarters of a ring (the open quarter is where the stairs arrive)
	local deck = K.model(model, "Deck")
	local t0 = (N - 1) * STEP + math.rad(12)
	K.cyl(deck, "CoreTop", 16.6, 0.6, T * CFrame.new(0, H - 0.3, 0), PAL.steel, Enum.Material.DiamondPlate)
	local SEG, slideK = 18, 10
	local prevTop
	for k = 0, SEG - 1 do
		local th = t0 + k * math.rad(15)
		K.part(deck, "Deck", Vector3.new(7.6, 0.8, 4.3), ring(th, 11.6, H - 0.4), PAL.steel, Enum.Material.DiamondPlate)
		local top = ring(th, 15.1, H + 3.6).Position
		if k ~= slideK and k ~= slideK - 1 then
			K.cyl(deck, "Post", 0.3, 3.6, ring(th, 15.1, H + 1.8), PAL.hazard, Enum.Material.Metal, { CastShadow = false })
			if prevTop then
				K.part(deck, "Rail", Vector3.new(0.28, 0.28, (top - prevTop).Magnitude + 0.2), CFrame.lookAt((top + prevTop) / 2, top), PAL.hazard, Enum.Material.Metal, { CastShadow = false })
			end
			prevTop = top
		else
			prevTop = nil
		end
	end
	K.sign(deck, "SLIDE THIS WAY", ring(t0 + (slideK - 0.5) * math.rad(15), 15.2, H + 6.4) * CFrame.Angles(0, math.rad(90), 0), Vector2.new(9, 1.8), { trim = PAL.hazard, pps = 26 })
	-- the slide
	local slide = K.model(model, "Slide")
	local ths = t0 + (slideK - 0.5) * math.rad(15)
	local M = 76
	local pts = {}
	for j = 0, M do
		local f = j / M
		pts[j] = ring(ths + j * math.rad(8), 17.4 + 17 * f, H - 0.5 - (H - 4.2) * f).Position
	end
	K.part(slide, "Entry", Vector3.new(5, 0.6, 9), ring(ths, 16, H - 0.3), PAL.hazard, Enum.Material.SmoothPlastic)
	for j = 0, M - 1 do
		local a, b = pts[j], pts[j + 1]
		local c = CFrame.lookAt((a + b) / 2, b)
		local len = (b - a).Magnitude + 0.7
		K.part(slide, "Chute", Vector3.new(9, 0.6, len), c, (j % 2 == 0) and PAL.hazard or C(250, 214, 80), Enum.Material.SmoothPlastic, { tag = "Conveyor", attrs = { Conveyor = 46 },
			CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.02, 0.1, 100, 1) })
		for _, x in ipairs({ -4.6, 4.6 }) do
			K.part(slide, "Wall", Vector3.new(0.6, 3.4, len), c * CFrame.new(x, 1.7, 0), PAL.red, Enum.Material.SmoothPlastic)
		end
		if j % 5 == 2 then
			local mid = (a + b) / 2
			local hgt = mid.Y - 0.5 - T.Position.Y
			K.cyl(slide, "Support", 1.3, hgt, CFrame.new(mid.X, T.Position.Y + hgt / 2, mid.Z), PAL.steelDark, Enum.Material.Metal)
		end
	end
	-- splash pool at the bottom
	local dir = ((pts[M] - pts[M - 1]) * Vector3.new(1, 0, 1)).Unit
	local pc = pts[M] + dir * 12
	pc = Vector3.new(pc.X, T.Position.Y - 0.4, pc.Z)
	local terrain = workspace.Terrain
	terrain:FillCylinder(CFrame.new(pc.X, pc.Y - 4, pc.Z), 8, 14.5, Enum.Material.Air)
	terrain:FillCylinder(CFrame.new(pc.X, pc.Y - 4.6, pc.Z), 6, 14.5, Enum.Material.Water)
	K.cyl(slide, "PoolFloor", 31, 0.6, CFrame.new(pc.X, pc.Y - 8, pc.Z), C(70, 150, 200), Enum.Material.SmoothPlastic)
	for k = 0, 23 do
		local a = k / 24 * math.pi * 2
		local p = pc + Vector3.new(math.sin(a) * 15.6, 0.5, -math.cos(a) * 15.6)
		K.part(slide, "PoolRim", Vector3.new(4.3, 1.8, 2.4), CFrame.lookAt(p, Vector3.new(pc.X, p.Y, pc.Z)), (k % 2 == 0) and PAL.white or PAL.blue, Enum.Material.SmoothPlastic)
	end
	station(K, model, CFrame.new(pts[2] + Vector3.new(0, 1.2, 0)), "slide", 11, 3)
	station(K, model, cf * CFrame.new(-30, 0.5, -40), "stand", 7, 1)
	station(K, model, cf * CFrame.new(-24, 0.5, -44), "stand", 7, 1)
end
