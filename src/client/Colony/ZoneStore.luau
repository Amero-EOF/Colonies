--!strict

const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const PlotData = require(Shared.Plot.PlotData)
const WildAreaData = require(Shared.Wilds.WildAreaData)

const source = vide.source

-- "Colony" for the player's plot, else a wild area's id
export type ZoneId = "Colony" | WildAreaData.WildAreaId

type Bounds = {
	Min: Vector3,
	Max: Vector3,
	-- Ground parts these bounds were measured from (streaming may add more)
	Count: number,
}

const POLL_INTERVAL = 0.25
-- Studs past a wild area's ground edge that still count as inside it
const WILD_MARGIN = 40
-- Studs above the ground still inside a zone (jumping, standing on buildings)
const ZONE_HEIGHT = 500

const player = Players.LocalPlayer

-- Which zone the local character stands in; nil when between zones
const ZoneStore = {
	Zone = source(nil :: ZoneId?),
}

const boundsCache: { [string]: Bounds } = {}
local started = false

-- World-space box around every part in a wild area's Ground folder
local function measure(ground: Instance): Bounds?
	local min, max = nil :: Vector3?, nil :: Vector3?
	local count = 0
	for _, part in ground:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		count += 1
		local cf = part.CFrame
		local half = part.Size / 2
		-- Rotated parts: project the half size onto each world axis
		local extent = Vector3.new(
			math.abs(cf.XVector.X) * half.X
				+ math.abs(cf.YVector.X) * half.Y
				+ math.abs(cf.ZVector.X) * half.Z,
			math.abs(cf.XVector.Y) * half.X
				+ math.abs(cf.YVector.Y) * half.Y
				+ math.abs(cf.ZVector.Y) * half.Z,
			math.abs(cf.XVector.Z) * half.X
				+ math.abs(cf.YVector.Z) * half.Y
				+ math.abs(cf.ZVector.Z) * half.Z
		)
		local low, high = cf.Position - extent, cf.Position + extent
		min = if min then min:Min(low) else low
		max = if max then max:Max(high) else high
	end
	if not min or not max then
		return nil
	end
	return { Min = min, Max = max, Count = count }
end

local function getBounds(id: string): Bounds?
	local wilds = workspace:FindFirstChild("Wilds")
	local area = wilds and wilds:FindFirstChild(id)
	local ground = area and area:FindFirstChild("Ground")
	if not ground then
		return boundsCache[id]
	end

	-- Re-measure only when streaming added or removed ground parts
	local cached = boundsCache[id]
	if cached and cached.Count == #ground:GetChildren() then
		return cached
	end
	local bounds = measure(ground)
	if bounds then
		boundsCache[id] = bounds
	end
	return bounds or cached
end

local function isInsideBounds(position: Vector3, bounds: Bounds): boolean
	return position.X >= bounds.Min.X - WILD_MARGIN
		and position.X <= bounds.Max.X + WILD_MARGIN
		and position.Z >= bounds.Min.Z - WILD_MARGIN
		and position.Z <= bounds.Max.Z + WILD_MARGIN
		and position.Y >= bounds.Min.Y - WILD_MARGIN
		and position.Y <= bounds.Max.Y + ZONE_HEIGHT
end

-- The zone containing a world position
function ZoneStore.Detect(position: Vector3): ZoneId?
	local level = player:GetAttribute("TownHallLevel")
	local height = PlotData.SURFACE:PointToObjectSpace(position).Y
	if
		PlotData.IsInside(position, if typeof(level) == "number" then level else 0)
		and math.abs(height) <= ZONE_HEIGHT
	then
		return "Colony"
	end

	for _, area in WildAreaData.AREAS do
		local bounds = getBounds(area.Id)
		if bounds and isInsideBounds(position, bounds) then
			return area.Id
		end
	end
	return nil
end

-- Polls the character's position and updates Zone when it changes
function ZoneStore.Start()
	if started then
		return
	end
	started = true

	task.spawn(function()
		while true do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			-- Keep the last zone while respawning so it doesn't flash nil
			if root and root:IsA("BasePart") then
				local zone = ZoneStore.Detect(root.Position)
				if zone ~= ZoneStore.Zone() then
					ZoneStore.Zone(zone)
				end
			end
			task.wait(POLL_INTERVAL)
		end
	end)
end

return ZoneStore
