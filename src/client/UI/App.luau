--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")
const UserInputService = game:GetService("UserInputService")

const Packages = ReplicatedStorage.Packages
const Shared = ReplicatedStorage.Shared
const Components = script.Parent.Components

const vide = require(Packages.vide)
const BuildingData = require(Shared.Buildings.BuildingData)
const BuildingTypes = require(Shared.Buildings.BuildingTypes)
const PlotData = require(Shared.Plot.PlotData)
const ColonyStore = require(script.Parent.Parent.Colony.ColonyStore)
const attributeSource = require(script.Parent.attributeSource)
const BuildMenu = require(Components.BuildMenu)
const BuildingPanel = require(Components.BuildingPanel)
const BuildingPlacement = require(Components.BuildingPlacement)
const Clock = require(Components.Clock)
const ColonistDialogue = require(Components.ColonistDialogue)
const ColonistPanel = require(Components.ColonistPanel)
const ColonyMenu = require(Components.ColonyMenu)
const FamilyTree = require(Components.FamilyTree)
const NamePrompt = require(Components.NamePrompt)
const Gathering = require(Components.Gathering)
const Inventory = require(Components.Inventory)
const MailboxPanel = require(Components.MailboxPanel)
const MerchantShop = require(Components.MerchantShop)
const SpireMenu = require(Components.SpireMenu)
const StoragePanel = require(Components.StoragePanel)
const TeleportHud = require(Components.TeleportHud)
const WorkScrollPanel = require(Components.WorkScrollPanel)
const ZoneBanner = require(Components.ZoneBanner)
const Notifications = require(Components.Notifications)
const RaidHud = require(Components.RaidHud)
const CreativeMenu = require(Components.CreativeMenu)

const create = vide.create
const source = vide.source
const show = vide.show
const switch = vide.switch
const cleanup = vide.cleanup

type BuildingId = BuildingTypes.BuildingId

local function App()
	local townHallLevel = attributeSource("TownHallLevel")
	local moving = source(nil :: BuildingId?)

	-- The building the ghost is placing: whatever is being moved, or on a new colony (once
	-- it's named) the first building, the Builder's Hut
	local placingId = function(): BuildingId?
		if not ColonyStore.Loaded() or ColonyStore.Name() == nil then
			return nil
		end
		local isNewColony = ColonyStore.GetBuilding("BuilderHut") == nil
			and ColonyStore.GetBuilding("TownHall") == nil
		return moving() or (if isNewColony then "BuilderHut" else nil)
	end

	local placing = function()
		return placingId() ~= nil
	end

	-- One constructor per building so switching between buildings rebuilds the ghost
	local ghosts = {}
	for id in BuildingData do
		ghosts[id] = function()
			local saved = ColonyStore.GetBuilding(id)
			local original = ColonyStore.Models[id]

			return BuildingPlacement({
				Id = id,
				Level = if saved then saved.Level else 1,
				PlotSize = PlotData.GetSize(townHallLevel() or 0),
				Original = if moving() == id then original else nil,
				OnPlaced = function()
					moving(nil)
				end,
			})
		end
	end

	-- The ghost lives in workspace, so it isn't a child of the ScreenGui
	switch(placingId)(ghosts)

	local function toggleMove(id: BuildingId)
		moving(if moving() == id then nil else id)
	end

	local connection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.Q then
			moving(nil)
		end
	end)
	cleanup(function()
		connection:Disconnect()
	end)

	return create("ScreenGui")({
		Name = "ColoniesUI",
		ResetOnSpawn = false,

		Gathering({
			Enabled = function()
				return not placing()
			end,
		}),

		Inventory(),

		StoragePanel(),

		BuildMenu({
			OnPlace = function(id)
				moving(id)
			end,
		}),

		BuildingPanel({
			OnMove = toggleMove,
		}),

		ColonyMenu({
			OnMoveTownHall = function()
				toggleMove("TownHall")
			end,
		}),

		Clock(),

		ZoneBanner(),

		Notifications(),

		RaidHud({
			Enabled = function()
				return not placing()
			end,
		}),

		ColonistPanel(),

		ColonistDialogue(),

		FamilyTree(),

		MerchantShop(),

		MailboxPanel(),

		WorkScrollPanel(),

		-- Dev-only, opened by the `creative` Cmdr command
		CreativeMenu(),

		show(function()
			return ColonyStore.Loaded() and ColonyStore.Name() == nil
		end, NamePrompt.NamePrompt),

		SpireMenu({
			OnMove = function()
				toggleMove("Spire")
			end,
		}),

		show(ColonyStore.Loaded, TeleportHud),

		show(placing, function()
			return create("TextLabel")({
				Name = "PlacementHint",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 16),
				Size = UDim2.fromOffset(460, 36),
				BackgroundColor3 = Color3.fromRGB(30, 30, 30),
				BackgroundTransparency = 0.2,
				TextColor3 = Color3.new(1, 1, 1),
				TextScaled = true,
				Text = function()
					local id = placingId()
					local name = if id then BuildingData[id].Name else ""
					local cancel = if moving() then ", Q to cancel" else ""
					return `Place your {name}: click to place, R to rotate{cancel}`
				end,

				create("UICorner")({}),
			})
		end),
	})
end

return App
