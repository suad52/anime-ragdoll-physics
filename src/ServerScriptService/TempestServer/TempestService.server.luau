--!nocheck
local PvPBal = require(game:GetService("ServerScriptService"):WaitForChild("PvP")) -- (2026-11-07) player damage/knockback balance
-- TempestService: server side of the Tempest kit. Owns cooldowns, hit detection, damage, stuns and every ragdoll
-- impulse (BasePart:ApplyImpulse). Clients only send intents through Remotes.Request and render Remotes.Broadcast.
--   Lance (Q) | Pulse (E) | Eyes (R, toggle) | Guardian (G; again = arrow) | Slash (M1 while the guardian is up)
--   | Release (X while the guardian is up: ends it through the normal end path)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Kit = ReplicatedStorage:WaitForChild("TempestKit")
local CFG = require(Kit:WaitForChild("Config"))
local Remotes = Kit:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")
local Broadcast = Remotes:WaitForChild("Broadcast")
local Knockback = Remotes:WaitForChild("Knockback")
local StunRemote = Remotes:WaitForChild("Stun")
local GuardianConstruct = require(script.Parent:WaitForChild("GuardianConstruct"))
local Evasion = require(script.Parent:WaitForChild("Evasion"))

-- shared pieces from the rest of the game: ragdolls for NPC bodies, self-healing craters, NPC flee, breakables
local RagdollService, GroundFX, Threat, WorldBlast
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
	local vs = ServerScriptService:FindFirstChild("VulpineServer")
	local gfx = vs and vs:FindFirstChild("GroundFX")
	if gfx then
		local ok, res = pcall(require, gfx)
		GroundFX = ok and res or nil
	end
end

local UP = Vector3.yAxis

local function now()
	return workspace:GetServerTimeNow()
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

local function validPoint(v)
	if typeof(v) ~= "Vector3" or v ~= v or math.abs(v.X) > 1e5 or math.abs(v.Y) > 1e5 or math.abs(v.Z) > 1e5 then
		return nil
	end
	return v
end

-- the flat direction from the caster toward the cursor point the client sent (else the camera look, else facing)
local function cursorFlat(payload, hrp)
	local look = flatOf(hrp.CFrame.LookVector, Vector3.new(0, 0, -1))
	local target = validPoint(payload.target)
	if target and ((target - hrp.Position) * Vector3.new(1, 0, 1)).Magnitude > 2 then
		return flatOf(target - hrp.Position, look)
	end
	return flatOf(payload.aim, look)
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
		s = { cd = {}, busy = 0, reqs = {}, eyes = nil, guard = nil, base = nil, token = 0, slashSide = 1, shieldAt = 0 }
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

-- (2026-11-07 perks) every cooldown scales with the player's perks: CooldownMul on every move, UltChargeMul on top for
-- the ultimate (the guardian, and the arrow and blade slash that only exist while it stands). TempestClient's bar
-- applies the same factors.
-- (2026-11-08) non-ultimate moves x PvPShared.Balance.NON_ULT_COOLDOWN_MUL ("double the cooldown on non ult abilities")
local BAL = require(game:GetService("ReplicatedStorage"):WaitForChild("PvPShared"):WaitForChild("Balance"))
local function cdDur(p, base, isUlt)
	local m = tonumber(p:GetAttribute("CooldownMul")) or 1
	if isUlt then
		m *= tonumber(p:GetAttribute("UltChargeMul")) or 1
	end
	if m ~= m or m <= 0 then
		m = 1
	end
	return base * m * (isUlt and 1 or BAL.NON_ULT_COOLDOWN_MUL)
end

-- (2026-11-07 perks) the caster's colourway, read at cast time: Config.AltPalette ("AZURE SUSANOO") while the player's
-- Skin attribute is "Alt", else the normal palette. ALT_CFG is the Config as the guardian builder sees it for that skin.
local ALT_PALETTE = table.clone(CFG.Palette)
for k, v in pairs(CFG.AltPalette or {}) do
	ALT_PALETTE[k] = v
end
local ALT_CFG = setmetatable({ Palette = ALT_PALETTE }, { __index = CFG })
local function skinned(p)
	return p ~= nil and p:GetAttribute("Skin") == "Alt"
end

local castId = 0
local function nextId()
	castId += 1
	return castId
end

-- how far the guardian has lifted its caster above their own standing height (0 while it is not up): hit tests that
-- belong on the ground (lance sweep, pulse, the slash fissure) measure from the standing height
local function guardLift(s, hum)
	local g = s.guard
	if g and g.hip0 and hum then
		return math.max(hum.HipHeight - g.hip0, 0)
	end
	return 0
end

-- walk speed = the value captured at spawn, times the eye-mode and guardian multipliers
local function applyMovement(p, s)
	local char, hum = liveChar(p)
	if not char or not s.base then
		return
	end
	local ws = s.base.ws
	if s.eyes and s.eyes.char == char then
		ws *= CFG.Eyes.WalkSpeedMul
	end
	if s.guard and s.guard.char == char and s.guard.ready then
		ws *= CFG.Guardian.WalkSpeedMul
	end
	hum.WalkSpeed = ws
	char:SetAttribute("KitWalkSpeed", ws)
