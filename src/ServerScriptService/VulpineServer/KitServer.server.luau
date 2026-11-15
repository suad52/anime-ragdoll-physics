--!nocheck
local PvPBal = require(game:GetService("ServerScriptService"):WaitForChild("PvP")) -- (2026-11-07) player damage/knockback balance
-- KitServer: server side of the Vulpine kit. Owns cooldowns, hit detection, damage and every ragdoll impulse
-- (BasePart:ApplyImpulse). Clients only send intents through Remotes.Request and render Remotes.Broadcast.
--   Sphere (Q) | Disc (E) | Power (R, toggle) | Morph (F: transform, then the bomb) | Release (X: end the form) |
--   Claw (M1 in form) | "SetKit" switches fighter
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")

local Kit = ReplicatedStorage:WaitForChild("VulpineKit")
local CFG = require(Kit:WaitForChild("Config"))
local Remotes = Kit:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")
local Broadcast = Remotes:WaitForChild("Broadcast")
local Knockback = Remotes:WaitForChild("Knockback")
local BeastConstruct = require(script.Parent:WaitForChild("BeastConstruct"))
local GroundFX = require(script.Parent:WaitForChild("GroundFX")) -- self-healing craters + debris rocks
-- the Tempest kit's auto-dodge: melee hits on players ask it first
local Evasion
do
	local ts = game:GetService("ServerScriptService"):WaitForChild("TempestServer", 5)
	local mod = ts and ts:FindFirstChild("Evasion")
	if mod then
		local ok, res = pcall(require, mod)
		Evasion = ok and res or nil
	end
end

-- optional hooks into the rest of the game (ragdolls for NPC bodies, NPC flee, breakable props)
local RagdollService, Threat, WorldBlast
do
	local gs = ServerScriptService:FindFirstChild("GojoServer")
	local mod = gs and gs:FindFirstChild("RagdollService")
	if mod then
		local ok, res = pcall(require, mod)
		if ok and res then
			RagdollService = res
			RagdollService.Init()
		end
	end
	Threat = gs and gs:FindFirstChild("Threat")
	WorldBlast = gs and gs:FindFirstChild("WorldBlast")
end

local FXFolder = workspace:FindFirstChild("KitFX") or Instance.new("Folder")
FXFolder.Name = "KitFX"
FXFolder.Parent = workspace

local UP = Vector3.yAxis

local function now()
	return workspace:GetServerTimeNow()
end

-- PERKS (2026-11-07, kits-A): every cooldown is base * CooldownMul (Faster Cooldowns); the ultimate - the Kurama form
-- and the moves that only exist inside it (the bomb, the claw) - also * UltChargeMul (Faster Ult Charge). Both are
-- player attributes written by ShopService only. The CRIMSON FOX skin (Skin == "Alt", read at cast time) recolours
-- the visuals built here: Power Mode's eyes/aura and the nine-tailed construct (Config.AltSkin).
-- (2026-11-08) non-ultimate moves x PvPShared.Balance.NON_ULT_COOLDOWN_MUL ("double the cooldown on non ult abilities")
local BAL = require(game:GetService("ReplicatedStorage"):WaitForChild("PvPShared"):WaitForChild("Balance"))
local function cdScale(p, isUlt)
	local m = tonumber(p:GetAttribute("CooldownMul")) or 1
	if isUlt then
		m *= tonumber(p:GetAttribute("UltChargeMul")) or 1
	end
	if m ~= m or m <= 0 then
		m = 1
	end
	return math.clamp(m, 0.05, 4) * (isUlt and 1 or BAL.NON_ULT_COOLDOWN_MUL)
end
local SkinTint, AltSkin, beastMap
do
	local okT, t = pcall(function()
		return require(ReplicatedStorage:WaitForChild("GojoShared", 10):WaitForChild("SkinTint", 10))
	end)
	local okA, a = pcall(function()
		return require(Kit:WaitForChild("Config"):WaitForChild("AltSkin", 10))
	end)
	if okT and okA and type(t) == "table" and type(a) == "table" then
		SkinTint, AltSkin = t, a
		beastMap = t.mapper(a.Beast)
	else
		warn("[KitServer] CRIMSON FOX skin unavailable: " .. tostring(not okT and t or a))
	end
end
local function altSkin(p)
	return AltSkin ~= nil and p:GetAttribute("Skin") == "Alt"
end

local function randomUnit()
	local v = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	return v.Magnitude > 1e-3 and v.Unit or Vector3.xAxis
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

local function flatOf(v, fallback)
	local f = typeof(v) == "Vector3" and Vector3.new(v.X, 0, v.Z) or Vector3.zero
	return f.Magnitude > 1e-3 and f.Unit or fallback
end

-- (aim, flat): the client's camera direction with the pitch clamped to +-40 degrees
local function aimOf(payload, hrp)
	local look = flatOf(hrp.CFrame.LookVector, Vector3.new(0, 0, -1))
	local v = payload.aim
	if typeof(v) ~= "Vector3" or v ~= v or v.Magnitude < 1e-3 then
		return look, look
	end
	local flat = flatOf(v, look)
	local pitch = math.clamp(math.asin(math.clamp(v.Unit.Y, -1, 1)), math.rad(-40), math.rad(40))
	return (flat * math.cos(pitch) + UP * math.sin(pitch)).Unit, flat
end

-- a world point the client says its cursor is on (nil if it is not a sane position)
local function validTarget(v)
	if typeof(v) ~= "Vector3" or v ~= v or math.abs(v.X) > 1e5 or math.abs(v.Y) > 1e5 or math.abs(v.Z) > 1e5 then
		return nil
	end
	return v
end

local function segDist(p, a, b)
	local ab = b - a
	local len2 = ab:Dot(ab)
	local t = len2 > 1e-6 and math.clamp((p - a):Dot(ab) / len2, 0, 1) or 0
	return (p - (a + ab * t)).Magnitude, a + ab * t
end

---------------------------------------------------------------------------------------------------
-- player state
local state = {}
local function getState(p)
	local s = state[p]
	if not s then
		s = { cd = {}, busy = 0, reqs = {}, power = nil, morph = nil, base = nil, token = 0 }
		state[p] = s
	end
	return s
end

local function rateOk(s)
	local t = os.clock()
	while #s.reqs > 0 and t - s.reqs[1] > 1 do
		table.remove(s.reqs, 1)
	end
	if #s.reqs >= 15 then
		return false
	end
	table.insert(s.reqs, t)
	return true
end

local function fire(kind, data)
	Broadcast:FireAllClients(kind, data)
end

local function sendCooldown(p, s, skill)
	Broadcast:FireClient(p, "Cooldown", { skill = skill, ends = s.cd[skill] or 0 })
