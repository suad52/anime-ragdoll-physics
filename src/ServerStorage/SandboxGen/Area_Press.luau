--!nocheck
-- THE CRUSHER: four splayed columns, a crown with two rams, and a 24 x 24 platen (tag BigPress: Travel, Damage) that
-- comes down when someone hits the button (tag PressButton). Sandbox.Machines flattens whatever was under it.
return function(K, model, cf, S)
	local PAL, C = K.PAL, K.C
	local function L(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	local green, dark = C(88, 106, 96), C(58, 62, 70)
	K.part(model, "Bed", Vector3.new(32, 0.8, 32), L(0, 0.4, 0), dark, Enum.Material.DiamondPlate)
	for i = 0, 7 do
		for _, s in ipairs({ { 0, -15.2, 0 }, { 0, 15.2, 0 }, { -15.2, 0, 90 }, { 15.2, 0, 90 } }) do
			K.part(model, "Stripe", Vector3.new(4, 0.06, 1.4), L(s[1], 0.83, s[2]) * CFrame.Angles(0, math.rad(s[3]), 0) * CFrame.new(-14 + i * 4, 0, 0), (i % 2 == 0) and PAL.hazard or C(24, 24, 28), Enum.Material.SmoothPlastic, { CastShadow = false })
		end
	end
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		K.part(model, "Column", Vector3.new(4.4, 22.4, 4.4), L(c[1] * 13.6, 11.9, c[2] * 13.6) * CFrame.Angles(math.rad(c[2] * 4), 0, math.rad(-c[1] * 4)), green, Enum.Material.Metal)
		K.part(model, "ColumnFoot", Vector3.new(6.4, 1.2, 6.4), L(c[1] * 14.2, 1.4, c[2] * 14.2), dark, Enum.Material.Metal)
	end
	K.part(model, "Crown", Vector3.new(34, 5.4, 34), L(0, 25.4, 0), green, Enum.Material.Metal)
	K.part(model, "CrownTrim", Vector3.new(35, 1, 35), L(0, 22.4, 0), dark, Enum.Material.Metal)
	for _, x in ipairs({ -7, 7 }) do
		K.cyl(model, "Ram", 5.2, 9, L(x, 32.6, 0), dark, Enum.Material.Metal)
		K.cyl(model, "RamCap", 6, 0.8, L(x, 37.4, 0), C(40, 42, 48), Enum.Material.Metal)
	end
	local platen = K.part(model, "Platen", Vector3.new(24, 3, 24), L(0, 18, 0), dark, Enum.Material.Metal, { tag = "BigPress", attrs = { Travel = 15.4, Damage = 140 } })
	K.part(platen, "PlatenBand", Vector3.new(24.4, 0.8, 24.4), L(0, 17, 0), PAL.hazard, Enum.Material.Metal, { Anchored = false, Massless = true, CanCollide = false })
	K.weld(platen, platen.PlatenBand)
	for _, x in ipairs({ -7, 7 }) do
		local rod = K.cyl(platen, "Rod", 3, 18, L(x, 28.5, 0), C(200, 204, 210), Enum.Material.Metal, { Anchored = false, Massless = true, CanCollide = false })
		K.weld(platen, rod)
	end
	K.part(model, "PressLight", Vector3.new(2.4, 1.2, 0.6), L(0, 21, -17.4), C(60, 62, 70), Enum.Material.Neon, { CastShadow = false })
	K.sign(model, "CRUSH ZONE", L(0, 25.4, -17.3), Vector2.new(18, 3), { back = PAL.hazard, color = C(20, 20, 24), strokeW = 0, trim = C(20, 20, 24), pps = 26 })
	K.button(model, L(21, 0, -16), "PressButton", "CRUSH", "The Crusher")
	K.button(model, L(-21, 0, -16), "Dispenser", "Drop a dummy under it", "The Crusher", { Drop = L(0, 7, 0), Cap = 5, Rag = 1.5 })
	K.danger(model, L(21, 0, 14) * CFrame.Angles(0, math.rad(-30), 0))
	K.station(model, L(-4, 1.1, 2) * CFrame.Angles(0, 0.4, 0), "stand", 7, 1)
	K.station(model, L(5, 1.1, -3) * CFrame.Angles(0, -0.5, 0), "stand", 7, 1)
end