end

---------------------------------------------------------------------------------------------------
-- targets and impulses
local function rootOf(model)
	-- (2026-11-08) a player in a giant form answers at the point of its whole body nearest the attack (PvP.formRoot)
	return PvPBal.formRoot(model) or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

-- every ragdollable body except the caster: tagged NPCs plus (optionally) other living players
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

-- one ApplyImpulse per assembly so every body part ends up moving at roughly `vel` (constraint rigs are one
-- assembly per limb); `keep` = how much of the current velocity survives
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

local function damage(attacker, model, amount)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if amount and amount > 0 and hum and hum.Health > 0 then
		model:SetAttribute("LastHitBy", attacker.UserId)
		hum:TakeDamage(PvPBal.dmg(hum, amount))
		recordHit(attacker, model, amount)
	end
end

-- damage + ragdoll + impulse on one body. Players are tumbled by their own client (it owns their physics).
local function knock(attacker, model, vel, ragTime, amount, keep)
	if vel.Magnitude > 320 then
		vel = vel.Unit * 320
	end
	damage(attacker, model, amount)
	if PvPBal.absorbed and PvPBal.absorbed(model) then
		return -- (2026-11-11) blocked / dodged (ServerScriptService.PvP, BLOCK): no tumble, no fling
	end
	local victim = Players:GetPlayerFromCharacter(model)
	if victim then
		if model:GetAttribute("Morphed") then
			vel *= 0.15 -- giants barely budge
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

-- breaks a block: clears "Blocking" and stamps "GuardBrokenUntil" for any block system to respect
local function breakGuard(model, duration)
	model:SetAttribute("Blocking", false)
	model:SetAttribute("GuardBrokenUntil", now() + duration)
end

local looseParams = OverlapParams.new()
looseParams.FilterType = Enum.RaycastFilterType.Exclude

-- loose physics props get pushed too (sign = -1 pulls inward)
local function pushLoose(pos, radius, speed, upBias, sign)
	local ignore = {}
	for _, n in ipairs({ "KitFX", "FX" }) do
		if workspace:FindFirstChild(n) then
			table.insert(ignore, workspace[n])
		end
	end
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

local function radialBlast(p, pos, radius, speed, upBias, amount, ragTime)
	for _, m in ipairs(enemies(p)) do
		PvPBal.aimAt(pos) -- (2026-11-10) a form answers at its body point nearest the blast, not the caster
		local off = rootOf(m).Position - pos
		local d = off.Magnitude
		if d <= radius then
			local k = 1 - d / radius
			local dir = ((d > 0.5 and off.Unit or randomUnit()) + UP * upBias).Unit
			knock(p, m, dir * speed * (0.35 + 0.65 * k), ragTime, amount * k)
		end
	end
	pushLoose(pos, radius, speed, upBias, 1)
	worldHooks(p, pos, radius * 0.6)
end

-- a melee hit on a player first gives their eye mode the chance to dodge it
local function dodged(model, attackerChar)
	return Players:GetPlayerFromCharacter(model) ~= nil and Evasion.tryEvade(model, attackerChar)
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
-- Skill 1: lightning lance. Wind-up (lightning gathers in the hand, rotation locked to the cursor), then the
-- caster's client dashes DashDistance studs; here we sweep the path for the first enemy root part.
local function castLance(p, s, payload)
	local char, _, hrp, t = gate(p, s, "Lance")
	if not char then
		return
	end
	local L = CFG.Lance
	local dir = cursorFlat(payload, hrp)
	s.cd.Lance = t + cdDur(p, L.Cooldown)
	s.busy = os.clock() + L.WindUp + L.DashTime + 0.3
	sendCooldown(p, s, "Lance")
	local id = nextId()
	fire("LanceCharge", { id = id, userId = p.UserId, windup = L.WindUp, dashTime = L.DashTime, distance = L.DashDistance, dir = dir })
	task.spawn(function()
		task.wait(L.WindUp)
		local c2, _, h2 = liveChar(p)
		if c2 ~= char then
			fire("LanceEnd", { id = id })
			return
		end
		-- the caster's client drives the dash, so the server sees it about one round trip late: keep watching until
		-- the rush has actually been seen and has ended (or a latency allowance runs out), and only test for hits
		-- while the body is really rushing, so walking into someone after the dash never counts
		local lift = UP * guardLift(s, char:FindFirstChildOfClass("Humanoid"))
		local prev = h2.Position - lift
		local t0 = os.clock()
		local seenDash, lastFast = false, 0
		while true do
			local dt = RunService.Heartbeat:Wait()
			c2, _, h2 = liveChar(p)
			if c2 ~= char then
				break
			end
			local pos = h2.Position - lift
			local speed = ((pos - prev) * Vector3.new(1, 0, 1)).Magnitude / math.max(dt, 1e-3)
			local best, bestD, at
			if speed > 35 then
				seenDash, lastFast = true, os.clock()
				local cur = pos + dir * 2 -- the lightning hand leads the body
				for _, m in ipairs(enemies(p)) do
					local d, closest = segDist(rootOf(m).Position, prev, cur)
					if d <= L.HitRadius and (not bestD or d < bestD) then
						best, bestD, at = m, d, closest
					end
				end
			end
			prev = pos
			if best then
				if dodged(best, char) then
					fire("LanceEnd", { id = id })
					return
				end
				local pos = rootOf(best).Position
				breakGuard(best, L.GuardBreakTime)
				knock(p, best, dir * L.Impulse + UP * L.UpImpulse, L.RagdollTime, L.Damage)
				pushLoose(pos, 10, L.Impulse * 0.6, 0.4, 1)
				worldHooks(p, pos, 4)
				if GroundFX then
					GroundFX.impact(pos, 3.5, 5, 45)
				end
				fire("LanceHit", { id = id, userId = p.UserId, pos = pos, dir = dir })
				return
			end
			if (seenDash and os.clock() - lastFast > 0.15) or os.clock() - t0 > L.DashTime + 0.9 then
				break
			end
		end
		fire("LanceEnd", { id = id })
	end)
