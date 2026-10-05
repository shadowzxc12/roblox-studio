--[[
	UIController: everything you see during a match.
	  GameUI        - mode name + round timer (top centre), team counts, your role badge, feed,
	                  small MENU / SHOP / SETTINGS buttons, big centre messages, countdown
	  ResultsUI     - big animated results screen with stats, coins and XP + PLAY AGAIN / MAIN MENU
	  Notifications - small toasts at the bottom
	Timers are calculated locally from RoundEndsAt (server time), so no per-second remotes are needed.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIKit = require(ReplicatedStorage.Modules.UIKit)
local Sounds = require(ReplicatedStorage.Modules.Sounds)
local Config = require(ReplicatedStorage.Modules.Config)
local Util = require(ReplicatedStorage.Modules.Util)
local ClientState = require(script.Parent.ClientState)
local CameraController = require(script.Parent.CameraController)
local PanelsController = require(script.Parent.PanelsController)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local C = UIKit.Colors
local make = UIKit.make
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UIController = {}

local gameGui: ScreenGui
local modeLabel: TextLabel
local timerLabel: TextLabel
local subLabel: TextLabel
local countsLabel: TextLabel
local roleBadge: Frame
local roleLabel: TextLabel
local feed: Frame
local bigLayer: Frame
local flash: Frame
local coinsLabel: TextLabel
local resultsGui: ScreenGui
local resultsRoot: Frame
local toastRoot: Frame
local currentBig: TextLabel? = nil
local hudVisible = false

local function modeCfg()
	return Config.Modes[ReplicatedStorage:GetAttribute("RoundMode") or ReplicatedStorage:GetAttribute("GameMode") or "Normal"] or Config.Modes.Normal
end

--================================ TOASTS ================================--
function UIController.Toast(text: string)
	if not toastRoot or text == "" then
		return
	end
	local t = make("Frame", { BackgroundColor3 = C.Panel, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 48), ZIndex = 2 }, toastRoot)
	UIKit.corner(t, 14)
	UIKit.stroke(t, 3)
	make("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }, t)
	local l = UIKit.text(t, text, 22, C.White, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1) })
	local sc = make("UIScale", { Scale = 0.6 }, t)
	UIKit.tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(3, function()
		UIKit.tween(t, 0.3, { BackgroundTransparency = 1 })
		UIKit.tween(l, 0.3, { TextTransparency = 1 })
		UIKit.tween(sc, 0.3, { Scale = 0.8 })
		Debris:AddItem(t, 0.35)
	end)
end

--================================ BIG CENTRE TEXT ================================--
local function bigText(text: string, color: Color3, size: number, duration: number)
	if currentBig then
		currentBig:Destroy()
	end
	local l = UIKit.text(bigLayer, text, size, color, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(1100, size * 1.3),
		ZIndex = 5,
		Rotation = -3,
	})
	l:FindFirstChildOfClass("UIStroke").Thickness = math.max(3, size / 10)
	currentBig = l
	local sc = make("UIScale", { Scale = 2.2 }, l)
	UIKit.tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(duration, function()
		if l.Parent then
			UIKit.tween(sc, 0.25, { Scale = 0.6 })
			UIKit.tween(l, 0.25, { TextTransparency = 1 })
			UIKit.tween(l:FindFirstChildOfClass("UIStroke"), 0.25, { Transparency = 1 })
			Debris:AddItem(l, 0.3)
		end
	end)
end

local function screenFlash(color: Color3)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 0.45
	UIKit.tween(flash, 0.5, { BackgroundTransparency = 1 })
end

--================================ FEED ================================--
local function addFeed(text: string)
	local item = make("Frame", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.15, Size = UDim2.new(1, 0, 0, 38), ZIndex = 2 }, feed)
	UIKit.corner(item, 10)
	UIKit.stroke(item, 2)
	local l = UIKit.text(item, text, 18, C.White, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), TextXAlignment = Enum.TextXAlignment.Right })
	local items = {}
	for _, c in feed:GetChildren() do
		if c:IsA("Frame") then
			table.insert(items, c)
		end
	end
	if #items > 4 then
		items[1]:Destroy()
	end
	task.delay(4.5, function()
		if item.Parent then
			UIKit.tween(item, 0.4, { BackgroundTransparency = 1 })
			UIKit.tween(l, 0.4, { TextTransparency = 1 })
			Debris:AddItem(item, 0.45)
		end
	end)
end

