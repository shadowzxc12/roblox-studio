--[[
	PromptUI: draws every ProximityPrompt in the game's own style (Custom prompt style).
	  [E]  Pick up
	       Canned Beans ×2        <- object text coloured by rarity
	Hold prompts show a filling ring. On touch screens the card itself is the button.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent.UI)

local PromptUI = {}

local player = Players.LocalPlayer
local C = UI.C
local active: { [ProximityPrompt]: any } = {}
local gui: Folder

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		return UI.KeyName(prompt.GamepadKeyCode)
	elseif inputType == Enum.ProximityPromptInputType.Touch then
		return "TAP"
	end
	return UI.KeyName(prompt.KeyboardKeyCode)
end

local function build(prompt: ProximityPrompt, inputType)
	local parent = prompt.Parent
	if not parent or (player.Character and prompt:IsDescendantOf(player.Character)) then
		return
	end
	local bb = UI.make("BillboardGui", {
		Name = "Prompt",
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(240, 64),
		StudsOffset = Vector3.new(0, 1.6, 0),
		LightInfluence = 0,
		ResetOnSpawn = false,
		Active = true,
		Adornee = parent,
		MaxDistance = 40,
	}, gui)
	local card = UI.make("TextButton", {
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.12,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(60, 48),
		AutomaticSize = Enum.AutomaticSize.X,
		BorderSizePixel = 0,
	}, bb)
	UI.corner(card, 9)
	local rarity = prompt:GetAttribute("Rarity")
	local accent = if rarity then UI.RarityColor(rarity) else C.Accent
	UI.stroke(card, accent, 1.5, 0.15)
	UI.pad(card, 8, 6)
	UI.list(card, 10, true).VerticalAlignment = Enum.VerticalAlignment.Center

	local key = keyText(prompt, inputType)
	local cap = UI.make("Frame", { BackgroundColor3 = C.Text, Size = UDim2.fromOffset(math.max(32, #key * 11 + 12), 32), LayoutOrder = 1 }, card)
	UI.corner(cap, 7)
	UI.text(cap, key, if #key > 2 then 12 else 17, Color3.fromHex("111111"), UI.Title, { TextXAlignment = Enum.TextXAlignment.Center })
	local ring = UI.make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4 }, cap)
	local ringStroke = UI.stroke(ring, accent, 3, 1)
	UI.corner(ring, 7)

	local texts = UI.make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(10, 36), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 }, card)
	UI.list(texts, 0)
	local action = UI.text(texts, prompt.ActionText, 15, C.Text, UI.Title, { Size = UDim2.fromOffset(0, 19), AutomaticSize = Enum.AutomaticSize.X })
	local object = UI.text(texts, prompt.ObjectText, 12, if rarity then accent else C.Muted, UI.Bold, { Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X })
	object.Visible = prompt.ObjectText ~= ""

	local scale = UI.make("UIScale", { Scale = 0.6 }, card)
	UI.tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)

	local holdTween = nil
	local rec = { Gui = bb, Ring = ringStroke, Action = action, Object = object }
	rec.Conns = {
		prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
			action.Text = prompt.ActionText
		end),
		prompt:GetPropertyChangedSignal("ObjectText"):Connect(function()
			object.Text = prompt.ObjectText
			object.Visible = prompt.ObjectText ~= ""
		end),
		prompt.PromptButtonHoldBegan:Connect(function()
			if prompt.HoldDuration > 0 then
				ringStroke.Transparency = 0
				ring.Size = UDim2.fromScale(0, 1)
				holdTween = TweenService:Create(ring, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
				holdTween:Play()
			end
		end),
		prompt.PromptButtonHoldEnded:Connect(function()
			if holdTween then
				holdTween:Cancel()
			end
			ringStroke.Transparency = 1
			ring.Size = UDim2.fromScale(1, 1)
		end),
		prompt.Triggered:Connect(function()
			UI.tween(scale, 0.08, { Scale = 0.9 })
			task.delay(0.08, function()
				UI.tween(scale, 0.12, { Scale = 1 })
			end)
		end),
	}
	-- touch / click on the card triggers the prompt
	card.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldBegin()
		end
	end)
	card.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldEnd()
		end
	end)
	active[prompt] = rec
end

local function destroy(prompt: ProximityPrompt)
	local rec = active[prompt]
	if not rec then
		return
	end
	active[prompt] = nil
	for _, c in rec.Conns do
		c:Disconnect()
	end
	rec.Gui:Destroy()
end

function PromptUI.Init()
	gui = UI.make("Folder", { Name = "Prompts" }, player:WaitForChild("PlayerGui"))
	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style == Enum.ProximityPromptStyle.Custom then
			build(prompt, inputType)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(destroy)
	UserInputService.LastInputTypeChanged:Connect(function()
		for prompt in active do
			destroy(prompt)
		end
	end)
end

return PromptUI
