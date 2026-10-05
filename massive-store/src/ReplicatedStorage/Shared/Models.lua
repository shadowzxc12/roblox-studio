--[[
	Models: procedural 3D models for items (loot / held in hand) and shopping carts.
	Built from simple parts so the game needs no uploaded meshes.
]]

local Items = require(script.Parent.Items)

local Models = {}

local function newPart(props)
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function weldTo(root: BasePart, p: BasePart, offset: CFrame)
	p.CFrame = root.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = p
	w.Parent = p
	p.Parent = root.Parent
end

--[[
	Item model. The returned Model's PrimaryPart is "Handle" (centre of the item, unanchored).
	The item sits with its bottom at the Handle's position minus Size.Y/2.
]]
function Models.Item(itemId: string): Model
	local item = Items.Get(itemId)
	local model = Instance.new("Model")
	model.Name = itemId
	if not item then
		local h = newPart({ Name = "Handle", Size = Vector3.new(1, 1, 1), Color = Color3.new(1, 0, 1) })
		h.Parent = model
		model.PrimaryPart = h
		return model
	end
	local size = Vector3.new(item.Size[1], item.Size[2], item.Size[3])
	local color = Color3.fromHex(item.Color)
	local accent = Color3.fromHex(item.Accent or item.Color)
	local shape = item.Shape

	local handle = newPart({ Name = "Handle", Size = size, Color = color })
	handle.Parent = model
	model.PrimaryPart = handle

	if shape == "Round" then
		handle.Shape = Enum.PartType.Ball
		handle.Size = Vector3.new(size.X, size.X, size.X)
		if item.Id == "Apple" then
			weldTo(handle, newPart({ Size = Vector3.new(0.08, 0.3, 0.08), Color = Color3.fromHex("5d4037") }), CFrame.new(0, size.X / 2, 0))
			weldTo(handle, newPart({ Size = Vector3.new(0.3, 0.05, 0.18), Color = accent }), CFrame.new(0.12, size.X / 2 + 0.05, 0))
		elseif item.Id == "LuckyCoin" then
			handle.Shape = Enum.PartType.Cylinder
			handle.Size = Vector3.new(size.Y, size.X, size.Z)
			handle.Material = Enum.Material.Foil
		else
			weldTo(handle, newPart({ Size = Vector3.new(size.X * 0.9, size.X * 0.2, size.X * 0.9), Color = accent }), CFrame.new(0, -size.X * 0.15, 0))
		end
	elseif shape == "Can" or shape == "Bottle" or shape == "Cell" then
		-- vertical cylinder: a Cylinder part's axis is X, rotate it up
		local d = size.X
		handle.Shape = Enum.PartType.Cylinder
		handle.Size = Vector3.new(size.Y, d, d)
		handle.CFrame = CFrame.Angles(0, 0, math.rad(90))
		handle.Material = if shape == "Can" then Enum.Material.Metal else Enum.Material.SmoothPlastic
		local band = newPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(size.Y * 0.45, d * 1.04, d * 1.04), Color = accent })
		weldTo(handle, band, CFrame.new(0, 0, 0))
		if shape == "Bottle" then
			local cap = newPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(size.Y * 0.18, d * 0.45, d * 0.45), Color = accent })
			weldTo(handle, cap, CFrame.new(size.Y * 0.58, 0, 0))
			handle.Transparency = if item.Id == "Water" then 0.25 else 0
		elseif shape == "Cell" then
			local nub = newPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, d * 0.4, d * 0.4), Color = Color3.fromHex("cfd8dc"), Material = Enum.Material.Metal })
			weldTo(handle, nub, CFrame.new(size.Y * 0.53, 0, 0))
			if item.Id == "PowerCell" then
				band.Material = Enum.Material.Neon
			end
		end
	elseif shape == "Tool" then
		local tool = item.Tool
		if tool == "Flashlight" then
			handle.Shape = Enum.PartType.Cylinder
			handle.Size = Vector3.new(size.Z, size.X, size.X)
			handle.CFrame = CFrame.Angles(0, math.rad(-90), 0)
			handle.Material = Enum.Material.Metal
			local head = newPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35, size.X * 1.5, size.X * 1.5), Color = color, Material = Enum.Material.Metal })
			weldTo(handle, head, CFrame.new(-size.Z / 2, 0, 0))
			local lens = newPart({ Name = "Lens", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, size.X * 1.3, size.X * 1.3), Color = accent, Material = Enum.Material.Neon })
			weldTo(handle, lens, CFrame.new(-size.Z / 2 - 0.18, 0, 0))
		elseif tool == "Hammer" then
			handle.Size = Vector3.new(0.25, size.Y, 0.25)
			handle.Material = Enum.Material.Wood
			weldTo(handle, newPart({ Size = Vector3.new(0.9, 0.35, 0.35), Color = accent, Material = Enum.Material.Metal }), CFrame.new(0.15, size.Y / 2 - 0.1, 0))
		elseif tool == "Crowbar" then
			handle.Size = Vector3.new(0.18, size.Y, 0.18)
			handle.Material = Enum.Material.Metal
			weldTo(handle, newPart({ Size = Vector3.new(0.5, 0.18, 0.18), Color = color, Material = Enum.Material.Metal }), CFrame.new(0.2, size.Y / 2, 0) * CFrame.Angles(0, 0, math.rad(-30)))
		elseif tool == "StunBaton" then
			handle.Size = Vector3.new(0.22, size.Y, 0.22)
			weldTo(handle, newPart({ Name = "Tip", Size = Vector3.new(0.3, 0.4, 0.3), Color = accent, Material = Enum.Material.Neon }), CFrame.new(0, size.Y / 2 + 0.2, 0))
		end
	elseif shape == "Kit" then
		weldTo(handle, newPart({ Size = Vector3.new(size.X * 0.5, size.Y * 0.16, 0.05), Color = accent }), CFrame.new(0, 0, -size.Z / 2 - 0.02))
		weldTo(handle, newPart({ Size = Vector3.new(size.X * 0.16, size.Y * 0.6, 0.05), Color = accent }), CFrame.new(0, 0, -size.Z / 2 - 0.02))
		if item.Id == "NightVision" then
			for _, x in { -0.22, 0.22 } do
				local lens = newPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 0.3, 0.3), Color = accent, Material = Enum.Material.Neon })
				weldTo(handle, lens, CFrame.new(x, 0, -size.Z / 2 - 0.1) * CFrame.Angles(0, math.rad(90), 0))
			end
		end
	elseif shape == "Jug" then
		weldTo(handle, newPart({ Size = Vector3.new(0.2, 0.25, 0.25), Color = accent }), CFrame.new(size.X / 2 - 0.15, size.Y / 2 + 0.1, 0))
		weldTo(handle, newPart({ Size = Vector3.new(0.5, 0.15, 0.15), Color = accent }), CFrame.new(-0.1, size.Y / 2 + 0.05, 0))
	elseif shape == "Plank" then
		weldTo(handle, newPart({ Size = size, Color = accent, Material = Enum.Material.WoodPlanks }), CFrame.new(0.15, size.Y, 0.05) * CFrame.Angles(0, math.rad(8), 0))
		handle.Material = Enum.Material.WoodPlanks
	elseif shape == "Sheet" then
		handle.Material = if item.Id == "Glass" then Enum.Material.Glass else Enum.Material.DiamondPlate
		handle.Transparency = if item.Id == "Glass" then 0.4 else 0
		if item.Id == "CircuitBoard" then
			handle.Material = Enum.Material.SmoothPlastic
			for i = -1, 1 do
				weldTo(handle, newPart({ Size = Vector3.new(0.15, 0.06, 0.15), Color = accent, Material = Enum.Material.Neon }), CFrame.new(i * 0.25, 0.06, 0.1))
			end
		end
	elseif shape == "Brick" then
		handle.Material = Enum.Material.Metal
		handle.Reflectance = 0.2
	else -- Box, Bag, Flat, Slice, Card
		if shape == "Bag" then
			handle.Material = Enum.Material.Foil
		end
		weldTo(handle, newPart({ Size = Vector3.new(size.X * 1.02, size.Y * 0.3, size.Z * 1.02), Color = accent }), CFrame.new(0, size.Y * 0.1, 0))
	end
	-- keep the model's pivot upright even when the handle part itself is rotated (cylinders)
	handle.PivotOffset = handle.CFrame.Rotation:Inverse()
	return model
