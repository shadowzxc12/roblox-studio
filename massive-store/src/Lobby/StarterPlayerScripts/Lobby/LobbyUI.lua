--[[
	LobbyUI: the lobby screens from the Figma file "MASSIVE STORE: LOCUST — UI".
	  01 Lobby — Main Menu     logo, PLAY SOLO / PLAY WITH PARTY / LOADOUT / SHOP / SETTINGS,
	                           profile chip, PARTY panel, invite toasts, daily missions strip
	  02 Lobby — Start a Run   SOLO | PARTY, SURVIVAL / INFECTION / HARDCORE cards, launch bar
	  pages                    LOCKER, SHOP (07), MISSIONS, SETTINGS, CREDITS (Client/Pages)
	  invite window            players in this lobby, Roblox friends, join by code
	The server decides everything (Lobby/Party); this only shows state and asks.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local Missions = require(Shared.Missions)
local Net = require(Shared.Net)
local PartyRules = require(Shared.PartyRules)
local Util = require(Shared.Util)

local Client = script.Parent.Parent:WaitForChild("Client")
local UI = require(Client.UI)
local ClientState = require(Client.ClientState)
local Pages = require(Client.Pages)
local Audio = require(Client.Audio)
local TeleportScreen = require(Client.TeleportScreen)

local LobbyCamera = require(script.Parent.LobbyCamera)

local LobbyUI = {}

local C = UI.C
local make = UI.make
local player = Players.LocalPlayer

local party = nil -- latest snapshot from the server
local who = "Solo" -- start-a-run toggle
local soloRules = "Survival" -- a party member going solo picks their own rules
local gui, root
local mainFrame, runFrame, pageFrame, pageContent, inviteFrame
local partyPanel, profileChip, missionStrip, partyButton
local toastHolder, inviteHolder

local function act(action: string, extra)
	local req = extra or {}
	req.Action = action
	Net.Event("PartyAction"):FireServer(req)
end

local function isLeader(): boolean
	return party ~= nil and party.Leader == player.UserId
end

local function partySize(): number
	return if party then #party.Members else 1
end

--============================ TOASTS ============================--
function LobbyUI.Toast(text: string, kind: string?)
	local color = C.Accent
	if kind == "Warn" then
		color = C.Danger
	elseif kind == "Good" then
		color = C.Good
	end
	local t = make("Frame", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.05, Size = UDim2.fromOffset(420, 40), BorderSizePixel = 0 }, toastHolder)
	UI.corner(t, 6)
	UI.stroke(t, color, 1, 0.5)
	make("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.new(0, 4, 1, 0), ZIndex = 3 }, t)
	UI.text(t, text, 13, C.Text, UI.Semi, { Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -24, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
	Audio.Play(if kind == "Warn" then "Warn" else "Notify")
	task.delay(3.5, function()
		UI.tween(t, 0.3, { BackgroundTransparency = 1 })
		task.wait(0.3)
		t:Destroy()
	end)
end

--============================ LOGO ============================--
local function logo(parent: Instance)
	local box = make("Frame", { Name = "Logo", BackgroundTransparency = 1, Position = UDim2.fromOffset(64, 52), Size = UDim2.fromOffset(460, 220) }, parent)
	UI.text(box, "OPEN 24/7  ·  NO EXIT", 12, C.Accent, UI.Mono, { Position = UDim2.fromOffset(2, 6), Size = UDim2.new(1, 0, 0, 16) })
	UI.text(box, "MASSIVE STORE", 76, C.Text, UI.Title, { Position = UDim2.fromOffset(-4, 20), Size = UDim2.new(1, 0, 0, 86) })
	local tag = make("Frame", { BackgroundColor3 = C.Danger, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 112), Size = UDim2.fromOffset(236, 52) }, box)
	UI.corner(tag, 4)
	UI.text(tag, "LOCUST", 40, C.Text, UI.Title, { Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -40, 1, 0) })
	local hole = make("Frame", { BackgroundColor3 = C.Bg, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -24, 0.5, 0), Size = UDim2.fromOffset(12, 12), ZIndex = 3 }, tag)
	UI.corner(hole)
	UI.text(box, "Survive the nights. Build in the aisles. Don't make a sound.", 13, C.Muted, UI.Body, { Position = UDim2.fromOffset(0, 178), Size = UDim2.fromOffset(400, 36), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	-- the sign flickers now and then
	task.spawn(function()
		while tag.Parent do
			task.wait(math.random(30, 80) / 10)
			for _ = 1, math.random(1, 3) do
				tag.BackgroundTransparency = 0.6
				task.wait(0.05)
				tag.BackgroundTransparency = 0
				task.wait(0.08)
			end
		end
	end)
	return box
end

--============================ PROFILE ============================--
local function renderProfile()
	profileChip:ClearAllChildren()
	UI.corner(profileChip, 8)
	UI.stroke(profileChip, Color3.new(1, 1, 1), 1, 0.92)
	local d = ClientState.Data
	local avatar = make("ImageLabel", { BackgroundColor3 = C.Panel2, Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(44, 44), Image = "", ZIndex = 3 }, profileChip)
	UI.corner(avatar)
	UI.stroke(avatar, C.Accent, 3, 0)
	task.spawn(function()
		local ok, img = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok and img and avatar.Parent then
			avatar.Image = img
		end
	end)
	local lv = make("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Position = UDim2.fromOffset(40, 40), Size = UDim2.fromOffset(24, 18), ZIndex = 4 }, profileChip)
	UI.corner(lv, 4)
	UI.text(lv, tostring(d and d.Level or 1), 11, C.Ink, UI.Mono, { TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
	UI.text(profileChip, player.DisplayName, 15, C.Text, UI.Bold, { Position = UDim2.fromOffset(72, 10), Size = UDim2.fromOffset(150, 20), TextTruncate = Enum.TextTruncate.AtEnd })
	local title = d and Cosmetics.Get(d.Equipped and d.Equipped.Title or "")
	UI.text(profileChip, ("%s · %d XP"):format(if title then string.upper(title.Name) else "SHOPPER", d and d.LevelXP or 0), 10, if title and title.Color then Color3.fromHex(title.Color) else C.Muted, UI.Mono, { Position = UDim2.fromOffset(72, 32), Size = UDim2.fromOffset(150, 14), TextTruncate = Enum.TextTruncate.AtEnd })
	UI.track(profileChip, C.Accent, (d and d.LevelXP or 0) / math.max(1, d and d.LevelXPNeeded or 100), { Position = UDim2.fromOffset(72, 50), Size = UDim2.fromOffset(150, 3) })
	local cr = make("Frame", { BackgroundColor3 = C.Panel2, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(78, 28), ZIndex = 3 }, profileChip)
	UI.corner(cr, 14)
	local coin = make("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(16, 16), ZIndex = 4 }, cr)
	UI.corner(coin)
	UI.text(cr, Util.Commas(d and d.Credits or 0), 12, C.Accent, UI.Mono, { Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -30, 1, 0), ZIndex = 4 })
	if d and d.Saving == false then
		UI.text(profileChip, "⚠ not saving", 9, C.Danger, UI.Mono, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 2), Size = UDim2.fromOffset(78, 10), TextXAlignment = Enum.TextXAlignment.Right })
	end
end

--============================ PARTY PANEL ============================--
local function memberRow(parent: Instance, m, y: number)
	local row = make("Frame", { Name = "Member", BackgroundColor3 = C.Panel2, BorderSizePixel = 0, Position = UDim2.fromOffset(16, y), Size = UDim2.new(1, -32, 0, 58) }, parent)
	UI.corner(row, 6)
	local av = make("ImageLabel", { BackgroundColor3 = if m.UserId == player.UserId then C.Accent else C.Info, Position = UDim2.fromOffset(10, 9), Size = UDim2.fromOffset(40, 40), ZIndex = 3 }, row)
	UI.corner(av)
	task.spawn(function()
		local ok, img = pcall(function()
			return Players:GetUserThumbnailAsync(m.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size60x60)
		end)
		if ok and img and av.Parent then
			av.Image = img
		end
	end)
	UI.text(row, m.Name, 14, C.Text, UI.Bold, { Position = UDim2.fromOffset(60, 10), Size = UDim2.fromOffset(110, 18), TextTruncate = Enum.TextTruncate.AtEnd })
	local title = Cosmetics.Get(m.Title or "")
	UI.text(row, ("LV %d · %s"):format(m.Level or 1, if m.UserId == player.UserId then "YOU" else string.upper(title and title.Name or "SHOPPER")), 10, C.Muted, UI.Mono, { Position = UDim2.fromOffset(60, 31), Size = UDim2.fromOffset(120, 14), TextTruncate = Enum.TextTruncate.AtEnd })
	if m.Leader then
		UI.tag(row, "LEADER", C.Accent, { Position = UDim2.new(1, -116, 0, 10), Size = UDim2.fromOffset(56, 18) })
	end
	UI.tag(row, if m.Ready then "READY" else "WAIT", if m.Ready then C.Good else C.Muted, { Position = UDim2.new(1, -56, 0, 20), Size = UDim2.fromOffset(48, 18) })
	if isLeader() and m.UserId ~= player.UserId then
		local kick = UI.button(row, { Text = "✕", Size = UDim2.fromOffset(22, 18), Position = UDim2.new(1, -116, 0, 32), TextSize = 11, Style = "Danger", Name = "Kick" })
		kick.Activated:Connect(function()
			act("Kick", { UserId = m.UserId })
		end)
	end
	return row
end

local openInvite -- forward

local function renderParty()
	partyPanel:ClearAllChildren()
	UI.corner(partyPanel, 8)
	UI.stroke(partyPanel, Color3.new(1, 1, 1), 1, 0.92)
	UI.text(partyPanel, "PARTY", 22, C.Text, UI.Title, { Position = UDim2.fromOffset(20, 12), Size = UDim2.fromOffset(80, 28) })
	UI.text(partyPanel, ("%d / %d"):format(partySize(), Config.Party.MaxSize), 13, C.Accent, UI.Mono, { Position = UDim2.fromOffset(96, 16), Size = UDim2.fromOffset(60, 20) })
	local code = make("Frame", { BackgroundColor3 = C.Panel2, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14), Size = UDim2.fromOffset(100, 26) }, partyPanel)
	UI.corner(code, 4)
	UI.text(code, "# " .. (party and party.Code or "------"), 11, C.Muted, UI.Mono, { TextXAlignment = Enum.TextXAlignment.Center })
	make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.92, BorderSizePixel = 0, Position = UDim2.fromOffset(20, 52), Size = UDim2.new(1, -40, 0, 1) }, partyPanel)
	local y = 66
	local members = party and party.Members or {}
	for _, m in members do
		memberRow(partyPanel, m, y)
		y += 66
	end
	for _ = #members + 1, Config.Party.MaxSize do
		local slot = make("TextButton", { Name = "EmptySlot", AutoButtonColor = false, Text = "+  INVITE A FRIEND", FontFace = UI.Mono, TextSize = 12, TextColor3 = C.Muted, BackgroundTransparency = 1, Position = UDim2.fromOffset(16, y), Size = UDim2.new(1, -32, 0, 58) }, partyPanel)
		UI.corner(slot, 6)
		UI.stroke(slot, Color3.new(1, 1, 1), 1, 0.8)
		slot.Activated:Connect(function()
			openInvite()
		end)
		y += 66
	end
	local inv = UI.button(partyPanel, { Text = "INVITE FRIENDS", Style = "Primary", Position = UDim2.fromOffset(16, y + 6), Size = UDim2.new(1, -132, 0, 52), TextSize = 18 })
	inv.Activated:Connect(function()
		openInvite()
	end)
	local solo = partySize() <= 1
	local second = UI.button(partyPanel, { Text = if solo then "CODE" else "LEAVE", Style = if solo then "Dark" else "Danger", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, y + 6), Size = UDim2.fromOffset(92, 52), TextSize = 18 })
	second.Activated:Connect(function()
		if solo then
			openInvite()
		else
			act("Leave")
		end
	end)
	partyPanel.Size = UDim2.fromOffset(316, y + 74)
	-- the main menu's party button shows readiness
	if partyButton then
		local ready = 0
		for _, m in members do
			if m.Ready then
				ready += 1
			end
		end
		local info = Config.Modes[party and party.Rules or "Survival"]
		local sub = partyButton:FindFirstChild("Sub")
		if sub then
			sub.Text = ("%d / %d ready · %s"):format(ready, math.max(1, #members), info and string.lower(info.Name) or "survival")
		end
	end
end

--============================ INVITE TOASTS ============================--
local function inviteToast(inv)
	local t = make("Frame", { Name = "Invite", BackgroundColor3 = C.Panel, BackgroundTransparency = 0.03, BorderSizePixel = 0, Size = UDim2.fromOffset(316, 80) }, inviteHolder)
	UI.corner(t, 8)
	UI.stroke(t, C.Accent, 1, 0.4)
	make("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Size = UDim2.new(0, 4, 1, 0), ZIndex = 3 }, t)
	UI.text(t, "PARTY INVITE", 10, C.Accent, UI.Mono, { Position = UDim2.fromOffset(18, 10), Size = UDim2.fromOffset(200, 14) })
	UI.text(t, ("%s wants you in their party (%d)"):format(inv.From, inv.Size or 1), 12, C.Text, UI.Semi, { Position = UDim2.fromOffset(18, 28), Size = UDim2.fromOffset(200, 32), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	local _, fill = UI.track(t, C.Accent, 1, { Position = UDim2.new(0, 18, 1, -10), Size = UDim2.new(1, -36, 0, 2) })
	UI.tween(fill, inv.Timeout or 30, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Linear)
	local yes = UI.button(t, { Text = "JOIN", Style = "Primary", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.fromOffset(72, 26), TextSize = 13 })
	local no = UI.button(t, { Text = "NO", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 40), Size = UDim2.fromOffset(72, 24), TextSize = 13 })
	yes.Activated:Connect(function()
		act("Accept", { PartyId = inv.PartyId })
		t:Destroy()
	end)
	no.Activated:Connect(function()
		act("Decline", { PartyId = inv.PartyId })
		t:Destroy()
	end)
	Audio.Play("Notify")
	task.delay(inv.Timeout or 30, function()
		if t.Parent then
			t:Destroy()
		end
	end)
end

--============================ INVITE WINDOW ============================--
local function renderInvite()
	inviteFrame:ClearAllChildren()
	UI.corner(inviteFrame, 10)
	UI.stroke(inviteFrame, Color3.new(1, 1, 1), 1, 0.9)
	UI.text(inviteFrame, "INVITE", 30, C.Text, UI.Title, { Position = UDim2.fromOffset(24, 16), Size = UDim2.fromOffset(200, 36) })
	UI.text(inviteFrame, ("YOUR PARTY CODE  # %s"):format(party and party.Code or "------"), 11, C.Accent, UI.Mono, { Position = UDim2.fromOffset(24, 54), Size = UDim2.fromOffset(300, 14) })
	local close = UI.button(inviteFrame, { Text = "✕", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16), Size = UDim2.fromOffset(36, 36), TextSize = 16 })
	close.Activated:Connect(function()
		inviteFrame.Visible = false
		ClientState.SetBusy("Invite", false)
	end)
	-- Roblox friends
	local friends = UI.button(inviteFrame, { Text = "INVITE ROBLOX FRIENDS", Sub = "They join this lobby straight into your party", Style = "Primary", Position = UDim2.fromOffset(24, 80), Size = UDim2.new(1, -48, 0, 64), TextSize = 22 })
	friends.Activated:Connect(function()
		local ok, can = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if not ok or not can then
			LobbyUI.Toast("Invites aren't available here (Studio or privacy settings).", "Warn")
			return
		end
		local options = Instance.new("ExperienceInviteOptions")
		options.PromptMessage = "Join my party in MASSIVE STORE: LOCUST!"
		options.LaunchData = party and party.Code or ""
		pcall(function()
			SocialService:PromptGameInvite(player, options)
		end)
	end)
	-- join by code
	UI.text(inviteFrame, "JOIN A PARTY BY CODE", 10, C.Muted, UI.Mono, { Position = UDim2.fromOffset(24, 160), Size = UDim2.fromOffset(300, 14) })
	local box = make("TextBox", { Name = "CodeBox", BackgroundColor3 = C.Panel2, BorderSizePixel = 0, Position = UDim2.fromOffset(24, 180), Size = UDim2.new(1, -164, 0, 44), FontFace = UI.Mono, TextSize = 18, TextColor3 = C.Text, PlaceholderText = "K7Q-2M4", PlaceholderColor3 = C.Dim, Text = "", ClearTextOnFocus = false }, inviteFrame)
	UI.corner(box, 6)
	UI.stroke(box, Color3.new(1, 1, 1), 1, 0.9)
	local joinB = UI.button(inviteFrame, { Text = "JOIN", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 180), Size = UDim2.fromOffset(104, 44), TextSize = 18 })
	joinB.Activated:Connect(function()
		act("JoinCode", { Code = box.Text })
	end)
	-- players in this lobby
	UI.text(inviteFrame, "IN THIS LOBBY", 10, C.Muted, UI.Mono, { Position = UDim2.fromOffset(24, 240), Size = UDim2.fromOffset(300, 14) })
	local list = make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(24, 260), Size = UDim2.new(1, -48, 1, -280), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4 }, inviteFrame)
	UI.list(list, 6)
	local n = 0
	for _, p in Players:GetPlayers() do
		if p ~= player and p:GetAttribute("PartyId") ~= (party and party.Id) then
			n += 1
			local row = make("Frame", { BackgroundColor3 = C.Panel2, BorderSizePixel = 0, Size = UDim2.new(1, -8, 0, 46), LayoutOrder = n }, list)
			UI.corner(row, 6)
			UI.text(row, p.DisplayName, 14, C.Text, UI.Bold, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -150, 1, 0) })
			UI.text(row, ("PARTY OF %d"):format(p:GetAttribute("PartySize") or 1), 9, C.Muted, UI.Mono, { Position = UDim2.new(1, -230, 0, 0), Size = UDim2.fromOffset(90, 46) })
			local b = UI.button(row, { Text = "INVITE", Style = "Primary", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(100, 32), TextSize = 14 })
			b.Activated:Connect(function()
				act("Invite", { UserId = p.UserId })
				b.Text = "SENT"
			end)
		end
	end
	if n == 0 then
		UI.text(list, "Nobody else is in this lobby yet — invite Roblox friends above.", 12, C.Muted, UI.Body, { Size = UDim2.new(1, 0, 0, 30), TextWrapped = true })
	end
