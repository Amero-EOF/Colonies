--!strict

const BuildingData = require(script.Parent.BuildingData)
const BuildingTypes = require(script.Parent.BuildingTypes)

type BuildingId = BuildingTypes.BuildingId

const BuildingUnlocks = {}

-- The Town Hall goes from Tier 0 to 5
BuildingUnlocks.MAX_LEVEL = 5
-- Every other building goes from 1 to 6
BuildingUnlocks.BUILDING_MAX_LEVEL = 6

function BuildingUnlocks.IsUnlocked(id: BuildingId, townHallLevel: number): boolean
	return BuildingData[id].UnlockLevel <= townHallLevel
end

-- Level 0 is a construction site, except the Town Hall, which starts built at Tier 0
function BuildingUnlocks.IsBuilt(id: BuildingId, level: number): boolean
	return level >= 1 or id == "TownHall"
end

-- Other buildings can be one level above the Town Hall
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
