--!strict

const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const BuildingData = require(Shared.Buildings.BuildingData)
const ItemsList = require(Shared.Inventory.ItemsList)
const ColonistStore = require(script.Parent.Parent.Parent.Colony.ColonistStore)
const ColonyStore = require(script.Parent.Parent.Parent.Colony.ColonyStore)
const WorkOrderMaterials = require(script.Parent.Parent.Parent.Colony.WorkOrderMaterials)

const cleanup = vide.cleanup
const create = vide.create
const derive = vide.derive
const indexes = vide.indexes
const show = vide.show
const source = vide.source

-- One line of the scroll: what the order still needs vs what the player carries
type Row = {
	ItemType: string,
	-- Still to bring: remaining cost minus what the Builder's Hut holds and the Builder carries
	Needed: number,
	-- In the player's backpack
	Carried: number,
}

const SCROLL_ITEM = "WorkScroll"
const TEXT_COLOR = Color3.new(1, 1, 1)
const MUTED_COLOR = Color3.fromRGB(180, 180, 180)
const ENOUGH_COLOR = Color3.fromRGB(120, 210, 120)
const SOME_COLOR = Color3.fromRGB(235, 205, 80)
const NONE_COLOR = Color3.fromRGB(225, 90, 80)
const ROW_HEIGHT = 22

const player = Players.LocalPlayer

-- Green: the player carries enough (or nothing more is needed), yellow: some, red: none
local function getColor(row: Row): Color3
	if row.Carried >= row.Needed then
		return ENOUGH_COLOR
	elseif row.Carried > 0 then
		return SOME_COLOR
	end
	return NONE_COLOR
end

local function isScroll(child: Instance): boolean
	return if child:IsA("Tool") then child:GetAttribute("ItemType") == SCROLL_ITEM else false
end

-- True while the local character holds the Work Scroll (Tool equipped from the hotbar)
local function holdingSource(): () -> boolean
	local holding = source(false)
	local characterConnections: { RBXScriptConnection } = {}

	local function watch(character: Model?)
		for _, connection in characterConnections do
			connection:Disconnect()
		end
		table.clear(characterConnections)
		if not character then
			holding(false)
			return
		end

		local function refresh()
			local found = false
			for _, child in character:GetChildren() do
				if isScroll(child) then
					found = true
					break
				end
			end
			holding(found)
		end
		table.insert(characterConnections, character.ChildAdded:Connect(refresh))
		table.insert(characterConnections, character.ChildRemoved:Connect(refresh))
		refresh()
	end

	local characterAdded = player.CharacterAdded:Connect(watch)
	watch(player.Character)
	cleanup(function()
		characterAdded:Disconnect()
		watch(nil)
	end)

	return holding
end

local function row(value: () -> Row, index: number)
	local label = function(name: string, x: number, width: number, text: () -> string)
		return create("TextLabel")({
			Name = name,
			Position = UDim2.fromScale(x, 0),
			Size = UDim2.fromScale(width, 1),
			BackgroundTransparency = 1,
			TextColor3 = function()
				return getColor(value())
			end,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 14,
			Text = text,
		})
	end

	return create("Frame")({
		Name = `Material_{index}`,
		LayoutOrder = index,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundTransparency = 1,

		label("Item", 0, 0.36, function()
			return value().ItemType
		end),
		label("Needed", 0.36, 0.32, function()
			local needed = value().Needed
			return if needed > 0 then `Needs {needed}` else "Ready"
		end),
		label("Carried", 0.68, 0.32, function()
			return `You have {value().Carried}`
		end),
	})
end

-- MineColonies' Resource Scroll: while the Work Scroll is held, lists what the Builder's current
-- work order still needs against what the player carries
local function WorkScrollPanel()
	local holding = holdingSource()

	local order = derive(function()
		return WorkOrderMaterials.GetCurrentOrder()
	end)

	local rows = derive(function(): { Row }
		local current = order()
		if not current then
			return {}
		end
		local backpack = ColonyStore.Inventory().Bags[1]
		local list: { Row } = {}
		for _, material in WorkOrderMaterials.Get(current) do
			local id = ItemsList.GetItemId(material.ItemType)
			table.insert(list, {
				ItemType = material.ItemType,
				Needed = material.Remaining - material.Ready,
				Carried = if id then WorkOrderMaterials.CountItem(backpack, id) else 0,
			})
		end
		return list
	end)

	local title = function(): string
		local current = order()
		if not current then
			return "No work orders right now"
		end
		local name = BuildingData[current.BuildingId].Name
		local kind = if current.Kind == "Build"
			then `Build {name}`
			else `Upgrade {name} to level {current.TargetLevel}`
		local builder = ColonistStore.Get(current.BuilderId)
		local by = if builder then ` ({builder.Name})` else ""
		return `#{current.Id} {kind}{by}`
	end

	return show(holding, function()
		return create("Frame")({
			Name = "WorkScrollPanel",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.fromOffset(320, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Color3.fromRGB(60, 48, 30),
			BackgroundTransparency = 0.1,

			create("UICorner")({}),
			create("UIStroke")({
				Color = Color3.fromRGB(215, 170, 60),
				Thickness = 2,
			}),
			create("UIPadding")({
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 12),
				PaddingTop = UDim.new(0, 10),
				PaddingBottom = UDim.new(0, 10),
			}),
			create("UIListLayout")({
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 4),
			}),

			create("TextLabel")({
				Name = "Title",
				LayoutOrder = 0,
				Size = UDim2.new(1, 0, 0, 22),
				BackgroundTransparency = 1,
				TextColor3 = TEXT_COLOR,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextSize = 18,
				Font = Enum.Font.GothamMedium,
				Text = "Work Scroll",
			}),
			create("TextLabel")({
				Name = "Order",
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 18),
				BackgroundTransparency = 1,
				TextColor3 = MUTED_COLOR,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextSize = 14,
				Text = title,
			}),

			show(function()
				return order() ~= nil and #rows() == 0
			end, function()
				return create("TextLabel")({
					Name = "AllUsed",
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 18),
					BackgroundTransparency = 1,
					TextColor3 = ENOUGH_COLOR,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextSize = 14,
					Text = "All materials used",
				})
			end),

			create("Frame")({
				Name = "Materials",
				LayoutOrder = 3,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,

				create("UIListLayout")({
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 2),
				}),

				indexes(rows, row),
			}),
		})
	end)
end

return WorkScrollPanel
