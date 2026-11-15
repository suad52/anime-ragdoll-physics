--!nocheck
local PvPBal = require(game:GetService("ServerScriptService"):WaitForChild("PvP")) -- (2026-11-07) player damage/knockback balance
-- CombatService: server-authoritative Hollow Purple + M1 punch combo.
-- Owns hit detection, ragdoll physics calls, terrain carving (with pristine restore), debris and breakables.
-- COMBAT REWORK (2026-11-11): the punch aims PvP at the puncher (PvP.setAim) and flags the finisher (PvP.m1Begin(final))
-- so a BLOCK (ServerScriptService.PvP) soaks hits 1-4 and the finisher breaks the guard; a blocked hit sends no
-- PunchHit and stuns nobody; an M1 request drops the puncher's own guard; and a LOCK-ON ASSIST lands a swing whose box
-- caught nobody on the nearest standing body in a short corridor ahead (resolvePunch).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("GojoShared")
local ConfigFolder = Shared:WaitForChild("Config")
local HP = require(ConfigFolder:WaitForChild("HollowPurple"))
local PUNCH = require(ConfigFolder:WaitForChild("Punch"))
local NPCCFG = require(ConfigFolder:WaitForChild("NPC"))
local Remotes = Shared:WaitForChild("Remotes")
local AbilityRequest = Remotes:WaitForChild("AbilityRequest")
local AbilityCast = Remotes:WaitForChild("AbilityCast")
local AbilityEvent = Remotes:WaitForChild("AbilityEvent")
local AbilityResult = Remotes:WaitForChild("AbilityResult")
local GojoServer = ServerScriptService:WaitForChild("GojoServer")
local Threat = GojoServer:WaitForChild("Threat")
local WorldBlast = GojoServer:WaitForChild("WorldBlast", 10)
local BLUE = require(ConfigFolder:WaitForChild("Blue"))
local RED = require(ConfigFolder:WaitForChild("Red"))
local DOMAIN = require(ConfigFolder:WaitForChild("Domain"))
local GrabMove = Remotes:WaitForChild("GrabMove")

local RagdollService
do
	local mod = GojoServer:WaitForChild("RagdollService", 10)
	local ok, res = pcall(require, mod)
	if ok and res then
		RagdollService = res
		RagdollService.Init()
	else
		warn("[Combat] RagdollService unavailable: " .. tostring(res))
	end
end

local Terrain = workspace.Terrain
local NPC_TAG = NPCCFG.Tag
local PvP = require(game:GetService("ServerScriptService"):WaitForChild("PvP")) -- (2026-11-07) Purple, Red and the punch hit other players too (lifts stay NPC-only; the Domain and Blue catch players since 2026-11-10 - HOLD, in the Blue section)
local FX = workspace:FindFirstChild("FX")
if not FX then
	FX = Instance.new("Folder")
	FX.Name = "FX"
	FX.Parent = workspace
end

local function now()
	return workspace:GetServerTimeNow()
end

-- PERKS (2026-11-07): every Limitless cooldown is base * CooldownMul (Faster Cooldowns), and the ultimate's (the
-- Domain) also * UltChargeMul (Faster Ult Charge). Both player attributes are written by ShopService only.
-- (2026-11-08) non-ultimate moves x PvPShared.Balance.NON_ULT_COOLDOWN_MUL ("double the cooldown on non ult abilities")
local BAL = require(game:GetService("ReplicatedStorage"):WaitForChild("PvPShared"):WaitForChild("Balance"))
local function cdScale(player, isUlt)
	local m = tonumber(player:GetAttribute("CooldownMul")) or 1
	if isUlt then
		m *= tonumber(player:GetAttribute("UltChargeMul")) or 1
	end
	if m ~= m or m <= 0 then
		m = 1
	end
	return math.clamp(m, 0.05, 4) * (isUlt and 1 or BAL.NON_ULT_COOLDOWN_MUL)
end

-- (2026-11-10) per-kit damage (PvPShared.Balance.KIT_DAMAGE_MUL): a buff scales the hit before the PvP caps, a nerf what
-- is left after them. Gojo's own moves pass kit "Limitless"; the shared punch string passes the puncher's kit.
local function kitHit(kit, hum, amount)
	local m = type(BAL.KIT_DAMAGE_MUL) == "table" and tonumber(BAL.KIT_DAMAGE_MUL[kit or "Limitless"]) or 1
	if m < 1 then
		return PvPBal.dmg(hum, amount) * m
	end
	return PvPBal.dmg(hum, amount * m)
end

local function randomUnit()
	local v = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	return v.Magnitude > 1e-3 and v.Unit or Vector3.xAxis
end

local function segDist(p, a, b)
	local ab = b - a
	local len2 = ab:Dot(ab)
	local t = 0
	if len2 > 1e-6 then
		t = math.clamp((p - a):Dot(ab) / len2, 0, 1)
	end
	return (p - (a + ab * t)).Magnitude
end

local function finite(v)
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

-- returns (aimDir, flatDir) with the pitch clamped, or nil
local function clampAim(v)
	if typeof(v) ~= "Vector3" or not finite(v) or v.Magnitude < 1e-3 then
		return nil
	end
	v = v.Unit
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude < 1e-3 then
		return nil
	end
	flat = flat.Unit
	local pitch = math.clamp(math.deg(math.asin(math.clamp(v.Y, -1, 1))), HP.MinPitch, HP.MaxPitch)
	local r = math.rad(pitch)
	return (flat * math.cos(r) + Vector3.yAxis * math.sin(r)).Unit, flat
end

local function liveChar(p)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hum and hrp and hum.Health > 0 then
		return char, hum, hrp
	end
	return nil
end

local function bodyPoints(model, a, b)
	-- (2026-11-08) a player in a giant form: the point of its whole body nearest the attack line a-b (PvP.formPoint)
	local fc = PvP.formCenter(model)
	if fc then
		local from = a or fc
		if a and b then
			local ab = b - a
			local len2 = ab:Dot(ab)
			from = len2 > 1e-6 and (a + ab * math.clamp((fc - a):Dot(ab) / len2, 0, 1)) or a
		end
		return { PvP.formPoint(model, from) }
	end
	local pts = {}
	for _, n in ipairs({ "UpperTorso", "LowerTorso", "Head" }) do
		local p = model:FindFirstChild(n)
		if p then
			table.insert(pts, p.Position)
		end
	end
	return pts
end

---------------------------------------------------------------------------------------------------
-- player state
local pstate = {}
local function getState(p)
	local s = pstate[p]
	if not s then
		s = { casting = false, castId = 0, cd = {}, combo = 0, lastSwing = -math.huge, punchLock = 0, reqs = {} }
		pstate[p] = s
	end
	return s
end
Players.PlayerRemoving:Connect(function(p)
	pstate[p] = nil
end)

local function rateOk(s)
	local t = os.clock()
	local r = s.reqs
	while #r > 0 and t - r[1] > 1 do
		table.remove(r, 1)
	end
	if #r >= 15 then
		return false
	end
	table.insert(r, t)
	return true
end

---------------------------------------------------------------------------------------------------
-- terrain: carve with FillBall; a pristine voxel cache per 32-stud chunk lets us restore exactly
local CHUNK = 32
local FLOOR_Y = -44 -- fallback only: with CityShared.GroundGuard (2026-11-07) a carve never goes deeper than
-- DestructionConfig.GROUND.MAX_DEPTH below the street (Hollow Purple's trench and Red's crater are shallow dishes)
local GroundGuard
do
	local ok, res = pcall(function()
		return require(ReplicatedStorage:WaitForChild("CityShared", 10):WaitForChild("GroundGuard", 10))
	end)
	GroundGuard = ok and res or nil
end
local terrainCache = {} -- key -> { region, mats, occs, refs }
local restoreQueue = {}

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { Terrain }
terrainOnly.IgnoreWater = true

local function ensureChunk(cx, cy, cz, dirty)
	local key = cx .. "," .. cy .. "," .. cz
	local c = terrainCache[key]
	if not c then
		local min = Vector3.new(cx * CHUNK, cy * CHUNK, cz * CHUNK)
		local region = Region3.new(min, min + Vector3.new(CHUNK, CHUNK, CHUNK))
		local ok, mats, occs = pcall(function()
			return Terrain:ReadVoxels(region, 4)
		end)
		if not ok then
			return
		end
		c = { region = region, mats = mats, occs = occs, refs = 0 }
		terrainCache[key] = c
	end
	c.touched = os.clock() -- (2026-11-07) a chunk held far too long is force-healed by the restore loop
	if not dirty[key] then
		dirty[key] = true
		c.refs += 1
	end
