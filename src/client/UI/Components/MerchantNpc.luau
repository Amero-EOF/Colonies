--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const MerchantData = require(Shared.Merchant.MerchantData)
const ColonyStore = require(script.Parent.Parent.Parent.Colony.ColonyStore)

const cleanup = vide.cleanup
const derive = vide.derive
const effect = vide.effect

type Props = {
	-- Opens (true) or closes (false) the shop; closes when the player walks away
	OnTrade: (open: boolean) -> (),
}

const SKIN_COLOR = Color3.fromRGB(229, 184, 143)
const ROBE_COLOR = Color3.fromRGB(95, 50, 130)
const PANTS_COLOR = Color3.fromRGB(60, 45, 35)
const GOLD_COLOR = Color3.fromRGB(215, 170, 60)
const HAT_COLOR = Color3.fromRGB(120, 30, 40)
const BEARD_COLOR = Color3.fromRGB(200, 200, 200)
const WOOD_COLOR = Color3.fromRGB(140, 95, 55)
const DARK_WOOD_COLOR = Color3.fromRGB(80, 55, 35)
const CANOPY_COLOR = Color3.fromRGB(190, 60, 50)
const STRIPE_COLOR = Color3.fromRGB(240, 225, 190)
-- Lying a cylinder's X axis upright
const UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)
const SHOULDER = Vector3.new(1.5, 4, 0)

