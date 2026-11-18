--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const ItemsList = require(ReplicatedStorage.Shared.Inventory.ItemsList)

-- "item": any ItemType from ItemsList, autocompleted
return function(registry: any)
	registry:RegisterType("item", registry.Cmdr.Util.MakeEnumType("Item", ItemsList.GetItemTypes()))
end
