--!strict

const BuildingData = require(script.Parent.BuildingData)
const BuildingModels = require(script.Parent.BuildingModels)
const BuildingTypes = require(script.Parent.BuildingTypes)
const ColonyTypes = require(script.Parent.Parent.Colony.ColonyTypes)
const PlotData = require(script.Parent.Parent.Plot.PlotData)

type BuildingId = BuildingTypes.BuildingId
type Placement = ColonyTypes.Placement
type SavedBuilding = ColonyTypes.SavedBuilding
type WorkOrder = ColonyTypes.WorkOrder

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

-- `offset` (building-local) turned by `rotation` quarter turns, in plot space
local function rotateOffset(offset: Vector3, rotation: number): Vector3
	return CFrame.Angles(0, rotation * math.pi / 2, 0):VectorToWorldSpace(offset)
end

-- Grid position range that keeps a box of `size`, centred `offset` away, inside the plot
local function clampAxis(value: number, plotSize: number, size: number, offset: number): number
	if offset == 0 then
		local max = limit(plotSize, size)
		return math.clamp(value, -max, max)
	end
	local half = (plotSize - size) / 2
	local low = math.ceil((-half - offset) / GRID_SIZE - 1e-6) * GRID_SIZE
	local high = math.floor((half - offset) / GRID_SIZE + 1e-6) * GRID_SIZE
	if low > high then
		return 0
	end
	return math.clamp(value, low, high)
end

-- Snaps a plot-local X/Z to the grid and keeps the footprint inside the plot. `centre` is
-- where the footprint's centre sits relative to the base centre (see GetReach).
-- Shared by the client ghost and the server so both agree on the result.
function BuildingPlacement.Resolve(
	plotSize: number,
	footprint: Vector2,
	x: number,
	z: number,
	rotation: number,
	centre: Vector3?
): Placement
	local quarterTurns = math.floor(rotation) % 4
	local size = getRotatedSize(footprint, quarterTurns)
	local offset = rotateOffset(centre or Vector3.zero, quarterTurns)

	return {
		X = clampAxis(snap(x), plotSize, size.X, offset.X),
		Z = clampAxis(snap(z), plotSize, size.Y, offset.Z),
		Rotation = quarterTurns,
	}
end

-- True when two placed footprints overlap on the plot
function BuildingPlacement.Overlaps(
	a: Placement,
	aFootprint: Vector2,
	b: Placement,
	bFootprint: Vector2
): boolean
	local aSize = getRotatedSize(aFootprint, a.Rotation)
	local bSize = getRotatedSize(bFootprint, b.Rotation)

	return math.abs(a.X - b.X) < (aSize.X + bSize.X) / 2
		and math.abs(a.Z - b.Z) < (aSize.Y + bSize.Y) / 2
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

local function round(value: number): number
	return math.round(value * 1000) / 1000
end

-- Placement with its base centre moved by `offset` (building-local studs; Y is ignored)
function BuildingPlacement.Shift(placement: Placement, offset: Vector3): Placement
	local moved = BuildingPlacement.ToCFrame(placement) * CFrame.new(offset.X, 0, offset.Z)
	local result = BuildingPlacement.FromCFrame(moved)
	return { X = round(result.X), Z = round(result.Z), Rotation = placement.Rotation }
end

-- Placement of a building once it's at `level`: its base centre moves when the level grows to
-- one side (BuildingModels.GetLevelOffset), so the parts both levels share stay where they are
function BuildingPlacement.GetLevelPlacement(saved: SavedBuilding, level: number): Placement?
	local placement = saved.Placement
	if not placement then
		return nil
	end
	return BuildingPlacement.Shift(
		placement,
		BuildingModels.GetLevelOffset(saved.Id, saved.Level, level)
	)
end

-- True when the whole footprint lies on a plot of side `plotSize`
function BuildingPlacement.IsOnPlot(
	plotSize: number,
	placement: Placement,
	footprint: Vector2
): boolean
	local size = getRotatedSize(footprint, placement.Rotation)
	local half = plotSize / 2 + 0.01
	return math.abs(placement.X) + size.X / 2 <= half and math.abs(placement.Z) + size.Y / 2 <= half
end

const reaches: { [string]: { Size: Vector2, Centre: Vector3 } } = {}

