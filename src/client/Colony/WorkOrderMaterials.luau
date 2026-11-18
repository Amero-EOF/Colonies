--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared

const BuildingBlueprint = require(Shared.Buildings.BuildingBlueprint)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const InventoryTypes = require(Shared.Inventory.InventoryTypes)
const ItemsList = require(Shared.Inventory.ItemsList)
const ColonistStore = require(script.Parent.ColonistStore)
const ColonyStore = require(script.Parent.ColonyStore)

type WorkOrder = ColonyTypes.WorkOrder

-- One material a work order still needs
export type Material = {
	ItemType: string,
	-- Units the rest of the order uses (BuildingBlueprint.GetRemainingCost)
	Remaining: number,
	-- Units already in the Builder's Hut storage or the Builder's inventory, capped at Remaining
	Ready: number,
}

const HUT = "BuilderHut"

-- What a work order still needs against what's ready for it. Shared by the work order list and
-- the Work Scroll so they agree with the Builder (server Builder.luau uses the same remaining cost).
-- Reads the stores' sources, so it's reactive inside Vide scopes.
const WorkOrderMaterials = {}

function WorkOrderMaterials.CountItem(bag: InventoryTypes.Bag?, itemId: number): number
	local count = 0
	if bag then
		for _, stack in bag.Items do
			if stack.UniqueID == itemId then
				count += stack.Quantity
			end
		end
	end
	return count
end

-- Per material, sorted by ItemType
function WorkOrderMaterials.Get(order: WorkOrder): { Material }
	local remaining =
		BuildingBlueprint.GetRemainingCost(order.BuildingId, order.TargetLevel, order.Progress)
	local hut = ColonyStore.HutStorage()[HUT]
	local builder = ColonistStore.Get(order.BuilderId)
	local materials: { Material } = {}
	for itemType, amount in remaining do
		local item = ItemsList.GetItemByItemType(itemType)
		local have = 0
		if item then
			have = WorkOrderMaterials.CountItem(hut, item.UniqueID)
				+ WorkOrderMaterials.CountItem(builder and builder.Carried, item.UniqueID)
		end
		table.insert(materials, {
			ItemType = itemType,
			Remaining = amount,
			Ready = math.min(have, amount),
		})
	end
	table.sort(materials, function(a, b)
		return a.ItemType < b.ItemType
	end)
	return materials
end

-- The order the Builder is working on, else the oldest one
function WorkOrderMaterials.GetCurrentOrder(): WorkOrder?
	local orders = ColonyStore.WorkOrders()
	for _, order in orders do
		if order.BuilderId and ColonistStore.Get(order.BuilderId) then
			return order
		end
	end
	return orders[1]
end

return WorkOrderMaterials
