--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared

const BuildingData = require(Shared.Buildings.BuildingData)
const BuildingModels = require(Shared.Buildings.BuildingModels)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const FarmData = require(Shared.Farm.FarmData)
const PlotData = require(Shared.Plot.PlotData)

type ColonyData = ColonyTypes.ColonyData
type SavedBuilding = ColonyTypes.SavedBuilding

-- Walkable grid over a colony's plot, in plot-local studs (Y is always 0)
export type Grid = {
	Key: string,
	CellSize: number,
	-- Cells per side
	Count: number,
	Half: number,
	Blocked: { [number]: boolean },
}

const CELL_SIZE = 4
-- Studs kept clear around building footprints
const MARGIN = 1
-- Studs in front of a building its door spot sits
const DOOR_OFFSET = 3
const MAX_ITERATIONS = 40000
const SQRT2 = math.sqrt(2)

const Navigation = {}

Navigation.DOOR_OFFSET = DOOR_OFFSET

local function getTownHallLevel(data: ColonyData): number
	for _, saved in data.Buildings do
		if saved.Id == "TownHall" then
			return saved.Level
		end
	end
	return 0
end

-- Unrotated X/Z size colonists path around: a building with a crop field only blocks its hut,
-- so its Farmer (and anyone else) can walk across the field
local function getObstacleSize(saved: SavedBuilding): Vector2
	if BuildingData[saved.Id].Components.Field then
		return Vector2.new(FarmData.HUT_FOOTPRINT, FarmData.HUT_FOOTPRINT)
	end
	return BuildingModels.GetFootprint(saved.Id, saved.Level)
end

local function getRotatedFootprint(saved: SavedBuilding): Vector2
	local footprint = getObstacleSize(saved)
	local placement = saved.Placement
	if placement and placement.Rotation % 2 == 1 then
		return Vector2.new(footprint.Y, footprint.X)
	end
	return footprint
end

local function getKey(data: ColonyData): string
	local parts = { tostring(getTownHallLevel(data)) }
	for _, saved in data.Buildings do
		local placement = saved.Placement
		if placement then
			table.insert(
				parts,
				`{saved.Id}:{saved.Level}:{placement.X}:{placement.Z}:{placement.Rotation}`
			)
		end
	end
	return table.concat(parts, "|")
end

local function toIndex(grid: Grid, ix: number, iz: number): number
	return iz * grid.Count + ix
end

local function toCell(grid: Grid, position: Vector3): (number, number)
	local ix = math.clamp(math.floor((position.X + grid.Half) / grid.CellSize), 0, grid.Count - 1)
	local iz = math.clamp(math.floor((position.Z + grid.Half) / grid.CellSize), 0, grid.Count - 1)
	return ix, iz
end

local function toPosition(grid: Grid, ix: number, iz: number): Vector3
	return Vector3.new(
		-grid.Half + (ix + 0.5) * grid.CellSize,
		0,
		-grid.Half + (iz + 0.5) * grid.CellSize
	)
end

local function isFree(grid: Grid, ix: number, iz: number): boolean
	return ix >= 0
		and iz >= 0
		and ix < grid.Count
		and iz < grid.Count
		and not grid.Blocked[toIndex(grid, ix, iz)]
end

-- Rebuilt only when the buildings or plot size change
function Navigation.GetGrid(data: ColonyData, previous: Grid?): Grid
	local key = getKey(data)
	if previous and previous.Key == key then
		return previous
	end

	local size = PlotData.GetSize(getTownHallLevel(data))
	local grid: Grid = {
		Key = key,
		CellSize = CELL_SIZE,
		Count = math.floor(size / CELL_SIZE),
		Half = size / 2,
		Blocked = {},
	}

	for _, saved in data.Buildings do
		local placement = saved.Placement
		if not placement then
			continue
		end
		local footprint = getRotatedFootprint(saved)
		local halfX = footprint.X / 2 + MARGIN
		local halfZ = footprint.Y / 2 + MARGIN
		local minX, minZ = toCell(grid, Vector3.new(placement.X - halfX, 0, placement.Z - halfZ))
		local maxX, maxZ = toCell(grid, Vector3.new(placement.X + halfX, 0, placement.Z + halfZ))
		for ix = minX, maxX do
			for iz = minZ, maxZ do
				local centre = toPosition(grid, ix, iz)
				if
					math.abs(centre.X - placement.X) < halfX
					and math.abs(centre.Z - placement.Z) < halfZ
				then
					grid.Blocked[toIndex(grid, ix, iz)] = true
				end
			end
		end
	end

	return grid
