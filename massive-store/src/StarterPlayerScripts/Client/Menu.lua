--[[
	Menu: the main menu (over the 3D MenuScene).
	  PLAY       pick a mode and enter the store
	  SERVERS    running stores (join friends / other modes)
	  INVENTORY  your locker: equip titles, flashlight beams, cart paint, effects; see unlocks
	  SHOP       Store Credits cosmetics (+ optional credit packs)
	  MISSIONS   today's missions and your stats
	  SETTINGS   audio, effects, camera shake, brightness
	  CREDITS
	In the store a small MENU button lets you go back here.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local Missions = require(Shared.Missions)
local Progression = require(Shared.Progression)
local Util = require(Shared.Util)
local Net = require(Shared.Net)

local UI = require(script.Parent.UI)
local ClientState = require(script.Parent.ClientState)
local Audio = require(script.Parent.Audio)
local MenuScene = require(script.Parent.MenuScene)
local Atmosphere = require(script.Parent.Atmosphere)

local Menu = {}

local player = Players.LocalPlayer
local C = UI.C
local make = UI.make

local gui, root, content, navButtons, profile
local ingameGui, confirmBox
local page = nil
local selectedMode = nil
local toastFn = function(_t, _k) end

--============================ LOGO ============================--
local function logo(parent, scale: number?)
	local s = scale or 1
	local box = make("Frame", { Name = "Logo", BackgroundTransparency = 1, Size = UDim2.fromOffset(380 * s, 120 * s) }, parent)
	local sign = make("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Size = UDim2.fromOffset(380 * s, 74 * s) }, box)
	UI.corner(sign, 8 * s)
	make("UIGradient", { Color = ColorSequence.new(Color3.fromHex("ffd84d"), Color3.fromHex("f0b400")), Rotation = 90 }, sign)
	make("UIStroke", { Color = Color3.fromHex("6b4e00"), Thickness = 2 * s }, sign)
	UI.text(sign, "MASSIVE STORE", 44 * s, Color3.fromHex("141414"), UI.Title, { TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, -2 * s) })
	local stripe = make("Frame", { BackgroundColor3 = Color3.fromHex("c4161c"), BorderSizePixel = 0, Position = UDim2.fromOffset(0, 74 * s), Size = UDim2.fromOffset(380 * s, 30 * s) }, box)
	UI.corner(stripe, 4 * s)
	UI.text(stripe, "L  O  C  U  S  T", 18 * s, Color3.new(1, 1, 1), UI.Caps, { TextXAlignment = Enum.TextXAlignment.Center })
	-- a flickering "light" on the sign
	task.spawn(function()
		while box.Parent do
			task.wait(math.random(20, 60) / 10)
			for _ = 1, math.random(1, 3) do
				sign.BackgroundTransparency = 0.5
				task.wait(0.05)
				sign.BackgroundTransparency = 0
				task.wait(0.07)
			end
		end
	end)
	return box
end
Menu.Logo = logo

--============================ HELPERS ============================--
local function clear()
	content:ClearAllChildren()
	UI.pad(content, 22, 18)
end

local function header(text: string, sub: string?)
	UI.text(content, text, 26, C.Text, UI.Title, { Size = UDim2.new(1, 0, 0, 30) })
	if sub then
		UI.text(content, sub, 12, C.Muted, UI.Bold, { Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 16) })
	end
end

local function scroll(y: number)
	local s = make("ScrollingFrame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 1, -y), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4, BorderSizePixel = 0 }, content)
	return s
end

local function tabs(parent, list, selected, onPick)
	local bar = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30) }, parent)
	UI.list(bar, 6, true)
	for i, t in list do
		local b = UI.button(bar, { Text = t.Text, Size = UDim2.fromOffset(t.Width or 92, 28), TextSize = 11, LayoutOrder = i, Style = if t.Id == selected then "Primary" else "Dark" })
		b.Activated:Connect(function()
			onPick(t.Id)
		end)
	end
	return bar
end

--============================ PAGES ============================--
local PAGES = {}

