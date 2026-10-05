--[[
	LocustAnimator: procedural animation for THE LOCUST and its Nymphs (client side, no assets).

	Insect-like on purpose: a long stalking gait, arms that hang and then reach when it hunts,
	a head that snaps between poses instead of turning smoothly, twitching antennae-like
	mandibles, fluttering wings when it shrieks, a convulsing stun, and an emerge / leave pose.
	Footstep and clicking sounds are triggered from the gait so they match its legs.
	Only Locusts near the camera are animated (performance).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Audio = require(script.Parent.Audio)

local LocustAnimator = {}

local rigs: { [Model]: any } = {}
local player = Players.LocalPlayer

local function rad(d)
	return math.rad(d)
end

local function motors(model: Model)
	local out = {}
	for _, m in model:GetDescendants() do
		if m:IsA("Motor6D") then
			out[m.Name] = m
		end
	end
	return out
end

local function add(model: Instance)
	if not model:IsA("Model") or rigs[model] then
		return
	end
	if model.Name ~= "Locust" and model.Name ~= "Nymph" then
		return
	end
	task.defer(function()
		local root = model:WaitForChild("HumanoidRootPart", 5)
		if not root then
			return
		end
		task.wait(0.1)
		rigs[model] = {
			Model = model,
			Root = root,
			M = motors(model),
			Phase = 0,
			LastStep = 0,
			HeadTarget = CFrame.new(),
			HeadCurrent = CFrame.new(),
			NextTwitch = 0,
			Scale = model:GetAttribute("Scale") or 1,
			NextClick = os.clock() + math.random() * 3,
			Head = model:FindFirstChild("Head"),
		}
	end)
end

local function remove(model: Instance)
	rigs[model :: any] = nil
end

local function animate(rig, dt: number)
	local model = rig.Model
	local M = rig.M
	local root = rig.Root
	local now = os.clock()
	local vel = root.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local state = model:GetAttribute("State") or "Patrol"
	local hunting = state == "Chase"
	local s = rig.Scale

	-- gait
	local stride = 2.4 * s
	rig.Phase += dt * speed / stride * math.pi
	local p = rig.Phase
	local move = math.clamp(speed / 10, 0, 1)
	local swing = math.sin(p) * 26 * move
	local lift = math.max(0, math.cos(p)) * 30 * move
	local lift2 = math.max(0, -math.cos(p)) * 30 * move

	-- footsteps on each half cycle
	local stepIndex = math.floor(p / math.pi)
	if stepIndex ~= rig.LastStep and speed > 2 then
		rig.LastStep = stepIndex
		if rig.Head then
			Audio.Play("LocustStep", rig.Root, math.clamp(speed / 14, 0.35, 1.2) * (if s < 1 then 0.4 else 1), if s < 1 then 1.8 else 1)
		end
	end
	if now > rig.NextClick and rig.Head then
		rig.NextClick = now + math.random(25, 70) / 10
		Audio.Play("LocustClick", rig.Head, if s < 1 then 0.5 else 1)
	end

	local bob = math.abs(math.sin(p)) * 0.25 * move
	local hunch = if hunting then 12 else 0

	-- attack / special overlays
	local attackT = now - (model:GetAttribute("AttackLocal") or 0)
	local attackAttr = model:GetAttribute("Attack")
	if attackAttr and attackAttr ~= rig.LastAttack then
		rig.LastAttack = attackAttr
		rig.AttackStart = now
	end
	attackT = now - (rig.AttackStart or -10)
	local attack = if attackT < 0.45 then math.sin(attackT / 0.45 * math.pi) else 0

	local stunned = (model:GetAttribute("StunnedUntil") or 0) > Workspace:GetServerTimeNow()
	local shriek = now - (rig.ShriekStart or -10) < 2.4
	local shriekAttr = model:GetAttribute("Shriek")
	if shriekAttr and shriekAttr ~= rig.LastShriek then
		rig.LastShriek = shriekAttr
		rig.ShriekStart = now
	end
	local sniff = model:GetAttribute("Sniff")
	if sniff and sniff ~= rig.LastSniff then
		rig.LastSniff = sniff
		rig.SniffStart = now
	end
	local sniffing = now - (rig.SniffStart or -10) < 1.4
	local emerge = math.clamp((Workspace:GetServerTimeNow() - (model:GetAttribute("Emerge") or 0)) / 2.6, 0, 1)
	local leaving = state == "Leaving"

	-- head: snaps to new poses (insect twitch)
	if now > rig.NextTwitch then
		rig.NextTwitch = now + (if hunting then 0.12 + math.random() * 0.25 else 0.25 + math.random() * 1.1)
		local yaw = (math.random() - 0.5) * (if hunting then 18 else 60)
		local pitch = (math.random() - 0.5) * 24
		local roll = (math.random() - 0.5) * (if hunting then 10 else 35)
		rig.HeadTarget = CFrame.Angles(rad(pitch), rad(yaw), rad(roll))
	end
	if sniffing then
		rig.HeadTarget = CFrame.Angles(rad(-35 + math.sin(now * 30) * 6), rad(math.sin(now * 11) * 20), 0)
	end
	local snapSpeed = if hunting then 30 else 22
	rig.HeadCurrent = rig.HeadCurrent:Lerp(rig.HeadTarget, math.clamp(dt * snapSpeed, 0, 1))

	local tremble = 0
	if stunned then
		tremble = math.sin(now * 55) * 8
	end

	local function set(name, cf)
		local m = M[name]
		if m then
			m.Transform = cf
		end
	end

	-- whole body: emerge from a crouch, sink when leaving
	local crouch = (1 - emerge) * 45
	if leaving then
		crouch = math.min(60, (now - (rig.LeaveStart or now)) * 40)
		rig.LeaveStart = rig.LeaveStart or now
	end
	set("Waist", CFrame.new(0, -bob - crouch / 45 * 2, 0) * CFrame.Angles(rad(-hunch - crouch * 0.6 + tremble + attack * -18), rad(math.sin(p * 0.5) * 4 * move), rad(tremble * 0.5)))
	set("Neck", rig.HeadCurrent * CFrame.Angles(rad(hunch * 0.8 + attack * 10 + (if shriek then -30 else 0)), 0, 0))
	set("AbdomenJoint", CFrame.Angles(rad(math.sin(p) * 6 * move + math.sin(now * 2) * 3), rad(math.sin(p * 0.5) * 6), 0))
	set("AbdomenTipJoint", CFrame.Angles(rad(math.sin(now * 2.6) * 6), 0, 0))

	for _, side in { "L", "R" } do
		local sign = if side == "L" then 1 else -1
		local legSwing = swing * sign
		local legLift = if side == "L" then lift else lift2
		set("Hip" .. side, CFrame.Angles(rad(-legSwing - legLift * 0.4 + crouch * 0.8), 0, 0))
		set("Knee" .. side, CFrame.Angles(rad(legLift * 1.1 - crouch * 0.6), 0, 0))
		set("Ankle" .. side, CFrame.Angles(rad(-legLift * 0.5), 0, 0))
		-- arms: hang and sway; reach forward while hunting; slash on attack
		local reach = if hunting then -55 else -10
		local armSwing = -legSwing * 0.6
		set("Shoulder" .. side, CFrame.Angles(rad(reach + armSwing - attack * 95 + tremble), 0, rad(sign * (attack * 18 + (if shriek then 35 else 0)))))
		set("Elbow" .. side, CFrame.Angles(rad((if hunting then -25 else 10) + attack * 50 + math.sin(now * 3 + sign) * 4), 0, 0))
		set("Wrist" .. side, CFrame.Angles(rad(math.sin(now * 9 + sign) * 8), 0, 0))
		set("SmallShoulder" .. side, CFrame.Angles(rad(math.sin(now * 7 + sign * 2) * 10 + attack * -40), 0, 0))
		set("SmallElbow" .. side, CFrame.Angles(rad(math.sin(now * 13 + sign) * 12), 0, 0))
		local flutter = if shriek then math.sin(now * 60) * 25 else math.sin(now * 1.3 + sign) * 2
		set("WingJoint" .. side, CFrame.Angles(0, 0, rad(sign * (flutter + (if shriek then 30 else 0)))))
	end

	-- fade out when leaving
	if leaving then
		local f = math.clamp((now - rig.LeaveStart) / 2, 0, 1)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
				d.LocalTransparencyModifier = f
			end
		end
	end
end

function LocustAnimator.Init()
	local function watch(folder: Instance)
		for _, c in folder:GetChildren() do
			add(c)
		end
		folder.ChildAdded:Connect(add)
		folder.ChildRemoved:Connect(remove)
	end
	task.spawn(function()
		local store = Workspace:WaitForChild("Store", 60)
		if store then
			watch(store:WaitForChild("Dynamic"))
		end
	end)
	RunService.Stepped:Connect(function(_, dt)
		local cam = Workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position or Vector3.zero
		for model, rig in rigs do
			if not model.Parent then
				rigs[model] = nil
			elseif (rig.Root.Position - camPos).Magnitude < 320 then
				local ok = pcall(animate, rig, dt)
				if not ok then
					rigs[model] = nil
				end
			end
		end
	end)
end

-- used by the 3D menu scene (a local Locust model)
function LocustAnimator.Track(model: Model)
	add(model)
end

return LocustAnimator
