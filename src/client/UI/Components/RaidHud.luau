--!strict

const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")
const UserInputService = game:GetService("UserInputService")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const ItemsList = require(Shared.Inventory.ItemsList)
const RaidData = require(Shared.Raid.RaidData)
const DayCycle = require(Shared.Time.DayCycle)
const RaidStore = require(script.Parent.Parent.Parent.Colony.RaidStore)

const create = vide.create
const source = vide.source
const show = vide.show
const cleanup = vide.cleanup

type Props = {
	-- False while something else owns mouse clicks (e.g. building placement)
	Enabled: () -> boolean,
}

const RAY_LENGTH = 500
const BANNER_COLOR = Color3.fromRGB(120, 30, 30)
-- Left of the clock in the top right corner
const RIGHT_OFFSET = 16 + 150 + 8

const player = Players.LocalPlayer

local function isAttackInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function getRaidersFolder(): Instance?
	local colony = workspace:FindFirstChild("MyColony")
	return colony and colony:FindFirstChild("Raiders")
end

local function getRaiderId(model: Instance?): number?
	local id = model and model:GetAttribute("RaiderId")
	return if typeof(id) == "number" then id else nil
end

-- The raider under a screen position, if any
local function findRaider(position: Vector3): number?
	local folder = getRaidersFolder()
	local camera = workspace.CurrentCamera
	if not folder or not camera then
		return nil
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }

	local ray = camera:ScreenPointToRay(position.X, position.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, params)
	local hit = result and result.Instance
	return getRaiderId(hit and hit:FindFirstAncestorOfClass("Model"))
end

-- True while the character holds an item that's a weapon (ItemsList Metadata.Damage)
local function isHoldingWeapon(): boolean
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local itemType = tool and tool:GetAttribute("ItemType")
	local itemId = if typeof(itemType) == "string" then ItemsList.GetItemId(itemType) else nil
	return itemId ~= nil and ItemsList.GetMetadata(itemId).Damage ~= nil
end

-- The raider closest to the character, within the player's reach
local function findNearestRaider(): number?
	local folder = getRaidersFolder()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not folder or not root or not root:IsA("BasePart") then
		return nil
	end

	local nearest: number? = nil
	local nearestDistance = RaidData.PLAYER_REACH
	for _, model in folder:GetChildren() do
		local id = getRaiderId(model)
		if id and model:IsA("Model") then
			local offset = model:GetPivot().Position - root.Position
			local distance = Vector2.new(offset.X, offset.Z).Magnitude
			if distance <= nearestDistance then
				nearest = id
				nearestDistance = distance
			end
		end
	end
	return nearest
end

local function getText(now: number): string
	local left = #RaidStore.Raiders()
	local hours = math.ceil(math.max(DayCycle.HoursBetween(now, RaidStore.RetreatAt()), 0))
	local retreat = if hours > 0 then `they retreat in {hours}h` else "they are retreating"
	return `Raid! {left} of {RaidStore.Total()} raiders left, {retreat}`
end

-- Raid banner (top right, beside the clock) and click/tap-to-attack: click a raider next to you
-- to strike it; with a weapon in hand, a click anywhere strikes the nearest raider in reach
local function RaidHud(props: Props)
	local text = source("")

	local connections = {
		RunService.Heartbeat:Connect(function()
			if not RaidStore.Active() then
				return
			end
			local current = getText(workspace:GetServerTimeNow())
			if current ~= text() then
				text(current)
			end
		end),

		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if
				gameProcessed
				or not isAttackInput(input)
				or not RaidStore.Active()
				or not props.Enabled()
			then
				return
			end
			local id = findRaider(input.Position)
			if not id and isHoldingWeapon() then
				id = findNearestRaider()
			end
			if id then
				RaidStore.Attack(id)
			end
		end),
	}

	cleanup(function()
		for _, connection in connections do
			connection:Disconnect()
		end
	end)

	return show(RaidStore.Active, function()
		return create("TextLabel")({
			Name = "RaidBanner",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -RIGHT_OFFSET, 0, 8),
			Size = UDim2.fromOffset(330, 30),
			BackgroundColor3 = BANNER_COLOR,
			BackgroundTransparency = 0.15,
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 15,
			Font = Enum.Font.GothamBold,
			Text = text,

			create("UICorner")({}),
		})
	end)
end

return RaidHud
