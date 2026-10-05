--[[
	MenuController: the 3D main menu (lobby servers).
	  MainMenu   - logo, NORMAL CHASE / INFECTION, SHOP / SETTINGS / CREDITS, player card, coins
	  GameModeUI - mode info panel (description, players, round length, difficulty, animated preview)
	               + PLAY / BACK, and the "Finding Players... 5/12" matchmaking overlay
	The 3D background is Workspace.Lobby.MenuScene: blocky characters chase each other in a circle
	while the camera slowly orbits (CameraController) with depth of field.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

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

local MenuController = {}

local menuGui: ScreenGui
local menuFade: CanvasGroup
local modeGui: ScreenGui
local modeWindow
local mmOverlay: Frame
local mmTitle: TextLabel
local mmCount: TextLabel
local mmMode: TextLabel
local mmCancel: TextButton
local selectedMode: string? = nil
local visible = false
local animConn: RBXScriptConnection? = nil
local previewConn: RBXScriptConnection? = nil
local logo: TextLabel
local toast: (string) -> ()
local entrance: { { Holder: GuiObject, Final: UDim2 } } = {}

--================================ 3D SCENE ================================--
local scene = nil -- { Focus = Vector3, Chars = { {Model, Parts, Offsets, TorsoY, Lane} } }

local LIMB_PIVOT = {
	LeftArm = Vector3.new(0, 0.9, 0),
	RightArm = Vector3.new(0, 0.9, 0),
	LeftLeg = Vector3.new(0, 0.9, 0),
	RightLeg = Vector3.new(0, 0.9, 0),
}

local function loadScene()
	if scene then
		return scene
	end
	local lobby = workspace:WaitForChild("Lobby", 10)
	local menuScene = lobby and lobby:WaitForChild("MenuScene", 10)
	if not menuScene then
		return nil
	end
	local focusPart = menuScene:WaitForChild("CameraFocus", 5)
	local chars = {}
	local folder = menuScene:FindFirstChild("Characters")
	if folder then
		for _, model in folder:GetChildren() do
			local torso = model:FindFirstChild("Torso")
			if torso then
				local offsets = {}
				for _, part in model:GetChildren() do
					if part:IsA("BasePart") then
						offsets[part] = torso.CFrame:ToObjectSpace(part.CFrame)
					end
				end
				table.insert(chars, {
					Model = model,
					Torso = torso,
					Offsets = offsets,
					TorsoY = torso.Position.Y,
					Lane = model:GetAttribute("Lane") or 0,
				})
			end
		end
	end
	scene = { Focus = if focusPart then focusPart.Position else Vector3.new(0, 3, 0), Chars = chars }
	return scene
end

-- Places one blocky character on the circle with running arms/legs.
local function poseCharacter(c, angle: number, t: number, radius: number, center: Vector3, phase: number)
	local pos = Vector3.new(center.X + math.cos(angle) * radius, c.TorsoY + math.abs(math.sin(t * 9 + phase)) * 0.35, center.Z + math.sin(angle) * radius)
	local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
	local base = CFrame.lookAt(pos, pos + tangent)
	local swing = math.sin(t * 9 + phase) * 0.8
	for part, offset in c.Offsets do
		local pivot = LIMB_PIVOT[part.Name]
		if pivot then
			local dir = if part.Name == "LeftArm" or part.Name == "RightLeg" then 1 else -1
			local p = offset.Position + pivot
			part.CFrame = base * CFrame.new(p) * CFrame.Angles(swing * dir, 0, 0) * CFrame.new(-p) * offset
		else
			part.CFrame = base * offset
		end
	end
end

local function startSceneAnimation()
	local s = loadScene()
	if animConn then
		animConn:Disconnect()
	end
	animConn = RunService.RenderStepped:Connect(function()
		local t = os.clock()
		if logo then
			logo.Rotation = -3 + math.sin(t * 1.6) * 2
		end
		if s then
			local center = s.Focus
			for _, c in s.Chars do
				-- lane 0 = chaser, a bit behind the runners
				local angle = t * 0.9 - c.Lane * 0.55
				poseCharacter(c, angle, t, 13, center, c.Lane * 1.3)
			end
		end
	end)
end

local function stopSceneAnimation()
	if animConn then
		animConn:Disconnect()
		animConn = nil
	end
end

--================================ MAIN MENU ================================--
local function addEntrance(holder: GuiObject)
	table.insert(entrance, { Holder = holder, Final = holder.Position })
end

local function buildMainMenu()
	local gui, root = UIKit.screen("MainMenu", 10, playerGui)
	menuGui = gui
	gui.Enabled = false
	menuFade = make("CanvasGroup", { Name = "Fade", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, root)

	-- soft vignette at the bottom so buttons read well over the 3D scene
	local shade = make("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.fromScale(1, 1), BorderSizePixel = 0 }, menuFade)
	make("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.75),
			NumberSequenceKeypoint.new(0.45, 1),
			NumberSequenceKeypoint.new(1, 0.45),
		}),
	}, shade)

	-- logo
	local logoHolder = make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.fromOffset(760, 150),
		ZIndex = 2,
	}, menuFade)
	logo = UIKit.text(logoHolder, Config.GameName, 112, C.Gold, { Size = UDim2.new(1, 0, 0, 120), ZIndex = 3 })
	logo:FindFirstChildOfClass("UIStroke").Thickness = 9
	UIKit.text(logoHolder, "RUN  •  CATCH  •  INFECT", 28, C.White, { Position = UDim2.fromOffset(0, 118), Size = UDim2.new(1, 0, 0, 34) })
	addEntrance(logoHolder)

	-- mode buttons
	local column = make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 250),
		Size = UDim2.fromOffset(420, 300),
		ZIndex = 2,
	}, menuFade)
	make("UIListLayout", { Padding = UDim.new(0, 14), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, column)

	local firstButton
	for i, id in Config.ModeOrder do
		local mode = Config.Modes[id]
		local btn = UIKit.button(column, {
			Name = id,
			Text = mode.DisplayName,
			TextSize = 34,
			Icon = if id == "Infection" then "virus" else "bolt",
			IconSize = 52,
			Size = UDim2.fromOffset(420, 88),
			Color = mode.Color,
			ColorDark = mode.ColorDark,
			Radius = 16,
			LayoutOrder = i,
			HoverScale = 1.07,
		})
		firstButton = firstButton or btn
		local stroke = btn:FindFirstChildOfClass("UIStroke")
		btn.MouseEnter:Connect(function()
			stroke.Color = C.Gold
			stroke.Thickness = 5
		end)
		btn.MouseLeave:Connect(function()
			stroke.Color = C.Ink
			stroke.Thickness = 3
		end)
		btn.Activated:Connect(function()
			MenuController.OpenMode(id)
		end)
	end

	-- small buttons row
	local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(420, 64), LayoutOrder = 10 }, column)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	for i, info in { { "SHOP", "cart", "Shop", C.Pink }, { "SETTINGS", "gear", "Settings", C.Blue }, { "CREDITS", "book", "Credits", C.Purple } } do
		local btn = UIKit.button(row, {
			Text = info[1],
			TextSize = 20,
			Icon = info[2],
			IconSize = 34,
			Size = UDim2.fromOffset(133, 60),
			Color = info[4],
			ColorDark = info[4]:Lerp(C.Ink, 0.35),
			LayoutOrder = i,
			Shine = false,
		})
		btn.Activated:Connect(function()
			PanelsController.Open(info[3])
		end)
	end
	addEntrance(column)

	-- player card (top-left)
	local card = make("Frame", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.1, Position = UDim2.fromOffset(20, 20), Size = UDim2.fromOffset(320, 96), ZIndex = 2 }, menuFade)
	UIKit.corner(card, 16)
	UIKit.stroke(card, 3)
	local avatar = make("ImageLabel", { BackgroundColor3 = C.PanelLight, Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(72, 72), ZIndex = 3 }, card)
	UIKit.corner(avatar)
	UIKit.stroke(avatar, 3)
	task.spawn(function()
		local ok, img = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok then
			avatar.Image = img
		end
	end)
	UIKit.text(card, player.DisplayName, 22, C.White, {
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(96, 12),
		Size = UDim2.new(1, -108, 0, 28),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local levelText = UIKit.text(card, "Level 1", 18, C.Gold, {
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(96, 42),
		Size = UDim2.new(1, -108, 0, 22),
	})
	local barBg = make("Frame", { BackgroundColor3 = C.Ink, Position = UDim2.fromOffset(96, 68), Size = UDim2.new(1, -112, 0, 14), ZIndex = 3 }, card)
	UIKit.corner(barBg)
	local barFill = make("Frame", { BackgroundColor3 = C.Gold, Size = UDim2.fromScale(0, 1), ZIndex = 4 }, barBg)
	UIKit.corner(barFill)
	addEntrance(card)

	-- coins + wins (top-right)
	local pills = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 26), Size = UDim2.fromOffset(330, 50), ZIndex = 2 }, menuFade)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 12) }, pills)
	local coins = UIKit.pill(pills, "coin", C.Orange)
	local wins = UIKit.pill(pills, "trophy", C.Purple)
	addEntrance(pills)

	UIKit.body(menuFade, "v" .. Config.Version, 14, C.Muted, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -8),
		Size = UDim2.fromOffset(120, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	local function refresh(data)
		if not data then
			return
		end
		coins.Text = Util.FormatNumber(data.Coins or 0)
		wins.Text = Util.FormatNumber(data.Wins or 0)
		levelText.Text = ("Level %d   %d / %d XP"):format(data.Level or 1, data.LevelXP or 0, data.LevelXPNeeded or 100)
		UIKit.tween(barFill, 0.4, { Size = UDim2.fromScale(math.clamp((data.LevelXP or 0) / math.max(1, data.LevelXPNeeded or 100), 0, 1), 1) })
	end
	ClientState.DataChanged.Event:Connect(refresh)
	refresh(ClientState.Data)

	MenuController.FirstButton = firstButton
end

--================================ MODE PANEL ================================--
local function buildPreview(parent: Instance, modeId: string)
	local vp = make("ViewportFrame", {
		BackgroundColor3 = Color3.fromHex("8fd3ff"),
		Size = UDim2.fromOffset(220, 220),
		Ambient = Color3.fromRGB(200, 200, 200),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-1, -2, -1),
		ZIndex = 3,
	}, parent)
	UIKit.corner(vp, 16)
	UIKit.stroke(vp, 3)
	local cam = make("Camera", { FieldOfView = 40 }, vp)
	vp.CurrentCamera = cam
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 14, 22), Vector3.new(0, 1, 0))
	make("Part", { Anchored = true, Size = Vector3.new(30, 1, 30), Position = Vector3.new(0, -0.5, 0), Color = Color3.fromHex("5cc34a"), TopSurface = Enum.SurfaceType.Studs }, vp)
	local s = loadScene()
	local actors = {}
	if s then
		for _, c in s.Chars do
			local clone = c.Model:Clone()
			for _, d in clone:GetDescendants() do
				if d:IsA("BillboardGui") or d:IsA("Highlight") or d:IsA("ParticleEmitter") then
					d:Destroy()
				end
			end
			-- infection preview: the hunter is green
			if modeId == "Infection" and c.Lane == 0 then
				for _, p in clone:GetChildren() do
					if p:IsA("BasePart") and p.Name ~= "Head" then
						p.Color = Color3.fromHex("6ad13a")
					end
				end
			end
			clone.Parent = vp
			table.insert(actors, { Model = clone, Lane = c.Lane, Y = c.TorsoY - s.Focus.Y })
		end
	end
	return vp, actors