PAGES.PLAY = function()
	clear()
	header("CHOOSE A MODE", "Every server is a different store. Every night is worse.")
	local serverMode = ReplicatedStorage:GetAttribute("Mode") or "Survival"
	selectedMode = selectedMode or serverMode
	local grid = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 0, 300) }, content)
	make("UIGridLayout", { CellSize = UDim2.new(0.5, -6, 0, 140), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	for i, id in Config.ModeOrder do
		local m = Config.Modes[id]
		local color = Color3.fromHex(m.Color)
		local card = make("TextButton", { AutoButtonColor = false, Text = "", BackgroundColor3 = C.Panel2, BackgroundTransparency = 0.1, LayoutOrder = i }, grid)
		UI.corner(card, 10)
		local stroke = UI.stroke(card, if selectedMode == id then color else C.Line, if selectedMode == id then 2 else 1)
		make("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.new(0, 4, 1, -20), Position = UDim2.fromOffset(10, 10) }, card)
		UI.text(card, m.Name, 20, color, UI.Title, { Position = UDim2.fromOffset(24, 12), Size = UDim2.new(1, -34, 0, 24) })
		UI.text(card, m.Desc, 12, C.Text, UI.Body, { Position = UDim2.fromOffset(24, 40), Size = UDim2.new(1, -34, 0, 54), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
		UI.text(card, ("UP TO %d PLAYERS%s"):format(m.MaxPlayers, if id == serverMode then " · THIS SERVER" else ""), 10, C.Muted, UI.Caps, { Position = UDim2.fromOffset(24, 108), Size = UDim2.new(1, -34, 0, 14) })
		card.Activated:Connect(function()
			selectedMode = id
			Audio.Play("Click")
			PAGES.PLAY()
		end)
		card.MouseEnter:Connect(function()
			if selectedMode ~= id then
				stroke.Color = C.Dim
			end
			Audio.Play("Hover")
		end)
		card.MouseLeave:Connect(function()
			if selectedMode ~= id then
				stroke.Color = C.Line
			end
		end)
	end
	local night = ReplicatedStorage:GetAttribute("Night") or 0
	local phase = ReplicatedStorage:GetAttribute("Phase") or "Waiting"
	local info = if phase == "Waiting" then "THE STORE IS CLOSED · BE THE FIRST INSIDE" else ("THIS STORE: %s · %s %d · %d PLAYERS"):format(Config.Modes[serverMode].Name, if phase == "Night" then "NIGHT" else "DAY", if phase == "Night" then night else night + 1, #Players:GetPlayers())
	UI.text(content, info, 11, C.Muted, UI.Caps, { Position = UDim2.new(0, 0, 1, -82), Size = UDim2.new(1, 0, 0, 14) })
	local label = if selectedMode == serverMode and selectedMode ~= "Solo" then "ENTER THE STORE" else "FIND A " .. Config.Modes[selectedMode].Name .. " STORE"
	local go = UI.button(content, { Text = label, Style = "Primary", Size = UDim2.new(1, 0, 0, 52), Position = UDim2.new(0, 0, 1, -60), TextSize = 20, Font = UI.Title })
	go.Activated:Connect(function()
		go.Text = "OPENING THE DOORS..."
		Net.Event("Play"):FireServer(selectedMode)
	end)
end

PAGES.SERVERS = function()
	clear()
	header("SERVERS", "Running stores. Join friends or another mode.")
	local refresh = UI.button(content, { Text = "REFRESH", Size = UDim2.fromOffset(110, 30), Position = UDim2.new(1, -110, 0, 4), TextSize = 12 })
	local list = scroll(62)
	UI.list(list, 6)
	local function load()
		list:ClearAllChildren()
		UI.list(list, 6)
		UI.text(list, "Looking for stores...", 13, C.Muted, UI.Bold, { Size = UDim2.new(1, 0, 0, 20) })
		local ok, servers = pcall(function()
			return Net.Function("GetServers"):InvokeServer()
		end)
		list:ClearAllChildren()
		UI.list(list, 6)
		if not ok or not servers then
			UI.text(list, "Couldn't load servers. Try again in a moment.", 13, C.Muted, UI.Bold, { Size = UDim2.new(1, 0, 0, 20) })
			return
		end
		for i, s in servers do
			local row = make("Frame", { BackgroundColor3 = C.Panel2, BackgroundTransparency = 0.1, Size = UDim2.new(1, -8, 0, 52), LayoutOrder = i }, list)
			UI.corner(row, 8)
			local m = Config.Modes[s.Mode] or Config.Modes.Survival
			UI.text(row, m.Name, 16, Color3.fromHex(m.Color), UI.Title, { Position = UDim2.fromOffset(14, 8), Size = UDim2.fromOffset(200, 20) })
			UI.text(row, ("%s %d · %d/%d players%s"):format(if s.Phase == "Night" then "NIGHT" else "DAY", if s.Phase == "Night" then s.Night or 0 else (s.Night or 0) + 1, s.Players or 0, s.Max or 12, if s.Here then " · YOU ARE HERE" else ""), 12, C.Muted, UI.Bold, { Position = UDim2.fromOffset(14, 28), Size = UDim2.fromOffset(320, 16) })
			local join = UI.button(row, { Text = if s.Here then "ENTER" else "JOIN", Style = "Primary", Size = UDim2.fromOffset(90, 34), Position = UDim2.new(1, -100, 0, 9), TextSize = 13 })
			join.Activated:Connect(function()
				join.Text = "..."
				local okJoin = Net.Function("JoinServer"):InvokeServer(s.Key)
				if not okJoin then
					join.Text = "FULL?"
				end
			end)
		end
		if #servers <= 1 then
			UI.text(list, "No other stores open right now. Picking a mode in PLAY opens a new one.", 12, C.Muted, UI.Bold, { Size = UDim2.new(1, 0, 0, 30), TextWrapped = true, LayoutOrder = 99 })
		end
	end
	refresh.Activated:Connect(load)
	task.spawn(load)
end

local lockerTab = "Title"
PAGES.INVENTORY = function()
	clear()
	header("LOCKER", "Your cosmetics and what you've unlocked")
	local list = { { Id = "Title", Text = "TITLES", Width = 74 }, { Id = "Outfit", Text = "OUTFITS", Width = 80 }, { Id = "Flashlight", Text = "BEAMS", Width = 70 }, { Id = "Cart", Text = "CARTS", Width = 66 }, { Id = "Effect", Text = "EFFECTS", Width = 76 }, { Id = "Emote", Text = "EMOTES", Width = 74 }, { Id = "Unlocks", Text = "UNLOCKS", Width = 80 } }
	local t = tabs(content, list, lockerTab, function(id)
		lockerTab = id
		PAGES.INVENTORY()
	end)
	t.Position = UDim2.fromOffset(0, 56)
	local s = scroll(96)
	UI.list(s, 6)
	local d = ClientState.Data
	if not d then
		return
	end
	if lockerTab == "Unlocks" then
		for i, u in Progression.Unlocks do
			local got = (d.Level or 1) >= u.Level
			local row = make("Frame", { BackgroundColor3 = C.Panel2, BackgroundTransparency = if got then 0.1 else 0.5, Size = UDim2.new(1, -8, 0, 34), LayoutOrder = i }, s)
			UI.corner(row, 6)
			UI.text(row, ("LV %d"):format(u.Level), 13, if got then C.Accent else C.Dim, UI.Mono, { Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(60, 34) })
			UI.text(row, u.Text, 13, if got then C.Text else C.Muted, UI.Bold, { Position = UDim2.fromOffset(74, 0), Size = UDim2.new(1, -110, 1, 0) })
			UI.text(row, if got then "✓" else "", 16, C.Good, UI.Title, { Position = UDim2.new(1, -30, 0, 0), Size = UDim2.fromOffset(20, 34) })
		end
		return
	end
	local n = 0
	for _, c in Cosmetics.List do
		if c.Slot == lockerTab and Cosmetics.Owns(d, d.Level or 1, c.Id) then
			n += 1
			local row = make("Frame", { BackgroundColor3 = C.Panel2, BackgroundTransparency = 0.1, Size = UDim2.new(1, -8, 0, 44), LayoutOrder = c.Order }, s)
			UI.corner(row, 6)
			local sw = make("Frame", { BackgroundColor3 = Color3.fromHex(c.Color or "8a92a2"), Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(24, 24) }, row)
			UI.corner(sw, 5)
			UI.text(row, c.Name, 15, C.Text, UI.Bold, { Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -170, 1, 0) })
			if c.Slot ~= "Emote" then
				local equipped = d.Equipped[c.Slot] == c.Id
				local b = UI.button(row, { Text = if equipped then "EQUIPPED" else "EQUIP", Style = if equipped then "Good" else "Dark", Size = UDim2.fromOffset(110, 30), Position = UDim2.new(1, -120, 0, 7), TextSize = 12 })
				b.Activated:Connect(function()
					local res = Net.Function("Shop"):InvokeServer({ Action = "Equip", Id = c.Id })
					if res and res.Message then
						toastFn(res.Message, "Warn")
					end
				end)
			else
				UI.text(row, "[H] in the store", 11, C.Muted, UI.Bold, { Position = UDim2.new(1, -140, 0, 0), Size = UDim2.fromOffset(130, 44), TextXAlignment = Enum.TextXAlignment.Right })
			end
		end
	end
	if n == 0 then
		UI.text(s, "Nothing here yet — visit the SHOP.", 13, C.Muted, UI.Bold, { Size = UDim2.new(1, 0, 0, 20) })
	end
end

local shopTab = "Title"
PAGES.SHOP = function()
	clear()
	local d = ClientState.Data
	header("SHOP", "Cosmetics only. Earn Store Credits by surviving nights and doing missions.")
	UI.text(content, ("%s CREDITS"):format(Util.Commas(d and d.Credits or 0)), 16, C.Accent, UI.Title, { Position = UDim2.new(1, -220, 0, 6), Size = UDim2.fromOffset(220, 22), TextXAlignment = Enum.TextXAlignment.Right })
	local list = { { Id = "Title", Text = "TITLES", Width = 66 }, { Id = "Outfit", Text = "OUTFITS", Width = 72 }, { Id = "Flashlight", Text = "BEAMS", Width = 62 }, { Id = "Cart", Text = "CARTS", Width = 60 }, { Id = "Effect", Text = "EFFECTS", Width = 70 }, { Id = "Emote", Text = "EMOTES", Width = 68 }, { Id = "Decor", Text = "DECOR", Width = 60 }, { Id = "Credits", Text = "+ CREDITS", Width = 84 } }
	local t = tabs(content, list, shopTab, function(id)
		shopTab = id
		PAGES.SHOP()
	end)
	t.Position = UDim2.fromOffset(0, 56)
	local s = scroll(96)
	if shopTab == "Credits" then
		UI.list(s, 8)
		for i, pack in Config.CreditProducts do
			local row = make("Frame", { BackgroundColor3 = C.Panel2, Size = UDim2.new(1, -8, 0, 56), LayoutOrder = i }, s)
			UI.corner(row, 8)
			UI.text(row, pack.Name, 16, C.Text, UI.Title, { Position = UDim2.fromOffset(14, 8), Size = UDim2.fromOffset(240, 20) })
			UI.text(row, ("%d Store Credits"):format(pack.Credits), 12, C.Accent, UI.Bold, { Position = UDim2.fromOffset(14, 30), Size = UDim2.fromOffset(240, 16) })
			local b = UI.button(row, { Text = ("R$ %d"):format(pack.Robux), Style = "Primary", Size = UDim2.fromOffset(110, 34), Position = UDim2.new(1, -120, 0, 11), TextSize = 14 })
			b.Activated:Connect(function()
				if pack.Id == 0 then
					toastFn("Credit packs aren't set up on this place yet (Config.CreditProducts).", "Warn")
					return
				end
				MarketplaceService:PromptProductPurchase(player, pack.Id)
			end)
		end
		UI.text(s, "Credits only buy cosmetics. Nothing that helps you survive is for sale.", 11, C.Muted, UI.Bold, { Size = UDim2.new(1, 0, 0, 30), TextWrapped = true, LayoutOrder = 10 })
		return
	end
	make("UIGridLayout", { CellSize = UDim2.new(0.333, -8, 0, 132), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, s)
	for _, c in Cosmetics.List do
		if c.Slot == shopTab and not c.Free then
			local owned = d and Cosmetics.Owns(d, d.Level or 1, c.Id)
			local card = make("Frame", { BackgroundColor3 = C.Panel2, BackgroundTransparency = 0.1, LayoutOrder = c.Order }, s)
			UI.corner(card, 8)
			local sw = make("Frame", { BackgroundColor3 = Color3.fromHex(c.Color or "8a92a2"), Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 0, 40) }, card)
			UI.corner(sw, 6)
			if c.Slot == "Title" then
				sw.BackgroundColor3 = C.Panel
				UI.text(sw, string.upper(c.Name), 13, Color3.fromHex(c.Color), UI.Title, { TextXAlignment = Enum.TextXAlignment.Center })
			end
			UI.text(card, c.Name, 13, C.Text, UI.Bold, { Position = UDim2.fromOffset(10, 56), Size = UDim2.new(1, -20, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd })
			local label, style = ("%d CREDITS"):format(c.Price), "Primary"
			if owned then
				label, style = "OWNED", "Good"
			elseif c.Level then
				label, style = "LEVEL " .. c.Level, "Dark"
			end
			local b = UI.button(card, { Text = label, Style = style, Size = UDim2.new(1, -20, 0, 32), Position = UDim2.new(0, 10, 1, -42), TextSize = 12 })
			b.Activated:Connect(function()
				if owned or c.Level then
					return
				end
				local res = Net.Function("Shop"):InvokeServer({ Action = "Buy", Id = c.Id })
				if res and res.Ok then
					Audio.Play("Legendary")
					toastFn("Bought " .. c.Name .. "!", "Good")
				elseif res then
					toastFn(res.Message or "Can't buy that", "Warn")
				end
			end)
		end
	end
end

PAGES.MISSIONS = function()
	clear()
	local d = ClientState.Data
	local now = os.time()
	local reset = (Util.DayNumber(now) + 1) * 86400 - now
	header("DAILY MISSIONS", ("New missions in %dh %02dm"):format(reset // 3600, (reset % 3600) // 60))
	local s = scroll(62)
	UI.list(s, 8)
	if not d then
		return
	end
	for i, id in Missions.ForDay(Util.DayNumber(now)) do
		local m = Missions.ById[id]
		local prog = if d.Missions and d.Missions.Day == Util.DayNumber(now) then d.Missions.Progress[id] or 0 else 0
		local claimed = d.Missions and d.Missions.Claimed and d.Missions.Claimed[id]
		local row = make("Frame", { BackgroundColor3 = C.Panel2, BackgroundTransparency = 0.1, Size = UDim2.new(1, -8, 0, 74), LayoutOrder = i }, s)
		UI.corner(row, 8)
		UI.text(row, m.Text, 15, C.Text, UI.Bold, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -150, 0, 20) })
		UI.text(row, ("+%d CREDITS · +%d XP"):format(m.Credits, m.XP), 11, C.Accent, UI.Caps, { Position = UDim2.fromOffset(14, 32), Size = UDim2.new(1, -150, 0, 14) })
		local _, set = UI.bar(row, C.Accent, { Position = UDim2.fromOffset(14, 54), Size = UDim2.new(1, -170, 0, 8) })
		set(prog / m.Goal)
		UI.text(row, ("%d/%d"):format(prog, m.Goal), 11, C.Muted, UI.Mono, { Position = UDim2.new(1, -150, 0, 48), Size = UDim2.fromOffset(40, 16) })
		local done = prog >= m.Goal
		local b = UI.button(row, { Text = if claimed then "CLAIMED" elseif done then "CLAIM" else "IN PROGRESS", Style = if claimed then "Dark" elseif done then "Primary" else "Ghost", Size = UDim2.fromOffset(120, 34), Position = UDim2.new(1, -130, 0, 10), TextSize = 12 })
		b.Activated:Connect(function()
			if done and not claimed then
				Net.Event("ClaimMission"):FireServer(id)
			end
		end)
	end
	local stats = d.Stats or {}
	local box = make("Frame", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.2, Size = UDim2.new(1, -8, 0, 120), LayoutOrder = 10 }, s)
	UI.corner(box, 8)
	UI.pad(box, 14, 10)
	make("UIGridLayout", { CellSize = UDim2.new(0.33, -6, 0, 30), CellPadding = UDim2.fromOffset(6, 4) }, box)
	for _, pair in { { "BEST NIGHT", d.BestNight or 0 }, { "NIGHTS SURVIVED", stats.NightsSurvived or 0 }, { "RUNS", d.Runs or 0 }, { "REVIVES", stats.Revives or 0 }, { "BUILT", stats.StructuresBuilt or 0 }, { "RARE FINDS", stats.RareFound or 0 } } do
		local cell = make("Frame", { BackgroundTransparency = 1 }, box)
		UI.text(cell, tostring(pair[2]), 16, C.Text, UI.Title, { Size = UDim2.new(1, 0, 0, 18) })
		UI.text(cell, pair[1], 9, C.Muted, UI.Caps, { Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 12) })
	end
end

local function setting(parent, key, label, order)
	local d = ClientState.Data
	local on = d and d.Settings and d.Settings[key]
	local row = make("Frame", { BackgroundColor3 = C.Panel2, BackgroundTransparency = 0.1, Size = UDim2.new(1, -8, 0, 46), LayoutOrder = order }, parent)
	UI.corner(row, 8)
	UI.text(row, label, 15, C.Text, UI.Bold, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -140, 1, 0) })
	local b = UI.button(row, { Text = if on then "ON" else "OFF", Style = if on then "Primary" else "Dark", Size = UDim2.fromOffset(90, 30), Position = UDim2.new(1, -100, 0, 8), TextSize = 13 })
	b.Activated:Connect(function()
		on = not on
		b.Text = if on then "ON" else "OFF"
		b.BackgroundColor3 = if on then C.Accent else C.Panel2
		b.TextColor3 = if on then Color3.fromHex("111111") else C.Text
		Net.Event("Settings"):FireServer(key, on)
		Menu.ApplySettings({ [key] = on })
	end)
end

PAGES.SETTINGS = function()
	clear()
	header("SETTINGS")
	local s = scroll(50)
	UI.list(s, 8)
	setting(s, "Music", "Music & drones", 1)
	setting(s, "SFX", "Sound effects", 2)
	setting(s, "Effects", "Particles & effects", 3)
	setting(s, "CameraShake", "Camera shake", 4)
	local d = ClientState.Data
	local row = make("Frame", { BackgroundColor3 = C.Panel2, BackgroundTransparency = 0.1, Size = UDim2.new(1, -8, 0, 46), LayoutOrder = 5 }, s)
	UI.corner(row, 8)
	UI.text(row, "Brightness", 15, C.Text, UI.Bold, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -240, 1, 0) })
	local value = (d and d.Settings and d.Settings.Brightness) or 0
	local label = UI.text(row, ("%+.1f"):format(value), 14, C.Accent, UI.Mono, { Position = UDim2.new(1, -150, 0, 0), Size = UDim2.fromOffset(50, 46), TextXAlignment = Enum.TextXAlignment.Center })
	for i, delta in { -0.5, 0.5 } do
		local b = UI.button(row, { Text = if delta < 0 then "−" else "+", Size = UDim2.fromOffset(36, 30), Position = UDim2.new(1, if i == 1 then -196 else -96, 0, 8), TextSize = 18 })
		b.Activated:Connect(function()
			value = math.clamp(value + delta, -1, 2)
			label.Text = ("%+.1f"):format(value)
			Net.Event("Settings"):FireServer("Brightness", value)
			Menu.ApplySettings({ Brightness = value })
		end)
	end
	UI.text(s, "Tip: the store is meant to be dark at night — raise brightness only if you really can't see.", 11, C.Muted, UI.Bold, { Size = UDim2.new(1, 0, 0, 30), TextWrapped = true, LayoutOrder = 9 })
