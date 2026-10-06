--[[
	Party (lobby place): groups of up to Config.Party.MaxSize players who go into a store together.

	Everybody is always in a party (alone = a party of one). In a party you can
	  - invite players in this lobby server (they get a JOIN / NO toast)
	  - invite Roblox friends (client: SocialService game invite carrying the party code as
	    LaunchData; when they arrive in this server they join your party automatically)
	  - join a party by its code (# K7Q-2M)
	  - ready up; the leader picks the rules (SURVIVAL / INFECTION / HARDCORE) and launches

	Launch reserves a brand-new private server of THIS place (private servers run the store) and
	teleports the whole party
	there in ONE TeleportAsync call (so they land together), with TeleportData
	  { Mode, PartyKey, Leader, Members, Rules, Solo }
	SOLO launch: only you go, the party stays here.
	When the party comes back from a store with the same PartyKey it is rebuilt automatically.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local PartyRules = require(Shared.PartyRules)
local Signal = require(Shared.Signal)

local Services = script.Parent.Parent:WaitForChild("Services")
local State = require(Services.State)
local Data = require(Services.Data)
local RateLimiter = require(Services.RateLimiter)

local Party = {}
Party.Changed = Signal.new() -- (party) members / leader changed: the world moves the lineup

local parties: { [number]: any } = {}
local byPlayer: { [Player]: any } = {}
local byCode: { [string]: any } = {}
local byKey: { [string]: any } = {} -- PartyKey from a returning teleport
local nextId = 0
local rng = Random.new()
local limiter = RateLimiter.new(12, 4)
local launchLimiter = RateLimiter.new(2, 5)

local MAX = Config.Party.MaxSize

--============================ STATE ============================--
local function memberInfo(party, p: Player)
	local d = Data.Get(p)
	return {
		UserId = p.UserId,
		Name = p.DisplayName,
		Level = Data.Level(p),
		Title = d and d.Equipped.Title or "Shopper",
		Ready = party.Ready[p] == true or party.Leader == p,
		Leader = party.Leader == p,
	}
end

function Party.Snapshot(party)
	local members = {}
	for _, p in party.Members do
		table.insert(members, memberInfo(party, p))
	end
	return {
		Id = party.Id,
		Code = party.Code,
		Leader = party.Leader and party.Leader.UserId or 0,
		Max = MAX,
		Rules = party.Rules,
		Members = members,
		Launching = party.Launching,
		Pad = party.Pad,
	}
end

local function push(party)
	if not parties[party.Id] then
		return
	end
	local snap = Party.Snapshot(party)
	for _, p in party.Members do
		p:SetAttribute("PartyId", party.Id)
		p:SetAttribute("PartySize", #party.Members)
		p:SetAttribute("PartyLeader", party.Leader == p)
		p:SetAttribute("Pad", party.Pad or 0)
		Net.Event("Party"):FireClient(p, snap)
	end
	Party.Changed:Fire(party)
end
Party.Push = push

local usedPads: { [number]: boolean } = {}
local function takePad(): number
	for i = 1, Config.Party.Pads do
		if not usedPads[i] then
			usedPads[i] = true
			return i
		end
	end
	return 0 -- lobby is very full: share the overflow pad
end

local function create(leader: Player, key: string?)
	nextId += 1
	local code = PartyRules.NewCode(rng)
	while byCode[code] do
		code = PartyRules.NewCode(rng)
	end
	local party = {
		Id = nextId,
		Code = code,
		Key = key,
		Leader = leader,
		Members = { leader },
		Ready = {},
		Rules = "Survival",
		Launching = false,
		Invites = {}, -- [Player] = expiry (os.clock)
		Pad = takePad(),
	}
	parties[party.Id] = party
	byCode[code] = party
	if key then
		byKey[key] = party
	end
	byPlayer[leader] = party
	return party
end

local function disband(party)
	parties[party.Id] = nil
	byCode[party.Code] = nil
	if party.Key and byKey[party.Key] == party then
		byKey[party.Key] = nil
	end
	if party.Pad and party.Pad > 0 then
		usedPads[party.Pad] = nil
	end
	Party.Changed:Fire(party)
end

-- take a player out of their party (the party survives with the others)
local function remove(player: Player)
	local party = byPlayer[player]
	if not party then
		return
	end
	byPlayer[player] = nil
	local i = table.find(party.Members, player)
	if i then
		table.remove(party.Members, i)
	end
	party.Ready[player] = nil
	if #party.Members == 0 then
		disband(party)
		return
	end
	if party.Leader == player then
		party.Leader = party.Members[1]
	end
	push(party)
end

local function soloParty(player: Player)
	remove(player)
	local party = create(player)
	push(party)
	return party
end

local function join(player: Player, party): (boolean, string?)
	if byPlayer[player] == party then
		return false, "Already in this party"
	end
	if party.Launching then
		return false, "That party is entering a store"
	end
	if #party.Members >= MAX then
		return false, "That party is full"
	end
	remove(player)
	table.insert(party.Members, player)
	byPlayer[player] = party
	party.Invites[player] = nil
	push(party)
	for _, p in party.Members do
		if p ~= player then
			State.Notify(p, player.DisplayName .. " joined the party", "Good")
		end
	end
	return true
end

function Party.Of(player: Player)
	return byPlayer[player]
end

function Party.All()
	return parties
end

--============================ LAUNCH ============================--
-- Studio sets this (the store runs on the same server): walk the players in, no teleport
Party.LocalLaunch = nil :: ((going: { Player }, mode: string) -> ())?

function Party.Launch(player: Player, solo: boolean, soloRules: string?): (boolean, string?)
	local party = byPlayer[player]
	if not party or party.Launching then
		return false, "Already launching"
	end
	local going: { Player }
	if solo then
		going = { player }
	else
		if party.Leader ~= player then
			return false, "Only the party leader can start"
		end
		for _, p in party.Members do
			if p ~= party.Leader and not party.Ready[p] then
				return false, p.DisplayName .. " is not ready"
			end
		end
		going = table.clone(party.Members)
	end
	local rules = party.Rules
	if solo and soloRules and table.find(Config.Party.LobbyModes, soloRules) then
		rules = soloRules
	end
	local mode, why = PartyRules.Resolve(rules, solo, #going)
	if not mode then
		return false, why
	end
	if Party.LocalLaunch then
		if not solo then
			for _, p in party.Members do
				party.Ready[p] = nil
			end
			push(party)
		end
		Party.LocalLaunch(going, mode)
		return true
	end
	if RunService:IsStudio() then
		return false, "Teleports don't work in Studio."
	end

	party.Launching = not solo
	if not solo then
		push(party)
	end
	local userIds = {}
	for _, p in going do
		table.insert(userIds, p.UserId)
		p:SetAttribute("Teleporting", true)
		Net.Event("Teleporting"):FireClient(p, { Mode = mode, Solo = solo, Members = #going })
	end

	local function fail(msg: string)
		party.Launching = false
		for _, p in going do
			if p.Parent then
				p:SetAttribute("Teleporting", false)
				Net.Event("Teleporting"):FireClient(p, { Cancel = true, Message = msg })
			end
		end
		if parties[party.Id] then
			push(party)
		end
	end

	task.spawn(function()
		local code
		for attempt = 1, 3 do
			local okR, res = pcall(function()
				return TeleportService:ReserveServer(game.PlaceId)
			end)
			if okR and res then
				code = res
				break
			end
			task.wait(attempt)
		end
		if not code then
			fail("Couldn't open a store right now. Try again!")
			return
		end
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = code
		options:SetTeleportData({
			Mode = mode,
			Rules = rules,
			Solo = solo,
			PartyKey = if solo then nil else (game.JobId .. ":" .. party.Id),
			Leader = if solo then player.UserId else party.Leader.UserId,
			Members = userIds,
		})
		local present = {}
		for _, p in going do
			if p.Parent then
				table.insert(present, p)
			end
		end
		local okT, errT = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, present, options)
		end)
		if not okT then
			fail("Teleport failed: " .. tostring(errT))
		end
	end)
	return true
end

--============================ ACTIONS ============================--
local function byUserId(id: any): Player?
	if type(id) ~= "number" then
		return nil
	end
	return Players:GetPlayerByUserId(id)
end

local ACTIONS = {}

function ACTIONS.Invite(player, req)
	local party = byPlayer[player]
	local target = byUserId(req.UserId)
	if not party or not target or target == player then
		return
	end
	if byPlayer[target] == party then
		State.Notify(player, target.DisplayName .. " is already in your party", "Info")
		return
	end
	if #party.Members >= MAX then
		State.Notify(player, "Your party is full", "Warn")
		return
	end
	local expiry = party.Invites[target]
	if expiry and expiry > os.clock() then
		State.Notify(player, "Invite already sent", "Info")
		return
	end
	party.Invites[target] = os.clock() + Config.Party.InviteTimeout
	Net.Event("PartyInvite"):FireClient(target, {
		PartyId = party.Id,
		From = player.DisplayName,
		FromUserId = player.UserId,
		Size = #party.Members,
		Timeout = Config.Party.InviteTimeout,
	})
	State.Notify(player, "Invite sent to " .. target.DisplayName, "Good")
end

function ACTIONS.Accept(player, req)
	local party = type(req.PartyId) == "number" and parties[req.PartyId]
	if not party then
		State.Notify(player, "That party doesn't exist any more", "Warn")
		return
	end
	local expiry = party.Invites[player]
	if not expiry or expiry < os.clock() then
		State.Notify(player, "That invite expired", "Warn")
		return
	end
	local ok, why = join(player, party)
	if not ok and why then
		State.Notify(player, why, "Warn")
	end
end

function ACTIONS.Decline(player, req)
	local party = type(req.PartyId) == "number" and parties[req.PartyId]
	if party and party.Invites[player] then
		party.Invites[player] = nil
		State.Notify(party.Leader, player.DisplayName .. " declined the invite", "Info")
	end
end

function ACTIONS.JoinCode(player, req)
	local code = type(req.Code) == "string" and string.upper(string.gsub(req.Code, "[^%w]", ""))
	if not code or #code ~= 6 then
		State.Notify(player, "Codes look like K7Q-2M4", "Warn")
		return
	end
	local party = byCode[string.sub(code, 1, 3) .. "-" .. string.sub(code, 4, 6)]
	if not party then
		State.Notify(player, "No party with that code in this lobby", "Warn")
		return
	end
	local ok, why = join(player, party)
	if not ok and why then
		State.Notify(player, why, "Warn")
	end
end

function ACTIONS.Leave(player)
	local party = byPlayer[player]
	if party and #party.Members > 1 and not party.Launching then
		soloParty(player)
		State.Notify(player, "You left the party", "Info")
		for _, p in party.Members do
			State.Notify(p, player.DisplayName .. " left the party", "Info")
		end
	end
end

function ACTIONS.Kick(player, req)
	local party = byPlayer[player]
	local target = byUserId(req.UserId)
	if party and target and party.Leader == player and target ~= player and byPlayer[target] == party and not party.Launching then
		soloParty(target)
		State.Notify(target, "You were removed from the party", "Warn")
	end
end

function ACTIONS.Promote(player, req)
	local party = byPlayer[player]
	local target = byUserId(req.UserId)
	if party and target and party.Leader == player and byPlayer[target] == party then
		party.Leader = target
		party.Ready[player] = true
		push(party)
	end
end

function ACTIONS.Ready(player, req)
	local party = byPlayer[player]
	if party and not party.Launching then
		party.Ready[player] = req.Value == true
		push(party)
	end
end

function ACTIONS.SetMode(player, req)
	local party = byPlayer[player]
	if party and party.Leader == player and not party.Launching and type(req.Mode) == "string" and table.find(Config.Party.LobbyModes, req.Mode) then
		party.Rules = req.Mode
		-- new rules: everybody confirms again
		table.clear(party.Ready)
		push(party)
	end
end

function ACTIONS.Launch(player, req)
	if not launchLimiter:Allow(player) then
		return
	end
	local ok, why = Party.Launch(player, req.Solo == true, if type(req.Rules) == "string" then req.Rules else nil)
	if not ok and why then
		State.Notify(player, why, "Warn")
	end
end

--============================ PLAYERS ============================--
local function onPlayerAdded(player: Player)
	local join_ = player:GetJoinData()
	local td = join_ and join_.TeleportData
	local launch = join_ and join_.LaunchData
	-- coming back from a store together: rebuild the party
	if type(td) == "table" and type(td.PartyKey) == "string" then
		local party = byKey[td.PartyKey]
		if party and parties[party.Id] and #party.Members < MAX then
			join(player, party)
		else
			local p = create(player, td.PartyKey)
			p.Rules = if type(td.Rules) == "string" and table.find(Config.Party.LobbyModes, td.Rules) then td.Rules else "Survival"
			push(p)
		end
		local party2 = byPlayer[player]
		if party2 and td.Leader == player.UserId then
			party2.Leader = player
			push(party2)
		end
		return
	end
	-- accepted a friend's game invite: LaunchData is their party code
	if type(launch) == "string" and byCode[launch] then
		local ok = join(player, byCode[launch])
		if ok then
			return
		end
	end
	soloParty(player)
end

function Party.Init()
	Net.Event("PartyAction").OnServerEvent:Connect(function(player, req)
		if not limiter:Allow(player) or type(req) ~= "table" or type(req.Action) ~= "string" then
			return
		end
		local fn = ACTIONS[req.Action]
		if fn then
			fn(player, req)
		end
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		remove(player)
		for _, party in parties do
			party.Invites[player] = nil
		end
	end)
	TeleportService.TeleportInitFailed:Connect(function(player, _result, message)
		local party = byPlayer[player]
		player:SetAttribute("Teleporting", false)
		Net.Event("Teleporting"):FireClient(player, { Cancel = true, Message = "Teleport failed: " .. tostring(message) })
		if party then
			party.Launching = false
			push(party)
		end
	end)
	-- levels / titles show in the party panel: refresh when profiles change
	Data.Changed:Connect(function(player)
		local party = byPlayer[player]
		if party then
			push(party)
		end
	end)
	Data.Loaded:Connect(function(player)
		local party = byPlayer[player]
		if party then
			push(party)
		end
	end)
end

return Party