end

local function buildModeUI()
	local gui, root = UIKit.screen("GameModeUI", 20, playerGui)
	modeGui = gui

	-- matchmaking overlay
	mmOverlay = make("Frame", { Name = "Matchmaking", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 20 }, root)
	local card = make("Frame", { BackgroundColor3 = C.Panel, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(500, 300), ZIndex = 21 }, mmOverlay)
	UIKit.corner(card, 20)
	UIKit.stroke(card, 4)
	UIKit.studs(card, 500, 300, 30, 0.93).ZIndex = 21
	local spinner = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 22), Size = UDim2.fromOffset(70, 70), ZIndex = 22 }, card)
	local spinIcon = UIKit.icon(spinner, "bolt", 64)
	mmTitle = UIKit.text(card, "FINDING PLAYERS...", 34, C.White, { Position = UDim2.fromOffset(0, 100), Size = UDim2.new(1, 0, 0, 40), ZIndex = 22 })
	mmCount = UIKit.text(card, "1 / 12", 30, C.Gold, { Position = UDim2.fromOffset(0, 142), Size = UDim2.new(1, 0, 0, 36), ZIndex = 22 })
	mmMode = UIKit.text(card, "", 20, C.Muted, { Position = UDim2.fromOffset(0, 180), Size = UDim2.new(1, 0, 0, 26), ZIndex = 22 })
	mmCancel = UIKit.button(card, {
		Text = "CANCEL",
		TextSize = 22,
		Size = UDim2.fromOffset(180, 52),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Color = C.Red,
		ColorDark = C.RedDark,
		Shine = false,
	})
	mmCancel.Parent.ZIndex = 23
	mmCancel.Activated:Connect(function()
		Remotes.CancelMatchmaking:FireServer()
	end)
	RunService.RenderStepped:Connect(function()
		if mmOverlay.Visible then
			spinIcon.Rotation = math.sin(os.clock() * 4) * 20
			mmTitle.Rotation = math.sin(os.clock() * 2) * 1.5
		end
	end)
