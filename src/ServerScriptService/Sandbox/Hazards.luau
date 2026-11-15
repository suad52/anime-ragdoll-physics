--!nocheck
-- ServerScriptService.Sandbox.Hazards: everything in the map that hurts. The map only carries tags + attributes
-- (ServerStorage.SandboxGen builds them); this module gives them behaviour:
--   Conveyor (speed) - Trampoline (Power) - Saw (Spin, Damage) - Press (Travel, Period, Damage) - SpikeZone - Trapdoor /
--   TrapdoorButton - GasCanSpawn / BarrelSpawn (stocked with tag Explosive props) - Rocket / RocketStrap / RocketLaunch
--   - DisasterBox / DisasterButton (Kind) / DisasterDoor / DisasterLight / DisasterScreen - DummyDrain
-- H.init(ctx): ctx = { Injury, Dummies, Ragdoll, net(action, ...), credit(player, amount) }
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local H = {}
local Injury, Dummies, Ragdoll, net, credit
local releaseGrab -- (player): Main's grab release, so a machine can take a body out of a player's hand
local C = Color3.fromRGB
local SND = { boom = 138533090376585, boom2 = 3444652484, hit = 126976659766267, heavy = 79476956608476, slash = 125132253621935,
	zap = 103012429197748, thunder = 168586586, whoosh = 99266120255392, fire = 85699884807201, rise = 122439012218772 }
local function sfx(key, pos, vol, speed)
	local a = Instance.new("Attachment")
	a.WorldPosition = pos
	a.Parent = workspace.Terrain
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. string.format("%d", SND[key] or SND.hit)
	s.Volume, s.PlaybackSpeed = vol or 0.8, (speed or 1) * (0.95 + math.random() * 0.1)
	s.RollOffMinDistance, s.RollOffMaxDistance, s.RollOffMode = 14, 260, Enum.RollOffMode.InverseTapered
	s.Parent = a
	s:Play()
	Debris:AddItem(a, 6)
end
H.sfx = sfx
H.SND = SND -- (2026-11-13) Sandbox.Machines adds its own sounds
-- Every console button runs through here, so a Studio session can press one without a player standing at it:
-- <button>.DebugTrigger:Fire(player). The BindableEvent only exists in Studio.
H.buttons = {} -- (2026-11-13) button part -> its handler; Sandbox.Wanderers presses a few of these (fn(nil): no player)
local function onPrompt(pp, fn)
	pp.Triggered:Connect(fn)
	H.buttons[pp.Parent] = fn
	if game:GetService("RunService"):IsStudio() then
		local ev = Instance.new("BindableEvent")
		ev.Name = "DebugTrigger"
		ev.Parent = pp.Parent
		ev.Event:Connect(fn)
	end
end
H.onPrompt = onPrompt
local function tagged(tag)
	return CollectionService:GetTagged(tag)
end
local function playerOf(uid)
	return uid and Players:GetPlayerByUserId(uid) or nil
end
local function lastBy(m)
	return playerOf(m:GetAttribute("LastHitBy"))
end
local npcParams = OverlapParams.new()
npcParams.FilterType = Enum.RaycastFilterType.Include
local function refreshParams()
	npcParams.FilterDescendantsInstances = { Dummies.folder }
end
local function hurt(m, part, kind, amount, by, dir, pos)
	Injury.hit(m, { part = part, type = kind, amount = amount, attacker = by, dir = dir, pos = pos })
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		hum:TakeDamage(amount * 0.8)
	end
	if credit and by then
		credit(by, amount)
	end
end
H.hurt = hurt

------------------------------------------------------------------------------------------------------- explosives
local props = {} -- [part] = { marker?, owner? }
local function makeProp(kind, cf, owner)
	local p
	if kind == "barrel" then
		p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(4.2, 3, 3)
		p.CFrame = cf * CFrame.new(0, 2.1, 0) * CFrame.Angles(0, 0, math.pi / 2)
		p.Color, p.Material = C(178, 40, 36), Enum.Material.Metal
		p:SetAttribute("Radius", 24)
		p:SetAttribute("Power", 130)
	elseif kind == "crate" then
		p = Instance.new("Part")
		p.Size = Vector3.new(3.4, 3.4, 3.4)
		p.CFrame = cf * CFrame.new(0, 1.8, 0)
		p.Color, p.Material = C(150, 110, 66), Enum.Material.WoodPlanks
	else
		p = Instance.new("Part")
		p.Size = Vector3.new(1.7, 2.2, 1.1)
		p.CFrame = cf * CFrame.new(0, 1.2, 0)
		p.Color, p.Material = C(204, 36, 32), Enum.Material.SmoothPlastic
		p:SetAttribute("Radius", 15)
		p:SetAttribute("Power", 92)
		for _, d in ipairs({ { Vector3.new(0.9, 0.25, 0.3), CFrame.new(0, 1.3, 0), C(204, 36, 32) }, { Vector3.new(0.3, 0.5, 0.3), CFrame.new(0.55, 1.2, 0) * CFrame.Angles(0, 0, -0.5), C(240, 200, 60) } }) do
			local q = Instance.new("Part")
			q.Size, q.Color, q.Material = d[1], d[3], Enum.Material.SmoothPlastic
			q.CanCollide, q.CanQuery, q.Massless = false, false, true
			q.CFrame = p.CFrame * d[2]
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = p, q
			w.Parent = q
			q.Parent = p
		end
	end
	p.Name = (kind == "barrel" and "FuelDrum") or (kind == "crate" and "Crate") or "GasCan"
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.CustomPhysicalProperties = PhysicalProperties.new(kind == "crate" and 0.4 or 0.9, 0.6, 0.15)
	p:SetAttribute("Kind", kind)
	if owner then
		p:SetAttribute("Owner", owner.UserId)
	end
	p.Parent = Injury.gore()
	if kind ~= "crate" then
		CollectionService:AddTag(p, "Explosive")
		p.Touched:Connect(function(other)
			if other.Anchored or not p.Parent then
				local rel = p.AssemblyLinearVelocity.Magnitude
				if rel > 85 then
					H.explode(p, playerOf(p:GetAttribute("LastHitBy")))
				end
			end
		end)
	end
	props[p] = { owner = owner, kind = kind }
	return p
end
H.makeProp = makeProp
function H.ownerProps(player, kind)
	local n, oldest = 0, nil
	for p, rec in pairs(props) do
		if p.Parent and rec.owner == player and (not kind or rec.kind == kind) then
			n += 1
			oldest = oldest or p
		end
	end
	return n, oldest
end
function H.clearOwner(player)
	for p, rec in pairs(props) do
		if rec.owner == player then
			props[p] = nil
			p:Destroy()
		end
	end
