--[[
	Util: small pure helpers shared by server, client and tests.
	Util.RNG(seed) is a deterministic random generator (Park-Miller) so the store layout is
	identical on the server and on every client that rebuilds it from the same seed.
]]

local Util = {}

local RNG = {}
RNG.__index = RNG

function Util.RNG(seed: number)
	local s = math.floor(math.abs(seed or 1)) % 2147483646 + 1
	return setmetatable({ s = s }, RNG)
end

-- [0, 1)
function RNG:Next(): number
	self.s = (self.s * 48271) % 2147483647
	return (self.s - 1) / 2147483646
end

-- integer in [a, b]
function RNG:Int(a: number, b: number): number
	if b <= a then
		return a
	end
	return math.min(b, a + math.floor(self:Next() * (b - a + 1)))
end

function RNG:Range(a: number, b: number): number
	return a + self:Next() * (b - a)
end

function RNG:Chance(p: number): boolean
	return self:Next() < p
end

function RNG:Pick(t)
	if #t == 0 then
		return nil
	end
	return t[self:Int(1, #t)]
end

function RNG:Shuffle(t)
	for i = #t, 2, -1 do
		local j = self:Int(1, i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

-- list of { key, weight } or a map key -> weight. Returns the picked key.
function RNG:Weighted(map)
	local total = 0
	for _, w in map do
		total += math.max(0, w)
	end
	if total <= 0 then
		return nil
	end
	local r = self:Next() * total
	-- stable order: sort keys so server and client agree
	local keys = {}
	for k in map do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	for _, k in keys do
		local w = math.max(0, map[k])
		if r < w then
			return k
		end
		r -= w
	end
	return keys[#keys]
end

function Util.HashString(str: string): number
	local h = 5381
	for i = 1, #str do
		h = (h * 33 + string.byte(str, i)) % 2147483647
	end
	return h
end

function Util.DeepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in t do
		c[k] = Util.DeepCopy(v)
	end
	return c
end

function Util.Round(x: number, step: number?): number
	local s = step or 1
	return math.floor(x / s + 0.5) * s
end

function Util.Lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Util.Clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

-- 7.5 -> "07:30 AM"
function Util.FormatClock(hours: number): string
	local h = math.floor(hours) % 24
	local m = math.floor((hours - math.floor(hours)) * 60)
	local suffix = if h < 12 then "AM" else "PM"
	local h12 = h % 12
	if h12 == 0 then
		h12 = 12
	end
	return string.format("%02d:%02d %s", h12, m, suffix)
end

function Util.FormatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function Util.Commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

-- XP needed to go from level L to L+1
function Util.XPForLevel(level: number): number
	return 100 + 55 * (level - 1)
end

-- returns level, xp into this level, xp needed for next level
function Util.LevelFromXP(xp: number): (number, number, number)
	local level = 1
	local rest = math.max(0, xp or 0)
	while rest >= Util.XPForLevel(level) and level < 500 do
		rest -= Util.XPForLevel(level)
		level += 1
	end
	return level, rest, Util.XPForLevel(level)
end

function Util.Count(t): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- UTC day number (used for daily missions)
function Util.DayNumber(unixTime: number): number
	return math.floor(unixTime / 86400)
end

return Util
