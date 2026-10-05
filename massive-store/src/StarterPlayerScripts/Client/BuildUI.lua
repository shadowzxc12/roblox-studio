--[[
	BuildUI: the build menu [B] and placement.

	Pick a structure -> a ghost follows your aim, snapped to the 4 stud grid
	(green = fits, red = blocked / too far / missing materials).
	  [Click] place   [R] rotate   [Right click] / [B] cancel
	In build mode, aim at one of your structures to see its health and:
	  [U] upgrade to the next tier   [P] repair   [X] remove (refund)
	Touch: on-screen Rotate / Place / Cancel buttons, aim = centre of the screen.
	The server re-checks everything (Building service).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Buildables = require(Shared.Buildables)
local Items = require(Shared.Items)
local Cosmetics = require(Shared.Cosmetics)
local InventoryCore = require(Shared.InventoryCore)
local Progression = require(Shared.Progression)
local Net = require(Shared.Net)

local UI = require(script.Parent.UI)
local ClientState = require(script.Parent.ClientState)
local Audio = require(script.Parent.Audio)

local BuildUI = {}

local player = Players.LocalPlayer
local C = UI.C
local make = UI.make

local gui, root, menu, cards, tabs, info, touchBar
local category = "Walls"
local placing = nil -- def being placed
local rotation = 0
local ghost = nil
local canPlace = false
local hovered = nil -- structure model under the cursor
local active = false

local function level(): number
	local d = ClientState.Data
	return d and d.Level or 1
end

local function perks()
	return Progression.Perks(level())
end

-- materials available: inventory + the cart you push
local function have(id: string): number
	local n = InventoryCore.Count(ClientState.Inventory, id)
	local cartContainer = player:GetAttribute("CartContainer")
	local cont = ClientState.Container
	if cont and cont.Kind == "Cart" and cont.Id == cartContainer then
		n += InventoryCore.Count(cont, id)
	end
	return n
end

local function affordable(cost): boolean
	for id, n in cost do
		if have(id) < n then
			return false
		end
	end
	return true
end

local function lockReason(def): string?
	local lv = level()
	if def.Unlock and lv < def.Unlock then
		return "LEVEL " .. def.Unlock
	end
	if def.Tier > 1 and def.Tier > perks().Tier then
		return ({ "", "LEVEL 3", "LEVEL 8", "LEVEL 16" })[def.Tier]
	end
	if def.Cosmetic then
		local d = ClientState.Data
		if not d or not Cosmetics.Owns(d, lv, def.Cosmetic) then
			return "SHOP"
		end
	end
	return nil
end

local function costLine(parent, cost, order)
	local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = order or 5 }, parent)
	UI.list(row, 6, true).VerticalAlignment = Enum.VerticalAlignment.Center
	local keys = {}
	for id in cost do
		table.insert(keys, id)
	end
	table.sort(keys)
	for _, id in keys do
		local n = cost[id]
		local item = Items.Get(id)
		local ok = have(id) >= n
		local chip = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X }, row)
		UI.list(chip, 2, true).VerticalAlignment = Enum.VerticalAlignment.Center
		local ic = UI.ItemIcon(chip, id, 16)
		ic.LayoutOrder = 1
		UI.text(chip, ("%d/%d"):format(math.min(have(id), 99), n), 11, if ok then C.Text else C.Danger, UI.Mono, { Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 })
		if not item then
			chip:Destroy()
		end
	end
	return row
end

