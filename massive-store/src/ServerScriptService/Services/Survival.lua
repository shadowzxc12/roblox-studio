--[[
	Survival: health, hunger, stamina, energy, movement speed, downed / revive / death,
	hiding spots, spawning and squad info. Fully server-authoritative:
	  - the client only says "I want to sprint / crouch"; the server decides the WalkSpeed
	  - all damage goes through Survival.Damage
	  - a movement check pulls players back if they move faster than their speed allows
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)

local State = require(script.Parent.State)
local World = require(script.Parent.World)
local Noise = require(script.Parent.Noise)
local Prompts = require(script.Parent.Prompts)
local Progress = require(script.Parent.Progress)
local RateLimiter = require(script.Parent.RateLimiter)

local SV = Config.Survival
local Survival = {}

Survival.Downed = Signal.new() -- (player, source)
Survival.Revived = Signal.new() -- (player, reviver)
Survival.Died = Signal.new() -- (player, position)
Survival.Spawned = Signal.new() -- (player, character)
Survival.Damaged = Signal.new() -- (player, amount, source)

-- set by Infection: return true to take over a bleed-out
Survival.BleedOutOverride = nil :: ((Player) -> boolean)?

local P: { [Player]: any } = {}
local inputLimiter = RateLimiter.new(30, 2)

local function newState()
	return {
		Health = SV.MaxHealth,
		Hunger = SV.MaxHunger,
		Stamina = SV.MaxStamina,
		Energy = SV.MaxEnergy,
		Downed = false,
		BleedOutAt = 0,
		Dead = false,
		WantSprint = false,
		WantCrouch = false,
		Sprinting = false,
		StaminaRegenAt = 0,
		Hidden = nil,
		BuffSpeed = 0,
		BuffUntil = 0,
		Heals = {},
		SpawnProtect = 0,
		Grace = 0,
		LastPos = nil,
		Strikes = 0,
		Sleeping = nil,
		Bed = nil,
		Infected = false,
		CartTier = 0, -- >0 while pushing a cart
		DownSource = nil,
	}
end

function Survival.Get(player: Player)
	return P[player]
end

local function root(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end
Survival.Root = root

local function humanoid(player: Player): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

function Survival.Position(player: Player): Vector3?
	local r = root(player)
	return r and r.Position
end

-- alive, in the run, standing (not downed / dead)
function Survival.IsActive(player: Player): boolean
	local s = P[player]
	return s ~= nil and State.InRun(player) and not s.Dead and not s.Downed and root(player) ~= nil
end

-- can the Locust see / attack this player right now?
function Survival.IsTargetable(player: Player): boolean
	local s = P[player]
	return Survival.IsActive(player) and not s.Hidden and not s.Infected and os.clock() > s.SpawnProtect
end

function Survival.ActivePlayers()
	local out = {}
	for _, p in Players:GetPlayers() do
		if Survival.IsActive(p) then
			table.insert(out, p)
		end
	end
	return out
end

function Survival.RunPlayers()
	local out = {}
	for _, p in Players:GetPlayers() do
		if State.InRun(p) and P[p] then
			table.insert(out, p)
		end
	end
	return out
end

local function sync(player: Player)
	local s = P[player]
	if not s then
		return
	end
	player:SetAttribute("Health", math.floor(s.Health + 0.5))
	player:SetAttribute("Hunger", math.floor(s.Hunger + 0.5))
	player:SetAttribute("Stamina", math.floor(s.Stamina + 0.5))
	player:SetAttribute("Energy", math.floor(s.Energy + 0.5))
	player:SetAttribute("Downed", s.Downed)
	player:SetAttribute("Dead", s.Dead)
	player:SetAttribute("Hidden", s.Hidden ~= nil)
	player:SetAttribute("Sprinting", s.Sprinting)
	player:SetAttribute("Crouching", s.WantCrouch and not s.Sprinting)
	player:SetAttribute("BuffUntil", if s.BuffUntil > os.clock() then State.Now() + (s.BuffUntil - os.clock()) else 0)
	local hum = humanoid(player)
	if hum and not s.Dead then
		hum.Health = math.max(1, s.Health)
	end
end
Survival.Sync = sync

-- teleport that the movement check accepts
function Survival.Teleport(player: Player, cf: CFrame)
	local s = P[player]
	local char = player.Character
	if not char then
		return
	end
	if s then
		s.Grace = os.clock() + 2
		s.LastPos = cf.Position
	end
	char:PivotTo(cf)
end

--============================ DAMAGE / DOWN / REVIVE ============================--
local function removeRevivePrompt(player: Player)
	local r = root(player)
	if r then
		local p = r:FindFirstChild("RevivePrompt")
		if p then
			p:Destroy()
		end
	end
end

function Survival.Kill(player: Player, reason: string?)
	local s = P[player]
	if not s or s.Dead then
		return
	end
	local pos = Survival.Position(player)
	if s.Hidden then
		Survival.Unhide(player)
	end
	s.Dead = true
	s.Downed = false
	removeRevivePrompt(player)
	local hum = humanoid(player)
	if hum then
		hum.Health = 0
	end
	sync(player)
	Survival.Died:Fire(player, pos, reason)
	State.Notify(nil, player.DisplayName .. " didn't make it. They'll be back at dawn.", "Danger")
end

function Survival.Down(player: Player, source: any?)
	local s = P[player]
	if not s or s.Downed or s.Dead then
		return
	end
	if s.Hidden then
		Survival.Unhide(player)
	end
	s.Downed = true
	s.Health = 0
	s.Sprinting = false
	s.DownSource = source
	local bleed = State.ModeInfo.BleedOut or SV.BleedOutTime
	s.BleedOutAt = os.clock() + bleed
	player:SetAttribute("BleedOut", State.Now() + bleed)
	local hum = humanoid(player)
	if hum then
		hum.WalkSpeed = SV.DownedSpeed
		hum.JumpHeight = 0
	end
	local r = root(player)
	if r then
		local prompt = Prompts.Make(r, "Revive", "Revive", player.DisplayName, { Hold = SV.ReviveTime, Distance = 9, Name = "RevivePrompt" })
		prompt:SetAttribute("Target", player.UserId)
	end
	sync(player)
	Survival.Downed:Fire(player, source)
	Progress.Track(player, "Downs", 1)
	-- if nobody else can help, a solo player without a medkit is out
	State.Cue("Downed", Survival.Position(player), player.UserId)
end

function Survival.Revive(player: Player, reviver: Player?, health: number?)
	local s = P[player]
	if not s or not s.Downed or s.Dead then
		return false
	end
	s.Downed = false
	s.Health = health or SV.ReviveHealth
	s.SpawnProtect = os.clock() + 2.5
	removeRevivePrompt(player)
	local hum = humanoid(player)
	if hum then
		hum.JumpHeight = 7.2
	end
	player:SetAttribute("BleedOut", 0)
	sync(player)
	Survival.Revived:Fire(player, reviver)
	if reviver and reviver ~= player then
		Progress.AddXP(reviver, Config.XP.Revive, "Revived " .. player.DisplayName)
		Progress.Track(reviver, "Revives", 1)
		State.Notify(player, reviver.DisplayName .. " got you back up!", "Good")
	end
	Noise.Emit(Survival.Position(player) or Vector3.zero, Config.Noise.Revive, player, "Revive")
	return true
end

function Survival.Damage(player: Player, amount: number, source: any?): boolean
	local s = P[player]
	if not s or s.Dead or amount <= 0 then
		return false
	end
	if os.clock() < s.SpawnProtect and source ~= "Starve" then
		return false
	end
	if s.Downed then
		-- hitting a downed player makes them bleed out faster
		s.BleedOutAt -= amount * 0.25
		player:SetAttribute("BleedOut", State.Now() + (s.BleedOutAt - os.clock()))
		return true
	end
	s.Health -= amount
	s.Sleeping = nil
	Survival.Damaged:Fire(player, amount, source)
	Net.Event("Cue"):FireClient(player, "Hurt", nil, amount)
	if s.Health <= 0 then
		Survival.Down(player, source)
	end
	sync(player)
	return true
end

function Survival.Heal(player: Player, amount: number, over: number?)
	local s = P[player]
	if not s or s.Dead or s.Downed then
		return
	end
	if over and over > 0 then
		table.insert(s.Heals, { PerSec = amount / over, Until = os.clock() + over })
	else
		s.Health = math.min(SV.MaxHealth, s.Health + amount)
	end
	sync(player)
end

-- food / drinks / medicine effects; returns false if it can't be used now
function Survival.Consume(player: Player, use): boolean
	local s = P[player]
	if not s or s.Dead or s.Downed or not use then
		return false
	end
	local mult = if s.Infected then 0.5 else 1
	if use.Hunger then
		s.Hunger = math.min(SV.MaxHunger, s.Hunger + use.Hunger * mult)
	end
	if use.Energy then
		s.Energy = math.min(SV.MaxEnergy, s.Energy + use.Energy * mult)
	end
	if use.Stamina then
		s.Stamina = math.min(SV.MaxStamina, s.Stamina + use.Stamina)
	end
	if use.Heal then
		Survival.Heal(player, use.Heal, use.HealOver)
	end
	if use.Buff then
		s.BuffSpeed = use.Buff.Speed or 0
		s.BuffUntil = os.clock() + (use.Buff.Time or 10)
	end
	sync(player)
	return true
end

--============================ HIDING ============================--
function Survival.Hide(player: Player, spotId: number)
	local s = P[player]
	local spot = World.HideSpots[spotId]
	if not s or not spot or s.Downed or s.Dead or s.CartTier > 0 then
		return false
	end
	if spot.Occupant and spot.Occupant ~= player then
		State.Notify(player, "Someone is already hiding there.", "Warn")
		return false
	end
	local r = root(player)
	if not r then
		return false
	end
	s.Hidden = spotId
	s.HideReturn = spot.CFrame * CFrame.new(0, 0.5, -3.5)
	spot.Occupant = player
	spot.Prompt.ActionText = "Leave"
	Survival.Teleport(player, spot.CFrame)
	r.Anchored = true
	player:SetAttribute("HideSpot", spotId)
	sync(player)
	return true
end

function Survival.Unhide(player: Player)
	local s = P[player]
	if not s or not s.Hidden then
		return
	end
	local spot = World.HideSpots[s.Hidden]
	s.Hidden = nil
	if spot then
		spot.Occupant = nil
		spot.Prompt.ActionText = "Hide"
	end
	local r = root(player)
	if r then
		r.Anchored = false
		if s.HideReturn then
			Survival.Teleport(player, s.HideReturn)
		end
	end
	player:SetAttribute("HideSpot", 0)
	sync(player)
end

function Survival.HiddenIn(spotId: number): Player?
	local spot = World.HideSpots[spotId]
	return spot and spot.Occupant
end

--============================ SPAWNING ============================--
local function setupCharacter(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then
		return
	end
	hum.MaxHealth = SV.MaxHealth
	hum.Health = SV.MaxHealth
	hum.BreakJointsOnDeath = false
	hum.WalkSpeed = SV.WalkSpeed
	hum.UseJumpPower = false
	hum.JumpHeight = 7.2
	-- nothing but our system may kill this character
	hum:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
	hum.HealthChanged:Connect(function(h)
		local s = P[player]
		if h <= 0 and s and not s.Dead then
			-- e.g. fell into the void: count as a death
			Survival.Kill(player, "Fell")
		end
	end)
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Players"
		end
	end
	char.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = "Players"
		end
	end)
end

-- spawn (or respawn) a player into the run. fresh = full stats
function Survival.Spawn(player: Player, cf: CFrame?, fresh: boolean?)
	local s = P[player]
	if not s or fresh then
		local old = s
		s = newState()
		if old then
			s.Bed = old.Bed
		end
		P[player] = s
	end
	s.Dead = false
	s.Downed = false
	s.Hidden = nil
	s.Health = math.max(s.Health, SV.MaxHealth * 0.6)
	s.Hunger = math.max(s.Hunger, 50)
	s.SpawnProtect = os.clock() + SV.SpawnProtection
	s.Grace = os.clock() + 4
	s.LastPos = nil
	player:SetAttribute("BleedOut", 0)
	player:SetAttribute("HideSpot", 0)
	local target = cf
	if not target and s.Bed and s.Bed.Parent then
		target = s.Bed:GetPivot() * CFrame.new(0, 3, 0)
	end
	target = target or World.SpawnCFrame()
	player:LoadCharacter()
	local char = player.Character or player.CharacterAdded:Wait()
	setupCharacter(player, char)
	Survival.Teleport(player, target)
	sync(player)
	Survival.Spawned:Fire(player, char)
end

function Survival.SetBed(player: Player, bed: Model?)
	local s = P[player]
	if s then
		s.Bed = bed
	end
end

function Survival.SetSleeping(player: Player, bed: Model?)
	local s = P[player]
	if s then
		s.Sleeping = bed
	end
end

function Survival.SetCartTier(player: Player, tier: number)
	local s = P[player]
	if s then
		s.CartTier = tier
	end
end

function Survival.SetInfected(player: Player, infected: boolean)
	local s = P[player]
	if s then
		s.Infected = infected
		player:SetAttribute("Infected", infected)
	end
end

-- remove a player from the run (back to the menu)
function Survival.LeaveRun(player: Player)
	local s = P[player]
	if s and s.Hidden then
		Survival.Unhide(player)
	end
	player:SetAttribute("InRun", false)
	P[player] = nil
	if player.Character then
		player.Character:Destroy()
		player.Character = nil
	end
end

function Survival.ResetForNewRun()
	for player, s in P do
		s.Bed = nil
	end
end

--============================ TICK ============================--
local function speedFor(player: Player, s): number
	if s.Hidden then
		return 0
	end
	if s.Downed then
		return SV.DownedSpeed
	end
	local base = SV.WalkSpeed
	if s.Infected then
		base = if s.Sprinting then 27 else 19
	elseif s.Sprinting then
		base = SV.SprintSpeed
	elseif s.WantCrouch then
		base = SV.CrouchSpeed
	end
	if s.CartTier > 0 then
		base *= 1 - (SV.CartPenalty[s.CartTier] or 0.2)
	end
	if s.Energy < SV.ExhaustedEnergy then
		base *= 0.85
	end
	if s.Hunger <= 0 then
		base *= 0.85
	end
	if os.clock() < s.BuffUntil then
		base += s.BuffSpeed
	end
	return base
end

local acc05, acc1 = 0, 0
local function step(dt: number)
	acc05 += dt
	acc1 += dt
	local now = os.clock()
	local hungerMult = State.ModeInfo.HungerMult or 1
	local running = State.RunActive
	for player, s in P do
		local hum = humanoid(player)
		local r = root(player)
		if hum and r and not s.Dead and State.InRun(player) then
			-- bleed out
			if s.Downed and now >= s.BleedOutAt then
				local handled = Survival.BleedOutOverride and Survival.BleedOutOverride(player)
				if not handled then
					Survival.Kill(player, "BledOut")
				end
				continue
			end
			local moving = Vector3.new(r.AssemblyLinearVelocity.X, 0, r.AssemblyLinearVelocity.Z).Magnitude > 2
			-- stamina
			local canSprint = s.WantSprint and moving and not s.Downed and not s.Hidden and s.Energy >= SV.ExhaustedEnergy * 0.5
			if canSprint and s.Stamina > 0 then
				s.Sprinting = true
				if not s.Infected then
					s.Stamina = math.max(0, s.Stamina - SV.StaminaSprintDrain * dt)
				end
				s.StaminaRegenAt = now + SV.StaminaRegenDelay
			else
				if s.Sprinting and s.Stamina <= 0 then
					s.StaminaRegenAt = now + SV.StaminaRegenDelay * 2
				end
				s.Sprinting = false
				if now >= s.StaminaRegenAt then
					local regen = SV.StaminaRegen * (if s.Energy < SV.ExhaustedEnergy then 0.45 else 1) * (if s.Hidden then 1.6 else 1)
					s.Stamina = math.min(SV.MaxStamina, s.Stamina + regen * dt)
				end
			end
			local speed = speedFor(player, s)
			if math.abs(hum.WalkSpeed - speed) > 0.05 then
				hum.WalkSpeed = speed
			end
			-- heals over time
			for i = #s.Heals, 1, -1 do
				local h = s.Heals[i]
				if now > h.Until then
					table.remove(s.Heals, i)
				elseif not s.Downed then
					s.Health = math.min(SV.MaxHealth, s.Health + h.PerSec * dt)
				end
			end
		end
	end

	if acc05 >= 0.5 then
		local d = acc05
		acc05 = 0
		for player, s in P do
			local r = root(player)
			if r and not s.Dead and State.InRun(player) and running then
				-- hunger / energy
				s.Hunger = math.max(0, s.Hunger - SV.HungerDrainPerMinute / 60 * d * hungerMult * (if s.Sprinting then 1.6 else 1))
				if s.Sleeping and s.Sleeping.Parent then
					s.Energy = math.min(SV.MaxEnergy, s.Energy + 10 * d)
				else
					s.Energy = math.max(0, s.Energy - SV.EnergyDrainPerMinute / 60 * d * (if s.Sprinting then 1.5 else 1))
				end
				if s.Hunger <= 0 and not s.Downed then
					Survival.Damage(player, SV.StarveDamagePerSecond * d, "Starve")
				elseif s.Hunger >= SV.FedRegenThreshold and not s.Downed and s.Health < SV.MaxHealth then
					s.Health = math.min(SV.MaxHealth, s.Health + SV.HealthRegenPerSecond * d)
				end
				-- noise from moving
				local v = Vector3.new(r.AssemblyLinearVelocity.X, 0, r.AssemblyLinearVelocity.Z).Magnitude
				if v > 2 and not s.Hidden then
					local loud = if s.Sprinting then Config.Noise.Sprint elseif s.WantCrouch then Config.Noise.Crouch else Config.Noise.Walk
					if s.CartTier > 0 then
						loud = math.max(loud, if s.CartTier >= 2 then Config.Noise.CartPushFast else Config.Noise.CartPush)
					end
					Noise.Emit(r.Position, loud, player, if s.Sprinting then "Sprint" else "Step")
				end
			end
			sync(player)
		end
	end

	if acc1 >= 1 then
		local d = acc1
		acc1 = 0
		-- movement validation (anti speed / teleport hacks)
		for player, s in P do
			local r = root(player)
			local hum = humanoid(player)
			if r and hum and not s.Dead and not s.Hidden then
				local pos = r.Position
				if s.LastPos and now > s.Grace then
					local flat = Vector3.new(pos.X - s.LastPos.X, 0, pos.Z - s.LastPos.Z).Magnitude
					local allowed = (math.max(hum.WalkSpeed, speedFor(player, s)) * 1.35 + 8) * d
					if flat > allowed then
						s.Strikes += 1
						if s.Strikes >= 2 then
							Survival.Teleport(player, CFrame.new(s.LastPos + Vector3.new(0, 1, 0)))
							s.Strikes = 0
							pos = s.LastPos
						end
					else
						s.Strikes = math.max(0, s.Strikes - 1)
					end
				end
				s.LastPos = pos
			end
		end
		-- squad info for HUDs / maps
		local squad = {}
		for player, s in P do
			if State.InRun(player) then
				local pos = Survival.Position(player)
				table.insert(squad, {
					UserId = player.UserId,
					Name = player.DisplayName,
					Pos = pos,
					Health = math.floor(s.Health),
					Downed = s.Downed,
					Dead = s.Dead,
					Hidden = s.Hidden ~= nil,
					Infected = s.Infected,
				})
			end
		end
		Net.Event("Squad"):FireAllClients(squad)
	end
end

function Survival.Init()
	Net.Event("Input").OnServerEvent:Connect(function(player, input)
		if not inputLimiter:Allow(player) or type(input) ~= "table" then
			return
		end
		local s = P[player]
		if not s then
			return
		end
		s.WantSprint = input.Sprint == true
		s.WantCrouch = input.Crouch == true
		if s.WantSprint then
			s.Sleeping = nil
		end
	end)

	Net.Event("LeaveHiding").OnServerEvent:Connect(function(player)
		Survival.Unhide(player)
	end)

	Prompts.Register("Hide", function(player, prompt)
		local id = prompt:GetAttribute("Id")
		local s = P[player]
		if not s then
			return
		end
		if s.Hidden == id then
			Survival.Unhide(player)
		elseif not s.Hidden and not s.Downed then
			Survival.Hide(player, id)
		end
	end)

	Prompts.Register("Revive", function(player, prompt)
		local targetId = prompt:GetAttribute("Target")
		local target = Players:GetPlayerByUserId(targetId)
		if not target or target == player or not Survival.IsActive(player) then
			return
		end
		local s = P[player]
		if s.Infected then
			return
		end
		if State.ModeInfo.ReviveNeedsMedkit then
			local Inventory = require(script.Parent.Inventory)
			if not Inventory.TakeItem(player, "Medkit", 1) then
				State.Notify(player, "Hardcore: you need a Medkit to revive.", "Warn")
				return
			end
		end
		Survival.Revive(target, player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local s = P[player]
		if s and s.Hidden then
			Survival.Unhide(player)
		end
		P[player] = nil
	end)

	RunService.Heartbeat:Connect(step)
end

return Survival
