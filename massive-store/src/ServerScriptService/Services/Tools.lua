--[[
	Tools: flashlight & batteries, night vision, crowbar, flares, alarm clocks, stun baton,
	repellent, supply beacon, keycards, plus the world interactions that need tools
	(store doors, locked room doors, hidden wall panels, basement shutters).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local Net = require(Shared.Net)
local Progression = require(Shared.Progression)

local State = require(script.Parent.State)
local World = require(script.Parent.World)
local Data = require(script.Parent.Data)
local Survival = require(script.Parent.Survival)
local Inventory = require(script.Parent.Inventory)
local Prompts = require(script.Parent.Prompts)
local Progress = require(script.Parent.Progress)
local Noise = require(script.Parent.Noise)
local RateLimiter = require(script.Parent.RateLimiter)

local Tools = {}

local function lazy(name)
	return require(script.Parent[name])
end

local battery: { [Player]: number } = {}
local flashOn: { [Player]: boolean } = {}
local nvOn: { [Player]: boolean } = {}
local cooldown: { [Player]: { [string]: number } } = {}
local toggleLimiter = RateLimiter.new(10, 2)

local function cd(player: Player, key: string, seconds: number): boolean
	local t = cooldown[player]
	if not t then
		t = {}
		cooldown[player] = t
	end
	local now = os.clock()
	if (t[key] or 0) > now then
		return false
	end
	t[key] = now + seconds
	return true
end

local function setBattery(player: Player, v: number)
	battery[player] = math.clamp(v, 0, 100)
	player:SetAttribute("Battery", math.floor(battery[player] + 0.5))
end

function Tools.Battery(player: Player): number
	return battery[player] or 0
end

--============================ FLASHLIGHT ============================--
local function removeLight(player: Player)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if head then
		local old = head:FindFirstChild("Flashlight")
		if old then
			old:Destroy()
		end
	end
end

local function applyLight(player: Player)
	removeLight(player)
	if not flashOn[player] then
		return
	end
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then
		return
	end
	local perks = Progression.Perks(Data.Level(player))
	local tier = Progression.FlashlightTiers[perks.Flashlight]
	local d = Data.Get(player)
	local skin = Cosmetics.Get(d and d.Equipped.Flashlight or "BeamWarm") or Cosmetics.Get("BeamWarm")
	local light = Instance.new("SpotLight")
	light.Name = "Flashlight"
	light.Face = Enum.NormalId.Front
	light.Range = tier.Range
	light.Brightness = tier.Brightness
	light.Angle = tier.Angle
	light.Color = Color3.fromHex(skin.Color)
	light.Shadows = true
	light.Parent = head
end

function Tools.SetFlashlight(player: Player, on: boolean)
	if on then
		if Inventory.Count(player, "Flashlight") <= 0 then
			return
		end
		if (battery[player] or 0) <= 0 then
			State.Notify(player, "Flashlight battery is dead — [R] to put in batteries.", "Warn")
			return
		end
	end
	flashOn[player] = on
	player:SetAttribute("FlashOn", on)
	applyLight(player)
	State.Cue("FlashClick", nil, on, player)
end

function Tools.Recharge(player: Player, item): boolean
	local b = battery[player] or 0
	if b >= 99 then
		return false
	end
	setBattery(player, b + (item.Charge or 30))
	State.Notify(player, ("Batteries in: %d%%"):format(battery[player]), "Good")
	return true
end

local function reload(player: Player)
	for _, id in { "BatteryAA", "BatteryPack", "PowerCell" } do
		if Inventory.Count(player, id) > 0 then
			if Tools.Recharge(player, require(Shared.Items).Get(id)) then
				Inventory.TakeItem(player, id, 1)
			end
			return
		end
	end
	State.Notify(player, "No batteries! Look in Electronics and Toys.", "Warn")
end

--============================ TOOL USE ============================--
local function aimPoint(player: Player, aim: Vector3?, maxDist: number): Vector3?
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then
		return nil
	end
	local from = head.Position
	local dir
	if aim and (aim - from).Magnitude > 1 then
		dir = (aim - from).Unit
	else
		dir = (char :: Model):GetPivot().LookVector
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, World.Folders.Loot }
	local hit = Workspace:Raycast(from, dir * maxDist, params)
	return if hit then hit.Position + hit.Normal * 0.5 else from + dir * maxDist
end

local function effectPart(pos: Vector3, color: Color3, size: number)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = Vector3.new(size, size, size)
	p.Shape = Enum.PartType.Ball
	p.Color = color
	p.Material = Enum.Material.Neon
	p.CFrame = CFrame.new(pos)
	p.Parent = World.Folders.Dynamic
	return p
end

local function nearestLocust(pos: Vector3, range: number)
	local L = lazy("Locust").Get()
	if L and L.Root and (L.Root.Position - pos).Magnitude <= range then
		return L
	end
	return nil
end

function Tools.Use(player: Player, item, aim: Vector3?): boolean
	local tool = item.Tool
	local me = Survival.Position(player)
	if not me then
		return false
	end
	if tool == "Flashlight" then
		Tools.SetFlashlight(player, not flashOn[player])
		return false
	elseif tool == "Hammer" then
		Net.Event("Cue"):FireClient(player, "OpenBuild", nil, nil)
		return false
	elseif tool == "StoreMap" then
		Net.Event("Cue"):FireClient(player, "OpenMap", nil, nil)
		return false
	elseif tool == "NightVision" then
		Tools.SetNightVision(player, not nvOn[player])
		return false
	elseif tool == "Crowbar" then
		if not cd(player, "Crowbar", 0.8) then
			return false
		end
		State.Cue("Swing", me, nil)
		if nearestLocust(me, 9) then
			lazy("Locust").Hurt(8, player)
			lazy("Locust").Stun(0.4, player)
			State.Cue("HitLocust", me, nil)
		end
		return false
	elseif tool == "Flare" then
		local pos = aimPoint(player, aim, 45)
		if not pos then
			return false
		end
		local flare = effectPart(pos, Color3.fromHex("ff3d00"), 0.6)
		flare.Name = "Flare"
		local light = Instance.new("PointLight")
		light.Color = Color3.fromHex("ff5a2e")
		light.Range = 34
		light.Brightness = 3
		light.Parent = flare
		local sparks = Instance.new("ParticleEmitter")
		sparks.Color = ColorSequence.new(Color3.fromHex("ffcc80"), Color3.fromHex("ff3d00"))
		sparks.LightEmission = 1
		sparks.Rate = 40
		sparks.Lifetime = NumberRange.new(0.3, 0.8)
		sparks.Speed = NumberRange.new(3, 8)
		sparks.SpreadAngle = Vector2.new(40, 40)
		sparks.Size = NumberSequence.new(0.15, 0)
		sparks.Acceleration = Vector3.new(0, -20, 0)
		sparks.Parent = flare
		State.Cue("Flare", pos, nil)
		task.spawn(function()
			for _ = 1, 20 do
				if not flare.Parent then
					break
				end
				Noise.Emit(pos, Config.Noise.Flare, nil, "Flare")
				task.wait(1)
			end
		end)
		Debris:AddItem(flare, 21)
		return true
	elseif tool == "NoiseMaker" then
		local pos = me - Vector3.new(0, 2.5, 0)
		local clock = effectPart(pos, Color3.fromHex("f44336"), 0.8)
		clock.Shape = Enum.PartType.Block
		clock.Material = Enum.Material.SmoothPlastic
		State.Notify(player, "Alarm set! Run!", "Info")
		task.spawn(function()
			task.wait(3)
			for _ = 1, 15 do
				if not clock.Parent then
					break
				end
				Noise.Emit(pos, Config.Noise.NoiseMaker, nil, "Alarm")
				State.Cue("Ring", pos, nil)
				task.wait(1)
			end
			clock:Destroy()
		end)
		return true
	elseif tool == "StunBaton" then
		if not cd(player, "Baton", 5) then
			return false
		end
		if (battery[player] or 0) < 30 then
			State.Notify(player, "The baton needs 30% battery.", "Warn")
			return false
		end
		State.Cue("Zap", me, nil)
		local L = nearestLocust(me, 10)
		if L then
			setBattery(player, battery[player] - 30)
			lazy("Locust").Stun(2.6, player)
			lazy("Locust").Hurt(30, player)
			State.Notify(player, "ZAP! The Locust is stunned!", "Good")
		end
		return false
	elseif tool == "Repellent" then
		local cloud = effectPart(me - Vector3.new(0, 2, 0), Color3.fromHex("76ff03"), 1)
		cloud.Transparency = 1
		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(Color3.fromHex("b2ff59"))
		pe.Transparency = NumberSequence.new(0.7, 1)
		pe.Size = NumberSequence.new(6, 12)
		pe.Rate = 8
		pe.Lifetime = NumberRange.new(4, 6)
		pe.Speed = NumberRange.new(1, 3)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Parent = cloud
		lazy("Locust").AddRepellent(me, 26, 60)
		Debris:AddItem(cloud, 60)
		State.Notify(player, "Repellent sprayed: the Locust won't come near here for 60s.", "Good")
		return true
	elseif tool == "SupplyBeacon" then
		local pos = me - Vector3.new(0, 2.5, 0)
		local beacon = effectPart(pos, Color3.fromHex("ff6d00"), 0.8)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromHex("ff6d00")
		light.Range = 12
		light.Parent = beacon
		lazy("Events").QueueBeacon(pos, beacon)
		State.Notify(player, "Beacon placed. A supply crate will drop here at dawn.", "Good")
		return true
	elseif tool == "Keycard" then
		State.Notify(player, "Swipe it on security doors or the basement shutters.", "Info")
		return false
	elseif tool == "LuckyCoin" then
		State.Notify(player, "The coin feels warm. Loot you pick up is luckier.", "Info")
		return false
	end
	return false
end

function Tools.SetNightVision(player: Player, on: boolean)
	if on and (Inventory.Count(player, "NightVision") <= 0 or (battery[player] or 0) <= 0) then
		return
	end
	nvOn[player] = on
	player:SetAttribute("NightVision", on)
end

--============================ INTERACTIONS ============================--
local function storeDoor(player, prompt)
	local id = prompt:GetAttribute("Id")
	local d = World.StoreDoors[id]
	if d and not d.Locked then
		World.SetStoreDoor(id, not d.Open)
		Noise.Emit(d.Position, Config.Noise.DoorOpen, player, "Door")
	end
end

local function roomOpened(player: Player, pos: Vector3)
	Progress.Track(player, "RoomsOpened", 1)
	Progress.AddXP(player, 20, "Opened a locked room")
	State.Cue("RoomOpened", pos, nil)
end

local function roomDoor(player, prompt)
	local id = prompt:GetAttribute("Id")
	local d = World.RoomDoors[id]
	if not d then
		return
	end
	if d.Lock == "Crowbar" then
		if Inventory.Count(player, "Crowbar") <= 0 then
			State.Notify(player, "It's jammed. You need a Crowbar.", "Warn")
			return
		end
		World.UnlockRoomDoor(id)
		Noise.Emit(d.Position, 0.7, player, "Break")
		roomOpened(player, d.Position)
	elseif d.Lock == "Keycard" then
		if not Inventory.TakeItem(player, "Keycard", 1) then
			State.Notify(player, "Security door. You need a Keycard.", "Warn")
			return
		end
		World.UnlockRoomDoor(id)
		roomOpened(player, d.Position)
	else
		World.SetRoomDoor(id, not d.Open)
		Noise.Emit(d.Position, Config.Noise.DoorOpen, player, "Door")
	end
end

local function panel(player, prompt)
	local id = prompt:GetAttribute("Id")
	local p = World.Panels[id]
	if not p or p.Open then
		return
	end
	if Inventory.Count(player, "Crowbar") <= 0 then
		State.Notify(player, "The panel is loose... a Crowbar could pry it off.", "Warn")
		return
	end
	World.OpenPanel(id)
	Noise.Emit(p.CFrame.Position, 0.8, player, "Break")
	roomOpened(player, p.CFrame.Position)
	Progress.AddXP(player, 30, "Found a hidden room")
	State.Notify(player, "A hidden room!", "Legendary")
end

local function gate(player, prompt)
	local id = prompt:GetAttribute("Id")
	local g = World.Gates[id]
	if not g or g.Open then
		return
	end
	if not Inventory.TakeItem(player, "Keycard", 1) then
		State.Notify(player, "Needs a Security Keycard (or wait for night 10).", "Warn")
		return
	end
	lazy("Director").OpenGate(id, player)
end

--============================ LOOP ============================--
function Tools.ResetPlayer(player: Player)
	setBattery(player, 100)
	flashOn[player] = false
	nvOn[player] = false
	player:SetAttribute("FlashOn", false)
	player:SetAttribute("NightVision", false)
	removeLight(player)
end

function Tools.Init()
	Net.Event("Flashlight").OnServerEvent:Connect(function(player)
		if toggleLimiter:Allow(player) and Survival.IsActive(player) then
			Tools.SetFlashlight(player, not flashOn[player])
		end
	end)
	Net.Event("Reload").OnServerEvent:Connect(function(player)
		if toggleLimiter:Allow(player) and Survival.IsActive(player) then
			reload(player)
		end
	end)
	Net.Event("NightVision").OnServerEvent:Connect(function(player)
		if toggleLimiter:Allow(player) and Survival.IsActive(player) then
			Tools.SetNightVision(player, not nvOn[player])
		end
	end)

	Prompts.Register("StoreDoor", storeDoor)
	Prompts.Register("RoomDoor", roomDoor)
	Prompts.Register("Panel", panel)
	Prompts.Register("Gate", gate)

	Survival.Spawned:Connect(function(player)
		task.defer(applyLight, player)
	end)
	local function off(player)
		if flashOn[player] then
			Tools.SetFlashlight(player, false)
		end
	end
	Survival.Downed:Connect(off)
	Survival.Died:Connect(off)

	Players.PlayerRemoving:Connect(function(player)
		battery[player] = nil
		flashOn[player] = nil
		nvOn[player] = nil
		cooldown[player] = nil
	end)

	-- battery drain
	task.spawn(function()
		while true do
			local dt = task.wait(0.5)
			for player, on in flashOn do
				if on then
					local perks = Progression.Perks(Data.Level(player))
					local tier = Progression.FlashlightTiers[perks.Flashlight]
					setBattery(player, (battery[player] or 0) - tier.Drain * dt)
					if Inventory.Count(player, "Flashlight") <= 0 or battery[player] <= 0 then
						Tools.SetFlashlight(player, false)
						if battery[player] <= 0 then
							State.Notify(player, "Flashlight died. [R] to reload batteries.", "Warn")
						end
					end
				end
			end
			for player, on in nvOn do
				if on then
					setBattery(player, (battery[player] or 0) - 0.45 * dt)
					if battery[player] <= 0 or Inventory.Count(player, "NightVision") <= 0 then
						Tools.SetNightVision(player, false)
					end
				end
			end
		end
	end)
end

return Tools