end

local castId = 0
local function nextId()
	castId += 1
	return castId
end

-- walk / jump = the values captured at spawn, times the power-mode and morph multipliers
local function applyMovement(p, s)
	local char, hum = liveChar(p)
	if not char or not s.base then
		return
	end
	local ws, jp, jh = s.base.ws, s.base.jp, s.base.jh
	if s.power and s.power.char == char then
		ws *= CFG.Power.WalkSpeedMul
		jp *= CFG.Power.JumpPowerMul
		jh *= CFG.Power.JumpPowerMul ^ 2 -- same take-off speed as a JumpPower x mul jump
	end
	if s.morph and s.morph.char == char and s.morph.grown then
		ws *= CFG.Morph.Scale * CFG.Morph.WalkSpeedPerScale
		jh *= CFG.Morph.JumpHeightMul
		jp *= math.sqrt(CFG.Morph.JumpHeightMul)
	end
	hum.WalkSpeed, hum.JumpPower, hum.JumpHeight = ws, jp, jh
	char:SetAttribute("KitWalkSpeed", ws)
end

---------------------------------------------------------------------------------------------------
-- targets and impulses
local function rootOf(model)
	-- (2026-11-08) a player in a giant form answers at the point of its whole body nearest the attack (PvP.formRoot)
	return PvPBal.formRoot(model) or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

-- every ragdollable body except the caster: tagged NPCs plus (optionally) other players
local function enemies(caster)
	PvPBal.setAim(caster) -- (2026-11-08) forms are hit at their body point nearest this attacker
	local list = {}
	for _, m in ipairs(CollectionService:GetTagged(CFG.TargetTag)) do
		if m.Parent and rootOf(m) then
			table.insert(list, m)
		end
	end
	if CFG.AffectPlayers then
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl ~= caster and liveChar(pl) then
				table.insert(list, pl.Character)
			end
		end
	end
	return list
end

local function knockMul(attacker)
	local s = state[attacker]
	return (s and s.power and s.power.char == attacker.Character) and CFG.Power.KnockbackMul or 1
end

-- hit feedback: damage dealt this frame is batched and broadcast once; clients pop numbers and confirm the hit
local hitBatch = {}
local function recordHit(attacker, model, amount)
	local r = rootOf(model)
	if r and amount and amount >= 0.5 and #hitBatch < 60 then
		table.insert(hitBatch, { u = attacker.UserId, p = r.Position, d = amount, big = amount >= 35 })
	end
end
RunService.Heartbeat:Connect(function()
	if #hitBatch > 0 then
		local list = hitBatch
		hitBatch = {}
		Broadcast:FireAllClients("Hits", list)
	end
end)

-- one ApplyImpulse per assembly so every body part ends up moving at roughly `vel` (constraint rigs are one
-- assembly per limb). `keep` = how much of the current velocity survives (0.5 lets repeated pulls stack gently)
local function impulseModel(model, vel, spin, keep)
	local done = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and not part.Anchored then
			local root = part.AssemblyRootPart
			if root and not root.Anchored and not done[root] then
				done[root] = true
				local m = root.AssemblyMass
				root:ApplyImpulse((vel - root.AssemblyLinearVelocity * (1 - (keep or 0))) * m)
				if spin then
					root:ApplyAngularImpulse(spin * m)
				end
			end
		end
	end
end

-- damage + ragdoll + impulse on one body. Players are tumbled by their own client (it owns their physics).
local function knock(attacker, model, vel, ragTime, damage, keep)
	vel *= knockMul(attacker)
	if vel.Magnitude > 320 then
		vel = vel.Unit * 320
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if damage and damage > 0 and hum and hum.Health > 0 then
		model:SetAttribute("LastHitBy", attacker.UserId)
		hum:TakeDamage(PvPBal.dmg(hum, damage))
		recordHit(attacker, model, damage)
	end
	if PvPBal.absorbed and PvPBal.absorbed(model) then
		return -- (2026-11-11) blocked / dodged (ServerScriptService.PvP, BLOCK): no tumble, no fling
	end
	local victim = Players:GetPlayerFromCharacter(model)
	if victim then
		if model:GetAttribute("Morphed") then
			vel *= 0.15 -- a giant barely budges
		end
		local rag = math.min(ragTime or 2, CFG.PlayerRagdollMax)
		PvPBal.markDown(model, rag) -- (2026-11-08) the server's clock for "lying on the ground" (M1 strings skip it)
		Knockback:FireClient(victim, vel * PvPBal.knockMul(), rag, keep or 0)
		return
	end
	if RagdollService then
		RagdollService.Ragdoll(model, ragTime)
	end
	impulseModel(model, vel, randomUnit() * 6, keep)
end

local looseParams = OverlapParams.new()
looseParams.FilterType = Enum.RaycastFilterType.Exclude

-- loose physics props get the same treatment (sign = -1 pulls inward)
local function pushLoose(pos, radius, speed, upBias, sign)
	local ignore = { FXFolder }
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	for _, m in ipairs(CollectionService:GetTagged(CFG.TargetTag)) do
		table.insert(ignore, m)
	end
	looseParams.FilterDescendantsInstances = ignore
	local done = {}
	for _, part in ipairs(workspace:GetPartBoundsInRadius(pos, radius, looseParams)) do
		local root = part.AssemblyRootPart
		if root and not root.Anchored and not done[root] then
			done[root] = true
			local off = root.Position - pos
			local k = math.clamp(1 - off.Magnitude / radius, 0, 1)
			local dir = ((off.Magnitude > 0.5 and off.Unit or UP) * (sign or 1) + UP * upBias).Unit
			pcall(function()
				root:ApplyImpulse(dir * speed * 0.6 * k * root.AssemblyMass)
			end)
		end
	end
end

local function worldHooks(p, pos, radius)
	if WorldBlast then
		WorldBlast:Fire(pos, radius, p.UserId)
	end
	if Threat then
		Threat:Fire(pos, radius * 2, 2)
	end
end

-- everything within `radius` is thrown straight out from `pos`, harder the closer it was
local function radialBlast(p, pos, radius, speed, upBias, damage, ragTime, minK)
	for _, m in ipairs(enemies(p)) do
		PvPBal.aimAt(pos) -- (2026-11-10) a form answers at its body point nearest the blast, not the caster
		local off = rootOf(m).Position - pos
		local d = off.Magnitude
		if d <= radius then
			local k = 1 - d / radius
			local dir = ((d > 0.5 and off.Unit or randomUnit()) + UP * upBias).Unit
			knock(p, m, dir * speed * ((minK or 0.35) + (1 - (minK or 0.35)) * k), ragTime, damage * k)
		end
	end
	pushLoose(pos, radius, speed, upBias, 1)
	worldHooks(p, pos, radius * 0.6)
