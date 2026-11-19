--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const BuildingData = require(Shared.Buildings.BuildingData)
const BuildingTypes = require(Shared.Buildings.BuildingTypes)
const BuildingUnlocks = require(Shared.Buildings.BuildingUnlocks)
const ItemsList = require(Shared.Inventory.ItemsList)
const DayCycle = require(Shared.Time.DayCycle)
const YardData = require(Shared.Yard.YardData)
const ColonistStore = require(script.Parent.Parent.Parent.Colony.ColonistStore)
const ColonyStore = require(script.Parent.Parent.Parent.Colony.ColonyStore)
const WorkOrderMaterials = require(script.Parent.Parent.Parent.Colony.WorkOrderMaterials)

const create = vide.create
const show = vide.show
const source = vide.source
const cleanup = vide.cleanup

type BuildingId = BuildingTypes.BuildingId
type Node = YardData.Node
type YardInfo = YardData.YardInfo

const TEXT_COLOR = Color3.new(1, 1, 1)
const MUTED_COLOR = Color3.fromRGB(170, 170, 170)
const BAR_BACK_COLOR = Color3.fromRGB(25, 25, 25)
const BAR_COLOR = Color3.fromRGB(235, 200, 90)
-- A node's chip goes from this colour (just worked) to its kind's colour (ready)
const WORKED_COLOR = Color3.fromRGB(75, 65, 55)
const DEFAULT_READY_COLOR = Color3.fromRGB(90, 160, 90)
const READY_COLORS: { [string]: Color3 } = {
	Trees = Color3.fromRGB(70, 145, 65),
	Rocks = Color3.fromRGB(125, 130, 145),
}
const CHIP_SIZE = Vector2.new(54, 40)
-- Seconds between regrowth updates
const TICK = 0.5

-- Chips are made once for the largest yard; smaller ones hide the rest
local function getMaxChips(): number
	local most = 0
	for _, info in YardData.YARDS do
		most = math.max(most, YardData.GetMaxNodes(info))
	end
	return most
end

local function capitalise(text: string): string
	return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

local function getItemName(itemType: string): string
	local id = ItemsList.GetItemId(itemType)
	return (id and ItemsList.GetDisplayName(id)) or itemType
end

-- "3-5 Wood", "2-4 Stone, sometimes 1-2 Ore"
local function describeYields(info: YardInfo): string
	local parts = {}
	for _, yield in info.Yields do
		local amount = if yield.Min == yield.Max then `{yield.Min}` else `{yield.Min}-{yield.Max}`
		local sometimes = if yield.Chance < 1 then "sometimes " else ""
		table.insert(parts, `{sometimes}{amount} {getItemName(yield.Item)}`)
	end
	return table.concat(parts, ", ")
end

