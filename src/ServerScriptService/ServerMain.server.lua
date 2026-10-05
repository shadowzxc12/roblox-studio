--[[
	ServerMain: the only server Script. It boots every system in order.

	Server types:
	  "Lobby"  public servers: 3D menu, shop, settings, matchmaking
	  "Match"  reserved servers created by matchmaking: one game mode, rounds forever
	Clients read ReplicatedStorage attribute "ServerType" to know which UI to show.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local DataManager = require(script.Parent.DataManager)
local RoleManager = require(script.Parent.RoleManager)
local ShopManager = require(script.Parent.ShopManager)
local RoundManager = require(script.Parent.RoundManager)
local MatchmakingManager = require(script.Parent.MatchmakingManager)
local RateLimiter = require(script.Parent.RateLimiter)

DataManager.Init()
RoleManager.Init()
ShopManager.Init()

local menuLimiter = RateLimiter.new(3, 5)

local function notify(player: Player, text: string)
	Remotes.Notify:FireClient(player, text)
end

if MatchmakingManager.IsMatchServer() then
	--=========================== MATCH SERVER ===========================--
	ReplicatedStorage:SetAttribute("ServerType", "Match")
	local mode = MatchmakingManager.ResolveMatchMode()
	ReplicatedStorage:SetAttribute("GameMode", mode)

	-- everyone who arrives here is in the match
	local function join(p: Player)
		p:SetAttribute("InMatch", true)
	end
	Players.PlayerAdded:Connect(join)
	for _, p in Players:GetPlayers() do
		join(p)
	end

	MatchmakingManager.StartMatchHeartbeat(mode)
	RoundManager.Start(mode)

	Remotes.ReturnToMenu.OnServerEvent:Connect(function(player)
		if not menuLimiter:Allow(player) then
			return
		end
		notify(player, "Going back to the lobby...")
		if not MatchmakingManager.SendToLobby(player) then
			notify(player, "Couldn't reach the lobby. Try again in a moment!")
		end
	end)
else
	--=========================== LOBBY SERVER ===========================--
	ReplicatedStorage:SetAttribute("ServerType", "Lobby")
	RoundManager.SetLobbyState()

	-- Studio only: no teleports possible, so the match runs right here.
	local function localMatch(player: Player, mode: string)
		local running = RoundManager.GetMode()
		if running and running ~= mode then
			notify(player, "Studio test: this server is already running " .. running .. ". Stop and start again to test another mode.")
			Remotes.MatchmakingStatus:FireClient(player, { State = "Cancelled" })
			return
		end
		ReplicatedStorage:SetAttribute("GameMode", mode)
		player:SetAttribute("InMatch", true)
		RoundManager.Start(mode)
		Remotes.MatchmakingStatus:FireClient(player, { State = "Joined", Mode = mode })
		if #Players:GetPlayers() < 2 then
			notify(player, "Studio test: start a 2+ player test (Test > Clients and Servers) to play a round.")
		end
	end
	MatchmakingManager.StartLobby(localMatch)

	Remotes.ReturnToMenu.OnServerEvent:Connect(function(player)
		if not menuLimiter:Allow(player) then
			return
		end
		if player:GetAttribute("InMatch") then
			RoundManager.RemovePlayer(player)
		end
	end)
end

if RunService:IsStudio() then
	print("[StudChase] Server ready as " .. tostring(ReplicatedStorage:GetAttribute("ServerType")))
end
