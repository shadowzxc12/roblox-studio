--[[
	StoreLayout: generates the whole MASSIVE STORE from a seed, as plain data (no Instances).

	The server builds it into the Workspace (StoreBuilder). Clients run the same generator with
	{ SkipProps = true } to know zones/cells for the HUD and the store map, so nothing big has
	to be sent over the network. Every server gets a different seed = a different store.

	Structure
	  The store is a grid of 80x80 stud cells (main floor + an underground level).
	  Cells are grouped into departments (zones) by region growing. Inside a zone there are no
	  walls (big open halls); between zones there are walls with doorways. A random spanning tree
	  of zones guarantees every department is reachable, extra doorways create loops so players
	  can escape around things.
	  Every cell keeps a "+" shaped lane (LaneWidth) clear through its centre and all doorways
	  sit on those lanes, so the Locust can travel cell-centre -> doorway -> cell-centre in
	  straight lines (the nav graph). Furniture, shelves and rooms live in the four quadrants.

	Output (all positions are numbers; Y = floor height)
	  Cells, CellList, Zones, Edges, Walls, Props, LootPoints, HidingSpots, CartSpawns,
	  GeneratorSpots, SpawnPoints, Lights, Signs, StoreDoors, RoomDoors, Panels, Gates, Nav
]]

local Config = require(script.Parent.Config)
local Util = require(script.Parent.Util)
local Zones = require(script.Parent.Zones)

local StoreLayout = {}

local DIR4 = {
	{ dc = 1, dr = 0 },
	{ dc = -1, dr = 0 },
	{ dc = 0, dr = 1 },
	{ dc = 0, dr = -1 },
}

-- doorways into these departments get a door
local STAFF = { Employee = true, Security = true, Storage = true, Bathrooms = true, Maintenance = true }

local function key(level: number, c: number, r: number): number
	return (if level == 0 then 0 else 100000) + r * 1000 + c
end
StoreLayout.Key = key