--================================ ROLE BADGE ================================--
local function refreshRole()
	local role = player:GetAttribute("Role")
	local look = role and Config.Roles[role]
	if not look then
		roleBadge.Visible = false
		return
	end
	roleBadge.Visible = true
	roleLabel.Text = "YOU ARE: " .. look.Label
	roleLabel.TextColor3 = look.Color
	local sc = roleBadge:FindFirstChildOfClass("UIScale") or make("UIScale", nil, roleBadge)
	sc.Scale = 1.3
	UIKit.tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

--================================ HUD ================================--
local function buildGameUI()
	local gui, root = UIKit.screen("GameUI", 5, playerGui)
	gameGui = gui
	gui.Enabled = false

	-- top centre: mode + timer
	local top = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(460, 170) }, root)
	local pill = make("Frame", { BackgroundColor3 = C.White, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(320, 44), ZIndex = 2 }, top)
	UIKit.corner(pill)
	UIKit.stroke(pill, 3)
	local pillGrad = UIKit.gradient(pill, C.Orange, C.OrangeStripe)
	modeLabel = UIKit.text(pill, "NORMAL CHASE", 26, C.White)
	timerLabel = UIKit.text(top, "00:00", 64, C.White, { Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 70) })
	subLabel = UIKit.text(top, "", 22, C.Gold, { Position = UDim2.fromOffset(0, 114), Size = UDim2.new(1, 0, 0, 28) })
	countsLabel = UIKit.text(top, "", 20, C.White, { Position = UDim2.fromOffset(0, 142), Size = UDim2.new(1, 0, 0, 26) })
	UIController.PillGradient = pillGrad

	-- top-left: menu / shop / settings
	local left = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 70), Size = UDim2.fromOffset(70, 230) }, root)
	make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, left)
	for i, info in { { "book", "Menu", C.Grey }, { "cart", "Shop", C.Pink }, { "gear", "Settings", C.Blue } } do
		local btn = UIKit.button(left, {
			Name = info[2],
			Icon = info[1],
			IconSize = 44,
			Size = UDim2.fromOffset(64, 64),
			Color = info[3],
			ColorDark = info[3]:Lerp(C.Ink, 0.35),
			LayoutOrder = i,
			Shine = false,
			HoverScale = 1.1,
		})
		UIKit.text(btn, info[2], 14, C.White, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(80, 18), ZIndex = 5 })
		btn.Activated:Connect(function()
			if info[2] == "Menu" then
				Remotes.ReturnToMenu:FireServer()
			else
				PanelsController.Open(info[2])
			end
		end)
	end

	-- top-right: coins + feed
	coinsLabel = UIKit.pill(root, "coin", C.Orange, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 70) })
	feed = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 130), Size = UDim2.fromOffset(380, 220) }, root)
	make("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder }, feed)

	-- bottom: role badge
	roleBadge = make("Frame", { BackgroundColor3 = C.Panel, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(380, 58), Visible = false, ZIndex = 2 }, root)
	UIKit.corner(roleBadge, 18)
	UIKit.stroke(roleBadge, 4)
	roleLabel = UIKit.text(roleBadge, "", 30, C.White)

	bigLayer = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4 }, root)
	flash = make("Frame", { BackgroundColor3 = C.White, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, BorderSizePixel = 0 }, gui)

	ClientState.DataChanged.Event:Connect(function(d)
		coinsLabel.Text = Util.FormatNumber(d.Coins or 0)
	end)
	if ClientState.Data then
		coinsLabel.Text = Util.FormatNumber(ClientState.Data.Coins or 0)
	end
	player:GetAttributeChangedSignal("Role"):Connect(refreshRole)
end

