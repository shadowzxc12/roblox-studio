--[[
	MASSIVE STORE: LOCUST — server entry point (the only server Script).
	Generates a new store for this server, builds it, then starts every system.
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

Players.CharacterAutoLoads = false

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StoreLayout = require(Shared.StoreLayout)
local Net = require(Shared.Net)

local Services = script.Parent:WaitForChild("Services")
local State = require(Services.State)
local World = require(Services.World)
local Prompts = require(Services.Prompts)
local Data = require(Services.Data)
local Progress = require(Services.Progress)
local Survival = require(Services.Survival)
local Inventory = require(Services.Inventory)
local Loot = require(Services.Loot)
local Building = require(Services.Building)
local Power = require(Services.Power)
local Carts = require(Services.Carts)
local Tools = require(Services.Tools)
local Locust = require(Services.Locust)
local Defense = require(Services.Defense)
local Events = require(Services.Events)
local Infection = require(Services.Infection)
local Shop = require(Services.Shop)
local Modes = require(Services.Modes)
local Director = require(Services.Director)

-- collision groups: players walk through each other (co-op in narrow aisles)
for _, g in { "Players", "Locust" } do
	pcall(function()
		PhysicsService:RegisterCollisionGroup(g)
	end)
end
PhysicsService:CollisionGroupSetCollidable("Players", "Players", false)

-- a different store on every server
local seed = (os.time() * 7 + math.random(1, 1000000)) % 2000000000
State.Seed = seed
State.SetAttr("Seed", seed)
local t0 = os.clock()
local plan = StoreLayout.Generate(seed)
State.Plan = plan
print(("[MassiveStore] layout seed %d: %d cells, %d props, %d loot points (%.2fs)"):format(seed, #plan.CellList, #plan.Props, #plan.LootPoints, os.clock() - t0))
World.Build(plan)

Prompts.Init()
Data.Init()
Progress.Init()
Survival.Init()
Inventory.Init()
Loot.Init()
Building.Init()
Power.Init()
Carts.Init()
Tools.Init()
Locust.Init()
Defense.Init()
Events.Init()
Infection.Init()
Shop.Init()
Modes.Init()
Director.Init()

Net.Function("GetPlan").OnServerInvoke = function()
	return { Seed = State.Seed, Gates = State.GatesOpen }
end

State.SetAttr("ServerReady", true)
if RunService:IsStudio() then
	print("[MassiveStore] server ready · mode " .. State.Mode)
end
