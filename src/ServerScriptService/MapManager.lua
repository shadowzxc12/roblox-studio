--[[
	MapManager: picks a random map from ServerStorage.Maps, clones it into Workspace,
	gives out spawn points and removes the map after the round.

	A map is a Model with:
	  Spawns (Folder)      -> Parts named "Spawn" (runners) and "ChaserSpawn" (hunters, optional)
	  attribute DisplayName -> name shown in the UI (optional)
	Add a new map = drop a new Model into ServerStorage.Maps. Nothing else to change.
]]

local ServerStorage = game:GetService("ServerStorage")

local MapManager = {}

local current: Model? = nil
local lastName: string? = nil
local rng = Random.new()

function MapManager.Load(): Model?
	MapManager.Unload()
	local maps = ServerStorage:WaitForChild("Maps"):GetChildren()
	if #maps == 0 then
		warn("[MapManager] No maps in ServerStorage.Maps")
		return nil
	end
	local choices = {}
	for _, m in maps do
		if m.Name ~= lastName or #maps == 1 then
			table.insert(choices, m)
		end
	end
	local pick = choices[rng:NextInteger(1, #choices)]
	lastName = pick.Name
	current = pick:Clone()
	current.Name = "CurrentMap"
	current:SetAttribute("SourceName", pick.Name)
	current.Parent = workspace
	return current
end

function MapManager.Unload()
	if current then
		current:Destroy()
		current = nil
	end
	local stray = workspace:FindFirstChild("CurrentMap")
	if stray then
		stray:Destroy()
	end
end

function MapManager.GetDisplayName(): string
	if not current then
		return ""
	end
	return current:GetAttribute("DisplayName") or current:GetAttribute("SourceName") or "Map"
end

local function spawnsNamed(name: string): { BasePart }
	local list = {}
	local folder = current and current:FindFirstChild("Spawns")
	if folder then
		for _, p in folder:GetChildren() do
			if p:IsA("BasePart") and p.Name == name then
				table.insert(list, p)
			end
		end
	end
	return list
end

-- A random spawn CFrame. Hunters use ChaserSpawn if the map has one.
function MapManager.GetSpawn(isHunter: boolean?): CFrame?
	local list = if isHunter then spawnsNamed("ChaserSpawn") else {}
	if #list == 0 then
		list = spawnsNamed("Spawn")
	end
	if #list == 0 then
		return nil
	end
	local p = list[rng:NextInteger(1, #list)]
	return p.CFrame + Vector3.new(rng:NextNumber(-2, 2), 3, rng:NextNumber(-2, 2))
end

function MapManager.Current(): Model?
	return current
end

return MapManager
