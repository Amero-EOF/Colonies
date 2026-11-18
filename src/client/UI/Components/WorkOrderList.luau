--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const BuildingData = require(Shared.Buildings.BuildingData)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const ColonistStore = require(script.Parent.Parent.Parent.Colony.ColonistStore)
const ColonyStore = require(script.Parent.Parent.Parent.Colony.ColonyStore)
const WorkOrderMaterials = require(script.Parent.Parent.Parent.Colony.WorkOrderMaterials)

const create = vide.create
const show = vide.show
const indexes = vide.indexes

type WorkOrder = ColonyTypes.WorkOrder

const TEXT_COLOR = Color3.new(1, 1, 1)
const MUTED_COLOR = Color3.fromRGB(170, 170, 170)
const CARD_COLOR = Color3.fromRGB(45, 45, 45)
const BAR_BACK_COLOR = Color3.fromRGB(25, 25, 25)
const BAR_COLOR = Color3.fromRGB(90, 160, 90)
const READY_COLOR = Color3.fromRGB(120, 200, 120)
const SHORT_COLOR = Color3.fromRGB(230, 170, 90)
const CARD_HEIGHT = 82

local function getTitle(order: WorkOrder): string
	local name = BuildingData[order.BuildingId].Name
	local kind = if order.Kind == "Build"
		then `Build {name}`
		else `Upgrade {name} to level {order.TargetLevel}`
	return `#{order.Id}  {kind}`
end

-- Materials the rest of the order needs against what's ready (Builder's Hut storage + the
-- Builder's inventory), e.g. "Needs: Stone 12/32, Wood 0/48". Second value: all ready.
local function getMaterials(order: WorkOrder): (string, boolean)
	local entries = {}
	local ready = true
	for _, material in WorkOrderMaterials.Get(order) do
		ready = ready and material.Ready >= material.Remaining
		table.insert(entries, `{material.ItemType} {material.Ready}/{material.Remaining}`)
	end
	if #entries == 0 then
		return "All materials used", true
	end
	return `Needs: {table.concat(entries, ", ")}`, ready
end

-- Who is on it and what they're doing right now
local function getWorker(order: WorkOrder): string
	local builder = ColonistStore.Get(order.BuilderId)
	if not builder then
		return "Waiting for a Builder"
	end
	local status = ColonistStore.GetStatus(builder.Id)
	return if status ~= "" then `{builder.Name}: {status}` else builder.Name
end

local function card(order: () -> WorkOrder, index: number)
	return create("Frame")({
		LayoutOrder = index,
		Size = UDim2.new(1, -8, 0, CARD_HEIGHT),
		BackgroundColor3 = CARD_COLOR,

		create("UICorner")({}),
		create("UIPadding")({
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
			PaddingTop = UDim.new(0, 6),
		}),

		create("TextLabel")({
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			TextColor3 = TEXT_COLOR,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextSize = 15,
			Font = Enum.Font.GothamMedium,
			Text = function()
				return getTitle(order())
			end,
		}),
		create("TextLabel")({
			Position = UDim2.fromOffset(0, 20),
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			TextColor3 = MUTED_COLOR,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextSize = 13,
			Text = function()
				return getWorker(order())
			end,
		}),

		create("TextLabel")({
			Position = UDim2.fromOffset(0, 38),
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			TextColor3 = function()
				local _, ready = getMaterials(order())
				return if ready then READY_COLOR else SHORT_COLOR
			end,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextSize = 13,
			Text = function()
				return (getMaterials(order()))
			end,
		}),

		-- Parts placed out of the total
		create("Frame")({
			Position = UDim2.fromOffset(0, 60),
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundColor3 = BAR_BACK_COLOR,

			create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
			create("Frame")({
				Size = function()
					local current = order()
					return UDim2.fromScale(current.Progress / math.max(current.TotalParts, 1), 1)
				end,
				BackgroundColor3 = BAR_COLOR,
				create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
			}),
			create("TextLabel")({
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				TextColor3 = TEXT_COLOR,
				TextSize = 12,
				Text = function()
					local current = order()
					return `{current.Progress}/{current.TotalParts} parts`
				end,
			}),
		}),
	})
end

-- Scrolling list of every work order, oldest first, with materials, progress and the Builder's status
local function WorkOrderList(layoutOrder: number?, height: number?)
	return create("ScrollingFrame")({
		Name = "WorkOrders",
		LayoutOrder = layoutOrder or 0,
		Size = if height then UDim2.new(1, 0, 0, height) else UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,

		create("UIListLayout")({
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),

		show(function()
			return #ColonyStore.WorkOrders() == 0
		end, function()
			return create("TextLabel")({
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				TextColor3 = MUTED_COLOR,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				TextSize = 15,
				Text = "No work orders. Place a building or request an upgrade.",
			})
		end),

		indexes(ColonyStore.WorkOrders, card),
	})
end

return WorkOrderList
