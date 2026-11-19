--!strict

const BuildingCosts = require(script.Parent.BuildingCosts)
const BuildingModels = require(script.Parent.BuildingModels)
const BuildingTypes = require(script.Parent.BuildingTypes)

type BuildingId = BuildingTypes.BuildingId
type Cost = BuildingCosts.Cost

export type BlueprintPart = {
	-- Build order, bottom-up
	Index: number,
	-- Material item type the part is made of ("Wood", "Stone"...)
	Material: string,
	-- Materials the Builder spends placing this part
	Cost: Cost,
}

export type Blueprint = {
	Parts: { BlueprintPart },
	Total: Cost,
}

-- Roblox materials that count as Wood; everything else is Stone unless a part has a BuildMaterial attribute
const WOOD_MATERIALS = {
	[Enum.Material.Wood] = true,
	[Enum.Material.WoodPlanks] = true,
}

const BuildingBlueprint = {}

const cache: { [string]: Blueprint } = {}

local function getBottom(pivot: CFrame, part: BasePart): number
	local cframe = pivot:ToObjectSpace(part.CFrame)
	local size = part.Size
	-- Half height of the part's world-aligned box
	local halfY = (
		math.abs(cframe.RightVector.Y) * size.X
		+ math.abs(cframe.UpVector.Y) * size.Y
		+ math.abs(cframe.LookVector.Y) * size.Z
	) / 2
	return cframe.Y - halfY
end

local function roundTo(value: number, step: number): number
	return math.round(value / step) * step
end

-- A model's BaseParts in build order: bottom first, then X, then Z. Server and client sort the same
-- model the same way, so part N on the client is part N in the blueprint.
function BuildingBlueprint.GetOrderedParts(model: Model): { BasePart }
	local pivot = model:GetPivot()
	local entries = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local offset = pivot:PointToObjectSpace(descendant.Position)
			table.insert(entries, {
				Part = descendant,
				Bottom = roundTo(getBottom(pivot, descendant), 0.1),
				X = roundTo(offset.X, 0.1),
				Z = roundTo(offset.Z, 0.1),
			})
		end
	end

	table.sort(entries, function(a, b)
		if a.Bottom ~= b.Bottom then
			return a.Bottom < b.Bottom
		elseif a.X ~= b.X then
			return a.X < b.X
		elseif a.Z ~= b.Z then
			return a.Z < b.Z
		end
		return a.Part.Name < b.Part.Name
	end)

	local parts = {}
	for i, entry in entries do
		parts[i] = entry.Part
	end
	return parts
end

-- Identifies a part across levels: name, position and size relative to `pivot`, which should be
-- the model's layout frame (BuildingModels.GetLayoutFrame) so levels with different base centres
-- still match up
function BuildingBlueprint.GetPartKey(pivot: CFrame, part: BasePart): string
	local offset = pivot:PointToObjectSpace(part.Position)
	local size = part.Size
	-- `+ 0` turns -0 into 0 so both print the same
	local function n(value: number): number
		return math.round(value * 10) + 0
	end
	return `{part.Name}|{n(offset.X)},{n(offset.Y)},{n(offset.Z)}|{n(size.X)},{n(size.Y)},{n(size.Z)}`
end

const keyCache: { [string]: { [string]: boolean } } = {}

-- Keys (GetPartKey) of every part in the building's model at `level`; empty below level 1
function BuildingBlueprint.GetPartKeys(id: BuildingId, level: number): { [string]: boolean }
	local cacheKey = `{id}_{level}`
	local cached = keyCache[cacheKey]
	if cached then
		return cached
	end
	local keys: { [string]: boolean } = {}
	if level >= 1 then
		local model = BuildingModels.Create(id, level)
		local pivot = BuildingModels.GetLayoutFrame(model)
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				keys[BuildingBlueprint.GetPartKey(pivot, descendant)] = true
			end
		end
		model:Destroy()
	end
	keyCache[cacheKey] = keys
	return keys
end

