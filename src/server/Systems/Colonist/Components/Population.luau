--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared
const Systems = script.Parent.Parent.Parent

const BuildingData = require(Shared.Buildings.BuildingData)
const BuildingUnlocks = require(Shared.Buildings.BuildingUnlocks)
const BuildingTypes = require(Shared.Buildings.BuildingTypes)
const ColonistData = require(Shared.Colonist.ColonistData)
const ColonistTypes = require(Shared.Colonist.ColonistTypes)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const ItemsList = require(Shared.Inventory.ItemsList)
const JobData = require(Shared.Colonist.JobData)
const Bag = require(Systems.Inventory.Components.Bag)
const Mailbox = require(Systems.Colony.Components.Mailbox)

type BuildingId = BuildingTypes.BuildingId
type Colonist = ColonistTypes.Colonist
type ColonyData = ColonyTypes.ColonyData
type Gender = ColonistTypes.Gender

const packItem = ItemsList.GetItemByItemType("ColonistPack")
assert(packItem, "ColonistPack item missing")

-- Who lives where, who works where, and families. Plain functions over ColonyData.
const Population = {}

-- Colonies start with this many colonists, and may always grow to it even without beds
Population.STARTING_COLONISTS = 4

local function pick<T>(list: { T }, random: Random): T
	return list[random:NextInteger(1, #list)]
end

function Population.Get(data: ColonyData, id: number?): Colonist?
	if not id then
		return nil
	end
	for _, colonist in data.Colonists do
		if colonist.Id == id then
			return colonist
		end
	end
	return nil
end

local function getSurname(data: ColonyData, colonist: Colonist?): string?
	if not colonist then
		return nil
	end
	return string.match(colonist.Name, "%s(%S+)$")
end

local function rollSkills(random: Random, parents: { Colonist }): { [string]: number }
	local skills = {}
	for _, skill in ColonistData.SKILLS do
		if #parents > 0 then
			local total = 0
			for _, parent in parents do
				total += parent.Skills[skill] or ColonistData.SKILL_MIN
			end
			local spread = ColonistData.CHILD_SKILL_SPREAD
			skills[skill] = math.clamp(
				math.round(total / #parents) + random:NextInteger(-spread, spread),
				ColonistData.SKILL_MIN,
				ColonistData.SKILL_MAX
			)
		else
			skills[skill] = random:NextInteger(ColonistData.SKILL_MIN, ColonistData.SKILL_MAX)
		end
	end
	return skills
end

-- Adds a new colonist: an adult arrival, or a child when parents are given
function Population.Create(
	data: ColonyData,
	day: number,
	random: Random,
	parents: { Colonist }?
): Colonist
	local parentList: { Colonist } = parents or {}
	local gender: Gender = if random:NextNumber() < 0.5 then "Male" else "Female"
	local first = pick(
		if gender == "Male" then ColonistData.MALE_NAMES else ColonistData.FEMALE_NAMES,
		random
	)
	local father = nil
	for _, parent in parentList do
		if parent.Gender == "Male" then
			father = parent
		end
	end
	local surname = getSurname(data, father or parentList[1]) or pick(ColonistData.SURNAMES, random)

	local colonist: Colonist = {
		Id = data.NextColonistId,
		Name = `{first} {surname}`,
		Gender = gender,
		Age = if #parentList > 0 then "Child" else "Adult",
		BornDay = day,
		Health = ColonistData.MAX_HEALTH,
		Saturation = ColonistData.MAX_SATURATION,
		Happiness = ColonistData.BASE_HAPPINESS,
		Skills = rollSkills(random, parentList),
		Family = { Parents = {}, Children = {} },
		Modifiers = {},
		Carried = Bag.new(packItem :: any),
		Relationship = ColonistData.DEFAULT_RELATIONSHIP,
	}
	data.NextColonistId += 1

	for _, parent in parentList do
		table.insert(colonist.Family.Parents, parent.Id)
		table.insert(parent.Family.Children, colonist.Id)
		colonist.Home = parent.Home
	end

	table.insert(data.Colonists, colonist)
	return colonist
end

-- Fills in fields older saves are missing
function Population.Migrate(data: ColonyData)
	for _, colonist in data.Colonists do
		colonist.Modifiers = colonist.Modifiers or {}
		colonist.Family = colonist.Family or { Parents = {}, Children = {} }
		colonist.Carried = colonist.Carried or Bag.new(packItem :: any)
		colonist.Relationship = colonist.Relationship or ColonistData.DEFAULT_RELATIONSHIP
		-- Quests from before the Wants/Reward format
		if colonist.Quest and not colonist.Quest.Wants then
			colonist.Quest = nil
		end
	end
end

-- Spouse, children, parents and siblings still in the colony
function Population.GetImmediateFamily(data: ColonyData, colonist: Colonist): { Colonist }
	local ids: { [number]: boolean } = {}
	local family = colonist.Family
	if family.Spouse then
		ids[family.Spouse] = true
	end
	for _, id in family.Children do
		ids[id] = true
	end
	for _, id in family.Parents do
		ids[id] = true
		local parent = Population.Get(data, id)
		if parent then
			for _, siblingId in parent.Family.Children do
				ids[siblingId] = true
			end
		end
	end
	ids[colonist.Id] = nil

	local members = {}
	for _, other in data.Colonists do
		if ids[other.Id] then
			table.insert(members, other)
		end
	end
	return members
end

local function isRelated(data: ColonyData, a: Colonist, b: Colonist): boolean
	for _, member in Population.GetImmediateFamily(data, a) do
		if member.Id == b.Id then
			return true
		end
	end
	return false
end

-- Moves a colonist into the departed list (kept for family trees). Whatever they carried goes
-- to the Town Hall mailbox; returns that letter, if any.
function Population.Remove(
	data: ColonyData,
	colonist: Colonist,
	fate: ColonistTypes.Fate
): ColonyTypes.Mail?
	for i, other in data.Colonists do
		if other.Id == colonist.Id then
			table.remove(data.Colonists, i)
			break
		end
	end

	table.insert(data.Departed, {
		Id = colonist.Id,
		Name = colonist.Name,
		Gender = colonist.Gender,
		Fate = fate,
		Family = colonist.Family,
	})
	while #data.Departed > ColonistData.MAX_DEPARTED do
		table.remove(data.Departed, 1)
	end

	-- Unassign from any work order it was building
	for _, order in data.WorkOrders do
		if order.BuilderId == colonist.Id then
			order.BuilderId = nil
		end
	end

	local items = if colonist.Carried then Mailbox.EmptyBag(colonist.Carried) else {}
	if #items == 0 then
		return nil
	end
	local reason = if fate == "Died" then "passed away" else "left the colony"
	return Mailbox.Send(data, {
		From = `{colonist.Name}'s belongings`,
		Title = if fate == "Died" then `In memory of {colonist.Name}` else "Left behind",
		Body = `{colonist.Name} {reason}. What they carried was sent to your mailbox.`,
		Items = items,
	})
end

-------- Housing --------

local function getSaved(data: ColonyData, id: BuildingId?): ColonyTypes.SavedBuilding?
	if not id then
		return nil
	end
	for _, saved in data.Buildings do
		if saved.Id == id then
			return saved
		end
	end
	return nil
end

-- Beds a built building offers
function Population.GetBeds(saved: ColonyTypes.SavedBuilding): number
	if not saved.Placement then
		return 0
	end
	return BuildingUnlocks.GetBeds(saved.Id, saved.Level)
end

function Population.GetTotalBeds(data: ColonyData): number
	local beds = 0
	for _, saved in data.Buildings do
		beds += Population.GetBeds(saved)
	end
	return beds
end

-- Most colonists the colony can hold right now
function Population.GetCapacity(data: ColonyData): number
	return math.max(Population.STARTING_COLONISTS, Population.GetTotalBeds(data))
end

-- Beds in a building not taken by a resident
function Population.GetFreeBeds(data: ColonyData, saved: ColonyTypes.SavedBuilding): number
	local residents = 0
	for _, colonist in data.Colonists do
		if colonist.Home == saved.Id then
			residents += 1
		end
	end
	return Population.GetBeds(saved) - residents
end

-- Moves a colonist into another built home with a free bed (e.g. Residence -> Town Hall)
function Population.MoveHome(data: ColonyData, colonist: Colonist, id: unknown): (boolean, string)
	local saved = if typeof(id) == "string" then getSaved(data, id :: any) else nil
	if not saved or Population.GetBeds(saved) == 0 then
		return false, "That building has no beds"
	end
	local name = BuildingData[saved.Id].Name
	if colonist.Home == saved.Id then
		return false, `{colonist.Name} already lives in the {name}`
	elseif colonist.Leaving then
		return false, `{colonist.Name} is leaving the colony`
	elseif Population.GetFreeBeds(data, saved) <= 0 then
		return false, `The {name} has no free beds`
	end
	colonist.Home = saved.Id
	return true, `{colonist.Name} moved into the {name}`
end

-- Keeps homes valid and moves homeless colonists into free beds; spouses share a home when they can
function Population.AssignHomes(data: ColonyData)
	local used: { [string]: number } = {}

	for _, colonist in data.Colonists do
		local home = getSaved(data, colonist.Home)
		local beds = if home then Population.GetBeds(home) else 0
		local id = colonist.Home
		if id and (used[id] or 0) < beds then
			used[id] = (used[id] or 0) + 1
		else
			colonist.Home = nil
		end
	end

	local function freeBeds(saved: ColonyTypes.SavedBuilding): number
		return Population.GetBeds(saved) - (used[saved.Id] or 0)
	end

	local function moveIn(colonist: Colonist, saved: ColonyTypes.SavedBuilding)
		colonist.Home = saved.Id
		used[saved.Id] = (used[saved.Id] or 0) + 1
	end

	for _, colonist in data.Colonists do
		if colonist.Home or colonist.Leaving then
			continue
		end

		-- Join the spouse or a parent first
		local spouse = Population.Get(data, colonist.Family.Spouse)
		local joined = false
		for _, relative in { spouse, Population.Get(data, colonist.Family.Parents[1]) } do
			local home = relative and getSaved(data, relative.Home)
			if home and freeBeds(home) > 0 then
				moveIn(colonist, home)
				joined = true
				break
			end
		end
		if joined then
			continue
		end

		-- Couples move together into a home with two free beds when possible
		local best: ColonyTypes.SavedBuilding? = nil
		for _, saved in data.Buildings do
			local free = freeBeds(saved)
			if free > 0 and (not best or free > freeBeds(best)) then
				best = saved
			end
		end
		if best then
			moveIn(colonist, best)
			if spouse and not spouse.Home and freeBeds(best) > 0 then
				moveIn(spouse, best)
			end
		end
	end
end

-------- Jobs --------

-- Jobs whose worker is hired as soon as the workplace is placed, because they build it themselves
const SELF_BUILT_JOBS: { [string]: boolean } = {
	Builder = true,
}

local function canStaff(saved: ColonyTypes.SavedBuilding): boolean
	local workplace = BuildingData[saved.Id].Components.Workplace
	if not workplace or not saved.Placement then
		return false
	end
	return BuildingUnlocks.IsBuilt(saved.Id, saved.Level)
		or SELF_BUILT_JOBS[workplace.Jobs[1]] == true
end

-- Built workplaces each get one worker: the unemployed adult best suited to the job.
-- Returns the colonists hired this call.
function Population.AssignJobs(data: ColonyData): { Colonist }
	local filled: { [string]: boolean } = {}
	local hired: { Colonist } = {}

	for _, colonist in data.Colonists do
		local workplace = getSaved(data, colonist.Workplace)
		local valid = workplace ~= nil
			and canStaff(workplace)
			and colonist.Age == "Adult"
			and not colonist.Leaving
			and not filled[workplace.Id]
		if valid and workplace then
			filled[workplace.Id] = true
		else
			colonist.Workplace = nil
			colonist.Job = nil
		end
	end

	for _, saved in data.Buildings do
		local workplace = BuildingData[saved.Id].Components.Workplace
		if not workplace or filled[saved.Id] or not canStaff(saved) then
			continue
		end
		local job = workplace.Jobs[1]

		local best: Colonist? = nil
		local bestScore = -1
		for _, colonist in data.Colonists do
			if colonist.Job or colonist.Age ~= "Adult" or colonist.Leaving or colonist.Debuff then
				continue
			end
			local score = JobData.Score(job, colonist.Skills)
			if score > bestScore then
				best, bestScore = colonist, score
			end
		end

		if best then
			best.Job = job
			best.Workplace = saved.Id
			filled[saved.Id] = true
			table.insert(hired, best)
		end
	end
	return hired
end

-------- Families --------

-- One random pair of single, unrelated adults of opposite gender gets married
function Population.TryMarry(data: ColonyData, random: Random): (Colonist?, Colonist?)
	local men, women = {}, {}
	for _, colonist in data.Colonists do
		local single = not Population.Get(data, colonist.Family.Spouse)
		if single and colonist.Age == "Adult" and not colonist.Leaving then
			table.insert(if colonist.Gender == "Male" then men else women, colonist)
		end
	end
	if #men == 0 or #women == 0 then
		return nil, nil
	end

	local man = pick(men, random)
	for _ = 1, #women do
		local woman = pick(women, random)
		if not isRelated(data, man, woman) then
			man.Family.Spouse = woman.Id
			woman.Family.Spouse = man.Id
			-- Move in together next time homes are assigned
			woman.Home = nil
			return man, woman
		end
	end
	return nil, nil
end

-- Married couples sharing a home with a free bed may have a child
function Population.TryBirths(data: ColonyData, day: number, random: Random): { Colonist }
	local born = {}
	local used: { [string]: number } = {}
	for _, colonist in data.Colonists do
		if colonist.Home then
			used[colonist.Home] = (used[colonist.Home] or 0) + 1
		end
	end

	for _, mother in table.clone(data.Colonists) do
		local father = Population.Get(data, mother.Family.Spouse)
		local home = getSaved(data, mother.Home)
		if
			mother.Gender ~= "Female"
			or not father
			or not home
			or father.Home ~= mother.Home
			or mother.Leaving
			or Population.GetBeds(home) - (used[home.Id] or 0) <= 0
			or random:NextNumber() >= ColonistData.BIRTH_CHANCE
		then
			continue
		end
		local child = Population.Create(data, day, random, { father, mother })
		used[home.Id] = (used[home.Id] or 0) + 1
		table.insert(born, child)
	end
	return born
end

-- Children become adults after a few days
function Population.GrowUp(data: ColonyData, day: number): { Colonist }
	local grown = {}
	for _, colonist in data.Colonists do
		if colonist.Age == "Child" and day - colonist.BornDay >= ColonistData.CHILD_GROWUP_DAYS then
			colonist.Age = "Adult"
			table.insert(grown, colonist)
		end
	end
	return grown
end

return Population
