-- ServerScriptService.CityDestruction.Audit (owner: destruction) - READ-ONLY contract audit of every destruction-tagged
-- instance in workspace (CONTRACT.md section 5). Never modifies anything. From the Edit command bar:
--   print(require(game.ServerScriptService.CityDestruction.Audit:Clone())())
-- returns summary (string), report { byDistrict = { [d] = {GLASS, PANEL, PROP, MARK, parts} }, issues = { [kind] = n },
-- samples = { [kind] = { path, ... } } }.
-- issue kinds: nested (a tagged instance inside another), multiTag, modelGlassOrMark, noPrimary, empty,
-- propNotModel, propOver40Parts, oversize, unanchored, joints (welds / constraints inside a breakable),
-- markCollides, notPartOrModel, floorLike (a colliding flat tagged part someone may stand on - check it)
local CollectionService = game:GetService("CollectionService")

local TAGS = { CityGlass = "GLASS", CityPanel = "PANEL", CityProp = "PROP", CityMark = "MARK" }
local LIMIT = { GLASS = 40, PANEL = 64, PROP = 30 }

return function(opts)
	opts = opts or {}
	local report = { byDistrict = {}, issues = {}, samples = {} }
	local function issue(kind, inst)
		report.issues[kind] = (report.issues[kind] or 0) + 1
		local s = report.samples[kind]
		if not s then
			s = {}
			report.samples[kind] = s
		end
		if #s < (opts.samples or 4) then
			table.insert(s, inst:GetFullName())
		end
	end
	local debris = workspace:FindFirstChild("CityDebris")
	local n = 0
	for tag, cat in pairs(TAGS) do
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			if inst:IsDescendantOf(workspace) and not (debris and inst:IsDescendantOf(debris)) then
				n += 1
				if n % 500 == 0 then
					task.wait()
				end
				local d = tostring(inst:GetAttribute("CityDistrict") or "?")
				local row = report.byDistrict[d]
				if not row then
					row = { GLASS = 0, PANEL = 0, PROP = 0, MARK = 0, parts = 0 }
					report.byDistrict[d] = row
				end
				row[cat] += 1
				local own = 0
				for t in pairs(TAGS) do
					if CollectionService:HasTag(inst, t) then
						own += 1
					end
				end
				if own > 1 and tag == "CityGlass" then
					issue("multiTag", inst)
				end
				local p = inst.Parent
				while p and p ~= workspace do
					local hit = false
					for t in pairs(TAGS) do
						if CollectionService:HasTag(p, t) then
							hit = true
						end
					end
					if hit then
						issue("nested", inst)
						break
					end
					p = p.Parent
				end
				local lim = LIMIT[cat]
				if inst:IsA("Model") then
					if cat == "GLASS" or cat == "MARK" then
						issue("modelGlassOrMark", inst)
					end
					if not inst.PrimaryPart then
						issue("noPrimary", inst)
					end
					local parts = 0
					for _, x in ipairs(inst:GetDescendants()) do
						if x:IsA("BasePart") then
							parts += 1
							if not x.Anchored then
								issue("unanchored", inst)
							end
						elseif x:IsA("JointInstance") or x:IsA("Constraint") or x:IsA("WeldConstraint") then
							issue("joints", inst)
						end
					end
					row.parts += parts
					if parts == 0 then
						issue("empty", inst)
					elseif cat == "PROP" and parts > 40 then
						issue("propOver40Parts", inst)
					end
					if lim and parts > 0 then
						local s = inst:GetExtentsSize()
						if math.max(s.X, s.Y, s.Z) > lim + 0.05 then
							issue("oversize", inst)
						end
					end
				elseif inst:IsA("BasePart") then
					row.parts += 1
					if cat == "PROP" then
						issue("propNotModel", inst)
					end
					if not inst.Anchored then
						issue("unanchored", inst)
					end
					if cat == "MARK" and inst.CanCollide then
						issue("markCollides", inst)
					end
					local s = inst.Size
					if lim and math.max(s.X, s.Y, s.Z) > lim + 0.05 then
						issue("oversize", inst)
					end
					if cat ~= "MARK" and inst.CanCollide and s.Y < 1.5 and s.X >= 6 and s.Z >= 6
						and math.abs(inst.CFrame.UpVector.Y) > 0.95 then
						issue("floorLike", inst)
					end
					for _, x in ipairs(inst:GetChildren()) do
						if x:IsA("JointInstance") or x:IsA("Constraint") or x:IsA("WeldConstraint") then
							issue("joints", inst)
						end
					end
				else
					issue("notPartOrModel", inst)
				end
			end
		end
	end
	local lines = { string.format("destruction audit: %d tagged instances", n) }
	local ds = {}
	for d in pairs(report.byDistrict) do
		table.insert(ds, d)
	end
	table.sort(ds)
	for _, d in ipairs(ds) do
		local r = report.byDistrict[d]
		table.insert(lines, string.format("  %-10s GLASS %5d PANEL %5d PROP %5d MARK %5d (parts %d)", d, r.GLASS, r.PANEL, r.PROP, r.MARK, r.parts))
	end
	local ks = {}
	for k in pairs(report.issues) do
		table.insert(ks, k)
	end
	table.sort(ks)
	if #ks == 0 then
		table.insert(lines, "  issues: none")
	end
	for _, k in ipairs(ks) do
		table.insert(lines, string.format("  issue %-16s %5d  e.g. %s", k, report.issues[k], table.concat(report.samples[k], " ; ")))
	end
	return table.concat(lines, "\n"), report
end
