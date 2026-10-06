--[[
	Pages: full-screen menu pages shared by the lobby and the in-store pause menu.
	  LOCKER    equip titles, outfits, beams, cart paint, effects; see level unlocks
	  SHOP      Figma 07: categories · featured item · grid · Store Credit packs
	  MISSIONS  today's missions + lifetime stats
	  SETTINGS  audio, effects, camera shake, brightness, sensitivity
	  CREDITS
	Pages.Render(name, frame) fills `frame` (designed for ~1184 x 560).
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

local Pages = {}

local player = Players.LocalPlayer
local C = UI.C
local make = UI.make

Pages.Toast = function(_text: string, _kind: string?) end
Pages.OnSetting = function(_key: string, _value: any) end -- set by the place's main script

local current: Frame? = nil
local currentName: string? = nil

local function priceRarity(c): Color3
	if c.Level then
		return C.Accent
	end
	local p = c.Price or 0
	if p >= 1000 then
		return C.Accent
	elseif p >= 700 then
		return C.Purple
	elseif p >= 400 then
		return C.Info
	elseif p >= 200 then
		return C.Good
	end
	return C.Muted
end

local function rarityName(c): string
	local col = priceRarity(c)
	if c.Level then
		return "UNLOCK"
	elseif col == C.Accent then
		return "LEGENDARY"
	elseif col == C.Purple then
		return "EPIC"
	elseif col == C.Info then
		return "RARE"
	elseif col == C.Good then
		return "UNCOMMON"
	end
	return "COMMON"
end

local function header(frame: Frame, title: string, sub: string?)
	UI.text(frame, title, 34, C.Text, UI.Title, { Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, -260, 0, 40) })
	if sub then
		UI.text(frame, string.upper(sub), 11, C.Muted, UI.Caps, { Position = UDim2.fromOffset(2, 42), Size = UDim2.new(1, -260, 0, 14) })
	end
end

local function scroll(parent: Instance, pos: UDim2, size: UDim2)
	return make("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = pos,
		Size = size,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.Muted,
		BorderSizePixel = 0,
	}, parent)
end

local function card(parent: Instance, props): Frame
	local f = make("Frame", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.05, BorderSizePixel = 0 }, parent)
	UI.corner(f, 8)
	UI.stroke(f, Color3.new(1, 1, 1), 1, 0.93)
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	return f
end

-- vertical category list on the left (Figma shop / locker)
local function categories(parent: Instance, list, selected: string, onPick)
	local col = make("Frame", { Name = "Categories", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 72), Size = UDim2.new(0, 200, 1, -72) }, parent)
	UI.list(col, 8)
	for i, t in list do
		local sel = t.Id == selected
		local b = UI.button(col, { Text = t.Text, Style = if sel then "Primary" else "Dark", Size = UDim2.new(1, 0, 0, 44), LayoutOrder = i, TextSize = 16 })
		b.TextXAlignment = Enum.TextXAlignment.Left
		UI.pad(b, 18, 0)
		b.Activated:Connect(function()
			onPick(t.Id)
		end)
	end
	return col
end

local function swatch(parent: Instance, c, size: UDim2, pos: UDim2): Frame
	local sw = make("Frame", { BackgroundColor3 = Color3.fromHex(c.Color or "8a92a2"), Position = pos, Size = size, BorderSizePixel = 0, ZIndex = 3 }, parent)
	UI.corner(sw, 8)
	if c.Slot == "Title" then
		sw.BackgroundColor3 = C.Panel2
		UI.text(sw, string.upper(c.Name), 13, Color3.fromHex(c.Color or "ffffff"), UI.Title, { TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4, TextScaled = true })
		make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, sw)
	elseif c.Accent then
		local stripe = make("Frame", { BackgroundColor3 = Color3.fromHex(c.Accent), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.18, 1), ZIndex = 4 }, sw)
		UI.corner(stripe, 3)
	end
	return sw
end

