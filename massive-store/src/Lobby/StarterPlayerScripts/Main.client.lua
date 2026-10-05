--[[
	MASSIVE STORE: LOCUST — LOBBY place client.
	The party lineup in the parking lot + the lobby menus. Shares UI, Pages, Audio, the
	character animator and the teleport screen with the Game place.
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer

while not player:GetAttribute("LoadingDone") do
	player:GetAttributeChangedSignal("LoadingDone"):Wait()
end

local Client = script.Parent:WaitForChild("Client")
local UI = require(Client.UI)
local ClientState = require(Client.ClientState)
local Audio = require(Client.Audio)
local Pages = require(Client.Pages)
local CharacterAnimator = require(Client.CharacterAnimator)

local Lobby = script.Parent:WaitForChild("Lobby")
local LobbyCamera = require(Lobby.LobbyCamera)
local LobbyUI = require(Lobby.LobbyUI)

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
Audio.SetMenu(true)
Pages.Init()
Pages.OnSetting = function(key, value)
	if key == "Music" then
		Audio.SetMusic(value)
	elseif key == "SFX" then
		Audio.SetSFX(value)
	end
end
CharacterAnimator.Init()
LobbyCamera.Init()
LobbyUI.Init()

local applied = false
ClientState.DataChanged:Connect(function(d)
	if d and d.Settings and not applied then
		applied = true
		Audio.SetMusic(d.Settings.Music ~= false)
		Audio.SetSFX(d.Settings.SFX ~= false)
	end
end)
