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
	local box = make("Frame", { Name = "Vitals", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 22, 1, -22), Size = UDim2.fromOffset(260, 130) }, root)
	UI.list(box, 6).VerticalAlignment = Enum.VerticalAlignment.Bottom
	local rows = {}
	local defs = {
		{ "Health", C.Health, 1 },
		{ "Hunger", C.Hunger, 2 },
		{ "Stamina", C.Stamina, 3 },
		{ "Energy", C.Energy, 4 },
		{ "Battery", C.Battery, 5 },
	}
	for _, d in defs do
		local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(260, 20), LayoutOrder = d[3] }, box)
		glyph(row, d[1], d[2], 16).Position = UDim2.fromOffset(0, 2)
		local bar, set = UI.bar(row, d[2], { Position = UDim2.fromOffset(24, 5), Size = UDim2.fromOffset(186, 10) })
		local value = UI.text(row, "100", 13, C.Text, UI.Mono, { Position = UDim2.fromOffset(218, 0), Size = UDim2.fromOffset(42, 20) })
		rows[d[1]] = { Row = row, Set = set, Value = value, Bar = bar }
	end
	rows.Battery.Row.Visible = false
	refs.Vitals = rows
	local buff = UI.text(box, "", 12, C.Accent, UI.Caps, { Size = UDim2.fromOffset(260, 16), LayoutOrder = 0, Visible = false })
	refs.Buff = buff
end

local function buildPhase()
	local pill = UI.panel(root, { Name = "Phase", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(300, 64) }, 12)
	local title = UI.text(pill, "DAY 1", 26, C.Text, UI.Title, { Position = UDim2.fromOffset(16, 6), Size = UDim2.fromOffset(170, 30) })
	local clock = UI.text(pill, "07:00 AM", 18, C.Accent, UI.Mono, { Position = UDim2.fromOffset(170, 9), Size = UDim2.fromOffset(115, 24), TextXAlignment = Enum.TextXAlignment.Right })
	local sub = UI.text(pill, "", 11, C.Muted, UI.Caps, { Position = UDim2.fromOffset(16, 36), Size = UDim2.fromOffset(270, 14) })
	local bar, set, fill = UI.bar(pill, C.Accent, { Position = UDim2.fromOffset(16, 52), Size = UDim2.fromOffset(268, 4) })
	refs.Phase = { Pill = pill, Title = title, Clock = clock, Sub = sub, SetBar = set, Fill = fill }

	local event = UI.panel(root, { Name = "Event", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 86), Size = UDim2.fromOffset(360, 52), Visible = false }, 10)
	UI.stroke(event, C.Danger, 1.5)
	local en = UI.text(event, "", 16, C.Danger, UI.Title, { Position = UDim2.fromOffset(14, 6), Size = UDim2.fromOffset(330, 20) })
	local ed = UI.text(event, "", 12, C.Text, UI.Body, { Position = UDim2.fromOffset(14, 27), Size = UDim2.fromOffset(330, 18), TextTruncate = Enum.TextTruncate.AtEnd })
	refs.Event = { Frame = event, Name = en, Desc = ed }
end

local function buildObjective()
	local box = make("Frame", { Name = "Objective", BackgroundTransparency = 1, Position = UDim2.fromOffset(22, 18), Size = UDim2.fromOffset(340, 80) }, root)
	local bar = make("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Size = UDim2.fromOffset(3, 40) }, box)
	UI.text(box, "OBJECTIVE", 11, C.Accent, UI.Caps, { Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(300, 14) })
	local text = UI.text(box, "Explore the store", 16, C.Text, UI.Bold, { Position = UDim2.fromOffset(12, 16), Size = UDim2.fromOffset(320, 24), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	local loc = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 50), Size = UDim2.fromOffset(320, 20) }, box)
	glyph(loc, "Pin", C.Muted, 14).Position = UDim2.fromOffset(0, 3)
	local where = UI.text(loc, "", 12, C.Muted, UI.Caps, { Position = UDim2.fromOffset(20, 0), Size = UDim2.fromOffset(300, 20) })
	refs.Objective = { Text = text, Where = where, Bar = bar }
end