end

local function carve(center, r, dirty)
	if GroundGuard then
		center, r = GroundGuard.clampBall(center, r)
		if not center then
			return false
		end
	elseif center.Y - r < FLOOR_Y then
		r = center.Y - FLOOR_Y -- never open a hole through the bottom of the map
	end
	if r < 2 then
		return false
	end
	local lo, hi = center - Vector3.one * r, center + Vector3.one * r
	for cx = math.floor(lo.X / CHUNK), math.floor(hi.X / CHUNK) do
		for cy = math.floor(lo.Y / CHUNK), math.floor(hi.Y / CHUNK) do
			for cz = math.floor(lo.Z / CHUNK), math.floor(hi.Z / CHUNK) do
				ensureChunk(cx, cy, cz, dirty)
			end
		end
	end
	Terrain:FillBall(center, r, Enum.Material.Air)
	return true
end

local liftParams = RaycastParams.new()
liftParams.FilterType = Enum.RaycastFilterType.Include
liftParams.FilterDescendantsInstances = { Terrain }

-- after a chunk is refilled, push any NPC / corpse that ended up inside the ground back on top
local function liftOutOf(region)
	local cpos, half = region.CFrame.Position, region.Size / 2
	for _, model in ipairs(CollectionService:GetTagged(NPC_TAG)) do
		local torso = model:FindFirstChild("LowerTorso") or model:FindFirstChild("HumanoidRootPart")
		if torso then
			local d = torso.Position - cpos
			if math.abs(d.X) <= half.X + 2 and math.abs(d.Z) <= half.Z + 2 and math.abs(d.Y) <= half.Y + 6 then
				local top = workspace:Raycast(Vector3.new(torso.Position.X, cpos.Y + half.Y + 150, torso.Position.Z), Vector3.new(0, -400, 0), liftParams)
				if top and torso.Position.Y < top.Position.Y + 0.5 then
					model:PivotTo(model:GetPivot() + Vector3.new(0, top.Position.Y + 3 - torso.Position.Y, 0))
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- debris rocks
local DEBRIS_CAP = 150
local debrisList = {}
local DEBRIS_MAT = {
	[Enum.Material.Grass] = Enum.Material.Ground,
	[Enum.Material.LeafyGrass] = Enum.Material.Ground,
	[Enum.Material.Water] = Enum.Material.Slate,
	[Enum.Material.Air] = Enum.Material.Ground,
}

local function removeDebris(p)
	local i = table.find(debrisList, p)
	if i then
		table.remove(debrisList, i)
	end
end

local function spawnRock(pos, vel, mat, color, size)
	if #debrisList >= DEBRIS_CAP then
		local old = table.remove(debrisList, 1)
		if old and old.Parent then
			old:Destroy()
		end
	end
	local p = Instance.new("Part")
	p.Name = "Rock"
	p.Size = size
	p.Material = mat
	p.Color = color
	p.CFrame = CFrame.new(pos) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
	p.CollisionGroup = "Debris"
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = FX
	pcall(function()
		p:SetNetworkOwner(nil)
	end)
	p.AssemblyLinearVelocity = vel
	p.AssemblyAngularVelocity = randomUnit() * (6 + math.random() * 10)
	table.insert(debrisList, p)
	task.delay(HP.DebrisLifetime, function()
		if p.Parent then
			TweenService:Create(p, TweenInfo.new(0.6), { Transparency = 1 }):Play()
			task.wait(0.65)
			if p.Parent then
				p:Destroy()
			end
		end
		removeDebris(p)
	end)
end

local function carveStep(c, r, dirty, data, stats)
	local rr = r * HP.CarveRadiusScale
	local hit = workspace:Raycast(c + Vector3.yAxis * rr, Vector3.new(0, -rr * 2.2, 0), terrainOnly)
	if carve(c, rr, dirty) then
		stats.carves += 1
	end
	if WorldBlast then
		WorldBlast:Fire(c, r, data.userId)
	end
	if not hit or stats.debris >= HP.MaxDebrisPerCast then
		return
	end
	local mat = DEBRIS_MAT[hit.Material] or hit.Material
	local okC, color = pcall(function()
		return Terrain:GetMaterialColor(mat)
	end)
	if not okC then
		mat, color = Enum.Material.Ground, Color3.fromRGB(102, 82, 60)
	end
	local side = data.dir:Cross(Vector3.yAxis)
	side = side.Magnitude > 1e-3 and side.Unit or Vector3.xAxis
	for _ = 1, math.random(2, 3) do
		if stats.debris >= HP.MaxDebrisPerCast then
			break
		end
		local sgn = (math.random() < 0.5) and -1 or 1
		local pos = Vector3.new(c.X, hit.Position.Y, c.Z) + side * sgn * rr * (0.7 + math.random() * 0.4) + Vector3.yAxis * 1.5
		local vel = side * sgn * (35 + math.random() * 45) + Vector3.yAxis * (45 + math.random() * 55) + data.dir * (15 + math.random() * 40)
		local s = 0.8 + math.random() * 1.8
		spawnRock(pos, vel, mat, color, Vector3.new(s, s * (0.6 + math.random() * 0.5), s * (0.7 + math.random() * 0.5)))
		stats.debris += 1
	end
end

---------------------------------------------------------------------------------------------------
-- breakables: anchored props that shatter, restored exactly afterwards
local breakables = {} -- [model] = info

local function registerBreakable(model)
	if breakables[model] or not model:IsA("Model") then
		return
	end
	local info = { model = model, parent = model.Parent, parts = {}, restoreAt = nil }
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			info.parts[d] = {
				cf = d.CFrame, anchored = d.Anchored, cc = d.CanCollide, cq = d.CanQuery, ct = d.CanTouch,
				tr = d.Transparency, group = d.CollisionGroup, parent = d.Parent,
			}
		end
	end
	local cf, size = model:GetBoundingBox()
	info.center = cf.Position
	info.radius = size.Magnitude / 2
	info.pristine = model:Clone()
	breakables[model] = info
end
for _, m in ipairs(CollectionService:GetTagged("Breakable")) do
	registerBreakable(m)
end
CollectionService:GetInstanceAddedSignal("Breakable"):Connect(registerBreakable)

local function restoreBreakable(model, info)
	local missing = model.Parent == nil
	if not missing then
		for part in pairs(info.parts) do
			if not part.Parent then
				missing = true
				break
			end
		end
	end
	if missing then
		breakables[model] = nil
		if model.Parent then
			model:Destroy()
		end
		local fresh = info.pristine:Clone()
		fresh.Parent = info.parent -- the tag comes with the clone and re-registers it
		return
	end
	for part, o in pairs(info.parts) do
		part.Anchored = true
		part.CFrame = o.cf
		part.Anchored = o.anchored
		part.CanCollide = o.cc
		part.CanQuery = o.cq
		part.CanTouch = o.ct
		part.Transparency = o.tr
		part.CollisionGroup = o.group
		if part.Parent ~= o.parent then
			part.Parent = o.parent
		end
	end
end

local function breakNear(a, b, r, data, stats)
	local eraseR = r * HP.EraseRadiusScale
	local breakR = r * HP.BreakRadiusScale
	for model, info in pairs(breakables) do
		if model.Parent and segDist(info.center, a, b) <= breakR + info.radius then
			local touched = false
			for part, o in pairs(info.parts) do
				if part.Parent and part.Anchored and part.Transparency < 1 then
					local d = segDist(part.Position, a, b) - part.Size.Magnitude * 0.25
					if d <= eraseR then
						part.Transparency = 1
						part.CanCollide = false
						part.CanQuery = false
						part.CanTouch = false
						touched = true
						stats.breaks += 1
					elseif d <= breakR then
						local rel = part.Position - data.origin
						local radial = rel - data.dir * rel:Dot(data.dir)
						radial = radial.Magnitude > 0.1 and radial.Unit or randomUnit()
						part.Anchored = false
						part.CollisionGroup = "Debris"
						pcall(function()
							part:SetNetworkOwner(nil)
						end)
						part.AssemblyLinearVelocity = radial * (40 + math.random() * 50) + data.dir * (50 + math.random() * 60) + Vector3.yAxis * (30 + math.random() * 50)
						part.AssemblyAngularVelocity = randomUnit() * (4 + math.random() * 8)
						touched = true
						stats.breaks += 1
					end
				end
			end
			if touched then
				info.restoreAt = os.clock() + HP.BreakableRestoreTime
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Lapse Blue: telekinetic grab-and-throw. The held body hangs from an AlignPosition on its chest, so the rest
-- of the ragdoll dangles and swings naturally while the caster steers the hold point.
local grabs = {} -- [player] = { model, align, att, t0 } (+ victim = the Player, for a player body: no align/att)

