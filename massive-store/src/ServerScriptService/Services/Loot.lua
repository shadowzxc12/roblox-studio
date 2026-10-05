--[[
	Loot: world items. Thousands of possible loot points come from the store layout; each run
	fills a random subset, rolled per department (Zones loot tables) and getting rarer every night
	(Items.Roll luck). Every dawn the store restocks a bit, so exploring deeper always pays.

	Also: dropped items, lost bags (death), supply crates and rare-item events.
	Item spawning and pickup are server-only; clients just trigger the prompt.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Rarity = require(Shared.Rarity)
local Util = require(Shared.Util)
local Zones = require(Shared.Zones)
local Models = require(Shared.Models)
local InventoryCore = require(Shared.InventoryCore)

local State = require(script.Parent.State)
local World = require(script.Parent.World)
local Prompts = require(script.Parent.Prompts)
local Progress = require(script.Parent.Progress)
local Inventory = require(script.Parent.Inventory)
local Noise = require(script.Parent.Noise)

local Loot = {}

local rng = Util.RNG(os.time() % 100000 + 7)
local loots: { [number]: any } = {}
local nextId = 0
local pointUsed: { [number]: number } = {}
local worldCount = 0
local droppedOrder = {}
local exploredZones: { [Player]: { [number]: boolean } } = {}

local function folder()
	return World.Folders.Loot
end

local function rayDown(pos: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder(), World.Folders.Dynamic }
	local hit = Workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -40, 0), params)
	return if hit then hit.Position else pos
end

local function decorate(model: Model, item)
	local handle = model.PrimaryPart :: BasePart
	local rank = Rarity.Rank(item.Rarity)
	if rank >= 3 then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromHex(Rarity.Info[item.Rarity].Color)
		light.Range = 4 + rank * 1.5
		light.Brightness = 0.6 + (rank - 3) * 0.5
		light.Shadows = false
		light.Parent = handle
	end
	if rank >= 4 then
		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(Color3.fromHex(Rarity.Info[item.Rarity].Color))
		pe.LightEmission = 0.8
		pe.Rate = if rank == 5 then 6 else 3
		pe.Lifetime = NumberRange.new(0.8, 1.6)
		pe.Speed = NumberRange.new(0.3, 0.9)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
		pe.Transparency = NumberSequence.new(0.1, 1)
		pe.Parent = handle
		game:GetService("CollectionService"):AddTag(pe, "OptionalEffect")
	end
end

-- create a world item. pos = where its bottom sits
local function spawnItem(itemId: string, qty: number, pos: Vector3, opts)
	local item = Items.Get(itemId)
	if not item then
		return nil
	end
	nextId += 1
	local id = nextId
	local model = Models.Item(itemId)
	model.Name = "Loot_" .. itemId
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.CastShadow = false
		end
	end
	local handle = model.PrimaryPart :: BasePart
	local h = math.min(item.Size[2], math.max(item.Size[1], item.Size[3]))
	if item.Shape == "Round" then
		h = item.Size[1]
	end
	local yaw = rng:Range(0, 360)
	-- long upright things (hammer, crowbar, baton) lie on their side
	local lay = CFrame.new()
	if item.Size[2] > math.max(item.Size[1], item.Size[3]) * 1.8 then
		lay = CFrame.Angles(0, 0, math.pi / 2)
		h = math.max(item.Size[1], item.Size[3])
	end
	model:PivotTo(CFrame.new(pos + Vector3.new(0, h / 2 + 0.02, 0)) * CFrame.Angles(0, math.rad(yaw), 0) * lay)
	decorate(model, item)
	local prompt = Prompts.Make(handle, "Loot", "Pick up", if qty > 1 then ("%s ×%d"):format(item.Name, qty) else item.Name, {
		Distance = Config.Loot.PickupDistance,
		Rarity = item.Rarity,
		Category = item.Category,
		Name = "LootPrompt",
	})
	prompt:SetAttribute("LootId", id)
	prompt:SetAttribute("ItemId", itemId)
	if opts and opts.Point then
		local point = State.Plan.LootPoints[opts.Point]
		if point and point.Bonus >= 2.5 then
			-- inside locked / hidden rooms: no grabbing through the wall
			prompt.RequiresLineOfSight = true
		end
	end
	model:SetAttribute("LootId", id)
	model.Parent = folder()
	loots[id] = {
		Id = id,
		Model = model,
		ItemId = itemId,
		Qty = qty,
		Point = opts and opts.Point,
		Fresh = not (opts and opts.Dropped),
		Prompt = prompt,
	}
	if opts and opts.Point then
		pointUsed[opts.Point] = id
	end
	if not (opts and opts.Dropped) then
		worldCount += 1
	else
		table.insert(droppedOrder, id)
		if #droppedOrder > Config.Loot.MaxDroppedItems then
			Loot.Remove(table.remove(droppedOrder, 1))
		end
	end
	return id
