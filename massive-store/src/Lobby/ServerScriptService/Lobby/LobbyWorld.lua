--[[
	LobbyWorld: the lobby is the MASSIVE STORE parking lot at night.
	Every party gets its own "pad": a slice of the store front (glowing sign, sliding doors with
	the lit store behind, cart corral, lamp posts) with the party members lined up in front of it.
	The client camera looks at your pad (Workspace.Lobby.Pads.Pad<n>, attribute Cam).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Models = require(Shared.Models)

local LobbyWorld = {}

local SPACING = 160
local SLOTS = {
	CFrame.new(0, 0, 0),
	CFrame.new(-4.6, 0, 1.4) * CFrame.Angles(0, math.rad(-12), 0),
	CFrame.new(4.6, 0, 1.4) * CFrame.Angles(0, math.rad(12), 0),
	CFrame.new(-9, 0, 3) * CFrame.Angles(0, math.rad(-20), 0),
	CFrame.new(9, 0, 3) * CFrame.Angles(0, math.rad(20), 0),
	CFrame.new(0, 0, 4.5),
}

local root: Folder
local pads: { [number]: CFrame } = {}

local function part(parent: Instance, size: Vector3, cf: CFrame, color: string, material: Enum.Material?, props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = Color3.fromHex(color)
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function signText(p: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?, font: Enum.Font?)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.LightInfluence = 0
	sg.Brightness = 2.2
	sg.PixelsPerStud = 40
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = if bg then 0 else 1
	t.BackgroundColor3 = bg or Color3.new()
	t.TextScaled = true
	t.Font = font or Enum.Font.Oswald
	t.TextColor3 = color
	t.Text = text
	t.Parent = sg
	sg.Parent = p
	return sg
end

-- one store-front slice. O = lineup centre on the ground, LookVector towards the camera.
local function buildPad(index: number, O: CFrame)
	local model = Instance.new("Model")
	model.Name = "Pad" .. index
	local function L(x, y, z)
		return O * CFrame.new(x, y, -z)
	end
	-- the camera: in front of the lineup, a bit low, looking slightly up at the sign
	local camCF = CFrame.lookAt(L(0, 4.6, 19).Position, L(0, 4.2, 0).Position)
	model:SetAttribute("Cam", camCF)
	model:SetAttribute("Origin", O)

	-- asphalt with parking lines
	part(model, Vector3.new(SPACING, 1, SPACING), L(0, -0.5, 10), "1b1c1f", Enum.Material.Asphalt)
	for i = -3, 3 do
		part(model, Vector3.new(0.4, 0.05, 14), L(i * 10 + 5, 0.03, 14), "d8d2b8", Enum.Material.SmoothPlastic, { CanCollide = false })
	end
	-- sidewalk + curb in front of the store
	part(model, Vector3.new(SPACING, 0.7, 12), L(0, 0.35, -10), "5d5f63", Enum.Material.Concrete)
	part(model, Vector3.new(SPACING, 0.75, 0.6), L(0, 0.38, -4), "c9a227", Enum.Material.Concrete)

	-- the store facade
	local wallZ = -16
	part(model, Vector3.new(SPACING, 34, 2), L(0, 17, wallZ), "2b2e33", Enum.Material.Concrete)
	part(model, Vector3.new(SPACING, 3, 3), L(0, 34.5, wallZ + 0.5), "c4161c", Enum.Material.Metal)
	-- entrance: dark glass + warm lit interior
	part(model, Vector3.new(30, 14, 0.6), L(0, 7.4, wallZ + 1.2), "8fb7c9", Enum.Material.Glass, { Transparency = 0.55, Reflectance = 0.25, CanCollide = false })
	local glow = part(model, Vector3.new(30, 14, 0.4), L(0, 7.4, wallZ - 0.4), "ffe8b0", Enum.Material.Neon, { Transparency = 0.15, CanCollide = false })
	local inside = Instance.new("SurfaceLight")
	inside.Face = Enum.NormalId.Back
	inside.Brightness = 3
	inside.Range = 26
	inside.Angle = 120
	inside.Color = Color3.fromHex("ffe2a8")
	inside.Parent = glow
	for _, x in { -15.5, 15.5, 0 } do
		part(model, Vector3.new(0.8, 14.6, 1), L(x, 7.4, wallZ + 1.4), "9aa0a8", Enum.Material.Metal)
	end
	part(model, Vector3.new(32, 0.8, 1.2), L(0, 14.9, wallZ + 1.4), "9aa0a8", Enum.Material.Metal)
	-- shelf silhouettes behind the glass
	for i = -2, 2 do
		part(model, Vector3.new(3, 9, 6), L(i * 6, 4.5, wallZ - 6), "121316", Enum.Material.Metal, { CanCollide = false })
	end
	-- the big sign
	local sign = part(model, Vector3.new(58, 8, 1), L(0, 24, wallZ + 1.6), "111111", Enum.Material.SmoothPlastic)
	signText(sign, Enum.NormalId.Back, "MASSIVE STORE", Color3.fromHex("ffc61a"))
	local signLight = Instance.new("SurfaceLight")
	signLight.Face = Enum.NormalId.Back
	signLight.Color = Color3.fromHex("ffc61a")
	signLight.Brightness = 1.2
	signLight.Range = 18
	signLight.Parent = sign
	local open = part(model, Vector3.new(9, 2.4, 0.4), L(-24, 11, wallZ + 1.3), "c4161c", Enum.Material.Neon)
	signText(open, Enum.NormalId.Back, "OPEN 24/7", Color3.new(1, 1, 1), nil, Enum.Font.Oswald)
	local loc = part(model, Vector3.new(14, 3, 0.4), L(24, 11, wallZ + 1.3), "1a1a1a", Enum.Material.SmoothPlastic)
	signText(loc, Enum.NormalId.Back, "NO EXIT AFTER DARK", Color3.fromHex("ff5a5a"), nil, Enum.Font.Oswald)

	-- lamp posts with cones of light
	for _, x in { -22, 22 } do
		part(model, Vector3.new(0.8, 22, 0.8), L(x, 11, 6), "3a3d42", Enum.Material.Metal)
		part(model, Vector3.new(5, 0.6, 1.6), L(x, 22, 6), "3a3d42", Enum.Material.Metal)
		local bulb = part(model, Vector3.new(3.6, 0.3, 1.2), L(x, 21.6, 6), "fff1c8", Enum.Material.Neon, { CanCollide = false })
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Bottom
		spot.Angle = 75
		spot.Range = 34
		spot.Brightness = 2.4
		spot.Color = Color3.fromHex("ffe7b8")
		spot.Shadows = true
		spot.Parent = bulb
	end
	-- key light on the lineup (so outfits read well)
	local key = part(model, Vector3.new(1, 1, 1), L(-6, 12, 12), "000000", Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false })
	key.CFrame = CFrame.lookAt(key.Position, L(0, 2, 0).Position)
	local keyLight = Instance.new("SpotLight")
	keyLight.Face = Enum.NormalId.Front
	keyLight.Angle = 50
	keyLight.Range = 30
	keyLight.Brightness = 1.6
	keyLight.Color = Color3.fromHex("fff4dc")
	keyLight.Parent = key
	-- red rim light from inside the store (something is watching)
	local rim = part(model, Vector3.new(1, 1, 1), L(8, 5, -10), "000000", Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false })
	local rimLight = Instance.new("PointLight")
	rimLight.Color = Color3.fromHex("ff2a2a")
	rimLight.Range = 14
	rimLight.Brightness = 0.8
	rimLight.Parent = rim

	-- cart corral + a few carts
	for i = 0, 2 do
		local cart = Models.Cart()
		for _, p in cart:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.CanCollide = false
			end
		end
		cart:PivotTo(L(-30 + i * 1.6, 0.85, -6 + i * 0.4) * CFrame.Angles(0, math.rad(90), 0))
		cart.Parent = model
	end
	part(model, Vector3.new(0.3, 3.4, 10), L(-28.5, 1.7, -6), "c9a227", Enum.Material.Metal)
	part(model, Vector3.new(0.3, 3.4, 10), L(-33, 1.7, -6), "c9a227", Enum.Material.Metal)
	-- bollards
	for _, x in { -12, -6, 6, 12 } do
		part(model, Vector3.new(1, 3, 1), L(x, 1.5, -5), "c9a227", Enum.Material.Metal, { Shape = Enum.PartType.Block })
	end
	-- a lonely car
	local car = Instance.new("Model")
	car.Name = "Car"
	part(car, Vector3.new(7, 2.4, 15), L(30, 1.9, 16), "5b1f1f", Enum.Material.Metal)
	part(car, Vector3.new(6.4, 2.2, 8), L(30, 4.2, 15), "3a1414", Enum.Material.Metal)
	part(car, Vector3.new(6.2, 1.8, 0.2), L(30, 4.2, 19.1), "1c2630", Enum.Material.Glass, { Transparency = 0.3 })
	for _, x in { -3.2, 3.2 } do
		for _, z in { 11, 21 } do
			part(car, Vector3.new(1, 2.6, 2.6), L(30 + x, 1.3, z), "111111", Enum.Material.Rubber, { Shape = Enum.PartType.Cylinder })
		end
	end
	car.Parent = model

	model.Parent = root:FindFirstChild("Pads")
	pads[index] = O
	return model
end

function LobbyWorld.Build()
	root = Instance.new("Folder")
	root.Name = "Lobby"
	local padsFolder = Instance.new("Folder")
	padsFolder.Name = "Pads"
	padsFolder.Parent = root
	root.Parent = Workspace
	local n = Config.Party.Pads
	local cols = math.ceil(math.sqrt(n + 1))
	for i = 0, n do
		local cx = (i % cols) * SPACING
		local cz = math.floor(i / cols) * SPACING
		buildPad(i, CFrame.new(cx, 0, cz))
	end
end

function LobbyWorld.PadCFrame(index: number): CFrame
	return pads[index] or pads[0]
end

-- stand the party in a line in front of their store front
function LobbyWorld.Place(party)
	if not party or not party.Members then
		return
	end
	local O = LobbyWorld.PadCFrame(party.Pad or 0)
	local order = { party.Leader }
	for _, p in party.Members do
		if p ~= party.Leader then
			table.insert(order, p)
		end
	end
	for i, p in order do
		local char = p and p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum then
			local slot = SLOTS[i] or SLOTS[#SLOTS]
			local height = hum.HipHeight + (hrp :: BasePart).Size.Y / 2
			if hum.RigType == Enum.HumanoidRigType.R6 then
				height = 3
			end
			hrp.Anchored = true
			char:PivotTo(O * slot * CFrame.new(0, height, 0))
		end
	end
end

function LobbyWorld.Init(Party, Shop)
	Party.Changed:Connect(function(party)
		LobbyWorld.Place(party)
	end)
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(char)
			char:WaitForChild("HumanoidRootPart", 10)
			char:WaitForChild("Humanoid", 10)
			task.wait()
			LobbyWorld.Place(Party.Of(player))
			if Shop then
				Shop.Apply(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

return LobbyWorld