-- HOLD (2026-11-10, "Gojo's ult: people can just walk out", "Blue doesn't grab people"). Blue and the Domain catch
-- OTHER PLAYERS too. The server can't move a client-owned body, so a caught player is only MARKED here: GrabbedBy +
-- BlueHoldPos (the hold point the caster steers) or InDomain + VoidHover (where it floats) on its character. The
-- victim's own GojoClient (it runs for every player, whatever kit they have equipped - see SelfHold there) hangs the
-- body at that point with its own constraints, the way the server hangs an NPC. While it is held the server keeps the
-- body stunned + ragdolled (holdPlayer, refreshed every frame), so every kit's gate refuses its moves (PvP.stunned),
-- PvPStunClient takes its walking / jumping, Dash refuses, Goku's flight ends - and a client that never applied the
-- hold still can't walk out. Forms the knockback clients treat as immune (super armour, the Susanoo, Ultra Instinct)
-- are never caught; giant forms are never grabbed, and a void pins one where it stands instead of lifting it.
local HOLD_REFRESH = 0.5 -- s of stun / ragdoll a held player keeps (so it lapses this long after it is let go)
local function holdImmune(model)
	return model:GetAttribute("SuperArmor") or model:GetAttribute("Guardian") or model:GetAttribute("AscForm") == "Instinct"
end
local function giantForm(model)
	return model:GetAttribute("Morphed") or model:GetAttribute("TitanForm") or model:GetAttribute("FoxBeast") or PvP.isForm(model)
end
local function holdPlayer(model)
	-- the stun is re-stamped only when it runs low (an attribute write replicates; this runs every frame)
	if (tonumber(model:GetAttribute("StunnedUntil")) or 0) - now() < HOLD_REFRESH * 0.5 then
		PvP.stun(model, HOLD_REFRESH)
	end
	PvP.ragdoll(model, HOLD_REFRESH) -- limp, like a held NPC (PvPStunClient puts its humanoid into Physics)
