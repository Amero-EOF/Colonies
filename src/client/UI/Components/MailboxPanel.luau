--!strict

const HttpService = game:GetService("HttpService")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const Net = require(Packages.Net)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const MailboxData = require(Shared.Colony.MailboxData)
const ColonyStore = require(script.Parent.Parent.Parent.Colony.ColonyStore)

const create = vide.create
const derive = vide.derive
const effect = vide.effect
const show = vide.show
const source = vide.source
const untrack = vide.untrack

type Mail = ColonyTypes.Mail

const TEXT_COLOR = Color3.new(1, 1, 1)
const MUTED_COLOR = Color3.fromRGB(170, 170, 170)
const ITEMS_COLOR = Color3.fromRGB(215, 170, 60)
const UNREAD_COLOR = Color3.fromRGB(230, 130, 60)
const CARD_COLOR = Color3.fromRGB(45, 45, 45)
const COLLECT_COLOR = Color3.fromRGB(45, 90, 45)
const DELETE_COLOR = Color3.fromRGB(110, 45, 45)
const CLOSE_COLOR = Color3.fromRGB(70, 70, 70)
const PANEL_WIDTH = 440
const LIST_HEIGHT = 340

-- Newest first
local function sorted(mail: { Mail }): { Mail }
	local list = table.clone(mail)
	table.sort(list, function(a, b)
		if a.Time ~= b.Time then
			return a.Time > b.Time
		end
		return a.Id > b.Id
	end)
	return list
end

local function textLine(props: { [any]: any })
	props.Size = props.Size or UDim2.new(1, 0, 0, 0)
	props.AutomaticSize = Enum.AutomaticSize.Y
	props.BackgroundTransparency = 1
	props.TextXAlignment = Enum.TextXAlignment.Left
	props.TextYAlignment = Enum.TextYAlignment.Top
	props.TextWrapped = true
	return create("TextLabel")(props)
end

local function button(props: { [any]: any })
	props.TextColor3 = TEXT_COLOR
	props.TextSize = props.TextSize or 15
	table.insert(props, create("UICorner")({}))
	return create("TextButton")(props)
end

