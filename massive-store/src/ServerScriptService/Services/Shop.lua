--[[
	Shop: Store Credits cosmetics, equipping, emotes, settings and Robux credit packs.
	Credits are earned by playing (nights survived, missions, legendary finds) and can
	optionally be bought. Robux only ever buys cosmetics (through credits) — never power.
	Purchases are idempotent (receipt ids are remembered) and saved right away.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local Net = require(Shared.Net)
local Util = require(Shared.Util)

local State = require(script.Parent.State)
local Data = require(script.Parent.Data)
local Survival = require(script.Parent.Survival)
local RateLimiter = require(script.Parent.RateLimiter)

local Shop = {}

local shopLimiter = RateLimiter.new(8, 4)
local emoteLimiter = RateLimiter.new(3, 3)
local settingsLimiter = RateLimiter.new(12, 4)

local SETTINGS = {
	Music = "boolean",
	SFX = "boolean",
	Effects = "boolean",
	CameraShake = "boolean",
	Brightness = "number",
	Sensitivity = "number",
}

--============================ VISUALS ============================--
local function applyCosmetics(player: Player)
	local char = player.Character
	local d = Data.Get(player)
	if not char or not d then
		return
	end
	local head = char:FindFirstChild("Head")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local old = char:FindFirstChild("CosmeticFx")
	if old then
		old:Destroy()
	end
	if head then
		local oldTitle = head:FindFirstChild("TitleGui")
		if oldTitle then
			oldTitle:Destroy()
		end
		local title = Cosmetics.Get(d.Equipped.Title)
		local bb = Instance.new("BillboardGui")
		bb.Name = "TitleGui"
		bb.Size = UDim2.fromOffset(200, 44)
		bb.StudsOffset = Vector3.new(0, 2.4, 0)
		bb.MaxDistance = 45
		bb.LightInfluence = 0
		bb.Adornee = head
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Size = UDim2.new(1, 0, 0.55, 0)
		name.Font = Enum.Font.GothamBlack
		name.TextScaled = true
		name.TextColor3 = Color3.new(1, 1, 1)
		name.TextStrokeTransparency = 0.5
		name.Text = player.DisplayName
		name.Parent = bb
		if title then
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Position = UDim2.fromScale(0, 0.55)
			t.Size = UDim2.new(1, 0, 0.42, 0)
			t.Font = Enum.Font.GothamBold
			t.TextScaled = true
			t.TextColor3 = Color3.fromHex(title.Color or "ffffff")
			t.TextStrokeTransparency = 0.6
			t.Text = string.upper(title.Name)
			t.Parent = bb
		end
		bb.Parent = head
	end
	-- outfit: a vest / jacket shell over the torso and arms
	local oldOutfit = char:FindFirstChild("Outfit")
	if oldOutfit then
		oldOutfit:Destroy()
	end
	local outfit = Cosmetics.Get(d.Equipped.Outfit or "OutfitNone")
	if outfit and outfit.Color then
		local folder = Instance.new("Folder")
		folder.Name = "Outfit"
		local function shell(partName: string, grow: Vector3, color: string, ofs: CFrame?)
			local base = char:FindFirstChild(partName)
			if not base or not base:IsA("BasePart") then
				return nil
			end
			local p = Instance.new("Part")
			p.Name = "OutfitShell"
			p.Size = base.Size + grow
			p.Color = Color3.fromHex(color)
			p.Material = Enum.Material.Fabric
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			p.CFrame = base.CFrame * (ofs or CFrame.new())
			local w = Instance.new("WeldConstraint")
			w.Part0 = base
			w.Part1 = p
			w.Parent = p
			p.Parent = folder
			return p
		end
		local torso = shell("UpperTorso", Vector3.new(0.12, 0.08, 0.14), outfit.Color) or shell("Torso", Vector3.new(0.12, 0.08, 0.14), outfit.Color)
		shell("LowerTorso", Vector3.new(0.1, 0.06, 0.12), outfit.Color)
		if outfit.Id ~= "OutfitClerk" then
			for _, arm in { "LeftUpperArm", "RightUpperArm", "Left Arm", "Right Arm" } do
				shell(arm, Vector3.new(0.08, 0.04, 0.08), outfit.Color)
			end
		end
		if outfit.Id == "OutfitHazmat" then
			for _, leg in { "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "Left Leg", "Right Leg" } do
				shell(leg, Vector3.new(0.08, 0.04, 0.08), outfit.Color)
			end
		end
		if torso and outfit.Accent then
			local badge = Instance.new("Part")
			badge.Name = "Badge"
			badge.Size = Vector3.new(0.5, 0.3, 0.06)
			badge.Color = Color3.fromHex(outfit.Accent)
			badge.Material = Enum.Material.SmoothPlastic
			badge.CanCollide = false
			badge.CanQuery = false
			badge.Massless = true
			badge.CFrame = torso.CFrame * CFrame.new(0.45, 0.25, -torso.Size.Z / 2 - 0.02)
			local w = Instance.new("WeldConstraint")
			w.Part0 = torso
			w.Part1 = badge
			w.Parent = badge
			badge.Parent = folder
		end
		folder.Parent = char
	end

	local fx = Cosmetics.Get(d.Equipped.Effect)
	if fx and fx.Color and hrp then
		local att = Instance.new("Attachment")
		att.Name = "CosmeticFx"
		att.Parent = hrp
		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(Color3.fromHex(fx.Color))
		pe.LightEmission = if fx.Id == "FxDust" then 0 else 0.8
		pe.Rate = if fx.Id == "FxFireflies" then 3 else 6
		pe.Lifetime = NumberRange.new(1, 2)
		pe.Speed = NumberRange.new(0.3, 1.2)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, if fx.Id == "FxPrices" then 0.4 else 0.18), NumberSequenceKeypoint.new(1, 0) })
		pe.Transparency = NumberSequence.new(0.1, 1)
		pe.Acceleration = if fx.Id == "FxEmbers" then Vector3.new(0, 3, 0) else Vector3.new(0, -0.5, 0)
		pe.Parent = att
		game:GetService("CollectionService"):AddTag(pe, "OptionalEffect")
	end
