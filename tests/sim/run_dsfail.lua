local SIM = G.SIM_REF
game._props.PrivateServerId = ""
G.DATA["Player_101"] = { Coins = 999, XP = 50 }
G.DATASTORE_FAIL = true
task.spawn(function()
	SIM.runChunk(SIM.SSS.ServerMain)
end)
local p = G.AddPlayer("Unlucky")
SIM.runUntil(30)
print("DataLoaded:", p:GetAttribute("DataLoaded"))
G.DATASTORE_FAIL = false
G.RemovePlayer(p)
SIM.runUntil(40)
print("store still has coins:", G.DATA["Player_101"].Coins)
