--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared

const BagSizes = require(Shared.Inventory.BagSizes)
const InventoryTypes = require(Shared.Inventory.InventoryTypes)
const ItemsList = require(Shared.Inventory.ItemsList)

type Bag = InventoryTypes.Bag
type ItemStack = InventoryTypes.ItemStack

-- One slot-to-slot move between (or inside) bags, sent to the MoveItems remote.
-- Bags are named by refs: "Backpack", "Storage", "Hut/<BuildingId>", "Colonist/<id>".
export type Move = {
	From: string,
	FromSlot: number,
	To: string,
	ToSlot: number,
	Count: number,
}

-- Most moves one MoveItems call may carry (a shift-distribute over every slot of a big bag)
const MAX_MOVES = 40

-- Slot moves on plain bag data. The server applies them; the client predicts with the same rules.
const BagMoves = {
	MAX_MOVES = MAX_MOVES,
	BACKPACK = "Backpack",
	STORAGE = "Storage",
}

function BagMoves.HutRef(buildingId: string): string
	return `Hut/{buildingId}`
end

function BagMoves.ColonistRef(colonistId: number): string
	return `Colonist/{colonistId}`
end

-- "Hut/BuilderHut" -> "Hut", "BuilderHut"; "Backpack" -> "Backpack", nil
function BagMoves.ParseRef(ref: string): (string, string?)
	local kind, id = string.match(ref, "^(%a+)/(.+)$")
	if kind and id then
		return kind, id
	end
	return ref, nil
end

function BagMoves.GetSlotsCount(bag: Bag): number
	local itemType = ItemsList.GetItemName(bag.UniqueID)
	return if itemType then BagSizes[itemType] or 0 else 0
end

function BagMoves.GetStack(bag: Bag, slot: number): ItemStack?
	for _, stack in bag.Items do
		if stack.Slot == slot then
			return stack
		end
	end
	return nil
end

-- Copy whose stacks can be changed without touching the original
function BagMoves.Clone(bag: Bag): Bag
	local items = {}
	for _, stack in bag.Items do
		table.insert(items, table.clone(stack))
	end
	return { UniqueID = bag.UniqueID, Items = items, Metadata = bag.Metadata }
end

local function isCount(value: unknown): boolean
	return typeof(value) == "number" and value >= 1 and value <= 2 ^ 31 and value % 1 == 0
end

-- Checks the shape of a move that came over the network
function BagMoves.IsMove(value: unknown): boolean
	if typeof(value) ~= "table" then
		return false
	end
	local move = value :: { [any]: any }
	return typeof(move.From) == "string"
		and typeof(move.To) == "string"
		and #move.From <= 64
		and #move.To <= 64
		and isCount(move.FromSlot)
		and isCount(move.ToSlot)
		and isCount(move.Count)
end

local function take(bag: Bag, stack: ItemStack)
	local index = table.find(bag.Items, stack)
	if index then
		table.remove(bag.Items, index)
	end
end

-- Moves `count` items from one slot to another, which may be in another bag:
-- into an empty slot, onto the same item (up to its MaxStack), or swapping with a
-- different item when the whole stack moves. Changes nothing when it fails.
function BagMoves.Move(
	from: Bag,
	fromSlot: number,
	to: Bag,
	toSlot: number,
	count: number
): (boolean, string)
	if fromSlot > BagMoves.GetSlotsCount(from) or toSlot > BagMoves.GetSlotsCount(to) then
		return false, "Invalid slot"
	end
	if rawequal(from, to) and fromSlot == toSlot then
		return false, "Same slot"
	end

	local source = BagMoves.GetStack(from, fromSlot)
	if not source then
		return false, "Nothing to move"
	end
	if count > source.Quantity then
		return false, "Not enough items"
	end

	local maxStack = ItemsList.GetMaxStack(source.UniqueID)
	local target = BagMoves.GetStack(to, toSlot)

	if not target then
		if count > maxStack then
			return false, "Too many for one slot"
		end
		if count == source.Quantity then
			take(from, source)
			source.Slot = toSlot
			table.insert(to.Items, source)
		else
			source.Quantity -= count
			table.insert(to.Items, { UniqueID = source.UniqueID, Quantity = count, Slot = toSlot })
		end
		return true, ""
	end

	if target.UniqueID == source.UniqueID then
		if target.Quantity + count > maxStack then
			return false, "That stack is full"
		end
		target.Quantity += count
		source.Quantity -= count
		if source.Quantity == 0 then
			take(from, source)
		end
		return true, ""
	end

	-- Different items trade places, so only a whole stack can swap
	if count ~= source.Quantity then
		return false, "Pick up the whole stack to swap"
	end
	take(from, source)
	take(to, target)
	source.Slot = toSlot
	target.Slot = fromSlot
	table.insert(to.Items, source)
	table.insert(from.Items, target)
	return true, ""
end

return BagMoves
