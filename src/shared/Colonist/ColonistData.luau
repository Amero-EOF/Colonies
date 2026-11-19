--!strict

const DayCycle = require(script.Parent.Parent.Time.DayCycle)

-- Relationship gained by the best reply in the day's conversation (the worst loses as much)
const TALK_MAX_DELTA = 0.5

-- Tuning for colonists. Anything tied to the day is in in-game hours/days, so it scales with
-- DayCycle.DAY_LENGTH; only short actions (eating, placing a part) are real seconds.
return table.freeze({
	MAX_HEALTH = 20,
	MAX_SATURATION = 20,
	MAX_HAPPINESS = 10,

	-- Traits rolled for a new arrival; children inherit the parents' average +- CHILD_SKILL_SPREAD
	SKILLS = table.freeze({
		"Athletics",
		"Dexterity",
		"Strength",
		"Agility",
		"Stamina",
		"Mana",
		"Adaptability",
		"Focus",
		"Creativity",
		"Knowledge",
		"Intelligence",
	}),
	SKILL_MIN = 1,
	SKILL_MAX = 15,
	CHILD_SKILL_SPREAD = 3,

	-- Studs/second, sped up with DayCycle.TIME_SCALE
	WALK_SPEED = DayCycle.Speed(10),
	CHILD_WALK_SPEED = DayCycle.Speed(8),

	-- Saturation lost per in-game day; doubled for the night a colonist is woken
	SATURATION_PER_DAY = 10,
	-- Below this a colonist goes to the Town Hall to eat Food from colony storage
	HUNGRY_AT = 8,
	FOOD_SATURATION = 5,
	EAT_TIME = 3,
	-- Food a colonist accepts from the player and carries; eaten on the spot when hungry
	FOOD_CARRY = 5,
	-- Health regained per in-game hour while saturation is at least half (also lost per hour starving or sick)
	HEAL_PER_HOUR = 0.5,

	-- Happiness (0-10): base plus factors plus timed modifiers
	BASE_HAPPINESS = 5,
	-- Relationship bar: 0 Angry -> 5 Happy (5 equal sections)
	RELATIONSHIP_MAX = 5,
	DEFAULT_RELATIONSHIP = 3,
	TALK_MAX_DELTA = TALK_MAX_DELTA,
	-- Replies offered in the day's conversation
	REPLY_COUNT = 3,
	-- Completing a quest is worth 1.5x the best reply; declining or abandoning costs 1.5x the worst
	QUEST_COMPLETE_DELTA = TALK_MAX_DELTA * 1.5,
	QUEST_DECLINE_DELTA = -TALK_MAX_DELTA * 1.5,
	-- Random chance (0-1) a colonist offers a quest in the day's conversation
	QUEST_CHANCE = 0.40,
	-- Maximum colonists that can have a pending/awaiting acceptance quest at once
	MAX_PENDING_QUESTS = 2,
	HOMELESS_HAPPINESS = -2,
	GOOD_HOME_LEVEL = 3,
	GOOD_HOME_HAPPINESS = 1,
	UNEMPLOYED_HAPPINESS = -1,
	-- Saturation factor ranges from -SATURATION_HAPPINESS to +SATURATION_HAPPINESS
	SATURATION_HAPPINESS = 2,
	WOKEN_HAPPINESS = -1.5,
	MOURNING_HAPPINESS = -2,
	MOURNING_DAYS = 3,
	SLEPT_HAPPINESS = 0.5,
	-- Seconds a woken colonist stays up before going back to bed
	WOKEN_AWAKE_TIME = DayCycle.Hours(1),

	-- Below 10% happiness, each morning: 50% chance of a debuff, then Fight or Flight 50/50
	LOW_HAPPINESS = 1,
	DEBUFF_CHANCE = 0.5,
	-- Health a Fight colonist loses per in-game hour
	FIGHT_DAMAGE_PER_HOUR = 1,
	-- Colony disease chance (0-100) added per in-game hour for every Fight colonist, and lost per day
	FIGHT_DISEASE_PER_HOUR = 0.25,
	DISEASE_DECAY_PER_DAY = 2,

	-- Seconds everyone spends at a funeral
	FUNERAL_TIME = DayCycle.Hours(6),

	-- Seconds between arrivals while there's a free bed
	ARRIVAL_INTERVAL = DayCycle.Hours(3),
	-- Each morning: chance two single adults sharing a home marry, and a married couple has a child
	MARRIAGE_CHANCE = 0.35,
	BIRTH_CHANCE = 0.25,
	CHILD_GROWUP_DAYS = 3,
	MAX_DEPARTED = 100,

	-- Builder: seconds per part = (BASE + PER_UNIT * materials) / (1 + Adaptability / ADAPTABILITY_SCALE)
	BUILD_PART_TIME = 1,
	BUILD_TIME_PER_UNIT = 0.25,
	ADAPTABILITY_SCALE = 50,

	MALE_NAMES = table.freeze({
		"Aldric",
		"Bram",
		"Cedric",
		"Dorian",
		"Edmund",
		"Finn",
		"Gareth",
		"Hugo",
		"Ivo",
		"Jasper",
		"Kendrick",
		"Leoric",
		"Milo",
		"Niall",
		"Osric",
		"Percival",
		"Roland",
		"Silas",
		"Tobias",
		"Wyatt",
	}),
	FEMALE_NAMES = table.freeze({
		"Ada",
		"Beatrix",
		"Cecily",
		"Daphne",
		"Elena",
		"Freya",
		"Greta",
		"Helena",
		"Isolde",
		"Juliet",
		"Katrin",
		"Lena",
		"Maud",
		"Nora",
		"Odette",
		"Rosalind",
		"Sabine",
		"Tilda",
		"Vera",
		"Wren",
	}),
	SURNAMES = table.freeze({
		"Ashford",
		"Blackwood",
		"Carter",
		"Dunmore",
		"Fletcher",
		"Greenhill",
		"Hartley",
		"Ironside",
		"Mason",
		"Oakley",
		"Thatcher",
		"Wexley",
	}),
})
