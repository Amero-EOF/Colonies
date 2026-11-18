--!strict
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const TextService = game:GetService("TextService")

const Shared = ReplicatedStorage.Shared
const InventoryFolder = Shared.Inventory

const InventoryTypes = require(InventoryFolder.InventoryTypes)
const BagSizes = require(InventoryFolder.BagSizes)
const ItemsList = require(InventoryFolder.ItemsList)

type BagData = InventoryTypes.Bag
type ItemStack = InventoryTypes.ItemStack
type Item = InventoryTypes.Item

const SETTINGS = table.freeze({
	MAX_ALIAS = 20,
})

-- Functions that act on plain bag data (saved as-is with ProfileStore)
const Bag = {}

function Bag.new(bagItem: Item): BagData
	assert(BagSizes[bagItem.ItemType], `No bag size found for bag: {bagItem.ItemType}`)

	return {
		UniqueID = bagItem.UniqueID,
		Items = {},
		Metadata = {},
	}
end

function Bag.GetSlotsCount(bag: BagData): number
	local itemType = ItemsList.GetItemName(bag.UniqueID)
	return if itemType then BagSizes[itemType] or 0 else 0
end

function Bag.GetStack(bag: BagData, slot: number): ItemStack?
	for _, stack in bag.Items do
		if stack.Slot == slot then
			return stack
		end
	end
	return nil
end

local function getFreeSlot(bag: BagData): number?
	for slot = 1, Bag.GetSlotsCount(bag) do
		if not Bag.GetStack(bag, slot) then
			return slot
		end
	end
	return nil
end

-- How many more of an item fit (topping up stacks and filling empty slots)
function Bag.GetSpaceFor(bag: BagData, uniqueID: number): number
	local maxStack = ItemsList.GetMaxStack(uniqueID)
	local space = 0
	for _, stack in bag.Items do
		if stack.UniqueID == uniqueID then
			space += maxStack - stack.Quantity
		end
	end

	return space + (Bag.GetSlotsCount(bag) - #bag.Items) * maxStack
end

-- Adds up to `quantity`, topping up existing stacks before using empty slots.
-- With `slot`, only that slot is used. Returns how many didn't fit.
function Bag.AddItem(bag: BagData, uniqueID: number, quantity: number, slot: number?): number
	if not ItemsList.GetItemName(uniqueID) or quantity <= 0 then
		return quantity
	end

	local maxStack = ItemsList.GetMaxStack(uniqueID)
	local remaining = quantity

	if slot then
		if slot < 1 or slot > Bag.GetSlotsCount(bag) then
			return remaining
		end

		local stack = Bag.GetStack(bag, slot)
		if not stack then
			local added = math.min(remaining, maxStack)
			table.insert(bag.Items, { UniqueID = uniqueID, Quantity = added, Slot = slot })
			return remaining - added
		elseif stack.UniqueID ~= uniqueID then
			return remaining
		end

		local added = math.min(remaining, maxStack - stack.Quantity)
		stack.Quantity += added
		return remaining - added
	end

	for _, stack in bag.Items do
		if stack.UniqueID == uniqueID and stack.Quantity < maxStack then
			local added = math.min(remaining, maxStack - stack.Quantity)
			stack.Quantity += added
			remaining -= added
			if remaining == 0 then
				return 0
			end
		end
	end

	while remaining > 0 do
		local free = getFreeSlot(bag)
		if not free then
			break
		end

		local added = math.min(remaining, maxStack)
		table.insert(bag.Items, { UniqueID = uniqueID, Quantity = added, Slot = free })
		remaining -= added
	end

	return remaining
end

-- Removes up to `quantity`, emptying the last stacks first; returns how many were removed
function Bag.RemoveItem(bag: BagData, uniqueID: number, quantity: number): number
	local removed = 0
	for i = #bag.Items, 1, -1 do
		local stack = bag.Items[i]
		if stack.UniqueID ~= uniqueID then
			continue
		end

		local taken = math.min(stack.Quantity, quantity - removed)
		stack.Quantity -= taken
		removed += taken
		if stack.Quantity == 0 then
			table.remove(bag.Items, i)
		end
		if removed == quantity then
			break
		end
	end

	return removed
end

function Bag.CountItem(bag: BagData, uniqueID: number): number
	local count = 0
	for _, stack in bag.Items do
		if stack.UniqueID == uniqueID then
			count += stack.Quantity
		end
	end
	return count
end

function Bag.FindItem(bag: BagData, itemType: string): ItemStack?
	local uniqueID = ItemsList.GetItemId(itemType)
	for _, stack in bag.Items do
		if stack.UniqueID == uniqueID then
			return stack
		end
	end
	return nil
end

-- Moves as much as fits from one bag into another; returns how many items moved.
-- Items `skip` returns true for stay behind (e.g. held tools when depositing).
function Bag.TransferAll(from: BagData, to: BagData, skip: ((uniqueID: number) -> boolean)?): number
	local moved = 0
	for i = #from.Items, 1, -1 do
		local stack = from.Items[i]
		if skip and skip(stack.UniqueID) then
			continue
		end
		local leftover = Bag.AddItem(to, stack.UniqueID, stack.Quantity)
		moved += stack.Quantity - leftover
		stack.Quantity = leftover
		if leftover == 0 then
			table.remove(from.Items, i)
		end
	end
	return moved
end

function Bag.ChangeAlias(bag: BagData, alias: string, player: Player): boolean
	if string.len(alias) > SETTINGS.MAX_ALIAS then
		return false
	end

	local ok, filtered = pcall(function(): string
		return TextService:FilterStringAsync(alias, player.UserId)
			:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		return false
	end

	bag.Metadata.Alias = filtered
	return true
end

return Bag
