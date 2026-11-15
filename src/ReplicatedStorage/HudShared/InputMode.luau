--!nocheck
-- ReplicatedStorage.HudShared.InputMode (2026-11-08, client): is this player on a TOUCH screen right now? HUDs use it to
-- drop PC key labels (the move bar's M1 / Q / E / R / G chips, the dash gauge's SHIFT) on phones and tablets.
--   InputMode.isTouch() -> bool
--   InputMode.changed(fn) -> RBXScriptConnection    fn(isTouch) every time it flips
-- Rule: UserInputService.PreferredInput when the engine has it (Touch = touch UI; it follows the device last used, so
-- a touch-screen laptop flips with its keyboard). Otherwise: a touch screen with no keyboard starts in touch mode, and
-- the last input flips it (a tap -> touch, a key press or mouse click -> keyboard).
-- Studio: LocalPlayer attribute InputModeOverride = "Touch" | "Keyboard" forces either (Studio's device emulator,
-- which reports a touch screen with no keyboard, works too).
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local InputMode = {}
local changedEvent = Instance.new("BindableEvent")

local hasPreferred = pcall(function()
	return UserInputService.PreferredInput
end)
local lastTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local function compute()
	local p = Players.LocalPlayer
	local o = p and p:GetAttribute("InputModeOverride")
	if o == "Touch" then
		return true
	elseif o == "Keyboard" then
		return false
	end
	if hasPreferred then
		local ok, v = pcall(function()
			return UserInputService.PreferredInput == Enum.PreferredInput.Touch
		end)
		if ok then
			return v
		end
	end
	return lastTouch
end

local current = compute()
local function refresh()
	local v = compute()
	if v ~= current then
		current = v
		changedEvent:Fire(v)
	end
end

function InputMode.isTouch()
	return current
end

function InputMode.changed(fn)
	return changedEvent.Event:Connect(fn)
end

if hasPreferred then
	pcall(function()
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(refresh)
	end)
end
UserInputService.LastInputTypeChanged:Connect(function(t)
	if t == Enum.UserInputType.Touch then
		lastTouch = true
	elseif t == Enum.UserInputType.Keyboard or t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2 then
		lastTouch = false
	else
		return
	end
	refresh()
end)
if Players.LocalPlayer then
	Players.LocalPlayer:GetAttributeChangedSignal("InputModeOverride"):Connect(refresh)
end

return InputMode