-- The parts a Builder places to reach `level`, in build order: at level 1 the whole model, above it
-- only the pieces the level adds to the one below. Returns the whole model when the two levels
-- look the same; the boolean is true when the list is just the added pieces (or level 1).
function BuildingBlueprint.GetBuildParts(
	model: Model,
	id: BuildingId,
	level: number
): ({ BasePart }, boolean)
	local ordered = BuildingBlueprint.GetOrderedParts(model)
	if level <= 1 then
		return ordered, true
	end
	local previous = BuildingBlueprint.GetPartKeys(id, level - 1)
	local pivot = BuildingModels.GetLayoutFrame(model)
	local added = {}
	for _, part in ordered do
		if not previous[BuildingBlueprint.GetPartKey(pivot, part)] then
			table.insert(added, part)
		end
	end
	if #added == 0 then
		return ordered, false
	end
	return added, true
end

function BuildingBlueprint.GetMaterial(part: BasePart): string
	local override = part:GetAttribute("BuildMaterial")
	if typeof(override) == "string" then
		return override
	end
	return if WOOD_MATERIALS[part.Material] then "Wood" else "Stone"
end

-- Splits `amount` into integers across `weights`: everyone gets 1 first when there's enough,
-- then the rest goes by weight using the largest remainder
local function distribute(amount: number, weights: { number }): { number }
	local count = #weights
	local shares = table.create(count, 0)
	if count == 0 or amount <= 0 then
		return shares
	end

	if amount < count then
		-- Not enough for everyone: the biggest parts get one each
		local order = {}
		for i = 1, count do
			order[i] = i
		end
		table.sort(order, function(a, b)
			return weights[a] > weights[b]
		end)
		for i = 1, amount do
			shares[order[i]] = 1
		end
		return shares
	end

	local rest = amount - count
	local total = 0
	for _, weight in weights do
		total += weight
	end

	local remainders = {}
	local given = 0
	for i, weight in weights do
		local exact = if total > 0 then rest * weight / total else rest / count
		local whole = math.floor(exact)
		shares[i] = 1 + whole
		given += whole
		table.insert(remainders, { Index = i, Fraction = exact - whole })
	end

	table.sort(remainders, function(a, b)
		if a.Fraction ~= b.Fraction then
			return a.Fraction > b.Fraction
		end
		return a.Index < b.Index
	end)
	for i = 1, rest - given do
		local entry = remainders[(i - 1) % count + 1]
		shares[entry.Index] += 1
	end

	return shares
end

-- Parts placed to reach `level` (GetBuildParts), bottom-up, with the level's cost spread across them.
-- Each material is shared by the parts made of it, weighted by part volume; a material with no
-- matching parts is shared by every part.
function BuildingBlueprint.Get(id: BuildingId, level: number): Blueprint
	local key = `{id}_{level}`
	local cached = cache[key]
	if cached then
		return cached
	end

	local model = BuildingModels.Create(id, level)
	local ordered = BuildingBlueprint.GetBuildParts(model, id, level)

	local parts: { BlueprintPart } = {}
	local volumes: { number } = {}
	for i, part in ordered do
		parts[i] = { Index = i, Material = BuildingBlueprint.GetMaterial(part), Cost = {} }
		volumes[i] = part.Size.X * part.Size.Y * part.Size.Z
	end
	model:Destroy()

	local total = BuildingCosts.Get(id, level)
	for item, amount in total do
		local indices = {}
		for i, part in parts do
			if part.Material == item then
				table.insert(indices, i)
			end
		end
		if #indices == 0 then
			for i in parts do
				table.insert(indices, i)
			end
		end

		local weights = {}
		for j, index in indices do
			weights[j] = volumes[index]
		end
		local shares = distribute(amount, weights)
		for j, index in indices do
			if shares[j] > 0 then
				parts[index].Cost[item] = shares[j]
			end
		end
	end

	local blueprint = { Parts = parts, Total = total }
	cache[key] = blueprint
	return blueprint
end

-- Materials still needed for the parts after the first `progress` ones
function BuildingBlueprint.GetRemainingCost(id: BuildingId, level: number, progress: number): Cost
	local parts = BuildingBlueprint.Get(id, level).Parts
	local remaining: Cost = {}
	for index = progress + 1, #parts do
		for item, amount in parts[index].Cost do
			remaining[item] = (remaining[item] or 0) + amount
		end
	end
	return remaining
end

return BuildingBlueprint
