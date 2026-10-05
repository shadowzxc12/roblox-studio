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

-- Ikony sa kreslia priamo v skripte (fungujú hneď). Ak chceš ostrejšie PNG z icons/png,
-- nahraj ich (View > Asset Manager > Bulk Import) a vlož sem ich ID namiesto 0.
local ICONS = {
	cart = "rbxassetid://0",
	book = "rbxassetid://0",
	gift = "rbxassetid://0",
	rebirth = "rbxassetid://0",
	invite = "rbxassetid://0",
	gear = "rbxassetid://0",
	egg_blue = "rbxassetid://0",
	egg_orange = "rbxassetid://0",
	egg_purple = "rbxassetid://0",
	question = "rbxassetid://0",
	moneybag = "rbxassetid://0",
	crown = "rbxassetid://0",
	clover = "rbxassetid://0",
	cash = "rbxassetid://0",
	magnet = "rbxassetid://0",
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

-- ICON_ART_BEGIN
-- Drawn icons: simple shapes on a 100x100 grid. Each layer is drawn twice:
-- first as a thicker ink silhouette (= the outline), then in colour on top.
local ICON_OUTLINE = 6
local IC = {
	ink = Color3.fromHex("1b1530"),
	white = Color3.fromHex("ffffff"),
	dark = Color3.fromHex("3a3f5c"),
	red = Color3.fromHex("ff4f6d"),
	redDark = Color3.fromHex("c4234a"),
	blue = Color3.fromHex("3a96ff"),
	blueDark = Color3.fromHex("1b5fd1"),
	gold = Color3.fromHex("ffd23f"),
	goldDark = Color3.fromHex("ffb21c"),
	pink = Color3.fromHex("ff5fa2"),
	pinkLight = Color3.fromHex("ff7ab6"),
	green = Color3.fromHex("6aea4f"),
	greenDark = Color3.fromHex("2fb52a"),
	clover = Color3.fromHex("3ddc6a"),
	cloverDark = Color3.fromHex("2a9d4b"),
	grey = Color3.fromHex("a8b2d1"),
	lilac = Color3.fromHex("e9e1ff"),
	steel = Color3.fromHex("e9eef8"),
	tan = Color3.fromHex("e8b46a"),
	brown = Color3.fromHex("c58b4b"),
	orange = Color3.fromHex("ffa324"),
	orangeLight = Color3.fromHex("ffe08a"),
	purple = Color3.fromHex("c063ff"),
	purpleLight = Color3.fromHex("ecc2ff"),
	blueLight = Color3.fromHex("9fd0ff"),
}

-- R = rectangle (r = corner radius or "round"), RC = rectangle by its centre, D = detail (no outline)
local function R(x, y, w, h, c, r, rot, extra)
	local s = { x = x, y = y, w = w, h = h, c = c, r = r, rot = rot }
	if extra then
		for k, v in extra do
			s[k] = v
		end
	end
	return s
end
local function RC(cx, cy, w, h, c, r, rot, extra)
	return R(cx - w / 2, cy - h / 2, w, h, c, r, rot, extra)
end
local function D(s)
	s.d = true
	return s
end
local function T(x, y, w, h, str, c, size, st)
	return { k = "text", x = x, y = y, w = w, h = h, str = str, c = c, size = size, st = st, d = true }
end
local function HL(x, y, w, h, rot)
	return D(RC(x, y, w, h, IC.white, "round", rot, { a = 0.5 }))
end
local function chevron(layer, cx, cy, dir, c)
	for _, side in { -1, 1 } do
		local a = math.rad(dir + 180 + side * 42)
		table.insert(layer, RC(cx + math.cos(a) * 10, cy + math.sin(a) * 10, 24, 11, c, 5.5, math.deg(a)))
	end
end
local function egg(c, spot)
	return {
		{ R(26, 6, 48, 48, c, "round"), R(21, 16, 58, 58, c, "round"), R(16, 26, 68, 68, c, "round") },
		{
			D(R(30, 56, 14, 14, spot, "round")),
			D(R(56, 40, 10, 10, spot, "round")),
			D(R(52, 68, 16, 16, spot, "round")),
			HL(36, 26, 8, 16, 25),
		},
	}
end

local rebirth = { { x = 26, y = 26, w = 48, h = 48, t = 12, c = IC.red, k = "ring" } }
chevron(rebirth, 75.4, 33, 45, IC.red)
chevron(rebirth, 24.6, 67, 225, IC.red)

local gear = { R(22, 22, 56, 56, IC.grey, "round") }
for i = 0, 7 do
	local a = math.rad(i * 45)
	table.insert(gear, RC(50 + math.sin(a) * 30, 50 - math.cos(a) * 30, 15, 18, IC.grey, 3, i * 45))
end

local ICON_ART = {
	cart = {
		{
			R(8, 14, 18, 8, IC.dark, 4),
			RC(27, 25, 8, 20, IC.dark, 4, -25),
			R(24, 30, 68, 38, IC.red, 7),
			R(28, 72, 18, 18, IC.dark, "round"),
			R(66, 72, 18, 18, IC.dark, "round"),
		},
		{
			D(R(38, 37, 5, 24, IC.redDark, 2.5)),
			D(R(53, 37, 5, 24, IC.redDark, 2.5)),
			D(R(68, 37, 5, 24, IC.redDark, 2.5)),
			HL(38, 34, 14, 4),
		},
	},
	book = {
		{ R(22, 78, 60, 14, IC.white, 4), R(18, 8, 64, 76, IC.blue, 8) },
		{ D(R(18, 8, 14, 76, IC.blueDark, 7)), T(30, 20, 52, 50, "★", IC.gold, 44, 3), HL(52, 15, 24, 4) },
	},
	gift = {
		{
			RC(38, 20, 26, 18, IC.gold, "round", -25),
			RC(62, 20, 26, 18, IC.gold, "round", 25),
			R(10, 28, 80, 20, IC.pinkLight, 6),
			R(16, 46, 68, 46, IC.pink, 6),
		},
		{ D(R(44, 28, 12, 64, IC.gold, nil, nil, { s = 2.5 })), HL(25, 34, 18, 4) },
	},
	rebirth = { rebirth },
	invite = {
		{ R(54, 10, 28, 28, IC.green, "round"), R(44, 42, 48, 44, IC.green, 22) },
		{ R(14, 22, 34, 34, IC.blue, "round"), R(8, 58, 50, 36, IC.blue, 18) },
		{ HL(26, 32, 10, 6) },
	},
	gear = {
		gear,
		{ D(R(38, 38, 24, 24, IC.dark, "round", nil, { s = 3 })), HL(32, 30, 5, 14, 40) },
	},
	egg_blue = egg(IC.blue, IC.blueLight),
	egg_orange = egg(IC.orange, IC.orangeLight),
	egg_purple = egg(IC.purple, IC.purpleLight),
	question = { { T(10, 2, 80, 96, "?", IC.lilac, 92, 8) } },
	moneybag = {
		{ R(36, 8, 28, 22, IC.brown, 5), R(14, 24, 72, 70, IC.tan, "round") },
		{
			D(R(32, 24, 36, 9, IC.green, 4.5, nil, { s = 2 })),
			T(20, 36, 60, 54, "$", IC.green, 54, 5),
			HL(28, 50, 8, 16, 30),
		},
	},
	crown = {
		{
			RC(26, 42, 22, 22, IC.gold, 3, 45),
			RC(50, 36, 24, 24, IC.gold, 3, 45),
			RC(74, 42, 22, 22, IC.gold, 3, 45),
			R(20, 18, 12, 12, IC.gold, "round"),
			R(44, 10, 12, 12, IC.gold, "round"),
			R(68, 18, 12, 12, IC.gold, "round"),
			R(12, 42, 76, 34, IC.gold, 4),
			R(8, 70, 84, 20, IC.goldDark, 6),
		},
		{
			D(R(23, 75, 10, 10, IC.red, "round", nil, { s = 1.5 })),
			D(R(44, 74, 12, 12, IC.blue, "round", nil, { s = 1.5 })),
			D(R(67, 75, 10, 10, IC.green, "round", nil, { s = 1.5 })),
			HL(22, 54, 5, 16),
		},
	},
	clover = {
		{ RC(64, 76, 8, 30, IC.cloverDark, 4, -30) },
		{ R(31, 54, 38, 38, IC.clover, "round") },
		{ R(8, 31, 38, 38, IC.clover, "round") },
		{ R(54, 31, 38, 38, IC.clover, "round") },
		{ R(31, 8, 38, 38, IC.clover, "round") },
		{ D(R(44, 44, 12, 12, IC.cloverDark, "round", nil, { s = 2 })), HL(42, 20, 6, 12, -30) },
	},
	cash = {
		{ RC(48, 50, 76, 42, IC.greenDark, 6, -12) },
		{ R(12, 32, 80, 44, IC.green, 6) },
		{
			D(R(38, 40, 28, 28, IC.greenDark, "round", nil, { s = 2.5 })),
			T(38, 40, 28, 28, "$", IC.white, 26, 3),
			HL(26, 39, 16, 4),
		},
	},
	magnet = {
		{
			R(14, 12, 18, 40, IC.red),
			R(68, 12, 18, 40, IC.red),
			{ k = "clip", x = 0, y = 52, w = 100, h = 48, children = {
				{ k = "ring", x = 32, y = 34, w = 36, h = 36, t = 18, c = IC.red },
			} },
		},
		{ R(12, 6, 22, 14, IC.steel, 3), R(66, 6, 22, 14, IC.steel, 3) },
		{ HL(21, 36, 5, 20) },
	},
}
-- ICON_ART_END

-- Icon: an uploaded PNG from ICONS if you set one, otherwise the drawn icon above.
local function icon(parent: Instance, name: string, size: number): GuiObject
	local id = ICONS[name]
	if id and id ~= "rbxassetid://0" then
		return make("ImageLabel", {
			BackgroundTransparency = 1,
			Image = id,
			ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size, size),
			ZIndex = 3,
		}, parent)
	end

	-- CanvasGroup keeps all the pieces together, so the icon can rotate and wobble as one
	local box = make("CanvasGroup", {
		Name = "Icon_" .. name,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		ZIndex = 3,
	}, parent)
	local art = ICON_ART[name]
	if not art then
		return box
	end
	local u = size / 100
	local z = 0

	local function draw(container: Instance, sh, ink: boolean, ox: number, oy: number)
		z += 1
		local o = if ink then ICON_OUTLINE else 0
		if sh.k == "text" then
			local t = make("TextLabel", {
				BackgroundTransparency = 1,
				FontFace = DISPLAY,
				Text = sh.str,
				TextColor3 = sh.c,
				TextSize = sh.size * u,
				Position = UDim2.fromOffset((sh.x - ox) * u, (sh.y - oy) * u),
				Size = UDim2.fromOffset(sh.w * u, sh.h * u),
				ZIndex = z,
			}, container)
			if sh.st then
				make("UIStroke", { Color = IC.ink, Thickness = sh.st * u }, t)
			end
		elseif sh.k == "ring" then
			local f = make("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset((sh.x + o - ox) * u, (sh.y + o - oy) * u),
				Size = UDim2.fromOffset((sh.w - 2 * o) * u, (sh.h - 2 * o) * u),
				ZIndex = z,
			}, container)
			corner(f)
			stroke(f, (sh.t + 2 * o) * u, if ink then IC.ink else sh.c)
		elseif sh.k == "clip" then
			local f = make("Frame", {
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				Position = UDim2.fromOffset((sh.x - ox) * u, (sh.y - oy) * u),
				Size = UDim2.fromOffset(sh.w * u, sh.h * u),
				ZIndex = z,
			}, container)
			for _, child in sh.children do
				draw(f, child, ink, sh.x, sh.y)
			end
		else
			local f = make("Frame", {
				BackgroundColor3 = if ink then IC.ink else sh.c,
				BackgroundTransparency = if ink then 0 else (sh.a or 0),
				BorderSizePixel = 0,
				Position = UDim2.fromOffset((sh.x - o - ox) * u, (sh.y - o - oy) * u),
				Size = UDim2.fromOffset((sh.w + 2 * o) * u, (sh.h + 2 * o) * u),
				Rotation = sh.rot or 0,
				ZIndex = z,
			}, container)
			if sh.r == "round" then
				corner(f)
			elseif sh.r then
				make("UICorner", { CornerRadius = UDim.new(0, (sh.r + o) * u) }, f)
			end
			if sh.s and not ink then
				stroke(f, sh.s * u)
			end
		end
	end

	for _, layer in art do
		for _, sh in layer do
			if not sh.d then
				draw(box, sh, true, 0, 0)
			end
		end
		for _, sh in layer do
			draw(box, sh, false, 0, 0)
		end
	end
	return box
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