end

local function closeModePanel()
	if previewConn then
		previewConn:Disconnect()
		previewConn = nil
	end
	if modeWindow then
		local win = modeWindow.Frame
		UIKit.tween(win, 0.25, { Position = UDim2.fromScale(1.35, 0.5), GroupTransparency = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.In).Completed:Connect(function()
			win:Destroy()
		end)
		modeWindow = nil
	end
	selectedMode = nil
end

function MenuController.OpenMode(modeId: string)
	closeModePanel()
	selectedMode = modeId
	local mode = Config.Modes[modeId]
	local root = modeGui:FindFirstChild("Root")
	local w = UIKit.window(root, {
		Name = "ModeWindow",
		Title = mode.DisplayName,
		Icon = if modeId == "Infection" then "virus" else "bolt",
		Size = Vector2.new(660, 470),
		HeaderColor = mode.Color,
		HeaderColor2 = mode.ColorDark,
	})
	modeWindow = w
	local win = w.Frame
	win.AnchorPoint = Vector2.new(0.5, 0.5)
	win.Position = UDim2.fromScale(1.35, 0.5)
	win.GroupTransparency = 1
	UIKit.tween(win, 0.45, { Position = UDim2.fromScale(0.5, 0.56), GroupTransparency = 0 }, Enum.EasingStyle.Back)
	Sounds.Play("Whoosh")

	local vp, actors = buildPreview(w.Body, modeId)
	local info = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(240, 0), Size = UDim2.new(1, -240, 0, 230), ZIndex = 3 }, w.Body)
	UIKit.body(info, mode.Description, 19, C.White, {
		Size = UDim2.new(1, 0, 0, 92),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local rows = {
		{ "Players", mode.RecommendedPlayers },
		{ "Round", Util.FormatTime(mode.RoundLength) },
	}
	for i, r in rows do
		UIKit.text(info, r[1] .. ":  " .. r[2], 22, C.White, {
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(0, 96 + (i - 1) * 34),
			Size = UDim2.new(1, 0, 0, 30),
		})
	end
	UIKit.text(info, "Difficulty:", 22, C.White, {
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, 166),
		Size = UDim2.fromOffset(130, 30),
	})
	for i = 1, 3 do
		local starHolder = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(130 + (i - 1) * 36, 162), Size = UDim2.fromOffset(36, 36), ZIndex = 3 }, info)
		local star = UIKit.icon(starHolder, "star", 34)
		if i > mode.Difficulty then
			for _, d in star:GetDescendants() do
				if d:IsA("TextLabel") then
					d.TextColor3 = C.GreyDark
				end
			end
		end
	end

	local play = UIKit.button(w.Body, {
		Text = "PLAY",
		TextSize = 34,
		Icon = "play",
		IconSize = 40,
		Size = UDim2.fromOffset(300, 76),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		HoverScale = 1.08,
		Radius = 16,
	})
	local back = UIKit.button(w.Body, {
		Text = "BACK",
		TextSize = 26,
		Size = UDim2.fromOffset(180, 64),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -6),
		Color = C.Grey,
		ColorDark = C.GreyDark,
		Shine = false,
	})
	play.Activated:Connect(function()
		Remotes.GameModeSelected:FireServer(modeId)
		mmTitle.Text = "FINDING PLAYERS..."
		mmCount.Text = ""
		mmMode.Text = mode.DisplayName
		mmCancel.Parent.Visible = true
		mmOverlay.Visible = true
	end)
	back.Activated:Connect(closeModePanel)
	w.Close.Activated:Connect(closeModePanel)
	if game:GetService("UserInputService").GamepadEnabled then
		game:GetService("GuiService").SelectedObject = play
	end

	-- animated preview: the two kinds of players run around in the viewport
	previewConn = RunService.RenderStepped:Connect(function()
		if not vp.Parent then
			return
		end
		local t = os.clock()
		for _, a in actors do
			local angle = t * 1.4 - a.Lane * 0.7
			local pos = Vector3.new(math.cos(angle) * 6, a.Y + math.abs(math.sin(t * 9 + a.Lane)) * 0.3, math.sin(angle) * 6)
			a.Model:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(-math.sin(angle), 0, math.cos(angle))))
		end
	end)
