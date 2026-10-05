--[[
	Defense: what base defences do to the Locust.
	  Snare Trap    stuns when stepped on (limited charges, no power)
	  Shock Plate   powered, stuns + big resolve damage, recharges
	  Sentry Turret powered, shoots the Locust (and Nymphs) in range with line of sight
	  Camera        powered, warns everyone when it spots the Locust
	The Locust can't be killed, but enough damage to its resolve makes it retreat.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local State = require(script.Parent.State)
local World = require(script.Parent.World)
local Building = require(script.Parent.Building)
local Locust = require(script.Parent.Locust)
local Noise = require(script.Parent.Noise)

local Defense = {}

local function los(from: Vector3, to: Vector3, ignore): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = { World.Folders.Loot, World.Folders.Dynamic, World.Folders.Lights, ignore }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	params.FilterDescendantsInstances = list
	return Workspace:Raycast(from, to - from, params) == nil
end

local function ownerOf(s): Player?
	return Players:GetPlayerByUserId(s.Owner)
end

local function step()
	local L = Locust.Get()
	local nymphs = Locust.Nymphs()
	if not L and #nymphs == 0 then
		return
	end
	local now = os.clock()
	local lpos = L and L.Root.Position
	for _, s in Building.All() do
		local def = s.Def
		if def.Kind == "Trap" and lpos and now >= (s.ReadyAt or 0) then
			local pos = s.Model:GetPivot().Position
			local d = Vector3.new(lpos.X - pos.X, 0, lpos.Z - pos.Z).Magnitude
			if d < def.Size[1] / 2 + 1.8 and math.abs(lpos.Y - pos.Y) < 9 then
				local powered = def.Power == nil or s.Powered
				if powered then
					s.ReadyAt = now + (def.Cooldown or 5)
					Locust.Stun(def.Stun, ownerOf(s))
					Locust.Hurt(def.ResolveDamage, ownerOf(s))
					State.Cue(if def.Power then "Shock" else "TrapSnap", pos, nil)
					Noise.Emit(pos, 1, nil, "Trap")
					if def.Charges then
						s.Charges = (s.Charges or def.Charges) - 1
						s.Model:SetAttribute("Charges", s.Charges)
						if s.Charges <= 0 then
							Building.Destroy(s)
						end
					end
				end
			end
		elseif def.Kind == "Turret" and s.Powered and now >= (s.ReadyAt or 0) then
			local head = s.Model:FindFirstChild("Head") :: BasePart?
			local from = if head then head.Position else s.Model:GetPivot().Position
			local target, targetPos = nil, nil
			if lpos and (lpos - from).Magnitude <= def.Range and los(from, lpos + Vector3.new(0, 2, 0), L.Model) then
				target, targetPos = "Locust", lpos + Vector3.new(0, 2, 0)
			else
				for _, n in nymphs do
					local np = n.Root.Position
					if (np - from).Magnitude <= def.Range and los(from, np, n.Model) then
						target, targetPos = n, np
						break
					end
				end
			end
			if target then
				s.ReadyAt = now + def.FireRate
				if head then
					head.CFrame = CFrame.lookAt(head.Position, Vector3.new(targetPos.X, head.Position.Y, targetPos.Z))
				end
				State.Cue("TurretFire", from, targetPos)
				Noise.Emit(from, Config.Noise.Turret, nil, "Turret")
				if target == "Locust" then
					Locust.Hurt(def.ResolveDamage, ownerOf(s))
				else
					target.Hits = (target.Hits or 0) + 1
					if target.Hits >= 4 then
						target.Until = 0
					end
				end
			end
		elseif def.Kind == "Camera" and s.Powered and lpos and now >= (s.ReadyAt or 0) then
			local pos = s.Model:GetPivot().Position
			if (lpos - pos).Magnitude <= (def.Range or 70) and los(pos, lpos + Vector3.new(0, 3, 0), L.Model) then
				s.ReadyAt = now + 6
				s.Model:SetAttribute("Alert", now)
				State.Cue("CameraAlert", lpos, pos)
			end
		end
	end
end

function Defense.Init()
	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(step)
			if not ok then
				warn("[Defense] " .. tostring(err))
			end
		end
	end)
end

return Defense
