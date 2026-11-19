--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared

const BehaviorTree = require(script.Parent.BehaviorTree5)
const BuildingUnlocks = require(Shared.Buildings.BuildingUnlocks)
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

-- This colonist's place (1-based, by Id) among the colonists whose `field` is `id`, so each
-- gets its own bed / work spot
local function getShareIndex(agent: Agent, field: "Home" | "Workplace", id: string): number
	local index = 1
	for _, other in agent.Context.Data.Colonists do
		if other[field] == id and other.Id < agent.Colonist.Id then
			index += 1
		end
	end
	return index
end

-- An authored spot of a placed building (BuildingSpots: "Bed", "Work", "StorageStand"), facing
-- its attachment's LookVector (or the building's centre); its door when the model has none.
-- `share` picks this colonist's own spot of a numbered set among the building's residents/workers.
function Tasks.SpotOf(
	agent: Agent,
	id: string?,
	spot: string,
	share: ("Home" | "Workplace")?
): (Vector3?, Vector3?)
	local saved = Tasks.GetBuilding(agent, id)
	if not saved or not id then
		return nil, nil
	end
	local index = if share then getShareIndex(agent, share, id) else 1
	local position, lookAt = Navigation.GetSpot(saved, spot, index)
	if position then
		return position, lookAt or Navigation.GetCentre(saved)
	end
	return Navigation.GetDoor(saved), Navigation.GetCentre(saved)
end

-- Where a worker stands while working at its workplace
function Tasks.WorkSpot(agent: Agent): (Vector3?, Vector3?)
	return Tasks.SpotOf(agent, agent.Colonist.Workplace, "Work", "Workplace")
end

-- Where a worker stands to use its workplace's storage
function Tasks.StorageSpot(agent: Agent): (Vector3?, Vector3?)
	return Tasks.SpotOf(agent, agent.Colonist.Workplace, "StorageStand")
end

-- Where colony life gathers (BuildingUnlocks.GetHubId): the built Town Hall's door, or before
-- it's built this colonist's own spot on a ring around the Spire, facing it
function Tasks.HubSpot(agent: Agent): (Vector3?, Vector3?)
	local data = agent.Context.Data
	local hubId = BuildingUnlocks.GetHubId(data.Buildings)
	if hubId == "TownHall" then
		return Tasks.DoorOf(agent, hubId)
	end
	local spire = Tasks.GetBuilding(agent, hubId)
	if not spire then
		return nil, nil
	end
	local spot = Navigation.GetRingSpot(
		agent.Context.Grid,
		spire,
		agent.Colonist.Id,
		math.max(#data.Colonists, 1)
	)
	return spot, Navigation.GetCentre(spire)
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
