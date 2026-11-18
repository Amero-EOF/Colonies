--!strict

const BuildingTypes = require(script.Parent.BuildingTypes)

type BuildingId = BuildingTypes.BuildingId

export type Cost = { [string]: number }

-- Materials for building `id` at `level` (a new building is level 1). Spire is never built.
const OVERRIDES: { [string]: (level: number) -> Cost } = {
	Spire = function()
		return {}
	end,
	BuilderHut = function(level)
		local cost: Cost = { Wood = 24 + 24 * (level - 1), Stone = 12 + 12 * (level - 1) }
		-- Tier 3 adds the brick workshop
		if level >= 3 then
			cost.BakedClay = 16 * (level - 2)
		end
		return cost
	end,
	FarmerHut = function(level)
		local cost: Cost = { Wood = 32 + 32 * (level - 1), Stone = 16 + 16 * (level - 1) }
		-- Tier 3 swaps the shingle roofs for fired clay tiles
		if level >= 3 then
			cost.BakedClay = 16 * (level - 2)
		end
		return cost
	end,
	TownHall = function(level)
		return { Wood = 48 * level, Stone = 32 * level }
	end,
}

const BuildingCosts = {}

function BuildingCosts.Get(id: BuildingId, level: number): Cost
	local override = OVERRIDES[id]
	if override then
		return override(level)
	end
	return { Wood = 32 + 32 * (level - 1), Stone = 16 + 16 * (level - 1) }
end

return BuildingCosts
