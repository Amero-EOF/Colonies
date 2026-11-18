--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const Net = require(Packages.Net)
const BuildingTypes = require(Shared.Buildings.BuildingTypes)
const BuildingUnlocks = require(Shared.Buildings.BuildingUnlocks)
const FarmData = require(Shared.Farm.FarmData)
const ItemsList = require(Shared.Inventory.ItemsList)
const ColonistStore = require(script.Parent.Parent.Parent.Colony.ColonistStore)
const ColonyStore = require(script.Parent.Parent.Parent.Colony.ColonyStore)
const WorkOrderMaterials = require(script.Parent.Parent.Parent.Colony.WorkOrderMaterials)

const create = vide.create
const derive = vide.derive
const show = vide.show
const source = vide.source
const cleanup = vide.cleanup

type Plot = FarmData.Plot

const HUT: BuildingTypes.BuildingId = "FarmerHut"

const TEXT_COLOR = Color3.new(1, 1, 1)
const MUTED_COLOR = Color3.fromRGB(170, 170, 170)
const BAR_BACK_COLOR = Color3.fromRGB(25, 25, 25)
const BAR_COLOR = Color3.fromRGB(90, 160, 90)
const RIPE_COLOR = Color3.fromRGB(235, 200, 90)
const BUTTON_COLOR = Color3.fromRGB(55, 55, 55)
const REMOVE_COLOR = Color3.fromRGB(120, 50, 45)

-- Fan colours (top-down view of the field, its entrance at the top)
const PATH_COLOR = Color3.fromRGB(165, 135, 95)
const HUT_COLOR = Color3.fromRGB(110, 75, 45)
const SOIL_COLOR = Color3.fromRGB(95, 65, 40)
const LOCKED_COLOR = Color3.fromRGB(70, 70, 70)
const SELECTED_TINT = Color3.new(1, 1, 1)
const SELECTED_AMOUNT = 0.25
const CROP_COLORS: { [string]: Color3 } = {
	Wheat = Color3.fromRGB(222, 184, 88),
	Carrot = Color3.fromRGB(235, 125, 35),
	Potato = Color3.fromRGB(105, 150, 70),
}
-- How strongly a wedge shows its crop's colour per stage (0 = waiting to be planted)
const STAGE_TINT = { [0] = 0.2, [1] = 0.45, [2] = 0.7, [3] = 1 }

-- Fan size in pixels and cells per side (each cell is one "pixel" of the field)
const FAN_SIZE = 200
const CELLS = 25
const DETAILS_WIDTH = 140
const PANEL_HEIGHT = FAN_SIZE
-- Seconds between growth updates
const TICK = 0.5

-- Which part of the field a fan cell (in hut-local studs) belongs to
type CellKind = "Outside" | "Hut" | "Path" | "Wedge"

local function classify(x: number, z: number, cellStuds: number): (CellKind, number)
	local distance = math.sqrt(x * x + z * z)
	if distance > FarmData.OUTER_RADIUS then
		return "Outside", 0
	end
	if distance <= FarmData.HUT_FOOTPRINT / 2 then
		return "Hut", 0
	end
	if distance < FarmData.SOIL_INNER or distance > FarmData.SOIL_OUTER then
		return "Path", 0
	end
	-- Angle from the front (-Z) toward +X, like FarmData.GetDirection
	local angle = math.atan2(x, -z) % (math.pi * 2)
	local step = math.pi * 2 / FarmData.WEDGE_COUNT
	local fromSpoke = math.min(angle % step, step - angle % step)
	if distance * math.sin(fromSpoke) < FarmData.PATH_WIDTH / 2 + cellStuds * 0.2 then
		return "Path", 0
	end
	return "Wedge", math.floor(angle / step) + 1
end

local function getSeedCount(seedItem: string): number
	local id = ItemsList.GetItemId(seedItem)
	if not id then
		return 0
	end
	local count = WorkOrderMaterials.CountItem(ColonyStore.HutStorage()[HUT], id)
	for _, colonist in ColonistStore.Colonists() do
		if colonist.Workplace == HUT then
			count += WorkOrderMaterials.CountItem(colonist.Carried, id)
		end
	end
	return count
end

