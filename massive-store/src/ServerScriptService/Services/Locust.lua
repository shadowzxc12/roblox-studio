--[[
	Locust: THE LOCUST's brain (server). Bodies are LocustRig models; clients animate them.

	It does NOT know where players are. It has to notice them:
	  SIGHT    field of view + range, worse in the dark, better if you use a flashlight,
	           worse if you crouch. Line of sight is raycast. Seeing you fills an "awareness"
	           meter first (no instant detection).
	  HEARING  noises (Noise service): sprinting, carts, building, generators, doors, flares...
	  CLOSE    within a few studs it senses you anyway (unless you are hidden)
	  LIGHTS   from night 3 it is drawn to powered base lights
	  MEMORY   it remembers which parts of the store players use (heat per cell, persists
	           between nights) and where bases are; it patrols there more as nights go on.

	States: Spawning, Patrol, Investigate, Search, Chase, Break, Stunned, Shriek, Retreat, Leaving

	Movement: long trips follow the store's lane graph (Nav A*: always clear straight lines),
	short trips and chases use PathfindingService. Player structures carry PathfindingModifiers
	(labels T1..T4 / B1..B2 / Door) whose costs depend on what it can break tonight, so it plans
	through weak walls and around strong ones. When something blocks it, it breaks it (if strong
	enough), shoves carts out of the way, opens doors (night 2+) or finds another way.

	Fair by design: losing sight for a while makes it give up, long chases frustrate it,
	turrets / traps / stun batons drain its resolve until it retreats, hiding spots work
	(until night 4 when it starts checking them), repellent keeps it out.
]]

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Nav = require(Shared.Nav)
local Util = require(Shared.Util)
local LocustRig = require(Shared.LocustRig)
local StoreLayout = require(Shared.StoreLayout)

local State = require(script.Parent.State)
local World = require(script.Parent.World)
local Survival = require(script.Parent.Survival)
local Noise = require(script.Parent.Noise)
local Progress = require(script.Parent.Progress)

local Locust = {}

local LC = Config.Locust
local rng = Util.RNG(os.time() % 7919 + 11)

local L = nil -- the active Locust
local nymphs = {}
local repellents = {}
local memory = { Heat = {}, Bases = {} }
local paths = {} -- PathfindingService Path objects for the current night

local function lazy(name)
	return require(script.Parent[name])
end

--============================ HELPERS ============================--
local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function rayParams(extra)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = { World.Folders.Loot, World.Folders.Dynamic, World.Folders.Lights, World.Folders.Signs, World.Folders.Hiding }
	if L then
		table.insert(list, L.Model)
	end
	for _, n in nymphs do
		table.insert(list, n.Model)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	if extra then
		for _, e in extra do
			table.insert(list, e)
		end
	end
	params.FilterDescendantsInstances = list
	return params
end

local function eyePos(): Vector3
	return L.Root.Position + Vector3.new(0, 4.2, 0)
end

local function lineOfSight(from: Vector3, to: Vector3): boolean
	local hit = Workspace:Raycast(from, to - from, rayParams())
	return hit == nil
end

local function inRepellent(pos: Vector3): boolean
	local now = os.clock()
	for i = #repellents, 1, -1 do
		local r = repellents[i]
		if now > r.Until then
			table.remove(repellents, i)
		elseif (r.Pos - pos).Magnitude < r.Radius then
			return true
		end
	end
	return false
end

local function cellOf(pos: Vector3)
	return StoreLayout.CellAt(State.Plan, pos.X, pos.Y, pos.Z)
end

local function canOpenDoors(): boolean
	return L ~= nil and L.Stats.Abilities.OpenDoors == true
end

-- nav graph path as a list of positions
local blockedLinks = {}
local function navPath(from: Vector3, to: Vector3)
	local plan = State.Plan
	local a, b = Nav.NodeAt(plan, from.X, from.Y, from.Z), Nav.NodeAt(plan, to.X, to.Y, to.Z)
	if not a or not b then
		return nil
	end
	local now = os.clock()
	local nodes = Nav.FindPath(plan, a, b, {
		CanPass = function(link, fromNode)
			if link.Gate and not State.GatesOpen[link.Gate] then
				return false
			end
			if link.Door then
				local d = World.StoreDoors[link.Door]
				if d and not d.Open and (d.Locked or not canOpenDoors()) then
					return false
				end
			end
			local key = math.min(fromNode, link.To) * 100000 + math.max(fromNode, link.To)
			if blockedLinks[key] and blockedLinks[key] > now then
				return false
			end
			return true
		end,
		NodeCost = function(i)
			local n = plan.Nav.Nodes[i]
			if #repellents > 0 and inRepellent(Vector3.new(n.X, n.Y, n.Z)) then
				return 5000
			end
			return 0
		end,
	})
	if not nodes then
		return nil
	end
	local out = {}
	for _, i in nodes do
		local n = plan.Nav.Nodes[i]
		table.insert(out, Vector3.new(n.X, n.Y + 1, n.Z))
	end
	table.insert(out, to)
	-- skip the first node if we're already between it and the second one
	if #out >= 3 then
		local d12 = (flat(out[2]) - flat(out[1])).Magnitude
		if (flat(out[2]) - flat(from)).Magnitude < d12 then
			table.remove(out, 1)
		end
	end
	return out, nodes
end

