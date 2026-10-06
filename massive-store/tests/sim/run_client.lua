-- Scenario: the CLIENT. Runs the real loading screen, menu, HUD, inventory, build mode, map,
-- prompts, Locust animation and audio against the real server in the same fake DataModel
-- (remotes are routed both ways). Clicks through every menu page, enters the store, plays a
-- day and a night, opens every panel, then goes back to the menu.

G.STUDIO = true
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local UIS = game:GetService("UserInputService")
local PPS = game:GetService("ProximityPromptService")
local Config = require(RS.Shared.Config)
Config.Cycle.FirstDay = 20
Config.Cycle.Day = 20
Config.Cycle.Dusk = 4
Config.Cycle.NightBase = 60
Config.Cycle.Dawn = 3

G.StartServer()
G.RunUntil(4)
local function check(cond, msg)
	if not cond then
		table.insert(ERRORS, "CHECK FAILED: " .. msg)
		print("CHECK FAILED: " .. msg)
	else
		print("ok: " .. msg)
	end
end
local function svc(name)
	return require(SSS.Services[name])
end
local State, Survival, Inventory, World, Locust = svc("State"), svc("Survival"), svc("Inventory"), svc("World"), svc("Locust")

local me = G.AddPlayer("Me")
local buddy = G.AddPlayer("Buddy")
G.StartClient(me)
G.RunUntil(9)
check(me:GetAttribute("LoadingDone") == true, "loading screen finished")
local pg = me:FindFirstChild("PlayerGui")
local function gui(name)
	return pg:FindFirstChild(name)
end
check(gui("LoadingScreen") == nil, "loading screen removed")

local function findButton(root, text)
	if not root then
		return nil
	end
	for _, d in root:GetDescendants() do
		if d.ClassName == "TextButton" then
			local label = d:FindFirstChild("Label", true)
			if d.Text == text or (label and label.Text == text) then
				return d
			end
		end
	end
	return nil
end
local function click(btn)
	if btn then
		btn.Activated:Fire()
		G.RunUntil(0.3)
	end
	return btn ~= nil
end

-- Studio: lobby and store are the same server. You start in the lobby (parking lot).
check(gui("MSL_Lobby") and gui("MSL_Lobby").Enabled, "lobby shows first")
check(not gui("MSL_Menu").Enabled, "no mode picker in the store part")
check(game:GetService("Workspace"):FindFirstChild("Lobby") ~= nil and game:GetService("Workspace"):FindFirstChild("Store") ~= nil, "lobby and store live on one server")
-- buddy is already in the store (server side), so the run is Survival
game:GetService("ReplicatedStorage").Remotes:FindFirstChild("Play").OnServerEvent:Fire(buddy, "Survival")
G.RunUntil(2)
local lobby = gui("MSL_Lobby")
check(click(lobby:FindFirstChild("PlaySolo", true)), "PLAY SOLO")
check(click(lobby:FindFirstChild("Launch", true)), "ENTER THE STORE")
G.RunUntil(3)
check(me:GetAttribute("InRun") == true, "the lobby put me straight into the store")
check(gui("MSL_HUD") and gui("MSL_HUD").Enabled, "HUD visible")
check(not lobby.Enabled, "lobby hidden in the store")
check(not gui("MSL_Menu").Enabled, "menu hidden")
check(me.CameraMode == Enum.CameraMode.LockFirstPerson, "first person in the store")
check(UIS.MouseIconEnabled == false, "no mouse arrow in first person")

local function key(code)
	UIS.InputBegan:Fire({ KeyCode = code, UserInputType = Enum.UserInputType.Keyboard }, false)
	G.RunUntil(0.2)
	UIS.InputEnded:Fire({ KeyCode = code, UserInputType = Enum.UserInputType.Keyboard }, false)
	G.RunUntil(0.2)
end
local function mouse()
	UIS.InputBegan:Fire({ KeyCode = Enum.KeyCode.Unknown, UserInputType = Enum.UserInputType.MouseButton1 }, false)
	G.RunUntil(0.2)
end

-- inventory (Tab is bound through ContextActionService)
G.CAS.MSL_Inventory("MSL_Inventory", Enum.UserInputState.Begin)
G.RunUntil(0.3)
local invPanel = gui("MSL_Inventory"):FindFirstChild("Inventory", true)
check(invPanel and invPanel.Visible, "inventory opens")
-- click two grid slots (select + move) and use buttons
local grid = invPanel:FindFirstChildOfClass("ScrollingFrame")
local slots = {}
for _, c in grid:GetChildren() do
	if c.ClassName == "TextButton" then
		table.insert(slots, c)
	end
