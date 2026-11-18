--!strict

const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared
const Packages = ReplicatedStorage.Packages
const Systems = script.Parent.Parent

const Net = require(Packages.Net)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const MailboxData = require(Shared.Colony.MailboxData)
const InventoryController = require(Systems.Inventory.InventoryController)
const ColonyController = require(script.Parent.ColonyController)
const Mailbox = require(script.Parent.Components.Mailbox)

type ColonyData = ColonyTypes.ColonyData
type Letter = Mailbox.Letter

const DEVELOPER = "The Developer"

-- Town Hall mailbox remotes, developer gifts/messages and overflow delivery for online players.
-- Data lives in ColonyData.Mail (see Components/Mailbox).
const MailboxController = {}

local started = false

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- True when the player stands by their Town Hall's mailbox
local function isNear(player: Player, data: ColonyData): boolean
	local mailbox = MailboxData.Find(data.Buildings)
	local root = getRoot(player)
	if not mailbox or not root then
		return false
	end
	local offset = mailbox.Position - root.Position
	return Vector2.new(offset.X, offset.Z).Magnitude
		<= MailboxData.REACH + MailboxData.REACH_TOLERANCE
end

-- Puts a letter in an online player's mailbox, shows a toast and re-sends the colony.
-- Returns the letter, or nil when their colony isn't loaded.
function MailboxController.Send(player: Player, letter: Letter): ColonyTypes.Mail?
	local data = ColonyController.GetData(player)
	if not data then
		return nil
	end
	local mail = Mailbox.Send(data, letter)
	Mailbox.Notify(player, mail)
	ColonyController.Sync(player)
	return mail
end

-- Developer gift/message to a Player or user id, online or offline (yields when offline).
-- Run from an injected server Script or the command bar, e.g.
-- require(game.ServerScriptService.Server.Systems.Colony.MailboxController)
-- 	.Gift(game.Players.Name, { Wood = 20 }, "Thanks for playing!", "Here's some wood.")
function MailboxController.Gift(
	target: Player | number,
	items: { [string]: number }?,
	title: string?,
	body: string?,
	from: string?
): boolean
	local letter: Letter = {
		From = from or DEVELOPER,
		Title = title,
		Body = body,
		Items = Mailbox.ItemsFromTypes(items or {}),
	}
	local userId = if typeof(target) == "number" then target else target.UserId
	-- Loaded in this server: deliver right away
	local player = Players:GetPlayerByUserId(userId)
	if player and MailboxController.Send(player, letter) then
		return true
	end
	-- Offline or in another server: a ProfileStore message, delivered when the profile is active
	return ColonyController.SendMessage(userId, { Kind = "Mail", Letter = letter })
end

-- "Wood:5" or "Wood:5,Stone:3" -> { Wood = 5, Stone = 3 }
local function parseItems(text: string): { [string]: number }
	local amounts: { [string]: number } = {}
	for itemType, amount in string.gmatch(text, "([%w_]+)%s*:%s*(%d+)") do
		amounts[itemType] = (amounts[itemType] or 0) + (tonumber(amount) or 0)
	end
	return amounts
end

-- Testing hook: the server-set player attribute "DebugMail" sends a letter.
-- "Wood:5" (or "Wood:5,Stone:3") sends items from The Developer; "msg:Title|Body" a message.
local function runDebug(player: Player, command: string)
	local message = string.match(command, "^msg:(.*)$")
	if message then
		local title, body = string.match(message, "^([^|]*)|(.*)$")
		MailboxController.Send(player, {
			From = DEVELOPER,
			Title = title or message,
			Body = body,
		})
		return
	end

	local items = Mailbox.ItemsFromTypes(parseItems(command))
	if #items == 0 then
		warn(`[Mailbox] DebugMail: nothing to send in "{command}"`)
		return
	end
	MailboxController.Send(player, { From = DEVELOPER, Title = "A gift", Items = items })
end

local function onCollect(player: Player, id: unknown): (boolean, string)
	local data = ColonyController.GetData(player)
	if not data then
		return false, "Colony not loaded"
	end
	if id ~= "All" and typeof(id) ~= "number" then
		return false, "No such letter"
	end
	if not isNear(player, data) then
		return false, "Stand next to your mailbox"
	end
	local backpack = InventoryController.GetBackpack(data)
	if not backpack then
		return false, "No backpack"
	end

	local moved, left = 0, 0
	if id == "All" then
		local letters: { ColonyTypes.Mail } = table.clone(data.Mail)
		for _, mail in letters do
			if #mail.Items > 0 then
				local m, l = Mailbox.Collect(data, backpack, mail.Id)
				moved += m
				left += l
			end
		end
	else
		if not Mailbox.Get(data, id :: number) then
			return false, "No such letter"
		end
		moved, left = Mailbox.Collect(data, backpack, id :: number)
	end
	ColonyController.Sync(player)

	if moved == 0 and left == 0 then
		return false, "Nothing to collect"
	elseif moved == 0 then
		return false, "Backpack full"
	elseif left > 0 then
		return true, `Collected {moved} items - backpack full, {left} left in the mailbox`
	end
	return true, `Collected {moved} items`
end

local function onDelete(player: Player, id: unknown): (boolean, string)
	local data = ColonyController.GetData(player)
	if not data or typeof(id) ~= "number" then
		return false, "No such letter"
	end
	if not isNear(player, data) then
		return false, "Stand next to your mailbox"
	end
	local mail = Mailbox.Get(data, id)
	if not mail then
		return false, "No such letter"
	end
	if not Mailbox.Delete(data, id) then
		return false, "Collect its items first"
	end
	ColonyController.Sync(player)
	return true, "Letter deleted"
end

-- Marks a letter (or "All") read
local function onRead(player: Player, id: unknown)
	local data = ColonyController.GetData(player)
	if not data or (id ~= "All" and typeof(id) ~= "number") then
		return
	end
	if Mailbox.MarkRead(data, if typeof(id) == "number" then id else nil) then
		ColonyController.Sync(player)
	end
end

function MailboxController.Start()
	if started then
		return
	end
	started = true

	Net:Handle("CollectMail", onCollect)
	Net:Handle("DeleteMail", onDelete)
	Net:Connect("ReadMail", onRead)

	-- e.g. from the Studio server command bar:
	-- game.Players.<Name>:SetAttribute("DebugMail", "Wood:5") / ("DebugMail", "msg:Hello|Welcome!")
	local function watchDebug(player: Player)
		player:GetAttributeChangedSignal("DebugMail"):Connect(function()
			local command = player:GetAttribute("DebugMail")
			if command == nil then
				return
			end
			player:SetAttribute("DebugMail", nil)
			if typeof(command) == "string" then
				runDebug(player, command)
			end
		end)
	end
	Players.PlayerAdded:Connect(watchDebug)
	for _, player in Players:GetPlayers() do
		watchDebug(player)
	end
end

return MailboxController
