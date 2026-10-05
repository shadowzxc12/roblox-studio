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
	Item model. The returned Model's PrimaryPart is "Handle": an invisible box the size of the
	item, centred, never rotated (so the model pivot is the item centre, +Y up, -Z front).
	Every visible piece is welded to it. Pieces are shaped per item: cans have rims and labels,
	bottles necks and caps, the flashlight a ribbed grip, a switch and a lens, the hammer a
	rubber grip and a claw, and so on.
]]
local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local UP = CFrame.Angles(0, 0, math.pi / 2) -- a Cylinder's axis is X: stand it up
local FWD = CFrame.Angles(0, math.pi / 2, 0) -- lay a cylinder along Z

local function darker(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), k)
end
local function lighter(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), k)
end

function Models.Item(itemId: string): Model
	local item = Items.Get(itemId)
	local model = Instance.new("Model")
	model.Name = itemId
	local size = if item then Vector3.new(item.Size[1], item.Size[2], item.Size[3]) else Vector3.one
	local handle = newPart({ Name = "Handle", Size = size, Transparency = 1, Color = Color3.new(1, 0, 1) })
	handle.Parent = model
	model.PrimaryPart = handle
	if not item then
		handle.Transparency = 0
		return model
	end
	local color = Color3.fromHex(item.Color)
	local accent = Color3.fromHex(item.Accent or item.Color)
	local sx, sy, sz = size.X, size.Y, size.Z
	local shape = item.Shape
	local id = item.Id

	local function add(name: string, sz3: Vector3, cf: CFrame, c: Color3, mat: Enum.Material?, partShape: Enum.PartType?, props): BasePart
		local p = newPart({ Name = name, Size = sz3, Color = c, Material = mat or Enum.Material.SmoothPlastic })
		if partShape then
			p.Shape = partShape
		end
		if props then
			for k, v in props do
				(p :: any)[k] = v
			end
		end
		weldTo(handle, p, cf)
		return p
	end
	-- vertical cylinder centred at (x, y, z)
	local function vcyl(name, dia, h, x, y, z, c, mat)
		return add(name, Vector3.new(h, dia, dia), CFrame.new(x, y, z) * UP, c, mat, CYL)
	end

	if shape == "Can" then
		local d = sx
		vcyl("Body", d, sy * 0.9, 0, 0, 0, Color3.fromHex("b8bec5"), Enum.Material.Metal)
		vcyl("Label", d * 1.02, sy * 0.62, 0, -sy * 0.02, 0, color)
		add("Stripe", Vector3.new(d * 0.5, sy * 0.16, 0.03), CFrame.new(0, sy * 0.05, -d * 0.5), accent)
		vcyl("RimTop", d * 0.96, sy * 0.05, 0, sy * 0.47, 0, Color3.fromHex("cfd5db"), Enum.Material.Metal)
		vcyl("RimBottom", d * 0.94, sy * 0.05, 0, -sy * 0.47, 0, Color3.fromHex("9aa1a8"), Enum.Material.Metal)
		if id == "Soda" or id == "EnergyDrink" or id == "Coffee" then
			add("Tab", Vector3.new(d * 0.22, 0.03, d * 0.14), CFrame.new(0, sy * 0.5, d * 0.1), Color3.fromHex("d7dce1"), Enum.Material.Metal)
		elseif id == "DuctTape" then
			-- a roll: dark hole in the middle
			vcyl("Hole", d * 0.5, sy * 0.92, 0, 0, 0, darker(color, 0.6))
		end
	elseif shape == "Bottle" then
		local d = sx
		local body = sy * 0.66
		local glass = id == "Water" or id == "Repellent"
		local b = vcyl("Body", d, body, 0, -sy / 2 + body / 2, 0, color, if glass then Enum.Material.Glass else Enum.Material.SmoothPlastic)
		b.Transparency = if id == "Water" then 0.35 else 0
		vcyl("Shoulder", d * 0.8, sy * 0.1, 0, -sy / 2 + body + sy * 0.05, 0, color, b.Material).Transparency = b.Transparency
		vcyl("Neck", d * 0.42, sy * 0.14, 0, -sy / 2 + body + sy * 0.15, 0, color, b.Material).Transparency = b.Transparency
		vcyl("Cap", d * 0.48, sy * 0.1, 0, sy / 2 - sy * 0.05, 0, accent)
		vcyl("Label", d * 1.02, body * 0.42, 0, -sy / 2 + body * 0.5, 0, if glass then accent else lighter(color, 0.6))
		if id == "Flare" then
			add("Striker", Vector3.new(d * 1.05, sy * 0.12, d * 1.05), CFrame.new(0, sy * 0.38, 0), Color3.fromHex("ffffff"))
		elseif id == "Adrenaline" then
			vcyl("Needle", 0.04, sy * 0.25, 0, sy / 2 + sy * 0.1, 0, Color3.fromHex("e0e0e0"), Enum.Material.Metal)
		elseif id == "GasCanister" then
			add("Valve", Vector3.new(d * 0.5, sy * 0.06, d * 0.2), CFrame.new(0, sy / 2, 0), Color3.fromHex("cfd8dc"), Enum.Material.Metal)
		end
	elseif shape == "Cell" then
		local d = sx
		vcyl("Body", d, sy * 0.92, 0, -sy * 0.02, 0, darker(accent, 0.2), Enum.Material.SmoothPlastic)
		vcyl("Wrap", d * 1.02, sy * 0.55, 0, sy * 0.1, 0, color, if id == "PowerCell" then Enum.Material.Neon else Enum.Material.SmoothPlastic)
		vcyl("Plus", d * 0.38, sy * 0.08, 0, sy * 0.48, 0, Color3.fromHex("cfd8dc"), Enum.Material.Metal)
		vcyl("Minus", d * 0.9, sy * 0.04, 0, -sy * 0.49, 0, Color3.fromHex("9aa1a8"), Enum.Material.Metal)
	elseif shape == "Tool" then
		local tool = item.Tool
		if tool == "Flashlight" then
			local d, L = sx, sz
			-- body along Z, lens at the front (-Z)
			add("Body", Vector3.new(L * 0.62, d, d), CFrame.new(0, 0, L * 0.12) * FWD, color, Enum.Material.Metal, CYL)
			for i = 0, 4 do
				add("Grip", Vector3.new(0.05, d * 1.06, d * 1.06), CFrame.new(0, 0, L * 0.05 + i * 0.09) * FWD, darker(color, 0.35), Enum.Material.Rubber, CYL)
			end
			add("Neck", Vector3.new(L * 0.12, d * 1.2, d * 1.2), CFrame.new(0, 0, -L * 0.24) * FWD, color, Enum.Material.Metal, CYL)
			add("Head", Vector3.new(L * 0.2, d * 1.55, d * 1.55), CFrame.new(0, 0, -L * 0.38) * FWD, lighter(color, 0.08), Enum.Material.Metal, CYL)
			add("Bezel", Vector3.new(0.06, d * 1.6, d * 1.6), CFrame.new(0, 0, -L * 0.48) * FWD, Color3.fromHex("c9ced4"), Enum.Material.Metal, CYL)
			add("Lens", Vector3.new(0.04, d * 1.35, d * 1.35), CFrame.new(0, 0, -L * 0.5) * FWD, accent, Enum.Material.Glass, CYL, { Transparency = 0.2 })
			add("Switch", Vector3.new(d * 0.32, d * 0.18, d * 0.42), CFrame.new(0, d * 0.5, -L * 0.1), Color3.fromHex("e53935"), Enum.Material.SmoothPlastic)
			add("TailCap", Vector3.new(0.08, d * 1.05, d * 1.05), CFrame.new(0, 0, L * 0.44) * FWD, darker(color, 0.3), Enum.Material.Metal, CYL)
			add("Lanyard", Vector3.new(0.04, d * 0.5, 0.12), CFrame.new(0, -d * 0.2, L * 0.5), Color3.fromHex("111111"), Enum.Material.Fabric)
		elseif tool == "Hammer" then
			local L = sy
			add("Shaft", Vector3.new(L * 0.86, 0.17, 0.17), CFrame.new(0, -L * 0.06, 0) * UP, color, Enum.Material.Wood, CYL)
			add("Grip", Vector3.new(L * 0.36, 0.22, 0.22), CFrame.new(0, -L * 0.3, 0) * UP, Color3.fromHex("1b1b1b"), Enum.Material.Rubber, CYL)
			add("Head", Vector3.new(0.34, 0.26, 0.26), CFrame.new(0, L * 0.42, 0), accent, Enum.Material.Metal)
			add("Face", Vector3.new(0.18, 0.24, 0.24), CFrame.new(0, L * 0.42, -0.2) * FWD, lighter(accent, 0.15), Enum.Material.Metal, CYL)
			add("ClawA", Vector3.new(0.09, 0.08, 0.34), CFrame.new(0.05, L * 0.4, 0.26) * CFrame.Angles(math.rad(25), 0, 0), accent, Enum.Material.Metal)
			add("ClawB", Vector3.new(0.09, 0.08, 0.34), CFrame.new(-0.05, L * 0.4, 0.26) * CFrame.Angles(math.rad(25), 0, 0), accent, Enum.Material.Metal)
		elseif tool == "Crowbar" then
			local L = sy
			add("Bar", Vector3.new(L * 0.86, 0.13, 0.13), CFrame.new(0, -L * 0.04, 0) * UP, color, Enum.Material.Metal, CYL)
			for i = 1, 3 do
				local a = math.rad(35 * i)
				add("Hook", Vector3.new(0.13, 0.16, 0.12), CFrame.new(0, L * 0.39, 0) * CFrame.Angles(a, 0, 0) * CFrame.new(0, 0.1, -0.03 * i), color, Enum.Material.Metal)
			end
			add("Claw", Vector3.new(0.14, 0.05, 0.22), CFrame.new(0, L * 0.43, 0.2) * CFrame.Angles(math.rad(80), 0, 0), darker(color, 0.25), Enum.Material.Metal)
			add("Blade", Vector3.new(0.16, 0.24, 0.05), CFrame.new(0, -L * 0.47, -0.05) * CFrame.Angles(math.rad(-20), 0, 0), darker(color, 0.25), Enum.Material.Metal)
			add("Tape", Vector3.new(L * 0.2, 0.16, 0.16), CFrame.new(0, -L * 0.25, 0) * UP, accent, Enum.Material.Fabric, CYL)
		elseif tool == "StunBaton" then
			local L = sy
			add("Grip", Vector3.new(L * 0.34, 0.26, 0.26), CFrame.new(0, -L * 0.32, 0) * UP, Color3.fromHex("1b1b1b"), Enum.Material.Rubber, CYL)
			add("Guard", Vector3.new(0.06, 0.38, 0.38), CFrame.new(0, -L * 0.14, 0) * UP, Color3.fromHex("3a3a3a"), Enum.Material.Metal, CYL)
			add("Shaft", Vector3.new(L * 0.5, 0.2, 0.2), CFrame.new(0, L * 0.12, 0) * UP, color, Enum.Material.Metal, CYL)
			add("Tip", Vector3.new(0.2, 0.24, 0.24), CFrame.new(0, L * 0.42, 0) * UP, accent, Enum.Material.Neon, CYL)
			add("Prong", Vector3.new(0.04, 0.12, 0.04), CFrame.new(0.06, L * 0.5, 0), Color3.fromHex("d7dce1"), Enum.Material.Metal)
			add("Prong", Vector3.new(0.04, 0.12, 0.04), CFrame.new(-0.06, L * 0.5, 0), Color3.fromHex("d7dce1"), Enum.Material.Metal)
			add("Battery", Vector3.new(0.12, 0.12, 0.06), CFrame.new(0, -L * 0.2, -0.14), accent, Enum.Material.Neon)
		end
	elseif shape == "Kit" then
		if id == "NightVision" then
			add("Strap", Vector3.new(sx * 1.05, sy * 0.35, sz * 0.9), CFrame.new(0, 0, sz * 0.1), Color3.fromHex("1b1b1b"), Enum.Material.Fabric)
			add("Housing", Vector3.new(sx * 0.7, sy * 0.8, sz * 0.6), CFrame.new(0, 0, -sz * 0.05), color, Enum.Material.SmoothPlastic)
			for _, x in { -0.22, 0.22 } do
				add("Tube", Vector3.new(sz * 0.6, sy * 0.62, sy * 0.62), CFrame.new(x, 0, -sz * 0.3) * FWD, darker(color, 0.4), Enum.Material.Metal, CYL)
				add("Lens", Vector3.new(0.04, sy * 0.52, sy * 0.52), CFrame.new(x, 0, -sz * 0.61) * FWD, accent, Enum.Material.Neon, CYL)
			end
			add("Knob", Vector3.new(0.08, 0.12, 0.12), CFrame.new(sx * 0.38, sy * 0.25, 0) * FWD, Color3.fromHex("3a3a3a"), Enum.Material.Metal, CYL)
		else
			-- first aid case with handle and latches
			add("Case", Vector3.new(sx, sy * 0.9, sz), CFrame.new(0, -sy * 0.05, 0), color, Enum.Material.SmoothPlastic)
			add("Lid", Vector3.new(sx * 1.02, sy * 0.12, sz * 1.02), CFrame.new(0, sy * 0.22, 0), darker(color, 0.06), Enum.Material.SmoothPlastic)
			add("CrossH", Vector3.new(sx * 0.42, sy * 0.14, 0.03), CFrame.new(0, -sy * 0.05, -sz / 2 - 0.01), accent)
			add("CrossV", Vector3.new(sx * 0.14, sy * 0.48, 0.03), CFrame.new(0, -sy * 0.05, -sz / 2 - 0.01), accent)
			add("CarryHandle", Vector3.new(sx * 0.4, 0.08, 0.1), CFrame.new(0, sy * 0.5, 0), Color3.fromHex("2b2b2b"), Enum.Material.Rubber)
			for _, x in { -0.3, 0.3 } do
				add("Latch", Vector3.new(0.1, 0.12, 0.04), CFrame.new(x * sx, sy * 0.2, -sz / 2 - 0.01), Color3.fromHex("cfd8dc"), Enum.Material.Metal)
			end
		end
	elseif shape == "Jug" then
		add("Body", Vector3.new(sx, sy * 0.86, sz), CFrame.new(0, -sy * 0.07, 0), color, Enum.Material.Metal)
		add("Rib", Vector3.new(sx * 0.7, sy * 0.06, sz * 1.04), CFrame.new(0, -sy * 0.12, 0), darker(color, 0.2), Enum.Material.Metal)
		add("Rib", Vector3.new(sx * 0.7, sy * 0.06, sz * 1.04), CFrame.new(0, sy * 0.08, 0), darker(color, 0.2), Enum.Material.Metal)
		add("HandleBar", Vector3.new(sx * 0.5, 0.1, 0.12), CFrame.new(-sx * 0.15, sy * 0.46, 0), accent, Enum.Material.Metal)
		add("HandlePost", Vector3.new(0.1, sy * 0.12, 0.12), CFrame.new(-sx * 0.38, sy * 0.4, 0), accent, Enum.Material.Metal)
		add("Spout", Vector3.new(sy * 0.3, 0.14, 0.14), CFrame.new(sx * 0.38, sy * 0.48, 0) * CFrame.Angles(0, 0, math.rad(55)), accent, Enum.Material.Metal, CYL)
		add("Cap", Vector3.new(0.06, 0.18, 0.18), CFrame.new(sx * 0.47, sy * 0.6, 0) * CFrame.Angles(0, 0, math.rad(55)), Color3.fromHex("ffc61a"), Enum.Material.SmoothPlastic, CYL)
	elseif shape == "Plank" then
		for i = 0, 1 do
			add("Plank", Vector3.new(sx, sy * 0.48, sz * 0.48), CFrame.new(0, -sy * 0.25 + i * sy * 0.5, (i - 0.5) * sz * 0.46) * CFrame.Angles(0, math.rad(i * 4), 0), if i == 0 then color else accent, Enum.Material.WoodPlanks)
			for _, x in { -0.4, 0.4 } do
				add("Nail", Vector3.new(0.05, 0.02, 0.05), CFrame.new(x * sx, -sy * 0.25 + i * sy * 0.5 + sy * 0.25, (i - 0.5) * sz * 0.46), Color3.fromHex("8d9aa6"), Enum.Material.Metal)
			end
		end
		add("Band", Vector3.new(0.08, sy * 1.05, sz * 1.02), CFrame.new(0, 0, 0), Color3.fromHex("1b1b1b"), Enum.Material.Fabric)
	elseif shape == "Sheet" then
		local glass = id == "Glass"
		add("Sheet", size, CFrame.new(), color, if glass then Enum.Material.Glass elseif id == "CircuitBoard" then Enum.Material.SmoothPlastic else Enum.Material.DiamondPlate, nil, { Transparency = if glass then 0.45 else 0, Reflectance = if id == "SteelPlate" then 0.15 else 0 })
		if id == "CircuitBoard" then
			for i = -1, 1 do
				add("Chip", Vector3.new(0.18, 0.06, 0.18), CFrame.new(i * sx * 0.28, sy * 0.55, sz * 0.12), Color3.fromHex("1b1b1b"))
				add("Trace", Vector3.new(0.03, 0.02, sz * 0.7), CFrame.new(i * sx * 0.28 + 0.12, sy * 0.52, 0), accent, Enum.Material.Neon)
			end
			add("Cap", Vector3.new(0.12, 0.14, 0.12), CFrame.new(sx * 0.35, sy * 0.6, -sz * 0.3) * UP, Color3.fromHex("1565c0"), Enum.Material.SmoothPlastic, CYL)
		elseif not glass then
			for _, x in { -0.42, 0.42 } do
				for _, z in { -0.4, 0.4 } do
					add("Bolt", Vector3.new(0.06, 0.1, 0.1), CFrame.new(x * sx, sy * 0.55, z * sz) * UP, darker(color, 0.4), Enum.Material.Metal, CYL)
				end
			end
		else
			add("Frame", Vector3.new(sx * 1.02, sy * 1.1, 0.06), CFrame.new(0, 0, -sz / 2), Color3.fromHex("9aa0a8"), Enum.Material.Metal)
		end
	elseif shape == "Brick" then
		add("Ingot", size * Vector3.new(1, 0.8, 1), CFrame.new(0, -sy * 0.1, 0), color, Enum.Material.Metal, nil, { Reflectance = 0.25 })
		add("Top", size * Vector3.new(0.86, 0.2, 0.8), CFrame.new(0, sy * 0.4, 0), lighter(color, 0.15), Enum.Material.Metal, nil, { Reflectance = 0.3 })
		add("Stamp", Vector3.new(sx * 0.4, 0.02, sz * 0.3), CFrame.new(0, sy * 0.51, 0), accent, Enum.Material.Neon)
	elseif shape == "Round" then
		if id == "Apple" then
			add("Fruit", Vector3.new(sx, sx, sx), CFrame.new(), color, Enum.Material.SmoothPlastic, BALL)
			add("Stem", Vector3.new(0.06, 0.24, 0.06), CFrame.new(0, sx / 2, 0) * CFrame.Angles(0, 0, math.rad(12)), Color3.fromHex("5d4037"), Enum.Material.Wood)
			add("Leaf", Vector3.new(0.26, 0.03, 0.14), CFrame.new(0.1, sx / 2 + 0.06, 0) * CFrame.Angles(0, 0, math.rad(-20)), accent, Enum.Material.Grass)
		elseif id == "Burger" then
			vcyl("BunBottom", sx, sy * 0.25, 0, -sy * 0.35, 0, color)
			vcyl("Patty", sx * 1.02, sy * 0.18, 0, -sy * 0.15, 0, accent, Enum.Material.Slate)
			add("Cheese", Vector3.new(sx * 0.9, sy * 0.05, sz * 0.9), CFrame.new(0, -sy * 0.04, 0) * CFrame.Angles(0, math.rad(45), 0), Color3.fromHex("ffc107"))
			vcyl("Lettuce", sx * 1.06, sy * 0.06, 0, sy * 0.02, 0, Color3.fromHex("6abf4b"), Enum.Material.Grass)
			vcyl("BunTop", sx, sy * 0.2, 0, sy * 0.15, 0, lighter(color, 0.08))
			add("Dome", Vector3.new(sx * 0.9, sx * 0.9, sx * 0.9), CFrame.new(0, sy * 0.25 - sx * 0.2, 0), lighter(color, 0.08), Enum.Material.SmoothPlastic, BALL)
		elseif id == "GoldenCake" then
			vcyl("Tier1", sx, sy * 0.45, 0, -sy * 0.27, 0, color)
			vcyl("Tier2", sx * 0.68, sy * 0.35, 0, sy * 0.13, 0, lighter(color, 0.1))
			vcyl("Icing", sx * 1.02, sy * 0.06, 0, -sy * 0.04, 0, accent)
			vcyl("Candle", 0.08, sy * 0.25, 0, sy * 0.42, 0, Color3.fromHex("ff5a8a"))
			add("Flame", Vector3.new(0.1, 0.14, 0.1), CFrame.new(0, sy * 0.6, 0), Color3.fromHex("ffcc33"), Enum.Material.Neon, BALL)
		elseif id == "LuckyCoin" then
			add("Coin", Vector3.new(sy, sx, sx), CFrame.new() * UP, color, Enum.Material.Foil, CYL)
			add("Rim", Vector3.new(sy * 1.1, sx * 0.8, sx * 0.8), CFrame.new() * UP, accent, Enum.Material.Foil, CYL)
		elseif id == "Rotisserie" then
			add("Chicken", Vector3.new(sx, sy, sz), CFrame.new(), color, Enum.Material.SmoothPlastic, BALL)
			for _, x in { -0.3, 0.3 } do
				add("Leg", Vector3.new(0.5, 0.18, 0.18), CFrame.new(x * sx, sy * 0.1, -sz * 0.42) * CFrame.Angles(0, math.rad(90 + x * 60), math.rad(20)), darker(color, 0.15), Enum.Material.SmoothPlastic, CYL)
			end
			add("Tray", Vector3.new(sx * 1.2, 0.06, sz * 1.1), CFrame.new(0, -sy / 2, 0), Color3.fromHex("111111"))
		else
			add("Ball", Vector3.new(sx, sx, sx), CFrame.new(), color, Enum.Material.SmoothPlastic, BALL)
			add("Band", Vector3.new(sx * 0.95, sx * 0.2, sx * 0.95), CFrame.new(0, -sx * 0.12, 0), accent)
		end
	elseif shape == "Card" then
		add("Card", Vector3.new(sx, math.max(sy, 0.04), sz), CFrame.new(), color)
		if id == "StoreMap" then
			add("Fold", Vector3.new(0.02, sy * 1.2, sz), CFrame.new(-sx * 0.17, 0, 0), darker(color, 0.25))
			add("Fold", Vector3.new(0.02, sy * 1.2, sz), CFrame.new(sx * 0.17, 0, 0), darker(color, 0.25))
			add("Title", Vector3.new(sx * 0.8, sy * 1.1, sz * 0.14), CFrame.new(0, 0, -sz * 0.36), accent)
		else
			add("Stripe", Vector3.new(sx, sy * 1.1, sz * 0.16), CFrame.new(0, 0, -sz * 0.25), accent)
			add("Chip", Vector3.new(sx * 0.18, sy * 1.2, sz * 0.2), CFrame.new(-sx * 0.28, 0, sz * 0.1), Color3.fromHex("d4af37"), Enum.Material.Foil)
			add("Clip", Vector3.new(sx * 0.2, sy * 1.2, sz * 0.08), CFrame.new(0, 0, sz * 0.47), Color3.fromHex("cfd8dc"), Enum.Material.Metal)
		end
	elseif shape == "Bag" then
		add("Bag", Vector3.new(sx * 0.96, sy * 0.82, sz), CFrame.new(), color, if id == "Cloth" then Enum.Material.Fabric else Enum.Material.Foil)
		add("CrimpTop", Vector3.new(sx, sy * 0.1, sz * 0.4), CFrame.new(0, sy * 0.45, 0), darker(color, 0.2), Enum.Material.Foil)
		add("CrimpBottom", Vector3.new(sx, sy * 0.08, sz * 0.5), CFrame.new(0, -sy * 0.45, 0), darker(color, 0.2), Enum.Material.Foil)
		add("Label", Vector3.new(sx * 0.6, sy * 0.34, 0.03), CFrame.new(0, 0, -sz / 2 - 0.01), accent)
		if id == "Banana" then
			for i = -1, 1 do
				add("Banana", Vector3.new(sx, sy * 0.5, sz * 0.4), CFrame.new(0, i * 0.04, i * sz * 0.3) * CFrame.Angles(0, 0, math.rad(i * 8)), color, Enum.Material.SmoothPlastic, CYL)
			end
		end
	elseif shape == "Flat" then
		add("Box", Vector3.new(sx, sy * 0.85, sz), CFrame.new(), color, Enum.Material.Cardboard)
		add("Window", Vector3.new(sx * 0.62, 0.03, sz * 0.62), CFrame.new(0, sy * 0.44, 0), accent)
		add("Brand", Vector3.new(sx * 0.9, 0.03, sz * 0.14), CFrame.new(0, sy * 0.44, -sz * 0.4), Color3.fromHex("ffffff"))
	elseif shape == "Slice" then
		add("BreadBottom", Vector3.new(sx, sy * 0.25, sz), CFrame.new(0, -sy * 0.35, 0), color)
		add("Filling", Vector3.new(sx * 1.04, sy * 0.25, sz * 1.04), CFrame.new(0, -sy * 0.08, 0), accent, Enum.Material.Grass)
		add("Ham", Vector3.new(sx * 0.98, sy * 0.1, sz * 0.98), CFrame.new(0, sy * 0.08, 0), Color3.fromHex("e57373"))
		add("BreadTop", Vector3.new(sx, sy * 0.25, sz), CFrame.new(0, sy * 0.3, 0) * CFrame.Angles(0, math.rad(5), 0), color)
	else -- Box
		local isCardboard = item.Category == "Material"
		add("Box", Vector3.new(sx, sy, sz), CFrame.new(), color, if isCardboard then Enum.Material.Cardboard else Enum.Material.SmoothPlastic)
		add("Band", Vector3.new(sx * 1.02, sy * 0.24, sz * 1.02), CFrame.new(0, sy * 0.14, 0), accent)
		add("Logo", Vector3.new(sx * 0.4, sy * 0.3, 0.03), CFrame.new(-sx * 0.15, -sy * 0.18, -sz / 2 - 0.01), lighter(accent, 0.4))
		if id == "NoiseMaker" then
			for _, x in { -0.25, 0.25 } do
				add("Bell", Vector3.new(0.22, 0.22, 0.22), CFrame.new(x * sx, sy * 0.55, 0), Color3.fromHex("d4af37"), Enum.Material.Foil, BALL)
			end
			add("Face", Vector3.new(0.04, sy * 0.6, sy * 0.6), CFrame.new(0, 0, -sz / 2 - 0.02) * FWD, Color3.fromHex("ffffff"), Enum.Material.SmoothPlastic, CYL)
		elseif id == "SupplyBeacon" then
			vcyl("Antenna", 0.05, sy * 0.6, sx * 0.3, sy * 0.75, 0, Color3.fromHex("cfd8dc"), Enum.Material.Metal)
			add("Light", Vector3.new(0.2, 0.2, 0.2), CFrame.new(-sx * 0.2, sy * 0.55, 0), Color3.fromHex("ff6d00"), Enum.Material.Neon, BALL)
		elseif id == "Electronics" then
			add("Wire", Vector3.new(0.05, 0.05, sz * 1.2), CFrame.new(sx * 0.3, sy * 0.55, 0), Color3.fromHex("e53935"))
			add("Wire", Vector3.new(0.05, 0.05, sz * 1.1), CFrame.new(sx * 0.2, sy * 0.55, 0.05), Color3.fromHex("1e88e5"))
		end
	end
	-- the pivot is the (unrotated) handle centre
	handle.PivotOffset = CFrame.new()
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
	-- caster wheels with forks
	for _, x in { -1.1, 1.1 } do
		for _, z in { -1.8, 1.8 } do
			local w = newPart({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 0.75, 0.75), Color = Color3.fromHex("1b1b1b"), Material = Enum.Material.Rubber })
			weldTo(root, w, CFrame.new(x, -0.45, z))
			local hub = newPart({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.32, 0.3, 0.3), Color = Color3.fromHex("9aa0a8"), Material = Enum.Material.Metal })
			weldTo(root, hub, CFrame.new(x, -0.45, z))
			piece("Fork", Vector3.new(0.4, 0.45, 0.12), CFrame.new(x, -0.1, z), 0, mat)
		end
	end
	-- invisible collision panels (the wire mesh below is only visual)
	piece("Floor", Vector3.new(2.8, 0.15, 4.2), CFrame.new(0, 1.3, 0), 1)
	piece("SideL", Vector3.new(0.12, 2.1, 4.2), CFrame.new(-1.4, 2.35, 0), 1)
	piece("SideR", Vector3.new(0.12, 2.1, 4.2), CFrame.new(1.4, 2.35, 0), 1)
	piece("Front", Vector3.new(2.8, 2.1, 0.12), CFrame.new(0, 2.35, -2.1), 1)
	piece("Back", Vector3.new(2.8, 2.1, 0.12), CFrame.new(0, 2.35, 2.1), 1)
	-- wire basket
	local function rod(size: Vector3, offset: CFrame)
		local r = newPart({ Name = "Wire", Size = size, Color = c, Material = mat })
		weldTo(root, r, offset)
	end
	for _, x in { -1.4, 1.4 } do
		for i = 0, 8 do
			rod(Vector3.new(0.06, 2.1, 0.06), CFrame.new(x, 2.35, -2.1 + i * 0.525))
		end
		for k = 0, 2 do
			rod(Vector3.new(0.06, 0.06, 4.2), CFrame.new(x, 1.45 + k * 0.7, 0))
		end
	end
	for _, z in { -2.1, 2.1 } do
		for i = 0, 5 do
			rod(Vector3.new(0.06, 2.1, 0.06), CFrame.new(-1.4 + i * 0.56, 2.35, z))
		end
		for k = 0, 2 do
			rod(Vector3.new(2.8, 0.06, 0.06), CFrame.new(0, 1.45 + k * 0.7, z))
		end
	end
	for i = 0, 5 do
		rod(Vector3.new(0.05, 0.05, 4.2), CFrame.new(-1.4 + i * 0.56, 1.3, 0))
	end
	for i = 0, 7 do
		rod(Vector3.new(2.8, 0.05, 0.05), CFrame.new(0, 1.3, -2.1 + i * 0.6))
	end
	piece("Rim", Vector3.new(2.95, 0.12, 0.12), CFrame.new(0, 3.42, -2.12), 0, mat)
	piece("Rim", Vector3.new(2.95, 0.12, 0.12), CFrame.new(0, 3.42, 2.12), 0, mat)
	piece("Rim", Vector3.new(0.12, 0.12, 4.35), CFrame.new(-1.42, 3.42, 0), 0, mat)
	piece("Rim", Vector3.new(0.12, 0.12, 4.35), CFrame.new(1.42, 3.42, 0), 0, mat)
	-- child seat flap folded on the back + red plastic bumpers + store logo plate
	piece("SeatFlap", Vector3.new(2.4, 1.2, 0.06), CFrame.new(0, 2.9, 1.95) * CFrame.Angles(math.rad(-12), 0, 0), 0.2, Enum.Material.DiamondPlate)
	for _, x in { -1.45, 1.45 } do
		local bumper = newPart({ Name = "Bumper", Size = Vector3.new(0.14, 0.3, 0.6), Color = Color3.fromHex("c4161c") })
		weldTo(root, bumper, CFrame.new(x, 3.2, -2.05))
	end
	local logoPlate = newPart({ Name = "Logo", Size = Vector3.new(1.2, 0.5, 0.05), Color = Color3.fromHex("ffc61a") })
	weldTo(root, logoPlate, CFrame.new(0, 2.9, -2.16))
	-- lower tray + frame legs
	piece("Tray", Vector3.new(2.2, 0.08, 3.4), CFrame.new(0, 0.25, 0.2), 0.3, Enum.Material.DiamondPlate)
	for _, x in { -1.2, 1.2 } do
		piece("Leg", Vector3.new(0.12, 1.2, 0.12), CFrame.new(x, 0.65, 1.9), 0, mat)
		piece("Leg", Vector3.new(0.12, 1.2, 0.12), CFrame.new(x, 0.65, -1.9), 0, mat)
	end
	-- push handle
	local bar = newPart({ Name = "Handle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 0.25, 0.25), Color = Color3.fromHex("e53935"), Material = Enum.Material.SmoothPlastic, CanQuery = true })
	weldTo(root, bar, CFrame.new(0, 3.9, 2.7))
	for _, x in { -1.35, 1.35 } do
		piece("HandlePost", Vector3.new(0.12, 0.9, 0.7), CFrame.new(x, 3.6, 2.4) * CFrame.Angles(math.rad(-30), 0, 0), 0, mat)
	end
	-- contents preview (fills up as the cart is loaded)
	local load = newPart({ Name = "Load", Size = Vector3.new(2.5, 0.1, 3.9), Color = Color3.fromHex("b58b5d"), Material = Enum.Material.Cardboard, Transparency = 1 })
	weldTo(root, load, CFrame.new(0, 1.4, 0))
	return model
end

return Models