end

---------------------------------------------------------------------------------------------------
-- Skill 2: KIRIN (2026-11-08; was a radial pulse around the caster). The caster raises a hand to the sky, storm clouds
-- gather over the cursor point and, StrikeDelay later, a dragon of lightning dives out of them onto that point (all
-- drawn by the clients from "KirinCall"). Everything within Radius of where it lands is stunned (WalkSpeed 0), held
-- in place for AnchorTime, shocked over StunTime, and knocked down outward once the hold ends ("Pulse" = the landing).
local function stunBody(model, duration, hold)
	local victim = Players:GetPlayerFromCharacter(model)
	if victim then
		PvPBal.stun(model, duration) -- (2026-11-08) the shared PvP stun too: no moves, no walking
		StunRemote:FireClient(victim, duration, hold)
		return
	end
	model:SetAttribute("StunnedUntil", now() + duration) -- the NPC brain stands still while this is in the future
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = 0
	end
	local r = rootOf(model)
	if r and not model:GetAttribute("Ragdolled") then
		r.Anchored = true
		task.delay(hold, function()
			if r.Parent then
				r.Anchored = false
			end
		end)
	end
end

-- the ground under a point (bodies, effects and debris are looked through); nil if there is none within reach
local kirinRay = RaycastParams.new()
kirinRay.FilterType = Enum.RaycastFilterType.Exclude
local function kirinGround(pos, above)
	local ignore = {}
	for _, n in ipairs({ "KitFX", "FX", "LocalFX", "KitDebris" }) do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(ignore, f)
		end
	end
	if GroundFX and GroundFX.folder then
		table.insert(ignore, GroundFX.folder)
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	for _, m in ipairs(CollectionService:GetTagged(CFG.TargetTag)) do
		table.insert(ignore, m)
	end
	kirinRay.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos + UP * above, Vector3.new(0, -(above + 80), 0), kirinRay)
	return hit and hit.Position or nil
end

