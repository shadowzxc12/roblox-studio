-- Scenario: a private store server made by the LOBBY for a party.
--   TeleportData sets the mode, everybody walks straight into the store (no menu),
--   leaving mid-run teleports you alone, the results screen sends the voters back together
--   with a PartyKey so the lobby rebuilds the party.
G.STUDIO = false
G.TELEPORT_DATA = { Mode = "Infection", Rules = "Infection", PartyKey = "job:1", Leader = 1002, Members = { 1001, 1002, 1003 } }
rawget(game, "_p").PrivateServerId = "psid-1"
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Config = require(RS.Shared.Config)
Config.Places.Lobby = 555
Config.Places.Game = 777
Config.Cycle.FirstDay = 4
Config.Cycle.Day = 4
Config.Cycle.Dusk = 2
Config.Cycle.NightBase = 40
Config.Cycle.NightPerNight = 0
local function check(cond, msg)
	if not cond then
		table.insert(ERRORS, "CHECK FAILED: " .. msg)
		print("CHECK FAILED: " .. msg)
	else
		print("ok: " .. msg)
	end
end
G.StartServer()
G.RunUntil(3)
local p1, p2, p3 = G.AddPlayer("One"), G.AddPlayer("Two"), G.AddPlayer("Three")
G.RunUntil(5)
local State = require(SSS.Services.State)
local Survival = require(SSS.Services.Survival)
check(State.Mode == "Infection", "reserved server mode from TeleportData, got " .. tostring(State.Mode))
check(p1:GetAttribute("InRun") and p2:GetAttribute("InRun") and p3:GetAttribute("InRun"), "the whole party walks straight into the store")

-- one leaves mid-run from the pause menu: alone, no party key
RS:WaitForChild("Remotes"):FindFirstChild("Lobby").OnServerEvent:Fire(p3, "Return")
G.RunUntil(1)
check(#G.TELEPORTS == 1 and G.TELEPORTS[1].PlaceId == 555 and #G.TELEPORTS[1].Players == 1, "leaving mid-run teleports only you to the lobby")
check(G.TELEPORTS[1].Data and G.TELEPORTS[1].Data.PartyKey == nil, "a lone leaver has no party key")
G.RemovePlayer(p3)

-- everyone falls at night -> results; both vote BACK TO LOBBY
for _ = 1, 200 do
	if State.Phase == "Night" then
		break
	end
	G.RunUntil(0.5)
end
G.RunUntil(Config.Survival.SpawnProtection + 1)
Survival.Damage(p1, 500, "Test")
Survival.Damage(p2, 500, "Test")
for _ = 1, 200 do
	G.RunUntil(0.5)
	if State.Phase == "Results" then
		break
	end
end
check(State.Phase == "Results", "the run ended")
RS.Remotes:FindFirstChild("Lobby").OnServerEvent:Fire(p1, "Return")
G.RunUntil(0.5)
check(#G.TELEPORTS == 1, "first vote waits for the others")
RS.Remotes:FindFirstChild("Lobby").OnServerEvent:Fire(p2, "Return")
G.RunUntil(0.5)
local t = G.TELEPORTS[2]
check(t and #t.Players == 2 and t.PlaceId == 555, "both go back to the lobby in one teleport")
check(t and t.Data and type(t.Data.PartyKey) == "string" and t.Data.Leader == 1002, "with a party key and the same leader")
if #ERRORS > 0 then
	error(ERRORS[1])
end
print("RESERVED SCENARIO OK")
