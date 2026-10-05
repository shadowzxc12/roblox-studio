--[[
	LoadingScreen (ReplicatedFirst = runs before anything else on the client).
	Shows the logo, an animated stud spinner, a progress bar and real loading steps,
	then fades out and sets LocalPlayer attribute "LoadingDone" so the rest of the UI starts.
	Self-contained on purpose (no modules) so it appears instantly.
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local INK = Color3.fromHex("1b1530")
local FONT = Font.fromEnum(Enum.Font.FredokaOne)
local MIN_TIME = 2.2
local MAX_WAIT_PER_STEP = 15

local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in props do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end
local function corner(p, r)
	make("UICorner", { CornerRadius = if r then UDim.new(0, r) else UDim.new(1, 0) }, p)
end
local function stroke(p, t)
	make("UIStroke", { Thickness = t, Color = INK }, p)
end

local gui = make("ScreenGui", { Name = "LoadingScreen", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 1000 }, playerGui)
local fade = make("CanvasGroup", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
local bg = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, fade)
make("UIGradient", {
	Color = ColorSequence.new(Color3.fromHex("4cc3ff"), Color3.fromHex("6a3df0")),
	Rotation = 60,
}, bg)

-- background: big soft studs drifting slowly
local studLayer = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1.2, 1.2), Position = UDim2.fromScale(-0.1, -0.1) }, fade)
for y = 0, 9 do
	for x = 0, 15 do
		local d = make("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.88,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale((x + (y % 2) * 0.5) / 15, y / 9),
			Size = UDim2.fromScale(0.022, 0.04),
		}, studLayer)
		make("UIAspectRatioConstraint", { AspectRatio = 1 }, d)
		corner(d)
	end
end

-- centre column (scaled to the screen)
local center = make("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(700, 420),
}, fade)
local uiScale = make("UIScale", {}, center)
local function rescale()
	local cam = workspace.CurrentCamera
	if cam then
		local vp = cam.ViewportSize
		uiScale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.45, 1.4)
	end
end
rescale()

local logo = make("TextLabel", {
	BackgroundTransparency = 1,
	FontFace = FONT,
	Text = "STUD CHASE",
	TextSize = 96,
	TextColor3 = Color3.fromHex("ffd23f"),
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.new(1, 0, 0, 110),
	Rotation = -3,
}, center)
stroke(logo, 8)
local logoScale = make("UIScale", { Scale = 0.6 }, logo)
TweenService:Create(logoScale, TweenInfo.new(0.6, Enum.EasingStyle.Back), { Scale = 1 }):Play()

local tagline = make("TextLabel", {
	BackgroundTransparency = 1,
	FontFace = FONT,
	Text = "RUN!  CATCH!  WIN!",
	TextSize = 30,
	TextColor3 = Color3.new(1, 1, 1),
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 112),
	Size = UDim2.new(1, 0, 0, 36),
}, center)
stroke(tagline, 3)

-- spinner: 8 studs in a ring that light up one after another
local spinner = make("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 180),
	Size = UDim2.fromOffset(110, 110),
}, center)
local dots = {}
for i = 1, 8 do
	local a = (i - 1) / 8 * math.pi * 2
	local d = make("Frame", {
		BackgroundColor3 = Color3.fromHex("ffd23f"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, math.cos(a) * 40, 0.5, math.sin(a) * 40),
		Size = UDim2.fromOffset(22, 22),
	}, spinner)
	corner(d)
	stroke(d, 3)
	table.insert(dots, d)
end

-- progress bar
local bar = make("Frame", {
	BackgroundColor3 = Color3.fromHex("23263a"),
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 320),
	Size = UDim2.fromOffset(460, 30),
}, center)
corner(bar)
stroke(bar, 4)
local fill = make("Frame", { BackgroundColor3 = Color3.fromHex("6aea4f"), Size = UDim2.fromScale(0, 1) }, bar)
corner(fill)
make("UIGradient", { Color = ColorSequence.new(Color3.fromHex("9dff7a"), Color3.fromHex("1fa324")), Rotation = 90 }, fill)

local status = make("TextLabel", {
	BackgroundTransparency = 1,
	FontFace = FONT,
	Text = "Loading...",
	TextSize = 28,
	TextColor3 = Color3.new(1, 1, 1),
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 362),
	Size = UDim2.new(1, 0, 0, 34),
}, center)
stroke(status, 3)

-- animation loop (only while the loading screen exists)
local conn = RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for i, d in dots do
		local phase = (t * 8 - i) % 8
		d.BackgroundTransparency = math.clamp(phase / 8, 0, 0.85)
		local s = 22 + math.max(0, 6 - phase * 2)
		d.Size = UDim2.fromOffset(s, s)
	end
	logo.Rotation = -3 + math.sin(t * 2) * 2
	studLayer.Position = UDim2.fromScale(-0.1 + (t * 0.01) % (1 / 15), -0.1 + (t * 0.006) % (2 / 9))
end)

local function setProgress(p: number, text: string)
	status.Text = text
	TweenService:Create(fill, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(p, 1) }):Play()
end

local startedAt = os.clock()
local function waitFor(check: () -> boolean)
	local t0 = os.clock()
	while not check() and os.clock() - t0 < MAX_WAIT_PER_STEP do
		task.wait(0.1)
	end
end

-- real loading steps
setProgress(0.15, "Loading...")
if not game:IsLoaded() then
	game.Loaded:Wait()
end
setProgress(0.4, "Loading Map...")
waitFor(function()
	return workspace:FindFirstChild("Lobby") ~= nil
end)
setProgress(0.65, "Preparing Match...")
waitFor(function()
	local serverType = ReplicatedStorage:GetAttribute("ServerType")
	return serverType == "Lobby" or (serverType == "Match" and ReplicatedStorage:GetAttribute("GameMode") ~= nil)
end)
setProgress(0.85, "Almost Ready...")
waitFor(function()
	return player:GetAttribute("DataLoaded") == true
end)
setProgress(1, "Let's go!")
task.wait(math.max(0.4, MIN_TIME - (os.clock() - startedAt)))

-- smooth fade out
local out = TweenService:Create(fade, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { GroupTransparency = 1 })
TweenService:Create(uiScale, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Scale = uiScale.Scale * 1.15 }):Play()
player:SetAttribute("LoadingDone", true)
out:Play()
out.Completed:Wait()
conn:Disconnect()
gui:Destroy()
