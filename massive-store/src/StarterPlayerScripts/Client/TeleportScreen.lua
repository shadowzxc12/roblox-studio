--[[
	TeleportScreen (Figma 03 "Teleport / Loading"): the admission receipt shown while you are
	teleported between the lobby and a store. It is also handed to TeleportService as the
	teleport GUI, so it stays on screen through the teleport itself.
	Show({ Mode, Solo, Members, Lobby }) / Hide(message?)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local UI = require(script.Parent.UI)

local TeleportScreen = {}

local C = UI.C
local make = UI.make
local player = Players.LocalPlayer

local gui: ScreenGui? = nil
local rows = {}
local token = 0

local TIPS = {
	"Running is loud. The Locust hears footsteps three aisles away.",
	"Your flashlight is a beacon. Turn it off when it hunts.",
	"A metal door buys more time than a plank wall.",
	"Downed teammates can be revived. Don't leave them.",
	"Generators are loud. Something might hear them.",
	"Thank you for shopping at MASSIVE STORE.",
}

local function build(info)
	local g = make("ScreenGui", { Name = "MSL_Teleport", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 900, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	local bg = make("Frame", { Name = "Bg", BackgroundColor3 = Color3.fromHex("050607"), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, g)
	local glow = make("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.1), Size = UDim2.fromScale(0.8, 0.9) }, bg)
	UI.corner(glow)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.88), NumberSequenceKeypoint.new(1, 1) }), Rotation = 90 }, glow)
	local root = make("Frame", { Name = "Root", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1280, 720) }, bg)
	make("UIAspectRatioConstraint", { AspectRatio = 16 / 9 }, root)
	make("UISizeConstraint", { MaxSize = Vector2.new(1280, 720) }, root)

	local modeInfo = Config.Modes[info.Mode or ""]
	local kicker = if info.Lobby then "NOW LEAVING" else "NOW ENTERING"
	local title = if info.Lobby then "BACK TO THE LOBBY" else "MASSIVE STORE"
	local sub = if info.Lobby then "THE PARKING LOT · YOUR PARTY" else ("%s  ·  %s  ·  NIGHT 1"):format(modeInfo and modeInfo.Name or "SURVIVAL", if info.Solo or (info.Members or 1) <= 1 then "SOLO" else ("PARTY OF " .. info.Members))
	UI.text(root, kicker, 12, C.Accent, UI.Mono, { Position = UDim2.fromScale(0, 0.12), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center })
	UI.text(root, title, 56, C.Text, UI.Title, { Position = UDim2.new(0, 0, 0.12, 20), Size = UDim2.new(1, 0, 0, 64), TextXAlignment = Enum.TextXAlignment.Center })
	UI.text(root, sub, 14, C.Muted, UI.Mono, { Position = UDim2.new(0, 0, 0.12, 92), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center })

	-- the receipt
	local rc = make("Frame", { Name = "Receipt", BackgroundColor3 = C.Paper, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.12, 132), Size = UDim2.fromOffset(340, 300) }, root)
	UI.corner(rc, 2)
	local ink = Color3.fromHex("1d1b17")
	UI.text(rc, "MASSIVE STORE", 20, ink, UI.Title, { Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center })
	UI.text(rc, if info.Lobby then "*** CUSTOMER EXIT RECEIPT ***" else "*** ADMISSION RECEIPT ***", 10, ink, UI.Mono, { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 12), TextXAlignment = Enum.TextXAlignment.Center })
	local dash = string.rep("- ", 20)
	UI.text(rc, dash, 10, ink, UI.Mono, { Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 0, 12), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 0.5 })
	local list = if info.Lobby
		then { "SAVE PROGRESS", "LOCK THE DOORS", "FIND THE CAR", "REGROUP PARTY", "BREATHE" }
		else { "RESERVE SERVER", ("PARTY  %d/%d"):format(info.Members or 1, info.Members or 1), "GENERATE AISLES", "STOCK SHELVES", "WAKE THE LOCUST" }
	table.clear(rows)
	for i, k in list do
		local y = 78 + (i - 1) * 22
		local l = UI.text(rc, k, 12, ink, UI.Mono, { Position = UDim2.fromOffset(24, y), Size = UDim2.fromOffset(200, 18), TextTransparency = 0.6 })
		local v = UI.text(rc, "...", 12, ink, UI.Mono, { Position = UDim2.new(1, -104, 0, y), Size = UDim2.fromOffset(80, 18), TextXAlignment = Enum.TextXAlignment.Right, TextTransparency = 0.6 })
		rows[i] = { L = l, V = v }
	end
	UI.text(rc, dash, 10, ink, UI.Mono, { Position = UDim2.fromOffset(0, 192), Size = UDim2.new(1, 0, 0, 12), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 0.5 })
	UI.text(rc, "TOTAL", 14, ink, UI.Mono, { Position = UDim2.fromOffset(24, 208), Size = UDim2.fromOffset(120, 18) })
	UI.text(rc, if info.Lobby then "PAID IN FULL" else "YOUR LIFE", 14, Color3.fromHex("b0151b"), UI.Mono, { Position = UDim2.new(1, -164, 0, 208), Size = UDim2.fromOffset(140, 18), TextXAlignment = Enum.TextXAlignment.Right })
	for i = 0, 45 do
		make("Frame", { BackgroundColor3 = ink, BorderSizePixel = 0, Position = UDim2.fromOffset(30 + i * 6.2, 240), Size = UDim2.fromOffset(({ 1, 2, 3, 1, 2 })[i % 5 + 1], 44) }, rc)
	end
	-- zig-zag tear at the bottom
	for i = 0, 16 do
		local tooth = make("Frame", { BackgroundColor3 = C.Paper, BorderSizePixel = 0, Rotation = 45, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 10 + i * 20, 1, 0), Size = UDim2.fromOffset(14, 14) }, rc)
		tooth.ZIndex = 1
	end

	local track = make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.9, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.12, 476), Size = UDim2.fromOffset(500, 4) }, root)
	UI.corner(track, 2)
	local fill = make("Frame", { Name = "Fill", BackgroundColor3 = C.Accent, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1) }, track)
	UI.corner(fill, 2)
	UI.text(root, "TIP  ·  " .. TIPS[math.random(1, #TIPS)], 12, C.Muted, UI.Body, { Position = UDim2.new(0, 0, 0.12, 498), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center })
	return g, fill
end

function TeleportScreen.Show(info)
	TeleportScreen.Hide()
	token += 1
	local my = token
	local g, fill = build(info or {})
	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
	pcall(function()
		TeleportService:SetTeleportGui(g)
	end)
	task.spawn(function()
		for i, r in rows do
			if token ~= my then
				return
			end
			task.wait(0.55 + math.random() * 0.4)
			if token ~= my then
				return
			end
			r.L.TextTransparency = 0
			r.V.TextTransparency = 0
			r.V.Text = "OK"
			r.V.TextColor3 = Color3.fromHex("1f7a35")
			UI.tween(fill, 0.4, { Size = UDim2.fromScale(math.min(0.95, i / (#rows + 0.4)), 1) })
		end
	end)
end

function TeleportScreen.Hide()
	token += 1
	if gui then
		gui:Destroy()
		gui = nil
	end
end

function TeleportScreen.IsShown(): boolean
	return gui ~= nil
end

return TeleportScreen
