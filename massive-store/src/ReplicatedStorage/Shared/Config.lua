--[[
	Config: every tuning number of MASSIVE STORE: LOCUST lives here.
	Pure data + pure functions (no Roblox services), so it can be required anywhere,
	including the headless tests in /tests.
]]

local Config = {}

Config.GameName = "MASSIVE STORE"
Config.Subtitle = "LOCUST"
Config.Version = "2.0.0"
Config.DataStoreName = "MassiveStoreLocust_v1"
Config.ServerRegistryName = "MSL_Servers_v1"
Config.MaxPlayers = 12

--[[
	Two places in one experience:
	  Lobby  the start place: menu, party, cosmetics, shop. Teleports you into a store.
	  Game   the store itself. Every run is a reserved (private) server just for you / your party.
	Publish both, then put their place ids here (Creator Dashboard -> experience -> Places).
	While an id is 0 (e.g. in Studio) teleports are skipped with a message.
]]
Config.Places = {
	Lobby = 0,
	Game = 0,
}

Config.Party = {
	MaxSize = 4,
	InviteTimeout = 30, -- seconds an invite stays valid
	LobbyModes = { "Survival", "Infection", "Hardcore" },
	Pads = 16, -- party lineups in the lobby parking lot
}

--=============================== MAP ===============================--
Config.Map = {
	Cols = 20, -- main floor cells along X
	Rows = 15, -- main floor cells along Z (row 1 = north / loading docks, last row = south / entrance)
	CellSize = 80,
	LaneWidth = 14, -- the "+" shaped walkway through every cell is always kept clear
	WallHeight = 24,
	WallThickness = 1,
	OpeningWidth = 16,
	OpeningHeight = 16,
	-- underground level (parking garage, underground storage, maintenance tunnels)
	BasementY = -24,
	BasementCols = { 4, 15 },
	BasementRows = { 1, 6 },
	Stairwells = 2,
	LockedRooms = 14,
	HiddenRooms = 6,
	LightsPerCell = 2,
	ProductDetail = 1, -- 0 = fewer decorative products (faster), 1 = full
}

--=============================== DAY / NIGHT ===============================--
Config.Cycle = {
	FirstDay = 300, -- seconds of the very first day (more time to learn)
	Day = 270,
	Dusk = 20, -- lights flicker, warning
	NightBase = 200,
	NightPerNight = 4, -- each night lasts a little longer...
	NightMax = 300,
	Dawn = 12,
	WipeResults = 18, -- results screen before the store resets after everyone fell
	DayStartClock = 7, -- 07:00
	DayEndClock = 20, -- 20:00 (dusk)
	NightEndClock = 6, -- 06:00
}

function Config.NightLength(night: number): number
	return math.min(Config.Cycle.NightMax, Config.Cycle.NightBase + Config.Cycle.NightPerNight * (night - 1))
end

--=============================== PLAYER SURVIVAL ===============================--
Config.Survival = {
	MaxHealth = 100,
	MaxHunger = 100,
	MaxStamina = 100,
	MaxEnergy = 100,
	HungerDrainPerMinute = 5.5,
	EnergyDrainPerMinute = 3.5,
	StarveDamagePerSecond = 1,
	ExhaustedEnergy = 15, -- below this you can't sprint and stamina regenerates slowly
	FedRegenThreshold = 65, -- above this hunger, health slowly regenerates
	HealthRegenPerSecond = 0.35,
	StaminaSprintDrain = 13,
	StaminaRegen = 11,
	StaminaRegenDelay = 1.0,
	WalkSpeed = 14,
	SprintSpeed = 24,
	CrouchSpeed = 7,
	DownedSpeed = 3,
	CartPenalty = { 0.25, 0.16, 0.08 }, -- walk speed penalty while pushing a cart (cart tier 1..3)
	BleedOutTime = 45,
	ReviveTime = 4,
	ReviveHealth = 35,
	SelfReviveTime = 6,
	SpawnProtection = 6,
	MaxReach = 12, -- server-side reach for picking up / opening
	BuildReach = 26,
}

--=============================== NOISE ===============================--
-- loudness 1.0 = heard from Locust.HearingRange studs away (scaled by night)
Config.Noise = {
	Walk = 0.22,
	Sprint = 0.85,
	Crouch = 0.04,
	Jump = 0.35,
	CartPush = 0.55,
	CartPushFast = 0.4,
	Build = 0.9,
	Break = 1.0,
	DoorOpen = 0.4,
	Generator = 0.35, -- emitted continuously by running generators
	Turret = 1.2,
	Pickup = 0.08,
	Eat = 0.1,
	Flare = 2.0,
	NoiseMaker = 2.4,
	Alarm = 3.0,
	Revive = 0.3,
	Lifetime = 2.5, -- a noise event is "audible" for this long
}

