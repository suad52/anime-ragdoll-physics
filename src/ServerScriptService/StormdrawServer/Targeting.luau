--!nocheck
-- StormdrawServer.Targeting: WHO an ability hits. Lock-on (Player > NPC > nothing), the bodies along a dash line,
-- the bodies in a melee box, and the M1 lock corridor - one module so every skill aims by the same rules.
-- A "body" is a living, hittable character: another player's (through ServerScriptService.PvP, so spawn protection,
-- i-frames and giant forms behave as they do for every other kit) or an NPC tagged Config.TargetTag.
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

local PvP = require(ServerScriptService:WaitForChild("PvP"))

local Targeting = {}

local UP = Vector3.yAxis
local FLAT = Vector3.new(1, 0, 1)
local BODY_PARTS = { "HumanoidRootPart", "UpperTorso", "Torso", "Head" }

local CFG, worldFilter
local sightRay = RaycastParams.new()
sightRay.FilterType = Enum.RaycastFilterType.Exclude

-- config = the kit's Config; filterFn() -> the instances a sight ray looks through (bodies, effects, debris)
function Targeting.init(config, filterFn)
	CFG = config
	worldFilter = filterFn
end

function Targeting.alive(model)
	if typeof(model) ~= "Instance" or not model.Parent then
		return false
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and model:GetAttribute("Dead") ~= true
end

function Targeting.kindOf(model)
	return PvP.playerOf(model) and "Player" or "NPC"
end

-- the part a body is measured from (a player in a giant form answers at its body point nearest the attack)
function Targeting.rootOf(model)
	return PvP.formRoot(model) or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

-- the point an attack aims at on a body (its chest)
function Targeting.pointOf(model)
	local fp = PvP.formPoint(model, PvP.aimFrom)
	if fp then
		return fp
	end
	local part = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart")
		or model.PrimaryPart
	return (part and part:IsA("BasePart")) and part.Position or nil
end

-- every body `caster` (a Player) may hit: { { model = Model, kind = "Player" | "NPC" }, ... }
function Targeting.bodies(caster)
	PvP.setAim(caster)
	local list = {}
	if CFG.AffectPlayers then
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl ~= caster then
				local c = PvP.hittable(pl) -- alive, spawned, no force field
				if c and c:GetAttribute("Dead") ~= true then
					table.insert(list, { model = c, kind = "Player" })
				end
			end
		end
	end
	for _, m in ipairs(CollectionService:GetTagged(CFG.TargetTag)) do
		if Targeting.alive(m) and Targeting.rootOf(m) then
			table.insert(list, { model = m, kind = "NPC" })
		end
	end
	return list
end

-- nothing solid between a and b (non-colliding and loose parts - Targeting.passable, set by the service - are seen
-- through)
function Targeting.sight(a, b)
	local filter = table.clone(worldFilter())
	for _ = 1, 4 do
		sightRay.FilterDescendantsInstances = filter
		local hit = workspace:Raycast(a, b - a, sightRay)
		if not hit then
			return true
		end
		if not (Targeting.passable and Targeting.passable(hit.Instance)) then
			return false
		end
		table.insert(filter, hit.Instance)
	end
	return true
end

