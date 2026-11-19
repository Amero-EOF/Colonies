--!strict

export type ItemMetadata = {
	isBag: boolean?,
	-- Shown instead of ItemType when set (e.g. "Work Scroll")
	DisplayName: string?,
	-- Owning one puts a Roblox Tool in the player's hotbar (ToolController.SyncItems)
	Holdable: boolean?,
	-- Colonists eat it like Food (e.g. Carrot, Potato)
	Edible: boolean?,
	-- Damage per swing against raiders while held (weapons)
	Damage: number?,
}

export type BagMetadata = {
	Alias: string?,
}

-- An entry in ItemsList
export type Item = {
	UniqueID: number,
	ItemType: string,
	Stackable: boolean,
	-- Most of this item one slot holds
	MaxStack: number,
	Category: string | { string },
	Metadata: ItemMetadata,
}

-- One occupied bag slot; plain data so it saves as-is
export type ItemStack = {
	UniqueID: number,
	Quantity: number,
	Slot: number,
}

-- Slot count comes from BagSizes by the bag item's ItemType
export type Bag = {
	UniqueID: number,
	Items: { ItemStack },
	Metadata: BagMetadata,
}

export type Inventory = {
	Bags: { Bag },
}

return 0
