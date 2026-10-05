warn = function(...) print("WARN", ...) end
-- Minimal fake Roblox engine for running the server code headless with virtual time.
-- SOURCES (path -> source) is defined before this file is concatenated.

local clock = 0
local queue = {} -- { time, seq, thread, args }
local seq = 0
local LOG = {}
local function log(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	table.insert(LOG, string.format("[%7.2f] %s", clock, table.concat(parts, " ")))
end
local VERBOSE = false

local function schedule(t, thread, ...)
	seq += 1
	table.insert(queue, { time = t, seq = seq, thread = thread, args = table.pack(...) })
end

local function resume(thread, ...)
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		error("COROUTINE ERROR: " .. tostring(err) .. "\n" .. debug.traceback(thread), 0)
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
	schedule(clock, th, ...)
	return th
end
function task.delay(t, fn, ...)
	local th = coroutine.create(fn)
	schedule(clock + (t or 0), th, ...)
	return th
end
function task.wait(t)
	local th = coroutine.running()
	schedule(clock + math.max(t or 0.03, 0.03), th)
	return coroutine.yield()
end
wait = task.wait

local function runUntil(tEnd)
	while true do
		table.sort(queue, function(a, b)
			if a.time == b.time then
				return a.seq < b.seq
			end
			return a.time < b.time
		end)
		local item = queue[1]
		if not item or item.time > tEnd then
			clock = tEnd
			return
		end
		table.remove(queue, 1)
		clock = math.max(clock, item.time)
		if coroutine.status(item.thread) == "suspended" then
			resume(item.thread, table.unpack(item.args, 1, item.args.n))
		end
	end
end

local realOs = os
os = setmetatable({
	clock = function()
		return clock
	end,
	time = function()
		return 1700000000 + math.floor(clock)
	end,
}, { __index = realOs })

-- Signals ------------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ handlers = {}, waiting = {} }, Signal)
end
function Signal:Connect(fn)
	local h = { fn = fn, connected = true }
	table.insert(self.handlers, h)
	return {
		Disconnect = function()
			h.connected = false
		end,
		Connected = true,
	}
end
Signal.connect = Signal.Connect
function Signal:Fire(...)
	for _, h in table.clone(self.handlers) do
		if h.connected then
			task.spawn(h.fn, ...)
		end
	end
	local w = self.waiting
	self.waiting = {}
	for _, th in w do
		schedule(clock, th, ...)
	end
end
function Signal:Wait()
	table.insert(self.waiting, coroutine.running())
	return coroutine.yield()
end
function Signal:Once(fn)
	local c
	c = self:Connect(function(...)
		c.Disconnect()
		fn(...)
	end)
	return c
end

-- Datatypes ------------------------------------------------------------------------
Vector3 = {}
local V3 = {}
V3.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return Vector3.new(v.X / m, v.Y / m, v.Z / m)
	end
	return nil
end
V3.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		a, b = b, a
	end
	return Vector3.new(a.X * b, a.Y * b, a.Z * b)
end
V3.__tostring = function(v)
	return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
end
function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, __type = "Vector3" }, V3)
end
Vector3.zero = Vector3.new()
Vector3.one = Vector3.new(1, 1, 1)

CFrame = {}
local CF = {}
CF.__index = function(c, k)
	if k == "Position" then
		return c.P
	end
end
CF.__add = function(c, v)
	return CFrame.new(c.P.X + v.X, c.P.Y + v.Y, c.P.Z + v.Z)
end
function CFrame.new(x, y, z)
	if type(x) == "table" then
		return setmetatable({ P = x }, CF)
	end
	return setmetatable({ P = Vector3.new(x, y, z) }, CF)
end

local function anyCtor()
	return setmetatable({}, {
		__index = function(_, _k)
			return function(...)
				return { ... }
			end
		end,
	})