end

--================================ SHOW / HIDE ================================--
-- While the menu is open the character must not walk around behind it.
local function setControls(enabled: boolean)
	pcall(function()
		local module = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 5) :: any)
		local controls = module:GetControls()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
end

function MenuController.Show()
	if visible then
		return
	end
	visible = true
	menuGui.Enabled = true
	modeGui.Enabled = true
	mmOverlay.Visible = false
	menuFade.GroupTransparency = 1
	UIKit.tween(menuFade, 0.5, { GroupTransparency = 0 })
	for i, e in entrance do
		e.Holder.Position = e.Final + UDim2.fromOffset(0, 60)
		task.delay(0.05 * i, function()
			UIKit.tween(e.Holder, 0.5, { Position = e.Final }, Enum.EasingStyle.Back)
		end)
	end
	local s = loadScene()
	CameraController.StartMenu(if s then s.Focus else Vector3.new(0, 3, 0))
	startSceneAnimation()
	setControls(false)
	Sounds.PlayMusic("MenuMusic")
	if game:GetService("UserInputService").GamepadEnabled and MenuController.FirstButton then
		game:GetService("GuiService").SelectedObject = MenuController.FirstButton
	end
end

function MenuController.Hide()
	if not visible then
		return
	end
	visible = false
	closeModePanel()
	PanelsController.Close()
	mmOverlay.Visible = false
	UIKit.tween(menuFade, 0.35, { GroupTransparency = 1 }).Completed:Connect(function()
		if not visible then
			menuGui.Enabled = false
		end
	end)
	stopSceneAnimation()
	CameraController.StopMenu()
	setControls(true)
	game:GetService("GuiService").SelectedObject = nil
