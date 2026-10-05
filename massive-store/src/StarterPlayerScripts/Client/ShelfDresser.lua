--[[
	ShelfDresser: client-side level of detail for the store shelves.
	The server builds each shelf section as one block of colour ("Product" parts, attribute
	Face = which side faces the aisle). Near the camera this replaces the block with real
	merchandise — rows of cans, cereal boxes, bottles, jars and chip bags with labels, caps
	and price tags — and puts the plain block back when you walk away.
	Everything is local (never replicated), anchored, non-colliding and skips shadows/raycasts.
	Variety is seeded from the block's position, so every player sees the same shelf.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ShelfDresser = {}

local NEAR, FAR = 70, 86
local PER_TICK = 10

local blocks: { [BasePart]: boolean } = {}
local dressed: { [BasePart]: Folder } = {}
local holder: Folder? = nil

local LABELS = {
	Color3.fromHex("f2f0ea"),
	Color3.fromHex("ffc61a"),
	Color3.fromHex("e0262d"),
	Color3.fromHex("1e88e5"),
	Color3.fromHex("2e7d32"),
	Color3.fromHex("111111"),
	Color3.fromHex("ff8a1f"),
}

local function hash(v: Vector3): number
	local a = math.floor(v.X * 7.3) % 65536
	local b = math.floor(v.Y * 1.9) % 65536
	local c = math.floor(v.Z * 8.3) % 65536
	return bit32.bxor(a * 7919, b * 104729, c * 1299709) % 2147483647
end

local function mk(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- one product standing on the shelf at `base` (bottom centre), front facing -Z of `base`
local function product(folder: Folder, kind: string, base: CFrame, w: number, h: number, d: number, color: Color3, label: Color3, rng: Random)
	if kind == "Can" then
		local dia = math.min(w, d)
		mk(folder, Vector3.new(h, dia, dia), base * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromHex("b8bec5"), Enum.Material.Metal, Enum.PartType.Cylinder)
		mk(folder, Vector3.new(h * 0.62, dia * 1.02, dia * 1.02), base * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	elseif kind == "Bottle" then
		local dia = math.min(w, d) * 0.9
		local body = h * 0.68
		mk(folder, Vector3.new(body, dia, dia), base * CFrame.new(0, body / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.Glass, Enum.PartType.Cylinder).Transparency = 0.15
		mk(folder, Vector3.new(h * 0.22, dia * 0.42, dia * 0.42), base * CFrame.new(0, body + h * 0.11, 0) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.Glass, Enum.PartType.Cylinder).Transparency = 0.15
		mk(folder, Vector3.new(h * 0.1, dia * 0.46, dia * 0.46), base * CFrame.new(0, h - h * 0.05, 0) * CFrame.Angles(0, 0, math.pi / 2), label, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		mk(folder, Vector3.new(dia * 1.01, body * 0.4, 0.04), base * CFrame.new(0, body * 0.45, -dia / 2 + 0.01), label)
	elseif kind == "Jar" then
		local dia = math.min(w, d)
		mk(folder, Vector3.new(h * 0.85, dia, dia), base * CFrame.new(0, h * 0.425, 0) * CFrame.Angles(0, 0, math.pi / 2), color, Enum.Material.Glass, Enum.PartType.Cylinder).Transparency = 0.1
		mk(folder, Vector3.new(h * 0.15, dia * 0.96, dia * 0.96), base * CFrame.new(0, h * 0.925, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromHex("c9a227"), Enum.Material.Metal, Enum.PartType.Cylinder)
	elseif kind == "Bag" then
		local bag = mk(folder, Vector3.new(w * 0.92, h * 0.86, d * 0.55), base * CFrame.new(0, h * 0.43, 0) * CFrame.Angles(math.rad(rng:NextNumber(-6, 2)), 0, 0), color, Enum.Material.Foil)
		mk(folder, Vector3.new(w * 0.94, h * 0.08, d * 0.3), bag.CFrame * CFrame.new(0, h * 0.45, 0), color:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Foil)
		mk(folder, Vector3.new(w * 0.6, h * 0.3, 0.04), bag.CFrame * CFrame.new(0, 0, -d * 0.28), label)
	else -- Box (cereal, crackers, detergent)
		local box = mk(folder, Vector3.new(w * 0.94, h, d * 0.9), base * CFrame.new(0, h / 2, 0), color, Enum.Material.SmoothPlastic)
		mk(folder, Vector3.new(w * 0.95, h * 0.22, 0.04), box.CFrame * CFrame.new(0, h * 0.24, -d * 0.45 - 0.01), label)
		if rng:NextNumber() < 0.5 then
			-- a round "NEW!" sticker
			mk(folder, Vector3.new(0.04, w * 0.4, w * 0.4), box.CFrame * CFrame.new(w * 0.15, -h * 0.14, -d * 0.45 - 0.02) * CFrame.Angles(0, math.pi / 2, 0), label:Lerp(Color3.new(1, 1, 1), 0.5), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		end
	end
end

local KINDS = { "Can", "Box", "Bottle", "Jar", "Bag", "Box", "Can" }

local function dress(block: BasePart)
	if dressed[block] or not holder then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Dress"
	local rng = Random.new(hash(block.Position))
	local face = block:GetAttribute("Face") or 1
	-- shelf space: X along the shelf, front of the shelf towards the aisle is -Z
	local cf = block.CFrame * CFrame.Angles(0, if face > 0 then math.pi else 0, 0)
	local size = block.Size
	local W, H, D = size.X, size.Y, size.Z
	local kind = KINDS[rng:NextInteger(1, #KINDS)]
	local itemW = if kind == "Box" then rng:NextNumber(0.75, 1.1) elseif kind == "Bag" then rng:NextNumber(0.9, 1.2) else rng:NextNumber(0.5, 0.7)
	local itemH = math.min(H, if kind == "Box" then rng:NextNumber(1.1, 1.6) elseif kind == "Bag" then rng:NextNumber(1.0, 1.4) else rng:NextNumber(0.75, 1.2))
	local itemD = if kind == "Box" then math.min(0.5, D * 0.3) else itemW
	local count = math.max(1, math.floor(W / (itemW + 0.06)))
	local gap = (W - count * itemW) / (count + 1)
	local base = block.Color
	local label = LABELS[rng:NextInteger(1, #LABELS)]
	local bottom = cf * CFrame.new(0, -H / 2, 0)
	-- back stock: a darker block so the shelf looks full behind the front row
	local backDepth = D - itemD - 0.15
	if backDepth > 0.2 then
		mk(folder, Vector3.new(W * 0.96, itemH * 0.92, backDepth), bottom * CFrame.new(0, itemH * 0.46, D / 2 - backDepth / 2), base:Lerp(Color3.new(0, 0, 0), 0.45), Enum.Material.SmoothPlastic)
	end
	for i = 1, count do
		local x = -W / 2 + gap * i + itemW * (i - 0.5)
		-- a few gaps where things were already taken
		if rng:NextNumber() < 0.88 then
			local tint = base:Lerp(Color3.new(1, 1, 1), rng:NextNumber(-0.05, 0.12))
			local at = bottom * CFrame.new(x + rng:NextNumber(-0.04, 0.04), 0, -D / 2 + itemD / 2 + 0.05 + rng:NextNumber(0, 0.12)) * CFrame.Angles(0, math.rad(rng:NextNumber(-7, 7)), 0)
			product(folder, kind, at, itemW, itemH, itemD, tint, label, rng)
		end
	end
	-- price tag strip on the shelf edge
	mk(folder, Vector3.new(W, 0.22, 0.05), bottom * CFrame.new(0, -0.12, -D / 2 - 0.05), Color3.fromHex("f2f0ea"))
	mk(folder, Vector3.new(0.5, 0.18, 0.06), bottom * CFrame.new(rng:NextNumber(-W / 3, W / 3), -0.12, -D / 2 - 0.06), Color3.fromHex("ffc61a"))
	folder.Parent = holder
	dressed[block] = folder
	block.LocalTransparencyModifier = 1
end

local function undress(block: BasePart)
	local f = dressed[block]
	if f then
		f:Destroy()
		dressed[block] = nil
	end
	if block.Parent then
		block.LocalTransparencyModifier = 0
	end
end

local function track(d: Instance)
	if d:IsA("BasePart") and d.Name == "Product" then
		blocks[d] = true
	end
end

local function untrack(d: Instance)
	if blocks[d :: any] then
		blocks[d :: any] = nil
		undress(d :: any)
	end
end

function ShelfDresser.Init()
	holder = Instance.new("Folder")
	holder.Name = "MSL_ShelfDetail"
	holder.Parent = Workspace
	task.spawn(function()
		local store = Workspace:WaitForChild("Store", 120)
		local props = store and store:WaitForChild("Props", 60)
		if not props then
			return
		end
		for _, d in props:GetDescendants() do
			track(d)
		end
		props.DescendantAdded:Connect(track)
		props.DescendantRemoving:Connect(untrack)
		local acc = 0
		RunService.Heartbeat:Connect(function(dt)
			acc += dt
			if acc < 0.25 then
				return
			end
			acc = 0
			local cam = Workspace.CurrentCamera
			if not cam then
				return
			end
			local pos = cam.CFrame.Position
			local budget = PER_TICK
			for block in blocks do
				if not block.Parent then
					untrack(block)
				else
					local dist = (block.Position - pos).Magnitude
					if dressed[block] then
						if dist > FAR then
							undress(block)
						end
					elseif dist < NEAR and budget > 0 then
						budget -= 1
						dress(block)
					end
				end
			end
		end)
	end)
end

return ShelfDresser
