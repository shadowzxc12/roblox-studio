--[[
	RoundManager: the one central state machine for matches.

	LOADING -> INTERMISSION -> STARTING -> PLAYING -> ROUND_END -> RESULTS -> RETURNING -> INTERMISSION ...
	(LOBBY is used by lobby servers that only run the menu + matchmaking.)

	Who plays: players with the attribute InMatch = true (every player in a match server;
	in Studio, players who pressed PLAY). Players who join during a round wait for the next one.

	Clients read the current state from ReplicatedStorage attributes:
	  RoundState, RoundMode, RoundEndsAt (server time), PlayersInMatch, PlayersNeeded, MapName, Waiting
	and get one RoundState event per change (cheap: no per-second remotes, clients count down locally).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Modules.Config)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local RoleManager = require(script.Parent.RoleManager)
local TagManager = require(script.Parent.TagManager)
local MapManager = require(script.Parent.MapManager)
local RewardManager = require(script.Parent.RewardManager)
local ShopManager = require(script.Parent.ShopManager)

local RoundManager = {}

local State = {
	LOBBY = "LOBBY",
	LOADING = "LOADING",
	INTERMISSION = "INTERMISSION",
	STARTING = "STARTING",
	PLAYING = "PLAYING",
	ROUND_END = "ROUND_END",
	RESULTS = "RESULTS",
	RETURNING = "RETURNING",
}
RoundManager.State = State

local modeId: string? = nil
local Mode = nil -- the mode module (Modes/Normal, Modes/Infection)
local ctx = nil -- the current round (nil between rounds)
local started = false
local rng = Random.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

local function setState(state: string, extra: { [string]: any }?)
	local attrs = {
		RoundState = state,
		RoundMode = modeId,
		RoundEndsAt = 0,
		Waiting = false,
		MapName = MapManager.GetDisplayName(),
	}
	if extra then
		for k, v in extra do
			attrs[k] = v
		end
	end
	for k, v in attrs do
		ReplicatedStorage:SetAttribute(k, v)
	end
	Remotes.RoundState:FireAllClients(attrs)
end

local function matchPlayers(): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("InMatch") then
			table.insert(list, p)
		end
	end
	return list
end

local function updatePlayerCount()
	ReplicatedStorage:SetAttribute("PlayersInMatch", #matchPlayers())
	ReplicatedStorage:SetAttribute("PlayersNeeded", Config.Round.MinPlayers)
end

local function isParticipant(p: Player): boolean
	return ctx ~= nil and ctx.Stats[p] ~= nil and p.Parent == Players and p:GetAttribute("InMatch") == true
end

local function participants(): { Player }
	local list = {}
	if ctx then
		for p in ctx.Stats do
			if isParticipant(p) then
				table.insert(list, p)
			end
		end
	end
	return list
end

-- Respawn a character (LoadCharacterAsync on new engines, LoadCharacter as a fallback).
local function respawn(player: Player)
	if not player.Parent then
		return
	end
	local ok = pcall(function()
		(player :: any):LoadCharacterAsync()
	end)
	if not ok then
		pcall(function()
			player:LoadCharacter()
		end)
	end
end

local function moveTo(player: Player, cf: CFrame?)
	local char = player.Character
	if cf and char and char:FindFirstChild("HumanoidRootPart") then
		TagManager.MarkTeleported(player)
		char:PivotTo(cf)
	end
end

local function announce(info)
	if not info then
		return
	end
	-- feed message for everyone
	Remotes.UpdateRole:FireAllClients({ Kind = info.Kind, Text = info.Text, Mode = modeId })
	-- personal big message ("YOU'RE THE CHASER!")
	if info.YouText then
		for player, text in info.YouText do
			if player.Parent then
				Remotes.UpdateRole:FireClient(player, { Kind = "You", Text = text, Role = RoleManager.Get(player), Mode = modeId })
			end
		end
	end
end

-- Called by TagManager after it validated a tag.
local function onTag(hunter: Player, prey: Player)
	if not ctx or ctx.State ~= State.PLAYING then
		return
	end
	local info = Mode.OnTag(ctx, hunter, prey)
	local root = prey.Character and prey.Character:FindFirstChild("HumanoidRootPart")
	local effect = ShopManager.GetTagEffect(hunter)
	if root then
		Remotes.TagEffect:FireAllClients(root.Position, if effect then effect.Color else nil, info.Kind)
	end
	announce(info)
end

-- PlayerRemoving / leaving the match mid-round
local function removeFromRound(player: Player)
	if ctx and ctx.Stats[player] then
		ctx.Stats[player] = nil
		if ctx.State == State.PLAYING then
			announce(Mode.OnPlayerRemoved(ctx))
		end
	end
end

-- A participant whose character respawns (fell off the map) goes back into the map.
local function onCharacterAdded(player: Player, char: Model)
	char:WaitForChild("HumanoidRootPart", 5)
	task.wait() -- let the default spawn finish first
	if ctx and isParticipant(player) and (ctx.State == State.PLAYING or ctx.State == State.STARTING) then
		moveTo(player, MapManager.GetSpawn(RoleManager.IsHunter(RoleManager.Get(player))))
	end
end

-- INTERMISSION: wait for enough players, then count down.
local function runIntermission()
	while true do
		updatePlayerCount()
		local count = #matchPlayers()
		if count < Config.Round.MinPlayers then
			setState(State.INTERMISSION, { Waiting = true })
			repeat
				task.wait(1)
				updatePlayerCount()
			until #matchPlayers() >= Config.Round.MinPlayers
			count = #matchPlayers()
		end
		local waitTime = if count >= Config.Round.MaxPlayers then Config.Round.FullServerIntermission else Config.Round.IntermissionTime
		local endsAt = now() + waitTime
		setState(State.INTERMISSION, { Waiting = false, RoundEndsAt = endsAt })
		local enough = true
		while now() < endsAt do
			task.wait(0.5)
			updatePlayerCount()
			if #matchPlayers() < Config.Round.MinPlayers then
				enough = false
				break
			end
		end
		if enough then
			return
		end
	end
end

-- STARTING: load map, choose roles, teleport in, reveal + countdown.
local function startRound(): boolean
	local players = {}
	for _, p in matchPlayers() do
		if p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
			table.insert(players, p)
		end
	end
	if #players < Config.Round.MinPlayers then
		return false
	end

	local map = MapManager.Load()
	if not map then
		return false
	end

	ctx = {
		State = State.STARTING,
		ModeId = modeId,
		Mode = Mode,
		Rng = rng,
		Stats = {},
		Participants = participants,
		IsParticipant = isParticipant,
	}
	for _, p in players do
		ctx.Stats[p] = { Catches = 0, Infections = 0, SurvivalTime = 0, TimesCaught = 0, PlayedTime = 0, Name = p.DisplayName }
	end

	local hunters = Mode.Setup(ctx, players)
	for _, p in players do
		RoleManager.SetFrozen(p, true)
		moveTo(p, MapManager.GetSpawn(RoleManager.IsHunter(RoleManager.Get(p))))
	end

	local names = {}
	for _, h in hunters do
		table.insert(names, h.DisplayName)
	end
	local modeCfg = Config.Modes[modeId]
	setState(State.STARTING)
	local revealTime = 3
	Remotes.Countdown:FireAllClients({
		Mode = modeId,
		RevealTitle = if modeId == "Infection" then "INFECTED PLAYER SELECTED" else "THE CHASER IS...",
		RevealNames = names,
		RevealTime = revealTime,
		Steps = Config.Round.CountdownSteps,
		StartText = modeCfg.StartText,
	})
	task.wait(revealTime + #Config.Round.CountdownSteps)
	return true
end

-- PLAYING: tag loop runs in TagManager; here we track time, stats and win conditions.
local function playRound()
	local modeCfg = Config.Modes[modeId]
	local startedAt = now()
	local endsAt = startedAt + modeCfg.RoundLength
	ctx.State = State.PLAYING
	ctx.StartedAt = startedAt
	setState(State.PLAYING, { RoundEndsAt = endsAt })

	-- runners go now, hunters after a short head start
	for _, p in participants() do
		if not RoleManager.IsHunter(RoleManager.Get(p)) then
			RoleManager.SetFrozen(p, false)
		end
	end
	task.delay(Config.Round.HunterReleaseDelay, function()
		if ctx and ctx.State == State.PLAYING then
			for _, p in participants() do
				RoleManager.SetFrozen(p, false)
			end
		end
	end)
	TagManager.Start(ctx, onTag)

	local last = now()
	local result
	while true do
		task.wait(Config.Round.TickRate)
		local t = now()
		local dt = t - last
		last = t
		for _, p in participants() do
			local s = ctx.Stats[p]
			s.PlayedTime += dt
			if RoleManager.Get(p) == Mode.PreyRole then
				s.SurvivalTime += dt
			end
		end
		if #participants() < Config.Round.MinPlayers then
			result = { Winner = "None", Title = "NOT ENOUGH PLAYERS" }
			break
		end
		result = Mode.CheckWin(ctx)
		if result then
			break
		end
		if t >= endsAt then
			result = Mode.OnTimeUp(ctx)
			result.TimeUp = true
			break
		end
	end
	ctx.Result = result
	ctx.Length = now() - startedAt
end

-- ROUND_END + RESULTS: freeze, rewards, results screen.
local function endRound()
	TagManager.Stop()
	ctx.State = State.ROUND_END
	for _, p in participants() do
		RoleManager.SetFrozen(p, true)
	end
	setState(State.ROUND_END, { ResultTitle = ctx.Result.Title })
	task.wait(2)

	ctx.State = State.RESULTS
	setState(State.RESULTS, { RoundEndsAt = now() + Config.Round.ResultsTime })
	local modeCfg = Config.Modes[modeId]
	local result = ctx.Result
	for _, p in participants() do
		local stats = ctx.Stats[p]
		local won = result.Winner ~= "None" and Mode.IsWinner(ctx, p, result)
		local reward = RewardManager.Grant(p, stats, won, ctx.Length, modeId)
		Remotes.ShowResults:FireClient(p, {
			Mode = modeId,
			Title = result.Title,
			Won = won,
			WinnerTeam = if result.Winner == "Prey" then modeCfg.PreyTeam elseif result.Winner == "Hunters" then modeCfg.HunterTeam else "",
			Caught = stats.Catches + stats.Infections,
			TimesCaught = stats.TimesCaught,
			SurvivalTime = math.floor(stats.SurvivalTime),
			Coins = reward.Coins,
			XP = reward.XP,
			NewLevel = reward.NewLevel,
		})
	end
	-- players who joined mid-round still see who won
	for _, p in matchPlayers() do
		if not ctx.Stats[p] then
			Remotes.ShowResults:FireClient(p, { Mode = modeId, Title = result.Title, Spectator = true })
		end
	end
	task.wait(Config.Round.ResultsTime)
end

-- RETURNING: clean up and send everyone back to the waiting area.
local function returnPlayers()
	setState(State.RETURNING)
	local list = participants()
	ctx = nil
	RoleManager.ClearAll()
	MapManager.Unload()
	for _, p in list do
		task.spawn(respawn, p) -- respawns in the lobby area, clean character
	end
	task.wait(Config.Round.ReturnTime)
end

-- Remove a player from the match (Studio "Main Menu", or before teleporting out).
function RoundManager.RemovePlayer(player: Player)
	removeFromRound(player)
	player:SetAttribute("InMatch", nil)
	RoleManager.Set(player, nil)
	player:SetAttribute("Frozen", nil)
	updatePlayerCount()
	if player.Character then
		task.spawn(respawn, player)
	end
end

function RoundManager.IsRunning(): boolean
	return started
end

function RoundManager.GetMode(): string?
	return modeId
end

-- Start the match loop for one game mode. Called once per server.
function RoundManager.Start(id: string)
	if started then
		return
	end
	local module = script.Parent.Modes:FindFirstChild(id)
	if not module or not Config.Modes[id] then
		warn("[RoundManager] Unknown mode " .. tostring(id) .. ", using Normal")
		id = "Normal"
		module = script.Parent.Modes.Normal
	end
	started = true
	modeId = id
	Mode = require(module)
	setState(State.LOADING)

	Players.PlayerRemoving:Connect(function(p)
		removeFromRound(p)
		task.defer(updatePlayerCount)
	end)
	local function hook(p: Player)
		p.CharacterAdded:Connect(function(char)
			onCharacterAdded(p, char)
		end)
		p:GetAttributeChangedSignal("InMatch"):Connect(updatePlayerCount)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end

	task.spawn(function()
		while true do
			runIntermission()
			local ok, err = pcall(function()
				if startRound() then
					playRound()
					endRound()
				end
			end)
			if not ok then
				warn("[RoundManager] Round error: " .. tostring(err))
				TagManager.Stop()
			end
			returnPlayers()
		end
	end)
end

function RoundManager.SetLobbyState()
	setState(State.LOBBY)
end

return RoundManager
