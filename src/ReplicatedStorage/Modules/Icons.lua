--[[
	Icons: cartoon icons drawn from simple shapes (no image uploads needed).
	Each layer is drawn twice: a thicker ink silhouette (the outline) and the colours on top.
	Icons.Create(parent, "coin", 48)
]]

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
	coin = {
		{ R(12, 12, 76, 76, IC.gold, "round") },
		{ D(R(26, 26, 48, 48, IC.goldDark, "round", nil, { s = 3 })), T(26, 26, 48, 48, "$", IC.gold, 40, 4), HL(30, 30, 8, 16, 30) },
	},
	trophy = {
		{
			{ k = "ring", x = 12, y = 20, w = 20, h = 22, t = 7, c = IC.gold },
			{ k = "ring", x = 68, y = 20, w = 20, h = 22, t = 7, c = IC.gold },
			R(26, 10, 48, 48, IC.gold, 16),
			R(44, 54, 12, 16, IC.gold),
			R(28, 66, 44, 10, IC.goldDark, 3),
			R(20, 76, 60, 14, IC.brown, 4),
		},
		{ T(26, 12, 48, 40, "1", IC.goldDark, 34, 0), HL(36, 22, 6, 18) },
	},
	star = { { T(4, 0, 92, 100, "★", IC.gold, 96, 7) } },
	bolt = {
		{ RC(50, 28, 16, 50, IC.gold, 3, 32), RC(50, 50, 34, 14, IC.gold, 3), RC(50, 72, 16, 50, IC.gold, 3, 32) },
		{ HL(56, 18, 4, 14, 32) },
	},
	virus = {
		{
			R(42, 4, 16, 16, IC.clover, "round"), R(42, 80, 16, 16, IC.clover, "round"),
			R(4, 42, 16, 16, IC.clover, "round"), R(80, 42, 16, 16, IC.clover, "round"),
			R(14, 14, 14, 14, IC.clover, "round"), R(72, 14, 14, 14, IC.clover, "round"),
			R(14, 72, 14, 14, IC.clover, "round"), R(72, 72, 14, 14, IC.clover, "round"),
			R(18, 18, 64, 64, IC.clover, "round"),
		},
		{
			D(R(32, 36, 12, 16, IC.ink, "round")), D(R(56, 36, 12, 16, IC.ink, "round")),
			D(R(38, 62, 24, 8, IC.ink, 4)), HL(32, 28, 8, 5),
		},
	},
	play = { { T(14, 0, 80, 100, "▶", IC.white, 80, 6) } },

}

local Icons = {}
Icons.Names = {}
for name in ICON_ART do
	table.insert(Icons.Names, name)
end

-- Creates an icon (a Frame; rotating/scaling it moves all pieces together), centred in parent.
function Icons.Create(parent: Instance, name: string, size: number): Frame
	local box = Instance.new("Frame")
	box.Name = "Icon_" .. name
	box.BackgroundTransparency = 1
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromOffset(size, size)
	box.ZIndex = 3
	box.Parent = parent
	local art = ICON_ART[name]
	if not art then
		return box
	end
	local u = size / 100
	local z = 0
	local font = Font.fromEnum(Enum.Font.FredokaOne)

	local function frame(container, props)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		for k, v in props do
			(f :: any)[k] = v
		end
		f.Parent = container
		return f
	end
	local function round(f, radius)
		local c = Instance.new("UICorner")
		c.CornerRadius = radius
		c.Parent = f
	end
	local function outline(f, thickness, color)
		local s = Instance.new("UIStroke")
		s.Color = color
		s.Thickness = thickness
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = f
	end

	local function draw(container: Instance, sh, ink: boolean, ox: number, oy: number)
		z += 1
		local o = if ink then ICON_OUTLINE else 0
		if sh.k == "text" then
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.FontFace = font
			t.Text = sh.str
			t.TextColor3 = sh.c
			t.TextSize = sh.size * u
			t.Position = UDim2.fromOffset((sh.x - ox) * u, (sh.y - oy) * u)
			t.Size = UDim2.fromOffset(sh.w * u, sh.h * u)
			t.ZIndex = z
			if sh.st and sh.st > 0 then
				local s = Instance.new("UIStroke")
				s.Color = IC.ink
				s.Thickness = sh.st * u
				s.Parent = t
			end
			t.Parent = container
		elseif sh.k == "ring" then
			local f = frame(container, {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset((sh.x + o - ox) * u, (sh.y + o - oy) * u),
				Size = UDim2.fromOffset((sh.w - 2 * o) * u, (sh.h - 2 * o) * u),
				ZIndex = z,
			})
			round(f, UDim.new(1, 0))
			outline(f, (sh.t + 2 * o) * u, if ink then IC.ink else sh.c)
		elseif sh.k == "clip" then
			local f = frame(container, {
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				Position = UDim2.fromOffset((sh.x - ox) * u, (sh.y - oy) * u),
				Size = UDim2.fromOffset(sh.w * u, sh.h * u),
				ZIndex = z,
			})
			for _, child in sh.children do
				draw(f, child, ink, sh.x, sh.y)
			end
		else
			local f = frame(container, {
				BackgroundColor3 = if ink then IC.ink else sh.c,
				BackgroundTransparency = if ink then 0 else (sh.a or 0),
				Position = UDim2.fromOffset((sh.x - o - ox) * u, (sh.y - o - oy) * u),
				Size = UDim2.fromOffset((sh.w + 2 * o) * u, (sh.h + 2 * o) * u),
				Rotation = sh.rot or 0,
				ZIndex = z,
			})
			if sh.r == "round" then
				round(f, UDim.new(1, 0))
			elseif sh.r then
				round(f, UDim.new(0, (sh.r + o) * u))
			end
			if sh.s and not ink then
				outline(f, sh.s * u, IC.ink)
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

return Icons
