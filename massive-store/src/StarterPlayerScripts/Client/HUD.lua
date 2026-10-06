--[[
	HUD: everything on screen while you are in the store.

	  top-left      objective + where you are (department)
	  top-centre    DAY 3 / NIGHT 7, clock, time left, random event card
	  top-right     nearby players (distance, direction, status)
	  bottom-left   health, hunger, stamina, energy, flashlight battery
	  right         notifications
	  centre        big banners (NIGHT 7 — THE LOCUST IS HUNTING), XP, level ups
	  edges         Locust proximity vignette + heartbeat pulse, damage flash
	  overlays      downed, dead, hiding, night vision, results, tutorial
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Net = require(Shared.Net)

local UI = require(script.Parent.UI)
local ClientState = require(script.Parent.ClientState)
local Audio = require(script.Parent.Audio)
local Atmosphere = require(script.Parent.Atmosphere)

local HUD = {}

local player = Players.LocalPlayer
local C = UI.C
local make = UI.make

local gui, root
local overlayGui, overlayRoot
local refs = {}

--============================ SMALL GLYPHS ============================--
local function glyph(parent, kind: string, color: Color3, size: number)
	local f = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size) }, parent)
	local function r(x, y, w, h, rot, round)
		local p = make("Frame", {
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromScale(w, h),
			Rotation = rot or 0,
		}, f)
		if round then
			UI.corner(p, round)
		end
		return p
	end
	if kind == "Health" then
		r(0.5, 0.5, 0.7, 0.24, 0, 2)
		r(0.5, 0.5, 0.24, 0.7, 0, 2)
	elseif kind == "Hunger" then
		local b = r(0.5, 0.56, 0.62, 0.62)
		UI.corner(b)
		r(0.6, 0.2, 0.12, 0.22, 30, 2)
	elseif kind == "Stamina" then
		r(0.42, 0.32, 0.18, 0.42, 25, 2)
		r(0.58, 0.68, 0.18, 0.42, 25, 2)
		r(0.5, 0.5, 0.42, 0.14, 0, 2)
	elseif kind == "Energy" then
		r(0.5, 0.52, 0.4, 0.66, 0, 3)
		r(0.5, 0.15, 0.18, 0.08, 0, 1)
	elseif kind == "Battery" then
		r(0.46, 0.5, 0.66, 0.38, 0, 2)
		r(0.86, 0.5, 0.08, 0.18, 0, 1)
	elseif kind == "Pin" then
		local b = r(0.5, 0.38, 0.5, 0.5)
		UI.corner(b)
		r(0.5, 0.66, 0.14, 0.4, 0, 2)
	end
	return f
end
HUD.Glyph = glyph

--============================ BUILD ============================--
local function buildVitals()
	-- Figma 04: glass panel, mono labels, thin bars, numbers on the right
	local box = UI.panel(root, { Name = "Vitals", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -24), Size = UDim2.fromOffset(284, 124), BackgroundTransparency = 0.2 }, 8)
	local list = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 1, -20) }, box)
	UI.list(list, 5).VerticalAlignment = Enum.VerticalAlignment.Center
	local rows = {}
	local defs = {
		{ "Health", "HP", C.Health, 1 },
		{ "Hunger", "FOOD", C.Hunger, 2 },
		{ "Energy", "ENERGY", C.Energy, 3 },
		{ "Stamina", "STAMINA", C.Stamina, 4 },
		{ "Battery", "BATTERY", C.Battery, 5 },
	}
	for _, d in defs do
		local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = d[4] }, list)
		UI.text(row, d[2], 9, C.Muted, UI.Mono, { Size = UDim2.fromOffset(64, 16) })
		local bar, set = UI.bar(row, d[3], { Position = UDim2.fromOffset(68, 4), Size = UDim2.new(1, -108, 0, 7) })
		local value = UI.text(row, "100", 11, C.Text, UI.Mono, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(34, 16), TextXAlignment = Enum.TextXAlignment.Right })
		rows[d[1]] = { Row = row, Set = set, Value = value, Bar = bar }
	end
	rows.Battery.Row.Visible = false
	refs.Vitals = rows
	refs.VitalsBox = box
	local buff = UI.text(root, "", 11, C.Accent, UI.Mono, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 26, 1, -154), Size = UDim2.fromOffset(280, 16), Visible = false })
	refs.Buff = buff

	-- noise meter (bottom right, Figma 04)
	local nm = UI.panel(root, { Name = "Noise", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -56), Size = UDim2.fromOffset(220, 62), BackgroundTransparency = 0.2 }, 8)
	UI.text(nm, "NOISE", 9, C.Muted, UI.Mono, { Position = UDim2.fromOffset(14, 8), Size = UDim2.fromOffset(80, 12) })
	local state = UI.text(nm, "QUIET", 9, C.Good, UI.Mono, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 8), Size = UDim2.fromOffset(100, 12), TextXAlignment = Enum.TextXAlignment.Right })
	local bars = {}
	for i = 1, 14 do
		local f = make("Frame", { BackgroundColor3 = C.Text, BackgroundTransparency = 0.85, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromOffset(14 + (i - 1) * 13.6, 54), Size = UDim2.fromOffset(8, 4) }, nm)
		UI.corner(f, 2)
		bars[i] = f
	end
	refs.Noise = { Bars = bars, State = state, Level = 0, Shape = {} }
	for i = 1, 14 do
		refs.Noise.Shape[i] = 0.35 + 0.65 * math.abs(math.sin(i * 1.7))
	end

	-- crosshair (first person)
	local dot = make("Frame", { Name = "Crosshair", BackgroundColor3 = C.Text, BackgroundTransparency = 0.1, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(6, 6) }, root)
	UI.corner(dot)
	UI.stroke(dot, Color3.new(0, 0, 0), 1, 0.5)
	refs.Crosshair = dot
