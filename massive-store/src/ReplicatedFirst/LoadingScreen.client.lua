--[[
	LoadingScreen (ReplicatedFirst runs first): a short cinematic while the game loads.
	Black screen, a buzzing store sign flickers to life, tips fade in and out, real loading
	steps fill the bar, then everything fades into the main menu.
	Self-contained on purpose (no modules) so it appears instantly.
]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

ReplicatedFirst:RemoveDefaultLoadingScreen()
-- coming from a teleport: keep the receipt screen from the other place up until we're ready
local arriving = nil
pcall(function()
	arriving = game:GetService("TeleportService"):GetArrivingTeleportGui()
end)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local YELLOW = Color3.fromHex("ffc61a")
local RED = Color3.fromHex("e0262d")
local TEXT = Color3.fromHex("f2f0ea")
local MUTED = Color3.fromHex("8d939c")
-- Figma type: Oswald (display), Roboto Mono (labels), Montserrat (body)
local TITLE = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
local CAPS = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)
local BODY = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Medium)
local MIN_TIME = 4.5

local TIPS = {
	"The lights don't stay on forever.",
	"Never go outside alone at night.",
	"The Locust learns.",
	"Food is more valuable than money.",
	"Sprinting is loud. Crouching is quiet.",
	"It sees your flashlight before it sees you.",
	"A locked door buys time. A metal door buys more.",
	"Generators are loud. Something might hear them.",
	"If it loses sight of you, stay still.",
	"Lockers are safe... for the first few nights.",
	"Downed teammates can be revived. Don't leave them.",
	"Every night, it gets a little faster.",
	"The basement opens on night 10. Or with a keycard.",
	"Thank you for shopping at MASSIVE STORE.",
}

local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in props do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local gui = make("ScreenGui", { Name = "LoadingScreen", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 1000, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
if arriving then
	arriving.DisplayOrder = 1001
	arriving.Parent = playerGui
end
local fade = make("CanvasGroup", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromHex("050506"), BorderSizePixel = 0 }, gui)

-- faint aisle lines in the background
for i = 1, 9 do
	local x = i / 10
	make("Frame", {
		BackgroundColor3 = Color3.fromHex("15171b"),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(x, 0),
		Size = UDim2.new(0, 2, 1, 0),
		BackgroundTransparency = 0.3,
	}, fade)
end

local center = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(640, 360) }, fade)
local uiScale = make("UIScale", {}, center)
local function rescale()
	local cam = Workspace.CurrentCamera
	if cam then
		local vp = cam.ViewportSize
		uiScale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.5, 1.5)
	end
end
rescale()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end

