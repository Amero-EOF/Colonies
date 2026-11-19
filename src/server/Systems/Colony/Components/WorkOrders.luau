--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared

const BuildingBlueprint = require(Shared.Buildings.BuildingBlueprint)
const BuildingTypes = require(Shared.Buildings.BuildingTypes)
const ColonyTypes = require(Shared.Colony.ColonyTypes)

type BuildingId = BuildingTypes.BuildingId
type ColonyData = ColonyTypes.ColonyData
type WorkOrder = ColonyTypes.WorkOrder

local function getPending(data: ColonyData, buildingId: BuildingId): WorkOrder?
	for _, order in data.WorkOrders do
		if order.BuildingId == buildingId then
			return order
		end
	end
	return nil
end

local function create(data: ColonyData, kind: "Build" | "Upgrade", buildingId: BuildingId, targetLevel: number): WorkOrder
	local order: WorkOrder = {
		Id = data.NextWorkOrderId,
		Kind = kind,
		BuildingId = buildingId,
		TargetLevel = targetLevel,
		Progress = 0,
		TotalParts = #BuildingBlueprint.Get(buildingId, targetLevel).Parts,
	}
	data.NextWorkOrderId += 1
	table.insert(data.WorkOrders, order)
	return order
end

local function createUpgrade(data: ColonyData, buildingId: BuildingId, targetLevel: number): WorkOrder
	return create(data, "Upgrade", buildingId, targetLevel)
end

-- A newly placed building waiting to be raised to level 1
local function createBuild(data: ColonyData, buildingId: BuildingId): WorkOrder
	return create(data, "Build", buildingId, 1)
end

local function getById(data: ColonyData, id: number): WorkOrder?
	for _, order in data.WorkOrders do
		if order.Id == id then
			return order
		end
	end
	return nil
end

local function remove(data: ColonyData, id: number)
	for i, order in data.WorkOrders do
		if order.Id == id then
			table.remove(data.WorkOrders, i)
			return
		end
	end
end

-- Older saves had timed orders; turn them into part-by-part ones
local function migrate(data: ColonyData)
	for _, order in data.WorkOrders do
		local old = order :: any
		old.CompleteAt = nil
		order.TotalParts = #BuildingBlueprint.Get(order.BuildingId, order.TargetLevel).Parts
		-- Blueprints can shrink (upgrades only place the pieces a level adds)
		order.Progress = math.min(order.Progress or 0, order.TotalParts)
		order.BuilderId = nil
	end
end

return {
	GetPending = getPending,
	GetById = getById,
	CreateUpgrade = createUpgrade,
	CreateBuild = createBuild,
	Remove = remove,
	Migrate = migrate,
}