end

PAGES.CREDITS = function()
	clear()
	header("CREDITS")
	local s = scroll(50)
	UI.list(s, 6)
	local lines = {
		{ "MASSIVE STORE: LOCUST", C.Accent, UI.Title, 18 },
		{ "An original survival horror game made for Roblox.", C.Text, UI.Bold, 13 },
		{ " ", C.Text, UI.Bold, 8 },
		{ "Design, code, map generator, AI, UI & sound design", C.Muted, UI.Caps, 11 },
		{ "Built entirely in Luau — every model, icon and sound is made in code.", C.Text, UI.Body, 13 },
		{ " ", C.Text, UI.Bold, 8 },
		{ "THANK YOU FOR SHOPPING AT MASSIVE STORE", C.Muted, UI.Caps, 11 },
		{ "We are not responsible for anything that happens after closing time.", C.Text, UI.Body, 13 },
	}
	for i, l in lines do
		UI.text(s, l[1], l[4], l[2], l[3], { Size = UDim2.new(1, 0, 0, l[4] + 8), LayoutOrder = i, TextWrapped = true })
	end
end

--============================ NAV ============================--
local function open(name: string)
	page = name
	for n, b in navButtons do
		local sel = n == name
		b.Bar.Visible = sel
		b.Button.TextColor3 = if sel then C.Accent else C.Text
	end
	content.Visible = true
	local scale = content:FindFirstChildOfClass("UIScale") or make("UIScale", {}, content)
	scale.Scale = 0.97
	UI.tween(scale, 0.2, { Scale = 1 })
	PAGES[name]()
	Audio.Play("Open")