end

-- common gate: alive, not mid-move, off cooldown
local function gate(p, s, skill)
	local char, hum, hrp = liveChar(p)
	if not char or os.clock() < s.busy then
		return nil
	end
	if PvPBal.stunned(p) then -- (2026-11-08) stunned / knocked down in PvP: no moves
		return nil
	end
	local t = now()
	if t < (s.cd[skill] or 0) then
		sendCooldown(p, s, skill)
		return nil
	end
	return char, hum, hrp, t
end

---------------------------------------------------------------------------------------------------
-- Skill 1: Energy Sphere. The caster's client anchors itself while the sphere grows, then thrusts forward
-- LaunchDistance studs; here we watch the front of the caster for an enemy root part during the thrust.
local function castSphere(p, s, payload)
	local char, _, hrp, t = gate(p, s, "Sphere")
	if not char then
		return
	end
	local S = CFG.Sphere
	local _, flat = aimOf(payload, hrp)
	local morphed = s.morph and s.morph.char == char
	s.cd.Sphere = t + S.Cooldown * cdScale(p, false)
	s.busy = os.clock() + S.AnchorTime + S.LaunchTime + 0.3
	sendCooldown(p, s, "Sphere")
	local id = nextId()
	fire("SphereCharge", {
		id = id, userId = p.UserId, dir = flat, anchor = S.AnchorTime, launch = S.LaunchTime,
		distance = S.LaunchDistance, size = S.SphereSize * (morphed and CFG.Morph.Scale or 1),
	})
	task.spawn(function()
		task.wait(S.AnchorTime)
		if liveChar(p) ~= char then
			fire("SphereEnd", { id = id })
			return
		end
		local t0 = os.clock()
		while os.clock() - t0 < S.LaunchTime + 0.2 do
			local c2, _, h2 = liveChar(p)
			if c2 ~= char then
				break
			end
			local front = h2.Position + flat * 2.5
			local best, bestD
			for _, m in ipairs(enemies(p)) do
				local d = (rootOf(m).Position - front).Magnitude
				if d <= S.HitRadius and (not bestD or d < bestD) then
					best, bestD = m, d
				end
			end
			if best then
				-- localized AOE around the struck body; the struck body itself takes the full thrust
				local center = rootOf(best).Position
				for _, m in ipairs(enemies(p)) do
					PvPBal.aimAt(center) -- (2026-11-10) forms: nearest the impact
					local off = rootOf(m).Position - center
					local d = off.Magnitude
					if m == best then
						local dodgedIt = Evasion and Players:GetPlayerFromCharacter(m) and Evasion.tryEvade(m, char)
						if not dodgedIt then
							knock(p, m, flat * S.Impulse + UP * S.UpImpulse, S.RagdollTime, S.Damage)
						end
					elseif d <= S.HitRadius then
						local k = 1 - d / S.HitRadius
						local dir = ((d > 0.5 and off.Unit or flat) + flat * 0.5 + UP * 0.4).Unit
						knock(p, m, dir * S.Impulse * 0.55 * (0.4 + 0.6 * k), S.RagdollTime, S.Damage * 0.5 * k)
					end
				end
				pushLoose(center, S.HitRadius * 1.5, S.Impulse, 0.4, 1)
				GroundFX.impact(center, 6, 8, S.Impulse * 0.35)
				worldHooks(p, center, S.HitRadius * 0.6)
				fire("SphereImpact", { id = id, userId = p.UserId, pos = center, dir = flat })
				return
			end
			RunService.Heartbeat:Wait()
		end
		fire("SphereEnd", { id = id })
	end)
end

---------------------------------------------------------------------------------------------------
-- Skill 2: Expanding Vortex Disc. Channel, then a physical (gravity-cancelled) carrier part is launched with
-- AssemblyLinearVelocity; on the first surface or body it swells into a vortex that drags bodies in, then detonates.
local discRay = RaycastParams.new()
discRay.FilterType = Enum.RaycastFilterType.Exclude

local function runVortex(p, id, pos)
	local D = CFG.Disc
	fire("DiscImpact", { id = id, userId = p.UserId, pos = pos, radius = D.VortexRadius, time = D.VortexTime, size = D.DiscSize, expand = D.ExpandScale })
	worldHooks(p, pos, D.VortexRadius * 0.4)
	GroundFX.impact(pos, 5, 6, 30)
	local ticks = math.max(1, math.floor(D.VortexTime / D.Tick))
	local tickDamage = D.Damage * 0.5 / ticks
	for tick = 1, ticks do
		for _, m in ipairs(enemies(p)) do
			PvPBal.aimAt(pos) -- (2026-11-10) forms: nearest the vortex
			local off = rootOf(m).Position - pos
			local d = off.Magnitude
			if d <= D.VortexRadius * 1.1 then
				local inward = d > 0.5 and -off.Unit or Vector3.zero
				local tangent = UP:Cross(off)
				tangent = tangent.Magnitude > 0.1 and tangent.Unit or randomUnit()
				local v = inward * math.min(D.PullSpeed, d * 4) + tangent * D.SwirlSpeed + UP * (3 + math.random() * 5)
				knock(p, m, v, D.RagdollTime, tickDamage, 0.5)
			end
		end
		if tick % 4 == 0 then
			GroundFX.ring(pos, D.VortexRadius * 0.8, 3, 22) -- the vortex tears chunks out of the ground and sucks them in
		end
		pushLoose(pos, D.VortexRadius, D.PullSpeed, 0.15, -1)
		task.wait(D.Tick)
	end
	fire("DiscDetonate", { id = id, userId = p.UserId, pos = pos, radius = D.VortexRadius })
	radialBlast(p, pos, D.VortexRadius * 1.3, D.ExplosionImpulse, D.ExplosionUpBias, D.Damage * 0.5, D.RagdollTime)
	GroundFX.impact(pos, 11, 16, 70)
end

