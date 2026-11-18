--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared
const Systems = script.Parent.Parent.Parent.Parent

const BuildingData = require(Shared.Buildings.BuildingData)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const FarmData = require(Shared.Farm.FarmData)
const InventoryTypes = require(Shared.Inventory.InventoryTypes)
const ItemsList = require(Shared.Inventory.ItemsList)
const BehaviorTree = require(script.Parent.Parent.BehaviorTree5)
const Agent = require(script.Parent.Parent.Agent)
const Tasks = require(script.Parent.Parent.Tasks)
const Bag = require(Systems.Inventory.Components.Bag)
const Mailbox = require(Systems.Colony.Components.Mailbox)
const Navigation = require(script.Parent.Parent.Parent.Components.Navigation)

type Agent = Agent.Agent
type Plot = FarmData.Plot
type SavedBuilding = ColonyTypes.SavedBuilding

-- Seconds to plant or harvest one wedge
const FIELD_WORK_TIME = 2
-- Seconds spent at the hut taking seeds or storing the harvest
const PICKUP_TIME = 1.5
const IDLE_TIME = 5
-- Seeds of each kind a Farmer accepts from the player (the rest can go in his hut's storage)
const SEED_CARRY = ItemsList.MAX_STACK

-- The Farmer works his hut's crop field (FarmData): plants every wedge the player assigned a
-- crop to with a matching seed (from his pack, else the hut's storage), harvests ripe wedges
-- (they regrow by themselves) and stores the harvest in the hut. With nothing to do he tends
-- a growing wedge or waits at the hut.
const Farmer = {}

local function getItemId(itemType: string): number?
	return ItemsList.GetItemId(itemType)
end

-- His workplace, when it has a crop field
local function getHut(agent: Agent): SavedBuilding?
	local hut = Tasks.GetBuilding(agent, agent.Colonist.Workplace)
	return if hut and BuildingData[hut.Id].Components.Field then hut else nil
end

local function getField(agent: Agent): ({ Plot }?, SavedBuilding?)
	local hut = getHut(agent)
	local field = hut and agent.Context.Data.Fields[hut.Id]
	if not hut or not field then
		return nil, nil
	end
	return field, hut
end

local function getStorage(agent: Agent): InventoryTypes.Bag?
	local hut = getHut(agent)
	return if hut then agent.Context.Data.HutStorage[hut.Id] else nil
end

local function countIn(bag: InventoryTypes.Bag?, itemType: string): number
	local id = getItemId(itemType)
	return if bag and id then Bag.CountItem(bag, id) else 0
end

local function getSeedType(crop: string): string
	local info = FarmData.GetCrop(crop)
	return if info then info.SeedItem else ""
end

-- Unlocked wedges with a crop waiting to be planted (wedge -> crop id)
local function getUnplanted(agent: Agent): { [number]: string }
	local field, hut = getField(agent)
	local list: { [number]: string } = {}
	if not field or not hut then
		return list
	end
	for wedge, plot in field do
		local info = FarmData.GetCrop(plot.Crop)
		if info and not plot.PlantedAt and FarmData.IsUnlocked(wedge, hut.Level) then
			list[wedge] = info.Id
		end
	end
	return list
end

-- Produce the Farmer carries (anything a crop yields)
local function getCarriedProduce(agent: Agent): { [number]: number }
	local carried: { [number]: number } = {}
	for _, info in FarmData.CROPS do
		local id = getItemId(info.ProduceItem)
		local count = if id then Bag.CountItem(agent.Colonist.Carried, id) else 0
		if id and count > 0 then
			carried[id] = count
		end
	end
	return carried
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
local function mailLeftovers(agent: Agent, id: number, quantity: number)
	if quantity <= 0 then
		return
	end
	Mailbox.Notify(
		agent.Context.Player,
		Mailbox.Send(agent.Context.Data, {
			From = "Lost & Found",
			Title = "Farmer's Hut full",
			Body = "Your Farmer had no room for this harvest.",
			Items = { { UniqueID = id, Quantity = quantity } },
		})
	)
end

-------- Steps --------

-- Picks the next wedge to work: a ripe one the pack has room for, else one waiting for a seed
-- the Farmer has or the hut holds
local function pickPlot(agent: Agent, now: number): boolean
	local blackboard = agent.Blackboard
	blackboard.FarmWedge = nil
	local field, hut = getField(agent)
	if not field or not hut then
		return false
	end

	for wedge, plot in field do
		local info = FarmData.GetCrop(plot.Crop)
		if
			not info
			or not FarmData.IsUnlocked(wedge, hut.Level)
			or not FarmData.IsRipe(plot, now)
		then
			continue
		end
		local id = getItemId(info.ProduceItem)
		if id and Bag.GetSpaceFor(agent.Colonist.Carried, id) >= info.Yield then
			blackboard.FarmWedge, blackboard.FarmKind, blackboard.FarmCrop =
				wedge, "Harvest", info.Id
			return true
		end
	end

	local storage = getStorage(agent)
	for wedge, crop in getUnplanted(agent) do
		local seed = getSeedType(crop)
		if countIn(agent.Colonist.Carried, seed) + countIn(storage, seed) > 0 then
			blackboard.FarmWedge, blackboard.FarmKind, blackboard.FarmCrop = wedge, "Plant", crop
			return true
		end
	end
	return false
end

-- Nothing to fetch: harvesting, or the seed is already in the pack
local function hasSeedInHand(agent: Agent): boolean
	local blackboard = agent.Blackboard
	if blackboard.FarmKind ~= "Plant" then
		return true
	end
	return countIn(agent.Colonist.Carried, getSeedType(blackboard.FarmCrop)) > 0
end

-- Stores the harvest and any seeds nothing is waiting for in the hut's storage. What doesn't
-- fit stays in the pack.
local function storeExtras(agent: Agent, storage: InventoryTypes.Bag): number
	local stored = 0
	for id, count in getCarriedProduce(agent) do
		stored += move(agent.Colonist.Carried, storage, id, count)
	end

	local wanted: { [string]: number } = {}
	for _, crop in getUnplanted(agent) do
		local seed = getSeedType(crop)
		wanted[seed] = (wanted[seed] or 0) + 1
	end
	for _, info in FarmData.CROPS do
		local seed = info.SeedItem
		local id = getItemId(seed)
		local extra = countIn(agent.Colonist.Carried, seed) - (wanted[seed] or 0)
		if id and extra > 0 then
			stored += move(agent.Colonist.Carried, storage, id, extra)
		end
	end
	return stored
end

-- At the hut: stores the harvest, then takes a seed for every wedge waiting to be planted
local function takeSeeds(agent: Agent): boolean
	local storage = getStorage(agent)
	if not storage then
		return false
	end
	storeExtras(agent, storage)

	local wanted: { [string]: number } = {}
	for _, crop in getUnplanted(agent) do
		local seed = getSeedType(crop)
		wanted[seed] = (wanted[seed] or 0) + 1
	end
	for seed, count in wanted do
		local id = getItemId(seed)
		local take = count - countIn(agent.Colonist.Carried, seed)
		if id and take > 0 then
			move(storage, agent.Colonist.Carried, id, take)
		end
	end
	agent.Context.SyncColony()
	return hasSeedInHand(agent)
end

-- Plants or harvests the picked wedge, if it still needs it
local function finishPlot(agent: Agent, now: number): boolean
	local blackboard = agent.Blackboard
	local field, hut = getField(agent)
	local wedge = blackboard.FarmWedge
	local plot = field and wedge and field[wedge]
	if not plot or not hut or not FarmData.IsUnlocked(wedge, hut.Level) then
		return false
	end
	local info = FarmData.GetCrop(plot.Crop)
	if not info or info.Id ~= blackboard.FarmCrop then
		return false
	end

	if blackboard.FarmKind == "Plant" then
		local seedId = getItemId(info.SeedItem)
		if
			plot.PlantedAt
			or not seedId
			or Bag.RemoveItem(agent.Colonist.Carried, seedId, 1) < 1
		then
			return false
		end
		plot.PlantedAt = now
		agent.Context.Log(`{agent.Colonist.Name} planted {info.Name}`)
		agent.Context.SyncColony()
		return true
	end

	local produceId = getItemId(info.ProduceItem)
	if not produceId or not FarmData.IsRipe(plot, now) then
		return false
	end
	-- Harvesting restarts its growth; no new seed needed
	plot.PlantedAt = now
	local left = Bag.AddItem(agent.Colonist.Carried, produceId, info.Yield)
	local storage = getStorage(agent)
	if left > 0 and storage then
		left = Bag.AddItem(storage, produceId, left)
	end
	mailLeftovers(agent, produceId, left)
	agent.Context.SyncColony()
	return true
end

-- Carrying a harvest the hut's storage has room for
local function hasHarvestToStore(agent: Agent): boolean
	local storage = getStorage(agent)
	if not storage then
		return false
	end
	for id in getCarriedProduce(agent) do
		if Bag.GetSpaceFor(storage, id) > 0 then
			return true
		end
	end
	return false
end

local function storeHarvest(agent: Agent): boolean
	local storage = getStorage(agent)
	if not storage then
		return false
	end
	local stored = storeExtras(agent, storage)
	agent.Context.SyncColony()
	return stored > 0
end

-------- Targets --------

local function hutDoor(agent: Agent): (Vector3?, Vector3?)
	return Tasks.DoorOf(agent, agent.Colonist.Workplace)
end

-- Middle of a wedge, facing along it toward the field's edge
local function wedgeSpot(agent: Agent, wedge: number): (Vector3?, Vector3?)
	local hut = getHut(agent)
	if not hut then
		return nil, nil
	end
	local outward = FarmData.GetDirection(FarmData.GetWedgeAngle(wedge)) * FarmData.SOIL_OUTER
	return Navigation.FromBuilding(hut, FarmData.GetWedgeCentre(wedge)),
		Navigation.FromBuilding(hut, outward)
end

local function plotSpot(agent: Agent): (Vector3?, Vector3?)
	local wedge = agent.Blackboard.FarmWedge
	if not wedge then
		return nil, nil
	end
	return wedgeSpot(agent, wedge)
end

-- A random growing wedge to tend while waiting, else the hut
local function idleSpot(agent: Agent): (Vector3?, Vector3?)
	local field, hut = getField(agent)
	local growing = {}
	if field and hut then
		for wedge, plot in field do
			if plot.PlantedAt and FarmData.IsUnlocked(wedge, hut.Level) then
				table.insert(growing, wedge)
			end
		end
	end
	if #growing > 0 then
		return wedgeSpot(agent, growing[agent.Context.Random:NextInteger(1, #growing)])
	end
	return hutDoor(agent)
end

-------- Status --------

local function getCropName(agent: Agent): string
	local info = FarmData.GetCrop(agent.Blackboard.FarmCrop)
	return if info then info.Name else "crops"
end

local function workStatus(agent: Agent): string
	local verb = if agent.Blackboard.FarmKind == "Plant" then "Planting" else "Harvesting"
	return `{verb} {getCropName(agent)}`
end

local function walkStatus(agent: Agent): string
	local verb = if agent.Blackboard.FarmKind == "Plant" then "plant" else "harvest"
	return `Going to {verb} {getCropName(agent)}`
end

local function getWaitStatus(agent: Agent): string
	local field = getField(agent)
	if not field then
		return "Waiting at the Farmer's Hut"
	end
	if next(getCarriedProduce(agent)) and not hasHarvestToStore(agent) then
		return "The Farmer's Hut storage is full"
	end

	local missing: { [string]: boolean } = {}
	local names = {}
	for _, crop in getUnplanted(agent) do
		local info = FarmData.GetCrop(crop)
		if info and not missing[info.SeedItem] then
			missing[info.SeedItem] = true
			local id = getItemId(info.SeedItem)
			table.insert(names, (id and ItemsList.GetDisplayName(id)) or info.SeedItem)
		end
	end
	if #names > 0 then
		table.sort(names)
		return `Needs {table.concat(names, ", ")} to plant`
	end

	for _, plot in field do
		if plot.PlantedAt then
			return "Tending the field"
		end
	end
	return "No crops to grow: pick some in the Farmer's Hut"
end

-------- Give rules --------

-- Seeds the Farmer accepts from the player (up to SEED_CARRY of each kind)
function Farmer.GetWanted(agent: Agent): { [string]: number }
	local wanted: { [string]: number } = {}
	for _, info in FarmData.CROPS do
		local seed = info.SeedItem
		local room = SEED_CARRY - countIn(agent.Colonist.Carried, seed)
		if room > 0 then
			wanted[seed] = room
		end
	end
	return wanted
end

function Farmer.Node()
	return BehaviorTree.Selector({
		nodes = {
			-- Plant or harvest a wedge, fetching its seed from the hut first if needed
			BehaviorTree.Sequence({
				nodes = {
					Tasks.Do(pickPlot),
					BehaviorTree.Selector({
						nodes = {
							Tasks.Do(hasSeedInHand),
							BehaviorTree.Sequence({
								nodes = {
									Tasks.MoveTo(hutDoor, "Fetching seeds"),
									Tasks.Wait(PICKUP_TIME, PICKUP_TIME, "Idle", "Taking seeds"),
									Tasks.Do(takeSeeds),
								},
							}),
						},
					}),
					Tasks.MoveTo(plotSpot, walkStatus),
					Tasks.Wait(FIELD_WORK_TIME, FIELD_WORK_TIME, "Work", workStatus),
					Tasks.Do(finishPlot),
				},
			}),
			-- Store the harvest in the hut
			BehaviorTree.Sequence({
				nodes = {
					Tasks.Do(hasHarvestToStore),
					Tasks.MoveTo(hutDoor, "Bringing the harvest to the hut"),
					Tasks.Wait(PICKUP_TIME, PICKUP_TIME, "Idle", "Storing the harvest"),
					Tasks.Do(storeHarvest),
				},
			}),
			-- Nothing ripe and no seeds to plant: tend the field or wait at the hut
			BehaviorTree.Sequence({
				nodes = {
					Tasks.MoveTo(idleSpot, getWaitStatus),
					Tasks.Wait(IDLE_TIME, IDLE_TIME, "Work", getWaitStatus),
				},
			}),
		},
	})
end

return Farmer
