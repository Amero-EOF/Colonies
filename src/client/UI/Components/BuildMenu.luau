--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const BuildingData = require(Shared.Buildings.BuildingData)
const BuildingTypes = require(Shared.Buildings.BuildingTypes)
const BuildingUnlocks = require(Shared.Buildings.BuildingUnlocks)
const ColonyStore = require(script.Parent.Parent.Parent.Colony.ColonyStore)
const attributeSource = require(script.Parent.Parent.attributeSource)

const create = vide.create
const source = vide.source
const show = vide.show
const derive = vide.derive
const indexes = vide.indexes

type BuildingId = BuildingTypes.BuildingId
type BuildingInfo = BuildingTypes.BuildingInfo

const TEXT_COLOR = Color3.new(1, 1, 1)
const MUTED_COLOR = Color3.fromRGB(190, 190, 190)
const MARGIN = 16

type Props = {
	-- Starts the placement ghost for a new building
	OnPlace: (BuildingId) -> (),
}

local function row(info: () -> BuildingInfo, index: number, onPlace: (BuildingId) -> ())
	return create("Frame")({
		Name = function()
			return info().Id
		end,
		LayoutOrder = index,
		Size = UDim2.new(1, -8, 0, 52),
		BackgroundColor3 = Color3.fromRGB(45, 45, 45),

		create("UICorner")({}),

		create("TextLabel")({
			Position = UDim2.fromOffset(10, 6),
			Size = UDim2.new(1, -110, 0, 20),
			BackgroundTransparency = 1,
			TextColor3 = TEXT_COLOR,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 16,
			Text = function()
				return info().Name
			end,
		}),

		create("TextLabel")({
			Position = UDim2.fromOffset(10, 26),
			Size = UDim2.new(1, -110, 0, 20),
			BackgroundTransparency = 1,
			TextColor3 = MUTED_COLOR,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextSize = 13,
			Text = function()
				return info().Description
			end,
		}),

		create("TextButton")({
			Name = "Place",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(90, 34),
			BackgroundColor3 = Color3.fromRGB(45, 90, 45),
			TextColor3 = TEXT_COLOR,
			TextSize = 16,
			Text = "Place",
			Activated = function()
				onPlace(info().Id)
			end,

			create("UICorner")({}),
		}),
	})
end

-- Build button in the bottom left; its menu lists unlocked buildings the colony doesn't have yet:
-- only the Builder's Hut at first, then the Town Hall once the hut is built, then the rest by
-- Town Hall level. Later the player will order buildings by talking to the Builder instead.
local function BuildMenu(props: Props)
	local open = source(false)
	local townHallLevel = attributeSource("TownHallLevel")

	local builderHutLevel = function(): number
		local builderHut = ColonyStore.GetBuilding("BuilderHut")
		return if builderHut then builderHut.Level else 0
	end

	local available = derive(function()
		local infos: { BuildingInfo } = {}
		for id, info in BuildingData do
			local unlocked = BuildingUnlocks.IsUnlocked(id, townHallLevel() or 0, builderHutLevel())
			if unlocked and not info.Components.Teleporter and not ColonyStore.GetBuilding(id) then
				table.insert(infos, info)
			end
		end

		table.sort(infos, function(a, b)
			if a.UnlockLevel ~= b.UnlockLevel then
				return a.UnlockLevel < b.UnlockLevel
			end
			return a.Name < b.Name
		end)
		return infos
	end)

	local function place(id: BuildingId)
		open(false)
		props.OnPlace(id)
	end

	-- Shown once the colony is named (the name prompt comes first)
	return show(function()
		return ColonyStore.Loaded() and ColonyStore.Name() ~= nil
	end, function()
		return {
			create("TextButton")({
				Name = "BuildButton",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, MARGIN, 1, -MARGIN),
				Size = UDim2.fromOffset(220, 40),
				BackgroundColor3 = Color3.fromRGB(110, 80, 40),
				TextColor3 = TEXT_COLOR,
				TextSize = 18,
				Text = "Build",
				Activated = function()
					open(not open())
				end,

				create("UICorner")({}),
			}),

			show(open, function()
				return create("Frame")({
					Name = "BuildMenu",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(420, 360),
					BackgroundColor3 = Color3.fromRGB(30, 30, 30),
					BackgroundTransparency = 0.05,

					create("UICorner")({}),
					create("UIPadding")({
						PaddingLeft = UDim.new(0, 12),
						PaddingRight = UDim.new(0, 12),
						PaddingTop = UDim.new(0, 12),
						PaddingBottom = UDim.new(0, 12),
					}),

					create("TextLabel")({
						Size = UDim2.new(1, -40, 0, 26),
						BackgroundTransparency = 1,
						TextColor3 = TEXT_COLOR,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextSize = 20,
						Text = function()
							return `Build (Town Hall level {townHallLevel() or 0})`
						end,
					}),

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

					create("ScrollingFrame")({
						Name = "List",
						Position = UDim2.fromOffset(0, 36),
						Size = UDim2.new(1, 0, 1, -36),
						BackgroundTransparency = 1,
						CanvasSize = UDim2.new(),
						AutomaticCanvasSize = Enum.AutomaticSize.Y,
						ScrollBarThickness = 6,

						create("UIListLayout")({
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 6),
						}),

						show(function()
							return #available() == 0
						end, function()
							return create("TextLabel")({
								Size = UDim2.new(1, 0, 0, 40),
								BackgroundTransparency = 1,
								TextColor3 = MUTED_COLOR,
								TextWrapped = true,
								TextSize = 16,
								Text = function()
									local townHall = ColonyStore.GetBuilding("TownHall")
									if not townHall or townHall.Level < 1 then
										return "Nothing new to build. Finish the Builder's Hut, then the Town Hall."
									end
									return "Nothing new to build. Upgrade the Town Hall to unlock more buildings."
								end,
							})
						end),

						indexes(available, function(info, index)
							return row(info, index, place)
						end),
					}),
				})
			end),
		}
	end)
end

return BuildMenu
