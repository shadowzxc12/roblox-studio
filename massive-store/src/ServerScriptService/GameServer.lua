--[[
	GameServer: starts THE STORE on this server — generates a new store from a random seed,
	builds it and starts every survival system. Used by Main.server when this server is a store
	(a private server made by the lobby, or Studio where lobby and store share one server).
]]

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StoreLayout = require(Shared.StoreLayout)
local Net = require(Shared.Net)

local Services = script.Parent:WaitForChild("Services")

local GameServer = {}

-- init(service) starts a service once (the lobby shares Data / Progress / Shop)
function GameServer.Start(init: (any) -> ())
	local State = require(Services.State)
	local World = require(Services.World)

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

	for _, name in {
		"Prompts",
		"Data",
		"Progress",
		"Survival",
		"Inventory",
		"Loot",
		"Building",
		"Power",
		"Carts",
		"Tools",
		"Locust",
		"Defense",
		"Events",
		"Infection",
		"Shop",
		"Modes",
		"Director",
	} do
		init(require(Services[name]))
	end

	Net.Function("GetPlan").OnServerInvoke = function()
		return { Seed = State.Seed, Gates = State.GatesOpen }
	end
	if RunService:IsStudio() then
		print("[MassiveStore] store ready · mode " .. State.Mode)
	end
end

return GameServer
