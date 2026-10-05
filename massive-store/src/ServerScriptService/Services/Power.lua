--[[
	Power: electricity.

	Player generators (Building "Generator") burn fuel and power devices in range
	(lights, cameras, shock plates, turrets) up to their capacity. Out of fuel = THE BASE GOES DARK.
	Store backup generators (placed by the layout in maintenance areas / tunnels) start broken:
	repair them with Electrical Parts and fuel them to keep the surrounding departments lit
	at night. Running generators are noisy — the Locust can hear them.

	Zone lighting (replicated as ReplicatedStorage attribute ZonePower_<zoneId>):
	  "On"        normal lights   (day, or powered by a store generator)
	  "Emergency" dim red lights  (some departments at night)
	  "Off"       pitch black
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Items = require(Shared.Items)
local Util = require(Shared.Util)

local State = require(script.Parent.State)
local World = require(script.Parent.World)
local Survival = require(script.Parent.Survival)
local Inventory = require(script.Parent.Inventory)
local Prompts = require(script.Parent.Prompts)
local Progress = require(script.Parent.Progress)
local Noise = require(script.Parent.Noise)

local Power = {}

local generators: { [any]: any } = {} -- key: structure or store generator record
local devices: { [any]: boolean } = {}
local zonePower: { [number]: string } = {}
local emergencyZones: { [number]: boolean } = {}
local outage = false
local rng = Util.RNG(os.time() % 9973 + 3)

local GREEN, RED, AMBER = Color3.fromHex("00e676"), Color3.fromHex("ff1744"), Color3.fromHex("ffb300")

local function genPosition(g): Vector3
	if g.Structure then
		return g.Structure.Model:GetPivot().Position
	end
	return g.Position
end

local function setLamp(g)
	local lamp
	if g.Structure then
		for _, p in g.Structure.Model:GetDescendants() do
			if p:IsA("BasePart") and p:GetAttribute("Lamp") then
				lamp = p
			end
		end
	else
		lamp = g.Lamp
	end
	if lamp then
		lamp.Color = if g.Broken then RED elseif g.Running and g.Fuel > 0 then GREEN else AMBER
	end
	local model = if g.Structure then g.Structure.Model else g.Model
	model:SetAttribute("Fuel", math.floor(g.Fuel))
	model:SetAttribute("Running", g.Running and g.Fuel > 0)
	model:SetAttribute("Broken", g.Broken == true)
	model:SetAttribute("Load", g.Load or 0)
	model:SetAttribute("Capacity", g.Capacity)
end

local function updatePrompts(g)
	if g.TogglePrompt then
		if g.Broken then
			g.TogglePrompt.ActionText = "Repair (2 Electrical Parts)"
		else
			g.TogglePrompt.ActionText = if g.Running then "Switch off" else "Switch on"
		end
		g.TogglePrompt.ObjectText = (if g.Store then "Backup Generator" else "Generator") .. (" · Fuel %d%%"):format(math.floor(g.Fuel))
	end
end

local function makePrompts(g, part: BasePart)
	local toggle = Prompts.Make(part, "GenToggle", "Switch on", "Generator", { Distance = 10, Hold = 0.4 })
	toggle:SetAttribute("GenKey", g.Key)
	local refuel = Prompts.Make(part, "GenRefuel", "Refuel", "", { Distance = 10, Key = Enum.KeyCode.L, GamepadKey = Enum.KeyCode.ButtonY, Hold = 0.6, Name = "RefuelPrompt" })
	refuel:SetAttribute("GenKey", g.Key)
	g.TogglePrompt = toggle
	g.RefuelPrompt = refuel
end

local byKey: { [string]: any } = {}

function Power.RegisterGenerator(structure)
	local g = {
		Key = "S" .. structure.Id,
		Structure = structure,
		Fuel = 25,
		Running = false,
		Capacity = structure.Def.Capacity or Config.Power.GeneratorCapacity,
		Load = 0,
		Radius = Config.Power.GeneratorRadius,
	}
	generators[g] = true
	byKey[g.Key] = g
	structure.Generator = g
	makePrompts(g, structure.Main)
	updatePrompts(g)
	setLamp(g)
end

function Power.RegisterDevice(structure)
	devices[structure] = true
	structure.Powered = false
end

local function registerStoreGenerators()
	for id, sg in World.StoreGenerators do
		local g = {
			Key = "B" .. id,
			Store = true,
			Model = sg.Model,
			Lamp = sg.Lamp,
			Position = sg.Position,
			Fuel = 0,
			Running = false,
			Broken = true,
			Capacity = 0,
			Load = 0,
			Radius = Config.Power.StoreGeneratorRadius,
		}
		generators[g] = true
		byKey[g.Key] = g
		makePrompts(g, sg.Body)
		updatePrompts(g)
		setLamp(g)
	end
end

local function running(g)
	return g.Running and g.Fuel > 0 and not g.Broken
end

-- assign devices to generators
local function distribute()
	for g in generators do
		g.Load = 0
	end
	for s in devices do
		if s.Model.Parent then
			local pos = s.Model:GetPivot().Position
			local best, bestD = nil, math.huge
			for g in generators do
				if not g.Store and running(g) and g.Load + s.Def.Power <= g.Capacity then
					local d = (genPosition(g) - pos).Magnitude
					if d <= g.Radius and d < bestD then
						best, bestD = g, d
					end
				end
			end
			local powered = best ~= nil and not outage
			if best then
				best.Load += s.Def.Power
			end
			if powered ~= s.Powered then
				s.Powered = powered
				s.Model:SetAttribute("Powered", powered)
				for _, p in s.Model:GetDescendants() do
					if p:IsA("PointLight") and p.Name == "BaseLight" then
						p.Enabled = powered
					elseif p:IsA("BasePart") and p:GetAttribute("Lamp") then
						p.Color = if powered then GREEN else RED
					elseif p:IsA("BasePart") and p.Name == "Bulb" then
						p.Material = if powered then Enum.Material.Neon else Enum.Material.SmoothPlastic
					end
				end
			end
		else
			devices[s] = nil
		end
	end
end

--============================ ZONE LIGHTING ============================--
local function storePowered(zone): boolean
	for g in generators do
		if g.Store and running(g) then
			local cell = State.Plan.Cells[zone.Center]
			if cell and (Vector3.new(cell.X, cell.Y, cell.Z) - g.Position).Magnitude <= g.Radius then
				return true
			end
		end
	end
	return false
end

function Power.RefreshZones()
	local plan = State.Plan
	if not plan then
		return
	end
	local night = State.Phase == "Night" or State.Phase == "Dusk"
	for _, zone in plan.Zones do
		local mode
		if outage then
			mode = if emergencyZones[zone.Id] then "Emergency" else "Off"
		elseif not night then
			mode = "On"
		elseif storePowered(zone) then
			mode = "On"
		elseif emergencyZones[zone.Id] then
			mode = "Emergency"
		else
			mode = "Off"
		end
		if State.Phase == "Dusk" and mode ~= "On" then
			mode = "Flicker"
		end
		if zonePower[zone.Id] ~= mode then
			zonePower[zone.Id] = mode
			State.SetAttr("ZonePower_" .. zone.Id, mode)
		end
	end
end

-- new night: pick which departments keep emergency lighting
function Power.RollEmergency()
	table.clear(emergencyZones)
	for _, zone in State.Plan.Zones do
		if rng:Chance(0.38) then
			emergencyZones[zone.Id] = true
		end
	end
end

function Power.SetOutage(on: boolean)
	outage = on
	State.SetAttr("Outage", on)
	distribute()
	Power.RefreshZones()
end

-- light level at a position: 1 lit, 0.6 emergency, 0 dark (+ powered base lights)
function Power.LightAt(pos: Vector3): number
	local plan = State.Plan
	if not plan then
		return 1
	end
	local StoreLayout = require(Shared.StoreLayout)
	local zone = StoreLayout.ZoneAt(plan, pos.X, pos.Y, pos.Z)
	local level = 0
	if zone then
		local m = zonePower[zone.Id] or "On"
		level = if m == "On" then 1 elseif m == "Emergency" or m == "Flicker" then 0.6 else 0
	end
	if level < 1 then
		for s in devices do
			if s.Powered and s.Def.Kind == "Light" and (s.Model:GetPivot().Position - pos).Magnitude < 28 then
				return 1
			end
		end
	end
	return level
end

-- powered lights (the Locust is drawn to them at higher nights)
function Power.PoweredLights()
	local out = {}
	for s in devices do
		if s.Powered and s.Def.Kind == "Light" then
			table.insert(out, s)
		end
	end
	return out
end

function Power.Devices()
	return devices
end

--============================ ACTIONS ============================--
local FUEL_ORDER = { "GasCanister", "FuelCan", "PowerCell" }

function Power.Refuel(player: Player, g, amount: number?): boolean
	if g.Broken then
		State.Notify(player, "Repair it first.", "Warn")
		return false
	end
	if g.Fuel >= 99 then
		State.Notify(player, "The tank is full.", "Info")
		return false
	end
	if amount then
		g.Fuel = math.min(100, g.Fuel + amount)
	else
		local used = nil
		for _, id in FUEL_ORDER do
			if Inventory.Count(player, id) > 0 then
				used = id
				break
			end
		end
		if not used then
			State.Notify(player, "You need a Fuel Can, Gas Canister or Power Cell.", "Warn")
			return false
		end
		Inventory.TakeItem(player, used, 1)
		g.Fuel = math.min(100, g.Fuel + (Items.Get(used).Fuel or 30))
	end
	Progress.Track(player, "Refuels", 1)
	if State.Phase == "Night" then
		State.NightUsedGenerator[player] = true
	end
	updatePrompts(g)
	setLamp(g)
	State.Cue("Refuel", genPosition(g), nil)
	return true
end

-- fuel item used from the hotbar: nearest generator in reach
function Power.RefuelNearest(player: Player, amount: number): boolean
	local me = Survival.Position(player)
	if not me then
		return false
	end
	local best, bestD = nil, 14
	for g in generators do
		local d = (genPosition(g) - me).Magnitude
		if d < bestD then
			best, bestD = g, d
		end
	end
	if not best then
		return false
	end
	return Power.Refuel(player, best, amount)
end

local function toggle(player: Player, g)
	if g.Broken then
		if Inventory.TakeItem(player, "Electronics", 2) then
			g.Broken = false
			State.Notify(player, "Generator repaired. Fuel it and switch it on.", "Good")
			Progress.AddXP(player, 15, "Repaired a generator")
		else
			State.Notify(player, "Needs 2 Electrical Parts to repair.", "Warn")
		end
	else
		if not g.Running and g.Fuel <= 0 then
			State.Notify(player, "No fuel!", "Warn")
			return
		end
		g.Running = not g.Running
		if g.Running and State.Phase == "Night" then
			State.NightUsedGenerator[player] = true
		end
		State.Cue(if g.Running then "GenStart" else "GenStop", genPosition(g), nil)
	end
	updatePrompts(g)
	setLamp(g)
	distribute()
	Power.RefreshZones()
end

-- random event: a running generator fails
function Power.FailRandom(): Vector3?
	local list = {}
	for g in generators do
		if running(g) then
			table.insert(list, g)
		end
	end
	if #list == 0 then
		return nil
	end
	local g = list[rng:Int(1, #list)]
	g.Running = false
	if g.Store then
		g.Broken = true
	end
	updatePrompts(g)
	setLamp(g)
	distribute()
	Power.RefreshZones()
	return genPosition(g)
end

function Power.ResetRun()
	for g in generators do
		if g.Store then
			g.Broken = true
			g.Running = false
			g.Fuel = 0
			updatePrompts(g)
			setLamp(g)
		else
			generators[g] = nil
			byKey[g.Key] = nil
		end
	end
	table.clear(devices)
	outage = false
	State.SetAttr("Outage", false)
	table.clear(emergencyZones)
	Power.RefreshZones()
end

function Power.Init()
	registerStoreGenerators()

	Prompts.Register("GenToggle", function(player, prompt)
		local g = byKey[prompt:GetAttribute("GenKey")]
		if g then
			toggle(player, g)
		end
	end)
	Prompts.Register("GenRefuel", function(player, prompt)
		local g = byKey[prompt:GetAttribute("GenKey")]
		if g then
			Power.Refuel(player, g)
		end
	end)

	local Building = require(script.Parent.Building)
	Building.Destroyed:Connect(function(s)
		if s.Generator then
			generators[s.Generator] = nil
			byKey[s.Generator.Key] = nil
			distribute()
		end
		devices[s] = nil
	end)
	Building.Placed:Connect(function()
		distribute()
	end)

	task.spawn(function()
		local acc = 0
		while true do
			local dt = task.wait(1)
			acc += dt
			local changed = false
			for g in generators do
				if running(g) then
					local burn = Config.Power.FuelPerSecondBase + Config.Power.FuelPerSecondPerLoad * (g.Load or 0)
					if g.Store then
						burn = 0.12
					end
					g.Fuel = math.max(0, g.Fuel - burn * dt)
					Noise.Emit(genPosition(g), Config.Noise.Generator, nil, "Generator")
					if g.Fuel <= 0 then
						g.Running = false
						changed = true
						State.Cue("GenStop", genPosition(g), nil)
						-- tell nearby players
						for _, p in Players:GetPlayers() do
							local pos = Survival.Position(p)
							if pos and (pos - genPosition(g)).Magnitude < 90 then
								State.Banner(p, "THE BASE GOES DARK", "A generator ran out of fuel", "ff3b3b", 3)
							end
						end
					end
					-- players next to a running generator at night "used" it (daily mission)
					if State.Phase == "Night" and not g.Store then
						for _, p in Players:GetPlayers() do
							local pos = Survival.Position(p)
							if pos and (pos - genPosition(g)).Magnitude < g.Radius then
								State.NightUsedGenerator[p] = true
							end
						end
					end
				end
				if acc >= 3 then
					updatePrompts(g)
					setLamp(g)
				end
			end
			if acc >= 3 then
				acc = 0
			end
			if changed then
				distribute()
				Power.RefreshZones()
			else
				distribute()
			end
		end
	end)
end

return Power
