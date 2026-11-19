--!strict

const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Shared = ReplicatedStorage.Shared
const Packages = ReplicatedStorage.Packages
const Systems = script.Parent.Parent

const Net = require(Packages.Net)
const BuildingUnlocks = require(Shared.Buildings.BuildingUnlocks)
const ColonistData = require(Shared.Colonist.ColonistData)
const ColonistTypes = require(Shared.Colonist.ColonistTypes)
const ColonyTypes = require(Shared.Colony.ColonyTypes)
const DayCycle = require(Shared.Time.DayCycle)
const InventoryTypes = require(Shared.Inventory.InventoryTypes)
const PlotData = require(Shared.Plot.PlotData)
const ColonyController = require(Systems.Colony.ColonyController)
const ColonyLog = require(Systems.Colony.Components.ColonyLog)
const Mailbox = require(Systems.Colony.Components.Mailbox)
const Notifications = require(Systems.Colony.Components.Notifications)
const Bag = require(Systems.Inventory.Components.Bag)
const InventoryController = require(Systems.Inventory.InventoryController)
const ItemsList = require(Shared.Inventory.ItemsList)
const Builder = require(script.Parent.AI.Jobs.Builder)
const Farmer = require(script.Parent.AI.Jobs.Farmer)
const Agent = require(script.Parent.AI.Agent)
const Brain = require(script.Parent.AI.Brain)
const Navigation = require(script.Parent.Components.Navigation)
const Needs = require(script.Parent.Components.Needs)
const Population = require(script.Parent.Components.Population)

type Agent = Agent.Agent
type Colonist = ColonistTypes.Colonist
type ColonyData = ColonyTypes.ColonyData
type Context = Agent.Context

-- Runtime for one loaded colony
type Colony = {
	Context: Context,
	Agents: { [number]: Agent },
	NextArrival: number,
	NextAssign: number,
	NextState: number,
}

const TICK = 0.2
const ASSIGN_INTERVAL = 2
const STATE_INTERVAL = 1
-- Studs from a colonist the player must be to wake it
const INTERACT_REACH = 20
const MOURNING_ID = "Mourning"

const ColonistController = {}

const colonies: { [Player]: Colony } = {}
local started = false

-- Other systems that step with a colony's colonists (see ColonistController.OnStep)
type StepHook = (
	player: Player,
	context: Context,
	agents: { [number]: Agent },
	deltaTime: number,
	now: number
) -> ()
const stepHooks: { StepHook } = {}

local function getSaved(data: ColonyData, id: string): ColonyTypes.SavedBuilding?
	for _, saved in data.Buildings do
		if saved.Id == id and saved.Placement then
			return saved
		end
	end
	return nil
end

-- A placed building that is built (not a construction site)
local function getBuilt(data: ColonyData, id: string): ColonyTypes.SavedBuilding?
	local saved = getSaved(data, id)
	return if saved and BuildingUnlocks.IsBuilt(saved.Id, saved.Level) then saved else nil
end

-- At the Town Hall's door once it's built; before that, in a ring around the Spire
local function getSpawn(context: Context, colonist: Colonist): Vector3
	local data = context.Data
	local townHall = getBuilt(data, "TownHall")
	local door = townHall and Navigation.GetDoor(townHall)
	if door then
		return door
	end
	local spire = getSaved(data, "Spire")
	local spot = spire
		and Navigation.GetRingSpot(context.Grid, spire, colonist.Id, Population.STARTING_COLONISTS)
	return spot or Vector3.zero
end

local function log(player: Player, text: string)
	local data = ColonyController.GetData(player)
	if data then
		ColonyLog.Add(data, text)
		ColonyController.Sync(player)
	end
end

local function getColonyName(data: ColonyData): string
	return data.Name or "the colony"
end

local function getFirstName(colonist: Colonist): string
	return string.match(colonist.Name, "^(%S+)") or colonist.Name
end

local function getSurname(colonist: Colonist): string
	return string.match(colonist.Name, "(%S+)$") or colonist.Name
end

-- "a Builder" / "an Alchemist"
local function withArticle(word: string): string
	local article = if string.match(word, "^[AEIOUaeiou]") then "an" else "a"
	return `{article} {word}`
end

local function createColony(player: Player, data: ColonyData): Colony
	Population.Migrate(data)
	local context: Context = {
		Player = player,
		Data = data,
		Grid = Navigation.GetGrid(data, nil),
		Random = Random.new(),
		ChangedMotions = {},
		SyncColony = function()
			ColonyController.Sync(player)
		end,
		CompleteWorkOrder = function(orderId)
			ColonyController.CompleteWorkOrder(player, orderId)
		end,
		Log = function(text)
			log(player, text)
		end,
	}
	return {
		Context = context,
		Agents = {},
		NextArrival = workspace:GetServerTimeNow() + ColonistData.ARRIVAL_INTERVAL,
		NextAssign = 0,
		NextState = 0,
	}
