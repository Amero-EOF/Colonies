--!strict

const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Packages = ReplicatedStorage.Packages
const UI = script.UI
const Colony = script.Colony

const vide = require(Packages.vide)
const App = require(UI.App)
const ColonistStore = require(Colony.ColonistStore)
const ColonistView = require(Colony.ColonistView)
const ColonyStore = require(Colony.ColonyStore)
const ColonyView = require(Colony.ColonyView)
const DayNight = require(Colony.DayNight)
const FieldView = require(Colony.FieldView)
const RaidStore = require(Colony.RaidStore)
const RaidView = require(Colony.RaidView)
const SpireTravel = require(Colony.SpireTravel)
const YardView = require(Colony.YardView)

ColonyStore.Start()
ColonyView.Start()
FieldView.Start()
YardView.Start()
ColonistStore.OnMessage = ColonyStore.Notify
ColonistStore.Start()
ColonistView.Start()
RaidStore.OnMessage = ColonyStore.Notify
RaidStore.Start()
RaidView.Start()
DayNight.Start()
SpireTravel.Start()

vide.mount(App, Players.LocalPlayer:WaitForChild("PlayerGui"))

-- Cmdr console (F2), for testing commands
const requireModule: any = require
requireModule(ReplicatedStorage:WaitForChild("CmdrClient"))
