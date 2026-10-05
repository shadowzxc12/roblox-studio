-- Kiddo Shop v2: bočné menu + STORE okno s animáciami, VFX a SFX.
-- Vlož ako LocalScript do StarterPlayer > StarterPlayerScripts.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local MarketplaceService = game:GetService("MarketplaceService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- CONFIG ---------------------------------------------------------------------

-- ID z Creator Dashboard (Monetization). id = 0 -> len ukážka (efekt bez platby).
-- pass = true -> Game Pass, inak Developer Product.
local PRODUCTS = {
	blue1 = { id = 0 }, blue3 = { id = 0 },
	orange1 = { id = 0 }, orange3 = { id = 0 },
	purple1 = { id = 0 }, purple3 = { id = 0 },
	starter = { id = 0 },
	luck15 = { id = 0 }, luck60 = { id = 0 },
	vip = { id = 0, pass = true },
	cash2x = { id = 0, pass = true },
	auto = { id = 0, pass = true },
}

-- Zvuky: vstavané zvuky Robloxu. Vymeň za "rbxassetid://..." z Creator Store.
local SFX = {
	hover = { id = "rbxasset://sounds/switch.wav", volume = 0.2, speed = 1.6 },
	click = { id = "rbxasset://sounds/button.wav", volume = 0.6, speed = 1 },
	open = { id = "rbxasset://sounds/swoosh.wav", volume = 0.5, speed = 1.2 },
	close = { id = "rbxasset://sounds/swoosh.wav", volume = 0.4, speed = 0.8 },
	pop = { id = "rbxasset://sounds/snap.wav", volume = 0.3, speed = 1.4 },
	buy = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.8, speed = 1 },
}

-- Theme ----------------------------------------------------------------------

local INK = Color3.fromHex("1b1530")
local WHITE = Color3.new(1, 1, 1)
local C = {
	body = Color3.fromHex("23263a"),
	orange = Color3.fromHex("ffbb22"),
	orangeStripe = Color3.fromHex("ff9d00"),
	red = Color3.fromHex("ff4040"),
	redDark = Color3.fromHex("c41e1e"),
	green = Color3.fromHex("6aea4f"),
	greenDark = Color3.fromHex("1fa324"),
	blue = Color3.fromHex("3a96ff"),
	blueDark = Color3.fromHex("1b5fd1"),
	tierOrange = Color3.fromHex("ffa324"),
	tierOrangeDark = Color3.fromHex("d96a00"),
	purple = Color3.fromHex("c063ff"),
	purpleDark = Color3.fromHex("7d2fd6"),
	starterA = Color3.fromHex("5b6cff"),
	starterB = Color3.fromHex("c04dff"),
	teal = Color3.fromHex("2fd39a"),
	tealDark = Color3.fromHex("128a6a"),
	gold = Color3.fromHex("ffd23f"),
	pink = Color3.fromHex("ff7ab6"),
	sideTop = Color3.fromHex("ffffff"),
	sideBottom = Color3.fromHex("d6e0ff"),
}
local CONFETTI = { C.gold, C.pink, C.blue, C.green, C.purple, C.orange, WHITE }

local DISPLAY = Font.fromEnum(Enum.Font.FredokaOne)

-- Helpers --------------------------------------------------------------------

local function make(className: string, props: { [string]: any }?, parent: Instance?): any
	local inst: any = Instance.new(className)
	if props then
		for k, v in props do
			inst[k] = v
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(parent: Instance, px: number?)
	make("UICorner", { CornerRadius = if px then UDim.new(0, px) else UDim.new(1, 0) }, parent)
end

local function stroke(parent: Instance, thickness: number, color: Color3?): UIStroke
	return make("UIStroke", {
		Color = color or INK,
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function vgrad(parent: Instance, top: Color3, bottom: Color3)
	make("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = 90 }, parent)
end

-- Cartoon text: white(ish) letters with a thick dark outline.
local function text(parent: Instance, str: string, size: number, color: Color3?): TextLabel
	local t = make("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = DISPLAY,
		TextSize = size,
		TextColor3 = color or WHITE,
		Text = str,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	}, parent)
	make("UIStroke", { Color = INK, Thickness = math.max(1.5, size / 11) }, t)
	return t
end

local function emoji(parent: Instance, e: string, size: number): TextLabel
	return make("TextLabel", {
		BackgroundTransparency = 1,
		Text = e,
		TextSize = size,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size + 10, size + 10),
		ZIndex = 3,
	}, parent)
end

local function holder(parent: Instance, size: UDim2, order: number?): Frame
	return make("Frame", { BackgroundTransparency = 1, Size = size, LayoutOrder = order or 0 }, parent)
end

local CENTER = { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1) }
local function centered(props: { [string]: any }): { [string]: any }
	for k, v in CENTER do
		if props[k] == nil then
			props[k] = v
		end
	end
	return props