--============================ LOCKER ============================--
local lockerTab = "Outfit"
local LOCKER_TABS = {
	{ Id = "Outfit", Text = "OUTFITS" },
	{ Id = "Title", Text = "TITLES" },
	{ Id = "Flashlight", Text = "FLASHLIGHT" },
	{ Id = "Cart", Text = "CART PAINT" },
	{ Id = "Effect", Text = "EFFECTS" },
	{ Id = "Emote", Text = "EMOTES" },
	{ Id = "Unlocks", Text = "LEVEL UNLOCKS" },
}

local function locker(frame: Frame)
	header(frame, "LOADOUT & OUTFITS", "what you wear into the store")
	categories(frame, LOCKER_TABS, lockerTab, function(id)
		lockerTab = id
		Pages.Refresh()
	end)
	local d = ClientState.Data
	local s = scroll(frame, UDim2.fromOffset(224, 72), UDim2.new(1, -224, 1, -72))
	if not d then
		return
	end
	if lockerTab == "Unlocks" then
		UI.list(s, 6)
		for i, u in Progression.Unlocks do
			local got = (d.Level or 1) >= u.Level
			local row = card(s, { Size = UDim2.new(1, -8, 0, 40), LayoutOrder = i, BackgroundTransparency = if got then 0.05 else 0.5 })
			UI.text(row, ("LV %d"):format(u.Level), 13, if got then C.Accent else C.Dim, UI.Mono, { Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(60, 40) })
			UI.text(row, u.Text, 13, if got then C.Text else C.Muted, UI.Semi, { Position = UDim2.fromOffset(80, 0), Size = UDim2.new(1, -150, 1, 0) })
			if got then
				UI.tag(row, "UNLOCKED", C.Good, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0) })
			end
		end
		return
	end
	make("UIGridLayout", { CellSize = UDim2.fromOffset(180, 180), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder }, s)
	local n = 0
	for _, c in Cosmetics.List do
		if c.Slot == lockerTab and Cosmetics.Owns(d, d.Level or 1, c.Id) then
			n += 1
			local box = card(s, { LayoutOrder = c.Order or n })
			make("Frame", { BackgroundColor3 = priceRarity(c), BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 4), ZIndex = 3 }, box)
			swatch(box, c, UDim2.fromOffset(56, 56), UDim2.fromOffset(16, 16))
			UI.text(box, string.upper(Cosmetics.SlotNames[c.Slot] or c.Slot), 9, C.Muted, UI.Caps, { Position = UDim2.fromOffset(16, 82), Size = UDim2.new(1, -32, 0, 12) })
			UI.text(box, c.Name, 17, C.Text, UI.Heading, { Position = UDim2.fromOffset(16, 96), Size = UDim2.new(1, -32, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd })
			if c.Slot == "Emote" then
				UI.text(box, "[H] IN THE STORE", 10, C.Muted, UI.Caps, { Position = UDim2.fromOffset(16, 140), Size = UDim2.new(1, -32, 0, 16) })
			else
				local equipped = d.Equipped[c.Slot] == c.Id
				local b = UI.button(box, { Text = if equipped then "EQUIPPED" else "EQUIP", Style = if equipped then "Good" else "Dark", Size = UDim2.new(1, -32, 0, 30), Position = UDim2.fromOffset(16, 132), TextSize = 14 })
				b.Activated:Connect(function()
					local res = Net.Function("Shop"):InvokeServer({ Action = "Equip", Id = c.Id })
					if res and res.Message then
						Pages.Toast(res.Message, "Warn")
					end
				end)
			end
		end
	end
	if n == 0 then
		UI.text(s, "Nothing here yet — visit the SHOP.", 13, C.Muted, UI.Semi, { Size = UDim2.new(1, 0, 0, 20) })
	end
end

--============================ SHOP (Figma 07) ============================--
local shopTab = "Outfit"
local SHOP_TABS = {
	{ Id = "Outfit", Text = "OUTFITS" },
	{ Id = "Flashlight", Text = "FLASHLIGHT" },
	{ Id = "Cart", Text = "CART PAINT" },
	{ Id = "Title", Text = "TITLES" },
	{ Id = "Effect", Text = "EFFECTS" },
	{ Id = "Emote", Text = "EMOTES" },
	{ Id = "Decor", Text = "BASE DECOR" },
}

local function buy(c)
	local res = Net.Function("Shop"):InvokeServer({ Action = "Buy", Id = c.Id })
	if res and res.Ok then
		Audio.Play("Legendary")
		Pages.Toast("Bought " .. c.Name .. "!", "Good")
	elseif res then
		Pages.Toast(res.Message or "Can't buy that", "Warn")
	end
end

local function priceButton(parent: Instance, c, owned: boolean, size: UDim2, pos: UDim2)
	local label, style, icon = Util.Commas(c.Price or 0), "Primary", "coin"
	if owned then
		label, style, icon = "OWNED", "Good", "check"
	elseif c.Level then
		label, style, icon = "LEVEL " .. c.Level, "Dark", "lock"
	end
	local b = UI.button(parent, { Text = label, Icon = icon, Style = style, Size = size, Position = pos, TextSize = 15 })
	b.Activated:Connect(function()
		if not owned and not c.Level then
			buy(c)
		end
	end)
	return b
end

local function shop(frame: Frame)
	local d = ClientState.Data
	header(frame, "STORE CREDITS", "cosmetic only · never pay to win")
	-- balance
	local bal = card(frame, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(220, 52) })
	UI.stroke(bal, C.Accent, 1, 0.5)
	local coin = make("Frame", { BackgroundColor3 = C.Accent, Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(24, 24), ZIndex = 3 }, bal)
	UI.corner(coin)
	UI.text(bal, Util.Commas(d and d.Credits or 0), 24, C.Accent, UI.Title, { Position = UDim2.fromOffset(48, 0), Size = UDim2.new(1, -60, 1, 0), ZIndex = 3 })

	categories(frame, SHOP_TABS, shopTab, function(id)
		shopTab = id
		Pages.Refresh()
	end)

	local list = {}
	for _, c in Cosmetics.List do
		if c.Slot == shopTab and not c.Free then
			table.insert(list, c)
		end
	end
	-- featured: the priciest thing you don't own yet
	local featured = nil
	for _, c in list do
		local owned = d and Cosmetics.Owns(d, d.Level or 1, c.Id)
		if not owned and not c.Level and (not featured or c.Price > featured.Price) then
			featured = c
		end
	end
	featured = featured or list[1]
	local mid = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(224, 72), Size = UDim2.new(1, -224 - 404, 1, -72) }, frame)
	local gridTop = 0
	if featured then
		local owned = d and Cosmetics.Owns(d, d.Level or 1, featured.Id)
		local hero = card(mid, { Size = UDim2.new(1, 0, 0, 220), ClipsDescendants = true })
		UI.stroke(hero, priceRarity(featured), 1, 0.4)
		make("UIGradient", { Color = ColorSequence.new(priceRarity(featured), C.Panel), Transparency = NumberSequence.new(0.7, 0), Rotation = 0 }, hero)
		UI.tag(hero, rarityName(featured), priceRarity(featured), { Position = UDim2.fromOffset(22, 20) })
		UI.text(hero, string.upper(featured.Name), 38, C.Text, UI.Title, { Position = UDim2.fromOffset(22, 44), Size = UDim2.new(0.62, 0, 0, 46), TextScaled = true })
		UI.text(hero, (Cosmetics.SlotNames[featured.Slot] or "") .. (if featured.Desc then " · " .. featured.Desc else ""), 12, C.Muted, UI.Body, { Position = UDim2.fromOffset(22, 96), Size = UDim2.new(0.6, 0, 0, 40), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
		priceButton(hero, featured, owned, UDim2.fromOffset(170, 48), UDim2.fromOffset(22, 152))
		swatch(hero, featured, UDim2.fromOffset(130, 150), UDim2.new(1, -160, 0, 34))
		gridTop = 232
	end
	local s = scroll(mid, UDim2.fromOffset(0, gridTop), UDim2.new(1, 0, 1, -gridTop))
	make("UIGridLayout", { CellSize = UDim2.new(0.333, -8, 0, 150), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, s)
	for i, c in list do
		local owned = d and Cosmetics.Owns(d, d.Level or 1, c.Id)
		local box = card(s, { LayoutOrder = c.Order or i })
		make("Frame", { BackgroundColor3 = priceRarity(c), BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 4), ZIndex = 3 }, box)
		swatch(box, c, UDim2.fromOffset(44, 44), UDim2.fromOffset(14, 14))
		UI.text(box, rarityName(c), 9, priceRarity(c), UI.Caps, { Position = UDim2.fromOffset(14, 64), Size = UDim2.new(1, -28, 0, 12) })
		UI.text(box, c.Name, 16, C.Text, UI.Heading, { Position = UDim2.fromOffset(14, 78), Size = UDim2.new(1, -28, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd })
		priceButton(box, c, owned, UDim2.new(1, -28, 0, 28), UDim2.fromOffset(14, 108))
	end
	-- credit packs (right column)
	local packs = card(frame, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 72), Size = UDim2.new(0, 380, 1, -72) })
	UI.text(packs, "GET CREDITS", 22, C.Text, UI.Title, { Position = UDim2.fromOffset(20, 14), Size = UDim2.new(1, -40, 0, 28) })
	UI.text(packs, "Support the store. Cosmetics only.", 11, C.Muted, UI.Body, { Position = UDim2.fromOffset(20, 44), Size = UDim2.new(1, -40, 0, 14) })
	for i, pack in Config.CreditProducts do
		local best = i == #Config.CreditProducts
		local row = make("Frame", { BackgroundColor3 = C.Panel2, BorderSizePixel = 0, Position = UDim2.fromOffset(20, 72 + (i - 1) * 108), Size = UDim2.new(1, -40, 0, 96) }, packs)
		UI.corner(row, 8)
		UI.stroke(row, if best then C.Accent else Color3.new(1, 1, 1), if best then 2 else 1, if best then 0 else 0.93)
		for k = 0, i - 1 do
			local cc = make("Frame", { BackgroundColor3 = C.Accent, BackgroundTransparency = k * 0.15, Position = UDim2.fromOffset(16 + k * 10, 30 - k * 3), Size = UDim2.fromOffset(34, 34), ZIndex = 3 + (i - k) }, row)
			UI.corner(cc)
		end
		UI.text(row, Util.Commas(pack.Credits), 28, C.Accent, UI.Title, { Position = UDim2.fromOffset(90, 14), Size = UDim2.fromOffset(130, 34) })
		UI.text(row, string.upper(pack.Name), 10, C.Muted, UI.Caps, { Position = UDim2.fromOffset(90, 54), Size = UDim2.fromOffset(130, 14) })
		local b = UI.button(row, { Text = ("R$ %d"):format(pack.Robux), Style = if best then "Primary" else "Dark", Size = UDim2.fromOffset(92, 40), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), TextSize = 15 })
		if best then
			local tag = UI.tag(row, "BEST VALUE", C.Danger, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 6), BackgroundTransparency = 0 })
			local label = tag:FindFirstChildOfClass("TextLabel")
			if label then
				label.TextColor3 = C.Text
			end
		end
		b.Activated:Connect(function()
			if pack.Id == 0 then
				Pages.Toast("Credit packs aren't set up on this place yet (Config.CreditProducts).", "Warn")
				return
			end
			MarketplaceService:PromptProductPurchase(player, pack.Id)
		end)
	end