-- PathfindingService path (short distances)
local function localPath(from: Vector3, to: Vector3)
	local path = paths.Main
	if not path then
		return nil
	end
	local ok = pcall(function()
		path:ComputeAsync(from, to)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return nil
	end
	local out = {}
	for _, w in path:GetWaypoints() do
		table.insert(out, w.Position + Vector3.new(0, 1, 0))
	end
	if #out > 1 then
		table.remove(out, 1)
	end
	return out
end

local function setupPaths(stats)
	local costs = { Door = if stats.Abilities.OpenDoors then 4 else math.huge, MapDoor = if stats.Abilities.OpenDoors then 2 else math.huge }
	for tier = 1, 4 do
		local m = Config.BreakMultiplier(stats, tier, "Wall")
		costs["T" .. tier] = if m >= 0.5 then 18 * tier else math.huge
		local mb = Config.BreakMultiplier(stats, tier, "Barricade")
		costs["B" .. tier] = if mb >= 0.5 then 12 * tier else math.huge
	end
	paths.Main = PathfindingService:CreatePath({
		AgentRadius = 2.2,
		AgentHeight = 10,
		AgentCanJump = false,
		AgentCanClimb = false,
		WaypointSpacing = 7,
		Costs = costs,
	})
end

--============================ MOVEMENT ============================--
local function setSpeed(speed: number)
	if L.Hum.WalkSpeed ~= speed then
		L.Hum.WalkSpeed = speed
	end
end

local function setState(name: string)
	if L.State ~= name then
		L.State = name
		L.StateSince = os.clock()
		L.Model:SetAttribute("State", name)
	end
end

local function clearPath()
	L.Path = nil
	L.PathIndex = 1
	L.Goal = nil
end

-- plan a route to a world position
local function goTo(pos: Vector3, mode: string?)
	L.Goal = pos
	L.GoalMode = mode
	L.PathTime = os.clock()
	local from = L.Root.Position
	local sameLevel = math.abs(from.Y - pos.Y) < 8
	local route = nil
	if sameLevel and (flat(pos) - flat(from)).Magnitude < 110 then
		route = localPath(from, pos)
	end
	if not route then
		route = navPath(from, pos)
	end
	if not route then
		route = { pos }
	end
	L.Path = route
	L.PathIndex = 1
	L.Detours = 0
end

local function arrived(radius: number?): boolean
	return L.Goal ~= nil and (flat(L.Root.Position) - flat(L.Goal)).Magnitude < (radius or 5)
end

-- walk along the current path; returns true when the end is reached
local function follow(): boolean
	if not L.Path then
		return true
	end
	local wp = L.Path[L.PathIndex]
	while wp and (flat(L.Root.Position) - flat(wp)).Magnitude < 4 do
		L.PathIndex += 1
		wp = L.Path[L.PathIndex]
	end
	if not wp then
		clearPath()
		return true
	end
	L.Hum:MoveTo(wp)
	return false
end

--============================ SENSES ============================--
local function lightFactor(player: Player, pos: Vector3): number
	if player:GetAttribute("FlashOn") then
		return LC.FlashlightSightMultiplier
	end
	local level = lazy("Power").LightAt(pos)
	local f = if level >= 1 then 1 elseif level > 0 then LC.EmergencySightMultiplier else LC.DarkSightMultiplier
	if player:GetAttribute("Crouching") then
		f *= LC.CrouchSightMultiplier
	end
	return f
end

-- can it see this player right now?
local function sees(player: Player): (boolean, number)
	local pos = Survival.Position(player)
	if not pos then
		return false, math.huge
	end
	local eye = eyePos()
	local d = (pos - eye).Magnitude
	local range = L.Stats.SightRange * lightFactor(player, pos)
	if d > range then
		return false, d
	end
	if d > 12 then
		local look = flat(L.Root.CFrame.LookVector).Unit
		local dir = flat(pos - eye)
		if dir.Magnitude > 0.1 and look:Dot(dir.Unit) < math.cos(math.rad(LC.FOV / 2)) then
			return false, d
		end
	end
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	local target = if head then head.Position else pos
	return lineOfSight(eye, target), d
end

local function heatAt(pos: Vector3, amount: number)
	local cell = cellOf(pos)
	if cell then
		memory.Heat[cell.Id] = (memory.Heat[cell.Id] or 0) + amount
	end
end

--============================ ACTIONS ============================--
local function cue(kind: string, extra: any?)
	State.Cue(kind, L.Root.Position, extra)
end

local function startChase(player: Player)
	if L.Target ~= player then
		L.ChaseStart = os.clock()
		L.LastHitTime = os.clock()
		cue("LocustChase", player.UserId)
	end
	L.Target = player
	L.LastSeen = os.clock()
	L.LastKnown = Survival.Position(player)
	clearPath()
	setState("Chase")
end

local function startSearch(center: Vector3, duration: number?)
	L.SearchCenter = center
	L.SearchUntil = os.clock() + (duration or L.Stats.SearchTime)
	L.Target = nil
	clearPath()
	setState("Search")
	heatAt(center, 4)
end

local function startInvestigate(pos: Vector3)
	L.InvestigatePos = pos
	clearPath()
	setState("Investigate")
	goTo(pos)
end

local function farNode(minDist: number)
	local plan = State.Plan
	local candidates = {}
	local playersPos = {}
	for _, p in Players:GetPlayers() do
		local pos = Survival.Position(p)
		if pos then
			table.insert(playersPos, pos)
		end
	end
	for _, cell in plan.CellList do
		local node = plan.Nav.CellNode[cell.Id]
		local reachable = cell.Level == 0 or State.GatesOpen.Basement1 or State.GatesOpen.Basement2
		if node and reachable and not cell.Stair and (cell.Type ~= "Sealed" or State.GatesOpen.SealedWing) then
			local v = Vector3.new(cell.X, cell.Y + 6, cell.Z)
			local ok = true
			for _, pp in playersPos do
				if (pp - v).Magnitude < minDist then
					ok = false
					break
				end
			end
			if ok then
				table.insert(candidates, v)
			end
		end
	end
	if #candidates == 0 then
		local cell = plan.CellList[rng:Int(1, #plan.CellList)]
		return Vector3.new(cell.X, cell.Y + 6, cell.Z)
	end
	return candidates[rng:Int(1, #candidates)]
end

local function pickPatrolTarget(): Vector3
	local plan = State.Plan
	local stats = L.Stats
	-- bases
	if stats.Abilities.SearchBases and #memory.Bases > 0 and rng:Chance(0.35) then
		local b = memory.Bases[rng:Int(1, #memory.Bases)]
		return b
	end
	-- remembered player areas
	if stats.Abilities.Memory and rng:Chance(0.6) then
		local weights = {}
		for id, h in memory.Heat do
			if h > 1 then
				weights[id] = h
			end
		end
		local id = rng:Weighted(weights)
		local cell = id and plan.Cells[id]
		if cell and not cell.Solid then
			return Vector3.new(cell.X + rng:Range(-10, 10), cell.Y + 3, cell.Z + rng:Range(-10, 10))
		end
	end
	-- towards players, loosely (it roams the store, drifting toward where people are)
	local active = Survival.ActivePlayers()
	if #active > 0 and rng:Chance(0.4) then
		local p = active[rng:Int(1, #active)]
		local pos = Survival.Position(p)
		if pos then
			local fuzz = 140 - math.min(80, stats.Night * 6)
			local cell = cellOf(pos + Vector3.new(rng:Range(-fuzz, fuzz), 0, rng:Range(-fuzz, fuzz))) or cellOf(pos)
			if cell then
				return Vector3.new(cell.X, cell.Y + 3, cell.Z)
			end
		end
	end
	return farNode(0)
end

local function attack(player: Player)
	local now = os.clock()
	if now < L.NextAttack then
		return
	end
	L.NextAttack = now + L.Stats.AttackCooldown
	L.Model:SetAttribute("Attack", now)
	cue("LocustAttack", player.UserId)
	task.delay(0.25, function()
		if not L or not player.Parent then
			return
		end
		local pos = Survival.Position(player)
		if pos and (pos - L.Root.Position).Magnitude <= LC.AttackRange + 2.5 and Survival.IsTargetable(player) then
			Survival.Damage(player, L.Stats.Damage, "Locust")
			L.LastHitTime = os.clock()
			local st = Survival.Get(player)
			if st and st.Downed then
				-- it doesn't camp the downed: shriek and move on, teammates get a chance
				cue("LocustScreech")
				heatAt(pos, 6)
				startSearch(pos + Vector3.new(rng:Range(-30, 30), 0, rng:Range(-30, 30)), L.Stats.SearchTime * 0.5)
				L.IgnoreUntil = L.IgnoreUntil or {}
				L.IgnoreUntil[player] = os.clock() + 20
			end
		end
	end)
end

function Locust.Stun(seconds: number, by: Player?)
	if not L or L.Passive or L.State == "Retreat" or L.State == "Leaving" or L.State == "Spawning" then
		return
	end
	L.StunUntil = math.max(L.StunUntil, os.clock() + seconds)
	L.Model:SetAttribute("StunnedUntil", State.Now() + seconds)
	setState("Stunned")
	L.Hum:MoveTo(L.Root.Position)
	setSpeed(0)
	cue("LocustStunned")
end

function Locust.Hurt(amount: number, by: Player?)
	if not L or L.Passive or L.State == "Retreat" or L.State == "Leaving" then
		return
	end
	L.Resolve -= amount
	if by then
		L.Contributors[by] = (L.Contributors[by] or 0) + amount
	end
	L.Model:SetAttribute("Resolve", math.max(0, L.Resolve / L.MaxResolve))
	if L.Resolve <= 0 then
		-- driven off!
		cue("LocustRetreat")
		State.Notify(nil, "The Locust retreats... for now.", "Good")
		for p in L.Contributors do
			if p.Parent then
				Progress.AddXP(p, Config.XP.LocustRepelled, "Drove the Locust away")
				Progress.Track(p, "LocustRepelled", 1)
			end
		end
		table.clear(L.Contributors)
		L.Target = nil
		L.RetreatUntil = os.clock() + LC.RetreatTime
		clearPath()
		setState("Retreat")
		goTo(farNode(260))
	end
end

function Locust.AddRepellent(pos: Vector3, radius: number, seconds: number)
	table.insert(repellents, { Pos = pos, Radius = radius, Until = os.clock() + seconds })
end

function Locust.InRepellent(pos: Vector3): boolean
	return inRepellent(pos)
end

-- structure in the way?
local function obstacleAhead()
	local root = L.Root
	local dir = flat(root.CFrame.LookVector)
	if L.Path and L.Path[L.PathIndex] then
		local to = flat(L.Path[L.PathIndex] - root.Position)
		if to.Magnitude > 0.5 then
			dir = to.Unit
		end
	end
	local params = rayParams()
	for _, h in { -1.5, 1.5 } do
		local hit = Workspace:Raycast(root.Position + Vector3.new(0, h, 0), dir * 6, params)
		if hit then
			return hit.Instance, dir
		end
	end
	return nil, dir
end

local function handleObstacle(): boolean
	local inst, dir = obstacleAhead()
	if not inst then
		return false
	end
	local Building = lazy("Building")
	local s = Building.FromInstance(inst)
	if s then
		if s.Def.Kind == "Door" and not s.Locked and canOpenDoors() then
			Building.SetDoor(s, true)
			cue("DoorBang")
			return true
		end
		L.BreakTarget = s
		L.BreakStart = os.clock()
		L.BreakHits = 0
		setState("Break")
		return true
	end
	local Carts = lazy("Carts")
	if Carts.Shove(inst, dir) then
		cue("CartShove")
		return true
	end
	return false
end

-- open doors right in front of it
local function doorsAhead()
	if not canOpenDoors() then
		return
	end
	local pos = L.Root.Position
	local look = flat(L.Root.CFrame.LookVector)
	for id, d in World.StoreDoors do
		if not d.Open and not d.Locked then
			local to = flat(d.Position - pos)
			if to.Magnitude < 9 and look:Dot(to.Unit) > 0.2 then
				World.SetStoreDoor(id, true)
				cue("DoorBang")
			end
		end
	end
	for id, d in World.RoomDoors do
		if not d.Open and not d.Lock then
			local to = flat(d.Position - pos)
			if to.Magnitude < 7 and look:Dot(to.Unit) > 0.2 then
				World.SetRoomDoor(id, true)
				cue("DoorBang")
			end
		end
	end
end

--============================ STATE MACHINE ============================--
local function updateAwareness(dt: number)
	local stats = L.Stats
	local best, bestScore = nil, 0
	for _, player in Players:GetPlayers() do
		local ignore = L.IgnoreUntil and L.IgnoreUntil[player]
		if Survival.IsTargetable(player) and not (ignore and os.clock() < ignore) and not inRepellent(Survival.Position(player)) then
			local seen, d = sees(player)
			local a = L.Awareness[player] or 0
			if seen then
				local closeness = math.clamp(1.6 - d / stats.SightRange, 0.5, 1.6)
				a += dt / stats.AwarenessTime * closeness
			elseif d < LC.CloseSenseRadius and not player:GetAttribute("Crouching") then
				a += dt * 2.5
			else
				a -= dt * 0.35
			end
			a = math.clamp(a, 0, 1.2)
			L.Awareness[player] = a
			if seen and a >= 1 and (not best or a - d / 500 > bestScore) then
				best, bestScore = player, a - d / 500
			end
			if seen then
				heatAt(Survival.Position(player), dt * 0.4)
			end
		else
			L.Awareness[player] = 0
		end
	end
	L.Model:SetAttribute("Alert", if best then 1 else 0)
	return best
end

local function hear()
	local noise = Noise.Heard(L.Root.Position, L.Stats.HearingRange, { Generator = L.Stats.Night < 3 })
	return noise
end

local function tickPatrol(dt: number)
	setSpeed(L.Stats.PatrolSpeed)
	if not L.Path or L.Goal == nil then
		if os.clock() < (L.PauseUntil or 0) then
			L.Hum:MoveTo(L.Root.Position)
			return
		end
		goTo(pickPatrolTarget())
	end
	if follow() then
		L.PauseUntil = os.clock() + rng:Range(0.8, 2.6)
		clearPath()
	end
end

local function tickInvestigate(dt: number)
	setSpeed(L.Stats.InvestigateSpeed)
	if not L.Path then
		goTo(L.InvestigatePos)
	end
	if follow() or arrived(6) then
		startSearch(L.InvestigatePos, L.Stats.SearchTime * 0.7)
	end
end

local function tickSearch(dt: number)
	setSpeed(L.Stats.PatrolSpeed * 1.1)
	local now = os.clock()
	if now > L.SearchUntil then
		clearPath()
		setState("Patrol")
		return
	end
	-- check hiding spots near the search area
	if L.Stats.Abilities.SearchHidingSpots and not L.CheckingSpot and now > (L.NextSpotCheck or 0) then
		L.NextSpotCheck = now + 4
		for id, spot in World.HideSpots do
			local d = (spot.CFrame.Position - L.SearchCenter).Magnitude
			if d < 32 and rng:Chance(0.25 + 0.03 * L.Stats.Night) then
				L.CheckingSpot = id
				goTo(spot.CFrame * CFrame.new(0, 0, -4).Position)
				break
			end
		end
	end
	if L.CheckingSpot then
		if follow() or arrived(5) then
			local spot = World.HideSpots[L.CheckingSpot]
			L.CheckingSpot = nil
			L.Model:SetAttribute("Sniff", os.clock())
			cue("LocustSniff")
			L.Hum:MoveTo(L.Root.Position)
			local hidden = spot and spot.Occupant
			if hidden and Survival.Get(hidden) and Survival.Get(hidden).Hidden then
				task.wait(1.2)
				if L and spot.Occupant == hidden then
					Survival.Unhide(hidden)
					cue("LocustFound", hidden.UserId)
					Survival.Damage(hidden, L.Stats.Damage * 1.2, "Locust")
					startChase(hidden)
				end
			end
			L.PauseUntil = os.clock() + 1.2
		end
		return
	end
	if not L.Path then
		if os.clock() < (L.PauseUntil or 0) then
			return
		end
		local c = L.SearchCenter
		goTo(c + Vector3.new(rng:Range(-28, 28), 0, rng:Range(-28, 28)))
	end
	if follow() then
		L.PauseUntil = os.clock() + rng:Range(0.5, 1.8)
		L.Model:SetAttribute("Sniff", os.clock())
	end
end

local function tickChase(dt: number)
	local target = L.Target
	local stats = L.Stats
	if not target or not target.Parent or not Survival.IsActive(target) then
		startSearch(L.LastKnown or L.Root.Position)
		return
	end
	local st = Survival.Get(target)
	local pos = Survival.Position(target)
	local now = os.clock()
	if st.Hidden then
		-- did it see them slip into the hiding spot?
		local spot = World.HideSpots[st.Hidden]
		if spot and stats.Abilities.SearchHidingSpots and now - L.LastSeen < 1.5 and (spot.CFrame.Position - L.Root.Position).Magnitude < 40 then
			L.SearchCenter = spot.CFrame.Position
			L.SearchUntil = now + stats.SearchTime
			L.CheckingSpot = st.Hidden
			L.Target = nil
			setState("Search")
			goTo(spot.CFrame * CFrame.new(0, 0, -4).Position)
		else
			startSearch(L.LastKnown or pos)
		end
		return
	end
	if inRepellent(pos) then
		cue("LocustHiss")
		startSearch(L.Root.Position + (L.Root.Position - pos).Unit * 30)
		return
	end
	local seen, d = sees(target)
	if seen or d < LC.CloseSenseRadius then
		L.LastSeen = now
		L.LastKnown = pos
	end
	-- lost them?
	if now - L.LastSeen > stats.LoseTime then
		cue("LocustLost")
		startSearch(L.LastKnown)
		return
	end
	-- frustrated by a long chase
	if now - L.ChaseStart > stats.ChaseEndurance and now - (L.LastHitTime or 0) > 12 then
		cue("LocustScreech")
		heatAt(L.LastKnown, 8)
		L.IgnoreUntil = L.IgnoreUntil or {}
		L.IgnoreUntil[target] = now + 15
		L.Target = nil
		clearPath()
		setState("Patrol")
		goTo(farNode(160))
		return
	end
	local speed = stats.ChaseSpeed
	-- lunge
	if stats.Abilities.Lunge and seen and d > 8 and d < 20 and now > (L.NextLunge or 0) then
		L.NextLunge = now + 9
		L.LungeUntil = now + 0.6
		L.Model:SetAttribute("Lunge", now)
		cue("LocustLunge")
	end
	if L.LungeUntil and now < L.LungeUntil then
		speed *= 1.9
	end
	setSpeed(speed)
	-- light surge
	if stats.Abilities.LightSurge and now > (L.NextSurge or 0) then
		L.NextSurge = now + 25
		for _, s in lazy("Power").PoweredLights() do
			if (s.Model:GetPivot().Position - L.Root.Position).Magnitude < 40 then
				lazy("Power").SetOutage(true)
				task.delay(6, function()
					lazy("Power").SetOutage(false)
				end)
				cue("LightSurge")
				break
			end
		end
	end
	if d <= LC.AttackRange and seen then
		L.Hum:MoveTo(pos)
		attack(target)
		return
	end
	-- re-plan towards where we think they are
	local goalPos = if seen then pos else L.LastKnown
	if not L.Path or not L.Goal or (L.Goal - goalPos).Magnitude > 6 or now - (L.PathTime or 0) > 1.2 then
		if seen and d < 30 then
			-- close and visible: run straight at them
			L.Path = { goalPos }
			L.PathIndex = 1
			L.Goal = goalPos
			L.PathTime = now
		else
			goTo(goalPos)
		end
	end
	follow()
end

local function tickBreak(dt: number)
	local s = L.BreakTarget
	local Building = lazy("Building")
	if not s or not Building.All()[s.Id] then
		L.BreakTarget = nil
		setState(if L.Target then "Chase" else "Patrol")
		clearPath()
		return
	end
	L.Hum:MoveTo(L.Root.Position)
	local mult = Config.BreakMultiplier(L.Stats, s.Def.Tier, s.Def.Kind) * (L.Variant.StructureMult or 1)
	local now = os.clock()
	if now >= L.NextAttack then
		L.NextAttack = now + L.Stats.AttackCooldown
		L.Model:SetAttribute("Attack", now)
		L.BreakHits += 1
		Noise.Emit(s.Model:GetPivot().Position, Config.Noise.Break, nil, "Break")
		local destroyed = Building.Damage(s, L.Stats.StructureDamage * mult, "Locust")
		if destroyed then
			heatAt(L.Root.Position, 5)
			L.BreakTarget = nil
			setState(if L.Target then "Chase" else "Search")
			if not L.Target then
				startSearch(L.Root.Position, L.Stats.SearchTime * 0.6)
			end
			clearPath()
			return
		end
	end
	-- too strong for tonight: give up and find another way
	if (mult < 0.5 and L.BreakHits >= 4) or now - L.BreakStart > 18 then
		cue("LocustScreech")
		L.BreakTarget = nil
		local pos = s.Model:GetPivot().Position
		table.insert(memory.Bases, pos)
		if #memory.Bases > 20 then
			table.remove(memory.Bases, 1)
		end
		-- block the nav link we were using for a while
		local plan = State.Plan
		local a = Nav.NodeAt(plan, L.Root.Position.X, L.Root.Position.Y, L.Root.Position.Z)
		local b = Nav.NodeAt(plan, pos.X, pos.Y, pos.Z)
		if a and b and a ~= b then
			blockedLinks[math.min(a, b) * 100000 + math.max(a, b)] = now + 60
		end
		startSearch(L.Root.Position + Vector3.new(rng:Range(-40, 40), 0, rng:Range(-40, 40)), 8)
	end
end

local function tickRetreat(dt: number)
	setSpeed(L.Stats.ChaseSpeed)
	if L.Path then
		follow()
	end
	if os.clock() > (L.RetreatUntil or 0) then
		L.Resolve = L.MaxResolve * 0.6
		L.Model:SetAttribute("Resolve", 0.6)
		clearPath()
		setState("Patrol")
	end
end

local function tickShriek()
	L.Hum:MoveTo(L.Root.Position)
	if os.clock() - L.StateSince > 2.2 then
		-- reveal the nearest player in range
		local best, bestD = nil, 70
		for _, p in Survival.ActivePlayers() do
			local pos = Survival.Position(p)
			if pos and Survival.IsTargetable(p) then
				local d = (pos - L.Root.Position).Magnitude
				if d < bestD then
					best, bestD = p, d
				end
			end
		end
		if best then
			startInvestigate(Survival.Position(best))
		else
			setState("Patrol")
		end
	end
end

local stuckCheck = { Pos = nil, Time = 0 }
local function tickStuck()
	local now = os.clock()
	if not L.Path or L.State == "Stunned" or L.State == "Break" or L.State == "Shriek" then
		stuckCheck.Pos = L.Root.Position
		stuckCheck.Time = now
		return
	end
	if not stuckCheck.Pos then
		stuckCheck.Pos = L.Root.Position
		stuckCheck.Time = now
		return
	end
	if now - stuckCheck.Time < 1.1 then
		return
	end
	local moved = (flat(L.Root.Position) - flat(stuckCheck.Pos)).Magnitude
	stuckCheck.Pos = L.Root.Position
	stuckCheck.Time = now
	if moved < 1.2 and L.Hum.WalkSpeed > 1 then
		L.StuckCount = (L.StuckCount or 0) + 1
		if handleObstacle() then
			return
		end
		local wp = L.Path and L.Path[L.PathIndex]
		if wp and L.StuckCount <= 3 then
			-- detour with PathfindingService
			local detour = localPath(L.Root.Position, wp)
			if detour then
				for i = #detour, 1, -1 do
					table.insert(L.Path, L.PathIndex, detour[i])
				end
				return
			end
		end
		if L.StuckCount > 6 then
			-- really stuck: hop to the nearest lane node out of sight
			local node = Nav.NodeAt(State.Plan, L.Root.Position.X, L.Root.Position.Y, L.Root.Position.Z)
			if node then
				local n = State.Plan.Nav.Nodes[node]
				L.Model:PivotTo(CFrame.new(n.X, n.Y + 6, n.Z))
			end
			L.StuckCount = 0
		end
		clearPath()
	else
		L.StuckCount = 0
	end
end

-- DAY: it roams the aisles but never hunts, breaks or attacks. Now and then it stops and
-- stares at a shopper it can see, then wanders off again.
local function tickDay(dt: number)
	local now = os.clock()
	setSpeed(LC.DayPatrolSpeed or 6.5)
	if L.StareAt then
		if now < (L.StareUntil or 0) and L.StareAt.Parent and Survival.IsActive(L.StareAt) then
			L.Hum:MoveTo(L.Root.Position)
			return
		end
		L.StareAt = nil
		L.Model:SetAttribute("Watching", 0)
	end
	if now > (L.NextStare or 0) then
		L.NextStare = now + 1.5
		for _, p in Survival.ActivePlayers() do
			local seen, d = sees(p)
			if seen and d < 70 then
				L.StareAt = p
				L.StareUntil = now + rng:Range(2.5, 4.5)
				L.NextStare = now + rng:Range(14, 24)
				L.Model:SetAttribute("Watching", p.UserId)
				L.Model:SetAttribute("Sniff", now)
				cue("LocustClick")
				clearPath()
				L.Hum:MoveTo(L.Root.Position)
				return
			end
		end
	end
	if not L.Path or L.Goal == nil then
		if now < (L.PauseUntil or 0) then
			L.Hum:MoveTo(L.Root.Position)
			return
		end
		goTo(pickPatrolTarget())
	end
	if follow() then
		L.PauseUntil = now + rng:Range(1.5, 4)
		clearPath()
		return
	end
	-- stuck? never break anything by day: just go somewhere else
	if not L.DayStuckPos or now - (L.DayStuckTime or 0) > 2 then
		if L.DayStuckPos and (flat(L.Root.Position) - flat(L.DayStuckPos)).Magnitude < 1 then
			clearPath()
		end
		L.DayStuckPos = L.Root.Position
		L.DayStuckTime = now
	end
end

local function tick(dt: number)
	if not L or not L.Model.Parent then
		return
	end
	local now = os.clock()
	L.Model:SetAttribute("Speed", L.Hum.WalkSpeed)
	if L.Passive and L.State ~= "Spawning" and L.State ~= "Leaving" then
		tickDay(dt)
		for _, p in Players:GetPlayers() do
			local pos = Survival.Position(p)
			if pos then
				p:SetAttribute("LocustDistance", math.floor((pos - L.Root.Position).Magnitude))
				p:SetAttribute("LocustHunting", false)
			end
		end
		return
	end
	if L.State == "Spawning" then
		L.Hum:MoveTo(L.Root.Position)
		if now - L.StateSince > 3 then
			setState("Patrol")
		end
		return
	end
	if L.State == "Leaving" then
		return
	end
	if L.State == "Stunned" then
		setSpeed(0)
		if now > L.StunUntil then
			L.Model:SetAttribute("StunnedUntil", 0)
			setState(if L.Target then "Chase" else "Search")
			if not L.Target then
				startSearch(L.Root.Position, 6)
			end
		end
		return
	end
	if L.State == "Retreat" then
		tickRetreat(dt)
		return
	end
	doorsAhead()

	-- senses
	if L.State ~= "Chase" then
		local seen = updateAwareness(dt)
		if seen then
			startChase(seen)
		elseif L.State ~= "Break" and L.State ~= "Shriek" then
			local noise = hear()
			if noise and noise ~= L.LastNoise then
				L.LastNoise = noise
				local source = noise.Source
				-- a very loud noise close by from a visible player = straight to the chase
				if typeof(source) == "Instance" and source:IsA("Player") and Survival.IsTargetable(source) and (L.Awareness[source] or 0) > 0.5 then
					startChase(source)
				elseif not L.InvestigatePos or (noise.Pos - L.InvestigatePos).Magnitude > 12 or L.State ~= "Investigate" then
					cue("LocustHears")
					startInvestigate(noise.Pos)
				end
			end
			-- drawn to lights
			if L.Stats.Night >= 3 and now > (L.NextLightCheck or 0) and L.State == "Patrol" then
				L.NextLightCheck = now + 18
				for _, s in lazy("Power").PoweredLights() do
					local p = s.Model:GetPivot().Position
					if (p - L.Root.Position).Magnitude < 160 and rng:Chance(0.35) then
						startInvestigate(p)
						break
					end
				end
			end
			-- shriek ability
			if L.Stats.Abilities.Shriek and now > (L.NextShriek or 0) and (L.State == "Patrol" or L.State == "Search") then
				L.NextShriek = now + rng:Range(45, 75)
				L.Model:SetAttribute("Shriek", now)
				cue("Shriek")
				setState("Shriek")
			end
		end
	else
		-- while chasing, switch to a much closer visible player
		local other = updateAwareness(dt)
		if other and other ~= L.Target then
			local a, b = Survival.Position(other), L.Target and Survival.Position(L.Target)
			if a and (not b or (a - L.Root.Position).Magnitude + 15 < (b - L.Root.Position).Magnitude) then
				startChase(other)
			end
		end
	end

	if L.State == "Patrol" then
		tickPatrol(dt)
	elseif L.State == "Investigate" then
		tickInvestigate(dt)
	elseif L.State == "Search" then
		tickSearch(dt)
	elseif L.State == "Chase" then
		tickChase(dt)
	elseif L.State == "Break" then
		tickBreak(dt)
	elseif L.State == "Shriek" then
		tickShriek()
	end
	tickStuck()

	-- proximity info for clients (heartbeat / warnings): distance replicated per player
	for _, p in Players:GetPlayers() do
		local pos = Survival.Position(p)
		if pos then
			local d = (pos - L.Root.Position).Magnitude
			p:SetAttribute("LocustDistance", math.floor(d))
			p:SetAttribute("LocustHunting", L.Target == p)
		end
	end
end

--============================ NYMPHS ============================--
local function spawnNymph(near: Vector3)
	local model = LocustRig.Build({ Body = "2a1a12", Shell = "3d2a1c", Eyes = "ff7a1a", Name = "NYMPH" }, 0.42)
	model.Name = "Nymph"
	model:PivotTo(CFrame.new(near + Vector3.new(rng:Range(-6, 6), 2, rng:Range(-6, 6))))
	model.Parent = World.Folders.Dynamic
	local root = model.PrimaryPart
	root:SetNetworkOwner(nil)
	local hum = model:FindFirstChildOfClass("Humanoid")
	hum.WalkSpeed = 15
	table.insert(nymphs, { Model = model, Root = root, Hum = hum, Until = os.clock() + 60, Goal = nil, NextCall = 0 })
end

local function tickNymphs()
	local now = os.clock()
	for i = #nymphs, 1, -1 do
		local n = nymphs[i]
		if now > n.Until or not n.Model.Parent then
			n.Model:Destroy()
			table.remove(nymphs, i)
		else
			if not n.Goal or (flat(n.Root.Position) - flat(n.Goal)).Magnitude < 5 then
				local cell = cellOf(n.Root.Position)
				if cell then
					local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
					local d = dirs[rng:Int(1, 4)]
					n.Goal = Vector3.new(cell.X + d[1] * 36, cell.Y + 2, cell.Z + d[2] * 36)
				end
			end
			if n.Goal then
				n.Hum:MoveTo(n.Goal)
			end
			if now > n.NextCall then
				for _, p in Survival.ActivePlayers() do
					local pos = Survival.Position(p)
					if pos and Survival.IsTargetable(p) and (pos - n.Root.Position).Magnitude < 45 and lineOfSight(n.Root.Position + Vector3.new(0, 1.5, 0), pos) then
						n.NextCall = now + 8
						Noise.Emit(pos, 2.2, nil, "Nymph")
						State.Cue("NymphCall", n.Root.Position, nil)
						break
					end
				end
			end
		end
	end
end

--============================ LIFECYCLE ============================--
-- passive = the harmless daytime roamer. Spawning the night Locust while the day one is
-- around wakes it up where it stands (no pop-in).
function Locust.Spawn(night: number, passive: boolean?)
	if L and L.Passive and not passive and L.Model.Parent then
		local stats = Config.LocustStats(night, State.ModeInfo.LocustMult or 1)
		stats.Resolve *= L.Variant.ResolveMult or 1
		setupPaths(stats)
		L.Stats = stats
		L.Passive = false
		L.Resolve = stats.Resolve
		L.MaxResolve = stats.Resolve
		L.StareAt = nil
		L.NextShriek = os.clock() + 40
		L.NextNymphs = os.clock() + 30
		clearPath()
		setState("Patrol")
		L.Model:SetAttribute("Passive", false)
		L.Model:SetAttribute("Watching", 0)
		L.Model:SetAttribute("Night", night)
		L.Model:SetAttribute("Resolve", 1)
		cue("LocustScreech")
		return L
	end
	Locust.Despawn(true)
	local mult = State.ModeInfo.LocustMult or 1
	local stats = Config.LocustStats(night, mult)
	local variant = Config.VariantFor(night)
	stats.Resolve *= variant.ResolveMult or 1
	setupPaths(stats)
	local model = LocustRig.Build(variant, 1)
	model.Name = "Locust"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local pos = farNode(LC.SpawnMinDistance)
	model:PivotTo(CFrame.new(pos + Vector3.new(0, 1, 0)))
	model.Parent = World.Folders.Dynamic
	local root = model.PrimaryPart :: BasePart
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.CollisionGroup = "Locust"
		end
	end
	root:SetNetworkOwner(nil)
	local hum = model:FindFirstChildOfClass("Humanoid")
	L = {
		Model = model,
		Root = root,
		Hum = hum,
		Stats = stats,
		Variant = variant,
		State = "Spawning",
		StateSince = os.clock(),
		Awareness = {},
		NextAttack = 0,
		StunUntil = 0,
		Resolve = stats.Resolve,
		MaxResolve = stats.Resolve,
		Contributors = {},
		LastSeen = 0,
		NextShriek = os.clock() + 40,
		NextNymphs = os.clock() + 30,
		Passive = passive == true,
	}
	model:SetAttribute("Passive", passive == true)
	model:SetAttribute("State", "Spawning")
	model:SetAttribute("Emerge", State.Now())
	model:SetAttribute("Night", night)
	model:SetAttribute("Resolve", 1)
	State.SetAttr("LocustVariant", variant.Name)
	if not passive then
		State.Cue("LocustSpawn", pos, variant.Name)
	end
	-- memory fades a little each night
	for id, h in memory.Heat do
		memory.Heat[id] = h * LC.MemoryDecayPerNight
	end
	return L
end

function Locust.Despawn(instant: boolean?)
	for _, n in nymphs do
		n.Model:Destroy()
	end
	table.clear(nymphs)
	if not L then
		return
	end
	local old = L
	L = nil
	for _, p in Players:GetPlayers() do
		p:SetAttribute("LocustDistance", nil)
		p:SetAttribute("LocustHunting", false)
	end
	if instant then
		old.Model:Destroy()
	else
		old.Model:SetAttribute("State", "Leaving")
		old.Model:SetAttribute("Leave", State.Now())
		State.Cue("LocustLeave", old.Root.Position, nil)
		old.Hum:MoveTo(old.Root.Position)
		task.delay(2.5, function()
			old.Model:Destroy()
		end)
	end
end

function Locust.Get()
	return L
end

function Locust.Nymphs()
	return nymphs
end

function Locust.ResetMemory()
	table.clear(memory.Heat)
	table.clear(memory.Bases)
	table.clear(blockedLinks)
end

function Locust.Init()
	-- learn where players spend time (day and night)
	task.spawn(function()
		while true do
			task.wait(10)
			if State.RunActive and State.Plan then
				for _, p in Survival.ActivePlayers() do
					local pos = Survival.Position(p)
					if pos then
						heatAt(pos, 1)
					end
				end
			end
		end
	end)
	lazy("Building").Placed:Connect(function(s)
		local pos = s.Model:GetPivot().Position
		heatAt(pos, 3)
		if #memory.Bases == 0 or (memory.Bases[#memory.Bases] - pos).Magnitude > 40 then
			table.insert(memory.Bases, pos)
			if #memory.Bases > 20 then
				table.remove(memory.Bases, 1)
			end
		end
	end)
	-- the brain
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.2)
			local now = os.clock()
			local dt = now - last
			last = now
			if L then
				local ok, err = pcall(tick, dt)
				if not ok then
					warn("[Locust] " .. tostring(err))
					if L then
						clearPath()
						setState("Patrol")
					end
				end
				-- nymph swarm
				if L and not L.Passive and L.Stats.Abilities.Nymphs and now > L.NextNymphs and #nymphs < 2 + (L.Variant.NymphBonus or 0) then
					L.NextNymphs = now + 80
					spawnNymph(L.Root.Position)
					spawnNymph(L.Root.Position)
					State.Cue("NymphSwarm", L.Root.Position, nil)
				end
			end
			if #nymphs > 0 then
				pcall(tickNymphs)
			end
		end
	end)
end

return Locust
