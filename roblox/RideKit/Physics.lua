-- RideKit.Physics: raycast-suspension bike. Runs on whoever owns the bike's
-- physics: the rider's client while riding, the server while it coasts to a stop.

local Physics = {}
Physics.__index = Physics

function Physics.new(bike: Model, cfg)
	local self = setmetatable({}, Physics)
	self.bike = bike
	self.cfg = cfg
	self.chassis = bike:WaitForChild("RideKit_Chassis") :: BasePart
	self.align = self.chassis:WaitForChild("RideKit_Align") :: AlignOrientation
	self.wheels = {
		{ localPos = bike:GetAttribute("RK_FrontAxle"), radius = bike:GetAttribute("RK_RadiusF") },
		{ localPos = bike:GetAttribute("RK_RearAxle"), radius = bike:GetAttribute("RK_RadiusR") },
	}
	self.comp = { cfg.SuspensionTravel * 0.5, cfg.SuspensionTravel * 0.5 }
	self.params = RaycastParams.new()
	self.params.FilterType = Enum.RaycastFilterType.Exclude
	self.params.FilterDescendantsInstances = { bike }
	self.params.IgnoreWater = false
	self:resetHeading()
	return self
end

-- re-read heading from the chassis (call when taking over the physics)
function Physics:resetHeading()
	local look = self.chassis.CFrame.LookVector
	self.yaw = math.atan2(-look.X, -look.Z)
	self.pitch = 0
	self.roll = 0
	self.wheelie = 0
end

function Physics:setIgnore(list: { Instance })
	self.params.FilterDescendantsInstances = list
end

-- suspension compression for wheel i (0 = fully extended) and the ground hit
function Physics:probe(i: number): (number, RaycastResult?)
	local cfg = self.cfg
	local w = self.wheels[i]
	local cf = self.chassis.CFrame
	local upv = cf.UpVector
	local travel = cfg.SuspensionTravel
	local mount = cf:PointToWorldSpace(w.localPos) + upv * (travel * 0.5)
	local hit = workspace:Raycast(mount, -upv * (travel + w.radius + 0.6), self.params)
	if hit then
		local dist = (hit.Position - mount).Magnitude
		return math.clamp(travel + w.radius - dist, 0, travel * 1.6), hit
	end
	return 0, nil
end

-- one physics step. throttle/steer are -1..1; returns forward speed
function Physics:step(dt: number, throttle: number, steer: number, wheelieHeld: boolean, hasDriver: boolean): number
	local cfg = self.cfg
	local ch = self.chassis
	dt = math.clamp(dt, 1 / 240, 1 / 20)
	local mass = ch.AssemblyMass
	local g = workspace.Gravity
	local upv = ch.CFrame.UpVector
	local travel = cfg.SuspensionTravel
	local k = cfg.SpringRate * g / travel
	local c = cfg.Damping * math.sqrt(2 * k)

	-- suspension: each wheel pushes the chassis up along its own up axis
	local hits = {}
	local grounded = false
	local push = 0
	for i = 1, 2 do
		local comp, hit = self:probe(i)
		local vel = (comp - self.comp[i]) / dt
		self.comp[i] = comp
		if hit and comp > 0 then
			hits[i] = hit
			grounded = true
			push += math.max(k * comp + c * vel, 0)
		end
	end
	if push > 0 then
		ch:ApplyImpulse(upv * math.min(push, g * 6) * mass * dt)
	end

	-- drive, brake and tyre grip in the heading frame
	local fwd = Vector3.new(-math.sin(self.yaw), 0, -math.cos(self.yaw))
	local right = Vector3.new(math.cos(self.yaw), 0, -math.sin(self.yaw))
	local v = ch.AssemblyLinearVelocity
	local vF = v:Dot(fwd)
	local vS = v:Dot(right)
	if grounded then
		local target, rate
		if throttle > 0.05 then
			target = throttle * cfg.MaxSpeed
			rate = if vF < -0.5 then cfg.BrakeDecel else cfg.Acceleration
		elseif throttle < -0.05 then
			if vF > 0.5 then
				target, rate = 0, cfg.BrakeDecel
			else
				target, rate = throttle * cfg.ReverseSpeed, cfg.Acceleration * 0.5
			end
		else
			target = 0
			rate = if hasDriver then cfg.CoastDecel else cfg.BrakeDecel
		end
		local dv = math.clamp(target - vF, -rate * dt, rate * dt)
		local side = -vS * (1 - math.exp(-cfg.SideGrip * dt))
		ch:ApplyImpulse((fwd * dv + right * side) * mass)

		-- steering turns the heading; weak at walking pace, gentler at top speed
		local speed = math.abs(vF)
		local turn = math.clamp(speed / cfg.FullTurnSpeed, 0, 1) * (1 - 0.45 * math.clamp(speed / cfg.MaxSpeed, 0, 1))
		local dir = if vF >= 0 then 1 else -1
		self.yaw -= steer * cfg.SteerRate * turn * dir * dt
	end

	-- lean into corners (positive roll = lean left)
	local leanAmt = math.clamp(math.abs(vF) / cfg.LeanFullSpeed, 0, 1)
	local targetRoll = if grounded then -steer * math.rad(cfg.MaxLean) * leanAmt else self.roll
	self.roll += (targetRoll - self.roll) * (1 - math.exp(-cfg.LeanResponse * dt))

	-- pitch follows the ground under both wheels, plus the wheelie
	local targetPitch = self.pitch
	if hits[1] and hits[2] then
		local d = hits[1].Position - hits[2].Position
		if d.Magnitude > 0.1 then
			targetPitch = math.asin(math.clamp(d.Y / d.Magnitude, -1, 1))
		end
	elseif not grounded then
		targetPitch = self.pitch * (1 - dt * 0.4)
	end
	self.pitch += (targetPitch - self.pitch) * (1 - math.exp(-10 * dt))
	local wantWheelie = wheelieHeld and hits[2] ~= nil and vF > cfg.WheelieMinSpeed and throttle > 0.3
	local wTarget = if wantWheelie then math.rad(cfg.WheelieAngle) else 0
	self.wheelie += (wTarget - self.wheelie) * (1 - math.exp(-(if wantWheelie then 2.5 else 4) * dt))

	self.align.CFrame = CFrame.fromEulerAnglesYXZ(self.pitch + self.wheelie, self.yaw, self.roll)
	return vF
end

return Physics
