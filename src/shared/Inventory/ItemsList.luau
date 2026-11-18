--!strict
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared
const Packages = ReplicatedStorage.Packages

const InventoryTypes = require(Shared.Inventory.InventoryTypes)
const TableUtil = require(Packages.TableUtil)

type Item = InventoryTypes.Item
type ItemMetadata = InventoryTypes.ItemMetadata

const MAX_STACK = 64

-- for unique items like skins, you could add the differences to the metadata
const items: { Item } = {
	{
		UniqueID = 1,
		ItemType = "Backpack",
		Metadata = { isBag = true },
		Stackable = false,
		MaxStack = 1,
		Category = { "Bag" },
	},
	{
		UniqueID = 2,
		ItemType = "TownHallStorage",
		Metadata = { isBag = true },
		Stackable = false,
		MaxStack = 1,
		Category = { "Bag" },
	},
	{
		UniqueID = 3,
		ItemType = "Wood",
		Metadata = {},
		Stackable = true,
		MaxStack = MAX_STACK,
		Category = "Resource",
	},
	{
		UniqueID = 4,
		ItemType = "Stone",
		Metadata = {},
		Stackable = true,
		MaxStack = MAX_STACK,
		Category = "Resource",
	},
	{
		UniqueID = 5,
		ItemType = "Ore",
		Metadata = {},
		Stackable = true,
		MaxStack = MAX_STACK,
		Category = "Resource",
	},
	{
		UniqueID = 6,
		ItemType = "Food",
		Metadata = {},
		Stackable = true,
		MaxStack = MAX_STACK,
		Category = "Resource",
	},
	-- A colonist's 5-slot inventory
	{
		UniqueID = 7,
		ItemType = "ColonistPack",
		Metadata = { isBag = true },
		Stackable = false,
		MaxStack = 1,
		Category = { "Bag" },
	},
	{
		UniqueID = 8,
		ItemType = "BuilderHutStorage",
		Metadata = { isBag = true },
		Stackable = false,
		MaxStack = 1,
		Category = { "Bag" },
	},
	-- Sold by the travelling merchant; held from the hotbar
	{
		UniqueID = 9,
		ItemType = "LandscapingShovel",
		Metadata = { DisplayName = "Landscaping Shovel", Holdable = true },
		Stackable = false,
		MaxStack = 1,
		Category = "Tool",
	},
	{
		UniqueID = 10,
		ItemType = "WorkScroll",
		Metadata = { DisplayName = "Work Scroll", Holdable = true },
		Stackable = false,
		MaxStack = 1,
		Category = "Tool",
	},
	-- Building material from Tier 3 up
	{
		UniqueID = 11,
		ItemType = "BakedClay",
		Metadata = { DisplayName = "Baked Clay" },
		Stackable = true,
		MaxStack = MAX_STACK,
		Category = "Resource",
	},
	-- Seeds handed to the Farmer (or put in his hut) to plant a crop (FarmData.CROPS)
	{
		UniqueID = 12,
		ItemType = "WheatSeeds",
		Metadata = { DisplayName = "Wheat Seeds" },
		Stackable = true,
		MaxStack = MAX_STACK,
		Category = "Seed",
	},
	{
		UniqueID = 13,
		ItemType = "CarrotSeeds",
		Metadata = { DisplayName = "Carrot Seeds" },
		Stackable = true,
		MaxStack = MAX_STACK,
		Category = "Seed",
	},
	{
		UniqueID = 14,
		ItemType = "PotatoSeeds",
		Metadata = { DisplayName = "Potato Seeds" },
		Stackable = true,
		MaxStack = MAX_STACK,
		Category = "Seed",
	},
	-- Crops the Farmer harvests; Carrot and Potato are also eaten like Food
	{
		UniqueID = 15,
		ItemType = "Wheat",
		Metadata = {},
		Stackable = true,
		MaxStack = MAX_STACK,
		Category = "Crop",
	},
	{
		UniqueID = 16,
		ItemType = "Carrot",
		Metadata = { Edible = true },
		Stackable = true,
		MaxStack = MAX_STACK,
		Category = "Crop",
	},
	{
		UniqueID = 17,
		ItemType = "Potato",
		Metadata = { Edible = true },
		Stackable = true,
		MaxStack = MAX_STACK,
		Category = "Crop",
	},
	{
		UniqueID = 18,
		ItemType = "FarmerHutStorage",
		Metadata = { isBag = true },
		Stackable = false,
		MaxStack = 1,
		Category = { "Bag" },
	},
}

local function find(uniqueID: number): Item?
	for _, item in items do
		if item.UniqueID == uniqueID then
			return item
		end
	end
	return nil
end

local function findByType(itemType: string): Item?
	for _, item in items do
		if item.ItemType == itemType then
			return item
		end
	end
	return nil
end

-- Returns a copy (deep when deepCopy is true) so callers can't edit the list
local function copy(item: Item?, deepCopy: boolean?): Item?
	if not item then
		return nil
	end
	return TableUtil.Copy(item, deepCopy)
end

return {
	MAX_STACK = MAX_STACK,

	GetItemByUniqueID = function(uniqueID: number, deepCopy: boolean?): Item?
		return copy(find(uniqueID), deepCopy)
	end,

	GetItemName = function(uniqueID: number): string?
		local item = find(uniqueID)
		return item and item.ItemType
	end,

	-- Every ItemType, in list order
	GetItemTypes = function(): { string }
		local types = {}
		for _, item in items do
			table.insert(types, item.ItemType)
		end
		return types
	end,

	GetItemId = function(itemType: string): number?
		local item = findByType(itemType)
		return item and item.UniqueID
	end,

	GetItemByItemType = function(itemType: string, deepCopy: boolean?): Item?
		return copy(findByType(itemType), deepCopy)
	end,

	-- Most of an item one slot holds (1 for unknown or non-stackable items)
	GetMaxStack = function(uniqueID: number): number
		local item = find(uniqueID)
		return if item and item.Stackable then item.MaxStack else 1
	end,

	isStackable = function(uniqueID: number): boolean
		local item = find(uniqueID)
		return item ~= nil and item.Stackable
	end,

	GetMetadata = function(uniqueID: number): ItemMetadata
		local item = find(uniqueID)
		return if item then item.Metadata else {}
	end,

	-- Name to show players (DisplayName, falling back to ItemType)
	GetDisplayName = function(uniqueID: number): string?
		local item = find(uniqueID)
		return item and (item.Metadata.DisplayName or item.ItemType)
	end,

	-- Items held from the hotbar as Roblox Tools (they stay in the backpack when depositing)
	IsHoldable = function(uniqueID: number): boolean
		local item = find(uniqueID)
		return item ~= nil and item.Metadata.Holdable == true
	end,

	-- Items colonists eat when hungry: Food first, then anything Edible, in list order
	GetFoodIds = function(): { number }
		local ids = {}
		for _, item in items do
			if item.ItemType == "Food" then
				table.insert(ids, 1, item.UniqueID)
			elseif item.Metadata.Edible then
				table.insert(ids, item.UniqueID)
			end
		end
		return ids
	end,
}
