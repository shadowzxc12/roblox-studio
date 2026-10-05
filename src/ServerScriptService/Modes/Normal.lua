--[[
	NORMAL CHASE
	- one random Chaser (two when the server is big), everyone else is a Runner
	- Chaser tags Runner -> they SWAP roles
	- timer ends -> players who are Runners win
	- no Runners left (e.g. everyone else left) -> Chasers win
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Util = require(ReplicatedStorage.Modules.Util)
local RoleManager = require(script.Parent.Parent.RoleManager)
local TagManager = require(script.Parent.Parent.TagManager)
local Config = require(ReplicatedStorage.Modules.Config)

local Mode = {}
Mode.Id = "Normal"
Mode.HunterRole = "Chaser"
Mode.PreyRole = "Runner"

local function countRole(ctx, role)
	local list = {}
	for _, p in ctx.Participants() do
		if RoleManager.Get(p) == role then
			table.insert(list, p)
		end
	end
	return list
end

function Mode.HunterCount(playerCount: number): number
	return if playerCount >= 9 then 2 else 1
end

-- Returns the players chosen as hunters (for the reveal).
function Mode.Setup(ctx, players: { Player }): { Player }
	Util.Shuffle(players, ctx.Rng)
	local hunters = {}
	for i, p in players do
		if i <= Mode.HunterCount(#players) then
			RoleManager.Set(p, "Chaser")
			table.insert(hunters, p)
		else
			RoleManager.Set(p, "Runner")
		end
	end
	return hunters
end

-- Chaser tagged a Runner: they swap roles.
function Mode.OnTag(ctx, hunter: Player, prey: Player)
	RoleManager.Set(prey, "Chaser")
	RoleManager.Set(hunter, "Runner")
	TagManager.SetCooldown(prey, Config.Tag.NewHunterDelay) -- short pause for the new Chaser
	TagManager.SetNoTagBack(prey, hunter) -- and no tag-backs
	ctx.Stats[hunter].Catches += 1
	ctx.Stats[prey].TimesCaught += 1
	return {
		Kind = "Swap",
		Text = hunter.DisplayName .. " caught " .. prey.DisplayName .. "!",
		YouText = { [prey] = "YOU'RE THE CHASER!", [hunter] = "YOU'RE A RUNNER! RUN!" },
	}
end

function Mode.CheckWin(ctx)
	if #countRole(ctx, "Runner") == 0 then
		return { Winner = "Hunters", Title = "CHASERS WIN!" }
	end
	return nil
end

function Mode.OnTimeUp(ctx)
	return { Winner = "Prey", Title = "RUNNERS WIN!" }
end

function Mode.IsWinner(ctx, player: Player, result): boolean
	local role = RoleManager.Get(player)
	if result.Winner == "Prey" then
		return role == "Runner"
	end
	return role == "Chaser"
end

-- If every Chaser left, pick a new one so the round can go on.
function Mode.OnPlayerRemoved(ctx)
	if #countRole(ctx, "Chaser") == 0 then
		local runners = countRole(ctx, "Runner")
		if #runners >= 2 then
			local p = runners[ctx.Rng:NextInteger(1, #runners)]
			RoleManager.Set(p, "Chaser")
			return { Kind = "NewHunter", Text = p.DisplayName .. " is the new Chaser!", YouText = { [p] = "YOU'RE THE CHASER!" } }
		end
	end
	return nil
end

return Mode