end

local function getState(colony: Colony): ColonistTypes.ColonistsState
	local context = colony.Context
	local status = {}
	for id, agent in colony.Agents do
		status[tostring(id)] = agent.Status
	end
	return {
		Colonists = context.Data.Colonists,
		Departed = context.Data.Departed,
		Funeral = context.Funeral,
		Disease = context.Data.Disease,
		Status = status,
	}
end

local function getMotions(colony: Colony): { ColonistTypes.Motion }
	local motions = {}
	for _, agent in colony.Agents do
		table.insert(motions, agent.Motion)
	end
	return motions
end

-- Adds agents for new colonists and drops ones that died or left
local function syncAgents(colony: Colony, now: number)
	local context = colony.Context
	local alive: { [number]: boolean } = {}
	for _, colonist in context.Data.Colonists do
		alive[colonist.Id] = true
		if not colony.Agents[colonist.Id] then
			local agent = Agent.new(colonist, context, getSpawn(context, colonist), now)
			colony.Agents[colonist.Id] = agent
			context.ChangedMotions[colonist.Id] = agent.Motion
		end
	end
	for id, agent in colony.Agents do
		if not alive[id] then
			Brain.Forget(agent)
			colony.Agents[id] = nil
		end
	end
end

local function startFuneral(colony: Colony, colonist: Colonist, now: number)
	local data = colony.Context.Data
	local site = getBuilt(data, "Graveyard")
		or getBuilt(data, "TownHall")
		or getSaved(data, "Spire")
	colony.Context.Funeral = {
		Name = colonist.Name,
		Until = now + ColonistData.FUNERAL_TIME,
		Position = (site and Navigation.GetDoor(site)) or Vector3.zero,
	}
end

local function onDeath(colony: Colony, colonist: Colonist, now: number)
	local context = colony.Context
	local data = context.Data
	local days = ColonistData.MOURNING_DAYS * DayCycle.DAY_LENGTH
	for _, member in Population.GetImmediateFamily(data, colonist) do
		Needs.AddModifier(member, MOURNING_ID, ColonistData.MOURNING_HAPPINESS, days, now)
	end
	local mail = Population.Remove(data, colonist, "Died")
	startFuneral(colony, colonist, now)
	context.Log(`{colonist.Name} died. Everyone is attending the funeral.`)
	Notifications.Send(context.Player, "Death", `{colonist.Name} died`)
	if mail then
		Mailbox.Notify(context.Player, mail)
	end
end

