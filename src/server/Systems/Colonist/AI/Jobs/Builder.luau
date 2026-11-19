--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared
const Systems = script.Parent.Parent.Parent.Parent

const BuildingBlueprint = require(Shared.Buildings.BuildingBlueprint)
const BuildingData = require(Shared.Buildings.BuildingData)
const ColonistData = require(Shared.Colonist.ColonistData)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const ItemsList = require(Shared.Inventory.ItemsList)
const BehaviorTree = require(script.Parent.Parent.BehaviorTree5)
const Agent = require(script.Parent.Parent.Agent)
const Tasks = require(script.Parent.Parent.Tasks)
const Bag = require(Systems.Inventory.Components.Bag)
const Mailbox = require(Systems.Colony.Components.Mailbox)

type Agent = Agent.Agent
type Cost = { [string]: number }
type WorkOrder = ColonyTypes.WorkOrder

const SUCCESS, RUNNING = Tasks.SUCCESS, Tasks.RUNNING

const HUT = "BuilderHut"
-- Seconds spent loading materials at the hut
const PICKUP_TIME = 1.5
const IDLE_TIME = 5

-- The Builder raises work-order buildings part by part, bottom-up. It carries materials in its
-- 5-slot inventory and walks back to the Builder's Hut whenever the next part needs more.
-- Until the hut itself is built, it only works on the hut, with materials the player hands it.
const Builder = {}

-- Server-wide build speed (testing); 2 = parts take half as long
local speedMultiplier = 1

function Builder.SetSpeedMultiplier(multiplier: number)
	speedMultiplier = multiplier
end

function Builder.GetSpeedMultiplier(): number
	return speedMultiplier
end

-- The hut is built and has its storage
local function isHutReady(agent: Agent): boolean
	local hut = Tasks.GetBuilding(agent, HUT)
	return hut ~= nil and hut.Level >= 1 and agent.Context.Data.HutStorage[HUT] ~= nil
end

local function getItemId(itemType: string): number?
	local item = ItemsList.GetItemByItemType(itemType)
	return item and item.UniqueID
end

local function getOrder(agent: Agent): WorkOrder?
	local id = agent.Blackboard.OrderId
	for _, order in agent.Context.Data.WorkOrders do
		if order.Id == id then
			return order
		end
	end
	return nil
end

local function getNextPartCost(order: WorkOrder): Cost?
	local part =
		BuildingBlueprint.Get(order.BuildingId, order.TargetLevel).Parts[order.Progress + 1]
	return part and part.Cost
end

local function countCarried(agent: Agent, itemType: string): number
	local id = getItemId(itemType)
	return if id then Bag.CountItem(agent.Colonist.Carried, id) else 0
end

local function covers(agent: Agent, cost: Cost): boolean
	for itemType, amount in cost do
		if countCarried(agent, itemType) < amount then
			return false
		end
	end
	return true
end

-- Pack slots needed to hold these totals
local function slotsFor(totals: Cost): number
	local slots = 0
	for itemType, amount in totals do
		local item = ItemsList.GetItemByItemType(itemType)
		local maxStack = if item then item.MaxStack else ItemsList.MAX_STACK
		slots += math.ceil(amount / maxStack)
	end
	return slots
end

local function describe(cost: Cost): string
	local parts = {}
	for itemType, amount in cost do
		table.insert(parts, `{amount} {itemType}`)
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

local function getPartTime(agent: Agent, cost: Cost): number
	local units = 0
	for _, amount in cost do
		units += amount
	end
	local adaptability = agent.Colonist.Skills.Adaptability or 0
	return (ColonistData.BUILD_PART_TIME + ColonistData.BUILD_TIME_PER_UNIT * units)
		/ (1 + adaptability / ColonistData.ADAPTABILITY_SCALE)
		/ speedMultiplier
end

