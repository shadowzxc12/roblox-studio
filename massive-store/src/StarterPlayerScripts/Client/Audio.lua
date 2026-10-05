--[[
	Audio: all sound design, client side.

	No uploaded audio is required: every sound is a "recipe" layering Roblox's built-in
	sounds (rbxasset://sounds/...) with pitch, distortion, EQ and reverb. To use your own
	audio, replace an Id in LIB below with "rbxassetid://<your id>" (the recipe keeps working).

	Day:   quiet supermarket ambience (fridge hum, ventilation, distant clatter, buzzing lights)
	Night: low drones, distant metal impacts, skittering, groans, breathing, screeches.
	       The director also drops into SILENCE now and then — silence is scarier than music.
	Heartbeat follows the Locust's distance. The Locust itself carries 3D sounds (steps,
	clicks, breathing) that the animator triggers in sync with its legs.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Audio = {}

local player = Players.LocalPlayer

local S = {
	Step = "rbxasset://sounds/action_footsteps_plastic.mp3",
	Jump = "rbxasset://sounds/action_jump.mp3",
	Land = "rbxasset://sounds/action_jump_land.mp3",
	Fall = "rbxasset://sounds/action_falling.mp3",
	GetUp = "rbxasset://sounds/action_get_up.mp3",
	Swim = "rbxasset://sounds/action_swim.mp3",
	Splash = "rbxasset://sounds/impact_water.mp3",
	Swoosh = "rbxasset://sounds/swoosh.wav",
	Button = "rbxasset://sounds/button.wav",
	ClickFast = "rbxasset://sounds/clickfast.wav",
	Ping = "rbxasset://sounds/electronicpingshort.wav",
	Snap = "rbxasset://sounds/snap.wav",
	Hit = "rbxasset://sounds/hit.wav",
	Glass = "rbxasset://sounds/glassbreak.wav",
	Splat = "rbxasset://sounds/splat.wav",
	Groan = "rbxasset://sounds/uuhhh.mp3",
	Shot = "rbxasset://sounds/Rocket shot.wav",
	Whoosh = "rbxasset://sounds/Rocket whoosh 01.wav",
	Engine = "rbxasset://sounds/Launching rocket.wav",
	Collide = "rbxasset://sounds/collide.wav",
}
Audio.Ids = S

-- recipes: list of layers { Id, Speed, Volume, Delay, Distort, Low (eq low gain), High (eq high gain), Pitch, Reverb }
local LIB = {
	-- UI
	Hover = { { Id = S.ClickFast, Speed = 2.2, Volume = 0.08 } },
	Click = { { Id = S.Button, Speed = 1.1, Volume = 0.3 } },
	Open = { { Id = S.Swoosh, Speed = 1.6, Volume = 0.18 } },
	Close = { { Id = S.Swoosh, Speed = 1.2, Volume = 0.12 } },
	Notify = { { Id = S.Ping, Speed = 1.2, Volume = 0.25 } },
	Warn = { { Id = S.Ping, Speed = 0.7, Volume = 0.3 } },
	Good = { { Id = S.Ping, Speed = 1.5, Volume = 0.25 }, { Id = S.Ping, Speed = 2, Volume = 0.2, Delay = 0.09 } },
	Legendary = { { Id = S.Ping, Speed = 1.2, Volume = 0.3 }, { Id = S.Ping, Speed = 1.6, Volume = 0.3, Delay = 0.1 }, { Id = S.Ping, Speed = 2.1, Volume = 0.3, Delay = 0.2 } },
	LevelUp = { { Id = S.Ping, Speed = 1, Volume = 0.35 }, { Id = S.Ping, Speed = 1.33, Volume = 0.35, Delay = 0.12 }, { Id = S.Ping, Speed = 1.66, Volume = 0.35, Delay = 0.24 }, { Id = S.Ping, Speed = 2, Volume = 0.4, Delay = 0.36 } },
	XP = { { Id = S.ClickFast, Speed = 1.8, Volume = 0.18 } },
	-- player actions
	Pickup = { { Id = S.Snap, Speed = 1.4, Volume = 0.35 }, { Id = S.Swoosh, Speed = 2.4, Volume = 0.08 } },
	Eat = { { Id = S.Splat, Speed = 1.6, Volume = 0.25 }, { Id = S.Splat, Speed = 1.9, Volume = 0.2, Delay = 0.25 } },
	Hurt = { { Id = S.Hit, Speed = 0.7, Volume = 0.6, Low = 6 }, { Id = S.Groan, Speed = 1.25, Volume = 0.25, Delay = 0.05 } },
	Build = { { Id = S.Hit, Speed = 1.3, Volume = 0.45 }, { Id = S.Hit, Speed = 1.1, Volume = 0.35, Delay = 0.18 } },
	StructureHit = { { Id = S.Collide, Speed = 0.6, Volume = 0.7, Low = 6, Reverb = true }, { Id = S.Hit, Speed = 0.45, Volume = 0.6 } },
	StructureBreak = { { Id = S.Glass, Speed = 0.55, Volume = 0.6 }, { Id = S.Collide, Speed = 0.4, Volume = 0.8, Low = 8 } },
	FlashClick = { { Id = S.ClickFast, Speed = 0.9, Volume = 0.3 } },
	DoorBang = { { Id = S.Collide, Speed = 0.5, Volume = 0.9, Low = 6, Reverb = true }, { Id = S.Hit, Speed = 0.35, Volume = 0.5 } },
	Swing = { { Id = S.Swoosh, Speed = 1.3, Volume = 0.35 } },
	HitLocust = { { Id = S.Hit, Speed = 0.8, Volume = 0.6 }, { Id = S.Snap, Speed = 0.6, Volume = 0.4 } },
	Zap = { { Id = S.Ping, Speed = 0.25, Volume = 0.6, Distort = 0.9 }, { Id = S.Snap, Speed = 2.5, Volume = 0.5, Delay = 0.05 } },
	Flare = { { Id = S.Engine, Speed = 2.2, Volume = 0.35, High = 4 } },
	Ring = { { Id = S.Ping, Speed = 2.6, Volume = 0.55 }, { Id = S.Ping, Speed = 2.6, Volume = 0.55, Delay = 0.15 } },
	Alarm = { { Id = S.Ping, Speed = 0.9, Volume = 0.9, Distort = 0.4, Reverb = true }, { Id = S.Ping, Speed = 0.7, Volume = 0.9, Distort = 0.4, Delay = 0.45 } },
	Refuel = { { Id = S.Swim, Speed = 1.4, Volume = 0.35 } },
	GenStart = { { Id = S.Engine, Speed = 0.35, Volume = 0.5, Low = 6 } },
	GenStop = { { Id = S.Engine, Speed = 0.2, Volume = 0.4, Low = 6 }, { Id = S.ClickFast, Speed = 0.6, Volume = 0.3 } },
	Downed = { { Id = S.Groan, Speed = 0.9, Volume = 0.5 }, { Id = S.Land, Speed = 0.7, Volume = 0.5 } },
	TrapSnap = { { Id = S.Snap, Speed = 0.6, Volume = 1 }, { Id = S.Collide, Speed = 0.7, Volume = 0.7 } },
	Shock = { { Id = S.Ping, Speed = 0.18, Volume = 0.9, Distort = 0.95 }, { Id = S.Snap, Speed = 3, Volume = 0.6 } },
	TurretFire = { { Id = S.Shot, Speed = 2.2, Volume = 0.35 } },
	CameraAlert = { { Id = S.Ping, Speed = 0.55, Volume = 0.5 }, { Id = S.Ping, Speed = 0.55, Volume = 0.5, Delay = 0.25 } },
	RoomOpened = { { Id = S.Collide, Speed = 1.1, Volume = 0.5 }, { Id = S.ClickFast, Speed = 0.8, Volume = 0.4 } },
	SupplyDrop = { { Id = S.Whoosh, Speed = 0.7, Volume = 0.6 }, { Id = S.Collide, Speed = 0.5, Volume = 0.9, Delay = 2, Low = 8, Reverb = true } },
	CartShove = { { Id = S.Collide, Speed = 1.2, Volume = 0.7 }, { Id = S.ClickFast, Speed = 0.5, Volume = 0.4 } },
	PowerDown = { { Id = S.Engine, Speed = 0.12, Volume = 0.6, Low = 8 }, { Id = S.Ping, Speed = 0.3, Volume = 0.4, Distort = 0.5 } },
	PowerUp = { { Id = S.Engine, Speed = 0.3, Volume = 0.4 }, { Id = S.ClickFast, Speed = 0.7, Volume = 0.4 } },
	Lockdown = { { Id = S.Collide, Speed = 0.35, Volume = 0.9, Low = 8, Reverb = true }, { Id = S.Ping, Speed = 0.5, Volume = 0.6, Delay = 0.3 } },
	Dusk = { { Id = S.Engine, Speed = 0.1, Volume = 0.5, Low = 8 }, { Id = S.Ping, Speed = 0.4, Volume = 0.3, Distort = 0.4, Delay = 0.5 } },
	Dawn = { { Id = S.Ping, Speed = 1, Volume = 0.3 }, { Id = S.Ping, Speed = 1.25, Volume = 0.3, Delay = 0.2 }, { Id = S.Ping, Speed = 1.5, Volume = 0.3, Delay = 0.4 } },
	Infected = { { Id = S.Groan, Speed = 0.6, Volume = 0.7, Distort = 0.7 } },
	InfectedSwipe = { { Id = S.Swoosh, Speed = 0.8, Volume = 0.5 } },

	-- THE LOCUST
	LocustStep = { { Id = S.Step, Speed = 0.55, Volume = 0.55, Low = 4 }, { Id = S.Snap, Speed = 1.7, Volume = 0.25 } },
	LocustClick = { { Id = S.Snap, Speed = 2.3, Volume = 0.3 }, { Id = S.Snap, Speed = 2.6, Volume = 0.25, Delay = 0.06 }, { Id = S.Snap, Speed = 2.2, Volume = 0.25, Delay = 0.12 } },
	Shriek = { { Id = S.Whoosh, Speed = 2.3, Volume = 1, Distort = 0.65, Reverb = true }, { Id = S.Groan, Speed = 0.5, Volume = 0.9, Distort = 0.85, Delay = 0.05 }, { Id = S.Glass, Speed = 0.4, Volume = 0.45, Delay = 0.1 } },
	LocustScreech = { { Id = S.Whoosh, Speed = 2.6, Volume = 0.8, Distort = 0.6, Reverb = true }, { Id = S.Groan, Speed = 0.62, Volume = 0.6, Distort = 0.8 } },
	LocustChase = { { Id = S.Groan, Speed = 0.42, Volume = 0.9, Distort = 0.9, Reverb = true }, { Id = S.Whoosh, Speed = 2.9, Volume = 0.5, Distort = 0.5, Delay = 0.15 } },
	LocustAttack = { { Id = S.Swoosh, Speed = 0.7, Volume = 0.8 }, { Id = S.Snap, Speed = 0.9, Volume = 0.7, Delay = 0.2 } },
	LocustHears = { { Id = S.Snap, Speed = 1.2, Volume = 0.4 }, { Id = S.Snap, Speed = 1.4, Volume = 0.35, Delay = 0.1 } },
	LocustSniff = { { Id = S.Swim, Speed = 1.8, Volume = 0.35 }, { Id = S.Swim, Speed = 2, Volume = 0.3, Delay = 0.35 } },
	LocustFound = { { Id = S.Collide, Speed = 0.6, Volume = 1 }, { Id = S.Whoosh, Speed = 2.6, Volume = 0.9, Distort = 0.6 } },
	LocustLost = { { Id = S.Groan, Speed = 0.35, Volume = 0.6, Distort = 0.7, Reverb = true } },
	LocustHiss = { { Id = S.Swim, Speed = 2.6, Volume = 0.6, Distort = 0.5 } },
	LocustStunned = { { Id = S.Groan, Speed = 0.8, Volume = 0.7, Distort = 0.7 }, { Id = S.Snap, Speed = 3, Volume = 0.5 } },
	LocustRetreat = { { Id = S.Whoosh, Speed = 1.8, Volume = 0.9, Distort = 0.6, Reverb = true }, { Id = S.Groan, Speed = 0.3, Volume = 0.8, Distort = 0.9, Delay = 0.3 } },
	LocustLunge = { { Id = S.Swoosh, Speed = 0.5, Volume = 0.8 } },
	LocustSpawn = { { Id = S.Whoosh, Speed = 1.6, Volume = 0.9, Distort = 0.7, Reverb = true }, { Id = S.Groan, Speed = 0.28, Volume = 0.9, Distort = 0.95, Delay = 0.4, Reverb = true } },
	LocustLeave = { { Id = S.Groan, Speed = 0.32, Volume = 0.7, Distort = 0.9, Reverb = true } },
	Roar = { { Id = S.Groan, Speed = 0.25, Volume = 1, Distort = 1, Reverb = true }, { Id = S.Engine, Speed = 0.12, Volume = 0.8, Low = 10 } },
	LightSurge = { { Id = S.Ping, Speed = 0.2, Volume = 0.8, Distort = 0.95 }, { Id = S.Glass, Speed = 0.8, Volume = 0.5, Delay = 0.1 } },
	NymphCall = { { Id = S.Whoosh, Speed = 3.6, Volume = 0.6, Distort = 0.5 } },
	NymphSwarm = { { Id = S.Snap, Speed = 3, Volume = 0.5 }, { Id = S.Snap, Speed = 3.3, Volume = 0.5, Delay = 0.08 }, { Id = S.Snap, Speed = 2.8, Volume = 0.5, Delay = 0.16 } },

	-- ambience one-shots
	AmbClatter = { { Id = S.Collide, Speed = 0.8, Volume = 0.25, Reverb = true } },
	AmbBuzz = { { Id = S.Ping, Speed = 0.22, Volume = 0.12, Distort = 0.3 } },
	AmbSqueak = { { Id = S.ClickFast, Speed = 0.45, Volume = 0.15, Reverb = true } },
	AmbDrip = { { Id = S.Splash, Speed = 2.5, Volume = 0.08, Reverb = true } },
	AmbMetal = { { Id = S.Hit, Speed = 0.35, Volume = 0.35, Low = 6, Reverb = true } },
	AmbSkitter = { { Id = S.Snap, Speed = 2.8, Volume = 0.2 }, { Id = S.Snap, Speed = 3, Volume = 0.2, Delay = 0.05 }, { Id = S.Snap, Speed = 2.6, Volume = 0.2, Delay = 0.11 }, { Id = S.Snap, Speed = 3.1, Volume = 0.15, Delay = 0.17 } },
	AmbGroan = { { Id = S.Groan, Speed = 0.3, Volume = 0.25, Distort = 0.8, Reverb = true } },
	AmbBreath = { { Id = S.Swim, Speed = 0.45, Volume = 0.12, Reverb = true } },
	Heartbeat = { { Id = S.Hit, Speed = 0.45, Volume = 0.6, Low = 10, High = -30 }, { Id = S.Hit, Speed = 0.4, Volume = 0.45, Low = 10, High = -30, Delay = 0.17 } },
	PlayerBreath = { { Id = S.Swim, Speed = 0.9, Volume = 0.12, High = -10 } },
}
Audio.Library = LIB

Audio.SFX = true
Audio.Music = true

local groups = {}
local function group(name: string, volume: number)
	local g = Instance.new("SoundGroup")
	g.Name = name
	g.Volume = volume
	g.Parent = SoundService
	groups[name] = g
	return g
end

local function addEffects(sound: Sound, layer)
	if layer.Distort then
		local d = Instance.new("DistortionSoundEffect")
		d.Level = layer.Distort
		d.Parent = sound
	end
	if layer.Low or layer.High then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = layer.Low or 0
		eq.MidGain = 0
		eq.HighGain = layer.High or 0
		eq.Parent = sound
	end
	if layer.Reverb then
		local r = Instance.new("ReverbSoundEffect")
		r.DecayTime = 2.4
		r.WetLevel = -4
		r.DryLevel = -2
		r.Parent = sound
	end
end

local function emitterAt(position: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.WorldPosition = position
	a.Parent = Workspace.Terrain
	Debris:AddItem(a, 8)
	return a
end

-- play a recipe. where = nil (2D), a Vector3 or an Instance (3D)
function Audio.Play(name: string, where: any?, volumeMult: number?, speedMult: number?)
	local recipe = LIB[name]
	if not recipe then
		return
	end
	local isUI = name == "Hover" or name == "Click" or name == "Open" or name == "Close"
	if not Audio.SFX and not isUI then
		return
	end
	local parent: Instance = SoundService
	if typeof(where) == "Vector3" then
		parent = emitterAt(where)
	elseif typeof(where) == "Instance" then
		parent = where
	end
	for _, layer in recipe do
		local s = Instance.new("Sound")
		s.SoundId = layer.Id
		s.Volume = (layer.Volume or 0.5) * (volumeMult or 1)
		s.PlaybackSpeed = (layer.Speed or 1) * (speedMult or 1) * (0.96 + math.random() * 0.08)
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 12
		s.RollOffMaxDistance = 420
		s.SoundGroup = groups.SFX
		addEffects(s, layer)
		s.Parent = parent
		if layer.Delay and layer.Delay > 0 then
			task.delay(layer.Delay, function()
				if s.Parent then
					s:Play()
				end
			end)
		else
			s:Play()
		end
		Debris:AddItem(s, 6 + (layer.Delay or 0))
	end
end

--============================ AMBIENCE ============================--
local layers = {}
local function loop(name: string, id: string, speed: number, low: number?, distort: number?)
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	s.Looped = true
	s.PlaybackSpeed = speed
	s.Volume = 0
	s.SoundGroup = groups.Ambience
	addEffects(s, { Low = low, Distort = distort, Reverb = true })
	s.Parent = SoundService
	s:Play()
	layers[name] = { Sound = s, Target = 0 }
	return s
end

local function setLayer(name: string, volume: number)
	local l = layers[name]
	if l then
		l.Target = volume
	end
end

local silenceUntil = 0
local menuMode = true

function Audio.SetMenu(on: boolean)
	menuMode = on
end

local function phase()
	return ReplicatedStorage:GetAttribute("Phase") or "Waiting"
end

local function ambienceTargets()
	local p = phase()
	local night = p == "Night"
	local silent = os.clock() < silenceUntil
	local music = if Audio.Music then 1 else 0
	if menuMode then
		setLayer("Hum", 0.08)
		setLayer("Vent", 0.05)
		setLayer("Drone", 0.12 * music)
		setLayer("Deep", 0.06 * music)
		return
	end
	if silent then
		setLayer("Hum", 0.01)
		setLayer("Vent", 0)
		setLayer("Drone", 0)
		setLayer("Deep", 0.02 * music)
		return
	end
	local outage = ReplicatedStorage:GetAttribute("Outage")
	setLayer("Hum", if night or outage then 0.03 else 0.14)
	setLayer("Vent", if night then 0.02 else 0.06)
	setLayer("Drone", (if night then 0.14 elseif p == "Dusk" then 0.1 else 0) * music)
	setLayer("Deep", (if night then 0.1 else 0) * music)
end

local function randomOffset(min: number, max: number): Vector3
	local a = math.random() * math.pi * 2
	local d = min + math.random() * (max - min)
	return Vector3.new(math.cos(a) * d, math.random(2, 12), math.sin(a) * d)
end

local function myPos(): Vector3?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return root and root.Position
end

local heartbeatNext = 0
local breathNext = 0
local function heartbeat()
	local d = player:GetAttribute("LocustDistance")
	local now = os.clock()
	if menuMode or not d or d > 75 or phase() ~= "Night" then
		return
	end
	if now >= heartbeatNext then
		local f = math.clamp(1 - d / 75, 0, 1)
		heartbeatNext = now + (1.15 - f * 0.7)
		Audio.Play("Heartbeat", nil, 0.3 + f * 0.9)
	end
end

local function breathing()
	local now = os.clock()
	if menuMode or now < breathNext then
		return
	end
	local stamina = player:GetAttribute("Stamina") or 100
	if stamina < 35 or player:GetAttribute("Hidden") then
		breathNext = now + (if stamina < 15 then 0.9 else 1.6)
		Audio.Play("PlayerBreath", nil, if player:GetAttribute("Hidden") then 0.5 else 1)
	end
end

function Audio.Cue(kind: string, position: Vector3?, extra: any)
	if LIB[kind] then
		Audio.Play(kind, position)
	end
end

function Audio.Init()
	group("SFX", 0.9)
	group("Ambience", 0.9)
	-- ambience beds
	loop("Hum", S.Engine, 0.11, 6)
	loop("Vent", S.Swim, 0.22, 2)
	loop("Drone", S.Whoosh, 0.09, 8, 0.2)
	loop("Deep", S.Groan, 0.12, 10, 0.5)

	task.spawn(function()
		while true do
			local dt = task.wait(0.1)
			ambienceTargets()
			for _, l in layers do
				local v = l.Sound.Volume
				l.Sound.Volume = v + (l.Target - v) * math.clamp(dt * 1.2, 0, 1)
			end
			heartbeat()
			breathing()
		end
	end)

	-- random one-shots + silence
	task.spawn(function()
		while true do
			task.wait(math.random(5, 14))
			local pos = myPos()
			if pos and not menuMode and os.clock() > silenceUntil then
				local p = phase()
				if p == "Night" then
					if math.random() < 0.12 then
						silenceUntil = os.clock() + math.random(14, 30)
					else
						local pick = ({ "AmbMetal", "AmbSkitter", "AmbGroan", "AmbBreath", "AmbDrip", "AmbMetal" })[math.random(1, 6)]
						Audio.Play(pick, pos + randomOffset(60, 180))
					end
				elseif p == "Day" or p == "Dawn" then
					local pick = ({ "AmbClatter", "AmbBuzz", "AmbSqueak", "AmbDrip" })[math.random(1, 4)]
					Audio.Play(pick, pos + randomOffset(40, 140))
				end
			end
		end
	end)
end

function Audio.SetSFX(on: boolean)
	Audio.SFX = on
end

function Audio.SetMusic(on: boolean)
	Audio.Music = on
end

return Audio
