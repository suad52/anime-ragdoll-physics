--!nocheck
-- FoxSageClient: keys and the ability bar for the Fox Sage kit. Active only while the player's "Kit" attribute is
-- "FoxSage"; the server (FoxSageService) decides everything, and FoxSageVFX draws the moves for every player.
--   Q Spiral Orb   E Spiral Shuriken   R Sage Mode   F Nine-Tailed Fox
--   in beast form:  Click Claw   Q Roar   E Beast Bomb
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local FoxShared = ReplicatedStorage:WaitForChild("FoxSageShared")
local CFG = require(FoxShared:WaitForChild("Config"))
local Remotes = FoxShared:WaitForChild("Remotes")
local FoxRequest = Remotes:WaitForChild("FoxRequest")
local FoxResult = Remotes:WaitForChild("FoxResult")
-- (2026-11-11 keybinds) owner: "have the option to have keybinds". The Q/E/R/F presses below are read through
-- HudShared.Keybinds - logical() turns the physical key into the DEFAULT key whose action the player bound to it - and
-- the key chips draw Keybinds.label() (redrawn on Keybinds.Changed). With no rebinds both return the key itself, so
-- default play is unchanged. M1 / touch stay raw (not rebindable).
local Keybinds = require(game:GetService("ReplicatedStorage"):WaitForChild("HudShared"):WaitForChild("Keybinds"))

local function now()
	return workspace:GetServerTimeNow()
end
local function isFox()
	return player:GetAttribute("Kit") == "FoxSage"
end
local function charAttr(name)
	local c = player.Character
	return c and c:GetAttribute(name)
end
local function inBeast()
	return charAttr("FoxBeast") == true
end
local function inSage()
	return charAttr("SageMode") == true
end

local debugAim = nil
local function aim()
	return debugAim or workspace.CurrentCamera.CFrame.LookVector
end

local cooldownEnd = {}
local COOLDOWN = {
	Orb = CFG.Orb.Cooldown, Shuriken = CFG.Shuriken.Cooldown, Sage = CFG.Sage.Cooldown, Beast = CFG.Beast.Cooldown,
	Swipe = CFG.Beast.Swipe.Cooldown, Roar = CFG.Beast.Roar.Cooldown, Bomb = CFG.Beast.Bomb.Cooldown,
}

local function send(ability, payload)
	if not isFox() then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or now() < (cooldownEnd[ability] or 0) then
		return
	end
	FoxRequest:FireServer(ability, payload or {})
end

local function useQ()
	if inBeast() then
		send("Roar")
	else
		send("Orb", { aimDir = aim() })
	end
end
local function useE()
	if inBeast() then
		send("Bomb", { aimDir = aim() })
	else
		send("Shuriken", { aimDir = aim() })
	end
end
local function useR()
	send("Sage")
end
local function useF()
	send("Beast")
end
local function useClick()
	if inBeast() then
		send("Swipe", { aimDir = aim() })
	end
end

FoxResult.OnClientEvent:Connect(function(ability, ok, info)
	if type(info) == "table" and type(info.cooldownEnd) == "number" then
		cooldownEnd[ability] = info.cooldownEnd
	end
end)

---------------------------------------------------------------------------------------------------
-- HUD (same look as the Gojo bar, bottom right)
local gui = Instance.new("ScreenGui")
gui.Name = "FoxSageHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local bar = Instance.new("Frame")
bar.Name = "AbilityBar"
bar.AnchorPoint = Vector2.new(1, 1)
bar.Position = UDim2.new(1, -22, 1, -22)
bar.Size = UDim2.fromOffset(380, 112)
bar.BackgroundTransparency = 1
bar.Visible = false
bar.Parent = gui
local barScale = Instance.new("UIScale")
barScale.Parent = bar

local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = r or UDim.new(0, 14)
	c.Parent = p
end
local function stroke(p, color, th, tr)
	local st = Instance.new("UIStroke")
	st.Color = color
	st.Thickness = th
	st.Transparency = tr or 0
	st.Parent = p
	return st