end

-- SFX ------------------------------------------------------------------------

local sounds: { [string]: Sound } = {}
for name, cfg in SFX do
	sounds[name] = make("Sound", {
		Name = "KiddoShop_" .. name,
		SoundId = cfg.id,
		Volume = cfg.volume,
		PlaybackSpeed = cfg.speed,
	}, SoundService)
end

local function sfx(name: string)
	local s = sounds[name]
	if s then
		s.PlaybackSpeed = SFX[name].speed * (0.92 + math.random() * 0.16) -- trochu iný tón zakaždým
		SoundService:PlayLocalSound(s)
	end
end

-- Animation registry (one RenderStepped loop drives all idle motion) ---------

local bobbers, spinners, wobblers, pulsers, glowers = {}, {}, {}, {}, {}

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for _, b in bobbers do
		b.obj.Position = b.base + UDim2.fromOffset(0, math.sin(t * b.speed + b.phase) * b.amp)
	end
	for _, s in spinners do
		s.obj.Rotation = s.base + t * s.speed
	end
	for _, w in wobblers do
		w.obj.Rotation = math.sin(t * w.speed + w.phase) * w.amp
	end
	for _, p in pulsers do
		p.obj.Scale = 1 + math.abs(math.sin(t * p.speed + p.phase)) * p.amp
	end
	for _, g in glowers do
		g.obj.Transparency = 0.35 + math.sin(t * 3) * 0.35
	end
end)

local function bob(obj: GuiObject, amp: number?, speed: number?)
	table.insert(bobbers, { obj = obj, base = obj.Position, amp = amp or 5, speed = speed or 2, phase = math.random() * 6 })
end
local function wobble(obj: GuiObject, amp: number?, speed: number?)
	table.insert(wobblers, { obj = obj, amp = amp or 8, speed = speed or 3, phase = math.random() * 6 })
end

