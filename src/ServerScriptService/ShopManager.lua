--[[
	ShopManager: cosmetic shop (coins only, no gameplay advantages) + settings saving.
	- RequestShop (RemoteFunction): { Action = "Buy" | "Equip" | "Unequip", Id = itemId }
	- RequestSettings (RemoteEvent): (key, boolean)
	The server checks everything: item exists, price, coins, ownership, rate limits.
	Also puts the equipped cosmetics on the character (trail, aura, title).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Modules.Config)
local Cosmetics = require(ReplicatedStorage.Modules.Cosmetics)
local DataManager = require(script.Parent.DataManager)
local RateLimiter = require(script.Parent.RateLimiter)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local ShopManager = {}

local shopLimiter = RateLimiter.new(8, 5)
local settingsLimiter = RateLimiter.new(10, 5)

local function clearCosmetics(char: Model)
	local old = char:FindFirstChild("Cosmetics")
	if old then
		old:Destroy()
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		for _, c in hrp:GetChildren() do
			if c:GetAttribute("Cosmetic") then
				c:Destroy()
			end
		end
	end
end

-- Builds the visuals for the equipped Trail / Aura / Title.
function ShopManager.ApplyCosmetics(player: Player)
	local char = player.Character
	local data = DataManager.Get(player)
	if not char or not data then
		return
	end
	clearCosmetics(char)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local head = char:FindFirstChild("Head")
	if not hrp then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Cosmetics"

	local trail = Cosmetics.Get(data.Equipped.Trail)
	if trail then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.8, 0)
		a0:SetAttribute("Cosmetic", true)
		a0.Parent = hrp
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.8, 0)
		a1:SetAttribute("Cosmetic", true)
		a1.Parent = hrp
		local t = Instance.new("Trail")
		t.Attachment0 = a0
		t.Attachment1 = a1
		t.Lifetime = 0.45
		t.LightEmission = 0.4
		t.Transparency = NumberSequence.new(0.2, 1)
		if trail.Rainbow then
			t.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromHex("ff4f6d")),
				ColorSequenceKeypoint.new(0.25, Color3.fromHex("ffd23f")),
				ColorSequenceKeypoint.new(0.5, Color3.fromHex("6aea4f")),
				ColorSequenceKeypoint.new(0.75, Color3.fromHex("4cc3ff")),
				ColorSequenceKeypoint.new(1, Color3.fromHex("9b4dff")),
			})
		else
			t.Color = ColorSequence.new(trail.Color, trail.Color2 or trail.Color)
		end
		CollectionService:AddTag(t, "OptionalEffect")
		t.Parent = folder
	end

	local aura = Cosmetics.Get(data.Equipped.Aura)
	if aura then
		local pe = Instance.new("ParticleEmitter")
		pe:SetAttribute("Cosmetic", true)
		pe.Color = ColorSequence.new(aura.Color)
		pe.LightEmission = 0.7
		pe.Rate = 6
		pe.Lifetime = NumberRange.new(0.8, 1.4)
		pe.Speed = NumberRange.new(0.5, 1.5)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		pe.Transparency = NumberSequence.new(0.1, 1)
		CollectionService:AddTag(pe, "OptionalEffect")
		pe.Parent = hrp
	end

	local title = Cosmetics.Get(data.Equipped.Title)
	if title and head then
		local bb = Instance.new("BillboardGui")
		bb.Name = "Title"
		bb.Adornee = head
		bb.Size = UDim2.fromScale(4, 0.6)
		bb.StudsOffset = Vector3.new(0, 1.7, 0)
		bb.MaxDistance = 60
		bb.LightInfluence = 0
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.Text = "~ " .. title.Name .. " ~"
		l.TextColor3 = title.Color
		local s = Instance.new("UIStroke")
		s.Thickness = 1.5
		s.Parent = l
		l.Parent = bb
		bb.Parent = folder
	end

	folder.Parent = char
end

-- The colour of a player's tag effect (or nil = default burst)
function ShopManager.GetTagEffect(player: Player)
	local data = DataManager.Get(player)
	return data and Cosmetics.Get(data.Equipped.TagEffect)
end

local function handleShop(player: Player, request)
	if not shopLimiter:Allow(player) then
		return { Ok = false, Message = "Slow down!" }
	end
	if type(request) ~= "table" or type(request.Action) ~= "string" then
		return { Ok = false, Message = "Bad request" }
	end
	local data = DataManager.Get(player)
	if not data then
		return { Ok = false, Message = "Data still loading" }
	end
	local item = Cosmetics.Get(request.Id)

	if request.Action == "Buy" then
		if not item then
			return { Ok = false, Message = "Unknown item" }
		end
		if data.OwnedCosmetics[item.Id] then
			return { Ok = false, Message = "Already owned" }
		end
		if data.Coins < item.Price then
			return { Ok = false, Message = "Not enough coins" }
		end
		DataManager.Update(player, function(d)
			d.Coins -= item.Price
			d.OwnedCosmetics[item.Id] = true
			d.Equipped[item.Category] = item.Id
		end)
		ShopManager.ApplyCosmetics(player)
		return { Ok = true, Message = "Bought " .. item.Name .. "!" }
	elseif request.Action == "Equip" then
		if not item or not data.OwnedCosmetics[item.Id] then
			return { Ok = false, Message = "You don't own that" }
		end
		DataManager.Update(player, function(d)
			d.Equipped[item.Category] = item.Id
		end)
		ShopManager.ApplyCosmetics(player)
		return { Ok = true, Message = "Equipped " .. item.Name }
	elseif request.Action == "Unequip" then
		local category = request.Category
		if type(category) ~= "string" or data.Equipped[category] == nil then
			return { Ok = false, Message = "Bad category" }
		end
		DataManager.Update(player, function(d)
			d.Equipped[category] = ""
		end)
		ShopManager.ApplyCosmetics(player)
		return { Ok = true, Message = "Unequipped" }
	end
	return { Ok = false, Message = "Unknown action" }
end

function ShopManager.Init()
	Remotes.RequestShop.OnServerInvoke = handleShop

	local allowed = {}
	for _, k in Config.SettingKeys do
		allowed[k] = true
	end
	Remotes.RequestSettings.OnServerEvent:Connect(function(player, key, value)
		if not settingsLimiter:Allow(player) then
			return
		end
		if type(key) ~= "string" or not allowed[key] or type(value) ~= "boolean" then
			return
		end
		DataManager.Update(player, function(d)
			d.Settings[key] = value
		end)
	end)

	local function hook(player: Player)
		player.CharacterAdded:Connect(function(char)
			char:WaitForChild("HumanoidRootPart", 5)
			char:WaitForChild("Head", 5)
			ShopManager.ApplyCosmetics(player)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
	DataManager.ProfileLoaded.Event:Connect(function(player)
		ShopManager.ApplyCosmetics(player)
	end)
end

return ShopManager