local bobbers, spinners, wobblers, pulsers, glowers, scrollers = {}, {}, {}, {}, {}, {}

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
	for _, sc in scrollers do
		local p = sc.pitch
		sc.obj.Position = UDim2.fromOffset(-2 * p + (t * sc.speed) % p, -2 * p + (t * sc.speed) % (2 * p))
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

-- Studs: Lego-like dot pattern for backgrounds (no image assets needed).
-- w/h = pixel size of the area; speed > 0 makes the pattern drift diagonally.
local function studs(parent: GuiObject, w: number, h: number, opts: { [string]: any }?): Frame
	local o = opts or {}
	local pitch = o.pitch or 28
	local size = o.size or 12
	local clip = make("CanvasGroup", {
		Name = "Studs",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
	}, parent)
	corner(clip, o.radius or 12)
	local grid = make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(-2 * pitch, -2 * pitch),
		Size = UDim2.fromOffset(w + 4 * pitch, h + 4 * pitch),
	}, clip)
	for y = 0, math.ceil(h / pitch) + 4 do
		for x = 0, math.ceil(w / pitch) + 4 do
			local stud = make("Frame", {
				BackgroundColor3 = o.color or WHITE,
				BackgroundTransparency = o.alpha or 0.85,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(x * pitch + (y % 2) * pitch / 2, y * pitch),
				Size = UDim2.fromOffset(size, size),
			}, grid)
			corner(stud)
			-- small shine dot = the "plastic" look of a Roblox stud
			make("Frame", {
				BackgroundColor3 = WHITE,
				BackgroundTransparency = math.min(1, (o.alpha or 0.85) + 0.05),
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.2, 0.15),
				Size = UDim2.fromScale(0.35, 0.35),
			}, stud)
		end
	end
	if o.speed then
		table.insert(scrollers, { obj = grid, pitch = pitch, speed = o.speed })
	end
	return clip
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
vgrad(window, Color3.fromHex("343a5c"), C.body)
studs(window, 600, 450, { pitch = 30, size = 14, alpha = 0.9, speed = 12 })
local sparkleLayer = make("CanvasGroup", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 0 }, window)
corner(sparkleLayer, 12)
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