-- Updates the HUD texts (runs ~5x per second, only while the HUD is visible).
local function updateHUD()
	local state = ReplicatedStorage:GetAttribute("RoundState") or ""
	local cfg = modeCfg()
	modeLabel.Text = cfg.DisplayName
	UIController.PillGradient.Color = ColorSequence.new(cfg.Color, cfg.ColorDark)
	local endsAt = ReplicatedStorage:GetAttribute("RoundEndsAt") or 0
	local left = math.max(0, endsAt - workspace:GetServerTimeNow())
	local inRound = player:GetAttribute("Role") ~= nil

	if state == "INTERMISSION" then
		if ReplicatedStorage:GetAttribute("Waiting") then
			timerLabel.Text = "WAITING"
			subLabel.Text = ("Finding Players... %d/%d"):format(ReplicatedStorage:GetAttribute("PlayersInMatch") or 1, Config.Round.MaxPlayers)
		else
			timerLabel.Text = Util.FormatTime(left)
			subLabel.Text = "INTERMISSION - next round soon!"
		end
		countsLabel.Text = ""
	elseif state == "PLAYING" then
		timerLabel.Text = Util.FormatTime(left)
		timerLabel.TextColor3 = if left <= 10 then C.Red else C.White
		subLabel.Text = if inRound then (ReplicatedStorage:GetAttribute("MapName") or "") else "Round in progress - you'll play next round!"
		local hunters, prey = 0, 0
		for _, p in Players:GetPlayers() do
			local r = p:GetAttribute("Role")
			if r == cfg.HunterRole then
				hunters += 1
			elseif r == cfg.PreyRole then
				prey += 1
			end
		end
		countsLabel.Text = ("%s %d   |   %s %d"):format(cfg.PreyTeam, prey, cfg.HunterTeam, hunters)
	elseif state == "STARTING" then
		timerLabel.Text = Util.FormatTime(cfg.RoundLength)
		subLabel.Text = "GET READY!"
	elseif state == "ROUND_END" or state == "RESULTS" then
		timerLabel.Text = "00:00"
		timerLabel.TextColor3 = C.White
		subLabel.Text = ReplicatedStorage:GetAttribute("ResultTitle") or ""
	else
		timerLabel.Text = "..."
		subLabel.Text = ""
	end
end

--================================ COUNTDOWN / REVEAL ================================--
local function onCountdown(info)
	if not hudVisible or type(info) ~= "table" then
		return
	end
	task.spawn(function()
		local cfg = Config.Modes[info.Mode] or Config.Modes.Normal
		local hunterLook = Config.Roles[cfg.HunterRole]
		bigText(info.RevealTitle or "", C.White, 48, 1.1)
		Sounds.Play("Whoosh")
		task.wait(1.2)
		bigText(table.concat(info.RevealNames or {}, " & "), hunterLook.Color, 76, math.max(0.5, (info.RevealTime or 3) - 1.4))
		Sounds.Play(if info.Mode == "Infection" then "Infect" else "Tag")
		CameraController.Shake(0.4, 0.3)
		task.wait(math.max(0.5, (info.RevealTime or 3) - 1.2))
		for i, step in info.Steps or {} do
			local last = i == #info.Steps
			bigText(step, if last then C.Green else C.Gold, if last then 130 else 120, 0.8)
			Sounds.Play(if last then "Go" else "Countdown")
			task.wait(1)
		end
		if player:GetAttribute("Role") == cfg.HunterRole then
			bigText(("YOU'RE IT! GO IN %d..."):format(Config.Round.HunterReleaseDelay), Config.Roles[cfg.HunterRole].Color, 72, 1.8)
			task.delay(Config.Round.HunterReleaseDelay, function()
				bigText("CATCH THEM!", Config.Roles[cfg.HunterRole].Color, 90, 1.4)
				Sounds.Play("Go")
			end)
		else
			bigText(info.StartText or "RUN!", cfg.Color, 90, 1.4)
		end
		Sounds.Play("RoundStart")
		CameraController.Punch()
	end)
end

--================================ TAG EFFECTS ================================--
local function onTagEffect(position: Vector3, color: Color3?, kind: string?)
	if typeof(position) ~= "Vector3" then
		return
	end
	local cam = workspace.CurrentCamera
	local near = cam and (cam.CFrame.Position - position).Magnitude < 90
	if near then
		Sounds.Play(if kind == "Infect" then "Infect" else "Tag")
	end
	local fxColor = color or (if kind == "Infect" then Color3.fromHex("7dff4a") else Color3.fromHex("ffd23f"))
	if ClientState.Settings.ShowEffects then
		local p = make("Part", {
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Transparency = 1,
			Size = Vector3.one,
			Position = position,
		}, workspace)
		local pe = make("ParticleEmitter", {
			Color = ColorSequence.new(fxColor, Color3.new(1, 1, 1)),
			LightEmission = 0.6,
			Lifetime = NumberRange.new(0.4, 0.8),
			Speed = NumberRange.new(10, 20),
			SpreadAngle = Vector2.new(180, 180),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) }),
			Rate = 0,
		}, p)
		pe:Emit(28)
		-- "TAG!" pop text
		local bb = make("BillboardGui", { Size = UDim2.fromScale(6, 2), StudsOffset = Vector3.new(0, 3, 0), AlwaysOnTop = true, LightInfluence = 0 }, p)
		local t = make("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Font = Enum.Font.FredokaOne,
			TextScaled = true,
			Text = if kind == "Infect" then "INFECTED!" else "TAG!",
			TextColor3 = fxColor,
		}, bb)
		make("UIStroke", { Thickness = 3, Color = C.Ink }, t)
		UIKit.tween(bb, 0.8, { StudsOffset = Vector3.new(0, 6, 0) })
		UIKit.tween(t, 0.8, { TextTransparency = 1 })
		Debris:AddItem(p, 1.2)
	end
