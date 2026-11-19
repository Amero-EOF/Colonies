--!strict

const HttpService = game:GetService("HttpService")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared

const vide = require(Packages.vide)
const Net = require(Packages.Net)
const BuildingTypes = require(Shared.Buildings.BuildingTypes)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const FarmData = require(Shared.Farm.FarmData)
const InventoryTypes = require(Shared.Inventory.InventoryTypes)
const YardData = require(Shared.Yard.YardData)

const source = vide.source

type SavedBuilding = ColonyTypes.SavedBuilding

export type ColonyState = {
	Name: string?,
	Buildings: { SavedBuilding },
	Events: { ColonyTypes.ColonyEvent },
	WorkOrders: { ColonyTypes.WorkOrder },
	Inventory: InventoryTypes.Inventory,
	Storage: InventoryTypes.Bag,
	HutStorage: { [string]: InventoryTypes.Bag },
	Fields: { [string]: { FarmData.Plot } }?,
	Yards: { [string]: { YardData.Node } }?,
	Mail: { ColonyTypes.Mail }?,
}

const MESSAGE_TIME = 2

-- The local player's colony as last sent by the server
const ColonyStore = {
	Loaded = source(false),
	Name = source(nil :: string?),
	Events = source({} :: { ColonyTypes.ColonyEvent }),
	WorkOrders = source({} :: { ColonyTypes.WorkOrder }),
	Buildings = source({} :: { SavedBuilding }),
	Inventory = source({ Bags = {} } :: InventoryTypes.Inventory),
	Storage = source(nil :: InventoryTypes.Bag?),
	-- Worker buildings' own storage (Builder's Hut...), by building id
	HutStorage = source({} :: { [string]: InventoryTypes.Bag }),
	-- Crop fields (Farmer's Hut), by building id; index = wedge. Growth is computed from
	-- each plot's PlantedAt with workspace:GetServerTimeNow() (FarmData.GetStage)
	Fields = source({} :: { [string]: { FarmData.Plot } }),
	-- Resource yards (Forester's Hut, Mine), by building id; index = node. Regrowth is computed
	-- from each node's HarvestedAt with workspace:GetServerTimeNow() (YardData.GetStage)
	Yards = source({} :: { [string]: { YardData.Node } }),
	-- Town Hall mailbox letters, oldest first
	Mail = source({} :: { ColonyTypes.Mail }),
	MailboxOpen = source(false),
	-- Building whose storage the panel shows; nil is the colony storage
	StorageTarget = source(nil :: string?),
	-- Building models the client drew, by building id
	Models = {} :: { [string]: Model },
	SpireMenuOpen = source(false),
	StorageOpen = source(false),
	ManageOpen = source(false),
	-- Building whose upgrade/move panel is open
	BuildingPanelId = source(nil :: BuildingTypes.BuildingId?),
	Message = source(""),
}

local lastBuildings = ""
local lastFields = ""
local lastYards = ""
local started = false

local function apply(state: ColonyState?)
	if not state then
		return
	end

	-- Only redraw buildings when they actually changed (gathering resends the whole state)
	local encoded = HttpService:JSONEncode(state.Buildings)
	if encoded ~= lastBuildings then
		lastBuildings = encoded
		ColonyStore.Buildings(state.Buildings)
	end

	ColonyStore.Name(state.Name)
	ColonyStore.Events(state.Events)
	ColonyStore.WorkOrders(state.WorkOrders)
	ColonyStore.Inventory(state.Inventory)
	ColonyStore.Storage(state.Storage)
	ColonyStore.HutStorage(state.HutStorage or {})
	-- Fields only change when crops are assigned, planted or harvested
	local fields = state.Fields or {}
	local encodedFields = HttpService:JSONEncode(fields)
	if encodedFields ~= lastFields then
		lastFields = encodedFields
		ColonyStore.Fields(fields)
	end
	-- Yards only change when a node is worked
	local yards = state.Yards or {}
	local encodedYards = HttpService:JSONEncode(yards)
	if encodedYards ~= lastYards then
		lastYards = encodedYards
		ColonyStore.Yards(yards)
	end
	ColonyStore.Mail(state.Mail or {})
	ColonyStore.Loaded(true)
end

-- Shows a short status line to the player
function ColonyStore.Notify(text: string)
	ColonyStore.Message(text)
	task.delay(MESSAGE_TIME, function()
		if ColonyStore.Message() == text then
			ColonyStore.Message("")
		end
	end)
end

function ColonyStore.GetBuilding(id: string): SavedBuilding?
	for _, saved in ColonyStore.Buildings() do
		if saved.Id == id then
			return saved
		end
	end
	return nil
end

function ColonyStore.Start()
	if started then
		return
	end
	started = true

	Net:Connect("ColonyState", apply)
	task.spawn(function()
		apply(Net:Invoke("GetColonyState"))
	end)
end

return ColonyStore
