--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared

const BehaviorTree = require(script.Parent.BehaviorTree5)
const ColonistTypes = require(Shared.Colonist.ColonistTypes)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const Agent = require(script.Parent.Agent)
const Navigation = require(script.Parent.Parent.Components.Navigation)

type Action = ColonistTypes.Action
type Agent = Agent.Agent

-- Leaf task factories shared by the colonist brain and every job. Each returns a BTrees V5 node.
const Tasks = {}

Tasks.SUCCESS = 1
Tasks.FAIL = 2
Tasks.RUNNING = 3

const SUCCESS, FAIL, RUNNING = 1, 2, 3

type Status = string | (agent: Agent) -> string
type Target = (agent: Agent, now: number) -> (Vector3?, Vector3?)

local function resolve(status: Status, agent: Agent): string
	return if type(status) == "function" then status(agent) else status
end

function Tasks.GetBuilding(agent: Agent, id: string?): ColonyTypes.SavedBuilding?
	if not id then
		return nil
	end
	for _, saved in agent.Context.Data.Buildings do
		if saved.Id == id and saved.Placement then
			return saved
		end
	end
	return nil
end

-- Door spot of a placed building, facing it
function Tasks.DoorOf(agent: Agent, id: string?): (Vector3?, Vector3?)
	local saved = Tasks.GetBuilding(agent, id)
	if not saved then
		return nil, nil
	end
	return Navigation.GetDoor(saved), Navigation.GetCentre(saved)
end

-- A condition leaf: Blackboard Query on the agent's own board
function Tasks.Is(key: string, value: string)
	return BehaviorTree["Blackboard Query"]({ board = "Entity", key = key, value = value })
end

-- Walks to the point `getTarget` returns; fails when there is none
function Tasks.MoveTo(getTarget: Target, status: Status)
	return BehaviorTree.Task({
		start = function(agent: Agent, now: number)
			local target, lookAt = getTarget(agent, now)
			agent.Blackboard.MoveOk = target ~= nil
			if target then
				agent.Status = resolve(status, agent)
				Agent.WalkTo(agent, target, "Idle", lookAt, now)
			end
		end,
		run = function(agent: Agent, now: number)
			if not agent.Blackboard.MoveOk then
				return FAIL
			end
			return if Agent.HasArrived(agent, now) then SUCCESS else RUNNING
		end,
	})
end

-- Plays `action` for a random time between min and max seconds, then succeeds
function Tasks.Wait(minTime: number, maxTime: number, action: Action, status: Status)
	return BehaviorTree.Task({
		start = function(agent: Agent, now: number)
			agent.Blackboard.WaitUntil = now + agent.Context.Random:NextNumber(minTime, maxTime)
			agent.Status = resolve(status, agent)
			Agent.SetAction(agent, action, agent.Motion.LookAt, now)
		end,
		run = function(agent: Agent, now: number)
			return if now >= agent.Blackboard.WaitUntil then SUCCESS else RUNNING
		end,
	})
end

-- Plays `action` until the brain switches mode (sleeping, mourning)
function Tasks.Hold(action: Action, status: Status)
	return BehaviorTree.Task({
		start = function(agent: Agent, now: number)
			agent.Status = resolve(status, agent)
			Agent.SetAction(agent, action, agent.Motion.LookAt, now)
		end,
		run = function()
			return RUNNING
		end,
	})
end

-- Runs `callback` once; it returns whether the step worked
function Tasks.Do(callback: (agent: Agent, now: number) -> boolean)
	return BehaviorTree.Task({
		run = function(agent: Agent, now: number)
			return if callback(agent, now) then SUCCESS else FAIL
		end,
	})
end

return Tasks
