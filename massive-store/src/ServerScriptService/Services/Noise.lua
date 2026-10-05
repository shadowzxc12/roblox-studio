--[[
	Noise: everything that makes a sound the Locust can hear.
	Emit(position, loudness, source, kind) -> remembered for Config.Noise.Lifetime seconds.
	The Locust asks Heard(listenerPos, hearingRange) for the most "interesting" noise:
	effective = loudness * hearingRange - distance  (must be > 0 to be heard)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local Noise = {}

local events = {}
local MAX = 200

function Noise.Emit(position: Vector3, loudness: number, source: any?, kind: string?)
	if not position then
		return
	end
	table.insert(events, { Pos = position, Loud = loudness, Source = source, Kind = kind or "Noise", Time = os.clock() })
	if #events > MAX then
		table.remove(events, 1)
	end
end

-- best audible noise for a listener (nil if nothing)
function Noise.Heard(listener: Vector3, hearingRange: number, ignoreKinds: { [string]: boolean }?)
	local now = os.clock()
	local best, bestScore = nil, 0
	local life = Config.Noise.Lifetime
	for i = #events, 1, -1 do
		local e = events[i]
		local age = now - e.Time
		if age > life then
			table.remove(events, i)
		elseif not (ignoreKinds and ignoreKinds[e.Kind]) then
			local dist = (e.Pos - listener).Magnitude
			local fade = 1 - age / life * 0.5
			local score = e.Loud * hearingRange * fade - dist
			if score > bestScore then
				best, bestScore = e, score
			end
		end
	end
	return best, bestScore
end

function Noise.Clear()
	table.clear(events)
end

return Noise
