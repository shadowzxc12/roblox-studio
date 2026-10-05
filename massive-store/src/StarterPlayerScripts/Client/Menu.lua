--[[
	Menu (Game place). The real main menu lives in the LOBBY place; in the store you get:
	  arrival screen   "entering the store" while the server drops you in (reserved servers),
	                   or the STUDIO TEST panel (pick a mode) when you press Play in Studio
	  pause menu       [P] / the MENU button: resume, loadout, missions, settings, back to lobby
	  pages            LOCKER, MISSIONS, SETTINGS (Client/Pages, same as the lobby)
	The 3D MenuScene plays behind the arrival screen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local UI = require(script.Parent.UI)
local ClientState = require(script.Parent.ClientState)
local Audio = require(script.Parent.Audio)
local MenuScene = require(script.Parent.MenuScene)
local Atmosphere = require(script.Parent.Atmosphere)
local Pages = require(script.Parent.Pages)
local ViewModel = require(script.Parent.ViewModel)

local Menu = {}

local player = Players.LocalPlayer
local C = UI.C
local make = UI.make

local gui, root -- arrival
local pauseGui, pauseRoot, pausePanel, pageFrame, pageContent, confirmBox, menuButton
local toastFn = function(_t, _k) end

local studio = RunService:IsStudio()
local lobbyReady = Config.Places.Lobby ~= 0 and not studio

--============================ LOGO ============================--
local function logo(parent: Instance, pos: UDim2)
	local box = make("Frame", { Name = "Logo", BackgroundTransparency = 1, Position = pos, Size = UDim2.fromOffset(460, 180) }, parent)
	UI.text(box, "OPEN 24/7  ·  NO EXIT", 12, C.Accent, UI.Mono, { Position = UDim2.fromOffset(2, 0), Size = UDim2.new(1, 0, 0, 16) })
	UI.text(box, "MASSIVE STORE", 72, C.Text, UI.Title, { Position = UDim2.fromOffset(-4, 14), Size = UDim2.new(1, 0, 0, 82) })
	local tag = make("Frame", { BackgroundColor3 = C.Danger, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 102), Size = UDim2.fromOffset(220, 48) }, box)
	UI.corner(tag, 4)
	UI.text(tag, "LOCUST", 36, C.Text, UI.Title, { Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -40, 1, 0) })
	local hole = make("Frame", { BackgroundColor3 = C.Bg, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -22, 0.5, 0), Size = UDim2.fromOffset(11, 11), ZIndex = 3 }, tag)
	UI.corner(hole)
	return box
end
Menu.Logo = logo

