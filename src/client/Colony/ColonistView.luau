--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const ColonistMotion = require(Shared.Colonist.ColonistMotion)
const ColonistTypes = require(Shared.Colonist.ColonistTypes)
const PlotData = require(Shared.Plot.PlotData)
const ColonistStore = require(script.Parent.ColonistStore)

const effect = vide.effect

type Colonist = ColonistTypes.Colonist

-- A blocky rig the client poses by hand every frame (no Humanoid or animation assets)
type Rig = {
	Model: Model,
	Root: Part,
	Torso: Part,
	Head: Part,
	LeftArm: Part,
	RightArm: Part,
	LeftLeg: Part,
	RightLeg: Part,
	Label: TextLabel,
	Prompt: ProximityPrompt,
	StatsPrompt: ProximityPrompt,
	-- Yellow "!" shown while the colonist has a quest
	QuestMarker: BillboardGui,
	Scale: number,
	Facing: Vector3,
	Phase: number,
}

const SKIN_COLORS = {
	Color3.fromRGB(255, 220, 177),
	Color3.fromRGB(229, 184, 143),
	Color3.fromRGB(198, 134, 66),
	Color3.fromRGB(141, 85, 36),
}
const JOB_COLORS: { [string]: Color3 } = {
	Builder = Color3.fromRGB(214, 160, 60),
}
const SHIRT_COLOR = Color3.fromRGB(120, 140, 170)
const CHILD_SCALE = 0.7
const PROMPT_REACH = 10
const QUEST_COLOR = Color3.fromRGB(255, 205, 40)
const WALK_SWING = math.rad(35)

const ColonistView = {}

local started = false

