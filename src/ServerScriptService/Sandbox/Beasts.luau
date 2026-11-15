--!nocheck
-- ServerScriptService.Sandbox.Beasts (2026-11-13): the rex, the bear and the shark (models tagged Beast, built by
-- ServerStorage.SandboxGen.Beasts; attributes Kind, Pen = CFrame of the pen floor / water surface, Roam = half extents,
-- Z = 0 for a round pen). Each is one unanchored assembly the SERVER drives with AlignPosition + AlignOrientation, so
-- clients see it interpolated; the limbs are animated on each client from the Gait / Jaw attributes
-- (StarterPlayerScripts.SandboxWorld). It hunts whatever dummy is inside its pen (players too, if nothing else is),
-- bites, shakes, and either tosses the body or swallows it. Collision group Beasts ignores the map, never the bodies.
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local B = {}
local KINDS = {
	rex = { walk = 9, run = 26, turn = 2.4, height = 12, fwd = 23, reach = 8, dmg = 85, shake = 1.3, swallow = 2, sever = 0.5, roar = "roar", pitch = 0.85, pdmg = 60, cause = "Eaten by a T-rex", toss = 60 },
	bear = { walk = 6, run = 19, turn = 3.2, height = 5.7, fwd = 11.4, reach = 5.5, dmg = 48, shake = 0.9, swallow = 4, sever = 0.35, roar = "growl", pitch = 1, pdmg = 34, cause = "Mauled by a bear", toss = 42 },
	shark = { walk = 10, run = 30, turn = 2.6, height = 0, fwd = 9.4, reach = 6.5, dmg = 70, shake = 1.1, swallow = 2, sever = 0.7, roar = "splash", pitch = 0.8, pdmg = 45, cause = "Eaten by a shark", toss = 20, swim = true },
}
local LIMBS = { "LeftLowerArm", "RightLowerArm", "LeftLowerLeg", "RightLowerLeg", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg" }

function B.init(ctx)
	local H, Injury, Dummies, Ragdoll = ctx.Hazards, ctx.Injury, ctx.Dummies, ctx.Ragdoll
	local hurt, sfx = H.hurt, H.sfx
	pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered("Beasts") then
			PhysicsService:RegisterCollisionGroup("Beasts")
		end
		PhysicsService:CollisionGroupSetCollidable("Beasts", "Default", false)
		PhysicsService:CollisionGroupSetCollidable("Beasts", "Beasts", false)
	end)
	local function lastBy(m)
		local uid = m:GetAttribute("LastHitBy")
		return uid and Players:GetPlayerByUserId(uid) or nil
	end
	-- (2026-11-13) smaller and thinner than it was (17 studs, 0.45): the first one hid the whole feeding
	local function bloodCloud(pos)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material, p.Color, p.Transparency = Enum.Material.SmoothPlastic, Color3.fromRGB(150, 16, 20), 0.62
		p.Size = Vector3.new(4, 4, 4)
		p.CFrame = CFrame.new(pos)
		p.Parent = Injury.gore()
		TweenService:Create(p, TweenInfo.new(3.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(10, 7, 10), Transparency = 1 }):Play()
		Debris:AddItem(p, 3.7)
	end

	local function run(model)
		local K = KINDS[model:GetAttribute("Kind")]
		local root = model.PrimaryPart
		local pen, roam = model:GetAttribute("Pen"), model:GetAttribute("Roam")
		if not K or not root or typeof(pen) ~= "CFrame" or typeof(roam) ~= "Vector3" then
			warn("[Beasts] " .. model:GetFullName() .. " is missing Kind / Pen / Roam")
			return
		end
		local round = roam.Z == 0
		local mouth = model:FindFirstChild("Mouth", true)
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				p.CollisionGroup = "Beasts"
			end
		end
		local att = Instance.new("Attachment")
		att.Name = "Drive"
		att.Parent = root
		local ap = Instance.new("AlignPosition")
		ap.Mode = Enum.PositionAlignmentMode.OneAttachment
		ap.Attachment0 = att
		ap.MaxForce, ap.MaxVelocity, ap.Responsiveness = 1e9, 1e4, 34
		ap.Position = root.Position
		ap.Parent = root
		local ao = Instance.new("AlignOrientation")
		ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
		ao.Attachment0 = att
		ao.MaxTorque, ao.MaxAngularVelocity, ao.Responsiveness = 1e9, 1e4, 26
		ao.CFrame = root.CFrame.Rotation
		ao.Parent = root
		root.Anchored = false
		pcall(function()
			root:SetNetworkOwner(nil)
		end)

		local lp = pen:PointToObjectSpace(root.Position)
		local x, z = lp.X, lp.Z
		local y = K.swim and lp.Y or 0
		local look = pen:VectorToObjectSpace(root.CFrame.LookVector)
		local yaw = math.atan2(-look.X, -look.Z)
		local function clampIn(px, pz)
			if round then
				local r = math.sqrt(px * px + pz * pz)
				if r > roam.X then
					px, pz = px / r * roam.X, pz / r * roam.X
				end
			else
				px, pz = math.clamp(px, -roam.X, roam.X), math.clamp(pz, -roam.Z, roam.Z)
			end
			return px, pz
		end
		local function randomSpot()
			if round then
				local a, r = math.random() * 6.28, math.sqrt(math.random()) * roam.X
				return math.sin(a) * r, math.cos(a) * r
			end
			return (math.random() * 2 - 1) * roam.X, (math.random() * 2 - 1) * roam.Z
		end
		local function inPen(p)
			local l = pen:PointToObjectSpace(p)
			if round then
				if math.sqrt(l.X * l.X + l.Z * l.Z) > roam.X + 5 then
					return false
				end
			elseif math.abs(l.X) > roam.X + 8 or math.abs(l.Z) > roam.Z + 8 then
				return false
			end
			if K.swim then
				return l.Y < 0.4 and l.Y > -(roam.Y + 4)
			end
			return l.Y > -2 and l.Y < roam.Y
		end

		local state, goalX, goalZ, idleUntil, restUntil, nextLook = "wander", x, z, 0, 0, 0
		local prey, isPlayer, held, struck, biteT, huntT = nil, false, nil, false, 0, 0
		local gait, jaw, dip, jawUntil, phase = 0, 0, 0, 0, 0
		local circle = math.random() * 6.28
		local eaten = setmetatable({}, { __mode = "k" })
		local bites = setmetatable({}, { __mode = "k" })
		local skip = setmetatable({}, { __mode = "k" })
		local function setAttr(name, v)
			if model:GetAttribute(name) ~= v then
				model:SetAttribute(name, v)
			end
		end
		local function roar()
			sfx(K.roar, root.Position, 1, K.pitch)
			jawUntil = os.clock() + 1.1
		end
		local function move(dt, gx, gz, speed)
			local dx, dz = gx - x, gz - z
			local d = math.sqrt(dx * dx + dz * dz)
			if d > 0.6 then
				local want = math.atan2(-dx, -dz)
				local diff = (want - yaw + math.pi) % (2 * math.pi) - math.pi
				yaw += math.clamp(diff, -K.turn * dt, K.turn * dt)
				local fx, fz = -math.sin(yaw), -math.cos(yaw)
				local align = math.max(0, (fx * dx + fz * dz) / d)
				local v = speed * (0.2 + 0.8 * align)
				local stepLen = math.min(v * dt, d)
				x, z = clampIn(x + fx * stepLen, z + fz * stepLen)
				gait = v / K.run
			else
				gait = 0
			end
			return d
		end
		local function preyPart()
			if not prey or not prey.Parent then
				return nil
			end
			if isPlayer then
				local hum = prey:FindFirstChildOfClass("Humanoid")
				return (hum and hum.Health > 0) and prey:FindFirstChild("HumanoidRootPart") or nil
			end
			if not Dummies.is(prey) then
				return nil
			end
			return prey:FindFirstChild("UpperTorso") or prey:FindFirstChild("LowerTorso") or prey:FindFirstChild("Head")
		end
		local function findPrey()
			local now = os.clock()
			local best, bd
			for m in pairs(Dummies.records) do
				if not m:GetAttribute("GrabbedBy") and not m:GetAttribute("Retired") and not eaten[m] and (skip[m] or 0) < now then
					local t = m:FindFirstChild("UpperTorso") or m:FindFirstChild("LowerTorso") or m:FindFirstChild("Head")
					if t and inPen(t.Position) then
						local d = (t.Position - root.Position).Magnitude
						if not bd or d < bd then
							best, bd = m, d
						end
					end
				end
			end
			if best then
				return best, false
			end
			for _, plr in ipairs(Players:GetPlayers()) do
				local char = plr.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if hrp and hum and hum.Health > 0 and (skip[char] or 0) < now and inPen(hrp.Position) then
					local d = (hrp.Position - root.Position).Magnitude
					if not bd or d < bd then
						best, bd = char, d
					end
				end
			end
			return best, best ~= nil
		end
		local function letGo()
			if held then
				for _, o in ipairs(held) do
					o:Destroy()
				end
				held = nil
			end
		end
		local function fwdWorld()
			return pen:VectorToWorldSpace(Vector3.new(-math.sin(yaw), 0, -math.cos(yaw)))
		end
		local function strike()
			local mpos = mouth and mouth.WorldPosition or root.Position
			if isPlayer then
				local hum, hrp = prey:FindFirstChildOfClass("Humanoid"), prey:FindFirstChild("HumanoidRootPart")
				if hum and hrp and (hrp.Position - mpos).Magnitude < K.reach + 9 then
					hum:TakeDamage(K.pdmg)
					pcall(Ragdoll.Fling, prey, fwdWorld() * 40 + Vector3.new(0, 40, 0), nil, 2)
					sfx("slash", hrp.Position, 0.9, 0.8)
				end
				skip[prey] = os.clock() + 2.5
				return
			end
			local best, bd
			for _, p in ipairs(prey:GetChildren()) do
				if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
					local d = (p.Position - mpos).Magnitude
					if not bd or d < bd then
						best, bd = p, d
					end
				end
			end
			if not best or bd > K.reach + 10 then
				return
			end
			local by = lastBy(prey)
			Ragdoll.Ragdoll(prey, nil)
			if Ragdoll.Hold then -- (2026-11-14) the jaws are the server's: so is what they hold
				Ragdoll.Hold(prey, 8)
			end
			if prey:GetAttribute("Strapped") then -- off the crane hook
				for _, d in ipairs(prey:GetDescendants()) do
					if d:IsA("RopeConstraint") and d.Name == "HookRope" then
						d:Destroy()
					end
				end
				prey:SetAttribute("Strapped", nil)
			end
			hurt(prey, best, "pierce", K.dmg, by, Vector3.yAxis, best.Position)
			hurt(prey, best, "crush", K.dmg * 0.5, by)
			Injury.spurt(best.Position, Vector3.yAxis, 22, 26)
			sfx("slash", best.Position, 1, 0.7)
			bites[prey] = (bites[prey] or 0) + 1
			if math.random() < K.sever then
				Injury.sever(prey, LIMBS[math.random(#LIMBS)], by, Vector3.yAxis)
			end
			local holdPart = (best.Parent == prey) and best or prey:FindFirstChild("UpperTorso")
			if holdPart and mouth then
				local a = Instance.new("Attachment")
				a.Name = "BiteGrip"
				a.Parent = holdPart
				local al = Instance.new("AlignPosition")
				al.Attachment0, al.Attachment1 = a, mouth
				al.MaxForce, al.Responsiveness, al.MaxVelocity = 8e4, 90, 300
				al.Parent = holdPart
				held = { a, al }
			end
			if K.swim then
				bloodCloud(best.Position)
			end
		end
		local function finish()
			letGo()
			if not isPlayer and prey and Dummies.is(prey) then
				if prey:GetAttribute("Dead") or (bites[prey] or 0) >= K.swallow then
					if not prey:GetAttribute("Invuln") then
						local st = Injury.get(prey)
						if st then
							st.fatal = K.cause
						end
						local hum = prey:FindFirstChildOfClass("Humanoid")
						if hum and hum.Health > 0 then
							hum.Health = 0
						end
						local mpos = mouth and mouth.WorldPosition or root.Position
						Injury.spurt(mpos, Vector3.yAxis, 30, 30)
						sfx("slash", mpos, 1, 0.6)
						if K.swim then
							bloodCloud(mpos)
						end
						eaten[prey] = true
						task.delay(0.2, Dummies.remove, prey, false)
						jawUntil = os.clock() + 0.5
					else
						skip[prey] = os.clock() + 6 -- a diamond body breaks teeth
						Ragdoll.Fling(prey, fwdWorld() * K.toss + Vector3.new(0, K.toss, 0), nil, 3)
					end
				else
					local f = fwdWorld()
					Ragdoll.Fling(prey, f * K.toss * 0.6 + f:Cross(Vector3.yAxis) * (math.random() - 0.5) * K.toss + Vector3.new(0, K.toss * 0.8, 0), nil, 3)
				end
			end
			prey = nil
			state = "rest"
			restUntil = os.clock() + 0.8 + math.random() * 0.8
		end

		while model.Parent and root.Parent do
			local dt = math.min(task.wait(), 0.1)
			local now = os.clock()
			local shake = 0
			if state == "wander" then
				dip += (0 - dip) * math.min(1, dt * 6)
				if K.swim then
					circle += dt * K.walk / (roam.X * 0.72)
					move(dt, math.sin(circle) * roam.X * 0.72, math.cos(circle) * roam.X * 0.72, K.walk)
					y += math.clamp(-3.4 - y, -6 * dt, 6 * dt)
				elseif now > idleUntil then
					if move(dt, goalX, goalZ, K.walk) <= 0.8 then
						idleUntil = now + 1 + math.random() * 3
						goalX, goalZ = randomSpot()
						if math.random() < 0.3 then
							roar()
						end
					end
				else
					gait = 0
				end
				if now > nextLook then
					nextLook = now + 0.4
					prey, isPlayer = findPrey()
					if prey then
						state, huntT = "hunt", 0
						if math.random() < 0.6 then
							roar()
						end
					end
				end
			elseif state == "hunt" then
				local tp = preyPart()
				huntT += dt
				if not tp or not inPen(tp.Position) or huntT > 14 then
					if prey and huntT > 14 then
						skip[prey] = now + 5
					end
					prey, state = nil, "wander"
				else
					local l = pen:PointToObjectSpace(tp.Position)
					local gx, gz = clampIn(l.X, l.Z)
					-- stop a mouth's length short so the bite lands on it, not behind it
					local dx, dz = gx - x, gz - z
					local d = math.sqrt(dx * dx + dz * dz)
					if d > K.fwd then
						move(dt, gx, gz, K.run)
					else
						move(dt, gx, gz, 0.01)
					end
					if K.swim then
						y += math.clamp(math.clamp(l.Y + 1, -roam.Y, -2.6) - y, -14 * dt, 14 * dt)
					end
					local fx, fz = -math.sin(yaw), -math.cos(yaw)
					local facing = d > 0.1 and (fx * dx + fz * dz) / d or 1
					if d < K.fwd + 4 and facing > 0.8 then
						state, biteT, struck = "bite", 0, false
					end
				end
			elseif state == "bite" then
				biteT += dt
				gait = 0
				local tp = preyPart()
				if not tp then
					letGo()
					prey, state = nil, "wander"
				elseif biteT < 0.34 then
					jawUntil = now + 0.1
					local level = (pen * CFrame.new(x, K.swim and y or K.height, z)).Position.Y + (mouth and (mouth.WorldPosition.Y - root.Position.Y) or 0) * 0.3
					local want = K.swim and 0 or math.asin(math.clamp((level - tp.Position.Y) / K.fwd, -0.2, 0.78))
					dip += (want - dip) * math.min(1, dt * 14)
				elseif not struck then
					struck = true
					strike()
				elseif biteT < 0.34 + K.shake then
					shake = math.sin(biteT * 24) * 0.3
					dip += (0.12 - dip) * math.min(1, dt * 5)
					if K.swim then
						y += math.clamp(-4.4 - y, -12 * dt, 12 * dt) -- (2026-11-13) just under the surface, where it can be watched (was 12 studs down)
					end
				else
					finish()
				end
			else -- rest
				gait = 0
				dip += (0 - dip) * math.min(1, dt * 6)
				if now > restUntil then
					state, nextLook = "wander", 0
				end
			end
			phase += dt * (4 + gait * 7)
			local bob = K.swim and math.sin(now * 1.3) * 0.4 or math.abs(math.sin(phase)) * 0.4 * gait
			ap.Position = (pen * CFrame.new(x, (K.swim and y or K.height) + bob, z)).Position
			ao.CFrame = (pen * CFrame.Angles(0, yaw + shake, 0) * CFrame.Angles(-dip, 0, K.swim and math.sin(now * 5) * 0.06 or 0)).Rotation
			setAttr("Gait", math.floor(gait * 5 + 0.5) / 5)
			setAttr("Jaw", (now < jawUntil) and 1 or 0)
		end
	end
	for _, model in ipairs(CollectionService:GetTagged("Beast")) do
		task.spawn(function()
			local ok, err = pcall(run, model)
			if not ok then
				warn("[Beasts] " .. tostring(err))
			end
		end)
	end
end

return B