end

local function buildProfile()
	local d = ClientState.Data
	profile:ClearAllChildren()
	UI.pad(profile, 14, 10)
	UI.text(profile, player.DisplayName, 16, C.Text, UI.Title, { Size = UDim2.new(1, 0, 0, 20) })
	if not d then
		return
	end
	local title = Cosmetics.Get(d.Equipped and d.Equipped.Title or "")
	UI.text(profile, if title then string.upper(title.Name) else "", 10, if title then Color3.fromHex(title.Color) else C.Muted, UI.Caps, { Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 14) })
	UI.text(profile, ("LEVEL %d"):format(d.Level or 1), 13, C.Accent, UI.Title, { Position = UDim2.fromOffset(0, 40), Size = UDim2.fromOffset(100, 16) })
	local _, set = UI.bar(profile, C.Accent, { Position = UDim2.fromOffset(84, 45), Size = UDim2.new(1, -84, 0, 6) })
	set((d.LevelXP or 0) / math.max(1, d.LevelXPNeeded or 100))
	UI.text(profile, ("%s CREDITS · BEST NIGHT %d"):format(Util.Commas(d.Credits or 0), d.BestNight or 0), 11, C.Muted, UI.Caps, { Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 0, 14) })
	local nextU = Progression.NextUnlock(d.Level or 1)
	if nextU then
		UI.text(profile, ("NEXT · LV %d: %s"):format(nextU.Level, nextU.Text), 10, C.Dim, UI.Bold, { Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, 0, 0, 14), TextTruncate = Enum.TextTruncate.AtEnd })
	end
	if d.Saving == false then
		UI.text(profile, "⚠ progress isn't saving on this server", 10, C.Danger, UI.Bold, { Position = UDim2.fromOffset(0, 96), Size = UDim2.new(1, 0, 0, 14) })
	end
