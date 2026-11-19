--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const Net = require(Packages.Net)
const Creative = require(Shared.Dev.Creative)
const ItemsList = require(Shared.Inventory.ItemsList)

const create = vide.create
const derive = vide.derive
const show = vide.show
const source = vide.source
const values = vide.values
const changed = vide.changed
const cleanup = vide.cleanup

type Entry = {
	Id: number,
	ItemType: string,
	Name: string,
	Category: string,
	-- Lower-case text the search box matches against
	SearchText: string,
}

const TEXT_COLOR = Color3.new(1, 1, 1)
const MUTED_COLOR = Color3.fromRGB(170, 170, 170)
const PANEL_COLOR = Color3.fromRGB(30, 30, 30)
const TILE_COLOR = Color3.fromRGB(55, 55, 55)
const SELECTED_COLOR = Color3.fromRGB(70, 90, 140)
const INPUT_COLOR = Color3.fromRGB(45, 45, 45)
const BUTTON_COLOR = Color3.fromRGB(70, 70, 70)
const SPAWN_COLOR = Color3.fromRGB(45, 110, 45)
const DISABLED_COLOR = Color3.fromRGB(60, 60, 60)
const PANEL_WIDTH = 560
const GRID_HEIGHT = 260
const TILE_SIZE = Vector2.new(100, 52)
const TILE_GAP = 6

-- Every item in ItemsList, in list order (built once; tiles reuse these tables)
local function buildEntries(): { Entry }
	local entries = {}
	for _, itemType in ItemsList.GetItemTypes() do
		local id = ItemsList.GetItemId(itemType)
		if not id then
			continue
		end
		local item = ItemsList.GetItemByUniqueID(id)
		local category = if item
			then (if typeof(item.Category) == "table" then item.Category[1] or "" else item.Category)
			else ""
		local name = ItemsList.GetDisplayName(id) or itemType
		table.insert(entries, {
			Id = id,
			ItemType = itemType,
			Name = name,
			Category = category,
			SearchText = string.lower(`{name} {itemType} {category}`),
		})
	end
	return entries
end

const ENTRIES = buildEntries()

local function corner()
	return create("UICorner")({})
end

local function button(props: {
	Name: string,
	Text: string,
	Size: UDim2,
	LayoutOrder: number,
	OnClick: () -> (),
})
	return create("TextButton")({
		Name = props.Name,
		LayoutOrder = props.LayoutOrder,
		Size = props.Size,
		BackgroundColor3 = BUTTON_COLOR,
		TextColor3 = TEXT_COLOR,
		TextSize = 18,
		Font = Enum.Font.GothamMedium,
		Text = props.Text,
		Activated = props.OnClick,

		corner(),
	})
end