end

--============================ MISSIONS ============================--
local function missions(frame: Frame)
	local d = ClientState.Data
	local now = os.time()
	local reset = (Util.DayNumber(now) + 1) * 86400 - now
	header(frame, "DAILY MISSIONS", ("new missions in %dh %02dm"):format(reset // 3600, (reset % 3600) // 60))
	local s = scroll(frame, UDim2.fromOffset(0, 72), UDim2.new(1, 0, 1, -72))
	UI.list(s, 10)
	if not d then
		return
	end
	for i, id in Missions.ForDay(Util.DayNumber(now)) do
		local m = Missions.ById[id]
		local prog = if d.Missions and d.Missions.Day == Util.DayNumber(now) then d.Missions.Progress[id] or 0 else 0
		local claimed = d.Missions and d.Missions.Claimed and d.Missions.Claimed[id]
		local row = card(s, { Size = UDim2.new(1, -8, 0, 84), LayoutOrder = i })
		make("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Size = UDim2.new(0, 4, 1, 0), ZIndex = 3 }, row)
		UI.text(row, m.Text, 20, C.Text, UI.Heading, { Position = UDim2.fromOffset(22, 12), Size = UDim2.new(1, -200, 0, 24) })
		UI.text(row, ("+%d CREDITS  ·  +%d XP"):format(m.Credits, m.XP), 11, C.Accent, UI.Caps, { Position = UDim2.fromOffset(22, 38), Size = UDim2.new(1, -200, 0, 14) })
		UI.track(row, C.Accent, prog / m.Goal, { Position = UDim2.fromOffset(22, 62), Size = UDim2.new(1, -280, 0, 6) })
		UI.text(row, ("%d / %d"):format(math.min(prog, m.Goal), m.Goal), 12, C.Text, UI.Mono, { Position = UDim2.new(1, -250, 0, 54), Size = UDim2.fromOffset(60, 20) })
		local done = prog >= m.Goal
		local b = UI.button(row, { Text = if claimed then "CLAIMED" elseif done then "CLAIM" else "IN PROGRESS", Style = if claimed then "Dark" elseif done then "Primary" else "Ghost", Size = UDim2.fromOffset(150, 44), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), TextSize = 16 })
		b.Activated:Connect(function()
			if done and not claimed then
				Net.Event("ClaimMission"):FireServer(id)
			end
		end)
	end
	local stats = d.Stats or {}
	local box = card(s, { Size = UDim2.new(1, -8, 0, 120), LayoutOrder = 10 })
	UI.pad(box, 22, 18)
	make("UIGridLayout", { CellSize = UDim2.new(0.166, -8, 0, 80), CellPadding = UDim2.fromOffset(8, 4) }, box)
	for _, pair in { { "BEST NIGHT", d.BestNight or 0 }, { "NIGHTS", stats.NightsSurvived or 0 }, { "RUNS", d.Runs or 0 }, { "REVIVES", stats.Revives or 0 }, { "BUILT", stats.StructuresBuilt or 0 }, { "RARE FINDS", stats.RareFound or 0 } } do
		local cell = make("Frame", { BackgroundTransparency = 1 }, box)
		UI.text(cell, pair[1], 10, C.Muted, UI.Caps, { Size = UDim2.new(1, 0, 0, 14) })
		UI.text(cell, Util.Commas(pair[2]), 40, C.Text, UI.Title, { Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 46) })
	end
end

--============================ SETTINGS ============================--
local function toggleRow(parent, key: string, label: string, sub: string, order: number)
	local d = ClientState.Data
	local on = d and d.Settings and d.Settings[key]
	local row = card(parent, { Size = UDim2.new(1, -8, 0, 64), LayoutOrder = order })
	UI.text(row, label, 18, C.Text, UI.Heading, { Position = UDim2.fromOffset(20, 10), Size = UDim2.new(1, -160, 0, 24) })
	UI.text(row, sub, 11, C.Muted, UI.Body, { Position = UDim2.fromOffset(20, 36), Size = UDim2.new(1, -160, 0, 16) })
	local b = UI.button(row, { Text = if on then "ON" else "OFF", Style = if on then "Primary" else "Dark", Size = UDim2.fromOffset(100, 38), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), TextSize = 16 })
	b.Activated:Connect(function()
		on = not on
		b.Text = if on then "ON" else "OFF"
		b.BackgroundColor3 = if on then C.Accent else C.Panel2
		b.TextColor3 = if on then C.Ink else C.Text
		Net.Event("Settings"):FireServer(key, on)
		Pages.OnSetting(key, on)
	end)
