--[[
	MASSIVE STORE: LOCUST — client entry point (the only LocalScript besides the loading screen).
	Starts every controller and switches between the 3D main menu and the in-store HUD.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer

-- wait for the loading screen
while not player:GetAttribute("LoadingDone") do
	player:GetAttributeChangedSignal("LoadingDone"):Wait()
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Client = script.Parent:WaitForChild("Client")
local UI = require(Client.UI)
local ClientState = require(Client.ClientState)
local Audio = require(Client.Audio)
local Atmosphere = require(Client.Atmosphere)
local LocustAnimator = require(Client.LocustAnimator)
local PromptUI = require(Client.PromptUI)
local HUD = require(Client.HUD)
local InventoryUI = require(Client.InventoryUI)
local BuildUI = require(Client.BuildUI)
local MapUI = require(Client.MapUI)
local CameraFX = require(Client.CameraFX)
local Controls = require(Client.Controls)
local Menu = require(Client.Menu)

-- our own HUD replaces these
for _, t in { Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health } do
	pcall(function()
		StarterGui:SetCoreGuiEnabled(t, false)
	end)
end

UI.Init()
UI.Sound = function(name)
	Audio.Play(name)
end
ClientState.Init()
Audio.Init()
Atmosphere.Init()
LocustAnimator.Init()
PromptUI.Init()
HUD.Init()
InventoryUI.Init()
BuildUI.Init()
MapUI.Init()
CameraFX.Init()
Controls.Init()
Menu.Init(HUD.Toast)

-- server cues: sounds + screen effects
Net.Event("Cue").OnClientEvent:Connect(function(kind, position, extra)
	Audio.Cue(kind, position, extra)
	HUD.Cue(kind, position, extra)
	if kind == "OpenBuild" then
		BuildUI.Toggle(true)
	end
end)

local function refresh()
	local inRun = player:GetAttribute("InRun") == true
	if inRun then
		Menu.Hide()
		HUD.SetVisible(true)
		InventoryUI.SetVisible(true)
		BuildUI.SetVisible(true)
		MapUI.SetVisible(true)
		Controls.SetVisible(true)
		CameraFX.Reset()
	else
		HUD.SetVisible(false)
		InventoryUI.SetVisible(false)
		BuildUI.SetVisible(false)
		MapUI.SetVisible(false)
		Controls.SetVisible(false)
		Menu.Show()
	end
end
player:GetAttributeChangedSignal("InRun"):Connect(refresh)
refresh()
