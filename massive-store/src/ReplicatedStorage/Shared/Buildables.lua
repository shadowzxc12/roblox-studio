--[[
	Buildables: everything players can place to make a base.

	Tier: 0 = no tier, 1 = Wood, 2 = Metal, 3 = Reinforced, 4 = Advanced
	The Locust gets better at breaking higher tiers as the nights go on (Config.BreakMultiplier),
	so bases have to be upgraded.

	Fields
	  Kind      Wall | Door | Window | Floor | Barricade | Table | Storage | Bed | Light | Camera
	            | Trap | Generator | Turret | Decoration
	  Size      {x, y, z} studs (walls are 8 long, 8 tall, 1 thick)
	  Cost      { ItemId = count }
	  HP        hit points
	  Upgrade   id of the next tier (upgrading costs Config.Building.UpgradeCostFraction of its cost)
	  Unlock    player level needed (Progression)
	  Power     power units used from a generator (Lights, Cameras, Turrets, Shock traps)
	  Slots     storage size
	  Cosmetic  requires owning this cosmetic (Store Credits shop) - decorations only
]]

local Buildables = {}

Buildables.TierInfo = {
	[0] = { Name = "", Color = "c8ccd4" },
	[1] = { Name = "WOOD", Color = "c08a4f" },
	[2] = { Name = "METAL", Color = "9aa4ae" },
	[3] = { Name = "REINFORCED", Color = "6e8cff" },
	[4] = { Name = "ADVANCED", Color = "ffb31a" },
}

Buildables.Categories = { "Walls", "Doors", "Floors", "Furniture", "Power", "Defense", "Decor" }

