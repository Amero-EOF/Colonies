--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const BuildingData = require(Shared.Buildings.BuildingData)
const BuildingPlacement = require(Shared.Buildings.BuildingPlacement)
const BuildingUnlocks = require(Shared.Buildings.BuildingUnlocks)
const YardData = require(Shared.Yard.YardData)
const ColonyStore = require(script.Parent.ColonyStore)

-- The stage one node shows (0 = not unlocked yet), and the model drawing it
type DrawnNode = {
	Stage: number,
	Model: Model?,
}

type DrawnYard = {
	Pivot: CFrame,
	Holder: Model,
	Nodes: { [number]: DrawnNode },
}

type Draw = (model: Model, base: CFrame, stage: number, random: Random) -> ()

-- Seconds between regrowth checks (models are only rebuilt when a node's stage changes)
const UPDATE_INTERVAL = 1

const BARK = Color3.fromRGB(105, 75, 45)
const CUT_WOOD = Color3.fromRGB(200, 165, 110)
const SAPLING_GREEN = Color3.fromRGB(125, 185, 85)
const LEAF_GREEN = Color3.fromRGB(60, 130, 55)
const DARK_LEAF_GREEN = Color3.fromRGB(45, 105, 50)
const STONE_GREY = Color3.fromRGB(125, 125, 130)
const DARK_STONE = Color3.fromRGB(95, 95, 100)
const RUBBLE_GREY = Color3.fromRGB(110, 105, 100)
const ORE_COLOR = Color3.fromRGB(205, 140, 80)

-- Draws the nodes of every resource yard (Forester's Hut trees, Mine rocks) of the local
-- player's colony: workspace.MyColony.Yards.<BuildingId>.Node<N>. Regrowth comes from each
-- node's HarvestedAt and the server clock (YardData.GetStage), so nothing is sent while they
-- grow back.
const YardView = {}

local started = false

const drawn: { [string]: DrawnYard } = {}
local holderFolder: Folder? = nil

local function addPart(
	model: Model,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = material
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

-- An upright cylinder standing on `base` (cylinders run along X, so it is turned)
local function addTrunk(model: Model, base: CFrame, height: number, width: number, color: Color3)
	addPart(
		model,
		Vector3.new(height, width, width),
		base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		Enum.Material.Wood,
		Enum.PartType.Cylinder
	)
end

local function addLeaves(model: Model, centre: CFrame, size: number, color: Color3)
	addPart(
		model,
		Vector3.new(size, size, size),
		centre,
		color,
		Enum.Material.Grass,
		Enum.PartType.Ball
	)
end

-- Stump, sapling, young tree, grown tree
local function drawTree(model: Model, base: CFrame, stage: number, random: Random)
	if stage <= 1 then
		addTrunk(model, base, 1.2, 2, BARK)
		addTrunk(model, base * CFrame.new(0, 1.2, 0), 0.1, 1.6, CUT_WOOD)
	elseif stage == 2 then
		-- Replanted beside the old stump
		addTrunk(model, base * CFrame.new(0.9, 0, 0.4), 0.5, 1.6, BARK)
		addTrunk(model, base, 2.4, 0.3, BARK)
		addLeaves(model, base * CFrame.new(0, 2.8, 0), 1.8, SAPLING_GREEN)
	elseif stage == 3 then
		local height = random:NextNumber(4.5, 5.5)
		addTrunk(model, base, height, 0.9, BARK)
		addLeaves(model, base * CFrame.new(0, height + 1.2, 0), 4.6, LEAF_GREEN)
	else
		local height = random:NextNumber(8, 10)
		addTrunk(model, base, height, 1.8, BARK)
		addLeaves(model, base * CFrame.new(0, height + 2, 0), 8, LEAF_GREEN)
		addLeaves(model, base * CFrame.new(2.4, height + 0.4, 1), 5.2, DARK_LEAF_GREEN)
		addLeaves(model, base * CFrame.new(-2, height + 0.8, -1.6), 5.6, DARK_LEAF_GREEN)
		addLeaves(model, base * CFrame.new(0, height + 5, 0), 4.6, LEAF_GREEN)
	end
end

local function addRock(model: Model, cframe: CFrame, size: Vector3, color: Color3)
	addPart(model, size, cframe, color, Enum.Material.Slate)
end

-- Rubble, loose rock, solid rock with ore showing
local function drawRock(model: Model, base: CFrame, stage: number, random: Random)
	if stage <= 1 then
		for i = 1, 4 do
			local size = random:NextNumber(0.6, 1.1)
			local spot = base
				* CFrame.Angles(0, i * math.pi / 2 + random:NextNumber(-0.5, 0.5), 0)
				* CFrame.new(random:NextNumber(0.6, 1.8), size / 2, 0)
				* CFrame.Angles(0, random:NextNumber(0, math.pi), 0)
			addRock(model, spot, Vector3.new(size, size, size), RUBBLE_GREY)
		end
	elseif stage == 2 then
		addRock(model, base * CFrame.new(0, 1, 0), Vector3.new(2.6, 2, 2.4), STONE_GREY)
		addRock(
			model,
			base * CFrame.new(1.5, 0.5, 0.8) * CFrame.Angles(0, 0.6, 0),
			Vector3.new(1.2, 1, 1.2),
			DARK_STONE
		)
	else
		local height = random:NextNumber(3.4, 4.2)
		addRock(model, base * CFrame.new(0, height / 2, 0), Vector3.new(4.6, height, 4), STONE_GREY)
		addRock(
			model,
			base * CFrame.new(2.4, 1.1, 1) * CFrame.Angles(0, 0.5, 0),
			Vector3.new(2.6, 2.2, 2.4),
			DARK_STONE
		)
		addRock(
			model,
			base * CFrame.new(-1.8, 0.8, -1.8) * CFrame.Angles(0, -0.4, 0),
			Vector3.new(2.2, 1.6, 2),
			DARK_STONE
		)
		-- Ore veins on the faces
		for _ = 1, 4 do
			local side = if random:NextNumber() < 0.5 then -1 else 1
			local vein = base
				* CFrame.new(
					random:NextNumber(-1.8, 1.8),
					random:NextNumber(0.8, height - 0.6),
					side * 2
				)
			addPart(model, Vector3.new(0.7, 0.5, 0.25), vein, ORE_COLOR, Enum.Material.Metal)
		end
	end
end

const DRAW: { [string]: Draw } = {
	Trees = drawTree,
	Rocks = drawRock,
}

local function buildNode(
	pivot: CFrame,
	info: YardData.YardInfo,
	node: number,
	stage: number
): Model?
	local position = YardData.GetNodePosition(info, node)
	local draw = DRAW[info.Kind]
	if not position or not draw then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = `Node{node}`
	model:SetAttribute("Kind", info.Kind)
	model:SetAttribute("Stage", stage)
	model:SetAttribute("StageName", info.Stages[stage])
	-- The same node always looks the same at a stage
	local random = Random.new(node * 7919 + stage)
	local base = pivot
		* CFrame.new(position.X, YardData.GROUND_HEIGHT, position.Z)
		* CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
	draw(model, base, stage, random)
	return model
end

local function clearYard(yard: DrawnYard)
	yard.Holder:Destroy()
	table.clear(yard.Nodes)
end

-- Redraws nodes whose stage changed; everything when a hut moved
local function refresh()
	local folder = holderFolder
	if not folder then
		return
	end
	local now = workspace:GetServerTimeNow()
	local yards = ColonyStore.Yards()
	local seen: { [string]: boolean } = {}

	for _, saved in ColonyStore.Buildings() do
		local placement = saved.Placement
		local nodes = yards[saved.Id]
		local component = BuildingData[saved.Id].Components.Yard
		local info = component and YardData.GetInfo(component.Kind)
		if
			not placement
			or not nodes
			or not info
			or not BuildingUnlocks.IsBuilt(saved.Id, saved.Level)
		then
			continue
		end
		seen[saved.Id] = true

		local pivot = BuildingPlacement.ToCFrame(placement)
		local old = drawn[saved.Id]
		if old and old.Pivot ~= pivot then
			clearYard(old)
			drawn[saved.Id] = nil
		end
		local current: DrawnYard = drawn[saved.Id]
			or {
				Pivot = pivot,
				Holder = Instance.new("Model"),
				Nodes = {},
			}
		if not current.Holder.Parent then
			current.Holder.Name = saved.Id
			current.Holder.Parent = folder
		end
		drawn[saved.Id] = current

		local count = YardData.GetNodeCount(info, saved.Level)
		for node = 1, YardData.GetMaxNodes(info) do
			local stage = if node <= count
				then YardData.GetStage(info, nodes[node] or {}, now)
				else 0
			local entry = current.Nodes[node]
			if entry and entry.Stage == stage then
				continue
			end
			if entry and entry.Model then
				entry.Model:Destroy()
			end
			local model = if stage > 0 then buildNode(pivot, info, node, stage) else nil
			if model then
				model.Parent = current.Holder
			end
			current.Nodes[node] = { Stage = stage, Model = model }
		end
	end

	for id, yard in drawn do
		if not seen[id] then
			clearYard(yard)
			drawn[id] = nil
		end
	end
end

function YardView.Start()
	if started then
		return
	end
	started = true

	local colonyFolder = workspace:FindFirstChild("MyColony") or workspace
	local folder = Instance.new("Folder")
	folder.Name = "Yards"
	folder.Parent = colonyFolder
	holderFolder = folder

	vide.root(function()
		vide.effect(function()
			ColonyStore.Buildings()
			ColonyStore.Yards()
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

return YardView
