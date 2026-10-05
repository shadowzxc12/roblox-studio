--[[
	Events: random things that happen in the store.
	  POWER OUTAGE      every light dies for a while
	  SECURITY ALERT    alarms ring somewhere (the Locust goes to check)
	  SUPPLY DROP       a crate of good loot crashes through the ceiling
	  LOCUST ROAR       the Locust becomes more aggressive for a while (night)
	  LOCKDOWN          some store doors slam shut and lock
	  GENERATOR FAILURE a running generator dies
	  RARE LOOT         something valuable appears (with a light beam)
	Supply Beacons (item) queue a crate drop for dawn.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Util = require(Shared.Util)
local StoreLayout = require(Shared.StoreLayout)

local State = require(script.Parent.State)
local World = require(script.Parent.World)
local Noise = require(script.Parent.Noise)
local Loot = require(script.Parent.Loot)
local Power = require(script.Parent.Power)
local Locust = require(script.Parent.Locust)

local Events = {}

local rng = Util.RNG(os.time() % 7777 + 5)
local beacons = {}
local current = nil

local function zoneName(pos: Vector3): string
	local zone = StoreLayout.ZoneAt(State.Plan, pos.X, pos.Y, pos.Z)
	return if zone then zone.Name else "THE STORE"
end

local function announce(kind: string, name: string, desc: string, pos: Vector3?, duration: number?)
	current = kind
	State.SetAttr("Event", name)
	Net.Event("Event"):FireAllClients({ Kind = kind, Name = name, Desc = desc, Position = pos, Time = duration or 8 })
	if duration then
		task.delay(duration, function()
			if current == kind then
				current = nil
				State.SetAttr("Event", "")
			end
		end)
	end
end

local DEFS = {
	{
		Kind = "PowerOutage",
		Weight = 1,
		Night = 1.3,
		Day = 0.4,
		Run = function()
			local t = rng:Range(25, 45)
			Power.SetOutage(true)
			announce("PowerOutage", "POWER OUTAGE", "All the lights just went out.", nil, t)
			State.Cue("PowerDown", nil, nil)
			task.delay(t, function()
				Power.SetOutage(false)
				State.Cue("PowerUp", nil, nil)
			end)
		end,
	},
	{
		Kind = "SecurityAlert",
		Weight = 1,
		Night = 1.2,
		Day = 0.8,
		Run = function()
			local pos = Loot.RandomPoint(nil, 0)
			announce("SecurityAlert", "SECURITY ALERT", "Alarms are ringing in " .. zoneName(pos) .. ".", pos, 16)
			task.spawn(function()
				for _ = 1, 15 do
					Noise.Emit(pos, Config.Noise.Alarm, nil, "Alarm")
					State.Cue("Alarm", pos, nil)
					task.wait(1)
				end
			end)
		end,
	},
	{
		Kind = "SupplyDrop",
		Weight = 1,
		Night = 0.6,
		Day = 1.4,
		Run = function()
			local pos = Loot.RandomPoint(nil, nil)
			Loot.SpawnCrate(pos, Config.Loot.SupplyDropItems, 2.5, "Supply Drop", true)
			State.Cue("SupplyDrop", pos, nil)
			announce("SupplyDrop", "SUPPLY DROP", "A crate came down in " .. zoneName(pos) .. ".", pos, 30)
		end,
	},
	{
		Kind = "LocustRoar",
		Weight = 1,
		Night = 1,
		Day = 0,
		Run = function()
			local L = Locust.Get()
			if not L then
				return
			end
			local stats = L.Stats
			stats.ChaseSpeed += 3
			stats.HearingRange *= 1.3
			stats.SightRange *= 1.15
			State.Cue("Roar", L.Root.Position, nil)
			announce("LocustRoar", "LOCUST ROAR", "It's angry. It's faster and hears more for a while.", nil, 40)
			task.delay(40, function()
				if Locust.Get() == L then
					stats.ChaseSpeed -= 3
					stats.HearingRange /= 1.3
					stats.SightRange /= 1.15
				end
			end)
		end,
	},
	{
		Kind = "Lockdown",
		Weight = 0.8,
		Night = 1,
		Day = 0.7,
		Run = function()
			local locked = {}
			for id in World.StoreDoors do
				if rng:Chance(0.45) then
					World.LockStoreDoor(id, true)
					table.insert(locked, id)
				end
			end
			if #locked == 0 then
				return
			end
			State.Cue("Lockdown", nil, nil)
			announce("Lockdown", "LOCKDOWN", #locked .. " store doors slammed shut and locked.", nil, 45)
			task.delay(45, function()
				for _, id in locked do
					World.LockStoreDoor(id, false)
				end
			end)
		end,
	},
	{
		Kind = "GeneratorFailure",
		Weight = 0.8,
		Night = 1,
		Day = 0.6,
		Run = function()
			local pos = Power.FailRandom()
			if pos then
				announce("GeneratorFailure", "GENERATOR FAILURE", "A generator in " .. zoneName(pos) .. " just died.", pos, 12)
			end
		end,
	},
	{
		Kind = "RareLoot",
		Weight = 0.7,
		Night = 0.8,
		Day = 1.1,
		Run = function()
			local pos = Loot.RandomPoint(nil, nil)
			local itemId = Loot.SpawnSpecial(pos, "Epic")
			announce("RareLoot", "RARE LOOT", "Something valuable is glowing in " .. zoneName(pos) .. ".", pos, 30)
			return itemId
		end,
	},
}

function Events.Trigger(kind: string?)
	local def = nil
	if kind then
		for _, d in DEFS do
			if d.Kind == kind then
				def = d
			end
		end
	else
		local weights = {}
		local night = State.Phase == "Night"
		for i, d in DEFS do
			weights[i] = d.Weight * (if night then d.Night else d.Day)
		end
		def = DEFS[rng:Weighted(weights)]
	end
	if def then
		local ok, err = pcall(def.Run)
		if not ok then
			warn("[Events] " .. def.Kind .. ": " .. tostring(err))
		end
	end
end

function Events.QueueBeacon(pos: Vector3, beacon: BasePart)
	table.insert(beacons, { Pos = pos, Part = beacon })
end

function Events.DropBeacons()
	for _, b in beacons do
		Loot.SpawnCrate(b.Pos, Config.Loot.SupplyDropItems + 2, 3.5, "Beacon Supply Crate", true)
		if b.Part then
			b.Part:Destroy()
		end
	end
	if #beacons > 0 then
		State.Notify(nil, "Supply beacons delivered!", "Good")
	end
	table.clear(beacons)
end

function Events.Clear()
	table.clear(beacons)
	current = nil
	State.SetAttr("Event", "")
end

function Events.Init()
	task.spawn(function()
		while true do
			local gap = rng:Range(Config.Events.MinGap, Config.Events.MaxGap)
			if State.Phase == "Night" then
				gap /= Config.Events.NightChanceMult
			end
			task.wait(gap)
			if State.RunActive and (State.Phase == "Day" or State.Phase == "Night") and not current then
				Events.Trigger()
			end
		end
	end)
end

return Events