-- Oldest work order that no other Builder has claimed (only its own hut until that is built)
local function pickOrder(agent: Agent): boolean
	agent.Blackboard.Shortage = nil
	local hutReady = isHutReady(agent)
	local best: WorkOrder? = nil
	for _, order in agent.Context.Data.WorkOrders do
		local free = order.BuilderId == nil or order.BuilderId == agent.Colonist.Id
		local allowed = hutReady or order.BuildingId == HUT
		if free and allowed and (not best or order.Id < best.Id) then
			best = order
		end
	end
	if not best then
		agent.Blackboard.OrderId = nil
		return false
	end
	best.BuilderId = agent.Colonist.Id
	agent.Blackboard.OrderId = best.Id
	return true
end

local function hasNextPart(agent: Agent): boolean
	local order = getOrder(agent)
	local cost = order and getNextPartCost(order)
	return cost ~= nil and covers(agent, cost)
end

-- Loads as many upcoming parts' materials as fit in the pack and the hut has
local function loadMaterials(agent: Agent): boolean
	local order = getOrder(agent)
	local hut = agent.Context.Data.HutStorage[HUT]
	if not order or not hut or not isHutReady(agent) then
		return false
	end

	local parts = BuildingBlueprint.Get(order.BuildingId, order.TargetLevel).Parts
	local slots = Bag.GetSlotsCount(agent.Colonist.Carried)
	local needed: Cost = {}
	local planned = 0
	for index = order.Progress + 1, #parts do
		local tentative = table.clone(needed)
		for itemType, amount in parts[index].Cost do
			tentative[itemType] = (tentative[itemType] or 0) + amount
		end

		local fits = slotsFor(tentative) <= slots
		for itemType, amount in tentative do
			local id = getItemId(itemType)
			local available = countCarried(agent, itemType)
				+ (if id then Bag.CountItem(hut, id) else 0)
			if amount > available then
				fits = false
			end
		end
		if not fits then
			break
		end
		needed = tentative
		planned += 1
	end

	if planned == 0 then
		-- Ask for everything the rest of the order needs, not just the next part
		local remaining =
			BuildingBlueprint.GetRemainingCost(order.BuildingId, order.TargetLevel, order.Progress)
		local missing: Cost = {}
		for itemType, amount in remaining do
			local id = getItemId(itemType)
			local short = amount
				- countCarried(agent, itemType)
				- (if id then Bag.CountItem(hut, id) else 0)
			if short > 0 then
				missing[itemType] = short
			end
		end
		agent.Blackboard.Shortage = if next(missing)
			then `Needs {describe(missing)} more in the Builder's Hut`
			else "Inventory too full to carry the next part"
		return false
	end

	for itemType, amount in needed do
		local id = getItemId(itemType)
		local take = amount - countCarried(agent, itemType)
		if id and take > 0 then
			local removed = Bag.RemoveItem(hut, id, take)
			local left = Bag.AddItem(agent.Colonist.Carried, id, removed)
			if left > 0 then
				-- Pack full after all: put the rest back (anything that won't fit is mailed)
				local lost = Bag.AddItem(hut, id, left)
				if lost > 0 then
					Mailbox.Notify(
						agent.Context.Player,
						Mailbox.Send(agent.Context.Data, {
							From = "Lost & Found",
							Title = "Builder's Hut full",
							Body = "These didn't fit back into the Builder's Hut.",
							Items = { { UniqueID = id, Quantity = lost } },
						})
					)
				end
			end
		end
	end
	agent.Context.SyncColony()
	return true
end

-- Materials the current order still needs beyond what the Builder carries
function Builder.GetWanted(agent: Agent): Cost
	local order = getOrder(agent)
	if not order and pickOrder(agent) then
		order = getOrder(agent)
	end
	if not order then
		return {}
	end
	local wanted =
		BuildingBlueprint.GetRemainingCost(order.BuildingId, order.TargetLevel, order.Progress)
	local remaining: Cost = {}
	for itemType, amount in wanted do
		local left = amount - countCarried(agent, itemType)
		if left > 0 then
			remaining[itemType] = left
		end
	end
	return remaining
end

local function getWaitStatus(agent: Agent): string
	if agent.Blackboard.Shortage then
		return agent.Blackboard.Shortage
	end
	if not isHutReady(agent) then
		local wanted = Builder.GetWanted(agent)
		if next(wanted) then
			return `Bring me {describe(wanted)} to build the Builder's Hut`
		end
	end
	return "Waiting for work orders"
end

local function getSiteName(agent: Agent): string
	local order = getOrder(agent)
	return if order then BuildingData[order.BuildingId].Name else "site"
end

-- Places parts while the pack covers them; succeeds when done or out of materials
local function buildTask()
	return BehaviorTree.Task({
		start = function(agent: Agent, now: number)
			local order = getOrder(agent)
			if not order then
				return
			end
			local _, centre = Tasks.DoorOf(agent, order.BuildingId)
			agent.Status = `Building the {getSiteName(agent)} ({order.Progress}/{order.TotalParts})`
			Agent.SetAction(agent, "Build", centre, now)
			local cost = getNextPartCost(order)
			agent.Blackboard.PartDoneAt = now + (if cost then getPartTime(agent, cost) else 0)
		end,
		run = function(agent: Agent, now: number)
			local order = getOrder(agent)
			if not order then
				return SUCCESS
			end
			if now < agent.Blackboard.PartDoneAt then
				return RUNNING
			end

			-- A save whose blueprint shrank can load with every part already placed
			if order.Progress >= order.TotalParts then
				agent.Context.CompleteWorkOrder(order.Id)
				agent.Blackboard.OrderId = nil
				return SUCCESS
			end
			local cost = getNextPartCost(order)
			if not cost or not covers(agent, cost) then
				return SUCCESS
			end
			for itemType, amount in cost do
				local id = getItemId(itemType)
				if id then
					Bag.RemoveItem(agent.Colonist.Carried, id, amount)
				end
			end
			order.Progress += 1
			agent.Status = `Building the {getSiteName(agent)} ({order.Progress}/{order.TotalParts})`

			if order.Progress >= order.TotalParts then
				agent.Context.Log(
					`{agent.Colonist.Name} finished building the {getSiteName(agent)}`
				)
				agent.Context.CompleteWorkOrder(order.Id)
				agent.Blackboard.OrderId = nil
				return SUCCESS
			end
			agent.Context.SyncColony()

			local nextCost = getNextPartCost(order)
			if not nextCost or not covers(agent, nextCost) then
				return SUCCESS
			end
			agent.Blackboard.PartDoneAt = now + getPartTime(agent, nextCost)
			return RUNNING
		end,
	})
end

local function hutDoor(agent: Agent): (Vector3?, Vector3?)
	return Tasks.SpotOf(agent, HUT, "StorageStand")
end

local function siteDoor(agent: Agent): (Vector3?, Vector3?)
	local order = getOrder(agent)
	return Tasks.DoorOf(agent, order and order.BuildingId)
end

function Builder.Node()
	return BehaviorTree.Selector({
		nodes = {
			BehaviorTree.Sequence({
				nodes = {
					Tasks.Do(pickOrder),
					BehaviorTree.Selector({
						nodes = {
							Tasks.Do(hasNextPart),
							BehaviorTree.Sequence({
								nodes = {
									Tasks.Do(isHutReady),
									Tasks.MoveTo(hutDoor, "Fetching materials"),
									Tasks.Wait(
										PICKUP_TIME,
										PICKUP_TIME,
										"Idle",
										"Loading materials"
									),
									Tasks.Do(loadMaterials),
								},
							}),
						},
					}),
					Tasks.MoveTo(siteDoor, function(agent)
						return `Walking to the {getSiteName(agent)}`
					end),
					buildTask(),
				},
			}),
			-- Nothing to build, or waiting on materials
			BehaviorTree.Sequence({
				nodes = {
					Tasks.MoveTo(hutDoor, "Going to the Builder's Hut"),
					Tasks.Wait(IDLE_TIME, IDLE_TIME, "Work", getWaitStatus),
				},
			}),
		},
	})
end

return Builder
