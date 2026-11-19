--!strict

const BuildingTypes = require(script.Parent.Parent.Buildings.BuildingTypes)
const ColonistTypes = require(script.Parent.Parent.Colonist.ColonistTypes)
const FarmData = require(script.Parent.Parent.Farm.FarmData)
const InventoryTypes = require(script.Parent.Parent.Inventory.InventoryTypes)
const YardData = require(script.Parent.Parent.Yard.YardData)

type BuildingId = BuildingTypes.BuildingId

-- Plot-local position of a building's base centre; Rotation is in quarter turns (0-3)
export type Placement = {
	X: number,
	Z: number,
	Rotation: number,
}

export type SavedBuilding = {
	Id: BuildingId,
	Level: number,
	-- nil until the player places it
	Placement: Placement?,
}

-- One line in the colony's event log
export type ColonyEvent = {
	-- workspace:GetServerTimeNow() when it happened
	Time: number,
	Text: string,
}

-- A job for the Builder: raise a new building (TargetLevel 1) or upgrade one, part by part
export type WorkOrder = {
	Id: number,
	Kind: "Build" | "Upgrade",
	BuildingId: BuildingId,
	TargetLevel: number,
	-- Blueprint parts placed so far (BuildingBlueprint order)
	Progress: number,
	-- Parts in the target level's blueprint
	TotalParts: number,
	-- Colonist id of the Builder working on it
	BuilderId: number?,
}

-- The travelling merchant's schedule, in server times (workspace:GetServerTimeNow())
export type MerchantVisit = {
	-- When the merchant next arrives; 0 until the Town Hall is placed
	NextArrival: number,
	-- When the current visit ends; 0 while he's away
	LeavesAt: number,
}

-- Items attached to a letter (any quantity; split into stacks when collected)
export type MailItem = {
	UniqueID: number,
	Quantity: number,
}

-- A letter in the Town Hall mailbox: developer gifts/messages, or items that had nowhere
-- else to go (full backpack, a departed colonist's belongings, glitched stacks)
export type Mail = {
	Id: number,
	-- workspace:GetServerTimeNow() when it arrived
	Time: number,
	From: string,
	Title: string?,
	Body: string?,
	-- Items still waiting to be collected; empty for text-only letters
	Items: { MailItem },
	Read: boolean,
}

-- When raiders next come (RaidController). A raid in progress isn't saved, only what its
-- raiders carry, so the items can be given back if the raid is cut short.
export type RaidSchedule = {
	-- DayCycle day whose night the next raid comes on; 0 until the colony can be raided
	NextDay: number,
	-- DayCycle day the colony was last loaded on (days spent away don't bring a raid closer)
	SeenDay: number,
	-- Stacks raiders took from the storage and haven't escaped with yet
	Carried: { MailItem },
}

-- Saved per player with ProfileStore
export type ColonyData = {
	-- nil until the player names their colony
	Name: string?,
	-- Newest last, capped in length
	Events: { ColonyEvent },
	WorkOrders: { WorkOrder },
	NextWorkOrderId: number,
	Buildings: { SavedBuilding },
	-- The player's bags; Bags[1] is the backpack
	Inventory: InventoryTypes.Inventory,
	-- Colony storage, deposited into at the Town Hall or Warehouse (at the Spire until the
	-- Town Hall is built)
	Storage: InventoryTypes.Bag,
	-- Storage owned by worker buildings (WorkerStorage component), by building id
	HutStorage: { [string]: InventoryTypes.Bag },
	-- Crop fields of buildings with a Field component, by building id; index = wedge (1-6)
	Fields: { [string]: { FarmData.Plot } },
	-- Resource nodes of buildings with a Yard component, by building id; index = node (YardData)
	Yards: { [string]: { YardData.Node } },
	Colonists: { ColonistTypes.Colonist },
	-- Dead or departed colonists, kept for family trees
	Departed: { ColonistTypes.DepartedColonist },
	NextColonistId: number,
	-- 0-100 chance a colonist falls sick each morning
	Disease: number,
	-- DayCycle day the daily rolls (debuffs, births...) last ran
	LastDay: number,
	Merchant: MerchantVisit,
	-- Town Hall mailbox, oldest first; no capacity limit
	Mail: { Mail },
	NextMailId: number,
	-- Raid schedule; nil in saves from before raids (RaidController fills it in)
	Raid: RaidSchedule?,
	-- Save format version (ColonyController's migrate); nil in saves from before versioning
	Version: number?,
}

return 0
