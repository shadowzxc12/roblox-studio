--[[
	Sounds (client): plays the Sound objects in ReplicatedStorage.Assets.Sounds.
	To change a sound, just change the SoundId of that Sound object in Studio.
	Respects the player's "Sound Effects" and "Music" settings.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local folder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds")

local Sounds = {}
Sounds.SFXEnabled = true
Sounds.MusicEnabled = true

local currentMusic: Sound? = nil
local currentMusicName: string? = nil

function Sounds.Play(name: string, pitch: number?)
	if not Sounds.SFXEnabled then
		return
	end
	local s = folder:FindFirstChild(name)
	if not s or s.SoundId == "" then
		return
	end
	local base = s:GetAttribute("BaseSpeed") or s.PlaybackSpeed
	s:SetAttribute("BaseSpeed", base)
	-- a little random pitch so repeated sounds don't feel robotic
	s.PlaybackSpeed = base * (pitch or (0.95 + math.random() * 0.1))
	SoundService:PlayLocalSound(s)
end

function Sounds.PlayMusic(name: string?)
	if currentMusicName == name and currentMusic then
		return
	end
	if currentMusic then
		currentMusic:Destroy()
		currentMusic = nil
	end
	currentMusicName = name
	if not name then
		return
	end
	local src = folder:FindFirstChild(name)
	if not src or src.SoundId == "" then
		return -- no music uploaded yet: put a SoundId on Assets/Sounds/MenuMusic or MatchMusic
	end
	currentMusic = src:Clone()
	currentMusic.Looped = true
	currentMusic.Parent = SoundService
	if Sounds.MusicEnabled then
		currentMusic:Play()
	end
end

function Sounds.SetMusicEnabled(on: boolean)
	Sounds.MusicEnabled = on
	if currentMusic then
		if on then
			currentMusic:Play()
		else
			currentMusic:Pause()
		end
	end
end

function Sounds.SetSFXEnabled(on: boolean)
	Sounds.SFXEnabled = on
end

return Sounds