end

local function buildPhase()
	local pill = UI.panel(root, { Name = "Phase", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 20), Size = UDim2.fromOffset(260, 70), BackgroundTransparency = 0.15 }, 8)
	local title = UI.text(pill, "DAY 1", 26, C.Text, UI.Title, { Position = UDim2.fromOffset(16, 4), Size = UDim2.fromOffset(150, 32) })
	local clock = UI.text(pill, "07:00 AM", 18, C.Text, UI.Mono, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 9), Size = UDim2.fromOffset(110, 24), TextXAlignment = Enum.TextXAlignment.Right })
	local sub = UI.text(pill, "", 9, C.Muted, UI.Mono, { Position = UDim2.fromOffset(16, 36), Size = UDim2.new(1, -32, 0, 12), TextTruncate = Enum.TextTruncate.AtEnd })
	local bar, set, fill = UI.bar(pill, C.Accent, { Position = UDim2.fromOffset(16, 54), Size = UDim2.new(1, -32, 0, 4) })
	refs.Phase = { Pill = pill, Title = title, Clock = clock, Sub = sub, SetBar = set, Fill = fill }

	local event = UI.panel(root, { Name = "Event", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 98), Size = UDim2.fromOffset(360, 52), Visible = false }, 8)
	UI.stroke(event, C.Danger, 1, 0.3)
	event.BackgroundColor3 = Color3.fromHex("1a0b0c")
	local en = UI.text(event, "", 16, C.Danger, UI.Title, { Position = UDim2.fromOffset(14, 5), Size = UDim2.fromOffset(330, 22) })
	local ed = UI.text(event, "", 11, C.Text, UI.Body, { Position = UDim2.fromOffset(14, 28), Size = UDim2.fromOffset(330, 16), TextTruncate = Enum.TextTruncate.AtEnd })
	refs.Event = { Frame = event, Name = en, Desc = ed }
end

local function buildObjective()
	local box = UI.panel(root, { Name = "Objective", Position = UDim2.fromOffset(24, 24), Size = UDim2.fromOffset(320, 92), BackgroundTransparency = 0.2 }, 8)
	local bar = make("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Size = UDim2.new(0, 4, 1, 0), ZIndex = 3 }, box)
	UI.text(box, "OBJECTIVE", 10, C.Accent, UI.Mono, { Position = UDim2.fromOffset(18, 10), Size = UDim2.fromOffset(200, 12) })
	local text = UI.text(box, "Explore the store", 17, C.Text, UI.Heading, { Position = UDim2.fromOffset(18, 24), Size = UDim2.new(1, -30, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd })
	local teamLine = UI.text(box, "", 11, C.Purple, UI.Semi, { Position = UDim2.fromOffset(18, 48), Size = UDim2.new(1, -30, 0, 14), TextTruncate = Enum.TextTruncate.AtEnd })
	local loc = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 66), Size = UDim2.new(1, -30, 0, 16) }, box)
	glyph(loc, "Pin", C.Muted, 12).Position = UDim2.fromOffset(0, 2)
	local where = UI.text(loc, "", 10, C.Muted, UI.Mono, { Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -18, 1, 0) })
	refs.Objective = { Text = text, Where = where, Bar = bar, Team = teamLine }
end

local function buildSquad()
	local box = make("Frame", { Name = "Squad", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 24), Size = UDim2.fromOffset(230, 260) }, root)
	UI.list(box, 4, false, Enum.HorizontalAlignment.Right)
	UI.text(box, "TEAM", 10, C.Muted, UI.Mono, { Size = UDim2.fromOffset(230, 12), TextXAlignment = Enum.TextXAlignment.Right, LayoutOrder = 0 })
	refs.Squad = { Box = box, Rows = {} }
end

local function buildToasts()
	local box = make("Frame", { Name = "Toasts", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20, 0.55, 0), Size = UDim2.fromOffset(330, 300) }, root)
	local l = UI.list(box, 6, false, Enum.HorizontalAlignment.Right)
	l.VerticalAlignment = Enum.VerticalAlignment.Bottom
	refs.Toasts = box
end

local function buildBanner()
	local holder = make("Frame", { Name = "Banner", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.34), Size = UDim2.fromOffset(900, 120), Visible = false }, root)
	local title = UI.text(holder, "", 64, C.Text, UI.Title, { Size = UDim2.fromOffset(900, 72), TextXAlignment = Enum.TextXAlignment.Center })
	make("UIStroke", { Thickness = 2, Transparency = 0.6, Color = Color3.new(0, 0, 0) }, title)
	local line = make("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(450, 76), Size = UDim2.fromOffset(240, 2) }, holder)
	local sub = UI.text(holder, "", 18, C.Text, UI.Caps, { Position = UDim2.fromOffset(0, 86), Size = UDim2.fromOffset(900, 24), TextXAlignment = Enum.TextXAlignment.Center })
	refs.Banner = { Holder = holder, Title = title, Sub = sub, Line = line }
end

local function edge(parent, anchor, pos, size, rot)
	local f = make("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, AnchorPoint = anchor, Position = pos, Size = size, BackgroundTransparency = 0 }, parent)
	make("UIGradient", { Rotation = rot, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }) }, f)
	return f
