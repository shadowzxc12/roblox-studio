--[[
	UI: the visual language of MASSIVE STORE.
	Dark glass panels, store-sign yellow accents, condensed caps labels, thin outlines.
	Everything is built in code (no image uploads). Every ScreenGui gets a Root frame with a
	UIScale that follows the screen (designed for 1280x720) so it works on PC, phone, tablet, TV.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Items)
local Rarity = require(Shared.Rarity)

local UI = {}

UI.C = {
	Bg = Color3.fromHex("0a0b0e"),
	Panel = Color3.fromHex("121418"),
	Panel2 = Color3.fromHex("1a1d23"),
	Panel3 = Color3.fromHex("23272f"),
	Line = Color3.fromHex("2e333d"),
	Text = Color3.fromHex("eceef2"),
	Muted = Color3.fromHex("8a92a2"),
	Dim = Color3.fromHex("5a6170"),
	Accent = Color3.fromHex("ffc61a"),
	AccentDark = Color3.fromHex("b8860b"),
	Danger = Color3.fromHex("ff3b3b"),
	Good = Color3.fromHex("5fd36a"),
	Info = Color3.fromHex("5ab4ff"),
	Purple = Color3.fromHex("b76bff"),
	Health = Color3.fromHex("ff4757"),
	Hunger = Color3.fromHex("ff9f43"),
	Stamina = Color3.fromHex("f1f2f6"),
	Energy = Color3.fromHex("54a0ff"),
	Battery = Color3.fromHex("ffe14d"),
}
local C = UI.C

UI.Title = Font.fromEnum(Enum.Font.GothamBlack)
UI.Bold = Font.fromEnum(Enum.Font.GothamBold)
UI.Body = Font.fromEnum(Enum.Font.GothamMedium)
UI.Mono = Font.fromEnum(Enum.Font.RobotoMono)
UI.Caps = Font.fromEnum(Enum.Font.Michroma)

local player = Players.LocalPlayer

function UI.make(className: string, props: { [string]: any }?, parent: Instance?): any
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
local make = UI.make

function UI.corner(parent: Instance, px: number?)
	return make("UICorner", { CornerRadius = if px then UDim.new(0, px) else UDim.new(1, 0) }, parent)
end

function UI.stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?)
	return make("UIStroke", {
		Color = color or C.Line,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

function UI.pad(parent: Instance, px: number, py: number?)
	return make("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, py or px),
		PaddingBottom = UDim.new(0, py or px),
	}, parent)
end

function UI.list(parent: Instance, padding: number?, horizontal: boolean?, align: Enum.HorizontalAlignment?)
	return make("UIListLayout", {
		Padding = UDim.new(0, padding or 6),
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
	}, parent)
end

function UI.tween(obj: Instance, time: number, props, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

function UI.text(parent: Instance, str: string, size: number, color: Color3?, font: Font?, props): TextLabel
	local t = make("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = font or UI.Bold,
		Text = str,
		TextSize = size,
		TextColor3 = color or C.Text,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		ZIndex = 2,
	}, parent)
	if props then
		for k, v in props do
			(t :: any)[k] = v
		end
	end
	return t
end

-- glass panel: dark, slightly transparent, thin outline, subtle top highlight
function UI.panel(parent: Instance, props, radius: number?): Frame
	local f = make("Frame", {
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
	}, parent)
	UI.corner(f, radius or 10)
	UI.stroke(f, C.Line, 1, 0.1)
	make("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 205)),
		Rotation = 90,
	}, f)
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	return f
end

