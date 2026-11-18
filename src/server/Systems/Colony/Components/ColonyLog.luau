--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared

const ColonyData = require(Shared.Colony.ColonyData)
const ColonyTypes = require(Shared.Colony.ColonyTypes)

type ColonyData = ColonyTypes.ColonyData

-- Adds an event to the colony's saved log, dropping the oldest past MAX_EVENTS
local function add(data: ColonyData, text: string)
	table.insert(data.Events, { Time = workspace:GetServerTimeNow(), Text = text })
	while #data.Events > ColonyData.MAX_EVENTS do
		table.remove(data.Events, 1)
	end
end

return {
	Add = add,
}
