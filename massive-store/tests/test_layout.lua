local StoreLayout = Load("StoreLayout")
local t0 = os.clock()
for _, seed in { 1, 42, 1337, 98765, 31337 } do
	local plan = StoreLayout.Generate(seed)
	local client = StoreLayout.Generate(seed, { SkipProps = true })
	-- server and client agree on zones
	for id, cell in plan.Cells do
		assert(client.Cells[id].Zone == cell.Zone, "zone mismatch")
	end
	-- nav connectivity: everything reachable from the entrance when gates are open
	local nav = plan.Nav
	local start = nav.CellNode[plan.Zones[1].Cells[1]]
	local seen, queue = { [start] = true }, { start }
	local seenClosed = { [start] = true }
	while #queue > 0 do
		local n = table.remove(queue)
		for _, l in nav.Links[n] do
			if not seen[l.To] then seen[l.To] = true table.insert(queue, l.To) end
		end
	end
	queue = { start }
	while #queue > 0 do
		local n = table.remove(queue)
		for _, l in nav.Links[n] do
			if not l.Gate and not seenClosed[l.To] then seenClosed[l.To] = true table.insert(queue, l.To) end
		end
	end
	local total, reach, reachClosed = 0, 0, 0
	local unreachable = {}
	for id, cell in plan.Cells do
		if not cell.Solid then
			total += 1
			local node = nav.CellNode[id]
			if seen[node] then reach += 1 else table.insert(unreachable, cell.Type .. "@" .. cell.Level) end
			if seenClosed[node] then reachClosed += 1 end
		end
	end
	local zoneCounts = {}
	for _, z in plan.Zones do zoneCounts[z.Type] = (zoneCounts[z.Type] or 0) + #z.Cells end
	local gates = 0
	for _ in plan.Gates do gates += 1 end
	local locked, hidden = 0, 0
	for _, r in plan.Rooms do if r.Status == "Locked" then locked += 1 elseif r.Status == "Hidden" then hidden += 1 end end
	print(string.format("seed %d: cells %d reach %d (gates closed %d) props %d loot %d hide %d carts %d gens %d lights %d doors %d roomdoors %d rooms %d locked %d hidden %d gates %d",
		seed, total, reach, reachClosed, #plan.Props, #plan.LootPoints, #plan.HidingSpots, #plan.CartSpawns, #plan.GeneratorSpots, #plan.Lights, #plan.StoreDoors, #plan.RoomDoors, #plan.Rooms, locked, hidden, gates))
	if reach ~= total then print("UNREACHABLE", table.concat(unreachable, ", ")) end
	assert(reach == total, "store not fully connected")
	-- main floor without gates must contain all normal zones
	for id, cell in plan.Cells do
		if not cell.Solid and cell.Level == 0 and cell.Type ~= "Sealed" and cell.Type ~= "Stairwell" then
			assert(seenClosed[nav.CellNode[id]], "main floor cell unreachable without gates: " .. cell.Type)
		end
	end
	-- lanes are clear: no prop box intersects the lane strips of its cell (except stair/tunnel ramps)
	local bad = 0
	local S, Lh = plan.CellSize, plan.LaneWidth / 2
	for _, p in plan.Props do
		if p.K ~= "Ball" and not p.N and not p.NC then
			local cell = StoreLayout.CellAt(plan, p.X, p.Y, p.Z)
			if cell and not cell.Stair and cell.Type ~= "Escalators" then
				local r = math.max(p.W, p.D) / 2
				local yawRad = math.rad(p.Yaw or 0)
				local ex = math.abs(math.cos(yawRad)) * p.W / 2 + math.abs(math.sin(yawRad)) * p.D / 2
				local ez = math.abs(math.sin(yawRad)) * p.W / 2 + math.abs(math.cos(yawRad)) * p.D / 2
				local dx, dz = p.X - cell.X, p.Z - cell.Z
				local bottom = p.Y - p.H / 2
				local inX = math.abs(dx) - ex < Lh - 0.3 -- overlaps the Z lane
				local inZ = math.abs(dz) - ez < Lh - 0.3 -- overlaps the X lane
				if (inX or inZ) and bottom < cell.Y + 11.5 and not p.Roll and not p.Pitch then
					bad += 1
					if bad <= 8 then print("LANE BLOCK", cell.Type, p.K, p.X - cell.X, p.Z - cell.Z, p.W, p.H, p.D, p.Yaw) end
				end
			end
		end
	end
	assert(bad == 0, "props in lanes: " .. bad)
	assert(#plan.LootPoints > 3000, "too few loot points")
end
print(string.format("ok in %.2fs", os.clock() - t0))
