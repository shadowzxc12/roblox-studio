--[[
	PanelsController: the pop-up windows used from both the menu and the match HUD.
	  SettingsUI - Music / Sound Effects / Show Effects / Camera Shake (ON/OFF, saved on the server)
	  ShopUI     - cosmetic shop (buy/equip through the server, which checks coins and ownership)
	  CreditsUI  - credits
	PanelsController.Open("Settings" | "Shop" | "Credits")
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIKit = require(ReplicatedStorage.Modules.UIKit)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local Config = require(ReplicatedStorage.Modules.Config)
local Cosmetics = require(ReplicatedStorage.Modules.Cosmetics)
local Util = require(ReplicatedStorage.Modules.Util)
local ClientState = require(script.Parent.ClientState)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local C = UIKit.Colors
local make = UIKit.make

local PanelsController = {}
local windows: { [string]: any } = {}
local openName: string? = nil
local dim: TextButton
local toast: (string) -> ()

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

function PanelsController.Close()
	if openName and windows[openName] then
		UIKit.hideWindow(windows[openName].Frame)
	end
	openName = nil
	UIKit.tween(dim, 0.2, { BackgroundTransparency = 1 }).Completed:Connect(function()
		if not openName then
			dim.Visible = false
		end
	end)
end

function PanelsController.Open(name: string)
	if openName == name then
		return
	end
	if openName and windows[openName] then
		UIKit.hideWindow(windows[openName].Frame)
	end
	local w = windows[name]
	if not w then
		return
	end
	openName = name
	if w.Refresh then
		w.Refresh()
	end
	dim.Visible = true
	UIKit.tween(dim, 0.2, { BackgroundTransparency = 0.45 })
	UIKit.showWindow(w.Frame)
end

function PanelsController.IsOpen(): boolean
	return openName ~= nil
end

--================================ SETTINGS ================================--
local function buildSettings(root)
	local w = UIKit.window(root, { Name = "SettingsWindow", Title = "SETTINGS", Icon = "gear", Size = Vector2.new(540, 430) })
	w.Frame.Visible = false
	make("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, w.Body)
	local toggles = {}
	for i, key in Config.SettingKeys do
		local row = make("Frame", { BackgroundColor3 = C.Panel, Size = UDim2.new(1, 0, 0, 68), LayoutOrder = i, ZIndex = 2 }, w.Body)
		UIKit.corner(row, 12)
		UIKit.stroke(row, 3)
		UIKit.text(row, Config.SettingLabels[key], 26, C.White, {
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(18, 0),
			Size = UDim2.new(1, -170, 1, 0),
		})
		local btn = UIKit.button(row, {
			Name = key,
			Text = "ON",
			TextSize = 24,
			Size = UDim2.fromOffset(120, 48),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Shine = false,
		})
		toggles[key] = btn
		btn.Activated:Connect(function()
			ClientState.SetSetting(key, not ClientState.Settings[key])
		end)
	end
	local function refresh()
		for key, btn in toggles do
			local on = ClientState.Settings[key]
			local label = btn:FindFirstChild("Label", true)
			if label then
				label.Text = if on then "ON" else "OFF"
			end
			local g = btn:FindFirstChildOfClass("UIGradient")
			if g then
				g.Color = if on then ColorSequence.new(C.Green, C.GreenDark) else ColorSequence.new(C.Grey, C.GreyDark)
			end
		end
	end
	ClientState.SettingsChanged.Event:Connect(refresh)
	refresh()
	w.Close.Activated:Connect(PanelsController.Close)
	w.Refresh = refresh
	return w
end

--================================ SHOP ================================--
local function buildShop(root)
	local w = UIKit.window(root, { Name = "ShopWindow", Title = "SHOP", Icon = "cart", Size = Vector2.new(820, 540) })
	w.Frame.Visible = false

	local coinsLabel = UIKit.pill(w.Frame, "coin", C.Gold, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -78, 0, 11),
		ZIndex = 6,
	})
	coinsLabel.Parent.ZIndex = 6

	-- category tabs
	local tabs = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 50), ZIndex = 2 }, w.Body)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, tabs)
	local grid = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 1, -62),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = C.Orange,
		ZIndex = 2,
	}, w.Body)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(180, 200), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4) }, grid)

	local category = Cosmetics.Categories[1]
	local tabButtons = {}

	local function render()
		for _, c in grid:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		local data = ClientState.Data
		coinsLabel.Text = Util.FormatNumber(data and data.Coins or 0)
		for cat, b in tabButtons do
			local g = b:FindFirstChildOfClass("UIGradient")
			if g then
				g.Color = if cat == category then ColorSequence.new(C.Blue, C.BlueDark) else ColorSequence.new(C.Grey, C.GreyDark)
			end
		end
		local order = 0
		for _, item in Cosmetics.Items do
			if item.Category == category then
				order += 1
				local owned = data and data.OwnedCosmetics and data.OwnedCosmetics[item.Id]
				local equipped = data and data.Equipped and data.Equipped[item.Category] == item.Id
				local card = make("Frame", { BackgroundColor3 = C.White, LayoutOrder = order, ZIndex = 2 }, grid)
				UIKit.gradient(card, C.PanelLight, C.Panel)
				UIKit.corner(card, 14)
				UIKit.stroke(card, 3, if equipped then C.Gold else C.Ink)
				-- preview swatch: a glowing stud in the item's colour
				local sw = make("Frame", {
					BackgroundColor3 = item.Color,
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 14),
					Size = UDim2.fromOffset(70, 70),
					ZIndex = 3,
				}, card)
				UIKit.corner(sw)
				UIKit.stroke(sw, 3)
				if item.Color2 then
					UIKit.gradient(sw, item.Color, item.Color2, 45)
				end
				UIKit.text(card, item.Name, 20, C.White, { Position = UDim2.fromOffset(0, 92), Size = UDim2.new(1, 0, 0, 26) })
				local label, color, dark
				if equipped then
					label, color, dark = "EQUIPPED", C.Gold, C.OrangeStripe
				elseif owned then
					label, color, dark = "EQUIP", C.Blue, C.BlueDark
				else
					label, color, dark = Util.FormatNumber(item.Price), C.Green, C.GreenDark
				end
				local btn = UIKit.button(card, {
					Text = label,
					TextSize = 20,
					Icon = if not owned then "coin" else nil,
					IconSize = 28,
					Size = UDim2.fromOffset(150, 46),
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -14),
					Color = color,
					ColorDark = dark,
				})
				btn.Activated:Connect(function()
					local request
					if equipped then
						request = { Action = "Unequip", Category = item.Category }
					elseif owned then
						request = { Action = "Equip", Id = item.Id }
					else
						request = { Action = "Buy", Id = item.Id }
					end
					local ok, result = pcall(function()
						return Remotes.RequestShop:InvokeServer(request)
					end)
					if ok and type(result) == "table" then
						toast(result.Message or "")
						if result.Ok and request.Action == "Buy" then
							Sounds.Play("Coin")
						end
					end
				end)
			end
		end
	end

	for i, cat in Cosmetics.Categories do
		local b = UIKit.button(tabs, {
			Text = Cosmetics.CategoryNames[cat],
			TextSize = 20,
			Size = UDim2.fromOffset(170, 46),
			LayoutOrder = i,
			Color = C.Grey,
			ColorDark = C.GreyDark,
			Shine = false,
		})
		tabButtons[cat] = b
		b.Activated:Connect(function()
			category = cat
			render()
		end)
	end

	ClientState.DataChanged.Event:Connect(function()
		if openName == "Shop" then
			render()
		end
	end)
	w.Close.Activated:Connect(PanelsController.Close)
	w.Refresh = render
	return w
