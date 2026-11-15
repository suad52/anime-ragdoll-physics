--!nocheck
-- GojoServer.CityNav (npc-life, 2026-11-07): the NPC waypoint graph of the SHIN-KAIDO city and the city behaviours
-- NPCService calls (wander along the graph with idle / browse / sit / station POIs, wait for the walk signal and cross
-- in groups, flee along the graph, the stranded-body check). CONTRACT.md section 6.
--
-- Graph, built once at server start (async, chunked): every Attachment under every workspace.City.*.Waypoints part
-- (node id = Name; Kind / Links / Poi / Face / Capacity / Signal / Floor attributes). Links are two-way, "@auto" links a
-- node to the nearest generated Nav node within 40 with line of sight at y + 3 (else the nearest sidewalk / plaza node of
-- another district). Every edge is validated with raycasts (knee + head height clear, floor continuous, <= 62 long,
-- <= 36 deg) and dropped with a per-district count when broken. If workspace.City.Nav has no nodes the street graph is
-- rebuilt from ServerStorage.CityGen.Nav + Plan; if even that fails, a validated 24-stud grid over ArenaBounds.
-- An edge from a "signal-wait" node into a "crosswalk" node is walkable only while its Signal group may walk
-- (workspace.City.Streets ScramblePhase / CrossPhase, or a local clock from Plan.signals when Streets' script is absent).
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local CityNav = {}
local V3 = Vector3.new
local FLAT = V3(1, 0, 1)

local CFG = {}
local nodes = {} -- [i] = { id, pos, kind, district, poi, face, cap, signal, adj = { j, ... }, comp }
local byId = {}
local grid = {}
local CELL = 32
local ready = false
local walkList, poiList = {}, {}
local poiUse = {}
local badEdge = {} -- ["i_j"] = until (os.clock)
local stats = { districts = {}, dropped = {}, autoMiss = {}, unknown = {}, nodes = 0, edges = 0, comps = 0, mainComp = 0, source = "?" }
CityNav.stats = stats

local SIG = { scramble = { stop = 34, walk = 22, flash = 6 }, cross = { x = 24, allred1 = 3, z = 24, allred2 = 3 } }

local POI_TIME = {
	browse = { 6, 14 }, sit = { 15, 35 }, stand = { 8, 20 }, wait = { 8, 20 }, view = { 8, 18 }, play = { 12, 25 },
	eat = { 15, 30 }, shop = { 6, 12 }, dance = { 10, 25 }, drink = { 12, 25 },
}
local WALK_KINDS = { sidewalk = true, plaza = true, interior = true, poi = true, bench = true, spawn = true }

---------------------------------------------------------------------------------------------------------------------
-- raycasts
---------------------------------------------------------------------------------------------------------------------
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true
pcall(function()
	params.RespectCanCollide = true
end)
local lastFilter = -math.huge
local function refreshFilter(t)
	if t then
		if t - lastFilter < 1 then
			return
		end
		lastFilter = t
	end
	local list = {}
	for _, n in ipairs({ "NPCs", "CityDebris", "FX", "LocalFX", "KitFX", "KitDebris", "TitanSwarm" }) do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(list, f)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	params.FilterDescendantsInstances = list
end

local function clearLine(a, b, h)
	local o = a + V3(0, h, 0)
	return workspace:Raycast(o, (b + V3(0, h, 0)) - o, params) == nil
end

local function floorY(p)
	local hit = workspace:Raycast(p + V3(0, 3, 0), V3(0, -9, 0), params)
	return hit and hit.Position.Y
end

-- nil = ok, else the reason the straight line a -> b is not walkable
local function edgeProblem(a, b)
	local d = b - a
	local len = d.Magnitude
	if len > 62 then
		return "long"
	end
	local flat = (d * FLAT).Magnitude
	local dy = math.abs(d.Y)
	if flat < 0.5 then
		return dy > 1.5 and "vertical" or nil
	end
	if math.deg(math.atan2(dy, flat)) > 36 then
		return "steep"
	end
	local sloped = dy > 1
	if not sloped then
		if not clearLine(a, b, 1.6) then
			return "knee"
		end
		if not clearLine(a, b, 5) then
			return "head"
		end
	end
	-- floor continuous; on stairs / ramps the knee + head rays follow the floor profile (a straight knee line from the
	-- foot of a stair to its top would clip the stair's own invisible ramp)
	local n = math.max(1, math.ceil(flat / (sloped and 2 or 4)))
	local prev
	for k = 0, n do
		local p = a:Lerp(b, k / n)
		local y = floorY(p)
		if not y or math.abs(y - p.Y) > 3 then
			return "floor"
		end
		local q = V3(p.X, y, p.Z)
		if sloped and prev then
			if not clearLine(prev, q, 1.6) then
				return "knee"
			end
			if not clearLine(prev, q, 5) then
				return "head"
			end
		end
		prev = q
	end
	return nil
end
CityNav.edgeProblem = edgeProblem

---------------------------------------------------------------------------------------------------------------------
-- graph
---------------------------------------------------------------------------------------------------------------------
local function cellKey(x, z)
	return math.floor(x / CELL) * 65536 + math.floor(z / CELL)
end

local function addNode(id, pos, kind, district, a)
	if byId[id] then
		return byId[id]
	end
	local n = { id = id, pos = pos, kind = kind or "interior", district = district, adj = {}, linkSpec = a and a.links or "" }
	if a then
		n.poi = a.poi
		n.face = a.face
		n.signal = a.signal
		n.cap = a.cap
	end
	if n.kind == "bench" and not n.poi then
		n.poi = "sit"
	end
	if n.poi and not n.cap then
		n.cap = (n.poi == "sit") and 1 or 4
	end
	table.insert(nodes, n)
	local i = #nodes
	n.i = i
	byId[id] = i
	local k = cellKey(pos.X, pos.Z)
	grid[k] = grid[k] or {}
	table.insert(grid[k], i)
	return i
end

local function nodesNear(pos, r)
	local out = {}
	local c0x, c1x = math.floor((pos.X - r) / CELL), math.floor((pos.X + r) / CELL)
	local c0z, c1z = math.floor((pos.Z - r) / CELL), math.floor((pos.Z + r) / CELL)
	for cx = c0x, c1x do
		for cz = c0z, c1z do
			local b = grid[cx * 65536 + cz]
			if b then
				for _, i in ipairs(b) do
					if (nodes[i].pos - pos).Magnitude <= r then
						table.insert(out, i)
					end
				end
			end
		end
	end
	return out
end
CityNav.nodesNear = nodesNear

local edgeSet = {}
local function edgeKey(i, j)
	return i < j and (i .. "_" .. j) or (j .. "_" .. i)
end
local function bump(t, d, k)
	t[d] = t[d] or {}
	t[d][k] = (t[d][k] or 0) + 1
end

local pending = {} -- candidate edges { i, j } before validation
local function want(i, j)
	if i == j then
		return
	end
	local k = edgeKey(i, j)
	if not edgeSet[k] then
		edgeSet[k] = "pending"
		table.insert(pending, { i, j })
	end
end

local function readDistrictNodes()
	local city = workspace:FindFirstChild("City")
	local count = 0
	if not city then
		return 0
	end
	for _, d in ipairs(city:GetChildren()) do
		local wp = d:FindFirstChild("Waypoints")
		if wp then
			local n = 0
			for _, a in ipairs(wp:GetChildren()) do
				if a:IsA("Attachment") then
					local face = a:GetAttribute("Face")
					addNode(a.Name, a.WorldPosition, a:GetAttribute("Kind"), d.Name, {
						links = a:GetAttribute("Links") or "",
						poi = a:GetAttribute("Poi"),
						face = typeof(face) == "Vector3" and face or nil,
						signal = a:GetAttribute("Signal"),
						cap = tonumber(a:GetAttribute("Capacity")),
					})
					n += 1
				end
			end
			stats.districts[d.Name] = { nodes = n, edges = 0 }
			count += n
		end
	end
	return count
end

-- the street graph straight from the Plan (when workspace.City.Nav is missing)
local function generatedFromPlan()
	local ok, res = pcall(function()
		local cg = ServerStorage:FindFirstChild("CityGen")
		local gen = require(cg.Nav)
		local Plan = require(cg.Plan)
		local ns, ls = gen.streetGraph(Plan)
		local idx = {}
		for i, n in ipairs(ns) do
			idx[i] = addNode("Nav:" .. i, V3(n.x, Plan.Y, n.z), n.kind, "Nav", { signal = n.attrs.Signal, face = n.attrs.Face })
		end
		for _, l in ipairs(ls) do
			want(idx[l[1]], idx[l[2]])
		end
		return #ns
	end)
	if not ok then
		warn("[CityNav] street graph from the Plan failed: " .. tostring(res))
		return 0
	end
	stats.districts.Nav = { nodes = res, edges = 0 }
	return res
end

-- last resort: a 24-stud grid over ArenaBounds (street level only)
local function gridFallback()
	local a = workspace:FindFirstChild("Arena")
	local b = a and a:FindFirstChild("ArenaBounds")
	local half = b and (b.Size / 2) or V3(780, 0, 780)
	local c = b and b.Position or V3()
	local ids = {}
	local n = 0
	for x = c.X - half.X + 12, c.X + half.X - 12, 24 do
		for z = c.Z - half.Z + 12, c.Z + half.Z - 12, 24 do
			local hit = workspace:Raycast(V3(x, 600, z), V3(0, -700, 0), params)
			if hit and hit.Position.Y < 14 then
				n += 1
				ids[x .. "," .. z] = addNode("Grid:" .. n, hit.Position, "plaza", "Grid")
			end
		end
		task.wait()
	end
	for x = c.X - half.X + 12, c.X + half.X - 12, 24 do
		for z = c.Z - half.Z + 12, c.Z + half.Z - 12, 24 do
			local i = ids[x .. "," .. z]
			if i then
				local r, d = ids[(x + 24) .. "," .. z], ids[x .. "," .. (z + 24)]
				if r then
					want(i, r)
				end
				if d then
					want(i, d)
				end
			end
		end
	end
	stats.districts.Grid = { nodes = n, edges = 0 }
	return n
end

local function resolveLinks()
	local autos = {}
	for i, n in ipairs(nodes) do
		local spec = n.linkSpec
		if spec and spec ~= "" then
			for tok in string.gmatch(spec, "[^,]+") do
				tok = string.gsub(tok, "^%s+", "")
				tok = string.gsub(tok, "%s+$", "")
				if tok == "@auto" then
					table.insert(autos, i)
				elseif tok ~= "" then
					local j = byId[tok]
					if j then
						want(i, j)
					else
						bump(stats.unknown, n.district, "unknown")
					end
				end
			end
		end
		n.linkSpec = nil
	end
	return autos
end

local function validatePending()
	refreshFilter()
	local done = 0
	for _, e in ipairs(pending) do
		local i, j = e[1], e[2]
		local a, b = nodes[i], nodes[j]
		local why = edgeProblem(a.pos, b.pos)
		local k = edgeKey(i, j)
		if why then
			edgeSet[k] = nil
			bump(stats.dropped, a.district, why)
			if b.district ~= a.district then
				bump(stats.dropped, b.district, why)
			end
		else
			edgeSet[k] = true
			table.insert(a.adj, j)
			table.insert(b.adj, i)
			stats.edges += 1
			stats.districts[a.district].edges += 1
		end
		done += 1
		if done % 250 == 0 then
			task.wait()
		end
	end
	pending = {}
end

local function resolveAutos(autos)
	for c, i in ipairs(autos) do
		local n = nodes[i]
		local cands = nodesNear(n.pos, 40)
		table.sort(cands, function(p, q)
			return (nodes[p].pos - n.pos).Magnitude < (nodes[q].pos - n.pos).Magnitude
		end)
		local linked = false
		for pass = 1, 2 do
			for _, j in ipairs(cands) do
				local m = nodes[j]
				local okKind
				if pass == 1 then
					okKind = m.district == "Nav" and m.kind == "sidewalk"
				else
					okKind = m.district ~= n.district and (m.kind == "sidewalk" or m.kind == "plaza")
				end
				if okKind and j ~= i and not edgeSet[edgeKey(i, j)] and clearLine(n.pos, m.pos, 3) and not edgeProblem(n.pos, m.pos) then
					edgeSet[edgeKey(i, j)] = true
					table.insert(n.adj, j)
					table.insert(m.adj, i)
					stats.edges += 1
					stats.districts[n.district].edges += 1
					linked = true
					break
				end
			end
			if linked then
				break
			end
		end
		if not linked then
			bump(stats.autoMiss, n.district, "@auto")
		end
		if c % 60 == 0 then
			task.wait()
		end
	end
end

local function components()
	local comp, sizes = 0, {}
	for i, n in ipairs(nodes) do
		if not n.comp then
			comp += 1
			local size, stack = 0, { i }
			n.comp = comp
			while #stack > 0 do
				local k = table.remove(stack)
				size += 1
				for _, j in ipairs(nodes[k].adj) do
					if not nodes[j].comp then
						nodes[j].comp = comp
						table.insert(stack, j)
					end
				end
			end
			sizes[comp] = size
		end
	end
	local best, bs = 0, 0
	for c, s in pairs(sizes) do
		if s > bs then
			best, bs = c, s
		end
	end
	stats.comps = comp
	stats.mainComp = bs
	stats.mainCompId = best
	return sizes
end

-- a Nav fallback SpawnLocation whose owner built its own spawn is switched off (one live spawn per Plan spawn)
local function dedupeSpawns()
	local city = workspace:FindFirstChild("City")
	local nav = city and city:FindFirstChild("Nav")
	local sf = nav and nav:FindFirstChild("Spawns")
	if not sf then
		return
	end
	local others = {}
	for _, d in ipairs(city:GetChildren()) do
		if d ~= nav then
			for _, s in ipairs(d:GetDescendants()) do
				if s:IsA("SpawnLocation") and s.Enabled then
					table.insert(others, s.Position)
				end
			end
		end
	end
	for _, s in ipairs(sf:GetChildren()) do
		if s:IsA("SpawnLocation") then
			for _, o in ipairs(others) do
				if ((o - s.Position) * FLAT).Magnitude < 8 then
					s.Enabled = false
					for _, r in ipairs(sf:GetChildren()) do
						if r.Name == "SpawnRing" and ((r.Position - s.Position) * FLAT).Magnitude < 6 then
							r.Transparency = 1
						end
					end
					break
				end
			end
		end
	end
end

function CityNav.build(opts)
	opts = opts or {}
	local t0 = os.clock()
	nodes, byId, grid, edgeSet, pending = {}, {}, {}, {}, {}
	stats.districts, stats.dropped, stats.autoMiss, stats.unknown = {}, {}, {}, {}
	stats.edges = 0
	refreshFilter()
	local count = readDistrictNodes()
	local navN = stats.districts.Nav and stats.districts.Nav.nodes or 0
	stats.source = "markers"
	if navN < 50 then
		local g = generatedFromPlan()
		count += g
		stats.source = g > 0 and "plan" or "markers"
	end
	if count < 50 then
		count += gridFallback()
		stats.source = "grid"
	end
	local autos = resolveLinks()
	validatePending()
	resolveAutos(autos)
	components()
	walkList, poiList = {}, {}
	for i, n in ipairs(nodes) do
		if n.poi then
			table.insert(poiList, i)
		end
		if WALK_KINDS[n.kind] and #n.adj > 0 then
			table.insert(walkList, i)
		end
	end
	stats.nodes = #nodes
	stats.seconds = math.floor((os.clock() - t0) * 100) / 100
	if not opts.noDedupe then
		pcall(dedupeSpawns)
	end
	ready = #walkList > 0
	return stats
end

function CityNav.report()
	local lines = { string.format("source %s: %d nodes, %d edges, %d components (main %d), %d walk nodes, %d POIs, %.2f s",
		stats.source, stats.nodes, stats.edges, stats.comps, stats.mainComp, #walkList, #poiList, stats.seconds or 0) }
	local names = {}
	for d in pairs(stats.districts) do
		table.insert(names, d)
	end
	table.sort(names)
	for _, d in ipairs(names) do
		local s = stats.districts[d]
		local dr = {}
		for why, c in pairs(stats.dropped[d] or {}) do
			table.insert(dr, why .. " " .. c)
		end
		local am = (stats.autoMiss[d] or {})["@auto"] or 0
		local un = (stats.unknown[d] or {}).unknown or 0
		local inMain = 0
		for _, n in ipairs(nodes) do
			if n.district == d and n.comp == stats.mainCompId then
				inMain += 1
			end
		end
		table.insert(lines, string.format("  %s: %d nodes (%d in main), %d edges, dropped [%s], @auto unresolved %d, unknown ids %d", d, s.nodes,
			inMain, s.edges, table.concat(dr, ", "), am, un))
	end
	return table.concat(lines, "\n")
end

function CityNav.ready()
	return ready
end
CityNav.nodes = function()
	return nodes
end

---------------------------------------------------------------------------------------------------------------------
-- signals
---------------------------------------------------------------------------------------------------------------------
local function localPhase(group, now)
	if group == "scramble" then
		local s = SIG.scramble
		local cyc = s.stop + s.walk + s.flash
		local t = now % cyc
		local base = now - t
		if t < s.stop then
			return "stop", base + s.stop
		elseif t < s.stop + s.walk then
			return "walk", base + s.stop + s.walk
		end
		return "flash", base + cyc
	end
	local c = SIG.cross
	local cyc = c.x + c.allred1 + c.z + c.allred2
	local t = now % cyc
	local base = now - t
	if t < c.x then
		return "x", base + c.x
	elseif t < c.x + c.allred1 then
		return "allred", base + c.x + c.allred1
	elseif t < c.x + c.allred1 + c.z then
		return "z", base + c.x + c.allred1 + c.z
	end
	return "allred", base + cyc
end

local streetsFolder
function CityNav.isOpen(group, now)
	now = now or workspace:GetServerTimeNow()
	if not streetsFolder or not streetsFolder.Parent then
		local city = workspace:FindFirstChild("City")
		streetsFolder = city and city:FindFirstChild("Streets")
	end
	local s = streetsFolder
	if group == "scramble" then
		local ph, e = s and s:GetAttribute("ScramblePhase"), s and s:GetAttribute("ScramblePhaseEnd")
		if ph == nil or e == nil or e < now - 5 then -- no Signals script (or stale Edit attributes): local clock
			ph, e = localPhase("scramble", now)
		end
		return ph == "walk" and (e - now) > 3
	end
	local ph, e = s and s:GetAttribute("CrossPhase"), s and s:GetAttribute("CrossPhaseEnd")
	if ph == nil or e == nil or e < now - 5 then
		ph, e = localPhase("cross", now)
	end
	return ph == group and (e - now) > 4
end

---------------------------------------------------------------------------------------------------------------------
-- search
---------------------------------------------------------------------------------------------------------------------
local function gated(i, j)
	local a, b = nodes[i], nodes[j]
	return a.kind == "signal-wait" and b.kind == "crosswalk" and b.signal or nil
end

local function astar(s, g, maxExp)
	if s == g then
		return { s }
	end
	maxExp = maxExp or 7000
	local goalPos = nodes[g].pos
	local gs, came, closed = { [s] = 0 }, {}, {}
	local heap = { { (nodes[s].pos - goalPos).Magnitude, s } }
	local now = os.clock()
	local exp = 0
	while #heap > 0 do
		-- pop min
		local top = heap[1]
		local last = table.remove(heap)
		if #heap > 0 then
			heap[1] = last
			local k = 1
			while true do
				local l, r = 2 * k, 2 * k + 1
				local m = k
				if heap[l] and heap[l][1] < heap[m][1] then
					m = l
				end
				if heap[r] and heap[r][1] < heap[m][1] then
					m = r
				end
				if m == k then
					break
				end
				heap[k], heap[m] = heap[m], heap[k]
				k = m
			end
		end
		local u = top[2]
		if u == g then
			local path = { g }
			while came[path[1]] do
				table.insert(path, 1, came[path[1]])
			end
			return path
		end
		if not closed[u] then
			closed[u] = true
			exp += 1
			if exp > maxExp then
				return nil
			end
			local up = nodes[u].pos
			for _, v in ipairs(nodes[u].adj) do
				if not closed[v] then
					local c = (nodes[v].pos - up).Magnitude
					if gated(u, v) then
						c += 12
					end
					local bu = badEdge[edgeKey(u, v)]
					if bu and bu > now then
						c += 400
					end
					local ng = gs[u] + c
					if not gs[v] or ng < gs[v] then
						gs[v] = ng
						came[v] = u
						table.insert(heap, { ng + (nodes[v].pos - goalPos).Magnitude, v })
						local k = #heap
						while k > 1 do
							local p = k // 2
							if heap[p][1] <= heap[k][1] then
								break
							end
							heap[p], heap[k] = heap[k], heap[p]
							k = p
						end
					end
				end
			end
		end
	end
	return nil
end
CityNav.astar = astar

-- nearest node to a body: 3-D distance with height weighted x3 (so a deck / floor above is not "near"), line of
-- sight from the body to the node checked on the closest few
local function nearestNode(pos, los, maxR)
	maxR = maxR or 48
	local r = 24
	while r <= maxR do
		local c = nodesNear(pos, r)
		if #c > 0 then
			local feet = pos - V3(0, 3, 0)
			table.sort(c, function(p, q)
				local a, b = nodes[p].pos - feet, nodes[q].pos - feet
				return (a * FLAT).Magnitude + math.abs(a.Y) * 3 < (b * FLAT).Magnitude + math.abs(b.Y) * 3
			end)
			if not los then
				return c[1]
			end
			for k = 1, math.min(6, #c) do
				local n = nodes[c[k]]
				if #n.adj > 0 and workspace:Raycast(pos, (n.pos + V3(0, 2.5, 0)) - pos, params) == nil then
					return c[k]
				end
			end
		end
		r *= 2
	end
	return nil
end
CityNav.nearestNode = nearestNode

---------------------------------------------------------------------------------------------------------------------
-- behaviours (rec = NPCService's record: model, hum, hrp, mode, nextAt, walkSpeed, ...)
---------------------------------------------------------------------------------------------------------------------
local function navOf(rec)
	local nv = rec.nav
	if not nv then
		nv = { lane = math.random() * 2 - 1 }
		rec.nav = nv
	end
	return nv
end

local function releasePoi(nv)
	if nv.poiHeld then
		poiUse[nv.poiHeld] = math.max(0, (poiUse[nv.poiHeld] or 1) - 1)
		nv.poiHeld = nil
	end
end

function CityNav.reset(rec)
	local nv = navOf(rec)
	releasePoi(nv)
	nv.path, nv.i, nv.goal, nv.poi, nv.target = nil, nil, nil, nil, nil
	nv.fleePath = nil
	rec.pose = nil
end

function CityNav.onSpawn(rec)
	navOf(rec)
	rec.pose = nil
end

local function spread(nv, from, to)
	-- lateral offset so a crowd spreads over a zebra / sidewalk instead of walking in single file
	local a, b = nodes[from], nodes[to]
	local d = (b.pos - a.pos) * FLAT
	if d.Magnitude < 0.5 then
		return b.pos
	end
	local perp = V3(-d.Z, 0, d.X).Unit
	local w = 0
	if b.kind == "crosswalk" or a.kind == "crosswalk" then
		w = 4
	elseif b.kind == "signal-wait" then
		w = 3
	elseif b.kind == "sidewalk" and a.kind == "sidewalk" then
		w = 1.5
	elseif b.kind == "plaza" and a.kind == "plaza" then
		w = 2.5
	end
	return b.pos + perp * (nv.lane * w)
end

local function issue(rec, nv, t)
	local to = nv.path[nv.i]
	local from = nv.path[nv.i - 1] or to
	local target = (from ~= to) and spread(nv, from, to) or nodes[to].pos
	nv.target = target
	nv.lastIssue = t
	nv.stuck = 0
	nv.jumped = false
	local dist = ((target - rec.hrp.Position) * FLAT).Magnitude
	nv.deadline = t + dist / math.max(4, rec.hum.WalkSpeed) * 2 + 4
	rec.hum:MoveTo(target)
end

local function pickGoal(rec, start)
	local sp = nodes[start]
	local comp = sp.comp
	local r = math.random()
	local poiP = CFG.CityPoiChance or 0.4
	local crossP = CFG.CityCrossChance or 0.25
	if r < poiP and #poiList > 0 then
		for _ = 1, 16 do
			local i = poiList[math.random(#poiList)]
			local n = nodes[i]
			local d = (n.pos - sp.pos).Magnitude
			if n.comp == comp and d < 220 and d > 4 and (poiUse[i] or 0) < (n.cap or 4) then
				return i, n.poi
			end
		end
	end
	if r < poiP + crossP and (sp.pos * FLAT).Magnitude < (CFG.CityCrossRadius or 300) then
		-- across the scramble: somewhere near a corner other than the nearest one
		local corners = { V3(-50, 2, -50), V3(50, 2, -50), V3(50, 2, 50), V3(-50, 2, 50) }
		local near, nd = 1, math.huge
		for k, c in ipairs(corners) do
			local d = ((c - sp.pos) * FLAT).Magnitude
			if d < nd then
				near, nd = k, d
			end
		end
		local pickC = corners[((near + math.random(1, 3) - 1) % 4) + 1]
		local out = pickC * FLAT
		local target = pickC + out.Unit * (20 + math.random() * 120)
		local c = nodesNear(target, 60)
		for _ = 1, 10 do
			if #c == 0 then
				break
			end
			local i = c[math.random(#c)]
			local n = nodes[i]
			if n.comp == comp and WALK_KINDS[n.kind] then
				if n.poi and (poiUse[i] or 0) < (n.cap or 4) then
					return i, n.poi
				end
				return i, nil
			end
		end
	end
	for _ = 1, 30 do
		local i = walkList[math.random(#walkList)]
		local n = nodes[i]
		local d = (n.pos - sp.pos).Magnitude
		if n.comp == comp and d > 40 and d < 260 then
			return i, nil
		end
	end
	-- sparse corner of the graph: any reachable node a few hops away
	local cur = start
	for _ = 1, 6 do
		local adj = nodes[cur].adj
		if #adj == 0 then
			break
		end
		cur = adj[math.random(#adj)]
	end
	return cur ~= start and cur or nil, nil
end

local function startTrip(rec, nv, t)
	refreshFilter(t)
	local start = nearestNode(rec.hrp.Position, true, 48)
	if not start then
		-- off the graph (knocked onto a roof, into a corner): head for the nearest node in a straight line
		local n = nearestNode(rec.hrp.Position, false, 192)
		if n then
			nv.path, nv.i, nv.goal, nv.poi = { n }, 1, n, nil
			rec.mode = "walk"
			rec.hum.WalkSpeed = rec.walkSpeed
			issue(rec, nv, t)
			return true
		end
		return false
	end
	local goal, poi = pickGoal(rec, start)
	if not goal then
		return false
	end
	local path = astar(start, goal)
	if not path then
		return false
	end
	releasePoi(nv)
	if poi then
		poiUse[goal] = (poiUse[goal] or 0) + 1
		nv.poiHeld = goal
	end
	nv.path, nv.i, nv.goal, nv.poi = path, 1, goal, poi
	rec.mode = "walk"
	rec.pose = nil
	rec.hum.WalkSpeed = rec.walkSpeed
	issue(rec, nv, t)
	return true
end

local function faceDir(rec, dir)
	if not dir or dir.Magnitude < 0.1 then
		return
	end
	local p = rec.hrp.Position
	local d = (dir * FLAT)
	if d.Magnitude < 0.1 then
		return
	end
	pcall(function()
		rec.hrp.CFrame = CFrame.lookAt(p, p + d.Unit)
	end)
end

local function arrive(rec, nv, t)
	local g = nv.goal and nodes[nv.goal]
	nv.path = nil
	rec.hum:MoveTo(rec.hrp.Position)
	if nv.poi and g then
		local span = POI_TIME[nv.poi] or { 6, 14 }
		nv.poiUntil = t + span[1] + math.random() * (span[2] - span[1])
		rec.mode = "poi"
		faceDir(rec, g.face)
		rec.pose = (nv.poi == "sit") and "sit" or nil
	else
		releasePoi(nv)
		rec.mode = "idle"
		rec.nextAt = t + (CFG.IdleTimeMin or 1) + math.random() * ((CFG.IdleTimeMax or 4) - (CFG.IdleTimeMin or 1))
	end
end

local function abortTrip(rec, nv, t)
	if nv.path and nv.i and nv.path[nv.i - 1] and nv.path[nv.i] then
		badEdge[edgeKey(nv.path[nv.i - 1], nv.path[nv.i])] = os.clock() + 60
	end
	releasePoi(nv)
	nv.path = nil
	rec.hum:MoveTo(rec.hrp.Position)
	rec.mode = "idle"
	rec.nextAt = t + 0.5 + math.random()
end

local function stepWalk(rec, nv, t, dt)
	if not nv.path or not nv.target then
		rec.mode = "idle"
		rec.nextAt = t + 0.3
		return
	end
	local hrp = rec.hrp
	local here = hrp.Position
	local tgt = nv.target
	local flat = ((here - tgt) * FLAT).Magnitude
	local node = nodes[nv.path[nv.i]]
	local tol = (node.kind == "crosswalk") and 3.5 or 2.4
	if flat < tol and math.abs(here.Y - 3 - tgt.Y) < 5 then
		nv.i += 1
		if nv.i > #nv.path then
			arrive(rec, nv, t)
			return
		end
		local grp = gated(nv.path[nv.i - 1], nv.path[nv.i])
		if grp and not CityNav.isOpen(grp) then
			rec.mode = "wait"
			nv.waitGroup = grp
			nv.waitSince = t
			local w = nodes[nv.path[nv.i - 1]]
			local fdir = (nodes[nv.path[nv.i]].pos - w.pos) * FLAT
			local perp = fdir.Magnitude > 0.1 and V3(-fdir.Z, 0, fdir.X).Unit or V3()
			local back = fdir.Magnitude > 0.1 and -fdir.Unit or V3()
			local spot = w.pos + perp * (nv.lane * 3.5) + back * (math.random() * 2)
			nv.waitSpot = spot
			nv.waitFace = fdir
			rec.hum:MoveTo(spot)
			return
		end
		issue(rec, nv, t)
		return
	end
	if t - (nv.lastIssue or 0) > 6 then
		rec.hum:MoveTo(tgt)
		nv.lastIssue = t
	end
	local speed = (hrp.AssemblyLinearVelocity * FLAT).Magnitude
	nv.stuck = (speed < 0.6) and ((nv.stuck or 0) + dt) or 0
	if nv.stuck > 1.2 then
		if not nv.jumped then
			nv.jumped = true
			nv.stuck = 0
			rec.hum.Jump = true
		else
			abortTrip(rec, nv, t)
			return
		end
	end
	if t > (nv.deadline or math.huge) then
		abortTrip(rec, nv, t)
	end
end

local function stepWait(rec, nv, t)
	if not nv.path then
		rec.mode = "idle"
		rec.nextAt = t + 0.3
		return
	end
	if CityNav.isOpen(nv.waitGroup) then
		-- a small random start delay so a crowd steps off in a ripple, not in lockstep
		if not nv.goAt then
			nv.goAt = t + math.random() * 1.2
		end
		if t >= nv.goAt then
			nv.goAt = nil
			rec.mode = "walk"
			issue(rec, nv, t)
		end
		return
	end
	nv.goAt = nil
	if nv.waitSpot and ((rec.hrp.Position - nv.waitSpot) * FLAT).Magnitude < 1.5 and not nv.faced then
		nv.faced = true
		faceDir(rec, nv.waitFace)
	end
	if t - (nv.waitSince or t) > 90 then
		-- the light never came (signals stopped?): give up this trip
		abortTrip(rec, nv, t)
	end
end

function CityNav.wander(rec, t, dt)
	local nv = navOf(rec)
	local mode = rec.mode
	if mode == "walk" then
		nv.faced = nil
		stepWalk(rec, nv, t, dt)
	elseif mode == "wait" then
		stepWait(rec, nv, t)
	elseif mode == "poi" then
		if t >= (nv.poiUntil or 0) then
			releasePoi(nv)
			rec.pose = nil
			rec.mode = "idle"
			rec.nextAt = t + 0.3 + math.random()
		elseif nv.poi == "dance" and math.random() < 0.03 then
			rec.hum.Jump = true
		end
	else
		rec.mode = "idle"
		rec.pose = nil
		if t >= (rec.nextAt or 0) then
			if not startTrip(rec, nv, t) then
				rec.nextAt = t + 1 + math.random() * 2
			end
		end
	end
end

-- flee along the graph: the reachable node (<= 7 hops, signals ignored - people run against the light) farthest
-- from the threat, re-planned every second while the threat lasts
function CityNav.flee(rec, t)
	local nv = navOf(rec)
	releasePoi(nv)
	rec.pose = nil
	local hrp = rec.hrp
	local here = hrp.Position
	local threat = rec.fleeFrom
	if not nv.fleePath or t >= (rec.nextFleeAt or 0) then
		rec.nextFleeAt = t + 1 -- NPCService zeroes it on every new Threat, which forces a re-plan
		refreshFilter(t)
		local s = nearestNode(here, false, 48)
		if not s then
			local away = (here - threat) * FLAT
			if away.Magnitude < 0.5 then
				away = V3(math.random() - 0.5, 0, math.random() - 0.5)
			end
			nv.fleePath = nil
			rec.hum:MoveTo(here + away.Unit * 30)
			return
		end
		local depth, came, order = { [s] = 0 }, {}, { s }
		local head = 1
		while head <= #order do
			local u = order[head]
			head += 1
			if depth[u] < 7 then
				for _, v in ipairs(nodes[u].adj) do
					if depth[v] == nil then
						depth[v] = depth[u] + 1
						came[v] = u
						table.insert(order, v)
					end
				end
			end
		end
		local best, bs = s, -math.huge
		for _, v in ipairs(order) do
			local n = nodes[v]
			local score = ((n.pos - threat) * FLAT).Magnitude - (n.kind == "crosswalk" and 6 or 0) + math.random() * 4
			if score > bs then
				best, bs = v, score
			end
		end
		local path = { best }
		while came[path[1]] do
			table.insert(path, 1, came[path[1]])
		end
		-- skip the first node when it lies toward the threat
		local fi = 1
		if #path > 1 and ((nodes[path[1]].pos - threat) * FLAT).Magnitude < ((here - threat) * FLAT).Magnitude - 2 then
			fi = 2
		end
		nv.fleePath, nv.fi = path, fi
		rec.hum:MoveTo(nodes[path[fi]].pos)
		nv.fleeTarget = nodes[path[fi]].pos
		return
	end
	local tgt = nv.fleeTarget
	if tgt and ((here - tgt) * FLAT).Magnitude < 3 then
		nv.fi += 1
		local i = nv.fleePath[nv.fi]
		if i then
			nv.fleeTarget = nodes[i].pos
			rec.hum:MoveTo(nv.fleeTarget)
		end
	end
end

-- a standing body far from every node for StrandTime s (knocked onto a sealed roof, wedged somewhere) is retired
-- like checkLost does (the kill goes to whoever hit it last); it first tries to walk back (startTrip's straight line)
function CityNav.checkStranded(rec, pos, t)
	if not ready then
		return
	end
	local m = rec.model
	if m:GetAttribute("GrabbedBy") or m:GetAttribute("InDomain") or m:GetAttribute("Ragdolled") then
		rec.strandSince = nil
		return
	end
	if t < (rec.strandNext or 0) then
		return
	end
	rec.strandNext = t + 1
	local feet = pos - V3(0, 3, 0)
	local near = nodesNear(feet, CFG.StrandDist or 60)
	local ok = false
	for _, i in ipairs(near) do
		if math.abs(nodes[i].pos.Y - feet.Y) < 14 then
			ok = true
			break
		end
	end
	if ok then
		rec.strandSince = nil
		return
	end
	rec.strandSince = rec.strandSince or t
	if t - rec.strandSince >= (CFG.StrandTime or 30) then
		local m = rec.hum.Parent
		if m then
			m:SetAttribute("Retired", true) -- removed by the game, not by a hit: DamageFeed shows no number for it
		end
		rec.hum.Health = 0
	end
end

function CityNav.init(cfg)
	CFG = cfg or {}
	pcall(function()
		local Plan = require(ServerStorage.CityGen.Plan)
		if Plan.signals then
			SIG = Plan.signals
		end
	end)
	task.spawn(function()
		task.wait(1) -- let the city settle (district scripts, destruction service) before the raycasts
		local ok, err = pcall(CityNav.build)
		if ok then
			print("[CityNav] " .. CityNav.report())
		else
			warn("[CityNav] graph build failed: " .. tostring(err))
		end
	end)
end

return CityNav