end

local function build()
	gui, root = UI.screen("MSL_Menu", 10)
	local shade = make("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Size = UDim2.new(0, 620, 1, 0) }, root)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.7, 0.55), NumberSequenceKeypoint.new(1, 1) }) }, shade)
	local lg = logo(root, 1)
	lg.Position = UDim2.fromOffset(48, 46)

	local nav = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(48, 200), Size = UDim2.fromOffset(280, 340) }, root)
	UI.list(nav, 2)
	navButtons = {}
	for i, name in { "PLAY", "SERVERS", "INVENTORY", "SHOP", "MISSIONS", "SETTINGS", "CREDITS" } do
		local b = make("TextButton", { AutoButtonColor = false, BackgroundTransparency = 1, Text = name, FontFace = UI.Title, TextSize = if i == 1 then 34 else 22, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(280, if i == 1 then 50 else 38), LayoutOrder = i }, nav)
		UI.pad(b, 16, 0)
		local bar = make("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Position = UDim2.new(0, -16, 0.2, 0), Size = UDim2.new(0, 4, 0.6, 0), Visible = false }, b)
		b.MouseEnter:Connect(function()
			UI.tween(b, 0.12, { TextColor3 = C.Accent })
			Audio.Play("Hover")
		end)
		b.MouseLeave:Connect(function()
			if page ~= name then
				UI.tween(b, 0.12, { TextColor3 = C.Text })
			end
		end)
		b.Activated:Connect(function()
			Audio.Play("Click")
			open(name)
		end)
		navButtons[name] = { Button = b, Bar = bar }
	end

	profile = UI.panel(root, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 48, 1, -36), Size = UDim2.fromOffset(330, 116) }, 10)
	content = UI.panel(root, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -48, 0.5, 0), Size = UDim2.fromOffset(600, 560), Visible = false }, 14)
	content.BackgroundTransparency = 0.12
	UI.text(root, ("v%s · %s"):format(Config.Version, if ReplicatedStorage:GetAttribute("ServerReady") then "store open" else "loading"), 10, C.Dim, UI.Mono, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -10), Size = UDim2.fromOffset(240, 14), TextXAlignment = Enum.TextXAlignment.Right })
	buildProfile()
	ClientState.DataChanged:Connect(function()
		buildProfile()
		if gui.Enabled and page and (page == "INVENTORY" or page == "SHOP" or page == "MISSIONS") then
			PAGES[page]()
		end
	end)
	open("PLAY")