-- Shine: a light streak sweeping over a button every few seconds.
local function shine(parent: GuiObject, radius: number?)
	local s = make("Frame", { BackgroundColor3 = WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 2, Name = "Shine" }, parent)
	if radius then
		corner(s, radius)
	end
	local g = make("UIGradient", {
		Rotation = 20,
		Offset = Vector2.new(-1, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, s)
	task.spawn(function()
		while s.Parent do
			task.wait(1.5 + math.random() * 3)
			g.Offset = Vector2.new(-1, 0)
			local tw = TweenService:Create(g, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Offset = Vector2.new(1, 0) })
			tw:Play()
			tw.Completed:Wait()
		end
	end)
end

-- Juicy button: grows on hover, squishes on press, plays sounds.
local function juicy(btn: GuiButton, hoverScale: number?): UIScale
	local sc = make("UIScale", nil, btn)
	local target = hoverScale or 1.07
	local function to(v: number, time: number?)
		TweenService:Create(sc, TweenInfo.new(time or 0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = v }):Play()
	end
	btn.MouseEnter:Connect(function()
		to(target)
		sfx("hover")
	end)
	btn.MouseLeave:Connect(function()
		to(1)
	end)
	btn.MouseButton1Down:Connect(function()
		to(0.88, 0.08)
	end)
	btn.MouseButton1Up:Connect(function()
		to(target)
	end)
	btn.Activated:Connect(function()
		sfx("click")
	end)
	return sc
end

-- GUI root -------------------------------------------------------------------

local gui = make("ScreenGui", {
	Name = "KiddoShop",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local fx = make("Frame", { Name = "FX", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50 }, gui)

-- VFX: purchase celebration --------------------------------------------------

local function celebrate(from: GuiObject, msg: string?)
	sfx("buy")
	local origin = from.AbsolutePosition + from.AbsoluteSize / 2

	-- white flash
	local flash = make("Frame", { BackgroundColor3 = WHITE, BackgroundTransparency = 0.6, Size = UDim2.fromScale(1, 1) }, fx)
	TweenService:Create(flash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
	task.delay(0.4, function()
		flash:Destroy()
	end)

	-- shock ring
	local ring = make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(origin.X, origin.Y),
		Size = UDim2.fromOffset(20, 20),
	}, fx)
	corner(ring)
	local rs = stroke(ring, 8, C.gold)
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Size = UDim2.fromOffset(200, 200) }):Play()
	local rt = TweenService:Create(rs, TweenInfo.new(0.45), { Transparency = 1, Thickness = 0 })
	rt:Play()
	rt.Completed:Connect(function()
		ring:Destroy()
	end)

	-- confetti: shoots out, then falls with gravity
	for _ = 1, 32 do
		local sz = math.random(8, 14)
		local bit = make("Frame", {
			BackgroundColor3 = CONFETTI[math.random(#CONFETTI)],
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(origin.X, origin.Y),
			Size = UDim2.fromOffset(sz, if math.random() < 0.5 then sz else sz / 2),
			Rotation = math.random(0, 360),
		}, fx)
		if math.random() < 0.4 then
			corner(bit)
		end
		local a = math.random() * math.pi * 2
		local d = math.random(70, 180)
		local mid = origin + Vector2.new(math.cos(a) * d, math.sin(a) * d - 50)
		local out = TweenService:Create(bit, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(mid.X, mid.Y),
			Rotation = bit.Rotation + math.random(-180, 180),
		})
		out:Play()
		out.Completed:Connect(function()
			local fall = TweenService:Create(bit, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(mid.X + math.random(-40, 40), mid.Y + math.random(140, 240)),
				BackgroundTransparency = 1,
				Rotation = bit.Rotation + math.random(-270, 270),
			})
			fall:Play()
			fall.Completed:Connect(function()
				bit:Destroy()
			end)
		end)
	end

	-- floating text
	local pop = text(fx, msg or "PURCHASED!", 34, C.gold)
	pop.AnchorPoint = Vector2.new(0.5, 0.5)
	pop.Size = UDim2.fromOffset(360, 44)
	pop.Position = UDim2.fromOffset(origin.X, origin.Y - 20)
	local ps = make("UIScale", { Scale = 0.3 }, pop)
	TweenService:Create(ps, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(pop, TweenInfo.new(1.2, Enum.EasingStyle.Quad), {
		Position = UDim2.fromOffset(origin.X, origin.Y - 110),
		TextTransparency = 1,
	}):Play()
	TweenService:Create(pop:FindFirstChildOfClass("UIStroke") :: UIStroke, TweenInfo.new(1.2), { Transparency = 1 }):Play()
	task.delay(1.3, function()
		pop:Destroy()
	end)
end

-- Purchases ------------------------------------------------------------------

local pendingButton: GuiObject? = nil

local function buy(key: string, from: GuiObject)
	local p = PRODUCTS[key]
	pendingButton = from
	if p and p.id > 0 then
		if p.pass then
			MarketplaceService:PromptGamePassPurchase(player, p.id)
		else
			MarketplaceService:PromptProductPurchase(player, p.id)
		end
	else
		celebrate(from, "DEMO: " .. string.upper(key))
	end
end

MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, _, purchased)
	if userId == player.UserId and purchased and pendingButton then
		celebrate(pendingButton)
	end
end)
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, _, purchased)
	if plr == player and purchased and pendingButton then
		celebrate(pendingButton)
	end
end)

-- Green R$ button
local function priceButton(parent: Instance, label: string, size: UDim2, order: number?, onClick: (GuiObject) -> ()): Frame
	local h = holder(parent, size, order)
	local b = make("TextButton", centered({ AutoButtonColor = false, Text = "", BackgroundColor3 = WHITE }), h)
	vgrad(b, C.green, C.greenDark)
	corner(b, 8)
	stroke(b, 2.5)
	shine(b, 8)
	text(b, label, math.floor(size.Y.Offset * 0.55))
	juicy(b)
	b.Activated:Connect(function()
		onClick(b)
	end)
	return h
