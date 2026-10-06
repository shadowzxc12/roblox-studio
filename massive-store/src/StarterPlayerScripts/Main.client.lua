--[[
	MASSIVE STORE: LOCUST — client entry point (the only LocalScript besides the loading screen).
	Starts every controller and switches between the LOBBY (parking lot, party, shop) and the
	STORE (first-person HUD). Lobby and store are one place: see ServerScriptService/Main.
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
local CharacterAnimator = require(Client.CharacterAnimator)
local ViewModel = require(Client.ViewModel)
local TeleportScreen = require(Client.TeleportScreen)
local ShelfDresser = require(Client.ShelfDresser)
local PromptUI = require(Client.PromptUI)
local HUD = require(Client.HUD)
local InventoryUI = require(Client.InventoryUI)
local BuildUI = require(Client.BuildUI)
local MapUI = require(Client.MapUI)
local CameraFX = require(Client.CameraFX)
local Controls = require(Client.Controls)
local Menu = require(Client.Menu)
local Pages = require(Client.Pages)

local Lobby = script.Parent:WaitForChild("Lobby")
local LobbyCamera = require(Lobby.LobbyCamera)
local LobbyUI = require(Lobby.LobbyUI)

-- what this server is: "Lobby" (public), "Game" (a private store) or "Both" (Studio)
local role = ReplicatedStorage:GetAttribute("Place")
while not role do
	ReplicatedStorage:GetAttributeChangedSignal("Place"):Wait()
	role = ReplicatedStorage:GetAttribute("Place")
end
local hasLobby = role ~= "Game"

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
CharacterAnimator.Init()
ViewModel.Init()
ShelfDresser.Init()
PromptUI.Init()
HUD.Init()
InventoryUI.Init()
BuildUI.Init()
MapUI.Init()
CameraFX.Init()
Controls.Init()
Menu.Init(HUD.Toast)
LobbyCamera.Init()
LobbyUI.Init()

-- one toast at a time: the lobby's while you're in the parking lot, the HUD's in the store
local function toast(text: string, kind: string?)
	if hasLobby and not ClientState.InRun() then
		LobbyUI.Toast(text, kind)
	else
		HUD.Toast(text, kind)
	end
end
HUD.ShouldToast = function()
	return not hasLobby or ClientState.InRun()
end
Pages.Toast = toast

-- server cues: sounds + screen effects
Net.Event("Cue").OnClientEvent:Connect(function(kind, position, extra)
	Audio.Cue(kind, position, extra)
	HUD.Cue(kind, position, extra)
	if kind == "OpenBuild" then
		BuildUI.Toggle(true)
	end
end)

-- teleports (back to the lobby): the receipt screen
Net.Event("Teleporting").OnClientEvent:Connect(function(info)
	if info.Cancel then
		TeleportScreen.Hide()
		if info.Message then
			toast(info.Message, "Warn")
		end
	else
		TeleportScreen.Show(info)
	end
end)

local function refresh()
	local inRun = player:GetAttribute("InRun") == true
	LobbyUI.SetVisible(hasLobby and not inRun)
	LobbyCamera.SetActive(hasLobby and not inRun)
	Atmosphere.SetLobby(hasLobby and not inRun)
	-- the player list also opens on Tab: off in the store so Tab is only the inventory
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, not inRun)
	end)
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
		if hasLobby then
			Menu.HideForLobby()
		else
			Menu.Show() -- a private store: "entering the store..." until the server walks you in
		end
	end
end
player:GetAttributeChangedSignal("InRun"):Connect(refresh)
refresh()
