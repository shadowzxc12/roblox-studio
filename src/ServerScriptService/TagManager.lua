--[[
	TagManager: server-authoritative tagging.

	How it works:
	- While a round is PLAYING, one loop checks the distance between every hunter and every prey
	  (HumanoidRootPart to HumanoidRootPart) every Config.Tag.CheckInterval seconds.
	- The client never says "I tagged someone" - there is no remote for it, so it can't be faked.
	- Only ONE tag is processed per check, so two tags can never happen at the same time.
	- Hunters have a cooldown after a tag; a freshly made hunter has to wait before tagging
	  (no instant tag-backs / tag spam).
	- Speed guard: a player who moves impossibly fast (teleport exploit) is ignored for a moment.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Modules.Config)
local RoleManager = require(script.Parent.RoleManager)

local TagManager = {}

local running = false
local runId = 0
local cooldownUntil: { [Player]: number } = {}
local suspiciousUntil: { [Player]: number } = {}
local lastPos: { [Player]: { Pos: Vector3, Time: number } } = {}
local ignoreSpeedUntil: { [Player]: number } = {}
local noTagBack: { [Player]: { Target: Player, Until: number } } = {}

local function rootOf(player: Player): BasePart?
	local char = player.Character
	if not char then
		return nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return nil
	end
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Call when the SERVER moves a character, so the speed guard doesn't flag it.
function TagManager.MarkTeleported(player: Player)
	ignoreSpeedUntil[player] = os.clock() + 1
	lastPos[player] = nil
end

-- "No tag-backs": newHunter can't tag oldHunter for a few seconds.
function TagManager.SetNoTagBack(newHunter: Player, oldHunter: Player)
	noTagBack[newHunter] = { Target = oldHunter, Until = os.clock() + Config.Tag.NoTagBackTime }
end

-- Give a player a tag cooldown (used for freshly made hunters).
function TagManager.SetCooldown(player: Player, seconds: number)
	cooldownUntil[player] = os.clock() + seconds
end

local function updateSpeedGuard(player: Player, root: BasePart, now: number)
	local prev = lastPos[player]
	lastPos[player] = { Pos = root.Position, Time = now }
	if not prev or (ignoreSpeedUntil[player] or 0) > now then
		return
	end
	local dt = now - prev.Time
	if dt <= 0 then
		return
	end
	local delta = root.Position - prev.Pos
	local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude / dt
	local hum = root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
	local walk = math.max(hum and hum.WalkSpeed or 16, 16)
	if horizontal > walk * Config.Tag.SpeedLimitMultiplier + Config.Tag.SpeedSlack then
		suspiciousUntil[player] = now + Config.Tag.SuspiciousTime
	end
end

--[[
	ctx.Mode: the mode module (HunterRole / PreyRole)
	ctx.IsParticipant(player) -> bool
	onTag(hunter, prey): called on a valid tag; the mode changes roles there
]]
function TagManager.Start(ctx, onTag: (Player, Player) -> ())
	TagManager.Stop()
	running = true
	runId += 1
	local myRun = runId
	local hunterRole = ctx.Mode.HunterRole
	local preyRole = ctx.Mode.PreyRole

	task.spawn(function()
		while running and myRun == runId do
			local now = os.clock()
			local hunters, prey = {}, {}
			for _, player in Players:GetPlayers() do
				if ctx.IsParticipant(player) then
					local root = rootOf(player)
					if root then
						updateSpeedGuard(player, root, now)
						local role = RoleManager.Get(player)
						if role == hunterRole then
							table.insert(hunters, { Player = player, Root = root })
						elseif role == preyRole then
							table.insert(prey, { Player = player, Root = root })
						end
					end
				end
			end

			local tagged = false
			for _, h in hunters do
				if tagged then
					break
				end
				local hp = h.Player
				if (cooldownUntil[hp] or 0) <= now and (suspiciousUntil[hp] or 0) <= now and not hp:GetAttribute("Frozen") then
					local blocked = noTagBack[hp]
					for _, p in prey do
						if blocked and blocked.Target == p.Player and blocked.Until > now then
							continue
						end
						local offset = p.Root.Position - h.Root.Position
						local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
						if flat <= Config.Tag.Range and math.abs(offset.Y) <= Config.Tag.MaxHeightDifference then
							cooldownUntil[hp] = now + Config.Tag.HunterCooldown
							tagged = true
							onTag(hp, p.Player)
							break
						end
					end
				end
			end
			task.wait(Config.Tag.CheckInterval)
		end
	end)
end

function TagManager.Stop()
	running = false
	runId += 1
	table.clear(cooldownUntil)
	table.clear(suspiciousUntil)
	table.clear(lastPos)
	table.clear(noTagBack)
end

Players.PlayerRemoving:Connect(function(player)
	cooldownUntil[player] = nil
	suspiciousUntil[player] = nil
	lastPos[player] = nil
	ignoreSpeedUntil[player] = nil
	noTagBack[player] = nil
end)

return TagManager
