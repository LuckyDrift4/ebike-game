-- A small rigid-body world standing in for Roblox physics, so RideKit's real
-- Physics module can be tested outside Studio:
--   * the chassis is a box (mass from size x density, box inertia, gyroscopic terms)
--   * gravity is integrated in 4 substeps per frame like the 240 Hz engine
--   * ApplyImpulseAtPosition / ApplyAngularImpulse act instantly, as in Roblox
--   * terrain: a height field (any function) with materials, plus boxes (kerbs, walls)
--   * collisions: the chassis box corners and the wheel guards push out of the ground
--     with friction (what Roblox would do for the invisible collision parts)
--   * workspace:Raycast hits the height field and the boxes, with Normal and Material

local Sim = {}

_G.Enum = _G.Enum or { RaycastFilterType = { Exclude = 0 } }
_G.RaycastParams = { new = function() return {} end }

local world = { height = function(_, _) return 0 end, material = function(_, _) return "Asphalt" end, boxes = {} }
Sim.world = world

local function groundAt(x, z)
	return world.height(x, z)
end

local function normalAt(x, z)
	local e = 0.02
	local dx = (groundAt(x + e, z) - groundAt(x - e, z)) / (2 * e)
	local dz = (groundAt(x, z + e) - groundAt(x, z - e)) / (2 * e)
	return Vector3.new(-dx, 1, -dz).Unit
end

local function rayBox(o, d, b)
	local tmin, tmax = -math.huge, math.huge
	local nmin = nil
	for _, ax in ipairs({ "X", "Y", "Z" }) do
		local lo, hi = b.min[ax], b.max[ax]
		if math.abs(d[ax]) < 1e-12 then
			if o[ax] < lo or o[ax] > hi then
				return nil
			end
		else
			local t1, t2 = (lo - o[ax]) / d[ax], (hi - o[ax]) / d[ax]
			local n1 = Vector3.new(ax == "X" and -1 or 0, ax == "Y" and -1 or 0, ax == "Z" and -1 or 0)
			if t1 > t2 then
				t1, t2 = t2, t1
				n1 = -n1
			end
			if t1 > tmin then
				tmin, nmin = t1, n1
			end
			tmax = math.min(tmax, t2)
			if tmin > tmax then
				return nil
			end
		end
	end
	if tmin < 0 or tmin > 1 or not nmin then
		return nil -- starts inside (Roblox ignores the part it starts in) or out of reach
	end
	return tmin, nmin
end

Sim.rays = 0
Sim.frames = 0
_G.workspace = {
	Gravity = 196.2,
	Raycast = function(_, origin, dir, _params)
		Sim.rays += 1
		local best, bestN, bestMat = nil, nil, nil
		-- height field: march then bisect
		if origin.Y > groundAt(origin.X, origin.Z) then
			local n = 48
			local prev = 0
			for i = 1, n do
				local t = i / n
				local p = origin + dir * t
				if p.Y <= groundAt(p.X, p.Z) then
					local a, b = prev, t
					for _ = 1, 22 do
						local mid = (a + b) / 2
						local q = origin + dir * mid
						if q.Y <= groundAt(q.X, q.Z) then
							b = mid
						else
							a = mid
						end
					end
					best = b
					local q = origin + dir * b
					bestN = normalAt(q.X, q.Z)
					bestMat = world.material(q.X, q.Z)
					break
				end
				prev = t
			end
		end
		for _, b in ipairs(world.boxes) do
			local t, n = rayBox(origin, dir, b)
			if t and (not best or t < best) then
				best, bestN, bestMat = t, n, b.material or "Concrete"
			end
		end
		if not best then
			return nil
		end
		return { Position = origin + dir * best, Normal = bestN, Material = { Name = bestMat }, Distance = (dir * best).Magnitude }
	end,
}

