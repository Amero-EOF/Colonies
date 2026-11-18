--!strict

const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared
const Packages = ReplicatedStorage.Packages
const Systems = script.Parent.Parent

const Net = require(Packages.Net)
const ColonistData = require(Shared.Colonist.ColonistData)
const ColonistTypes = require(Shared.Colonist.ColonistTypes)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const Conversation = require(Shared.Colonist.Conversation)
const DayCycle = require(Shared.Time.DayCycle)
const ItemsList = require(Shared.Inventory.ItemsList)
const ColonyController = require(Systems.Colony.ColonyController)
const ColonyLog = require(Systems.Colony.Components.ColonyLog)
const Mailbox = require(Systems.Colony.Components.Mailbox)
const Notifications = require(Systems.Colony.Components.Notifications)
const Bag = require(Systems.Inventory.Components.Bag)
const InventoryController = require(Systems.Inventory.InventoryController)
const ColonistController = require(script.Parent.ColonistController)
const Population = require(script.Parent.Components.Population)

type Colonist = ColonistTypes.Colonist
type ColonyData = ColonyTypes.ColonyData
type Dialogue = ColonistTypes.Dialogue

-- Talking to colonists (one conversation each per day), their quests, and moving their home
const ConversationController = {}

const random = Random.new()
-- Replies offered in each player's open conversations, by colonist id
const offered: { [Player]: { [number]: { Conversation.Reply } } } = {}
-- Day each colonist last rolled for a quest, so reopening the chat can't reroll it
const questRolls: { [Player]: { [number]: number } } = {}
local started = false

local function getColonist(player: Player, id: unknown): (ColonyData?, Colonist?)
	local data = ColonyController.GetData(player)
	if not data or typeof(id) ~= "number" then
		return nil, nil
	end
	return data, Population.Get(data, id)
end

local function getDay(): number
	return DayCycle.GetDay(workspace:GetServerTimeNow())
end

local function questDialogue(colonist: Colonist, canTalk: boolean): Dialogue
	local quest = colonist.Quest :: ColonistTypes.Quest
	return {
		Kind = "Quest",
		Line = Conversation.GetQuestPrompt(quest),
		Replies = {},
		Quest = quest,
		CanTalk = canTalk,
	}
end

-- Opens a conversation. A colonist with a quest brings it up first (or asks for a new one) unless
-- `chat` is set; otherwise it's the day's chat, or a "come back tomorrow" line.
local function onTalk(player: Player, id: unknown, chat: unknown): (Dialogue?, string)
	local data, colonist = getColonist(player, id)
	if not data or not colonist then
		return nil, "Colonist not found"
	end
	local ok, err = ColonistController.StartTalk(player, colonist.Id)
	if not ok then
		return nil, err
	end
	local day = getDay()
	local canTalk = Conversation.CanTalk(colonist, day)

	if chat ~= true then
		if colonist.Quest then
			return questDialogue(colonist, canTalk), ""
		end
		local rolls = questRolls[player] or {}
		questRolls[player] = rolls
		if canTalk and rolls[colonist.Id] ~= day then
			rolls[colonist.Id] = day
			if Conversation.RollQuest(data.Colonists, colonist, random) then
				ColonistController.SyncColonists(player)
				return questDialogue(colonist, canTalk), ""
			end
		end
	end

	if not canTalk then
		return {
			Kind = "Talk",
			Line = Conversation.GetBusyLine(random),
			Replies = {},
			CanTalk = false,
		},
			""
	end
	local replies = Conversation.RollReplies(colonist, random)
	offered[player] = offered[player] or {}
	offered[player][colonist.Id] = replies
	local texts = {}
	for _, reply in replies do
		table.insert(texts, reply.Text)
	end
	return {
		Kind = "Talk",
		Line = Conversation.GetGreeting(colonist, random),
		Replies = texts,
		CanTalk = true,
	},
		""
end

-- Picks a reply: uses up today's conversation and moves the relationship bar
local function onReply(player: Player, id: unknown, index: unknown): (string?, string)
	local data, colonist = getColonist(player, id)
	if not data or not colonist then
		return nil, "Colonist not found"
	end
	if not ColonistController.IsTalking(player, colonist.Id) then
		return nil, `{colonist.Name} isn't talking with you`
	end
	local replies = offered[player] and offered[player][colonist.Id]
	local reply = if replies and typeof(index) == "number" then replies[index] else nil
	if not replies or not reply then
		return nil, "Talk to them first"
	end
	offered[player][colonist.Id] = nil
	local day = getDay()
	if not Conversation.CanTalk(colonist, day) then
		return nil, `You've already spoken with {colonist.Name} today`
	end
	local reaction = Conversation.ApplyReply(colonist, reply, day, random)
	ColonistController.SyncColonists(player)
	return reaction, ""