end
check(#slots >= 12, "inventory grid has slots (" .. #slots .. ")")
click(slots[3])
click(slots[9])
click(slots[9])
click(findButton(invPanel, "USE"))
click(findButton(invPanel, "DROP ONE"))
G.CAS.MSL_Inventory("MSL_Inventory", Enum.UserInputState.Begin)
G.RunUntil(0.3)
check(not invPanel.Visible, "inventory closes")
-- the raw Tab key (when the player list grabs it from ContextActionService) and I
key(Enum.KeyCode.Tab)
check(invPanel.Visible, "Tab key opens the inventory")
G.RunUntil(0.3)
key(Enum.KeyCode.Tab)
check(not invPanel.Visible, "Tab key closes it")
G.RunUntil(0.3)
key(Enum.KeyCode.I)
check(invPanel.Visible, "I opens the inventory")
G.RunUntil(0.3)
key(Enum.KeyCode.I)
check(not invPanel.Visible, "I closes it")

-- hotbar + use + flashlight + sprint/crouch
key(Enum.KeyCode.Three)
mouse()
key(Enum.KeyCode.F)
check(me:GetAttribute("FlashOn") == true, "flashlight on")
key(Enum.KeyCode.F)
UIS.InputBegan:Fire({ KeyCode = Enum.KeyCode.LeftShift, UserInputType = Enum.UserInputType.Keyboard }, false)
G.RunUntil(1)
UIS.InputEnded:Fire({ KeyCode = Enum.KeyCode.LeftShift, UserInputType = Enum.UserInputType.Keyboard }, false)
key(Enum.KeyCode.C)
key(Enum.KeyCode.C)

-- build mode: open, pick a wall, try to place, rotate, cancel
key(Enum.KeyCode.B)
local buildMenu = gui("MSL_Build"):FindFirstChild("BuildMenu", true)
check(buildMenu and buildMenu.Visible, "build menu opens")
local card
for _, d in buildMenu:GetDescendants() do
	if d.ClassName == "TextButton" and d.Text == "" and d.Name ~= "Close" then
		card = d
		break
	end
end
click(card)
key(Enum.KeyCode.R)
mouse()
G.RunUntil(0.5)
UIS.InputBegan:Fire({ KeyCode = Enum.KeyCode.Unknown, UserInputType = Enum.UserInputType.MouseButton2 }, false)
G.RunUntil(0.2)
click(findButton(buildMenu, "DOORS"))
click(findButton(buildMenu, "POWER"))
key(Enum.KeyCode.B)
check(not buildMenu.Visible, "build menu closes")

-- map
key(Enum.KeyCode.M)
local map = gui("MSL_Map"):FindFirstChild("Map", true)
check(map and map.Visible, "map opens")
click(findButton(map, "B1"))
click(findButton(map, "MAIN FLOOR"))
key(Enum.KeyCode.M)

-- pause menu + shared pages (locker, missions, settings)
key(Enum.KeyCode.P)
local pause = gui("MSL_Pause")
check(pause and pause.Enabled, "pause menu opens")
for _, entry in { { "LOADOUT & OUTFITS", "FLASHLIGHT" }, { "DAILY MISSIONS", nil }, { "SETTINGS", "ON" } } do
	check(click(findButton(pause, entry[1])), "pause page " .. entry[1])
	local content = pause:FindFirstChild("Content", true)
	check(content and #content:GetChildren() > 0, "page drawn " .. entry[1])
	if entry[2] then
		click(findButton(pause, entry[2]))
	end
	click(findButton(pause, "BACK"))
end
check(click(findButton(pause, "RESUME")), "resume")
check(not pause.Enabled, "pause menu closed")

-- first-person view model: arms + the held item in front of the camera
key(Enum.KeyCode.One)
local cam = game:GetService("Workspace").CurrentCamera
for _ = 1, 10 do
	local head = me.Character and me.Character:FindFirstChild("Head")
	if head then
		cam.CFrame = head.CFrame
	end
	G.RunUntil(0.1)
end
local vm = cam:FindFirstChild("MSL_ViewModel")
check(vm ~= nil and vm:FindFirstChild("RHand") ~= nil, "view model arms drawn")
check(me:GetAttribute("HeldItem") ~= "" and vm and #vm:GetChildren() > 12, "held item in the view model")
local held = me.Character and me.Character:FindFirstChild("HeldItem")
local grip = held and held:FindFirstChild("HeldGrip", true)
check(grip ~= nil and grip.ClassName == "Weld", "third-person item uses a real grip weld")
mouse()
check(me.Character:GetAttribute("ActionN") ~= nil, "use broadcasts an action animation")
-- character animator drove a joint
local moved = false
for _, d in me.Character:GetDescendants() do
	if d.ClassName == "Motor6D" and d.Transform ~= CFrame.new() then
		moved = true
	end
end
check(moved, "custom animation drives the joints")

-- custom prompts: show a loot prompt
local lootPrompt
for _, d in World.Folders.Loot:GetDescendants() do
	if d.ClassName == "ProximityPrompt" then
		lootPrompt = d
		break
	end
end
PPS.PromptShown:Fire(lootPrompt, Enum.ProximityPromptInputType.Keyboard)
G.RunUntil(0.3)
check(pg:FindFirstChild("Prompts") and #pg.Prompts:GetChildren() > 0, "custom prompt drawn")
lootPrompt.PromptButtonHoldBegan:Fire()
lootPrompt.Triggered:Fire()
PPS.PromptHidden:Fire(lootPrompt)
G.RunUntil(0.3)

-- live a night with the Locust nearby (animator + audio + HUD warnings)
local ok = false
for _ = 1, 200 do
	G.RunUntil(0.5)
	if State.Phase == "Night" and Locust.Get() and Locust.Get().State ~= "Spawning" then
		ok = true
		break
	end
end
check(ok, "night came")
local L = Locust.Get()
Survival.Teleport(me, CFrame.new(L.Root.Position + L.Root.CFrame.LookVector * 30))
G.RunUntil(10)
check(me:GetAttribute("LocustDistance") ~= nil, "HUD gets the Locust distance")
-- hide
local spotId, spot = next(World.HideSpots)
Survival.Teleport(me, spot.CFrame * CFrame.new(0, 0, -3))
G.RunUntil(0.2)
PPS.PromptTriggered:Fire(spot.Prompt, me)
G.RunUntil(1)
check(me:GetAttribute("Hidden") == true, "hiding (camera peeks out)")
key(Enum.KeyCode.Space)
G.RunUntil(0.5)
check(me:GetAttribute("Hidden") == false, "Space leaves the hiding spot")
-- downed overlay
Survival.Damage(me, 500, "Test")
G.RunUntil(1)
check(me:GetAttribute("Downed") == true, "downed overlay state")
Survival.Revive(me, buddy)
G.RunUntil(1)

-- results screen path: everyone down at night
for _ = 1, 200 do
	if State.Phase == "Night" then
		break
	end
	G.RunUntil(0.5)
end
G.RunUntil(3) -- revive protection wears off
Survival.Damage(me, 500, "Test")
Survival.Damage(buddy, 500, "Test")
for _ = 1, 120 do
	G.RunUntil(0.5)
	if State.Phase == "Results" then
		break
	end
end
check(State.Phase == "Results", "results screen")
G.RunUntil(1)
local results = gui("MSL_Overlay"):FindFirstChild("Results", true)
check(results ~= nil, "results screen drawn (Figma 08)")
check(click(results and results:FindFirstChild("NewStore", true)), "NEW STORE closes the results")
G.RunUntil(Config.Cycle.WipeResults + 4)

-- back to the lobby (Studio: the lobby is on this server)
key(Enum.KeyCode.P)
click(findButton(gui("MSL_Pause"), "BACK TO LOBBY"))
click(findButton(gui("MSL_Pause"), "LOBBY"))
G.RunUntil(2)
check(me:GetAttribute("InRun") == false, "returned to the lobby")
check(lobby.Enabled, "lobby showing again")
check(me.Character and me.Character:FindFirstChild("HumanoidRootPart") and me.Character.HumanoidRootPart.Anchored, "standing in the lobby lineup again")
check(UIS.MouseIconEnabled == true, "mouse arrow back in the lobby")

print("client sent:", G.CLIENT_SENT and G.CLIENT_SENT.Input, "inputs,", G.CLIENT_SENT and G.CLIENT_SENT.Build, "builds")
if #ERRORS > 0 then
	print(("FAILED with %d errors"):format(#ERRORS))
	for i = 1, math.min(10, #ERRORS) do
		print(ERRORS[i])
	end
	error("client scenario failed")
end
print("CLIENT SCENARIO OK")
