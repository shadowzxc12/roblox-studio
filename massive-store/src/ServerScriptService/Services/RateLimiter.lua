-- RateLimiter: stops a client from spamming a remote.
-- local limiter = RateLimiter.new(5, 10)  -> at most 5 requests per 10 seconds per player
local Players = game:GetService("Players")

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(maxRequests: number, window: number)
	local self = setmetatable({ Max = maxRequests, Window = window, Log = {} }, RateLimiter)
	Players.PlayerRemoving:Connect(function(player)
		self.Log[player] = nil
	end)
	return self
end

function RateLimiter:Allow(player: Player): boolean
	local now = os.clock()
	local log = self.Log[player]
	if not log then
		log = {}
		self.Log[player] = log
	end
	while log[1] and now - log[1] > self.Window do
		table.remove(log, 1)
	end
	if #log >= self.Max then
		return false
	end
	table.insert(log, now)
	return true
end

return RateLimiter