end
-- a blast at a point (explosive props, rocket rounds, meteors)
function H.blastAt(pos, radius, power, by, quiet, vol)
	if not quiet and H.onBlast then -- (2026-11-13) Sandbox.Wanderers: a bang is heard round corners
		pcall(H.onBlast, pos, radius, by)
	end
	local e = Instance.new("Explosion")
	e.Position = pos
	e.BlastRadius = radius
	e.BlastPressure = quiet and 0 or 180000
	e.DestroyJointRadiusPercent = 0
	e.ExplosionType = Enum.ExplosionType.NoCraters
	e.Parent = workspace
	if vol ~= 0 then
		sfx(radius > 18 and "boom" or "boom2", pos, vol or 1, radius > 18 and 0.9 or 1.1)
	end
	refreshParams()
	local seen = {}
	for _, part in ipairs(workspace:GetPartBoundsInRadius(pos, radius, npcParams)) do
		local m = Dummies.of(part)
		if m and not seen[m] then
			seen[m] = true
			local best = Injury.blast(m, pos, radius, power, by)
			local hum = m:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				hum:TakeDamage(best * 1.1)
			end
			if credit and by then
				credit(by, best)
			end
			local root = m:FindFirstChild("UpperTorso") or m.PrimaryPart
			if root then
				local d = root.Position - pos
				local f = 1 - math.clamp(d.Magnitude / radius, 0, 1)
				Ragdoll.Fling(m, ((d.Magnitude > 0.1 and d.Unit or Vector3.yAxis) + Vector3.new(0, 0.7, 0)).Unit * (40 + 110 * f), nil, 2.6)
				if Ragdoll.LendNearest then
					Ragdoll.LendNearest(m, 120)
				end
			end
		end
	end
	for p in pairs(props) do -- chain reaction
		if p.Parent and CollectionService:HasTag(p, "Explosive") and (p.Position - pos).Magnitude < radius * 0.85 and not p:GetAttribute("Boom") then
			task.delay(0.08 + math.random() * 0.25, H.explode, p, by)
		end
	end
	if net then
		net("boom", pos, radius)
	end
end
function H.explode(p, by)
	if not p.Parent or p:GetAttribute("Boom") then
		return
	end
	p:SetAttribute("Boom", true)
	local pos = p.Position
	local radius, power = p:GetAttribute("Radius") or 15, p:GetAttribute("Power") or 90
	local rec = props[p]
	props[p] = nil
	p:Destroy()
	H.blastAt(pos, radius, power, by)
	-- the fire it leaves
	local f = Instance.new("Part")
	f.Anchored, f.CanCollide, f.CanQuery, f.CanTouch, f.Transparency = true, false, false, false, 1
	f.Size = Vector3.new(1, 1, 1)
	f.CFrame = CFrame.new(pos)
	f.Parent = Injury.gore()
	local fire = Instance.new("Fire")
	fire.Size, fire.Heat = radius * 0.7, 14
	fire.Parent = f
	local light = Instance.new("PointLight")
	light.Range, light.Brightness, light.Color = radius * 1.6, 3, C(255, 160, 70)
	light.Parent = f
	Debris:AddItem(f, 5)
	task.spawn(function()
		for _ = 1, 8 do
			task.wait(0.55)
			refreshParams()
			local seen = {}
			for _, part in ipairs(workspace:GetPartBoundsInRadius(pos, radius * 0.45, npcParams)) do
				local m = Dummies.of(part)
				if m and not seen[m] then
					seen[m] = true
					hurt(m, part, "burn", 9, by)
				end
			end
		end
	end)
	if rec and rec.marker then
		task.delay(16, function()
			if rec.marker.Parent then
				local np = makeProp(rec.kind, rec.marker.CFrame)
				props[np].marker = rec.marker
			end
		end)
	end
end
-- a weapon or a stray part hit something that is not a dummy
function H.damageProp(part, amount, by)
	if by and part and part.Parent and H.onPropHarm then -- (2026-11-13) Sandbox.Wanderers: smashing things up is seen too
		pcall(H.onPropHarm, part, amount, by)
	end
	if part and part.Parent and CollectionService:HasTag(part, "Explosive") then
		if by then
			part:SetAttribute("LastHitBy", by.UserId)
		end
		if amount >= 14 then
			H.explode(part, by)
			return true
		end
	end
	return false
end