--============================ ARRIVAL / STUDIO TEST ============================--
local function buildArrival()
	gui, root = UI.screen("MSL_Menu", 10)
	local shade = make("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Size = UDim2.new(0, 760, 1, 0) }, root)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.6, 0.4), NumberSequenceKeypoint.new(1, 1) }) }, shade)
	logo(root, UDim2.fromOffset(64, 52))
	local col = make("Frame", { Name = "Modes", BackgroundTransparency = 1, Position = UDim2.fromOffset(64, 250), Size = UDim2.fromOffset(380, 420) }, root)
	UI.list(col, 10)
	if studio or not lobbyReady then
		UI.text(col, "STUDIO TEST  ·  PICK A MODE", 11, C.Accent, UI.Mono, { Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 0 })
		for i, id in Config.ModeOrder do
			local m = Config.Modes[id]
			local b = UI.button(col, { Name = "Play" .. id, Text = "PLAY " .. m.Name, Sub = m.Desc, Style = if i == 1 then "Primary" else "Dark", Accent = i ~= 1, Size = UDim2.fromOffset(380, if i == 1 then 72 else 60), TextSize = if i == 1 then 28 else 22, LayoutOrder = i })
			b.Activated:Connect(function()
				Net.Event("Play"):FireServer(id)
			end)
		end
		UI.text(col, "Published games start in the LOBBY place (party, shop, outfits) and teleport here. Set Config.Places to link them.", 11, C.Muted, UI.Body, { Size = UDim2.new(1, 0, 0, 44), TextWrapped = true, LayoutOrder = 20 })
	else
		UI.text(col, "ENTERING THE STORE...", 30, C.Text, UI.Title, { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1 })
		UI.text(col, "Your store is being stocked. Stay close to your party.", 13, C.Muted, UI.Body, { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 2 })
		local back = UI.button(col, { Text = "BACK TO LOBBY", Accent = true, Size = UDim2.fromOffset(380, 56), LayoutOrder = 3 })
		back.Activated:Connect(function()
			Net.Event("Lobby"):FireServer("Return")
		end)
	end
end

--============================ PAUSE MENU ============================--
local function closePage()
	pageFrame.Visible = false
	Pages.Close()
end

local function openPage(name: string)
	pausePanel.Visible = false
	pageFrame.Visible = true
	Pages.Render(name, pageContent)
	Audio.Play("Open")
end

function Menu.TogglePause(on: boolean?)
	if on == nil then
		on = not pauseGui.Enabled
	end
	if on and not ClientState.InRun() then
		return
	end
	pauseGui.Enabled = on
	pausePanel.Visible = on
	closePage()
	confirmBox.Visible = false
	ClientState.SetBusy("Pause", on)
	Audio.Play(if on then "Open" else "Close")
end

local function buildPause()
	pauseGui, pauseRoot = UI.screen("MSL_Pause", 30)
	pauseGui.Enabled = false
	local dim = make("Frame", { BackgroundColor3 = C.Bg, BackgroundTransparency = 0.25, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, pauseRoot)
	dim.Active = true
	pausePanel = make("Frame", { Name = "Panel", BackgroundTransparency = 1, Position = UDim2.fromOffset(64, 0), Size = UDim2.new(0, 400, 1, 0) }, pauseRoot)
	logo(pausePanel, UDim2.fromOffset(0, 52))
	local col = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 250), Size = UDim2.fromOffset(380, 420) }, pausePanel)
	UI.list(col, 10)
	local resume = UI.button(col, { Text = "RESUME", Sub = "Back into the aisles", Key = "P", Style = "Primary", Size = UDim2.fromOffset(380, 72), TextSize = 30, LayoutOrder = 1 })
	resume.Activated:Connect(function()
		Menu.TogglePause(false)
	end)
	for i, def in { { "LOADOUT & OUTFITS", "Equip cosmetics", "LOCKER" }, { "DAILY MISSIONS", "Progress and stats", "MISSIONS" }, { "SETTINGS", "Audio · effects · controls", "SETTINGS" } } do
		local b = UI.button(col, { Text = def[1], Sub = def[2], Accent = true, Size = UDim2.fromOffset(380, 56), LayoutOrder = 1 + i })
		b.Activated:Connect(function()
			openPage(def[3])
		end)
	end
	local leave = UI.button(col, { Text = if lobbyReady then "BACK TO LOBBY" else "LEAVE THE STORE", Sub = "Your supplies drop in a bag where you stand", Style = "Danger", Size = UDim2.fromOffset(380, 56), LayoutOrder = 9 })
	leave.Activated:Connect(function()
		confirmBox.Visible = true
	end)

	-- page host
	pageFrame = make("Frame", { Name = "Page", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false }, pauseRoot)
	local back = UI.button(pageFrame, { Text = "←  BACK", Font = UI.Mono, Position = UDim2.fromOffset(48, 36), Size = UDim2.fromOffset(100, 36), TextSize = 13 })
	back.Activated:Connect(function()
		closePage()
		pausePanel.Visible = true
	end)
	pageContent = make("Frame", { Name = "Content", BackgroundTransparency = 1, Position = UDim2.fromOffset(168, 28), Size = UDim2.new(1, -216, 1, -76) }, pageFrame)

	-- confirm
	confirmBox = UI.panel(pauseRoot, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(460, 200), Visible = false, ZIndex = 5 }, 10)
	UI.stroke(confirmBox, C.Danger, 1, 0.4)
	UI.text(confirmBox, "LEAVE THE STORE?", 30, C.Text, UI.Title, { Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 36), TextXAlignment = Enum.TextXAlignment.Center })
	UI.text(confirmBox, "You'll drop your supplies in a bag where you stand.\nXP, credits and missions are kept.", 12, C.Muted, UI.Body, { Position = UDim2.fromOffset(20, 60), Size = UDim2.new(1, -40, 0, 40), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true })
	local yes = UI.button(confirmBox, { Text = if lobbyReady then "LOBBY" else "LEAVE", Style = "Danger", Size = UDim2.fromOffset(190, 52), Position = UDim2.new(0.5, -200, 1, -72), TextSize = 22 })
	local no = UI.button(confirmBox, { Text = "STAY", Style = "Primary", Size = UDim2.fromOffset(190, 52), Position = UDim2.new(0.5, 10, 1, -72), TextSize = 22 })
	no.Activated:Connect(function()
		confirmBox.Visible = false
	end)
	yes.Activated:Connect(function()
		confirmBox.Visible = false
		Menu.TogglePause(false)
		Net.Event("Lobby"):FireServer("Return")
	end)

	-- small MENU button in the HUD
	local _, hudRoot = UI.screen("MSL_MenuButton", 7)
	menuButton = UI.button(hudRoot, { Name = "MenuButton", Text = "MENU  [P]", Font = UI.Mono, Size = UDim2.fromOffset(96, 26), Position = UDim2.fromOffset(24, 124), TextSize = 11, Style = "Ghost" })
	menuButton.Activated:Connect(function()
		Menu.TogglePause(true)
	end)
	menuButton.Visible = false
