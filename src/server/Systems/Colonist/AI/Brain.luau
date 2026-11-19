--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared
const Systems = script.Parent.Parent.Parent

const BuildingUnlocks = require(Shared.Buildings.BuildingUnlocks)
const ColonistData = require(Shared.Colonist.ColonistData)
const DayCycle = require(Shared.Time.DayCycle)
const InventoryTypes = require(Shared.Inventory.InventoryTypes)
const ItemsList = require(Shared.Inventory.ItemsList)
const BehaviorTree = require(script.Parent.BehaviorTree5)
const Agent = require(script.Parent.Agent)
const Jobs = require(script.Parent.Jobs)
const Guard = require(script.Parent.Jobs.Guard)
const Tasks = require(script.Parent.Tasks)
const Navigation = require(script.Parent.Parent.Components.Navigation)
const Population = require(script.Parent.Parent.Components.Population)
const Bag = require(Systems.Inventory.Components.Bag)
const Mailbox = require(Systems.Colony.Components.Mailbox)

type Agent = Agent.Agent

export type Mode = "Leave" | "Defend" | "Funeral" | "Sleep" | "Talk" | "Eat" | "Work" | "Wander"

const WANDER_RADIUS = 40
const FUNERAL_RADIUS = 8
-- Studs between colonists sleeping at the same home
const BED_SPACING = 3

-- Food, plus edible crops (Carrot, Potato); eaten in this order
const FOOD_IDS = ItemsList.GetFoodIds()
assert(#FOOD_IDS > 0, "Food item missing")

-- Picks what a colonist should be doing and runs it through one BTrees V5 tree.
-- The mode is decided in code each tick and written to the blackboard; the tree's top Selector
-- branches on it, and the controller aborts the tree whenever it changes.
const Brain = {}

local function countFood(bag: InventoryTypes.Bag): number
	local count = 0
	for _, id in FOOD_IDS do
		count += Bag.CountItem(bag, id)
	end
	return count
end

local function hasOwnFood(agent: Agent): boolean
	return countFood(agent.Colonist.Carried) > 0
end

local function hasStoredFood(agent: Agent): boolean
	return countFood(agent.Context.Data.Storage) > 0 and Tasks.HubSpot(agent) ~= nil
end

function Brain.GetMode(agent: Agent, now: number): Mode
	local colonist = agent.Colonist
	local context = agent.Context

	if colonist.Leaving then
		return "Leave"
	end
	-- Guards fight while raiders are on the plot: before sleep, and before a funeral too, or the
	-- first colonist a raid kills would pull every Guard out of the fight
	if Guard.IsDefending(agent) then
		return "Defend"
	end
	local funeral = context.Funeral
	if funeral and now < funeral.Until then
		return "Funeral"
	end
	if DayCycle.IsNight(now) and now >= agent.AwakeUntil then
		return "Sleep"
	end
	-- Stands still while the player talks to it (bedtime ends the conversation)
	if agent.TalkingTo then
		return "Talk"
	end
	if
		colonist.Saturation < ColonistData.HUNGRY_AT
		and (hasOwnFood(agent) or hasStoredFood(agent))
	then
		return "Eat"
	end
	local canWork = colonist.Age == "Adult"
		and colonist.Job ~= nil
		and colonist.Debuff ~= "Fight"
		and not colonist.Sick
	if canWork then
		return "Work"
	end
	return "Wander"
end

-------- Targets --------

-- Its own Bed attachment in its home, else its home's door (several colonists spread along
-- it). Homeless colonists sleep at the Town Hall, or outside around the Spire before the Town
-- Hall is built.
local function bedSpot(agent: Agent): (Vector3?, Vector3?)
	local colonist = agent.Colonist
	local home = Tasks.GetBuilding(agent, colonist.Home)
	if home and Navigation.GetSpot(home, "Bed") then
		return Tasks.SpotOf(agent, colonist.Home, "Bed", "Home")
	end
	local door, centre = Tasks.DoorOf(agent, colonist.Home)
	if not door then
		door, centre = Tasks.HubSpot(agent)
		if door and not BuildingUnlocks.IsTownHallBuilt(agent.Context.Data.Buildings) then
			-- Already a spot of its own on the ring
			return door, centre
		end
	end
	if not door then
		return nil, nil
	end
	local offset = ((colonist.Id % 3) - 1) * BED_SPACING
	return Navigation.Snap(agent.Context.Grid, door + Vector3.new(offset, 0, 0)), centre
end

local function funeralSpot(agent: Agent): (Vector3?, Vector3?)
	local funeral = agent.Context.Funeral
	if not funeral then
		return nil, nil
	end
	local angle = agent.Colonist.Id * 2.4
	local spot = funeral.Position
		+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * FUNERAL_RADIUS
	return Navigation.Snap(agent.Context.Grid, spot), funeral.Position
end

-- Where stored food is eaten: the Town Hall, or the Spire before it's built
local function hubSpot(agent: Agent): (Vector3?, Vector3?)
	return Tasks.HubSpot(agent)
end

local function wanderSpot(agent: Agent, now: number): (Vector3?, Vector3?)
	local hub = Tasks.GetBuilding(agent, BuildingUnlocks.GetHubId(agent.Context.Data.Buildings))
	local centre = (hub and Navigation.GetCentre(hub)) or Vector3.zero
	return Navigation.GetRandomPoint(
		agent.Context.Grid,
		centre,
		WANDER_RADIUS,
		agent.Context.Random
	),
		nil
