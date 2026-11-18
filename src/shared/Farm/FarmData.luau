--!strict

-- Farmer's Hut field ("fan"): the hut stands in a centre circle, ringed by 6 wedge-shaped crop plots
-- split by straight paths (spokes). All geometry is in the hut's local space: studs, pivot at the base
-- centre, front = -Z. The Blockbench model and the code both follow these numbers.

export type CropId = "Wheat" | "Carrot" | "Potato"

export type CropInfo = {
	Id: CropId,
	Name: string,
	-- Item the player hands over to plant it (consumed once; the crop then regrows forever)
	SeedItem: string,
	-- Item a harvest yields
	ProduceItem: string,
	-- Produce per harvest of one wedge
	Yield: number,
	-- Seconds per growth stage; stage 1 at planting, ripe (stage STAGES) after (STAGES - 1) * StageTime
	StageTime: number,
}

-- Saved per wedge in the hut's field state
export type Plot = {
	Crop: CropId?,
	-- Server time the current growth started (planted or last harvested)
	PlantedAt: number?,
}

-- Growth stages before ripe (1 = sprout, 2 = growing, 3 = ripe)
const STAGES = 3

const CROPS: { [CropId]: CropInfo } = {
	Wheat = {
		Id = "Wheat",
		Name = "Wheat",
		SeedItem = "WheatSeeds",
		ProduceItem = "Wheat",
		Yield = 4,
		StageTime = 20,
	},
	Carrot = {
		Id = "Carrot",
		Name = "Carrot",
		SeedItem = "CarrotSeeds",
		ProduceItem = "Carrot",
		Yield = 3,
		StageTime = 25,
	},
	Potato = {
		Id = "Potato",
		Name = "Potato",
		SeedItem = "PotatoSeeds",
		ProduceItem = "Potato",
		Yield = 3,
		StageTime = 30,
	},
}

const CROP_ORDER: { CropId } = { "Wheat", "Carrot", "Potato" }

-- Whole field: a circle of this radius (footprint 2 * OUTER_RADIUS square)
const OUTER_RADIUS = 48
-- Centre circle holding the hut (hut model fits inside a 24 x 24 square)
const HUT_RADIUS = 18
-- Tilled soil runs from SOIL_INNER to SOIL_OUTER; the rings outside it are the circular path and border
const SOIL_INNER = 20
const SOIL_OUTER = 46
-- Top of the tilled soil (crops stand on it); paths sit slightly lower
const SOIL_HEIGHT = 0.5
-- Width of each straight path between wedges (and of the front entry path)
const PATH_WIDTH = 3
const WEDGE_COUNT = 6
-- Hut level that unlocks each wedge (index = wedge). T1 = the two front wedges, T2 = sides, T3 = back.
const WEDGE_UNLOCK_LEVEL = { 1, 2, 3, 3, 2, 1 }

-- Angles are radians measured from the front (-Z) toward +X: direction = (sin a, 0, -cos a).
-- Spokes (paths) sit at 0, 60, 120 ... degrees; wedge i is centred at 30 + 60 * (i - 1) degrees.
local function getWedgeAngle(wedge: number): number
	return math.rad(30 + 60 * (wedge - 1))
end

-- Unit direction from the hut centre toward angle `a`, in hut-local space
local function getDirection(angle: number): Vector3
	return Vector3.new(math.sin(angle), 0, -math.cos(angle))
end

-- Wedges unlocked at a hut level (levels above 3 keep all 6)
local function getUnlockedWedges(level: number): { number }
	local list = {}
	for wedge, unlock in WEDGE_UNLOCK_LEVEL do
		if level >= unlock then
			table.insert(list, wedge)
		end
	end
	return list
end

local function isUnlocked(wedge: number, level: number): boolean
	local unlock = WEDGE_UNLOCK_LEVEL[wedge]
	return unlock ~= nil and level >= unlock
end

-- Growth stage (0 = empty, 1..STAGES) of a plot at `now`
local function getStage(plot: Plot, now: number): number
	local crop = plot.Crop and CROPS[plot.Crop]
	if not crop or not plot.PlantedAt then
		return 0
	end
	local elapsed = math.max(now - plot.PlantedAt, 0)
	return math.min(math.floor(elapsed / crop.StageTime) + 1, STAGES)
end

local function isRipe(plot: Plot, now: number): boolean
	return getStage(plot, now) >= STAGES
end

-------- Helpers (code only; the geometry above is shared with the model) --------

-- Side of the square around the hut that colonists path around (the rest of the field is walkable)
const HUT_FOOTPRINT = 24
-- Radius of a wedge's middle, where the Farmer stands to plant and harvest
const WEDGE_MID_RADIUS = (SOIL_INNER + SOIL_OUTER) / 2
-- Looked up by plain strings (saved data, remotes); the checker widens refined CropId locals to string
const CROPS_BY_ID: { [string]: CropInfo } = CROPS :: any

-- A crop's info from any id (nil when it isn't a crop)
local function getCrop(id: unknown): CropInfo?
	return if typeof(id) == "string" then CROPS_BY_ID[id] else nil
end

local function isCropId(value: unknown): boolean
	return getCrop(value) ~= nil
end

-- Seconds from planting (or harvesting) until ripe, matching getStage
local function getGrowTime(crop: string): number
	local info = CROPS_BY_ID[crop]
	return if info then (STAGES - 1) * info.StageTime else 0
end

-- 0..1 growth toward ripe (0 while empty or not planted yet)
local function getProgress(plot: Plot, now: number): number
	local info = getCrop(plot.Crop)
	local plantedAt = plot.PlantedAt
	if not info or not plantedAt then
		return 0
	end
	return math.clamp((now - plantedAt) / ((STAGES - 1) * info.StageTime), 0, 1)
end

-- Hut-local point on the ground in the middle of a wedge
local function getWedgeCentre(wedge: number): Vector3
	return getDirection(getWedgeAngle(wedge)) * WEDGE_MID_RADIUS
end

-- A field with every wedge empty
local function newField(): { Plot }
	local field = {}
	for wedge = 1, WEDGE_COUNT do
		field[wedge] = {}
	end
	return field
end

return {
	STAGES = STAGES,
	CROPS = CROPS,
	CROP_ORDER = CROP_ORDER,
	OUTER_RADIUS = OUTER_RADIUS,
	HUT_RADIUS = HUT_RADIUS,
	SOIL_INNER = SOIL_INNER,
	SOIL_OUTER = SOIL_OUTER,
	SOIL_HEIGHT = SOIL_HEIGHT,
	PATH_WIDTH = PATH_WIDTH,
	WEDGE_COUNT = WEDGE_COUNT,
	WEDGE_UNLOCK_LEVEL = WEDGE_UNLOCK_LEVEL,
	GetWedgeAngle = getWedgeAngle,
	GetDirection = getDirection,
	GetUnlockedWedges = getUnlockedWedges,
	IsUnlocked = isUnlocked,
	GetStage = getStage,
	IsRipe = isRipe,
	HUT_FOOTPRINT = HUT_FOOTPRINT,
	WEDGE_MID_RADIUS = WEDGE_MID_RADIUS,
	GetCrop = getCrop,
	IsCropId = isCropId,
	GetGrowTime = getGrowTime,
	GetProgress = getProgress,
	GetWedgeCentre = getWedgeCentre,
	NewField = newField,
}