local function rankOf(kind)
	return table.find(CFG.Lock.Priority, kind) or (#CFG.Lock.Priority + 1)
end

-- LOCK-ON. The body an ability cast from `origin`, facing `facing` (flat unit), aims itself at:
--   * classes are tried in Config.Lock.Priority order - any PLAYER in range beats every NPC;
--   * inside a class the body under the cursor (opts.cursor, a world point) wins, else the lowest
--     distance + degrees-off-the-facing x AngleWeight (so what is in front is preferred, but something close behind
--     still counts);
--   * bodies out of opts.range, or behind a wall (Lock.NeedSight), are never picked.
-- Returns (model, kind, point) or nil - nil means "nothing to lock: go the way you face".
function Targeting.pick(caster, origin, facing, opts)
	local L = CFG.Lock
	local range = opts.range or 40
	local cursor = opts.cursor
	local eye = origin + UP
	local best = {}
	for _, b in ipairs(Targeting.bodies(caster)) do
		local pt = Targeting.pointOf(b.model)
		if pt then
			local off = pt - origin
			local dist = off.Magnitude
			if dist <= range and dist > 0.05 then
				local flatOff = off * FLAT
				local ang = 0
				if flatOff.Magnitude > 0.5 then
					ang = math.deg(math.acos(math.clamp(flatOff.Unit:Dot(facing), -1, 1)))
				end
				local score = dist + ang * L.AngleWeight
				if cursor and (pt - cursor).Magnitude <= L.CursorRadius then
					score = (pt - cursor).Magnitude - 1000
				end
				local cur = best[b.kind]
				if (not cur or score < cur.score) and (not L.NeedSight or Targeting.sight(eye, pt)) then
					best[b.kind] = { model = b.model, score = score, point = pt }
				end
			end
		end
	end
	for _, kind in ipairs(L.Priority) do
		local hit = best[kind]
		if hit then
			return hit.model, kind, hit.point
		end
	end
	return nil
end

-- up to `max` bodies within `radius` of `origin`, in lock order: players before NPCs, nearest first inside a class
function Targeting.around(caster, origin, radius, max)
	local rows = {}
	local eye = origin + UP
	for _, b in ipairs(Targeting.bodies(caster)) do
		local pt = Targeting.pointOf(b.model)
		if pt then
			local dist = (pt - origin).Magnitude
			if dist <= radius and (not CFG.Lock.NeedSight or Targeting.sight(eye, pt)) then
				table.insert(rows, { model = b.model, rank = rankOf(b.kind), dist = dist })
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		return a.dist < b.dist
	end)
	local out = {}
	for i = 1, math.min(#rows, max or #rows) do
		out[i] = rows[i].model
	end
	return out
end

-- distance from p to the segment a-b, the nearest point on it, and how far along it that point is (studs from a)
local function segDist(p, a, b)
	local ab = b - a
	local len2 = ab:Dot(ab)
	local t = len2 > 1e-6 and math.clamp((p - a):Dot(ab) / len2, 0, 1) or 0
	local near = a + ab * t
	return (p - near).Magnitude, near, t * math.sqrt(len2)
end
Targeting.segDist = segDist

-- distance from a body to the segment a-b, measured to its nearest part (less a little of that part's bulk), and how
-- far along the segment the body sits
function Targeting.bodySegDist(model, a, b)
	local fc = PvP.formCenter(model)
	if fc then
		local _, near = segDist(fc, a, b)
		local d, _, along = segDist(PvP.formPoint(model, near), a, b)
		return d, along
	end
	local best, bestAlong = math.huge, 0
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") then
			local d, _, along = segDist(part.Position, a, b)
			d -= math.min(part.Size.Magnitude * 0.25, 4)
			if d < best then
				best, bestAlong = d, along
			end
		end
	end
	return best, bestAlong
end

-- every body within `radius` of the line a-b, nearest to a first: { { model, kind, along }, ... }
function Targeting.sweep(caster, a, b, radius)
	local rows = {}
	for _, body in ipairs(Targeting.bodies(caster)) do
		local d, along = Targeting.bodySegDist(body.model, a, b)
		if d <= radius then
			table.insert(rows, { model = body.model, kind = body.kind, along = along })
		end
	end
	table.sort(rows, function(x, y)
		return x.along < y.along
	end)
	return rows
end

-- a body's test points: a giant form's nearest body point, then root / torso / head
local function pointsOf(model, from)
	local pts = {}
	local fp = PvP.formPoint(model, from)
	if fp then
		table.insert(pts, fp)
	end
	for _, n in ipairs(BODY_PARTS) do
		local part = model:FindFirstChild(n)
		if part and part:IsA("BasePart") then
			table.insert(pts, part.Position)
		end
	end
	return pts
end

-- MELEE BOX: standing bodies with a point inside the box (cf = its centre frame). A PLAYER is also tested where it
-- stood over the swing's hit delay, as the attacker saw it (PvP.lagOffsets), in a box PvP.MELEE_PAD bigger; a body
-- that is down (PvP.isDown) is passed over, like every other M1 string in the game.
function Targeting.inBox(caster, cf, size, hitDelay)
	local half = size / 2
	local out = {}
	for _, b in ipairs(Targeting.bodies(caster)) do
		local m = b.model
		if not PvP.isDown(m) then
			local isPl = b.kind == "Player"
			local pad = isPl and PvP.MELEE_PAD or 0
			local offs = isPl and PvP.lagOffsets(m, caster, hitDelay) or { Vector3.zero }
			local inside = false
			for _, pt in ipairs(pointsOf(m, cf.Position)) do
				for _, off in ipairs(offs) do
					local l = cf:PointToObjectSpace(pt + off)
					if math.abs(l.X) <= half.X + pad and math.abs(l.Y) <= half.Y + pad and math.abs(l.Z) <= half.Z + pad then
						inside = true
						break
					end
				end
				if inside then
					break
				end
			end
			if inside then
				table.insert(out, b)
			end
		end
	end
	return out
end

-- M1 LOCK-ON (PvPShared.Balance M1_LOCK_*): the first living, standing body in a corridor `reach` long and `radius`
-- wide from `origin` along the flat `aim`, in sight. Returns (model, point) or nil.
function Targeting.corridor(caster, origin, aim, reach, radius)
	local best, bestAlong, bestPt = nil, nil, nil
	for _, b in ipairs(Targeting.bodies(caster)) do
		local m = b.model
		if not PvP.isDown(m) then
			local isPl = b.kind == "Player"
			local r = radius + (isPl and PvP.MELEE_PAD or 0)
			local offs = isPl and PvP.lagOffsets(m, caster, 0) or { Vector3.zero }
			local fc = PvP.formCenter(m)
			local from = fc and (origin + aim * math.clamp((fc - origin):Dot(aim), 0, reach)) or origin
			for _, pt in ipairs(pointsOf(m, from)) do
				for _, off in ipairs(offs) do
					local q = pt + off
					local along = (q - origin):Dot(aim)
					if along >= -1 and along <= reach and (bestAlong == nil or along < bestAlong)
						and (q - (origin + aim * math.clamp(along, 0, reach))).Magnitude <= r
						and Targeting.sight(origin, q) then
						best, bestAlong, bestPt = m, along, q
					end
				end
			end
		end
	end
	return best, bestPt
end

return Targeting