end

local function buildOverlays()
	overlayGui, overlayRoot = UI.screen("MSL_Overlay", 2)
	-- vignette (edges) for darkness / Locust proximity
	local vig = make("Frame", { Name = "Vignette", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, overlayRoot)
	local edges = {
		edge(vig, Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.3), 90),
		edge(vig, Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromScale(1, 0.3), -90),
		edge(vig, Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(0.25, 1), 0),
		edge(vig, Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.fromScale(0.25, 1), 180),
	}
	refs.Vignette = edges
	local hunted = UI.text(overlayRoot, "IT'S HUNTING YOU", 14, C.Danger, UI.Caps, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 150), Size = UDim2.fromOffset(400, 20), TextXAlignment = Enum.TextXAlignment.Center, Visible = false })
	refs.Hunted = hunted
	local flash = make("Frame", { Name = "DamageFlash", BackgroundColor3 = Color3.fromHex("ff1e1e"), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, overlayRoot)
	refs.Flash = flash

	-- hiding: slats
	local hide = make("Frame", { Name = "Hiding", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false }, overlayRoot)
	for i = 0, 9 do
		make("Frame", { BackgroundColor3 = Color3.fromHex("050506"), BorderSizePixel = 0, Position = UDim2.fromScale(0, i / 10), Size = UDim2.new(1, 0, 0.055, 0), BackgroundTransparency = 0.05 }, hide)
	end
	UI.text(hide, "HIDING", 22, C.Text, UI.Title, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -110), Size = UDim2.fromOffset(400, 30), TextXAlignment = Enum.TextXAlignment.Center })
	UI.text(hide, "[E] or [SPACE] to leave · stay quiet", 13, C.Muted, UI.Caps, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -88), Size = UDim2.fromOffset(500, 18), TextXAlignment = Enum.TextXAlignment.Center })
	refs.Hiding = hide

	-- downed
	local down = make("Frame", { Name = "Downed", BackgroundColor3 = Color3.fromHex("200000"), BackgroundTransparency = 0.55, Size = UDim2.fromScale(1, 1), Visible = false }, overlayRoot)
	UI.text(down, "YOU'RE DOWN", 54, C.Danger, UI.Title, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(800, 64), TextXAlignment = Enum.TextXAlignment.Center })
	local dsub = UI.text(down, "", 18, C.Text, UI.Caps, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(800, 24), TextXAlignment = Enum.TextXAlignment.Center })
	local dhint = UI.text(down, "", 14, C.Muted, UI.Bold, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromOffset(800, 20), TextXAlignment = Enum.TextXAlignment.Center })
	refs.Downed = { Frame = down, Sub = dsub, Hint = dhint }

	-- dead
	local dead = make("Frame", { Name = "Dead", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false }, overlayRoot)
	UI.text(dead, "YOU DIDN'T MAKE IT", 40, C.Text, UI.Title, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120), Size = UDim2.fromOffset(800, 48), TextXAlignment = Enum.TextXAlignment.Center })
	local deadSub = UI.text(dead, "You'll be back at dawn. Your bag was left where you fell.", 15, C.Muted, UI.Caps, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 170), Size = UDim2.fromOffset(800, 20), TextXAlignment = Enum.TextXAlignment.Center })
	refs.Dead = { Frame = dead, Sub = deadSub }

	-- night vision
	local nv = make("Frame", { Name = "NightVision", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false }, overlayRoot)
	for i = 0, 40 do
		make("Frame", { BackgroundColor3 = Color3.fromHex("0b2a0b"), BackgroundTransparency = 0.85, BorderSizePixel = 0, Position = UDim2.fromScale(0, i / 40), Size = UDim2.new(1, 0, 0, 1) }, nv)
	end
	local rec = make("Frame", { BackgroundTransparency = 1, Position = UDim2.new(1, -150, 1, -42), Size = UDim2.fromOffset(130, 22) }, nv)
	UI.iconLabel(rec, "dot", "NV  REC", 14, C.Good, UI.Mono)
	refs.NV = nv
end

