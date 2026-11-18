--!strict

-- Every player's plot sits at the same spot and is only rendered on the owner's client
const SURFACE = CFrame.new(0, 1, 0)
const THICKNESS = 1
const BASE_SIZE = 384
const GROWTH_PER_LEVEL = 128

-- Side length of the square plot for a Town Hall level
local function getSize(townHallLevel: number): number
	return BASE_SIZE + math.max(townHallLevel, 0) * GROWTH_PER_LEVEL
end

local function isInside(position: Vector3, townHallLevel: number): boolean
	local offset = SURFACE:PointToObjectSpace(position)
	local half = getSize(townHallLevel) / 2
	return math.abs(offset.X) <= half and math.abs(offset.Z) <= half
end

return {
	-- Top centre of the plot
	SURFACE = SURFACE,
	THICKNESS = THICKNESS,
	GetSize = getSize,
	IsInside = isInside,
}
