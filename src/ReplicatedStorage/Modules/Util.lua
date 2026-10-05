-- Small helpers shared by server and client.
local Config = require(script.Parent.Config)

local Util = {}

-- 154 -> "02:34"
function Util.FormatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	return string.format("%02d:%02d", seconds // 60, seconds % 60)
end

-- 1250 -> "1,250"
function Util.FormatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

-- Total XP -> level, xp inside the current level, xp needed for next level
function Util.LevelFromXP(totalXP: number): (number, number, number)
	local level = 1
	local remaining = totalXP
	while remaining >= Config.XPForLevel(level) do
		remaining -= Config.XPForLevel(level)
		level += 1
	end
	return level, remaining, Config.XPForLevel(level)
end

function Util.Shuffle<T>(list: { T }, rng: Random): { T }
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

return Util