local function castDisc(p, s, payload)
	local char, _, hrp, t = gate(p, s, "Disc")
	if not char then
		return
	end
	local D = CFG.Disc
	local aim, flat = aimOf(payload, hrp)
	-- the throw goes wherever the cursor is when the channel ends; the client updates this with "DiscAim"
	s.discAim = { id = nil, target = validTarget(payload.target) }
	s.cd.Disc = t + D.Cooldown * cdScale(p, false)
	s.busy = os.clock() + D.ChannelTime + 0.3
	sendCooldown(p, s, "Disc")
	local id = nextId()
	s.discAim.id = id
	fire("DiscChannel", { id = id, userId = p.UserId, time = D.ChannelTime, size = D.DiscSize, dir = flat })
	task.spawn(function()
		task.wait(D.ChannelTime)
		local c2, _, h2 = liveChar(p)
		if c2 ~= char then
			fire("DiscCancel", { id = id })
			return
		end
		local carrier = Instance.new("Part")
		carrier.Name = "VortexDisc"
		carrier.Shape = Enum.PartType.Ball
		carrier.Size = Vector3.one * D.DiscSize * 0.5
		carrier.Transparency = 1
		carrier.CanCollide = false
		carrier.CanTouch = false
		carrier.CanQuery = false
		-- aim from the disc's launch point straight at the cursor's latest world point
		local origin = h2.Position + UP * 2.5
		local target = s.discAim and s.discAim.id == id and s.discAim.target
		if target and (target - origin).Magnitude > 4 then
			aim = (target - origin).Unit
			flat = flatOf(aim, flat)
		end
		carrier.CFrame = CFrame.new(origin + flat * 3)
		carrier:SetAttribute("DiscId", id)
		local att = Instance.new("Attachment")
		att.Parent = carrier
		local antiGravity = Instance.new("VectorForce")
		antiGravity.Attachment0 = att
		antiGravity.RelativeTo = Enum.ActuatorRelativeTo.World
		antiGravity.ApplyAtCenterOfMass = true
		antiGravity.Force = UP * carrier:GetMass() * workspace.Gravity
		antiGravity.Parent = carrier
		carrier.Parent = FXFolder
		pcall(function()
			carrier:SetNetworkOwner(nil)
		end)
		carrier.AssemblyLinearVelocity = aim * D.Speed
		fire("DiscLaunch", { id = id, userId = p.UserId, carrier = carrier, dir = aim })

		-- sweep the path each frame: raycast for surfaces/bodies, distance check for root parts
		local ignore = { FXFolder, GroundFX.folder, char }
		for _, f in ipairs({ "FX", "LocalFX" }) do
			if workspace:FindFirstChild(f) then
				table.insert(ignore, workspace[f])
			end
		end
		discRay.FilterDescendantsInstances = ignore
		local prev, travelled, hitPos = carrier.Position, 0, nil
		local radius = D.DiscSize * 0.5
		while carrier.Parent do
			local dt = RunService.Heartbeat:Wait()
			local cur = carrier.Position
			local seg = cur - prev
			if seg.Magnitude > 1e-3 then
				local res = workspace:Raycast(prev, seg + seg.Unit * radius, discRay)
				if res then
					hitPos = res.Position - seg.Unit * 1.5
				else
					for _, m in ipairs(enemies(p)) do
						PvPBal.aimSeg(m, prev, cur) -- (2026-11-10) forms: nearest the disc's path
						local d, closest = segDist(rootOf(m).Position, prev, cur)
						if d <= radius + 2 then
							hitPos = closest
							break
						end
					end
				end
				travelled += seg.Magnitude
			end
			if hitPos or travelled >= D.Range then
				hitPos = hitPos or cur
				break
			end
			-- steering: turn the velocity toward the caster's latest cursor point, at most TurnRate deg/s
			local tgt = s.discAim and s.discAim.id == id and s.discAim.target
			if tgt and (tgt - cur).Magnitude > 4 then
				local vel = carrier.AssemblyLinearVelocity
				local dirNow = vel.Magnitude > 1 and vel.Unit or aim
				local want = (tgt - cur).Unit
				local ang = math.acos(math.clamp(dirNow:Dot(want), -1, 1))
				local maxTurn = math.rad(D.TurnRate) * dt
				local newDir = want
				if ang > maxTurn then
					local axis = dirNow:Cross(want)
					if axis.Magnitude < 1e-4 then
						axis = dirNow:Cross(UP).Magnitude > 1e-4 and dirNow:Cross(UP) or Vector3.xAxis
					end
					newDir = CFrame.fromAxisAngle(axis.Unit, maxTurn):VectorToWorldSpace(dirNow)
				end
				carrier.AssemblyLinearVelocity = newDir * D.Speed
			end
			prev = cur
		end
		carrier.Anchored = true
		carrier.CFrame = CFrame.new(hitPos)
		Debris:AddItem(carrier, D.VortexTime + 1)
		runVortex(p, id, hitPos)
	end)
end

---------------------------------------------------------------------------------------------------
-- Skill 3: Enhanced Power Mode (toggle). Visual parts live in a folder inside the character so every client
-- sees them; the caster's client adds the enemy-sense outlines locally.
local function endPower(p, s, quiet)
	local pw = s.power
	if not pw then
		return
	end
	s.power = nil
	if pw.folder then
		pw.folder:Destroy()
	end
	if pw.char.Parent then
		pw.char:SetAttribute("PowerMode", false)
	end
	s.cd.Power = now() + CFG.Power.Cooldown * cdScale(p, false)
	sendCooldown(p, s, "Power")
	applyMovement(p, s)
	if not quiet then
		fire("PowerOff", { userId = p.UserId })
	end
end

