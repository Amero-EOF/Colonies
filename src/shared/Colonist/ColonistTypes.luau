--!strict

const BuildingTypes = require(script.Parent.Parent.Buildings.BuildingTypes)
const InventoryTypes = require(script.Parent.Parent.Inventory.InventoryTypes)

type BuildingId = BuildingTypes.BuildingId

export type Gender = "Male" | "Female"
export type AgeGroup = "Child" | "Adult"
export type Debuff = "Fight" | "Flight"
export type Fate = "Died" | "Left"

-- What the colonist does once it reaches the end of its path
export type Action = "Idle" | "Sleep" | "Build" | "Mourn" | "Eat" | "Work"

export type QuestState = "Pending" | "Accepted"

export type QuestItem = { ItemType: string, Quantity: number }

-- A colonist's request: bring Wants, get Reward. Quests never change the relationship.
export type Quest = {
	Id: string,
	Title: string,
	-- What the colonist says when asking
	Ask: string,
	Wants: QuestItem,
	Reward: QuestItem,
	-- Pending: awaiting the player's answer; Accepted: waiting for the items
	State: QuestState,
}

export type QuestAction = "Accept" | "Decline" | "Complete"

-- Returned by the "TalkColonist" remote and shown in the dialogue frame
export type Dialogue = {
	-- "Quest" frames show the quest and its Accept/Decline or Hand in/Abandon buttons
	Kind: "Talk" | "Quest",
	-- What the colonist says
	Line: string,
	-- Player replies; empty once today's conversation is used up
	Replies: { string },
	Quest: Quest?,
	-- Today's conversation is still available
	CanTalk: boolean,
}

-- A relationship step (0 Angry -> 5 Happy)
-- Luau has no number literal types, so this is a plain number kept in 0-5
export type RelationshipStep = number
export type Modifier = {
	Id: string,
	Amount: number,
	-- workspace:GetServerTimeNow() when it wears off
	Until: number,
}

-- Colonist ids; siblings are derived from shared parents
export type Family = {
	Spouse: number?,
	Parents: { number },
	Children: { number },
}

-- Saved per colonist in ColonyData.Colonists
export type Colonist = {
	Id: number,
	Name: string,
	Gender: Gender,
	Age: AgeGroup,
	-- DayCycle day index it was born/arrived on
	BornDay: number,
	Health: number,
	Saturation: number,
	Happiness: number,
	-- Traits from the wiki (Athletics, Dexterity...), SKILL_MIN-SKILL_MAX
	Skills: { [string]: number },
	-- Job name from BuildingData Workplace.Jobs (e.g. "Builder")
	Job: string?,
	Workplace: BuildingId?,
	Home: BuildingId?,
	Family: Family,
	Debuff: Debuff?,
	Modifiers: { Modifier },
	-- 5-slot inventory (ColonistPack)
	Carried: InventoryTypes.Bag,
	-- Day index of the night it was woken on; its food use doubles until the next night
	WokenDay: number?,
	-- Walking out of the colony (Flight debuff, or family of a Flight colonist)
	Leaving: boolean?,
	-- Caught a disease this morning; cured next morning
	Sick: boolean?,
	-- DayCycle day of the last conversation with the player (one per day)
	TalkedDay: number?,
	-- Relationship with the player: 0 Angry -> 5 Happy; fractional, each whole number is one bar section
	Relationship: number,
	-- Quest awaiting an answer or accepted
	Quest: Quest?,
}

-- Kept so family trees can still show colonists who died or left
export type DepartedColonist = {
	Id: number,
	Name: string,
	Gender: Gender,
	Fate: Fate,
	Family: Family,
}

-- Path the client replays: position at time t is Path walked at Speed from StartTime
export type Motion = {
	Id: number,
	Path: { Vector3 },
	Speed: number,
	StartTime: number,
	Action: Action,
	-- Where to face once arrived (optional)
	LookAt: Vector3?,
}

export type Funeral = {
	Name: string,
	Until: number,
	Position: Vector3,
}

-- Sent to the owner with the "ColonistsState" remote
export type ColonistsState = {
	Colonists: { Colonist },
	Departed: { DepartedColonist },
	Funeral: Funeral?,
	Disease: number,
	-- Colonist id (string) -> short status line ("Sleeping", "Building the Town Hall"...)
	Status: { [string]: string },
}

return 0
