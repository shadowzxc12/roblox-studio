--[[
	Data: loads, keeps and saves player profiles with DataStoreService.

	- every DataStore call is in pcall with retries
	- a session lock (JobId + time) stops two servers overwriting each other (teleports!)
	- if loading fails the player gets temporary data that is NEVER saved,
	  so an outage can't wipe progress
	- saves on leave, every few minutes and in BindToClose
	- clients never write data; they get read-only snapshots through the "Data" remote

	A run (the current store, its loot and bases) belongs to the server and is not saved:
	what persists is progression (XP, level, credits, cosmetics, missions, stats, settings).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local Cosmetics = require(Shared.Cosmetics)

local Data = {}

local TEMPLATE = {
	Credits = 0,
	XP = 0,
	BestNight = 0,
	Runs = 0,
	Stats = {
		NightsSurvived = 0,
		FoodFound = 0,
		StructuresBuilt = 0,
		Revives = 0,
		RareFound = 0,
		LootFound = 0,
		RoomsOpened = 0,
		LocustRepelled = 0,
		Refuels = 0,
		ZonesExplored = 0,
		NightNoGenerator = 0,
		Downs = 0,
	},
	Owned = {},
	Equipped = { Title = "Shopper", Outfit = "OutfitNone", Flashlight = "BeamWarm", Cart = "CartChrome", Effect = "FxNone" },
	Missions = { Day = 0, Progress = {}, Claimed = {} },
	Settings = { Music = true, SFX = true, Effects = true, CameraShake = true, Brightness = 0, Sensitivity = 1 },
	Purchases = {},
	SeenTutorial = false,
}

local LOCK_TIMEOUT = 90
local LOAD_ATTEMPTS = if RunService:IsStudio() then 2 else 6
local AUTOSAVE_INTERVAL = 150

local storeOk, store = pcall(function()
	return DataStoreService:GetDataStore(Config.DataStoreName)
end)
if not storeOk then
	warn("[Data] DataStores unavailable (publish the place and enable Studio API access): " .. tostring(store))
	store = nil
end

local profiles: { [Player]: { Data: any, CanSave: boolean } } = {}

Data.Loaded = Signal.new() -- (player, data)
Data.Changed = Signal.new() -- (player, data)

local function reconcile(data, template)
	for k, v in template do
		if type(data[k]) ~= type(v) then
			data[k] = Util.DeepCopy(v)
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
		return Util.DeepCopy(TEMPLATE), false
	end
	for attempt = 1, LOAD_ATTEMPTS do
		local lockedByOther = false
		local ok, result = pcall(function()
			return store:UpdateAsync(keyFor(player), function(old)
				old = old or Util.DeepCopy(TEMPLATE)
				local lock = old.Lock
				if lock and lock.JobId ~= game.JobId and os.time() - (lock.Time or 0) < LOCK_TIMEOUT and attempt < LOAD_ATTEMPTS then
					lockedByOther = true
					return nil
				end
				old.Lock = { JobId = game.JobId, Time = os.time() }
				return old
			end)
		end)
		if ok and result and not lockedByOther then
			return reconcile(result, TEMPLATE), true
		end
		if not ok then
			warn(("[Data] load attempt %d failed for %s: %s"):format(attempt, player.Name, tostring(result)))
		end
		if not player.Parent then
			return nil, false
		end
		task.wait(if lockedByOther then 2 else attempt * 1.5)
	end
	warn("[Data] using temporary data for " .. player.Name .. " (will not be saved)")
	return Util.DeepCopy(TEMPLATE), false
end

local function saveData(player: Player, release: boolean)
	local profile = profiles[player]
	if not profile or not profile.CanSave or not store then
		return
	end
	local snapshot = Util.DeepCopy(profile.Data)
	snapshot.Lock = if release then nil else { JobId = game.JobId, Time = os.time() }
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			store:UpdateAsync(keyFor(player), function(old)
				if old and old.Lock and old.Lock.JobId ~= game.JobId and os.time() - (old.Lock.Time or 0) < LOCK_TIMEOUT then
					return nil
				end
				return snapshot
			end)
		end)
		if ok then
			return
		end
		warn(("[Data] save attempt %d failed for %s: %s"):format(attempt, player.Name, tostring(err)))
		task.wait(attempt)
	end
end

function Data.Snapshot(player: Player)
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local d = Util.DeepCopy(profile.Data)
	d.Lock = nil
	d.Purchases = nil
	local level, into, need = Util.LevelFromXP(d.XP)
	d.Level = level
	d.LevelXP = into
	d.LevelXPNeeded = need
	d.Saving = profile.CanSave
	return d
end

local function push(player: Player)
	local snap = Data.Snapshot(player)
	if snap then
		Net.Event("Data"):FireClient(player, snap)
		player:SetAttribute("Level", snap.Level)
		player:SetAttribute("Title", snap.Equipped.Title)
		local stats = player:FindFirstChild("leaderstats")
		if stats then
			stats.Level.Value = snap.Level
			stats["Best Night"].Value = snap.BestNight
		end
	end
end
Data.Push = push

function Data.Get(player: Player)
	local profile = profiles[player]
	return profile and profile.Data
end

function Data.Level(player: Player): number
	local d = Data.Get(player)
	return if d then (Util.LevelFromXP(d.XP)) else 1
end

-- every change goes through here so the client always gets an update
function Data.Update(player: Player, fn: (any) -> ())
	local profile = profiles[player]
	if not profile then
		return false
	end
	fn(profile.Data)
	push(player)
	Data.Changed:Fire(player, profile.Data)
	return true
end

function Data.CanSave(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.CanSave
end

-- force a save (after Robux purchases)
function Data.SaveNow(player: Player)
	saveData(player, false)
end

local function onPlayerAdded(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Parent = stats
	local best = Instance.new("IntValue")
	best.Name = "Best Night"
	best.Parent = stats
	stats.Parent = player

	local data, canSave = loadData(player)
	if not data or not player.Parent then
		return
	end
	-- equipped items must still be valid
	for slot, def in Cosmetics.Defaults do
		if not Cosmetics.Get(data.Equipped[slot]) then
			data.Equipped[slot] = def
		end
	end
	profiles[player] = { Data = data, CanSave = canSave }
	push(player)
	player:SetAttribute("DataLoaded", true)
	Data.Loaded:Fire(player, data)
end

function Data.Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end

	Players.PlayerRemoving:Connect(function(player)
		saveData(player, true)
		profiles[player] = nil
	end)

	Net.Function("GetData").OnServerInvoke = function(player)
		return Data.Snapshot(player)
	end

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

return Data