-- where the dragon lands: the cursor point (pulled in to Range from the caster), dropped onto the ground under it -
-- a cursor on a body or a wall strikes at its foot, a cursor on the sky strikes Range out along that heading
local function kirinPoint(s, payload, hrp, hum)
	local P = CFG.Pulse
	local feet = hrp.Position - UP * (hum.HipHeight + hrp.Size.Y / 2) -- (HipHeight already includes a guardian's lift)
	local target = validPoint(payload.target)
	local off = target and (target - feet) * Vector3.new(1, 0, 1) or nil
	local point, above = nil, 6
	if target and off.Magnitude <= P.Range then
		point = target
	else
		local dir = (off and off.Magnitude > 1e-3) and off.Unit or cursorFlat(payload, hrp)
		point = feet + dir * (off and math.min(off.Magnitude, P.Range) or P.Range * 0.4)
		above = 40 -- the cursor's own height means nothing out there: search well above the caster's
	end
	return kirinGround(point, above) or point
end

local function castPulse(p, s, payload)
	local char, hum, hrp, t = gate(p, s, "Pulse")
	if not char then
		return
	end
	local P = CFG.Pulse
	s.cd.Pulse = t + cdDur(p, P.Cooldown)
	s.busy = os.clock() + P.CastLock
	sendCooldown(p, s, "Pulse")
	local center = kirinPoint(s, payload, hrp, hum)
	local id = nextId()
	fire("KirinCall", { id = id, userId = p.UserId, pos = center, strikeAt = now() + P.StrikeDelay, delay = P.StrikeDelay, sky = P.SkyHeight, radius = P.Radius })
	task.wait(P.StrikeDelay)
	if not p.Parent then
		return
	end
	local caught = {}
	for _, m in ipairs(enemies(p)) do
		PvPBal.aimAt(center) -- (2026-11-10) forms: nearest the strike
		local r = rootOf(m)
		if r and (r.Position - center).Magnitude <= P.Radius + 2 then
			table.insert(caught, m)
			damage(p, m, P.StrikeDamage or 0)
			stunBody(m, P.StunTime, P.AnchorTime)
		end
	end
	fire("Pulse", { id = id, userId = p.UserId, pos = center, radius = P.Radius, stun = P.StunTime, hold = P.AnchorTime, caught = caught, sky = P.SkyHeight })
	worldHooks(p, center, P.Radius * 0.6)
	if GroundFX then
		GroundFX.impact(center, 6, 10, 55)
		GroundFX.ring(center, P.Radius * 0.7, 12, 26)
	end
	-- damage over time across the stun
	task.spawn(function()
		for _ = 1, P.Ticks do
			task.wait(P.StunTime / P.Ticks)
			for _, m in ipairs(caught) do
				if m.Parent then
					damage(p, m, P.Damage / P.Ticks)
				end
			end
		end
	end)
	-- once the hold ends, everything caught is thrown down and out
	task.delay(P.AnchorTime, function()
		for _, m in ipairs(caught) do
			local r = m.Parent and rootOf(m)
			if r then
				local off = (r.Position - center) * Vector3.new(1, 0, 1)
				local dir = ((off.Magnitude > 0.5 and off.Unit or randomUnit()) + UP * P.UpBias).Unit
				knock(p, m, dir * P.KnockSpeed, P.RagdollTime, 0)
			end
		end
		pushLoose(center, P.Radius, P.KnockSpeed, P.UpBias, 1)
	end)
end

---------------------------------------------------------------------------------------------------
-- Skill 3: eye mode (toggle). Glowing eye overlays (crimson right, violet left, optional decal art) and a violet
-- trail off the left eye, built in the character so everyone sees them; the next melee hit is auto-dodged.
local function buildEyes(char, pal)
	local head = char:FindFirstChild("Head")
	local folder = Instance.new("Folder")
	folder.Name = "EyeModeFX"
	if head then
		local sz = head.Size
		local E, Pal = CFG.Eyes, pal or CFG.Palette
		for _, side in ipairs({ 1, -1 }) do -- +1 = the right eye (a character's right is +X in its own space)
			local right = side > 0
			local eye = Instance.new("Part")
			eye.Name = right and "RightEye" or "LeftEye"
			eye.Material = Enum.Material.Neon
			eye.Color = right and Pal.EyeRight or Pal.EyeLeft
			eye.Size = Vector3.new(0.24, 0.16, 0.05) * (sz.Y / 1.2)
			eye.CanCollide, eye.CanQuery, eye.CanTouch, eye.Massless, eye.CastShadow = false, false, false, true, false
			local c0 = CFrame.new(0.2 * sz.X * side, 0.08 * sz.Y, -0.5 * sz.Z - 0.012)
			eye.CFrame = head.CFrame * c0
			local w = Instance.new("Weld")
			w.Part0, w.Part1, w.C0 = head, eye, c0
			w.Parent = eye
			local art = right and E.RightDecal or E.LeftDecal
			if art ~= "" then
				local d = Instance.new("Decal")
				d.Face = Enum.NormalId.Front
				d.Texture = art
				d.Parent = eye
			end
			if not right then
				-- the left eye drags a violet streak of light behind every move
				local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
				a0.Position, a1.Position = Vector3.new(0, 0.06, 0), Vector3.new(0, -0.06, 0)
				a0.Parent, a1.Parent = eye, eye
				local trail = Instance.new("Trail")
				trail.Attachment0, trail.Attachment1 = a0, a1
				trail.Color = ColorSequence.new(Pal.EyeTrail, Pal.EyeLeft)
				trail.Transparency = NumberSequence.new(0.05, 1)
				trail.Lifetime = 0.45
				trail.LightEmission = 1
				trail.FaceCamera = true
				trail.WidthScale = NumberSequence.new(1, 0)
				trail.Parent = eye
			end
			local glow = Instance.new("PointLight")
			glow.Color, glow.Range, glow.Brightness, glow.Shadows = eye.Color, 4, 1.2, false
			glow.Parent = eye
			eye.Parent = folder
		end
	end
	folder.Parent = char
	return folder
end

local function endEyes(p, s, reason)
	local e = s.eyes
	if not e then
		return
	end
	s.eyes = nil
	if e.folder then
		e.folder:Destroy()
	end
	if e.char.Parent then
		e.char:SetAttribute("EyeMode", false)
	end
	s.cd.Eyes = now() + cdDur(p, CFG.Eyes.Cooldown)
	sendCooldown(p, s, "Eyes")
	applyMovement(p, s)
	fire("EyesOff", { userId = p.UserId, reason = reason })
end

local function toggleEyes(p, s)
	if s.eyes then
		endEyes(p, s, "cancel")
		return
	end
	local char, _, hrp, t = gate(p, s, "Eyes")
	if not char then
		return
	end
	s.eyes = { char = char, untilT = t + CFG.Eyes.Window, folder = buildEyes(char, skinned(p) and ALT_PALETTE or CFG.Palette) }
	char:SetAttribute("EyeUntil", s.eyes.untilT)
	char:SetAttribute("EyeMode", true)
	applyMovement(p, s)
	fire("EyesOn", { userId = p.UserId, pos = hrp.Position })
end

-- the dodge: blink BlinkBehind studs behind the attacker, facing their back, and spend the window
Evasion.setHandler(function(victim, attacker)
	local pl = Players:GetPlayerFromCharacter(victim)
	local s = pl and state[pl]
	if not s or not s.eyes or s.eyes.char ~= victim or now() >= s.eyes.untilT then
		return false
	end
	-- (2026-11-10) the real roots: rootOf can hand back a form's unparented stand-in, which has no facing
	local vhrp = victim:FindFirstChild("HumanoidRootPart")
	local ahrp = attacker and attacker:FindFirstChild("HumanoidRootPart")
	if not vhrp then
		return false
	end
	local from = vhrp.Position
	if ahrp then
		local behind = (ahrp.CFrame * CFrame.new(0, 0, CFG.Eyes.BlinkBehind)).Position
		victim:PivotTo(CFrame.lookAt(behind, Vector3.new(ahrp.Position.X, behind.Y, ahrp.Position.Z)))
	end
	fire("EyesDodge", { userId = pl.UserId, from = from, to = vhrp.Position })
	endEyes(pl, s, "dodge")
	return true
end)

-- Studio-only test hook: lets a test script run the dodge path without a second player to attack with
if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "DebugEvade"
	hook.OnInvoke = function(victim, attacker)
		return Evasion.tryEvade(victim, attacker)
	end
	hook.Parent = script
end

---------------------------------------------------------------------------------------------------
-- Skill 4: spectral guardian. A summoning shockwave, then the construct is welded to the root and the caster is lifted
-- into its chest (HipHeight); while it is up a force shield shoves everything back, M1 becomes a giant blade slash
-- that splits the ground, G looses an arrow, and X releases it. Every way out (release, timeout, death, kit switch)
-- comes through endGuardian, which puts hip height, jump and walk speed back exactly as they were.
local function endGuardian(p, s, quiet, reason)
	local g = s.guard
	if not g then
		return
	end
	s.guard = nil
	s.token += 1
	local char = g.char
	if g.rise then
		g.rise:Cancel()
	end
	local hum = char.Parent and char:FindFirstChildOfClass("Humanoid")
	if hum and g.hip0 then
		hum.HipHeight = g.hip0
		hum.JumpPower, hum.JumpHeight = g.jp0, g.jh0
	end
	if g.model then
		if quiet or not char.Parent then
			g.model:Destroy()
		else
			-- clients dissolve it on GuardianEnd; renamed so nothing mistakes it for a standing guardian
			g.model.Name = "GuardianConstruct_Fading"
			Debris:AddItem(g.model, CFG.Guardian.FadeTime or 0.6)
		end
	end
	if char.Parent then
		char:SetAttribute("Morphed", false)
		char:SetAttribute("Guardian", false)
		char:SetAttribute("GuardianUntil", nil)
		char:SetAttribute("GuardianReleaseAt", nil)
	end
	-- (perks) an Instant Ult bought while the guardian stood leaves it ready the moment it ends
	s.cd.Guardian = s.ultReset and 0 or now() + cdDur(p, CFG.Guardian.Cooldown, true)
	s.ultReset = nil
	sendCooldown(p, s, "Guardian")
	applyMovement(p, s)
	local _, _, hrp = liveChar(p)
	if not quiet then
		fire("GuardianEnd", { userId = p.UserId, pos = hrp and hrp.Position, reason = reason, fade = CFG.Guardian.FadeTime or 0.6 })
	end
end

-- X: the caster lets the guardian go. Refused until the entrance (summoning + its own arrow) has played out.
local function releaseGuardian(p, s)
	local g = s.guard
	if not g or not g.ready then
		return
	end
	if os.clock() < (g.releaseAt or 0) then
		Broadcast:FireClient(p, "ReleaseDenied", { wait = g.releaseAt - os.clock() })
		return
	end
	endGuardian(p, s, false, "release")
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
-- the guardian's signature move: a giant lightning arrow. The caster's client reports the cursor just before the draw
-- finishes; the arrow then pierces everything within Width of its line (it stops at the first solid surface), the
-- ground along the line is torn up one crater after another as the arrow passes, and it detonates where it lands.
local arrowRay = RaycastParams.new()
arrowRay.FilterType = Enum.RaycastFilterType.Exclude

local function groundBelow(pos)
	local ignore = {}
	for _, inst in ipairs({ workspace:FindFirstChild("KitFX") or false, (GroundFX and GroundFX.folder) or false }) do
		if inst then
			table.insert(ignore, inst)
		end
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	for _, m in ipairs(CollectionService:GetTagged(CFG.TargetTag)) do
		table.insert(ignore, m)
	end
	arrowRay.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos + UP * 4, Vector3.new(0, -60, 0), arrowRay)
	return hit and hit.Position or nil
end

local function castArrow(p, s, payload, auto)
	if auto then
		s.busy = 0 -- the entrance's own guard
	end
	local char, _, hrp, t = gate(p, s, "Arrow")
	if not char or not (auto or (s.guard and s.guard.ready)) then
		return
	end
	local A = CFG.Arrow
	local charge = auto and A.AutoChargeTime or A.ChargeTime
	local id = nextId()
	s.cd.Arrow = t + cdDur(p, A.Cooldown, true) + charge
	sendCooldown(p, s, "Arrow")
	s.busy = os.clock() + charge + 0.6
	s.arrowAim = { id = id, target = validPoint(type(payload) == "table" and payload.target or nil) }
	fire("ArrowCharge", { id = id, userId = p.UserId, time = charge })
	task.delay(charge, function()
		local c2, _, h2 = liveChar(p)
		if c2 ~= char or not s.guard then
			fire("ArrowCancel", { id = id })
			return
		end
		local look = (h2.CFrame.LookVector * Vector3.new(1, 0, 1))
		look = look.Magnitude > 1e-3 and look.Unit or Vector3.new(0, 0, -1)
		-- loosed from the guardian's bow at full draw (the client's draw pose puts the bow grip there)
		local origin = (CFrame.lookAt(h2.Position, h2.Position + look) * CFrame.new(GuardianConstruct.points(CFG).muzzle)).Position
		local aim = s.arrowAim and s.arrowAim.id == id and s.arrowAim.target or nil
		s.arrowAim = nil
		local dir = look
		if aim and (aim - origin).Magnitude > 6 then
			dir = (aim - origin).Unit
		end
		-- the line stops at the first solid surface
		local ignore = {}
	for _, inst in ipairs({ workspace:FindFirstChild("KitFX") or false, (GroundFX and GroundFX.folder) or false }) do
		if inst then
			table.insert(ignore, inst)
		end
	end
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl.Character then
				table.insert(ignore, pl.Character)
			end
		end
		for _, m in ipairs(CollectionService:GetTagged(CFG.TargetTag)) do
			table.insert(ignore, m)
		end
		arrowRay.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(origin, dir * A.Range, arrowRay)
		local finish = hit and hit.Position or origin + dir * A.Range
		local length = (finish - origin).Magnitude
		fire("ArrowFire", { id = id, userId = p.UserId, origin = origin, dir = dir, length = length, speed = A.Speed })
		-- everything on the line is pierced and carried along with it
		for _, m in ipairs(enemies(p)) do
			PvPBal.aimSeg(m, origin, finish) -- (2026-11-10) forms: nearest the arrow's line
			local r = rootOf(m)
			local d, closest = segDist(r.Position, origin, finish)
			if d <= A.Width then
				local k = 1 - ((closest - origin).Magnitude / math.max(length, 1)) * 0.35
				breakGuard(m, 1.5)
				knock(p, m, (dir * 0.95 + UP * A.UpBias).Unit * A.Impulse * k, A.RagdollTime, A.Damage * k)
			end
		end
		-- a crater trail torn up behind the arrow's head
		task.spawn(function()
			local steps = math.min(A.TrenchSteps, math.max(2, math.floor(length / 9)))
			for i = 1, steps do
				local at = origin + dir * (length * i / steps)
				local g = groundBelow(at)
				if g and GroundFX and (g - at).Magnitude < 40 then
					GroundFX.impact(g, 3.4, 1, 45)
				end
				worldHooks(p, at, 8)
				task.wait((length / steps) / A.Speed)
			end
		end)
		-- the detonation where it lands
		task.delay(length / A.Speed, function()
			fire("ArrowHit", { id = id, userId = p.UserId, pos = finish, radius = A.EndRadius })
			radialBlast(p, finish, A.EndRadius, A.EndImpulse, 0.7, A.EndDamage, A.RagdollTime)
			worldHooks(p, finish, A.EndRadius * 0.5)
			local g = groundBelow(finish) or finish
			if GroundFX then
				GroundFX.impact(g, 11, 16, 100)
			end
		end)
	end)