----------------------------------------------------------------------------------------------------------- rocket
local function setupRocket(rocket)
	local body = rocket.PrimaryPart
	if not body then
		return
	end
	local home = rocket:GetPivot()
	local strap = rocket:FindFirstChild("Strap")
	local engine = rocket:FindFirstChild("Engine")
	local busy = false
	-- (2026-11-13) ANY number of bodies ride now. The console button still puts one on the strap; and a body a player
	-- CARRIES up against the rocket sticks to it right where it is - the owner: "they can attach to just where they
	-- are in terms of the rocket". The limb nearest the hull is welded to the part it is touching; the rest dangles.
	local riders = {} -- { model, weld }
	local strapRider
	-- (2026-11-13, second pass) STICK was 1.5, i.e. a limb had to be TOUCHING. Carried at hand height the red fins stick
	-- out furthest, so they caught every body first and the owner found "only the red parts" worked. Now being near is
	-- enough (4.5 studs from any part of the rocket), the trunk is preferred over a stray hand, and the body is pulled
	-- in until it rests on the hull before it is welded, so it ends up ON the rocket at the height and side it was held.
	local STICK = 4.5
	local screen = rocket.Parent and rocket.Parent:FindFirstChild("RocketScreen", true)
	local function show(text, color)
		local l = screen and screen:FindFirstChild("Label") and screen.Label:FindFirstChildOfClass("TextLabel")
		if l then
			l.Text = text
			l.TextColor3 = color or C(120, 255, 160)
		end
	end
	local function fx(on)
		if not engine then
			return
		end
		for _, d in ipairs(engine:GetDescendants()) do
			if d:IsA("ParticleEmitter") or d:IsA("PointLight") then
				d.Enabled = on
			end
		end
	end
	local function prune()
		for i = #riders, 1, -1 do
			local r = riders[i]
			if not r.model.Parent or not Dummies.is(r.model) or not r.weld.Parent then
				if r.model == strapRider then
					strapRider = nil
				end
				table.remove(riders, i)
			end
		end
	end
	local function attach(m, part, onto, player)
		if busy or m:GetAttribute("Strapped") or not part or not onto then
			return false
		end
		m:SetAttribute("Strapped", true)
		if player then
			m:SetAttribute("LastHitBy", player.UserId)
		end
		Ragdoll.Ragdoll(m, nil)
		for _, p in ipairs(m:GetChildren()) do
			if p:IsA("BasePart") then
				p.AssemblyLinearVelocity, p.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
			end
		end
		local w = Instance.new("WeldConstraint")
		w.Name = "RocketWeld"
		w.Part0, w.Part1 = onto, part
		w.Parent = part
		table.insert(riders, { model = m, weld = w })
		prune()
		show((#riders > 1) and (#riders .. " ON BOARD") or "STRAPPED IN", C(255, 200, 90))
		sfx("hit", part.Position, 0.7, 0.8)
		return true
	end
	for _, b in ipairs(tagged("RocketStrap")) do
		local pp = b:FindFirstChildOfClass("ProximityPrompt")
		if pp and b:IsDescendantOf(rocket.Parent) then
			onPrompt(pp, function(player)
				prune()
				if busy or strapRider or not strap then
					return
				end
				local best, bd
				for m in pairs(Dummies.records) do
					local t = m:FindFirstChild("UpperTorso")
					if t and not m:GetAttribute("Strapped") and not m:GetAttribute("GrabbedBy") then
						local d = (t.Position - strap.Position).Magnitude
						if d < 55 and (not bd or d < bd) then
							best, bd = m, d
						end
					end
				end
				if not best then
					show("NO DUMMY NEARBY", C(255, 200, 90))
					return
				end
				Ragdoll.Ragdoll(best, nil)
				local t = best:FindFirstChild("UpperTorso")
				local at = strap.CFrame * CFrame.new(0, 0, -0.9) * CFrame.Angles(0, math.pi, 0)
				best:PivotTo(at)
				t.CFrame = at
				if attach(best, t, strap, player) then
					strapRider = best
				end
			end)
		end
	end
	for _, b in ipairs(tagged("RocketLaunch")) do
		local pp = b:FindFirstChildOfClass("ProximityPrompt")
		if pp and b:IsDescendantOf(rocket.Parent) then
			onPrompt(pp, function(player)
				if busy then
					return
				end
				busy = true
				for n = 3, 1, -1 do
					show("T - " .. n, C(255, 90, 70))
					sfx("zap", body.Position, 0.5, 0.7)
					task.wait(1)
				end
				show("LIFTOFF", C(255, 90, 70))
				-- on the pad a rider hangs by the one limb that touched the hull; for the flight EVERY part is pinned to it.
				-- The rocket is pivoted, not simulated (up to ~390 studs/s): held by a hand alone, the body stretched out and
				-- trailed 700 studs behind it (measured)
				prune()
				for _, r in ipairs(riders) do
					for _, p in ipairs(r.model:GetChildren()) do
						if p:IsA("BasePart") and p ~= r.weld.Part1 then
							p.AssemblyLinearVelocity, p.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
							local w = Instance.new("WeldConstraint")
							w.Name = "RocketFlightWeld"
							w.Part0, w.Part1 = body, p
							w.Parent = p
						end
					end
				end
				fx(true)
				sfx("boom", body.Position, 1, 0.6)
				sfx("fire", body.Position, 1, 0.8)
				if net then
					net("boom", body.Position, 60)
				end
				local y, v = 0, 4
				local conn
				conn = RunService.Heartbeat:Connect(function(dt)
					v += 70 * dt
					y += v * dt
					rocket:PivotTo((home + Vector3.new(0, y, 0)))
				end)
				while y < 1100 do
					task.wait(0.1)
				end
				conn:Disconnect()
				fx(false)
				local top = ((home + Vector3.new(0, y, 0))).Position
				sfx("boom", top, 1, 0.8)
				prune()
				for _, r in ipairs(riders) do
					local rider = r.model
					if rider.Parent then
						local hum = rider:FindFirstChildOfClass("Humanoid")
						local st = Injury.get(rider)
						if st then
							st.fatal = "Lost in space"
						end
						if player then
							rider:SetAttribute("LastHitBy", player.UserId)
						end
						if hum and hum.Health > 0 then
							hum.Health = 0
						end
					end
				end
				task.wait(0.2)
				for _, r in ipairs(riders) do
					if r.model.Parent then
						Dummies.remove(r.model, false)
					end
				end
				riders, strapRider = {}, nil
				for _, d in ipairs(rocket:GetDescendants()) do
					if d:IsA("BasePart") then
						d.LocalTransparencyModifier = 0
					end
				end
				rocket:PivotTo((home + Vector3.new(0, -200, 0)))
				show("REFUELLING", C(255, 200, 90))
				task.wait(5)
				rocket:PivotTo(home)
				show("READY", C(120, 255, 160))
				busy = false
			end)
		end
	end
	-- carried bodies stick: ten times a second, any GRABBED dummy with a limb within STICK studs of the hull
	local hull = {}
	for _, d in ipairs(rocket:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide then
			table.insert(hull, d)
		end
	end
	-- It sticks once it is being HELD there (near the rocket and all but still for 0.3 s), not the instant it passes:
	-- with the wider reach the fins snatched every body on its way up to the hull (measured in a 12-position sweep).
	-- The trunk is taken over a stray hand whenever it is in reach, and the fins lose a tie with the hull.
	local holding = setmetatable({}, { __mode = "k" })
	task.spawn(function()
		while rocket.Parent do
			task.wait(0.1)
			if not busy then
				local c = body.Position
				for m, rec in pairs(Dummies.records) do
					local uid = m:GetAttribute("GrabbedBy")
					if uid and not m:GetAttribute("Strapped") and ((rec.hrp.Position - c) * Vector3.new(1, 0, 1)).Magnitude < 24 then
						local bestPart, bestOnto, bestQ, bd, score
						for _, p in ipairs(m:GetChildren()) do
							if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
								local trunk = (p.Name == "UpperTorso" or p.Name == "LowerTorso") and 5 or 0
								for _, h in ipairs(hull) do
									local q = h:GetClosestPointOnSurface(p.Position)
									local d = (q - p.Position).Magnitude
									local s = d - trunk + ((h.Name == "Fin") and 1.5 or 0)
									if d <= STICK and (not score or s < score) then
										bestPart, bestOnto, bestQ, bd, score = p, h, q, d, s
									end
								end
							end
						end
						local torso = m:FindFirstChild("UpperTorso") or rec.hrp
						if bestPart and torso.AssemblyLinearVelocity.Magnitude < 9 then
							holding[m] = (holding[m] or 0) + 0.1
						else
							holding[m] = nil
						end
						if bestPart and (holding[m] or 0) >= 0.3 then
							holding[m] = nil
							local player = Players:GetPlayerByUserId(uid)
							if player and releaseGrab then
								releaseGrab(player) -- the hand lets go; the rocket has it now
							end
							-- pull the whole body in until that part rests on the hull
							local rest = math.min(bestPart.Size.X, bestPart.Size.Y, bestPart.Size.Z) * 0.5 + 0.05
							if bd > rest then
								m:PivotTo(m:GetPivot() + (bestQ - bestPart.Position).Unit * (bd - rest))
							end
							attach(m, bestPart, bestOnto, player)
						end
					end
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------------------------------- disasters
-- (2026-11-13) the owner's pass on the box:
--   * SEVERAL AT ONCE. There is no box-wide "busy" any more: each kind has its own run record, the door shuts on
--     the first one in and opens after the last one out. A kind that is already running ignores its own button.
--   * END. The red button on its own pedestal (Kind = "End") sets run.stop on everything running. Every RUN loop
--     watches that flag; whatever a RUN makes it lists in run.undo, which is run afterwards however it ended.
--   * FLOOD could not be seen. The walls were Material.Glass, and Roblox does not draw a see-through part that
--     sits behind Glass: the water only ever showed through the doorway. The walls are plain see-through plastic
--     now (generator + live map), the water has a lighter surface sheet and four jets pour in while it fills.
--     StarterPlayerScripts.FloodView tints the screen when the camera goes under (a part has no inside faces).
--   * LIGHTNING hits every living body in the box in one volley, and between volleys each one stays on an arc
--     from the roof with the Tesla coil's own effect (H.zap, lent by Sandbox.Machines: x-ray skeleton, held and
--     convulsing, charring). Anything still alive when it stops walks away scorched, as with the coil.
--   * METEORS: rocks 7-11 studs across coming in from the sky about five a second (it was one 4-stud rock every
--     0.7 s), each landing as one big blast and two smaller ones beside it.
local function setupDisaster(floor)
	local inner = floor:GetAttribute("Inner") or Vector3.new(60, 36, 60)
	local home = floor.CFrame -- where the floor rests (the quake shakes it)
	local base = home * CFrame.new(0, floor.Size.Y / 2, 0) -- centre of the floor's top
	local area = floor.Parent
	local door, screen
	for _, d in ipairs(area:GetDescendants()) do
		if d.Name == "DisasterDoor" then
			door = d
		elseif d.Name == "DisasterScreen" then
			screen = d
		end
	end
	local doorHome = door and door.CFrame
	local RED, AMBER, GREEN = C(255, 60, 50), C(255, 200, 80), C(90, 230, 130)
	local function show(text, color)
		local l = screen and screen:FindFirstChild("Label") and screen.Label:FindFirstChildOfClass("TextLabel")
		if l then
			l.Text, l.TextColor3 = text, color or C(120, 255, 160)
		end
	end
	local function lights(color)
		for _, l in ipairs(tagged("DisasterLight")) do
			if l:IsDescendantOf(area) then
				l.Color = color
				local pl = l:FindFirstChildOfClass("PointLight")
				if pl then
					pl.Color = color
				end
			end
		end
	end
	local function inside()
		refreshParams()
		local list, seen = {}, {}
		for _, part in ipairs(workspace:GetPartBoundsInBox(base * CFrame.new(0, inner.Y / 2, 0), inner, npcParams)) do
			local m = Dummies.of(part)
			if m and not seen[m] then
				seen[m] = true
				table.insert(list, m)
			end
		end
		return list
	end
	local function living(m)
		local rec = Dummies.records and Dummies.records[m]
		return rec ~= nil and not rec.dead and not m:GetAttribute("Invuln")
	end
	local function rnd()
		return base * CFrame.new((math.random() - 0.5) * (inner.X - 8), 0, (math.random() - 0.5) * (inner.Z - 8))
	end
	local function blame(m, by)
		if by then
			m:SetAttribute("LastHitBy", by.UserId)
		end
	end
	local function holder(name) -- an invisible anchored part to hang particles / lights / attachments on
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Transparency = 1
		p.Size = Vector3.new(1, 1, 1)
		return p
	end
	local LIMBS = { "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }
	local function anyPart(m) -- a limb that is still attached (a severed one has left the model)
		for _ = 1, 4 do
			local p = m:FindFirstChild(LIMBS[math.random(#LIMBS)])
			if p then
				return p
			end
		end
		return m:FindFirstChild("UpperTorso")
	end
	local RUN = {}
	function RUN.Tornado(by, run)
		local funnel = Instance.new("Model")
		funnel.Name = "Tornado"
		table.insert(run.undo, function()
			funnel:Destroy()
		end)
		local rings = {}
		for i = 1, 9 do
			local r = Instance.new("Part")
			r.Shape = Enum.PartType.Cylinder
			r.Anchored, r.CanCollide, r.CanQuery, r.CanTouch, r.CastShadow = true, false, false, false, false
			r.Material, r.Color, r.Transparency = Enum.Material.SmoothPlastic, C(150, 156, 166), 0.62
			r.Size = Vector3.new(3.4, 4 + i * 2.6, 4 + i * 2.6)
			r.Parent = funnel
			rings[i] = r
		end
		funnel.Parent = Injury.gore()
		local t0 = os.clock()
		local centre = rnd()
		local target = rnd()
		local batter = {} -- per dummy: when the next piece of debris may hit it
		while not run.stop and os.clock() - t0 < 13 do
			local dt = task.wait()
			if (centre.Position - target.Position).Magnitude < 3 then
				target = rnd()
			end
			centre = centre + (target.Position - centre.Position).Unit * 14 * dt
			local t = os.clock() - t0
			for i, r in ipairs(rings) do
				local sway = Vector3.new(math.sin(t * 2 + i * 0.5), 0, math.cos(t * 1.7 + i * 0.6)) * i * 0.35
				r.CFrame = CFrame.new(centre.Position + sway + Vector3.new(0, i * 3.4 - 1, 0)) * CFrame.Angles(0, t * 6 + i, math.pi / 2)
			end
			for _, m in ipairs(inside()) do
				Ragdoll.Ragdoll(m, 3)
				blame(m, by)
				local torso = m:FindFirstChild("UpperTorso")
				local near = 0
				for _, p in ipairs(m:GetChildren()) do
					if p:IsA("BasePart") and not p.Anchored then
						local d = (p.Position - centre.Position) * Vector3.new(1, 0, 1)
						local dist = math.max(d.Magnitude, 1)
						local pull = math.clamp(1 - dist / 40, 0, 1)
						if pull > 0 then
							local tang = Vector3.yAxis:Cross(d / dist)
							local low = p.Position.Y - base.Position.Y < inner.Y * 0.68
							local want = tang * 66 * pull - (d / dist) * 26 * pull + Vector3.new(0, low and (24 + 44 * pull) or -8, 0)
							p.AssemblyLinearVelocity = p.AssemblyLinearVelocity:Lerp(want, math.min(1, dt * (5 + 16 * pull)))
						end
						if p == torso then
							near = pull
						end
					end
				end
				if near > 0.45 and t > (batter[m] or 0) then
					batter[m] = t + 0.55 + math.random() * 0.5
					local part = anyPart(m)
					if part then
						hurt(m, part, "blunt", math.random(7, 15), by, nil, part.Position)
					end
				end
			end
		end
	end
	function RUN.Quake(by, run)
		table.insert(run.undo, function()
			floor.CFrame = home
		end)
		local t0 = os.clock()
		local nextJolt = 0
		while not run.stop and os.clock() - t0 < 10 do
			task.wait()
			local t = os.clock() - t0
			floor.CFrame = home * CFrame.new(math.sin(t * 38) * 0.5, math.sin(t * 51) * 0.22, math.cos(t * 43) * 0.5)
			if t > nextJolt then
				nextJolt = t + 0.45
				for _, m in ipairs(inside()) do
					blame(m, by)
					Ragdoll.Fling(m, Vector3.new(math.random(-34, 34), math.random(34, 62), math.random(-34, 34)), nil, 2.5)
					if math.random() < 0.45 then -- thrown into the floor
						local part = anyPart(m)
						if part then
							hurt(m, part, "blunt", math.random(6, 14), by, -Vector3.yAxis, part.Position)
						end
					end
				end
				if net then
					net("boom", base.Position, 50)
				end
			end
		end
	end
	function RUN.Meteors(by, run)
		local sky = {} -- rocks still falling -> their tween, so END can take them out of the air
		table.insert(run.undo, function()
			for rock, tw in pairs(sky) do
				sky[rock] = nil
				tw:Cancel()
				rock:Destroy()
			end
		end)
		-- the whole shower comes in on one slant, like a real one
		local slant = CFrame.Angles(0, math.random() * math.pi * 2, 0) * Vector3.new(36, 0, 0)
		local function land(goal, size)
			H.blastAt(goal, 11 + size, 100, by)
			-- the rock breaks up: two smaller blasts beside the first, a beat later (one of them silent - the ear
			-- cannot take sixteen bangs a second)
			for i = 1, 2 do
				local off = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * (10 + size * 1.4)
				task.delay(0.08 + math.random() * 0.24, function()
					if not run.stop then
						H.blastAt(goal + off, 9, 48, by, false, i == 1 and 0.4 or 0)
					end
				end)
			end
			-- what it leaves: a scorch that fades, a fire that burns out, shards thrown clear
			local mark = Instance.new("Part")
			mark.Name = "MeteorScorch"
			mark.Shape = Enum.PartType.Cylinder
			mark.Anchored, mark.CanCollide, mark.CanQuery, mark.CanTouch, mark.CastShadow = true, false, false, false, false
			mark.Material, mark.Color, mark.Transparency = Enum.Material.Slate, C(22, 18, 16), 0.15
			mark.Size = Vector3.new(0.14, size * 1.7, size * 1.7)
			mark.CFrame = CFrame.new(goal.X, base.Position.Y + 0.09, goal.Z) * CFrame.Angles(0, 0, math.pi / 2)
			mark.Parent = Injury.gore()
			TweenService:Create(mark, TweenInfo.new(5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
			Debris:AddItem(mark, 5.2)
			local f = holder("MeteorFire")
			f.CFrame = CFrame.new(goal)
			local fire = Instance.new("Fire")
			fire.Size, fire.Heat = size * 1.3, 12
			fire.Parent = f
			f.Parent = Injury.gore()
			Debris:AddItem(f, 2.2)
			for _ = 1, 4 do
				local d = 0.8 + math.random() * 1.4
				local sh = Instance.new("Part")
				sh.Name = "MeteorShard"
				sh.Size = Vector3.new(d, d, d)
				sh.Color, sh.Material = C(60, 40, 34), Enum.Material.Slate
				sh.CanCollide, sh.CanQuery, sh.CanTouch, sh.CastShadow = false, false, false, false
				sh.CFrame = CFrame.new(goal + Vector3.new(0, 1.5, 0)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
				sh.Parent = Injury.gore()
				sh.AssemblyLinearVelocity = Vector3.new(math.random(-42, 42), math.random(36, 78), math.random(-42, 42))
				sh.AssemblyAngularVelocity = Vector3.new(math.random(-20, 20), math.random(-20, 20), math.random(-20, 20))
				Debris:AddItem(sh, 1.5)
			end
		end
		local count = 0
		local function launch()
			count += 1
			local size = 7 + math.random() * 4
			local goal = rnd().Position + Vector3.new(0, size * 0.3, 0)
			local from = goal + Vector3.new(0, 96, 0) + slant + Vector3.new((math.random() - 0.5) * 16, 0, (math.random() - 0.5) * 16)
			local rock = Instance.new("Part")
			rock.Name = "Meteor"
			rock.Shape = Enum.PartType.Ball
			rock.Size = Vector3.new(size, size, size)
			rock.Color, rock.Material = C(60, 40, 34), Enum.Material.Slate
			rock.Anchored, rock.CanCollide, rock.CanQuery, rock.CanTouch, rock.CastShadow = true, false, false, false, false
			rock.CFrame = CFrame.new(from)
			local fire = Instance.new("Fire")
			fire.Size, fire.Heat = size * 2.2, 0
			fire.Parent = rock
			local pl = Instance.new("PointLight")
			pl.Range, pl.Brightness, pl.Color, pl.Shadows = 44, 4, C(255, 140, 60), false
			pl.Parent = rock
			local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment") -- the streak behind it
			a0.Position, a1.Position = Vector3.new(size * 0.42, 0, 0), Vector3.new(-size * 0.42, 0, 0)
			a0.Parent, a1.Parent = rock, rock
			local tr = Instance.new("Trail")
			tr.Attachment0, tr.Attachment1 = a0, a1
			tr.Lifetime, tr.LightEmission, tr.FaceCamera = 0.5, 1, true
			tr.Color = ColorSequence.new(C(255, 214, 130), C(255, 70, 20))
			tr.Transparency = NumberSequence.new(0.1, 1)
			tr.WidthScale = NumberSequence.new(1, 0.15)
			tr.Parent = rock
			rock.Parent = Injury.gore()
			local tw = TweenService:Create(rock, TweenInfo.new(0.8 + math.random() * 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(goal) })
			sky[rock] = tw
			tw.Completed:Connect(function(state)
				if sky[rock] then
					sky[rock] = nil
					rock:Destroy()
					if state == Enum.PlaybackState.Completed and not run.stop then
						land(goal, size)
					end
				end
			end)
			tw:Play()
			if count % 2 == 1 then
				sfx("whoosh", from:Lerp(goal, 0.6), 0.5, 0.8)
			end
		end
		local t0 = os.clock()
		while not run.stop and os.clock() - t0 < 12 do
			launch()
			if math.random() < 0.3 then
				launch() -- now and then a pair
			end
			task.wait(0.17 + math.random() * 0.15)
		end
		local t1 = os.clock() -- let the last ones land
		while not run.stop and next(sky) and os.clock() - t1 < 1.6 do
			task.wait(0.1)
		end
		if not run.stop then
			task.wait(0.6)
		end
	end
	function RUN.Lightning(by, run)
		local Z = H.zap -- the Tesla coil's arc, lent by Sandbox.Machines (nil if it has not set up: bolts only)
		local roofY = base.Position.Y + inner.Y - 0.8
		local held = {} -- body -> { V = the arc's own state, T = its source up at the roof }
		local retry = {} -- body -> when to try latching again (something else has it on an arc)
		table.insert(run.undo, function()
			for m, hd in pairs(held) do
				held[m] = nil
				pcall(Z.stop, m, hd.V)
				hd.T.part:Destroy()
			end
		end)
		local function strike(from, to, thick) -- one jagged bolt, gone in a blink
			local bolt = Instance.new("Model")
			bolt.Name = "Lightning"
			local last = from
			local n = 7
			for i = 1, n do
				local nxt = (i == n) and to or (from:Lerp(to, i / n) + Vector3.new((math.random() - 0.5) * 8, 0, (math.random() - 0.5) * 8))
				local seg = Instance.new("Part")
				seg.Anchored, seg.CanCollide, seg.CanQuery, seg.CanTouch, seg.CastShadow = true, false, false, false, false
				seg.Material, seg.Color = Enum.Material.Neon, C(225, 238, 255)
				seg.Size = Vector3.new(thick, thick, (nxt - last).Magnitude)
				seg.CFrame = CFrame.lookAt((last + nxt) / 2, nxt)
				seg.Parent = bolt
				last = nxt
			end
			bolt.Parent = Injury.gore()
			Debris:AddItem(bolt, 0.18)
		end
		local function volley(list) -- EVERYONE, in the same instant
			local hit = 0
			for _, m in ipairs(list) do
				local torso = m:FindFirstChild("UpperTorso") or m.PrimaryPart
				if torso then
					hit += 1
					local at = torso.Position
					strike(Vector3.new(at.X, roofY, at.Z), at, 1.1)
					blame(m, by)
					-- (as the coil does) a bumped HitSeq tells HitReactServer this hit is spoken for: no shove
					m:SetAttribute("HitSeq", (m:GetAttribute("HitSeq") or 0) + 1)
					hurt(m, "UpperTorso", "shock", 26, by)
				end
			end
			if hit == 0 then -- an empty box still gets its storm
				for _ = 1, 4 do
					local at = rnd().Position
					strike(Vector3.new(at.X, roofY, at.Z), at, 0.9)
				end
			end
			local f = holder("LightningFlash") -- one flash and one clap for the lot
			f.CFrame = base * CFrame.new(0, inner.Y * 0.6, 0)
			local l = Instance.new("PointLight")
			l.Range, l.Brightness, l.Color, l.Shadows = 60, 14, C(220, 235, 255), false
			l.Parent = f
			f.Parent = Injury.gore()
			Debris:AddItem(f, 0.2)
			sfx("thunder", base.Position + Vector3.new(0, inner.Y / 2, 0), 1, 0.9 + math.random() * 0.3)
			if net then
				net("boom", base.Position, 30)
			end
		end
		local t0, last, nextVolley = os.clock(), os.clock(), 0
		while not run.stop and os.clock() - t0 < 11 do
			task.wait(0.06)
			local now = os.clock()
			local step = math.min(now - last, 0.25)
			last = now
			local list, seen = {}, {}
			for _, m in ipairs(inside()) do
				if living(m) then
					table.insert(list, m)
					seen[m] = true
				end
			end
			if now - t0 >= nextVolley then
				nextVolley = (now - t0) + 1.5 + math.random() * 0.7
				volley(list)
			end
			if Z then
				for _, m in ipairs(list) do
					local torso = m:FindFirstChild("UpperTorso")
					local hd = held[m]
					if not hd and torso and now >= (retry[m] or 0) then
						local src = holder("LightningSource")
						src:SetAttribute("Damage", 38)
						src.CFrame = CFrame.new(torso.Position.X, roofY, torso.Position.Z)
						src.Parent = Injury.gore()
						local T = { part = src, G = { by = by } }
						local V = Z.start(T, m)
						if V then
							hd = { V = V, T = T }
							held[m] = hd
						else
							src:Destroy()
							retry[m] = now + 0.6
						end
					end
					if hd then
						if torso then -- the arc comes straight down on it, wherever it has been thrown
							hd.T.part.CFrame = CFrame.new(torso.Position.X, roofY, torso.Position.Z)
						end
						Z.tick(hd.T, m, hd.V, step, now)
					end
				end
				for m, hd in pairs(held) do
					if not seen[m] or not m.Parent then -- dead, dragged out or gone: let go (the coil's own ending)
						held[m] = nil
						Z.stop(m, hd.V)
						hd.T.part:Destroy()
					end
				end
			end
		end
	end
	function RUN.Flood(by, run)
		local TOP, RISE, HOLD, DRAIN = 22, 6, 7, 3.5
		local spanX, spanZ = inner.X - 0.4, inner.Z - 0.4
		local made = {}
		table.insert(run.undo, function()
			for _, o in ipairs(made) do
				o:Destroy()
			end
		end)
		-- LAG (2026-11-15, owner: "fix the lag on the flooding event"): the water used to be two huge server parts
		-- tweened ten times a second, and every step of every tween was streamed to every player. Now the server only
		-- keeps a tiny invisible FloodRig with a Level attribute (10 small updates a second); each player's own
		-- StarterPlayerScripts.FloodView draws the water and its surface from it and glides them every frame.
		local water = Instance.new("Part")
		water.Name = "FloodRig"
		water.Anchored, water.CanCollide, water.CanQuery, water.CanTouch, water.CastShadow = true, false, false, false, false
		water.Transparency = 1
		water.Size = Vector3.new(1, 1, 1)
		water.CFrame = base -- the centre of the floor's top
		water:SetAttribute("SpanX", spanX)
		water:SetAttribute("SpanZ", spanZ)
		water:SetAttribute("Level", 0.2)
		CollectionService:AddTag(water, "FloodRig")
		table.insert(made, water)
		local snd = Instance.new("Sound")
		snd.SoundId = "rbxassetid://9120551511" -- "Waterfall Heavy Water Flow 1 (SFX)", Pro Sound Effects (Creator Store)
		snd.Looped, snd.Volume = true, 0.9
		snd.RollOffMinDistance, snd.RollOffMaxDistance, snd.RollOffMode = 34, 280, Enum.RollOffMode.InverseTapered
		snd.Parent = water
		water.Parent = Injury.gore()
		snd:Play()
		local jets = {} -- four pipes' worth pouring in from the roof while it fills
		for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
			local j = holder("FloodJet")
			j.Size = Vector3.new(3, 0.4, 3)
			j.CFrame = base * CFrame.new(c[1] * (inner.X / 2 - 7), inner.Y - 1, c[2] * (inner.Z / 2 - 7))
			local e = Instance.new("ParticleEmitter")
			e.Texture = "rbxasset://textures/particles/smoke_main.dds"
			e.EmissionDirection = Enum.NormalId.Bottom
			e.Rate, e.Speed = 28, NumberRange.new(38, 42) -- (2026-11-15) was 60: half the see-through smoke to draw
			e.SpreadAngle = Vector2.new(4, 4)
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 4.6) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.8, 0.45), NumberSequenceKeypoint.new(1, 1) })
			e.Color = ColorSequence.new(C(200, 230, 255), C(96, 166, 236))
			e.LightEmission, e.LightInfluence = 0.2, 1
			e.Rotation, e.RotSpeed = NumberRange.new(0, 360), NumberRange.new(-60, 60)
			e.Parent = j
			j.Parent = Injury.gore()
			table.insert(made, j)
			table.insert(jets, e)
		end
		local level, t0, drown, pulled = 0.2, os.clock(), {}, nil
		local glide = TweenInfo.new(0.1, Enum.EasingStyle.Linear)
		while true do
			local dt = task.wait(0.1)
			local t = os.clock() - t0
			if run.stop and not pulled then
				pulled = { at = t, from = level } -- END pulls the plug: gone in a second, not in a blink
			end
			local filling = false
			if pulled then
				level = pulled.from * (1 - (t - pulled.at) / 1)
			elseif t < RISE then
				level, filling = TOP * t / RISE, true
			elseif t < RISE + HOLD then
				level = TOP
			else
				level = TOP * (1 - (t - RISE - HOLD) / DRAIN)
			end
			if level <= 0.2 and not filling then
				break
			end
			level = math.max(level, 0.2)
			water:SetAttribute("Level", level) -- FloodView glides to it on every screen
			if pulled then
				water:SetAttribute("Pulled", true)
			end
			local fall = math.max(0.15, (inner.Y - 1 - level) / 40) -- a jet stops at the surface, not at the floor
			for _, e in ipairs(jets) do
				if e.Enabled ~= filling then
					e.Enabled = filling
				end
				if filling then
					e.Lifetime = NumberRange.new(fall * 0.9, fall)
				end
			end
			snd.Volume = filling and 0.9 or (pulled and 0.5 or 0.3)
			local top = base.Position.Y + level
			for _, m in ipairs(inside()) do
				local head = m:FindFirstChild("Head")
				local waist = m:FindFirstChild("LowerTorso") or m:FindFirstChild("UpperTorso")
				if waist and waist.Position.Y < top then -- it has reached the waist: off its feet and afloat
					Ragdoll.Ragdoll(m, 2)
					for _, p in ipairs(m:GetChildren()) do
						if p:IsA("BasePart") and not p.Anchored and p.Position.Y < top then
							p.AssemblyLinearVelocity = p.AssemblyLinearVelocity * 0.86 + Vector3.new(math.sin(t * 2) * 1.5, 5.5, math.cos(t * 1.6) * 1.5)
						end
					end
				end
				if head and head.Position.Y < top - 0.5 then
					drown[m] = (drown[m] or 0) + dt
					local st = Injury.get(m)
					if st and not st.dead then
						st.touched = true
						st.awakeCap = math.max(0, 100 - drown[m] * 16)
						if drown[m] > 7 then
							blame(m, by)
							st.fatal = "Drowned"
							st.heartStopAt = st.heartStopAt or os.clock()
						end
					end
				else
					drown[m] = math.max(0, (drown[m] or 0) - dt * 0.5)
				end
			end
		end
	end

	local active, order, gen = {}, {}, 0 -- kind -> its run; the kinds in the order they started; bumps on every change
	local function status()
		local n = #order
		if n == 1 then
			show(string.upper(order[1]), RED)
		elseif n == 2 then
			show(string.upper(order[1]) .. " + " .. string.upper(order[2]), RED)
		elseif n > 2 then
			show(n .. " DISASTERS", RED)
		end
	end
	local function start(kind, player)
		if not RUN[kind] or active[kind] then
			return
		end
		local by = (typeof(player) == "Instance" and player:IsA("Player")) and player or nil
		local run = { stop = false, undo = {} }
		active[kind] = run
		table.insert(order, kind)
		gen += 1
		lights(RED)
		sfx("zap", base.Position, 0.8, 0.6)
		if #order == 1 then -- the first one in shuts the door
			show(string.upper(kind) .. " INCOMING", RED)
			if door then
				TweenService:Create(door, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { CFrame = doorHome * CFrame.new(door:GetAttribute("Slide") or -12, 0, 0) }):Play()
			end
			task.wait(1.2)
		end
		if not run.stop then
			status()
			local ok, err = pcall(RUN[kind], by, run)
			if not ok then
				warn("[Hazards] disaster " .. tostring(kind) .. ": " .. tostring(err))
			end
		end
		for _, fn in ipairs(run.undo) do -- whatever it made comes down, however it ended
			pcall(fn)
		end
		active[kind] = nil
		local i = table.find(order, kind)
		if i then
			table.remove(order, i)
		end
		gen += 1
		if #order > 0 then
			status()
			return
		end
		local mine = gen -- the last one out opens the door
		if door then
			TweenService:Create(door, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { CFrame = doorHome }):Play()
		end
		lights(AMBER)
		show("COOLING DOWN", AMBER)
		task.wait(3)
		if gen == mine then -- nothing was started while it cooled
			lights(GREEN)
			show("STANDBY", C(120, 255, 160))
		end
	end
	local function stopAll()
		if #order == 0 then
			return
		end
		for _, run in pairs(active) do
			run.stop = true
		end
		show("STOPPING", AMBER)
		sfx("zap", base.Position, 0.8, 0.45)
	end
	for _, b in ipairs(tagged("DisasterButton")) do
		local pp = b:FindFirstChildOfClass("ProximityPrompt")
		if pp and b:IsDescendantOf(area) then
			local kind = b:GetAttribute("Kind")
			onPrompt(pp, function(player)
				if kind == "End" then
					stopAll()
				else
					start(kind, player)
				end
			end)
		end
	end
end

--------------------------------------------------------------------------------------------------------------- init
function H.init(ctx)
	Injury, Dummies, Ragdoll, net, credit = ctx.Injury, ctx.Dummies, ctx.Ragdoll, ctx.net, ctx.credit
	releaseGrab = ctx.release
	for _, p in ipairs(tagged("Conveyor")) do
		p.AssemblyLinearVelocity = p.CFrame.LookVector * (p:GetAttribute("Conveyor") or 10)
	end
	-- trampolines (dummies and loose props; a player's own bounce is done on their client)
	local bounced = setmetatable({}, { __mode = "k" })
	for _, mat in ipairs(tagged("Trampoline")) do
		mat.Touched:Connect(function(hit)
			if hit.Anchored then
				return
			end
			local m = Dummies.of(hit)
			local key = m or hit
			local t = os.clock()
			if (bounced[key] or 0) > t then
				return
			end
			bounced[key] = t + 0.3
			local power = mat:GetAttribute("Power") or 90
			if m then
				Ragdoll.Ragdoll(m, 2.2)
				for _, p in ipairs(m:GetChildren()) do
					if p:IsA("BasePart") then
						local v = p.AssemblyLinearVelocity
						p.AssemblyLinearVelocity = Vector3.new(v.X * 0.7 + math.random(-6, 6), power, v.Z * 0.7 + math.random(-6, 6))
					end
				end
				-- (2026-11-14) it will come down on the mat again, and the SERVER bounces it: a body a client simulated
				-- would sit on the mat until the server noticed. The server keeps it while it bounces.
				if Ragdoll.Hold then
					Ragdoll.Hold(m, 2.5)
				end
			elseif not Players:GetPlayerFromCharacter(hit.Parent) and not Players:GetPlayerFromCharacter(hit.Parent.Parent) then
				local v = hit.AssemblyLinearVelocity
				hit.AssemblyLinearVelocity = Vector3.new(v.X, power * 0.8, v.Z)
			end
			sfx("whoosh", mat.Position, 0.5, 0.7)
		end)
	end
	-- saws + press + spikes + drain: one loop
	local saws, presses = {}, {}
	for _, s in ipairs(tagged("Saw")) do
		table.insert(saws, { part = s, spin = s:GetAttribute("Spin") or 18, dmg = s:GetAttribute("Damage") or 38, hitAt = setmetatable({}, { __mode = "k" }) })
	end
	for _, p in ipairs(tagged("Press")) do
		p.CanCollide = false
		table.insert(presses, { part = p, home = p.CFrame, travel = p:GetAttribute("Travel") or 5, period = p:GetAttribute("Period") or 3.4, dmg = p:GetAttribute("Damage") or 90, slammed = false })
	end
	local zones, drains = tagged("SpikeZone"), tagged("DummyDrain")
	-- (2026-11-14, owner: "the npcs arent getting incinerated in the fire pit at the end of it") a DummyDrain with
	-- attribute Mode = "fire" (the Factory's pit) burns what lands in it instead of grinding it: it catches fire, chars
	-- black all over (Injury.char: one charring, no line per limb), dies "Incinerated" and burns away in ~3 s.
	local burning = setmetatable({}, { __mode = "k" })
	local function incinerate(m, part)
		burning[m] = true
		local st = Injury.get(m)
		if st then
			st.fatal = "Incinerated"
		end
		local pos = part.Position
		sfx("fire", pos, 0.9, 1)
		sfx("whoosh", pos, 0.6, 0.6)
		local flames = {}
		for _, n in ipairs({ "UpperTorso", "LowerTorso", "Head", "LeftUpperLeg", "RightUpperLeg", "LeftUpperArm", "RightUpperArm" }) do
			local p = m:FindFirstChild(n)
			if p then
				local f = Instance.new("Fire")
				f.Size, f.Heat = (n == "UpperTorso" or n == "LowerTorso") and 7 or 4, 14
				f.Color, f.SecondaryColor = C(255, 150, 50), C(255, 60, 20)
				f.Parent = p
				table.insert(flames, f)
			end
		end
		local torso = m:FindFirstChild("UpperTorso")
		if torso then
			local sm = Instance.new("Smoke")
			sm.Color, sm.Opacity, sm.RiseVelocity, sm.Size = C(40, 36, 34), 0.35, 7, 6
			sm.Parent = torso
		end
		-- the charring creeps over it, then it is dead and the fire takes it
		if Injury.char then
			Injury.char(m, 60)
			task.delay(0.5, Injury.char, m, 200)
		end
		task.delay(0.7, function()
			local hum = m.Parent and m:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				hum.Health = 0
			end
		end)
		task.delay(2.6, function()
			if m.Parent then
				Dummies.remove(m, true) -- (fades over a second)
			end
		end)
	end
	local impaled = setmetatable({}, { __mode = "k" })
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for _, S in ipairs(saws) do
			S.part.CFrame = S.part.CFrame * CFrame.Angles(S.spin * dt, 0, 0)
		end
		for _, P in ipairs(presses) do
			local f = (now % P.period) / P.period
			local k
			if f < 0.5 then
				k = 0
			elseif f < 0.58 then
				k = (f - 0.5) / 0.08
			elseif f < 0.78 then
				k = 1
			else
				k = 1 - (f - 0.78) / 0.22
			end
			P.part.CFrame = P.home * CFrame.new(0, -P.travel * k, 0)
			if k >= 1 and not P.slammed then
				P.slammed = true
				refreshParams()
				local low = P.home * CFrame.new(0, -P.travel - 0.4, 0)
				local seen = {}
				for _, part in ipairs(workspace:GetPartBoundsInBox(low, P.part.Size + Vector3.new(0, 2.5, 0), npcParams)) do
					local m = Dummies.of(part)
					if m then
						seen[m] = (seen[m] or 0) + 1
						if seen[m] <= 4 then
							hurt(m, part, "crush", P.dmg * (seen[m] == 1 and 1 or 0.6), lastBy(m), Vector3.new(0, -1, 0))
						end
						Ragdoll.Ragdoll(m, 3)
					end
				end
				sfx("heavy", low.Position, 1, 0.7)
				if next(seen) and net then
					net("boom", low.Position, 26)
				end
			elseif k < 0.5 then
				P.slammed = false
			end
		end
		acc += dt
		if acc < 0.12 then
			return
		end
		acc = 0
		refreshParams()
		for _, S in ipairs(saws) do
			local ok, parts = pcall(workspace.GetPartsInPart, workspace, S.part, npcParams)
			if ok then
				for _, part in ipairs(parts) do
					local m = Dummies.of(part)
					if m and (S.hitAt[m] or 0) < now then
						S.hitAt[m] = now + 0.32
						hurt(m, part, "slash", S.dmg, lastBy(m), S.part.CFrame.UpVector, part.Position)
						Ragdoll.Ragdoll(m, 2)
						sfx("slash", part.Position, 0.7, 1.3)
						local sp = S.part:FindFirstChild("Sparks")
						if sp then
							sp:Emit(14)
						end
					end
				end
			end
		end
		for _, Z in ipairs(zones) do
			local seen = {}
			for _, part in ipairs(workspace:GetPartBoundsInBox(Z.CFrame, Z.Size, npcParams)) do
				local m = Dummies.of(part)
				if m and not impaled[m] then
					seen[m] = seen[m] or {}
					table.insert(seen[m], part)
				end
			end
			for m, parts in pairs(seen) do
				local torso = m:FindFirstChild("UpperTorso")
				local vy = torso and torso.AssemblyLinearVelocity.Y or 0
				if vy < -4 or #parts >= 4 then
					impaled[m] = true
					table.sort(parts, function(a, b)
						return a.Position.Y < b.Position.Y
					end)
					local amt = math.clamp(math.abs(vy) * 1.5, 30, 88)
					Ragdoll.Ragdoll(m, nil)
					for i = 1, math.min(3, #parts) do
						hurt(m, parts[i], "pierce", amt * (i == 1 and 1 or 0.6), lastBy(m), Vector3.new(0, 1, 0), parts[i].Position - Vector3.new(0, 0.4, 0))
					end
					local st = Injury.get(m)
					if st then
						st.bleedA += 1.6
						st.fatal = st.fatal or "Impaled"
					end
					local floor = Z.Parent and Z.Parent:FindFirstChild("PitFloor")
					if floor and parts[1].Parent then
						local w = Instance.new("WeldConstraint")
						w.Part0, w.Part1 = floor, parts[1]
						w.Parent = parts[1]
					end
					sfx("slash", parts[1].Position, 0.9, 0.8)
				end
			end
		end
		for _, D in ipairs(drains) do
			local fire = D:GetAttribute("Mode") == "fire"
			for _, part in ipairs(workspace:GetPartBoundsInBox(D.CFrame, D.Size, npcParams)) do
				local m = Dummies.of(part)
				if m and fire then
					if not burning[m] then
						incinerate(m, part)
					end
				elseif m then
					local hum = m:FindFirstChildOfClass("Humanoid")
					local st = Injury.get(m)
					if st then
						st.fatal = "Fed to the grinder"
					end
					if hum and hum.Health > 0 then
						hum.Health = 0
					end
					Injury.spurt(part.Position, Vector3.yAxis, 24, 26)
					sfx("slash", part.Position, 0.8, 0.7)
					task.delay(0.25, Dummies.remove, m, false)
				end
			end
		end
	end)
	-- trapdoors
	for _, b in ipairs(tagged("TrapdoorButton")) do
		local pp = b:FindFirstChildOfClass("ProximityPrompt")
		local area = b.Parent
		local open = false
		if pp then
			onPrompt(pp, function(player)
				if open then
					return
				end
				open = true
				local leaves = {}
				for _, l in ipairs(tagged("Trapdoor")) do
					if l:IsDescendantOf(area) then
						local side = l:GetAttribute("Side") or 1
						local home = l.CFrame
						local half = l.Size.X / 2
						local goal = home * CFrame.new(side * half, 0, 0) * CFrame.Angles(0, 0, side * math.rad(82)) * CFrame.new(-side * half, 0, 0)
						TweenService:Create(l, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = goal }):Play()
						table.insert(leaves, { l, home })
					end
				end
				sfx("heavy", b.Position, 0.8, 1.2)
				-- whoever pulled the lever owns what falls through (the impale had no one to credit)
				if player then
					for m in pairs(Dummies.records) do
						local t = m:FindFirstChild("UpperTorso")
						if t then
							for _, L in ipairs(leaves) do
								local d = (t.Position - L[2].Position) * Vector3.new(1, 0, 1)
								if d.Magnitude < math.max(L[1].Size.X, L[1].Size.Z) then
									m:SetAttribute("LastHitBy", player.UserId)
									break
								end
							end
						end
					end
				end
				task.wait(3.2)
				for _, L in ipairs(leaves) do
					TweenService:Create(L[1], TweenInfo.new(0.7, Enum.EasingStyle.Quad), { CFrame = L[2] }):Play()
				end
				task.wait(0.8)
				open = false
			end)
		end
	end
	-- stock the gas yard
	for _, mk in ipairs(tagged("GasCanSpawn")) do
		local p = makeProp("gascan", mk.CFrame)
		props[p].marker = mk
	end
	for _, mk in ipairs(tagged("BarrelSpawn")) do
		local p = makeProp("barrel", mk.CFrame)
		props[p].marker = mk
	end
	for _, r in ipairs(tagged("Rocket")) do
		task.spawn(setupRocket, r)
	end
	for _, f in ipairs(tagged("DisasterBox")) do
		task.spawn(setupDisaster, f)
	end
end

return H
