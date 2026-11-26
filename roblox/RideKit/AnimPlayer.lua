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
