--!nocheck
-- ServerScriptService.Sandbox.Powers (2026-11-14, owner: "make it to where the injuries are properly reflected in what
-- the anime ability does ... hollow purple usually puts like a huge hole in a persons body while the rasenshuriken
-- puts very [small] but large amounts of holes in a body ... do this for all the abilities and characters").
-- Every fighter's hit on a dummy already passes ServerScriptService.PvP.dmg -> Sandbox.Main.bodyHit. That hook used to
-- know only the fighter (one wound type per kit). This module knows the MOVE:
--   1. Powers.resolve() reads the call stack of the hit: the kit script and the cast function it is in (castPalm,
--      runPurple, ZangetsuServer.Moves.Getsuga ...) name the move. No kit script had to change for it. A hit made
--      from an unnamed inner function is found by its line (LINES, built by Powers.Lines - see the end of this file).
--   2. MOVES[kit][move] = { recipe, options }: what that move leaves on a body, built from Sandbox.Injury (what
--      broke, bled, came off) and Sandbox.Wounds (what you see).
-- A move with no entry falls back to Main's old per-kit wound. TRUE damage (written straight to Health: Sukuna's
-- world cut, Zenitsu's Thunder God, Goku's Silver Flash) never passed PvP.dmg, so those three kits now call
-- PvP.trueHit just before they write it. Gojo's hitNPC also leaves PvP.aimLine = the orb's real line.
-- Studio: Main.Debug:Invoke("powers", n) = the last hits and how each was read; ("powers", "seen") = a count per
-- move; ("powers", "unknown") = hits no move claimed; ("power", model, kit, move, damage, player?, from?) = one
-- move's wound on a body without casting it.
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Injury = require(script.Parent:WaitForChild("Injury"))
local Wounds = require(script.Parent:WaitForChild("Wounds"))
local Gore = require(script.Parent:WaitForChild("Gore"))
local PvP = require(ServerScriptService:WaitForChild("PvP"))
local K = Gore.COLORS
local C = Color3.fromRGB

local Powers = {}
local STUDIO = RunService:IsStudio()
local DENT, CHARRED, SEARED = C(132, 100, 134), C(34, 24, 22), C(74, 26, 22)

------------------------------------------------------------------------------------------- which move is landing
local S = "ServerScriptService."
local SRC = {
	[S .. "GojoServer.CombatService"] = { kit = "Limitless", fn = { hitNPC = "Purple", runPurple = "Purple", redBlast = "Red", runRed = "Red", collapseDomain = "Domain", runDomain = "Domain" } },
	[S .. "VulpineServer.KitServer"] = { kit = "Vulpine", fn = { castSphere = "Sphere", runVortex = "Vortex", castDisc = "Disc", detonateBomb = "Bomb", flyBomb = "Bomb", castBomb = "Bomb", castClaw = "Claw",
		toggleMorph = "Morph", endMorph = "Morph", releaseMorph = "Morph" } },
	[S .. "GodspeedServer"] = { kit = "Godspeed", fn = { castPalm = "Palm", castThunder = "Thunder", castEcho = "Echo", castGodspeed = "Godspeed" } },
	[S .. "OneForAllServer"] = { kit = "OneForAll", fn = { castAirForce = "AirForce", castDetroit = "Detroit", castBlackwhip = "Blackwhip", castOFA = "OFA" } },
	[S .. "TempestServer.TempestService"] = { kit = "Tempest", fn = { castLance = "Lance", castPulse = "Pulse", castArrow = "Arrow", toggleGuardian = "GuardianBurst", endGuardian = "GuardianBurst",
		releaseGuardian = "GuardianBurst", castSlash = "GuardianSlash", onPlayer = "GuardianShield" } },
	[S .. "CarverServer.CarverService"] = { kit = "Carver", fn = { castCleave = "Cleave", castCleaveLine = "Cleave", burstFuga = "Fuga", flyFuga = "Fuga", castFuga = "Fuga", castSever = "Sever", castShrine = "Shrine" } },
	[S .. "ShifterServer.ShifterService"] = { kit = "Shifter", fn = { castSpin = "Spin", castHook = "Spin", startWarrior = "TitanBurst", warriorPunch = "TitanPunch", warriorSlam = "TitanSlam", steamField = "Steam",
		startColossus = "ColossusBurst", colossusStomp = "Stomp", colossusBurst = "ColossusBurst", founderRoar = "Roar", startFounder = "Rise", boneSpear = "Spear", rumble = "Rumble",
		updateSwarm = "Bite", spawnFollower = "Bite" } },
	[S .. "AscendantServer.AscendantService"] = { kit = "Ascendant", fn = { castBeam = "Beam", warpKick = "Warp", castWarp = "Warp", castSurge = "Surge", startForm = "Surge", castFlurry = "Flurry", castInstinct = "Instinct",
		castStrike = "M1" } },
	[S .. "StormdrawServer.StormdrawService"] = { kit = "Stormdraw", fn = { castSlash = "M1", castFlash = "Flash", castChain = "Chain", castDragon = "Dragon" } },
}
local MODS = { ZangetsuServer = "Zangetsu", GomuServer = "Gomu" }
local LINES = {} -- [script path] = { { firstLine, "functionName" }, ... } ascending; filled from the child module Lines
do
	local L = script:FindFirstChild("Lines")
	local ok, t = pcall(function()
		return L and require(L)
	end)
	if ok and type(t) == "table" then
		LINES = t
	end
end
local stale = {}
local function byLine(src, line)
	local T = LINES[src]
	if not T or stale[src] then
		return nil
	end
	local name
	for _, e in ipairs(T) do
		if e[1] <= line then
			name = e[2]
		else
			break
		end
	end
	return name
