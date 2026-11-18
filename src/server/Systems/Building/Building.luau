--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared

const BuildingData = require(Shared.Buildings.BuildingData)
const BuildingTypes = require(Shared.Buildings.BuildingTypes)

type BuildingId = BuildingTypes.BuildingId
type BuildingInfo = BuildingTypes.BuildingInfo

-- A placed building is plain data; behaviour lives in systems that act on its components.
-- Nothing (placing, upgrading, workers) is implemented yet.
export type BuildingObject = {
	Id: BuildingId,
	Info: BuildingInfo,
	Level: number,
}

const Building = {}

function Building.new(id: BuildingId, level: number): BuildingObject
	local info = BuildingData[id]
	assert(info, `Unknown building id: {id}`)

	return {
		Id = id,
		Info = info,
		Level = level,
	}
end

return Building
