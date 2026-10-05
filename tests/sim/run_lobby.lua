local SIM = G.SIM_REF
game._props.PrivateServerId = ""
task.spawn(function()
	SIM.runChunk(SIM.SSS.ServerMain)
end)
local ps = {}
for i = 1, G.TEST_PLAYERS do
	table.insert(ps, G.AddPlayer("L" .. i))
end
SIM.runUntil(3)
local remote = SIM.RS.Remotes.GameModeSelected
-- 3 players pick Normal, 1 picks Infection, 1 sends garbage
remote._props.OnServerEvent:Fire(ps[1], "Normal")
remote._props.OnServerEvent:Fire(ps[2], "Normal")
remote._props.OnServerEvent:Fire(ps[3], "Infection")
remote._props.OnServerEvent:Fire(ps[4], "HackMode")
remote._props.OnServerEvent:Fire(ps[4], { evil = true })
SIM.runUntil(30)
for _, f in G.FIRED do
	if f.remote == "MatchmakingStatus" or f.remote == "Notify" then
		local pl = f.payload
		print(string.format("[%5.1f] %s -> %s %s", f.t, f.remote, f.to, if type(pl) == "table" then (tostring(pl.State) .. " " .. tostring(pl.Mode) .. " " .. tostring(pl.Count) .. "/" .. tostring(pl.Max) .. " " .. tostring(pl.Message)) else tostring(pl)))
	end
end
for _, t in G.TELEPORTS do
	local names = {}
	for _, p in t.players do
		table.insert(names, p.Name)
	end
	print("TELEPORT", table.concat(names, ","), "code=" .. tostring(t.options and t.options._props.ReservedServerAccessCode))
end
for name, map in G.MEM do
	for k, v in map do
		print("MEM", name, k, v.Mode, v.Players, v.AccessCode)
	end
end
print("RoundState attr:", SIM.RS:GetAttribute("RoundState"), "ServerType:", SIM.RS:GetAttribute("ServerType"))
