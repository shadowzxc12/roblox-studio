-- Pure module tests: inventory, items, buildables, progression, missions, night scaling, nav.
local InventoryCore = Load("InventoryCore")
local Items = Load("Items")
local Buildables = Load("Buildables")
local Progression = Load("Progression")
local Missions = Load("Missions")
local Config = Load("Config")
local Util = Load("Util")
local Nav = Load("Nav")
local StoreLayout = Load("StoreLayout")

-- inventory stacking / moving / transfer
local inv = InventoryCore.new(4)
assert(InventoryCore.Add(inv, "Apple", 15) == 15)
assert(inv.Slots[1].Qty == 10 and inv.Slots[2].Qty == 5, "stacks split at 10")
assert(InventoryCore.Add(inv, "Wood", 100) == 60, "only two slots of wood fit")
assert(InventoryCore.Add(inv, "Nope", 1) == 0, "invalid item rejected")
assert(InventoryCore.Count(inv, "Apple") == 15)
assert(InventoryCore.Remove(inv, "Apple", 7) == 7 and InventoryCore.Count(inv, "Apple") == 8)
local box = InventoryCore.new(2)
assert(InventoryCore.Transfer(inv, 3, box) == 30)
assert(InventoryCore.HasAll(box, { Wood = 30 }) and not InventoryCore.HasAll(box, { Wood = 31 }))
InventoryCore.ConsumeMulti({ inv, box }, { Wood = 40 })
assert(InventoryCore.Count(inv, "Wood") + InventoryCore.Count(box, "Wood") == 20)
local overflow = InventoryCore.Resize(inv, 1)
assert(inv.Size == 1)
local fromBad = InventoryCore.FromData({ Slots = { { Id = "Apple", Qty = 999 }, { Id = "Hack", Qty = 5 }, "x" } }, 3)
assert(fromBad.Slots[1].Qty == 10 and fromBad.Slots[2] == nil, "untrusted data sanitised")
print("inventory ok", #overflow)

-- items roll by zone and get rarer with luck
local rng = Util.RNG(3)
local zone = { Categories = { Food = 1 }, Items = {} }
local lowRare, highRare = 0, 0
for _ = 1, 2000 do
	local id = Items.Roll(zone, 0, rng)
	if Items.Get(id).Rarity ~= "Common" then
		lowRare += 1
	end
	local id2 = Items.Roll(zone, 6, rng)
	if Items.Get(id2).Rarity ~= "Common" then
		highRare += 1
	end
end
assert(highRare > lowRare * 1.3, ("luck makes loot rarer (%d vs %d)"):format(lowRare, highRare))
print("loot rolls ok", lowRare, highRare)

-- every build cost / upgrade references real items
for _, b in Buildables.List do
	for id in b.Cost do
		assert(Items.Get(id), b.Id .. " costs unknown item " .. id)
	end
	if b.Upgrade then
		assert(Buildables.Get(b.Upgrade), b.Id .. " upgrades to nothing")
		assert(Buildables.Get(b.Upgrade).Tier == b.Tier + 1, b.Id .. " upgrade tier")
	end
end
print("buildables ok")

-- night scaling: monotonic, capped, fair at night 1
local prev = Config.LocustStats(1)
assert(prev.ChaseSpeed < Config.Survival.SprintSpeed, "night 1 Locust is slower than a sprinting player")
assert(prev.BreakTier == 0)
for n = 2, 60 do
	local s = Config.LocustStats(n)
	assert(s.ChaseSpeed >= prev.ChaseSpeed and s.Damage >= prev.Damage and s.HearingRange >= prev.HearingRange, "scaling not monotonic at " .. n)
	prev = s
end
assert(Config.LocustStats(3).BreakTier == 1 and Config.LocustStats(10).BreakTier == 2 and Config.LocustStats(20).BreakTier == 4)
assert(Config.BreakMultiplier(Config.LocustStats(1), 1, "Wall") < 0.1, "night 1 can't break walls")
assert(Config.BreakMultiplier(Config.LocustStats(3), 1, "Barricade") == 1, "night 3 breaks barricades")
assert(Config.BreakMultiplier(Config.LocustStats(5), 1, "Wall") == 1, "night 5 breaks wood")
assert(Config.BreakMultiplier(Config.LocustStats(5), 3, "Wall") < 0.1, "night 5 can't break reinforced")
assert(Config.LocustStats(60).ChaseSpeed <= 29 * 1.12 + 0.01, "speed capped")
assert(Config.VariantFor(35).Name == "IRON LOCUST")
print("scaling ok")

-- progression
assert(Progression.Perks(1).Slots == 12 and Progression.Perks(20).Slots == 26)
assert(Progression.Perks(8).Tier == 3 and Progression.Perks(16).Tier == 4)
local lvl = Util.LevelFromXP(0)
assert(lvl == 1)
assert(Util.LevelFromXP(100) == 2)
print("progression ok")

-- missions: 3 a day, deterministic, distinct stats
for day = 19000, 19030 do
	local list = Missions.ForDay(day)
	assert(#list == 3)
	local stats = {}
	for _, id in list do
		assert(not stats[Missions.ById[id].Stat])
		stats[Missions.ById[id].Stat] = true
	end
	assert(table.concat(list) == table.concat(Missions.ForDay(day)))
end
print("missions ok")

-- nav: path across the store, blocked gates respected
local plan = StoreLayout.Generate(77)
local nodes = Nav.CellNodes(plan)
local path = Nav.FindPath(plan, nodes[1], nodes[#nodes])
assert(path and #path > 5, "long path found")
local closed = Nav.FindPath(plan, nodes[1], nodes[#nodes], { CanPass = function(link)
	return link.Gate == nil
end })
-- the last node is in the basement: unreachable with gates closed
local lastCell = plan.Cells[plan.Nav.Nodes[nodes[#nodes]].Cell]
if lastCell.Level == -1 then
	assert(closed == nil, "gates block the basement")
end
print("nav ok")
print("ALL CORE TESTS OK")