--=============================== THE LOCUST ===============================--
Config.Locust = {
	Height = 11,
	AttackRange = 6.5,
	CloseSenseRadius = 9, -- hears breathing, always notices you this close (unless hidden)
	FOV = 110,
	DarkSightMultiplier = 0.45,
	EmergencySightMultiplier = 0.75,
	FlashlightSightMultiplier = 1.7,
	CrouchSightMultiplier = 0.7,
	BaseResolve = 120,
	ResolvePerNight = 25,
	RetreatTime = 40,
	MemoryDecayPerNight = 0.8,
	SpawnMinDistance = 450,
}

-- The Locust's stats for a night. modeMult scales difficulty (Hardcore > 1, Solo < 1).
function Config.LocustStats(night: number, modeMult: number?)
	local m = modeMult or 1
	local n = math.max(1, night)
	local function cap(v, hi)
		return math.min(v, hi)
	end
	local stats = {
		Night = n,
		PatrolSpeed = cap(9 + 0.5 * n, 18) * math.min(m, 1.15),
		InvestigateSpeed = cap(13 + 0.6 * n, 22) * math.min(m, 1.15),
		ChaseSpeed = cap(17.5 + 0.75 * n, if n >= 20 then 29 else 27) * math.min(m, 1.12),
		Damage = cap(14 + 2.6 * n, 62) * m,
		AttackCooldown = math.max(0.9, 1.5 - 0.03 * n),
		HearingRange = cap(55 + 7 * n, 210) * m,
		SightRange = cap(45 + 4.5 * n, 150) * m,
		AwarenessTime = math.max(0.3, 1.25 - 0.05 * n) / m, -- seconds of being seen before it commits
		LoseTime = cap(3.5 + 0.35 * n, 11), -- seconds without sight before it gives up the chase
		ChaseEndurance = cap(22 + 2 * n, 70), -- a chase that lasts longer makes it frustrated
		SearchTime = cap(10 + 1.2 * n, 40),
		StructureDamage = (18 + 11 * n) * m,
		BreakTier = 0, -- highest structure tier it can break at full strength (see below)
		Resolve = (Config.Locust.BaseResolve + Config.Locust.ResolvePerNight * n) * m,
		Abilities = {},
	}
	-- breaking power: night 3 weak barricades, night 5 doors, night 10 metal, 15 reinforced, 20 advanced
	if n >= 20 then
		stats.BreakTier = 4
	elseif n >= 15 then
		stats.BreakTier = 3
	elseif n >= 10 then
		stats.BreakTier = 2
	elseif n >= 3 then
		stats.BreakTier = 1
	end
	for name, minNight in Config.LocustAbilities do
		if n >= minNight then
			stats.Abilities[name] = true
		end
	end
	return stats
end

-- night the ability becomes available
Config.LocustAbilities = {
	OpenDoors = 2, -- opens store doors and unlocked player doors
	BreakBarricades = 3, -- wood barricades (tier 1) even before doors
	Memory = 3, -- patrols the places players use the most
	SearchHidingSpots = 4,
	SearchBases = 5,
	BreakDoors = 5, -- wood doors + wood walls
	Shriek = 7, -- reveals nearby players and makes flashlights flicker
	Lunge = 12,
	LightSurge = 15, -- powered lights near it short out
	Nymphs = 20, -- small scouts that call the Locust
}

-- How much of its structure damage the Locust deals to a structure of this tier.
function Config.BreakMultiplier(stats, tier: number, kind: string?): number
	if tier <= 0 then
		return 1
	end
	if tier <= stats.BreakTier then
		return 1
	end
	-- night 3-4: only barricades of tier 1
	if tier == 1 and kind == "Barricade" and stats.Abilities.BreakBarricades then
		return 1
	end
	if tier == 1 and stats.Abilities.BreakDoors then
		return 1
	end
	if tier == 2 and kind == "Barricade" and stats.Abilities.BreakDoors then
		return 0.6
	end
	-- above its tier it can only scratch it: an unrepaired base still falls eventually
	return if tier - stats.BreakTier >= 2 then 0.02 else 0.06
end

-- Special Locust variants at very high nights (every 10 nights after 20)
Config.LocustVariants = {
	{ MinNight = 1, Name = "THE LOCUST", Body = "17130f", Shell = "2a2118", Eyes = "ffb000" },
	{ MinNight = 20, Name = "HOLLOW LOCUST", Body = "8e8a7e", Shell = "c9c4b2", Eyes = "a8f5ff", Translucent = true },
	{ MinNight = 30, Name = "IRON LOCUST", Body = "2b2f36", Shell = "6d7480", Eyes = "ff5a1f", StructureMult = 1.5, ResolveMult = 1.5 },
	{ MinNight = 40, Name = "SWARM QUEEN", Body = "1a0b10", Shell = "4a1020", Eyes = "ff1e3c", StructureMult = 1.6, ResolveMult = 1.8, NymphBonus = 2 },
}

