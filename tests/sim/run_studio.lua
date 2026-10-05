local SIM = G.SIM_REF
game._props.PrivateServerId = ""
G.SIM_STUDIO = true
task.spawn(function()
	SIM.runChunk(SIM.SSS.ServerMain)
end)
local ps = {}
for i = 1, 3 do
	table.insert(ps, G.AddPlayer("S" .. i))
end
SIM.runUntil(3)
local remote = SIM.RS.Remotes.GameModeSelected
remote._props.OnServerEvent:Fire(ps[1], "Normal")
remote._props.OnServerEvent:Fire(ps[2], "Normal")
remote._props.OnServerEvent:Fire(ps[3], "Infection") -- different mode in the same Studio server -> rejected
SIM.runUntil(40)
SIM.RS.Remotes.ReturnToMenu._props.OnServerEvent:Fire(ps[2]) -- back to menu mid round
SIM.runUntil(60)
local last
for _, f in G.FIRED do
	local pl = f.payload
	if f.remote == "RoundState" and pl.RoundState ~= last then
		last = pl.RoundState
		print(string.format("[%5.1f] STATE %s %s", f.t, pl.RoundState, if pl.Waiting then "(waiting)" else ""))
	elseif f.remote == "MatchmakingStatus" or f.remote == "Notify" then
		print(string.format("[%5.1f] %s -> %s %s", f.t, f.remote, f.to, if type(pl) == "table" then tostring(pl.State) else tostring(pl)))
	elseif f.remote == "UpdateRole" and f.to == "*" then
		print(string.format("[%5.1f] FEED %s", f.t, pl.Text))
	end
end
for _, p in ps do
	print(p.Name, "InMatch=" .. tostring(p:GetAttribute("InMatch")), "Role=" .. tostring(p:GetAttribute("Role")))
end