local headIcon = icon(header, "cart", 52)
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

local function packCard(order: number, name: string, top: Color3, bottom: Color3, egg: string, key: string)
	local h = holder(packRow, UDim2.fromOffset(176, 160), order)
	local card = make("Frame", centered({ BackgroundColor3 = WHITE }), h)
	vgrad(card, top, bottom)
	corner(card, 12)
	stroke(card, 3)
	studs(card, 176, 160, { pitch = 22, size = 9, alpha = 0.82 })
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
		local e = icon(s, if i == 2 then egg else "question", 34)
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
packCard(1, "Blue Pack", C.blue, C.blueDark, "egg_blue", "blue")
packCard(2, "Orange Pack", C.tierOrange, C.tierOrangeDark, "egg_orange", "orange")
packCard(3, "Purple Pack", C.purple, C.purpleDark, "egg_purple", "purple")

-- 2) Starter Pack banner
local starterHolder = holder(content, UDim2.fromOffset(552, 140), 2)
local starter = make("Frame", centered({ BackgroundColor3 = WHITE }), starterHolder)
make("UIGradient", { Color = ColorSequence.new(C.starterA, C.starterB) }, starter)
corner(starter, 14)
table.insert(glowers, { obj = stroke(starter, 4, WHITE) })
shine(starter, 14)
studs(starter, 552, 140, { pitch = 26, size = 11, alpha = 0.82, speed = 8, radius = 14 })
popIn(starter)

