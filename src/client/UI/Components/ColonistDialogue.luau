--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const Net = require(Packages.Net)
const ColonistTypes = require(Shared.Colonist.ColonistTypes)
const Conversation = require(Shared.Colonist.Conversation)
const ColonistStore = require(script.Parent.Parent.Parent.Colony.ColonistStore)
const ColonyStore = require(script.Parent.Parent.Parent.Colony.ColonyStore)

const create = vide.create
const show = vide.show
const derive = vide.derive
const untrack = vide.untrack

type Dialogue = ColonistTypes.Dialogue
type OpenDialogue = ColonistStore.OpenDialogue

const TEXT_COLOR = Color3.new(1, 1, 1)
const NAME_COLOR = Color3.fromRGB(255, 210, 110)
const QUEST_COLOR = Color3.fromRGB(255, 205, 40)
const PANEL_COLOR = Color3.fromRGB(30, 30, 30)
const REPLY_COLOR = Color3.fromRGB(60, 60, 70)
const GREEN_BUTTON = Color3.fromRGB(45, 90, 45)
const RED_BUTTON = Color3.fromRGB(110, 50, 50)
const GREY_BUTTON = Color3.fromRGB(70, 70, 70)
const WIDTH = 560
const PORTRAIT_SIZE = 130
-- Keeps the frame above the default Roblox tool hotbar
const BOTTOM_OFFSET = 84

local busy = false

local function close()
	ColonistStore.EndTalk()
end

-- Calls a dialogue remote; the colonist's reply line replaces the frame's text, errors become a toast
local function request(open: OpenDialogue, remote: string, arg: any)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local line, message = Net:Invoke(remote, open.Id, arg)
		busy = false
		if typeof(line) == "string" then
			ColonistStore.Dialogue({
				Id = open.Id,
				Dialogue = {
					Kind = "Talk",
					Line = line,
					Replies = {},
					-- A reply uses up the day's chat; a quest answer doesn't
					CanTalk = remote ~= "ReplyColonist" and open.Dialogue.CanTalk,
				},
			})
		elseif message then
			ColonyStore.Notify(tostring(message))
		end
	end)
end