end

--============================ SETTINGS ============================--
function Menu.ApplySettings(s)
	if s.Music ~= nil then
		Audio.SetMusic(s.Music)
	end
	if s.SFX ~= nil then
		Audio.SetSFX(s.SFX)
	end
	if s.CameraShake ~= nil then
		Atmosphere.SetShake(s.CameraShake)
		ViewModel.SetBob(s.CameraShake)
	end
	if s.Brightness ~= nil then
		Atmosphere.SetBrightness(s.Brightness)
	end
	if s.Sensitivity ~= nil then
		ViewModel.SetSensitivity(s.Sensitivity)
	end
	if s.Effects ~= nil then
		for _, e in game:GetService("CollectionService"):GetTagged("OptionalEffect") do
			if e:IsA("ParticleEmitter") or e:IsA("Trail") then
				e.Enabled = s.Effects
			end
		end
	end
end

--============================ SHOW / HIDE ============================--
function Menu.Show()
	ClientState.MenuOpen = true
	gui.Enabled = true
	menuButton.Visible = false
	Menu.TogglePause(false)
	Atmosphere.SetMenu(true)
	Audio.SetMenu(true)
	MenuScene.Start()
end

function Menu.Hide()
	ClientState.MenuOpen = false
	gui.Enabled = false
	menuButton.Visible = true
	MenuScene.Stop()
	Atmosphere.SetMenu(false)
	Audio.SetMenu(false)
end

function Menu.Init(toast)
	toastFn = toast or toastFn
	Pages.Toast = toastFn
	Pages.OnSetting = function(key, value)
		Menu.ApplySettings({ [key] = value })
	end
	Pages.Init()
	buildArrival()
	buildPause()
	ClientState.DataChanged:Connect(function(d)
		if d and d.Settings and not Menu.SettingsApplied then
			Menu.SettingsApplied = true
			Menu.ApplySettings(d.Settings)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or ClientState.Busy.Build then
			return -- [P] repairs in build mode
		end
		if (input.KeyCode == Enum.KeyCode.P or input.KeyCode == Enum.KeyCode.ButtonStart) and ClientState.InRun() then
			Menu.TogglePause()
		end
	end)
end

return Menu