local function buildPowerVisuals(char, pal)
	local P = pal or CFG.Palette
	local head = char:FindFirstChild("Head")
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	local folder = Instance.new("Folder")
	folder.Name = "PowerModeFX"
	if head then
		local s = head.Size
		for _, side in ipairs({ -1, 1 }) do
			-- glowing eye overlay welded onto the face
			local eye = Instance.new("Part")
			eye.Name = "GlowEye"
			eye.Material = Enum.Material.Neon
			eye.Color = P.PowerEye
			eye.Size = Vector3.new(0.26, 0.11, 0.05) * (s.Y / 1.2)
			eye.CanCollide, eye.CanQuery, eye.CanTouch, eye.Massless, eye.CastShadow = false, false, false, true, false
			local c0 = CFrame.new(0.2 * s.X * side, 0.08 * s.Y, -0.5 * s.Z - 0.01) * CFrame.Angles(0, 0, math.rad(10 * side))
			eye.CFrame = head.CFrame * c0
			local w = Instance.new("Weld")
			w.Part0, w.Part1, w.C0 = head, eye, c0
			w.Parent = eye
			-- eye trail: two attachments across the eye streak light behind fast moves
			local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
			a0.Position, a1.Position = Vector3.new(0, 0.05, 0), Vector3.new(0, -0.05, 0)
			a0.Parent, a1.Parent = eye, eye
			local trail = Instance.new("Trail")
			trail.Attachment0, trail.Attachment1 = a0, a1
			trail.Color = ColorSequence.new(P.PowerEye)
			trail.Transparency = NumberSequence.new(0, 1)
			trail.Lifetime = 0.3
			trail.LightEmission = 1
			trail.FaceCamera = true
			trail.WidthScale = NumberSequence.new(1, 0)
			trail.Parent = eye
			eye.Parent = folder
		end
		if CFG.Power.MarkingDecal ~= "" then
			local decal = Instance.new("Decal")
			decal.Name = "PowerMarkings"
			decal.Face = Enum.NormalId.Front
			decal.Texture = CFG.Power.MarkingDecal
			decal.Parent = head
			local tag = Instance.new("ObjectValue")
			tag.Name = "DecalRef"
			tag.Value = decal
			tag.Parent = folder
		end
	end
	if torso then
		local att = Instance.new("Attachment")
		att.Name = "PowerAura"
		att.Parent = torso
		local tag = Instance.new("ObjectValue")
		tag.Name = "AttachmentRef"
		tag.Value = att
		tag.Parent = folder
		local embers = Instance.new("ParticleEmitter")
		embers.Name = "Embers"
		embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		embers.Color = ColorSequence.new(P.PowerAura, P.PowerEmber)
		embers.LightEmission = 1
		embers.LightInfluence = 0
		embers.Rate = 18
		embers.Lifetime = NumberRange.new(0.9, 1.6)
		embers.Speed = NumberRange.new(0.5, 2)
		embers.SpreadAngle = Vector2.new(180, 180)
		embers.Acceleration = Vector3.new(0, 3, 0)
		embers.Size = NumberSequence.new(0.35, 0)
		embers.Parent = att
		local aura = Instance.new("ParticleEmitter")
		aura.Name = "Aura"
		aura.Texture = "rbxasset://textures/particles/fire_main.dds"
		aura.Color = ColorSequence.new(P.PowerAura, P.PowerEmber)
		aura.LightEmission = 0.8
		aura.LightInfluence = 0
		aura.Rate = 22
		aura.Lifetime = NumberRange.new(0.4, 0.7)
		aura.Speed = NumberRange.new(1, 3)
		aura.Acceleration = Vector3.new(0, 7, 0)
		aura.Size = NumberSequence.new(1.4, 0)
		aura.Transparency = NumberSequence.new(0.5, 1)
		aura.Parent = att
		local glow = Instance.new("PointLight")
		glow.Color = P.PowerEmber
		glow.Range = 10
		glow.Brightness = 1.5
		glow.Shadows = false
		glow.Parent = att
	end
	folder.Parent = char
	-- the attachment and decal live on body parts; destroying the folder must take them too
	folder.Destroying:Connect(function()
		for _, ref in ipairs(folder:GetChildren()) do
			if ref:IsA("ObjectValue") and ref.Value then
				ref.Value:Destroy()
			end
		end
	end)
	return folder
end

local function togglePower(p, s)
	if s.power then
		endPower(p, s)
		return
	end
	local char, _, hrp, t = gate(p, s, "Power")
	if not char then
		return
	end
	local P = CFG.Power
	s.power = { char = char, untilT = t + P.Duration, folder = buildPowerVisuals(char, altSkin(p) and AltSkin.Palette or nil) }
	char:SetAttribute("PowerUntil", s.power.untilT)
	char:SetAttribute("PowerMode", true)
	applyMovement(p, s)
	fire("PowerOn", { userId = p.UserId, pos = hrp.Position, radius = P.SenseRadius })
	GroundFX.ring(hrp.Position, 6, 9, 16) -- the power-up lifts pebbles off the ground
end

---------------------------------------------------------------------------------------------------
-- Skill 4: Spectral Beast morph (toggle). Shockwave on trigger, then the rig + hitboxes are scaled smoothly with
-- Model:ScaleTo, the body is hidden and the construct is welded on. Clients raise the camera and shake on footsteps.

-- scales the character a little every frame; lifts it as it grows so the longer legs don't sink into the ground,
-- and lowers it as it shrinks so the shorter legs don't leave it dropping from the giant's hip height
local function smoothScale(char, hum, from, to, duration)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end
	local groundPerScale = (hum.HipHeight + hrp.Size.Y / 2) / from
	local t0, cur = os.clock(), from
	while true do
		local a = math.clamp((os.clock() - t0) / duration, 0, 1)
		local sc = from + (to - from) * (a * a * (3 - 2 * a))
		local ok, err = pcall(function()
			char:ScaleTo(sc)
			if sc ~= cur then
				char:PivotTo(char:GetPivot() + UP * (sc - cur) * groundPerScale)
			end
		end)
		if not ok then
			warn("[KitServer] ScaleTo failed: " .. tostring(err))
			return false
		end
		cur = sc
		if a >= 1 then
			return true
		end
		RunService.Heartbeat:Wait()
		if not char.Parent then
			return false
		end
	end
end

local function hideBody(m)
	m.hidden = {}
	for _, d in ipairs(m.char:GetDescendants()) do
		if (d:IsA("BasePart") or d:IsA("Decal")) and d.Transparency < 1 then
			m.hidden[d] = d.Transparency
			d.Transparency = 1
		end
	end
end

local function showBody(m)
	for inst, tr in pairs(m.hidden or {}) do
		if inst.Parent then
			inst.Transparency = tr
		end
	end
	m.hidden = nil
end

-- the one exit for the form (time up, X / the RELEASE chip, a kit switch, death): the construct dissolves, the rig
-- shrinks back to 1 with the body still hidden (no giant human on screen), then the body reappears; every form
-- attribute is cleared and the normal cooldown starts
local function endMorph(p, s, quiet)
	local m = s.morph
	if not m then
		return
	end
	s.morph = nil
	s.token += 1
	if m.model then
		m.model:Destroy()
	end
	if m.shield and m.shield.Parent then
		m.shield:Destroy()
	end
	local char = m.char
	if char.Parent then
		char:SetAttribute("Morphed", nil)
		char:SetAttribute("MorphUntil", nil)
		char:SetAttribute("MorphReadyAt", nil)
	end
	if s.ultFree then
		s.ultFree = nil -- an instant ult was bought while the form stood: this time no cooldown starts
		s.cd.Morph = 0
	else
		s.cd.Morph = now() + CFG.Morph.Cooldown * cdScale(p, true)
	end
	sendCooldown(p, s, "Morph")
	local c2, hum, hrp = liveChar(p)
	if c2 == char then
		s.busy = os.clock() + CFG.Morph.GrowTime + 0.2
		if not quiet then
			fire("MorphEnd", { userId = p.UserId, pos = hrp.Position, scale = char:GetScale() })
		end
		task.spawn(function()
			if char:GetScale() ~= 1 then
				smoothScale(char, hum, char:GetScale(), 1, CFG.Morph.GrowTime)
			end
			showBody(m)
			applyMovement(p, s)
		end)
	else
		showBody(m)
	end
	applyMovement(p, s)
