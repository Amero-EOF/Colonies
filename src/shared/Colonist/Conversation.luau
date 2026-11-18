--!strict

-- Daily conversations and colonist quests: plain data and pure functions; the server owns the state.
-- Lines follow the style of Stronghold's Conscript quotes
-- (@url:`https://stronghold.fandom.com/wiki/Conscript/Quotes`): short, eager, "my lord"/"sire".
-- Replies are vague remarks; how a colonist takes one depends on their traits and occupation.

const ColonistData = require(script.Parent.ColonistData)
const ColonistTypes = require(script.Parent.ColonistTypes)
const JobData = require(script.Parent.JobData)

type Colonist = ColonistTypes.Colonist
type Quest = ColonistTypes.Quest

-- A player reply and how far it moves the relationship
export type Reply = { Text: string, Delta: number }

type QuestTemplate = {
	Id: string,
	Title: string,
	Ask: string,
	Wants: ColonistTypes.QuestItem,
	Reward: ColonistTypes.QuestItem,
}

-- Relationship section names, 0 Angry -> 5 Happy
const MOODS: { [number]: string } = {
	[0] = "Angry",
	[1] = "Grumpy",
	[2] = "Wary",
	[3] = "Content",
	[4] = "Cheerful",
	[5] = "Happy",
}

-- What the colonist opens with, by relationship section
const GREETINGS: { [number]: { string } } = {
	[0] = {
		"What do you want now?",
		"Leave me be, my lord.",
		"Not you again...",
		"I've nothing to say to you.",
	},
	[1] = { "Yes... my lord?", "Must we talk, sire?", "Hmph. My lord.", "Make it quick, my lord." },
	[2] = { "My lord?", "Sire?", "You called, my lord?", "What is it, sire?" },
	[3] = { "Yes, my lord!", "At your service!", "Ready, sire!", "Your orders, my lord?" },
	[4] = {
		"Good day, my lord!",
		"Always a pleasure, sire!",
		"Ready for anything, my lord!",
		"What can I do for you, sire?",
	},
	[5] = {
		"For you, my lord, anything!",
		"Long live my lord!",
		"A fine day to see you, sire!",
		"I'd follow you anywhere, my lord!",
	},
}

-- Vague remarks, each quietly about one trait; colonists strong in it take it well, weak ones badly
const SKILL_REMARKS: { [string]: { string } } = {
	Athletics = { "Fine weather for a run, eh?", "You look like you could outrun a horse." },
	Dexterity = {
		"Nimble fingers make light work.",
		"Steady hands are worth their weight in gold.",
	},
	Strength = { "Plenty of heavy lifting today.", "Those barrels won't carry themselves." },
	Agility = { "Light on your feet, as ever.", "Quick as a hare, some say." },
	Stamina = { "Long day ahead, I'd wager.", "Still going strong at sundown?" },
	Mana = { "Strange lights in the sky last night...", "Do you ever feel the air hum?" },
	Adaptability = { "Things change quickly around here.", "New faces, new walls, new troubles." },
	Focus = { "Mind on your work, I see.", "Not easily distracted, are you?" },
	Creativity = { "Seen anything beautiful lately?", "The colony could use some colour." },
	Knowledge = { "Read any good books?", "There's always more to learn." },
	Intelligence = { "Puzzled out anything new?", "A sharp mind is a rare thing." },
}

-- How the colonist takes the reply
const REACTIONS: { [string]: { string } } = {
	Good = { "Thank you, my lord!", "You honour me, sire!", "Aye! That warms the heart, my lord!" },
	Neutral = { "Aye, my lord.", "As you wish.", "If you say so, sire." },
	Bad = { "As you say... my lord.", "Hmph.", "Is that meant to be funny, sire?" },
}

-- Once today's conversation is used up
const BUSY_LINES = {
	"We've spoken today, my lord. Back to work!",
	"Tomorrow, sire. There's work to be done.",
	"I've chores waiting, my lord. Another day?",
}

const QUEST_LINES: { [string]: { string } } = {
	Accept = {
		"I knew I could count on you, my lord!",
		"Bless you, sire!",
		"Right you are, my lord!",
	},
	Decline = {
		"Hmph. I'll manage alone then.",
		"As you wish... my lord.",
		"I see how it is, sire.",
	},
	Complete = {
		"You're a true lord, my lord!",
		"Bless you, sire! Take this, with my thanks.",
		"For the colony!",
	},
}

const QUESTS: { QuestTemplate } = {
	{
		Id = "Firewood",
		Title = "Firewood",
		Ask = "The nights are cold, my lord. Could you spare some wood?",
		Wants = { ItemType = "Wood", Quantity = 10 },
		Reward = { ItemType = "Food", Quantity = 5 },
	},
	{
		Id = "Rations",
		Title = "Rations",
		Ask = "My belly's empty, sire. A little food?",
		Wants = { ItemType = "Food", Quantity = 5 },
		Reward = { ItemType = "Stone", Quantity = 10 },
	},
	{
		Id = "Masonry",
		Title = "Masonry",
		Ask = "I need stone to mend my wall, my lord.",
		Wants = { ItemType = "Stone", Quantity = 10 },
		Reward = { ItemType = "Wood", Quantity = 12 },
	},
	{
		Id = "Prospecting",
		Title = "Prospecting",
		Ask = "Bring me ore and I'll make it worth your while, sire!",
		Wants = { ItemType = "Ore", Quantity = 5 },
		Reward = { ItemType = "Food", Quantity = 8 },
	},
}

