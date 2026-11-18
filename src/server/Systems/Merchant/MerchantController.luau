--!strict

const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared
const Packages = ReplicatedStorage.Packages
const Systems = script.Parent.Parent

const Net = require(Packages.Net)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const ItemsList = require(Shared.Inventory.ItemsList)
const MerchantData = require(Shared.Merchant.MerchantData)
const ColonyController = require(Systems.Colony.ColonyController)
const ColonyLog = require(Systems.Colony.Components.ColonyLog)
const MailboxController = require(Systems.Colony.MailboxController)
const Notifications = require(Systems.Colony.Components.Notifications)
const Bag = require(Systems.Inventory.Components.Bag)
const InventoryController = require(Systems.Inventory.InventoryController)

type ColonyData = ColonyTypes.ColonyData
type MerchantVisit = ColonyTypes.MerchantVisit

const TICK = 1
-- Extra studs the server allows past the Trade prompt's reach (lag)
const REACH_TOLERANCE = 6
-- Only announce a departure the player was around for (not one that happened while offline)
const LEAVE_NOTICE_WINDOW = 10

-- The travelling merchant visits every player's colony beside its Town Hall every few
-- in-game days and stays one day. The schedule is saved with the colony and follows server
-- time, so it carries on across rejoins. The owner's client draws him from the player attribute.
const MerchantController = {}

local started = false

-- The saved schedule (older saves get one)
local function getVisit(data: ColonyData): MerchantVisit
	local visit = (data :: any).Merchant :: MerchantVisit?
	if not visit then
		local fresh: MerchantVisit = { NextArrival = 0, LeavesAt = 0 }
		data.Merchant = fresh
		return fresh
	end
	return visit
end

local function isTownHallPlaced(data: ColonyData): boolean
	for _, saved in data.Buildings do
		if saved.Id == "TownHall" then
			return saved.Placement ~= nil
		end
	end
	return false
end

local function setAttribute(player: Player, visit: MerchantVisit)
	local value = if visit.LeavesAt > 0 then visit.LeavesAt else nil
	if player:GetAttribute(MerchantData.ATTRIBUTE) ~= value then
		player:SetAttribute(MerchantData.ATTRIBUTE, value)
	end
end

local function arrive(player: Player, data: ColonyData)
	ColonyLog.Add(data, "A travelling merchant has arrived beside the Town Hall")
	Notifications.Send(player, "Merchant", "A travelling merchant has arrived")
	ColonyController.Sync(player)
end

local function leave(player: Player, data: ColonyData, now: number, leftAt: number)
	ColonyLog.Add(data, "The travelling merchant has moved on")
	if now - leftAt <= LEAVE_NOTICE_WINDOW then
		Notifications.Send(player, "Merchant", "The travelling merchant has left")
	end
	ColonyController.Sync(player)
end

-- Advances one colony's schedule to `now`
local function update(player: Player, data: ColonyData, now: number)
	local visit = getVisit(data)

	-- He only visits a placed Town Hall; the schedule starts once it's placed
	if not isTownHallPlaced(data) then
		visit.NextArrival = 0
		visit.LeavesAt = 0
		setAttribute(player, visit)
		return
	end
	if visit.NextArrival <= 0 then
		visit.NextArrival = MerchantData.GetFirstArrival(now)
	end

	if visit.LeavesAt > 0 and now >= visit.LeavesAt then
		local leftAt = visit.LeavesAt
		visit.LeavesAt = 0
		leave(player, data, now, leftAt)
	end

	if visit.LeavesAt == 0 and now >= visit.NextArrival then
		-- Visits that ended while the player was away are skipped
		local arrival = MerchantData.GetLatestArrival(visit.NextArrival, now)
		visit.NextArrival = arrival + MerchantData.VISIT_INTERVAL
		if now < arrival + MerchantData.STAY_TIME then
			visit.LeavesAt = arrival + MerchantData.STAY_TIME
			arrive(player, data)
		end
	end

	setAttribute(player, visit)
end

