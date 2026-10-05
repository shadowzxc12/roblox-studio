--[[
	Progression: what Survival XP levels unlock. Everything here is earned by playing;
	nothing that helps you survive can be bought with Robux.
]]

local Util = require(script.Parent.Util)

local Progression = {}

-- level -> unlocks gained at that level
Progression.Unlocks = {
	{ Level = 2, Kind = "Slots", Value = 2, Text = "+2 inventory slots" },
	{ Level = 2, Kind = "Build", Value = "Ramp", Text = "Ramps & Generators" },
	{ Level = 3, Kind = "Tier", Value = 2, Text = "METAL building tier" },
	{ Level = 4, Kind = "Flashlight", Value = 2, Text = "Flashlight II (brighter, lasts longer)" },
	{ Level = 5, Kind = "Slots", Value = 4, Text = "Backpack: +4 inventory slots" },
	{ Level = 5, Kind = "Build", Value = "Camera", Text = "Security Cameras" },
	{ Level = 6, Kind = "Cart", Value = 2, Text = "Cart II (bigger basket, faster wheels)" },
	{ Level = 7, Kind = "Build", Value = "ShockTrap", Text = "Shock Plates" },
	{ Level = 8, Kind = "Tier", Value = 3, Text = "REINFORCED building tier" },
	{ Level = 9, Kind = "Build", Value = "Turret", Text = "Sentry Turrets" },
	{ Level = 10, Kind = "Flashlight", Value = 3, Text = "Flashlight III" },
	{ Level = 10, Kind = "Title", Value = "NightWalker", Text = "Title: Night Walker" },
	{ Level = 12, Kind = "Slots", Value = 4, Text = "Backpack II: +4 inventory slots" },
	{ Level = 14, Kind = "Cart", Value = 3, Text = "Cart III (armored, smooth wheels)" },
	{ Level = 16, Kind = "Tier", Value = 4, Text = "ADVANCED building tier" },
	{ Level = 20, Kind = "Slots", Value = 4, Text = "Backpack III: +4 inventory slots" },
	{ Level = 20, Kind = "Title", Value = "StoreVeteran", Text = "Title: Store Veteran" },
	{ Level = 30, Kind = "Title", Value = "LocustBane", Text = "Title: Locust Bane" },
	{ Level = 50, Kind = "Title", Value = "AfterHours", Text = "Title: After Hours" },
}

Progression.BaseSlots = 12

Progression.FlashlightTiers = {
	{ Range = 55, Brightness = 2.4, Angle = 55, Drain = 0.55 },
	{ Range = 75, Brightness = 3, Angle = 60, Drain = 0.42 },
	{ Range = 95, Brightness = 3.6, Angle = 65, Drain = 0.32 },
}

function Progression.Perks(level: number)
	local perks = { Slots = Progression.BaseSlots, Tier = 1, Flashlight = 1, Cart = 1, Builds = {}, Titles = {} }
	for _, u in Progression.Unlocks do
		if level >= u.Level then
			if u.Kind == "Slots" then
				perks.Slots += u.Value
			elseif u.Kind == "Tier" then
				perks.Tier = math.max(perks.Tier, u.Value)
			elseif u.Kind == "Flashlight" then
				perks.Flashlight = math.max(perks.Flashlight, u.Value)
			elseif u.Kind == "Cart" then
				perks.Cart = math.max(perks.Cart, u.Value)
			elseif u.Kind == "Build" then
				perks.Builds[u.Value] = true
			elseif u.Kind == "Title" then
				perks.Titles[u.Value] = true
			end
		end
	end
	return perks
end

function Progression.PerksFromXP(xp: number)
	return Progression.Perks((Util.LevelFromXP(xp)))
end

-- unlocks gained when going from level a to level b
function Progression.NewUnlocks(a: number, b: number)
	local out = {}
	for _, u in Progression.Unlocks do
		if u.Level > a and u.Level <= b then
			table.insert(out, u)
		end
	end
	return out
end

-- next unlock after `level` (for the "next reward" bar)
function Progression.NextUnlock(level: number)
	for _, u in Progression.Unlocks do
		if u.Level > level then
			return u
		end
	end
	return nil
end

return Progression
