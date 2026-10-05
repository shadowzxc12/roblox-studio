--[[
	Prompts: one place that creates ProximityPrompts and routes their triggers.
	Every prompt has an "Action" attribute; systems register a handler per action.
	Prompts use the Custom style, the client draws them (Controllers/PromptUI).
	The server re-checks distance and state in every handler (never trust the client).
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local RateLimiter = require(script.Parent.RateLimiter)

local Prompts = {}

local handlers: { [string]: (Player, ProximityPrompt) -> () } = {}
local holdHandlers: { [string]: { Began: any, Ended: any } } = {}
local limiter = RateLimiter.new(14, 2)

function Prompts.Register(action: string, fn: (Player, ProximityPrompt) -> ())
	handlers[action] = fn
end

function Prompts.RegisterHold(action: string, began, ended)
	holdHandlers[action] = { Began = began, Ended = ended }
end

--[[
	opts: { Hold = seconds, Distance = studs, Key = Enum.KeyCode, Name = string, Rarity = string,
	        RequiresLineOfSight = bool, Exclusivity = Enum.ProximityPromptExclusivity }
]]
function Prompts.Make(parent: Instance, action: string, actionText: string, objectText: string?, opts)
	opts = opts or {}
	local p = Instance.new("ProximityPrompt")
	p.Name = opts.Name or (action .. "Prompt")
	p.ActionText = actionText
	p.ObjectText = objectText or ""
	p.HoldDuration = opts.Hold or 0
	p.MaxActivationDistance = opts.Distance or 9
	p.RequiresLineOfSight = opts.RequiresLineOfSight or false
	p.Style = Enum.ProximityPromptStyle.Custom
	p.KeyboardKeyCode = opts.Key or Enum.KeyCode.E
	p.GamepadKeyCode = opts.GamepadKey or Enum.KeyCode.ButtonX
	p.Exclusivity = opts.Exclusivity or Enum.ProximityPromptExclusivity.OnePerButton
	p:SetAttribute("Action", action)
	if opts.Rarity then
		p:SetAttribute("Rarity", opts.Rarity)
	end
	if opts.Category then
		p:SetAttribute("Category", opts.Category)
	end
	p.Parent = parent
	return p
end

-- distance check helper for handlers
function Prompts.InReach(player: Player, position: Vector3, extra: number?): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	return (root.Position - position).Magnitude <= 14 + (extra or 0)
end

function Prompts.PromptPosition(prompt: ProximityPrompt): Vector3?
	local parent = prompt.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	elseif parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	elseif parent and parent:IsA("Model") then
		return parent:GetPivot().Position
	end
	return nil
end

function Prompts.Init()
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		local action = prompt:GetAttribute("Action")
		local fn = action and handlers[action]
		if not fn or not limiter:Allow(player) then
			return
		end
		local pos = Prompts.PromptPosition(prompt)
		if pos and not Prompts.InReach(player, pos, prompt.MaxActivationDistance) then
			return
		end
		if player:GetAttribute("Downed") or player:GetAttribute("Dead") then
			if action ~= "Hide" then
				return
			end
		end
		local ok, err = pcall(fn, player, prompt)
		if not ok then
			warn("[Prompts] " .. tostring(action) .. ": " .. tostring(err))
		end
	end)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, player)
		local action = prompt:GetAttribute("Action")
		local h = action and holdHandlers[action]
		if h and h.Began then
			task.spawn(h.Began, player, prompt)
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt, player)
		local action = prompt:GetAttribute("Action")
		local h = action and holdHandlers[action]
		if h and h.Ended then
			task.spawn(h.Ended, player, prompt)
		end
	end)
	Players.PlayerRemoving:Connect(function() end)
end

return Prompts