end
Shop.Apply = applyCosmetics

--============================ ACTIONS ============================--
local function buy(player: Player, id: string)
	local c = Cosmetics.Get(id)
	local d = Data.Get(player)
	if not c or not d then
		return { Ok = false, Message = "Unknown item" }
	end
	local level = Data.Level(player)
	if Cosmetics.Owns(d, level, id) then
		return { Ok = false, Message = "You already own this" }
	end
	if c.Level then
		return { Ok = false, Message = "Unlocks at level " .. c.Level }
	end
	if d.Credits < c.Price then
		return { Ok = false, Message = "Not enough Store Credits" }
	end
	Data.Update(player, function(data)
		data.Credits -= c.Price
		data.Owned[id] = true
	end)
	return { Ok = true }
end

local function equip(player: Player, id: string)
	local c = Cosmetics.Get(id)
	local d = Data.Get(player)
	if not c or not d or c.Slot == "Emote" or c.Slot == "Decor" then
		return { Ok = false }
	end
	if not Cosmetics.Owns(d, Data.Level(player), id) then
		return { Ok = false, Message = "You don't own this yet" }
	end
	Data.Update(player, function(data)
		data.Equipped[c.Slot] = id
	end)
	applyCosmetics(player)
	if c.Slot == "Flashlight" and player:GetAttribute("FlashOn") then
		local Tools = require(script.Parent.Tools)
		Tools.SetFlashlight(player, false)
		Tools.SetFlashlight(player, true)
	end
	return { Ok = true }
end

local function emote(player: Player, id: any)
	local c = type(id) == "string" and Cosmetics.Get(id)
	local d = Data.Get(player)
	if not c or c.Slot ~= "Emote" or not d or not Cosmetics.Owns(d, Data.Level(player), id) then
		return
	end
	if not Survival.IsActive(player) or player:GetAttribute("Hidden") then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = c.Anim
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		track:Play()
		task.delay(4, function()
			track:Stop(0.3)
		end)
	end
end

--============================ ROBUX CREDIT PACKS ============================--
local function processReceipt(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local pack = nil
	for _, p in Config.CreditProducts do
		if p.Id ~= 0 and p.Id == info.ProductId then
			pack = p
		end
	end
	if not pack then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local d = Data.Get(player)
	if not d then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if d.Purchases[info.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	Data.Update(player, function(data)
		data.Credits += pack.Credits
		data.Purchases[info.PurchaseId] = os.time()
		-- keep the receipt list small
		local count = Util.Count(data.Purchases)
		if count > 60 then
			local oldestKey, oldest = nil, math.huge
			for k, t in data.Purchases do
				if t < oldest then
					oldestKey, oldest = k, t
				end
			end
			if oldestKey then
				data.Purchases[oldestKey] = nil
			end
		end
	end)
	if not Data.CanSave(player) then
		-- don't grant purchases that can't be saved
		Data.Update(player, function(data)
			data.Credits -= pack.Credits
			data.Purchases[info.PurchaseId] = nil
		end)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	Data.SaveNow(player)
	State.Notify(player, ("+%d Store Credits — thank you!"):format(pack.Credits), "Credits")
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function Shop.Init()
	Net.Function("Shop").OnServerInvoke = function(player, req)
		if not shopLimiter:Allow(player) or type(req) ~= "table" or type(req.Id) ~= "string" then
			return { Ok = false, Message = "Slow down!" }
		end
		if req.Action == "Buy" then
			return buy(player, req.Id)
		elseif req.Action == "Equip" then
			return equip(player, req.Id)
		end
		return { Ok = false }
	end

	Net.Event("Emote").OnServerEvent:Connect(function(player, id)
		if emoteLimiter:Allow(player) then
			emote(player, id)
		end
	end)

	Net.Event("Settings").OnServerEvent:Connect(function(player, key, value)
		if not settingsLimiter:Allow(player) or type(key) ~= "string" then
			return
		end
		local t = SETTINGS[key]
		if not t or type(value) ~= t then
			return
		end
		if t == "number" then
			value = math.clamp(value, -1, 2)
		end
		Data.Update(player, function(d)
			d.Settings[key] = value
		end)
	end)

	MarketplaceService.ProcessReceipt = processReceipt

	Survival.Spawned:Connect(function(player)
		task.defer(applyCosmetics, player)
	end)
end

return Shop
