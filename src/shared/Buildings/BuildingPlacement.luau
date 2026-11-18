--!strict

const ColonyTypes = require(script.Parent.Parent.Colony.ColonyTypes)
const PlotData = require(script.Parent.Parent.Plot.PlotData)

type Placement = ColonyTypes.Placement

const GRID_SIZE = 4

const BuildingPlacement = {}

BuildingPlacement.GRID_SIZE = GRID_SIZE

local function snap(value: number): number
	return math.round(value / GRID_SIZE) * GRID_SIZE
end

-- Largest grid position that keeps half of `size` inside half of `plotSize`
local function limit(plotSize: number, size: number): number
	return math.max(math.floor((plotSize - size) / 2 / GRID_SIZE) * GRID_SIZE, 0)
end

-- X/Z size after turning `rotation` quarter turns
local function getRotatedSize(footprint: Vector2, rotation: number): Vector2
	return if rotation % 2 == 1 then Vector2.new(footprint.Y, footprint.X) else footprint
end

-- Snaps a plot-local X/Z to the grid and keeps the footprint inside the plot.
-- Shared by the client ghost and the server so both agree on the result.
function BuildingPlacement.Resolve(
	plotSize: number,
	footprint: Vector2,
	x: number,
	z: number,
	rotation: number
): Placement
	local quarterTurns = math.floor(rotation) % 4
	local size = getRotatedSize(footprint, quarterTurns)
	local maxX = limit(plotSize, size.X)
	local maxZ = limit(plotSize, size.Y)

	return {
		X = math.clamp(snap(x), -maxX, maxX),
		Z = math.clamp(snap(z), -maxZ, maxZ),
		Rotation = quarterTurns,
	}
end

-- True when two placed footprints overlap on the plot
function BuildingPlacement.Overlaps(a: Placement, aFootprint: Vector2, b: Placement, bFootprint: Vector2): boolean
	local aSize = getRotatedSize(aFootprint, a.Rotation)
	local bSize = getRotatedSize(bFootprint, b.Rotation)

	return math.abs(a.X - b.X) < (aSize.X + bSize.X) / 2 and math.abs(a.Z - b.Z) < (aSize.Y + bSize.Y) / 2
end

-- Placement of a world CFrame on the plot
function BuildingPlacement.FromCFrame(cframe: CFrame): Placement
	local offset = PlotData.SURFACE:ToObjectSpace(cframe)
	local _, yaw = offset:ToEulerAnglesYXZ()

	return {
		X = offset.X,
		Z = offset.Z,
		Rotation = math.round(yaw / (math.pi / 2)) % 4,
	}
end

-- World CFrame for a building's base centre
function BuildingPlacement.ToCFrame(placement: Placement): CFrame
	return PlotData.SURFACE
		* CFrame.new(placement.X, 0, placement.Z)
		* CFrame.Angles(0, placement.Rotation * math.pi / 2, 0)
end

return BuildingPlacement