end

local function stepRow(parent, key: string, label: string, sub: string, order: number, step: number, min: number, max: number, fmt: string)
	local d = ClientState.Data
	local value = (d and d.Settings and d.Settings[key]) or (if key == "Sensitivity" then 1 else 0)
	local row = card(parent, { Size = UDim2.new(1, -8, 0, 64), LayoutOrder = order })
	UI.text(row, label, 18, C.Text, UI.Heading, { Position = UDim2.fromOffset(20, 10), Size = UDim2.new(1, -260, 0, 24) })
	UI.text(row, sub, 11, C.Muted, UI.Body, { Position = UDim2.fromOffset(20, 36), Size = UDim2.new(1, -260, 0, 16) })
	local valueLabel = UI.text(row, fmt:format(value), 16, C.Accent, UI.Mono, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -66, 0, 0), Size = UDim2.fromOffset(70, 64), TextXAlignment = Enum.TextXAlignment.Center })
	for i, delta in { -step, step } do
		local b = UI.button(row, { Text = "", Icon = if delta < 0 then "minus" else "plus", Name = if delta < 0 then "Minus" else "Plus", Size = UDim2.fromOffset(40, 38), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, if i == 1 then -140 else -16, 0.5, 0), TextSize = 20 })
		b.Activated:Connect(function()
			value = math.clamp(value + delta, min, max)
			valueLabel.Text = fmt:format(value)
			Net.Event("Settings"):FireServer(key, value)
			Pages.OnSetting(key, value)
		end)
	end
