--[[
	InventoryUI: hotbar (slots 1-6) + the full inventory [Tab] + containers (storage, carts,
	bags, supply crates).

	Fast & simple:
	  1-6 / click a hotbar slot   hold that item (click again to put it away)
	  Left click (holding)        use / eat / throw
	  Q                           drop the held item
	  Tab                         open the inventory. Click an item to select it, click another
	                              slot to move / swap / stack. Buttons: use, drop, give, store.
	  With a container open       click your item = store it, click theirs = take it.
	Everything is a request; the server checks and answers with the new inventory.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Items)
local Rarity = require(Shared.Rarity)
local Net = require(Shared.Net)

local UI = require(script.Parent.UI)
local ClientState = require(script.Parent.ClientState)
local Audio = require(script.Parent.Audio)

local InventoryUI = {}

local player = Players.LocalPlayer
local C = UI.C
local make = UI.make

local gui, root
local hotbar, hotSlots = nil, {}
local panel, grid, details, contPanel, contGrid, contTitle
local selectedSlot = nil -- slot picked in the full inventory
local open = false
local heldLabel

local function invAction(t)
	Net.Event("InvAction"):FireServer(t)
end

local function slotFrame(parent, size: number, order: number)
	local f = make("TextButton", {
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.12,
		Size = UDim2.fromOffset(size, size),
		LayoutOrder = order,
		BorderSizePixel = 0,
	}, parent)
	UI.corner(f, 8)
	local stroke = UI.stroke(f, Color3.new(1, 1, 1), 1, 0.92)
	local iconHolder = make("Frame", { Name = "IconHolder", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Size = UDim2.fromOffset(size * 0.72, size * 0.72) }, f)
	local qty = UI.text(f, "", 12, C.Text, UI.Mono, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -5, 1, -2), Size = UDim2.fromOffset(40, 14), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 6 })
	-- Figma: a full-width rarity strip along the bottom edge
	local rarityBar = make("Frame", { BackgroundColor3 = C.Line, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, -8, 0, 3), ZIndex = 5 }, f)
	UI.corner(rarityBar, 2)
	return { Button = f, Stroke = stroke, Icon = iconHolder, Qty = qty, Rarity = rarityBar, ItemId = nil, Size = size }
end

local function fillSlot(s, entry)
	local id = entry and entry.Id or nil
	if s.ItemId ~= id then
		s.ItemId = id
		s.Icon:ClearAllChildren()
		if id then
			local icon = UI.ItemIcon(s.Icon, id, s.Size * 0.72)
			icon.Position = UDim2.fromOffset(0, 0)
		end
	end
	s.Qty.Text = if entry and entry.Qty > 1 then "×" .. entry.Qty else ""
	local item = id and Items.Get(id)
	s.Rarity.BackgroundColor3 = if item then UI.RarityColor(item.Rarity) else C.Line
	s.Rarity.Visible = item ~= nil
end

--============================ HOTBAR ============================--
local function buildHotbar()
	hotbar = make("Frame", { Name = "Hotbar", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(6 * 68 + 5 * 8, 68) }, root)
	UI.list(hotbar, 8, true)
	for i = 1, 6 do
		local s = slotFrame(hotbar, 68, i)
		s.Number = UI.text(s.Button, tostring(i), 10, C.Muted, UI.Mono, { Position = UDim2.fromOffset(6, 4), Size = UDim2.fromOffset(12, 12), ZIndex = 6 })
		s.Button.Activated:Connect(function()
			Net.Event("Hotbar"):FireServer(i)
		end)
		hotSlots[i] = s
	end
	heldLabel = UI.text(root, "", 15, C.Text, UI.Title, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -90), Size = UDim2.fromOffset(400, 20), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1 })
end

local lastHeld = nil
local function refreshHotbar(inv)
	for i = 1, 6 do
		local s = hotSlots[i]
		fillSlot(s, inv.Slots[i] or nil)
		local sel = inv.Selected == i
		s.Stroke.Color = if sel then C.Accent else Color3.new(1, 1, 1)
		s.Stroke.Transparency = if sel then 0 else 0.92
		s.Stroke.Thickness = if sel then 2 else 1
		s.Button.BackgroundColor3 = if sel then C.Panel2 else C.Panel
		if s.Number then
			s.Number.TextColor3 = if sel then C.Accent else C.Muted
		end
	end
	local held = inv.Slots[inv.Selected or 0]
	local heldId = held and held.Id or nil
	if heldId ~= lastHeld then
		lastHeld = heldId
		if heldId then
			local item = Items.Get(heldId)
			heldLabel.Text = item.Name .. (if item.Use then "  ·  click to use" elseif item.Tool then "  ·  click to use" else "")
			heldLabel.TextColor3 = UI.RarityColor(item.Rarity)
			heldLabel.TextTransparency = 0
			task.delay(2, function()
				if lastHeld == heldId then
					UI.tween(heldLabel, 0.6, { TextTransparency = 1 })
				end
			end)
		end
	end
end