end

-- small in-game MENU button + confirm
local function buildInGame()
	local g, r = UI.screen("MSL_InGameMenu", 7)
	ingameGui = g
	local b = UI.button(r, { Text = "MENU", Size = UDim2.fromOffset(70, 26), Position = UDim2.fromOffset(22, 104), TextSize = 11, Style = "Ghost" })
	confirmBox = UI.panel(r, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 170), Visible = false }, 12)
	UI.text(confirmBox, "LEAVE THE STORE?", 22, C.Text, UI.Title, { Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Center })
	UI.text(confirmBox, "You'll drop your supplies in a bag where you stand.\nYour progress (XP, credits) is kept.", 12, C.Muted, UI.Bold, { Position = UDim2.fromOffset(20, 52), Size = UDim2.new(1, -40, 0, 40), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true })
	local yes = UI.button(confirmBox, { Text = "MAIN MENU", Style = "Danger", Size = UDim2.fromOffset(170, 40), Position = UDim2.new(0.5, -180, 1, -58) })
	local no = UI.button(confirmBox, { Text = "STAY", Style = "Primary", Size = UDim2.fromOffset(170, 40), Position = UDim2.new(0.5, 10, 1, -58) })
	b.Activated:Connect(function()
		confirmBox.Visible = true
		ClientState.SetBusy("Confirm", true)
	end)
	no.Activated:Connect(function()
		confirmBox.Visible = false
		ClientState.SetBusy("Confirm", false)
	end)
	yes.Activated:Connect(function()
		confirmBox.Visible = false
		ClientState.SetBusy("Confirm", false)
		Net.Event("Menu"):FireServer("ReturnToMenu")
	end)
	g.Enabled = false
