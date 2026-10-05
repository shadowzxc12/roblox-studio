--[[
	DataManager: loads, keeps and saves PlayerData with DataStoreService.

	Safety:
	- every DataStore call is wrapped in pcall with retries
	- a simple session lock (JobId + time) stops two servers from overwriting each other
	  (important because players teleport between lobby and match servers)
	- if loading fails, the player plays with temporary data that is NEVER saved,
	  so a DataStore outage can't wipe anyone's progress
	- saves on leave, every few minutes, and in BindToClose
	- clients never write data: they only receive read-only snapshots
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Modules.Config)
local Util = require(ReplicatedStorage.Modules.Util)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local DataManager = {}

local TEMPLATE = {
	Coins = 0,
	XP = 0,
	Level = 1,
	Wins = 0,
	Losses = 0,
	GamesPlayed = 0,
	Catches = 0,
	Infections = 0,
	SurvivalTime = 0,
	OwnedCosmetics = {},
	Equipped = { Trail = "", Aura = "", Title = "", TagEffect = "" },
	Settings = { Music = true, SoundEffects = true, ShowEffects = true, CameraShake = true },
}

local LOCK_TIMEOUT = 90 -- a lock older than this is considered dead
local LOAD_ATTEMPTS = if RunService:IsStudio() then 2 else 6
local AUTOSAVE_INTERVAL = 150

-- GetDataStore can fail (e.g. a place that was never published); then data is temporary.
local storeOk, store = pcall(function()
	return DataStoreService:GetDataStore(Config.DataStoreName)
end)
if not storeOk then
	warn("[DataManager] DataStores unavailable (publish the place and enable Studio API access): " .. tostring(store))
	store = nil
end
local profiles: { [Player]: { Data: any, CanSave: boolean } } = {}

DataManager.ProfileLoaded = Instance.new("BindableEvent") -- fires (player, data)

local function deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in t do
		c[k] = deepCopy(v)
	end
	return c
end

-- Fill in missing keys (new fields added in updates) and fix wrong types.
local function reconcile(data, template)
	for k, v in template do
		if type(data[k]) ~= type(v) then
			data[k] = deepCopy(v)
		elseif type(v) == "table" and next(v) ~= nil then
			reconcile(data[k], v)
		end
	end
	return data
end

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

local function loadData(player: Player)
	if not store then
		return deepCopy(TEMPLATE), false
	end
	for attempt = 1, LOAD_ATTEMPTS do
		local lockedByOther = false
		local ok, result = pcall(function()
			return store:UpdateAsync(keyFor(player), function(old)
				old = old or deepCopy(TEMPLATE)
				local lock = old.Lock
				if lock and lock.JobId ~= game.JobId and os.time() - (lock.Time or 0) < LOCK_TIMEOUT and attempt < LOAD_ATTEMPTS then
					lockedByOther = true -- another server still has it (e.g. mid-teleport save)
					return nil -- cancel this write
				end
				old.Lock = { JobId = game.JobId, Time = os.time() }
				return old
			end)
		end)
		if ok and result and not lockedByOther then
			return reconcile(result, TEMPLATE), true
		end
		if not ok then
			warn(("[DataManager] Load attempt %d failed for %s: %s"):format(attempt, player.Name, tostring(result)))
		end
		if not player.Parent then
			return nil, false
		end
		task.wait(if lockedByOther then 2 else attempt * 1.5)
	end
	warn("[DataManager] Using temporary data for " .. player.Name .. " (will not be saved)")
	return deepCopy(TEMPLATE), false
end

local function saveData(player: Player, release: boolean)
	local profile = profiles[player]
	if not profile or not profile.CanSave or not store then
		return
	end
	local snapshot = deepCopy(profile.Data)
	snapshot.Lock = if release then nil else { JobId = game.JobId, Time = os.time() }
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			store:UpdateAsync(keyFor(player), function(old)
				-- never overwrite data that another server took over
				if old and old.Lock and old.Lock.JobId ~= game.JobId and os.time() - (old.Lock.Time or 0) < LOCK_TIMEOUT then
					return nil
				end
				return snapshot
			end)
		end)
		if ok then
			return
		end
		warn(("[DataManager] Save attempt %d failed for %s: %s"):format(attempt, player.Name, tostring(err)))
		task.wait(attempt)
	end
end

-- Public, read-only copy for the client
function DataManager.Snapshot(player: Player)
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local d = deepCopy(profile.Data)
	d.Lock = nil
	local level, into, need = Util.LevelFromXP(d.XP)
	d.Level = level
	d.LevelXP = into
	d.LevelXPNeeded = need
	return d
end

local function push(player: Player)
	local snap = DataManager.Snapshot(player)
	if snap then
		Remotes.DataUpdated:FireClient(player, snap)
		local stats = player:FindFirstChild("leaderstats")
		if stats then
			stats.Wins.Value = snap.Wins
			stats.Coins.Value = snap.Coins
		end
	end
end

function DataManager.Get(player: Player)
	local profile = profiles[player]
	return profile and profile.Data
end

-- All changes go through here so the client always gets an update.
function DataManager.Update(player: Player, fn: (any) -> ())
	local profile = profiles[player]
	if not profile then
		return false
	end
	fn(profile.Data)
	profile.Data.Level = (Util.LevelFromXP(profile.Data.XP))
	push(player)
	return true
end

-- Coins/XP with sanity limits. Returns new level if the player levelled up.
function DataManager.AddRewards(player: Player, coins: number, xp: number): number?
	coins = math.clamp(math.floor(coins), 0, 10000)
	xp = math.clamp(math.floor(xp), 0, 10000)
	local before, after
	DataManager.Update(player, function(d)
		before = Util.LevelFromXP(d.XP)
		d.Coins += coins
		d.XP += xp
		after = Util.LevelFromXP(d.XP)
	end)
	return if after and before and after > before then after else nil
end

local function onPlayerAdded(player: Player)
	-- leaderboard in the player list
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Parent = stats
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = stats
	stats.Parent = player

	local data, canSave = loadData(player)
	if not data or not player.Parent then
		return
	end
	profiles[player] = { Data = data, CanSave = canSave }
	push(player)
	player:SetAttribute("DataLoaded", true)
	DataManager.ProfileLoaded:Fire(player, data)
end

function DataManager.Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end

	Players.PlayerRemoving:Connect(function(player)
		saveData(player, true)
		profiles[player] = nil
	end)

	-- client asks for its data (e.g. when opening the shop)
	Remotes.RequestData.OnServerInvoke = function(player)
		return DataManager.Snapshot(player)
	end

	-- autosave loop
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player in profiles do
				task.spawn(saveData, player, false)
			end
		end
	end)

	game:BindToClose(function()
		if not store then
			return
		end
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				saveData(player, true)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.5)
		end
	end)
end

return DataManager