end

-- Closest walkable cell to a position (searching outwards ring by ring)
local function nearestFree(grid: Grid, ix: number, iz: number): (number, number)
	if isFree(grid, ix, iz) then
		return ix, iz
	end
	for radius = 1, grid.Count do
		for dx = -radius, radius do
			for _, dz in { -radius, radius } do
				if isFree(grid, ix + dx, iz + dz) then
					return ix + dx, iz + dz
				end
			end
		end
		for dz = -radius + 1, radius - 1 do
			for _, dx in { -radius, radius } do
				if isFree(grid, ix + dx, iz + dz) then
					return ix + dx, iz + dz
				end
			end
		end
	end
	return ix, iz
end

function Navigation.IsWalkable(grid: Grid, position: Vector3): boolean
	local half = grid.Half
	if math.abs(position.X) >= half or math.abs(position.Z) >= half then
		return false
	end
	local ix, iz = toCell(grid, position)
	return isFree(grid, ix, iz)
end

-- Nearest walkable point to a position
function Navigation.Snap(grid: Grid, position: Vector3): Vector3
	if Navigation.IsWalkable(grid, position) then
		return Vector3.new(position.X, 0, position.Z)
	end
	local ix, iz = nearestFree(grid, toCell(grid, position))
	return toPosition(grid, ix, iz)
end

-- True when the straight line between two points crosses no blocked cell
local function hasLineOfSight(grid: Grid, from: Vector3, to: Vector3): boolean
	local offset = to - from
	local steps = math.ceil(offset.Magnitude / (grid.CellSize / 2))
	for i = 1, steps - 1 do
		if not Navigation.IsWalkable(grid, from + offset * (i / steps)) then
			return false
		end
	end
	return true
end

-- Binary heap of { Index, Score }
local function push(heap: { { number } }, index: number, score: number)
	table.insert(heap, { index, score })
	local i = #heap
	while i > 1 do
		local parent = i // 2
		if heap[parent][2] <= heap[i][2] then
			break
		end
		heap[parent], heap[i] = heap[i], heap[parent]
		i = parent
	end
end

local function pop(heap: { { number } }): number
	local top = heap[1][1]
	local last = table.remove(heap) :: { number }
	if #heap > 0 then
		heap[1] = last
		local i = 1
		while true do
			local left, right = i * 2, i * 2 + 1
			local smallest = i
			if left <= #heap and heap[left][2] < heap[smallest][2] then
				smallest = left
			end
			if right <= #heap and heap[right][2] < heap[smallest][2] then
				smallest = right
			end
			if smallest == i then
				break
			end
			heap[smallest], heap[i] = heap[i], heap[smallest]
			i = smallest
		end
	end
	return top
end

const NEIGHBOURS = {
	{ 1, 0, 1 },
	{ -1, 0, 1 },
	{ 0, 1, 1 },
	{ 0, -1, 1 },
	{ 1, 1, SQRT2 },
	{ 1, -1, SQRT2 },
	{ -1, 1, SQRT2 },
	{ -1, -1, SQRT2 },
}

