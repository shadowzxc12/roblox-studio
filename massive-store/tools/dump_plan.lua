-- Prints a generated store as plain lines for tools/render_map.py
local StoreLayout = Load("StoreLayout")
local Zones = Load("Zones")
local seed = SEED or 2024
local plan = StoreLayout.Generate(seed)
print(("PLAN %d %d %d %f %f %d"):format(plan.Cols, plan.Rows, plan.CellSize, plan.OriginX, plan.OriginZ, plan.BasementY))
for _, c in plan.CellList do
	print(("CELL %d %d %d %s %d %s"):format(c.Level, c.Col, c.Row, c.Type or "?", c.Zone or 0, Zones.Types[c.Type].Floor))
end
for _, z in plan.Zones do
	if z.Center then
		local c = plan.Cells[z.Center]
		print(("ZONE %d %f %f %s"):format(z.Level, c.X, c.Z, (z.Name:gsub(" ", "_"))))
	end
end
for _, w in plan.Walls do
	print(("WALL %d %f %f %s %d %s"):format(w.Level, w.X, w.Z, w.Dir, if w.Opening then 1 else 0, w.Gate or "-"))
end
for _, p in plan.Props do
	if p.Y - (p.H or 1) / 2 < (if p.Y < -1 then plan.BasementY + 14 else 14) then
		local level = if p.Y < -0.5 then -1 else 0
		print(("PROP %d %f %f %f %f %f %s"):format(level, p.X, p.Z, p.W or 1, p.D or 1, p.Yaw or 0, p.C or "999999"))
	end
end
for _, l in plan.LootPoints do
	print(("LOOT %d %f %f %f"):format(if l.Y < -0.5 then -1 else 0, l.X, l.Z, l.Bonus))
end
for _, c in plan.CartSpawns do
	print(("CART %d %f %f"):format(if c.Y < -0.5 then -1 else 0, c.X, c.Z))
end
for _, sp in plan.SpawnPoints do
	print(("SPAWN %f %f"):format(sp.X, sp.Z))
end
