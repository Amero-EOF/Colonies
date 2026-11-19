--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared
const Systems = script.Parent.Parent.Parent.Parent

const BuildingData = require(Shared.Buildings.BuildingData)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const InventoryTypes = require(Shared.Inventory.InventoryTypes)
const ItemsList = require(Shared.Inventory.ItemsList)
const YardData = require(Shared.Yard.YardData)
const BehaviorTree = require(script.Parent.Parent.BehaviorTree5)
const Agent = require(script.Parent.Parent.Agent)
const Tasks = require(script.Parent.Parent.Tasks)
const Bag = require(Systems.Inventory.Components.Bag)
const Mailbox = require(Systems.Colony.Components.Mailbox)
const Navigation = require(script.Parent.Parent.Parent.Components.Navigation)

type Agent = Agent.Agent
type Node = YardData.Node
type SavedBuilding = ColonyTypes.SavedBuilding
type YardInfo = YardData.YardInfo

-- Seconds spent at the hut storing what was gathered
const STORE_TIME = 1.5
const IDLE_TIME = 5

-- A gatherer works the resource yard around his building (YardData): he walks to a ready node,
-- works it, carries what it gave in his pack and hauls it to the building's own storage, where
-- the player collects it. Worked nodes grow back by themselves. One behavior for every yard
-- kind (Forester: Trees, Miner: Rocks); the kind's YardInfo holds everything that differs.
const Gatherer = {}

-- His workplace, when it has a yard of this kind
local function getHut(agent: Agent, info: YardInfo): SavedBuilding?
	local hut = Tasks.GetBuilding(agent, agent.Colonist.Workplace)
	local yard = hut and BuildingData[hut.Id].Components.Yard
	return if hut and yard and yard.Kind == info.Kind then hut else nil
end

local function getNodes(agent: Agent, info: YardInfo): ({ Node }?, SavedBuilding?)
	local hut = getHut(agent, info)
	local nodes = hut and agent.Context.Data.Yards[hut.Id]
	if not hut or not nodes then
		return nil, nil
	end
	return nodes, hut
end

local function getStorage(agent: Agent, info: YardInfo): InventoryTypes.Bag?
	local hut = getHut(agent, info)
	return if hut then agent.Context.Data.HutStorage[hut.Id] else nil
end

-- What the yard yields that he carries (item id -> count), and how many in total
local function getCarried(agent: Agent, info: YardInfo): ({ [number]: number }, number)
	local carried: { [number]: number } = {}
	local total = 0
	for _, yield in info.Yields do
		local id = ItemsList.GetItemId(yield.Item)
		local count = if id then Bag.CountItem(agent.Colonist.Carried, id) else 0
		if id and count > 0 and not carried[id] then
			carried[id] = count
			total += count
		end
	end
	return carried, total
end

-- Moves an item from one bag to another; anything that doesn't fit stays where it was
local function move(
	from: InventoryTypes.Bag,
	to: InventoryTypes.Bag,
	id: number,
	amount: number
): number
	local count = math.min(amount, Bag.CountItem(from, id), Bag.GetSpaceFor(to, id))
	if count <= 0 then
		return 0
	end
	local removed = Bag.RemoveItem(from, id, count)
	local left = Bag.AddItem(to, id, removed)
	if left > 0 then
		Bag.AddItem(from, id, left)
	end
	return removed - left
end

-- Items that fit nowhere go to the Town Hall mailbox
local function mailLeftovers(agent: Agent, hut: SavedBuilding, id: number, quantity: number)
	if quantity <= 0 then
		return
	end
	local job = agent.Colonist.Job or "worker"
	Mailbox.Notify(
		agent.Context.Player,
		Mailbox.Send(agent.Context.Data, {
			From = "Lost & Found",
			Title = `{BuildingData[hut.Id].Name} full`,
			Body = `Your {job} had no room for this.`,
			Items = { { UniqueID = id, Quantity = quantity } },
		})
	)
end

