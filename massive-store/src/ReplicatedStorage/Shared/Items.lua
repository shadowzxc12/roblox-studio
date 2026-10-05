--[[
	Items: the catalogue of everything that can be found in MASSIVE STORE.

	Fields
	  Id, Name, Category, Rarity, Stack, Desc
	  Shape / Size / Color / Accent  -> procedural 3D model + 2D icon (no uploaded assets needed)
	  Use = { Hunger, Energy, Stamina, Heal, HealOver, Buff = { Speed, Time } }  consumables
	  Tool = "Flashlight" | "Hammer" | ...                                         usable tools / specials
	  Charge (battery %) / Fuel (generator %)
	  Weight (optional) overrides how common it is in loot rolls
]]

local Rarity = require(script.Parent.Rarity)

local Items = {}

Items.Categories = { "Food", "Material", "Tool", "Battery", "Medical", "Fuel", "Special" }
Items.CategoryInfo = {
	Food = { Name = "FOOD", Color = "ff9f43" },
	Material = { Name = "MATERIALS", Color = "b0a48c" },
	Tool = { Name = "TOOLS", Color = "5ab4ff" },
	Battery = { Name = "BATTERIES", Color = "ffe14d" },
	Medical = { Name = "MEDICAL", Color = "ff5a6e" },
	Fuel = { Name = "FUEL", Color = "ff7b2e" },
	Special = { Name = "SPECIAL", Color = "c084ff" },
}

