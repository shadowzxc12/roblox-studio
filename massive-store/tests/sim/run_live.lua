-- Scenario: a live (non-Studio) PUBLIC server. Lobby and store are one place: public servers
-- are the lobby (parking lot, party, shop), only private servers made by the lobby run a store.
G.STUDIO = false
local RS = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
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
check(RS:GetAttribute("Place") == "Lobby", "public server runs the lobby")
check(Workspace:FindFirstChild("Lobby") ~= nil and Workspace:FindFirstChild("Store") == nil, "parking lot, no store")
local a = G.AddPlayer("Ann")
G.RunUntil(4)
check(not a:GetAttribute("InRun"), "nobody is put in a run on the lobby")
check(a:GetAttribute("PartyId") ~= nil, "everybody gets a party")
check(a.Character ~= nil, "lobby avatar loaded")
check(#G.TELEPORTS == 0, "nobody is teleported away")
G.Close()
G.RunUntil(3)
if #ERRORS > 0 then
	for i = 1, math.min(8, #ERRORS) do
		print(ERRORS[i])
	end
	error("live scenario failed")
end
print("LIVE SCENARIO OK")
