-- ServerScriptService.CityRuntime.Lifts (owner: towers) - KAGAMI TOWER lift pads.
-- Every part tagged "CityLift" (Kit.TAG.LIFT) under workspace.City has attributes LiftId (its own name) and To (the
-- LiftId of the pad it sends you to). A player whose character stands on a pad for Hold (1) s is moved to the target
-- pad; they must step off before that pad works again (no ping-pong). Server-only, polls 5x/s over a handful of pads.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TAG = "CityLift"
local POLL = 0.2

local pads = {} -- [part] = true
local byId = {}
local function add(p)
	if p:IsA("BasePart") and p:IsDescendantOf(workspace) then
		pads[p] = true
		local id = p:GetAttribute("LiftId") or p.Name
		byId[id] = p
	end
end
local function remove(p)
	pads[p] = nil
	for id, q in pairs(byId) do
		if q == p then
			byId[id] = nil
		end
	end
end
for _, p in ipairs(CollectionService:GetTagged(TAG)) do
	add(p)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)

local function padUnder(pos)
	for p in pairs(pads) do
		if p.Parent then
			local rel = p.CFrame:PointToObjectSpace(pos)
			local s = p.Size
			if math.abs(rel.X) <= s.X / 2 and math.abs(rel.Z) <= s.Z / 2 and rel.Y > -0.5 and rel.Y < 7 then
				return p
			end
		end
	end
	return nil
end

local state = {} -- [player] = { pad, t0, mustLeave }
Players.PlayerRemoving:Connect(function(plr)
	state[plr] = nil
end)

local function busy(char)
	if char:GetAttribute("GrabbedBy") or char:GetAttribute("InDomain") then
		return true
	end
	local stun = char:GetAttribute("StunnedUntil")
	if type(stun) == "number" then
		return stun > os.clock() and stun < 1e8 or (stun > workspace:GetServerTimeNow())
	end
	return false
end

while true do
	task.wait(POLL)
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local st = state[plr]
		if not st then
			st = {}
			state[plr] = st
		end
		if not (hrp and hum and hum.Health > 0) then
			st.pad, st.mustLeave = nil, nil
		else
			local pad = padUnder(hrp.Position)
			if not pad then
				st.pad, st.mustLeave = nil, nil
			elseif st.mustLeave then
				-- arrived by lift: wait until they step off
			elseif st.pad ~= pad then
				st.pad, st.t0 = pad, os.clock()
			elseif os.clock() - st.t0 >= (pad:GetAttribute("Hold") or 1) and not busy(char) then
				local target = byId[pad:GetAttribute("To") or ""]
				if target and target.Parent then
					local look = target.CFrame.LookVector
					local dest = target.Position + Vector3.new(0, 3.2, 0)
					char:PivotTo(CFrame.lookAt(dest, dest + Vector3.new(look.X, 0, look.Z)))
					hrep.AssemblyLinearVelocity = Vector3.zero
					st.pad, st.mustLeave = target, true
				end
			end
		end
	end
end
