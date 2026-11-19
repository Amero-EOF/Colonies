--!strict

const Shared = script.Parent.Parent

const BuildingModels = require(Shared.Buildings.BuildingModels)
const BuildingPlacement = require(Shared.Buildings.BuildingPlacement)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const MailboxData = require(Shared.Colony.MailboxData)
const PlotData = require(Shared.Plot.PlotData)
const DayCycle = require(Shared.Time.DayCycle)

type SavedBuilding = ColonyTypes.SavedBuilding

-- Something the travelling merchant sells
export type Offer = {
	Id: string,
	-- ItemsList item the player receives
	ItemType: string,
	-- How many one purchase gives (1 when nil)
	Quantity: number?,
	Description: string,
	-- Items taken from the backpack, by ItemType; empty is free (testing)
	Price: { [string]: number },
}

-- In-game days between arrivals, and how long each visit lasts
const VISIT_EVERY_DAYS = 3
const STAY_DAYS = 1

-- Studs between the Town Hall's side and the merchant
const SPOT_GAP = 10
-- Ground the merchant and his cart take up (X/Z around where he stands), kept off buildings
const SPOT_SIZE = Vector2.new(10, 16)

const OFFERS: { Offer } = {
	{
		Id = "LandscapingShovel",
		ItemType = "LandscapingShovel",
		Description = "Reshapes the land around your colony. (Coming soon)",
		Price = {},
	},
	{
		Id = "WorkScroll",
		ItemType = "WorkScroll",
		Description = "Hold it to see what your Builder's work order still needs and what you carry.",
		Price = {},
	},
	{
		Id = "Sword",
		ItemType = "Sword",
		Description = "Hold it and click raiders to strike them down. Hits harder than your tools.",
		Price = {},
	},
	{
		Id = "WheatSeeds",
		ItemType = "WheatSeeds",
		Quantity = 8,
		Description = "Give them to your Farmer to plant Wheat. Once planted it regrows forever.",
		Price = {},
	},
	{
		Id = "CarrotSeeds",
		ItemType = "CarrotSeeds",
		Quantity = 8,
		Description = "Give them to your Farmer to plant Carrots. Once planted they regrow forever.",
		Price = {},
	},
	{
		Id = "PotatoSeeds",
		ItemType = "PotatoSeeds",
		Quantity = 8,
		Description = "Give them to your Farmer to plant Potatoes. Once planted they regrow forever.",
		Price = {},
	},
}

const MerchantData = {}

MerchantData.OFFERS = OFFERS
MerchantData.VISIT_EVERY_DAYS = VISIT_EVERY_DAYS
MerchantData.STAY_DAYS = STAY_DAYS
-- Seconds between arrivals and per visit (scale with DayCycle.DAY_LENGTH)
MerchantData.VISIT_INTERVAL = DayCycle.Hours(24 * VISIT_EVERY_DAYS)
MerchantData.STAY_TIME = DayCycle.Hours(24 * STAY_DAYS)
-- Studs from the merchant his Trade prompt (and the server's buy check) reaches
MerchantData.TRADE_REACH = 12
-- Player attribute holding the server time the current visit ends (nil while away)
MerchantData.ATTRIBUTE = "MerchantUntil"
MerchantData.NAME = "Travelling Merchant"

function MerchantData.GetOffer(id: string): Offer?
	for _, offer in OFFERS do
		if offer.Id == id then
			return offer
		end
	end
	return nil
end

-- "Free (test)" while there's no price, else e.g. "12 Stone, 20 Wood"
function MerchantData.DescribePrice(offer: Offer): string
	local parts = {}
	for itemType, amount in offer.Price do
		table.insert(parts, `{amount} {itemType}`)
	end
	if #parts == 0 then
		return "Free (test)"
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

-- First visit after the Town Hall is placed: the next morning
function MerchantData.GetFirstArrival(now: number): number
	return DayCycle.GetNextMorning(now)
end

-- The latest scheduled arrival at or before `now`, following `scheduled` every VISIT_INTERVAL
function MerchantData.GetLatestArrival(scheduled: number, now: number): number
	local missed = math.max(math.floor((now - scheduled) / MerchantData.VISIT_INTERVAL), 0)
	return scheduled + missed * MerchantData.VISIT_INTERVAL
end

-- World CFrame where the merchant stands (facing out of the Town Hall's front), beside
-- the Town Hall on the first side clear of other buildings. nil until the Town Hall is built.
-- Shared so the client draws him where the server checks the player's reach.
function MerchantData.GetSpot(buildings: { SavedBuilding }): CFrame?
	local townHall: SavedBuilding? = nil
	for _, saved in buildings do
		if saved.Id == "TownHall" and saved.Level >= 1 then
			townHall = saved
		end
	end
	local placement = townHall and townHall.Placement
	if not townHall or not placement then
		return nil
	end

	local base = BuildingPlacement.ToCFrame(placement)
	local footprint = BuildingModels.GetFootprint(townHall.Id, townHall.Level)
	local side = footprint.X / 2 + SPOT_GAP
	local front = footprint.Y / 2 + SPOT_GAP
	-- Right side, left side, front corners, back; he faces the Town Hall's front (+Z)
	local facing = CFrame.Angles(0, math.pi, 0)
	local candidates = {
		CFrame.new(side, 0, footprint.Y / 4),
		CFrame.new(-side, 0, footprint.Y / 4),
		CFrame.new(side, 0, front),
		CFrame.new(-side, 0, front),
		CFrame.new(0, 0, -front),
	}

	for _, offset in candidates do
		local spot = base * offset * facing
		if not PlotData.IsInside(spot.Position, townHall.Level) then
			continue
		end
		local spotPlacement = BuildingPlacement.FromCFrame(spot)
		-- Never on top of the Town Hall mailbox
		local clear = not MailboxData.Overlaps(buildings, spot, SPOT_SIZE)
		for _, other in buildings do
			if not clear then
				break
			end
			local otherPlacement = other.Placement
			if
				otherPlacement
				and BuildingPlacement.Overlaps(
					spotPlacement,
					SPOT_SIZE,
					otherPlacement,
					BuildingModels.GetFootprint(other.Id, other.Level)
				)
			then
				clear = false
				break
			end
		end
		if clear then
			return spot
		end
	end

	return base * candidates[1] * facing
end

return MerchantData