local LIST = {
	--============================ FOOD & DRINK ============================--
	{ Id = "Apple", Name = "Apple", Category = "Food", Rarity = "Common", Stack = 10, Shape = "Round", Size = { 0.8, 0.8, 0.8 }, Color = "d63a2f", Accent = "4caf50", Use = { Hunger = 12 }, Desc = "Crisp enough. Restores a little hunger." },
	{ Id = "Banana", Name = "Banana", Category = "Food", Rarity = "Common", Stack = 10, Shape = "Bag", Size = { 1.2, 0.4, 0.4 }, Color = "ffd93b", Accent = "6b4f1d", Use = { Hunger = 10, Stamina = 15 }, Desc = "Quick snack. Restores some stamina too." },
	{ Id = "Candy", Name = "Candy Bar", Category = "Food", Rarity = "Common", Stack = 12, Shape = "Box", Size = { 0.9, 0.2, 0.35 }, Color = "8e3fd1", Accent = "ffd23f", Use = { Hunger = 8, Energy = 6 }, Desc = "Sugar rush. A little energy." },
	{ Id = "Bread", Name = "Bread Loaf", Category = "Food", Rarity = "Common", Stack = 6, Shape = "Box", Size = { 1.4, 0.7, 0.7 }, Color = "d9a35b", Accent = "fff2d0", Use = { Hunger = 18 }, Desc = "Still soft. Somehow." },
	{ Id = "Chips", Name = "Chips", Category = "Food", Rarity = "Common", Stack = 8, Shape = "Bag", Size = { 1, 1.2, 0.4 }, Color = "ff4b2b", Accent = "ffd23f", Use = { Hunger = 10 }, Desc = "Loud to open. Very loud." },
	{ Id = "Water", Name = "Water Bottle", Category = "Food", Rarity = "Common", Stack = 8, Shape = "Bottle", Size = { 0.45, 1.3, 0.45 }, Color = "a7dbff", Accent = "1e88e5", Use = { Hunger = 5, Energy = 5, Stamina = 40 }, Desc = "Refills stamina." },
	{ Id = "Soda", Name = "Fizz Cola", Category = "Food", Rarity = "Common", Stack = 8, Shape = "Can", Size = { 0.45, 0.8, 0.45 }, Color = "c62828", Accent = "ffffff", Use = { Hunger = 6, Energy = 12 }, Desc = "Warm cola. Some energy." },
	{ Id = "Cereal", Name = "Cereal Box", Category = "Food", Rarity = "Uncommon", Stack = 5, Shape = "Box", Size = { 1, 1.4, 0.4 }, Color = "ffb300", Accent = "e53935", Use = { Hunger = 25 }, Desc = "Crunchy. Fills you up." },
	{ Id = "CannedBeans", Name = "Canned Beans", Category = "Food", Rarity = "Uncommon", Stack = 6, Shape = "Can", Size = { 0.6, 0.8, 0.6 }, Color = "9e9e9e", Accent = "8d4b2a", Use = { Hunger = 30 }, Desc = "Lasts forever. Fills you up." },
	{ Id = "Soup", Name = "Soup Can", Category = "Food", Rarity = "Uncommon", Stack = 6, Shape = "Can", Size = { 0.6, 0.8, 0.6 }, Color = "e53935", Accent = "ffffff", Use = { Hunger = 26, Heal = 8 }, Desc = "Warm inside. Heals a little." },
	{ Id = "Sandwich", Name = "Sandwich", Category = "Food", Rarity = "Uncommon", Stack = 5, Shape = "Slice", Size = { 1, 0.5, 1 }, Color = "e0b06c", Accent = "6abf4b", Use = { Hunger = 28 }, Desc = "From the deli. Probably fine." },
	{ Id = "Coffee", Name = "Cold Coffee", Category = "Food", Rarity = "Uncommon", Stack = 6, Shape = "Can", Size = { 0.45, 0.9, 0.45 }, Color = "4e342e", Accent = "d7b899", Use = { Hunger = 4, Energy = 35 }, Desc = "Restores a lot of energy." },
	{ Id = "Chocolate", Name = "Chocolate", Category = "Food", Rarity = "Uncommon", Stack = 10, Shape = "Box", Size = { 1, 0.15, 0.5 }, Color = "5d3a1a", Accent = "c0a080", Use = { Hunger = 14, Energy = 10 }, Desc = "Comfort food." },
	{ Id = "EnergyDrink", Name = "VOLT Energy", Category = "Food", Rarity = "Uncommon", Stack = 6, Shape = "Can", Size = { 0.45, 1, 0.45 }, Color = "2bff88", Accent = "101010", Use = { Energy = 45, Stamina = 100, Buff = { Speed = 4, Time = 20 } }, Desc = "Full stamina and +speed for 20 seconds." },
	{ Id = "Pizza", Name = "Frozen Pizza", Category = "Food", Rarity = "Rare", Stack = 4, Shape = "Flat", Size = { 1.6, 0.25, 1.6 }, Color = "ffcc80", Accent = "d84315", Use = { Hunger = 45 }, Desc = "Thawed. Big meal." },
	{ Id = "Burger", Name = "Burger", Category = "Food", Rarity = "Rare", Stack = 4, Shape = "Round", Size = { 1, 0.7, 1 }, Color = "c58a3e", Accent = "6d3b1f", Use = { Hunger = 42, Heal = 10 }, Desc = "From the food court grill. Big meal." },
	{ Id = "FrozenMeal", Name = "TV Dinner", Category = "Food", Rarity = "Rare", Stack = 4, Shape = "Flat", Size = { 1.3, 0.3, 1 }, Color = "1565c0", Accent = "ffffff", Use = { Hunger = 50, Energy = 10 }, Desc = "Three compartments of mystery." },
	{ Id = "Rotisserie", Name = "Rotisserie Chicken", Category = "Food", Rarity = "Epic", Stack = 2, Shape = "Round", Size = { 1.4, 1, 1.1 }, Color = "c67c2c", Accent = "ffe0a0", Use = { Hunger = 75, Heal = 25 }, Desc = "A feast. Restores hunger and health." },
	{ Id = "GoldenCake", Name = "Golden Anniversary Cake", Category = "Food", Rarity = "Legendary", Stack = 1, Shape = "Round", Size = { 1.6, 1, 1.6 }, Color = "ffd54f", Accent = "ffffff", Use = { Hunger = 100, Energy = 100, Heal = 100, Stamina = 100 }, Desc = "50 YEARS OF MASSIVE STORE. Restores everything." },

	--============================ MATERIALS ============================--
	{ Id = "Wood", Name = "Wood Planks", Category = "Material", Rarity = "Common", Stack = 30, Shape = "Plank", Size = { 2.6, 0.3, 0.8 }, Color = "b7864b", Accent = "8a5f30", Weight = 14, Desc = "Basic building material." },
	{ Id = "Screws", Name = "Screws", Category = "Material", Rarity = "Common", Stack = 40, Shape = "Box", Size = { 0.6, 0.4, 0.4 }, Color = "8d9aa6", Accent = "e0e0e0", Weight = 11, Desc = "Used in metal builds." },
	{ Id = "DuctTape", Name = "Duct Tape", Category = "Material", Rarity = "Common", Stack = 20, Shape = "Can", Size = { 0.7, 0.3, 0.7 }, Color = "9ea7ad", Accent = "5f6a70", Weight = 9, Desc = "Fixes everything. Used for repairs and traps." },
	{ Id = "Cloth", Name = "Cloth", Category = "Material", Rarity = "Common", Stack = 20, Shape = "Bag", Size = { 1.1, 0.4, 0.8 }, Color = "6d8fb3", Accent = "e8e8e8", Weight = 8, Desc = "Beds, bandages and decorations." },
	{ Id = "Metal", Name = "Scrap Metal", Category = "Material", Rarity = "Uncommon", Stack = 30, Shape = "Sheet", Size = { 1.8, 0.15, 1.3 }, Color = "8a9199", Accent = "5c636b", Weight = 8, Desc = "Stronger walls and doors." },
	{ Id = "Glass", Name = "Glass Panel", Category = "Material", Rarity = "Uncommon", Stack = 10, Shape = "Sheet", Size = { 1.6, 0.1, 1.2 }, Color = "bfe9ff", Accent = "ffffff", Desc = "For windows and lights." },
	{ Id = "Concrete", Name = "Concrete Mix", Category = "Material", Rarity = "Uncommon", Stack = 15, Shape = "Bag", Size = { 1.3, 0.5, 0.9 }, Color = "b8b4aa", Accent = "6e6a60", Desc = "Reinforced structures." },
	{ Id = "Electronics", Name = "Electrical Parts", Category = "Material", Rarity = "Uncommon", Stack = 20, Shape = "Box", Size = { 0.8, 0.4, 0.6 }, Color = "2e7d32", Accent = "ffd54f", Desc = "Wires, switches, fuses. Powered builds." },
	{ Id = "SteelPlate", Name = "Steel Plate", Category = "Material", Rarity = "Rare", Stack = 15, Shape = "Sheet", Size = { 1.8, 0.2, 1.3 }, Color = "c7ced6", Accent = "7d858d", Desc = "Reinforced and advanced structures." },
	{ Id = "CircuitBoard", Name = "Circuit Board", Category = "Material", Rarity = "Rare", Stack = 10, Shape = "Sheet", Size = { 1, 0.1, 0.7 }, Color = "1b5e20", Accent = "ffca28", Desc = "Turrets, cameras and advanced builds." },
	{ Id = "Alloy", Name = "Titanium Alloy", Category = "Material", Rarity = "Epic", Stack = 10, Shape = "Brick", Size = { 1.2, 0.4, 0.6 }, Color = "9fb3c8", Accent = "e3f2fd", Desc = "Advanced structures. Extremely tough." },

	--============================ TOOLS ============================--
	{ Id = "Flashlight", Name = "Flashlight", Category = "Tool", Rarity = "Common", Stack = 1, Shape = "Tool", Size = { 0.35, 0.35, 1.3 }, Color = "263238", Accent = "ffe082", Tool = "Flashlight", Weight = 4, Desc = "[F] toggles light. Uses batteries. The Locust sees lights." },
	{ Id = "Hammer", Name = "Builder's Hammer", Category = "Tool", Rarity = "Common", Stack = 1, Shape = "Tool", Size = { 0.4, 1.4, 0.4 }, Color = "8d6e63", Accent = "90a4ae", Tool = "Hammer", Weight = 3, Desc = "[B] build menu. Click structures to repair or upgrade." },
	{ Id = "Crowbar", Name = "Crowbar", Category = "Tool", Rarity = "Uncommon", Stack = 1, Shape = "Tool", Size = { 0.25, 2, 0.25 }, Color = "c62828", Accent = "424242", Tool = "Crowbar", Desc = "Pries open locked rooms and hidden panels. Can poke the Locust." },
	{ Id = "Flare", Name = "Road Flare", Category = "Tool", Rarity = "Uncommon", Stack = 5, Shape = "Bottle", Size = { 0.25, 1, 0.25 }, Color = "ff3d00", Accent = "ffffff", Tool = "Flare", Desc = "Throw it: bright and loud. The Locust goes to check it." },
	{ Id = "NoiseMaker", Name = "Alarm Clock", Category = "Tool", Rarity = "Rare", Stack = 3, Shape = "Box", Size = { 0.7, 0.6, 0.4 }, Color = "f44336", Accent = "ffffff", Tool = "NoiseMaker", Desc = "Place it and run. Rings loudly after 3 seconds." },
	{ Id = "Keycard", Name = "Security Keycard", Category = "Tool", Rarity = "Rare", Stack = 3, Shape = "Card", Size = { 0.6, 0.05, 0.4 }, Color = "1e88e5", Accent = "ffffff", Tool = "Keycard", Desc = "Opens security doors and the basement shutters." },
	{ Id = "StunBaton", Name = "Stun Baton", Category = "Tool", Rarity = "Epic", Stack = 1, Shape = "Tool", Size = { 0.3, 1.6, 0.3 }, Color = "212121", Accent = "40c4ff", Tool = "StunBaton", Desc = "Click near the Locust to stun it. Uses 30% battery." },

	--============================ BATTERIES ============================--
	{ Id = "BatteryAA", Name = "AA Batteries", Category = "Battery", Rarity = "Common", Stack = 12, Shape = "Cell", Size = { 0.25, 0.6, 0.25 }, Color = "ffd600", Accent = "212121", Charge = 30, Weight = 12, Desc = "[R] reloads your flashlight (+30%)." },
	{ Id = "BatteryPack", Name = "Battery Pack", Category = "Battery", Rarity = "Uncommon", Stack = 6, Shape = "Box", Size = { 0.8, 0.5, 0.5 }, Color = "37474f", Accent = "ffd600", Charge = 65, Desc = "Reloads a lot of flashlight charge (+65%)." },
	{ Id = "PowerCell", Name = "Power Cell", Category = "Battery", Rarity = "Rare", Stack = 4, Shape = "Cell", Size = { 0.5, 0.9, 0.5 }, Color = "00e5ff", Accent = "263238", Charge = 100, Fuel = 30, Desc = "Full flashlight charge, or 30% generator fuel." },

	--============================ MEDICAL ============================--
	{ Id = "Bandage", Name = "Bandage", Category = "Medical", Rarity = "Common", Stack = 8, Shape = "Can", Size = { 0.5, 0.4, 0.5 }, Color = "f5f5f5", Accent = "e53935", Use = { Heal = 20, HealOver = 4 }, Weight = 9, Desc = "Heals 20 over 4 seconds." },
	{ Id = "Painkillers", Name = "Painkillers", Category = "Medical", Rarity = "Uncommon", Stack = 6, Shape = "Bottle", Size = { 0.35, 0.6, 0.35 }, Color = "ff7043", Accent = "ffffff", Use = { Heal = 35, HealOver = 6 }, Desc = "Heals 35 over 6 seconds." },
	{ Id = "Medkit", Name = "Medkit", Category = "Medical", Rarity = "Rare", Stack = 3, Shape = "Kit", Size = { 1.1, 0.7, 0.5 }, Color = "f5f5f5", Accent = "e53935", Use = { Heal = 70, HealOver = 3 }, Desc = "Heals 70. Revives faster. Needed for revives in Hardcore." },
	{ Id = "Adrenaline", Name = "Adrenaline Shot", Category = "Medical", Rarity = "Epic", Stack = 2, Shape = "Bottle", Size = { 0.2, 0.8, 0.2 }, Color = "ffeb3b", Accent = "d50000", Use = { Heal = 40, Stamina = 100, Buff = { Speed = 6, Time = 12 } }, Desc = "Instantly revives a teammate (hold on them) or boosts you." },

	--============================ FUEL ============================--
	{ Id = "FuelCan", Name = "Fuel Can", Category = "Fuel", Rarity = "Uncommon", Stack = 4, Shape = "Jug", Size = { 0.9, 1.1, 0.5 }, Color = "d32f2f", Accent = "212121", Fuel = 40, Weight = 6, Desc = "+40% generator fuel." },
	{ Id = "GasCanister", Name = "Gas Canister", Category = "Fuel", Rarity = "Rare", Stack = 2, Shape = "Bottle", Size = { 0.7, 1.4, 0.7 }, Color = "1565c0", Accent = "eeeeee", Fuel = 100, Desc = "Fills a generator completely." },

	--============================ SPECIAL ============================--
	{ Id = "StoreMap", Name = "Store Directory", Category = "Special", Rarity = "Rare", Stack = 1, Shape = "Card", Size = { 1.2, 0.05, 0.9 }, Color = "ffc61a", Accent = "101010", Tool = "StoreMap", Desc = "Reveals the whole store on your map [M]." },
	{ Id = "Repellent", Name = "Locust Repellent", Category = "Special", Rarity = "Epic", Stack = 2, Shape = "Bottle", Size = { 0.4, 1.1, 0.4 }, Color = "76ff03", Accent = "1b5e20", Tool = "Repellent", Desc = "Sprays a cloud the Locust won't enter for 60 seconds." },
	{ Id = "SupplyBeacon", Name = "Supply Beacon", Category = "Special", Rarity = "Epic", Stack = 1, Shape = "Box", Size = { 0.6, 0.9, 0.6 }, Color = "ff6d00", Accent = "ffffff", Tool = "SupplyBeacon", Desc = "Place it: a supply crate drops here at dawn." },
	{ Id = "NightVision", Name = "Night Vision Goggles", Category = "Special", Rarity = "Legendary", Stack = 1, Shape = "Kit", Size = { 0.9, 0.4, 0.5 }, Color = "33691e", Accent = "76ff03", Tool = "NightVision", Desc = "[N] see in the dark without a light. Uses flashlight battery." },
	{ Id = "LuckyCoin", Name = "Founder's Coin", Category = "Special", Rarity = "Legendary", Stack = 1, Shape = "Round", Size = { 0.6, 0.12, 0.6 }, Color = "ffca28", Accent = "fff59d", Tool = "LuckyCoin", Desc = "While you carry it, loot you open is rarer." },
}