end

function Loot.Remove(id: number?)
	local l = id and loots[id]
	if not l then
		return
	end
	loots[id] = nil
	if l.Point then
		pointUsed[l.Point] = nil
	end
	if l.Fresh then
		worldCount -= 1
	end
	l.Model:Destroy()
end

local function luckFor(bonus: number): number
	return math.max(0, (State.Night - 1) * 0.28) + (bonus or 0)
end

-- fill `count` random free loot points
function Loot.Populate(count: number)
	local plan = State.Plan
	local points = plan.LootPoints
	local mult = State.ModeInfo.LootMult or 1
	count = math.floor(count * mult)
	local placed, tries = 0, 0
	local gatesOpen = State.GatesOpen
	while placed < count and tries < count * 6 and worldCount < Config.Loot.MaxWorldItems do
		tries += 1
		local index = rng:Int(1, #points)
		if not pointUsed[index] then
			local p = points[index]
			local zinfo = Zones.Types[p.Type]
			if zinfo and zinfo.Loot then
				-- sealed areas are richer the later they open; still rolled now
				local id, qty = Items.Roll(zinfo.Loot, luckFor(p.Bonus), rng)
				if id then
					spawnItem(id, qty, Vector3.new(p.X, p.Y, p.Z), { Point = index })
					placed += 1
					if placed % 150 == 0 then
						task.wait()
					end
				end
			end
		end
	end
	return placed
end

function Loot.Restock()
	return Loot.Populate(Config.Loot.RestockPerDay)
end

-- refill the free loot points inside locked / hidden rooms and sealed areas
function Loot.RestockRooms()
	local points = State.Plan.LootPoints
	local placed = 0
	for index, p in points do
		if p.Bonus >= 2.5 and not pointUsed[index] and worldCount < Config.Loot.MaxWorldItems then
			local zinfo = Zones.Types[p.Type]
			if zinfo and zinfo.Loot and rng:Chance(0.7) then
				local id, qty = Items.Roll(zinfo.Loot, luckFor(p.Bonus + 1), rng)
				if id then
					spawnItem(id, qty, Vector3.new(p.X, p.Y, p.Z), { Point = index })
					placed += 1
				end
			end
		end
	end
	return placed
end

function Loot.Drop(pos: Vector3, itemId: string, qty: number)
	local ground = rayDown(pos)
	return spawnItem(itemId, qty, ground, { Dropped = true })
end

-- picked up something (from the world or out of a container)
function Loot.OnPickedUp(player: Player, itemId: string, fresh: boolean)
	local item = Items.Get(itemId)
	if not item then
		return
	end
	if fresh then
		Progress.Track(player, "LootFound", 1)
		if item.Category == "Food" then
			Progress.Track(player, "FoodFound", 1)
		end
		local rank = Rarity.Rank(item.Rarity)
		if rank >= 3 then
			Progress.Track(player, "RareFound", 1)
			local xp = Config.XP.RareFind[item.Rarity]
			if xp then
				Progress.AddXP(player, xp, Rarity.Info[item.Rarity].Name .. " find: " .. item.Name)
			end
			if rank == 5 then
				Progress.AddCredits(player, Config.Credits.LegendaryFind, "Legendary find")
				State.Notify(nil, player.DisplayName .. " found a LEGENDARY " .. item.Name .. "!", "Legendary")
			end
		end
	end
end

-- Founder's Coin: sometimes upgrades what you pick up to the next rarity
local function luckyUpgrade(player: Player, itemId: string): string
	if not player:GetAttribute("HasLuckyCoin") or rng:Next() > 0.25 then
		return itemId
	end
	local item = Items.Get(itemId)
	local rank = Rarity.Rank(item.Rarity)
	if rank >= 5 then
		return itemId
	end
	local options = {}
	for _, other in Items.List do
		if other.Category == item.Category and Rarity.Rank(other.Rarity) == rank + 1 then
			table.insert(options, other.Id)
		end
	end
	if #options == 0 then
		return itemId
	end
	local up = options[rng:Int(1, #options)]
	State.Notify(player, "The Founder's Coin glints... " .. item.Name .. " became " .. Items.Get(up).Name .. "!", "Legendary")
	return up
end

local function onLootPrompt(player: Player, prompt: ProximityPrompt)
	local id = prompt:GetAttribute("LootId")
	local l = loots[id]
	if not l then
		return
	end
	local itemId = l.ItemId
	if l.Fresh then
		itemId = luckyUpgrade(player, itemId)
	end
	local added = Inventory.Give(player, itemId, l.Qty)
	if added <= 0 then
		State.Notify(player, "Your inventory is full! Drop something or use a cart.", "Warn")
		return
	end
	Loot.OnPickedUp(player, itemId, l.Fresh)
	Inventory.PlayAction(player, "Pickup")
	State.Cue("Pickup", l.Model:GetPivot().Position, itemId, player)
	Noise.Emit(l.Model:GetPivot().Position, Config.Noise.Pickup, player, "Pickup")
	if added >= l.Qty then
		Loot.Remove(id)
	else
		l.Qty -= added
		local item = Items.Get(l.ItemId)
		prompt.ObjectText = ("%s ×%d"):format(item.Name, l.Qty)
		State.Notify(player, "Inventory full — took " .. added .. ".", "Warn")
	end
end

--============================ BAGS & CRATES ============================--
local function containerModel(kind: string, pos: Vector3, name: string)
	local model = Instance.new("Model")
	model.Name = kind
	local body = Instance.new("Part")
	body.Anchored = true
	body.CanCollide = kind == "Crate"
	body.CanTouch = false
	body.Name = "Body"
	if kind == "Crate" then
		body.Size = Vector3.new(4, 3, 4)
		body.Color = Color3.fromHex("e65100")
		body.Material = Enum.Material.DiamondPlate
		for _, x in { -1.6, 1.6 } do
			local band = Instance.new("Part")
			band.Anchored = true
			band.CanCollide = false
			band.CanQuery = false
			band.Size = Vector3.new(0.4, 3.1, 4.1)
			band.Color = Color3.fromHex("212121")
			band.Material = Enum.Material.Metal
			band.CFrame = CFrame.new(pos + Vector3.new(x, 1.5, 0))
			band.Parent = model
		end
		local light = Instance.new("PointLight")
		light.Color = Color3.fromHex("ff9100")
		light.Range = 14
		light.Brightness = 1.5
		light.Parent = body
	else
		body.Size = Vector3.new(2.4, 1.2, 1.4)
		body.Color = Color3.fromHex("37474f")
		body.Material = Enum.Material.Fabric
		body.Shape = Enum.PartType.Block
	end
	body.CFrame = CFrame.new(pos + Vector3.new(0, body.Size.Y / 2, 0))
	body.Parent = model
	model.PrimaryPart = body
	model.Parent = World.Folders.Dynamic
	return model, body
end

function Loot.SpawnBag(pos: Vector3, invData, name: string)
	local ground = rayDown(pos)
	local model, body = containerModel("Bag", ground, name)
	local cid
	cid = Inventory.NewContainer("Bag", invData, model, name, {
		AllowStore = false,
		OnChanged = function(c)
			if InventoryCore.IsEmpty(c.Inv) then
				Inventory.RemoveContainer(cid)
				model:Destroy()
			end
		end,
	})
	local prompt = Prompts.Make(body, "OpenContainer", "Search", name, { Distance = 9 })
	prompt:SetAttribute("ContainerId", cid)
	-- bags fade after a few nights
	task.delay(900, function()
		if model.Parent then
			Inventory.RemoveContainer(cid)
			model:Destroy()
		end
	end)
	return model
end

-- a supply crate full of good loot. fall = drop from the ceiling
function Loot.SpawnCrate(pos: Vector3, count: number, bonus: number, title: string?, fall: boolean?)
	local crateInv = InventoryCore.new(12)
	local zone = { Categories = { Food = 1, Material = 1, Tool = 1, Battery = 1, Medical = 1.2, Fuel = 1, Special = 0.6 }, Items = {} }
	for _ = 1, count do
		local id, qty = Items.Roll(zone, luckFor(bonus), rng)
		if id then
			InventoryCore.Add(crateInv, id, qty)
		end
	end
	local ground = rayDown(pos)
	local model, body = containerModel("Crate", ground, title or "Supply Crate")
	if fall then
		local target = model:GetPivot()
		model:PivotTo(target + Vector3.new(0, 18, 0))
		local cfv = Instance.new("CFrameValue")
		cfv.Value = model:GetPivot()
		cfv.Changed:Connect(function(v)
			if model.Parent then
				model:PivotTo(v)
			end
		end)
		TweenService:Create(cfv, TweenInfo.new(2.2, Enum.EasingStyle.Bounce), { Value = target }):Play()
		task.delay(2.5, function()
			cfv:Destroy()
		end)
	end
	local cid
	cid = Inventory.NewContainer("Crate", crateInv, model, title or "Supply Crate", {
		AllowStore = false,
		OnChanged = function(c)
			if InventoryCore.IsEmpty(c.Inv) then
				Inventory.RemoveContainer(cid)
				task.delay(2, function()
					model:Destroy()
				end)
			end
		end,
	})
	local prompt = Prompts.Make(body, "OpenContainer", "Open", title or "Supply Crate", { Distance = 9, Hold = 1, Rarity = "Epic" })
	prompt:SetAttribute("ContainerId", cid)
	return model
end

-- one valuable item somewhere, with a light beam so players can find it
function Loot.SpawnSpecial(pos: Vector3, rarity: string?)
	local zone = { Categories = { Food = 1, Material = 0.6, Tool = 1, Battery = 0.8, Medical = 1, Fuel = 0.6, Special = 2 }, Items = {} }
	local itemId, qty
	for _ = 1, 30 do
		itemId, qty = Items.Roll(zone, 8, rng)
		if itemId and Rarity.Rank(Items.Get(itemId).Rarity) >= Rarity.Rank(rarity or "Epic") then
			break
		end
	end
	local id = spawnItem(itemId, qty, rayDown(pos), {})
	local l = loots[id]
	if l then
		local beamPart = Instance.new("Part")
		beamPart.Anchored = true
		beamPart.CanCollide = false
		beamPart.CanQuery = false
		beamPart.Size = Vector3.new(0.6, 22, 0.6)
		beamPart.Color = Color3.fromHex(Rarity.Info[Items.Get(itemId).Rarity].Color)
		beamPart.Material = Enum.Material.Neon
		beamPart.Transparency = 0.6
		beamPart.CFrame = l.Model:GetPivot() + Vector3.new(0, 11, 0)
		beamPart.Parent = l.Model
	end
	return itemId, pos
end

-- a random loot point position (for events)
function Loot.RandomPoint(minDistFrom: Vector3?, level: number?)
	local points = State.Plan.LootPoints
	for _ = 1, 60 do
		local p = points[rng:Int(1, #points)]
		local cell = State.Plan.Cells[p.Cell]
		local zinfo = cell and Zones.Types[cell.Type]
		local okLevel = level == nil or (cell and cell.Level == level)
		local locked = cell and (cell.Type == "Sealed" and not State.GatesOpen.SealedWing)
		if okLevel and not locked and zinfo and p.Bonus < 2 then
			local v = Vector3.new(p.X, p.Y, p.Z)
			if not minDistFrom or (v - minDistFrom).Magnitude > 150 then
				return v
			end
		end
	end
	local p = points[1]
	return Vector3.new(p.X, p.Y, p.Z)
end

function Loot.ClearAll()
	for id in loots do
		Loot.Remove(id)
	end
	table.clear(pointUsed)
	table.clear(droppedOrder)
	worldCount = 0
	table.clear(exploredZones)
end

-- XP for discovering departments
local function exploreTick()
	local StoreLayout = require(Shared.StoreLayout)
	for _, player in Players:GetPlayers() do
		if State.InRun(player) and State.Plan then
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				local zone = StoreLayout.ZoneAt(State.Plan, root.Position.X, root.Position.Y, root.Position.Z)
				if zone and zone.Type ~= "Solid" then
					local seen = exploredZones[player]
					if not seen then
						seen = {}
						exploredZones[player] = seen
					end
					if not seen[zone.Id] then
						seen[zone.Id] = true
						if Util.Count(seen) > 1 then
							Progress.AddXP(player, Config.XP.ExploreZone, "Discovered " .. zone.Name)
							Progress.Track(player, "ZonesExplored", 1)
						end
					end
				end
			end
		end
	end
end

function Loot.Init()
	Prompts.Register("Loot", onLootPrompt)
	Players.PlayerRemoving:Connect(function(player)
		exploredZones[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(2)
			pcall(exploreTick)
		end
	end)
end

return Loot