local LIST = {
	--============================ WALLS ============================--
	{ Id = "WallWood", Name = "Wood Wall", Category = "Walls", Kind = "Wall", Tier = 1, Size = { 8, 8, 1 }, HP = 160, Cost = { Wood = 4 }, Upgrade = "WallMetal", Unlock = 1, Color = "a8743f", Material = "WoodPlanks" },
	{ Id = "WallMetal", Name = "Metal Wall", Category = "Walls", Kind = "Wall", Tier = 2, Size = { 8, 8, 1 }, HP = 450, Cost = { Metal = 4, Screws = 3 }, Upgrade = "WallReinforced", Unlock = 3, Color = "8e969e", Material = "DiamondPlate" },
	{ Id = "WallReinforced", Name = "Reinforced Wall", Category = "Walls", Kind = "Wall", Tier = 3, Size = { 8, 8, 1.4 }, HP = 1100, Cost = { SteelPlate = 2, Metal = 3, Concrete = 2 }, Upgrade = "WallAdvanced", Unlock = 8, Color = "5d6f8f", Material = "Concrete" },
	{ Id = "WallAdvanced", Name = "Advanced Wall", Category = "Walls", Kind = "Wall", Tier = 4, Size = { 8, 8, 1.6 }, HP = 2600, Cost = { Alloy = 2, SteelPlate = 2, CircuitBoard = 1, Concrete = 2 }, Unlock = 16, Color = "2f3540", Material = "Metal", Glow = "ffb31a" },
	{ Id = "WindowWood", Name = "Wood Window", Category = "Walls", Kind = "Window", Tier = 1, Size = { 8, 8, 1 }, HP = 110, Cost = { Wood = 3, Glass = 1 }, Upgrade = "WindowMetal", Unlock = 1, Color = "a8743f", Material = "WoodPlanks" },
	{ Id = "WindowMetal", Name = "Metal Window", Category = "Walls", Kind = "Window", Tier = 2, Size = { 8, 8, 1 }, HP = 320, Cost = { Metal = 3, Glass = 1, Screws = 2 }, Unlock = 3, Color = "8e969e", Material = "DiamondPlate" },
	{ Id = "BarricadeWood", Name = "Wood Barricade", Category = "Walls", Kind = "Barricade", Tier = 1, Size = { 8, 4, 1.5 }, HP = 90, Cost = { Wood = 2 }, Upgrade = "BarricadeMetal", Unlock = 1, Color = "b5814a", Material = "WoodPlanks" },
	{ Id = "BarricadeMetal", Name = "Metal Barricade", Category = "Walls", Kind = "Barricade", Tier = 2, Size = { 8, 4, 1.5 }, HP = 260, Cost = { Metal = 2, Screws = 1 }, Unlock = 3, Color = "8e969e", Material = "DiamondPlate" },

	--============================ DOORS ============================--
	{ Id = "DoorWood", Name = "Wood Door", Category = "Doors", Kind = "Door", Tier = 1, Size = { 8, 8, 1 }, HP = 140, Cost = { Wood = 5, Screws = 1 }, Upgrade = "DoorMetal", Unlock = 1, Color = "8d5a2b", Material = "WoodPlanks" },
	{ Id = "DoorMetal", Name = "Metal Door", Category = "Doors", Kind = "Door", Tier = 2, Size = { 8, 8, 1 }, HP = 420, Cost = { Metal = 5, Screws = 3 }, Upgrade = "DoorReinforced", Unlock = 3, Color = "7d858d", Material = "DiamondPlate" },
	{ Id = "DoorReinforced", Name = "Vault Door", Category = "Doors", Kind = "Door", Tier = 3, Size = { 8, 8, 1.4 }, HP = 1000, Cost = { SteelPlate = 3, Metal = 3, Electronics = 1 }, Upgrade = "DoorAdvanced", Unlock = 8, Color = "4f5f7f", Material = "Metal" },
	{ Id = "DoorAdvanced", Name = "Blast Door", Category = "Doors", Kind = "Door", Tier = 4, Size = { 8, 8, 1.6 }, HP = 2400, Cost = { Alloy = 3, SteelPlate = 2, CircuitBoard = 2 }, Unlock = 16, Color = "262b33", Material = "Metal", Glow = "ffb31a", Power = 1 },

	--============================ FLOORS ============================--
	{ Id = "FloorWood", Name = "Wood Floor / Ceiling", Category = "Floors", Kind = "Floor", Tier = 1, Size = { 8, 1, 8 }, HP = 160, Cost = { Wood = 4 }, Upgrade = "FloorMetal", Unlock = 1, Color = "a8743f", Material = "WoodPlanks" },
	{ Id = "FloorMetal", Name = "Metal Floor / Ceiling", Category = "Floors", Kind = "Floor", Tier = 2, Size = { 8, 1, 8 }, HP = 450, Cost = { Metal = 4, Screws = 2 }, Unlock = 3, Color = "8e969e", Material = "DiamondPlate" },
	{ Id = "Ramp", Name = "Wood Ramp", Category = "Floors", Kind = "Ramp", Tier = 1, Size = { 8, 8, 8 }, HP = 160, Cost = { Wood = 5 }, Unlock = 2, Color = "a8743f", Material = "WoodPlanks" },

	--============================ FURNITURE ============================--
	{ Id = "Table", Name = "Table", Category = "Furniture", Kind = "Table", Tier = 0, Size = { 6, 3, 4 }, HP = 80, Cost = { Wood = 3 }, Unlock = 1, Color = "8d6e63", Material = "Wood" },
	{ Id = "Crate", Name = "Storage Crate", Category = "Furniture", Kind = "Storage", Tier = 1, Size = { 4, 3, 3 }, HP = 120, Cost = { Wood = 5 }, Slots = 10, Unlock = 1, Color = "b5814a", Material = "WoodPlanks" },
	{ Id = "Locker", Name = "Metal Locker", Category = "Furniture", Kind = "Storage", Tier = 2, Size = { 3, 7, 2.5 }, HP = 300, Cost = { Metal = 5, Screws = 3 }, Slots = 16, Unlock = 4, Color = "607d8b", Material = "Metal" },
	{ Id = "Vault", Name = "Storage Vault", Category = "Furniture", Kind = "Storage", Tier = 3, Size = { 5, 5, 4 }, HP = 800, Cost = { SteelPlate = 3, Metal = 4, Electronics = 1 }, Slots = 24, Unlock = 10, Color = "37474f", Material = "Metal" },
	{ Id = "Bed", Name = "Camp Bed", Category = "Furniture", Kind = "Bed", Tier = 0, Size = { 4, 2, 8 }, HP = 80, Cost = { Wood = 3, Cloth = 3 }, Unlock = 1, Color = "5c7a99", Material = "Fabric" },

	--============================ POWER ============================--
	{ Id = "Generator", Name = "Generator", Category = "Power", Kind = "Generator", Tier = 2, Size = { 5, 4, 4 }, HP = 400, Cost = { Metal = 6, Electronics = 3, Screws = 4 }, Unlock = 2, Color = "f9a825", Material = "Metal", Capacity = 8 },
	{ Id = "Lamp", Name = "Work Lamp", Category = "Power", Kind = "Light", Tier = 0, Size = { 1.5, 6, 1.5 }, HP = 60, Cost = { Metal = 1, Glass = 1, Electronics = 1 }, Power = 1, Unlock = 1, Color = "424242", Material = "Metal" },
	{ Id = "Camera", Name = "Security Camera", Category = "Power", Kind = "Camera", Tier = 0, Size = { 1.5, 1.5, 2.5 }, HP = 60, Cost = { Electronics = 2, CircuitBoard = 1 }, Power = 1, Unlock = 5, Color = "eceff1", Material = "SmoothPlastic", Range = 70 },

	--============================ DEFENSE ============================--
	{ Id = "BearTrap", Name = "Snare Trap", Category = "Defense", Kind = "Trap", Tier = 1, Size = { 4, 1, 4 }, HP = 100, Cost = { Metal = 2, DuctTape = 2 }, Unlock = 2, Color = "6d6d6d", Material = "Metal", Stun = 2.5, ResolveDamage = 20, Charges = 3 },
	{ Id = "ShockTrap", Name = "Shock Plate", Category = "Defense", Kind = "Trap", Tier = 2, Size = { 6, 0.6, 6 }, HP = 220, Cost = { Metal = 3, Electronics = 2, CircuitBoard = 1 }, Power = 2, Unlock = 7, Color = "263238", Material = "Metal", Stun = 3.5, ResolveDamage = 45, Cooldown = 12, Glow = "40c4ff" },
	{ Id = "Turret", Name = "Sentry Turret", Category = "Defense", Kind = "Turret", Tier = 3, Size = { 3, 4, 3 }, HP = 500, Cost = { SteelPlate = 2, CircuitBoard = 2, Electronics = 3, Screws = 4 }, Power = 3, Unlock = 9, Color = "37474f", Material = "Metal", Range = 55, ResolveDamage = 6, FireRate = 0.4 },

	--============================ DECOR (cosmetic) ============================--
	{ Id = "DecoNeon", Name = "Neon 'OPEN' Sign", Category = "Decor", Kind = "Decoration", Tier = 0, Size = { 6, 2, 0.5 }, HP = 40, Cost = { Glass = 1 }, Unlock = 1, Color = "ff2e7e", Material = "Neon", Cosmetic = "DecoNeon" },
	{ Id = "DecoPlant", Name = "Potted Palm", Category = "Decor", Kind = "Decoration", Tier = 0, Size = { 2, 6, 2 }, HP = 40, Cost = { Wood = 1 }, Unlock = 1, Color = "43a047", Material = "Grass", Cosmetic = "DecoPlant" },
	{ Id = "DecoFlag", Name = "Survivor Flag", Category = "Decor", Kind = "Decoration", Tier = 0, Size = { 3, 9, 0.4 }, HP = 40, Cost = { Cloth = 2 }, Unlock = 1, Color = "ffc61a", Material = "Fabric", Cosmetic = "DecoFlag" },
	{ Id = "DecoGnome", Name = "Garden Gnome", Category = "Decor", Kind = "Decoration", Tier = 0, Size = { 1.5, 3, 1.5 }, HP = 40, Cost = { Concrete = 1 }, Unlock = 1, Color = "e53935", Material = "SmoothPlastic", Cosmetic = "DecoGnome" },
}

