--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const Net = require(Packages.Net)
const BuildingData = require(Shared.Buildings.BuildingData)
const BuildingPlacement = require(Shared.Buildings.BuildingPlacement)
const BuildingTypes = require(Shared.Buildings.BuildingTypes)
const BuildingUnlocks = require(Shared.Buildings.BuildingUnlocks)
const PlotData = require(Shared.Plot.PlotData)
const ColonyStore = require(script.Parent.Parent.Parent.Colony.ColonyStore)
const FieldPanel = require(script.Parent.FieldPanel)
const WorkOrderList = require(script.Parent.WorkOrderList)
const YardPanel = require(script.Parent.YardPanel)
const attributeSource = require(script.Parent.Parent.attributeSource)

const create = vide.create
const show = vide.show
const source = vide.source

type BuildingId = BuildingTypes.BuildingId

const UpgradeBuilding = Net:RemoteEvent("UpgradeBuilding")

const TEXT_COLOR = Color3.new(1, 1, 1)
const MUTED_COLOR = Color3.fromRGB(190, 190, 190)
const TAB_COLOR = Color3.fromRGB(55, 55, 55)
const SELECTED_TAB_COLOR = Color3.fromRGB(70, 90, 140)
const WORK_ORDERS_HEIGHT = 260

type Tab = "Building" | "WorkOrders" | "Field" | "Yard"

-- Extra tabs some buildings get besides their own page
const BUILDING_TABS: { [BuildingId]: { { Id: Tab, Name: string } } } = {
	BuilderHut = {
		{ Id = "Building", Name = "Building" },
		{ Id = "WorkOrders", Name = "Work Orders" },
	},
	FarmerHut = {
		{ Id = "Building", Name = "Building" },
		{ Id = "Field", Name = "Field" },
	},
	ForesterHut = {
		{ Id = "Building", Name = "Building" },
		{ Id = "Yard", Name = "Trees" },
	},
	Mine = {
		{ Id = "Building", Name = "Building" },
		{ Id = "Yard", Name = "Rocks" },
	},
}

type Props = {
	OnMove: (BuildingId) -> (),
}

local function line(text: () -> string, layoutOrder: number, color: Color3?)
	return create("TextLabel")({
		LayoutOrder = layoutOrder,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		TextColor3 = color or TEXT_COLOR,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		TextSize = 16,
		Text = text,
	})
end

local function button(name: string, layoutOrder: number, color: Color3, props: { [any]: any })
	props.Name = name
	props.LayoutOrder = layoutOrder
	props.Size = UDim2.new(1 / 3, -6, 0, 34)
	props.BackgroundColor3 = color
	props.TextColor3 = TEXT_COLOR
	props.TextSize = 15
	props.TextWrapped = true
	table.insert(props, create("UICorner")({}))
	return create("TextButton")(props)
end