-- A* over the grid, then string-pulled. Returns plot-local points from `from` to `to`
-- (the end is moved to the nearest walkable spot when it sits inside a building).
function Navigation.FindPath(grid: Grid, from: Vector3, to: Vector3): { Vector3 }
	from = Vector3.new(from.X, 0, from.Z)
	to = Navigation.Snap(grid, to)

	if hasLineOfSight(grid, from, to) then
		return { from, to }
	end

	local startX, startZ = nearestFree(grid, toCell(grid, from))
	local goalX, goalZ = nearestFree(grid, toCell(grid, to))
	local start = toIndex(grid, startX, startZ)
	local goal = toIndex(grid, goalX, goalZ)
	local count = grid.Count

	local cameFrom: { [number]: number } = {}
	local cost: { [number]: number } = { [start] = 0 }
	local closed: { [number]: boolean } = {}
	local open = {}
	push(open, start, 0)

	local iterations = 0
	local found = false
	while #open > 0 and iterations < MAX_ITERATIONS do
		iterations += 1
		local current = pop(open)
		if current == goal then
			found = true
			break
		end
		if closed[current] then
			continue
		end
		closed[current] = true

		local cx, cz = current % count, current // count
		for _, neighbour in NEIGHBOURS do
			local nx, nz = cx + neighbour[1], cz + neighbour[2]
			if not isFree(grid, nx, nz) then
				continue
			end
			-- No cutting corners past buildings
			if
				neighbour[1] ~= 0
				and neighbour[2] ~= 0
				and (not isFree(grid, nx, cz) or not isFree(grid, cx, nz))
			then
				continue
			end
			local index = toIndex(grid, nx, nz)
			local newCost = cost[current] + neighbour[3]
			if newCost < (cost[index] or math.huge) then
				cost[index] = newCost
				cameFrom[index] = current
				local dx, dz = math.abs(nx - goalX), math.abs(nz - goalZ)
				local heuristic = math.max(dx, dz) + (SQRT2 - 1) * math.min(dx, dz)
				push(open, index, newCost + heuristic)
			end
		end
	end

	if not found then
		return { from, to }
	end

	local cells = {}
	local current: number? = goal
	while current do
		table.insert(cells, 1, toPosition(grid, current % count, current // count))
		current = cameFrom[current]
	end
	cells[1] = from
	table.insert(cells, to)

	-- String pulling: skip points that are visible from the last kept point
	local path = { cells[1] }
	local anchor = 1
	for i = 3, #cells do
		if not hasLineOfSight(grid, cells[anchor], cells[i]) then
			anchor = i - 1
			table.insert(path, cells[anchor])
		end
	end
	table.insert(path, cells[#cells])
	return path
end

-- Plot-local CFrame of a building's base centre (Y = 0), rotated like the building
local function getBaseCFrame(placement: ColonyTypes.Placement): CFrame
	return CFrame.new(placement.X, 0, placement.Z)
		* CFrame.Angles(0, placement.Rotation * math.pi / 2, 0)
end

-- Plot-local spot just outside a building's front (its local +Z side). A building with a crop
-- field has its door just outside the hut on the field's front entry path (local -Z, FarmData).
function Navigation.GetDoor(saved: SavedBuilding): Vector3?
	local placement = saved.Placement
	if not placement then
		return nil
	end
	local offset
	if BuildingData[saved.Id].Components.Field then
		offset = Vector3.new(0, 0, -(FarmData.HUT_FOOTPRINT / 2 + MARGIN + DOOR_OFFSET))
	else
		local footprint = BuildingModels.GetFootprint(saved.Id, saved.Level)
		offset = Vector3.new(0, 0, footprint.Y / 2 + MARGIN + DOOR_OFFSET)
	end
	local door = getBaseCFrame(placement) * offset
	return Vector3.new(door.X, 0, door.Z)
end

-- Plot-local point from a point in a building's own space (e.g. a crop field wedge)
function Navigation.FromBuilding(saved: SavedBuilding, localPoint: Vector3): Vector3?
	local placement = saved.Placement
	if not placement then
		return nil
	end
	local point = getBaseCFrame(placement) * localPoint
	return Vector3.new(point.X, 0, point.Z)
end

-- Plot-local centre of a building
function Navigation.GetCentre(saved: SavedBuilding): Vector3?
	local placement = saved.Placement
	return if placement then Vector3.new(placement.X, 0, placement.Z) else nil
end

-- A random walkable point within `radius` of `around`
function Navigation.GetRandomPoint(
	grid: Grid,
	around: Vector3,
	radius: number,
	random: Random
): Vector3
	for _ = 1, 12 do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(radius * 0.25, radius)
		local point = around
			+ Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		if Navigation.IsWalkable(grid, point) then
			return point
		end
	end
	return Navigation.Snap(grid, around)
end

-- Closest point on the plot's edge (where colonists leave the colony)
function Navigation.GetEdge(grid: Grid, from: Vector3): Vector3
	local edge = grid.Half - grid.CellSize / 2
	local x, z = from.X, from.Z
	if math.abs(x) > math.abs(z) then
		x = math.sign(x) * edge
	else
		z = (if z == 0 then 1 else math.sign(z)) * edge
	end
	return Navigation.Snap(grid, Vector3.new(x, 0, z))
end

-- Plot-local position to world space
function Navigation.ToWorld(position: Vector3): Vector3
	return PlotData.SURFACE * position
end

return Navigation