local function buildHints()
	local hints = make("Frame", { Name = "Hints", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -20), Size = UDim2.fromOffset(420, 22) }, root)
	local l = UI.list(hints, 10, true, Enum.HorizontalAlignment.Right)
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	for i, pair in { { "B", "Build" }, { "Tab", "Inventory" }, { "M", "Map" }, { "F", "Light" }, { "C", "Crouch" } } do
		local h = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(10, 22), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i }, hints)
		UI.list(h, 4, true).VerticalAlignment = Enum.VerticalAlignment.Center
		local cap = UI.keycap(h, pair[1], 18)
		cap.LayoutOrder = 1
		UI.text(h, pair[2], 12, C.Muted, UI.Bold, { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 })
	end
	hints.Visible = not UI.IsTouch()
	refs.Hints = hints
	local cart = UI.panel(root, { Name = "CartInfo", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -112), Size = UDim2.fromOffset(300, 30), Visible = false }, 8)
	refs.CartText = UI.text(cart, "", 13, C.Text, UI.Bold, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
	refs.Cart = cart
end

--============================ ACTIONS ============================--
local TOAST_COLORS = {
	Info = C.Info,
	Good = C.Good,
	Warn = C.Accent,
	Danger = C.Danger,
	Credits = C.Accent,
	Mission = C.Purple,
	Legendary = Color3.fromHex("ffb31a"),
}

-- set by Main: in the lobby part of the place the lobby shows notifications instead
HUD.ShouldToast = function(): boolean
	return true
end

function HUD.Toast(text: string, kind: string?)
	kind = kind or "Info"
	local color = TOAST_COLORS[kind] or C.Info
	local t = UI.panel(refs.Toasts, { Size = UDim2.fromOffset(330, 10), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 0.12, LayoutOrder = math.floor(os.clock() * 100) }, 8)
	make("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.new(0, 3, 1, 0) }, t)
	UI.pad(t, 12, 8)
	UI.text(t, text, 13, C.Text, UI.Bold, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true })
	local scale = make("UIScale", { Scale = 0.8 }, t)
	UI.tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	local sound = if kind == "Danger" or kind == "Warn" then "Warn" elseif kind == "Legendary" then "Legendary" elseif kind == "Good" or kind == "Mission" then "Good" else "Notify"
	Audio.Play(sound)
	task.delay(4.5, function()
		UI.tween(t, 0.4, { BackgroundTransparency = 1 })
		for _, d in t:GetDescendants() do
			if d:IsA("TextLabel") then
				UI.tween(d, 0.4, { TextTransparency = 1 })
			elseif d:IsA("Frame") then
				UI.tween(d, 0.4, { BackgroundTransparency = 1 })
			elseif d:IsA("UIStroke") then
				UI.tween(d, 0.4, { Transparency = 1 })
			end
		end
		task.wait(0.45)
		t:Destroy()
	end)
	local list = refs.Toasts:GetChildren()
	local count = 0
	for _, c in list do
		if c:IsA("Frame") then
			count += 1
		end
	end
	if count > 5 then
		for _, c in list do
			if c:IsA("Frame") then
				c:Destroy()
				break
			end
		end
	end
end

local bannerToken = 0
function HUD.Banner(payload)
	bannerToken += 1
	local token = bannerToken
	local b = refs.Banner
	b.Title.Text = payload.Title or ""
	b.Sub.Text = payload.Sub or ""
	local color = if payload.Color then Color3.fromHex(payload.Color) else C.Text
	b.Title.TextColor3 = color
	b.Line.BackgroundColor3 = color
	b.Holder.Visible = true
	b.Title.TextTransparency = 1
	b.Sub.TextTransparency = 1
	b.Line.Size = UDim2.fromOffset(0, 2)
	UI.tween(b.Title, 0.5, { TextTransparency = 0 })
	UI.tween(b.Sub, 0.8, { TextTransparency = 0 })
	UI.tween(b.Line, 0.8, { Size = UDim2.fromOffset(320, 2) })
	task.delay(payload.Time or 4, function()
		if token ~= bannerToken then
			return
		end
		UI.tween(b.Title, 0.8, { TextTransparency = 1 })
		UI.tween(b.Sub, 0.8, { TextTransparency = 1 })
		UI.tween(b.Line, 0.8, { Size = UDim2.fromOffset(0, 2) })
		task.wait(0.85)
		if token == bannerToken then
			b.Holder.Visible = false
		end
	end)
end

local eventToken = 0
function HUD.Event(e)
	eventToken += 1
	local token = eventToken
	local ev = refs.Event
	ev.Name.Text = e.Name or ""
	ev.Desc.Text = e.Desc or ""
	ev.Frame.Visible = true
	ev.Frame.Position = UDim2.new(0.5, 0, 0, 70)
	UI.tween(ev.Frame, 0.3, { Position = UDim2.new(0.5, 0, 0, 86) }, Enum.EasingStyle.Back)
	Audio.Play("Warn")
	task.delay(math.max(6, math.min(e.Time or 8, 20)), function()
		if token == eventToken then
			ev.Frame.Visible = false
		end
	end)
end

local xpQueue = {}
function HUD.XP(amount: number, reason: string)
	local holder = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -150 - #xpQueue * 24), Size = UDim2.fromOffset(500, 22) }, root)
	table.insert(xpQueue, holder)
	local t = UI.text(holder, ("+%d XP  %s"):format(amount, reason or ""), 15, C.Accent, UI.Title, { TextXAlignment = Enum.TextXAlignment.Center })
	Audio.Play("XP")
	UI.tween(holder, 2.2, { Position = holder.Position - UDim2.fromOffset(0, 40) })
	task.delay(1.4, function()
		UI.tween(t, 0.8, { TextTransparency = 1 })
		task.wait(0.85)
		local i = table.find(xpQueue, holder)
		if i then
			table.remove(xpQueue, i)
		end
		holder:Destroy()
	end)
end

function HUD.LevelUp(info)
	local card = UI.panel(root, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.62), Size = UDim2.fromOffset(420, 80), AutomaticSize = Enum.AutomaticSize.Y }, 12)
	UI.stroke(card, C.Accent, 2)
	UI.pad(card, 16, 12)
	UI.list(card, 4, false, Enum.HorizontalAlignment.Center)
	UI.text(card, "LEVEL " .. info.Level, 34, C.Accent, UI.Title, { Size = UDim2.fromOffset(380, 38), TextXAlignment = Enum.TextXAlignment.Center })
	for _, u in info.Unlocks or {} do
		UI.text(card, "UNLOCKED · " .. u.Text, 13, C.Text, UI.Caps, { Size = UDim2.fromOffset(380, 18), TextXAlignment = Enum.TextXAlignment.Center })
	end
	local scale = make("UIScale", { Scale = 0.5 }, card)
	UI.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	Audio.Play("LevelUp")
	task.delay(4.5, function()
		UI.tween(scale, 0.25, { Scale = 0 })
		task.wait(0.3)
		card:Destroy()
	end)
