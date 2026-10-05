--[[
	MenuScene: the 3D background of the main menu, built locally on the client.
	A dark supermarket aisle disappearing into the fog, buzzing ceiling lights that flicker,
	an abandoned cart... and sometimes, far down the aisle, THE LOCUST crosses the light.
	The camera breathes and slowly drifts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local LocustRig = require(Shared.LocustRig)
local Models = require(Shared.Models)

local LocustAnimator = require(script.Parent.LocustAnimator)
local Audio = require(script.Parent.Audio)

local MenuScene = {}

local ORIGIN = Vector3.new(0, 2200, 0)
local scene: Model? = nil
local lights = {}
local locust: Model? = nil
local conn: RBXScriptConnection? = nil
local running = false

local function part(parent, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local PRODUCTS = { "e53935", "fdd835", "43a047", "fb8c00", "8e24aa", "1e88e5", "f5f5f5", "6d4c41", "ff7043", "26a69a" }

local function build()
	local m = Instance.new("Model")
	m.Name = "MenuScene"
	local o = CFrame.new(ORIGIN)
	part(m, Vector3.new(60, 1, 420), o * CFrame.new(0, -0.5, -200), Color3.fromHex("bdb8ad"), Enum.Material.SmoothPlastic, { Reflectance = 0.06 })
	part(m, Vector3.new(60, 1, 420), o * CFrame.new(0, 24.5, -200), Color3.fromHex("1d1e21"), Enum.Material.Concrete)
	part(m, Vector3.new(1, 25, 420), o * CFrame.new(-30, 12, -200), Color3.fromHex("8f8b83"), Enum.Material.Concrete)
	part(m, Vector3.new(1, 25, 420), o * CFrame.new(30, 12, -200), Color3.fromHex("8f8b83"), Enum.Material.Concrete)
	local rng = Random.new(7)
	for i = 0, 12 do
		local z = -10 - i * 30
		for _, x in { -12, 12 } do
			local g = o * CFrame.new(x, 0, z - 13)
			part(m, Vector3.new(4.5, 0.6, 26), g * CFrame.new(0, 0.3, 0), Color3.fromHex("5f646b"), Enum.Material.Metal)
			part(m, Vector3.new(0.3, 8.5, 26), g * CFrame.new(0, 4.6, 0), Color3.fromHex("868b92"), Enum.Material.Metal)
			for lv = 1, 3 do
				local y = 0.6 + lv * 2.43
				part(m, Vector3.new(4.5, 0.2, 26), g * CFrame.new(0, y - 0.1, 0), Color3.fromHex("5f646b"), Enum.Material.Metal)
			end
			for _, sy in { 0.6, 3.03, 5.46 } do
				for _, side in { -1, 1 } do
					if rng:NextNumber() < 0.8 then
						local len = rng:NextNumber(8, 24)
						local h = rng:NextNumber(0.9, 1.7)
						part(m, Vector3.new(1.7, h, len), g * CFrame.new(side * 1.1, sy + h / 2, rng:NextNumber(-12 + len / 2, 12 - len / 2)), Color3.fromHex(PRODUCTS[rng:NextInteger(1, #PRODUCTS)]), Enum.Material.SmoothPlastic)
					end
				end
			end
		end
		-- ceiling fixture over the aisle
		local fixture = part(m, Vector3.new(2, 0.35, 10), o * CFrame.new(0, 22.6, z), Color3.fromHex("fff4dc"), Enum.Material.Neon)
		part(m, Vector3.new(2.4, 0.4, 10.4), o * CFrame.new(0, 23, z), Color3.fromHex("9ea3a8"), Enum.Material.Metal)
		local sl = Instance.new("SurfaceLight")
		sl.Face = Enum.NormalId.Bottom
		sl.Angle = 120
		sl.Range = 32
		sl.Brightness = 1.3
		sl.Color = Color3.fromHex("fff1d6")
		sl.Parent = fixture
		table.insert(lights, { Part = fixture, Light = sl, Broken = i == 2 or i == 6 or i >= 8, Dead = i >= 9 })
		-- aisle sign
		if i % 3 == 1 then
			local sign = part(m, Vector3.new(9, 3, 0.4), o * CFrame.new(0, 17, z - 15), Color3.fromHex("15171a"))
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Back
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 30
			gui.LightInfluence = 0.4
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Size = UDim2.fromScale(1, 1)
			t.Font = Enum.Font.GothamBlack
			t.TextScaled = true
			t.TextColor3 = Color3.fromHex("ffc61a")
			t.Text = "AISLE " .. (40 + i)
			t.Parent = gui
			gui.Parent = sign
		end
	end
	-- the cart
	local cart = Models.Cart()
	for _, p in cart:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
		end
	end
	cart:PivotTo(o * CFrame.new(-4, 0.85, -34) * CFrame.Angles(0, math.rad(28), 0))
	cart.Parent = m
	for k = 1, 3 do
		part(m, Vector3.new(1, 1.3, 0.4), o * CFrame.new(rng:NextNumber(-6, 6), 0.65, -25 - k * 4) * CFrame.Angles(math.rad(90), rng:NextNumber(0, 6), 0), Color3.fromHex(PRODUCTS[k]))
	end
	-- the Locust, far away
	locust = LocustRig.Build(Config.LocustVariants[1], 1)
	for _, p in locust:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = p.Name == "HumanoidRootPart"
			p.CanCollide = false
		end
	end
	locust.Name = "Locust"
	locust:PivotTo(o * CFrame.new(-40, 6, -170) * CFrame.Angles(0, math.rad(-90), 0))
	locust.Parent = m
	m.Parent = Workspace
	scene = m
	LocustAnimator.Track(locust)
end

local camT = 0
local locustT = 0
local nextAppearance = 6
local appearance = nil

local function step(dt)
	if not running then
		return
	end
	camT += dt
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local o = CFrame.new(ORIGIN)
	local drift = math.sin(camT * 0.05) * 6
	local sway = CFrame.Angles(math.rad(math.sin(camT * 0.7) * 0.6), math.rad(math.sin(camT * 0.37) * 1.4 - 7), math.rad(math.sin(camT * 0.5) * 0.5))
	cam.CFrame = o * CFrame.new(5 + math.sin(camT * 0.21) * 0.6, 5.2 + math.sin(camT * 0.9) * 0.08, 4 - drift) * sway
	cam.FieldOfView = 62

	-- lights flicker
	for _, l in lights do
		if l.Dead then
			l.Part.Material = Enum.Material.SmoothPlastic
			l.Part.Color = Color3.fromHex("2a2a2c")
			l.Light.Enabled = false
		elseif l.Broken then
			local on = math.random() > 0.18
			l.Light.Enabled = on
			l.Part.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end

	-- the Locust crosses the far end of the aisle now and then
	locustT += dt
	if locust and locust.PrimaryPart then
		local root = locust.PrimaryPart
		if not appearance and locustT > nextAppearance then
			appearance = { Start = locustT, Dir = if math.random() < 0.5 then 1 else -1, Z = -150 - math.random() * 40 }
			Audio.Play("LocustClick", root.Position)
		end
		if appearance then
			local t = (locustT - appearance.Start) / 9
			if t >= 1 then
				appearance = nil
				nextAppearance = locustT + 14 + math.random() * 14
				root.CFrame = o * CFrame.new(-60, 6, -170)
			else
				local x = (-34 + 68 * t) * appearance.Dir
				local stopX = math.sin(t * math.pi) -- slows down in the middle of the aisle... and looks
				local yaw = if appearance.Dir > 0 then -90 else 90
				if t > 0.45 and t < 0.6 then
					yaw = 180 -- it looks down the aisle. at you.
				end
				root.CFrame = o * CFrame.new(x * (0.6 + 0.4 * (1 - stopX * 0.6)), 6, appearance.Z) * CFrame.Angles(0, math.rad(yaw), 0)
				root.AssemblyLinearVelocity = Vector3.new(6 * appearance.Dir, 0, 0)
			end
		end
	end
end

function MenuScene.Start()
	if running then
		return
	end
	running = true
	if not scene then
		build()
	else
		scene.Parent = Workspace
		if locust then
			LocustAnimator.Track(locust)
		end
	end
	if not conn then
		conn = RunService.RenderStepped:Connect(step)
	end
end

function MenuScene.Stop()
	running = false
	if scene then
		scene.Parent = nil
	end
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = 70
end

return MenuScene
