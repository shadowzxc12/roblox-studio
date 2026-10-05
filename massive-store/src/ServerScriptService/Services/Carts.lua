--[[
	Carts: shopping carts you can push around the store.
	  [E] push   [G] let go   [L] open the basket (or the CART tab while pushing)
	A pushed cart is welded in front of you (no wheel physics = cheap and smooth) and slows you
	a little depending on your cart upgrade. It is noisy: the Locust can hear it.
	The basket is a container: carry loot, move building materials (builds can use what's in
	the cart you push), help teammates. Your progression unlocks bigger baskets / better wheels
	(Progression Cart tier) and your equipped cosmetic cart paint is applied when you grab one.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local InventoryCore = require(Shared.InventoryCore)
local Models = require(Shared.Models)
local Net = require(Shared.Net)
local Progression = require(Shared.Progression)

local State = require(script.Parent.State)
local World = require(script.Parent.World)
local Data = require(script.Parent.Data)
local Survival = require(script.Parent.Survival)
local Inventory = require(script.Parent.Inventory)
local Prompts = require(script.Parent.Prompts)
local RateLimiter = require(script.Parent.RateLimiter)

local Carts = {}

local carts: { [number]: any } = {}
local held: { [Player]: any } = {}
local partToCart: { [BasePart]: any } = {}
local nextId = 0
local limiter = RateLimiter.new(10, 3)

local HOLD_OFFSET = CFrame.new(0, -2.15, -4.3)

local function paint(cart, skinId: string?)
	local skin = Cosmetics.Get(skinId or "CartChrome") or Cosmetics.Get("CartChrome")
	local color = Color3.fromHex(skin.Color)
	local material = if skin.Material then (Enum.Material :: any)[skin.Material] else Enum.Material.Metal
	for _, p in cart.Model:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "Wheel" and p.Name ~= "Root" and p.Name ~= "Handle" and p.Name ~= "Load" then
			p.Color = color
			if p.Name == "Rim" or p.Name == "Leg" or p.Name == "HandlePost" then
				p.Material = material
			end
		end
	end
end

local function updateLoad(cart)
	local used = 0
	for i = 1, cart.Inv.Size do
		if cart.Inv.Slots[i] then
			used += 1
		end
	end
	local load = cart.Model:FindFirstChild("Load")
	if load then
		local f = used / cart.Inv.Size
		load.Transparency = if f > 0 then 0 else 1
		load.Size = Vector3.new(2.5, 0.1 + f * 1.8, 3.9)
		local root = cart.Model.PrimaryPart
		-- re-weld at the new height
		local w = load:FindFirstChildOfClass("WeldConstraint")
		if w then
			w.Enabled = false
			load.CFrame = root.CFrame * CFrame.new(0, 1.4 + f * 0.9, 0)
			w.Enabled = true
		end
	end
	cart.Model:SetAttribute("Used", used)
	cart.Model:SetAttribute("Size", cart.Inv.Size)
end

local function setParked(cart, cf: CFrame)
	local model = cart.Model
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
		end
	end
	model:PivotTo(cf)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = p.Name ~= "Load" and p.Name ~= "Wheel"
			p.CollisionGroup = "Default"
		end
	end
end

local function spawnCart(cf: CFrame)
	nextId += 1
	local model = Models.Cart()
	model.Name = "Cart"
	local cart = {
		Id = nextId,
		Model = model,
		Inv = InventoryCore.new(Config.Carts.Slots[1]),
		Tier = 1,
		HP = Config.Carts.MaxHealth[1],
		Home = cf,
		HeldBy = nil,
	}
	cart.ContainerId = Inventory.NewContainer("Cart", cart.Inv, model, "Shopping Cart", {
		OnChanged = function()
			updateLoad(cart)
		end,
	})
	local root = model.PrimaryPart
	local handle = model:FindFirstChild("Handle") :: BasePart
	local push = Prompts.Make(handle, "CartPush", "Push", "Shopping Cart", { Distance = Config.Carts.GrabDistance })
	push:SetAttribute("CartId", cart.Id)
	local open = Prompts.Make(root, "OpenContainer", "Open basket", "", { Distance = Config.Carts.GrabDistance, Key = Enum.KeyCode.L, GamepadKey = Enum.KeyCode.ButtonY, Name = "OpenPrompt" })
	open:SetAttribute("ContainerId", cart.ContainerId)
	cart.PushPrompt = push
	cart.OpenPrompt = open
	model:SetAttribute("CartId", cart.Id)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			partToCart[p] = cart
		end
	end
	model.Parent = World.Folders.Carts
	setParked(cart, cf)
	paint(cart, nil)
	updateLoad(cart)
	carts[cart.Id] = cart
	return cart
end

local function groundCF(pos: Vector3, yaw: number): CFrame
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = { World.Folders.Carts, World.Folders.Loot, World.Folders.Dynamic }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	params.FilterDescendantsInstances = list
	local hit = Workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), params)
	local y = if hit then hit.Position.Y else pos.Y - 0.85
	return CFrame.new(pos.X, y + 0.85, pos.Z) * CFrame.Angles(0, yaw, 0)
end