end

openInvite = function()
	renderInvite()
	inviteFrame.Visible = true
	ClientState.SetBusy("Invite", true)
end

--============================ START A RUN (Figma 02) ============================--
local function dots(n: number): string
	return string.rep("●", n) .. string.rep("○", 5 - n)
end

local function modeStats(id: string)
	local m = Config.Modes[id]
	local locust = math.clamp(math.floor((m.LocustMult - 0.55) * 6.5 + 0.5), 1, 5)
	local loot = if m.LootMult < 0.8 then "Scarce" elseif m.LootMult > 1.1 then "Plenty" else "Normal"
	local death = if m.ReviveNeedsMedkit then "Medkit revive" else "Revive"
	return { { "LOCUST", dots(locust) }, { "LOOT", loot }, { "DEATH", death } }
end

local renderRun -- forward

local function ownRules(): boolean
	return who == "Solo" and not isLeader() and partySize() > 1
end

local function currentRules(): string
	if ownRules() then
		return soloRules
	end
	return party and party.Rules or "Survival"
end


local function launchSummary(): (string?, string?)
	local solo = who == "Solo"
	local size = if solo then 1 else partySize()
	return PartyRules.Resolve(currentRules(), solo, size)
end

renderRun = function()
	runFrame:ClearAllChildren()
	local rules = currentRules()
	local leader = isLeader()
	local canPick = who == "Solo" or leader
	-- header
	local back = UI.button(runFrame, { Text = "←  BACK", Font = UI.Mono, Position = UDim2.fromOffset(48, 36), Size = UDim2.fromOffset(100, 36), TextSize = 13 })
	back.Activated:Connect(function()
		LobbyUI.Open("Main")
	end)
	UI.text(runFrame, "START A RUN", 40, C.Text, UI.Title, { Position = UDim2.fromOffset(168, 26), Size = UDim2.fromOffset(500, 48) })
	UI.text(runFrame, "PICK WHO COMES WITH YOU, THEN THE RULES OF THE STORE", 11, C.Muted, UI.Mono, { Position = UDim2.fromOffset(170, 76), Size = UDim2.fromOffset(600, 14) })
	-- SOLO | PARTY
	local seg = make("Frame", { BackgroundColor3 = C.Panel, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -48, 0, 32), Size = UDim2.fromOffset(352, 54) }, runFrame)
	UI.corner(seg, 8)
	UI.stroke(seg, Color3.new(1, 1, 1), 1, 0.92)
	for i, opt in { { "Solo", "SOLO", "private server · just you" }, { "Party", "PARTY", ("%d / %d members"):format(partySize(), Config.Party.MaxSize) } } do
		local sel = who == opt[1]
		local b = UI.button(seg, { Text = opt[2], Sub = opt[3], Style = if sel then "Primary" else "Ghost", Position = UDim2.fromOffset(4 + (i - 1) * 174, 4), Size = UDim2.fromOffset(170, 46), TextSize = 18 })
		if not sel then
			b.BackgroundTransparency = 1
		end
		b.Activated:Connect(function()
			who = opt[1]
			if who == "Party" and partySize() <= 1 then
				LobbyUI.Toast("You're alone — invite friends to play as a party.", "Info")
			end
			renderRun()
		end)
	end
	-- mode cards
	local cards = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120), Size = UDim2.fromOffset(1184, 420) }, runFrame)
	for i, id in Config.Party.LobbyModes do
		local m = Config.Modes[id]
		local col = Color3.fromHex(m.Color)
		local sel = rules == id
		local okMode, why = PartyRules.Resolve(id, who == "Solo", if who == "Solo" then 1 else partySize())
		local cardB = make("TextButton", { Name = "Mode_" .. id, AutoButtonColor = false, Text = "", BackgroundColor3 = C.Panel, BorderSizePixel = 0, Position = UDim2.fromOffset((i - 1) * 400, 0), Size = UDim2.fromOffset(384, 420), ClipsDescendants = true }, cards)
		UI.corner(cardB, 10)
		UI.stroke(cardB, if sel then col else Color3.new(1, 1, 1), if sel then 2 else 1, if sel then 0 else 0.92)
		local art = make("Frame", { BackgroundColor3 = col, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 190) }, cardB)
		make("UIGradient", { Transparency = NumberSequence.new(0.62, 1), Rotation = 90 }, art)
		for k = 0, 5 do
			make("Frame", { BackgroundColor3 = Color3.fromHex("050607"), BackgroundTransparency = 0.25, BorderSizePixel = 0, Position = UDim2.fromOffset(24 + k * 58, 60 + (k % 2) * 14), Size = UDim2.fromOffset(40, 130 - (k % 2) * 14) }, art)
		end
		UI.text(art, ("0%d"):format(i), 12, col, UI.Mono, { Position = UDim2.fromOffset(24, 16), Size = UDim2.fromOffset(40, 16) })
		if sel then
			UI.tag(art, "SELECTED", col, { Position = UDim2.new(1, -110, 0, 16), Size = UDim2.fromOffset(92, 24), BackgroundTransparency = 0 }):FindFirstChildOfClass("TextLabel").TextColor3 = C.Ink
		end
		UI.text(cardB, m.Name, 34, C.Text, UI.Title, { Position = UDim2.fromOffset(24, 202), Size = UDim2.new(1, -48, 0, 40) })
		UI.text(cardB, m.Desc, 12, C.Muted, UI.Body, { Position = UDim2.fromOffset(24, 250), Size = UDim2.new(1, -48, 0, 54), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
		make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.92, BorderSizePixel = 0, Position = UDim2.fromOffset(24, 318), Size = UDim2.new(1, -48, 0, 1) }, cardB)
		for j, st in modeStats(id) do
			UI.text(cardB, st[1], 9, C.Muted, UI.Mono, { Position = UDim2.fromOffset(24 + (j - 1) * 116, 334), Size = UDim2.fromOffset(110, 12) })
			UI.text(cardB, st[2], 15, if j == 1 then col else C.Text, if j == 1 then UI.Mono else UI.Heading, { Position = UDim2.fromOffset(24 + (j - 1) * 116, 350), Size = UDim2.fromOffset(110, 22) })
		end
		if not okMode then
			local veil = make("Frame", { BackgroundColor3 = C.Bg, BackgroundTransparency = 0.35, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 6 }, cardB)
			UI.text(veil, string.upper(why or "UNAVAILABLE"), 12, C.Danger, UI.Mono, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.new(1, -40, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 })
		elseif not canPick then
			UI.text(cardB, "THE LEADER PICKS", 10, C.Muted, UI.Mono, { Position = UDim2.fromOffset(24, 390), Size = UDim2.fromOffset(200, 14) })
		end
		cardB.Activated:Connect(function()
			if not canPick then
				LobbyUI.Toast("Only the party leader picks the mode.", "Info")
				return
			end
			if ownRules() then
				soloRules = id
				renderRun()
				return
			end
			act("SetMode", { Mode = id })
		end)
	end
	-- launch bar
	local bar = make("Frame", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.04, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 564), Size = UDim2.fromOffset(1184, 104) }, runFrame)
	UI.corner(bar, 10)
	UI.stroke(bar, Color3.new(1, 1, 1), 1, 0.92)
	local mode, why = launchSummary()
	local info = Config.Modes[mode or rules]
	UI.text(bar, if mode then "READY TO TELEPORT" else "CAN'T START YET", 11, if mode then C.Accent else C.Danger, UI.Mono, { Position = UDim2.fromOffset(28, 18), Size = UDim2.fromOffset(400, 14) })
	UI.text(bar, ("%s  ·  %s"):format(if who == "Solo" then "Solo" else ("Party of " .. partySize()), info and (string.sub(info.Name, 1, 1) .. string.lower(string.sub(info.Name, 2))) or rules), 22, C.Text, UI.Heading, { Position = UDim2.fromOffset(28, 36), Size = UDim2.fromOffset(560, 28) })
	UI.text(bar, why or (if who == "Solo" then "A private store server is reserved just for you. You come back here when the run ends." else "Your whole party lands in the same private store. You come back together."), 11, C.Muted, UI.Body, { Position = UDim2.fromOffset(28, 70), Size = UDim2.fromOffset(600, 16) })
	-- readiness chips (party)
	if who == "Party" and party then
		for i, m in party.Members do
			local chip = make("Frame", { BackgroundColor3 = C.Panel2, BorderSizePixel = 0, Position = UDim2.fromOffset(640 + (i - 1) * 50, 30), Size = UDim2.fromOffset(42, 42) }, bar)
			UI.corner(chip)
			UI.stroke(chip, if m.Ready then C.Good else C.Muted, 2, 0)
			UI.text(chip, string.upper(string.sub(m.Name, 1, 1)), 18, C.Text, UI.Title, { TextXAlignment = Enum.TextXAlignment.Center })
		end
	end
	local goText, goSub, goStyle = "ENTER THE STORE", "teleport  →", "Primary"
	local me = nil
	if party then
		for _, m in party.Members do
			if m.UserId == player.UserId then
				me = m
			end
		end
	end
	if who == "Party" and not leader then
		goText = if me and me.Ready then "READY ✓" else "READY UP"
		goSub = if me and me.Ready then "waiting for the leader" else "tell the leader you're set"
		goStyle = if me and me.Ready then "Good" else "Primary"
	elseif who == "Party" then
		local waiting = 0
		for _, m in party and party.Members or {} do
			if not m.Ready then
				waiting += 1
			end
		end
		if waiting > 0 then
			goText, goSub, goStyle = "WAITING", ("%d not ready"):format(waiting), "Dark"
		end
	end
	if party and party.Launching then
		goText, goSub, goStyle = "TELEPORTING...", "hold on", "Dark"
	end
	local go = UI.button(bar, { Name = "Launch", Text = goText, Sub = goSub, Style = goStyle, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -24, 0.5, 0), Size = UDim2.fromOffset(300, 64), TextSize = 26 })
	go.Activated:Connect(function()
		if who == "Party" and not leader then
			act("Ready", { Value = not (me and me.Ready) })
			return
		end
		if not mode then
			LobbyUI.Toast(why or "Can't start", "Warn")
			return
		end
		act("Launch", { Solo = who == "Solo", Rules = rules })
	end)
