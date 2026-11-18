--!strict

const ResourceData = require(script.Parent.Parent.Resources.ResourceData)

type NodeId = ResourceData.NodeId

export type WildAreaId = "Forest"

-- A wild area lives in workspace.Wilds.<Id>; nodes spawn on the parts in its Ground folder
export type WildAreaInfo = {
	Id: WildAreaId,
	Name: string,
	Description: string,
	-- Spire level needed to teleport here
	UnlockLevel: number,
	-- Chance for each ground cell to hold a node
	SpawnChance: number,
	-- Relative chance of each node type
	NodeWeights: { [NodeId]: number },
}

const AREAS: { WildAreaInfo } = {
	{
		Id = "Forest",
		Name = "Forest",
		Description = "Dense woods with some stone and berries.",
		UnlockLevel = 1,
		SpawnChance = 0.18,
		NodeWeights = { Tree = 60, Rock = 20, Bush = 15, OreRock = 5 },
	},
}

local function get(id: unknown): WildAreaInfo?
	for _, area in AREAS do
		if area.Id == id then
			return area
		end
	end

	return nil
end

return {
	AREAS = AREAS,
	Get = get,
}
