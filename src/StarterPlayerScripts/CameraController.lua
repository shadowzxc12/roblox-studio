--[[
	CameraController
	- Menu camera: slow orbit around the 3D menu scene with depth of field.
	- Shake: short camera shake (only if the "Camera Shake" setting is on).
	Connections only exist while they are needed (no permanent RenderStepped).
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ClientState = require(script.Parent.ClientState)

local CameraController = {}

local player = Players.LocalPlayer
local menuConn: RBXScriptConnection? = nil
local dof: DepthOfFieldEffect? = nil

local function getDOF(): DepthOfFieldEffect
	if not dof then
		local d = Instance.new("DepthOfFieldEffect")
		d.Name = "MenuDepthOfField"
		d.FarIntensity = 0.55
		d.NearIntensity = 0.3
		d.FocusDistance = 28
		d.InFocusRadius = 16
		d.Enabled = false
		d.Parent = Lighting
		dof = d
	end
	return dof :: DepthOfFieldEffect
end

function CameraController.StartMenu(focus: Vector3)
	CameraController.StopMenu()
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	getDOF().Enabled = true
	local radius, height = 30, 9
	local started = os.clock()
	menuConn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		local angle = t * 0.08
		local pos = focus + Vector3.new(math.cos(angle) * radius, height + math.sin(t * 0.4) * 1.5, math.sin(angle) * radius)
		cam.CFrame = CFrame.lookAt(pos, focus + Vector3.new(0, 3, 0))
	end)
end

function CameraController.StopMenu()
	if menuConn then
		menuConn:Disconnect()
		menuConn = nil
	end
	if dof then
		dof.Enabled = false
	end
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		cam.CameraSubject = hum
	end
end

function CameraController.IsInMenu(): boolean
	return menuConn ~= nil
end

-- Short shake using the humanoid CameraOffset (works with the default camera).
function CameraController.Shake(intensity: number?, duration: number?)
	if not ClientState.Settings.CameraShake then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local strength = intensity or 0.5
	local length = duration or 0.35
	local started = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		if t >= length or not hum.Parent then
			conn:Disconnect()
			hum.CameraOffset = Vector3.zero
			return
		end
		local fade = 1 - t / length
		hum.CameraOffset = Vector3.new(
			(math.random() - 0.5) * strength * fade,
			(math.random() - 0.5) * strength * fade,
			(math.random() - 0.5) * strength * fade
		)
	end)
end

-- Gentle field-of-view kick (round start etc.)
function CameraController.Punch()
	local cam = workspace.CurrentCamera
	cam.FieldOfView = 80
	TweenService:Create(cam, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { FieldOfView = 70 }):Play()
end

return CameraController
