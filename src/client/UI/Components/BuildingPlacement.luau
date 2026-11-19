--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")
const UserInputService = game:GetService("UserInputService")

const Shared = ReplicatedStorage.Shared
const Packages = ReplicatedStorage.Packages

const vide = require(Packages.vide)
const Net = require(Packages.Net)
const BuildingModels = require(Shared.Buildings.BuildingModels)
const BuildingPlacement = require(Shared.Buildings.BuildingPlacement)
const BuildingTypes = require(Shared.Buildings.BuildingTypes)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const PlotData = require(Shared.Plot.PlotData)
const ColonyStore = require(script.Parent.Parent.Parent.Colony.ColonyStore)

const source = vide.source
const spring = vide.spring
const effect = vide.effect
const cleanup = vide.cleanup

type BuildingId = BuildingTypes.BuildingId
type Placement = ColonyTypes.Placement

type Obstacle = BuildingPlacement.Obstacle

type Props = {
	Id: BuildingId,
	Level: number,
	-- Current plot side length
	PlotSize: number,
	OnPlaced: () -> (),
	-- The already-placed model when moving: it turns into the ghost and the preview stays solid
	Original: Model?,
}

const GHOST_TRANSPARENCY = 0.5
const SPRING_PERIOD = 0.2
const RAY_LENGTH = 5000
const BLOCKED_COLOR = Color3.fromRGB(255, 60, 60)
const REACH_COLOR = Color3.fromRGB(255, 255, 255)
const REACH_HEIGHT = 0.2
const REACH_LIFT = 0.15

-- Makes a model's parts see-through locally and returns a function that restores them
local function ghostify(model: Model): () -> ()
	local saved: { [BasePart]: number } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			saved[descendant] = descendant.Transparency
			descendant.Transparency = math.max(descendant.Transparency, GHOST_TRANSPARENCY)
		end
	end

	return function()
		for part, transparency in saved do
			part.Transparency = transparency
		end
	end
end

-- Preview that follows the mouse on the player's plot: click to place, R to rotate 90 degrees
local function BuildingPlacementGhost(props: Props)
	local plot = workspace:WaitForChild("MyColony"):WaitForChild("Plot") :: BasePart
	local plotSize = props.PlotSize
	-- The ground the building can ever grow into: placing keeps all of it free
	local reachSize, reachCentre = BuildingPlacement.GetReach(props.Id, props.Level)
	local original = props.Original

	local ghost = BuildingModels.Create(props.Id, props.Level)
	for _, descendant in ghost:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
		end
	end

	local restoreOriginal: (() -> ())? = nil
	local startX, startZ, rotation = 0, 0, 0
	if original then
		restoreOriginal = ghostify(original)

		-- Start the preview where the original stands
		local start = BuildingPlacement.FromCFrame(original:GetPivot())
		startX, startZ, rotation = start.X, start.Z, start.Rotation
	else
		ghostify(ghost)
	end
	ghost.Parent = workspace

	local placement = source(
		BuildingPlacement.Resolve(plotSize, reachSize, startX, startZ, rotation, reachCentre)
	)
	local busy = false

	-- Other buildings on the plot the preview can't overlap
	-- (including the ground their ordered upgrades will grow into)
	-- (and the ground they could grow into at their biggest level)
	local obstacles: { Obstacle } = BuildingPlacement.GetObstacles(
		ColonyStore.Buildings(),
		ColonyStore.WorkOrders(),
		props.Id,
		true
	)

	local blocked = function(): boolean
		local current = BuildingPlacement.GetReachPlacement(props.Id, props.Level, placement())
		for _, obstacle in obstacles do
			if
				BuildingPlacement.Overlaps(
					current,
					reachSize,
					obstacle.Placement,
					obstacle.Footprint
				)
			then
				return true
			end
		end
		return false
	end

	-- Flat box outlining the building's full reach on the ground
	local reach = Instance.new("Part")
	reach.Name = "PlacementReach"
	reach.Anchored = true
	reach.CanCollide = false
	reach.CanQuery = false
	reach.CanTouch = false
	reach.CastShadow = false
	reach.Transparency = 1
	reach.Size = Vector3.new(reachSize.X, REACH_HEIGHT, reachSize.Y)
	reach.Parent = workspace

	local outline = Instance.new("SelectionBox")
	outline.Adornee = reach
	outline.LineThickness = 0.15
	outline.SurfaceTransparency = 0.85
	outline.Parent = reach

	local highlight = Instance.new("Highlight")
	highlight.FillColor = BLOCKED_COLOR
	highlight.OutlineColor = BLOCKED_COLOR
	highlight.FillTransparency = 0.4
	highlight.Parent = ghost

	effect(function()
		local isBlocked = blocked()
		highlight.Enabled = isBlocked
		outline.Color3 = if isBlocked then BLOCKED_COLOR else REACH_COLOR
		outline.SurfaceColor3 = outline.Color3
	end)

	-- Position and yaw spring separately: springing a whole CFrame goes through Euler XYZ
	-- angles, which tumbles the ghost on X/Z when a Y turn passes 90 degrees
	local turns = source(rotation) -- quarter turns, never wrapped so 3 -> 4 keeps spinning forward
	local animatedPosition = spring(function()
		return BuildingPlacement.ToCFrame(placement()).Position
	end, SPRING_PERIOD)
	local animatedYaw = spring(function()
		return turns() * math.pi / 2
	end, SPRING_PERIOD)
	ghost:PivotTo(BuildingPlacement.ToCFrame(placement()))

	effect(function()
		ghost:PivotTo(
			CFrame.new(animatedPosition())
				* PlotData.SURFACE.Rotation
				* CFrame.Angles(0, animatedYaw(), 0)
		)
		reach.CFrame = ghost:GetPivot()
			* CFrame.new(reachCentre.X, REACH_HEIGHT / 2 + REACH_LIFT, reachCentre.Z)
	end)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { plot }

	local function update()
		local camera = workspace.CurrentCamera
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local result = workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, raycastParams)
		if not result then
			return
		end

		local localPosition = PlotData.SURFACE:PointToObjectSpace(result.Position)
		local resolved = BuildingPlacement.Resolve(
			plotSize,
			reachSize,
			localPosition.X,
			localPosition.Z,
			rotation,
			reachCentre
		)
		local current = placement()
		if
			resolved.X ~= current.X
			or resolved.Z ~= current.Z
			or resolved.Rotation ~= current.Rotation
		then
			placement(resolved)
		end
	end

	local function place()
		if busy or blocked() then
			return
		end
		busy = true

		local chosen = placement()
		task.spawn(function()
			local placed =
				Net:Invoke("PlaceBuilding", props.Id, chosen.X, chosen.Z, chosen.Rotation)
			busy = false
			if placed then
				props.OnPlaced()
			end
		end)
	end

	local connections = {
		RunService.RenderStepped:Connect(update),
		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end

			if input.KeyCode == Enum.KeyCode.R then
				rotation = (rotation + 1) % 4
				turns(turns() + 1)
				update()
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				place()
			end
		end),
	}

	cleanup(function()
		for _, connection in connections do
			connection:Disconnect()
		end
		ghost:Destroy()
		reach:Destroy()
		if restoreOriginal then
			restoreOriginal()
		end
	end)

	return ghost
end

return BuildingPlacementGhost
