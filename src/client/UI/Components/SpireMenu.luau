--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const Net = require(Packages.Net)
const SpireData = require(Shared.Spire.SpireData)
const WildAreaData = require(Shared.Wilds.WildAreaData)
const ColonyStore = require(script.Parent.Parent.Parent.Colony.ColonyStore)
const attributeSource = require(script.Parent.Parent.attributeSource)

const create = vide.create
const source = vide.source
const show = vide.show

const TEXT_COLOR = Color3.new(1, 1, 1)
const UNLOCKED_COLOR = Color3.fromRGB(90, 70, 160)
const LOCKED_COLOR = Color3.fromRGB(60, 60, 60)

type Props = {
	OnMove: () -> (),
}

local function button(props: { [any]: any })
	props.Size = props.Size or UDim2.new(1, 0, 0, 34)
	props.TextColor3 = TEXT_COLOR
	props.TextSize = 16
	table.insert(props, create("UICorner")({}))
	return create("TextButton")(props)
end

-- Wild area menu opened from the player's Spire
local function SpireMenu(props: Props)
	local open = ColonyStore.SpireMenuOpen
	local status = source("")
	local townHallLevel = attributeSource("TownHallLevel")

	local spireLevel = function(): number
		return SpireData.GetLevel(townHallLevel() or 1)
	end

	local function teleport(id: string)
		status("...")
		task.spawn(function()
			local ok, message = Net:Invoke("SpireTeleport", id)
			status(tostring(message))
			if ok then
				open(false)
			end
		end)
	end

	local function areaButtons()
		local buttons = {}
		for i, area in WildAreaData.AREAS do
			local unlocked = function()
				return spireLevel() >= area.UnlockLevel
			end

			table.insert(
				buttons,
				button({
					Name = area.Id,
					LayoutOrder = i,
					BackgroundColor3 = function()
						return if unlocked() then UNLOCKED_COLOR else LOCKED_COLOR
					end,
					Text = function()
						return if unlocked() then area.Name else `{area.Name} (Spire Lv {area.UnlockLevel})`
					end,
					Activated = function()
						if unlocked() then
							teleport(area.Id)
						end
					end,
				})
			)
		end
		return buttons
	end

	return show(open, function()
		status("")

		return create("Frame")({
			Name = "SpireMenu",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(340, 0),
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
				Name = "Title",
				LayoutOrder = 0,
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundTransparency = 1,
				TextColor3 = TEXT_COLOR,
				TextSize = 20,
				Text = function()
					return `Spire (Lv {spireLevel()}): travel to the wilds`
				end,
			}),

			create("Frame")({
				Name = "Areas",
				LayoutOrder = 1,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,

				create("UIListLayout")({
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 6),
				}),

				areaButtons(),
			}),

			create("TextLabel")({
				Name = "Status",
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				TextColor3 = TEXT_COLOR,
				TextSize = 16,
				Text = status,
			}),

			button({
				Name = "Move",
				LayoutOrder = 3,
				BackgroundColor3 = Color3.fromRGB(90, 90, 60),
				Text = "Move Spire",
				Activated = function()
					open(false)
					props.OnMove()
				end,
			}),

			button({
				Name = "Close",
				LayoutOrder = 4,
				BackgroundColor3 = Color3.fromRGB(70, 70, 70),
				Text = "Close",
				Activated = function()
					open(false)
				end,
			}),
		})
	end)
end

return SpireMenu
