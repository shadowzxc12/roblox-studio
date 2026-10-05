--[[
	InventoryCore: slot containers (player inventory, storage boxes, carts, lost bags).
	Pure data: inv = { Size = n, Slots = { [i] = { Id = "Apple", Qty = 3 } } }
	Only the server changes containers; clients get read-only copies.
]]

local Items = require(script.Parent.Items)

local InventoryCore = {}

function InventoryCore.new(size: number)
	return { Size = size, Slots = {} }
end

local function stackOf(id)
	return Items.StackOf(id)
end

-- how many of `id` would fit
function InventoryCore.Space(inv, id: string): number
	local stack = stackOf(id)
	local space = 0
	for i = 1, inv.Size do
		local s = inv.Slots[i]
		if not s then
			space += stack
		elseif s.Id == id then
			space += math.max(0, stack - s.Qty)
		end
	end
	return space
end

-- adds as many as fit; returns how many were added
function InventoryCore.Add(inv, id: string, qty: number): number
	if not Items.IsValid(id) or qty <= 0 then
		return 0
	end
	local stack = stackOf(id)
	local left = math.floor(qty)
	-- top up existing stacks first
	for i = 1, inv.Size do
		local s = inv.Slots[i]
		if left <= 0 then
			break
		end
		if s and s.Id == id and s.Qty < stack then
			local n = math.min(left, stack - s.Qty)
			s.Qty += n
			left -= n
		end
	end
	for i = 1, inv.Size do
		if left <= 0 then
			break
		end
		if not inv.Slots[i] then
			local n = math.min(left, stack)
			inv.Slots[i] = { Id = id, Qty = n }
			left -= n
		end
	end
	return math.floor(qty) - left
end

function InventoryCore.Count(inv, id: string): number
	local n = 0
	for i = 1, inv.Size do
		local s = inv.Slots[i]
		if s and s.Id == id then
			n += s.Qty
		end
	end
	return n
end

-- removes up to qty of id (from the last stacks first); returns removed amount
function InventoryCore.Remove(inv, id: string, qty: number): number
	local left = qty
	for i = inv.Size, 1, -1 do
		local s = inv.Slots[i]
		if left <= 0 then
			break
		end
		if s and s.Id == id then
			local n = math.min(left, s.Qty)
			s.Qty -= n
			left -= n
			if s.Qty <= 0 then
				inv.Slots[i] = nil
			end
		end
	end
	return qty - left
end

function InventoryCore.RemoveFromSlot(inv, slot: number, qty: number?)
	local s = inv.Slots[slot]
	if not s then
		return nil, 0
	end
	local n = math.min(qty or s.Qty, s.Qty)
	s.Qty -= n
	local id = s.Id
	if s.Qty <= 0 then
		inv.Slots[slot] = nil
	end
	return id, n
end

function InventoryCore.HasAll(inv, cost): boolean
	for id, n in cost do
		if InventoryCore.Count(inv, id) < n then
			return false
		end
	end
	return true
end

-- like HasAll but counts items across several containers (inventory + nearby cart)
function InventoryCore.HasAllMulti(list, cost): boolean
	for id, n in cost do
		local have = 0
		for _, inv in list do
			have += InventoryCore.Count(inv, id)
		end
		if have < n then
			return false
		end
	end
	return true
end

function InventoryCore.ConsumeMulti(list, cost)
	for id, n in cost do
		local left = n
		for _, inv in list do
			if left <= 0 then
				break
			end
			left -= InventoryCore.Remove(inv, id, left)
		end
	end
end

-- move / swap / merge inside one container
function InventoryCore.Move(inv, from: number, to: number): boolean
	if from == to or from < 1 or to < 1 or from > inv.Size or to > inv.Size then
		return false
	end
	local a, b = inv.Slots[from], inv.Slots[to]
	if not a then
		return false
	end
	if b and b.Id == a.Id then
		local stack = stackOf(a.Id)
		local n = math.min(a.Qty, stack - b.Qty)
		b.Qty += n
		a.Qty -= n
		if a.Qty <= 0 then
			inv.Slots[from] = nil
		end
		return n > 0
	end
	inv.Slots[from], inv.Slots[to] = b, a
	return true
end

-- move a stack (or part of it) from one container to another; returns moved amount
function InventoryCore.Transfer(src, slot: number, dst, qty: number?): number
	local s = src.Slots[slot]
	if not s then
		return 0
	end
	local want = math.min(qty or s.Qty, s.Qty)
	local added = InventoryCore.Add(dst, s.Id, want)
	if added > 0 then
		InventoryCore.RemoveFromSlot(src, slot, added)
	end
	return added
end

-- change size; returns overflowing stacks that no longer fit
function InventoryCore.Resize(inv, size: number)
	local overflow = {}
	if size < inv.Size then
		for i = size + 1, inv.Size do
			local s = inv.Slots[i]
			if s then
				inv.Slots[i] = nil
				table.insert(overflow, s)
			end
		end
	end
	inv.Size = size
	-- try to keep overflow inside
	for i = #overflow, 1, -1 do
		local s = overflow[i]
		local added = InventoryCore.Add(inv, s.Id, s.Qty)
		s.Qty -= added
		if s.Qty <= 0 then
			table.remove(overflow, i)
		end
	end
	return overflow
end

function InventoryCore.IsEmpty(inv): boolean
	for i = 1, inv.Size do
		if inv.Slots[i] then
			return false
		end
	end
	return true
end

-- plain array copy for the network ({ [i] = {Id, Qty} | false })
function InventoryCore.Serialize(inv)
	local out = { Size = inv.Size, Slots = {} }
	for i = 1, inv.Size do
		local s = inv.Slots[i]
		out.Slots[i] = if s then { Id = s.Id, Qty = s.Qty } else false
	end
	return out
end

-- rebuild from untrusted / saved data
function InventoryCore.FromData(data, size: number)
	local inv = InventoryCore.new(size)
	if type(data) == "table" and type(data.Slots) == "table" then
		for i = 1, size do
			local s = data.Slots[i]
			if type(s) == "table" and Items.IsValid(s.Id) and type(s.Qty) == "number" then
				local q = math.clamp(math.floor(s.Qty), 1, stackOf(s.Id))
				inv.Slots[i] = { Id = s.Id, Qty = q }
			end
		end
	end
	return inv
end

-- list of { Id, Qty } of everything inside
function InventoryCore.Contents(inv)
	local out = {}
	for i = 1, inv.Size do
		local s = inv.Slots[i]
		if s then
			table.insert(out, { Id = s.Id, Qty = s.Qty })
		end
	end
	return out
end

return InventoryCore
