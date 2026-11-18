--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const BuildingData = require(Shared.Buildings.BuildingData)
const BuildingPlacement = require(Shared.Buildings.BuildingPlacement)
const BuildingUnlocks = require(Shared.Buildings.BuildingUnlocks)
const FarmData = require(Shared.Farm.FarmData)
const ColonyStore = require(script.Parent.ColonyStore)

-- What one wedge shows, and the model drawing it
type DrawnWedge = {
	Key: string,
	Model: Model?,
}

type DrawnField = {
	Pivot: CFrame,
	Level: number,
	Holder: Model,
	Wedges: { [number]: DrawnWedge },
}

-- Seconds between growth checks (models are only rebuilt when a wedge's stage changes)
const UPDATE_INTERVAL = 1
-- Studs between plants, along and across a wedge
const ROW_SPACING = 4
const PLANT_SPACING = 3.5
-- Studs kept clear of the spokes and the soil's edges
const PATH_CLEARANCE = 0.6
const EDGE_CLEARANCE = 1.2
-- Plant size at each growth stage (1 sprout, 2 growing, 3 ripe)
const STAGE_SCALE = { 0.35, 0.7, 1 }

const LEAF_GREEN = Color3.fromRGB(70, 145, 55)
const YOUNG_GREEN = Color3.fromRGB(120, 185, 80)
const WHEAT_GREEN = Color3.fromRGB(140, 175, 70)
const WHEAT_GOLD = Color3.fromRGB(222, 184, 88)
const WHEAT_EAR = Color3.fromRGB(200, 150, 60)
const CARROT_ORANGE = Color3.fromRGB(235, 125, 35)
const POTATO_LEAF = Color3.fromRGB(60, 120, 50)
const POTATO_FLOWER = Color3.fromRGB(235, 225, 245)
const POTATO_FLOWER_CENTRE = Color3.fromRGB(240, 205, 70)

-- Draws the crops growing on every crop field (Farmer's Hut) of the local player's colony:
-- workspace.MyColony.Fields.<BuildingId>.Wedge<N>. Growth comes from each plot's PlantedAt and
-- the server clock (FarmData.GetStage), so nothing is sent while crops grow.
const FieldView = {}

local started = false

const drawn: { [string]: DrawnField } = {}
local holderFolder: Folder? = nil

-- Plant spots in hut-local studs (Y = 0) for each wedge, with a stable per-spot random seed
const spots: { [number]: { Vector3 } } = {}

local function getSpots(wedge: number): { Vector3 }
	local cached = spots[wedge]
	if cached then
		return cached
	end

	local list = {}
	local angle = FarmData.GetWedgeAngle(wedge)
	local forward = FarmData.GetDirection(angle)
	local across = Vector3.new(-forward.Z, 0, forward.X)
	local halfAngle = math.pi / FarmData.WEDGE_COUNT
	local minRadius = FarmData.SOIL_INNER + EDGE_CLEARANCE
	local maxRadius = FarmData.SOIL_OUTER - EDGE_CLEARANCE
	local random = Random.new(wedge * 7919)

	local radius = minRadius
	while radius <= maxRadius do
		local halfWidth = radius * math.sin(halfAngle)
		local count = math.floor(halfWidth * 2 / PLANT_SPACING)
		for i = 0, count do
			local offset = (i - count / 2) * PLANT_SPACING
			local point = forward * radius + across * offset
			-- A little jitter so rows don't look machine-planted
			point += Vector3.new(random:NextNumber(-0.4, 0.4), 0, random:NextNumber(-0.4, 0.4))
			local distance = point.Magnitude
			local relative = math.atan2(point:Dot(across), point:Dot(forward))
			local fromSpoke = distance * math.sin(halfAngle - math.abs(relative))
			if
				distance <= maxRadius
				and distance >= minRadius
				and math.abs(relative) < halfAngle
				and fromSpoke >= FarmData.PATH_WIDTH / 2 + PATH_CLEARANCE
			then
				table.insert(list, point)
			end
		end
		radius += ROW_SPACING
	end

	spots[wedge] = list
	return list
end

local function addPart(
	model: Model,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	if shape then
		part.Shape = shape
	end
	part.Parent = model
	return part
end

-- Thin stalks turning golden, with ears once ripe
local function drawWheat(model: Model, base: CFrame, stage: number, random: Random)
	local scale = STAGE_SCALE[stage]
	local height = 3.2 * scale
	local color = if stage >= 3 then WHEAT_GOLD elseif stage == 2 then WHEAT_GREEN else YOUNG_GREEN
	for i = 1, 3 do
		local yaw = (i / 3) * math.pi * 2 + random:NextNumber(-0.4, 0.4)
		local lean = random:NextNumber(0.05, 0.18)
		local stalk = base
			* CFrame.Angles(0, yaw, 0)
			* CFrame.new(0.25, 0, 0)
			* CFrame.Angles(0, 0, lean)
		addPart(model, Vector3.new(0.15, height, 0.15), stalk * CFrame.new(0, height / 2, 0), color)
		if stage >= 3 then
			addPart(
				model,
				Vector3.new(0.32, 0.9, 0.32),
				stalk * CFrame.new(0, height + 0.35, 0),
				WHEAT_EAR
			)
		end
	end
end

-- Leafy green tops; the orange root shows once ripe
local function drawCarrot(model: Model, base: CFrame, stage: number, random: Random)
	local scale = STAGE_SCALE[stage]
	local height = 1.8 * scale
	local color = if stage == 1 then YOUNG_GREEN else LEAF_GREEN
	for i = 1, 3 do
		local yaw = (i / 3) * math.pi * 2 + random:NextNumber(-0.3, 0.3)
		local leaf = base
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(random:NextNumber(0.25, 0.45), 0, 0)
		addPart(
			model,
			Vector3.new(0.1, height, 0.55 * scale + 0.15),
			leaf * CFrame.new(0, height / 2, 0),
			color
		)
	end
	if stage >= 3 then
		-- Cylinders run along X; turned upright, the top pokes out of the soil
		addPart(
			model,
			Vector3.new(0.6, 0.55, 0.55),
			base * CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.pi / 2),
			CARROT_ORANGE,
			Enum.PartType.Cylinder
		)
	end
end

-- Bushy leaves, flowering as it grows
local function drawPotato(model: Model, base: CFrame, stage: number, random: Random)
	local scale = STAGE_SCALE[stage]
	local size = 1.6 * scale + 0.3
	addPart(
		model,
		Vector3.new(size, size, size),
		base * CFrame.new(0, size * 0.4, 0),
		if stage == 1 then YOUNG_GREEN else POTATO_LEAF,
		Enum.PartType.Ball
	)
	if stage >= 2 then
		local side = size * 0.7
		addPart(
			model,
			Vector3.new(side, side, side),
			base
				* CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
				* CFrame.new(size * 0.45, side * 0.35, 0),
			POTATO_LEAF,
			Enum.PartType.Ball
		)
	end
	if stage >= 3 then
		for i = 1, 2 do
			local yaw = random:NextNumber(0, math.pi * 2)
			local flower = base * CFrame.Angles(0, yaw, 0) * CFrame.new(size * 0.3, size * 0.85, 0)
			addPart(model, Vector3.new(0.4, 0.4, 0.4), flower, POTATO_FLOWER, Enum.PartType.Ball)
			addPart(
				model,
				Vector3.new(0.18, 0.18, 0.18),
				flower * CFrame.new(0, 0.18, 0),
				POTATO_FLOWER_CENTRE,
				Enum.PartType.Ball
			)
		end
	end
end

const DRAW: { [string]: (Model, CFrame, number, Random) -> () } = {
	Wheat = drawWheat,
	Carrot = drawCarrot,
	Potato = drawPotato,
}

local function buildWedge(pivot: CFrame, wedge: number, crop: string, stage: number): Model
	local model = Instance.new("Model")
	model.Name = `Wedge{wedge}`
	model:SetAttribute("Crop", crop)
	model:SetAttribute("Stage", stage)
	local draw = DRAW[crop]
	for index, spot in getSpots(wedge) do
		local random = Random.new(wedge * 1000 + index)
		local base = pivot
			* CFrame.new(spot.X, FarmData.SOIL_HEIGHT, spot.Z)
			* CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
		draw(model, base, stage, random)
	end
	return model
end

local function clearField(field: DrawnField)
	field.Holder:Destroy()
	table.clear(field.Wedges)
end

-- Redraws wedges whose crop or stage changed; everything when a hut moved or changed level
local function refresh()
	local folder = holderFolder
	if not folder then
		return
	end
	local now = workspace:GetServerTimeNow()
	local fields = ColonyStore.Fields()
	local seen: { [string]: boolean } = {}

	for _, saved in ColonyStore.Buildings() do
		local placement = saved.Placement
		local field = fields[saved.Id]
		if
			not placement
			or not field
			or not BuildingData[saved.Id].Components.Field
			or not BuildingUnlocks.IsBuilt(saved.Id, saved.Level)
		then
			continue
		end
		seen[saved.Id] = true

		local pivot = BuildingPlacement.ToCFrame(placement)
		local old = drawn[saved.Id]
		if old and (old.Pivot ~= pivot or old.Level ~= saved.Level) then
			clearField(old)
			drawn[saved.Id] = nil
		end
		local current: DrawnField = drawn[saved.Id]
			or {
				Pivot = pivot,
				Level = saved.Level,
				Holder = Instance.new("Model"),
				Wedges = {},
			}
		if not current.Holder.Parent then
			current.Holder.Name = saved.Id
			current.Holder.Parent = folder
		end
		drawn[saved.Id] = current

		for wedge = 1, FarmData.WEDGE_COUNT do
			local plot = field[wedge] or {}
			local info = FarmData.GetCrop(plot.Crop)
			local crop = if info then info.Id else nil
			local stage = if FarmData.IsUnlocked(wedge, saved.Level)
				then FarmData.GetStage(plot, now)
				else 0
			local key = if crop and stage > 0 then `{crop}:{stage}` else ""
			local entry = current.Wedges[wedge]
			if entry and entry.Key == key then
				continue
			end
			if entry and entry.Model then
				entry.Model:Destroy()
			end
			local model = if crop and stage > 0 then buildWedge(pivot, wedge, crop, stage) else nil
			if model then
				model.Parent = current.Holder
			end
			current.Wedges[wedge] = { Key = key, Model = model }
		end
	end

	for id, field in drawn do
		if not seen[id] then
			clearField(field)
			drawn[id] = nil
		end
	end
end

function FieldView.Start()
	if started then
		return
	end
	started = true

	local colonyFolder = workspace:FindFirstChild("MyColony") or workspace
	local folder = Instance.new("Folder")
	folder.Name = "Fields"
	folder.Parent = colonyFolder
	holderFolder = folder

	vide.root(function()
		vide.effect(function()
			ColonyStore.Buildings()
			ColonyStore.Fields()
			vide.untrack(refresh)
		end)
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime
		if elapsed < UPDATE_INTERVAL then
			return
		end
		elapsed = 0
		refresh()
	end)
end

return FieldView