end

-- X / the RELEASE chip: only once the form is fully up (its entrance and opening bomb have played)
local function releaseMorph(p, s)
	local m = s.morph
	if not m or not m.grown or os.clock() < (m.releaseAt or 0) or liveChar(p) ~= m.char then
		return
	end
	endMorph(p, s)
end

-- a brief invisible force field: the entrance cinematic can't be interrupted by damage
local function ffOn(char)
	local ff = Instance.new("ForceField")
	ff.Name = "UltimateShield"
	ff.Visible = false
	ff.Parent = char
	return ff
end

---------------------------------------------------------------------------------------------------
-- the form's signature move: the Tailed Beast Bomb. Charged in the beast's mouth (the caster's client reports the
-- cursor just before the charge ends, like the disc), then flown in a straight line, shoving aside whatever it
-- brushes, and detonated on the first surface or body. The clients simulate the same line, so it looks smooth.
local bombRay = RaycastParams.new()
bombRay.FilterType = Enum.RaycastFilterType.Exclude

local function detonateBomb(p, id, pos)
	local B = CFG.Bomb
	fire("BombHit", { id = id, userId = p.UserId, pos = pos, radius = B.BlastRadius })
	radialBlast(p, pos, B.BlastRadius, B.Impulse, B.UpBias, B.Damage, B.RagdollTime, 0.4)
	worldHooks(p, pos, B.BlastRadius * 0.5)
	GroundFX.impact(pos, 15, 24, 120)
	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2 + math.random() * 0.5
		GroundFX.impact(pos + Vector3.new(math.cos(a), 0, math.sin(a)) * (24 + math.random() * 6), 5.5, 3, 80)
	end
end

local function flyBomb(p, id, origin, dir)
	local B = CFG.Bomb
	fire("BombLaunch", { id = id, userId = p.UserId, origin = origin, dir = dir, speed = B.Speed, size = B.Size })
	local ignore = { FXFolder, GroundFX.folder }
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	for _, m in ipairs(CollectionService:GetTagged(CFG.TargetTag)) do
		table.insert(ignore, m)
	end
	local pos, travelled, hitPos = origin, 0, nil
	local brushed = {}
	while travelled < B.Range and not hitPos do
		local dt = math.min(RunService.Heartbeat:Wait(), 0.1)
		local step = B.Speed * dt
		bombRay.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(pos, dir * (step + B.Size * 0.4), bombRay)
		if hit then
			hitPos = hit.Position - dir * 2
			break
		end
		local nextPos = pos + dir * step
		for _, m in ipairs(enemies(p)) do
			PvPBal.aimSeg(m, pos, nextPos) -- (2026-11-10) forms: nearest the bomb's path
			local r = rootOf(m)
			local d, closest = segDist(r.Position, pos, nextPos)
			if d <= B.SweepRadius then
				hitPos = closest
				break
			elseif d <= B.BrushRadius and not brushed[m] then
				brushed[m] = true
				local side = (r.Position - closest) * Vector3.new(1, 0, 1)
				side = side.Magnitude > 0.5 and side.Unit or randomUnit()
				knock(p, m, (side + UP * 0.5).Unit * 70, 1.8, 0)
			end
		end
		pos = nextPos
		travelled += step
	end
	detonateBomb(p, id, hitPos or pos)
end

local function castBomb(p, s, payload, auto)
	if auto then
		s.busy = 0 -- the entrance's own guard
	end
	local char, _, hrp, t = gate(p, s, "Bomb")
	if not char or not (auto or (s.morph and s.morph.grown)) then
		return
	end
	local B = CFG.Bomb
	local charge = auto and B.AutoChargeTime or B.ChargeTime
	local id = nextId()
	s.cd.Bomb = t + B.Cooldown * cdScale(p, true) + charge
	sendCooldown(p, s, "Bomb")
	s.busy = os.clock() + charge + 0.5
	local target = validTarget(type(payload) == "table" and payload.target or nil)
	s.discAim = { id = id, target = target }
	fire("BombCharge", { id = id, userId = p.UserId, time = charge, size = CFG.Bomb.Size })
	task.delay(charge, function()
		local c2, _, h2 = liveChar(p)
		if c2 ~= char or not s.morph then
			fire("BombCancel", { id = id })
			return
		end
		local model = s.morph.model
		local nose = model and model:FindFirstChild("Nose", true)
		local look = flatOf(h2.CFrame.LookVector, Vector3.new(0, 0, -1))
		local origin = (nose and nose.Parent) and nose.Position or (h2.Position + look * 12 + UP * 8)
		local aim = s.discAim and s.discAim.id == id and s.discAim.target or target
		local dir = look
		if aim and (aim - origin).Magnitude > 6 then
			dir = (aim - origin).Unit
		end
		s.discAim = nil
		flyBomb(p, id, origin, dir)
	end)
end

---------------------------------------------------------------------------------------------------
-- M1 in form: a rearing three-claw swipe; the cone in front is struck and three furrows rake the ground
local function castClaw(p, s, payload)
	if not (s.morph and s.morph.grown) then
		return
	end
	local char, _, hrp, t = gate(p, s, "Claw")
	if not char then
		return
	end
	local C = CFG.Claw
	s.cd.Claw = t + C.Cooldown * cdScale(p, true)
	s.clawSide = -(s.clawSide or -1)
	local side = s.clawSide
	local _, flat = aimOf(payload, hrp)
	fire("ClawStart", { userId = p.UserId, side = side, windup = C.Windup, dir = flat })
	task.delay(C.Windup, function()
		local c2, _, h2 = liveChar(p)
		if c2 ~= char or not s.morph then
			return
		end
		-- the cone is measured from the beast's root (its shoulders), so it reaches past the snout to where the paw
		-- visibly rakes; anything under the chest is struck whatever the angle
		local origin = h2.Position
		local across = flat:Cross(UP) * side
		local half = math.rad(C.Arc / 2)
		local inner = C.Inner or 5
		for _, m in ipairs(enemies(p)) do
			local off = (rootOf(m).Position - origin) * Vector3.new(1, 0, 1)
			local d = off.Magnitude
			if d <= C.Range and (d < inner or math.acos(math.clamp(off.Unit:Dot(flat), -1, 1)) <= half) then
				local k = 1 - d / C.Range
				knock(p, m, (flat * 0.8 + across * 0.45 + UP * 0.5).Unit * C.Impulse * (0.6 + 0.4 * k), 3.5, C.Damage * (0.5 + 0.5 * k))
			end
		end
		-- two craters per furrow (was one every 11 studs: up to nine terrain carves per swipe)
		local start = C.FissureStart or 10
		for _, ang in ipairs({ -0.5, 0, 0.5 }) do
			local dd = CFrame.fromAxisAngle(UP, ang):VectorToWorldSpace(flat)
			for _, dist in ipairs({ start + (C.FissureLength - start) * 0.4, C.FissureLength }) do
				GroundFX.impact(origin + dd * dist, 2.6 + dist * 0.03, 1, 40)
			end
		end
		local mid = origin + flat * (C.Range * 0.55)
		pushLoose(mid, C.Range * 0.45, C.Impulse, 0.4, 1)
		worldHooks(p, mid, 16)
		fire("Claw", { userId = p.UserId, side = side, origin = origin, dir = flat, range = C.Range, arc = C.Arc, fissure = C.FissureLength, start = start })
	end)
