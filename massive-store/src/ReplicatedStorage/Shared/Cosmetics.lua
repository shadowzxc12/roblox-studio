--[[
	Cosmetics: bought with Store Credits (earned by playing, optionally bought with Robux).
	Purely visual. Nothing here changes survival stats.

	Slots: Title, Outfit (player skin), Flashlight (beam colour), Cart (cart paint),
	       Effect (player effect), Emote (owned emotes are all usable, not equipped),
	       Decor (unlocks base decorations)
]]

local Cosmetics = {}

Cosmetics.Slots = { "Title", "Outfit", "Flashlight", "Cart", "Effect", "Emote", "Decor" }
Cosmetics.SlotNames = {
	Title = "TITLES",
	Outfit = "OUTFITS",
	Flashlight = "FLASHLIGHT SKINS",
	Cart = "CART PAINT",
	Effect = "PLAYER EFFECTS",
	Emote = "EMOTES",
	Decor = "BASE DECOR",
}

Cosmetics.List = {
	-- titles (some are unlocked by level, see Progression)
	{ Id = "Shopper", Slot = "Title", Name = "Shopper", Price = 0, Color = "c8ccd4", Free = true },
	{ Id = "NightShift", Slot = "Title", Name = "Night Shift", Price = 150, Color = "5ab4ff" },
	{ Id = "Stocker", Slot = "Title", Name = "Shelf Stocker", Price = 150, Color = "ff9f43" },
	{ Id = "CouponQueen", Slot = "Title", Name = "Coupon Royalty", Price = 300, Color = "ff7ab6" },
	{ Id = "CartKing", Slot = "Title", Name = "Cart Commander", Price = 400, Color = "ffc61a" },
	{ Id = "Insomniac", Slot = "Title", Name = "Insomniac", Price = 600, Color = "b76bff" },
	{ Id = "NightWalker", Slot = "Title", Name = "Night Walker", Price = 0, Color = "7cff4f", Level = 10 },
	{ Id = "StoreVeteran", Slot = "Title", Name = "Store Veteran", Price = 0, Color = "ffb31a", Level = 20 },
	{ Id = "LocustBane", Slot = "Title", Name = "Locust Bane", Price = 0, Color = "ff3b3b", Level = 30 },
	{ Id = "AfterHours", Slot = "Title", Name = "After Hours", Price = 0, Color = "e8e8ff", Level = 50 },

	-- outfits (skins): worn over your avatar
	{ Id = "OutfitNone", Slot = "Outfit", Name = "Your Avatar", Price = 0, Free = true },
	{ Id = "OutfitClerk", Slot = "Outfit", Name = "Store Clerk Vest", Price = 180, Color = "ffc61a", Accent = "c4161c" },
	{ Id = "OutfitJanitor", Slot = "Outfit", Name = "Night Janitor", Price = 260, Color = "1f8a8a", Accent = "e0e0e0" },
	{ Id = "OutfitSecurity", Slot = "Outfit", Name = "Security Guard", Price = 350, Color = "1c2a4a", Accent = "ffd23f" },
	{ Id = "OutfitHoodie", Slot = "Outfit", Name = "Midnight Hoodie", Price = 420, Color = "15151a", Accent = "ff3b3b" },
	{ Id = "OutfitHazmat", Slot = "Outfit", Name = "Hazmat Suit", Price = 900, Color = "f2d22e", Accent = "2b2b2b" },

	-- flashlight beams
	{ Id = "BeamWarm", Slot = "Flashlight", Name = "Warm White", Price = 0, Color = "fff1c9", Free = true },
	{ Id = "BeamCool", Slot = "Flashlight", Name = "Cool LED", Price = 120, Color = "d4ecff" },
	{ Id = "BeamAmber", Slot = "Flashlight", Name = "Amber", Price = 200, Color = "ffb347" },
	{ Id = "BeamMint", Slot = "Flashlight", Name = "Mint", Price = 250, Color = "a8ffd8" },
	{ Id = "BeamViolet", Slot = "Flashlight", Name = "Black Light", Price = 450, Color = "b98cff" },

	-- carts
	{ Id = "CartChrome", Slot = "Cart", Name = "Classic Chrome", Price = 0, Color = "b9c1c9", Free = true },
	{ Id = "CartRed", Slot = "Cart", Name = "Fire Red", Price = 150, Color = "e53935" },
	{ Id = "CartMint", Slot = "Cart", Name = "Retro Mint", Price = 200, Color = "7fe0c0" },
	{ Id = "CartGold", Slot = "Cart", Name = "Gold Member", Price = 800, Color = "ffc61a", Material = "Foil" },
	{ Id = "CartNeon", Slot = "Cart", Name = "Neon Runner", Price = 650, Color = "39ff8e", Material = "Neon" },

	-- player effects
	{ Id = "FxNone", Slot = "Effect", Name = "None", Price = 0, Free = true },
	{ Id = "FxDust", Slot = "Effect", Name = "Store Dust", Price = 200, Color = "d8cbb0" },
	{ Id = "FxFireflies", Slot = "Effect", Name = "Fireflies", Price = 450, Color = "f9ff7a" },
	{ Id = "FxPrices", Slot = "Effect", Name = "Price Tags", Price = 550, Color = "ffc61a" },
	{ Id = "FxEmbers", Slot = "Effect", Name = "Embers", Price = 700, Color = "ff7a2e" },

	-- emotes (default Roblox emote animations)
	{ Id = "EmoteWave", Slot = "Emote", Name = "Wave", Price = 0, Free = true, Anim = "rbxassetid://507770239" },
	{ Id = "EmotePoint", Slot = "Emote", Name = "Point", Price = 0, Free = true, Anim = "rbxassetid://507770453" },
	{ Id = "EmoteCheer", Slot = "Emote", Name = "Cheer", Price = 100, Anim = "rbxassetid://507770677" },
	{ Id = "EmoteLaugh", Slot = "Emote", Name = "Laugh", Price = 100, Anim = "rbxassetid://507770818" },
	{ Id = "EmoteDance", Slot = "Emote", Name = "Aisle Dance", Price = 250, Anim = "rbxassetid://507771019" },
	{ Id = "EmoteDance2", Slot = "Emote", Name = "Checkout Groove", Price = 300, Anim = "rbxassetid://507776043" },
	{ Id = "EmoteDance3", Slot = "Emote", Name = "Closing Time", Price = 350, Anim = "rbxassetid://507777268" },

	-- base decorations (unlock the Decor buildables)
	{ Id = "DecoNeon", Slot = "Decor", Name = "Neon 'OPEN' Sign", Price = 220, Color = "ff2e7e" },
	{ Id = "DecoPlant", Slot = "Decor", Name = "Potted Palm", Price = 120, Color = "43a047" },
	{ Id = "DecoFlag", Slot = "Decor", Name = "Survivor Flag", Price = 180, Color = "ffc61a" },
	{ Id = "DecoGnome", Slot = "Decor", Name = "Garden Gnome", Price = 260, Color = "e53935" },
}

Cosmetics.ById = {}
for i, c in Cosmetics.List do
	c.Order = i
	Cosmetics.ById[c.Id] = c
end

Cosmetics.Defaults = { Title = "Shopper", Outfit = "OutfitNone", Flashlight = "BeamWarm", Cart = "CartChrome", Effect = "FxNone" }

function Cosmetics.Get(id: string)
	return Cosmetics.ById[id]
end

-- does this player own it? (data = profile data, level = player level)
function Cosmetics.Owns(data, level: number, id: string): boolean
	local c = Cosmetics.ById[id]
	if not c then
		return false
	end
	if c.Free then
		return true
	end
	if c.Level then
		return level >= c.Level
	end
	return data.Owned ~= nil and data.Owned[id] == true
end

return Cosmetics