end

-- STORE window ---------------------------------------------------------------

local popIns: { UIScale } = {}
local function popIn(obj: GuiObject)
	table.insert(popIns, make("UIScale", nil, obj))
end

local dim = make("TextButton", {
	Text = "",
	AutoButtonColor = false,
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	ZIndex = 10,
}, gui)

local window = make("Frame", {
	Name = "Store",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(600, 450),
	BackgroundColor3 = C.body,
	Visible = false,
	Active = true, -- klik do okna nezavrie obchod
	ZIndex = 11,
}, gui)
corner(window, 14)
stroke(window, 4)
local wscale = make("UIScale", nil, window)

-- Header: orange stripes, basket icon, STORE title, red X
local header = make("Frame", {
	BackgroundColor3 = WHITE,
	Position = UDim2.fromOffset(-8, -16),
	Size = UDim2.new(1, 16, 0, 64),
	ZIndex = 2,
}, window)
do
	local kps = {}
	local count = 10 -- 10 stripes = 20 keypoints (Roblox max)
	for i = 0, count - 1 do
		local col = if i % 2 == 0 then C.orange else C.orangeStripe
		table.insert(kps, ColorSequenceKeypoint.new(i / count, col))
		table.insert(kps, ColorSequenceKeypoint.new(if i == count - 1 then 1 else (i + 1) / count - 0.001, col))
	end
	make("UIGradient", { Color = ColorSequence.new(kps), Rotation = 30 }, header)
end
corner(header, 10)
stroke(header, 4)
shine(header, 10)

local headIcon = emoji(header, "🛒", 52)
headIcon.Position = UDim2.fromOffset(40, 22)
wobble(headIcon, 10, 3)

local title = text(header, "STORE", 40)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Position = UDim2.fromOffset(84, 0)
title.Size = UDim2.new(0, 300, 1, 0)

local closeHolder = holder(header, UDim2.fromOffset(50, 50))
closeHolder.AnchorPoint = Vector2.new(1, 0.5)
closeHolder.Position = UDim2.new(1, -10, 0.5, 0)
closeHolder.ZIndex = 4
local closeBtn = make("TextButton", centered({ AutoButtonColor = false, Text = "", BackgroundColor3 = WHITE, ZIndex = 4 }), closeHolder)
vgrad(closeBtn, C.red, C.redDark)
corner(closeBtn, 8)
stroke(closeBtn, 3)
text(closeBtn, "X", 32)
juicy(closeBtn, 1.12)

-- Scrolling content
local content = make("ScrollingFrame", {
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 54),
	Size = UDim2.new(1, 0, 1, -60),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 8,
	ScrollBarImageColor3 = C.orange,
	ZIndex = 1,
}, window)
make("UIListLayout", {
	Padding = UDim.new(0, 14),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, content)
make("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 18) }, content)

local function hlist(parent: Instance, padding: number, align: Enum.HorizontalAlignment?)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, padding),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, parent)
end

-- 1) Three item packs (blue / orange / purple)
local packRow = holder(content, UDim2.fromOffset(552, 160), 1)
hlist(packRow, 12)

local function packCard(order: number, name: string, top: Color3, bottom: Color3, icon: string, key: string)
	local h = holder(packRow, UDim2.fromOffset(176, 160), order)
	local card = make("Frame", centered({ BackgroundColor3 = WHITE }), h)
	vgrad(card, top, bottom)
	corner(card, 12)
	stroke(card, 3)
	popIn(card)

	local t = text(card, name, 18)
	t.Size = UDim2.new(1, 0, 0, 26)
	t.Position = UDim2.fromOffset(0, 6)

	local slots = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 46) }, card)
	hlist(slots, 6)
	for i = 1, 3 do
		local s = make("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.6, Size = UDim2.fromOffset(44, 44), LayoutOrder = i }, slots)
		corner(s, 8)
		stroke(s, 2, WHITE).Transparency = 0.5
		local e = emoji(s, if i == 2 then icon else "❔", 26)
		if i == 2 then
			bob(e, 3, 3)
		end
	end

	local cols = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, 0, 0, 70) }, card)
	hlist(cols, 8)
	for i, info in { { "1x Item", "R$99", key .. "1" }, { "3x Item", "R$269", key .. "3" } } do
		local col = holder(cols, UDim2.fromOffset(78, 64), i)
		local l = text(col, info[1], 13)
		l.Size = UDim2.new(1, 0, 0, 20)
		local pb = priceButton(col, info[2], UDim2.fromOffset(78, 36), nil, function(b)
			buy(info[3], b)
		end)
		pb.Position = UDim2.fromOffset(0, 24)
	end
