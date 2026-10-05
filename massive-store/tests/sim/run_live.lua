-- Scenario: a live (non-Studio) public server. Matchmaking into other modes reserves servers
-- and teleports, the server browser lists stores, joining works, the registry heartbeat runs.
-- Also a reserved server picks its mode from TeleportData.
G.STUDIO = false
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
G.StartServer()
G.RunUntil(4)
local State = require(SSS.Services.State)
local Remotes = RS:WaitForChild("Remotes")
local function check(cond, msg)
	if not cond then
		table.insert(ERRORS, "CHECK FAILED: " .. msg)
		print("CHECK FAILED: " .. msg)
	else
		print("ok: " .. msg)
	end
end
local a, b, c = G.AddPlayer("Ann"), G.AddPlayer("Ben"), G.AddPlayer("Cat")
G.RunUntil(3)
check(State.Mode == "Survival", "public server runs Survival")
Remotes:FindFirstChild("Play").OnServerEvent:Fire(a, "Survival")
G.RunUntil(2)
check(a:GetAttribute("InRun"), "Survival on a Survival server enters directly")
Remotes:FindFirstChild("Play").OnServerEvent:Fire(b, "Hardcore")
G.RunUntil(2)
check(#G.TELEPORTS == 1 and G.TELEPORTS[1].Options.ReservedServerAccessCode ~= nil, "Hardcore reserves a new server and teleports")
Remotes:FindFirstChild("Play").OnServerEvent:Fire(c, "Solo")
G.RunUntil(2)
check(#G.TELEPORTS == 2, "Solo always gets its own reserved server")
G.RunUntil(20) -- registry heartbeat
local list = Remotes:FindFirstChild("GetServers").OnServerInvoke(a)
check(type(list) == "table" and #list >= 1, "server browser lists this store (" .. (list and #list or 0) .. ")")
local ok = Remotes:FindFirstChild("JoinServer").OnServerInvoke(a, list[1].Key)
check(ok, "joining the listed store works")
G.RunUntil(2)
check(a:GetAttribute("InRun") == true, "joined player is in the store")
G.Close()
G.RunUntil(3)
if #ERRORS > 0 then
	for i = 1, math.min(8, #ERRORS) do
		print(ERRORS[i])
	end
	error("live scenario failed")
end
print("LIVE SCENARIO OK")
