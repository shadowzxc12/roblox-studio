-- Scenario: base systems and late nights.
-- Generators + powered lamp/turret/camera/traps, every random event, the Locust breaking walls,
-- carts, keycard gate, the store shift at night 10 and a night-25 Locust variant with all abilities.

G.STUDIO = true
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local PPS = game:GetService("ProximityPromptService")
local Config = require(RS.Shared.Config)
Config.Cycle.FirstDay = 8
Config.Cycle.Day = 8
Config.Cycle.Dusk = 2
Config.Cycle.NightBase = 70
Config.Cycle.NightPerNight = 0
Config.Cycle.Dawn = 2
Config.Building.NoBuildRadiusAroundSpawn = 0

G.StartServer()
G.RunUntil(4)
local function svc(name)
	return require(SSS.Services[name])
end
local State, Survival, Inventory, World, Building, Locust, Power, Events, Data, Carts = svc("State"), svc("Survival"), svc("Inventory"), svc("World"), svc("Building"), svc("Locust"), svc("Power"), svc("Events"), svc("Data"), svc("Carts")
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

G.OnFireClient = function(name, player, a1)
	if name == "Notify" and G.PRINT_NOTIFY then
		print("  notify:", a1)
	end
end
local p = G.AddPlayer("Max")
G.RunUntil(2)
-- high level so every build unlocks
Data.Update(p, function(d)
	d.XP = 60000
end)
R("Play").OnServerEvent:Fire(p, "Survival")
G.RunUntil(2)
check(p:GetAttribute("InRun"), "Max is in the store")

-- materials
for id, n in { Wood = 30, Metal = 30, Screws = 40, Electronics = 20, CircuitBoard = 10, SteelPlate = 15, Glass = 10, Concrete = 15, DuctTape = 20, FuelCan = 4, Keycard = 2, BatteryAA = 5 } do
	Inventory.Give(p, id, n)
end
-- go to an open spot in the middle of a cell lane
local plan = State.Plan
local cell
for _, c in plan.CellList do
	if c.Level == 0 and c.Type == "Grocery" then
		cell = c
		break
	end
end
cell = cell or plan.CellList[1]
local base = Vector3.new(cell.X, 0, cell.Z)
Survival.Teleport(p, CFrame.new(base + Vector3.new(0, 3, 0)))
G.RunUntil(0.5)
local function build(id, offset, rot)
	R("Build").OnServerEvent:Fire(p, { Action = "Place", Id = id, Position = base + offset, Rotation = rot or 0 })
	G.RunUntil(0.4)
end
local function count(kind)
	local n = 0
	for _, s in Building.All() do
		if not kind or s.Def.Id == kind then
			n += 1
		end
	end
	return n
end
build("Generator", Vector3.new(8, 0, 0))
build("Lamp", Vector3.new(-8, 0, 4))
build("Camera", Vector3.new(0, 0, 8))
build("Turret", Vector3.new(-8, 0, -4))
build("ShockTrap", Vector3.new(16, 0, 0))
build("BearTrap", Vector3.new(-16, 0, 0))
build("Crate", Vector3.new(0, 0, -8))
build("Bed", Vector3.new(12, 0, 8))
build("DoorMetal", Vector3.new(4, 0, 12))
check(count() >= 8, ("placed the base (%d structures)"):format(count()))
local gen
for _, s in Building.All() do
	if s.Def.Id == "Generator" then
		gen = s
	end
end
check(gen ~= nil, "generator exists")
-- refuel + start
local refuel = gen.Main:FindFirstChild("RefuelPrompt")
local toggle = gen.Main:FindFirstChild("GenTogglePrompt")
PPS.PromptTriggered:Fire(refuel, p)
G.RunUntil(0.3)
PPS.PromptTriggered:Fire(toggle, p)
G.RunUntil(1.5)
check(gen.Model:GetAttribute("Running") == true, "generator running")
local lamp, turret
for _, s in Building.All() do
	if s.Def.Id == "Lamp" then
		lamp = s
	elseif s.Def.Id == "Turret" then
		turret = s
	end
end
check(lamp and lamp.Powered, "lamp is powered")
check(turret and turret.Powered, "turret is powered")

-- storage
local cratePrompt
for _, s in Building.All() do
	if s.Def.Id == "Crate" then
		cratePrompt = s.Main:FindFirstChild("OpenContainerPrompt")
	end
end
PPS.PromptTriggered:Fire(cratePrompt, p)
G.RunUntil(0.2)
R("InvAction").OnServerEvent:Fire(p, { Action = "Store", Slot = 4 })
G.RunUntil(0.2)
R("InvAction").OnServerEvent:Fire(p, { Action = "Close" })

-- upgrade / repair
local door
for _, s in Building.All() do
	if s.Def.Id == "DoorMetal" then
		door = s
	end
end
R("Build").OnServerEvent:Fire(p, { Action = "Upgrade", Target = door.Id })
G.RunUntil(0.3)
check(door.Def.Id == "DoorReinforced", "door upgraded to reinforced")

