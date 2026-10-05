--[[
	Missions: daily missions (3 per UTC day, the same for everyone that day).
	Progress is tracked by the server with Progress.Track(player, Stat, amount).
]]

local Util = require(script.Parent.Util)

local Missions = {}

Missions.List = {
	{ Id = "Survive3", Stat = "NightsSurvived", Goal = 3, Text = "Survive 3 nights", Credits = 60, XP = 200 },
	{ Id = "Survive5", Stat = "NightsSurvived", Goal = 5, Text = "Survive 5 nights", Credits = 100, XP = 350 },
	{ Id = "Food10", Stat = "FoodFound", Goal = 10, Text = "Find 10 food items", Credits = 30, XP = 100 },
	{ Id = "Food25", Stat = "FoodFound", Goal = 25, Text = "Find 25 food items", Credits = 50, XP = 180 },
	{ Id = "Build20", Stat = "StructuresBuilt", Goal = 20, Text = "Build 20 structures", Credits = 45, XP = 150 },
	{ Id = "Build40", Stat = "StructuresBuilt", Goal = 40, Text = "Build 40 structures", Credits = 70, XP = 250 },
	{ Id = "Revive1", Stat = "Revives", Goal = 1, Text = "Revive a teammate", Credits = 40, XP = 150 },
	{ Id = "Revive3", Stat = "Revives", Goal = 3, Text = "Revive 3 teammates", Credits = 80, XP = 300 },
	{ Id = "Rare1", Stat = "RareFound", Goal = 1, Text = "Find a rare (or better) item", Credits = 35, XP = 120 },
	{ Id = "Rare5", Stat = "RareFound", Goal = 5, Text = "Find 5 rare (or better) items", Credits = 90, XP = 320 },
	{ Id = "NoGen", Stat = "NightNoGenerator", Goal = 1, Text = "Survive a night without using a generator", Credits = 60, XP = 220 },
	{ Id = "Rooms2", Stat = "RoomsOpened", Goal = 2, Text = "Open 2 locked or hidden rooms", Credits = 50, XP = 180 },
	{ Id = "Explore8", Stat = "ZonesExplored", Goal = 8, Text = "Explore 8 different departments", Credits = 30, XP = 120 },
	{ Id = "Repel1", Stat = "LocustRepelled", Goal = 1, Text = "Drive the Locust away with your defenses", Credits = 70, XP = 260 },
	{ Id = "Refuel3", Stat = "Refuels", Goal = 3, Text = "Refuel generators 3 times", Credits = 35, XP = 120 },
	{ Id = "Loot60", Stat = "LootFound", Goal = 60, Text = "Pick up 60 items", Credits = 40, XP = 140 },
}

Missions.ById = {}
for _, m in Missions.List do
	Missions.ById[m.Id] = m
end

Missions.PerDay = 3

-- deterministic pick of the day's missions, never two with the same stat
function Missions.ForDay(day: number)
	local rng = Util.RNG(day * 7919 + 17)
	local pool = table.clone(Missions.List)
	rng:Shuffle(pool)
	local out, usedStats = {}, {}
	for _, m in pool do
		if not usedStats[m.Stat] then
			usedStats[m.Stat] = true
			table.insert(out, m.Id)
			if #out >= Missions.PerDay then
				break
			end
		end
	end
	return out
end

return Missions
