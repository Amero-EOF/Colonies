--!strict

const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared
const Packages = ReplicatedStorage.Packages
const Systems = script.Parent.Parent

const Net = require(Packages.Net)
const BuildingData = require(Shared.Buildings.BuildingData)
const BuildingTypes = require(Shared.Buildings.BuildingTypes)
const BuildingUnlocks = require(Shared.Buildings.BuildingUnlocks)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const FarmData = require(Shared.Farm.FarmData)
const ColonyController = require(Systems.Colony.ColonyController)
const ColonyLog = require(Systems.Colony.Components.ColonyLog)

type ColonyData = ColonyTypes.ColonyData
type Plot = FarmData.Plot

-- The building whose field the remotes change (one per colony)
const HUT: BuildingTypes.BuildingId = "FarmerHut"
-- Server-set player attribute (testing): every planted crop becomes ripe, then it's cleared
const DEBUG_RIPEN_ATTRIBUTE = "DebugFarmRipen"

-- The Farmer's Hut crop field. The player picks a crop per unlocked wedge; the Farmer
-- (AI/Jobs/Farmer) plants it with a seed and harvests it whenever it's ripe, after which it
-- regrows by itself. Growth is a pure function of server time (FarmData.GetStage).
const FarmController = {}

local started = false

-- The hut's field, if the hut is built; else nil and a message for the player
local function getField(data: ColonyData): ({ Plot }?, number, string)
	local saved: ColonyTypes.SavedBuilding? = nil
	for _, building in data.Buildings do
		if building.Id == HUT then
			saved = building
		end
	end
	local name = BuildingData[HUT].Name
	if not saved or not saved.Placement then
		return nil, 0, `Place a {name} first`
	end
	if not BuildingUnlocks.IsBuilt(saved.Id, saved.Level) then
		return nil, 0, `The {name} isn't built yet`
	end
	local field = data.Fields[HUT]
	if not field then
		return nil, 0, `The {name} has no field`
	end
	return field, saved.Level, ""
end

local function getPlot(player: Player, wedge: unknown): (ColonyData?, Plot?, string)
	local data = ColonyController.GetData(player)
	if not data then
		return nil, nil, "Colony not loaded"
	end
	if typeof(wedge) ~= "number" or wedge % 1 ~= 0 then
		return nil, nil, "Pick a part of the field"
	end
	local field, level, err = getField(data)
	if not field then
		return nil, nil, err
	end
	if not FarmData.IsUnlocked(wedge, level) then
		local unlock = FarmData.WEDGE_UNLOCK_LEVEL[wedge]
		return nil, nil, if unlock then `Unlocks at level {unlock}` else "Pick a part of the field"
	end
	local plot = field[wedge]
	if not plot then
		plot = {}
		field[wedge] = plot
	end
	return data, plot, ""
end

-- Assigns a crop to a wedge. It waits there until the Farmer plants a matching seed.
local function onSetFieldCrop(player: Player, wedge: unknown, crop: unknown): (boolean, string)
	local data, plot, err = getPlot(player, wedge)
	if not data or not plot then
		return false, err
	end
	local info = FarmData.GetCrop(crop)
	if not info then
		return false, "Unknown crop"
	end
	if plot.Crop == info.Id then
		return true, `{info.Name} is already growing there`
	end

	plot.Crop = info.Id
	plot.PlantedAt = nil
	ColonyLog.Add(data, `Field {wedge}: the Farmer will plant {info.Name}`)
	ColonyController.Sync(player)
	return true, `The Farmer will plant {info.Name} (needs {info.Name} Seeds)`
end

-- Empties a wedge. A seed the Farmer already took stays in his pack, so nothing is lost
-- unless the crop was already planted.
local function onClearFieldCrop(player: Player, wedge: unknown): (boolean, string)
	local data, plot, err = getPlot(player, wedge)
	if not data or not plot then
		return false, err
	end
	local info = FarmData.GetCrop(plot.Crop)
	if not info then
		plot.Crop = nil
		plot.PlantedAt = nil
		return true, "Nothing is growing there"
	end

	local name = info.Name
	plot.Crop = nil
	plot.PlantedAt = nil
	ColonyLog.Add(data, `Field {wedge}: removed the {name}`)
	ColonyController.Sync(player)
	return true, `Removed the {name}`
end

-- Testing: makes every planted crop of the player's colony ripe now
function FarmController.Ripen(player: Player): number
	local data = ColonyController.GetData(player)
	if not data then
		return 0
	end
	local now = workspace:GetServerTimeNow()
	local ripened = 0
	for _, field in data.Fields do
		for _, plot in field do
			local info = FarmData.GetCrop(plot.Crop)
			if info and plot.PlantedAt then
				plot.PlantedAt = now - FarmData.GetGrowTime(info.Id) - 1
				ripened += 1
			end
		end
	end
	ColonyController.Sync(player)
	return ripened
end

local function watchDebug(player: Player)
	local function check()
		if player:GetAttribute(DEBUG_RIPEN_ATTRIBUTE) == true then
			FarmController.Ripen(player)
			player:SetAttribute(DEBUG_RIPEN_ATTRIBUTE, nil)
		end
	end
	player:GetAttributeChangedSignal(DEBUG_RIPEN_ATTRIBUTE):Connect(check)
	check()
end

function FarmController.Start()
	if started then
		return
	end
	started = true

	Net:Handle("SetFieldCrop", onSetFieldCrop)
	Net:Handle("ClearFieldCrop", onClearFieldCrop)

	Players.PlayerAdded:Connect(watchDebug)
	for _, player in Players:GetPlayers() do
		watchDebug(player)
	end
end

return FarmController