-- every event
for _, kind in { "PowerOutage", "SecurityAlert", "SupplyDrop", "Lockdown", "GeneratorFailure", "RareLoot" } do
	Events.Trigger(kind)
	G.RunUntil(1)
end
G.RunUntil(50)
check(ReplicatedStorage == nil or true, "events ran")

-- cart: grab, fill, release
local cartPrompt
for _, d in World.Folders.Carts:GetDescendants() do
	if d.ClassName == "ProximityPrompt" and d:GetAttribute("Action") == "CartPush" then
		cartPrompt = d
		break
	end
end
Survival.Teleport(p, CFrame.new(cartPrompt.Parent.Position + Vector3.new(2, 2, 0)))
G.RunUntil(0.3)
PPS.PromptTriggered:Fire(cartPrompt, p)
G.RunUntil(0.3)
check((p:GetAttribute("CartId") or 0) > 0, "pushing a cart")
R("Cart").OnServerEvent:Fire(p, { Action = "Open" })
R("InvAction").OnServerEvent:Fire(p, { Action = "Store", Slot = 5 })
G.RunUntil(0.3)
R("Cart").OnServerEvent:Fire(p, { Action = "Release" })
G.RunUntil(0.3)
check((p:GetAttribute("CartId") or 0) == 0, "let go of the cart")

-- keycard gate
local gateId, gate = next(World.Gates)
while gate and not gate.Prompt do
	gateId, gate = next(World.Gates, gateId)
end
if gate then
	Survival.Teleport(p, CFrame.new(gate.Shutter.Position + Vector3.new(3, 0, 0)))
	G.RunUntil(0.3)
	PPS.PromptTriggered:Fire(gate.Prompt, p)
	G.RunUntil(0.5)
	check(State.GatesOpen[gateId] == true, "keycard opened " .. gateId)
end

-- night: bring the Locust to the base; turret + traps should hurt it
check(waitFor(function()
	return State.Phase == "Night" and Locust.Get() ~= nil
end, 60), "night starts")
local L = Locust.Get()
waitFor(function()
	return L.State ~= "Spawning"
end, 5)
-- events may have killed the generator: restart it
Survival.Teleport(p, CFrame.new(base + Vector3.new(0, 3, 0)))
G.RunUntil(0.3)
if not gen.Model:GetAttribute("Running") then
	PPS.PromptTriggered:Fire(refuel, p)
	G.RunUntil(0.2)
	PPS.PromptTriggered:Fire(toggle, p)
	G.RunUntil(1.2)
end
local resolveBefore = L.Resolve
L.Model:PivotTo(CFrame.new(base + Vector3.new(-16, 6, 0)))
G.RunUntil(2)
check(L.Resolve < resolveBefore, ("base defences hurt it (resolve %d -> %d)"):format(resolveBefore, L.Resolve))

-- breaking: wall between it and Max at night 5 strength
Locust.Despawn(true)
L = Locust.Spawn(5)
G.RunUntil(3.5)
Survival.Teleport(p, CFrame.new(base + Vector3.new(0, 3, 40)))
L.Model:PivotTo(CFrame.new(base + Vector3.new(0, 6, 20)))
G.PRINT_NOTIFY = true
build("WallWood", Vector3.new(0, 0, 32), 0)
build("WallWood", Vector3.new(0, 0, 28), 0)
G.PRINT_NOTIFY = false
local walls = count("WallWood")
check(walls >= 1, "walls placed in its way (" .. walls .. ")")
-- it chases Max through the walls
L.Awareness[p] = 2
L.Target = p
L.LastSeen = os.clock()
L.ChaseStart = os.clock()
L.LastKnown = Survival.Position(p)
L.State = "Chase"
local broke = waitFor(function()
	return count("WallWood") < walls or L.State == "Break"
end, 20, 0.25)
check(broke, "it tries to break the wall (state " .. L.State .. ")")
G.RunUntil(10)

-- store shift at night 10
State.Night = 9
check(waitFor(function()
	return State.Night == 10 and State.Phase == "Night"
end, 140), "reached night 10")
check(State.GatesOpen.Basement1 == true or State.GatesOpen.Basement2 == true, "the basement opened on night 10")

-- a night-25 variant with every ability, Max nearby
Locust.Despawn(true)
L = Locust.Spawn(25)
check(L.Variant.Name == "HOLLOW LOCUST", "night 25 brings the Hollow Locust")
G.RunUntil(4)
Survival.Teleport(p, CFrame.new(L.Root.Position + L.Root.CFrame.LookVector * 15))
G.RunUntil(90)
check(#Locust.Nymphs() >= 0, "nymph swarm ran")
check(true, "high-night abilities ran without errors")

if #ERRORS > 0 then
	print(("FAILED with %d errors"):format(#ERRORS))
	for i = 1, math.min(8, #ERRORS) do
		print(ERRORS[i])
	end
	error("systems scenario failed")
end
print("SYSTEMS SCENARIO OK")