Items.List = LIST
Items.ById = {}
for i, item in LIST do
	item.Order = i
	item.Weight = item.Weight or Rarity.Info[item.Rarity].Weight
	Items.ById[item.Id] = item
end

function Items.Get(id: string)
	return Items.ById[id]
end

function Items.IsValid(id: any): boolean
	return type(id) == "string" and Items.ById[id] ~= nil
end

function Items.StackOf(id: string): number
	local item = Items.ById[id]
	return if item then item.Stack else 1
end

--[[
	Roll one loot item.
	zoneLoot = { Categories = { Food = 1, ... }, Items = { Water = 3, ... } } (see Zones)
	luck grows with nights and room bonuses; rng is a Util.RNG
]]
function Items.Roll(zoneLoot, luck: number, rng)
	local weights = {}
	local cats = zoneLoot and zoneLoot.Categories or {}
	local boosts = zoneLoot and zoneLoot.Items or {}
	for _, item in LIST do
		local w = item.Weight * (cats[item.Category] or 0.04) * (boosts[item.Id] or 1) * Rarity.Boost(item.Rarity, luck)
		if w > 0 then
			weights[item.Id] = w
		end
	end
	local id = rng:Weighted(weights)
	local item = Items.ById[id]
	local qty = 1
	if item and item.Category == "Material" and item.Stack >= 15 then
		qty = rng:Int(1, if item.Rarity == "Common" then 4 else 2)
	elseif item and item.Category == "Battery" and item.Rarity == "Common" then
		qty = rng:Int(1, 2)
	end
	return id, qty
end

return Items
