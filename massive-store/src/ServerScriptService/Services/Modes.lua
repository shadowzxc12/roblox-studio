--[[
	Modes: which game mode this server runs, the PLAY button, the server browser and teleports.

	One place, many servers:
	  public servers           -> SURVIVAL
	  reserved servers         -> the mode in their TeleportData (INFECTION / HARDCORE / SOLO,
	                              or SURVIVAL when created from the menu)
	PLAY <mode>:
	  same mode as this server -> walk into the store here
	  other mode               -> join a listed server of that mode with space, or reserve a new one
	  SOLO                     -> always a brand-new private reserved server
	SERVERS lists running servers (MemoryStore registry, refreshed every 15 s).
	In Studio teleports don't work: the first PLAY decides this test server's mode.
]]

local MemoryStoreService = game:GetService("MemoryStoreService")
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
local RateLimiter = require(script.Parent.RateLimiter)

local Modes = {}

local studio = RunService:IsStudio()
local limiter = RateLimiter.new(4, 6)
local listLimiter = RateLimiter.new(6, 10)
local teleporting: { [Player]: boolean } = {}
local lastList = {} -- key -> entry, from the latest GetServers call (server-side copy)

local function registry()
	return MemoryStoreService:GetSortedMap(Config.ServerRegistryName)
end

local function isReserved(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

function Modes.Resolve(): string
	if isReserved() then
		local first = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
		local data = first:GetJoinData().TeleportData
		if type(data) == "table" and type(data.Mode) == "string" and Config.Modes[data.Mode] then
			return data.Mode
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

local function registryKey(): string
	return if isReserved() then game.PrivateServerId else game.JobId
end

local function heartbeat(closing: boolean?)
	if studio then
		return
	end
	pcall(function()
		if closing then
			registry():RemoveAsync(registryKey())
			return
		end
		registry():SetAsync(registryKey(), {
			JobId = game.JobId,
			Mode = State.Mode,
			Night = State.Night,
			Phase = State.Phase,
			Players = #Players:GetPlayers(),
			Max = State.ModeInfo.MaxPlayers or Config.MaxPlayers,
			Reserved = isReserved(),
			AccessCode = Modes.AccessCode,
			Updated = os.time(),
		}, 60)
	end)
end

local function fetchServers()
	local ok, items = pcall(function()
		return registry():GetRangeAsync(Enum.SortDirection.Ascending, 100)
	end)
	local out = {}
	if ok and type(items) == "table" then
		for _, item in items do
			local v = item.value
			if type(v) == "table" and Config.Modes[v.Mode] and v.Mode ~= "Solo" and os.time() - (v.Updated or 0) < 60 then
				v.Key = item.key
				table.insert(out, v)
			end
		end
	end
	return out
end

local function teleport(player: Player, options: TeleportOptions)
	teleporting[player] = true
	State.Notify(player, "Heading to another store...", "Info")
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { player }, options)
	end)
	if not ok then
		teleporting[player] = nil
		State.Notify(player, "Teleport failed: " .. tostring(err), "Warn")
	end
	return ok
end

local function newReserved(player: Player, mode: string)
	local ok, code = pcall(function()
		return TeleportService:ReserveServer(game.PlaceId)
	end)
	if not ok or not code then
		State.Notify(player, "Couldn't create a server right now. Try again!", "Warn")
		return false
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = code
	options:SetTeleportData({ Mode = mode, AccessCode = if mode == "Solo" then nil else code })
	return teleport(player, options)
end

local function enterHere(player: Player)
	if player:GetAttribute("InRun") then
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

