--[[
	Building: player bases. Place / upgrade / repair / remove structures.

	The client only proposes { Id, Position, Rotation }. The server:
	  - checks the build exists, the player's level/tier unlocks, cosmetic ownership
	  - snaps the position to the grid and the rotation to 90 degrees
	  - checks reach, structure limits, spawn protection zone and overlaps
	  - takes the materials (inventory + the cart you are pushing)
	Structures have HP; the Locust damages them (Config.BreakMultiplier decides how well).
	Doors, storage, beds, lights, cameras, traps, turrets and generators get their behaviour here
	(power comes from Power).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Buildables = require(Shared.Buildables)
local Cosmetics = require(Shared.Cosmetics)
local InventoryCore = require(Shared.InventoryCore)
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local Progression = require(Shared.Progression)

local State = require(script.Parent.State)
local World = require(script.Parent.World)
local Data = require(script.Parent.Data)
local Survival = require(script.Parent.Survival)
local Inventory = require(script.Parent.Inventory)
local Progress = require(script.Parent.Progress)
local Prompts = require(script.Parent.Prompts)
local Noise = require(script.Parent.Noise)
local RateLimiter = require(script.Parent.RateLimiter)

local Building = {}
Building.Destroyed = Signal.new() -- (structure)
Building.Placed = Signal.new() -- (structure)

local structures: { [number]: any } = {}
local byModel: { [Model]: any } = {}
local nextId = 0
local perPlayer: { [number]: number } = {}
local total = 0
local buildLimiter = RateLimiter.new(8, 2)

local GRID = Config.Building.Grid

local function col(hex)
	return Color3.fromHex(hex)
end

local function mat(name)
	local ok, m = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and m then m else Enum.Material.SmoothPlastic
end

function Building.All()
	return structures
end

function Building.FromInstance(inst: Instance?)
	while inst and inst ~= Workspace do
		if inst:IsA("Model") and byModel[inst] then
			return byModel[inst]
		end
		inst = inst.Parent
	end
	return nil
end

--============================ VISUALS ============================--
local function newPart(model, name, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = model
	return p
end

-- builds the parts of a structure at cf (cf = centre of its bounding box)
local function buildVisual(def, cf: CFrame, ownerSkin): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = def.Id
	local size = Vector3.new(def.Size[1], def.Size[2], def.Size[3])
	local c, m = col(def.Color), mat(def.Material)
	local main
	if def.Kind == "Wall" or def.Kind == "Barricade" then
		main = newPart(model, "Main", size, cf, c, m)
		if def.Kind == "Barricade" then
			main.Transparency = 1
			main.CanQuery = true
			for i = -1, 1, 2 do
				newPart(model, "Plank", Vector3.new(size.X, 1, size.Z * 0.8), cf * CFrame.new(0, i * 0.8, 0) * CFrame.Angles(0, 0, math.rad(i * 10)), c, m, { CanCollide = false })
			end
		end
		if def.Tier >= 3 then
			for _, y in { -size.Y / 2 + 0.4, size.Y / 2 - 0.4 } do
				newPart(model, "Trim", Vector3.new(size.X, 0.5, size.Z + 0.2), cf * CFrame.new(0, y, 0), col(if def.Glow then def.Glow else "3a3f4a"), if def.Glow then Enum.Material.Neon else Enum.Material.Metal, { CanCollide = false, CanQuery = false })
			end
		end
	elseif def.Kind == "Window" then
		main = newPart(model, "Main", size, cf, c, m, { Transparency = 1 })
		local fw = 1.4
		newPart(model, "Frame", Vector3.new(size.X, fw, size.Z), cf * CFrame.new(0, size.Y / 2 - fw / 2, 0), c, m, { CanCollide = false })
		newPart(model, "Frame", Vector3.new(size.X, 3, size.Z), cf * CFrame.new(0, -size.Y / 2 + 1.5, 0), c, m, { CanCollide = false })
		newPart(model, "Frame", Vector3.new(fw, size.Y, size.Z), cf * CFrame.new(-size.X / 2 + fw / 2, 0, 0), c, m, { CanCollide = false })
		newPart(model, "Frame", Vector3.new(fw, size.Y, size.Z), cf * CFrame.new(size.X / 2 - fw / 2, 0, 0), c, m, { CanCollide = false })
		newPart(model, "Glass", Vector3.new(size.X - 2 * fw, size.Y - 3 - fw, 0.2), cf * CFrame.new(0, 0.8, 0), col("bfe9ff"), Enum.Material.Glass, { Transparency = 0.55, CanCollide = false })
		if def.Tier >= 2 then
			for i = -1, 1 do
				newPart(model, "Bar", Vector3.new(0.25, size.Y - 3 - fw, 0.3), cf * CFrame.new(i * 1.6, 0.8, 0), col("5c636b"), Enum.Material.Metal, { CanCollide = false })
			end
		end
	elseif def.Kind == "Door" then
		-- the frame is the "Main" part (no collision); the leaf blocks
		main = newPart(model, "Main", size, cf, c, m, { Transparency = 1, CanCollide = false })
		newPart(model, "Frame", Vector3.new(0.8, size.Y, size.Z + 0.2), cf * CFrame.new(-size.X / 2 + 0.4, 0, 0), c:Lerp(Color3.new(0, 0, 0), 0.3), m)
		newPart(model, "Frame", Vector3.new(0.8, size.Y, size.Z + 0.2), cf * CFrame.new(size.X / 2 - 0.4, 0, 0), c:Lerp(Color3.new(0, 0, 0), 0.3), m)
		newPart(model, "Frame", Vector3.new(size.X, 0.8, size.Z + 0.2), cf * CFrame.new(0, size.Y / 2 - 0.4, 0), c:Lerp(Color3.new(0, 0, 0), 0.3), m)
		local leaf = newPart(model, "Leaf", Vector3.new(size.X - 1.6, size.Y - 0.8, size.Z * 0.8), cf * CFrame.new(0, -0.4, 0), c, m)
		newPart(model, "Knob", Vector3.new(0.3, 0.3, size.Z + 0.4), cf * CFrame.new(size.X / 2 - 1.6, -0.4, 0), col("ffc61a"), Enum.Material.Metal, { CanCollide = false })
		if def.Glow then
			newPart(model, "Glow", Vector3.new(size.X - 1.6, 0.3, size.Z + 0.1), cf * CFrame.new(0, 1, 0), col(def.Glow), Enum.Material.Neon, { CanCollide = false, CanQuery = false })
		end
		leaf:SetAttribute("ClosedCF", leaf.CFrame)
	elseif def.Kind == "Floor" then
		main = newPart(model, "Main", size, cf, c, m)
	elseif def.Kind == "Ramp" then
		main = newPart(model, "Main", size, cf, c, m, { Transparency = 1, CanCollide = false })
		local w = Instance.new("WedgePart")
		w.Name = "Wedge"
		w.Anchored = true
		w.Size = size
		w.CFrame = cf
		w.Color = c
		w.Material = m
		w.Parent = model
	elseif def.Kind == "Table" then
		main = newPart(model, "Main", Vector3.new(size.X, 0.4, size.Z), cf * CFrame.new(0, size.Y / 2 - 0.2, 0), c, m)
		for _, x in { -1, 1 } do
			for _, z in { -1, 1 } do
				newPart(model, "Leg", Vector3.new(0.4, size.Y - 0.4, 0.4), cf * CFrame.new(x * (size.X / 2 - 0.4), -0.2, z * (size.Z / 2 - 0.4)), c, m)
			end
		end
	elseif def.Kind == "Storage" then
		main = newPart(model, "Main", size, cf, c, m)
		newPart(model, "Lid", Vector3.new(size.X + 0.1, 0.3, size.Z + 0.1), cf * CFrame.new(0, size.Y / 2 - 0.15, 0), c:Lerp(Color3.new(0, 0, 0), 0.25), m, { CanCollide = false })
		newPart(model, "Label", Vector3.new(size.X * 0.4, 0.5, 0.1), cf * CFrame.new(0, size.Y * 0.15, -size.Z / 2 - 0.05), col("ffc61a"), Enum.Material.SmoothPlastic, { CanCollide = false, CanQuery = false })
	elseif def.Kind == "Bed" then
		main = newPart(model, "Main", Vector3.new(size.X, 1.2, size.Z), cf * CFrame.new(0, -size.Y / 2 + 0.6, 0), col("5d4037"), Enum.Material.Wood)
		newPart(model, "Mattress", Vector3.new(size.X - 0.4, 0.6, size.Z - 0.4), cf * CFrame.new(0, -size.Y / 2 + 1.5, 0), c, m, { CanCollide = false })
		newPart(model, "Pillow", Vector3.new(size.X - 1.2, 0.4, 1.2), cf * CFrame.new(0, -size.Y / 2 + 2, size.Z / 2 - 1), col("eceff1"), Enum.Material.Fabric, { CanCollide = false })
	elseif def.Kind == "Generator" then
		main = newPart(model, "Main", size, cf, c, m)
		newPart(model, "Panel", Vector3.new(1.6, 1.2, 0.2), cf * CFrame.new(-1, 0.6, -size.Z / 2 - 0.1), col("212121"), Enum.Material.SmoothPlastic, { CanCollide = false })
		local lamp = newPart(model, "StatusLamp", Vector3.new(0.4, 0.4, 0.2), cf * CFrame.new(1.2, 1, -size.Z / 2 - 0.1), col("ff1744"), Enum.Material.Neon, { CanCollide = false, CanQuery = false })
		lamp:SetAttribute("Lamp", true)
		newPart(model, "Exhaust", Vector3.new(0.6, 1.6, 0.6), cf * CFrame.new(1.6, size.Y / 2 + 0.8, 1), col("424242"), Enum.Material.Metal, { CanCollide = false })
	elseif def.Kind == "Light" then
		main = newPart(model, "Main", Vector3.new(0.4, size.Y, 0.4), cf, col("424242"), Enum.Material.Metal)
		newPart(model, "Base", Vector3.new(size.X, 0.3, size.Z), cf * CFrame.new(0, -size.Y / 2 + 0.15, 0), col("212121"), Enum.Material.Metal, { CanCollide = false })
		local head = newPart(model, "Bulb", Vector3.new(1.4, 0.8, 1.4), cf * CFrame.new(0, size.Y / 2, 0), col("fff3c4"), Enum.Material.SmoothPlastic, { CanCollide = false })
		local light = Instance.new("PointLight")
		light.Name = "BaseLight"
		light.Range = 30
		light.Brightness = 2
		light.Color = col("ffe9b8")
		light.Shadows = true
		light.Enabled = false
		light.Parent = head
	elseif def.Kind == "Camera" then
		main = newPart(model, "Main", Vector3.new(1, 1, size.Z), cf, c, m)
		newPart(model, "Lens", Vector3.new(0.6, 0.6, 0.2), cf * CFrame.new(0, 0, -size.Z / 2 - 0.1), col("111111"), Enum.Material.Glass, { CanCollide = false })
		local led = newPart(model, "StatusLamp", Vector3.new(0.2, 0.2, 0.2), cf * CFrame.new(0.35, 0.35, -size.Z / 2), col("ff1744"), Enum.Material.Neon, { CanCollide = false, CanQuery = false })
		led:SetAttribute("Lamp", true)
		newPart(model, "Mount", Vector3.new(0.3, size.Y, 0.3), cf * CFrame.new(0, -size.Y / 2, 0.6), col("9e9e9e"), Enum.Material.Metal, { CanCollide = false })
	elseif def.Kind == "Trap" then
		main = newPart(model, "Main", size, cf, c, m, { CanCollide = false })
		if def.Id == "BearTrap" then
			for i = -1, 1, 2 do
				newPart(model, "Jaw", Vector3.new(size.X * 0.9, 0.5, 0.25), cf * CFrame.new(0, 0.3, i * 0.8) * CFrame.Angles(math.rad(i * 35), 0, 0), col("9e9e9e"), Enum.Material.Metal, { CanCollide = false })
			end
		else
			newPart(model, "Grid", Vector3.new(size.X - 0.6, 0.1, size.Z - 0.6), cf * CFrame.new(0, size.Y / 2, 0), col(def.Glow or "40c4ff"), Enum.Material.Neon, { CanCollide = false, CanQuery = false, Transparency = 0.6 })
		end
	elseif def.Kind == "Turret" then
		main = newPart(model, "Main", Vector3.new(size.X, 1.6, size.Z), cf * CFrame.new(0, -size.Y / 2 + 0.8, 0), c, m)
		newPart(model, "Post", Vector3.new(0.8, 1.6, 0.8), cf * CFrame.new(0, 0, 0), col("263238"), Enum.Material.Metal)
		local head = newPart(model, "Head", Vector3.new(1.8, 1.2, 2.4), cf * CFrame.new(0, size.Y / 2 - 0.6, 0), col("455a64"), Enum.Material.Metal, { CanCollide = false })
		newPart(model, "Barrel", Vector3.new(0.3, 0.3, 1.6), cf * CFrame.new(0, size.Y / 2 - 0.6, -1.8), col("111111"), Enum.Material.Metal, { CanCollide = false })
		head:SetAttribute("Head", true)
		local led = newPart(model, "StatusLamp", Vector3.new(0.3, 0.3, 0.3), cf * CFrame.new(0, size.Y / 2, 0.9), col("ff1744"), Enum.Material.Neon, { CanCollide = false, CanQuery = false })
		led:SetAttribute("Lamp", true)
	elseif def.Kind == "Decoration" then
		if def.Id == "DecoPlant" then
			main = newPart(model, "Main", Vector3.new(1.6, 1.8, 1.6), cf * CFrame.new(0, -size.Y / 2 + 0.9, 0), col("bf6f3a"), Enum.Material.SmoothPlastic)
			newPart(model, "Leaves", Vector3.new(3.4, 3.4, 3.4), cf * CFrame.new(0, size.Y / 2 - 1.7, 0), c, m, { Shape = Enum.PartType.Ball, CanCollide = false })
		elseif def.Id == "DecoFlag" then
			main = newPart(model, "Main", Vector3.new(0.3, size.Y, 0.3), cf * CFrame.new(-size.X / 2, 0, 0), col("9e9e9e"), Enum.Material.Metal)
			newPart(model, "Cloth", Vector3.new(size.X, 2.2, 0.1), cf * CFrame.new(0, size.Y / 2 - 1.3, 0), c, m, { CanCollide = false })
		elseif def.Id == "DecoGnome" then
			main = newPart(model, "Main", Vector3.new(1.2, 1.6, 1.2), cf * CFrame.new(0, -0.7, 0), col("1e88e5"), Enum.Material.SmoothPlastic)
			newPart(model, "Head", Vector3.new(0.9, 0.9, 0.9), cf * CFrame.new(0, 0.4, 0), col("ffccbc"), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball, CanCollide = false })
			newPart(model, "Hat", Vector3.new(0.9, 1, 0.9), cf * CFrame.new(0, 1.2, 0), c, m, { CanCollide = false })
		else
			main = newPart(model, "Main", size, cf, c, m, { CanCollide = false })
			local light = Instance.new("PointLight")
			light.Color = c
			light.Range = 12
			light.Brightness = 1.2
			light.Parent = main
		end
	else
		main = newPart(model, "Main", size, cf, c, m)
	end
	model.PrimaryPart = main
	-- the Locust's pathfinding plans through structures it can break (see Locust.setupPaths)
	local mod = Instance.new("PathfindingModifier")
	mod.Name = "LocustCost"
	mod.PassThrough = true
	mod.Label = Building.ModifierLabel(def, false)
	mod.Parent = main
	return model, main
end

function Building.ModifierLabel(def, locked: boolean): string
	if def.Kind == "Door" and not locked then
		return "Door"
	elseif def.Kind == "Barricade" then
		return "B" .. math.max(1, def.Tier)
	elseif def.Tier <= 0 then
		return "T0"
	end
	return "T" .. def.Tier
end

--============================ PLACEMENT ============================--
function Building.SnapCFrame(def, pos: Vector3, rot: number): CFrame
	return Buildables.Snap(def, pos, rot, GRID)
end

local function overlapParams(ignore)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = { World.Folders.Loot, World.Folders.Dynamic, World.Folders.Lights, World.Folders.Signs }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	if ignore then
		table.insert(list, ignore)
	end
	params.FilterDescendantsInstances = list
	params.RespectCanCollide = true
	return params
end

local function nearSpawn(pos: Vector3): boolean
	for _, cf in World.SpawnCFrames do
		if (cf.Position - pos).Magnitude < Config.Building.NoBuildRadiusAroundSpawn then
			return true
		end
	end
	return false
end

-- returns nil or an error message
function Building.CanPlace(player: Player, def, cf: CFrame): string?
	local level = Data.Level(player)
	local perks = Progression.Perks(level)
	if def.Unlock and level < def.Unlock then
		return "Unlocks at level " .. def.Unlock
	end
	if def.Tier > 1 and def.Tier > perks.Tier then
		return Buildables.TierInfo[def.Tier].Name .. " tier is locked (level " .. ({ 1, 3, 8, 16 })[def.Tier] .. ")"
	end
	if def.Cosmetic then
		local d = Data.Get(player)
		if not d or not Cosmetics.Owns(d, level, def.Cosmetic) then
			return "Unlock this decoration in the SHOP"
		end
	end
	if (perPlayer[player.UserId] or 0) >= Config.Building.MaxStructuresPerPlayer then
		return "You've reached your structure limit"
	end
	if total >= Config.Building.MaxStructuresTotal then
		return "This store can't hold more structures"
	end
	local me = Survival.Position(player)
	if not me or (me - cf.Position).Magnitude > Config.Survival.BuildReach then
		return "Too far away"
	end
	if nearSpawn(cf.Position) then
		return "Can't build at the entrance"
	end
	-- must be inside the store and on something solid
	local plan = State.Plan
	local StoreLayout = require(Shared.StoreLayout)
	local cell = StoreLayout.CellAt(plan, cf.Position.X, cf.Position.Y - def.Size[2] / 2 + 0.5, cf.Position.Z)
	if not cell or cell.Solid then
		return "Can't build here"
	end
	local size = Vector3.new(def.Size[1], def.Size[2], def.Size[3])
	local inside = Workspace:GetPartBoundsInBox(cf, size - Vector3.new(0.3, 0.3, 0.3), overlapParams())
	for _, p in inside do
		if p.CanCollide then
			return "Something is in the way"
		end
	end
	if def.Kind == "Trap" or def.Kind == "Floor" then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { World.Folders.Loot, World.Folders.Dynamic }
	local below = Workspace:Raycast(cf.Position, Vector3.new(0, -(def.Size[2] / 2 + 1.5), 0), params)
	if not below then
		return "Needs support underneath"
	end
	return nil
end

local function setOwnerTag(model: Model, player: Player)
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("OwnerName", player.DisplayName)
end

local function updateHPAttr(s)
	s.Model:SetAttribute("HP", math.floor(s.HP))
	s.Model:SetAttribute("MaxHP", s.MaxHP)
end

local function addPrompts(s)
	local def = s.Def
	local main = s.Main
	if def.Kind == "Door" then
		local p = Prompts.Make(main, "BuildDoor", "Open", def.Name, { Distance = 9 })
		p:SetAttribute("StructureId", s.Id)
		s.Prompt = p
		local lockP = Prompts.Make(main, "BuildDoorLock", "Lock", "", { Distance = 9, Key = Enum.KeyCode.L, GamepadKey = Enum.KeyCode.ButtonY, Name = "LockPrompt" })
		lockP:SetAttribute("StructureId", s.Id)
		s.LockPrompt = lockP
	elseif def.Kind == "Storage" then
		local inv = InventoryCore.new(def.Slots or 10)
		s.ContainerId = Inventory.NewContainer("Storage", inv, s.Model, def.Name)
		local p = Prompts.Make(main, "OpenContainer", "Open", def.Name, { Distance = 9 })
		p:SetAttribute("ContainerId", s.ContainerId)
	elseif def.Kind == "Bed" then
		local p = Prompts.Make(main, "Bed", "Sleep", "Camp Bed · sets your respawn", { Distance = 8, Hold = 0.5 })
		p:SetAttribute("StructureId", s.Id)
	elseif def.Kind == "Generator" then
		require(script.Parent.Power).RegisterGenerator(s)
	elseif def.Kind == "Trap" then
		s.Charges = def.Charges
		s.ReadyAt = 0
	end
	if def.Power then
		require(script.Parent.Power).RegisterDevice(s)
	end
end

function Building.Place(player: Player, id: string, pos: Vector3, rot: number)
	local def = Buildables.Get(id)
	if not def then
		return false, "Unknown build"
	end
	if Inventory.Count(player, "Hammer") <= 0 then
		return false, "You need a Builder's Hammer"
	end
	local cf = Building.SnapCFrame(def, pos, rot)
	local err = Building.CanPlace(player, def, cf)
	if err then
		return false, err
	end
	if not Inventory.Consume(player, def.Cost) then
		return false, "Not enough materials"
	end
	local d = Data.Get(player)
	local model, main = buildVisual(def, cf, d and d.Equipped)
	nextId += 1
	local s = {
		Id = nextId,
		Def = def,
		Model = model,
		Main = main,
		HP = def.HP,
		MaxHP = def.HP,
		Owner = player.UserId,
		Open = false,
		Locked = false,
		Powered = false,
	}
	structures[s.Id] = s
	byModel[model] = s
	perPlayer[player.UserId] = (perPlayer[player.UserId] or 0) + 1
	total += 1
	model:SetAttribute("StructureId", s.Id)
	model:SetAttribute("Build", def.Id)
	model:SetAttribute("Tier", def.Tier)
	model:SetAttribute("Kind", def.Kind)
	setOwnerTag(model, player)
	updateHPAttr(s)
	addPrompts(s)
	model.Parent = World.Folders.Structures
	-- a little pop-in
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local t = p.Transparency
			p.Transparency = 0.8
			TweenService:Create(p, TweenInfo.new(0.25), { Transparency = t }):Play()
		end
	end
	Noise.Emit(cf.Position, Config.Noise.Build, player, "Build")
	State.Cue("Build", cf.Position, def.Id)
	Progress.BuildXP(player)
	Progress.Track(player, "StructuresBuilt", 1)
	Building.Placed:Fire(s)
	return true
end

--============================ DAMAGE / REPAIR ============================--
function Building.Destroy(s, silent: boolean?)
	if not structures[s.Id] then
		return
	end
	structures[s.Id] = nil
	byModel[s.Model] = nil
	perPlayer[s.Owner] = math.max(0, (perPlayer[s.Owner] or 1) - 1)
	total -= 1
	local pos = s.Model:GetPivot().Position
	if s.ContainerId then
		Inventory.RemoveContainer(s.ContainerId, pos)
	end
	Building.Destroyed:Fire(s)
	if not silent then
		State.Cue("StructureBreak", pos, s.Def.Tier)
		-- debris
		for _, p in s.Model:GetDescendants() do
			if p:IsA("BasePart") and p.Transparency < 1 then
				p.Anchored = false
				p.CanCollide = false
				p.CanQuery = false
				p.AssemblyLinearVelocity = Vector3.new(math.random(-12, 12), math.random(6, 16), math.random(-12, 12))
			end
		end
		s.Model.Parent = World.Folders.Dynamic
		game:GetService("Debris"):AddItem(s.Model, 2.5)
	else
		s.Model:Destroy()
	end
end

-- returns true if destroyed
function Building.Damage(s, amount: number, source: any?): boolean
	if not structures[s.Id] then
		return true
	end
	if s.Def.Kind == "Door" and s.Def.Power and s.Powered then
		amount *= 0.5 -- a powered blast door holds much better
	end
	s.HP -= amount
	updateHPAttr(s)
	if s.HP <= 0 then
		Building.Destroy(s)
		return true
	end
	State.Cue("StructureHit", s.Model:GetPivot().Position, s.Def.Tier)
	return false
end

local function repair(player: Player, s)
	if s.HP >= s.MaxHP then
		return false, "Already at full health"
	end
	local cost = Buildables.ScaledCost(s.Def.Id, Config.Building.RepairCostFraction)
	if not Inventory.Consume(player, cost) then
		return false, "Not enough materials to repair"
	end
	s.HP = s.MaxHP
	updateHPAttr(s)
	State.Cue("Build", s.Model:GetPivot().Position, s.Def.Id)
	return true
end

local function upgrade(player: Player, s)
	local cost, to = Buildables.UpgradeCost(s.Def.Id, Config.Building.UpgradeCostFraction)
	if not cost or not to then
		return false, "Can't be upgraded further"
	end
	local perks = Progression.Perks(Data.Level(player))
	if to.Tier > perks.Tier then
		return false, Buildables.TierInfo[to.Tier].Name .. " tier is locked"
	end
	if not Inventory.Consume(player, cost) then
		return false, "Not enough materials to upgrade"
	end
	local cf = s.Model:GetPivot()
	local wasOpen = s.Open
	local containerInv = s.ContainerId and Inventory.GetContainer(s.ContainerId)
	-- swap the visual, keep the id
	local model, main = buildVisual(to, cf)
	byModel[s.Model] = nil
	s.Model:Destroy()
	s.Def = to
	s.Model = model
	s.Main = main
	s.MaxHP = to.HP
	s.HP = to.HP
	s.Open = false
	byModel[model] = s
	model:SetAttribute("StructureId", s.Id)
	model:SetAttribute("Build", to.Id)
	model:SetAttribute("Tier", to.Tier)
	model:SetAttribute("Kind", to.Kind)
	setOwnerTag(model, Players:GetPlayerByUserId(s.Owner) or player)
	updateHPAttr(s)
	if s.ContainerId and containerInv then
		-- keep storage contents
		local p = Prompts.Make(main, "OpenContainer", "Open", to.Name, { Distance = 9 })
		p:SetAttribute("ContainerId", s.ContainerId)
		containerInv.Instance = model
	else
		addPrompts(s)
	end
	model.Parent = World.Folders.Structures
	if wasOpen then
		Building.SetDoor(s, true)
	end
	State.Cue("Build", cf.Position, to.Id)
	Progress.BuildXP(player)
	return true
end

local function remove(player: Player, s)
	if s.Owner ~= player.UserId then
		return false, "Only " .. tostring(s.Model:GetAttribute("OwnerName")) .. " can remove this"
	end
	local refund = Buildables.ScaledCost(s.Def.Id, Config.Building.RefundOnRemove)
	for item, n in refund do
		local added = Inventory.Give(player, item, n)
		if added < n then
			require(script.Parent.Loot).Drop(s.Model:GetPivot().Position, item, n - added)
		end
	end
	Building.Destroy(s, true)
	return true
end

--============================ DOORS / BEDS ============================--
function Building.SetDoor(s, open: boolean)
	if s.Def.Kind ~= "Door" then
		return
	end
	local leaf = s.Model:FindFirstChild("Leaf") :: BasePart?
	if not leaf then
		return
	end
	s.Open = open
	local closed = leaf:GetAttribute("ClosedCF") :: CFrame
	local size = leaf.Size
	local hinge = closed * CFrame.new(-size.X / 2, 0, 0)
	local target = if open then hinge * CFrame.Angles(0, math.rad(-95), 0) * CFrame.new(size.X / 2, 0, 0) else closed
	TweenService:Create(leaf, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { CFrame = target }):Play()
	leaf.CanCollide = not open
	if s.Prompt then
		s.Prompt.ActionText = if open then "Close" else "Open"
	end
	s.Model:SetAttribute("Open", open)
	Noise.Emit(s.Model:GetPivot().Position, Config.Noise.DoorOpen, nil, "Door")
end

function Building.SetLocked(s, locked: boolean)
	s.Locked = locked
	if locked and s.Open then
		Building.SetDoor(s, false)
	end
	if s.LockPrompt then
		s.LockPrompt.ActionText = if locked then "Unlock" else "Lock"
	end
	s.Model:SetAttribute("Locked", locked)
	local mod = s.Main:FindFirstChild("LocustCost")
	if mod then
		mod.Label = Building.ModifierLabel(s.Def, locked)
	end
end

--============================ REMOTES ============================--
local function reply(player, ok, msg)
	if not ok and msg then
		State.Notify(player, msg, "Warn")
	end
end

function Building.Init()
	Net.Event("Build").OnServerEvent:Connect(function(player, req)
		if not buildLimiter:Allow(player) or type(req) ~= "table" then
			return
		end
		if not Survival.IsActive(player) or player:GetAttribute("Infected") then
			return
		end
		if req.Action == "Place" then
			if type(req.Id) ~= "string" or typeof(req.Position) ~= "Vector3" or type(req.Rotation) ~= "number" then
				return
			end
			if req.Position.Magnitude > 5000 or req.Position ~= req.Position then
				return
			end
			reply(player, Building.Place(player, req.Id, req.Position, req.Rotation))
			return
		end
		local s = type(req.Target) == "number" and structures[req.Target]
		if not s then
			return
		end
		local me = Survival.Position(player)
		if not me or (me - s.Model:GetPivot().Position).Magnitude > Config.Survival.BuildReach + 4 then
			reply(player, false, "Too far away")
			return
		end
		if Inventory.Count(player, "Hammer") <= 0 then
			reply(player, false, "You need a Builder's Hammer")
			return
		end
		if req.Action == "Repair" then
			reply(player, repair(player, s))
		elseif req.Action == "Upgrade" then
			reply(player, upgrade(player, s))
		elseif req.Action == "Remove" then
			reply(player, remove(player, s))
		end
	end)

	Prompts.Register("BuildDoor", function(player, prompt)
		local s = structures[prompt:GetAttribute("StructureId")]
		if not s then
			return
		end
		if s.Locked and s.Owner ~= player.UserId and not s.Open then
			-- teammates can still open: locks only stop the Locust
		end
		Building.SetDoor(s, not s.Open)
	end)
	Prompts.Register("BuildDoorLock", function(player, prompt)
		local s = structures[prompt:GetAttribute("StructureId")]
		if s then
			Building.SetLocked(s, not s.Locked)
			State.Notify(player, if s.Locked then "Door locked: the Locust has to break it." else "Door unlocked: the Locust can open it from night 2.", "Info")
		end
	end)
	Prompts.Register("Bed", function(player, prompt)
		local s = structures[prompt:GetAttribute("StructureId")]
		if not s then
			return
		end
		Survival.SetBed(player, s.Model)
		if State.Phase == "Day" then
			Survival.SetSleeping(player, s.Model)
			State.Notify(player, "Resting... your energy refills. Respawn point set.", "Good")
			task.delay(8, function()
				Survival.SetSleeping(player, nil)
			end)
		else
			State.Notify(player, "Respawn point set. Too dangerous to sleep at night.", "Info")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		-- structures stay for teammates
	end)
end

function Building.ClearAll()
	for _, s in structures do
		Building.Destroy(s, true)
	end
	table.clear(structures)
	table.clear(byModel)
	table.clear(perPlayer)
	total = 0
end

-- structures within radius (for the Locust's base search and turret targeting)
function Building.Near(pos: Vector3, radius: number)
	local out = {}
	for _, s in structures do
		if (s.Model:GetPivot().Position - pos).Magnitude <= radius then
			table.insert(out, s)
		end
	end
	return out
end

return Building
