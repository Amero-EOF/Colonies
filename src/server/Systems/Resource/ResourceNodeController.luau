--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const ServerStorage = game:GetService("ServerStorage")

const ResourceData = require(ReplicatedStorage.Shared.Resources.ResourceData)
const WildAreaData = require(ReplicatedStorage.Shared.Wilds.WildAreaData)

type NodeId = ResourceData.NodeId
type NodeInfo = ResourceData.NodeInfo
type WildAreaInfo = WildAreaData.WildAreaInfo

type PartSpec = {
	Shape: Enum.PartType,
	Size: Vector3,
	-- Height of the part's centre above the node's base
	Height: number,
	Color: Color3,
	Material: Enum.Material,
}

const SEED = 1
-- Ground is split into cells; each cell may hold one node
const CELL_SIZE = 48
const JITTER = CELL_SIZE / 4

const PLACEHOLDERS: { [NodeId]: { PartSpec } } = {
	Tree = {
		{
			Shape = Enum.PartType.Block,
			Size = Vector3.new(3, 14, 3),
			Height = 7,
			Color = Color3.fromRGB(105, 64, 40),
			Material = Enum.Material.Wood,
		},
		{
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(12, 12, 12),
			Height = 16,
			Color = Color3.fromRGB(58, 125, 21),
			Material = Enum.Material.Grass,
		},
	},
	Rock = {
		{
			Shape = Enum.PartType.Block,
			Size = Vector3.new(8, 6, 8),
			Height = 3,
			Color = Color3.fromRGB(120, 120, 120),
			Material = Enum.Material.Slate,
		},
	},
	OreRock = {
		{
			Shape = Enum.PartType.Block,
			Size = Vector3.new(7, 6, 7),
			Height = 3,
			Color = Color3.fromRGB(90, 80, 75),
			Material = Enum.Material.Slate,
		},
		{
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(3, 3, 3),
			Height = 6,
			Color = Color3.fromRGB(214, 125, 48),
			Material = Enum.Material.Metal,
		},
	},
	Bush = {
		{
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(6, 6, 6),
			Height = 2.5,
			Color = Color3.fromRGB(76, 140, 50),
			Material = Enum.Material.Grass,
		},
	},
}

const ResourceNodeController = {}

local nodesFolder: Folder? = nil

-- Clone of ServerStorage.ResourceModels.<NodeId> (pivot at its base), or a placeholder
local function createModel(id: NodeId, baseCFrame: CFrame): Model
	local folder = ServerStorage:FindFirstChild("ResourceModels")
	local template = folder and folder:FindFirstChild(id)

	local model: Model
	if template and template:IsA("Model") then
		model = template:Clone()
	else
		model = Instance.new("Model")
		for _, spec in PLACEHOLDERS[id] do
			local part = Instance.new("Part")
			part.Anchored = true
			part.Shape = spec.Shape
			part.Size = spec.Size
			part.Color = spec.Color
			part.Material = spec.Material
			part.CFrame = CFrame.new(0, spec.Height, 0)
			part.Parent = model
		end
		model.WorldPivot = CFrame.new()
	end

	model.Name = id
	model:SetAttribute("NodeId", id)
	model:PivotTo(baseCFrame)

	return model
end

local function pickNode(area: WildAreaInfo, rng: Random): NodeId
	local total = 0
	for _, weight in area.NodeWeights do
		total += weight
	end

	local roll = rng:NextNumber() * total
	for id, weight in area.NodeWeights do
		roll -= weight
		if roll <= 0 then
			return id
		end
	end

	return "Tree"
end

-- Scatters nodes over every part in workspace.Wilds.<AreaId>.Ground
local function generate(area: WildAreaInfo, folder: Folder)
	local ground = workspace:WaitForChild("Wilds"):WaitForChild(area.Id):WaitForChild("Ground")
	local rng = Random.new(SEED)

	for _, part in ground:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end

		local size = part.Size
		for ix = 0, math.floor(size.X / CELL_SIZE) - 1 do
			for iz = 0, math.floor(size.Z / CELL_SIZE) - 1 do
				if rng:NextNumber() >= area.SpawnChance then
					continue
				end

				local x = (ix + 0.5) * CELL_SIZE - size.X / 2 + rng:NextNumber(-JITTER, JITTER)
				local z = (iz + 0.5) * CELL_SIZE - size.Z / 2 + rng:NextNumber(-JITTER, JITTER)
				local baseCFrame = part.CFrame
					* CFrame.new(x, size.Y / 2, z)
					* CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0)

				createModel(pickNode(area, rng), baseCFrame).Parent = folder
			end
		end
	end
end

-- Info for a node that is currently gatherable, otherwise nil
function ResourceNodeController.GetInfo(node: Instance): NodeInfo?
	if not nodesFolder or node.Parent ~= nodesFolder then
		return nil
	end

	local id = node:GetAttribute("NodeId")
	if typeof(id) ~= "string" then
		return nil
	end

	return (ResourceData.NODES :: { [string]: NodeInfo })[id]
end

-- Hides the node until its respawn time has passed
function ResourceNodeController.Deplete(node: Instance)
	local info = ResourceNodeController.GetInfo(node)
	local folder = nodesFolder
	if not info or not folder then
		return
	end

	node.Parent = nil
	task.delay(info.RespawnTime, function()
		node.Parent = folder
	end)
end

function ResourceNodeController.Start()
	if nodesFolder then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "Nodes"
	folder.Parent = workspace:WaitForChild("Wilds")
	nodesFolder = folder

	for _, area in WildAreaData.AREAS do
		generate(area, folder)
	end
end

return ResourceNodeController
