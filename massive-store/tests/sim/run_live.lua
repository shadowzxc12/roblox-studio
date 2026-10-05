-- Scenario: a live (non-Studio) PUBLIC server of the Game place once both places are linked.
-- Stores only run in reserved servers made by the lobby, so anybody who lands on a public
-- store server is sent to the lobby place.
G.STUDIO = false
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.Shared.Config)
Config.Places.Lobby = 555
Config.Places.Game = 777
G.StartServer()
G.RunUntil(4)
local function check(cond, msg)
	if not cond then
		table.insert(ERRORS, "CHECK FAILED: " .. msg)
		print("CHECK FAILED: " .. msg)
	else
		print("ok: " .. msg)
	end
end
local a = G.AddPlayer("Ann")
G.RunUntil(4)
check(not a:GetAttribute("InRun"), "public store server doesn't start a run")
check(#G.TELEPORTS == 1 and G.TELEPORTS[1].PlaceId == 555, "player is sent to the lobby place")
G.Close()
G.RunUntil(3)
if #ERRORS > 0 then
	for i = 1, math.min(8, #ERRORS) do
		print(ERRORS[i])
	end
	error("live scenario failed")
end
print("LIVE SCENARIO OK")
