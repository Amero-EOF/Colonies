--!strict

const Shared = script.Parent.Parent

const BuildingModels = require(Shared.Buildings.BuildingModels)
const BuildingPlacement = require(Shared.Buildings.BuildingPlacement)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const ItemsList = require(Shared.Inventory.ItemsList)

type SavedBuilding = ColonyTypes.SavedBuilding
type MailItem = ColonyTypes.MailItem

-- Studs between the Town Hall's front edge and the mailbox
const FRONT_GAP = 4
-- Studs the mailbox sits right of the entrance (the front's centre line)
const SIDE_OFFSET = 8

-- Where the Town Hall mailbox stands. The Town Hall has no entrance yet, so its front is the
-- pivot's LookVector (note: colonists' door, Navigation.GetDoor, uses the +Z side) and the
-- mailbox stands just in front of it, shifted along the RightVector. The client puts a
-- "MailboxAttachment" there; a real model can replace the placeholder by moving that spot.
const MailboxData = {}

-- Ground the mailbox takes up (X/Z), kept clear of the merchant
MailboxData.SIZE = Vector2.new(4, 4)
-- Studs from the mailbox its prompt reaches; the server allows some lag on top
MailboxData.REACH = 10
MailboxData.REACH_TOLERANCE = 6
-- Longest text a letter keeps
MailboxData.MAX_FROM = 60
MailboxData.MAX_TITLE = 100
MailboxData.MAX_BODY = 2000

-- World CFrame of the mailbox's base, facing out of the Town Hall's front (LookVector)
function MailboxData.GetCFrame(townHallPivot: CFrame, footprint: Vector2): CFrame
	local front = footprint.Y / 2 + FRONT_GAP + MailboxData.SIZE.Y / 2
	local side = math.min(SIDE_OFFSET, footprint.X / 2)
	-- -Z is the LookVector, +X the RightVector
	return townHallPivot * CFrame.new(side, 0, -front)
end

-- The placed Town Hall's mailbox, or nil until the Town Hall is placed
function MailboxData.Find(buildings: { SavedBuilding }): CFrame?
	for _, saved in buildings do
		local placement = saved.Placement
		if saved.Id == "TownHall" and placement then
			return MailboxData.GetCFrame(
				BuildingPlacement.ToCFrame(placement),
				BuildingModels.GetFootprint(saved.Id, saved.Level)
			)
		end
	end
	return nil
end

-- True when a square area of `size` at a world CFrame overlaps the mailbox
function MailboxData.Overlaps(buildings: { SavedBuilding }, cframe: CFrame, size: Vector2): boolean
	local mailbox = MailboxData.Find(buildings)
	if not mailbox then
		return false
	end
	return BuildingPlacement.Overlaps(
		BuildingPlacement.FromCFrame(cframe),
		size,
		BuildingPlacement.FromCFrame(mailbox),
		MailboxData.SIZE
	)
end

-- "5 Wood, 1 Work Scroll"
function MailboxData.DescribeItems(items: { MailItem }): string
	local parts = {}
	for _, item in items do
		local name = ItemsList.GetDisplayName(item.UniqueID) or `Item {item.UniqueID}`
		table.insert(parts, `{item.Quantity} {name}`)
	end
	return table.concat(parts, ", ")
end

function MailboxData.CountItems(items: { MailItem }): number
	local count = 0
	for _, item in items do
		count += item.Quantity
	end
	return count
end

return MailboxData
