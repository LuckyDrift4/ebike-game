-- Drives RideKit's real Physics module against a mock chassis on flat ground,
-- integrating gravity like the engine (4 substeps per frame), and checks that
-- the suspension settles at ride height without bouncing and that the bike drives.
_G.Enum = { RaycastFilterType = { Exclude = 0 } }
local GROUND_Y = 0
_G.workspace = {
	Gravity = 196.2,
	Raycast = function(_, origin, dir)
		if dir.Y >= 0 then return nil end
		local t = (GROUND_Y - origin.Y) / dir.Y
		if t < 0 or t > 1 then return nil end
		return { Position = origin + dir * t, Normal = Vector3.yAxis }
	end,
}
_G.RaycastParams = { new = function() return {} end }

local function run(drop: number, fps: number, frames: number, throttle: number)
	local radius, travel = 1.2, Config.SuspensionTravel
	-- chassis centre sits 0.8 above the axles; axles 2.5 ahead/behind
	local restY = GROUND_Y + radius - travel * 0.5 + travel * 0.5 + 0.8 -- axle at radius (+ sag offsets cancel)
	local chassis = { CFrame = CFrame.new(0, restY + 0.8 * 0 + drop, 0), AssemblyLinearVelocity = Vector3.zero, AssemblyMass = 10 }
	function chassis:ApplyImpulse(i) self.AssemblyLinearVelocity += i / self.AssemblyMass end
	local align = { CFrame = CFrame.new() }
	local bike = {
		attrs = { RK_FrontAxle = Vector3.new(0, -0.8, -2.5), RK_RearAxle = Vector3.new(0, -0.8, 2.5), RK_RadiusF = radius, RK_RadiusR = radius },
		WaitForChild = function(self, name)
			if name == "RideKit_Chassis" then return chassis end
		end,
		GetAttribute = function(self, k) return self.attrs[k] end,
	}
	chassis.WaitForChild = function(_, name) return align end
	local phys = Physics.new(bike, Config)
	local ys, xs = {}, {}
	for f = 1, frames do
		local dt = 1 / fps
		phys:step(dt, throttle, 0, false, true)
		for _ = 1, 4 do
			chassis.AssemblyLinearVelocity += Vector3.new(0, -workspace.Gravity * dt / 4, 0)
			chassis.CFrame = CFrame.new(chassis.CFrame.Position + chassis.AssemblyLinearVelocity * (dt / 4)) * align.CFrame.Rotation
		end
		table.insert(ys, chassis.CFrame.Y - restY)
		table.insert(xs, chassis.CFrame.Position)
	end
	return ys, xs, restY
end

for _, fps in ipairs({ 60, 30 }) do
	local ys = run(0.3, fps, fps * 3, 0)
	local lo, hi = math.huge, -math.huge
	for i = math.floor(#ys * 0.5), #ys do
		lo, hi = math.min(lo, ys[i]), math.max(hi, ys[i])
	end
	local minAll = math.huge
	for _, y in ipairs(ys) do minAll = math.min(minAll, y) end
	-- bounce count: sign changes of velocity after first second
	local flips = 0
	for i = fps + 2, #ys do
		if (ys[i] - ys[i - 1]) * (ys[i - 1] - ys[i - 2]) < -1e-8 then flips += 1 end
	end
	print(string.format("drop 0.3 @%dfps: deepest %+.3f, settled range [%+.4f, %+.4f], direction flips after 1s: %d", fps, minAll, lo, hi, flips))
end
local _, xs = run(0, 60, 180, 1)
local speed = (xs[#xs] - xs[#xs - 1]).Magnitude * 60
print(string.format("full throttle 3s: travelled %.1f studs, speed %.1f studs/s (MaxSpeed %d)", (xs[#xs] - xs[1]).Magnitude, speed, Config.MaxSpeed))
