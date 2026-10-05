--[[
	Modes (Game place): which game mode this store server runs, who enters, and the way back
	to the lobby.

	Normal flow (published experience):
	  Lobby -> START A RUN -> a reserved server of this place is created for you / your party.
	  TeleportData = { Mode, Rules, Solo, PartyKey, Leader, Members }.
	  The first arrival sets the mode; everybody who arrives walks straight into the store.
	  BACK TO LOBBY (results screen or pause menu) teleports you back; players leaving together
	  from the results screen go in one group so the lobby rebuilds their party.

	Public servers of this place (somebody joined it directly) send players to the lobby.
	In Studio (no teleports) the client shows a STUDIO TEST panel: the first PLAY picks the mode.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local State = require(script.Parent.State)
local Survival = require(script.Parent.Survival)
local Inventory = require(script.Parent.Inventory)
local Data = require(script.Parent.Data)
local RateLimiter = require(script.Parent.RateLimiter)

local Modes = {}

local studio = RunService:IsStudio()
local limiter = RateLimiter.new(4, 6)
local teleporting: { [Player]: boolean } = {}
local lobbyVotes: { [Player]: boolean } = {}

Modes.Join = nil -- TeleportData of the first arrival

local function isReserved(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end
Modes.IsReserved = isReserved

local function lobbyReady(): boolean
	return not studio and Config.Places.Lobby ~= 0
end

function Modes.Resolve(): string
	if isReserved() then
		local first = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
		local data = first:GetJoinData().TeleportData
		if type(data) == "table" then
			Modes.Join = data
			if type(data.Mode) == "string" and Config.Modes[data.Mode] then
				return data.Mode
			end
		end
	end
	return "Survival"
end

function Modes.Set(mode: string)
	State.Mode = mode
	State.ModeInfo = Config.Modes[mode]
	State.SetAttr("Mode", mode)
	State.SetAttr("ModeName", State.ModeInfo.Name)
end

local function enterHere(player: Player)
	if player:GetAttribute("InRun") or teleporting[player] then
		return
	end
	local Director = require(script.Parent.Director)
	player:SetAttribute("InRun", true)
	if State.RunActive then
		Director.JoinRun(player, true)
	else
		Director.PendingStart = true
	end
end
Modes.Enter = enterHere

-- Studio test servers: the first PLAY decides the mode
function Modes.Play(player: Player, mode: string)
	if not Config.Modes[mode] or player:GetAttribute("InRun") then
		return
	end
	if isReserved() or lobbyReady() then
		-- real servers: you are already in the right store
		enterHere(player)
		return
	end
	local anyoneIn = false
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("InRun") then
			anyoneIn = true
		end
	end
	if not anyoneIn and not State.RunActive then
		Modes.Set(mode)
	elseif mode ~= State.Mode then
		State.Notify(player, "Studio test: this server is running " .. State.ModeInfo.Name .. ". Stop and start again to test another mode.", "Warn")
	end
	enterHere(player)
end

-- leave the store but stay on this server (Studio / no lobby configured)
function Modes.ReturnToMenu(player: Player)
	if not player:GetAttribute("InRun") then
		return
	end
	local pos = Survival.Position(player)
	require(script.Parent.Carts).Release(player)
	if pos then
		Inventory.DropBag(player, pos)
	end
	Survival.LeaveRun(player)
end

local function teleportToLobby(group: { Player }, keepParty: boolean)
	local list = {}
	for _, p in group do
		if p.Parent and not teleporting[p] then
			table.insert(list, p)
			teleporting[p] = true
			Net.Event("Teleporting"):FireClient(p, { Lobby = true, Members = #group })
		end
	end
	if #list == 0 then
		return
	end
	local options = Instance.new("TeleportOptions")
	local leader = list[1]
	local join = Modes.Join
	if type(join) == "table" and type(join.Leader) == "number" then
		for _, p in list do
			if p.UserId == join.Leader then
				leader = p
			end
		end
	end
	options:SetTeleportData({
		PartyKey = if keepParty and #list > 1 then HttpService:GenerateGUID(false) else nil,
		Leader = leader.UserId,
		Rules = if type(join) == "table" then join.Rules else nil,
	})
	for _, p in list do
		Data.SaveNow(p)
	end
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(Config.Places.Lobby, list, options)
	end)
	if not ok then
		for _, p in list do
			teleporting[p] = nil
			Net.Event("Teleporting"):FireClient(p, { Cancel = true, Message = "Teleport failed: " .. tostring(err) })
		end
	end
end

-- results screen: everybody who picked BACK TO LOBBY goes together when the timer ends
-- (or right away once every player in the store voted)
function Modes.FlushLobbyVotes()
	local group = {}
	for p in lobbyVotes do
		if p.Parent then
			table.insert(group, p)
		end
	end
	table.clear(lobbyVotes)
	if #group > 0 then
		teleportToLobby(group, true)
	end
end

function Modes.BackToLobby(player: Player)
	if not lobbyReady() then
		Modes.ReturnToMenu(player)
		State.Notify(player, "No lobby in Studio — publish both places and set Config.Places.", "Info")
		return
	end
	if State.Phase == "Results" then
		lobbyVotes[player] = true
		local all = true
		for _, p in Players:GetPlayers() do
			if not lobbyVotes[p] and not teleporting[p] then
				all = false
			end
		end
		if all then
			Modes.FlushLobbyVotes()
		else
			State.Notify(player, "Heading back to the lobby when the results end...", "Info")
		end
		return
	end
	-- mid-run: drop your bag for the team and go
	Modes.ReturnToMenu(player)
	teleportToLobby({ player }, false)
end

function Modes.Init()
	Modes.Set("Survival")
	if isReserved() then
		task.spawn(function()
			Modes.Set(Modes.Resolve())
		end)
	end

	-- arrivals walk straight into the store (not in Studio: the test panel picks a mode there)
	local function arrived(player: Player)
		if studio and not isReserved() then
			return
		end
		if not isReserved() and lobbyReady() then
			-- somebody joined the store place directly: send them to the lobby
			task.delay(2, teleportToLobby, { player }, false)
			return
		end
		task.spawn(function()
			while player.Parent and not player:GetAttribute("DataLoaded") do
				task.wait(0.25)
			end
			-- give the reserved-server mode a moment to be read from the first arrival
			if isReserved() and not Modes.Join then
				task.wait(0.5)
			end
			if player.Parent then
				enterHere(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(arrived)
	for _, p in Players:GetPlayers() do
		arrived(p)
	end

	Net.Event("Play").OnServerEvent:Connect(function(player, mode)
		if limiter:Allow(player) and type(mode) == "string" then
			Modes.Play(player, mode)
		end
	end)

	Net.Event("Menu").OnServerEvent:Connect(function(player, action)
		if limiter:Allow(player) and action == "ReturnToMenu" then
			Modes.ReturnToMenu(player)
		end
	end)

	Net.Event("Lobby").OnServerEvent:Connect(function(player, action)
		if limiter:Allow(player) and action == "Return" then
			Modes.BackToLobby(player)
		end
	end)

	State.PhaseChanged:Connect(function(phase)
		if phase ~= "Results" then
			Modes.FlushLobbyVotes()
		end
	end)

	TeleportService.TeleportInitFailed:Connect(function(player, _result, message)
		if teleporting[player] then
			teleporting[player] = nil
			Net.Event("Teleporting"):FireClient(player, { Cancel = true, Message = "Teleport failed (" .. tostring(message) .. ")" })
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		teleporting[player] = nil
		lobbyVotes[player] = nil
	end)
end

return Modes
