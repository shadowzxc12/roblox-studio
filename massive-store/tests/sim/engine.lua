--[[
	A small fake Roblox engine for running the real SERVER code headless (luau CLI).
	Virtual time, coroutine scheduler, Instances with properties/attributes/signals,
	Vector3 / CFrame math, services (DataStore, MemoryStore, Pathfinding, Tween, ...).
	Physics is faked: Humanoid:MoveTo walks the root part toward the target each step,
	downward raycasts hit a flat floor, everything else is "clear".

	SOURCES (path -> source) and TREE (instance paths) are defined before this file.
]]

--============================ SCHEDULER ============================--
local clock = 0
local queue = {}
local seq = 0
ERRORS = {}

local function schedule(t, thread, args)
	seq += 1
	table.insert(queue, { time = t, seq = seq, thread = thread, args = args })
end

local function resume(thread, ...)
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		local msg = tostring(err) .. "\n" .. debug.traceback(thread)
		table.insert(ERRORS, msg)
		print("SCRIPT ERROR: " .. msg)
	end
end

task = {}
function task.spawn(fn, ...)
	local th = if type(fn) == "thread" then fn else coroutine.create(fn)
	resume(th, ...)
	return th
end
function task.defer(fn, ...)
	local th = if type(fn) == "thread" then fn else coroutine.create(fn)
	schedule(clock, th, table.pack(...))
	return th
end
function task.delay(t, fn, ...)
	local th = if type(fn) == "thread" then fn else coroutine.create(fn)
	schedule(clock + (t or 0), th, table.pack(...))
	return th
end
function task.wait(t)
	local th = coroutine.running()
	local start = clock
	schedule(clock + math.max(t or 0.03, 0.03), th, nil)
	coroutine.yield()
	return clock - start
end
function task.cancel(th)
	for i = #queue, 1, -1 do
		if queue[i].thread == th then
			table.remove(queue, i)
		end
	end
end
wait = task.wait
spawn = task.spawn
delay = task.delay
function tick()
	return clock
end
function time()
	return clock
end

local heartbeatFns = {}
local STEP = 0.05
local function runUntil(tEnd)
	while clock < tEnd do
		local nextStep = math.min(tEnd, clock + STEP)
		-- run everything scheduled before nextStep
		while true do
			table.sort(queue, function(a, b)
				if a.time == b.time then
					return a.seq < b.seq
				end
				return a.time < b.time
			end)
			local item = queue[1]
			if not item or item.time > nextStep then
				break
			end
			table.remove(queue, 1)
			clock = math.max(clock, item.time)
			if coroutine.status(item.thread) == "suspended" then
				if item.args then
					resume(item.thread, table.unpack(item.args, 1, item.args.n))
				else
					resume(item.thread)
				end
			end
		end
		local dt = nextStep - clock
		clock = nextStep
		for _, fn in heartbeatFns do
			fn(STEP)
		end
		local _ = dt
	end
end
G.RunUntil = function(t)
	runUntil(clock + t)
end
G.Clock = function()
	return clock
end

local realOs = os
os = setmetatable({
	clock = function()
		return clock
	end,
	time = function()
		return 1760000000 + math.floor(clock)
	end,
}, { __index = realOs })

--============================ SIGNAL ============================--
local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ handlers = {}, waiting = {} }, Signal)
end
function Signal:Connect(fn)
	local h = { fn = fn, connected = true }
	table.insert(self.handlers, h)
	local conn = { Connected = true }
	function conn.Disconnect()
		h.connected = false
		conn.Connected = false
	end
	conn.disconnect = conn.Disconnect
	return setmetatable(conn, { __index = function(_, k)
		if k == "Disconnect" then
			return function()
				h.connected = false
			end
		end
	end })
end
function Signal:Once(fn)
	local c
	c = self:Connect(function(...)
		c.Disconnect()
		fn(...)
	end)
	return c
end
function Signal:Fire(...)
	for _, h in table.clone(self.handlers) do
		if h.connected then
			task.spawn(h.fn, ...)
		end
	end
	local w = self.waiting
	self.waiting = {}
	for _, th in w do
		schedule(clock, th, table.pack(...))
	end
end
function Signal:Wait()
	table.insert(self.waiting, coroutine.running())
	return coroutine.yield()
end
local function sigProxy(sig)
	-- allow both sig:Connect and sig.Connect(sig, ...)
	return sig
end

--============================ DATATYPES ============================--
local realTypeof = typeof
local TYPE = {}

Vector3 = {}
local V3 = {}
TYPE[V3] = "Vector3"
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
end
V3.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		if m == 0 then
			return v3(0, 0, 0)
		end
		return v3(v.X / m, v.Y / m, v.Z / m)
	elseif k == "x" then
		return v.X
	elseif k == "y" then
		return v.Y
	elseif k == "z" then
		return v.Z
	end
	return V3[k]
end
V3.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return v3(b.X * a, b.Y * a, b.Z * a)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(v)
	return string.format("%.2f, %.2f, %.2f", v.X, v.Y, v.Z)
end
function V3.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3.Lerp(a, b, t)
	return a + (b - a) * t
end
function V3.Abs(a)
	return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end
function V3.Max(a, b)
	return v3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
end
function V3.Min(a, b)
	return v3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
end
function V3.FuzzyEq(a, b, eps)
	return (a - b).Magnitude <= (eps or 1e-5)
end
Vector3.new = v3
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)

Vector2 = {}
local V2 = {}
TYPE[V2] = "Vector2"
local function v2(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, V2)
end
V2.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	end
	return V2[k]
end
V2.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
V2.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
V2.__mul = function(a, b)
	if type(b) == "number" then
		return v2(a.X * b, a.Y * b)
	end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2.__div = function(a, b)
	return v2(a.X / b, a.Y / b)
end
Vector2.new = v2
Vector2.zero = v2(0, 0)

-- CFrame: position + rotation matrix rows r[1..3][1..3]
CFrame = {}
local CF = {}
TYPE[CF] = "CFrame"
local function cfnew(px, py, pz, r)
	return setmetatable({ p = v3(px, py, pz), r = r or { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } } }, CF)
