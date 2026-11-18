--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const Net = require(Packages.Net)
const BuildingData = require(Shared.Buildings.BuildingData)
const BuildingUnlocks = require(Shared.Buildings.BuildingUnlocks)
const ColonistData = require(Shared.Colonist.ColonistData)
const ColonistTypes = require(Shared.Colonist.ColonistTypes)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const PlotData = require(Shared.Plot.PlotData)
const ColonistStore = require(script.Parent.Parent.Parent.Colony.ColonistStore)
const ColonyStore = require(script.Parent.Parent.Parent.Colony.ColonyStore)
const TownHallPanel = require(script.Parent.TownHallPanel)
const WorkOrderList = require(script.Parent.WorkOrderList)
const attributeSource = require(script.Parent.Parent.attributeSource)

const create = vide.create
const source = vide.source
const show = vide.show
const switch = vide.switch
const indexes = vide.indexes
const derive = vide.derive

type Tab = "TownHall" | "Statistics" | "Colonists" | "Events" | "WorkOrders"

const TABS: { { Id: Tab, Name: string } } = {
	{ Id = "TownHall", Name = "Town Hall" },
	{ Id = "Statistics", Name = "Statistics" },
	{ Id = "Colonists", Name = "Colonists" },
	{ Id = "Events", Name = "Events" },
	{ Id = "WorkOrders", Name = "Work Orders" },
}

const TEXT_COLOR = Color3.new(1, 1, 1)
const MUTED_COLOR = Color3.fromRGB(190, 190, 190)
const TAB_COLOR = Color3.fromRGB(55, 55, 55)
const SELECTED_TAB_COLOR = Color3.fromRGB(70, 90, 140)
const PANEL_SIZE = Vector2.new(520, 380)

local function line(text: string | () -> string, layoutOrder: number, color: Color3?)
	return create("TextLabel")({
		LayoutOrder = layoutOrder,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		TextColor3 = color or TEXT_COLOR,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		TextSize = 16,
		Text = text,
	})
end

local function list(children: any)
	return create("ScrollingFrame")({
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,

		create("UIListLayout")({
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),

		children,
	})
end

-- Colony name at the top of the menu; click it to type a new name, Enter or click away to save
local function NameTitle()
	local status = source("")
	local box: TextBox

	local function submit()
		local name = box.Text
		if name == ColonyStore.Name() then
			return
		end

		status("...")
		task.spawn(function()
			local ok, message = Net:Invoke("SetColonyName", name)
			status(if ok then "" else tostring(message))
			if not ok then
				box.Text = ColonyStore.Name() or ""
			end
		end)
	end

	box = create("TextBox")({
		Name = "Title",
		Size = UDim2.new(1, -200, 0, 26),
		BackgroundColor3 = Color3.fromRGB(45, 45, 45),
		BackgroundTransparency = 1,
		TextColor3 = TEXT_COLOR,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 20,
		ClearTextOnFocus = false,
		Text = function()
			return ColonyStore.Name() or ""
		end,

		Focused = function()
			box.BackgroundTransparency = 0
		end,
		FocusLost = function()
			box.BackgroundTransparency = 1
			submit()
		end,

		create("UICorner")({}),
	})

	return {
		box,

		create("TextLabel")({
			Name = "NameStatus",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -38, 0, 0),
			Size = UDim2.fromOffset(156, 26),
			BackgroundTransparency = 1,
			TextColor3 = Color3.fromRGB(255, 140, 140),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextWrapped = true,
			TextSize = 13,
			Text = status,
		}),
	}
end

local function StatisticsTab()
	local townHallLevel = attributeSource("TownHallLevel")

	-- Beds across every placed building that houses colonists
	local housingCapacity = function(): number
		local capacity = 0
		for _, saved in ColonyStore.Buildings() do
			local housing = BuildingData[saved.Id].Components.Housing
			if saved.Placement and housing and BuildingUnlocks.IsBuilt(saved.Id, saved.Level) then
				capacity += housing.Capacity + (housing.CapacityPerLevel or 0) * saved.Level
			end
		end
		return capacity
	end

	local placedCount = function(): number
		local count = 0
		for _, saved in ColonyStore.Buildings() do
			if saved.Placement then
				count += 1
			end
		end
		return count
	end

	return list({
		line(function()
			return `Town Hall level: {townHallLevel() or 0}/{BuildingUnlocks.MAX_LEVEL}`
		end, 1),
		line(function()
			local size = PlotData.GetSize(townHallLevel() or 0)
			return `Plot size: {size} x {size} studs`
		end, 2),
		line(function()
			return `Buildings: {placedCount()}`
		end, 3),
		line(function()
			return `Colonists: {#ColonistStore.Colonists()}  (beds: {housingCapacity()})`
		end, 4),
		line(function()
			return `Disease risk: {math.floor(ColonistStore.Disease())}%`
		end, 5),
		line(function()
			local funeral = ColonistStore.Funeral()
			return if funeral then `Funeral for {funeral.Name} in progress` else ""
		end, 6, MUTED_COLOR),
	})
