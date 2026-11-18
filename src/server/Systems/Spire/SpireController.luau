--!strict

const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared
const Systems = script.Parent.Parent

const Net = require(Packages.Net)
const BuildingUnlocks = require(Shared.Buildings.BuildingUnlocks)
const PlotData = require(Shared.Plot.PlotData)
const SpireData = require(Shared.Spire.SpireData)
const WildAreaData = require(Shared.Wilds.WildAreaData)
const ColonyController = require(Systems.Colony.ColonyController)

type WildAreaInfo = WildAreaData.WildAreaInfo
type TravelKind = SpireData.TravelKind
type TravelInfo = SpireData.TravelInfo

-- A running travel sequence; the client moves the character, the server checks it arrived
type Travel = {
	Token: number,
	Kind: TravelKind,
	Character: Model,
	Destination: CFrame,
	StartTime: number,
	Finishing: boolean,
}

const ARRIVAL_HEIGHT = 4
-- Keep arrivals this far from the area's edge and from resource nodes
const EDGE_MARGIN = 32
const NODE_CLEARANCE = 10
const ARRIVAL_ATTEMPTS = 20
-- Seconds to let the landed position replicate before checking it
const ARRIVAL_CHECK_DELAY = 0.5
-- A "done" this many seconds before the sequence could finish is ignored
const EARLY_DONE_SLACK = 0.5

const TRAVEL = SpireData.TRAVEL

const SpireController = {}

-- Each player's running travel, so a newer one can't be finished by an old timer
const travels: { [Player]: Travel } = {}
-- Server time when each player can teleport again
const readyTimes: { [Player]: number } = {}
local nextToken = 0
local started = false

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- A random clear spot on the area's ground, or nil if the area isn't built
local function getRandomArrival(area: WildAreaInfo): CFrame?
	local wilds = workspace:FindFirstChild("Wilds")
	local areaFolder = wilds and wilds:FindFirstChild(area.Id)
	local ground = areaFolder and areaFolder:FindFirstChild("Ground")
	if not ground then
		return nil
	end

	local parts = {}
	for _, part in ground:GetChildren() do
		if part:IsA("BasePart") then
			table.insert(parts, part)
		end
	end
	if #parts == 0 then
		return nil
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { wilds and wilds:FindFirstChild("Nodes") or {} }

	local fallback: CFrame? = nil
	for _ = 1, ARRIVAL_ATTEMPTS do
		local part = parts[math.random(#parts)]
		local halfX = math.max(part.Size.X / 2 - EDGE_MARGIN, 0)
		local halfZ = math.max(part.Size.Z / 2 - EDGE_MARGIN, 0)
		local x = (math.random() * 2 - 1) * halfX
		local z = (math.random() * 2 - 1) * halfZ
		local cframe = part.CFrame * CFrame.new(x, part.Size.Y / 2 + ARRIVAL_HEIGHT, z)
		fallback = fallback or cframe

		if
			#workspace:GetPartBoundsInRadius(cframe.Position, NODE_CLEARANCE, overlapParams) == 0
		then
			return cframe
		end
	end

	return fallback
end

-- Ends a travel; the cooldown only starts if the player actually got there
local function finishTravel(player: Player, travel: Travel, arrived: boolean)
	if travels[player] ~= travel then
		return
	end
	travels[player] = nil
	player:SetAttribute("TeleportChannelEnd", nil)
	player:SetAttribute("TeleportChannelTime", nil)

	if arrived then
		local nextReady = workspace:GetServerTimeNow() + SpireData.COOLDOWN
		readyTimes[player] = nextReady
		player:SetAttribute("TeleportReadyAt", nextReady)
	end
end

-- Puts the character at the destination if the client didn't get it there.
-- Returns false when the travelling character is gone (died or reset).
local function settleArrival(player: Player, travel: Travel): boolean
	local character = player.Character
	local root = getRoot(player)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character ~= travel.Character or not root or not humanoid or humanoid.Health <= 0 then
		return false
	end

	if (root.Position - travel.Destination.Position).Magnitude > TRAVEL.ARRIVAL_TOLERANCE then
		root.AssemblyLinearVelocity = Vector3.zero
		travel.Character:PivotTo(travel.Destination)
	end
	return true
end

local function checkArrival(player: Player, travel: Travel)
	if travels[player] == travel then
		finishTravel(player, travel, settleArrival(player, travel))
	end
end

-- Server picks and streams the destination; the owner's client plays the sequence and moves
-- its character (it owns the physics). If the client never reports back, the server moves it.
local function startTravel(
	player: Player,
	kind: TravelKind,
	destination: CFrame?
): (boolean, string)
	local now = workspace:GetServerTimeNow()
	if travels[player] then
		return false, "Already teleporting"
	end

	local readyAt = readyTimes[player]
	if readyAt and now < readyAt then
		return false, `Ready in {math.ceil(readyAt - now)}s`
	end

	local character = player.Character
	if not character or not getRoot(player) then
		return false, "No character"
	end
	if not destination then
		return false, "Can't teleport"
	end

	nextToken += 1
	local travel: Travel = {
		Token = nextToken,
		Kind = kind,
		Character = character,
		Destination = destination,
		StartTime = now,
		Finishing = false,
	}
	travels[player] = travel

	-- The HUD's channel bar covers everything before launch
	local channelTime = SpireData.GetChannelTime(kind)
	player:SetAttribute("TeleportChannelTime", channelTime)
	player:SetAttribute("TeleportChannelEnd", now + channelTime)

	-- Stream the landing spot while the client plays the light-up and launch
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(destination.Position)
		end)
	end)

	local info: TravelInfo = {
		Token = travel.Token,
		Kind = kind,
		Destination = destination,
	}
	Net:RemoteEvent("SpireTravel"):FireClient(player, info)

	-- Fallback for a client that never finishes (error, exploit, lost event)
	local timeout = SpireData.GetTravelTime(kind) + TRAVEL.GROUND_WAIT + TRAVEL.TIMEOUT_GRACE
	task.delay(timeout, checkArrival, player, travel)

	return true, "Teleporting..."