local function makePart(
	model: Model,
	name: string,
	size: Vector3,
	color: Color3,
	cframe: CFrame,
	cylinder: boolean?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.CFrame = cframe
	part.Anchored = true
	-- Players bump into the cart, not the merchant himself
	part.CanCollide = string.sub(name, 1, 4) == "Cart"
	part.CanTouch = false
	part.CanQuery = name == "Torso" or part.CanCollide
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if cylinder then
		part.Shape = Enum.PartType.Cylinder
	end
	part.Parent = model
	return part
end

-- Block figure in a robe and wide-brimmed hat with his covered cart behind him.
-- Built around the origin at his feet, facing -Z.
local function buildModel(): (Model, Part, Part)
	local model = Instance.new("Model")
	model.Name = "TravellingMerchant"

	makePart(model, "LeftLeg", Vector3.new(1, 2, 1), PANTS_COLOR, CFrame.new(-0.5, 1, 0))
	makePart(model, "RightLeg", Vector3.new(1, 2, 1), PANTS_COLOR, CFrame.new(0.5, 1, 0))
	makePart(model, "Robe", Vector3.new(2.4, 1.6, 1.4), ROBE_COLOR, CFrame.new(0, 1.2, 0))
	local torso = makePart(model, "Torso", Vector3.new(2, 2, 1), ROBE_COLOR, CFrame.new(0, 3, 0))
	makePart(model, "Sash", Vector3.new(2.05, 0.3, 1.05), GOLD_COLOR, CFrame.new(0, 2.4, 0))
	makePart(model, "LeftArm", Vector3.new(1, 2, 1), ROBE_COLOR, CFrame.new(-1.5, 3, 0))
	local rightArm =
		makePart(model, "RightArm", Vector3.new(1, 2, 1), ROBE_COLOR, CFrame.new(1.5, 3, 0))
	local head =
		makePart(model, "Head", Vector3.new(1.2, 1.2, 1.2), SKIN_COLOR, CFrame.new(0, 4.6, 0))
	makePart(model, "Beard", Vector3.new(1, 0.6, 0.3), BEARD_COLOR, CFrame.new(0, 4.2, -0.65))
	makePart(
		model,
		"HatBrim",
		Vector3.new(0.2, 3, 3),
		HAT_COLOR,
		CFrame.new(0, 5.3, 0) * UPRIGHT,
		true
	)
	makePart(
		model,
		"HatCrown",
		Vector3.new(1, 1.4, 1.4),
		HAT_COLOR,
		CFrame.new(0, 5.85, 0) * UPRIGHT,
		true
	)
	makePart(
		model,
		"HatBand",
		Vector3.new(0.25, 1.45, 1.45),
		GOLD_COLOR,
		CFrame.new(0, 5.5, 0) * UPRIGHT,
		true
	)

	-- The cart
	makePart(model, "CartBed", Vector3.new(4, 1, 5), WOOD_COLOR, CFrame.new(0, 1.8, 4.5))
	for _, x in { -2.2, 2.2 } do
		makePart(
			model,
			"CartWheel",
			Vector3.new(0.4, 2, 2),
			DARK_WOOD_COLOR,
			CFrame.new(x, 1, 4.5),
			true
		)
		makePart(
			model,
			"CartShaft",
			Vector3.new(0.3, 0.3, 3),
			DARK_WOOD_COLOR,
			CFrame.new(x * 0.7, 1.8, 8.5)
		)
		for _, z in { 2.3, 6.7 } do
			makePart(
				model,
				"CartPost",
				Vector3.new(0.3, 3, 0.3),
				DARK_WOOD_COLOR,
				CFrame.new(x * 0.8, 3.8, z)
			)
		end
	end
	makePart(model, "CartCanopy", Vector3.new(4.4, 0.3, 5.4), CANOPY_COLOR, CFrame.new(0, 5.4, 4.5))
	for _, z in { 2.7, 4.5, 6.3 } do
		makePart(
			model,
			"CartStripe",
			Vector3.new(4.45, 0.32, 0.8),
			STRIPE_COLOR,
			CFrame.new(0, 5.4, z)
		)
	end
	makePart(model, "CartCrate", Vector3.new(1.2, 1.2, 1.2), WOOD_COLOR, CFrame.new(-0.9, 2.9, 3.8))
	makePart(model, "CartCrate", Vector3.new(1, 1, 1), GOLD_COLOR, CFrame.new(0.9, 2.8, 5.2))
	makePart(
		model,
		"CartBarrel",
		Vector3.new(1.4, 1.1, 1.1),
		DARK_WOOD_COLOR,
		CFrame.new(0.6, 3, 3.4) * UPRIGHT,
		true
	)

	-- With a PrimaryPart the model pivots on it (WorldPivot is ignored), so move the torso's
	-- pivot down to his feet; otherwise PivotTo sinks him 3 studs into the ground
	model.PrimaryPart = torso
	torso.PivotOffset = torso.CFrame:Inverse()

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(200, 30)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	billboard.MaxDistance = 80
	billboard.Adornee = head
	billboard.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = GOLD_COLOR
	label.TextStrokeTransparency = 0.4
	label.TextSize = 16
	label.Font = Enum.Font.GothamMedium
	label.Text = MerchantData.NAME
	label.Parent = billboard

	return model, torso, rightArm
end

-- The travelling merchant beside the Town Hall with his "Trade" prompt. A world object:
-- mount it with show() outside the ScreenGui.
local function MerchantNpc(props: Props): Model
	local model, torso, rightArm = buildModel()

	local attachment = Instance.new("Attachment")
	attachment.Name = "TradePromptAttachment"
	attachment.Position = Vector3.new(0, -1, 0)
	attachment.Parent = torso

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TradePrompt"
	prompt.ActionText = "Trade"
	prompt.ObjectText = MerchantData.NAME
	prompt.HoldDuration = 0
	-- T, so it doesn't clash with the Town Hall's E/F prompts nearby
	prompt.KeyboardKeyCode = Enum.KeyCode.T
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = MerchantData.TRADE_REACH
	prompt.Parent = attachment

	prompt.Triggered:Connect(function()
		props.OnTrade(true)
	end)
	prompt.PromptHidden:Connect(function()
		-- Only close when walking away, not when the model is being removed
		task.defer(function()
			if prompt.Parent then
				props.OnTrade(false)
			end
		end)
	end)

	local spot = derive(function()
		return MerchantData.GetSpot(ColonyStore.Buildings())
	end)

	local pivot = CFrame.new()
	effect(function()
		local current = spot()
		if current then
			pivot = current
			model:PivotTo(current)
			model.Parent = workspace:FindFirstChild("MyColony") or workspace
		else
			model.Parent = nil
		end
	end)

	-- Waves now and then (one part posed per frame)
	local connection = RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local wave = math.max(math.sin(t * 0.8), 0)
		local angle = -wave * math.rad(150) + math.sin(t * 6) * math.rad(15) * wave
		rightArm.CFrame = pivot
			* CFrame.new(SHOULDER)
			* CFrame.Angles(angle, 0, 0)
			* CFrame.new(0, -1, 0)
	end)

	cleanup(function()
		connection:Disconnect()
		model:Destroy()
	end)

	return model
end

return MerchantNpc
