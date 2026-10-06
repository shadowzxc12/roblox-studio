--[[
	LobbyServer: the lobby part of the place — profile, party, cosmetics, shop, missions.
	Nothing here is a run. In Studio ("Both") the store runs on the same server, so a launch
	puts the party straight into it instead of teleporting.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Services = script.Parent.Parent:WaitForChild("Services")

local LobbyServer = {}

function LobbyServer.Start(init: (any) -> (), role: string)
	local State = require(Services.State)
	local Data = require(Services.Data)
	local Progress = require(Services.Progress)
	local Shop = require(Services.Shop)
	local Party = require(script.Parent.Party)
	local LobbyWorld = require(script.Parent.LobbyWorld)

	LobbyWorld.Build()
	init(Data)
	init(Progress)
	init(Shop)
	Party.Init()
	LobbyWorld.Init(Party, Shop)

	-- outfits / titles need the profile: re-apply once it is loaded
	Data.Loaded:Connect(function(player)
		if not player:GetAttribute("InRun") then
			Shop.Apply(player)
		end
	end)

	if role == "Both" then
		-- Studio: the store is on this server — walk the party in
		local Modes = require(Services.Modes)
		Party.LocalLaunch = function(going: { Player }, mode: string)
			local anyoneIn = false
			for _, p in game:GetService("Players"):GetPlayers() do
				if p:GetAttribute("InRun") then
					anyoneIn = true
				end
			end
			if not anyoneIn and not State.RunActive then
				Modes.Set(mode)
			elseif State.Mode ~= mode then
				for _, p in going do
					State.Notify(p, "Studio: this server's store already runs " .. State.ModeInfo.Name .. " — joining it.", "Info")
				end
			end
			for _, p in going do
				Modes.Enter(p)
			end
		end
	else
		Net.Function("GetPlan").OnServerInvoke = function()
			return nil
		end
	end
end

return LobbyServer