end
local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamBlack
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function button(size, pos, bg, wide)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Text = ""
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = pos
	b.Size = wide and UDim2.fromOffset(size.X, size.Y) or UDim2.fromOffset(size, size)
	b.BackgroundColor3 = bg
	b.Parent = bar
	corner(b, UDim.new(0, wide and 12 or 18))
	local st = stroke(b, Color3.fromRGB(255, 190, 110), 2, 0.2)
	local orb, grad
	if not wide then
		orb = Instance.new("Frame")
		orb.AnchorPoint = Vector2.new(0.5, 0.5)
		orb.Position = UDim2.fromScale(0.5, 0.42)
		orb.Size = UDim2.fromScale(0.42, 0.42)
		orb.BackgroundColor3 = Color3.new(1, 1, 1)
		orb.Parent = b
		corner(orb, UDim.new(1, 0))
		grad = Instance.new("UIGradient")
		grad.Rotation = 45
		grad.Parent = orb
	end
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(wide and 24 or 26, wide and 22 or 20)
	chip.Position = UDim2.fromOffset(wide and 7 or 6, wide and 7 or 6)
	chip.BackgroundColor3 = Color3.fromRGB(24, 14, 8)
	chip.Parent = b
	corner(chip, UDim.new(0, 6))
	local key = label(chip, { Size = UDim2.fromScale(1, 1), Text = "", TextScaled = true, Font = Enum.Font.GothamBold, ZIndex = 2 })
	local name, sub
	if wide then
		name = label(b, { Size = UDim2.new(1, -44, 0, 16), Position = UDim2.fromOffset(38, 4), Text = "", TextScaled = true, ZIndex = 2 })
		sub = label(b, { Size = UDim2.new(1, -44, 0, 11), Position = UDim2.fromOffset(38, 21), Text = "", TextScaled = true, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(255, 200, 140), ZIndex = 2 })
	else
		name = label(b, { Size = UDim2.new(1, -8, 0, 14), Position = UDim2.new(0, 4, 1, -20), Text = "", TextScaled = true, ZIndex = 2 })
	end
	local cd = Instance.new("Frame")
	cd.BackgroundColor3 = Color3.new(0, 0, 0)
	cd.BackgroundTransparency = 0.35
	cd.ZIndex = 3
	if wide then
		cd.AnchorPoint = Vector2.new(1, 0)
		cd.Position = UDim2.fromScale(1, 0)
		cd.Size = UDim2.fromScale(0, 1)
	else
		cd.AnchorPoint = Vector2.new(0, 1)
		cd.Position = UDim2.fromScale(0, 1)
		cd.Size = UDim2.fromScale(1, 0)
	end
	cd.Parent = b
	corner(cd, UDim.new(0, wide and 12 or 18))
	local cdText = label(b, { Size = wide and UDim2.fromScale(1, 1) or UDim2.fromScale(1, 0.4), Position = wide and UDim2.new() or UDim2.fromScale(0, 0.22), Text = "", TextScaled = true, ZIndex = 4 })
	return { button = b, stroke = st, grad = grad, key = key, name = name, sub = sub, cd = cd, cdText = cdText, wide = wide }
end

local ORANGE_BG = Color3.fromRGB(60, 28, 10)
local slots = {
	q = button(104, UDim2.new(1, 0, 1, -16), ORANGE_BG),
	e = button(72, UDim2.new(1, -116, 1, -16), Color3.fromRGB(26, 34, 52)),
	r = button(72, UDim2.new(1, -198, 1, -16), Color3.fromRGB(48, 40, 10)),
	click = button(72, UDim2.new(1, -280, 1, -16), Color3.fromRGB(60, 14, 14)),
	f = button(Vector2.new(186, 36), UDim2.new(1, 0, 1, -132), Color3.fromRGB(70, 22, 8), true),
}
do
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 200, 170))
	g.Parent = slots.f.button
	slots.f.button.BackgroundColor3 = Color3.fromRGB(80, 26, 10)
end

-- what each slot means in each form
local FORMS = {
	normal = {
		q = { Enum.KeyCode.Q, "SPIRAL ORB", "Orb", Color3.fromRGB(235, 248, 255), Color3.fromRGB(70, 150, 255) },
		e = { Enum.KeyCode.E, "SPIRAL SHURIKEN", "Shuriken", Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 220, 255) },
		r = { Enum.KeyCode.R, "SAGE MODE", "Sage", Color3.fromRGB(255, 244, 200), Color3.fromRGB(240, 170, 40) },
	},
	beast = {
		q = { Enum.KeyCode.Q, "ROAR", "Roar", Color3.fromRGB(255, 230, 190), Color3.fromRGB(255, 120, 40) },
		e = { Enum.KeyCode.E, "BEAST BOMB", "Bomb", Color3.fromRGB(220, 190, 255), Color3.fromRGB(70, 20, 120) },
		r = { Enum.KeyCode.R, "SAGE MODE", "Sage", Color3.fromRGB(255, 244, 200), Color3.fromRGB(240, 170, 40) },
		click = { "M1", "CLAW", "Swipe", Color3.fromRGB(255, 210, 200), Color3.fromRGB(230, 40, 30) },
	},
}

local function setSlot(slot, spec)
	-- (2026-11-11 keybinds) a KeyCode chip shows the player's own binding; "M1" (the click) is not rebindable
	slot.key.Text = typeof(spec[1]) == "EnumItem" and Keybinds.label(spec[1]) or spec[1]
	slot.name.Text = spec[2]
	slot.ability = spec[3]
	if slot.grad then
		slot.grad.Color = ColorSequence.new(spec[4], spec[5])
	end
end

