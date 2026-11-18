--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const BagSizes = require(Shared.Inventory.BagSizes)
const InventoryTypes = require(Shared.Inventory.InventoryTypes)
const ItemsList = require(Shared.Inventory.ItemsList)
const ItemCursor = require(script.Parent.Parent.ItemCursor)

const create = vide.create
const derive = vide.derive
const indexes = vide.indexes
const cleanup = vide.cleanup

type Bag = InventoryTypes.Bag

type Props = {
	Name: string,
	LayoutOrder: number,
	Columns: number,
	Bag: () -> Bag?,
	-- Which bag this is for MoveItems ("Backpack", "Storage", "Hut/<id>", "Colonist/<id>");
	-- without it the grid is read-only
	Ref: (() -> string?)?,
}

const TEXT_COLOR = Color3.new(1, 1, 1)
const SLOT_COLOR = Color3.fromRGB(55, 55, 55)
const SELECTED_COLOR = Color3.fromRGB(70, 90, 140)
const SLOT_SIZE = 56
const SLOT_GAP = 4

local function getSlotCount(bag: Bag?): number
	local itemType = bag and ItemsList.GetItemName(bag.UniqueID)
	return if itemType then BagSizes[itemType] or 0 else 0
end

-- Grid of slots for a bag; the slot count is fixed by the bag type.
-- Slots are buttons: left click picks up / places, right click splits / places one,
-- Dragging with the left button while holding a stack spreads it over the slots dragged across.
local function BagGrid(props: Props)
	ItemCursor.Start()

	local getRef: () -> string? = props.Ref or function(): string?
		return nil
	end

	-- The bag with moves still waiting on the server already applied
	local view = derive(function()
		return ItemCursor.View(getRef(), props.Bag())
	end)

	-- Rebuilt when the bag arrives or changes type, since the slot count comes from the bag
	local slotNumbers = derive(function()
		local numbers = {}
		for slot = 1, getSlotCount(props.Bag()) do
			numbers[slot] = slot
		end
		return numbers
	end)

	local function press(slot: number, button: ItemCursor.Button)
		local ref = getRef()
		if ref then
			ItemCursor.Press(ref, slot, button)
		end
	end

	local slots = indexes(slotNumbers, function(_, slot: number)
		-- "Wood\n12" for what the slot shows, or "" when empty
		local text = function(): string
			local uniqueID, quantity = ItemCursor.GetShown(getRef(), view(), slot)
			return if uniqueID
				then `{ItemsList.GetDisplayName(uniqueID) or "?"}\n{quantity}`
				else ""
		end

		return create("TextButton")({
			Name = `Slot{slot}`,
			LayoutOrder = slot,
			AutoButtonColor = false,
			BackgroundColor3 = function()
				local _, _, selected = ItemCursor.GetShown(getRef(), view(), slot)
				return if selected then SELECTED_COLOR else SLOT_COLOR
			end,
			TextColor3 = TEXT_COLOR,
			TextSize = 13,
			TextWrapped = true,
			Text = text,

			MouseButton1Down = function()
				press(slot, "Left")
			end,
			MouseButton2Down = function()
				press(slot, "Right")
			end,
			MouseEnter = function()
				local ref = getRef()
				if ref then
					ItemCursor.Hover(ref, slot)
				end
			end,

			create("UICorner")({}),
		})
	end)

	local grid = create("Frame")({
		Name = props.Name,
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.fromOffset(props.Columns * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,

		create("UIGridLayout")({
			SortOrder = Enum.SortOrder.LayoutOrder,
			CellSize = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
			CellPadding = UDim2.fromOffset(SLOT_GAP, SLOT_GAP),
		}),

		slots,
	})

	ItemCursor.Register(grid, getRef)
	cleanup(function()
		ItemCursor.Unregister(grid)
	end)

	return grid
end

-- Panel width that fits a grid with this many columns plus 12px padding each side
local function getPanelWidth(columns: number): number
	return columns * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP + 24
end

return {
	BagGrid = BagGrid,
	GetPanelWidth = getPanelWidth,
	GetSlotCount = getSlotCount,
}