-- "Wood", "Stone and Ore": what he carries from the yard
local function describeCarried(agent: Agent, info: YardInfo): string
	local names = {}
	for id in getCarried(agent, info) do
		table.insert(names, ItemsList.GetDisplayName(id) or "goods")
	end
	if #names == 0 then
		return "goods"
	end
	table.sort(names)
	return table.concat(names, " and ")
end

-- Hut-local point to plot space
local function toPlot(hut: SavedBuilding, point: Vector3?): Vector3?
	return if point then Navigation.FromBuilding(hut, point) else nil
end

-------- Steps --------

-- The closest ready node he has room to work: under his carry limit, with pack space for the
-- most every yielded item can give
local function findNode(agent: Agent, now: number, info: YardInfo): number?
	local nodes, hut = getNodes(agent, info)
	if not nodes or not hut then
		return nil
	end
	local _, total = getCarried(agent, info)
	if total >= info.CarryLimit then
		return nil
	end
	for _, yield in info.Yields do
		local id = ItemsList.GetItemId(yield.Item)
		if not id or Bag.GetSpaceFor(agent.Colonist.Carried, id) < yield.Max then
			return nil
		end
	end

	local position = Agent.GetPosition(agent, now)
	local best: number? = nil
	local bestDistance = math.huge
	for index = 1, YardData.GetNodeCount(info, hut.Level) do
		local node = nodes[index]
		local spot = toPlot(hut, YardData.GetStandPosition(info, index))
		if not node or not spot or not YardData.IsReady(info, node, now) then
			continue
		end
		local distance = (spot - position).Magnitude
		if distance < bestDistance then
			best, bestDistance = index, distance
		end
	end
	return best
end

local function pickNode(agent: Agent, now: number, info: YardInfo): boolean
	local node = findNode(agent, now, info)
	agent.Blackboard.YardNode = node
	return node ~= nil
end

-- Takes what the picked node gives, if it is still ready; it then starts growing back
local function harvest(agent: Agent, now: number, info: YardInfo): boolean
	local nodes, hut = getNodes(agent, info)
	local index = agent.Blackboard.YardNode
	local node = nodes and index and nodes[index]
	if
		not node
		or not hut
		or index > YardData.GetNodeCount(info, hut.Level)
		or not YardData.IsReady(info, node, now)
	then
		return false
	end

	node.HarvestedAt = now
	local random = agent.Context.Random
	local storage = getStorage(agent, info)
	for _, yield in info.Yields do
		local id = ItemsList.GetItemId(yield.Item)
		if not id or random:NextNumber() >= yield.Chance then
			continue
		end
		local left =
			Bag.AddItem(agent.Colonist.Carried, id, random:NextInteger(yield.Min, yield.Max))
		if left > 0 and storage then
			left = Bag.AddItem(storage, id, left)
		end
		mailLeftovers(agent, hut, id, left)
	end
	agent.Context.SyncColony()
	return true
end

-- Carrying something the storage has room for, with a full load or nothing left to work
local function shouldHaul(agent: Agent, now: number, info: YardInfo): boolean
	local storage = getStorage(agent, info)
	if not storage then
		return false
	end
	local carried, total = getCarried(agent, info)
	local hasRoom = false
	for id in carried do
		hasRoom = hasRoom or Bag.GetSpaceFor(storage, id) > 0
	end
	if not hasRoom then
		return false
	end
	return total >= info.CarryLimit or findNode(agent, now, info) == nil
end

-- At the hut: puts what he gathered in its storage. What doesn't fit stays in his pack.
local function store(agent: Agent, info: YardInfo): boolean
	local storage = getStorage(agent, info)
	if not storage then
		return false
	end
	local stored = 0
	for id, count in getCarried(agent, info) do
		stored += move(agent.Colonist.Carried, storage, id, count)
	end
	agent.Context.SyncColony()
	return stored > 0
end

-- Carrying something the storage has no room for at all
local function isStorageFull(agent: Agent, info: YardInfo): boolean
	local storage = getStorage(agent, info)
	local carried, total = getCarried(agent, info)
	if not storage or total == 0 then
		return false
	end
	for id in carried do
		if Bag.GetSpaceFor(storage, id) > 0 then
			return false
		end
	end
	return true