end

--============================ MAIN (Figma 01) ============================--
local function renderMissions()
	missionStrip:ClearAllChildren()
	UI.corner(missionStrip, 6)
	UI.stroke(missionStrip, Color3.new(1, 1, 1), 1, 0.94)
	UI.text(missionStrip, "DAILY", 11, C.Accent, UI.Mono, { Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(60, 40) })
	local d = ClientState.Data
	local day = Util.DayNumber(os.time())
	for i, id in Missions.ForDay(day) do
		if i > 3 then
			break
		end
		local m = Missions.ById[id]
		local prog = if d and d.Missions and d.Missions.Day == day then d.Missions.Progress[id] or 0 else 0
		local x = 80 + (i - 1) * 256
		UI.text(missionStrip, m.Text, 11, C.Text, UI.Semi, { Position = UDim2.fromOffset(x, 4), Size = UDim2.fromOffset(230, 16), TextTruncate = Enum.TextTruncate.AtEnd })
		UI.track(missionStrip, C.Accent, prog / m.Goal, { Position = UDim2.fromOffset(x, 26), Size = UDim2.fromOffset(220, 4) })
	end
	local open = make("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), ZIndex = 9 }, missionStrip)
	open.Activated:Connect(function()
		LobbyUI.Open("Page", "MISSIONS")
	end)
end

local function buildMain()
	mainFrame = make("Frame", { Name = "Main", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, root)
	-- readable left side over the 3D scene
	local fade = make("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Size = UDim2.new(0, 760, 1, 0) }, mainFrame)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.6, 0.35), NumberSequenceKeypoint.new(1, 1) }) }, fade)
	logo(mainFrame)
	local col = make("Frame", { Name = "Buttons", BackgroundTransparency = 1, Position = UDim2.fromOffset(64, 292), Size = UDim2.fromOffset(360, 340) }, mainFrame)
	UI.list(col, 10)
	local solo = UI.button(col, { Name = "PlaySolo", Text = "PLAY SOLO", Sub = "Your own store. Nobody hears you scream.", Key = "↵", Style = "Primary", Size = UDim2.fromOffset(360, 72), TextSize = 30, LayoutOrder = 1 })
	solo.Activated:Connect(function()
		who = "Solo"
		LobbyUI.Open("Run")
	end)
	partyButton = UI.button(col, { Name = "PlayParty", Text = "PLAY WITH PARTY", Sub = "1 / 1 ready · survival", Key = "P", Accent = true, Size = UDim2.fromOffset(360, 56), LayoutOrder = 2 })
	partyButton.Activated:Connect(function()
		who = "Party"
		LobbyUI.Open("Run")
		if partySize() <= 1 then
			openInvite()
		end
	end)
	for i, def in {
		{ "LOADOUT & OUTFITS", "Cosmetics, flashlight beam, cart paint", "L", "LOCKER" },
		{ "STORE CREDITS SHOP", "Outfits, titles, effects — cosmetic only", "B", "SHOP" },
		{ "SETTINGS", "Audio · effects · controls", "⚙", "SETTINGS" },
	} do
		local b = UI.button(col, { Name = def[4], Text = def[1], Sub = def[2], Key = def[3], Accent = true, Size = UDim2.fromOffset(360, 56), LayoutOrder = 2 + i })
		b.Activated:Connect(function()
			LobbyUI.Open("Page", def[4])
		end)
	end
	-- right column
	profileChip = make("Frame", { Name = "Profile", BackgroundColor3 = C.Panel, BackgroundTransparency = 0.1, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -44, 0, 40), Size = UDim2.fromOffset(316, 64) }, mainFrame)
	partyPanel = make("Frame", { Name = "Party", BackgroundColor3 = C.Panel, BackgroundTransparency = 0.08, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -44, 0, 120), Size = UDim2.fromOffset(316, 404) }, mainFrame)
	missionStrip = make("Frame", { Name = "Missions", BackgroundColor3 = C.Panel, BackgroundTransparency = 0.25, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 64, 1, -32), Size = UDim2.fromOffset(856, 40) }, mainFrame)
	local credits = make("TextButton", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -44, 1, -40), Size = UDim2.fromOffset(200, 16), Text = "v2.0  ·  LOBBY  ·  CREDITS", FontFace = UI.Mono, TextSize = 10, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Right }, mainFrame)
	credits.Activated:Connect(function()
		LobbyUI.Open("Page", "CREDITS")
	end)
	renderProfile()
	renderParty()
	renderMissions()
