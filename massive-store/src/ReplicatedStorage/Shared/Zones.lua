--[[
	Zones: every department of MASSIVE STORE.
	  Name      shown on signs and in the HUD
	  Fill      how StoreLayout furnishes the cells (see StoreLayout.Fill*)
	  Floor     floor colour, Accent sign colour, Light ceiling-light colour
	  Loot      { Categories = weight multipliers, Items = per-item boosts }
	  Products  colours of the decorative products on shelves
	  Size      target number of cells per instance, Count how many instances
	  Level     0 = main floor, -1 = underground
]]

local Zones = {}

Zones.Types = {
	Entrance = {
		Name = "ENTRANCE", Fill = "Entrance", Floor = "cfc9bb", Accent = "ffc61a", Light = "fff4dc", Level = 0,
		Loot = { Categories = { Food = 1, Tool = 1.2, Battery = 1, Medical = 0.6 }, Items = { Flashlight = 2, Hammer = 2 } },
		Products = { "ffc61a", "e53935", "1e88e5" },
	},
	Grocery = {
		Name = "GROCERY", Fill = "Aisles", Floor = "e4dfd1", Accent = "43a047", Light = "fffaf0", Level = 0, Size = 16, Count = 2,
		Loot = { Categories = { Food = 1.6, Material = 0.15, Battery = 0.2 }, Items = { CannedBeans = 1.5, Cereal = 1.6, Chips = 1.4 } },
		Products = { "e53935", "fdd835", "43a047", "fb8c00", "8e24aa", "1e88e5", "f5f5f5", "6d4c41" },
	},
	Drinks = {
		Name = "DRINKS", Fill = "Coolers", Floor = "dfe6ea", Accent = "1e88e5", Light = "eef8ff", Level = 0, Size = 10, Count = 1,
		Loot = { Categories = { Food = 1.2 }, Items = { Water = 5, Soda = 5, EnergyDrink = 4, Coffee = 3, Apple = 0.2, Bread = 0.2 } },
		Products = { "c62828", "1565c0", "2bff88", "ffeb3b", "4e342e", "a7dbff" },
	},
	Frozen = {
		Name = "FROZEN FOODS", Fill = "Freezers", Floor = "d7e3ea", Accent = "4fc3f7", Light = "e3f6ff", Level = 0, Size = 10, Count = 1,
		Loot = { Categories = { Food = 1.4 }, Items = { Pizza = 5, FrozenMeal = 5, Water = 1.5 } },
		Products = { "e1f5fe", "1565c0", "ff7043", "ffcc80", "b3e5fc" },
	},
	Bakery = {
		Name = "BAKERY", Fill = "Bakery", Floor = "e8d9c0", Accent = "d9a35b", Light = "fff0d6", Level = 0, Size = 5, Count = 1,
		Loot = { Categories = { Food = 1.5 }, Items = { Bread = 6, Sandwich = 2.5, GoldenCake = 3, Chocolate = 2 } },
		Products = { "d9a35b", "f6d7a7", "8d5524", "fff2d0" },
	},
	Restaurant = {
		Name = "FOOD COURT", Fill = "Restaurant", Floor = "c9b79c", Accent = "ff7043", Light = "ffe9cc", Level = 0, Size = 7, Count = 1,
		Loot = { Categories = { Food = 1.5, Fuel = 0.5 }, Items = { Burger = 5, Pizza = 2, Soda = 2, Rotisserie = 2.5 } },
		Products = { "ff7043", "ffca28", "8d6e63" },
	},
	Electronics = {
		Name = "ELECTRONICS", Fill = "Electronics", Floor = "c4c8cf", Accent = "29b6f6", Light = "eaf6ff", Level = 0, Size = 12, Count = 1,
		Loot = { Categories = { Battery = 2, Material = 1, Tool = 0.8, Special = 0.6 }, Items = { Electronics = 4, CircuitBoard = 3, BatteryPack = 2, PowerCell = 2, Flashlight = 2, NightVision = 3 } },
		Products = { "212121", "37474f", "29b6f6", "eceff1", "263238" },
	},
	Furniture = {
		Name = "HOME & FURNITURE", Fill = "Furniture", Floor = "b99c7a", Accent = "a1887f", Light = "fff1df", Level = 0, Size = 16, Count = 1,
		Loot = { Categories = { Material = 1.6, Tool = 0.6 }, Items = { Wood = 3, Cloth = 3, Screws = 1.5, Glass = 1.5 } },
		Products = { "8d6e63", "bcaaa4", "5d4037", "efebe9", "607d8b" },
	},
	Garden = {
		Name = "GARDEN CENTER", Fill = "Garden", Floor = "8f9a6b", Accent = "7cb342", Light = "f4ffe8", Level = 0, Size = 12, Count = 1,
		Loot = { Categories = { Material = 1.3, Tool = 1, Fuel = 1.5, Food = 0.4 }, Items = { Wood = 2.5, Concrete = 2.5, FuelCan = 3, Crowbar = 2, Apple = 3 } },
		Products = { "558b2f", "7cb342", "33691e", "795548", "c0ca33" },
	},
	Pharmacy = {
		Name = "PHARMACY", Fill = "Pharmacy", Floor = "e9eef0", Accent = "e53935", Light = "f6fbff", Level = 0, Size = 5, Count = 1,
		Loot = { Categories = { Medical = 3.5, Food = 0.3, Special = 0.4 }, Items = { Medkit = 2, Adrenaline = 2, Repellent = 2 } },
		Products = { "ffffff", "e53935", "42a5f5", "66bb6a", "ffca28" },
	},
	Toys = {
		Name = "TOYS", Fill = "Toys", Floor = "d6d0e6", Accent = "ab47bc", Light = "fdf0ff", Level = 0, Size = 10, Count = 1,
		Loot = { Categories = { Battery = 1.5, Tool = 0.7, Food = 0.6, Special = 0.4 }, Items = { BatteryAA = 3, NoiseMaker = 4, Candy = 3, LuckyCoin = 2 } },
		Products = { "e53935", "fdd835", "1e88e5", "43a047", "ab47bc", "ff7043", "ec407a" },
	},
	Clothing = {
		Name = "CLOTHING", Fill = "Clothing", Floor = "d3c7c0", Accent = "ec407a", Light = "fff4f6", Level = 0, Size = 12, Count = 1,
		Loot = { Categories = { Material = 1, Medical = 0.6, Food = 0.3 }, Items = { Cloth = 6, Bandage = 2 } },
		Products = { "ec407a", "5c6bc0", "26a69a", "ffa726", "8d6e63", "eeeeee", "212121" },
	},
	Bathrooms = {
		Name = "RESTROOMS", Fill = "Bathrooms", Floor = "e0e6e8", Accent = "90a4ae", Light = "f0fbff", Level = 0, Size = 2, Count = 2,
		Loot = { Categories = { Medical = 1.5, Material = 0.5 }, Items = { Bandage = 3, DuctTape = 2 } },
		Products = { "ffffff", "b0bec5" },
	},
	Employee = {
		Name = "STAFF ONLY", Fill = "Employee", Floor = "a7a29a", Accent = "ffb300", Light = "fff6e0", Level = 0, Size = 4, Count = 2,
		Loot = { Categories = { Food = 0.8, Tool = 1.5, Battery = 1, Medical = 1, Special = 0.5 }, Items = { Coffee = 4, Keycard = 2, Crowbar = 2, Flashlight = 2, StoreMap = 3 } },
		Products = { "607d8b", "ffb300", "8d6e63" },
	},
	Storage = {
		Name = "STOCK ROOMS", Fill = "StorageRooms", Floor = "9e9890", Accent = "8d6e63", Light = "fff4e0", Level = 0, Size = 6, Count = 2,
		Loot = { Categories = { Material = 1.4, Food = 0.8, Fuel = 0.6, Battery = 0.6, Tool = 0.5 }, Items = {} },
		Products = { "a1887f", "8d6e63", "d7ccc8" },
	},
	Security = {
		Name = "SECURITY OFFICE", Fill = "Security", Floor = "6f747c", Accent = "1e88e5", Light = "e8f1ff", Level = 0, Size = 2, Count = 1,
		Loot = { Categories = { Tool = 2, Battery = 1.5, Special = 1, Medical = 0.8 }, Items = { Keycard = 6, StunBaton = 3, Flare = 2, StoreMap = 3 } },
		Products = { "263238", "1e88e5" },
	},
	Warehouse = {
		Name = "WAREHOUSE", Fill = "Warehouse", Floor = "9a958c", Accent = "ffb300", Light = "fff1d0", Level = 0, Size = 18, Count = 1,
		Loot = { Categories = { Material = 2, Fuel = 1, Food = 0.6, Tool = 0.5 }, Items = { Metal = 2, SteelPlate = 1.5, Concrete = 2, Screws = 2 } },
		Products = { "a1887f", "d7ccc8", "8d6e63", "1565c0", "ffb300" },
	},
	LoadingDocks = {
		Name = "LOADING DOCKS", Fill = "Docks", Floor = "8c8780", Accent = "ff6f00", Light = "fff0d0", Level = 0, Size = 6, Count = 1,
		Loot = { Categories = { Material = 1.5, Fuel = 2, Tool = 0.6 }, Items = { FuelCan = 2, GasCanister = 2, Metal = 1.5 } },
		Products = { "a1887f", "ff6f00" },
	},
	Maintenance = {
		Name = "MAINTENANCE", Fill = "Maintenance", Floor = "7d7a74", Accent = "ff8f00", Light = "fff3cf", Level = 0, Size = 2, Count = 2,
		Loot = { Categories = { Material = 1.2, Fuel = 2, Battery = 1, Tool = 0.8 }, Items = { Electronics = 3, FuelCan = 2, DuctTape = 2 } },
		Products = { "616161", "ff8f00" },
	},
	Escalators = {
		Name = "ESCALATORS", Fill = "Escalators", Floor = "cfcac0", Accent = "ffc61a", Light = "fff8e6", Level = 0, Size = 3, Count = 1,
		Loot = { Categories = { Food = 0.8, Tool = 0.6, Medical = 0.6 }, Items = {} },
		Products = { "ffc61a" },
	},
	Sealed = {
		Name = "SEALED WING", Fill = "Sealed", Floor = "6b655c", Accent = "ff3b3b", Light = "ffd9c2", Level = 0, Gate = "SealedWing",
		Loot = { Categories = { Food = 1, Material = 1, Tool = 1, Battery = 1, Medical = 1, Fuel = 1, Special = 1.2 }, Items = {} },
		Products = { "5d4037", "3e2723", "795548" },
		LootBonus = 3,
	},
	Stairwell = {
		Name = "STAIRS B1", Fill = "Stairwell", Floor = "a8a39a", Accent = "ffc61a", Light = "fff1d0", Level = 0,
		Loot = { Categories = {}, Items = {} },
		Products = {},
	},
	--============================ UNDERGROUND ============================--
	Parking = {
		Name = "PARKING GARAGE", Fill = "Parking", Floor = "5c5c5c", Accent = "fdd835", Light = "e6f0ff", Level = -1, Size = 26, Count = 1,
		Loot = { Categories = { Fuel = 2.5, Material = 1, Tool = 0.8, Battery = 0.8, Food = 0.4 }, Items = { GasCanister = 2, Crowbar = 1.5, SupplyBeacon = 2 } },
		Products = { "b71c1c", "0d47a1", "eeeeee", "212121", "f9a825", "2e7d32" },
		LootBonus = 1,
	},
	UndergroundStorage = {
		Name = "UNDERGROUND STORAGE", Fill = "Warehouse", Floor = "6e6a63", Accent = "ff8f00", Light = "ffe9c4", Level = -1, Size = 20, Count = 1,
		Loot = { Categories = { Material = 2, Food = 1, Special = 0.8, Battery = 0.8 }, Items = { SteelPlate = 2.5, Alloy = 3, CircuitBoard = 2 } },
		Products = { "8d6e63", "a1887f", "455a64" },
		LootBonus = 1.5,
	},
	Tunnels = {
		Name = "MAINTENANCE TUNNELS", Fill = "Tunnels", Floor = "55524c", Accent = "ff6f00", Light = "ffd8a8", Level = -1, Size = 16, Count = 1,
		Loot = { Categories = { Material = 1.5, Fuel = 1.5, Battery = 1.5, Special = 1, Tool = 1 }, Items = { Electronics = 2, PowerCell = 2, Repellent = 1.5 } },
		Products = { "455a64" },
		LootBonus = 1.5,
	},
	Solid = { Name = "", Fill = "None", Floor = "444444", Accent = "444444", Light = "ffffff", Level = -1, Loot = { Categories = {}, Items = {} }, Products = {} },
}

-- zones that receive a random number of cells by region growing (main floor)
Zones.GrowOrder = {
	"Grocery", "Drinks", "Frozen", "Bakery", "Restaurant", "Electronics", "Furniture", "Garden", "Pharmacy",
	"Toys", "Clothing", "Bathrooms", "Employee", "Storage", "Security", "Maintenance", "Escalators",
}
Zones.BasementOrder = { "Parking", "UndergroundStorage", "Tunnels" }

function Zones.Get(typeName: string)
	return Zones.Types[typeName]
end

return Zones
