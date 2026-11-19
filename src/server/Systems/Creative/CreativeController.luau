--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared
const Packages = ReplicatedStorage.Packages
const Systems = script.Parent.Parent

const Net = require(Packages.Net)
const Creative = require(Shared.Dev.Creative)
const DevAccess = require(Shared.Dev.DevAccess)
const ItemsList = require(Shared.Inventory.ItemsList)
const ColonyController = require(Systems.Colony.ColonyController)
const Bag = require(Systems.Inventory.Components.Bag)
const InventoryController = require(Systems.Inventory.InventoryController)

-- Dev-only Creative menu: the `creative` Cmdr command toggles it on the tester's client,
-- and CreativeSpawn puts any item into their backpack (Bags[1])
const CreativeController = {}

local started = false

-- Re-checks permission, validates the request, then fills the backpack.
-- Returns how many were spawned and a message for the menu.
local function onSpawn(player: Player, itemId: unknown, amount: unknown): (number, string)
	if not DevAccess.IsTester(player) then
		return 0, "You don't have permission to use the Creative menu."
	end
	if typeof(itemId) ~= "number" then
		return 0, "Unknown item"
	end
	local id = itemId :: number
	local name = ItemsList.GetDisplayName(id)
	if not name then
		return 0, "Unknown item"
	end
	if not Creative.IsValidAmount(amount) then
		return 0,
			`Amount must be a whole number from {Creative.MIN_AMOUNT} to {Creative.MAX_AMOUNT}`
	end

	local data = ColonyController.GetData(player)
	if not data then
		return 0, "Colony not loaded yet"
	end
	local backpack = InventoryController.GetBackpack(data)
	if not backpack then
		return 0, "No backpack"
	end

	local count = amount :: number
	local left = Bag.AddItem(backpack, id, count)
	local given = count - left
	if given == 0 then
		return 0, "Your backpack is full"
	end
	ColonyController.Sync(player)
	return given, `Spawned {given} {name}` .. (if left > 0 then ` ({left} didn't fit)` else "")
end

-- Opens or closes the menu on the player's client (only for testers)
function CreativeController.Toggle(player: Player): boolean
	if not DevAccess.IsTester(player) then
		return false
	end
	Net:RemoteEvent(Creative.TOGGLE_REMOTE):FireClient(player)
	return true
end

function CreativeController.Start()
	if started then
		return
	end
	started = true

	-- Created up front so the client finds it when it connects
	Net:RemoteEvent(Creative.TOGGLE_REMOTE)
	Net:Handle(Creative.SPAWN_REMOTE, onSpawn)
end

return CreativeController
