--!strict

const DayCycle = require(script.Parent.Parent.Time.DayCycle)

-- Resource yards: buildings with a Yard component (BuildingData) stand in the middle of a round
-- yard of resource nodes (trees, rocks...) that their worker harvests and that grow back by
-- themselves. One yard kind per kind of node; AI/Jobs/Gatherer works any of them.
-- All geometry is in the hut's local space: studs, pivot at the base centre, front (door) = +Z.

-- One thing a worked node can give
export type Yield = {
	-- ItemsList item type
	Item: string,
	Min: number,
	Max: number,
	-- 0-1 chance this item drops at all
	Chance: number,
}

export type YardInfo = {
	Kind: string,
	-- One node and several, lower case ("tree", "trees")
	NodeName: string,
	NodePlural: string,
	-- Stage names in growth order. A node is at stage 1 right after it was worked and ready
	-- again at the last one.
	Stages: { string },
	Yields: { Yield },
	-- Seconds from being worked until ready again
	RegrowTime: number,
	-- Seconds of work per node
	WorkTime: number,
	-- Nodes at hut level 1, and more per level above it
	BaseNodes: number,
	NodesPerLevel: number,
	-- The worker hauls to the hut once he carries this many yielded items
	CarryLimit: number,
	-- Status lines of the worker
	WalkStatus: string,
	WorkStatus: string,
	IdleStatus: string,
	-- Extra moment at the node after working it (replanting); nil skips it
	AfterStatus: string?,
	AfterTime: number,
	-- What the worker calls his building when hauling ("hut", "mine")
	HomeName: string,
	-- Placeholder ground under the yard
	GroundColor: Color3,
	GroundMaterial: Enum.Material,
}

-- Saved per node in the hut's yard state
export type Node = {
	-- Server time it was last worked; nil while it never was (ready)
	HarvestedAt: number?,
}

const YARDS: { [string]: YardInfo } = {
	-- Forester's Hut: trees chopped for Wood. He replants, so a stump turns into a sapling
	-- and grows back.
	Trees = {
		Kind = "Trees",
		NodeName = "tree",
		NodePlural = "trees",
		Stages = { "Stump", "Sapling", "Young tree", "Grown tree" },
		Yields = {
			{ Item = "Wood", Min = 3, Max = 5, Chance = 1 },
		},
		RegrowTime = DayCycle.Hours(8),
		WorkTime = 4,
		BaseNodes = 4,
		NodesPerLevel = 2,
		CarryLimit = 16,
		WalkStatus = "Going to chop a tree",
		WorkStatus = "Chopping a tree",
		IdleStatus = "Waiting for trees to grow",
		AfterStatus = "Replanting a sapling",
		AfterTime = 1.5,
		HomeName = "hut",
		GroundColor = Color3.fromRGB(70, 110, 55),
		GroundMaterial = Enum.Material.Grass,
	},
	-- Mine: rocks dug for Stone and some Ore; the face fills back in over time
	Rocks = {
		Kind = "Rocks",
		NodeName = "rock",
		NodePlural = "rocks",
		Stages = { "Rubble", "Loose rock", "Solid rock" },
		Yields = {
			{ Item = "Stone", Min = 2, Max = 4, Chance = 1 },
			{ Item = "Ore", Min = 1, Max = 2, Chance = 0.4 },
		},
		RegrowTime = DayCycle.Hours(10),
		WorkTime = 5,
		BaseNodes = 3,
		NodesPerLevel = 2,
		CarryLimit = 16,
		WalkStatus = "Going to mine a rock",
		WorkStatus = "Mining a rock",
		IdleStatus = "Waiting for the rock to settle",
		AfterStatus = nil,
		AfterTime = 0,
		HomeName = "mine",
		GroundColor = Color3.fromRGB(105, 100, 95),
		GroundMaterial = Enum.Material.Slate,
	},
}

-- Side of the square around the hut that colonists path around (the rest of the yard is walkable)
const HUT_FOOTPRINT = 24
-- Whole yard: a circle of this radius (footprint 2 * YARD_RADIUS square)
const YARD_RADIUS = 40
-- Top of the yard's ground (nodes stand on it)
const GROUND_HEIGHT = 0.3
-- Nodes alternate between two rings around the hut
const RING_INNER = 26
const RING_OUTER = 34
-- Arc in front of the hut (around +Z) kept free of nodes, for its door
const FRONT_GAP = math.rad(70)
-- Studs toward the hut from a node where its worker stands
const STAND_DISTANCE = 3.5
-- Hut levels nodes are added for (BuildingUnlocks.BUILDING_MAX_LEVEL)
const MAX_LEVEL = 6