-- the sign
local sign = make("Frame", { BackgroundColor3 = YELLOW, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(320, 40), Size = UDim2.fromOffset(520, 100), BackgroundTransparency = 1 }, center)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, sign)
local signStroke = make("UIStroke", { Color = Color3.fromHex("6b4e00"), Thickness = 3, Transparency = 1 }, sign)
local signText = make("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), FontFace = TITLE, Text = "MASSIVE STORE", TextSize = 76, TextColor3 = TEXT, TextTransparency = 1 }, sign)
local stripe = make("Frame", { BackgroundColor3 = RED, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(320, 146), Size = UDim2.fromOffset(236, 52), BackgroundTransparency = 1 }, center)
make("UICorner", { CornerRadius = UDim.new(0, 4) }, stripe)
local stripeText = make("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), FontFace = TITLE, Text = "LOCUST", TextSize = 40, TextColor3 = Color3.new(1, 1, 1), TextTransparency = 1 }, stripe)
make("TextLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(320, 20), Size = UDim2.fromOffset(400, 16), FontFace = CAPS, Text = "OPEN 24/7  ·  NO EXIT", TextSize = 12, TextColor3 = YELLOW }, center)
local glow = make("Frame", { BackgroundColor3 = YELLOW, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(320, 100), Size = UDim2.fromOffset(700, 260), BackgroundTransparency = 1, ZIndex = 0 }, center)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, glow)

local tip = make("TextLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(320, 216), Size = UDim2.fromOffset(640, 30), FontFace = BODY, TextSize = 20, TextColor3 = TEXT, TextTransparency = 1, Text = "" }, center)
local barBack = make("Frame", { BackgroundColor3 = Color3.fromHex("1a1d23"), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(320, 290), Size = UDim2.fromOffset(360, 4) }, center)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, barBack)
local bar = make("Frame", { BackgroundColor3 = YELLOW, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1) }, barBack)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, bar)
local status = make("TextLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(320, 302), Size = UDim2.fromOffset(400, 16), FontFace = CAPS, TextSize = 11, TextColor3 = MUTED, Text = "" }, center)

-- a little hum
local hum = Instance.new("Sound")
hum.SoundId = "rbxasset://sounds/Launching rocket.wav"
hum.Looped = true
hum.PlaybackSpeed = 0.1
hum.Volume = 0
hum.Parent = SoundService
pcall(function()
	hum:Play()
end)
TweenService:Create(hum, TweenInfo.new(2), { Volume = 0.12 }):Play()
local buzz = Instance.new("Sound")
buzz.SoundId = "rbxasset://sounds/electronicpingshort.wav"
buzz.PlaybackSpeed = 0.25
buzz.Volume = 0.25
buzz.Parent = SoundService

local started = os.clock()

-- the sign flickers on
task.spawn(function()
	task.wait(0.6)
	for i = 1, 7 do
		local on = i % 2 == 1 or i == 7
		local t = if on then 0 else 0.85
		signText.TextTransparency = t
		stripe.BackgroundTransparency = t
		stripeText.TextTransparency = t
		glow.BackgroundTransparency = if on then 0.94 else 1
		if on then
			pcall(function()
				buzz:Play()
			end)
		end
		task.wait(0.04 + math.random() * 0.14)
	end
	-- occasional flicker afterwards
	while gui.Parent do
		task.wait(1 + math.random() * 3)
		stripe.BackgroundTransparency = 0.6
		glow.BackgroundTransparency = 1
		task.wait(0.06)
		stripe.BackgroundTransparency = 0
		glow.BackgroundTransparency = 0.94
	end
end)

-- tips
task.spawn(function()
	local order = {}
	for i = 1, #TIPS do
		order[i] = i
	end
	for i = #order, 2, -1 do
		local j = math.random(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local k = 1
	task.wait(1.2)
	while gui.Parent do
		tip.Text = '"' .. TIPS[order[k]] .. '"'
		TweenService:Create(tip, TweenInfo.new(0.6), { TextTransparency = 0 }):Play()
		task.wait(3)
		TweenService:Create(tip, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
		task.wait(0.7)
		k = k % #order + 1
	end
end)

local function setProgress(f: number, text: string)
	status.Text = text
	TweenService:Create(bar, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(f, 1) }):Play()
end

local function waitFor(check, timeout)
	local t0 = os.clock()
	while not check() and os.clock() - t0 < timeout do
		task.wait(0.1)
	end
end

setProgress(0.12, "UNLOCKING THE DOORS")
if not game:IsLoaded() then
	game.Loaded:Wait()
end
setProgress(0.35, "BUILDING THE STORE")
waitFor(function()
	return ReplicatedStorage:GetAttribute("ServerReady") == true
end, 60)
setProgress(0.6, "STOCKING THE SHELVES")
waitFor(function()
	return ReplicatedStorage:FindFirstChild("Remotes") ~= nil and ReplicatedStorage:FindFirstChild("Shared") ~= nil
end, 30)
pcall(function()
	ContentProvider:PreloadAsync({ hum, buzz })
end)
setProgress(0.8, "TURNING ON THE LIGHTS")
waitFor(function()
	return player:GetAttribute("DataLoaded") == true
end, 20)
setProgress(1, "WELCOME TO MASSIVE STORE")
local left = MIN_TIME - (os.clock() - started)
if left > 0 then
	task.wait(left)
end
task.wait(0.4)

player:SetAttribute("LoadingDone", true)
if arriving then
	arriving:Destroy()
end
TweenService:Create(fade, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { GroupTransparency = 1 }):Play()
TweenService:Create(hum, TweenInfo.new(1.2), { Volume = 0 }):Play()
task.wait(1.3)
gui:Destroy()
hum:Destroy()
buzz:Destroy()
