--!nocheck
-- ServerScriptService.Sandbox.Wounds (2026-11-14, owner: "make the injuries and blood spill and such on the npcs a lot
-- more realistic and gore-y"): what an injury looks like ON the body. Sandbox.Injury decides what happened and calls
-- one of these; every piece is a part named Wound / Stump / StumpBone welded to the limb (those names are what
-- SandboxClient hides for a player with BLOOD off, and what Injury.hit maps back to the limb when a later blow lands
-- on one).
--   Wounds.gash(st, part, pos, amount, small)  an open cut: wet rim, dark inside, fat / bone showing in a deep one
--   Wounds.hole(st, part, pos, amount, lean)   a bullet's or a blade's way in
--   Wounds.exit(st, part, pos, dir, amount) -> world position | nil   a bullet's way OUT: bigger, torn
--   Wounds.bruise / Wounds.burn(st, part, pos, amount)
--   Wounds.boneOut(st, part) -> world position, world direction     an open fracture: the broken end through the skin
--   Wounds.crushHead(st, part) -> did it                             a skull that gave way
--   Wounds.stump(onPart, jointPos, facing, dia) -> part              the cut end of a severed limb (both sides of the cut)
-- st.marks keeps each wound as a group of parts, newest last; the oldest go when a body carries more than MAX parts.
-- Deliberately NOT here: organs, brain matter. Roblox bans "realistic depictions of extreme gore" at every maturity
-- label; open wounds, blood, bone and severed limbs are what its Restricted label covers.
local TweenService = game:GetService("TweenService")
local Gore = require(script.Parent:WaitForChild("Gore"))
local K = Gore.COLORS
local fxPart, blob = Gore.fxPart, Gore.blob
local C = Color3.fromRGB
local Wounds = {}
local MAX = 64 -- wound PARTS a body may carry (a rifle burst put 118 on one before this counted parts, not wounds)

-- weld a list of { part, CFrame in the limb's space, name? } onto the limb as one wound
local function put(st, part, list)
	local group = {}
	for _, it in ipairs(list) do
		local p = it[1]
		p.Name = it[3] or "Wound"
		p.CFrame = part.CFrame * it[2]
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = part, p
		w.Parent = p
		p.Parent = part
		table.insert(group, p)
	end
	if st then
		table.insert(st.marks, group)
		st.markParts = (st.markParts or 0) + #group
		while st.markParts > MAX and #st.marks > 1 do
			local old = table.remove(st.marks, 1)
			st.markParts -= #old
			for _, p in ipairs(old) do
				p:Destroy()
			end
		end
	end
	return group
end
-- the point on the limb's surface nearest a hit, and that face's outward normal (both in the limb's space)
local function surface(part, pos)
	local lp = part.CFrame:PointToObjectSpace(pos)
	local h = part.Size / 2
	local gx, gy, gz = h.X - math.abs(lp.X), h.Y - math.abs(lp.Y), h.Z - math.abs(lp.Z)
	local axis = (gx <= gy and gx <= gz) and "X" or ((gy <= gz) and "Y" or "Z")
	if part.Name ~= "Head" and axis == "Y" and part.Size.Y > 0.6 then
		axis = (gx <= gz) and "X" or "Z" -- not on a limb's end caps
	end
	local sign = lp[axis] >= 0 and 1 or -1
	local x = axis == "X" and sign * (h.X + 0.025) or math.clamp(lp.X, -h.X * 0.8, h.X * 0.8)
	local y = axis == "Y" and sign * (h.Y + 0.025) or math.clamp(lp.Y, -h.Y * 0.85, h.Y * 0.85)
	local z = axis == "Z" and sign * (h.Z + 0.025) or math.clamp(lp.Z, -h.Z * 0.8, h.Z * 0.8)
	return Vector3.new(x, y, z), Vector3.new(axis == "X" and sign or 0, axis == "Y" and sign or 0, axis == "Z" and sign or 0)
end
-- a frame on that face: -Z out of the limb, Y along the face's LONGER side; and the face's long and short sizes
local function face(part, v, nrm)
	local s = part.Size
	local a1, d1, a2, d2
	if nrm.X ~= 0 then
		a1, d1, a2, d2 = Vector3.yAxis, s.Y, Vector3.zAxis, s.Z
	elseif nrm.Y ~= 0 then
		a1, d1, a2, d2 = Vector3.xAxis, s.X, Vector3.zAxis, s.Z
	else
		a1, d1, a2, d2 = Vector3.yAxis, s.Y, Vector3.xAxis, s.X
	end
	if d2 > d1 then
		a1, d1, d2 = a2, d2, d1
	end
	return CFrame.lookAt(v, v + nrm, a1), d1, d2
end
-- blood running down the limb from a wound: the way that was down when it was made, as far as the face goes
local function streak(part, v, nrm, a)
	local dl = part.CFrame:VectorToObjectSpace(Vector3.new(0, -1, 0))
	dl = dl - nrm * dl:Dot(nrm)
	if dl.Magnitude < 0.35 then
		return nil -- the face is level: it pools where it is
	end
	dl = dl.Unit
	local h = part.Size / 2
	local room = 9
	for _, ax in ipairs({ "X", "Y", "Z" }) do
		local d = dl[ax]
		if math.abs(d) > 0.05 then
			room = math.min(room, ((d > 0 and h[ax] or -h[ax]) - v[ax]) / d)
		end
	end
	local len = math.min(room * 0.95, 0.3 + a / 45 + math.random() * 0.3, 1.3)
	if len < 0.18 then
		return nil
	end
	local p = blob(Vector3.new(0.07 + math.random() * 0.06, len, 0.035), K.BLOOD)
	p.Transparency = 1
	TweenService:Create(p, TweenInfo.new(1.3), { Transparency = 0.06 }):Play() -- it appears as it runs
	local c = v + dl * (len / 2)
	return p, CFrame.lookAt(c, c + nrm, dl)
end
-- blood that has soaked out round a wound: two patches that do not line up, lying under the wound itself. (Tinting
-- the whole limb instead turned a white body pink - it read as paint.)
local function soak(list, base, short, d)
	d = math.min(d, short * 0.7) -- (limbs are rounder than their boxes: a patch the full width hangs off the edge)
	for i = 1, 2 do
		local b = blob(Vector3.new(d * (0.6 + math.random() * 0.4), d * (0.6 + math.random() * 0.4), 0.02), K.BLOOD)
		b.Transparency = 0.2 + math.random() * 0.15
		table.insert(list, { b, base * CFrame.new((math.random() - 0.5) * d * 0.25, (math.random() - 0.5) * d * 0.25, 0.004 * i) * CFrame.Angles(0, 0, math.random() * 3) })
	end
end

function Wounds.gash(st, part, pos, a, small)
	local v, nrm = surface(part, pos)
	local base, long, short = face(part, v, nrm)
	local th = math.random() * math.pi -- the cut's angle off the face's long side
	local len = small and (0.3 + math.random() * 0.3) or math.clamp(0.45 + a / 36, 0.55, 1.7)
	-- as long as fits on the face at that angle
	len = math.min(len, 0.92 * math.min(long / math.max(math.abs(math.cos(th)), 0.2), short / math.max(math.abs(math.sin(th)), 0.2)))
	local gape = math.clamp(0.07 + a / 400, 0.08, 0.2) * (small and 0.7 or 1)
	local cf = base * CFrame.Angles(0, 0, th)
	local list = { { blob(Vector3.new(gape * 2.4, len, 0.04), K.FRESH), cf }, { blob(Vector3.new(gape, len * 0.86, 0.065), K.PIT:Lerp(K.DARK, 0.5)), cf } }
	if not small and a >= 22 then
		soak(list, base, short, math.clamp(0.5 + a / 60, 0.6, 1.3))
	end
	if a >= 44 and not small then
		-- deep: the fat under the skin shows along the middle - bone, in a deeper one
		table.insert(list, { blob(Vector3.new(gape * 0.36, len * 0.5, 0.085), (a >= 60) and K.BONE or K.FAT), cf })
	end
	local run, rcf = streak(part, v, nrm, a)
	if run then
		table.insert(list, { run, rcf })
	end
	put(st, part, list)
end

function Wounds.hole(st, part, pos, a, lean)
	local v, nrm = surface(part, pos)
	local base, _, short = face(part, v, nrm)
	local d = 0.24 + math.random() * 0.1
	local list = { { blob(Vector3.new(d, d, 0.035), K.BLOOD), base }, { blob(Vector3.new(d * 0.5, d * 0.5, 0.06), K.PIT), base } }
	if not lean then
		soak(list, base, short, 0.42 + math.random() * 0.2)
		local run, rcf = streak(part, v, nrm, a)
		if run then
			table.insert(list, { run, rcf })
		end
	end
	put(st, part, list)
end

function Wounds.exit(st, part, pos, dir, a)
	local lp = part.CFrame:PointToObjectSpace(pos)
	local ld = part.CFrame:VectorToObjectSpace(dir)
	local h = part.Size / 2
	lp = Vector3.new(math.clamp(lp.X, -h.X, h.X), math.clamp(lp.Y, -h.Y, h.Y), math.clamp(lp.Z, -h.Z, h.Z))
	local best, axis = math.huge, nil
	for _, ax in ipairs({ "X", "Y", "Z" }) do
		local d = ld[ax]
		if math.abs(d) > 1e-3 then
			local t = ((d > 0 and h[ax] or -h[ax]) - lp[ax]) / d
			if t < best then
				best, axis = t, ax
			end
		end
	end
	if not axis or best < 0.2 then
		return nil -- a graze: it never went through
	end
	local sign = ld[axis] > 0 and 1 or -1
	local nrm = Vector3.new(axis == "X" and sign or 0, axis == "Y" and sign or 0, axis == "Z" and sign or 0)
	local v = lp + ld * best + nrm * 0.025
	local base, _, short = face(part, v, nrm)
	local d = math.min(math.clamp(0.4 + a / 90, 0.42, 0.85), short * 0.6)
	local list = {
		{ blob(Vector3.new(d, d * (0.7 + math.random() * 0.3), 0.04), K.FRESH), base * CFrame.Angles(0, 0, math.random() * 3) },
		{ blob(Vector3.new(d * 0.8, d * 0.5, 0.045), K.BLOOD), base * CFrame.Angles(0, 0, math.random() * 3) },
		{ blob(Vector3.new(d * 0.48, d * 0.48, 0.07), K.PIT), base },
	}
	for _ = 1, 3 do -- torn skin round it
		table.insert(list, { blob(Vector3.new(0.07, d * (0.35 + math.random() * 0.3), 0.05), K.DARK),
			base * CFrame.Angles(0, 0, math.random() * math.pi * 2) * CFrame.new(0, d * 0.45, 0) })
	end
	soak(list, base, short * 0.75, 0.7 + math.random() * 0.3)
	local run, rcf = streak(part, v, nrm, a + 20)
	if run then
		table.insert(list, { run, rcf })
	end
	put(st, part, list)
	return part.CFrame:PointToWorldSpace(v)
end

local BRUISE = { C(86, 44, 92), C(112, 38, 58), C(62, 56, 106) }
function Wounds.bruise(st, part, pos, a)
	local v, nrm = surface(part, pos)
	local base, _, short = face(part, v, nrm)
	local d = math.min(math.clamp(0.5 + a / 55, 0.6, 1.25), short * 0.85)
	local list = {}
	for i = 1, 3 do -- mottled: three patches that do not line up
		local b = blob(Vector3.new(d * (0.55 + math.random() * 0.45), d * (0.55 + math.random() * 0.45), 0.03), BRUISE[i])
		b.Transparency = 0.5 + math.random() * 0.18
		table.insert(list, { b, base * CFrame.new((math.random() - 0.5) * d * 0.3, (math.random() - 0.5) * d * 0.3, -0.003 * i) * CFrame.Angles(0, 0, math.random() * 3) })
	end
	put(st, part, list)
end

function Wounds.burn(st, part, pos, a)
	local v, nrm = surface(part, pos)
	local base, _, short = face(part, v, nrm)
	local d = math.min(math.clamp(0.6 + a / 50, 0.7, 1.3), short * 0.9)
	local raw = blob(Vector3.new(d * 1.15, d * 1.05, 0.03), C(150, 44, 34)) -- raw, round the edge
	raw.Transparency = 0.35
	local char = blob(Vector3.new(d * 0.8, d * 0.72, 0.045), C(28, 22, 20)) -- charred, in the middle
	char.Material = Enum.Material.Slate
	char.Transparency = 0.1
	put(st, part, { { raw, base * CFrame.Angles(0, 0, math.random() * 3) }, { char, base * CFrame.Angles(0, 0, math.random() * 3) } })
end

function Wounds.boneOut(st, part)
	local h = part.Size / 2
	local side = (math.random() < 0.5) and "X" or "Z"
	local sign = math.random() < 0.5 and 1 or -1
	local nrm = Vector3.new(side == "X" and sign or 0, 0, side == "Z" and sign or 0)
	local v = nrm * ((side == "X" and h.X or h.Z) + 0.02) + Vector3.new(0, (math.random() - 0.5) * h.Y * 0.7, 0)
	local base = CFrame.lookAt(v, v + nrm)
	local tilt = base * CFrame.Angles(math.rad(math.random(-40, 40)), math.rad(math.random(-40, 40)), 0)
	put(st, part, {
		{ blob(Vector3.new(0.5, 0.42, 0.04), K.FRESH), base },
		{ blob(Vector3.new(0.3, 0.26, 0.06), K.PIT), base },
		{ fxPart(Vector3.new(0.13, 0.13, 0.55), K.BONE), tilt * CFrame.new(0, 0, -0.12), "StumpBone" }, -- the shaft, out through the skin
		{ fxPart(Vector3.new(0.08, 0.08, 0.2), K.BONE), tilt * CFrame.new(0.02, 0.02, -0.46) * CFrame.Angles(0.2, 0.3, 0.6), "StumpBone" }, -- its splintered end
	})
	return part.CFrame:PointToWorldSpace(v), part.CFrame:VectorToWorldSpace(nrm)
end

function Wounds.crushHead(st, part)
	if part:GetAttribute("Crushed") then
		return false
	end
	part:SetAttribute("Crushed", true)
	local f = Vector3.new(1.16, 0.62, 1.12)
	part.Size = part.Size * f
	for _, c in ipairs(part:GetChildren()) do
		if c:IsA("Attachment") then
			c.Position = c.Position * f -- (the neck joint follows, as it does for the press and the lab)
		end
	end
	local h = part.Size / 2
	local list = {}
	for i = 1, 3 do -- the dent in the crown: dark and wet
		local d = 0.35 + math.random() * 0.3
		local v = Vector3.new((math.random() - 0.5) * h.X, h.Y + 0.02, (math.random() - 0.5) * h.Z)
		table.insert(list, { blob(Vector3.new(d, d * 0.8, 0.05), i == 1 and K.PIT or K.BLOOD), CFrame.lookAt(v, v + Vector3.yAxis) * CFrame.Angles(0, 0, math.random() * 3) })
	end
	put(st, part, list)
	return true
end

function Wounds.stump(onPart, jointPos, facing, dia)
	if not onPart or not onPart.Parent then
		return nil
	end
	local out = CFrame.lookAt(jointPos + facing * 0.02, jointPos + facing * 1.02) -- -Z points out of the stump
	local flat = out * CFrame.Angles(0, math.pi / 2, 0) -- a cylinder's axis is X: here X points out of the stump
	local function weld(p, cf, name)
		p.Name = name or "Stump"
		p.CFrame = cf
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = onPart, p
		w.Parent = p
		p.Parent = onPart
		return p
	end
	local function cyl(len, d, color)
		local p = fxPart(Vector3.new(len, d, d), color)
		p.Shape = Enum.PartType.Cylinder
		return p
	end
	weld(cyl(0.1, dia * 1.04, K.DARK), flat) -- the skin's cut edge
	local meat = weld(cyl(0.15, dia * 0.88, K.MUSCLE), flat)
	for i = 1, 7 do -- torn muscle: wet lumps round the bone, none of them level
		local ang, r = i / 7 * math.pi * 2 + math.random() * 0.5, dia * (0.14 + math.random() * 0.16)
		local s = dia * (0.3 + math.random() * 0.16)
		local lump = blob(Vector3.new(s, s * (0.6 + math.random() * 0.4), 0.05 + math.random() * 0.06), (i % 3 == 0) and K.FAT or ((i % 2 == 0) and K.FLESH or K.MUSCLE))
		weld(lump, out * CFrame.new(math.cos(ang) * r, math.sin(ang) * r, -0.07) * CFrame.Angles(0, 0, math.random() * 3))
	end
	local boneLen = 0.34 + math.random() * 0.12
	weld(cyl(boneLen, dia * 0.3, K.BONE), flat * CFrame.new(0.1, 0, 0), "StumpBone") -- the bone stands proud of the meat
	weld(cyl(boneLen, dia * 0.13, K.MARROW), flat * CFrame.new(0.115, 0, 0), "StumpBone")
	for _ = 1, 3 do -- strips of skin hanging off the edge
		local ang = math.random() * math.pi * 2
		local len = 0.28 + math.random() * 0.34
		local strip = blob(Vector3.new(0.09, 0.035, len), (math.random() < 0.5) and K.FLESH or K.DARK)
		weld(strip, out * CFrame.new(math.cos(ang) * dia * 0.46, math.sin(ang) * dia * 0.46, -len * 0.42)
			* CFrame.Angles(math.rad(math.random(-28, 28)), math.rad(math.random(-28, 28)), 0))
	end
	return meat
end

------------------------------------------------------------------------------------------------- POWER WOUNDS
-- (2026-11-14, owner: "make it to where the injuries are properly reflected in what the anime ability does ... hollow
-- purple usually puts like a huge hole in a persons body while the rasenshuriken puts very [small] but large amounts
-- of holes in a body") the marks Sandbox.Powers builds each fighter's moves out of:
--   Wounds.bore(st, part, pos, dir, radius, lining, done)        a REAL hole right through the limb (GeometryService)
--   Wounds.scoop(st, part, pos, radius, depth, lining, done)     a bowl bitten or ground out of it; a dent, with a bruise lining
--   Wounds.pepper(st, part, n, o)      n pinholes scattered over it
--   Wounds.cut(st, part, pos, along, a, o) / Wounds.rake(...)    a straight cut right across it / claw marks
--   Wounds.fern(st, part, pos, scale)  the branching figure lightning leaves on skin
--   Wounds.band(st, part, y, color)    a mark right round it (something that gripped)
--   Wounds.fist(st, part, pos, d, o)   one round imprint          Wounds.scald(st, part, pos, a)  raw and blistered
--   Wounds.faceBleed(st, head, o)      blood from the eyes / nose / ears
-- A carved limb keeps its part (joints, hits and tint all still go to it) but is hidden behind a shell named Carved.
local GeometryService = game:GetService("GeometryService")
local EXTRA_MAX = 190 -- signature marks a body may carry on top of its ordinary wounds (a peppered body is ~100)
Wounds.surface, Wounds.face = surface, face

-- like put(), for marks that ARE the move's signature: they do not age out with the ordinary wounds
local function keep(st, part, list)
	if #list == 0 then
		return nil
	end
	if st and (st.extraParts or 0) + #list > EXTRA_MAX then
		for _, it in ipairs(list) do
			it[1]:Destroy()
		end
		return nil
	end
	local group = {}
	for _, it in ipairs(list) do
		local p = it[1]
		p.Name = it[3] or "Wound"
		p.CFrame = part.CFrame * it[2]
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = part, p
		w.Parent = p
		p.Parent = part
		table.insert(group, p)
	end
	if st then
		st.extraParts = (st.extraParts or 0) + #group
	end
	return group
end
-- the limb's real skin under a point of its box: position and outward normal in the limb's space (the body meshes are
-- rounder than their boxes, so small marks placed on the box hang in the air)
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
local function skin(part, v, nrm)
	rayParams.FilterDescendantsInstances = { part }
	local o = part.CFrame:PointToWorldSpace(v + nrm * 0.45)
	local hit = workspace:Raycast(o, part.CFrame:VectorToWorldSpace(-nrm) * 1.3, rayParams)
	if hit and hit.Instance == part then
		local ln = part.CFrame:VectorToObjectSpace(hit.Normal)
		return part.CFrame:PointToObjectSpace(hit.Position) + ln * 0.014, ln
	end
	return nil
end
Wounds.skin = skin

----------------------------------------------------------------------------------------------------- carving
local carveBusy, carveQueue = 0, {}
local carveCache, cacheN = {}, 0
local BENCH = CFrame.new(0, 6000, 0) -- where the cutting is done (nothing there is ever parented to the world)
local function q(x)
	return math.floor(x * 10 + 0.5) / 10
end
local function doCarve(job)
	local part = job.part
	if not part.Parent then
		return false
	end
	local old = part:FindFirstChild("Carved")
	local src = old or part
	local key
	if not old and part:IsA("MeshPart") then
		local p, s = job.lcf, job.size
		local rx, ry, rz = p:ToOrientation()
		key = table.concat({ part.MeshId, q(part.Size.X), q(part.Size.Y), q(part.Size.Z), job.shape, q(p.X), q(p.Y), q(p.Z), q(rx), q(ry), q(rz), q(s.X), q(s.Y), q(s.Z),
			job.lining:ToHex(), part.Color:ToHex() }, "|")
	end
	local shell = key and carveCache[key] and carveCache[key]:Clone() or nil
	if not shell then
		local work = src:Clone()
		work:ClearAllChildren()
		work.Anchored, work.Transparency, work.CFrame = true, 0, BENCH
		local cut = Instance.new("Part")
		cut.Anchored, cut.Material, cut.Color = true, Enum.Material.SmoothPlastic, job.lining
		cut.TopSurface, cut.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		if job.shape == "cyl" then -- size = (diameter, -, length); the hole runs along the frame's Z
			cut.Shape = Enum.PartType.Cylinder
			cut.Size = Vector3.new(job.size.Z, job.size.X, job.size.X)
			cut.CFrame = BENCH * job.lcf * CFrame.Angles(0, math.pi / 2, 0)
		elseif job.shape == "ball" then
			cut.Shape = Enum.PartType.Ball
			cut.Size = Vector3.new(job.size.X, job.size.X, job.size.X)
			cut.CFrame = BENCH * job.lcf
		else
			cut.Size = job.size
			cut.CFrame = BENCH * job.lcf
		end
		local ok, res = pcall(function()
			return GeometryService:SubtractAsync(work, { cut }, { CollisionFidelity = Enum.CollisionFidelity.Box, RenderFidelity = Enum.RenderFidelity.Precise, SplitApart = false })
		end)
		work:Destroy()
		cut:Destroy()
		if not ok or type(res) ~= "table" or not res[1] then
			if not ok then
				warn("[Wounds] carve failed: " .. tostring(res))
			end
			return false
		end
		shell = res[1]
		for i = 2, #res do
			res[i]:Destroy()
		end
		if key then
			if cacheN >= 48 then
				table.clear(carveCache)
				cacheN = 0
			end
			carveCache[key] = shell:Clone()
			cacheN += 1
		end
	end
	if not part.Parent then
		shell:Destroy()
		return false
	end
	shell.Name = "Carved"
	shell.Anchored, shell.CanCollide, shell.CanQuery, shell.CanTouch, shell.Massless = false, false, false, false, true
	shell.CFrame = part.CFrame
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = part, shell
	w.Parent = shell
	-- the limb's later tints (burns, bruising) carry over: the shell's colours are baked, so it is tinted by ratio
	local base = part.Color
	local conn = part:GetPropertyChangedSignal("Color"):Connect(function()
		local c = part.Color
		shell.Color = Color3.new(math.min(1, c.R / math.max(base.R, 0.05)), math.min(1, c.G / math.max(base.G, 0.05)), math.min(1, c.B / math.max(base.B, 0.05)))
	end)
	shell.Destroying:Connect(function()
		conn:Disconnect()
	end)
	shell.Parent = part
	if old then
		old:Destroy()
	end
	part.Transparency = 1
	local gz = part:FindFirstChild("Glaze") -- (a glazed limb: the glaze is remade over the new shape)
	if gz then
		local c, t, mat = gz.Color, gz.Transparency, gz.Material
		gz:Destroy()
		Wounds.glaze(nil, part, c, t, mat)
	end
	return true, shell
end
local function pumpCarves()
	while carveBusy < 2 and #carveQueue > 0 do
		local job = table.remove(carveQueue, 1)
		carveBusy += 1
		task.spawn(function()
			local ok, did, shell = pcall(doCarve, job)
			carveBusy -= 1
			if not ok then
				warn("[Wounds] carve: " .. tostring(did))
			end
			if job.done then
				pcall(job.done, ok and did == true, shell)
			end
			pumpCarves()
		end)
	end
end
-- cut `shape` ("cyl" | "ball" | "block") out of a limb. lcf = the cutter's frame in the limb's space, lining = the
-- colour of the cut faces. Queued (the cut takes ~0.1-0.3 s); done(ok, shell) is called either way.
function Wounds.carve(st, part, shape, lcf, size, lining, done)
	if not part or not part.Parent or not (part:IsA("MeshPart") or part:IsA("Part")) or part.Name == "Head" then
		if done then
			pcall(done, false)
		end
		return false
	end
	local n = part:GetAttribute("Carves") or 0
	if n >= 4 or #carveQueue > 30 then
		if done then
			pcall(done, false)
		end
		return false
	end
	part:SetAttribute("Carves", n + 1)
	table.insert(carveQueue, { st = st, part = part, shape = shape, lcf = lcf, size = size, lining = lining or K.MUSCLE, done = done })
	pumpCarves()
	return true
end
-- a hole right through: along `dir` (world), through the world point `pos`
function Wounds.bore(st, part, pos, dir, radius, lining, done)
	local lp = part.CFrame:PointToObjectSpace(pos)
	local ld = part.CFrame:VectorToObjectSpace(dir)
	if ld.Magnitude < 0.1 then
		ld = Vector3.zAxis
	end
	-- snapped, so that bodies hit the same way share one cut
	local yaw, pitch = math.atan2(ld.X, ld.Z), math.asin(math.clamp(ld.Unit.Y, -1, 1))
	local step = math.rad(15)
	yaw, pitch = math.floor(yaw / step + 0.5) * step, math.floor(pitch / step + 0.5) * step
	ld = Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch))
	lp = Vector3.new(q(lp.X), q(lp.Y), q(lp.Z))
	return Wounds.carve(st, part, "cyl", CFrame.lookAt(lp, lp + ld), Vector3.new(radius * 2, 0, 6), lining, done)
end
-- a bowl out of the side nearest `pos`: `depth` studs into the skin
function Wounds.scoop(st, part, pos, radius, depth, lining, done)
	local v, nrm = surface(part, pos)
	local sp, sn = skin(part, v, nrm)
	if not sp then
		sp, sn = v, nrm
	end
	local c = sp + sn * (radius - depth - 0.07) -- (the mesh sits a little inside the box the ray found)
	c = Vector3.new(q(c.X), q(c.Y), q(c.Z))
	return Wounds.carve(st, part, "ball", CFrame.new(c), Vector3.new(radius * 2, 0, 0), lining, done)
end

------------------------------------------------------------------------------------------------------- marks
function Wounds.pepper(st, part, n, o)
	o = o or {}
	local h = part.Size / 2
	local list = {}
	local head = part.Name == "Head"
	for _ = 1, n do
		local ax = (math.random() < h.X / (h.X + h.Z)) and "Z" or "X"
		local sign = math.random() < 0.5 and 1 or -1
		local nrm = Vector3.new(ax == "X" and sign or 0, 0, ax == "Z" and sign or 0)
		local v = Vector3.new(ax == "X" and sign * h.X or (math.random() * 2 - 1) * h.X * 0.7, (math.random() * 2 - 1) * h.Y * (head and 0.66 or 0.88),
			ax == "Z" and sign * h.Z or (math.random() * 2 - 1) * h.Z * 0.7)
		local sp, sn = skin(part, v, nrm)
		if sp then
			local d = (o.size or 0.09) * (0.65 + math.random() * 0.75)
			local dot = fxPart(Vector3.new(0.024, d, d), (math.random() < 0.35) and K.PIT or K.DARK)
			dot.Shape = Enum.PartType.Cylinder
			table.insert(list, { dot, CFrame.lookAt(sp, sp + sn) * CFrame.Angles(0, math.pi / 2, 0) })
		end
	end
	return keep(st, part, list)
end

-- the face's own frame at v, and where the face's middle is in it (x across the short side, y along the long one)
local function plane(part, pos)
	local v, nrm = surface(part, pos)
	local base, long, short = face(part, v, nrm)
	local c = base:PointToObjectSpace(Vector3.zero)
	return base, long, short, c.X, c.Y, v, nrm
end
-- one cut's pieces, added to list: a straight line at angle th through (ox, oy) of the face frame
local function cutInto(list, base, long, short, cx, cy, ox, oy, th, a, o)
	local ux, uy = -math.sin(th), math.cos(th)
	local t0, t1 = -9, 9
	local function slab(p0, u, c, half)
		if math.abs(u) < 1e-3 then
			return
		end
		local a0, a1 = (c - half - p0) / u, (c + half - p0) / u
		if a0 > a1 then
			a0, a1 = a1, a0
		end
		t0, t1 = math.max(t0, a0), math.min(t1, a1)
	end
	slab(ox, ux, cx, short / 2 * 0.84) -- (the body is rounder than its box: a cut drawn to the box's edge hangs off it)
	slab(oy, uy, cy, long / 2 * 0.88)
	if t1 - t0 < 0.15 then
		return false
	end
	if o.len and t1 - t0 > o.len then
		local mid = math.clamp(0, t0 + o.len / 2, t1 - o.len / 2)
		t0, t1 = mid - o.len / 2, mid + o.len / 2
	end
	local len, tm = t1 - t0, (t0 + t1) / 2
	-- a blade's cut is narrow however deep it went (a torn gash - Wounds.gash - is the wide one)
	local gape = o.thin and 0.04 or math.clamp(0.05 + a / 800, 0.055, 0.12)
	local cf = base * CFrame.new(ox + ux * tm, oy + uy * tm, 0) * CFrame.Angles(0, 0, th)
	if o.hair then -- a scratch: one line
		table.insert(list, { blob(Vector3.new(0.045, len, 0.03), K.FRESH), cf })
		return true
	end
	if o.edge then -- an energy blade: its lips are burnt
		local e = blob(Vector3.new(gape * 3.4, len * 1.03, 0.026), o.edge)
		e.Transparency = 0.12
		table.insert(list, { e, cf })
	end
	table.insert(list, { blob(Vector3.new(gape * 2.1, len, 0.04), K.FRESH), cf })
	table.insert(list, { blob(Vector3.new(gape * 0.9, len * 0.93, 0.062), K.PIT:Lerp(K.DARK, 0.5)), cf })
	if a >= 44 and not o.thin then
		table.insert(list, { blob(Vector3.new(gape * 0.3, len * 0.5, 0.08), (a >= 60) and K.BONE or K.FAT), cf })
	end
	return true
end
-- the blood that has soaked out along a cut: a thin patch lying the way the cut does (a round one read as a sticker)
local function seep(list, base, th, len, a)
	local b = blob(Vector3.new(math.clamp(0.16 + a / 260, 0.2, 0.42), (list.len or len) * 0.95, 0.018), K.BLOOD)
	b.Transparency = 0.3
	table.insert(list, 1, { b, base * CFrame.new(0, 0, 0.004) * CFrame.Angles(0, 0, th) })
end
local function angleOf(part, base, along)
	local la = base:VectorToObjectSpace(part.CFrame:VectorToObjectSpace(along))
	if math.abs(la.X) + math.abs(la.Y) < 0.08 then
		return math.random() * math.pi
	end
	return math.atan2(-la.X, la.Y)
end
-- one straight cut across the limb, lying along the world direction `along` (the way the blade went).
-- o.len = studs (default: right across), o.thin, o.edge = a colour burnt along its lips, o.keep = never ages out
function Wounds.cut(st, part, pos, along, a, o)
	o = o or {}
	local base, long, short, cx, cy, v, nrm = plane(part, pos)
	local list = {}
	local th = angleOf(part, base, along)
	if not cutInto(list, base, long, short, cx, cy, 0, 0, th, a, o) then
		return
	end
	list.len = 0
	for _, it in ipairs(list) do
		list.len = math.max(list.len, it[1].Size.Y)
	end
	if a >= 22 and not o.thin and not o.hair then
		seep(list, base, th, math.min(short, 1.4), a)
	end
	if not o.hair then
		local run, rcf = streak(part, v, nrm, a)
		if run then
			table.insert(list, { run, rcf })
		end
	end
	if o.keep then
		keep(st, part, list)
	else
		put(st, part, list)
	end
end
-- claw marks: n cuts side by side
function Wounds.rake(st, part, pos, along, n, a, o)
	o = o or {}
	local base, long, short, cx, cy, v, nrm = plane(part, pos)
	local th = angleOf(part, base, along)
	local px, py = math.cos(th), math.sin(th) -- across the cuts
	local gap = o.gap or 0.2
	local list = {}
	for i = 1, n do
		local off = (i - (n + 1) / 2) * gap
		cutInto(list, base, long, short, cx, cy, px * off, py * off, th + (math.random() - 0.5) * 0.08, a, { len = (o.len or 1.3) * (0.8 + math.random() * 0.3), thin = o.thin })
	end
	if not o.dry then
		local b = blob(Vector3.new(gap * (n + 0.6), (o.len or 1.3) * 0.9, 0.018), K.BLOOD)
		b.Transparency = 0.36
		table.insert(list, 1, { b, base * CFrame.new(0, 0, 0.004) * CFrame.Angles(0, 0, th) })
	end
	local run, rcf = streak(part, v, nrm, a)
	if run then
		table.insert(list, { run, rcf })
	end
	put(st, part, list)
end

local FERN = C(128, 30, 46)
function Wounds.fern(st, part, pos, scale, color)
	scale = scale or 1
	local base, long, short, cx, cy = plane(part, pos)
	local list = {}
	local function grow(x, y, ang, len, w, depth)
		if #list >= 14 or depth > 4 or len < 0.07 then
			return
		end
		local nx, ny = x + math.sin(ang) * len, y + math.cos(ang) * len
		if math.abs(nx - cx) > short / 2 * 0.92 or math.abs(ny - cy) > long / 2 * 0.94 then
			return
		end
		local seg = blob(Vector3.new(w, len * 1.12, 0.022), color or FERN)
		seg.Transparency = 0.12
		table.insert(list, { seg, base * CFrame.new((x + nx) / 2, (y + ny) / 2, 0) * CFrame.Angles(0, 0, -ang) })
		grow(nx, ny, ang + (math.random() - 0.5) * 0.9, len * (0.72 + math.random() * 0.2), w * 0.82, depth + 1)
		if math.random() < 0.6 then
			grow(nx, ny, ang + (math.random() < 0.5 and -1 or 1) * (0.6 + math.random() * 0.5), len * 0.62, w * 0.7, depth + 1)
		end
	end
	local arms = 3 + math.random(0, 1)
	local a0 = math.random() * math.pi * 2
	for i = 1, arms do
		grow(0, 0, a0 + i / arms * math.pi * 2 + (math.random() - 0.5) * 0.6, (0.2 + math.random() * 0.1) * scale, 0.05 * math.sqrt(scale), 1)
	end
	return keep(st, part, list)
end

function Wounds.band(st, part, y, color, wide)
	local h = part.Size / 2
	y = math.clamp(y or 0, -h.Y * 0.8, h.Y * 0.8)
	wide = wide or 0.17
	color = color or BRUISE[1]
	local list = {}
	for _, s in ipairs({ 1, -1 }) do
		local sp = skin(part, Vector3.new(0, y, s * h.Z), Vector3.new(0, 0, s))
		local z = sp and sp.Z or s * (h.Z + 0.015)
		local a = fxPart(Vector3.new(h.X * 1.72, wide, 0.02), color)
		a.Transparency = 0.3
		table.insert(list, { a, CFrame.new(0, y, z) })
		local sq = skin(part, Vector3.new(s * h.X, y, 0), Vector3.new(s, 0, 0))
		local x = sq and sq.X or s * (h.X + 0.015)
		local b = fxPart(Vector3.new(0.02, wide, h.Z * 1.72), color)
		b.Transparency = 0.3
		table.insert(list, { b, CFrame.new(x, y, 0) })
	end
	return keep(st, part, list)
end

-- o.welt: a pale middle inside a dark ring (compressed air); o.dark: deeper
function Wounds.fist(st, part, pos, d, o)
	o = o or {}
	local v, nrm = surface(part, pos)
	local base, _, short = face(part, v, nrm)
	d = math.min(d or 0.6, short * 0.92)
	local ring = blob(Vector3.new(d, d * 0.92, 0.03), o.dark and C(70, 30, 78) or BRUISE[1])
	ring.Transparency = o.dark and 0.3 or 0.42
	local mid = blob(Vector3.new(d * 0.6, d * 0.55, 0.036), o.welt and C(214, 168, 164) or BRUISE[2])
	mid.Transparency = o.welt and 0.2 or 0.38
	put(st, part, { { ring, base * CFrame.Angles(0, 0, math.random() * 3) },
		{ mid, base * CFrame.new((math.random() - 0.5) * d * 0.14, (math.random() - 0.5) * d * 0.14, -0.003) * CFrame.Angles(0, 0, math.random() * 3) } })
end

function Wounds.scald(st, part, pos, a)
	local v, nrm = surface(part, pos)
	local base, _, short = face(part, v, nrm)
	local d = math.min(math.clamp(0.6 + a / 40, 0.7, 1.5), short * 0.92)
	local raw = blob(Vector3.new(d * 1.1, d, 0.03), C(184, 58, 52))
	raw.Transparency = 0.36
	local list = { { raw, base * CFrame.Angles(0, 0, math.random() * 3) } }
	for _ = 1, 3 do
		local s = 0.1 + math.random() * 0.1
		local bl = blob(Vector3.new(s, s, 0.05), C(236, 200, 176))
		bl.Transparency = 0.15
		table.insert(list, { bl, base * CFrame.new((math.random() - 0.5) * d * 0.6, (math.random() - 0.5) * d * 0.6, -0.004) })
	end
	put(st, part, list)
end

-- a skin of colour over ONE limb (charred feet, scalded arms). Needed because a LIVING humanoid is drawn with one colour
-- per limb group - head, torso, each arm, each leg, taken from the upper part - so Part.Color on a foot, a forearm or
-- the lower torso shows only once the body is dead (measured 2026-11-14). A child MeshPart is drawn as itself.
function Wounds.glaze(st, part, color, transparency, material)
	if not part or not part.Parent or not part:IsA("MeshPart") or part.Name == "Head" or part:FindFirstChild("Glaze") then
		return nil
	end
	local src = part:FindFirstChild("Carved") or part
	local g = src:Clone()
	g:ClearAllChildren()
	g.Name = "Glaze"
	g.Size = src.Size * 1.04
	g.Color, g.Transparency, g.Material = color, transparency or 0, material or Enum.Material.SmoothPlastic
	g.Anchored, g.CanCollide, g.CanQuery, g.CanTouch, g.Massless, g.CastShadow = false, false, false, false, true, false
	g.CFrame = part.CFrame
	local wl = Instance.new("WeldConstraint")
	wl.Part0, wl.Part1 = part, g
	wl.Parent = g
	g.Parent = part
	if st then
		st.extraParts = (st.extraParts or 0) + 1
	end
	return g
end

-- o = { eyes, nose, ears }: thin runs of blood down the face (pressure, a roar, a mind overloaded)
function Wounds.faceBleed(st, head, o)
	if not head or head:GetAttribute("FaceBleed") then
		return
	end
	head:SetAttribute("FaceBleed", true)
	local h = head.Size / 2
	local list = {}
	local function run(v, nrm, len)
		local sp, sn = skin(head, v, nrm)
		if not sp then
			return
		end
		local p = blob(Vector3.new(0.05, len, 0.028), K.BLOOD)
		local c = sp - Vector3.yAxis * (len / 2)
		table.insert(list, { p, CFrame.lookAt(c, c + sn, Vector3.yAxis) })
	end
	local front = Vector3.new(0, 0, -1)
	if o.eyes then
		run(Vector3.new(-0.2, 0.1, -h.Z), front, 0.3 + math.random() * 0.12)
		run(Vector3.new(0.2, 0.1, -h.Z), front, 0.3 + math.random() * 0.12)
	end
	if o.nose then
		run(Vector3.new(0.03, -0.08, -h.Z), front, 0.2 + math.random() * 0.1)
	end
	if o.ears then
		run(Vector3.new(-h.X, 0.02, 0), Vector3.new(-1, 0, 0), 0.26)
		run(Vector3.new(h.X, 0.02, 0), Vector3.new(1, 0, 0), 0.26)
	end
	return keep(st, head, list)
end

return Wounds
