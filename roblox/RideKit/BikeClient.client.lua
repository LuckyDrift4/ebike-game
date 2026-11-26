-- RideKit.BikeClient (Script, RunContext = Client). Runs on every player's
-- machine for this bike:
--   * drives the bike when the local player is the rider
--   * animates wheels, fork, suspension for everyone
--   * poses the rider (R6) for everyone

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
-- @end

runBike(kit.Parent :: Model)