end

-------- Targets --------

local function hutDoor(agent: Agent): (Vector3?, Vector3?)
	return Tasks.StorageSpot(agent)
end

-- Beside a node, facing it
local function nodeSpot(agent: Agent, info: YardInfo, index: number?): (Vector3?, Vector3?)
	local hut = getHut(agent, info)
	if not hut or not index then
		return nil, nil
	end
	return toPlot(hut, YardData.GetStandPosition(info, index)),
		toPlot(hut, YardData.GetNodePosition(info, index))
end

-- With nothing to work: a node that is growing back, else the hut. Waits at the hut while its
-- storage is full.
local function idleSpot(agent: Agent, now: number, info: YardInfo): (Vector3?, Vector3?)
	local nodes, hut = getNodes(agent, info)
	local growing = {}
	if nodes and hut and not isStorageFull(agent, info) then
		for index = 1, YardData.GetNodeCount(info, hut.Level) do
			local node = nodes[index]
			if node and not YardData.IsReady(info, node, now) then
				table.insert(growing, index)
			end
		end
	end
	if #growing > 0 then
		return nodeSpot(agent, info, growing[agent.Context.Random:NextInteger(1, #growing)])
	end
	return hutDoor(agent)
end

-------- Status --------

local function getWaitStatus(agent: Agent, info: YardInfo): string
	local hut = getHut(agent, info)
	if not hut then
		return "Waiting at work"
	end
	if isStorageFull(agent, info) then
		return `The {BuildingData[hut.Id].Name} storage is full`
	end
	return info.IdleStatus
end

-- The behavior of a yard kind's worker (YardData.YARDS), for the job registry
function Gatherer.NodeFor(kind: string): () -> any
	local found = YardData.GetInfo(kind)
	assert(found, `Unknown yard kind {kind}`)
	local info: YardInfo = found

	local function waitStatus(agent: Agent): string
		return getWaitStatus(agent, info)
	end

	return function()
		-- Work a node, then (trees) replant it
		local work = {
			Tasks.Do(function(agent: Agent, now: number)
				return pickNode(agent, now, info)
			end),
			Tasks.MoveTo(function(agent: Agent)
				return nodeSpot(agent, info, agent.Blackboard.YardNode)
			end, info.WalkStatus),
			Tasks.Wait(info.WorkTime, info.WorkTime, "Work", info.WorkStatus),
			Tasks.Do(function(agent: Agent, now: number)
				return harvest(agent, now, info)
			end),
		}
		local afterStatus = info.AfterStatus
		if afterStatus then
			table.insert(work, Tasks.Wait(info.AfterTime, info.AfterTime, "Work", afterStatus))
		end

		return BehaviorTree.Selector({
			nodes = {
				-- Haul a full load (or the last of it) to the hut's storage
				BehaviorTree.Sequence({
					nodes = {
						Tasks.Do(function(agent: Agent, now: number)
							return shouldHaul(agent, now, info)
						end),
						Tasks.MoveTo(hutDoor, function(agent: Agent)
							return `Hauling {describeCarried(agent, info)} to the {info.HomeName}`
						end),
						Tasks.Wait(STORE_TIME, STORE_TIME, "Idle", function(agent: Agent)
							return `Storing {describeCarried(agent, info)}`
						end),
						Tasks.Do(function(agent: Agent)
							return store(agent, info)
						end),
					},
				}),
				BehaviorTree.Sequence({ nodes = work }),
				-- Nothing ready, or no room left: wait by a growing node or at the hut
				BehaviorTree.Sequence({
					nodes = {
						Tasks.MoveTo(function(agent: Agent, now: number)
							return idleSpot(agent, now, info)
						end, waitStatus),
						Tasks.Wait(IDLE_TIME, IDLE_TIME, "Idle", waitStatus),
					},
				}),
			},
		})
	end
end

return Gatherer
