-- Signal: tiny script-to-script event (no Instances). Handlers run in their own thread.
local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local h = { Fn = fn, On = true }
	table.insert(self._handlers, h)
	return {
		Disconnect = function()
			h.On = false
			local i = table.find(self._handlers, h)
			if i then
				table.remove(self._handlers, i)
			end
		end,
	}
end

function Signal:Fire(...)
	for _, h in table.clone(self._handlers) do
		if h.On then
			task.spawn(h.Fn, ...)
		end
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	local conn
	conn = self:Connect(function(...)
		conn.Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

return Signal
