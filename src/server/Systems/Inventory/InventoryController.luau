--!strict
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared
const Packages = ReplicatedStorage.Packages

const Net = require(Packages.Net)
const BagMoves = require(Shared.Inventory.BagMoves)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const InventoryTypes = require(Shared.Inventory.InventoryTypes)
const ItemsList = require(Shared.Inventory.ItemsList)
const Bag = require(script.Parent.Components.Bag)

type ColonyData = ColonyTypes.ColonyData
type BagData = InventoryTypes.Bag
type ItemStack = InventoryTypes.ItemStack
type Move = BagMoves.Move

-- How one kind of bag ref ("Backpack", "Hut", "Colonist"...) is found for a player.
-- Resolve returns the bag only when the player may touch it right now (e.g. stands close
-- enough), otherwise nil and the reason. Sync re-sends that bag's state to the player.
export type BagAccess = {
	Resolve: (player: Player, id: string?) -> (BagData?, string),
	Sync: (player: Player) -> (),
}

const InventoryController = {}

const accessByKind: { [string]: BagAccess } = {}
local started = false

-- The player's 10-slot bag
function InventoryController.GetBackpack(data: ColonyData): BagData?
	return data.Inventory.Bags[1]
end

-- Moves everything in the backpack that fits into colony storage; returns how many items moved.
-- Held tools (Work Scroll, shovel...) stay in the backpack.
function InventoryController.Deposit(data: ColonyData): number
	local backpack = InventoryController.GetBackpack(data)
	return if backpack then Bag.TransferAll(backpack, data.Storage, ItemsList.IsHoldable) else 0
end

-- Lets MoveItems reach a kind of bag; the systems that own the bags register themselves
function InventoryController.RegisterBag(kind: string, access: BagAccess)
	accessByKind[kind] = access
end

local function snapshot(bag: BagData): { ItemStack }
	local items = {}
	for _, stack in bag.Items do
		table.insert(items, table.clone(stack))
	end
	return items
end

-- Puts a bag back as it was, keeping the same Items table other code may hold
local function restore(bag: BagData, items: { ItemStack })
	table.clear(bag.Items)
	for _, stack in items do
		table.insert(bag.Items, stack)
	end
end

-- Applies a list of slot moves for the player, all or nothing, then re-sends the bags
local function onMoveItems(player: Player, moves: unknown): (boolean, string)
	if typeof(moves) ~= "table" then
		return false, "Invalid move"
	end
	local list = moves :: { unknown }
	if #list == 0 or #list > BagMoves.MAX_MOVES then
		return false, "Invalid move"
	end

	local bags: { [string]: BagData } = {}
	local syncs: { [BagAccess]: boolean } = {}
	local valid: { Move } = {}
	local problem: string? = nil

	for _, value in list do
		if not BagMoves.IsMove(value) then
			return false, "Invalid move"
		end
		local move = value :: Move
		table.insert(valid, move)

		for _, ref in { move.From, move.To } do
			if bags[ref] then
				continue
			end
			local kind, id = BagMoves.ParseRef(ref)
			local access = accessByKind[kind]
			if not access then
				return false, "Unknown bag"
			end
			syncs[access] = true
			local bag, reason = access.Resolve(player, id)
			if not bag then
				problem = problem or reason
				continue
			end
			bags[ref] = bag
		end
	end

	local function syncAll()
		for access in syncs do
			access.Sync(player)
		end
	end

	if problem then
		syncAll()
		return false, problem
	end

	local saved: { [BagData]: { ItemStack } } = {}
	for _, bag in bags do
		saved[bag] = saved[bag] or snapshot(bag)
	end

	for _, move in valid do
		local ok, reason =
			BagMoves.Move(bags[move.From], move.FromSlot, bags[move.To], move.ToSlot, move.Count)
		if not ok then
			for bag, items in saved do
				restore(bag, items)
			end
			syncAll()
			return false, reason
		end
	end

	syncAll()
	return true, ""
end

function InventoryController.Start()
	if started then
		return
	end
	started = true

	Net:Handle("MoveItems", onMoveItems)
end

return InventoryController
