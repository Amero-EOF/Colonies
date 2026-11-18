--!strict

const Debris = game:GetService("Debris")
const Lighting = game:GetService("Lighting")
const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")
const TweenService = game:GetService("TweenService")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const Net = require(Packages.Net)
const SpireData = require(Shared.Spire.SpireData)
const ColonyStore = require(script.Parent.ColonyStore)

type TravelInfo = SpireData.TravelInfo

const TRAVEL = SpireData.TRAVEL

const GLOW_COLOR = Color3.fromRGB(170, 120, 255)
const CORE_COLOR = Color3.fromRGB(235, 220, 255)
const DUST_COLOR = Color3.fromRGB(150, 135, 110)
const GLOW_FILL_TRANSPARENCY = 0.4
const GLOW_LIGHT_BRIGHTNESS = 6
const GLOW_LIGHT_RANGE = 40
const BEAM_GROW_TIME = 0.4
const BEAM_CORE_WIDTH = 0.3
const BEAM_CORE_TRANSPARENCY = 0.4
const BEAM_GLOW_TRANSPARENCY = 0.7
-- The arrival beam is thinner than the Spire's
const ARRIVAL_BEAM_WIDTH = 0.6
const GLOW_FADE_TIME = 0.5
const BLUR_SIZE = 18
const FLASH_IN_TIME = 0.1
const FLASH_OUT_TIME = 0.35
-- Studs the player hovers above where they started when the Spire model isn't drawn
const NO_SPIRE_HOVER = 20
-- R6 legs are 2 studs tall; R15 rigs count them in HipHeight
const R6_LEG_HEIGHT = 2
-- Glide to the ground when it streams in this far from where the brake ended
const SETTLE_MIN_GAP = 0.5
const SETTLE_TIME = 0.15
const GROUND_RAY_LENGTH = 600
const LANDING_RING_SIZE = 26
const LANDING_FX_TIME = 0.6
const DUST_COUNT = 40
const DUST_LIFETIME = 2
const SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

const player = Players.LocalPlayer

-- Plays the Spire travel sequence when the server sends "SpireTravel":
-- light up -> float to the Spire top -> launch -> teleport into the sky -> drop -> land
const SpireTravel = {}

-- The character being flown and everything to undo afterwards
type State = {
	Character: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	-- Facing kept for the whole trip (yaw only)
	Rotation: CFrame,
	-- Studs from the feet up to the root's centre
	RootHeight: number,
	Camera: Camera,
	BaseFov: number,
	Blur: BlurEffect,
	FlashGui: ScreenGui,
	Flash: Frame,
	-- Destroyed when the sequence ends; lingering effects go straight into workspace
	Effects: Folder,
	Tweens: { Tween },
}

local started = false
local busy = false

local function smoothstep(alpha: number): number
	return alpha * alpha * (3 - 2 * alpha)
end

local function easeIn(alpha: number): number
	return alpha * alpha * alpha
end

local function easeOut(alpha: number): number
	return 1 - (1 - alpha) * (1 - alpha)
end

local function play(
	state: State,
	instance: Instance,
	duration: number,
	goals: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
)
	local info = TweenInfo.new(
		duration,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out
	)
	local tween = TweenService:Create(instance, info, goals)
	table.insert(state.Tweens, tween)
	tween:Play()
end

