-- Scenario: a reserved server created by matchmaking learns its mode from TeleportData.
G.STUDIO = false
G.TELEPORT_DATA = { Mode = "Infection", AccessCode = "code-123" }
rawget(game, "_p").PrivateServerId = "psid-1"
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
G.StartServer()
G.RunUntil(3)
local p = G.AddPlayer("Teleported")
G.RunUntil(3)
local State = require(SSS.Services.State)
local Modes = require(SSS.Services.Modes)
assert(State.Mode == "Infection", "reserved server mode from TeleportData, got " .. tostring(State.Mode))
assert(Modes.AccessCode == "code-123", "remembers its access code")
RS:WaitForChild("Remotes"):FindFirstChild("Play").OnServerEvent:Fire(p, "Infection")
G.RunUntil(3)
assert(p:GetAttribute("InRun"), "player enters the infection store")
if #ERRORS > 0 then
	error(ERRORS[1])
end
print("RESERVED SCENARIO OK")
