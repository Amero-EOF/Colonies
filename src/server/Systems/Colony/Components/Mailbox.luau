--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared
const Systems = script.Parent.Parent.Parent

const ColonyTypes = require(Shared.Colony.ColonyTypes)
const InventoryTypes = require(Shared.Inventory.InventoryTypes)
const ItemsList = require(Shared.Inventory.ItemsList)
const MailboxData = require(Shared.Colony.MailboxData)
const Bag = require(Systems.Inventory.Components.Bag)
const Notifications = require(script.Parent.Notifications)

type ColonyData = ColonyTypes.ColonyData
type Mail = ColonyTypes.Mail
type MailItem = ColonyTypes.MailItem
type BagData = InventoryTypes.Bag

-- What Send takes: who it's from, optional text and items
export type Letter = {
	From: string,
	Title: string?,
	Body: string?,
	Items: { MailItem }?,
}

-- The Town Hall mailbox: plain functions over ColonyData.Mail.
-- Anything with nowhere else to go (full backpack, a departed colonist's belongings,
-- glitched stacks) and developer gifts/messages end up here.
const Mailbox = {}

local function clip(text: string?, limit: number): string?
	if not text or text == "" then
		return nil
	end
	local length = utf8.len(text)
	if not length then
		-- Not valid UTF-8; cut by bytes
		return string.sub(text, 1, limit)
	end
	if length <= limit then
		return text
	end
	local cut = utf8.offset(text, limit + 1)
	return if cut then string.sub(text, 1, cut - 1) else text
end

-- Known items only, whole positive quantities, one entry per item
local function cleanItems(items: { MailItem }?): { MailItem }
	local merged: { MailItem } = {}
	local byId: { [number]: MailItem } = {}
	local list: { MailItem } = items or {}
	for _, item in list do
		local quantity = math.floor(item.Quantity)
		if not ItemsList.GetItemName(item.UniqueID) or quantity <= 0 then
			continue
		end
		local existing = byId[item.UniqueID]
		if existing then
			existing.Quantity += quantity
		else
			local entry = { UniqueID = item.UniqueID, Quantity = quantity }
			byId[item.UniqueID] = entry
			table.insert(merged, entry)
		end
	end
	return merged
end

-- Older saves get an empty mailbox
function Mailbox.Migrate(data: ColonyData)
	local old = data :: any
	if typeof(old.Mail) ~= "table" then
		old.Mail = {}
	end
	local nextId = if typeof(old.NextMailId) == "number" then old.NextMailId else 1
	for _, mail in data.Mail do
		nextId = math.max(nextId, mail.Id + 1)
	end
	data.NextMailId = nextId
end

-- Puts a letter in the mailbox and returns it (text-only letters are fine)
function Mailbox.Send(data: ColonyData, letter: Letter): Mail
	local mail: Mail = {
		Id = data.NextMailId,
		Time = workspace:GetServerTimeNow(),
		From = clip(letter.From, MailboxData.MAX_FROM) or "Unknown",
		Title = clip(letter.Title, MailboxData.MAX_TITLE),
		Body = clip(letter.Body, MailboxData.MAX_BODY),
		Items = cleanItems(letter.Items),
		Read = false,
	}
	data.NextMailId += 1
	table.insert(data.Mail, mail)
	return mail
end

-- A Letter from untrusted data (ProfileStore messages), or nil when malformed
function Mailbox.ToLetter(value: unknown): Letter?
	if typeof(value) ~= "table" then
		return nil
	end
	local raw = value :: { [string]: unknown }
	if typeof(raw.From) ~= "string" then
		return nil
	end
	local items: { MailItem } = {}
	if typeof(raw.Items) == "table" then
		for _, item in raw.Items :: { unknown } do
			if typeof(item) ~= "table" then
				continue
			end
			local entry = item :: { [string]: unknown }
			if typeof(entry.UniqueID) == "number" and typeof(entry.Quantity) == "number" then
				table.insert(items, { UniqueID = entry.UniqueID, Quantity = entry.Quantity })
			end
		end
	end
	return {
		From = raw.From,
		Title = if typeof(raw.Title) == "string" then raw.Title else nil,
		Body = if typeof(raw.Body) == "string" then raw.Body else nil,
		Items = items,
	}
end

-- Items from ItemType names ({ Wood = 5 }); unknown names are skipped
function Mailbox.ItemsFromTypes(amounts: { [string]: number }): { MailItem }
	local items: { MailItem } = {}
	for itemType, quantity in amounts do
		local id = ItemsList.GetItemId(itemType)
		if id then
			table.insert(items, { UniqueID = id, Quantity = quantity })
		end
	end
	return items