end
local function matmul(a, b)
	local out = {}
	for i = 1, 3 do
		out[i] = {}
		for j = 1, 3 do
			out[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
		end
	end
	return out
end
local function matvec(m, v)
	return v3(m[1][1] * v.X + m[1][2] * v.Y + m[1][3] * v.Z, m[2][1] * v.X + m[2][2] * v.Y + m[2][3] * v.Z, m[3][1] * v.X + m[3][2] * v.Y + m[3][3] * v.Z)
end
local function transpose(m)
	return { { m[1][1], m[2][1], m[3][1] }, { m[1][2], m[2][2], m[3][2] }, { m[1][3], m[2][3], m[3][3] } }
end
CF.__index = function(c, k)
	if k == "Position" or k == "p" then
		return rawget(c, "p")
	elseif k == "X" then
		return c.p.X
	elseif k == "Y" then
		return c.p.Y
	elseif k == "Z" then
		return c.p.Z
	elseif k == "LookVector" then
		return v3(-c.r[1][3], -c.r[2][3], -c.r[3][3])
	elseif k == "RightVector" then
		return v3(c.r[1][1], c.r[2][1], c.r[3][1])
	elseif k == "UpVector" then
		return v3(c.r[1][2], c.r[2][2], c.r[3][2])
	elseif k == "Rotation" then
		return cfnew(0, 0, 0, c.r)
	end
	return CF[k]
end
-- keep rotations orthonormal (repeated PivotTo products would drift and blow up)
local function ortho(m)
	local x = v3(m[1][1], m[2][1], m[3][1])
	local y = v3(m[1][2], m[2][2], m[3][2])
	if x.Magnitude < 1e-9 or y.Magnitude < 1e-9 then
		return { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
	end
	x = x.Unit
	y = (y - x * x:Dot(y))
	if y.Magnitude < 1e-9 then
		return { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
	end
	y = y.Unit
	local z = x:Cross(y)
	return { { x.X, y.X, z.X }, { x.Y, y.Y, z.Y }, { x.Z, y.Z, z.Z } }
end
CF.__mul = function(a, b)
	if getmetatable(b) == V3 then
		return matvec(a.r, b) + a.p
	end
	return setmetatable({ p = matvec(a.r, b.p) + a.p, r = ortho(matmul(a.r, b.r)) }, CF)
end
CF.__add = function(a, v)
	return setmetatable({ p = a.p + v, r = a.r }, CF)
end
CF.__sub = function(a, v)
	return setmetatable({ p = a.p - v, r = a.r }, CF)
end
CF.__eq = function(a, b)
	return a.p == b.p
end
function CF.Inverse(c)
	local rt = transpose(c.r)
	local p = matvec(rt, c.p)
	return setmetatable({ p = -p, r = rt }, CF)
end
function CF.Lerp(a, b, t)
	return setmetatable({ p = a.p:Lerp(b.p, t), r = if t < 0.5 then a.r else b.r }, CF)
end
function CF.ToOrientation(c)
	local r = c.r
	local rx = math.asin(math.clamp(-r[2][3], -1, 1))
	local ry = math.atan2(r[1][3], r[3][3])
	local rz = math.atan2(r[2][1], r[2][2])
	return rx, ry, rz
end
CF.ToEulerAnglesYXZ = CF.ToOrientation
function CF.PointToWorldSpace(c, v)
	return c * v
end
function CF.PointToObjectSpace(c, v)
	return c:Inverse() * v
end
function CF.VectorToWorldSpace(c, v)
	return matvec(c.r, v)
end
function CF.ToWorldSpace(c, o)
	return c * o
end
function CF.ToObjectSpace(c, o)
	return c:Inverse() * o
end
function CF.GetComponents(c)
	local r = c.r
	return c.p.X, c.p.Y, c.p.Z, r[1][1], r[1][2], r[1][3], r[2][1], r[2][2], r[2][3], r[3][1], r[3][2], r[3][3]
end
local function rx(a)
	local c, s = math.cos(a), math.sin(a)
	return { { 1, 0, 0 }, { 0, c, -s }, { 0, s, c } }
end
local function ry(a)
	local c, s = math.cos(a), math.sin(a)
	return { { c, 0, s }, { 0, 1, 0 }, { -s, 0, c } }
end
local function rz(a)
	local c, s = math.cos(a), math.sin(a)
	return { { c, -s, 0 }, { s, c, 0 }, { 0, 0, 1 } }
end
function CFrame.new(x, y, z, ...)
	if x == nil then
		return cfnew(0, 0, 0)
	end
	if getmetatable(x) == V3 then
		if y and getmetatable(y) == V3 then
			return CFrame.lookAt(x, y)
		end
		return cfnew(x.X, x.Y, x.Z)
	end
	local extra = { ... }
	if #extra == 9 then
		return cfnew(x, y, z, { { extra[1], extra[2], extra[3] }, { extra[4], extra[5], extra[6] }, { extra[7], extra[8], extra[9] } })
	end
	return cfnew(x, y or 0, z or 0)
end
function CFrame.Angles(a, b, c)
	return cfnew(0, 0, 0, matmul(matmul(rx(a or 0), ry(b or 0)), rz(c or 0)))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.fromOrientation(a, b, c)
	return cfnew(0, 0, 0, matmul(matmul(ry(b or 0), rx(a or 0)), rz(c or 0)))
end
CFrame.fromEulerAnglesYXZ = CFrame.fromOrientation
function CFrame.lookAt(eye, target, up)
	local f = (target - eye)
	if f.Magnitude < 1e-6 then
		return cfnew(eye.X, eye.Y, eye.Z)
	end
	f = f.Unit
	local u = up or v3(0, 1, 0)
	local right = f:Cross(u)
	if right.Magnitude < 1e-6 then
		right = v3(1, 0, 0)
	end
	right = right.Unit
	local upv = right:Cross(f)
	return cfnew(eye.X, eye.Y, eye.Z, { { right.X, upv.X, -f.X }, { right.Y, upv.Y, -f.Y }, { right.Z, upv.Z, -f.Z } })
end
function CFrame.fromAxisAngle(axis, a)
	return CFrame.Angles(0, a, 0)
end
CFrame.identity = cfnew(0, 0, 0)

Color3 = {}
local C3 = {}
TYPE[C3] = "Color3"
C3.__index = C3
local function c3(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3)
end
C3.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
function C3.Lerp(a, b, t)
	return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
function C3.ToHex(c)
	return string.format("%02x%02x%02x", c.R * 255, c.G * 255, c.B * 255)
end
Color3.new = c3
function Color3.fromRGB(r, g, b)
	return c3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function Color3.fromHex(h)
	assert(type(h) == "string", "fromHex needs a string")
	h = h:gsub("#", "")
	assert(#h == 6, "bad hex " .. h)
	return c3(tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255)
end
function Color3.fromHSV(h, s, v)
	return c3(v, v, v)
end

local function simpleType(name, fields)
	local mt = {}
	mt.__index = mt
	TYPE[mt] = name
	return function(...)
		local t = { ... }
		local o = {}
		for i, f in fields do
			o[f] = t[i]
		end
		return setmetatable(o, mt)
	end, mt
end

UDim = {}
UDim.new = simpleType("UDim", { "Scale", "Offset" })
UDim2 = {}
local UD2 = {}
TYPE[UD2] = "UDim2"
UD2.__index = UD2
local function ud2(xs, xo, ys, yo)
	return setmetatable({ X = UDim.new(xs or 0, xo or 0), Y = UDim.new(ys or 0, yo or 0) }, UD2)
end
UD2.__add = function(a, b)
	return ud2(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
UD2.__sub = function(a, b)
	return ud2(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset)
end
UDim2.new = ud2
function UDim2.fromScale(x, y)
	return ud2(x, 0, y, 0)
end
function UDim2.fromOffset(x, y)
	return ud2(0, x, 0, y)
end
NumberRange = {}
NumberRange.new = simpleType("NumberRange", { "Min", "Max" })
NumberSequenceKeypoint = {}
NumberSequenceKeypoint.new = simpleType("NumberSequenceKeypoint", { "Time", "Value" })
NumberSequence = {}
NumberSequence.new = simpleType("NumberSequence", { "A", "B" })
ColorSequenceKeypoint = {}
ColorSequenceKeypoint.new = simpleType("ColorSequenceKeypoint", { "Time", "Value" })
ColorSequence = {}
ColorSequence.new = simpleType("ColorSequence", { "A", "B" })
TweenInfo = {}
TweenInfo.new = simpleType("TweenInfo", { "Time", "EasingStyle", "EasingDirection" })
PhysicalProperties = {}
PhysicalProperties.new = simpleType("PhysicalProperties", { "Density" })
Rect = {}
Rect.new = simpleType("Rect", { "A", "B" })
Font = {}
Font.fromEnum = simpleType("Font", { "Enum" })
Font.new = simpleType("Font", { "Family", "Weight" })

local RP = {}
RP.__index = RP
TYPE[RP] = "RaycastParams"
RaycastParams = {}
function RaycastParams.new()
	return setmetatable({ FilterDescendantsInstances = {}, FilterType = nil }, RP)
end
local OP = {}
OP.__index = OP
TYPE[OP] = "OverlapParams"
OverlapParams = {}
function OverlapParams.new()
	return setmetatable({ FilterDescendantsInstances = {} }, OP)
end

Random = {}
local RND = {}
RND.__index = RND
function Random.new(seed)
	return setmetatable({ s = (seed or 1) % 2147483646 + 1 }, RND)
end
function RND:NextNumber(a, b)
	self.s = (self.s * 48271) % 2147483647
	local f = (self.s - 1) / 2147483646
	if a then
		return a + f * (b - a)
	end
	return f
end
function RND:NextInteger(a, b)
	return a + math.floor(self:NextNumber() * (b - a + 1))
end

-- Enum: any path works, items are cached so == compares correctly
local enumCache = {}
local EnumItemMT = { __tostring = function(e)
	return "Enum." .. e.EnumType .. "." .. e.Name
end }
TYPE[EnumItemMT] = "EnumItem"
local function enumType(typeName)
	local t = enumCache[typeName]
	if not t then
		t = setmetatable({}, {
			__index = function(self, name)
				local item = setmetatable({ Name = name, EnumType = typeName, Value = #name }, EnumItemMT)
				rawset(self, name, item)
				return item
			end,
		})
		function t.GetEnumItems()
			return {}
		end
		enumCache[typeName] = t
	end
	return t
end
Enum = setmetatable({}, { __index = function(_, k)
	return enumType(k)
end })

--============================ INSTANCES ============================--
local Instance_ = {}
local InstMT = {}
TYPE[InstMT] = "Instance"

local CLASS_PARENT = {
	Part = "BasePart", WedgePart = "BasePart", MeshPart = "BasePart", SpawnLocation = "BasePart", TrussPart = "BasePart",
	BasePart = "PVInstance", Model = "PVInstance", PVInstance = "Instance",
	Script = "LuaSourceContainer", LocalScript = "LuaSourceContainer", ModuleScript = "LuaSourceContainer",
	PointLight = "Light", SpotLight = "Light", SurfaceLight = "Light",
	ScreenGui = "LayerCollector", BillboardGui = "LayerCollector", SurfaceGui = "LayerCollector",
	Frame = "GuiObject", TextLabel = "GuiObject", TextButton = "GuiButton", ImageLabel = "GuiObject", ImageButton = "GuiButton",
	ScrollingFrame = "GuiObject", GuiButton = "GuiObject", CanvasGroup = "GuiObject",
	RemoteEvent = "Instance", RemoteFunction = "Instance",
	Motor6D = "JointInstance", Weld = "JointInstance", WeldConstraint = "Instance",
	ParticleEmitter = "Instance", Trail = "Instance", Beam = "Instance",
	Humanoid = "Instance", Folder = "Instance",
	IntValue = "ValueBase", NumberValue = "ValueBase", CFrameValue = "ValueBase", StringValue = "ValueBase", BoolValue = "ValueBase", ObjectValue = "ValueBase",
}
local function isA(cls, target)
	if target == "Instance" then
		return true
	end
	while cls do
		if cls == target then
			return true
		end
		cls = CLASS_PARENT[cls]
	end
	return false
end

local DEFAULTS = {
	Transparency = 0, Reflectance = 0, Anchored = false, CanCollide = true, CanQuery = true, CanTouch = true,
	Massless = false, CastShadow = true, Enabled = true, Brightness = 1, Range = 8, Angle = 90, Volume = 0.5,
	PlaybackSpeed = 1, Health = 100, MaxHealth = 100, WalkSpeed = 16, JumpHeight = 7.2, JumpPower = 50, HipHeight = 2,
	HoldDuration = 0, MaxActivationDistance = 10, ActionText = "", ObjectText = "", Text = "", Visible = true,
	BackgroundTransparency = 0, TextTransparency = 0, Rotation = 0, LayoutOrder = 0, ZIndex = 1, Value = 0,
	CollisionGroup = "Default", Looped = false, Archivable = true, AutoRotate = true, Sit = false,
	MaxPlayers = 12, RespawnTime = 5, CharacterAutoLoads = true, Gravity = 196.2,
}

local function newSignalTable()
	return {}
end

function InstMT.__index(self, k)
	local props = rawget(self, "_p")
	local v = props[k]
	if v ~= nil then
		return v
	end
	local m = Instance_[k]
	if m ~= nil then
		return m
	end
	for _, c in rawget(self, "_c") do
		if rawget(c, "_p").Name == k then
			return c
		end
	end
	-- events (created lazily)
	local events = rawget(self, "_e")
	if k == "ChildAdded" or k == "ChildRemoved" or k == "DescendantAdded" or k == "DescendantRemoving" or k == "Changed"
		or k == "AttributeChanged" or k == "Destroying" or k == "AncestryChanged" or k == "Touched"
		or k:match("Changed$") or k:match("^On") == nil and (k:match("Added$") or k:match("Removing$") or k:match("Triggered$") or k:match("Began$") or k:match("Ended$") or k:match("Finished$") or k:match("Failed$") or k:match("Activated$") or k:match("^Mouse") or k:match("Click$") or k:match("Gained$") or k:match("Lost$") or k:match("Shown$") or k:match("Hidden$") or k:match("Completed$") or k:match("Heartbeat$") or k:match("Stepped$") or k == "Event" or k == "Loaded") then
		local s = events[k]
		if not s then
			s = Signal.new()
			events[k] = s
		end
		return s
	end
	if k == "OnServerEvent" or k == "OnClientEvent" then
		local s = events[k]
		if not s then
			s = Signal.new()
			events[k] = s
		end
		return s
	end
	local cls = props.ClassName
	if k == "Position" and isA(cls, "BasePart") then
		return (props.CFrame or CFrame.identity).Position
	end
	if k == "Orientation" then
		return Vector3.zero
	end
	if k == "Size" and isA(cls, "BasePart") then
		return Vector3.new(4, 1, 2)
	end
	if k == "CFrame" and isA(cls, "BasePart") then
		return CFrame.identity
	end
	if k == "PivotOffset" then
		return CFrame.identity
	end
	if k == "AssemblyLinearVelocity" or k == "Velocity" then
		return Vector3.zero
	end
	if k == "Color" or k == "TextColor3" or k == "BackgroundColor3" then
		return Color3.new(0.6, 0.6, 0.6)
	end
	if k == "Material" then
		return Enum.Material.Plastic
	end
	return DEFAULTS[k]
end

local propChanged
function InstMT.__newindex(self, k, v)
	local props = rawget(self, "_p")
	if k == "Parent" then
		Instance_._setParent(self, v)
		return
	end
	if k == "Position" and isA(props.ClassName, "BasePart") then
		local cf = props.CFrame or CFrame.identity
		props.CFrame = setmetatable({ p = v, r = cf.r }, CF)
		propChanged(self, "Position")
		propChanged(self, "CFrame")
		return
	end
	if k == "CFrame" and getmetatable(v) == CF then
		local pp = v.p
		if pp.X ~= pp.X or pp.Y ~= pp.Y or pp.Z ~= pp.Z then
			error("NaN CFrame assigned to " .. tostring(props.Name))
		end
	end
	local old = props[k]
	props[k] = v
	if old ~= v then
		propChanged(self, k)
	end
end
InstMT.__tostring = function(self)
	return rawget(self, "_p").Name
end

function propChanged(self, k)
	local events = rawget(self, "_e")
	local p = events["prop:" .. k]
	if p then
		p:Fire()
	end
	local ch = events.Changed
	if ch then
		local cls = rawget(self, "_p").ClassName
		if isA(cls, "ValueBase") and k == "Value" then
			ch:Fire(rawget(self, "_p").Value)
		elseif not isA(cls, "ValueBase") then
			ch:Fire(k)
		end
	end
	if k == "Health" then
		local hc = events.HealthChanged
		if hc then
			hc:Fire(rawget(self, "_p").Health)
		end
	end
end

local humanoids = setmetatable({}, { __mode = "k" })
local function newInstance(className, name)
	local self = setmetatable({ _p = { ClassName = className, Name = name or className }, _c = {}, _e = {}, _a = {} }, InstMT)
	if className == "Humanoid" then
		humanoids[self] = true
	end
	return self
end
G.NewInstance = newInstance

function Instance_._setParent(self, parent)
	local props = rawget(self, "_p")
	local old = props.Parent
	if old == parent then
		return
	end
	if old then
		local list = rawget(old, "_c")
		for i, c in list do
			if c == self then
				table.remove(list, i)
				break
			end
		end
		local ev = rawget(old, "_e").ChildRemoved
		if ev then
			ev:Fire(self)
		end
	end
	props.Parent = parent
	if parent then
		table.insert(rawget(parent, "_c"), self)
		local ev = rawget(parent, "_e").ChildAdded
		if ev then
			ev:Fire(self)
		end
		local anc = parent
		while anc do
			local da = rawget(anc, "_e").DescendantAdded
			if da then
				da:Fire(self)
			end
			anc = rawget(anc, "_p").Parent
		end
		if G.OnParented then
			G.OnParented(self)
		end
	end
	local ac = rawget(self, "_e").AncestryChanged
	if ac then
		ac:Fire(self, parent)
	end
end

function Instance_:IsA(c)
	return isA(self.ClassName, c)
end
function Instance_:GetChildren()
	return table.clone(rawget(self, "_c"))
end
function Instance_:GetDescendants()
	local out = {}
	local function rec(i)
		for _, c in rawget(i, "_c") do
			table.insert(out, c)
			rec(c)
		end
	end
	rec(self)
	return out
end
function Instance_:FindFirstChild(name, recursive)
	for _, c in rawget(self, "_c") do
		if rawget(c, "_p").Name == name then
			return c
		end
	end
	if recursive then
		for _, c in rawget(self, "_c") do
			local f = c:FindFirstChild(name, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function Instance_:WaitForChild(name, timeout)
	local c = self:FindFirstChild(name)
	local t0 = clock
	while not c do
		if timeout and clock - t0 > timeout then
			return nil
		end
		if clock - t0 > 30 and not timeout then
			error("Infinite yield on WaitForChild " .. name .. " in " .. self.Name)
		end
		task.wait(0.1)
		c = self:FindFirstChild(name)
	end
	return c
end
function Instance_:FindFirstChildOfClass(cls)
	for _, c in rawget(self, "_c") do
		if c.ClassName == cls then
			return c
		end
	end
	return nil
end
function Instance_:FindFirstChildWhichIsA(cls)
	for _, c in rawget(self, "_c") do
		if c:IsA(cls) then
			return c
		end
	end
	return nil
end
function Instance_:FindFirstAncestorOfClass(cls)
	local p = self.Parent
	while p do
		if p.ClassName == cls then
			return p
		end
		p = p.Parent
	end
	return nil
end
function Instance_:FindFirstAncestorWhichIsA(cls)
	local p = self.Parent
	while p do
		if p:IsA(cls) then
			return p
		end
		p = p.Parent
	end
	return nil
end
function Instance_:IsDescendantOf(other)
	local p = self.Parent
	while p do
		if p == other then
			return true
		end
		p = p.Parent
	end
	return false
end
function Instance_:IsAncestorOf(other)
	return other:IsDescendantOf(self)
end
function Instance_:Destroy()
	local ev = rawget(self, "_e").Destroying
	if ev then
		ev:Fire()
	end
	for _, c in self:GetChildren() do
		c:Destroy()
	end
	self.Parent = nil
	rawget(self, "_p").Destroyed = true
end
function Instance_:ClearAllChildren()
	for _, c in self:GetChildren() do
		c:Destroy()
	end
end
function Instance_:SetAttribute(k, v)
	local a = rawget(self, "_a")
	local old = a[k]
	a[k] = v
	if old ~= v then
		local e = rawget(self, "_e")
		local s = e["attr:" .. k]
		if s then
			s:Fire()
		end
		if e.AttributeChanged then
			e.AttributeChanged:Fire(k)
		end
	end
end
function Instance_:GetAttribute(k)
	return rawget(self, "_a")[k]
end
function Instance_:GetAttributes()
	return table.clone(rawget(self, "_a"))
end
function Instance_:GetAttributeChangedSignal(k)
	local e = rawget(self, "_e")
	local s = e["attr:" .. k]
	if not s then
		s = Signal.new()
		e["attr:" .. k] = s
	end
	return s
end
function Instance_:GetPropertyChangedSignal(k)
	local e = rawget(self, "_e")
	local s = e["prop:" .. k]
	if not s then
		s = Signal.new()
		e["prop:" .. k] = s
	end
	return s
end
function Instance_:Clone()
	local c = newInstance(self.ClassName, self.Name)
	for k, v in rawget(self, "_p") do
		if k ~= "Parent" then
			rawget(c, "_p")[k] = v
		end
	end
	for k, v in rawget(self, "_a") do
		rawget(c, "_a")[k] = v
	end
	for _, ch in rawget(self, "_c") do
		ch:Clone().Parent = c
	end
	return c
end
function Instance_:GetFullName()
	local n = self.Name
	local p = self.Parent
	while p and p.ClassName ~= "DataModel" do
		n = p.Name .. "." .. n
		p = p.Parent
	end
	return n
end
-- PVInstance
local function parts(self)
	local out = {}
	if self:IsA("BasePart") then
		table.insert(out, self)
	end
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end
function Instance_:GetPivot()
	if self:IsA("BasePart") then
		return self.CFrame * self.PivotOffset
	end
	local pp = self.PrimaryPart
	if pp then
		return pp.CFrame * pp.PivotOffset
	end
	local wp = rawget(self, "_p").WorldPivot
	if wp then
		return wp
	end
	for _, p in parts(self) do
		return p.CFrame
	end
	return CFrame.identity
end
function Instance_:PivotTo(cf)
	local pp = cf.p
	if pp.X ~= pp.X or pp.Y ~= pp.Y or pp.Z ~= pp.Z then
		error("PivotTo with NaN position on " .. self.Name)
	end
	if self:IsA("BasePart") then
		local delta = cf * self:GetPivot():Inverse()
		for _, p in parts(self) do
			p.CFrame = delta * p.CFrame
		end
		return
	end
	local old = self:GetPivot()
	local delta = cf * old:Inverse()
	for _, p in parts(self) do
		p.CFrame = delta * p.CFrame
	end
	if not self.PrimaryPart then
		rawget(self, "_p").WorldPivot = cf
	end
end
function Instance_:SetPrimaryPartCFrame(cf)
	self:PivotTo(cf)
end
function Instance_:GetBoundingBox()
	return self:GetPivot(), Vector3.new(4, 4, 4)
end
function Instance_:SetNetworkOwner() end
function Instance_:GetNetworkOwner()
	return nil
end
function Instance_:GetMass()
	return 1
end
function Instance_:ApplyImpulse() end
-- Humanoid
function Instance_:MoveTo(target)
	rawget(self, "_p").MoveTarget = target
end
function Instance_:SetStateEnabled() end
function Instance_:ChangeState() end
function Instance_:GetState()
	return Enum.HumanoidStateType.Running
end
function Instance_:LoadAnimation()
	return { Play = function() end, Stop = function() end, Priority = nil, Length = 1 }
end
function Instance_:PlayEmote()
	return true
end
-- sounds / misc
function Instance_:Play() end
function Instance_:Stop() end
function Instance_:Pause() end
function Instance_:Resume() end
function Instance_:Emit() end
function Instance_:Clear() end
-- remotes
G.FIRED = {}
function Instance_:FireClient(player, ...)
	G.FIRED[self.Name] = (G.FIRED[self.Name] or 0) + 1
	if G.OnFireClient then
		G.OnFireClient(self.Name, player, ...)
	end
	if G.CLIENT_RUNNING and player == G.LOCAL_PLAYER then
		self.OnClientEvent:Fire(...)
	end
end
function Instance_:FireAllClients(...)
	G.FIRED[self.Name] = (G.FIRED[self.Name] or 0) + 1
	if G.OnFireClient then
		G.OnFireClient(self.Name, nil, ...)
	end
	if G.CLIENT_RUNNING then
		self.OnClientEvent:Fire(...)
	end
end
function Instance_:FireServer(...)
	G.CLIENT_SENT = G.CLIENT_SENT or {}
	G.CLIENT_SENT[self.Name] = (G.CLIENT_SENT[self.Name] or 0) + 1
	self.OnServerEvent:Fire(G.LOCAL_PLAYER, ...)
end
function Instance_:InvokeServer(...)
	local fn = self.OnServerInvoke
	if fn then
		return fn(G.LOCAL_PLAYER, ...)
	end
	return nil
end
function Instance_:Fire(...)
	self.Event:Fire(...)
end
-- prompts
function Instance_:InputHoldBegin() end
function Instance_:InputHoldEnd() end

Instance = {}
function Instance.new(className, parent)
	local i = newInstance(className)
	if className == "Humanoid" then
		rawget(i, "_p").Health = 100
	end
	if className == "Model" then
		rawget(i, "_p").PrimaryPart = nil
	end
	if parent then
		i.Parent = parent
	end
	return i
end

typeof = function(v)
	local mt = getmetatable(v)
	if mt and TYPE[mt] then
		return TYPE[mt]
	end
	return realTypeof(v)
end

--============================ GAME / SERVICES ============================--
game = newInstance("DataModel", "Game")
rawget(game, "_p").JobId = "sim-job"
rawget(game, "_p").PlaceId = 123
rawget(game, "_p").PrivateServerId = ""
rawget(game, "_p").PrivateServerOwnerId = 0
local services = {}
local closers = {}
function Instance_:BindToClose(fn)
	table.insert(closers, fn)
end
function Instance_:IsLoaded()
	return true
end
local SERVICE_SETUP = {}
function Instance_:GetService(name)
	local s = services[name]
	if not s then
		s = newInstance(name, name)
		services[name] = s
		s.Parent = game
		if SERVICE_SETUP[name] then
			SERVICE_SETUP[name](s)
		end
	end
	return s
end
workspace = game:GetService("Workspace")
local Workspace = workspace

SERVICE_SETUP.Workspace = function(ws)
	local cam = newInstance("Camera", "Camera")
	rawget(cam, "_p").ViewportSize = Vector2.new(1280, 720)
	rawget(cam, "_p").CFrame = CFrame.new(0, 10, 0)
	rawget(cam, "_p").FieldOfView = 70
	cam.Parent = ws
	rawget(ws, "_p").CurrentCamera = cam
	rawget(ws, "_p").Terrain = newInstance("Terrain", "Terrain")
	rawget(ws, "_p").Terrain.Parent = ws
end
SERVICE_SETUP.Workspace(Workspace)
do
	local L = game:GetService("Lighting")
	local lp = rawget(L, "_p")
	lp.Ambient = Color3.new(0.2, 0.2, 0.2)
	lp.OutdoorAmbient = Color3.new(0.2, 0.2, 0.2)
	lp.FogColor = Color3.new(0, 0, 0)
	lp.FogStart = 0
	lp.FogEnd = 500
	lp.ExposureCompensation = 0
	local grade = newInstance("ColorCorrectionEffect", "Grade")
	rawget(grade, "_p").TintColor = Color3.new(1, 1, 1)
	rawget(grade, "_p").Saturation = 0
	rawget(grade, "_p").Brightness = 0
	rawget(grade, "_p").Contrast = 0
	grade.Parent = L
	local bloom = newInstance("BloomEffect", "Bloom")
	rawget(bloom, "_p").Intensity = 0.5
	bloom.Parent = L
end
-- flat-floor raycasts: downward rays hit y=0 (main floor) or the basement floor;
-- other rays only hit player structures (Workspace.Store.Structures) so the AI can bump into them
local FLOOR = newInstance("Part", "SimFloor")
local function excluded(inst, params)
	if not params then
		return false
	end
	for _, f in params.FilterDescendantsInstances or {} do
		if inst == f or inst:IsDescendantOf(f) then
			return true
		end
	end
	return false
end
local function rayOBB(origin, dir, part)
	local cf = part.CFrame
	local inv = cf:Inverse()
	local o = inv * origin
	local d = matvec(inv.r, dir)
	local h = part.Size / 2
	local tmin, tmax = 0, 1
	for _, axis in { "X", "Y", "Z" } do
		local oa, da, ha = o[axis], d[axis], h[axis]
		if math.abs(da) < 1e-9 then
			if oa < -ha or oa > ha then
				return nil
			end
		else
			local t1, t2 = (-ha - oa) / da, (ha - oa) / da
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tmin = math.max(tmin, t1)
			tmax = math.min(tmax, t2)
			if tmin > tmax then
				return nil
			end
		end
	end
	return tmin
end
function Instance_:Raycast(origin, dir, params)
	local store = rawget(self, "_p").ClassName == "Workspace" and self:FindFirstChild("Store")
	local structures = store and store:FindFirstChild("Structures")
	local best, bestT = nil, math.huge
	if structures then
		for _, d in structures:GetDescendants() do
			if d:IsA("BasePart") and d.CanCollide ~= false and d.CanQuery ~= false and not excluded(d, params) then
				local t = rayOBB(origin, dir, d)
				if t and t < bestT then
					best, bestT = d, t
				end
			end
		end
	end
	if best then
		return { Position = origin + dir * bestT, Normal = -dir.Unit, Instance = best, Material = Enum.Material.Plastic, Distance = dir.Magnitude * bestT }
	end
	if dir.Y < -0.5 and math.abs(dir.X) < 1 and math.abs(dir.Z) < 1 then
		local floorY = if origin.Y < -1 then -24 else 0
		if origin.Y >= floorY and origin.Y + dir.Y <= floorY then
			return { Position = Vector3.new(origin.X, floorY, origin.Z), Normal = Vector3.new(0, 1, 0), Instance = FLOOR, Material = Enum.Material.Plastic, Distance = origin.Y - floorY }
		end
	end
	return nil
end
function Instance_:GetPartBoundsInBox()
	return {}
end
function Instance_:GetPartBoundsInRadius()
	return {}
end
function Instance_:GetPartsInPart()
	return {}
end
function Instance_:GetServerTimeNow()
	return 1760000000 + clock
end

SERVICE_SETUP.RunService = function(rs)
	local hb = Signal.new()
	rawget(rs, "_e").Heartbeat = hb
	local stepped = Signal.new()
	local render = Signal.new()
	rawget(rs, "_e").Stepped = stepped
	rawget(rs, "_e").RenderStepped = render
	rawget(rs, "_e").PreSimulation = Signal.new()
	table.insert(heartbeatFns, function(dt)
		for _, h in table.clone(hb.handlers) do
			if h.connected then
				local th = coroutine.create(h.fn)
				resume(th, dt)
			end
		end
		if G.CLIENT_RUNNING then
			for _, h in table.clone(stepped.handlers) do
				if h.connected then
					resume(coroutine.create(h.fn), clock, dt)
				end
			end
			for _, h in table.clone(render.handlers) do
				if h.connected then
					resume(coroutine.create(h.fn), dt)
				end
			end
			for _, fn in G.RENDER_BINDS do
				resume(coroutine.create(fn), dt)
			end
		end
	end)
end
function Instance_:IsStudio()
	return G.STUDIO == true
end
function Instance_:IsServer()
	return true
end
function Instance_:IsClient()
	return G.CLIENT_RUNNING == true
end
function Instance_:IsRunning()
	return true
end
G.RENDER_BINDS = {}
function Instance_:BindToRenderStep(name, priority, fn)
	G.RENDER_BINDS[name] = fn
end
function Instance_:UnbindFromRenderStep() end

-- DataStores
G.DATA = {}
G.DS_FAIL = false
function Instance_:GetDataStore(name)
	local ds = newInstance("DataStore", name)
	G.DATA[name] = G.DATA[name] or {}
	local store = G.DATA[name]
	function ds.UpdateAsync(_, key, fn)
		if G.DS_FAIL then
			error("DataStore request failed (simulated)")
		end
		task.wait(0.05)
		local new = fn(store[key])
		if new ~= nil then
			store[key] = new
		end
		return store[key]
	end
	function ds.GetAsync(_, key)
		return store[key]
	end
	function ds.SetAsync(_, key, v)
		store[key] = v
	end
	return ds
end
-- MemoryStore
function Instance_:GetSortedMap(name)
	local m = newInstance("MemoryStoreSortedMap", name)
	local data = {}
	function m.SetAsync(_, k, v)
		data[k] = v
		return true
	end
	function m.GetAsync(_, k)
		return data[k]
	end
	function m.UpdateAsync(_, k, fn)
		local v = fn(data[k])
		if v ~= nil then
			data[k] = v
		end
		return v
	end
	function m.RemoveAsync(_, k)
		data[k] = nil
	end
	function m.GetRangeAsync()
		local out = {}
		for k, v in data do
			table.insert(out, { key = k, value = v })
		end
		return out
	end
	return m
end
-- Teleport
G.TELEPORTS = {}
function Instance_:ReserveServer()
	return "code-" .. math.random(1, 99999), "psid-" .. math.random(1, 99999)
end
function Instance_:TeleportAsync(placeId, players, options)
	table.insert(G.TELEPORTS, { Players = players, Options = options })
end
function Instance_:SetTeleportData(d)
	rawget(self, "_p").TeleportData = d
end
function Instance_:GetTeleportData()
	return rawget(self, "_p").TeleportData
end
-- Tween
function Instance_:Create(obj, info, props)
	local t = newInstance("Tween", "Tween")
	local cancelled = false
	function t.Play()
		task.delay(info and info.Time or 0, function()
			if cancelled then
				return
			end
			for k, v in props do
				obj[k] = v
			end
			t.Completed:Fire(Enum.PlaybackState.Completed)
		end)
	end
	function t.Cancel()
		cancelled = true
	end
	function t.Pause() end
	return t
end
-- CollectionService
local tags = {}
function Instance_:AddTag(inst, tag)
	tags[tag] = tags[tag] or {}
	tags[tag][inst] = true
end
function Instance_:RemoveTag(inst, tag)
	if tags[tag] then
		tags[tag][inst] = nil
	end
end
function Instance_:HasTag(inst, tag)
	return tags[tag] ~= nil and tags[tag][inst] == true
end
function Instance_:GetTagged(tag)
	local out = {}
	for i in tags[tag] or {} do
		table.insert(out, i)
	end
	return out
end
function Instance_:GetInstanceAddedSignal()
	return Signal.new()
end
function Instance_:GetInstanceRemovedSignal()
	return Signal.new()
end
-- Pathfinding: straight lines
function Instance_:CreatePath()
	local path = newInstance("Path", "Path")
	local wps = {}
	rawget(path, "_p").Status = Enum.PathStatus.Success
	function path.ComputeAsync(_, from, to)
		task.wait(0.01)
		wps = {}
		local n = math.max(1, math.floor((to - from).Magnitude / 7))
		for i = 0, n do
			table.insert(wps, { Position = from:Lerp(to, i / n), Action = Enum.PathWaypointAction.Walk })
		end
		path.Status = Enum.PathStatus.Success
	end
	function path.GetWaypoints()
		return wps
	end
	return path
end
-- Physics
function Instance_:RegisterCollisionGroup() end
function Instance_:CollisionGroupSetCollidable() end
-- Debris
function Instance_:AddItem(inst, t)
	task.delay(t or 10, function()
		if inst.Destroy then
			inst:Destroy()
		end
	end)
end
-- Marketplace
function Instance_:PromptProductPurchase() end

--============================ CLIENT SERVICES ============================--
SERVICE_SETUP.UserInputService = function(uis)
	rawget(uis, "_p").TouchEnabled = false
	rawget(uis, "_p").KeyboardEnabled = true
	rawget(uis, "_p").GamepadEnabled = false
	rawget(uis, "_p").MouseEnabled = true
end
function Instance_:GetMouseLocation()
	return Vector2.new(640, 360)
end
function Instance_:ViewportPointToRay(x, y)
	local cf = self.CFrame
	return { Origin = cf.Position, Direction = cf.LookVector }
end
function Instance_:ScreenPointToRay(x, y)
	return self:ViewportPointToRay(x, y)
end
function Instance_:WorldToViewportPoint(p)
	return Vector3.new(640, 360, 10), true
end
function Instance_:BindAction() end
function Instance_:BindActionAtPriority(name, fn)
	G.CAS = G.CAS or {}
	G.CAS[name] = fn
end
function Instance_:UnbindAction() end
function Instance_:SetCoreGuiEnabled() end
function Instance_:SetCore() end
function Instance_:PreloadAsync() end
function Instance_:RemoveDefaultLoadingScreen() end
function Instance_:GetLastInputType()
	return Enum.UserInputType.Keyboard
end
function Instance_:IsKeyDown()
	return false
end
function Instance_:PlayLocalSound() end

--============================ PLAYERS ============================--
local Players = game:GetService("Players")
local playerList = {}
function Instance_:GetPlayers()
	return table.clone(playerList)
end
function Instance_:GetPlayerByUserId(id)
	for _, p in playerList do
		if p.UserId == id then
			return p
		end
	end
	return nil
end
function Instance_:GetPlayerFromCharacter(c)
	for _, p in playerList do
		if p.Character == c then
			return p
		end
	end
	return nil
end
function Instance_:GetJoinData()
	return { TeleportData = G.TELEPORT_DATA }
end
function Instance_:Kick() end

local function makeCharacter(player)
	local char = newInstance("Model", player.Name)
	local function part(name, size, offset)
		local p = newInstance("Part", name)
		p.Size = size
		p.CFrame = CFrame.new(0, 3 + offset, 0)
		p.Parent = char
		return p
	end
	local hrp = part("HumanoidRootPart", Vector3.new(2, 2, 1), 0)
	part("Head", Vector3.new(1, 1, 1), 1.5)
	part("RightHand", Vector3.new(0.5, 0.5, 0.5), -1)
	part("UpperTorso", Vector3.new(2, 1.6, 1), 0.2)
	char.PrimaryPart = hrp
	local hum = newInstance("Humanoid", "Humanoid")
	hum.Parent = char
	local animator = newInstance("Animator", "Animator")
	animator.Parent = hum
	return char
end

function Instance_:LoadCharacter()
	local player = self
	local old = player.Character
	if old then
		old:Destroy()
	end
	local char = makeCharacter(player)
	char.Parent = Workspace
	player.Character = char
	player.CharacterAdded:Fire(char)
	task.wait(0.03)
end

G.NEXT_USER = 1000
function G.AddPlayer(name)
	G.NEXT_USER += 1
	local p = newInstance("Player", name)
	rawget(p, "_p").UserId = G.NEXT_USER
	rawget(p, "_p").DisplayName = name
	newInstance("PlayerGui", "PlayerGui").Parent = p
	newInstance("Backpack", "Backpack").Parent = p
	p.Parent = Players
	table.insert(playerList, p)
	Players.PlayerAdded:Fire(p)
	return p
end
function G.RemovePlayer(p)
	Players.PlayerRemoving:Fire(p)
	local i = table.find(playerList, p)
	if i then
		table.remove(playerList, i)
	end
	if p.Character then
		p.Character:Destroy()
	end
	p.Parent = nil
end
function G.Close()
	for _, fn in closers do
		task.spawn(fn)
	end
end

-- Humanoid movement sim: walk root parts toward MoveTo targets
table.insert(heartbeatFns, function(dt)
	for inst in humanoids do
		local props = rawget(inst, "_p")
		if props.MoveTarget and props.Parent then
			local model = props.Parent
			local root = model:FindFirstChild("HumanoidRootPart")
			if root and not root.Anchored then
				local pos = root.Position
				local target = props.MoveTarget
				local to = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
				local speed = props.WalkSpeed or 16
				local step = speed * dt
				if to.Magnitude <= step or speed <= 0 then
					local newPos = if speed > 0 then Vector3.new(target.X, target.Y, target.Z) else pos
					model:PivotTo(CFrame.new(newPos))
					root.AssemblyLinearVelocity = Vector3.zero
					if speed > 0 then
						props.MoveTarget = nil
						local ev = rawget(inst, "_e").MoveToFinished
						if ev then
							ev:Fire(true)
						end
					end
				elseif Workspace:Raycast(pos, to.Unit * (step + 2)) and Workspace:Raycast(pos, to.Unit * (step + 2)).Instance ~= FLOOR then
					-- blocked by a structure
					root.AssemblyLinearVelocity = Vector3.zero
				else
					local dir = to.Unit
					local ny = pos.Y + (target.Y - pos.Y) * math.min(1, step / math.max(1, to.Magnitude))
					local newPos = Vector3.new(pos.X + dir.X * step, ny, pos.Z + dir.Z * step)
					model:PivotTo(CFrame.lookAt(newPos, newPos + dir))
					root.AssemblyLinearVelocity = dir * speed
				end
			end
		end
	end
end)

--============================ SCRIPTS / REQUIRE ============================--
local moduleCache = {}
local function runSource(inst, kind)
	local path = inst:GetAttribute("SourcePath")
	local src = SOURCES[path]
	local fn, err = loadstring(src, "=" .. path)
	if not fn then
		error("compile error in " .. path .. ": " .. tostring(err))
	end
	local env = setmetatable({ script = inst }, { __index = ENV })
	setfenv(fn, env)
	return fn
end
local realRequire = require
require = function(m)
	if type(m) == "table" and getmetatable(m) == InstMT then
		if moduleCache[m] ~= nil then
			return moduleCache[m]
		end
		local fn = runSource(m, "module")
		local result = fn()
		moduleCache[m] = result
		return result
	end
	return realRequire(m)
end

-- build the tree from TREE: { { Path = "ServerScriptService/Services/State", Class = "ModuleScript", Source = "src/..." } }
local function getPath(path)
	local parts = string.split(path, "/")
	local node = game:GetService(parts[1])
	for i = 2, #parts do
		local nxt = node:FindFirstChild(parts[i])
		if not nxt then
			nxt = newInstance("Folder", parts[i])
			nxt.Parent = node
		end
		node = nxt
	end
	return node
end
G.ServerScripts = {}
G.ClientScripts = {}
for _, entry in TREE do
	local parts = string.split(entry.Path, "/")
	local name = table.remove(parts)
	local parent = getPath(table.concat(parts, "/"))
	local inst = newInstance(entry.Class, name)
	inst:SetAttribute("SourcePath", entry.Source)
	inst.Parent = parent
	if entry.Class == "Script" then
		table.insert(G.ServerScripts, inst)
	elseif entry.Class == "LocalScript" then
		table.insert(G.ClientScripts, inst)
	end
end
-- start the client for one player: ReplicatedFirst first, then StarterPlayerScripts
function G.StartClient(player)
	G.CLIENT_RUNNING = true
	G.LOCAL_PLAYER = player
	rawget(game:GetService("Players"), "_p").LocalPlayer = player
	table.sort(G.ClientScripts, function(a, b)
		return a:IsDescendantOf(game:GetService("ReplicatedFirst")) and not b:IsDescendantOf(game:GetService("ReplicatedFirst"))
	end)
	for _, s in G.ClientScripts do
		task.spawn(function()
			runSource(s, "script")()
		end)
	end
end
function G.StartServer()
	for _, s in G.ServerScripts do
		task.spawn(function()
			runSource(s, "script")()
		end)
	end
end
G.Signal = Signal
G.Players = Players
G.Workspace = Workspace
G.Services = services
