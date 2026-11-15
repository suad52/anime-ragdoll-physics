--!nocheck
-- MINEFIELD: fourteen pressure mines (tag Mine: Radius, Power) in a roped-off patch of dirt. They re-arm themselves.
return function(K, model, cf, S)
	local PAL, C = K.PAL, K.C
	local M = Enum.Material
	local function L(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	local HW = 24
	local cs = { L(-HW, 0, -HW), L(HW, 0, -HW), L(HW, 0, HW), L(-HW, 0, HW) }
	for i = 1, 4 do
		local a, b = cs[i].Position, cs[i % 4 + 1].Position
		for k = 0, 4 do
			K.cyl(model, "Stake", 0.5, 3.4, CFrame.new(a:Lerp(b, k / 5) + Vector3.new(0, 1.7, 0)), PAL.woodDark, M.Wood)
		end
		if i ~= 1 then
			K.part(model, "Tape", Vector3.new(0.15, 0.5, (b - a).Magnitude), CFrame.lookAt((a + b) / 2 + Vector3.new(0, 2.9, 0), b + Vector3.new(0, 2.9, 0)), PAL.hazard, M.Fabric, { CanCollide = false, CastShadow = false })
		end
	end
	local rng = Random.new(77)
	local placed = {}
	while #placed < 14 do
		local p = Vector3.new(rng:NextNumber(-HW + 4, HW - 4), 0, rng:NextNumber(-HW + 4, HW - 4))
		local ok = true
		for _, q in ipairs(placed) do
			if (q - p).Magnitude < 8 then
				ok = false
			end
		end
		if ok then
			table.insert(placed, p)
			local mine = K.cyl(model, "Mine", 3.4, 0.6, L(p.X, 0.2, p.Z), C(52, 58, 46), M.Metal, { tag = "Mine", attrs = { Radius = 13, Power = 84 }, CanCollide = false })
			K.cyl(mine, "Lamp", 0.9, 0.7, L(p.X, 0.25, p.Z), PAL.red, M.Neon, { CastShadow = false, CanCollide = false, CanTouch = false })
		end
	end
	K.danger(model, L(-8, 0, -HW - 3), "MINES")
	K.danger(model, L(HW + 3, 0, 8) * CFrame.Angles(0, math.rad(90), 0), "MINES")
	K.station(model, L(-6, 0.3, 3), "stand", 10, 1)
	K.station(model, L(9, 0.3, -6) * CFrame.Angles(0, 2, 0), "stand", 10, 1)
end
