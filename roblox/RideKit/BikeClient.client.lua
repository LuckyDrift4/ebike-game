-- RideKit.BikeClient (Script, RunContext = Client). Runs on every player's
-- machine for this bike:
--   * the rider's machine runs the physics (RideKit.Physics)
--   * everyone sees the wheels spin, the bars turn, the fork and swingarm move,
--     the engine sound and brake light, and the rider animated (R6)

local kit = script.Parent
local Config = require(kit:WaitForChild("Config"))
local Physics = require(kit:WaitForChild("Physics"))
local AnimPlayer = require(kit:WaitForChild("AnimPlayer"))
local AnimData = require(kit:WaitForChild("AnimData"))

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
	local remote = bike:WaitForChild("RideKit_Remote", 10) :: RemoteEvent?

	local physics = Physics.new(bike, Config)
	local radF = bike:GetAttribute("RK_RadiusF") :: number
	local radR = bike:GetAttribute("RK_RadiusR") :: number
	local armLen = bike:GetAttribute("RK_SwingArm") :: number
	local travel = Config.SuspensionTravel

	-- E = wheelie (keyboard E, gamepad X, the Wheelie button on mobile); stoppies are on S
	local leanBack = 0
	local ACT_BACK = "RideKitWheelie_" .. bike.Name .. "_" .. tostring(math.random(1, 1e9))
	local function onBack(_, state)
		leanBack = if state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change then 1 else 0
		return Enum.ContextActionResult.Sink
	end

	local wasDriver = false
	local crashSent = false
	local spinF, spinR, steerVis = 0, 0, 0
	local riderJoints, riderChar = nil, nil
	local tookOver = false
	local animClips = AnimPlayer.prepare(AnimData)
	local clipSteer = if animClips.LeanRight then math.max(math.abs(animClips.LeanRight.steer or 0.24), 0.05) else 0.24
	local animWeights = {}
	local animTime = 0
	local offF, offR = 0, 0

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

	local function bind(on: boolean)
		if on then
			local prio = Enum.ContextActionPriority.High.Value
			ContextActionService:BindActionAtPriority(ACT_BACK, onBack, true, prio, table.unpack(Config.WheelieKeys))
			ContextActionService:SetTitle(ACT_BACK, "Wheelie")
			ContextActionService:SetPosition(ACT_BACK, UDim2.new(1, -190, 1, -95))
		else
			ContextActionService:UnbindAction(ACT_BACK)
			leanBack = 0
		end
	end

	-- thrown off: the rider keeps the bike's speed and tumbles; the bike falls over
	local function crashOff(char: Model)
		crashSent = true
		if remote then
			remote:FireServer("crash")
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local v = chassis.AssemblyLinearVelocity
		if hum then
			hum.Sit = false
			hum.Jump = true
		end
		task.delay(0.05, function()
			if root and root.Parent then
				root.AssemblyLinearVelocity = v * 0.85 + Vector3.new(0, 18, 0)
			end
			if hum and hum.Parent then
				hum:ChangeState(Enum.HumanoidStateType.FallingDown)
			end
		end)
	end

	local conn
	conn = RunService.Stepped:Connect(function(_, dt)
		if not bike:IsDescendantOf(workspace) then
			conn:Disconnect()
			return
		end
		local occupant = seat.Occupant
		local char = occupant and occupant.Parent
		local isDriver = char ~= nil and char == player.Character

		-- the driver role: controls, fresh physics state
		if isDriver ~= wasDriver then
			wasDriver = isDriver
			physics:reset()
			bind(isDriver)
			crashSent = false
		end

		physics:setIgnore(if char then { bike, char } else { bike })
		local tf = if char then seat.ThrottleFloat else 0
		local throttle, brake = math.max(tf, 0), math.max(-tf, 0)
		local steer = if char then seat.SteerFloat else 0

		local out = nil
		if isDriver and not chassis.Anchored then
			out = physics:step(dt, {
				driver = true,
				throttle = throttle,
				brake = brake,
				steer = steer,
				leanBack = leanBack,
			})
			if out.crashed and not crashSent and char then
				crashOff(char)
			end
		end

		-- visuals for everyone: spin, steer, suspension -------------------------------------------
		local cf = chassis.CFrame
		local vF = chassis.AssemblyLinearVelocity:Dot(cf.LookVector)
		local speedFrac = math.clamp(math.abs(vF) / Config.MaxSpeed, 0, 1)
		local compF, compR, hitF, hitR
		if out then
			compF, compR = out.comp[1], out.comp[2]
			hitF, hitR = out.contact[1], out.contact[2]
		else
			local c1, h1 = physics:probe(1)
			local c2, h2 = physics:probe(2)
			compF, compR, hitF, hitR = c1, c2, h1 ~= nil, h2 ~= nil
		end
		-- wheels: roll with the ground, spin up when the rear lights up, stop when locked
		local rollF, rollR = vF / radF, vF / radR
		if out then
			if out.slip[2] > 0.05 and throttle > 0.2 then
				rollR += out.slip[2] * 40
			end
			if out.braking then
				rollF *= 1 - out.slip[1]
				rollR *= 1 - out.slip[2]
			end
		end
		if not hitR and throttle > 0.2 then
			rollR = math.max(rollR, 40 * throttle) -- in the air the throttle spins it up
		end
		spinF = (spinF + rollF * dt) % (2 * math.pi)
		spinR = (spinR + rollR * dt) % (2 * math.pi)
		local steerTarget = if out then out.steerAngle else steer * Physics.lockAt(Config, physics.wheelbase, vF)
		steerVis += (steerTarget - steerVis) * (1 - math.exp(-20 * dt))
		local smooth = 1 - math.exp(-30 * dt)
		local function shown(c, hit)
			return if hit then math.clamp(c - travel * 0.5, -travel * 0.5, travel * 0.6) else -travel * 0.5
		end
		offF += (shown(compF, hitF) - offF) * smooth
		offR += (shown(compR, hitR) - offR) * smooth
		steerMotor.Transform = CFrame.Angles(0, -steerVis, 0)
		frontSlideMotor.Transform = CFrame.new(0, offF, 0) -- fork lowers + wheel slide up the fork
		frontHubMotor.Transform = CFrame.Angles(-spinF, 0, 0)
		swingMotor.Transform = CFrame.Angles(-math.asin(math.clamp(offR / armLen, -0.5, 0.5)), 0, 0)
		rearHubMotor.Transform = CFrame.Angles(-spinR, 0, 0)

		-- sounds and brake light -------------------------------------------------------------------
		local braking = char ~= nil and brake > 0.1 and vF > 1
		for _, l in ipairs(brakeLights) do
			l.Enabled = braking
		end
		if engineSound then
			local rev = math.max(speedFrac, if hitR then 0 else throttle * 0.9)
			engineSound.PlaybackSpeed = 0.6 + 1.1 * rev + 0.15 * throttle
			engineSound.Volume = if char then engineVol * (0.35 + 0.65 * math.max(rev, throttle * 0.6)) else 0
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

		-- rider animation (keyframed in Blender, see blender/anim) ----------------------------------
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
			table.clear(animWeights)
		end
		if riderJoints and char then
			AnimPlayer.silence(char)
			animTime += dt
			-- always seated, upright: brace on the brakes (and in a stoppie), arms follow the bars
			local stoppie = if out then out.stoppie else (hitF and not hitR and cf.LookVector.Y < -0.05)
			local target = {
				brake = if braking or stoppie then math.max(brake, if stoppie then 1 else 0) else 0,
				leanR = math.clamp(steerVis / clipSteer, 0, 1),
				leanL = math.clamp(-steerVis / clipSteer, 0, 1),
			}
			local a = 1 - math.exp(-Config.AnimBlendSpeed * dt)
			for k, v in pairs(target) do
				animWeights[k] = (animWeights[k] or 0) + (v - (animWeights[k] or 0)) * a
			end
			AnimPlayer.apply(riderJoints, AnimPlayer.pose(animClips, animTime, animWeights))
		end
	end)
end
-- @end

runBike(kit.Parent :: Model)
