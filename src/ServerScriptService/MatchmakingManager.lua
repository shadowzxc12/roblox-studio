--[[
	MatchmakingManager

	LOBBY servers (public servers):
	  - players pick a mode -> they enter that mode's queue on this lobby server
	  - every few seconds the queue looks for an OPEN match of the same mode (shared across ALL
	    servers through MemoryStoreService). If one has space, the queued players are teleported in.
	  - otherwise, once enough players are queued (or someone waited too long), a new Reserved
	    Server is created with TeleportService:ReserveServer and the players are teleported there.
	  - queued players see "Finding Players... 5/12"
	  Modes never mix: every match server is registered for exactly one mode.

	MATCH servers (reserved servers):
	  - read their mode from MemoryStore (written by the lobby that reserved them),
	    with TeleportData as a fallback
	  - report player count every few seconds so lobbies can fill them up
	  - "Main Menu" teleports the player back to a lobby (a public server of this place)

	STUDIO: TeleportService doesn't work in Studio, so pressing PLAY starts the match right
	inside the Studio server instead (handled by ServerMain through OnLocalMatch).
]]

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Modules.Config)
local RateLimiter = require(script.Parent.RateLimiter)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local MatchmakingManager = {}

local MM = Config.Matchmaking
local MAX = Config.Round.MaxPlayers

-- Memory store maps are created lazily: in an unpublished Studio place these calls can fail,
-- and every use below is wrapped in pcall.
local function infoMap()
	return MemoryStoreService:GetSortedMap("SC_MatchInfo_v1")
end
local function openMap(mode: string)
	return MemoryStoreService:GetSortedMap("SC_OpenMatches_v1_" .. mode)
end

local queues: { [string]: { { Player: Player, Since: number } } } = {}
for _, id in Config.ModeOrder do
	queues[id] = {}
end
local queuedMode: { [Player]: string } = {}
local teleporting: { [Player]: boolean } = {}
local limiter = RateLimiter.new(6, 10)

local function status(player: Player, payload)
	Remotes.MatchmakingStatus:FireClient(player, payload)
end

local function removeFromQueues(player: Player)
	local mode = queuedMode[player]
	queuedMode[player] = nil
	if mode then
		local q = queues[mode]
		for i = #q, 1, -1 do
			if q[i].Player == player then
				table.remove(q, i)
			end
		end
	end
end

-- Best open match of this mode with free space (prefers fuller matches so servers fill up).
local function findOpenMatch(mode: string)
	local ok, items = pcall(function()
		return openMap(mode):GetRangeAsync(Enum.SortDirection.Ascending, 50)
	end)
	if not ok or type(items) ~= "table" then
		return nil
	end
	local best = nil
	for _, item in items do
		local v = item.value
		if type(v) == "table" and type(v.AccessCode) == "string" and os.time() - (v.Updated or 0) < MM.MatchTTL then
			local count = v.Players or 0
			if count < MAX and (not best or count > best.Players) then
				best = { Key = item.key, AccessCode = v.AccessCode, Players = count }
			end
		end
	end
	return best
end

local function createMatch(mode: string)
	local ok, code, privateServerId = pcall(function()
		return TeleportService:ReserveServer(game.PlaceId)
	end)
	if not ok or not code then
		warn("[Matchmaking] ReserveServer failed: " .. tostring(code))
		return nil
	end
	local entry = { AccessCode = code, Players = 0, Updated = os.time(), Mode = mode }
	pcall(function()
		openMap(mode):SetAsync(privateServerId, entry, MM.MatchTTL)
	end)
	pcall(function()
		infoMap():SetAsync(privateServerId, { Mode = mode }, 6 * 3600)
	end)
	return { Key = privateServerId, AccessCode = code, Players = 0 }
end

local function teleportBatch(mode: string, batch: { Player }, match)
	for _, p in batch do
		removeFromQueues(p)
		teleporting[p] = true
		status(p, { State = "Teleporting", Mode = mode })
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = match.AccessCode
	options:SetTeleportData({ Mode = mode })
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, batch, options)
	end)
	if ok then
		-- tell other lobbies these slots are taken (the match will report the real number soon)
		pcall(function()
			openMap(mode):UpdateAsync(match.Key, function(old)
				if type(old) ~= "table" then
					return nil
				end
				old.Players = (old.Players or 0) + #batch
				return old
			end, MM.MatchTTL)
		end)
	else
		warn("[Matchmaking] Teleport failed: " .. tostring(err))
		for _, p in batch do
			teleporting[p] = nil
			if p.Parent then
				status(p, { State = "Failed", Mode = mode, Message = "Teleport failed, please try again." })
			end
		end
	end
