--!strict

export type ResourceId = "Wood" | "Stone" | "Ore" | "Food"
export type ToolType = "Axe" | "Pickaxe"
export type NodeId = "Tree" | "Rock" | "OreRock" | "Bush"

export type ToolInfo = {
	Id: string,
	Name: string,
	Type: ToolType,
	-- Gather speed multiplier; better tools are faster
	Speed: number,
}

-- A gatherable object in the wilds (tree, rock...)
export type NodeInfo = {
	Id: NodeId,
	Name: string,
	Resource: ResourceId,
	Yield: number,
	-- Seconds to gather with a Speed 1 tool
	GatherTime: number,
	-- nil when no tool is needed
	Tool: ToolType?,
	RespawnTime: number,
}

const RESOURCES: { ResourceId } = { "Wood", "Stone", "Ore", "Food" }

const NODES: { [NodeId]: NodeInfo } = {
	Tree = {
		Id = "Tree",
		Name = "Tree",
		Resource = "Wood",
		Yield = 5,
		GatherTime = 3,
		Tool = "Axe",
		RespawnTime = 60,
	},
	Rock = {
		Id = "Rock",
		Name = "Rock",
		Resource = "Stone",
		Yield = 4,
		GatherTime = 4,
		Tool = "Pickaxe",
		RespawnTime = 90,
	},
	OreRock = {
		Id = "OreRock",
		Name = "Ore Rock",
		Resource = "Ore",
		Yield = 2,
		GatherTime = 6,
		Tool = "Pickaxe",
		RespawnTime = 180,
	},
	Bush = {
		Id = "Bush",
		Name = "Berry Bush",
		Resource = "Food",
		Yield = 3,
		GatherTime = 2,
		Tool = nil,
		RespawnTime = 45,
	},
}

const TOOLS: { [string]: ToolInfo } = {
	Axe = { Id = "Axe", Name = "Axe", Type = "Axe", Speed = 1 },
	Pickaxe = { Id = "Pickaxe", Name = "Pickaxe", Type = "Pickaxe", Speed = 1 },
}

-- Seconds to gather a node with the given tool, or nil when the right tool isn't equipped
local function getGatherTime(node: NodeInfo, tool: ToolInfo?): number?
	if not node.Tool then
		return node.GatherTime
	end

	if not tool or tool.Type ~= node.Tool then
		return nil
	end

	return node.GatherTime / tool.Speed
end

return {
	RESOURCES = RESOURCES,
	NODES = NODES,
	TOOLS = TOOLS,
	STARTER_TOOLS = { "Axe", "Pickaxe" },
	-- Horizontal studs between the player and a node's base
	GATHER_RANGE = 14,
	GetGatherTime = getGatherTime,
}
