-- Scenario: the Locust. Short days, then forces encounters:
-- chase + attack + down, revive, hiding (and being found later), breaking walls,
-- being driven off (resolve), a full wipe -> results -> a brand new run.

G.STUDIO = true
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local PPS = game:GetService("ProximityPromptService")
local Config = require(RS.Shared.Config)
Config.Cycle.FirstDay = 12
Config.Cycle.Day = 12
Config.Cycle.Dusk = 3
Config.Cycle.NightBase = 90
Config.Cycle.Dawn = 3
Config.Cycle.WipeResults = 6

G.StartServer()
G.RunUntil(4)
local function svc(name)
	return require(SSS.Services[name])
end
local State, Survival, Inventory, World, Building, Locust = svc("State"), svc("Survival"), svc("Inventory"), svc("World"), svc("Building"), svc("Locust")
local Remotes = RS:WaitForChild("Remotes")
local function R(name)
	return Remotes:FindFirstChild(name)
end
local function check(cond, msg)
	if not cond then
		table.insert(ERRORS, "CHECK FAILED: " .. msg)
		print("CHECK FAILED: " .. msg)
	else
		print("ok: " .. msg)
	end
end
local function waitFor(fn, timeout, step)
	local t = 0
	while not fn() and t < timeout do
		G.RunUntil(step or 0.5)
		t += step or 0.5
	end
	return fn()
end

local a, b = G.AddPlayer("Ann"), G.AddPlayer("Ben")
G.RunUntil(2)
R("Play").OnServerEvent:Fire(a, "Survival")
R("Play").OnServerEvent:Fire(b, "Survival")
G.RunUntil(2)

check(waitFor(function()
	return State.Phase == "Night" and Locust.Get() ~= nil
end, 60), "night 1 starts and the Locust spawns")
local L = Locust.Get()
check(L.Model:GetAttribute("State") ~= nil, "Locust has a state attribute")
waitFor(function()
	return L.State ~= "Spawning"
end, 6)

-- put Ann right in front of it, in plain sight
local function inFront(dist)
	local cf = L.Root.CFrame
	return CFrame.new(cf.Position + cf.LookVector * dist + Vector3.new(0, 0, 0))
end
-- Ann keeps stumbling into its field of view
local function stayInFront()
	Survival.Teleport(a, inFront(9))
end
stayInFront()
check(waitFor(function()
	if L.State ~= "Chase" then
		stayInFront()
	end
	return L.State == "Chase" and L.Target == a
end, 8, 0.2), "it notices Ann and starts the chase")
check(waitFor(function()
	return a:GetAttribute("Downed") == true
end, 30, 0.25), "Ann gets downed (attacks land)")
check(L.State ~= "Chase" or L.Target ~= a, "it doesn't camp the downed player")

-- Ben revives Ann
Survival.Teleport(b, CFrame.new(Survival.Position(a) + Vector3.new(2, 0, 0)))
local prompt = Survival.Root(a):FindFirstChild("RevivePrompt")
check(prompt ~= nil, "downed player has a revive prompt")
PPS.PromptTriggered:Fire(prompt, b)
G.RunUntil(0.5)
check(a:GetAttribute("Downed") == false, "Ben revived Ann")

-- hide Ann in a locker far from the Locust; it shouldn't find her quickly at night 1
local spotId, spot = next(World.HideSpots)
Survival.Teleport(a, spot.CFrame * CFrame.new(0, 0, -3))
PPS.PromptTriggered:Fire(spot.Prompt, a)
G.RunUntil(0.5)
check(a:GetAttribute("Hidden") == true, "Ann hides")
R("LeaveHiding").OnServerEvent:Fire(a)
G.RunUntil(0.5)
check(a:GetAttribute("Hidden") == false, "Ann leaves the hiding spot")

-- structure in the Locust's way: give Ben materials and let him build a wall right in front of it
Inventory.Give(b, "Wood", 30)
Survival.Teleport(b, inFront(10))
G.RunUntil(0.3)
local front = L.Root.Position + L.Root.CFrame.LookVector * 6
R("Build").OnServerEvent:Fire(b, { Action = "Place", Id = "WallWood", Position = Vector3.new(front.X, 0, front.Z), Rotation = 0 })
G.RunUntil(0.5)
local count = 0
for _ in Building.All() do
	count += 1
end
check(count >= 1, "Ben built a wall (" .. count .. " structures)")

-- drive it off with resolve damage
Locust.Hurt(L.MaxResolve + 10, b)
G.RunUntil(0.5)
check(L.State == "Retreat", "enough resolve damage makes it retreat")
G.RunUntil(Config.Locust.RetreatTime + 2)
check(L.State ~= "Retreat", "it comes back after retreating")

-- stun
Locust.Stun(2, b)
check(L.State == "Stunned", "stun works")
G.RunUntil(3)
check(L.State ~= "Stunned", "stun wears off")

-- survive to dawn
check(waitFor(function()
	return State.Phase == "Dawn" or State.Phase == "Day"
end, 120), "dawn comes")
check(Locust.Get() == nil, "the Locust leaves at dawn")
check(State.Night == 1, "night counter is 1")

-- night 2: everyone goes down -> wipe -> results -> new run
check(waitFor(function()
	return State.Phase == "Night"
end, 60), "night 2 starts")
local runBefore = State.RunId
for _, p in { a, b } do
	Survival.Damage(p, 500, "Test")
end
G.RunUntil(1)
check(a:GetAttribute("Downed") and b:GetAttribute("Downed"), "both downed")
check(waitFor(function()
	return State.Phase == "Results"
end, 60), "wipe -> results screen")
check(waitFor(function()
	return State.RunId > runBefore and State.Phase == "Day"
end, 40), "a new run starts after the results")
check(a:GetAttribute("InRun") and Survival.IsActive(a), "players are back in the new run")
check(State.Night == 0, "night counter reset")

-- leave to menu mid run drops a bag
Inventory.Give(a, "Apple", 3)
R("Menu").OnServerEvent:Fire(a, "ReturnToMenu")
G.RunUntil(1)
check(a:GetAttribute("InRun") == false, "Ann went back to the menu")
local bags = 0
for _, c in World.Folders.Dynamic:GetChildren() do
	if c.Name == "Bag" then
		bags += 1
	end
end
check(bags >= 1, "her supplies were left in a bag")
R("Play").OnServerEvent:Fire(a, "Survival")
G.RunUntil(2)
check(a:GetAttribute("InRun") == true, "Ann rejoined the running store")

if #ERRORS > 0 then
	print(("FAILED with %d errors"):format(#ERRORS))
	for i = 1, math.min(8, #ERRORS) do
		print(ERRORS[i])
	end
	error("locust scenario failed")
end
print("LOCUST SCENARIO OK")
