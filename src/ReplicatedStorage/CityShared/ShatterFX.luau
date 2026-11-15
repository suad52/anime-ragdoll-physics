-- ReplicatedStorage.CityShared.ShatterFX (owner: destruction) - the client half of the city destruction.
-- CityShatterClient feeds it the server's CityShatter batches. Everything here is client-only and capped:
--   glass  -> thin glass shards (pooled anchored WedgeParts, CanCollide / CanQuery / CanTouch false) flown by a
--             tiny ballistic sim with one short raycast per moving shard per frame (bounce, then settle + fade)
--   screen -> the same shards, part of them neon, plus a burst of sparks
--   dust   -> a puff of dust (one ParticleEmitter:Emit on a Terrain attachment) where a panel / prop tore off
-- Caps: MAX_SHARDS alive (oldest recycled), MAX_DUST emitters, nothing beyond MAX_DIST from the camera.
-- FX.new(opts) -> fx with fx:handle(batch), fx:step(dt), fx:destroy(), fx.count(). opts: config, folder, camera.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FX = {}

local V3 = Vector3.new
local CF = CFrame.new
local clamp = math.clamp

local DUST_TEX = "rbxasset://textures/particles/smoke_main.dds"
local SPARK_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local NEONS = { Color3.fromRGB(255, 60, 200), Color3.fromRGB(40, 240, 255), Color3.fromRGB(255, 190, 60), Color3.fromRGB(170, 255, 60) }