local function pick<T>(list: { T }, random: Random): T
	return list[random:NextInteger(1, #list)]
end

-- 0-1 for how good the colonist is at a trait
local function getSkillScore(colonist: Colonist, skill: string): number
	local value = colonist.Skills[skill] or ColonistData.SKILL_MIN
	return (value - ColonistData.SKILL_MIN) / (ColonistData.SKILL_MAX - ColonistData.SKILL_MIN)
end

-- -TALK_MAX_DELTA (worst) to +TALK_MAX_DELTA (best) from a 0-1 score
local function toDelta(score: number): number
	return ColonistData.TALK_MAX_DELTA * (2 * math.clamp(score, 0, 1) - 1)
end

const Conversation = {}

-- Relationship section (0-5) a value falls in
function Conversation.GetStep(relationship: number): number
	return math.clamp(math.floor(relationship), 0, ColonistData.RELATIONSHIP_MAX)
end

function Conversation.GetMood(relationship: number): string
	return MOODS[Conversation.GetStep(relationship)]
end

function Conversation.AddRelationship(colonist: Colonist, delta: number)
	colonist.Relationship =
		math.clamp(colonist.Relationship + delta, 0, ColonistData.RELATIONSHIP_MAX)
end

-- One conversation per colonist per DayCycle day
function Conversation.CanTalk(colonist: Colonist, day: number): boolean
	return colonist.TalkedDay ~= day
end

function Conversation.GetGreeting(colonist: Colonist, random: Random): string
	return pick(GREETINGS[Conversation.GetStep(colonist.Relationship)], random)
end

function Conversation.GetBusyLine(random: Random): string
	return pick(BUSY_LINES, random)
end

function Conversation.GetQuestLine(kind: "Accept" | "Decline" | "Complete", random: Random): string
	return pick(QUEST_LINES[kind], random)
end

-- What the colonist says about their quest when spoken to
function Conversation.GetQuestPrompt(quest: Quest): string
	return if quest.State == "Pending"
		then quest.Ask
		else `Have you brought the {quest.Wants.ItemType:lower()}, my lord?`
end

-- REPLY_COUNT remarks about different traits; one is about their occupation when they have one
function Conversation.RollReplies(colonist: Colonist, random: Random): { Reply }
	local skills = table.clone(ColonistData.SKILLS)
	local replies: { Reply } = {}
	local job = colonist.Job and JobData.Get(colonist.Job)
	if colonist.Job and job then
		local score = getSkillScore(colonist, job.Primary)
		if job.Secondary then
			score = (score + getSkillScore(colonist, job.Secondary)) / 2
		end
		table.insert(replies, {
			Text = `How's the {colonist.Job:lower()} trade treating you?`,
			Delta = toDelta(score),
		})
	end
	while #replies < ColonistData.REPLY_COUNT and #skills > 0 do
		local skill = table.remove(skills, random:NextInteger(1, #skills)) :: string
		local remarks = SKILL_REMARKS[skill]
		if remarks then
			table.insert(
				replies,
				{ Text = pick(remarks, random), Delta = toDelta(getSkillScore(colonist, skill)) }
			)
		end
	end
	for i = #replies, 2, -1 do
		local j = random:NextInteger(1, i)
		replies[i], replies[j] = replies[j], replies[i]
	end
	return replies
end

-- Uses up today's conversation and moves the relationship bar; returns the colonist's reaction
function Conversation.ApplyReply(
	colonist: Colonist,
	reply: Reply,
	day: number,
	random: Random
): string
	colonist.TalkedDay = day
	Conversation.AddRelationship(colonist, reply.Delta)
	local third = ColonistData.TALK_MAX_DELTA / 3
	local kind = if reply.Delta > third
		then "Good"
		elseif reply.Delta < -third then "Bad"
		else "Neutral"
	return pick(REACTIONS[kind], random)
end

-- Colonists whose quest is still awaiting the player's answer
function Conversation.CountPendingQuests(colonists: { Colonist }): number
	local count = 0
	for _, colonist in colonists do
		if colonist.Quest and colonist.Quest.State == "Pending" then
			count += 1
		end
	end
	return count
end

-- Rolls the chance of the colonist asking for a quest (at most MAX_PENDING_QUESTS awaiting an answer)
function Conversation.RollQuest(colonists: { Colonist }, colonist: Colonist, random: Random): Quest?
	if
		colonist.Quest
		or colonist.Leaving
		or Conversation.CountPendingQuests(colonists) >= ColonistData.MAX_PENDING_QUESTS
		or random:NextNumber() >= ColonistData.QUEST_CHANCE
	then
		return nil
	end
	local template = pick(QUESTS, random)
	local quest: Quest = {
		Id = template.Id,
		Title = template.Title,
		Ask = template.Ask,
		Wants = table.clone(template.Wants),
		Reward = table.clone(template.Reward),
		State = "Pending",
	}
	colonist.Quest = quest
	return quest
end

-- "Bring 10 Wood - reward: 5 Food"
function Conversation.Describe(quest: Quest): string
	return `Bring {quest.Wants.Quantity} {quest.Wants.ItemType} - reward: {quest.Reward.Quantity} {quest.Reward.ItemType}`
end

return Conversation