-- Dev-only menu, toggled by the `creative` Cmdr command: pick any item, choose an amount
-- (1..999) and spawn it into the backpack. The server re-checks permission on every spawn.
local function CreativeMenu()
	local open = source(false)
	local alive = true

	-- The remote is looked up off-scope because Net waits for it on the client
	local connection: RBXScriptConnection? = nil
	task.spawn(function()
		local ok, result = pcall(function()
			return Net:Connect(Creative.TOGGLE_REMOTE, function()
				open(not open())
			end)
		end)
		if not ok then
			warn(`[CreativeMenu] {result}`)
		elseif alive then
			connection = result
		else
			result:Disconnect()
		end
	end)
	cleanup(function()
		alive = false
		if connection then
			connection:Disconnect()
		end
	end)

	return show(open, function()
		-- Panel-local state resets every time the menu opens
		local search = source("")
		local selected = source(nil :: Entry?)
		local amount = source(Creative.MIN_AMOUNT)
		local status = source("")
		local busy = false

		local filtered = derive(function(): { Entry }
			local query = string.lower(search())
			if query == "" then
				return ENTRIES
			end
			local list = {}
			for _, entry in ENTRIES do
				if string.find(entry.SearchText, query, 1, true) then
					table.insert(list, entry)
				end
			end
			return list
		end)

		local function setAmount(n: number)
			amount(Creative.ClampAmount(n))
		end

		local function spawnItem()
			local entry = selected()
			if busy or not entry then
				return
			end
			busy = true
			status("...")
			local count = amount()
			task.spawn(function()
				local ok, result = pcall(function(): string
					local _, message = Net:Invoke(Creative.SPAWN_REMOTE, entry.Id, count)
					return tostring(message)
				end)
				busy = false
				status(if ok then result else "Couldn't reach the server")
			end)
		end

		local tiles = values(filtered, function(entry: Entry, index: () -> number)
			return create("TextButton")({
				Name = `Item_{entry.ItemType}`,
				LayoutOrder = index,
				AutoButtonColor = true,
				BackgroundColor3 = function()
					return if selected() == entry then SELECTED_COLOR else TILE_COLOR
				end,
				Text = "",
				Activated = function()
					selected(entry)
					status("")
				end,

				corner(),
				create("UIPadding")({
					PaddingLeft = UDim.new(0, 4),
					PaddingRight = UDim.new(0, 4),
					PaddingTop = UDim.new(0, 4),
					PaddingBottom = UDim.new(0, 4),
				}),
				create("TextLabel")({
					Name = "ItemName",
					Size = UDim2.new(1, 0, 0.65, 0),
					BackgroundTransparency = 1,
					TextColor3 = TEXT_COLOR,
					TextSize = 13,
					TextWrapped = true,
					Font = Enum.Font.GothamMedium,
					Text = entry.Name,
				}),
				create("TextLabel")({
					Name = "Category",
					Position = UDim2.fromScale(0, 0.65),
					Size = UDim2.new(1, 0, 0.35, 0),
					BackgroundTransparency = 1,
					TextColor3 = MUTED_COLOR,
					TextSize = 11,
					Text = entry.Category,
				}),
			})
		end)

		local amountBox: TextBox
		amountBox = create("TextBox")({
			Name = "Amount",
			LayoutOrder = 3,
			Size = UDim2.fromOffset(64, 34),
			BackgroundColor3 = INPUT_COLOR,
			TextColor3 = TEXT_COLOR,
			TextSize = 16,
			ClearTextOnFocus = false,
			Text = function()
				return tostring(amount())
			end,
			FocusLost = function()
				local n = tonumber(amountBox.Text)
				setAmount(n or amount())
				-- Same value doesn't rerun the binding, so put the clamped text back by hand
				amountBox.Text = tostring(amount())
			end,

			corner(),
		})

		return create("Frame")({
			Name = "CreativeMenu",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(PANEL_WIDTH, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = PANEL_COLOR,
			BackgroundTransparency = 0.1,
			ZIndex = 10,

			corner(),
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

			create("Frame")({
				Name = "Header",
				LayoutOrder = 0,
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundTransparency = 1,

				create("TextLabel")({
					Name = "Title",
					Size = UDim2.new(1, -40, 1, 0),
					BackgroundTransparency = 1,
					TextColor3 = TEXT_COLOR,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextSize = 20,
					Font = Enum.Font.GothamMedium,
					Text = "Creative (dev)",
				}),
				create("TextButton")({
					Name = "Close",
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromScale(1, 0),
					Size = UDim2.fromOffset(30, 30),
					BackgroundColor3 = Color3.fromRGB(120, 45, 45),
					TextColor3 = TEXT_COLOR,
					TextSize = 16,
					Font = Enum.Font.GothamMedium,
					Text = "X",
					Activated = function()
						open(false)
					end,

					corner(),
				}),
			}),

			create("TextBox")({
				Name = "Search",
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundColor3 = INPUT_COLOR,
				TextColor3 = TEXT_COLOR,
				PlaceholderText = "Search items...",
				PlaceholderColor3 = MUTED_COLOR,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextSize = 15,
				ClearTextOnFocus = false,
				Text = "",
				changed("Text", search),

				corner(),
				create("UIPadding")({
					PaddingLeft = UDim.new(0, 8),
				}),
			}),

			create("ScrollingFrame")({
				Name = "Items",
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, GRID_HEIGHT),
				BackgroundTransparency = 1,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				ScrollBarThickness = 6,

				create("UIGridLayout")({
					SortOrder = Enum.SortOrder.LayoutOrder,
					CellSize = UDim2.fromOffset(TILE_SIZE.X, TILE_SIZE.Y),
					CellPadding = UDim2.fromOffset(TILE_GAP, TILE_GAP),
				}),
				create("UIPadding")({
					PaddingRight = UDim.new(0, 8),
				}),

				tiles,
			}),

			create("Frame")({
				Name = "Controls",
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 0, 34),
				BackgroundTransparency = 1,

				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 6),
				}),

				create("TextLabel")({
					Name = "Selected",
					LayoutOrder = 1,
					Size = UDim2.new(1, -(34 + 64 + 34 + 110 + 4 * 6), 1, 0),
					BackgroundTransparency = 1,
					TextColor3 = TEXT_COLOR,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextSize = 15,
					Text = function()
						local entry = selected()
						return if entry then `Selected: {entry.Name}` else "Pick an item"
					end,
				}),
				button({
					Name = "Minus",
					Text = "-",
					LayoutOrder = 2,
					Size = UDim2.fromOffset(34, 34),
					OnClick = function()
						setAmount(amount() - 1)
					end,
				}),
				amountBox,
				button({
					Name = "Plus",
					Text = "+",
					LayoutOrder = 4,
					Size = UDim2.fromOffset(34, 34),
					OnClick = function()
						setAmount(amount() + 1)
					end,
				}),
				create("TextButton")({
					Name = "Spawn",
					LayoutOrder = 5,
					Size = UDim2.fromOffset(110, 34),
					BackgroundColor3 = function()
						return if selected() then SPAWN_COLOR else DISABLED_COLOR
					end,
					TextColor3 = TEXT_COLOR,
					TextSize = 16,
					Font = Enum.Font.GothamMedium,
					Text = "Spawn",
					Activated = spawnItem,

					corner(),
				}),
			}),

			create("TextLabel")({
				Name = "Status",
				LayoutOrder = 4,
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				TextColor3 = TEXT_COLOR,
				TextSize = 15,
				Text = status,
			}),
		})
	end)
end

return CreativeMenu
