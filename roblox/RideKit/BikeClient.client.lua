-- RideKit.BikeClient (Script, RunContext = Client). Runs on every player's
-- machine for this bike:
--   * drives the bike when the local player is the rider
--   * animates wheels, fork, suspension for everyone
--   * poses the rider (R6) for everyone

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local kit = script.Parent
local Config = require(kit:WaitForChild("Config"))
local Physics = require(kit:WaitForChild("Physics"))
local Pose = require(kit:WaitForChild("Pose"))

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
		local steerTarget = steer * math.rad(Config.MaxSteerAngle) * (1 - 0.65 * speedFrac)
		steerVis += (steerTarget - steerVis) * (1 - math.exp(-12 * dt))
		local compF, hitF = physics:probe(1)
		local compR, hitR = physics:probe(2)
		-- wheel travel shown on the forks / swingarm, lightly smoothed
		local smooth = 1 - math.exp(-30 * dt)
		offF += (math.clamp(compF - travel * 0.5, -travel * 0.5, travel * 0.8) - offF) * smooth
		offR += (math.clamp(compR - travel * 0.5, -travel * 0.5, travel * 0.8) - offR) * smooth
		steerMotor.Transform = CFrame.Angles(0, -steerVis, 0)
		frontHubMotor.Transform = CFrame.new(0, offF, 0) * CFrame.Angles(-spinF, 0, 0)
		swingMotor.Transform = CFrame.Angles(-math.asin(math.clamp(offR / armLen, -0.5, 0.5)), 0, 0)
		rearHubMotor.Transform = CFrame.Angles(-spinR, 0, 0)

		-- rider pose
		if char ~= riderChar then
			if riderJoints then
				Pose.clear(riderJoints)
				riderJoints.mem = nil
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
				dt = dt,
			})
		end
	end)
end
-- @end

runBike(kit.Parent :: Model)