end
packCard(1, "Blue Pack", C.blue, C.blueDark, "🐶", "blue")
packCard(2, "Orange Pack", C.tierOrange, C.tierOrangeDark, "🦊", "orange")
packCard(3, "Purple Pack", C.purple, C.purpleDark, "🦄", "purple")

-- 2) Starter Pack banner
local starterHolder = holder(content, UDim2.fromOffset(552, 140), 2)
local starter = make("Frame", centered({ BackgroundColor3 = WHITE }), starterHolder)
make("UIGradient", { Color = ColorSequence.new(C.starterA, C.starterB) }, starter)
corner(starter, 14)
table.insert(glowers, { obj = stroke(starter, 4, WHITE) })
shine(starter, 14)
popIn(starter)

local stTitle = text(starter, "Starter Pack!", 28)
stTitle.TextXAlignment = Enum.TextXAlignment.Left
stTitle.Position = UDim2.fromOffset(16, 8)
stTitle.Size = UDim2.new(0, 300, 0, 34)

local stItems = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 44), Size = UDim2.fromOffset(360, 88), ZIndex = 3 }, starter)
hlist(stItems, 4, Enum.HorizontalAlignment.Left)
local function stItem(order: number, icon: string, caption: string, color: Color3, tag: string?)
	local h = holder(stItems, UDim2.fromOffset(86, 88), order)
	local e = emoji(h, icon, 48)
	e.Position = UDim2.new(0.5, 0, 0, 34)
	bob(e, 4, 2.5)
	local c = text(h, caption, 20, color)
	c.Size = UDim2.new(1, 0, 0, 24)
	c.Position = UDim2.new(0, 0, 1, -24)
	if tag then
		local tg = text(h, tag, 18, C.gold)
		tg.Size = UDim2.fromOffset(50, 22)
		tg.Position = UDim2.fromOffset(44, -4)
		tg.ZIndex = 4
		wobble(tg, 12, 5)
	end
end
local function plus(order: number)
	local p = text(holder(stItems, UDim2.fromOffset(24, 88), order), "+", 30)
	p.Position = UDim2.fromOffset(0, -8)
end
stItem(1, "💰", "+100k", C.green)
plus(2)
stItem(3, "👑", "VIP", C.gold)
plus(4)
stItem(5, "🎁", "Item", WHITE, "OP!")

local stBuy = priceButton(starter, "R$99", UDim2.fromOffset(130, 56), nil, function(b)
	buy("starter", b)
end)
stBuy.AnchorPoint = Vector2.new(1, 0.5)
stBuy.Position = UDim2.new(1, -18, 0.5, 14)
stBuy.ZIndex = 4

-- 3) Divider: ☆ Server Luck ☆
local function divider(order: number, label: string)
	local h = holder(content, UDim2.fromOffset(552, 30), order)
	for _, x in { 0, 1 } do
		make("Frame", {
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(x, 0.5),
			Position = UDim2.fromScale(x, 0.5),
			Size = UDim2.new(0.3, 0, 0, 3),
		}, h)
	end
	text(h, "☆  " .. label .. "  ☆", 20)
end
divider(3, "Server Luck")

