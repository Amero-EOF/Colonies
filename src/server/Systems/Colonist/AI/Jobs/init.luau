--!strict

const BehaviorTree = require(script.Parent.BehaviorTree5)
const Agent = require(script.Parent.Agent)
const Tasks = require(script.Parent.Tasks)
const Builder = require(script.Builder)
const Farmer = require(script.Farmer)

type Agent = Agent.Agent

-- Behavior per job name (BuildingData Workplace.Jobs). Add a module with Node() and list it here;
-- jobs without one just go to their workplace and work there.
const JOB_NODES: { [string]: () -> any } = {
	Builder = Builder.Node,
	Farmer = Farmer.Node,
}

const WORK_TIME_MIN = 8
const WORK_TIME_MAX = 15

local function workplaceDoor(agent: Agent): (Vector3?, Vector3?)
	return Tasks.DoorOf(agent, agent.Colonist.Workplace)
end

local function genericJob()
	return BehaviorTree.Sequence({
		nodes = {
			Tasks.MoveTo(workplaceDoor, "Going to work"),
			Tasks.Wait(WORK_TIME_MIN, WORK_TIME_MAX, "Work", function(agent: Agent)
				return `Working as {agent.Colonist.Job or "a worker"}`
			end),
		},
	})
end

const Jobs = {}

-- One branch per job, picked by the agent's Blackboard.Job
function Jobs.Node()
	local branches = {}
	for job, node in JOB_NODES do
		table.insert(
			branches,
			BehaviorTree.Sequence({
				nodes = { Tasks.Is("Job", job), node() },
			})
		)
	end
	table.insert(branches, genericJob())
	return BehaviorTree.Selector({ nodes = branches })
end

return Jobs