end
local unfreezeHook -- set by the Domain section: pulls a body out of any Unlimited Void
-- a body that has just been flung (a void's shatter, a Blue throw, a Red or Purple hit) can't be caught by any void for
-- a moment: otherwise a second void standing at the same time freezes it mid-flight and the fling dies. Not recorded
-- as released, so once the window ends a void that is still up takes the body back and it floats again.
local voidGrace = {} -- [model] = server time until which no void may freeze it
local function graceFling(model, secs)
	voidGrace[model] = now() + (secs or 1.6)
end

local function endGrab(player, throwDir)
	local g = grabs[player]
	if not g then
		return
	end
	grabs[player] = nil
	-- (2026-11-10, "add a cooldown to Gojo's blue") the cooldown starts when the grab ENDS - a hold can last 15 s, so one
	-- started at the grab was always over by the throw - and the caster's Q button is told, the way Red / Purple are
	if player.Parent then
		local cd = BLUE.Cooldown * cdScale(player, false)
		getState(player).blueReady = os.clock() + cd
		AbilityResult:FireClient(player, "Blue", true, { cooldownEnd = now() + cd })
	end
	if g.align then
		g.align:Destroy()
	end
	if g.att then
		g.att:Destroy()
	end
	local m = g.model
	if m and m.Parent then
		m:SetAttribute("GrabbedBy", nil)
		if g.victim then
			m:SetAttribute("BlueHoldPos", nil) -- its client lets go; the Fling below sends the release throw / drop (PvP.knock)
		end
		local v = Vector3.zero
		if typeof(throwDir) == "Vector3" and finite(throwDir) and throwDir.Magnitude > 0.1 then
			v = throwDir.Unit * BLUE.ThrowSpeed + Vector3.yAxis * 12
			graceFling(m)
		end
		if RagdollService then
			RagdollService.Fling(m, v, randomUnit() * 9, BLUE.RagdollTime)
		end
	end
	local thrownDir = (typeof(throwDir) == "Vector3" and finite(throwDir) and throwDir.Magnitude > 0.1) and throwDir.Unit or nil
	AbilityEvent:FireAllClients("BlueRelease", { userId = player.UserId, thrown = typeof(throwDir) == "Vector3", dir = thrownDir })
end

-- anything that hits a held body (a purple, say) takes it out of the caster's hands
local function releaseModel(model)
	if unfreezeHook then
		unfreezeHook(model)
	end
	for p, g in pairs(grabs) do
		if g.model == model then
			endGrab(p, nil)
		end
	end
end

local function startGrab(player, s, target)
	if grabs[player] or s.casting or not RagdollService then
		return
	end
	local t = os.clock()
	if t < (s.blueReady or 0) then
		return
	end
	local char, _, hrp = liveChar(player)
	if not char or typeof(target) ~= "Instance" or not target:IsA("Model") then
		return
	end
	-- (2026-11-10) another player's character can be grabbed too (HOLD above); GojoClient's pickTarget skips the same
	local victim = PvP.playerOf(target)
	if victim then
		if victim == player or PvP.hittable(victim) ~= target or holdImmune(target) or giantForm(target) then
			return
		end
	elseif not CollectionService:HasTag(target, NPC_TAG) then
		return
	end
	if not target:IsDescendantOf(workspace) or target:GetAttribute("GrabbedBy") then
		return
	end
	local ut = target:FindFirstChild("UpperTorso")
	if not ut or (ut.Position - hrp.Position).Magnitude > BLUE.Range then
		return
	end
	s.blueReady = t + 0.3 -- a double press can't start two grabs; the real cooldown starts at the release (endGrab)
	if unfreezeHook then
		unfreezeHook(target)
	end
	if victim then
		-- a player is only marked: its own client pulls its chest to BlueHoldPos and hangs it there (the point is set
		-- first, so it is there when GrabbedBy lands); GrabMove moves the point, the Heartbeat keeps it stunned + limp
		target:SetAttribute("BlueHoldPos", ut.Position + Vector3.yAxis * 3)
		target:SetAttribute("GrabbedBy", player.UserId)
		target:SetAttribute("LastHitBy", player.UserId)
		holdPlayer(target)
		grabs[player] = { model = target, t0 = t, victim = victim }
		AbilityEvent:FireAllClients("BlueGrab", { userId = player.UserId, model = target })
		return
	end
	RagdollService.Ragdoll(target, 0.1) -- RagdollService's GrabbedBy guard keeps it down while it is held
	target:SetAttribute("GrabbedBy", player.UserId)
	target:SetAttribute("LastHitBy", player.UserId)
	local att = Instance.new("Attachment")
	att.Name = "BlueGrab"
	att.Parent = ut
	local ap = Instance.new("AlignPosition")
	ap.Name = "BlueGrabAlign"
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att
	ap.Position = ut.Position + Vector3.yAxis * 3
	ap.MaxForce = BLUE.MaxForce
	ap.MaxVelocity = BLUE.MaxVelocity
	ap.Responsiveness = BLUE.Responsiveness
	ap.Parent = ut
	grabs[player] = { model = target, align = ap, att = att, t0 = t }
	AbilityEvent:FireAllClients("BlueGrab", { userId = player.UserId, model = target })
end

GrabMove.OnServerEvent:Connect(function(player, pos)
	local g = grabs[player]
	if not g or typeof(pos) ~= "Vector3" or not finite(pos) then
		return
	end
	local _, _, hrp = liveChar(player)
	if not hrp then
		endGrab(player, nil)
		return
	end
	local off = pos - hrp.Position
	if off.Magnitude > BLUE.MaxHoldRange then
		pos = hrp.Position + off.Unit * BLUE.MaxHoldRange
	end
	if g.victim then
		g.model:SetAttribute("BlueHoldPos", pos) -- a held player follows it on its own client (HOLD)
	else
		g.align.Position = pos
	end
end)

local function requestBlue(player, s, payload)
	if payload.action == "start" then
		startGrab(player, s, payload.target)
	elseif payload.action == "release" then
		endGrab(player, payload.dir)
	end
end

Players.PlayerRemoving:Connect(function(p)
	endGrab(p, nil)
end)

-- (2026-11-10, "they can only be held for 2-3 seconds before they're auto thrown") when the hold runs out (BLUE.MaxHold)
-- the body is thrown, not dropped: outward from the caster through the body (where the hold point has it - in front,
-- along the caster's aim), flattened with a slight rise, at the normal throw speed (endGrab adds its own lift)
local function autoThrowDir(p, g)
	local _, _, hrp = liveChar(p)
	local ut = g.model:FindFirstChild("UpperTorso")
	local d = (hrp and ut) and (ut.Position - hrp.Position) or Vector3.zero
	local flat = Vector3.new(d.X, 0, d.Z)
	if flat.Magnitude < 1 and hrp then
		local lv = hrp.CFrame.LookVector
		flat = Vector3.new(lv.X, 0, lv.Z)
	end
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	return (flat.Unit + Vector3.yAxis * 0.25).Unit
end

RunService.Heartbeat:Connect(function()
	for p, g in pairs(grabs) do
		if not g.model.Parent or (g.align and not g.align.Parent) or not liveChar(p)
			or (g.victim and (PvP.hittable(g.victim) ~= g.model or holdImmune(g.model))) then
			endGrab(p, nil)
		elseif os.clock() - g.t0 > BLUE.MaxHold then
			endGrab(p, autoThrowDir(p, g))
		elseif g.victim then
			holdPlayer(g.model) -- (2026-11-10) a held player stays stunned + limp until it is let go
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- Hollow Purple
local castCounter = 0

local function hitNPC(player, model, data)
	releaseModel(model)
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("HumanoidRootPart")
	if not torso then
		return
	end
	local rel = torso.Position - data.origin
	local radial = (rel - data.dir * rel:Dot(data.dir)) * Vector3.new(1, 0, 1)
	if radial.Magnitude < 0.75 then
		local side = data.dir:Cross(Vector3.yAxis)
		side = side.Magnitude > 1e-3 and side.Unit or Vector3.xAxis
		radial = side * ((math.random() < 0.5) and -1 or 1)
	else
		radial = radial.Unit
	end
	local v = data.dir * HP.ForwardFling + radial * HP.RadialFling + Vector3.yAxis * HP.UpFling
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		model:SetAttribute("LastHitBy", player.UserId)
		PvPBal.aimLine = { data.origin, data.dir, os.clock() } -- (2026-11-14) the orb's real line, for Sandbox.Powers (what it erases)
		hum:TakeDamage(kitHit("Limitless", hum, HP.Damage))
	end
	if RagdollService then
		RagdollService.Fling(model, v, randomUnit() * HP.Spin, nil)
	end
	AbilityEvent:FireAllClients("PurpleHit", { castId = data.castId, pos = torso.Position })
end

local function runPurple(player, s, data, startChar)
	local launchAt = data.startServerTime + data.launchTime
	local castT0 = now()
	startChar:SetAttribute("CastingUntil", launchAt) -- (2026-11-09) an M1 that lands during the charge breaks the cast (PvP.breakCast)
	-- charge: cancel if the caster dies, respawns or leaves before launch
	while now() < launchAt do
		local char = liveChar(player)
		local broke = char == startChar and PvPBal.castBrokenSince(startChar, castT0)
		if not player.Parent or not char or char ~= startChar or broke then
			AbilityEvent:FireAllClients("PurpleCancel", { castId = data.castId })
			if s.castId == data.castId then
				s.casting = false
			end
			if broke then
				s.cd.HollowPurple = now() + PvPBal.CAST_BREAK_COOLDOWN
				AbilityResult:FireClient(player, "HollowPurple", true, { cooldownEnd = s.cd.HollowPurple })
			end
			return
		end
		RunService.Heartbeat:Wait()
	end

	local stats = { hits = 0, pulled = 0, carves = 0, debris = 0, breaks = 0 }
	local hitSet, pulledSet, dirty = {}, {}, {}
	local r = data.radius
	local prev, nextCarve = 0, 0
	while true do
		local dist = math.clamp((now() - launchAt) * data.speed, 0, data.range)
		local a = data.origin + data.dir * prev
		local b = data.origin + data.dir * dist
		for _, model in ipairs(PvP.bodies(NPC_TAG, player)) do
			if model.Parent and not hitSet[model] then
				local pts = bodyPoints(model, a, b)
				local hit = false
				for _, pt in ipairs(pts) do
					if segDist(pt, a, b) <= r + 2 then
						hit = true
						break
					end
				end
				if hit then
					hitSet[model] = true
					stats.hits += 1
					hitNPC(player, model, data)
				elseif not pulledSet[model] and RagdollService and pts[1] then
					-- Lapse Blue: whatever is just ahead of the orb gets dragged into it
					local rel = pts[1] - data.origin
					local along = rel:Dot(data.dir)
					local ahead = along - dist
					if ahead > 0 and ahead <= HP.PullLeadDistance and (rel - data.dir * along).Magnitude <= r * HP.PullRadiusScale then
						local hum = model:FindFirstChildOfClass("Humanoid")
						if hum and hum.Health > 0 then
							pulledSet[model] = true
							stats.pulled += 1
							-- drag them sideways onto the orb's axis (and a little toward it) so it runs straight into them
							local perp = data.dir * along - rel
							perp = perp.Magnitude > 0.1 and perp.Unit or Vector3.zero
							local toward = b - pts[1]
							toward = toward.Magnitude > 0.1 and toward.Unit or -data.dir
							RagdollService.Fling(model, perp * HP.PullSpeed + toward * HP.PullSpeed * 0.35 + Vector3.yAxis * 10, nil, 3)
						end
					end
				end
			end
		end
		while nextCarve <= dist do
			carveStep(data.origin + data.dir * nextCarve, r, dirty, data, stats)
			nextCarve += HP.CarveStep
		end
		breakNear(a, b, r, data, stats)
		prev = dist
		if dist >= data.range then
			break
		end
		RunService.Heartbeat:Wait()
	end
	AbilityEvent:FireAllClients("PurpleEnd", { castId = data.castId, pos = data.origin + data.dir * data.range })
	local chunks = 0
	for _ in pairs(dirty) do
		chunks += 1
	end
	print(string.format("[Combat] Purple #%d %s hits=%d pulled=%d carves=%d debris=%d breaks=%d chunks=%d",
		data.castId, data.variant, stats.hits, stats.pulled, stats.carves, stats.debris, stats.breaks, chunks))
	task.delay(HP.TerrainRestoreDelay, function()
		for key in pairs(dirty) do
			local c = terrainCache[key]
			if c then
				c.refs -= 1
				if c.refs <= 0 then
					table.insert(restoreQueue, key)
				end
			end
		end
	end)
end

local function requestPurple(player, s, payload)
	local char, _, hrp = liveChar(player)
	if not char then
		AbilityResult:FireClient(player, "HollowPurple", false, { reason = "dead" })
		return
	end
	if s.casting then
		AbilityResult:FireClient(player, "HollowPurple", false, { reason = "busy" })
		return
	end
	if grabs[player] then
		endGrab(player, nil)
	end
	local t = now()
	if t < (s.cd.HollowPurple or 0) then
		AbilityResult:FireClient(player, "HollowPurple", false, { reason = "cooldown", cooldownEnd = s.cd.HollowPurple })
		return
	end
	local variant = (payload.variant == "Incantation") and "Incantation" or "Quick"
	local V = HP.Variants[variant]
	local aim, flat = clampAim(payload.aimDir)
	if not aim then
		local lv = hrp.CFrame.LookVector
		flat = Vector3.new(lv.X, 0, lv.Z)
		flat = flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(0, 0, -1)
		aim = flat
	end
	castCounter += 1
	local data = {
		castId = castCounter, variant = variant, startServerTime = t, userId = player.UserId,
		origin = hrp.Position + flat * HP.OriginForward + Vector3.yAxis * HP.OriginUp,
		dir = aim, launchTime = V.LaunchTime, speed = V.Speed, radius = V.Radius, range = V.Range,
	}
	s.casting = true
	s.castId = data.castId
	s.cd.HollowPurple = t + HP.Cooldown * cdScale(player, false)
	AbilityCast:FireAllClients(player, "HollowPurple", data)
	AbilityResult:FireClient(player, "HollowPurple", true, { castId = data.castId, cooldownEnd = s.cd.HollowPurple })
	Threat:Fire(hrp.Position, HP.ThreatRadius, V.LaunchTime + 1)
	task.delay(V.LockTime, function()
		if s.castId == data.castId then
			s.casting = false
		end
	end)
	task.spawn(runPurple, player, s, data, char)
end

---------------------------------------------------------------------------------------------------
-- Reversal: Red - a repulsive orb fired from the fingertip. It detonates on the first body or surface it meets
-- (or at the end of its range) and blasts everything around it outward.
local redCounter = 0
local redRay = RaycastParams.new()
redRay.FilterType = Enum.RaycastFilterType.Exclude
local looseOverlap = OverlapParams.new()
looseOverlap.FilterType = Enum.RaycastFilterType.Exclude

local function bodiesAndPlayers()
	local list = { FX }
	local npcs = workspace:FindFirstChild("NPCs")
	if npcs then
		table.insert(list, npcs)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

local function redBlast(player, data, pos)
	local R = RED.BlastRadius
	AbilityEvent:FireAllClients("RedBlast", { castId = data.castId, pos = pos, radius = R, userId = data.userId })
	if WorldBlast then
		WorldBlast:Fire(pos, R * 0.75, player.UserId)
	end
	local hits, breaks = 0, 0
	-- bodies (alive or corpses) are thrown straight away from the blast, harder the closer they were
	for _, model in ipairs(PvP.bodies(NPC_TAG, player)) do
		local t = model:FindFirstChild("UpperTorso") or model:FindFirstChild("HumanoidRootPart")
		if t and model.Parent then
			-- (2026-11-10) a giant form: its body point nearest the blast (its torso floats far above where Red bursts)
			local off = (PvP.formPoint(model, pos) or t.Position) - pos
			local d = off.Magnitude
			if d <= R then
				hits += 1
				releaseModel(model)
				local k = 1 - d / R
				local radial = d > 0.5 and off.Unit or data.dir
				local dir = (radial + Vector3.yAxis * RED.UpBias).Unit
				local hum = model:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 and model:GetAttribute("Dead") ~= true then
					model:SetAttribute("LastHitBy", player.UserId)
					hum:TakeDamage(kitHit("Limitless", hum, RED.Damage * k))
				end
				if RagdollService then
					RagdollService.Fling(model, dir * (RED.MinPower + (RED.Power - RED.MinPower) * k), randomUnit() * (10 + 20 * k), RED.RagdollTime)
				end
			end
		end
	end
	-- loose physics props (bowling pins, swings, knocked-off debris) get shoved as well
	looseOverlap.FilterDescendantsInstances = bodiesAndPlayers()
	local pushed = {}
	for _, part in ipairs(workspace:GetPartBoundsInRadius(pos, R, looseOverlap)) do
		local root = part.AssemblyRootPart
		if root and not root.Anchored and not pushed[root] then
			pushed[root] = true
			local off = root.Position - pos
			local d = off.Magnitude
			local k = math.clamp(1 - d / R, 0, 1)
			local radial = d > 0.5 and off.Unit or data.dir
			root.AssemblyLinearVelocity += (radial + Vector3.yAxis * RED.UpBias).Unit * RED.Power * 0.6 * k
		end
	end
	-- breakable props near the centre come apart outward (restored by the breakables timer)
	local inner = R * RED.BreakRadiusScale
	for model, info in pairs(breakables) do
		if model.Parent and (info.center - pos).Magnitude <= inner + info.radius then
			local touched = false
			for part in pairs(info.parts) do
				if part.Parent and part.Anchored and part.Transparency < 1 then
					local off = part.Position - pos
					local d = off.Magnitude
					if d <= inner then
						local k = 1 - d / inner
						local radial = d > 0.5 and off.Unit or data.dir
						part.Anchored = false
						part.CollisionGroup = "Debris"
						pcall(function()
							part:SetNetworkOwner(nil)
						end)
						part.AssemblyLinearVelocity = (radial + Vector3.yAxis * 0.5).Unit * RED.BreakPower * (0.5 + k)
						part.AssemblyAngularVelocity = randomUnit() * (4 + 8 * k)
						touched = true
						breaks += 1
					end
				end
			end
			if touched then
				info.restoreAt = os.clock() + HP.BreakableRestoreTime
			end
		end
	end
	-- a crater where it went off near the ground (restored from the pristine terrain cache like the purple trench)
	local ground = workspace:Raycast(pos + Vector3.yAxis * 2, Vector3.new(0, -14, 0), terrainOnly)
	if ground then
		local dirty = {}
		carve(ground.Position, RED.CraterRadius, dirty)
		task.delay(HP.TerrainRestoreDelay, function()
			for key in pairs(dirty) do
				local c = terrainCache[key]
				if c then
					c.refs -= 1
					if c.refs <= 0 then
						table.insert(restoreQueue, key)
					end
				end
			end
		end)
	end
	print(string.format("[Combat] Red #%d blast at (%.0f,%.0f,%.0f) hits=%d breaks=%d", data.castId, pos.X, pos.Y, pos.Z, hits, breaks))
end

local function runRed(player, s, data, startChar)
	local launchAt = data.startServerTime + data.launchTime
	while now() < launchAt do
		local char = liveChar(player)
		if not player.Parent or not char or char ~= startChar then
			AbilityEvent:FireAllClients("RedCancel", { castId = data.castId })
			if s.redId == data.castId then
				s.casting = false
			end
			return
		end
		RunService.Heartbeat:Wait()
	end
	redRay.FilterDescendantsInstances = bodiesAndPlayers()
	local r = RED.ProjectileRadius
	local prev = 0
	while true do
		local dist = math.clamp((now() - launchAt) * data.speed, 0, data.range)
		local a = data.origin + data.dir * prev
		local b = data.origin + data.dir * dist
		local hitPos
		local ab = b - a
		local len2 = ab:Dot(ab)
		for _, model in ipairs(PvP.bodies(NPC_TAG, player)) do
			if model.Parent then
				for _, pt in ipairs(bodyPoints(model, a, b)) do
					if segDist(pt, a, b) <= r + 1 then
						local tt = len2 > 1e-6 and math.clamp((pt - a):Dot(ab) / len2, 0, 1) or 0
						hitPos = a + ab * tt
						break
					end
				end
			end
			if hitPos then
				break
			end
		end
		if not hitPos and len2 > 1e-6 then
			local res = workspace:Raycast(a, ab, redRay)
			if res then
				hitPos = res.Position - data.dir
			end
		end
		if hitPos or dist >= data.range then
			redBlast(player, data, hitPos or b)
			return
		end
		prev = dist
		RunService.Heartbeat:Wait()
	end
end

local function requestRed(player, s, payload)
	local char, _, hrp = liveChar(player)
	if not char then
		AbilityResult:FireClient(player, "Red", false, { reason = "dead" })
		return
	end
	if s.casting then
		AbilityResult:FireClient(player, "Red", false, { reason = "busy" })
		return
	end
	local t = now()
	if t < (s.cd.Red or 0) then
		AbilityResult:FireClient(player, "Red", false, { reason = "cooldown", cooldownEnd = s.cd.Red })
		return
	end
	if grabs[player] then
		endGrab(player, nil)
	end
	local aim, flat = clampAim(payload.aimDir)
	if not aim then
		local lv = hrp.CFrame.LookVector
		flat = Vector3.new(lv.X, 0, lv.Z)
		flat = flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(0, 0, -1)
		aim = flat
	end
	redCounter += 1
	local right = flat:Cross(Vector3.yAxis)
	local data = {
		castId = redCounter, startServerTime = t, userId = player.UserId,
		origin = hrp.Position + flat * RED.OriginForward + right * RED.OriginRight + Vector3.yAxis * RED.OriginUp,
		dir = aim, launchTime = RED.LaunchTime, speed = RED.Speed, range = RED.Range,
	}
	s.casting = true
	s.redId = data.castId
	s.cd.Red = t + RED.Cooldown * cdScale(player, false)
	AbilityCast:FireAllClients(player, "Red", data)
	AbilityResult:FireClient(player, "Red", true, { castId = data.castId, cooldownEnd = s.cd.Red })
	task.delay(RED.LockTime, function()
		if s.redId == data.castId then
			s.casting = false
		end
	end)
	task.spawn(runRed, player, s, data, char)
end

---------------------------------------------------------------------------------------------------
-- Domain Expansion: Unlimited Void. As the dome sweeps outward everything it passes is frozen in "information
-- overload": weightless (a VectorForce cancels gravity on every limb), hanging upright above the ground, slowly
-- turning and twitching. (2026-11-08) Only bodies INSIDE the dome are caught - while it expands, and any that walk in
-- once it has formed; the capture wave that used to race on across the whole map (DOMAIN.Reach) is gone. When the
-- domain ends it shatters: the bodies caught inside take the damage and the fling.
local domainCounter = 0
local domains = {} -- [player] = d

local function unfreeze(d, model, rec)
	for _, inst in ipairs(rec.parts) do
		if inst.Parent then
			inst:Destroy()
		end
	end
	d.frozen[model] = nil
	d.released[model] = true
	if model.Parent then
		model:SetAttribute("InDomain", nil)
		if rec.player then
			model:SetAttribute("VoidHover", nil) -- its own client lets go (HOLD, in the Blue section)
		end
	end
end

-- anything else grabbing or blasting a frozen body takes it out of the domain first
unfreezeHook = function(model)
	graceFling(model)
	for _, d in pairs(domains) do
		local rec = d.frozen[model]
		if rec then
			unfreeze(d, model, rec)
		end
	end
end

-- (2026-11-10) a PLAYER the void catches is only marked (HOLD, in the Blue section): its own client floats it at
-- VoidHover - 7-16 studs over whatever it stands on (a roof, an interior floor; the NPC hover only knows terrain), kept
-- under any ceiling - and runDomain keeps it stunned + limp until the void lets go. A giant form is pinned where it
-- stands; immune forms are never caught.
local function freezePlayer(d, model, ut)
	if holdImmune(model) then
		return
	end
	local pos = ut.Position
	local hover = pos
	if not giantForm(model) then
		redRay.FilterDescendantsInstances = bodiesAndPlayers() -- (shared with Red, which sets its own filter on every use)
		local ground = workspace:Raycast(pos + Vector3.yAxis, Vector3.new(0, -60, 0), redRay)
		local y = (ground and ground.Position.Y or (pos.Y - 3)) + DOMAIN.HoverMin + math.random() * (DOMAIN.HoverMax - DOMAIN.HoverMin)
		local roof = y > pos.Y and workspace:Raycast(pos, Vector3.new(0, y - pos.Y + 4, 0), redRay)
		if roof then
			y = math.max(pos.Y, roof.Position.Y - 4)
		end
		hover = Vector3.new(pos.X, y, pos.Z)
	end
	model:SetAttribute("VoidHover", hover) -- before InDomain, so the client has the point when the mark lands
	model:SetAttribute("InDomain", d.userId)
	model:SetAttribute("LastHitBy", d.userId)
	holdPlayer(model)
	d.frozen[model] = { parts = {}, player = true, inside = (pos - d.center).Magnitude <= d.radius + 2 }
end

local function freezeInDomain(d, model)
	local ut = model:FindFirstChild("UpperTorso")
	if not ut or not RagdollService or model:GetAttribute("GrabbedBy") or model:GetAttribute("InDomain")
		or (voidGrace[model] or 0) > now() then
		return -- held by a Blue, already floating in someone else's void, or flung a moment ago
	end
	if PvP.playerOf(model) then
		freezePlayer(d, model, ut)
		return
	end
	RagdollService.Ragdoll(model, 3)
	model:SetAttribute("InDomain", d.userId)
	local rec = {
		parts = {}, nextTwitch = 0, phase = math.random() * math.pi * 2,
		inside = (ut.Position - d.center).Magnitude <= d.radius + 2, -- only these take the shatter
		yaw = math.random() * math.pi * 2, spin = (math.random() < 0.5 and -1 or 1) * (0.25 + math.random() * 0.35),
	}
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			p.AssemblyLinearVelocity *= 0.2
			local a = Instance.new("Attachment")
			a.Name = "VoidAtt"
			a.Parent = p
			local f = Instance.new("VectorForce")
			f.Name = "VoidFloat"
			f.Attachment0 = a
			f.RelativeTo = Enum.ActuatorRelativeTo.World
			f.ApplyAtCenterOfMass = true
			f.Force = Vector3.new(0, p.AssemblyMass * workspace.Gravity, 0)
			f.Parent = p
			table.insert(rec.parts, f)
			table.insert(rec.parts, a)
		end
	end
	local ground = workspace:Raycast(ut.Position + Vector3.yAxis * 3, Vector3.new(0, -60, 0), terrainOnly)
	local gy = ground and ground.Position.Y or (ut.Position.Y - 3)
	rec.hover = Vector3.new(ut.Position.X, gy + DOMAIN.HoverMin + math.random() * (DOMAIN.HoverMax - DOMAIN.HoverMin), ut.Position.Z)
	local att = Instance.new("Attachment")
	att.Name = "VoidHoverAtt"
	att.Parent = ut
	local ap = Instance.new("AlignPosition")
	ap.Name = "VoidHover"
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att
	ap.Position = rec.hover
	ap.Responsiveness = 6
	ap.MaxForce = 6000
	ap.MaxVelocity = 18 -- a clear lift-off rather than a slow drift
	ap.Parent = ut
	table.insert(rec.parts, ap)
	table.insert(rec.parts, att)
	rec.align = ap
	-- hang upright with the limbs adrift, slowly turning: a body suspended in the void
	local ao = Instance.new("AlignOrientation")
	ao.Name = "VoidUpright"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.Responsiveness = 4
	ao.MaxTorque = 2500
	ao.CFrame = CFrame.Angles(0, rec.yaw, 0)
	ao.Parent = ut
	table.insert(rec.parts, ao)
	rec.upright = ao
	d.frozen[model] = rec
end

local function collapseDomain(player, d, early)
	if d.collapsed then
		return
	end
	d.collapsed = true
	if domains[player] == d then
		domains[player] = nil
	end
	AbilityEvent:FireAllClients("DomainCollapse", { castId = d.castId, center = d.center, radius = d.radius, early = early == true })
	if WorldBlast and not early then
		WorldBlast:Fire(d.center, d.radius * 0.5, d.userId)
	end
	local n, outside = 0, 0
	for model, rec in pairs(d.frozen) do
		unfreeze(d, model, rec)
		local t = model.Parent and model:FindFirstChild("UpperTorso")
		if t and not rec.inside then
			-- caught by the wave beyond the dome: just let go (they drop, ragdolled, and get back up)
			outside += 1
			RagdollService.Ragdoll(model, 1.5)
		elseif t then
			n += 1
			local off = (t.Position - d.center) * Vector3.new(1, 0, 1)
			local radial = off.Magnitude > 1 and off.Unit or Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
			local dir = (radial + Vector3.yAxis * DOMAIN.CollapseUp).Unit
			local hum = model:FindFirstChildOfClass("Humanoid")
			if not early and hum and hum.Health > 0 and model:GetAttribute("Dead") ~= true then
				model:SetAttribute("LastHitBy", d.userId)
				hum:TakeDamage(kitHit("Limitless", hum, DOMAIN.CollapseDamage)) -- (2026-11-10) a player takes it through the PvP caps
			end
			local power = early and DOMAIN.CollapsePower * 0.3 or DOMAIN.CollapsePower * (0.75 + math.random() * 0.4)
			graceFling(model, 2)
			RagdollService.Fling(model, dir * power, randomUnit() * 24, 3)
		end
	end
	print(string.format("[Combat] Domain #%d %s with %d bodies inside, %d let go outside", d.castId, early and "broke early" or "shattered", n, outside))
end

local function runDomain(player, s, d)
	local start = d.startServerTime + d.start
	local endsAt = start + d.expandTime + d.duration
	local dt = 0
	while true do
		local t = now()
		if not player.Parent or not liveChar(player) then
			collapseDomain(player, d, true)
			return
		end
		if t >= endsAt then
			collapseDomain(player, d, false)
			return
		end
		-- the expanding boundary captures everything it sweeps past, and once the dome has formed anything that walks
		-- inside it; nothing beyond d.radius is ever touched
		if t >= start then
			local formed = start + d.expandTime
			local r = d.radius
			if t < formed then
				r = d.radius * (t - start) / d.expandTime
			end
			for m, untilT in pairs(voidGrace) do
				if untilT <= t or not m.Parent then
					voidGrace[m] = nil
				end
			end
			-- (2026-11-10) other players too (freezePlayer) - it used to be the NPC tag only, so a player just walked out.
			-- STUDIO ONLY: attribute PvPSelfTest = true on this script lets a void catch its own caster, so the player path
			-- can be playtested in Play Solo (one player). Never read in a live server.
			local exclude = player
			if RunService:IsStudio() and script:GetAttribute("PvPSelfTest") == true then
				exclude = nil
			end
			for _, model in ipairs(PvP.bodies(NPC_TAG, exclude)) do
				if model.Parent and not d.frozen[model] and not d.released[model] then
					local tt = model:FindFirstChild("UpperTorso")
					if tt and (tt.Position - d.center).Magnitude <= r then
						freezeInDomain(d, model)
					end
				end
			end
		end
		-- keep the frozen drifting, bobbing and twitching
		local clock = os.clock()
		for model, rec in pairs(d.frozen) do
			if not model.Parent or (rec.align and not rec.align.Parent) then
				d.frozen[model] = nil
			elseif rec.player then
				-- (2026-11-10) a caught player floats on its own client: keep it stunned + limp, and let it go if it died,
				-- respawned or turned immune. (Never RagdollService.Ragdoll here: on a player that fires a knockback.)
				local hum = model:FindFirstChildOfClass("Humanoid")
				if PvP.hittable(Players:GetPlayerFromCharacter(model)) ~= model or holdImmune(model) then
					unfreeze(d, model, rec)
				else
					holdPlayer(model)
					if DOMAIN.OverloadDPS > 0 and hum and hum.Health > 1 and dt > 0 then
						model:SetAttribute("LastHitBy", d.userId)
						hum:TakeDamage(PvPBal.dmg(hum, math.min(DOMAIN.OverloadDPS * dt, hum.Health - 1)))
					end
				end
			else
				RagdollService.Ragdoll(model, 3)
				rec.align.Position = rec.hover + Vector3.new(math.cos(clock * 0.4 + rec.phase) * 1.6, math.sin(clock * 1.3 + rec.phase) * 1.3, math.sin(clock * 0.5 + rec.phase) * 1.6)
				if rec.upright and rec.upright.Parent then
					rec.yaw += rec.spin * dt
					rec.upright.CFrame = CFrame.Angles(math.sin(clock * 0.7 + rec.phase) * 0.18, rec.yaw, math.cos(clock * 0.6 + rec.phase) * 0.18)
				end
				if clock >= rec.nextTwitch then
					rec.nextTwitch = clock + DOMAIN.TwitchEvery * (0.6 + math.random() * 0.8)
					local ut = model:FindFirstChild("UpperTorso")
					if ut then
						ut.AssemblyAngularVelocity += randomUnit() * (0.6 + math.random() * 1.2) -- a shudder; the upright align holds the rest
					end
					for _, n in ipairs({ "LeftLowerArm", "RightLowerArm", "LeftLowerLeg", "RightLowerLeg", "Head" }) do
						local p = model:FindFirstChild(n)
						if p then
							p.AssemblyLinearVelocity += randomUnit() * (3 + math.random() * 6)
						end
					end
				end
				local hum = model:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 1 and dt > 0 then
					hum:TakeDamage(math.min(DOMAIN.OverloadDPS * dt, hum.Health - 1))
				end
			end
		end
		dt = RunService.Heartbeat:Wait()
	end
end

local function requestDomain(player, s, payload)
	local char, _, hrp = liveChar(player)
	if not char then
		AbilityResult:FireClient(player, "Domain", false, { reason = "dead" })
		return
	end
	if s.casting or domains[player] then
		AbilityResult:FireClient(player, "Domain", false, { reason = "busy" })
		return
	end
	local t = now()
	if t < (s.cd.Domain or 0) then
		AbilityResult:FireClient(player, "Domain", false, { reason = "cooldown", cooldownEnd = s.cd.Domain })
		return
	end
	if grabs[player] then
		endGrab(player, nil)
	end
	local ground = workspace:Raycast(hrp.Position, Vector3.new(0, -20, 0), terrainOnly)
	local lv = hrp.CFrame.LookVector * Vector3.new(1, 0, 1)
	domainCounter += 1
	local d = {
		castId = domainCounter, startServerTime = t, userId = player.UserId,
		center = ground and ground.Position or (hrp.Position - Vector3.yAxis * 3),
		facing = lv.Magnitude > 1e-3 and lv.Unit or Vector3.new(0, 0, -1),
		radius = DOMAIN.Radius, start = DOMAIN.Start, expandTime = DOMAIN.ExpandTime, duration = DOMAIN.Duration,
		frozen = {}, released = {},
	}
	domains[player] = d
	s.casting = true
	s.domainId = d.castId
	s.cd.Domain = t + DOMAIN.Cooldown * cdScale(player, true)
	local data = {
		castId = d.castId, startServerTime = t, center = d.center, facing = d.facing, radius = d.radius,
		start = d.start, expandTime = d.expandTime, duration = d.duration,
	}
	AbilityCast:FireAllClients(player, "Domain", data)
	AbilityResult:FireClient(player, "Domain", true, { castId = d.castId, cooldownEnd = s.cd.Domain })
	Threat:Fire(d.center, d.radius * 1.3, d.start + d.expandTime)
	task.delay(DOMAIN.LockTime, function()
		if s.domainId == d.castId then
			s.casting = false
		end
	end)
	task.spawn(runDomain, player, s, d)
end

---------------------------------------------------------------------------------------------------
-- M1 punch combo
local function resolvePunch(player, combo, flat, finisher)
	local char, _, hrp = liveChar(player)
	if not char then
		return
	end
	local cf = CFrame.lookAt(hrp.Position, hrp.Position + flat) * CFrame.new(0, 0, -PUNCH.Range)
	local half = PUNCH.HitboxSize / 2 + Vector3.new(0.5, 0.5, 0.5)
	local final = combo >= PUNCH.ComboLength
	local fin = final and finisher and PUNCH.Finishers and PUNCH.Finishers[finisher] or nil
	if WorldBlast then
		WorldBlast:Fire(cf.Position, (fin and fin.crater) or 4.5, player.UserId)
	end
	local bodies = PvP.bodies(NPC_TAG, player)
	-- (2026-11-11) BLOCK: the hit comes from the puncher (PvP's front check), and the finisher breaks a guard
	PvP.setAim(player)
	PvPBal.m1Begin(final) -- (2026-11-09) M1 hits: full damage on players, and they break a cast
	-- (2026-11-11, missed punches) LOCK-ON ASSIST: when the box catches no living body, the nearest standing body in a
	-- corridor along the swing (Balance.M1_LOCK_REACH, capped at 10 studs; M1_LOCK_RADIUS wide; up to 5 studs above /
	-- below the chest - a hop or a ledge; clear line of sight) takes the hit instead. Players are tested over the same
	-- rewound positions as the box.
	local assist = nil
	do
		local any = false
		local reach = math.min(tonumber(BAL.M1_LOCK_REACH) or 10, 10)
		local rad = tonumber(BAL.M1_LOCK_RADIUS) or 3.5
		local best, bestD
		local chest = hrp.Position + Vector3.yAxis * 1
		for _, model in ipairs(bodies) do
			local h = model:FindFirstChildOfClass("Humanoid")
			local tp = model:FindFirstChild("UpperTorso") or model:FindFirstChild("HumanoidRootPart")
			if tp and h and h.Health > 0 and model:GetAttribute("Dead") ~= true and not PvP.isDown(model) and not PvP.isForm(model) then
				local offs = PvP.lagOffsets(model, player, (PUNCH.HitDelays and PUNCH.HitDelays[combo]) or PUNCH.HitDelay)
				for _, off in ipairs(offs) do
					local p = tp.Position + off
					local rel = p - chest
					local along = rel:Dot(flat)
					local side = (rel - flat * along) * Vector3.new(1, 0, 1)
					if along > 0 and along <= reach and side.Magnitude <= rad and math.abs(rel.Y) <= 5 then
						local l = cf:PointToObjectSpace(p)
						if math.abs(l.X) <= half.X and math.abs(l.Y) <= half.Y and math.abs(l.Z) <= half.Z then
							any = true -- the box already has it
						end
						if not bestD or along < bestD then
							best, bestD = model, along
						end
						break
					end
				end
			end
		end
		if best and not any then
			local tp = best:FindFirstChild("UpperTorso") or best:FindFirstChild("HumanoidRootPart")
			local rp = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances = { char, best, FX, workspace:FindFirstChild("NPCs") }
			local ray = workspace:Raycast(chest, tp.Position - chest, rp)
			if not ray or not ray.Instance or not ray.Instance.CanCollide then
				assist = best
			end
		end
	end
	for _, model in ipairs(bodies) do
		-- (2026-11-08) a living body that was flung and is still down is passed over (PvP.isDown): the string can't keep
		-- juggling someone lying on the ground. Corpses still take the juggle.
		if model.Parent and not PvP.isDown(model) then
			local hitPos = nil
			if model == assist then
				local tp = model:FindFirstChild("UpperTorso") or model:FindFirstChild("HumanoidRootPart")
				hitPos = tp and tp.Position
			end
			-- (2026-11-10, "hard to hit people with the normal attack when they're running") a PLAYER is also tested where it
			-- stood since this swing started, as the attacker saw it (PvP.lagOffsets), in a slightly bigger box
			local offs = PvP.lagOffsets(model, player, (PUNCH.HitDelays and PUNCH.HitDelays[combo]) or PUNCH.HitDelay)
			local hb = PvP.playerOf(model) and (half + Vector3.one * PvP.MELEE_PAD) or half
			local function inBox(pos)
				for _, off in ipairs(offs) do
					local l = cf:PointToObjectSpace(pos + off)
					if math.abs(l.X) <= hb.X and math.abs(l.Y) <= hb.Y and math.abs(l.Z) <= hb.Z then
						return true
					end
				end
				return false
			end
			local fp = PvP.formPoint(model, cf.Position) -- (2026-11-08) a giant form: its body point nearest the punch
			if fp and inBox(fp) then
				hitPos = fp
			end
			for _, n in ipairs(hitPos and {} or { "UpperTorso", "LowerTorso", "Head" }) do
				local p = model:FindFirstChild(n)
				if p and inBox(p.Position) then
					hitPos = p.Position
					break
				end
			end
			if hitPos then
				local nhum = model:FindFirstChildOfClass("Humanoid")
				local alive = nhum and nhum.Health > 0 and model:GetAttribute("Dead") ~= true
				local spin = randomUnit() * 10
				local juggle = flat * PUNCH.CorpseJuggle.X + Vector3.yAxis * PUNCH.CorpseJuggle.Y
				if alive then
					model:SetAttribute("LastHitBy", player.UserId)
					if final then
						nhum:TakeDamage(kitHit(player:GetAttribute("Kit"), nhum, fin and fin.damage or PUNCH.FinalDamage))
						local L = fin and fin.launch or PUNCH.FinalLaunch
						if RagdollService then
							local fv, fr = flat * L.X + Vector3.yAxis * L.Y, PUNCH.RagdollTime
							if not fin then -- (2026-11-09) the normal blast keeps a player within reach; launch / slam throw as before
								fv, fr = PvPBal.m1Finish(model, fv, fr)
							end
							RagdollService.Fling(model, fv, spin, fr)
						end
					else
						nhum:TakeDamage(kitHit(player:GetAttribute("Kit"), nhum, PUNCH.Damage))
						local blocked = PvP.absorbed(model) -- (2026-11-11) a blocked hit stuns nobody
						if not blocked then
							model:SetAttribute("StunnedUntil", now() + PUNCH.StunTime)
						end
						local nhrp = not blocked and model:FindFirstChild("HumanoidRootPart")
						if nhrp then
							nhrp.AssemblyLinearVelocity = flat * PUNCH.Knockback + Vector3.yAxis * 4
						end
					end
				elseif RagdollService then
					RagdollService.Fling(model, juggle, spin, nil)
				end
				if not (alive and PvP.absorbed(model)) then -- (2026-11-11) a blocked hit shows the guard spark instead (GuardFX)
					AbilityEvent:FireAllClients("PunchHit", { pos = hitPos, combo = combo, final = final, by = player.UserId,
						finisher = final and (finisher or "blast") or nil })
				end
			end
		end
	end
	PvPBal.m1End()
end

local function requestPunch(player, s, payload)
	local char, _, hrp = liveChar(player)
	if not char or s.casting then
		return
	end
	if char:GetAttribute("Blocking") then
		char:SetAttribute("Blocking", false) -- (2026-11-11) swinging drops the guard (GuardClient does too)
	end
	local t = now()
	-- 0.1 s of slack (2026-11-07): the client now sends a buffered / held swing right on the interval, and network
	-- jitter must not get it refused while the client already plays it
	if t - s.lastSwing < PUNCH.SwingInterval - 0.1 or t < s.punchLock - 0.1 then
		return
	end
	if t - s.lastSwing > PUNCH.ComboResetTime then
		s.combo = 0
	end
	s.combo = s.combo % PUNCH.ComboLength + 1
	s.lastSwing = t
	local combo = s.combo
	if combo >= PUNCH.ComboLength then
		s.punchLock = t + PUNCH.FinalCooldown
	end
	local _, flat = clampAim(payload.aimDir)
	if not flat then
		local lv = hrp.CFrame.LookVector
		flat = Vector3.new(lv.X, 0, lv.Z)
		flat = flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(0, 0, -1)
	end
	local finisher = nil
	if combo >= PUNCH.ComboLength and PUNCH.Finishers and PUNCH.Finishers[payload.finisher] then
		finisher = payload.finisher
	end
	AbilityCast:FireAllClients(player, "Punch", { combo = combo, startServerTime = t, dir = flat, finisher = finisher })
	task.delay((PUNCH.HitDelays and PUNCH.HitDelays[combo]) or PUNCH.HitDelay, resolvePunch, player, combo, flat, finisher)
end

AbilityRequest.OnServerEvent:Connect(function(player, ability, payload)
	local s = getState(player)
	if not rateOk(s) or typeof(ability) ~= "string" then
		return
	end
	if type(payload) ~= "table" then
		payload = {}
	end
	-- other kits keep the shared punch only (and not even that while morphed into a giant form)
	local kitId = player:GetAttribute("Kit")
	if kitId ~= nil and kitId ~= "Limitless" and ability ~= "Punch" then
		return
	end
	if ability == "Punch" and player.Character and (player.Character:GetAttribute("Morphed") or player.Character:GetAttribute("OwnM1")) then
		return
	end
	-- (2026-11-08) a player stunned or knocked down in PvP can't start a move (letting go of a Blue grab still works)
	if PvP.stunned(player) and not (ability == "BlueGrab" and grabs[player]) then
		if ability ~= "Punch" then
			AbilityResult:FireClient(player, ability, false, { reason = "stunned" })
		end
		return
	end
	if ability == "HollowPurple" then
		requestPurple(player, s, payload)
	elseif ability == "Punch" then
		requestPunch(player, s, payload)
	elseif ability == "BlueGrab" then
		requestBlue(player, s, payload)
	elseif ability == "Red" then
		requestRed(player, s, payload)
	elseif ability == "Domain" then
		requestDomain(player, s, payload)
	end
end)

---------------------------------------------------------------------------------------------------
-- restores (terrain chunks spread over frames, breakables on their timers)
local lastBreakCheck = 0
local lastStaleCheck = 0
RunService.Heartbeat:Connect(function()
	local n = 0
	while #restoreQueue > 0 and n < 4 do
		local key = table.remove(restoreQueue, 1)
		local c = terrainCache[key]
		if c and c.refs <= 0 then
			-- (2026-11-07, ground fix) MERGE the snapshot into the current ground: only raise cells the snapshot has fuller,
			-- so a snapshot taken while another kit's crater was open can never re-open that crater after it healed
			pcall(function()
				local okR, curM, curO = pcall(function()
					return Terrain:ReadVoxels(c.region, 4)
				end)
				if okR and curO and #curO == #c.occs then
					for x = 1, #c.occs do
						for y = 1, #c.occs[x] do
							for z = 1, #c.occs[x][y] do
								if c.occs[x][y][z] > curO[x][y][z] then
									curO[x][y][z] = c.occs[x][y][z]
									curM[x][y][z] = c.mats[x][y][z]
								end
							end
						end
					end
					Terrain:WriteVoxels(c.region, 4, curM, curO)
				else
					Terrain:WriteVoxels(c.region, 4, c.mats, c.occs)
				end
			end)
			terrainCache[key] = nil
			-- lift EVERY body (players too, not only NPCs) that the refill sealed inside the ground
			if GroundGuard and GroundGuard.liftOut then
				pcall(GroundGuard.liftOut, c.region)
			else
				liftOutOf(c.region)
			end
			n += 1
		end
	end
	local t = os.clock()
	-- a chunk still held 120 s after its last carve (a cast thread that errored before releasing it) heals anyway
	if t - (lastStaleCheck or 0) > 5 then
		lastStaleCheck = t
		for key, c in pairs(terrainCache) do
			if c.refs > 0 and c.touched and t - c.touched > 120 then
				c.refs = 0
				table.insert(restoreQueue, key)
			end
		end
	end
	if t - lastBreakCheck > 0.25 then
		lastBreakCheck = t
		for model, info in pairs(breakables) do
			if info.restoreAt and t >= info.restoreAt then
				info.restoreAt = nil
				restoreBreakable(model, info)
			end
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- PERKS (2026-11-07): the "Instant Ult" product (ShopService fires ServerStorage.PerkHooks.UltReset) clears a Limitless
-- caster's Domain Expansion cooldown and tells their bar, the same way a cast result does
task.spawn(function()
	local hooks = game:GetService("ServerStorage"):WaitForChild("PerkHooks", 30)
	local ultReset = hooks and hooks:WaitForChild("UltReset", 30)
	if not ultReset then
		warn("[Combat] PerkHooks.UltReset missing: the instant ult product does nothing for Limitless")
		return
	end
	ultReset.Event:Connect(function(player)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or not player.Parent then
			return
		end
		local kit = player:GetAttribute("Kit")
		if kit ~= nil and kit ~= "Limitless" then
			return
		end
		local s = getState(player)
		s.cd.Domain = 0
		AbilityResult:FireClient(player, "Domain", true, { cooldownEnd = 0, reset = true })
	end)
end)

print("[Combat] online")