end
Color3 = { fromHex = function(h) return { hex = h } end, new = function(...) return { ... } end, fromRGB = function(...) return { ... } end }
UDim2 = anyCtor()
UDim = anyCtor()
Vector2 = anyCtor()
NumberSequence = anyCtor()
NumberSequenceKeypoint = anyCtor()
ColorSequence = anyCtor()
ColorSequenceKeypoint = anyCtor()
NumberRange = anyCtor()
TweenInfo = anyCtor()
Font = anyCtor()
Enum = setmetatable({}, {
	__index = function(_, enumName)
		return setmetatable({}, {
			__index = function(_, item)
				return enumName .. "." .. item
			end,
		})
	end,
})

Random = {}
function Random.new(seed)
	local state = seed or 12345
	local function nextf()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
	return {
		NextInteger = function(_, a, b)
			return a + math.floor(nextf() * (b - a + 1))
		end,
		NextNumber = function(_, a, b)
			a, b = a or 0, b or 1
			return a + nextf() * (b - a)
		end,
	}
end

typeof = function(v)
	if type(v) == "table" and v.__type then
		return v.__type
	end
	if type(v) == "table" and v.__instance then
		return "Instance"
	end
	return type(v)
end

-- Instances -------------------------------------------------------------------------
local Inst = {}
local instMeta = {}
local CLASS_PARENTS = {
	Part = "BasePart", SpawnLocation = "BasePart", WedgePart = "BasePart", BasePart = "PVInstance",
	Model = "PVInstance", ModuleScript = "LuaSourceContainer", Script = "LuaSourceContainer",
	TextLabel = "GuiObject", Frame = "GuiObject", ParticleEmitter = "Instance", Trail = "Instance",
}
local function isA(cls, target)
	while cls do
		if cls == target or target == "Instance" then
			return true
		end
		cls = CLASS_PARENTS[cls]
	end
	return false
end

instMeta.__index = function(self, k)
	local m = Inst[k]
	if m then
		return m
	end
	local props = rawget(self, "_props")
	if props[k] ~= nil then
		return props[k]
	end
	local kids = rawget(self, "_children")
	for _, c in kids do
		if c._props.Name == k then
			return c
		end
	end
	local getter = rawget(self, "_get")
	if getter and getter[k] then
		return getter[k](self)
	end
	if k == "Parent" then
		return nil
	end
	-- unknown member: methods are no-ops returning nil, signals are created on demand
	if k:match("Changed$") or k:match("Added$") or k:match("Removing$") or k == "Activated" or k == "Touched" or k == "Event" or k == "OnServerEvent" or k == "Completed" or k == "Died" then
		local sig = Signal.new()
		props[k] = sig
		return sig
	end
	return nil
end
instMeta.__newindex = function(self, k, v)
	if k == "Parent" then
		local old = self._props.Parent
		if old then
			local list = old._children
			for i, c in list do
				if c == self then
					table.remove(list, i)
					break
				end
			end
		end
		self._props.Parent = v
		if v then
			table.insert(v._children, self)
			local onAdd = rawget(v, "_onChildAdded")
			if onAdd then
				onAdd(self)
			end
		end
		return
	end
	local setter = rawget(self, "_set")
	if setter and setter[k] then
		setter[k](self, v)
		return
	end
	self._props[k] = v
end
instMeta.__tostring = function(self)
	return self._props.Name
end

local function newInstance(className, name)
	local self = setmetatable({ __instance = true, _props = { ClassName = className, Name = name or className }, _children = {}, _attrs = {}, _attrSignals = {} }, instMeta)
	return self
end

function Inst:IsA(c)
	return isA(self._props.ClassName, c)
end
function Inst:GetChildren()
	return table.clone(self._children)
end
function Inst:GetDescendants()
	local out = {}
	local function rec(i)
		for _, c in i._children do
			table.insert(out, c)
			rec(c)
		end
	end
	rec(self)
	return out