end

function MenuController.IsVisible(): boolean
	return visible
end

local function makeTeleportGui(): ScreenGui
	local g = Instance.new("ScreenGui")
	g.IgnoreGuiInset = true
	local bg = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.White }, g)
	UIKit.gradient(bg, Color3.fromHex("4cc3ff"), Color3.fromHex("6a3df0"), 60)
	local t = make("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.FredokaOne,
		Text = "GET READY TO RUN!",
		TextScaled = true,
		TextColor3 = C.Gold,
	}, bg)
	make("UITextSizeConstraint", { MaxTextSize = 80 }, t)
	return g
end

function MenuController.Init(showToast: (string) -> ())
	toast = showToast
	buildMainMenu()
	buildModeUI()

	Remotes.MatchmakingStatus.OnClientEvent:Connect(function(status)
		if type(status) ~= "table" then
			return
		end
		if status.State == "Searching" then
			mmOverlay.Visible = true
			mmTitle.Text = "FINDING PLAYERS..."
			mmCount.Text = ("%d / %d"):format(status.Count or 1, status.Max or Config.Round.MaxPlayers)
			mmCancel.Parent.Visible = true
		elseif status.State == "Teleporting" then
			mmOverlay.Visible = true
			mmTitle.Text = "TELEPORTING..."
			mmCount.Text = "Match found!"
			mmCancel.Parent.Visible = false
			Sounds.Play("Go")
			pcall(function()
				TeleportService:SetTeleportGui(makeTeleportGui())
			end)
		elseif status.State == "Joined" then
			mmOverlay.Visible = false
			MenuController.Hide()
		elseif status.State == "Cancelled" or status.State == "Failed" then
			mmOverlay.Visible = false
			if status.Message then
				toast(status.Message)
			end
		end
	end)
end

return MenuController
