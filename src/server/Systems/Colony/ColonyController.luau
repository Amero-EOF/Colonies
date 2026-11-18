--!strict

const Players = game:GetService("Players")
const PhysicsService = game:GetService("PhysicsService")
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const RunService = game:GetService("RunService")
const TextService = game:GetService("TextService")
const ServerScriptService = game:GetService("ServerScriptService")

const Shared = ReplicatedStorage.Shared
const Packages = ReplicatedStorage.Packages
const ServerPackages = ServerScriptService.ServerPackages
const Systems = script.Parent.Parent

const ProfileStore = require(ServerPackages.profilestore)
const Net = require(Packages.Net)
const BuildingData = require(Shared.Buildings.BuildingData)
const BuildingModels = require(Shared.Buildings.BuildingModels)
const BuildingPlacement = require(Shared.Buildings.BuildingPlacement)
const BuildingUnlocks = require(Shared.Buildings.BuildingUnlocks)
const ColonyDataConfig = require(Shared.Colony.ColonyData)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const BagMoves = require(Shared.Inventory.BagMoves)
const InventoryTypes = require(Shared.Inventory.InventoryTypes)
const ItemsList = require(Shared.Inventory.ItemsList)
const FarmData = require(Shared.Farm.FarmData)
const PlotData = require(Shared.Plot.PlotData)
const SpireData = require(Shared.Spire.SpireData)
const Bag = require(Systems.Inventory.Components.Bag)
const Inventory = require(Systems.Inventory.Components.Inventory)
const InventoryController = require(Systems.Inventory.InventoryController)
const ToolController = require(Systems.Tools.ToolController)
const ColonyLog = require(script.Parent.Components.ColonyLog)
const Mailbox = require(script.Parent.Components.Mailbox)
const WorkOrders = require(script.Parent.Components.WorkOrders)

type ColonyData = ColonyTypes.ColonyData
type Placement = ColonyTypes.Placement
type SavedBuilding = ColonyTypes.SavedBuilding

type Colony = {
	Player: Player,
	Profile: any,
}

const storageItem = ItemsList.GetItemByItemType("TownHallStorage")
assert(storageItem, "TownHallStorage item missing")

const PROFILE_TEMPLATE: ColonyData = {
	Buildings = {
		{ Id = "TownHall", Level = 0 },
	},
	Inventory = Inventory.new(),
	Storage = Bag.new(storageItem),
	HutStorage = {},
	Fields = {},
	Events = {},
	WorkOrders = {},
	NextWorkOrderId = 1,
	Colonists = {},
	Departed = {},
	NextColonistId = 1,
	Disease = 0,
	LastDay = -1,
	Merchant = { NextArrival = 0, LeavesAt = 0 },
	Mail = {},
	NextMailId = 1,
}

-- Buildings every colony starts with already placed (they can still be moved)
const STARTING_BUILDINGS: { [string]: Placement } = {
	Spire = { X = 0, Z = -48, Rotation = 0 },
}

const TELEPORT_HEIGHT = 5
const TELEPORT_CLEARANCE = 8
-- Studs past a building's footprint its prompts reach (server allows some lag on top)
const USE_REACH = 16
const CHARACTER_GROUP = "Characters"

-- Studio uses ProfileStore's mock store so testing never touches real saves
const RealStore = ProfileStore.New("Colonies", PROFILE_TEMPLATE)
const ColonyStore = if RunService:IsStudio() then RealStore.Mock else RealStore

const ColonyController = {}

const colonies: { [Player]: Colony } = {}
local started = false

