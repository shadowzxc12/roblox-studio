--[[
	LobbyCamera: a slow cinematic camera on your party's lineup in front of the store.
	  Main  wide shot, the lineup sits in the gap between the menu and the party panel
	  Run   pushes in on the store doors
	  Page  blurred background behind the full-screen pages
	The mouse adds a little parallax so the scene feels alive.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LobbyCamera = {}

local player = Players.LocalPlayer
local focus = "Main"
local active = false
local blur: BlurEffect? = nil
local current: CFrame? = nil

local OFFSETS = {
	Main = CFrame.new(0, 0, 0),
	Run = CFrame.new(0, 1.2, -7) * CFrame.Angles(math.rad(6), 0, 0),
	Page = CFrame.new(0, 0.5, -3),
}

local function padCam(): CFrame?
	local lobby = Workspace:FindFirstChild("Lobby")
	local pads = lobby and lobby:FindFirstChild("Pads")
	local pad = pads and pads:FindFirstChild("Pad" .. tostring(player:GetAttribute("Pad") or 0))
	return pad and pad:GetAttribute("Cam")
end

function LobbyCamera.SetFocus(name: string)
	focus = name
	if blur and active then
		local want = if name == "Page" then 14 elseif name == "Run" then 4 else 0
		game:GetService("TweenService"):Create(blur, TweenInfo.new(0.35), { Size = want }):Play()
	end
end

function LobbyCamera.SetActive(on: boolean)
	if active == on then
		return
	end
	active = on
	current = nil
	if not on then
		if blur then
			blur.Size = 0
		end
		local cam = Workspace.CurrentCamera
		if cam then
			cam.CameraType = Enum.CameraType.Custom
			cam.FieldOfView = 70
		end
	end
end

local function step(dt: number)
	if not active then
		return
	end
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local base = padCam()
	if not base then
		return
	end
	cam.CameraType = Enum.CameraType.Scriptable
	local vp = cam.ViewportSize
	local m = UserInputService:GetMouseLocation()
	local nx = if vp.X > 0 then (m.X / vp.X - 0.5) else 0
	local ny = if vp.Y > 0 then (m.Y / vp.Y - 0.5) else 0
	local t = os.clock()
	local drift = CFrame.new(math.sin(t * 0.21) * 0.35, math.sin(t * 0.33) * 0.15, 0)
		* CFrame.Angles(math.rad(-ny * 2.2 + math.sin(t * 0.4) * 0.3), math.rad(-nx * 3.5), 0)
	local target = base * (OFFSETS[focus] or OFFSETS.Main) * drift
	if not current then
		current = target
	end
	current = (current :: CFrame):Lerp(target, math.clamp(dt * 3, 0, 1))
	cam.CFrame = current :: CFrame
	cam.FieldOfView = 50
end

function LobbyCamera.Init()
	blur = Instance.new("BlurEffect")
	blur.Name = "MSL_LobbyBlur"
	blur.Size = 0
	blur.Parent = Lighting
	RunService:BindToRenderStep("MSL_LobbyCamera", Enum.RenderPriority.Camera.Value + 1, step)
	player:GetAttributeChangedSignal("Pad"):Connect(function()
		current = nil -- cut to the new pad
	end)
end

return LobbyCamera