-- Morning rolls: sickness, Fight or Flight, growing up, marriages and births.
-- Future colony events (raids, weather, disease outbreaks) should roll here too and announce
-- themselves with Notifications.Send(context.Player, "ColonyEvent", text).
local function runDay(colony: Colony, day: number)
	local context = colony.Context
	local data = context.Data
	local random = context.Random

	data.Disease = math.max(data.Disease - ColonistData.DISEASE_DECAY_PER_DAY, 0)
	for _, colonist in data.Colonists do
		colonist.Sick = nil
	end
	if #data.Colonists > 0 and random:NextNumber() * 100 < data.Disease then
		local patient = data.Colonists[random:NextInteger(1, #data.Colonists)]
		patient.Sick = true
		context.Log(`{patient.Name} fell sick`)
	end

	for _, colonist in table.clone(data.Colonists) do
		local debuff = Needs.RollDebuff(colonist, random)
		if debuff == "Fight" then
			colonist.Debuff = "Fight"
			context.Log(`{colonist.Name} is miserable and refuses to work (Fight)`)
		elseif debuff == "Flight" then
			colonist.Debuff = "Flight"
			colonist.Leaving = true
			local family = Population.GetImmediateFamily(data, colonist)
			for _, member in family do
				member.Leaving = true
			end
			local suffix = if #family > 0 then ` with {#family} family member(s)` else ""
			context.Log(`{colonist.Name} is miserable and is leaving the colony{suffix} (Flight)`)

			-- One toast per departing family, naming everyone who goes
			if #family > 0 then
				local names = { getFirstName(colonist) }
				for _, member in family do
					table.insert(names, getFirstName(member))
				end
				Notifications.Send(
					context.Player,
					"Leave",
					`The {getSurname(colonist)} family is leaving the colony ({table.concat(
						names,
						", "
					)})`
				)
			else
				Notifications.Send(context.Player, "Leave", `{colonist.Name} is leaving the colony`)
			end
		end
	end

	for _, colonist in Population.GrowUp(data, day) do
		context.Log(`{colonist.Name} has grown up`)
	end
	if random:NextNumber() < ColonistData.MARRIAGE_CHANCE then
		local a, b = Population.TryMarry(data, random)
		if a and b then
			context.Log(`{a.Name} and {b.Name} got married`)
		end
	end
	for _, child in Population.TryBirths(data, day, random) do
		context.Log(`{child.Name} was born`)
		local parentNames = {}
		for _, parentId in child.Family.Parents do
			local parent = Population.Get(data, parentId)
			if parent then
				table.insert(parentNames, getFirstName(parent))
			end
		end
		local parents = if #parentNames > 0 then table.concat(parentNames, " and ") else "A couple"
		Notifications.Send(context.Player, "Birth", `{parents} had a child: {getFirstName(child)}`)
	end
end

local function updateColony(colony: Colony, deltaTime: number, now: number)
	local context = colony.Context
	local data = context.Data
	context.Grid = Navigation.GetGrid(data, context.Grid)

	-- Days pass and colonists arrive from the start, before any building exists
	local day = DayCycle.GetDay(now)
	if data.LastDay < day then
		if data.LastDay >= 0 then
			runDay(colony, day)
		end
		data.LastDay = day
	end

	-- A new colony's first colonists appear at once, standing around the Spire (saves that
	-- already have colonists have moved NextColonistId past 1, so none are added twice). More
	-- come while there's room: up to STARTING_COLONISTS without beds, then one per free bed.
	if data.NextColonistId == 1 then
		for _ = 1, Population.STARTING_COLONISTS do
			Population.Create(data, day, context.Random)
		end
		context.Log(`{Population.STARTING_COLONISTS} colonists have arrived at the Spire`)
		Notifications.Send(
			context.Player,
			"Join",
			`{Population.STARTING_COLONISTS} colonists joined {getColonyName(data)}`
		)
	elseif now >= colony.NextArrival then
		colony.NextArrival = now + ColonistData.ARRIVAL_INTERVAL
		if #data.Colonists < Population.GetCapacity(data) then
			local colonist = Population.Create(data, day, context.Random)
			context.Log(`{colonist.Name} has joined the colony`)
			Notifications.Send(
				context.Player,
				"Join",
				`{colonist.Name} joined {getColonyName(data)}`
			)
		end
	end

	if now >= colony.NextAssign then
		colony.NextAssign = now + ASSIGN_INTERVAL
		Population.AssignHomes(data)
		for _, colonist in Population.AssignJobs(data) do
			local text = `{colonist.Name} is now {withArticle(colonist.Job or "worker")}`
			context.Log(text)
			Notifications.Send(context.Player, "Job", text)
		end
	end

	if context.Funeral and now >= context.Funeral.Until then
		context.Funeral = nil
	end

	syncAgents(colony, now)

	for id, agent in colony.Agents do
		if Needs.Update(data, agent.Colonist, deltaTime, now) then
			onDeath(colony, agent.Colonist, now)
			continue
		end
		Brain.Step(agent, now)
		-- Bedtime (or leaving, a funeral...) ends a conversation
		local talker = agent.TalkingTo
		if talker and agent.Blackboard.Mode ~= "Talk" then
			agent.TalkingTo = nil
			Net:RemoteEvent("ColonistTalkEnded")
				:FireClient(talker, agent.Colonist.Id, `{agent.Colonist.Name} has to go to bed`)
		end
	end

	-- Systems stepping with the colonists (raids); one failing doesn't stop the colony's tick
	for _, hook in stepHooks do
		local ok, err = pcall(function()
			hook(context.Player, context, colony.Agents, deltaTime, now)
		end)
		if not ok then
			warn(`[Colonists] {context.Player.Name} step hook: {err}`)
		end
	end

	-- Agents may have died or left during the step
	syncAgents(colony, now)

	if next(context.ChangedMotions) then
		local motions = {}
		for _, motion in context.ChangedMotions do
			table.insert(motions, motion)
		end
		table.clear(context.ChangedMotions)
		Net:RemoteEvent("ColonistMotions"):FireClient(context.Player, motions)
	end

	if now >= colony.NextState then
		colony.NextState = now + STATE_INTERVAL
		Net:RemoteEvent("ColonistsState"):FireClient(context.Player, getState(colony))
	end
end

local function tick(deltaTime: number)
	local now = workspace:GetServerTimeNow()
	local loaded: { [Player]: boolean } = {}

	for _, player in ColonyController.GetLoadedPlayers() do
		loaded[player] = true
		local data = ColonyController.GetData(player)
		if not data then
			continue
		end
		local existing = colonies[player]
		local colony: Colony = if existing and existing.Context.Data == data
			then existing
			else createColony(player, data)
		colonies[player] = colony
		local ok, err = pcall(function()
			updateColony(colony, deltaTime, now)
		end)
		if not ok then
			warn(`[Colonists] {player.Name}: {err}`)
		end
	end

	for player, colony in colonies do
		if not loaded[player] then
			for _, agent in colony.Agents do
				Brain.Forget(agent)
			end
			colonies[player] = nil
		end
	end
end

-- The colony and agent a player is standing next to, or an error message
local function getNearAgent(player: Player, id: unknown): (Colony?, Agent?, string)
	local colony = colonies[player]
	local agent = if colony and typeof(id) == "number" then colony.Agents[id] else nil
	if not colony or not agent then
		return nil, nil, "Colonist not found"
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local position = PlotData.SURFACE * Agent.GetPosition(agent, workspace:GetServerTimeNow())
	if
		not root
		or not root:IsA("BasePart")
		or (root.Position - position).Magnitude > INTERACT_REACH
	then
		return nil, nil, "Too far away"
	end
	return colony, agent, ""
end

-- "Wake up" in the colonist's menu: it gets up, loses happiness and eats double until the next night
local function onWake(player: Player, id: unknown): (boolean, string)
	local colony = colonies[player]
	local agent = if colony and typeof(id) == "number" then colony.Agents[id] else nil
	if not colony or not agent then
		return false, "Colonist not found"
	end
	local now = workspace:GetServerTimeNow()

	local colonist = agent.Colonist
	-- Asleep, or on the way to bed
	if agent.Blackboard.Mode == "Sleep" then
		agent.AwakeUntil = now + ColonistData.WOKEN_AWAKE_TIME
		colonist.WokenDay = DayCycle.GetDay(now)
		Needs.AddModifier(colonist, "Woken", ColonistData.WOKEN_HAPPINESS, DayCycle.DAY_LENGTH, now)
		colonist.Happiness = Needs.GetHappiness(colony.Context.Data, colonist, now)
		agent.Status = "Woken up (grumpy)"
		return true,
			`You woke {colonist.Name}. They're unhappy and will eat twice as much tomorrow.`
	end
	return false, `{colonist.Name} isn't asleep`
end

-- What a colonist accepts from the player: Food up to FOOD_CARRY, plus a Builder's missing
-- materials or a Farmer's seeds
local function getWanted(agent: Agent): { [string]: number }
	local wanted: { [string]: number } = {}
	if agent.Colonist.Job == "Builder" then
		wanted = Builder.GetWanted(agent)
	elseif agent.Colonist.Job == "Farmer" then
		wanted = Farmer.GetWanted(agent)
	end
	local food = ItemsList.GetItemByItemType("Food")
	if food then
		local carried = Bag.CountItem(agent.Colonist.Carried, food.UniqueID)
		local room = ColonistData.FOOD_CARRY - carried
		if room > 0 then
			wanted.Food = (wanted.Food or 0) + room
		end
	end
	return wanted
end

-- Hands a colonist Food (and a Builder its materials, a Farmer his seeds) from the player's backpack
local function onGive(player: Player, id: unknown): (boolean, string)
	local colony, agent, err = getNearAgent(player, id)
	if not colony or not agent then
		return false, err
	end
	local colonist = agent.Colonist
	local backpack = InventoryController.GetBackpack(colony.Context.Data)
	if not backpack then
		return false, "No backpack"
	end

	local given = {}
	for itemType, amount in getWanted(agent) do
		local item = ItemsList.GetItemByItemType(itemType)
		if not item then
			continue
		end
		local itemId = item.UniqueID
		local count = math.min(
			amount,
			Bag.CountItem(backpack, itemId),
			Bag.GetSpaceFor(colonist.Carried, itemId)
		)
		if count > 0 then
			local removed = Bag.RemoveItem(backpack, itemId, count)
			local left = Bag.AddItem(colonist.Carried, itemId, removed)
			if left > 0 then
				-- Anything that won't fit back in the backpack is mailed
				local lost = Bag.AddItem(backpack, itemId, left)
				if lost > 0 then
					Mailbox.Notify(
						player,
						Mailbox.Send(colony.Context.Data, {
							From = "Lost & Found",
							Title = "Backpack full - sent to your mailbox",
							Items = { { UniqueID = itemId, Quantity = lost } },
						})
					)
				end
			end
			if removed - left > 0 then
				table.insert(given, `{removed - left} {itemType}`)
			end
		end
	end

	if #given == 0 then
		local full = #colonist.Carried.Items >= Bag.GetSlotsCount(colonist.Carried)
		return false,
			if full then `{colonist.Name}'s inventory is full` else "You have nothing they need"
	end
	table.sort(given)
	colony.Context.SyncColony()
	local text = `Gave {colonist.Name} {table.concat(given, ", ")}`
	colony.Context.Log(text)
	return true, text
end

-- A colonist's pack for MoveItems, only while the player stands next to them
local function resolveCarried(player: Player, id: string?): (InventoryTypes.Bag?, string)
	local _, agent, err = getNearAgent(player, if id then tonumber(id) else nil)
	return if agent then agent.Colonist.Carried else nil, err
end

-- Sends the colonists right away instead of waiting for the next state tick
local function syncColonists(player: Player)
	local colony = colonies[player]
	if colony then
		Net:RemoteEvent("ColonistsState"):FireClient(player, getState(colony))
	end
end

ColonistController.SyncColonists = syncColonists

-- Runs `hook` every tick for each loaded colony, right after its colonists' AI stepped.
-- Lets later systems (RaidController) act on the same agents without a require cycle.
function ColonistController.OnStep(hook: StepHook)
	table.insert(stepHooks, hook)
end

-- Kills a colonist through the usual death path (belongings mailed, funeral, Death toast).
-- Returns false when the player has no such colonist.
function ColonistController.Kill(player: Player, id: number): boolean
	local colony = colonies[player]
	local agent = colony and colony.Agents[id]
	if not colony or not agent or not Population.Get(colony.Context.Data, id) then
		return false
	end
	agent.Colonist.Health = 0
	onDeath(colony, agent.Colonist, workspace:GetServerTimeNow())
	return true
end

-- Starts a conversation: the colonist stops where it is until EndTalk. Sleeping colonists
-- must be woken first.
function ColonistController.StartTalk(player: Player, id: unknown): (boolean, string)
	local colony, agent, err = getNearAgent(player, id)
	if not colony or not agent then
		return false, err
	end
	if agent.TalkingTo == player then
		return true, ""
	end
	local mode = Brain.GetMode(agent, workspace:GetServerTimeNow())
	if mode == "Sleep" then
		local state = if agent.Motion.Action == "Sleep" then "asleep" else "going to bed"
		return false, `{agent.Colonist.Name} is {state}. Wake them up first.`
	elseif mode == "Defend" then
		return false, `{agent.Colonist.Name} is busy fighting off the raid`
	elseif mode == "Leave" or mode == "Funeral" then
		return false, `{agent.Colonist.Name} can't talk right now`
	end
	-- One conversation at a time
	for _, other in colony.Agents do
		if other.TalkingTo == player then
			other.TalkingTo = nil
		end
	end
	agent.TalkingTo = player
	return true, ""
end

-- The player is in a conversation with this colonist (it's awake and hasn't walked off to bed)
function ColonistController.IsTalking(player: Player, id: unknown): boolean
	local colony = colonies[player]
	local agent = if colony and typeof(id) == "number" then colony.Agents[id] else nil
	return agent ~= nil and agent.TalkingTo == player
end

function ColonistController.EndTalk(player: Player, id: unknown)
	local colony = colonies[player]
	local agent = if colony and typeof(id) == "number" then colony.Agents[id] else nil
	if agent and agent.TalkingTo == player then
		agent.TalkingTo = nil
	end
end

function ColonistController.Start()
	if started then
		return
	end
	started = true

	Net:RemoteEvent("ColonistsState")
	Net:RemoteEvent("ColonistMotions")
	Net:RemoteEvent("ColonistTalkEnded")
	Net:Handle("GetColonists", function(player: Player): any
		local colony = colonies[player]
		if not colony then
			return nil
		end
		return { State = getState(colony), Motions = getMotions(colony) }
	end)
	Net:Handle("WakeColonist", onWake)
	Net:Handle("GiveColonist", onGive)
	InventoryController.RegisterBag("Colonist", { Resolve = resolveCarried, Sync = syncColonists })

	Players.PlayerRemoving:Connect(function(player)
		local colony = colonies[player]
		if colony then
			for _, agent in colony.Agents do
				Brain.Forget(agent)
			end
			colonies[player] = nil
		end
	end)

	task.spawn(function()
		local last = workspace:GetServerTimeNow()
		while true do
			task.wait(TICK)
			local now = workspace:GetServerTimeNow()
			tick(now - last)
			last = now
		end
	end)
end

return ColonistController
