-- Plays the Blender riding clips (AnimData, via the real AnimPlayer) on a
-- standard R6 rig seated where RideKit seats the rider on surron2 (BikeRef),
-- and checks the hands land on the grips (turned with the bars in the lean
-- clips), the feet near the steps and the face looks forward - for every key
-- of every clip and for blends between them.
-- Executed by run_tests.mjs (node run_tests.mjs anim_test.luau).

local R6 = {
	Torso = { CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), "HRP" },
	Head = { CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), "Torso" },
	["Right Arm"] = { CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), "Torso" },
	["Left Arm"] = { CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), "Torso" },
	["Right Leg"] = { CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), "Torso" },
	["Left Leg"] = { CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), "Torso" },
}
local function cf(d)
	local r, p = d.r, d.p
	return CFrame.new(p[1], p[2], p[3], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
end
local function v(t) return Vector3.new(t[1], t[2], t[3]) end

local hrp = cf(BikeRef.hrp)
local chassis = cf(BikeRef.chassis)
local sp = cf(BikeRef.steerPivot)
local failures = 0
local function check(c, msg)
	if not c then
		failures += 1
		print("FAIL: " .. msg)
	end
end

local function body(pose)
	local torso = hrp * R6.Torso[1] * pose.Torso * R6.Torso[2]:Inverse()
	local out = { Torso = torso }
	for _, part in ipairs({ "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg" }) do
		out[part] = torso * R6[part][1] * pose[part] * R6[part][2]:Inverse()
	end
	return out
end

local function measure(pose, steer)
	local b = body(pose)
	local turn = sp * CFrame.fromAxisAngle(Vector3.yAxis, -steer) * sp:Inverse()
	local gR, gL = turn * v(BikeRef.gripR), turn * v(BikeRef.gripL)
	local handR = b["Right Arm"] * Vector3.new(0, -1, 0)
	local handL = b["Left Arm"] * Vector3.new(0, -1, 0)
	local footR = b["Right Leg"] * Vector3.new(0, -1, 0)
	local footL = b["Left Leg"] * Vector3.new(0, -1, 0)
	return math.max((handR - gR).Magnitude, (handL - gL).Magnitude),
		math.max((footR - v(BikeRef.pegR)).Magnitude, (footL - v(BikeRef.pegL)).Magnitude),
		b.Head.LookVector:Dot(chassis.LookVector)
end

local clips = AnimPlayer.prepare(AnimData)
for _, name in ipairs({ "Ride", "Brake", "LeanRight", "LeanLeft" }) do
	local clip = clips[name]
	check(clip ~= nil, name .. ": clip exported")
	if not clip then
		continue
	end
	local worstH, worstF, minLook = 0, 0, 1
	for t = 0, clip.length, 0.05 do
		local h, f, look = measure(AnimPlayer.sample(clip, t), clip.steer)
		worstH, worstF, minLook = math.max(worstH, h), math.max(worstF, f), math.min(minLook, look)
	end
	print(string.format("%-9s hands->grips worst %.3f  feet->steps worst %.3f  head·forward min %+.2f", name, worstH, worstF, minLook))
	check(worstH < 0.12, name .. ": hands on the grips")
	check(worstF < 0.5, name .. ": feet at the steps")
	check(minLook > 0.6, name .. ": looking forward")
end
-- blends the client makes while riding straight (bars straight)
for _, w in ipairs({
	{ brake = 0.5 },
	{ brake = 1 },
}) do
	local h = measure(AnimPlayer.pose(clips, 0.7, w), 0)
	check(h < 0.15, "blend keeps the hands on the grips")
	print(string.format("blend %s: hands->grips %.3f", (function()
		local t = {}
		for k, x in pairs(w) do
			if x > 0 then
				table.insert(t, k .. " " .. x)
			end
		end
		table.sort(t)
		return table.concat(t, ", ")
	end)(), h))
end
-- half lean with half-turned bars
local h = measure(AnimPlayer.pose(clips, 0.3, { brake = 0, leanR = 0.5, leanL = 0 }), clips.LeanRight.steer * 0.5)
print(string.format("half lean right: hands->grips %.3f", h))
check(h < 0.25, "half lean keeps the hands near the grips")
-- sitting upright (the pose the user asked for): the torso stays close to vertical on the bike
local up = body(AnimPlayer.sample(clips.Ride, 0)).Torso.UpVector:Dot(chassis.UpVector)
print(string.format("Ride torso upright: %.1f deg from the bike's up", math.deg(math.acos(math.clamp(up, -1, 1)))))
check(up > math.cos(math.rad(8)), "Ride: sitting upright")
print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
