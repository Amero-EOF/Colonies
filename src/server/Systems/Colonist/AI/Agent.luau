--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared

const ColonistData = require(Shared.Colonist.ColonistData)
const ColonistMotion = require(Shared.Colonist.ColonistMotion)
const ColonistTypes = require(Shared.Colonist.ColonistTypes)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const Navigation = require(script.Parent.Parent.Components.Navigation)
const Raiders = require(script.Parent.Parent.Parent.Raid.Components.Raiders)

type Action = ColonistTypes.Action
type Colonist = ColonistTypes.Colonist
type Motion = ColonistTypes.Motion

-- Runtime state for one loaded colony, shared by its agents
export type Context = {
	Player: Player,
	Data: ColonyTypes.ColonyData,
	Grid: Navigation.Grid,
	Random: Random,
	Funeral: ColonistTypes.Funeral?,
	-- The raid in progress, set by RaidController while it lasts (Guards fight its raiders)
	Raid: Raiders.Raid?,
	-- Motions changed since the last send, by colonist id
	ChangedMotions: { [number]: Motion },
	-- Hooks into the colony (kept here so AI modules don't require controllers)
	SyncColony: () -> (),
	CompleteWorkOrder: (orderId: number) -> (),
	Log: (text: string) -> (),
}

-- Runtime state for one colonist; the behavior tree's `obj`
export type Agent = {
	Colonist: Colonist,
	Context: Context,
	Motion: Motion,
	-- Short line for the UI ("Sleeping", "Building the Tavern"...)
	Status: string,
	-- Behavior tree board; Mode and Job drive the tree's Blackboard Query branches
	Blackboard: { [string]: any },
	-- Set when woken at night; stays up until then
	AwakeUntil: number,
	-- The player talking with it; it stands still until the conversation ends
	TalkingTo: Player?,
}

const Agent = {}

function Agent.new(colonist: Colonist, context: Context, position: Vector3, now: number): Agent
	return {
		Colonist = colonist,
		Context = context,
		Motion = {
			Id = colonist.Id,
			Path = { position },
			Speed = 0,
			StartTime = now,
			Action = "Idle",
		},
		Status = "Idle",
		Blackboard = {},
		AwakeUntil = 0,
		TalkingTo = nil,
	}
end

function Agent.GetPosition(agent: Agent, now: number): Vector3
	local position = ColonistMotion.Evaluate(agent.Motion, now)
	return position
end

local function setMotion(agent: Agent, motion: Motion)
	agent.Motion = motion
	agent.Context.ChangedMotions[agent.Colonist.Id] = motion
end

local function getSpeed(agent: Agent): number
	return if agent.Colonist.Age == "Child"
		then ColonistData.CHILD_WALK_SPEED
		else ColonistData.WALK_SPEED
end

-- Walks to a plot-local point around buildings; `action` plays once it arrives
function Agent.WalkTo(agent: Agent, target: Vector3, action: Action, lookAt: Vector3?, now: number)
	local from = Agent.GetPosition(agent, now)
	setMotion(agent, {
		Id = agent.Colonist.Id,
		Path = Navigation.FindPath(agent.Context.Grid, from, target),
		Speed = getSpeed(agent),
		StartTime = now,
		Action = action,
		LookAt = lookAt,
	})
end

-- Like WalkTo at a given speed (Guards run at raiders)
function Agent.RunTo(
	agent: Agent,
	target: Vector3,
	speed: number,
	action: Action,
	lookAt: Vector3?,
	now: number
)
	local from = Agent.GetPosition(agent, now)
	setMotion(agent, {
		Id = agent.Colonist.Id,
		Path = Navigation.FindPath(agent.Context.Grid, from, target),
		Speed = speed,
		StartTime = now,
		Action = action,
		LookAt = lookAt,
	})
end

-- Stops where it is and plays `action`
function Agent.SetAction(agent: Agent, action: Action, lookAt: Vector3?, now: number)
	local position = Agent.GetPosition(agent, now)
	local motion = agent.Motion
	if motion.Speed == 0 and motion.Action == action and motion.LookAt == lookAt then
		return
	end
	setMotion(agent, {
		Id = agent.Colonist.Id,
		Path = { position },
		Speed = 0,
		StartTime = now,
		Action = action,
		LookAt = lookAt,
	})
end

function Agent.HasArrived(agent: Agent, now: number): boolean
	return now >= ColonistMotion.GetEndTime(agent.Motion)
end

-- Puts the agent at a point instantly (spawning)
function Agent.Teleport(agent: Agent, position: Vector3, now: number)
	setMotion(agent, {
		Id = agent.Colonist.Id,
		Path = { position },
		Speed = 0,
		StartTime = now,
		Action = "Idle",
	})
end

return Agent
