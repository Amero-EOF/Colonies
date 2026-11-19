--!strict

const Shared = script.Parent.Parent

const ColonistData = require(Shared.Colonist.ColonistData)
const JobData = require(Shared.Colonist.JobData)
const DayCycle = require(Shared.Time.DayCycle)

-- Tuning for raids and Guards. Anything tied to the day is in in-game days/hours, so it scales
-- with DayCycle.DAY_LENGTH; only short actions (a swing, rummaging the storage) are real seconds.
const RaidData = {}

-- Player attribute the server sets while a raid is on (true/false)
RaidData.ATTRIBUTE = "RaidActive"

-------- Schedule --------

-- Raids only come once the Town Hall is placed and the colony has this many colonists
RaidData.MIN_COLONISTS = 3
-- In-game days from becoming raidable to the first raid night
RaidData.FIRST_RAID_DAYS = 5
-- In-game days between raid nights (picked at random in this range)
RaidData.MIN_DAYS_BETWEEN = 3
RaidData.MAX_DAYS_BETWEEN = 5
-- Clock hour of the warning on the day of a raid (raiders come at nightfall)
RaidData.WARN_HOUR = 17
-- Seconds of night that must be left for a raid to start (else they come the next night)
RaidData.MIN_NIGHT_LEFT = DayCycle.NightHours(4)
-- Seconds after dawn the retreating raiders get to leave the plot before the raid is called off
RaidData.RETREAT_TIME = DayCycle.DaytimeHours(4)
-- Seconds a raid forced in the daytime (testing) lasts before the raiders retreat
RaidData.FORCED_RAID_TIME = DayCycle.DaytimeHours(10)

-------- Raid size --------

RaidData.BASE_RAIDERS = 2
RaidData.RAIDERS_PER_TOWN_HALL_LEVEL = 1
-- One more raider for every this many colonists
RaidData.COLONISTS_PER_RAIDER = 4
RaidData.MAX_RAIDERS = 12
-- Studs between raiders where they appear at the plot's edge
RaidData.SPAWN_SPACING = 5

-------- Raiders --------

RaidData.RAIDER_HEALTH = 16
RaidData.RAIDER_HEALTH_PER_LEVEL = 4
RaidData.RAIDER_DAMAGE = 3
RaidData.RAIDER_DAMAGE_PER_LEVEL = 0.5
-- Seconds between a raider's swings
RaidData.RAIDER_ATTACK_INTERVAL = 1.5
-- Studs a raider's swing reaches
RaidData.RAIDER_REACH = 5
-- Studs/second, sped up with DayCycle.TIME_SCALE like colonists
RaidData.RAIDER_SPEED = DayCycle.Speed(11)
RaidData.FLEE_SPEED = DayCycle.Speed(13)
-- Studs past which a raider stops chasing a Guard that engaged it
RaidData.LEASH = 30
-- Seconds a raider stands still for a swing at a colonist it passes
RaidData.SWING_PAUSE = 0.6
-- A chaser (raider or Guard) re-paths once its target moved this many studs, at most this often
RaidData.REPATH_DISTANCE = 4
RaidData.REPATH_INTERVAL = 0.4
-- Seconds a raider rummages through the Town Hall storage
RaidData.STEAL_TIME = 3
-- Stacks one raider carries off
RaidData.STACKS_PER_RAIDER = 2
-- A raider that finds the storage empty goes after colonists instead, for this long (it lets
-- go of whoever it is chasing when the time is up)
RaidData.HUNT_TIME = DayCycle.NightHours(2)
-- Studs around a raider it looks for colonists to hunt
RaidData.HUNT_RADIUS = 60

-------- Guards --------

RaidData.GUARD_JOB = "Guard"
RaidData.GUARD_BASE_DAMAGE = 3
-- Extra damage per level of the Guard's tower
RaidData.GUARD_DAMAGE_PER_LEVEL = 1
-- Extra damage at the highest primary trait (JobData: Adaptability)
RaidData.GUARD_SKILL_DAMAGE = 3
-- Share of a raider's damage a Guard shrugs off at the highest secondary trait (JobData: Stamina)
RaidData.GUARD_MAX_BLOCK = 0.4
-- Seconds between a Guard's swings
RaidData.GUARD_ATTACK_INTERVAL = 1.2
RaidData.GUARD_REACH = 5
-- At or below this health a Guard breaks off and falls back to his tower
RaidData.GUARD_RETREAT_HEALTH = 4
-- Guards run during a raid (colonists walk at ColonistData.WALK_SPEED)
RaidData.GUARD_RUN_SPEED = DayCycle.Speed(14)
-- Studs around his tower a Guard patrols by day, and seconds he keeps watch at each stop
RaidData.PATROL_RADIUS = 30
RaidData.PATROL_WAIT_MIN = 4
RaidData.PATROL_WAIT_MAX = 9

-------- The player --------

-- Studs from a raider the player's character can hit it
RaidData.PLAYER_REACH = 10
-- Extra studs the server allows past that (lag)
RaidData.REACH_TOLERANCE = 6
-- Seconds between the player's swings
RaidData.PLAYER_ATTACK_COOLDOWN = 0.5
RaidData.BARE_HANDS_DAMAGE = 2
-- Damage of the gathering tools when held, by ResourceData tool type; held items use their
-- ItemsList Metadata.Damage instead
RaidData.TOOL_DAMAGE = table.freeze({
	Axe = 4,
	Pickaxe = 3,
}) :: { [string]: number }

-- Raiders in a raid on a colony with this Town Hall level and population
function RaidData.GetRaidSize(townHallLevel: number, colonists: number): number
	local size = RaidData.BASE_RAIDERS
		+ math.max(townHallLevel, 0) * RaidData.RAIDERS_PER_TOWN_HALL_LEVEL
		+ math.floor(colonists / RaidData.COLONISTS_PER_RAIDER)
	return math.clamp(size, 1, RaidData.MAX_RAIDERS)
end

function RaidData.GetRaiderHealth(townHallLevel: number): number
	return RaidData.RAIDER_HEALTH + math.max(townHallLevel, 0) * RaidData.RAIDER_HEALTH_PER_LEVEL
end

function RaidData.GetRaiderDamage(townHallLevel: number): number
	return RaidData.RAIDER_DAMAGE + math.max(townHallLevel, 0) * RaidData.RAIDER_DAMAGE_PER_LEVEL
end

-- 0-1 of how good a trait is
local function getSkillShare(skills: { [string]: number }, skill: string?): number
	if not skill then
		return 0
	end
	return math.clamp((skills[skill] or 0) / ColonistData.SKILL_MAX, 0, 1)
end

-- Damage of one Guard swing: grows with his tower's level and his primary trait
function RaidData.GetGuardDamage(skills: { [string]: number }, towerLevel: number): number
	local info = JobData.Get(RaidData.GUARD_JOB)
	return RaidData.GUARD_BASE_DAMAGE
		+ math.max(towerLevel, 1) * RaidData.GUARD_DAMAGE_PER_LEVEL
		+ getSkillShare(skills, info and info.Primary) * RaidData.GUARD_SKILL_DAMAGE
end

-- Share (0-GUARD_MAX_BLOCK) of a raider's damage a Guard shrugs off, from his secondary trait
function RaidData.GetGuardBlock(skills: { [string]: number }): number
	local info = JobData.Get(RaidData.GUARD_JOB)
	return getSkillShare(skills, info and info.Secondary) * RaidData.GUARD_MAX_BLOCK
end

return RaidData
