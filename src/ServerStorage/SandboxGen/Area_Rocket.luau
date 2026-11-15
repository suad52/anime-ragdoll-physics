--!nocheck
-- ROCKET PAD: strap a dummy to the hull at the console, press LAUNCH, watch it leave. The rocket is one anchored Model
-- (tag Rocket); ServerScriptService.Sandbox flies it by pivoting the model, so a strapped body rides along.
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
	K.cyl(model, "PadDisc", 62, 0.5, L(0, 0.45, 6), C(74, 74, 78), Enum.Material.Concrete)
	K.cyl(model, "PadRing", 46, 0.54, L(0, 0.45, 6), PAL.hazard, Enum.Material.SmoothPlastic, { CastShadow = false })
	K.cyl(model, "PadCore", 42, 0.58, L(0, 0.45, 6), C(58, 58, 62), Enum.Material.Concrete, { CastShadow = false })
	K.cyl(model, "Scorch", 20, 0.62, L(0, 0.45, 6), C(26, 24, 24), Enum.Material.Slate, { CastShadow = false })
	K.cyl(model, "Mount", 13, 2.4, L(0, 1.9, 6), PAL.steelDark, Enum.Material.Metal)
	local rocket = K.model(model, "Rocket")
	local base = L(0, 3.1, 6)
	local body = K.cyl(rocket, "Body", 7, 28, base * CFrame.new(0, 17, 0), PAL.white, Enum.Material.SmoothPlastic)
	rocket.PrimaryPart = body
	for i, d in ipairs({ { 6.6, 3 }, { 5.4, 2.6 }, { 3.8, 2.4 }, { 2, 2 } }) do
		local y = 31 + ({ 1.5, 4.3, 6.8, 9 })[i]
		K.cyl(rocket, "Nose", d[1], d[2], base * CFrame.new(0, y, 0), (i % 2 == 1) and PAL.red or PAL.white, Enum.Material.SmoothPlastic)
	end
	K.ball(rocket, "Tip", 1.8, (base * CFrame.new(0, 41.2, 0)).Position, PAL.red, Enum.Material.SmoothPlastic)
	K.cyl(rocket, "BandA", 7.15, 1.4, base * CFrame.new(0, 26, 0), PAL.red, Enum.Material.SmoothPlastic, { CastShadow = false })
	K.cyl(rocket, "BandB", 7.15, 1, base * CFrame.new(0, 8, 0), C(30, 32, 40), Enum.Material.SmoothPlastic, { CastShadow = false })
	K.cyl(rocket, "Window", 2.6, 0.5, base * CFrame.new(0, 22, -3.4) * CFrame.Angles(math.rad(90), 0, 0), C(70, 130, 200), Enum.Material.Glass)
	K.cyl(rocket, "WindowRim", 3.1, 0.4, base * CFrame.new(0, 22, -3.3) * CFrame.Angles(math.rad(90), 0, 0), PAL.steel, Enum.Material.Metal, { CastShadow = false })
	for k = 0, 3 do
		local c = base * CFrame.Angles(0, k * math.pi / 2 + math.pi / 4, 0)
		K.wedge(rocket, "Fin", Vector3.new(0.6, 9, 5), c * CFrame.new(0, 6.5, -5.6) * CFrame.Angles(0, math.pi, 0), PAL.red, Enum.Material.SmoothPlastic)
	end
	local engine = K.cyl(rocket, "Engine", 5, 2.6, base * CFrame.new(0, 1.7, 0), C(40, 42, 48), Enum.Material.Metal)
	local fireAtt = K.new("Attachment", { Name = "Exhaust", CFrame = CFrame.new(1.3, 0, 0) * CFrame.Angles(0, 0, math.rad(90)) }, engine)
	K.new("ParticleEmitter", { Name = "Fire", Enabled = false, Rate = 240, Lifetime = NumberRange.new(0.35, 0.7), Speed = NumberRange.new(60, 90), SpreadAngle = Vector2.new(8, 8),
		Texture = "rbxasset://textures/particles/fire_main.dds", LightEmission = 0.9, Color = ColorSequence.new(C(255, 236, 170), C(255, 110, 30)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4.5), NumberSequenceKeypoint.new(1, 1.2) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }) }, fireAtt)
	K.new("ParticleEmitter", { Name = "Smoke", Enabled = false, Rate = 90, Lifetime = NumberRange.new(2.5, 4.5), Speed = NumberRange.new(26, 44), SpreadAngle = Vector2.new(34, 34),
		Texture = "rbxasset://textures/particles/smoke_main.dds", Color = ColorSequence.new(C(220, 216, 210), C(120, 118, 116)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 22) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }) }, fireAtt)
	K.new("PointLight", { Name = "Glow", Enabled = false, Range = 60, Brightness = 5, Color = C(255, 170, 80), Shadows = false }, engine)
	-- where a body is strapped on: back to the hull, facing the hub
	local strap = K.part(rocket, "Strap", Vector3.new(4.4, 6.2, 0.5), base * CFrame.new(0, 12, -3.75), C(60, 62, 70), Enum.Material.Metal)
	for _, y in ipairs({ 1.6, -1.2 }) do
		K.part(rocket, "Belt", Vector3.new(4.8, 0.5, 0.7), base * CFrame.new(0, 12 + y, -3.9), PAL.orange, Enum.Material.Fabric, { CastShadow = false })
	end
	K.tag(rocket, "Rocket")
	-- gantry
	K.truss(model, "Gantry", Vector3.new(4, 44, 4), L(11, 22.4, 6), PAL.steelDark)
	K.truss(model, "GantryArmA", Vector3.new(2, 2, 7), L(6.5, 30, 6) * CFrame.Angles(0, math.rad(90), 0), PAL.steelDark)
	K.truss(model, "GantryArmB", Vector3.new(2, 2, 7), L(6.5, 14, 6) * CFrame.Angles(0, math.rad(90), 0), PAL.steelDark)
	local beacon = K.ball(model, "Beacon", 1.8, L(11, 45.4, 6).Position, PAL.red, Enum.Material.Neon, { CastShadow = false })
	K.new("PointLight", { Range = 24, Brightness = 2, Color = PAL.red, Shadows = false }, beacon)
	-- console
	local con = K.model(model, "Console")
	K.part(con, "Desk", Vector3.new(12, 3.2, 3.6), L(0, 2, -26), PAL.steelDark, Enum.Material.Metal)
	K.part(con, "Top", Vector3.new(12, 0.5, 4.2), L(0, 3.9, -26.2) * CFrame.Angles(math.rad(-16), 0, 0), C(36, 40, 50), Enum.Material.SmoothPlastic)
	local screen = K.part(con, "RocketScreen", Vector3.new(11, 3.6, 0.4), L(0, 7.4, -24.6), C(10, 14, 20), Enum.Material.SmoothPlastic)
	K.label(screen, "READY", { screen = true, faces = { Enum.NormalId.Front }, glow = true, color = C(120, 255, 160), font = Enum.Font.Code })
	K.part(con, "ScreenPost", Vector3.new(0.8, 2.5, 0.8), L(0, 4.35, -24.6), PAL.steelDark, Enum.Material.Metal)
	local function button(x, color, tag, action)
		local b = K.cyl(con, tag, 2.2, 0.9, L(x, 4.5, -26.4) * CFrame.Angles(math.rad(-16), 0, 0), color, Enum.Material.Neon)
		K.tag(b, tag)
		K.new("ProximityPrompt", { ActionText = action, ObjectText = "Rocket", HoldDuration = 0.25, MaxActivationDistance = 11, RequiresLineOfSight = false,
			KeyboardKeyCode = (tag == "RocketLaunch") and Enum.KeyCode.L or Enum.KeyCode.K }, b)
	end
	button(-3, PAL.hazard, "RocketStrap", "Strap in the nearest dummy")
	button(3, PAL.red, "RocketLaunch", "LAUNCH")
	station(K, model, L(-9, 0.6, -14), "stand", 7, 1)
	station(K, model, L(9, 0.6, -14), "stand", 7, 1)
end