local function makePart(model: Model, name: string, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = name == "Torso"
	part.CanTouch = false
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local function createRig(colonist: Colonist, folder: Folder): Rig
	local scale = if colonist.Age == "Child" then CHILD_SCALE else 1
	local skin = SKIN_COLORS[(colonist.Id % #SKIN_COLORS) + 1]
	local shirt = JOB_COLORS[colonist.Job or ""] or SHIRT_COLOR
	local pants = Color3.fromRGB(70, 60, 50)

	local model = Instance.new("Model")
	model.Name = colonist.Name
	model:SetAttribute("ColonistId", colonist.Id)

	local root = makePart(model, "HumanoidRootPart", Vector3.new(2, 2, 1) * scale, skin)
	root.Transparency = 1
	model.PrimaryPart = root

	local rig: Rig = {
		Model = model,
		Root = root,
		Torso = makePart(model, "Torso", Vector3.new(2, 2, 1) * scale, shirt),
		Head = makePart(model, "Head", Vector3.new(1.2, 1.2, 1.2) * scale, skin),
		LeftArm = makePart(model, "LeftArm", Vector3.new(1, 2, 1) * scale, shirt),
		RightArm = makePart(model, "RightArm", Vector3.new(1, 2, 1) * scale, shirt),
		LeftLeg = makePart(model, "LeftLeg", Vector3.new(1, 2, 1) * scale, pants),
		RightLeg = makePart(model, "RightLeg", Vector3.new(1, 2, 1) * scale, pants),
		Label = Instance.new("TextLabel"),
		Prompt = Instance.new("ProximityPrompt"),
		StatsPrompt = Instance.new("ProximityPrompt"),
		QuestMarker = Instance.new("BillboardGui"),
		Scale = scale,
		Facing = Vector3.new(0, 0, -1),
		Phase = colonist.Id * 1.7,
	}

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(200, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.5 * scale, 0)
	billboard.MaxDistance = 60
	billboard.AlwaysOnTop = false
	billboard.Adornee = rig.Head
	billboard.Parent = rig.Head
	local label = rig.Label
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.5
	label.TextSize = 14
	label.Font = Enum.Font.GothamMedium
	label.Parent = billboard

	local marker = rig.QuestMarker
	marker.Name = "QuestMarker"
	marker.Size = UDim2.fromOffset(40, 50)
	marker.StudsOffsetWorldSpace = Vector3.new(0, 4.2 * scale, 0)
	marker.MaxDistance = 120
	marker.Enabled = colonist.Quest ~= nil
	marker.Adornee = rig.Head
	marker.Parent = rig.Head
	local mark = Instance.new("TextLabel")
	mark.Size = UDim2.fromScale(1, 1)
	mark.BackgroundTransparency = 1
	mark.Text = "!"
	mark.TextScaled = true
	mark.Font = Enum.Font.GothamBlack
	mark.TextColor3 = QUEST_COLOR
	mark.TextStrokeTransparency = 0
	mark.TextStrokeColor3 = Color3.fromRGB(60, 40, 0)
	mark.Parent = marker

	local prompt = rig.Prompt
	prompt.ActionText = "Talk"
	prompt.ObjectText = colonist.Name
	prompt.HoldDuration = 0
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = PROMPT_REACH
	prompt.Parent = rig.Torso

	-- Straight to the stats menu, skipping the conversation
	local statsPrompt = rig.StatsPrompt
	statsPrompt.ActionText = "Stats"
	statsPrompt.ObjectText = colonist.Name
	statsPrompt.HoldDuration = 0
	statsPrompt.KeyboardKeyCode = Enum.KeyCode.F
	statsPrompt.RequiresLineOfSight = false
	statsPrompt.MaxActivationDistance = PROMPT_REACH
	statsPrompt.UIOffset = Vector2.new(0, 72)
	statsPrompt.Parent = rig.Torso

	local id = colonist.Id
	prompt.Triggered:Connect(function()
		ColonistStore.Talk(id)
	end)
	statsPrompt.Triggered:Connect(function()
		ColonistStore.SelectedId(id)
	end)
	-- Walking away closes the conversation and the menus
	prompt.PromptHidden:Connect(function()
		task.defer(function()
			if not prompt.Parent then
				return
			end
			local open = ColonistStore.Dialogue()
			if open and open.Id == id then
				ColonistStore.EndTalk()
			end
			if ColonistStore.SelectedId() == id then
				ColonistStore.SelectedId(nil)
				ColonistStore.FamilyTreeId(nil)
			end
		end)
	end)

	model.Parent = folder
	return rig
end

-- Limb angles (radians, around each limb's shoulder/hip X axis) for an action
local function getPose(
	action: string,
	walking: boolean,
	t: number
): (number, number, number, number, number)
	-- leftArm, rightArm, leftLeg, rightLeg, headPitch
	if walking then
		local swing = math.sin(t * 8) * WALK_SWING
		return swing, -swing, -swing, swing, 0
	elseif action == "Build" or action == "Work" then
		local hammer = -math.rad(70) - math.abs(math.sin(t * 6)) * math.rad(50)
		return math.rad(-10), hammer, 0, 0, math.rad(-10)
	elseif action == "Eat" then
		local bite = -math.rad(110) + math.sin(t * 4) * math.rad(15)
		return 0, bite, 0, 0, 0
	elseif action == "Mourn" then
		return math.rad(-20), math.rad(-20), 0, 0, math.rad(-35)
	end
	local breathe = math.sin(t * 1.5) * math.rad(3)
	return breathe, -breathe, 0, 0, 0
end

local function limb(base: CFrame, offset: Vector3, angle: number, length: number): CFrame
	-- Pivot at the top of the limb
	return base * CFrame.new(offset) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, -length / 2, 0)
end

local function poseRig(
	rig: Rig,
	motion: ColonistTypes.Motion,
	now: number,
	parts: { BasePart },
	cframes: { CFrame }
)
	local position, facing, finished = ColonistMotion.Evaluate(motion, now)
	if facing.Magnitude > 0.01 then
		rig.Facing = facing
	end
	local s = rig.Scale
	local walking = not finished and motion.Speed > 0
	local t = now + rig.Phase

	local world = PlotData.SURFACE * position
	local hipHeight = 2 * s
	local base = CFrame.lookAt(world, world + rig.Facing)
	local torso = base * CFrame.new(0, hipHeight + s, 0)
	if motion.Action == "Sleep" and not walking then
		-- Lie on the ground beside the door
		torso = base * CFrame.new(0, 0.5 * s, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
	end

	local leftArm, rightArm, leftLeg, rightLeg, headPitch =
		getPose(if walking then "Idle" else motion.Action, walking, t)
	if motion.Action == "Sleep" and not walking then
		leftArm, rightArm, leftLeg, rightLeg, headPitch = 0, 0, 0, 0, 0
	end

	table.insert(parts, rig.Root)
	table.insert(cframes, torso)
	table.insert(parts, rig.Torso)
	table.insert(cframes, torso)
	table.insert(parts, rig.Head)
	table.insert(cframes, torso * CFrame.new(0, 1.6 * s, 0) * CFrame.Angles(headPitch, 0, 0))
	table.insert(parts, rig.LeftArm)
	table.insert(cframes, limb(torso, Vector3.new(-1.5 * s, s, 0), leftArm, 2 * s))
	table.insert(parts, rig.RightArm)
	table.insert(cframes, limb(torso, Vector3.new(1.5 * s, s, 0), rightArm, 2 * s))
	table.insert(parts, rig.LeftLeg)
	table.insert(cframes, limb(torso, Vector3.new(-0.5 * s, -s, 0), leftLeg, 2 * s))
	table.insert(parts, rig.RightLeg)
	table.insert(cframes, limb(torso, Vector3.new(0.5 * s, -s, 0), rightLeg, 2 * s))
end

function ColonistView.Start()
	if started then
		return
	end
	started = true

	local folder = Instance.new("Folder")
	folder.Name = "MyColonists"
	folder.Parent = workspace

	local rigs: { [number]: Rig } = {}
	-- Rebuilt when age or job changes (size and shirt colour)
	local looks: { [number]: string } = {}

	vide.root(function()
		effect(function()
			local alive: { [number]: boolean } = {}
			for _, colonist in ColonistStore.Colonists() do
				alive[colonist.Id] = true
				local look = `{colonist.Age}:{colonist.Job or ""}`
				local rig = rigs[colonist.Id]
				if rig and looks[colonist.Id] ~= look then
					rig.Model:Destroy()
					rigs[colonist.Id] = nil
				end
				if not rigs[colonist.Id] then
					rigs[colonist.Id] = createRig(colonist, folder)
					looks[colonist.Id] = look
				end
			end
			for id, rig in rigs do
				if not alive[id] then
					rig.Model:Destroy()
					rigs[id] = nil
					looks[id] = nil
					ColonistStore.Motions[id] = nil
				end
			end
		end)

		effect(function()
			local status = ColonistStore.Status()
			for _, colonist in ColonistStore.Colonists() do
				local rig = rigs[colonist.Id]
				if rig then
					rig.QuestMarker.Enabled = colonist.Quest ~= nil
					local line = status[tostring(colonist.Id)]
					rig.Label.Text = if line and line ~= ""
						then `{colonist.Name}\n{line}`
						else colonist.Name
				end
			end
		end)
	end)

	RunService.RenderStepped:Connect(function()
		local now = workspace:GetServerTimeNow()
		local parts: { BasePart } = {}
		local cframes: { CFrame } = {}
		for id, rig in rigs do
			local motion = ColonistStore.Motions[id]
			if motion then
				poseRig(rig, motion, now, parts, cframes)
			end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

return ColonistView