-- The Town Hall mailbox: letters newest first with their items, Collect / Delete per letter
-- and Collect all. Opened from the mailbox's prompt; closes when the player walks away.
local function MailboxPanel()
	local open = ColonyStore.MailboxOpen

	return show(open, function()
		local status = source("")
		local busy = false
		-- Letters unread since the panel opened keep their dot while it stays open
		local fresh: { [number]: boolean } = {}

		local function request(remote: string, id: number | string)
			if busy then
				return
			end
			busy = true
			status("...")
			task.spawn(function()
				local ok, result = pcall(function(): string
					local _, message = Net:Invoke(remote, id)
					return tostring(message)
				end)
				busy = false
				status(if ok then result else "Couldn't reach the mailbox")
			end)
		end

		-- Opening the panel (and mail arriving while it's open) marks letters read
		effect(function()
			local unread = false
			for _, mail in ColonyStore.Mail() do
				if not mail.Read and not fresh[mail.Id] then
					fresh[mail.Id] = true
					unread = true
				end
			end
			if unread then
				task.spawn(function()
					Net:RemoteEvent("ReadMail"):FireServer("All")
				end)
			end
		end)

		-- Only rebuild the letters when they actually changed (the colony state is resent often)
		local signature = derive(function()
			return HttpService:JSONEncode(ColonyStore.Mail())
		end)

		local function letterCard(mail: Mail, index: number)
			local hasItems = #mail.Items > 0
			local children: { any } = {
				create("UICorner")({}),
				create("UIPadding")({
					PaddingLeft = UDim.new(0, 8),
					PaddingRight = UDim.new(0, 8),
					PaddingTop = UDim.new(0, 6),
					PaddingBottom = UDim.new(0, 6),
				}),
				create("UIListLayout")({
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 3),
				}),

				create("Frame")({
					Name = "Header",
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 18),
					BackgroundTransparency = 1,

					create("Frame")({
						Name = "UnreadDot",
						AnchorPoint = Vector2.new(0, 0.5),
						Position = UDim2.fromScale(0, 0.5),
						Size = UDim2.fromOffset(8, 8),
						BackgroundColor3 = UNREAD_COLOR,
						Visible = fresh[mail.Id] == true or not mail.Read,
						create("UICorner")({ CornerRadius = UDim.new(1, 0) }),
					}),
					create("TextLabel")({
						Name = "From",
						Position = UDim2.fromOffset(14, 0),
						Size = UDim2.new(1, -124, 1, 0),
						BackgroundTransparency = 1,
						TextColor3 = TEXT_COLOR,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
						TextSize = 15,
						Font = Enum.Font.GothamMedium,
						Text = mail.From,
					}),
					create("TextLabel")({
						Name = "Date",
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.fromScale(1, 0),
						Size = UDim2.new(0, 110, 1, 0),
						BackgroundTransparency = 1,
						TextColor3 = MUTED_COLOR,
						TextXAlignment = Enum.TextXAlignment.Right,
						TextSize = 12,
						Text = os.date("%d %b %H:%M", math.floor(mail.Time)),
					}),
				}),
			}

			if mail.Title then
				table.insert(
					children,
					textLine({
						Name = "Title",
						LayoutOrder = 2,
						TextColor3 = TEXT_COLOR,
						TextSize = 14,
						Font = Enum.Font.GothamBold,
						Text = mail.Title,
					})
				)
			end
			if mail.Body then
				table.insert(
					children,
					textLine({
						Name = "Body",
						LayoutOrder = 3,
						TextColor3 = MUTED_COLOR,
						TextSize = 13,
						Text = mail.Body,
					})
				)
			end
			if hasItems then
				table.insert(
					children,
					textLine({
						Name = "Items",
						LayoutOrder = 4,
						TextColor3 = ITEMS_COLOR,
						TextSize = 13,
						Text = `Items: {MailboxData.DescribeItems(mail.Items)}`,
					})
				)
			end

			table.insert(
				children,
				create("Frame")({
					Name = "Actions",
					LayoutOrder = 5,
					Size = UDim2.new(1, 0, 0, 28),
					BackgroundTransparency = 1,

					button({
						Name = if hasItems then "Collect" else "Delete",
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.fromScale(1, 0),
						Size = UDim2.fromOffset(90, 28),
						BackgroundColor3 = if hasItems then COLLECT_COLOR else DELETE_COLOR,
						Text = if hasItems then "Collect" else "Delete",
						Activated = function()
							request(if hasItems then "CollectMail" else "DeleteMail", mail.Id)
						end,
					}),
				})
			)

			return create("Frame")({
				Name = `Letter_{mail.Id}`,
				LayoutOrder = index,
				Size = UDim2.new(1, -8, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = CARD_COLOR,
				children,
			})
		end

		local function letters()
			signature()
			return untrack(function()
				local list = sorted(ColonyStore.Mail())
				if #list == 0 then
					return {
						textLine({
							Name = "Empty",
							TextColor3 = MUTED_COLOR,
							TextSize = 15,
							Text = "Your mailbox is empty.",
						}),
					}
				end
				local cards = {}
				for i, mail in list do
					table.insert(cards, letterCard(mail, i))
				end
				return cards
			end)
		end

		status("")

		return create("Frame")({
			Name = "MailboxPanel",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(PANEL_WIDTH, 0),
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
				Font = Enum.Font.GothamMedium,
				Text = function()
					local count = #ColonyStore.Mail()
					return if count == 1 then "Mailbox (1 letter)" else `Mailbox ({count} letters)`
				end,
			}),

			create("ScrollingFrame")({
				Name = "Letters",
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, LIST_HEIGHT),
				BackgroundTransparency = 1,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollBarThickness = 6,

				create("UIListLayout")({
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 6),
				}),

				letters,
			}),

			create("TextLabel")({
				Name = "Status",
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				TextColor3 = TEXT_COLOR,
				TextSize = 15,
				TextWrapped = true,
				Text = status,
			}),

			create("Frame")({
				Name = "Buttons",
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 0, 34),
				BackgroundTransparency = 1,

				create("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 8),
				}),

				button({
					Name = "CollectAll",
					Size = UDim2.new(0.5, -4, 1, 0),
					BackgroundColor3 = COLLECT_COLOR,
					TextSize = 16,
					Text = "Collect all",
					Activated = function()
						request("CollectMail", "All")
					end,
				}),

				button({
					Name = "Close",
					Size = UDim2.new(0.5, -4, 1, 0),
					BackgroundColor3 = CLOSE_COLOR,
					TextSize = 16,
					Text = "Close",
					Activated = function()
						open(false)
					end,
				}),
			}),
		})
	end)
end

return MailboxPanel