local function setControlsEnabled(enabled: boolean)
	local playerScripts = player:FindFirstChildOfClass("PlayerScripts")
	local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if not playerModule or not playerModule:IsA("ModuleScript") then
		return
	end

	pcall(function()
		local controls = (require(playerModule) :: any):GetControls()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
end

local function isAlive(state: State): boolean
	return player.Character == state.Character
		and state.Root:IsDescendantOf(workspace)
		and state.Humanoid.Health > 0
end

-- Pins the root at a position (physics would otherwise pull it down between frames)
local function place(state: State, position: Vector3)
	state.Root.CFrame = state.Rotation + position
	state.Root.AssemblyLinearVelocity = Vector3.zero
	state.Root.AssemblyAngularVelocity = Vector3.zero
end

-- Holds the root on path(alpha) every physics step for `duration`; false if the character died
local function moveAlong(state: State, duration: number, path: (number) -> Vector3): boolean
	local startTime = os.clock()
	while true do
		if not isAlive(state) then
			return false
		end

		local alpha = if duration > 0 then math.min((os.clock() - startTime) / duration, 1) else 1
		place(state, path(alpha))
		if alpha >= 1 then
			return true
		end
		RunService.PreSimulation:Wait()
	end
end

local function hold(state: State, position: Vector3, duration: number): boolean
	return moveAlong(state, duration, function()
		return position
	end)
end

-- Root position standing on the ground under `position`, or nil if that ground hasn't streamed in
local function findLanding(state: State, position: Vector3): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { state.Character }
	params.RespectCanCollide = true

	local origin = position + Vector3.new(0, TRAVEL.SKY_HEIGHT, 0)
	local result = workspace:Raycast(origin, Vector3.new(0, -GROUND_RAY_LENGTH, 0), params)
	if not result then
		return nil
	end
	return Vector3.new(position.X, result.Position.Y + state.RootHeight, position.Z)
end

local function createFxPart(name: string, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Parent = parent
	return part
end

-- Cylinders run along X; this stands one up with its bottom at `base`
local function pillarCFrame(base: Vector3, height: number): CFrame
	return CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
end

local function createBeamPart(
	parent: Instance,
	base: Vector3,
	width: number,
	color: Color3,
	transparency: number
): Part
	local part = createFxPart("Beam", parent)
	part.Shape = Enum.PartType.Cylinder
	part.Color = color
	part.Transparency = transparency
	part.Size = Vector3.new(1, width, width)
	part.CFrame = pillarCFrame(base, 1)

	-- Shoots up into the sky from its base
	local info = TweenInfo.new(BEAM_GROW_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(part, info, {
		Size = Vector3.new(TRAVEL.BEAM_HEIGHT, width, width),
		CFrame = pillarCFrame(base, TRAVEL.BEAM_HEIGHT),
	}):Play()
	return part
end

-- A bright core inside a soft glow, rising from `base`
local function shootBeam(parent: Instance, base: Vector3, width: number): { Part }
	return {
		createBeamPart(parent, base, width * BEAM_CORE_WIDTH, CORE_COLOR, BEAM_CORE_TRANSPARENCY),
		createBeamPart(parent, base, width, GLOW_COLOR, BEAM_GLOW_TRANSPARENCY),
	}
end

local function fadeBeam(state: State, parts: { Part }, duration: number)
	for _, part in parts do
		play(state, part, duration, {
			Transparency = 1,
			Size = Vector3.new(TRAVEL.BEAM_HEIGHT, 0.1, 0.1),
		})
	end
end

-- Glow on the client-drawn Spire; returns the top middle of the model and the glow to fade later
local function lightUpSpire(state: State): (Vector3?, Highlight?, PointLight?)
	local model = ColonyStore.Models["Spire"]
	if not model or not model.Parent then
		return nil, nil, nil
	end

	local boxCFrame, size = model:GetBoundingBox()
	local top = boxCFrame.Position + Vector3.new(0, size.Y / 2, 0)

	local highlight = Instance.new("Highlight")
	highlight.Name = "SpireGlow"
	highlight.Adornee = model
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = GLOW_COLOR
	highlight.OutlineColor = CORE_COLOR
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Parent = state.Effects

	local lightPart = createFxPart("SpireLight", state.Effects)
	lightPart.Transparency = 1
	lightPart.Size = Vector3.one
	lightPart.CFrame = CFrame.new(top)

	local light = Instance.new("PointLight")
	light.Color = GLOW_COLOR
	light.Range = GLOW_LIGHT_RANGE
	light.Brightness = 0
	light.Parent = lightPart

	play(
		state,
		highlight,
		TRAVEL.LIGHT_UP_TIME,
		{ FillTransparency = GLOW_FILL_TRANSPARENCY, OutlineTransparency = 0 }
	)
	play(state, light, TRAVEL.LIGHT_UP_TIME, { Brightness = GLOW_LIGHT_BRIGHTNESS })
	return top, highlight, light
end

-- Dust burst and an expanding ring where the player touched down
local function landingEffect(feet: Vector3)
	local anchor = createFxPart("SpireLandingDust", workspace)
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 0.2, 1)
	anchor.CFrame = CFrame.new(feet)

	local dust = Instance.new("ParticleEmitter")
	dust.Texture = SMOKE_TEXTURE
	dust.Color = ColorSequence.new(DUST_COLOR)
	dust.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) })
	dust.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.6, 1)
	dust.Speed = NumberRange.new(14, 22)
	dust.SpreadAngle = Vector2.new(85, 85)
	dust.Drag = 5
	dust.Rate = 0
	dust.Parent = anchor
	dust:Emit(DUST_COUNT)
	Debris:AddItem(anchor, DUST_LIFETIME)

	local ring = createFxPart("SpireLandingRing", workspace)
	ring.Shape = Enum.PartType.Cylinder
	ring.Color = GLOW_COLOR
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.2, 2, 2)
	ring.CFrame = CFrame.new(feet) * CFrame.Angles(0, 0, math.pi / 2)
	TweenService
		:Create(
			ring,
			TweenInfo.new(LANDING_FX_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Size = Vector3.new(0.2, LANDING_RING_SIZE, LANDING_RING_SIZE),
				Transparency = 1,
			}
		)
		:Play()
	Debris:AddItem(ring, LANDING_FX_TIME)
end

