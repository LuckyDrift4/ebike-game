-- RideKit.BikeServer (Script, RunContext = Server). Lives in the RideKit folder
-- inside the bike model. Rigs the bike, handles getting on and off, network
-- ownership and crashes, and lets the bike roll to a stop (or fall over) after
-- the rider gets off.

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

-- the rider's client tells us when they crash
local remote = Instance.new("RemoteEvent")
remote.Name = "RideKit_Remote"
remote.Parent = bike

local function isDown(): boolean
	return chassis.CFrame.UpVector.Y < 0.6
end

-- stand a fallen bike back up where it lies
local function pickUp()
	local cf = chassis.CFrame
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(cf.UpVector.X, 0, cf.UpVector.Z)
	end
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bike }
	local hit = workspace:Raycast(cf.Position + Vector3.yAxis * 6, Vector3.yAxis * -30, params)
	local ground = if hit then hit.Position.Y else cf.Position.Y - 3
	local rear = bike:GetAttribute("RK_RearAxle") :: Vector3
	local height = -rear.Y + (bike:GetAttribute("RK_RadiusR") :: number) + 0.1
	local pos = Vector3.new(cf.Position.X, ground + height, cf.Position.Z)
	chassis.Anchored = true
	chassis.CFrame = CFrame.lookAt(pos, pos + flat)
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	physics:reset()
end

local function updatePrompt()
	prompt.Enabled = seat.Occupant == nil
	prompt.ActionText = if isDown() then "Pick up" else "Ride"
end

-- get on with the prompt (walking into the seat works too); a fallen bike gets picked up first
prompt.Triggered:Connect(function(player)
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or seat.Occupant ~= nil then
		return
	end
	if isDown() or physics.crashed then
		pickUp()
		updatePrompt()
		return
	end
	seat:Sit(hum)
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

-- while seated the rider weighs nothing: the bike's mass already includes them,
-- so every avatar rides the same
local madeMassless = {}
local function setRiderMassless(character: Model?, on: boolean)
	if on and character then
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("BasePart") and not d.Massless then
				d.Massless = true
				table.insert(madeMassless, d)
			end
		end
	else
		for _, p in ipairs(madeMassless) do
			if p.Parent then
				p.Massless = false
			end
		end
		table.clear(madeMassless)
	end
end

local coasting = false
local rider: Player? = nil
local stillTime = 0
seat:GetPropertyChangedSignal("Occupant"):Connect(function()
	local occupant = seat.Occupant
	if occupant then
		local player = Players:GetPlayerFromCharacter(occupant.Parent)
		if isDown() then
			pickUp()
		end
		coasting = false
		rider = player
		setRiderMassless(occupant.Parent, true)
		chassis.Anchored = false
		if player then
			chassis:SetNetworkOwner(player)
		end
	else
		setRiderMassless(nil, false)
		rider = nil
		if not chassis.Anchored then
			local speed = chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector)
			local crashed = physics.crashed
			chassis:SetNetworkOwner(nil)
			physics:reset()
			local leaning = chassis.CFrame.UpVector.Y < math.cos(math.rad(50))
			if crashed or leaning or math.abs(speed) > Config.DismountCrashSpeed then
				physics:crash("off") -- nobody holding it up: it falls over
			end
			coasting = true
			stillTime = 0
		end
	end
	updatePrompt()
end)

remote.OnServerEvent:Connect(function(player, what)
	if player == rider and what == "crash" then
		physics:crash("rider")
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy() -- thrown off
		end
	end
end)

-- after getting off: roll to a stop (or fall over), then park (anchor) where it ends up
RunService.Stepped:Connect(function(_, dt)
	if not coasting then
		return
	end
	local out = physics:step(dt, { driver = false, brake = if physics.crashed then 0 else 0.6 })
	local still = chassis.AssemblyLinearVelocity.Magnitude < 0.6 and chassis.AssemblyAngularVelocity.Magnitude < 0.4
	stillTime = if still then stillTime + dt else 0
	if stillTime > (if physics.crashed then 1.5 else 0.75) or chassis.Position.Y < workspace.FallenPartsDestroyHeight + 20 then
		coasting = false
		chassis.Anchored = true
		chassis.AssemblyLinearVelocity = Vector3.zero
		chassis.AssemblyAngularVelocity = Vector3.zero
		updatePrompt()
	end
	if out.crashed and prompt.ActionText ~= "Pick up" and isDown() then
		updatePrompt()
	end
end)