end

-- The client landed; check its position once it has replicated
local function onTravelDone(player: Player, token: unknown)
	local travel = travels[player]
	if not travel or travel.Token ~= token or travel.Finishing then
		return
	end

	-- Too early to have played the sequence; leave it to the timeout
	local elapsed = workspace:GetServerTimeNow() - travel.StartTime
	if elapsed < SpireData.GetTravelTime(travel.Kind) - EARLY_DONE_SLACK then
		return
	end

	travel.Finishing = true
	task.delay(ARRIVAL_CHECK_DELAY, checkArrival, player, travel)
end

local function onSpireTeleport(player: Player, id: unknown): (boolean, string)
	local area = WildAreaData.Get(id)
	local spire = ColonyController.GetBuilding(player, "Spire")
	if not area or not spire then
		return false, "Can't teleport"
	end

	if not ColonyController.IsNear(player, spire) then
		return false, "Too far from your Spire"
	end

	if spire.Level < area.UnlockLevel then
		return false, `Needs Spire level {area.UnlockLevel}`
	end

	if travels[player] then
		return false, "Already teleporting"
	end

	return startTravel(player, "Spire", getRandomArrival(area))
end

local function onReturnHome(player: Player): (boolean, string)
	local root = getRoot(player)
	if not ColonyController.GetData(player) or not root then
		return false, "Colony not loaded"
	end

	-- Any colony's plot is home, since they all share one spot
	if PlotData.IsInside(root.Position, BuildingUnlocks.MAX_LEVEL) then
		return false, "You're already home"
	end

	return startTravel(player, "Home", ColonyController.GetHomeCFrame(player))
end

local function onCharacterRemoving(player: Player)
	local travel = travels[player]
	if travel then
		finishTravel(player, travel, false)
	end
end

function SpireController.Start()
	if started then
		return
	end
	started = true

	Net:RemoteEvent("SpireTravel")
	Net:Connect("SpireTravelDone", onTravelDone)
	Net:Handle("SpireTeleport", onSpireTeleport)
	Net:Handle("ReturnHome", onReturnHome)

	local function watch(player: Player)
		player.CharacterRemoving:Connect(function()
			onCharacterRemoving(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		travels[player] = nil
		readyTimes[player] = nil
	end)
end

return SpireController