end
function Inst:FindFirstChild(name, recursive)
	for _, c in self._children do
		if c._props.Name == name then
			return c
		end
	end
	if recursive then
		for _, c in self._children do
			local f = c:FindFirstChild(name, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function Inst:WaitForChild(name, timeout)
	local t0 = clock
	while true do
		local c = self:FindFirstChild(name)
		if c then
			return c
		end
		if timeout and clock - t0 >= timeout then
			return nil
		end
		task.wait(0.1)
	end
end
function Inst:FindFirstChildOfClass(cls)
	for _, c in self._children do
		if c._props.ClassName == cls then
			return c
		end
	end
	return nil
end
function Inst:FindFirstChildWhichIsA(cls)
	for _, c in self._children do
		if c:IsA(cls) then
			return c
		end
	end
	return nil
end
function Inst:IsDescendantOf(other)
	local p = self._props.Parent
	while p do
		if p == other then
			return true
		end
		p = p._props.Parent
	end
	return false
end
function Inst:Destroy()
	self.Parent = nil
	self._props.Destroyed = true
end
function Inst:ClearAllChildren()
	for _, c in table.clone(self._children) do
		c:Destroy()
	end
end
function Inst:SetAttribute(k, v)
	if self._attrs[k] == v then
		return
	end
	self._attrs[k] = v
	local s = self._attrSignals[k]
	if s then
		s:Fire()
	end
end
function Inst:GetAttribute(k)
	return self._attrs[k]
end
function Inst:GetAttributeChangedSignal(k)
	self._attrSignals[k] = self._attrSignals[k] or Signal.new()
	return self._attrSignals[k]
end
function Inst:Clone()
	local c = newInstance(self._props.ClassName, self._props.Name)
	for k, v in self._props do
		if k ~= "Parent" and type(v) ~= "table" or (type(v) == "table" and getmetatable(v) == CF) or (type(v) == "table" and getmetatable(v) == V3) then
			if k ~= "Parent" then
				c._props[k] = v
			end
		end
	end
	for k, v in self._attrs do
		c._attrs[k] = v
	end
	for _, child in self._children do
		child:Clone().Parent = c
	end
	return c
end
function Inst:PivotTo(cf)
	local hrp = self:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp._props.Position = cf.P
		hrp._props.CFrame = cf
	end
end
function Inst:GetFullName()
	return self._props.Name
end

-- Instance.new: generic objects that accept any property
Instance = {}
function Instance.new(className, parent)
	local i = newInstance(className)
	if className == "BindableEvent" then
		i._props.Event = Signal.new()
		i._props.Fire = function(self, ...)
			self._props.Event:Fire(...)
		end
	elseif className == "TeleportOptions" then
		i._props.SetTeleportData = function() end
	elseif className == "ParticleEmitter" then
		i._props.Emit = function() end
	end
	if parent then
		i.Parent = parent
	end
	return i
end

-- Services --------------------------------------------------------------------------
game = newInstance("DataModel", "game")
game._props.JobId = "job-1"
game._props.PlaceId = 1
game._props.PrivateServerId = ""
game._props.PrivateServerOwnerId = 0
game._props.BindToClose = function(_, fn)
	table.insert(game._bindToClose, fn)
end
rawset(game, "_bindToClose", {})

local services = {}
local function service(name)
	if not services[name] then
		local s = newInstance(name, name)
		s.Parent = game
		services[name] = s
	end
	return services[name]
end
game._props.GetService = function(_, name)
	return service(name)
end

workspace = service("Workspace")
workspace._props.GetServerTimeNow = function()
	return 1700000000 + clock
end

local RunService = service("RunService")
RunService._props.IsStudio = function()
	return G.SIM_STUDIO == true
end
RunService._props.IsServer = function()
	return true
end
RunService._props.Heartbeat = Signal.new()

local CollectionService = service("CollectionService")
CollectionService._props.AddTag = function() end

local Debris = service("Debris")
Debris._props.AddItem = function() end

-- DataStore: in-memory, can be made to fail
G.DATA = {}
local DataStoreService = service("DataStoreService")
DataStoreService._props.GetDataStore = function(_, name)
	local ds = newInstance("DataStore", name)
	ds._props.UpdateAsync = function(_, key, fn)
		task.wait(0.1)
		if G.DATASTORE_FAIL then
			error("DataStore request failed (simulated)")
		end
		local old = G.DATA[key]
		local new = fn(old and table.clone(old) or nil)
		if new ~= nil then
			G.DATA[key] = new
			return new
		end
		return old
	end
	return ds
end

-- MemoryStore: in-memory sorted maps
G.MEM = {}
local MemoryStoreService = service("MemoryStoreService")
MemoryStoreService._props.GetSortedMap = function(_, name)
	G.MEM[name] = G.MEM[name] or {}
	local store = G.MEM[name]
	local m = newInstance("MemoryStoreSortedMap", name)
	m._props.SetAsync = function(_, k, v)
		store[k] = v
		return true
	end
	m._props.GetAsync = function(_, k)
		return store[k]
	end
	m._props.RemoveAsync = function(_, k)
		store[k] = nil
	end
	m._props.UpdateAsync = function(_, k, fn)
		local v = fn(store[k])
		if v ~= nil then
			store[k] = v
		end
		return v
	end
	m._props.GetRangeAsync = function()
		local out = {}
		for k, v in store do
			table.insert(out, { key = k, value = v })
		end
		return out
	end
	return m
end

G.TELEPORTS = {}
local TeleportService = service("TeleportService")
TeleportService._props.ReserveServer = function()
	return "ACCESS-" .. tostring(#G.TELEPORTS + 1), "PSID-" .. tostring(#G.TELEPORTS + 1)
end
TeleportService._props.TeleportAsync = function(_, placeId, players, options)
	table.insert(G.TELEPORTS, { placeId = placeId, players = players, options = options })
end
TeleportService._props.TeleportInitFailed = Signal.new()

-- Players -----------------------------------------------------------------------------
local Players = service("Players")
Players._props.PlayerAdded = Signal.new()
Players._props.PlayerRemoving = Signal.new()
Players._props.GetPlayers = function()
	local out = {}
	for _, c in Players._children do
		if c._props.ClassName == "Player" then
			table.insert(out, c)
		end
	end
	return out
end

local function makeCharacter(player, pos)
	local char = newInstance("Model", player._props.Name)
	local hrp = newInstance("Part", "HumanoidRootPart")
	hrp._props.Position = pos
	hrp._props.CFrame = CFrame.new(pos)
	hrp.Parent = char
	local head = newInstance("Part", "Head")
	head.Parent = char
	local hum = newInstance("Humanoid", "Humanoid")
	hum._props.Health = 100
	hum._props.WalkSpeed = 16
	hum._props.JumpHeight = 7.2
	hum.Parent = char
	char.Parent = workspace
	return char
end

local nextUserId = 100
function G.AddPlayer(name)
	nextUserId += 1
	local p = newInstance("Player", name)
	p._props.UserId = nextUserId
	p._props.DisplayName = name
	p._props.CharacterAdded = Signal.new()
	p._props.GetJoinData = function()
		return { TeleportData = { Mode = "Normal" } }
	end
	local function spawnChar()
		if p._props.Character then
			p._props.Character:Destroy()
		end
		local lobbySpawn = Vector3.new(math.random(-10, 10), 3, math.random(-10, 10))
		local c = makeCharacter(p, lobbySpawn)
		p._props.Character = c
		p._props.CharacterAdded:Fire(c)
	end
	p._props.LoadCharacter = function()
		spawnChar()
	end
	p._props.LoadCharacterAsync = function()
		spawnChar()
	end
	p.Parent = Players
	Players._props.PlayerAdded:Fire(p)
	task.delay(0.5, spawnChar)
	return p
end

function G.RemovePlayer(p)
	Players._props.PlayerRemoving:Fire(p)
	p.Parent = nil
end

-- Remotes: record everything fired to clients
G.FIRED = {}
local function makeRemote(name, cls)
	local r = newInstance(cls, name)
	r._props.OnServerEvent = Signal.new()
	r._props.OnClientEvent = Signal.new()
	r._props.FireClient = function(_, player, payload, ...)
		table.insert(G.FIRED, { remote = name, to = player._props.Name, payload = payload, t = clock })
	end
	r._props.FireAllClients = function(_, payload, ...)
		table.insert(G.FIRED, { remote = name, to = "*", payload = payload, t = clock })
	end
	return r
end

-- Build the tree from SOURCES ------------------------------------------------------------
local RS = service("ReplicatedStorage")
local SSS = service("ServerScriptService")
local SS = service("ServerStorage")

local remotes = newInstance("Folder", "Remotes")
for _, n in REMOTE_EVENTS do
	makeRemote(n, "RemoteEvent").Parent = remotes
end
for _, n in REMOTE_FUNCTIONS do
	makeRemote(n, "RemoteFunction").Parent = remotes
end
remotes.Parent = RS

local function folderAt(root, path)
	local cur = root
	for part in path:gmatch("[^/]+") do
		local nxt = cur:FindFirstChild(part)
		if not nxt then
			nxt = newInstance("Folder", part)
			nxt.Parent = cur
		end
		cur = nxt
	end
	return cur
end

local moduleCache = {}
local realRequire = require
for path, src in SOURCES do
	local root, rest = path:match("^(%w+)/(.*)$")
	local base = if root == "ServerScriptService" then SSS elseif root == "ReplicatedStorage" then RS else nil
	if base then
		local dir, file = rest:match("^(.*)/([^/]+)$")
		if not dir then
			dir, file = "", rest
		end
		local parent = if dir == "" then base else folderAt(base, dir)
		local name, kind = file:match("^(.-)%.(server)%.lua$")
		if not name then
			name = file:match("^(.-)%.lua$")
			kind = "module"
		end
		local inst = newInstance(if kind == "server" then "Script" else "ModuleScript", name)
		rawset(inst, "_source", src)
		rawset(inst, "_path", path)
		inst.Parent = parent
	end
end

local function runChunk(inst)
	local fn, err = loadstring(rawget(inst, "_source"), "=" .. rawget(inst, "_path"))
	if not fn then
		error(err)
	end
	local env = setmetatable({ script = inst }, { __index = ENV })
	setfenv(fn, env)
	return fn()
end

require = function(target)
	if type(target) == "table" and rawget(target, "__instance") then
		if moduleCache[target] == nil then
			moduleCache[target] = runChunk(target)
		end
		return moduleCache[target]
	end
	return realRequire(target)
end

-- Maps: ServerStorage.Maps.MapX with Spawns folder
local maps = newInstance("Folder", "Maps")
for i = 1, 3 do
	local m = newInstance("Model", "Map" .. i)
	m._attrs.DisplayName = "Test Map " .. i
	local sp = newInstance("Folder", "Spawns")
	for j = 1, 8 do
		local a = j / 8 * math.pi * 2
		local p = newInstance("Part", "Spawn")
		p._props.CFrame = CFrame.new(1000 + math.cos(a) * 40, 0.5, math.sin(a) * 40)
		p.Parent = sp
	end
	local cp = newInstance("Part", "ChaserSpawn")
	cp._props.CFrame = CFrame.new(1000, 0.5, 0)
	cp.Parent = sp
	sp.Parent = m
	m.Parent = maps
end
maps.Parent = SS

G.SIM = {
	runUntil = runUntil,
	now = function()
		return clock
	end,
	log = log,
	LOG = LOG,
	Players = Players,
	RS = RS,
	SSS = SSS,
	runChunk = runChunk,
	service = service,
}
