--[[
	ViewModel: first-person camera + your arms and the item in your hands.

	The store is played in first person (LockFirstPerson while you're alive in a run). You see
	two arms (your skin colour, sleeves in your outfit colour) holding the selected item with
	the same grip numbers the third-person model uses (Shared/Holding):
	  Aim      flashlight pointed where you look (the lens glows when it's on)
	  Melee    hammer / crowbar / baton held up at your side
	  OneHand  food, batteries, cards in front of you
	  TwoHand  planks, sheets, kits carried with both hands
	  Push     both hands on the cart handle
	Layers on top: equip (raise from below), walk / sprint bob, mouse sway with spring lag,
	jump / land kick, crouch dip, idle breathing and the use actions (swing, eat, drink, heal,
	throw, place, reload, click).
	Open windows (inventory, map, menus) unlock the mouse with a Modal button.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Holding = require(Shared.Holding)
local Items = require(Shared.Items)
local Models = require(Shared.Models)

local UI = require(script.Parent.UI)
local ClientState = require(script.Parent.ClientState)

local ViewModel = {}

local player = Players.LocalPlayer
local sin, cos, rad, clamp, exp = math.sin, math.cos, math.rad, math.clamp, math.exp

local GRIP = CFrame.new(0, -0.15, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
local GRIP_INV = GRIP:Inverse()
local UPPER, LOWER = 1.15, 1.05 -- arm bone lengths (studs)

local model: Model? = nil
local arms = {}
local itemModel: Model? = nil
local itemId: string? = nil
local lens: BasePart? = nil
local modal: TextButton? = nil

local bobOn = true
local firstPerson = false
local equipT = -10
local actionName: string? = nil
local actionT = -10
local phase = 0
local lastCamLook: CFrame? = nil
local sway = Vector2.zero
local swayVel = Vector2.zero
local kick = 0
local kickVel = 0
local wasAir = false
local airTime = 0
local smoothSpeed = 0
local lastRootPos: Vector3? = nil

--============================ BUILD ============================--
local function part(name: string, size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function colors(): (Color3, Color3, Color3)
	local char = player.Character
	local skin = Color3.fromHex("c99a74")
	local sleeve = Color3.fromHex("283040")
	local cuff = Color3.fromHex("1c222d")
	if char then
		local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
		if hand and hand:IsA("BasePart") then
			skin = hand.Color
		end
		local arm = char:FindFirstChild("RightUpperArm") or char:FindFirstChild("Right Arm")
		local shirt = char:FindFirstChildOfClass("Shirt")
		if arm and arm:IsA("BasePart") and not shirt then
			sleeve = arm.Color
		end
		local outfit = char:FindFirstChild("Outfit")
		local shell = outfit and outfit:FindFirstChild("OutfitShell")
		if shell and shell:IsA("BasePart") then
			sleeve = shell.Color
		end
		cuff = sleeve:Lerp(Color3.new(0, 0, 0), 0.35)
	end
	return skin, sleeve, cuff
end

local function buildArms()
	if model then
		model:Destroy()
	end
	model = Instance.new("Model")
	model.Name = "MSL_ViewModel"
	local skin, sleeve, cuff = colors()
	table.clear(arms)
	for _, side in { "R", "L" } do
		local a = {
			Upper = part(side .. "Upper", Vector3.new(0.42, UPPER, 0.42), sleeve, Enum.Material.Fabric),
			Lower = part(side .. "Lower", Vector3.new(0.38, LOWER, 0.38), sleeve, Enum.Material.Fabric),
			Cuff = part(side .. "Cuff", Vector3.new(0.42, 0.14, 0.42), cuff, Enum.Material.Fabric),
			Hand = part(side .. "Hand", Vector3.new(0.34, 0.42, 0.24), skin),
			Thumb = part(side .. "Thumb", Vector3.new(0.1, 0.22, 0.1), skin),
			Fingers = part(side .. "Fingers", Vector3.new(0.32, 0.12, 0.2), skin),
		}
		for _, p in a do
			p.Parent = model
		end
		arms[side] = a
	end
	model.Parent = Workspace.CurrentCamera
end

local function setItem(id: string?)
	if itemModel then
		itemModel:Destroy()
		itemModel = nil
	end
	lens = nil
	itemId = id
	equipT = os.clock()
	if not id or not model or not Items.Get(id) then
		return
	end
	local m = Models.Item(id)
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			if p.Name == "Lens" then
				lens = p
			end
		elseif p:IsA("WeldConstraint") or p:IsA("Weld") then
			p:Destroy()
		end
	end
	-- anchored: keep each part's offset from the pivot so we can move the whole item
	local pivot = m:GetPivot()
	local offsets = {}
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			offsets[p] = pivot:ToObjectSpace(p.CFrame)
		end
	end
	m:SetAttribute("ViewItem", id)
	m.Parent = model
	itemModel = m
	ViewModel._offsets = offsets
end

--============================ ARM IK ============================--
-- place a two-bone arm from shoulder S to the hand CFrame; pole points the elbow
local function placeArm(a, S: Vector3, hand: CFrame, pole: Vector3)
	local wrist = (hand * CFrame.new(0, 0.21, 0)).Position -- hand +Y points to the wrist
	local toW = wrist - S
	local d = clamp(toW.Magnitude, 0.2, UPPER + LOWER - 0.02)
	local dir = if toW.Magnitude > 1e-3 then toW.Unit else Vector3.new(0, 0, -1)
	-- law of cosines for the upper bone angle
	local cosA = clamp((UPPER * UPPER + d * d - LOWER * LOWER) / (2 * UPPER * d), -1, 1)
	local sinA = math.sqrt(1 - cosA * cosA)
	local bend = (pole - dir * pole:Dot(dir))
	bend = if bend.Magnitude > 1e-3 then bend.Unit else Vector3.new(0, -1, 0)
	local elbow = S + dir * (cosA * UPPER) + bend * (sinA * UPPER)
	local function bone(p: BasePart, from: Vector3, to: Vector3)
		local mid = (from + to) / 2
		local up = (from - to)
		up = if up.Magnitude > 1e-3 then up.Unit else Vector3.new(0, 1, 0)
		local right = up:Cross(Vector3.new(0, 0, 1))
		right = if right.Magnitude > 1e-3 then right.Unit else Vector3.new(1, 0, 0)
		p.CFrame = CFrame.fromMatrix(mid, right, up)
	end
	bone(a.Upper, S, elbow)
	bone(a.Lower, elbow, wrist)
	a.Cuff.CFrame = CFrame.lookAt(wrist, wrist + (wrist - elbow).Unit) * CFrame.Angles(math.pi / 2, 0, 0) * CFrame.new(0, -0.02, 0)
	a.Hand.CFrame = hand
	a.Fingers.CFrame = hand * CFrame.new(0, -0.2, -0.1)
	a.Thumb.CFrame = hand * CFrame.new(if a == arms.R then -0.2 else 0.2, -0.02, -0.08) * CFrame.Angles(0, 0, rad(if a == arms.R then -25 else 25))
end

--============================ POSES ============================--
-- the grip point (item canonical orientation) in camera space for each hold
local BASE = {
	Aim = CFrame.new(0.78, -0.82, -1.55) * CFrame.Angles(rad(2), rad(3), 0),
	Melee = CFrame.new(0.95, -1.12, -1.65) * CFrame.Angles(rad(8), rad(-14), rad(-10)),
	OneHand = CFrame.new(0.72, -0.92, -1.45) * CFrame.Angles(rad(-4), rad(-18), 0),
	TwoHand = CFrame.new(0.85, -1.18, -1.5) * CFrame.Angles(rad(-6), 0, 0),
	Push = CFrame.new(0.95, -1.35, -1.9),
}

local function heldKind(): string?
	if (player:GetAttribute("CartId") or 0) ~= 0 then
		return "Push"
	end
	local id = player:GetAttribute("HeldItem")
	if type(id) == "string" and id ~= "" then
		return Holding.Kind(id)
	end
	return nil
end

local function actionOffset(kind: string, now: number): CFrame
	local length = actionName and Holding.ActionTime[actionName]
	if not length then
		return CFrame.new()
	end
	local k = (now - actionT) / length
	if k < 0 or k >= 1 then
		actionName = nil
		return CFrame.new()
	end
	local env = sin(k * math.pi)
	local a = actionName
	if a == "Swing" or a == "Build" then
		local wind = clamp(k / 0.35, 0, 1)
		local strike = clamp((k - 0.35) / 0.18, 0, 1)
		local back = 1 - clamp((k - 0.6) / 0.4, 0, 1)
		return CFrame.new(-0.25 * strike * back, 0.35 * wind - 0.55 * strike * back, 0.2 * wind - 0.5 * strike * back)
			* CFrame.Angles(rad(55 * wind - 125 * strike) * back, rad(15 * wind), rad(-20 * strike * back))
	elseif a == "Eat" or a == "Drink" then
		local nib = sin(k * 24) * 0.03 * env
		return CFrame.new(-0.62 * env, 0.62 * env + nib, 0.55 * env) * CFrame.Angles(rad((if a == "Drink" then 65 else 25) * env), rad(30 * env), 0)
	elseif a == "Heal" then
		return CFrame.new(-0.5 * env, 0.25 * env, 0.2 * env) * CFrame.Angles(rad(-25 * env), rad(25 * env), 0)
	elseif a == "Throw" then
		local back = clamp(k / 0.45, 0, 1)
		local fwd = clamp((k - 0.45) / 0.2, 0, 1)
		return CFrame.new(0.15 * back - 0.2 * fwd, 0.55 * back - 0.2 * fwd, 0.6 * back - 1.2 * fwd) * CFrame.Angles(rad(60 * back - 90 * fwd), 0, 0)
	elseif a == "Place" or a == "Pickup" or a == "Revive" then
		return CFrame.new(-0.1 * env, -0.7 * env, -0.25 * env) * CFrame.Angles(rad(-35 * env), 0, 0)
	elseif a == "Reload" then
		return CFrame.new(-0.25 * env, 0.12 * env, 0.15 * env) * CFrame.Angles(rad(-20 * env), rad(40 * env), rad(30 * env))
	elseif a == "Click" then
		return CFrame.new(0, 0, 0.05 * env) * CFrame.Angles(rad(-4 * env), 0, 0)
	end
	return CFrame.new()
end

--============================ FRAME ============================--
local function shouldShow(): boolean
	if not ClientState.InRun() or ClientState.MenuOpen then
		return false
	end
	if player:GetAttribute("Dead") or player:GetAttribute("Downed") or player:GetAttribute("Hidden") then
		return false
	end
	return player.Character ~= nil
end

local function updateCameraMode(alive: boolean)
	if alive then
		if player.CameraMode ~= Enum.CameraMode.LockFirstPerson then
			player.CameraMode = Enum.CameraMode.LockFirstPerson
		end
	else
		if player.CameraMode ~= Enum.CameraMode.Classic then
			player.CameraMode = Enum.CameraMode.Classic
			player.CameraMaxZoomDistance = 14
			player.CameraMinZoomDistance = 0.5
		end
	end
end

local function hideBody(char: Model)
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
		elseif d:IsA("Decal") then
			d.LocalTransparencyModifier = 1
		end
	end
end

local function render(dt: number)
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local inRunAlive = ClientState.InRun() and not ClientState.MenuOpen and not player:GetAttribute("Dead")
	updateCameraMode(inRunAlive and not player:GetAttribute("Hidden"))
	-- free the mouse while a window is open
	if modal then
		local busy = ClientState.Busy
		modal.Visible = ClientState.MenuOpen or busy.Inventory == true or busy.Container == true or busy.Map == true or busy.Confirm == true or busy.Pause == true or busy.Results == true or busy.BuildMenu == true
		-- first person: no mouse arrow in the middle of the screen (the HUD has a crosshair);
		-- it comes back whenever a window frees the mouse or you're not in the store
		local locked = inRunAlive and not modal.Visible and not player:GetAttribute("Hidden")
		if UserInputService.MouseIconEnabled ~= not locked then
			UserInputService.MouseIconEnabled = not locked
		end
	end
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	firstPerson = head ~= nil and (cam.CFrame.Position - (head :: BasePart).Position).Magnitude < 2.2
	local show = shouldShow() and firstPerson
	if not model or not model.Parent then
		buildArms()
	end
	if not show then
		if model then
			model.Parent = nil
		end
		lastCamLook = nil
		return
	end
	model.Parent = cam
	if char then
		hideBody(char)
	end

	local now = os.clock()
	local kind = heldKind()
	local held = player:GetAttribute("HeldItem")
	if type(held) ~= "string" or held == "" then
		held = nil
	end
	if held ~= itemId then
		setItem(held)
	end
	if not kind then
		model.Parent = nil
		return
	end

	-- movement
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local speed = 0
	if root then
		if lastRootPos then
			local d = root.Position - lastRootPos
			speed = Vector3.new(d.X, 0, d.Z).Magnitude / math.max(dt, 1e-3)
			if speed > 80 then
				speed = 0
			end
		end
		lastRootPos = root.Position
	end
	smoothSpeed += (speed - smoothSpeed) * clamp(dt * 8, 0, 1)
	local sprint = player:GetAttribute("Sprinting") == true
	local crouch = player:GetAttribute("Crouching") == true
	local moving = clamp(smoothSpeed / 14, 0, 1.4)
	phase = (phase + smoothSpeed * dt / (if sprint then 7 else 5.2)) % 1
	local ph = phase * math.pi * 2

	local air = hum and hum.FloorMaterial == Enum.Material.Air
	if air then
		airTime += dt
	elseif wasAir and airTime > 0.25 then
		kickVel -= clamp(airTime, 0.3, 1) * 3.5
		airTime = 0
	else
		airTime = 0
	end
	wasAir = air == true
	-- spring for the jump / land kick
	kickVel += (-kick * 60 - kickVel * 10) * dt
	kick += kickVel * dt

	-- mouse sway: how much the camera turned this frame
	local look = cam.CFrame.Rotation
	if lastCamLook then
		local rel = lastCamLook:ToObjectSpace(look)
		local rx, ry = rel:ToEulerAnglesYXZ()
		swayVel += Vector2.new(-ry, -rx) * 0.9
	end
	lastCamLook = look
	swayVel += (-sway * 90 - swayVel * 14) * dt
	sway += swayVel * dt
	sway = Vector2.new(clamp(sway.X, -0.25, 0.25), clamp(sway.Y, -0.25, 0.25))

	local b = if bobOn then 1 else 0.25
	local bobX = sin(ph) * 0.045 * moving * b
	local bobY = -math.abs(cos(ph)) * 0.05 * moving * b
	local breathe = sin(now * 1.6) * 0.012
	local sprintPose = if sprint and moving > 0.5 and kind ~= "Push" then 1 else 0
	local equip = clamp((now - equipT) / 0.32, 0, 1)
	local e = 1 - (1 - equip) ^ 3

	local offset = CFrame.new(bobX + sway.X * 0.35, bobY + breathe + kick * 0.08 - (if crouch then 0.05 else 0) - (1 - e) * 1.1, 0)
		* CFrame.Angles(sway.Y * 0.6 + (1 - e) * rad(-35), sway.X * 0.6, bobX * 1.2)
		* CFrame.new(-0.18 * sprintPose, -0.12 * sprintPose, 0.1 * sprintPose)
		* CFrame.Angles(rad(-18) * sprintPose, rad(28) * sprintPose, rad(-8) * sprintPose)

	local grip = cam.CFrame * offset * BASE[kind] * actionOffset(kind, now)

	-- the item
	if itemModel and itemId and kind ~= "Push" then
		local pivot = grip * Holding.ItemOffset(itemId)
		for p, ofs in ViewModel._offsets or {} do
			if p.Parent then
				p.CFrame = pivot * ofs
			end
		end
		if lens then
			local on = player:GetAttribute("FlashOn") == true
			lens.Material = if on then Enum.Material.Neon else Enum.Material.Glass
			lens.Transparency = if on then 0 else 0.3
		end
		itemModel.Parent = model
	elseif itemModel then
		itemModel.Parent = nil
	end

	-- arms
	local camCF = cam.CFrame * offset
	local shoulderR = (camCF * CFrame.new(0.95, -1.55, 0.35)).Position
	local shoulderL = (camCF * CFrame.new(-0.95, -1.55, 0.35)).Position
	local handR = grip * GRIP_INV
	local poleR = (camCF.RightVector * 0.6 - camCF.UpVector)
	local poleL = (-camCF.RightVector * 0.6 - camCF.UpVector)
	local showLeft = false
	local handL = handR
	if kind == "TwoHand" and itemId then
		local item = Items.Get(itemId)
		local w = item and item.Size[1] or 1
		local pivot = grip * Holding.ItemOffset(itemId)
		handL = pivot * CFrame.new(-w / 2 + 0.1, 0, 0) * CFrame.Angles(-math.pi / 2, 0, 0) * CFrame.new(0, 0.15, 0)
		showLeft = true
	elseif kind == "Push" then
		handR = cam.CFrame * offset * CFrame.new(0.9, -1.35, -1.9) * CFrame.Angles(-math.pi / 2, 0, 0)
		handL = cam.CFrame * offset * CFrame.new(-0.9, -1.35, -1.9) * CFrame.Angles(-math.pi / 2, 0, 0)
		showLeft = true
	elseif actionName == "Heal" or actionName == "Reload" then
		handL = grip * CFrame.new(-0.35, 0.05, 0.1) * CFrame.Angles(-math.pi / 2, 0, rad(20))
		showLeft = true
	end
	placeArm(arms.R, shoulderR, handR, poleR)
	if showLeft then
		placeArm(arms.L, shoulderL, handL, poleL)
	end
	for _, p in arms.L do
		p.Transparency = if showLeft then 0 else 1
	end
end

function ViewModel.Play(action: string?)
	if action and Holding.ActionTime[action] then
		actionName = action
		actionT = os.clock()
	end
end

function ViewModel.SetBob(on: boolean)
	bobOn = on
end

function ViewModel.SetSensitivity(v: number)
	pcall(function()
		UserInputService.MouseDeltaSensitivity = math.clamp(v, 0.2, 2)
	end)
end

function ViewModel.IsFirstPerson(): boolean
	return firstPerson
end

function ViewModel.Init()
	local _, root = UI.screen("MSL_MouseUnlock", 0)
	modal = UI.make("TextButton", { Name = "Modal", Modal = true, Text = "", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), Visible = false }, root)
	RunService:BindToRenderStep("MSL_ViewModel", Enum.RenderPriority.Camera.Value + 5, render)
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		buildArms()
		itemId = nil
	end)
	-- the server's action broadcast (our own input already played it)
	local function hookChar(char: Model)
		char:GetAttributeChangedSignal("ActionN"):Connect(function()
			local a = char:GetAttribute("Action")
			-- skip the echo of an action we already predicted locally
			if a and not (actionName == a and os.clock() - actionT < 0.6) then
				ViewModel.Play(a)
			end
		end)
	end
	if player.Character then
		hookChar(player.Character)
	end
	player.CharacterAdded:Connect(hookChar)
end

return ViewModel
