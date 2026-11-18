--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const Net = require(Packages.Net)
const BuildingData = require(Shared.Buildings.BuildingData)
const BuildingUnlocks = require(Shared.Buildings.BuildingUnlocks)
const BagMoves = require(Shared.Inventory.BagMoves)
const ColonistData = require(Shared.Colonist.ColonistData)
const ColonistTypes = require(Shared.Colonist.ColonistTypes)
const Conversation = require(Shared.Colonist.Conversation)
const JobData = require(Shared.Colonist.JobData)
const ColonistStore = require(script.Parent.Parent.Parent.Colony.ColonistStore)
const ColonyStore = require(script.Parent.Parent.Parent.Colony.ColonyStore)
const BagGrid = require(script.Parent.BagGrid)

const create = vide.create
const show = vide.show
const derive = vide.derive

type Colonist = ColonistTypes.Colonist

const TEXT_COLOR = Color3.new(1, 1, 1)
const MUTED_COLOR = Color3.fromRGB(190, 190, 190)
const PRIMARY_COLOR = Color3.fromRGB(255, 210, 110)
const PANEL_SIZE = Vector2.new(320, 470)
const EMPTY_COLOR = Color3.fromRGB(50, 50, 50)
const ANGRY_COLOR = Color3.fromRGB(200, 60, 60)
const HAPPY_COLOR = Color3.fromRGB(90, 190, 90)
const GREY_BUTTON = Color3.fromRGB(70, 70, 70)

local function label(text: string | () -> string, layoutOrder: number, props: { [string]: any }?)
	local properties: { [string]: any } = {
		LayoutOrder = layoutOrder,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		TextColor3 = TEXT_COLOR,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		TextSize = 15,
		Text = text,
	}
	for key, value in (props or {}) :: { [string]: any } do
		properties[key] = value
	end
	return create("TextLabel")(properties)
end

-- A labelled bar (health, hunger, happiness)
local function bar(
	name: string,
	layoutOrder: number,
	color: Color3,
	value: () -> number,
	max: number
)
	return create("Frame")({
		LayoutOrder = layoutOrder,
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundColor3 = Color3.fromRGB(50, 50, 50),

		create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
		create("Frame")({
			Size = function()
				return UDim2.fromScale(math.clamp(value() / max, 0, 1), 1)
			end,
			BackgroundColor3 = color,
			create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
		}),
		create("TextLabel")({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			TextColor3 = TEXT_COLOR,
			TextStrokeTransparency = 0.6,
			TextSize = 13,
			ZIndex = 2,
			Text = function()
				return `{name}: {math.floor(value() * 10 + 0.5) / 10}/{max}`
			end,
		}),
	})
end

-- Relationship split into RELATIONSHIP_MAX sections, filled up to the value (0 Angry -> 5 Happy)
-- Relationship split into RELATIONSHIP_MAX sections (0 Angry -> 5 Happy); each section fills
-- partially, so 3.4 is three full sections and 40% of the fourth
local function relationshipBar(layoutOrder: number, value: () -> number)
	local max = ColonistData.RELATIONSHIP_MAX
	local fillColor = function(): Color3
		return ANGRY_COLOR:Lerp(HAPPY_COLOR, math.clamp(value() / max, 0, 1))
	end
	local sections = {}
	for i = 1, max do
		table.insert(
			sections,
			create("Frame")({
				LayoutOrder = i,
				Size = UDim2.new(1 / max, -3, 1, 0),
				BackgroundColor3 = EMPTY_COLOR,
				ClipsDescendants = true,
				create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
				create("Frame")({
					Size = function()
						return UDim2.fromScale(math.clamp(value() - (i - 1), 0, 1), 1)
					end,
					BackgroundColor3 = fillColor,
					BorderSizePixel = 0,
					create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
				}),
			})
		)
	end
	return create("Frame")({
		LayoutOrder = layoutOrder,
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		create("TextLabel")({
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			TextColor3 = TEXT_COLOR,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 13,
			Text = function()
				local relationship = value()
				local percent = math.floor(relationship / max * 100 + 0.5)
				return `Relationship: {Conversation.GetMood(relationship)} ({percent}%)`
			end,
		}),
		create("Frame")({
			Position = UDim2.fromOffset(0, 18),
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 3),
			}),
			sections,
		}),
	})
end

local function button(
	text: string | () -> string,
	layoutOrder: number,
	color: Color3,
	onClick: () -> ()
)
	return create("TextButton")({
		LayoutOrder = layoutOrder,
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = color,
		TextColor3 = TEXT_COLOR,
		TextSize = 15,
		TextWrapped = true,
		Text = text,
		Activated = onClick,
		create("UICorner")({}),
	})
end

