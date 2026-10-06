--[[
	MASSIVE STORE: LOCUST — server entry point (the only server Script). ONE place, three roles:

	  Lobby  public servers: the parking lot, parties, cosmetics, shop. START A RUN reserves a
	         private server of THIS same place and teleports you / your party there.
	  Game   private (reserved) servers: the store. Arrivals walk straight in.
	  Both   Roblox Studio (no teleports): lobby and store run on the same server, and
	         START A RUN drops you straight into the store.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

Players.CharacterAutoLoads = false

local Services = script.Parent:WaitForChild("Services")
local State = require(Services.State)

local function isReserved(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

local role = if isReserved() then "Game" elseif RunService:IsStudio() then "Both" else "Lobby"
State.Role = role
State.SetAttr("Place", role)

local started = {}
local function init(service)
	if not started[service] then
		started[service] = true
		service.Init()
	end
end

if role ~= "Lobby" then
	require(script.Parent.GameServer).Start(init)
end
if role ~= "Game" then
	require(script.Parent.Lobby.LobbyServer).Start(init, role)
end

State.SetAttr("ServerReady", true)
print("[MassiveStore] server ready · " .. role)