end

--============================ NAV ============================--
local screen = "Main"
function LobbyUI.Open(name: string, page: string?)
	screen = name
	mainFrame.Visible = name == "Main"
	runFrame.Visible = name == "Run"
	pageFrame.Visible = name == "Page"
	if name == "Run" then
		renderRun()
	elseif name == "Page" and page then
		Pages.Render(page, pageContent)
	else
		Pages.Close()
	end
	LobbyCamera.SetFocus(name)
	Audio.Play("Open")
end

local function buildPageHost()
	pageFrame = make("Frame", { Name = "Page", BackgroundColor3 = C.Bg, BackgroundTransparency = 0.25, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false }, root)
	local back = UI.button(pageFrame, { Text = "←  BACK", Font = UI.Mono, Position = UDim2.fromOffset(48, 36), Size = UDim2.fromOffset(100, 36), TextSize = 13 })
	back.Activated:Connect(function()
		LobbyUI.Open("Main")
	end)
	pageContent = make("Frame", { Name = "Content", BackgroundTransparency = 1, Position = UDim2.fromOffset(168, 28), Size = UDim2.new(1, -216, 1, -76) }, pageFrame)
end

function LobbyUI.Init()
	gui, root = UI.screen("MSL_Lobby", 2)
	Pages.Toast = LobbyUI.Toast
	buildMain()
	runFrame = make("Frame", { Name = "Run", BackgroundColor3 = C.Bg, BackgroundTransparency = 0.35, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false }, root)
	buildPageHost()
	inviteFrame = make("Frame", { Name = "InviteWindow", BackgroundColor3 = C.Panel, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(540, 520), Visible = false, ZIndex = 20 }, root)
	toastHolder = make("Frame", { Name = "Toasts", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 20), Size = UDim2.fromOffset(420, 200) }, root)
	UI.list(toastHolder, 6, false, Enum.HorizontalAlignment.Center)
	inviteHolder = make("Frame", { Name = "Invites", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -44, 1, -80), Size = UDim2.fromOffset(316, 300) }, root)
	local il = UI.list(inviteHolder, 8)
	il.VerticalAlignment = Enum.VerticalAlignment.Bottom

	Net.Event("Party").OnClientEvent:Connect(function(snap)
		party = snap
		renderParty()
		if screen == "Run" then
			renderRun()
		end
		if inviteFrame.Visible then
			renderInvite()
		end
	end)
	Net.Event("PartyInvite").OnClientEvent:Connect(inviteToast)
	Net.Event("Notify").OnClientEvent:Connect(LobbyUI.Toast)
	Net.Event("Teleporting").OnClientEvent:Connect(function(info)
		if info.Cancel then
			TeleportScreen.Hide()
			if info.Message then
				LobbyUI.Toast(info.Message, "Warn")
			end
		else
			TeleportScreen.Show(info)
		end
	end)
	ClientState.DataChanged:Connect(function()
		renderProfile()
		renderMissions()
		renderParty()
	end)
	Players.PlayerAdded:Connect(function()
		if inviteFrame.Visible then
			renderInvite()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local kc = input.KeyCode
		if kc == Enum.KeyCode.Escape or kc == Enum.KeyCode.ButtonB then
			if inviteFrame.Visible then
				inviteFrame.Visible = false
				ClientState.SetBusy("Invite", false)
			elseif screen ~= "Main" then
				LobbyUI.Open("Main")
			end
		elseif screen == "Main" then
			if kc == Enum.KeyCode.Return then
				who = "Solo"
				LobbyUI.Open("Run")
			elseif kc == Enum.KeyCode.P then
				who = "Party"
				LobbyUI.Open("Run")
			elseif kc == Enum.KeyCode.L then
				LobbyUI.Open("Page", "LOCKER")
			elseif kc == Enum.KeyCode.B then
				LobbyUI.Open("Page", "SHOP")
			end
		end
	end)
	LobbyUI.Open("Main")
end

return LobbyUI
