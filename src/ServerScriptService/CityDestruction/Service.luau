-- ServerScriptService.CityDestruction.Service (owner: destruction)
-- Server-authoritative destruction + regen for NEON SHIBUYA (CONTRACT.md section 5).
--   * listens to GojoServer.WorldBlast(pos, radius, userId) and GojoServer.BreakBlast(pos, radius, dir, speed, userId)
--   * 3D grid buckets (CELL studs) over every CityGlass / CityPanel / CityProp / CityMark instance in workspace
--   * damage with falloff, HP per piece, BreakGroup, NoRegen; <= MAX_BREAKS_PER_STEP breaks per Heartbeat
--   * GLASS: hidden + client shards; PANEL / PROP: hidden + an unanchored welded clone in workspace.CityDebris
--     (collision group Debris, CanTouch / CanQuery false), flung, faded after 6-10 s, cap 240 parts oldest-first
--   * regen after Regen s when no player / NPC root is within pieceRadius + 6 (retry every 2 s), 0.5 s fade-in
--   * one CityShatter:FireAllClients(batch) per Heartbeat at most
-- Service.start(opts) -> handle. opts (all optional, used by the Edit harness): config, worldBlast, breakBlast,
-- send(batch), filter(inst) -> bool, debrisFolder, roots() -> {Vector3}, edit (skip network owner / group setup),
-- dryRun (never touches an instance: breaks are only recorded in handle.dry), seed. handle: stop(), impact(pos, radius, dir, speed, userId, kind), stats(), records, index(inst).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Service = {}

local V3 = Vector3.new
local floor, max, min, clamp = math.floor, math.max, math.min, math.clamp

local function cellKey(cx, cy, cz)
	return (cx + 512) + (cy + 512) * 1024 + (cz + 512) * 1048576
end

local ENABLED_CLASSES = { "SurfaceGui", "BillboardGui", "Light", "Beam", "ParticleEmitter", "Trail", "Fire", "Smoke", "Sparkles", "Highlight" }
local function hasEnabled(d)
	for _, c in ipairs(ENABLED_CLASSES) do
		if d:IsA(c) then
			return true
		end
	end
	return false
end

-- registers the Debris group with the same non-colliding pairs as GojoShared.Config.Collision (RagdollService does
-- the same at boot; whichever runs first wins, both are idempotent)
local function ensureGroups(groupName)
	local okCfg, cfg = pcall(function()
		return require(ReplicatedStorage.GojoShared.Config.Collision)
	end)
	local groups = (okCfg and cfg and cfg.Groups) or { "Players", "NPCs", "Ragdolls", groupName }
	local pairsNC = (okCfg and cfg and cfg.NonColliding) or { { "Players", "Ragdolls" }, { "Players", groupName }, { "NPCs", groupName } }
	local seen = false
	for _, g in ipairs(groups) do
		if g == groupName then
			seen = true
		end
	end
	if not seen then
		table.insert(groups, groupName)
	end
	for _, g in ipairs(groups) do
		pcall(function()
			if not PhysicsService:IsCollisionGroupRegistered(g) then
				PhysicsService:RegisterCollisionGroup(g)
			end
		end)
	end
	for _, p in ipairs(pairsNC) do
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable(p[1], p[2], false)
		end)
	end
end

