local SIM = G.SIM
local MODE = G.TEST_MODE
game._props.PrivateServerId = "PSID-1"
G.MEM["SC_MatchInfo_v1"] = { ["PSID-1"] = { Mode = MODE } }
G.MEM["SC_OpenMatches_v1_" .. MODE] = { ["PSID-1"] = { AccessCode = "A", Players = 0, Updated = os.time(), Mode = MODE } }

task.spawn(function()
	SIM.runChunk(SIM.SSS.ServerMain)
end)

local players = {}
for i = 1, G.TEST_PLAYERS do
	table.insert(players, G.AddPlayer("P" .. i))
end

local Config = require(SIM.RS.Modules.Config)
local cfg = Config.Modes[MODE]

-- bots: hunters chase the nearest prey, prey runs away from the nearest hunter
local function hrp(p)
	return p.Character and p.Character:FindFirstChild("HumanoidRootPart")
end
task.spawn(function()
	while true do
		task.wait(0.1)
		for _, p in SIM.Players:GetPlayers() do
			local root = hrp(p)
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			local role = p:GetAttribute("Role")
			if root and hum and role and hum.WalkSpeed > 0 then
				local wantHunt = role == cfg.HunterRole
				local best, bestD = nil, math.huge
				for _, q in SIM.Players:GetPlayers() do
					local qr = hrp(q)
					local qrole = q:GetAttribute("Role")
					if q ~= p and qr and qrole and ((wantHunt and qrole == cfg.PreyRole) or (not wantHunt and qrole == cfg.HunterRole)) then
						local d = (qr.Position - root.Position).Magnitude
						if d < bestD then
							best, bestD = qr, d
						end
					end
				end
				if best and bestD > 0.01 then
					local dir = (best.Position - root.Position)
					dir = Vector3.new(dir.X, 0, dir.Z)
					dir = dir * (1 / math.max(dir.Magnitude, 0.001))
					local speed = hum.WalkSpeed * (if wantHunt then 1 else 0.85) -- prey bots are a bit slower so catches happen
					local sign = if wantHunt then 1 else -1
					local np = root.Position + dir * (speed * 0.1 * sign)
					-- stay inside a 60 stud arena around the map centre
					np = Vector3.new(math.clamp(np.X, 940, 1060), np.Y, math.clamp(np.Z, -60, 60))
					root._props.Position = np
				end
			end
		end
	end
end)

-- exploit test: at t=60 a hunter teleports right onto a prey; must NOT tag for a moment
local exploitAt = 60
task.delay(exploitAt, function()
	for _, p in SIM.Players:GetPlayers() do
		if p:GetAttribute("Role") == cfg.HunterRole and hrp(p) then
			local far, farD = nil, 0
			for _, q in SIM.Players:GetPlayers() do
				if q:GetAttribute("Role") == cfg.PreyRole and hrp(q) then
					local d = (hrp(q).Position - hrp(p).Position).Magnitude
					if d > farD then
						far, farD = q, d
					end
				end
			end
			if far and farD > 20 then
				SIM.log(string.format("EXPLOIT TEST: %s teleports %.0f studs onto %s", p.Name, farD, far.Name))
				hrp(p)._props.Position = hrp(far).Position + Vector3.new(1, 0, 0)
				G.EXPLOIT = { hunter = p, prey = far, t = SIM.now() }
				return
			end
		end
	end
	SIM.log("EXPLOIT TEST skipped (no far prey)")
end)

-- a player leaves mid-round at t=G.LEAVE_AT
if G.LEAVE_AT then
	task.delay(G.LEAVE_AT, function()
		local p = players[1]
		SIM.log("LEAVE TEST: " .. p.Name .. " (" .. tostring(p:GetAttribute("Role")) .. ") leaves")
		G.RemovePlayer(p)
	end)
end

SIM.runUntil(G.TEST_DURATION)

-- report
local lastState = nil
for _, f in G.FIRED do
	local pl = f.payload
	if f.remote == "RoundState" and pl.RoundState ~= lastState then
		lastState = pl.RoundState
		print(string.format("[%6.1f] STATE %-12s %s", f.t, pl.RoundState, if pl.Waiting then "(waiting)" else ""))
	elseif f.remote == "UpdateRole" and f.to == "*" then
		print(string.format("[%6.1f] FEED  %s", f.t, tostring(pl.Text)))
	elseif f.remote == "UpdateRole" then
		print(string.format("[%6.1f] YOU   %s -> %s", f.t, f.to, tostring(pl.Text)))
	elseif f.remote == "Countdown" then
		print(string.format("[%6.1f] REVEAL %s %s", f.t, pl.RevealTitle, table.concat(pl.RevealNames, ",")))
	elseif f.remote == "ShowResults" and not pl.Spectator then
		print(string.format("[%6.1f] RESULT %s: %s won=%s caught=%d survived=%ds coins=%d xp=%d", f.t, f.to, pl.Title, tostring(pl.Won), pl.Caught, pl.SurvivalTime, pl.Coins, pl.XP))
	end
end
for _, line in SIM.LOG do
	print(line)
end
-- did the exploit tag happen within 2s?
if G.EXPLOIT then
	local e = G.EXPLOIT
	for _, f in G.FIRED do
		if f.remote == "UpdateRole" and f.to == "*" and f.t >= e.t and f.t < e.t + 1.9 and tostring(f.payload.Text):find(e.hunter.Name .. " caught " .. e.prey.Name, 1, true) then
			print("!! EXPLOIT TAG WENT THROUGH at " .. f.t)
			G.EXPLOIT_FAIL = true
		end
	end
end
	if not G.EXPLOIT_FAIL then
		print("EXPLOIT TEST OK: teleporting hunter could not tag for the suspicious window")
	end
-- remove everyone, check saved data
for _, p in SIM.Players:GetPlayers() do
	G.RemovePlayer(p)
end
SIM.runUntil(G.TEST_DURATION + 30)
for k, v in G.DATA do
	print(string.format("SAVED %s coins=%d xp=%d wins=%d losses=%d games=%d catches=%d infections=%d survival=%d lock=%s", k, v.Coins, v.XP, v.Wins, v.Losses, v.GamesPlayed, v.Catches, v.Infections, v.SurvivalTime, tostring(v.Lock)))
end