--[[
	button(parent, { Text, Size, Position, AnchorPoint, Style = "Primary"|"Ghost"|"Danger"|"Dark", TextSize, LayoutOrder, Icon })
]]
function UI.button(parent: Instance, opts): TextButton
	local style = opts.Style or "Dark"
	local bg, fg = C.Panel2, C.Text
	if style == "Primary" then
		bg, fg = C.Accent, Color3.fromHex("111111")
	elseif style == "Danger" then
		bg, fg = C.Danger, Color3.new(1, 1, 1)
	elseif style == "Good" then
		bg, fg = C.Good, Color3.fromHex("0b1a0d")
	elseif style == "Ghost" then
		bg = C.Panel
	end
	local b = make("TextButton", {
		Name = opts.Name or ((opts.Text or "Button") .. "Button"),
		AutoButtonColor = false,
		BackgroundColor3 = bg,
		BackgroundTransparency = if style == "Ghost" then 0.4 else 0,
		BorderSizePixel = 0,
		Size = opts.Size or UDim2.fromOffset(180, 40),
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		FontFace = opts.Font or UI.Bold,
		Text = opts.Text or "",
		TextSize = opts.TextSize or 16,
		TextColor3 = fg,
		LayoutOrder = opts.LayoutOrder or 0,
		Selectable = true,
		ZIndex = opts.ZIndex or 2,
	}, parent)
	UI.corner(b, opts.Radius or 8)
	local stroke = UI.stroke(b, if style == "Primary" then C.AccentDark else C.Line, 1, 0)
	local scale = make("UIScale", {}, b)
	b.MouseEnter:Connect(function()
		UI.tween(scale, 0.12, { Scale = 1.03 })
		UI.tween(stroke, 0.12, { Color = if style == "Primary" then Color3.new(1, 1, 1) else C.Accent })
		UI.Sound("Hover")
	end)
	b.MouseLeave:Connect(function()
		UI.tween(scale, 0.12, { Scale = 1 })
		UI.tween(stroke, 0.12, { Color = if style == "Primary" then C.AccentDark else C.Line })
	end)
	b.MouseButton1Down:Connect(function()
		UI.tween(scale, 0.06, { Scale = 0.97 })
	end)
	b.MouseButton1Up:Connect(function()
		UI.tween(scale, 0.1, { Scale = 1 })
	end)
	b.Activated:Connect(function()
		UI.Sound("Click")
	end)
	return b
end

-- horizontal bar. returns frame, setter(fraction, text?)
function UI.bar(parent: Instance, color: Color3, props)
	local back = make("Frame", {
		BackgroundColor3 = Color3.fromHex("0d0f13"),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(200, 10),
	}, parent)
	UI.corner(back, 4)
	local fillBack = make("Frame", {
		Name = "Lag",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, back)
	UI.corner(fillBack, 4)
	local fill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	}, back)
	UI.corner(fill, 4)
	make("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)),
		Rotation = 90,
	}, fill)
	if props then
		for k, v in props do
			(back :: any)[k] = v
		end
	end
	local last = 1
	local function set(f: number)
		f = math.clamp(f, 0, 1)
		if math.abs(f - last) < 0.001 then
			return
		end
		UI.tween(fill, 0.18, { Size = UDim2.fromScale(f, 1) })
		if f < last then
			task.delay(0.35, function()
				UI.tween(fillBack, 0.5, { Size = UDim2.fromScale(f, 1) })
			end)
		else
			fillBack.Size = UDim2.fromScale(f, 1)
		end
		last = f
	end
	return back, set, fill
end

-- a ScreenGui with a scaled Root frame
local guis = {}
function UI.screen(name: string, order: number?, ignoreInset: boolean?): (ScreenGui, Frame)
	local gui = make("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = if ignoreInset == nil then true else ignoreInset,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = order or 1,
	}, player:WaitForChild("PlayerGui"))
	local root = make("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1280, 720),
	}, gui)
	local scale = make("UIScale", {}, root)
	table.insert(guis, { Root = root, Scale = scale })
	UI.rescale()
	return gui, root
end

function UI.rescale()
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	local s = math.min(vp.X / 1280, vp.Y / 720)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		s = math.max(s, 0.62)
	end
	s = math.clamp(s, 0.5, 1.6)
	for _, g in guis do
		g.Scale.Scale = s
		-- root fills the screen in design units
		g.Root.Size = UDim2.fromOffset(vp.X / s, vp.Y / s)
	end
	UI.ScaleFactor = s
end

function UI.Init()
	local function hook()
		local cam = Workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(UI.rescale)
		end
		UI.rescale()
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hook)
	hook()
end

function UI.IsTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function UI.IsGamepad(): boolean
	return UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
end

-- set by Audio
UI.Sound = function(_name: string) end