function Service.start(opts)
	opts = opts or {}
	local CFG = opts.config or require(ReplicatedStorage:WaitForChild("CityShared"):WaitForChild("DestructionConfig"))
	local CELL = CFG.CELL
	local rng = Random.new(opts.seed or os.time())
	local now = os.clock

	local S = {
		records = {}, -- inst -> rec
		grid = {}, -- cellKey -> { [rec] = true }
		groups = {}, -- "District|Group" -> { rec, ... }
		queue = {}, -- pending impacts
		recent = {}, -- processed impacts (merge window)
		breakQueue = {}, -- { rec, impact, d }
		broken = {}, -- array of broken recs (regen scan)
		debris = {}, -- array of { inst, n, dieAt, fading, rec }
		debrisParts = 0,
		fades = {}, -- active transparency fades
		batch = {},
		stamp = 0,
		conns = {},
		counts = { indexed = 0, nested = 0, impacts = 0, merged = 0, breaks = 0, regens = 0, debrisSpawned = 0, debrisCulled = 0, batches = 0, skipped = 0, maxStepMs = 0 },
		alive = true,
	}

	-- debris folder
	local debrisFolder = opts.debrisFolder
	if not debrisFolder then
		debrisFolder = workspace:FindFirstChild("CityDebris")
		if not debrisFolder then
			debrisFolder = Instance.new("Folder")
			debrisFolder.Name = "CityDebris"
			debrisFolder.Parent = workspace
		end
	end
	S.debrisFolder = debrisFolder

	if not opts.edit then
		ensureGroups(CFG.DEBRIS_GROUP)
	end

	local send = opts.send
	if not send then
		local shared = ReplicatedStorage:WaitForChild("CityShared")
		local remotes = shared:FindFirstChild("Remotes")
		if not remotes then
			remotes = Instance.new("Folder")
			remotes.Name = "Remotes"
			remotes.Parent = shared
		end
		local remote = remotes:FindFirstChild("CityShatter")
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = "CityShatter"
			remote.Parent = remotes
		end
		send = function(batch)
			remote:FireAllClients(batch)
		end
	end

	-------------------------------------------------------------------------------------------------------------------
	-- INDEX
	-------------------------------------------------------------------------------------------------------------------
	local tagNames = {}
	for tag in pairs(CFG.TAGS) do
		table.insert(tagNames, tag)
	end

	local function categoryOf(inst)
		for _, tag in ipairs(tagNames) do
			if CollectionService:HasTag(inst, tag) then
				return CFG.TAGS[tag]
			end
		end
		return nil
	end

	local function taggedAncestor(inst)
		local p = inst.Parent
		while p and p ~= workspace and p ~= game do
			if categoryOf(p) then
				return p
			end
			p = p.Parent
		end
		return nil
	end

	local function boundsOf(inst)
		if inst:IsA("BasePart") then
			return inst.Position, inst.Size
		end
		local ok, cf, size = pcall(function()
			return inst:GetBoundingBox()
		end)
		if ok and cf then
			return cf.Position, size
		end
		return nil
	end

	local function cellsOf(pos, r, fn)
		local x0, x1 = floor((pos.X - r) / CELL), floor((pos.X + r) / CELL)
		local y0, y1 = floor((pos.Y - r) / CELL), floor((pos.Y + r) / CELL)
		local z0, z1 = floor((pos.Z - r) / CELL), floor((pos.Z + r) / CELL)
		for cx = x0, x1 do
			for cy = y0, y1 do
				for cz = z0, z1 do
					fn(cellKey(cx, cy, cz))
				end
			end
		end
	end

	local function unindex(inst)
		local rec = S.records[inst]
		if not rec then
			return
		end
		S.records[inst] = nil
		for _, k in ipairs(rec.cells) do
			local b = S.grid[k]
			if b then
				b[rec] = nil
				if next(b) == nil then
					S.grid[k] = nil
				end
			end
		end
		if rec.groupKey then
			local g = S.groups[rec.groupKey]
			if g then
				local i = table.find(g, rec)
				if i then
					table.remove(g, i)
				end
			end
		end
		rec.dead = true
		S.counts.indexed -= 1
	end

	local function index(inst)
		if S.records[inst] or not S.alive then
			return S.records[inst]
		end
		if not (inst:IsA("BasePart") or inst:IsA("Model")) then
			return nil
		end
		if not inst:IsDescendantOf(workspace) or inst:IsDescendantOf(debrisFolder) then
			return nil
		end
		if opts.filter and not opts.filter(inst) then
			return nil
		end
		local cat = categoryOf(inst)
		if not cat then
			return nil
		end
		if taggedAncestor(inst) then
			S.counts.nested += 1 -- contract: never nest tags; the outer piece owns it
			return nil
		end
		local pos, size = boundsOf(inst)
		if not pos then
			return nil
		end
		local r = max(size.Magnitude * 0.5, 0.5)
		local hp = inst:GetAttribute("HP")
		hp = (type(hp) == "number" and hp > 0) and hp or CFG.HP[cat]
		local rec = { inst = inst, cat = cat, pos = pos, size = size, r = r, hp = hp, maxHp = hp, cells = {}, lastHit = 0 }
		cellsOf(pos, r, function(k)
			local b = S.grid[k]
			if not b then
				b = {}
				S.grid[k] = b
			end
			b[rec] = true
			table.insert(rec.cells, k)
		end)
		local g = inst:GetAttribute("BreakGroup")
		if type(g) == "string" and g ~= "" then
			rec.groupKey = tostring(inst:GetAttribute("CityDistrict") or "") .. "|" .. g
			local list = S.groups[rec.groupKey]
			if not list then
				list = {}
				S.groups[rec.groupKey] = list
			end
			table.insert(list, rec)
		end
		S.records[inst] = rec
		S.counts.indexed += 1
		return rec
	end
	S.index = index

	local pendingAdds = {}
	for _, tag in ipairs(tagNames) do
		table.insert(S.conns, CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
			table.insert(pendingAdds, inst) -- indexed next step, once its children / position exist
		end))
		table.insert(S.conns, CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
			if S.records[inst] and (not categoryOf(inst) or not inst:IsDescendantOf(workspace)) then
				unindex(inst)
			end
		end))
	end

	-- initial index in slices so the server never hitches
	task.spawn(function()
		local n = 0
		for _, tag in ipairs(tagNames) do
			for _, inst in ipairs(CollectionService:GetTagged(tag)) do
				if not S.alive then
					return
				end
				index(inst)
				n += 1
				if n % 400 == 0 then
					task.wait()
				end
			end
		end
		S.ready = true
	end)

	-------------------------------------------------------------------------------------------------------------------
	-- HIDE / RESTORE
	-------------------------------------------------------------------------------------------------------------------
	local function hide(inst)
		local saved = {}
		local function visit(d)
			if d:IsA("BasePart") then
				table.insert(saved, { d, 1, d.Transparency, d.CanCollide, d.CanQuery })
				d.Transparency = 1
				d.CanCollide = false
				d.CanQuery = false
			elseif d:IsA("Decal") then -- Decal + Texture
				table.insert(saved, { d, 2, d.Transparency })
				d.Transparency = 1
			elseif hasEnabled(d) then
				if d.Enabled then
					table.insert(saved, { d, 3 })
					d.Enabled = false
				end
			end
		end
		visit(inst)
		for _, d in ipairs(inst:GetDescendants()) do
			visit(d)
		end
		return saved
	end

	local function finishRestore(saved)
		for _, s in ipairs(saved) do
			local d = s[1]
			if d.Parent then
				if s[2] == 1 then
					d.Transparency = s[3]
					d.CanCollide = s[4]
					d.CanQuery = s[5]
				elseif s[2] == 2 then
					d.Transparency = s[3]
				else
					d.Enabled = true
				end
			end
		end
	end

	-------------------------------------------------------------------------------------------------------------------
	-- DEBRIS
	-------------------------------------------------------------------------------------------------------------------
	local function killDebris(i)
		local d = table.remove(S.debris, i)
		if not d then
			return
		end
		S.debrisParts -= d.n
		if d.rec and d.rec.debris == d then
			d.rec.debris = nil
		end
		if d.inst then
			d.inst:Destroy()
		end
	end

	local function throwVector(rec, impact, d)
		local radial = rec.pos - impact.pos
		radial = radial.Magnitude > 0.01 and radial.Unit or Vector3.yAxis
		local dir = radial
		if impact.dir then
			dir = impact.dir * CFG.DIR_WEIGHT + radial * (1 - CFG.DIR_WEIGHT)
		end
		dir = dir + V3(0, CFG.FLING_UP, 0)
		dir = dir.Magnitude > 0.01 and dir.Unit or Vector3.yAxis
		local reach = impact.radius + rec.r
		local fall = clamp(1 - d / reach, 0.25, 1)
		local base = impact.speed or (20 + impact.radius * 1.6)
		local sizeScale = clamp(10 / (rec.r + 6), 0.45, 1.25)
		local fl = rec.inst:GetAttribute("Fling")
		fl = type(fl) == "number" and fl or 1
		local speed = clamp(base * fall * sizeScale * (CFG.FLING[rec.cat] or 1) * fl, CFG.FLING_MIN, CFG.FLING_MAX)
		return dir, speed
	end

	local function spawnDebris(rec, impact, d, dir, speed)
		local inst = rec.inst
		local clone = inst:Clone() -- clone BEFORE hiding the original
		if not clone then
			return
		end
		local parts = {}
		local function prep(x)
			for _, t in ipairs(CollectionService:GetTags(x)) do
				CollectionService:RemoveTag(x, t) -- the clone must not be indexed / driven by Signals / animated as a screen
			end
			if x:IsA("BasePart") then
				table.insert(parts, x)
			elseif x:IsA("JointInstance") or x:IsA("Constraint") or x:IsA("WeldConstraint") or x:IsA("LuaSourceContainer")
				or x:IsA("Light") or x:IsA("ParticleEmitter") or x:IsA("Beam") or x:IsA("Trail") or x:IsA("Fire")
				or x:IsA("Smoke") or x:IsA("Sparkles") or x:IsA("ProximityPrompt") or x:IsA("ClickDetector") then
				x:Destroy()
			end
		end
		for _, x in ipairs(clone:GetDescendants()) do
			prep(x)
		end
		prep(clone)
		local n = #parts
		if n == 0 or n > CFG.DEBRIS_CAP then
			clone:Destroy()
			return
		end
		while S.debrisParts + n > CFG.DEBRIS_CAP and #S.debris > 0 do
			killDebris(1) -- oldest first
			S.counts.debrisCulled += 1
		end
		local primary = clone:IsA("BasePart") and clone or (clone.PrimaryPart or parts[1])
		for _, p in ipairs(parts) do
			p.Anchored = false
			p.CanTouch = false
			p.CanQuery = false
			p.CanCollide = true
			p.CollisionGroup = CFG.DEBRIS_GROUP
			p.Massless = false
			if p ~= primary then
				local w = Instance.new("WeldConstraint")
				w.Part0 = primary
				w.Part1 = p
				w.Parent = primary
			end
		end
		clone:SetAttribute("CityDebris", true)
		clone:SetAttribute("Broken", nil)
		clone.Parent = debrisFolder
		local spin = V3(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * clamp(14 / (rec.r + 2), 1, 8)
		primary.AssemblyLinearVelocity = dir * speed
		primary.AssemblyAngularVelocity = spin
		if not opts.edit then
			pcall(function()
				primary:SetNetworkOwner(nil)
			end)
		end
		local life = rng:NextNumber(CFG.DEBRIS_LIFE_MIN, CFG.DEBRIS_LIFE_MAX)
		local entry = { inst = clone, n = n, parts = parts, primary = primary, dieAt = now() + life, rec = rec }
		table.insert(S.debris, entry)
		S.debrisParts += n
		rec.debris = entry
		S.counts.debrisSpawned += 1
	end

	-------------------------------------------------------------------------------------------------------------------
	-- BREAK
	-------------------------------------------------------------------------------------------------------------------
	local function addFx(e)
		if #S.batch < CFG.BATCH_MAX then
			table.insert(S.batch, e)
		end
	end

	local function breakPiece(item)
		local rec, impact, d = item[1], item[2], item[3]
		rec.pending = false
		local inst = rec.inst
		if rec.dead or rec.broken or not inst.Parent then
			return
		end
		if opts.dryRun then -- read-only run (audits against real districts): record, never touch the instance
			rec.broken = true
			S.dry = S.dry or {}
			table.insert(S.dry, rec)
			S.counts.breaks += 1
			return
		end
		local mode = inst:GetAttribute("Debris")
		if mode ~= "shatter" and mode ~= "fling" and mode ~= "none" then
			mode = CFG.DEBRIS_MODE[rec.cat]
		end
		local dir, speed = throwVector(rec, impact, d)
		local primary = inst:IsA("BasePart") and inst or inst.PrimaryPart
		if mode == "fling" then
			spawnDebris(rec, impact, d, dir, speed)
		end
		rec.saved = hide(inst)
		rec.broken = true
		rec.brokenAt = now()
		local regen = inst:GetAttribute("Regen")
		regen = (type(regen) == "number" and regen > 0) and regen or CFG.REGEN[rec.cat]
		rec.regenAt = inst:GetAttribute("NoRegen") == true and math.huge or (rec.brokenAt + regen)
		table.insert(S.broken, rec)
		inst:SetAttribute("Broken", true)
		inst:SetAttribute("BrokenAt", workspace:GetServerTimeNow())
		if impact.uid then
			inst:SetAttribute("BrokenBy", impact.uid)
		end
		S.counts.breaks += 1
		-- client FX entry (glass shards / screen sparks / dust for flung panels + props)
		if rec.cat ~= "MARK" and primary then
			local kind = (mode == "shatter") and "glass" or "dust"
			local e = { kind = kind, pos = rec.pos, size = (mode == "shatter") and primary.Size or rec.size,
				cframe = primary.CFrame, color = primary.Color, dir = dir * speed }
			if CollectionService:HasTag(primary, "CityScreen") then
				e.screen = true
			end
			addFx(e)
		end
	end

	local function queueBreak(rec, impact, d)
		if rec.broken or rec.pending then
			return
		end
		rec.pending = true
		table.insert(S.breakQueue, { rec, impact, d })
		if rec.groupKey then
			for _, other in ipairs(S.groups[rec.groupKey] or {}) do
				if not other.broken and not other.pending and not other.dead then
					other.pending = true
					table.insert(S.breakQueue, { other, impact, (other.pos - impact.pos).Magnitude })
				end
			end
		end
	end

	-------------------------------------------------------------------------------------------------------------------
	-- IMPACTS
	-------------------------------------------------------------------------------------------------------------------
	local function falloff(radius, d, pr)
		local reach = radius + pr
		if d >= reach then
			return 0
		end
		return (CFG.DMG_BASE + CFG.DMG_PER_RADIUS * radius) * (1 - (d / reach) ^ (CFG.FALLOFF_POW or 1))
	end

	local function applyImpact(im)
		S.counts.impacts += 1
		S.stamp += 1
		local stamp = S.stamp
		local pos, radius = im.pos, im.radius
		local credit = im.credit
		local t = now()
		local markOk = radius >= CFG.MARK_MIN_RADIUS and im.kind ~= "crash" -- bodies moving through never erase road paint
		local mult = im.mult or 1 -- crash impacts scale their damage with speed / size (CityDestruction.Crash)
		cellsOf(pos, radius, function(k)
			local b = S.grid[k]
			if not b then
				return
			end
			for rec in pairs(b) do
				if rec.stamp ~= stamp then
					rec.stamp = stamp
					if not rec.broken and not rec.pending and not rec.dead then
						local skip = false
						if rec.cat == "MARK" then
							skip = (not markOk) or (pos.Y - rec.pos.Y > radius * CFG.MARK_MAX_HEIGHT)
						end
						if not skip then
							local d = (rec.pos - pos).Magnitude
							local dmg = falloff(radius, d, rec.r) * mult
							if credit then
								dmg -= falloff(credit.radius, (rec.pos - credit.pos).Magnitude, rec.r)
							end
							if dmg > 0 then
								if t - rec.lastHit > CFG.HEAL_AFTER then
									rec.hp = rec.maxHp
								end
								rec.lastHit = t
								rec.hp -= dmg
								if rec.hp <= 0 then
									queueBreak(rec, im, d)
								end
							end
						end
					end
				end
			end
		end)
	end

	local function impact(pos, radius, dir, speed, userId, kind, mult)
		if not S.alive or typeof(pos) ~= "Vector3" or type(radius) ~= "number" or radius ~= radius or radius <= 0 then
			return
		end
		if pos.X ~= pos.X or math.abs(pos.X) > 1e5 or math.abs(pos.Y) > 1e5 or math.abs(pos.Z) > 1e5 then
			return
		end
		if typeof(dir) == "Vector3" and dir.Magnitude > 1e-3 and dir.Magnitude < 1e6 then
			dir = dir.Unit
		else
			dir = nil
		end
		if type(speed) ~= "number" or speed ~= speed or speed <= 0 then
			speed = nil
		else
			speed = min(speed, 400)
		end
		if type(mult) ~= "number" or mult ~= mult or mult <= 0 then
			mult = nil
		else
			mult = min(mult, 8)
		end
		table.insert(S.queue, { pos = pos, radius = min(radius, CFG.MAX_RADIUS), dir = dir, speed = speed, uid = userId, mult = mult,
			kind = kind or (dir and "break" or "world"), t = now() })
		-- the structure layer (CityDestruction.Structure: holes in walls + terrain craters) sees every impact too
		if S.onImpact then
			pcall(S.onImpact, pos, min(radius, CFG.MAX_RADIUS), dir, kind or (dir and "break" or "world"), mult, userId)
		end
		if #S.queue > CFG.MAX_QUEUE then
			table.remove(S.queue, 1)
			S.counts.skipped += 1
		end
	end
	S.impact = impact

	-- true when any indexed breakable has a grid bucket within `radius` of `pos` (Crash skips empty air with it)
	function S.hasNear(pos, radius)
		local found = false
		cellsOf(pos, radius, function(k)
			if not found and S.grid[k] then
				found = true
			end
		end)
		return found
	end

	local function processImpacts()
		local q = S.queue
		if #q == 0 then
			return
		end
		local take = min(#q, CFG.MAX_IMPACTS_PER_STEP)
		local list = table.move(q, 1, take, 1, {})
		S.queue = table.move(q, take + 1, #q, 1, {})
		-- same-step pairs: fold a WorldBlast + BreakBlast into one impact (BreakBlast's pos / dir / speed, max radius)
		for i = 1, #list do
			local a = list[i]
			if not a.drop then
				for j = i + 1, #list do
					local b = list[j]
					if not b.drop and b.kind ~= a.kind and a.kind ~= "crash" and b.kind ~= "crash" and math.abs(a.t - b.t) <= CFG.MERGE_TIME
						and (a.pos - b.pos).Magnitude <= CFG.MERGE_DIST then
						local br = (a.kind == "break") and a or b
						local wo = (br == a) and b or a
						br.radius = max(br.radius, wo.radius)
						br.uid = br.uid or wo.uid
						br.merged = true
						list[i] = br
						list[j] = { drop = true }
						a = br
						S.counts.merged += 1
						break
					end
				end
			end
		end
		-- across steps: the late partner of an already-applied impact only tops the damage up
		local t = now()
		for i = #S.recent, 1, -1 do
			if t - S.recent[i].t > CFG.MERGE_TIME + 0.05 then
				table.remove(S.recent, i)
			end
		end
		for _, im in ipairs(list) do
			if not im.drop then
				if not im.merged then
					for _, old in ipairs(S.recent) do
						if im.kind ~= "crash" and old.kind ~= "crash" and not old.merged and old.kind ~= im.kind and math.abs(old.t - im.t) <= CFG.MERGE_TIME
							and (old.pos - im.pos).Magnitude <= CFG.MERGE_DIST then
							im.credit = old
							im.dir = im.dir or old.dir
							im.speed = im.speed or old.speed
							old.merged = true
							im.merged = true
							S.counts.merged += 1
							break
						end
					end
				end
				applyImpact(im)
				table.insert(S.recent, im)
			end
		end
	end

	local function processBreaks()
		local bq = S.breakQueue
		if #bq == 0 then
			return
		end
		local nb, nm = 0, 0
		local rest = {}
		local c0 = os.clock()
		local budget = (CFG.BREAK_BUDGET_MS or 1e9) / 1000
		local cap = CFG.MAX_BREAKS_PER_STEP
		for _, item in ipairs(bq) do
			local isMark = item[1].cat == "MARK"
			if not isMark and nb >= 4 and cap > nb and os.clock() - c0 > budget then
				cap = nb -- out of time this step: the rest waits for the next Heartbeat
			end
			if isMark and nm < CFG.MAX_MARKS_PER_STEP then
				nm += 1
				breakPiece(item)
			elseif not isMark and nb < cap then
				nb += 1
				breakPiece(item)
			else
				table.insert(rest, item)
			end
		end
		S.breakQueue = rest
	end

	-------------------------------------------------------------------------------------------------------------------
	-- FADES, DEBRIS LIFE, REGEN
	-------------------------------------------------------------------------------------------------------------------
	local function stepFades()
		local t = now()
		for i = #S.fades, 1, -1 do
			local f = S.fades[i]
			local a = clamp((t - f.t0) / f.dur, 0, 1)
			for _, s in ipairs(f.items) do
				local d = s[1]
				if d.Parent then
					d.Transparency = s[2] + (s[3] - s[2]) * a
				end
			end
			if a >= 1 then
				table.remove(S.fades, i)
				if f.done then
					f.done()
				end
			end
		end
	end

	local function stepDebris()
		local t = now()
		for i = #S.debris, 1, -1 do
			local d = S.debris[i]
			if not d.inst.Parent or (d.primary and d.primary.Position.Y < CFG.DEBRIS_KILL_Y) then
				killDebris(i)
			elseif not d.fading and t >= d.dieAt then
				d.fading = true
				local items = {}
				for _, p in ipairs(d.parts) do
					if p.Parent then
						table.insert(items, { p, p.Transparency, 1 })
					end
				end
				table.insert(S.fades, { t0 = t, dur = CFG.DEBRIS_FADE, items = items, done = function()
					local j = table.find(S.debris, d)
					if j then
						killDebris(j)
					end
				end })
			end
		end
	end

	local function rootPositions()
		if opts.roots then
			return opts.roots()
		end
		local out = {}
		for _, plr in ipairs(Players:GetPlayers()) do
			local ch = plr.Character
			local r = ch and (ch:FindFirstChild("HumanoidRootPart") or ch.PrimaryPart)
			if r then
				table.insert(out, r.Position)
			end
		end
		local npcs = workspace:FindFirstChild("NPCs")
		if npcs then
			for _, m in ipairs(npcs:GetChildren()) do
				local r = m:FindFirstChild("HumanoidRootPart") or (m:IsA("Model") and m.PrimaryPart)
				if r then
					table.insert(out, r.Position)
				end
			end
		end
		for _, m in ipairs(CollectionService:GetTagged("RagdollNPC")) do
			if not (npcs and m:IsDescendantOf(npcs)) then
				local r = m:FindFirstChild("HumanoidRootPart") or (m:IsA("Model") and m.PrimaryPart)
				if r then
					table.insert(out, r.Position)
				end
			end
		end
		return out
	end

	local function restore(rec)
		if rec.debris then
			local j = table.find(S.debris, rec.debris)
			if j then
				killDebris(j)
			end
			rec.debris = nil
		end
		local saved = rec.saved or {}
		rec.saved = nil
		local items = {}
		for _, s in ipairs(saved) do
			if s[2] ~= 3 and s[1].Parent then
				table.insert(items, { s[1], 1, s[3] })
			end
		end
		local function done()
			finishRestore(saved)
			rec.broken = false
			rec.hp = rec.maxHp
			rec.lastHit = 0
			if rec.inst.Parent then
				rec.inst:SetAttribute("Broken", false)
			end
		end
		rec.restoring = true
		table.insert(S.fades, { t0 = now(), dur = CFG.REGEN_FADE, items = items, done = function()
			rec.restoring = false
			done()
		end })
		S.counts.regens += 1
	end

	local lastRegenScan = 0
	local function stepRegen()
		local t = now()
		if t - lastRegenScan < CFG.REGEN_CHECK then
			return
		end
		lastRegenScan = t
		local roots
		for i = #S.broken, 1, -1 do
			local rec = S.broken[i]
			if rec.dead or not rec.inst.Parent then
				table.remove(S.broken, i)
			elseif t >= rec.regenAt then
				roots = roots or rootPositions()
				local clearR = rec.r + CFG.REGEN_CLEAR
				local blocked = false
				for _, p in ipairs(roots) do
					if (p - rec.pos).Magnitude < clearR then
						blocked = true
						break
					end
				end
				if blocked then
					rec.regenAt = t + CFG.REGEN_RETRY
				else
					table.remove(S.broken, i)
					restore(rec)
				end
			end
		end
	end

	-------------------------------------------------------------------------------------------------------------------
	-- MAIN LOOP + HOOKS
	-------------------------------------------------------------------------------------------------------------------
	table.insert(S.conns, RunService.Heartbeat:Connect(function()
		if #pendingAdds > 0 then
			local list = pendingAdds
			pendingAdds = {}
			for i, inst in ipairs(list) do
				if i <= 400 then
					index(inst)
				else
					table.insert(pendingAdds, inst)
				end
			end
		end
		local c0 = os.clock()
		processImpacts()
		processBreaks()
		local ms = (os.clock() - c0) * 1000
		if ms > S.counts.maxStepMs then
			S.counts.maxStepMs = ms
		end
		if #S.fades > 0 then
			stepFades()
		end
		if #S.debris > 0 then
			stepDebris()
		end
		if #S.broken > 0 then
			stepRegen()
		end
		if #S.batch > 0 then
			local b = S.batch
			S.batch = {}
			S.counts.batches += 1
			local ok, err = pcall(send, b)
			if not ok then
				warn("[CityDestruction] send failed: " .. tostring(err))
			end
		end
	end))

	if opts.worldBlast then
		table.insert(S.conns, opts.worldBlast.Event:Connect(function(pos, radius, userId)
			impact(pos, radius, nil, nil, userId, "world")
		end))
	end
	if opts.breakBlast then
		table.insert(S.conns, opts.breakBlast.Event:Connect(function(pos, radius, dir, speed, userId)
			impact(pos, radius, dir, speed, userId, "break")
		end))
	end

	function S.stats()
		local nb = 0
		for _ in pairs(S.grid) do
			nb += 1
		end
		return {
			indexed = S.counts.indexed, buckets = nb, broken = #S.broken, debrisParts = S.debrisParts, debrisModels = #S.debris,
			queue = #S.queue, breakQueue = #S.breakQueue, fades = #S.fades, ready = S.ready == true, counts = S.counts,
		}
	end

	-- restores everything at once (used by the harness / a clean shutdown)
	function S.restoreAll()
		for i = #S.broken, 1, -1 do
			local rec = table.remove(S.broken, i)
			if rec.saved then
				finishRestore(rec.saved)
				rec.saved = nil
			end
			rec.broken = false
			if rec.inst.Parent then
				rec.inst:SetAttribute("Broken", false)
			end
		end
		for i = #S.fades, 1, -1 do
			local f = table.remove(S.fades, i)
			if f.done then
				f.done()
			end
		end
		while #S.debris > 0 do
			killDebris(#S.debris)
		end
	end

	function S.stop()
		S.alive = false
		for _, c in ipairs(S.conns) do
			c:Disconnect()
		end
		S.conns = {}
	end

	return S
end

return Service
