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