-- The Farmer's Hut "Field" tab: the field drawn as a fan (hut in the middle, six wedges around
-- it). Click an unlocked wedge, then pick a crop for it or remove it. Each wedge shows its crop,
-- growth stage and a progress bar; locked wedges show the hut level that unlocks them.
local function FieldPanel(layoutOrder: number)
	local now = source(workspace:GetServerTimeNow())
	local selected = source(nil :: number?)
	local status = source("")
	local busy = false

	local elapsed = 0
	local connection = RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime
		if elapsed >= TICK then
			elapsed = 0
			now(workspace:GetServerTimeNow())
		end
	end)
	cleanup(connection)

	local level = function(): number
		local saved = ColonyStore.GetBuilding(HUT)
		return if saved then saved.Level else 0
	end
	local built = function(): boolean
		return BuildingUnlocks.IsBuilt(HUT, level())
	end
	local getPlot = function(wedge: number): Plot
		local field = ColonyStore.Fields()[HUT]
		return (field and field[wedge]) or {}
	end

	-- Per wedge: colour on the fan, label text and growth (each only changes when it must)
	local wedgeColors: { () -> Color3 } = {}
	local wedgeTexts: { () -> string } = {}
	local wedgeProgress: { () -> number } = {}
	for wedge = 1, FarmData.WEDGE_COUNT do
		wedgeColors[wedge] = derive(function(): Color3
			local color = LOCKED_COLOR
			if FarmData.IsUnlocked(wedge, level()) then
				local plot = getPlot(wedge)
				local info = FarmData.GetCrop(plot.Crop)
				color = if info
					then SOIL_COLOR:Lerp(
						CROP_COLORS[info.Id],
						STAGE_TINT[FarmData.GetStage(plot, now())]
					)
					else SOIL_COLOR
			end
			return if selected() == wedge then color:Lerp(SELECTED_TINT, SELECTED_AMOUNT) else color
		end)
		wedgeTexts[wedge] = derive(function(): string
			if not FarmData.IsUnlocked(wedge, level()) then
				return `Lv {FarmData.WEDGE_UNLOCK_LEVEL[wedge]}`
			end
			local plot = getPlot(wedge)
			local info = FarmData.GetCrop(plot.Crop)
			if not info then
				return "Empty"
			end
			local name = info.Name
			if not plot.PlantedAt then
				return `{name}\nto plant`
			end
			return `{name}\n{FarmData.GetStage(plot, now())}/{FarmData.STAGES}`
		end)
		wedgeProgress[wedge] = derive(function(): number
			return FarmData.GetProgress(getPlot(wedge), now())
		end)
	end

	local function send(remote: string, ...: any)
		if busy then
			return
		end
		busy = true
		local args = table.pack(...)
		task.spawn(function()
			local ok, message = pcall(function(): string
				local _, reply = Net:Invoke(remote, table.unpack(args, 1, args.n))
				return tostring(reply)
			end)
			busy = false
			status(if ok then message else "Couldn't reach your Farmer's Hut")
		end)
	end

	-- One "pixel" of the fan; wedge cells select their wedge when clicked
	local function cell(ix: number, iz: number)
		local cellPixels = FAN_SIZE / CELLS
		local cellStuds = FarmData.OUTER_RADIUS * 2 / CELLS
		local x = (ix + 0.5) * cellStuds - FarmData.OUTER_RADIUS
		local z = (iz + 0.5) * cellStuds - FarmData.OUTER_RADIUS
		local kind, wedge = classify(x, z, cellStuds)
		if kind == "Outside" then
			return nil
		end
		local props: { [any]: any } = {
			Name = `Cell{ix}_{iz}`,
			Position = UDim2.fromOffset(ix * cellPixels, iz * cellPixels),
			Size = UDim2.fromOffset(math.ceil(cellPixels), math.ceil(cellPixels)),
			BorderSizePixel = 0,
			BackgroundColor3 = if kind == "Hut" then HUT_COLOR else PATH_COLOR,
		}
		if kind ~= "Wedge" then
			return create("Frame")(props)
		end
		props.BackgroundColor3 = wedgeColors[wedge]
		props.Text = ""
		props.AutoButtonColor = false
		props.Activated = function()
			selected(wedge)
			status("")
		end
		return create("TextButton")(props)
	end

	local function wedgeLabel(wedge: number)
		local centre = FarmData.GetWedgeCentre(wedge) / (FarmData.OUTER_RADIUS * 2)
		return create("Frame")({
			Name = `Wedge{wedge}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + centre.X, 0.5 + centre.Z),
			Size = UDim2.fromOffset(46, 32),
			BackgroundTransparency = 1,
			ZIndex = 3,
			Active = false,

			create("TextLabel")({
				Size = UDim2.new(1, 0, 1, -5),
				BackgroundTransparency = 1,
				TextColor3 = TEXT_COLOR,
				TextStrokeTransparency = 0.4,
				TextSize = 11,
				Font = Enum.Font.GothamMedium,
				Text = wedgeTexts[wedge],
				ZIndex = 3,
			}),
			show(function()
				return getPlot(wedge).PlantedAt ~= nil
			end, function()
				return create("Frame")({
					Name = "Progress",
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.fromScale(0.5, 1),
					Size = UDim2.new(0.8, 0, 0, 4),
					BackgroundColor3 = BAR_BACK_COLOR,
					BorderSizePixel = 0,
					ZIndex = 3,
					create("Frame")({
						Size = function()
							return UDim2.fromScale(wedgeProgress[wedge](), 1)
						end,
						BackgroundColor3 = function()
							return if wedgeProgress[wedge]() >= 1 then RIPE_COLOR else BAR_COLOR
						end,
						BorderSizePixel = 0,
						ZIndex = 3,
					}),
				})
			end),
		})
	end

	local function fan()
		local children = {}
		for iz = 0, CELLS - 1 do
			for ix = 0, CELLS - 1 do
				local instance = cell(ix, iz)
				if instance then
					table.insert(children, instance)
				end
			end
		end
		for wedge = 1, FarmData.WEDGE_COUNT do
			table.insert(children, wedgeLabel(wedge))
		end
		return create("Frame")({
			Name = "Fan",
			LayoutOrder = 1,
			Size = UDim2.fromOffset(FAN_SIZE, FAN_SIZE),
			BackgroundTransparency = 1,

			create("TextLabel")({
				Name = "Entrance",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.fromOffset(60, 12),
				BackgroundTransparency = 1,
				TextColor3 = MUTED_COLOR,
				TextSize = 10,
				Text = "Entrance",
				ZIndex = 4,
			}),
			children,
		})
	end

	local function cropButton(info: FarmData.CropInfo, index: number)
		local crop = info.Id
		return create("TextButton")({
			Name = crop,
			LayoutOrder = 10 + index,
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundColor3 = function()
				local wedge = selected()
				local current = if wedge then getPlot(wedge).Crop else nil
				return if current == crop
					then BUTTON_COLOR:Lerp(CROP_COLORS[crop], 0.5)
					else BUTTON_COLOR
			end,
			TextColor3 = TEXT_COLOR,
			TextSize = 13,
			Text = function()
				return `{info.Name} ({getSeedCount(info.SeedItem)} seeds)`
			end,
			Activated = function()
				local wedge = selected()
				if wedge then
					send("SetFieldCrop", wedge, crop)
				end
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
		})
	end

	local function details()
		local buttons = {}
		for i, crop in FarmData.CROP_ORDER do
			local info = FarmData.GetCrop(crop)
			if info then
				table.insert(buttons, cropButton(info, i))
			end
		end

		local selectedUnlocked = function(): boolean
			local wedge = selected()
			return wedge ~= nil and FarmData.IsUnlocked(wedge, level())
		end

		return create("Frame")({
			Name = "Details",
			LayoutOrder = 2,
			Size = UDim2.fromOffset(DETAILS_WIDTH, PANEL_HEIGHT),
			BackgroundTransparency = 1,

			create("UIListLayout")({
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 4),
			}),

			create("TextLabel")({
				Name = "Title",
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				TextColor3 = TEXT_COLOR,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				TextSize = 14,
				Font = Enum.Font.GothamMedium,
				Text = function()
					local wedge = selected()
					if not wedge then
						return "Click a part of the field"
					end
					local info = FarmData.GetCrop(getPlot(wedge).Crop)
					local name = if info then info.Name else "Empty"
					return `Field {wedge}: {name}`
				end,
			}),
			create("TextLabel")({
				Name = "Info",
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				TextColor3 = MUTED_COLOR,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				TextSize = 12,
				Text = function()
					local wedge = selected()
					if not wedge then
						return "Crops regrow after every harvest."
					end
					if not FarmData.IsUnlocked(wedge, level()) then
						return `Unlocks at Lv {FarmData.WEDGE_UNLOCK_LEVEL[wedge]}`
					end
					local plot = getPlot(wedge)
					local info = FarmData.GetCrop(plot.Crop)
					if not info then
						return "Pick a crop to plant here."
					end
					if not plot.PlantedAt then
						return `Waiting for the Farmer to plant it (uses 1 {info.Name} Seed)`
					end
					local stage = FarmData.GetStage(plot, now())
					if stage >= FarmData.STAGES then
						return `Stage {stage}/{FarmData.STAGES}: ripe, waiting for the harvest`
					end
					local left = math.ceil(
						FarmData.GetGrowTime(info.Id) * (1 - FarmData.GetProgress(plot, now()))
					)
					return `Stage {stage}/{FarmData.STAGES}: ripe in {left}s`
				end,
			}),
			show(function()
				local wedge = selected()
				return wedge ~= nil and getPlot(wedge).PlantedAt ~= nil
			end, function()
				return create("Frame")({
					Name = "Progress",
					LayoutOrder = 3,
					Size = UDim2.new(1, 0, 0, 8),
					BackgroundColor3 = BAR_BACK_COLOR,
					BorderSizePixel = 0,
					create("Frame")({
						Size = function()
							local wedge = selected()
							local progress = if wedge
								then FarmData.GetProgress(getPlot(wedge), now())
								else 0
							return UDim2.fromScale(progress, 1)
						end,
						BackgroundColor3 = BAR_COLOR,
						BorderSizePixel = 0,
					}),
				})
			end),
			show(selectedUnlocked, function()
				return create("Frame")({
					Name = "Crops",
					LayoutOrder = 4,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					create("UIListLayout")({
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 4),
					}),
					buttons,
					show(function()
						local wedge = selected()
						return wedge ~= nil and getPlot(wedge).Crop ~= nil
					end, function()
						return create("TextButton")({
							Name = "Remove",
							LayoutOrder = 20,
							Size = UDim2.new(1, 0, 0, 24),
							BackgroundColor3 = REMOVE_COLOR,
							TextColor3 = TEXT_COLOR,
							TextSize = 13,
							Text = "Remove",
							Activated = function()
								local wedge = selected()
								if wedge then
									send("ClearFieldCrop", wedge)
								end
							end,
							create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
						})
					end),
				})
			end),
		})
	end

	local function farmerLine(): string
		for _, colonist in ColonistStore.Colonists() do
			if colonist.Workplace == HUT then
				local current = ColonistStore.GetStatus(colonist.Id)
				return if current ~= "" then `{colonist.Name}: {current}` else colonist.Name
			end
		end
		return "No Farmer yet"
	end

	local function seedLine(): string
		local parts = {}
		for _, crop in FarmData.CROP_ORDER do
			local info = FarmData.GetCrop(crop)
			if info then
				table.insert(parts, `{info.Name} {getSeedCount(info.SeedItem)}`)
			end
		end
		return `Seeds (hut + Farmer): {table.concat(parts, ", ")}`
	end

	local function line(name: string, order: number, text: () -> string, color: Color3)
		return create("TextLabel")({
			Name = name,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			TextSize = 13,
			Text = text,
		})
	end

	return create("Frame")({
		Name = "FieldPanel",
		LayoutOrder = layoutOrder,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,

		create("UIListLayout")({
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),

		show(function()
			return not built()
		end, function()
			return line("NotBuilt", 1, function()
				return "The field opens once the Farmer's Hut is built."
			end, MUTED_COLOR)
		end),

		show(built, function()
			return create("Frame")({
				Name = "Field",
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, PANEL_HEIGHT),
				BackgroundTransparency = 1,
				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 10),
				}),
				fan(),
				details(),
			})
		end),

		line("Seeds", 3, seedLine, TEXT_COLOR),
		line("Farmer", 4, farmerLine, MUTED_COLOR),
		line("Status", 5, status, TEXT_COLOR),
	})
end

return FieldPanel