-- penetration of a world point: depth and push-out normal
local function penetration(p)
	local best, bestN = 0, nil
	local gy = groundAt(p.X, p.Z)
	if p.Y < gy then
		local n = normalAt(p.X, p.Z)
		best, bestN = (gy - p.Y) * n.Y, n
	end
	for _, b in ipairs(world.boxes) do
		if p.X > b.min.X and p.X < b.max.X and p.Y > b.min.Y and p.Y < b.max.Y and p.Z > b.min.Z and p.Z < b.max.Z then
			local opts = {
				{ p.X - b.min.X, Vector3.new(-1, 0, 0) },
				{ b.max.X - p.X, Vector3.new(1, 0, 0) },
				{ p.Y - b.min.Y, Vector3.new(0, -1, 0) },
				{ b.max.Y - p.Y, Vector3.new(0, 1, 0) },
				{ p.Z - b.min.Z, Vector3.new(0, 0, -1) },
				{ b.max.Z - p.Z, Vector3.new(0, 0, 1) },
			}
			table.sort(opts, function(a, c) return a[1] < c[1] end)
			if opts[1][1] > best then
				best, bestN = opts[1][1], opts[1][2]
			end
		end
	end
	return best, bestN
end

local function orthonormal(cf)
	local x = cf.RightVector.Unit
	local y = cf.UpVector
	y = (y - x * y:Dot(x)).Unit
	local z = x:Cross(y)
	return CFrame.fromMatrix(cf.Position, x, y, z)
end

-- a bike laid out like RideKit's rig: geometry from the surron2 reference
function Sim.bike(cfg, opts)
	opts = opts or {}
	local radF, radR = opts.radF or 1.2657, opts.radR or 1.2209
	local wb = opts.wheelbase or 5.118
	local back = wb * cfg.ComBack
	local dy = radR * cfg.ComHeight
	local size = Vector3.new(1.2, 1.6, wb * 1.15) -- as Rig.build makes RideKit_Chassis
	local density = cfg.ChassisDensity
	local start = opts.at or Vector3.new(0, radR + dy, 0)
	local yaw = opts.yaw or 0
	local body = {
		Size = size,
		AssemblyMass = density * size.X * size.Y * size.Z,
		AssemblyLinearVelocity = opts.velocity or Vector3.zero,
		AssemblyAngularVelocity = Vector3.zero,
		Anchored = false,
	}
	body.CFrame = CFrame.new(start) * CFrame.Angles(opts.pitch or 0, yaw, opts.roll or 0)
	body.AssemblyCenterOfMass = body.CFrame.Position
	local m = body.AssemblyMass
	body.I = Vector3.new(
		m / 12 * (size.Y ^ 2 + size.Z ^ 2),
		m / 12 * (size.X ^ 2 + size.Z ^ 2),
		m / 12 * (size.X ^ 2 + size.Y ^ 2)
	)
	body.impulses = 0
	local function invI(b, vec)
		local l = b.CFrame:VectorToObjectSpace(vec)
		return b.CFrame:VectorToWorldSpace(Vector3.new(l.X / b.I.X, l.Y / b.I.Y, l.Z / b.I.Z))
	end
	body.invI = invI
	function body:ApplyImpulseAtPosition(J, at)
		self.AssemblyLinearVelocity += J / self.AssemblyMass
		self.AssemblyAngularVelocity += invI(self, (at - self.CFrame.Position):Cross(J))
	end
	function body:ApplyAngularImpulse(Lv)
		self.AssemblyAngularVelocity += invI(self, Lv)
	end
	function body:ApplyImpulse(J)
		self.AssemblyLinearVelocity += J / self.AssemblyMass
	end
	-- collision points: box corners + wheel guards (0.7 x radius rings at the axles)
	local axF = Vector3.new(0, -dy, -(wb / 2 + back))
	local axR = Vector3.new(0, -dy, wb / 2 - back)
	local pts = {}
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				table.insert(pts, Vector3.new(sx * size.X / 2, sy * size.Y / 2, sz * size.Z / 2))
			end
		end
	end
	for _, ax in ipairs({ axF, axR }) do
		local r = 0.7 * (if ax == axF then radF else radR)
		for k = 0, 7 do
			local a = k / 8 * 2 * math.pi
			for _, sx in ipairs({ -0.15, 0.15 }) do
				table.insert(pts, ax + Vector3.new(sx, math.cos(a) * r, math.sin(a) * r))
			end
		end
	end
	body.points = pts
	body.touching = false

	local model = {
		attrs = { RK_FrontAxle = axF, RK_RearAxle = axR, RK_RadiusF = radF, RK_RadiusR = radR },
	}
	function model:WaitForChild(name)
		assert(name == "RideKit_Chassis", name)
		return body
	end
	function model:GetAttribute(k)
		return self.attrs[k]
	end
	return model, body
