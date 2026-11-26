----------------------------------------------------------------------------------------------------------------------------------------------------------------

local Config = (function()
	-- RideKit settings. Tweak these in Studio while play-testing.
	-- Distances are in studs, speeds in studs/second, angles in degrees unless noted.
	local Config = {
		-- names of the parts RideKit looks for inside the bike model
		WheelPartName = "Wheel", -- the two invisible cylinder wheels
		SteerHingeName = "TripleTreeHinge", -- steering head (fork pivots around this)
		SwingHingeName = "RearSwingArmHinge", -- swingarm pivot
		SeatPartKeyword = "seat", -- part whose name contains this is the seat (else the highest seat-shaped part)
		FallbackRake = 26, -- steering-axis angle if there is no TripleTreeHinge

		-- engine / handling
		MaxSpeed = 70, -- ~70 km/h at Roblox scale
		ReverseSpeed = 10,
		Acceleration = 34,
		BrakeDecel = 70,
		CoastDecel = 5,
		SteerRate = 2.4, -- heading change (rad/s) at full lock
		FullTurnSpeed = 10, -- below this speed steering is weaker (a bike can't turn on the spot)
		MaxSteerAngle = 17, -- visual bar angle at walking pace (less at speed; the lean clips are posed at 14)
		MaxLean = 35, -- lean into corners at speed
		LeanFullSpeed = 30,
		LeanResponse = 6,
		SideGrip = 10, -- how quickly sideways sliding is killed (1/s)

		-- suspension (raycast)
		SuspensionTravel = 0.5,
		SpringRate = 1.0, -- 1.0 = sits at half travel; higher = stiffer
		Damping = 0.75, -- 1.0 = no rebound at all; lower = springier (stays stable)
		WeightTransfer = 0.0012, -- nose dive under braking / squat under throttle (rad per stud/s²)
		AlignResponsiveness = 40,
		ChassisDensity = 0.7,

		-- wheelie (hold E on keyboard / X on gamepad / on-screen button on mobile)
		WheelieKeys = { Enum.KeyCode.E, Enum.KeyCode.ButtonX },
		WheelieAngle = 24,
		WheelieMinSpeed = 6,

		-- rider placement on the seat (R6)
		SeatHeight = "auto", -- "auto" = as low as needed for the feet to reach the pegs, or a number
		-- (HumanoidRootPart height above the seat top, e.g. 1.0)
		SeatForward = "auto", -- "auto" = slide forward until the hands reach the bars, or a number
		GripInset = 0.25, -- hands sit this far in from the ends of the handlebar
		PegInset = 0.15, -- feet sit this far in from the ends of the foot-peg bar

		-- rider animation (keyframed in Blender: blender/anim/ride_anims.blend)
		AnimBlendSpeed = 7, -- how fast the rider moves between ride / tuck / brake / lean / wheelie
		Pose = { TorsoLean = 0.35 }, -- forward lean the seat position is fitted for (matches the Blender clips)
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
		self.accel = 0
		self.lastVF = nil
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
		local k = cfg.SpringRate * g / travel -- per wheel; two wheels hold the bike at half travel
		local cd = cfg.Damping * math.sqrt(2 * k)

		-- suspension: implicit (backward-Euler) spring + damper along the bike's up axis.
		-- A plain per-frame spring force lags the 240 Hz physics by a frame, which eats
		-- the damping and makes the bike bounce; solving it implicitly is stable at any
		-- frame rate and settles at ride height.
		local hits = {}
		local grounded = false
		local n, C, rateSum, rateN = 0, 0, 0, 0
		for i = 1, 2 do
			local comp, hit = self:probe(i)
			if hit and comp > 0 then
				hits[i] = hit
				grounded = true
				n += 1
				C += comp + 3 * math.max(comp - travel, 0) -- stiff bump stop past full travel
				if self.comp[i] > 0 then
					rateSum += (comp - self.comp[i]) / dt
					rateN += 1
				end
				self.comp[i] = comp
			else
				self.comp[i] = 0
			end
		end
		if n > 0 then
			local gUp = g * math.max(upv.Y, 0.2)
			-- chassis speed along up, measured from how fast the springs extend
			local vUp = if rateN > 0 then -rateSum / rateN else ch.AssemblyLinearVelocity:Dot(upv)
			local vNew = (vUp + dt * (k * C - gUp)) / (1 + n * k * dt * dt + n * cd * dt)
			local dv = math.clamp(vNew - vUp + gUp * dt, -g * dt * 2, g * dt * 8)
			ch:ApplyImpulse(upv * dv * mass)
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
		-- weight transfer: nose dives under braking, squats under acceleration
		if self.lastVF then
			local a = (vF - self.lastVF) / dt
			self.accel += (a - self.accel) * (1 - math.exp(-8 * dt))
		end
		self.lastVF = vF
		local transfer = if grounded then math.clamp(self.accel * cfg.WeightTransfer, -0.07, 0.05) else 0
		local wantWheelie = wheelieHeld and hits[2] ~= nil and vF > cfg.WheelieMinSpeed and throttle > 0.3
		local wTarget = if wantWheelie then math.rad(cfg.WheelieAngle) else 0
		self.wheelie += (wTarget - self.wheelie) * (1 - math.exp(-(if wantWheelie then 2.5 else 4) * dt))

		self.align.CFrame = CFrame.fromEulerAnglesYXZ(self.pitch + self.wheelie + transfer, self.yaw, self.roll)
		return vF
	end

	return Physics
end)()
local AnimPlayer = (function()
	-- RideKit.AnimPlayer: plays the R6 riding animations made in Blender
	-- (blender/anim/ride_anims.blend -> roblox/anim/ride_anims.json -> AnimData).
	-- No pose is computed here: it samples the Blender keyframes, blends the clips
	-- (ride + tuck / brake / lean left / lean right / wheelie) by riding state, and
	-- writes the result to the rider's Motor6D.Transform on every client.

	local AnimPlayer = {}

	-- Blender bone (= R6 part) -> R6 joint that moves it
	local JOINT_OF = {
		Torso = { "HumanoidRootPart", "RootJoint" },
		Head = { "Torso", "Neck" },
		["Right Arm"] = { "Torso", "Right Shoulder" },
		["Left Arm"] = { "Torso", "Left Shoulder" },
		["Right Leg"] = { "Torso", "Right Hip" },
		["Left Leg"] = { "Torso", "Left Hip" },
	}
	local PARTS = { "Torso", "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg" }

	-- AnimData quaternions -> CFrames, once
	function AnimPlayer.prepare(data)
		local clips = {}
		for name, c in pairs(data.clips) do
			local frames = {}
			for _, k in ipairs(c.keys) do
				local pose = {}
				for _, part in ipairs(PARTS) do
					local q = k.pose[part]
					pose[part] = CFrame.new(0, 0, 0, q[1], q[2], q[3], q[4])
				end
				table.insert(frames, { t = k.t, pose = pose })
			end
			clips[name] = { length = c.length, loop = c.loop, frames = frames, steer = c.steer }
		end
		return clips
	end

	-- pose of a clip at time t (seconds), interpolating between keys
	function AnimPlayer.sample(clip, t: number)
		local frames = clip.frames
		if #frames == 1 or clip.length <= 0 then
			return frames[1].pose
		end
		t = if clip.loop then t % clip.length else math.clamp(t, 0, clip.length)
		for i = 1, #frames - 1 do
			local a, b = frames[i], frames[i + 1]
			if t <= b.t then
				local u = if b.t > a.t then (t - a.t) / (b.t - a.t) else 0
				u = u * u * (3 - 2 * u) -- ease between keys
				local out = {}
				for _, part in ipairs(PARTS) do
					out[part] = a.pose[part]:Lerp(b.pose[part], u)
				end
				return out
			end
		end
		return frames[#frames].pose
	end

	-- blend pose `over` on top of `base` with weight w (0..1)
	function AnimPlayer.blend(base, over, w: number)
		if w <= 1e-3 then
			return base
		end
		local out = {}
		for _, part in ipairs(PARTS) do
			out[part] = base[part]:Lerp(over[part], math.min(w, 1))
		end
		return out
	end

	--[[ Full riding pose.
	  clips  : from prepare
	  t      : time in seconds (for the looping ride clip)
	  w      : smoothed weights { tuck, brake, leanR, leanL, wheelie } (0..1) ]]
	function AnimPlayer.pose(clips, t: number, w)
		local pose = AnimPlayer.sample(clips.Ride, t)
		pose = AnimPlayer.blend(pose, AnimPlayer.sample(clips.Tuck, t), w.tuck)
		pose = AnimPlayer.blend(pose, AnimPlayer.sample(clips.Brake, t), w.brake)
		pose = AnimPlayer.blend(pose, AnimPlayer.sample(clips.LeanRight, t), w.leanR)
		pose = AnimPlayer.blend(pose, AnimPlayer.sample(clips.LeanLeft, t), w.leanL)
		pose = AnimPlayer.blend(pose, AnimPlayer.sample(clips.Wheelie, t), w.wheelie)
		return pose
	end

	-- R6 joints of a character (nil for R15)
	function AnimPlayer.joints(character: Model)
		local hum = character:FindFirstChildOfClass("Humanoid")
		if not hum or hum.RigType ~= Enum.HumanoidRigType.R6 then
			return nil
		end
		local j = {}
		for part, path in pairs(JOINT_OF) do
			local p0 = character:FindFirstChild(path[1])
			local m = p0 and p0:FindFirstChild(path[2])
			if not (m and m:IsA("Motor6D")) then
				return nil
			end
			j[part] = m
		end
		return j
	end

	-- write a pose to the joints. The R6 Animate script poses seated characters by
	-- spinning the shoulder/hip Motors (DesiredAngle/CurrentAngle), which would add
	-- on top, so those are zeroed too.
	function AnimPlayer.apply(j, pose)
		for _, part in ipairs(PARTS) do
			local m = j[part]
			m.MaxVelocity = 0
			m.DesiredAngle = 0
			m.CurrentAngle = 0
			m.Transform = pose[part]
		end
	end

	function AnimPlayer.clear(j)
		for _, part in ipairs(PARTS) do
			j[part].Transform = CFrame.new()
		end
	end

	-- local rider only: pause the default Animate script while riding
	function AnimPlayer.takeOver(character: Model)
		local animate = character:FindFirstChild("Animate")
		if animate and (animate:IsA("LocalScript") or animate:IsA("Script")) then
			animate.Disabled = true
		end
		AnimPlayer.silence(character)
	end

	function AnimPlayer.release(character: Model)
		local animate = character:FindFirstChild("Animate")
		if animate and (animate:IsA("LocalScript") or animate:IsA("Script")) then
			animate.Disabled = false
		end
	end

	-- stop default sit / idle animation tracks on a rider (local view only)
	function AnimPlayer.silence(character: Model)
		local hum = character:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				track:Stop(0)
			end
		end
	end

	return AnimPlayer
end)()
local AnimData = (function()
	-- R6 riding clips keyframed in Blender (blender/anim/ride_anims.blend).
	-- Generated by roblox/build_ridekit.py from roblox/anim/ride_anims.json; do not edit.
	-- Each key: time (s) and every R6 joint's Motor6D.Transform rotation as a quaternion {x, y, z, w}.
	return {
		bike = "surron2",
		clips = {
			Ride = { length = 2.0, loop = true, steer = 0.0, keys = {
				{ t = 0.0, pose = { ["Torso"] = { 0.13954, 0.00000, 0.00000, 0.99022 }, ["Head"] = { -0.12428, -0.00000, 0.00000, 0.99225 }, ["Right Arm"] = { 0.07363, -0.00000, 0.57084, 0.81776 }, ["Left Arm"] = { 0.09559, 0.00000, -0.57172, 0.81486 }, ["Right Leg"] = { -0.12399, -0.00000, 0.07083, 0.98975 }, ["Left Leg"] = { -0.10638, -0.00000, -0.07874, 0.99120 } } },
				{ t = 0.1, pose = { ["Torso"] = { 0.13954, 0.00000, 0.00000, 0.99022 }, ["Head"] = { -0.12384, 0.00000, -0.00357, 0.99230 }, ["Right Arm"] = { 0.07363, -0.00000, 0.57084, 0.81776 }, ["Left Arm"] = { 0.09559, 0.00000, -0.57172, 0.81486 }, ["Right Leg"] = { -0.12399, -0.00000, 0.07083, 0.98975 }, ["Left Leg"] = { -0.10638, -0.00000, -0.07874, 0.99120 } } },
				{ t = 0.2, pose = { ["Torso"] = { 0.13954, 0.00000, 0.00000, 0.99022 }, ["Head"] = { -0.12277, 0.00000, -0.01209, 0.99236 }, ["Right Arm"] = { 0.07363, -0.00000, 0.57084, 0.81776 }, ["Left Arm"] = { 0.09559, 0.00000, -0.57172, 0.81486 }, ["Right Leg"] = { -0.12399, -0.00000, 0.07083, 0.98975 }, ["Left Leg"] = { -0.10638, -0.00000, -0.07874, 0.99120 } } },
				{ t = 0.3, pose = { ["Torso"] = { 0.13954, 0.00000, 0.00000, 0.99022 }, ["Head"] = { -0.12145, 0.00000, -0.02224, 0.99235 }, ["Right Arm"] = { 0.07363, -0.00000, 0.57084, 0.81776 }, ["Left Arm"] = { 0.09559, 0.00000, -0.57172, 0.81486 }, ["Right Leg"] = { -0.12399, -0.00000, 0.07083, 0.98975 }, ["Left Leg"] = { -0.10638, -0.00000, -0.07874, 0.99120 } } },
				{ t = 0.4, pose = { ["Torso"] = { 0.13954, 0.00000, 0.00000, 0.99022 }, ["Head"] = { -0.12033, -0.00000, -0.03073, 0.99226 }, ["Right Arm"] = { 0.07363, -0.00000, 0.57084, 0.81776 }, ["Left Arm"] = { 0.09559, 0.00000, -0.57172, 0.81486 }, ["Right Leg"] = { -0.12399, -0.00000, 0.07083, 0.98975 }, ["Left Leg"] = { -0.10638, -0.00000, -0.07874, 0.99120 } } },
				{ t = 0.5, pose = { ["Torso"] = { 0.13954, 0.00000, 0.00000, 0.99022 }, ["Head"] = { -0.11985, 0.00000, -0.03428, 0.99220 }, ["Right Arm"] = { 0.07363, -0.00000, 0.57084, 0.81776 }, ["Left Arm"] = { 0.09559, 0.00000, -0.57172, 0.81486 }, ["Right Leg"] = { -0.12399, -0.00000, 0.07083, 0.98975 }, ["Left Leg"] = { -0.10638, -0.00000, -0.07874, 0.99120 } } },
				{ t = 0.6, pose = { ["Torso"] = { 0.13954, 0.00000, 0.00000, 0.99022 }, ["Head"] = { -0.12075, 0.00000, -0.03237, 0.99216 }, ["Right Arm"] = { 0.07363, -0.00000, 0.57084, 0.81776 }, ["Left Arm"] = { 0.09559, 0.00000, -0.57172, 0.81486 }, ["Right Leg"] = { -0.12399, -0.00000, 0.07083, 0.98975 }, ["Left Leg"] = { -0.10638, -0.00000, -0.07874, 0.99120 } } },
				{ t = 0.7, pose = { ["Torso"] = { 0.13954, 0.00000, 0.00000, 0.99022 }, ["Head"] = { -0.12290, 0.00000, -0.02718, 0.99205 }, ["Right Arm"] = { 0.07363, -0.00000, 0.57084, 0.81776 }, ["Left Arm"] = { 0.09559, 0.00000, -0.57172, 0.81486 }, ["Right Leg"] = { -0.12399, -0.00000, 0.07083, 0.98975 }, ["Left Leg"] = { -0.10638, -0.00000, -0.07874, 0.99120 } } },
				{ t = 0.8, pose = { ["Torso"] = { 0.13954, 0.00000, 0.00000, 0.99022 }, ["Head"] = { -0.12546, 0.00000, -0.01952, 0.99191 }, ["Right Arm"] = { 0.07363, -0.00000, 0.57084, 0.81776 }, ["Left Arm"] = { 0.09559, 0.00000, -0.57172, 0.81486 }, ["Right Leg"] = { -0.12399, -0.00000, 0.07083, 0.98975 }, ["Left Leg"] = { -0.10638, -0.00000, -0.07874, 0.99120 } } },
				{ t = 0.9, pose = { ["Torso"] = { 0.13954, 0.00000, 0.00000, 0.99022 }, ["Head"] = { -0.12761, 0.00000, -0.01018, 0.99177 }, ["Right Arm"] = { 0.07363, -0.00000, 0.57084, 0.81776 }, ["Left Arm"] = { 0.09559, 0.00000, -0.57172, 0.81486 }, ["Right Leg"] = { -0.12399, -0.00000, 0.07083, 0.98975 }, ["Left Leg"] = { -0.10638, -0.00000, -0.07874, 0.99120 } } },
				{ t = 1.0, pose = { ["Torso"] = { 0.13954, 0.00000, 0.00000, 0.99022 }, ["Head"] = { -0.12851, 0.00000, 0.00000, 0.99171 }, ["Right Arm"] = { 0.07363, -0.00000, 0.57084, 0.81776 }, ["Left Arm"] = { 0.09559, 0.00000, -0.57172, 0.81486 }, ["Right Leg"] = { -0.12399, -0.00000, 0.07083, 0.98975 }, ["Left Leg"] = { -0.10638, -0.00000, -0.07874, 0.99120 } } },
				{ t = 1.1, pose = { ["Torso"] = { 0.13954, 0.00000, 0.00000, 0.99022 }, ["Head"] = { -0.12761, 0.00000, 0.01018, 0.99177 }, ["Right Arm"] = { 0.07363, -0.00000, 0.57084, 0.81776 }, ["Left Arm"] = { 0.09559, 0.00000, -0.57172, 0.81486 }, ["Right Leg"] = { -0.12399, -0.00000, 0.07083, 0.98975 }, ["Left Leg"] = { -0.10638, -0.00000, -0.07874, 0.99120 } } },
				{ t = 1.2, pose = { ["Torso"] = { 0.13954, 0.00000, 0.00000, 0.99022 }, ["Head"] = { -0.12546, -0.00000, 0.01952, 0.99191 }, ["Right Arm"] = { 0.07363, -0.00000, 0.57084, 0.81776 }, ["Left Arm"] = { 0.09559, 0.00000, -0.57172, 0.81486 }, ["Right Leg"] = { -0.12399, -0.00000, 0.07083, 0.98975 }, ["Left Leg"] = { -0.10638, -0.00000, -0.07874, 0.99120 } } },
				{ t = 1.3, pose = { ["Torso"] = { 0.13954, 0.00000, 0.00000, 0.99022 }, ["Head"] = { -0.12290, 0.00000, 0.02718, 0.99205 }, ["Right Arm"] = { 0.07363, -0.00000, 0.57084, 0.81776 }, ["Left Arm"] = { 0.09559, 0.00000, -0.57172, 0.81486 }, ["Right Leg"] = { -0.12399, -0.00000, 0.07083, 0.98975 }, ["Left Leg"] = { -0.10638, -0.00000, -0.07874, 0.99120 } } },
				{ t = 1.4, pose = { ["Torso"] = { 0.13954, 0.00000, 0.00000, 0.99022 }, ["Head"] = { -0.12075, 0.00000, 0.03237, 0.99216 }, ["Right Arm"] = { 0.07363, -0.00000, 0.57084, 0.81776 }, ["Left Arm"] = { 0.09559, 0.00000, -0.57172, 0.81486 }, ["Right Leg"] = { -0.12399, -0.00000, 0.07083, 0.98975 }, ["Left Leg"] = { -0.10638, -0.00000, -0.07874, 0.99120 } } },
				{ t = 1.5, pose = { ["Torso"] = { 0.13954, 0.00000, 0.00000, 0.99022 }, ["Head"] = { -0.11985, 0.00000, 0.03428, 0.99220 }, ["Right Arm"] = { 0.07363, -0.00000, 0.57084, 0.81776 }, ["Left Arm"] = { 0.09559, 0.00000, -0.57172, 0.81486 }, ["Right Leg"] = { -0.12399, -0.00000, 0.07083, 0.98975 }, ["Left Leg"] = { -0.10638, -0.00000, -0.07874, 0.99120 } } },
				{ t = 1.6, pose = { ["Torso"] = { 0.13954, 0.00000, 0.00000, 0.99022 }, ["Head"] = { -0.11992, 0.00000, 0.03073, 0.99231 }, ["Right Arm"] = { 0.07363, -0.00000, 0.57084, 0.81776 }, ["Left Arm"] = { 0.09559, 0.00000, -0.57172, 0.81486 }, ["Right Leg"] = { -0.12399, -0.00000, 0.07083, 0.98975 }, ["Left Leg"] = { -0.10638, -0.00000, -0.07874, 0.99120 } } },
				{ t = 1.7, pose = { ["Torso"] = { 0.13954, 0.00000, 0.00000, 0.99022 }, ["Head"] = { -0.12024, 0.00000, 0.02224, 0.99250 }, ["Right Arm"] = { 0.07363, -0.00000, 0.57084, 0.81776 }, ["Left Arm"] = { 0.09559, 0.00000, -0.57172, 0.81486 }, ["Right Leg"] = { -0.12399, -0.00000, 0.07083, 0.98975 }, ["Left Leg"] = { -0.10638, -0.00000, -0.07874, 0.99120 } } },
				{ t = 1.8, pose = { ["Torso"] = { 0.13954, 0.00000, 0.00000, 0.99022 }, ["Head"] = { -0.12094, -0.00000, 0.01209, 0.99259 }, ["Right Arm"] = { 0.07363, -0.00000, 0.57084, 0.81776 }, ["Left Arm"] = { 0.09559, 0.00000, -0.57172, 0.81486 }, ["Right Leg"] = { -0.12399, -0.00000, 0.07083, 0.98975 }, ["Left Leg"] = { -0.10638, -0.00000, -0.07874, 0.99120 } } },
				{ t = 1.9, pose = { ["Torso"] = { 0.13954, 0.00000, 0.00000, 0.99022 }, ["Head"] = { -0.12222, -0.00000, 0.00357, 0.99250 }, ["Right Arm"] = { 0.07363, -0.00000, 0.57084, 0.81776 }, ["Left Arm"] = { 0.09559, 0.00000, -0.57172, 0.81486 }, ["Right Leg"] = { -0.12399, -0.00000, 0.07083, 0.98975 }, ["Left Leg"] = { -0.10638, -0.00000, -0.07874, 0.99120 } } },
				{ t = 2.0, pose = { ["Torso"] = { 0.13954, 0.00000, 0.00000, 0.99022 }, ["Head"] = { -0.12428, -0.00000, 0.00000, 0.99225 }, ["Right Arm"] = { 0.07363, -0.00000, 0.57084, 0.81776 }, ["Left Arm"] = { 0.09559, 0.00000, -0.57172, 0.81486 }, ["Right Leg"] = { -0.12399, -0.00000, 0.07083, 0.98975 }, ["Left Leg"] = { -0.10638, -0.00000, -0.07874, 0.99120 } } },
			} },
			Tuck = { length = 1.0, loop = true, steer = 0.0, keys = {
				{ t = 0.0, pose = { ["Torso"] = { 0.16918, -0.00000, -0.00000, 0.98559 }, ["Head"] = { -0.18004, -0.00000, 0.00000, 0.98366 }, ["Right Arm"] = { 0.07644, -0.00000, 0.59320, 0.80141 }, ["Left Arm"] = { 0.09924, 0.00000, -0.59411, 0.79824 }, ["Right Leg"] = { -0.12377, -0.00000, 0.11628, 0.98547 }, ["Left Leg"] = { -0.10617, -0.00000, -0.12441, 0.98653 } } },
				{ t = 1.0, pose = { ["Torso"] = { 0.16918, -0.00000, -0.00000, 0.98559 }, ["Head"] = { -0.18004, -0.00000, 0.00000, 0.98366 }, ["Right Arm"] = { 0.07644, -0.00000, 0.59320, 0.80141 }, ["Left Arm"] = { 0.09924, 0.00000, -0.59411, 0.79824 }, ["Right Leg"] = { -0.12377, -0.00000, 0.11628, 0.98547 }, ["Left Leg"] = { -0.10617, -0.00000, -0.12441, 0.98653 } } },
			} },
			Brake = { length = 1.0, loop = true, steer = 0.0, keys = {
				{ t = 0.0, pose = { ["Torso"] = { 0.10481, 0.00000, 0.00000, 0.99449 }, ["Head"] = { -0.07199, 0.00000, 0.00000, 0.99740 }, ["Right Arm"] = { 0.07066, 0.00000, 0.54471, 0.83564 }, ["Left Arm"] = { 0.09174, 0.00000, -0.54555, 0.83304 }, ["Right Leg"] = { -0.12411, 0.00000, 0.01727, 0.99212 }, ["Left Leg"] = { -0.10651, 0.00000, -0.02485, 0.99400 } } },
				{ t = 1.0, pose = { ["Torso"] = { 0.10481, 0.00000, 0.00000, 0.99449 }, ["Head"] = { -0.07199, 0.00000, 0.00000, 0.99740 }, ["Right Arm"] = { 0.07066, 0.00000, 0.54471, 0.83564 }, ["Left Arm"] = { 0.09174, 0.00000, -0.54555, 0.83304 }, ["Right Leg"] = { -0.12411, 0.00000, 0.01727, 0.99212 }, ["Left Leg"] = { -0.10651, 0.00000, -0.02485, 0.99400 } } },
			} },
			LeanRight = { length = 1.0, loop = true, steer = 0.24, keys = {
				{ t = 0.0, pose = { ["Torso"] = { 0.17564, -0.13342, -0.16469, 0.96137 }, ["Head"] = { -0.17435, 0.00000, -0.06362, 0.98263 }, ["Right Arm"] = { 0.25756, 0.00000, 0.62658, 0.73557 }, ["Left Arm"] = { -0.06365, 0.00000, -0.49522, 0.86643 }, ["Right Leg"] = { -0.31351, 0.00000, 0.24114, 0.91846 }, ["Left Leg"] = { 0.10797, -0.00000, -0.09514, 0.98959 } } },
				{ t = 1.0, pose = { ["Torso"] = { 0.17564, -0.13342, -0.16469, 0.96137 }, ["Head"] = { -0.17435, 0.00000, -0.06362, 0.98263 }, ["Right Arm"] = { 0.25756, 0.00000, 0.62658, 0.73557 }, ["Left Arm"] = { -0.06365, 0.00000, -0.49522, 0.86643 }, ["Right Leg"] = { -0.31351, 0.00000, 0.24114, 0.91846 }, ["Left Leg"] = { 0.10797, -0.00000, -0.09514, 0.98959 } } },
			} },
			LeanLeft = { length = 1.0, loop = true, steer = -0.24, keys = {
				{ t = 0.0, pose = { ["Torso"] = { 0.17430, 0.13517, 0.17430, 0.95967 }, ["Head"] = { -0.17270, -0.00000, 0.05327, 0.98353 }, ["Right Arm"] = { -0.08833, -0.00000, 0.46757, 0.87953 }, ["Left Arm"] = { 0.28308, 0.00000, -0.61252, 0.73803 }, ["Right Leg"] = { 0.09810, -0.00000, 0.07991, 0.99196 }, ["Left Leg"] = { -0.29659, -0.00000, -0.25045, 0.92158 } } },
				{ t = 1.0, pose = { ["Torso"] = { 0.17430, 0.13517, 0.17430, 0.95967 }, ["Head"] = { -0.17270, -0.00000, 0.05327, 0.98353 }, ["Right Arm"] = { -0.08833, -0.00000, 0.46757, 0.87953 }, ["Left Arm"] = { 0.28308, 0.00000, -0.61252, 0.73803 }, ["Right Leg"] = { 0.09810, -0.00000, 0.07991, 0.99196 }, ["Left Leg"] = { -0.29659, -0.00000, -0.25045, 0.92158 } } },
			} },
			Wheelie = { length = 1.0, loop = true, steer = 0.0, keys = {
				{ t = 0.0, pose = { ["Torso"] = { 0.06495, -0.00000, -0.00000, 0.99789 }, ["Head"] = { 0.15107, -0.00000, 0.00000, 0.98852 }, ["Right Arm"] = { 0.06763, 0.00000, 0.51481, 0.85463 }, ["Left Arm"] = { 0.08781, -0.00000, -0.51561, 0.85231 }, ["Right Leg"] = { -0.12407, -0.00000, -0.04410, 0.99129 }, ["Left Leg"] = { -0.10649, -0.00000, 0.03698, 0.99363 } } },
				{ t = 1.0, pose = { ["Torso"] = { 0.06495, -0.00000, -0.00000, 0.99789 }, ["Head"] = { 0.15107, -0.00000, 0.00000, 0.98852 }, ["Right Arm"] = { 0.06763, 0.00000, 0.51481, 0.85463 }, ["Left Arm"] = { 0.08781, -0.00000, -0.51561, 0.85231 }, ["Right Leg"] = { -0.12407, -0.00000, -0.04410, 0.99129 }, ["Left Leg"] = { -0.10649, -0.00000, 0.03698, 0.99363 } } },
			} },
		},
	}
end)()

-- @body (everything below is shared with the single-file RideKit_Client.lua)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
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
	local frontSlider = bike:WaitForChild("RideKit_FrontSlider") :: BasePart
	local frontSlideMotor = steerPivot:WaitForChild("RideKit_FrontSlideMotor") :: Motor6D
	local frontHubMotor = frontSlider:WaitForChild("RideKit_FrontHubMotor") :: Motor6D
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
	local animClips = AnimPlayer.prepare(AnimData)
	local animWeights = { tuck = 0, brake = 0, leanR = 0, leanL = 0, wheelie = 0 }
	local animTime = 0
	local poseBounce = 0

	-- motor / wind sounds and brake lights already in the model (played locally)
	local engineSound, windSound = nil, nil
	for _, d in ipairs(bike:GetDescendants()) do
		if d:IsA("Sound") then
			if string.lower(d.Name) == "wind" then
				windSound = d
			elseif d.Looped and not engineSound then
				engineSound = d
			end
		end
	end
	local engineVol = if engineSound then engineSound.Volume else 0
	local windVol = if windSound then windSound.Volume else 0
	local brakeLights = {}
	for _, d in ipairs(bike:GetDescendants()) do
		if d:IsA("Light") then
			local a = d.Parent
			while a and a ~= bike do
				local n = string.lower(a.Name)
				if n == "brk" or string.find(n, "brakelight", 1, true) or string.find(n, "brake light", 1, true) then
					table.insert(brakeLights, d)
					break
				end
				a = a.Parent
			end
		end
	end
	local offF, offR = 0, 0

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
		local steerTarget = steer * math.rad(Config.MaxSteerAngle) * (1 - 0.4 * speedFrac)
		steerVis += (steerTarget - steerVis) * (1 - math.exp(-12 * dt))
		local compF, hitF = physics:probe(1)
		local compR, hitR = physics:probe(2)
		-- wheel travel shown on the forks / swingarm, lightly smoothed
		local smooth = 1 - math.exp(-30 * dt)
		offF += (math.clamp(compF - travel * 0.5, -travel * 0.5, travel * 0.8) - offF) * smooth
		offR += (math.clamp(compR - travel * 0.5, -travel * 0.5, travel * 0.8) - offR) * smooth
		steerMotor.Transform = CFrame.Angles(0, -steerVis, 0)
		frontSlideMotor.Transform = CFrame.new(0, offF, 0) -- fork lowers + wheel slide up the fork
		frontHubMotor.Transform = CFrame.Angles(-spinF, 0, 0)
		swingMotor.Transform = CFrame.Angles(-math.asin(math.clamp(offR / armLen, -0.5, 0.5)), 0, 0)
		rearHubMotor.Transform = CFrame.Angles(-spinR, 0, 0)

		-- sounds and brake light
		local braking = char ~= nil and throttle < -0.1 and vF > 1
		for _, l in ipairs(brakeLights) do
			l.Enabled = braking
		end
		if engineSound then
			local level = math.max(speedFrac, math.abs(throttle) * 0.6)
			engineSound.PlaybackSpeed = 0.6 + 1.1 * speedFrac + 0.15 * math.max(throttle, 0)
			engineSound.Volume = if char then engineVol * (0.35 + 0.65 * level) else 0
			if char and not engineSound.IsPlaying then
				engineSound:Play()
			end
		end
		if windSound then
			windSound.Volume = windVol * speedFrac
			if speedFrac > 0.05 and not windSound.IsPlaying then
				windSound:Play()
			end
		end

		-- rider animation (made in Blender, see blender/anim): blend the clips by riding state
		if char ~= riderChar then
			if riderJoints then
				AnimPlayer.clear(riderJoints)
			end
			if tookOver and riderChar then
				AnimPlayer.release(riderChar)
			end
			riderChar = char
			riderJoints = if char then AnimPlayer.joints(char) else nil
			tookOver = riderJoints ~= nil and char == player.Character -- R6 only; R15 keeps its sit animation
			if tookOver then
				AnimPlayer.takeOver(char)
			end
			animTime = 0
		end
		if riderJoints and char then
			AnimPlayer.silence(char)
			animTime += dt
			-- wheelie = nose higher than the ground slope under the wheels
			local pitch = math.asin(math.clamp(chassis.CFrame.LookVector.Y, -1, 1))
			local slope = 0
			if hitF and hitR then
				local d = hitF.Position - hitR.Position
				slope = math.asin(math.clamp(d.Y / math.max(d.Magnitude, 0.01), -1, 1))
			end
			local wheelieAngle = math.max(pitch - slope, 0)
			local moving = math.clamp(math.abs(vF) / 12, 0, 1)
			local target = {
				tuck = math.max(throttle, 0) * math.clamp(math.abs(vF) / 25, 0.3, 1),
				brake = if throttle < -0.1 and vF > 1 then -throttle else 0,
				leanR = math.max(steer, 0) * math.max(moving, 0.5),
				leanL = math.max(-steer, 0) * math.max(moving, 0.5),
				wheelie = math.clamp((wheelieAngle - 0.06) / 0.3, 0, 1),
			}
			local a = 1 - math.exp(-Config.AnimBlendSpeed * dt)
			for k, v in pairs(target) do
				animWeights[k] += (v - animWeights[k]) * a
			end
			AnimPlayer.apply(riderJoints, AnimPlayer.pose(animClips, animTime, animWeights))
		end
	end)
end

local CollectionService = game:GetService("CollectionService")
for _, b in ipairs(CollectionService:GetTagged("RideKitBike")) do
	task.spawn(runBike, b)
end
CollectionService:GetInstanceAddedSignal("RideKitBike"):Connect(function(b)
	task.spawn(runBike, b)
end)
