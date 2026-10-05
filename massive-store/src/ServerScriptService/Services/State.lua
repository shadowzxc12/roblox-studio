--[[
	State: the server's shared game state + signals every system listens to.

	Replicated to clients as attributes on ReplicatedStorage (cheap, automatic):
	  Seed, Mode, Phase, Night, PhaseStart, PhaseEnds (workspace:GetServerTimeNow() based),
	  RunActive, Outage, Gate_<id>, ZonePower_<zoneId>, LocustVariant
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)

local State = {
	Mode = "Survival",
	ModeInfo = Config.Modes.Survival,
	Phase = "Waiting", -- Waiting | Day | Dusk | Night | Dawn | Results
	Night = 0, -- number of the current (or upcoming) night
	RunActive = false,
	Plan = nil,
	Seed = 0,
	RunId = 0,
	GatesOpen = {},
	NightUsedGenerator = {}, -- [player] = true if they powered a generator this night

	PhaseChanged = Signal.new(), -- (phase, night)
	NightStarted = Signal.new(), -- (night)
	NightSurvived = Signal.new(), -- (night)
	RunStarted = Signal.new(), -- ()
	RunEnded = Signal.new(), -- (summary)
	PlayerJoinedRun = Signal.new(), -- (player)
}

function State.Now(): number
	return Workspace:GetServerTimeNow()
end

function State.SetAttr(name: string, value: any)
	ReplicatedStorage:SetAttribute(name, value)
end

function State.Notify(player: Player?, text: string, kind: string?)
	local ev = Net.Event("Notify")
	if player then
		ev:FireClient(player, text, kind or "Info")
	else
		ev:FireAllClients(text, kind or "Info")
	end
end

-- big centred title, e.g. NIGHT 3 — THE LOCUST IS HUNTING
function State.Banner(player: Player?, title: string, sub: string?, color: string?, time: number?)
	local payload = { Title = title, Sub = sub, Color = color, Time = time or 4 }
	local ev = Net.Event("Banner")
	if player then
		ev:FireClient(player, payload)
	else
		ev:FireAllClients(payload)
	end
end

function State.Cue(kind: string, position: Vector3?, extra: any, player: Player?)
	local ev = Net.Event("Cue")
	if player then
		ev:FireClient(player, kind, position, extra)
	else
		ev:FireAllClients(kind, position, extra)
	end
end

function State.IsNight(): boolean
	return State.Phase == "Night"
end

function State.InRun(player: Player): boolean
	return player:GetAttribute("InRun") == true
end

return State
