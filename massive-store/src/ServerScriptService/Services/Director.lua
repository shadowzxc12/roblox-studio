--[[
	Director: the run.

	  Waiting  -> first player presses PLAY -> run starts (Day 1)
	  Day      explore, loot, build                          (Config.Cycle.Day seconds)
	  Dusk     lights flicker, "get to your base"            (Config.Cycle.Dusk)
	  Night    the Locust hunts                              (Config.NightLength(n))
	  Dawn     survivors rewarded, dead respawn, restock     (Config.Cycle.Dawn)
	  ...repeat forever: every night is harder.
	  Everyone down/dead at night -> Results -> the store resets (new run)

	Every 10 nights the store changes: new areas unlock (basement at 10, sealed wing at 20),
	loot gets better and new Locust variants appear (Config.LocustVariants).

	Also owns the in-game clock, objectives and the end-of-run summary.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Util = require(Shared.Util)

local State = require(script.Parent.State)
local World = require(script.Parent.World)
local Data = require(script.Parent.Data)
local Survival = require(script.Parent.Survival)
local Inventory = require(script.Parent.Inventory)
local Loot = require(script.Parent.Loot)
local Power = require(script.Parent.Power)
local Building = require(script.Parent.Building)
local Carts = require(script.Parent.Carts)
local Locust = require(script.Parent.Locust)
local Events = require(script.Parent.Events)
local Progress = require(script.Parent.Progress)
local Tools = require(script.Parent.Tools)
local Noise = require(script.Parent.Noise)

local Director = {}

local C = Config.Cycle
local runStats = { Started = 0, Downs = 0, Revives = 0, Built = 0, Players = {} }
local phaseThread = nil

-- team objectives: one per day, everyone in the store contributes
local TEAM_OBJECTIVES = {
	{ Stat = "FoodFound", Goal = 8, Text = "find %d food items" },
	{ Stat = "StructuresBuilt", Goal = 8, Text = "build %d structures" },
	{ Stat = "Refuels", Goal = 1, Text = "refuel a generator" },
	{ Stat = "ZonesExplored", Goal = 4, Text = "explore %d new departments" },
	{ Stat = "RoomsOpened", Goal = 1, Text = "open a locked or hidden room" },
	{ Stat = "RareFound", Goal = 2, Text = "find %d rare items" },
	{ Stat = "LootFound", Goal = 30, Text = "pick up %d items" },
}
local team = nil -- { Def, Goal, Progress, Done }
local teamRng = Util.RNG(os.time() % 4441 + 9)
local primaryObjective = ""

local function setPhase(phase: string, length: number)
	State.Phase = phase
	local now = State.Now()
	State.SetAttr("Phase", phase)
	State.SetAttr("PhaseStart", now)
	State.SetAttr("PhaseEnds", now + length)
	State.SetAttr("PhaseLength", length)
	State.SetAttr("Night", State.Night)
	State.PhaseChanged:Fire(phase, State.Night)
	Power.RefreshZones()
end

local function teamText(): string
	if not team then
		return ""
	end
	local body = string.format(team.Def.Text, team.Goal)
	if team.Done then
		return "TEAM DONE · " .. body
	end
	return ("TEAM · %s (%d/%d)"):format(body, math.min(team.Progress, team.Goal), team.Goal)
end

local function objective(text: string?, player: Player?)
	if text then
		primaryObjective = text
	end
	if player then
		Net.Event("Objective"):FireClient(player, primaryObjective, teamText())
	else
		Net.Event("Objective"):FireAllClients(primaryObjective, teamText())
	end
end

local function newTeamObjective()
	local def = TEAM_OBJECTIVES[teamRng:Int(1, #TEAM_OBJECTIVES)]
	local players = math.max(1, #Survival.RunPlayers())
	local goal = if def.Goal > 1 then math.ceil(def.Goal * (0.6 + 0.4 * math.min(players, 6) / 2)) else 1
	team = { Def = def, Goal = goal, Progress = 0, Done = false }
end

local function onTracked(player: Player, stat: string, amount: number)
	if not team or team.Done or stat ~= team.Def.Stat or not State.RunActive then
		return
	end
	if State.Phase ~= "Day" and State.Phase ~= "Dusk" then
		return
	end
	team.Progress += amount
	if team.Progress >= team.Goal then
		team.Done = true
		for _, p in Survival.RunPlayers() do
			Progress.AddXP(p, Config.XP.Objective, "Team objective complete")
			Progress.AddCredits(p, 5, "Team objective")
		end
		State.Notify(nil, "TEAM OBJECTIVE COMPLETE: " .. string.format(team.Def.Text, team.Goal), "Good")
	end
	objective(nil)
end

function Director.OpenGate(id: string, by: Player?)
	if State.GatesOpen[id] then
		return
	end
	State.GatesOpen[id] = true
	World.SetGate(id, true)
	local gate = World.Gates[id]
	local kind = gate and gate.Data.Kind
	if kind == "Basement" then
		State.Banner(nil, "THE BASEMENT IS OPEN", if by then by.DisplayName .. " swiped a keycard" else "Parking garage · underground storage · tunnels", "ffc61a", 4)
	else
		State.Banner(nil, "THE SEALED WING IS OPEN", "Something valuable was locked away in there", "ff3b3b", 4)
	end
	if by then
		Progress.AddXP(by, 40, "Opened a new area")
	end
end

-- every 10 nights the store shifts
local function storeShift(night: number)
	if night % 10 ~= 0 then
		return
	end
	if night >= 10 then
		for id, g in World.Gates do
			if g.Data.Kind == "Basement" then
				Director.OpenGate(id)
			end
		end
	end
	if night >= 20 and World.Gates.SealedWing then
		Director.OpenGate("SealedWing")
	end
	local variant = Config.VariantFor(night)
	State.Banner(nil, "THE STORE SHIFTS", "New areas, better loot... and " .. variant.Name, "ff7a1a", 5)
	-- fresh, better stock everywhere; emptied stock rooms get locked up and refilled
	World.RelockRooms(6)
	Loot.RestockRooms()
	Loot.Populate(250)
end

local function survivors()
	local out = {}
	for _, p in Survival.RunPlayers() do
		local s = Survival.Get(p)
		if s and not s.Dead and not s.Downed then
			table.insert(out, p)
		end
	end
	return out
end

local function anyoneStanding(): boolean
	for _, p in Survival.RunPlayers() do
		local s = Survival.Get(p)
		if s and not s.Dead and not s.Downed and not s.Infected then
			return true
		end
	end
	return false
end

--============================ PHASES ============================--
local function runDay(first: boolean)
	local length = if first then C.FirstDay else C.Day
	setPhase("Day", length)
	if not first then
		State.Banner(nil, "DAY " .. (State.Night + 1), "It wanders the aisles... but won't attack. Yet.", "ffc61a", 3.5)
	end
	-- by day the Locust roams the store too, harmless until night falls
	if Config.Locust.DayRoam then
		local runId = State.RunId
		task.delay((Config.Locust.DaySpawnDelay or 25) * (if first then 2 else 1), function()
			if State.Phase == "Day" and State.RunActive and State.RunId == runId and not Locust.Get() then
				Locust.Spawn(State.Night + 1, true)
			end
		end)
	end
	newTeamObjective()
	objective(if first then "Explore the store and grab food & materials" else "Restock: food, fuel, materials. Upgrade your base.")
	task.delay(length * 0.55, function()
		if State.Phase == "Day" then
			objective("Build or reinforce a base before night [B]")
		end
	end)
	task.wait(length)
end

local function runDusk()
	setPhase("Dusk", C.Dusk)
	State.Night += 1
	State.SetAttr("Night", State.Night)
	State.Banner(nil, "NIGHT IS COMING", "Get back to your base", "ff7a1a", 3)
	objective("Get to your base or find somewhere to hide!")
	State.Cue("Dusk", nil, nil)
	Power.RollEmergency()
	task.wait(C.Dusk)
end

local function runNight()
	local night = State.Night
	local length = Config.NightLength(night)
	table.clear(State.NightUsedGenerator)
	Progress.ResetNightBudgets()
	setPhase("Night", length)
	storeShift(night)
	local variant = Config.VariantFor(night)
	State.Banner(nil, "NIGHT " .. night, (if variant.MinNight > 1 then variant.Name else "THE LOCUST") .. " IS HUNTING", "ff3b3b", 5)
	objective("Survive until 6:00 AM")
	Locust.Spawn(night)
	State.NightStarted:Fire(night)
	local deadline = os.clock() + length
	local wiped = false
	while os.clock() < deadline do
		task.wait(1)
		if #Survival.RunPlayers() > 0 and not anyoneStanding() then
			-- downed players may still be revived by... nobody. Give bleed-outs a moment.
			local allGone = true
			for _, p in Survival.RunPlayers() do
				local s = Survival.Get(p)
				if s and s.Downed and not s.Dead and State.ModeInfo.SelfRevive and Inventory.Count(p, "Medkit") > 0 then
					allGone = false
				end
			end
			if allGone then
				task.wait(3)
				if not anyoneStanding() then
					wiped = true
					break
				end
			end
		end
		if #Survival.RunPlayers() == 0 then
			wiped = true
			break
		end
	end
	return wiped
end

local function runDawn()
	local night = State.Night
	Locust.Despawn(false)
	setPhase("Dawn", C.Dawn)
	State.Banner(nil, "6:00 AM", "You survived night " .. night, "7cff4f", 4)
	State.Cue("Dawn", nil, nil)
	-- rewards
	for _, p in survivors() do
		Progress.AddXP(p, Config.XP.SurviveNightBase + Config.XP.SurviveNightPerNight * night, "Survived night " .. night)
		Progress.AddCredits(p, Config.Credits.SurviveNightBase + Config.Credits.SurviveNightPerNight * night, "Night " .. night)
		Progress.Track(p, "NightsSurvived", 1)
		if not State.NightUsedGenerator[p] then
			Progress.Track(p, "NightNoGenerator", 1)
		end
		Data.Update(p, function(d)
			d.BestNight = math.max(d.BestNight, night)
		end)
		local rs = runStats.Players[p.UserId]
		if rs then
			rs.Nights += 1
		end
	end
	-- downed players get up, dead players come back
	for _, p in Survival.RunPlayers() do
		local s = Survival.Get(p)
		if s and s.Downed then
			Survival.Revive(p, nil, 30)
		end
		if s and s.Dead then
			Survival.Spawn(p, nil, false)
			Tools.ResetPlayer(p)
		end
		if s and s.Infected then
			require(script.Parent.Infection).Cure(p)
		end
	end
	Events.DropBeacons()
	Loot.Restock()
	State.NightSurvived:Fire(night)
	task.wait(C.Dawn)
end

local function results()
	setPhase("Results", C.WipeResults)
	Locust.Despawn(false)
	local night = State.Night
	State.Banner(nil, "THE STORE CLAIMED YOU", "You survived " .. math.max(0, night - 1) .. " nights", "ff3b3b", 5)
	local summary = {
		Nights = math.max(0, night - 1),
		Mode = State.Mode,
		Duration = os.clock() - runStats.Started,
		Players = {},
	}
	for userId, rs in runStats.Players do
		table.insert(summary.Players, rs)
	end
	table.sort(summary.Players, function(a, b)
		return a.Nights > b.Nights
	end)
	for _, p in Players:GetPlayers() do
		Data.Update(p, function(d)
			d.Runs += 1
		end)
	end
	Net.Event("Results"):FireAllClients(summary)
	State.RunEnded:Fire(summary)
	task.wait(C.WipeResults)
end

-- wipe everything run-specific and start again at Day 1
function Director.ResetRun()
	State.RunActive = false
	Locust.Despawn(true)
	Locust.ResetMemory()
	Events.Clear()
	Noise.Clear()
	Building.ClearAll()
	Loot.ClearAll()
	Power.ResetRun()
	World.ResetRun()
	table.clear(State.GatesOpen)
	for id in World.Gates do
		State.SetAttr("Gate_" .. id, false)
	end
	Survival.ResetForNewRun()
	State.Night = 0
	State.RunId += 1
	State.SetAttr("RunId", State.RunId)
	runStats = { Started = os.clock(), Players = {} }
end

function Director.StartRun()
	Director.ResetRun()
	Carts.SpawnAll()
	Loot.Populate(Config.Loot.InitialItems)
	State.RunActive = true
	State.SetAttr("RunActive", true)
	State.RunStarted:Fire()
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("InRun") then
			Director.JoinRun(p, true)
		end
	end
end

-- a player enters the store (from the menu)
function Director.JoinRun(player: Player, fresh: boolean?)
	player:SetAttribute("InRun", true)
	runStats.Players[player.UserId] = runStats.Players[player.UserId] or { Name = player.DisplayName, Nights = 0 }
	Inventory.ResetPlayer(player, true)
	Tools.ResetPlayer(player)
	Survival.Spawn(player, nil, true)
	State.PlayerJoinedRun:Fire(player)
	local d = Data.Get(player)
	if d and not d.SeenTutorial then
		Data.Update(player, function(data)
			data.SeenTutorial = true
		end)
		Net.Event("Cue"):FireClient(player, "Tutorial", nil, nil)
	end
	if State.Phase == "Night" then
		objective("Survive until 6:00 AM", player)
	else
		objective("Explore the store and grab food & materials", player)
	end
end

local function loop()
	while true do
		-- wait for players
		State.Phase = "Waiting"
		State.SetAttr("Phase", "Waiting")
		while #Survival.RunPlayers() == 0 and not Director.PendingStart do
			task.wait(0.5)
		end
		Director.PendingStart = false
		Director.StartRun()
		runDay(true)
		while true do
			runDusk()
			local wiped = runNight()
			if wiped then
				break
			end
			runDawn()
			if #Survival.RunPlayers() == 0 then
				break
			end
			runDay(false)
		end
		if #Survival.RunPlayers() > 0 then
			results()
			-- everyone in the store starts again
			for _, p in Players:GetPlayers() do
				if p:GetAttribute("InRun") then
					p:SetAttribute("InRun", true)
				end
			end
			Director.PendingStart = true
		else
			Director.ResetRun()
			State.SetAttr("RunActive", false)
		end
	end
end

-- in-game clock for the HUD (07:00 -> 20:00 by day, 20:00 -> 06:00 by night)
local function clockLoop()
	while true do
		task.wait(1)
		local now = State.Now()
		local start = ReplicatedStorage:GetAttribute("PhaseStart") or now
		local length = ReplicatedStorage:GetAttribute("PhaseLength") or 1
		local t = math.clamp((now - start) / math.max(1, length), 0, 1)
		local hours
		if State.Phase == "Day" then
			hours = Util.Lerp(C.DayStartClock, C.DayEndClock - 0.5, t)
		elseif State.Phase == "Dusk" then
			hours = Util.Lerp(C.DayEndClock - 0.5, C.DayEndClock, t)
		elseif State.Phase == "Night" then
			hours = (C.DayEndClock + t * (24 - C.DayEndClock + C.NightEndClock)) % 24
		elseif State.Phase == "Dawn" then
			hours = Util.Lerp(C.NightEndClock, C.DayStartClock, t)
		else
			hours = C.DayStartClock
		end
		State.SetAttr("Clock", hours)
	end
end

function Director.Init()
	Director.PendingStart = false
	Progress.Tracked:Connect(onTracked)
	-- extra run stats
	Survival.Downed:Connect(function(player)
		local rs = runStats.Players and runStats.Players[player.UserId]
		if rs then
			rs.Downs = (rs.Downs or 0) + 1
		end
	end)
	Survival.Revived:Connect(function(player, by)
		local rs = by and runStats.Players and runStats.Players[by.UserId]
		if rs and by ~= player then
			rs.Revives = (rs.Revives or 0) + 1
		end
	end)
	Building.Placed:Connect(function(s)
		local p = Players:GetPlayerByUserId(s.Owner)
		local rs = p and runStats.Players and runStats.Players[p.UserId]
		if rs then
			rs.Built = (rs.Built or 0) + 1
		end
	end)
	task.spawn(clockLoop)
	phaseThread = task.spawn(loop)
end

return Director