local stTitle = text(starter, "Starter Pack!", 28)
stTitle.TextXAlignment = Enum.TextXAlignment.Left
stTitle.Position = UDim2.fromOffset(16, 8)
stTitle.Size = UDim2.new(0, 300, 0, 34)

local stItems = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 44), Size = UDim2.fromOffset(360, 88), ZIndex = 3 }, starter)
hlist(stItems, 4, Enum.HorizontalAlignment.Left)
local function stItem(order: number, iconName: string, caption: string, color: Color3, tag: string?)
	local h = holder(stItems, UDim2.fromOffset(86, 88), order)
	local e = icon(h, iconName, 56)
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
stItem(1, "moneybag", "+100k", C.green)
plus(2)
stItem(3, "crown", "VIP", C.gold)
plus(4)
stItem(5, "gift", "Item", WHITE, "OP!")

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
studs(luck, 552, 96, { pitch = 24, size = 10, alpha = 0.82 })
popIn(luck)
local clover = icon(luck, "clover", 56)
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
	{ "VIP", "crown", "R$199", "vip", C.gold, C.tierOrangeDark },
	{ "2x Cash", "cash", "R$149", "cash2x", C.green, C.greenDark },
	{ "Auto Collect", "magnet", "R$99", "auto", C.pink, C.purpleDark },
} do
	local h = holder(passRow, UDim2.fromOffset(176, 136), i)
	local card = make("Frame", centered({ BackgroundColor3 = WHITE }), h)
	vgrad(card, info[5], info[6])
	corner(card, 12)
	stroke(card, 3)
	studs(card, 176, 160, { pitch = 22, size = 9, alpha = 0.82 })
	popIn(card)
	local e = icon(card, info[2], 48)
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

