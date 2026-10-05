--[[
	Cosmetics catalog. Purely visual: nothing here changes speed, hitbox or tagging.
	Add an item = add a row. Categories: Trail, Aura, Title, TagEffect.
]]

local Cosmetics = {}

Cosmetics.Categories = { "Trail", "Aura", "Title", "TagEffect" }
Cosmetics.CategoryNames = { Trail = "Trails", Aura = "Auras", Title = "Titles", TagEffect = "Tag Effects" }

local hex = Color3.fromHex
Cosmetics.Items = {
	-- Trails
	{ Id = "Trail_Sky", Category = "Trail", Name = "Sky Trail", Price = 100, Color = hex("4cc3ff"), Color2 = hex("ffffff") },
	{ Id = "Trail_Fire", Category = "Trail", Name = "Fire Trail", Price = 250, Color = hex("ffbb22"), Color2 = hex("ff4a2e") },
	{ Id = "Trail_Rainbow", Category = "Trail", Name = "Rainbow Trail", Price = 600, Color = hex("ff4f6d"), Color2 = hex("6a3df0"), Rainbow = true },
	-- Auras
	{ Id = "Aura_Sparkle", Category = "Aura", Name = "Sparkles", Price = 150, Color = hex("ffd23f") },
	{ Id = "Aura_Hearts", Category = "Aura", Name = "Pink Glow", Price = 300, Color = hex("ff7ab6") },
	{ Id = "Aura_Galaxy", Category = "Aura", Name = "Galaxy", Price = 750, Color = hex("9b4dff") },
	-- Titles (shown under your name)
	{ Id = "Title_Speedy", Category = "Title", Name = "Speedy", Price = 50, Color = hex("4cc3ff") },
	{ Id = "Title_Sneaky", Category = "Title", Name = "Sneaky", Price = 120, Color = hex("b98cff") },
	{ Id = "Title_Legend", Category = "Title", Name = "Legend", Price = 1000, Color = hex("ffd23f") },
	-- Tag effects (burst when YOU catch someone)
	{ Id = "Tag_Confetti", Category = "TagEffect", Name = "Confetti Pop", Price = 200, Color = hex("ff7ab6") },
	{ Id = "Tag_Lightning", Category = "TagEffect", Name = "Zap", Price = 400, Color = hex("ffe94a") },
	{ Id = "Tag_Slime", Category = "TagEffect", Name = "Slime Splash", Price = 400, Color = hex("7dff4a") },
}

local byId = {}
for _, item in Cosmetics.Items do
	byId[item.Id] = item
end

function Cosmetics.Get(id: string?)
	return if id then byId[id] else nil
end

return Cosmetics