end

local function matchmakingPass()
	for mode, queue in queues do
		-- clean up players who left / are teleporting
		for i = #queue, 1, -1 do
			local e = queue[i]
			if not e.Player.Parent or teleporting[e.Player] or queuedMode[e.Player] ~= mode then
				table.remove(queue, i)
			end
		end
		if #queue > 0 then
			local match = findOpenMatch(mode)
			local shown = math.min(#queue + (if match then match.Players else 0), MAX)
			for _, e in queue do
				status(e.Player, { State = "Searching", Mode = mode, Count = shown, Max = MAX })
			end
			local waited = os.clock() - queue[1].Since
			if not match and (#queue >= MM.MinToCreate or waited >= MM.MaxWait) then
				match = createMatch(mode)
			end
			if match then
				local space = MAX - match.Players
				local batch = {}
				for i = 1, math.min(space, #queue) do
					table.insert(batch, queue[i].Player)
				end
				if #batch > 0 then
					task.spawn(teleportBatch, mode, batch, match)
				end
			end
		end
	end
end

--[[ LOBBY ]]
-- onLocalMatch(player, mode): used in Studio, where teleports are impossible.
function MatchmakingManager.StartLobby(onLocalMatch: (Player, string) -> ())
	local studio = RunService:IsStudio()

	Remotes.GameModeSelected.OnServerEvent:Connect(function(player, mode)
		if not limiter:Allow(player) then
			return
		end
		if type(mode) ~= "string" or not Config.Modes[mode] then
			return
		end
		if player:GetAttribute("InMatch") or teleporting[player] then
			return
		end
		if studio then
			onLocalMatch(player, mode)
			return
		end
		removeFromQueues(player)
		queuedMode[player] = mode
		table.insert(queues[mode], { Player = player, Since = os.clock() })
		status(player, { State = "Searching", Mode = mode, Count = #queues[mode], Max = MAX })
	end)

	Remotes.CancelMatchmaking.OnServerEvent:Connect(function(player)
		if teleporting[player] then
			return
		end
		removeFromQueues(player)
		status(player, { State = "Cancelled" })
	end)

	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		if teleporting[player] then
			teleporting[player] = nil
			status(player, { State = "Failed", Message = "Teleport failed (" .. tostring(message) .. "). Try again!" })
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		removeFromQueues(player)
		teleporting[player] = nil
	end)

	if not studio then
		task.spawn(function()
			while true do
				task.wait(MM.PollInterval)
				local ok, err = pcall(matchmakingPass)
				if not ok then
					warn("[Matchmaking] " .. tostring(err))
				end
			end
		end)
	end
end

--[[ MATCH SERVER ]]

function MatchmakingManager.IsMatchServer(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

-- Which mode is this reserved server for?
function MatchmakingManager.ResolveMatchMode(): string
	for _ = 1, 3 do
		local ok, info = pcall(function()
			return infoMap():GetAsync(game.PrivateServerId)
		end)
		if ok and type(info) == "table" and Config.Modes[info.Mode] then
			return info.Mode
		end
		task.wait(1)
	end
	local first = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
	local data = first:GetJoinData().TeleportData
	if type(data) == "table" and type(data.Mode) == "string" and Config.Modes[data.Mode] then
		return data.Mode
	end
	return "Normal"
end

-- Keeps this match visible to lobbies with an up-to-date player count.
function MatchmakingManager.StartMatchHeartbeat(mode: string)
	local key = game.PrivateServerId
	local function report(closing: boolean)
		pcall(function()
			openMap(mode):UpdateAsync(key, function(old)
				if type(old) ~= "table" then
					return nil -- we never had an entry (or it expired): nothing to update
				end
				old.Players = if closing then MAX else #Players:GetPlayers()
				old.Updated = os.time()
				return old
			end, MM.MatchTTL)
		end)
	end
	task.spawn(function()
		while true do
			report(false)
			task.wait(MM.HeartbeatInterval)
		end
	end)
	game:BindToClose(function()
		pcall(function()
			openMap(mode):RemoveAsync(key)
		end)
	end)
end

-- Back to a lobby. Returns false if the teleport could not start.
function MatchmakingManager.SendToLobby(player: Player): boolean
	if RunService:IsStudio() then
		return false
	end
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { player })
	end)
	if not ok then
		warn("[Matchmaking] Lobby teleport failed: " .. tostring(err))
	end
	return ok
end

return MatchmakingManager
