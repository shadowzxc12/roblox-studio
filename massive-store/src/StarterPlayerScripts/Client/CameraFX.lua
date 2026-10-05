--[[
	CameraFX: special cameras.
	  Hiding     peek out of the locker / stall / vent (scriptable camera with slow breathing sway)
	  Spectate   when you're dead: follow living teammates ([Q] / [E] or the arrows to switch)
	  Infected   survivors nearby glow through walls for infected players
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local UI = require(script.Parent.UI)
local ClientState = require(script.Parent.ClientState)

local CameraFX = {}

local player = Players.LocalPlayer
local mode = "Default"
local spectateIndex = 1
local highlights: { [Player]: Highlight } = {}
local label

local function hideSpotPart(): BasePart?
	local id = player:GetAttribute("HideSpot") or 0
	if id == 0 then
		return nil
	end
	local store = Workspace:FindFirstChild("Store")
	local hiding = store and store:FindFirstChild("Hiding")
	return hiding and hiding:FindFirstChild("Hide" .. id) :: BasePart?
end

local function living()
	local out = {}
	for _, p in Players:GetPlayers() do
		if p ~= player and p:GetAttribute("InRun") and not p:GetAttribute("Dead") and p.Character and p.Character:FindFirstChildOfClass("Humanoid") then
			table.insert(out, p)
		end
	end
	return out
end

function CameraFX.Cycle(dir: number)
	spectateIndex += dir
end

local function setMode(m: string)
	if mode == m then
		return
	end
	mode = m
	local cam = Workspace.CurrentCamera
	if m == "Default" then
		cam.CameraType = Enum.CameraType.Custom
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			cam.CameraSubject = hum
		end
	elseif m == "Hiding" then
		cam.CameraType = Enum.CameraType.Scriptable
	elseif m == "Spectate" then
		cam.CameraType = Enum.CameraType.Custom
	end
	label.Visible = m == "Spectate"
end

local function update()
	if ClientState.MenuOpen then
		return
	end
	local cam = Workspace.CurrentCamera
	if player:GetAttribute("Hidden") then
		local part = hideSpotPart()
		if part then
			setMode("Hiding")
			local t = os.clock()
			local sway = CFrame.Angles(math.rad(math.sin(t * 0.9) * 1.2), math.rad(math.sin(t * 0.6) * 2.5), 0)
			cam.CFrame = part.CFrame * CFrame.new(0, 1.6, -0.6) * sway
			cam.FieldOfView = 60
			return
		end
	end
	if player:GetAttribute("Dead") and player:GetAttribute("InRun") then
		setMode("Spectate")
		local list = living()
		if #list > 0 then
			spectateIndex = ((spectateIndex - 1) % #list) + 1
			local target = list[spectateIndex]
			local hum = target.Character:FindFirstChildOfClass("Humanoid")
			if hum and cam.CameraSubject ~= hum then
				cam.CameraSubject = hum
			end
			label.Text = "SPECTATING " .. string.upper(target.DisplayName) .. "   [Q] / [E] switch"
		else
			label.Text = "WAITING FOR DAWN..."
		end
		return
	end
	setMode("Default")
	if cam.FieldOfView ~= 70 and mode == "Default" then
		cam.FieldOfView = 70
	end
end

local function updateHighlights()
	local infected = player:GetAttribute("Infected") == true
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	for _, p in Players:GetPlayers() do
		if p ~= player then
			local h = highlights[p]
			local pc = p.Character
			local pr = pc and pc:FindFirstChild("HumanoidRootPart")
			local show = infected and pr and root and not p:GetAttribute("Infected") and not p:GetAttribute("Dead") and (pr.Position - root.Position).Magnitude < 70
			if show then
				if not h or h.Adornee ~= pc then
					if h then
						h:Destroy()
					end
					h = Instance.new("Highlight")
					h.FillColor = Color3.fromHex("7cff4f")
					h.FillTransparency = 0.7
					h.OutlineColor = Color3.fromHex("7cff4f")
					h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					h.Adornee = pc
					h.Parent = Workspace.CurrentCamera
					highlights[p] = h
				end
			elseif h then
				h:Destroy()
				highlights[p] = nil
			end
		end
	end
end

function CameraFX.Init()
	local _, root = UI.screen("MSL_Spectate", 2)
	label = UI.text(root, "", 14, UI.C.Text, UI.Caps, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.fromOffset(700, 20), TextXAlignment = Enum.TextXAlignment.Center, Visible = false })
	RunService:BindToRenderStep("MSL_CameraFX", Enum.RenderPriority.Camera.Value + 2, update)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or mode ~= "Spectate" then
			return
		end
		if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.ButtonL1 then
			CameraFX.Cycle(-1)
		elseif input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.ButtonR1 then
			CameraFX.Cycle(1)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			pcall(updateHighlights)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		if highlights[p] then
			highlights[p]:Destroy()
			highlights[p] = nil
		end
	end)
end

function CameraFX.Reset()
	mode = "None"
	setMode("Default")
end

return CameraFX