function StoreLayout.Generate(seed: number, options)
	options = options or {}
	local M = options.Map or Config.Map
	local rng = Util.RNG(seed)
	local S, cols, rows = M.CellSize, M.Cols, M.Rows
	local H, BY = M.WallHeight, M.BasementY
	local BH = -1 - BY -- basement wall height (the main floor slab is its ceiling)
	local L = M.LaneWidth
	local Q = (S - L) / 2 -- quadrant size
	local QOFF = L / 2 + Q / 2
	local ox, oz = -cols * S / 2, -rows * S / 2
	local detail = M.ProductDetail or 1

	local plan = {
		Seed = seed,
		Cols = cols,
		Rows = rows,
		CellSize = S,
		OriginX = ox,
		OriginZ = oz,
		WallHeight = H,
		BasementY = BY,
		BasementHeight = BH,
		LaneWidth = L,
		Cells = {},
		CellList = {},
		Zones = {},
		Edges = {},
		Walls = {},
		Props = {},
		LootPoints = {},
		HidingSpots = {},
		CartSpawns = {},
		GeneratorSpots = {},
		SpawnPoints = {},
		Lights = {},
		Signs = {},
		StoreDoors = {},
		RoomDoors = {},
		Panels = {},
		Gates = {},
		Rooms = {},
		Nav = { Nodes = {}, Links = {}, CellNode = {} },
	}

	local function heightOf(level: number): number
		return if level == 0 then H else BH
	end

	--============================ CELLS ============================--
	local function addCell(level, c, r)
		local cell = {
			Id = key(level, c, r),
			Level = level,
			Col = c,
			Row = r,
			X = ox + (c - 0.5) * S,
			Z = oz + (r - 0.5) * S,
			Y = if level == 0 then 0 else BY,
		}
		plan.Cells[cell.Id] = cell
		table.insert(plan.CellList, cell)
		return cell
	end
	for r = 1, rows do
		for c = 1, cols do
			addCell(0, c, r)
		end
	end
	local bc0, bc1 = M.BasementCols[1], M.BasementCols[2]
	local br0, br1 = M.BasementRows[1], M.BasementRows[2]
	for r = br0, br1 do
		for c = bc0, bc1 do
			addCell(-1, c, r)
		end
	end
	local function cellAt(level, c, r)
		return plan.Cells[key(level, c, r)]
	end

	--============================ ZONES ============================--
	local function newZone(typeName: string, level: number)
		local z = { Id = #plan.Zones + 1, Type = typeName, Level = level, Cells = {}, Name = Zones.Types[typeName].Name, Target = 0 }
		table.insert(plan.Zones, z)
		return z
	end
	local function assign(cell, zone)
		cell.Zone = zone.Id
		cell.Type = zone.Type
		table.insert(zone.Cells, cell.Id)
	end

	local midC = math.floor(cols / 2)
	local entrance = newZone("Entrance", 0)
	for r = rows - 1, rows do
		for c = midC, midC + 1 do
			assign(cellAt(0, c, r), entrance)
		end
	end

	local docks = newZone("LoadingDocks", 0)
	local ds = rng:Int(2, cols - 6)
	for c = ds, ds + 4 do
		assign(cellAt(0, c, 1), docks)
	end

	local sealed = newZone("Sealed", 0)
	local sc = if rng:Chance(0.5) then 1 else cols - 2
	local sr = rng:Int(4, rows - 5)
	for r = sr, sr + 2 do
		for c = sc, sc + 2 do
			assign(cellAt(0, c, r), sealed)
		end
	end

	-- stairwells: a ramp from a main-floor cell down to the basement cell east of the one below it
	local solidZone = newZone("Solid", -1)
	local stairs = {}
	local tries = 0
	while #stairs < M.Stairwells and tries < 400 do
		tries += 1
		local c = rng:Int(math.max(bc0, 2), bc1 - 1)
		local r = rng:Int(math.max(br0, 2), br1)
		local main, west = cellAt(0, c, r), cellAt(0, c - 1, r)
		local below, landing = cellAt(-1, c, r), cellAt(-1, c + 1, r)
		local ok = main and west and below and landing and not main.Zone and not west.Zone and not landing.Solid
		if ok then
			for _, s in stairs do
				if math.abs(s.Row - r) < 2 and math.abs(s.Col - c) < 4 then
					ok = false
				end
			end
		end
		if ok then
			local z = newZone("Stairwell", 0)
			assign(main, z)
			main.Stair = true
			main.StairIndex = #stairs + 1
			below.Solid = true
			assign(below, solidZone)
			table.insert(stairs, main)
		end
	end

	local function neighbors(cell)
		local out = {}
		for _, d in DIR4 do
			local n = cellAt(cell.Level, cell.Col + d.dc, cell.Row + d.dr)
			if n then
				table.insert(out, n)
			end
		end
		return out
	end

	local function freeCells(level)
		local out = {}
		for _, cell in plan.CellList do
			if cell.Level == level and not cell.Zone then
				table.insert(out, cell)
			end
		end
		return out
	end

	local function seedZones(list, level)
		for _, z in list do
			if #z.Cells == 0 then
				local free = freeCells(level)
				local best, bestD = nil, -1
				for _ = 1, 16 do
					local cand = rng:Pick(free)
					if cand then
						local d = math.huge
						for _, other in plan.Zones do
							if other.Level == level and #other.Cells > 0 and other.Type ~= "Solid" then
								local oc = plan.Cells[other.Cells[1]]
								d = math.min(d, math.abs(oc.Col - cand.Col) + math.abs(oc.Row - cand.Row))
							end
						end
						if d > bestD then
							best, bestD = cand, d
						end
					end
				end
				if best then
					assign(best, z)
				end
			end
		end
	end

	local function grow(list)
		local progress = true
		while progress do
			progress = false
			local order = table.clone(list)
			rng:Shuffle(order)
			for _, z in order do
				if #z.Cells > 0 and #z.Cells < z.Target then
					local frontier = {}
					for _, id in z.Cells do
						for _, n in neighbors(plan.Cells[id]) do
							if not n.Zone then
								table.insert(frontier, n)
							end
						end
					end
					if #frontier > 0 then
						assign(rng:Pick(frontier), z)
						progress = true
					end
				end
			end
		end
	end

	-- leftover cells join a neighbouring zone, preferring the big departments
	-- (so small rooms like restrooms stay small)
	local NO_JOIN = { Sealed = true, Stairwell = true, Solid = true, Entrance = true, LoadingDocks = true }
	local function joinScore(z)
		local size = Zones.Types[z.Type].Size or 1
		return size * 10 - #z.Cells * 0.1
	end
	local function fillLeftovers(level)
		local changed = true
		while changed do
			changed = false
			for _, cell in freeCells(level) do
				local best = nil
				for _, n in neighbors(cell) do
					local z = n.Zone and plan.Zones[n.Zone]
					if z and not NO_JOIN[z.Type] and (not best or joinScore(z) > joinScore(best)) then
						best = z
					end
				end
				if best then
					assign(cell, best)
					changed = true
				end
			end
		end
		for _, cell in freeCells(level) do
			assign(cell, newZone(if level == 0 then "Storage" else "Tunnels", level))
		end
	end

	-- department sizes are scaled so they fill the floor (few leftovers)
	local function sizeFactor(order, level, extra)
		local total = extra or 0
		for _, t in order do
			local info = Zones.Types[t]
			total += info.Size * (info.Count or 1)
		end
		return #freeCells(level) / math.max(1, total)
	end
	local mainFactor = sizeFactor(Zones.GrowOrder, 0, Zones.Types.Warehouse.Size)

	-- main floor
	local growMain = {}
	local warehouse = newZone("Warehouse", 0)
	warehouse.Target = math.floor(Zones.Types.Warehouse.Size * mainFactor * rng:Range(0.85, 1.1) + 0.5)
	for c = ds, ds + 4 do
		local cl = cellAt(0, c, 2)
		if cl and not cl.Zone then
			assign(cl, warehouse)
		end
	end
	table.insert(growMain, warehouse)
	for _, t in Zones.GrowOrder do
		local info = Zones.Types[t]
		for _ = 1, info.Count or 1 do
			local z = newZone(t, 0)
			local f = if info.Size <= 3 then math.min(mainFactor, 1.4) else mainFactor
			z.Target = math.max(1, math.floor(info.Size * f * rng:Range(0.8, 1.15) + 0.5))
			table.insert(growMain, z)
		end
	end
	seedZones(growMain, 0)
	grow(growMain)
	fillLeftovers(0)

	-- basement
	local growBase = {}
	local baseFactor = sizeFactor(Zones.BasementOrder, -1)
	for _, t in Zones.BasementOrder do
		local info = Zones.Types[t]
		for _ = 1, info.Count or 1 do
			local z = newZone(t, -1)
			z.Target = math.max(1, math.floor(info.Size * baseFactor * rng:Range(0.85, 1.15) + 0.5))
			table.insert(growBase, z)
		end
	end
	seedZones(growBase, -1)
	grow(growBase)
	fillLeftovers(-1)

	-- zone centre cell (for signs / map labels)
	for _, z in plan.Zones do
		if #z.Cells > 0 then
			local sx, sz = 0, 0
			for _, id in z.Cells do
				sx += plan.Cells[id].X
				sz += plan.Cells[id].Z
			end
			sx /= #z.Cells
			sz /= #z.Cells
			local best, bestD = nil, math.huge
			for _, id in z.Cells do
				local cl = plan.Cells[id]
				local d = (cl.X - sx) ^ 2 + (cl.Z - sz) ^ 2
				if d < bestD then
					best, bestD = cl, d
				end
			end
			z.Center = best.Id
		end
	end

	--============================ EDGES / DOORWAYS ============================--
	for _, cell in plan.CellList do
		for _, d in { { 1, 0 }, { 0, 1 } } do
			local n = cellAt(cell.Level, cell.Col + d[1], cell.Row + d[2])
			if n then
				local e = {
					Id = #plan.Edges + 1,
					A = cell.Id,
					B = n.Id,
					Level = cell.Level,
					Dir = if d[1] == 1 then "EW" else "NS",
					X = (cell.X + n.X) / 2,
					Z = (cell.Z + n.Z) / 2,
					Y = cell.Y,
					Wall = true,
					Opening = false,
				}
				table.insert(plan.Edges, e)
			end
		end
	end

	local zonePairs, pairList = {}, {}
	for _, e in plan.Edges do
		local a, b = plan.Cells[e.A], plan.Cells[e.B]
		if a.Solid or b.Solid then
			-- the only way out of the solid block under a stairwell is the ramp exit (east side)
			if e.Dir == "EW" and a.Solid and cellAt(0, a.Col, a.Row).Stair and not b.Solid then
				e.Opening = true
				e.StairBottom = cellAt(0, a.Col, a.Row).Id
			end
		elseif a.Stair or b.Stair then
			if e.Dir == "EW" and b.Stair then
				e.Opening = true
				e.Gate = "Basement" .. b.StairIndex
			end
		elseif a.Zone == b.Zone then
			e.Wall = false
			e.Opening = true
		else
			local z1, z2 = math.min(a.Zone, b.Zone), math.max(a.Zone, b.Zone)
			local k = z1 * 1000 + z2
			local p = zonePairs[k]
			if not p then
				p = { Z1 = z1, Z2 = z2, Edges = {} }
				zonePairs[k] = p
				table.insert(pairList, p)
			end
			table.insert(p.Edges, e)
		end
	end

	local parent = {}
	local function find(x)
		while parent[x] and parent[x] ~= x do
			x = parent[x]
		end
		return x
	end
	local function pickEdge(list)
		-- prefer an edge in the middle of the shared boundary
		if #list >= 3 and rng:Chance(0.5) then
			return list[math.floor(#list / 2) + 1]
		end
		return list[rng:Int(1, #list)]
	end
	local function isSealedPair(p)
		return plan.Zones[p.Z1].Type == "Sealed" or plan.Zones[p.Z2].Type == "Sealed"
	end
	rng:Shuffle(pairList)
	for _, p in pairList do
		if not isSealedPair(p) then
			local r1, r2 = find(p.Z1), find(p.Z2)
			if r1 ~= r2 then
				parent[r1] = r2
				pickEdge(p.Edges).Opening = true
				p.Tree = true
			end
		end
	end
	for _, p in pairList do
		if not isSealedPair(p) then
			if not p.Tree and rng:Chance(0.6) then
				pickEdge(p.Edges).Opening = true
			end
			if #p.Edges >= 4 and rng:Chance(0.5) then
				pickEdge(p.Edges).Opening = true
			end
		end
	end
	local sealedPairs = {}
	for _, p in pairList do
		if isSealedPair(p) then
			table.insert(sealedPairs, p)
		end
	end
	if #sealedPairs > 0 then
		local e = pickEdge(rng:Pick(sealedPairs).Edges)
		e.Opening = true
		e.Gate = "SealedWing"
	end

	-- store doors and gates on doorways
	for _, e in plan.Edges do
		if e.Wall and e.Opening and not e.Gate and not e.StairBottom then
			local ta, tb = plan.Cells[e.A].Type, plan.Cells[e.B].Type
			local staff = STAFF[ta] or STAFF[tb]
			if staff or rng:Chance(0.12) then
				local door = { Id = #plan.StoreDoors + 1, X = e.X, Y = e.Y, Z = e.Z, Dir = e.Dir, Level = e.Level, Staff = staff == true, Edge = e.Id }
				table.insert(plan.StoreDoors, door)
				e.Door = door.Id
			end
		end
		if e.Gate then
			local isBasement = string.sub(e.Gate, 1, 8) == "Basement"
			plan.Gates[e.Gate] = {
				Id = e.Gate,
				Kind = if isBasement then "Basement" else "SealedWing",
				X = e.X,
				Y = e.Y,
				Z = e.Z,
				Dir = e.Dir,
				Level = e.Level,
				OpenNight = if isBasement then 10 else 20,
				Keycard = isBasement,
				Edge = e.Id,
			}
		end
	end

	--============================ WALLS ============================--
	local function addWall(x, z, y, level, dir, info)
		local w = { X = x, Z = z, Y = y, H = heightOf(level), Dir = dir, Length = S, Level = level }
		for k, v in info do
			w[k] = v
		end
		table.insert(plan.Walls, w)
	end
	for _, e in plan.Edges do
		if e.Wall then
			addWall(e.X, e.Z, e.Y, e.Level, e.Dir, { Opening = e.Opening, Door = e.Door, Gate = e.Gate, StairBottom = e.StairBottom })
		end
	end
	local garageExitDone = false
	for _, cell in plan.CellList do
		for _, d in DIR4 do
			if not cellAt(cell.Level, cell.Col + d.dc, cell.Row + d.dr) then
				local feature = nil
				if cell.Level == 0 and cell.Type == "Entrance" and d.dr == 1 then
					feature = "Storefront"
				elseif cell.Level == 0 and cell.Type == "LoadingDocks" and d.dr == -1 then
					feature = "DockDoors"
				elseif cell.Level == -1 and cell.Type == "Parking" and not garageExitDone and rng:Chance(0.35) then
					feature = "GarageExit"
					garageExitDone = true
				end
				addWall(cell.X + d.dc * S / 2, cell.Z + d.dr * S / 2, cell.Y, cell.Level, if d.dc ~= 0 then "EW" else "NS", {
					Opening = false,
					Perimeter = true,
					Feature = feature,
				})
			end
		end
	end

	--============================ NAV GRAPH ============================--
	local nav = plan.Nav
	local function addNode(x, y, z, cellId)
		table.insert(nav.Nodes, { X = x, Y = y, Z = z, Cell = cellId })
		nav.Links[#nav.Nodes] = {}
		return #nav.Nodes
	end
	local function link(a, b, gate, door)
		local na, nb = nav.Nodes[a], nav.Nodes[b]
		local cost = math.sqrt((na.X - nb.X) ^ 2 + (na.Y - nb.Y) ^ 2 + (na.Z - nb.Z) ^ 2)
		table.insert(nav.Links[a], { To = b, Cost = cost, Gate = gate, Door = door })
		table.insert(nav.Links[b], { To = a, Cost = cost, Gate = gate, Door = door })
	end
	for _, cell in plan.CellList do
		if not cell.Solid then
			local y = if cell.Stair then BY / 2 else cell.Y
			nav.CellNode[cell.Id] = addNode(cell.X, y, cell.Z, cell.Id)
		end
	end
	for _, e in plan.Edges do
		if e.Opening then
			local a, b = plan.Cells[e.A], plan.Cells[e.B]
			if e.StairBottom then
				local n = addNode(e.X, BY, e.Z, nil)
				link(nav.CellNode[e.StairBottom], n)
				link(n, nav.CellNode[b.Id])
			else
				local n = addNode(e.X, e.Y, e.Z, nil)
				link(nav.CellNode[a.Id], n, e.Gate, e.Door)
				link(n, nav.CellNode[b.Id], e.Gate, e.Door)
			end
		end
	end

	--============================ SPAWNS ============================--
	for _, id in entrance.Cells do
		local cl = plan.Cells[id]
		for _, off in { { 0, -12 }, { -12, 0 }, { 12, 0 } } do
			table.insert(plan.SpawnPoints, { X = cl.X + off[1], Y = 0, Z = cl.Z + off[2] })
		end
	end

	if options.SkipProps then
		return plan
	end

	--============================ PROPS ============================--
	local props = plan.Props
	local function emit(p)
		table.insert(props, p)
		return p
	end

	local function grp(x, y, z, yaw)
		local r = math.rad(yaw or 0)
		return { X = x, Y = y, Z = z, Yaw = yaw or 0, C = math.cos(r), S = math.sin(r) }
	end
	local function toWorld(g, lx, lz)
		return g.X + lx * g.C + lz * g.S, g.Z - lx * g.S + lz * g.C
	end
	local function extra(p, ex)
		if ex then
			for k, v in ex do
				p[k] = v
			end
		end
		return p
	end
	-- a box in group space; ly is the bottom of the box
	local function gbox(g, lx, ly, lz, w, h, d, color, mat, ex)
		local x, z = toWorld(g, lx, lz)
		return emit(extra({ K = "Box", X = x, Y = g.Y + ly + h / 2, Z = z, W = w, H = h, D = d, Yaw = g.Yaw, C = color, M = mat or "SmoothPlastic" }, ex))
	end
	-- vertical cylinder
	local function gcyl(g, lx, ly, lz, dia, h, color, mat, ex)
		local x, z = toWorld(g, lx, lz)
		return emit(extra({ K = "Cyl", X = x, Y = g.Y + ly + h / 2, Z = z, W = dia, H = h, D = dia, Yaw = g.Yaw, C = color, M = mat or "SmoothPlastic" }, ex))
	end
	-- horizontal cylinder along the group's local X
	local function gcylH(g, lx, ly, lz, dia, length, color, mat, ex)
		local x, z = toWorld(g, lx, lz)
		return emit(extra({ K = "CylH", X = x, Y = g.Y + ly, Z = z, W = length, H = dia, D = dia, Yaw = g.Yaw, C = color, M = mat or "SmoothPlastic" }, ex))
	end
	local function gball(g, lx, ly, lz, dia, color, mat, ex)
		local x, z = toWorld(g, lx, lz)
		return emit(extra({ K = "Ball", X = x, Y = g.Y + ly + dia / 2, Z = z, W = dia, H = dia, D = dia, Yaw = g.Yaw, C = color, M = mat or "SmoothPlastic" }, ex))
	end
	local curCell, curZone, curBonus = nil, nil, 0
	local function gloot(g, lx, ly, lz, bonus)
		local x, z = toWorld(g, lx, lz)
		table.insert(plan.LootPoints, {
			X = x,
			Y = g.Y + ly,
			Z = z,
			Cell = curCell.Id,
			Zone = curZone.Id,
			Type = curZone.Type,
			Bonus = curBonus + (bonus or 0),
		})
	end
	local function ghide(g, lx, ly, lz, kind, faceYaw)
		local x, z = toWorld(g, lx, lz)
		table.insert(plan.HidingSpots, { Id = #plan.HidingSpots + 1, X = x, Y = g.Y + ly, Z = z, Yaw = g.Yaw + (faceYaw or 0), Kind = kind, Cell = curCell.Id })
	end
	local function light(x, y, z, kind, color, emergency, range)
		table.insert(plan.Lights, {
			X = x,
			Y = y,
			Z = z,
			Kind = kind,
			Color = color,
			Emergency = emergency,
			Range = range,
			Zone = curZone.Id,
			Cell = curCell.Id,
			Level = curCell.Level,
		})
	end
	local function sign(text, sub, x, y, z, yaw, w, h, color, kind)
		table.insert(plan.Signs, { Text = text, Sub = sub, X = x, Y = y, Z = z, Yaw = yaw, W = w, H = h, Color = color, Kind = kind or "Zone" })
	end

	local function quads(cell)
		local out = {}
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(out, { X = cell.X + sx * QOFF, Z = cell.Z + sz * QOFF, Y = cell.Y, SX = sx, SZ = sz, Half = Q / 2, Cell = cell })
			end
		end
		rng:Shuffle(out)
		return out
	end

	local function pickProduct(zinfo)
		local list = zinfo.Products
		if #list == 0 then
			return "9e9e9e"
		end
		return list[rng:Int(1, #list)]
	end

	------------------------------------------------------------------ furniture library
	-- double sided store shelf ("gondola"), length along local X
	local function gondola(x, y, z, yaw, length, depth, height, zinfo, lootN, opts)
		opts = opts or {}
		local g = grp(x, y, z, yaw)
		local frame = opts.Frame or "5f646b"
		gbox(g, 0, 0, 0, length, 0.6, depth, frame, "Metal")
		gbox(g, 0, 0.6, 0, length, height - 0.6, 0.3, opts.Back or "868b92", "Metal")
		local levels = opts.Levels or 3
		local surfaces = { 0.6 }
		for i = 1, levels do
			local ly = 0.6 + i * (height - 1.2) / levels
			gbox(g, 0, ly - 0.2, 0, length, 0.2, depth, frame, "Metal")
			if i < levels then
				table.insert(surfaces, ly)
			end
		end
		local gap = (height - 1.2) / levels
		local sides = if opts.OneSided then { 1 } else { -1, 1 }
		for _, sy in surfaces do
			for _, side in sides do
				if rng:Chance(0.82 * detail) then
					local segs = rng:Int(1, 2)
					local segLen = (length - 1) / segs
					for k = 1, segs do
						if rng:Chance(0.8) then
							local cx = -length / 2 + 0.5 + segLen * (k - 0.5)
							local ph = math.min(gap - 0.5, rng:Range(0.8, 1.7))
							-- N/Face: the client dresses these blocks with individual products (ShelfDresser)
							gbox(g, cx, sy, side * depth / 4, segLen * rng:Range(0.55, 0.95), ph, depth / 2 - 0.5, opts.Product or pickProduct(zinfo), "SmoothPlastic", { N = "Product", Face = side })
						end
					end
				end
			end
		end
		for _ = 1, lootN do
			local side = sides[rng:Int(1, #sides)]
			gloot(g, rng:Range(-length / 2 + 1.5, length / 2 - 1.5), surfaces[rng:Int(1, #surfaces)], side * (depth / 2 - 0.35), opts.Bonus)
		end
		return g
	end

	local function pallet(g, lx, lz, stackColor, levels)
		gbox(g, lx, 0, lz, 4, 0.5, 4, "a1795a", "WoodPlanks")
		local h = 0.5
		for i = 1, (levels or 1) do
			local bh = rng:Range(1.2, 2.4)
			gbox(g, lx + rng:Range(-0.2, 0.2), h, lz + rng:Range(-0.2, 0.2), 3.6, bh, 3.6, stackColor or "b58b5d", "Cardboard")
			h += bh
		end
		return h
	end

	local function boxStack(g, lx, lz, n, color)
		local h = 0
		for _ = 1, n do
			local s = rng:Range(1.6, 3)
			gbox(g, lx + rng:Range(-0.4, 0.4), h, lz + rng:Range(-0.4, 0.4), s, s * 0.8, s, color or "b58b5d", "Cardboard", { Yaw = g.Yaw + rng:Range(-12, 12) })
			h += s * 0.8
		end
		return h
	end

	local function tableProp(g, lx, lz, w, d, color)
		gbox(g, lx, 0, lz, w * 0.9, 2.6, d * 0.9, "3e3a36", "Metal")
		gbox(g, lx, 2.6, lz, w, 0.35, d, color or "8d6e63", "Wood")
		return 2.95
	end

	local function locker(g, lx, lz, color, hide)
		gbox(g, lx, 0, lz, 2.6, 7, 2.4, color or "607d8b", "Metal")
		gbox(g, lx, 1, lz + 1.21, 2.2, 5.6, 0.05, "4b5d66", "Metal")
		if hide then
			ghide(g, lx, 2.6, lz, "Locker", 180)
		end
	end

	-- a room filling a quadrant; doorway towards one of the lanes
	local roomStats = { Locked = 0, Hidden = 0 }
	local function room(q, opts)
		opts = opts or {}
		local half = q.Half - 1.2
		local height = heightOf(q.Cell.Level)
		local t = 0.8
		local status = "Open"
		if opts.CanLock then
			if roomStats.Hidden < M.HiddenRooms and rng:Chance(0.08) then
				status = "Hidden"
				roomStats.Hidden += 1
			elseif roomStats.Locked < M.LockedRooms and rng:Chance(opts.LockChance or 0.22) then
				status = "Locked"
				roomStats.Locked += 1
			end
		end
		local doorAxis = opts.DoorAxis or (if rng:Chance(0.5) then "X" else "Z")
		local color = opts.Color or "bdb7ab"
		local g = grp(q.X, q.Y, q.Z, 0)
		local dw, dh = 6, 12
		-- walls along Z at x = +-half
		for _, sx in { -1, 1 } do
			local isDoor = doorAxis == "X" and sx == -q.SX
			if isDoor then
				local seg = (2 * half - dw) / 2
				gbox(g, sx * half, 0, -half + seg / 2, t, height, seg, color, "Concrete")
				gbox(g, sx * half, 0, half - seg / 2, t, height, seg, color, "Concrete")
				gbox(g, sx * half, dh, 0, t, height - dh, dw, color, "Concrete")
			else
				gbox(g, sx * half, 0, 0, t, height, 2 * half + t, color, "Concrete")
			end
		end
		for _, sz in { -1, 1 } do
			local isDoor = doorAxis == "Z" and sz == -q.SZ
			if isDoor then
				local seg = (2 * half - dw) / 2
				gbox(g, -half + seg / 2, 0, sz * half, seg, height, t, color, "Concrete")
				gbox(g, half - seg / 2, 0, sz * half, seg, height, t, color, "Concrete")
				gbox(g, 0, dh, sz * half, dw, height - dh, t, color, "Concrete")
			else
				gbox(g, 0, 0, sz * half, 2 * half - t, height, t, color, "Concrete")
			end
		end
		local dx, dz, yaw
		if doorAxis == "X" then
			dx, dz, yaw = q.X - q.SX * half, q.Z, 90
		else
			dx, dz, yaw = q.X, q.Z - q.SZ * half, 0
		end
		-- Face: yaw of a group whose local -Z points at the back wall and +Z at the door
		local face
		if doorAxis == "X" then
			face = if q.SX < 0 then 90 else -90
		else
			face = if q.SZ < 0 then 0 else 180
		end
		local r = { Id = #plan.Rooms + 1, X = q.X, Y = q.Y, Z = q.Z, Half = half, Status = status, Cell = q.Cell.Id, DoorX = dx, DoorZ = dz, DoorYaw = yaw, Face = face, Kind = opts.Kind }
		table.insert(plan.Rooms, r)
		if status == "Hidden" then
			table.insert(plan.Panels, { Id = #plan.Panels + 1, X = dx, Y = q.Y, Z = dz, Yaw = yaw, W = dw, H = dh, Color = color, Room = r.Id })
		elseif status == "Locked" or rng:Chance(opts.DoorChance or 0.45) then
			local lock = nil
			if status == "Locked" then
				lock = opts.Lock or (if rng:Chance(0.6) then "Crowbar" else "Keycard")
			end
			table.insert(plan.RoomDoors, { Id = #plan.RoomDoors + 1, X = dx, Y = q.Y, Z = dz, Yaw = yaw, W = dw, H = dh, Lock = lock, Room = r.Id, Level = q.Cell.Level })
		end
		r.Bonus = if status == "Hidden" then 4 elseif status == "Locked" then 2.5 else 0
		light(q.X, q.Y + math.min(height, 13) - 1, q.Z, "Room", nil, rng:Chance(0.3), 22)
		return r, g, half
	end

	------------------------------------------------------------------ quadrant fills
	local Q2 = Q / 2 - 2 -- usable half extent inside a quadrant

	local function promo(q, zinfo)
		local g = grp(q.X, q.Y, q.Z, rng:Pick({ 0, 90 }))
		for _, p in { { -5, -5 }, { 5, 5 }, { -5, 5 } } do
			if rng:Chance(0.8) then
				local top = pallet(g, p[1], p[2], pickProduct(zinfo), rng:Int(1, 2))
				if rng:Chance(0.6) then
					gloot(g, p[1], top, p[2], 0)
				end
			end
		end
		gbox(g, 6, 0, -6, 5, 3, 5, "e53935", "SmoothPlastic")
		gloot(g, 6, 3, -6, 0)
	end

	local function shelvesQuad(q, zinfo, along, opts)
		for _, off in { -7.5, 7.5 } do
			if along == "X" then
				gondola(q.X, q.Y, q.Z + off, 0, 26, 4.5, 8.5, zinfo, 4, opts)
			else
				gondola(q.X + off, q.Y, q.Z, 90, 26, 4.5, 8.5, zinfo, 4, opts)
			end
		end
	end

	local function cooler(x, y, z, yaw, zinfo)
		local g = grp(x, y, z, yaw)
		local len, dep, hgt = 24, 4, 9
		gbox(g, 0, 0, 0, len, 0.8, dep, "dfe3e6", "Metal")
		gbox(g, 0, 0.8, -dep / 2 + 0.3, len, hgt - 0.8, 0.6, "c9ced3", "Metal")
		gbox(g, 0, hgt - 0.6, 0, len, 0.6, dep, "eceff1", "Metal")
		gbox(g, 0, 0.8, dep / 2 - 0.1, len, hgt - 1.4, 0.2, "d6f1ff", "Glass", { Tr = 0.6 })
		gbox(g, 0, hgt - 0.9, dep / 2 - 0.5, len, 0.25, 0.4, "cfefff", "Neon", { Tag = "StoreNeon" })
		for i = 0, 2 do
			if rng:Chance(0.85 * detail) then
				gbox(g, rng:Range(-2, 2), 1.2 + i * 2.5, -0.2, len * rng:Range(0.5, 0.95), 1.8, dep - 1.8, pickProduct(zinfo), "SmoothPlastic")
			end
		end
		for _ = 1, 3 do
			gloot(g, rng:Range(-len / 2 + 2, len / 2 - 2), 0, dep / 2 + 0.9, 0)
		end
	end

	local function chestFreezer(g, lx, lz, zinfo)
		gbox(g, lx, 0, lz, 12, 3.2, 5, "f1f4f6", "SmoothPlastic")
		gbox(g, lx, 3.2, lz, 11.6, 0.25, 4.6, "cfefff", "Glass", { Tr = 0.55 })
		gbox(g, lx, 2.2, lz, 11, 0.9, 4, pickProduct(zinfo), "SmoothPlastic")
		gloot(g, lx + rng:Range(-4, 4), 3.45, lz, 0)
	end

	local function counter(g, lx, lz, length, color, hideKind)
		gbox(g, lx, 0, lz, length, 3.6, 3, color or "8d6e63", "Wood")
		gbox(g, lx, 3.6, lz, length + 0.3, 0.3, 3.3, "e0e0e0", "Marble")
		if hideKind then
			ghide(g, lx, 1.4, lz - 2.6, hideKind, 180)
		end
	end

	local FILL = {}

	-- products knocked off the shelves, lying in the aisles (decoration, no collision)
	local function scatter(q, zinfo, along)
		local g = grp(q.X, q.Y, q.Z, if along == "X" then 0 else 90)
		for _ = 1, rng:Int(1, 3) do
			local s = rng:Range(0.6, 1.4)
			gbox(g, rng:Range(-11, 11), 0, rng:Pick({ -12.5, 0, 12.5 }) + rng:Range(-1, 1), s, s * rng:Range(0.4, 1.2), s * 0.7, pickProduct(zinfo), "SmoothPlastic", { NC = true, Yaw = g.Yaw + rng:Range(0, 180), Roll = rng:Pick({ 0, 90 }) })
		end
	end

	FILL.Aisles = function(cell, zinfo, zs)
		for _, q in quads(cell) do
			if rng:Chance(0.12) then
				promo(q, zinfo)
			else
				shelvesQuad(q, zinfo, zs.Along)
				if rng:Chance(0.35 * detail) then
					scatter(q, zinfo, zs.Along)
				end
			end
		end
		plan.AisleCounter = (plan.AisleCounter or 0) + 1
		sign("AISLE " .. plan.AisleCounter, zinfo.Name, cell.X, cell.Y + H - 7, cell.Z, if zs.Along == "X" then 90 else 0, 9, 3.2, zinfo.Accent, "Aisle")
	end

	FILL.Coolers = function(cell, zinfo, zs)
		for _, q in quads(cell) do
			if zs.Along == "X" then
				cooler(q.X, q.Y, q.Z - 7.5, 180, zinfo)
				cooler(q.X, q.Y, q.Z + 7.5, 0, zinfo)
			else
				cooler(q.X - 7.5, q.Y, q.Z, 90, zinfo)
				cooler(q.X + 7.5, q.Y, q.Z, -90, zinfo)
			end
		end
	end

	FILL.Freezers = function(cell, zinfo, zs)
		for _, q in quads(cell) do
			local g = grp(q.X, q.Y, q.Z, if zs.Along == "X" then 0 else 90)
			for _, a in { -7, 7 } do
				for _, b in { -6, 6 } do
					chestFreezer(g, a, b, zinfo)
				end
			end
		end
	end

	FILL.Bakery = function(cell, zinfo)
		for i, q in quads(cell) do
			local g = grp(q.X, q.Y, q.Z, if q.SZ < 0 then 0 else 180)
			if i == 1 then
				counter(g, 0, 4, 24, "c8a27a", "Counter")
				for k = -2, 2 do
					gball(g, k * 4.5, 3.9, 4, 1.4, pickProduct(zinfo), "SmoothPlastic")
				end
				gbox(g, 0, 3.9, 4, 23, 2.2, 2.6, "e8f6ff", "Glass", { Tr = 0.7 })
				gloot(g, -6, 3.9, 4.8, 0)
				gloot(g, 6, 3.9, 4.8, 0)
				gbox(g, 0, 0, -10, 24, 7, 4, "9aa0a6", "Metal")
				for k = -1, 1 do
					gbox(g, k * 8, 2.2, -7.95, 5, 3, 0.1, "1b1b1b", "Glass", { Tr = 0.2 })
				end
			elseif i == 2 then
				gondola(q.X, q.Y, q.Z, if rng:Chance(0.5) then 0 else 90, 22, 4, 7.5, zinfo, 5, { Frame = "6d4c41", Back = "8d6e63" })
			else
				for _, p in { { -7, -6 }, { 7, 6 } } do
					local top = tableProp(g, p[1], p[2], 6, 4, "d7b899")
					gcyl(g, p[1] - 4.5, 0, p[2], 1.8, 2.2, "8d6e63")
					gcyl(g, p[1] + 4.5, 0, p[2], 1.8, 2.2, "8d6e63")
					if rng:Chance(0.6) then
						gloot(g, p[1], top, p[2], 0)
					end
				end
			end
		end
	end

	FILL.Restaurant = function(cell, zinfo, zs)
		for _, q in quads(cell) do
			local g = grp(q.X, q.Y, q.Z, 0)
			if not zs.CounterDone or (rng:Chance(0.18) and (zs.Counters or 0) < 3) then
				zs.CounterDone = true
				zs.Counters = (zs.Counters or 0) + 1
				local yaw = if q.SZ < 0 then 0 else 180
				local g2 = grp(q.X, q.Y, q.Z, yaw)
				counter(g2, 0, 2, 26, "d84315", "Counter")
				gbox(g2, 0, 0, -11, 26, 4, 3, "9aa0a6", "Metal")
				gbox(g2, -7, 4, -11, 6, 2, 2.5, "616161", "Metal")
				gbox(g2, 6, 3.9, 2, 1.6, 1.2, 1.2, "212121", "SmoothPlastic")
				gbox(g2, 0, 9, -13.5, 22, 4, 0.5, zinfo.Accent, "Neon", { Tag = "StoreNeon" })
				gloot(g2, -4, 3.9, 2.5, 0)
				gloot(g2, 4, 4, -11, 0)
				gloot(g2, -9, 4, -11, 0)
			else
				for _, a in { -7.5, 7.5 } do
					for _, b in { -7.5, 7.5 } do
						gcyl(g, a, 0, b, 0.8, 3, "3e3a36", "Metal")
						gcyl(g, a, 3, b, 5, 0.35, "efebe9", "SmoothPlastic")
						gcyl(g, a - 3.8, 0, b, 1.8, 2.1, "ff7043", "SmoothPlastic")
						gcyl(g, a + 3.8, 0, b, 1.8, 2.1, "ff7043", "SmoothPlastic")
						if rng:Chance(0.35) then
							gloot(g, a, 3.35, b, 0)
						end
					end
				end
			end
		end
	end

	FILL.Electronics = function(cell, zinfo, zs)
		for _, q in quads(cell) do
			if rng:Chance(0.5) then
				shelvesQuad(q, zinfo, zs.Along, { Frame = "37474f", Back = "263238" })
			else
				local g = grp(q.X, q.Y, q.Z, if zs.Along == "X" then 0 else 90)
				for _, b in { -6.5, 6.5 } do
					local top = tableProp(g, 0, b, 24, 4, "263238")
					for k = -1, 1 do
						gbox(g, k * 8, top, b, 5.5, 3.4, 0.35, "111111", "SmoothPlastic")
						gbox(g, k * 8, top + 0.3, b + 0.2, 5, 2.8, 0.05, "1d3b5a", "Neon", { Tr = 0.35, Tag = "Screen" })
					end
					gloot(g, rng:Range(-9, 9), top, b - 1.4, 0)
				end
			end
		end
	end

	FILL.Furniture = function(cell, zinfo)
		for _, q in quads(cell) do
			local yaw = rng:Pick({ 0, 90, 180, 270 })
			local g = grp(q.X, q.Y, q.Z, yaw)
			local kind = rng:Int(1, 4)
			gbox(g, 0, 0, 0, 22, 0.1, 22, pickProduct(zinfo), "Fabric")
			if kind == 1 then -- bedroom
				gbox(g, 0, 0, -2, 9, 1.6, 11, "5d4037", "Wood")
				gbox(g, 0, 1.6, -2, 8.4, 1.1, 10.4, "eceff1", "Fabric")
				gbox(g, 0, 2.7, -6.2, 6, 0.6, 1.8, "ffffff", "Fabric")
				gbox(g, 0, 0, -7.8, 9, 5, 0.6, "4e342e", "Wood")
				gbox(g, 7, 0, -6, 2.6, 2.4, 2.6, "6d4c41", "Wood")
				gbox(g, -9, 0, 7, 6, 9, 3, "8d6e63", "Wood")
				ghide(g, -9, 2.8, 7, "Wardrobe", 180)
				gloot(g, 0, 2.8, -1, 0)
				gloot(g, 7, 2.4, -6, 0)
			elseif kind == 2 then -- living room
				gbox(g, 0, 0, -6, 12, 2, 4, pickProduct(zinfo), "Fabric")
				gbox(g, 0, 2, -7.6, 12, 3, 1, pickProduct(zinfo), "Fabric")
				gbox(g, -6.5, 0, -6, 1.2, 3, 4, "6d4c41", "Fabric")
				gbox(g, 6.5, 0, -6, 1.2, 3, 4, "6d4c41", "Fabric")
				local top = tableProp(g, 0, 0, 6, 3.5, "8d6e63")
				gbox(g, 0, 0, 8, 10, 2.4, 2.4, "3e2723", "Wood")
				gbox(g, 0, 2.4, 8, 8, 4.4, 0.4, "111111", "SmoothPlastic")
				gloot(g, 0, top, 0, 0)
				gloot(g, 3, 2.4, 8, 0)
			elseif kind == 3 then -- dining
				local top = tableProp(g, 0, 0, 10, 6, "a1887f")
				for _, p in { { -3, -4.2 }, { 3, -4.2 }, { -3, 4.2 }, { 3, 4.2 } } do
					gbox(g, p[1], 0, p[2], 2.2, 2, 2.2, "6d4c41", "Wood")
					gbox(g, p[1], 2, p[2] + (if p[2] < 0 then -1 else 1), 2.2, 2.8, 0.3, "6d4c41", "Wood")
				end
				gloot(g, -2, top, 0, 0)
				gloot(g, 2.5, top, 1, 0)
			else -- flat pack storage
				gondola(q.X, q.Y, q.Z, yaw, 22, 4.5, 9, zinfo, 5, { Product = "b58b5d", Frame = "455a64" })
			end
		end
	end

	FILL.Garden = function(cell, zinfo)
		for _, q in quads(cell) do
			local yaw = rng:Pick({ 0, 90 })
			local g = grp(q.X, q.Y, q.Z, yaw)
			local kind = rng:Int(1, 5)
			if kind == 1 then
				for _, b in { -7, 7 } do
					gbox(g, 0, 0, b, 24, 2, 4, "6d4c41", "WoodPlanks")
					gbox(g, 0, 2, b, 23.4, 0.3, 3.4, "4caf50", "Grass")
					for k = -1, 1 do
						gball(g, k * 7 + rng:Range(-1, 1), 2, b, rng:Range(2.4, 3.6), pickProduct(zinfo), "Grass")
					end
					gloot(g, rng:Range(-9, 9), 2.3, b, 0)
				end
			elseif kind == 2 then
				for _, p in { { -7, -7 }, { 7, -7 }, { -7, 7 }, { 7, 7 } } do
					local top = pallet(g, p[1], p[2], rng:Pick({ "795548", "a1887f", "c0ca33" }), rng:Int(1, 3))
					if rng:Chance(0.5) then
						gloot(g, p[1], top, p[2], 0)
					end
				end
			elseif kind == 3 then -- tool shed (hiding spot)
				gbox(g, 0, 0, -4, 10, 8, 0.6, "8d6e63", "WoodPlanks")
				gbox(g, -5, 0, 0, 0.6, 8, 8, "8d6e63", "WoodPlanks")
				gbox(g, 5, 0, 0, 0.6, 8, 8, "8d6e63", "WoodPlanks")
				gbox(g, -3.2, 0, 4, 3.6, 8, 0.6, "8d6e63", "WoodPlanks")
				gbox(g, 3.2, 0, 4, 3.6, 8, 0.6, "8d6e63", "WoodPlanks")
				gbox(g, 0, 8, 0, 11, 0.6, 9, "5d4037", "WoodPlanks")
				ghide(g, 0, 2.6, -1.5, "Shed", 180)
				gloot(g, -3, 0, -2, 0)
			elseif kind == 4 then -- greenhouse frame
				for _, p in { { -10, -10 }, { 10, -10 }, { -10, 10 }, { 10, 10 } } do
					gbox(g, p[1], 0, p[2], 0.5, 10, 0.5, "eceff1", "Metal")
				end
				gbox(g, 0, 10, 0, 21, 0.3, 21, "e0f7fa", "Glass", { Tr = 0.75 })
				local top = tableProp(g, 0, 0, 14, 4, "9e9e9e")
				for k = -2, 2 do
					gcyl(g, k * 2.6, top, 0, 1.4, 1.2, "bf6f3a", "SmoothPlastic")
					gball(g, k * 2.6, top + 1, 0, 1.6, "66bb6a", "Grass")
				end
				gloot(g, 4, top, 1.2, 0)
			else
				for _, p in { { -7, -7 }, { 7, 7 }, { 7, -7 } } do
					gcyl(g, p[1], 0, p[2], 3, 2.4, "bf6f3a", "SmoothPlastic")
					gcyl(g, p[1], 2.4, p[2], 0.6, 5, "6d4c41", "Wood")
					gball(g, p[1], 6, p[2], rng:Range(4, 6), "558b2f", "Grass")
				end
				gloot(g, -6, 0, 6, 0)
			end
		end
	end

	FILL.Pharmacy = function(cell, zinfo, zs)
		for _, q in quads(cell) do
			if not zs.CounterDone then
				zs.CounterDone = true
				local g = grp(q.X, q.Y, q.Z, if q.SZ < 0 then 0 else 180)
				counter(g, 0, 3, 24, "eceff1", "Counter")
				local bx, bz = toWorld(g, 0, -8)
				gondola(bx, q.Y, bz, g.Yaw, 24, 2.5, 9, zinfo, 0, { OneSided = true })
				gbox(g, 0, 10, -1, 14, 3, 0.5, "e53935", "Neon", { Tag = "StoreNeon" })
				sign("PHARMACY", "PRESCRIPTIONS", q.X, q.Y + 13, q.Z, g.Yaw, 14, 3, zinfo.Accent, "Small")
				gloot(g, -5, 3.9, 3.5, 0.5)
				gloot(g, 5, 3.9, 3.5, 0.5)
				gloot(g, 0, 0.6, -6.9, 0.5)
			else
				shelvesQuad(q, zinfo, zs.Along, { Frame = "eceff1", Back = "cfd8dc" })
			end
		end
	end

	FILL.Toys = function(cell, zinfo, zs)
		for _, q in quads(cell) do
			local k = rng:Int(1, 4)
			local g = grp(q.X, q.Y, q.Z, 0)
			if k <= 2 then
				shelvesQuad(q, zinfo, zs.Along)
			elseif k == 3 then -- giant plush bears
				for _, p in { { -7, -7 }, { 7, 7 } } do
					local c = rng:Pick({ "a1887f", "f48fb1", "90caf9", "fff59d" })
					gball(g, p[1], 0, p[2], 6, c, "Fabric")
					gball(g, p[1], 5, p[2], 4, c, "Fabric")
					gball(g, p[1] - 1.5, 8.2, p[2], 1.4, c, "Fabric")
					gball(g, p[1] + 1.5, 8.2, p[2], 1.4, c, "Fabric")
				end
				gloot(g, 7, 0, -7, 0)
				gloot(g, -7, 0, 7, 0)
			else -- ball pit
				gbox(g, 0, 0, 0, 16, 2.5, 16, "1e88e5", "SmoothPlastic", { Tr = 0.2 })
				for _ = 1, 8 do
					gball(g, rng:Range(-6, 6), 2.2, rng:Range(-6, 6), 1.2, pickProduct(zinfo), "SmoothPlastic", { NC = true })
				end
				gloot(g, 0, 2.6, 0, 0.5)
			end
		end
	end

	FILL.Clothing = function(cell, zinfo, zs)
		for _, q in quads(cell) do
			local g = grp(q.X, q.Y, q.Z, if zs.Along == "X" then 0 else 90)
			local k = rng:Int(1, 4)
			if k == 1 and not zs.FittingDone then
				zs.FittingDone = true
				for i = -1, 1 do
					local x = i * 7
					gbox(g, x - 3.2, 0, -6, 0.4, 8, 7, "eceff1", "SmoothPlastic")
					gbox(g, x + 3.2, 0, -6, 0.4, 8, 7, "eceff1", "SmoothPlastic")
					gbox(g, x, 0, -9.5, 6.8, 8, 0.4, "eceff1", "SmoothPlastic")
					gbox(g, x, 1, -2.5, 6, 7, 0.2, pickProduct(zinfo), "Fabric")
					ghide(g, x, 2.6, -6, "FittingRoom", 180)
				end
				gloot(g, 0, 0, 6, 0)
			elseif k <= 2 then -- round racks
				for _, p in { { -7, -7 }, { 7, -7 }, { -7, 7 }, { 7, 7 } } do
					gcyl(g, p[1], 0, p[2], 0.4, 5, "b0bec5", "Metal")
					gcyl(g, p[1], 1.2, p[2], 5.5, 3.6, pickProduct(zinfo), "Fabric")
					if rng:Chance(0.4) then
						gloot(g, p[1] + 3, 0, p[2], 0)
					end
				end
			elseif k == 3 then -- straight racks
				for _, b in { -7, 7 } do
					gbox(g, 0, 5, b, 24, 0.3, 0.3, "b0bec5", "Metal")
					gbox(g, -11.5, 0, b, 0.4, 5.3, 0.4, "b0bec5", "Metal")
					gbox(g, 11.5, 0, b, 0.4, 5.3, 0.4, "b0bec5", "Metal")
					for s = -1, 1 do
						gbox(g, s * 7.5, 1.4, b, 6.5, 3.4, 1.6, pickProduct(zinfo), "Fabric")
					end
					gloot(g, rng:Range(-10, 10), 0, b + 1.8, 0)
				end
			else -- mannequins
				for _, p in { { -6, -6 }, { 6, -6 }, { 0, 6 } } do
					local c = pickProduct(zinfo)
					gcyl(g, p[1], 0, p[2], 2.4, 0.3, "424242", "Metal")
					gbox(g, p[1], 0.3, p[2], 1.6, 3, 1, "eeeeee", "SmoothPlastic")
					gbox(g, p[1], 3.3, p[2], 2.2, 2.4, 1.2, c, "Fabric")
					gball(g, p[1], 5.7, p[2], 1.3, "eeeeee", "SmoothPlastic")
				end
				gloot(g, 0, 0, -1, 0)
			end
		end
	end

	FILL.Bathrooms = function(cell, zinfo)
		for _, q in quads(cell) do
			local r, g, half = room(q, { Color = "dfe6e8", Kind = "Restroom" })
			-- stalls along the wall opposite the door side
			local stallG = grp(q.X, q.Y, q.Z, r.Face)
			for i = -1, 1 do
				local x = i * 6
				gbox(stallG, x - 3, 0, -(half - 4), 0.3, 7, 7, "90a4ae", "SmoothPlastic")
				gbox(stallG, x, 1, -(half - 7.5), 4.4, 6, 0.25, "78909c", "SmoothPlastic")
				gbox(stallG, x, 0, -(half - 1.6), 1.6, 2.4, 2, "ffffff", "SmoothPlastic")
				ghide(stallG, x, 2.6, -(half - 3.8), "Stall", 180)
			end
			gbox(stallG, 9.3, 0, -(half - 4), 0.3, 7, 7, "90a4ae", "SmoothPlastic")
			gbox(stallG, half - 2.3, 0, 4, 2.6, 3.2, 10, "eceff1", "Marble")
			gbox(stallG, half - 0.9, 4.5, 4, 0.15, 3.5, 10, "e0f7fa", "Glass", { Refl = 0.4 })
			gloot(stallG, half - 2.3, 3.2, rng:Range(0, 8), r.Bonus)
		end
	end

	FILL.Employee = function(cell, zinfo, zs)
		for _, q in quads(cell) do
			local k = rng:Int(1, 4)
			if k == 4 and zs.OpenDone then
				k = rng:Int(1, 3)
			end
			if k == 4 then
				zs.OpenDone = true
				local g = grp(q.X, q.Y, q.Z, 0)
				for _, p in { { -6, -6 }, { 6, 6 }, { 6, -6 } } do
					local top = pallet(g, p[1], p[2], "a1887f", rng:Int(1, 3))
					gloot(g, p[1], top, p[2], 0)
				end
			else
				local r, _, half = room(q, { CanLock = true, Color = "c9c1b2", Kind = "Staff" })
				local inner = grp(q.X, q.Y, q.Z, r.Face)
				if k == 1 then -- locker room
					for i = -2, 2 do
						locker(inner, i * 3, -(half - 1.6), "546e7a", i % 2 == 0)
					end
					gbox(inner, 0, 0, 2, 12, 1.6, 2, "8d6e63", "Wood")
					gloot(inner, -4, 0, -(half - 4), r.Bonus)
					gloot(inner, 4, 1.6, 2, r.Bonus)
				elseif k == 2 then -- break room
					local top = tableProp(inner, 0, 0, 8, 5, "eceff1")
					gbox(inner, -(half - 2), 0, -6, 3.4, 7.5, 3, "c62828", "SmoothPlastic")
					gbox(inner, -(half - 2), 1.5, -4.45, 2.6, 4.5, 0.1, "ffeb3b", "Neon", { Tr = 0.5, Tag = "StoreNeon" })
					gbox(inner, -(half - 2), 0, 0, 3.4, 7.5, 3, "1565c0", "SmoothPlastic")
					gloot(inner, 1, top, 0, r.Bonus)
					gloot(inner, -(half - 4.2), 0, -6, r.Bonus)
					gloot(inner, -(half - 4.2), 0, 0, r.Bonus)
				else -- office
					for _, b in { -5, 5 } do
						local top = tableProp(inner, -3, b, 7, 3.5, "6d4c41")
						gbox(inner, -3, top, b, 2.4, 1.8, 0.2, "111111", "SmoothPlastic")
						gloot(inner, -0.5, top, b, r.Bonus)
					end
					gbox(inner, half - 2, 0, 0, 2.4, 5, 3.4, "78909c", "Metal")
					gloot(inner, half - 2, 5, 0, r.Bonus)
				end
			end
		end
	end

	FILL.StorageRooms = function(cell, zinfo)
		for _, q in quads(cell) do
			if rng:Chance(0.2) then
				local g = grp(q.X, q.Y, q.Z, 0)
				for _, p in { { -7, -7 }, { 7, -7 }, { 0, 7 } } do
					local top = pallet(g, p[1], p[2], nil, rng:Int(1, 3))
					gloot(g, p[1], top, p[2], 0)
				end
			else
				local r, _, half = room(q, { CanLock = true, Color = "a8a196", Kind = "Stock" })
				local inner = grp(q.X, q.Y, q.Z, r.Face)
				gondola(q.X, q.Y, q.Z, inner.Yaw, 22, 3, 8, zinfo, 0, { OneSided = true, Product = "b58b5d" })
				for _, p in { { -8, half - 5 }, { 8, half - 5 } } do
					local h = boxStack(inner, p[1], p[2], rng:Int(1, 3))
					gloot(inner, p[1], h, p[2], r.Bonus)
				end
				for _ = 1, 3 do
					gloot(inner, rng:Range(-9, 9), 0.6, 1.9, r.Bonus)
				end
				if r.Status ~= "Open" then
					gloot(inner, 0, 0, half - 3, r.Bonus)
				end
			end
		end
	end

	FILL.Security = function(cell, zinfo, zs)
		for _, q in quads(cell) do
			local r, _, half = room(q, { CanLock = zs.MonitorDone == true, Lock = "Keycard", Color = "7b8189", Kind = "Security", LockChance = 0.5 })
			local inner = grp(q.X, q.Y, q.Z, r.Face)
			if not zs.MonitorDone then
				zs.MonitorDone = true
				gbox(inner, 0, 0, -(half - 3), 20, 3, 3.5, "37474f", "Metal")
				for i = -2, 2 do
					gbox(inner, i * 4, 3, -(half - 1.8), 3.6, 2.6, 0.3, "111111", "SmoothPlastic")
					gbox(inner, i * 4, 3.2, -(half - 2), 3.2, 2.2, 0.05, "2e5f3a", "Neon", { Tr = 0.3, Tag = "Screen" })
				end
				gloot(inner, -6, 3, -(half - 3.5), r.Bonus + 0.5)
				gloot(inner, 6, 3, -(half - 3.5), r.Bonus + 0.5)
			end
			local sideG = grp(q.X, q.Y, q.Z, inner.Yaw + 90)
			for i = -1, 1 do
				locker(sideG, i * 3, -(half - 1.6), "263238", i == 0)
			end
			gloot(inner, 0, 0, 0, r.Bonus + 0.5)
		end
	end

	local function rack(g, lx, lz, zinfo, bonus)
		local len = 26
		for _, a in { -len / 2, 0, len / 2 } do
			for _, b in { -2, 2 } do
				gbox(g, lx + a, 0, lz + b, 0.5, 16, 0.5, "1565c0", "Metal")
			end
		end
		for _, ly in { 5, 10.5 } do
			gbox(g, lx, ly, lz, len, 0.4, 4.6, "ff8f00", "Metal")
		end
		for _, ly in { 0, 5.4, 10.9 } do
			for _, a in { -6.5, 6.5 } do
				if rng:Chance(0.7) then
					gbox(g, lx + a, ly, lz, 5, 0.4, 4, "a1795a", "WoodPlanks")
					gbox(g, lx + a, ly + 0.4, lz, 4.6, rng:Range(1.8, 3.8), 3.8, pickProduct(zinfo), "Cardboard")
				end
			end
		end
		gloot(g, lx + rng:Range(-11, 11), 0, lz + 2.6, bonus)
		gloot(g, lx + rng:Range(-11, 11), 5.4, lz + 2.4, bonus)
	end

	FILL.Warehouse = function(cell, zinfo, zs)
		for _, q in quads(cell) do
			local g = grp(q.X, q.Y, q.Z, if zs.Along == "X" then 0 else 90)
			if rng:Chance(0.15) then
				gbox(g, 0, 0, 0, 5, 3, 8, "ffb300", "Metal")
				gbox(g, 0, 3, -1.5, 4.4, 4, 3, "212121", "Metal", { Tr = 0.4 })
				gbox(g, 0, 0, 5, 0.6, 9, 0.6, "424242", "Metal")
				gbox(g, -1, 0.3, 7, 0.4, 0.3, 4, "616161", "Metal")
				gbox(g, 1, 0.3, 7, 0.4, 0.3, 4, "616161", "Metal")
				local top = pallet(g, 7, -7, nil, 2)
				gloot(g, 7, top, -7, 0)
			else
				rack(g, 0, -7.5, zinfo, 0)
				rack(g, 0, 7.5, zinfo, 0)
			end
		end
	end

	FILL.Docks = function(cell, zinfo)
		for _, q in quads(cell) do
			local g = grp(q.X, q.Y, q.Z, rng:Pick({ 0, 90 }))
			for _, p in { { -7, -6 }, { 6, 7 }, { 7, -7 } } do
				if rng:Chance(0.75) then
					local top = pallet(g, p[1], p[2], rng:Pick({ "b58b5d", "1565c0", "ff6f00" }), rng:Int(1, 3))
					if rng:Chance(0.5) then
						gloot(g, p[1], top, p[2], 0)
					end
				end
			end
		end
		table.insert(plan.CartSpawns, { X = cell.X + rng:Range(-28, 28), Y = cell.Y, Z = cell.Z + 4.5, Yaw = 0 })
	end

	FILL.Maintenance = function(cell, zinfo, zs)
		for i, q in quads(cell) do
			if i == 1 then
				local r, _, half = room(q, { Color = "8d8a83", Kind = "Generator", DoorChance = 0.7 })
				local inner = grp(q.X, q.Y, q.Z, r.Face)
				table.insert(plan.GeneratorSpots, { Id = #plan.GeneratorSpots + 1, X = q.X, Y = q.Y, Z = q.Z, Yaw = inner.Yaw, Cell = cell.Id, Zone = curZone.Id, Store = true })
				for k = -1, 1 do
					gcylH(inner, 0, 9 + k * 1.6, -(half - 1), 0.9, 2 * half - 2, "78909c", "Metal")
				end
				gbox(inner, half - 1.3, 3, 0, 0.8, 4, 6, "455a64", "Metal")
				gloot(inner, -(half - 3), 0, half - 3, r.Bonus)
				gloot(inner, half - 3, 0, half - 3, r.Bonus)
			else
				local g = grp(q.X, q.Y, q.Z, rng:Pick({ 0, 90 }))
				local top = tableProp(g, 0, -6, 12, 4, "616161")
				gloot(g, rng:Range(-4, 4), top, -6, 0)
				gbox(g, 0, 0, 7, 10, 7, 2, "9e9e9e", "Metal")
				gloot(g, 3, 0, 4.5, 0)
			end
		end
	end

	FILL.Escalators = function(cell, zinfo, zs)
		for i, q in quads(cell) do
			local yaw = if zs.Along == "X" then 0 else 90
			local g = grp(q.X, q.Y, q.Z, yaw)
			if i <= 2 then
				-- broken escalator: climbs into the ceiling and ends in rubble
				local len, rise = 30, 16
				local ang = math.deg(math.atan(rise / len))
				local hyp = math.sqrt(len * len + rise * rise)
				gbox(g, 0, rise / 2 - 0.5, -2, hyp, 1, 5, "6d7278", "DiamondPlate", { Roll = ang })
				gbox(g, 0, rise / 2 + 1.5, -4.8, hyp, 2.5, 0.6, "212121", "SmoothPlastic", { Roll = ang })
				gbox(g, 0, rise / 2 + 1.5, 0.8, hyp, 2.5, 0.6, "212121", "SmoothPlastic", { Roll = ang })
				for _ = 1, 4 do
					gbox(g, len / 2 - rng:Range(0, 4), rise - rng:Range(0, 3), -2 + rng:Range(-2, 2), rng:Range(2, 4), rng:Range(1.5, 3), rng:Range(2, 4), "8d8a83", "Concrete", { Roll = rng:Range(-30, 30), Pitch = rng:Range(-30, 30) })
				end
				for k = -1, 1 do
					gbox(g, -len / 2 - 2.5, 0, -2 + k * 2.2, 0.3, 3, 0.3, "fdd835", "SmoothPlastic")
				end
				gbox(g, -len / 2 - 2.5, 2.4, -2, 0.2, 0.4, 6, "fdd835", "Neon")
				sign("OUT OF ORDER", "SORRY FOR THE INCONVENIENCE", q.X, q.Y + 6, q.Z, yaw + 90, 7, 2.2, "ff3b3b", "Small")
				gloot(g, -len / 2 + 2, 0, 5, 0)
			else
				gbox(g, -6, 0, -8, 8, 1.6, 2.2, "6d4c41", "Wood")
				gbox(g, 6, 0, 8, 8, 1.6, 2.2, "6d4c41", "Wood")
				gcyl(g, 0, 0, 0, 10, 1.6, "b0bec5", "Marble")
				gcyl(g, 0, 1.6, 0, 1.4, 4, "cfd8dc", "Marble")
				gloot(g, 0, 1.6, 4, 0)
			end
		end
	end

	FILL.Sealed = function(cell, zinfo, zs)
		for _, q in quads(cell) do
			local k = rng:Int(1, 3)
			local g = grp(q.X, q.Y, q.Z, rng:Pick({ 0, 90 }))
			if k == 1 then
				-- collapsed shelves
				for _, b in { -7, 7 } do
					gbox(g, 0, 1.5, b, 26, 0.6, 4.5, "5f646b", "CorrodedMetal", { Pitch = rng:Range(-25, 25), Roll = rng:Range(-8, 8) })
					gbox(g, rng:Range(-8, 8), 0, b + 2, 4, 0.8, 3, pickProduct(zinfo), "Cardboard", { Yaw = g.Yaw + rng:Range(0, 90) })
					gloot(g, rng:Range(-10, 10), 0, b + 3.4, 0)
				end
			elseif k == 2 then
				for _ = 1, 5 do
					gbox(g, rng:Range(-10, 10), 0, rng:Range(-10, 10), rng:Range(2, 5), rng:Range(1, 3), rng:Range(2, 5), "6d665c", "Concrete", { Yaw = rng:Range(0, 90), Roll = rng:Range(-20, 20) })
				end
				gloot(g, rng:Range(-6, 6), 0, rng:Range(-6, 6), 0)
				gloot(g, rng:Range(-6, 6), 0, rng:Range(-6, 6), 0)
			else
				shelvesQuad(q, zinfo, zs.Along, { Frame = "4e4b46", Back = "3e3a36" })
			end
		end
		sign("KEEP OUT", "STRUCTURAL DAMAGE", cell.X, cell.Y + 8, cell.Z, 0, 8, 2.5, "ff3b3b", "Small")
	end

	FILL.Stairwell = function(cell, zinfo)
		local g = grp(cell.X, cell.Y, cell.Z, 0)
		local drop = -BY
		local hyp = math.sqrt(S * S + drop * drop)
		local ang = -math.deg(math.atan(drop / S))
		gbox(g, 0, drop * -0.5 - 1, 0, hyp, 1, L, "8d8a83", "Concrete", { Roll = ang, N = "Ramp" })
		for _, sz in { -1, 1 } do
			gbox(g, 0, BY, sz * (L / 2 + 0.5), S, drop + 3.5, 1, "a8a39a", "Concrete")
			gbox(g, 0, 3.5, sz * (L / 2 + 0.5), S, 0.4, 1.4, "fdd835", "SmoothPlastic")
		end
		local x0 = cell.X - S / 2
		sign("B1  UNDERGROUND", "PARKING · STORAGE · MAINTENANCE", x0 + 3, cell.Y + 18, cell.Z, 90, 14, 3.4, zinfo.Accent, "Zone")
		for _, q in quads(cell) do
			local gq = grp(q.X, q.Y, q.Z, 0)
			if rng:Chance(0.6) then
				local top = pallet(gq, rng:Range(-6, 6), rng:Range(-6, 6), nil, rng:Int(1, 2))
				gloot(gq, 0, top, 0, 0)
			end
		end
	end

	FILL.Parking = function(cell, zinfo)
		for _, q in quads(cell) do
			local g = grp(q.X, q.Y, q.Z, 0)
			gbox(g, -q.SX * (Q2 - 0.5), 0, -q.SZ * (Q2 - 0.5), 3, BH, 3, "9e9e9e", "Concrete")
			local carYaw = rng:Pick({ 0, 180 })
			local cg = grp(q.X, q.Y, q.Z, carYaw)
			for _, a in { -5, 5 } do
				gbox(cg, a + 4.5, 0, 0, 0.3, 0.05, 14, "fdd835", "SmoothPlastic", { NC = true })
				if rng:Chance(0.75) then
					local c = pickProduct(zinfo)
					gbox(cg, a, 0, 0, 6.2, 1.2, 11, "1b1b1b", "SmoothPlastic")
					gbox(cg, a, 1.2, 0, 6.4, 2, 11.6, c, "SmoothPlastic")
					gbox(cg, a, 3.2, -0.8, 5.6, 1.9, 6, "263238", "Glass", { Tr = 0.25 })
					if rng:Chance(0.45) then
						gloot(cg, a + 4, 0, 4, 0)
					end
				end
			end
		end
		if rng:Chance(0.5) then
			table.insert(plan.CartSpawns, { X = cell.X + rng:Range(-26, 26), Y = cell.Y, Z = cell.Z + 4.5, Yaw = 0 })
		end
	end

	FILL.Tunnels = function(cell, zinfo, zs)
		for i, q in quads(cell) do
			local g = grp(q.X, q.Y, q.Z, 0)
			if i == 1 and rng:Chance(0.35) and (zs.Generators or 0) < 3 then
				zs.Generators = (zs.Generators or 0) + 1
				table.insert(plan.GeneratorSpots, { Id = #plan.GeneratorSpots + 1, X = q.X, Y = q.Y, Z = q.Z, Yaw = 0, Cell = cell.Id, Zone = curZone.Id, Store = true })
				gbox(g, q.SX * (q.Half - 2), 0, 0, 3, BH, Q - 1, "4a4741", "Concrete")
				gloot(g, -q.SX * 6, 0, 6, 0)
			else
				gbox(g, 0, 0, 0, Q - 1, BH, Q - 1, "4a4741", "Concrete")
				-- pipes along the faces that look at the lanes
				gcylH(grp(q.X, q.Y, q.Z, 90), 0, 14, q.SX * -(Q / 2), 1.2, Q - 1, "6d4c41", "CorrodedMetal")
				gcylH(g, 0, 16, q.SZ * -(Q / 2), 1.6, Q - 1, "78909c", "Metal")
			end
		end
		local lg = grp(cell.X, cell.Y, cell.Z, 0)
		gloot(lg, rng:Range(-30, -10), 0, rng:Pick({ -5.5, 5.5 }), 0)
		if rng:Chance(0.6) then
			gloot(lg, rng:Pick({ -5.5, 5.5 }), 0, rng:Range(10, 30), 0)
		end
		if rng:Chance(0.25) then
			table.insert(plan.HidingSpots, { Id = #plan.HidingSpots + 1, X = cell.X + 9, Y = cell.Y + 2.6, Z = cell.Z + 18, Yaw = 90, Kind = "Vent", Cell = cell.Id })
			gbox(lg, 7.4, 0, 18, 0.3, 5, 4, "5f6368", "DiamondPlate")
		end
	end

	FILL.Entrance = function(cell, zinfo, zs)
		for _, q in quads(cell) do
			local g = grp(q.X, q.Y, q.Z, 0)
			if q.SZ > 0 and cell.Row == rows then
				-- checkout lanes
				for i = -1, 1 do
					local x = i * 9
					gbox(g, x, 0, 0, 3, 3.4, 16, "37474f", "SmoothPlastic")
					gbox(g, x, 3.4, 1, 2.4, 0.3, 12, "212121", "Rubber")
					gbox(g, x, 3.4, -6, 2, 1.4, 2, "eceff1", "SmoothPlastic")
					gbox(g, x, 4.8, -6, 1.6, 1.2, 0.2, "1d3b5a", "Neon", { Tr = 0.4, Tag = "Screen" })
					gbox(g, x + 2.6, 0, -6, 1.6, 4.5, 3, "e53935", "SmoothPlastic")
					gcyl(g, x, 7, -7, 0.3, 4, "b0bec5", "Metal")
					gbox(g, x, 11, -7, 1.6, 1.6, 0.3, "ffc61a", "Neon", { Tag = "StoreNeon" })
					if i ~= 1 then
						ghide(g, x + 4.2, 1.4, 2, "Counter", 90)
					end
					gloot(g, x + 2.6, 4.5, -6, 0)
				end
			elseif not zs.ServiceDone then
				zs.ServiceDone = true
				counter(g, 0, 0, 20, "1e88e5", "Counter")
				sign("CUSTOMER SERVICE", "HOW CAN WE HELP?", q.X, q.Y + 10, q.Z - 3, 0, 14, 3, zinfo.Accent, "Small")
				gloot(g, -5, 3.9, 0, 0)
				gloot(g, 5, 3.9, 0, 0)
			elseif (zs.Corrals or 0) < 3 then
				zs.Corrals = (zs.Corrals or 0) + 1
				-- cart corral
				gbox(g, 0, 0, -8, 24, 3, 0.4, "b0bec5", "Metal")
				gbox(g, 0, 0, 8, 24, 3, 0.4, "b0bec5", "Metal")
				for k = -1, 1 do
					table.insert(plan.CartSpawns, { X = q.X + k * 6, Y = q.Y, Z = q.Z, Yaw = 90 })
				end
				gloot(g, 9, 0, 0, 0)
			else
				-- waiting area: benches, plants and a vending machine
				gbox(g, -6, 0, -6, 9, 1.8, 2.4, "455a64", "Metal")
				gbox(g, 6, 0, 6, 9, 1.8, 2.4, "455a64", "Metal")
				gcyl(g, 8, 0, -8, 3, 2.4, "bf6f3a")
				gball(g, 8, 2.4, -8, 4.5, "558b2f", "Grass")
				gbox(g, -9, 0, 8, 3.4, 7.5, 3, "1565c0", "SmoothPlastic")
				gbox(g, -9, 1.5, 6.45, 2.6, 4.5, 0.1, "bbdefb", "Neon", { Tr = 0.5, Tag = "StoreNeon" })
				gloot(g, -9, 0, 5.5, 0)
			end
		end
		if not zs.BannerDone then
			zs.BannerDone = true
			sign("MASSIVE STORE", "EVERYTHING YOU NEED · OPEN 24/7", ox + cols * S / 2, cell.Y + 17, cell.Z + 20, 0, 30, 6, "ffc61a", "Banner")
		end
	end

	FILL.None = function() end

	------------------------------------------------------------------ run the fills
	local zoneState = {}
	for _, cell in plan.CellList do
		if not cell.Solid then
			curCell = cell
			curZone = plan.Zones[cell.Zone]
			local zinfo = Zones.Types[curZone.Type]
			curBonus = zinfo.LootBonus or 0
			local zs = zoneState[curZone.Id]
			if not zs then
				zs = { Along = if rng:Chance(0.5) then "X" else "Z" }
				zoneState[curZone.Id] = zs
			end
			local fill = FILL[zinfo.Fill] or FILL.Aisles
			fill(cell, zinfo, zs)

			-- ceiling lights over the lanes
			local h = heightOf(cell.Level)
			local n = if curZone.Type == "Tunnels" or cell.Stair then 1 else M.LightsPerCell
			local spots = if n == 1 then { { 0, 0 } } else { { -20, 0 }, { 20, 0 }, { 0, -20 }, { 0, 20 } }
			for i = 1, math.min(n, #spots) do
				local p = spots[i]
				light(cell.X + p[1], cell.Y + h - 1.2, cell.Z + p[2], if curZone.Type == "Tunnels" then "Cage" else "Panel", zinfo.Light, rng:Chance(0.22), if cell.Level == 0 then 34 else 28)
			end
		end
	end

	-- zone signs
	for _, z in plan.Zones do
		if z.Center and z.Type ~= "Solid" and z.Type ~= "Stairwell" then
			local cl = plan.Cells[z.Center]
			local info = Zones.Types[z.Type]
			sign(info.Name, nil, cl.X, cl.Y + heightOf(cl.Level) - 4.5, cl.Z + 6, 0, math.max(14, #info.Name * 1.6), 3.6, info.Accent, "Zone")
		end
	end

	-- loose carts along the lanes
	local laneCells = {}
	for _, cell in plan.CellList do
		local t = cell.Type
		if not cell.Solid and not cell.Stair and t ~= "Sealed" and t ~= "Tunnels" then
			table.insert(laneCells, cell)
		end
	end
	while #plan.CartSpawns < Config.Carts.Count and #laneCells > 0 do
		local cl = rng:Pick(laneCells)
		local sx = rng:Pick({ -1, 1 })
		table.insert(plan.CartSpawns, { X = cl.X + sx * rng:Range(12, 30), Y = cl.Y, Z = cl.Z + rng:Pick({ -4.5, 4.5 }), Yaw = rng:Pick({ 0, 180 }) + rng:Range(-15, 15) })
	end

	-- extra player generator spots are not needed; store generators power whole regions
	return plan
end

--============================ LOOKUPS ============================--

-- cell at a world position (nil outside the store)
function StoreLayout.CellAt(plan, x: number, y: number, z: number)
	local c = math.floor((x - plan.OriginX) / plan.CellSize) + 1
	local r = math.floor((z - plan.OriginZ) / plan.CellSize) + 1
	local level = if y < -0.5 then -1 else 0
	local cell = plan.Cells[key(level, c, r)]
	if cell and cell.Solid then
		cell = plan.Cells[key(0, c, r)] -- on the ramp
	end
	if not cell and level == -1 then
		cell = plan.Cells[key(0, c, r)]
	end
	return cell
end

function StoreLayout.ZoneAt(plan, x: number, y: number, z: number)
	local cell = StoreLayout.CellAt(plan, x, y, z)
	return cell and plan.Zones[cell.Zone], cell
end

return StoreLayout
