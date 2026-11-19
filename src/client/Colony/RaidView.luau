--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const ColonistMotion = require(Shared.Colonist.ColonistMotion)
const PlotData = require(Shared.Plot.PlotData)
const RaidTypes = require(Shared.Raid.RaidTypes)
const RaidStore = require(script.Parent.RaidStore)

const effect = vide.effect

type RaiderInfo = RaidTypes.RaiderInfo

-- A blocky rig posed by hand every frame, like the colonists' (no Humanoid or animation assets)
type Rig = {
	Model: Model,
	Root: Part,
	Torso: Part,
	Head: Part,
	LeftArm: Part,
	RightArm: Part,
	LeftLeg: Part,
	RightLeg: Part,
	Club: Part,
	-- Sack on its back while it carries stolen items
	Sack: Part,
	Fill: Frame,
	Facing: Vector3,
	Phase: number,
}

const FOLDER_NAME = "Raiders"
const SKIN_COLOR = Color3.fromRGB(168, 190, 140)
const HOOD_COLOR = Color3.fromRGB(60, 30, 30)
const SHIRT_COLOR = Color3.fromRGB(110, 35, 35)
const PANTS_COLOR = Color3.fromRGB(45, 40, 40)
const CLUB_COLOR = Color3.fromRGB(95, 70, 50)
const SACK_COLOR = Color3.fromRGB(190, 165, 110)
const HIT_COLOR = Color3.fromRGB(255, 255, 255)
const HEALTH_COLOR = Color3.fromRGB(210, 60, 50)
const WALK_SWING = math.rad(40)
-- Seconds a raider flashes after the player hits it
const HIT_FLASH = 0.15

-- Draws the raiders on the local player's plot from RaidStore: workspace.MyColony.Raiders.Raider<Id>
const RaidView = {}

local started = false

