-- Scenario: the LOBBY place (built from lobby.project.json).
--   parking-lot pads, everybody starts in a party of one, invites + accept, join by code,
--   leave, ready-up, leader picks the rules, party launch = one reserved server + one teleport
--   for the whole party, solo launch from inside a party, refused combinations, a party coming
--   back from a store is rebuilt, and the client lobby UI (main, start a run, pages, invite window).
G.STUDIO = false
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Config = require(RS.Shared.Config)

local function check(cond, msg)
	if not cond then
		table.insert(ERRORS, "CHECK FAILED: " .. msg)
		print("CHECK FAILED: " .. msg)
	else
		print("ok: " .. msg)
	end
end
local invites = {}
G.OnFireClient = function(name, player, a1)
	if name == "PartyInvite" and player then
		invites[player] = a1
	end
end

G.StartServer()
G.RunUntil(3)
check(RS:GetAttribute("Place") == "Lobby", "a public server is the lobby")
check(Workspace:FindFirstChild("Store") == nil, "no store is built in the lobby")
check(Workspace:FindFirstChild("Lobby") and #Workspace.Lobby.Pads:GetChildren() == Config.Party.Pads + 1, "parking lot pads built")
local A, B, C = G.AddPlayer("Ann"), G.AddPlayer("Ben"), G.AddPlayer("Cat")
G.StartClient(A)
G.RunUntil(8)
local Party = require(SSS.Lobby.Party)
local Remotes = RS:WaitForChild("Remotes")
local function act(p, req)
	Remotes:FindFirstChild("PartyAction").OnServerEvent:Fire(p, req)
	G.RunUntil(0.3)
end
check(A:GetAttribute("PartyId") and A:GetAttribute("PartyId") ~= B:GetAttribute("PartyId"), "everybody starts in their own party")
check((A:GetAttribute("Pad") or 0) > 0 and A:GetAttribute("Pad") ~= B:GetAttribute("Pad"), "each party has its own pad")
-- the lobby loads lobby avatars itself
G.RunUntil(0.5)
local hrp = A.Character and A.Character:FindFirstChild("HumanoidRootPart")
local padO = Workspace.Lobby.Pads:FindFirstChild("Pad" .. A:GetAttribute("Pad")):GetAttribute("Origin")
check(hrp and hrp.Anchored and (hrp.Position - padO.Position).Magnitude < 8, "Ann stands in the lineup on her pad")

-- invite + accept
act(A, { Action = "Invite", UserId = B.UserId })
check(invites[B] and invites[B].From == "Ann", "Ben got Ann's invite")
act(B, { Action = "Accept", PartyId = invites[B].PartyId })
check(A:GetAttribute("PartyId") == B:GetAttribute("PartyId") and A:GetAttribute("PartySize") == 2, "Ben joined Ann's party")
check(A:GetAttribute("PartyLeader") == true and B:GetAttribute("PartyLeader") == false, "Ann leads")
-- join by code + leave
local code = Party.Of(A).Code
act(C, { Action = "JoinCode", Code = string.lower(string.gsub(code, "-", "")) })
check(C:GetAttribute("PartyId") == A:GetAttribute("PartyId") and A:GetAttribute("PartySize") == 3, "Cat joined by code")
act(C, { Action = "Leave" })
check(C:GetAttribute("PartyId") ~= A:GetAttribute("PartyId") and A:GetAttribute("PartySize") == 2, "Cat left")
-- only the leader picks the rules; new rules reset ready
act(B, { Action = "SetMode", Mode = "Hardcore" })
check(Party.Of(A).Rules == "Survival", "members can't change the rules")
act(A, { Action = "SetMode", Mode = "Hardcore" })
check(Party.Of(A).Rules == "Hardcore", "leader picked HARDCORE")

-- client UI of Ann: party panel + start a run
local pg = A:FindFirstChild("PlayerGui")
local lobbyGui = pg:FindFirstChild("MSL_Lobby")
check(lobbyGui ~= nil, "lobby UI built")
local function count(root, name)
	local n = 0
	for _, d in root:GetDescendants() do
		if d.Name == name then
			n += 1
		end
	end
	return n
end
check(count(lobbyGui:FindFirstChild("Party", true), "Member") == 2, "party panel shows both members")
local function click(btn)
	if btn then
		btn.Activated:Fire()
		G.RunUntil(0.3)
	end
	return btn ~= nil
end
check(click(lobbyGui:FindFirstChild("PlayParty", true)), "PLAY WITH PARTY")
local run = lobbyGui:FindFirstChild("Run", true)
check(run and run.Visible, "start-a-run screen open")
check(run:FindFirstChild("Mode_Hardcore", true) ~= nil and run:FindFirstChild("Launch", true) ~= nil, "mode cards + launch bar drawn")

-- launch needs everybody ready
local before = #G.TELEPORTS
act(A, { Action = "Launch", Solo = false })
check(#G.TELEPORTS == before, "can't launch while Ben isn't ready")
act(B, { Action = "Ready", Value = true })
click(run:FindFirstChild("Launch", true)) -- Ann presses ENTER THE STORE in the UI
G.RunUntil(1)
local t = G.TELEPORTS[#G.TELEPORTS]
check(t and t.PlaceId == game.PlaceId and #t.Players == 2, "the whole party teleports to a store server of this place, together")
check(t and t.Options.ReservedServerAccessCode ~= nil, "into a brand-new reserved server")
check(t and t.Data and t.Data.Mode == "Hardcore" and type(t.Data.PartyKey) == "string" and t.Data.Leader == A.UserId, "TeleportData carries mode, party key and leader")
check(pg:FindFirstChild("MSL_Teleport") ~= nil, "teleport receipt screen shown")

-- Cat alone: SURVIVAL solo -> the Solo mode; INFECTION solo is refused
local n = #G.TELEPORTS
act(C, { Action = "Launch", Solo = true, Rules = "Infection" })
check(#G.TELEPORTS == n, "solo Infection is refused")
act(C, { Action = "Launch", Solo = true, Rules = "Survival" })
G.RunUntil(1)
local tc = G.TELEPORTS[#G.TELEPORTS]
check(#G.TELEPORTS == n + 1 and tc.Data.Mode == "Solo" and #tc.Players == 1, "solo survival -> Solo mode server")

-- a party coming back from a store is rebuilt
G.TELEPORT_DATA = { PartyKey = "job:7", Leader = G.NEXT_USER + 2, Rules = "Infection" }
local D = G.AddPlayer("Dan")
local E = G.AddPlayer("Eve")
G.RunUntil(2)
G.TELEPORT_DATA = nil
check(D:GetAttribute("PartyId") == E:GetAttribute("PartyId") and D:GetAttribute("PartySize") == 2, "returning party is regrouped")
check(E:GetAttribute("PartyLeader") == true, "with the same leader")
check(Party.Of(D).Rules == "Infection", "and the same rules")

-- pages + invite window open in the UI
for _, name in { "LOCKER", "SHOP", "SETTINGS" } do
	click(lobbyGui:FindFirstChild("Back", true) or nil)
	local main = lobbyGui:FindFirstChild("Main", true)
	if main and not main.Visible then
		for _, d in lobbyGui:GetDescendants() do
			if d.ClassName == "TextButton" and d.Name == "Back" and d.Parent and d.Parent.Visible then
				click(d)
				break
			end
		end
	end
	check(click(lobbyGui:FindFirstChild(name, true)), "open page " .. name)
	local content = lobbyGui:FindFirstChild("Content", true)
	check(content and #content:GetChildren() > 0, "page drawn " .. name)
end
if #ERRORS > 0 then
	for i = 1, math.min(10, #ERRORS) do
		print(ERRORS[i])
	end
	error("lobby scenario failed")
end
print("LOBBY SCENARIO OK")
