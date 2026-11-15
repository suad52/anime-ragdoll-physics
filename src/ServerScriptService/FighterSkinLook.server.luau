--!nocheck
-- ServerScriptService.FighterSkinLook (2026-11-10, skins fix): an equipped fighter skin shows ON THE FIGHTER, not only in
-- the moves' effects. While the player's Skin attribute is "Alt" (ShopService: the CURRENT Kit's skin is owned and
-- switched on), the character wears that skin's colourway from HudShared.PerkCatalog.SKIN_COLORS[kit] = { hi, lo },
-- mapped the way HudShared.CardArt's skin card dresses its figure (top / sleeves = hi, pants = lo, glow = hi):
--   * Shirt.Color3 and ShirtGraphic.Color3 = hi, Pants.Color3 = lo brightened toward its own hue (Color3 MULTIPLIES the
--     clothing texture, so the raw dark lo would just turn every pair of pants black)
--   * BodyColors only where the avatar has no clothing: no Shirt -> torso + arms hi, no Pants -> legs lo
--   * a thin Neon trim in hi (belt + wrist and ankle cuffs, folder "FighterSkinTrim") so it reads at a distance. Not a
--     Highlight: the engine draws 31 at most and the kits + NightOutlines already budget for them.
-- Done on the SERVER so every client sees it. Each changed property keeps its original in attributes on its own
-- instance (FSOrig_<prop> / FSSet_<prop>); if something else rewrites the property meanwhile (an Ultimate Outfit
-- ApplyDescription), that value becomes the new original. Everything goes back exactly when the skin is switched off,
-- the Kit changes to one without its skin on, or Kit is "None"; a respawn re-applies it on the new body.
-- Forms: while the character is Morphed / TitanForm (giant forms; ShifterServer.TitanSkins parks BodyColors and blanks
-- the clothes) or in Gear Fifth (Gear5Until ahead: GomuKit.Client.Gear5 whitens the body CLIENT-side, and a server
-- BodyColors write would undo that) nothing on the body is touched; the trim is removed while Morphed / TitanForm /
-- scaled (so it never balloons with a titan). It all re-applies once the form ends. Writes only happen when a value
-- differs, so the steady state costs nothing and never fights a client-local look.
-- Character attribute FighterSkin = the kit whose colourway is on the body now (nil = none).
-- Studio: script.Control:Invoke("state", player) -> a table describing what is applied.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Perks = require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("PerkCatalog"))

local POLL = 1
local TRIM = "FighterSkinTrim"
local EPS = 0.002
local WHITE = Color3.new(1, 1, 1)

-- what each clothing class gets: prop -> "hi" | "pants"
local CLOTH = {
	Shirt = { Color3 = "hi" },
	ShirtGraphic = { Color3 = "hi" },
	Pants = { Color3 = "pants" },
}
local BODY_TOP = { "TorsoColor3", "LeftArmColor3", "RightArmColor3" }
local BODY_LEGS = { "LeftLegColor3", "RightLegColor3" }

