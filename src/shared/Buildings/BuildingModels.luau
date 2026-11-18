--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const BuildingData = require(script.Parent.BuildingData)
const BuildingTypes = require(script.Parent.BuildingTypes)
const FarmData = require(script.Parent.Parent.Farm.FarmData)

type BuildingId = BuildingTypes.BuildingId

type PlaceholderStyle = {
	Footprint: Vector2,
	BaseHeight: number,
	HeightPerLevel: number,
	Color: Color3,
}

const DEFAULT_STYLE: PlaceholderStyle = {
	Footprint = Vector2.new(24, 24),
	BaseHeight = 0,
	HeightPerLevel = 6,
	Color = Color3.fromRGB(163, 162, 165),
}

-- Placeholder looks that differ from the default grey block
const STYLES: { [string]: PlaceholderStyle } = {
	Spire = {
		Footprint = Vector2.new(10, 10),
		BaseHeight = 30,
		HeightPerLevel = 10,
		Color = Color3.fromRGB(120, 90, 200),
	},
}

const BuildingModels = {}

const footprints: { [string]: Vector2 } = {}

const MIN_HEIGHT = 6
const FLOOR_THICKNESS = 1
const ROOF_THICKNESS = 1
const WALL_THICKNESS = 1
const WALL_ROW_HEIGHT = 3
-- Footprints this small become a stacked pillar instead of a walled box
const PILLAR_SIZE = 12
const PILLAR_BLOCK_HEIGHT = 4
-- Placeholder crop field (buildings with a Field component): path-coloured disc under stepped
-- soil wedges. Field parts cost no materials (BuildMaterial "Soil").
const FIELD_PATH_HEIGHT = 0.4
const FIELD_PATH_COLOR = Color3.fromRGB(165, 135, 95)
const FIELD_SOIL_COLOR = Color3.fromRGB(95, 65, 40)
const FIELD_SOIL_BANDS = 6
const FIELD_MATERIAL = "Soil"