-- The ground a building can ever take up across all its levels, seen from `level`: the size of
-- that box and where its centre sits relative to the level's base centre (building-local).
-- New buildings are placed so this whole area is free, so they never run out of room to grow.
function BuildingPlacement.GetReach(id: BuildingId, level: number): (Vector2, Vector3)
	level = math.max(level, 1)
	local key = `{id}_{level}`
	local cached = reaches[key]
	if not cached then
		local footprint = BuildingModels.GetFootprint(id, level)
		local minX, maxX = -footprint.X / 2, footprint.X / 2
		local minZ, maxZ = -footprint.Y / 2, footprint.Y / 2
		local other = 1
		while BuildingModels.HasModel(id, other) do
			if other ~= level then
				local size = BuildingModels.GetFootprint(id, other)
				local offset = BuildingModels.GetLevelOffset(id, level, other)
				minX = math.min(minX, offset.X - size.X / 2)
				maxX = math.max(maxX, offset.X + size.X / 2)
				minZ = math.min(minZ, offset.Z - size.Y / 2)
				maxZ = math.max(maxZ, offset.Z + size.Y / 2)
			end
			other += 1
		end
		cached = {
			Size = Vector2.new(maxX - minX, maxZ - minZ),
			Centre = Vector3.new((minX + maxX) / 2, 0, (minZ + maxZ) / 2),
		}
		reaches[key] = cached
	end
	return cached.Size, cached.Centre
end

-- Placement of the reach box's centre for a building whose base centre is at `placement`
function BuildingPlacement.GetReachPlacement(
	id: BuildingId,
	level: number,
	placement: Placement
): (Placement, Vector2)
	local size, centre = BuildingPlacement.GetReach(id, level)
	return BuildingPlacement.Shift(placement, centre), size
end

export type Obstacle = {
	Id: BuildingId,
	Placement: Placement,
	Footprint: Vector2,
}

-- Ground other buildings take up: where they stand now, and for those with an upgrade ordered,
-- where the bigger level will stand too (so nothing gets placed in the way of it). With
-- `reach`, also the ground each could grow into at its biggest level (used for placing).
function BuildingPlacement.GetObstacles(
	buildings: { SavedBuilding },
	workOrders: { WorkOrder },
	exceptId: BuildingId?,
	reach: boolean?
): { Obstacle }
	local obstacles: { Obstacle } = {}
	for _, saved in buildings do
		local placement = saved.Placement
		if saved.Id == exceptId or not placement then
			continue
		end
		if reach then
			local reachPlacement, size =
				BuildingPlacement.GetReachPlacement(saved.Id, saved.Level, placement)
			table.insert(obstacles, { Id = saved.Id, Placement = reachPlacement, Footprint = size })
		end
		table.insert(obstacles, {
			Id = saved.Id,
			Placement = placement,
			Footprint = BuildingModels.GetFootprint(saved.Id, saved.Level),
		})
		for _, order in workOrders do
			if order.BuildingId == saved.Id and order.TargetLevel > saved.Level then
				table.insert(obstacles, {
					Id = saved.Id,
					Placement = BuildingPlacement.GetLevelPlacement(saved, order.TargetLevel) :: Placement,
					Footprint = BuildingModels.GetFootprint(saved.Id, order.TargetLevel),
				})
			end
		end
	end
	return obstacles
end

-- Whether a building fits on the plot at `placement` (`level` picks its footprint) without
-- overlapping any obstacle; returns the reason shown to the player when it doesn't.
-- With `reach`, the ground of every level it can grow to must fit (used for placing).
function BuildingPlacement.CheckSpace(
	id: BuildingId,
	level: number,
	placement: Placement,
	plotSize: number,
	obstacles: { Obstacle },
	reach: boolean?
): (boolean, string?)
	local footprint = BuildingModels.GetFootprint(id, level)
	if reach then
		placement, footprint = BuildingPlacement.GetReachPlacement(id, level, placement)
	end
	if not BuildingPlacement.IsOnPlot(plotSize, placement, footprint) then
		return false, "Not enough room on the plot"
	end
	for _, obstacle in obstacles do
		if
			obstacle.Id ~= id
			and BuildingPlacement.Overlaps(
				placement,
				footprint,
				obstacle.Placement,
				obstacle.Footprint
			)
		then
			return false, `Blocked by the {BuildingData[obstacle.Id].Name}`
		end
	end
	return true, nil
end

-- Whether a placed building has room to grow to `level`: the bigger footprint (at its shifted
-- base centre) must stay on the plot and clear of the other buildings
function BuildingPlacement.CanGrow(
	saved: SavedBuilding,
	level: number,
	plotSize: number,
	buildings: { SavedBuilding },
	workOrders: { WorkOrder }
): (boolean, string?)
	local placement = BuildingPlacement.GetLevelPlacement(saved, level)
	if not placement then
		return false, "Not placed"
	end
	local obstacles = BuildingPlacement.GetObstacles(buildings, workOrders, saved.Id)
	local fits, reason =
		BuildingPlacement.CheckSpace(saved.Id, level, placement, plotSize, obstacles)
	if not fits then
		return false, `Needs more room to grow: {reason}`
	end
	return true, nil
end

return BuildingPlacement
