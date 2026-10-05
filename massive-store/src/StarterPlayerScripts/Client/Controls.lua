--[[
	Controls: keyboard, mouse, gamepad and touch.

	  Shift sprint (loud)   C crouch (quiet)   F flashlight   R reload batteries   N night vision
	  1-6 hold item   Click use   Q drop   Tab inventory   B build   M map
	  G let go of cart   X cart basket   H emote   Space leave hiding spot
	Touch gets on-screen buttons; gamepad: L3 sprint, R3 crouch, DPad items, Y build, X use.
	The client only sends intentions; speeds, stamina and every action are decided on the server.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Cosmetics = require(Shared.Cosmetics)

local UI = require(script.Parent.UI)
local ClientState = require(script.Parent.ClientState)
local InventoryUI = require(script.Parent.InventoryUI)
local BuildUI = require(script.Parent.BuildUI)
local MapUI = require(script.Parent.MapUI)

local Controls = {}

local player = Players.LocalPlayer
local sprint, crouch = false, false
local lastSent = { Sprint = false, Crouch = false }
local touchGui, emoteMenu

local function sendInput()
	if lastSent.Sprint ~= sprint or lastSent.Crouch ~= crouch then
		lastSent = { Sprint = sprint, Crouch = crouch }
		Net.Event("Input"):FireServer({ Sprint = sprint, Crouch = crouch })
	end
end

local function inRun(): boolean
	return ClientState.InRun() and not ClientState.MenuOpen
end

local function aimPoint(): Vector3?
	local cam = Workspace.CurrentCamera
	local pos = if UI.IsTouch() then cam.ViewportSize / 2 else UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(pos.X, pos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character or Workspace.CurrentCamera, Workspace.CurrentCamera }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 120, params)
	return if hit then hit.Position else ray.Origin + ray.Direction * 60
end

function Controls.Use()
	if not inRun() then
		return
	end
	if player:GetAttribute("Infected") then
		Net.Event("UseItem"):FireServer(0)
		return
	end
	local inv = ClientState.Inventory
	local slot = inv.Selected or 0
	if slot > 0 and inv.Slots[slot] then
		Net.Event("UseItem"):FireServer(slot, aimPoint())
	end
end

local function toggleEmotes()
	if not emoteMenu then
		return
	end
	emoteMenu.Visible = not emoteMenu.Visible
	if emoteMenu.Visible then
		emoteMenu:ClearAllChildren()
		UI.list(emoteMenu, 6, true, Enum.HorizontalAlignment.Center)
		local d = ClientState.Data
		for _, c in Cosmetics.List do
			if c.Slot == "Emote" and d and Cosmetics.Owns(d, d.Level or 1, c.Id) then
				local b = UI.button(emoteMenu, { Text = string.upper(c.Name), Size = UDim2.fromOffset(110, 36), TextSize = 12, LayoutOrder = c.Order })
				b.Activated:Connect(function()
					Net.Event("Emote"):FireServer(c.Id)
					emoteMenu.Visible = false
				end)
			end
		end
	end
end

local function onInput(input: InputObject, processed: boolean)
	if not inRun() then
		return
	end
	if BuildUI.HandleInput(input, processed) then
		return
	end
	if processed then
		return
	end
	local kc = input.KeyCode
	local t = input.UserInputType
	if kc == Enum.KeyCode.LeftShift or kc == Enum.KeyCode.ButtonL3 then
		sprint = true
		crouch = false
	elseif kc == Enum.KeyCode.C or kc == Enum.KeyCode.ButtonR3 then
		crouch = not crouch
	elseif kc == Enum.KeyCode.LeftControl then
		crouch = true
	elseif kc == Enum.KeyCode.F then
		Net.Event("Flashlight"):FireServer()
	elseif kc == Enum.KeyCode.R then
		Net.Event("Reload"):FireServer()
	elseif kc == Enum.KeyCode.N then
		Net.Event("NightVision"):FireServer()
	elseif kc == Enum.KeyCode.ButtonSelect then
		if not BuildUI.IsActive() then
			InventoryUI.Toggle()
		end
	elseif kc == Enum.KeyCode.B or kc == Enum.KeyCode.ButtonY then
		InventoryUI.Toggle(false)
		BuildUI.Toggle()
	elseif kc == Enum.KeyCode.M then
		MapUI.Toggle()
	elseif kc == Enum.KeyCode.G then
		Net.Event("Cart"):FireServer({ Action = "Release" })
	elseif kc == Enum.KeyCode.X then
		Net.Event("Cart"):FireServer({ Action = "Open" })
	elseif kc == Enum.KeyCode.H then
		toggleEmotes()
	elseif kc == Enum.KeyCode.Q then
		local inv = ClientState.Inventory
		if inv.Selected and inv.Selected > 0 and inv.Slots[inv.Selected] then
			Net.Event("InvAction"):FireServer({ Action = "Drop", Slot = inv.Selected, Qty = 1 })
		end
	elseif kc == Enum.KeyCode.Space and player:GetAttribute("Hidden") then
		Net.Event("LeaveHiding"):FireServer()
	elseif kc == Enum.KeyCode.Escape then
		InventoryUI.Toggle(false)
		MapUI.Toggle(false)
	elseif kc == Enum.KeyCode.DPadLeft or kc == Enum.KeyCode.DPadRight then
		local inv = ClientState.Inventory
		local cur = inv.Selected or 0
		local nextSlot = (cur + (if kc == Enum.KeyCode.DPadRight then 1 else -1) - 1) % 6 + 1
		Net.Event("Hotbar"):FireServer(nextSlot)
	elseif t == Enum.UserInputType.MouseButton1 or kc == Enum.KeyCode.ButtonR2 then
		if not ClientState.IsBusy() then
			Controls.Use()
		end
	else
		local digits = {
			[Enum.KeyCode.One] = 1,
			[Enum.KeyCode.Two] = 2,
			[Enum.KeyCode.Three] = 3,
			[Enum.KeyCode.Four] = 4,
			[Enum.KeyCode.Five] = 5,
			[Enum.KeyCode.Six] = 6,
		}
		local d = digits[kc]
		if d then
			Net.Event("Hotbar"):FireServer(d)
		end
	end
	sendInput()
end

local function onInputEnded(input: InputObject)
	local kc = input.KeyCode
	if kc == Enum.KeyCode.LeftShift or kc == Enum.KeyCode.ButtonL3 then
		sprint = false
	elseif kc == Enum.KeyCode.LeftControl then
		crouch = false
	end
	sendInput()
end

--============================ TOUCH ============================--
local function buildTouch()
	local gui, root = UI.screen("MSL_Touch", 3)
	touchGui = gui
	local box = UI.make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -200), Size = UDim2.fromOffset(200, 230) }, root)
	local function btn(text, x, y, fn, holdEnd)
		local b = UI.button(box, { Text = text, Size = UDim2.fromOffset(66, 66), Position = UDim2.fromOffset(x, y), TextSize = 12, Radius = 33 })
		b.BackgroundTransparency = 0.3
		if holdEnd then
			b.MouseButton1Down:Connect(fn)
			b.MouseButton1Up:Connect(holdEnd)
		else
			b.Activated:Connect(fn)
		end
		return b
	end
	btn("USE", 130, 160, Controls.Use)
	btn("RUN", 130, 84, function()
		sprint = true
		crouch = false
		sendInput()
	end, function()
		sprint = false
		sendInput()
	end)
	btn("SNEAK", 54, 160, function()
		crouch = not crouch
		sendInput()
	end)
	btn("LIGHT", 54, 84, function()
		Net.Event("Flashlight"):FireServer()
	end)
	btn("BAG", 130, 8, function()
		InventoryUI.Toggle()
	end)
	btn("BUILD", 54, 8, function()
		BuildUI.Toggle()
	end)
	local top = UI.make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -260, 0, 18), Size = UDim2.fromOffset(240, 40) }, root)
	UI.list(top, 6, true, Enum.HorizontalAlignment.Right)
	for i, def in { { "MAP", function()
		MapUI.Toggle()
	end }, { "CART", function()
		Net.Event("Cart"):FireServer({ Action = "Open" })
	end }, { "DROP", function()
		Net.Event("Cart"):FireServer({ Action = "Release" })
	end } } do
		local b = UI.button(top, { Text = def[1], Size = UDim2.fromOffset(70, 34), TextSize = 11, LayoutOrder = i })
		b.Activated:Connect(def[2])
	end
	gui.Enabled = false
end

function Controls.SetVisible(on: boolean)
	if touchGui then
		touchGui.Enabled = on and UI.IsTouch()
	end
	if not on then
		sprint, crouch = false, false
		sendInput()
		if emoteMenu then
			emoteMenu.Visible = false
		end
	end
end

function Controls.Init()
	UserInputService.InputBegan:Connect(onInput)
	UserInputService.InputEnded:Connect(onInputEnded)
	buildTouch()
	local _, root = UI.screen("MSL_Emotes", 5)
	emoteMenu = UI.make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -110), Size = UDim2.fromOffset(800, 40), Visible = false }, root)
	-- keep the Tab key from opening the player list while in the store
	ContextActionService:BindActionAtPriority("MSL_Inventory", function(_, state)
		if not inRun() then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin and not BuildUI.IsActive() then
			InventoryUI.Toggle()
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.Tab)
	-- re-send held keys after respawn
	player.CharacterAdded:Connect(function()
		lastSent = { Sprint = not sprint, Crouch = not crouch }
		sendInput()
	end)
end

return Controls
