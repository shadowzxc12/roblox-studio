--[[
	MapUI: the store directory map [M].
	Shows the departments you have explored (the Store Directory item reveals everything),
	walls and doorways, sealed areas, you, your teammates and live events (supply drops,
	rare loot, camera sightings of the Locust). Main floor and B1 are separate pages.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Zones = require(Shared.Zones)
local Net = require(Shared.Net)

local UI = require(script.Parent.UI)
local ClientState = require(script.Parent.ClientState)
local Audio = require(script.Parent.Audio)

local MapUI = {}

local player = Players.LocalPlayer
local C = UI.C
local make = UI.make

local gui, root, frame, canvas, legend
local level = 0
local built = {}
local cellFrames = {}
local labels = {}
local markers = {}
local pings = {}
local px = 30
local plan

local function toMap(x: number, z: number): (number, number)
	return (x - plan.OriginX) / plan.CellSize * px, (z - plan.OriginZ) / plan.CellSize * px
end

local function build(lv: number)
	canvas:ClearAllChildren()
	table.clear(cellFrames)
	table.clear(labels)
	local S = plan.CellSize
	px = math.floor(math.min(980 / plan.Cols, 540 / plan.Rows))
	canvas.Size = UDim2.fromOffset(plan.Cols * px, plan.Rows * px)
	for _, cell in plan.CellList do
		if cell.Level == lv and not cell.Solid then
			local zinfo = Zones.Types[cell.Type]
			local f = make("Frame", {
				BackgroundColor3 = Color3.fromHex(zinfo.Floor):Lerp(Color3.new(0, 0, 0), 0.55),
				BorderSizePixel = 0,
				Position = UDim2.fromOffset((cell.Col - 1) * px, (cell.Row - 1) * px),
				Size = UDim2.fromOffset(px, px),
			}, canvas)
			cellFrames[cell.Id] = { Frame = f, Cell = cell, Color = f.BackgroundColor3 }
		end
	end
	-- walls
	for _, e in plan.Edges do
		if e.Level == lv and e.Wall then
			local x, z = toMap(e.X, e.Z)
			local vertical = e.Dir == "EW"
			local function seg(offset, len, color)
				make("Frame", {
					BackgroundColor3 = color or C.Text,
					BackgroundTransparency = 0.25,
					BorderSizePixel = 0,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = if vertical then UDim2.fromOffset(x, z + offset) else UDim2.fromOffset(x + offset, z),
					Size = if vertical then UDim2.fromOffset(2, len) else UDim2.fromOffset(len, 2),
					ZIndex = 3,
				}, canvas)
			end
			if e.Opening then
				local gap = 16 / S * px
				local part = (px - gap) / 2
				seg(-(gap / 2 + part / 2), part)
				seg(gap / 2 + part / 2, part)
				if e.Gate and not ReplicatedStorage:GetAttribute("Gate_" .. e.Gate) then
					seg(0, gap, C.Danger)
				end
			else
				seg(0, px)
			end
		end
	end
	-- zone labels
	for _, z in plan.Zones do
		if z.Level == lv and z.Center and z.Type ~= "Solid" then
			local cl = plan.Cells[z.Center]
			local x, y = toMap(cl.X, cl.Z)
			local l = UI.text(canvas, z.Name, 9, C.Text, UI.Caps, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(px * 3, 14), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5, TextStrokeTransparency = 0.3 })
			labels[z.Id] = { Label = l, Zone = z }
		end
	end
	built[lv] = true
end

local function refreshFog()
	local all = player:GetAttribute("HasMap") == true
	for id, rec in cellFrames do
		local known = all or ClientState.Discovered[id]
		rec.Frame.BackgroundColor3 = if known then rec.Color else Color3.fromHex("0c0d10")
	end
	for _, l in labels do
		local known = all
		if not known then
			for _, id in l.Zone.Cells do
				if ClientState.Discovered[id] then
					known = true
					break
				end
			end
		end
		l.Label.Visible = known
	end
end

local function marker(color: Color3, size: number, arrow: boolean?)
	local m = make("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(size, size), ZIndex = 8 }, canvas)
	UI.corner(m, if arrow then 2 else nil)
	UI.stroke(m, Color3.new(0, 0, 0), 1.5)
	if arrow then
		m.Rotation = 45
	end
	return m
end

local function updateMarkers()
	for _, m in markers do
		m:Destroy()
	end
	table.clear(markers)
	-- teammates
	for _, e in ClientState.Squad do
		if e.Pos and e.UserId ~= player.UserId and ((e.Pos.Y < -0.5) == (level == -1)) then
			local x, y = toMap(e.Pos.X, e.Pos.Z)
			local m = marker(if e.Downed then C.Danger elseif e.Infected then Color3.fromHex("7cff4f") else C.Info, 9)
			m.Position = UDim2.fromOffset(x, y)
			table.insert(markers, m)
			local n = UI.text(canvas, e.Name, 10, C.Text, UI.Bold, { Position = UDim2.fromOffset(x + 7, y - 7), Size = UDim2.fromOffset(100, 14), ZIndex = 8, TextStrokeTransparency = 0.3 })
			table.insert(markers, n)
		end
	end
	-- pings (events / camera sightings)
	local now = os.clock()
	for i = #pings, 1, -1 do
		local p = pings[i]
		if now > p.Until then
			table.remove(pings, i)
		elseif (p.Pos.Y < -0.5) == (level == -1) then
			local x, y = toMap(p.Pos.X, p.Pos.Z)
			local s = 12 + math.sin(now * 6) * 4
			local m = marker(p.Color, s)
			m.BackgroundTransparency = 0.2
			m.Position = UDim2.fromOffset(x, y)
			table.insert(markers, m)
			local n = UI.text(canvas, p.Text, 10, p.Color, UI.Caps, { Position = UDim2.fromOffset(x + 10, y - 6), Size = UDim2.fromOffset(160, 14), ZIndex = 8, TextStrokeTransparency = 0.2 })
			table.insert(markers, n)
		end
	end
	-- me
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	if r and ((r.Position.Y < -0.5) == (level == -1)) then
		local x, y = toMap(r.Position.X, r.Position.Z)
		local me = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(16, 16), ZIndex = 9 }, canvas)
		local look = Workspace.CurrentCamera.CFrame.LookVector
		me.Rotation = math.deg(math.atan2(look.X, -look.Z))
		local body = make("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.6), Size = UDim2.fromOffset(10, 10), Rotation = 45, ZIndex = 9 }, me)
		UI.stroke(body, Color3.new(0, 0, 0), 1.5)
		make("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(3, 8), ZIndex = 9 }, me)
		table.insert(markers, me)
	end
end

function MapUI.Ping(pos: Vector3, text: string, color: Color3, seconds: number)
	table.insert(pings, { Pos = pos, Text = text, Color = color, Until = os.clock() + seconds })
end

function MapUI.Toggle(on: boolean?)
	if on == nil then
		on = not frame.Visible
	end
	if on and (not plan or not ClientState.InRun()) then
		return
	end
	frame.Visible = on
	ClientState.SetBusy("Map", on)
	Audio.Play(if on then "Open" else "Close")
	if on then
		local char = player.Character
		local r = char and char:FindFirstChild("HumanoidRootPart")
		local wantLevel = if r and r.Position.Y < -0.5 then -1 else 0
		if wantLevel ~= level or not built[level] then
			level = wantLevel
			build(level)
		end
		refreshFog()
		updateMarkers()
	end
end

function MapUI.IsOpen(): boolean
	return frame.Visible
end

function MapUI.SetVisible(on: boolean)
	gui.Enabled = on
	if not on then
		frame.Visible = false
		ClientState.SetBusy("Map", false)
	end
end

function MapUI.Init()
	gui, root = UI.screen("MSL_Map", 6)
	frame = make("Frame", { Name = "Map", BackgroundColor3 = Color3.fromHex("050608"), BackgroundTransparency = 0.08, Size = UDim2.fromScale(1, 1), Visible = false }, root)
	UI.text(frame, "STORE DIRECTORY", 24, C.Accent, UI.Title, { Position = UDim2.fromOffset(40, 24), Size = UDim2.fromOffset(400, 28) })
	legend = UI.text(frame, "Explore to fill in the map · a Store Directory reveals everything · [M] close", 12, C.Muted, UI.Bold, { Position = UDim2.fromOffset(40, 54), Size = UDim2.fromOffset(700, 16) })
	local holder = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 26), Size = UDim2.fromOffset(1000, 560) }, frame)
	canvas = make("Frame", { BackgroundColor3 = Color3.fromHex("0a0b0e"), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(600, 450), ClipsDescendants = true }, holder)
	UI.stroke(canvas, C.Line, 1)
	local levels = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -40, 0, 24), Size = UDim2.fromOffset(240, 36) }, frame)
	UI.list(levels, 8, true, Enum.HorizontalAlignment.Right)
	for i, def in { { "MAIN FLOOR", 0 }, { "B1", -1 } } do
		local b = UI.button(levels, { Text = def[1], Size = UDim2.fromOffset(110, 34), TextSize = 13, LayoutOrder = i })
		b.Activated:Connect(function()
			level = def[2]
			build(level)
			refreshFog()
			updateMarkers()
		end)
	end
	local close = UI.button(frame, { Text = "✕", Size = UDim2.fromOffset(34, 34), Position = UDim2.new(1, -40, 1, -60), AnchorPoint = Vector2.new(1, 0) })
	close.Activated:Connect(function()
		MapUI.Toggle(false)
	end)

	if ClientState.Plan then
		plan = ClientState.Plan
	end
	ClientState.PlanReady:Connect(function(p)
		plan = p
		table.clear(built)
	end)
	Net.Event("Event").OnClientEvent:Connect(function(e)
		if e.Position then
			MapUI.Ping(e.Position, e.Name, C.Accent, math.max(20, e.Time or 20))
		end
	end)
	Net.Event("Cue").OnClientEvent:Connect(function(kind, pos)
		if kind == "CameraAlert" and pos then
			MapUI.Ping(pos, "LOCUST SPOTTED", C.Danger, 10)
		elseif kind == "OpenMap" then
			MapUI.Toggle(true)
		end
	end)
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		if frame.Visible then
			acc += dt
			if acc > 0.25 then
				acc = 0
				updateMarkers()
			end
		end
	end)
	ReplicatedStorage.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 5) == "Gate_" then
			table.clear(built)
		end
	end)
	gui.Enabled = false
end

return MapUI
