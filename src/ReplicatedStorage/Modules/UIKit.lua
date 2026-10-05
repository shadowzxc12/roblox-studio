--[[
	UIKit: shared building blocks for all client UI (cartoon "stud" style).

	Responsive layout: every screen has a "Root" frame with a UIScale that follows the screen size
	(designed for 1280x720). Things are anchored with Scale (corners/centre of the screen) and the
	UIScale makes them fit PC, phone, tablet and TV. Buttons are big enough for touch, and are
	Selectable so console players can use a gamepad.
]]

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Sounds = require(script.Parent.Sounds)
local Icons = require(script.Parent.Icons)

local UIKit = {}

UIKit.Colors = {
	Ink = Color3.fromHex("1b1530"),
	White = Color3.new(1, 1, 1),
	Panel = Color3.fromHex("23263a"),
	PanelLight = Color3.fromHex("343a5c"),
	Orange = Color3.fromHex("ffbb22"),
	OrangeStripe = Color3.fromHex("ff9d00"),
	Green = Color3.fromHex("6aea4f"),
	GreenDark = Color3.fromHex("1fa324"),
	Blue = Color3.fromHex("3a96ff"),
	BlueDark = Color3.fromHex("1b5fd1"),
	Red = Color3.fromHex("ff4040"),
	RedDark = Color3.fromHex("c41e1e"),
	Purple = Color3.fromHex("9b4dff"),
	PurpleDark = Color3.fromHex("5b2bb8"),
	Gold = Color3.fromHex("ffd23f"),
	Pink = Color3.fromHex("ff7ab6"),
	Grey = Color3.fromHex("8a90a8"),
	GreyDark = Color3.fromHex("5a6078"),
	Muted = Color3.fromHex("c9cde0"),
}
local C = UIKit.Colors

UIKit.Font = Font.fromEnum(Enum.Font.FredokaOne)
UIKit.BodyFont = Font.fromEnum(Enum.Font.GothamBold)

local DESIGN = Vector2.new(1280, 720)

function UIKit.make(className: string, props: { [string]: any }?, parent: Instance?): any
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
local make = UIKit.make

function UIKit.corner(parent: Instance, px: number?)
	return make("UICorner", { CornerRadius = if px then UDim.new(0, px) else UDim.new(1, 0) }, parent)
end

function UIKit.stroke(parent: Instance, thickness: number, color: Color3?, contextual: boolean?)
	return make("UIStroke", {
		Thickness = thickness,
		Color = color or C.Ink,
		ApplyStrokeMode = if contextual then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border,
	}, parent)
end

function UIKit.gradient(parent: Instance, a: Color3, b: Color3, rotation: number?)
	return make("UIGradient", { Color = ColorSequence.new(a, b), Rotation = rotation or 90 }, parent)
end

function UIKit.tween(obj: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- Cartoon text: white letters with a thick ink outline.
function UIKit.text(parent: Instance, str: string, size: number, color: Color3?, props: { [string]: any }?): TextLabel
	local t = make("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = UIKit.Font,
		Text = str,
		TextSize = size,
		TextColor3 = color or C.White,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	}, parent)
	make("UIStroke", { Thickness = math.max(1.5, size / 12), Color = C.Ink }, t)
	if props then
		for k, v in props do
			(t :: any)[k] = v
		end
	end
	return t
end

-- Plain body text (descriptions).
function UIKit.body(parent: Instance, str: string, size: number, color: Color3?, props: { [string]: any }?): TextLabel
	local t = make("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = UIKit.BodyFont,
		Text = str,
		TextSize = size,
		TextColor3 = color or C.Muted,
		TextWrapped = true,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	}, parent)
	if props then
		for k, v in props do
			(t :: any)[k] = v
		end
	end
	return t
end

function UIKit.icon(parent: Instance, name: string, size: number)
	return Icons.Create(parent, name, size)
end

-- Hover grows, press squishes, release bounces back, with sounds. Works with mouse, touch and gamepad.
function UIKit.juicy(btn: GuiButton, hoverScale: number?): UIScale
	local sc = make("UIScale", nil, btn)
	local target = hoverScale or 1.06
	local function to(v: number, time: number?)
		TweenService:Create(sc, TweenInfo.new(time or 0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = v }):Play()
	end
	local function hover()
		to(target)
		Sounds.Play("Hover")
	end
	btn.MouseEnter:Connect(hover)
	btn.SelectionGained:Connect(hover)
	btn.MouseLeave:Connect(function()
		to(1)
	end)
	btn.SelectionLost:Connect(function()
		to(1)
	end)
	btn.MouseButton1Down:Connect(function()
		to(0.9, 0.08)
	end)
	btn.MouseButton1Up:Connect(function()
		to(target)
	end)
	btn.Activated:Connect(function()
		Sounds.Play("Click")
		to(0.92, 0.06)
		task.delay(0.07, function()
			to(1)
		end)
	end)
	return sc
