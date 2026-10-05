--[[
	Holding: how items sit in your hand and which animation an item plays.
	Shared by the server (third-person held item, action broadcast), the character animator and
	the first-person view model, so every view of a held item agrees.

	Item space (Models.Item): +Y is up, -Z is the front (lens, blade, label).
	Hand space: the R15 RightGripAttachment convention — CFrame.new(0, -0.15, 0) * Angles(-90°, 0, 0)
	on RightHand (R6: (0, -1, 0) on "Right Arm"). With the forearm held forward (every hold pose
	does that) item +Y points up and item -Z points where you look.

	HoldKind:  "Aim"     flashlight: arm out, pointing where you look
	           "Melee"   hammer / crowbar / baton: fist at the hip, head up
	           "TwoHand" planks, sheets, kits, jugs, big boxes: carried in front with both hands
	           "OneHand" food, cans, batteries, cards: held in front at chest height
	Actions (character attribute "Action", counter "ActionN"):
	           Swing, Eat, Drink, Heal, Throw, Place, Reload, Click, Build, Pickup, Revive
]]

local Items = require(script.Parent.Items)

local Holding = {}

local GRIP_R15 = CFrame.new(0, -0.15, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
local GRIP_R6 = CFrame.new(0, -1, 0) * CFrame.Angles(-math.pi / 2, 0, 0)

Holding.ActionTime = {
	Swing = 0.5,
	Eat = 1.2,
	Drink = 1.2,
	Heal = 1.1,
	Throw = 0.65,
	Place = 0.8,
	Reload = 0.9,
	Click = 0.25,
	Build = 0.45,
	Pickup = 0.55,
	Revive = 1.2,
}

function Holding.Kind(itemId: string?): string?
	local item = itemId and Items.Get(itemId)
	if not item then
		return nil
	end
	local tool = item.Tool
	if tool == "Flashlight" then
		return "Aim"
	elseif tool == "Hammer" or tool == "Crowbar" or tool == "StunBaton" then
		return "Melee"
	end
	local sh = item.Shape
	if sh == "Plank" or sh == "Sheet" or sh == "Kit" or sh == "Jug" or sh == "Brick" then
		return "TwoHand"
	end
	local s = item.Size
	if s and math.max(s[1], s[2], s[3]) >= 1.4 then
		return "TwoHand"
	end
	return "OneHand"
end

-- the animation an item plays when used
function Holding.ActionFor(itemId: string?): string?
	local item = itemId and Items.Get(itemId)
	if not item then
		return nil
	end
	local tool = item.Tool
	if tool == "Hammer" or tool == "Crowbar" or tool == "StunBaton" then
		return "Swing"
	elseif tool == "Flare" then
		return "Throw"
	elseif tool == "NoiseMaker" or tool == "SupplyBeacon" then
		return "Place"
	elseif tool == "Flashlight" or tool == "NightVision" or tool == "StoreMap" or tool == "Keycard" then
		return "Click"
	elseif tool == "Repellent" then
		return "Throw"
	end
	if item.Category == "Medical" then
		return "Heal"
	elseif item.Category == "Battery" or item.Category == "Fuel" then
		return "Reload"
	elseif item.Category == "Food" then
		if item.Shape == "Bottle" or item.Shape == "Can" then
			return "Drink"
		end
		return "Eat"
	end
	return "Click"
end

-- where the item sits relative to the grip point (item space)
function Holding.ItemOffset(itemId: string): CFrame
	local item = Items.Get(itemId)
	if not item then
		return CFrame.new()
	end
	local sx, sy, sz = item.Size[1], item.Size[2], item.Size[3]
	local kind = Holding.Kind(itemId)
	local tool = item.Tool
	if tool == "Flashlight" then
		-- hand around the body, lens forward
		return CFrame.new(0, 0, -sz * 0.18)
	elseif tool == "Hammer" or tool == "StunBaton" then
		return CFrame.new(0, sy * 0.32, 0)
	elseif tool == "Crowbar" then
		return CFrame.new(0, sy * 0.36, 0)
	elseif kind == "TwoHand" then
		-- between both hands, a little forward and lower (hands under it)
		return CFrame.new(-0.85, 0.05 + sy / 2 - 0.15, -sz / 2 - 0.25)
	elseif item.Shape == "Card" then
		return CFrame.new(0, 0.05, -0.25) * CFrame.Angles(math.rad(70), 0, 0)
	end
	-- small items: palm behind the item
	return CFrame.new(0, sy * 0.1, -sz / 2 - 0.08)
end

-- the held item's pivot relative to the hand part (R15 RightHand or R6 Right Arm)
function Holding.Grip(itemId: string, r6: boolean?): CFrame
	return (if r6 then GRIP_R6 else GRIP_R15) * Holding.ItemOffset(itemId)
end

return Holding