-- 4) Server luck card
local luckHolder = holder(content, UDim2.fromOffset(552, 96), 4)
local luck = make("Frame", centered({ BackgroundColor3 = WHITE }), luckHolder)
vgrad(luck, C.teal, C.tealDark)
corner(luck, 12)
stroke(luck, 3)
popIn(luck)
local clover = emoji(luck, "🍀", 50)
clover.Position = UDim2.fromOffset(46, 48)
wobble(clover, 12, 2.5)
local lt = text(luck, "x2 LUCK", 28)
lt.TextXAlignment = Enum.TextXAlignment.Left
lt.Position = UDim2.fromOffset(86, 14)
lt.Size = UDim2.fromOffset(200, 34)
local ls = text(luck, "For the whole server!", 15)
ls.TextXAlignment = Enum.TextXAlignment.Left
ls.Position = UDim2.fromOffset(86, 50)
ls.Size = UDim2.fromOffset(200, 22)
local luckCols = make("Frame", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -14, 0.5, 0),
	Size = UDim2.fromOffset(200, 70),
}, luck)
hlist(luckCols, 10, Enum.HorizontalAlignment.Right)
for i, info in { { "15 min", "R$49", "luck15" }, { "1 hour", "R$149", "luck60" } } do
	local col = holder(luckCols, UDim2.fromOffset(88, 64), i)
	local l = text(col, info[1], 14)
	l.Size = UDim2.new(1, 0, 0, 20)
	local pb = priceButton(col, info[2], UDim2.fromOffset(88, 38), nil, function(b)
		buy(info[3], b)
	end)
	pb.Position = UDim2.fromOffset(0, 24)
end

-- 5) Game passes
divider(5, "Game Passes")
local passRow = holder(content, UDim2.fromOffset(552, 136), 6)
hlist(passRow, 12)
for i, info in {
	{ "VIP", "👑", "R$199", "vip", C.gold, C.tierOrangeDark },
	{ "2x Cash", "💵", "R$149", "cash2x", C.green, C.greenDark },
	{ "Auto Collect", "🧲", "R$99", "auto", C.pink, C.purpleDark },
} do
	local h = holder(passRow, UDim2.fromOffset(176, 136), i)
	local card = make("Frame", centered({ BackgroundColor3 = WHITE }), h)
	vgrad(card, info[5], info[6])
	corner(card, 12)
	stroke(card, 3)
	popIn(card)
	local e = emoji(card, info[2], 40)
	e.Position = UDim2.new(0.5, 0, 0, 32)
	bob(e, 4, 2 + i * 0.3)
	local n = text(card, info[1], 18)
	n.Size = UDim2.new(1, 0, 0, 24)
	n.Position = UDim2.fromOffset(0, 58)
	local pb = priceButton(card, info[3], UDim2.fromOffset(120, 38), nil, function(b)
		buy(info[4], b)
	end)
	pb.AnchorPoint = Vector2.new(0.5, 1)
	pb.Position = UDim2.new(0.5, 0, 1, -10)
end

-- Open / close -----------------------------------------------------------------

local isOpen = false
local storeBadge: GuiObject? = nil

local function fitScale(): number
	local vp = (Workspace.CurrentCamera :: Camera).ViewportSize
	return math.clamp(math.min((vp.Y - 60) / 470, (vp.X - 220) / 620), 0.5, 1)
end

local OFF = UDim2.new(0, -340, 0.5, 0) -- vyletí zboku (od bočného menu)

local function openStore(highlightStarter: boolean?)
	if isOpen then
		return
	end
	isOpen = true
	sfx("open")
	if storeBadge then
		storeBadge.Visible = false
	end

	dim.Visible = true
	TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 0.45 }):Play()

	local s = fitScale()
	window.Visible = true
	window.Position = OFF
	window.Rotation = -8
	wscale.Scale = s * 0.6
	local slide = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(window, slide, { Position = UDim2.fromScale(0.5, 0.5), Rotation = 0 }):Play()
	TweenService:Create(wscale, slide, { Scale = s }):Play()

	content.CanvasPosition = Vector2.zero
	for i, sc in popIns do
		sc.Scale = 0
		task.delay(0.18 + i * 0.05, function()
			if isOpen then
				TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
				sfx("pop")
			end
		end)
	end

	if highlightStarter then
		task.delay(0.9, function()
			local sc = popIns[4] -- starter banner
			TweenService:Create(sc, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1, true), { Scale = 1.07 }):Play()
		end)
	end
end

