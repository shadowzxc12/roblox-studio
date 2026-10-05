-- Kiddo Shop: obchod pre malé deti (veľké tlačidlá, jasné farby, hrubé obrysy).
-- Vlož ako LocalScript do StarterPlayer > StarterPlayerScripts.
-- Farby a rozmery sú rovnaké ako v dizajn systéme "Kiddo Shop".

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Tokens ---------------------------------------------------------------------

local C = {
	cream = Color3.fromHex("fff8ec"),
	card = Color3.fromHex("ffffff"),
	lilac = Color3.fromHex("e9e1ff"),
	ink = Color3.fromHex("2a1b4a"),
	inkMuted = Color3.fromHex("5e4f80"),
	grape = Color3.fromHex("6a3df0"),
	onGrape = Color3.fromHex("ffffff"),
	sky = Color3.fromHex("4cc3ff"),
	mint = Color3.fromHex("3ddc97"),
	sunshine = Color3.fromHex("ffd23f"),
	bubblegum = Color3.fromHex("ff7ab6"),
	tomato = Color3.fromHex("ff7a6b"),
}

local RARITY = {
	Common = Color3.fromHex("b8c2cc"),
	Rare = C.sky,
	Epic = Color3.fromHex("b98cff"),
	Legendary = C.sunshine,
}

local DISPLAY = Font.fromEnum(Enum.Font.FredokaOne)
local BODY = Font.fromName("Nunito", Enum.FontWeight.Bold)

local TAP_MIN = 56

-- Itemy v obchode: zmeň podľa svojej hry. `image` je rbxassetid obrázka.
local ITEMS = {
	Pets = {
		{ id = "rainbow_cat", name = "Rainbow Cat", price = 250, rarity = "Epic", image = "" },
		{ id = "tiny_dog", name = "Tiny Dog", price = 100, rarity = "Common", image = "" },
		{ id = "dragon", name = "Baby Dragon", price = 5000, rarity = "Legendary", image = "" },
	},
	Hats = {
		{ id = "party_hat", name = "Party Hat", price = 80, rarity = "Rare", image = "" },
		{ id = "wizard_hat", name = "Wizard Hat", price = 150, rarity = "Epic", image = "" },
	},
	Power = {
		{ id = "speed", name = "Super Speed", price = 300, rarity = "Rare", image = "" },
	},
}
local TAB_ORDER = { "Pets", "Hats", "Power" }

-- Stav hráča (v skutočnej hre ho drž na serveri a kupuj cez RemoteFunction!)
local coins = 1250
local gems = 40
local owned: { [string]: boolean } = {}

-- Helpers --------------------------------------------------------------------