-- Freezes the character (PlatformStand + no controls) and sets up the screen effects
local function begin(character: Model): State?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if
		not humanoid
		or not root
		or not root:IsA("BasePart")
		or humanoid.Health <= 0
		or not camera
		or not playerGui
	then
		return nil
	end

	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	local rotation = if look.Magnitude > 0.01
		then CFrame.lookAt(Vector3.zero, look)
		else CFrame.identity
	local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then R6_LEG_HEIGHT else 0

	local effects = Instance.new("Folder")
	effects.Name = "SpireTravelFX"
	effects.Parent = workspace

	local blur = Instance.new("BlurEffect")
	blur.Name = "SpireTravelBlur"
	blur.Size = 0
	blur.Parent = Lighting

	local flashGui = Instance.new("ScreenGui")
	flashGui.Name = "SpireTravelFlash"
	flashGui.IgnoreGuiInset = true
	flashGui.ResetOnSpawn = false
	flashGui.DisplayOrder = 100

	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BorderSizePixel = 0
	flash.BackgroundColor3 = CORE_COLOR
	flash.BackgroundTransparency = 1
	flash.Parent = flashGui
	flashGui.Parent = playerGui

	setControlsEnabled(false)
	humanoid.Sit = false
	humanoid.PlatformStand = true

	return {
		Character = character,
		Humanoid = humanoid,
		Root = root,
		Rotation = rotation,
		RootHeight = humanoid.HipHeight + root.Size.Y / 2 + legs,
		Camera = camera,
		BaseFov = camera.FieldOfView,
		Blur = blur,
		FlashGui = flashGui,
		Flash = flash,
		Effects = effects,
		Tweens = {},
	}
end

-- Undoes everything begin() did; safe after death or an error mid-sequence
local function finish(state: State)
	for _, tween in state.Tweens do
		tween:Cancel()
	end
	state.Camera.FieldOfView = state.BaseFov
	state.Blur:Destroy()
	state.FlashGui:Destroy()
	state.Effects:Destroy()

	if state.Humanoid.Parent then
		state.Root.AssemblyLinearVelocity = Vector3.zero
		state.Humanoid.PlatformStand = false
		if state.Humanoid.Health > 0 then
			state.Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
	setControlsEnabled(true)
end

