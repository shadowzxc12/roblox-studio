--[[
	CharacterAnimator: custom procedural animation for every player character (R15 and R6).
	The default Animate script is replaced (StarterCharacterScripts.Animate is empty), and this
	drives Motor6D.Transform every frame, on every client, for every nearby character:

	  idle      breathing, weight shift, looking around
	  walk/run  stride matched to the real ground speed (no foot sliding), arm swing, lean,
	            bob; sprint = longer stride + forward lean; backwards walking plays in reverse
	  crouch    low sneak with bent knees
	  jump/fall tuck on take-off, arms out while falling, a springy landing squash
	  climb / swim / sit / downed (crawl) / dead / hidden
	  holding   Aim (flashlight), Melee (hammer...), TwoHand (planks, kits), OneHand (food),
	            Push (shopping cart) — the upper body blends over the legs
	  actions   Swing, Eat, Drink, Heal, Throw, Place, Reload, Click, Build, Pickup, Revive
	            (character attributes Action / ActionN, set by the server)
	Emotes (Animator tracks) still play: while a track is playing the animator steps aside.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Holding = require(Shared.Holding)

local CharacterAnimator = {}

local rigs: { [Model]: any } = {}
local player = Players.LocalPlayer
local MAX_DIST = 220

local R6_NAMES = {
	RootJoint = "Root",
	["Right Shoulder"] = "RightShoulder",
	["Left Shoulder"] = "LeftShoulder",
	["Right Hip"] = "RightHip",
	["Left Hip"] = "LeftHip",
	Neck = "Neck",
}
local R15_NAMES = {
	Root = true,
	Waist = true,
	Neck = true,
	RightShoulder = true,
	RightElbow = true,
	RightWrist = true,
	LeftShoulder = true,
	LeftElbow = true,
	LeftWrist = true,
	RightHip = true,
	RightKnee = true,
	RightAnkle = true,
	LeftHip = true,
	LeftKnee = true,
	LeftAnkle = true,
}

local sin, cos, rad, clamp, exp = math.sin, math.cos, math.rad, math.clamp, math.exp
local TAU = math.pi * 2

local function A(x, y, z)
	return CFrame.Angles(x or 0, y or 0, z or 0)
end

--============================ RIG ============================--
local function collect(rec)
	table.clear(rec.M)
	for _, m in rec.Char:GetDescendants() do
		if m:IsA("Motor6D") then
			local logical = if rec.R6 then R6_NAMES[m.Name] else (if R15_NAMES[m.Name] then m.Name else nil)
			if logical then
				local rot = m.C0.Rotation
				rec.M[logical] = { Motor = m, Rot = rot, Inv = rot:Inverse(), Cur = CFrame.new() }
			end
		end
	end
end

local function add(char: Model)
	if rigs[char] then
		return
	end
	task.defer(function()
		local hum = char:WaitForChild("Humanoid", 8) :: Humanoid?
		local root = char:WaitForChild("HumanoidRootPart", 8) :: BasePart?
		if not hum or not root then
			return
		end
		local rec = {
			Char = char,
			Hum = hum,
			Root = root,
			Player = Players:GetPlayerFromCharacter(char),
			R6 = hum.RigType == Enum.HumanoidRigType.R6,
			M = {},
			Phase = 0,
			Speed = 0,
			LastPos = root.Position,
			Air = 0,
			LandT = -10,
			Land = 0,
			ActionN = char:GetAttribute("ActionN") or 0,
			Action = nil,
			ActionT = -10,
			Seed = math.random() * 100,
			LookYaw = 0,
			NextLook = 0,
			LookTarget = 0,
			Ground = true,
			NextRay = 0,
		}
		collect(rec)
		char.DescendantAdded:Connect(function(d)
			if d:IsA("Motor6D") then
				collect(rec)
			end
		end)
		char:GetAttributeChangedSignal("ActionN"):Connect(function()
			local n = char:GetAttribute("ActionN") or 0
			if n ~= rec.ActionN then
				rec.ActionN = n
				rec.Action = char:GetAttribute("Action")
				rec.ActionT = os.clock()
			end
		end)
		rigs[char] = rec
	end)
end

-- play an action locally right away (the local player's own input; the server echo is ignored)
function CharacterAnimator.PlayLocal(action: string)
	local char = player.Character
	local rec = char and rigs[char]
	if rec then
		rec.Action = action
		rec.ActionT = os.clock()
	end
end

--============================ POSES ============================--
-- every pose is a table of joint -> CFrame in the joint's parent space
-- (X rotation > 0 swings a limb forward, Z > 0 lifts the right arm sideways)

local function attr(rec, name: string)
	local p = rec.Player
	return p and p:GetAttribute(name)
end

local function heldKind(rec): string?
	if (attr(rec, "CartId") or 0) ~= 0 then
		return "Push"
	end
	local held = attr(rec, "HeldItem")
	if type(held) == "string" and held ~= "" then
		return Holding.Kind(held)
	end
	local model = rec.Char:FindFirstChild("HeldItem")
	if model then
		return Holding.Kind(model:GetAttribute("ItemId"))
	end
	return nil
end

local function onGround(rec, now: number): boolean
	if rec.Player == player then
		local fm = rec.Hum.FloorMaterial
		return fm ~= Enum.Material.Air
	end
	-- other players: FloorMaterial isn't replicated; a short ray every few frames
	if now >= rec.NextRay then
		rec.NextRay = now + 0.08
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { rec.Char }
		local hip = rec.Hum.HipHeight + rec.Root.Size.Y / 2
		local hit = Workspace:Raycast(rec.Root.Position, Vector3.new(0, -(hip + 1.2), 0), params)
		rec.Ground = hit ~= nil
	end
	return rec.Ground
end

local function step(rec, dt: number, now: number)
	local root, hum = rec.Root, rec.Hum
	local M = rec.M
	if not M.RightHip and not M.LeftHip then
		return
	end
	-- emotes / animation tracks win
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then
		local ok, tracks = pcall(function()
			return animator:GetPlayingAnimationTracks()
		end)
		if ok and tracks and #tracks > 0 then
			for _, j in M do
				j.Cur = CFrame.new()
			end
			return
		end
	end

	-- movement from real position change (works for anchored / teleported / remote characters)
	local pos = root.Position
	local delta = (pos - rec.LastPos)
	rec.LastPos = pos
	if dt <= 0 then
		return
	end
	local vel = delta / dt
	if vel.Magnitude > 120 then
		vel = Vector3.zero -- teleport
	end
	local flat = Vector3.new(vel.X, 0, vel.Z)
	local speed = flat.Magnitude
	rec.Speed += (speed - rec.Speed) * clamp(dt * 10, 0, 1)
	local look = root.CFrame.LookVector
	local forward = if speed > 0.5 then flat.Unit:Dot(Vector3.new(look.X, 0, look.Z).Unit) else 1
	local side = if speed > 0.5 then flat.Unit:Dot(root.CFrame.RightVector) else 0

	local state = hum:GetState()
	local grounded = onGround(rec, now)
	local downed = attr(rec, "Downed") == true
	local dead = attr(rec, "Dead") == true or state == Enum.HumanoidStateType.Dead
	local crouch = attr(rec, "Crouching") == true
	local sprint = attr(rec, "Sprinting") == true or rec.Speed > 18.5
	local hidden = attr(rec, "Hidden") == true
	local climbing = state == Enum.HumanoidStateType.Climbing
	local swimming = state == Enum.HumanoidStateType.Swimming
	local seated = hum.Sit or state == Enum.HumanoidStateType.Seated

	if grounded then
		if rec.Air > 0.25 then
			rec.LandT = now
			rec.Land = clamp(rec.Air * 0.9, 0.25, 1)
		end
		rec.Air = 0
	else
		rec.Air += dt
	end
	local airborne = rec.Air > 0.12 and not climbing and not swimming
	local rising = vel.Y > 2

	-- stride: one full cycle per ~2 stride lengths travelled
	local stride = if sprint then 7.2 elseif crouch then 3.4 else 5.2
	local moving = clamp((rec.Speed - 0.6) / 4, 0, 1)
	local dir = if forward < -0.3 then -1 else 1
	rec.Phase = (rec.Phase + dir * rec.Speed * dt / stride) % 1
	local ph = rec.Phase * TAU
	local s1, c1 = sin(ph), cos(ph)
	local bob = math.abs(sin(ph)) -- two bobs per cycle

	local amp = (if sprint then 1.0 elseif crouch then 0.55 else 0.62) * moving
	local P = {}
	local t = now + rec.Seed

	------------------------------------------------ locomotion (legs + torso)
	local breathe = sin(t * 1.7) * (1 - moving)
	local lean = -(if sprint then 0.2 elseif crouch then 0.32 else 0.06) * moving - (if crouch then 0.18 else 0)
	local rootY = -bob * (if sprint then 0.32 else 0.18) * moving
	if crouch then
		rootY -= 0.95
	end
	local sway = sin(t * 0.55) * 0.05 * (1 - moving)
	P.Root = CFrame.new(sway * 2, rootY, 0) * A(lean * 0.5, side * -0.12 * moving, sin(ph) * 0.05 * moving + sway)
	P.Waist = A(lean * 0.6 + breathe * 0.02, -s1 * 0.12 * amp, 0)
	local hipBase = if crouch then 0.75 else 0
	local kneeBase = if crouch then -1.25 else -0.06
	P.RightHip = A(hipBase + s1 * amp * 0.85, 0, side * 0.08)
	P.LeftHip = A(hipBase - s1 * amp * 0.85, 0, side * 0.08)
	-- knee bends on the back-swing / lift
	P.RightKnee = A(kneeBase - math.max(0, -c1) * amp * 1.25, 0, 0)
	P.LeftKnee = A(kneeBase - math.max(0, c1) * amp * 1.25, 0, 0)
	P.RightAnkle = A((if crouch then 0.45 else 0) + math.max(0, c1) * amp * 0.35, 0, 0)
	P.LeftAnkle = A((if crouch then 0.45 else 0) + math.max(0, -c1) * amp * 0.35, 0, 0)
	-- arms swing opposite to legs
	local armAmp = amp * (if sprint then 1.15 else 0.75)
	P.RightShoulder = A(-s1 * armAmp + breathe * 0.02, 0, 0.06 + sway)
	P.LeftShoulder = A(s1 * armAmp + breathe * 0.02, 0, -0.06 + sway)
	P.RightElbow = A(0.15 + (if sprint then 1.25 else 0.35) * moving + math.max(0, s1) * 0.4 * amp, 0, 0)
	P.LeftElbow = A(0.15 + (if sprint then 1.25 else 0.35) * moving + math.max(0, -s1) * 0.4 * amp, 0, 0)
	P.RightWrist = A(0, 0, 0)
	P.LeftWrist = A(0, 0, 0)

	-- idle look-around (not for the local first-person player)
	if now > rec.NextLook then
		rec.NextLook = now + 2 + math.random() * 4
		rec.LookTarget = (math.random() - 0.5) * (if moving > 0.5 then 0.3 else 1.1)
	end
	rec.LookYaw += (rec.LookTarget - rec.LookYaw) * clamp(dt * 3, 0, 1)
	P.Neck = A(-lean * 0.4 + breathe * 0.02, rec.LookYaw * (1 - moving * 0.6), 0)

	------------------------------------------------ air
	if airborne then
		local fall = clamp(-vel.Y / 60, 0, 1)
		if rising then
			P.RightHip = A(0.75, 0, 0.05)
			P.LeftHip = A(-0.15, 0, -0.05)
			P.RightKnee = A(-1.3)
			P.LeftKnee = A(-0.5)
			P.RightShoulder = A(0.5, 0, 0.35)
			P.LeftShoulder = A(-0.4, 0, -0.35)
			P.RightElbow = A(0.8)
			P.LeftElbow = A(0.6)
		else
			local f = sin(t * 9) * 0.15 * fall
			P.RightHip = A(0.35 + f, 0, 0.12)
			P.LeftHip = A(0.1 - f, 0, -0.12)
			P.RightKnee = A(-0.7)
			P.LeftKnee = A(-0.35)
			P.RightShoulder = A(0.3 + f, 0, 0.9 + fall * 0.6)
			P.LeftShoulder = A(0.3 - f, 0, -0.9 - fall * 0.6)
			P.RightElbow = A(0.4)
			P.LeftElbow = A(0.4)
		end
		P.Waist = A(-0.08, 0, 0)
		P.Root = CFrame.new(0, 0, 0) * A(-0.05, 0, 0)
	end

	------------------------------------------------ landing squash
	local sinceLand = now - rec.LandT
	if sinceLand < 0.45 and not airborne then
		local k = exp(-sinceLand * 9) * rec.Land
		P.Root = CFrame.new(0, -1.1 * k, 0) * P.Root
		P.RightHip = A(0.9 * k) * P.RightHip
		P.LeftHip = A(0.9 * k) * P.LeftHip
		P.RightKnee = A(-1.6 * k) * P.RightKnee
		P.LeftKnee = A(-1.6 * k) * P.LeftKnee
		P.RightAnkle = A(0.7 * k) * P.RightAnkle
		P.LeftAnkle = A(0.7 * k) * P.LeftAnkle
		P.Waist = A(-0.35 * k) * P.Waist
	end

	------------------------------------------------ special states
	if climbing then
		local c = sin(now * 7) * clamp(math.abs(vel.Y) / 8, 0, 1)
		P.RightShoulder = A(2.6 + c * 0.4, 0, 0.1)
		P.LeftShoulder = A(2.6 - c * 0.4, 0, -0.1)
		P.RightElbow = A(0.6)
		P.LeftElbow = A(0.6)
		P.RightHip = A(0.6 - c * 0.5)
		P.LeftHip = A(0.6 + c * 0.5)
		P.RightKnee = A(-1.1)
		P.LeftKnee = A(-1.1)
	elseif swimming then
		local c = sin(now * 5)
		P.Root = A(-1.2, 0, 0)
		P.RightShoulder = A(2.4 + c * 0.8, 0, 0.4)
		P.LeftShoulder = A(2.4 - c * 0.8, 0, -0.4)
		P.RightHip = A(c * 0.4)
		P.LeftHip = A(-c * 0.4)
	elseif seated then
		P.Root = CFrame.new()
		P.RightHip = A(1.55)
		P.LeftHip = A(1.55)
		P.RightKnee = A(-1.55)
		P.LeftKnee = A(-1.55)
		P.RightShoulder = A(0.35, 0, 0.08)
		P.LeftShoulder = A(0.35, 0, -0.08)
	elseif hidden then
		P.Root = CFrame.new(0, -1.2, 0) * A(-0.2, 0, 0)
		P.RightHip = A(1.2)
		P.LeftHip = A(1.2)
		P.RightKnee = A(-2)
		P.LeftKnee = A(-2)
		P.RightShoulder = A(0.9, 0, -0.3)
		P.LeftShoulder = A(0.9, 0, 0.3)
		P.RightElbow = A(1.6)
		P.LeftElbow = A(1.6)
		P.Neck = A(-0.3)
	end
	if downed or dead then
		-- crawling on the floor, reaching forward
		local c = if dead then 0 else sin(now * 4) * clamp(rec.Speed / 4, 0, 1)
		P.Root = CFrame.new(0, -2.1, 0.6) * A(-1.45, 0, if dead then 0.2 else 0)
		P.Waist = A(0.15)
		P.Neck = A(if dead then -0.2 else 0.7)
		P.RightShoulder = A(2.5 + c * 0.6, 0, 0.3)
		P.LeftShoulder = A(2.5 - c * 0.6, 0, -0.3)
		P.RightElbow = A(0.5 + math.max(0, c))
		P.LeftElbow = A(0.5 + math.max(0, -c))
		P.RightHip = A(-0.1 + c * 0.3, 0, 0.1)
		P.LeftHip = A(-0.1 - c * 0.3, 0, -0.1)
		P.RightKnee = A(-0.3 - math.max(0, c) * 0.6)
		P.LeftKnee = A(-0.3 - math.max(0, -c) * 0.6)
	end

	------------------------------------------------ holding (upper body)
	local kind = if downed or dead or hidden or climbing or swimming then nil else heldKind(rec)
	if kind then
		local walkSway = s1 * 0.08 * moving
		local bounce = bob * 0.05 * moving
		if kind == "Aim" then
			P.RightShoulder = A(1.35 + bounce, 0.05, -0.12)
			P.RightElbow = A(0.25)
			P.RightWrist = A(0.05)
			P.LeftShoulder = A(s1 * 0.35 * amp + 0.05, 0, -0.06)
		elseif kind == "Melee" then
			P.RightShoulder = A(0.55 + walkSway + bounce, 0, 0.12)
			P.RightElbow = A(1.35)
			P.RightWrist = A(-0.1)
			P.LeftShoulder = A(s1 * 0.4 * amp, 0, -0.06)
		elseif kind == "OneHand" then
			P.RightShoulder = A(0.45 + walkSway + bounce, 0, 0.1)
			P.RightElbow = A(1.35)
		elseif kind == "TwoHand" then
			P.RightShoulder = A(0.75 + bounce, -0.25, 0.08)
			P.LeftShoulder = A(0.75 + bounce, 0.25, -0.08)
			P.RightElbow = A(0.95)
			P.LeftElbow = A(0.95)
			P.Waist = A(0.06) * P.Waist
		elseif kind == "Push" then
			P.RightShoulder = A(1.25 + bounce, -0.12, 0)
			P.LeftShoulder = A(1.25 + bounce, 0.12, 0)
			P.RightElbow = A(0.35)
			P.LeftElbow = A(0.35)
			P.Waist = A(-0.12) * P.Waist
		end
	end

	------------------------------------------------ actions
	local action = rec.Action
	local length = action and Holding.ActionTime[action]
	if action and length then
		local k = (now - rec.ActionT) / length
		if k >= 1 or k < 0 then
			rec.Action = nil
		else
			local env = sin(k * math.pi) -- 0 -> 1 -> 0
			if action == "Swing" or action == "Build" then
				-- wind up, strike, recover
				local wind = clamp(k / 0.35, 0, 1)
				local strike = clamp((k - 0.35) / 0.2, 0, 1)
				local raise = 2.5 * wind - 2.1 * strike
				P.RightShoulder = A(0.55 + raise * (1 - clamp((k - 0.7) / 0.3, 0, 1)), 0, 0.15)
				P.RightElbow = A(1.35 + 0.6 * wind - 1.0 * strike)
				P.Waist = A(-0.25 * strike * env, -0.35 * wind + 0.6 * strike, 0) * P.Waist
			elseif action == "Eat" or action == "Drink" then
				local nib = sin(k * 22) * 0.08
				P.RightShoulder = A(0.4 + 0.8 * env, -0.35 * env, 0.1)
				P.RightElbow = A(1.35 + 1.05 * env + nib)
				if action == "Drink" then
					P.Neck = A(0.45 * env)
				end
			elseif action == "Heal" then
				P.RightShoulder = A(0.5 + 0.4 * env, -0.5 * env, 0)
				P.LeftShoulder = A(0.5 + 0.4 * env, 0.5 * env, 0)
				P.RightElbow = A(1.6)
				P.LeftElbow = A(1.6)
				P.Neck = A(-0.4 * env)
			elseif action == "Throw" then
				local back = clamp(k / 0.45, 0, 1)
				local fwd = clamp((k - 0.45) / 0.2, 0, 1)
				P.RightShoulder = A(1.2 + 1.8 * back - 2.2 * fwd, 0, 0.25)
				P.RightElbow = A(1.4 * back * (1 - fwd))
				P.Waist = A(0, -0.4 * back + 0.7 * fwd, 0) * P.Waist
			elseif action == "Place" or action == "Pickup" or action == "Revive" then
				P.Root = CFrame.new(0, -1.3 * env, 0) * P.Root
				P.Waist = A(-0.6 * env) * P.Waist
				P.RightHip = A(1.0 * env) * P.RightHip
				P.LeftHip = A(1.0 * env) * P.LeftHip
				P.RightKnee = A(-1.6 * env) * P.RightKnee
				P.LeftKnee = A(-1.6 * env) * P.LeftKnee
				P.RightShoulder = A(0.4 + 0.9 * env, 0, 0.05)
				P.RightElbow = A(0.3)
				if action == "Revive" then
					P.LeftShoulder = A(0.4 + 0.9 * env, 0, -0.05)
				end
			elseif action == "Reload" then
				P.LeftShoulder = A(0.7 * env, 0.4 * env, 0)
				P.LeftElbow = A(1.5 * env)
				P.RightShoulder = A(0.6 + 0.3 * env, -0.2 * env, 0)
				P.RightElbow = A(1.3)
				P.Neck = A(-0.35 * env)
			elseif action == "Click" then
				P.RightWrist = A(0.3 * env) * (P.RightWrist or CFrame.new())
			end
		end
	end

	------------------------------------------------ apply (smoothed)
	local alpha = clamp(dt * (if airborne then 10 else 14), 0, 1)
	for name, j in M do
		local target = P[name]
		if not target then
			-- R6 has no elbows/knees: nothing to do; missing R15 joints rest
			target = CFrame.new()
		end
		j.Cur = j.Cur:Lerp(target, alpha)
		-- rotate in the parent's frame: conjugate by the joint's C0 rotation (R6 joints are turned)
		j.Motor.Transform = j.Inv * j.Cur * j.Rot
	end
end

function CharacterAnimator.Init()
	local function hookPlayer(p: Player)
		if p.Character then
			add(p.Character)
		end
		p.CharacterAdded:Connect(add)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	for _, p in Players:GetPlayers() do
		hookPlayer(p)
	end
	RunService.Stepped:Connect(function(_, dt)
		local now = os.clock()
		local cam = Workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position or Vector3.zero
		for char, rec in rigs do
			if not char.Parent then
				rigs[char] = nil
			elseif (rec.Root.Position - camPos).Magnitude < MAX_DIST then
				local ok, err = pcall(step, rec, dt, now)
				if not ok then
					warn("[CharacterAnimator] " .. tostring(err))
					rigs[char] = nil
				end
			end
		end
	end)
end

return CharacterAnimator
