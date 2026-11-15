--!nocheck
-- GojoShared.SkinTint (2026-11-07, PERKS skins - owner kits-A): turns finished VFX into a kit's alternate colourway.
-- Used by the Limitless (GojoClient) and Vulpine (KitServer) kits; any other kit may use it too. Client AND server.
--   SkinTint.isAlt(player)       -> true when that player's Skin attribute is "Alt" (ShopService writes it)
--   SkinTint.mapper(spec)        -> a Color3 -> Color3 function. spec = {
--        Exact = { ["r,g,b"] = Color3 },   exact colours swapped first (0-255 ints, e.g. a construct's fixed fur colours)
--        Gray = 0.06,                     colours less saturated than this (white / grey / black) are left alone
--        SatFloor = 0.3,                  sat/val multipliers only touch colours at least this saturated
--        Bands = { { from, to, hue, sat?, val? } },  hue bands in DEGREES (wrapping: from 330 to 45 is fine)
--      }
--   SkinTint.apply(inst, map)    recolours ONE instance (part, emitter, beam, trail, light, highlight, GUI text...)
--   SkinTint.applyTree(root, map) root + every descendant
--   SkinTint.watch(folder, map)  recolours everything ever parented under `folder` (deferred one resumption, so the
--                                code that built it has finished setting it up). Returns the connection.
-- Every instance is recoloured at most once (mapping is not idempotent). Parts are only recoloured when they are
-- VFX materials (Neon / ForceField / Glass / SmoothPlastic), and world-lit smoke/dust emitters are left alone, so
-- rubble and dust keep the ground's colour.
local M = {}

function M.isAlt(player)
	return typeof(player) == "Instance" and player:IsA("Player") and player:GetAttribute("Skin") == "Alt"
end

local function key(c)
	return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
M.key = key

function M.mapper(spec)
	spec = spec or {}
	local exact, bands = spec.Exact or {}, spec.Bands or {}
	local gray, floor = spec.Gray or 0.06, spec.SatFloor or 0.3
	return function(c)
		if typeof(c) ~= "Color3" then
			return c
		end
		local ex = exact[key(c)]
		if ex then
			return ex
		end
		local h, s, v = c:ToHSV()
		if s < gray then
			return c
		end
		local deg = h * 360
		for _, b in ipairs(bands) do
			local inside
			if b.from <= b.to then
				inside = deg >= b.from and deg < b.to
			else
				inside = deg >= b.from or deg < b.to
			end
			if inside then
				if s >= floor then
					s = math.clamp(s * (b.sat or 1), 0, 1)
					v = math.clamp(v * (b.val or 1), 0, 1)
				end
				return Color3.fromHSV((b.hue % 360) / 360, s, v)
			end
		end
		return c
	end
end

local function seq(cs, map)
	local out = {}
	for i, k in ipairs(cs.Keypoints) do
		out[i] = ColorSequenceKeypoint.new(k.Time, map(k.Value))
	end
	return ColorSequence.new(out)
end

local VFX_MAT = {
	[Enum.Material.Neon] = true,
	[Enum.Material.ForceField] = true,
	[Enum.Material.Glass] = true,
	[Enum.Material.SmoothPlastic] = true,
}

local done = setmetatable({}, { __mode = "k" })

local function recolour(inst, map)
	if inst:IsA("BasePart") then
		if VFX_MAT[inst.Material] then
			inst.Color = map(inst.Color)
		end
	elseif inst:IsA("ParticleEmitter") then
		-- world-lit smoke and dust (no glow of their own) keep their colour
		if not (inst.LightEmission <= 0.05 and inst.LightInfluence >= 0.5) then
			inst.Color = seq(inst.Color, map)
		end
	elseif inst:IsA("Beam") or inst:IsA("Trail") then
		inst.Color = seq(inst.Color, map)
	elseif inst:IsA("Light") then
		inst.Color = map(inst.Color)
	elseif inst:IsA("Highlight") then
		inst.FillColor = map(inst.FillColor)
		inst.OutlineColor = map(inst.OutlineColor)
	elseif inst:IsA("TextLabel") or inst:IsA("TextButton") then
		inst.TextColor3 = map(inst.TextColor3)
	elseif inst:IsA("UIStroke") then
		inst.Color = map(inst.Color)
	elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		inst.ImageColor3 = map(inst.ImageColor3)
	elseif inst:IsA("Decal") then
		inst.Color3 = map(inst.Color3)
	elseif inst:IsA("Fire") then
		inst.Color = map(inst.Color)
		inst.SecondaryColor = map(inst.SecondaryColor)
	end
end

function M.apply(inst, map)
	if typeof(inst) ~= "Instance" or done[inst] or not map then
		return
	end
	done[inst] = true
	pcall(recolour, inst, map)
end

function M.applyTree(root, map)
	if typeof(root) ~= "Instance" then
		return
	end
	M.apply(root, map)
	for _, d in ipairs(root:GetDescendants()) do
		M.apply(d, map)
	end
end

function M.watch(folder, map)
	for _, d in ipairs(folder:GetDescendants()) do
		M.apply(d, map)
	end
	return folder.DescendantAdded:Connect(function(d)
		task.defer(M.apply, d, map)
	end)
end

return M