local function button(
	text: string,
	layoutOrder: number,
	color: Color3,
	onClick: () -> (),
	size: UDim2?
)
	return create("TextButton")({
		LayoutOrder = layoutOrder,
		Size = size or UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = color,
		TextColor3 = TEXT_COLOR,
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
		Activated = onClick,
		create("UICorner")({}),
		create("UIPadding")({ PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
	})
end

-- A still of the colonist's rig (cloned from workspace.MyColonists), framed on the head
local function portrait(id: number)
	local viewport = create("ViewportFrame")({
		Name = "Portrait",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0, -8, 1, 0),
		Size = UDim2.fromOffset(PORTRAIT_SIZE, PORTRAIT_SIZE),
		BackgroundColor3 = PANEL_COLOR,
		BackgroundTransparency = 0.05,
		Ambient = Color3.fromRGB(200, 200, 200),
		LightColor = Color3.new(1, 1, 1),
		create("UICorner")({}),
		create("UIStroke")({
			Color = function()
				local open = ColonistStore.Dialogue()
				return if open and open.Dialogue.Kind == "Quest" then QUEST_COLOR else GREY_BUTTON
			end,
			Thickness = 2,
		}),
	})

	local folder = workspace:FindFirstChild("MyColonists")
	local rig: Model? = nil
	for _, child in (if folder then folder:GetChildren() else {}) do
		if child:IsA("Model") and child:GetAttribute("ColonistId") == id then
			rig = child
			break
		end
	end
	if not rig then
		return viewport
	end

	local clone = rig:Clone()
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BillboardGui") or descendant:IsA("ProximityPrompt") then
			descendant:Destroy()
		end
	end
	clone.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	local head = clone:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		-- Head and shoulders, from the front
		local size = head.Size.Y
		local focus = head.Position - Vector3.new(0, size * 0.35, 0)
		camera.CFrame = CFrame.lookAt(focus + head.CFrame.LookVector * size * 4.5, focus)
	end
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport
end

-- The choices for the open dialogue: replies, quest answers, and "Chat" when the day's chat is left
local function choices(open: OpenDialogue): { Instance }
	local dialogue = open.Dialogue
	local items = {}
	for i, text in dialogue.Replies do
		table.insert(
			items,
			button(`"{text}"`, i, REPLY_COLOR, function()
				request(open, "ReplyColonist", i)
			end)
		)
	end

	local quest = dialogue.Quest
	if dialogue.Kind == "Quest" and quest then
		local pending = quest.State == "Pending"
		table.insert(
			items,
			button(if pending then "Accept quest" else "Hand in items", 10, GREEN_BUTTON, function()
				request(open, "ColonistQuest", if pending then "Accept" else "Complete")
			end)
		)
		table.insert(
			items,
			button(if pending then "Decline quest" else "Abandon quest", 11, RED_BUTTON, function()
				request(open, "ColonistQuest", "Decline")
			end)
		)
	end

	if dialogue.CanTalk and #dialogue.Replies == 0 then
		table.insert(
			items,
			button("Chat", 20, REPLY_COLOR, function()
				ColonistStore.Talk(open.Id, true)
			end)
		)
	end
	return items
end

-- Conversation frame centred above the hotbar: name top-left, portrait to the left. Quest
-- conversations get a gold border and a "! QUEST" tag.
local function ColonistDialogue()
	return show(function()
		return ColonistStore.Dialogue() ~= nil
	end, function()
		-- Keeps the last dialogue so bindings never see nil while the frame closes
		local last = ColonistStore.Dialogue() :: OpenDialogue
		local current = derive(function(): OpenDialogue
			last = ColonistStore.Dialogue() or last
			return last
		end)
		local openId = derive(function(): number
			return current().Id
		end)
		local isQuest = derive(function(): boolean
			return current().Dialogue.Kind == "Quest"
		end)

		return create("Frame")({
			Name = "ColonistDialogue",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -BOTTOM_OFFSET),
			Size = UDim2.fromOffset(WIDTH, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,

			function()
				local id = openId()
				return untrack(function()
					return portrait(id)
				end)
			end,

			create("Frame")({
				Name = "Panel",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = PANEL_COLOR,
				BackgroundTransparency = 0.05,

				create("UICorner")({}),
				create("UIStroke")({
					Color = function()
						return if isQuest() then QUEST_COLOR else GREY_BUTTON
					end,
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
					Padding = UDim.new(0, 6),
				}),

				create("Frame")({
					Name = "Header",
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 24),
					BackgroundTransparency = 1,
					create("TextLabel")({
						Name = "ColonistName",
						Size = UDim2.new(1, -110, 1, 0),
						BackgroundTransparency = 1,
						TextColor3 = NAME_COLOR,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextSize = 20,
						Font = Enum.Font.GothamBold,
						Text = function()
							local colonist = ColonistStore.Get(openId())
							return if colonist then colonist.Name else ""
						end,
					}),
					show(isQuest, function()
						return create("TextLabel")({
							Name = "QuestTag",
							AnchorPoint = Vector2.new(1, 0),
							Position = UDim2.fromScale(1, 0),
							Size = UDim2.fromOffset(100, 24),
							BackgroundColor3 = QUEST_COLOR,
							TextColor3 = Color3.fromRGB(40, 30, 0),
							TextSize = 15,
							Font = Enum.Font.GothamBlack,
							Text = "! QUEST",
							create("UICorner")({}),
						})
					end),
				}),

				create("TextLabel")({
					Name = "Line",
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					TextColor3 = TEXT_COLOR,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = true,
					TextSize = 17,
					Text = function()
						return `"{current().Dialogue.Line}"`
					end,
				}),

				show(isQuest, function()
					return create("TextLabel")({
						Name = "QuestDetails",
						LayoutOrder = 3,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
						TextColor3 = QUEST_COLOR,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextWrapped = true,
						TextSize = 15,
						Text = function()
							local quest = current().Dialogue.Quest
							return if quest
								then `{quest.Title}: {Conversation.Describe(quest)}`
								else ""
						end,
					})
				end),

				create("Frame")({
					Name = "Choices",
					LayoutOrder = 4,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					create("UIListLayout")({
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 4),
					}),
					function()
						local open = current()
						return untrack(function()
							return choices(open)
						end)
					end,
				}),

				create("Frame")({
					Name = "Footer",
					LayoutOrder = 5,
					Size = UDim2.new(1, 0, 0, 28),
					BackgroundTransparency = 1,
					create("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Right,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 6),
					}),
					button("Stats", 1, Color3.fromRGB(70, 90, 140), function()
						ColonistStore.SelectedId(current().Id)
						close()
					end, UDim2.fromOffset(110, 28)),
					button("Goodbye", 2, GREY_BUTTON, close, UDim2.fromOffset(110, 28)),
				}),
			}),
		})
	end)
end

return ColonistDialogue