end

local function edgeSpot(agent: Agent, now: number): (Vector3?, Vector3?)
	return Navigation.GetEdge(agent.Context.Grid, Agent.GetPosition(agent, now)), nil
end

-------- Steps --------

-- Eats Food (or edible crops) from a bag until full
local function eatFrom(agent: Agent, storage: InventoryTypes.Bag): boolean
	local colonist = agent.Colonist
	local wanted = math.ceil(
		(ColonistData.MAX_SATURATION - colonist.Saturation) / ColonistData.FOOD_SATURATION
	)
	local eaten = 0
	for _, id in FOOD_IDS do
		local left = math.max(wanted, 1) - eaten
		if left <= 0 then
			break
		end
		eaten += Bag.RemoveItem(storage, id, left)
	end
	colonist.Saturation = math.min(
		colonist.Saturation + eaten * ColonistData.FOOD_SATURATION,
		ColonistData.MAX_SATURATION
	)
	agent.Context.SyncColony()
	return eaten > 0
end

local function eatOwn(agent: Agent): boolean
	return eatFrom(agent, agent.Colonist.Carried)
end

local function eatStored(agent: Agent): boolean
	return eatFrom(agent, agent.Context.Data.Storage)
end

local function depart(agent: Agent): boolean
	local colonist = agent.Colonist
	local data = agent.Context.Data
	if Population.Get(data, colonist.Id) then
		local mail = Population.Remove(data, colonist, "Left")
		agent.Context.Log(`{colonist.Name} left the colony`)
		if mail then
			Mailbox.Notify(agent.Context.Player, mail)
		end
	end
	return true
end

local function wanderStatus(agent: Agent): string
	local colonist = agent.Colonist
	if colonist.Debuff == "Fight" then
		return "Refusing to work"
	elseif colonist.Sick then
		return "Sick"
	elseif colonist.Age == "Child" then
		return "Playing"
	end
	return "Wandering (unemployed)"
end

local function build()
	return BehaviorTree.Selector({
		nodes = {
			BehaviorTree.Sequence({
				nodes = {
					Tasks.Is("Mode", "Leave"),
					Tasks.MoveTo(edgeSpot, "Leaving the colony"),
					Tasks.Do(depart),
				},
			}),
			BehaviorTree.Sequence({
				nodes = {
					Tasks.Is("Mode", "Defend"),
					Guard.DefendNode(),
				},
			}),
			BehaviorTree.Sequence({
				nodes = {
					Tasks.Is("Mode", "Funeral"),
					Tasks.MoveTo(funeralSpot, "Going to a funeral"),
					Tasks.Hold("Mourn", function(agent: Agent)
						local funeral = agent.Context.Funeral
						return if funeral then `Mourning {funeral.Name}` else "Mourning"
					end),
				},
			}),
			BehaviorTree.Sequence({
				nodes = {
					Tasks.Is("Mode", "Sleep"),
					Tasks.MoveTo(bedSpot, "Going to bed"),
					Tasks.Hold("Sleep", "Sleeping"),
				},
			}),
			BehaviorTree.Sequence({
				nodes = {
					Tasks.Is("Mode", "Talk"),
					Tasks.Hold("Idle", "Talking with you"),
				},
			}),
			BehaviorTree.Sequence({
				nodes = {
					Tasks.Is("Mode", "Eat"),
					BehaviorTree.Selector({
						nodes = {
							-- Food the player gave it: eat where it stands
							BehaviorTree.Sequence({
								nodes = {
									Tasks.Do(hasOwnFood),
									Tasks.Wait(
										ColonistData.EAT_TIME,
										ColonistData.EAT_TIME,
										"Eat",
										"Eating"
									),
									Tasks.Do(eatOwn),
								},
							}),
							BehaviorTree.Sequence({
								nodes = {
									Tasks.MoveTo(hubSpot, "Going to eat"),
									Tasks.Wait(
										ColonistData.EAT_TIME,
										ColonistData.EAT_TIME,
										"Eat",
										"Eating"
									),
									Tasks.Do(eatStored),
								},
							}),
						},
					}),
				},
			}),
			BehaviorTree.Sequence({
				nodes = {
					Tasks.Is("Mode", "Work"),
					Jobs.Node(),
				},
			}),
			BehaviorTree.Sequence({
				nodes = {
					Tasks.MoveTo(wanderSpot, wanderStatus),
					Tasks.Wait(2, 6, "Idle", wanderStatus),
				},
			}),
		},
	})
end

const tree = BehaviorTree:new({ tree = build() })

-- One step of the colonist's AI
function Brain.Step(agent: Agent, now: number)
	local mode = Brain.GetMode(agent, now)
	local blackboard = agent.Blackboard
	if blackboard.Mode ~= mode then
		tree:Abort(agent, now)
		blackboard.Mode = mode
	end
	blackboard.Job = agent.Colonist.Job or "None"
	tree:Run(agent, now)
end

-- Frees the tree's per-agent state (it is never cleared otherwise)
function Brain.Forget(agent: Agent)
	tree.DataLookup[agent] = nil
end

return Brain