local function closeStore()
	if not isOpen then
		return
	end
	isOpen = false
	sfx("close")
	TweenService:Create(dim, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
	local back = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	local tw = TweenService:Create(window, back, { Position = OFF, Rotation = -8 })
	TweenService:Create(wscale, back, { Scale = fitScale() * 0.6 }):Play()
	tw:Play()
	tw.Completed:Connect(function()
		if not isOpen then
			window.Visible = false
			dim.Visible = false
		end
	end)
end

closeBtn.Activated:Connect(closeStore)
dim.Activated:Connect(closeStore)
;(Workspace.CurrentCamera :: Camera):GetPropertyChangedSignal("ViewportSize"):Connect(function()
	if isOpen then
		wscale.Scale = fitScale()
	end
end)

-- Side menu (left) -------------------------------------------------------------

local side = make("Frame", {
	Name = "SideMenu",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 14, 0.5, 0),
	Size = UDim2.fromOffset(2 * 78 + 10, 3 * 80 + 20),
}, gui)
make("UIGridLayout", {
	CellSize = UDim2.fromOffset(78, 80),
	CellPadding = UDim2.fromOffset(10, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, side)

local SIDE = {
	{ name = "Store", icon = "🛒", badge = true, action = function() openStore() end },
	{ name = "Index", icon = "📘" },
	{ name = "Gift", icon = "🎁", badge = true },
	{ name = "Rebirth", icon = "🔄" },
	{ name = "Invite", icon = "👥" },
	{ name = "Settings", icon = "⚙️" },
}

for i, item in SIDE do
	local h = holder(side, UDim2.fromScale(1, 1), i)
	local b = make("TextButton", {
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -6),
		Size = UDim2.fromOffset(66, 66),
	}, h)
	vgrad(b, C.sideTop, C.sideBottom)
	corner(b, 12)
	stroke(b, 3)
	local ic = emoji(b, item.icon, 38)
	ic.Position = UDim2.fromScale(0.5, 0.42)
	local l = text(b, item.name, 15)
	l.Size = UDim2.new(1, 20, 0, 20)
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 1, -8)
	l.ZIndex = 4

	if item.badge then
		local bd = make("Frame", {
			BackgroundColor3 = C.red,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -4, 0, 4),
			Size = UDim2.fromOffset(24, 24),
			ZIndex = 5,
		}, b)
		corner(bd)
		stroke(bd, 2.5)
		text(bd, "!", 18).ZIndex = 6
		table.insert(pulsers, { obj = make("UIScale", nil, bd), amp = 0.2, speed = 4, phase = i })
		if item.name == "Store" then
			storeBadge = bd
		end
	end

	local sc = juicy(b, 1.1)
	b.MouseEnter:Connect(function()
		TweenService:Create(ic, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = -14 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(ic, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
	end)
	b.Activated:Connect(function()
		if item.action then
			item.action()
		else
			print("KiddoShop: " .. item.name .. " (napoj vlastnú akciu)")
		end
	end)

	-- entrance: buttons pop in one after another
	sc.Scale = 0
	task.delay(0.3 + i * 0.07, function()
		TweenService:Create(sc, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
end

-- Floating offers (right) with spinning light rays ------------------------------

local function floatingOffer(y: number, icon: string, title: string, price: string)
	local h = make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -30, y, 0),
		Size = UDim2.fromOffset(120, 120),
	}, gui)
	for i = 0, 3 do
		local ray = make("Frame", {
			BackgroundColor3 = C.gold,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1.25, 0, 0, 16),
		}, h)
		make("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.25),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, ray)
		table.insert(spinners, { obj = ray, base = i * 45, speed = 35 })
	end
	local glow = make("Frame", {
		BackgroundColor3 = C.gold,
		BackgroundTransparency = 0.55,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(74, 74),
	}, h)
	corner(glow)
	table.insert(pulsers, { obj = make("UIScale", nil, glow), amp = 0.15, speed = 2, phase = y * 10 })

	local b = make("TextButton", centered({ AutoButtonColor = false, Text = "", BackgroundTransparency = 1, ZIndex = 3 }), h)
	emoji(b, icon, 58)
	local t = text(b, title, 18, C.gold)
	t.Size = UDim2.new(1.4, 0, 0, 22)
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Position = UDim2.new(0.5, 0, 0, 2)
	local p = text(b, price, 18, C.green)
	p.Size = UDim2.new(1, 0, 0, 22)
	p.Position = UDim2.new(0, 0, 1, -24)
	juicy(b, 1.15)
	b.Activated:Connect(function()
		openStore(true)
	end)
	bob(h, 6, 2)
end
floatingOffer(0.38, "💸", "OP", "R$99")
floatingOffer(0.64, "🎁", "Starter Pack!", "R$99")
