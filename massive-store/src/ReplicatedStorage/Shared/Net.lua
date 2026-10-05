--[[
	Net: every RemoteEvent / RemoteFunction in one place.
	The server creates them at startup (ReplicatedStorage.Remotes), clients wait for them.

	Rule of the game: the client only ASKS. The server validates everything (rate limits,
	distance, ownership, costs) and owns all important values (health, inventory, XP, credits).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Events = {
	-- server -> client
	"Notify", -- (text, kind)
	"Banner", -- ({ Title, Sub, Color, Time })
	"Data", -- (profile snapshot)
	"Inventory", -- (serialized inventory, selectedSlot)
	"Container", -- ({ Kind, Id, Name, Inv } | nil)
	"Cue", -- (kind, position, extra) sound / visual cues
	"Squad", -- ({ teammates })
	"Results", -- (run summary)
	"XP", -- (amount, reason)
	"Objective", -- (text)
	"Event", -- ({ Kind, Name, Desc, Position })
	"Unlocks", -- ({ unlock entries }) after a level up
	-- client -> server
	"Input", -- ({ Sprint = bool, Crouch = bool })
	"Flashlight", -- ()
	"Reload", -- ()
	"Hotbar", -- (slot)
	"UseItem", -- (slot, aimPosition?)
	"InvAction", -- ({ Action = ..., ... })
	"Build", -- ({ Action = ..., ... })
	"Cart", -- ({ Action = "Release" })
	"Emote", -- (cosmeticId)
	"Play", -- (modeId)
	"Menu", -- (action)
	"Settings", -- (key, value)
	"ClaimMission", -- (missionId)
	"NightVision", -- ()
	"LeaveHiding", -- ()
}

Net.Functions = {
	"GetData",
	"Shop", -- ({ Action = "Buy" | "Equip", Id })
	"GetServers",
	"JoinServer", -- (entry)
	"GetPlan", -- -> store seed and gate states
}

local folder: Folder

if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		for _, name in Net.Events do
			local r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = folder
		end
		for _, name in Net.Functions do
			local r = Instance.new("RemoteFunction")
			r.Name = name
			r.Parent = folder
		end
		folder.Parent = ReplicatedStorage
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Net.Event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

function Net.Function(name: string): RemoteFunction
	return folder:WaitForChild(name) :: RemoteFunction
end

return Net