--============================ ITEM ICONS ============================--
-- draws a small flat icon of an item from its procedural shape
function UI.ItemIcon(parent: Instance, itemId: string, size: number?): Frame
	local s = size or 48
	local item = Items.Get(itemId)
	local holder = make("Frame", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(s, s),
		ZIndex = 3,
	}, parent)
	if not item then
		return holder
	end
	local color = Color3.fromHex(item.Color)
	local accent = Color3.fromHex(item.Accent or item.Color)
	local function shape(px, py, w, h, c, radius, rot, z)
		local f = make("Frame", {
			BackgroundColor3 = c,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(px, py),
			Size = UDim2.fromScale(w, h),
			Rotation = rot or 0,
			ZIndex = z or 4,
		}, holder)
		if radius then
			UI.corner(f, radius)
		end
		return f
	end
	local sh = item.Shape
	local dx, dy = item.Size[1], math.max(item.Size[2], item.Size[3] * 0.6)
	local m = math.max(dx, dy)
	local w, h = math.clamp(dx / m * 0.72, 0.22, 0.8), math.clamp(dy / m * 0.72, 0.18, 0.8)
	if sh == "Round" then
		local b = shape(0.5, 0.55, 0.62, 0.62, color, nil)
		UI.corner(b)
		shape(0.58, 0.24, 0.14, 0.2, accent, 3, 25)
	elseif sh == "Can" or sh == "Cell" then
		local b = shape(0.5, 0.52, 0.42, 0.7, color, 6)
		shape(0.5, 0.52, 0.44, 0.24, accent, 2)
		if sh == "Cell" then
			shape(0.5, 0.14, 0.16, 0.08, Color3.fromHex("cfd8dc"), 2)
		end
		b.ZIndex = 4
	elseif sh == "Bottle" then
		shape(0.5, 0.56, 0.36, 0.64, color, 7)
		shape(0.5, 0.2, 0.18, 0.16, accent, 3)
		shape(0.5, 0.58, 0.38, 0.18, accent, 2)
	elseif sh == "Tool" then
		local tool = item.Tool
		if tool == "Flashlight" then
			shape(0.42, 0.5, 0.56, 0.2, color, 4, -30)
			shape(0.72, 0.33, 0.2, 0.28, color, 4, -30)
			shape(0.78, 0.29, 0.1, 0.22, accent, 3, -30)
		elseif tool == "Hammer" then
			shape(0.5, 0.56, 0.12, 0.66, color, 3, 30)
			shape(0.62, 0.3, 0.44, 0.16, accent, 3, 30)
		elseif tool == "Crowbar" then
			shape(0.5, 0.5, 0.1, 0.8, color, 3, 35)
			shape(0.3, 0.2, 0.24, 0.08, color, 3, -20)
		else
			shape(0.5, 0.55, 0.14, 0.7, color, 3, 30)
			shape(0.68, 0.24, 0.16, 0.16, accent, 8, 30)
		end
	elseif sh == "Kit" then
		shape(0.5, 0.55, 0.72, 0.5, color, 6)
		shape(0.5, 0.55, 0.32, 0.1, accent, 2)
		shape(0.5, 0.55, 0.1, 0.32, accent, 2)
		shape(0.5, 0.27, 0.26, 0.1, color, 2)
	elseif sh == "Jug" then
		shape(0.5, 0.56, 0.56, 0.66, color, 6)
		shape(0.66, 0.2, 0.14, 0.14, accent, 3)
		shape(0.42, 0.26, 0.26, 0.08, accent, 2)
	elseif sh == "Card" then
		shape(0.5, 0.5, 0.74, 0.5, color, 5, -12)
		shape(0.5, 0.42, 0.74, 0.1, accent, 0, -12)
	elseif sh == "Plank" then
		shape(0.5, 0.42, 0.8, 0.16, color, 3, -15)
		shape(0.5, 0.62, 0.8, 0.16, accent, 3, -8)
	elseif sh == "Sheet" then
		shape(0.5, 0.55, 0.74, 0.46, color, 4, -10)
		shape(0.5, 0.55, 0.6, 0.06, accent, 2, -10)
	else
		shape(0.5, 0.55, w, h, color, 5)
		shape(0.5, 0.5, w * 0.98, h * 0.26, accent, 2)
	end
	return holder
end

function UI.RarityColor(r: string): Color3
	local info = Rarity.Info[r]
	return Color3.fromHex(if info then info.Color else "c8ccd4")
end

-- simple tooltip/key cap like [E]
function UI.keycap(parent: Instance, key: string, size: number?): Frame
	local s = size or 22
	local f = make("Frame", {
		BackgroundColor3 = C.Text,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(math.max(s, #key * s * 0.45 + 10), s),
		ZIndex = 5,
	}, parent)
	UI.corner(f, 5)
	UI.text(f, key, s * 0.6, Color3.fromHex("111111"), UI.Title, { TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
	return f
end

function UI.KeyName(code: Enum.KeyCode): string
	local name = code.Name
	local map = { ButtonX = "X", ButtonY = "Y", ButtonA = "A", ButtonB = "B", LeftShift = "Shift", LeftControl = "Ctrl" }
	return map[name] or name
end

UI.Gui = GuiService
return UI