end

-- Gives an item to the player's backpack; whatever doesn't fit is mailed
local function giveItem(
	player: Player,
	data: ColonyData,
	backpack: any,
	itemId: number,
	quantity: number
)
	local left = Bag.AddItem(backpack, itemId, quantity)
	if left > 0 then
		Mailbox.Notify(
			player,
			Mailbox.Send(data, {
				From = "Lost & Found",
				Title = "Backpack full - sent to your mailbox",
				Items = { { UniqueID = itemId, Quantity = left } },
			})
		)
	end
end

-- Accept / Decline (or abandon) / Complete a quest. Returns the colonist's reply line.
-- Completing raises the relationship by QUEST_COMPLETE_DELTA; declining or abandoning lowers it.
local function onQuest(player: Player, id: unknown, action: unknown): (string?, string)
	local data, colonist = getColonist(player, id)
	if not data or not colonist then
		return nil, "Colonist not found"
	end
	if not ColonistController.IsTalking(player, colonist.Id) then
		return nil, `{colonist.Name} isn't talking with you`
	end
	local quest = colonist.Quest
	if not quest then
		return nil, `{colonist.Name} has no quest`
	end
	local pending = quest.State == "Pending"

	if action == "Accept" and pending then
		quest.State = "Accepted"
		Notifications.Send(player, "Job", `Quest accepted: {quest.Title}`)
		ColonistController.SyncColonists(player)
		return Conversation.GetQuestLine("Accept", random), ""
	elseif action == "Decline" then
		colonist.Quest = nil
		Conversation.AddRelationship(colonist, ColonistData.QUEST_DECLINE_DELTA)
		ColonistController.SyncColonists(player)
		return Conversation.GetQuestLine("Decline", random), ""
	elseif action == "Complete" and not pending then
		local backpack = InventoryController.GetBackpack(data)
		local wantId = ItemsList.GetItemId(quest.Wants.ItemType)
		local rewardId = ItemsList.GetItemId(quest.Reward.ItemType)
		if not backpack or not wantId or not rewardId then
			return nil, "Quest items missing"
		end
		local have = Bag.CountItem(backpack, wantId)
		if have < quest.Wants.Quantity then
			return nil,
				`Bring {quest.Wants.Quantity} {quest.Wants.ItemType} in your backpack ({have}/{quest.Wants.Quantity})`
		end
		Bag.RemoveItem(backpack, wantId, quest.Wants.Quantity)
		giveItem(player, data, backpack, rewardId, quest.Reward.Quantity)
		colonist.Quest = nil
		Conversation.AddRelationship(colonist, ColonistData.QUEST_COMPLETE_DELTA)
		ColonyLog.Add(data, `{colonist.Name}'s quest "{quest.Title}" is complete`)
		Notifications.Send(
			player,
			"Job",
			`Quest complete! You received {quest.Reward.Quantity} {quest.Reward.ItemType}`
		)
		ColonyController.Sync(player)
		ColonistController.SyncColonists(player)
		return Conversation.GetQuestLine("Complete", random), ""
	end
	return nil, "You can't do that right now"
end

-- "Move to" in the colonist's menu: e.g. Residence -> Town Hall
local function onMoveHome(player: Player, id: unknown, buildingId: unknown): (boolean, string)
	local data, colonist = getColonist(player, id)
	if not data or not colonist then
		return false, "Colonist not found"
	end
	local ok, message = Population.MoveHome(data, colonist, buildingId)
	if ok then
		ColonyLog.Add(data, message)
		ColonyController.Sync(player)
		ColonistController.SyncColonists(player)
	end
	return ok, message
end

function ConversationController.Start()
	if started then
		return
	end
	started = true

	Net:Handle("TalkColonist", onTalk)
	Net:Handle("ReplyColonist", onReply)
	Net:Handle("ColonistQuest", onQuest)
	Net:Handle("MoveColonistHome", onMoveHome)
	Net:Connect("EndTalkColonist", function(player: Player, id: unknown)
		ColonistController.EndTalk(player, id)
		if offered[player] and typeof(id) == "number" then
			offered[player][id] = nil
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		offered[player] = nil
		questRolls[player] = nil
	end)
end

return ConversationController
