-- Rarity levels used by loot, UI colours and XP rewards.
local Rarity = {}

Rarity.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

Rarity.Info = {
	Common = { Rank = 1, Name = "COMMON", Color = "c8ccd4", Weight = 10 },
	Uncommon = { Rank = 2, Name = "UNCOMMON", Color = "5fd36a", Weight = 5 },
	Rare = { Rank = 3, Name = "RARE", Color = "4aa8ff", Weight = 2 },
	Epic = { Rank = 4, Name = "EPIC", Color = "b76bff", Weight = 0.6 },
	Legendary = { Rank = 5, Name = "LEGENDARY", Color = "ffb31a", Weight = 0.15 },
}

-- luck: 0 on night 1, grows with nights and with locked/hidden rooms or supply drops
function Rarity.Boost(rarity: string, luck: number): number
	local L = math.max(0, luck)
	if rarity == "Common" then
		return math.max(0.35, 1 - 0.06 * L)
	elseif rarity == "Uncommon" then
		return 1 + 0.15 * L
	elseif rarity == "Rare" then
		return 1 + 0.4 * L
	elseif rarity == "Epic" then
		return 1 + 0.7 * L
	else
		return 1 + 1.0 * L
	end
end

function Rarity.Rank(rarity: string): number
	local info = Rarity.Info[rarity]
	return if info then info.Rank else 1
end

return Rarity
