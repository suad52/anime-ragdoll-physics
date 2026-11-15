--!nocheck
-- TESLA COIL: switched on, the ball at the top (tag Tesla: Range, Damage = health per SECOND) latches an arc onto the
-- nearest four bodies and cooks them where they stand - see Sandbox.Machines.
return function(K, model, cf, S)
	local PAL, C = K.PAL, K.C
	local M = Enum.Material
	local function L(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	local copper = C(190, 112, 60)
	K.cyl(model, "Base", 18, 1.2, L(0, 0.6, 0), PAL.concrete, M.Concrete)
	K.cyl(model, "Plinth", 9, 2.4, L(0, 2.4, 0), C(48, 52, 60), M.Metal)
	K.cyl(model, "Coil", 5, 17, L(0, 12, 0), copper, M.Metal)
	for i = 0, 7 do
		K.cyl(model, "Winding", 5.5, 0.6, L(0, 4.6 + i * 2.1, 0), C(120, 70, 40), M.Metal, { CastShadow = false })
	end
	K.cyl(model, "Collar", 12, 2.4, L(0, 21.4, 0), C(200, 204, 212), M.Metal)
	local top = K.ball(model, "TeslaTop", 8, L(0, 24.6, 0).Position, C(210, 220, 240), M.Metal, { tag = "Tesla", attrs = { Range = 40, Damage = 55, Group = "tesla", On = false } })
	K.new("PointLight", { Range = 30, Brightness = 0, Color = C(150, 180, 255), Shadows = false }, top)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		K.cyl(model, "Insulator", 1.4, 4, L(math.sin(a) * 8, 3.2, math.cos(a) * 8), C(230, 230, 224), M.SmoothPlastic)
	end
	K.button(model, L(4, 0, -17), "Switch", "Turn on the coil", "Tesla Coil", { Group = "tesla", On = false, Label = "the coil" })
	K.danger(model, L(-9, 0, -16) * CFrame.Angles(0, math.rad(-18), 0), "HIGH VOLTAGE")
	for _, p in ipairs({ { -13, 6 }, { 12, 9 }, { 2, 15 } }) do
		K.station(model, L(p[1], 0.3, p[2]), "stand", 9, 1)
	end
end