function Config.VariantFor(night: number)
	local pick = Config.LocustVariants[1]
	for _, v in Config.LocustVariants do
		if night >= v.MinNight then
			pick = v
		end
	end
	return pick
end

--=============================== GAME MODES ===============================--
Config.ModeOrder = { "Survival", "Infection", "Hardcore", "Solo" }
Config.Modes = {
	Survival = {
		Name = "SURVIVAL",
		Desc = "Classic mode. Loot by day, build a base, survive as many nights as possible.",
		MaxPlayers = 12,
		LocustMult = 1,
		LootMult = 1,
		HungerMult = 1,
		BleedOut = 45,
		ReviveNeedsMedkit = false,
		Color = "ffc61a",
	},
	Infection = {
		Name = "INFECTION",
		Desc = "From night 2, one player turns into an infected hunter each night. The rest must survive.",
		MaxPlayers = 12,
		MinPlayers = 2,
		LocustMult = 0.85,
		LootMult = 1,
		HungerMult = 1,
		BleedOut = 35,
		ReviveNeedsMedkit = false,
		InfectionFromNight = 2,
		Color = "7cff4f",
	},
	Hardcore = {
		Name = "HARDCORE",
		Desc = "Fewer supplies, a stronger Locust, and reviving needs a medkit.",
		MaxPlayers = 12,
		LocustMult = 1.3,
		LootMult = 0.6,
		HungerMult = 1.3,
		BleedOut = 25,
		ReviveNeedsMedkit = true,
		Color = "ff3b3b",
	},
	Solo = {
		Name = "SOLO",
		Desc = "Just you and the Locust. Tuned for one player; a medkit lets you get yourself back up.",
		MaxPlayers = 1,
		LocustMult = 0.82,
		LootMult = 1.2,
		HungerMult = 0.9,
		BleedOut = 30,
		ReviveNeedsMedkit = false,
		SelfRevive = true,
		Color = "5ab4ff",
	},
}

--=============================== LOOT ===============================--
Config.Loot = {
	InitialItems = 950,
	RestockPerDay = 320,
	MaxWorldItems = 1300,
	MaxDroppedItems = 250,
	PickupDistance = 10,
	SupplyDropItems = 6,
}

--=============================== BUILDING / POWER ===============================--
Config.Building = {
	Grid = 4,
	MaxStructuresPerPlayer = 160,
	MaxStructuresTotal = 900,
	RefundOnRemove = 0.5,
	RepairCostFraction = 0.25,
	UpgradeCostFraction = 0.75,
	NoBuildRadiusAroundSpawn = 40,
}

Config.Power = {
	GeneratorRadius = 52,
	GeneratorCapacity = 8,
	FuelPerSecondBase = 0.05, -- % per second idle
	FuelPerSecondPerLoad = 0.03, -- extra % per second per power unit used
	StoreGeneratorRadius = 260,
}

--=============================== CARTS ===============================--
Config.Carts = {
	Count = 36,
	Slots = { 12, 18, 24 }, -- by cart tier (progression)
	MaxHealth = { 150, 220, 400 },
	GrabDistance = 9,
}

--=============================== PROGRESSION / ECONOMY ===============================--
Config.XP = {
	SurviveNightBase = 90,
	SurviveNightPerNight = 15,
	RareFind = { Rare = 12, Epic = 35, Legendary = 90 },
	Revive = 45,
	BuildEach = 2,
	BuildCapPerNight = 80,
	ExploreZone = 8,
	Objective = 60,
	InfectedDown = 30,
	LocustRepelled = 40,
}

Config.Credits = {
	SurviveNightBase = 8,
	SurviveNightPerNight = 2,
	LegendaryFind = 10,
	MaxPerNight = 200,
}

-- Developer products for Store Credits (fill in your own product ids after creating them).
Config.CreditProducts = {
	{ Id = 0, Credits = 120, Robux = 49, Name = "Pocket Change" },
	{ Id = 0, Credits = 400, Robux = 149, Name = "Shopping Bag" },
	{ Id = 0, Credits = 1000, Robux = 349, Name = "Full Cart" },
}

--=============================== EVENTS ===============================--
Config.Events = {
	MinGap = 70,
	MaxGap = 150,
	NightChanceMult = 1.2,
}

return Config