end

function HUD.Flash(strength: number)
	refs.Flash.BackgroundTransparency = 1 - math.clamp(strength, 0.1, 0.55)
	UI.tween(refs.Flash, 0.5, { BackgroundTransparency = 1 })
end

--============================ RESULTS ============================--
-- Figma 08 "Run Over — Results": big title, stat tiles, party, BACK TO LOBBY / NEW STORE
function HUD.Results(summary)
	local old = overlayRoot:FindFirstChild("Results")
	if old then
		old:Destroy()
	end
	local screen = make("Frame", { Name = "Results", BackgroundColor3 = Color3.fromHex("060708"), BackgroundTransparency = 0.08, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 20 }, overlayRoot)
	ClientState.SetBusy("Results", true)
	local glow = make("Frame", { BackgroundColor3 = C.Danger, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromScale(0.9, 0.9), ZIndex = 20 }, screen)
	UI.corner(glow)
	make("UIGradient", { Transparency = NumberSequence.new(0.86, 1), Rotation = 90 }, glow)
	local body = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 60), Size = UDim2.fromOffset(816, 620), ZIndex = 21 }, screen)
	local z = 22
	local modeName = Config.Modes[summary.Mode] and Config.Modes[summary.Mode].Name or ""
	UI.text(body, "THE STORE IS CLOSED", 12, C.Danger, UI.Mono, { Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z })
	UI.text(body, ("YOU SURVIVED %d NIGHT%s"):format(summary.Nights, if summary.Nights == 1 then "" else "S"), 60, C.Text, UI.Title, { Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 72), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z })
	local d = ClientState.Data
	UI.text(body, ("Best: %d nights  ·  %s  ·  %s"):format(d and d.BestNight or summary.Nights, modeName, Util.FormatTime(summary.Duration or 0)), 13, C.Muted, UI.Body, { Position = UDim2.fromOffset(0, 96), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z })
	-- tiles
	local built, revives, downs = 0, 0, 0
	for _, p in summary.Players or {} do
		built += p.Built or 0
		revives += p.Revives or 0
		downs += p.Downs or 0
	end
	for i, t in { { "NIGHTS", summary.Nights, C.Accent }, { "BUILT", built, C.Text }, { "REVIVES", revives, C.Good }, { "DOWNS", downs, C.Danger } } do
		local tile = make("Frame", { BackgroundColor3 = C.Panel, BorderSizePixel = 0, Position = UDim2.fromOffset((i - 1) * 208, 136), Size = UDim2.fromOffset(196, 116), ZIndex = z }, body)
		UI.corner(tile, 10)
		UI.stroke(tile, Color3.new(1, 1, 1), 1, 0.92)
		UI.text(tile, t[1], 10, C.Muted, UI.Mono, { Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 14), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z + 1 })
		UI.text(tile, tostring(t[2]), 46, t[3], UI.Title, { Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 56), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z + 1 })
	end
	-- party
	local party = make("Frame", { BackgroundColor3 = C.Panel, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 268), Size = UDim2.new(1, 0, 0, 180), ZIndex = z }, body)
	UI.corner(party, 10)
	UI.stroke(party, Color3.new(1, 1, 1), 1, 0.92)
	local list = make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(20, 14), Size = UDim2.new(1, -40, 1, -28), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3, ZIndex = z + 1 }, party)
	make("UIGridLayout", { CellSize = UDim2.new(0.5, -8, 0, 48), CellPadding = UDim2.fromOffset(12, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	for i, p in summary.Players or {} do
		local row = make("Frame", { BackgroundTransparency = 1, LayoutOrder = i, ZIndex = z + 1 }, list)
		local av = make("Frame", { BackgroundColor3 = if i == 1 then C.Accent else C.Info, BorderSizePixel = 0, Size = UDim2.fromOffset(44, 44), ZIndex = z + 2 }, row)
		UI.corner(av)
		UI.text(av, string.upper(string.sub(p.Name or "?", 1, 1)), 20, C.Ink, UI.Title, { TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z + 3 })
		UI.text(row, p.Name or "?", 17, C.Text, UI.Heading, { Position = UDim2.fromOffset(56, 2), Size = UDim2.new(1, -60, 0, 22), ZIndex = z + 2, TextTruncate = Enum.TextTruncate.AtEnd })
		UI.text(row, ("%d nights · %d built · %d revives%s"):format(p.Nights or 0, p.Built or 0, p.Revives or 0, if i == 1 then " · MVP" else ""), 10, C.Muted, UI.Mono, { Position = UDim2.fromOffset(56, 26), Size = UDim2.new(1, -60, 0, 14), ZIndex = z + 2 })
	end
	-- buttons
	local lobby = UI.button(body, { Name = "BackToLobby", Text = "BACK TO LOBBY", Sub = "teleport · your party stays together", Style = "Primary", Position = UDim2.fromOffset(0, 468), Size = UDim2.fromOffset(400, 66), TextSize = 26, ZIndex = z })
	local stay = UI.button(body, { Name = "NewStore", Text = "NEW STORE", Sub = "same server · starts by itself", Position = UDim2.fromOffset(416, 468), Size = UDim2.fromOffset(400, 66), TextSize = 26, ZIndex = z })
	local timer = UI.text(body, "", 11, C.Muted, UI.Mono, { Position = UDim2.fromOffset(0, 546), Size = UDim2.new(1, 0, 0, 14), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z })
	local function close()
		ClientState.SetBusy("Results", false)
		if screen.Parent then
			screen:Destroy()
		end
	end
	lobby.Activated:Connect(function()
		Net.Event("Lobby"):FireServer("Return")
		local label = lobby:FindFirstChild("Label")
		if label then
			label.Text = "SEE YOU THERE"
		end
	end)
	stay.Activated:Connect(close)
	local scale = make("UIScale", { Scale = 0.92 }, body)
	UI.tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	local ends = os.clock() + Config.Cycle.WipeResults - 1
	task.spawn(function()
		while screen.Parent and os.clock() < ends do
			timer.Text = ("A NEW STORE OPENS IN %ds"):format(math.ceil(ends - os.clock()))
			task.wait(0.25)
		end
		close()
	end)
end

--============================ TUTORIAL ============================--
local TIPS = {
	{ "WELCOME TO MASSIVE STORE", "It's huge. Grab food and materials while the lights are on." },
	{ "BUILD A BASE  [B]", "Walls, doors, beds, generators, traps. Upgrade them — the Locust gets stronger." },
	{ "WHEN NIGHT FALLS", "Get back to your base or hide in a locker. Sprinting and lights give you away." },
	{ "TEAMWORK", "Share supplies, push carts, revive downed teammates (hold [E] on them)." },
}

function HUD.Tutorial()
	task.spawn(function()
		for i, tip in TIPS do
			local card = UI.panel(root, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -200), Size = UDim2.fromOffset(520, 70) }, 12)
			UI.stroke(card, C.Accent, 1.5)
			UI.text(card, tip[1], 18, C.Accent, UI.Title, { Position = UDim2.fromOffset(18, 10), Size = UDim2.fromOffset(480, 22) })
			UI.text(card, tip[2], 13, C.Text, UI.Body, { Position = UDim2.fromOffset(18, 36), Size = UDim2.fromOffset(480, 24), TextWrapped = true })
			UI.text(card, ("%d/%d"):format(i, #TIPS), 11, C.Muted, UI.Mono, { Position = UDim2.fromOffset(470, 10), Size = UDim2.fromOffset(40, 14) })
			local scale = make("UIScale", { Scale = 0.85 }, card)
			UI.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			task.wait(6.5)
			UI.tween(scale, 0.2, { Scale = 0 })
			task.wait(0.25)
			card:Destroy()
		end
	end)
end

--============================ UPDATE ============================--
local function updateVitals()
	local v = refs.Vitals
	local function row(name, attr, max)
		local val = player:GetAttribute(attr) or max
		v[name].Set(val / max)
		v[name].Value.Text = tostring(math.floor(val))
	end
	row("Health", "Health", Config.Survival.MaxHealth)
	row("Hunger", "Hunger", Config.Survival.MaxHunger)
	row("Stamina", "Stamina", Config.Survival.MaxStamina)
	row("Energy", "Energy", Config.Survival.MaxEnergy)
	local hasLight = player:GetAttribute("HasFlashlight") or player:GetAttribute("HasNightVision")
	v.Battery.Row.Visible = hasLight == true
	if hasLight then
		row("Battery", "Battery", 100)
		v.Battery.Value.TextColor3 = if player:GetAttribute("FlashOn") then C.Battery else C.Muted
	end
	-- warnings
	local hunger = player:GetAttribute("Hunger") or 100
	v.Hunger.Value.TextColor3 = if hunger < 20 then C.Danger else C.Text
	local buffUntil = player:GetAttribute("BuffUntil") or 0
	local left = buffUntil - Workspace:GetServerTimeNow()
	refs.Buff.Visible = left > 0
	if left > 0 then
		refs.Buff.Text = ("SPEED BOOST %ds"):format(math.ceil(left))
	end
end

local function updatePhase()
	local ph = refs.Phase
	local phase = ReplicatedStorage:GetAttribute("Phase") or "Waiting"
	local night = ReplicatedStorage:GetAttribute("Night") or 0
	local now = Workspace:GetServerTimeNow()
	local ends = ReplicatedStorage:GetAttribute("PhaseEnds") or now
	local length = ReplicatedStorage:GetAttribute("PhaseLength") or 1
	local left = math.max(0, ends - now)
	local isNight = phase == "Night"
	if isNight then
		ph.Title.Text = "NIGHT " .. night
		ph.Title.TextColor3 = C.Danger
		ph.Clock.TextColor3 = C.Text
		ph.Fill.BackgroundColor3 = C.Danger
		ph.Sub.Text = string.upper(("%s · dawn in %s"):format(ReplicatedStorage:GetAttribute("LocustVariant") or "THE LOCUST", Util.FormatTime(left)))
	elseif phase == "Dusk" then
		ph.Title.Text = "DUSK"
		ph.Title.TextColor3 = Color3.fromHex("ff7a1a")
		ph.Fill.BackgroundColor3 = Color3.fromHex("ff7a1a")
		ph.Sub.Text = ("NIGHT %d IN %s"):format(night, Util.FormatTime(left))
		ph.Clock.TextColor3 = C.Orange
	elseif phase == "Results" then
		ph.Title.Text = "GAME OVER"
		ph.Title.TextColor3 = C.Danger
		ph.Sub.Text = ""
	else
		ph.Title.Text = "DAY " .. (night + 1)
		ph.Title.TextColor3 = C.Text
		ph.Fill.BackgroundColor3 = C.Accent
		ph.Sub.Text = if phase == "Day" then ("NIGHTFALL IN %s · %s"):format(Util.FormatTime(left), ReplicatedStorage:GetAttribute("ModeName") or "") else ""
		ph.Clock.TextColor3 = C.Text
	end
	ph.SetBar(1 - left / math.max(1, length))
	ph.Clock.Text = Util.FormatClock(ReplicatedStorage:GetAttribute("Clock") or 7)
end

local function updateSquad()
	local sq = refs.Squad
	local cam = Workspace.CurrentCamera
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local me = root and root.Position
	local list = {}
	for _, e in ClientState.Squad do
		if e.UserId ~= player.UserId then
			table.insert(list, e)
		end
	end
	if me then
		table.sort(list, function(a, b)
			local da = a.Pos and (a.Pos - me).Magnitude or math.huge
			local db = b.Pos and (b.Pos - me).Magnitude or math.huge
			return da < db
		end)
	end
	for i = 1, 6 do
		local e = list[i]
		local row = sq.Rows[i]
		if e and not row then
			row = make("Frame", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.2, Size = UDim2.fromOffset(230, 36), LayoutOrder = i }, sq.Box)
			UI.corner(row, 6)
			UI.stroke(row, Color3.new(1, 1, 1), 1, 0.93)
			local dot = make("Frame", { BackgroundColor3 = C.Good, Position = UDim2.fromOffset(10, 9), Size = UDim2.fromOffset(18, 18) }, row)
			UI.corner(dot)
			local name = UI.text(row, "", 12, C.Text, UI.Bold, { Position = UDim2.fromOffset(36, 3), Size = UDim2.fromOffset(110, 18), TextTruncate = Enum.TextTruncate.AtEnd })
			local _, hp = UI.track(row, C.Good, 1, { Position = UDim2.fromOffset(36, 23), Size = UDim2.fromOffset(150, 4) })
			local dist = UI.text(row, "", 10, C.Muted, UI.Mono, { Position = UDim2.fromOffset(140, 3), Size = UDim2.fromOffset(50, 18), TextXAlignment = Enum.TextXAlignment.Right })
			local arrow = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(210, 18), Size = UDim2.fromOffset(14, 14) }, row)
			local tip = make("Frame", { BackgroundColor3 = C.Text, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(3, 12) }, arrow)
			UI.corner(tip, 2)
			local head = make("Frame", { BackgroundColor3 = C.Text, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.15), Size = UDim2.fromOffset(7, 7), Rotation = 45 }, arrow)
			row = { Frame = row, Dot = dot, Name = name, Dist = dist, Arrow = arrow, HP = hp }
			sq.Rows[i] = row
		end
		if row then
			row.Frame.Visible = e ~= nil
			if e then
				row.Name.Text = e.Name
				local color = C.Good
				if e.Dead then
					color = C.Dim
				elseif e.Downed then
					color = if math.floor(os.clock() * 3) % 2 == 0 then C.Danger else Color3.fromHex("6a1010")
				elseif e.Infected then
					color = Color3.fromHex("7cff4f")
				elseif e.Hidden then
					color = C.Info
				elseif e.Health < 40 then
					color = C.Accent
				end
				row.Dot.BackgroundColor3 = color
				row.HP.Size = UDim2.fromScale(math.clamp((e.Health or 100) / Config.Survival.MaxHealth, 0, 1), 1)
				row.HP.BackgroundColor3 = if (e.Health or 100) < 40 then C.Danger else C.Good
				row.Name.TextColor3 = if e.Dead then C.Dim else C.Text
				if me and e.Pos then
					local d = (e.Pos - me).Magnitude
					row.Dist.Text = ("%dm"):format(math.floor(d / 3.5))
					local look = cam.CFrame.LookVector
					local dir = e.Pos - me
					local a1 = math.atan2(look.X, look.Z)
					local a2 = math.atan2(dir.X, dir.Z)
					row.Arrow.Rotation = math.deg(a1 - a2)
				else
					row.Dist.Text = ""
				end
			end
		end
	end
