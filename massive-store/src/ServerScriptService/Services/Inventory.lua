--[[
	Inventory: server-side player inventories and containers (storage boxes, carts, lost bags,
	supply crates). The client sends requests; every one is validated here:
	  slot numbers, item ids, quantities, distance to the container, who has it open.

	Hotbar = the first 6 slots. Selecting a slot holds that item in your hand (visual only).
	UseItem dispatches to Survival (food / medicine), Tools, Power (fuel).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local InventoryCore = require(Shared.InventoryCore)
local Models = require(Shared.Models)
local Holding = require(Shared.Holding)
local Net = require(Shared.Net)
local Progression = require(Shared.Progression)

local State = require(script.Parent.State)
local Data = require(script.Parent.Data)
local Survival = require(script.Parent.Survival)
local Prompts = require(script.Parent.Prompts)
local Noise = require(script.Parent.Noise)
local RateLimiter = require(script.Parent.RateLimiter)

local Inventory = {}

local function lazy(name)
	return require(script.Parent[name])
end

local HOTBAR = 6
local inv: { [Player]: any } = {}
local selected: { [Player]: number } = {}
local openContainer: { [Player]: number } = {}
local containers: { [number]: any } = {}
local nextContainer = 0

local actionLimiter = RateLimiter.new(25, 3)
local useLimiter = RateLimiter.new(8, 2)
local hotbarLimiter = RateLimiter.new(20, 2)

Inventory.StarterKit = {
	{ "Flashlight", 1 },
	{ "Hammer", 1 },
	{ "Apple", 2 },
	{ "Water", 1 },
	{ "BatteryAA", 1 },
	{ "Wood", 8 },
}
local KEEP_ON_DEATH = { Flashlight = true, Hammer = true }

function Inventory.Get(player: Player)
	return inv[player]
end

local function sizeFor(player: Player): number
	local perks = Progression.Perks(Data.Level(player))
	return perks.Slots
end

local function updateFlags(player: Player)
	local i = inv[player]
	if not i then
		return
	end
	player:SetAttribute("HasFlashlight", InventoryCore.Count(i, "Flashlight") > 0)
	player:SetAttribute("HasHammer", InventoryCore.Count(i, "Hammer") > 0)
	player:SetAttribute("HasMap", InventoryCore.Count(i, "StoreMap") > 0)
	player:SetAttribute("HasNightVision", InventoryCore.Count(i, "NightVision") > 0)
	player:SetAttribute("HasLuckyCoin", InventoryCore.Count(i, "LuckyCoin") > 0)
	player:SetAttribute("Batteries", InventoryCore.Count(i, "BatteryAA") + InventoryCore.Count(i, "BatteryPack") + InventoryCore.Count(i, "PowerCell"))
end

--============================ HELD ITEM ============================--
local function clearHeld(player: Player)
	local char = player.Character
	if char then
		local old = char:FindFirstChild("HeldItem")
		if old then
			old:Destroy()
		end
	end
end

local function updateHeld(player: Player)
	clearHeld(player)
	local i = inv[player]
	local slot = selected[player] or 0
	local s = i and i.Slots[slot]
	local char = player.Character
	player:SetAttribute("HeldItem", if s then s.Id else "")
	if not s or not char then
		return
	end
	local r15Hand = char:FindFirstChild("RightHand")
	local hand = r15Hand or char:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local model = Models.Item(s.Id)
	model.Name = "HeldItem"
	model:SetAttribute("ItemId", s.Id)
	local handle = model.PrimaryPart :: BasePart
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.Massless = true
			p.CanQuery = false
			p.CanTouch = false
		end
	end
	-- a real grip (same numbers the first-person view model uses), not "stuck to the wrist"
	local grip = Holding.Grip(s.Id, r15Hand == nil)
	model:PivotTo(hand.CFrame * grip)
	local w = Instance.new("Weld")
	w.Name = "HeldGrip"
	w.Part0 = hand
	w.Part1 = handle
	w.C0 = grip
	w.C1 = handle.PivotOffset
	w.Parent = handle
	model.Parent = char
end

-- tell every client to play an action animation on this character (third person + view model)
function Inventory.PlayAction(player: Player, action: string?)
	local char = player.Character
	if not char or not action then
		return
	end
	char:SetAttribute("Action", action)
	char:SetAttribute("ActionN", (char:GetAttribute("ActionN") or 0) + 1)
end

--============================ SYNC ============================--
function Inventory.Push(player: Player)
	local i = inv[player]
	if not i then
		return
	end
	local data = InventoryCore.Serialize(i)
	data.Selected = selected[player] or 0
	Net.Event("Inventory"):FireClient(player, data)
	updateFlags(player)
	-- the selected stack may have changed
	local held = player:GetAttribute("HeldItem")
	local s = i.Slots[selected[player] or 0]
	if (s and s.Id or "") ~= held then
		updateHeld(player)
	end
end

local function pushContainer(id: number)
	local c = containers[id]
	if not c then
		return
	end
	local data = InventoryCore.Serialize(c.Inv)
	data.Id = id
	data.Kind = c.Kind
	data.Name = c.Name
	for viewer in c.Viewers do
		if openContainer[viewer] == id and viewer.Parent then
			Net.Event("Container"):FireClient(viewer, data)
		else
			c.Viewers[viewer] = nil
		end
	end
	if c.OnChanged then
		task.spawn(c.OnChanged, c)
	end
end
Inventory.PushContainer = pushContainer

--============================ API ============================--
function Inventory.Give(player: Player, id: string, qty: number): number
	local i = inv[player]
	if not i then
		return 0
	end
	local added = InventoryCore.Add(i, id, qty)
	if added > 0 then
		Inventory.Push(player)
	end
	return added
end

function Inventory.Count(player: Player, id: string): number
	local i = inv[player]
	return if i then InventoryCore.Count(i, id) else 0
end

function Inventory.TakeItem(player: Player, id: string, qty: number): boolean
	local i = inv[player]
	if not i or InventoryCore.Count(i, id) < qty then
		return false
	end
	InventoryCore.Remove(i, id, qty)
	Inventory.Push(player)
	return true
end

-- containers that pay for builds: your inventory + the cart you are pushing
local function payers(player: Player)
	local list = { inv[player] }
	local Carts = lazy("Carts")
	local cart = Carts.HeldBy(player)
	if cart then
		table.insert(list, cart.Inv)
	end
	return list
end

function Inventory.HasAll(player: Player, cost): boolean
	if not inv[player] then
		return false
	end
	return InventoryCore.HasAllMulti(payers(player), cost)
end

function Inventory.Consume(player: Player, cost): boolean
	if not Inventory.HasAll(player, cost) then
		return false
	end
	local list = payers(player)
	InventoryCore.ConsumeMulti(list, cost)
	Inventory.Push(player)
	local Carts = lazy("Carts")
	local cart = Carts.HeldBy(player)
	if cart then
		pushContainer(cart.ContainerId)
	end
	return true
end

function Inventory.RefreshSize(player: Player)
	local i = inv[player]
	if not i then
		return
	end
	local size = sizeFor(player)
	if size ~= i.Size then
		local overflow = InventoryCore.Resize(i, size)
		local pos = Survival.Position(player)
		for _, s in overflow do
			if pos then
				lazy("Loot").Drop(pos, s.Id, s.Qty)
			end
		end
		Inventory.Push(player)
	end
end

function Inventory.ResetPlayer(player: Player, starter: boolean)
	inv[player] = InventoryCore.new(sizeFor(player))
	selected[player] = 0
	if starter then
		for _, e in Inventory.StarterKit do
			InventoryCore.Add(inv[player], e[1], e[2])
		end
		if State.Mode == "Hardcore" then
			InventoryCore.Remove(inv[player], "Wood", 4)
		end
	end
	Inventory.Push(player)
end

-- drop everything (except the starter tools) as a searchable bag
function Inventory.DropBag(player: Player, position: Vector3)
	local i = inv[player]
	if not i or not position then
		return
	end
	local bag = InventoryCore.new(36)
	for slot = 1, i.Size do
		local s = i.Slots[slot]
		if s and not KEEP_ON_DEATH[s.Id] then
			InventoryCore.Add(bag, s.Id, s.Qty)
			i.Slots[slot] = nil
		end
	end
	Inventory.Push(player)
	if InventoryCore.IsEmpty(bag) then
		return
	end
	lazy("Loot").SpawnBag(position, bag, player.DisplayName .. "'s bag")
end

--============================ CONTAINERS ============================--
-- instance: BasePart/Model used for distance checks
function Inventory.NewContainer(kind: string, invData, instance: Instance, name: string, opts)
	nextContainer += 1
	local id = nextContainer
	containers[id] = {
		Id = id,
		Kind = kind,
		Inv = invData,
		Instance = instance,
		Name = name,
		Viewers = {},
		OnChanged = opts and opts.OnChanged,
		AllowStore = if opts and opts.AllowStore == false then false else true,
	}
	return id
end

function Inventory.GetContainer(id: number)
	return containers[id]
end

-- remove a container; its items spill on the floor (destroyed storage, broken cart)
function Inventory.RemoveContainer(id: number, spillAt: Vector3?)
	local c = containers[id]
	if not c then
		return
	end
	containers[id] = nil
	for viewer in c.Viewers do
		if openContainer[viewer] == id then
			openContainer[viewer] = nil
			Net.Event("Container"):FireClient(viewer, nil)
		end
	end
	if spillAt and not InventoryCore.IsEmpty(c.Inv) then
		lazy("Loot").SpawnBag(spillAt, c.Inv, "Spilled supplies")
	end
end

local function containerPos(c): Vector3?
	local inst = c.Instance
	if not inst or not inst.Parent then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	return nil
end

local function canReach(player: Player, c): boolean
	local Carts = lazy("Carts")
	local held = Carts.HeldBy(player)
	if held and held.ContainerId == c.Id then
		return true
	end
	local pos = containerPos(c)
	local me = Survival.Position(player)
	return pos ~= nil and me ~= nil and (pos - me).Magnitude <= Config.Survival.MaxReach + 4
end

function Inventory.Open(player: Player, id: number)
	local c = containers[id]
	if not c or not canReach(player, c) or not Survival.IsActive(player) then
		return
	end
	openContainer[player] = id
	c.Viewers[player] = true
	pushContainer(id)
end

function Inventory.Close(player: Player)
	local id = openContainer[player]
	openContainer[player] = nil
	if id and containers[id] then
		containers[id].Viewers[player] = nil
	end
	Net.Event("Container"):FireClient(player, nil)
end

--============================ USE ============================--
local function useItem(player: Player, slot: number, aim: Vector3?)
	local i = inv[player]
	local s = i and i.Slots[slot]
	if not s then
		return
	end
	local item = Items.Get(s.Id)
	local st = Survival.Get(player)
	if not item or not st or st.Dead then
		return
	end
	local consumed = false
	if not st.Downed then
		Inventory.PlayAction(player, Holding.ActionFor(s.Id))
	end

	if st.Downed then
		-- only a medkit (self revive) or adrenaline works while down
		if (item.Id == "Medkit" and State.ModeInfo.SelfRevive) or item.Id == "Adrenaline" then
			if not player:GetAttribute("SelfReviving") then
				player:SetAttribute("SelfReviving", true)
				local delay = if item.Id == "Adrenaline" then 1 else Config.Survival.SelfReviveTime
				InventoryCore.RemoveFromSlot(i, slot, 1)
				Inventory.Push(player)
				State.Notify(player, "Getting back up...", "Info")
				task.delay(delay, function()
					player:SetAttribute("SelfReviving", false)
					local now = Survival.Get(player)
					if now and now.Downed and not now.Dead then
						Survival.Revive(player, player, 45)
					end
				end)
			end
		end
		return
	end

	if item.Id == "Adrenaline" then
		-- revive a downed teammate nearby instantly
		local me = Survival.Position(player)
		for _, other in Players:GetPlayers() do
			local os_ = Survival.Get(other)
			local pos = Survival.Position(other)
			if other ~= player and os_ and os_.Downed and pos and me and (pos - me).Magnitude < 12 then
				Survival.Revive(other, player, 70)
				consumed = true
				break
			end
		end
		if not consumed then
			consumed = Survival.Consume(player, item.Use)
		end
	elseif item.Use and (item.Category == "Food" or item.Category == "Medical") then
		consumed = Survival.Consume(player, item.Use)
		if consumed then
			local pos = Survival.Position(player)
			if pos then
				Noise.Emit(pos, if item.Id == "Chips" then 0.45 else Config.Noise.Eat, player, "Eat")
			end
			State.Cue("Eat", pos, item.Id, player)
		end
	elseif item.Category == "Battery" then
		consumed = lazy("Tools").Recharge(player, item)
		if not consumed and item.Fuel then
			consumed = lazy("Power").RefuelNearest(player, item.Fuel)
		end
	elseif item.Category == "Fuel" then
		consumed = lazy("Power").RefuelNearest(player, item.Fuel)
		if not consumed then
			State.Notify(player, "Walk up to a generator to refuel it.", "Warn")
		end
	elseif item.Tool then
		consumed = lazy("Tools").Use(player, item, aim)
	elseif item.Category == "Material" then
		State.Notify(player, "Materials are used in the build menu [B].", "Info")
	end

	if consumed and i.Slots[slot] and i.Slots[slot].Id == item.Id then
		InventoryCore.RemoveFromSlot(i, slot, 1)
		Inventory.Push(player)
	elseif consumed then
		InventoryCore.Remove(i, item.Id, 1)
		Inventory.Push(player)
	end
end

--============================ REMOTES ============================--
local function validSlot(i, slot)
	return type(slot) == "number" and slot == slot and slot >= 1 and slot <= i.Size and slot % 1 == 0
end

local function onAction(player: Player, req)
	if not actionLimiter:Allow(player) or type(req) ~= "table" then
		return
	end
	local i = inv[player]
	if not i or not Survival.IsActive(player) then
		if req.Action == "Close" then
			Inventory.Close(player)
		end
		return
	end
	local action = req.Action
	if action == "Move" then
		if validSlot(i, req.From) and validSlot(i, req.To) then
			InventoryCore.Move(i, req.From, req.To)
			Inventory.Push(player)
		end
	elseif action == "Drop" then
		if validSlot(i, req.Slot) then
			local qty = if type(req.Qty) == "number" then math.clamp(math.floor(req.Qty), 1, 999) else nil
			local id, n = InventoryCore.RemoveFromSlot(i, req.Slot, qty)
			if id and n > 0 then
				local pos = Survival.Position(player)
				local r = Survival.Root(player)
				if pos and r then
					lazy("Loot").Drop(pos + r.CFrame.LookVector * 3, id, n)
				end
				Inventory.Push(player)
			end
		end
	elseif action == "Store" then
		local id = openContainer[player]
		local c = id and containers[id]
		if c and c.AllowStore and validSlot(i, req.Slot) and canReach(player, c) then
			local qty = if type(req.Qty) == "number" then math.clamp(math.floor(req.Qty), 1, 999) else nil
			if InventoryCore.Transfer(i, req.Slot, c.Inv, qty) > 0 then
				Inventory.Push(player)
				pushContainer(id)
			end
		end
	elseif action == "Take" then
		local id = openContainer[player]
		local c = id and containers[id]
		if c and type(req.Slot) == "number" and validSlot(c.Inv, req.Slot) and canReach(player, c) then
			local s = c.Inv.Slots[req.Slot]
			local qty = if type(req.Qty) == "number" then math.clamp(math.floor(req.Qty), 1, 999) else nil
			if s and InventoryCore.Transfer(c.Inv, req.Slot, i, qty) > 0 then
				lazy("Loot").OnPickedUp(player, s.Id, false)
				Inventory.Push(player)
				pushContainer(id)
			end
		end
	elseif action == "TakeAll" then
		local id = openContainer[player]
		local c = id and containers[id]
		if c and canReach(player, c) then
			for slot = 1, c.Inv.Size do
				if c.Inv.Slots[slot] then
					InventoryCore.Transfer(c.Inv, slot, i)
				end
			end
			Inventory.Push(player)
			pushContainer(id)
		end
	elseif action == "Give" then
		local target = Players:GetPlayerByUserId(tonumber(req.Target) or 0)
		if target and target ~= player and inv[target] and validSlot(i, req.Slot) and Survival.IsActive(target) then
			local a, b = Survival.Position(player), Survival.Position(target)
			if a and b and (a - b).Magnitude <= 14 then
				local s = i.Slots[req.Slot]
				local qty = if type(req.Qty) == "number" then math.clamp(math.floor(req.Qty), 1, 999) else nil
				local moved = InventoryCore.Transfer(i, req.Slot, inv[target], qty)
				if moved > 0 and s then
					Inventory.Push(player)
					Inventory.Push(target)
					State.Notify(target, ("%s gave you %dx %s"):format(player.DisplayName, moved, Items.Get(s.Id).Name), "Good")
				else
					State.Notify(player, target.DisplayName .. "'s inventory is full.", "Warn")
				end
			end
		end
	elseif action == "Close" then
		Inventory.Close(player)
	end
end

function Inventory.Init()
	Net.Event("InvAction").OnServerEvent:Connect(onAction)

	Net.Event("Hotbar").OnServerEvent:Connect(function(player, slot)
		if not hotbarLimiter:Allow(player) then
			return
		end
		local i = inv[player]
		if not i or type(slot) ~= "number" or slot % 1 ~= 0 or slot < 0 or slot > HOTBAR then
			return
		end
		selected[player] = if selected[player] == slot then 0 else slot
		updateHeld(player)
		Inventory.Push(player)
	end)

	Net.Event("UseItem").OnServerEvent:Connect(function(player, slot, aim)
		if not useLimiter:Allow(player) then
			return
		end
		local i = inv[player]
		if not i or not validSlot(i, slot) then
			return
		end
		if aim ~= nil and typeof(aim) ~= "Vector3" then
			aim = nil
		end
		useItem(player, slot, aim)
	end)

	Prompts.Register("OpenContainer", function(player, prompt)
		local id = prompt:GetAttribute("ContainerId")
		if type(id) == "number" then
			Inventory.Open(player, id)
		end
	end)

	Survival.Spawned:Connect(function(player)
		task.defer(updateHeld, player)
	end)
	Survival.Died:Connect(function(player, pos)
		Inventory.Close(player)
		if pos then
			Inventory.DropBag(player, pos)
		end
	end)

	lazy("Progress").LeveledUp:Connect(function(player)
		Inventory.RefreshSize(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		Inventory.Close(player)
		inv[player] = nil
		selected[player] = nil
	end)
end

function Inventory.Selected(player: Player): (number, string?)
	local slot = selected[player] or 0
	local i = inv[player]
	local s = i and i.Slots[slot]
	return slot, s and s.Id
end

return Inventory