end

--[[
	Shopping cart. Front of the cart is -Z, the handle is at +Z.
	PrimaryPart "Root" is the chassis; everything is welded to it.
]]
function Models.Cart(color: Color3?, material: Enum.Material?): Model
	local model = Instance.new("Model")
	model.Name = "Cart"
	local c = color or Color3.fromHex("b9c1c9")
	local mat = material or Enum.Material.Metal
	local root = newPart({ Name = "Root", Size = Vector3.new(2.8, 0.3, 4.4), Color = Color3.fromHex("37474f"), Material = Enum.Material.Metal, CanCollide = true, CanQuery = true, Massless = false })
	root.Parent = model
	model.PrimaryPart = root

	local function piece(name, size, offset, transparency, m)
		local p = newPart({ Name = name, Size = size, Color = c, Material = m or mat, Transparency = transparency or 0, CanQuery = true, CanCollide = true })
		weldTo(root, p, offset)
		return p
	end
	-- wheels
	for _, x in { -1.1, 1.1 } do
		for _, z in { -1.8, 1.8 } do
			local w = newPart({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35, 0.8, 0.8), Color = Color3.fromHex("1b1b1b") })
			weldTo(root, w, CFrame.new(x, -0.45, z))
		end
	end
	-- basket (wire mesh look)
	piece("Floor", Vector3.new(2.8, 0.15, 4.2), CFrame.new(0, 1.3, 0), 0.25, Enum.Material.DiamondPlate)
	piece("SideL", Vector3.new(0.12, 2.1, 4.2), CFrame.new(-1.4, 2.35, 0), 0.45, Enum.Material.DiamondPlate)
	piece("SideR", Vector3.new(0.12, 2.1, 4.2), CFrame.new(1.4, 2.35, 0), 0.45, Enum.Material.DiamondPlate)
	piece("Front", Vector3.new(2.8, 2.1, 0.12), CFrame.new(0, 2.35, -2.1), 0.45, Enum.Material.DiamondPlate)
	piece("Back", Vector3.new(2.8, 2.1, 0.12), CFrame.new(0, 2.35, 2.1), 0.45, Enum.Material.DiamondPlate)
	piece("Rim", Vector3.new(2.95, 0.15, 4.35), CFrame.new(0, 3.45, 0), 0, mat)
	-- frame legs
	for _, x in { -1.2, 1.2 } do
		piece("Leg", Vector3.new(0.12, 1.2, 0.12), CFrame.new(x, 0.65, 1.9), 0, mat)
		piece("Leg", Vector3.new(0.12, 1.2, 0.12), CFrame.new(x, 0.65, -1.9), 0, mat)
	end
	-- handle
	local bar = newPart({ Name = "Handle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 0.25, 0.25), Color = Color3.fromHex("e53935"), Material = Enum.Material.SmoothPlastic, CanQuery = true })
	weldTo(root, bar, CFrame.new(0, 3.9, 2.7))
	for _, x in { -1.3, 1.3 } do
		piece("HandlePost", Vector3.new(0.12, 0.9, 0.7), CFrame.new(x, 3.6, 2.4) * CFrame.Angles(math.rad(-30), 0, 0), 0, mat)
	end
	-- contents preview (fills up as the cart is loaded)
	local load = newPart({ Name = "Load", Size = Vector3.new(2.5, 0.1, 3.9), Color = Color3.fromHex("b58b5d"), Material = Enum.Material.Cardboard, Transparency = 1 })
	weldTo(root, load, CFrame.new(0, 1.4, 0))
	return model
end

return Models