end

local function settings(frame: Frame)
	header(frame, "SETTINGS", "audio · graphics · controls")
	local s = scroll(frame, UDim2.fromOffset(0, 72), UDim2.new(1, 0, 1, -72))
	UI.list(s, 10)
	toggleRow(s, "Music", "Music & drones", "The low hum of the store, the night music", 1)
	toggleRow(s, "SFX", "Sound effects", "Footsteps, doors, the Locust — keep this ON", 2)
	toggleRow(s, "Effects", "Particles & effects", "Turn off on slow devices", 3)
	toggleRow(s, "CameraShake", "Camera shake & head bob", "Screen shake, first-person bobbing and sway", 4)
	stepRow(s, "Brightness", "Brightness", "The store is meant to be dark at night", 5, 0.5, -1, 2, "%+.1f")
	stepRow(s, "Sensitivity", "Mouse sensitivity", "First-person look speed", 6, 0.1, 0.2, 2, "%.1f×")
end

--============================ CREDITS ============================--
local function credits(frame: Frame)
	header(frame, "CREDITS")
	local s = scroll(frame, UDim2.fromOffset(0, 72), UDim2.new(1, 0, 1, -72))
	UI.list(s, 8)
	local lines = {
		{ "MASSIVE STORE: LOCUST", C.Accent, UI.Title, 30 },
		{ "An original survival horror game made for Roblox.", C.Text, UI.Semi, 14 },
		{ "DESIGN · CODE · MAP GENERATOR · AI · UI · SOUND · ANIMATION", C.Muted, UI.Caps, 11 },
		{ "Every model, icon, animation and sound is made in Luau. UI designed in Figma.", C.Text, UI.Body, 14 },
		{ "THANK YOU FOR SHOPPING AT MASSIVE STORE", C.Muted, UI.Caps, 11 },
		{ "We are not responsible for anything that happens after closing time.", C.Text, UI.Body, 14 },
	}
	for i, l in lines do
		UI.text(s, l[1], l[4], l[2], l[3], { Size = UDim2.new(1, 0, 0, l[4] + 12), LayoutOrder = i, TextWrapped = true })
	end
end

local RENDER = {
	LOCKER = locker,
	SHOP = shop,
	MISSIONS = missions,
	SETTINGS = settings,
	CREDITS = credits,
}

function Pages.Render(name: string, frame: Frame)
	current, currentName = frame, name
	frame:ClearAllChildren()
	local fn = RENDER[name]
	if fn then
		fn(frame)
	end
end

function Pages.Refresh()
	if current and currentName and current.Parent then
		Pages.Render(currentName, current)
	end
end

function Pages.Close()
	current, currentName = nil, nil
end

function Pages.Init()
	ClientState.DataChanged:Connect(function()
		if currentName == "LOCKER" or currentName == "SHOP" or currentName == "MISSIONS" then
			Pages.Refresh()
		end
	end)
end

return Pages