end

---------------------------------------------------------------------------------------------------
-- the summoning: a cinematic entrance. A lightning storm gathers around the caster (1.2 s), then the guardian bursts
-- out -- shockwave, craters, skeleton and armour taking shape on the clients -- and loosens an arrow of its own.
-- Pressing the key again while it stands fires another arrow.
local function toggleGuardian(p, s, payload)
	if s.guard then
		if s.guard.ready then
			castArrow(p, s, payload, false)
		end
		return
	end
	local char, _, hrp, t = gate(p, s, "Guardian")
	if not char then
		return
	end
	local G, A = CFG.Guardian, CFG.Arrow
	s.token += 1
	local tok = s.token
	s.busy = os.clock() + G.GatherTime + G.SummonTime + A.AutoChargeTime + 1.5
	local hum0 = char:FindFirstChildOfClass("Humanoid")
	s.guard = { char = char, untilT = math.huge, ready = false, hip0 = hum0.HipHeight, jp0 = hum0.JumpPower, jh0 = hum0.JumpHeight, cfg = skinned(p) and ALT_CFG or CFG }
	char:SetAttribute("Morphed", true) -- the shared punch is replaced by the blade while the guardian stands
	local shield = ffOn(char)
	local base = hrp.Position
	local function alive()
		return s.token == tok and s.guard ~= nil and liveChar(p) == char
	end
	fire("GuardianStart", { userId = p.UserId, pos = base, gather = G.GatherTime })
	task.spawn(function()
		task.wait(G.GatherTime)
		if not alive() then
			shield:Destroy()
			return
		end
		local c2, _, h2 = liveChar(p)
		-- the burst: everything around is thrown, the ground cracks open, the guardian is built
		fire("GuardianBurst", { userId = p.UserId, pos = h2.Position, radius = G.BurstRadius, time = G.SummonTime })
		radialBlast(p, h2.Position, G.BurstRadius, G.BurstImpulse, 0.65, G.BurstDamage, 3.5)
		if GroundFX then
			GroundFX.ring(h2.Position, 12, 16, 26)
			for i = 1, 7 do
				local ang = (i / 7) * math.pi * 2 + math.random() * 0.4
				GroundFX.impact(h2.Position + Vector3.new(math.cos(ang), 0, math.sin(ang)) * (18 + math.random() * 6), 4.2, 3, 75)
			end
		end
		local ok, model = pcall(GuardianConstruct.build, char, s.guard.cfg or CFG)
		if not ok then
			warn("[TempestService] guardian build failed: " .. tostring(model))
			model = nil
		end
		s.guard.model = model
		s.guard.ready = true
		s.guard.untilT = now() + G.Duration
		-- the caster rises into the guardian's chest as it takes shape; a giant hops, it does not bounce
		local hum = h2.Parent and c2:FindFirstChildOfClass("Humanoid")
		if hum then
			local lift = (G.RootHeight or GuardianConstruct.RootHeight) * (G.Scale or 1) - h2.Size.Y / 2
			if lift > s.guard.hip0 then
				s.guard.rise = TweenService:Create(hum, TweenInfo.new(G.RiseTime or G.SummonTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { HipHeight = lift })
				s.guard.rise:Play()
			end
			hum.JumpPower = s.guard.jp0 * (G.JumpMul or 1)
			hum.JumpHeight = s.guard.jh0 * (G.JumpMul or 1)
		end
		local fullIn = G.SummonTime + A.AutoChargeTime + 0.3
		s.guard.releaseAt = os.clock() + fullIn
		char:SetAttribute("GuardianUntil", s.guard.untilT)
		char:SetAttribute("GuardianReleaseAt", now() + fullIn)
		char:SetAttribute("Guardian", true)
		applyMovement(p, s)
		fire("GuardianOn", { userId = p.UserId, pos = h2.Position, reveal = G.SummonTime })
		-- the signature move, straight out of the summoning
		task.wait(G.SummonTime)
		-- (2026-11-10) the shield covers the summoning, not the standing guardian: from here the Susanoo takes hits like
		-- any player (it used to stay up through the auto arrow, ~2 s of a fully revealed giant taking nothing)
		if shield.Parent then
			shield:Destroy()
		end
		if alive() then
			castArrow(p, s, nil, true)
		end
		task.delay(A.AutoChargeTime + 1.2, function()
			if shield.Parent then
				shield:Destroy()
			end
		end)
	end)
end

local function castSlash(p, s, payload)
	if not (s.guard and s.guard.ready) then
		return
	end
	local char, _, hrp, t = gate(p, s, "Slash")
	if not char then
		return
	end
	local G = CFG.Guardian
	s.cd.Slash = t + cdDur(p, G.SlashCooldown, true)
	s.slashSide = -s.slashSide
	local side = s.slashSide
	local dir = cursorFlat(payload, hrp)
	fire("SlashStart", { userId = p.UserId, side = side, windup = G.SlashWindup, dir = dir })
	task.delay(G.SlashWindup, function()
		local c2, _, h2 = liveChar(p)
		if c2 ~= char or not s.guard then
			return
		end
		local origin = h2.Position
		-- the swing comes off the guardian's sword shoulder; its ground split starts at the caster's standing height
		local pivot = (CFrame.lookAt(origin, origin + dir) * CFrame.new(GuardianConstruct.points(CFG).shoulder)).Position
		local low = origin - UP * guardLift(s, c2:FindFirstChildOfClass("Humanoid"))
		local across = dir:Cross(UP) * side
		local half = math.rad(G.SlashArc / 2)
		for _, m in ipairs(enemies(p)) do
			local off = (rootOf(m).Position - origin) * Vector3.new(1, 0, 1)
			local d = off.Magnitude
			if d <= G.SlashRange and (d < 4 or math.acos(math.clamp(off.Unit:Dot(dir), -1, 1)) <= half) and not dodged(m, char) then
				local k = 1 - d / G.SlashRange
				local v = (dir * 0.75 + across * 0.5 + UP * 0.45).Unit * G.SlashImpulse * (0.6 + 0.4 * k)
				breakGuard(m, 1)
				knock(p, m, v, 3.5, G.SlashDamage * (0.5 + 0.5 * k))
			end
		end
		-- the ground splits along the swing; structural damage all along it
		for dist = 6, G.FissureLength, 5 do
			local at = low + dir * dist
			if GroundFX then
				GroundFX.impact(at, 3 + dist * 0.04, 2, 40)
			end
			worldHooks(p, at, 7)
		end
		pushLoose(low + dir * 14, 18, G.SlashImpulse, 0.4, 1)
		fire("Slash", { userId = p.UserId, side = side, origin = low, pivot = pivot, dir = dir, range = G.SlashRange, arc = G.SlashArc, fissure = G.FissureLength })
	end)
end

---------------------------------------------------------------------------------------------------
-- spawning, requests, timers, the guardian's force shield
local function onCharacter(p, char)
	local s = getState(p)
	s.token += 1
	s.busy = 0
	s.eyes = nil
	s.guard = nil
	s.ultReset = nil
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then
		s.base = { ws = hum.WalkSpeed }
	end
end

local function onPlayer(p)
	if p.Character then
		task.spawn(onCharacter, p, p.Character)
	end
	p.CharacterAdded:Connect(function(char)
		onCharacter(p, char)
	end)
	-- switching away from this kit drops whatever is active
	p:GetAttributeChangedSignal("Kit"):Connect(function()
		local s = state[p]
		if s and p:GetAttribute("Kit") ~= CFG.KitId then
			endEyes(p, s, "cancel")
			endGuardian(p, s)
		end
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
	-- the cursor point for the arrow being drawn: it only moves a point, so it skips the request limiter
	if action == "ArrowAim" then
		if type(payload) == "table" and s.arrowAim and payload.id == s.arrowAim.id then
			s.arrowAim.target = validPoint(payload.target) or s.arrowAim.target
		end
		return
	end
	if typeof(action) ~= "string" or not rateOk(s) then
		return
	end
	if type(payload) ~= "table" then
		payload = {}
	end
	if p:GetAttribute("Kit") ~= CFG.KitId then
		return
	end
	-- (2026-11-08) "while in susanoo or kurama or the titans players shouldn't be able to use the other abilities":
	-- while the Susanoo stands only its own moves work (M1: slash, G: arrow, X: release) - no Chidori, Kirin, or
	-- turning the eyes on (turning them off still works)
	if s.guard and (action == "Lance" or action == "Pulse" or (action == "Eyes" and not s.eyes)) then
		return
	end
	if action == "Lance" then
		castLance(p, s, payload)
	elseif action == "Pulse" then
		task.spawn(castPulse, p, s, payload) -- (it waits out the dragon's dive)
	elseif action == "Eyes" then
		toggleEyes(p, s)
	elseif action == "Guardian" then
		toggleGuardian(p, s, payload)
	elseif action == "Slash" then
		castSlash(p, s, payload)
	elseif action == "Release" then
		releaseGuardian(p, s)
	end
end)

RunService.Heartbeat:Connect(function()
	local t = now()
	local clock = os.clock()
	local G = CFG.Guardian
	for p, s in pairs(state) do
		if s.eyes and (p.Character ~= s.eyes.char or t >= s.eyes.untilT) then
			endEyes(p, s, p.Character ~= s.eyes.char and "cancel" or "expired")
		end
		local g = s.guard
		if g and g.ready then
			local char, _, hrp = liveChar(p)
			if char ~= g.char or t >= g.untilT then
				endGuardian(p, s, char ~= g.char, char ~= g.char and "lost" or "expired")
			elseif clock >= s.shieldAt then
				-- the force shield: everything that steps inside is shoved back out and singed
				s.shieldAt = clock + G.ShieldTick
				for _, m in ipairs(enemies(p)) do
					local off = (rootOf(m).Position - hrp.Position) * Vector3.new(1, 0, 1)
					if off.Magnitude <= G.ShieldRadius then
						local dir = ((off.Magnitude > 0.5 and off.Unit or randomUnit()) + UP * 0.35).Unit
						knock(p, m, dir * G.ShieldPush, 1.5, G.ShieldDamage, 0.3)
						fire("ShieldHit", { userId = p.UserId, pos = rootOf(m).Position })
					end
				end
			end
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- (2026-11-07 perks) Instant Ult: ServerStorage.PerkHooks.UltReset(player) clears the guardian's cooldown (and the
-- arrow's and slash's) for a player on this kit and pushes the new state to their bar. Bought while the guardian
-- stands, the cooldown its end would start is skipped instead.
local function ultReset(p)
	if typeof(p) ~= "Instance" or not p:IsA("Player") or p:GetAttribute("Kit") ~= CFG.KitId then
		return
	end
	local s = getState(p)
	s.cd.Guardian, s.cd.Arrow, s.cd.Slash = 0, 0, 0
	s.ultReset = s.guard ~= nil or nil
	sendCooldown(p, s, "Guardian")
	sendCooldown(p, s, "Arrow")
	sendCooldown(p, s, "Slash")
end
task.spawn(function()
	local hooks = game:GetService("ServerStorage"):WaitForChild("PerkHooks", 30)
	local ev = hooks and hooks:WaitForChild("UltReset", 10)
	if ev then
		ev.Event:Connect(function(p)
			local ok, err = pcall(ultReset, p)
			if not ok then
				warn("[TempestService] UltReset: " .. tostring(err))
			end
		end)
	else
		warn("[TempestService] PerkHooks.UltReset not found")
	end
end)

print("[TempestService] online")
