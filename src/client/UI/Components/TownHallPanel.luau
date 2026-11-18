--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared
const Packages = ReplicatedStorage.Packages

const vide = require(Packages.vide)
const Net = require(Packages.Net)
const BuildingData = require(Shared.Buildings.BuildingData)
const BuildingUnlocks = require(Shared.Buildings.BuildingUnlocks)
const ColonyStore = require(script.Parent.Parent.Parent.Colony.ColonyStore)

const create = vide.create
const source = vide.source
const derive = vide.derive
const indexes = vide.indexes
const show = vide.show

const UpgradeBuilding = Net:RemoteEvent("UpgradeBuilding")

const TEXT_COLOR = Color3.new(1, 1, 1)
const MUTED_COLOR = Color3.fromRGB(190, 190, 190)
const HEADER_COLOR = Color3.fromRGB(255, 220, 120)

type Props = {
	Level: () -> number?,
	OnMove: () -> (),
}

-- Names of buildings unlocked at exactly this Town Hall level, alphabetical
local function getNamesUnlockedAt(level: number): { string }
	local names = {}
	for id, info in BuildingData do
		if info.UnlockLevel == level and id ~= "TownHall" then
			table.insert(names, info.Name)
		end
	end
	table.sort(names)
	return names
end

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

local function button(name: string, layoutOrder: number, color: Color3, props: { [any]: any })
	props.Name = name
	props.LayoutOrder = layoutOrder
	props.Size = UDim2.new(0.5, -4, 0, 34)
	props.BackgroundColor3 = color
	props.TextColor3 = TEXT_COLOR
	props.TextSize = 16
	table.insert(props, create("UICorner")({}))
	return create("TextButton")(props)
end

-- Town Hall tab of the Manage menu: upgrade, move and the unlocked buildings
local function TownHallPanel(props: Props)
	local level = function(): number
		return props.Level() or 0
	end

	-- Needs a Builder's Hut of the target level
	local canUpgrade = function(): (boolean, string)
		local builderHut = ColonyStore.GetBuilding("BuilderHut")
		return BuildingUnlocks.CanUpgrade("TownHall", level(), level(), if builderHut then builderHut.Level else 0)
	end
	-- True while the upgrade preview with its confirm button is shown
	local confirming = source(false)

	local pendingLevel = function(): number?
		for _, order in ColonyStore.WorkOrders() do
			if order.BuildingId == "TownHall" then
				return order.TargetLevel
			end
		end
		return nil
	end

	-- One line per unlocked level: "Lv 2: Builder, Farm"
	local unlockedLines = derive(function()
		local lines = {}
		for unlockLevel = 0, level() do
			local names = getNamesUnlockedAt(unlockLevel)
			if #names > 0 then
				table.insert(lines, `Lv {unlockLevel}: {table.concat(names, ", ")}`)
			end
		end
		return lines
	end)

	local nextUnlocks = function(): string
		local names = getNamesUnlockedAt(level() + 1)
		return if #names > 0 then table.concat(names, ", ") else "No new buildings"
	end

	return create("ScrollingFrame")({
		Name = "TownHall",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,

		create("UIListLayout")({
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),

		line(function()
			return `Town Hall level {level()}/{BuildingUnlocks.MAX_LEVEL}`
		end, 1),

		create("Frame")({
			Name = "Buttons",
			LayoutOrder = 2,
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
						confirming(not confirming())
					end
				end,
			}),

			button("Move", 2, Color3.fromRGB(90, 90, 60), {
				Text = "Move Town Hall",
				Activated = props.OnMove,
			}),
		}),

		show(function()
			return confirming() and pendingLevel() == nil and (canUpgrade())
		end, function()
			return create("Frame")({
				Name = "UpgradePreview",
				LayoutOrder = 3,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = Color3.fromRGB(45, 45, 45),

				create("UICorner")({}),
				create("UIPadding")({
					PaddingLeft = UDim.new(0, 8),
					PaddingRight = UDim.new(0, 8),
					PaddingTop = UDim.new(0, 8),
					PaddingBottom = UDim.new(0, 8),
				}),
				create("UIListLayout")({
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 6),
				}),

				line(function()
					return `Upgrading to level {level() + 1} unlocks:`
				end, 1, HEADER_COLOR),
				line(nextUnlocks, 2),

				create("Frame")({
					LayoutOrder = 3,
					Size = UDim2.new(1, 0, 0, 34),
					BackgroundTransparency = 1,

					create("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
					}),

					button("Confirm", 1, Color3.fromRGB(45, 90, 45), {
						Text = "Confirm (test, free)",
						Activated = function()
							confirming(false)
							UpgradeBuilding:FireServer("TownHall")
						end,
					}),

					button("Cancel", 2, Color3.fromRGB(70, 70, 70), {
						Text = "Cancel",
						Activated = function()
							confirming(false)
						end,
					}),
				}),
			})
		end),

		line("Unlocked buildings", 4, MUTED_COLOR),

		create("Frame")({
			Name = "Unlocked",
			LayoutOrder = 5,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,

			create("UIListLayout")({
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 4),
			}),

			indexes(unlockedLines, function(text: () -> string, index: number)
				return line(text, index)
			end),
		}),
	})
end

return TownHallPanel