end

local function onUpdateRole(info)
	if not hudVisible or type(info) ~= "table" then
		return
	end
	if info.Kind == "You" then
		local look = info.Role and Config.Roles[info.Role]
		local color = if look then look.Color else C.Gold
		bigText(info.Text or "", color, 64, 1.8)
		screenFlash(color)
		CameraController.Shake(0.6, 0.35)
	elseif info.Text then
		addFeed(info.Text)
	end
end

--================================ RESULTS ================================--
local function confetti(parent: Instance)
	local colors = { C.Gold, C.Pink, C.Blue, C.Green, C.Purple, C.Orange }
	for _ = 1, 40 do
		local s = math.random(10, 18)
		local f = make("Frame", {
			BackgroundColor3 = colors[math.random(#colors)],
			BorderSizePixel = 0,
			Position = UDim2.new(math.random(), 0, -0.05, 0),
			Size = UDim2.fromOffset(s, s * 0.6),
			Rotation = math.random(0, 360),
			ZIndex = 9,
		}, parent)
		local fall = math.random(18, 32) / 10
		UIKit.tween(f, fall, {
			Position = UDim2.new(f.Position.X.Scale + (math.random() - 0.5) * 0.2, 0, 1.05, 0),
			Rotation = f.Rotation + math.random(-360, 360),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(f, fall + 0.1)
	end
end

local function closeResults()
	for _, c in resultsRoot:GetChildren() do
		c:Destroy()
	end
	resultsGui.Enabled = false
end

local function statRow(parent: Instance, order: number, icon: string, label: string, value: string, color: Color3?)
	local row = make("Frame", { BackgroundColor3 = C.Panel, Size = UDim2.new(1, 0, 0, 46), LayoutOrder = order, ZIndex = 3 }, parent)
	UIKit.corner(row, 10)
	UIKit.stroke(row, 2)
	local ih = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 3), Size = UDim2.fromOffset(40, 40), ZIndex = 4 }, row)
	UIKit.icon(ih, icon, 38)
	UIKit.text(row, label, 20, C.White, { TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(54, 0), Size = UDim2.new(0.6, -54, 1, 0), ZIndex = 4 })
	return UIKit.text(row, value, 22, color or C.Gold, { TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(0.4, 0, 0, 0), Size = UDim2.new(0.6, -14, 1, 0), ZIndex = 4 })
end

local function countUp(label: TextLabel, target: number, prefix: string)
	task.spawn(function()
		local steps = 20
		for i = 1, steps do
			label.Text = prefix .. Util.FormatNumber(math.floor(target * i / steps))
			if i % 4 == 0 then
				Sounds.Play("Coin", 1 + i / steps * 0.4)
			end
			task.wait(0.04)
		end
		label.Text = prefix .. Util.FormatNumber(target)
	end)
end

local function onResults(r)
	if not hudVisible or type(r) ~= "table" then
		return
	end
	closeResults()
	resultsGui.Enabled = true
	local cfg = Config.Modes[r.Mode] or Config.Modes.Normal

	local dim = make("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1 }, resultsRoot)
	UIKit.tween(dim, 0.4, { BackgroundTransparency = 0.35 })

	-- dramatic title
	local title = UIKit.text(resultsRoot, r.Title or "", 104, if r.Won then C.Gold else cfg.Color, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.fromOffset(1100, 120),
		ZIndex = 8,
		Rotation = -12,
	})
	title:FindFirstChildOfClass("UIStroke").Thickness = 9
	local ts = make("UIScale", { Scale = 3 }, title)
	UIKit.tween(ts, 0.6, { Scale = 1 }, Enum.EasingStyle.Back)
	UIKit.tween(title, 0.6, { Rotation = -3 }, Enum.EasingStyle.Back)
	local sub = if r.Spectator then "You'll play next round!" elseif r.Won then "YOU WIN!" else "GOOD TRY!"
	UIKit.text(resultsRoot, sub, 40, C.White, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 152), Size = UDim2.fromOffset(600, 48), ZIndex = 8 })
	Sounds.Play(if r.Won then "Victory" else "Defeat")
	if r.Won then
		confetti(resultsRoot)
		CameraController.Shake(0.5, 0.4)
	end

	-- stats card
	local card = make("Frame", { BackgroundColor3 = C.White, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 214), Size = UDim2.fromOffset(560, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 2 }, resultsRoot)
	UIKit.gradient(card, C.PanelLight, C.Panel)
	UIKit.corner(card, 18)
	UIKit.stroke(card, 4)
	make("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, card)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, card)
	local cs = make("UIScale", { Scale = 0.7 }, card)
	UIKit.tween(cs, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)

	if not r.Spectator then
		statRow(card, 1, "trophy", "Winner", if r.WinnerTeam ~= "" then r.WinnerTeam else "-", C.White)
		statRow(card, 2, if r.Mode == "Infection" then "virus" else "bolt", if r.Mode == "Infection" then "Players infected" else "Players caught", tostring(r.Caught or 0), C.White)
		statRow(card, 3, "clover", "Survival time", Util.FormatTime(r.SurvivalTime or 0), C.White)
		local coins = statRow(card, 4, "coin", "Coins earned", "+0", C.Gold)
		local xp = statRow(card, 5, "star", "XP earned", "+0", Color3.fromHex("9dff7a"))
		task.delay(0.5, function()
			countUp(coins, r.Coins or 0, "+")
			countUp(xp, r.XP or 0, "+")
		end)
		if r.NewLevel then
			statRow(card, 6, "crown", "LEVEL UP!", "Level " .. r.NewLevel, C.Gold)
		end
	else
		statRow(card, 1, "trophy", "Result", r.Title or "", C.White)
	end

	-- buttons
	local row = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -30), Size = UDim2.fromOffset(560, 72), ZIndex = 8 }, resultsRoot)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 20) }, row)
	local again = UIKit.button(row, { Text = "PLAY AGAIN", TextSize = 28, Icon = "play", IconSize = 36, Size = UDim2.fromOffset(270, 70), HoverScale = 1.08 })
	local menu = UIKit.button(row, { Text = "MAIN MENU", TextSize = 26, Size = UDim2.fromOffset(240, 70), Color = C.Grey, ColorDark = C.GreyDark, Shine = false })
	again.Activated:Connect(closeResults)
	menu.Activated:Connect(function()
		closeResults()
		Remotes.ReturnToMenu:FireServer()
	end)
	if game:GetService("UserInputService").GamepadEnabled then
		game:GetService("GuiService").SelectedObject = again
	end