function Carts.HeldBy(player: Player)
	return held[player]
end

function Carts.Release(player: Player)
	local cart = held[player]
	if not cart then
		return
	end
	held[player] = nil
	cart.HeldBy = nil
	local root = cart.Model.PrimaryPart
	local weld = root:FindFirstChild("HoldWeld")
	if weld then
		weld:Destroy()
	end
	local cf = root.CFrame
	local _, yaw = cf:ToOrientation()
	setParked(cart, groundCF(cf.Position, yaw))
	cart.PushPrompt.Enabled = true
	cart.OpenPrompt.Enabled = true
	Survival.SetCartTier(player, 0)
	player:SetAttribute("CartId", 0)
end

function Carts.Grab(player: Player, cart)
	if cart.HeldBy or held[player] or not Survival.IsActive(player) then
		return
	end
	local st = Survival.Get(player)
	if st.Hidden or st.Infected then
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	-- the pusher's progression decides basket size; their cosmetic decides the paint
	local perks = Progression.Perks(Data.Level(player))
	if perks.Cart > cart.Tier then
		cart.Tier = perks.Cart
		InventoryCore.Resize(cart.Inv, Config.Carts.Slots[cart.Tier])
		cart.HP = Config.Carts.MaxHealth[cart.Tier]
	end
	local d = Data.Get(player)
	paint(cart, d and d.Equipped.Cart)
	for _, p in cart.Model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.Massless = true
			p.CollisionGroup = "Players"
		end
	end
	local root = cart.Model.PrimaryPart
	root.CFrame = hrp.CFrame * HOLD_OFFSET
	local weld = Instance.new("Weld")
	weld.Name = "HoldWeld"
	weld.Part0 = hrp
	weld.Part1 = root
	weld.C0 = HOLD_OFFSET
	weld.Parent = root
	cart.HeldBy = player
	held[player] = cart
	cart.PushPrompt.Enabled = false
	cart.OpenPrompt.Enabled = false
	Survival.SetCartTier(player, cart.Tier)
	player:SetAttribute("CartId", cart.Id)
	player:SetAttribute("CartContainer", cart.ContainerId)
	updateLoad(cart)
	State.Notify(player, ("Pushing a cart (%d slots). [G] let go · [X] open basket"):format(cart.Inv.Size), "Info")
end

-- the Locust walked into something: push a parked cart out of the way
function Carts.Shove(inst: Instance, dir: Vector3): boolean
	local cart = partToCart[inst :: any]
	if not cart or cart.HeldBy then
		return false
	end
	local cf = cart.Model:GetPivot()
	local side = Vector3.new(-dir.Z, 0, dir.X)
	if math.random() < 0.5 then
		side = -side
	end
	local target = cf.Position + side * 6 + dir * 2
	local _, yaw = cf:ToOrientation()
	setParked(cart, groundCF(target, yaw + math.rad(math.random(-40, 40))))
	cart.HP -= 40
	if cart.HP <= 0 then
		Carts.Break(cart)
	end
	return true
end

function Carts.Break(cart)
	if cart.HeldBy then
		Carts.Release(cart.HeldBy)
	end
	local pos = cart.Model:GetPivot().Position
	carts[cart.Id] = nil
	for p, c in partToCart do
		if c == cart then
			partToCart[p] = nil
		end
	end
	Inventory.RemoveContainer(cart.ContainerId, pos)
	State.Cue("StructureBreak", pos, 1)
	cart.Model:Destroy()
	-- a fresh cart appears back at its spot later
	task.delay(90, function()
		if State.RunActive then
			spawnCart(cart.Home)
		end
	end)
end

function Carts.SpawnAll()
	for _, c in carts do
		Inventory.RemoveContainer(c.ContainerId)
		c.Model:Destroy()
	end
	table.clear(carts)
	table.clear(partToCart)
	table.clear(held)
	for _, sp in State.Plan.CartSpawns do
		spawnCart(groundCF(Vector3.new(sp.X, sp.Y + 1, sp.Z), math.rad(sp.Yaw or 0)))
	end
end

function Carts.Init()
	Prompts.Register("CartPush", function(player, prompt)
		local cart = carts[prompt:GetAttribute("CartId")]
		if cart then
			Carts.Grab(player, cart)
		end
	end)
	Net.Event("Cart").OnServerEvent:Connect(function(player, req)
		if not limiter:Allow(player) or type(req) ~= "table" then
			return
		end
		if req.Action == "Release" then
			Carts.Release(player)
		elseif req.Action == "Open" then
			local cart = held[player]
			if cart then
				Inventory.Open(player, cart.ContainerId)
			end
		end
	end)
	-- let go when something happens to the pusher
	local function drop(player)
		if held[player] then
			Carts.Release(player)
		end
	end
	Survival.Downed:Connect(drop)
	Survival.Died:Connect(drop)
	Players.PlayerRemoving:Connect(drop)
	task.spawn(function()
		while true do
			task.wait(0.5)
			for player, cart in held do
				local st = Survival.Get(player)
				if not st or st.Hidden or not player.Character or not cart.Model.Parent then
					Carts.Release(player)
				end
			end
		end
	end)
end

return Carts