end
-- -> kit, move, frames (a readable trail, Studio only)
function Powers.resolve()
	local kit, move, sub
	local trail = STUDIO and {} or nil
	for level = 2, 40 do
		local src, name, line = debug.info(level, "snl")
		if src == nil then
			break
		end
		local T = SRC[src]
		if T then
			if trail and #trail < 7 then
				table.insert(trail, (name ~= "" and name or "?") .. "@" .. tostring(line))
			end
			if not move then
				local mv = T.fn[name]
				if not mv then -- an inner function, named or not: the top-level function its line lies in
					local outer = byLine(src, line)
					mv = outer and outer ~= name and T.fn[outer]
					if trail and mv then
						trail[#trail] = trail[#trail] .. "(in " .. outer .. ")"
					end
				end
				if mv then
					kit, move = T.kit, mv
				end
			end
			-- a named function whose line no longer matches the table: the kit script was edited since Lines was built
			if name ~= "" and LINES[src] and not stale[src] then
				local f = debug.info(level, "f")
				local def = f and debug.info(f, "l")
				for _, e in ipairs(LINES[src]) do
					if e[2] == name then
						if def and e[1] ~= def then
							stale[src] = true
							warn("[Powers] " .. src .. " changed since Powers.Lines was built (" .. name .. " moved): inner-function hits there fall back to the kit's plain wound. Rebuild Lines (see the end of Sandbox.Powers).")
						end
						break
					end
				end
			end
		else
			local server, mod = string.match(src, "^ServerScriptService%.(%w+)%.Moves%.(%w+)$")
			if server and MODS[server] then
				if trail and #trail < 7 then
					table.insert(trail, mod .. ":" .. (name ~= "" and name or "?") .. "@" .. tostring(line))
				end
				if not move then
					kit, move = MODS[server], mod
				end
				if move == mod and not sub and name ~= "" then
					sub = name -- the function inside that move's module (Hollow: roar / finisher)
				end
			elseif trail and #trail < 7 and (string.find(src, "ZangetsuServer", 1, true) or string.find(src, "GomuServer", 1, true)) then
				table.insert(trail, "Core:" .. (name ~= "" and name or "?") .. "@" .. tostring(line))
			end
		end
	end
	return kit, move, trail and table.concat(trail, " < ") or nil, sub
end

---------------------------------------------------------------------------------------------------------- helpers
local ORDER = Injury.ORDER
local function P(m, n)
	return m:FindFirstChild(n)
end
local function rnd(a, b)
	return a + (b - a) * math.random()
end
local function sgn()
	return math.random() < 0.5 and -1 or 1
end
local function one(m, names)
	local list = {}
	for _, n in ipairs(names) do
		local p = m:FindFirstChild(n)
		if p then
			table.insert(list, p)
		end
	end
	return list[math.random(math.max(#list, 1))]
end
local ARMS = { "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm" }
local LEGS = { "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }
local LIMBS = { "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }
local CORE = { "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg" }
-- where a blow aimed at "the body" lands: the trunk mostly, the big limbs, now and then the neck
local BODY = { "UpperTorso", "UpperTorso", "UpperTorso", "UpperTorso", "LowerTorso", "Head", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg", "LeftLowerArm", "RightLowerLeg" }
-- the part an attack from ctx.from most likely landed on (the nearer, the likelier)
local function near(ctx)
	local list = {}
	for _, n in ipairs(ORDER) do
		local p = ctx.model:FindFirstChild(n)
		if p then
			table.insert(list, { p, ctx.from and (p.Position - ctx.from).Magnitude or math.random() })
		end
	end
	if #list == 0 then
		return nil
	end
	table.sort(list, function(a, b)
		return a[2] < b[2]
	end)
	local r = math.random()
	local i = (r < 0.42) and 1 or ((r < 0.72) and 2 or ((r < 0.88) and 3 or 4))
	return list[math.min(i, #list)][1]
end
-- a point outside the part on the attacker's side (Sandbox.Wounds puts the mark on the face nearest it)
local function toward(ctx, part, spread, d)
	spread = spread or 0.5
	local cf = part.CFrame
	return part.Position - (d or ctx.dir) * 3 + cf.RightVector * ((math.random() - 0.5) * part.Size.X * spread) + cf.UpVector * ((math.random() - 0.5) * part.Size.Y * spread)
end
local function hurt(ctx, part, kind, amount, o)
	if not part or part.Parent ~= ctx.model then
		return
	end
	local d = (o and o.dir) or ctx.dir
	local info = { part = part, pos = (o and o.pos) or (part.Position - d * 0.6), type = kind, amount = amount, attacker = ctx.by, dir = d }
	if o then
		info.nodraw, info.nospray, info.nosever = o.nodraw, o.nospray, o.nosever
	end
	Injury.hit(ctx.model, info)
end
local function say(ctx, text, sev)
	Injury.say(ctx.model, text, sev or 3, ctx.by)
end
local function char(ctx, names, amount, add)
	for _, n in ipairs(names) do
		local r = ctx.st.regions[n]
		if r and not r.sev then
			r.burn = add and math.min(160, (r.burn or 0) + amount) or math.max(r.burn or 0, amount)
			Injury.tint(ctx.model, n)
		end
	end
	ctx.st.touched = true
end
local function mist(pos, dir, n)
	Gore.spray(pos, dir, { n = 1, particles = n or 14, speed = 8, spread = 70, size = 0.3, mist = true })
end
local function smoke(m, secs, where)
	local t = m:FindFirstChild(where or "UpperTorso")
	if t and not t:FindFirstChild("PowerSmoke") then
		local s = Instance.new("Smoke")
		s.Name = "PowerSmoke"
		s.Color, s.Opacity, s.RiseVelocity, s.Size = C(58, 54, 52), 0.2, 4, 2.2
		s.Parent = t
		task.delay(secs, function()
			s.Enabled = false
			Debris:AddItem(s, 6)
		end)
	end
end
local function ignite(m, secs)
	for _, n in ipairs(CORE) do
		local p = m:FindFirstChild(n)
		if p and not p:FindFirstChild("PowerFire") then
			local f = Instance.new("Fire")
			f.Name = "PowerFire"
			f.Size, f.Heat = (n == "UpperTorso") and 6 or 3.5, 10
			f.Color, f.SecondaryColor = C(255, 150, 50), C(255, 60, 20)
			f.Parent = p
			task.delay(secs, function()
				f.Enabled = false
				Debris:AddItem(f, 2)
			end)
		end
	end
	smoke(m, secs + 3)
end
-- pressed flat, the way Sandbox.Machines' press leaves a body
local function flatten(m)
	if m:GetAttribute("Flat") then
		return false
	end
	m:SetAttribute("Flat", true)
	for _, p in ipairs(m:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			local up = p.CFrame:VectorToObjectSpace(Vector3.yAxis)
			local ax, ay, az = math.abs(up.X), math.abs(up.Y), math.abs(up.Z)
			local f
			if ax >= ay and ax >= az then
				f = Vector3.new(0.3, 1.25, 1.25)
			elseif ay >= az then
				f = Vector3.new(1.25, 0.3, 1.25)
			else
				f = Vector3.new(1.25, 1.25, 0.3)
			end
			p.Size = p.Size * f
			for _, a in ipairs(p:GetChildren()) do
				if a:IsA("Attachment") then
					a.Position = a.Position * f
				end
			end
		end
	end
	return true
end
local function distToLine(p, o, d)
	local rel = p - o
	return (rel - d * rel:Dot(d)).Magnitude
end

---------------------------------------------------------------------------------------------------------- recipes
-- ctx = { model, st, hum, by, from, dir (unit, the way the attack travelled), flat (dir, level), raw (the move's own
-- damage, before the Strength slider), amt (what Injury is told: slider x 1.5, as Main always did), up (UpperTorso) }
local R = {}

function R.generic(ctx, s)
	local kind = s.kind or "blunt"
	if kind == "blast" and ctx.amt >= 45 then
		Injury.blast(ctx.model, ctx.up.Position - ctx.dir * 3, 10, ctx.amt, ctx.by)
	else
		hurt(ctx, near(ctx), kind, ctx.amt)
	end
end

-- HOLLOW PURPLE: whatever the orb's line crosses is not torn or burnt - it is gone
function R.erase(ctx)
	local m, st, up = ctx.model, ctx.st, ctx.up
	local o, d = ctx.from or (up.Position - ctx.dir * 8), ctx.dir
	local L = PvP.aimLine
	if L and os.clock() - L[3] < 0.25 and L[2].Magnitude > 0.1 then
		o, d = L[1], L[2].Unit
	end
	-- the orb is far wider than a person: everyone it touches gets its core, so the line is drawn in onto the chest
	local rel = up.Position - o
	local off = (o + d * rel:Dot(d)) - up.Position
	if off.Magnitude > 0.8 then
		off = off.Unit * 0.8
	end
	off = Vector3.new(off.X, math.clamp(off.Y, -0.5, 0.4), off.Z)
	local c = up.Position + off
	local centred = off.Magnitude < 0.5
	st.fatal = "Erased"
	say(ctx, centred and "Torso erased" or "Flank and shoulder erased", 4)
	-- what else stood on the line (upper limbs first: what hangs from them goes with them)
	for _, n in ipairs({ "Head", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg", "LeftLowerArm", "RightLowerArm", "LeftLowerLeg", "RightLowerLeg", "LeftHand", "RightHand" }) do
		local p = P(m, n)
		if p and distToLine(p.Position, c, d) < (n == "Head" and 0.7 or 0.86) then
			Injury.sever(m, n, ctx.by, d, "blast", { vapor = true })
		end
	end
	Wounds.bore(st, up, c, d, 0.63, K.FLESH)
	local low = P(m, "LowerTorso")
	if low and distToLine(low.Position, c, d) < 0.8 then
		Wounds.bore(st, low, c, d, 0.63, K.FLESH)
	end
	hurt(ctx, up, "blast", 150, { nodraw = true, nospray = true, nosever = true, dir = d })
	if centred then
		for _, k in ipairs({ "heart", "lungL", "lungR", "aorta" }) do
			st.organs[k] = 0
		end
		st.dirty = true
	end
	st.fatal = "Erased"
	mist(c, d, 12)
	Injury.kill(m, "Erased")
end

-- RASENSHURIKEN: countless blades too small to see - the whole body is pricked through, everywhere at once
local PEPPER = { UpperTorso = 18, LowerTorso = 8, Head = 6, LeftUpperArm = 6, RightUpperArm = 6, LeftUpperLeg = 8, RightUpperLeg = 8, LeftLowerArm = 5, RightLowerArm = 5,
	LeftLowerLeg = 6, RightLowerLeg = 6, LeftHand = 2, RightHand = 2, LeftFoot = 2, RightFoot = 2 } -- of 90
local PEPPER_ORDER = { "UpperTorso", "LowerTorso", "Head", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg", "LeftLowerArm", "RightLowerArm", "LeftLowerLeg", "RightLowerLeg",
	"LeftHand", "RightHand", "LeftFoot", "RightFoot" }
function R.pepper(ctx, s)
	local m, st = ctx.model, ctx.st
	if s.burst then -- one function deals the storm's ticks and its last burst
		s = { light = ctx.raw < s.burst }
	end
	local total = s.light and math.clamp(math.floor(ctx.raw * 1.6), 10, 30) or math.clamp(math.floor(ctx.raw * 2.4), 96, 140)
	local scale = total / 90
	for name, w in pairs(PEPPER) do
		local r = st.regions[name]
		if r and not r.sev then
			r.hp = math.max(0, r.hp - (s.light and 3 or 16))
			r.holes = (r.holes or 0) + math.max(1, math.floor(w * scale + 0.5))
			r.wet = math.min(1, (r.wet or 0) + (s.light and 0.06 or 0.3))
			Injury.tint(m, name)
		end
	end
	st.bleedM += s.light and 0.25 or 1.7
	hurt(ctx, ctx.up, "pierce", s.light and 8 or 28, { nodraw = true, nospray = true })
	if not s.light then
		st.fatal = st.fatal or "Cellular destruction"
		say(ctx, "Countless pinhole wounds - cellular damage", 3)
	end
	task.spawn(function()
		for _, name in ipairs(PEPPER_ORDER) do
			local p = m.Parent and P(m, name)
			if p then
				local n = math.floor(PEPPER[name] * scale + math.random())
				if n > 0 then
					Wounds.pepper(st, p, n, { size = 0.075 })
					if name == "UpperTorso" or name == "Head" or math.random() < 0.3 then
						mist(p.Position, Vector3.yAxis, s.light and 5 or 12)
					end
				end
				if not s.light then
					task.wait(0.06)
				end
			end
		end
	end)
end

-- RASENGAN: a spinning ball ground into the body - a bowl worn out of it, the skin round it dragged the way it spun
function R.gouge(ctx)
	local m, st, up = ctx.model, ctx.st, ctx.up
	local d = ctx.dir
	local centre = up.Position - up.CFrame.UpVector * (up.Size.Y * rnd(0.05, 0.3)) + up.CFrame.RightVector * rnd(-0.25, 0.25)
	Wounds.scoop(st, up, centre - d * 3, 0.52, 0.21, K.MUSCLE)
	local u = d:Cross(Vector3.yAxis)
	u = u.Magnitude > 0.1 and u.Unit or Vector3.xAxis
	local v = d:Cross(u).Unit
	local turn = sgn()
	for i = 1, 9 do -- the skin round it, dragged the way the ball turned
		local a = i / 9 * math.pi * 2 + math.random() * 0.3
		local radial = u * math.cos(a) + v * math.sin(a)
		local tangent = (v * math.cos(a) - u * math.sin(a)) * turn
		Wounds.cut(st, up, centre + radial * (0.58 + (i % 2) * 0.13) - d * 3, tangent + radial * 0.5, 10, { len = 0.36 + (i % 2) * 0.12, hair = true })
	end
	hurt(ctx, up, "blunt", ctx.amt * 1.3, { nodraw = true })
	st.bleedM += 0.9
	say(ctx, "Spiral gouge: abdomen", 3)
	Injury.organ(m, ({ "stomach", "gut", "liver" })[math.random(3)], 45, ctx.by)
	Gore.spray(centre - d * 0.5, -d + Vector3.new(0, 0.5, 0), { n = 4, particles = 18, speed = 14, spread = 60, size = 0.5, mist = true })
end

-- CLAWS (Kurama's, a chakra cloak's): four furrows side by side
function R.claws(ctx, s)
	local m, st, up = ctx.model, ctx.st, ctx.up
	local side = ctx.flat:Cross(Vector3.yAxis)
	local along = (side * sgn() * rnd(0.4, 0.9) - Vector3.yAxis).Unit
	Wounds.rake(st, up, toward(ctx, up, 0.3), along, s.n or 4, ctx.amt, { gap = 0.21, len = 1.5 })
	hurt(ctx, up, "slash", ctx.amt, { nodraw = true })
	local arm = one(m, ARMS)
	if arm and math.random() < 0.55 then
		Wounds.rake(st, arm, toward(ctx, arm, 0.3), along, 3, ctx.amt * 0.6, { gap = 0.15, len = 0.8 })
		hurt(ctx, arm, "slash", ctx.amt * 0.5, { nodraw = true, nospray = true })
	end
	say(ctx, "Claw wounds: chest", 2)
end

-- a blast with a character: s.dent (pure force: the chest pushed in), s.burn, s.scald, s.bleed (nose and ears),
-- s.chunk (a piece of the body gone with it), s.radius
function R.blast(ctx, s)
	local m, st, up = ctx.model, ctx.st, ctx.up
	local amt = ctx.amt
	if amt >= 40 then
		Injury.blast(m, up.Position - ctx.dir * 3, s.radius or 10, amt, ctx.by)
	else
		hurt(ctx, near(ctx), "blast", amt)
	end
	if up.Parent ~= m then
		return
	end
	if s.dent and ctx.raw >= 20 then
		Wounds.scoop(st, up, toward(ctx, up, 0.4), 0.95, math.clamp(0.1 + ctx.raw / 400, 0.12, 0.24), DENT)
	end
	if s.chunk and ctx.raw >= s.chunk then
		Wounds.scoop(st, up, toward(ctx, up, 0.6), 0.74, 0.3, SEARED)
	end
	if s.burn then
		char(ctx, ORDER, math.clamp(amt * s.burn, 10, 80))
		smoke(m, 4)
	end
	if s.scald then
		for _ = 1, 4 do
			local p = one(m, ORDER)
			if p then
				Wounds.scald(st, p, toward(ctx, p, 0.7), amt * 0.5)
				Wounds.glaze(st, p, C(196, 74, 64), 0.55)
			end
		end
		say(ctx, "Scalded by steam", 2)
	end
	if s.bleed and amt >= 45 then
		Wounds.faceBleed(st, P(m, "Head"), { nose = true, ears = true })
	end
end

-- a wave of pure pressure (a Bankai released, an aura flaring): no fire in it - bruising, and blood from the nose
function R.pressure(ctx, s)
	local m, st = ctx.model, ctx.st
	hurt(ctx, ctx.up, "blunt", ctx.amt)
	local arm = one(m, ARMS)
	if arm then
		hurt(ctx, arm, "blunt", ctx.amt * 0.5, { nosever = true })
	end
	if ctx.raw >= (s.bleed or 20) then
		Wounds.faceBleed(st, P(m, "Head"), { nose = true, ears = ctx.raw >= 40 })
	end
end

-- UNLIMITED VOID: nothing touches the body. The mind is given everything at once.
function R.mind(ctx)
	local m, st = ctx.model, ctx.st
	local head = P(m, "Head")
	hurt(ctx, head or ctx.up, "blunt", 1, { nodraw = true, nospray = true })
	if head then
		Wounds.faceBleed(st, head, { eyes = true, nose = true })
	end
	say(ctx, "Neural overload - catatonic", 3)
	Injury.organ(m, "brain", 65, ctx.by)
	Injury.down(m)
end

-- lightning put INTO the body by a hand or a blade: a burn where it went in, the fern it draws under the skin
function R.shock(ctx, s)
	local m, st = ctx.model, ctx.st
	local big = s.finale and ctx.raw >= s.finale
	local part = (s.torso or big) and ctx.up or near(ctx)
	if not part then
		return
	end
	local pos = toward(ctx, part, 0.4)
	Wounds.burn(st, part, pos, big and 40 or (s.light and 9 or 16))
	if not s.light or math.random() < 0.4 then
		Wounds.fern(st, part, pos, big and 1.5 or (s.light and 0.7 or 1))
	end
	hurt(ctx, part, "shock", ctx.amt, { nodraw = true })
	if big then -- the whole charge let go at once: it runs the length of the body
		for _, p in ipairs({ ctx.up, one(m, ARMS), one(m, LEGS) }) do
			if p then
				Wounds.fern(st, p, toward(ctx, p, 0.6, -ctx.dir), 1.25)
			end
		end
		smoke(m, 3)
		say(ctx, "Massive electrical discharge", 3)
	end
end

-- lightning from the SKY: in at the head, down the body, out through the feet
function R.lightning(ctx, s)
	local m, st, up = ctx.model, ctx.st, ctx.up
	if s.minor and ctx.raw < s.minor then
		return R.shock(ctx, {})
	end
	local down = Vector3.new(0, -1, 0)
	Wounds.fern(st, up, toward(ctx, up, 0.4), 1.7)
	Wounds.fern(st, up, toward(ctx, up, 0.4, -ctx.dir), 1.4)
	local side = math.random() < 0.5 and "Left" or "Right"
	for _, n in ipairs({ side .. "UpperArm", side .. "UpperLeg", side .. "LowerLeg" }) do
		local p = P(m, n)
		if p then
			Wounds.fern(st, p, toward(ctx, p, 0.5), 1.1)
		end
	end
	-- in at the head, out through the feet: both are left charred
	for _, n in ipairs({ "LeftFoot", "RightFoot" }) do
		Wounds.glaze(st, P(m, n), CHARRED, 0.04)
	end
	char(ctx, { "LeftFoot", "RightFoot" }, 70)
	char(ctx, { "Head" }, 34)
	if s.heavy then
		char(ctx, { "Head", "UpperTorso", "LeftUpperArm", "RightUpperArm" }, 60)
	end
	hurt(ctx, up, "shock", ctx.amt * (s.mul or 1), { nodraw = true, dir = down })
	smoke(m, 4, "Head")
	say(ctx, "Struck by lightning", 3)
end

-- a hand driven in (Killua, from behind): one deep wound and the fingers beside it
function R.stab(ctx)
	local m, st, up = ctx.model, ctx.st, ctx.up
	local pos = toward(ctx, up, 0.35)
	Wounds.scoop(st, up, pos, 0.25, 0.24, K.PIT, function(ok)
		if not ok and up.Parent == m then
			Wounds.hole(st, up, pos, 60)
		end
	end)
	Wounds.rake(st, up, pos + up.CFrame.UpVector * 0.4, Vector3.yAxis, 4, 14, { gap = 0.11, len = 0.26, thin = true, dry = true })
	hurt(ctx, up, "pierce", ctx.amt * 1.25, { nodraw = true })
	say(ctx, "Hand driven into the chest", 3)
end

-- RUN THROUGH: a real hole, in one side and out the other. s.radius, s.lining, s.fern (lightning in it), s.rise (it
-- came up out of the ground), s.spike (and stayed in), s.blast (and then went off), s.min (below this it only burst)
function R.impale(ctx, s)
	local m, st, up = ctx.model, ctx.st, ctx.up
	if s.under and ctx.raw < s.under then
		return R.blast(ctx, { burn = s.fern and 0.3 or nil })
	end
	local d = ctx.flat
	local c = up.Position + up.CFrame.RightVector * rnd(-0.32, 0.32) + up.CFrame.UpVector * rnd(-0.3, 0.3)
	if s.rise then
		d = (ctx.flat * rnd(0.75, 1) + Vector3.yAxis * rnd(0.55, 0.8)).Unit
		c = up.Position + up.CFrame.RightVector * rnd(-0.25, 0.25) - up.CFrame.UpVector * rnd(0.05, 0.3)
	end
	local lining = s.lining or K.FLESH
	Wounds.bore(st, up, c, d, s.radius or 0.26, lining, function(ok)
		if not ok and up.Parent == m then
			Wounds.hole(st, up, c - d * 3, 60)
			Wounds.exit(st, up, c, d, 80)
		end
	end)
	if s.fern then -- off to the side of the hole, not across it
		local side = d:Cross(Vector3.yAxis)
		side = side.Magnitude > 0.1 and side.Unit or up.CFrame.RightVector
		Wounds.fern(st, up, c + side * ((s.radius or 0.26) + 0.16) - d * 3, 1.3)
		Wounds.fern(st, up, c - side * ((s.radius or 0.26) + 0.16) + d * 3, 1.1)
		char(ctx, { "UpperTorso" }, 24)
	end
	hurt(ctx, up, "pierce", ctx.amt * (s.mul or 1), { nodraw = true, dir = d })
	Gore.spray(c + d * 0.6, d + Vector3.new(0, 0.15, 0), { n = 5, particles = 20, speed = 20, spread = 22, size = 0.5, mist = true })
	if s.spike and (st.spikes or 0) < 2 then
		st.spikes = (st.spikes or 0) + 1
		local sp = Gore.fxPart(Vector3.new(5.4, 0.3, 0.3), K.BONE)
		sp.Shape = Enum.PartType.Cylinder
		sp.Name = "StumpBone"
		sp.CFrame = CFrame.lookAt(c, c + d) * CFrame.Angles(0, math.pi / 2, 0)
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = up, sp
		w.Parent = sp
		sp.Parent = up
	end
	if s.blast then
		Injury.blast(m, c, 9, ctx.amt * s.blast, ctx.by)
	end
	say(ctx, s.say or "Run through the chest", 3)
end

-- IMPRINTS: a fist, a boot, a bullet of air - each one leaves its own round mark. s.n, s.d, s.welt, s.dark,
-- s.head (chance it lands on the head), s.torso, s.kind, s.mul, s.big = { above, d } (the heavy one of the string)
function R.fists(ctx, s)
	local m, st = ctx.model, ctx.st
	local d = s.d or 0.55
	if s.big and ctx.raw >= s.big[1] then
		d = s.big[2]
	end
	local part
	for _ = 1, s.n or 1 do
		part = (s.head and math.random() < s.head and P(m, "Head")) or (s.torso and ctx.up)
			or (s.spread and one(m, { "UpperTorso", "UpperTorso", "UpperTorso", "LowerTorso", "Head", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg" })) or near(ctx) or ctx.up
		Wounds.fist(st, part, toward(ctx, part, 0.75), d, s)
	end
	hurt(ctx, part, s.kind or "blunt", ctx.amt * (s.mul or 1), { nodraw = true })
end

-- SMASH: one blow with everything behind it - the chest is pushed IN, and what was behind the ribs takes it
function R.smash(ctx, s)
	local m, st, up = ctx.model, ctx.st, ctx.up
	local big = s.big and ctx.raw >= s.big
	Wounds.scoop(st, up, toward(ctx, up, 0.3), s.radius or 0.92, (s.depth or 0.17) * (big and 1.35 or 1), DENT)
	hurt(ctx, up, "crush", ctx.amt * (s.mul or 1), { nodraw = true })
	for _ = 1, (s.extra or 1) + (big and 1 or 0) do
		local p = one(m, { "LeftUpperArm", "RightUpperArm", "LowerTorso", "Head", "LeftLowerArm", "RightLowerArm" })
		if p then
			hurt(ctx, p, "crush", ctx.amt * 0.45, { nosever = true })
		end
	end
	say(ctx, s.say or "Chest caved in", 3)
end

-- BOUND: what was wrapped round the body and pulled tight leaves its line (s.color, s.gather in MOVES)
function R.bind(ctx, s)
	local m, st = ctx.model, ctx.st
	st.bands = (st.bands or 0) + 1
	if st.bands <= 5 then
		local part = (st.bands % 2 == 1) and ctx.up or one(m, s.neck and { "UpperTorso" } or ARMS) or ctx.up
		Wounds.band(st, part, (s.neck and st.bands == 1) and part.Size.Y * 0.36 or rnd(-0.3, 0.3) * part.Size.Y, s.color, s.wide)
		if st.bands == 1 then
			say(ctx, s.say or "Constriction marks", 1)
		end
	end
	hurt(ctx, ctx.up, "crush", ctx.amt, { nodraw = true, nospray = true, nosever = true })
end

-- CUTS: straight, and as long as the body is wide. s.n, s.where ("near" | "torso" | "neck" | "cycle"), s.angle ("flat"
-- | "vert" | "diag" | any), s.thin, s.edge, s.len, s.mul, s.delay (the blood comes a moment after the blade),
-- s.limb = chance a limb takes the same cut (and comes off, if it was deep enough), s.fern (lightning in the blade)
local CYCLE = { "UpperTorso", "LeftUpperArm", "RightUpperLeg", "Head", "RightUpperArm", "LeftUpperLeg", "LowerTorso" }
function R.cuts(ctx, s)
	local m, st = ctx.model, ctx.st
	local amt = ctx.amt * (s.mul or 1)
	local side = ctx.flat:Cross(Vector3.yAxis)
	local last
	for _ = 1, s.n or 1 do
		local part
		if s.where == "torso" then
			part = ctx.up
		elseif s.where == "neck" then
			part = (math.random() < (s.neck or 0.5)) and P(m, "Head") or ctx.up
		elseif s.where == "cycle" then
			st.cycle = (st.cycle or 0) % #CYCLE + 1
			part = P(m, CYCLE[st.cycle]) or ctx.up
		elseif s.where == "any" then
			part = one(m, ORDER) or ctx.up
		else
			part = one(m, BODY) or ctx.up
		end
		local along
		if s.angle == "flat" then
			along = side + Vector3.yAxis * rnd(-0.12, 0.12)
		elseif s.angle == "vert" then
			along = Vector3.yAxis + side * rnd(-0.25, 0.25)
		elseif s.angle == "diag" then
			along = side * sgn() + Vector3.yAxis * rnd(0.7, 1.1)
		else
			local a = math.random() * math.pi
			along = side * math.cos(a) + Vector3.yAxis * math.sin(a)
		end
		local pos = toward(ctx, part, 0.5)
		if part.Name == "Head" then -- the neck
			pos = part.Position - Vector3.yAxis * (part.Size.Y * 0.4) - ctx.dir * 3
			along = side
		end
		Wounds.cut(st, part, pos, along, amt, { thin = s.thin, edge = s.edge, len = s.len })
		if s.fern then
			Wounds.fern(st, part, pos, 0.8)
		end
		hurt(ctx, part, "slash", amt, { nodraw = true, nospray = s.delay ~= nil, nosever = s.nosever })
		last = part
	end
	if s.delay and last then
		local at, d = last.Position, ctx.dir
		task.delay(s.delay, function()
			Gore.spray(at, d * 0.6 + Vector3.new(0, 0.6, 0), { n = 6, particles = 22, speed = 17, spread = 40, size = 0.55, mist = true })
			Gore.sfx("slash", at, 0.5, 1.1)
		end)
	end
	if s.limb and math.random() < s.limb then
		local limb = one(m, LIMBS)
		if limb then
			Wounds.cut(st, limb, toward(ctx, limb, 0.4), side, amt, { edge = s.edge })
			hurt(ctx, limb, "slash", amt, { nodraw = true })
		end
	end
end

-- a crescent of energy thrown off a blade (Getsuga Tensho): shoulder to hip, its lips burnt; the black one goes through
function R.crescent(ctx, s)
	local m, st, up = ctx.model, ctx.st, ctx.up
	local bankai = ctx.raw >= (s.bankai or 56)
	local side = ctx.flat:Cross(Vector3.yAxis)
	local sg = sgn()
	local along = (side * sg + Vector3.yAxis * 0.95).Unit
	local edge = bankai and C(20, 6, 12) or C(34, 52, 86)
	Wounds.cut(st, up, toward(ctx, up, 0.12), along, ctx.amt, { edge = edge, keep = true })
	local low = P(m, "LowerTorso")
	if low then
		Wounds.cut(st, low, toward(ctx, low, 0.2), along, ctx.amt * 0.7, { edge = edge })
	end
	hurt(ctx, up, "slash", ctx.amt, { nodraw = true })
	if bankai then
		if math.random() < 0.4 then
			Injury.bisect(m, ctx.by, ctx.flat)
		else
			-- the shoulder at the top of the cut
			local best, bd
			for _, n in ipairs({ "LeftUpperArm", "RightUpperArm" }) do
				local p = P(m, n)
				local dd = p and (p.Position - up.Position):Dot(side * sg)
				if p and (not bd or dd > bd) then
					best, bd = p, dd
				end
			end
			if best then
				hurt(ctx, best, "slash", math.max(ctx.amt, 58))
			end
		end
	end
	say(ctx, "Cut open from shoulder to hip", 3)
end

-- CUT IN TWO (a slash that cuts the space the body stands in)
function R.bisect(ctx)
	local m = ctx.model
	hurt(ctx, P(m, "LowerTorso") or ctx.up, "slash", ctx.amt, { nodraw = true, nosever = true })
	if not Injury.bisect(m, ctx.by, ctx.flat) then
		hurt(ctx, P(m, "Head"), "slash", math.max(ctx.amt, 60))
	end
end

-- a domain of cuts: nothing in it is spared and nothing is deep - until the last one. s.final = the closing blow
function R.shred(ctx, s)
	local m, st = ctx.model, ctx.st
	if ctx.raw >= (s.final or 999) then
		for _ = 1, 4 do
			local p = one(m, ORDER)
			if p then
				local a = math.random() * math.pi
				Wounds.cut(st, p, toward(ctx, p, 0.6), Vector3.new(math.cos(a), math.sin(a), rnd(-0.5, 0.5)), 50, {})
			end
		end
		hurt(ctx, ctx.up, "slash", ctx.amt, { nodraw = true })
		local taken = 0
		for _, n in ipairs({ "LeftLowerArm", "RightUpperLeg", "RightUpperArm", "LeftLowerLeg", "LeftUpperArm", "RightLowerLeg" }) do
			if taken < 2 and math.random() < 0.6 and Injury.sever(m, n, ctx.by, ctx.dir, "slash") then
				taken += 1
			end
		end
		if math.random() < 0.3 then
			Injury.sever(m, "Head", ctx.by, ctx.dir, "slash")
		end
		say(ctx, "Cut apart", 4)
		return
	end
	for _ = 1, 2 do
		local p = one(m, ORDER)
		if p then
			local a = math.random() * math.pi
			Wounds.cut(st, p, toward(ctx, p, 0.8, Vector3.new(rnd(-1, 1), rnd(-0.3, 0.3), rnd(-1, 1)).Unit), Vector3.new(math.cos(a), math.sin(a), rnd(-0.5, 0.5)), 20, { len = rnd(0.45, 1), thin = math.random() < 0.5 })
			hurt(ctx, p, "slash", 9 + ctx.amt, { nodraw = true, nosever = true })
		end
	end
end

-- FIRE that takes the whole body. s.tick = below this it is the fire still burning
function R.burnUp(ctx, s)
	local m, st = ctx.model, ctx.st
	local now = (st.regions.UpperTorso.burn or 0)
	if s.tick and ctx.raw < s.tick then
		Injury.char(m, math.min(150, now + 14))
		ignite(m, 2.5)
		return
	end
	Injury.char(m, math.clamp(math.max(now, ctx.amt * 0.9), 55, 135))
	hurt(ctx, ctx.up, "burn", ctx.amt * 0.6)
	for _ = 1, 3 do
		local p = one(m, ORDER)
		if p then
			Wounds.burn(st, p, toward(ctx, p, 0.7), 44)
		end
	end
	ignite(m, s.secs or 4.5)
	st.fatal = "Incinerated"
	say(ctx, "Engulfed in flames", 3)
end

-- a BEAM held on the body: it burns for as long as it is there, and what it ends with takes more than skin
function R.beam(ctx, s)
	local m, st, up = ctx.model, ctx.st, ctx.up
	if ctx.raw < (s.tick or 12) then
		hurt(ctx, near(ctx), "burn", ctx.amt * 1.4)
		char(ctx, CORE, 7, true)
		return
	end
	Injury.blast(m, up.Position - ctx.dir * 3, 10, ctx.amt, ctx.by)
	char(ctx, ORDER, math.clamp(30 + ctx.raw, 40, 100))
	if ctx.raw >= (s.final or 36) and up.Parent == m then
		Wounds.scoop(st, up, toward(ctx, up, 0.4), 0.8, 0.26, CHARRED)
		local arm = one(m, { "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm" })
		if arm and (st.regions[arm.Name].burn or 0) >= 70 and math.random() < 0.6 then
			Injury.sever(m, arm.Name, ctx.by, ctx.dir, "blast", { vapor = true })
			say(ctx, "Arm burnt away", 3)
		end
		st.fatal = st.fatal or "Burnt through"
	end
	smoke(m, 4)
end

-- STEAM: skin raw and blistered, not charred
function R.steam(ctx, s)
	local m, st = ctx.model, ctx.st
	if s.blast and ctx.raw >= s.blast then
		return R.blast(ctx, { scald = true })
	end
	for _ = 1, 2 do
		local p = one(m, ORDER)
		if p then
			Wounds.scald(st, p, toward(ctx, p, 0.8, Vector3.new(rnd(-1, 1), 0, rnd(-1, 1)).Unit), 20)
			hurt(ctx, p, "burn", 5, { nodraw = true })
		end
	end
	st.scalds = (st.scalds or 0) + 1
	if st.scalds <= 6 then -- the skin itself goes red, a limb at a time
		Wounds.glaze(st, one(m, { "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }), C(196, 74, 64), 0.58)
	end
	if not st.scalded then
		st.scalded = true
		say(ctx, "Scalded by steam", 2)
	end
end

-- UNDER something far bigger than a person. s.min = below this it only struck
function R.flat(ctx, s)
	local m, st = ctx.model, ctx.st
	if s.under and ctx.raw < s.under then
		return R.fists(ctx, { d = 1.1, torso = true, kind = "crush", dark = true })
	end
	local down = Vector3.new(0, -1, 0)
	flatten(m)
	hurt(ctx, ctx.up, "crush", math.max(ctx.amt, 60), { nosever = true, dir = down })
	say(ctx, "Crushed flat", 4)
	Injury.kill(m, "Crushed")
	for _, n in ipairs({ "LowerTorso", "Head" }) do
		hurt(ctx, P(m, n), "crush", math.max(ctx.amt, n == "Head" and 76 or 60), { nosever = true, dir = down })
	end
	for _ = 1, 2 do
		hurt(ctx, one(m, LIMBS), "crush", 52, { nosever = true, dir = down })
	end
	local low = P(m, "LowerTorso") or ctx.up
	Gore.pool(low.Position, 3)
end

-- a body the size of a house hitting one the size of a person
function R.titan(ctx, s)
	local m, st, up = ctx.model, ctx.st, ctx.up
	Wounds.fist(st, up, toward(ctx, up, 0.2), 1.5, { dark = true })
	hurt(ctx, up, "crush", ctx.amt, { nodraw = true })
	for _ = 1, 3 do
		hurt(ctx, one(m, { "LeftUpperArm", "RightUpperArm", "LowerTorso", "LeftUpperLeg", "RightUpperLeg", "Head" }), "crush", ctx.amt * 0.55, { nosever = true })
	end
	say(ctx, "Struck by a Titan's fist", 3)
end

-- a ROAR: the ears go first
function R.roar(ctx)
	local m, st = ctx.model, ctx.st
	local head = P(m, "Head")
	hurt(ctx, head or ctx.up, "blunt", math.min(ctx.amt, 6), { nodraw = true, nospray = true })
	if head then
		Wounds.faceBleed(st, head, { ears = true, nose = math.random() < 0.5 })
	end
	if not st.deaf then
		st.deaf = true
		say(ctx, "Eardrums ruptured", 2)
		Injury.organ(m, "brain", 28, ctx.by)
	end
end

-- a BITE: a mouthful is gone
function R.bite(ctx)
	local m, st = ctx.model, ctx.st
	local part = one(m, { "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftUpperLeg", "RightUpperLeg", "UpperTorso" }) or ctx.up
	local r = st.regions[part.Name]
	if part.Name ~= "UpperTorso" and r and r.hp <= 25 then
		Injury.sever(m, part.Name, ctx.by, ctx.dir, "crush")
		say(ctx, "Bitten off", 3)
		return
	end
	local pos = toward(ctx, part, 0.5)
	Wounds.scoop(st, part, pos, part.Name == "UpperTorso" and 0.42 or 0.36, part.Name == "UpperTorso" and 0.24 or 0.3, K.MUSCLE)
	hurt(ctx, part, "slash", ctx.amt * 1.4, { nodraw = true, nosever = true })
	st.bleedM += 0.5
	say(ctx, "Bite wound: " .. (Injury.REG[part.Name] and Injury.REG[part.Name].label or "body"), 2)
end

------------------------------------------------------------------------------------------------------- the moves
-- { recipe, options..., gather = the move's own damage that must build up before it marks the body (small ticks) }
local MOVES = {
	Limitless = { -- GOJO
		Purple = { R.erase }, -- Hollow Purple: erased
		Red = { R.blast, dent = true, bleed = true }, -- Reversal Red: pure repelling force
		Domain = { R.mind }, -- Unlimited Void
	},
	Vulpine = { -- NARUTO
		Sphere = { R.gouge, min = 15 }, -- Rasengan
		Disc = { R.pepper, min = 20, weak = { R.pepper, light = true } }, -- Rasenshuriken
		Vortex = { R.pepper, burst = 10, gather = 4 }, -- ...which is all in the storm it opens into: a few at a time, then all at once
		Bomb = { R.blast, radius = 12, burn = 0.45, chunk = 50 }, -- Tailed Beast Bomb
		Claw = { R.claws }, -- Kurama's claws
		Morph = { R.blast, burn = 0.35 }, -- the cloak bursting out
	},
	Godspeed = { -- KILLUA
		M1 = { R.shock, light = true },
		Palm = { R.shock, torso = true }, -- Lightning Palm
		Thunder = { R.lightning, min = 20, weak = { R.shock } }, -- Thunderbolt
		Echo = { R.stab, min = 15 }, -- Rhythm Echo: behind you
		Godspeed = { R.shock, finale = 40 }, -- Whirlwind: many touches, then all of it
	},
	OneForAll = { -- DEKU
		AirForce = { R.fists, welt = true, d = 0.44, spread = true }, -- bullets of air
		Detroit = { R.smash, min = 25, weak = { R.fists, d = 0.8, kind = "crush", spread = true } }, -- Detroit Smash
		Blackwhip = { R.split, below = 15, lo = { R.bind, color = C(34, 30, 44), say = "Bound by Blackwhip" }, hi = { R.fists, head = 0.55, torso = true, d = 0.75, dark = true } },
		OFA = { R.split, below = 12, lo = { R.bind, color = C(34, 30, 44) }, hi = { R.split, below = 40, lo = { R.fists, d = 0.7, kind = "crush" }, hi = { R.smash, radius = 1.05, depth = 0.23, extra = 3, mul = 1.2, say = "Chest crushed" } } },
	},
	Tempest = { -- SASUKE
		Lance = { R.impale, radius = 0.27, lining = SEARED, fern = true, mul = 1.2, say = "Run through by Chidori", min = 20, weak = { R.shock } },
		Pulse = { R.lightning, heavy = true, minor = 28 }, -- Kirin
		Arrow = { R.impale, radius = 0.36, lining = CHARRED, fern = true, blast = 0.7, under = 70, say = "Run through by a lightning arrow" }, -- Indra's Arrow
		GuardianBurst = { R.blast, dent = true },
		GuardianShield = { R.generic, kind = "burn", gather = 8 }, -- touching the Susanoo itself
		GuardianSlash = { R.cuts, where = "torso", angle = "diag", mul = 1.2, limb = 0.8 }, -- a Susanoo's blade
	},
	Carver = { -- SUKUNA
		Cleave = { R.cuts, mul = 1.25 }, -- Dismantle
		Sever = { R.bisect, min = 35, weak = { R.cuts, mul = 1.3 } }, -- the world-cutting slash
		Fuga = { R.burnUp, tick = 20, gather = 9 },
		Shrine = { R.shred, final = 20, gather = 3 }, -- Malevolent Shrine
	},
	Shifter = { -- EREN
		Spin = { R.cuts, n = 3, where = "any", limb = 0.7, len = 1.3 }, -- ODM blades
		TitanBurst = { R.split, below = 20, lo = { R.roar }, hi = { R.blast, burn = 0.3 } }, -- the bolt of a transformation / the roar
		TitanPunch = { R.titan },
		TitanSlam = { R.flat, under = 25 },
		Steam = { R.steam, gather = 10 },
		ColossusBurst = { R.blast, scald = true, radius = 12 },
		Stomp = { R.flat, under = 25 },
		Roar = { R.roar },
		Rise = { R.blast, dent = true, radius = 12 },
		Rumble = { R.flat, under = 25 },
		Spear = { R.impale, radius = 0.25, rise = true, spike = true, say = "Impaled on a spear of bone", min = 20 },
		Bite = { R.bite }, -- the Founder's followers
	},
	Zangetsu = { -- ICHIGO
		M1 = { R.cuts, len = 1.5 },
		Getsuga = { R.crescent, bankai = 56 },
		Shunpo = { R.cuts, where = "torso", angle = "flat", delay = 0.3 },
		Hollow = { R.split, below = 14, lo = { R.cuts, len = 0.9, gather = 6 }, hi = { R.cuts, edge = C(96, 10, 20), mul = 1.2 } }, -- the mask on: wild cuts, then a wave
		["Hollow:roar"] = { R.roar },
		["Hollow:finisher"] = { R.cuts, where = "torso", angle = "vert", mul = 1.3, limb = 0.6 },
		Bankai = { R.pressure },
		BankaiGrab = { R.split, below = 8, lo = { R.bind, neck = true, gather = 8, say = "Crushed in a grip" }, hi = { R.fists, d = 0.9, torso = true } },
	},
	Ascendant = { -- GOKU
		Beam = { R.beam, tick = 12, final = 38, gather = 9 }, -- Kamehameha
		Warp = { R.fists, head = 0.6, torso = true, d = 0.6 }, -- the kick out of an instant transmission
		Surge = { R.generic, kind = "burn" },
		Instinct = { R.pressure },
		Flurry = { R.fists, d = 0.5, spread = true, n = 2 }, -- Silver Flash
	},
	Gomu = { -- LUFFY
		M1 = { R.fists, d = 0.6, big = { 16, 0.85 }, spread = true },
		Gatling = { R.fists, d = 0.46, big = { 7, 0.8 }, gather = 4, spread = true, n = 2 },
		Rocket = { R.fists, torso = true, d = 0.95, kind = "crush", dark = true },
		Elephant = { R.smash, radius = 1.05, depth = 0.22, extra = 2, say = "Chest caved in by a giant fist", min = 25 },
		Gear5 = { R.split, below = 55, lo = { R.fists, torso = true, d = 1.15, dark = true }, hi = { R.flat } }, -- ...and the Bajrang Gun
		Bajrang = { R.flat, under = 40 },
	},
	Stormdraw = { -- ZENITSU
		Flash = { R.cuts, where = "neck", neck = 0.5, angle = "flat", thin = true, mul = 2, fern = true, delay = 0.25 }, -- one draw
		Chain = { R.cuts, where = "cycle", thin = true, fern = true, gather = 8 }, -- Sixfold: six, from six sides (the damage is shared out between bodies)
		Dragon = { R.cuts, where = "neck", neck = 1, angle = "flat", fern = true, mul = 1.1 }, -- Flaming Thunder God: the head
	},
}
Powers.MOVES = MOVES

-- two moves that share one function are told apart by how hard they hit: s.below
function R.split(ctx, s)
	local t = (ctx.raw < s.below) and s.lo or s.hi
	local need = t.gather
	if need then
		local acc = ctx.st.pw
		local key = ctx.key .. "#" .. tostring(s.below)
		local sum = (acc[key] or 0) + ctx.raw
		if sum < need then
			acc[key] = sum
			return
		end
		acc[key] = 0
		ctx.amt = ctx.amt * sum / math.max(ctx.raw, 0.01)
		ctx.raw = sum
	end
	return t[1](ctx, t)
end
-- (R.split is used in the table above before it is defined here: fill those slots in)
local function fix(t)
	for k, v in pairs(t) do
		if type(v) == "table" then
			if v.below and v[1] == nil then
				v[1] = R.split
			end
			fix(v)
		end
	end
end
fix(MOVES)

------------------------------------------------------------------------------------------------------- the hook
local log = {}
Powers.unknown = {}
Powers.seen = {}
local function note(line)
	table.insert(log, line)
	if #log > 300 then
		table.remove(log, 1)
	end
end
function Powers.dump(n)
	n = n or 40
	local out = {}
	for i = math.max(1, #log - n + 1), #log do
		table.insert(out, log[i])
	end
	return table.concat(out, "\n")
end

-- hum = the dummy's humanoid, scaled = the hit after the attacker's Strength slider, base = before it.
-- -> true when this module dealt with it (Main then leaves it alone)
function Powers.hit(hum, scaled, base, m1, by, from, forceKit, forceMove)
	local model = hum.Parent
	local st = Injury.get(model)
	local up = model and (model:FindFirstChild("UpperTorso") or model:FindFirstChild("LowerTorso"))
	if not st or not up then
		return false
	end
	local kit, move, trail, sub
	if forceKit then -- Studio: Main.Debug:Invoke("power", model, kit, move, damage, player?, from?)
		kit, move, trail = forceKit, forceMove, "test"
	else
		kit, move, trail, sub = Powers.resolve()
	end
	local own = by and by:GetAttribute("Kit") or nil
	if not forceKit and (m1 or move == "M1") then
		kit, move = kit or own, "M1"
	end
	kit = kit or own
	local spec = kit and MOVES[kit] and move and ((sub and MOVES[kit][move .. ":" .. sub]) or MOVES[kit][move]) or nil
	-- a glancing hit (the edge of a blast, a splash) is not the move's signature: s.min of its own damage, or the plain wound
	if spec and spec.min and base < spec.min then
		spec = spec.weak
	end
	if STUDIO then
		local k = tostring(kit) .. "." .. tostring(move) .. (spec and "" or " (plain)")
		Powers.seen[k] = (Powers.seen[k] or 0) + 1
		note(string.format("%s.%s %s raw %.1f%s | %s", tostring(kit), tostring(move), spec and "ok" or "--", base, m1 and " m1" or "", tostring(trail)))
		if not spec and not m1 then
			local k = tostring(kit) .. "|" .. tostring(trail)
			Powers.unknown[k] = (Powers.unknown[k] or 0) + 1
		end
	end
	if not spec then
		return false
	end
	st.pw = st.pw or {}
	local key = kit .. "." .. move
	local raw, amt = base, scaled * 1.5
	if spec.gather then
		local sum = (st.pw[key] or 0) + base
		if sum < spec.gather and base < spec.gather then
			st.pw[key] = sum
			return true
		end
		st.pw[key] = 0
		if base < spec.gather then
			amt = amt * sum / math.max(base, 0.01)
			raw = sum
		end
	end
	local dir
	local dd = from and (up.Position - from) or nil
	if dd and dd.Magnitude > 0.5 then
		dir = dd.Unit
	else
		dir = -up.CFrame.LookVector
	end
	local flat = dir * Vector3.new(1, 0, 1)
	flat = flat.Magnitude > 0.2 and flat.Unit or (up.CFrame.LookVector * Vector3.new(-1, 0, -1)).Unit
	local ctx = { model = model, st = st, hum = hum, by = by, from = from, dir = dir, flat = flat, raw = raw, amt = amt, up = up, key = key, kit = kit, move = move }
	local ok, err = pcall(spec[1], ctx, spec)
	if not ok then
		warn("[Powers] " .. key .. ": " .. tostring(err))
		return false
	end
	return true
end

return Powers

--[[ REBUILDING Powers.Lines (command bar, Edit mode) after a kit's server script has been edited:
local out = { "return {" }
for _, path in ipairs({ "GojoServer.CombatService", "VulpineServer.KitServer", "GodspeedServer", "OneForAllServer", "TempestServer.TempestService", "CarverServer.CarverService",
	"ShifterServer.ShifterService", "AscendantServer.AscendantService", "StormdrawServer.StormdrawService" }) do
	local s = game.ServerScriptService
	for seg in path:gmatch("[^%.]+") do s = s[seg] end
	local row, n = {}, 0
	for line in (s.Source .. "\n"):gmatch("(.-)\n") do
		n += 1
		local name = line:match("^local function ([%w_]+)") or line:match("^function ([%w_%.:]+)") or line:match("^local ([%w_]+) = function") or line:match("^([%w_%.]+) = function")
		if name then table.insert(row, string.format('{ %d, "%s" }', n, name)) end
	end
	table.insert(out, string.format('\t["ServerScriptService.%s"] = { %s },', path, table.concat(row, ", ")))
end
table.insert(out, "}")
game.ServerScriptService.Sandbox.Powers.Lines.Source = table.concat(out, "\n")
]]
