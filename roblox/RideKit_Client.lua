-- RideKit (client). PASTE INTO A *LocalScript* IN StarterPlayer > StarterPlayerScripts.
-- Drives, animates and poses (R6) every bike that has the RideKit server Script.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")

local Config = (function()
	-- RideKit settings. Tweak these in Studio while play-testing.
	-- Distances are in studs, speeds in studs/second, angles in degrees unless noted.
	local Config = {
		-- names of the parts RideKit looks for inside the bike model
		WheelPartName = "Wheel", -- the two invisible cylinder wheels
		SteerHingeName = "TripleTreeHinge", -- steering head (fork pivots around this)
		SwingHingeName = "RearSwingArmHinge", -- swingarm pivot
		SeatPartKeyword = "seat", -- first part whose name contains this is used to place the seat
		FallbackRake = 26, -- steering-axis angle if there is no TripleTreeHinge

		-- engine / handling
		MaxSpeed = 70, -- ~70 km/h at Roblox scale
		ReverseSpeed = 10,
		Acceleration = 34,
		BrakeDecel = 70,
		CoastDecel = 5,
		SteerRate = 2.4, -- heading change (rad/s) at full lock
		FullTurnSpeed = 10, -- below this speed steering is weaker (a bike can't turn on the spot)
		MaxSteerAngle = 30, -- visual fork angle at walking pace (less at speed)
		MaxLean = 35, -- lean into corners at speed
		LeanFullSpeed = 30,
		LeanResponse = 6,
		SideGrip = 10, -- how quickly sideways sliding is killed (1/s)

		-- suspension (raycast)
		SuspensionTravel = 0.5,
		SpringRate = 1.0, -- 1.0 = sits at half travel when parked
		Damping = 0.45,
		AlignResponsiveness = 40,
		ChassisDensity = 0.7,

		-- wheelie (hold E on keyboard / X on gamepad / on-screen button on mobile)
		WheelieKeys = { Enum.KeyCode.E, Enum.KeyCode.ButtonX },
		WheelieAngle = 24,
		WheelieMinSpeed = 6,

		-- rider placement on the seat (R6)
		SeatHeight = 1.0, -- HumanoidRootPart height above the seat top
		SeatForward = 0.3, -- slide the rider forward on the seat

		-- rider pose (radians). "World" angles are measured from straight down,
		-- the code subtracts the torso lean so hands/feet stay on the bars/pegs.
		Pose = {
			TorsoLean = 0.34, -- leaning forward over the bars
			TorsoLeanThrottle = 0.10, -- extra tuck when accelerating
			TorsoLeanSpeed = 0.08, -- extra tuck at top speed
			BrakeLeanBack = 0.12,
			WheelieLeanBack = 0.35,
			TurnLean = 0.20, -- rider leans further into the corner than the bike
			TurnTwist = 0.12, -- shoulders follow the bars
			HeadUp = 0.30, -- keep looking ahead
			ArmWorld = 1.05, -- arms reaching forward-down to the grips
			ArmSteer = 0.22,
			LegWorld = 0.20, -- shins forward to the pegs
			LegSpread = 0.18, -- knees out around the bike
			Bounce = 0.04, -- body bob from the suspension
		},
	}

	return Config
end)()
local Physics = (function()
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
end)()
local Pose = (function()
	-- RideKit.Pose: procedural R6 riding pose. Every client poses every rider, so it
	-- needs no uploaded animation and looks the same for everyone.
	--
	-- R6 joint conventions (Transform is applied in each joint's own frame):
	--   RootJoint/Neck: +X rotation pitches forward, +Y rolls left, +Z twists left
	--   Shoulders/Hips:  +Z swings the right limb forward (left limb: -Z),
	--                    -X swings either limb outwards

	local Pose = {}

	local JOINTS = {
		Root = { "HumanoidRootPart", "RootJoint" },
		Neck = { "Torso", "Neck" },
		RS = { "Torso", "Right Shoulder" },
		LS = { "Torso", "Left Shoulder" },
		RH = { "Torso", "Right Hip" },
		LH = { "Torso", "Left Hip" },
	}

	-- returns the six R6 Motor6Ds, or nil for R15 / incomplete characters
	function Pose.joints(character: Model)
		local hum = character:FindFirstChildOfClass("Humanoid")
		if not hum or hum.RigType ~= Enum.HumanoidRigType.R6 then
			return nil
		end
		local out = {}
		for key, path in pairs(JOINTS) do
			local part = character:FindFirstChild(path[1])
			local m = part and part:FindFirstChild(path[2])
			if not (m and m:IsA("Motor6D")) then
				return nil
			end
			out[key] = m
		end
		return out
	end

	-- state: throttle, steer (-1..1), speed (studs/s, signed), maxSpeed, wheelie (rad), bounce (studs)
	function Pose.apply(j, p, state)
		local speedFrac = math.clamp(math.abs(state.speed) / state.maxSpeed, 0, 1)
		local lean = p.TorsoLean
			+ p.TorsoLeanThrottle * math.max(state.throttle, 0)
			+ p.TorsoLeanSpeed * speedFrac
			- p.BrakeLeanBack * math.max(-state.throttle, 0) * (if state.speed > 1 then 1 else 0)
			- p.WheelieLeanBack * math.clamp(state.wheelie / 0.4, 0, 1)
			+ p.Bounce * state.bounce
		local turnAmt = state.steer * math.clamp(math.abs(state.speed) / 15, 0.3, 1)
		local roll = -p.TurnLean * turnAmt
		local twist = -p.TurnTwist * state.steer

		j.Root.Transform = CFrame.Angles(lean, roll, twist)
		j.Neck.Transform = CFrame.Angles(-lean * 0.8 - p.HeadUp * speedFrac, 0, -twist * 0.6)

		local arm = p.ArmWorld - lean
		j.RS.Transform = CFrame.Angles(0, 0, arm - p.ArmSteer * state.steer)
		j.LS.Transform = CFrame.Angles(0, 0, -(arm + p.ArmSteer * state.steer))

		local leg = p.LegWorld + lean
		j.RH.Transform = CFrame.Angles(-p.LegSpread, 0, leg)
		j.LH.Transform = CFrame.Angles(-p.LegSpread, 0, -leg)
	end

	function Pose.clear(j)
		for _, m in pairs(j) do
			m.Transform = CFrame.new()
		end
	end

	-- stop the default sit / idle animations on this rider (local view only)
	function Pose.silence(character: Model)
		local hum = character:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				track:Stop(0)
			end
		end
	end

	return Pose
end)()

-- @body (everything below is shared with the single-file RideKit_Client.lua)
local function runBike(bike: Model)
	if not bike:GetAttribute("RideKitReady") then
		bike:GetAttributeChangedSignal("RideKitReady"):Wait()
	end

	local player = Players.LocalPlayer
	local chassis = bike:WaitForChild("RideKit_Chassis") :: BasePart
	local seat = bike:WaitForChild("RideKit_Seat") :: VehicleSeat
	local steerPivot = bike:WaitForChild("RideKit_SteerPivot") :: BasePart
	local swingPivot = bike:WaitForChild("RideKit_SwingPivot") :: BasePart
	local steerMotor = chassis:WaitForChild("RideKit_SteerMotor") :: Motor6D
	local swingMotor = chassis:WaitForChild("RideKit_SwingMotor") :: Motor6D
	local frontHubMotor = steerPivot:WaitForChild("RideKit_FrontHubMotor") :: Motor6D
	local rearHubMotor = swingPivot:WaitForChild("RideKit_RearHubMotor") :: Motor6D

	local physics = Physics.new(bike, Config)
	local radF = bike:GetAttribute("RK_RadiusF") :: number
	local radR = bike:GetAttribute("RK_RadiusR") :: number
	local armLen = bike:GetAttribute("RK_SwingArm") :: number
	local travel = Config.SuspensionTravel

	-- wheelie input (keyboard / gamepad / mobile button while riding)
	local wheelieHeld = false
	local ACTION = "RideKitWheelie_" .. bike.Name .. "_" .. tostring(math.random(1, 1e9))
	local function onWheelie(_, state)
		wheelieHeld = state == Enum.UserInputState.Begin
		return Enum.ContextActionResult.Sink
	end

	local wasDriver = false
	local spinF, spinR, steerVis = 0, 0, 0
	local riderJoints, riderChar = nil, nil
	local poseBounce = 0

	local conn
	conn = RunService.Stepped:Connect(function(_, dt)
		if not bike:IsDescendantOf(workspace) then
			conn:Disconnect()
			return
		end
		local occupant = seat.Occupant
		local char = occupant and occupant.Parent
		local isDriver = char ~= nil and char == player.Character

		-- input binding follows the driver role
		if isDriver ~= wasDriver then
			wasDriver = isDriver
			if isDriver then
				physics:resetHeading()
				ContextActionService:BindAction(ACTION, onWheelie, true, table.unpack(Config.WheelieKeys))
				ContextActionService:SetTitle(ACTION, "Wheelie")
			else
				ContextActionService:UnbindAction(ACTION)
				wheelieHeld = false
			end
		end

		physics:setIgnore(if char then { bike, char } else { bike })
		local throttle = if char then seat.ThrottleFloat else 0
		local steer = if char then seat.SteerFloat else 0

		if isDriver and not chassis.Anchored then
			physics:step(dt, throttle, steer, wheelieHeld, true)
		end

		-- visuals for everyone: spin, steer, suspension
		local vF = chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector)
		spinF = (spinF + vF / radF * dt) % (2 * math.pi)
		spinR = (spinR + vF / radR * dt) % (2 * math.pi)
		local speedFrac = math.clamp(math.abs(vF) / Config.MaxSpeed, 0, 1)
		local steerTarget = steer * math.rad(Config.MaxSteerAngle) * (1 - 0.65 * speedFrac)
		steerVis += (steerTarget - steerVis) * (1 - math.exp(-12 * dt))
		local compF, hitF = physics:probe(1)
		local compR, hitR = physics:probe(2)
		local offF = math.clamp(compF - travel * 0.5, -travel * 0.5, travel * 0.8)
		local offR = math.clamp(compR - travel * 0.5, -travel * 0.5, travel * 0.8)
		steerMotor.Transform = CFrame.Angles(0, -steerVis, 0)
		frontHubMotor.Transform = CFrame.new(0, offF, 0) * CFrame.Angles(-spinF, 0, 0)
		swingMotor.Transform = CFrame.Angles(-math.asin(math.clamp(offR / armLen, -0.5, 0.5)), 0, 0)
		rearHubMotor.Transform = CFrame.Angles(-spinR, 0, 0)

		-- rider pose
		if char ~= riderChar then
			if riderJoints then
				Pose.clear(riderJoints)
			end
			riderChar = char
			riderJoints = if char then Pose.joints(char) else nil
		end
		if riderJoints and char then
			Pose.silence(char)
			poseBounce += ((offF + offR) * 0.5 - poseBounce) * (1 - math.exp(-8 * dt))
			-- wheelie = nose higher than the ground slope under the wheels
			local pitch = math.asin(math.clamp(chassis.CFrame.LookVector.Y, -1, 1))
			local slope = 0
			if hitF and hitR then
				local d = hitF.Position - hitR.Position
				slope = math.asin(math.clamp(d.Y / math.max(d.Magnitude, 0.01), -1, 1))
			end
			local wheelieAngle = if hitR and compF <= 0 then math.max(pitch - slope, 0.2) else math.max(pitch - slope, 0)
			Pose.apply(riderJoints, Config.Pose, {
				throttle = throttle,
				steer = steer,
				speed = vF,
				maxSpeed = Config.MaxSpeed,
				wheelie = if wheelieAngle > 0.12 then wheelieAngle else 0,
				bounce = -poseBounce,
			})
		end
	end)
end

for _, b in ipairs(CollectionService:GetTagged("RideKitBike")) do
	task.spawn(runBike, b)
end
CollectionService:GetInstanceAddedSignal("RideKitBike"):Connect(function(b)
	task.spawn(runBike, b)
end)
