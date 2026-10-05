--[[
	Infection mode: from night 2, one random survivor turns into an infected, Locust-like hunter
	for the night. Infected players are fast, tireless, see survivors through walls nearby and
	down them with their claws ([Click]). A survivor downed by an infected who bleeds out joins
	the infected instead of dying. Everyone turns back to normal at dawn.
	The Locust ignores infected players. Survivors can stun infected with a crowbar / stun baton.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Util = require(Shared.Util)

local State = require(script.Parent.State)
local Survival = require(script.Parent.Survival)
local Progress = require(script.Parent.Progress)
local RateLimiter = require(script.Parent.RateLimiter)

local Infection = {}

local rng = Util.RNG(os.time() % 4999 + 1)
local attackLimiter = RateLimiter.new(6, 3)
local nextAttack: { [Player]: number } = {}
local savedColors: { [Player]: { [BasePart]: Color3 } } = {}

local function applyLook(player: Player)
	local char = player.Character
	if not char then
		return
	end
	local saved = {}
	for _, p in char:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			saved[p] = p.Color
			p.Color = Color3.fromHex("1a120c")
		elseif p:IsA("Shirt") or p:IsA("Pants") or p:IsA("ShirtGraphic") then
			p:SetAttribute("WasParent", true)
			p.Parent = nil
		end
	end
	savedColors[player] = saved
	local head = char:FindFirstChild("Head")
	if head then
		for _, x in { -0.25, 0.25 } do
			local eye = Instance.new("Part")
			eye.Name = "InfectedEye"
			eye.Shape = Enum.PartType.Ball
			eye.Size = Vector3.new(0.3, 0.3, 0.3)
			eye.Material = Enum.Material.Neon
			eye.Color = Color3.fromHex("7cff4f")
			eye.CanCollide = false
			eye.Massless = true
			eye.CFrame = head.CFrame * CFrame.new(x, 0.15, -0.55)
			local w = Instance.new("WeldConstraint")
			w.Part0 = head
			w.Part1 = eye
			w.Parent = eye
			eye.Parent = char
		end
		local glow = Instance.new("PointLight")
		glow.Name = "InfectedGlow"
		glow.Color = Color3.fromHex("7cff4f")
		glow.Range = 8
		glow.Brightness = 1.2
		glow.Parent = head
	end
end

function Infection.Infect(player: Player, by: Player?)
	if player:GetAttribute("Infected") then
		return
	end
	local s = Survival.Get(player)
	if s and s.Downed then
		Survival.Revive(player, nil, 100)
	end
	Survival.SetInfected(player, true)
	applyLook(player)
	require(script.Parent.Carts).Release(player)
	require(script.Parent.Tools).SetFlashlight(player, false)
	State.Banner(player, "YOU ARE INFECTED", "Hunt the survivors · [Click] to attack · back to normal at dawn", "7cff4f", 5)
	State.Notify(nil, player.DisplayName .. " has been infected!", "Danger")
	State.Cue("Infected", Survival.Position(player), player.UserId)
	if by then
		Progress.AddXP(by, Config.XP.InfectedDown, "Infected " .. player.DisplayName)
	end
end

function Infection.Cure(player: Player)
	if not player:GetAttribute("Infected") then
		return
	end
	Survival.SetInfected(player, false)
	-- fresh body in the same spot
	local root = Survival.Root(player)
	local cf = if root then root.CFrame else nil
	Survival.Spawn(player, cf, false)
	savedColors[player] = nil
	State.Notify(player, "The infection fades with the sunrise.", "Good")
end

-- a survivor's bleed-out: turned instead of killed when an infected downed them
local function bleedOverride(player: Player): boolean
	if State.Mode ~= "Infection" then
		return false
	end
	local s = Survival.Get(player)
	local src = s and s.DownSource
	if typeof(src) == "Instance" and src:IsA("Player") and src:GetAttribute("Infected") then
		Infection.Infect(player, src)
		return true
	end
	return false
end

function Infection.Stun(player: Player, seconds: number)
	local s = Survival.Get(player)
	if s and s.Infected then
		s.BuffSpeed = -30
		s.BuffUntil = os.clock() + seconds
	end
end

local function attack(player: Player)
	local s = Survival.Get(player)
	if not s or not s.Infected or s.Downed or s.Dead then
		return
	end
	local now = os.clock()
	if now < (nextAttack[player] or 0) then
		return
	end
	nextAttack[player] = now + 1.1
	local root = Survival.Root(player)
	if not root then
		return
	end
	State.Cue("InfectedSwipe", root.Position, nil)
	local best, bestD = nil, 8
	for _, other in Players:GetPlayers() do
		if other ~= player and Survival.IsTargetable(other) then
			local pos = Survival.Position(other)
			local to = pos - root.Position
			if to.Magnitude < bestD and root.CFrame.LookVector:Dot(to.Unit) > 0.2 then
				best, bestD = other, to.Magnitude
			end
		end
	end
	if best then
		Survival.Damage(best, 26, player)
		local bs = Survival.Get(best)
		if bs and bs.Downed then
			bs.DownSource = player
			Progress.AddXP(player, Config.XP.InfectedDown, "Downed " .. best.DisplayName)
		end
		return
	end
	-- claw at structures in front
	local Building = require(script.Parent.Building)
	local stats = Config.LocustStats(State.Night, 0.6)
	for _, st in Building.Near(root.Position + root.CFrame.LookVector * 4, 6) do
		local mult = Config.BreakMultiplier(stats, st.Def.Tier, st.Def.Kind)
		Building.Damage(st, 30 * mult, player)
		break
	end
end

function Infection.Init()
	Survival.BleedOutOverride = bleedOverride
	Net.Event("UseItem").OnServerEvent:Connect(function(player, slot)
		-- slot 0 from an infected player = claw attack
		if slot == 0 and player:GetAttribute("Infected") and attackLimiter:Allow(player) then
			attack(player)
		end
	end)
	State.NightStarted:Connect(function(night)
		if State.Mode ~= "Infection" or night < (State.ModeInfo.InfectionFromNight or 2) then
			return
		end
		local candidates = {}
		for _, p in Survival.ActivePlayers() do
			if not p:GetAttribute("Infected") then
				table.insert(candidates, p)
			end
		end
		if #candidates >= (State.ModeInfo.MinPlayers or 2) then
			task.wait(8)
			local p = candidates[rng:Int(1, #candidates)]
			if p.Parent and Survival.IsActive(p) then
				Infection.Infect(p)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		nextAttack[player] = nil
		savedColors[player] = nil
	end)
end

return Infection