local function addPart(model: Model, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Color = color
	part.Material = material
	part.Size = size
	part.CFrame = CFrame.new(position)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

-- Flat crop field around a hut (FarmData geometry): a path disc of OUTER_RADIUS with the six
-- soil wedges between the spokes, each approximated by radial bands of boxes, top at SOIL_HEIGHT
local function addFieldBase(model: Model)
	local base = addPart(
		model,
		"FieldBase",
		Vector3.new(FIELD_PATH_HEIGHT, FarmData.OUTER_RADIUS * 2, FarmData.OUTER_RADIUS * 2),
		Vector3.new(0, FIELD_PATH_HEIGHT / 2, 0),
		FIELD_PATH_COLOR,
		Enum.Material.Ground
	)
	base.Shape = Enum.PartType.Cylinder
	base.CFrame = CFrame.new(0, FIELD_PATH_HEIGHT / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
	base:SetAttribute("BuildMaterial", FIELD_MATERIAL)

	local halfAngle = math.pi / FarmData.WEDGE_COUNT
	local depth = (FarmData.SOIL_OUTER - FarmData.SOIL_INNER) / FIELD_SOIL_BANDS
	for wedge = 1, FarmData.WEDGE_COUNT do
		local angle = FarmData.GetWedgeAngle(wedge)
		local direction = FarmData.GetDirection(angle)
		for band = 1, FIELD_SOIL_BANDS do
			local inner = FarmData.SOIL_INNER + (band - 1) * depth
			-- Narrow enough to stay off the spokes; short enough to stay inside the soil circle
			local halfWidth = inner * math.sin(halfAngle) - FarmData.PATH_WIDTH / 2
			local outer =
				math.min(inner + depth, math.sqrt(FarmData.SOIL_OUTER ^ 2 - halfWidth ^ 2))
			if halfWidth <= 0 or outer <= inner then
				continue
			end
			local soil = addPart(
				model,
				`Soil{wedge}_{band}`,
				Vector3.new(halfWidth * 2, FarmData.SOIL_HEIGHT, outer - inner),
				Vector3.zero,
				FIELD_SOIL_COLOR,
				Enum.Material.Ground
			)
			local centre = direction * ((inner + outer) / 2)
			soil.CFrame = CFrame.new(centre.X, FarmData.SOIL_HEIGHT / 2, centre.Z)
				* CFrame.Angles(0, -angle, 0)
			soil:SetAttribute("BuildMaterial", FIELD_MATERIAL)
		end
	end
end

-- A placeholder made of many parts (floor, wall rows, roof) so Builders can raise it bottom-up.
-- Stone: floor, bottom wall row, pillar blocks. Wood: upper wall rows and roof.
-- Buildings with a Field component stand in the middle of a flat crop field.
local function createPlaceholder(id: BuildingId, level: number): Model
	local style = STYLES[id] or DEFAULT_STYLE
	local height = math.max(style.BaseHeight + level * style.HeightPerLevel, MIN_HEIGHT)
	local width, depth = style.Footprint.X, style.Footprint.Y
	local stoneColor = style.Color:Lerp(Color3.fromRGB(120, 120, 120), 0.5)

	local model = Instance.new("Model")
	local labelPart: BasePart
	if BuildingData[id].Components.Field then
		addFieldBase(model)
	end

	if math.max(width, depth) <= PILLAR_SIZE then
		local blocks = math.max(math.round(height / PILLAR_BLOCK_HEIGHT), 1)
		local blockHeight = height / blocks
		for i = 1, blocks do
			labelPart = addPart(
				model,
				`Block{i}`,
				Vector3.new(width, blockHeight, depth),
				Vector3.new(0, blockHeight * (i - 0.5), 0),
				style.Color,
				Enum.Material.Cobblestone
			)
		end
	else
		labelPart = addPart(
			model,
			"Floor",
			Vector3.new(width, FLOOR_THICKNESS, depth),
			Vector3.new(0, FLOOR_THICKNESS / 2, 0),
			stoneColor,
			Enum.Material.Cobblestone
		)

		local wallHeight = height - FLOOR_THICKNESS - ROOF_THICKNESS
		local rows = math.max(math.round(wallHeight / WALL_ROW_HEIGHT), 1)
		local rowHeight = wallHeight / rows
		for row = 1, rows do
			local y = FLOOR_THICKNESS + rowHeight * (row - 0.5)
			local isStone = row == 1
			local color = if isStone then stoneColor else style.Color
			local material = if isStone then Enum.Material.Cobblestone else Enum.Material.WoodPlanks
			local innerDepth = depth - WALL_THICKNESS * 2
			addPart(model, `WallN{row}`, Vector3.new(width, rowHeight, WALL_THICKNESS), Vector3.new(0, y, -(depth - WALL_THICKNESS) / 2), color, material)
			addPart(model, `WallS{row}`, Vector3.new(width, rowHeight, WALL_THICKNESS), Vector3.new(0, y, (depth - WALL_THICKNESS) / 2), color, material)
			addPart(model, `WallW{row}`, Vector3.new(WALL_THICKNESS, rowHeight, innerDepth), Vector3.new(-(width - WALL_THICKNESS) / 2, y, 0), color, material)
			addPart(model, `WallE{row}`, Vector3.new(WALL_THICKNESS, rowHeight, innerDepth), Vector3.new((width - WALL_THICKNESS) / 2, y, 0), color, material)
		end

		addPart(
			model,
			"Roof",
			Vector3.new(width, ROOF_THICKNESS, depth),
			Vector3.new(0, height - ROOF_THICKNESS / 2, 0),
			style.Color:Lerp(Color3.fromRGB(110, 70, 40), 0.6),
			Enum.Material.WoodPlanks
		)
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(200, 50)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, height + 4 - labelPart.Position.Y, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = labelPart

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = `{BuildingData[id].Name} (Lv {level})`
	label.Parent = billboard

	-- Pivot at the base centre, like the real models
	model.WorldPivot = CFrame.new()

	return model
end

-- Returns an unparented clone of ReplicatedStorage.BuildingModels.<Id>.Level<N>
-- (its pivot must be at the base centre), falling back to the highest lower level that has a model,
-- or a labelled placeholder block. Level 0 draws level 1.
function BuildingModels.Create(id: BuildingId, level: number): Model
	level = math.max(level, 1)
	local folder = ReplicatedStorage:FindFirstChild("BuildingModels")
	local levels = folder and folder:FindFirstChild(id)
	-- Levels without their own model reuse the highest modelled level below them
	local template: Instance? = nil
	if levels then
		for l = level, 1, -1 do
			template = levels:FindFirstChild(`Level{l}`)
			if template then
				break
			end
		end
	end

	local model = if template and template:IsA("Model")
		then template:Clone()
		else createPlaceholder(id, level)
	model.Name = id

	return model
end

-- Unrotated X/Z size of the model, cached per id and level. Unbuilt sites (level 0) use level 1.
function BuildingModels.GetFootprint(id: BuildingId, level: number): Vector2
	level = math.max(level, 1)
	local key = `{id}_{level}`
	local cached = footprints[key]
	if cached then
		return cached
	end

	local model = BuildingModels.Create(id, level)
	local size = model:GetExtentsSize()
	model:Destroy()

	local footprint = Vector2.new(size.X, size.Z)
	footprints[key] = footprint
	return footprint
end

return BuildingModels