-- The whole flight; returns false if the character died on the way
local function run(state: State, info: TravelInfo): boolean
	local start = state.Root.Position
	local lifted = start + Vector3.new(0, TRAVEL.LIFT_HEIGHT, 0)
	local launchFrom: Vector3
	local departBeam: { Part }
	local highlight: Highlight?, light: PointLight? = nil, nil

	if info.Kind == "Spire" then
		-- 1. Spire lights up, its beam shoots into the sky, the player lifts off
		local top: Vector3?
		top, highlight, light = lightUpSpire(state)
		local beamBase = top or (start - Vector3.new(0, state.RootHeight, 0))
		departBeam = shootBeam(state.Effects, beamBase, TRAVEL.BEAM_WIDTH)
		launchFrom = if top
			then top + Vector3.new(0, TRAVEL.FLOAT_CLEARANCE + state.RootHeight, 0)
			else start + Vector3.new(0, NO_SPIRE_HOVER, 0)

		local liftedOff = moveAlong(state, TRAVEL.LIGHT_UP_TIME, function(alpha)
			return start:Lerp(lifted, easeOut(alpha))
		end)
		if not liftedOff then
			return false
		end

		-- 2. Float to the top middle: rise first, then drift over so it arcs above the roof
		local floated = moveAlong(state, TRAVEL.FLOAT_TIME, function(alpha)
			local horizontal = lifted:Lerp(launchFrom, easeIn(alpha))
			local vertical = lifted.Y + (launchFrom.Y - lifted.Y) * smoothstep(math.sqrt(alpha))
			return Vector3.new(horizontal.X, vertical, horizontal.Z)
		end)
		if not floated then
			return false
		end
	else
		-- Return home: the beam rises from the player's feet instead
		departBeam =
			shootBeam(state.Effects, start - Vector3.new(0, state.RootHeight, 0), TRAVEL.BEAM_WIDTH)
		launchFrom = lifted
		local charged = moveAlong(state, TRAVEL.HOME_CHARGE_TIME, function(alpha)
			return start:Lerp(lifted, easeOut(alpha))
		end)
		if not charged then
			return false
		end
	end

	-- 3. Launch straight up, very fast, with an FOV kick and blur; a flash hides the cut
	local peak = launchFrom + Vector3.new(0, TRAVEL.LAUNCH_HEIGHT, 0)
	local launchStyle = Enum.EasingStyle.Cubic
	local inward = Enum.EasingDirection.In
	play(
		state,
		state.Camera,
		TRAVEL.LAUNCH_TIME,
		{ FieldOfView = state.BaseFov + TRAVEL.FOV_KICK },
		launchStyle,
		inward
	)
	play(state, state.Blur, TRAVEL.LAUNCH_TIME, { Size = BLUR_SIZE }, launchStyle, inward)
	fadeBeam(state, departBeam, TRAVEL.LAUNCH_TIME + GLOW_FADE_TIME)
	if highlight then
		play(state, highlight, GLOW_FADE_TIME, { FillTransparency = 1, OutlineTransparency = 1 })
	end
	if light then
		play(state, light, GLOW_FADE_TIME, { Brightness = 0 })
	end

	local launchStart = os.clock()
	local flashing = false
	local launched = moveAlong(state, TRAVEL.LAUNCH_TIME, function(alpha)
		if not flashing and os.clock() - launchStart >= TRAVEL.LAUNCH_TIME - FLASH_IN_TIME then
			flashing = true
			play(
				state,
				state.Flash,
				FLASH_IN_TIME,
				{ BackgroundTransparency = 0 },
				Enum.EasingStyle.Linear
			)
		end
		return launchFrom:Lerp(peak, easeIn(alpha))
	end)
	if not launched then
		return false
	end

	-- 4. Teleport into the sky above the landing spot (the server is streaming it in)
	local destination = info.Destination.Position
	local landing = findLanding(state, destination) or destination
	local sky = landing + Vector3.new(0, TRAVEL.SKY_HEIGHT, 0)
	state.Flash.BackgroundTransparency = 0
	if not hold(state, sky, 0) then
		return false
	end

	local arrivalBeam = shootBeam(
		workspace,
		landing - Vector3.new(0, state.RootHeight, 0),
		TRAVEL.BEAM_WIDTH * ARRIVAL_BEAM_WIDTH
	)
	for _, part in arrivalBeam do
		Debris:AddItem(
			part,
			TRAVEL.HANG_TIME + TRAVEL.DROP_TIME + TRAVEL.BRAKE_TIME + GLOW_FADE_TIME
		)
	end
	play(state, state.Flash, FLASH_OUT_TIME, { BackgroundTransparency = 1 })
	if not hold(state, sky, TRAVEL.HANG_TIME) then
		return false
	end

	-- 5. Drop fast, brake hard just above the ground, then settle onto it
	local settleTime = TRAVEL.DROP_TIME + TRAVEL.BRAKE_TIME
	play(state, state.Camera, settleTime, { FieldOfView = state.BaseFov })
	play(state, state.Blur, settleTime, { Size = 0 })
	for _, part in arrivalBeam do
		TweenService:Create(part, TweenInfo.new(settleTime + GLOW_FADE_TIME), { Transparency = 1 })
			:Play()
	end

	local brakeAt = landing + Vector3.new(0, TRAVEL.BRAKE_HEIGHT, 0)
	local dropped = moveAlong(state, TRAVEL.DROP_TIME, function(alpha)
		return sky:Lerp(brakeAt, alpha * alpha)
	end)
	if not dropped then
		return false
	end

	-- The ground may have streamed in during the drop
	landing = findLanding(state, destination) or landing
	local braked = moveAlong(state, TRAVEL.BRAKE_TIME, function(alpha)
		return brakeAt:Lerp(landing, easeOut(alpha))
	end)
	if not braked then
		return false
	end

	-- Hover until the ground exists so the player can't fall through the world
	local ground = findLanding(state, destination)
	local deadline = os.clock() + TRAVEL.GROUND_WAIT
	while not ground and os.clock() < deadline do
		if not hold(state, landing, 0) then
			return false
		end
		RunService.PreSimulation:Wait()
		ground = findLanding(state, destination)
	end

	if ground and math.abs(ground.Y - landing.Y) > SETTLE_MIN_GAP then
		local from = landing
		local target = ground
		local settled = moveAlong(state, SETTLE_TIME, function(alpha)
			return from:Lerp(target, easeOut(alpha))
		end)
		if not settled then
			return false
		end
		landing = target
	end

	landingEffect(landing - Vector3.new(0, state.RootHeight, 0))
	return true
end

local function travel(info: TravelInfo)
	local character = player.Character
	if busy or not character then
		return
	end

	local state = begin(character)
	if not state then
		return
	end

	busy = true
	local ok, result = pcall(run, state, info)
	finish(state)
	busy = false

	if not ok then
		warn(`SpireTravel failed: {result}`)
	elseif result then
		Net:RemoteEvent("SpireTravelDone"):FireServer(info.Token)
	end
end

function SpireTravel.Start()
	if started then
		return
	end
	started = true

	Net:Connect("SpireTravel", function(info: any)
		if
			type(info) ~= "table"
			or typeof(info.Destination) ~= "CFrame"
			or type(info.Token) ~= "number"
		then
			return
		end
		task.spawn(travel, info :: TravelInfo)
	end)
end

return SpireTravel