-- the trim: { limb, height, inflate, y as a fraction of the limb's height (0 = centre, -0.5 = bottom), y offset }
local TRIM_R15 = {
	{ "LowerTorso", 0.16, 0.16, 0.25, 0 },
	{ "LeftLowerArm", 0.14, 0.1, -0.5, 0.09 },
	{ "RightLowerArm", 0.14, 0.1, -0.5, 0.09 },
	{ "LeftLowerLeg", 0.14, 0.1, -0.5, 0.12 },
	{ "RightLowerLeg", 0.14, 0.1, -0.5, 0.12 },
}
local TRIM_R6 = {
	{ "Torso", 0.16, 0.16, -0.5, 0.16 },
	{ "Left Arm", 0.14, 0.1, -0.5, 0.2 },
	{ "Right Arm", 0.14, 0.1, -0.5, 0.2 },
	{ "Left Leg", 0.14, 0.1, -0.5, 0.15 },
	{ "Right Leg", 0.14, 0.1, -0.5, 0.15 },
}

local function near(a, b)
	if typeof(a) ~= "Color3" or typeof(b) ~= "Color3" then
		return false
	end
	return math.abs(a.R - b.R) < EPS and math.abs(a.G - b.G) < EPS and math.abs(a.B - b.B) < EPS
end

local function truthy(v)
	return v ~= nil and v ~= false and v ~= ""
end

-- lo pushed toward its own hue at full brightness (the multiply tint keeps the hue without blacking the texture out)
local function pantsTint(lo)
	local m = math.max(lo.R, lo.G, lo.B)
	if m < 1e-3 then
		return lo
	end
	return lo:Lerp(Color3.new(lo.R / m, lo.G / m, lo.B / m), 0.6)
end

-- the colourway for this player right now, or nil
local function colorsFor(p)
	if p:GetAttribute("Skin") ~= "Alt" then
		return nil
	end
	local kit = p:GetAttribute("Kit")
	local sc = type(kit) == "string" and Perks.SKIN_COLORS and Perks.SKIN_COLORS[kit]
	if type(sc) ~= "table" or typeof(sc[1]) ~= "Color3" then
		return nil
	end
	local hi = sc[1]
	local lo = typeof(sc[2]) == "Color3" and sc[2] or hi
	return { kit = kit, hi = hi, lo = lo, pants = pantsTint(lo) }
end

-- giant / morph forms own the body
local function formOwnsBody(char)
	return truthy(char:GetAttribute("Morphed")) or truthy(char:GetAttribute("TitanForm"))
end
local function gearFifth(char)
	local t = tonumber(char:GetAttribute("Gear5Until"))
	return t ~= nil and t > workspace:GetServerTimeNow()
end
local function scaled(char)
	local ok, s = pcall(function()
		return char:GetScale()
	 end)
	return ok and type(s) == "number" and math.abs(s - 1) > 0.05
end

-- set inst[prop] = value, remembering the original on the instance
local function setProp(inst, prop, value)
	local okR, cur = pcall(function()
		return inst[prop]
	end)
	if not okR then
		return
	end
	local aO, aS = "FSOrig_" .. prop, "FSSet_" .. prop
	local set = inst:GetAttribute(aS)
	if set == nil or not near(cur, set) then
		-- first tint, or something else rewrote it since ours: what is there now is the original
		inst:SetAttribute(aO, cur)
	end
	if not near(cur, value) then
		pcall(function()
			inst[prop] = value
		end)
	end
	if not near(set, value) then
		inst:SetAttribute(aS, value)
	end
end

-- put inst[prop] back (only if it still holds our value) and forget it
local function unsetProp(inst, prop)
	local aO, aS = "FSOrig_" .. prop, "FSSet_" .. prop
	local set = inst:GetAttribute(aS)
	if set == nil then
		return
	end
	local orig = inst:GetAttribute(aO)
	local okR, cur = pcall(function()
		return inst[prop]
	end)
	if okR and orig ~= nil and near(cur, set) then
		pcall(function()
			inst[prop] = orig
		end)
	end
	inst:SetAttribute(aO, nil)
	inst:SetAttribute(aS, nil)
end

local function tintLook(char, c)
	local shirt = char:FindFirstChildOfClass("Shirt")
	local pants = char:FindFirstChildOfClass("Pants")
	for _, ch in ipairs(char:GetChildren()) do
		local spec = CLOTH[ch.ClassName]
		if spec then
			for prop, which in pairs(spec) do
				setProp(ch, prop, c[which])
			end
		elseif ch:IsA("BodyColors") then
			for _, prop in ipairs(BODY_TOP) do
				if shirt then
					unsetProp(ch, prop)
				else
					setProp(ch, prop, c.hi)
				end
			end
			for _, prop in ipairs(BODY_LEGS) do
				if pants then
					unsetProp(ch, prop)
				else
					setProp(ch, prop, c.lo)
				end
			end
		end
	end
end

local function restoreLook(char)
	for _, ch in ipairs(char:GetChildren()) do
		local spec = CLOTH[ch.ClassName]
		if spec then
			for prop in pairs(spec) do
				unsetProp(ch, prop)
			end
		elseif ch:IsA("BodyColors") then
			for _, prop in ipairs(BODY_TOP) do
				unsetProp(ch, prop)
			end
			for _, prop in ipairs(BODY_LEGS) do
				unsetProp(ch, prop)
			end
		end
	end
end

local function removeTrim(char)
	local f = char:FindFirstChild(TRIM)
	if f then
		f:Destroy()
	end
end

-- the trim is still good: built for this kit and every band still welded to a limb of this character
local function trimValid(f, char, kit)
	if f:GetAttribute("Kit") ~= kit then
		return false
	end
	local n = 0
	for _, b in ipairs(f:GetChildren()) do
		local w = b:FindFirstChild("TrimWeld")
		if not (w and w.Part0 and w.Part0.Parent == char) then
			return false
		end
		n += 1
	end
	return n > 0 and n == (f:GetAttribute("Bands") or -1)
end

local function ensureTrim(char, c)
	local f = char:FindFirstChild(TRIM)
	if f and trimValid(f, char, c.kit) then
		return
	end
	if f then
		f:Destroy()
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local spots = (hum and hum.RigType == Enum.HumanoidRigType.R6) and TRIM_R6 or TRIM_R15
	f = Instance.new("Folder")
	f.Name = TRIM
	f:SetAttribute("Kit", c.kit)
	local n = 0
	for _, s in ipairs(spots) do
		local limb = char:FindFirstChild(s[1])
		if limb and limb:IsA("BasePart") then
			local sz = limb.Size
			local h, inf = s[2], s[3]
			local off = CFrame.new(0, sz.Y * s[4] + s[5], 0)
			local b = Instance.new("Part")
			b.Name = "Trim_" .. s[1]
			b.Size = Vector3.new(sz.X + inf, h, sz.Z + inf)
			b.Material = Enum.Material.Neon
			b.Color = c.hi
			b.TopSurface = Enum.SurfaceType.Smooth
			b.BottomSurface = Enum.SurfaceType.Smooth
			b.Anchored = false
			b.Massless = true
			b.CanCollide = false
			b.CanTouch = false
			b.CanQuery = false
			b.CastShadow = false
			b:SetAttribute("SkinTrim", true)
			b.CFrame = limb.CFrame * off
			local w = Instance.new("Weld")
			w.Name = "TrimWeld"
			w.Part0 = limb
			w.Part1 = b
			w.C0 = off
			w.Parent = b
			b.Parent = f
			n += 1
		end
	end
	f:SetAttribute("Bands", n)
	if n > 0 then
		f.Parent = char
	else
		f:Destroy()
	end
end

-- OUTFITS (2026-11-10, "the skins should use items from the roblox marketplace to make the avatar more like the
-- character"): when a kit has an entry in HudShared.SkinOutfits, an equipped skin DRESSES the avatar in that fighter's
-- look (hair, signature accessories, shirt + pants from the Roblox catalog) through a HumanoidDescription: the
-- player's own face, skin colour and body stay. The player's applied description is kept first and re-applied
-- exactly when the skin goes off, the kit changes or the player respawns (a new body starts from their own look).
-- A kit without an outfit entry keeps the tint + trim above.
local Outfits
do
	local ok, m = pcall(function()
		return require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("SkinOutfits", 10))
	end)
	Outfits = ok and type(m) == "table" and m or {}
end
local origDesc = setmetatable({}, { __mode = "k" }) -- [character] = the player's own HumanoidDescription
local applying = setmetatable({}, { __mode = "k" })
local function outfitFor(c)
	local o = c and Outfits[c.kit]
	return type(o) == "table" and o or nil
end
local function ids(list)
	local out = {}
	for _, v in ipairs(list or {}) do
		table.insert(out, tostring(v))
	end
	return table.concat(out, ",")
end
local function applyOutfit(char, hum, kit, o)
	if char:GetAttribute("SkinOutfit") == kit or applying[char] then
		return
	end
	applying[char] = true
	local ok, err = pcall(function()
		if not origDesc[char] then
			origDesc[char] = hum:GetAppliedDescription()
		end
		local d = origDesc[char]:Clone()
		-- the costume REPLACES these slots (an empty string strips the player's own pieces there)
		d.HairAccessory = ids(o.hair)
		d.HatAccessory = ids(o.hat)
		d.FaceAccessory = ids(o.face)
		d.NeckAccessory = ids(o.neck)
		d.ShouldersAccessory = ids(o.shoulders)
		d.FrontAccessory = ids(o.front)
		d.BackAccessory = ids(o.back)
		d.WaistAccessory = ids(o.waist)
		d.Shirt = o.shirt or 0
		d.Pants = o.pants or 0
		d.GraphicTShirt = 0
		-- layered (3D) clothing: the costume's pieces only - the player's own layered clothes come off
		local layered = {}
		for i, l in ipairs(o.layered or {}) do
			table.insert(layered, { AssetId = l.id, AccessoryType = Enum.AccessoryType[l.type], IsLayered = true, Order = i })
		end
		local rigid = {}
		for _, a in ipairs(d:GetAccessories(true)) do
			if not a.IsLayered then
				table.insert(rigid, a)
			end
		end
		for _, l in ipairs(layered) do
			table.insert(rigid, l)
		end
		d:SetAccessories(rigid, true)
		hum:ApplyDescription(d)
	end)
	applying[char] = nil
	if ok then
		char:SetAttribute("SkinOutfit", kit)
	else
		warn("[FighterSkinLook] outfit for " .. tostring(kit) .. " failed: " .. tostring(err))
		char:SetAttribute("SkinOutfit", nil)
	end
end
local function removeOutfit(char, hum)
	if not char:GetAttribute("SkinOutfit") or applying[char] then
		return
	end
	applying[char] = true
	local ok, err = pcall(function()
		if origDesc[char] then
			hum:ApplyDescription(origDesc[char])
		end
	end)
	applying[char] = nil
	char:SetAttribute("SkinOutfit", nil)
	origDesc[char] = nil
	if not ok then
		warn("[FighterSkinLook] outfit restore failed: " .. tostring(err))
	end
end

local function reconcile(p)
	local char = p.Character
	if not (char and char.Parent) then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return -- a body that is dying keeps whatever it wore
	end
	local c = colorsFor(p)
	local owned = formOwnsBody(char)
	local o = outfitFor(c)
	if not owned and not gearFifth(char) then
		-- a costume from the catalog replaces the tint + trim for kits that have one
		if o then
			restoreLook(char)
			removeTrim(char)
			applyOutfit(char, hum, c.kit, o)
			if char:GetAttribute("FighterSkin") ~= c.kit then
				char:SetAttribute("FighterSkin", c.kit)
			end
			return
		elseif char:GetAttribute("SkinOutfit") then
			removeOutfit(char, hum)
		end
	end
	if o then
		return -- a form owns the body: leave the costume as it is until the form ends
	end
	if not owned and not gearFifth(char) then
		if c then
			tintLook(char, c)
		else
			restoreLook(char)
		end
		local want = c and c.kit or nil
		if char:GetAttribute("FighterSkin") ~= want then
			char:SetAttribute("FighterSkin", want)
		end
	end
	if c and not owned and not scaled(char) then
		ensureTrim(char, c)
	else
		removeTrim(char)
	end
end

-- coalesced: many triggers in one frame -> one reconcile
local pending = {}
local function schedule(p)
	if pending[p] then
		return
	end
	pending[p] = true
	task.defer(function()
		pending[p] = nil
		if p.Parent then
			local ok, err = pcall(reconcile, p)
			if not ok then
				warn("[FighterSkinLook] " .. p.Name .. ": " .. tostring(err))
			end
		end
	end)
end

local WATCH_CLASS = { Shirt = true, Pants = true, ShirtGraphic = true, BodyColors = true, Humanoid = true }
local WATCH_ATTR = { Morphed = true, TitanForm = true, Gear5Until = true }

local function onCharacter(p, char)
	char.ChildAdded:Connect(function(ch)
		if WATCH_CLASS[ch.ClassName] then
			schedule(p)
		end
	end)
	char.ChildRemoved:Connect(function(ch)
		if WATCH_CLASS[ch.ClassName] then
			schedule(p)
		end
	end)
	char.AttributeChanged:Connect(function(name)
		if WATCH_ATTR[name] then
			schedule(p)
		end
	end)
	schedule(p)
end

local function onPlayer(p)
	p:GetAttributeChangedSignal("Skin"):Connect(function()
		schedule(p)
	end)
	p:GetAttributeChangedSignal("Kit"):Connect(function()
		schedule(p)
	end)
	p.CharacterAdded:Connect(function(char)
		onCharacter(p, char)
	end)
	p.CharacterAppearanceLoaded:Connect(function()
		schedule(p)
	end)
	if p.Character then
		onCharacter(p, p.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	onPlayer(p)
end
Players.PlayerRemoving:Connect(function(p)
	pending[p] = nil
end)

-- backstop: forms that expire on a clock (Gear5Until), scale changes, a limb replaced under the trim
task.spawn(function()
	while true do
		task.wait(POLL)
		for _, p in ipairs(Players:GetPlayers()) do
			schedule(p)
		end
	end
end)

if RunService:IsStudio() then
	local ctl = Instance.new("BindableFunction")
	ctl.Name = "Control"
	ctl.OnInvoke = function(cmd, p)
		if type(p) == "string" then
			p = Players:FindFirstChild(p)
		end
		p = p or Players:GetPlayers()[1]
		if cmd == "state" and p then
			local char = p.Character
			local function col(cls, prop)
				local i = char and char:FindFirstChildOfClass(cls)
				return i and tostring(i[prop]) or "none"
			end
			local f = char and char:FindFirstChild(TRIM)
			local c = colorsFor(p)
			return {
				Skin = p:GetAttribute("Skin"), Kit = p:GetAttribute("Kit"), EquipSkins = p:GetAttribute("EquipSkins"),
				OwnedSkins = p:GetAttribute("OwnedSkins"), FighterSkin = char and char:GetAttribute("FighterSkin"),
				wantHi = c and tostring(c.hi), wantPants = c and tostring(c.pants),
				shirt = col("Shirt", "Color3"), pants = col("Pants", "Color3"), graphic = col("ShirtGraphic", "Color3"),
				torso = col("BodyColors", "TorsoColor3"), legs = col("BodyColors", "LeftLegColor3"),
				trimBands = f and #f:GetChildren() or 0, trimColor = f and f:FindFirstChildWhichIsA("BasePart") and tostring(f:FindFirstChildWhichIsA("BasePart").Color) or nil,
				formOwnsBody = char and formOwnsBody(char) or false, gearFifth = char and gearFifth(char) or false,
			}
		elseif cmd == "reconcile" and p then
			reconcile(p)
			return true
		end
		return nil
	end
	ctl.Parent = script
end
