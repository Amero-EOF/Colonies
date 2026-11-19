--!strict

const BehaviorTree = require(script.Parent.BehaviorTree5)
const Agent = require(script.Parent.Agent)
const Tasks = require(script.Parent.Tasks)
const Builder = require(script.Builder)
const Farmer = require(script.Farmer)
const Gatherer = require(script.Gatherer)
const Guard = require(script.Guard)

type Agent = Agent.Agent

-- Behavior per job name (BuildingData Workplace.Jobs). Add a module with Node() and list it here;
-- jobs without one just go to their workplace and work there.
const JOB_NODES: { [string]: () -> any } = {
	Builder = Builder.Node,
	Farmer = Farmer.Node,
	-- Patrols by day; during a raid the brain's "Defend" mode takes over (Guard.DefendNode)
	Guard = Guard.Node,
	-- Workers of a resource yard (YardData): one behavior, set up per yard kind
	Forester = Gatherer.NodeFor("Trees"),
	Miner = Gatherer.NodeFor("Rocks"),
}

const WORK_TIME_MIN = 8
const WORK_TIME_MAX = 15

local function workplaceDoor(agent: Agent): (Vector3?, Vector3?)
	return Tasks.WorkSpot(agent)
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