-- A boxed vertical list
local function section(layoutOrder: number, color: Color3, children: { any })
	return create("Frame")({
		LayoutOrder = layoutOrder,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = color,
		create("UICorner")({}),
		create("UIPadding")({
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
		}),
		create("UIListLayout")({
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
		children,
	})
end

-- Calls a remote outside the UI scope and shows its message
local function invoke(name: string, ...: any)
	local args = table.pack(...)
	task.spawn(function()
		local _, message = Net:Invoke(name, table.unpack(args, 1, args.n))
		if message and message ~= "" then
			ColonyStore.Notify(tostring(message))
		end
	end)
end

-- Housing buildings a colonist could move into, as "Id:freeBeds" entries (a string so it only changes on real changes)
local function getHomeChoices(colonist: Colonist): string
	local entries = {}
	for _, saved in ColonyStore.Buildings() do
		local housing = BuildingData[saved.Id].Components.Housing
		if
			saved.Id == colonist.Home
			or not housing
			or not saved.Placement
			or not BuildingUnlocks.IsBuilt(saved.Id, saved.Level)
		then
			continue
		end
		local beds = housing.Capacity + (housing.CapacityPerLevel or 0) * saved.Level
		if beds <= 0 then
			continue
		end
		for _, other in ColonistStore.Colonists() do
			if other.Home == saved.Id then
				beds -= 1
			end
		end
		table.insert(entries, `{saved.Id}:{beds}`)
	end
	return table.concat(entries, ",")
end

local function buildingName(id: string?): string
	local data = id and (BuildingData :: any)[id]
	return if data then data.Name else "None"
end

-- Opened by talking to a colonist: needs, traits and family
local function ColonistPanel()
	return show(function()
		return ColonistStore.Get(ColonistStore.SelectedId()) ~= nil
	end, function()
		-- Keeps the last known colonist so labels never see nil while the panel closes
		local last: Colonist = ColonistStore.Get(ColonistStore.SelectedId()) :: Colonist
		local colonist = derive(function(): Colonist
			last = ColonistStore.Get(ColonistStore.SelectedId()) or last
			return last
		end)
		local current = colonist

		local questState = derive(function(): string?
			local quest = current().Quest
			return quest and quest.State
		end)
		local homeChoices = derive(function(): string
			return getHomeChoices(current())
		end)

		local skillLines = {}
		for i, skill in ColonistData.SKILLS do
			table.insert(
				skillLines,
				label(
					function()
						local c = current()
						local traits = c.Job and JobData.Get(c.Job)
						local marker = ""
						if traits and traits.Primary == skill then
							marker = "  (primary)"
						elseif traits and traits.Secondary == skill then
							marker = "  (secondary)"
						end
						return `{skill}: {c.Skills[skill] or 0}{marker}`
					end,
					100 + i,
					{
						TextSize = 14,
						TextColor3 = function()
							local c = current()
							local traits = c.Job and JobData.Get(c.Job)
							if
								traits and (traits.Primary == skill or traits.Secondary == skill)
							then
								return PRIMARY_COLOR
							end
							return MUTED_COLOR
						end,
					}
				)
			)
		end

		return create("Frame")({
			Name = "ColonistPanel",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -16, 0.5, 0),
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

			create("TextButton")({
				Name = "Close",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.fromOffset(30, 26),
				BackgroundColor3 = Color3.fromRGB(110, 50, 50),
				TextColor3 = TEXT_COLOR,
				TextSize = 16,
				Text = "X",
				ZIndex = 2,
				Activated = function()
					ColonistStore.SelectedId(nil)
					ColonistStore.FamilyTreeId(nil)
				end,
				create("UICorner")({}),
			}),

			create("ScrollingFrame")({
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollBarThickness = 6,

				create("UIListLayout")({
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 5),
				}),

				label(function()
					return current().Name
				end, 1, { TextSize = 20, Size = UDim2.new(1, -36, 0, 0) }),
				label(function()
					local c = current()
					local age = if c.Age == "Child" then "Child" else "Adult"
					return `{c.Gender} {age}  -  {c.Job or (if c.Age == "Child"
						then "Too young to work"
						else "Unemployed")}`
				end, 2, { TextColor3 = MUTED_COLOR }),
				label(function()
					return ColonistStore.GetStatus(current().Id)
				end, 3, { TextColor3 = MUTED_COLOR, TextSize = 14 }),

				bar("Health", 10, Color3.fromRGB(200, 60, 60), function()
					return current().Health
				end, ColonistData.MAX_HEALTH),
				bar("Hunger", 11, Color3.fromRGB(200, 140, 60), function()
					return current().Saturation
				end, ColonistData.MAX_SATURATION),
				bar("Happiness", 12, Color3.fromRGB(90, 170, 90), function()
					return current().Happiness
				end, ColonistData.MAX_HAPPINESS),
				relationshipBar(14, function()
					return current().Relationship
				end),

				show(questState, function()
					return label(function()
						local quest = current().Quest
						if not quest then
							return ""
						end
						local state = if quest.State == "Pending"
							then "awaiting your answer"
							else "accepted"
						return `Quest ({state}): {Conversation.Describe(quest)}`
					end, 15, { TextColor3 = Color3.fromRGB(255, 205, 40), TextSize = 14 })
				end),

				label(
					function()
						local c = current()
						local notes = {}
						if c.Debuff == "Fight" then
							table.insert(
								notes,
								"Fight: miserable, refuses to work and is wasting away"
							)
						elseif c.Leaving then
							table.insert(notes, "Flight: leaving the colony")
						end
						if c.Sick then
							table.insert(notes, "Sick")
						end
						if c.WokenDay then
							table.insert(notes, "Was woken at night (eats double)")
						end
						return table.concat(notes, "\n")
					end,
					13,
					{
						TextColor3 = Color3.fromRGB(255, 140, 140),
						TextSize = 14,
					}
				),

				label(function()
					return `Home: {buildingName(current().Home)}`
				end, 20),
				label(function()
					return `Workplace: {buildingName(current().Workplace)}`
				end, 21),
				section(22, Color3.fromRGB(40, 40, 50), {
					function()
						local entries = homeChoices()
						if entries == "" then
							return label("No other home with beds to move to", 1, {
								TextColor3 = MUTED_COLOR,
								TextSize = 14,
							})
						end
						local children = { label("Move residence to:", 1, { TextSize = 14 }) }
						for i, entry in string.split(entries, ",") do
							local id, free = string.match(entry, "^(.-):(%-?%d+)$")
							local freeBeds = tonumber(free) or 0
							local text = if freeBeds > 0
								then `{buildingName(id)} ({freeBeds} free bed{if freeBeds == 1
									then ""
									else "s"})`
								else `{buildingName(id)} (full)`
							table.insert(
								children,
								button(
									text,
									1 + i,
									if freeBeds > 0
										then Color3.fromRGB(60, 80, 130)
										else GREY_BUTTON,
									function()
										invoke("MoveColonistHome", current().Id, id)
									end
								)
							)
						end
						return children
					end,
				}),

				label("Inventory", 24, { TextSize = 17 }),
				BagGrid.BagGrid({
					Name = "Carried",
					LayoutOrder = 25,
					Columns = 5,
					Bag = function()
						return current().Carried
					end,
					Ref = function(): string?
						return BagMoves.ColonistRef(current().Id)
					end,
				}),
				show(function()
					return ColonistStore.GetStatus(current().Id) == "Sleeping"
				end, function()
					return create("TextButton")({
						LayoutOrder = 27,
						Size = UDim2.new(1, 0, 0, 28),
						BackgroundColor3 = Color3.fromRGB(140, 90, 40),
						TextColor3 = TEXT_COLOR,
						TextSize = 15,
						Text = "Wake up (unhappy, eats double)",
						Activated = function()
							local id = current().Id
							task.spawn(function()
								local _, message = Net:Invoke("WakeColonist", id)
								ColonyStore.Notify(tostring(message))
							end)
						end,
						create("UICorner")({}),
					})
				end),

				create("TextButton")({
					LayoutOrder = 26,
					Size = UDim2.new(1, 0, 0, 28),
					BackgroundColor3 = Color3.fromRGB(45, 90, 45),
					TextColor3 = TEXT_COLOR,
					TextSize = 15,
					Text = function()
						local job = current().Job
						return if job == "Builder"
							then "Give food / materials"
							elseif job == "Farmer" then "Give food / seeds"
							else "Give food"
					end,
					Activated = function()
						local id = current().Id
						task.spawn(function()
							local _, message = Net:Invoke("GiveColonist", id)
							ColonyStore.Notify(tostring(message))
						end)
					end,
					create("UICorner")({}),
				}),

				create("TextButton")({
					LayoutOrder = 30,
					Size = UDim2.new(1, 0, 0, 28),
					BackgroundColor3 = Color3.fromRGB(70, 90, 140),
					TextColor3 = TEXT_COLOR,
					TextSize = 15,
					Text = "Family Tree",
					Activated = function()
						local id = current().Id
						ColonistStore.FamilyTreeId(
							if ColonistStore.FamilyTreeId() == id then nil else id
						)
					end,
					create("UICorner")({}),
				}),

				label("Traits", 100, { TextSize = 17 }),
				skillLines,
			}),
		})
	end)
end

return ColonistPanel
