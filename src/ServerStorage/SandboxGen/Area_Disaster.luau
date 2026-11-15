--!nocheck
-- DISASTER BOX: a 60x36x60 glass test chamber. The floor carries tag DisasterBox + attribute Inner (the inside size);
-- the buttons on the console (tag DisasterButton, attribute Kind) start a tornado / quake / meteors / lightning / flood
-- - any number at once - and the red button on the pedestal beside it (Kind = "End") stops whatever is running.
local function station(K, model, cf, kind, every, max, extra)
	local attrs = { Kind = kind, Every = every or 8, Max = max or 1 }
	for k, v in pairs(extra or {}) do
		attrs[k] = v
	end
	return K.part(model, "Station", Vector3.new(2, 0.2, 2), cf, nil, nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, tag = "DummyStation", attrs = attrs })
end
return function(K, model, cf, A)
	local PAL, C = K.PAL, K.C
	local function L(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	local W, HT = 60, 36
	local floor = K.part(model, "DisasterFloor", Vector3.new(W + 2, 1.2, W + 2), L(0, 1, 4), C(72, 76, 86), Enum.Material.Concrete, { tag = "DisasterBox", attrs = { Inner = Vector3.new(W, HT, W) } })
	for ix = -2, 2 do -- floor grid lines
		K.part(model, "Grid", Vector3.new(0.3, 0.06, W), L(ix * 12, 1.63, 4), PAL.hazard, Enum.Material.SmoothPlastic, { CastShadow = false, Transparency = 0.3 })
		K.part(model, "Grid", Vector3.new(W, 0.06, 0.3), L(0, 1.63, 4 + ix * 12), PAL.hazard, Enum.Material.SmoothPlastic, { CastShadow = false, Transparency = 0.3 })
	end
	local hw = W / 2 + 0.5
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		K.part(model, "Column", Vector3.new(2, HT + 2, 2), L(c[1] * hw, 1.6 + (HT + 2) / 2, 4 + c[2] * hw), PAL.steelDark, Enum.Material.Metal)
		local bcn = K.ball(model, "DisasterLight", 2.2, L(c[1] * hw, HT + 4.8, 4 + c[2] * hw).Position, C(90, 230, 130), Enum.Material.Neon, { CastShadow = false, tag = "DisasterLight" })
		K.new("PointLight", { Range = 26, Brightness = 1.5, Color = C(90, 230, 130), Shadows = false }, bcn)
	end
	for _, s in ipairs({ { 0, -hw, W + 3, 2 }, { 0, hw, W + 3, 2 }, { -hw, 0, 2, W + 3 }, { hw, 0, 2, W + 3 } }) do
		K.part(model, "Beam", Vector3.new(s[3], 2, s[4]), L(s[1], HT + 2.6, 4 + s[2]), PAL.steelDark, Enum.Material.Metal)
	end
	local glassC = C(168, 206, 222)
	local function glass(size, c)
		-- (2026-11-13) NOT Material.Glass: Roblox does not draw a see-through part that sits behind Glass, so the flood,
		-- the tornado and an x-rayed body were all invisible from outside the box. Plain see-through plastic shows them.
		return K.part(model, "Glass", size, c, glassC, Enum.Material.SmoothPlastic, { Transparency = 0.8, Reflectance = 0.06, CastShadow = false })
	end
	glass(Vector3.new(W, HT, 0.6), L(0, 1.6 + HT / 2, 4 + hw))
	glass(Vector3.new(0.6, HT, W), L(-hw, 1.6 + HT / 2, 4))
	glass(Vector3.new(0.6, HT, W), L(hw, 1.6 + HT / 2, 4))
	glass(Vector3.new(W + 1, 0.6, W + 1), L(0, HT + 1.9, 4))
	local DW, DH = 12, 12
	glass(Vector3.new((W - DW) / 2, HT, 0.6), L(-(W + DW) / 4, 1.6 + HT / 2, 4 - hw))
	glass(Vector3.new((W - DW) / 2, HT, 0.6), L((W + DW) / 4, 1.6 + HT / 2, 4 - hw))
	glass(Vector3.new(DW, HT - DH, 0.6), L(0, 1.6 + DH + (HT - DH) / 2, 4 - hw))
	K.part(model, "DoorFrame", Vector3.new(DW + 1.6, 0.8, 1.4), L(0, 1.6 + DH + 0.4, 4 - hw), PAL.hazard, Enum.Material.Metal)
	K.part(model, "DisasterDoor", Vector3.new(DW, DH, 0.5), L(DW, 1.6 + DH / 2, 4 - hw - 0.6), C(190, 60, 50), Enum.Material.Metal, { Transparency = 0.25, tag = "DisasterDoor", attrs = { Slide = -DW } })
	K.wedge(model, "Ramp", Vector3.new(DW + 2, 1.6, 6), L(0, 0.8, 4 - hw - 3.6) * CFrame.Angles(0, math.pi, 0), PAL.steel, Enum.Material.DiamondPlate)
	-- console
	local con = K.model(model, "Console")
	K.part(con, "Desk", Vector3.new(24, 3.2, 3.6), L(0, 2, -42), PAL.steelDark, Enum.Material.Metal)
	K.part(con, "Top", Vector3.new(24, 0.5, 4.2), L(0, 3.9, -42.2) * CFrame.Angles(math.rad(-16), 0, 0), C(36, 40, 50), Enum.Material.SmoothPlastic)
	local kinds = { { "Tornado", C(150, 200, 230) }, { "Quake", C(190, 140, 90) }, { "Meteors", C(255, 120, 50) }, { "Lightning", C(250, 230, 90) }, { "Flood", C(70, 140, 230) } }
	for i, kd in ipairs(kinds) do
		local x = (i - 3) * 4.6
		local b = K.cyl(con, "DisasterButton", 2, 0.9, L(x, 4.5, -42.4) * CFrame.Angles(math.rad(-16), 0, 0), kd[2], Enum.Material.Neon, { tag = "DisasterButton", attrs = { Kind = kd[1] } })
		K.new("ProximityPrompt", { ActionText = "Start: " .. kd[1], ObjectText = "Disaster box", HoldDuration = 0.2, MaxActivationDistance = 7, RequiresLineOfSight = false, KeyboardKeyCode = Enum.KeyCode.K }, b)
		local tagP = K.part(con, "Tag", Vector3.new(4.2, 1.1, 0.2), L(x, 6.2, -40.9), K.SIGN_BLACK, Enum.Material.SmoothPlastic, { CastShadow = false })
		K.label(tagP, string.upper(kd[1]), { faces = { Enum.NormalId.Front }, color = kd[2], pps = 30 })
	end
	K.part(con, "TagBar", Vector3.new(24, 0.3, 0.3), L(0, 5.5, -40.9), PAL.steelDark, Enum.Material.Metal)
	for _, x in ipairs({ -11.5, 11.5 }) do
		K.part(con, "TagPost", Vector3.new(0.4, 3, 0.4), L(x, 5, -40.9), PAL.steelDark, Enum.Material.Metal)
	end
	-- (2026-11-13) the emergency stop, on its own pedestal so it cannot be mistaken for a sixth disaster
	local EX = -16
	K.part(con, "EndPost", Vector3.new(1.6, 3.6, 1.6), L(EX, 2, -42.2), PAL.steelDark, Enum.Material.Metal)
	K.part(con, "EndCollar", Vector3.new(3.2, 0.5, 3.2), L(EX, 3.9, -42.2) * CFrame.Angles(math.rad(-16), 0, 0), PAL.hazard, Enum.Material.Metal)
	local eb = K.cyl(con, "DisasterButton", 2.2, 0.9, L(EX, 4.5, -42.4) * CFrame.Angles(math.rad(-16), 0, 0), C(230, 40, 40), Enum.Material.Neon, { tag = "DisasterButton", attrs = { Kind = "End" } })
	K.new("ProximityPrompt", { ActionText = "End all", ObjectText = "Disaster box", HoldDuration = 0.2, MaxActivationDistance = 7, RequiresLineOfSight = false, KeyboardKeyCode = Enum.KeyCode.K }, eb)
	K.part(con, "EndTagPost", Vector3.new(0.4, 5.25, 0.4), L(EX, 3.025, -40.9), K.SIGN_BLACK, Enum.Material.Metal) -- stops under the tag
	local et = K.part(con, "Tag", Vector3.new(4.2, 1.1, 0.2), L(EX, 6.2, -40.9), K.SIGN_BLACK, Enum.Material.SmoothPlastic, { CastShadow = false })
	K.label(et, "END ALL", { faces = { Enum.NormalId.Front }, pps = 30 })
	local screen = K.part(model, "DisasterScreen", Vector3.new(22, 4, 0.5), L(0, 1.6 + DH + 4, 4 - hw - 0.6), C(10, 14, 20), Enum.Material.SmoothPlastic)
	K.label(screen, "STANDBY", { screen = true, faces = { Enum.NormalId.Front }, glow = true, color = C(120, 255, 160), font = Enum.Font.Code })
	local rng = Random.new(11)
	for i = 1, 6 do
		station(K, model, L(rng:NextNumber(-22, 22), 1.9, 4 + rng:NextNumber(-22, 22)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), "stand", 9, 1)
	end
end
