--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const Net = require(Packages.Net)
const BuildingData = require(Shared.Buildings.BuildingData)
const BagMoves = require(Shared.Inventory.BagMoves)
const ColonyStore = require(script.Parent.Parent.Parent.Colony.ColonyStore)
const BagGrid = require(script.Parent.BagGrid)

const create = vide.create
const source = vide.source
const show = vide.show

const TEXT_COLOR = Color3.new(1, 1, 1)
-- Gap between this panel and the backpack opened beside it
const SIDE_GAP = 8

local function button(props: { [any]: any })
	props.Size = UDim2.new(0.5, -4, 0, 34)
	props.TextColor3 = TEXT_COLOR
	props.TextSize = 16
	table.insert(props, create("UICorner")({}))
	return create("TextButton")(props)
end

-- Colony storage (Town Hall, Warehouse) or a worker building's own storage (Builder's Hut)
local function StoragePanel()
	local open = ColonyStore.StorageOpen
	local status = source("")

	local function deposit()
		status("...")
		task.spawn(function()
			local _, message = Net:Invoke("Deposit", ColonyStore.StorageTarget())
			status(tostring(message))
		end)
	end

	return show(open, function()
		status("")

		return create("Frame")({
			Name = "StoragePanel",
			-- Left of centre; the backpack opens on the right so items can be moved across
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(0.5, -SIDE_GAP / 2, 0.5, 0),
			Size = UDim2.fromOffset(BagGrid.GetPanelWidth(6), 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Color3.fromRGB(30, 30, 30),
			BackgroundTransparency = 0.1,

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
					local target = ColonyStore.StorageTarget()
					return if target
						then `{(BuildingData :: any)[target].Name} storage`
						else "Colony storage"
				end,
			}),

			BagGrid.BagGrid({
				Name = "Storage",
				LayoutOrder = 2,
				Columns = 6,
				Bag = function()
					local target = ColonyStore.StorageTarget()
					return if target
						then ColonyStore.HutStorage()[target]
						else ColonyStore.Storage()
				end,
				Ref = function(): string?
					local target = ColonyStore.StorageTarget()
					return if target then BagMoves.HutRef(target) else BagMoves.STORAGE
				end,
			}),

			create("TextLabel")({
				Name = "Status",
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				TextColor3 = TEXT_COLOR,
				TextSize = 16,
				Text = status,
			}),

			create("Frame")({
				Name = "Buttons",
				LayoutOrder = 4,
				Size = UDim2.new(1, 0, 0, 34),
				BackgroundTransparency = 1,

				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 8),
				}),

				button({
					Name = "Deposit",
					BackgroundColor3 = Color3.fromRGB(45, 90, 45),
					Text = "Deposit all",
					Activated = deposit,
				}),

				button({
					Name = "Close",
					BackgroundColor3 = Color3.fromRGB(70, 70, 70),
					Text = "Close",
					Activated = function()
						open(false)
					end,
				}),
			}),
		})
	end)
end

return StoragePanel
