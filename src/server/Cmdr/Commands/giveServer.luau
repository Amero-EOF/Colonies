--!strict

const ServerScriptService = game:GetService("ServerScriptService")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Systems = ServerScriptService.Server.Systems

const ItemsList = require(ReplicatedStorage.Shared.Inventory.ItemsList)
const ColonyController = require(Systems.Colony.ColonyController)
const Bag = require(Systems.Inventory.Components.Bag)
const InventoryController = require(Systems.Inventory.InventoryController)

-- Fills the backpack first (or storage), then the other; reports what didn't fit
return function(
	context: any,
	itemType: string,
	quantity: number?,
	players: { Player }?,
	target: string?
): string
	local itemId = ItemsList.GetItemId(itemType)
	local amount = math.max(quantity or 1, 1)
	if not itemId then
		return `Unknown item {itemType}`
	end

	local lines = {}
	local targets: { Player } = players or { context.Executor }
	for _, player in targets do
		local data = ColonyController.GetData(player)
		if not data then
			table.insert(lines, `{player.Name}: colony not loaded`)
			continue
		end
		local backpack = InventoryController.GetBackpack(data)
		local bags: { any } = if target == "storage"
			then { data.Storage, backpack }
			else { backpack, data.Storage }
		local left = amount
		for _, bag in bags do
			if bag and left > 0 then
				left = Bag.AddItem(bag, itemId, left)
			end
		end
		ColonyController.Sync(player)
		local given = amount - left
		table.insert(
			lines,
			`{player.Name}: gave {given} {itemType}`
				.. (if left > 0 then ` ({left} didn't fit)` else "")
		)
	end
	return table.concat(lines, "\n")
end
