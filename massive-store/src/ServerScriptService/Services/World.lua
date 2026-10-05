--[[
	World: builds MASSIVE STORE into the Workspace from a StoreLayout plan and owns the
	interactive map pieces (store doors, room doors, hidden panels, gates, hiding spots,
	store generators, lights).

	Workspace.Store
	  Shell      floors, ceiling, walls
	  Props      shelves, products, furniture (anchored, no physics)
	  Lights     ceiling fixtures (tag "StoreLight"; clients switch / flicker them)
	  Signs      department signs
	  Doors      store doors, room doors, hidden panels, gates
	  Hiding     hiding spots (prompts)
	  Generators store backup generators
	  Loot       world items (Loot service)
	  Structures player builds (Building service)
	  Carts      shopping carts (Carts service)
	  Dynamic    flares, crates, effects
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Zones)
local StoreLayout = require(Shared.StoreLayout)

local Prompts = require(script.Parent.Prompts)

local World = {
	Plan = nil,
	Store = nil,
	Folders = {},
	StoreDoors = {},
	RoomDoors = {},
	Panels = {},
	Gates = {},
	HideSpots = {},
	StoreGenerators = {},
	SpawnCFrames = {},
}

local MATERIALS = {}
local function mat(name: string?): Enum.Material
	if not name then
		return Enum.Material.SmoothPlastic
	end
	local m = MATERIALS[name]
	if m == nil then
		local ok, v = pcall(function()
			return (Enum.Material :: any)[name]
		end)
		m = if ok and v then v else Enum.Material.SmoothPlastic
		MATERIALS[name] = m
	end
	return m
end

local COLORS = {}
local function col(hex: string?): Color3
	hex = hex or "cccccc"
	local c = COLORS[hex]
	if not c then
		c = Color3.fromHex(hex)
		COLORS[hex] = c
	end
	return c
end

local built = 0
local function tick()
	built += 1
	if built % 1500 == 0 then
		task.wait()
	end
end

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	local maxDim = math.max(size.X, size.Y, size.Z)
	if maxDim < 3 then
		p.CastShadow = false
	end
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	tick()
	return p
end
World.Part = part

local function surfaceText(p: BasePart, face: Enum.NormalId, text: string, sub: string?, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0.3
	gui.MaxDistance = 160
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(0.94, if sub then 0.62 else 0.84)
	t.Position = UDim2.fromScale(0.03, if sub then 0.06 else 0.08)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.Text = text
	t.TextColor3 = color
	t.Parent = frame
	if sub then
		local s = Instance.new("TextLabel")
		s.BackgroundTransparency = 1
		s.Size = UDim2.fromScale(0.9, 0.24)
		s.Position = UDim2.fromScale(0.05, 0.7)
		s.Font = Enum.Font.GothamBold
		s.TextScaled = true
		s.Text = sub
		s.TextColor3 = Color3.fromRGB(230, 230, 230)
		s.Parent = frame
	end
	gui.Parent = p
	return gui
end
World.SurfaceText = surfaceText

--============================ SHELL ============================--
local function buildShell(plan, shell: Instance)
	local S, H = plan.CellSize, plan.WallHeight
	local wallMain, wallBase = col("d8d2c4"), col("8f8b83")
	local trim = col("3b3f45")
	for _, cell in plan.CellList do
		local zinfo = Zones.Types[cell.Type] or Zones.Types.Solid
		local floorColor = col(zinfo.Floor)
		local floorMat = if cell.Level == 0 then Enum.Material.SmoothPlastic else Enum.Material.Concrete
		if cell.Type == "Garden" then
			floorMat = Enum.Material.Slate
		end
		local y = cell.Y - 0.5
		if cell.Stair then
			local strip = (S - plan.LaneWidth) / 2
			for _, sz in { -1, 1 } do
				part(shell, Vector3.new(S, 1, strip), CFrame.new(cell.X, y, cell.Z + sz * (plan.LaneWidth / 2 + strip / 2)), floorColor, floorMat)
			end
		else
			part(shell, Vector3.new(S, 1, S), CFrame.new(cell.X, y, cell.Z), floorColor, floorMat, { Name = "Floor" })
		end
	end
	-- ceiling strips over the main floor
	local width = plan.Cols * S
	for r = 1, plan.Rows do
		local z = plan.OriginZ + (r - 0.5) * S
		part(shell, Vector3.new(width, 1, S), CFrame.new(plan.OriginX + width / 2, H + 0.5, z), col("2c2d30"), Enum.Material.Concrete, { CastShadow = true, Name = "Ceiling" })
	end

	-- walls
	local T = 1
	local OW, OH = 16, 16
	for _, w in plan.Walls do
		local isBase = w.Level ~= 0
		local c = if isBase then wallBase else wallMain
		local m = if isBase then Enum.Material.Concrete else Enum.Material.SmoothPlastic
		local yaw = if w.Dir == "EW" then 90 else 0 -- wall length runs along local X
		local base = CFrame.new(w.X, w.Y, w.Z) * CFrame.Angles(0, math.rad(yaw), 0)
		local L = w.Length
		if w.Opening then
			local seg = (L - OW) / 2
			for _, s in { -1, 1 } do
				part(shell, Vector3.new(seg, w.H, T), base * CFrame.new(s * (OW / 2 + seg / 2), w.H / 2, 0), c, m)
				-- dark base trim
				part(shell, Vector3.new(seg, 0.8, T + 0.15), base * CFrame.new(s * (OW / 2 + seg / 2), 0.4, 0), trim, Enum.Material.SmoothPlastic, { CanQuery = false })
			end
			part(shell, Vector3.new(OW, w.H - OH, T), base * CFrame.new(0, OH + (w.H - OH) / 2, 0), c, m)
			-- door frame
			part(shell, Vector3.new(OW + 1, 0.8, T + 0.4), base * CFrame.new(0, OH + 0.4, 0), trim, Enum.Material.Metal, { CanQuery = false })
		else
			part(shell, Vector3.new(L + (if w.Perimeter then T else 0), w.H, T), base * CFrame.new(0, w.H / 2, 0), c, m)
			part(shell, Vector3.new(L, 0.8, T + 0.15), base * CFrame.new(0, 0.4, 0), trim, Enum.Material.SmoothPlastic, { CanQuery = false })
			if w.Feature == "Storefront" then
				-- big dark windows, boarded up
				for i = -1, 1 do
					part(shell, Vector3.new(18, 12, 0.3), base * CFrame.new(i * 24, 8, 0.7), col("0d1117"), Enum.Material.Glass, { Transparency = 0.15, Reflectance = 0.25, CanQuery = false })
					for k = 0, 2 do
						part(shell, Vector3.new(20, 1.2, 0.4), base * CFrame.new(i * 24, 4 + k * 4, 1) * CFrame.Angles(0, 0, math.rad((k % 2 * 2 - 1) * 8)), col("a1795a"), Enum.Material.WoodPlanks, { CanQuery = false })
					end
				end
			elseif w.Feature == "DockDoors" then
				for _, x in { -18, 18 } do
					part(shell, Vector3.new(16, 15, 0.4), base * CFrame.new(x, 7.5, 0.7), col("7d858d"), Enum.Material.CorrodedMetal, { CanQuery = false })
					part(shell, Vector3.new(17, 1, 0.8), base * CFrame.new(x, 15.4, 0.8), col("ffc61a"), Enum.Material.SmoothPlastic, { CanQuery = false })
					part(shell, Vector3.new(1.2, 4, 1.4), base * CFrame.new(x - 8.8, 2, 1.1), col("212121"), Enum.Material.Rubber, { CanQuery = false })
					part(shell, Vector3.new(1.2, 4, 1.4), base * CFrame.new(x + 8.8, 2, 1.1), col("212121"), Enum.Material.Rubber, { CanQuery = false })
				end
			elseif w.Feature == "GarageExit" then
				part(shell, Vector3.new(30, 14, 0.4), base * CFrame.new(0, 7, 0.7), col("5f646b"), Enum.Material.CorrodedMetal, { CanQuery = false })
				local sign = part(shell, Vector3.new(8, 2.5, 0.3), base * CFrame.new(0, 16, 0.8), col("1b5e20"), Enum.Material.SmoothPlastic, { CanQuery = false })
				surfaceText(sign, Enum.NormalId.Front, "EXIT", nil, col("ffffff"))
				surfaceText(sign, Enum.NormalId.Back, "EXIT", nil, col("ffffff"))
			end
		end
	end
end

--============================ PROPS ============================--
local function buildProps(plan, folder: Instance)
	for _, p in plan.Props do
		local cf = CFrame.new(p.X, p.Y, p.Z) * CFrame.Angles(0, math.rad(p.Yaw or 0), 0)
		if p.Pitch or p.Roll then
			cf *= CFrame.Angles(math.rad(p.Pitch or 0), 0, math.rad(p.Roll or 0))
		end
		local size
		local shape = nil
		if p.K == "Cyl" then
			-- cylinder axis is X; stand it up
			size = Vector3.new(p.H, p.W, p.D)
			cf *= CFrame.Angles(0, 0, math.rad(90))
			shape = Enum.PartType.Cylinder
		elseif p.K == "CylH" then
			size = Vector3.new(p.W, p.H, p.D)
			shape = Enum.PartType.Cylinder
		elseif p.K == "Ball" then
			size = Vector3.new(p.W, p.W, p.W)
			shape = Enum.PartType.Ball
		else
			size = Vector3.new(p.W, p.H, p.D)
		end
		local pt = part(folder, size, cf, col(p.C), mat(p.M))
		if shape then
			pt.Shape = shape
		end
		if p.Tr then
			pt.Transparency = p.Tr
		end
		if p.Refl then
			pt.Reflectance = p.Refl
		end
		if p.NC then
			pt.CanCollide = false
			pt.CanQuery = false
		end
		if p.N then
			pt.Name = p.N
		end
		if p.Face then
			pt:SetAttribute("Face", p.Face)
		end
		if math.max(size.X, size.Z) < 2.5 and size.Y < 2.5 then
			pt.CanQuery = false -- small products: skip raycasts
		end
		if p.Tag then
			CollectionService:AddTag(pt, p.Tag)
			local here = StoreLayout.CellAt(plan, p.X, p.Y, p.Z)
			pt:SetAttribute("Zone", if here then here.Zone else 0)
			pt:SetAttribute("BaseColor", pt.Color)
		end
	end
end

--============================ LIGHTS ============================--
local function buildLights(plan, folder: Instance)
	for i, l in plan.Lights do
		local color = col(l.Color or "fff4e0")
		local fixture
		if l.Kind == "Cage" then
			fixture = part(folder, Vector3.new(1.2, 1.2, 1.2), CFrame.new(l.X, l.Y, l.Z), color, Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false, CanQuery = false, CastShadow = false })
			local pl = Instance.new("PointLight")
			pl.Range = l.Range or 24
			pl.Brightness = 1.2
			pl.Color = color
			pl.Shadows = false
			pl.Parent = fixture
		else
			local size = if l.Kind == "Room" then Vector3.new(4, 0.3, 1.5) else Vector3.new(10, 0.35, 2)
			fixture = part(folder, size, CFrame.new(l.X, l.Y, l.Z), color, Enum.Material.Neon, { CanCollide = false, CanQuery = false, CastShadow = false })
			local housing = part(folder, size + Vector3.new(0.4, 0.2, 0.4), CFrame.new(l.X, l.Y + 0.25, l.Z), col("9ea3a8"), Enum.Material.Metal, { CanCollide = false, CanQuery = false, CastShadow = false })
			housing.Name = "Housing"
			local sl = Instance.new("SurfaceLight")
			sl.Face = Enum.NormalId.Bottom
			sl.Angle = 120
			sl.Range = l.Range or 30
			sl.Brightness = if l.Kind == "Room" then 1 else 1.25
			sl.Color = color
			sl.Shadows = false
			sl.Parent = fixture
		end
		fixture.Name = "Light"
		fixture:SetAttribute("Zone", l.Zone)
		fixture:SetAttribute("Emergency", l.Emergency == true)
		fixture:SetAttribute("BaseColor", color)
		fixture:SetAttribute("Seed", i % 97)
		CollectionService:AddTag(fixture, "StoreLight")
	end
end

--============================ SIGNS ============================--
local function buildSigns(plan, folder: Instance)
	for _, s in plan.Signs do
		local depth = 0.4
		local cf = CFrame.new(s.X, s.Y, s.Z) * CFrame.Angles(0, math.rad(s.Yaw or 0), 0)
		local accent = col(s.Color)
		local board = part(folder, Vector3.new(s.W, s.H, depth), cf, col("15171a"), Enum.Material.SmoothPlastic, { CanCollide = false, CastShadow = false })
		board.Name = "Sign"
		local edge = part(folder, Vector3.new(s.W, 0.25, depth + 0.1), cf * CFrame.new(0, -s.H / 2 - 0.1, 0), accent, Enum.Material.Neon, { CanCollide = false, CanQuery = false, CastShadow = false })
		edge:SetAttribute("BaseColor", accent)
		local here = StoreLayout.CellAt(plan, s.X, s.Y, s.Z)
		edge:SetAttribute("Zone", here and here.Zone or 0)
		CollectionService:AddTag(edge, "StoreNeon")
		if s.Kind ~= "Small" then
			for _, x in { -s.W / 2 + 0.6, s.W / 2 - 0.6 } do
				part(folder, Vector3.new(0.1, 6, 0.1), cf * CFrame.new(x, s.H / 2 + 3, 0), col("444444"), Enum.Material.Metal, { CanCollide = false, CanQuery = false, CastShadow = false })
			end
		end
		surfaceText(board, Enum.NormalId.Front, s.Text, s.Sub, accent)
		surfaceText(board, Enum.NormalId.Back, s.Text, s.Sub, accent)
	end
end

--============================ DOORS & GATES ============================--
local function doorPrompt(parent, action, text, object, id, extra)
	local p = Prompts.Make(parent, action, text, object, extra)
	p:SetAttribute("Id", id)
	return p
end

local function buildStoreDoors(plan, folder: Instance)
	for _, d in plan.StoreDoors do
		local yaw = if d.Dir == "EW" then 90 else 0
		local base = CFrame.new(d.X, d.Y, d.Z) * CFrame.Angles(0, math.rad(yaw), 0)
		local model = Instance.new("Model")
		model.Name = "StoreDoor" .. d.Id
		local leaves = {}
		for _, side in { -1, 1 } do
			local hinge = base * CFrame.new(side * 8, 0, 0)
			local closed = hinge * CFrame.new(-side * 4, 7.5, 0)
			local leaf = part(model, Vector3.new(7.9, 15, 0.5), closed, col(if d.Staff then "8d6e63" else "b0bec5"), if d.Staff then Enum.Material.Wood else Enum.Material.Metal)
			leaf.Name = "Leaf"
			local mod = Instance.new("PathfindingModifier")
			mod.Label = "MapDoor"
			mod.PassThrough = true
			mod.Parent = leaf
			local window = part(model, Vector3.new(3, 4, 0.55), closed * CFrame.new(0, 2.5, 0), col("1b2430"), Enum.Material.Glass, { Transparency = 0.3, CanCollide = false, CanQuery = false })
			window.Name = "Window"
			table.insert(leaves, { Leaf = leaf, Window = window, Hinge = hinge, Side = side })
		end
		if d.Staff then
			local sign = part(model, Vector3.new(5, 1.2, 0.2), base * CFrame.new(0, 17.2, 0), col("ffc61a"), Enum.Material.SmoothPlastic, { CanCollide = false, CanQuery = false })
			surfaceText(sign, Enum.NormalId.Front, "STAFF ONLY", nil, col("101010"))
			surfaceText(sign, Enum.NormalId.Back, "STAFF ONLY", nil, col("101010"))
		end
		local hit = part(model, Vector3.new(2, 2, 2), base * CFrame.new(0, 4, 0), col("ffffff"), Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
		hit.Name = "PromptAnchor"
		local prompt = doorPrompt(hit, "StoreDoor", "Open", "Door", d.Id, { Distance = 10 })
		model.Parent = folder
		World.StoreDoors[d.Id] = { Id = d.Id, Model = model, Leaves = leaves, Open = false, Locked = false, Prompt = prompt, Position = base.Position, Data = d }
	end
end

local function setLeaves(door, open: boolean)
	for _, l in door.Leaves do
		local angle = if open then math.rad(l.Side * 95) else 0
		local target = l.Hinge * CFrame.Angles(0, angle, 0) * CFrame.new(-l.Side * 4, 7.5, 0)
		TweenService:Create(l.Leaf, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { CFrame = target }):Play()
		TweenService:Create(l.Window, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { CFrame = target * CFrame.new(0, 2.5, 0) }):Play()
		l.Leaf.CanCollide = not open
	end
end

function World.SetStoreDoor(id: number, open: boolean)
	local door = World.StoreDoors[id]
	if not door or door.Open == open then
		return false
	end
	if open and door.Locked then
		return false
	end
	door.Open = open
	setLeaves(door, open)
	door.Prompt.ActionText = if open then "Close" else "Open"
	door.Model:SetAttribute("Open", open)
	return true
end

function World.LockStoreDoor(id: number, locked: boolean)
	local door = World.StoreDoors[id]
	if not door then
		return
	end
	door.Locked = locked
	if locked then
		World.SetStoreDoor(id, false)
		door.Locked = true
		door.Prompt.ActionText = "LOCKDOWN"
		door.Prompt.Enabled = false
	else
		door.Prompt.Enabled = true
		door.Prompt.ActionText = if door.Open then "Close" else "Open"
	end
	door.Model:SetAttribute("Locked", locked)
	for _, l in door.Leaves do
		local mod = l.Leaf:FindFirstChildOfClass("PathfindingModifier")
		if mod then
			mod.PassThrough = not locked
		end
		l.Leaf.Color = if locked then col("b71c1c") else col(if door.Data.Staff then "8d6e63" else "b0bec5")
	end
end

local function buildRoomDoors(plan, folder: Instance)
	for _, d in plan.RoomDoors do
		local base = CFrame.new(d.X, d.Y, d.Z) * CFrame.Angles(0, math.rad(d.Yaw), 0)
		local hinge = base * CFrame.new(-d.W / 2, 0, 0)
		local closed = hinge * CFrame.new(d.W / 2, d.H / 2, 0)
		local color = if d.Lock == "Keycard" then col("455a64") elseif d.Lock then col("6d4c41") else col("8d8a83")
		local leaf = part(folder, Vector3.new(d.W - 0.1, d.H, 0.4), closed, color, if d.Lock == "Keycard" then Enum.Material.DiamondPlate else Enum.Material.Wood)
		leaf.Name = "RoomDoor" .. d.Id
		local mod = Instance.new("PathfindingModifier")
		mod.Label = "MapDoor"
		mod.PassThrough = d.Lock == nil
		mod.Parent = leaf
		local text = "Open"
		local object = "Door"
		local led = nil
		if d.Lock == "Crowbar" then
			text, object = "Pry open", "Locked · needs Crowbar"
		elseif d.Lock == "Keycard" then
			text, object = "Swipe Keycard", "Security door"
			local pad = part(folder, Vector3.new(0.6, 0.9, 0.3), base * CFrame.new(d.W / 2 + 0.8, 4.5, 0.5), col("212121"), Enum.Material.SmoothPlastic, { CanCollide = false })
			led = part(folder, Vector3.new(0.3, 0.15, 0.1), base * CFrame.new(d.W / 2 + 0.8, 4.8, 0.7), col("ff1744"), Enum.Material.Neon, { CanCollide = false, CanQuery = false })
			led.Name = "Led"
			pad.Name = "Keypad"
		end
		local prompt = doorPrompt(leaf, "RoomDoor", text, object, d.Id, { Hold = if d.Lock == "Crowbar" then 2.5 else 0, Distance = 8 })
		World.RoomDoors[d.Id] = { Id = d.Id, Leaf = leaf, Led = led, Hinge = hinge, Data = d, Lock = d.Lock, Open = false, Prompt = prompt, Position = base.Position, BaseLock = d.Lock }
	end
end

function World.SetRoomDoor(id: number, open: boolean)
	local door = World.RoomDoors[id]
	if not door or door.Lock then
		return false
	end
	if door.Open == open then
		return false
	end
	door.Open = open
	local d = door.Data
	local target = door.Hinge * CFrame.Angles(0, if open then math.rad(-100) else 0, 0) * CFrame.new(d.W / 2, d.H / 2, 0)
	TweenService:Create(door.Leaf, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { CFrame = target }):Play()
	door.Leaf.CanCollide = not open
	door.Prompt.ActionText = if open then "Close" else "Open"
	door.Prompt.ObjectText = "Door"
	door.Prompt.HoldDuration = 0
	return true
end

function World.UnlockRoomDoor(id: number)
	local door = World.RoomDoors[id]
	if not door then
		return
	end
	door.Lock = nil
	local mod = door.Leaf:FindFirstChildOfClass("PathfindingModifier")
	if mod then
		mod.PassThrough = true
	end
	if door.Led then
		door.Led.Color = col("00e676")
	end
	World.SetRoomDoor(id, true)
end

local function buildPanels(plan, folder: Instance)
	for _, p in plan.Panels do
		local cf = CFrame.new(p.X, p.Y + p.H / 2, p.Z) * CFrame.Angles(0, math.rad(p.Yaw), 0)
		local panel = part(folder, Vector3.new(p.W, p.H, 1.0), cf, col(p.Color):Lerp(Color3.new(1, 1, 1), 0.08), Enum.Material.Concrete)
		panel.Name = "LoosePanel" .. p.Id
		-- subtle cracks hint that something is behind it
		for k = -1, 1, 2 do
			part(folder, Vector3.new(0.12, p.H * 0.7, 1.05), cf * CFrame.new(k * 1.6, 0, 0) * CFrame.Angles(0, 0, math.rad(k * 9)), col("4a4741"), Enum.Material.Concrete, { CanCollide = false, CanQuery = false })
		end
		local prompt = doorPrompt(panel, "Panel", "Pry open", "Loose wall panel · needs Crowbar", p.Id, { Hold = 3, Distance = 8 })
		World.Panels[p.Id] = { Id = p.Id, Part = panel, Open = false, Prompt = prompt, CFrame = cf, Data = p }
	end
end

function World.OpenPanel(id: number)
	local panel = World.Panels[id]
	if not panel or panel.Open then
		return false
	end
	panel.Open = true
	panel.Prompt.Enabled = false
	panel.Part.CanCollide = false
	TweenService:Create(panel.Part, TweenInfo.new(0.8, Enum.EasingStyle.Quad), { CFrame = panel.CFrame * CFrame.new(0, -0.5, 3) * CFrame.Angles(math.rad(80), 0, 0), Transparency = 0.2 }):Play()
	return true
end

local function buildGates(plan, folder: Instance)
	for id, g in plan.Gates do
		local yaw = if g.Dir == "EW" then 90 else 0
		local base = CFrame.new(g.X, g.Y, g.Z) * CFrame.Angles(0, math.rad(yaw), 0)
		local model = Instance.new("Model")
		model.Name = "Gate_" .. id
		local shutter = part(model, Vector3.new(16, 16, 0.6), base * CFrame.new(0, 8, 0), col("6b7178"), Enum.Material.CorrodedMetal)
		shutter.Name = "Shutter"
		for k = 0, 3 do
			part(model, Vector3.new(16.1, 0.5, 0.7), base * CFrame.new(0, 2 + k * 4, 0), col(if k % 2 == 0 then "ffc61a" else "1b1b1b"), Enum.Material.SmoothPlastic, { CanCollide = false, CanQuery = false })
		end
		local sign = part(model, Vector3.new(9, 2.2, 0.2), base * CFrame.new(0, 12, 0.5), col("b71c1c"), Enum.Material.SmoothPlastic, { CanCollide = false, CanQuery = false })
		local title = if g.Kind == "Basement" then "B1 SEALED" else "SEALED WING"
		local sub = if g.Kind == "Basement" then "KEYCARD OR NIGHT 10" else "OPENS ON NIGHT 20"
		surfaceText(sign, Enum.NormalId.Front, title, sub, col("ffffff"))
		local sign2 = part(model, Vector3.new(9, 2.2, 0.2), base * CFrame.new(0, 12, -0.5), col("b71c1c"), Enum.Material.SmoothPlastic, { CanCollide = false, CanQuery = false })
		surfaceText(sign2, Enum.NormalId.Back, title, sub, col("ffffff"))
		local prompt = nil
		if g.Keycard then
			prompt = doorPrompt(shutter, "Gate", "Swipe Keycard", "Basement shutter", id, { Distance = 10 })
		end
		model.Parent = folder
		World.Gates[id] = { Id = id, Model = model, Shutter = shutter, Open = false, Prompt = prompt, Base = base, Data = g }
	end
end

function World.SetGate(id: string, open: boolean)
	local gate = World.Gates[id]
	if not gate or gate.Open == open then
		return false
	end
	gate.Open = open
	for _, p in gate.Model:GetDescendants() do
		if p:IsA("BasePart") then
			local target = p.CFrame + Vector3.new(0, if open then 15.5 else -15.5, 0)
			TweenService:Create(p, TweenInfo.new(if open then 3 else 1, Enum.EasingStyle.Quad), { CFrame = target }):Play()
			if p.Name == "Shutter" then
				p.CanCollide = not open
			end
		end
	end
	if gate.Prompt then
		gate.Prompt.Enabled = not open
	end
	game:GetService("ReplicatedStorage"):SetAttribute("Gate_" .. id, open)
	return true
end

--============================ HIDING SPOTS ============================--
local HIDE_NAMES = {
	Locker = "Locker",
	Stall = "Restroom stall",
	Counter = "Under the counter",
	Wardrobe = "Wardrobe",
	FittingRoom = "Fitting room",
	Shed = "Tool shed",
	Vent = "Maintenance vent",
}

local function buildHiding(plan, folder: Instance)
	for _, h in plan.HidingSpots do
		local cf = CFrame.new(h.X, h.Y, h.Z) * CFrame.Angles(0, math.rad(h.Yaw), 0)
		local anchor = part(folder, Vector3.new(1, 1, 1), cf, col("ffffff"), Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
		anchor.Name = "Hide" .. h.Id
		anchor:SetAttribute("Kind", h.Kind)
		local prompt = doorPrompt(anchor, "Hide", "Hide", HIDE_NAMES[h.Kind] or "Hiding spot", h.Id, { Distance = 7, Hold = 0.3 })
		World.HideSpots[h.Id] = { Id = h.Id, Part = anchor, CFrame = cf, Kind = h.Kind, Occupant = nil, Prompt = prompt, Cell = h.Cell }
	end
end

--============================ STORE GENERATORS ============================--
local function buildGenerators(plan, folder: Instance)
	for _, g in plan.GeneratorSpots do
		local cf = CFrame.new(g.X, g.Y, g.Z) * CFrame.Angles(0, math.rad(g.Yaw or 0), 0)
		local model = Instance.new("Model")
		model.Name = "BackupGenerator" .. g.Id
		local body = part(model, Vector3.new(8, 5, 5), cf * CFrame.new(0, 2.5, 0), col("f9a825"), Enum.Material.Metal)
		body.Name = "Body"
		part(model, Vector3.new(8.4, 0.6, 5.4), cf * CFrame.new(0, 0.3, 0), col("37474f"), Enum.Material.Metal)
		part(model, Vector3.new(2, 1.6, 0.3), cf * CFrame.new(-2, 3.5, -2.6), col("212121"), Enum.Material.SmoothPlastic, { CanCollide = false })
		local lamp = part(model, Vector3.new(0.5, 0.5, 0.3), cf * CFrame.new(2.5, 4, -2.6), col("ff1744"), Enum.Material.Neon, { CanCollide = false, CanQuery = false })
		lamp.Name = "StatusLamp"
		part(model, Vector3.new(0.8, 3, 0.8), cf * CFrame.new(3, 6, 1.5), col("424242"), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = false })
		local sign = part(model, Vector3.new(6, 1.2, 0.2), cf * CFrame.new(0, 7.5, 0), col("101010"), Enum.Material.SmoothPlastic, { CanCollide = false, CanQuery = false })
		surfaceText(sign, Enum.NormalId.Front, "BACKUP POWER", nil, col("ffc61a"))
		surfaceText(sign, Enum.NormalId.Back, "BACKUP POWER", nil, col("ffc61a"))
		model.PrimaryPart = body
		model:SetAttribute("Store", true)
		model.Parent = folder
		World.StoreGenerators[g.Id] = { Id = g.Id, Model = model, Body = body, Lamp = lamp, Spot = g, Position = cf.Position }
	end
end

--============================ BUILD ============================--
function World.Build(plan)
	World.Plan = plan
	local t0 = os.clock()
	local store = Instance.new("Model")
	store.Name = "Store"
	store.ModelStreamingMode = Enum.ModelStreamingMode.Nonatomic
	local function folder(name)
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = store
		World.Folders[name] = f
		return f
	end
	local shell = folder("Shell")
	local props = folder("Props")
	local lights = folder("Lights")
	local signs = folder("Signs")
	local doors = folder("Doors")
	local hiding = folder("Hiding")
	local gens = folder("Generators")
	folder("Loot")
	folder("Structures")
	folder("Carts")
	folder("Dynamic")

	buildShell(plan, shell)
	buildProps(plan, props)
	buildLights(plan, lights)
	buildSigns(plan, signs)
	buildStoreDoors(plan, doors)
	buildRoomDoors(plan, doors)
	buildPanels(plan, doors)
	buildGates(plan, doors)
	buildHiding(plan, hiding)
	buildGenerators(plan, gens)

	for _, sp in plan.SpawnPoints do
		table.insert(World.SpawnCFrames, CFrame.new(sp.X, sp.Y + 4, sp.Z) * CFrame.Angles(0, math.rad(180), 0))
	end

	store.Parent = Workspace
	World.Store = store
	print(("[World] store built: %d parts in %.1fs"):format(built, os.clock() - t0))
	return store
end

-- the store shift: some opened locked rooms are closed and locked again (with new stock inside)
function World.RelockRooms(max: number)
	local opened = {}
	for _, door in World.RoomDoors do
		if door.BaseLock and not door.Lock then
			table.insert(opened, door)
		end
	end
	for i = 1, math.min(max, #opened) do
		local door = table.remove(opened, math.random(1, #opened))
		door.Lock = nil
		World.SetRoomDoor(door.Id, false)
		door.Lock = door.BaseLock
		local mod = door.Leaf:FindFirstChildOfClass("PathfindingModifier")
		if mod then
			mod.PassThrough = false
		end
		door.Prompt.ActionText = if door.Lock == "Crowbar" then "Pry open" else "Swipe Keycard"
		door.Prompt.ObjectText = if door.Lock == "Crowbar" then "Locked · needs Crowbar" else "Security door"
		door.Prompt.HoldDuration = if door.Lock == "Crowbar" then 2.5 else 0
		if door.Led then
			door.Led.Color = col("ff1744")
		end
	end
end

-- reset doors/gates/rooms for a new run (the building itself stays)
function World.ResetRun()
	for id in World.Gates do
		World.SetGate(id, false)
	end
	for id, door in World.StoreDoors do
		World.LockStoreDoor(id, false)
		World.SetStoreDoor(id, false)
	end
	for _, door in World.RoomDoors do
		if door.BaseLock then
			door.Lock = nil
			World.SetRoomDoor(door.Id, false)
			door.Lock = door.BaseLock
			local mod = door.Leaf:FindFirstChildOfClass("PathfindingModifier")
			if mod then
				mod.PassThrough = false
			end
			door.Prompt.ActionText = if door.Lock == "Crowbar" then "Pry open" else "Swipe Keycard"
			door.Prompt.ObjectText = if door.Lock == "Crowbar" then "Locked · needs Crowbar" else "Security door"
			door.Prompt.HoldDuration = if door.Lock == "Crowbar" then 2.5 else 0
			if door.Led then
				door.Led.Color = col("ff1744")
			end
		else
			World.SetRoomDoor(door.Id, false)
		end
	end
	for _, panel in World.Panels do
		if panel.Open then
			panel.Open = false
			panel.Part.CFrame = panel.CFrame
			panel.Part.Transparency = 0
			panel.Part.CanCollide = true
			panel.Prompt.Enabled = true
		end
	end
	for _, f in { "Loot", "Structures", "Dynamic" } do
		World.Folders[f]:ClearAllChildren()
	end
end

-- random spawn CFrame at the entrance
function World.SpawnCFrame(): CFrame
	local list = World.SpawnCFrames
	return list[math.random(1, #list)]
end

return World