end

-- Every colonist with their job and mood; click one to open its menu
local function ColonistsTab()
	return list({
		show(function()
			return #ColonistStore.Colonists() == 0
		end, function()
			return line(
				"No colonists yet. They arrive once the Town Hall is placed.",
				0,
				MUTED_COLOR
			)
		end),

		indexes(
			ColonistStore.Colonists,
			function(colonist: () -> ColonistTypes.Colonist, index: number)
				return create("TextButton")({
					LayoutOrder = index,
					Size = UDim2.new(1, -8, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundColor3 = TAB_COLOR,
					TextColor3 = TEXT_COLOR,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = true,
					TextSize = 14,
					Text = function()
						local c = colonist()
						local job = c.Job or (if c.Age == "Child" then "Child" else "Unemployed")
						local mood =
							`{math.floor(c.Happiness * 10 + 0.5) / 10}/{ColonistData.MAX_HAPPINESS}`
						return `{c.Name}  -  {job}  -  Happiness {mood}\n{ColonistStore.GetStatus(
							c.Id
						)}`
					end,
					Activated = function()
						ColonistStore.SelectedId(colonist().Id)
					end,

					create("UICorner")({}),
					create("UIPadding")({
						PaddingLeft = UDim.new(0, 6),
						PaddingTop = UDim.new(0, 4),
						PaddingBottom = UDim.new(0, 4),
					}),
				})
			end
		),
	})
end

local function EventsTab()
	-- Newest first
	local events = derive(function()
		local reversed = {}
		local all = ColonyStore.Events()
		for i = #all, 1, -1 do
			table.insert(reversed, all[i])
		end
		return reversed
	end)

	return list({
		show(function()
			return #events() == 0
		end, function()
			return line("Nothing has happened yet.", 0, MUTED_COLOR)
		end),

		indexes(events, function(event: () -> ColonyTypes.ColonyEvent, index: number)
			return line(function()
				local current = event()
				return `[{os.date("%d %b %H:%M", math.floor(current.Time))}] {current.Text}`
			end, index)
		end),
	})
end

local function WorkOrdersTab()
	return WorkOrderList()
end

type Props = {
	-- Starts moving the Town Hall; the menu closes so the ghost is visible
	OnMoveTownHall: () -> (),
}

-- Opened from the Town Hall's Manage prompt
local function ColonyMenu(props: Props)
	local open = ColonyStore.ManageOpen
	local tab = source("TownHall" :: Tab)

	local tabComponents: { [Tab]: () -> Instance } = {
		TownHall = function()
			return TownHallPanel({
				Level = attributeSource("TownHallLevel"),
				OnMove = function()
					open(false)
					props.OnMoveTownHall()
				end,
			})
		end,
		Statistics = StatisticsTab,
		Colonists = ColonistsTab,
		Events = EventsTab,
		WorkOrders = WorkOrdersTab,
	}

	return show(open, function()
		local tabButtons = {}
		for i, info in TABS do
			table.insert(
				tabButtons,
				create("TextButton")({
					Name = info.Id,
					LayoutOrder = i,
					Size = UDim2.new(1 / #TABS, -4, 1, 0),
					BackgroundColor3 = function()
						return if tab() == info.Id then SELECTED_TAB_COLOR else TAB_COLOR
					end,
					TextColor3 = TEXT_COLOR,
					TextSize = 14,
					Text = info.Name,
					Activated = function()
						tab(info.Id)
					end,

					create("UICorner")({}),
				})
			)
		end

		return create("Frame")({
			Name = "ColonyMenu",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y),
			BackgroundColor3 = Color3.fromRGB(30, 30, 30),
			BackgroundTransparency = 0.05,

			create("UICorner")({}),
			create("UIPadding")({
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 12),
				PaddingTop = UDim.new(0, 12),
				PaddingBottom = UDim.new(0, 12),
			}),

			NameTitle(),

			create("TextButton")({
				Name = "Close",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.fromOffset(30, 26),
				BackgroundColor3 = Color3.fromRGB(110, 50, 50),
				TextColor3 = TEXT_COLOR,
				TextSize = 16,
				Text = "X",
				Activated = function()
					open(false)
				end,

				create("UICorner")({}),
			}),

			create("Frame")({
				Name = "Tabs",
				Position = UDim2.fromOffset(0, 34),
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundTransparency = 1,

				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 4),
				}),

				tabButtons,
			}),

			create("Frame")({
				Name = "Page",
				Position = UDim2.fromOffset(0, 74),
				Size = UDim2.new(1, 0, 1, -74),
				BackgroundTransparency = 1,

				switch(tab)(tabComponents),
			}),
		})
	end)
end

return ColonyMenu
