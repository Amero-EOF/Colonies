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

-- A building is composed of the components it has; absent components are nil
export type BuildingComponents = {
	Workplace: WorkplaceComponent?,
}

export type BuildingInfo = {
	Id: BuildingId,
	Name: string,
	Description: string,
	Components: BuildingComponents,
}

return 0