end

function Mailbox.Get(data: ColonyData, id: number): Mail?
	for _, mail in data.Mail do
		if mail.Id == id then
			return mail
		end
	end
	return nil
end

-- Moves a letter's items into the backpack as far as they fit; the rest stays in the letter.
-- Returns how many items moved and how many are left.
function Mailbox.Collect(data: ColonyData, backpack: BagData, id: number): (number, number)
	local mail = Mailbox.Get(data, id)
	if not mail then
		return 0, 0
	end

	local moved, left = 0, 0
	local remaining: { MailItem } = {}
	for _, item in mail.Items do
		-- Items removed from ItemsList can never be collected; drop them
		if not ItemsList.GetItemName(item.UniqueID) then
			continue
		end
		local leftover = Bag.AddItem(backpack, item.UniqueID, item.Quantity)
		moved += item.Quantity - leftover
		if leftover > 0 then
			left += leftover
			table.insert(remaining, { UniqueID = item.UniqueID, Quantity = leftover })
		end
	end
	mail.Items = remaining
	mail.Read = true
	return moved, left
end

-- Removes a letter once nothing is left to collect
function Mailbox.Delete(data: ColonyData, id: number): boolean
	for i, mail in data.Mail do
		if mail.Id == id then
			if #mail.Items > 0 then
				return false
			end
			table.remove(data.Mail, i)
			return true
		end
	end
	return false
end

-- Marks one letter (or every letter when id is nil) read; true when something changed
function Mailbox.MarkRead(data: ColonyData, id: number?): boolean
	local changed = false
	for _, mail in data.Mail do
		if (id == nil or mail.Id == id) and not mail.Read then
			mail.Read = true
			changed = true
		end
	end
	return changed
end

function Mailbox.CountUnread(data: ColonyData): number
	local count = 0
	for _, mail in data.Mail do
		if not mail.Read then
			count += 1
		end
	end
	return count
end

-- Empties a bag, returning what it held (e.g. a departed colonist's pack)
function Mailbox.EmptyBag(bag: BagData): { MailItem }
	local items: { MailItem } = {}
	for _, stack in bag.Items do
		table.insert(items, { UniqueID = stack.UniqueID, Quantity = stack.Quantity })
	end
	table.clear(bag.Items)
	return cleanItems(items)
end

-- Takes out stacks a bag can't hold: slots outside the bag, two stacks in one slot, more
-- than a full stack. Unknown items are left alone. Returns what was taken.
function Mailbox.TakeGlitched(bag: BagData): { MailItem }
	local slots = Bag.GetSlotsCount(bag)
	if slots <= 0 then
		return {}
	end

	local taken: { MailItem } = {}
	local kept = {}
	local used: { [number]: boolean } = {}
	for _, stack in bag.Items do
		if not ItemsList.GetItemName(stack.UniqueID) then
			table.insert(kept, stack)
			continue
		end
		local quantity = math.floor(stack.Quantity)
		if quantity <= 0 then
			continue
		end
		local slot = stack.Slot
		if slot ~= math.floor(slot) or slot < 1 or slot > slots or used[slot] then
			table.insert(taken, { UniqueID = stack.UniqueID, Quantity = quantity })
			continue
		end
		used[slot] = true
		local maxStack = ItemsList.GetMaxStack(stack.UniqueID)
		if quantity > maxStack then
			table.insert(taken, { UniqueID = stack.UniqueID, Quantity = quantity - maxStack })
			quantity = maxStack
		end
		stack.Quantity = quantity
		table.insert(kept, stack)
	end

	-- Same Items table, so anything holding it stays valid
	table.clear(bag.Items)
	for _, stack in kept do
		table.insert(bag.Items, stack)
	end
	return cleanItems(taken)
end

-- Toast telling the player a letter arrived
function Mailbox.Notify(player: Player, mail: Mail)
	local text = if mail.Title
		then `{mail.From}: {mail.Title}`
		elseif #mail.Items > 0 then `{mail.From} sent {MailboxData.DescribeItems(mail.Items)}`
		else `New mail from {mail.From}`
	Notifications.Send(player, "Mail", text)
end

-- Reminds the player of letters they haven't read (e.g. on joining)
function Mailbox.NotifyUnread(player: Player, data: ColonyData)
	local unread = Mailbox.CountUnread(data)
	if unread > 0 then
		local letters = if unread == 1 then "1 unread letter" else `{unread} unread letters`
		Notifications.Send(player, "Mail", `You have {letters} in the Town Hall mailbox`)
	end
end

return Mailbox