end

---------------------------------------------------------------------------------------------------
-- the transformation. A cinematic entrance: the caster floats up while chakra gathers (1.3 s), then the form bursts
-- out -- a shockwave, a ring of craters, the rig scaling up with the construct appearing -- and the beast finishes
-- by spitting a Tailed Beast Bomb. Pressing the key again while in form fires another bomb.
local function toggleMorph(p, s, payload)
	if s.morph then
		if s.morph.grown then
			castBomb(p, s, payload, false)
		end
		return
	end
	local char, hum, hrp, t = gate(p, s, "Morph")
	if not char then
		return
	end
	local M, B = CFG.Morph, CFG.Bomb
	s.token += 1
	local tok = s.token
	s.busy = os.clock() + M.GatherTime + M.GrowTime + 0.5 + B.AutoChargeTime + 1
	s.morph = { char = char, untilT = math.huge, grown = false }
	char:SetAttribute("Morphed", true)
	local shield = ffOn(char)
	s.morph.shield = shield
	local base = hrp.CFrame
	local function alive()
		return s.token == tok and s.morph ~= nil and liveChar(p) == char
	end
	fire("MorphStart", { userId = p.UserId, pos = base.Position, gather = M.GatherTime, radius = M.BurstRadius })
	task.spawn(function()
		-- 1. the caster floats up while the chakra gathers
		hrp.Anchored = true
		local t0 = os.clock()
		while os.clock() - t0 < M.GatherTime and alive() do
			local a = (os.clock() - t0) / M.GatherTime
			hrp.CFrame = base + UP * (M.Levitate * a * a * (3 - 2 * a))
			RunService.Heartbeat:Wait()
		end
		hrp.Anchored = false
		if not alive() then
			shield:Destroy()
			return
		end
		-- 2. the burst: shockwave, craters, the rig grows
		hrp.CFrame = base
		fire("MorphBurst", { userId = p.UserId, pos = base.Position, radius = M.BurstRadius, grow = M.GrowTime, scale = M.Scale })
		radialBlast(p, base.Position, M.BurstRadius, M.BurstImpulse, 0.7, M.BurstDamage, 4)
		local look = flatOf(base.LookVector, Vector3.new(0, 0, -1))
		for i = 1, 8 do
			local dir = CFrame.fromAxisAngle(UP, (i / 8) * math.pi * 2 + math.random() * 0.4):VectorToWorldSpace(look)
			GroundFX.impact(base.Position + dir * (17 + math.random() * 6), 4.5, 3, 80)
		end
		-- the body vanishes inside the burst; the rig grows unseen and the beast appears when it is full size
		hideBody(s.morph)
		local scaled = smoothScale(char, hum, char:GetScale(), M.Scale, M.GrowTime)
		if not alive() then
			shield:Destroy()
			return
		end
		if not scaled then
			warn("[KitServer] rig scaling unavailable; the construct is shown at its normal size")
		end
		local ok, model = pcall(BeastConstruct.build, char, CFG)
		if ok then
			s.morph.model = model
			if model and beastMap and altSkin(p) then
				SkinTint.applyTree(model, beastMap) -- CRIMSON FOX: replicated to everyone
			end
		else
			warn("[KitServer] construct build failed: " .. tostring(model))
		end
		s.morph.grown = true
		s.morph.untilT = now() + M.Duration
		s.morph.releaseAt = os.clock() + (M.ReleaseLock or 1.3)
		char:SetAttribute("MorphUntil", s.morph.untilT)
		char:SetAttribute("MorphReadyAt", now() + (M.ReleaseLock or 1.3))
		applyMovement(p, s)
		local _, _, h2 = liveChar(p)
		fire("MorphOn", { userId = p.UserId, pos = h2 and h2.Position or hrp.Position })
		-- (2026-11-10) the shield covers the transformation, not the standing beast: from here Kurama takes hits like any
		-- player (it used to stay up through the auto bomb, ~2.4 s of a full-size, visibly struck giant taking nothing)
		if shield.Parent then
			shield:Destroy()
		end
		-- 3. the signature move, straight out of the transformation
		task.wait(0.45)
		if alive() then
			castBomb(p, s, nil, true)
		end
		task.delay(B.AutoChargeTime + 1.2, function()
			if shield.Parent then
				shield:Destroy()
			end
		end)
	end)
end

---------------------------------------------------------------------------------------------------
-- fighter switching, spawning, requests, timers
local OTHER_KITS = { Limitless = true, Godspeed = true, OneForAll = true, Tempest = true, Carver = true, Shifter = true, Zangetsu = true, Ascendant = true, Gomu = true, Stormdraw = true, Normal = true } -- fighters owned by other scripts (Gojo, Killua, Deku, Sasuke, Sukuna, Eren, Ichigo, Goku, Luffy, Zenitsu)
-- fighters are unlocked per player (2026-11-07): ShopService publishes the player's unlocked ones as KitsOwned (a
-- JSON array, server-written); nothing else can switch to a fighter that isn't in it
local HttpService = game:GetService("HttpService")
local function ownsKit(p, kitId)
	local raw = p:GetAttribute("KitsOwned")
	if type(raw) ~= "string" then
		return false
	end
	local ok, list = pcall(HttpService.JSONDecode, HttpService, raw)
	return ok and type(list) == "table" and table.find(list, kitId) ~= nil
end

