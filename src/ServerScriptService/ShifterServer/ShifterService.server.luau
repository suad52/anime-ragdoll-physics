--!nocheck
local PvPBal = require(game:GetService("ServerScriptService"):WaitForChild("PvP")) -- (2026-11-07) player damage/knockback balance
-- ShifterService: server side of the Shifter kit. Owns cooldowns, hit detection, damage, every ragdoll impulse, the
-- rig scaling and the welded giant bodies; clients render (they send "Request" and play back "Broadcast").
--   Tether   : twin hooks (the caster's own client reels its body in) / a spinning blade strike on a nearby enemy
--   Warrior  : a 4x form with super-armour: punches on M1, a leaping hammer slam on the key again
--   Colossus : a 14x form born from a thermal blast; a steam field scalds and repels; stomps on M1, a full steam
--              release on the key again
--   Founder  : a skeletal colossus over a territory: roars that flatten everything, a hunting swarm of giants, bone
--              spears on M1, a marching wall of giants on the key again
-- Every form can be left early with "Release" (X on the client): its normal end path and its normal cooldown.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")

local Kit = ReplicatedStorage:WaitForChild("ShifterKit")
local CFG = require(Kit:WaitForChild("Config"))
local Remotes = Kit:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")
local Broadcast = Remotes:WaitForChild("Broadcast")
local Knockback = Remotes:WaitForChild("Knockback")
local TitanSkins = require(script.Parent:WaitForChild("TitanSkins"))

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

local FXFolder = workspace:FindFirstChild("KitFX") or Instance.new("Folder")
FXFolder.Name = "KitFX"
FXFolder.Parent = workspace
local SwarmFolder = workspace:FindFirstChild("TitanSwarm") or Instance.new("Folder")
SwarmFolder.Name = "TitanSwarm"
SwarmFolder.Parent = workspace

local UP = Vector3.yAxis
local FLAT = Vector3.new(1, 0, 1)

local function now()
	return workspace:GetServerTimeNow()
end

local function randomUnit()
	local v = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	return v.Magnitude > 1e-3 and v.Unit or Vector3.xAxis
end

local function randomFlat()
	local a = math.random() * math.pi * 2
	return Vector3.new(math.cos(a), 0, math.sin(a))
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
	local f = typeof(v) == "Vector3" and v * FLAT or Vector3.zero
	return f.Magnitude > 1e-3 and f.Unit or fallback
end

-- a world point the client says its cursor is on (nil if it is not a sane position)
local function validPoint(v)
	if typeof(v) ~= "Vector3" or v ~= v or math.abs(v.X) > 1e5 or math.abs(v.Y) > 1e5 or math.abs(v.Z) > 1e5 then
		return nil
	end
	return v
end

-- (aim, flat): the direction from `origin` to the client's cursor point and its horizontal part
local function aimFrom(origin, payload, hrp)
	local look = flatOf(hrp.CFrame.LookVector, Vector3.new(0, 0, -1))
	local target = validPoint(type(payload) == "table" and payload.target or nil)
	if target and ((target - origin) * FLAT).Magnitude > 4 then
		local d = (target - origin).Unit
		return d, flatOf(d, look)
	end
	return look, look
end

---------------------------------------------------------------------------------------------------
-- player state
local state = {}
local function getState(p)
	local s = state[p]
	if not s then
		s = { cd = {}, busy = 0, reqs = {}, token = 0 }
		state[p] = s
	end
	return s
end

local function rateOk(s)
	local t = os.clock()
	while #s.reqs > 0 and t - s.reqs[1] > 1 do
		table.remove(s.reqs, 1)
	end
	if #s.reqs >= 18 then
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

-- PERKS (2026-11-07, kits-D). Faster Cooldowns / Faster Ult Charge: every cooldown this kit starts is base x the
-- player's CooldownMul, and the ultimate's x UltChargeMul as well (both attributes are written by ShopService only).
-- The Founding Titan is the ultimate (the wide G button); its bone spears and the rumbling exist only inside it, so
-- they count as the ultimate too. Fighter Skins: a caster whose player has Skin == "Alt" gets the CRYSTAL TITAN bodies
-- (Config.AltPalette over Palette, Config.AltMaterial on every piece that does not glow).
local ULT_SKILLS = { Founder = true, Spear = true, Rumble = true }
-- (2026-11-08) non-ultimate moves x PvPShared.Balance.NON_ULT_COOLDOWN_MUL ("double the cooldown on non ult abilities");
-- the giant forms' M1s (the Attack Titan's punch, the Colossal's stomp) are swings, not abilities, and keep theirs
local BAL = require(game:GetService("ReplicatedStorage"):WaitForChild("PvPShared"):WaitForChild("Balance"))
local FORM_M1 = { Punch = true, Stomp = true }
local function cdFor(p, skill, base)
	local m = tonumber(p:GetAttribute("CooldownMul")) or 1
	if ULT_SKILLS[skill] then
		m *= tonumber(p:GetAttribute("UltChargeMul")) or 1
	end
	if m ~= m or m <= 0 then
		m = 1
	end
	return base * math.clamp(m, 0.05, 4) * ((ULT_SKILLS[skill] or FORM_M1[skill]) and 1 or BAL.NON_ULT_COOLDOWN_MUL)
end
local ALT_CFG
do
	local pal = table.clone(CFG.Palette)
	for k, v in pairs(CFG.AltPalette or {}) do
		pal[k] = v
	end
	ALT_CFG = setmetatable({ Palette = pal }, { __index = CFG })
end
local function isAlt(p)
	return p:GetAttribute("Skin") == "Alt"
end
local function crystalize(model)
	local mat = CFG.AltMaterial
	if typeof(model) ~= "Instance" or typeof(mat) ~= "EnumItem" then
		return
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Material ~= Enum.Material.Neon and d.Transparency < 1 then
			d.Material = mat
		end
	end
end

local castId = 0
local function nextId()
	castId += 1
	return castId
end

---------------------------------------------------------------------------------------------------
-- targets, damage and impulses
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

local function isEnemy(caster, model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or not model.Parent then
		return false
	end
	for _, m in ipairs(enemies(caster)) do
		if m == model then
			return true
		end
	end
	return false
end

-- one ApplyImpulse per assembly so every body part ends up moving at roughly `vel`
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

-- damage + ragdoll + impulse on one body. Players are tumbled by their own client (it owns their physics); a
-- player standing in a giant form with super-armour only takes the damage.
local function knock(attacker, model, vel, ragTime, amount, keep)
	if vel.Magnitude > 330 then
		vel = vel.Unit * 330
	end
	damage(attacker, model, amount)
	if PvPBal.absorbed and PvPBal.absorbed(model) then
		return -- (2026-11-11) blocked / dodged (ServerScriptService.PvP, BLOCK): no tumble, no fling
	end
	local victim = Players:GetPlayerFromCharacter(model)
	if victim then
		if model:GetAttribute("SuperArmor") then
			return
		end
		if model:GetAttribute("Morphed") then
			vel *= 0.15
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

-- loose physics props get pushed too
local function pushLoose(pos, radius, speed, upBias)
	local ignore = { FXFolder, SwarmFolder }
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
			local dir = ((off.Magnitude > 0.5 and off.Unit or UP) + UP * upBias).Unit
			pcall(function()
				root:ApplyImpulse(dir * speed * 0.6 * k * root.AssemblyMass)
			end)
		end
	end
end

-- breakables in the radius shatter, and NPCs nearby flee
local function worldHooks(p, pos, radius)
	if WorldBlast then
		WorldBlast:Fire(pos, radius, p.UserId)
	end
	if Threat then
		Threat:Fire(pos, radius * 2, 2)
	end
end

-- everything within `radius` is thrown straight out from `pos`, harder the closer it was
local function radialBlast(p, pos, radius, speed, upBias, amount, ragTime, minK)
	minK = minK or 0.35
	for _, m in ipairs(enemies(p)) do
		PvPBal.aimAt(pos) -- (2026-11-10) a giant form answers at its body point nearest the blast, not the caster
		local off = rootOf(m).Position - pos
		local d = off.Magnitude
		if d <= radius then
			local k = 1 - d / radius
			local dir = ((d > 0.5 and off.Unit or randomUnit()) + UP * upBias).Unit
			knock(p, m, dir * speed * (minK + (1 - minK) * k), ragTime, amount * (0.4 + 0.6 * k))
		end
	end
	pushLoose(pos, radius, speed, upBias)
	worldHooks(p, pos, radius * 0.6)
end

-- common gate: alive, not mid-move, off cooldown (`slack` forgives a little latency on quick skills)
local function gate(p, s, skill, slack)
	local char, hum, hrp = liveChar(p)
	if not char or os.clock() < s.busy then
		return nil
	end
	if PvPBal.stunned(p) then -- (2026-11-08) stunned / knocked down in PvP: no moves
		return nil
	end
	local t = now()
	if t + (slack or 0) < (s.cd[skill] or 0) then
		sendCooldown(p, s, skill)
		return nil
	end
	return char, hum, hrp, t
end

local function ffOn(char, duration)
	local ff = Instance.new("ForceField")
	ff.Name = "ShiftShield"
	ff.Visible = false
	ff.Parent = char
	if duration then
		task.delay(duration, function()
			if ff.Parent then
				ff:Destroy()
			end
		end)
	end
	return ff
end

local castRay = RaycastParams.new()
castRay.FilterType = Enum.RaycastFilterType.Exclude
local function worldFilter()
	local ignore = { FXFolder, SwarmFolder }
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
	return ignore
end

local function groundBelow(pos, depth)
	castRay.FilterDescendantsInstances = worldFilter()
	local hit = workspace:Raycast(pos + UP * 4, Vector3.new(0, -(depth or 60), 0), castRay)
	return hit and hit.Position or nil
end

local function impact(pos, radius, rocks, speed)
	if GroundFX then
		GroundFX.impact(pos, radius, rocks, speed)
	end
end

-- a ring of craters round `center`
local function craterRing(center, count, radius, size, speed)
	for i = 1, count do
		local a = (i / count) * math.pi * 2 + math.random() * 0.4
		local at = center + Vector3.new(math.cos(a), 0, math.sin(a)) * (radius + math.random() * radius * 0.2)
		local g = groundBelow(at + UP * 30, 90)
		if g then
			impact(g, size, 2, speed or 80)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- movement, rig scaling, hiding the body under a giant
local function applyMovement(p, s)
	local char, hum = liveChar(p)
	if not hum or not s.base then
		return
	end
	local f = s.form
	local ws, jp, jh = s.base.ws, s.base.jp, s.base.jh
	if f and f.char == char then
		if not f.grown or f.kind == "Founder" then
			ws, jp, jh = 0, 0, 0
		elseif f.kind == "Warrior" then
			local W = CFG.Warrior
			ws = s.base.ws * (1 + (W.Scale - 1) * 0.35) * W.SpeedMul
			jp, jh = s.base.jp * 1.7, s.base.jh * 3
		elseif f.kind == "Colossus" then
			ws, jp, jh = CFG.Colossus.WalkSpeed, 0, 0
		end
	end
	hum.WalkSpeed, hum.JumpPower, hum.JumpHeight = ws, jp, jh
	char:SetAttribute("KitWalkSpeed", ws)
end

-- scales the character a little every frame; lifts it as it grows so the longer legs don't sink into the ground.
-- `keepGoing` (optional) is asked every frame: a form that ended mid-grow stops growing instead of fighting the shrink
local function smoothScale(char, hum, from, to, duration, keepGoing)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end
	local groundPerScale = (hum.HipHeight + hrp.Size.Y / 2) / from
	local t0, cur = os.clock(), from
	while true do
		if keepGoing and not keepGoing() then
			return false
		end
		local a = math.clamp((os.clock() - t0) / duration, 0, 1)
		local sc = from + (to - from) * (a * a * (3 - 2 * a))
		local ok, err = pcall(function()
			char:ScaleTo(sc)
			if sc > cur then
				char:PivotTo(char:GetPivot() + UP * (sc - cur) * groundPerScale)
			end
		end)
		if not ok then
			warn("[ShifterService] ScaleTo failed: " .. tostring(err))
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

local function hideBody(f)
	f.hidden = {}
	local gear = f.char:FindFirstChild("ShifterGear")
	if gear then
		gear:Destroy() -- rebuilt at normal size when the form ends
	end
	for _, d in ipairs(f.char:GetDescendants()) do
		if (d:IsA("BasePart") or d:IsA("Decal")) and d.Transparency < 1 then
			f.hidden[d] = d.Transparency
			d.Transparency = 1
		end
	end
end

local function showBody(f)
	for inst, tr in pairs(f.hidden or {}) do
		if inst.Parent then
			inst.Transparency = tr
		end
	end
	f.hidden = nil
end

-- (2026-11-11, "you lose your pants still when going from titan to human") a SAFETY NET for the avatar's own look.
-- The form's own restores (TitanSkins.undress + showBody) put everything back in every path tried in Studio (X, the
-- timeout, death, a kit switch, back-to-back forms, the moves used in form, the Eren skin's costume landing in the
-- gather), yet the owner's playtests still lose the pants. So each form records the look it starts with
-- (snapshotLook, in beginForm) and when it ends the body is checked against that record a few times (repairLook: after
-- the shrink, again at +2.5 s and +7 s, past the husk): a Shirt / Pants / T-shirt that is missing or blank, a missing
-- BodyColors, or an accessory / face / body part left invisible is put back - unless the player's applied
-- HumanoidDescription changed that clothing slot meanwhile (a fighter skin's costume or the Ultimate Outfit re-dressing
-- the body on purpose). Every repair is warned in the output with the form and the moment, so the path is findable.
local CLOTHES = { Shirt = { "ShirtTemplate", "Shirt" }, Pants = { "PantsTemplate", "Pants" }, ShirtGraphic = { "Graphic", "GraphicTShirt" } }
local function snapshotLook(f)
	local char = f.char
	local hum = char:FindFirstChildOfClass("Humanoid")
	local look = { clothes = {}, vis = {} }
	local okD, desc = pcall(function()
		return hum:GetAppliedDescription()
	end)
	desc = okD and desc or nil
	for cls, spec in pairs(CLOTHES) do
		local c = char:FindFirstChildOfClass(cls)
		if c and c[spec[1]] ~= "" then
			look.clothes[cls] = { template = c[spec[1]], clone = c:Clone(), id = desc and desc[spec[2]] or nil }
		end
	end
	local bc = char:FindFirstChildOfClass("BodyColors")
	look.bodyColors = bc and bc:Clone() or nil
	for _, d in ipairs(char:GetDescendants()) do
		if (d:IsA("BasePart") or d:IsA("Decal")) and d.Transparency < 1 and not d:FindFirstAncestor("ShifterGear") then
			look.vis[d] = d.Transparency
		end
	end
	f.look = look
end
local function repairLook(p, s, f, when)
	local look, char = f.look, f.char
	if not look or s.form or p.Character ~= char or not char.Parent then
		return -- another form stands, or this body is gone
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or math.abs(char:GetScale() - (f.baseScale or 1)) > 0.05 then
		return -- dead, or still shrinking (a later check catches it)
	end
	local okD, desc = pcall(function()
		return hum:GetAppliedDescription()
	end)
	local fixed = {}
	for cls, rec in pairs(look.clothes) do
		local spec = CLOTHES[cls]
		-- a description that now names a different item for this slot re-dressed the body on purpose: leave it
		if not (okD and desc and rec.id ~= nil) or desc[spec[2]] == rec.id then
			local c = char:FindFirstChildOfClass(cls)
			if not c then
				rec.clone:Clone().Parent = char
				table.insert(fixed, cls .. " (was missing)")
			elseif c[spec[1]] == "" then
				c[spec[1]] = rec.template
				table.insert(fixed, cls .. " (was blank)")
			end
		end
	end
	if look.bodyColors and not char:FindFirstChildOfClass("BodyColors") then
		look.bodyColors:Clone().Parent = char
		table.insert(fixed, "BodyColors (was missing)")
	end
	local shown = 0
	for inst, tr in pairs(look.vis) do
		if inst.Parent and inst:IsDescendantOf(char) and inst.Transparency >= 1 then
			inst.Transparency = tr
			shown += 1
		end
	end
	if shown > 0 then
		table.insert(fixed, shown .. " part(s) / decal(s) left invisible")
	end
	if #fixed > 0 then
		warn(string.format("[ShifterService] %s after the %s form (%s): put back %s", p.Name, f.kind, when, table.concat(fixed, ", ")))
	end
end

-- gear: on the body while the kit is equipped and no giant form stands
local function refreshGear(p, s)
	local char, hum = liveChar(p)
	local existing = p.Character and p.Character:FindFirstChild("ShifterGear")
	local want = char ~= nil and p:GetAttribute("Kit") == CFG.KitId and not s.form and math.abs(char:GetScale() - 1) < 0.05
	if want and not existing then
		local ok, err = pcall(TitanSkins.gear, char, CFG)
		if not ok then
			warn("[ShifterService] gear build failed: " .. tostring(err))
		end
	elseif not want and existing then
		existing:Destroy()
	end
end

-- a giant's body left where it stood when the form ends: cut loose, anchored, steaming away (clients fade it)
local function leaveHusk(skin, kind, life)
	for _, d in ipairs(skin:GetDescendants()) do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	for _, d in ipairs(skin:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		elseif d:IsA("ParticleEmitter") then
			d.Rate *= 1.5 -- a last breath of steam (x3 fogged the whole area round a fallen colossus)
		end
	end
	skin.Name = "TitanHusk"
	skin.Parent = FXFolder
	fire("Husk", { model = skin, kind = kind, life = life })
	Debris:AddItem(skin, life + 0.5)
end

---------------------------------------------------------------------------------------------------
-- forms: shared lifecycle
local endSwarm -- (Founder) defined below
local TITAN_FORMS = { "Warrior", "Colossus", "Founder" } -- (2026-11-10) one shared transformation cooldown

local function clearForm(p, s, quiet)
	local f = s.form
	if not f then
		return
	end
	s.form = nil
	s.token += 1
	local char = f.char
	-- (2026-11-10) the avatar's own clothes, colours and face come back NOW, before the form attributes clear: the skin
	-- used to undo itself only when its husk was destroyed 4.5-6 s later, and FighterSkinLook / PerkUltOutfit re-dress
	-- the body on that attribute change (an outfit applied then would have captured the titan's blank clothes)
	if f.skin then
		pcall(TitanSkins.undress, f.skin)
	end
	if f.locked then
		p:SetAttribute("KitLocked", nil)
	end
	if f.ff and f.ff.Parent then
		f.ff:Destroy()
	end
	if char.Parent then
		for _, a in ipairs({ "Morphed", "SuperArmor", "TitanForm", "FormUntil", "ReleaseAt", "FounderCenter" }) do
			char:SetAttribute(a, nil)
		end
	end
	if f.kind == "Founder" then
		endSwarm(f)
	end
	if f.skin and f.skin.Parent then
		leaveHusk(f.skin, f.kind, f.kind == "Colossus" and 6 or 4.5)
	end
	showBody(f)
	-- (2026-11-10) SHARED TITAN COOLDOWN: ending ANY form puts ALL THREE transformations on the ended form's cooldown
	-- (perk-scaled as usual; never shortening a longer lock already running), so leaving the Colossal can't go straight
	-- into the Attack Titan. An Instant Ult Charge bought while the Founding Titan stood (noCooldown) still frees the
	-- Founder itself; the other two keep the shared lock.
	local lockEnd = now() + cdFor(p, f.kind, CFG[f.kind].Cooldown)
	for _, k in ipairs(TITAN_FORMS) do
		if k == "Founder" and (f.noCooldown or (s.ultFree and f.kind ~= "Founder")) then
			-- (a charge bought while another titan stood is kept for the Founder: that ending doesn't re-lock it)
			s.cd[k] = 0
		else
			s.cd[k] = math.max(s.cd[k] or 0, lockEnd)
		end
		sendCooldown(p, s, k)
	end
	local c2, hum, hrp = liveChar(p)
	local standing = c2 == char
	if standing then
		if hrp.Anchored then
			hrp.Anchored = false
		end
		if f.returnTo then
			char:PivotTo(f.returnTo)
		end
	end
	-- every client drops its side of the form (camera, steam field, the set piece) - also when the body died in it
	if not quiet then
		local root = char:FindFirstChild("HumanoidRootPart")
		fire("FormEnd", { userId = p.UserId, kind = f.kind, pos = root and root.Position or f.center or Vector3.zero, scale = char:GetScale() })
	end
	if standing then
		local target = f.baseScale or 1
		if math.abs(char:GetScale() - target) > 0.01 then
			s.busy = os.clock() + 0.9
			local tok = s.token
			task.spawn(function()
				smoothScale(char, hum, char:GetScale(), target, 0.7, function()
					return s.token == tok
				end)
				-- a ScaleTo round trip drifts a little: the body gets its own hip height back exactly
				if char.Parent and f.baseHip and math.abs(char:GetScale() - target) < 0.01 then
					hum.HipHeight = f.baseHip
				end
				applyMovement(p, s)
				refreshGear(p, s)
			end)
		else
			if f.baseHip then
				hum.HipHeight = f.baseHip
			end
			refreshGear(p, s)
		end
	end
	applyMovement(p, s)
	-- (2026-11-11) the safety net: check the body's own look once it is back to size, and again past the husk
	if f.look then
		for _, at in ipairs({ 0.05, 1, 2.5, 7 }) do
			task.delay(at, function()
				local ok, err = pcall(repairLook, p, s, f, string.format("+%.1f s", at))
				if not ok then
					warn("[ShifterService] look check failed: " .. tostring(err))
				end
			end)
		end
	end
end

-- starts a form's entrance; returns the form record and an `alive` check (nil if the form can't start now)
local function beginForm(p, s, kind, entrance)
	local char, hum, hrp, t = gate(p, s, kind)
	if not char or s.form then
		return nil
	end
	s.token += 1
	local tok = s.token
	local f = { kind = kind, char = char, grown = false, untilT = math.huge, locked = true, baseScale = char:GetScale(), baseHip = hum.HipHeight }
	pcall(snapshotLook, f) -- (2026-11-11) the look the form must hand back (repairLook)
	s.form = f
	s.busy = os.clock() + entrance
	char:SetAttribute("Morphed", true)
	p:SetAttribute("KitLocked", true) -- no switching fighters in the middle of a transformation
	f.ff = ffOn(char, entrance + 1)
	applyMovement(p, s)
	local function alive()
		return s.token == tok and s.form == f and liveChar(p) == char
	end
	return f, alive, char, hum, hrp
end

-- the entrance is over: the giant stands. "Release" (X) is accepted from `releaseDelay` s on (the Founder's rise)
local function formReady(p, s, f, duration, releaseDelay)
	f.grown = true
	f.untilT = now() + duration
	f.releaseAt = now() + (releaseDelay or 0)
	f.locked = false
	p:SetAttribute("KitLocked", nil)
	s.busy = 0
	f.char:SetAttribute("TitanForm", f.kind)
	f.char:SetAttribute("FormUntil", f.untilT)
	f.char:SetAttribute("ReleaseAt", f.releaseAt)
	applyMovement(p, s)
end

---------------------------------------------------------------------------------------------------
-- Skill 1: the twin hooks. The caster's client raycasts the cursor and reels its own body in (it owns its physics);
-- the server checks the range and tells every other client where the cables went.
local function castHook(p, s, payload)
	if s.form then
		return
	end
	local T = CFG.Tether
	local char, _, hrp, t = gate(p, s, "Tether", 0.15)
	if not char then
		return
	end
	local target = validPoint(payload.target)
	if not target or (target - hrp.Position).Magnitude > T.Range + 15 then
		return
	end
	s.cd.Tether = t + cdFor(p, "Tether", T.Cooldown)
	fire("Hook", { userId = p.UserId, id = payload.id, target = target, spread = T.Spread })
end

-- the spinning strike: the caster's client dashes at the target; the server lands the hit when the dash gets there
local function castSpin(p, s, payload)
	if s.form then
		return
	end
	local T = CFG.Tether
	local char, _, hrp, t = gate(p, s, "Spin", 0.25)
	if not char then
		return
	end
	local target = payload.target
	if not isEnemy(p, target) then
		return
	end
	local r = rootOf(target)
	if not r or (r.Position - hrp.Position).Magnitude > T.SpinRange + 15 then
		return
	end
	s.cd.Spin = t + cdFor(p, "Spin", T.SpinCooldown)
	local id = nextId()
	fire("Spin", { userId = p.UserId, id = id, target = target, time = T.SpinTime })
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < T.SpinTime + 0.3 do
			RunService.Heartbeat:Wait()
			local c2, _, h2 = liveChar(p)
			if h2 then
				PvPBal.setAim(h2.Position, p) -- (2026-11-10) forms: nearest the dashing caster (the aim is stale here)
			end
			local r2 = target.Parent and rootOf(target)
			if c2 ~= char or not r2 then
				return
			end
			local off = r2.Position - h2.Position
			if off.Magnitude <= T.SpinReach + 2.5 then
				local fl = flatOf(off, flatOf(h2.CFrame.LookVector, Vector3.new(0, 0, -1)))
				knock(p, target, (fl * 0.9 + UP * T.SpinUpBias).Unit * T.SpinImpulse, T.SpinRagdoll, T.SpinDamage)
				worldHooks(p, r2.Position, 8)
				fire("SpinHit", { userId = p.UserId, id = id, pos = r2.Position, dir = fl, target = target })
				return
			end
		end
		fire("SpinMiss", { userId = p.UserId, id = id })
	end)
end

---------------------------------------------------------------------------------------------------
-- Skill 2: the 15-metre form. The caster bites down on a hand while lightning gathers (GatherTime), a bolt hits, the
-- steam explosion throws everything back and the rig grows inside the cloud; the giant roars when it is out.
local function startWarrior(p, s)
	local W = CFG.Warrior
	local f, alive, char, hum, hrp = beginForm(p, s, "Warrior", W.GatherTime + W.GrowTime + 0.6)
	if not f then
		return
	end
	fire("WarriorStart", { userId = p.UserId, pos = hrp.Position, gather = W.GatherTime })
	task.spawn(function()
		task.wait(W.GatherTime)
		if not alive() then
			return
		end
		local pos = hrp.Position
		local g = groundBelow(pos) or (pos - UP * 3)
		fire("WarriorBurst", { userId = p.UserId, pos = pos, ground = g, radius = W.BurstRadius, grow = W.GrowTime, scale = W.Scale })
		radialBlast(p, pos, W.BurstRadius, W.BurstImpulse, 0.65, W.BurstDamage, 4)
		-- (2026-11-07) the burst craters round the feet, never under them: the titan grows up standing right here,
		-- and with craters now lasting 45 s it stood in its own pit for the whole form
		craterRing(g, 6, 13, 5.5, 100)
		craterRing(g, 8, 17, 4.5)
		hideBody(f)
		smoothScale(char, hum, char:GetScale(), W.Scale, W.GrowTime, alive)
		if not alive() then
			return
		end
		local alt = isAlt(p)
		local ok, skin = pcall(TitanSkins.warrior, char, alt and ALT_CFG or CFG)
		if ok then
			f.skin = skin
			if alt then
				crystalize(skin)
			end
		else
			warn("[ShifterService] warrior body failed: " .. tostring(skin))
		end
		char:SetAttribute("SuperArmor", true)
		formReady(p, s, f, W.Duration)
		fire("WarriorOn", { userId = p.UserId, pos = hrp.Position, scale = W.Scale })
		-- the roar: a blast of breath and steam that bowls over everything close
		task.wait(0.4)
		if alive() then
			radialBlast(p, hrp.Position, W.RoarRadius, W.RoarImpulse, 0.4, W.RoarDamage, 2.2, 0.3)
		end
	end)
end

-- M1 in form: a huge alternating punch at the cone in front; the fist hits the ground and cracks it
local function warriorPunch(p, s, f, payload)
	local W = CFG.Warrior
	local char, _, hrp, t = gate(p, s, "Punch", 0.05)
	if not char then
		return
	end
	s.cd.Punch = t + cdFor(p, "Punch", W.PunchCooldown)
	s.punchSide = -(s.punchSide or -1)
	local side = s.punchSide
	local _, flat = aimFrom(hrp.Position, payload, hrp)
	fire("WarriorPunch", { userId = p.UserId, side = side, windup = W.PunchWindup, dir = flat })
	task.delay(W.PunchWindup, function()
		local c2, _, h2 = liveChar(p)
		if s.form ~= f or c2 ~= char then
			return
		end
		local origin = h2.Position
		local half = math.rad(W.PunchArc / 2)
		for _, m in ipairs(enemies(p)) do
			local off = rootOf(m).Position - origin
			local fl = off * FLAT
			local d = fl.Magnitude
			if d <= W.PunchRange and math.abs(off.Y) < 30 and (d < 6 or math.acos(math.clamp(fl.Unit:Dot(flat), -1, 1)) <= half) then
				local k = 1 - d / W.PunchRange
				knock(p, m, (flat * 0.85 + UP * 0.45).Unit * W.PunchImpulse * (0.6 + 0.4 * k), 3.5, W.PunchDamage * (0.6 + 0.4 * k))
			end
		end
		-- the fist comes down on the ground ahead (the punch pose drives it there); the reach scales with the body
		local sc = char:GetScale()
		local at = origin + flat * sc * (W.PunchReach or 3.4) + flat:Cross(UP) * side * sc * 0.55
		local g = groundBelow(at + UP * 10, 60) or at
		impact(g, 3.6, 3, 60)
		pushLoose(at, 16, W.PunchImpulse, 0.4)
		worldHooks(p, at, 10)
		fire("WarriorPunchHit", { userId = p.UserId, pos = g, dir = flat, side = side })
	end)
end

-- the key again in form: a leap, then both fists hammer the ground where it lands
local landRay = RaycastParams.new()
landRay.FilterType = Enum.RaycastFilterType.Exclude
local function warriorSlam(p, s, f, payload)
	local W = CFG.Warrior
	local char, hum, hrp, t = gate(p, s, "Slam")
	if not char then
		return
	end
	s.cd.Slam = t + cdFor(p, "Slam", W.SlamCooldown)
	sendCooldown(p, s, "Slam")
	s.busy = os.clock() + W.SlamAir + 0.5
	local _, flat = aimFrom(hrp.Position, payload, hrp)
	fire("WarriorSlam", { userId = p.UserId, air = W.SlamAir, dir = flat })
	task.spawn(function()
		-- wait for the landing (or the airtime running out)
		local t0 = os.clock()
		task.wait(0.3)
		while os.clock() - t0 < W.SlamAir + 0.6 do
			local c2, h2c, h2 = liveChar(p)
			if s.form ~= f or c2 ~= char then
				return
			end
			landRay.FilterDescendantsInstances = worldFilter()
			local reach = h2c.HipHeight + h2.Size.Y / 2 + 3
			local hit = workspace:Raycast(h2.Position, Vector3.new(0, -reach, 0), landRay)
			if hit and h2.AssemblyLinearVelocity.Y < 5 and os.clock() - t0 > 0.45 then
				break
			end
			RunService.Heartbeat:Wait()
		end
		local c3, _, h3 = liveChar(p)
		if s.form ~= f or c3 ~= char then
			return
		end
		local g = groundBelow(h3.Position, 80) or h3.Position
		radialBlast(p, g, W.SlamRadius, W.SlamImpulse, 0.75, W.SlamDamage, 4.5, 0.4)
		craterRing(g, 6, 11, 6, 110) -- round the landing, not under it (see the burst)
		craterRing(g, 9, 20, 4.2)
		fire("WarriorSlamHit", { userId = p.UserId, pos = g, radius = W.SlamRadius })
		s.busy = 0
	end)
end

---------------------------------------------------------------------------------------------------
-- Skill 3: the 60-metre form. Golden lightning gathers and strikes; a thermal blast levels everything within
-- BlastRadius (breakables shatter), and the rig rises 14x out of the fireball. While it stands, the steam field
-- scalds and shoves everything within SteamRadius of its feet.
local function steamField(p, s, f, alive)
	local C = CFG.Colossus
	while alive() and f.grown do
		local _, hum, h = liveChar(p)
		local feet = h.Position - UP * (hum.HipHeight + h.Size.Y / 2)
		for _, m in ipairs(enemies(p)) do
			PvPBal.aimAt(feet) -- (2026-11-10) forms: nearest the steam field's centre
			local off = rootOf(m).Position - feet
			local fl = off * FLAT
			local d = fl.Magnitude
			if d <= C.SteamRadius and off.Y < 90 and off.Y > -20 then
				local k = 1 - d / C.SteamRadius
				local out = d > 0.5 and fl.Unit or randomFlat()
				knock(p, m, (out + UP * 0.35).Unit * C.SteamImpulse * (0.5 + 0.5 * k), 1.6, C.SteamDamage)
			end
		end
		pushLoose(feet, C.SteamRadius, C.SteamImpulse, 0.3)
		task.wait(C.SteamTick)
	end
end

local function startColossus(p, s)
	local C = CFG.Colossus
	local f, alive, char, hum, hrp = beginForm(p, s, "Colossus", C.GatherTime + 0.25 + C.GrowTime + 0.6)
	if not f then
		return
	end
	fire("ColossusStart", { userId = p.UserId, pos = hrp.Position, gather = C.GatherTime })
	task.spawn(function()
		task.wait(C.GatherTime)
		if not alive() then
			return
		end
		local pos = hrp.Position
		local g = groundBelow(pos) or (pos - UP * 3)
		fire("ColossusStrike", { userId = p.UserId, pos = pos, ground = g })
		task.wait(0.25)
		if not alive() then
			return
		end
		fire("ColossusBlast", { userId = p.UserId, pos = pos, ground = g, radius = C.BlastRadius, grow = C.GrowTime, scale = C.Scale })
		radialBlast(p, pos, C.BlastRadius, C.BlastImpulse, 0.6, C.BlastDamage, 5, 0.45)
		worldHooks(p, pos, C.BlastRadius) -- the blast takes every breakable in its full radius
		craterRing(g, 7, 22, 9, 140) -- round the feet, not under them: the colossus rises out of this spot
		craterRing(g, 10, 28, 6, 110)
		craterRing(g, 12, 46, 5, 90)
		hideBody(f)
		smoothScale(char, hum, char:GetScale(), C.Scale, C.GrowTime, alive)
		if not alive() then
			return
		end
		local alt = isAlt(p)
		local ok, skin = pcall(TitanSkins.colossus, char, alt and ALT_CFG or CFG)
		if ok then
			f.skin = skin
			if alt then
				crystalize(skin)
			end
		else
			warn("[ShifterService] colossus body failed: " .. tostring(skin))
		end
		char:SetAttribute("SuperArmor", true)
		formReady(p, s, f, C.Duration)
		fire("ColossusOn", { userId = p.UserId, pos = hrp.Position, scale = C.Scale, steam = C.SteamRadius })
		steamField(p, s, f, alive)
	end)
end

-- M1 in form: a foot comes down in front and the ground caves in
local function colossusStomp(p, s, f, payload)
	local C = CFG.Colossus
	local char, hum, hrp, t = gate(p, s, "Stomp", 0.05)
	if not char then
		return
	end
	s.cd.Stomp = t + cdFor(p, "Stomp", C.StompCooldown)
	s.stompSide = -(s.stompSide or -1)
	local side = s.stompSide
	local _, flat = aimFrom(hrp.Position, payload, hrp)
	fire("ColossusStomp", { userId = p.UserId, side = side, windup = C.StompWindup, dir = flat })
	task.delay(C.StompWindup, function()
		local c2, h2c, h2 = liveChar(p)
		if s.form ~= f or c2 ~= char then
			return
		end
		local sc = char:GetScale()
		local feet = h2.Position - UP * (h2c.HipHeight + h2.Size.Y / 2)
		local at = feet + flat * sc * 1.6 + flat:Cross(UP) * side * sc * 0.6
		local g = groundBelow(at + UP * 30, 90) or at
		radialBlast(p, g, C.StompRadius, C.StompImpulse, 0.65, C.StompDamage, 3.5, 0.4)
		impact(g, 9, 10, 100)
		craterRing(g, 6, 14, 3.6)
		fire("ColossusStompHit", { userId = p.UserId, pos = g, radius = C.StompRadius })
	end)
end

-- the key again in form: every vent opens at once, a scalding blast of steam in all directions
local function colossusBurst(p, s, f)
	local C = CFG.Colossus
	local char, hum, hrp, t = gate(p, s, "Burst")
	if not char then
		return
	end
	s.cd.Burst = t + cdFor(p, "Burst", C.BurstCooldown)
	sendCooldown(p, s, "Burst")
	s.busy = os.clock() + C.BurstCharge + 0.3
	fire("ColossusBurstCharge", { userId = p.UserId, time = C.BurstCharge })
	task.delay(C.BurstCharge, function()
		local c2, h2c, h2 = liveChar(p)
		if s.form ~= f or c2 ~= char then
			return
		end
		local feet = h2.Position - UP * (h2c.HipHeight + h2.Size.Y / 2)
		fire("ColossusBurst", { userId = p.UserId, pos = h2.Position, feet = feet, radius = C.BurstRadius })
		radialBlast(p, feet + UP * 6, C.BurstRadius, C.BurstImpulse, 0.55, C.BurstDamage, 4.5, 0.45)
		worldHooks(p, feet, C.BurstRadius * 0.7)
		craterRing(feet, 10, 24, 4.5, 100)
		s.busy = 0
	end)
end

---------------------------------------------------------------------------------------------------
-- Skill 4: the skeletal colossus. The ground shakes while the caster calls it (GatherTime); it rises over the cast
-- point (RiseTime) and stays there. The caster's body waits hidden at its heart, protected, while their view goes
-- overhead. A roar every RoarEvery seconds flattens everything in the territory; waves of giants spawn and hunt.
local swarmAnims
local DEFAULT_ANIMS = {
	idle = "http://www.roblox.com/asset/?id=507766388",
	walk = "http://www.roblox.com/asset/?id=507777826",
}

local function setAnim(fo, key, speed)
	if fo.current ~= key then
		local old = fo.current and fo.tracks[fo.current]
		if old then
			old:Stop(0.25)
		end
		fo.current = key
		local new = fo.tracks[key]
		if new then
			new:Play(0.25)
		end
	end
	local tr = fo.tracks[key]
	if tr and speed then
		tr:AdjustSpeed(speed)
	end
end

-- the swarm's bodies: a few shapes are built once per server and cloned per giant (building a rig from a
-- HumanoidDescription is slow, and it used to happen for every single giant)
local SWARM_SHAPES = {
	{ head = 1.2, width = 1.05, depth = 1.05, height = 1.0, prop = 0.25, body = 0.15 },
	{ head = 1.1, width = 1.2, depth = 1.15, height = 0.95, prop = 0, body = 0.3 },
	{ head = 1.35, width = 0.92, depth = 0.95, height = 1.06, prop = 0.6, body = 0 },
}
local swarmTemplates, swarmBuilding, swarmFailUntil = {}, {}, {}
local function swarmTemplate(i)
	while swarmBuilding[i] do
		task.wait(0.05)
	end
	if swarmTemplates[i] then
		return swarmTemplates[i]
	end
	if os.clock() < (swarmFailUntil[i] or 0) then
		return nil
	end
	swarmBuilding[i] = true
	local sh = SWARM_SHAPES[i]
	local desc = Instance.new("HumanoidDescription")
	desc.HeadScale, desc.WidthScale, desc.DepthScale, desc.HeightScale = sh.head, sh.width, sh.depth, sh.height
	desc.ProportionScale, desc.BodyTypeScale = sh.prop, sh.body
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	swarmBuilding[i] = nil
	if not ok or not rig or not rig:FindFirstChildOfClass("Humanoid") or not rig:FindFirstChild("HumanoidRootPart") then
		warn("[ShifterService] could not build a swarm giant: " .. tostring(rig))
		swarmFailUntil[i] = os.clock() + 20
		return nil
	end
	local animate = rig:FindFirstChild("Animate")
	if animate then
		if not swarmAnims then
			swarmAnims = {}
			for _, key in ipairs({ "idle", "walk" }) do
				local sv = animate:FindFirstChild(key)
				local anim = sv and sv:FindFirstChildOfClass("Animation")
				swarmAnims[key] = (anim and anim.AnimationId ~= "") and anim.AnimationId or DEFAULT_ANIMS[key]
			end
		end
		animate:Destroy()
	end
	rig.Name = "SwarmGiant"
	swarmTemplates[i] = rig
	return rig
end

local function spawnFollower(p, f, alive)
	local F = CFG.Founder
	local rng = f.rng
	local tpl = swarmTemplate(rng:NextInteger(1, #SWARM_SHAPES))
	if not tpl or not alive() then
		return -- (the form can end while the first body of a shape is being built)
	end
	local rig = tpl:Clone()
	local hum = rig:FindFirstChildOfClass("Humanoid")
	local hrp = rig:FindFirstChild("HumanoidRootPart")
	local skinCfg = f.alt and ALT_CFG or CFG
	local flesh = skinCfg.Palette.Flesh[rng:NextInteger(1, #skinCfg.Palette.Flesh)]
	for _, d in ipairs(rig:GetChildren()) do
		if d:IsA("BasePart") and d ~= hrp then
			d.Color = flesh
		end
	end
	local bc = rig:FindFirstChildOfClass("BodyColors")
	if bc then
		bc.HeadColor3, bc.TorsoColor3 = flesh, flesh
		bc.LeftArmColor3, bc.RightArmColor3, bc.LeftLegColor3, bc.RightLegColor3 = flesh, flesh, flesh, flesh
	end
	local k = rng:NextNumber(F.FollowerScale[1], F.FollowerScale[2])
	rig:ScaleTo(k)
	pcall(TitanSkins.swarmling, rig, skinCfg, rng)
	if f.alt then
		crystalize(rig)
	end
	hum.MaxHealth, hum.Health = 400, 400
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.WalkSpeed = F.FollowerSpeed * rng:NextNumber(0.8, 1.2)
	local a = rng:NextNumber(0, math.pi * 2)
	local spot = f.center + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(35, 70)
	local g = groundBelow(spot + UP * 60, 140) or spot
	local standY = g.Y + hum.HipHeight + hrp.Size.Y / 2 + 0.2
	rig:PivotTo(CFrame.lookAt(Vector3.new(spot.X, standY, spot.Z), Vector3.new(spot.X, standY, spot.Z) + (spot - f.center) * FLAT))
	rig:SetAttribute("SwarmOwner", p.UserId)
	rig:SetAttribute("SwarmCast", f.castId)
	rig.Parent = SwarmFolder
	pcall(function()
		hrp:SetNetworkOwner(nil)
	end)
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local tracks = {}
	for key, id in pairs(swarmAnims or DEFAULT_ANIMS) do
		local an = Instance.new("Animation")
		an.AnimationId = id
		local okT, tr = pcall(function()
			return animator:LoadAnimation(an)
		end)
		if okT and tr then
			tr.Looped = true
			tr.Priority = key == "idle" and Enum.AnimationPriority.Idle or Enum.AnimationPriority.Movement
			tracks[key] = tr
		end
	end
	local fo = { model = rig, hum = hum, hrp = hrp, tracks = tracks, scale = k, nextAttack = os.clock() + 1, nextWander = 0, nextThink = 0 }
	setAnim(fo, "idle")
	table.insert(f.followers, fo)
	fire("SwarmSpawn", { userId = p.UserId, pos = Vector3.new(spot.X, g.Y, spot.Z), scale = k })
end

-- the swarm's brains, run on the founder's own tick (4 Hz): each giant re-picks its prey twice a second and chases it
local function updateSwarm(p, f)
	local F = CFG.Founder
	local clock = os.clock()
	local list
	for i = #f.followers, 1, -1 do
		local fo = f.followers[i]
		if not fo.model.Parent or not fo.hrp.Parent or fo.hum.Health <= 0 or fo.hrp.Position.Y < -200 then
			table.remove(f.followers, i)
			if fo.model.Parent then
				fo.model:SetAttribute("Evaporating", true)
				Debris:AddItem(fo.model, 2)
			end
		else
			if clock >= fo.nextThink then
				fo.nextThink = clock + 0.5
				list = list or enemies(p)
				local best, bd = nil, math.huge
				for _, m in ipairs(list) do
					PvPBal.setAim(fo.hrp.Position, p) -- (2026-11-10) forms: nearest this swarm giant
					local r = rootOf(m)
					local h = m:FindFirstChildOfClass("Humanoid")
					if r and h and h.Health > 0 and (r.Position - f.center).Magnitude <= F.FollowerHunt then
						local d = (r.Position - fo.hrp.Position).Magnitude
						if d < bd then
							best, bd = m, d
						end
					end
				end
				fo.target = best
			end
			local target = fo.target
			PvPBal.setAim(fo.hrp.Position, p)
			local tr = target and target.Parent and rootOf(target)
			if tr then
				fo.hum:MoveTo(tr.Position)
				local reach = 3.2 * fo.scale + 3
				if (tr.Position - fo.hrp.Position).Magnitude <= reach and clock >= fo.nextAttack then
					fo.nextAttack = clock + 1.4
					fire("SwarmSwipe", { model = fo.model })
					task.delay(0.3, function()
						if fo.hrp.Parent then
							PvPBal.setAim(fo.hrp.Position, p)
						end
						local r = target.Parent and rootOf(target)
						if not r or not fo.model.Parent or not fo.hrp.Parent or fo.hrp.Anchored then
							return
						end
						local off = r.Position - fo.hrp.Position
						if off.Magnitude <= reach * 1.4 then
							local fl = flatOf(off, flatOf(fo.hrp.CFrame.LookVector, Vector3.zAxis))
							knock(p, target, (fl * 0.8 + UP * 0.55).Unit * F.FollowerImpulse, 2.8, F.FollowerDamage)
						end
					end)
				end
			else
				fo.target = nil
				if clock >= fo.nextWander then
					fo.nextWander = clock + 3 + math.random() * 2
					fo.hum:MoveTo(f.center + randomFlat() * (20 + math.random() * 60))
				end
			end
			local speed = (fo.hrp.AssemblyLinearVelocity * FLAT).Magnitude
			if speed > 2 then
				setAnim(fo, "walk", math.clamp(speed / (12 * fo.scale), 0.35, 1.6))
			else
				setAnim(fo, "idle")
			end
		end
	end
end

endSwarm = function(f)
	for _, fo in ipairs(f.followers or {}) do
		if fo.model.Parent then
			fo.model:SetAttribute("Evaporating", true)
			for _, tr in pairs(fo.tracks) do
				pcall(function()
					tr:Stop(0.3)
				end)
			end
			local pos = fo.hrp.Parent and fo.hrp.Position
			if pos then
				fo.hrp.Anchored = true
			end
			fire("SwarmEvaporate", { model = fo.model, pos = pos, scale = fo.scale })
			Debris:AddItem(fo.model, 1.8)
		end
	end
	f.followers = {}
end

local function founderRoar(p, f)
	local F = CFG.Founder
	fire("FounderRoar", { userId = p.UserId, pos = f.center, radius = F.Radius })
	for _, m in ipairs(enemies(p)) do
		PvPBal.aimAt(f.center) -- (2026-11-10) forms: nearest the roar's centre
		local off = rootOf(m).Position - f.center
		local fl = off * FLAT
		if fl.Magnitude <= F.Radius and math.abs(off.Y) < 80 then
			-- flattened: a shove outward and down, then left lying there
			local out = fl.Magnitude > 0.5 and fl.Unit or randomFlat()
			knock(p, m, (out + UP * 0.15).Unit * F.RoarImpulse, F.RoarRagdoll, F.RoarDamage)
		end
	end
	pushLoose(f.center, F.Radius, F.RoarImpulse * 2, 0.2)
	if Threat then
		Threat:Fire(f.center, F.Radius * 2, 3)
	end
end

local function startFounder(p, s)
	local F = CFG.Founder
	local f, alive, char, hum, hrp = beginForm(p, s, "Founder", F.GatherTime + 0.6)
	if not f then
		return
	end
	s.ultFree = nil -- (2026-11-10) a bought ult charge is spent on this Founder
	f.followers = {}
	f.alt = isAlt(p) -- (the swarm giants of a CRYSTAL TITAN are crystal too)
	f.rng = Random.new(math.floor(os.clock() * 1000) % 100000)
	f.castId = nextId() -- tags this cast's swarm, so a giant that outlives it is swept up
	f.returnTo = hrp.CFrame
	local look = flatOf(hrp.CFrame.LookVector, Vector3.new(0, 0, -1))
	f.center = groundBelow(hrp.Position) or (hrp.Position - UP * 3)
	f.look = look
	fire("FounderStart", { userId = p.UserId, pos = f.center, gather = F.GatherTime, dir = look })
	hrp.Anchored = true
	task.spawn(function()
		task.wait(F.GatherTime)
		if not alive() then
			return
		end
		local seed = f.rng:NextInteger(1, 1e6)
		f.seed = seed -- (a late joiner gets the same set piece)
		fire("FounderRise", { userId = p.UserId, pos = f.center, dir = look, rise = F.RiseTime, duration = F.Duration, radius = F.Radius, seed = seed })
		radialBlast(p, f.center, F.RiseRadius, F.RiseImpulse, 0.75, F.RiseDamage, 4)
		impact(f.center, 12, 18, 120)
		craterRing(f.center, 10, 34, 5.5, 100)
		hideBody(f)
		-- the caster waits at the heart of the construct. (2026-11-10) Shielded only while it RISES (the entrance, when X
		-- is refused too); after that it takes hits like any player (it used to be untouchable for all 29 s). Anchored
		-- there, it is super-armoured like the other two titans: no tumble, and no stun locking its spears / rumbling
		if f.ff and f.ff.Parent then
			f.ff:Destroy()
		end
		f.ff = ffOn(char, F.RiseTime)
		hrp.CFrame = CFrame.lookAt(f.center + UP * 4, f.center + UP * 4 + look)
		char:SetAttribute("FounderCenter", f.center)
		char:SetAttribute("SuperArmor", true)
		formReady(p, s, f, F.RiseTime + F.Duration, F.RiseTime)
		task.wait(F.RiseTime)
		local nextRoar, nextSpawn = 0, 0
		while alive() do
			local clock = os.clock()
			if clock >= nextRoar then
				nextRoar = clock + F.RoarEvery
				founderRoar(p, f)
			end
			if clock >= nextSpawn then
				nextSpawn = clock + F.SpawnEvery
				for _ = 1, F.SpawnCount do
					if #f.followers < F.MaxFollowers and alive() then
						spawnFollower(p, f, alive)
						task.wait(0.15)
					end
				end
			end
			updateSwarm(p, f)
			task.wait(0.25)
		end
	end)
end

-- M1 in form: a bone spear tears up out of the ground at the cursor
local function boneSpear(p, s, f, payload)
	local F = CFG.Founder
	local char, _, _, t = gate(p, s, "Spear", 0.05)
	if not char then
		return
	end
	local target = validPoint(payload.target)
	if not target then
		return
	end
	local off = (target - f.center) * FLAT
	if off.Magnitude > F.SpearRange then
		target = f.center + off.Unit * F.SpearRange + UP * (target.Y - f.center.Y)
	end
	local g = groundBelow(target + UP * 30, 120) or target
	s.cd.Spear = t + cdFor(p, "Spear", F.SpearCooldown)
	fire("BoneSpearWarn", { userId = p.UserId, pos = g, delay = F.SpearDelay, radius = F.SpearRadius })
	task.delay(F.SpearDelay, function()
		if s.form ~= f then
			return
		end
		fire("BoneSpear", { userId = p.UserId, pos = g, radius = F.SpearRadius })
		radialBlast(p, g, F.SpearRadius, F.SpearImpulse, 1.8, F.SpearDamage, 3.5, 0.6)
		impact(g, 4.5, 6, 80)
	end)
end

-- the key again in form: a wall of giants marches out along the aim, trampling everything in its path
local function rumble(p, s, f, payload)
	local F = CFG.Founder
	local char, _, _, t = gate(p, s, "Rumble")
	if not char then
		return
	end
	s.cd.Rumble = t + cdFor(p, "Rumble", F.RumbleCooldown)
	sendCooldown(p, s, "Rumble")
	local target = validPoint(payload.target)
	local dir = target and flatOf(target - f.center, f.look) or f.look
	local origin = f.center + dir * 25
	local across = dir:Cross(UP)
	fire("Rumble", {
		userId = p.UserId, origin = origin, dir = dir, width = F.RumbleWidth, count = F.RumbleCount,
		speed = F.RumbleSpeed, length = F.RumbleLength, seed = math.random(1, 1e6),
	})
	task.spawn(function()
		local hitSet = {}
		local t0 = os.clock()
		local nextImpact = 0
		while true do
			local front = math.min((os.clock() - t0) * F.RumbleSpeed, F.RumbleLength)
			local frontC = origin + dir * front
			for _, m in ipairs(enemies(p)) do
				if not hitSet[m] then
					-- (2026-11-10) forms: nearest the marching front (a line across the wall)
					PvPBal.aimSeg(m, frontC - across * (F.RumbleWidth / 2), frontC + across * (F.RumbleWidth / 2))
					local off = rootOf(m).Position - origin
					local along = off:Dot(dir)
					if along <= front + 8 and along >= front - 18 and math.abs(off:Dot(across)) <= F.RumbleWidth / 2 then
						hitSet[m] = true
						knock(p, m, (dir * 0.75 + UP * 0.7).Unit * F.RumbleImpulse, 4.5, F.RumbleDamage)
					end
				end
			end
			if front >= nextImpact then
				nextImpact += 26
				for j = -1, 1 do
					local at = origin + dir * front + across * (j * F.RumbleWidth * 0.33 + (math.random() - 0.5) * 10)
					local g = groundBelow(at + UP * 40, 120)
					if g then
						impact(g, 4.5, 2, 70)
					end
				end
				pushLoose(origin + dir * front, F.RumbleWidth * 0.5, F.RumbleImpulse, 0.6)
				worldHooks(p, origin + dir * front, F.RumbleWidth * 0.5)
			end
			if front >= F.RumbleLength then
				break
			end
			task.wait(0.08)
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- spawning, kit switching, requests, timers
local function onCharacter(p, char)
	local s = getState(p)
	s.token += 1
	s.busy = 0
	if s.form then
		clearForm(p, s, true)
	end
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then
		s.base = { ws = hum.WalkSpeed, jp = hum.JumpPower, jh = hum.JumpHeight }
		-- dying inside a form ends it at once (husk, swarm, every client's set piece and camera), not at the respawn
		hum.Died:Connect(function()
			local s2 = state[p]
			if s2 and s2.form and s2.form.char == char then
				clearForm(p, s2, false)
			end
		end)
	end
	-- the gear goes on once the avatar's parts have finished loading (they replace the placeholder limbs)
	if not p:HasAppearanceLoaded() then
		local done = false
		local conn = p.CharacterAppearanceLoaded:Connect(function()
			done = true
		end)
		local t0 = os.clock()
		while not done and os.clock() - t0 < 6 do
			task.wait(0.1)
		end
		conn:Disconnect()
	end
	task.wait(0.2)
	if p.Character == char then
		refreshGear(p, s)
	end
end

local function onPlayer(p)
	if p.Character then
		task.spawn(onCharacter, p, p.Character)
	end
	p.CharacterAdded:Connect(function(char)
		onCharacter(p, char)
	end)
	-- switching away from this kit ends a standing form and takes the gear off; switching to it puts the gear on
	p:GetAttributeChangedSignal("Kit"):Connect(function()
		local s = getState(p)
		if p:GetAttribute("Kit") ~= CFG.KitId and s.form then
			clearForm(p, s, false)
		end
		refreshGear(p, s)
	end)
end
for _, p in ipairs(Players:GetPlayers()) do
	onPlayer(p)
end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(p)
	local s = state[p]
	if s and s.form then
		clearForm(p, s, false) -- every client drops the set piece now, not when it would have timed out
	end
	state[p] = nil
end)

-- a client that has just started gets every skeletal colossus already standing (the other two forms are welded to
-- bodies, so they replicate by themselves)
local function syncFounders(p)
	for other, s in pairs(state) do
		local f = s.form
		if other ~= p and f and f.kind == "Founder" and f.grown and f.center and f.seed then
			local left = f.untilT - now()
			if left > 1 then
				Broadcast:FireClient(p, "FounderRise", {
					userId = other.UserId, pos = f.center, dir = f.look, rise = 0.05, duration = left,
					radius = CFG.Founder.Radius, seed = f.seed, sync = true,
				})
			end
		end
	end
end

Request.OnServerEvent:Connect(function(p, action, payload)
	local s = getState(p)
	if typeof(action) ~= "string" or not rateOk(s) then
		return
	end
	if type(payload) ~= "table" then
		payload = {}
	end
	-- sent once by a client as it starts: the set pieces already standing
	if action == "Sync" then
		if not s.synced then
			s.synced = true
			syncFounders(p)
		end
		return
	end
	if p:GetAttribute("Kit") ~= CFG.KitId then
		return
	end
	local f = s.form
	local grown = f and f.grown and f.char == p.Character
	if action == "Release" then
		-- X: the form ends early through its normal end path (husk, scale back, the normal cooldown). Refused while
		-- the entrance is still playing, i.e. only once the form is fully up (the Founder: after its rise)
		if grown and now() >= (f.releaseAt or 0) then
			clearForm(p, s, false)
		end
	elseif action == "Hook" then
		-- (2026-11-08) "while in ... the titans players shouldn't be able to use the other abilities": no ODM gear in a
		-- titan (its own M1, its key-again move and X are all a titan gets; the other titans were already refused)
		if not f then
			castHook(p, s, payload)
		end
	elseif action == "Unhook" then
		fire("Unhook", { userId = p.UserId, id = payload.id })
	elseif action == "Spin" then
		if not f then
			castSpin(p, s, payload)
		end
	elseif action == "Warrior" then
		if not f then
			startWarrior(p, s)
		elseif grown and f.kind == "Warrior" then
			warriorSlam(p, s, f, payload)
		end
	elseif action == "Colossus" then
		if not f then
			startColossus(p, s)
		elseif grown and f.kind == "Colossus" then
			colossusBurst(p, s, f)
		end
	elseif action == "Founder" then
		if not f then
			startFounder(p, s)
		elseif grown and f.kind == "Founder" then
			rumble(p, s, f, payload)
		end
	elseif action == "TitanM1" and grown then
		if f.kind == "Warrior" then
			warriorPunch(p, s, f, payload)
		elseif f.kind == "Colossus" then
			colossusStomp(p, s, f, payload)
		elseif f.kind == "Founder" then
			boneSpear(p, s, f, payload)
		end
	end
end)

local nextSweep = 0
RunService.Heartbeat:Connect(function()
	local t = now()
	for p, s in pairs(state) do
		local f = s.form
		if f and f.grown and (p.Character ~= f.char or t >= f.untilT) then
			clearForm(p, s, p.Character ~= f.char)
		end
	end
	-- belt and braces, every 2 s: a swarm giant whose colossus is gone (a spawn that finished after the end, an error
	-- mid-cast) is removed
	local clock = os.clock()
	if clock >= nextSweep then
		nextSweep = clock + 2
		for _, m in ipairs(SwarmFolder:GetChildren()) do
			if not m:GetAttribute("Evaporating") then
				local owner = Players:GetPlayerByUserId(m:GetAttribute("SwarmOwner") or 0)
				local s = owner and state[owner]
				local f = s and s.form
				if not (f and f.kind == "Founder" and f.castId ~= nil and f.castId == m:GetAttribute("SwarmCast")) then
					m:Destroy()
				end
			end
		end
	end
end)

-- Studio-only test hook (2026-11-07, kits-D): ShifterServerDebug:Invoke("state", player) -> { form, grown, cd, now }
-- (cd = the server's cooldown END times, compare with now; checks the perk cooldown scaling and the ult reset)
if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "ShifterServerDebug"
	hook.OnInvoke = function(cmd, a)
		if cmd == "state" then
			local s = state[a]
			return s and { form = s.form and s.form.kind, grown = s.form and s.form.grown, cd = table.clone(s.cd), now = now(), alt = typeof(a) == "Instance" and isAlt(a) } or nil
		end
		return nil
	end
	hook.Parent = script
end

-- PERKS (2026-11-07, kits-D): Instant Ult Charge. ShopService fires ServerStorage.PerkHooks.UltReset(player) after the
-- purchase is saved; a Shifter player's Founding Titan (and its inner moves) is ready at once. Bought while the titan
-- stands, its ending starts no cooldown either.
task.spawn(function()
	local hooks = game:GetService("ServerStorage"):WaitForChild("PerkHooks", 30)
	local ev = hooks and hooks:WaitForChild("UltReset", 30)
	if not (ev and ev:IsA("BindableEvent")) then
		warn("[ShifterService] PerkHooks.UltReset not found: the instant ult product does nothing for the Shifter")
		return
	end
	ev.Event:Connect(function(p)
		if typeof(p) ~= "Instance" or not p:IsA("Player") or p:GetAttribute("Kit") ~= CFG.KitId then
			return
		end
		local s = getState(p)
		s.cd.Founder, s.cd.Rumble, s.cd.Spear = 0, 0, 0
		if s.form and s.form.kind == "Founder" then
			s.form.noCooldown = true
		else
			-- (2026-11-10) the shared titan lock: the charge clears the Founder's slot only (the Attack / Colossal keep
			-- theirs), and holds until the Founder is used, so an Attack Titan ending meanwhile can't re-lock it
			s.ultFree = true
		end
		sendCooldown(p, s, "Founder")
		sendCooldown(p, s, "Rumble")
	end)
end)

print("[ShifterService] online")