end

--================================ CREDITS ================================--
local function buildCredits(root)
	local w = UIKit.window(root, { Name = "CreditsWindow", Title = "CREDITS", Icon = "book", Size = Vector2.new(540, 400) })
	w.Frame.Visible = false
	UIKit.body(w.Body, table.concat({
		Config.GameName .. "  v" .. Config.Version,
		"",
		"Game design & building: you!",
		"Systems: matchmaking, rounds, tagging, data, shop",
		"Made with Roblox Studio + Rojo",
		"",
		"Thanks for playing! Be kind, have fun and RUN!",
	}, "\n"), 22, C.White, { TextYAlignment = Enum.TextYAlignment.Top })
	w.Close.Activated:Connect(PanelsController.Close)
	return w
end

function PanelsController.Init(showToast: (string) -> ())
	toast = showToast
	-- the dim layer sits in its own ScreenGui just below the windows
	local gui = make("ScreenGui", { Name = "PanelsDim", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 50 }, playerGui)
	dim = make("TextButton", {
		Name = "Dim",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Selectable = false,
	}, gui)
	dim.Activated:Connect(PanelsController.Close)

	local _, settingsRoot = UIKit.screen("SettingsUI", 51, playerGui)
	local _, shopRoot = UIKit.screen("ShopUI", 51, playerGui)
	local _, creditsRoot = UIKit.screen("CreditsUI", 51, playerGui)
	windows.Settings = buildSettings(settingsRoot)
	windows.Shop = buildShop(shopRoot)
	windows.Credits = buildCredits(creditsRoot)

	-- gamepad: Select opens settings, B closes any window
	ContextActionService:BindAction("ToggleSettings", function(_, state)
		if state == Enum.UserInputState.Begin then
			if openName then
				PanelsController.Close()
			else
				PanelsController.Open("Settings")
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.ButtonSelect)
	ContextActionService:BindAction("CloseWindow", function(_, state)
		if state == Enum.UserInputState.Begin and openName then
			PanelsController.Close()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.ButtonB)
end

return PanelsController