--============================ FULL INVENTORY ============================--
local gridSlots = {}
local contSlots = {}

local function showDetails(slot)
	details:ClearAllChildren()
	UI.pad(details, 14, 12)
	local inv = ClientState.Inventory
	local entry = slot and inv.Slots[slot]
	if not entry then
		UI.text(details, "Select an item", 14, C.Muted, UI.Bold, { Size = UDim2.new(1, 0, 0, 20) })
		return
	end
	local item = Items.Get(entry.Id)
	local layout = UI.list(details, 6)
	local iconBox = make("Frame", { BackgroundColor3 = C.Panel2, Size = UDim2.fromOffset(80, 80), LayoutOrder = 1 }, details)
	UI.corner(iconBox, 10)
	UI.stroke(iconBox, UI.RarityColor(item.Rarity), 1.5)
	local ic = UI.ItemIcon(iconBox, item.Id, 64)
	ic.Position = UDim2.fromOffset(8, 8)
	UI.text(details, item.Name, 20, C.Text, UI.Title, { Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 2, TextWrapped = true })
	UI.text(details, Rarity.Info[item.Rarity].Name .. " · " .. Items.CategoryInfo[item.Category].Name, 11, UI.RarityColor(item.Rarity), UI.Caps, { Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 3 })
	UI.text(details, item.Desc or "", 13, C.Muted, UI.Body, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, LayoutOrder = 4 })
	if item.Use then
		local parts = {}
		for k, v in item.Use do
			if type(v) == "number" then
				table.insert(parts, ("%s +%d"):format(k, v))
			end
		end
		UI.text(details, table.concat(parts, "   "), 12, C.Good, UI.Mono, { Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 5, TextWrapped = true })
	end
	local buttons = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 6 }, details)
	UI.list(buttons, 6)
	local function btn(text, style, fn)
		local b = UI.button(buttons, { Text = text, Style = style, Size = UDim2.new(1, 0, 0, 34), TextSize = 14 })
		b.Activated:Connect(fn)
	end
	if item.Use or item.Tool or item.Category == "Battery" or item.Category == "Fuel" then
		btn("USE", "Primary", function()
			Net.Event("UseItem"):FireServer(slot)
		end)
	end
	if ClientState.Container then
		btn("STORE  →", "Good", function()
			invAction({ Action = "Store", Slot = slot })
		end)
	end
	btn("DROP", "Dark", function()
		invAction({ Action = "Drop", Slot = slot })
		selectedSlot = nil
	end)
	if entry.Qty > 1 then
		btn("DROP ONE", "Dark", function()
			invAction({ Action = "Drop", Slot = slot, Qty = 1 })
		end)
	end
	-- give to the nearest teammate
	local char = player.Character
	local root_ = char and char:FindFirstChild("HumanoidRootPart")
	local nearest, nd = nil, 14
	if root_ then
		for _, e in ClientState.Squad do
			if e.UserId ~= player.UserId and e.Pos and not e.Dead and not e.Downed then
				local d = (e.Pos - root_.Position).Magnitude
				if d < nd then
					nearest, nd = e, d
				end
			end
		end
	end
	if nearest then
		btn("GIVE TO " .. string.upper(nearest.Name), "Dark", function()
			invAction({ Action = "Give", Slot = slot, Target = nearest.UserId })
		end)
	end
end

