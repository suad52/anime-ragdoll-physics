--!nocheck
-- SandboxGen.World (2026-11-13, open test ground): lighting, the ground, the spawn deck, the trails, a painted patch of
-- ground under each site, signposts and all the loose scenery. Nothing is on a ring any more: Build.SITES places each
-- site at any angle straight on the grass; this fills S.cf0 / S.cf / S.model for the area builders that run after it.
-- Ground = real terrain, flat where you play (every builder assumes y 0): it carves (pits, the lake, the train
-- tunnels), holds water and paints itself, none of which one big baseplate part can do.
return function(K, map, SITES)
	local PAL, C = K.PAL, K.C
	local Lighting = game:GetService("Lighting")
	local terrain = workspace.Terrain
	local up = CFrame.new
	local M = Enum.Material
	for _, c in ipairs(Lighting:GetChildren()) do
		c:Destroy()
	end
	pcall(function() Lighting.LightingStyle = Enum.LightingStyle.Realistic end)
	pcall(function() Lighting.PrioritizeLightingQuality = true end)
	-- (2026-11-14, owner: "take away the grass and make it a green baseplate and make the sky look cartoonish and blue
	-- and just try to make the game more vibrant overall"): midday sun, bright fill light, a clear blue sky with no haze,
	-- big white clouds, punchier colour and no distance blur. (Was: 16.35 h, a hazy warm atmosphere, a softer grade.)
	-- The server's day/night cycle stays off in this place (ServerScriptService.DayNightService disabled), so this holds.
	Lighting.ClockTime = 13.6
	Lighting.GeographicLatitude = 38
	Lighting.Brightness = 2.8
	Lighting.ExposureCompensation = 0
	Lighting.Ambient = C(118, 122, 148)
	Lighting.OutdoorAmbient = C(138, 146, 172)
	Lighting.ColorShift_Top = C(255, 244, 226)
	Lighting.ColorShift_Bottom = C(150, 176, 220)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.35
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.35
	-- (2026-11-14, owner: "the sky should be more cartoonish", then "a little bit less cartoony") a painted, softly
	-- cel-shaded skybox: bright blue with stylised clouds - between Roblox's default sky and a flat obby sky (the free
	-- Creator Store skybox "Cartoon Sky", asset 10594688909 by xor25th - only its six texture ids are used). Tried and
	-- passed over: "Cartoon Obby Sky" 6216752998 (too cartoony). The dynamic 3D Clouds are OFF (below): their realistic
	-- puffs sat in front of the painted ones.
	K.new("Sky", { Name = "Sky", SunAngularSize = 16, MoonAngularSize = 9, StarCount = 2200,
		SkyboxBk = "rbxassetid://6295671271", SkyboxFt = "rbxassetid://6295671136", SkyboxLf = "rbxassetid://6295670996",
		SkyboxRt = "rbxassetid://6295671509", SkyboxUp = "rbxassetid://6295671667", SkyboxDn = "rbxassetid://6295671382" }, Lighting)
	K.new("Atmosphere", { Density = 0.2, Offset = 0, Color = C(168, 208, 255), Decay = C(64, 124, 255), Glare = 0, Haze = 0 }, Lighting)
	K.new("BloomEffect", { Name = "Bloom", Intensity = 0.3, Size = 22, Threshold = 1.6 }, Lighting)
	K.new("SunRaysEffect", { Name = "SunRays", Intensity = 0.04, Spread = 0.85 }, Lighting)
	K.new("ColorCorrectionEffect", { Name = "Grade", Brightness = 0, Contrast = 0.16, Saturation = 0.18, TintColor = C(255, 255, 255) }, Lighting)
	K.new("DepthOfFieldEffect", { Name = "DepthOfField", Enabled = false, FarIntensity = 0.16, FocusDistance = 70, InFocusRadius = 90, NearIntensity = 0 }, Lighting)
	local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover, clouds.Density, clouds.Color = 0.5, 0.9, C(255, 255, 255)
	clouds.Enabled = false -- the painted skybox has the clouds
	clouds.Parent = terrain
	pcall(function()
		-- (2026-11-13) clear water: at 0.5 transparency / 0.4 reflectance you could not see the shark take a body
		terrain.WaterColor, terrain.WaterTransparency, terrain.WaterWaveSize, terrain.WaterWaveSpeed, terrain.WaterReflectance = C(56, 196, 236), 0.92, 0.1, 8, 0.1
	end)
	------------------------------------------------------------------------------------------------ ground
	terrain:Clear()
	for gx = -2, 1 do
		terrain:FillBlock(CFrame.new(gx * 280 + 140, -22, 0), Vector3.new(280, 40, 1120), M.Grass) -- top at -2: the surface lands on y 0 (see MapKit)
		task.wait()
	end
	-- (2026-11-14) CARTOON GROUND: the terrain-only materials render FLAT (a MaterialVariant with no texture maps, set
	-- as the base material's override in MaterialService), so the field reads as one plain green baseplate and the
	-- hills / rocks as smooth toy shapes - while staying real terrain (the pits, the lake and the train tunnels are
	-- carved into it). Concrete / Slate are left textured: hundreds of building parts use them.
	local MS = game:GetService("MaterialService")
	for _, m in ipairs({ M.Grass, M.LeafyGrass, M.Rock, M.Ground, M.Mud, M.Sand, M.Pavement, M.Asphalt, M.Cobblestone }) do
		local v = MS:FindFirstChild("Cartoon" .. m.Name) or Instance.new("MaterialVariant")
		v.Name = "Cartoon" .. m.Name
		v.BaseMaterial = m
		v.Parent = MS
		pcall(function() MS:SetBaseMaterialOverride(m, v.Name) end)
	end
	for m, c in pairs({ [M.Grass] = C(60, 140, 50), [M.LeafyGrass] = C(60, 140, 50), [M.Rock] = C(126, 132, 152), [M.Ground] = C(200, 150, 90),
		[M.Mud] = C(176, 124, 82), [M.Sand] = C(236, 206, 128), [M.Pavement] = C(206, 208, 216), [M.Asphalt] = C(92, 96, 114),
		[M.Cobblestone] = C(180, 174, 164), [M.Concrete] = C(214, 214, 222), [M.Slate] = C(124, 132, 150) }) do
		pcall(function() terrain:SetMaterialColor(m, c) end)
	end
	-- (2026-11-14) the owner: "remove the tall grass and make the ground more ... simple". No grass blades (Decoration),
	-- and no leafy-grass patches: the field is one plain grass, with only the sites' own floors and the footpaths on it.
	pcall(function() terrain.Decoration = false end)
	local rng = Random.new(20261113)
	-- (2026-11-14) the field is smaller and is no longer a square centred on the spawn deck: Build.SITES.field.
	local F = SITES.field or { x0 = -352, x1 = 352, z0 = -352, z1 = 352 }
	local FCX, FCZ, FHX, FHZ = (F.x0 + F.x1) / 2, (F.z0 + F.z1) / 2, (F.x1 - F.x0) / 2, (F.z1 - F.z0) / 2
	map:SetAttribute("FieldMin", Vector3.new(F.x0, 0, F.z0)) -- Sandbox.Wanderers and Sandbox.Mutations keep inside these
	map:SetAttribute("FieldMax", Vector3.new(F.x1, 0, F.z1))
	for i = 0, 39 do -- hills close the field in: a rounded square, so the corners of the field stay usable
		local a = i / 40 * math.pi * 2
		local k, j = 1 + 0.28 * (1 - math.abs(math.cos(2 * a))), rng:NextNumber(-14, 22)
		local rad = rng:NextNumber(48, 78)
		terrain:FillBall(Vector3.new(FCX + math.sin(a) * ((FHX + 80) * k + j), rng:NextNumber(-16, 6), FCZ - math.cos(a) * ((FHZ + 80) * k + j)), rad, (i % 5 == 2) and M.Rock or M.Grass)
		if i % 7 == 6 then
			task.wait()
		end
	end
	for i = 0, 17 do -- and a taller row behind it
		local a = (i + 0.5) / 18 * math.pi * 2
		local k, j = 1 + 0.28 * (1 - math.abs(math.cos(2 * a))), rng:NextNumber(-20, 30)
		terrain:FillBall(Vector3.new(FCX + math.sin(a) * ((FHX + 208) * k + j), rng:NextNumber(-40, -12), FCZ - math.cos(a) * ((FHZ + 208) * k + j)), rng:NextNumber(88, 116), M.Grass)
		task.wait()
	end
	local walls = K.model(map, "Bounds")
	for _, w in ipairs({ { FCX, F.z1, FHX * 2 + 16, 2 }, { FCX, F.z0, FHX * 2 + 16, 2 }, { F.x1, FCZ, 2, FHZ * 2 + 16 }, { F.x0, FCZ, 2, FHZ * 2 + 16 } }) do
		K.part(walls, "Wall", Vector3.new(w[3], 400, w[4]), CFrame.new(w[1], 190, w[2]), nil, nil, { Transparency = 1, CastShadow = false, CanQuery = false })
	end
	------------------------------------------------------------------------------------------------ sites
	for _, S in ipairs(SITES) do
		S.cf0 = CFrame.new(S.x, 0, S.z) * CFrame.Angles(0, -math.rad(S.yaw or 0), 0)
		S.cf = S.legacy and S.cf0 * up(0, -0.4, 0) or S.cf0
		S.model = K.model(map, S.name)
	end
	local function inSite(S, p, margin)
		local l = S.cf0:PointToObjectSpace(Vector3.new(p.X, 0, p.Z))
		if S.box then -- (2026-11-14) the measured footprint, not the circle: the sites stand 10 studs apart now
			local m = margin or 0
			local function within(b)
				return l.X > b[1] - m and l.X < b[2] + m and l.Z > b[3] - m and l.Z < b[4] + m
			end
			if within(S.box) then
				return true
			end
			for _, b in ipairs(S.also or {}) do
				if within(b) then
					return true
				end
			end
			return S.signX ~= nil and not S.noSign and math.abs(l.X - S.signX) < 6.5 + m and math.abs(l.Z - S.signZ) < 2 + m
		end
		local dz = 0
		if l.Z < -(S.ahead or 0) then
			dz = -(S.ahead or 0) - l.Z
		elseif l.Z > (S.behind or 0) then
			dz = l.Z - (S.behind or 0)
		end
		return math.sqrt(l.X * l.X + dz * dz) < S.r + (margin or 0)
	end
	------------------------------------------------------------------------------------------------ trails
	-- painted into the ground, wobbling as they go: a paved trunk north from the deck, dirt footpaths everywhere else
	local trailPts = {}
	local function trail(pts, width, mat, wob) -- wob = how far it may wander off the line (8; a lane between two sites takes 1)
		local prev
		for i = 1, #pts - 1 do
			local a, b = Vector3.new(pts[i][1], 0, pts[i][2]), Vector3.new(pts[i + 1][1], 0, pts[i + 1][2])
			local n = math.max(1, math.ceil((b - a).Magnitude / 9))
			for k = 0, n do
				local p = a:Lerp(b, k / n)
				p += Vector3.new(math.noise(p.X * 0.03, p.Z * 0.03, 1.7) * (wob or 8), 0, math.noise(p.X * 0.03, p.Z * 0.03, 9.3) * (wob or 8))
				if prev and (p - prev).Magnitude > 0.5 then
					local w = width * (1 + math.noise(p.X * 0.11, p.Z * 0.11, 4.4) * 0.35)
					local down = Vector3.new(0, -4, 0)
					terrain:FillBlock(CFrame.lookAt((prev + p) / 2 + down, p + down), Vector3.new(w, 4, (p - prev).Magnitude + w * 0.5), mat)
					table.insert(trailPts, { (prev + p) / 2, width / 2 + 2 })
				end
				table.insert(trailPts, { p, width / 2 + 2 })
				prev = p
			end
		end
		task.wait()
	end
	-- (2026-11-14) the footpaths run down the lanes between the packed sites: Build.SITES.trails
	for _, t in ipairs(SITES.trails or {}) do
		trail(t, t.w or 6, t.mat or M.Ground, 1)
	end
	------------------------------------------------------------------------------------------------ ground patches
	for _, S in ipairs(SITES) do
		if S.ground then
			local rb = Random.new(math.floor(S.x * 7 + S.z * 13))
			local r = S.patch or S.r
			local function slab(x, z, w, d, yaw)
				terrain:FillBlock(CFrame.new(x, -4, z) * CFrame.Angles(0, yaw, 0), Vector3.new(w, 4, d), S.ground)
			end
			slab(S.x, S.z, r * 1.5, r * 1.5, rb:NextNumber(0, 1.5))
			slab(S.x, S.z, r * 1.25, r * 1.8, rb:NextNumber(0, 3))
			if S.legacy then -- hard ground under everything the old pad builders lay (they lay thin floor markings)
				local b = S.box
				if b then -- (2026-11-14) the measured footprint, not the whole 92-stud pad: the neighbours are 10 studs away
					terrain:FillBlock(S.cf0 * CFrame.new((b[1] + b[2]) / 2, -4, (b[3] + b[4]) / 2), Vector3.new(b[2] - b[1] + 4, 4, b[4] - b[3] + 4), S.ground)
				else
					terrain:FillBlock(S.cf0 * CFrame.new(0, -4, 0), Vector3.new((S.half or 46) * 2, 4, (S.half or 46) * 2), S.ground)
				end
			end
			for i = 1, 6 do
				local a = i / 6 * math.pi * 2 + rb:NextNumber(-0.4, 0.4)
				local d = r * rb:NextNumber(0.45, 0.75)
				slab(S.x + math.sin(a) * d, S.z + math.cos(a) * d, r * rb:NextNumber(0.5, 0.9), r * rb:NextNumber(0.5, 0.9), rb:NextNumber(0, 3))
			end
		end
	end
	task.wait()
	------------------------------------------------------------------------------------------------ spawn deck
	-- big pavers with the joints showing, a promenade north into the field, the boards and kiosks stood about it
	local deck = K.model(map, "Spawn")
	terrain:FillBlock(CFrame.new(0, -4, 4), Vector3.new(92, 4, 72), M.Pavement)
	terrain:FillBlock(CFrame.new(0, -4, -72), Vector3.new(38, 4, 100), M.Pavement)
	-- (2026-11-14) GREEN BASEPLATE: the painted trails, site patches and paving above become plain ground again, so the
	-- whole field is one flat green (flat-coloured terrain shows a material's blocky voxel edges, which looked messy).
	-- The sites' own parts stay; the areas built after this (the lake, the pits) carve and paint on top as before.
	do
		local field = Region3.new(Vector3.new(F.x0 - 4, -12, F.z0 - 4), Vector3.new(F.x1 + 4, 4, F.z1 + 4)):ExpandToGrid(4)
		for _, m in ipairs({ M.Pavement, M.Concrete, M.Asphalt, M.Ground, M.Mud, M.Sand, M.Slate, M.Cobblestone, M.LeafyGrass }) do
			terrain:ReplaceMaterial(field, 4, m, M.Grass)
		end
		task.wait()
	end
	local tones = { C(192, 188, 180), C(180, 176, 168), C(200, 196, 188) }
	local drng = Random.new(7)
	for ix = -2, 2 do
		for iz = -1, 1 do
			K.part(deck, "Paver", Vector3.new(15.6, 0.5, 15.6), up(ix * 16, 0.25, iz * 16), tones[drng:NextInteger(1, 3)], M.Concrete)
		end
	end
	for iz = 0, 5 do
		for _, x in ipairs({ -8, 8 }) do
			K.part(deck, "Paver", Vector3.new(15.6, 0.5, 15.6), up(x, 0.25, -32 - iz * 16), tones[drng:NextInteger(1, 3)], M.Concrete)
		end
	end
	for _, p in ipairs({ { -9, 2 }, { 0, 0 }, { 9, 2 }, { -5, 10 }, { 5, 10 }, { 0, 16 } }) do
		K.new("SpawnLocation", { Name = "Spawn", Anchored = true, Size = Vector3.new(4, 0.2, 4), Transparency = 1, CanCollide = false, CanQuery = false, Neutral = true, Duration = 2,
			CFrame = CFrame.lookAt(Vector3.new(p[1], 1.4, p[2]), Vector3.new(p[1], 1.4, p[2] - 30)) }, deck)
	end
	-- (2026-11-14) the "RAGDOLL SANDBOX" pylon that stood behind the spawn at z 33 (dais, pylon, cap, four lettered
	-- faces) was removed at the owner's request. It drew nothing from rng, so nothing after it moves on a rebuild; the
	-- old block is in ServerStorage.Backup_2026-11-14_totem.World_before.
	for i, name in ipairs({ "LB_Kills", "LB_Time", "LB_Damage" }) do
		local at = ({ Vector3.new(-25, 0.5, 31), Vector3.new(25, 0.5, 31), Vector3.new(-49, 0.5, 6) })[i]
		local cf = CFrame.lookAt(at + Vector3.new(0, 7, 0), Vector3.new(0, 7.6, -4))
		for _, x in ipairs({ -5.2, 5.2 }) do
			-- (2026-11-13) two short legs under the frame (they were 13 tall, through the board and 1.4 out of its top)
			K.cyl(deck, "LBPost", 0.6, 2.22, CFrame.new((cf * up(x, -5.99, 0.3)).Position), K.SIGN_BLACK, M.Metal)
		end
		K.part(deck, "LBFrame", Vector3.new(13.2, 9.8, 0.5), cf * up(0, 0, 0.3), K.SIGN_BLACK, M.Metal)
		K.part(deck, name, Vector3.new(12.4, 9, 0.3), cf, K.SIGN_BLACK, M.SmoothPlastic, { tag = "Leaderboard" })
	end
	local function kiosk(at, yawOff, title, tag, prompt, stripe)
		local cf = CFrame.lookAt(Vector3.new(at.X, 0.5, at.Z), Vector3.new(0, 0.5, at.Z * 0.4)) * CFrame.Angles(0, math.rad(yawOff), 0)
		local m = K.model(deck, title)
		K.part(m, "Floor", Vector3.new(13, 0.3, 8), cf * up(0, 0.15, 1), PAL.woodDark, M.WoodPlanks)
		local counter = K.part(m, "Counter", Vector3.new(11, 3.4, 2), cf * up(0, 1.7, -1.4), PAL.wood, M.WoodPlanks)
		K.part(m, "CounterTop", Vector3.new(11.6, 0.3, 2.6), cf * up(0, 3.5, -1.4), PAL.white, M.Marble)
		K.part(m, "Back", Vector3.new(12, 9, 0.6), cf * up(0, 4.5, 4.2), PAL.navy, M.SmoothPlastic)
		for _, x in ipairs({ -5.8, 5.8 }) do
			K.part(m, "Side", Vector3.new(0.5, 9, 6), cf * up(x, 4.5, 1.4), PAL.navy, M.SmoothPlastic)
		end
		for k = -3, 3 do
			K.part(m, "Awning", Vector3.new(1.75, 0.3, 6.4), cf * up(k * 1.75, 9.2, -0.6) * CFrame.Angles(math.rad(14), 0, 0), (k % 2 == 0) and stripe or PAL.white, M.Fabric)
		end
		K.sign(m, title, cf * up(0, 11.6, -1.6), Vector2.new(11, 2.6), { trim = stripe })
		K.tag(counter, tag)
		K.new("ProximityPrompt", { ActionText = prompt, ObjectText = title, HoldDuration = 0, MaxActivationDistance = 13, RequiresLineOfSight = false, KeyboardKeyCode = Enum.KeyCode.B }, counter)
	end
	-- (2026-11-14, owner: "remove the dummy depot and the shop from the spawn area") no SHOP / DUMMY DEPOT stands any
	-- more: the shop opens from the SHOP tile, the spawn menu with V / its key strip. kiosk() is kept for the record.
	-- kiosk(Vector3.new(50, 0, -10), 9, "SHOP", "ShopKiosk", "Open the shop", PAL.red)
	-- kiosk(Vector3.new(48, 0, 18), -12, "DUMMY DEPOT", "SpawnKiosk", "Open the spawn menu", PAL.blue)
	K.bench(deck, up(-40, 0.5, -19) * CFrame.Angles(0, math.rad(200), 0))
	K.bench(deck, up(-30, 0.5, 20) * CFrame.Angles(0, math.rad(165), 0))
	for _, p in ipairs({ { -44, -27, 135 }, { 44, -27, 225 }, { -44, 27, 45 }, { 21, -70, 270 }, { -21, -104, 90 } }) do
		K.lamp(deck, Vector3.new(p[1], 0.3, p[2]), math.rad(p[3]))
	end
	------------------------------------------------------------------------------------------------ signposts
	local srng = Random.new(99)
	for _, S in ipairs(SITES) do
		if S.title and not S.noSign then
			local capsule = (S.ahead or 0) + (S.behind or 0) > 0
			local at = S.cf0 * up(S.signX or (capsule and (S.r - 2) or (S.r * 0.5 + 4)), 0, S.signZ or (capsule and -6 or -(S.r + 3)))
			local base = CFrame.new(at.Position) * (S.cf0 - S.cf0.Position) * CFrame.Angles(0, math.rad(srng:NextNumber(-16, 16)), math.rad(srng:NextNumber(-3, 3)))
			for _, x in ipairs({ -4, 4 }) do
				-- (2026-11-13) legs stop UNDER the sign and stand in line with it. They were 7.4 tall and 0.4 behind the
				-- board, so they ran up through its back face to the top edge. The board's trim ends at 4.65.
				K.part(S.model, "SignPost", Vector3.new(0.7, 4.67, 0.7), base * up(x, 2.335, -0.3), K.SIGN_BLACK, M.Metal)
			end
			K.sign(S.model, S.title, base * up(0, 6.3, -0.3), Vector2.new(10.5, 2.4), { trim = S.accent, pps = 26 })
		end
	end
	------------------------------------------------------------------------------------------------ scenery
	local scenery = K.model(map, "Scenery")
	local function clear(p, margin)
		margin = margin or 0
		if p.X < F.x0 + 14 or p.X > F.x1 - 14 or p.Z < F.z0 + 14 or p.Z > F.z1 - 14 then
			return false
		end
		if math.abs(p.X) < 62 + margin and p.Z > -36 - margin and p.Z < 50 + margin then
			return false -- the deck
		end
		if math.abs(p.X) < 22 + margin and p.Z > -126 - margin and p.Z < -30 then
			return false -- the promenade
		end
		for _, S in ipairs(SITES) do
			if inSite(S, p, margin) then
				return false
			end
		end
		for _, t in ipairs(trailPts) do
			if (t[1] - p).Magnitude < t[2] + margin then
				return false
			end
		end
		return true
	end
	local taken = {}
	local function spot(r, tries, lim)
		lim = lim or 332
		for _ = 1, tries or 60 do
			local inset = 352 - lim -- lim was written against the old +-352 square: keep it as a distance in from the wall
			local p = Vector3.new(rng:NextNumber(F.x0 + inset, F.x1 - inset), 0, rng:NextNumber(F.z0 + inset, F.z1 - inset))
			local ok = clear(p, r)
			if ok then
				for _, t in ipairs(taken) do
					if (t[1] - p).Magnitude < t[2] + r then
						ok = false
						break
					end
				end
			end
			if ok then
				table.insert(taken, { p, r })
				return p
			end
		end
	end
	-- lamps along the trails
	for i = 9, #trailPts, 15 do
		local p, q = trailPts[i][1], trailPts[math.min(#trailPts, i + 1)][1]
		local d = (q - p)
		if d.Magnitude > 0.5 and d.Magnitude < 12 then
			local side = d.Unit:Cross(Vector3.yAxis) * ((i % 2 == 0) and 1 or -1) * (trailPts[i][2] + 3)
			local at = p + side
			if clear(at, -3) or true then
				local okSite = true
				for _, S in ipairs(SITES) do
					if inSite(S, at, 2) then
						okSite = false
					end
				end
				if okSite then
					K.lamp(scenery, at + Vector3.new(0, 0.1, 0), math.atan2(side.X, side.Z))
					table.insert(taken, { at, 4 })
				end
			end
		end
	end
	-- a few low knolls where nothing is built, so the field is not a billiard table
	for _ = 1, 7 do
		local p = spot(30, 90, 300)
		if p then
			local R, h = rng:NextNumber(44, 58), rng:NextNumber(3.5, 6)
			terrain:FillBall(Vector3.new(p.X, h - R - 2, p.Z), R, M.Grass)
		end
	end
	task.wait()
	local function mark(tag, cf)
		return K.zone(scenery, tag, Vector3.new(1, 1, 1), cf, tag)
	end
	-- loose physics props (the server stocks these markers): crate stacks, fuel drums, gas cans
	for _ = 1, 10 do
		local p = spot(9, 60, 320)
		if p then
			local base = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
			local n = rng:NextInteger(2, 3)
			for i = 1, n do
				mark("CrateSpawn", base * up((i - (n + 1) / 2) * 3.7, 0, rng:NextNumber(-0.3, 0.3)) * CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), 0))
			end
			for i = 1, n - 1 do
				if rng:NextNumber() < 0.8 then
					mark("CrateSpawn", base * up((i - n / 2) * 3.7, 3.45, 0))
				end
			end
		end
	end
	for _ = 1, 7 do
		local p = spot(7, 60, 320)
		if p then
			for i = 1, rng:NextInteger(1, 3) do
				mark("BarrelSpawn", CFrame.new(p + Vector3.new((i - 2) * 3.6, 0, rng:NextNumber(-1.5, 1.5))))
			end
		end
	end
	for _ = 1, 6 do
		local p = spot(6, 60, 320)
		if p then
			for i = 1, rng:NextInteger(2, 3) do
				mark("GasCanSpawn", CFrame.new(p + Vector3.new((i - 2) * 2.4, 0, rng:NextNumber(-1.5, 1.5))) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0))
			end
		end
	end
	-- lone bounce pads
	for _ = 1, 8 do
		local p = spot(10, 60, 320)
		if p then
			local col = ({ PAL.red, PAL.blue, PAL.hazard, PAL.orange })[rng:NextInteger(1, 4)]
			local m = K.model(scenery, "Bouncer")
			K.cyl(m, "Frame", 12.6, 1.4, CFrame.new(p + Vector3.new(0, 0.9, 0)), PAL.steelDark, M.Metal)
			K.cyl(m, "Mat", 11, 0.5, CFrame.new(p + Vector3.new(0, 1.5, 0)), col, M.Fabric, { tag = "Trampoline", attrs = { Power = rng:NextInteger(80, 125) } })
			K.cyl(m, "Dot", 4, 0.52, CFrame.new(p + Vector3.new(0, 1.5, 0)), PAL.white, M.Fabric, { CastShadow = false, CanCollide = false, CanQuery = false })
		end
	end
	-- (2026-11-13) nine dummies used to be posted here "just standing about". The crowd is ServerScriptService.Sandbox.Wanderers
	-- now, and it walks. The draws stay, so that everything laid after this keeps its place.
	for _ = 1, 9 do
		local p = spot(7, 60, 300)
		if p then
			rng:NextNumber(0, 6.28)
		end
	end
	-- junk: tyre stacks, benches, picnic tables
	for _ = 1, 8 do
		local p = spot(5, 60, 320)
		if p then
			local m = K.model(scenery, "Tyres")
			for i = 0, rng:NextInteger(2, 4) do
				K.cyl(m, "Tyre", 4.4, 1.3, CFrame.new(p + Vector3.new(rng:NextNumber(-0.3, 0.3), 0.65 + i * 1.3, rng:NextNumber(-0.3, 0.3))), C(28, 28, 32), M.Rubber)
			end
			if rng:NextNumber() < 0.5 then
				K.cyl(m, "Tyre", 4.4, 1.3, CFrame.new(p + Vector3.new(4.2, 2.2, 0.4)) * CFrame.Angles(0, 0, math.rad(78)), C(28, 28, 32), M.Rubber)
			end
		end
	end
	for _ = 1, 5 do
		local p = spot(6, 60, 300)
		if p then
			K.bench(scenery, CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0))
		end
	end
	for _ = 1, 4 do
		local p = spot(8, 60, 300)
		if p then
			local cf = CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
			local m = K.model(scenery, "Picnic")
			K.part(m, "Top", Vector3.new(9, 0.4, 4), cf * up(0, 3.2, 0), PAL.wood, M.WoodPlanks)
			for _, z in ipairs({ -3.4, 3.4 }) do
				K.part(m, "Seat", Vector3.new(9, 0.4, 1.6), cf * up(0, 1.8, z), PAL.wood, M.WoodPlanks)
			end
			for _, x in ipairs({ -3.4, 3.4 }) do
				K.part(m, "Leg", Vector3.new(0.5, 3.2, 7.6), cf * up(x, 1.6, 0), PAL.woodDark, M.Wood)
			end
		end
	end
	task.wait()
	-- trees, bushes, rocks
	local trees = 0
	for _ = 1, 150 do
		local p = spot(5, 12)
		if p then
			trees += 1
			local tree
			if rng:NextNumber() < 0.38 then
				tree = K.pine(scenery, p, rng:NextNumber(0.9, 1.5), rng)
			else
				tree = K.tree(scenery, p, rng:NextNumber(0.85, 1.5), rng)
			end
			-- (2026-11-13) no trees inside the activity circle (Build: SITES.treeFree). The tree is still BUILT and its
			-- spot still taken before it is thrown away, so the random sequence - and with it every bush, rock and
			-- tree outside the circle - lands exactly where it did before.
			local F = SITES.treeFree
			if F and math.sqrt((p.X - F.x) ^ 2 + (p.Z - F.z) ^ 2) <= F.r then
				tree:Destroy()
			end
		end
		if trees % 40 == 39 then
			task.wait()
		end
	end
	for _ = 1, 90 do
		local p = spot(2, 8)
		if p then
			if rng:NextNumber() < 0.55 then
				K.ball(scenery, "Bush", rng:NextNumber(3.5, 6), p + Vector3.new(0, 0.6, 0), ({ PAL.leaf, PAL.leaf2, PAL.leaf3 })[rng:NextInteger(1, 3)], M.Grass, { CastShadow = false })
			else
				local s = rng:NextNumber(2.5, 7)
				K.part(scenery, "Rock", Vector3.new(s, s * 0.7, s * 0.9), CFrame.new(p + Vector3.new(0, s * 0.2, 0)) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 6), rng:NextNumber(0, 1)), C(118, 116, 112), M.Slate)
			end
		end
	end
end