-- Upgrade and move panel for any building besides the Town Hall and Spire, opened from its Manage prompt.
-- The Builder's Hut also gets a Work Orders tab, the Farmer's Hut a Field tab.
local function BuildingPanel(props: Props)
	local townHallLevel = attributeSource("TownHallLevel")

	return show(function()
		return ColonyStore.BuildingPanelId() ~= nil
	end, function()
		-- Every time the panel opens it starts on the building's own page
		local selectedTab = source("Building" :: Tab)
		local id = function(): BuildingId
			return ColonyStore.BuildingPanelId() or "BuilderHut"
		end
		local level = function(): number
			local saved = ColonyStore.GetBuilding(id())
			return if saved then saved.Level else 1
		end
		local pendingLevel = function(): number?
			for _, order in ColonyStore.WorkOrders() do
				if order.BuildingId == id() then
					return order.TargetLevel
				end
			end
			return nil
		end
		local tab = function(): Tab
			return if BUILDING_TABS[id()] then selectedTab() else "Building"
		end
		local onBuildingTab = function(): boolean
			return tab() == "Building"
		end

		local canUpgrade = function(): (boolean, string)
			local builderHut = ColonyStore.GetBuilding("BuilderHut")
			local canUpgrade, reason = BuildingUnlocks.CanUpgrade(
				id(),
				level(),
				townHallLevel() or 0,
				if builderHut then builderHut.Level else 0
			)
			local saved = ColonyStore.GetBuilding(id())
			if not canUpgrade or not saved or not saved.Placement then
				return canUpgrade, reason
			end
			-- The next level may have a bigger footprint that needs room on the plot
			local fits, blocked = BuildingPlacement.CanGrow(
				saved,
				saved.Level + 1,
				PlotData.GetSize(townHallLevel() or 0),
				ColonyStore.Buildings(),
				ColonyStore.WorkOrders()
			)
			if not fits then
				return false, blocked or "Not enough room"
			end
			return true, reason
		end

		return create("Frame")({
			Name = "BuildingPanel",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(380, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Color3.fromRGB(30, 30, 30),
			BackgroundTransparency = 0.05,

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

			line(function()
				return `{BuildingData[id()].Name} - level {level()}/{BuildingUnlocks.BUILDING_MAX_LEVEL}`
			end, 1),
			show(function()
				return BUILDING_TABS[id()] ~= nil
			end, function()
				local buttons = {}
				for i, info in BUILDING_TABS[id()] do
					table.insert(
						buttons,
						create("TextButton")({
							Name = info.Id,
							LayoutOrder = i,
							Size = UDim2.new(1 / #BUILDING_TABS[id()], -4, 1, 0),
							BackgroundColor3 = function()
								return if tab() == info.Id then SELECTED_TAB_COLOR else TAB_COLOR
							end,
							TextColor3 = TEXT_COLOR,
							TextSize = 14,
							Text = info.Name,
							Activated = function()
								selectedTab(info.Id)
							end,
							create("UICorner")({}),
						})
					)
				end
				return create("Frame")({
					Name = "Tabs",
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 28),
					BackgroundTransparency = 1,
					create("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 4),
					}),
					buttons,
				})
			end),

			show(onBuildingTab, function()
				return line(function()
					return BuildingData[id()].Description
				end, 3, MUTED_COLOR)
			end),

			show(function()
				return id() == "BuilderHut" and onBuildingTab()
			end, function()
				return line(function()
					if level() <= 1 then
						return "Lets the Town Hall be built"
					end
					return `Lets the Town Hall be upgraded to level {math.min(
						level(),
						BuildingUnlocks.MAX_LEVEL
					)}`
				end, 4, MUTED_COLOR)
			end),

			show(function()
				return tab() == "WorkOrders"
			end, function()
				return WorkOrderList(5, WORK_ORDERS_HEIGHT)
			end),

			show(function()
				return tab() == "Field"
			end, function()
				return FieldPanel(5)
			end),

			show(function()
				return tab() == "Yard"
			end, function()
				return YardPanel(id, 5)
			end),

			create("Frame")({
				Name = "Buttons",
				LayoutOrder = 6,
				Size = UDim2.new(1, 0, 0, 34),
				BackgroundTransparency = 1,

				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 8),
				}),

				button("Upgrade", 1, Color3.fromRGB(60, 90, 140), {
					AutoButtonColor = function()
						return pendingLevel() == nil and (canUpgrade())
					end,
					Text = function()
						local pending = pendingLevel()
						if pending then
							return `Builder upgrading to Lv {pending}...`
						end
						local _, reason = canUpgrade()
						return reason
					end,
					Activated = function()
						if pendingLevel() == nil and canUpgrade() then
							UpgradeBuilding:FireServer(id())
						end
					end,
				}),

				button("Move", 2, Color3.fromRGB(90, 90, 60), {
					Text = "Move",
					Activated = function()
						local current = id()
						ColonyStore.BuildingPanelId(nil)
						props.OnMove(current)
					end,
				}),

				button("Close", 3, Color3.fromRGB(70, 70, 70), {
					Text = "Close",
					Activated = function()
						ColonyStore.BuildingPanelId(nil)
					end,
				}),
			}),
		})
	end)
end

return BuildingPanel