end

-- Light streak that sweeps over a button now and then.
function UIKit.shine(parent: GuiObject, radius: number?)
	local s = make("Frame", { Name = "Shine", BackgroundColor3 = C.White, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, parent)
	if radius then
		UIKit.corner(s, radius)
	end
	local g = make("UIGradient", {
		Rotation = 20,
		Offset = Vector2.new(-1, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.5),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, s)
	task.spawn(function()
		while s.Parent do
			task.wait(2 + math.random() * 3)
			if s.Parent and s:IsDescendantOf(game) then
				g.Offset = Vector2.new(-1, 0)
				TweenService:Create(g, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Offset = Vector2.new(1, 0) }):Play()
			end
		end
	end)
end

--[[
	Big cartoon button.
	opts = { Text, Size (UDim2), Position, AnchorPoint, Color, ColorDark, TextSize, Icon, IconSize, Radius, LayoutOrder, Shine }
	Returns the button and its holder (holder is what you position / put in layouts).
]]
function UIKit.button(parent: Instance, opts): (TextButton, Frame)
	local holder = make("Frame", {
		Name = (opts.Name or opts.Text or "Button") .. "Holder",
		BackgroundTransparency = 1,
		Size = opts.Size or UDim2.fromOffset(200, 56),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		LayoutOrder = opts.LayoutOrder or 0,
		ZIndex = opts.ZIndex or 1,
	}, parent)
	local radius = opts.Radius or 12
	local btn = make("TextButton", {
		Name = opts.Name or "Button",
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = C.White,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Selectable = true,
	}, holder)
	UIKit.gradient(btn, opts.Color or C.Green, opts.ColorDark or C.GreenDark)
	UIKit.corner(btn, radius)
	UIKit.stroke(btn, opts.StrokeThickness or 3)
	if opts.Shine ~= false then
		UIKit.shine(btn, radius)
	end
	-- content row: optional icon + text
	local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, btn)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	if opts.Icon then
		local iconSize = opts.IconSize or 36
		local iconHolder = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(iconSize, iconSize), LayoutOrder = 1 }, row)
		UIKit.icon(iconHolder, opts.Icon, iconSize)
	end
	if opts.Text and opts.Text ~= "" then
		local t = UIKit.text(row, opts.Text, opts.TextSize or 24)
		t.AutomaticSize = Enum.AutomaticSize.X
		t.Size = UDim2.fromScale(0, 1)
		t.LayoutOrder = 2
		t.Name = "Label"
	end
	UIKit.juicy(btn, opts.HoverScale)
	return btn, holder
end

-- Lego-like stud dots (static, cheap) to decorate panel backgrounds.
function UIKit.studs(parent: GuiObject, w: number, h: number, pitch: number?, alpha: number?)
	pitch = pitch or 28
	local clip = make("Frame", { Name = "Studs", BackgroundTransparency = 1, ClipsDescendants = true, Size = UDim2.fromScale(1, 1), ZIndex = 0 }, parent)
	local size = math.floor(pitch * 0.45)
	for y = 0, math.ceil(h / pitch) do
		for x = 0, math.ceil(w / pitch) do
			local d = make("Frame", {
				BackgroundColor3 = C.White,
				BackgroundTransparency = alpha or 0.9,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(x * pitch + (y % 2) * pitch / 2, y * pitch + 4),
				Size = UDim2.fromOffset(size, size),
			}, clip)
			UIKit.corner(d)
		end
	end
	return clip
end

