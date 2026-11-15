--!nocheck
-- MUTATION LAB: three glass-fronted test chambers (window on the left, door on the right, as you face them). Each has a subject on SubjectSpot, a console of eight buttons
-- (tag MutateButton, attribute Mut, a ClickDetector each), a door that sinks into the floor (tag ChamberDoor on its
-- button) and a "new subject" button (tag ChamberReset). Sandbox.Mutations applies the mutations and, when the door
-- opens, walks the subject out past InnerSpot and ExitSpot to roam the map.
local MUTS = {
	{ "wings", "WINGS", Color3.fromRGB(180, 120, 255) }, { "legs", "LONG\nLEGS", Color3.fromRGB(60, 220, 255) },
	{ "arms", "LONG\nARMS", Color3.fromRGB(255, 220, 60) }, { "head", "BIG\nHEAD", Color3.fromRGB(255, 90, 200) },
	{ "tentacles", "TENTA\nCLES", Color3.fromRGB(255, 70, 70) }, { "diamond", "DIAMOND", Color3.fromRGB(240, 250, 255) },
	{ "giant", "GIANT", Color3.fromRGB(90, 255, 120) }, { "tiny", "TINY", Color3.fromRGB(255, 150, 50) },
}
return function(K, model, cf, S)
	local PAL, C = K.PAL, K.C
	local M = Enum.Material
	local function L(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	local wall, trim, white = C(206, 206, 202), C(70, 76, 86), C(236, 238, 240)
	-- (2026-11-13) H was 15: a giant on long legs with a big head stands 16.6 studs tall. 19 clears every stack.
	local H, Z0, Z1 = 19, 4, 28
	K.ground(L(0, 0, 9), Vector3.new(104, 0, 56), M.Concrete) -- the whole slab: grass blades came up through the chamber floor
	K.part(model, "Slab", Vector3.new(96, 0.6, 48), L(0, 0.3, 9), C(150, 150, 152), M.Concrete)
	K.part(model, "Back", Vector3.new(90, H + 3, 2), L(0, (H + 3) / 2 + 0.6, Z1 + 1), wall, M.Concrete)
	K.part(model, "Roof", Vector3.new(92, 2, Z1 - Z0 + 9), L(0, H + 1.6, (Z0 + Z1) / 2 - 2.5), trim, M.Concrete)
	for _, x in ipairs({ -43.5, -15, 15, 43.5 }) do
		K.part(model, "Wall", Vector3.new((math.abs(x) > 40) and 3 or 6, H, Z1 - Z0 + 1), L(x, H / 2 + 0.6, (Z0 + Z1) / 2 + 0.5), wall, M.Concrete)
	end
	K.sign(model, "MUTATION LAB", L(0, H + 5.6, -2), Vector2.new(40, 5), { glow = true, trim = S.accent, color = C(190, 255, 230) })
	for _, x in ipairs({ -30, 30 }) do
		K.part(model, "Vent", Vector3.new(8, 3, 6), L(x, H + 4.1, 18), C(120, 124, 132), M.Metal)
	end
	for i, cx in ipairs({ 30, 0, -30 }) do -- 01 on the left as you face the building
		local ch = K.model(model, "Chamber" .. i)
		local zc = (Z0 + Z1) / 2
		K.part(ch, "Floor", Vector3.new(24, 0.2, Z1 - Z0), L(cx, 0.7, zc), white, M.SmoothPlastic)
		K.part(ch, "Liner", Vector3.new(24, H - 0.4, 0.3), L(cx, H / 2 + 0.6, Z1 - 0.2), white, M.SmoothPlastic)
		for _, sx in ipairs({ -1, 1 }) do
			K.part(ch, "Liner", Vector3.new(0.3, H - 0.4, Z1 - Z0), L(cx + sx * 11.85, H / 2 + 0.6, zc), white, M.SmoothPlastic)
		end
		for _, lz in ipairs({ 10, 21 }) do
			local lp = K.part(ch, "LightPanel", Vector3.new(9, 0.3, 3), L(cx + 3, H + 0.4, lz) * CFrame.Angles(0, math.rad(lz == 10 and 12 or -8), 0), C(245, 250, 255), M.Neon, { CastShadow = false })
			K.new("PointLight", { Range = 22, Brightness = 1.3, Color = C(235, 245, 255), Shadows = false }, lp)
		end
		-- front (2026-11-13, the owner: "move the door to the right side of the window rather than the left", and big
		-- subjects could not get out): window cx .. cx+12, mullion, door cx-11.5 .. cx-1, jamb. +x is on your LEFT as
		-- you face the building. The door is 10.5 x 17.6 (it was 7.5 x 13.4). The window is plain see-through plastic,
		-- NOT Material.Glass: Roblox does not draw a see-through part behind Glass, so a diamond subject vanished.
		local WX, WW, DX, DW, DOORH, CNX = 6, 12, -6.25, 10.5, 17.6, 6.75
		K.part(ch, "Sill", Vector3.new(WW, 2.4, 1), L(cx + WX, 1.8, Z0), wall, M.Concrete)
		K.part(ch, "Glass", Vector3.new(WW, 12, 0.5), L(cx + WX, 9, Z0), C(170, 215, 230), M.SmoothPlastic, { Transparency = 0.78, Reflectance = 0.06 })
		K.part(ch, "Header", Vector3.new(WW, 4.6, 1), L(cx + WX, H - 1.7, Z0), trim, M.Concrete)
		K.part(ch, "Mullion", Vector3.new(1, H, 1), L(cx - 0.5, H / 2 + 0.6, Z0), trim, M.Metal)
		K.part(ch, "Jamb", Vector3.new(0.5, H, 1), L(cx - 11.75, H / 2 + 0.6, Z0), trim, M.Metal)
		K.part(ch, "DoorHead", Vector3.new(DW, H - DOORH, 1), L(cx + DX, 0.6 + DOORH + (H - DOORH) / 2, Z0), trim, M.Concrete)
		local door = K.part(ch, "Door", Vector3.new(DW, DOORH, 0.6), L(cx + DX, 0.6 + DOORH / 2, Z0), C(226, 226, 222), M.Metal, { attrs = { Slide = -(DOORH + 0.2) } })
		for _, y in ipairs({ 3, 14.6 }) do
			local band = K.part(door, "Band", Vector3.new(DW + 0.05, 1.2, 0.7), L(cx + DX, y, Z0), PAL.hazard, M.SmoothPlastic, { Anchored = false, Massless = true, CanCollide = false })
			K.weld(door, band)
		end
		local screen = K.part(ch, "ChamberScreen", Vector3.new(WW - 0.6, 2.2, 0.3), L(cx + WX, H - 1.8, Z0 - 0.62), C(10, 14, 18), M.SmoothPlastic)
		K.label(screen, "CHAMBER 0" .. i, { screen = true, faces = { Enum.NormalId.Front }, glow = true, color = C(90, 255, 190), pps = 30, strokeW = 0, font = Enum.Font.GothamBlack })
		-- console: the panel is yawed 180 so its Top-face gui reads from the outside
		K.part(ch, "Console", Vector3.new(15, 3, 3), L(cx + CNX, 2.1, -5), C(22, 24, 30), M.SmoothPlastic)
		K.part(ch, "ConsoleGlow", Vector3.new(15.1, 0.25, 0.2), L(cx + CNX, 3.2, -6.55), S.accent, M.Neon, { CastShadow = false })
		local panel = K.part(ch, "Panel", Vector3.new(15, 0.4, 3.6), L(cx + CNX, 3.95, -5) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(math.rad(16), 0, 0), C(14, 16, 20), M.SmoothPlastic)
		local g = K.new("SurfaceGui", { Name = "Labels", Face = Enum.NormalId.Top, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 40, LightInfluence = 0, Brightness = 1.6 }, panel)
		for k, mut in ipairs(MUTS) do
			local dx = -6.3 + (k - 1) * 1.8 -- along the panel's own +X; the panel is yawed 180, so k = 1 is on your left
			local b = K.part(ch, "MutBtn", Vector3.new(1.4, 0.5, 1.4), panel.CFrame * CFrame.new(dx, 0.4, -0.6), mut[3], M.Neon, { tag = "MutateButton", attrs = { Mut = mut[1] }, CastShadow = false })
			K.new("ClickDetector", { MaxActivationDistance = 18 }, b)
			-- a Top-face gui runs its X along the part's -Z and its Y along +X (measured), so each label is turned 90
			K.new("TextLabel", { Size = UDim2.fromOffset(70, 44), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(36, (dx + 7.5) * 40), Rotation = 90, BackgroundTransparency = 1, Text = mut[2], TextScaled = true, TextWrapped = false,
				Font = Enum.Font.GothamBold, TextColor3 = C(235, 240, 245) }, g)
		end
		local db = K.part(ch, "DoorButton", Vector3.new(2, 2.4, 0.6), L(cx - 13.6, 5, Z0 - 0.3), C(24, 24, 28), M.Metal, { tag = "ChamberDoor" })
		K.part(ch, "DoorLens", Vector3.new(1.1, 1.1, 0.3), L(cx - 13.6, 5, Z0 - 0.7), PAL.red, M.Neon, { CastShadow = false, CanCollide = false })
		local tagp = K.part(ch, "DoorTag", Vector3.new(2.6, 0.9, 0.2), L(cx - 13.6, 7, Z0 - 0.2), K.SIGN_BLACK, M.SmoothPlastic)
		K.label(tagp, "DOOR", { faces = { Enum.NormalId.Front }, pps = 30, strokeW = 0 })
		K.new("ProximityPrompt", { ActionText = "Open the door", ObjectText = "Chamber 0" .. i, HoldDuration = 0, MaxActivationDistance = 9, RequiresLineOfSight = false, KeyboardKeyCode = Enum.KeyCode.K }, db)
		K.cyl(ch, "ResetPost", 1, 3.2, L(cx + 15.6, 1.6 + 0.6, -5), C(22, 24, 30), M.Metal)
		local rb = K.cyl(ch, "ResetButton", 1.8, 0.6, L(cx + 15.6, 4.1, -5), C(240, 240, 240), M.Neon, { tag = "ChamberReset", CastShadow = false })
		K.new("ProximityPrompt", { ActionText = "New test subject", ObjectText = "Chamber 0" .. i, HoldDuration = 0, MaxActivationDistance = 7, RequiresLineOfSight = false, KeyboardKeyCode = Enum.KeyCode.K }, rb)
		K.zone(ch, "SubjectSpot", Vector3.new(1, 1, 1), L(cx + WX, 0.8, 15))
		K.zone(ch, "InnerSpot", Vector3.new(1, 1, 1), L(cx + DX, 0.8, 10))
		K.zone(ch, "ExitSpot", Vector3.new(1, 1, 1), L(cx + DX, 0.6, -17))
		K.cyl(ch, "Mark", 6, 0.06, L(cx + WX, 0.83, 15), S.accent, M.Neon, { CastShadow = false, Transparency = 0.35, CanCollide = false })
	end
end
