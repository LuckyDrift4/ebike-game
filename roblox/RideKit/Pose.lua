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
  s       : { throttle, steer, speed, maxSpeed, wheelie, bounce, dt }
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
	local function torsoFor(extra: number, tw: number): (CFrame, CFrame)
		local local_ = CFrame.fromAxisAngle(Vector3.yAxis, baseTwist + tw) * roll
			* CFrame.fromAxisAngle(Vector3.xAxis, -(lean + extra))
		local T = solve(root, hrpCF, hrpCF.Rotation * local_)
		return T, hrpCF * root.C0 * T * root.C1:Inverse()
	end
	local best, bestExtra, bestTw = math.huge, 0, 0
	for extra = -0.15, p.MaxExtraLean + 1e-6, 0.05 do
		for tw = -0.6, 0.6 + 1e-6, 0.05 do
			local _, torso = torsoFor(extra, tw)
			local dR = (targets.gripR - torso * j.RS.C0.Position).Magnitude - armReach
			local dL = (targets.gripL - torso * j.LS.C0.Position).Magnitude - armReach
			local fR = math.max((targets.pegR - torso * j.RH.C0.Position).Magnitude - legReach, 0)
			local fL = math.max((targets.pegL - torso * j.LH.C0.Position).Magnitude - legReach, 0)
			local cost = dR * dR + dL * dL + 0.5 * (fR * fR + fL * fL) + 0.02 * extra * extra + 0.01 * tw * tw
			if cost < best then
				best, bestExtra, bestTw = cost, extra, tw
			end
		end
	end
	-- glide towards the best stance instead of snapping (the search is coarse)
	local mem = j.mem or { extra = bestExtra, tw = bestTw }
	j.mem = mem
	local a = if s.dt then 1 - math.exp(-12 * s.dt) else 1
	mem.extra += (bestExtra - mem.extra) * a
	mem.tw += (bestTw - mem.tw) * a
	local rootT, torsoCF = torsoFor(mem.extra, mem.tw)
	root.Transform = rootT

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
