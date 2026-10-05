-- Scenario: a server with 3 bot players playing several days and nights.
-- Bots loot, eat, build, push carts, hide, use tools, revive each other and get hunted.
-- Also fuzzes every remote with garbage. Fails on any script error.

G.STUDIO = true
local TOTAL = tonumber(G.ARG_TIME) or 1800

G.StartServer()
G.RunUntil(4)

local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local PPS = game:GetService("ProximityPromptService")
assert(RS:GetAttribute("ServerReady"), "server not ready")
local function svc(name)
	return require(SSS.Services[name])
end
local State, Survival, Inventory, World, Building, Locust, Loot = svc("State"), svc("Survival"), svc("Inventory"), svc("World"), svc("Building"), svc("Locust"), svc("Loot")
local Items = require(RS.Shared.Items)
local Remotes = RS:WaitForChild("Remotes")
local R = setmetatable({}, { __index = function(_, k) return Remotes:FindFirstChild(k) end })
function R:GetChildren() return Remotes:GetChildren() end

local stats = { Prompts = 0, Builds = 0, Uses = 0, Downs = 0, Revives = 0, Deaths = 0 }
Survival.Downed:Connect(function()
	stats.Downs += 1
end)
Survival.Revived:Connect(function()
	stats.Revives += 1
end)
Survival.Died:Connect(function()
	stats.Deaths += 1
end)

local bots = {}
for _, name in { "Alice", "Bob", "Cara" } do
	table.insert(bots, G.AddPlayer(name))
end
G.RunUntil(2)
for _, p in bots do
	assert(p:GetAttribute("DataLoaded"), "data not loaded for " .. p.Name)
	R.Play.OnServerEvent:Fire(p, "Survival")
end
G.RunUntil(3)
for _, p in bots do
	assert(p:GetAttribute("InRun"), p.Name .. " not in run")
	assert(p.Character, p.Name .. " has no character")
