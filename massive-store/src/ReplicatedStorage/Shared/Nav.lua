--[[
	Nav: A* over the store's lane graph (StoreLayout plan.Nav).
	Nodes are cell centres and doorway midpoints; every link is a clear straight line, so a
	path can be walked with simple MoveTo calls. Pure Luau (tested headless).

	opts = {
	  CanPass = function(link, fromNode) -> boolean   (gates, doors, temporarily blocked links)
	  NodeCost = function(nodeIndex) -> number         (extra cost, e.g. repellent clouds)
	  MaxIterations = number
	}
]]

local StoreLayout = require(script.Parent.StoreLayout)

local Nav = {}

-- binary min-heap on f-score
local function push(heap, node, f)
	table.insert(heap, { node, f })
	local i = #heap
	while i > 1 do
		local p = i // 2
		if heap[p][2] <= heap[i][2] then
			break
		end
		heap[p], heap[i] = heap[i], heap[p]
		i = p
	end
end

local function pop(heap)
	local top = heap[1]
	local last = table.remove(heap)
	if #heap > 0 then
		heap[1] = last
		local i = 1
		while true do
			local l, r = i * 2, i * 2 + 1
			local s = i
			if l <= #heap and heap[l][2] < heap[s][2] then
				s = l
			end
			if r <= #heap and heap[r][2] < heap[s][2] then
				s = r
			end
			if s == i then
				break
			end
			heap[s], heap[i] = heap[i], heap[s]
			i = s
		end
	end
	return top[1]
end

function Nav.FindPath(plan, from: number, to: number, opts)
	opts = opts or {}
	local nodes, links = plan.Nav.Nodes, plan.Nav.Links
	if not nodes[from] or not nodes[to] then
		return nil
	end
	if from == to then
		return { from }
	end
	local goal = nodes[to]
	local function h(i)
		local n = nodes[i]
		return math.sqrt((n.X - goal.X) ^ 2 + (n.Y - goal.Y) ^ 2 + (n.Z - goal.Z) ^ 2)
	end
	local g = { [from] = 0 }
	local came = {}
	local closed = {}
	local heap = {}
	push(heap, from, h(from))
	local iterations = 0
	local maxIt = opts.MaxIterations or 20000
	while #heap > 0 do
		iterations += 1
		if iterations > maxIt then
			return nil
		end
		local cur = pop(heap)
		if cur == to then
			local path = { cur }
			while came[cur] do
				cur = came[cur]
				table.insert(path, 1, cur)
			end
			return path
		end
		if not closed[cur] then
			closed[cur] = true
			for _, link in links[cur] do
				local nxt = link.To
				if not closed[nxt] and (not opts.CanPass or opts.CanPass(link, cur)) then
					local cost = g[cur] + link.Cost + (if opts.NodeCost then opts.NodeCost(nxt) else 0)
					if g[nxt] == nil or cost < g[nxt] then
						g[nxt] = cost
						came[nxt] = cur
						push(heap, nxt, cost + h(nxt))
					end
				end
			end
		end
	end
	return nil
end

-- the cell-centre node for a world position (nil outside the store)
function Nav.NodeAt(plan, x: number, y: number, z: number): number?
	local cell = StoreLayout.CellAt(plan, x, y, z)
	return cell and plan.Nav.CellNode[cell.Id]
end

function Nav.NodePosition(plan, i: number)
	local n = plan.Nav.Nodes[i]
	return n.X, n.Y, n.Z
end

-- all cell nodes (useful for random patrol targets)
function Nav.CellNodes(plan)
	local out = {}
	for _, cell in plan.CellList do
		local n = plan.Nav.CellNode[cell.Id]
		if n then
			table.insert(out, n)
		end
	end
	return out
end

return Nav