local function corner(parent: Instance, px: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = if px then UDim.new(0, px) else UDim.new(1, 0)
	c.Parent = parent
end

local function stroke(parent: Instance, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = C.ink
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function label(parent: Instance, text: string, font: Font, size: number, color: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.FontFace = font
	t.TextSize = size
	t.TextColor3 = color
	t.Text = text
	t.Size = UDim2.fromScale(1, 1)
	t.Parent = parent
	return t
end

local function fmt(n: number): string
	local s = tostring(n)
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- Chunky button: ink shadow under it, sinks 4px when pressed.
local function chunkyButton(parent: Instance, text: string, fill: Color3, size: UDim2, radius: number?): TextButton
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = size + UDim2.fromOffset(0, 5)
	holder.Parent = parent

	local shadow = Instance.new("Frame")
	shadow.BackgroundColor3 = C.ink
	shadow.Size = size
	shadow.Position = UDim2.fromOffset(0, 5)
	shadow.Parent = holder
	corner(shadow, radius)

	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BackgroundColor3 = fill
	b.Size = size
	b.FontFace = DISPLAY
	b.TextSize = 22
	b.TextColor3 = if fill == C.grape then C.onGrape else C.ink
	b.Text = string.upper(text)
	b.ZIndex = 2
	b.Parent = holder
	corner(b, radius)
	stroke(b, 4)

	b.MouseButton1Down:Connect(function()
		b.Position = UDim2.fromOffset(0, 4)
	end)
	local function up()
		b.Position = UDim2.fromOffset(0, 0)
	end
	b.MouseButton1Up:Connect(up)
	b.MouseLeave:Connect(up)
	return b
end

local function setDisabled(b: TextButton, text: string)
	b.Active = false
	b.BackgroundColor3 = C.lilac
	b.TextColor3 = C.inkMuted
	b.Text = string.upper(text)
	local s = b:FindFirstChildOfClass("UIStroke")
	if s then
		s.Color = C.inkMuted
	end
end

local function pill(parent: Instance, fill: Color3, icon: string): TextLabel
	local p = Instance.new("Frame")
	p.BackgroundColor3 = fill
	p.Size = UDim2.fromOffset(130, 44)
	p.Parent = parent
	corner(p)
	stroke(p, 3)
	local t = label(p, icon, DISPLAY, 20, C.ink)
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Position = UDim2.fromOffset(14, 0)
	t.Size = UDim2.new(1, -14, 1, 0)
	return t
end

-- Shop window ----------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "KiddoShop"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- Open button (always on screen)
local openHolder = Instance.new("Frame")
openHolder.BackgroundTransparency = 1
openHolder.AnchorPoint = Vector2.new(0, 0.5)
openHolder.Position = UDim2.new(0, 16, 0.5, 0)
openHolder.Size = UDim2.fromOffset(120, 70)
openHolder.Parent = gui
local openBtn = chunkyButton(openHolder, "Shop", C.grape, UDim2.fromOffset(120, 64), 14)

local window = Instance.new("Frame")
window.Name = "Window"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.fromOffset(720, 520)
window.BackgroundColor3 = C.cream
window.Visible = false
window.Parent = gui
corner(window, 32)
stroke(window, 4)
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(720, 520)
sizeLimit.Parent = window
local scale = Instance.new("UIScale")
scale.Parent = window

-- Header
local head = Instance.new("Frame")
head.BackgroundColor3 = C.grape
head.Size = UDim2.new(1, 0, 0, 76)
head.Parent = window
corner(head, 32)
local headFill = Instance.new("Frame") -- squares off the header's bottom corners
headFill.BackgroundColor3 = C.grape
headFill.BorderSizePixel = 0
headFill.Position = UDim2.new(0, 0, 1, -32)
headFill.Size = UDim2.new(1, 0, 0, 32)
headFill.Parent = head
local headLine = Instance.new("Frame")
headLine.BackgroundColor3 = C.ink
headLine.BorderSizePixel = 0
headLine.Position = UDim2.new(0, 0, 1, 0)
headLine.Size = UDim2.new(1, 0, 0, 4)
headLine.Parent = head

local title = label(head, "SHOP", DISPLAY, 40, C.onGrape)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Position = UDim2.fromOffset(24, 0)
title.Size = UDim2.new(0, 200, 1, 0)
title.ZIndex = 2

local wallet = Instance.new("Frame")
wallet.BackgroundTransparency = 1
wallet.AnchorPoint = Vector2.new(1, 0.5)
wallet.Position = UDim2.new(1, -16, 0.5, 0)
wallet.Size = UDim2.fromOffset(400, 61)
wallet.ZIndex = 2
wallet.Parent = head
local wl = Instance.new("UIListLayout")
wl.FillDirection = Enum.FillDirection.Horizontal
wl.HorizontalAlignment = Enum.HorizontalAlignment.Right
wl.VerticalAlignment = Enum.VerticalAlignment.Center
wl.Padding = UDim.new(0, 10)
wl.Parent = wallet

local coinText = pill(wallet, C.sunshine, "")
local gemText = pill(wallet, C.bubblegum, "")
local closeBtn = chunkyButton(wallet, "X", C.tomato, UDim2.fromOffset(TAP_MIN, TAP_MIN))

local function refreshWallet()
	coinText.Text = "🪙 " .. fmt(coins)
	gemText.Text = "💎 " .. fmt(gems)
end

-- Body
local body = Instance.new("Frame")
body.BackgroundTransparency = 1
body.Position = UDim2.fromOffset(16, 96)
body.Size = UDim2.new(1, -32, 1, -112)
body.Parent = window

local tabs = Instance.new("Frame")
tabs.BackgroundColor3 = C.lilac
tabs.Size = UDim2.fromOffset(#TAB_ORDER * 130 + (#TAB_ORDER - 1) * 8 + 12, 68)
tabs.Parent = body
corner(tabs)
stroke(tabs, 3)
local tl = Instance.new("UIListLayout")
tl.FillDirection = Enum.FillDirection.Horizontal
tl.VerticalAlignment = Enum.VerticalAlignment.Center
tl.Padding = UDim.new(0, 8)
tl.Parent = tabs
local tp = Instance.new("UIPadding")
tp.PaddingLeft = UDim.new(0, 6)
tp.Parent = tabs

local grid = Instance.new("ScrollingFrame")
grid.BackgroundTransparency = 1
grid.BorderSizePixel = 0
grid.Position = UDim2.fromOffset(0, 84)
grid.Size = UDim2.new(1, 0, 1, -84)
grid.ScrollBarThickness = 10
grid.ScrollBarImageColor3 = C.grape
grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
grid.CanvasSize = UDim2.new()
grid.Parent = body
local gl = Instance.new("UIGridLayout")
gl.CellSize = UDim2.fromOffset(200, 270)
gl.CellPadding = UDim2.fromOffset(16, 16)
gl.Parent = grid
local gp = Instance.new("UIPadding")
gp.PaddingTop = UDim.new(0, 14)
gp.PaddingLeft = UDim.new(0, 10)
gp.Parent = grid

-- Item card
local renderTab: (string) -> ()
local currentTab = TAB_ORDER[1]

local function itemCard(item)
	local cell = Instance.new("Frame")
	cell.BackgroundTransparency = 1
	cell.Parent = grid

	local shadow = Instance.new("Frame")
	shadow.BackgroundColor3 = C.ink
	shadow.Position = UDim2.fromOffset(0, 5)
	shadow.Size = UDim2.new(1, 0, 1, -5)
	shadow.Parent = cell
	corner(shadow, 22)

	local card = Instance.new("Frame")
	card.BackgroundColor3 = C.card
	card.Size = UDim2.new(1, 0, 1, -5)
	card.ZIndex = 2
	card.Parent = cell
	corner(card, 22)
	stroke(card, 3)

	local well = Instance.new("ImageLabel")
	well.BackgroundColor3 = C.lilac
	well.Position = UDim2.fromOffset(12, 12)
	well.Size = UDim2.new(1, -24, 0, 110)
	well.Image = item.image
	well.ScaleType = Enum.ScaleType.Fit
	well.ImageTransparency = if owned[item.id] then 0.4 else 0
	well.ZIndex = 3
	well.Parent = card
	corner(well, 14)

	local badge = Instance.new("TextLabel")
	badge.BackgroundColor3 = RARITY[item.rarity] or RARITY.Common
	badge.Position = UDim2.fromOffset(-8, -12)
	badge.Size = UDim2.fromOffset(96, 24)
	badge.Rotation = -6
	badge.FontFace = DISPLAY
	badge.TextSize = 14
	badge.TextColor3 = C.ink
	badge.Text = string.upper(item.rarity)
	badge.ZIndex = 5
	badge.Parent = card
	corner(badge, 8)
	stroke(badge, 3)

	local name = label(card, item.name, DISPLAY, 20, C.ink)
	name.Position = UDim2.fromOffset(12, 128)
	name.Size = UDim2.new(1, -24, 0, 48)
	name.TextWrapped = true
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.ZIndex = 3

	local price = label(card, "🪙 " .. fmt(item.price), DISPLAY, 20, C.ink)
	price.Position = UDim2.fromOffset(12, 180)
	price.Size = UDim2.new(1, -24, 0, 24)
	price.TextXAlignment = Enum.TextXAlignment.Left
	price.ZIndex = 3

	local btnRow = Instance.new("Frame")
	btnRow.BackgroundTransparency = 1
	btnRow.Position = UDim2.fromOffset(12, 208)
	btnRow.Size = UDim2.new(1, -24, 0, 53)
	btnRow.ZIndex = 3
	btnRow.Parent = card

	local isOwned = owned[item.id]
	local btn = chunkyButton(btnRow, if isOwned then "Equip" else "Buy", if isOwned then C.sky else C.mint, UDim2.new(1, 0, 0, 48))
	btn.ZIndex = 4

	if not isOwned and coins < item.price then
		setDisabled(btn, "Buy")
		local hint = label(card, "You need " .. fmt(item.price - coins) .. " more coins", BODY, 14, C.inkMuted)
		hint.Position = UDim2.fromOffset(82, 176)
		hint.Size = UDim2.new(1, -94, 0, 32)
		hint.TextXAlignment = Enum.TextXAlignment.Right
		hint.TextWrapped = true
		hint.ZIndex = 3
		price.Size = UDim2.new(0, 70, 0, 24)
		return
	end

	btn.Activated:Connect(function()
		if owned[item.id] then
			print("Equip", item.id) -- tu napoj svoje equip
			return
		end
		if coins >= item.price then
			coins -= item.price
			owned[item.id] = true
			refreshWallet()
			renderTab(currentTab)
		end
	end)
end

-- Tabs
local tabButtons: { [string]: TextButton } = {}
for _, tabName in TAB_ORDER do
	local t = Instance.new("TextButton")
	t.AutoButtonColor = false
	t.Size = UDim2.fromOffset(130, TAP_MIN)
	t.FontFace = DISPLAY
	t.TextSize = 22
	t.Text = tabName
	t.Parent = tabs
	corner(t)
	tabButtons[tabName] = t
	t.Activated:Connect(function()
		renderTab(tabName)
	end)
end

renderTab = function(tabName: string)
	currentTab = tabName
	for n, b in tabButtons do
		local on = n == tabName
		b.BackgroundColor3 = C.grape
		b.BackgroundTransparency = if on then 0 else 1
		b.TextColor3 = if on then C.onGrape else C.ink
	end
	for _, child in grid:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for _, item in ITEMS[tabName] do
		itemCard(item)
	end
end

-- Open / close with a pop ----------------------------------------------------

local POP = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function open()
	refreshWallet()
	renderTab(currentTab)
	scale.Scale = 0.8
	window.Visible = true
	TweenService:Create(scale, POP, { Scale = 1 }):Play()
end

local function close()
	window.Visible = false
end

openBtn.Activated:Connect(function()
	if window.Visible then
		close()
	else
		open()
	end
end)
closeBtn.Activated:Connect(close)

refreshWallet()