end

local pulse = 0
local function updateWarnings(dt)
	local inRun = ClientState.InRun()
	local d = player:GetAttribute("LocustDistance")
	local night = ReplicatedStorage:GetAttribute("Phase") == "Night"
	local proximity = if d and night and inRun then math.clamp(1 - (d - 10) / 70, 0, 1) else 0
	pulse += dt * (1 + proximity * 4)
	local beat = (math.sin(pulse * math.pi) + 1) / 2
	local dark = if night then 0.55 else 0.85
	local red = proximity * (0.55 + beat * 0.35)
	for _, e in refs.Vignette do
		e.BackgroundColor3 = Color3.new(0, 0, 0):Lerp(Color3.fromHex("7a0000"), math.clamp(red * 1.4, 0, 1))
		e.BackgroundTransparency = math.clamp(dark - red * 0.6, 0, 1)
	end
	refs.Hunted.Visible = inRun and player:GetAttribute("LocustHunting") == true and night
	-- noise meter: jumps to how loud you were, then decays
	local nz = refs.Noise
	local heard = player:GetAttribute("Noise") or 0
	local at = player:GetAttribute("NoiseAt") or 0
	local live = if Workspace:GetServerTimeNow() - at < 0.6 then heard else 0
	if player:GetAttribute("Sprinting") then
		live = math.max(live, 0.55)
	elseif player:GetAttribute("Crouching") then
		live = math.max(live * 0.5, 0.05)
	end
	nz.Level = math.max(live, nz.Level - dt * 0.6)
	local lit = math.floor(nz.Level * 14 + 0.5)
	for i, f in nz.Bars do
		local on = i <= lit
		f.Size = UDim2.fromOffset(8, 4 + (if on then nz.Shape[i] * 30 * (0.8 + 0.2 * beat) else 0))
		f.BackgroundTransparency = if on then 0 else 0.85
		f.BackgroundColor3 = if not on then C.Text elseif i > 10 then C.Danger else C.Accent
	end
	nz.State.Text = if nz.Level > 0.7 then "LOUD" elseif nz.Level > 0.3 then "AUDIBLE" else "QUIET"
	nz.State.TextColor3 = if nz.Level > 0.7 then C.Danger elseif nz.Level > 0.3 then C.Accent else C.Good
	refs.Crosshair.Visible = inRun and not ClientState.IsBusy() and not player:GetAttribute("Dead") and not player:GetAttribute("Hidden")
	-- overlays
	local downed = player:GetAttribute("Downed") == true and inRun
	refs.Downed.Frame.Visible = downed
	if downed then
		local left = math.max(0, (player:GetAttribute("BleedOut") or 0) - Workspace:GetServerTimeNow())
		refs.Downed.Sub.Text = ("BLEEDING OUT · %s"):format(Util.FormatTime(left))
		local mode = ReplicatedStorage:GetAttribute("Mode")
		refs.Downed.Hint.Text = if mode == "Solo" then "Use a Medkit from your hotbar to get back up" else "Crawl to safety · a teammate can revive you (hold E)"
	end
	refs.Dead.Frame.Visible = player:GetAttribute("Dead") == true and inRun
	refs.Hiding.Visible = player:GetAttribute("Hidden") == true and inRun
	refs.NV.Visible = player:GetAttribute("NightVision") == true and inRun
	-- cart
	local cartId = player:GetAttribute("CartId") or 0
	refs.Cart.Visible = cartId > 0 and inRun
	if cartId > 0 then
		local store = Workspace:FindFirstChild("Store")
		local carts = store and store:FindFirstChild("Carts")
		local used, size = 0, 0
		if carts then
			for _, c in carts:GetChildren() do
				if c:GetAttribute("CartId") == cartId then
					used, size = c:GetAttribute("Used") or 0, c:GetAttribute("Size") or 0
				end
			end
		end
		refs.CartText.Text = ("CART %d/%d   [G] let go   [X] basket"):format(used, size)
	end
