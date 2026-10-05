--[[
	ClientState: what the client knows (read-only copies from the server) + signals.
	The store plan is rebuilt locally from the server's seed (StoreLayout with SkipProps),
	so the HUD and the map know every department without big network transfers.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local StoreLayout = require(Shared.StoreLayout)

local ClientState = {
	Data = nil,
	Inventory = { Size = 12, Slots = {}, Selected = 0 },
	Container = nil,
	Squad = {},
	Plan = nil,
	Objective = "",
	TeamObjective = "",
	Discovered = {}, -- [cellId] = true
	MenuOpen = true,
	Busy = {}, -- UI layers that capture input: [name] = true

	DataChanged = Signal.new(),
	InventoryChanged = Signal.new(),
	ContainerChanged = Signal.new(),
	SquadChanged = Signal.new(),
	ObjectiveChanged = Signal.new(),
	PlanReady = Signal.new(),
}

local player = Players.LocalPlayer

function ClientState.SetBusy(name: string, on: boolean)
	ClientState.Busy[name] = if on then true else nil
end

function ClientState.IsBusy(): boolean
	return next(ClientState.Busy) ~= nil
end

function ClientState.InRun(): boolean
	return player:GetAttribute("InRun") == true
end

function ClientState.Attr(name: string)
	return ReplicatedStorage:GetAttribute(name)
end

local function buildPlan()
	local seed = ReplicatedStorage:GetAttribute("Seed")
	while not seed do
		ReplicatedStorage:GetAttributeChangedSignal("Seed"):Wait()
		seed = ReplicatedStorage:GetAttribute("Seed")
	end
	ClientState.Plan = StoreLayout.Generate(seed, { SkipProps = true })
	ClientState.PlanReady:Fire(ClientState.Plan)
end

-- zone / cell the local player stands in
function ClientState.Where()
	local plan = ClientState.Plan
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not plan or not root then
		return nil, nil
	end
	local p = root.Position
	return StoreLayout.ZoneAt(plan, p.X, p.Y, p.Z)
end

function ClientState.Init()
	Net.Event("Data").OnClientEvent:Connect(function(data)
		ClientState.Data = data
		ClientState.DataChanged:Fire(data)
	end)
	Net.Event("Inventory").OnClientEvent:Connect(function(inv)
		ClientState.Inventory = inv
		ClientState.InventoryChanged:Fire(inv)
	end)
	Net.Event("Container").OnClientEvent:Connect(function(c)
		ClientState.Container = c
		ClientState.ContainerChanged:Fire(c)
	end)
	Net.Event("Squad").OnClientEvent:Connect(function(list)
		ClientState.Squad = list
		ClientState.SquadChanged:Fire(list)
	end)
	Net.Event("Objective").OnClientEvent:Connect(function(text, teamText)
		ClientState.Objective = text or ""
		ClientState.TeamObjective = teamText or ""
		ClientState.ObjectiveChanged:Fire(text)
	end)
	task.spawn(function()
		local ok, data = pcall(function()
			return Net.Function("GetData"):InvokeServer()
		end)
		if ok and data then
			ClientState.Data = data
			ClientState.DataChanged:Fire(data)
		end
	end)
	task.spawn(buildPlan)
	-- remember explored cells (for the map)
	task.spawn(function()
		while true do
			task.wait(1)
			local _, cell = ClientState.Where()
			if cell then
				ClientState.Discovered[cell.Id] = true
			end
		end
	end)
	ReplicatedStorage:GetAttributeChangedSignal("RunId"):Connect(function()
		table.clear(ClientState.Discovered)
	end)
end

return ClientState
