-- RideKit.BikeServer (Script, RunContext = Server). Lives in the RideKit folder
-- inside the bike model. Rigs the bike, handles mounting and network ownership,
-- and lets the bike roll to a stop after the rider gets off.

local kit = script.Parent
local bike = kit.Parent :: Model
local Config = require(kit:WaitForChild("Config"))
local Rig = require(kit:WaitForChild("Rig"))
local Physics = require(kit:WaitForChild("Physics"))

-- @body (everything below is shared with the single-file RideKit_Server.lua)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local rig = Rig.build(bike, Config)
local seat: VehicleSeat = rig.seat
local chassis: BasePart = rig.chassis
local prompt: ProximityPrompt = rig.prompt
local physics = Physics.new(bike, Config)

-- mount with the prompt (walking into the seat works too)
prompt.Triggered:Connect(function(player)
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 and seat.Occupant == nil then
		seat:Sit(hum)
	end
end)

-- place the rider on the seat: low enough for the feet to reach the pegs
seat.ChildAdded:Connect(function(child)
	if child.Name == "SeatWeld" and child:IsA("Weld") then
		task.defer(function()
			child.C0 = CFrame.new(bike:GetAttribute("RK_RiderOffset"))
			child.C1 = CFrame.new()
		end)
	end
end)

local coasting = false
seat:GetPropertyChangedSignal("Occupant"):Connect(function()
	local occupant = seat.Occupant
	prompt.Enabled = occupant == nil
	if occupant then
		coasting = false
		local player = Players:GetPlayerFromCharacter(occupant.Parent)
		chassis.Anchored = false
		if player then
			chassis:SetNetworkOwner(player)
		end
	else
		if not chassis.Anchored then
			chassis:SetNetworkOwner(nil)
			physics:resetHeading()
			coasting = true
		end
	end
end)

-- after dismounting: brake to a stop on the server, then park (anchor) upright
local stillTime = 0
RunService.Stepped:Connect(function(_, dt)
	if not coasting then
		return
	end
	local speed = physics:step(dt, 0, 0, false, false)
	if math.abs(speed) < 0.5 then
		stillTime += dt
	else
		stillTime = 0
	end
	if stillTime > 0.75 then
		coasting = false
		stillTime = 0
		chassis.Anchored = true
		chassis.AssemblyLinearVelocity = Vector3.zero
		chassis.AssemblyAngularVelocity = Vector3.zero
	end
end)