end

local function updateWhere()
	local zone = ClientState.Where()
	refs.Objective.Where.Text = if zone and zone.Name ~= "" then zone.Name else ""
	refs.Objective.Text.Text = ClientState.Objective ~= "" and ClientState.Objective or "Explore the store"
	refs.Objective.Team.Text = ClientState.TeamObjective or ""
	refs.Objective.Team.TextColor3 = if string.find(ClientState.TeamObjective or "", "TEAM DONE", 1, true) then C.Good else C.Purple
end

function HUD.SetVisible(on: boolean)
	gui.Enabled = on
	overlayGui.Enabled = on
end

function HUD.Cue(kind: string, pos: Vector3?, extra: any)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local dist = if pos and root then (pos - root.Position).Magnitude else 0
	if kind == "Hurt" then
		HUD.Flash(math.clamp((extra or 10) / 40, 0.15, 0.55))
		Atmosphere.Shake(2.5, 0.3)
	elseif kind == "Shriek" or kind == "Roar" then
		if dist < 140 then
			Atmosphere.Shake(if kind == "Roar" then 2 else 1.2, 1.2)
			Atmosphere.FlickerFlashlight(2.5)
		end
	elseif kind == "LocustChase" and extra == player.UserId then
		Atmosphere.Shake(1.5, 0.6)
	elseif kind == "CameraAlert" then
		HUD.Toast("CAMERA: the Locust was spotted near a base!", "Danger")
	elseif kind == "Tutorial" then
		HUD.Tutorial()
	elseif kind == "LightSurge" and dist < 80 then
		Atmosphere.FlickerFlashlight(3)
	elseif kind == "StructureBreak" and dist < 50 then
		Atmosphere.Shake(1, 0.3)
	end
end

function HUD.Init()
	gui, root = UI.screen("MSL_HUD", 3)
	buildOverlays()
	buildVitals()
	buildPhase()
	buildObjective()
	buildSquad()
	buildToasts()
	buildBanner()
	buildHints()

	Net.Event("Notify").OnClientEvent:Connect(function(text, kind)
		if HUD.ShouldToast() then
			HUD.Toast(text, kind)
		end
	end)
	Net.Event("Banner").OnClientEvent:Connect(HUD.Banner)
	Net.Event("Event").OnClientEvent:Connect(HUD.Event)
	Net.Event("XP").OnClientEvent:Connect(HUD.XP)
	Net.Event("Unlocks").OnClientEvent:Connect(HUD.LevelUp)
	Net.Event("Results").OnClientEvent:Connect(HUD.Results)

	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		updateWarnings(dt)
		acc += dt
		if acc >= 0.15 then
			acc = 0
			updateVitals()
			updatePhase()
			updateSquad()
			updateWhere()
		end
	end)
	HUD.SetVisible(false)
end

return HUD
