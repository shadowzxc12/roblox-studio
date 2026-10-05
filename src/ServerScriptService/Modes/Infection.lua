--[[
	INFECTION
	- one random Infected (two on big servers), everyone else is a Survivor
	- Infected tags Survivor -> the Survivor becomes Infected (forever, this round)
	- everyone infected -> Infected win
	- timer ends with at least one Survivor -> Survivors win
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Util = require(ReplicatedStorage.Modules.Util)
local Config = require(ReplicatedStorage.Modules.Config)
local RoleManager = require(script.Parent.Parent.RoleManager)
local TagManager = require(script.Parent.Parent.TagManager)

local Mode = {}
Mode.Id = "Infection"
Mode.HunterRole = "Infected"
Mode.PreyRole = "Survivor"

local function withRole(ctx, role)
	local list = {}
	for _, p in ctx.Participants() do
		if RoleManager.Get(p) == role then
			table.insert(list, p)
		end
	end
	return list
end

function Mode.HunterCount(playerCount: number): number
	return if playerCount >= 10 then 2 else 1
end

function Mode.Setup(ctx, players: { Player }): { Player }
	Util.Shuffle(players, ctx.Rng)
	local first = {}
	for i, p in players do
		if i <= Mode.HunterCount(#players) then
			RoleManager.Set(p, "Infected")
			table.insert(first, p)
		else
			RoleManager.Set(p, "Survivor")
		end
	end
	return first
end

function Mode.OnTag(ctx, hunter: Player, prey: Player)
	RoleManager.Set(prey, "Infected")
	TagManager.SetCooldown(prey, 1)
	ctx.Stats[hunter].Infections += 1
	ctx.Stats[prey].TimesCaught += 1
	return {
		Kind = "Infect",
		Text = hunter.DisplayName .. " infected " .. prey.DisplayName .. "!",
		YouText = { [prey] = "YOU'VE BEEN INFECTED!" },
	}
end

function Mode.CheckWin(ctx)
	if #withRole(ctx, "Survivor") == 0 then
		return { Winner = "Hunters", Title = "INFECTED WIN!" }
	end
	return nil
end

function Mode.OnTimeUp(ctx)
	return { Winner = "Prey", Title = "SURVIVORS WIN!" }
end

function Mode.IsWinner(ctx, player: Player, result): boolean
	local role = RoleManager.Get(player)
	if result.Winner == "Prey" then
		return role == "Survivor"
	end
	return role == "Infected"
end

-- If all infected players left, infect a random survivor so the round continues.
function Mode.OnPlayerRemoved(ctx)
	if #withRole(ctx, "Infected") == 0 then
		local survivors = withRole(ctx, "Survivor")
		if #survivors >= 2 then
			local p = survivors[ctx.Rng:NextInteger(1, #survivors)]
			RoleManager.Set(p, "Infected")
			TagManager.SetCooldown(p, Config.Tag.NewHunterDelay)
			return { Kind = "NewHunter", Text = p.DisplayName .. " is now INFECTED!", YouText = { [p] = "YOU'VE BEEN INFECTED!" } }
		end
	end
	return nil
end

return Mode
