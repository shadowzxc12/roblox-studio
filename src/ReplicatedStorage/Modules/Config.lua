--[[
	Config: every tunable number of the game in one place.
	Shared by server and client (the client only READS it for display; the server enforces it).
]]

local Config = {}

Config.GameName = "STUD CHASE"
Config.Version = "1.0.0"

-- Game modes -------------------------------------------------------------------
-- To add a mode: add an entry here AND a module with the same Id in ServerScriptService/Modes.
Config.ModeOrder = { "Normal", "Infection" }
Config.Modes = {
	Normal = {
		Id = "Normal",
		DisplayName = "NORMAL CHASE",
		Description = "One player starts as the Chaser. Catch players to become the Chaser yourself. Survive until the timer ends!",
		RecommendedPlayers = "4 - 12",
		RoundLength = 150, -- seconds
		Difficulty = 1, -- 1..3 stars
		HunterRole = "Chaser",
		PreyRole = "Runner",
		HunterTeam = "CHASERS",
		PreyTeam = "RUNNERS",
		Color = Color3.fromHex("ff6a3d"),
		ColorDark = Color3.fromHex("c63a17"),
		StartText = "THE CHASE BEGINS!",
	},
	Infection = {
		Id = "Infection",
		DisplayName = "INFECTION",
		Description = "One player starts infected. Catch Survivors and infect them. Can anyone survive?",
		RecommendedPlayers = "6 - 12",
		RoundLength = 120,
		Difficulty = 2,
		HunterRole = "Infected",
		PreyRole = "Survivor",
		HunterTeam = "INFECTED",
		PreyTeam = "SURVIVORS",
		Color = Color3.fromHex("6ad13a"),
		ColorDark = Color3.fromHex("2f8a1f"),
		StartText = "RUN!",
	},
}

-- How a role looks (label above the character, highlight colours) ----------------
Config.Roles = {
	Chaser = { Label = "CHASER", Color = Color3.fromHex("ff4a2e"), Outline = Color3.fromHex("ffb21c"), Highlight = true, AlwaysOnTop = true },
	Runner = { Label = "RUNNER", Color = Color3.fromHex("4cc3ff") },
	Infected = { Label = "INFECTED", Color = Color3.fromHex("7dff4a"), Outline = Color3.fromHex("9b4dff"), Highlight = true, AlwaysOnTop = true },
	Survivor = { Label = "SURVIVOR", Color = Color3.fromHex("ffffff") },
}

-- Movement (same for everyone except a tiny edge for hunters so catching is possible)
Config.Movement = {
	RunnerSpeed = 16,
	HunterSpeed = 17.5,
	JumpHeight = 7.2,
}

-- Round flow ---------------------------------------------------------------------
Config.Round = {
	MinPlayers = 2, -- a round needs at least this many players
	MaxPlayers = 12,
	IntermissionTime = 15, -- seconds between rounds once enough players are here
	FullServerIntermission = 6, -- shorter wait when the server is full
	CountdownSteps = { "3", "2", "1", "GO!" },
	HunterReleaseDelay = 3, -- runners get a head start
	ResultsTime = 10,
	ReturnTime = 2,
	TickRate = 0.25, -- how often the round manager checks win conditions
}

-- Tagging (server-side) ----------------------------------------------------------
Config.Tag = {
	Range = 5.5, -- studs between HumanoidRootParts
	MaxHeightDifference = 6,
	CheckInterval = 0.1,
	HunterCooldown = 1.0, -- after any tag, the tagger waits this long
	NewHunterDelay = 2.0, -- a freshly made hunter can't tag anyone for this long
	NoTagBackTime = 6.0, -- ...and can't tag the player who just tagged them for this long
	SpeedLimitMultiplier = 1.6, -- anti-teleport: moving faster than this * WalkSpeed (+ slack) is suspicious
	SpeedSlack = 12,
	SuspiciousTime = 2,
}

-- Rewards (granted only by the server) --------------------------------------------
Config.Rewards = {
	Participation = { Coins = 10, XP = 20 }, -- played most of the round
	MinParticipation = 0.5, -- fraction of the round you must have played
	MinRoundLength = 30, -- rounds shorter than this give no participation/win rewards (anti-farming)
	Win = { Coins = 25, XP = 50 },
	Catch = { Coins = 5, XP = 10 }, -- per catch / infection
	MaxCatchesRewarded = 10,
	SurvivalPer30s = { Coins = 3, XP = 6 },
}

-- Levels: XP needed to go from level L to L+1
function Config.XPForLevel(level: number): number
	return 100 + (level - 1) * 50
end

-- Matchmaking ----------------------------------------------------------------------
Config.Matchmaking = {
	PollInterval = 2, -- seconds between matchmaking passes in a lobby
	MaxWait = 12, -- after this long a match server is created even with fewer players
	MinToCreate = 2, -- players needed in the queue to create a match right away
	MatchTTL = 90, -- memory store entries expire if a match stops reporting
	HeartbeatInterval = 5,
}

Config.DataStoreName = "StudChase_PlayerData_v1"

-- Settings the player can toggle (all ON by default)
Config.SettingKeys = { "Music", "SoundEffects", "ShowEffects", "CameraShake" }
Config.SettingLabels = {
	Music = "Music",
	SoundEffects = "Sound Effects",
	ShowEffects = "Show Effects",
	CameraShake = "Camera Shake",
}

return Config