function Modes.Play(player: Player, mode: string)
	if teleporting[player] or not Config.Modes[mode] then
		return
	end
	if mode == State.Mode and mode ~= "Solo" then
		enterHere(player)
		return
	end
	if mode == "Solo" and State.Mode == "Solo" and #Players:GetPlayers() == 1 then
		enterHere(player)
		return
	end
	if studio then
		-- no teleports in Studio: the first PLAY picks the mode for this test server
		local anyoneIn = false
		for _, p in Players:GetPlayers() do
			if p:GetAttribute("InRun") then
				anyoneIn = true
			end
		end
		if not anyoneIn and not State.RunActive then
			Modes.Set(mode)
			enterHere(player)
		else
			State.Notify(player, "Studio test: this server is running " .. State.ModeInfo.Name .. ". Stop and start again to test another mode.", "Warn")
			enterHere(player)
		end
		return
	end
	if mode ~= "Solo" then
		-- join a running server of that mode with free slots
		for _, entry in fetchServers() do
			if entry.Mode == mode and entry.Players < (entry.Max or Config.MaxPlayers) and entry.JobId ~= game.JobId then
				local options = Instance.new("TeleportOptions")
				if entry.Reserved and entry.AccessCode then
					options.ReservedServerAccessCode = entry.AccessCode
				elseif not entry.Reserved then
					options.ServerInstanceId = entry.JobId
				else
					continue
				end
				options:SetTeleportData({ Mode = mode, AccessCode = entry.AccessCode })
				teleport(player, options)
				return
			end
		end
	end
	newReserved(player, mode)
end

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

function Modes.Init()
	Modes.Set("Survival")
	if isReserved() then
		-- reserved servers learn their mode (and access code for the browser) from the first arrival
		task.spawn(function()
			Modes.Set(Modes.Resolve())
			local first = Players:GetPlayers()[1]
			local data = first and first:GetJoinData().TeleportData
			if type(data) == "table" and type(data.AccessCode) == "string" then
				Modes.AccessCode = data.AccessCode
			end
		end)
	end

	Net.Event("Play").OnServerEvent:Connect(function(player, mode)
		if limiter:Allow(player) and type(mode) == "string" then
			Modes.Play(player, mode)
		end
	end)

	Net.Event("Menu").OnServerEvent:Connect(function(player, action)
		if not limiter:Allow(player) then
			return
		end
		if action == "ReturnToMenu" then
			Modes.ReturnToMenu(player)
		end
	end)

	Net.Function("GetServers").OnServerInvoke = function(player)
		if not listLimiter:Allow(player) then
			return nil
		end
		local list = if studio then {} else fetchServers()
		local out = {}
		table.clear(lastList)
		for _, e in list do
			lastList[e.Key] = e
			table.insert(out, {
				Key = e.Key,
				Mode = e.Mode,
				Night = e.Night,
				Phase = e.Phase,
				Players = e.Players,
				Max = e.Max,
				Here = e.JobId == game.JobId,
			})
		end
		-- always show this server
		local hereListed = false
		for _, e in out do
			if e.Here then
				hereListed = true
			end
		end
		if not hereListed then
			table.insert(out, 1, {
				Key = "here",
				Mode = State.Mode,
				Night = State.Night,
				Phase = State.Phase,
				Players = #Players:GetPlayers(),
				Max = State.ModeInfo.MaxPlayers or Config.MaxPlayers,
				Here = true,
			})
		end
		return out
	end

	Net.Function("JoinServer").OnServerInvoke = function(player, key)
		if not limiter:Allow(player) or type(key) ~= "string" then
			return false
		end
		if key == "here" then
			enterHere(player)
			return true
		end
		local e = lastList[key]
		if not e then
			return false
		end
		if e.JobId == game.JobId then
			enterHere(player)
			return true
		end
		if studio then
			return false
		end
		local options = Instance.new("TeleportOptions")
		if e.Reserved then
			if not e.AccessCode then
				return false
			end
			options.ReservedServerAccessCode = e.AccessCode
		else
			options.ServerInstanceId = e.JobId
		end
		options:SetTeleportData({ Mode = e.Mode, AccessCode = e.AccessCode })
		return teleport(player, options)
	end

	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		if teleporting[player] then
			teleporting[player] = nil
			State.Notify(player, "Teleport failed (" .. tostring(message) .. ")", "Warn")
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		teleporting[player] = nil
	end)

	task.spawn(function()
		while true do
			heartbeat(false)
			task.wait(15)
		end
	end)
	game:BindToClose(function()
		heartbeat(true)
	end)
end

return Modes
