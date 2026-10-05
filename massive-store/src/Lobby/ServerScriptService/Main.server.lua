--[[
	MASSIVE STORE: LOCUST — LOBBY place server.
	The lobby is where you start: profile, party, cosmetics, shop, missions.
	Nothing here is a run; START A RUN teleports you (or your party) into a private store
	server of the Game place (see Lobby/Party).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Services = script.Parent:WaitForChild("Services")
local State = require(Services.State)
local Data = require(Services.Data)
local Progress = require(Services.Progress)
local Shop = require(Services.Shop)

local Lobby = script.Parent:WaitForChild("Lobby")
local Party = require(Lobby.Party)
local LobbyWorld = require(Lobby.LobbyWorld)

Players.CharacterAutoLoads = true
State.SetAttr("Place", "Lobby")

LobbyWorld.Build()
Data.Init()
Progress.Init()
Shop.Init()
Party.Init()
LobbyWorld.Init(Party, Shop)

-- outfits / titles need the profile: re-apply once it is loaded
Data.Loaded:Connect(function(player)
	Shop.Apply(player)
end)

-- the lobby has no store: answer the plan request with nothing
Net.Function("GetPlan").OnServerInvoke = function()
	return nil
end

State.SetAttr("ServerReady", true)
