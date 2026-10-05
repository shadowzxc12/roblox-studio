--[[
	RoleManager: the ONLY place that changes a player's role.
	The role is stored as a player attribute ("Role") which replicates to every client
	(clients can read it, but only the server can change it).
	Also creates the role visuals: outline (Highlight), label above the head, small particles.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Modules.Config)

local RoleManager = {}

local HUNTER_ROLES = { Chaser = true, Infected = true }

local function getHumanoid(player: Player): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

function RoleManager.Get(player: Player): string?
	return player:GetAttribute("Role")
end

function RoleManager.IsHunter(role: string?): boolean
	return role ~= nil and HUNTER_ROLES[role] == true
end

-- Walk speed comes from the role; frozen players can't move (countdown / head start).
function RoleManager.ApplyMovement(player: Player)
	local hum = getHumanoid(player)
	if not hum then
		return
	end
	if player:GetAttribute("Frozen") then
		hum.WalkSpeed = 0
		hum.JumpHeight = 0
	else
		local role = RoleManager.Get(player)
		hum.WalkSpeed = if RoleManager.IsHunter(role) then Config.Movement.HunterSpeed else Config.Movement.RunnerSpeed
		hum.JumpHeight = Config.Movement.JumpHeight
	end
end

function RoleManager.SetFrozen(player: Player, frozen: boolean)
	player:SetAttribute("Frozen", frozen or nil)
	RoleManager.ApplyMovement(player)
end

local function clearVisuals(char: Model)
	local old = char:FindFirstChild("RoleVisuals")
	if old then
		old:Destroy()
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local fx = hrp and hrp:FindFirstChild("RoleParticles")
	if fx then
		fx:Destroy()
	end
end

local function applyVisuals(player: Player)
	local char = player.Character
	if not char then
		return
	end
	clearVisuals(char)
	local role = RoleManager.Get(player)
	local look = role and Config.Roles[role]
	if not look then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "RoleVisuals"

	if look.Highlight then
		local hl = Instance.new("Highlight")
		hl.FillColor = look.Color
		hl.FillTransparency = 0.7
		hl.OutlineColor = look.Outline or look.Color
		hl.OutlineTransparency = 0
		-- hunters show through walls so runners always know where the danger is
		hl.DepthMode = if look.AlwaysOnTop then Enum.HighlightDepthMode.AlwaysOnTop else Enum.HighlightDepthMode.Occluded
		hl.Adornee = char
		hl.Parent = folder
	end

	local head = char:FindFirstChild("Head")
	if head then
		local bb = Instance.new("BillboardGui")
		bb.Name = "RoleLabel"
		bb.Adornee = head
		bb.Size = UDim2.fromScale(5, 1.1)
		bb.StudsOffset = Vector3.new(0, 2.6, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 90
		bb.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = look.Label
		label.TextColor3 = look.Color
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromHex("1b1530")
		stroke.Parent = label
		label.Parent = bb
		bb.Parent = folder
	end

	-- small particle effect for hunters (clients can hide it with the "Show Effects" setting)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp and RoleManager.IsHunter(role) then
		local pe = Instance.new("ParticleEmitter")
		pe.Name = "RoleParticles"
		pe.Color = ColorSequence.new(look.Color, look.Outline or look.Color)
		pe.LightEmission = 0.6
		pe.Rate = 12
		pe.Lifetime = NumberRange.new(0.5, 0.9)
		pe.Speed = NumberRange.new(1, 3)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		pe.Transparency = NumberSequence.new(0.2, 1)
		CollectionService:AddTag(pe, "OptionalEffect")
		pe.Parent = hrp
	end

	folder.Parent = char
end

-- Set (or clear with nil) a player's role. Server only.
function RoleManager.Set(player: Player, role: string?)
	player:SetAttribute("Role", role)
	applyVisuals(player)
	RoleManager.ApplyMovement(player)
end

function RoleManager.ClearAll()
	for _, p in Players:GetPlayers() do
		p:SetAttribute("Frozen", nil)
		RoleManager.Set(p, nil)
	end
end

function RoleManager.Init()
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(char)
			char:WaitForChild("HumanoidRootPart", 5)
			char:WaitForChild("Head", 5)
			applyVisuals(player)
			RoleManager.ApplyMovement(player)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

return RoleManager