local function buildPanel()
	panel = UI.panel(root, { Name = "Inventory", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.fromOffset(640, 420), Visible = false }, 14)
	UI.text(panel, "INVENTORY", 22, C.Text, UI.Title, { Position = UDim2.fromOffset(20, 14), Size = UDim2.fromOffset(300, 26) })
	local hint = UI.text(panel, "Click an item, then click a slot to move it · [Tab] close", 11, C.Muted, UI.Bold, { Position = UDim2.fromOffset(20, 40), Size = UDim2.fromOffset(400, 14) })
	local close = UI.button(panel, { Text = "✕", Size = UDim2.fromOffset(34, 34), Position = UDim2.new(1, -48, 0, 12), TextSize = 16 })
	close.Activated:Connect(function()
		InventoryUI.Toggle(false)
	end)
	grid = make("ScrollingFrame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 64), Size = UDim2.fromOffset(372, 336), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3, BorderSizePixel = 0 }, panel)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(66, 66), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	details = make("Frame", { BackgroundColor3 = C.Panel2, BackgroundTransparency = 0.3, Position = UDim2.fromOffset(404, 64), Size = UDim2.fromOffset(216, 336) }, panel)
	UI.corner(details, 10)

	-- container side panel
	contPanel = UI.panel(root, { Name = "Container", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5, 330, 0.47, 0), Size = UDim2.fromOffset(300, 420), Visible = false }, 14)
	UI.stroke(contPanel, C.Accent, 1.5)
	contTitle = UI.text(contPanel, "STORAGE", 20, C.Accent, UI.Title, { Position = UDim2.fromOffset(18, 14), Size = UDim2.fromOffset(200, 24) })
	UI.text(contPanel, "Click an item to take it", 11, C.Muted, UI.Bold, { Position = UDim2.fromOffset(18, 40), Size = UDim2.fromOffset(260, 14) })
	contGrid = make("ScrollingFrame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 64), Size = UDim2.fromOffset(268, 296), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3, BorderSizePixel = 0 }, contPanel)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(58, 58), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, contGrid)
	local takeAll = UI.button(contPanel, { Text = "TAKE ALL", Style = "Primary", Size = UDim2.fromOffset(130, 34), Position = UDim2.new(0, 18, 1, -48), TextSize = 14 })
	takeAll.Activated:Connect(function()
		invAction({ Action = "TakeAll" })
	end)
	local closeC = UI.button(contPanel, { Text = "CLOSE", Size = UDim2.fromOffset(120, 34), Position = UDim2.new(1, -138, 1, -48), TextSize = 14 })
	closeC.Activated:Connect(function()
		invAction({ Action = "Close" })
	end)
	hint.Parent = panel
end

local function refreshGrid(inv)
	local size = inv.Size or 12
	for i = 1, math.max(size, #gridSlots) do
		local s = gridSlots[i]
		if i <= size and not s then
			s = slotFrame(grid, 66, i)
			local index = i
			s.Button.Activated:Connect(function()
				local cur = ClientState.Inventory
				if ClientState.Container and cur.Slots[index] then
					invAction({ Action = "Store", Slot = index })
					return
				end
				if selectedSlot and selectedSlot ~= index and cur.Slots[selectedSlot] then
					invAction({ Action = "Move", From = selectedSlot, To = index })
					selectedSlot = nil
				elseif cur.Slots[index] then
					selectedSlot = index
				else
					selectedSlot = nil
				end
				Audio.Play("Click")
				refreshGrid(ClientState.Inventory)
				showDetails(selectedSlot)
			end)
			s.Button.MouseButton2Click:Connect(function()
				if ClientState.Inventory.Slots[index] then
					Net.Event("UseItem"):FireServer(index)
				end
			end)
			gridSlots[i] = s
		end
		if s then
			s.Button.Visible = i <= size
			if i <= size then
				fillSlot(s, inv.Slots[i] or nil)
				local sel = selectedSlot == i
				s.Stroke.Color = if sel then C.Accent elseif i <= 6 then C.Dim else C.Line
				s.Stroke.Thickness = if sel then 2 else 1
			end
		end
	end
end

local function refreshContainer(c)
	if not c then
		contPanel.Visible = false
		ClientState.SetBusy("Container", false)
		if open and not panel.Visible then
			InventoryUI.Toggle(false)
		end
		return
	end
	contPanel.Visible = true
	ClientState.SetBusy("Container", true)
	contTitle.Text = string.upper(c.Name or c.Kind or "STORAGE")
	for i = 1, math.max(c.Size, #contSlots) do
		local s = contSlots[i]
		if i <= c.Size and not s then
			s = slotFrame(contGrid, 58, i)
			local index = i
			s.Button.Activated:Connect(function()
				if ClientState.Container and ClientState.Container.Slots[index] then
					invAction({ Action = "Take", Slot = index })
					Audio.Play("Click")
				end
			end)
			contSlots[i] = s
		end
		if s then
			s.Button.Visible = i <= c.Size
			if i <= c.Size then
				fillSlot(s, c.Slots[i] or nil)
			end
		end
	end
	if not panel.Visible then
		InventoryUI.Toggle(true)
	end
end

function InventoryUI.Toggle(on: boolean?)
	if on == nil then
		on = not panel.Visible
	end
	if on and not ClientState.InRun() then
		return
	end
	open = on
	panel.Visible = on
	ClientState.SetBusy("Inventory", on)
	Audio.Play(if on then "Open" else "Close")
	if on then
		selectedSlot = nil
		refreshGrid(ClientState.Inventory)
		showDetails(nil)
		local scale = panel:FindFirstChildOfClass("UIScale") or make("UIScale", {}, panel)
		scale.Scale = 0.92
		UI.tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	else
		if ClientState.Container then
			invAction({ Action = "Close" })
		end
	end
end

function InventoryUI.IsOpen(): boolean
	return panel.Visible
end

function InventoryUI.SetVisible(on: boolean)
	gui.Enabled = on
	if not on then
		panel.Visible = false
		contPanel.Visible = false
		ClientState.SetBusy("Inventory", false)
		ClientState.SetBusy("Container", false)
	end
end

function InventoryUI.Init()
	gui, root = UI.screen("MSL_Inventory", 4)
	buildHotbar()
	buildPanel()
	ClientState.InventoryChanged:Connect(function(inv)
		refreshHotbar(inv)
		if panel.Visible then
			refreshGrid(inv)
			if selectedSlot and not inv.Slots[selectedSlot] then
				selectedSlot = nil
			end
			showDetails(selectedSlot)
		end
	end)
	ClientState.ContainerChanged:Connect(refreshContainer)
	refreshHotbar(ClientState.Inventory)
	gui.Enabled = false
end

return InventoryUI
