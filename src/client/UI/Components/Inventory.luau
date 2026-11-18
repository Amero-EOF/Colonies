--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const UserInputService = game:GetService("UserInputService")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const BagMoves = require(Shared.Inventory.BagMoves)
const InventoryTypes = require(Shared.Inventory.InventoryTypes)
const ColonyStore = require(script.Parent.Parent.Parent.Colony.ColonyStore)
const BagGrid = require(script.Parent.BagGrid)

const create = vide.create
const source = vide.source
const spring = vide.spring
const cleanup = vide.cleanup

type Bag = InventoryTypes.Bag

const TOGGLE_KEY = Enum.KeyCode.B
const TEXT_COLOR = Color3.new(1, 1, 1)
const SPRING_PERIOD = 0.25
const MARGIN = 16
const BUTTON_SIZE = Vector2.new(200, 40)
-- Gap between the bag and the storage panel when both are open side by side
const SIDE_GAP = 8

-- Inventory button in the bottom right; the bag panel grows out of it to the screen centre.
-- It also opens beside the storage panel so items can be moved between the two.
local function Inventory()
	local open = source(false)
	local shown = function(): boolean
		return open() or ColonyStore.StorageOpen()
	end
	local progress = spring(function()
		return if shown() then 1 else 0
	end, SPRING_PERIOD)

	local backpack = function(): Bag?
		return ColonyStore.Inventory().Bags[1]
	end

	local usedSlots = function(): string
		local bag = backpack()
		return `{if bag then #bag.Items else 0}/{BagGrid.GetSlotCount(bag)}`
	end

	local connection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == TOGGLE_KEY then
			open(not open())
		end
	end)
	cleanup(function()
		connection:Disconnect()
	end)

	-- The button's top-left corner, where the closed panel shrinks to
	local cornerPosition = UDim2.new(1, -MARGIN - BUTTON_SIZE.X, 1, -MARGIN - BUTTON_SIZE.Y)
	-- Screen centre, or just right of it when the storage panel takes the left half
	local openAnchor = function(): Vector2
		return if ColonyStore.StorageOpen() then Vector2.new(0, 0.5) else Vector2.new(0.5, 0.5)
	end
	local openPosition = function(): UDim2
		return if ColonyStore.StorageOpen()
			then UDim2.new(0.5, SIDE_GAP / 2, 0.5, 0)
			else UDim2.fromScale(0.5, 0.5)
	end

	return {
		create("Frame")({
			Name = "InventoryPanel",
			AnchorPoint = function()
				return Vector2.new(0, 0):Lerp(openAnchor(), progress())
			end,
			Position = function()
				return cornerPosition:Lerp(openPosition(), progress())
			end,
			Size = UDim2.fromOffset(BagGrid.GetPanelWidth(5), 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Color3.fromRGB(30, 30, 30),
			BackgroundTransparency = 0.1,
			Visible = function()
				return progress() > 0.01
			end,

			create("UIScale")({
				Scale = function()
					return math.max(progress(), 0)
				end,
			}),
			create("UICorner")({}),
			create("UIPadding")({
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 12),
				PaddingTop = UDim.new(0, 12),
				PaddingBottom = UDim.new(0, 12),
			}),
			create("UIListLayout")({
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 8),
			}),

			create("TextLabel")({
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 22),
				BackgroundTransparency = 1,
				TextColor3 = TEXT_COLOR,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextSize = 18,
				Text = function()
					return `Bag {usedSlots()}`
				end,
			}),

			BagGrid.BagGrid({
				Name = "Backpack",
				LayoutOrder = 2,
				Columns = 5,
				Bag = backpack,
				Ref = function(): string?
					return BagMoves.BACKPACK
				end,
			}),
		}),

		create("TextButton")({
			Name = "InventoryButton",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -MARGIN, 1, -MARGIN),
			Size = UDim2.fromOffset(BUTTON_SIZE.X, BUTTON_SIZE.Y),
			BackgroundColor3 = Color3.fromRGB(45, 70, 45),
			TextColor3 = TEXT_COLOR,
			TextSize = 18,
			Text = function()
				return `Inventory (B) {usedSlots()}`
			end,

			Activated = function()
				open(not open())
			end,

			create("UICorner")({}),
		}),
	}
end

return Inventory