end

--================================ PUBLIC ================================--
function UIController.SetVisible(on: boolean)
	hudVisible = on
	gameGui.Enabled = on
	if not on then
		closeResults()
	else
		refreshRole()
		Sounds.PlayMusic(nil)
	end
end

function UIController.Init()
	buildGameUI()
	local rg, rr = UIKit.screen("ResultsUI", 30, playerGui)
	resultsGui, resultsRoot = rg, rr
	resultsGui.Enabled = false
	local _, tr = UIKit.screen("Notifications", 60, playerGui)
	toastRoot = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -100), Size = UDim2.fromOffset(800, 200) }, tr)
	make("UIListLayout", { Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom }, toastRoot)

	Remotes.Countdown.OnClientEvent:Connect(onCountdown)
	Remotes.UpdateRole.OnClientEvent:Connect(onUpdateRole)
	Remotes.TagEffect.OnClientEvent:Connect(onTagEffect)
	Remotes.ShowResults.OnClientEvent:Connect(onResults)
	Remotes.Notify.OnClientEvent:Connect(function(text)
		if type(text) == "string" then
			UIController.Toast(text)
		end
	end)
	Remotes.RoundState.OnClientEvent:Connect(function(attrs)
		if not hudVisible or type(attrs) ~= "table" then
			return
		end
		if attrs.RoundState == "PLAYING" then
			Sounds.PlayMusic("MatchMusic")
		elseif attrs.RoundState == "ROUND_END" then
			bigText(attrs.ResultTitle or "TIME'S UP!", C.Gold, 80, 1.6)
			Sounds.PlayMusic(nil)
		elseif attrs.RoundState == "STARTING" then
			closeResults()
		end
	end)

	-- HUD refresh loop (cheap, only does work while visible)
	task.spawn(function()
		while true do
			if hudVisible then
				updateHUD()
			end
			task.wait(0.2)
		end
	end)
end

return UIController
