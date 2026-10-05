--[[
	RewardManager: turns round stats into Coins / XP and saves stats.
	Everything is computed on the server from server-tracked numbers, so it can't be faked:
	- you only get participation rewards if you played most of the round
	- catch rewards are capped per round
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Modules.Config)
local DataManager = require(script.Parent.DataManager)

local RewardManager = {}

--[[
	stats: { Catches, Infections, SurvivalTime, TimesCaught, PlayedTime }
	roundLength: seconds the round actually lasted
	Returns a breakdown table that is also shown on the results screen.
]]
function RewardManager.Grant(player: Player, stats, won: boolean, roundLength: number, modeId: string)
	local R = Config.Rewards
	local coins, xp = 0, 0
	local played = roundLength >= R.MinRoundLength and stats.PlayedTime / roundLength >= R.MinParticipation

	if played then
		coins += R.Participation.Coins
		xp += R.Participation.XP
		if won then
			coins += R.Win.Coins
			xp += R.Win.XP
		end
	end

	local catches = math.min(stats.Catches + stats.Infections, R.MaxCatchesRewarded)
	coins += catches * R.Catch.Coins
	xp += catches * R.Catch.XP

	local survivalChunks = math.floor(stats.SurvivalTime / 30)
	coins += survivalChunks * R.SurvivalPer30s.Coins
	xp += survivalChunks * R.SurvivalPer30s.XP

	local newLevel = DataManager.AddRewards(player, coins, xp)
	DataManager.Update(player, function(d)
		if played then
			d.GamesPlayed += 1
			if won then
				d.Wins += 1
			else
				d.Losses += 1
			end
		end
		d.Catches += stats.Catches
		d.Infections += stats.Infections
		d.SurvivalTime += math.floor(stats.SurvivalTime)
	end)

	return { Coins = coins, XP = xp, NewLevel = newLevel, Counted = played }
end

return RewardManager
