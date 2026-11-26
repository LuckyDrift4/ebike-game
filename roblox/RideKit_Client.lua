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
		SeatHeight = "auto", -- "auto" = as low as needed for the feet to reach the pegs, or a number
		-- (HumanoidRootPart height above the seat top, e.g. 1.0)
		SeatForward = 0.55, -- slide the rider forward on the seat (towards the bars)
		GripInset = 0.25, -- hands sit this far in from the ends of the handlebar
		PegInset = 0.15, -- feet sit this far in from the ends of the foot-peg bar

		-- rider pose (radians). Hands are aimed at the grips and feet at the pegs
		-- automatically; these only shape the body around them.
		Pose = {
			TorsoLean = 0.30, -- leaning forward over the bars
			TorsoLeanThrottle = 0.10, -- extra tuck when accelerating
			TorsoLeanSpeed = 0.08, -- extra tuck at top speed
			BrakeLeanBack = 0.12,
			WheelieLeanBack = 0.30,
			MaxExtraLean = 0.45, -- lean up to this much further when the grips are out of reach
			TurnLean = 0.18, -- rider leans further into the corner than the bike
			TurnTwist = 0.15, -- shoulders follow the bars (fine-tuned automatically so both hands reach)
			HeadTurn = 0.30, -- look into the corner
			HeadDown = 0.10, -- slight chin-down when slow
			HeadUp = 0.10, -- look further ahead at speed
			Bounce = 0.04, -- body bob from the suspension
		},}

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
	-- Instead of guessing joint angles, each limb is AIMED at a real point on the
	-- bike: hands at the handlebar grips (which follow the steering), feet at the
	-- foot pegs, head looking down the road. Joint transforms are then solved from
	--   Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse()
	-- using the joints' own C0/C1, so the result is right for any standard R6 rig.
	--
	-- The R6 "Animate" script poses seated characters by spinning the shoulder and
	-- hip Motors (DesiredAngle / CurrentAngle), which would add on top of this, so
	-- those angles are zeroed every frame (and the local rider's Animate script is
	-- paused by the client while riding).

	local Pose = {}

	local JOINTS = {
		Root = { "HumanoidRootPart", "RootJoint" },
		Neck = { "Torso", "Neck" },
		RS = { "Torso", "Right Shoulder" },
		LS = { "Torso", "Left Shoulder" },
		RH = { "Torso", "Right Hip" },
		LH = { "Torso", "Left Hip" },
	}
	local KEYS = { "Root", "Neck", "RS", "LS", "RH", "LH" }

	-- returns the R6 joints + limb sizes, or nil for R15 / incomplete characters
	function Pose.joints(character: Model)
		local hum = character:FindFirstChildOfClass("Humanoid")
		if not hum or hum.RigType ~= Enum.HumanoidRigType.R6 then
			return nil
		end
		local j = {}
		for key, path in pairs(JOINTS) do
			local part = character:FindFirstChild(path[1])
			local m = part and part:FindFirstChild(path[2])
			if not (m and m:IsA("Motor6D")) then
				return nil
			end
			j[key] = m
		end
		j.hrp = character:FindFirstChild("HumanoidRootPart")
		local arm = character:FindFirstChild("Right Arm")
		local leg = character:FindFirstChild("Right Leg")
		j.armLen = if arm and arm:IsA("BasePart") then arm.Size.Y else 2
		j.legLen = if leg and leg:IsA("BasePart") then leg.Size.Y else 2
		return j
	end

	-- limb-space vector from the joint (C1 position) to the hand / foot
	local function tipOf(m, len: number): Vector3
		return Vector3.new(0, -len / 2, 0) - m.C1.Position
	end

	-- rotation that points a limb from world point `joint` at `target`, keeping the
	-- limb's X axis close to `rightHint` (no corkscrew twist)
	local function aimLimb(joint: Vector3, target: Vector3, tip: Vector3, rightHint: Vector3): CFrame
		local d = target - joint
		local R = CFrame.new()
		for _ = 1, 3 do
			if d.Magnitude < 1e-4 then
				break
			end
			local y = -d.Unit -- limb +Y runs from the hand back up to the joint
			local x = rightHint - y * rightHint:Dot(y)
			if x.Magnitude < 1e-3 then
				x = y:Cross(Vector3.zAxis)
			end
			R = CFrame.fromMatrix(Vector3.zero, x.Unit, y)
			-- the hand sits off the limb axis (tip.X / tip.Z): aim the axis so the hand lands on target
			local side = R:VectorToWorldSpace(Vector3.new(tip.X, 0, tip.Z))
			d = target - side - joint
		end
		return R
	end

	-- Transform that gives Part1 the world rotation `childRot` under Part0 at `parentCF`
	local function solve(m, parentCF: CFrame, childRot: CFrame): CFrame
		return m.C0.Rotation:Inverse() * parentCF.Rotation:Inverse() * childRot * m.C1.Rotation
	end

	--[[
	  j       : from Pose.joints (motors + hrp + limb sizes)
	  hrpCF   : HumanoidRootPart CFrame (welded to the seat)
	  bikeCF  : bike chassis CFrame (head looks along it)
	  targets : { gripL, gripR, pegL, pegR } world positions
	  p       : Config.Pose
	  s       : { throttle, steer, speed, maxSpeed, wheelie, bounce }
	  returns : torso CFrame, hand and foot positions (for debugging/tests)
	]]
	function Pose.solve(j, hrpCF: CFrame, bikeCF: CFrame, targets, p, s)
		for _, key in ipairs(KEYS) do
			local m = j[key]
			m.MaxVelocity = 0
			m.DesiredAngle = 0
			m.CurrentAngle = 0
		end

		local speedFrac = math.clamp(math.abs(s.speed) / s.maxSpeed, 0, 1)
		local turn = s.steer * math.clamp(math.abs(s.speed) / 15, 0.3, 1)
		local lean = p.TorsoLean
			+ p.TorsoLeanThrottle * math.max(s.throttle, 0)
			+ p.TorsoLeanSpeed * speedFrac
			- p.BrakeLeanBack * math.max(-s.throttle, 0) * (if s.speed > 1 then 1 else 0)
			- p.WheelieLeanBack * math.clamp(s.wheelie / 0.4, 0, 1)
			+ p.Bounce * s.bounce

		-- torso (rotates about its centre, the HRP). R6 arms can't bend, so search a
		-- small range of extra lean and shoulder twist for the stance where both hands
		-- land on the grips (and the feet still reach the pegs).
		local armTip = tipOf(j.RS, j.armLen)
		local legTip = tipOf(j.RH, j.legLen)
		local armReach, legReach = armTip.Magnitude, legTip.Magnitude
		local root = j.Root
		local roll = CFrame.fromAxisAngle(Vector3.zAxis, -p.TurnLean * turn)
		local baseTwist = -p.TurnTwist * s.steer
		local best, bestT, bestTorso = math.huge, nil, nil
		for extra = -0.15, p.MaxExtraLean + 1e-6, 0.05 do
			for tw = -0.6, 0.6 + 1e-6, 0.05 do
				local local_ = CFrame.fromAxisAngle(Vector3.yAxis, baseTwist + tw) * roll
					* CFrame.fromAxisAngle(Vector3.xAxis, -(lean + extra))
				local T = solve(root, hrpCF, hrpCF.Rotation * local_)
				local torso = hrpCF * root.C0 * T * root.C1:Inverse()
				local dR = (targets.gripR - torso * j.RS.C0.Position).Magnitude - armReach
				local dL = (targets.gripL - torso * j.LS.C0.Position).Magnitude - armReach
				local fR = math.max((targets.pegR - torso * j.RH.C0.Position).Magnitude - legReach, 0)
				local fL = math.max((targets.pegL - torso * j.LH.C0.Position).Magnitude - legReach, 0)
				local cost = dR * dR + dL * dL + 0.5 * (fR * fR + fL * fL) + 0.02 * extra * extra + 0.01 * tw * tw
				if cost < best then
					best, bestT, bestTorso = cost, T, torso
				end
			end
		end
		root.Transform = bestT
		local torsoCF = bestTorso

		-- head: eyes level with the horizon (follows the bike's lean, not its pitch),
		-- looking into the corner a little
		local look = bikeCF.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		flatLook = if flatLook.Magnitude > 1e-3 then flatLook.Unit else hrpCF.LookVector
		local headUp = (Vector3.yAxis + bikeCF.UpVector).Unit
		local headRight = flatLook:Cross(headUp).Unit
		local headRot = CFrame.fromMatrix(Vector3.zero, headRight, headRight:Cross(flatLook))
			* CFrame.fromAxisAngle(Vector3.yAxis, -p.HeadTurn * s.steer)
			* CFrame.fromAxisAngle(Vector3.xAxis, -p.HeadDown + p.HeadUp * speedFrac)
		j.Neck.Transform = solve(j.Neck, torsoCF, headRot)

		-- arms to the grips, legs to the pegs
		local right = torsoCF.RightVector
		local out = { torso = torsoCF }
		local limbs = {
			{ j.RS, targets.gripR, j.armLen, "handR" },
			{ j.LS, targets.gripL, j.armLen, "handL" },
			{ j.RH, targets.pegR, j.legLen, "footR" },
			{ j.LH, targets.pegL, j.legLen, "footL" },
		}
		for _, l in ipairs(limbs) do
			local m, target, len, name = l[1], l[2], l[3], l[4]
			local jointW = torsoCF * m.C0.Position
			local tip = tipOf(m, len)
			local R = aimLimb(jointW, target, tip, right)
			m.Transform = solve(m, torsoCF, R)
			out[name] = jointW + R:VectorToWorldSpace(tip)
		end
		return out
	end

	-- local rider only: stop the default animations and pause the Animate script
	function Pose.takeOver(character: Model)
		local animate = character:FindFirstChild("Animate")
		if animate and (animate:IsA("LocalScript") or animate:IsA("Script")) then
			animate.Disabled = true
		end
		Pose.silence(character)
	end

	function Pose.release(character: Model)
		local animate = character:FindFirstChild("Animate")
		if animate and (animate:IsA("LocalScript") or animate:IsA("Script")) then
			animate.Disabled = false
		end
	end

	function Pose.clear(j)
		for _, key in ipairs(KEYS) do
			j[key].Transform = CFrame.new()
		end
	end

	-- stop the default sit / idle animation tracks on a rider (local view only)
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
	local gripL = bike:GetAttribute("RK_GripL") :: Vector3
	local gripR = bike:GetAttribute("RK_GripR") :: Vector3
	local pegL = bike:GetAttribute("RK_PegL") :: Vector3
	local pegR = bike:GetAttribute("RK_PegR") :: Vector3

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
	local tookOver = false
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
			if tookOver and riderChar then
				Pose.release(riderChar)
			end
			riderChar = char
			riderJoints = if char then Pose.joints(char) else nil
			tookOver = riderJoints ~= nil and char == player.Character -- R6 only; R15 keeps its sit animation
			if tookOver then
				Pose.takeOver(char)
			end
		end
		if riderJoints and char and riderJoints.hrp then
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
			local steerCF = steerPivot.CFrame
			local chassisCF = chassis.CFrame
			Pose.solve(riderJoints, riderJoints.hrp.CFrame, chassisCF, {
				gripL = steerCF * gripL,
				gripR = steerCF * gripR,
				pegL = chassisCF * pegL,
				pegR = chassisCF * pegR,
			}, Config.Pose, {
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
