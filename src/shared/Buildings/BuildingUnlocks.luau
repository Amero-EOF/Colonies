--!strict

const BuildingData = require(script.Parent.BuildingData)
const BuildingTypes = require(script.Parent.BuildingTypes)
const ColonyTypes = require(script.Parent.Parent.Colony.ColonyTypes)

type BuildingId = BuildingTypes.BuildingId
type SavedBuilding = ColonyTypes.SavedBuilding

const BuildingUnlocks = {}

-- The Town Hall goes from 1 to 5 (level 0 is its construction site)
BuildingUnlocks.MAX_LEVEL = 5
-- Every other building goes from 1 to 6
BuildingUnlocks.BUILDING_MAX_LEVEL = 6

-- A colony starts with only the Builder's Hut unlocked. The Town Hall unlocks once the
-- Builder's Hut is built; everything else unlocks by Town Hall level.
function BuildingUnlocks.IsUnlocked(
	id: BuildingId,
	townHallLevel: number,
	builderHutLevel: number
): boolean
	if id == "TownHall" then
		return builderHutLevel >= 1
	end
	return BuildingData[id].UnlockLevel <= townHallLevel
end

-- Why a building can't be placed yet (for menus)
function BuildingUnlocks.GetLockReason(id: BuildingId): string
	if id == "TownHall" then
		return "Needs a built Builder's Hut"
	end
	return `Needs Town Hall level {BuildingData[id].UnlockLevel}`
end

-- Level 0 is a construction site (the Town Hall too)
function BuildingUnlocks.IsBuilt(_id: BuildingId, level: number): boolean
	return level >= 1
end

-- Beds a building offers at `level` (0 for buildings that don't house colonists or aren't built)
function BuildingUnlocks.GetBeds(id: BuildingId, level: number): number
	local housing = BuildingData[id].Components.Housing
	if not housing or not BuildingUnlocks.IsBuilt(id, level) then
		return 0
	end
	local byLevel = housing.CapacityByLevel
	if byLevel and #byLevel > 0 then
		return byLevel[math.min(level, #byLevel)]
	end
	return housing.Capacity + (housing.CapacityPerLevel or 0) * level
end

-- Saved level of a building; 0 when it isn't placed yet or is a construction site
function BuildingUnlocks.GetLevel(buildings: { SavedBuilding }, id: BuildingId): number
	for _, saved in buildings do
		if saved.Id == id then
			return saved.Level
		end
	end
	return 0
end

-- True once the Town Hall is placed and built
function BuildingUnlocks.IsTownHallBuilt(buildings: { SavedBuilding }): boolean
	for _, saved in buildings do
		if saved.Id == "TownHall" then
			return saved.Placement ~= nil and BuildingUnlocks.IsBuilt(saved.Id, saved.Level)
		end
	end
	return false
end

-- Where colony life gathers: the Town Hall once it's built, the Spire before that (colonists
-- eat and sleep around it; colony storage and the mailbox are reached there)
function BuildingUnlocks.GetHubId(buildings: { SavedBuilding }): BuildingId
	return if BuildingUnlocks.IsTownHallBuilt(buildings) then "TownHall" else "Spire"
end

-- Whether the player reaches colony storage at this building: built Storage buildings (Town
-- Hall, Warehouse), and the Spire until the Town Hall is built
function BuildingUnlocks.IsStorageSpot(saved: SavedBuilding, townHallBuilt: boolean): boolean
	if BuildingData[saved.Id].Components.Storage then
		return BuildingUnlocks.IsBuilt(saved.Id, saved.Level)
	end
	return saved.Id == "Spire" and not townHallBuilt
end

-- Other buildings can be one level above the Town Hall (so the Builder's Hut reaches level 1
-- while the Town Hall is still unbuilt)
function BuildingUnlocks.GetMaxLevel(id: BuildingId, townHallLevel: number): number
	if id == "TownHall" then
		return BuildingUnlocks.MAX_LEVEL
	end

	return math.min(townHallLevel + 1, BuildingUnlocks.BUILDING_MAX_LEVEL)
end

-- Whether a building can go up one level, and the reason shown to the player if not.
-- The Town Hall needs a Builder's Hut of the level it is upgrading to.
function BuildingUnlocks.CanUpgrade(
	id: BuildingId,
	level: number,
	townHallLevel: number,
	builderHutLevel: number
): (boolean, string)
	if BuildingData[id].Components.Teleporter then
		return false, "Follows the Town Hall"
	end

	local maxLevel = BuildingUnlocks.GetMaxLevel(id, townHallLevel)
	if level >= maxLevel then
		if id == "TownHall" or level >= BuildingUnlocks.BUILDING_MAX_LEVEL then
			return false, "Max level"
		end
		return false, `Needs Town Hall level {level}`
	end

	if id == "TownHall" and builderHutLevel < level + 1 then
		return false, `Needs Builder's Hut level {level + 1}`
	end

	return true, `Upgrade to level {level + 1}`
end

return BuildingUnlocks
