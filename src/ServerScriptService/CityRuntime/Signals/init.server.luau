-- ServerScriptService.CityRuntime.Signals (Script) - NEON SHIBUYA traffic + pedestrian signal cycles (streets builder).
-- Runs the two cycles of Plan.signals (CONTRACT.md section 7), publishes ScramblePhase / ScramblePhaseEnd /
-- CrossPhase / CrossPhaseEnd / SignalEpoch (server time, workspace:GetServerTimeNow()) on workspace.City.Streets, and
-- lights every part tagged CitySignal under workspace.City by its Group / Lamp attributes (Neon + signal colour when
-- lit, SIGNAL_OFF SmoothPlastic when not). Lamps added later (any district, regen, rebuilds) are picked up by the tag
-- signal; destruction debris clones live outside workspace.City and are ignored. Only Color / Material are written.
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local Plan = require(ServerStorage:WaitForChild("CityGen"):WaitForChild("Plan"))
local Core = require(script:WaitForChild("SignalCore"))
local palette = Plan.palette
local TAG = "CitySignal"
local TICK = 0.1

local city = workspace:WaitForChild("City")
local streets = city:WaitForChild("Streets")

local buckets = {} -- "Group|Lamp" -> { [part] = lampName }
local keyOf = {} -- part -> key
local lit = {} -- key -> last applied state

local function add(p, tries)
	if keyOf[p] or not p:IsA("BasePart") or not p:IsDescendantOf(city) then
		return
	end
	local g, l = p:GetAttribute("Group"), p:GetAttribute("Lamp")
	if not (g and l) then
		if (tries or 0) < 5 then
			task.delay(1, add, p, (tries or 0) + 1) -- attributes may land right after the tag
		end
		return
	end
	local k = g .. "|" .. l
	keyOf[p] = k
	buckets[k] = buckets[k] or {}
	buckets[k][p] = l
	if lit[k] ~= nil then
		Core.paint(p, l, lit[k], palette)
	end
end

local function remove(p)
	local k = keyOf[p]
	if k then
		buckets[k][p] = nil
		keyOf[p] = nil
	end
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)
for _, p in ipairs(CollectionService:GetTagged(TAG)) do
	add(p)
end

local epoch = workspace:GetServerTimeNow()
streets:SetAttribute("SignalEpoch", epoch)
local published = {}

while true do
	local now = workspace:GetServerTimeNow()
	local states, attrs = Core.states(now - epoch, Plan.signals)
	if attrs.ScramblePhase ~= published.ScramblePhase or attrs.ScramblePhaseEnd ~= published.ScramblePhaseEnd then
		streets:SetAttribute("ScramblePhase", attrs.ScramblePhase)
		streets:SetAttribute("ScramblePhaseEnd", epoch + attrs.ScramblePhaseEnd)
		published.ScramblePhase, published.ScramblePhaseEnd = attrs.ScramblePhase, attrs.ScramblePhaseEnd
	end
	if attrs.CrossPhase ~= published.CrossPhase or attrs.CrossPhaseEnd ~= published.CrossPhaseEnd then
		streets:SetAttribute("CrossPhase", attrs.CrossPhase)
		streets:SetAttribute("CrossPhaseEnd", epoch + attrs.CrossPhaseEnd)
		published.CrossPhase, published.CrossPhaseEnd = attrs.CrossPhase, attrs.CrossPhaseEnd
	end
	for k, on in pairs(states) do
		if lit[k] ~= on then
			lit[k] = on
			local b = buckets[k]
			if b then
				for p, l in pairs(b) do
					if p.Parent and p:IsDescendantOf(city) then
						Core.paint(p, l, on, palette)
					else
						remove(p)
					end
				end
			end
		end
	end
	task.wait(TICK)
end
