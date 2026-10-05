-- Kiddo Shop: odmeny za Robux nákupy (Developer Products).
-- Vlož ako Script do ServerScriptService. Bez tohto Roblox nákup nepotvrdí
-- a hráčovi vráti Robux.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

-- productId -> čo hráč dostane. Doplň rovnaké ID ako v PRODUCTS v KiddoShop.client.lua.
local REWARDS: { [number]: (Player) -> () } = {
	-- [123456789] = function(plr)
	-- 	plr.leaderstats.Cash.Value += 100000
	-- end,
}

MarketplaceService.ProcessReceipt = function(receipt)
	local plr = Players:GetPlayerByUserId(receipt.PlayerId)
	local reward = REWARDS[receipt.ProductId]
	if not plr or not reward then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, err = pcall(reward, plr)
	if not ok then
		warn("KiddoShop reward failed:", err)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end