local function tick()
	local now = workspace:GetServerTimeNow()
	for _, player in ColonyController.GetLoadedPlayers() do
		local data = ColonyController.GetData(player)
		if data then
			local ok, err = pcall(function()
				update(player, data, now)
			end)
			if not ok then
				warn(`[Merchant] {player.Name}: {err}`)
			end
		end
	end
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- "Buy" in the merchant's shop: one of the offer's item into the backpack
local function onBuy(player: Player, offerId: unknown): (boolean, string)
	local offer = if typeof(offerId) == "string" then MerchantData.GetOffer(offerId) else nil
	if not offer then
		return false, "The merchant doesn't sell that"
	end
	local data = ColonyController.GetData(player)
	if not data then
		return false, "Colony not loaded"
	end

	local visit = getVisit(data)
	if visit.LeavesAt <= workspace:GetServerTimeNow() then
		return false, "The merchant isn't here"
	end

	local spot = MerchantData.GetSpot(data.Buildings)
	local root = getRoot(player)
	if not spot or not root then
		return false, "Stand next to the merchant"
	end
	local offset = spot.Position - root.Position
	if Vector2.new(offset.X, offset.Z).Magnitude > MerchantData.TRADE_REACH + REACH_TOLERANCE then
		return false, "Stand next to the merchant"
	end

	local item = ItemsList.GetItemByItemType(offer.ItemType)
	local backpack = InventoryController.GetBackpack(data)
	if not item or not backpack then
		return false, "Can't buy that right now"
	end

	-- Prices are empty for now (free while testing); charge them once they're set
	for itemType, amount in offer.Price do
		local id = ItemsList.GetItemId(itemType)
		if not id or Bag.CountItem(backpack, id) < amount then
			return false, `You need {MerchantData.DescribePrice(offer)}`
		end
	end

	local quantity = offer.Quantity or 1
	local name = ItemsList.GetDisplayName(item.UniqueID) or offer.ItemType
	-- "a Work Scroll" / "8 Wheat Seeds"
	local bought = if quantity > 1 then `{quantity} {name}` else `a {name}`
	-- A full backpack doesn't stop the sale: what doesn't fit goes to the Town Hall mailbox
	local left = Bag.AddItem(backpack, item.UniqueID, quantity)
	local mailed = left > 0
	for itemType, amount in offer.Price do
		local id = ItemsList.GetItemId(itemType)
		if id then
			Bag.RemoveItem(backpack, id, amount)
		end
	end

	ColonyLog.Add(data, `Bought {bought} from the travelling merchant`)
	if mailed then
		MailboxController.Send(player, {
			From = MerchantData.NAME,
			Title = "Backpack full - sent to your mailbox",
			Body = `Your {name} didn't fit in your backpack, so I left it here.`,
			Items = { { UniqueID = item.UniqueID, Quantity = left } },
		})
		return true, "Backpack full - sent to your mailbox"
	end
	ColonyController.Sync(player)
	return true, `Bought {bought}`
end

-- Testing: makes the merchant arrive now (call from an injected server Script:
-- require(game.ServerScriptService.Server.Systems.Merchant.MerchantController).ForceArrive(player))
function MerchantController.ForceArrive(player: Player): boolean
	local data = ColonyController.GetData(player)
	if not data or not isTownHallPlaced(data) then
		return false
	end
	local now = workspace:GetServerTimeNow()
	local visit = getVisit(data)
	visit.LeavesAt = 0
	visit.NextArrival = now
	update(player, data, now)
	return true
end

-- Testing: sends the merchant away now (the next visit stays scheduled)
function MerchantController.ForceLeave(player: Player): boolean
	local data = ColonyController.GetData(player)
	if not data then
		return false
	end
	local now = workspace:GetServerTimeNow()
	local visit = getVisit(data)
	if visit.LeavesAt <= 0 then
		return false
	end
	visit.LeavesAt = now
	update(player, data, now)
	return true
end

-- True while the merchant is at the player's colony
function MerchantController.IsPresent(player: Player): boolean
	local data = ColonyController.GetData(player)
	return data ~= nil and getVisit(data).LeavesAt > workspace:GetServerTimeNow()
end

function MerchantController.Start()
	if started then
		return
	end
	started = true

	Net:Handle("BuyFromMerchant", onBuy)

	-- Testing hook: setting the player attribute "DebugMerchant" to "Arrive"/"Leave" on the server
	-- (e.g. from the Studio command bar) forces a visit
	local function watchDebug(player: Player)
		player:GetAttributeChangedSignal("DebugMerchant"):Connect(function()
			local command = player:GetAttribute("DebugMerchant")
			if command == nil then
				return
			end
			player:SetAttribute("DebugMerchant", nil)
			if command == "Arrive" then
				MerchantController.ForceArrive(player)
			elseif command == "Leave" then
				MerchantController.ForceLeave(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(watchDebug)
	for _, player in Players:GetPlayers() do
		watchDebug(player)
	end

	task.spawn(function()
		while true do
			task.wait(TICK)
			tick()
		end
	end)
end

return MerchantController