--============================ MENU ============================--
local function refreshCards()
	cards:ClearAllChildren()
	make("UIGridLayout", { CellSize = UDim2.fromOffset(150, 118), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, cards)
	for _, def in Buildables.List do
		if def.Category == category then
			local reason = lockReason(def)
			local card = make("TextButton", { AutoButtonColor = false, Text = "", BackgroundColor3 = C.Panel2, LayoutOrder = def.Order }, cards)
			UI.corner(card, 8)
			local tierColor = Color3.fromHex(Buildables.TierInfo[def.Tier].Color)
			local stroke = UI.stroke(card, C.Line, 1)
			UI.pad(card, 8, 6)
			UI.list(card, 3)
			local swatch = make("Frame", { BackgroundColor3 = Color3.fromHex(def.Color), Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 1 }, card)
			UI.corner(swatch, 5)
			if def.Tier > 0 then
				UI.text(swatch, Buildables.TierInfo[def.Tier].Name, 10, Color3.new(1, 1, 1), UI.Caps, { Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -6, 1, 0), TextStrokeTransparency = 0.4 })
			end
			UI.text(card, def.Name, 13, C.Text, UI.Bold, { Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 2, TextTruncate = Enum.TextTruncate.AtEnd })
			UI.text(card, ("HP %d%s"):format(def.HP, if def.Power then (" · ⚡%d"):format(def.Power) elseif def.Slots then (" · %d slots"):format(def.Slots) else ""), 10, C.Muted, UI.Mono, { Size = UDim2.new(1, 0, 0, 13), LayoutOrder = 3 })
			costLine(card, def.Cost, 4)
			if reason then
				local lock = make("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, Size = UDim2.fromScale(1, 1), ZIndex = 8 }, card)
				UI.corner(lock, 8)
				UI.text(lock, "🔒 " .. reason, 13, C.Accent, UI.Title, { TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 9 })
			end
			card.MouseEnter:Connect(function()
				stroke.Color = tierColor
				Audio.Play("Hover")
			end)
			card.MouseLeave:Connect(function()
				stroke.Color = C.Line
			end)
			card.Activated:Connect(function()
				if reason then
					Audio.Play("Warn")
					return
				end
				BuildUI.StartPlacing(def)
			end)
		end
	end
end

local function buildMenu()
	menu = UI.panel(root, { Name = "BuildMenu", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -96), Size = UDim2.fromOffset(820, 330), Visible = false }, 14)
	UI.text(menu, "BUILD", 22, C.Text, UI.Title, { Position = UDim2.fromOffset(18, 12), Size = UDim2.fromOffset(120, 26) })
	UI.text(menu, "Materials come from your inventory and the cart you push", 11, C.Muted, UI.Bold, { Position = UDim2.fromOffset(110, 20), Size = UDim2.fromOffset(400, 14) })
	local close = UI.button(menu, { Text = "✕", Size = UDim2.fromOffset(32, 32), Position = UDim2.new(1, -46, 0, 10) })
	close.Activated:Connect(function()
		BuildUI.Toggle(false)
	end)
	tabs = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 48), Size = UDim2.new(1, -36, 0, 30) }, menu)
	UI.list(tabs, 6, true)
	for i, cat in Buildables.Categories do
		local b = UI.button(tabs, { Text = string.upper(cat), Size = UDim2.fromOffset(100, 30), TextSize = 12, LayoutOrder = i, Style = if cat == category then "Primary" else "Dark" })
		b.Activated:Connect(function()
			category = cat
			for _, other in tabs:GetChildren() do
				if other:IsA("TextButton") then
					local sel = other.Text == string.upper(cat)
					other.BackgroundColor3 = if sel then C.Accent else C.Panel2
					other.TextColor3 = if sel then Color3.fromHex("111111") else C.Text
				end
			end
			refreshCards()
		end)
	end
	cards = make("ScrollingFrame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 88), Size = UDim2.new(1, -36, 1, -100), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3, BorderSizePixel = 0 }, menu)

	-- placement help / structure info
	info = UI.panel(root, { Name = "BuildInfo", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -100), Size = UDim2.fromOffset(460, 64), Visible = false }, 10)
	UI.pad(info, 12, 8)
	UI.list(info, 3)

	touchBar = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -180), Size = UDim2.fromOffset(120, 170), Visible = false }, root)
	UI.list(touchBar, 8)
	for _, t in { { "PLACE", "Primary" }, { "ROTATE", "Dark" }, { "CANCEL", "Danger" } } do
		local b = UI.button(touchBar, { Text = t[1], Style = t[2], Size = UDim2.fromOffset(120, 46), TextSize = 15 })
		b.Activated:Connect(function()
			if t[1] == "PLACE" then
				BuildUI.Place()
			elseif t[1] == "ROTATE" then
				rotation = (rotation + 90) % 360
			else
				BuildUI.StopPlacing()
			end
		end)
	end
end