-- Node spots per yard kind, in unlock order
const slots: { [string]: { Vector3 } } = {}

local function gcd(a: number, b: number): number
	while b ~= 0 do
		a, b = b, a % b
	end
	return a
end

-- A yard kind's info from any value (nil when it isn't one)
local function getInfo(kind: unknown): YardInfo?
	return if typeof(kind) == "string" then YARDS[kind] else nil
end

-- Nodes a yard has at a hut level (0 while the hut is a construction site)
local function getNodeCount(info: YardInfo, level: number): number
	if level < 1 then
		return 0
	end
	return info.BaseNodes + info.NodesPerLevel * (math.min(level, MAX_LEVEL) - 1)
end

local function getMaxNodes(info: YardInfo): number
	return getNodeCount(info, MAX_LEVEL)
end

-- Unit direction from the hut centre toward angle `a`: radians from the front (+Z) toward +X
local function getDirection(angle: number): Vector3
	return Vector3.new(math.sin(angle), 0, math.cos(angle))
end

-- Hut-local ground spots of every node the yard can ever have; index = node. The first
-- getNodeCount(level) are in use. Spots are spread so each level's nodes surround the hut.
local function getSlots(info: YardInfo): { Vector3 }
	local cached = slots[info.Kind]
	if cached then
		return cached
	end

	local count = getMaxNodes(info)
	-- Walking the arc in strides (coprime with the count) visits every spot once, far apart first
	local stride = math.max(math.floor(count * 0.4), 1)
	while gcd(stride, count) ~= 1 do
		stride += 1
	end

	local arc = math.pi * 2 - FRONT_GAP
	local list = {}
	for node = 1, count do
		local spot = ((node - 1) * stride) % count
		local angle = FRONT_GAP / 2 + (spot + 0.5) * arc / count
		local radius = if spot % 2 == 0 then RING_INNER else RING_OUTER
		list[node] = getDirection(angle) * radius
	end

	slots[info.Kind] = list
	return list
end

-- Hut-local ground spot of a node
local function getNodePosition(info: YardInfo, node: number): Vector3?
	return getSlots(info)[node]
end

-- Hut-local spot the worker stands at to work a node (between it and the hut)
local function getStandPosition(info: YardInfo, node: number): Vector3?
	local position = getSlots(info)[node]
	if not position then
		return nil
	end
	return position - position.Unit * STAND_DISTANCE
end

-- 0..1 regrowth of a node at `now` (1 = ready)
local function getProgress(info: YardInfo, node: Node, now: number): number
	local harvestedAt = node.HarvestedAt
	if not harvestedAt or info.RegrowTime <= 0 then
		return 1
	end
	return math.clamp((now - harvestedAt) / info.RegrowTime, 0, 1)
end

-- Growth stage (1..#Stages) of a node at `now`
local function getStage(info: YardInfo, node: Node, now: number): number
	local stages = #info.Stages
	local progress = getProgress(info, node, now)
	return math.min(math.floor(progress * (stages - 1)) + 1, stages)
end

local function isReady(info: YardInfo, node: Node, now: number): boolean
	return getProgress(info, node, now) >= 1
end

-- Seconds until a node is ready again (0 when it is)
local function getTimeLeft(info: YardInfo, node: Node, now: number): number
	return (1 - getProgress(info, node, now)) * info.RegrowTime
end

-- A yard's saved nodes with every gap filled (new nodes are ready); keeps what is there
local function fillNodes(info: YardInfo, nodes: { Node }?): { Node }
	local list: { Node } = nodes or {}
	for node = 1, getMaxNodes(info) do
		list[node] = list[node] or {}
	end
	return list
end

return {
	YARDS = YARDS,
	HUT_FOOTPRINT = HUT_FOOTPRINT,
	YARD_RADIUS = YARD_RADIUS,
	GROUND_HEIGHT = GROUND_HEIGHT,
	RING_INNER = RING_INNER,
	RING_OUTER = RING_OUTER,
	FRONT_GAP = FRONT_GAP,
	STAND_DISTANCE = STAND_DISTANCE,
	MAX_LEVEL = MAX_LEVEL,
	GetInfo = getInfo,
	GetNodeCount = getNodeCount,
	GetMaxNodes = getMaxNodes,
	GetDirection = getDirection,
	GetNodePosition = getNodePosition,
	GetStandPosition = getStandPosition,
	GetProgress = getProgress,
	GetStage = getStage,
	IsReady = isReady,
	GetTimeLeft = getTimeLeft,
	FillNodes = fillNodes,
}
