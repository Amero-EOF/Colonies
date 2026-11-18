--!strict
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared

const InventoryTypes = require(Shared.Inventory.InventoryTypes)
const ItemsList = require(Shared.Inventory.ItemsList)
const Bag = require(script.Parent.Bag)

type InventoryData = InventoryTypes.Inventory
type BagData = InventoryTypes.Bag
type ItemStack = InventoryTypes.ItemStack
type Item = InventoryTypes.Item

const SETTINGS = {
	BAG_LIMIT = math.huge,
}

const DEFAULT_BAGS = { "Backpack" }

-- Functions that act on plain inventory data (saved as-is with ProfileStore)
const Inventory = {}

export type RemoveBagResult = "No bag found" | "Bag is not empty" | "Valid"

function Inventory.AddBag(inventory: InventoryData, bagItem: Item): boolean
	if not bagItem.Metadata.isBag or #inventory.Bags + 1 > SETTINGS.BAG_LIMIT then
		return false
	end

	table.insert(inventory.Bags, Bag.new(bagItem))
	return true
end

-- A new inventory holding the default bags
function Inventory.new(): InventoryData
	local inventory: InventoryData = { Bags = {} }

	for _, bagName in DEFAULT_BAGS do
		local item = ItemsList.GetItemByItemType(bagName)
		if not item then
			warn(`No item found for bag: {bagName}`)
			continue
		end
		Inventory.AddBag(inventory, item)
	end

	return inventory
end

function Inventory.GetBag(inventory: InventoryData, bagIndex: number): BagData?
	return inventory.Bags[bagIndex]
end

-- Adds to the given bag, or across bags in order; returns how many didn't fit
function Inventory.AddItem(
	inventory: InventoryData,
	uniqueID: number,
	quantity: number,
	bagIndex: number?,
	slot: number?
): number
	if bagIndex then
		local bag = inventory.Bags[bagIndex]
		return if bag then Bag.AddItem(bag, uniqueID, quantity, slot) else quantity
	end

	local remaining = quantity
	for _, bag in inventory.Bags do
		remaining = Bag.AddItem(bag, uniqueID, remaining)
		if remaining == 0 then
			break
		end
	end
	return remaining
end

function Inventory.SearchItem(inventory: InventoryData, itemType: string): { ItemStack }
	local stacks = {}
	for _, bag in inventory.Bags do
		local stack = Bag.FindItem(bag, itemType)
		if stack then
			table.insert(stacks, stack)
		end
	end
	return stacks
end

function Inventory.RemoveBag(inventory: InventoryData, bagIndex: number): RemoveBagResult
	local bag = inventory.Bags[bagIndex]
	if not bag then
		return "No bag found"
	end
	if #bag.Items > 0 then
		return "Bag is not empty"
	end

	table.remove(inventory.Bags, bagIndex)
	return "Valid"
end

return Inventory