local function setInfo(lines)
	for _, c in info:GetChildren() do
		if not c:IsA("UIPadding") and not c:IsA("UIListLayout") and not c:IsA("UICorner") and not c:IsA("UIStroke") and not c:IsA("UIGradient") then
			c:Destroy()
		end
	end
	info.Visible = lines ~= nil
	info.Size = UDim2.fromOffset(460, 18 + (if lines then #lines * 20 else 0))
	if lines then
		for i, l in lines do
			if type(l) == "table" and l.Cost then
				costLine(info, l.Cost, i)
			else
				UI.text(info, l.Text or l, l.Size or 13, l.Color or C.Text, l.Font or UI.Bold, { Size = UDim2.new(1, 0, 0, 17), LayoutOrder = i })
			end
		end
	end
end

--============================ GHOST ============================--
local function clearGhost()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
end

local function makeGhost(def)
	clearGhost()
	local p = Instance.new("Part")
	p.Name = "BuildGhost"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.ForceField
	p.Size = Vector3.new(def.Size[1], def.Size[2], def.Size[3])
	p.Color = C.Good
	p.Transparency = 0.2
	p.Parent = Workspace.CurrentCamera
	if def.Kind == "Ramp" then
		local w = Instance.new("WedgePart")
		w.Anchored = true
		w.CanCollide = false
		w.CanQuery = false
		w.Size = p.Size
		w.Material = Enum.Material.ForceField
		w.Parent = p
		p.Transparency = 1
	end
	ghost = p
end

local function aimRay()
	local cam = Workspace.CurrentCamera
	local pos
	if UI.IsTouch() then
		pos = cam.ViewportSize / 2
	else
		pos = UserInputService:GetMouseLocation()
	end
	return cam:ViewportPointToRay(pos.X, pos.Y)
end

local function raycastWorld(ray)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = { Workspace.CurrentCamera }
	if player.Character then
		table.insert(list, player.Character)
	end
	local store = Workspace:FindFirstChild("Store")
	if store then
		for _, n in { "Loot", "Lights", "Signs", "Dynamic" } do
			local f = store:FindFirstChild(n)
			if f then
				table.insert(list, f)
			end
		end
	end
	params.FilterDescendantsInstances = list
	return Workspace:Raycast(ray.Origin, ray.Direction * 80, params)
end

local function structureFrom(inst: Instance?)
	while inst and inst ~= Workspace do
		if inst:IsA("Model") and inst:GetAttribute("StructureId") then
			return inst
		end
		inst = inst.Parent
	end
	return nil
end

local function updatePlacement()
	if not placing or not ghost then
		return
	end
	local hit = raycastWorld(aimRay())
	if not hit then
		ghost.Transparency = 1
		canPlace = false
		return
	end
	local pos = hit.Position
	-- walls placed against a structure's side snap next to it
	local cf = Buildables.Snap(placing, pos, rotation, Config.Building.Grid)
	ghost.CFrame = cf
	local w = ghost:FindFirstChildOfClass("WedgePart")
	if w then
		w.CFrame = cf
	end
	local char = player.Character
	local rootPart = char and char:FindFirstChild("HumanoidRootPart")
	local reason = nil
	if not rootPart or (rootPart.Position - cf.Position).Magnitude > Config.Survival.BuildReach then
		reason = "Too far"
	elseif not affordable(placing.Cost) then
		reason = "Not enough materials"
	else
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local list = { Workspace.CurrentCamera }
		for _, p in Players:GetPlayers() do
			if p.Character then
				table.insert(list, p.Character)
			end
		end
		local store = Workspace:FindFirstChild("Store")
		if store then
			for _, n in { "Loot", "Dynamic", "Lights", "Signs" } do
				local f = store:FindFirstChild(n)
				if f then
					table.insert(list, f)
				end
			end
		end
		params.FilterDescendantsInstances = list
		params.RespectCanCollide = true
		local parts = Workspace:GetPartBoundsInBox(cf, ghost.Size - Vector3.new(0.3, 0.3, 0.3), params)
		if #parts > 0 then
			reason = "Blocked"
		end
	end
	canPlace = reason == nil
	local color = if canPlace then C.Good else C.Danger
	ghost.Color = color
	ghost.Transparency = if ghost:FindFirstChildOfClass("WedgePart") then 1 else 0.25
	if w then
		w.Color = color
	end
	setInfo({
		{ Text = placing.Name .. (if reason then "  —  " .. reason else ""), Color = if reason then C.Danger else C.Text, Font = UI.Title, Size = 15 },
		{ Cost = placing.Cost },
		{ Text = if UI.IsTouch() then "PLACE · ROTATE · CANCEL" else "[Click] place   [R] rotate   [Right click] cancel", Color = C.Muted, Size = 11 },
	})
end

local hoverHighlight = nil
local function updateHover()
	if placing or not active then
		if hoverHighlight then
			hoverHighlight:Destroy()
			hoverHighlight = nil
		end
		hovered = nil
		return
	end
	local hit = raycastWorld(aimRay())
	local model = hit and structureFrom(hit.Instance)
	if model ~= hovered then
		hovered = model
		if hoverHighlight then
			hoverHighlight:Destroy()
			hoverHighlight = nil
		end
		if model then
			hoverHighlight = Instance.new("Highlight")
			hoverHighlight.FillTransparency = 0.85
			hoverHighlight.OutlineColor = C.Accent
			hoverHighlight.FillColor = C.Accent
			hoverHighlight.Adornee = model
			hoverHighlight.Parent = Workspace.CurrentCamera
		end
	end
	if hovered then
		local def = Buildables.Get(hovered:GetAttribute("Build"))
		if def then
			local hp, max = hovered:GetAttribute("HP") or def.HP, hovered:GetAttribute("MaxHP") or def.HP
			local lines = {
				{ Text = ("%s   HP %d/%d   owner: %s"):format(def.Name, hp, max, hovered:GetAttribute("OwnerName") or "?"), Font = UI.Title, Size = 14 },
			}
			local up = def.Upgrade and Buildables.Get(def.Upgrade)
			if up then
				local cost = Buildables.UpgradeCost(def.Id, Config.Building.UpgradeCostFraction)
				table.insert(lines, { Text = "[U] Upgrade to " .. up.Name, Color = C.Accent, Size = 12 })
				table.insert(lines, { Cost = cost })
			end
			table.insert(lines, { Text = ("[P] Repair   %s"):format(if hovered:GetAttribute("Owner") == player.UserId then "[X] Remove (50% refund)" else ""), Color = C.Muted, Size = 12 })
			setInfo(lines)
		end
	elseif not menu.Visible then
		setInfo({ { Text = "BUILD MODE · aim at a structure to upgrade / repair · [B] menu", Color = C.Muted, Size = 12 } })
	else
		setInfo(nil)
	end
end

--============================ API ============================--
function BuildUI.StartPlacing(def)
	placing = def
	menu.Visible = false
	makeGhost(def)
	touchBar.Visible = UI.IsTouch()
	Audio.Play("Open")
end

function BuildUI.StopPlacing()
	placing = nil
	clearGhost()
	touchBar.Visible = false
	setInfo(nil)
end

function BuildUI.Place()
	if not placing or not ghost then
		return
	end
	if not canPlace then
		Audio.Play("Warn")
		return
	end
	local cf = ghost.CFrame
	local base = cf.Position - Vector3.new(0, placing.Size[2] / 2, 0)
	Net.Event("Build"):FireServer({ Action = "Place", Id = placing.Id, Position = base, Rotation = rotation })
	Audio.Play("Build")
end

function BuildUI.Action(action: string)
	if not hovered then
		return
	end
	Net.Event("Build"):FireServer({ Action = action, Target = hovered:GetAttribute("StructureId") })
	Audio.Play("Click")
end

function BuildUI.Toggle(on: boolean?)
	if on == nil then
		on = not active
	end
	if on and (not ClientState.InRun() or not player:GetAttribute("HasHammer") or player:GetAttribute("Infected")) then
		if on and not player:GetAttribute("HasHammer") then
			Audio.Play("Warn")
		end
		return
	end
	active = on
	ClientState.SetBusy("Build", on)
	menu.Visible = on
	if on then
		refreshCards()
		local scale = menu:FindFirstChildOfClass("UIScale") or make("UIScale", {}, menu)
		scale.Scale = 0.94
		UI.tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
		Audio.Play("Open")
	else
		BuildUI.StopPlacing()
		setInfo(nil)
		Audio.Play("Close")
	end
end

function BuildUI.IsActive(): boolean
	return active
end

function BuildUI.IsPlacing(): boolean
	return placing ~= nil
end

function BuildUI.HandleInput(input: InputObject): boolean
	if not active then
		return false
	end
	local kc = input.KeyCode
	if input.UserInputType == Enum.UserInputType.MouseButton1 and placing then
		BuildUI.Place()
		return true
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		if placing then
			BuildUI.StopPlacing()
			menu.Visible = true
			return true
		end
	elseif kc == Enum.KeyCode.R and placing then
		rotation = (rotation + 90) % 360
		Audio.Play("Hover")
		return true
	elseif kc == Enum.KeyCode.U then
		BuildUI.Action("Upgrade")
		return true
	elseif kc == Enum.KeyCode.P then
		BuildUI.Action("Repair")
		return true
	elseif kc == Enum.KeyCode.X and hovered then
		BuildUI.Action("Remove")
		return true
	elseif kc == Enum.KeyCode.Escape then
		BuildUI.Toggle(false)
		return true
	end
	return false
end

function BuildUI.SetVisible(on: boolean)
	gui.Enabled = on
	if not on then
		BuildUI.Toggle(false)
	end
end

function BuildUI.Init()
	gui, root = UI.screen("MSL_Build", 4)
	buildMenu()
	RunService.RenderStepped:Connect(function()
		if active then
			updatePlacement()
			updateHover()
		end
	end)
	ClientState.InventoryChanged:Connect(function()
		if active and menu.Visible then
			refreshCards()
		end
	end)
	gui.Enabled = false
end

return BuildUI