local lastForm
local function refreshForm()
	local form = inBeast() and "beast" or "normal"
	if form == lastForm then
		return
	end
	lastForm = form
	for k, spec in pairs(FORMS[form]) do
		setSlot(slots[k], spec)
	end
	slots.click.button.Visible = form == "beast"
	slots.f.key.Text = Keybinds.label(Enum.KeyCode.F)
	slots.f.ability = "Beast"
	slots.f.name.Text = "NINE-TAILED FOX"
end
refreshForm()
-- (2026-11-11 keybinds) a rebind redraws every chip: forget the form so refreshForm re-sets all the slots
Keybinds.Changed:Connect(function()
	lastForm = nil
	refreshForm()
end)

local function updateSlot(slot)
	if not slot.ability or not slot.button.Visible then
		return
	end
	local rem = (cooldownEnd[slot.ability] or 0) - now()
	local total = COOLDOWN[slot.ability] or 1
	local frac = math.clamp(rem / total, 0, 1)
	slot.cd.Size = slot.wide and UDim2.fromScale(frac, 1) or UDim2.fromScale(1, frac)
	slot.cdText.Text = rem > 0 and (rem >= 10 and string.format("%.0f", rem) or string.format("%.1f", rem)) or ""
end

local function updateTimers()
	-- active forms count down on their own buttons instead of a cooldown
	local sageUntil = charAttr("SageUntil")
	if inSage() and type(sageUntil) == "number" then
		local left = sageUntil - now()
		slots.r.cdText.Text = left > 0 and string.format("%.0f", left) or ""
		slots.r.cdText.TextColor3 = Color3.fromRGB(255, 220, 90)
		slots.r.stroke.Color = Color3.fromRGB(255, 220, 90)
		slots.r.cd.Size = UDim2.fromScale(1, 0)
	else
		slots.r.cdText.TextColor3 = Color3.new(1, 1, 1)
		slots.r.stroke.Color = Color3.fromRGB(255, 190, 110)
	end
	local beastUntil = charAttr("FoxBeastUntil")
	if inBeast() and type(beastUntil) == "number" then
		local left = beastUntil - now()
		slots.f.sub.Text = left > 0 and string.format("BEAST FORM  %.0fs", left) or "BEAST FORM"
		slots.f.cd.Size = UDim2.fromScale(0, 1)
		slots.f.cdText.Text = ""
	else
		slots.f.sub.Text = "BEAST FORM"
	end
end

-- buttons double as touch controls
slots.q.button.Activated:Connect(useQ)
slots.e.button.Activated:Connect(useE)
slots.r.button.Activated:Connect(useR)
slots.f.button.Activated:Connect(useF)
slots.click.button.Activated:Connect(useClick)

-- (2026-11-09) TOUCH: a plain tap on the screen (not on a button or the thumbstick, not a camera drag) is an M1
UserInputService.TouchTapInWorld:Connect(function(_, processedByUI)
	if processedByUI or _G.SandboxArmed then -- (2026-11-14) not while a sandbox weapon / GRAB is out (SandboxClient's HIT button owns the tap then)
		return
	end
	if isFox() then
		useClick()
	end
end)
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe or not isFox() then
		return
	end
	-- (2026-11-11 keybinds) the DEFAULT key whose action the player bound to this key (Unknown if Q was moved away)
	local k = Keybinds.logical(input.KeyCode)
	if k == Enum.KeyCode.Q then
		useQ()
	elseif k == Enum.KeyCode.E then
		useE()
	elseif k == Enum.KeyCode.R then
		useR()
	elseif k == Enum.KeyCode.F then
		useF()
	elseif (input.UserInputType == Enum.UserInputType.MouseButton1 and not _G.SandboxArmed) then
		useClick()
	end
end)

local function applyKit()
	bar.Visible = isFox()
end
applyKit()
player:GetAttributeChangedSignal("Kit"):Connect(applyKit)

RunService.Heartbeat:Connect(function()
	if not bar.Visible then
		return
	end
	refreshForm()
	for _, slot in pairs(slots) do
		updateSlot(slot)
	end
	updateTimers()
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	barScale.Scale = math.clamp(vp.Y / 720, 0.75, 1.3)
end)

if RunService:IsStudio() then
	local dbg = ReplicatedStorage:FindFirstChild("GojoShared") and ReplicatedStorage.GojoShared:FindFirstChild("ClientDebug")
	if dbg then
		dbg.Event:Connect(function(cmd, arg)
			if cmd == "Aim" then
				debugAim = (typeof(arg) == "Vector3" and arg.Magnitude > 0) and arg.Unit or nil
			elseif cmd == "Fox" and isFox() then
				if arg == "Orb" or arg == "Roar" then
					useQ()
				elseif arg == "Shuriken" or arg == "Bomb" then
					useE()
				elseif arg == "Sage" then
					useR()
				elseif arg == "Beast" then
					useF()
				elseif arg == "Swipe" then
					useClick()
				end
			end
		end)
	end
end

print("[FoxSageClient] ready")
