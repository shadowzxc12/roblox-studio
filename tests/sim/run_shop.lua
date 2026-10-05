local SIM = G.SIM_REF
game._props.PrivateServerId = ""
G.DATA["Player_101"] = { Coins = 120, XP = 0, OwnedCosmetics = {}, Equipped = { Trail = "" } } -- old/partial save -> reconcile
task.spawn(function()
	SIM.runChunk(SIM.SSS.ServerMain)
end)
local p = G.AddPlayer("Shopper")
local q = G.AddPlayer("Offline") -- DataStore fails for this one
SIM.runUntil(1)
local shop = SIM.RS.Remotes.RequestShop._props.OnServerInvoke
local function try(req)
	local r = shop(p, req)
	print(string.format("%-40s -> ok=%s %s", tostring(req.Action) .. " " .. tostring(req.Id or req.Category), tostring(r.Ok), r.Message))
end
try({ Action = "Buy", Id = "Trail_Fire" }) -- 250 > 120 coins
try({ Action = "Buy", Id = "Trail_Sky" }) -- 100 ok
try({ Action = "Buy", Id = "Trail_Sky" }) -- already owned
try({ Action = "Equip", Id = "Aura_Galaxy" }) -- not owned
try({ Action = "Buy", Id = "NotAThing" })
try({ Action = "Unequip", Category = "Trail" })
try({ Action = "Unequip", Category = "Coins" })
local bad = shop(p, "garbage")
print("garbage ->", bad.Ok, bad.Message)
for i = 1, 10 do
	shop(p, { Action = "Equip", Id = "Trail_Sky" })
end
local r = shop(p, { Action = "Equip", Id = "Trail_Sky" })
print("spam ->", r.Ok, r.Message)
-- settings
local set = SIM.RS.Remotes.RequestSettings._props.OnServerEvent
set:Fire(p, "Music", false)
set:Fire(p, "Coins", true)
set:Fire(p, "SoundEffects", "yes")
G.DATASTORE_FAIL = false
_G = nil
G.RemovePlayer(p)
SIM.runUntil(10)
local d = G.DATA["Player_101"]
print("saved coins", d.Coins, "owned Trail_Sky", d.OwnedCosmetics.Trail_Sky, "Music", d.Settings.Music, "hasCoinsSetting", d.Settings.Coins, "SFX", d.Settings.SoundEffects, "Wins field", d.Wins)
