--[[
	ClientMain: the only client LocalScript (besides the loading screen in ReplicatedFirst).
	Waits for the loading screen, starts every controller, and switches between
	the 3D main menu (not in a match) and the match HUD (in a match).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- wait for the loading screen to finish
while not player:GetAttribute("LoadingDone") do
	player:GetAttributeChangedSignal("LoadingDone"):Wait()
end

local ClientState = require(script.Parent.ClientState)
local PanelsController = require(script.Parent.PanelsController)
local UIController = require(script.Parent.UIController)
local MenuController = require(script.Parent.MenuController)

ClientState.Init()
UIController.Init()
PanelsController.Init(UIController.Toast)
MenuController.Init(UIController.Toast)

-- In a match server the server marks everyone InMatch; give it a moment to replicate.
if ReplicatedStorage:GetAttribute("ServerType") == "Match" then
	local t0 = os.clock()
	while not player:GetAttribute("InMatch") and os.clock() - t0 < 5 do
		task.wait(0.1)
	end
end

local function refresh()
	if player:GetAttribute("InMatch") then
		MenuController.Hide()
		UIController.SetVisible(true)
	else
		UIController.SetVisible(false)
		MenuController.Show()
	end
end
player:GetAttributeChangedSignal("InMatch"):Connect(refresh)
refresh()
