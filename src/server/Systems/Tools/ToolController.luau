--!strict

const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const ServerStorage = game:GetService("ServerStorage")

const ResourceData = require(ReplicatedStorage.Shared.Resources.ResourceData)
const InventoryTypes = require(ReplicatedStorage.Shared.Inventory.InventoryTypes)
const ItemsList = require(ReplicatedStorage.Shared.Inventory.ItemsList)

type ToolInfo = ResourceData.ToolInfo
type BagData = InventoryTypes.Bag

const HANDLE_COLOR = Color3.fromRGB(105, 64, 40)
const HEAD_COLOR = Color3.fromRGB(150, 150, 150)
const SCROLL_COLOR = Color3.fromRGB(236, 222, 180)
-- Attribute on Tools made from inventory items (the client finds the held Work Scroll by it)
const ITEM_ATTRIBUTE = "ItemType"

const ToolController = {}

local started = false

-- Holdable item types each player's backpack holds, from the last SyncItems
const heldItems: { [Player]: { [string]: boolean } } = {}

-- Clone of ServerStorage.Tools.<Id>, or a placeholder handle with a head
local function createTool(info: ToolInfo): Tool
	local folder = ServerStorage:FindFirstChild("Tools")
	local template = folder and folder:FindFirstChild(info.Id)

	local tool: Tool
	if template and template:IsA("Tool") then
		tool = template:Clone()
	else
		tool = Instance.new("Tool")

		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(0.4, 4, 0.4)
		handle.Color = HANDLE_COLOR
		handle.CanCollide = false
		handle.Parent = tool

		local head = Instance.new("Part")
		head.Name = "Head"
		head.Size = if info.Type == "Axe"
			then Vector3.new(0.4, 1.2, 1.6)
			else Vector3.new(0.4, 0.6, 3)
		head.Color = HEAD_COLOR
		head.CanCollide = false
		head.Massless = true
		head.CFrame = handle.CFrame * CFrame.new(0, 1.6, 0)
		head.Parent = tool

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = head
		weld.Parent = handle
	end

	tool.Name = info.Name
	tool.CanBeDropped = false
	tool:SetAttribute("ToolId", info.Id)

	return tool
end

local function giveStarterTools(player: Player)
	local backpack = player:WaitForChild("Backpack")
	for _, id in ResourceData.STARTER_TOOLS do
		local info = ResourceData.TOOLS[id]
		if info and not backpack:FindFirstChild(info.Name) then
			createTool(info).Parent = backpack
		end
	end
end

local function weld(part0: BasePart, part1: BasePart)
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = part0
	constraint.Part1 = part1
	constraint.Parent = part0
end

local function addPart(tool: Tool, name: string, size: Vector3, color: Color3, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.CanCollide = false
	part.Massless = name ~= "Handle"
	part.CFrame = cframe
	part.Parent = tool
	return part
end

-- Clone of ServerStorage.Tools.<ItemType>, or a placeholder look (shovel or rolled scroll)
local function createItemTool(itemType: string, name: string): Tool
	local folder = ServerStorage:FindFirstChild("Tools")
	local template = folder and folder:FindFirstChild(itemType)

	local tool: Tool
	if template and template:IsA("Tool") then
		tool = template:Clone()
	else
		tool = Instance.new("Tool")
		if itemType == "WorkScroll" then
			-- Rolled paper with wooden ends; the cylinder's axis is its X
			local handle = addPart(
				tool,
				"Handle",
				Vector3.new(1.6, 0.5, 0.5),
				SCROLL_COLOR,
				CFrame.Angles(0, 0, math.pi / 2)
			)
			handle.Shape = Enum.PartType.Cylinder
			for _, side in { -1, 1 } do
				local rod = addPart(
					tool,
					"Rod",
					Vector3.new(0.2, 0.6, 0.6),
					HANDLE_COLOR,
					handle.CFrame * CFrame.new(side * 0.85, 0, 0)
				)
				rod.Shape = Enum.PartType.Cylinder
				weld(handle, rod)
			end
		else
			-- Long wooden shaft with a flat metal blade
			local handle =
				addPart(tool, "Handle", Vector3.new(0.3, 4, 0.3), HANDLE_COLOR, CFrame.new())
			local blade = addPart(
				tool,
				"Blade",
				Vector3.new(1.1, 1.3, 0.15),
				HEAD_COLOR,
				handle.CFrame * CFrame.new(0, -2.5, 0)
			)
			weld(handle, blade)
		end
	end

	tool.Name = name
	tool.CanBeDropped = false
	tool:SetAttribute(ITEM_ATTRIBUTE, itemType)

	return tool
end

-- Item Tools the player has, in the hotbar or equipped, by item type
local function getItemTools(player: Player): { [string]: Tool }
	local tools: { [string]: Tool } = {}
	local containers: { Instance } = {}
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		table.insert(containers, backpack)
	end
	if player.Character then
		table.insert(containers, player.Character)
	end
	for _, container in containers do
		for _, child in container:GetChildren() do
			local itemType = child:GetAttribute(ITEM_ATTRIBUTE)
			if child:IsA("Tool") and typeof(itemType) == "string" then
				if tools[itemType] then
					child:Destroy()
				else
					tools[itemType] = child
				end
			end
		end
	end
	return tools
end

-- Adds a Tool for every held item type the player owns and removes the rest
local function applyHeldItems(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local owned: { [string]: boolean } = heldItems[player] or {}
	local tools = getItemTools(player)

	for itemType, tool in tools do
		if not owned[itemType] then
			tool:Destroy()
		end
	end
	if not backpack then
		return
	end
	for itemType in owned do
		if not tools[itemType] then
			local id = ItemsList.GetItemId(itemType)
			local name = (id and ItemsList.GetDisplayName(id)) or itemType
			createItemTool(itemType, name).Parent = backpack
		end
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function()
		giveStarterTools(player)
		applyHeldItems(player)
	end)

	if player.Character then
		giveStarterTools(player)
		applyHeldItems(player)
	end
end

-- One hotbar Tool per holdable item type (Landscaping Shovel, Work Scroll...) in the
-- player's backpack bag; called whenever the colony state is synced
function ToolController.SyncItems(player: Player, backpack: BagData?)
	local owned: { [string]: boolean } = {}
	if backpack then
		for _, stack in backpack.Items do
			local itemType = ItemsList.GetItemName(stack.UniqueID)
			if itemType and ItemsList.IsHoldable(stack.UniqueID) then
				owned[itemType] = true
			end
		end
	end
	heldItems[player] = owned
	applyHeldItems(player)
end

function ToolController.Start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		heldItems[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return ToolController