local function setKit(p, s, kitId)
	if kitId ~= CFG.KitId and not OTHER_KITS[kitId] then
		return
	end
	if not ownsKit(p, kitId) then
		return -- locked: unlock it in the CHARACTER menu first
	end
	if p:GetAttribute("Kit") == kitId or os.clock() < s.busy or p:GetAttribute("KitLocked") then
		return -- KitLocked: the equipped kit (Godspeed / OneForAll) is mid-move
	end
	-- (2026-11-11, owner: "character swap cooldown") after a switch the next one waits PvPShared.Balance.KIT_SWAP_COOLDOWN
	-- seconds. The player attribute KitSwapReadyAt (server time) is the whole state: CharacterSelect counts it down
	-- ("SWAP IN 12s") and refuses locally, this is the authority. Only a switch FROM a fighter starts it, so the first
	-- pick (ShopService writes Kit directly, from "None") neither starts nor waits on it. Studio test bypass: the
	-- player attribute DevNoSwapCooldown = true (set it on the Server) skips the check and clears the stamp.
	local noSwapCd = RunService:IsStudio() and p:GetAttribute("DevNoSwapCooldown") == true
	if not noSwapCd and now() < (tonumber(p:GetAttribute("KitSwapReadyAt")) or 0) then
		return
	end
	local cur = p:GetAttribute("Kit")
	local fromFighter = cur == CFG.KitId or OTHER_KITS[cur] == true
	endPower(p, s)
	endMorph(p, s)
	-- the stamp goes out BEFORE Kit, so the menu's Kit handler already sees the new cooldown
	-- (2026-11-13) a cooldown of 0 (the owner: "remove the switching cooldown") leaves NO stamp: the menus count down from the
	-- stamp plus a little slack, so stamping "now" still showed "SWAP IN 1s" and refused a second switch for a moment
	local swapCd = tonumber(BAL.KIT_SWAP_COOLDOWN) or 0
	if noSwapCd or swapCd <= 0 then
		p:SetAttribute("KitSwapReadyAt", nil)
	elseif fromFighter then
		p:SetAttribute("KitSwapReadyAt", now() + swapCd)
	end
	p:SetAttribute("Kit", kitId)
end

-- (2026-11-14) ServerScriptService.MapSwitch puts everyone on Gojo in THE RUINS (and gives the old fighter back on the
-- way out): the same clean-up as a switch, but no ownership / cooldown / mid-move refusal - the map decides
do
	local f = Instance.new("BindableFunction")
	f.Name = "ServerSetKit"
	f.OnInvoke = function(p, kitId)
		if typeof(p) ~= "Instance" or not p:IsA("Player") or type(kitId) ~= "string" then
			return false
		end
		if kitId ~= CFG.KitId and not OTHER_KITS[kitId] and kitId ~= "Normal" then
			return false
		end
		if p:GetAttribute("Kit") == kitId then
			return true
		end
		local s = getState(p)
		endPower(p, s)
		endMorph(p, s)
		p:SetAttribute("KitSwapReadyAt", nil)
		p:SetAttribute("Kit", kitId)
		return true
	end
	f.Parent = script
end

local function onCharacter(p, char)
	local s = getState(p)
	s.token += 1
	s.busy = 0
	s.power = nil
	s.morph = nil
	s.ultFree = nil
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then
		s.base = { ws = hum.WalkSpeed, jp = hum.JumpPower, jh = hum.JumpHeight }
		char:SetAttribute("KitWalkSpeed", hum.WalkSpeed)
	end
end

local function onPlayer(p)
	if p:GetAttribute("Kit") == nil then
		p:SetAttribute("Kit", "Limitless")
	end
	if p.Character then
		task.spawn(onCharacter, p, p.Character)
	end
	p.CharacterAdded:Connect(function(char)
		onCharacter(p, char)
	end)
end
for _, p in ipairs(Players:GetPlayers()) do
	onPlayer(p)
end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(p)
	state[p] = nil
end)

Request.OnServerEvent:Connect(function(p, action, payload)
	local s = getState(p)
	-- cursor updates stream in fast while the disc is steered; they skip the request limiter (they only move a point)
	if action == "DiscAim" then
		if type(payload) == "table" and s.discAim and payload.id == s.discAim.id then
			s.discAim.target = validTarget(payload.target) or s.discAim.target
		end
		return
	end
	if typeof(action) ~= "string" or not rateOk(s) then
		return
	end
	if type(payload) ~= "table" then
		payload = {}
	end
	if action == "SetKit" then
		setKit(p, s, payload.kit)
		return
	end
	if p:GetAttribute("Kit") ~= CFG.KitId then
		return
	end
	-- (2026-11-08) "while in susanoo or kurama or the titans players shouldn't be able to use the other abilities":
	-- inside the Kurama form only its own moves work (F: bomb, M1: claw, X: release) - no Rasengan, Rasenshuriken or
	-- Sage Mode (switching Sage Mode OFF still works)
	if s.morph and s.morph.char == p.Character and (action == "Sphere" or action == "Disc" or (action == "Power" and not s.power)) then
		return
	end
	if action == "Sphere" then
		castSphere(p, s, payload)
	elseif action == "Disc" then
		castDisc(p, s, payload)
	elseif action == "Power" then
		togglePower(p, s)
	elseif action == "Morph" then
		toggleMorph(p, s, payload)
	elseif action == "Release" then
		releaseMorph(p, s)
	elseif action == "Claw" then
		castClaw(p, s, payload)
	end
end)

RunService.Heartbeat:Connect(function()
	local t = now()
	for p, s in pairs(state) do
		if s.power and (p.Character ~= s.power.char or t >= s.power.untilT) then
			endPower(p, s, p.Character ~= s.power.char)
		end
		if s.morph and s.morph.grown and (p.Character ~= s.morph.char or t >= s.morph.untilT) then
			endMorph(p, s, p.Character ~= s.morph.char)
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- PERKS (2026-11-07): the "Instant Ult" product (ShopService fires ServerStorage.PerkHooks.UltReset). For a Vulpine
-- player it clears the Kurama cooldown (and the bomb's, which is part of the ultimate) and updates their bar the usual
-- way; bought while the form stands, the form's own cooldown is skipped when it ends.
task.spawn(function()
	local hooks = game:GetService("ServerStorage"):WaitForChild("PerkHooks", 30)
	local ultReset = hooks and hooks:WaitForChild("UltReset", 30)
	if not ultReset then
		warn("[KitServer] PerkHooks.UltReset missing: the instant ult product does nothing for Vulpine")
		return
	end
	ultReset.Event:Connect(function(p)
		if typeof(p) ~= "Instance" or not p:IsA("Player") or not p.Parent or p:GetAttribute("Kit") ~= CFG.KitId then
			return
		end
		local s = getState(p)
		if s.morph then
			s.ultFree = true
		end
		s.cd.Morph = 0
		s.cd.Bomb = 0
		sendCooldown(p, s, "Morph")
		sendCooldown(p, s, "Bomb")
	end)
end)

print("[KitServer] online")
