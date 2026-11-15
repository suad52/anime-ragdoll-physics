--!nocheck
-- ZangetsuKit.Client.BankaiGrab (2026-11-08): TENSA GRAB, G again inside Tensa Zangetsu. Every client draws every cast
-- from the server's broadcasts (ServerScriptService.ZangetsuServer.Moves.BankaiGrab), on the server timeline:
--   BankaiGrabCast    { id, userId, t0, origin, face, lock, whiff? | arrive (CFrame), target, slot, drop, dashAt, grabAt,
--                       crush, releaseAt, stagger }
--   BankaiGrabTick    { id, userId, i, pos }       a crushing pulse in the grip
--   BankaiGrabRelease { id, userId, pos, model }   the victim set down on its feet in front of him
--   BankaiGrabCancel  { id, userId, why }
-- Beats: 0.00 callout + root (caster), clip "BankaiGrab", a black-red flame licks off his feet; DashAt the flash-step: a
-- black afterimage left where he stood, a black-crimson streak along the dash, a ring at his feet, streaks thrown back
-- (the caster blinks to `arrive`); GrabAt the hand closes on the collar: a black flame burst, a ring, a glow + light,
-- a hit + crackle, a dark aura wraps the victim for the hold (the victim's screen: a crimson edge); each crush pulse:
-- a ring, sparks, a flame lick and a rising hit; ReleaseAt the shove: a flat shock ring + a dust doughnut where it
-- lands, streaks along the push, a heavy hit (caster: a shake and a faint crimson flash). A whiff: the clutch at the
-- air with one small burst. Others' casts draw past Config.BankaiGrab.Gate camera distance only as sounds.
return function(ctx)
	local H = {}
	local FX, S, CFG = ctx.FX, ctx.S, ctx.CFG
	local PAL = ctx.PAL or CFG.Palette or {}
	local G = type(CFG.BankaiGrab) == "table" and CFG.BankaiGrab or {}
	local UP = ctx.UP or Vector3.yAxis
	local C3 = Color3.fromRGB
	local BLACK = PAL.Black or C3(14, 10, 14)
	local CRIMSON = PAL.Crimson or C3(220, 20, 40)
	local EMBER = PAL.Ember or C3(255, 90, 60)
	local GATE = type(G.Gate) == "number" and G.Gate or 200

	local casts = {} -- "userId#id" -> { key, char, d, f, aura, done }
	local function keyOf(d)
		return tostring(d.userId) .. "#" .. tostring(d.id)
	end

	local warned = {}
	local function try(fn, ...)
		if type(fn) ~= "function" then
			return
		end
		local ok, err = pcall(fn, ...)
		if not ok then
			local k = tostring(err)
			if not warned[k] then
				warned[k] = true
				warn("[Client.BankaiGrab] " .. k)
			end
		end
	end
	-- run fn at server time t0 + secs
	local function at(t0, secs, fn)
		local wait = (t0 + secs) - ctx.now()
		if wait <= 0 then
			task.spawn(try, fn)
		else
			task.delay(wait, try, fn)
		end
	end
	local function near(pos)
		return typeof(pos) == "Vector3" and ctx.camDist(pos) <= GATE
	end
	local function groundUnder(pos)
		local ok, hit = pcall(FX.groundHit, pos, 8)
		return (ok and hit) and hit.Position or (pos - UP * 3)
	end

	local function stopCast(c)
		if not c or c.done then
			return
		end
		c.done = true
		if c.aura then
			pcall(function()
				c.aura:Destroy()
			end)
			c.aura = nil
		end
		if casts[c.key] == c then
			casts[c.key] = nil
		end
	end

	H.BankaiGrabCast = function(d)
		local char, caster = ctx.charOf(d.userId)
		if not char then
			return
		end
		local isLocal = caster == ctx.player
		local t0 = tonumber(d.t0) or ctx.now()
		local hrp = char:FindFirstChild("HumanoidRootPart")
		local origin = typeof(d.origin) == "Vector3" and d.origin or (hrp and hrp.Position)
		if not origin then
			return
		end
		local face = ctx.flat(d.face)
		local seen = isLocal or near(origin) or near(d.slot)
		local c = { key = keyOf(d), char = char, d = d, done = false }
		stopCast(casts[c.key])
		casts[c.key] = c
		c.f = ctx.castFolder("BankaiGrab", 4)

		if isLocal then
			try(ctx.callout, "BankaiGrab")
			local lock = tonumber(d.lock) or 0.9
			ctx.root(math.max(lock - (ctx.now() - t0), 0.05), face)
		end
		if seen then
			ctx.playClip(char, d.whiff and "BankaiGrabWhiff" or "BankaiGrab")
			try(S.reiatsuFlame, c.f, origin - UP * 2.4, { black = true, count = 8, height = 3, size = 1, life = 0.4 })
			ctx.soundAt("Zap", origin, 0.6, 0.8)
		end

		if d.whiff then
			at(t0, 0.16, function()
				if c.done then
					return
				end
				local r = char:FindFirstChild("HumanoidRootPart")
				local p = r and (r.Position + face * 2.6 + UP * 0.6) or origin
				if seen then
					FX.ring(c.f, p, face, 0.5, 4, CRIMSON, 0.3, { alpha = 0.2 })
					FX.sparks(c.f, p, { color = CRIMSON, color2 = EMBER, count = 10, speed = { 10, 25 }, size = 0.35, life = 0.4 })
					ctx.soundAt("Whoosh", p, 0.7, 1.2)
				end
				task.delay(0.6, stopCast, c)
			end)
			return
		end

		local arrive = typeof(d.arrive) == "CFrame" and d.arrive or CFrame.lookAt(origin, origin + face)
		local slot = typeof(d.slot) == "Vector3" and d.slot or (arrive.Position + face * 2.7)
		local grip = slot + UP * 1.2 - face * 0.5 -- the collar, in his fist

		-- DASH: the flash-step in front of the victim
		at(t0, tonumber(d.dashAt) or 0.1, function()
			if c.done then
				return
			end
			if seen then
				try(S.ghost, char, CRIMSON, 0.5, 0.35, nil, { black = true })
				try(S.slashLine, c.f, origin, arrive.Position, { width = 0.35, black = true, edge = CRIMSON, life = 0.35 })
				FX.ring(c.f, groundUnder(origin) + UP * 0.2, UP, 1, 9, CRIMSON, 0.35, { alpha = 0.25 })
				FX.streaks(c.f, origin, { dir = -face, spread = 25, count = 14, speed = { 40, 80 }, color = CRIMSON, color2 = BLACK, size = 0.4, life = 0.25 })
				ctx.soundAt("Whoosh", origin, 0.9, 1.3)
			end
			if isLocal then
				ctx.blinkTo(arrive)
				ctx.shake(0.25, 0.15)
			end
		end)

		-- GRAB: the hand closes on the collar
		at(t0, tonumber(d.grabAt) or 0.16, function()
			if c.done then
				return
			end
			if seen then
				try(S.reiatsuFlame, c.f, grip, { black = true, count = 12, height = 3.5, size = 1.1, life = 0.5 })
				FX.ring(c.f, grip, face, 0.6, 6, CRIMSON, 0.3, { alpha = 0.15 })
				FX.glow(c.f, grip, 3, CRIMSON, 0.25, { alpha = 0.3 })
				FX.light(c.f, grip, CRIMSON, 6, 16, 0.4)
				ctx.soundAt("Hit", grip, 0.9, 0.85)
				ctx.soundAt("Crackle", grip, 0.6, 1)
				local victim = d.target
				if typeof(victim) == "Instance" and victim.Parent and type(S.aura) == "function" then
					local ok, a = pcall(S.aura, victim, { black = true, rate = 30, size = 0.9 })
					if ok and a then
						c.aura = a
					end
				end
			end
			if isLocal then
				ctx.shake(0.4, 0.18)
			end
			if d.target ~= nil and d.target == ctx.player.Character then
				try(ctx.vignette, 0.22, 0.6, CRIMSON) -- you're the one being held
			end
		end)
		-- a dropped broadcast never leaves the aura on
		task.delay(math.max((tonumber(d.releaseAt) or 0.84) + 1.5, 1), stopCast, c)
	end

	H.BankaiGrabTick = function(d)
		local pos = typeof(d.pos) == "Vector3" and d.pos or nil
		if not pos then
			return
		end
		local isLocal = d.userId == ctx.player.UserId
		if not (isLocal or near(pos)) then
			return
		end
		local c = casts[keyOf(d)]
		local f = (c and c.f and c.f.Parent) and c.f or ctx.castFolder("BankaiGrabTick", 2)
		local grip = pos + UP * 1.2 - (c and ctx.flat(c.d.face) or Vector3.zero) * 0.5
		local i = tonumber(d.i) or 1
		FX.ring(f, grip, ctx.camFacing(grip), 0.4, 3.5 + i, CRIMSON, 0.22, { alpha = 0.2 })
		FX.sparks(f, grip, { color = CRIMSON, color2 = EMBER, count = 8 + i * 2, speed = { 12, 30 }, size = 0.3, life = 0.35 })
		try(S.reiatsuFlame, f, grip, { black = true, count = 6, height = 2.2, size = 0.8, life = 0.35 })
		ctx.soundAt("Hit2", grip, 0.8, 0.9 + 0.08 * i)
		if isLocal then
			ctx.shake(0.18 + 0.05 * i, 0.1)
		end
	end

	H.BankaiGrabRelease = function(d)
		local c = casts[keyOf(d)]
		local pos = typeof(d.pos) == "Vector3" and d.pos or nil
		local isLocal = d.userId == ctx.player.UserId
		if pos and (isLocal or near(pos)) then
			local f = (c and c.f and c.f.Parent) and c.f or ctx.castFolder("BankaiGrabRelease", 3)
			local g = groundUnder(pos)
			FX.ring(f, g + UP * 0.2, UP, 1, 10, CRIMSON, 0.4, { alpha = 0.2 })
			try(S.dustRing, f, g, 2, 8, 22)
			if c then
				FX.streaks(f, pos, { dir = ctx.flat(c.d.face), spread = 30, count = 16, speed = { 40, 90 }, color = CRIMSON, color2 = BLACK, size = 0.45, life = 0.3 })
			end
			ctx.soundAt("HitHeavy", pos, 1, 0.9)
			if isLocal then
				ctx.shake(0.5, 0.2)
				try(ctx.flash, CRIMSON, 0.1, 0.2)
			end
		end
		stopCast(c)
	end

	H.BankaiGrabCancel = function(d)
		stopCast(casts[keyOf(d)])
	end

	H.__reset = function()
		local list = {}
		for _, c in pairs(casts) do
			table.insert(list, c)
		end
		for _, c in ipairs(list) do
			stopCast(c)
		end
	end

	return H
end