local function isFiniteNumber(value: unknown): boolean
	return typeof(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local function getSaved(data: ColonyData, id: string): (SavedBuilding?, number?)
	for i, saved in data.Buildings do
		if saved.Id == id then
			return saved, i
		end
	end

	return nil, nil
end

local function getTownHallLevel(data: ColonyData): number
	local townHall = getSaved(data, "TownHall")
	return if townHall then townHall.Level else 0
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Standing spot just in front of a placed building
local function getSpotBeside(saved: SavedBuilding, placement: Placement): CFrame
	local footprint = BuildingModels.GetFootprint(saved.Id, saved.Level)
	local offset = math.max(footprint.X, footprint.Y) / 2 + TELEPORT_CLEARANCE
	return BuildingPlacement.ToCFrame(placement) * CFrame.new(0, TELEPORT_HEIGHT, offset)
end

-- Beside the Spire, otherwise the plot centre
local function getHomeCFrame(data: ColonyData): CFrame
	local spire = getSaved(data, "Spire")
	if spire and spire.Placement then
		return getSpotBeside(spire, spire.Placement)
	end

	return PlotData.SURFACE * CFrame.new(0, TELEPORT_HEIGHT, 0)
end

-- Everything the owner's client needs to draw the colony and its menus
local function getState(data: ColonyData)
	return {
		Name = data.Name,
		Buildings = data.Buildings,
		Inventory = data.Inventory,
		Storage = data.Storage,
		HutStorage = data.HutStorage,
		Fields = data.Fields,
		Events = data.Events,
		WorkOrders = data.WorkOrders,
		Mail = data.Mail,
	}
end

-- Gives every built worker building with a WorkerStorage component its bag
local function ensureHutStorage(data: ColonyData)
	for _, saved in data.Buildings do
		local workerStorage = BuildingData[saved.Id].Components.WorkerStorage
		if
			workerStorage
			and BuildingUnlocks.IsBuilt(saved.Id, saved.Level)
			and not data.HutStorage[saved.Id]
		then
			local item = ItemsList.GetItemByItemType(workerStorage.BagItem)
			if item then
				data.HutStorage[saved.Id] = Bag.new(item)
			end
		end
	end
end

-- Gives every building with a Field component its crop field (only filling gaps in saved ones)
local function ensureFields(data: ColonyData)
	for _, saved in data.Buildings do
		if not BuildingData[saved.Id].Components.Field then
			continue
		end
		local field = data.Fields[saved.Id] or FarmData.NewField()
		for wedge = 1, FarmData.WEDGE_COUNT do
			field[wedge] = field[wedge] or {}
		end
		data.Fields[saved.Id] = field
	end
end

local function sync(colony: Colony)
	local data: ColonyData = colony.Profile.Data
	local player = colony.Player

	Net:RemoteEvent("ColonyState"):FireClient(player, getState(data))
	-- Held items (Work Scroll, shovel...) follow what the backpack holds
	ToolController.SyncItems(player, InventoryController.GetBackpack(data))

	local townHall = getSaved(data, "TownHall")
	player:SetAttribute("TownHallLevel", getTownHallLevel(data))
	player:SetAttribute("TownHallPlaced", townHall ~= nil and townHall.Placement ~= nil)
end

-- Stacks a bag can't hold (lost slots, doubled slots, overfull stacks) go to the mailbox
local function rescueGlitchedItems(data: ColonyData)
	local bags: { [string]: InventoryTypes.Bag } = { Storage = data.Storage }
	local backpack = InventoryController.GetBackpack(data)
	if backpack then
		bags.Backpack = backpack
	end
	for id, bag in data.HutStorage do
		local info = BuildingData[id :: any]
		bags[if info then `{info.Name} storage` else `{id} storage`] = bag
	end

	local items = {}
	local where = {}
	for name, bag in bags do
		local taken = Mailbox.TakeGlitched(bag)
		if #taken > 0 then
			table.insert(where, name)
			table.move(taken, 1, #taken, #items + 1, items)
		end
	end
	if #items > 0 then
		table.sort(where)
		Mailbox.Send(data, {
			From = "Lost & Found",
			Title = "Recovered items",
			Body = `These items were stuck in your {table.concat(where, ", ")} and were moved here.`,
			Items = items,
		})
	end
end

-- Fills in anything older saves are missing
local function migrate(data: ColonyData)
	local old = data :: any
	old.Carried = nil
	old.Stored = nil

	for id, placement in STARTING_BUILDINGS do
		local saved = getSaved(data, id)
		if not saved then
			table.insert(
				data.Buildings,
				{ Id = id :: any, Level = 1, Placement = table.clone(placement) }
			)
		elseif not saved.Placement then
			saved.Placement = table.clone(placement)
		end
	end

	local spire = getSaved(data, "Spire")
	if spire then
		spire.Level = SpireData.GetLevel(getTownHallLevel(data))
	end

	-- The Town Hall is never a construction site
	for _, order in table.clone(data.WorkOrders) do
		if order.BuildingId == "TownHall" and order.Kind == "Build" then
			WorkOrders.Remove(data, order.Id)
		end
	end

	WorkOrders.Migrate(data)
	ensureHutStorage(data)
	data.Fields = data.Fields or {}
	ensureFields(data)
	Mailbox.Migrate(data)
	rescueGlitchedItems(data)
end

-- Moves the character out if a building was just placed on top of them
local function ejectFromBuilding(player: Player, saved: SavedBuilding, placement: Placement)
	local root = getRoot(player)
	local character = player.Character
	if not root or not character then
		return
	end

	local footprint = BuildingModels.GetFootprint(saved.Id, saved.Level)
	local localPosition = BuildingPlacement.ToCFrame(placement):PointToObjectSpace(root.Position)
	local half = math.max(footprint.X, footprint.Y) / 2 + 2
	if math.abs(localPosition.X) <= half and math.abs(localPosition.Z) <= half then
		character:PivotTo(getSpotBeside(saved, placement))
	end
end

-- Places or moves one of the player's buildings on their plot
local function onPlaceBuilding(
	player: Player,
	id: unknown,
	x: unknown,
	z: unknown,
	rotation: unknown
): boolean
	local colony = colonies[player]
	if not colony or typeof(id) ~= "string" then
		return false
	end

	if not isFiniteNumber(x) or not isFiniteNumber(z) or not isFiniteNumber(rotation) then
		return false
	end

	local data: ColonyData = colony.Profile.Data
	local saved, index = getSaved(data, id)
	local isNew = saved == nil
	if not saved then
		-- Building something new: it must be unlocked and the Town Hall placed first
		local townHall = getSaved(data, "TownHall")
		local info = BuildingData[id :: any]
		if not info or not townHall or not townHall.Placement then
			return false
		end
		if not BuildingUnlocks.IsUnlocked(info.Id, townHall.Level) then
			return false
		end
		saved = { Id = info.Id, Level = 1 }
	end
	assert(saved, "saved is set above")

	local footprint = BuildingModels.GetFootprint(saved.Id, saved.Level)
	local plotSize = PlotData.GetSize(getTownHallLevel(data))
	local placement =
		BuildingPlacement.Resolve(plotSize, footprint, x :: number, z :: number, rotation :: number)

	for j, other in data.Buildings do
		if j ~= index and other.Placement then
			local otherFootprint = BuildingModels.GetFootprint(other.Id, other.Level)
			if
				BuildingPlacement.Overlaps(placement, footprint, other.Placement, otherFootprint)
			then
				return false
			end
		end
	end

	if isNew then
		local info = BuildingData[saved.Id]
		-- New buildings start as construction sites. The Builder's Hut is built by its own
		-- Builder, using materials the player hands to him directly.
		saved.Level = 0
		table.insert(data.Buildings, saved)
		if saved.Level == 0 then
			local order = WorkOrders.CreateBuild(data, saved.Id)
			ColonyLog.Add(data, `Work order #{order.Id}: build the {info.Name}`)
		end
		ensureHutStorage(data)
		ensureFields(data)
	end
	if not saved.Placement then
		ColonyLog.Add(data, `Placed the {BuildingData[saved.Id].Name}`)
	end
	saved.Placement = placement
	ejectFromBuilding(player, saved, placement)
	sync(colony)

	return true
end

-- Testing only: free upgrade, no resources yet. Queues a work order for the Builder.
local function onUpgradeBuilding(player: Player, id: unknown)
	local colony = colonies[player]
	if not colony or typeof(id) ~= "string" then
		return
	end

	local data: ColonyData = colony.Profile.Data
	local saved = getSaved(data, id)
	if not saved or not saved.Placement or WorkOrders.GetPending(data, saved.Id) then
		return
	end

	local builderHut = getSaved(data, "BuilderHut")
	local builderHutLevel = if builderHut then builderHut.Level else 0
	if
		not BuildingUnlocks.CanUpgrade(
			saved.Id,
			saved.Level,
			getTownHallLevel(data),
			builderHutLevel
		)
	then
		return
	end

	local order = WorkOrders.CreateUpgrade(data, saved.Id, saved.Level + 1)
	local name = BuildingData[saved.Id].Name
	ColonyLog.Add(data, `Work order #{order.Id}: upgrade the {name} to level {order.TargetLevel}`)
	sync(colony)
end

-- Applies a finished work order. The plot grows with the Town Hall and the Spire follows it.
local function completeWorkOrder(data: ColonyData, order: ColonyTypes.WorkOrder)
	local saved = getSaved(data, order.BuildingId)
	if not saved then
		return
	end

	saved.Level = math.max(saved.Level, order.TargetLevel)
	if saved.Id == "TownHall" then
		local spire = getSaved(data, "Spire")
		if spire then
			spire.Level = SpireData.GetLevel(saved.Level)
		end
	end

	ColonyLog.Add(
		data,
		`Builder finished #{order.Id}: {BuildingData[saved.Id].Name} is now level {saved.Level}`
	)
end

local function onSetColonyName(player: Player, name: unknown): (boolean, string)
	local colony = colonies[player]
	if not colony or typeof(name) ~= "string" then
		return false, "Can't rename"
	end

	local trimmed = string.gsub(name, "^%s*(.-)%s*$", "%1")
	local length = utf8.len(trimmed)
	if not length or length < ColonyDataConfig.NAME_MIN or length > ColonyDataConfig.NAME_MAX then
		return false, `Use {ColonyDataConfig.NAME_MIN}-{ColonyDataConfig.NAME_MAX} characters`
	end

	local ok, filtered = pcall(function(): string
		return TextService:FilterStringAsync(trimmed, player.UserId)
			:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		return false, "Couldn't check the name, try again"
	end
	if filtered ~= trimmed then
		return false, "That name isn't allowed"
	end

	local data: ColonyData = colony.Profile.Data
	ColonyLog.Add(
		data,
		if data.Name then `Renamed the colony to {trimmed}` else `Founded {trimmed}`
	)
	data.Name = trimmed
	sync(colony)

	return true, "Saved"
end

-- True when the player stands within reach of one of their placed buildings
local function isNear(player: Player, saved: SavedBuilding): boolean
	local root = getRoot(player)
	local placement = saved.Placement
	if not root or not placement then
		return false
	end

	local footprint = BuildingModels.GetFootprint(saved.Id, saved.Level)
	local offset = BuildingPlacement.ToCFrame(placement).Position - root.Position
	return Vector2.new(offset.X, offset.Z).Magnitude
		<= math.max(footprint.X, footprint.Y) / 2 + USE_REACH + 4
end

local function onDeposit(player: Player, target: unknown): (boolean, string)
	local colony = colonies[player]
	if not colony then
		return false, "Colony not loaded"
	end

	local data: ColonyData = colony.Profile.Data

	-- Delivering to a worker building's own storage (e.g. Builder's Hut materials)
	if typeof(target) == "string" then
		local saved = getSaved(data, target)
		local bag = data.HutStorage[target]
		local backpack = InventoryController.GetBackpack(data)
		if
			not saved
			or not bag
			or not backpack
			or not BuildingUnlocks.IsBuilt(saved.Id, saved.Level)
		then
			return false, "That building has no storage"
		end
		local name = BuildingData[saved.Id].Name
		if not isNear(player, saved) then
			return false, `Stand next to your {name}`
		end
		local moved = Bag.TransferAll(backpack, bag, ItemsList.IsHoldable)
		if moved > 0 then
			ColonyLog.Add(data, `Delivered {moved} items to the {name}`)
		end
		sync(colony)
		return true,
			if moved > 0 then `Delivered {moved} items to the {name}` else "Nothing to deliver"
	end

	for _, saved in data.Buildings do
		if BuildingData[saved.Id].Components.Storage and isNear(player, saved) then
			local moved = InventoryController.Deposit(data)
			if moved > 0 then
				ColonyLog.Add(data, `Deposited {moved} items`)
			end
			sync(colony)
			return true, if moved > 0 then `Deposited {moved} items` else "Nothing to deposit"
		end
	end

	return false, "Stand next to your Town Hall or Warehouse"
end

-- Bags of this colony that MoveItems may change for the player: the backpack anywhere,
-- colony storage beside a Storage building, a worker building's storage beside it
local function syncPlayer(player: Player)
	local colony = colonies[player]
	if colony then
		sync(colony)
	end
end

local function resolveBackpack(player: Player): (InventoryTypes.Bag?, string)
	local colony = colonies[player]
	local backpack = colony and InventoryController.GetBackpack(colony.Profile.Data)
	return backpack, if backpack then "" else "Colony not loaded"
end

local function resolveStorage(player: Player): (InventoryTypes.Bag?, string)
	local colony = colonies[player]
	if not colony then
		return nil, "Colony not loaded"
	end
	local data: ColonyData = colony.Profile.Data
	for _, saved in data.Buildings do
		if BuildingData[saved.Id].Components.Storage and isNear(player, saved) then
			return data.Storage, ""
		end
	end
	return nil, "Stand next to your Town Hall or Warehouse"
end

local function resolveHutStorage(player: Player, id: string?): (InventoryTypes.Bag?, string)
	local colony = colonies[player]
	if not colony or not id then
		return nil, "That building has no storage"
	end
	local data: ColonyData = colony.Profile.Data
	local saved = getSaved(data, id)
	local bag = data.HutStorage[id]
	if not saved or not bag or not BuildingUnlocks.IsBuilt(saved.Id, saved.Level) then
		return nil, "That building has no storage"
	end
	if not isNear(player, saved) then
		return nil, `Stand next to your {BuildingData[saved.Id].Name}`
	end
	return bag, ""
end

local function setupCharacter(player: Player, character: Model)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = CHARACTER_GROUP
		end
	end
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = CHARACTER_GROUP
		end
	end)

	-- Respawn beside the Spire once the colony has loaded
	task.defer(function()
		local colony = colonies[player]
		if colony and character.Parent then
			character:PivotTo(getHomeCFrame(colony.Profile.Data))
		end
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)

	local profile = ColonyStore:StartSessionAsync(`Player_{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if not profile then
		player:Kick("Failed to load your colony, please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	migrate(profile.Data)

	profile.OnSessionEnd:Connect(function()
		colonies[player] = nil
		player:Kick("Your colony was loaded in another server.")
	end)

	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	local colony: Colony = { Player = player, Profile = profile }
	colonies[player] = colony
	sync(colony)
	Mailbox.NotifyUnread(player, profile.Data)

	-- Mail sent with ColonyController.SendMessage (developer gifts, works while offline or
	-- in another server); handled once the profile is loaded here
	profile:MessageHandler(function(message: any, processed: () -> ())
		if typeof(message) ~= "table" or message.Kind ~= "Mail" or colonies[player] ~= colony then
			return
		end
		local letter = Mailbox.ToLetter(message.Letter)
		if letter then
			local mail = Mailbox.Send(profile.Data, letter)
			Mailbox.Notify(player, mail)
			sync(colony)
		end
		processed()
	end)

	local character = player.Character
	if character then
		setupCharacter(player, character)
	end
end

local function onPlayerRemoving(player: Player)
	local colony = colonies[player]
	if colony then
		colonies[player] = nil
		colony.Profile:EndSession()
	end
end

-- The player's saved colony data, once their profile has loaded
function ColonyController.GetData(player: Player): ColonyData?
	local colony = colonies[player]
	return colony and colony.Profile.Data
end

-- The player's saved building with this id
function ColonyController.GetBuilding(player: Player, id: string): SavedBuilding?
	local data = ColonyController.GetData(player)
	return if data then (getSaved(data, id)) else nil
end

function ColonyController.IsNear(player: Player, saved: SavedBuilding): boolean
	return isNear(player, saved)
end

function ColonyController.GetTownHallLevel(player: Player): number
	local data = ColonyController.GetData(player)
	return if data then getTownHallLevel(data) else 0
end

-- Where "return home" teleports the player
function ColonyController.GetHomeCFrame(player: Player): CFrame?
	local data = ColonyController.GetData(player)
	return if data then getHomeCFrame(data) else nil
end

-- Re-sends the player's colony after their data changed elsewhere (e.g. gathering)
function ColonyController.Sync(player: Player)
	local colony = colonies[player]
	if colony then
		sync(colony)
	end
end

-- Applies a work order the Builder finished and removes it
function ColonyController.CompleteWorkOrder(player: Player, orderId: number)
	local data = ColonyController.GetData(player)
	local order = data and WorkOrders.GetById(data, orderId)
	if not data or not order then
		return
	end

	WorkOrders.Remove(data, orderId)
	completeWorkOrder(data, order)
	ensureHutStorage(data)
	ensureFields(data)
	ColonyController.Sync(player)
end

-- Players whose colony has loaded
function ColonyController.GetLoadedPlayers(): { Player }
	local players = {}
	for player in colonies do
		table.insert(players, player)
	end
	return players
end

-- Queues a ProfileStore message for a player's colony, online or not (yields). Messages are
-- handled when the profile is active (see MessageHandler in onPlayerAdded); e.g.
-- { Kind = "Mail", Letter = { From = "...", Title = "...", Items = { ... } } }
function ColonyController.SendMessage(userId: number, message: { [string]: any }): boolean
	local ok, result = pcall(function(): boolean
		return ColonyStore:MessageAsync(`Player_{userId}`, message)
	end)
	if not ok then
		warn(`[Colony] Message to {userId} failed: {result}`)
	end
	return ok and result == true
end

function ColonyController.Start()
	if started then
		return
	end
	started = true

	PhysicsService:RegisterCollisionGroup(CHARACTER_GROUP)
	PhysicsService:CollisionGroupSetCollidable(CHARACTER_GROUP, CHARACTER_GROUP, false)

	Net:RemoteEvent("ColonyState")
	Net:Handle("GetColonyState", function(player: Player): any
		local colony = colonies[player]
		if not colony then
			return nil
		end

		return getState(colony.Profile.Data)
	end)
	Net:Handle("PlaceBuilding", onPlaceBuilding)
	Net:Handle("Deposit", onDeposit)
	Net:Connect("UpgradeBuilding", onUpgradeBuilding)
	Net:Handle("SetColonyName", onSetColonyName)

	InventoryController.RegisterBag(
		BagMoves.BACKPACK,
		{ Resolve = resolveBackpack, Sync = syncPlayer }
	)
	InventoryController.RegisterBag(
		BagMoves.STORAGE,
		{ Resolve = resolveStorage, Sync = syncPlayer }
	)
	InventoryController.RegisterBag("Hut", { Resolve = resolveHutStorage, Sync = syncPlayer })

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return ColonyController