function FX.new(opts)
	opts = opts or {}
	local CFG = (opts.config or require(ReplicatedStorage:WaitForChild("CityShared"):WaitForChild("DestructionConfig"))).CLIENT
	local rng = Random.new()
	local folder = opts.folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "CityShatterLocal"
		folder.Parent = workspace
	end
	local self = { shards = {}, pool = {}, dust = {}, folder = folder }

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.RespectCanCollide = true
	local function refreshFilter()
		local ex = { folder }
		local deb = workspace:FindFirstChild("CityDebris")
		if deb then
			table.insert(ex, deb)
		end
		local npcs = workspace:FindFirstChild("NPCs")
		if npcs then
			table.insert(ex, npcs)
		end
		local lp = game:GetService("Players").LocalPlayer
		if lp and lp.Character then
			table.insert(ex, lp.Character)
		end
		rayParams.FilterDescendantsInstances = ex
	end
	refreshFilter()
	local lastFilter = os.clock()

	local function camPos()
		local cam = opts.camera or workspace.CurrentCamera
		return cam and cam.CFrame.Position or Vector3.zero
	end

	local function takePart()
		local p = table.remove(self.pool)
		if not p then
			p = Instance.new("WedgePart")
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			p.Name = "Shard"
		end
		return p
	end

	local function release(s)
		local p = s.part
		p.Parent = nil
		if #self.pool < CFG.MAX_SHARDS then
			table.insert(self.pool, p)
		else
			p:Destroy()
		end
	end

	local function recycleOldest(n)
		for _ = 1, n do
			local s = table.remove(self.shards, 1)
			if not s then
				return
			end
			release(s)
		end
	end

	local function addShard(cf, size, col, mat, transp, refl, vel)
		if #self.shards >= CFG.MAX_SHARDS then
			recycleOldest(1)
		end
		local p = takePart()
		p.Size = size
		p.Color = col
		p.Material = mat
		p.Transparency = transp
		p.Reflectance = refl
		p.CFrame = cf
		p.Parent = folder
		local life = rng:NextNumber(CFG.SHARD_LIFE_MIN, CFG.SHARD_LIFE_MAX)
		table.insert(self.shards, {
			part = p, pos = cf.Position, rot = cf - cf.Position, vel = vel,
			spin = V3(rng:NextNumber(-9, 9), rng:NextNumber(-9, 9), rng:NextNumber(-9, 9)),
			t = 0, life = life, base = transp, resting = false,
		})
	end

	local function emitter(pos, props, count)
		if #self.dust >= CFG.MAX_DUST then
			local old = table.remove(self.dust, 1)
			if old.att then
				old.att:Destroy()
			end
		end
		local att = Instance.new("Attachment")
		att.WorldPosition = pos
		local pe = Instance.new("ParticleEmitter")
		for k, v in pairs(props) do
			pe[k] = v
		end
		pe.Enabled = false
		pe.Parent = att
		att.Parent = workspace.Terrain
		pe:Emit(count)
		table.insert(self.dust, { att = att, t = 0 })
	end

	local function grey(c, k)
		local h, s, v = c:ToHSV()
		return Color3.fromHSV(h, s * k, clamp(v * 0.45 + 0.12, 0, 1))
	end

	local function glass(e)
		local cf, size = e.cframe, e.size
		if typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" then
			return
		end
		-- the pane's two big axes span its face; the smallest is its thickness
		local ax = { { size.X, cf.RightVector }, { size.Y, cf.UpVector }, { size.Z, cf.LookVector } }
		table.sort(ax, function(a, b)
			return a[1] > b[1]
		end)
		local w, h = ax[1][1], ax[2][1]
		local u, v = ax[1][2], ax[2][2]
		local n = clamp(math.floor(w * h / 6), CFG.SHARDS_MIN, CFG.SHARDS_MAX)
		local dir = typeof(e.dir) == "Vector3" and e.dir or Vector3.zero
		local col = typeof(e.color) == "Color3" and e.color or Color3.fromRGB(120, 170, 200)
		local glassCol = col:Lerp(Color3.fromRGB(205, 238, 255), 0.6)
		local speed = clamp(dir.Magnitude, 10, 70)
		local d = dir.Magnitude > 0.01 and dir.Unit or Vector3.yAxis
		for _ = 1, n do
			local p = cf.Position + u * (rng:NextNumber(-0.5, 0.5) * w) + v * (rng:NextNumber(-0.5, 0.5) * h)
			local sz = V3(0.08, rng:NextNumber(0.4, 1.4), rng:NextNumber(0.4, 1.6)) * clamp((w * h) ^ 0.25 / 2.6, 0.5, 1.2)
			local rot = CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28))
			local vel = d * speed * rng:NextNumber(0.35, 0.9) + V3(rng:NextNumber(-7, 7), rng:NextNumber(2, 12), rng:NextNumber(-7, 7))
			local neon = e.screen and rng:NextNumber() < 0.45
			if neon then
				addShard(CF(p) * rot, sz, NEONS[rng:NextInteger(1, #NEONS)], Enum.Material.Neon, 0, 0, vel)
			else
				addShard(CF(p) * rot, sz, glassCol, Enum.Material.Glass, 0.45, 0.35, vel)
			end
		end
		if e.screen then
			emitter(cf.Position, {
				Texture = SPARK_TEX, Color = ColorSequence.new(Color3.fromRGB(200, 250, 255), Color3.fromRGB(255, 80, 220)),
				LightEmission = 1, Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
				Lifetime = NumberRange.new(0.3, 0.8), Speed = NumberRange.new(12, 30), SpreadAngle = Vector2.new(70, 70),
				Acceleration = V3(0, -40, 0), EmissionDirection = Enum.NormalId.Top,
			}, clamp(math.floor(w * h / 4), 10, 30))
		end
	end

	local function dust(e)
		local lp = game:GetService("Players").LocalPlayer
		if lp and lp:GetAttribute("Opt_smoke") == false then
			return -- (2026-11-11) SETTINGS > GRAPHICS > DESTRUCTION SMOKE off
		end
		local pos, size = e.pos, e.size
		if typeof(pos) ~= "Vector3" then
			return
		end
		local s = typeof(size) == "Vector3" and size.Magnitude or 6
		local col = typeof(e.color) == "Color3" and e.color or Color3.fromRGB(150, 150, 150)
		local c = grey(col, 0.15)
		emitter(pos, {
			Texture = DUST_TEX, Color = ColorSequence.new(c, Color3.fromRGB(70, 72, 80)), LightEmission = 0.05,
			LightInfluence = 1, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(0.6, 0.6), NumberSequenceKeypoint.new(1, 1) }),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, clamp(s * 0.25, 2, 6)), NumberSequenceKeypoint.new(1, clamp(s * 0.7, 5, 18)) }),
			Lifetime = NumberRange.new(1.4, 2.8), Speed = NumberRange.new(4, clamp(s, 8, 22)), SpreadAngle = Vector2.new(180, 180),
			Drag = 2.5, Acceleration = V3(0, 1.5, 0), RotSpeed = NumberRange.new(-40, 40), Rotation = NumberRange.new(0, 360),
		}, clamp(math.floor(s * 1.2), 10, 28))
	end

	function self:handle(batch)
		if type(batch) ~= "table" then
			return
		end
		if os.clock() - lastFilter > 2 then
			refreshFilter()
			lastFilter = os.clock()
		end
		local cp = camPos()
		for _, e in ipairs(batch) do
			if type(e) == "table" and typeof(e.pos) == "Vector3" and (e.pos - cp).Magnitude <= CFG.MAX_DIST then
				if e.kind == "glass" then
					glass(e)
				elseif e.kind == "dust" then
					dust(e)
				end
			end
		end
	end

	function self:step(dt)
		dt = math.min(dt, 1 / 20)
		local shards = self.shards
		if #shards > 0 then
			local parts, cfs = {}, {}
			for i = #shards, 1, -1 do
				local s = shards[i]
				s.t += dt
				if s.t >= s.life then
					table.remove(shards, i)
					release(s)
				else
					if not s.resting then
						s.vel -= V3(0, CFG.GRAVITY * dt, 0)
						local step = s.vel * dt
						local hit = workspace:Raycast(s.pos, step, rayParams)
						if hit then
							local nrm = hit.Normal
							local vn = nrm * s.vel:Dot(nrm)
							s.vel = (s.vel - vn) * 0.45 - vn * 0.25
							s.pos = hit.Position + nrm * 0.06
							s.spin *= 0.4
							if s.vel.Magnitude < 4 and nrm.Y > 0.6 then
								s.resting = true
								-- lie flat: the shard's thin X axis along the surface normal
								local t = s.rot.LookVector
								local vy = t - nrm * t:Dot(nrm)
								if vy.Magnitude < 0.1 then
									vy = Vector3.zAxis - nrm * nrm.Z
								end
								s.rot = CFrame.fromMatrix(Vector3.zero, nrm, vy.Unit)
								s.pos += nrm * 0.04
							end
						else
							s.pos += step
						end
						if not s.resting then
							s.rot = CFrame.Angles(s.spin.X * dt, s.spin.Y * dt, s.spin.Z * dt) * s.rot
						end
					end
					local left = s.life - s.t
					if left < CFG.SHARD_FADE then
						s.part.Transparency = s.base + (1 - s.base) * (1 - left / CFG.SHARD_FADE)
					end
					table.insert(parts, s.part)
					table.insert(cfs, CF(s.pos) * s.rot)
				end
			end
			if #parts > 0 then
				workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
			end
		end
		for i = #self.dust, 1, -1 do
			local d = self.dust[i]
			d.t += dt
			if d.t > CFG.DUST_LIFE then
				table.remove(self.dust, i)
				d.att:Destroy()
			end
		end
	end

	function self.count()
		return #self.shards, #self.dust, #self.pool
	end

	function self:destroy()
		for _, s in ipairs(self.shards) do
			s.part:Destroy()
		end
		for _, p in ipairs(self.pool) do
			p:Destroy()
		end
		for _, d in ipairs(self.dust) do
			d.att:Destroy()
		end
		self.shards, self.pool, self.dust = {}, {}, {}
		if not opts.folder then
			folder:Destroy()
		end
	end

	return self
end

return FX
