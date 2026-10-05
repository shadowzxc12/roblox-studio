-- Scenario: game modes. Set G.MODE before this file (run_infection / run_solo / run_hardcore).
--   Infection: one survivor turns at night 2, claws down others, a bleed-out spreads it, dawn cures
--   Solo:      self-revive with a medkit
--   Hardcore:  reviving needs a medkit, less loot

G.STUDIO = true
local MODE = G.MODE or "Infection"
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local PPS = game:GetService("ProximityPromptService")
local Config = require(RS.Shared.Config)
Config.Cycle.FirstDay = 6
Config.Cycle.Day = 6
Config.Cycle.Dusk = 2
Config.Cycle.NightBase = 60
Config.Cycle.NightPerNight = 0
Config.Cycle.Dawn = 2

G.StartServer()
G.RunUntil(4)
local function svc(name)
	return require(SSS.Services[name])
end
local State, Survival, Inventory = svc("State"), svc("Survival"), svc("Inventory")
local Remotes = RS:WaitForChild("Remotes")
local function R(name)
	return Remotes:FindFirstChild(name)
end
local function check(cond, msg)
	if not cond then
		table.insert(ERRORS, "CHECK FAILED: " .. msg)
		print("CHECK FAILED: " .. msg)
	else
		print("ok: " .. msg)
	end
end
local function waitFor(fn, timeout, step)
	local t = 0
	while not fn() and t < timeout do
		G.RunUntil(step or 0.5)
		t += step or 0.5
	end
	return fn()
end

local bots = {}
for i = 1, (if MODE == "Solo" then 1 else 3) do
	table.insert(bots, G.AddPlayer("Bot" .. i))
end
G.RunUntil(2)
for _, p in bots do
	R("Play").OnServerEvent:Fire(p, MODE)
end
G.RunUntil(2)
check(State.Mode == MODE, "server mode is " .. MODE)
G.RunUntil(Config.Survival.SpawnProtection + 1) -- spawn protection wears off
check(bots[1]:GetAttribute("InRun"), "first bot in the store")

if MODE == "Infection" then
	check(waitFor(function()
		return State.Night == 2 and State.Phase == "Night"
	end, 200), "night 2")
	local infected
	check(waitFor(function()
		for _, p in bots do
			if p:GetAttribute("Infected") then
				infected = p
				return true
			end
		end
		return false
	end, 15), "someone got infected")
	local victim
	for _, p in bots do
		if p ~= infected then
			victim = p
			break
		end
	end
	-- the infected claws the victim until they're down
	for _ = 1, 12 do
		Survival.Teleport(infected, CFrame.new(Survival.Position(victim) + Vector3.new(0, 0, 3), Survival.Position(victim)))
		G.RunUntil(0.1)
		R("UseItem").OnServerEvent:Fire(infected, 0)
		G.RunUntil(1.2)
		if victim:GetAttribute("Downed") then
			break
		end
	end
	check(victim:GetAttribute("Downed") == true, "infected downed a survivor")
	-- nobody revives: they bleed out and turn
	check(waitFor(function()
		return victim:GetAttribute("Infected") == true
	end, 60), "the bleed-out spread the infection")
	check(waitFor(function()
		return State.Phase == "Dawn" or State.Phase == "Day" or State.Phase == "Results"
	end, 80), "the night ended")
	if State.Phase ~= "Results" then
		G.RunUntil(1)
		check(not infected:GetAttribute("Infected"), "dawn cured the infected")
	end
elseif MODE == "Solo" then
	local p = bots[1]
	Inventory.Give(p, "Medkit", 1)
	Survival.Damage(p, 500, "Test")
	G.RunUntil(0.5)
	check(p:GetAttribute("Downed") == true, "solo player downed")
	local inv = Inventory.Get(p)
	local slot
	for i = 1, inv.Size do
		if inv.Slots[i] and inv.Slots[i].Id == "Medkit" then
			slot = i
		end
	end
	R("UseItem").OnServerEvent:Fire(p, slot)
	G.RunUntil(Config.Survival.SelfReviveTime + 1)
	check(p:GetAttribute("Downed") == false, "self revive with a medkit")
elseif MODE == "Hardcore" then
	local a, b = bots[1], bots[2]
	Survival.Damage(a, 500, "Test")
	G.RunUntil(0.5)
	Survival.Teleport(b, CFrame.new(Survival.Position(a) + Vector3.new(2, 0, 0)))
	G.RunUntil(0.2)
	local prompt = Survival.Root(a):FindFirstChild("RevivePrompt")
	PPS.PromptTriggered:Fire(prompt, b)
	G.RunUntil(0.5)
	check(a:GetAttribute("Downed") == true, "no revive without a medkit in hardcore")
	Inventory.Give(b, "Medkit", 1)
	PPS.PromptTriggered:Fire(prompt, b)
	G.RunUntil(0.5)
	check(a:GetAttribute("Downed") == false, "medkit revive works")
	check(Inventory.Count(b, "Medkit") == 0, "the medkit was used")
end

if #ERRORS > 0 then
	print(("FAILED with %d errors"):format(#ERRORS))
	for i = 1, math.min(8, #ERRORS) do
		print(ERRORS[i])
	end
	error(MODE .. " scenario failed")
end
print(MODE .. " SCENARIO OK")