end

function Menu.ApplySettings(s)
	if s.Music ~= nil then
		Audio.SetMusic(s.Music)
	end
	if s.SFX ~= nil then
		Audio.SetSFX(s.SFX)
	end
	if s.CameraShake ~= nil then
		Atmosphere.SetShake(s.CameraShake)
	end
	if s.Brightness ~= nil then
		Atmosphere.SetBrightness(s.Brightness)
	end
	if s.Effects ~= nil then
		for _, e in game:GetService("CollectionService"):GetTagged("OptionalEffect") do
			if e:IsA("ParticleEmitter") or e:IsA("Trail") then
				e.Enabled = s.Effects
			end
		end
	end
end

function Menu.Show()
	ClientState.MenuOpen = true
	gui.Enabled = true
	ingameGui.Enabled = false
	Atmosphere.SetMenu(true)
	Audio.SetMenu(true)
	MenuScene.Start()
	selectedMode = nil
	if page == "PLAY" or not page then
		open("PLAY")
	end
end

function Menu.Hide()
	ClientState.MenuOpen = false
	gui.Enabled = false
	ingameGui.Enabled = true
	confirmBox.Visible = false
	ClientState.SetBusy("Confirm", false)
	MenuScene.Stop()
	Atmosphere.SetMenu(false)
	Audio.SetMenu(false)
end

function Menu.Init(toast)
	toastFn = toast or toastFn
	build()
	buildInGame()
	ClientState.DataChanged:Connect(function(d)
		if d and d.Settings and not Menu.SettingsApplied then
			Menu.SettingsApplied = true
			Menu.ApplySettings(d.Settings)
		end
	end)
	ReplicatedStorage:GetAttributeChangedSignal("Mode"):Connect(function()
		if gui.Enabled and page == "PLAY" then
			PAGES.PLAY()
		end
	end)
end

return Menu