end

-- advance the world by one frame (4 substeps)
function Sim.step(body, dt)
	local n = 4
	local h = dt / n
	local g = workspace.Gravity
	body.touching = false
	for _ = 1, n do
		body.AssemblyLinearVelocity += Vector3.new(0, -g * h, 0)
		-- contacts (friction 0.5, no bounce)
		for _, lp in ipairs(body.points) do
			local p = body.CFrame:PointToWorldSpace(lp)
			local depth, nrm = penetration(p)
			if depth > 0 then
				body.touching = true
				local r = p - body.CFrame.Position
				local v = body.AssemblyLinearVelocity + body.AssemblyAngularVelocity:Cross(r)
				local vn = v:Dot(nrm)
				local mInv = 1 / body.AssemblyMass + nrm:Dot(body.invI(body, r:Cross(nrm)):Cross(r))
				if vn < 0 then
					local jn = -vn / mInv
					local vt = v - nrm * vn
					local J = nrm * jn
					if vt.Magnitude > 1e-6 then
						local tdir = vt.Unit
						local mt = 1 / (1 / body.AssemblyMass + tdir:Dot(body.invI(body, r:Cross(tdir)):Cross(r)))
						J -= tdir * math.min(0.5 * jn, mt * vt.Magnitude)
					end
					body:ApplyImpulseAtPosition(J, p)
				end
				body.CFrame = body.CFrame + nrm * (depth * 0.5)
			end
		end
		-- integrate: position, then rotation with the gyroscopic term
		local cf = body.CFrame
		local wb = cf:VectorToObjectSpace(body.AssemblyAngularVelocity)
		local I = body.I
		local Lb = Vector3.new(I.X * wb.X, I.Y * wb.Y, I.Z * wb.Z)
		local gyro = wb:Cross(Lb)
		wb -= Vector3.new(gyro.X / I.X, gyro.Y / I.Y, gyro.Z / I.Z) * h
		local w = cf:VectorToWorldSpace(wb)
		body.AssemblyAngularVelocity = w
		local pos = cf.Position + body.AssemblyLinearVelocity * h
		local wm = w.Magnitude
		local rot = cf.Rotation
		if wm > 1e-9 then
			rot = CFrame.fromAxisAngle(w / wm, wm * h) * rot
		end
		body.CFrame = orthonormal(CFrame.new(pos) * rot)
	end
	body.AssemblyCenterOfMass = body.CFrame.Position
end

-- run `seconds` at `fps`; input(t, out) returns the rider input table; each(t, out) watches
function Sim.run(phys, body, fps, seconds, input, each)
	local dt = 1 / fps
	local frames = math.floor(seconds * fps + 0.5)
	local out = phys.out
	for f = 1, frames do
		Sim.frames += 1
		local t = f * dt
		out = phys:step(dt, input(t, out))
		Sim.step(body, dt)
		if each then
			each(t, out)
		end
	end
	return out
end

function Sim.reset()
	world.height = function(_, _) return 0 end
	world.material = function(_, _) return "Asphalt" end
	world.boxes = {}
end

return Sim
