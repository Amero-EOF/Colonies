--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared
const AI = script.Parent.Parent

const RaidData = require(Shared.Raid.RaidData)
const BehaviorTree = require(AI.BehaviorTree5)
const Agent = require(AI.Agent)
const Tasks = require(AI.Tasks)
const Navigation = require(AI.Parent.Components.Navigation)
const Raiders = require(AI.Parent.Parent.Raid.Components.Raiders)

type Agent = Agent.Agent

const SUCCESS, RUNNING = Tasks.SUCCESS, Tasks.RUNNING

-- The Guard: patrols around his tower by day and sleeps at night like everyone else, but while
-- raiders are on the plot he gets up and fights them (the brain's "Defend" mode).
const Guard = {}

-- His tower (Guard Tower, Barracks Tower or Gatehouse)
local function getTower(agent: Agent)
	return Tasks.GetBuilding(agent, agent.Colonist.Workplace)
end

local function towerDoor(agent: Agent): (Vector3?, Vector3?)
	return Tasks.WorkSpot(agent)
end

local function patrolSpot(agent: Agent): (Vector3?, Vector3?)
	local tower = getTower(agent)
	local centre = tower and Navigation.GetCentre(tower)
	if not centre then
		return nil, nil
	end
	return Navigation.GetRandomPoint(
		agent.Context.Grid,
		centre,
		RaidData.PATROL_RADIUS,
		agent.Context.Random
	),
		nil
end

-- Damage of one of his swings (tower level and his primary trait)
function Guard.GetDamage(agent: Agent): number
	local tower = getTower(agent)
	return RaidData.GetGuardDamage(agent.Colonist.Skills, if tower then tower.Level else 1)
end

-- True while this colonist should be fighting a raid (checked by the brain every step)
function Guard.IsDefending(agent: Agent): boolean
	local colonist = agent.Colonist
	return agent.Context.Raid ~= nil
		and colonist.Job == RaidData.GUARD_JOB
		and colonist.Age == "Adult"
		and colonist.Debuff ~= "Fight"
		and not colonist.Sick
end

-- The raider he's after: the one he was already fighting, else the closest
local function pickRaider(
	agent: Agent,
	raid: Raiders.Raid,
	position: Vector3,
	now: number
): (Raiders.Raider?, number)
	local board = agent.Blackboard
	local current = if board.RaiderId then raid.Raiders[board.RaiderId] else nil
	if current and Raiders.IsActive(current) then
		local offset = Raiders.GetPosition(current, now) - position
		return current, Vector2.new(offset.X, offset.Z).Magnitude
	end
	local nearest, distance = Raiders.GetNearest(raid, position, now)
	board.RaiderId = if nearest then nearest.Id else nil
	return nearest, distance
end

-- Runs at the nearest raider and fights it until the raid is over. Never finishes on its own:
-- the brain leaves "Defend" when the raid ends.
local function defendTask()
	return BehaviorTree.Task({
		start = function(agent: Agent)
			local board = agent.Blackboard
			board.RaiderId = nil
			board.GuardState = nil
			board.ChaseTo = nil
			board.NextChase = 0
			board.NextSwing = 0
		end,
		run = function(agent: Agent, now: number)
			local raid = agent.Context.Raid
			if not raid then
				return SUCCESS
			end
			local board = agent.Blackboard
			local colonist = agent.Colonist
			local position = Agent.GetPosition(agent, now)

			-- Too hurt to go on: back to the tower, and the raiders fighting him let him go
			if colonist.Health <= RaidData.GUARD_RETREAT_HEALTH then
				if board.GuardState ~= "Retreat" then
					board.GuardState = "Retreat"
					Raiders.Release(raid, colonist.Id)
					agent.Status = "Wounded, falling back"
					local door, centre = towerDoor(agent)
					Agent.RunTo(
						agent,
						door or position,
						RaidData.GUARD_RUN_SPEED,
						"Idle",
						centre,
						now
					)
				end
				return RUNNING
			end

			local raider, distance = pickRaider(agent, raid, position, now)
			if not raider then
				if board.GuardState ~= "Hold" then
					board.GuardState = "Hold"
					agent.Status = "On guard"
					Agent.SetAction(agent, "Idle", nil, now)
				end
				return RUNNING
			end

			local target = Raiders.GetPosition(raider, now)
			if distance <= RaidData.GUARD_REACH then
				board.GuardState = "Fight"
				board.ChaseTo = nil
				agent.Status = "Fighting raiders"
				Agent.SetAction(agent, "Attack", target, now)
				if now >= board.NextSwing then
					board.NextSwing = now + RaidData.GUARD_ATTACK_INTERVAL
					Raiders.Engage(raider, colonist.Id)
					if Raiders.Damage(raid, raider, Guard.GetDamage(agent)) then
						board.RaiderId = nil
						agent.Context.Log(`{colonist.Name} struck down a raider`)
					end
				end
				return RUNNING
			end

			-- Chase: re-path when the raider has moved on, or he got there and it's gone
			local chaseTo: Vector3? = board.ChaseTo
			local stale = not chaseTo
				or Agent.HasArrived(agent, now)
				or (chaseTo - target).Magnitude > RaidData.REPATH_DISTANCE
			if board.GuardState ~= "Chase" or (stale and now >= board.NextChase) then
				board.GuardState = "Chase"
				board.ChaseTo = target
				board.NextChase = now + RaidData.REPATH_INTERVAL
				agent.Status = "Charging at raiders"
				Agent.RunTo(agent, target, RaidData.GUARD_RUN_SPEED, "Idle", target, now)
			end
			return RUNNING
		end,
	})
end

-- The brain's "Defend" branch
function Guard.DefendNode()
	return defendTask()
end

-- The day job: walk a round near the tower, keep watch a moment, repeat
function Guard.Node()
	return BehaviorTree.Sequence({
		nodes = {
			Tasks.MoveTo(patrolSpot, "Patrolling"),
			Tasks.Wait(RaidData.PATROL_WAIT_MIN, RaidData.PATROL_WAIT_MAX, "Idle", "Keeping watch"),
		},
	})
end

return Guard
