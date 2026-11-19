--!strict

export type BuildingId =
	"AlchemistLaboratory"
	| "Apiary"
	| "Archery"
	| "Bakery"
	| "Barracks"
	| "BarracksTower"
	| "BlacksmithHut"
	| "BrickYard"
	| "BuilderHut"
	| "ChefKitchen"
	| "ChickenFarmerHut"
	| "CombatAcademy"
	| "ComposterHut"
	| "ConcreteMixerHut"
	| "CourierHut"
	| "CowhandHut"
	| "CrusherHut"
	| "DiningHall"
	| "DyerHut"
	| "EnchanterTower"
	| "FarmerHut"
	| "FisherHut"
	| "FletcherHut"
	| "Flowershop"
	| "ForesterHut"
	| "Gatehouse"
	| "GlassblowerHut"
	| "Graveyard"
	| "GuardTower"
	| "Hospital"
	| "Library"
	| "MechanicHut"
	| "Mine"
	| "MysticalSite"
	| "NetherMine"
	| "Plantation"
	| "Quarry"
	| "RabbitHutch"
	| "Residence"
	| "Sawmill"
	| "School"
	| "ShepherdHut"
	| "SifterHut"
	| "Smeltery"
	| "Spire"
	| "Stable"
	| "StonemasonHut"
	| "SwineherdHut"
	| "Tavern"
	| "TownHall"
	| "University"
	| "Warehouse"

-- Townspeople jobs that work at this building
export type WorkplaceComponent = {
	Jobs: { string },
}

-- Players can deposit carried resources here
export type StorageComponent = {}

-- Teleports its owner to the wilds
export type TeleporterComponent = {}

-- Colonists can live here; beds = Capacity + CapacityPerLevel * level, or CapacityByLevel[level]
-- when set (levels past its end use the last entry)
export type HousingComponent = {
	Capacity: number,
	CapacityPerLevel: number?,
	CapacityByLevel: { number }?,
}

-- The building's own storage (e.g. Builder's Hut materials); the player delivers into it
export type WorkerStorageComponent = {
	-- Bag item type from ItemsList (its size comes from BagSizes)
	BagItem: string,
}

-- A crop field around the building (FarmData geometry: 6 wedges unlocked by level); its Farmer
-- plants and harvests it. Only the hut in the middle blocks colonists, the field is walkable.
export type FieldComponent = {}

-- A yard of resource nodes around the building (YardData: trees, rocks...; more nodes per
-- level) that its worker harvests and that grow back. Only the hut in the middle blocks colonists.
export type YardComponent = {
	-- Yard kind from YardData.YARDS
	Kind: string,
}

-- A building is composed of the components it has; absent components are nil
export type BuildingComponents = {
	Workplace: WorkplaceComponent?,
	Storage: StorageComponent?,
	Teleporter: TeleporterComponent?,
	Housing: HousingComponent?,
	WorkerStorage: WorkerStorageComponent?,
	Field: FieldComponent?,
	Yard: YardComponent?,
}

export type BuildingInfo = {
	Id: BuildingId,
	Name: string,
	Description: string,
	-- Town Hall level required before this building can be built
	UnlockLevel: number,
	Components: BuildingComponents,
}

return 0