--[[
	A ScreenGui with a responsive Root frame.
	Returns gui, root. Put everything inside root and position it with Scale anchors.
]]
function UIKit.screen(name: string, displayOrder: number, parent: Instance): (ScreenGui, Frame)
	local gui = make("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder,
		Enabled = true,
	}, parent)
	local root = make("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	}, gui)
	local scale = make("UIScale", nil, root)
	local function update()
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		local vp = cam.ViewportSize
		local s = math.clamp(math.min(vp.X / DESIGN.X, vp.Y / DESIGN.Y), 0.5, 1.5)
		-- phones are small: make things a bit bigger relative to the screen
		if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
			s = math.clamp(s * 1.12, 0.5, 1.5)
		end
		scale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	update()
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return gui, root
end

--[[
	Cartoon window: dark body with studs, orange striped header, title, round red X.
	opts = { Title, Size, Icon, HeaderColor, HeaderColor2 }
	Returns { Frame = CanvasGroup (fade it), Body = Frame, Close = TextButton }
]]
function UIKit.window(parent: Instance, opts)
	local size = opts.Size or Vector2.new(640, 460)
	local frame = make("CanvasGroup", {
		Name = opts.Name or "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		GroupTransparency = 0,
	}, parent)
	UIKit.corner(frame, 18)
	-- background lives in its own frame: a UIGradient on a CanvasGroup would tint everything inside
	local bg = make("Frame", { Name = "Background", BackgroundColor3 = C.White, Size = UDim2.fromScale(1, 1), ZIndex = 0 }, frame)
	UIKit.gradient(bg, C.PanelLight, C.Panel)
	UIKit.corner(bg, 18)
	UIKit.studs(frame, size.X, size.Y, 30, 0.92).ZIndex = 1
	-- outline drawn by a frame on top (UIStroke on a CanvasGroup is clipped)
	local border = make("Frame", { Name = "Border", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4), ZIndex = 10 }, frame)
	UIKit.corner(border, 14)
	UIKit.stroke(border, 4)

	local header = make("Frame", { Name = "Header", BackgroundColor3 = C.White, Size = UDim2.new(1, 0, 0, 66), ZIndex = 2 }, frame)
	local a, b = opts.HeaderColor or C.Orange, opts.HeaderColor2 or C.OrangeStripe
	local kps = {}
	local count = 10
	for i = 0, count - 1 do
		local col = if i % 2 == 0 then a else b
		table.insert(kps, ColorSequenceKeypoint.new(i / count, col))
		table.insert(kps, ColorSequenceKeypoint.new(if i == count - 1 then 1 else (i + 1) / count - 0.001, col))
	end
	make("UIGradient", { Color = ColorSequence.new(kps), Rotation = 30 }, header)
	UIKit.corner(header, 18)
	make("Frame", { BackgroundColor3 = C.Ink, BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, -4), Size = UDim2.new(1, 0, 0, 4), ZIndex = 3 }, header)

	if opts.Icon then
		local ih = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 5), Size = UDim2.fromOffset(54, 54), ZIndex = 4 }, header)
		UIKit.icon(ih, opts.Icon, 50)
	end
	local title = UIKit.text(header, opts.Title or "", 36, C.White, {
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(if opts.Icon then 76 else 22, 0),
		Size = UDim2.new(1, -150, 1, -4),
		ZIndex = 4,
	})
	title.Name = "Title"

	local close = UIKit.button(header, {
		Name = "Close",
		Text = "X",
		TextSize = 28,
		Size = UDim2.fromOffset(48, 48),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, -2),
		Color = C.Red,
		ColorDark = C.RedDark,
		Shine = false,
		HoverScale = 1.12,
	})
	close.Parent.ZIndex = 5

	local body = make("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 80),
		Size = UDim2.new(1, -36, 1, -96),
		ZIndex = 2,
	}, frame)
	return { Frame = frame, Body = body, Close = close, Title = title }
end

-- Fade + pop a CanvasGroup in / out.
function UIKit.showWindow(win: CanvasGroup)
	local sc = win:FindFirstChild("PopScale") or make("UIScale", { Name = "PopScale" }, win)
	win.Visible = true
	win.GroupTransparency = 1
	sc.Scale = 0.85
	UIKit.tween(win, 0.2, { GroupTransparency = 0 })
	UIKit.tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	Sounds.Play("Whoosh")
	-- console: put the gamepad cursor in the window
	if UserInputService.GamepadEnabled then
		for _, d in win:GetDescendants() do
			if d:IsA("GuiButton") and d.Selectable and d.Name ~= "Close" then
				GuiService.SelectedObject = d
				break
			end
		end
	end
end

function UIKit.hideWindow(win: CanvasGroup)
	local sc = win:FindFirstChild("PopScale") or make("UIScale", { Name = "PopScale" }, win)
	UIKit.tween(win, 0.18, { GroupTransparency = 1 })
	local t = UIKit.tween(sc, 0.18, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	t.Completed:Connect(function()
		if win.GroupTransparency > 0.9 then
			win.Visible = false
		end
	end)
end

-- Small pill showing an icon + number (coins, XP ...). Returns the TextLabel to update.
function UIKit.pill(parent: Instance, icon: string, color: Color3, props: { [string]: any }?): TextLabel
	local p = make("Frame", { BackgroundColor3 = color, Size = UDim2.fromOffset(150, 44) }, parent)
	UIKit.corner(p)
	UIKit.stroke(p, 3)
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	local ih = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(-6, -4), Size = UDim2.fromOffset(52, 52), ZIndex = 3 }, p)
	UIKit.icon(ih, icon, 50)
	local t = UIKit.text(p, "0", 22, C.White, {
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(52, 0),
		Size = UDim2.new(1, -60, 1, 0),
	})
	return t
end

return UIKit