local function makePart(model: Model, name: string, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	-- Every body part can be clicked to attack
	part.CanQuery = true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local function createRig(raider: RaiderInfo, folder: Instance): Rig
	local model = Instance.new("Model")
	model.Name = `Raider{raider.Id}`
	model:SetAttribute("RaiderId", raider.Id)

	local root = makePart(model, "HumanoidRootPart", Vector3.new(2, 2, 1), SHIRT_COLOR)
	root.Transparency = 1
	root.CanQuery = false
	model.PrimaryPart = root

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Health"
	billboard.Size = UDim2.fromOffset(70, 10)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
	billboard.MaxDistance = 120
	billboard.AlwaysOnTop = true

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.fromScale(1, 1)
	bar.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	bar.BorderSizePixel = 0
	bar.Parent = billboard

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = HEALTH_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = bar

	local rig: Rig = {
		Model = model,
		Root = root,
		Torso = makePart(model, "Torso", Vector3.new(2, 2, 1), SHIRT_COLOR),
		Head = makePart(model, "Head", Vector3.new(1.2, 1.2, 1.2), SKIN_COLOR),
		LeftArm = makePart(model, "LeftArm", Vector3.new(1, 2, 1), SKIN_COLOR),
		RightArm = makePart(model, "RightArm", Vector3.new(1, 2, 1), SKIN_COLOR),
		LeftLeg = makePart(model, "LeftLeg", Vector3.new(1, 2, 1), PANTS_COLOR),
		RightLeg = makePart(model, "RightLeg", Vector3.new(1, 2, 1), PANTS_COLOR),
		Club = makePart(model, "Club", Vector3.new(0.5, 0.5, 2.6), CLUB_COLOR),
		Sack = makePart(model, "Sack", Vector3.new(1.6, 1.8, 1), SACK_COLOR),
		Fill = fill,
		Facing = Vector3.new(0, 0, -1),
		Phase = raider.Id * 1.7,
	}
	rig.Head.Color = HOOD_COLOR
	rig.Sack.Transparency = 1
	rig.Sack.CanQuery = false

	billboard.Adornee = rig.Head
	billboard.Parent = rig.Head

	model.Parent = folder
	return rig
end

-- Limb angles (radians, around each limb's shoulder/hip X axis) for an action
local function getPose(
	action: string,
	walking: boolean,
	t: number
): (number, number, number, number)
	-- leftArm, rightArm, leftLeg, rightLeg
	if walking then
		local swing = math.sin(t * 9) * WALK_SWING
		-- The club arm stays raised while it runs
		return swing, -math.rad(60), -swing, swing
	elseif action == "Attack" then
		-- Winds up overhead and chops down
		local chop = -math.rad(150) + math.abs(math.sin(t * 5)) * math.rad(110)
		return math.rad(-15), chop, 0, 0
	elseif action == "Work" then
		-- Rummaging through the storage with both hands
		local dig = math.sin(t * 7) * math.rad(25)
		return -math.rad(70) + dig, -math.rad(70) - dig, 0, 0
	end
	local breathe = math.sin(t * 1.5) * math.rad(3)
	return breathe, -math.rad(20) - breathe, 0, 0
end

local function limb(base: CFrame, offset: Vector3, angle: number, length: number): CFrame
	-- Pivot at the top of the limb
	return base * CFrame.new(offset) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, -length / 2, 0)
end

local function poseRig(
	rig: Rig,
	motion: RaidTypes.Motion,
	now: number,
	parts: { BasePart },
	cframes: { CFrame }
)
	local position, facing, finished = ColonistMotion.Evaluate(motion, now)
	if facing.Magnitude > 0.01 then
		rig.Facing = facing
	end
	local walking = not finished and motion.Speed > 0
	local t = now + rig.Phase

	local world = PlotData.SURFACE * position
	local base = CFrame.lookAt(world, world + rig.Facing)
	local torso = base * CFrame.new(0, 3, 0)
	local leftArm, rightArm, leftLeg, rightLeg = getPose(motion.Action, walking, t)
	local rightArmCFrame = limb(torso, Vector3.new(1.5, 1, 0), rightArm, 2)

	table.insert(parts, rig.Root)
	table.insert(cframes, torso)
	table.insert(parts, rig.Torso)
	table.insert(cframes, torso)
	table.insert(parts, rig.Head)
	table.insert(cframes, torso * CFrame.new(0, 1.6, 0))
	table.insert(parts, rig.LeftArm)
	table.insert(cframes, limb(torso, Vector3.new(-1.5, 1, 0), leftArm, 2))
	table.insert(parts, rig.RightArm)
	table.insert(cframes, rightArmCFrame)
	table.insert(parts, rig.LeftLeg)
	table.insert(cframes, limb(torso, Vector3.new(-0.5, -1, 0), leftLeg, 2))
	table.insert(parts, rig.RightLeg)
	table.insert(cframes, limb(torso, Vector3.new(0.5, -1, 0), rightLeg, 2))
	-- Held in the right hand, sticking out past the fist
	table.insert(parts, rig.Club)
	table.insert(cframes, rightArmCFrame * CFrame.new(0, -1, -1))
	table.insert(parts, rig.Sack)
	table.insert(cframes, torso * CFrame.new(0, 0.2, 1))
end

local function setColor(rig: Rig, hit: boolean)
	rig.Torso.Color = if hit then HIT_COLOR else SHIRT_COLOR
	rig.Head.Color = if hit then HIT_COLOR else HOOD_COLOR
end

function RaidView.Start()
	if started then
		return
	end
	started = true

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = workspace:FindFirstChild("MyColony") or workspace

	local rigs: { [number]: Rig } = {}
	-- Raiders currently drawn white (just hit)
	local flashing: { [number]: boolean } = {}

	vide.root(function()
		effect(function()
			local alive: { [number]: boolean } = {}
			if RaidStore.Active() then
				for _, raider in RaidStore.Raiders() do
					alive[raider.Id] = true
					local rig = rigs[raider.Id]
					if not rig then
						rig = createRig(raider, folder)
						rigs[raider.Id] = rig
					end
					local share = if raider.MaxHealth > 0
						then math.clamp(raider.Health / raider.MaxHealth, 0, 1)
						else 0
					rig.Fill.Size = UDim2.fromScale(share, 1)
					rig.Sack.Transparency = if raider.Carrying then 0 else 1
				end
			end
			for id, rig in rigs do
				if not alive[id] then
					rig.Model:Destroy()
					rigs[id] = nil
					flashing[id] = nil
					RaidStore.Motions[id] = nil
					RaidStore.Hits[id] = nil
				end
			end
		end)
	end)

	RunService.RenderStepped:Connect(function()
		if next(rigs) == nil then
			return
		end
		local now = workspace:GetServerTimeNow()
		local clock = os.clock()
		local parts: { BasePart } = {}
		local cframes: { CFrame } = {}
		for id, rig in rigs do
			local motion = RaidStore.Motions[id]
			if motion then
				poseRig(rig, motion, now, parts, cframes)
			end
			local hitAt = RaidStore.Hits[id]
			local hit = hitAt ~= nil and clock - hitAt < HIT_FLASH
			if hit ~= (flashing[id] or false) then
				flashing[id] = hit
				setColor(rig, hit)
			end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

return RaidView