Buildables.List = LIST
Buildables.ById = {}
for i, b in LIST do
	b.Order = i
	Buildables.ById[b.Id] = b
end

function Buildables.Get(id: string)
	return Buildables.ById[id]
end

-- cost to upgrade `fromId` to its next tier
function Buildables.UpgradeCost(fromId: string, fraction: number)
	local from = Buildables.ById[fromId]
	local to = from and from.Upgrade and Buildables.ById[from.Upgrade]
	if not to then
		return nil
	end
	local cost = {}
	for item, n in to.Cost do
		cost[item] = math.max(1, math.ceil(n * fraction))
	end
	return cost, to
end

function Buildables.ScaledCost(id: string, fraction: number)
	local b = Buildables.ById[id]
	if not b then
		return {}
	end
	local cost = {}
	for item, n in b.Cost do
		cost[item] = math.max(1, math.ceil(n * fraction))
	end
	return cost
end

-- walls, doors etc. sit on grid lines (so they line up with 8x8 floor tiles)
function Buildables.SnapsToEdge(b): boolean
	return b.Kind == "Wall" or b.Kind == "Door" or b.Kind == "Window" or b.Kind == "Barricade"
end

--[[
	Snap(def, surfacePosition, rotationDegrees, grid) -> CFrame of the structure's centre.
	Shared by the client preview and the server so both agree exactly.
	Everything is centred on multiples of the grid (4): 8 stud floor tiles then have their edges
	on grid lines, and 8 stud walls placed on those lines join up edge to edge.
]]
function Buildables.Snap(def, pos, rot: number, grid: number)
	local g = grid or 4
	local r = (math.floor((rot or 0) / 90 + 0.5) % 4) * 90
	local x = math.floor(pos.X / g + 0.5) * g
	local z = math.floor(pos.Z / g + 0.5) * g
	local y = math.floor((pos.Y + def.Size[2] / 2) * 10 + 0.5) / 10
	return CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(r), 0)
end

return Buildables
