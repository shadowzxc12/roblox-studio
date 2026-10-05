--[[
	Progress: Survival XP, levels/unlocks, Store Credits, lifetime stats and daily missions.
	All values are server-side; every amount is clamped so a bug can't hand out millions.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local Missions = require(Shared.Missions)
local Progression = require(Shared.Progression)

local Data = require(script.Parent.Data)
local RateLimiter = require(script.Parent.RateLimiter)

local Progress = {}
Progress.LeveledUp = Signal.new() -- (player, oldLevel, newLevel)

local nightBudget: { [Player]: { BuildXP: number, Credits: number } } = {}
local claimLimiter = RateLimiter.new(6, 5)

local function budget(player)
	local b = nightBudget[player]
	if not b then
		b = { BuildXP = 0, Credits = 0 }
		nightBudget[player] = b
	end
	return b
end

function Progress.ResetNightBudgets()
	table.clear(nightBudget)
end

local function today(): number
	return Util.DayNumber(os.time())
end

local function rollMissions(d)
	local day = today()
	if d.Missions.Day ~= day then
		d.Missions = { Day = day, Progress = {}, Claimed = {} }
	end
end

function Progress.AddXP(player: Player, amount: number, reason: string?)
	amount = math.clamp(math.floor(amount), 0, 5000)
	if amount <= 0 then
		return
	end
	local before, after
	Data.Update(player, function(d)
		before = Util.LevelFromXP(d.XP)
		d.XP += amount
		after = Util.LevelFromXP(d.XP)
	end)
	if not before then
		return
	end
	Net.Event("XP"):FireClient(player, amount, reason or "")
	if after > before then
		local unlocks = Progression.NewUnlocks(before, after)
		Net.Event("Unlocks"):FireClient(player, { Level = after, Unlocks = unlocks })
		Progress.LeveledUp:Fire(player, before, after)
	end
end

function Progress.AddCredits(player: Player, amount: number, reason: string?, ignoreCap: boolean?)
	amount = math.clamp(math.floor(amount), 0, 5000)
	if not ignoreCap then
		local b = budget(player)
		amount = math.min(amount, Config.Credits.MaxPerNight - b.Credits)
		b.Credits += amount
	end
	if amount <= 0 then
		return
	end
	Data.Update(player, function(d)
		d.Credits += amount
	end)
	Net.Event("Notify"):FireClient(player, ("+%d Store Credits%s"):format(amount, if reason then " · " .. reason else ""), "Credits")
end

-- XP for building, capped per night
function Progress.BuildXP(player: Player)
	local b = budget(player)
	if b.BuildXP >= Config.XP.BuildCapPerNight then
		return
	end
	b.BuildXP += Config.XP.BuildEach
	Progress.AddXP(player, Config.XP.BuildEach, nil)
end

-- lifetime stat + daily mission progress
function Progress.Track(player: Player, stat: string, amount: number?)
	local n = amount or 1
	local completed = {}
	Data.Update(player, function(d)
		if d.Stats[stat] ~= nil then
			d.Stats[stat] += n
		end
		rollMissions(d)
		for _, id in Missions.ForDay(d.Missions.Day) do
			local m = Missions.ById[id]
			if m.Stat == stat and not d.Missions.Claimed[id] then
				local before = d.Missions.Progress[id] or 0
				local now = math.min(m.Goal, before + n)
				d.Missions.Progress[id] = now
				if before < m.Goal and now >= m.Goal then
					table.insert(completed, m)
				end
			end
		end
	end)
	for _, m in completed do
		Net.Event("Notify"):FireClient(player, "MISSION COMPLETE: " .. m.Text .. " — claim it in MISSIONS", "Mission")
	end
end

function Progress.ClaimMission(player: Player, id: any)
	if type(id) ~= "string" or not Missions.ById[id] then
		return
	end
	local m = Missions.ById[id]
	local ok = false
	Data.Update(player, function(d)
		rollMissions(d)
		if not table.find(Missions.ForDay(d.Missions.Day), id) then
			return
		end
		if d.Missions.Claimed[id] or (d.Missions.Progress[id] or 0) < m.Goal then
			return
		end
		d.Missions.Claimed[id] = true
		ok = true
	end)
	if ok then
		Progress.AddCredits(player, m.Credits, "Mission", true)
		Progress.AddXP(player, m.XP, "Mission")
	end
end

function Progress.Init()
	Net.Event("ClaimMission").OnServerEvent:Connect(function(player, id)
		if claimLimiter:Allow(player) then
			Progress.ClaimMission(player, id)
		end
	end)
	Data.Loaded:Connect(function(player)
		Data.Update(player, rollMissions)
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		nightBudget[player] = nil
	end)
end

return Progress