-- The "Trees" / "Rocks" tab of a building with a resource yard (Forester's Hut, Mine): one chip
-- per node with its stage and regrowth, what the nodes give, what is in the hut's storage and
-- what its worker is doing. `id` is the building the panel is open on.
local function YardPanel(id: () -> BuildingId, layoutOrder: number)
	local now = source(workspace:GetServerTimeNow())

	local elapsed = 0
	local connection = RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime
		if elapsed >= TICK then
			elapsed = 0
			now(workspace:GetServerTimeNow())
		end
	end)
	cleanup(connection)

	local getInfo = function(): YardInfo?
		local yard = BuildingData[id()].Components.Yard
		return if yard then YardData.GetInfo(yard.Kind) else nil
	end
	local level = function(): number
		local saved = ColonyStore.GetBuilding(id())
		return if saved then saved.Level else 0
	end
	local built = function(): boolean
		return BuildingUnlocks.IsBuilt(id(), level())
	end
	local count = function(): number
		local info = getInfo()
		return if info then YardData.GetNodeCount(info, level()) else 0
	end
	local getNode = function(node: number): Node
		local nodes = ColonyStore.Yards()[id()]
		return (nodes and nodes[node]) or {}
	end

	local function summaryLine(): string
		local info = getInfo()
		if not info then
			return ""
		end
		local ready = 0
		for node = 1, count() do
			if YardData.IsReady(info, getNode(node), now()) then
				ready += 1
			end
		end
		local lastStage = string.lower(info.Stages[#info.Stages])
		return `{capitalise(info.NodePlural)}: {ready} of {count()} are a {lastStage}`
	end

	local function nextLine(): string
		local info = getInfo()
		if not info then
			return ""
		end
		local soonest = math.huge
		for node = 1, count() do
			local left = YardData.GetTimeLeft(info, getNode(node), now())
			if left > 0 then
				soonest = math.min(soonest, left)
			end
		end
		if soonest == math.huge then
			return `Every {info.NodeName} is ready to be worked.`
		end
		local hours = math.max(math.ceil(DayCycle.HoursBetween(now(), now() + soonest)), 1)
		return `The next {info.NodeName} is ready in about {hours} h.`
	end

	local function yieldLine(): string
		local info = getInfo()
		if not info then
			return ""
		end
		local text = `Each {info.NodeName} gives {describeYields(info)}.`
		if level() < YardData.MAX_LEVEL then
			text ..= ` Every level adds {info.NodesPerLevel} more {info.NodePlural}.`
		end
		return text
	end

	local function storageLine(): string
		local info = getInfo()
		if not info then
			return ""
		end
		local bag = ColonyStore.HutStorage()[id()]
		local parts = {}
		for _, yield in info.Yields do
			local itemId = ItemsList.GetItemId(yield.Item)
			local amount = if itemId then WorkOrderMaterials.CountItem(bag, itemId) else 0
			table.insert(parts, `{getItemName(yield.Item)} {amount}`)
		end
		return `In storage: {table.concat(parts, ", ")}`
	end

	local function workerLine(): string
		for _, colonist in ColonistStore.Colonists() do
			if colonist.Workplace == id() then
				local current = ColonistStore.GetStatus(colonist.Id)
				return if current ~= "" then `{colonist.Name}: {current}` else colonist.Name
			end
		end
		local workplace = BuildingData[id()].Components.Workplace
		local job = if workplace then workplace.Jobs[1] else "worker"
		return `No {job} yet`
	end

	local function line(name: string, order: number, text: () -> string, color: Color3)
		return create("TextLabel")({
			Name = name,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			TextSize = 13,
			Text = text,
		})
	end

	-- One node: its stage name over a regrowth bar, coloured by how far along it is
	local function chip(node: number)
		local progress = function(): number
			local info = getInfo()
			return if info then YardData.GetProgress(info, getNode(node), now()) else 0
		end
		return create("Frame")({
			Name = `Node{node}`,
			LayoutOrder = node,
			Visible = function()
				return node <= count()
			end,
			BackgroundColor3 = function()
				local info = getInfo()
				local ready = (info and READY_COLORS[info.Kind]) or DEFAULT_READY_COLOR
				return WORKED_COLOR:Lerp(ready, progress())
			end,
			BorderSizePixel = 0,

			create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
			create("TextLabel")({
				Size = UDim2.new(1, 0, 1, -6),
				BackgroundTransparency = 1,
				TextColor3 = TEXT_COLOR,
				TextStrokeTransparency = 0.5,
				TextWrapped = true,
				TextSize = 10,
				Font = Enum.Font.GothamMedium,
				Text = function()
					local info = getInfo()
					if not info then
						return ""
					end
					return info.Stages[YardData.GetStage(info, getNode(node), now())]
				end,
			}),
			create("Frame")({
				Name = "Progress",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -2),
				Size = UDim2.new(0.8, 0, 0, 3),
				BackgroundColor3 = BAR_BACK_COLOR,
				BorderSizePixel = 0,
				Visible = function()
					return progress() < 1
				end,
				create("Frame")({
					Size = function()
						return UDim2.fromScale(progress(), 1)
					end,
					BackgroundColor3 = BAR_COLOR,
					BorderSizePixel = 0,
				}),
			}),
		})
	end

	local function chips()
		local children = {}
		for node = 1, getMaxChips() do
			table.insert(children, chip(node))
		end
		return create("Frame")({
			Name = "Nodes",
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,

			create("UIGridLayout")({
				CellSize = UDim2.fromOffset(CHIP_SIZE.X, CHIP_SIZE.Y),
				CellPadding = UDim2.fromOffset(4, 4),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			children,
		})
	end

	return create("Frame")({
		Name = "YardPanel",
		LayoutOrder = layoutOrder,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,

		create("UIListLayout")({
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),

		show(function()
			return not built()
		end, function()
			return line("NotBuilt", 1, function()
				local info = getInfo()
				local plural = if info then info.NodePlural else "yard"
				return `The {plural} can be worked once the {BuildingData[id()].Name} is built.`
			end, MUTED_COLOR)
		end),

		show(built, function()
			return line("Summary", 1, summaryLine, TEXT_COLOR)
		end),
		show(built, chips),
		show(built, function()
			return line("Next", 3, nextLine, MUTED_COLOR)
		end),

		line("Yield", 4, yieldLine, MUTED_COLOR),
		line("Storage", 5, storageLine, TEXT_COLOR),
		line("Worker", 6, workerLine, MUTED_COLOR),
	})
end

return YardPanel