local function buildSquad()
	local box = make("Frame", { Name = "Squad", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 18), Size = UDim2.fromOffset(230, 240) }, root)
	UI.list(box, 4, false, Enum.HorizontalAlignment.Right)
	UI.text(box, "SURVIVORS", 11, C.Muted, UI.Caps, { Size = UDim2.fromOffset(230, 14), TextXAlignment = Enum.TextXAlignment.Right, LayoutOrder = 0 })
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
	UI.text(nv, "NV ● REC", 14, C.Good, UI.Mono, { Position = UDim2.new(1, -140, 1, -40), Size = UDim2.fromOffset(120, 20) })
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
function HUD.Results(summary)
	local panel = UI.panel(overlayRoot, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(560, 380), ZIndex = 20 }, 14)
	UI.stroke(panel, C.Danger, 2)
	UI.text(panel, "THE STORE CLAIMED YOU", 30, C.Danger, UI.Title, { Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 36), TextXAlignment = Enum.TextXAlignment.Center })
	UI.text(panel, ("%s · %d NIGHTS SURVIVED · %s"):format(Config.Modes[summary.Mode] and Config.Modes[summary.Mode].Name or "", summary.Nights, Util.FormatTime(summary.Duration or 0)), 13, C.Muted, UI.Caps, { Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center })
	local list = make("ScrollingFrame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(24, 92), Size = UDim2.new(1, -48, 0, 220), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4, BorderSizePixel = 0 }, panel)
	UI.list(list, 4)
	local header = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18) }, list)
	for i, h in { "SURVIVOR", "NIGHTS", "BUILT", "REVIVES", "DOWNS" } do
		UI.text(header, h, 11, C.Muted, UI.Caps, { Position = UDim2.fromScale(if i == 1 then 0 else 0.4 + (i - 2) * 0.15, 0), Size = UDim2.fromScale(if i == 1 then 0.4 else 0.15, 1) })
	end
	for _, p in summary.Players or {} do
		local row = make("Frame", { BackgroundColor3 = C.Panel2, BackgroundTransparency = 0.2, Size = UDim2.new(1, 0, 0, 28) }, list)
		UI.corner(row, 6)
		local vals = { p.Name, p.Nights or 0, p.Built or 0, p.Revives or 0, p.Downs or 0 }
		for i, v in vals do
			UI.text(row, tostring(v), 14, C.Text, if i == 1 then UI.Bold else UI.Mono, { Position = UDim2.new(if i == 1 then 0 else 0.4 + (i - 2) * 0.15, 8, 0, 0), Size = UDim2.fromScale(if i == 1 then 0.4 else 0.15, 1) })
		end
	end
	UI.text(panel, "A NEW STORE OPENS IN A MOMENT...", 13, C.Accent, UI.Caps, { Position = UDim2.new(0, 0, 1, -40), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center })
	local scale = make("UIScale", { Scale = 0.7 }, panel)
	UI.tween(scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(Config.Cycle.WipeResults - 1, function()
		panel:Destroy()
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
		ph.Fill.BackgroundColor3 = C.Danger
		ph.Sub.Text = ("%s · DAWN IN %s"):format(ReplicatedStorage:GetAttribute("LocustVariant") or "THE LOCUST", Util.FormatTime(left))
	elseif phase == "Dusk" then
		ph.Title.Text = "DUSK"
		ph.Title.TextColor3 = Color3.fromHex("ff7a1a")
		ph.Fill.BackgroundColor3 = Color3.fromHex("ff7a1a")
		ph.Sub.Text = ("NIGHT %d IN %s"):format(night, Util.FormatTime(left))
	elseif phase == "Results" then
		ph.Title.Text = "GAME OVER"
		ph.Title.TextColor3 = C.Danger
		ph.Sub.Text = ""
	else
		ph.Title.Text = "DAY " .. (night + 1)
		ph.Title.TextColor3 = C.Text
		ph.Fill.BackgroundColor3 = C.Accent
		ph.Sub.Text = if phase == "Day" then ("NIGHTFALL IN %s · %s"):format(Util.FormatTime(left), ReplicatedStorage:GetAttribute("ModeName") or "") else ""
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
			row = make("Frame", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.25, Size = UDim2.fromOffset(220, 26), LayoutOrder = i }, sq.Box)
			UI.corner(row, 6)
			local dot = make("Frame", { BackgroundColor3 = C.Good, Position = UDim2.fromOffset(8, 9), Size = UDim2.fromOffset(8, 8) }, row)
			UI.corner(dot)
			local name = UI.text(row, "", 13, C.Text, UI.Bold, { Position = UDim2.fromOffset(22, 0), Size = UDim2.fromOffset(120, 26), TextTruncate = Enum.TextTruncate.AtEnd })
			local dist = UI.text(row, "", 12, C.Muted, UI.Mono, { Position = UDim2.fromOffset(140, 0), Size = UDim2.fromOffset(50, 26), TextXAlignment = Enum.TextXAlignment.Right })
			local arrow = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(204, 13), Size = UDim2.fromOffset(14, 14) }, row)
			local tip = make("Frame", { BackgroundColor3 = C.Text, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(3, 12) }, arrow)
			UI.corner(tip, 2)
			local head = make("Frame", { BackgroundColor3 = C.Text, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.15), Size = UDim2.fromOffset(7, 7), Rotation = 45 }, arrow)
			row = { Frame = row, Dot = dot, Name = name, Dist = dist, Arrow = arrow }
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

	Net.Event("Notify").OnClientEvent:Connect(HUD.Toast)
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
