-- Scenario: by DAY the Locust roams the store but never hunts or attacks; at night the same
-- creature wakes up and becomes the hunter.
G.STUDIO = true
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Config = require(RS.Shared.Config)
Config.Cycle.FirstDay = 60
Config.Cycle.Day = 60
Config.Cycle.Dusk = 3
Config.Cycle.NightBase = 40
Config.Locust.DaySpawnDelay = 3
local function check(cond, msg)
	if not cond then
		table.insert(ERRORS, "CHECK FAILED: " .. msg)
		print("CHECK FAILED: " .. msg)
	else
		print("ok: " .. msg)
	end
end
G.StartServer()
G.RunUntil(4)
local State = require(SSS.Services.State)
local Survival = require(SSS.Services.Survival)
local Locust = require(SSS.Services.Locust)
local p = G.AddPlayer("Shopper")
G.RunUntil(2)
RS.Remotes:FindFirstChild("Play").OnServerEvent:Fire(p, "Survival")
G.RunUntil(10)
check(State.Phase == "Day", "it's day")
local L = Locust.Get()
check(L ~= nil and L.Passive == true, "the Locust roams the store by day")
-- stand right in front of it for a while
local hp = p:GetAttribute("Health")
local sawChase = false
for _ = 1, 40 do
	if L and L.Root then
		Survival.Teleport(p, CFrame.new(L.Root.Position + L.Root.CFrame.LookVector * 8))
	end
	G.RunUntil(0.5)
	if L and (L.State == "Chase" or L.State == "Break") then
		sawChase = true
	end
end
check(not sawChase, "it never hunts or breaks things by day")
check(p:GetAttribute("Health") == hp and not p:GetAttribute("Downed"), "it never attacks by day")
check(L and L.Model:GetAttribute("Watching") ~= nil, "it stops to stare at you")
-- night: the same creature wakes up
for _ = 1, 200 do
	if State.Phase == "Night" then
		break
	end
	G.RunUntil(0.5)
end
G.RunUntil(1)
check(Locust.Get() == L and L.Passive == false, "at night the roamer wakes up as the hunter")
-- night, alone, right next to it: it bites, downs you and (nobody can save you) kills you
G.RunUntil(Config.Survival.SpawnProtection + 1)
local died = false
for _ = 1, 80 do
	local L2 = Locust.Get()
	if L2 and L2.Root and not p:GetAttribute("Downed") and not p:GetAttribute("Dead") then
		Survival.Teleport(p, CFrame.new(L2.Root.Position + L2.Root.CFrame.LookVector * 4 - Vector3.new(0, 3, 0)))
	end
	G.RunUntil(0.5)
	if p:GetAttribute("Dead") then
		died = true
		break
	end
end
check((p:GetAttribute("Health") or 100) < 100 or died, "at night it bites when you're next to it")
check(died, "alone and downed, it finishes you off")
if #ERRORS > 0 then
	error(ERRORS[1])
end
print("DAY SCENARIO OK")
