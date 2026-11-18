--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared

const ColonistData = require(Shared.Colonist.ColonistData)
const ColonistTypes = require(Shared.Colonist.ColonistTypes)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const DayCycle = require(Shared.Time.DayCycle)

type Colonist = ColonistTypes.Colonist
type ColonyData = ColonyTypes.ColonyData

-- Hunger, health and happiness. Plain functions over saved colonist data.
const Needs = {}

-- Food use doubles from the night a colonist was woken until the following night
function Needs.IsFoodDoubled(colonist: Colonist, now: number): boolean
	local woken = colonist.WokenDay
	if not woken then
		return false
	end
	local day = DayCycle.GetDay(now)
	return day == woken or (day == woken + 1 and not DayCycle.IsNight(now))
end

function Needs.AddModifier(
	colonist: Colonist,
	id: string,
	amount: number,
	duration: number,
	now: number
)
	for i = #colonist.Modifiers, 1, -1 do
		if colonist.Modifiers[i].Id == id then
			table.remove(colonist.Modifiers, i)
		end
	end
	table.insert(colonist.Modifiers, { Id = id, Amount = amount, Until = now + duration })
end

local function getHomeLevel(data: ColonyData, colonist: Colonist): number?
	if not colonist.Home then
		return nil
	end
	for _, saved in data.Buildings do
		if saved.Id == colonist.Home then
			return saved.Level
		end
	end
	return nil
end

-- Base happiness plus housing, job, food, sickness and timed modifiers, clamped to 0-MAX
function Needs.GetHappiness(data: ColonyData, colonist: Colonist, now: number): number
	local happiness = ColonistData.BASE_HAPPINESS

	local homeLevel = getHomeLevel(data, colonist)
	if not homeLevel then
		happiness += ColonistData.HOMELESS_HAPPINESS
	elseif homeLevel >= ColonistData.GOOD_HOME_LEVEL then
		happiness += ColonistData.GOOD_HOME_HAPPINESS
	end

	if colonist.Age == "Adult" and not colonist.Job then
		happiness += ColonistData.UNEMPLOYED_HAPPINESS
	end

	local fed = colonist.Saturation / ColonistData.MAX_SATURATION
	happiness += (fed * 2 - 1) * ColonistData.SATURATION_HAPPINESS

	if colonist.Sick then
		happiness -= 1
	end

	for _, modifier in colonist.Modifiers do
		if modifier.Until > now then
			happiness += modifier.Amount
		end
	end

	return math.clamp(happiness, 0, ColonistData.MAX_HAPPINESS)
end

-- Advances hunger and health by `deltaTime` seconds. Returns true when the colonist died.
function Needs.Update(data: ColonyData, colonist: Colonist, deltaTime: number, now: number): boolean
	for i = #colonist.Modifiers, 1, -1 do
		if colonist.Modifiers[i].Until <= now then
			table.remove(colonist.Modifiers, i)
		end
	end

	local drainPerSecond = ColonistData.SATURATION_PER_DAY / DayCycle.DAY_LENGTH
	if Needs.IsFoodDoubled(colonist, now) then
		drainPerSecond *= 2
	end
	colonist.Saturation = math.max(colonist.Saturation - drainPerSecond * deltaTime, 0)

	local hours = deltaTime / DayCycle.HOUR_LENGTH
	if colonist.Saturation <= 0 then
		-- Starving
		colonist.Health -= ColonistData.HEAL_PER_HOUR * hours
	elseif
		colonist.Saturation >= ColonistData.MAX_SATURATION / 2
		and not colonist.Sick
		and colonist.Debuff ~= "Fight"
	then
		colonist.Health =
			math.min(colonist.Health + ColonistData.HEAL_PER_HOUR * hours, ColonistData.MAX_HEALTH)
	end

	if colonist.Sick then
		colonist.Health -= ColonistData.HEAL_PER_HOUR * hours
	end
	if colonist.Debuff == "Fight" then
		colonist.Health -= ColonistData.FIGHT_DAMAGE_PER_HOUR * hours
		data.Disease = math.min(data.Disease + ColonistData.FIGHT_DISEASE_PER_HOUR * hours, 100)
	end

	colonist.Happiness = Needs.GetHappiness(data, colonist, now)
	return colonist.Health <= 0
end

-- Morning roll for unhappy colonists: DEBUFF_CHANCE of Fight or Flight (50/50)
function Needs.RollDebuff(colonist: Colonist, random: Random): ColonistTypes.Debuff?
	if colonist.Debuff or colonist.Leaving or colonist.Age ~= "Adult" then
		return nil
	end
	if colonist.Happiness >= ColonistData.LOW_HAPPINESS then
		return nil
	end
	if random:NextNumber() >= ColonistData.DEBUFF_CHANCE then
		return nil
	end
	return if random:NextNumber() < 0.5 then "Fight" else "Flight"
end

return Needs
