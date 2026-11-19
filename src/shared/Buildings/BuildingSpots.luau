--!strict

const BuildingModels = require(script.Parent.BuildingModels)
const BuildingTypes = require(script.Parent.BuildingTypes)

type BuildingId = BuildingTypes.BuildingId

-- Utility spots authored as Attachments inside a building's level model
-- (ReplicatedStorage.BuildingModels.<Id>.Level<N>), found at any depth by name:
--   Door           where colonists enter; they path to it, then walk straight to spots inside
--   Bed, Bed2...   where residents sleep, one colonist per bed
--   Work, Work2... where workers stand while working, one worker per spot
--   StorageStand   where colonists stand to use the building's storage
--   StoragePrompt  the Storage ProximityPrompt
--   ManagePrompt   the building menu (Manage) ProximityPrompt
--   TeleportPrompt the Spire's Teleport ProximityPrompt
-- A numbered set is ordered by its number (no number = 1). The attachment's LookVector is the
-- way a colonist faces there. Every lookup returns nothing when the model has no such
-- attachment, so callers fall back to their computed spots.
const BuildingSpots = {}

-- Building-local CFrames (relative to the model's pivot) per "id_level_name"
const cache: { [string]: { CFrame } } = {}

local function getNumber(name: string, spot: string): number?
	if name == spot then
		return 1
	end
	if string.sub(name, 1, #spot) ~= spot then
		return nil
	end
	local suffix = string.sub(name, #spot + 1)
	return if string.match(suffix, "^%d+$") then tonumber(suffix) else nil
end

-- Every spot named `spot` (or `spot` + a number) in building-local space, in number order
function BuildingSpots.Get(id: BuildingId, level: number, spot: string): { CFrame }
	level = math.max(level, 1)
	local key = `{id}_{level}_{spot}`
	local cached = cache[key]
	if cached then
		return cached
	end

	local model = BuildingModels.Create(id, level)
	local pivot = model:GetPivot()
	local found: { { Number: number, CFrame: CFrame } } = {}
	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("Attachment") then
			continue
		end
		local number = getNumber(descendant.Name, spot)
		local part = descendant.Parent
		if not number or not part or not part:IsA("BasePart") then
			continue
		end
		-- Worked out from the part, as the model isn't in the workspace
		local world = part.CFrame * descendant.CFrame
		table.insert(found, { Number = number, CFrame = pivot:ToObjectSpace(world) })
	end
	model:Destroy()

	table.sort(found, function(a, b)
		return a.Number < b.Number
	end)
	local spots: { CFrame } = {}
	for _, entry in found do
		table.insert(spots, entry.CFrame)
	end
	cache[key] = spots
	return spots
end

-- Spot `index` of a numbered set (wrapping round when there are more users than spots)
function BuildingSpots.GetAt(id: BuildingId, level: number, spot: string, index: number): CFrame?
	local spots = BuildingSpots.Get(id, level, spot)
	if #spots == 0 then
		return nil
	end
	return spots[(math.max(index, 1) - 1) % #spots + 1]
end

return BuildingSpots
