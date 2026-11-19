--!strict

const ServerScriptService = game:GetService("ServerScriptService")

const Systems = script.Systems
const CmdrSetup = script.Cmdr

const Cmdr = require(ServerScriptService.ServerPackages.cmdr)

const ColonyController = require(Systems.Colony.ColonyController)
const ColonistController = require(Systems.Colonist.ColonistController)
const ConversationController = require(Systems.Colonist.ConversationController)
const FarmController = require(Systems.Farm.FarmController)
const GatherController = require(Systems.Resource.GatherController)
const InventoryController = require(Systems.Inventory.InventoryController)
const MailboxController = require(Systems.Colony.MailboxController)
const MerchantController = require(Systems.Merchant.MerchantController)
const RaidController = require(Systems.Raid.RaidController)
const ResourceNodeController = require(Systems.Resource.ResourceNodeController)
const SpireController = require(Systems.Spire.SpireController)
const ToolController = require(Systems.Tools.ToolController)
const YardController = require(Systems.Yard.YardController)
const CreativeController = require(Systems.Creative.CreativeController)

ColonyController.Start()
ColonistController.Start()
ConversationController.Start()
InventoryController.Start()
ToolController.Start()
GatherController.Start()
ResourceNodeController.Start()
SpireController.Start()
MerchantController.Start()
RaidController.Start()
MailboxController.Start()
FarmController.Start()
YardController.Start()
CreativeController.Start()

-- Cmdr console (F2): built-in commands plus testing commands (src/server/Cmdr)
require(CmdrSetup.Hooks.OnlyTesters)(Cmdr.Registry)
Cmdr.Registry:RegisterDefaultCommands()
Cmdr.Registry:RegisterTypesIn(CmdrSetup.Types)
Cmdr.Registry:RegisterCommandsIn(CmdrSetup.Commands)