end
print("run started: phase", State.Phase, "players in run", #Survival.RunPlayers())

local rng = Random.new(5)
local function rootOf(p)
	return p.Character and p.Character:FindFirstChild("HumanoidRootPart")
end
local function trigger(prompt, p)
	if prompt and prompt.Parent then
		stats.Prompts += 1
		PPS.PromptTriggered:Fire(prompt, p)
	end
end
local function nearestPrompt(folder, action, pos, maxD)
	local best, bestD = nil, maxD or math.huge
	for _, d in folder:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and d:GetAttribute("Action") == action and d.Enabled ~= false then
			local par = d.Parent
			local pp = if par:IsA("BasePart") then par.Position elseif par:IsA("Model") then par:GetPivot().Position else nil
			if pp then
				local dd = (pp - pos).Magnitude
				if dd < bestD then
					best, bestD = d, dd
				end
			end
		end
	end
	return best, bestD
end
local function goNear(p, prompt)
	local par = prompt.Parent
	local pos = if par:IsA("BasePart") then par.Position else par:GetPivot().Position
	Survival.Teleport(p, CFrame.new(pos + Vector3.new(2, 3, 0)))
end
local function walkRandom(p)
	local plan = State.Plan
	local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local root = rootOf(p)
	local cell = require(RS.Shared.StoreLayout).CellAt(plan, root.Position.X, root.Position.Y, root.Position.Z)
	if cell then
		local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
		local d = dirs[rng:NextInteger(1, 4)]
		hum:MoveTo(Vector3.new(cell.X + d[1] * 35, cell.Y + 3, cell.Z + d[2] * 35))
	end
end

local BUILDS = { "WallWood", "BarricadeWood", "DoorWood", "FloorWood", "Crate", "Bed", "Lamp", "Generator", "BearTrap", "Table", "WindowWood" }

local function act(p)
	local st = Survival.Get(p)
	local root = rootOf(p)
	if not st or not root or not p:GetAttribute("InRun") then
		return
	end
	if st.Dead then
		return
	end
	local pos = root.Position
	local inv = Inventory.Get(p)
	local roll = rng:NextNumber()
	if st.Downed then
		-- teammates come help
		for _, other in bots do
			if other ~= p and Survival.IsActive(other) and rng:NextNumber() < 0.5 then
				Survival.Teleport(other, CFrame.new(pos + Vector3.new(2, 0, 0)))
				local prompt = root:FindFirstChild("RevivePrompt")
				trigger(prompt, other)
				break
			end
		end
		return
	end
	if st.Hidden then
		if roll < 0.3 then
			R.LeaveHiding.OnServerEvent:Fire(p)
		end
		return
	end
	if roll < 0.25 then
		local prompt = nearestPrompt(World.Folders.Loot, "Loot", pos)
		if prompt then
			goNear(p, prompt)
			trigger(prompt, p)
		end
	elseif roll < 0.35 then
		-- eat or use something
		for slot = 1, inv.Size do
			local s = inv.Slots[slot]
			if s then
				local item = Items.Get(s.Id)
				if (item.Category == "Food" and st.Hunger < 80) or item.Category == "Medical" or item.Tool == "Flare" or item.Tool == "NoiseMaker" or item.Category == "Battery" or item.Tool == "Repellent" or item.Tool == "SupplyBeacon" or item.Tool == "StunBaton" or item.Tool == "Crowbar" then
					stats.Uses += 1
					R.UseItem.OnServerEvent:Fire(p, slot, pos + Vector3.new(10, 0, 0))
					break
				end
			end
		end
	elseif roll < 0.5 then
		stats.Builds += 1
		R.Build.OnServerEvent:Fire(p, {
			Action = "Place",
			Id = BUILDS[rng:NextInteger(1, #BUILDS)],
			Position = Vector3.new(pos.X + rng:NextInteger(-10, 10), 0, pos.Z + rng:NextInteger(-10, 10)),
			Rotation = rng:NextInteger(0, 3) * 90,
		})
	elseif roll < 0.56 then
		local s = Building.Near(pos, 30)[1]
		if s then
			R.Build.OnServerEvent:Fire(p, { Action = ({ "Repair", "Upgrade", "Remove" })[rng:NextInteger(1, 3)], Target = s.Id })
			local prompt = s.Model:FindFirstChild("OpenContainer" .. "Prompt", true)
			if prompt then
				trigger(prompt, p)
				R.InvAction.OnServerEvent:Fire(p, { Action = "Store", Slot = rng:NextInteger(1, 12) })
				R.InvAction.OnServerEvent:Fire(p, { Action = "Take", Slot = 1 })
				R.InvAction.OnServerEvent:Fire(p, { Action = "Close" })
			end
			for _, d in s.Model:GetDescendants() do
				if d.ClassName == "ProximityPrompt" then
					trigger(d, p)
				end
			end
		end
	elseif roll < 0.62 then
		if p:GetAttribute("CartId") and p:GetAttribute("CartId") > 0 then
			R.Cart.OnServerEvent:Fire(p, { Action = "Open" })
			R.InvAction.OnServerEvent:Fire(p, { Action = "Store", Slot = rng:NextInteger(1, 12) })
			R.Cart.OnServerEvent:Fire(p, { Action = "Release" })
		else
			local prompt = nearestPrompt(World.Folders.Carts, "CartPush", pos)
			if prompt then
				goNear(p, prompt)
				trigger(prompt, p)
			end
		end
	elseif roll < 0.68 and State.Phase == "Night" then
		local prompt = nearestPrompt(World.Folders.Hiding, "Hide", pos)
		if prompt then
			goNear(p, prompt)
			trigger(prompt, p)
		end
	elseif roll < 0.72 then
		R.Flashlight.OnServerEvent:Fire(p)
		R.Reload.OnServerEvent:Fire(p)
		R.Hotbar.OnServerEvent:Fire(p, rng:NextInteger(0, 6))
	elseif roll < 0.76 then
		local prompt = nearestPrompt(World.Folders.Doors, ({ "StoreDoor", "RoomDoor", "Panel", "Gate" })[rng:NextInteger(1, 4)], pos)
		if prompt then
			goNear(p, prompt)
			trigger(prompt, p)
		end
	elseif roll < 0.79 then
		local prompt = nearestPrompt(World.Folders.Generators, ({ "GenToggle", "GenRefuel" })[rng:NextInteger(1, 2)], pos)
		if prompt then
			goNear(p, prompt)
			trigger(prompt, p)
		end
	elseif roll < 0.81 then
		local other = bots[rng:NextInteger(1, #bots)]
		if other ~= p and rootOf(other) then
			Survival.Teleport(p, CFrame.new(rootOf(other).Position + Vector3.new(3, 0, 0)))
			R.InvAction.OnServerEvent:Fire(p, { Action = "Give", Slot = rng:NextInteger(1, 6), Target = other.UserId })
		end
	elseif roll < 0.83 then
		local prompt = nearestPrompt(World.Folders.Dynamic, "OpenContainer", pos, 400)
		if prompt then
			goNear(p, prompt)
			trigger(prompt, p)
			R.InvAction.OnServerEvent:Fire(p, { Action = "TakeAll" })
		end
	else
		R.Input.OnServerEvent:Fire(p, { Sprint = rng:NextNumber() < 0.4, Crouch = rng:NextNumber() < 0.2 })
		walkRandom(p)
	end
end

-- garbage for every remote (exploit attempts)
local function fuzz(p)
	local junk = { nil, 1, -1, 0, 1e9, 0 / 0, "x", true, {}, { Action = "Move", From = "a", To = {} }, { Action = "Place", Id = "WallWood", Position = "nope", Rotation = {} }, Vector3.new(1e9, 0, 0), { Action = "Drop", Slot = 1.5 }, { Action = "Give", Target = "1", Slot = 1, Qty = "9" } }
	for _, r in R:GetChildren() do
		if r.ClassName == "RemoteEvent" then
			for _ = 1, 2 do
				r.OnServerEvent:Fire(p, junk[rng:NextInteger(1, #junk)], junk[rng:NextInteger(1, #junk)])
			end
		elseif r.ClassName == "RemoteFunction" and r.OnServerInvoke and r.Name ~= "JoinServer" then
			local ok, err = pcall(r.OnServerInvoke, p, junk[rng:NextInteger(1, #junk)])
			if not ok then
				table.insert(ERRORS, "RemoteFunction " .. r.Name .. ": " .. tostring(err))
			end
		end
	end
end

for _, p in bots do
	task.spawn(function()
		while p.Parent do
			task.wait(rng:NextNumber(0.4, 1.4))
			act(p)
		end
	end)
end
task.spawn(function()
	while true do
		task.wait(20)
		fuzz(bots[rng:NextInteger(1, #bots)])
	end
end)

local t = 0
local lastNight = 0
while t < TOTAL do
	G.RunUntil(60)
	t += 60
	local L = Locust.Get()
	local alive = 0
	for _, p in bots do
		if Survival.IsActive(p) then
			alive += 1
		end
	end
	local lootCount = #World.Folders.Loot:GetChildren()
	local structs = 0
	for _ in Building.All() do
		structs += 1
	end
	print(string.format("t=%4d phase=%-7s night=%d active=%d locust=%s loot=%d structures=%d errors=%d", t, State.Phase, State.Night, alive, if L then L.State .. "/" .. (L.Target and L.Target.Name or "-") else "none", lootCount, structs, #ERRORS))
	lastNight = math.max(lastNight, State.Night)
	if #ERRORS > 20 then
		break
	end
end

for _, p in bots do
	local d = require(SSS.Services.Data).Get(p)
	print(p.Name, "XP", d.XP, "credits", d.Credits, "best night", d.BestNight, "level", p:GetAttribute("Level"))
end
print("stats", stats.Prompts, "prompts", stats.Builds, "build attempts", stats.Uses, "uses", stats.Downs, "downs", stats.Revives, "revives", stats.Deaths, "deaths")
print("remote fires:", G.FIRED.Notify or 0, "notifies,", G.FIRED.Inventory or 0, "inventory pushes,", G.FIRED.Cue or 0, "cues")

-- leaving players and shutdown must not error
G.RemovePlayer(bots[3])
G.RunUntil(5)
G.Close()
G.RunUntil(5)

if #ERRORS > 0 then
	print(("FAILED with %d errors"):format(#ERRORS))
	for i = 1, math.min(5, #ERRORS) do
		print(ERRORS[i])
	end
	error("simulation failed")
end
assert(lastNight >= 1, "no night happened")
print("SIM OK — reached night " .. lastNight)
