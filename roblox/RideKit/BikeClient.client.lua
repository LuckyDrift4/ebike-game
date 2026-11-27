-- RideKit.BikeClient (Script, RunContext = Client). Runs on every player's
-- machine for this bike:
--   * the rider's machine runs the physics (RideKit.Physics) and shows the HUD
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

local STUD_M = 0.28 -- metres per stud (Roblox avatar scale); studs/s x 1.008 = km/h

local CRASH_TEXT = {
	loop = "Looped it!",
	lowside = "Lost the front!",
	hit = "Hit something!",
	endo = "Over the bars!",
	flip = "Flipped it!",
}

-- rider HUD: speed, wheelie / stoppie timer with the balance bar, messages ---------------------
local function makeHud(player: Player)
	local gui = Instance.new("ScreenGui")
	gui.Name = "RideKit_HUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local function label(parent, text, size, font, color, anchor, pos, dims)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Text = text
		l.TextSize = size
		l.Font = font
		l.TextColor3 = color or Color3.new(1, 1, 1)
		l.AnchorPoint = anchor or Vector2.zero
		l.Position = pos or UDim2.new()
		l.Size = dims or UDim2.new(1, 0, 0, size)
		l.Parent = parent
		return l
	end
	local function panel(name, anchor, pos, size)
		local f = Instance.new("Frame")
		f.Name = name
		f.AnchorPoint = anchor
		f.Position = pos
		f.Size = size
		f.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
		f.BackgroundTransparency = 0.3
		f.BorderSizePixel = 0
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 12)
		c.Parent = f
		f.Parent = gui
		return f
	end
	local function bar(parent, color, x, w, y, h)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = color
		f.Position = UDim2.new(x, 0, 0, y)
		f.Size = UDim2.new(w, 0, 0, h)
		f.Parent = parent
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, math.floor(h / 2))
		c.Parent = f
		return f
	end

	-- speed, bottom right
	local sp = panel("Speed", Vector2.new(1, 1), UDim2.new(1, -20, 1, -20), UDim2.fromOffset(160, 84))
	local speed = label(sp, "0", 46, Enum.Font.GothamBlack, nil, Vector2.new(1, 0), UDim2.new(1, -14, 0, 6), UDim2.new(1, -28, 0, 46))
	speed.TextXAlignment = Enum.TextXAlignment.Right
	local unit = label(sp, "KM/H", 13, Enum.Font.GothamBold, Color3.fromRGB(160, 168, 180), Vector2.new(1, 0), UDim2.new(1, -14, 0, 52), UDim2.new(1, -28, 0, 13))
	unit.TextXAlignment = Enum.TextXAlignment.Right
	local powerTrack = bar(sp, Color3.fromRGB(45, 50, 58), 0.08, 0.84, 72, 5)
	local power = bar(powerTrack, Color3.fromRGB(80, 220, 120), 0, 0, 0, 5)

	-- wheelie / stoppie, top centre
	local tr = panel("Trick", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 64), UDim2.fromOffset(320, 104))
	tr.Visible = false
	local title = label(tr, "WHEELIE", 14, Enum.Font.GothamBold, Color3.fromRGB(255, 200, 70), nil, UDim2.fromOffset(0, 8))
	local timeL = label(tr, "0.0 s", 30, Enum.Font.GothamBlack, nil, nil, UDim2.fromOffset(0, 24))
	local track = bar(tr, Color3.fromRGB(45, 50, 58), 0.06, 0.88, 64, 10)
	local sweet = bar(track, Color3.fromRGB(70, 200, 110), 0.6, 0.2, 0, 10)
	local over = bar(track, Color3.fromRGB(230, 70, 60), 1 / 1.2, 1 - 1 / 1.2, 0, 10)
	local marker = bar(track, Color3.new(1, 1, 1), 0, 0, -4, 18)
	marker.Size = UDim2.fromOffset(4, 18)
	marker.AnchorPoint = Vector2.new(0.5, 0)
	local best = label(tr, "", 12, Enum.Font.GothamBold, Color3.fromRGB(160, 168, 180), nil, UDim2.fromOffset(0, 82))

	-- big message, middle
	local msg = label(gui, "", 44, Enum.Font.GothamBlack, nil, Vector2.new(0.5, 0.5), UDim2.new(0.5, 0, 0.35, 0), UDim2.new(1, 0, 0, 50))
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = msg
	msg.TextTransparency = 1
	stroke.Transparency = 1

	-- controls, bottom centre (fades out)
	local hintText = if game:GetService("UserInputService").TouchEnabled
		then "Wheelie / Stoppie buttons · stick to ride · Jump to get off"
		else "W / S  throttle · brake     A / D  steer     E  wheelie     Q  stoppie / stand     Space  get off"
	local hint = label(gui, hintText, 14, Enum.Font.GothamBold, nil, Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -22), UDim2.new(0.9, 0, 0, 16))
	local hintStroke = Instance.new("UIStroke")
	hintStroke.Thickness = 1.5
	hintStroke.Parent = hint

	gui.Parent = player:WaitForChild("PlayerGui")

	local hud = { gui = gui, bestW = 0, bestS = 0, hintT = 8, shownT = 0, kind = nil, t = 0, dist = 0 }
	function hud:message(text)
		local TweenService = game:GetService("TweenService")
		msg.Text = text
		msg.TextTransparency = 0
		stroke.Transparency = 0
		local fade = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 1.6)
		TweenService:Create(msg, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
	end
	-- off the bike: hide the gauges now, keep a crash message up for a moment
	function hud:close(linger: boolean)
		sp.Visible = false
		tr.Visible = false
		hint.Visible = false
		if linger then
			task.delay(2.4, function()
				gui:Destroy()
			end)
		else
			gui:Destroy()
		end
	end
	function hud:update(dt, out, throttle, brake)
		speed.Text = tostring(math.floor(math.abs(out.speed) * 1.008 + 0.5))
		local p = if brake > 0 then -brake else throttle
		power.Size = UDim2.new(math.abs(p), 0, 1, 0)
		power.BackgroundColor3 = if p < 0 then Color3.fromRGB(235, 80, 70) else Color3.fromRGB(80, 220, 120)

		-- trick timer
		local kind = if out.wheelie then "wheelie" elseif out.stoppie then "stoppie" else nil
		if kind then
			if self.kind ~= kind then
				self.kind, self.t, self.dist = kind, 0, 0
			end
			self.t += dt
			self.dist += math.abs(out.speed) * dt * STUD_M
			self.shownT = 2
		elseif self.kind then
			-- just ended: keep the result up for a moment, record the best
			if self.kind == "wheelie" and self.t > self.bestW then
				self.bestW = self.t
				if self.t > 1.5 then
					self:message(string.format("Best wheelie! %.1f s", self.t))
				end
			elseif self.kind == "stoppie" and self.t > self.bestS then
				self.bestS = self.t
			end
			self.kind = nil
		end
		self.shownT -= dt
		tr.Visible = self.shownT > 0 and self.t > 0.25
		if tr.Visible then
			local isW = (kind or self.lastKind) ~= "stoppie"
			title.Text = if isW then "WHEELIE" else "STOPPIE"
			timeL.Text = string.format("%.1f s  ·  %d m", self.t, math.floor(self.dist + 0.5))
			local bestT = if isW then self.bestW else self.bestS
			best.Text = if bestT > 0 then string.format("BEST  %.1f s", bestT) else ""
			-- balance bar: 0 = flat, 1/1.2 = the balance point, red = past it
			local f
			if isW then
				local bal = math.max(out.balanceAngle, 0.2)
				f = out.wheelieAngle / bal
				sweet.Position = UDim2.new((bal - math.rad(Config.WheelieSweetSpot + 6)) / bal / 1.2, 0, 0, 0)
				sweet.Size = UDim2.new(math.rad(Config.WheelieSweetSpot + 5) / bal / 1.2, 0, 1, 0)
			else
				f = out.stoppieAngle / math.rad(Config.StoppieAngle)
				sweet.Position = UDim2.new(0.6, 0, 0, 0)
				sweet.Size = UDim2.new(0.25, 0, 1, 0)
			end
			marker.Position = UDim2.new(math.clamp(f / 1.2, 0, 1), 0, 0, -4)
			marker.BackgroundColor3 = if f > 1 then Color3.fromRGB(255, 90, 80) else Color3.new(1, 1, 1)
		end
		if kind then
			self.lastKind = kind
		end

		-- controls hint fades out
		self.hintT -= dt
		local h = math.clamp(self.hintT / 1.5, 0, 1)
		hint.TextTransparency = 1 - h
		hintStroke.Transparency = 1 - h * 0.6
	end
	return hud
end

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

	-- E = wheelie / lean back, Q = stoppie / stand up (keyboard, gamepad, mobile buttons)
	local leanBack, leanForward = 0, 0
	local id = bike.Name .. "_" .. tostring(math.random(1, 1e9))
	local ACT_BACK, ACT_FWD = "RideKitWheelie_" .. id, "RideKitStoppie_" .. id
	local function onBack(_, state)
		leanBack = if state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change then 1 else 0
		return Enum.ContextActionResult.Sink
	end
	local function onFwd(_, state)
		leanForward = if state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change then 1 else 0
		return Enum.ContextActionResult.Sink
	end

	local wasDriver = false
	local hud = nil
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
			ContextActionService:BindActionAtPriority(ACT_FWD, onFwd, true, prio, table.unpack(Config.StoppieKeys))
			ContextActionService:SetTitle(ACT_BACK, "Wheelie")
			ContextActionService:SetTitle(ACT_FWD, "Stoppie")
			ContextActionService:SetPosition(ACT_BACK, UDim2.new(1, -190, 1, -95))
			ContextActionService:SetPosition(ACT_FWD, UDim2.new(1, -190, 1, -165))
		else
			ContextActionService:UnbindAction(ACT_BACK)
			ContextActionService:UnbindAction(ACT_FWD)
			leanBack, leanForward = 0, 0
		end
	end

	-- thrown off: the rider keeps the bike's speed and tumbles; the bike falls over
	local function crashOff(char: Model, reason: string?)
		crashSent = true
		if remote then
			remote:FireServer("crash")
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local v = chassis.AssemblyLinearVelocity
		if hud then
			hud:message(CRASH_TEXT[reason or ""] or "Crashed!")
		end
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
			if hud then
				hud:close(false)
			end
			return
		end
		local occupant = seat.Occupant
		local char = occupant and occupant.Parent
		local isDriver = char ~= nil and char == player.Character

		-- the driver role: controls, HUD, fresh physics state
		if isDriver ~= wasDriver then
			wasDriver = isDriver
			physics:reset()
			bind(isDriver)
			if hud then
				hud:close(crashSent)
				hud = nil
			end
			crashSent = false
			if isDriver and Config.ShowHud then
				hud = makeHud(player)
			end
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
				leanForward = leanForward,
			})
			if out.crashed and not crashSent and char then
				crashOff(char, out.crashReason)
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

		if hud and out then
			hud:update(dt, out, throttle, brake)
		end

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
			-- what the bike is doing: from the physics for the rider, from the bike for everyone else
			local lean, wheelie, stoppie, airborne, standing
			if out then
				lean = out.lean
				wheelie = if out.wheelie then math.clamp(out.wheelieAngle / math.max(out.balanceAngle, 0.3) * 1.2, 0, 1) else 0
				stoppie = if out.stoppie then math.clamp(out.stoppieAngle / math.rad(Config.StoppieAngle), 0, 1) else 0
				airborne = out.airborne and out.airTime > 0.08
				standing = out.standing and math.abs(vF) > 3
			else
				local up = cf.UpVector
				local flatFwd = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
				local flatRight = if flatFwd.Magnitude > 0.05 then flatFwd.Unit:Cross(Vector3.yAxis) else cf.RightVector
				lean = math.atan2(up:Dot(flatRight), up.Y)
				local pitch = math.asin(math.clamp(cf.LookVector.Y, -1, 1))
				wheelie = if hitR and not hitF then math.clamp((pitch - 0.08) / 0.6, 0, 1) else 0
				stoppie = if hitF and not hitR then math.clamp((-pitch - 0.05) / 0.3, 0, 1) else 0
				airborne = not hitF and not hitR
				standing = false
			end
			local moving = math.abs(vF) > 2
			local maxLean = math.rad(Config.MaxLean)
			local target = {
				tuck = if wheelie > 0.1 then 0 else throttle * math.clamp(math.abs(vF) / 40, 0.25, 1),
				brake = if braking and stoppie < 0.1 then brake else 0,
				stand = if airborne or standing then 1 else 0,
				hangR = if moving then math.clamp(lean / maxLean, 0, 1) else 0,
				hangL = if moving then math.clamp(-lean / maxLean, 0, 1) else 0,
				leanR = math.clamp(steerVis / clipSteer, 0, 1),
				leanL = math.clamp(-steerVis / clipSteer, 0, 1),
				wheelie = wheelie,
				stoppie = stoppie,
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
