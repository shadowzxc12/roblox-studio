--[[
	ClientState: the client's read-only copy of PlayerData + local settings.
	The server sends DataUpdated whenever data changes. Settings are applied locally right away
	and the server is asked to save them (it validates the request).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sounds = require(ReplicatedStorage.Modules.Sounds)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local ClientState = {}
ClientState.Data = nil
ClientState.Settings = { Music = true, SoundEffects = true, ShowEffects = true, CameraShake = true }
ClientState.DataChanged = Instance.new("BindableEvent")
ClientState.SettingsChanged = Instance.new("BindableEvent")

local settingsLoaded = false

local function setEffectVisible(inst: Instance)
	if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") then
		inst.Enabled = ClientState.Settings.ShowEffects
	end
end

local function applySettings()
	local s = ClientState.Settings
	Sounds.SetMusicEnabled(s.Music)
	Sounds.SetSFXEnabled(s.SoundEffects)
	for _, inst in CollectionService:GetTagged("OptionalEffect") do
		setEffectVisible(inst)
	end
	ClientState.SettingsChanged:Fire(s)
end

function ClientState.SetSetting(key: string, value: boolean)
	if ClientState.Settings[key] == nil then
		return
	end
	ClientState.Settings[key] = value
	applySettings()
	Remotes.RequestSettings:FireServer(key, value)
end

local function onData(snapshot)
	if type(snapshot) ~= "table" then
		return
	end
	ClientState.Data = snapshot
	if not settingsLoaded and type(snapshot.Settings) == "table" then
		settingsLoaded = true
		for k, v in snapshot.Settings do
			if ClientState.Settings[k] ~= nil and type(v) == "boolean" then
				ClientState.Settings[k] = v
			end
		end
		applySettings()
	end
	ClientState.DataChanged:Fire(snapshot)
end

function ClientState.Init()
	Remotes.DataUpdated.OnClientEvent:Connect(onData)
	CollectionService:GetInstanceAddedSignal("OptionalEffect"):Connect(setEffectVisible)
	task.spawn(function()
		local ok, snap = pcall(function()
			return Remotes.RequestData:InvokeServer()
		end)
		if ok and snap then
			onData(snap)
		end
	end)
end

return ClientState
