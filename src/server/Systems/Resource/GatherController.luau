--!strict

const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared
const Systems = script.Parent.Parent

const Net = require(Packages.Net)
const ResourceData = require(Shared.Resources.ResourceData)
const ItemsList = require(Shared.Inventory.ItemsList)
const ColonyController = require(Systems.Colony.ColonyController)
const MailboxController = require(Systems.Colony.MailboxController)
const Bag = require(Systems.Inventory.Components.Bag)
const InventoryController = require(Systems.Inventory.InventoryController)
const ResourceNodeController = require(script.Parent.ResourceNodeController)

type ToolInfo = ResourceData.ToolInfo

type Pending = {
	Node: Instance,
	Started: number,
	Duration: number,
}

-- The client's bar may finish slightly before the server clock
const LATENCY_TOLERANCE = 0.25
-- Extra reach on top of GATHER_RANGE for movement lag
const RANGE_TOLERANCE = 4

const GatherController = {}

const pending: { [Player]: Pending } = {}
local started = false

local function getEquippedTool(player: Player): ToolInfo?
	local character = player.Character
	local tool = character and character:FindFirstChildWhichIsA("Tool")
	local id = tool and tool:GetAttribute("ToolId")

	return if typeof(id) == "string" then ResourceData.TOOLS[id] else nil
end

-- Returns the gather duration, or nil and why the player can't gather the node
local function validate(player: Player, node: Instance): (number?, string?)
	local info = ResourceNodeController.GetInfo(node)
	if not info or not node:IsA("Model") then
		return nil, "Already gathered"
	end

	local data = ColonyController.GetData(player)
	if not data then
		return nil, "Colony not loaded"
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil, "No character"
	end

	local offset = node:GetPivot().Position - root.Position
	if Vector2.new(offset.X, offset.Z).Magnitude > ResourceData.GATHER_RANGE + RANGE_TOLERANCE then
		return nil, "Too far away"
	end

	local backpack = InventoryController.GetBackpack(data)
	local itemId = ItemsList.GetItemId(info.Resource)
	if not backpack or not itemId or Bag.GetSpaceFor(backpack, itemId) <= 0 then
		return nil, "Bag full, deposit at your Town Hall or Warehouse"
	end

	local duration = ResourceData.GetGatherTime(info, getEquippedTool(player))
	if not duration then
		return nil, `Equip your {info.Tool}`
	end

	return duration, nil
end

local function onBeginGather(player: Player, node: unknown): (boolean, number | string)
	pending[player] = nil
	if typeof(node) ~= "Instance" then
		return false, "Nothing to gather"
	end

	local duration, reason = validate(player, node)
	if not duration then
		return false, reason or "Can't gather"
	end

	pending[player] = { Node = node, Started = os.clock(), Duration = duration }
	return true, duration
end

local function onFinishGather(player: Player): (boolean, string)
	local current = pending[player]
	pending[player] = nil
	if not current then
		return false, "Not gathering"
	end

	if os.clock() - current.Started < current.Duration - LATENCY_TOLERANCE then
		return false, "Too fast"
	end

	local duration, reason = validate(player, current.Node)
	local info = ResourceNodeController.GetInfo(current.Node)
	local data = ColonyController.GetData(player)
	if not duration or not info or not data then
		return false, reason or "Can't gather"
	end

	local backpack = InventoryController.GetBackpack(data)
	local itemId = ItemsList.GetItemId(info.Resource)
	if not backpack or not itemId then
		return false, "Can't gather"
	end

	local left = Bag.AddItem(backpack, itemId, info.Yield)
	local added = info.Yield - left
	ResourceNodeController.Deplete(current.Node)
	if left > 0 then
		-- Only part of the yield fit; the rest goes to the Town Hall mailbox
		MailboxController.Send(player, {
			From = "Lost & Found",
			Title = "Backpack full - sent to your mailbox",
			Body = `{left} {info.Resource} you gathered didn't fit in your backpack.`,
			Items = { { UniqueID = itemId, Quantity = left } },
		})
		return true, `+{added} {info.Resource} ({left} sent to your mailbox)`
	end
	ColonyController.Sync(player)

	return true, `+{added} {info.Resource}`
end

function GatherController.Start()
	if started then
		return
	end
	started = true

	Net:Handle("BeginGather", onBeginGather)
	Net:Handle("FinishGather", onFinishGather)
	Net:Connect("CancelGather", function(player: Player)
		pending[player] = nil
	end)

	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
	end)
end

return GatherController
