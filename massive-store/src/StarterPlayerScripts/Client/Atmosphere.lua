--[[
	Atmosphere: lighting and the store's lights, client side (cheap, smooth, no network spam).

	The server only says which departments have power (ReplicatedStorage ZonePower_<id>:
	On / Emergency / Off / Flicker) and the phase. Here we:
	  - blend Lighting (ambient, fog, colour grading) between day / dusk / night / outage
	  - switch ceiling fixtures on, to red emergency mode, or off, and flicker them at dusk
	  - keep a few "faulty" lights buzzing even by day
	  - night vision goggles, downed tint, brightness setting
	  - camera shake (respects the setting)
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Atmosphere = {}

local player = Players.LocalPlayer
local grade = Lighting:FindFirstChild("Grade") :: ColorCorrectionEffect?
local bloom = Lighting:FindFirstChild("Bloom") :: BloomEffect?

local PROFILES = {
	Day = { Ambient = Color3.new(0.36, 0.355, 0.35), Fog = Color3.new(0.38, 0.38, 0.39), FogStart = 160, FogEnd = 720, Bright = 0.02, Contrast = 0.06, Sat = -0.05, Tint = Color3.new(1, 0.99, 0.96), Bloom = 0.45 },
	Dusk = { Ambient = Color3.new(0.17, 0.15, 0.15), Fog = Color3.new(0.12, 0.09, 0.08), FogStart = 80, FogEnd = 420, Bright = 0, Contrast = 0.1, Sat = -0.15, Tint = Color3.new(1, 0.9, 0.84), Bloom = 0.6 },
	Night = { Ambient = Color3.new(0.034, 0.034, 0.045), Fog = Color3.new(0.008, 0.008, 0.012), FogStart = 18, FogEnd = 250, Bright = -0.02, Contrast = 0.16, Sat = -0.35, Tint = Color3.new(0.88, 0.92, 1), Bloom = 0.8 },
	Outage = { Ambient = Color3.new(0.02, 0.02, 0.026), Fog = Color3.new(0.005, 0.005, 0.008), FogStart = 10, FogEnd = 200, Bright = -0.03, Contrast = 0.18, Sat = -0.45, Tint = Color3.new(0.85, 0.9, 1), Bloom = 0.8 },
	Menu = { Ambient = Color3.new(0.05, 0.05, 0.06), Fog = Color3.new(0.01, 0.01, 0.014), FogStart = 10, FogEnd = 220, Bright = 0, Contrast = 0.15, Sat = -0.25, Tint = Color3.new(0.92, 0.94, 1), Bloom = 0.9 },
}
PROFILES.Dawn = PROFILES.Dusk
PROFILES.Waiting = PROFILES.Day
PROFILES.Results = PROFILES.Night

local menu = true
local brightnessSetting = 0
local shakeEnabled = true
local lights: { [BasePart]: any } = {}
local neons: { [BasePart]: boolean } = {}

local RED = Color3.fromRGB(170, 18, 14)
local OFF = Color3.fromRGB(38, 38, 40)

local function zoneMode(zone: number?): string
	if not zone then
		return "On"
	end
	return ReplicatedStorage:GetAttribute("ZonePower_" .. zone) or "On"
end

local function lightObj(part: BasePart): Light?
	return part:FindFirstChildWhichIsA("Light") :: Light?
end

local function setLight(rec, on: boolean, emergency: boolean)
	local part = rec.Part
	local l = rec.Light
	if on then
		if emergency then
			part.Material = Enum.Material.Neon
			part.Color = RED
			if l then
				l.Enabled = true
				l.Color = RED
				l.Brightness = 0.55
			end
		else
			part.Material = Enum.Material.Neon
			part.Color = rec.Base
			if l then
				l.Enabled = true
				l.Color = rec.Base
				l.Brightness = rec.BaseBrightness
			end
		end
	else
		part.Material = Enum.Material.SmoothPlastic
		part.Color = OFF
		if l then
			l.Enabled = false
		end
	end
	rec.On = on
	rec.Emergency = emergency
end

local function applyLight(rec)
	if menu then
		return
	end
	local mode = zoneMode(rec.Zone)
	rec.Mode = mode
	if mode == "On" then
		setLight(rec, true, false)
	elseif mode == "Emergency" then
		setLight(rec, rec.EmergencyLight, rec.EmergencyLight)
	elseif mode == "Flicker" then
		setLight(rec, true, false)
	else
		setLight(rec, false, false)
	end
end

local function track(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local l = lightObj(part)
	local rec = {
		Part = part,
		Light = l,
		Zone = part:GetAttribute("Zone"),
		EmergencyLight = part:GetAttribute("Emergency") == true,
		Base = part:GetAttribute("BaseColor") or part.Color,
		BaseBrightness = if l then l.Brightness else 1,
		Faulty = (part:GetAttribute("Seed") or 1) % 11 == 0,
	}
	lights[part] = rec
	applyLight(rec)
end

local function applyNeon(part: BasePart)
	if menu then
		return
	end
	local mode = zoneMode(part:GetAttribute("Zone"))
	if mode == "On" or mode == "Flicker" then
		part.Material = Enum.Material.Neon
		part.Color = part:GetAttribute("BaseColor") or part.Color
	else
		part.Material = Enum.Material.SmoothPlastic
		part.Color = (part:GetAttribute("BaseColor") or part.Color):Lerp(Color3.new(0, 0, 0), 0.75)
	end
end

local function refreshAll()
	for _, rec in lights do
		applyLight(rec)
	end
	for part in neons do
		applyNeon(part)
	end
end

function Atmosphere.SetMenu(on: boolean)
	menu = on
	if not on then
		refreshAll()
	end
end

function Atmosphere.SetBrightness(v: number)
	brightnessSetting = v
end

function Atmosphere.SetShake(on: boolean)
	shakeEnabled = on
end

--============================ CAMERA SHAKE ============================--
local shakeAmount, shakeUntil = 0, 0
function Atmosphere.Shake(intensity: number, duration: number)
	if not shakeEnabled then
		return
	end
	shakeAmount = math.max(shakeAmount, intensity)
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
end

local flickerUntil = 0
function Atmosphere.FlickerFlashlight(seconds: number)
	flickerUntil = os.clock() + seconds
end

--============================ LOOPS ============================--
local function lerpLighting(dt: number)
	local phase = ReplicatedStorage:GetAttribute("Phase") or "Waiting"
	local key = phase
	if menu then
		key = "Menu"
	elseif ReplicatedStorage:GetAttribute("Outage") then
		key = "Outage"
	end
	local p = PROFILES[key] or PROFILES.Day
	local k = math.clamp(dt * 0.8, 0, 1)
	local amb = p.Ambient
	local nv = player:GetAttribute("NightVision") and not menu
	if nv then
		amb = Color3.new(0.42, 0.48, 0.42)
	end
	Lighting.Ambient = Lighting.Ambient:Lerp(amb, k)
	Lighting.OutdoorAmbient = Lighting.OutdoorAmbient:Lerp(amb, k)
	Lighting.FogColor = Lighting.FogColor:Lerp(if nv then Color3.new(0.05, 0.12, 0.05) else p.Fog, k)
	Lighting.FogStart += ((if nv then 60 else p.FogStart) - Lighting.FogStart) * k
	Lighting.FogEnd += ((if nv then 380 else p.FogEnd) - Lighting.FogEnd) * k
	Lighting.ExposureCompensation += (brightnessSetting * 0.35 - Lighting.ExposureCompensation) * k
	if grade then
		local downed = player:GetAttribute("Downed") and not menu
		local tint = p.Tint
		local sat = p.Sat
		local bright = p.Bright
		if nv then
			tint = Color3.new(0.55, 1, 0.55)
			sat = -1
			bright = 0.12
		elseif downed then
			tint = Color3.new(1, 0.6, 0.6)
			sat = -0.75
		end
		grade.TintColor = grade.TintColor:Lerp(tint, k)
		grade.Saturation += (sat - grade.Saturation) * k
		grade.Brightness += (bright - grade.Brightness) * k
		grade.Contrast += (p.Contrast - grade.Contrast) * k
	end
	if bloom then
		bloom.Intensity += (p.Bloom - bloom.Intensity) * k
	end
end

local flickT = 0
local function flicker(dt: number)
	flickT += dt
	if flickT < 0.07 or menu then
		return
	end
	flickT = 0
	local cam = Workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	for _, rec in lights do
		if rec.Part.Parent then
			if rec.Mode == "Flicker" or (rec.Faulty and rec.Mode == "On") then
				if (rec.Part.Position - camPos).Magnitude < 260 then
					local p = if rec.Mode == "Flicker" then 0.35 else 0.04
					if math.random() < p then
						setLight(rec, not rec.On, false)
					elseif not rec.On and math.random() < 0.5 then
						setLight(rec, true, false)
					end
				end
			end
		end
	end
	-- local flashlight flicker (Locust shriek)
	if os.clock() < flickerUntil then
		local char = player.Character
		local head = char and char:FindFirstChild("Head")
		local fl = head and head:FindFirstChild("Flashlight") :: SpotLight?
		if fl then
			fl.Enabled = math.random() < 0.4
		end
	elseif flickerUntil > 0 then
		flickerUntil = 0
		local char = player.Character
		local head = char and char:FindFirstChild("Head")
		local fl = head and head:FindFirstChild("Flashlight") :: SpotLight?
		if fl then
			fl.Enabled = true
		end
	end
end

function Atmosphere.Init()
	for _, p in CollectionService:GetTagged("StoreLight") do
		track(p)
	end
	CollectionService:GetInstanceAddedSignal("StoreLight"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("StoreLight"):Connect(function(p)
		lights[p] = nil
	end)
	for _, tag in { "StoreNeon", "Screen" } do
		for _, p in CollectionService:GetTagged(tag) do
			if p:IsA("BasePart") then
				neons[p] = true
				applyNeon(p)
			end
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(p)
			if p:IsA("BasePart") then
				neons[p] = true
				applyNeon(p)
			end
		end)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(p)
			neons[p] = nil
		end)
	end
	-- zone power changes
	ReplicatedStorage.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 10) == "ZonePower_" then
			local zone = tonumber(string.sub(name, 11))
			for _, rec in lights do
				if rec.Zone == zone then
					applyLight(rec)
				end
			end
			for part in neons do
				if part:GetAttribute("Zone") == zone then
					applyNeon(part)
				end
			end
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		lerpLighting(dt)
		flicker(dt)
	end)
	-- shake after the camera updates
	RunService:BindToRenderStep("MSL_Shake", Enum.RenderPriority.Camera.Value + 1, function()
		local now = os.clock()
		if now < shakeUntil then
			local cam = Workspace.CurrentCamera
			local a = shakeAmount * math.clamp((shakeUntil - now) * 2, 0, 1)
			cam.CFrame *= CFrame.Angles(math.rad((math.random() - 0.5) * a), math.rad((math.random() - 0.5) * a), 0)
		else
			shakeAmount = 0
		end
	end)
end

return Atmosphere