-- Sparkles drifting up behind the shop content while it is open
local SPARKLES = { "✦", "✧", "★", "•" }
local function sparkleLoop()
	while isOpen do
		local s = make("TextLabel", {
			BackgroundTransparency = 1,
			Text = SPARKLES[math.random(#SPARKLES)],
			TextColor3 = CONFETTI[math.random(#CONFETTI)],
			TextSize = math.random(12, 24),
			TextTransparency = 0.3,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(math.random(), 0, 1, 20),
			Size = UDim2.fromOffset(30, 30),
		}, sparkleLayer)
		local dur = 3 + math.random() * 3
		TweenService:Create(s, TweenInfo.new(dur, Enum.EasingStyle.Linear), {
			Position = s.Position + UDim2.new(math.random(-10, 10) / 100, 0, -1.1, 0),
			Rotation = math.random(-180, 180),
			TextTransparency = 1,
		}):Play()
		task.delay(dur, function()
			s:Destroy()
		end)
		task.wait(0.25)
	end
end

local function openStore(highlightStarter: boolean?)
	if isOpen then
		return
	end
	isOpen = true
	task.spawn(sparkleLoop)
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

-- The SHOP stand on the map has a ProximityPrompt named "OpenShop" (press E / tap)
game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt)
	if prompt.Name == "OpenShop" then
		openStore()
	end
end)
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
	{ name = "Store", icon = "cart", badge = true, action = function() openStore() end },
	{ name = "Index", icon = "book" },
	{ name = "Gift", icon = "gift", badge = true },
	{ name = "Rebirth", icon = "rebirth" },
	{ name = "Invite", icon = "invite" },
	{ name = "Settings", icon = "gear" },
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
	local ic = icon(b, item.icon, 44)
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

local function floatingOffer(y: number, iconName: string, title: string, price: string)
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
	icon(b, iconName, 68)
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
floatingOffer(0.38, "cash", "OP", "R$99")
floatingOffer(0.64, "gift", "Starter Pack!", "R$99")
