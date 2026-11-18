--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const Net = require(Packages.Net)
const ItemsList = require(Shared.Inventory.ItemsList)
const MerchantData = require(Shared.Merchant.MerchantData)
const attributeSource = require(script.Parent.Parent.attributeSource)
const MerchantNpc = require(script.Parent.MerchantNpc)

const create = vide.create
const effect = vide.effect
const show = vide.show
const source = vide.source

type Offer = MerchantData.Offer

const TEXT_COLOR = Color3.new(1, 1, 1)
const MUTED_COLOR = Color3.fromRGB(180, 180, 180)
const PRICE_COLOR = Color3.fromRGB(215, 170, 60)
const CARD_COLOR = Color3.fromRGB(45, 45, 45)
const BUY_COLOR = Color3.fromRGB(45, 90, 45)
const CARD_HEIGHT = 76

local function getName(offer: Offer): string
	local id = ItemsList.GetItemId(offer.ItemType)
	local name = (id and ItemsList.GetDisplayName(id)) or offer.ItemType
	local quantity = offer.Quantity or 1
	return if quantity > 1 then `{quantity} {name}` else name
end

-- The travelling merchant (drawn in the world while he's visiting) and his shop panel,
-- opened from his "Trade" prompt
local function MerchantShop()
	local open = source(false)
	local status = source("")
	local leavesAt = attributeSource(MerchantData.ATTRIBUTE)
	local busy = false

	local present = function(): boolean
		local value = leavesAt()
		return typeof(value) == "number" and value > 0
	end

	-- His rig lives in workspace, so it isn't a child of the ScreenGui
	show(present, function()
		return MerchantNpc({
			OnTrade = function(isOpen: boolean)
				open(isOpen)
			end,
		})
	end)

	-- Closed when he leaves, so it doesn't pop open on his next visit
	effect(function()
		if not present() then
			open(false)
		end
	end)

	local function buy(offer: Offer)
		if busy then
			return
		end
		busy = true
		status("...")
		task.spawn(function()
			local ok, result = pcall(function(): string
				local _, message = Net:Invoke("BuyFromMerchant", offer.Id)
				return tostring(message)
			end)
			busy = false
			status(if ok then result else "Couldn't reach the merchant")
		end)
	end

	local function offerCard(offer: Offer, index: number)
		return create("Frame")({
			Name = `Offer_{offer.Id}`,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, CARD_HEIGHT),
			BackgroundColor3 = CARD_COLOR,

			create("UICorner")({}),
			create("UIPadding")({
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
				PaddingTop = UDim.new(0, 6),
				PaddingBottom = UDim.new(0, 6),
			}),

			create("TextLabel")({
				Name = "ItemName",
				Size = UDim2.new(1, -96, 0, 20),
				BackgroundTransparency = 1,
				TextColor3 = TEXT_COLOR,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextSize = 16,
				Font = Enum.Font.GothamMedium,
				Text = getName(offer),
			}),
			create("TextLabel")({
				Name = "Description",
				Position = UDim2.fromOffset(0, 22),
				Size = UDim2.new(1, -96, 0, 30),
				BackgroundTransparency = 1,
				TextColor3 = MUTED_COLOR,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextWrapped = true,
				TextSize = 12,
				Text = offer.Description,
			}),
			create("TextLabel")({
				Name = "Price",
				Position = UDim2.new(1, -88, 0, 0),
				Size = UDim2.fromOffset(88, 20),
				BackgroundTransparency = 1,
				TextColor3 = PRICE_COLOR,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextSize = 13,
				Text = MerchantData.DescribePrice(offer),
			}),
			create("TextButton")({
				Name = "Buy",
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.fromScale(1, 1),
				Size = UDim2.fromOffset(80, 30),
				BackgroundColor3 = BUY_COLOR,
				TextColor3 = TEXT_COLOR,
				TextSize = 16,
				Text = "Buy",
				Activated = function()
					buy(offer)
				end,

				create("UICorner")({}),
			}),
		})
	end

	local function offerCards()
		local cards = {}
		for i, offer in MerchantData.OFFERS do
			table.insert(cards, offerCard(offer, i))
		end
		return cards
	end

	return show(function()
		return open() and present()
	end, function()
		status("")

		return create("Frame")({
			Name = "MerchantShop",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(380, 0),
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
				Text = MerchantData.NAME,
			}),

			create("Frame")({
				Name = "Offers",
				LayoutOrder = 1,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,

				create("UIListLayout")({
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 6),
				}),

				offerCards(),
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

			create("TextButton")({
				Name = "Close",
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 0, 34),
				BackgroundColor3 = Color3.fromRGB(70, 70, 70),
				TextColor3 = TEXT_COLOR,
				TextSize = 16,
				Text = "Close",
				Activated = function()
					open(false)
				end,

				create("UICorner")({}),
			}),
		})
	end)
end

return MerchantShop
