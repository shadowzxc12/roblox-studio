--[[
	PartyRules: which game mode a lobby launch turns into (shared so the lobby UI can grey out
	choices the server would refuse).

	  rules   = "Survival" | "Infection" | "Hardcore"   (the card picked on START A RUN)
	  solo    = true when you play alone (SOLO toggle, or a party of one)
	  size    = how many players go

	  SOLO  + SURVIVAL  -> "Solo"      (the solo-tuned survival: self-revive with a medkit)
	  SOLO  + HARDCORE  -> "Hardcore"  (one life is one life)
	  SOLO  + INFECTION -> refused     (needs somebody to turn)
	  PARTY + any       -> that mode
]]

local Config = require(script.Parent.Config)

local PartyRules = {}

function PartyRules.Resolve(rules: string, solo: boolean, size: number): (string?, string?)
	if not table.find(Config.Party.LobbyModes, rules) then
		return nil, "Unknown mode"
	end
	if solo or size <= 1 then
		if rules == "Infection" then
			return nil, "Infection needs at least 2 players"
		end
		return if rules == "Survival" then "Solo" else rules, nil
	end
	local info = Config.Modes[rules]
	if info.MinPlayers and size < info.MinPlayers then
		return nil, ("%s needs at least %d players"):format(info.Name, info.MinPlayers)
	end
	if size > (info.MaxPlayers or Config.MaxPlayers) then
		return nil, "Too many players for " .. info.Name
	end
	return rules, nil
end

-- 6 character party codes without look-alike letters
local ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
function PartyRules.NewCode(rng: Random): string
	local out = {}
	for i = 1, 6 do
		local k = rng:NextInteger(1, #ALPHABET)
		out[i] = string.sub(ALPHABET, k, k)
	end
	return table.concat(out, "", 1, 3) .. "-" .. table.concat(out, "", 4, 6)
end

return PartyRules
