--[[
	LocustRig: builds THE LOCUST from parts (no meshes or uploads needed).

	Tall, hunched, insect-like: a long tilted thorax, segmented abdomen, a narrow head with
	mandibles, antennae and glowing eyes, very long thin arms ending in claws, a second pair of
	small folded "praying" arms, tattered wings, and digitigrade legs.

	Every limb segment hangs from a Motor6D, so clients can animate it procedurally
	(LocustAnimator) without any animation assets. The server only moves the HumanoidRootPart.
	The same builder makes the menu background Locust and the small Nymph scouts (scale < 1).
]]

local LocustRig = {}

local function rad(d)
	return math.rad(d)
end

-- Build(variant, scale) -> Model (Humanoid + parts, not parented)
function LocustRig.Build(variant, scale: number?)
	local s = scale or 1
	variant = variant or { Body = "17130f", Shell = "2a2118", Eyes = "ffb000" }
	local body = Color3.fromHex(variant.Body)
	local shell = Color3.fromHex(variant.Shell)
	local eyes = Color3.fromHex(variant.Eyes)

	local model = Instance.new("Model")
	model.Name = "Locust"

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(3, 9, 3) * s
	root.Transparency = 1
	root.CanCollide = true
	root.CanQuery = true
	root.CanTouch = true
	root.Anchored = false
	root.CustomPhysicalProperties = PhysicalProperties.new(2, 0.3, 0, 1, 1)
	root.Parent = model
	model.PrimaryPart = root

	local function part(name, size, color, mat, transparency)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size * s
		p.Color = color
		p.Material = mat or Enum.Material.SmoothPlastic
		p.Transparency = transparency or (if variant.Translucent then 0.35 else 0)
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Anchored = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end

	-- Motor6D from parent to child. jointInParent: CFrame of the joint in parent space,
	-- jointInChild: where the joint sits in the child's space.
	local function motor(name, parentPart, childPart, jointInParent: CFrame, jointInChild: CFrame)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = parentPart
		m.Part1 = childPart
		m.C0 = CFrame.new(jointInParent.Position * s) * jointInParent.Rotation
		m.C1 = CFrame.new(jointInChild.Position * s) * jointInChild.Rotation
		m.Parent = parentPart
		return m
	end

	local function weld(parentPart, childPart, offset: CFrame)
		local w = Instance.new("Weld")
		w.Part0 = parentPart
		w.Part1 = childPart
		w.C0 = CFrame.new(offset.Position * s) * offset.Rotation
		w.Parent = childPart
		return w
	end

	-- torso: tilted forward, joint at the waist
	local thorax = part("Thorax", Vector3.new(2.2, 4, 1.8), shell, Enum.Material.Slate)
	motor("Waist", root, thorax, CFrame.new(0, 1.2, 0) * CFrame.Angles(rad(-35), 0, 0), CFrame.new(0, -2, 0))
	local plate = part("ChestPlate", Vector3.new(1.6, 3, 0.4), body, Enum.Material.SmoothPlastic)
	weld(thorax, plate, CFrame.new(0, 0.1, -0.95))
	for i = 0, 2 do
		local ridge = part("Ridge", Vector3.new(1.9, 0.3, 0.5), shell, Enum.Material.Slate)
		weld(thorax, ridge, CFrame.new(0, 1.2 - i * 1.1, 0.95))
	end
	-- spines down the back, carapace side plates, belly bands
	for i = 0, 4 do
		local spine = part("Spine", Vector3.new(0.16, 0.9 - i * 0.1, 0.16), body, Enum.Material.Slate)
		weld(thorax, spine, CFrame.new(0, 1.7 - i * 0.8, 1.05) * CFrame.Angles(rad(-55), 0, 0) * CFrame.new(0, 0.35, 0))
	end
	for _, side in { -1, 1 } do
		local sidePlate = part("SidePlate", Vector3.new(0.35, 3.2, 1.5), shell, Enum.Material.Slate)
		weld(thorax, sidePlate, CFrame.new(side * 1.12, 0.1, 0.1) * CFrame.Angles(0, 0, rad(side * -6)))
		local shoulderPlate = part("ShoulderPlate", Vector3.new(0.9, 0.5, 1.2), shell, Enum.Material.Slate)
		weld(thorax, shoulderPlate, CFrame.new(side * 1.1, 1.75, 0) * CFrame.Angles(0, 0, rad(side * 25)))
	end
	for i = 0, 3 do
		local band = part("BellyBand", Vector3.new(1.4, 0.16, 0.42), shell, Enum.Material.Slate)
		weld(thorax, band, CFrame.new(0, 1.1 - i * 0.65, -1.02))
	end

	-- abdomen (two segments, hanging back and down)
	local abd1 = part("Abdomen", Vector3.new(1.9, 1.7, 2.8), shell, Enum.Material.Slate)
	motor("AbdomenJoint", root, abd1, CFrame.new(0, 0.6, 0.9) * CFrame.Angles(rad(28), 0, 0), CFrame.new(0, 0, -1.3))
	local abd2 = part("AbdomenTip", Vector3.new(1.4, 1.3, 2.4), body, Enum.Material.Slate)
	motor("AbdomenTipJoint", abd1, abd2, CFrame.new(0, -0.1, 1.3) * CFrame.Angles(rad(18), 0, 0), CFrame.new(0, 0, -1.1))
	for i = 0, 2 do
		local ring = part("Segment", Vector3.new(2.05, 1.85, 0.22), body, Enum.Material.Slate)
		weld(abd1, ring, CFrame.new(0, 0, -0.9 + i * 0.9))
		local ring2 = part("Segment", Vector3.new(1.52, 1.42, 0.2), shell, Enum.Material.Slate)
		weld(abd2, ring2, CFrame.new(0, 0, -0.8 + i * 0.8))
	end
	for _, side in { -1, 1 } do
		for i = 0, 2 do
			local pore = part("Spiracle", Vector3.new(0.14, 0.14, 0.14), eyes, Enum.Material.Neon, 0.3)
			pore.Shape = Enum.PartType.Ball
			weld(abd1, pore, CFrame.new(side * 0.96, -0.2, -0.9 + i * 0.9))
		end
	end
	local stinger = part("Stinger", Vector3.new(0.18, 0.18, 1.1), shell, Enum.Material.Slate)
	weld(abd2, stinger, CFrame.new(0, -0.2, 1.55) * CFrame.Angles(rad(-25), 0, 0))

	-- head
	local head = part("Head", Vector3.new(1.3, 1.4, 2.6), shell, Enum.Material.Slate)
	local neck = motor("Neck", thorax, head, CFrame.new(0, 2, -0.3) * CFrame.Angles(rad(28), 0, 0), CFrame.new(0, -0.3, 1.1))
	local jaw = part("Jaw", Vector3.new(1.1, 0.4, 1.8), body)
	weld(head, jaw, CFrame.new(0, -0.75, -0.3))
	for _, side in { -1, 1 } do
		local eye = part("Eye", Vector3.new(0.42, 0.42, 0.42), eyes, Enum.Material.Neon, 0)
		eye.Shape = Enum.PartType.Ball
		weld(head, eye, CFrame.new(side * 0.42, 0.25, -1.05))
		local mandible = part("Mandible", Vector3.new(0.18, 0.18, 1.1), body)
		weld(head, mandible, CFrame.new(side * 0.32, -0.7, -1.45) * CFrame.Angles(0, rad(side * 18), 0))
		local antenna = part("Antenna", Vector3.new(0.1, 0.1, 3.8), body)
		weld(head, antenna, CFrame.new(side * 0.35, 0.95, -0.2) * CFrame.Angles(rad(48), rad(side * -14), 0) * CFrame.new(0, 0, 1.6))
	end
	-- crest, cheek plates, extra small eyes, segmented mandibles and palps
	local crest = part("Crest", Vector3.new(0.3, 0.5, 2.2), body, Enum.Material.Slate)
	weld(head, crest, CFrame.new(0, 0.8, 0.1))
	for _, side in { -1, 1 } do
		local cheek = part("Cheek", Vector3.new(0.3, 0.9, 1.4), body, Enum.Material.Slate)
		weld(head, cheek, CFrame.new(side * 0.68, -0.2, -0.4) * CFrame.Angles(0, rad(side * 10), 0))
		for k = 0, 2 do
			local small = part("SmallEye", Vector3.new(0.16, 0.16, 0.16), eyes, Enum.Material.Neon, 0)
			small.Shape = Enum.PartType.Ball
			weld(head, small, CFrame.new(side * (0.2 + k * 0.12), 0.55 - k * 0.04, -0.95 + k * 0.08))
		end
		local mTip = part("MandibleTip", Vector3.new(0.14, 0.14, 0.7), shell)
		weld(head, mTip, CFrame.new(side * 0.32, -0.7, -1.45) * CFrame.Angles(0, rad(side * 18), 0) * CFrame.new(0, 0, -0.75) * CFrame.Angles(0, rad(side * -55), 0) * CFrame.new(0, 0, -0.25))
		local palp = part("Palp", Vector3.new(0.09, 0.09, 0.8), body)
		weld(head, palp, CFrame.new(side * 0.5, -0.85, -1.0) * CFrame.Angles(rad(-35), rad(side * 25), 0) * CFrame.new(0, 0, -0.3))
	end
	local glow = Instance.new("PointLight")
	glow.Name = "EyeGlow"
	glow.Color = eyes
	glow.Range = 9 * s
	glow.Brightness = 1.6
	glow.Shadows = false
	glow.Parent = head
	local eyeAtt = Instance.new("Attachment")
	eyeAtt.Name = "EyeAttachment"
	eyeAtt.Position = Vector3.new(0, 0.25, -1.2) * s
	eyeAtt.Parent = head

	-- long arms (shoulder -> upper -> fore -> claw fingers)
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		local upper = part("UpperArm" .. tag, Vector3.new(0.5, 3.8, 0.5), body)
		motor("Shoulder" .. tag, thorax, upper, CFrame.new(side * 1.3, 1.5, -0.2) * CFrame.Angles(rad(40), 0, rad(side * 12)), CFrame.new(0, 1.9, 0))
		local fore = part("ForeArm" .. tag, Vector3.new(0.38, 4.4, 0.38), body)
		motor("Elbow" .. tag, upper, fore, CFrame.new(0, -1.9, 0) * CFrame.Angles(rad(35), 0, 0), CFrame.new(0, 2.2, 0))
		local hand = part("Hand" .. tag, Vector3.new(0.5, 0.6, 0.4), shell)
		motor("Wrist" .. tag, fore, hand, CFrame.new(0, -2.2, 0), CFrame.new(0, 0.3, 0))
		for k = -1, 1 do
			local claw = part("Claw", Vector3.new(0.12, 1.5, 0.12), shell)
			weld(hand, claw, CFrame.new(k * 0.18, -0.9, 0) * CFrame.Angles(rad(15), 0, rad(k * 8)))
			local tip = part("ClawTip", Vector3.new(0.08, 0.5, 0.08), body)
			weld(claw, tip, CFrame.new(0, -0.9, -0.08) * CFrame.Angles(rad(25), 0, 0))
		end
		-- mantis spikes along the forearm, bands on the upper arm, an elbow knob
		for k = 0, 3 do
			local spike = part("ArmSpike", Vector3.new(0.1, 0.55, 0.1), shell)
			weld(fore, spike, CFrame.new(0, 1.4 - k * 0.9, -0.22) * CFrame.Angles(rad(-50), 0, 0) * CFrame.new(0, 0.22, 0))
		end
		for k = 0, 2 do
			local band = part("ArmBand", Vector3.new(0.6, 0.14, 0.6), shell, Enum.Material.Slate)
			weld(upper, band, CFrame.new(0, 1.2 - k * 1.2, 0))
		end
		local knob = part("ElbowKnob", Vector3.new(0.55, 0.55, 0.55), shell, Enum.Material.Slate)
		knob.Shape = Enum.PartType.Ball
		weld(fore, knob, CFrame.new(0, 2.1, 0.05))
		-- small folded "praying" arms
		local small = part("SmallArm" .. tag, Vector3.new(0.25, 1.5, 0.25), body)
		motor("SmallShoulder" .. tag, thorax, small, CFrame.new(side * 0.7, 0.6, -0.85) * CFrame.Angles(rad(-60), 0, rad(side * 10)), CFrame.new(0, 0.75, 0))
		local smallFore = part("SmallFore" .. tag, Vector3.new(0.2, 1.4, 0.2), shell)
		motor("SmallElbow" .. tag, small, smallFore, CFrame.new(0, -0.75, 0) * CFrame.Angles(rad(130), 0, 0), CFrame.new(0, 0.7, 0))
		-- wings folded on the back
		local wing = part("Wing" .. tag, Vector3.new(0.06, 3.8, 1.3), shell, Enum.Material.SmoothPlastic, 0.4)
		motor("WingJoint" .. tag, thorax, wing, CFrame.new(side * 0.45, 1.4, 0.95) * CFrame.Angles(rad(12), rad(side * 8), rad(side * -6)), CFrame.new(0, 1.8, 0))
		for k = 0, 2 do
			local vein = part("WingVein", Vector3.new(0.08, 3.4 - k * 0.6, 0.06), body, Enum.Material.SmoothPlastic, 0)
			weld(wing, vein, CFrame.new(0, 0.1 + k * 0.3, -0.45 + k * 0.42) * CFrame.Angles(rad(-6 + k * 6), 0, 0))
		end
		local hind = part("HindWing" .. tag, Vector3.new(0.05, 3, 1.1), body, Enum.Material.SmoothPlastic, 0.55)
		weld(wing, hind, CFrame.new(side * 0.06, -0.3, 0.35) * CFrame.Angles(rad(8), 0, 0))
	end

	-- digitigrade legs (hip -> thigh -> shin -> foot)
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		local thigh = part("Thigh" .. tag, Vector3.new(0.75, 3.1, 0.75), body)
		motor("Hip" .. tag, root, thigh, CFrame.new(side * 0.95, 0.5, 0.2) * CFrame.Angles(rad(30), 0, 0), CFrame.new(0, 1.55, 0))
		local shin = part("Shin" .. tag, Vector3.new(0.5, 3.3, 0.5), body)
		motor("Knee" .. tag, thigh, shin, CFrame.new(0, -1.55, 0) * CFrame.Angles(rad(-72), 0, 0), CFrame.new(0, 1.65, 0))
		local foot = part("Foot" .. tag, Vector3.new(0.4, 1.8, 0.4), shell)
		motor("Ankle" .. tag, shin, foot, CFrame.new(0, -1.65, 0) * CFrame.Angles(rad(58), 0, 0), CFrame.new(0, 0.9, 0))
		for k = -1, 1, 2 do
			local toe = part("Toe", Vector3.new(0.14, 0.14, 1.1), shell)
			weld(foot, toe, CFrame.new(k * 0.15, -0.85, -0.4) * CFrame.Angles(rad(-20), rad(k * 12), 0))
		end
		local heel = part("HeelSpur", Vector3.new(0.12, 0.12, 0.7), shell)
		weld(foot, heel, CFrame.new(0, -0.8, 0.3) * CFrame.Angles(rad(25), 0, 0))
		for k = 0, 2 do
			local spike = part("LegSpike", Vector3.new(0.1, 0.5, 0.1), shell)
			weld(shin, spike, CFrame.new(0, 1.1 - k * 1.0, 0.24) * CFrame.Angles(rad(55), 0, 0) * CFrame.new(0, 0.2, 0))
		end
		local kneeCap = part("KneeCap", Vector3.new(0.85, 0.85, 0.85), shell, Enum.Material.Slate)
		kneeCap.Shape = Enum.PartType.Ball
		weld(shin, kneeCap, CFrame.new(0, 1.6, 0))
		local thighPlate = part("ThighPlate", Vector3.new(0.9, 2.2, 0.35), shell, Enum.Material.Slate)
		weld(thigh, thighPlate, CFrame.new(side * 0.3, 0.2, -0.3) * CFrame.Angles(0, rad(side * 20), 0))
	end

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.HipHeight = 1.5 * s
	hum.WalkSpeed = 10
	hum.UseJumpPower = true
	hum.JumpPower = 0
	hum.MaxSlopeAngle = 50
	hum.AutoRotate = true
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.MaxHealth = 1e9
	hum.Health = 1e9
	hum.Parent = model

	model:SetAttribute("Scale", s)
	model:SetAttribute("Variant", variant.Name or "THE LOCUST")
	return model, neck
end

return LocustRig
